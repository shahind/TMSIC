function tests = test_rcbs_core
%TEST_RCBS_CORE  Validation of the RCBS RC solver and the Part-A bug fixes.
%
%   Run:  >> runtests('tests/test_rcbs_core.m')
%
%   Covers (see docs/RCBS_validation.md):
%     - addZone('C_main',..) actually sets the node capacitance      (bug #1)
%     - 1R1C step response matches the analytic solution and is 1st-order
%     - wall T-network matches a high-accuracy ode45 reference
%     - implicit solver conserves energy to machine precision
%     - cached-factorisation solver == legacy dense assembly
%     - "exact" ZOH solver agrees with backward Euler to O(dt)
%     - heat-source closures / getMainTemp see LIVE temperature       (bug #2)
%     - controlFcn / stepCallback / actuator registry work            (new)
%     - getStateSpace returns a stable, correctly-sized model
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    here = fileparts(fileparts(mfilename('fullpath')));
    addpath(here);
    tc.TestData.here = here;
end

function b = mk1R1C(C, R, T0, Tout, dt)
    b = RCBS.Building(); b.addStorey('S'); b.S.addZone('Z','C_main',C);
    b.S.Z.nodes(1).T = T0;
    b.S.Z.addWindow(R,'W');
    b.outdoorTempFunc = @(t) Tout;
    b.simulation.startDate = datetime(2025,1,1);
    b.simulation.timeStep  = seconds(dt);
end

function test_cmain_applied(tc)
    b = RCBS.Building(); b.addStorey('S'); b.S.addZone('Z','C_main',2.7e6);
    [~,ni] = b.simulation.buildNodeMap();
    verifyEqual(tc, ni{1}.C, 2.7e6, 'AbsTol', 1e-6);
    b.S.Z.C_main = 4.1e6;                       % later assignment must also propagate
    [~,ni] = b.simulation.buildNodeMap();
    verifyEqual(tc, ni{1}.C, 4.1e6, 'AbsTol', 1e-6);
end

function test_1R1C_analytic(tc)
    C = 2e6; R = 0.5; T0 = 20; Tout = 0; tau = R*C;
    errPrev = inf;
    for dt = [600 150 40 10]
        b = mk1R1C(C,R,T0,Tout,dt);
        b.simulate(hours(6));
        T  = b.simulation.results.S.Z.T;
        tt = seconds(b.simulation.results.Time - b.simulation.results.Time(1));
        Tan = Tout + (T0-Tout)*exp(-tt/tau);
        e = max(abs(T - Tan));
        verifyLessThan(tc, e, 0.02);            % small at all dt
        verifyLessThan(tc, e, errPrev*1.05);    % monotone decreasing (1st order)
        errPrev = e;
    end
    verifyLessThan(tc, errPrev, 1e-3);          % converged
end

function test_wall_Tnetwork_vs_ode45(tc)
    Cm=2e6; Cw=2e7; Rw=2.5; Rwin=0.5; T0=20;
    b = RCBS.Building(); b.addStorey('S'); b.S.addZone('Z','C_main',Cm);
    b.S.Z.nodes(1).T = T0;
    b.S.Z.addWall(Rw,Cw,T0,'Wall'); b.S.Z.addWindow(Rwin,'W');
    b.outdoorTempFunc = @(t) 10*sin(2*pi*hour(t)/24);
    b.simulation.startDate = datetime(2025,1,1); b.simulation.timeStep = seconds(30);
    b.simulate(days(1));
    res = b.simulation.results; Tm = res.S.Z.T;
    ts  = seconds(res.Time - res.Time(1));
    g1 = 1/(Rw/2); g2 = 1/(Rw/2); gw = 1/Rwin;
    Toc = @(s) 10*sin(2*pi*mod(s/3600,24)/24);
    f  = @(s,x)[ (g1*(x(2)-x(1)) + gw*(Toc(s)-x(1)))/Cm ;
                 (g1*(x(1)-x(2)) + g2*(Toc(s)-x(2)))/Cw ];
    sol = ode45(f,[0 86400],[T0;T0]);
    Tref = deval(sol, ts, 1).';
    verifyLessThan(tc, max(abs(Tm - Tref)), 0.05);
end

function test_energy_balance(tc)
    C = 2e6; R = 0.5;
    b = RCBS.Building(); b.addStorey('S'); b.S.addZone('Z','C_main',C);
    b.S.Z.addWindow(R,'W');
    b.outdoorTempFunc = @(t) 5 + 8*sin(2*pi*hour(t)/24);
    b.S.Z.connectToExternalSource(@(bb) 1500*(hour(bb.simulation.t)>=6 && hour(bb.simulation.t)<20),'T_main');
    b.simulation.startDate = datetime(2025,1,1); b.simulation.timeStep = seconds(60);
    b.simulate(days(2));
    res = b.simulation.results; T = res.S.Z.T; Tout = res.OutdoorTemperature; dt = 60; tv = res.Time;
    Qin   = arrayfun(@(k) 1500*(hour(tv(k))>=6 && hour(tv(k))<20), (1:numel(T)-1)');
    Qloss = (T(2:end)-Tout(2:end))/R;
    Ein = sum(Qin)*dt; Eloss = sum(Qloss)*dt; Estore = C*(T(end)-T(1));
    verifyLessThan(tc, abs(Ein-(Estore+Eloss))/abs(Ein), 1e-9);
end

function test_interzone_capacitive_element(tc)
    % connectToZone(other, R, name, C_mid, T0) builds an R/2 - C - R/2 T-network
    % (partition wall / floor slab) between two zone air nodes, with a mid mass.
    Ca = 2e6; Cb = 2e6; Rext = 0.05; Rslab = 0.04; Cslab = 6e6; T0 = 20;
    b = RCBS.Building();
    b.addStorey('L'); b.addStorey('U');
    b.L.addZone('Z','C_main',Ca);  b.L.Z.nodes(1).T = T0;  b.L.Z.addWindow(Rext,'W');
    b.U.addZone('Z','C_main',Cb);  b.U.Z.nodes(1).T = T0;  b.U.Z.addWindow(Rext,'W');
    b.L.Z.connectToZone(b.U.Z, Rslab, 'slab', Cslab, T0);     % capacitive slab
    b.outdoorTempFunc = @(t) 0;
    b.simulation.startDate = datetime(2025,1,1);  b.simulation.timeStep = seconds(30);
    b.simulation.buildLinear();

    % the slab added exactly one mid node (with capacitance) to the network
    nn = string(b.simulation.nodeNames);
    verifyEqual(tc, numel(nn), 3);                            % L.Z.T_main, L.Z.slab_c, U.Z.T_main
    verifyTrue(tc, any(nn == "L.Z.slab_c"));

    % heat the lower zone; the upper zone must warm through the slab (with no
    % slab it would sit near the 0 degC outdoor boundary)
    b.L.Z.connectToExternalSource(@(bb) 3000, 'T_main');
    b.simulate(days(3));
    r = b.simulation.results;
    verifyGreaterThan(tc, r.L.Z.T(end), r.U.Z.T(end));        % heated zone warmer
    verifyGreaterThan(tc, r.U.Z.T(end), 25);                  % coupling transmits heat

    % whole-network energy balance:  E_in = dStore + E_loss_to_outdoor
    T   = r.Tall;                                             % (nt x 3)
    tv  = r.Time;  dt = 30;
    Cvec = [Ca; Cslab; Cb];
    Qin   = 3000 * ones(numel(tv)-1, 1);
    % loss to outdoor is through the two windows only (mid node has no outdoor path)
    iL = find(nn=="L.Z.T_main"); iU = find(nn=="U.Z.T_main");
    Qloss = (T(2:end,iL) + T(2:end,iU)) / Rext;               % Tout = 0
    Ein = sum(Qin)*dt;  Eloss = sum(Qloss)*dt;
    Estore = sum(Cvec' .* (T(end,:) - T(1,:)));
    verifyLessThan(tc, abs(Ein - (Estore + Eloss)) / abs(Ein), 1e-9);
end

function test_solver_equivalence(tc)
    b = RCBS.Building(); b.addStorey('S'); b.S.addZone('Z','C_main',2e6);
    b.S.Z.addWall(2.5,2e7,20,'Wall'); b.S.Z.addWindow(0.5,'W');
    b.S.Z.addInternalMass(1e-3,5e7,20,'IM');
    b.outdoorTempFunc = @(t) 2 + 6*sin(2*pi*hour(t)/24);
    b.simulation.startDate = datetime(2025,1,1); b.simulation.timeStep = seconds(60);

    b.simulation.solverMode = "cached"; b.simulate(days(3)); Tc = b.simulation.results.S.Z.T;
    b.simulation.solverMode = "legacy"; b.simulate(days(3)); Tl = b.simulation.results.S.Z.T;
    b.simulation.solverMode = "exact";  b.simulate(days(3)); Te = b.simulation.results.S.Z.T;
    verifyLessThan(tc, max(abs(Tc-Tl)), 1e-8);            % identical scheme
    verifyLessThan(tc, max(abs(Tc-Te)), 5e-3);            % ZOH vs bEuler, O(dt)
end

function test_live_state_visibility(tc)
    seen = [];
    b = RCBS.Building(); b.addStorey('S'); b.S.addZone('Z','C_main',2e6);
    b.S.Z.addWindow(0.5,'W');
    b.S.Z.connectToExternalSource(@probe,'T_main');
    b.outdoorTempFunc = @(t) 0;
    b.simulation.startDate = datetime(2025,1,1); b.simulation.timeStep = seconds(300);
    b.simulate(hours(4));
    verifyGreaterThan(tc, numel(unique(round(seen,4))), 5);   % was 1 before the fix
    function q = probe(bb), seen(end+1) = bb.S.Z.getMainTemp(); q = 0; end
end

function test_control_hook_and_actuator(tc)
    b = RCBS.Building(); b.addStorey('S'); b.S.addZone('Z','C_main',2e6);
    b.S.Z.addWall(2.5,2e7,20,'Wall'); b.S.Z.addWindow(0.5,'W');
    b.outdoorTempFunc = @(t) 0;
    b.simulation.startDate = datetime(2025,1,1); b.simulation.timeStep = seconds(60);
    b.simulation.registerActuator('Qh',0);
    b.S.Z.connectToExternalSource(@(bb) bb.simulation.getActuator('Qh'),'T_main');
    b.simulation.controlFcn = @(sim) sim.setActuator('Qh', max(0, 5000*(21 - sim.measure('S.Z'))));
    cbCount = zeros(1);
    b.simulation.stepCallback = @(s,k,t,T) plus(cbCount(1),0);   % must be callable, must not error
    b.simulate(days(2));
    Tf = b.simulation.results.S.Z.T(end);
    verifyGreaterThan(tc, Tf, 19.5);      % closed-loop heater holds near 21
    verifyLessThan(tc,   Tf, 21.5);
    verifyGreaterThan(tc, max(b.simulation.results.S.Z.heatInput), 0);  % actuator delivered heat
end

function test_statespace(tc)
    b = RCBS.Building(); b.addStorey('S'); b.S.addZone('Z','C_main',2e6);
    b.S.Z.addWall(2.5,2e7,20,'Wall'); b.S.Z.addWindow(0.5,'W');
    b.S.Z.addInternalMass(1e-3,5e7,20,'IM');
    b.simulation.buildLinear();
    [sysc, io] = b.simulation.getStateSpace();
    verifyEqual(tc, size(sysc.A,1), 3);
    verifyEqual(tc, size(sysc.B,2), 4);          % [Tout ; Q x 3]
    verifyTrue(tc, isstable(sysc));
    verifyEqual(tc, io.zoneMainRows, 1);
end
