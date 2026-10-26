classdef IdealHeatExchanger < DHS.HeatExchanger
% DHS.IDEALHEATEXCHANGER  Simplified substation for a building WITHOUT an internal loop: the exchanger is
%                         a simple radiator that the district water flows through.
%
%   The building side is not modelled. The exchanger is represented by the radiator characteristic of
%   EN 442 (as in the Modelica Buildings library's radiator): the heat given to the room is proportional
%   to the mean water-to-room temperature difference raised to a power n,
%
%       Q = Qnom ( (Tmean - Tzone) / dTnom )^n ,        Tmean = Tsup_primary - Q/(2 Cp)     (arithmetic mean
%                                                                                           of supply and return)
%       Tret_primary = Tsup_primary - Q/Cp ,            Cp = mdot_p cp
%
%   so the heat depends on the district supply temperature, the primary flow (set by the valve) and the
%   room temperature, and on nothing else: there is no conductance, no effectiveness and no internal
%   water. Q solves the equation above (bisection; the left side grows and the right side falls with Q,
%   so it is unique), is limited to Qcap and is zero when the supply is no warmer than the room.
%   References: docs/dhs-heat-exchanger.md.
%
%   Use it for a building without an internal loop; a building with a loop uses an
%   ENTUPlateHeatExchanger or a FixedEffectivenessHeatExchanger (running a building with an ideal
%   exchanger and a loop is an error).
%
%   Create with  hx = DHS.IdealHeatExchanger('HX', 'Qnom',8e5, 'dTnom',50, 'exponent',1.3)
%                building.attachHeatExchanger(hx)
%
%   PROPERTIES (SI, in addition to DHS.HeatExchanger)
%     Qnom      [W]   heat at the nominal temperature difference                         (5e5)
%     dTnom     [K]   nominal mean water-to-room temperature difference (EN 442: 75/65/20) (50)
%     exponent  [-]   radiator exponent n (about 1.3; 1.1-1.4)                            (1.3)
%     Qcap      [W]   delivery limit (HeatExchanger), here unlimited by default            (Inf)

    properties
        Qnom     (1,1) double = 5.0e5
        dTnom    (1,1) double = 50
        exponent (1,1) double = 1.3
    end

    methods
        function obj = IdealHeatExchanger(name, varargin)
            if nargin < 1, name = 'HX'; end
            obj@DHS.HeatExchanger(name, varargin{:});
            if ~any(strcmp(varargin(1:2:end), 'Qcap')), obj.Qcap = Inf; end
        end

        function tf = usesInternalLoop(~), tf = false; end

        function [Qdel, TretP] = idealTransfer(obj, mdotPrimary, TsupPrimary, Tzone)
            % IDEALTRANSFER  Heat delivered to the room and the primary return temperature.
            %   [Qdel, TretP] = hx.idealTransfer(mdotPrimary, TsupPrimary, Tzone)
            Cp = mdotPrimary * obj.cp;
            if mdotPrimary <= 1e-6 || TsupPrimary <= Tzone
                Q = 0;
            else
                f  = @(Q) obj.Qnom * (max(TsupPrimary - Q/(2*Cp) - Tzone, 0)/obj.dTnom)^obj.exponent - Q;   % decreases with Q
                hi = min(obj.Qcap, Cp*(TsupPrimary - Tzone));       % the return cannot drop below the room
                lo = 0;
                if f(hi) >= 0
                    Q = hi;
                else
                    for k = 1:60                                    % bisection
                        mid = 0.5*(lo + hi);
                        if f(mid) > 0, lo = mid; else, hi = mid; end
                    end
                    Q = 0.5*(lo + hi);
                end
            end
            Qdel = Q;  TretP = TsupPrimary - Q/max(Cp, eps);
            if mdotPrimary <= 1e-6, TretP = TsupPrimary; end
            obj.Qdel = Qdel;  obj.TretPrimary = TretP;
        end
    end
end
