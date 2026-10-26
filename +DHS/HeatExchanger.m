classdef (Abstract) HeatExchanger < dynamicprops
% DHS.HEATEXCHANGER  Abstract substation heat exchanger: its primary valve & pump, its ports and the
%                    pressure loss. The concrete types differ in how they find the delivered heat.
%
%   Three types ship with the toolbox (the same pattern as the pumps):
%
%   For a building WITH an internal loop (DHS.LoopHeatExchanger): the internal side is the building's
%   loop, so the heat follows from the district temperatures and flow and from the temperature and flow
%   of the water coming back from the loop.
%     DHS.ENTUPlateHeatExchanger            counterflow plate exchanger, effectiveness from NTU = UA/Cmin
%     DHS.FixedEffectivenessHeatExchanger   effectiveness fixed by the user
%   For a building WITHOUT an internal loop:
%     DHS.IdealHeatExchanger                the exchanger is a simple radiator that the district water
%                                           flows through (the radiator model of EN 442, as in the
%                                           Modelica Buildings library): the heat follows from the
%                                           district temperature and flow and the room temperature
%   Create the default type with  building.addHeatExchanger('HX', 'UA',..,'Qcap',..)  (an
%   ENTUPlateHeatExchanger) and any other with
%       building.attachHeatExchanger( DHS.FixedEffectivenessHeatExchanger('HX', 'effectiveness',0.85, 'Qcap',..) )
%       building.attachHeatExchanger( DHS.IdealHeatExchanger('HX', 'Qnom',8e5) )
%
%   FOUR PORTS  districtInlet / districtOutlet (the building's supply and return junctions, connected to
%   the district network with  tee.portC.connect(building); building.connect(returnJunction))  and
%   internalOutlet / internalInlet (the junctions where the building's internal loop starts and ends;
%   the first use of either creates the loop):
%       hx.internalOutlet.addPipe(0.05, 4)  ...  returnPipe.connect(hx.internalInlet)
%   A loop heat exchanger needs both internal ports connected and an ideal one needs none: running a
%   building that does not satisfy this stops with an error that names the ports.
%
%   PRIMARY-SIDE PRESSURE LOSS  The valve plus the exchanger body
%   itself. The body loss is quoted, the same way a manufacturer's data sheet
%   does, as a design pressure drop dpNomPrimary at a design flow mdotNomPrimary
%   (a typical plate heat exchanger primary-side design drop in a district-heating
%   substation is of order a few tens of kPa), giving a fixed K = dpNomPrimary/mdotNomPrimary^2
%   -- the same dp ~ mdot^2 turbulent-flow form as a pipe or a valve, but sized to
%   each unit's own rating rather than one constant every instance shares (matching
%   Simscape's own "Pressure loss coefficient" option for this component).
%
%   Owns a valve and a pump on the primary side (obj.valve, obj.pump; a
%   DHS.Hydraulic.CentrifugalPump). The valve sets the building's flow. The pump
%   is a booster in series with the valve and is stopped (speed 0) by default;
%   set hx.pump.speed or attach a controller to use it. Attach controllers to either:
%       hx.valve.attachController(c) ,  hx.pump.attachController(c)
%   or swap the pump type entirely:
%       hx.attachPump( DHS.Hydraulic.FixedDisplacementPump('P','mdotRated',4,'dpMax',2e5) )
%   A valve or pump you attach is reachable by its own name:
%   hx.attachValve(DHS.Hydraulic.Valve('V1','Kvs',12)) gives hx.V1.Kvs.
%
%   PROPERTIES (SI, common to all types)
%     name          char
%     Qcap          [W]     substation heat-delivery limit
%     internalVolume [L]    water in the exchanger's internal side and its manifolds (5); the loop
%                           water also counts the volume of the loop pipes
%     cp            [J/kg/K] water specific heat                         (4186)
%     dpNomPrimary  [Pa]    HX-body primary pressure drop at mdotNomPrimary (3.0e4)
%     mdotNomPrimary [kg/s] primary flow the dpNomPrimary rating is quoted at;
%                           defaults from Qcap/(cp*20 K) if left empty
%     valve         DHS.Hydraulic.Valve  (primary control valve)
%     pump          DHS.Hydraulic.Pump   (primary booster pump, stopped by default)
%   LIVE STATE
%     Qdel        [W]     delivered heat this step
%     TretPrimary [degC]  primary return temperature this step

    properties
        name           (1,:) char = 'HX'
        Qcap           (1,1) double = 5.0e5
        internalVolume (1,1) double = 5
        cp             (1,1) double = 4186
        dpNomPrimary   (1,1) double = 3.0e4
        mdotNomPrimary        double = []
        valve          DHS.Hydraulic.Valve
        pump                                   % a DHS.Hydraulic.Pump: the primary pump
    end
    properties (SetAccess = protected)
        Qdel        (1,1) double = 0
        TretPrimary (1,1) double = NaN
    end
    properties (Access = ?DHS.Building)
        hostBuilding = []     % the DHS.Building this substation belongs to
    end
    properties (Dependent, SetAccess = private)
        districtInlet         % the building's supply junction
        districtOutlet        % the building's return junction
        internalOutlet        % supply junction of the internal loop (water leaving the exchanger)
        internalInlet         % return junction of the internal loop (water entering the exchanger)
    end

    methods (Abstract)
        tf = usesInternalLoop(obj)     % true: the internal side is the building's loop; false: the exchanger is the emitter
    end

    methods
        function obj = HeatExchanger(name, varargin)
            if nargin >= 1, obj.name = name; end
            obj.valve = DHS.Hydraulic.Valve([obj.name '.valve']);
            obj.pump  = DHS.Hydraulic.CentrifugalPump([obj.name '.pump'], 'speed', 0);
            for i = 1:2:numel(varargin), obj.(varargin{i}) = varargin{i+1}; end
        end

        function attachPump(obj, p)
            % ATTACHPUMP  Install a pre-built primary pump (centrifugal or
            %   fixed-displacement) in place of the default.
            assert(isa(p,'DHS.Hydraulic.Pump'), 'DHS:HeatExchanger:pump', ...
                'Expected a DHS.Hydraulic.Pump.');
            if ~isempty(obj.hostBuilding), p.hostPort = obj.hostBuilding.inlet; end
            obj.pump = p;
            DHS.registerName(obj, p);                          % hx.Booster.dp0
        end

        function attachValve(obj, v)
            % ATTACHVALVE  Install a pre-built primary control valve.
            assert(isa(v,'DHS.Hydraulic.Valve'), 'DHS:HeatExchanger:valve', ...
                'Expected a DHS.Hydraulic.Valve.');
            obj.valve = v;
            DHS.registerName(obj, v);                          % hx.V1.Kvs
        end

        function j = get.districtInlet(obj),  j = obj.host().inlet;  end
        function j = get.districtOutlet(obj), j = obj.host().outlet; end
        function j = get.internalOutlet(obj), j = obj.host().ensureInternalLoop().plantSupply; end
        function j = get.internalInlet(obj),  j = obj.host().ensureInternalLoop().plantReturn; end

        function K = primaryResistance(obj, rho)
            % PRIMARYRESISTANCE  valve + HX-body hydraulic resistance [Pa/(kg/s)^2].
            mNom = obj.mdotNomPrimary;
            if isempty(mNom), mNom = max(obj.Qcap/(obj.cp*20), 0.5); end   % 20 K design drop
            Khx = obj.dpNomPrimary / mNom^2;
            K   = obj.valve.resistance(rho) + Khx;
        end
    end

    methods (Access = private)
        function b = host(obj)
            assert(~isempty(obj.hostBuilding), 'DHS:HeatExchanger:noHost', ...
                'Heat exchanger "%s" is not attached to a building yet.', obj.name);
            b = obj.hostBuilding;
        end
    end
end
