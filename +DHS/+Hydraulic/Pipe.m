classdef Pipe < handle
% DHS.HYDRAULIC.PIPE  A run of buried pre-insulated pipe between two hydraulic nodes.
%
%   Hydraulics : Darcy-Weisbach with the Swamee-Jain explicit friction
%                factor.  dp = K(mdot) * mdot^2 ,  K = f*L / (D * 2*rho * A^2).
%   Heat loss  : steady  Q_loss = UperM * L * (T_water - T_ground)  [W], applied
%                by the network as a transport temperature drop.
%
%   Two equivalent ways to wire a pipe into a network (see DHS.HydraulicNetwork):
%     declarative   hn.addPipe(nodeA, nodeB, 'L',40, 'D',0.11)
%     port-wiring   pipe = DHS.Hydraulic.Pipe('name', 'L',40, 'D',0.11);
%                   nodeA.connectToPipe(pipe);
%                   pipe.connectOutput(nodeB);      % registers it with the network
%
%   PROPERTIES (SI)
%     name    char
%     L       [m]     length
%     D       [m]     inner diameter
%     eps     [m]     wall roughness            (4.6e-5, commercial steel)
%     UperM   [W/m/K] buried-pipe heat-loss coefficient   (0.30)
%     teeSide char    '' | 'run' | 'branch' -- set automatically when this pipe
%                     leaves a DHS.Hydraulic.TJunction; adds that fitting's own
%                     minor loss to resistance() (see TJunction).
%   LIVE STATE (filled by HydraulicNetwork.solve / the co-sim each step)
%     mdot    [kg/s]  flow (toward nodeB positive)
%     vel     [m/s]   bulk velocity
%     dp      [Pa]    friction pressure drop
%     f       [-]     Darcy friction factor
%     Tdrop   [K]     transport temperature drop over the pipe
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
        teeSide (1,:) char = ''
    end
    properties
        nodeA = []           % DHS.Hydraulic.Junction or plant/pump/HX port
        nodeB = []           % DHS.Hydraulic.Junction or plant/pump/HX port
        mdot  (1,1) double = 0
        vel   (1,1) double = 0
        dp    (1,1) double = 0
        f     (1,1) double = 0.02
        Tdrop (1,1) double = 0
        decorative double = false
        downBuildings double = []   % indices of the buildings in this pipe's subtree
    end

    methods
        function obj = Pipe(name, varargin)
            % PIPE  Pipe(name, 'L',40, 'D',0.11, ...)  for port-wiring (nodeA/
            %   nodeB are filled in later by connectToPipe/connectOutput), or
            %   the legacy Pipe(name, nodeA, nodeB, 'L',.., 'D',..) form used
            %   internally by HydraulicNetwork.addPipe -- a leading argument
            %   that is not a property-name string is taken as nodeA (then
            %   nodeB), so both call styles are unambiguous.
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

        function p = connectOutput(obj, port)
            % CONNECTOUTPUT  Port-wiring: finish this pipe by attaching its
            %   downstream end to PORT, and register it with the hydraulic
            %   network that its upstream end already belongs to -- the same
            %   registration hn.addPipe performs, so the return-side mirror pipe
            %   is created automatically and the network solve is unaffected by
            %   which style built the topology.
            obj.nodeB = port;
            net = [];
            if ~isempty(obj.nodeA) && isprop(obj.nodeA, 'network'), net = obj.nodeA.network; end
            assert(~isempty(net), 'DHS:Pipe:connectOutput', ...
                ['Pipe "%s" has no upstream hydraulic network yet -- connect its ', ...
                 'input to a wired port first (nodeA.connectToPipe(pipe)).'], obj.name);
            net.registerPipe(obj);
            p = obj;
        end

        function tee = addTjunction(obj, name, sideDiameter)
            % ADDTJUNCTION  Insert a T-junction at this pipe's downstream end.
            %   tee = pipe1.addTjunction('T1', 0.05)
            %   The tee's main diameter is this pipe's own D; finish the branch
            %   and run legs with tee.connectToPipe('portB',pipeRun) /
            %   ('portC',pipeBranch), each followed by .connectOutput(...).
            tee = DHS.Hydraulic.TJunction(name, 'mainDiameter', obj.D, 'sideDiameter', sideDiameter);
            obj.connectOutput(tee);
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
