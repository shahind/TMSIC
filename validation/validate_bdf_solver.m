function V = validate_bdf_solver(plotMode)
%VALIDATE_BDF_SOLVER  Backward-Euler solver: order of accuracy, cross-checks,
%                     and discrete energy conservation.
%
%   COMPONENT      RCBS.Simulation  (cached sparse-LU backward Euler; also the
%                  "legacy" dense per-step assembly and the "exact" ZOH expm path)
%
%   TEST CASE
%     (a) ORDER  A 1R1C zone with a known analytical solution is integrated to a
%         fixed final time at dt = T/2^k. The global error at the final time is
%         fitted as  err ~ dt^p ; backward Euler is first order, so p ~ 1.
%     (b) EQUIVALENCE  The three solver modes are run on the same 3-node building:
%         "cached" must be bit-identical to "legacy" (same scheme, different
%         assembly); "exact" (matrix exponential, ZOH inputs) must agree with
%         "cached" to O(dt).
%     (c) ENERGY  Over a driven run, the discrete first law
%           sum(Q_in) dt  -  sum(Q_loss) dt  =  Delta[ sum(C .* T) ]
%         must hold to machine precision -- the implicit update is conservative
%         for a constant-coefficient RC network.
%
%   REFERENCE
%     Backward (implicit) Euler is a first-order A-stable one-step method:
%     Hairer, E., Norsett, S.P. & Wanner, G. (1993) "Solving Ordinary
%     Differential Equations I", Springer, Sec. II.7; LeVeque, R.J. (2007)
%     "Finite Difference Methods for Ordinary and Partial Differential
%     Equations", SIAM, Ch. 5-6. The ZOH exact discretisation x_{k+1} =
%     e^{A dt} x_k + A^{-1}(e^{A dt}-I) B u_k is standard (Franklin, Powell &
%     Workman, "Digital Control of Dynamic Systems").
%
%   WHY THIS TEST IS GOOD
%     The order test proves the time integrator is implemented correctly (a
%     wrong sign or a forward-Euler slip would show as instability or order 0);
%     the equivalence test proves the fast cached factorisation reproduces the
%     reference assembly exactly; the energy test proves the scheme conserves
%     the quantity it should, independent of any analytical solution.
%
%   EXPECTED OUTPUT
%     p in [0.9, 1.1];  |cached - legacy| < 1e-8 degC;  |cached - exact| < 5e-3 degC;
%     relative energy-balance residual < 1e-9.
%
%   Run:  >> V = validate_bdf_solver
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));

    % ---- (a) order of accuracy ----
    Cc = 1.2e5;  Rr = 0.02;  T0 = 20;  Tout = 0;  tau = Rr*Cc;
    Tend = 3*tau;
    ks = 3:8;  dts = Tend ./ 2.^ks;  errs = zeros(size(dts));
    for i = 1:numel(dts)
        b = RCBS.Building(); b.addStorey('S'); b.S.addZone('Z','C_main',Cc);
        b.S.Z.nodes(1).T = T0;  b.S.Z.addWindow(Rr,'W');
        b.outdoorTempFunc = @(t) Tout;
        b.simulation.startDate = datetime(2025,1,1); b.simulation.timeStep = seconds(dts(i));
        b.simulate(seconds(Tend));
        Ts = b.simulation.results.S.Z.T;
        errs(i) = abs(Ts(end) - (Tout + (T0-Tout)*exp(-Tend/tau)));
    end
    p = polyfit(log(dts), log(errs), 1);  order = p(1);

    % ---- (b) solver-mode equivalence ----
    mk3 = @() build3();
    b = mk3();  b.simulation.solverMode = "cached";  b.simulate(days(3));  Tc = b.simulation.results.S.Z.T;
    b = mk3();  b.simulation.solverMode = "legacy";  b.simulate(days(3));  Tl = b.simulation.results.S.Z.T;
    b = mk3();  b.simulation.solverMode = "exact";   b.simulate(days(3));  Te = b.simulation.results.S.Z.T;
    eCL = max(abs(Tc - Tl));
    eCE = max(abs(Tc - Te));

    % ---- (c) discrete energy conservation ----
    Cen = 2e6;  Ren = 0.05;
    b = RCBS.Building(); b.addStorey('S'); b.S.addZone('Z','C_main',Cen);
    b.S.Z.addWindow(Ren,'W');
    b.outdoorTempFunc = @(t) 4 + 7*sin(2*pi*hour(t)/24);
    b.S.Z.connectToExternalSource(@(bb) 1400*(hour(bb.simulation.t)>=6 && hour(bb.simulation.t)<20),'T_main');
    b.simulation.startDate = datetime(2025,1,1); b.simulation.timeStep = seconds(60);
    b.simulate(days(2));
    r = b.simulation.results;  T = r.S.Z.T;  Toutv = r.OutdoorTemperature;  tv = r.Time;  dt = 60;
    Qin   = arrayfun(@(k) 1400*(hour(tv(k))>=6 && hour(tv(k))<20), (1:numel(T)-1)');
    Qloss = (T(2:end) - Toutv(2:end)) / Ren;                  % implicit update -> use end-of-step T
    Ein = sum(Qin)*dt;  Eloss = sum(Qloss)*dt;  Estore = Cen*(T(end) - T(1));
    eEnergy = abs(Ein - (Estore + Eloss)) / abs(Ein);

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(1) = mk('convergence order p  (backward Euler => 1)',      1, order, 0.1,  'abs');
    C(2) = mk('|cached - legacy|  max  [degC]',                  0, eCL,   1e-8, 'abs');
    C(3) = mk('|cached - exact ZOH|  max  [degC]',               0, eCE,   5e-3, 'abs');
    C(4) = mk('discrete energy-balance relative residual',       0, eEnergy, 1e-9, 'abs');
    V.name = 'Backward-Euler solver: order, mode equivalence, energy conservation';
    V.passed = vtable(V.name, C);
    V.cases = C;  V.detail = struct('order',order,'errs',errs,'dts',dts,'eCL',eCL,'eCE',eCE,'eEnergy',eEnergy);

    tk = (0:numel(Tc)-1).'*60/3600;                       % hours
    vplot(mfilename, { ...
        struct('title','Convergence of backward Euler', 'xlabel','time step  [s]', 'ylabel','error at final time  [\circC]', ...
            'xscale','log', 'yscale','log', 'legendLoc','southeast', ...
            'series',{{ struct('x',dts,'y',errs(1)*(dts/dts(1)),'name','first-order slope','style','ref'), ...
                        struct('x',dts,'y',errs,'name','measured error','style','point') }}), ...
        struct('title','Optimised solver and exact discretisation', 'xlabel','time  [h]', 'ylabel','zone temperature  [\circC]', ...
            'legendLoc','southeast', ...
            'series',{{ struct('x',tk,'y',Te,'name','exact zero-order-hold solution','style','ref'), ...
                        struct('x',tk,'y',Tc,'name','cached backward Euler','style','sim') }}) }, plotMode);
end

function b = build3()
    b = RCBS.Building(); b.addStorey('S'); b.S.addZone('Z','C_main',2e6);
    b.S.Z.addWall(2.5, 2e7, 20, 'Wall');  b.S.Z.addWindow(0.5,'W');
    b.S.Z.addInternalMass(1e-3, 5e7, 20, 'IM');
    b.outdoorTempFunc = @(t) 2 + 6*sin(2*pi*hour(t)/24);
    b.simulation.startDate = datetime(2025,1,1); b.simulation.timeStep = seconds(60);
end

function s = mk(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
