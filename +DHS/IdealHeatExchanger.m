classdef IdealHeatExchanger < DHS.HeatExchanger
% DHS.IDEALHEATEXCHANGER  Substation of a building without an internal loop: one radiator that the
%   district water flows through (EN 442 radiator law).
%
%   hx = DHS.IdealHeatExchanger('HX', 'Qnom',8e5, 'dTnom',50, 'exponent',1.3);
%   b.attachHeatExchanger(hx);
%   Q = Qnom*((Tmean - Tzone)/dTnom)^n with Tmean = Tsup_primary - Q/(2*Cp). Q is limited to Qcap
%   (unlimited by default). Qnom [W] (5e5), dTnom [K] (50), exponent [-] (1.3).
%   Using it with an internal loop is an error. See docs/dhs-heat-exchanger.md.

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
