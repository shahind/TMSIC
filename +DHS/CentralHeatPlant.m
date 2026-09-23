classdef CentralHeatPlant < handle
% DHS.CENTRALHEATPLANT  Central gas heat plant: boiler(s) + primary pump + the
%                       plant-side water thermal dynamics.
%
%   BUILD IT  (two equivalent styles; see DHS.HydraulicNetwork)
%     chp    = sys.addCentralHeatPlant('CHP');
%     boiler = chp.addBoiler('B1', 'QMax',1.5e6, 'etaCurve',@(Tr) 0.92-0.0025*(Tr-50));
%     pump   = chp.addPump('P0', 'dp0',3.0e5, 'mdotMax',14);     % a CentrifugalPump
%     boiler.connectTo(pump);
%     chp.setSupplySetpoint(70);                        % fixed scalar
%     chp.attachFiringController( DHS.controllers.PID(0.045, 3e-5, 1.5, 150) );  % optional
%
%   or, naming the pump type and wiring it port-by-port:
%     pump = DHS.Hydraulic.CentrifugalPump('P0', 'dp0',3.0e5, 'mdotMax',14);
%     chp.attachPump(pump);
%     pipe1 = DHS.Hydraulic.Pipe('B1->P0');  boiler.connectToPipe('output', pipe1);
%     pipe1.connectOutput(pump.inlet);       % pipe1 is decorative here: the plant's
%                                             % boiler+pump are one lumped pressure node
%
%   PLANT-SIDE WATER DYNAMICS: three
%   lumped stirred-tank water masses in series -- return header (Cw_rh),
%   boiler + buffer (Cw), supply header (Cw_sh) -- plus a low-loss header
%   (hydraulic separator) that recirculates surplus supply water into the return
%   when the network draws less than the boiler-loop flow mdotMinBoiler, a boiler
%   high-limit aquastat (TboilerMax), a standby loss, a burner slew-rate limit
%   and a supply-sensor lag. With these, a FIXED supply setpoint is held to
%   ~+-0.5-2 K as the load and return temperature swing.
%
%   The supply-temperature loop drives the burner firing fraction u in [0,1];
%   Q_gas = u * QgasMax  (QgasMax = sum of boiler QMax). Swap firingController
%   for any DHS.controllers.Controller.
%
%   Units SI: degC, W, kg/s, J/K, Pa, s.

    properties
        name (1,:) char = 'CHP'

        % water masses / low-loss header
        Cw            (1,1) double = 8.0e7
        Cw_rh         (1,1) double = 4.0e6
        Cw_sh         (1,1) double = 5.0e6
        mdotMinBoiler (1,1) double = 2.5
        TboilerMax    (1,1) double = 90
        standbyLossW  (1,1) double = 10e3
        cp            (1,1) double = 4186

        % supply-temperature control
        TsupSet          (1,1) double = 70     % FIXED setpoint [degC]
        sensorTau        (1,1) double = 20     % supply-sensor lag [s]
        firingSlewPerMin (1,1) double = 0.15   % max change in firing fraction per minute
        firingController                       % DHS.controllers.Controller (default PID)

        boilers     cell = {}                  % 1xN DHS.Boiler
        supplyPump                             % a DHS.Hydraulic.Pump: the central pump
    end
    properties
        supplyPort DHS.Hydraulic.Junction
        returnPort DHS.Hydraulic.Junction
    end
    properties (SetAccess = private)
        Tboiler     (1,1) double = 78
        TretHdr     (1,1) double = 50
        Tsupply     (1,1) double = 70
        TsupplyMeas (1,1) double = 70
        Qgas    (1,1) double = 0
        Qboiler (1,1) double = 0
        eta     (1,1) double = 0.92
        firing  (1,1) double = 0
        firingPrev (1,1) double = 0
        hiLimitCut (1,1) logical = false
    end

    methods
        function obj = CentralHeatPlant(name)
            if nargin >= 1, obj.name = name; end
            obj.supplyPort = DHS.Hydraulic.Junction([obj.name '.supply'], 'supply');
            obj.returnPort = DHS.Hydraulic.Junction([obj.name '.return'], 'return');
            obj.firingController = DHS.controllers.PID(0.045, 3e-5, 1.5, 150);
            obj.firingController.name = [obj.name '-firingPID'];
        end

        % ---- assembly API --------------------------------------------------
        function b = addBoiler(obj, name, varargin)
            b = DHS.Boiler(name, varargin{:});
            b.parentPlant = obj;
            obj.boilers{end+1} = b;
        end
        function p = addPump(obj, name, varargin)
            % ADDPUMP  Quick path: builds a centrifugal pump (today's default
            %   physics). For a fixed-displacement pump, build one yourself and
            %   hand it in with attachPump.
            p = DHS.Hydraulic.CentrifugalPump(name, varargin{:});
            obj.attachPump(p);
        end
        function attachPump(obj, p)
            % ATTACHPUMP  Install a pre-built pump (either DHS.Hydraulic.
            %   CentrifugalPump or DHS.Hydraulic.FixedDisplacementPump) as the
            %   plant's central pump.
            assert(isa(p,'DHS.Hydraulic.Pump'), 'DHS:CentralHeatPlant:pump', ...
                'Expected a DHS.Hydraulic.Pump.');
            p.hostPort = obj.supplyPort;
            obj.supplyPump = p;
        end
        function attachFiringController(obj, c)
            % ATTACHFIRINGCONTROLLER  Swap the burner-firing control law.
            assert(isa(c,'DHS.controllers.Controller'), 'DHS:CentralHeatPlant:ctrl', ...
                'Controller must be a DHS.controllers.Controller.');
            obj.firingController = c;
        end
        function setSupplySetpoint(obj, T)
            obj.TsupSet = T;
        end

        function q = QgasMax(obj)
            if isempty(obj.boilers), q = 1.5e6; else
                q = sum(cellfun(@(b) b.QMax, obj.boilers));
            end
        end

        % ---- lifecycle -----------------------------------------------------
        function reset(obj, Tboiler0, Tsupply0)
            if nargin > 1 && ~isempty(Tboiler0), obj.Tboiler = Tboiler0; end
            if nargin > 2 && ~isempty(Tsupply0), obj.Tsupply = Tsupply0; end
            obj.TsupplyMeas = obj.Tsupply;
            obj.TretHdr     = max(20, obj.Tsupply - 20);
            obj.firingController.reset();
            obj.Qgas = 0; obj.Qboiler = 0; obj.firing = 0; obj.firingPrev = 0;
            obj.hiLimitCut = false;
            obj.eta = obj.etaOf(obj.TretHdr);
        end

        function stepControl(obj, dt, aux)
            if nargin < 3, aux = struct(); end
            if obj.sensorTau > 0
                a = dt / (obj.sensorTau + dt);
                obj.TsupplyMeas = obj.TsupplyMeas + a*(obj.Tsupply - obj.TsupplyMeas);
            else
                obj.TsupplyMeas = obj.Tsupply;
            end
            u = min(1, max(0, obj.firingController.update(obj.TsupplyMeas, obj.TsupSet, dt, aux)));
            obj.firing = u;
            if obj.firingSlewPerMin > 0
                df = obj.firingSlewPerMin * (dt/60);
                obj.firing = min(obj.firingPrev + df, max(obj.firingPrev - df, obj.firing));
            end
            obj.firingPrev = obj.firing;
            if obj.Tboiler >= obj.TboilerMax
                obj.hiLimitCut = true;
            elseif obj.Tboiler <= obj.TboilerMax - 3
                obj.hiLimitCut = false;
            end
            if obj.hiLimitCut, obj.firing = 0; end
            obj.Qgas = obj.firing * obj.QgasMax();
        end

        function [Ts, Tb, Trh, Qloop, e] = evalBoiler(obj, mdotPrimary, TretNet, dt, Qbase)
            if nargin < 5, Qbase = 0; end
            mdotNet = max(mdotPrimary, 0);
            mdotB   = max(mdotNet, obj.mdotMinBoiler);
            mcB     = mdotB * obj.cp;
            frec       = max(0, (mdotB - mdotNet) / mdotB);
            TretToHdr  = (1 - frec)*TretNet + frec*obj.Tsupply;
            if obj.Cw_rh > 0
                arh = obj.Cw_rh/dt;
                Trh = (arh*obj.TretHdr + mcB*TretToHdr) / (arh + mcB);
            else
                Trh = TretToHdr;
            end
            e  = obj.etaOf(Trh);
            ab = obj.Cw/dt;
            Tb = (ab*obj.Tboiler + e*obj.Qgas + mcB*Trh - Qbase - obj.standbyLossW) / (ab + mcB);
            if obj.Cw_sh > 0
                ash = obj.Cw_sh/dt;
                Ts  = (ash*obj.Tsupply + mcB*Tb) / (ash + mcB);
            else
                Ts  = Tb;
            end
            Qloop = max(0, mdotNet * obj.cp * (Ts - TretNet));
        end

        function commit(obj, Tb, Trh, Ts, Qloop, e)
            obj.Tboiler = Tb;  obj.TretHdr = Trh;  obj.Tsupply = Ts;
            obj.Qboiler = Qloop;  obj.eta = e;
        end

        function e = etaOf(obj, Tret)
            if isempty(obj.boilers)
                e = min(0.98, max(0.80, 0.92 - 0.0025*(Tret - 50)));
            else
                e = mean(cellfun(@(b) b.etaOf(Tret), obj.boilers));
            end
        end
    end
end
