function V = validate_desBuilding(plotMode)
%VALIDATE_DESBUILDING  DHS.Building: closed-loop steady-state heat balance
%                      (single zone) and delivered-heat conservation (multi-zone).
%
%   COMPONENT      DHS.Building  (wraps an RCBS.Building; owns the HX + valve +
%                  pump + controller; assembles hydronic + solar + internal +
%                  ventilation + free-cooling heat into the RC nodes each step;
%                  in multi-zone mode: aggregate control + demand-proportional
%                  heat split).  Case (1) additionally exercises DHS.System /
%                  DHS.HydraulicNetwork so the valve has real actuator authority.
%
%   TEST CASE + REFERENCE
%     (1) SINGLE-ZONE CLOSED-LOOP EQUILIBRIUM.  A one-zone DHS.Building on a
%         minimal district loop (central heat plant + pump + one pipe + one
%         substation).  A PID valve loop, a fixed setpoint, a constant outdoor
%         temperature, a constant internal gain and a plentiful primary supply.
%         The hydraulic network is solved every step, so closing the valve
%         actually throttles the primary mass flow (the loop has authority).
%         At equilibrium the first law of the zone reads
%             Q_delivered + Q_internal = (UA_env + G_vent) * (T_zone - T_out)
%         and the loop must hold  T_zone ~ setpoint.  (Steady-state energy
%         balance; ASHRAE Handbook-Fundamentals Ch. 18-19; the HX itself is
%         validated separately in validate_heat_exchanger, the network in
%         validate_hydraulic_network.)
%     (2) MULTI-ZONE HEAT-SPLIT CONSERVATION.  For a multi-zone DHS.Building the
%         per-zone delivered heat  Q_del,z = Q_del_total * w_z / sum(w_z)  with
%         weights  w_z = area_z * max(0, setpoint_z - T_zone,z) .  When at least
%         one zone is below its setpoint (sum(w_z) > 0) two properties must hold
%         every step:  sum_z Q_del,z == Q_del_total (nothing created or lost in
%         the split), and Q_del,z >= 0 with more heat to the colder / larger
%         zones.  (When no zone is below setpoint the building has zero heating
%         demand and the split is not exercised -- see note below.)
%     (3) HX WRAPPER CONSISTENCY.  DHS.Building.exchange(mdot, Tsup) must return
%         exactly what heatExchanger() returns for the same arguments (the
%         secondary-return temperature is T_zone + secApproach).
%
%   WHY THIS TEST IS GOOD
%     (1) is an end-to-end check that the per-step assembly (prepare -> control
%     -> hydraulic solve -> exchange -> advance) drives the wrapped RC model to
%     the physically correct steady state, i.e. the node injection signs, the
%     valve->flow->heat chain and the loop are all right. (2) is the invariant
%     the multi-zone extension must not break. (3) checks the thin wrapper adds
%     nothing spurious.
%
%   Run:  >> V = validate_desBuilding
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));

    % ================= (1) single-zone closed-loop equilibrium =================
    %   A small building on a minimal district loop. Realistic (small) envelope
    %   resistances so the steady state is physical, moderate capacitances so it
    %   is reached within the run, and a properly-sized substation so the valve
    %   settles mid-stroke (proving it has authority over the primary flow).
    Rw = 0.02/12;  Rr = 0.04/12;  Rwin = 0.03/12;  Rinf = 0.05/12;
    UAenv = 1/Rw + 1/Rr + 1/Rwin + 1/Rinf;                          % ~1540 W/K
    Gvent = 1400;  Qint = 45000;  Tout = -12;  sp = 21;

    B = RCBS.Building(); B.addStorey('S'); B.S.addZone('Z','C_main',1e7);
    B.S.Z.setAir(1e7, 18);
    B.S.Z.addInternalMass(5e-3, 2e7, 18, 'IntMass');
    B.S.Z.addWall(Rw, 1e7, 18, 'Wall');   B.S.Z.addRoof(Rr, 5e6, 18, 'Roof');
    B.S.Z.addWindow(Rwin, 'Window');      B.S.Z.addWindow(Rinf, 'InfVent');

    t0  = datetime(2025,1,6);                                       % a Monday
    csv = writeConstantWeather(t0, 3, Tout, 8);                      % constant boundary conditions
    cleanup = onCleanup(@() delete(csv));

    sys = DHS.System('weather', csv, 'startDate', t0, 'timeStep', seconds(60));
    chp = sys.addCentralHeatPlant('CHP');
    chp.addBoiler('B','QMax',2e6);
    chp.addPump('P','dp0',1.0e5,'mdotMax',6);
    chp.setSupplySetpoint(75);
    hn  = sys.addHydraulicNetwork();
    t1  = hn.addJunction('T1');
    hn.addPipe(chp.supplyPort, t1, 'L',8, 'D',0.10);                % short fat main: negligible trunk loss

    b = sys.addBuilding('Test');
    b.useRCModel(B);
    b.GventOcc = Gvent;  b.freeCool = false;  b.connLength = 15;  b.connD = 0.03;  b.Kminor = 8;
    hx = b.addHeatExchanger('HX','UA',8e3,'Qcap',2e5,'mdotSecNom',1.2,'secApproach',15);
    hx.valve.Kvs = 4;  hx.pump.dp0 = 2e4;  hx.pump.mdotMax = 1.5;  hx.pump.minSpeed = 0.1;
    hx.valve.attachController( DHS.controllers.PID(0.15, 1.6e-4, 0, 40) );
    b.attachSolar( DHS.Solar() );                                   % no glazing -> zero solar
    b.attachSchedule( fixedSchedule(sp, Qint) );
    hn.connectBuilding(t1, b);

    res = sys.run(days(2));                                         % 48 h ~ 10 time constants -> steady

    tail = @(v) mean(v(end-200:end));
    Tz  = res.bldg(1).Tzone(end);
    Qd  = tail(res.bldg(1).Qdeliv);
    mdE = tail(res.bldg(1).mdot);  vE = tail(res.bldg(1).valve);
    balRes  = abs((Qd + Qint) - (UAenv + Gvent)*(Tz - Tout)) / (Qd + Qint);
    trackErr = abs(Tz - sp);
    % the valve must actually be modulating (not pinned open/shut) -- proves authority
    valveModulates = vE > 0.02 && vE < 0.98;

    % ================= (2) multi-zone heat-split conservation =================
    sys2 = DHS.examples.campus_multizone();
    bm  = sys2.buildings{3};                                        % Science
    sys2.compile();
    dt = 60;
    bm.bindClock(sys2.startDate, seconds(dt), @(t) -5);  bm.reset(dt);
    wx2 = struct('ghi',50,'dhi',30,'dni',0,'sunZen',80,'sunAz',180,'sunEl',10,'albedo',0.2, ...
                 'Tout',-5,'Tground',4);
    splitResid = 0;  negFound = false;  Qtot_sample = 0;  nSplit = 0;
    for k = 1:400
        t = sys2.startDate + seconds(dt*(k-1));
        bm.prepare(t, wx2);
        bm.control(dt, wx2);
        bm.exchange(6, 70);
        Qtot = bm.Qdel;
        A   = [bm.zones.area];
        w   = A .* max(0, bm.mz.Tsp - bm.mz.Tz);
        bm.advance(dt, t + seconds(dt), wx2);
        Qz  = bm.mz.Qdel;                                           % per-zone delivered heat
        if abs(Qtot) > 1 && sum(w) > eps
            splitResid = max(splitResid, abs(sum(Qz) - Qtot) / abs(Qtot));
            Qtot_sample = Qtot;  nSplit = nSplit + 1;
        end
        if any(Qz < -1e-9), negFound = true; end
    end

    % ================= (3) HX wrapper consistency =================
    b3 = DHS.Building('W');  b3.useRCModel(trivialRC());
    hx3 = b3.addHeatExchanger('HX','UA',3e4,'Qcap',4e5,'mdotSecNom',5,'secApproach',12);
    b3.attachSolar(DHS.Solar()); b3.attachSchedule(DHS.Schedule());
    b3.bindClock(datetime(2025,1,1), seconds(60), @(t) 0);  b3.reset(60);
    b3.prepare(datetime(2025,1,1), struct('ghi',0,'dhi',0,'dni',0,'sunZen',120,'sunAz',0,'sunEl',-30,'albedo',0.2,'Tout',0,'Tground',4));
    Tz3 = b3.zoneTemp();
    [Qw, Trw] = b3.exchange(3.5, 68);
    [Qref, TrwRef] = heatExchanger(3.5, 68, Tz3 + hx3.secApproach, hx3.UA, hx3.mdotSecNom*hx3.cp, hx3.Qcap, hx3.cp);
    eWrap = max(abs(Qw - Qref), abs(Trw - TrwRef)) / max(abs(Qref), eps);

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(1) = mk('(1) closed-loop steady heat balance  residual',   0, balRes, 5e-3, 'abs');
    C(2) = mk('(1) closed-loop zone temp vs setpoint  [degC]',   0, trackErr, 0.30, 'abs');
    C(3) = mk('(1) valve modulates (0 < pos < 1) -> has authority',1, double(valveModulates), 0, 'abs');
    C(4) = mk('(2) multi-zone split conserves  sum(Qz) = Qtotal', 0, splitResid, 1e-9, 'abs');
    C(5) = mk('(2) no negative per-zone delivered heat',         0, double(negFound), 0, 'abs');
    C(6) = mk('(3) exchange() == heatExchanger() for same args', 0, eWrap, 1e-12, 'abs');
    V.name = 'DHS.Building: closed-loop energy balance + multi-zone heat-split conservation';
    V.passed = vtable(V.name, C);
    V.cases = C;  V.detail = struct('Tz',Tz,'Qd',Qd,'mdot',mdE,'valve',vE,'balRes',balRes, ...
                                    'trackErr',trackErr,'splitResid',splitResid, ...
                                    'nSplit',nSplit,'Qtot_sample',Qtot_sample,'eWrap',eWrap);

    th   = hours(res.time - res.time(1));
    Qan  = ((UAenv + Gvent)*(sp - Tout) - Qint) * ones(size(th));   % zone first law at the setpoint -> steady delivered heat
    vplot(mfilename, { ...
        struct('title','Zone temperature in closed loop', 'xlabel','time  [h]', 'ylabel','zone temperature  [\circC]', 'legendLoc','southoutside', ...
            'series',{{ struct('x',th,'y',res.bldg(1).setpoint,'name','setpoint','style','ref'), ...
                        struct('x',th,'y',res.bldg(1).Tzone,'name','DHS.System run','style','sim') }}), ...
        struct('title','Heat delivered to the building', 'xlabel','time  [h]', 'ylabel','heat  [kW]', 'legendLoc','southoutside', ...
            'series',{{ struct('x',th,'y',Qan/1e3,'name','steady zone heat balance','style','ref'), ...
                        struct('x',th,'y',res.bldg(1).Qdeliv/1e3,'name','heat exchanger','style','sim') }}) }, plotMode);
end

% ---------------------------------------------------------------------------
function path = writeConstantWeather(startDate, nDays, Tout, Tground)
% Write a Solcast-style CSV with constant boundary conditions (no sun, flat
% outdoor + ground temperature) spanning [startDate, startDate+nDays], so a
% DHS.System run reaches a clean, analysable steady state.
    tt  = (startDate : hours(1) : startDate + days(nDays)).';
    n   = numel(tt);
    pe  = string(datetime(tt, 'Format', 'yyyy-MM-dd''T''HH:mm:ss')) + "-08:00";
    z   = zeros(n,1);
    T = table(pe, z, z, z, 120+z, 0+z, 0.2+z, Tout+z, Tground+z, ...
        'VariableNames', {'period_end','ghi','dhi','dni','zenith','azimuth', ...
                          'albedo','t_outdoor_C','t_ground_C'});
    path = [tempname '.csv'];
    writetable(T, path);
end

function s = fixedSchedule(sp, gW)
    s = DHS.Schedule('occStartHour',0,'occEndHour',24,'Tocc',sp,'Tsetback',sp, ...
                     'weekendOccupied',true,'weekendStartHour',0,'weekendEndHour',24, ...
                     'rampHours',0,'gainOccW',gW,'gainBaseW',gW,'gainMassFraction',0);
end

function B = trivialRC()
    B = RCBS.Building(); B.addStorey('S'); B.S.addZone('Z','C_main',2e6);
    B.S.Z.setAir(2e6, 20);
    B.S.Z.addWindow(1.0, 'Window');  B.S.Z.addWindow(1.5, 'InfVent');
end

function s = mk(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
