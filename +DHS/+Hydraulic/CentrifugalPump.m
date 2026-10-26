classdef CentrifugalPump < DHS.Hydraulic.Pump
% DHS.HYDRAULIC.CENTRIFUGALPUMP  Variable-speed centrifugal pump: a quadratic head-flow
%                                characteristic at full speed and the affinity laws.
%
%       head(mdot, s) = s^2 * dp0  -  K * mdot^2 ,      K = (dp0 - dpRated) / mdotRated^2      [Pa]
%
%   The characteristic is the parabola through two points of the pump's data sheet at its maximum
%   rotational speed: the shut-off head dp0 (no flow) and a duty point, the flow mdotRated and the head
%   dpRated the pump gives there. s is the speed as a fraction of the maximum rotational speed nMax
%   (s = rpm / nMax). Speed scaling follows the pump affinity laws: flow is proportional to s and head
%   to s^2, head(s*Q, s) = s^2 * head(Q, 1). The flow and the head the pump delivers are never set
%   directly: they are where the characteristic, at the current speed, meets the resistance of the
%   network (the special case of MATLAB/Simscape's Centrifugal Pump (TL) general affinity-law model for
%   a quadratic reference head curve, docs/dhs-hydraulic.md).
%
%   A pump with speed 0 is stopped: as a substation pump it adds no head and no
%   resistance (the branch flow is sqrt(dpAvailable/Kbranch)).
%
%   PROPERTIES (SI, in addition to DHS.Hydraulic.Pump)
%     dp0        [Pa]    shut-off head at maximum speed (no flow)                       (1e5)
%     mdotRated  [kg/s]  flow of the duty point at maximum speed                        (5)
%     dpRated    [Pa]    head at that flow at maximum speed; empty = 75 % of dp0        ([])
%     mdotFree   [kg/s]  read only: flow at zero head at maximum speed (end of the curve)
%     nMax       [rpm]   maximum rotational speed (Pump)
%     speed      [-]     fraction of nMax, or rpm [rpm] (Pump)

    properties
        dp0       (1,1) double = 1.0e5
        mdotRated (1,1) double = 5
        dpRated         double = []
    end
    properties (Dependent, SetAccess = private)
        mdotFree
    end

    methods
        function obj = CentrifugalPump(name, varargin)
            obj@DHS.Hydraulic.Pump(name, varargin{:});
        end

        function m = get.mdotFree(obj)
            m = obj.mdotRated * sqrt(obj.dp0 / max(obj.dp0 - obj.dutyHead(), eps));
        end

        function K = curveK(obj)
            % CURVEK  Coefficient of the characteristic, head = s^2 dp0 - K mdot^2 [Pa/(kg/s)^2].
            K = (obj.dp0 - obj.dutyHead()) / obj.mdotRated^2;
        end

        function h = curveHead(obj, mdot, frac)
            % CURVEHEAD  Head [Pa] at flow mdot and speed fraction frac (default obj.speed).
            if nargin < 3, frac = obj.speed; end
            frac = min(1, max(obj.minSpeed, frac));
            h = max(0, frac^2 * obj.dp0 - obj.curveK() * mdot.^2);
        end

        function [K, H] = inlineCurve(obj)
            % INLINECURVE  head = H - K mdot^2 with H = s^2 dp0 (s: speed, with minSpeed).
            s = min(1, max(obj.minSpeed, obj.speed));
            K = obj.curveK();  H = s^2 * obj.dp0;
        end

        function [m, h] = solveBranch(obj, Kbranch, dpAvailable, frac)
            % SOLVEBRANCH  Closed-form intersection of this pump's curve with a
            %   branch of resistance Kbranch [Pa/(kg/s)^2], given the differential
            %   pressure dpAvailable already present at its tee:
            %     s^2 dp0 + dpAvailable = (Kbranch + K) * m^2
            if nargin < 4 || isempty(frac), frac = obj.speed; end
            if frac <= 0                          % stopped: no head, no extra resistance
                m = sqrt(max(0, dpAvailable) / Kbranch);  h = 0;  return
            end
            s = min(1, max(obj.minSpeed, frac));
            Kden = Kbranch + obj.curveK();
            m = sqrt(max(0, (s^2*obj.dp0 + dpAvailable) / Kden));
            h = obj.curveHead(m, s);
        end
    end

    methods (Access = private)
        function d = dutyHead(obj)
            % head at the rated flow: dpRated, or 75 % of the shut-off head when it is not given
            d = obj.dpRated;
            if isempty(d), d = 0.75 * obj.dp0; end
            if d > obj.dp0 || d < 0
                error('DHS:CentrifugalPump:duty', ...
                    'Pump "%s": the head at the rated flow (%.4g Pa) must lie between 0 and the shut-off head dp0 (%.4g Pa).', ...
                    obj.name, d, obj.dp0);
            end
        end
    end
end
