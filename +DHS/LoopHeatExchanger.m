classdef (Abstract) LoopHeatExchanger < DHS.HeatExchanger
% DHS.LOOPHEATEXCHANGER  Abstract heat exchanger whose internal side is the building's internal loop.
%
%   The delivered heat follows from the district water (flow and supply temperature) and from the water
%   coming back from the loop (its flow and temperature), with the effectiveness of the type
%   (DHS.ENTUPlateHeatExchanger, DHS.FixedEffectivenessHeatExchanger). With the capacity rates
%   Cp = mdot_p cp and Cs = mdot_s cp and Cmin = min(Cp, Cs), heating only (clamped to [0, Qcap]):
%       Q = clamp( eps Cmin (Tsup_primary - Tsec_in) , 0 , Qcap )
%       Tret_primary = Tsup_primary - Q/Cp ,     Tsec_out = Tsec_in + Q/Cs
%   The types only differ in eps (effectivenessCmin returns eps*Cmin).
%
%   Both internal ports must be connected: the first pipe of the loop to hx.internalOutlet and its last
%   pipe to hx.internalInlet (see DHS.HeatExchanger).
%
%   PROPERTIES (SI, in addition to DHS.HeatExchanger)
%     mdotSecNom   [kg/s]  internal flow assumed when transfer is called without one          (6)

    properties
        mdotSecNom (1,1) double = 6
    end

    methods (Abstract)
        EC = effectivenessCmin(obj, mdotPrimary, mdotSec)   % effectiveness times the smaller capacity rate [W/K]
    end

    methods
        function tf = usesInternalLoop(~), tf = true; end

        function [Qdel, TretP, TsecOut] = transfer(obj, mdotPrimary, TsupPrimary, TsecIn, mdotSec)
            % TRANSFER  Heat transfer for the resolved primary flow.
            %   [Qdel, TretP, TsecOut] = hx.transfer(mdotPrimary, TsupPrimary, TsecIn)
            %   [...] = hx.transfer(mdotPrimary, TsupPrimary, TsecIn, mdotSec)
            %   mdotSec is the internal flow [kg/s] (default mdotSecNom); in a building the loop's actual
            %   flow and the temperature of the water returning from it are passed. TsecOut is the
            %   internal water leaving the exchanger.
            if nargin < 5 || isempty(mdotSec), mdotSec = obj.mdotSecNom; end
            if mdotPrimary <= 1e-6 || mdotSec <= 1e-6 || TsupPrimary <= TsecIn
                Qdel = 0; TretP = TsupPrimary; TsecOut = TsecIn;
            else
                Cp   = mdotPrimary * obj.cp;
                Cs   = mdotSec * obj.cp;
                UAeff = obj.effectivenessCmin(mdotPrimary, mdotSec);
                Qdel  = min(max(UAeff * (TsupPrimary - TsecIn), 0), obj.Qcap);
                TretP = TsupPrimary - Qdel / Cp;
                TsecOut = TsecIn + Qdel / Cs;
            end
            obj.Qdel = Qdel;  obj.TretPrimary = TretP;
        end
    end
end
