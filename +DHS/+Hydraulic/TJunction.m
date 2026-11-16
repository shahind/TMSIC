classdef TJunction < DHS.Hydraulic.Junction
% DHS.HYDRAULIC.TJUNCTION  A tee: a straight run (portB) and a side branch (portC) with their minor losses.
%
%   tee = DHS.Hydraulic.TJunction('T1', 'mainDiameter',0.10, 'sideDiameter',0.05);
%   pipe.connect(tee);    tee.portB.connect(nextPipe);    tee.portC.connect(building);
%   Or: tee = pipe1.addTee(0.05);   tee = pipe1.addTjunction('T1', 0.05);   tee = hn.addJunction('T1','type','tee',...)
%
%   Equivalent-length losses, added to the pipe that leaves the port (supply side only):
%   K_run = f*20/(2*rho*A_main^2), K_branch = f*60/(2*rho*A_side^2).
%   mainDiameter, sideDiameter [m]; roughness [m] (4.6e-5); frictionModel 'fixed' (default, Re = 1e7) or
%   'actual' (the leg's own Reynolds number). See docs/dhs-hydraulic.md.

    properties
        mainDiameter (1,1) double = 0.10
        sideDiameter (1,1) double = 0.05
        roughness    (1,1) double = 4.6e-5
        frictionModel (1,:) char {mustBeMember(frictionModel,{'fixed','actual'})} = 'fixed'
    end
    properties (SetAccess = private)
        portA     % inlet
        portB     % straight run
        portC     % side branch
    end
    properties (Access = private)
        pipeCount (1,1) double = 0    % counts declarative hn.addPipe calls off this tee
    end

    methods
        function obj = TJunction(name, varargin)
            obj@DHS.Hydraulic.Junction(name, 'supply');
            for i = 1:2:numel(varargin), obj.(varargin{i}) = varargin{i+1}; end
            obj.portA = DHS.Hydraulic.Port(obj, 'portA');
            obj.portB = DHS.Hydraulic.Port(obj, 'portB');
            obj.portC = DHS.Hydraulic.Port(obj, 'portC');
        end

        function markStart(obj, port, thing)
            % MARKSTART  A link leaves portB (the run) or portC (the branch); a radiator or building
            %   leaves portC unless told otherwise. Sets the fitting's loss on whatever leaves.
            isLink = isa(thing, 'DHS.Hydraulic.Link');
            if isempty(port) || strcmp(port, 'portA')
                if isLink, port = 'portB'; else, port = 'portC'; end
            end
            switch lower(string(port))
                case "portb", side = 'run';
                case "portc", side = 'branch';
                otherwise
                    error('DHS:TJunction:port', ...
                        'Unknown port "%s" (use ''portB'' for the run or ''portC'' for the branch).', port);
            end
            thing.teeSide = side;
            obj.pipeCount = obj.pipeCount + 1;
        end

        function K = teeLossK(obj, side, rho, mu, mdot)
            % TEELOSSK  Equivalent-length minor loss for RUN or BRANCH.
            %   frictionModel = 'fixed' (default): the friction factor is
            %   evaluated at a fixed, fully turbulent asymptote for that leg's
            %   diameter, matching the standard convention and MATLAB/Simscape's
            %   own default T-Junction (TL) model (docs/dhs-hydraulic.md).
            %   frictionModel = 'actual': the friction factor instead follows
            %   the leg's actual flow (mdot), the same laminar/turbulent rule
            %   DHS.Hydraulic.Pipe.resistance uses, for users who want the
            %   fitting's own friction factor to vary with Reynolds number too.
            switch lower(string(side))
                case "run",    D = obj.mainDiameter;  nD = 20;
                case "branch", D = obj.sideDiameter;   nD = 60;
                otherwise, error('DHS:TJunction:teeLossK', 'side must be ''run'' or ''branch''.');
            end
            Leq = nD * D;
            A   = pi*D^2/4;
            if strcmp(obj.frictionModel, 'actual')
                if nargin < 5, mdot = 0; end
                v  = abs(mdot) / (rho * A);
                Re = rho * max(v, 1e-6) * D / mu;
            else
                Re = 1e7;
            end
            f = DHS.Hydraulic.Pipe.swameeJain(Re, obj.roughness/D);
            K = f * Leq / (D * 2*rho * A^2);
        end

        function markPipeAttached(obj)
            % MARKPIPEATTACHED  Used by HydraulicNetwork.addPipe to auto-assign
            %   the first declaratively-added pipe off this tee as the run and
            %   the second as the branch.
            obj.pipeCount = obj.pipeCount + 1;
        end

        function n = attachedCount(obj)
            n = obj.pipeCount;
        end
    end
end
