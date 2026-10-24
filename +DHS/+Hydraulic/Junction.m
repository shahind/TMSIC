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
%     side        char        'supply' | 'return': which tree the node belongs to
%   LIVE STATE (filled by HydraulicNetwork.solve each step)
%     p           [Pa]        gauge pressure at this node
%     mdotThrough [kg/s]      total flow passing this node toward the leaves
%     T           [degC]      water temperature at this node (supply: arriving from
%                             the plant; return: the mix of the streams joining here)

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
        network      = []        % the DHS.HydraulicNetwork this node belongs to
        xy           = [NaN NaN] % layout position for visualize()
    end

    methods
        function obj = Junction(name, side)
            if nargin >= 1, obj.name = name; end
            if nargin >= 2, obj.side = side; end
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
