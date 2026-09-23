classdef Junction < handle
% DHS.HYDRAULIC.JUNCTION  A hydraulic node (a tee / manifold point) in the pipe network.
%
%   A Junction carries a single gauge pressure. Pipes connect junctions to each
%   other and to the plant ports; buildings are fed from junctions.
%
%   Two equivalent ways to build the same network (see DHS.HydraulicNetwork):
%     declarative   hn.addPipe(nodeA, nodeB, 'L',40, 'D',0.11)
%     port-wiring   nodeA.connectToPipe(pipe); pipe.connectOutput(nodeB)
%
%   PROPERTIES
%     name        char        label, e.g. 'T1'
%     side        char        'supply' | 'return' (set by the network)
%   LIVE STATE (filled by HydraulicNetwork.solve each step)
%     p           [Pa]        gauge pressure at this node
%     mdotThrough [kg/s]      total flow passing this node toward the leaves

    properties
        name (1,:) char = ''
        side (1,:) char = 'supply'
    end
    properties
        p           (1,1) double = NaN
        mdotThrough (1,1) double = 0
    end
    % topology (managed by DHS.HydraulicNetwork)
    properties
        parentPipe   = []        % DHS.Hydraulic.Pipe toward the root (plant); [] at the root
        childPipes   = {}        % DHS.Hydraulic.Pipe cell toward the leaves
        fedBuildings = {}        % DHS.Building cell fed directly from this junction
        mirror       = []        % the matching junction on the other side
        network      = []        % the DHS.HydraulicNetwork this node belongs to
        xy           = [NaN NaN] % layout position for visualize()
    end

    methods
        function obj = Junction(name, side)
            if nargin >= 1, obj.name = name; end
            if nargin >= 2, obj.side = side; end
            % every supply-side node gets its own return-side counterpart
            % automatically, whether it is built through hn.addJunction or
            % directly (DHS.Hydraulic.Junction(...), or a subclass such as
            % DHS.Hydraulic.TJunction)
            if strcmp(obj.side, 'supply')
                obj.mirror = DHS.Hydraulic.Junction([obj.name '_ret'], 'return');
                obj.mirror.mirror = obj;
            end
        end

        function p = connectToPipe(obj, varargin)
            % CONNECTTOPIPE  Port-wiring: attach a pipe downstream of this node.
            %   junction.connectToPipe(pipe)              (plain junctions/ports)
            %   junction.connectToPipe('portName', pipe)   (multi-port components
            %                                               such as DHS.Hydraulic.TJunction)
            %   Finish the wire with  pipe.connectOutput(nextNode)  -- that call is
            %   what actually registers the pipe with the network, exactly the way
            %   hn.addPipe already does, so the two styles produce identical topology.
            if numel(varargin) == 1
                pipe = varargin{1};
            else
                pipe = varargin{2};
            end
            assert(isa(pipe,'DHS.Hydraulic.Pipe'), 'DHS:Junction:connectToPipe', ...
                'Expected a DHS.Hydraulic.Pipe.');
            pipe.nodeA = obj;
            p = pipe;
        end
    end
end
