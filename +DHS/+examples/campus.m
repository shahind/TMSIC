function sys = campus(varargin)
%DHS.EXAMPLES.CAMPUS  Build the 5-building UBCO-style campus as a DHS.System.
%
%   sys = DHS.examples.campus()
%   sys = DHS.examples.campus('weatherCsv', '...', 'startDate', datetime(2025,1,1))
%
%   Builds, through the +DHS assembly API, a campus with one central gas heat
%   plant, a branching supply/return main, and five buildings (Administration,
%   Arts, Science, Engineering, Library) each with an RCBS thermal model, a
%   plate heat exchanger + control valve, a solar model and a
%   weekly occupancy schedule.
%
%   The supply main is wired one component at a time with addPipe / addTee
%   and connect, and each building has an internal loop (pipe, pump, tee,
%   valve, radiator, bypass) wired the same way from the heat exchanger's
%   internal outlet to its internal inlet. DHS.HydraulicNetwork also accepts
%   the declarative style (hn.addPipe(nodeA,nodeB,...)) if you prefer it;
%   both produce the identical network.
%
%   The 14-day results (plant heat, zone temperatures, efficiency, energy
%   closure) should match the archived DES_results.mat; the distribution
%   pressures differ slightly because DHS models the supply main as a proper
%   trunk-and-branch tree rather than five independent radials.

    p = inputParser;
    p.addParameter('weatherCsv', fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'solar_data_2025.csv'));
    p.addParameter('startDate',  datetime(2025,1,1,0,0,0));
    p.addParameter('timeStep',   seconds(60));
    p.addParameter('couplingIterations', 2);
    p.parse(varargin{:});
    o = p.Results;

    sys = DHS.System('weather', char(o.weatherCsv), 'startDate', o.startDate, ...
        'timeStep', o.timeStep, 'couplingIterations', o.couplingIterations, ...
        'pumpFrac', 1, 'baseHeatW', 60e3);

    % ---------- central heat plant ----------
    chp = sys.addCentralHeatPlant('CHP');
    chp.Cw = 8.0e7;  chp.Cw_rh = 4.0e6;  chp.Cw_sh = 5.0e6;
    chp.mdotMinBoiler = 2.5;  chp.TboilerMax = 90;  chp.standbyLossW = 10e3;
    chp.sensorTau = 20;  chp.firingSlewPerMin = 0.15;
    chp.setSupplySetpoint(70);

    boiler1 = chp.addBoiler('B1', 'QMax', 2.0e6, ...
        'etaRef', 0.92, 'etaSlope', 0.0025, 'TetaRef', 50, 'etaMin', 0.80, 'etaMax', 0.98);
    pump0 = DHS.Hydraulic.CentrifugalPump('P0', 'dp0', 6.0e5, 'mdotRated',10);
    chp.attachPump(pump0);
    boiler1.connectTo(pump0);

    % the boiler's controller holds the supply temperature at its setpoint
    firing = DHS.controllers.PID(0.045, 3e-5, 1.5, 150);
    firing.name = 'CHP-firingPID';
    firing.measure   = @(sys) sys.plant.TsupplyMeas;
    firing.reference = @(sys) sys.plant.TsupSet;
    boiler1.attachController(firing);

    % ---------- distribution network ----------
    hn = sys.addHydraulicNetwork();
    hn.pReturnRef = 1.5e5;  hn.rho = 978;  hn.mu = 4.0e-4;

    %            name          Af    ns  h    WWR   Ln    Le  constr     gW  occ[s e wknd]
    B = { ...
      'Administration',      3700,  2, 3.6, 0.40,  55,  106, 'oldBrick',  8, [7 18 0]; ...
      'Arts',                3900,  3, 3.6, 0.30,  77,   95, 'oldBrick',  8, [7 19 0]; ...
      'Science',             3500,  4, 3.6, 0.30,  74,   74, 'oldBrick',  9, [7 20 0]; ...
      'Engineering',         4800,  4, 3.7, 0.40,  80,  110, 'newGlass',  9, [7 20 0]; ...
      'Library',             1700,  2, 3.6, 0.45,  64,   50, 'oldBrick', 10, [6 22 1]  ...
    };
    % per-building district equipment (Admin, Arts, Science, Engineering, Library)
    connD         = [0.045 0.050 0.050 0.055 0.036];
    Kvs           = [ 14    18    20    26    8  ];
    dpNomPrimary  = [30e3  35e3  35e3  40e3  25e3];   % HX-body design pressure drop [Pa]
    % Lengths of the pipes of each building's internal loop [m]; the totals are about 0.2 m of pipe per m2
    % of floor, as in a radiator system with an air handling unit (7,400, 11,700, 14,000, 19,200 and 3,400 m2).
    %               exchanger   pump to   branch to the     return    bypass
    %               to pump     the tee   radiator (each way) main
    loopLen       = [   75       520        75              665        70;      % Administration, 1,480 m
                       115       820       115             1055       120;      % Arts, 2,340 m
                       140       980       140             1260       140;      % Science, 2,800 m
                       190      1345       190             1730       195;      % Engineering, 3,840 m
                        35       240        35              305        30 ];    % Library, 680 m
    mdotNomPrimary= [ 3.5   4.5   5.0   6.0   2.0 ];  % ... at this primary design flow [kg/s]

    % supply main: one T-junction per building, ordered by distance from the
    % plant. Each trunk pipe is created at the end of the previous one with addPipe(D, L),
    % and the tee at its end with addTee(side diameter); the tee's run (portB) continues
    % the main, and its portC feeds a building. The T-junction's own run/branch loss is
    % picked up automatically wherever a pipe leaves its portB or portC.
    %   Admin 40 m, Library 70 m, Arts 90 m, Science 130 m, Engineering 170 m
    order   = [1 5 2 3 4];                       % build order -> distance order
    segLen  = [40 30 20 40 40];                  % plant->T1, T1->T2, ... segment lengths [m]
    Dmain   = 0.11;
    outlet  = chp.supplyPort;
    tee = cell(1,5);
    for kk = 1:5
        bi = order(kk);
        trunkPipe = outlet.addPipe(Dmain, segLen(kk), 'name',sprintf('trunk%d', kk), 'UperM',0.30);
        tee{bi}   = trunkPipe.addTee(connD(bi), 'name',['T_' B{bi,1}]);
        outlet    = tee{bi}.portB;
    end

    % return main: defined separately from the supply main -- its own junctions and pipes,
    % here the same lengths and diameter as the supply, each flowing toward the plant
    retJ = cell(1,5);
    for bi = 1:5
        retJ{bi} = DHS.Hydraulic.Junction(['R_' B{bi,1}], 'return');
    end
    for kk = 1:5                                 % built from the plant outward, like the supply main
        bi = order(kk);
        if kk == 1, dest = chp.returnPort; else, dest = retJ{order(kk-1)}; end
        retPipe = retJ{bi}.addPipe(Dmain, segLen(kk), 'name',sprintf('return%d', kk), 'UperM',0.30);
        retPipe.connect(dest);
    end

    % central pump speed holds the supply-return differential pressure at the last tee at 3 bar
    dpPID = DHS.controllers.PID('Kp',2.5e-7, 'Ki',2.1e-9, 'uMin',0.3);
    dpPID.name = 'P0-dpPID';
    dpPID.measure   = @(sys) tee{bi}.p - retJ{bi}.p;
    dpPID.reference = 3.0e5;
    pump0.attachController(dpPID);

    Tinit = 20;
    for i = 1:size(B,1)
        name = B{i,1}; Af = B{i,2}; ns = B{i,3}; h = B{i,4}; WWR = B{i,5};
        Ln = B{i,6};   Le = B{i,7}; constr = B{i,8}; gW = B{i,9}; occ = B{i,10};

        C    = construction(constr);
        geom = rc_from_geometry(Af, ns, h, WWR, Ln, Le, C, Tinit);
        Qpk  = (geom.UA_total + geom.rc.Gvent_occ) * (21 - (-15));

        b = sys.addBuilding(name);
        rcB = rcBuildingFromRc(geom.rc);
        b.useRCModel(rcB);
        b.GventOcc = geom.rc.Gvent_occ;
        b.connD = connD(i);  b.connLength = 20;  b.Kminor = 8;

        hx = b.addHeatExchanger('HX', ...
            'UA', 1.6*Qpk/22, 'Qcap', 1.5*Qpk, ...
            'dpNomPrimary', dpNomPrimary(i), 'mdotNomPrimary', mdotNomPrimary(i));
        hx.valve.Kvs = Kvs(i);  hx.valve.char = 'eqpct';  hx.valve.rangeability = 50;

        % internal loop, from the exchanger's internal outlet back to its internal inlet:
        %   pipe -> pump -> pipe -> tee (portC: valve -> pipe -> radiator -> pipe, portB: bypass) -> return junction -> pipe
        % 100 mm mains with the lengths of loopLen, insulated pipes inside the building (UperM 0.15 W/m/K).
        rad  = DHS.Radiator('Radiator', 'Qdes', Qpk, 'Tsup', 60, 'Tret', 40);
        rad.connect(rcB.S1.Z);                                % the radiator heats the zone
        L    = loopLen(i,:);                                  % feed, pump to tee, branch, return main, bypass [m]
        Dm   = 0.10;  Dz = rad.pipeD;                         % loop main and zone branch pipe diameters [m]
        % loop pump: the flow the radiator needs plus what the bypass takes, 1.5 x the design flow, and the
        % head to push all of it through the mains and the bypass with the zone valve shut (shut-off head 1.6 x that)
        Mref  = 1.5 * rad.mdotDes;
        Kmain = DHS.Hydraulic.Pipe('mains', 'L',L(1)+L(2)+L(4), 'D',Dm).resistance(Mref, 983, 4.7e-4);
        Kbyp  = 1.2e4 / (0.5*rad.mdotDes)^2;
        loopPump = hx.internalOutlet.addPipe(Dm, L(1), 'UperM',0.15).addPump( ...
            'dp0',1.6*(Kmain + Kbyp)*Mref^2, 'mdotRated',Mref, 'name','loopPump');
        loopTee = loopPump.addPipe(Dm, L(2), 'UperM',0.15).addTee(Dz);
        zoneValve = loopTee.portC.addValve('Kvs',DHS.Hydraulic.Valve.kvsFor(rad.mdotDes, 5e3), 'char','linear', 'minPos',1e-3, 'name','zoneValve');
        zoneValve.addPipe(Dz, L(3), 'UperM',0.15).connect(rad);
        retJloop = DHS.Hydraulic.Junction([name '.loopReturn'], 'return');
        rad.addPipe(Dz, L(3), 'UperM',0.15).connect(retJloop);
        retJloop.addPipe(Dm, L(4), 'UperM',0.15).connect(hx.internalInlet);
        bypassValve = loopTee.portB.addPipe(Dm, L(5), 'UperM',0.15).addValve('Kvs',DHS.Hydraulic.Valve.kvsFor(0.5*rad.mdotDes, 1.2e4), 'char','linear', 'name','bypassValve');
        bypassValve.connect(retJloop);                              % takes the water the zone valve does not
        % the zone valve holds the zone temperature at the schedule's setpoint
        zonePID = DHS.controllers.PID(0.6, 2e-3, 0);
        zonePID.name = [name '-zoneValvePID'];
        zonePID.measure   = @(sys) rad.Tzone;
        zonePID.reference = @(sys) rad.setpoint;
        zoneValve.attachController(zonePID);
        % the loop pump holds the internal mass flow
        flowPID = DHS.controllers.PID('Kp',0.03/rad.mdotDes, 'Ki',0.002/rad.mdotDes, 'uMin',0.3);   % pump speed from the flow error
        flowPID.name = [name '-flowPID'];
        flowPID.measure   = @(sys) b.mdotInt;
        flowPID.reference = 1.5*rad.mdotDes;           % the radiator's design flow plus what the bypass takes
        loopPump.attachController(flowPID);
        % the district valve holds the internal supply temperature (exchanger internal outlet)
        supPID = DHS.controllers.PID(0.02, 4e-5, 0);
        supPID.name = [name '-supplyPID'];
        supPID.measure   = @(sys) b.TintSup;
        supPID.reference = 60;
        hx.valve.attachController(supPID);

        % solar: glazing spread over 4 orientations from the real facade lengths
        fN = Ln/(Ln+Le)/2;  fE = Le/(Ln+Le)/2;
        waNESW = geom.Awin * [fN fE fN fE];
        if strcmp(name,'Library'), waNESW = geom.Awin*[0.12 0.18 0.50 0.20]; end
        b.attachSolar( DHS.Solar('winArea', ...
            struct('N',waNESW(1),'E',waNESW(2),'S',waNESW(3),'W',waNESW(4)), ...
            'SHGC', C.SHGC, 'massFraction', 0.12) );

        b.attachSchedule( DHS.Schedule( ...
            'occStartHour',occ(1),'occEndHour',occ(2),'rampHours',1, ...
            'weekendOccupied',logical(occ(3)),'weekendStartHour',10,'weekendEndHour',18, ...
            'Tocc',21,'Tsetback',18,'gainOccW', gW*Af*ns,'gainMassFraction',0.30) );

        tee{i}.portC.connect(b);                       % the building hangs on its tee's side port
        b.connect(retJ{i});                            % and drains into its return junction
    end
end

% ======================================================================
function C = construction(key)
    switch key
        case 'oldBrick'
            C.Uw=0.35; C.Ur=0.16; C.Uwin=1.10; C.SHGC=0.44;
            C.ACH_inf=0.11; C.ACH_vent=0.42; C.exposedWallFrac=0.55;
            C.kappa_wall=90e3; C.kappa_mass=100e3; C.kappa_roof=75e3; C.furn=5;
        case 'newGlass'
            C.Uw=0.26; C.Ur=0.13; C.Uwin=1.00; C.SHGC=0.32;
            C.ACH_inf=0.06; C.ACH_vent=0.50; C.exposedWallFrac=0.60;
            C.kappa_wall=80e3; C.kappa_mass=95e3; C.kappa_roof=70e3; C.furn=5;
        otherwise
            error('DHS:examples:campus:construction', 'Unknown construction "%s".', key);
    end
end

function g = rc_from_geometry(Af, ns, h, WWR, Ln, Le, C, Tinit)
    rho_air = 1.2;  cp_air = 1005;
    h_ms = 9.1;  A_mass_ratio = 2.5;
    AfTot = Af * ns;
    Peri  = 2*(Ln + Le) * C.exposedWallFrac;
    Awall_gross = Peri * h * ns;
    Awin  = WWR * Awall_gross;
    Awall = max(0, Awall_gross - Awin);
    Aroof = Af;
    V     = AfTot * h;
    Gwall = C.Uw   * Awall;
    Groof = C.Ur   * Aroof;
    Gwin  = C.Uwin * Awin;
    Ginf  = C.ACH_inf  * V * rho_air * cp_air / 3600;
    Gvent = C.ACH_vent * V * rho_air * cp_air / 3600;
    Gmass = h_ms * A_mass_ratio * AfTot;

    rc = struct();
    rc.Tinit  = Tinit;
    rc.Af     = AfTot;
    rc.Afoot  = Af;
    rc.V      = V;
    rc.Gvent_occ = Gvent;
    rc.C_air  = rho_air * cp_air * V * C.furn;
    rc.C_mass = C.kappa_mass * AfTot;   rc.R_mass = 1 / Gmass;
    rc.C_wall = C.kappa_wall * Awall;   rc.R_wall = 1 / Gwall;
    rc.C_roof = C.kappa_roof * Aroof;   rc.R_roof = 1 / Groof;
    rc.R_win  = 1 / Gwin;
    rc.R_inf  = 1 / Ginf;

    g.rc = rc;  g.Awin = Awin;  g.Awall = Awall;  g.Aroof = Aroof;
    g.V = V;    g.UA_total = Gwall + Groof + Gwin + Ginf;
end

function Bld = rcBuildingFromRc(rc)
    % standard single-zone RCBS building: air / internal mass / wall / roof
    T0 = 20;
    if isfield(rc,'Tinit') && ~isempty(rc.Tinit), T0 = rc.Tinit; end
    Bld = RCBS.Building();
    Bld.addStorey('S1');
    Bld.S1.addZone('Z', 'C_main', rc.C_air);
    Bld.S1.Z.setAir(rc.C_air, T0);
    Bld.S1.Z.addInternalMass(rc.R_mass, rc.C_mass, T0, 'IntMass');
    Bld.S1.Z.addWall(rc.R_wall, rc.C_wall, T0, 'Wall');
    Bld.S1.Z.addRoof(rc.R_roof, rc.C_roof, T0, 'Roof');
    Bld.S1.Z.addWindow(rc.R_win, 'Window');
    Bld.S1.Z.addWindow(rc.R_inf, 'InfVent');
end
