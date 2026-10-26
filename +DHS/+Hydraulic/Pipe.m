classdef Pipe < DHS.Hydraulic.Link
% DHS.HYDRAULIC.PIPE  A run of buried pre-insulated pipe between two hydraulic nodes.
%
%   Hydraulics : Darcy-Weisbach with the Swamee-Jain explicit friction
%                factor.  dp = K(mdot) * mdot^2 ,  K = f*L / (D * 2*rho * A^2).
%   Heat loss  : steady heat loss to the ground along the pipe. Water entering at
%                T_in leaves at  T_out = T_g + (T_in - T_g) * exp(-UperM*L / (mdot*cp))
%                and the pipe loses  Q_loss = mdot*cp*(T_in - T_out)  [W]. The network
%                applies it pipe by pipe, so every pipe loses heat once, with the
%                flow it actually carries.
%
%   Ways to wire a pipe into a network (see DHS.HydraulicNetwork and DHS.Hydraulic.Link):
%     declarative   hn.addPipe(nodeA, nodeB, 'L',40, 'D',0.11)
%     connecting    pipe = DHS.Hydraulic.Pipe('name', 'L',40, 'D',0.11);
%                   nodeA.connect(pipe);
%                   pipe.connect(nodeB);            % registers it with the network
%     one call      pipe = nodeA.addPipe(0.11, 40); % diameter, length
%
%   PROPERTIES (SI)
%     name    char
%     L       [m]     length
%     D       [m]     inner diameter
%     eps     [m]     wall roughness            (4.6e-5, commercial steel)
%     UperM   [W/m/K] buried-pipe heat-loss coefficient   (0.30)
%     Input   the node the pipe starts at (read only; Input.p, Input.T)
%     Output  the node the pipe ends at   (read only; Output.p, Output.T)
%     (nodeA, nodeB, teeSide, decorative and downBuildings are those of DHS.Hydraulic.Link)
%     teeSide char    '' | 'run' | 'branch' -- set automatically when this pipe
%                     leaves a DHS.Hydraulic.TJunction; adds that fitting's own
%                     minor loss to resistance() (see TJunction).
%   LIVE STATE (filled by HydraulicNetwork.solve / the co-sim each step)
%     mdot    [kg/s]  flow (toward nodeB positive)
%     vel     [m/s]   bulk velocity
%     dp      [Pa]    friction pressure drop
%     f       [-]     Darcy friction factor
%     Tin     [degC]  water temperature entering the pipe
%     Tout    [degC]  water temperature leaving the pipe
%     Tdrop   [K]     temperature drop over the pipe, Tin - Tout
%     Qloss   [W]     heat lost to the ground
%     decorative logical  true for a same-node round trip (e.g. a boiler-to-pump
%                     stub inside the lumped plant) -- wired for a clear diagram,
%                     but outside the solved topology since both ends alias one
%                     pressure node.

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
