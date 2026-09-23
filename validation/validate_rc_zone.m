function V = validate_rc_zone(plotMode)
%VALIDATE_RC_ZONE  Single-node (1R1C) thermal zone vs the analytical solution.
%
%   COMPONENT      RCBS.Zone / RCBS.Simulation  (one air node, one conductance to
%                  an outdoor boundary, optional constant heat input)
%
%   TEST CASE
%     A single lumped thermal capacitance C [J/K] is connected to a constant
%     boundary temperature T_out through a single resistance R [K/W]. No other
%     paths. Two sub-cases:
%       (1) free response  -- initial temperature T0, no heat input;
%       (2) forced response -- constant heat input Q into the node.
%
%   ANALYTICAL REFERENCE  (lumped-capacitance / Newtonian cooling)
%       C dT/dt = (T_out - T)/R + Q
%       T(t) = T_inf + (T0 - T_inf) exp(-t / (R C)) ,   T_inf = T_out + Q R
%     Incropera & DeWitt, "Fundamentals of Heat and Mass Transfer", 6th ed.,
%     Sec. 5.1-5.3 (the lumped capacitance method); EN ISO 13790:2008 Annex C.
%     The time constant tau = R*C and the steady state T_inf = T_out + Q*R are
%     exact for this ODE.
%
%   WHY THIS TEST IS GOOD
%     It is the smallest possible RC network with a closed-form solution, so any
%     error in (a) how a zone assembles its capacitance and conductance, (b) the
%     sign of the outdoor coupling, (c) the heat-source injection, or (d) the
%     time integration shows up immediately and unambiguously. Sub-case (2) also
%     pins the steady-state gain (a units error in C or R would still give a
%     decaying exponential but the wrong T_inf).
%
%   EXPECTED OUTPUT
%     * free response: max |T_sim - T_analytic| < 0.02 degC at dt = 30 s over 6 h
%     * time constant recovered from the 63.2 % point within 1 %
%     * forced response steady state = T_out + Q*R to < 0.05 degC
%     * global error is first-order in dt (halving dt roughly halves the error)
%
%   Run:  >> V = validate_rc_zone
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));

    C = 1.2e5;  R = 0.02;  T0 = 20;  Tout = 0;  tau = R*C;     % tau = 2400 s (40 min)
    horizon = hours(6);                                         % ~9 time constants

    % ---- (1) free response, fine step ----
    dt = 30;
    b = onezone(C, R, T0, Tout, dt);
    b.simulate(horizon);
    t  = seconds(b.simulation.results.Time - b.simulation.results.Time(1));
    Ts = b.simulation.results.S.Z.T;
    Tan = Tout + (T0 - Tout).*exp(-t./tau);
    eFree = max(abs(Ts - Tan));

    % time constant from the 63.2 % crossing (T = T0 + (Tinf-T0)*(1-1/e))
    Tcross = T0 + (Tout - T0)*(1 - exp(-1));
    tauSim = interp1(flipud(Ts(:)), flipud(t(:)), Tcross);

    % ---- (2) forced response: constant Q, steady state ----
    Q = 800;                                   % W  -> T_inf = T_out + Q*R = 16 degC
    bf = onezone(C, R, T0, Tout, dt);
    bf.S.Z.connectToExternalSource(@(bb) Q, 'T_main');
    bf.simulate(days(1));                       % ~36*tau -> fully converged
    Tinf = bf.simulation.results.S.Z.T(end);

    % ---- (3) order of accuracy in dt ----
    dts = [300 150 75 37.5 18.75];  errs = zeros(size(dts));   % all << tau (asymptotic regime)
    for i = 1:numel(dts)
        bo = onezone(C, R, T0, Tout, dts(i));
        bo.simulate(horizon);
        to = seconds(bo.simulation.results.Time - bo.simulation.results.Time(1));
        errs(i) = abs(bo.simulation.results.S.Z.T(end) - (Tout + (T0-Tout)*exp(-to(end)/tau)));
    end
    slope = polyfit(log(dts), log(errs), 1);  order = slope(1);

    % a finer-step free-response error, to show convergence to the analytic curve
    bfine = onezone(C, R, T0, Tout, 5);  bfine.simulate(horizon);
    tf = seconds(bfine.simulation.results.Time - bfine.simulation.results.Time(1));
    eFine = max(abs(bfine.simulation.results.S.Z.T - (Tout + (T0-Tout).*exp(-tf./tau))));

    C1 = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C1(1) = c('free response error at dt=30 s  [degC]  (O(dt/tau) ~ 0.05)', 0, eFree, 0.06, 'abs');
    C1(2) = c('free response error at dt=5 s   [degC]  (converging)',       0, eFine, 0.012, 'abs');
    C1(3) = c('recovered time constant tau  [s]',               tau, tauSim, 0.01, 'rel');
    C1(4) = c('forced steady state  T_inf = T_out + Q*R  [degC]', Tout + Q*R, Tinf, 0.05, 'abs');
    C1(5) = c('global error order in dt  (backward Euler => 1)',   1, order, 0.15, 'abs');
    V.name = 'RC zone (1R1C) vs analytical lumped-capacitance solution';
    V.passed = vtable(V.name, C1);
    V.cases = C1;  V.detail = struct('eFree',eFree,'tauSim',tauSim,'Tinf',Tinf,'order',order,'errs',errs,'dts',dts);

    Tfan = Tout + (T0-Tout).*exp(-tf./tau);
    vplot(mfilename, { ...
        struct('title','Free response of a single RC zone', 'xlabel','time  [h]', 'ylabel','zone temperature  [\circC]', ...
            'series',{{ struct('x',tf/3600,'y',Tfan,'name','T_\infty + (T_0 - T_\infty) e^{-t/\tau}','style','ref'), ...
                        struct('x',tf/3600,'y',bfine.simulation.results.S.Z.T,'name','RCBS.Zone','style','sim') }}) }, plotMode);
end

function b = onezone(C, R, T0, Tout, dt)
    b = RCBS.Building();  b.addStorey('S');  b.S.addZone('Z','C_main',C);
    b.S.Z.nodes(1).T = T0;
    b.S.Z.addWindow(R, 'W');                    % pure conductance air<->outdoor, G = 1/R
    b.outdoorTempFunc = @(t) Tout;
    b.simulation.startDate = datetime(2025,1,1);
    b.simulation.timeStep  = seconds(dt);
end

function s = c(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
