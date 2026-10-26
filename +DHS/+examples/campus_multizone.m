function sys = campus_multizone(varargin)
%DHS.EXAMPLES.CAMPUS_MULTIZONE  The 5-building campus, but with MULTI-ZONE buildings.
%
%   sys = DHS.examples.campus_multizone()
%
%   Same central heat plant and distribution network as DHS.examples.campus, but
%   every building's RC model has several thermal zones instead of one:
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

    boiler1 = chp.addBoiler('B1', 'QMax', 2.0e6, 'etaRef', 0.92, 'etaSlope', 0.0025, ...
        'TetaRef', 50, 'etaMin', 0.80, 'etaMax', 0.98);
    pump0 = DHS.Hydraulic.CentrifugalPump('P0', 'dp0', 6.0e5, 'mdotRated',10);
    chp.attachPump(pump0);
    boiler1.connectTo(pump0);

    % the boiler's controller holds the supply temperature at its setpoint
    firing = DHS.controllers.PID(0.045, 3e-5, 1.5, 150);
    firing.name = 'CHP-firingPID';
    firing.measure   = @(sys) sys.plant.TsupplyMeas;
    firing.reference = @(sys) sys.plant.TsupSet;
    boiler1.attachController(firing);

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
    % Lengths of the pipes of each building's internal loop [m]; the totals are about 0.2 m of pipe per m2
    % of floor, as in a radiator system with an air handling unit (7,400, 11,700, 14,000, 19,200 and 3,400 m2).
    %             exchanger  pump to    supply main   return main   branch to a   bypass
    %             to pump    1st tee    between tees  per zone      radiator
    %                                   (per zone)                  (each way)
    loopLen = [      75         75          130           130          28          75;      % Administration, 4 zones, 1,490 m
                    115        115          135           135          29         115;      % Arts, 6 zones, 2,310 m
                    140        140          122           122          26         140;      % Science, 8 zones, 2,790 m
                    190        190          170           170          36         190;      % Engineering, 8 zones, 3,870 m
                     35         35           60            60          13          35 ];    % Library, 4 zones, 690 m

    % wired one component at a time with addPipe / addTee (see DHS.examples.campus)
    order  = [1 5 2 3 4];                   % build order -> distance order (Admin,Lib,Arts,Sci,Eng)
    segLen = [40 30 20 40 40];
    Dmain  = 0.11;
    outlet = chp.supplyPort;
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
        hx = b.addHeatExchanger('HX', ...
            'UA', 2.0*Qpk/22, 'Qcap', 1.8*Qpk, ...
            'dpNomPrimary', dpNomPrimary(i), 'mdotNomPrimary', mdotNomPrimary(i));
        hx.valve.Kvs = 1.3*Kvs(i);  hx.valve.char = 'eqpct';  hx.valve.rangeability = 50;
        % internal loop: exchanger -> pipe -> pump -> pipe -> one tee per zone (portC: valve -> radiator,
        % portB: on to the next tee) -> bypass; a return main collects the radiators back to the exchanger
        % 100 mm mains with the lengths of loopLen, insulated pipes inside the building (UperM 0.15 W/m/K).
        mdotLoop = Qpk/(4186*20);                             % design flow of the whole loop [kg/s]
        Dm   = 0.10;                                          % loop main diameter [m]
        L    = loopLen(i,:);  nZ = numel(zinfo);              % feed, pump to tee, supply seg, return seg, branch, bypass [m]
        % loop pump: 1.5 x the design flow (the radiators' plus what the bypass takes), shut-off head 1.6 x
        % the head that pushes all of it through the mains and the bypass with the zone valves shut
        Mref  = 1.5 * mdotLoop;
        Kmain = DHS.Hydraulic.Pipe('mains', 'L',L(1)+L(2)+nZ*(L(3)+L(4)), 'D',Dm).resistance(Mref, 983, 4.7e-4);
        Kbyp  = 1.2e4 / (0.5*mdotLoop)^2;
        loopPump = hx.internalOutlet.addPipe(Dm, L(1), 'UperM',0.15).addPump( ...
            'dp0',1.6*(Kmain + Kbyp)*Mref^2, 'mdotRated',Mref, 'name','loopPump');
        feed = loopPump.addPipe(Dm, L(2), 'UperM',0.15);      % end of the supply main so far
        rjPrev = hx.internalInlet;                            % end of the return main so far

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

            % this zone's radiator, sized for the zone's peak load, and its valve; both hang on a tee of the loop
            rad = DHS.Radiator(matlab.lang.makeValidName(['Rad_' zi.key]), ...
                'Qdes', max(500, (zi.UA_design + zi.Gvent_occ)*(21 - (-15))), 'Tsup', 60, 'Tret', 40);
            zk = strsplit(zi.key, '.');
            rad.connect(rcB.(zk{1}).(zk{2}));                 % the radiator heats this zone
            zTee      = feed.addTee(rad.pipeD);
            zoneValve = zTee.portC.addValve('Kvs',DHS.Hydraulic.Valve.kvsFor(rad.mdotDes, 5e3), 'char','linear', 'minPos',1e-3, 'name',['Valve_' rad.name]);
            zoneValve.addPipe(rad.pipeD, L(5), 'UperM',0.15).connect(rad);
            rj = DHS.Hydraulic.Junction(sprintf('%s.ret%d', name, z), 'return');
            rad.addPipe(rad.pipeD, L(5), 'UperM',0.15).connect(rj);
            rj.addPipe(Dm, L(4), 'UperM',0.15).connect(rjPrev);
            rjPrev = rj;
            feed = zTee.portB.addPipe(Dm, L(3), 'UperM',0.15);   % the supply main goes on to the next zone
            zonePID = DHS.controllers.PID(0.6, 2e-3, 0);      % the zone valve holds the zone temperature
            zonePID.name = [rad.name '-valvePID'];
            zonePID.measure   = @(sys) rad.Tzone;
            zonePID.reference = @(sys) rad.setpoint;
            zoneValve.attachController(zonePID);
        end
        % the end of the supply main is a bypass: the pipe's valve joins the last return junction
        feed.L = L(6);                                        % the pipe after the last tee is the bypass pipe
        bypassValve = feed.addValve('Kvs',DHS.Hydraulic.Valve.kvsFor(0.5*mdotLoop, 1.2e4), 'char','linear', 'name','bypassValve');
        bypassValve.connect(rjPrev);
        flowPID = DHS.controllers.PID('Kp',0.03/mdotLoop, 'Ki',0.002/mdotLoop, 'uMin',0.3);
        flowPID.name = [name '-flowPID'];
        flowPID.measure   = @(sys) b.mdotInt;
        flowPID.reference = 1.5*mdotLoop;            % the radiators' design flow plus what the bypass takes
        loopPump.attachController(flowPID);          % the loop pump holds the internal mass flow
        % the district valve holds the internal supply temperature (exchanger internal outlet)
        supPID = DHS.controllers.PID(0.02, 4e-5, 0);
        supPID.name = [name '-supplyPID'];
        supPID.measure   = @(sys) b.TintSup;
        supPID.reference = 60;
        hx.valve.attachController(supPID);

        tee{i}.portC.connect(b);                       % the building hangs on its tee's side port
        b.connect(retJ{i});                            % and drains into its return junction
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

