classdef ENTUPlateHeatExchanger < DHS.LoopHeatExchanger
% DHS.ENTUPLATEHEATEXCHANGER  Counterflow plate heat exchanger by the effectiveness-NTU method: the
%                             effectiveness follows from the conductance UA and the two flows.
%
%       Cp = mdot_p cp ;  Cs = mdot_s cp ;  Cmin = min(Cp, Cs) ;  Cmax = max(Cp, Cs) ;  Cr = Cmin/Cmax
%       NTU = UA/Cmin
%       eps = (1 - exp(-NTU (1-Cr))) / (1 - Cr exp(-NTU (1-Cr)))        (Cr < 1)
%           = NTU/(1 + NTU)                                              (Cr -> 1)
%
%   so the effectiveness changes with the flow regime: a small flow on either side raises NTU and eps,
%   a large one lowers them. The same effectiveness-NTU relation as MATLAB/Simscape's Heat Exchanger
%   (TL-TL) and Plate Heat Exchanger (TL-TL) blocks (docs/dhs-heat-exchanger.md). The heat balance is
%   that of DHS.LoopHeatExchanger and the ports, valve and pump those of DHS.HeatExchanger. The
%   building needs an internal loop connected to hx.internalOutlet and hx.internalInlet.
%
%   Create with  building.addHeatExchanger('HX', 'UA',3.5e4, 'Qcap',8e5)  or
%                hx = DHS.ENTUPlateHeatExchanger('HX', 'UA',3.5e4, 'Qcap',8e5)
%
%   PROPERTIES (SI, in addition to DHS.LoopHeatExchanger)
%     UA   [W/K]   heat-exchanger conductance                         (4.0e4)

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
