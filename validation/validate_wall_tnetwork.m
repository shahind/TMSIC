function V = validate_wall_tnetwork(plotMode)
%VALIDATE_WALL_TNETWORK  3R2C single-layer wall (RCBS.Zone.addWall) vs a
%                        high-accuracy ODE reference.
%
%   COMPONENT      RCBS.Zone.addWall(R_total, C_wall, T0, name) -- inserts the
%                  T-network  R/2 - C_wall - R/2  between the zone air node and
%                  the outdoor boundary.
%
%   TEST CASE
%     Zone air node (capacitance C_air) + one opaque wall (total resistance R_w,
%     mid-node capacitance C_w) + one window (pure conductance 1/R_win) to a
%     sinusoidally varying outdoor temperature over two days. This is a 2-state
%     linear system whose exact response is obtained by ode45 at tight
%     tolerances and by the analytic transfer function.
%
%       C_air dT_air/dt = (T_w - T_air)/(R_w/2) + (T_out - T_air)/R_win
%       C_w   dT_w /dt  = (T_air - T_w)/(R_w/2) + (T_out - T_w)/(R_w/2)
%
%   REFERENCE
%     The R/2 - C - R/2 T-network is the standard lumped model of a single
%     homogeneous wall layer. ode45 (Dormand-Prince 4(5)) at RelTol 1e-10 is the reference integrator.
%
%   WHY THIS TEST IS GOOD
%     addWall must (a) split R_total into two halves, (b) create the mid node
%     with the right capacitance, (c) connect the mid node to BOTH the air node
%     and the outdoor boundary, and (d) leave the air node otherwise untouched.
%     A wrong split (R vs R/2), a missing half-resistor, or a mid node wired to
%     the wrong neighbour all produce a visibly different 2-state response that
%     ode45 on the intended equations will not match.
%
%   EXPECTED OUTPUT
%     max |T_air,RCBS - T_air,ode45| < 0.03 degC over 2 days at dt = 30 s;
%     the wall mid-node temperature agrees to the same tolerance;
%     the steady-periodic amplitude and phase lag match to < 2 %.
%
%   Run:  >> V = validate_wall_tnetwork
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));

    Cair = 2.0e6;  Cw = 2.0e7;  Rw = 2.5;  Rwin = 0.5;  T0 = 20;
    Toc  = @(s) 5 + 12*sin(2*pi*mod(s/3600,24)/24 - pi/2);      % degC, daily swing
    dt = 30;

    b = RCBS.Building();  b.addStorey('S');  b.S.addZone('Z','C_main',Cair);
    b.S.Z.nodes(1).T = T0;
    b.S.Z.addWall(Rw, Cw, T0, 'Wall');
    b.S.Z.addWindow(Rwin, 'Win');
    b.outdoorTempFunc = @(t) Toc(seconds(t - datetime(2025,1,1)));
    b.simulation.startDate = datetime(2025,1,1);  b.simulation.timeStep = seconds(dt);
    b.simulate(days(2));
    r  = b.simulation.results;
    ts = seconds(r.Time - r.Time(1));
    iAir = find(string(b.simulation.nodeNames) == "S.Z.T_main");
    iW   = find(string(b.simulation.nodeNames) == "S.Z.Wall");
    Tair = r.Tall(:, iAir);   Twall = r.Tall(:, iW);

    % reference: ode45 on the intended 2-state system
    g_half = 1/(Rw/2);  g_win = 1/Rwin;
    f = @(s,x)[ (g_half*(x(2)-x(1)) + g_win*(Toc(s)-x(1))) / Cair ;
                (g_half*(x(1)-x(2)) + g_half*(Toc(s)-x(2))) / Cw ];
    sol = ode45(f, [0 ts(end)], [T0; T0], odeset('RelTol',1e-10,'AbsTol',1e-10));
    Xref = deval(sol, ts);
    eAir  = max(abs(Tair  - Xref(1,:).'));
    eWall = max(abs(Twall - Xref(2,:).'));

    % steady-periodic amplitude of the air node over the last 24 h vs ode45
    last = ts >= ts(end) - 86400;
    ampR = (max(Tair(last))  - min(Tair(last)))/2;
    ampO = (max(Xref(1,last)) - min(Xref(1,last)))/2;

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(1) = mk('max|T_air - ode45|  over 2 days  [degC]',   0, eAir,  0.03, 'abs');
    C(2) = mk('max|T_wall_mid - ode45|          [degC]',   0, eWall, 0.03, 'abs');
    C(3) = mk('steady-periodic air amplitude  [degC]',     ampO, ampR, 0.02, 'rel');
    V.name = '3R2C wall T-network (addWall) vs ode45 reference';
    V.passed = vtable(V.name, C);
    V.cases = C;  V.detail = struct('eAir',eAir,'eWall',eWall,'ampRCBS',ampR,'ampODE',ampO);

    th = ts/3600;
    vplot(mfilename, { ...
        struct('title','Zone air temperature', 'xlabel','time  [h]', 'ylabel','temperature  [\circC]', ...
            'series',{{ struct('x',th,'y',Xref(1,:).','name','ode45','style','ref'), ...
                        struct('x',th,'y',Tair,'name','RCBS addWall','style','sim') }}), ...
        struct('title','Wall mid-layer temperature', 'xlabel','time  [h]', 'ylabel','temperature  [\circC]', ...
            'series',{{ struct('x',th,'y',Xref(2,:).','name','ode45','style','ref'), ...
                        struct('x',th,'y',Twall,'name','RCBS addWall','style','sim') }}) }, plotMode);
end

function s = mk(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
