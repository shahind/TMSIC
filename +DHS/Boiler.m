classdef Boiler < handle
% DHS.BOILER  A gas boiler stage: a burner capacity and a part-load efficiency curve.
%
%   Create it with chp.addBoiler('B1', 'QMax',1.5e6).
%   Efficiency: etaCurve(Tret) if given, else clip(etaRef - etaSlope*(Tret - TetaRef), etaMin, etaMax).
%   QMax [W]; etaRef 0.92, etaSlope 0.0025 1/K, TetaRef 50 degC, etaMin 0.80, etaMax 0.98.
%   controller: a DHS.controllers.Controller that sets the firing fraction 0..1.
%   See docs/dhs-plant.md.

    properties
        name     (1,:) char = ''
        QMax     (1,1) double = 1.5e6
        etaCurve             = []
        etaRef   (1,1) double = 0.92
        etaSlope (1,1) double = 0.0025
        TetaRef  (1,1) double = 50
        etaMin   (1,1) double = 0.80
        etaMax   (1,1) double = 0.98
        controller           = []
    end
    properties (SetAccess = ?DHS.CentralHeatPlant)
        feedsPump  = []       % DHS.Hydraulic.Pump the boiler discharges into (visual/topology)
        parentPlant = []      % the DHS.CentralHeatPlant this boiler belongs to (set by chp.addBoiler)
        firing     (1,1) double = 0   % firing fraction this step
        firingPrev (1,1) double = 0
    end

    methods
        function obj = Boiler(name, varargin)
            if nargin >= 1, obj.name = name; end
            for i = 1:2:numel(varargin), obj.(varargin{i}) = varargin{i+1}; end
        end

        function attachController(obj, c)
            % ATTACHCONTROLLER  Attach a feedback law that sets the firing fraction each step.
            assert(isa(c,'DHS.controllers.Controller'), 'DHS:Boiler:ctrl', ...
                'Controller must be a DHS.controllers.Controller.');
            obj.controller = c;
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
