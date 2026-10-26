classdef FixedEffectivenessHeatExchanger < DHS.LoopHeatExchanger
% DHS.FIXEDEFFECTIVENESSHEATEXCHANGER  Heat exchanger whose effectiveness is given by the user and does
%                                      not depend on the flows.
%
%       Q = clamp( eps Cmin (Tsup_primary - Tsec_in) , 0 , Qcap ) ,   eps = effectiveness (constant)
%
%   Use it when the data sheet gives the effectiveness at the operating point and the conductance UA or
%   the flow dependence are not needed. The Modelica Buildings library's plate heat exchanger model
%   offers a constant effectiveness (default 0.8), and the City Energy Analyst sizes its substation
%   exchangers for a design effectiveness of 0.9 (references in docs/dhs-heat-exchanger.md).
%   The heat balance is that of DHS.LoopHeatExchanger and the ports, valve and pump those of
%   DHS.HeatExchanger. The building needs an internal loop connected to hx.internalOutlet and hx.internalInlet.
%
%   Create with  hx = DHS.FixedEffectivenessHeatExchanger('HX', 'effectiveness',0.85, 'Qcap',8e5)
%                building.attachHeatExchanger(hx)
%
%   PROPERTIES (SI, in addition to DHS.LoopHeatExchanger)
%     effectiveness  [-]   fixed effectiveness, 0 < eps <= 1                  (0.8)

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
