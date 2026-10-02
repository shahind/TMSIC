classdef CentrifugalPump < DHS.Hydraulic.Pump
% DHS.HYDRAULIC.CENTRIFUGALPUMP  Variable-speed centrifugal pump: quadratic
%                                head-flow curve + the affinity laws.
%
%       head(mdot, s) = s^2 * dp0  -  dp0 * mdot^2 / mdotMax^2        [Pa]
%
%   The standard first model of a centrifugal circulator. Speed scaling follows
%   the pump affinity laws: head(s*Q, s) = s^2 * head(Q, 1). The special case of
%   MATLAB/Simscape's Centrifugal Pump (TL) general affinity-law model for a
%   quadratic reference head curve (docs/dhs-hydraulic.md).
%
%   PROPERTIES (SI, in addition to DHS.Hydraulic.Pump)
%     dp0       [Pa]    shut-off head (mdot = 0)
%     mdotMax   [kg/s]  run-out flow (head = 0 at speed 1)

    properties
        dp0     (1,1) double = 1.0e5
        mdotMax (1,1) double = 10
    end

    methods
        function obj = CentrifugalPump(name, varargin)
            obj@DHS.Hydraulic.Pump(name, varargin{:});
        end

        function h = curveHead(obj, mdot, frac)
            % CURVEHEAD  Head [Pa] at flow mdot and speed fraction frac (default obj.speed).
            if nargin < 3, frac = obj.speed; end
            frac = min(1, max(obj.minSpeed, frac));
            h = max(0, frac^2 * obj.dp0 - obj.dp0 * mdot.^2 / obj.mdotMax^2);
        end

        function [m, h] = solveBranch(obj, Kbranch, dpAvailable, frac)
            % SOLVEBRANCH  Closed-form intersection of this pump's curve with a
            %   branch of resistance Kbranch [Pa/(kg/s)^2], given the differential
            %   pressure dpAvailable already present at its tee:
            %     s^2 dp0 + dpAvailable = (Kbranch + dp0/mdotMax^2) * m^2
            if nargin < 4 || isempty(frac), frac = obj.speed; end
            s = min(1, max(obj.minSpeed, frac));
            Kden = Kbranch + obj.dp0 / obj.mdotMax^2;
            m = sqrt(max(0, (s^2*obj.dp0 + dpAvailable) / Kden));
            h = obj.curveHead(m, s);
        end
    end
end
