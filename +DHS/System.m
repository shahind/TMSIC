classdef System < handle
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
%     chp.addPump('P0', 'dp0',3.0e5, 'mdotMax',14);
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
%   This declarative style and the port-wiring style
%   (pipe.connectOutput/connectToPipe, T-junctions, named pump types) build the
%   exact same network -- see DHS.HydraulicNetwork and DHS.Hydraulic.*.
%
%   PER-STEP SEQUENCE  (sequential / Gauss-Seidel with an inner supply/return
%   fixed-point):
%     1. sample the weather;
%     2. each building.prepare(t,wx) -> setpoint / occupancy / gains / solar;
%     3. each building.control(dt,wx) -> valve + pump commands;
%     4. network.solve(pumpFrac) -> branch flows, velocities, node pressures;
%     5. plant.stepControl(dt) -> burner firing;
%     6. inner loop until the plant supply temperature is self-consistent:
%        supply-pipe loss -> HX inlet temp; building.exchange -> delivered heat +
%        primary return; return-pipe loss + mixing -> plant return; plant.evalBoiler;
%     7. plant.commit;
%     8. each building.advance(dt,tNext,wx) -> step its RCBS model one interval;
%     9. log; fire stepCallback(sys,k,t).
%
%   OUTPUT  res.time, res.Tout, res.plant.(...), res.bldg(i).(...), res.energy.(...)

    properties
        startDate  datetime
        timeStep   duration = seconds(60)
        couplingIterations (1,1) double = 2
        pumpFrac   (1,1) double = 1
        baseHeatW  (1,1) double = 0
        cp         (1,1) double = 4186

        weather    DHS.Weather
        plant      DHS.CentralHeatPlant
        network    DHS.HydraulicNetwork
        buildings  cell = {}

        stepCallback = []
    end
    properties (SetAccess = private)
        nB        (1,1) double = 0
        Lsup double = []          % per-building buried supply length [m]
        Lret double = []          % per-building buried return length [m]
        plantInit (1,2) double = [78 70]
        live      struct = struct()
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
            p.parse(varargin{:});
            o = p.Results;
            if ~isempty(o.weather), obj.weather = DHS.Weather(char(o.weather)); end
            obj.startDate = o.startDate;
            obj.timeStep  = o.timeStep;
            obj.couplingIterations = o.couplingIterations;
            obj.pumpFrac  = o.pumpFrac;
            obj.baseHeatW = o.baseHeatW;
        end

        % ---- assembly API ------------------------------------------------
        function chp = addCentralHeatPlant(obj, name)
            if nargin < 2, name = 'CHP'; end
            chp = DHS.CentralHeatPlant(name);
            obj.plant = chp;
            obj.compiled = false;
        end

        function hn = addHydraulicNetwork(obj)
            hn = DHS.HydraulicNetwork();
            obj.network = hn;
            if ~isempty(obj.plant)
                hn.plantSupply = obj.plant.supplyPort;
                hn.plantReturn = obj.plant.returnPort;
                obj.plant.supplyPort.mirror = obj.plant.returnPort;
                obj.plant.returnPort.mirror = obj.plant.supplyPort;
                obj.plant.supplyPort.network = hn;
                obj.plant.returnPort.network = hn;
            end
            obj.compiled = false;
        end

        function b = addBuilding(obj, name)
            b = DHS.Building(name);
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
            obj.plant.supplyPort.mirror = obj.plant.returnPort;
            obj.plant.returnPort.mirror = obj.plant.supplyPort;
            obj.plant.supplyPort.network = obj.network;
            obj.plant.returnPort.network = obj.network;
            obj.network.plantPump = obj.plant.supplyPump;
            obj.network.compile();

            % per-building buried pipe lengths: plant -> feeding junction + connection
            n = obj.nB;
            obj.Lsup = zeros(1,n);  obj.Lret = zeros(1,n);
            for b = 1:n
                bd = obj.buildings{b};
                Ls = bd.connLength;  Lr = bd.connLength;
                j  = bd.inlet.parentPipe;                 % feeding supply junction
                pj = j.parentPipe;
                while ~isempty(pj)
                    Ls = Ls + pj.L;
                    Lr = Lr + pj.L;
                    pj = pj.nodeA.parentPipe;
                end
                obj.Lsup(b) = Ls;  obj.Lret(b) = Lr;
            end
            obj.plantInit = [obj.plant.Tboiler, obj.plant.Tsupply];
            obj.compiled = true;
        end

        % ---- run -----------------------------------------------------------
        function res = run(obj, duration_)
            if ~obj.compiled, obj.compile(); end
            dt = seconds(obj.timeStep);
            if isduration(duration_), total = seconds(duration_); else, total = double(duration_); end
            nt = floor(total/dt) + 1;
            n  = obj.nB;
            Upm = 0.30;                     % fallback W/m/K
            UAs = zeros(1,n); UAr = zeros(1,n);
            for b = 1:n
                UAs(b) = Upm * obj.Lsup(b);
                UAr(b) = Upm * obj.Lret(b);
            end

            obj.plant.reset(obj.plantInit(1), obj.plantInit(2));
            wfcn = @(t) obj.weather.at(t).Tout;
            for b = 1:n
                obj.buildings{b}.bindClock(obj.startDate, obj.timeStep, wfcn);
                obj.buildings{b}.reset(dt);
            end

            time  = obj.startDate + seconds((0:nt-1)'*dt);
            Toutv = zeros(nt,1);
            zc = @() zeros(nt,1);
            P = struct('Tsupply',zc(),'Tboiler',zc(),'Treturn',zc(),'TreturnNet',zc(), ...
                       'TsupSet',zc(),'Qgas',zc(),'Qboiler',zc(),'Qdist_loss',zc(),'Qbase',zc(), ...
                       'eta',zc(),'firing',zc(),'Mtot',zc(),'dpPump',zc(),'pSupHeader',zc());
            b0 = struct('name','','Tzone',zc(),'Twall',zc(),'Troof',zc(),'Tmass',zc(), ...
                        'setpoint',zc(),'Qdeliv',zc(),'Qsolar',zc(),'Qint',zc(), ...
                        'Qvent',zc(),'Qfreecool',zc(),'valve',zc(),'pump',zc(),'mdot',zc(), ...
                        'vel',zc(),'Tsup_hx',zc(),'Tret_primary',zc(),'pSup',zc(),'pRet',zc());
            Bd = repmat(b0,1,n);
            for b = 1:n
                Bd(b).name = obj.buildings{b}.name;
                sg0 = obj.buildings{b}.signals();
                Bd(b).zoneNames = sg0.zoneNames;
                Bd(b).Tzones    = zeros(nt, numel(sg0.zoneNames));
            end

            W = obj.weather.atVec(time);
            hasCb = ~isempty(obj.stepCallback);

            % prime row 1
            Toutv(1) = W.Tout(1);
            wx1 = struct('ghi',W.ghi(1),'dhi',W.dhi(1),'dni',W.dni(1), ...
                         'sunZen',W.sunZen(1),'sunAz',W.sunAz(1),'sunEl',W.sunEl(1), ...
                         'albedo',W.albedo(1),'Tout',W.Tout(1),'Tground',W.Tground(1));
            hyd0 = obj.network.solve(obj.pumpFrac);
            P.Tsupply(1)=obj.plant.Tsupply; P.Tboiler(1)=obj.plant.Tboiler; P.eta(1)=obj.plant.eta;
            P.TsupSet(1)=obj.plant.TsupSet; P.Treturn(1)=obj.plant.TretHdr; P.TreturnNet(1)=obj.plant.TretHdr;
            P.Mtot(1)=hyd0.Mtot; P.dpPump(1)=hyd0.dpPump; P.pSupHeader(1)=hyd0.pSupHeader;
            for b = 1:n
                bd = obj.buildings{b};
                bd.prepare(time(1), wx1);
                sg = bd.signals();
                Bd(b).Tzone(1)=sg.Tzone; Bd(b).Twall(1)=sg.Twall;
                Bd(b).Troof(1)=sg.Troof; Bd(b).Tmass(1)=sg.Tmass;
                Bd(b).setpoint(1)=sg.setpoint;
                Bd(b).Tzones(1,:)=sg.Tzones;
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

                for b = 1:n
                    obj.buildings{b}.prepare(t, wx);
                    obj.buildings{b}.control(dt, wx);
                end

                hyd  = obj.network.solve(obj.pumpFrac);
                mdot = hyd.mdot;
                obj.plant.stepControl(dt, struct('Mtot',hyd.Mtot,'Tout',wx.Tout, ...
                                                 'Tret_prev',P.Treturn(max(k-1,1))));

                TsupPlant = obj.plant.Tsupply;
                Qdel = zeros(1,n); TretP = zeros(1,n); TsupHx = zeros(1,n);
                QlossS = zeros(1,n); QlossR = zeros(1,n);
                Tb=obj.plant.Tboiler; Ts=TsupPlant; Trh=obj.plant.TretHdr;
                Qb=0; ef=obj.plant.eta; Tret=TsupPlant;
                maxit = max(1, obj.couplingIterations) + 3;
                for it = 1:maxit %#ok<NASGU>
                    for b = 1:n
                        mc = max(mdot(b),1e-6)*obj.cp;
                        dTs = UAs(b)*(TsupPlant - wx.Tground)/mc;
                        TsupHx(b) = max(wx.Tground, TsupPlant - dTs);
                        QlossS(b) = mc*(TsupPlant - TsupHx(b));
                        [Qdel(b), Tri] = obj.buildings{b}.exchange(mdot(b), TsupHx(b));
                        dTr = UAr(b)*(Tri - wx.Tground)/mc;
                        TretP(b) = max(wx.Tground, Tri - dTr);
                        QlossR(b) = mc*(Tri - TretP(b));
                    end
                    if sum(mdot) > 1e-9
                        Tret = sum(mdot.*TretP)/sum(mdot);
                    else
                        Tret = mean(TretP);
                    end
                    [Ts, Tb, Trh, Qb, ef] = obj.plant.evalBoiler(hyd.Mtot, Tret, dt, obj.baseHeatW);
                    if abs(Ts - TsupPlant) < 1e-7 && it >= obj.couplingIterations
                        TsupPlant = Ts; break
                    end
                    TsupPlant = Ts;
                end
                obj.plant.commit(Tb, Trh, Ts, Qb, ef);
                Qbase = obj.baseHeatW;
                Qdist = sum(QlossS) + sum(QlossR);

                for b = 1:n
                    obj.buildings{b}.advance(dt, tnp, wx);
                end

                P.Tsupply(k)=obj.plant.Tsupply; P.Tboiler(k)=obj.plant.Tboiler;
                P.TsupSet(k)=obj.plant.TsupSet; P.Treturn(k)=obj.plant.TretHdr;
                P.TreturnNet(k)=Tret; P.Qgas(k)=obj.plant.Qgas;
                P.Qboiler(k)=obj.plant.Qboiler + Qbase; P.eta(k)=obj.plant.eta;
                P.Qdist_loss(k)=Qdist; P.Qbase(k)=Qbase; P.firing(k)=obj.plant.firing;
                P.Mtot(k)=hyd.Mtot; P.dpPump(k)=hyd.dpPump; P.pSupHeader(k)=hyd.pSupHeader;
                for b = 1:n
                    sg = obj.buildings{b}.signals();
                    Bd(b).Tzone(k)=sg.Tzone; Bd(b).Twall(k)=sg.Twall; Bd(b).Troof(k)=sg.Troof;
                    Bd(b).Tmass(k)=sg.Tmass; Bd(b).setpoint(k)=sg.setpoint; Bd(b).Qdeliv(k)=sg.Qdeliv;
                    Bd(b).Qsolar(k)=sg.Qsolar; Bd(b).Qint(k)=sg.Qint; Bd(b).Qvent(k)=sg.Qvent;
                    Bd(b).Qfreecool(k)=sg.Qfreecool; Bd(b).valve(k)=sg.valve; Bd(b).pump(k)=sg.pump;
                    Bd(b).Tret_primary(k)=sg.Tret_primary;
                    Bd(b).Tzones(k,:)=sg.Tzones;
                    Bd(b).mdot(k)=hyd.mdot(b); Bd(b).vel(k)=hyd.vel(b);
                    Bd(b).Tsup_hx(k)=TsupHx(b);
                    Bd(b).pSup(k)=hyd.pSupBranch(b); Bd(b).pRet(k)=hyd.pRetBranch(b);
                end

                if hasCb
                    obj.live = obj.snapshot();
                    obj.stepCallback(obj, k, tnp);
                end
            end

            res.time = time;  res.Tout = Toutv;  res.plant = P;  res.bldg = Bd;
            res.energy = DHS.System.energySummary(P, Bd, dt);
            res.config = struct('timeStep_s',dt,'couplingIterations',obj.couplingIterations, ...
                                'pumpFrac',obj.pumpFrac,'nBuildings',n);
        end

        function s = snapshot(obj)
            n = obj.nB;
            s.t       = obj.buildings{1}.sim.t;
            s.Tsupply = obj.plant.Tsupply;
            s.Tboiler = obj.plant.Tboiler;
            s.Qgas    = obj.plant.Qgas;
            s.eta     = obj.plant.eta;
            s.Tzone   = arrayfun(@(b) obj.buildings{b}.zoneTemp(), 1:n);
            s.valve   = arrayfun(@(b) obj.buildings{b}.heatExchanger.valve.pos, 1:n);
            s.Qdeliv  = arrayfun(@(b) obj.buildings{b}.Qdel, 1:n);
        end

        function visualize(obj)
            % VISUALIZE  Draw the assembled district: plant, mains, tees, buildings.
            if ~obj.compiled, obj.compile(); end
            DHS.drawSchematic(obj);
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
