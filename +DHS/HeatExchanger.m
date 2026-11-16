classdef (Abstract) HeatExchanger < dynamicprops
% DHS.HEATEXCHANGER  Abstract substation heat exchanger with its primary valve and pump.
%
%   Types: DHS.ENTUPlateHeatExchanger and DHS.FixedEffectivenessHeatExchanger (building with an internal
%   loop), DHS.IdealHeatExchanger (building without one). Create the plate type with
%   b.addHeatExchanger('HX','UA',..,'Qcap',..), any other with b.attachHeatExchanger(hx).
%
%   Ports: districtInlet/districtOutlet (the building's supply and return junctions) and
%   internalOutlet/internalInlet (where the internal loop starts and ends).
%   Pressure loss: K = dpNomPrimary/mdotNomPrimary^2 plus the valve. hx.valve and hx.pump take
%   controllers; the pump is stopped by default.
%   Qcap [W], internalVolume [L] (5), cp 4186 J/kg/K, dpNomPrimary [Pa] (3e4), mdotNomPrimary [kg/s].
%   See docs/dhs-heat-exchanger.md.

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
