classdef Junction < handle
% DHS.HYDRAULIC.JUNCTION  A node of the pipe network with one gauge pressure.
%
%   j = DHS.Hydraulic.Junction('R1', 'return');     % side is 'supply' or 'return'
%   j.connect(pipe), j.addPipe(D, L) and the other add... calls work as on every component (see Link).
%   Live: p [Pa], T [degC], mdotThrough [kg/s]. See docs/dhs-hydraulic.md.

    properties
        name (1,:) char = ''
        side (1,:) char = 'supply'
    end
    properties
        p           (1,1) double = NaN
        T           (1,1) double = NaN
        mdotThrough (1,1) double = 0
    end
    % topology (managed by DHS.HydraulicNetwork)
    properties
        parentPipe   = []        % the pipe leaving this node toward the plant; [] at the plant
        childPipes   = {}        % the pipes arriving at this node from the leaves' side
        fedBuildings = {}        % DHS.Building cell attached at this junction (fed from it, or draining into it)
        outLinks     = {}        % links that start here (recorded by connect)
        inLinks      = {}        % links that end here
        terminals    = {}        % buildings, radiators and bypass links fed from this node
        network      = []        % the DHS.HydraulicNetwork this node belongs to
        xy           = [NaN NaN] % layout position for visualize()
    end

    methods
        function obj = Junction(name, side)
            if nargin >= 1, obj.name = name; end
            if nargin >= 2, obj.side = side; end
        end

        function dst = connect(obj, varargin)
            % CONNECT  Join the next component to this node: junction.connect(pipe), or a radiator or building.
            %   On a tee, name the port:  tee.connect('portC', pipe)  (tee.portC.connect(pipe) is the same).
            if numel(varargin) == 1
                dst = varargin{1};  src = obj;
            else
                dst = varargin{2};  src = obj.(varargin{1});
            end
            DHS.Hydraulic.connectEnds(src, dst);
        end

        function p = connectToPipe(obj, varargin)
            % CONNECTTOPIPE  Older name for connect.
            p = obj.connect(varargin{:});
        end

        function x = addPipe(obj, varargin),     x = DHS.Hydraulic.addOn(obj, 'pipe', varargin{:});     end
        function x = addValve(obj, varargin),    x = DHS.Hydraulic.addOn(obj, 'valve', varargin{:});    end
        function x = addPump(obj, varargin),     x = DHS.Hydraulic.addOn(obj, 'pump', varargin{:});     end
        function x = addTee(obj, varargin),      x = DHS.Hydraulic.addOn(obj, 'tee', varargin{:});      end
        function x = addRadiator(obj, varargin), x = DHS.Hydraulic.addOn(obj, 'radiator', varargin{:}); end

        function markStart(obj, port, ~)
            % MARKSTART  A link or terminal starts at this node (a tee overrides this to set the fitting's loss).
            if ~isempty(port)
                error('DHS:Junction:port', '"%s" is a plain junction and has no ports.', obj.name);
            end
        end
    end
end
