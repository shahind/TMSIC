classdef Link < handle
% DHS.HYDRAULIC.LINK  Base of the in-line components Pipe, Valve and Pump.
%
%   A link carries water from nodeA to nodeB. Every component has connect, and add... creates a
%   component, connects it downstream and returns it:
%     pipe1  = tee.portC.addPipe(0.05, 12);          % diameter [m], length [m]
%     valve1 = pipe1.addValve('Kvs',4);               pipe2 = valve1.addPipe(0.05, 3);
%     pipe2.connect(rad1);                            rad1.connect(returnPipe1);
%   connectToPipe and connectOutput are aliases of connect. See docs/dhs-hydraulic.md.

    properties
        nodeA = []
        nodeB = []
        teeSide (1,:) char = ''
        decorative double = false
        downBuildings double = []
    end
    properties (Dependent, SetAccess = private)
        Input
        Output
    end

    methods
        function n = get.Input(obj),  n = obj.nodeA; end
        function n = get.Output(obj), n = obj.nodeB; end

        function dst = connect(obj, dst, varargin)
            % CONNECT  Join the downstream end of this link to a node, link, radiator or building.
            DHS.Hydraulic.connectEnds(obj, dst, varargin{:});
        end

        function p = connectOutput(obj, dst)
            % CONNECTOUTPUT  Older name for connect.
            DHS.Hydraulic.connectEnds(obj, dst);  p = obj;
        end

        function x = addPipe(obj, varargin),     x = DHS.Hydraulic.addOn(obj, 'pipe', varargin{:});     end
        function x = addValve(obj, varargin),    x = DHS.Hydraulic.addOn(obj, 'valve', varargin{:});    end
        function x = addPump(obj, varargin),     x = DHS.Hydraulic.addOn(obj, 'pump', varargin{:});     end
        function x = addTee(obj, varargin),      x = DHS.Hydraulic.addOn(obj, 'tee', varargin{:});      end
        function x = addRadiator(obj, varargin), x = DHS.Hydraulic.addOn(obj, 'radiator', varargin{:}); end
        function x = addJunction(obj, varargin), x = DHS.Hydraulic.addOn(obj, 'junction', varargin{:}); end
    end
end
