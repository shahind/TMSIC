classdef Building < dynamicprops
% DHS.BUILDING  One building connected to the district loop.
%
%   Wraps an RCBS thermal model (any RCBS.Building) and adds the district-side
%   equipment and the calculation of every heat flow that enters the RC nodes:
%
%     * a plate heat exchanger with its own primary control valve and pump
%       (DHS.HeatExchanger, obj.heatExchanger);
%     * a solar model (DHS.Solar) and an occupancy schedule (DHS.Schedule);
%     * occupied-hours mechanical ventilation and winter free-cooling terms.
%
%   RCBS stays a pure RC library: heat is computed HERE and injected into the
%   right RCBS node each step with RCBS.Simulation.stepOnce.
%
%   SINGLE-ZONE (the default)
%     b = sys.addBuilding('Engineering');
%     b.useRCModel( makeEngineeringRC() );                 % 1-zone RCBS.Building
%     hx = b.addHeatExchanger('HX', 'UA',3.5e4, 'Qcap',8e5);
%     c = DHS.controllers.PID(0.14, 1.6e-4, 0);
%     c.measure = @(sys) b.Tzone;  c.reference = @(sys) b.setpoint;
%     hx.valve.attachController(c);
%     b.attachSolar( DHS.Solar(...) );
%     b.attachSchedule( DHS.Schedule(...) );
%
%   MULTI-ZONE  (RCBS.Building with several zones -- storeys split into rooms,
%   coupled by partition walls and floor/ceiling slabs; see DHS.examples.campus_multizone)
%     b.useRCModel( makeMultiZoneRC() );                   % N-zone RCBS.Building
%     hx = b.addHeatExchanger('HX', 'UA',.., 'Qcap',..);
%     hx.valve.attachController( DHS.controllers.PID(...) );
%     b.attachZone('S1.Lobby',   'area',444, 'solar',DHS.Solar(..), 'schedule',DHS.Schedule(..), 'GventOcc',..);
%     b.attachZone('S1.Dining',  'area',296, 'solar',DHS.Solar(..), 'schedule',DHS.Schedule(..), 'GventOcc',..);
%     ...
%   One substation feeds the whole building. The control loop regulates the
%   area-weighted mean zone temperature to the area-weighted mean setpoint; the
%   delivered heat is split between zones in proportion to each zone's current
%   heating demand  area * max(0, setpoint - T_zone). Ventilation and free-cooling
%   are applied per zone.
%
%   INTERNAL LOOP  (optional; without it the substation is ideal: the exchanger's heat goes straight
%   to the zones, shared by demand). The loop starts at the exchanger's internal outlet and ends at its
%   internal inlet; you connect its components like the district network, and nothing else is needed:
%     hx = b.addHeatExchanger('HX', ...);
%     p1   = hx.internalOutlet.addPipe(0.05, 4);          % pipe from the exchanger
%     pump = p1.addPump('dp0',3e4, 'mdotRated',1);          % loop pump
%     tee  = pump.addPipe(0.05, 4).addTee(0.032);         % tee, side port 32 mm
%     valve = tee.portC.addValve('Kvs',4);                % zone valve
%     rad  = valve.addRadiator('rad1', 'Qdes',8e3);       % radiator (a DHS.Radiator)
%     rad.connect(zone1, R);                              % heat to an RCBS zone (R in K/W)
%     rad.addPipe(0.05, 4).connect(hx.internalInlet);     % return to the exchanger
%   The loop pump, the zone valves and the district valve (hx.valve) each take a controller; the
%   exchanger heats the loop water, each radiator (DHS.Radiator) turns it into heat at its zone, and
%   the zones stay RC models. The water in the loop is a lumped capacity at the supply side, from the
%   volume of the loop pipes plus hx.internalVolume (b.loopCapacity [J/K] overrides it).
%
%   PER-STEP PROTOCOL  (driven by DHS.System)
%     prepare(t, wx)          sample schedule + solar (per zone if multi-zone)
%     u = control(sys, dt)    run the valve/pump controllers -> valve command in [0,1]
%     [Qd,Tr] = exchange(mdot, Tsup_hx)   eps-NTU HX for the resolved primary flow
%     advance(dt, tNext, wx)  assemble the node-heat vector and step the RC model

    properties
        name (1,:) char = ''

        heatExchanger                     % a DHS.HeatExchanger: ENTUPlate, FixedEffectiveness or Ideal
        internalLoop                      % DHS.HydraulicNetwork of the building's internal loop ([] = ideal substation)
        radiators cell = {}               % the DHS.Radiator of each zone
        loopCapacity (1,1) double = NaN   % [J/K] heat capacity of the loop water; NaN = from the pipe volumes and hx.internalVolume
        solar         DHS.Solar          % single-zone only
        schedule      DHS.Schedule       % single-zone only

        % district connection pipe (junction -> HX -> junction), one each way
        connLength (1,1) double = 20      % [m]
        connD      (1,1) double = 0.05    % [m]
        Kminor     (1,1) double = 8       % sum of minor-loss coefficients on the branch [-]

        % envelope conductances used by the ventilation / free-cooling terms
        Ginf     (1,1) double = 0         % background infiltration 1/R_inf [W/K]
        GventOcc (1,1) double = 0         % occupied mechanical-ventilation conductance [W/K]

        % winter free-cooling / economizer (occupied hours only)
        freeCool         (1,1) logical = true
        freeCoolFactor   (1,1) double  = 6
        freeCoolDeadband (1,1) double  = 0.5

        cp (1,1) double = 4186
        integrator (1,:) char {mustBeMember(integrator, {'backwardEuler','forwardEuler','exact'})} = 'backwardEuler'   % for the loop water and the radiators (set by DHS.System)

        % --- multi-zone: one descriptor per RC zone (empty => single-zone) ---
        zones struct = struct('key',{},'area',{},'roomType',{},'solar',{},'schedule',{}, ...
                              'Ginf',{},'GventOcc',{},'freeCool',{},'freeCoolFactor',{}, ...
                              'freeCoolDeadband',{},'iAir',{},'iMass',{},'iWall',{},'iRoof',{})
    end

    properties (SetAccess = private)
        rcBuilding                        % RCBS.Building
        sim                              % RCBS.Simulation (exposed for getStateSpace)
        iAir  (1,1) double = 1
        iMass (1,:) double = []
        iWall (1,:) double = []
        iRoof (1,:) double = []

        % live per-step state (single-zone; for multi-zone the aggregates)
        Tzone       (1,1) double = NaN
        setpoint    (1,1) double = NaN
        occupied    (1,1) logical = false
        command     (1,1) double = 0
        Qdel        (1,1) double = 0
        TretPrimary (1,1) double = NaN
        Qvent       (1,1) double = 0
        Qfreecool   (1,1) double = 0
        Qsa (1,1) double = 0
        Qsm (1,1) double = 0
        Qsw (1,1) double = 0
        Qia (1,1) double = 0
        Qim (1,1) double = 0
        mz  struct = struct()             % multi-zone per-step vectors
        % internal loop
        TintSup (1,1) double = NaN        % loop supply temperature leaving the exchanger [degC]
        TintRet (1,1) double = NaN        % loop return temperature entering the exchanger [degC]
        mdotInt (1,1) double = 0          % loop flow [kg/s]
        QlossLoop (1,1) double = 0        % heat the loop pipes lose to the building [W]
        radZone double = []               % zone index of each radiator
        radBranch double = []             % branch index of each radiator in the internal loop
        radMdot double = []               % flow of each branch [kg/s]
        TintState (1,1) double = NaN      % loop supply temperature at the start of the step
        loopCap   (1,1) double = 1e6      % heat capacity of the loop water in use [J/K]
    end
    properties (Dependent)
        supplyNode                        % the junction the building is fed from
        returnNode                        % the junction it drains into
        teeSide                           % '' | 'run' | 'branch' of the tee it hangs on
    end
    properties
        inlet  DHS.Hydraulic.Junction     % supply-side port
        outlet DHS.Hydraulic.Junction     % return-side port
        connPipeSup DHS.Hydraulic.Pipe
        connPipeRet DHS.Hydraulic.Pipe
    end

    methods
        function obj = Building(name, varargin)
            if nargin >= 1, obj.name = name; end
            for i = 1:2:numel(varargin), obj.(varargin{i}) = varargin{i+1}; end
            obj.inlet       = DHS.Hydraulic.Junction([obj.name '.inlet'],  'supply');
            obj.outlet      = DHS.Hydraulic.Junction([obj.name '.outlet'], 'return');
            obj.connPipeSup = DHS.Hydraulic.Pipe([obj.name '.connSup']);
            obj.connPipeRet = DHS.Hydraulic.Pipe([obj.name '.connRet']);
        end

        % ---- assembly API --------------------------------------------------
        function obj = useRCModel(obj, B)
            % USERCMODEL  Attach the RCBS thermal model (an RCBS.Building).
            assert(isa(B,'RCBS.Building'), 'DHS:Building:rc', 'Expected an RCBS.Building.');
            obj.rcBuilding = B;
            obj.sim = B.simulation;
            for i = 1:numel(B.storeyList)                      % building.Storey1.Zone2.Wall.R
                DHS.registerName(obj, B.(B.storeyList{i}), B.storeyList{i});
            end
        end

        function hx = addHeatExchanger(obj, name, varargin)
            % ADDHEATEXCHANGER  Create the substation HX (+ its valve and pump).
            if nargin < 2, name = [obj.name '.HX']; end
            hx = DHS.ENTUPlateHeatExchanger(name, varargin{:});
            obj.attachHeatExchanger(hx);
        end

        function attachHeatExchanger(obj, hx)
            % ATTACHHEATEXCHANGER  Install a pre-built DHS.HeatExchanger.
            assert(isa(hx,'DHS.HeatExchanger'), 'DHS:Building:hx', 'Expected a DHS.HeatExchanger.');
            hx.hostBuilding  = obj;
            hx.pump.hostPort = obj.inlet;
            obj.heatExchanger = hx;
            DHS.registerName(obj, hx);                         % sys.Library.HX.UA
        end

        function dst = connect(obj, dst, varargin)
            % CONNECT  building.connect(returnJunction): the building drains into the return junction
            %   (or into the first pipe of a return line). It is fed from a tee port or junction:
            %   tee.portC.connect(building).
            DHS.Hydraulic.connectEnds(obj, dst, varargin{:});
        end

        function x = addPipe(obj, varargin),  x = DHS.Hydraulic.addOn(obj, 'pipe', varargin{:});  end
        function x = addValve(obj, varargin), x = DHS.Hydraulic.addOn(obj, 'valve', varargin{:}); end
        function x = addPump(obj, varargin),  x = DHS.Hydraulic.addOn(obj, 'pump', varargin{:});  end

        function n = get.supplyNode(obj),  n = obj.connPipeSup.nodeA; end
        function set.supplyNode(obj, n),   obj.connPipeSup.nodeA = n; end
        function n = get.returnNode(obj),  n = obj.connPipeRet.nodeB; end
        function set.returnNode(obj, n),   obj.connPipeRet.nodeB = n; end
        function t = get.teeSide(obj),     t = obj.connPipeSup.teeSide; end
        function set.teeSide(obj, t),      obj.connPipeSup.teeSide = t; end

        function sizeServicePipes(obj)
            % the two service pipes take their length and diameter from connLength and connD
            obj.connPipeSup.L = obj.connLength;  obj.connPipeSup.D = obj.connD;
            obj.connPipeRet.L = obj.connLength;  obj.connPipeRet.D = obj.connD;
        end

        function obj = attachSolar(obj, s)
            assert(isa(s,'DHS.Solar'), 'DHS:Building:solar', 'Expected a DHS.Solar.');
            obj.solar = s;
        end
        function obj = attachSchedule(obj, s)
            assert(isa(s,'DHS.Schedule'), 'DHS:Building:sched', 'Expected a DHS.Schedule.');
            obj.schedule = s;
            if isprop(s,'Gvent_occ') && ~isempty(s.Gvent_occ), obj.GventOcc = s.Gvent_occ; end
        end

        function obj = attachZone(obj, key, varargin)
            % ATTACHZONE  Register one RC zone of a multi-zone building.
            %   attachZone('S1.Lobby', 'area',A, 'roomType','lobby', ...
            %              'solar',DHS.Solar(..), 'schedule',DHS.Schedule(..), ...
            %              'GventOcc',G, 'Ginf',Gi, 'freeCool',true/false, ...)
            %   `key` is "Storey.Zone" exactly as named in the RCBS model.
            p = inputParser;
            p.addParameter('area', 1);
            p.addParameter('roomType', '');
            p.addParameter('solar', DHS.Solar());
            p.addParameter('schedule', DHS.Schedule());
            p.addParameter('GventOcc', 0);
            p.addParameter('Ginf', 0);
            p.addParameter('freeCool', obj.freeCool);
            p.addParameter('freeCoolFactor', obj.freeCoolFactor);
            p.addParameter('freeCoolDeadband', obj.freeCoolDeadband);
            p.parse(varargin{:});
            r = p.Results;
            zm = struct('key',char(key),'area',r.area,'roomType',char(r.roomType), ...
                'solar',r.solar,'schedule',r.schedule,'Ginf',r.Ginf,'GventOcc',r.GventOcc, ...
                'freeCool',logical(r.freeCool),'freeCoolFactor',r.freeCoolFactor, ...
                'freeCoolDeadband',r.freeCoolDeadband,'iAir',0,'iMass',[],'iWall',[],'iRoof',[]);
            obj.zones(end+1) = zm;
        end

        function tf = isMultiZone(obj), tf = ~isempty(obj.zones); end

        % ---- lifecycle ---------------------------------------------------
        function bindClock(obj, startDate, timeStep, outdoorTempFcn)
            obj.sim.startDate = startDate;
            obj.sim.timeStep  = timeStep;
            if nargin > 3 && ~isempty(outdoorTempFcn)
                obj.rcBuilding.outdoorTempFunc = outdoorTempFcn;
            end
            obj.sim.buildLinear();
            nn = string(obj.sim.nodeNames);

            if obj.isMultiZone()
                keyList = string(obj.sim.zoneKeyList);
                for z = 1:numel(obj.zones)
                    k = string(obj.zones(z).key);
                    j = find(keyList == k, 1);
                    assert(~isempty(j), 'DHS:Building:zoneKey', ...
                        'attachZone key "%s" not found in the RC model (have: %s).', ...
                        k, strjoin(keyList, ', '));
                    obj.zones(z).iAir  = obj.sim.zoneMainRow(j);
                    pfx = k + ".";
                    obj.zones(z).iMass = find(startsWith(nn,pfx) & contains(nn,"IntMass"));
                    obj.zones(z).iWall = find(startsWith(nn,pfx) & contains(nn,"Wall"));
                    obj.zones(z).iRoof = find(startsWith(nn,pfx) & contains(nn,"Roof"));
                    if obj.zones(z).Ginf == 0
                        obj.zones(z).Ginf = obj.readInfilConductance(char(k));
                    end
                end
                obj.iAir = obj.zones(1).iAir;      % a sane default for accessors
            else
                obj.iAir  = obj.sim.zoneMainRow(1);
                obj.iMass = find(contains(nn,'IntMass'));
                obj.iWall = find(contains(nn,'Wall'));
                obj.iRoof = find(contains(nn,'Roof'));
                if obj.Ginf == 0
                    obj.Ginf = obj.readInfilConductance();
                end
            end
            obj.checkHeatExchanger();
            obj.prepareLoop();
        end

        function reset(obj, dt)
            if ~isempty(obj.heatExchanger.valve.controller), obj.heatExchanger.valve.controller.reset(); end
            if ~isempty(obj.heatExchanger.pump.controller),  obj.heatExchanger.pump.controller.reset();  end
            obj.sim.resetState();
            obj.sim.buildLinear();
            obj.sim.factor(dt);
            [obj.command, obj.Qdel, obj.Qvent, obj.Qfreecool] = deal(0);
            obj.TretPrimary = NaN;
            if obj.isMultiZone()
                nZ = numel(obj.zones);
                obj.mz = struct('Tz',zeros(1,nZ),'Tsp',zeros(1,nZ),'occ',false(1,nZ), ...
                    'Qia',zeros(1,nZ),'Qim',zeros(1,nZ),'Qsa',zeros(1,nZ),'Qsm',zeros(1,nZ), ...
                    'Qsw',zeros(1,nZ),'Qdel',zeros(1,nZ),'Qvent',zeros(1,nZ),'Qfc',zeros(1,nZ));
                obj.mz.Tz = arrayfun(@(z) obj.sim.Tnow(z.iAir), obj.zones);
            end
            obj.Tzone = obj.aggTzone();
            if ~isempty(obj.internalLoop)
                obj.TintSup = obj.Tzone + 20;  obj.TintRet = obj.Tzone + 20;  obj.mdotInt = 0;
                obj.TintState = obj.TintSup;  obj.QlossLoop = 0;
                obj.internalLoop.resetLinkControllers();
                for k = 1:numel(obj.radiators)
                    if obj.isMultiZone(), Tz = obj.mz.Tz(obj.radZone(k)); else, Tz = obj.Tzone; end
                    obj.radiators{k}.reset(Tz);
                end
            end
        end

        function prepare(obj, t, wx)
            if obj.isMultiZone()
                for z = 1:numel(obj.zones)
                    zm = obj.zones(z);
                    obj.mz.Tsp(z) = zm.schedule.setpoint(t);
                    obj.mz.occ(z) = zm.schedule.isOccupied(t);
                    [obj.mz.Qia(z), obj.mz.Qim(z)] = zm.schedule.internalGain(t);
                    [obj.mz.Qsa(z), obj.mz.Qsm(z), obj.mz.Qsw(z)] = zm.solar.heatGain(wx);
                    obj.mz.Tz(z) = obj.sim.Tnow(zm.iAir);
                end
                obj.setpoint = obj.aggSetpoint();
                obj.occupied = any(obj.mz.occ);
                obj.Tzone    = obj.aggTzone();
                for k = 1:numel(obj.radiators)
                    obj.radiators{k}.Tzone    = obj.mz.Tz(obj.radZone(k));
                    obj.radiators{k}.setpoint = obj.mz.Tsp(obj.radZone(k));
                end
            else
                obj.setpoint = obj.schedule.setpoint(t);
                obj.occupied = obj.schedule.isOccupied(t);
                [obj.Qia, obj.Qim] = obj.schedule.internalGain(t);
                [obj.Qsa, obj.Qsm, obj.Qsw] = obj.solar.heatGain(wx);
                obj.Tzone = obj.sim.Tnow(obj.iAir);
                for k = 1:numel(obj.radiators)
                    obj.radiators{k}.Tzone = obj.Tzone;  obj.radiators{k}.setpoint = obj.setpoint;
                end
            end
        end

        function u = control(obj, sys, dt)
            % CONTROL  Ask the valve's (and the booster pump's) controller for a command.
            v = obj.heatExchanger.valve;  p = obj.heatExchanger.pump;
            if ~isempty(v.controller)
                v.pos = min(1, max(0, v.controller.update(sys, dt)));
            end
            if ~isempty(p.controller)
                p.speed = min(1, max(0, p.controller.update(sys, dt)));
            end
            if ~isempty(obj.internalLoop)
                obj.internalLoop.controlLinks(sys, dt);          % loop pumps, zone valves, bypass valves
            end
            obj.advanceValves(dt);                                % the actuators follow their commands
            u = v.pos;
            obj.command = v.pos;
        end

        function beginRun(obj)
            % BEGINRUN  Start of a run: this building's valves are at their commands and their lags apply.
            obj.heatExchanger.valve.beginRun();
            if ~isempty(obj.internalLoop), obj.internalLoop.beginRun(); end
        end

        function endRun(obj)
            obj.heatExchanger.valve.endRun();
            if ~isempty(obj.internalLoop), obj.internalLoop.endRun(); end
        end

        function advanceValves(obj, dt)
            obj.heatExchanger.valve.advance(dt);
            if ~isempty(obj.internalLoop), obj.internalLoop.advanceValves(dt); end
        end

        function solveInternalLoop(obj)
            % SOLVEINTERNALLOOP  Flows in the internal loop for the current valve positions and pump speed.
            if isempty(obj.internalLoop), return, end
            s = obj.internalLoop.solve(1);
            obj.mdotInt = s.Mtot;
            obj.radMdot = s.mdot;
        end

        function [Qdel, TretP] = exchange(obj, mdotPrimary, TsupHx)
            % EXCHANGE  Heat from the district water to the building.
            %   Without an internal loop the exchanger delivers to the zones directly (the secondary
            %   heat follows from the radiator law of DHS.IdealHeatExchanger). With one, the exchanger heats the
            %   loop water, the radiators take it to the zones, and the cooled water returns.
            if isempty(obj.internalLoop)
                [Qdel, TretP] = obj.heatExchanger.idealTransfer(mdotPrimary, TsupHx, obj.Tzone);   % IdealHeatExchanger
                obj.Qdel = Qdel;  obj.TretPrimary = TretP;
                return
            end
            [Qdel, TretP, TsecOut] = obj.heatExchanger.transfer(mdotPrimary, TsupHx, obj.TintRet, obj.mdotInt);
            obj.Qdel = Qdel;  obj.TretPrimary = TretP;
            m   = obj.radMdot;  dt = seconds(obj.sim.timeStep);
            % the loop water is a stirred tank at the supply side: Cl dT/dt = mdot cp (TsecOut - T)
            if obj.mdotInt > 1e-9
                Cd = obj.loopCap/dt;  Cm = obj.mdotInt*obj.cp;
                switch obj.integrator
                    case 'backwardEuler'
                        obj.TintSup = (Cd*obj.TintState + Cm*TsecOut) / (Cd + Cm);
                    case 'forwardEuler'
                        if Cm/Cd > 2
                            warning('DHS:Building:forwardEulerUnstable', ...
                                'Building "%s": forwardEuler for the loop water needs a step below %.3g s (it is %.3g s).', ...
                                obj.name, 2*obj.loopCap/Cm, dt);
                        end
                        obj.TintSup = obj.TintState + (Cm/Cd)*(TsecOut - obj.TintState);
                    case 'exact'
                        obj.TintSup = TsecOut + (obj.TintState - TsecOut)*exp(-Cm/Cd);
                end
            else
                obj.TintSup = obj.TintState;
            end
            [TsupZ, qlS] = obj.internalLoop.supplyTemperatures(obj.TintSup, obj.Tzone, m, obj.cp);
            Tout = TsupZ;                                      % a bypass passes the water on unchanged
            for k = 1:numel(obj.radiators)
                rad = obj.radiators{k};  j = obj.radBranch(k);
                if obj.isMultiZone(), Tz = obj.mz.Tz(obj.radZone(k)); else, Tz = obj.Tzone; end
                [Qa, To, Tm, Qw] = rad.response(m(j), TsupZ(j), Tz, dt);
                rad.store(m(j), TsupZ(j), To, Qw, Qa, Tm);
                Tout(j) = To;
            end
            [Tret, qlR] = obj.internalLoop.returnTemperatures(Tout, obj.Tzone, m, obj.cp);
            obj.QlossLoop = qlS + qlR;                         % heat the loop pipes give to the building
            if obj.mdotInt > 1e-9, obj.TintRet = Tret; end
        end

        function advance(obj, ~, tNext, wx)
            N = numel(obj.sim.Tnow);
            q = zeros(N, 1);
            Qheat = obj.Qdel;                                  % heat to the zone air: the exchanger's, or the radiators'
            if ~isempty(obj.internalLoop)
                Qrz = zeros(1, max(1, numel(obj.zones)));
                for k = 1:numel(obj.radiators)
                    Qrz(obj.radZone(k)) = Qrz(obj.radZone(k)) + obj.radiators{k}.Qair;
                    obj.radiators{k}.commit();
                end
                Qheat = sum(Qrz) + obj.QlossLoop;            % radiators plus the loop pipes' own heat
                obj.TintState = obj.TintSup;
            end

            if obj.isMultiZone()
                nZ = numel(obj.zones);
                A  = [obj.zones.area];
                Tz = obj.mz.Tz;  Tsp = obj.mz.Tsp;  occ = obj.mz.occ;

                if ~isempty(obj.internalLoop)
                    obj.mz.Qdel = Qrz;                         % each zone gets what its radiators give
                else
                    % ideal substation: split the delivered heat by each zone's current heating demand
                    w = A .* max(0, Tsp - Tz);
                    if sum(w) > eps, obj.mz.Qdel = obj.Qdel * w ./ sum(w);
                    else,            obj.mz.Qdel = zeros(1,nZ);
                    end
                end

                for z = 1:nZ
                    zm = obj.zones(z);
                    qv = 0;
                    if occ(z) && zm.GventOcc > 0
                        qv = -zm.GventOcc * (Tz(z) - wx.Tout);
                    end
                    qf = 0;
                    if zm.freeCool && occ(z) ...
                            && Tz(z) > Tsp(z) + zm.freeCoolDeadband && wx.Tout < Tz(z) - 0.5
                        frac = min(1, (Tz(z) - Tsp(z) - zm.freeCoolDeadband) / 1.0);
                        qf = -frac * zm.freeCoolFactor * zm.Ginf * (Tz(z) - wx.Tout);
                    end
                    obj.mz.Qvent(z) = qv;  obj.mz.Qfc(z) = qf;

                    qpipe = 0;
                    if ~isempty(obj.internalLoop), qpipe = obj.QlossLoop * zm.area / sum(A); end   % loop pipe heat, by area
                    q(zm.iAir) = q(zm.iAir) + obj.mz.Qdel(z) + qpipe + obj.mz.Qsa(z) + obj.mz.Qia(z) + qv + qf;
                    if ~isempty(zm.iMass)
                        q(zm.iMass(1)) = q(zm.iMass(1)) + obj.mz.Qsm(z) + obj.mz.Qim(z);
                    else
                        q(zm.iAir) = q(zm.iAir) + obj.mz.Qsm(z) + obj.mz.Qim(z);
                    end
                    if ~isempty(zm.iWall) && obj.mz.Qsw(z) ~= 0
                        q(zm.iWall) = q(zm.iWall) + obj.mz.Qsw(z) / numel(zm.iWall);
                    end
                end
                obj.Qvent     = sum(obj.mz.Qvent);
                obj.Qfreecool = sum(obj.mz.Qfc);
            else
                Tz = obj.Tzone;  Tsp = obj.setpoint;
                obj.Qvent = 0;
                if obj.occupied && obj.GventOcc > 0
                    obj.Qvent = -obj.GventOcc * (Tz - wx.Tout);
                end
                obj.Qfreecool = 0;
                if obj.freeCool && obj.occupied ...
                        && Tz > Tsp + obj.freeCoolDeadband && wx.Tout < Tz - 0.5
                    frac = min(1, (Tz - Tsp - obj.freeCoolDeadband) / 1.0);
                    obj.Qfreecool = -frac * obj.freeCoolFactor * obj.Ginf * (Tz - wx.Tout);
                end
                q(obj.iAir) = q(obj.iAir) + Qheat + obj.Qsa + obj.Qia + obj.Qvent + obj.Qfreecool;
                if ~isempty(obj.iMass)
                    q(obj.iMass(1)) = q(obj.iMass(1)) + obj.Qsm + obj.Qim;
                else
                    q(obj.iAir) = q(obj.iAir) + obj.Qsm + obj.Qim;
                end
                if ~isempty(obj.iWall) && obj.Qsw ~= 0
                    q(obj.iWall) = q(obj.iWall) + obj.Qsw / numel(obj.iWall);
                end
            end

            obj.sim.stepOnce(tNext, wx.Tout, q);
            obj.Tzone = obj.aggTzone();
        end

        % ---- accessors -------------------------------------------------------
        function T = zoneTemp(obj), T = obj.aggTzone(); end
        function T = wallTemp(obj)
            if obj.isMultiZone(), T = obj.aggNode('iWall'); else, T = obj.nodeT(obj.iWall); end
        end
        function T = roofTemp(obj)
            if obj.isMultiZone(), T = obj.aggNode('iRoof'); else, T = obj.nodeT(obj.iRoof); end
        end
        function T = massTemp(obj)
            if obj.isMultiZone(), T = obj.aggNode('iMass'); else, T = obj.nodeT(obj.iMass); end
        end

        function s = signals(obj)
            s = struct('Tzone',obj.zoneTemp(),'Twall',obj.wallTemp(), ...
                'Troof',obj.roofTemp(),'Tmass',obj.massTemp(), ...
                'setpoint',obj.setpoint,'Qdeliv',obj.Qdel, ...
                'Qsolar',obj.aggQsolar(),'Qint',obj.aggQint(), ...
                'Qvent',obj.Qvent,'Qfreecool',obj.Qfreecool, ...
                'valve',obj.heatExchanger.valve.pos, ...
                'pump',obj.heatExchanger.pump.speed, ...
                'Tret_primary',obj.TretPrimary, ...
                'Tint_sup',obj.TintSup,'Tint_ret',obj.TintRet,'mdot_int',obj.mdotInt);
            if obj.isMultiZone()
                s.Tzones    = arrayfun(@(z) obj.sim.Tnow(z.iAir), obj.zones);
                s.zoneNames = {obj.zones.key};
                s.Qzones    = obj.mz.Qdel;
            else
                s.Tzones    = obj.zoneTemp();
                s.zoneNames = {obj.name};
                s.Qzones    = obj.Qdel;
                if ~isempty(obj.internalLoop) && ~isempty(obj.radiators)
                    s.Qzones = sum(cellfun(@(r) r.Qair, obj.radiators));
                end
            end
        end
    end

    methods
        % ---- hydraulic branch protocol (DHS.HydraulicNetwork) -----------------------------
        function K = branchResistance(obj, rho, mu, m)
            % BRANCHRESISTANCE  Service pipes + valve + exchanger body + minor losses [Pa/(kg/s)^2],
            %   with the pipes' friction at the flow m (the last solved flow when not given).
            A  = pi*obj.connD^2/4;
            if nargin < 4, m = obj.connPipeSup.mdot; end
            m0 = max(m, 0.2);
            K = obj.connPipeSup.resistance(m0, rho, mu) + obj.connPipeRet.resistance(m0, rho, mu) ...
              + obj.heatExchanger.primaryResistance(rho) + obj.Kminor/(2*rho*A^2);
        end

        function p = branchPump(obj)
            p = obj.heatExchanger.pump;
        end

        function m = branchFlow(obj)
            m = obj.connPipeSup.mdot;
        end

        function [T, ql] = inletTemperature(obj, Tnode, Tground, m, cp)
            % water temperature at the heat exchanger, after the supply service pipe
            [T, ql] = obj.connPipeSup.outletTemperature(Tnode, Tground, m, cp);
        end

        function [T, ql] = outletTemperature(obj, Thx, Tground, m, cp)
            % water temperature leaving the building, after the return service pipe
            [T, ql] = obj.connPipeRet.outletTemperature(Thx, Tground, m, cp);
        end

        function vel = setBranchResult(obj, m, rho, dpBooster, pSup, pRet)
            % SETBRANCHRESULT  Store the solved flow in the service pipes, pump and valve.
            hx = obj.heatExchanger;
            A  = pi*obj.connD^2/4;
            vel = m/(rho*A);
            obj.connPipeSup.mdot = m;  obj.connPipeRet.mdot = m;
            obj.connPipeSup.vel = vel; obj.connPipeRet.vel = vel;
            hx.pump.mdot = m;  hx.pump.head = dpBooster;
            hx.valve.dp  = hx.valve.resistance(rho) * m^2;
            obj.inlet.p  = pSup;  obj.outlet.p = pRet;
        end
    end

    methods (Access = {?DHS.HeatExchanger})
        function sec = ensureInternalLoop(obj)
            % ENSUREINTERNALLOOP  The building's internal hydraulic network, made the first time anything is
            %   connected to the exchanger's internal outlet or inlet. Its root is the exchanger's internal side.
            if isempty(obj.internalLoop)
                sec = DHS.HydraulicNetwork();
                sec.pReturnRef = 1.0e5;  sec.rho = 983;  sec.mu = 4.7e-4;
                sup = DHS.Hydraulic.Junction([obj.name '.internalOutlet'], 'supply');
                ret = DHS.Hydraulic.Junction([obj.name '.internalInlet'], 'return');
                sup.network = sec;  ret.network = sec;
                sec.plantSupply = sup;  sec.plantReturn = ret;
                sec.nameOwner = obj;                              % loop parts are reachable by name on the building
                obj.internalLoop = sec;
            end
            sec = obj.internalLoop;
        end
    end

    methods (Access = private)
        function checkHeatExchanger(obj)
            % the heat exchanger type and the internal loop must agree, and the loop must be connected
            hx = obj.heatExchanger;
            assert(~isempty(hx), 'DHS:Building:noHeatExchanger', ...
                'Building "%s" has no heat exchanger: building.addHeatExchanger(...) or attachHeatExchanger(...).', obj.name);
            loop = obj.internalLoop;
            if hx.usesInternalLoop()
                outOk = ~isempty(loop) && ~(isempty(loop.plantSupply.outLinks) && isempty(loop.plantSupply.terminals));
                inOk  = ~isempty(loop) && ~(isempty(loop.plantReturn.inLinks) && isempty(loop.plantReturn.fedBuildings));
                if ~(outOk && inOk)
                    miss = {};
                    if ~outOk, miss{end+1} = 'internalOutlet'; end %#ok<AGROW>
                    if ~inOk,  miss{end+1} = 'internalInlet';  end %#ok<AGROW>
                    error('DHS:Building:heatExchangerPorts', ...
                        ['Building "%s": the %s needs its internal loop connected to the heat exchanger, and ' ...
                         'hx.%s is not connected. Connect the loop between hx.internalOutlet and hx.internalInlet, ' ...
                         'or use a DHS.IdealHeatExchanger for a building without a loop.'], ...
                        obj.name, class(hx), strjoin(miss, ' and hx.'));
                end
            elseif ~isempty(loop)
                error('DHS:Building:idealWithLoop', ...
                    ['Building "%s" has an internal loop but its heat exchanger is a %s, which stands for a ' ...
                     'building without one. Use an ENTUPlateHeatExchanger or a FixedEffectivenessHeatExchanger, ' ...
                     'or remove the loop.'], obj.name, class(hx));
            end
        end

        function prepareLoop(obj)
            % find the radiators of the internal loop, their zones, and the water it holds
            if isempty(obj.internalLoop), obj.radiators = {}; return, end
            net = obj.internalLoop;
            net.compile();                                        % walks the connections; needs a pump
            rads = {};
            for k = 1:numel(net.buildings)
                if isa(net.buildings{k}, 'DHS.Radiator'), rads{end+1} = net.buildings{k}; end %#ok<AGROW>
            end
            obj.radiators = rads;
            for k = 1:numel(rads), rads{k}.integrator = obj.integrator; end
            links = net.allLinks();  V = 0;
            for k = 1:numel(links)
                if isa(links{k}, 'DHS.Hydraulic.Pipe'), V = V + pi*links{k}.D^2/4 * links{k}.L; end
            end
            V = V + obj.heatExchanger.internalVolume/1000;        % pipes plus the exchanger's internal side [m3]
            if isnan(obj.loopCapacity), obj.loopCap = max(net.rho * V * obj.cp, 1);
            else,                       obj.loopCap = obj.loopCapacity; end
            obj.mapRadiators();
        end

        function key = zoneKeyOf(obj, z)
            % 'Storey.Zone' of an RCBS zone object (or the text itself)
            if ischar(z) || isstring(z), key = char(z); return, end
            key = '';
            rcb = obj.rcBuilding;
            for s = 1:numel(rcb.storeyList)
                st = rcb.(rcb.storeyList{s});
                for q = 1:numel(st.zoneList)
                    if st.(st.zoneList{q}) == z, key = [rcb.storeyList{s} '.' st.zoneList{q}]; return, end
                end
            end
        end

        function mapRadiators(obj)
            % zone index and branch index of every radiator
            nR = numel(obj.radiators);
            obj.radZone = ones(1, nR);  obj.radBranch = zeros(1, nR);
            for k = 1:nR
                rad = obj.radiators{k};
                if obj.isMultiZone()
                    assert(~isempty(rad.zone), 'DHS:Building:radiatorZone', ...
                        'Radiator "%s": connect it to the zone it heats, rad.connect(zone).', rad.name);
                    key = obj.zoneKeyOf(rad.zone);
                    j = find(strcmp({obj.zones.key}, key), 1);
                    assert(~isempty(j), 'DHS:Building:radiatorZone', ...
                        'Radiator "%s": its zone is not one of the building''s zones.', rad.name);
                    obj.radZone(k) = j;
                end
                obj.radBranch(k) = find(cellfun(@(x) x == rad, obj.internalLoop.buildings), 1);
            end
        end

        function T = nodeT(obj, idx)
            if isempty(idx), T = NaN; else, T = obj.sim.Tnow(idx(1)); end
        end
        function T = aggTzone(obj)
            if obj.isMultiZone()
                A = [obj.zones.area];
                T = sum(A .* arrayfun(@(z) obj.sim.Tnow(z.iAir), obj.zones)) / sum(A);
            else
                T = obj.sim.Tnow(obj.iAir);
            end
        end
        function T = aggSetpoint(obj)
            A = [obj.zones.area];
            T = sum(A .* obj.mz.Tsp) / sum(A);
        end
        function T = aggNode(obj, fld)
            A = []; v = [];
            for z = 1:numel(obj.zones)
                idx = obj.zones(z).(fld);
                if ~isempty(idx)
                    A(end+1) = obj.zones(z).area; %#ok<AGROW>
                    v(end+1) = obj.sim.Tnow(idx(1)); %#ok<AGROW>
                end
            end
            if isempty(v), T = NaN; else, T = sum(A.*v)/sum(A); end
        end
        function Q = aggQsolar(obj)
            if obj.isMultiZone(), Q = sum(obj.mz.Qsa) + sum(obj.mz.Qsm);
            else,                 Q = obj.Qsa + obj.Qsm; end
        end
        function Q = aggQint(obj)
            if obj.isMultiZone(), Q = sum(obj.mz.Qia) + sum(obj.mz.Qim);
            else,                 Q = obj.Qia + obj.Qim; end
        end
        function G = readInfilConductance(obj, zoneKey)
            % sum 1/R of 'InfVent'/'Infil*' resistors, optionally in one zone only
            if nargin < 2, zoneKey = ''; end
            G = 0;
            try
                for s = 1:numel(obj.rcBuilding.storeyList)
                    sn = obj.rcBuilding.storeyList{s};
                    st = obj.rcBuilding.(sn);
                    for z = 1:numel(st.zoneList)
                        zn = st.zoneList{z};
                        if ~isempty(zoneKey) && ~strcmp(zoneKey, [sn '.' zn]), continue; end
                        zo = st.(zn);
                        for r = 1:numel(zo.resistors)
                            nm = zo.resistors(r).name;
                            if contains(nm,'InfVent') || contains(nm,'Infil')
                                G = G + 1/zo.resistors(r).R;
                            end
                        end
                    end
                end
            catch
            end
        end
    end
end
