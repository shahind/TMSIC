classdef TJunction < DHS.Hydraulic.Junction
% DHS.HYDRAULIC.TJUNCTION  A real T-fitting: a main run plus a side branch, each
%                          with its own minor-loss coefficient from the branch's
%                          own diameter.
%
%   BUILD IT
%     tee = DHS.Hydraulic.TJunction('T1', 'mainDiameter',0.10, 'sideDiameter',0.05);
%     tee.connectToPipe('portB', pipeRun);      pipeRun.connectOutput(nextTee);
%     tee.connectToPipe('portC', pipeBranch);   pipeBranch.connectOutput(building.inlet);
%     pipeIn.connectOutput(tee);                % (or tee.portA, equivalently)
%
%   or insert one on an existing pipe's downstream end:
%     tee = pipe1.addTjunction('T1', 0.05);     % mainDiameter = pipe1.D
%
%   or, in the declarative style, on a plain hn.addJunction network:
%     tee = hn.addJunction('T1', 'type','tee', 'mainDiameter',0.10, 'sideDiameter',0.05);
%     hn.addPipe(tee, nextTee);                 % first pipe off a tee = the run
%     hn.addPipe(tee, building.inlet);          % second = the branch
%
%   LOSS MODEL  Equivalent-length method: a standard tee has an equivalent
%   length, in pipe diameters, of 20 used as a straight run and 60 used as a
%   branch (see docs/dhs-hydraulic.md for the reference):
%       K_run    = f(D_main) * (20*D_main) / (D_main * 2*rho*A_main^2)
%       K_branch = f(D_side) * (60*D_side) / (D_side * 2*rho*A_side^2)
%   This K is added on top of the ordinary pipe resistance of whichever pipe
%   leaves portB (run) or portC (branch) -- see DHS.Hydraulic.Pipe.resistance.
%   Applied on the supply side only (the return-side mirror pipe is a plain
%   junction, not a tee).
%
%   PROPERTIES (SI, in addition to DHS.Hydraulic.Junction)
%     mainDiameter  [m]    diameter of the straight-through run
%     sideDiameter  [m]    diameter of the side branch
%     roughness     [m]    wall roughness for the tee's own loss (4.6e-5, steel)
%     frictionModel char   'fixed' (default) | 'actual' -- see TEELOSSK

    properties
        mainDiameter (1,1) double = 0.10
        sideDiameter (1,1) double = 0.05
        roughness    (1,1) double = 4.6e-5
        frictionModel (1,:) char {mustBeMember(frictionModel,{'fixed','actual'})} = 'fixed'
    end
    properties (Access = private)
        pipeCount (1,1) double = 0    % counts declarative hn.addPipe calls off this tee
    end

    methods
        function obj = TJunction(name, varargin)
            obj@DHS.Hydraulic.Junction(name, 'supply');
            for i = 1:2:numel(varargin), obj.(varargin{i}) = varargin{i+1}; end
        end

        function j = portA(obj)
            % PORTA  The inbound port -- this tee IS the node pipes connect into.
            j = obj;
        end

        function p = connectToPipe(obj, varargin)
            % CONNECTTOPIPE  tee.connectToPipe('portB', pipe) for the straight
            %   run, tee.connectToPipe('portC', pipe) for the side branch, or
            %   tee.connectToPipe(pipe) -- portB (the run) is the default, since
            %   a tee usually sits on a trunk that keeps going.
            if numel(varargin) == 1
                portName = 'portB';  pipe = varargin{1};
            else
                portName = varargin{1};  pipe = varargin{2};
            end
            switch lower(string(portName))
                case "portb", pipe.teeSide = 'run';
                case "portc", pipe.teeSide = 'branch';
                otherwise
                    error('DHS:TJunction:port', ...
                        'Unknown port "%s" (use ''portB'' for the run or ''portC'' for the branch).', portName);
            end
            pipe.nodeA = obj;
            obj.pipeCount = obj.pipeCount + 1;
            p = pipe;
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
