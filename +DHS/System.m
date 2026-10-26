classdef System < dynamicprops
% DHS.SYSTEM  A district heating system: a central heat plant + a pipe network +
%             N buildings, co-simulated on a fixed time step.
%
%   This is the top-level object of the +DHS library. You ASSEMBLE it from named
%   parts and then run it -- the code reads like the plant diagram:
%
%     sys = DHS.System('weather','solar_data_2025.csv', 'startDate',datetime(2025,1,1));
%
%     chp    = sys.addCentralHeatPlant('CHP');
%     chp.addBoiler('B1', 'QMax',1.5e6);
%     chp.addPump('P0', 'dp0',3.0e5, 'mdotRated',7);
%     chp.setSupplySetpoint(70);
%
%     hn = sys.addHydraulicNetwork();
%     t1 = hn.addJunction('T1');
%     hn.addPipe(chp.supplyPort, t1, 'L',40, 'D',0.11);
%
%     b  = sys.addBuilding('Engineering');
%     b.useRCModel( makeEngineeringRC() );
%     hx = b.addHeatExchanger('HX', 'UA',3.5e4, 'Qcap',8e5);
%     hx.valve.attachController( DHS.controllers.PID(0.14, 1.6e-4, 0) );
%     hn.connectBuilding(t1, b);
%
%     sys.visualize();
%     res = sys.run(days(14));
%
%   This declarative style and the connecting style (a.connect(b), or
%   pipe = node.addPipe(D, L), T-junctions, named pump types) build the
%   exact same network -- see DHS.HydraulicNetwork and DHS.Hydraulic.*.
%
%   PER-STEP SEQUENCE  (sequential / Gauss-Seidel with an inner supply/return
%   fixed-point):
%     1. sample the weather, then call stepFunction(sys) if there is one;
%     2. each building.prepare(t,wx) -> setpoint / occupancy / gains / solar;
%     3. each building.control(sys,dt) -> valve + pump commands; the central pump
%        and the bypass valve run their own controllers (c.update(sys,dt)) on the
%        previous step's pressures;
%     4. network.solve(pump speed) -> branch flows, velocities, node pressures;
%     5. plant.stepControl(sys,dt) -> burner firing (each boiler's controller);
%     6. inner loop until the plant supply temperature is self-consistent:
%        supply-pipe loss -> HX inlet temp; building.exchange -> delivered heat +
%        primary return; return-pipe loss + mixing -> plant return; plant.evalBoiler;
%     7. plant.commit;
%     8. each building.advance(dt,tNext,wx) -> step its RCBS model one interval;
%     9. log.
%   Hooks: startFunction(sys) runs once before the run, stepFunction(sys) at the start of
%   every step (step 1 is the first), stopFunction(sys) once after the last step.
%
%   OUTPUT  res.time, res.Tout, res.plant.(...), res.bldg(i).(...), res.energy.(...)

    properties
        startDate  datetime
        timeStep   duration = seconds(60)
        couplingIterations (1,1) double = 2
        pumpFrac   (1,1) double = 1        % central pump speed when it has no controller
        baseHeatW  (1,1) double = 0
        cp         (1,1) double = 4186
        integrator (1,:) char {mustBeMember(integrator, {'backwardEuler','forwardEuler','exact'})} = 'backwardEuler'   % time integration of the buildings' RC models, the radiators and the loop water

        weather    DHS.Weather
        plant      DHS.CentralHeatPlant
        network    DHS.HydraulicNetwork
        buildings  cell = {}

        % user hooks: each is @(sys) and may read or change anything in the system
        startFunction = []        % once, before the run starts
        stepFunction  = []        % at the start of every step, before the controllers
        stopFunction  = []        % once, after the last step (sys.result holds the results)
        userData      struct = struct()   % yours: the toolbox never reads or changes it
        result        struct = struct()   % the run's results; set before stopFunction, returned by run
    end
    properties (SetAccess = private)
        time      datetime                   % start of the current step (read by controllers)
        stepIndex (1,1) double = 0           % number of the current step, 1 for the first
        wx        struct = struct()          % weather sample of the current step: Tout, Tground, ghi, dhi, dni, sunZen, sunAz, sunEl, albedo
        nB        (1,1) double = 0
        plantInit (1,2) double = [78 70]
        compiled  (1,1) logical = false
    end

    methods
        function obj = System(varargin)
            p = inputParser;
            p.addParameter('weather', '');
            p.addParameter('startDate', datetime(2025,1,1,0,0,0));
            p.addParameter('timeStep', seconds(60));
            p.addParameter('couplingIterations', 2);
            p.addParameter('pumpFrac', 1);
            p.addParameter('baseHeatW', 0);
            p.addParameter('integrator', 'backwardEuler');
            p.parse(varargin{:});
            o = p.Results;
            if ~isempty(o.weather), obj.weather = DHS.Weather(char(o.weather)); end
            obj.startDate = o.startDate;
            obj.timeStep  = o.timeStep;
            obj.couplingIterations = o.couplingIterations;
            obj.pumpFrac  = o.pumpFrac;
            obj.baseHeatW = o.baseHeatW;
            obj.integrator = o.integrator;
        end

        % ---- assembly API ------------------------------------------------
        function chp = addCentralHeatPlant(obj, name, varargin)
            % ADDCENTRALHEATPLANT  sys.addCentralHeatPlant('CHP', 'TboilerMax',85, ...) -- any
            %   property of the plant as a name-value pair.
            if nargin < 2, name = 'CHP'; end
            chp = DHS.CentralHeatPlant(name, varargin{:});
            obj.plant = chp;
            DHS.registerName(obj, chp);                        % sys.CHP.B1.QMax
            obj.compiled = false;
        end

        function hn = addHydraulicNetwork(obj, varargin)
            % ADDHYDRAULICNETWORK  sys.addHydraulicNetwork('rho',970, 'pReturnRef',2e5) -- any
            %   property of the network as a name-value pair.
            hn = DHS.HydraulicNetwork();
            for i = 1:2:numel(varargin), hn.(varargin{i}) = varargin{i+1}; end
            obj.network = hn;
            if ~isempty(obj.plant)
                hn.plantSupply = obj.plant.supplyPort;
                hn.plantReturn = obj.plant.returnPort;
                obj.plant.supplyPort.network = hn;
                obj.plant.returnPort.network = hn;
            end
            obj.compiled = false;
        end

        function b = addBuilding(obj, name, varargin)
            % ADDBUILDING  sys.addBuilding('Library', 'connD',0.05, 'connLength',20, ...) -- any
            %   property of the building as a name-value pair.
            b = DHS.Building(name, varargin{:});
            DHS.registerName(obj, b);                          % sys.Library.Storey1.Zone2.Wall.R
            obj.buildings{end+1} = b;
            obj.nB = numel(obj.buildings);
            obj.compiled = false;
        end

        function setWeather(obj, csv)
            obj.weather = DHS.Weather(char(csv));
        end

        % ---- compile ---------------------------------------------------------
        function compile(obj)
            assert(~isempty(obj.plant) && ~isempty(obj.network), 'DHS:System:incomplete', ...
                'Add a central heat plant and a hydraulic network first.');
            obj.network.plantSupply = obj.plant.supplyPort;
            obj.network.plantReturn = obj.plant.returnPort;
            obj.plant.supplyPort.network = obj.network;
            obj.plant.returnPort.network = obj.network;
            obj.network.plantPump = obj.plant.supplyPump;
            obj.network.discover();
            obj.network.orderTerminals(obj.buildings);   % the flow vectors are indexed like sys.buildings
            obj.network.compile();

            obj.plantInit = [obj.plant.Tboiler, obj.plant.Tsupply];
            obj.compiled = true;
        end

        % ---- run -----------------------------------------------------------
        function res = run(obj, duration_)
            if ~obj.compiled, obj.compile(); end
            obj.time = obj.startDate;  obj.stepIndex = 0;
            obj.wx = obj.weather.at(obj.startDate);
            if ~isempty(obj.startFunction), obj.startFunction(obj); end
            if ~obj.compiled, obj.compile(); end              % the hook may have changed the structure
            dt = seconds(obj.timeStep);
            if isduration(duration_), total = seconds(duration_); else, total = double(duration_); end
            nt = floor(total/dt) + 1;
            n  = obj.nB;

            obj.plant.reset(obj.plantInit(1), obj.plantInit(2));
            pump0 = obj.plant.supplyPump;  bpv = obj.network.bypassValve;
            for c = {pump0, bpv}
                if ~isempty(c{1}) && ~isempty(c{1}.controller), c{1}.controller.reset(); end
            end
            obj.network.resetLinkControllers();
            pf = obj.pumpFrac;  pump0.speed = pf;
            wfcn = @(t) obj.weather.at(t).Tout;
            for b = 1:n
                obj.buildings{b}.integrator = obj.integrator;
                obj.buildings{b}.sim.solverMode = obj.simMode();
                obj.buildings{b}.bindClock(obj.startDate, obj.timeStep, wfcn);
                obj.buildings{b}.reset(dt);
            end

            obj.network.beginRun();                           % the valves follow their commands with their lags
            for b = 1:n, obj.buildings{b}.beginRun(); end
            runGuard = onCleanup(@() obj.endValveRun());

            time  = obj.startDate + seconds((0:nt-1)'*dt);
            Toutv = zeros(nt,1);
            zc = @() zeros(nt,1);
            P = struct('Tsupply',zc(),'Tboiler',zc(),'Treturn',zc(),'TreturnNet',zc(), ...
                       'TsupSet',zc(),'Qgas',zc(),'Qboiler',zc(),'Qdist_loss',zc(),'Qbase',zc(), ...
                       'eta',zc(),'firing',zc(),'Mtot',zc(),'Mbypass',zc(),'dpPump',zc(),'pSupHeader',zc(),'pumpSpeed',zc(),'bypassPos',zc());
            b0 = struct('name','','Tzone',zc(),'Twall',zc(),'Troof',zc(),'Tmass',zc(), ...
                        'setpoint',zc(),'Qdeliv',zc(),'Qsolar',zc(),'Qint',zc(), ...
                        'Qvent',zc(),'Qfreecool',zc(),'valve',zc(),'pump',zc(),'mdot',zc(), ...
                        'vel',zc(),'Tsup_hx',zc(),'Tret_primary',zc(),'pSup',zc(),'pRet',zc(), ...
                        'Tint_sup',zc(),'Tint_ret',zc(),'mdot_int',zc());
            Bd = repmat(b0,1,n);
            for b = 1:n
                Bd(b).name = obj.buildings{b}.name;
                sg0 = obj.buildings{b}.signals();
                Bd(b).zoneNames = sg0.zoneNames;
                Bd(b).Tzones    = zeros(nt, numel(sg0.zoneNames));
                Bd(b).Qzones    = zeros(nt, numel(sg0.zoneNames));
            end

            W = obj.weather.atVec(time);

            % prime row 1
            Toutv(1) = W.Tout(1);
            wx1 = struct('ghi',W.ghi(1),'dhi',W.dhi(1),'dni',W.dni(1), ...
                         'sunZen',W.sunZen(1),'sunAz',W.sunAz(1),'sunEl',W.sunEl(1), ...
                         'albedo',W.albedo(1),'Tout',W.Tout(1),'Tground',W.Tground(1));
            hyd0 = obj.network.solve(pf);
            P.Tsupply(1)=obj.plant.Tsupply; P.Tboiler(1)=obj.plant.Tboiler; P.eta(1)=obj.plant.eta;
            P.TsupSet(1)=obj.plant.TsupSet; P.Treturn(1)=obj.plant.TretHdr; P.TreturnNet(1)=obj.plant.TretHdr;
            P.Mtot(1)=hyd0.Mtot; P.Mbypass(1)=hyd0.mdotBypass; P.dpPump(1)=hyd0.dpPump; P.pSupHeader(1)=hyd0.pSupHeader;
            P.pumpSpeed(1)=pf;  if ~isempty(bpv), P.bypassPos(1)=bpv.pos; end
            for b = 1:n
                bd = obj.buildings{b};
                bd.prepare(time(1), wx1);
                sg = bd.signals();
                Bd(b).Tzone(1)=sg.Tzone; Bd(b).Twall(1)=sg.Twall;
                Bd(b).Troof(1)=sg.Troof; Bd(b).Tmass(1)=sg.Tmass;
                Bd(b).setpoint(1)=sg.setpoint;
                Bd(b).Tzones(1,:)=sg.Tzones;  Bd(b).Qzones(1,:)=0;
                Bd(b).mdot(1)=hyd0.mdot(b); Bd(b).vel(1)=hyd0.vel(b);
                Bd(b).pSup(1)=hyd0.pSupBranch(b); Bd(b).pRet(1)=hyd0.pRetBranch(b);
                Bd(b).Tsup_hx(1)=obj.plant.Tsupply; Bd(b).Tret_primary(1)=obj.plant.Tsupply;
            end

            for k = 2:nt
                t = time(k-1);  tnp = time(k);
                wx = struct('ghi',W.ghi(k-1),'dhi',W.dhi(k-1),'dni',W.dni(k-1), ...
                            'sunZen',W.sunZen(k-1),'sunAz',W.sunAz(k-1),'sunEl',W.sunEl(k-1), ...
                            'albedo',W.albedo(k-1),'Tout',W.Tout(k-1),'Tground',W.Tground(k-1));
                Toutv(k) = wx.Tout;

                obj.time = t;  obj.wx = wx;  obj.stepIndex = k - 1;
                if ~isempty(obj.stepFunction), obj.stepFunction(obj); end
                for b = 1:n
                    obj.buildings{b}.prepare(t, wx);
                end
                for b = 1:n
                    obj.buildings{b}.control(obj, dt);
                    obj.buildings{b}.solveInternalLoop();
                end

                pf = obj.loopCommand(pump0, pf, dt);                    % central pump
                pump0.speed = pf;
                if ~isempty(bpv), bpv.pos = obj.loopCommand(bpv, bpv.pos, dt); end   % bypass valve
                obj.network.controlLinks(obj, dt);                     % valves and pumps placed in the network
                obj.network.advanceValves(dt);
                hyd  = obj.network.solve(pf);
                mdot = hyd.mdot;
                obj.plant.stepControl(obj, dt);

                TsupPlant = obj.plant.Tsupply;
                Qdel = zeros(1,n); Tri = zeros(1,n); TsupHx = zeros(1,n);
                QlossS = 0; QlossR = 0;
                Tb=obj.plant.Tboiler; Ts=TsupPlant; Trh=obj.plant.TretHdr;
                Qb=0; ef=obj.plant.eta; Tret=TsupPlant;
                maxit = max(1, obj.couplingIterations) + 3;
                for it = 1:maxit %#ok<NASGU>
                    % supply walk: plant -> every pipe (own flow, own heat loss) -> each HX
                    [TsupHx, QlossS] = obj.network.supplyTemperatures(TsupPlant, wx.Tground, mdot, obj.cp);
                    for b = 1:n
                        [Qdel(b), Tri(b)] = obj.buildings{b}.exchange(mdot(b), TsupHx(b));
                    end
                    % return walk: each HX -> every return pipe, enthalpy mixing at junctions
                    [Tret, QlossR] = obj.network.returnTemperatures(Tri, wx.Tground, mdot, obj.cp);
                    [Ts, Tb, Trh, Qb, ef] = obj.plant.evalBoiler(hyd.Mtot, Tret, dt, obj.baseHeatW);
                    if abs(Ts - TsupPlant) < 1e-7 && it >= obj.couplingIterations
                        TsupPlant = Ts; break
                    end
                    TsupPlant = Ts;
                end
                obj.plant.commit(Tb, Trh, Ts, Qb, ef);
                Qbase = obj.baseHeatW;
                Qdist = QlossS + QlossR;

                for b = 1:n
                    obj.buildings{b}.advance(dt, tnp, wx);
                end

                P.Tsupply(k)=obj.plant.Tsupply; P.Tboiler(k)=obj.plant.Tboiler;
                P.TsupSet(k)=obj.plant.TsupSet; P.Treturn(k)=obj.plant.TretHdr;
                P.TreturnNet(k)=Tret; P.Qgas(k)=obj.plant.Qgas;
                P.Qboiler(k)=obj.plant.Qboiler + Qbase; P.eta(k)=obj.plant.eta;
                P.Qdist_loss(k)=Qdist; P.Qbase(k)=Qbase; P.firing(k)=obj.plant.firing;
                P.Mtot(k)=hyd.Mtot; P.Mbypass(k)=hyd.mdotBypass; P.dpPump(k)=hyd.dpPump; P.pSupHeader(k)=hyd.pSupHeader;
                P.pumpSpeed(k)=pf;  if ~isempty(bpv), P.bypassPos(k)=bpv.pos; end
                for b = 1:n
                    sg = obj.buildings{b}.signals();
                    Bd(b).Tzone(k)=sg.Tzone; Bd(b).Twall(k)=sg.Twall; Bd(b).Troof(k)=sg.Troof;
                    Bd(b).Tmass(k)=sg.Tmass; Bd(b).setpoint(k)=sg.setpoint; Bd(b).Qdeliv(k)=sg.Qdeliv;
                    Bd(b).Qsolar(k)=sg.Qsolar; Bd(b).Qint(k)=sg.Qint; Bd(b).Qvent(k)=sg.Qvent;
                    Bd(b).Qfreecool(k)=sg.Qfreecool; Bd(b).valve(k)=sg.valve; Bd(b).pump(k)=sg.pump;
                    Bd(b).Tret_primary(k)=sg.Tret_primary;
                    Bd(b).Tzones(k,:)=sg.Tzones;  Bd(b).Qzones(k,:)=sg.Qzones;
                    Bd(b).Tint_sup(k)=sg.Tint_sup;  Bd(b).Tint_ret(k)=sg.Tint_ret;  Bd(b).mdot_int(k)=sg.mdot_int;
                    Bd(b).mdot(k)=hyd.mdot(b); Bd(b).vel(k)=hyd.vel(b);
                    Bd(b).Tsup_hx(k)=TsupHx(b);
                    Bd(b).pSup(k)=hyd.pSupBranch(b); Bd(b).pRet(k)=hyd.pRetBranch(b);
                end
            end

            res.time = time;  res.Tout = Toutv;  res.plant = P;  res.bldg = Bd;
            res.energy = DHS.System.energySummary(P, Bd, dt);
            res.config = struct('timeStep_s',dt,'couplingIterations',obj.couplingIterations, ...
                                'pumpFrac',obj.pumpFrac,'nBuildings',n);
            obj.result = res;
            if ~isempty(obj.stopFunction), obj.stopFunction(obj); end
            res = obj.result;
        end

        function visualize(obj)
            % VISUALIZE  Draw the assembled district: plant, mains, tees, buildings.
            if ~obj.compiled, obj.compile(); end
            DHS.drawSchematic(obj);
        end
    end

    methods (Access = private)
        function endValveRun(obj)
            if ~isempty(obj.network), obj.network.endRun(); end
            for b = 1:numel(obj.buildings), obj.buildings{b}.endRun(); end
        end

        function m = simMode(obj)
            % RCBS.Simulation solverMode that matches obj.integrator
            switch obj.integrator
                case 'backwardEuler', m = "cached";
                case 'forwardEuler',  m = "forwardEuler";
                case 'exact',         m = "exact";
            end
        end

        function u = loopCommand(obj, comp, u, dt)
            % One sample of the controller on a pump or valve; u is unchanged without one.
            if isempty(comp) || isempty(comp.controller), return, end
            u = min(1, max(0, comp.controller.update(obj, dt)));
        end
    end

    methods (Static, Access = private)
        function e = energySummary(P, Bd, dt)
            k2 = dt / 3.6e6;
            gas  = sum(P.Qgas)       * k2;
            boil = sum(P.Qboiler)    * k2;
            dist = sum(P.Qdist_loss) * k2;
            base = sum(P.Qbase)      * k2;
            del  = 0;
            for i = 1:numel(Bd), del = del + sum(Bd(i).Qdeliv); end
            del  = del * k2;
            e.gas_kWh=gas; e.boiler_kWh=boil; e.delivered_kWh=del;
            e.dist_loss_kWh=dist; e.base_kWh=base;
            e.plant_eff = boil / max(gas, eps);
            e.closure_err = (boil - del - dist - base) / max(boil, eps);
        end
    end
end
