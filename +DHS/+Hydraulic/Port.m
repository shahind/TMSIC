classdef Port < handle
% DHS.HYDRAULIC.PORT  One of the three connections of a T-junction: portA (inlet), portB (run),
%                     portC (side branch).
%
%   A tee's ports are reached by name:
%
%       tee = hn.tee2;
%       tee.portB.connectToPipe(pipe3);     % wire the run
%       tee.portC.D = 0.06;                 % diameter of the side branch [m]
%       tee.portC.p                         % gauge pressure at the tee [Pa]
%       tee.portC.pipe.L                    % the pipe leaving that port
%
%   PROPERTIES
%     D     [m]     diameter of the fitting at this port: the main diameter for portA and
%                   portB, the side diameter for portC (read and write)
%     p     [Pa]    gauge pressure at the tee, live (read only)
%     T     [degC]  water temperature at the tee, live (read only)
%     pipe          the pipe attached at this port, [] if none (read only)

    properties (SetAccess = private)
        name = ''
        node
    end
    properties (Dependent)
        D
    end
    properties (Dependent, SetAccess = private)
        p
        T
        pipe
    end

    methods
        function obj = Port(node, name)
            obj.node = node;  obj.name = name;
        end

        function pipe = connectToPipe(obj, pipe)
            % CONNECTTOPIPE  Attach a pipe to this port: portB the run, portC the side branch.
            %   Finish the wire with  pipe.connectOutput(nextNode).
            if strcmp(obj.name, 'portA')
                error('DHS:Port:inlet', 'portA is the inlet: finish the incoming pipe with pipe.connectOutput(tee).');
            end
            obj.node.connectToPipe(obj.name, pipe);
        end

        function v = get.D(obj)
            if strcmp(obj.name, 'portC'), v = obj.node.sideDiameter; else, v = obj.node.mainDiameter; end
        end
        function set.D(obj, v)
            if strcmp(obj.name, 'portC'), obj.node.sideDiameter = v; else, obj.node.mainDiameter = v; end
        end

        function v = get.p(obj), v = obj.node.p; end
        function v = get.T(obj), v = obj.node.T; end

        function v = get.pipe(obj)
            v = [];
            switch obj.name
                case 'portA', v = obj.node.parentPipe;
                case 'portB', side = 'run';
                case 'portC', side = 'branch';
            end
            if strcmp(obj.name, 'portA'), return, end
            for k = 1:numel(obj.node.childPipes)
                if strcmp(obj.node.childPipes{k}.teeSide, side), v = obj.node.childPipes{k}; return, end
            end
            if strcmp(side, 'branch') && ~isempty(obj.node.fedBuildings)
                v = obj.node.fedBuildings{1}.connPipeSup;            % a building's service pipe
            end
        end
    end
end
