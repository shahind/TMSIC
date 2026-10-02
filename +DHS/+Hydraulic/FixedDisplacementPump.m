classdef FixedDisplacementPump < DHS.Hydraulic.Pump
% DHS.HYDRAULIC.FIXEDDISPLACEMENTPUMP  Positive-displacement pump: flow is set
%                                      by speed, almost independent of head,
%                                      until a relief valve caps the pressure.
%
%   Unlike a centrifugal pump, a gear/piston/screw (positive-displacement) pump
%   delivers a flow set by its speed and displacement, essentially regardless of
%   the downstream resistance, until the required head would exceed the unit's
%   working-pressure limit -- at that point an internal relief valve opens and
%   caps the head, and the flow drops below the commanded value:
%
%       mdot = min( frac*mdotRated , sqrt(max(0,(dpMax+dpAvailable))/Kbranch) )
%
%   A simpler model of the same pump type than MATLAB/Simscape's Fixed-Displacement
%   Pump (TL) block, which also models shaft torque/speed, volumetric leakage and
%   friction torque (docs/dhs-hydraulic.md).
%
%   SCOPE  This flow-vs-resistance physics is fully modelled at the branch level
%   (solveBranch, used for a building's substation pump). At the *central*
%   plant-pump position, DHS.HydraulicNetwork only asks a pump for the head it
%   contributes at the network root (curveHead); a fixed-displacement pump there
%   reports its relief-valve ceiling dpMax as the available header head -- a
%   full positive-displacement central-plant solve (where the pump, not the
%   downstream resistance, would set the *whole network's* total flow) is future
%   work.
%
%   PROPERTIES (SI, in addition to DHS.Hydraulic.Pump)
%     mdotRated [kg/s]  flow delivered at full speed against a low-resistance load
%     dpMax     [Pa]    relief-valve / maximum working-pressure ceiling

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

        function [m, h] = solveBranch(obj, Kbranch, dpAvailable, frac)
            % SOLVEBRANCH  Forces the commanded flow unless the branch resistance
            %   would need more head than the relief valve allows.
            if nargin < 4 || isempty(frac), frac = obj.speed; end
            s = min(1, max(obj.minSpeed, frac));
            mCmd = s * obj.mdotRated;
            mCap = sqrt(max(0, (obj.dpMax + dpAvailable) / max(Kbranch, eps)));
            m = min(mCmd, mCap);
            h = max(0, Kbranch*m^2 - dpAvailable);
        end
    end
end
