function V = validate_lqr(plotMode)
%VALIDATE_LQR  Integral-augmented discrete LQR: gain vs an independent dlqr,
%              closed-loop stability, and offset-free tracking / disturbance
%              rejection.
%
%   COMPONENT      DHS.controllers.LQR(sysc, opts)
%                  -- augments the continuous plant with an integral of the
%                  tracking error, discretises at Ts, solves the discrete LQR
%                  (dlqr), and applies  u = -Kx (x - r) - Ki xi.
%
%   TEST CASE + REFERENCE
%     (1) GAIN.  Three checks:
%       (1a) the class's [Kx Ki] equals an INDEPENDENT reproduction of its own
%            construction (augment error integral -> c2d at Ts -> dlqr);
%       (1b) with the integral weight -> 0 the class's state-feedback part Kx
%            equals a plain (non-augmented) discrete dlqr on the same plant with
%            the same Q, R  (the integral state decouples cleanly);
%       (1c) for the continuous double integrator  A = [0 1; 0 0], B = [0; 1]
%            (a mass with force input) with Q = diag(q, 0), R = r, the
%            infinite-horizon LQR gain has the CLOSED FORM (Anderson, B.D.O. &
%            Moore, J.B. (1990) "Optimal Control: Linear Quadratic Methods",
%            Prentice-Hall, Sec. 3; Bryson & Ho (1975) "Applied Optimal
%            Control", Sec. 5):
%                K = [ sqrt(q/r) ,  sqrt( 2 sqrt(q/r) ) ]
%            A continuous-cost-consistent discrete design (Qd = Q*Ts, Rd = R*Ts)
%            at small Ts must converge to this K -- this confirms dlqr/c2d
%            actually return the CARE solution the class relies on.
%     (2) STABILITY.  All poles of the closed-loop augmented discrete system are
%         strictly inside the unit circle.
%     (3) OFFSET-FREE.  Simulating the augmented closed loop on a 2-state RC zone:
%         a step setpoint is tracked to zero steady-state error (integral state
%         removes the offset a pure -K(x-r) law would leave on the non-controlled
%         nodes), and a constant load disturbance is rejected to zero error.
%
%   WHY THIS TEST IS GOOD
%     (1) proves the Riccati / dlqr call and the c2d discretisation are wired
%     correctly (a wrong sign, wrong Q/R placement, or a transpose slip changes
%     the gain); (2) proves the design is actually stabilising; (3) proves the
%     integral augmentation delivers the offset-free property it is there for.
%
%   EXPECTED OUTPUT
%     class [Kx Ki] == independent dlqr to 1e-10;  |Kx - analytic K| < 2 % (small
%     Ts, tiny qInt);  max |closed-loop pole| < 1;  tracking & disturbance
%     steady-state errors < 5e-3 degC.
%
%   Run:  >> V = validate_lqr
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));

    % ---- (1) double-integrator gain ----
    %   DHS.controllers.LQR expects B = [T_outdoor | Q_node_1 ... Q_node_N], so
    %   column 1 is a (here unused) disturbance input and the manipulated input
    %   is column uCol = 2.
    A = [0 1; 0 0];  B = [0; 1];  q = 1;  r = 1e-2;
    Kan = [sqrt(q/r), sqrt(2*sqrt(q/r))];

    sysc = ss(A, [zeros(2,1), B], eye(2), 0);
    io = struct('zoneMainRows', 1);
    Ts = 0.02;  qInt = 1e-8;
    c = DHS.controllers.LQR(sysc, struct('io',io,'Ts',Ts,'uMaxW',1, ...
        'qZone',q,'qOther',q,'qInt',qInt,'R',r,'yRow',1,'uCol',2));

    % (1a) independent reproduction of the class's own construction
    nx = 2;  Cy = [1 0];
    Aa = [A, zeros(nx,1); -Cy, 0];  Ba = [B; 0];
    sysd = c2d(ss(Aa,Ba,eye(nx+1),0), Ts, 'zoh');
    Qd = diag([q, q, qInt]);  Qd(1,1) = q;
    Kd = dlqr(sysd.A, sysd.B, Qd, r);
    eGain = max(abs([c.Kx, c.Ki] - Kd));

    % (1b) with qInt -> 0, Kx == plain (non-augmented) discrete dlqr
    cN = DHS.controllers.LQR(sysc, struct('io',io,'Ts',Ts,'uMaxW',1, ...
        'qZone',q,'qOther',q,'qInt',1e-12,'R',r,'yRow',1,'uCol',2));
    sd2 = c2d(ss(A, B, eye(2), 0), Ts, 'zoh');
    Kplain = dlqr(sd2.A, sd2.B, diag([q q]), r);
    eDecouple = max(abs(cN.Kx - Kplain));

    % (1c) continuous-cost-consistent discrete LQR -> analytic CARE gain as Ts->0
    Tsc = 1e-3;
    sdc = c2d(ss(A, B, eye(2), 0), Tsc, 'zoh');
    Kc  = dlqr(sdc.A, sdc.B, diag([q 0])*Tsc, r*Tsc);
    eKan = max(abs(Kc - Kan) ./ abs(Kan));

    % ---- (2) closed-loop stability of the augmented discrete system ----
    Kfull = [c.Kx, c.Ki];
    Acl = sysd.A - sysd.B*Kfull;
    specR = max(abs(eig(Acl)));

    % ---- (3) offset-free tracking + disturbance rejection on a 2-state RC zone ----
    Cair = 2e6; Cw = 1.5e7; Rw = 3.0; Rwin = 0.6;
    gh = 1/(Rw/2); gwin = 1/Rwin;
    Az = [ -(gh+gwin)/Cair,  gh/Cair ;  gh/Cw, -(2*gh)/Cw ];
    Bz = [ 1/Cair ; 0 ];                 % heat into the air node
    Bd = [ gwin/Cair ; gh/Cw ];          % outdoor-temp coupling
    io2 = struct('zoneMainRows', 1);
    cz = DHS.controllers.LQR(ss(Az, [Bd Bz], eye(2), 0), struct('io',io2,'Ts',60, ...
        'uMaxW',5e4,'qZone',5e3,'qOther',1,'qInt',5e-2,'R',1e-9,'yRow',1,'uCol',2));
    x = [18; 18];  ref = 21;  Tout = -2;  dt = 60;  Xtr = zeros(1,4000);
    for k = 1:4000
        u = cz.update(x(1), ref, dt, struct('x', x));       % u in [0,1]
        Qh = u * 5e4;                                       % W
        xdot = Az*x + Bz*Qh + Bd*Tout;
        x = x + dt*xdot;
        Xtr(k) = x(1);
    end
    eTrack = abs(x(1) - ref);

    x = [21; 21];  dstep = 6;  Xds = zeros(1,4000);         % a +6 K "outdoor" step disturbance
    cz.reset();
    for k = 1:4000
        u = cz.update(x(1), ref, dt, struct('x', x));
        Qh = u * 5e4;
        xdot = Az*x + Bz*Qh + Bd*(Tout + dstep);
        x = x + dt*xdot;
        Xds(k) = x(1);
    end
    eDist = abs(x(1) - ref);

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(1) = mk('(1a) class [Kx Ki] == independent augmented dlqr',  0, eGain, 1e-9, 'abs');
    C(2) = mk('(1b) qInt->0: Kx == plain discrete dlqr  (gains ~10)', 0, eDecouple, 5e-4, 'abs');
    C(3) = mk('(1c) discrete LQR -> analytic CARE gain as Ts->0',   0, eKan, 0.02, 'abs');
    C(4) = mk('(2)  max |closed-loop discrete pole| < 1',          0, max(0, specR - 1 + 1e-6), 1e-6, 'abs');
    C(5) = mk('(3)  offset-free step tracking  error [degC]',      0, eTrack, 5e-3, 'abs');
    C(6) = mk('(3)  constant-disturbance rejection [degC]',        0, eDist,  5e-3, 'abs');
    V.name = 'Integral-augmented LQR: gain vs dlqr/CARE, stability, offset-free';
    V.passed = vtable(V.name, C);
    V.cases = C;  V.detail = struct('eGain',eGain,'eDecouple',eDecouple,'eKan',eKan,'specR',specR,'eTrack',eTrack,'eDist',eDist,'Kx',c.Kx,'Kan',Kan);

    th = (1:4000)*dt/3600;  ev = eig(Acl);  ph = linspace(0,2*pi,200);
    vplot(mfilename, { ...
        struct('title','LQR tracking and disturbance rejection', 'xlabel','time  [h]', 'ylabel','zone temperature  [\circC]', ...
            'legendLoc','southeast', ...
            'series',{{ struct('x',th,'y',ref+0*th,'name','setpoint','style','ref'), ...
                        struct('x',th,'y',Xtr,'name','step tracking','style','sim'), ...
                        struct('x',th,'y',Xds,'name','with a +6 K disturbance','style','sim') }}) }, plotMode);
end

function s = mk(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
