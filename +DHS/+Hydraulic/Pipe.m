classdef Pipe < DHS.Hydraulic.Link
% DHS.HYDRAULIC.PIPE  A pipe between two nodes: Darcy-Weisbach friction (Swamee-Jain) and heat loss
%   to the ground.
%
%   pipe = DHS.Hydraulic.Pipe('pipe1', 'L',40, 'D',0.11);    % or node.addPipe(0.11, 40)
%   dp = K*mdot^2 with K = f*L/(D*2*rho*A^2). Water entering at Tin leaves at
%   Tg + (Tin - Tg)*exp(-UperM*L/(mdot*cp)).
%   L [m], D [m], eps [m] roughness (4.6e-5), UperM [W/m/K] (0.30). Input and Output are the end nodes.
%   Live: mdot, vel, dp, f, Tin, Tout, Tdrop, Qloss. See docs/dhs-hydraulic.md.

    properties
        name    (1,:) char = ''
        L       (1,1) double = 50
        D       (1,1) double = 0.10
        eps     (1,1) double = 4.6e-5
        UperM   (1,1) double = 0.30
    end
    properties
        mdot  (1,1) double = 0
        vel   (1,1) double = 0
        dp    (1,1) double = 0
        f     (1,1) double = 0.02
        Tin   (1,1) double = NaN
        Tout  (1,1) double = NaN
        Tdrop (1,1) double = 0
        Qloss (1,1) double = 0
    end

    methods
        function obj = Pipe(name, varargin)
            % PIPE  Pipe(name, 'L',40, 'D',0.11, ...)  creates a pipe whose ends are
            %   joined later with connect. Pipe(name, nodeA, nodeB, 'L',.., 'D',..)
            %   gives the end nodes directly; a leading argument that is not a
            %   property-name string is taken as nodeA (then nodeB).
            if nargin >= 1, obj.name = name; end
            rest = varargin;
            if ~isempty(rest) && ~(ischar(rest{1}) || isstring(rest{1}))
                obj.nodeA = rest{1};  rest(1) = [];
                if ~isempty(rest) && ~(ischar(rest{1}) || isstring(rest{1}))
                    obj.nodeB = rest{1};  rest(1) = [];
                end
            end
            for i = 1:2:numel(rest), obj.(rest{i}) = rest{i+1}; end
        end

        function tee = addTjunction(obj, name, sideDiameter)
            % ADDTJUNCTION  Insert a T-junction at this pipe's downstream end.
            %   tee = pipe1.addTjunction('T1', 0.05)
            %   The tee's main diameter is this pipe's own D; finish the branch
            %   and run legs with tee.portB.connect(pipeRun) / tee.portC.connect(pipeBranch).
            tee = DHS.Hydraulic.TJunction(name, 'mainDiameter', obj.D, 'sideDiameter', sideDiameter);
            obj.connect(tee);
        end

        function K = resistance(obj, mdot, rho, mu)
            % RESISTANCE  Pa/(kg/s)^2 for the current flow (lagged friction factor).
            %   Adds the T-junction run/branch minor loss on top of the pipe's own
            %   Darcy-Weisbach term when this pipe leaves a DHS.Hydraulic.TJunction.
            A  = pi*obj.D^2/4;
            v  = abs(mdot) / (rho * A);
            Re = rho * max(v,1e-6) * obj.D / mu;
            obj.f = DHS.Hydraulic.Pipe.swameeJain(Re, obj.eps/obj.D);
            K  = obj.f * obj.L / (obj.D * 2*rho * A^2);
            if ~isempty(obj.teeSide) && isa(obj.nodeA, 'DHS.Hydraulic.TJunction')
                K = K + obj.nodeA.teeLossK(obj.teeSide, rho, mu, mdot);
            end
        end
    end

    methods
        function [K, H] = linkLoss(obj, mdot, rho, mu)
            % LINKLOSS  Pressure loss K*mdot^2 and head gain H of this link (a pipe has no head gain);
            %   the network walks supply pressure as  p(B) = p(A) - (K mdot^2 - H).
            K = obj.resistance(mdot, rho, mu);  H = 0;
        end

        function setFlow(obj, Q, dp, rho)
            % SETFLOW  Store the solved flow, pressure change and velocity.
            obj.mdot = Q;  obj.dp = dp;  obj.vel = Q/(rho*pi*obj.D^2/4);
        end

        function [Tout, Qloss] = outletTemperature(obj, Tin, Tground, mdot, cp)
            % OUTLETTEMPERATURE  Water temperature leaving the pipe and the heat lost.
            %   [Tout, Qloss] = pipe.outletTemperature(Tin, Tground, mdot, cp)
            %   Also stores Tin, Tout, Tdrop and Qloss in the pipe.
            mc   = max(mdot, 1e-6) * cp;                    % capacity rate [W/K]
            Tout = Tground + (Tin - Tground) * exp(-obj.UperM * obj.L / mc);
            Qloss = mc * (Tin - Tout);
            obj.Tin = Tin;  obj.Tout = Tout;  obj.Tdrop = Tin - Tout;  obj.Qloss = Qloss;
        end
    end

    methods (Static)
        function f = swameeJain(Re, relRough)
            if Re < 2300
                f = 64 / max(Re,1);
            else
                f = 0.25 / (log10(relRough/3.7 + 5.74/Re^0.9))^2;
            end
            f = min(max(f, 0.008), 0.1);
        end
    end
end
