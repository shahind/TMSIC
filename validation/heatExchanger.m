function [Qdel, TretPrimary, TretSecondary] = heatExchanger(mdotPrimary, TsupPrimary, ...
                                                            TsecIn, UA, CdotSec, Qcap, cp)
%HEATEXCHANGER  Effectiveness-NTU counterflow plate heat exchanger, one step.
%
%   [Qdel, TretPrimary, TretSecondary] = heatExchanger(mdotPrimary, TsupPrimary,
%       TsecIn, UA, CdotSec, Qcap, cp)
%
%   Transfers heat from a district PRIMARY hot-water stream to a building
%   SECONDARY stream. Heating-only: the delivered heat is clamped to [0, Qcap].
%
%   INPUTS (SI)
%     mdotPrimary  primary mass flow (from the hydraulic solve)      [kg/s]
%     TsupPrimary  primary supply-water temperature at the HX inlet  [degC]
%     TsecIn       secondary return-water temperature into the HX    [degC]
%                  (for an emitter loop: zone air temp + emitter approach)
%     UA           heat-exchanger conductance                        [W/K]
%     CdotSec      secondary-side heat-capacity rate mdot_sec*cp     [W/K]
%     Qcap         substation heat-delivery capacity limit           [W]
%     cp           water specific heat capacity (default 4186)       [J/kg/K]
%
%   OUTPUTS
%     Qdel          heat delivered to the secondary side  (0 .. Qcap)   [W]
%     TretPrimary   primary return-water temperature = TsupPrimary - Qdel/(mdot_p*cp) [degC]
%     TretSecondary secondary supply-water temperature = TsecIn + Qdel/CdotSec [degC]
%
%   METHOD -- effectiveness-NTU, counterflow (Incropera & DeWitt, "Fundamentals
%   of Heat and Mass Transfer", 6th ed., Sec. 11.4; also VDI Heat Atlas):
%     Cdot_p = mdot_p*cp ;  Cmin = min(Cdot_p, Cdot_s) ;  Cr = Cmin/Cmax
%     NTU    = UA / Cmin
%     eps    = (1 - exp(-NTU(1-Cr))) / (1 - Cr exp(-NTU(1-Cr)))     (Cr < 1)
%            = NTU / (1 + NTU)                                       (Cr -> 1)
%     Q      = eps * Cmin * (TsupPrimary - TsecIn),  clamped to [0, Qcap]
%
%   With no primary flow, or a primary supply no warmer than the secondary
%   return, no heat is transferred and the primary leaves at its inlet
%   temperature.

    if nargin < 7 || isempty(cp), cp = 4186; end

    if mdotPrimary <= 1e-6 || TsupPrimary <= TsecIn || CdotSec <= 0
        Qdel          = 0;
        TretPrimary   = TsupPrimary;
        TretSecondary = TsecIn;
        return
    end

    Cp   = mdotPrimary * cp;
    Cs   = CdotSec;
    Cmin = min(Cp, Cs);
    Cmax = max(Cp, Cs);
    Cr   = Cmin / Cmax;
    NTU  = UA / Cmin;

    if abs(1 - Cr) < 1e-6
        eps = NTU / (1 + NTU);
    else
        ex  = exp(-NTU * (1 - Cr));
        eps = (1 - ex) / (1 - Cr * ex);
    end

    Qdel          = min(max(eps * Cmin * (TsupPrimary - TsecIn), 0), Qcap);
    TretPrimary   = TsupPrimary - Qdel / Cp;
    TretSecondary = TsecIn + Qdel / Cs;
end
