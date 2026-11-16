classdef FixedEffectivenessHeatExchanger < DHS.LoopHeatExchanger
% DHS.FIXEDEFFECTIVENESSHEATEXCHANGER  Exchanger with a constant effectiveness.
%
%   hx = DHS.FixedEffectivenessHeatExchanger('HX', 'effectiveness',0.85, 'Qcap',8e5);
%   b.attachHeatExchanger(hx);
%   effectiveness [-] (0.8). The building needs its internal loop connected.
%   See docs/dhs-heat-exchanger.md.

    properties
        effectiveness (1,1) double {mustBeGreaterThan(effectiveness,0), mustBeLessThanOrEqual(effectiveness,1)} = 0.8
    end

    methods
        function obj = FixedEffectivenessHeatExchanger(name, varargin)
            if nargin < 1, name = 'HX'; end
            obj@DHS.LoopHeatExchanger(name, varargin{:});
        end

        function EC = effectivenessCmin(obj, mdotPrimary, mdotSec)
            EC = obj.effectiveness * min(mdotPrimary, mdotSec) * obj.cp;
        end
    end
end
