classdef Radiator < handle
% DHS.RADIATOR  A zone's radiator: one branch of the building's internal loop.
%
%   The radiator is a lump of metal that takes heat from the water and gives it to the zone air. It
%   is an R-C-R element, and the water side is a flow-dependent resistance:
%
%       water --(UAwm, effectiveness)--> metal (C) --(UAma)--> zone air
%
%     water to metal   the water cools along the radiator against the metal temperature Tm,
%                      Tout = Tm + (Tin - Tm) exp(-UAwm/(mdot cp)),
%                      so Qw = a (Tin - Tm) with a = mdot cp (1 - exp(-UAwm/(mdot cp))): the
%                      water-side conductance a grows with the flow and saturates at mdot cp
%     metal            C dTm/dt = Qw - Qair                               (backward Euler)
%     metal to air     Qair = UAma (Tm - Tzone), the heat the zone receives
%
%   The zone stays an RC model: this element only computes Qair, which the building injects at the
%   zone's air node. With no flow the radiator just cools to the zone.
%
%   WIRING  A radiator is a component of the loop like a pipe: water comes in from a pipe or a valve
%   and leaves to a return pipe, and it is connected to the zone it heats. The valve, the service
%   pipes and any pump are components of their own (DHS.Hydraulic.Valve, Pipe), put where you want them.
%       rad = DHS.Radiator('rad1', 'Qdes',8e3);                % or pipe.addRadiator('rad1', 'Qdes',8e3)
%       tee.portC.connect(pipe1);  pipe1.connect(valve1);  valve1.connect(pipe2);  pipe2.connect(rad);
%       rad.connect(returnPipe1);  returnPipe1.connect(returnJunction);
%       rad.connect(zone1, R);                                 % heat to an RCBS zone, R in K/W (optional)
%   The radiator's own pressure drop is dpBody at the design flow.
%
%   CONSTRUCT  r = DHS.Radiator('Lobby', 'Qdes',8e3)
%     'Qdes' [W] sizes the thermal parameters (below) for the design water temperatures; any of
%     them can be given directly instead.
%
%   PROPERTIES (SI)
%     name       char
%     Qdes       [W]     design heat output
%     Tsup Tret  [degC]  design supply and return water temperatures   (70, 50)
%     Tair       [degC]  design air temperature                         (20)
%     epsDes     [-]     design water-to-metal effectiveness           (0.9)
%     UAwm       [W/K]   water-to-metal conductance       (from Qdes, Tsup, Tret, epsDes)
%     UAma       [W/K]   metal-to-air conductance         (from Qdes; 1/R when connected to a zone with R)
%     C          [J/K]   metal and water capacity         (20 kJ/K per kW of Qdes)
%     mdotDes    [kg/s]  design flow                      (Qdes / (cp (Tsup - Tret)))
%     dpBody     [Pa]    pressure drop of the radiator at the design flow           (5000)
%     pipeD      [m]     pipe diameter for 0.8 m/s at the design flow (read only), a size to use for its pipes
%     zone               the RCBS zone it heats (set by rad.connect(zone)); the only zone of a one-zone building if empty
%   LIVE STATE
%     Tmetal     [degC]  metal temperature
%     mdot       [kg/s]  flow through the radiator
%     Tin Tout   [degC]  water temperatures at the radiator
%     Qwater     [W]     heat from the water to the metal
%     Qair       [W]     heat from the metal to the zone air
%     Tzone setpoint     the zone's air temperature and setpoint (set by the building each step)

    properties
        name   (1,:) char = ''
        Qdes   (1,1) double = NaN
        Tsup   (1,1) double = 70
        Tret   (1,1) double = 50
        Tair   (1,1) double = 20
        epsDes (1,1) double = 0.9
        UAwm   (1,1) double = NaN
        UAma   (1,1) double = NaN
        C      (1,1) double = NaN
        mdotDes (1,1) double = NaN
        cp     (1,1) double = 4186
        dpBody (1,1) double = 5000
        zone   = []
        integrator (1,:) char {mustBeMember(integrator, {'backwardEuler','forwardEuler','exact'})} = 'backwardEuler'
        % ends of the radiator in the hydraulic network (set by connect)
        supplyNode = []
        returnNode = []
        teeSide (1,:) char = ''
    end
    properties (SetAccess = private)
        Tmetal  (1,1) double = 20
        mdot    (1,1) double = 0
        Tin     (1,1) double = NaN
        Tout    (1,1) double = NaN
        Qwater  (1,1) double = 0
        Qair    (1,1) double = 0
        dp      (1,1) double = 0
        TmetalNext (1,1) double = 20
    end
    properties
        Tzone    (1,1) double = NaN
        setpoint (1,1) double = NaN
    end
    properties (Dependent, SetAccess = private)
        pipeD
    end

    methods
        function obj = Radiator(name, varargin)
            if nargin >= 1, obj.name = name; end
            for i = 1:2:numel(varargin), obj.(varargin{i}) = varargin{i+1}; end
            obj.sizeFromDesign();
        end

        function D = get.pipeD(obj)
            D = max(0.015, sqrt(4*obj.mdotDes/(pi*983*0.8)));
        end

        % ---- wiring ---------------------------------------------------------------------
        function dst = connect(obj, dst, varargin)
            % CONNECT  rad.connect(returnPipe) / rad.connect(returnJunction): the water leaves here;
            %   rad.connect(zone, R): the radiator heats an RCBS zone through the resistance R [K/W].
            DHS.Hydraulic.connectEnds(obj, dst, varargin{:});
        end

        function x = addPipe(obj, varargin),     x = DHS.Hydraulic.addOn(obj, 'pipe', varargin{:});     end
        function x = addValve(obj, varargin),    x = DHS.Hydraulic.addOn(obj, 'valve', varargin{:});    end
        function x = addPump(obj, varargin),     x = DHS.Hydraulic.addOn(obj, 'pump', varargin{:});     end
        function x = addTee(obj, varargin),      x = DHS.Hydraulic.addOn(obj, 'tee', varargin{:});      end

        function connectZone(obj, zone, R)
            % CONNECTZONE  Called by rad.connect(zone, R): the zone this radiator heats and, optionally, the
            %   resistance R [K/W] from the radiator metal to the zone air (UAma = 1/R).
            obj.zone = zone;
            if nargin >= 3 && ~isempty(R), obj.UAma = 1/R; end
        end

        % ---- thermal model ----------------------------------------------------------
        function [Qair, Tout, TmNew, Qwater] = response(obj, mdot, Tin, Tzone, dt)
            % RESPONSE  Heat to the zone air, water outlet temperature and new metal temperature for
            %   water at flow MDOT and temperature TIN, zone air at TZONE, over a step DT [s].
            %   Pure function of the current state; commit() stores it. The metal temperature is
            %   advanced with obj.integrator: 'backwardEuler' (default, implicit), 'forwardEuler'
            %   (explicit, stable for dt < C/(a + UAma)) or 'exact' (the exact solution for constant
            %   inputs over the step). The heats are the step averages, so the first law holds in each step.
            G2 = obj.UAma;
            if mdot > 1e-9
                a = mdot*obj.cp * (1 - exp(-obj.UAwm/(mdot*obj.cp)));    % water-side conductance
            else
                a = 0;
            end
            Tm = obj.Tmetal;
            switch obj.integrator
                case 'backwardEuler'
                    Cd = obj.C/dt;
                    TmNew = (Cd*Tm + a*Tin + G2*Tzone) / (Cd + a + G2);
                    Qwater = a * (Tin - TmNew);
                    Qair   = G2 * (TmNew - Tzone);
                case 'forwardEuler'
                    if dt*(a + G2)/obj.C > 2
                        warning('DHS:Radiator:forwardEulerUnstable', ...
                            'Radiator "%s": forwardEuler with a step of %.3g s is unstable (limit %.3g s); use a smaller step or backwardEuler.', ...
                            obj.name, dt, 2*obj.C/(a + G2));
                    end
                    Qwater = a * (Tin - Tm);
                    Qair   = G2 * (Tm - Tzone);
                    TmNew  = Tm + dt*(Qwater - Qair)/obj.C;
                case 'exact'
                    lam = (a + G2)/obj.C;
                    if lam*dt < 1e-12
                        TmNew = Tm;  Tbar = Tm;
                    else
                        Tss = (a*Tin + G2*Tzone)/(a + G2);
                        e1  = exp(-lam*dt);
                        TmNew = Tss + (Tm - Tss)*e1;
                        Tbar  = Tss + (Tm - Tss)*(1 - e1)/(lam*dt);        % mean metal temperature over the step
                    end
                    Qwater = a * (Tin - Tbar);
                    Qair   = G2 * (Tbar - Tzone);
            end
            if mdot > 1e-9, Tout = Tin - Qwater/(mdot*obj.cp); else, Tout = obj.Tmetal; end
        end

        function store(obj, mdot, Tin, Tout, Qwater, Qair, TmNew)
            % STORE  Keep the results of the last response() (live state), to be committed by commit().
            obj.mdot = mdot;  obj.Tin = Tin;  obj.Tout = Tout;
            obj.Qwater = Qwater;  obj.Qair = Qair;  obj.TmetalNext = TmNew;
        end

        function commit(obj)
            obj.Tmetal = obj.TmetalNext;
        end

        function reset(obj, Tzone)
            % RESET  Start a run with the metal at the zone temperature.
            obj.Tmetal = Tzone;  obj.TmetalNext = Tzone;
            obj.mdot = 0;  obj.Qwater = 0;  obj.Qair = 0;  obj.Tin = NaN;  obj.Tout = NaN;
        end

        % ---- hydraulic branch protocol (DHS.HydraulicNetwork) ---------------------------
        function K = branchResistance(obj, rho, mu, m)
            % BRANCHRESISTANCE  The radiator's own pressure drop (plus the tee's loss if it is wired
            %   straight to a tee port) [Pa/(kg/s)^2]. Pipes and valves before and after it are
            %   links of their own.
            if nargin < 4, m = obj.mdot; end
            K = obj.dpBody / obj.mdotDes^2;
            if ~isempty(obj.teeSide) && isa(obj.supplyNode, 'DHS.Hydraulic.TJunction')
                K = K + obj.supplyNode.teeLossK(obj.teeSide, rho, mu, max(m, 0.02));
            end
        end

        function p = branchPump(~)
            p = DHS.Hydraulic.stoppedPump();
        end

        function m = branchFlow(obj),  m = obj.mdot; end

        function vel = setBranchResult(obj, m, ~, ~, ~, ~)
            obj.mdot = m;
            obj.dp = obj.dpBody * (m/obj.mdotDes)^2;
            vel = 0;
        end

        function [T, ql] = inletTemperature(~, Tnode, ~, ~, ~)
            T = Tnode;  ql = 0;
        end

        function [T, ql] = outletTemperature(~, Tout, ~, ~, ~)
            T = Tout;  ql = 0;
        end
    end

    methods (Access = private)
        function sizeFromDesign(obj)
            % Fill every thermal parameter that was not given from Qdes and the design temperatures.
            if isnan(obj.Qdes), return, end
            if isnan(obj.mdotDes), obj.mdotDes = obj.Qdes / (obj.cp * (obj.Tsup - obj.Tret)); end
            if isnan(obj.UAwm)
                obj.UAwm = -obj.mdotDes * obj.cp * log(1 - obj.epsDes);
            end
            if isnan(obj.UAma)
                Tm = obj.Tsup - (obj.Tsup - obj.Tret)/obj.epsDes;           % metal temperature at design
                obj.UAma = obj.Qdes / (Tm - obj.Tair);
            end
            if isnan(obj.C), obj.C = 20e3 * obj.Qdes/1e3; end
        end
    end
end
