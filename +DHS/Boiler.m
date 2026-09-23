classdef Boiler < handle
% DHS.BOILER  A gas boiler stage in the central heat plant.
%
%   Carries the burner capacity and the part-load efficiency curve. The plant's
%   lumped water-mass thermal dynamics live in DHS.CentralHeatPlant; a Boiler is
%   the burner + its efficiency characteristic. Create with  chp.addBoiler(...).
%
%   Efficiency vs return-water temperature (condensing gas boiler; ASHRAE Systems
%   & Equipment 2020 Ch.32):
%       eta(Tret) = etaCurve(Tret)                       if etaCurve is set
%                 = clamp(etaRef - etaSlope*(Tret-TetaRef), etaMin, etaMax)  else
%
%   PROPERTIES (SI)
%     name      char
%     QMax      [W]     maximum burner heat release
%     etaCurve  handle  optional  @(Tret) -> efficiency [-]
%     etaRef etaSlope TetaRef etaMin etaMax   default curve parameters

    properties
        name     (1,:) char = ''
        QMax     (1,1) double = 1.5e6
        etaCurve             = []
        etaRef   (1,1) double = 0.92
        etaSlope (1,1) double = 0.0025
        TetaRef  (1,1) double = 50
        etaMin   (1,1) double = 0.80
        etaMax   (1,1) double = 0.98
    end
    properties (SetAccess = ?DHS.CentralHeatPlant)
        feedsPump  = []       % DHS.Hydraulic.Pump the boiler discharges into (visual/topology)
        parentPlant = []      % the DHS.CentralHeatPlant this boiler belongs to (set by chp.addBoiler)
    end

    methods
        function obj = Boiler(name, varargin)
            if nargin >= 1, obj.name = name; end
            for i = 1:2:numel(varargin), obj.(varargin{i}) = varargin{i+1}; end
        end

        function connectTo(obj, pump)
            % CONNECTTO  Record that this boiler discharges into `pump`.
            assert(isa(pump,'DHS.Hydraulic.Pump'), 'DHS:Boiler:connectTo', 'Expected a DHS.Hydraulic.Pump.');
            obj.feedsPump = pump;
        end

        function p = connectToPipe(obj, varargin)
            % CONNECTTOPIPE  Port-wiring: boiler.connectToPipe('output', pipe).
            %   The plant's boiler and pump are one lumped pressure node in this
            %   model, so this wires PIPE to the plant's own supply port -- see
            %   DHS.Hydraulic.Pump.inlet for the same convention on the pump side.
            if numel(varargin) == 1, pipe = varargin{1}; else, pipe = varargin{2}; end
            assert(~isempty(obj.parentPlant), 'DHS:Boiler:noPlant', ...
                'Boiler "%s" is not attached to a plant yet (use chp.addBoiler).', obj.name);
            p = obj.parentPlant.supplyPort.connectToPipe(pipe);
        end

        function j = outlet(obj)
            % OUTLET  see connectToPipe.
            assert(~isempty(obj.parentPlant), 'DHS:Boiler:noPlant', ...
                'Boiler "%s" is not attached to a plant yet (use chp.addBoiler).', obj.name);
            j = obj.parentPlant.supplyPort;
        end

        function e = etaOf(obj, Tret)
            if ~isempty(obj.etaCurve)
                e = obj.etaCurve(Tret);
            else
                e = obj.etaRef - obj.etaSlope*(Tret - obj.TetaRef);
            end
            e = min(obj.etaMax, max(obj.etaMin, e));
        end
    end
end
