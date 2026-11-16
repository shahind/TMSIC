classdef FixedDisplacementPump < DHS.Hydraulic.Pump
% DHS.HYDRAULIC.FIXEDDISPLACEMENTPUMP  Positive-displacement pump: the flow is set by the speed until a
%   relief valve caps the pressure.
%
%   pump = DHS.Hydraulic.FixedDisplacementPump('P', 'mdotRated',3, 'dpMax',2.5e5);
%   mdot = min(speed*mdotRated, sqrt(max(0, dpMax + dpAvail)/K)).
%   mdotRated [kg/s] (5), dpMax [Pa] (4e5). As the central pump it reports dpMax as the header head; a
%   full positive-displacement solve of the whole network is not implemented. See docs/dhs-hydraulic.md.

    properties
        mdotRated (1,1) double = 5
        dpMax     (1,1) double = 4.0e5
    end

    methods
        function obj = FixedDisplacementPump(name, varargin)
            obj@DHS.Hydraulic.Pump(name, varargin{:});
        end

        function h = curveHead(obj, mdot, frac) %#ok<INUSL>
            % CURVEHEAD  Central-pump role: the relief-valve ceiling whenever the
            %   pump is running, 0 when stopped (see the class header SCOPE note).
            if nargin < 3 || isempty(frac), frac = obj.speed; end
            if min(1, max(0,frac)) <= 0, h = 0; else, h = obj.dpMax; end
        end

        function [K, H] = inlineCurve(obj) %#ok<MANU>
            error('DHS:FixedDisplacementPump:inline', ...
                'A fixed-displacement pump cannot be placed in-line in a network; use a centrifugal pump.');
        end

        function [m, h] = solveBranch(obj, Kbranch, dpAvailable, frac)
            % SOLVEBRANCH  Forces the commanded flow unless the branch resistance
            %   would need more head than the relief valve allows.
            if nargin < 4 || isempty(frac), frac = obj.speed; end
            if frac <= 0                          % stopped: no head, no extra resistance
                m = sqrt(max(0, dpAvailable) / max(Kbranch, eps));  h = 0;  return
            end
            s = min(1, max(obj.minSpeed, frac));
            mCmd = s * obj.mdotRated;
            mCap = sqrt(max(0, (obj.dpMax + dpAvailable) / max(Kbranch, eps)));
            m = min(mCmd, mCap);
            h = max(0, Kbranch*m^2 - dpAvailable);
        end
    end
end
