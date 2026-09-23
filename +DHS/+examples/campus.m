function sys = campus(varargin)
%DHS.EXAMPLES.CAMPUS  Build the 5-building UBCO-style campus as a DHS.System.
%
%   sys = DHS.examples.campus()
%   sys = DHS.examples.campus('weatherCsv', '...', 'startDate', datetime(2025,1,1))
%
%   Builds, through the +DHS assembly API, a campus with one central gas heat
%   plant, a branching supply/return main, and five buildings (Administration,
%   Arts, Science, Engineering, Library) each with an RCBS thermal model, a
%   plate heat exchanger + control valve + primary pump, a solar model and a
%   weekly occupancy schedule.
%
%   The plant and the supply main are wired PORT BY PORT here -- a pipe is
%   built, its input is connected, its output is connected, the same way a
%   zone wires its walls in +RCBS. DHS.HydraulicNetwork also accepts the
%   declarative style (hn.addPipe(nodeA,nodeB,...)) if you prefer it; both
%   produce the identical network.
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

    boiler1 = chp.addBoiler('B1', 'QMax', 1.5e6, ...
        'etaRef', 0.92, 'etaSlope', 0.0025, 'TetaRef', 50, 'etaMin', 0.80, 'etaMax', 0.98);
    pump0 = DHS.Hydraulic.CentrifugalPump('P0', 'dp0', 3.0e5, 'mdotMax', 14);
    chp.attachPump(pump0);
    boiler1.connectTo(pump0);
    chp.attachFiringController( DHS.controllers.PID(0.045, 3e-5, 1.5, 150) );
    chp.firingController.name = 'CHP-firingPID';

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
    mdotNomPrimary= [ 3.5   4.5   5.0   6.0   2.0 ];  % ... at this primary design flow [kg/s]
    pDp0          = [0.8e5 0.9e5 0.9e5 1.1e5 0.6e5];
    pMdot         = [ 3.5   4.5   5.0   6.0   2.0 ];

    % supply main: one T-junction per building, ordered by distance from the
    % plant, wired one pipe at a time -- build it, connect its input, connect
    % its output, and the T-junction's own run/branch loss is picked up
    % automatically wherever a pipe leaves its portB or portC (see
    % DHS.Hydraulic.TJunction)
    %   Admin 40 m, Library 70 m, Arts 90 m, Science 130 m, Engineering 170 m
    order   = [1 5 2 3 4];                       % build order -> distance order
    segLen  = [40 30 20 40 40];                  % plant->T1, T1->T2, ... segment lengths [m]
    Dmain   = 0.11;
    outlet  = chp.supplyPort;
    tee = cell(1,5);
    for kk = 1:5
        bi   = order(kk);
        trunkPipe = DHS.Hydraulic.Pipe(sprintf('trunk%d', kk), 'L',segLen(kk), 'D',Dmain, 'UperM',0.30);
        outlet.connectToPipe(trunkPipe);
        tee{bi} = DHS.Hydraulic.TJunction(['T_' B{bi,1}], 'mainDiameter',Dmain, 'sideDiameter',connD(bi));
        trunkPipe.connectOutput(tee{bi});
        outlet = tee{bi};
    end

    Tinit = 20;
    for i = 1:size(B,1)
        name = B{i,1}; Af = B{i,2}; ns = B{i,3}; h = B{i,4}; WWR = B{i,5};
        Ln = B{i,6};   Le = B{i,7}; constr = B{i,8}; gW = B{i,9}; occ = B{i,10};

        C    = construction(constr);
        geom = rc_from_geometry(Af, ns, h, WWR, Ln, Le, C, Tinit);
        Qpk  = (geom.UA_total + geom.rc.Gvent_occ) * (21 - (-15));

        b = sys.addBuilding(name);
        b.useRCModel( rcBuildingFromRc(geom.rc) );
        b.GventOcc = geom.rc.Gvent_occ;
        b.connD = connD(i);  b.connLength = 20;  b.Kminor = 8;

        hx = b.addHeatExchanger([name '.HX'], ...
            'UA', 1.6*Qpk/22, 'Qcap', 1.5*Qpk, ...
            'mdotSecNom', max(1.5, Qpk/(4186*22)), 'secApproach', 28, ...
            'dpNomPrimary', dpNomPrimary(i), 'mdotNomPrimary', mdotNomPrimary(i));
        hx.valve.Kvs = Kvs(i);  hx.valve.char = 'eqpct';  hx.valve.rangeability = 50;
        pump = DHS.Hydraulic.CentrifugalPump([name '.pump'], ...
            'dp0', pDp0(i), 'mdotMax', pMdot(i), 'minSpeed', 0.25);
        hx.attachPump(pump);
        hx.valve.attachController( DHS.controllers.PID(0.14, 1.6e-4, 0, 40) );
        hx.valve.controller.name = [name '-valvePID'];

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

        hn.connectBuilding(tee{i}, b);
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
