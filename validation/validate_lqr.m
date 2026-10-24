function V = validate_lqr(plotMode)
%VALIDATE_LQR  Discrete LQR regulator: gain vs an independent dlqr and the analytic
%              Riccati solution, closed-loop stability, and regulation to zero.
%
%   COMPONENT      DHS.controllers.LQR(A, B, Q, R, Ts)
%                  -- discretises the continuous model at Ts (zero-order hold),
%                  solves the discrete LQR (dlqr) and applies  u = -K x.
%
%   TEST CASE + REFERENCE
%     (1) GAIN.  Two checks:
%       (1a) the class's K equals an INDEPENDENT reproduction of its own
%            construction (c2d at Ts -> dlqr);
%       (1b) for the continuous double integrator  A = [0 1; 0 0], B = [0; 1]
%            (a mass with force input) with Q = diag(q, 0), R = r, the
%            infinite-horizon LQR gain has the CLOSED FORM:
%                K = [ sqrt(q/r) ,  sqrt( 2 sqrt(q/r) ) ]
%            A continuous-cost-consistent discrete design (Qd = Q*Ts, Rd = R*Ts)
%            at small Ts must converge to this K -- this confirms dlqr/c2d
%            actually return the CARE solution the class relies on.
%     (2) STABILITY.  All poles of the closed-loop discrete system Ad - Bd K are
%         strictly inside the unit circle.
%     (3) REGULATION.  Closing the class around the exact discrete model of a
%         2-state RC zone reproduces the closed-form recursion
%         x_{k+1} = (Ad - Bd K) x_k to rounding, and the state decays to zero.
%
%   WHY THIS TEST IS GOOD
%     (1) proves the Riccati / dlqr call and the c2d discretisation are wired
%     correctly (a wrong sign, wrong Q/R placement, or a transpose slip changes
%     the gain); (2) proves the design is actually stabilising; (3) proves the
%     update law applies that gain to the state it is given, with the right sign.
%
%   EXPECTED OUTPUT
%     class K == independent dlqr to 1e-10;  |K - analytic K| < 2 % (small Ts);
%     max |closed-loop pole| < 1;  closed-loop trajectory == recursion to 1e-9;
%     final state below 1e-3 of the initial one.
%
%   Run:  >> V = validate_lqr
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));

    % ---- (1) double-integrator gain ----
    A = [0 1; 0 0];  B = [0; 1];  q = 1;  r = 1e-2;
    Kan = [sqrt(q/r), sqrt(2*sqrt(q/r))];
    Ts = 0.02;
    c = DHS.controllers.LQR(A, B, diag([q q]), r, Ts);

    % (1a) independent reproduction of the class's own construction
    sd = c2d(ss(A, B, eye(2), 0), Ts, 'zoh');
    Kd = dlqr(sd.A, sd.B, diag([q q]), r);
    eGain = max(abs(c.K - Kd));

    % (1b) continuous-cost-consistent discrete LQR -> analytic CARE gain as Ts->0
    Tsc = 1e-3;
    cc  = DHS.controllers.LQR(A, B, diag([q 0])*Tsc, r*Tsc, Tsc);
    eKan = max(abs(cc.K - Kan) ./ abs(Kan));

    % ---- (2) closed-loop stability of the discrete system ----
    Acl = sd.A - sd.B*c.K;
    specR = max(abs(eig(Acl)));

    % ---- (3) regulation on a 2-state RC zone (deviation coordinates) ----
    Cair = 2e6; Cw = 1.5e7; Rw = 3.0; Rwin = 0.6;
    gh = 1/(Rw/2); gwin = 1/Rwin;
    Az = [ -(gh+gwin)/Cair,  gh/Cair ;  gh/Cw, -(2*gh)/Cw ];
    Bz = [ 1/Cair ; 0 ];                 % heat into the air node
    dt = 60;
    cz = DHS.controllers.LQR(Az, Bz, [5e3 1], 1e-9, dt);
    cz.uMin = -Inf;  cz.uMax = Inf;      % unsaturated, so the recursion is exact
    cz.state = @(s) s.x;                 % here the "simulation" is a struct holding the state
    sdz = c2d(ss(Az, Bz, eye(2), 0), dt, 'zoh');
    Aclz = sdz.A - sdz.B*cz.K;
    N = 600;  x = [-3; 0];  xr = x;  Xtr = zeros(1,N);  eRec = 0;
    for k = 1:N
        u  = cz.update(struct('x', x), dt);
        x  = sdz.A*x + sdz.B*u;                      % the exact discrete plant
        xr = Aclz*xr;                                % the closed-form recursion
        eRec = max(eRec, norm(x - xr)/norm([-3; 0]));
        Xtr(k) = x(1);
    end
    eReg = norm(x)/norm([-3; 0]);

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(1) = mk('(1a) class K == independent c2d + dlqr',               0, eGain, 1e-9, 'abs');
    C(2) = mk('(1b) discrete LQR -> analytic CARE gain as Ts->0',     0, eKan, 0.02, 'abs');
    C(3) = mk('(2)  max |closed-loop discrete pole| < 1',             0, max(0, specR - 1 + 1e-6), 1e-6, 'abs');
    C(4) = mk('(3)  closed loop == recursion (Ad - Bd K)^k x0',       0, eRec, 1e-9, 'abs');
    C(5) = mk('(3)  regulation: final |x| / initial |x|',             0, eReg, 1e-3, 'abs');
    V.name = 'LQR regulator: gain vs dlqr/CARE, stability, regulation to zero';
    V.passed = vtable(V.name, C);
    V.cases = C;  V.detail = struct('eGain',eGain,'eKan',eKan,'specR',specR,'eRec',eRec,'eReg',eReg,'K',c.K,'Kan',Kan);

    th = (1:N)*dt/3600;
    vplot(mfilename, { ...
        struct('title','LQR regulation of a two-state RC zone', 'xlabel','time  [h]', 'ylabel','air-node deviation  [K]', ...
            'legendLoc','southeast', ...
            'series',{{ struct('x',th,'y',0*th,'name','target','style','ref'), ...
                        struct('x',th,'y',Xtr,'name','LQR','style','sim') }}) }, plotMode);
end

function s = mk(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
