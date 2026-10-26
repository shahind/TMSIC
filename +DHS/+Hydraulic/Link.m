classdef Link < handle
% DHS.HYDRAULIC.LINK  Base of the in-line network components: Pipe, Valve and Pump.
%
%   A link has two ends, nodeA (upstream) and nodeB (downstream), and the water flows from A to B.
%   Components are wired with connect, the same call on every component:
%
%       tee.portC.connect(pipe1);        % tee -> pipe
%       pipe1.connect(valve1);           % pipe -> valve (a node is made between them)
%       valve1.connect(pipe2);
%       pipe2.connect(rad1);             % pipe -> radiator
%       rad1.connect(returnPipe1);       % radiator -> return pipe
%       returnPipe1.connect(retJ);       % return pipe -> return junction
%       rad1.connect(zone1, R);          % radiator -> zone (heat), R in K/W
%
%   or created and connected in one call with add, which returns the new component:
%
%       pipe1  = tee.portC.addPipe(0.05, 12);      % diameter D, length L
%       valve1 = pipe1.addValve('Kvs',4);
%       pipe2  = valve1.addPipe(0.05, 3);
%       tee2   = pipe2.addTee(0.032);              % side diameter; the main diameter is pipe2.D
%       pump   = pipe2.addPump('dp0',3e4, 'mdotRated',1);
%
%   connect and add work the same on a junction, a tee port, a pipe, a valve, a pump, a radiator
%   and a building. connectToPipe and connectOutput are aliases of connect.
%
%   PROPERTIES
%     nodeA nodeB   the nodes at the two ends ([] until connected)
%     Input Output  the same, read only
%     teeSide       '' | 'run' | 'branch', set when the link leaves a tee port (adds the fitting's loss)
%     decorative    true for a same-node stub that is drawn but not solved
%     downBuildings terminals (buildings, radiators) in the subtree behind this link

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
