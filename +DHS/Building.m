classdef Building < handle
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
%     hx.valve.attachController( DHS.controllers.PID(0.14, 1.6e-4, 0) );
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
%   PER-STEP PROTOCOL  (driven by DHS.System)
%     prepare(t, wx)          sample schedule + solar (per zone if multi-zone)
%     u = control(dt, wx)     run the valve/pump controller -> command in [0,1]
%     [Qd,Tr] = exchange(mdot, Tsup_hx)   eps-NTU HX for the resolved primary flow
%     advance(dt, tNext, wx)  assemble the node-heat vector and step the RC model

    properties
        name (1,:) char = ''

        heatExchanger DHS.HeatExchanger
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
    end
    properties
        inlet  DHS.Hydraulic.Junction     % supply-side port
        outlet DHS.Hydraulic.Junction     % return-side port
        connPipeSup DHS.Hydraulic.Pipe
        connPipeRet DHS.Hydraulic.Pipe
    end

    methods
        function obj = Building(name)
            if nargin >= 1, obj.name = name; end
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
        end

        function hx = addHeatExchanger(obj, name, varargin)
            % ADDHEATEXCHANGER  Create the substation HX (+ its valve and pump).
            if nargin < 2, name = [obj.name '.HX']; end
            hx = DHS.HeatExchanger(name, varargin{:});
            obj.attachHeatExchanger(hx);
        end

        function attachHeatExchanger(obj, hx)
            % ATTACHHEATEXCHANGER  Install a pre-built DHS.HeatExchanger.
            assert(isa(hx,'DHS.HeatExchanger'), 'DHS:Building:hx', 'Expected a DHS.HeatExchanger.');
            hx.hostBuilding  = obj;
            hx.pump.hostPort = obj.inlet;
            obj.heatExchanger = hx;
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
            else
                obj.setpoint = obj.schedule.setpoint(t);
                obj.occupied = obj.schedule.isOccupied(t);
                [obj.Qia, obj.Qim] = obj.schedule.internalGain(t);
                [obj.Qsa, obj.Qsm, obj.Qsw] = obj.solar.heatGain(wx);
                obj.Tzone = obj.sim.Tnow(obj.iAir);
            end
        end

        function u = control(obj, dt, wx)
            aux = struct('x', obj.sim.Tnow, 'wx', wx, 'Tout', wx.Tout);
            v = obj.heatExchanger.valve;  p = obj.heatExchanger.pump;
            meas = obj.Tzone;  ref = obj.setpoint;
            if ~isempty(v.controller)
                u = min(1, max(0, v.controller.update(meas, ref, dt, aux)));
                v.pos = u;
            else
                u = v.pos;
            end
            if ~isempty(p.controller)
                p.speed = min(1, max(0, p.controller.update(meas, ref, dt, aux)));
            else
                p.speed = v.pos;                 % sequenced with the valve
            end
            obj.command = v.pos;
        end

        function [Qdel, TretP] = exchange(obj, mdotPrimary, TsupHx)
            TsecIn = obj.Tzone + obj.heatExchanger.secApproach;
            [Qdel, TretP] = obj.heatExchanger.transfer(mdotPrimary, TsupHx, TsecIn);
            obj.Qdel = Qdel;  obj.TretPrimary = TretP;
        end

        function advance(obj, ~, tNext, wx)
            N = numel(obj.sim.Tnow);
            q = zeros(N, 1);

            if obj.isMultiZone()
                nZ = numel(obj.zones);
                A  = [obj.zones.area];
                Tz = obj.mz.Tz;  Tsp = obj.mz.Tsp;  occ = obj.mz.occ;

                % split the delivered heat by each zone's current heating demand
                w = A .* max(0, Tsp - Tz);
                if sum(w) > eps, obj.mz.Qdel = obj.Qdel * w ./ sum(w);
                else,            obj.mz.Qdel = zeros(1,nZ);
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

                    q(zm.iAir) = q(zm.iAir) + obj.mz.Qdel(z) + obj.mz.Qsa(z) + obj.mz.Qia(z) + qv + qf;
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
                q(obj.iAir) = q(obj.iAir) + obj.Qdel + obj.Qsa + obj.Qia + obj.Qvent + obj.Qfreecool;
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
                'Tret_primary',obj.TretPrimary);
            if obj.isMultiZone()
                s.Tzones    = arrayfun(@(z) obj.sim.Tnow(z.iAir), obj.zones);
                s.zoneNames = {obj.zones.key};
            else
                s.Tzones    = obj.zoneTemp();
                s.zoneNames = {obj.name};
            end
        end
    end

    methods (Access = private)
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
