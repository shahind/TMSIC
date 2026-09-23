function sys = campus_multizone(varargin)
%DHS.EXAMPLES.CAMPUS_MULTIZONE  The 5-building campus, but with MULTI-ZONE buildings.
%
%   sys = DHS.examples.campus_multizone()
%
%   Same central heat plant and distribution network as DHS.examples.campus, but
%   every building's RC model is now several thermal zones instead of one:
%
%     * each storey is split into a LARGER zone (60 % of the footprint) and a
%       SMALLER zone (40 %);
%     * the two zones on a storey are coupled by an interior PARTITION WALL
%       (a capacitive R/2-C-R/2 element, RCBS.Zone.connectToZone with a mid mass);
%     * a zone is coupled to the zone directly above / below it by a FLOOR/CEILING
%       SLAB (its ceiling is the other's floor) -- also a capacitive element;
%     * each zone is given the thermal character of a room type -- classroom,
%       lecture hall, office, study room, lab, dining, lobby -- with its own
%       internal-gain density, occupancy schedule, ventilation rate, setpoint,
%       glazing ratio and thermal mass.
%
%   One district substation feeds each building. Its control loop regulates the
%   area-weighted mean zone temperature; the delivered heat is split between the
%   zones in proportion to each zone's current heating demand. Ventilation and
%   free-cooling are per zone.
%
%   res = sys.run(days(14));  res.bldg(i).Tzones is nt x nZones, res.bldg(i).zoneNames.

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

    % ---------- central heat plant (identical to DHS.examples.campus) ----------
    chp = sys.addCentralHeatPlant('CHP');
    chp.Cw = 8.0e7;  chp.Cw_rh = 4.0e6;  chp.Cw_sh = 5.0e6;
    chp.mdotMinBoiler = 2.5;  chp.TboilerMax = 90;  chp.standbyLossW = 10e3;
    chp.sensorTau = 20;  chp.firingSlewPerMin = 0.15;
    chp.setSupplySetpoint(70);

    boiler1 = chp.addBoiler('B1', 'QMax', 1.5e6, 'etaRef', 0.92, 'etaSlope', 0.0025, ...
        'TetaRef', 50, 'etaMin', 0.80, 'etaMax', 0.98);
    pump0 = DHS.Hydraulic.CentrifugalPump('P0', 'dp0', 3.0e5, 'mdotMax', 14);
    chp.attachPump(pump0);
    boiler1.connectTo(pump0);
    chp.attachFiringController( DHS.controllers.PID(0.045, 3e-5, 1.5, 150) );
    chp.firingController.name = 'CHP-firingPID';

    % ---------- distribution network (identical to DHS.examples.campus) ----------
    hn = sys.addHydraulicNetwork();
    hn.pReturnRef = 1.5e5;  hn.rho = 978;  hn.mu = 4.0e-4;

    %            name          Af    ns  h    Ln    Le  construction  layout key
    B = { ...
      'Administration', 3700, 2, 3.6, 55, 106, 'oldBrick', 'admin'; ...
      'Arts',           3900, 3, 3.6, 77,  95, 'oldBrick', 'arts';  ...
      'Science',        3500, 4, 3.6, 74,  74, 'oldBrick', 'science';...
      'Engineering',    4800, 4, 3.7, 80, 110, 'newGlass', 'eng';   ...
      'Library',        1700, 2, 3.6, 64,  50, 'oldBrick', 'library' ...
    };
    connD          = [0.045 0.050 0.050 0.055 0.036];
    Kvs            = [ 14    18    20    26    8  ];
    dpNomPrimary   = [30e3  35e3  35e3  40e3  25e3];   % HX-body design pressure drop [Pa]
    mdotNomPrimary = [ 3.5   4.5   5.0   6.0   2.0 ];  % ... at this primary design flow [kg/s]
    pDp0   = [0.8e5 0.9e5 0.9e5 1.1e5 0.6e5];
    pMdot  = [ 3.5   4.5   5.0   6.0   2.0 ];

    % wired port-by-port, one pipe at a time (see DHS.examples.campus)
    order  = [1 5 2 3 4];                   % build order -> distance order (Admin,Lib,Arts,Sci,Eng)
    segLen = [40 30 20 40 40];
    Dmain  = 0.11;
    outlet = chp.supplyPort;
    tee = cell(1,5);
    for kk = 1:5
        bi = order(kk);
        trunkPipe = DHS.Hydraulic.Pipe(sprintf('trunk%d', kk), 'L',segLen(kk), 'D',Dmain, 'UperM',0.30);
        outlet.connectToPipe(trunkPipe);
        tee{bi} = DHS.Hydraulic.TJunction(['T_' B{bi,1}], 'mainDiameter',Dmain, 'sideDiameter',connD(bi));
        trunkPipe.connectOutput(tee{bi});
        outlet = tee{bi};
    end

    Tinit = 20;
    for i = 1:size(B,1)
        name = B{i,1}; Af = B{i,2}; ns = B{i,3}; h = B{i,4};
        Ln = B{i,5};   Le = B{i,6}; constr = B{i,7};
        C  = construction(constr);
        layout = roomLayout(B{i,8}, ns);          % 2 x ns cell of room-type names

        [rcB, zinfo] = makeMultiZoneRC(ns, Af, h, Ln, Le, C, layout, Tinit);

        Qpk = 0;
        for z = 1:numel(zinfo)
            Qpk = Qpk + (zinfo(z).UA_design + zinfo(z).Gvent_occ) * (21 - (-15));
        end

        b = sys.addBuilding(name);
        b.useRCModel(rcB);
        b.connD = connD(i);  b.connLength = 20;  b.Kminor = 8;

        % HX sized with extra headroom: one substation must cover several zones
        % with different loads (high-ventilation labs, high-gain dining, ...)
        hx = b.addHeatExchanger([name '.HX'], ...
            'UA', 2.0*Qpk/22, 'Qcap', 1.8*Qpk, ...
            'mdotSecNom', max(2.0, 1.3*Qpk/(4186*22)), 'secApproach', 28, ...
            'dpNomPrimary', dpNomPrimary(i), 'mdotNomPrimary', mdotNomPrimary(i));
        hx.valve.Kvs = 1.3*Kvs(i);  hx.valve.char = 'eqpct';  hx.valve.rangeability = 50;
        pump = DHS.Hydraulic.CentrifugalPump([name '.pump'], ...
            'dp0', pDp0(i), 'mdotMax', 1.3*pMdot(i), 'minSpeed', 0.25);
        hx.attachPump(pump);
        hx.valve.attachController( DHS.controllers.PID(0.14, 1.6e-4, 0, 40) );
        hx.valve.controller.name = [name '-valvePID'];

        for z = 1:numel(zinfo)
            zi = zinfo(z);  rf = roomFeatures(zi.roomType);
            % glazing spread over the four orientations by facade length
            fN = Ln/(Ln+Le)/2;  fE = Le/(Ln+Le)/2;
            wa = zi.winArea * [fN fE fN fE];
            if strcmp(zi.roomType,'lobby'), wa = zi.winArea*[0.10 0.15 0.55 0.20]; end
            b.attachZone(zi.key, ...
                'area', zi.area, 'roomType', zi.roomType, ...
                'solar', DHS.Solar('winArea', struct('N',wa(1),'E',wa(2),'S',wa(3),'W',wa(4)), ...
                                   'SHGC', C.SHGC, 'massFraction', rf.radiant), ...
                'schedule', DHS.Schedule('occStartHour',rf.occ(1),'occEndHour',rf.occ(2), ...
                     'rampHours',1,'weekendOccupied',logical(rf.occ(3)), ...
                     'weekendStartHour',10,'weekendEndHour',18, ...
                     'Tocc',rf.Tocc,'Tsetback',rf.Tset, ...
                     'gainOccW', rf.gW*zi.area, 'gainMassFraction', rf.radiant), ...
                'GventOcc', zi.Gvent_occ, 'Ginf', zi.Ginf);
        end

        hn.connectBuilding(tee{i}, b);
    end
end

% ======================================================================
function layout = roomLayout(key, ns)
% 2 x ns cell: row 1 = larger (60%) zone type, row 2 = smaller (40%) zone type
    switch key
        case 'admin'                    % 2 storeys
            L = {'lobby','office'; 'office','study'};
        case 'arts'                     % 3 storeys
            L = {'lobby','dining'; 'classroom','office'; 'lecture','study'};
        case 'science'                  % 4 storeys
            L = {'lobby','office'; 'lab','classroom'; 'lab','classroom'; 'lab','office'};
        case 'eng'                      % 4 storeys
            L = {'lobby','dining'; 'lab','office'; 'lab','classroom'; 'office','study'};
        case 'library'                  % 2 storeys
            L = {'study','lobby'; 'study','office'};
        otherwise
            error('DHS:examples:campus_multizone:layout', 'Unknown layout "%s".', key);
    end
    layout = L(1:ns, :).';               % -> 2 x ns  (row 1 big, row 2 small)
end

% ----------------------------------------------------------------------
function rf = roomFeatures(type)
% Thermal character of a room type.
%   gW    diversified internal-gain density when occupied      [W/m^2]
%   occ   [occStartHour  occEndHour  weekendOccupied(0/1)]
%   vent  mechanical outdoor-air change when occupied, net of HRV  [1/h]
%   Tocc / Tset  occupied / setback heating setpoint            [degC]
%   WWR   window-to-(zone-)wall ratio                            [-]
%   mass  thermal-mass multiplier on C_air / C_mass             [-]
%   radiant  radiant fraction of gains / solar to the mass node [-]
    T = struct( ...
      'classroom', struct('gW',24,'occ',[8 17 0],'vent',1.3,'Tocc',21,'Tset',17,'WWR',0.28,'mass',1.00,'radiant',0.30), ...
      'lecture',   struct('gW',30,'occ',[9 20 0],'vent',1.6,'Tocc',21,'Tset',17,'WWR',0.22,'mass',1.00,'radiant',0.35), ...
      'office',    struct('gW',12,'occ',[8 18 0],'vent',0.5,'Tocc',21,'Tset',18,'WWR',0.35,'mass',0.90,'radiant',0.30), ...
      'study',     struct('gW',15,'occ',[7 22 1],'vent',0.6,'Tocc',21,'Tset',19,'WWR',0.32,'mass',1.00,'radiant',0.30), ...
      'lab',       struct('gW',22,'occ',[8 20 0],'vent',2.2,'Tocc',21,'Tset',18,'WWR',0.18,'mass',0.80,'radiant',0.25), ...
      'dining',    struct('gW',38,'occ',[11 14 1],'vent',2.6,'Tocc',20,'Tset',18,'WWR',0.35,'mass',0.70,'radiant',0.25), ...
      'lobby',     struct('gW', 6,'occ',[6 22 1],'vent',0.4,'Tocc',21,'Tset',19,'WWR',0.55,'mass',0.50,'radiant',0.20) );
    assert(isfield(T,type), 'DHS:examples:campus_multizone:roomType', 'Unknown room type "%s".', type);
    rf = T.(type);
end

% ======================================================================
function C = construction(key)
    switch key
        case 'oldBrick'
            C.Uw=0.35; C.Ur=0.16; C.Uwin=1.10; C.SHGC=0.44;
            C.ACH_inf=0.11; C.exposedWallFrac=0.55;
            C.kappa_wall=90e3; C.kappa_mass=100e3; C.kappa_roof=75e3; C.furn=5;
        case 'newGlass'
            C.Uw=0.26; C.Ur=0.13; C.Uwin=1.00; C.SHGC=0.32;
            C.ACH_inf=0.06; C.exposedWallFrac=0.60;
            C.kappa_wall=80e3; C.kappa_mass=95e3; C.kappa_roof=70e3; C.furn=5;
        otherwise
            error('DHS:examples:campus_multizone:construction', 'Unknown construction "%s".', key);
    end
end

% ======================================================================
function [B, zinfo] = makeMultiZoneRC(nS, footprint, h, Ln, Le, C, layout, Tinit)
% Build an RCBS.Building: nS storeys, each split into Big (60%) + Small (40%),
% coupled by partition walls (same storey) and floor/ceiling slabs (between storeys).
    rho_air = 1.2;  cp_air = 1005;
    h_ms = 9.1;  A_mass_ratio = 2.5;
    U_gslab = 0.10;  kappa_gslab = 180e3;      % ground-floor slab-on-grade: small,
                                               % heavily damped loss (couples to T_out
                                               % here -- a documented simplification,
                                               % RCBS has no ground node)
    U_slab  = 2.5;   kappa_slab  = 220e3;      % interior concrete deck between storeys
    U_part  = 2.0;   kappa_part  = 40e3;       % interior partition wall

    B = RCBS.Building();
    zinfo = struct('key',{},'area',{},'roomType',{},'winArea',{},'V',{}, ...
                   'UA_design',{},'Gvent_occ',{},'Ginf',{});
    share = [0.60 0.40];  zoneName = {'Big','Small'};

    Peri = 2*(Ln + Le) * C.exposedWallFrac;    % heat-losing wall perimeter of a storey

    for k = 1:nS
        s = sprintf('S%d', k);
        B.addStorey(s);
        for zz = 1:2
            rt = layout{zz, k};  rf = roomFeatures(rt);
            area  = share(zz) * footprint;
            V     = area * h;
            wallG = Peri * share(zz) * h;                 % gross exterior wall of this zone
            Awin  = rf.WWR * wallG;
            Awall = max(0, wallG - Awin);

            C_air  = rho_air*cp_air*V*C.furn*rf.mass;
            C_mass = C.kappa_mass * area * rf.mass;      R_mass = 1/(h_ms*A_mass_ratio*area);
            C_wall = C.kappa_wall * Awall;               R_wall = 1/(C.Uw   * max(Awall,1));
            R_win  = 1/(C.Uwin * max(Awin,1));
            Ginf   = C.ACH_inf * V * rho_air*cp_air/3600;  R_inf = 1/Ginf;
            Gvent  = rf.vent   * V * rho_air*cp_air/3600;

            zn = zoneName{zz};
            B.(s).addZone(zn, 'C_main', C_air);
            B.(s).(zn).setAir(C_air, Tinit);
            B.(s).(zn).addInternalMass(R_mass, C_mass, Tinit, 'IntMass');
            B.(s).(zn).addWall(R_wall, C_wall, Tinit, 'Wall');
            B.(s).(zn).addWindow(R_win, 'Window');
            B.(s).(zn).addWindow(R_inf, 'InfVent');
            if k == nS
                B.(s).(zn).addRoof(1/(C.Ur*area), C.kappa_roof*area, Tinit, 'Roof');
            end
            if k == 1
                B.(s).(zn).addWall(1/(U_gslab*area), kappa_gslab*area, Tinit, 'GroundSlab');
            end

            UA_design = C.Uw*Awall + C.Uwin*Awin + Ginf;
            if k == nS, UA_design = UA_design + C.Ur*area; end
            zinfo(end+1) = struct('key',[s '.' zn], 'area',area, 'roomType',rt, ...
                'winArea',Awin, 'V',V, 'UA_design',UA_design, ...
                'Gvent_occ',Gvent, 'Ginf',Ginf); %#ok<AGROW>
        end

        % interior partition between the two zones on this storey
        Apart = sqrt(footprint) * h;
        B.(s).Big.connectToZone(B.(s).Small, 1/(U_part*Apart), ...
            sprintf('part_%s', s), kappa_part*Apart, Tinit);
    end

    % floor/ceiling slabs: storey k ceiling  ==  storey k+1 floor
    for k = 1:nS-1
        sa = sprintf('S%d', k);  sb = sprintf('S%d', k+1);
        for zz = 1:2
            zn = zoneName{zz};
            A_slab = share(zz) * footprint;
            B.(sa).(zn).connectToZone(B.(sb).(zn), 1/(U_slab*A_slab), ...
                sprintf('slab_%s_%s', sa, zn), kappa_slab*A_slab, Tinit);
        end
    end
end
