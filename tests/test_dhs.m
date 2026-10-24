function tests = test_dhs
%TEST_DHS  Tests for the +DHS district-heating-systems library.
%
%   Run:  >> runtests('tests/test_dhs.m')
%
%   Covers the assembly API, the tree hydraulic solve (incl. building coupling),
%   a short co-simulation of the campus (energy closure, setpoint tracking) and
%   the controller-swap interface.
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    tc.TestData.sys = DHS.examples.campus();
    tc.TestData.res = tc.TestData.sys.run(days(2));
end

% ================= assembly API =================
function test_assemble_minimal(tc)
    sys = DHS.System('startDate', datetime(2025,1,1));
    chp = sys.addCentralHeatPlant('CHP');
    b   = chp.addBoiler('B1','QMax',8e5);
    pmp = chp.addPump('P0','dp0',2e5,'mdotMax',8);
    b.connectTo(pmp);
    verifyEqual(tc, sys.plant.QgasMax(), 8e5);
    verifyEqual(tc, chp.boilers{1}.feedsPump, pmp);
    hn = sys.addHydraulicNetwork();
    t1 = hn.addJunction('T1');
    r1 = hn.addJunction('R1', 'side','return');
    verifyEqual(tc, t1.side, 'supply');  verifyEqual(tc, r1.side, 'return');
    verifyEqual(tc, hn.R1, r1);
    % the two sides are separate trees: a supply pipe and a return pipe need not match
    hn.addPipe(chp.supplyPort, t1, 'name','sup1', 'L',40, 'D',0.11);
    hn.addPipe(r1, chp.returnPort, 'name','ret1', 'L',55, 'D',0.13);
    verifyEqual(tc, [hn.sup1.L, hn.sup1.D], [40 0.11]);
    verifyEqual(tc, [hn.ret1.L, hn.ret1.D], [55 0.13]);
    verifyError(tc, @() hn.addPipe(t1, r1), 'DHS:HydraulicNetwork:sides');
end

function test_port_wiring_matches_declarative(tc)
    % The declarative and port-wiring assembly styles must produce identical
    % topology: build the same small network both ways and compare solve().
    mkSys = @() DHS.System('startDate', datetime(2025,1,1));
    mkRC  = @() trivialRC();

    % ---- declarative ----
    sysD = mkSys();
    chpD = sysD.addCentralHeatPlant('CHP');
    chpD.addBoiler('B','QMax',1e6);
    chpD.addPump('P','dp0',3e5,'mdotMax',14);
    hnD = sysD.addHydraulicNetwork();
    tD  = hnD.addJunction('T1','type','tee','mainDiameter',0.11,'sideDiameter',0.05);
    hnD.addPipe(chpD.supplyPort, tD, 'L',40,'D',0.11);
    rD  = hnD.addJunction('R1', 'side','return');
    hnD.addPipe(rD, chpD.returnPort, 'L',40,'D',0.11);
    bD  = sysD.addBuilding('B1');  bD.useRCModel(mkRC());
    hxD = bD.addHeatExchanger('HX','UA',3e4,'Qcap',5e5);
    hxD.valve.Kvs = 18;  hxD.pump.dp0 = 0.9e5;  hxD.pump.mdotMax = 5;
    bD.attachSolar(DHS.Solar());  bD.attachSchedule(DHS.Schedule());
    hnD.connectBuilding(tD, bD, rD);
    sysD.compile();
    sD = hnD.solve(1);

    % ---- port-wiring ----
    sysP = mkSys();
    chpP = sysP.addCentralHeatPlant('CHP');
    chpP.addBoiler('B','QMax',1e6);
    pumpP = DHS.Hydraulic.CentrifugalPump('P','dp0',3e5,'mdotMax',14);
    chpP.attachPump(pumpP);
    hnP = sysP.addHydraulicNetwork();
    pipe1 = DHS.Hydraulic.Pipe('CHP->T1', 'L',40, 'D',0.11);
    chpP.supplyPort.connectToPipe(pipe1);
    tP = pipe1.addTjunction('T1', 0.05);
    rP = DHS.Hydraulic.Junction('R1', 'return');
    ret1 = DHS.Hydraulic.Pipe('ret1', 'L',40, 'D',0.11);
    rP.connectToPipe(ret1);  ret1.connectOutput(chpP.returnPort);
    bP  = sysP.addBuilding('B1');  bP.useRCModel(mkRC());
    hxP = bP.addHeatExchanger('HX','UA',3e4,'Qcap',5e5);
    hxP.valve.Kvs = 18;  hxP.pump.dp0 = 0.9e5;  hxP.pump.mdotMax = 5;
    bP.attachSolar(DHS.Solar());  bP.attachSchedule(DHS.Schedule());
    hnP.connectBuilding(tP, bP, rP);
    sysP.compile();
    sP = hnP.solve(1);

    verifyEqual(tc, sP.Mtot,   sD.Mtot,   'RelTol', 1e-12);
    verifyEqual(tc, sP.mdot,   sD.mdot,   'RelTol', 1e-12);
    verifyEqual(tc, sP.dpPump, sD.dpPump, 'RelTol', 1e-12);
end

function test_tjunction_loss_equivalent_length(tc)
    % A standard tee has an equivalent length of 20 diameters used as a run,
    % 60 as a branch, evaluated at the fully turbulent asymptote for that
    % leg's own diameter -- matching MATLAB/Simscape's own default
    % T-Junction (TL) model (K_main=20*fT_main, K_side=60*fT_side).
    tee = DHS.Hydraulic.TJunction('T', 'mainDiameter',0.10, 'sideDiameter',0.05);
    rho = 978;  mu = 4.0e-4;
    Krun    = tee.teeLossK('run',    rho, mu);
    Kbranch = tee.teeLossK('branch', rho, mu);

    fRun = DHS.Hydraulic.Pipe.swameeJain(1e7, tee.roughness/tee.mainDiameter);
    ARun = pi*tee.mainDiameter^2/4;
    KrunRef = fRun * (20*tee.mainDiameter) / (tee.mainDiameter * 2*rho*ARun^2);

    fBr = DHS.Hydraulic.Pipe.swameeJain(1e7, tee.roughness/tee.sideDiameter);
    ABr = pi*tee.sideDiameter^2/4;
    KbranchRef = fBr * (60*tee.sideDiameter) / (tee.sideDiameter * 2*rho*ABr^2);

    verifyEqual(tc, Krun,    KrunRef,    'RelTol', 1e-12);
    verifyEqual(tc, Kbranch, KbranchRef, 'RelTol', 1e-12);
    verifyGreaterThan(tc, Kbranch, Krun);   % branch (60D) always loses more than run (20D)

    % the fitting's friction factor is deliberately flow-independent (the 20
    % and 60 multipliers are themselves empirical constants calibrated to
    % fully turbulent flow): a pipe carrying this tee's branch loss picks up
    % exactly the same extra resistance at a representative flow and at a
    % deliberately tiny, laminar-range flow.
    gPipe = DHS.Hydraulic.Pipe('g', 'D',tee.sideDiameter, 'L',6, 'teeSide','branch');
    gPipe.nodeA = tee;
    gBase = DHS.Hydraulic.Pipe('gBase', 'D',tee.sideDiameter, 'L',6);
    KbranchAtHiFlow = gPipe.resistance(2,    rho, mu) - gBase.resistance(2,    rho, mu);
    KbranchAtLoFlow = gPipe.resistance(1e-4, rho, mu) - gBase.resistance(1e-4, rho, mu);
    verifyEqual(tc, KbranchAtHiFlow, KbranchAtLoFlow, 'RelTol', 1e-12);

    % a pipe leaving the tee's branch port picks the loss up automatically
    pipe = DHS.Hydraulic.Pipe('side');
    tee.portC.connectToPipe(pipe);
    verifyEqual(tc, pipe.teeSide, 'branch');
    K = pipe.resistance(2, rho, mu);
    verifyGreaterThan(tc, K, Kbranch);   % pipe's own Darcy term plus the tee's
end

function test_tjunction_friction_model_actual(tc)
    % frictionModel='actual' evaluates the fitting's own friction factor at
    % the leg's actual Reynolds number instead of the fixed, fully turbulent
    % asymptote 'fixed' uses by default.
    rho = 978;  mu = 4.0e-4;  mdot = 0.02;   % small flow -> laminar-range Re
    teeFixed = DHS.Hydraulic.TJunction('Tf', 'mainDiameter',0.10, 'sideDiameter',0.05);
    teeAct   = DHS.Hydraulic.TJunction('Ta', 'mainDiameter',0.10, 'sideDiameter',0.05, 'frictionModel','actual');

    Kfixed = teeFixed.teeLossK('run', rho, mu, mdot);
    Kact   = teeAct.teeLossK('run', rho, mu, mdot);
    verifyNotEqual(tc, Kact, Kfixed);   % must actually differ at this low flow

    A  = pi*teeAct.mainDiameter^2/4;
    Re = rho * (mdot/(rho*A)) * teeAct.mainDiameter / mu;
    fRef = DHS.Hydraulic.Pipe.swameeJain(Re, teeAct.roughness/teeAct.mainDiameter);
    KactRef = fRef * (20*teeAct.mainDiameter) / (teeAct.mainDiameter * 2*rho*A^2);
    verifyEqual(tc, Kact, KactRef, 'RelTol', 1e-12);
end

function test_fixed_displacement_pump_branch(tc)
    pd = DHS.Hydraulic.FixedDisplacementPump('PD', 'mdotRated',5, 'dpMax',3e5);
    Kbr = 4000;  dpAvail = 0;

    % low resistance: the pump forces its rated flow (unlimited by the relief valve)
    [m1, h1] = pd.solveBranch(Kbr, dpAvail, 1);
    verifyEqual(tc, m1, 5, 'RelTol', 1e-12);
    verifyEqual(tc, h1, Kbr*m1^2 - dpAvail, 'RelTol', 1e-12);
    verifyLessThan(tc, h1, pd.dpMax);

    % high resistance: the relief valve caps the head, flow drops below rated
    KbrHigh = 4e5;
    [m2, h2] = pd.solveBranch(KbrHigh, dpAvail, 1);
    verifyLessThan(tc, m2, 5);
    verifyEqual(tc, h2, pd.dpMax, 'AbsTol', 1e-9);
    verifyEqual(tc, m2, sqrt((pd.dpMax+dpAvail)/KbrHigh), 'RelTol', 1e-12);

    % speed scales the commanded (unsaturated) flow linearly
    [m3, ~] = pd.solveBranch(Kbr, dpAvail, 0.4);
    verifyEqual(tc, m3, 0.4*5, 'RelTol', 1e-12);
end

% ================= hydraulic solve =================
function test_hydro_sum_equals_Mtot(tc)
    hyd = tc.TestData.sys.network.solve(1);
    verifyEqual(tc, sum(hyd.mdot) + hyd.mdotBypass, hyd.Mtot, 'RelTol', 1e-9);
    verifyGreaterThan(tc, min(hyd.pSupBranch), hyd.pRetBranch(1)*0);   % pressures set
    verifyGreaterThan(tc, hyd.dpPump, 0);
end

function test_hydro_buildings_are_coupled(tc)
    net = tc.TestData.sys.network;
    for b = 1:numel(net.buildings)
        net.buildings{b}.heatExchanger.valve.pos = 0.5;
        net.buildings{b}.heatExchanger.pump.speed = 0.5;
    end
    s0 = net.solve(1);
    net.buildings{4}.heatExchanger.valve.pos  = 1.0;   % open Engineering
    net.buildings{4}.heatExchanger.pump.speed = 1.0;
    s1 = net.solve(1);
    verifyGreaterThan(tc, s1.mdot(4), 1.3*s0.mdot(4));  % the opened branch surges
    verifyGreaterThan(tc, s1.Mtot,    s0.Mtot);
    verifyLessThan(tc,    s1.dpPump,  s0.dpPump);       % central pump sags
    others = [1 2 3 5];
    verifyTrue(tc, all(s1.mdot(others) < s0.mdot(others)));  % every other branch loses flow
end

% ================= co-simulation =================
function test_energy_closure(tc)
    res = tc.TestData.res; P = res.plant;
    qd = zeros(size(P.Qboiler));
    for i = 1:numel(res.bldg), qd = qd + res.bldg(i).Qdeliv; end
    resid = P.Qboiler - qd - P.Qdist_loss - P.Qbase;
    verifyLessThan(tc, abs(sum(resid)) / abs(sum(P.Qboiler)), 1e-6);
    verifyGreaterThan(tc, res.energy.plant_eff, 0.80);
    verifyLessThan(tc,    res.energy.plant_eff, 1.0);
end

function test_supply_regulation_and_tracking(tc)
    res = tc.TestData.res; P = res.plant;
    verifyLessThan(tc, mean(abs(P.Tsupply - P.TsupSet)), 2.0);
    verifyLessThan(tc, prctile(abs(diff(P.Tsupply)), 99), 0.6);   % no chatter
    occ = hour(res.time) >= 9 & hour(res.time) < 16 & weekday(res.time) >= 2 & weekday(res.time) <= 6;
    for i = 1:numel(res.bldg)
        verifyLessThan(tc, abs(mean(res.bldg(i).Tzone(occ) - res.bldg(i).setpoint(occ))), 1.2);
        verifyLessThan(tc, min(res.bldg(i).Tzone), 20.5);         % setback visible
    end
end

function test_pressures_velocities_in_band(tc)
    res = tc.TestData.res; P = res.plant;
    verifyGreaterThan(tc, min(P.pSupHeader), 1.0e5);
    verifyLessThan(tc,    max(P.pSupHeader), 8.0e5);
    for i = 1:numel(res.bldg)
        verifyLessThan(tc, max(res.bldg(i).vel), 3.0);
    end
end

% ================= controller swap =================
function test_controller_swap_runs_and_differs(tc)
    sP = DHS.examples.campus();  rP = sP.run(days(1));
    sL = DHS.examples.campus();
    [sysc, io] = sL.buildings{3}.rcBuilding.simulation.getStateSpace();
    b3 = sL.buildings{3};
    r  = io.zoneMainRows(1);
    Qw = ones(size(sysc.A,1), 1);  Qw(r) = 6e3;
    lq = DHS.controllers.LQR(sysc.A, sysc.B(:, r+1), Qw, 1e-9, 60);
    lq.uScale = b3.heatExchanger.Qcap;                         % heat at full valve opening
    lq.state  = @(sys) b3.rcBuilding.simulation.Tnow - b3.setpoint;   % x = x_real - x_ref
    b3.heatExchanger.valve.attachController(lq);
    rL = sL.run(days(1));
    verifyTrue(tc, all(isfinite(rL.bldg(3).Tzone)));
    verifyLessThan(tc, max(rL.bldg(3).Tzone), 30);
    verifyGreaterThan(tc, max(abs(rL.bldg(3).Tzone - rP.bldg(3).Tzone)), 0.02);
end

function test_pid_positional_and_relay(tc)
    c = DHS.controllers.PID(2, 0.05, 0);
    verifyEqual(tc, c.Kp, 2);  verifyEqual(tc, c.Ki, 0.05);
    r = DHS.controllers.Relay(0.5);
    r.measure = @(s) s.y;  r.reference = @(s) s.r;           % the "simulation" is a struct here
    verifyEqual(tc, r.update(struct('y',0,'r', 1.0), 1), 1);
    verifyEqual(tc, r.update(struct('y',0,'r',-1.0), 1), 0);
    verifyError(tc, @() DHS.controllers.PID(1,0,0).update(struct(), 1), 'DHS:controllers:noReference');   % a controller must be told what to hold
end

function test_callback_controller(tc)
    c = DHS.controllers.Callback(@(sys, dt) 0.5*(sys.r - sys.y));
    verifyEqual(tc, c.update(struct('y',19,'r',21), 60), 1);           % 0.5*2 = 1
    verifyEqual(tc, c.update(struct('y',20.5,'r',21), 60), 0.25, 'AbsTol', 1e-12);
    verifyEqual(tc, c.update(struct('y',25,'r',21), 60), 0);            % clamped to uMin
    v = DHS.Hydraulic.Valve('V');
    v.attachController(c);                               % accepted like any controller
    verifyEqual(tc, v.controller, c);
    verifyError(tc, @() DHS.controllers.Callback(5), 'DHS:controllers:Callback:fcn');
end

% ================= multi-zone example =================
function test_multizone_campus_runs_and_closes(tc)
    sys = DHS.examples.campus_multizone();
    res = sys.run(days(1));
    P = res.plant;
    % every building is 2 zones per storey, coupled by partitions + slabs
    for b = 1:sys.nB
        bd = sys.buildings{b};
        nS = numel(bd.rcBuilding.storeyList);
        verifyEqual(tc, numel(bd.zones), 2*nS, sprintf('%s zone count', bd.name));
        verifyEqual(tc, size(res.bldg(b).Tzones,2), 2*nS);
        nn = string(bd.sim.nodeNames);
        verifyTrue(tc, any(contains(nn,'part_')), 'partition mid nodes present');
        verifyTrue(tc, any(contains(nn,'slab_')) || nS == 1, 'slab mid nodes present');
        verifyTrue(tc, all(res.bldg(b).Tzones(:) > 8 & res.bldg(b).Tzones(:) < 32));
    end
    % energy still closes with the multi-zone RC networks
    qd = zeros(size(P.Qboiler));
    for b = 1:sys.nB, qd = qd + res.bldg(b).Qdeliv; end
    resid = P.Qboiler - qd - P.Qdist_loss - P.Qbase;
    verifyLessThan(tc, abs(sum(resid))/abs(sum(P.Qboiler)), 1e-3);
    verifyGreaterThan(tc, res.energy.plant_eff, 0.80);
    verifyLessThan(tc,    max(P.Qgas), sys.plant.QgasMax()*1.0001);
end

function test_multizone_slab_couples_storeys(tc)
    % heat one zone; with the outdoor boundary held at the initial temperature
    % (no envelope loss) every zone can only warm -- the zone directly above the
    % heated one (slab-coupled) must warm clearly more than a non-adjacent zone
    sys = DHS.examples.campus_multizone();
    b = sys.buildings{3};                                   % Science, 4 storeys
    b.bindClock(datetime(2025,1,1), seconds(60), @(t) 20);
    b.reset(60);
    sim = b.sim;  nn = string(sim.nodeNames);
    iS1 = find(nn == "S1.Big.T_main");
    iS2 = find(nn == "S2.Big.T_main");
    iS4 = find(nn == "S4.Big.T_main");
    T0 = sim.Tnow;
    q  = zeros(numel(T0),1);  q(iS1) = 2e4;                 % 20 kW into S1.Big
    for k = 1:720, sim.stepOnce(datetime(2025,1,1)+seconds(60*k), 20, q); end
    dS1 = sim.Tnow(iS1) - T0(iS1);
    dS2 = sim.Tnow(iS2) - T0(iS2);
    dS4 = sim.Tnow(iS4) - T0(iS4);
    verifyGreaterThan(tc, dS1, dS2 + 1);      % heated zone warms most
    verifyGreaterThan(tc, dS2, dS4 + 0.3);    % slab-adjacent zone above warms more than a far one
    verifyGreaterThan(tc, dS2, 0.3);          % the coupling actually transmits heat upward
end

% ================= pipe temperatures =================
function test_pipe_heat_loss_counted_once(tc)
    % The network's heat loss is the sum over the pipes that exist (trunk,
    % service and return pipes), each with its own flow; a trunk shared by
    % several buildings is not counted once per building.
    sys = tc.TestData.sys;  hn = sys.network;  res = tc.TestData.res;
    q = 0;
    for k = 1:numel(hn.pipes),       q = q + hn.pipes{k}.Qloss;       end
    for k = 1:numel(hn.returnPipes), q = q + hn.returnPipes{k}.Qloss; end
    for b = 1:numel(hn.buildings), q = q + hn.buildings{b}.connPipeSup.Qloss + hn.buildings{b}.connPipeRet.Qloss; end
    if hn.hasBypass(), q = q + hn.bypassPipe.Qloss; end
    verifyEqual(tc, q, res.plant.Qdist_loss(end), 'RelTol', 1e-9);
    % water cools along the supply tree and every pipe's outlet is its Tin minus its drop
    p1 = hn.pipes{1};
    verifyLessThan(tc, p1.Tout, p1.Tin);
    verifyEqual(tc, p1.Tdrop, p1.Tin - p1.Tout, 'AbsTol', 1e-12);
end

function test_end_bypass_takes_undrawn_flow(tc)
    % With an end-of-line bypass, water the buildings do not draw passes through
    % it, so total flow = building flows + bypass flow, and the bypass carries a
    % larger share when the buildings' valves are closed than when they are open.
    sys = campusWithBypass();  hn = sys.network;
    verifyTrue(tc, hn.hasBypass());
    verifyFalse(tc, tc.TestData.sys.network.hasBypass());     % the default campus has none
    pos = cellfun(@(b) b.heatExchanger.valve.pos, hn.buildings);
    share = zeros(1,2);  tot = zeros(1,2);
    for k = 1:2                                       % 1: valves closed, 2: valves open
        for b = 1:numel(hn.buildings), hn.buildings{b}.heatExchanger.valve.pos = k-1; end
        s = hn.solve(1);
        verifyGreaterThan(tc, s.mdotBypass, 0);
        verifyEqual(tc, s.Mtot, sum(s.mdot) + s.mdotBypass, 'AbsTol', 1e-9);
        share(k) = s.mdotBypass / s.Mtot;  tot(k) = sum(s.mdot);
    end
    for b = 1:numel(hn.buildings), hn.buildings{b}.heatExchanger.valve.pos = pos(b); end
    verifyGreaterThan(tc, share(1), share(2));
    verifyGreaterThan(tc, tot(2), tot(1));
end

function test_building_pump_stopped_by_default(tc)
    % A building has its control valve only: the substation pump is stopped
    % unless switched on, and a stopped pump adds no head and no resistance.
    hn = DHS.examples.campus().network;
    for b = 1:numel(hn.buildings)
        p = hn.buildings{b}.heatExchanger.pump;
        verifyEqual(tc, p.speed, 0);
        K = 3e5;  dp = 7e4;
        [m, h] = p.solveBranch(K, dp, p.speed);
        verifyEqual(tc, m, sqrt(dp/K), 'RelTol', 1e-12);
        verifyEqual(tc, h, 0);
        verifyGreaterThan(tc, p.solveBranch(K, dp, 1), m);
    end
end

function test_central_pump_holds_differential_pressure(tc)
    % The campus runs its central pump on a PID that holds the supply-return
    % differential pressure at the last tee at 3 bar.
    sys = tc.TestData.sys;  node = sys.network.T_Engineering;  rnode = sys.network.R_Engineering;
    setappdata(0, 'dhsDp', []);  cleaner = onCleanup(@() rmappdata(0, 'dhsDp'));
    sys.stepFunction = @(s) setappdata(0, 'dhsDp', ...
        [getappdata(0,'dhsDp'), node.p - rnode.p, s.plant.supplyPump.speed]);
    res = sys.run(days(1));  sys.stepFunction = [];
    d = reshape(getappdata(0, 'dhsDp'), 2, []);
    free = d(2,:) > 0.32 & d(2,:) < 0.98;            % pump neither at its minimum nor at full speed
    verifyGreaterThan(tc, nnz(free), 100);
    verifyLessThan(tc, median(abs(d(1,free) - 3e5)) / 3e5, 0.05);
    verifyGreaterThan(tc, max(res.plant.pumpSpeed) - min(res.plant.pumpSpeed(2:end)), 0.2);
end

function test_bypass_valve_fixed_by_default_and_controllable(tc)
    % The bypass valve holds its position unless a controller is attached; with a
    % PID on the differential pressure at its junction it moves.
    res0 = campusWithBypass().run(hours(6));
    verifyEqual(tc, res0.plant.bypassPos, ones(size(res0.plant.bypassPos)));
    sys = campusWithBypass();  hn = sys.network;  v = hn.bypassValve;
    j = hn.bypassJunction;  rj = hn.bypassReturnJunction;
    c = DHS.controllers.PID('Kp',1/2e5, 'Ki',0, 'dir',-1);                    % open when dp > reference
    c.measure   = @(s) j.p - rj.p;
    c.reference = 3.5e5;                                                      % above what the pump holds: close
    v.attachController(c);
    res = sys.run(hours(6));
    verifyLessThan(tc, res.plant.bypassPos(end), 0.6);
    verifyGreaterThanOrEqual(tc, min(res.plant.bypassPos), 0);
    verifyLessThan(tc, mean(res.plant.Mbypass(2:end)), mean(res0.plant.Mbypass(2:end)));
end

% ================= start / step / stop functions =================
function test_start_step_stop_functions(tc)
    % The three hooks get the whole system: start sets a parameter before the run,
    % step changes one during it and logs the weather, stop post-processes the results.
    sys = DHS.examples.campus();
    sys.startFunction = @startHook;
    sys.stepFunction  = @stepHook;
    sys.stopFunction  = @stopHook;
    res = sys.run(days(1));
    n = round(86400 / seconds(sys.timeStep));
    verifyEqual(tc, res.plant.TsupSet(1), 65);                     % set by startFunction
    verifyEqual(tc, res.plant.TsupSet(100), 65);
    verifyEqual(tc, res.plant.TsupSet(101), 60);                   % changed at the start of step 100
    verifyEqual(tc, sys.userData.idx, 1:n);                        % called once per step
    verifyEqual(tc, res.Tout(2:end).', sys.userData.Tout, 'AbsTol', 1e-12);   % sys.wx is the weather of the step
    verifyEqual(tc, res.nHookSteps, n);                            % added by stopFunction, returned by run
    verifyEqual(tc, sys.result.nHookSteps, n);
    w = sys.weather.at(sys.startDate);
    for f = {'Tout','Tground','ghi','dhi','dni','sunZen','sunAz','sunEl','albedo'}
        verifyTrue(tc, isfield(sys.wx, f{1}) && isfield(w, f{1}));
    end
end

function test_step_function_changes_rc_model(tc)
    % A hook may change the RC model by name during the run: halving a window resistance at
    % step 500 raises the heat the building needs afterwards.
    sB = DHS.examples.campus();  rB = sB.run(days(1));
    sV = DHS.examples.campus();
    sV.stepFunction = @rcHook;
    rV = sV.run(days(1));
    qB = rB.bldg(1).Qdeliv;  qV = rV.bldg(1).Qdeliv;
    verifyEqual(tc, qV(1:501), qB(1:501), 'AbsTol', 1e-6);          % identical until the change
    verifyGreaterThan(tc, mean(qV(502:end)), 1.03*mean(qB(502:end)));
    verifyTrue(tc, all(isfinite(rV.bldg(1).Tzone)));
end

function test_named_access_to_rc_parts(tc)
    % building.Storey.Zone.Part.R / C / T: names instead of struct indices
    sys = DHS.examples.campus();
    z = sys.Arts.S1.Z;
    verifyEqual(tc, sys.Arts, sys.buildings{2});
    verifyEqual(tc, z.Wall.R, sum([z.resistors(strcmp({z.resistors.name}, 'Wall_m') | strcmp({z.resistors.name}, 'Wall_o')).R]), 'RelTol', 1e-12);
    R0 = z.Wall.R;  z.Wall.R = 2*R0;
    verifyEqual(tc, z.Wall.R, 2*R0, 'RelTol', 1e-12);
    verifyEqual(tc, z.resistors(strcmp({z.resistors.name}, 'Wall_m')).R, R0, 'RelTol', 1e-12);   % each half
    z.Wall.C = 5e7;
    verifyEqual(tc, z.nodes(strcmp({z.nodes.name}, 'Wall')).C, 5e7);
    verifyEqual(tc, z.Air.T, z.nodes(1).T);
    verifyEqual(tc, z.Window.R, z.resistors(strcmp({z.resistors.name}, 'Window')).R);
    verifyError(tc, @() z.Window.T, 'RCBS:Part:noNode');            % a window has no mass
    verifyError(tc, @() z.Air.R, 'RCBS:Part:noResistance');
end

function test_named_access_to_network_parts(tc)
    % hn.<pipe>, hn.<tee>, tee.portX.<property>, sys.<plant>.<boiler>: names instead of cell indices
    sys = DHS.examples.campus();  hn = sys.network;
    verifyEqual(tc, hn.trunk1.L, 40);  verifyEqual(tc, hn.trunk1.D, 0.11);
    verifyEqual(tc, hn.return1.L, 40);  verifyEqual(tc, hn.return1.D, 0.11);   % the return side is its own pipes
    hn.trunk1.L = 60;                                              % ... not changed with the supply pipe
    verifyEqual(tc, hn.pipes{1}.L, 60);  verifyEqual(tc, hn.return1.L, 40);
    hn.return1.D = 0.13;  verifyEqual(tc, hn.trunk1.D, 0.11);
    hn.return1.D = 0.11;
    tee = hn.T_Administration;
    verifyClass(tc, tee, 'DHS.Hydraulic.TJunction');
    verifyEqual(tc, tee.portB.D, 0.11);  verifyEqual(tc, tee.portC.D, 0.045);
    tee.portC.D = 0.06;  verifyEqual(tc, tee.sideDiameter, 0.06);
    verifyEqual(tc, hn.trunk1.Output, tee);                        % trunk1 ends at the first tee
    verifyEqual(tc, hn.trunk1.Input, sys.plant.supplyPort);
    verifyEqual(tc, tee.portB.pipe, hn.trunk2);                    % the pipe leaving the run
    verifyEqual(tc, tee.portC.pipe, sys.Administration.connPipeSup);   % the building's service pipe
    verifyEqual(tc, tee.portA.pipe, hn.trunk1);
    verifyEqual(tc, sys.CHP.B1.QMax, 1.5e6);  verifyEqual(tc, sys.CHP.P0.dp0, 6e5);
    sys.compile();  s = hn.solve(1);                               % the edited network still solves
    verifyTrue(tc, s.Mtot > 0);
end

function test_return_side_is_solved_on_its_own(tc)
    % the return pipes are separate from the supply pipes: a narrower, longer return main
    % lowers the flow and loses more heat without touching the supply side
    sys = DHS.examples.campus();  hn = sys.network;  sys.compile();
    for k = 1:60, s0 = hn.solve(1); end
    Mbase = s0.Mtot;
    hn.return1.D = 0.06;  hn.return1.L = 200;
    for k = 1:60, s1 = hn.solve(1); end
    verifyLessThan(tc, s1.Mtot, Mbase);
    verifyEqual(tc, hn.trunk1.D, 0.11);  verifyEqual(tc, hn.trunk1.L, 40);
    [~, q1] = hn.returnTemperatures(50*ones(1,5), 5, s1.mdot, 4186);
    hn.return1.D = 0.11;  hn.return1.L = 40;
    for k = 1:60, s2 = hn.solve(1); end
    [~, q0] = hn.returnTemperatures(50*ones(1,5), 5, s2.mdot, 4186);
    verifyEqual(tc, s2.Mtot, Mbase, 'RelTol', 1e-6);
    verifyGreaterThan(tc, q1, q0);
end

function test_port_wiring_by_port_objects(tc)
    % a tee built by hand is wired through its port objects and registered by name
    sys = DHS.System('startDate', datetime(2025,1,1));
    chp = sys.addCentralHeatPlant('CHP');  chp.addBoiler('B','QMax',1e6);  chp.addPump('P','dp0',3e5,'mdotMax',14);
    hn = sys.addHydraulicNetwork();
    p1 = DHS.Hydraulic.Pipe('pip1', 'L',40, 'D',0.11);
    chp.supplyPort.connectToPipe(p1);
    tee1 = DHS.Hydraulic.TJunction('tee1', 'mainDiameter',0.11, 'sideDiameter',0.05);
    p1.connectOutput(tee1);
    p2 = DHS.Hydraulic.Pipe('pip2', 'L',30, 'D',0.11);
    tee1.portB.connectToPipe(p2);
    tee2 = DHS.Hydraulic.TJunction('tee2', 'mainDiameter',0.11, 'sideDiameter',0.05);
    p2.connectOutput(tee2.portA);                                   % a port is also a valid target
    verifyEqual(tc, hn.pip1, p1);  verifyEqual(tc, hn.pip2, p2);  verifyEqual(tc, hn.tee2, tee2);
    verifyEqual(tc, hn.tee1.portB.pipe, p2);
    verifyEqual(tc, p2.teeSide, 'run');
    verifyError(tc, @() tee1.portA.connectToPipe(p2), 'DHS:Port:inlet');
    % the string form wires the same way: tee.connectToPipe('portC', pipe), tee.connectToPipe(pipe) = portB
    p3 = DHS.Hydraulic.Pipe('pip3', 'L',20, 'D',0.05);   tee2.connectToPipe('portC', p3);
    p4 = DHS.Hydraulic.Pipe('pip4', 'L',20, 'D',0.11);   tee2.connectToPipe(p4);
    verifyEqual(tc, p3.teeSide, 'branch');  verifyEqual(tc, p4.teeSide, 'run');
    p5 = DHS.Hydraulic.Pipe('pip5', 'L',20, 'D',0.05);   tee2.portC.connectToPipe(p5);
    verifyEqual(tc, p5.teeSide, p3.teeSide);
    verifyEqual(tc, p5.nodeA, p3.nodeA);
end

function test_parameters_at_creation_and_by_assignment(tc)
    % every component takes its parameters as name-value pairs when it is created
    % and as plain property assignment afterwards
    sys = DHS.System('startDate', datetime(2025,1,1));
    chp = sys.addCentralHeatPlant('Plant', 'TboilerMax',85, 'Cw',5e7);
    verifyEqual(tc, sys.Plant.TboilerMax, 85);  verifyEqual(tc, chp.Cw, 5e7);
    chp.addBoiler('Boil1', 'QMax',9e5, 'etaRef',0.9, 'etaMin',0.7);
    verifyEqual(tc, chp.Boil1.QMax, 9e5);  verifyEqual(tc, chp.Boil1.etaMin, 0.7);
    chp.Boil1.QMax = 8e5;  verifyEqual(tc, chp.boilers{1}.QMax, 8e5);
    chp.addPump('Pmp', 'dp0',2e5, 'mdotMax',9, 'minSpeed',0.2);
    verifyEqual(tc, chp.Pmp.dp0, 2e5);  verifyEqual(tc, chp.supplyPump.minSpeed, 0.2);
    chp.Pmp.mdotMax = 10;  verifyEqual(tc, chp.supplyPump.mdotMax, 10);
    hn = sys.addHydraulicNetwork('pReturnRef',2e5, 'rho',970);
    verifyEqual(tc, hn.rho, 970);  verifyEqual(tc, hn.pReturnRef, 2e5);
    hn.addJunction('tee1', 'type','tee', 'mainDiameter',0.12, 'sideDiameter',0.06, 'roughness',1e-4, 'frictionModel','actual');
    verifyEqual(tc, hn.tee1.mainDiameter, 0.12);  verifyEqual(tc, hn.tee1.roughness, 1e-4);
    verifyEqual(tc, hn.tee1.frictionModel, 'actual');
    hn.addPipe(chp.supplyPort, hn.tee1, 'name','pipeA', 'D',0.2, 'L',33, 'eps',1e-4, 'UperM',0.2);
    verifyEqual(tc, [hn.pipeA.D, hn.pipeA.L, hn.pipeA.eps, hn.pipeA.UperM], [0.2 33 1e-4 0.2]);
    hn.pipeA.D = 0.15;  verifyEqual(tc, hn.pipeA.D, 0.15);
    b = sys.addBuilding('Hall', 'connD',0.04, 'connLength',12, 'Kminor',5);
    verifyEqual(tc, [sys.Hall.connD, sys.Hall.connLength, sys.Hall.Kminor], [0.04 12 5]);
    hx = b.addHeatExchanger('HX', 'UA',2e4, 'Qcap',3e5, 'dpNomPrimary',2e4);
    verifyEqual(tc, sys.Hall.HX.UA, 2e4);  verifyEqual(tc, hx.dpNomPrimary, 2e4);
    hx.attachValve(DHS.Hydraulic.Valve('V1', 'Kvs',12, 'char','linear', 'rangeability',30));
    hx.attachPump(DHS.Hydraulic.CentrifugalPump('Booster', 'dp0',5e4, 'mdotMax',3));
    verifyEqual(tc, [sys.Hall.HX.V1.Kvs, sys.Hall.HX.V1.rangeability], [12 30]);
    verifyEqual(tc, sys.Hall.HX.Booster.dp0, 5e4);
    hx.V1.Kvs = 14;  verifyEqual(tc, hx.valve.Kvs, 14);
    hn.addJunction('rj', 'side','return');
    hn.addBypass(hn.tee1, hn.rj, 'name','bp1', 'L',12, 'D',0.04, 'eps',1e-4, 'Kvs',2, 'pos',0.5, 'char','eqpct', 'rangeability',40);
    verifyEqual(tc, [hn.bp1.L, hn.bp1.D, hn.bp1.eps], [12 0.04 1e-4]);
    verifyEqual(tc, [hn.bypassValve.Kvs, hn.bypassValve.pos, hn.bypassValve.rangeability], [2 0.5 40]);
    verifyEqual(tc, hn.bypassValve.char, 'eqpct');
    verifyError(tc, @() hn.addBypass(hn.tee1, hn.rj, 'nonsense', 1), 'DHS:HydraulicNetwork:bypass');
end

function test_hooks_and_controllers_share_user_data(tc)
    % sys.userData is how a hook hands data to the controllers: here an occupancy
    % schedule written by startFunction drives a valve through a Callback.
    sys = DHS.examples.campus();
    sys.startFunction = @userDataHook;
    sys.Administration.heatExchanger.valve.attachController(DHS.controllers.Callback(@occupancyLaw));
    res = sys.run(hours(24));
    v = res.bldg(1).valve;
    verifyEqual(tc, v(2:301), 0.1*ones(300,1), 'AbsTol', 1e-12);     % steps 1-300 unoccupied
    verifyEqual(tc, v(302:601), 0.9*ones(300,1), 'AbsTol', 1e-12);   % steps 301-600 occupied
end

function startHook(sys)
    sys.plant.TsupSet = 65;
    sys.userData = struct('idx', [], 'Tout', []);
end

function stepHook(sys)
    sys.userData.idx(end+1)  = sys.stepIndex;
    sys.userData.Tout(end+1) = sys.wx.Tout;
    if sys.stepIndex == 100, sys.plant.TsupSet = 60; end
end

function stopHook(sys)
    sys.result.nHookSteps = numel(sys.userData.idx);
end

function rcHook(sys)
    if sys.stepIndex == 500
        z = sys.Administration.S1.Z;                    % building, storey and zone by name
        z.Window.R = z.Window.R / 2;
    end
end

function userDataHook(sys)
    sys.userData.occ = [zeros(1, 300), ones(1, 300), zeros(1, 840)];      % a schedule the controllers share
end

function u = occupancyLaw(sys, ~)
    u = 0.1 + 0.8 * sys.userData.occ(sys.stepIndex);
end

% ================= helpers =================
function sys = campusWithBypass()
    sys = DHS.examples.campus();
    sys.network.addBypass(sys.network.T_Engineering, sys.network.R_Engineering, 'L',10, 'D',0.05, 'Kvs',1.5);
    sys.compile();
end

function B = trivialRC()
    B = RCBS.Building(); B.addStorey('S'); B.S.addZone('Z','C_main',2e6);
    B.S.Z.setAir(2e6, 20);
    B.S.Z.addWindow(0.02, 'Window');  B.S.Z.addWindow(0.05, 'InfVent');
end
