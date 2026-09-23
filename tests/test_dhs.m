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
    verifyEqual(tc, t1.mirror.side, 'return');
    verifyEqual(tc, t1.mirror.mirror, t1);
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
    bD  = sysD.addBuilding('B1');  bD.useRCModel(mkRC());
    hxD = bD.addHeatExchanger('HX','UA',3e4,'Qcap',5e5);
    hxD.valve.Kvs = 18;  hxD.pump.dp0 = 0.9e5;  hxD.pump.mdotMax = 5;
    bD.attachSolar(DHS.Solar());  bD.attachSchedule(DHS.Schedule());
    hnD.connectBuilding(tD, bD);
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
    bP  = sysP.addBuilding('B1');  bP.useRCModel(mkRC());
    hxP = bP.addHeatExchanger('HX','UA',3e4,'Qcap',5e5);
    hxP.valve.Kvs = 18;  hxP.pump.dp0 = 0.9e5;  hxP.pump.mdotMax = 5;
    bP.attachSolar(DHS.Solar());  bP.attachSchedule(DHS.Schedule());
    hnP.connectBuilding(tP, bP);
    sysP.compile();
    sP = hnP.solve(1);

    verifyEqual(tc, sP.Mtot,   sD.Mtot,   'RelTol', 1e-12);
    verifyEqual(tc, sP.mdot,   sD.mdot,   'RelTol', 1e-12);
    verifyEqual(tc, sP.dpPump, sD.dpPump, 'RelTol', 1e-12);
end

function test_tjunction_loss_matches_crane(tc)
    % Crane TP-410: a standard tee has an equivalent length of 20 diameters
    % used as a run, 60 as a branch.
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

    % a pipe leaving the tee's branch port picks the loss up automatically
    pipe = DHS.Hydraulic.Pipe('side');
    tee.connectToPipe('portC', pipe);
    verifyEqual(tc, pipe.teeSide, 'branch');
    K = pipe.resistance(2, rho, mu);
    verifyGreaterThan(tc, K, Kbranch);   % pipe's own Darcy term plus the tee's
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
    verifyEqual(tc, sum(hyd.mdot), hyd.Mtot, 'RelTol', 1e-9);
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
    sL.buildings{3}.heatExchanger.valve.attachController( DHS.controllers.LQR(sysc, ...
        struct('io',io,'Ts',60,'uMaxW',sL.buildings{3}.heatExchanger.Qcap, ...
               'qZone',6e3,'qInt',8e-2,'R',1e-9)) );
    rL = sL.run(days(1));
    verifyTrue(tc, all(isfinite(rL.bldg(3).Tzone)));
    verifyLessThan(tc, max(rL.bldg(3).Tzone), 30);
    verifyGreaterThan(tc, max(abs(rL.bldg(3).Tzone - rP.bldg(3).Tzone)), 0.02);
end

function test_pid_positional_and_relay(tc)
    c = DHS.controllers.PID(2, 0.05, 0);
    verifyEqual(tc, c.Kp, 2);  verifyEqual(tc, c.Ki, 0.05);
    r = DHS.controllers.Relay(0.5);
    verifyEqual(tc, r.update(0, 1.0, 1), 1);
    verifyEqual(tc, r.update(0,-1.0, 1), 0);
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

% ================= helpers =================
function B = trivialRC()
    B = RCBS.Building(); B.addStorey('S'); B.S.addZone('Z','C_main',2e6);
    B.S.Z.setAir(2e6, 20);
    B.S.Z.addWindow(0.02, 'Window');  B.S.Z.addWindow(0.05, 'InfVent');
end
