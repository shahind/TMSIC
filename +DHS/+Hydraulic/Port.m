classdef Port < handle
% DHS.HYDRAULIC.PORT  A connection of a tee: portA (inlet), portB (run) or portC (side branch).
%
%   tee.portB.connect(pipe3);     tee.portC.D = 0.06;     tee.portC.p     tee.portC.pipe.L
%   D [m] is the diameter at the port (read and write), p [Pa] and T [degC] are live (read only), and
%   pipe is the pipe attached to the port ([] if none). See docs/dhs-hydraulic.md.

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

        function dst = connect(obj, dst, varargin)
            % CONNECT  Join the next component to this port: tee.portC.connect(pipe), or a radiator or building.
            %   portB is the run and portC the side branch; portA is the inlet, so finish the incoming
            %   component with  component.connect(tee).
            if strcmp(obj.name, 'portA')
                error('DHS:Port:inlet', 'portA is the inlet: finish the incoming component with component.connect(tee).');
            end
            DHS.Hydraulic.connectEnds(obj, dst, varargin{:});
        end

        function pipe = connectToPipe(obj, pipe)
            % CONNECTTOPIPE  Older name for connect.
            obj.connect(pipe);
        end

        function x = addPipe(obj, varargin),     x = DHS.Hydraulic.addOn(obj, 'pipe', varargin{:});     end
        function x = addValve(obj, varargin),    x = DHS.Hydraulic.addOn(obj, 'valve', varargin{:});    end
        function x = addPump(obj, varargin),     x = DHS.Hydraulic.addOn(obj, 'pump', varargin{:});     end
        function x = addTee(obj, varargin),      x = DHS.Hydraulic.addOn(obj, 'tee', varargin{:});      end
        function x = addRadiator(obj, varargin), x = DHS.Hydraulic.addOn(obj, 'radiator', varargin{:}); end

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
            if strcmp(side, 'branch') && ~isempty(obj.node.fedBuildings) ...
                    && isprop(obj.node.fedBuildings{1}, 'connPipeSup')
                v = obj.node.fedBuildings{1}.connPipeSup;            % a building's service pipe
            end
        end
    end
end
