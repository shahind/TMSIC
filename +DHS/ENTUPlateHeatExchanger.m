classdef ENTUPlateHeatExchanger < DHS.LoopHeatExchanger
% DHS.ENTUPLATEHEATEXCHANGER  Counterflow plate exchanger by the effectiveness-NTU method.
%
%   hx = b.addHeatExchanger('HX', 'UA',3.5e4, 'Qcap',8e5)
%   NTU = UA/Cmin and eps from the counterflow relation (Incropera and DeWitt). UA [W/K] (4e4).
%   The building needs its internal loop connected. See docs/dhs-heat-exchanger.md.

    properties
        UA (1,1) double = 4.0e4
    end

    methods
        function obj = ENTUPlateHeatExchanger(name, varargin)
            if nargin < 1, name = 'HX'; end
            obj@DHS.LoopHeatExchanger(name, varargin{:});
        end

        function EC = effectivenessCmin(obj, mdotPrimary, mdotSec)
            % effectiveness times the smaller capacity rate [W/K] of the counterflow exchanger
            Cp = mdotPrimary * obj.cp;  Cs = mdotSec * obj.cp;
            Cmin = min(Cp, Cs);  Cmax = max(Cp, Cs);  Cr = Cmin / Cmax;
            NTU  = obj.UA / Cmin;
            if abs(1 - Cr) < 1e-6
                eps = NTU / (1 + NTU);
            else
                ex  = exp(-NTU * (1 - Cr));
                eps = (1 - ex) / (1 - Cr * ex);
            end
            EC = eps * Cmin;
        end
    end
end
