classdef HydraulicNetwork < dynamicprops
% DHS.HYDRAULICNETWORK  The district pipe network: a supply tree and a return tree, both
%                       rooted at the central heat plant, with buildings joining them.
%                       One central pump; each building's flow is set by its control
%                       valve (a booster pump per building is optional).
%
%   You define the supply side and the return side separately. They need not look alike:
%   the return branch may be longer or shorter, with other diameters, roughness or heat
%   loss than the supply branch. Each side is a tree of junctions and pipes:
%     supply  plant supply port -> junctions -> buildings        (pipes flow away from the plant)
%     return  buildings -> junctions -> plant return port        (pipes flow toward the plant)
%
%   Two equivalent ways to build the same network -- both end up compiled into
%   the same integer-indexed trees, so solve() cannot tell which one you used.
%
%   LINKS  The pipes of the two trees are links between nodes; valves and in-line pumps are links too
%   (DHS.Hydraulic.Link): a valve loses K*mdot^2 where it sits, a pump adds its head there. A network
%   needs at least one pump, the central pump plantPump or an in-line pump placed anywhere in a tree.
%   A link's flow is the sum of the branch flows behind it. A link joined to a return junction from
%   the supply side is a bypass branch (DHS.Hydraulic.CrossLink).
%
%   CONNECTING  Components are wired with connect (or created and wired with add*), the same call on a
%   junction, tee port, pipe, valve, pump, radiator and building; the network is found by walking the
%   connections from the plant, so the order of the calls does not matter (see DHS.Hydraulic.Link):
%     tee.portC.connect(building);   building.connect(returnJunction);
%
%   DECLARATIVE
%     hn = sys.addHydraulicNetwork();
%     t1 = hn.addJunction('T1');                                  % a supply junction
%     hn.addPipe(chp.supplyPort, t1, 'name','sup1', 'L',40, 'D',0.11);
%     r1 = hn.addJunction('R1', 'side','return');                 % a return junction
%     hn.addPipe(r1, chp.returnPort, 'name','ret1', 'L',45, 'D',0.13);   % flows from r1 to the plant
%     hn.connectBuilding(t1, bldgArts, r1);                       % supply junction, building, return junction
%   A tee on the supply side:  hn.addJunction('T2', 'type','tee', 'mainDiameter',0.11, 'sideDiameter',0.05)
%     the first pipe leaving a tee is its run, the next its branch; a building is always the branch.
%
%   CONNECTING  (see DHS.Hydraulic.Link)
%     pipe1 = DHS.Hydraulic.Pipe('sup1', 'L',40, 'D',0.11);
%     chp.supplyPort.connect(pipe1);                              % plant supply -> pipe1
%     tee1  = pipe1.addTee(0.05, 'name','T1');                    % pipe1 -> tee T1 (mainDiameter = pipe1.D)
%     pipe2 = DHS.Hydraulic.Pipe('sup2', 'L',50, 'D',0.11);
%     tee1.portB.connect(pipe2);  pipe2.connect(t2);              % the run of T1
%     r1    = DHS.Hydraulic.Junction('R1', 'return');
%     r1.addPipe(0.13, 45, 'name','ret1').connect(chp.returnPort);   % return pipe from R1 to the plant
%     tee1.portC.connect(bldgAdmin);  bldgAdmin.connect(r1);      % a building hangs on the side port of a tee
%   or in one call, with the new component returned:  tee1 = chp.supplyPort.addPipe(0.11, 40).addTee(0.05)
%
%   The same class serves a building's internal loop, which starts at the heat exchanger's internal
%   outlet (hx.internalOutlet) and ends at its internal inlet (hx.internalInlet); its branches are the
%   zone radiators. You do not handle the loop network: connecting to those two ports is enough.
%   Pipes, valves, pumps and tees work exactly as on the district side.
%
%   NAMED PARTS  Every junction and pipe is reachable by its name once it is in the network:
%     hn.sup1.L = 60;   hn.ret1.D = 0.15;   hn.tee2.portC.D = 0.06;   hn.R1.p
%   A name that is not a valid MATLAB identifier is not registered. The service connection of
%   a building is sized by its connLength/connD (building.connPipeSup and connPipeRet are
%   its two pipes and may be edited separately after hn.connectBuilding).
%
%   SOLVE  (each co-simulation step, given the central pump speed pumpFrac):
%     * segment flow  Q_seg  = sum of the branch flows in the subtree behind a pipe
%     * central pump head  dpC = plantPump.curveHead(Mtot, pumpFrac)
%     * pressure walk from the plant out along the supply tree, losing  K*Q_seg^2
%       on each pipe (plus a T-junction's own run/branch loss where one sits, see
%       DHS.Hydraulic.TJunction), and from the plant return port out along the return tree,
%       where the pressure rises by K*Q_seg^2 on each pipe
%     * each building branch (connection pipes + valve + HX body), given the
%       differential pressure between its supply and its return junction, closes through
%       its own pump's solveBranch (a stopped pump adds nothing: m = sqrt(dp/K)) -- the
%       one nonlinear equation a centrifugal and a fixed-displacement pump answer
%       differently, see DHS.Hydraulic.Pump
%     * damped fixed-point on Mtot (segment flows and dpC depend on it); the damping starts at
%       0.5 and is halved whenever the iteration stops improving, so a strongly coupled
%       network (a narrow return main, say) still converges
%
%   TEMPERATURES  (supplyTemperatures / returnTemperatures, called by DHS.System each step
%   with the flows from solve): the supply walk takes the plant supply temperature out
%   through every pipe, each losing heat to the ground with its own flow
%   (DHS.Hydraulic.Pipe.outletTemperature); the return walk takes each heat-exchanger
%   outlet temperature back through the return tree, loses heat in every return pipe and
%   mixes the streams at each junction by enthalpy flow. Junctions themselves lose no heat.
%
%   The buildings are COUPLED: opening one valve/pump raises Mtot, raises the
%   shared-trunk friction and pulls the central pump down its curve, so every
%   other tee loses differential pressure.
%
%   Units SI: kg/s, Pa (gauge), m.

    properties
        pReturnRef (1,1) double = 1.5e5
        rho        (1,1) double = 978
        mu         (1,1) double = 4.0e-4
        solver     (1,:) char {mustBeMember(solver, {'newton','anderson','fixedPoint'})} = 'newton'
        maxIter    (1,1) double = 40       % most iterations of one solve
        tol        (1,1) double = 1e-9     % flow change that ends the iteration [kg/s]
        damping    (1,1) double = 0.5      % first step of 'anderson' and 'fixedPoint': m = (1-w) m + w G(m)
        andersonDepth (1,1) double = 5     % iterates 'anderson' combines
    end
    properties (SetAccess = private)
        junctions       cell = {}      % supply junctions
        returnJunctions cell = {}      % return junctions
        pipes           cell = {}      % supply pipes
        returnPipes     cell = {}      % return pipes
        buildings       cell = {}
        compiled  (1,1) logical = false
        lastIter  (1,1) double = 0     % iterations of the last solve
        lastErr   (1,1) double = 0     % flow change of the last iteration [kg/s]
    end
    properties (SetAccess = private)
        bypassPipe     = []           % DHS.Hydraulic.Pipe from a supply junction to a return junction
        bypassValve    = []           % DHS.Hydraulic.Valve in series with it (sets the minimum flow)
        bypassJunction = []           % supply junction the bypass leaves
        bypassReturnJunction = []     % return junction the bypass joins
    end
    properties (Access = private)
        solverData_ = struct()        % integer-indexed copy of the topology, filled by compile()
        jac_ = []                     % Jacobian of the flow residual from the last solve, the start of the next
    end
    properties
        plantSupply DHS.Hydraulic.Junction
        plantReturn DHS.Hydraulic.Junction
        plantPump                               % a DHS.Hydraulic.Pump: the central pump (owned by the plant)
        nameOwner = []                          % a building whose internal loop this is: parts are also reachable by name on it
    end

    methods
        % ---- assembly API (declarative) -----------------------------------
        function j = addJunction(obj, name, varargin)
            % ADDJUNCTION  hn.addJunction('T1')  for a plain supply junction,
            %   hn.addJunction('R1', 'side','return')  for a return junction, or
            %   hn.addJunction('T1','type','tee','mainDiameter',Dm,'sideDiameter',Ds)
            %   for a supply tee with its own minor-loss physics (see DHS.Hydraulic.TJunction).
            %   Any property of the part can be given as a name-value pair
            %   ('roughness', 'frictionModel', ...) and changed later, e.g. hn.T1.sideDiameter = 0.06.
            type = 'plain';  side = 'supply';
            k = find(strcmpi(varargin(1:2:end), 'type'), 1);
            if ~isempty(k), type = varargin{2*k}; varargin(2*k-1:2*k) = []; end
            k = find(strcmpi(varargin(1:2:end), 'side'), 1);
            if ~isempty(k), side = varargin{2*k}; varargin(2*k-1:2*k) = []; end
            if strcmpi(type, 'tee')
                assert(strcmpi(side, 'supply'), 'DHS:HydraulicNetwork:returnTee', ...
                    'A tee is available on the supply side only.');
                js = DHS.Hydraulic.TJunction(name, varargin{:});
            else
                js = DHS.Hydraulic.Junction(name, lower(side));
                for i = 1:2:numel(varargin), js.(varargin{i}) = varargin{i+1}; end
            end
            js.network = obj;
            obj.addToList(js);
            j = js;
            obj.compiled = false;
        end

        function p = addPipe(obj, nodeA, nodeB, varargin)
            % ADDPIPE  hn.addPipe(nodeA, nodeB, 'name','pipe1', 'L',40, 'D',0.11, ...)
            %   A supply pipe runs from nodeA toward nodeB, away from the plant; a return pipe
            %   (both nodes on the return side) runs from nodeA toward nodeB, toward the plant.
            %   Any pipe property can be given as a name-value pair.
            ps = DHS.Hydraulic.Pipe([nodeA.name '->' nodeB.name], nodeA, nodeB, varargin{:});
            if isa(nodeA, 'DHS.Hydraulic.TJunction')
                if nodeA.attachedCount() == 0, ps.teeSide = 'run'; else, ps.teeSide = 'branch'; end
                nodeA.markPipeAttached();
            end
            p = obj.registerPipe(ps);
        end

        function p = addPump(obj, nodeA, nodeB, varargin)
            % ADDPUMP  hn.addPump(nodeA, nodeB, 'name','P1', 'dp0',5e4, 'mdotRated',1.5)
            %   An in-line centrifugal pump between two nodes of the same tree. Any pump property can be given
            %   as a name-value pair, or a pre-built DHS.Hydraulic.CentrifugalPump as the third argument
            %   after the nodes. It adds its head at that point of the loop.
            if ~isempty(varargin) && isa(varargin{1}, 'DHS.Hydraulic.Pump')
                pump = varargin{1};  varargin(1) = [];
            else
                pump = DHS.Hydraulic.CentrifugalPump([nodeA.name '->' nodeB.name]);
            end
            for i = 1:2:numel(varargin), pump.(varargin{i}) = varargin{i+1}; end
            pump.nodeA = nodeA;  pump.nodeB = nodeB;
            p = obj.registerPipe(pump);
        end

        function p = registerPipe(obj, pipe)
            % REGISTERPIPE  Shared endpoint for both assembly styles: given a
            %   DHS.Hydraulic.Pipe whose nodeA/nodeB are already set, adds it to the supply
            %   or the return tree. Used directly by DHS.Hydraulic.Pipe.connectOutput.
            if obj.hasLink(pipe), p = pipe;  return, end
            nodeA = pipe.nodeA;  nodeB = pipe.nodeB;
            assert(~isempty(nodeA) && ~isempty(nodeB), 'DHS:HydraulicNetwork:registerPipe', ...
                'Pipe "%s" needs both ends wired before it can be used.', pipe.name);
            if nodeA == nodeB
                pipe.decorative = true;   % a same-node round trip inside a lumped
                p = pipe;  return          % component (e.g. boiler->pump); not solved
            end
            assert(strcmp(nodeA.side, nodeB.side), 'DHS:HydraulicNetwork:sides', ...
                'Pipe "%s" joins a supply node to a return node; use the building or the bypass for that.', pipe.name);
            nodeA.network = obj;  nodeB.network = obj;
            if strcmp(nodeA.side, 'supply')
                nodeB.parentPipe = pipe;                 % toward the plant
                nodeA.childPipes{end+1} = pipe;
                obj.pipes{end+1} = pipe;
            else
                nodeA.parentPipe = pipe;                 % toward the plant: the pipe leaving this node
                nodeB.childPipes{end+1} = pipe;          % pipes arriving from the buildings' side
                obj.returnPipes{end+1} = pipe;
            end
            obj.registerJunctionIfNew(nodeA);
            obj.registerJunctionIfNew(nodeB);
            DHS.registerName(obj, pipe);
            if ~isempty(obj.nameOwner), DHS.registerName(obj.nameOwner, pipe); end
            obj.compiled = false;
            p = pipe;
        end

        function connectBuilding(obj, supplyJunction, building, returnJunction)
            % CONNECTBUILDING  hn.connectBuilding(supplyJunction, building, returnJunction)
            %   The older, declarative form of  tee.portC.connect(building); building.connect(returnJunction).
            %   The building (or radiator) is fed from a supply junction and drains into a return junction
            %   (the plant's own returnPort is allowed). A building's two service pipes,
            %   building.connPipeSup and building.connPipeRet, start from building.connLength
            %   and building.connD and can be edited separately afterwards.
            assert(isa(supplyJunction,'DHS.Hydraulic.Junction') && strcmp(supplyJunction.side,'supply'), ...
                'DHS:HydraulicNetwork:conn', 'First argument must be a supply junction.');
            assert(ismethod(building, 'branchResistance'), 'DHS:HydraulicNetwork:conn', ...
                'Second argument must be a DHS.Building or a DHS.Radiator.');
            assert(nargin >= 4 && isa(returnJunction,'DHS.Hydraulic.Junction') && strcmp(returnJunction.side,'return'), ...
                'DHS:HydraulicNetwork:conn', ...
                'Third argument must be a return junction: hn.connectBuilding(supplyJunction, building, returnJunction).');
            if obj.hasTerminal(building), return, end
            if isa(supplyJunction, 'DHS.Hydraulic.TJunction') && isempty(building.teeSide)
                supplyJunction.markStart('portC', building);   % a side tap off the trunk, never a straight-through run
            end
            building.supplyNode = supplyJunction;  building.returnNode = returnJunction;
            if ismethod(building, 'sizeServicePipes'), building.sizeServicePipes(); end
            if ~any(cellfun(@(x) x == building, supplyJunction.terminals)), supplyJunction.terminals{end+1} = building; end
            supplyJunction.fedBuildings{end+1} = building;
            returnJunction.fedBuildings{end+1} = building;
            obj.registerJunctionIfNew(supplyJunction);
            obj.registerJunctionIfNew(returnJunction);
            obj.buildings{end+1} = building;
            if ~isempty(obj.nameOwner) && isa(building, 'DHS.Radiator'), DHS.registerName(obj.nameOwner, building); end
            obj.compiled = false;
        end

        function discover(obj)
            % DISCOVER  Register every link and terminal that is connected to the plant but not yet in the
            %   lists, by walking the connections out from the plant supply port and in from the plant
            %   return port. Called by compile, so the order of the connect calls does not matter.
            if isempty(obj.plantSupply) || isempty(obj.plantReturn), return, end
            queue = {obj.plantSupply};  seen = {};
            while ~isempty(queue)
                n = queue{1};  queue(1) = [];
                if any(cellfun(@(x) x == n, seen)), continue, end
                seen{end+1} = n; %#ok<AGROW>
                for k = 1:numel(n.outLinks)
                    L = n.outLinks{k};
                    if isempty(L.nodeB) || strcmp(L.nodeB.side, 'return'), continue, end
                    obj.registerPipe(L);
                    queue{end+1} = L.nodeB; %#ok<AGROW>
                end
                for k = 1:numel(n.terminals)
                    T = n.terminals{k};
                    if ~isempty(T.returnNode), obj.connectBuilding(n, T, T.returnNode); end
                end
            end
            queue = {obj.plantReturn};  seen = {};
            while ~isempty(queue)
                n = queue{1};  queue(1) = [];
                if any(cellfun(@(x) x == n, seen)), continue, end
                seen{end+1} = n; %#ok<AGROW>
                for k = 1:numel(n.inLinks)
                    L = n.inLinks{k};
                    if isempty(L.nodeA) || strcmp(L.nodeA.side, 'supply'), continue, end
                    obj.registerPipe(L);
                    queue{end+1} = L.nodeA; %#ok<AGROW>
                end
            end
        end

        function orderTerminals(obj, list)
            % ORDERTERMINALS  Put the given buildings first, in that order, so that the flow vector of
            %   solve() is indexed like the system's building list. Other terminals (bypass links) follow.
            idx = zeros(1, numel(list));
            for k = 1:numel(list)
                j = find(cellfun(@(x) x == list{k}, obj.buildings), 1);
                assert(~isempty(j), 'DHS:HydraulicNetwork:notConnected', ...
                    'Building "%s" is not connected to the network: tee.portC.connect(building); building.connect(returnJunction).', list{k}.name);
                idx(k) = j;
            end
            rest = setdiff(1:numel(obj.buildings), idx, 'stable');
            obj.buildings = obj.buildings([idx rest]);
            obj.compiled = false;
        end

        function tf = hasLink(obj, link)
            tf = any(cellfun(@(x) x == link, obj.pipes)) || any(cellfun(@(x) x == link, obj.returnPipes));
        end

        function tf = hasTerminal(obj, term)
            tf = any(cellfun(@(x) x == term, obj.buildings));
        end

        function L = allLinks(obj)
            % ALLLINKS  Every link of the network: the supply and return pipes, valves and pumps, and the bypass links.
            L = [obj.pipes, obj.returnPipes];
            for k = 1:numel(obj.buildings)
                if isa(obj.buildings{k}, 'DHS.Hydraulic.CrossLink'), L{end+1} = obj.buildings{k}.link; end %#ok<AGROW>
            end
        end

        function controlLinks(obj, sys, dt)
            % CONTROLLINKS  Run the controllers of the valves and in-line pumps that sit in the network.
            links = obj.allLinks();
            for k = 1:numel(links)
                L = links{k};
                if isa(L, 'DHS.Hydraulic.Valve') && ~isempty(L.controller)
                    L.pos = min(1, max(0, L.controller.update(sys, dt)));
                elseif isa(L, 'DHS.Hydraulic.Pump') && ~isempty(L.controller)
                    L.speed = min(1, max(0, L.controller.update(sys, dt)));
                end
            end
        end

        function beginRun(obj)
            % BEGINRUN  Start of a run: the valves of the network are at their commands and their lags apply.
            L = obj.allValves();
            for k = 1:numel(L), L{k}.beginRun(); end
        end

        function endRun(obj)
            L = obj.allValves();
            for k = 1:numel(L), L{k}.endRun(); end
        end

        function advanceValves(obj, dt)
            % ADVANCEVALVES  Move every valve of the network toward its command over a step dt [s].
            L = obj.allValves();
            for k = 1:numel(L), L{k}.advance(dt); end
        end

        function V = allValves(obj)
            % every valve of the network: in-line and bypass links, and the bypass valve of addBypass
            L = obj.allLinks();  V = {};
            for k = 1:numel(L)
                if isa(L{k}, 'DHS.Hydraulic.Valve'), V{end+1} = L{k}; end %#ok<AGROW>
            end
            if obj.hasBypass(), V{end+1} = obj.bypassValve; end
        end

        function resetLinkControllers(obj)
            L = obj.allLinks();
            for k = 1:numel(L)
                if (isa(L{k}, 'DHS.Hydraulic.Valve') || isa(L{k}, 'DHS.Hydraulic.Pump')) && ~isempty(L{k}.controller)
                    L{k}.controller.reset();
                end
            end
        end

        function addBypass(obj, supplyJunction, returnJunction, varargin)
            % ADDBYPASS  An end-of-line bypass from a supply junction to a return junction.
            %   hn.addBypass(supplyJunction, returnJunction, 'L',20, 'D',0.05, 'Kvs',1.5)
            %   hn.addBypass(t4, r4, 'name','bp1', 'L',20, 'D',0.05, 'Kvs',1.5, 'pos',1)
            %   A pipe plus a valve joins the end of the supply tree straight to the
            %   return side. Water the buildings do not draw (their valves are partly closed)
            %   passes through it and joins the return; its flow follows from the
            %   differential pressure between the two junctions, sqrt(dp/K) with K the pipe's
            %   resistance plus the valve's.
            %   Name-value pairs set the pipe ('name' (default 'bypass'), 'L', 'D', 'eps',
            %   'UperM') and the valve ('Kvs', 'pos' (default 1, fixed), 'char', 'rangeability',
            %   'minPos'). The pipe is hn.<name> and hn.bypassPipe, the valve hn.bypassValve;
            %   attach a controller to the valve to move it (DHS.controllers.Controller).
            assert(nargin >= 3 && isa(supplyJunction,'DHS.Hydraulic.Junction') && strcmp(supplyJunction.side,'supply') ...
                && isa(returnJunction,'DHS.Hydraulic.Junction') && strcmp(returnJunction.side,'return'), ...
                'DHS:HydraulicNetwork:bypass', 'addBypass needs a supply junction and a return junction.');
            pipe  = DHS.Hydraulic.Pipe('bypass', 'L',20, 'D',0.05);
            valve = DHS.Hydraulic.Valve('bypass.valve', 'Kvs',1.5, 'char','linear', 'pos',1);
            for i = 1:2:numel(varargin)
                key = varargin{i};  val = varargin{i+1};
                if isprop(pipe, key)
                    pipe.(key) = val;
                elseif isprop(valve, key)
                    valve.(key) = val;
                else
                    error('DHS:HydraulicNetwork:bypass', '"%s" is not a pipe or valve property.', key);
                end
            end
            pipe.nodeA = supplyJunction;  pipe.nodeB = returnJunction;
            if isa(supplyJunction, 'DHS.Hydraulic.TJunction'), pipe.teeSide = 'run'; end
            obj.bypassPipe = pipe;  obj.bypassValve = valve;
            obj.bypassJunction = supplyJunction;  obj.bypassReturnJunction = returnJunction;
            DHS.registerName(obj, pipe);
            obj.compiled = false;
        end

        function tf = hasBypass(obj)
            tf = ~isempty(obj.bypassPipe);
        end

        % ---- compile / solve ------------------------------------------------
        function compile(obj)
            % COMPILE  Freeze the two trees into integer-indexed arrays so solve()
            %   never touches a string or a containers.Map per step.
            assert(~isempty(obj.plantSupply) && ~isempty(obj.plantReturn), 'DHS:HydraulicNetwork:noPlant', ...
                'Connect the plant to the network first.');
            obj.discover();
            hasPump = ~isempty(obj.plantPump) || any(cellfun(@(x) isa(x, 'DHS.Hydraulic.Pump'), [obj.pipes, obj.returnPipes]));
            assert(hasPump, 'DHS:HydraulicNetwork:noPump', ...
                'The network has no pump to circulate the water: add one, for example pipe.addPump(''dp0'',3e4, ''mdotRated'',1).');
            c = struct();

            % ---- chains of links that carry the flow of a single terminal (a valve, pipes before a radiator)
            %      are folded into that terminal's branch: they are in series with it, so its flow is
            %      sqrt(dp / total K). This keeps the flow iteration well conditioned when a valve is nearly shut.
            nB0 = numel(obj.buildings);
            absorbed = {};  supChain = cell(1,nB0);  retChain = cell(1,nB0);  topS = cell(1,nB0);  topR = cell(1,nB0);
            for b = 1:nB0
                bd = obj.buildings{b};
                n = bd.supplyNode;  chain = {};  nTerm = 1;       % the terminal's own node feeds one terminal, the nodes behind it none
                from = [];                                         % the link we came from (a child of n)
                while obj.foldable(n, obj.plantSupply, from, nTerm)
                    L = n.parentPipe;  chain = [{L}, chain];  absorbed{end+1} = L;  n = L.nodeA;  nTerm = 0;  from = L; %#ok<AGROW>
                end
                supChain{b} = chain;  topS{b} = n;
                r = bd.returnNode;  chain = {};  nTerm = 1;  from = [];
                while obj.foldable(r, obj.plantReturn, from, nTerm)
                    L = r.parentPipe;  chain{end+1} = L;  absorbed{end+1} = L;  r = L.nodeB;  nTerm = 0;  from = L; %#ok<AGROW>
                end
                retChain{b} = chain;  topR{b} = r;
                for q = [supChain{b}, retChain{b}], q{1}.downBuildings = b; end
            end
            c.supChain = supChain;  c.retChain = retChain;

            % ---- supply tree: node 1 = plant supply port, 2.. = supply junctions
            nJ = numel(obj.junctions);
            c.nS = nJ + 1;
            idxS = containers.Map('KeyType','char','ValueType','double');
            idxS(obj.plantSupply.name) = 1;
            for k = 1:nJ, idxS(obj.junctions{k}.name) = k + 1; end
            order = []; queue = keepTree(obj.plantSupply.childPipes, absorbed);
            while ~isempty(queue)
                ps = queue{1}; queue(1) = [];
                order(end+1) = find(cellfun(@(x) x == ps, obj.pipes), 1); %#ok<AGROW>
                queue = [queue, keepTree(ps.nodeB.childPipes, absorbed)]; %#ok<AGROW>
            end
            c.orderS = order;
            nP = numel(obj.pipes);
            c.sA = zeros(1,nP);  c.sB = zeros(1,nP);          % nodes at the plant side and the far side
            for k = 1:nP
                c.sA(k) = idxS(obj.pipes{k}.nodeA.name);
                c.sB(k) = idxS(obj.pipes{k}.nodeB.name);
            end

            % ---- return tree: node 1 = plant return port, 2.. = return junctions
            nR1 = numel(obj.returnJunctions);
            c.nR = nR1 + 1;
            idxR = containers.Map('KeyType','char','ValueType','double');
            idxR(obj.plantReturn.name) = 1;
            for k = 1:nR1, idxR(obj.returnJunctions{k}.name) = k + 1; end
            orderR = []; queue = keepTree(obj.plantReturn.childPipes, absorbed);   % pipes arriving at the plant
            while ~isempty(queue)
                pr = queue{1}; queue(1) = [];
                orderR(end+1) = find(cellfun(@(x) x == pr, obj.returnPipes), 1); %#ok<AGROW>
                queue = [queue, keepTree(pr.nodeA.childPipes, absorbed)]; %#ok<AGROW>
            end
            c.orderR = orderR;
            nPR = numel(obj.returnPipes);
            c.rA = zeros(1,nPR);  c.rB = zeros(1,nPR);        % rA: far end (flow starts), rB: toward the plant
            for k = 1:nPR
                c.rA(k) = idxR(obj.returnPipes{k}.nodeA.name);
                c.rB(k) = idxR(obj.returnPipes{k}.nodeB.name);
            end

            % ---- branches: each building (and the bypass) joins a supply node and a return node
            nB = numel(obj.buildings);
            c.sNode = zeros(1,nB);  c.rNode = zeros(1,nB);
            fedS = cell(1, c.nS);  fedR = cell(1, c.nR);
            for b = 1:nB
                bd = obj.buildings{b};
                c.sNode(b) = idxS(topS{b}.name);
                c.rNode(b) = idxR(topR{b}.name);
                fedS{c.sNode(b)} = [fedS{c.sNode(b)}, b];
                fedR{c.rNode(b)} = [fedR{c.rNode(b)}, b];
            end
            c.bypassS = 0;  c.bypassR = 0;
            if obj.hasBypass()
                c.sNode(nB+1) = idxS(obj.bypassJunction.name);
                c.rNode(nB+1) = idxR(obj.bypassReturnJunction.name);
                fedS{c.sNode(nB+1)} = [fedS{c.sNode(nB+1)}, nB+1];
                fedR{c.rNode(nB+1)} = [fedR{c.rNode(nB+1)}, nB+1];
                c.bypassS = c.sNode(nB+1);  c.bypassR = c.rNode(nB+1);
            end

            % ---- branches behind every pipe, leaves first
            c.downS = cell(1, nP);
            for kk = numel(order):-1:1
                k = order(kk);  ps = obj.pipes{k};
                down = fedS{c.sB(k)};
                kids = keepTree(ps.nodeB.childPipes, absorbed);
                for q = 1:numel(kids)
                    down = [down, c.downS{find(cellfun(@(x) x == kids{q}, obj.pipes), 1)}]; %#ok<AGROW>
                end
                c.downS{k} = unique(down);
                ps.downBuildings = c.downS{k}(c.downS{k} <= nB);
            end
            c.downR = cell(1, nPR);
            for kk = numel(orderR):-1:1
                k = orderR(kk);  pr = obj.returnPipes{k};
                down = fedR{c.rA(k)};
                kids = keepTree(pr.nodeA.childPipes, absorbed);
                for q = 1:numel(kids)
                    down = [down, c.downR{find(cellfun(@(x) x == kids{q}, obj.returnPipes), 1)}]; %#ok<AGROW>
                end
                c.downR{k} = unique(down);
                pr.downBuildings = c.downR{k}(c.downR{k} <= nB);
            end
            obj.solverData_ = c;
            obj.compiled = true;
        end

        function s = solve(obj, pumpFrac)
            if nargin < 1 || isempty(pumpFrac), pumpFrac = 1; end
            if ~obj.compiled, obj.compile(); end
            c = obj.solverData_;
            nB = numel(obj.buildings);
            r = obj.rho;  mu_ = obj.mu;

            Kbr = zeros(1,nB);  pumps = cell(1,nB);
            for b = 1:nB
                bd = obj.buildings{b};
                Kbr(b)   = obj.terminalK(b, max(bd.branchFlow(), 0.02), r, mu_);
                pumps{b} = bd.branchPump();
            end

            m = zeros(1,nB);
            for b = 1:nB
                m(b) = max(obj.buildings{b}.branchFlow(), pumps{b}.solveBranch(Kbr(b), 0, pumps{b}.speed));
            end

            % end-of-line bypass: one more branch (index nB+1) with no pump, whose flow
            % follows from the differential pressure across it, m = sqrt(dp/K)
            hasBp = obj.hasBypass();  Kbp = 0;
            if hasBp
                Kbp = obj.bypassPipe.resistance(max(obj.bypassPipe.mdot, 0.2), r, mu_) ...
                    + obj.bypassValve.resistance(r);
                m(nB+1) = max(obj.bypassPipe.mdot, 0.1);
            end
            nT = numel(m);

            ctx = struct('c',c, 'Kbr',Kbr, 'pumps',{pumps}, 'hasBp',hasBp, ...
                         'Kbp',Kbp, 'nB',nB, 'nT',nT, 'r',r, 'mu',mu_, 'pumpFrac',pumpFrac);
            [x, nEval, err] = obj.solveFlows(m(:), ctx);
            obj.lastIter = nEval;  obj.lastErr = err;
            m = x.';
            for b = 1:nB                                       % branch resistances at the solved flows
                Kbr(b) = obj.terminalK(b, max(m(b), 0.02), r, mu_);
            end

            Mtot = sum(m);
            mBp = 0;
            if hasBp
                mBp = m(nT);
                obj.bypassPipe.mdot = mBp;  obj.bypassPipe.dp = obj.bypassPipe.resistance(mBp, r, mu_)*mBp^2;
                obj.bypassPipe.vel  = mBp/(r*pi*obj.bypassPipe.D^2/4);
                obj.bypassValve.dp  = obj.bypassValve.resistance(r)*mBp^2;
            end
            [pS, pR] = obj.pressureWalk(m, pumpFrac);
            dpC = 0;
            if ~isempty(obj.plantPump)
                dpC = obj.plantPump.curveHead(Mtot, pumpFrac);
                obj.plantPump.head = dpC;  obj.plantPump.mdot = Mtot;
            end

            obj.plantSupply.p = pS(1);  obj.plantReturn.p = pR(1);
            for k = 1:numel(obj.junctions),       obj.junctions{k}.p       = pS(k+1); end
            for k = 1:numel(obj.returnJunctions), obj.returnJunctions{k}.p = pR(k+1); end
            pSupBranch = zeros(1,nB); pRetBranch = zeros(1,nB); vel = zeros(1,nB);
            for b = 1:nB
                bd = obj.buildings{b};
                [~, dpBP] = pumps{b}.solveBranch(Kbr(b), pS(c.sNode(b)) - pR(c.rNode(b)), pumps{b}.speed);
                pcur = pS(c.sNode(b));                         % pressure walk along the folded links
                for k = 1:numel(c.supChain{b})
                    L = c.supChain{b}{k};  [Kl, Hl] = L.linkLoss(m(b), r, mu_);
                    dpl = Kl*m(b)^2 - Hl;  L.setFlow(m(b), dpl, r);  pcur = pcur - dpl;  L.nodeB.p = pcur;
                end
                prcur = pR(c.rNode(b));
                for k = numel(c.retChain{b}):-1:1
                    L = c.retChain{b}{k};  [Kl, Hl] = L.linkLoss(m(b), r, mu_);
                    dpl = Kl*m(b)^2 - Hl;  L.setFlow(m(b), dpl, r);  prcur = prcur + dpl;  L.nodeA.p = prcur;
                end
                pSupBranch(b) = pcur + dpBP;
                pRetBranch(b) = prcur;
                vel(b) = bd.setBranchResult(m(b), r, dpBP, pSupBranch(b), pRetBranch(b));
            end

            s = struct('Mtot',Mtot, 'dpPump',dpC, 'pSupHeader',obj.pReturnRef + dpC, ...
                       'mdot',m(1:nB), 'mdotBypass',mBp, 'vel',vel, ...
                       'pSupBranch',pSupBranch, 'pRetBranch',pRetBranch);
        end

        function [TsupHx, Qloss] = supplyTemperatures(obj, Tplant, Tground, m, cp)
            % SUPPLYTEMPERATURES  Walk the supply tree out from the plant.
            %   [TsupHx, Qloss] = hn.supplyTemperatures(Tplant, Tground, m, cp)
            %   Water leaves the plant at Tplant [degC] and loses heat in every pipe
            %   with the flow that pipe carries (DHS.Hydraulic.Pipe.outletTemperature);
            %   a junction splits the flow and passes the temperature on unchanged
            %   (no heat loss in the fitting). m is the building flow vector [kg/s].
            %   Returns the temperature at each building's heat exchanger inlet and
            %   the total supply-side heat loss [W]. Pipe and junction temperatures
            %   are stored (pipe.Tin/Tout, junction.T).
            if ~obj.compiled, obj.compile(); end
            c = obj.solverData_;
            Tn = zeros(1, c.nS);  Tn(1) = Tplant;  Qloss = 0;
            m = obj.withBypassFlow(m);                      % append the bypass flow (if any)
            for kk = 1:numel(c.orderS)
                k = c.orderS(kk);
                Q = sum(m(c.downS{k}));
                [To, ql] = obj.pipes{k}.outletTemperature(Tn(c.sA(k)), Tground, Q, cp);
                Tn(c.sB(k)) = To;  Qloss = Qloss + ql;
            end
            nB = numel(obj.buildings);  TsupHx = zeros(1, nB);
            for b = 1:nB
                T0 = Tn(c.sNode(b));
                for q = 1:numel(c.supChain{b})                 % links folded into the branch
                    [T0, ql] = c.supChain{b}{q}.outletTemperature(T0, Tground, m(b), cp);
                    Qloss = Qloss + ql;
                end
                [TsupHx(b), ql] = obj.buildings{b}.inletTemperature(T0, Tground, m(b), cp);
                Qloss = Qloss + ql;
            end
            if obj.hasBypass()                             % supply water that no building takes
                [~, ql] = obj.bypassPipe.outletTemperature(Tn(c.bypassS), Tground, m(nB+1), cp);
                Qloss = Qloss + ql;
            end
            obj.plantSupply.T = Tplant;
            for k = 1:numel(obj.junctions), obj.junctions{k}.T = Tn(k+1); end
        end

        function [Tret, Qloss] = returnTemperatures(obj, Thx, Tground, m, cp)
            % RETURNTEMPERATURES  Walk the return tree in toward the plant.
            %   [Tret, Qloss] = hn.returnTemperatures(Thx, Tground, m, cp)
            %   Thx is each building's heat-exchanger outlet temperature [degC].
            %   Every return pipe loses heat with its own flow, and at each junction
            %   the incoming streams mix with their enthalpy flows (m*cp*T). Returns the
            %   temperature arriving at the plant and the total return-side heat loss [W].
            if ~obj.compiled, obj.compile(); end
            c = obj.solverData_;
            nB = numel(obj.buildings);  Qloss = 0;
            m = obj.withBypassFlow(m);
            sumM = zeros(1, c.nR);  sumMT = zeros(1, c.nR);
            for b = 1:nB
                if b <= numel(Thx), Tb = Thx(b); else, Tb = obj.buildings{b}.Tpass; end   % a bypass link passes the water on
                [To, ql] = obj.buildings{b}.outletTemperature(Tb, Tground, m(b), cp);
                Qloss = Qloss + ql;
                for q = 1:numel(c.retChain{b})
                    [To, ql] = c.retChain{b}{q}.outletTemperature(To, Tground, m(b), cp);
                    Qloss = Qloss + ql;
                end
                n = c.rNode(b);
                sumM(n) = sumM(n) + m(b);  sumMT(n) = sumMT(n) + m(b)*To;
            end
            if obj.hasBypass()      % bypass water enters the return at its return junction, at the temperature it left the bypass
                n = c.bypassR;
                sumM(n) = sumM(n) + m(nB+1);  sumMT(n) = sumMT(n) + m(nB+1)*obj.bypassPipe.Tout;
            end
            Tn = repmat(Tground, 1, c.nR);
            for kk = numel(c.orderR):-1:1                  % far ends first
                k = c.orderR(kk);  a = c.rA(k);  b = c.rB(k);
                Q = sum(m(c.downR{k}));
                if sumM(a) > 0, Tmix = sumMT(a)/sumM(a); else, Tmix = Tground; end
                Tn(a) = Tmix;
                [To, ql] = obj.returnPipes{k}.outletTemperature(Tmix, Tground, Q, cp);
                Qloss = Qloss + ql;
                sumM(b) = sumM(b) + Q;  sumMT(b) = sumMT(b) + Q*To;
            end
            if sumM(1) > 0, Tret = sumMT(1)/sumM(1);
            else,           Tret = mean(Thx(1:min(numel(Thx), nB)));
            end
            Tn(1) = Tret;
            obj.plantReturn.T = Tret;
            for k = 1:numel(obj.returnJunctions), obj.returnJunctions{k}.T = Tn(k+1); end
        end
    end

    methods (Access = private)
        function [x, nEval, err] = solveFlows(obj, x, ctx)
            % The branch flows x solve  F(x) = x - G(x) = 0, where G(x) is the flow each branch passes at the
            % pressure difference that the flows x leave across it. obj.solver selects the method:
            %   'newton'      Newton's method with a Jacobian built once by finite differences, updated by
            %                 Broyden's rule and reused by the next solve (whose flows are close), with a
            %                 backtracking line search. Robust with pump curves and nearly shut valves.
            %   'anderson'    damped first step, then Anderson acceleration of the fixed point x = G(x).
            %   'fixedPoint'  x = (1-w) x + w G(x), w = damping, halved whenever the error stops falling.
            nT = ctx.nT;
            Fx = x - obj.flowMap(x.', ctx).';
            err = max(abs(Fx));  nEval = 1;
            switch obj.solver
                case 'newton'
                    J = obj.jac_;
                    if ~isequal(size(J), [nT nT]), J = []; end
                    sinceFD = 0;  errBest = err;  it = 0;
                    while err >= obj.tol && it < obj.maxIter
                        it = it + 1;
                        if isempty(J) || sinceFD >= 6
                            J = zeros(nT);                                  % finite-difference Jacobian
                            for j = 1:nT
                                h = max(1e-4, 1e-3*abs(x(j)));
                                xj = x;  xj(j) = xj(j) + h;
                                J(:,j) = (xj - obj.flowMap(xj.', ctx).' - Fx) / h;  nEval = nEval + 1;
                            end
                            sinceFD = 0;
                        end
                        dx = -(J \ Fx);
                        if any(~isfinite(dx)), dx = -Fx; J = []; end
                        t = 1;
                        for ls = 1:8                                       % backtracking
                            xn = max(0, x + t*dx);
                            Fn = xn - obj.flowMap(xn.', ctx).';  nEval = nEval + 1;
                            if max(abs(Fn)) < (1 - 1e-4*t)*err || ls == 8, break, end
                            t = 0.5*t;
                        end
                        dxs = xn - x;  dF = Fn - Fx;
                        if any(dxs ~= 0) && ~isempty(J)
                            J = J + ((dF - J*dxs) * dxs.') / (dxs.'*dxs);     % Broyden update
                        end
                        x = xn;  Fx = Fn;  err = max(abs(Fx));
                        if err < 0.5*errBest, errBest = err;  sinceFD = 0; else, sinceFD = sinceFD + 1; end
                    end
                    obj.jac_ = J;
                case 'anderson'
                    w = obj.damping;  errPrev = Inf;
                    FH = zeros(nT, 0);  GH = zeros(nT, 0);
                    for it = 1:obj.maxIter
                        if err < obj.tol, break, end
                        g = x + (-Fx);                                       % G(x) = x - F(x)
                        g = g(:);
                        if err > 10*errPrev
                            w = max(0.02, 0.5*w);  FH = zeros(nT, 0);  GH = zeros(nT, 0);
                        end
                        errPrev = err;
                        FH = [FH, g - x];  GH = [GH, g]; %#ok<AGROW>
                        if size(FH, 2) > obj.andersonDepth, FH(:,1) = [];  GH(:,1) = []; end
                        if size(FH, 2) >= 2
                            dF = diff(FH, 1, 2);  dG = diff(GH, 1, 2);
                            A2 = dF.'*dF;
                            gam = (A2 + 1e-10*max(trace(A2), eps)*eye(size(A2,1))) \ (dF.'*(g - x));
                            x = max(0, GH(:,end) - dG*gam);
                        else
                            x = (1 - w)*x + w*g;
                        end
                        Fx = x - obj.flowMap(x.', ctx).';  nEval = nEval + 1;  err = max(abs(Fx));
                    end
                case 'fixedPoint'
                    w = obj.damping;  errPrev = Inf;
                    for it = 1:obj.maxIter
                        if err < obj.tol, break, end
                        if err > errPrev, w = max(0.02, 0.5*w); end
                        errPrev = err;
                        x = x - w*Fx;                                       % x + w (G(x) - x)
                        Fx = x - obj.flowMap(x.', ctx).';  nEval = nEval + 1;  err = max(abs(Fx));
                    end
            end
        end

        function g = flowMap(obj, m, ctx)
            % G(m): the flow each branch passes at the pressure difference the flows m leave across it
            c = ctx.c;  Kbr = ctx.Kbr;
            for b = 1:ctx.nB                                   % every branch's K follows its flow
                Kbr(b) = obj.terminalK(b, max(m(b), 0.02), ctx.r, ctx.mu);
            end
            [pS, pR] = obj.pressureWalk(m, ctx.pumpFrac);
            dpAvail = pS(c.sNode) - pR(c.rNode);
            g = zeros(1, ctx.nT);
            for b = 1:ctx.nB, g(b) = ctx.pumps{b}.solveBranch(Kbr(b), dpAvail(b), ctx.pumps{b}.speed); end
            if ctx.hasBp, g(ctx.nT) = sqrt(max(0, dpAvail(ctx.nT)) / ctx.Kbp); end
        end

        function tf = foldable(obj, n, plantNode, from, nTerm)
            % a node whose only link and only terminal can be folded into that terminal's branch
            tf = false;
            if n == plantNode || isempty(n.parentPipe), return, end
            kids = n.childPipes;
            if ~isempty(from), kids(cellfun(@(x) x == from, kids)) = []; end
            if ~isempty(kids) || numel(n.fedBuildings) ~= nTerm, return, end
            if isa(n.parentPipe, 'DHS.Hydraulic.Pump'), return, end
            if obj.hasBypass() && (n == obj.bypassJunction || n == obj.bypassReturnJunction), return, end
            tf = true;
        end

        function K = terminalK(obj, b, Q, r, mu)
            % resistance of branch b at the flow Q: the terminal itself plus the links folded into it
            c = obj.solverData_;
            K = obj.buildings{b}.branchResistance(r, mu, Q) + obj.chainResistance(c.supChain{b}, Q, r, mu) ...
                                                           + obj.chainResistance(c.retChain{b}, Q, r, mu);
        end

        function K = chainResistance(~, links, Q, r, mu)
            K = 0;
            for k = 1:numel(links), K = K + links{k}.linkLoss(Q, r, mu); end
        end

        function m = withBypassFlow(obj, m)
            % M (1 x nB building flows) -> [M, bypass flow] when the network has a bypass
            if obj.hasBypass() && numel(m) == numel(obj.buildings)
                m = [m, obj.bypassPipe.mdot];
            end
        end

        function addToList(obj, node)
            if strcmp(node.side, 'supply'), obj.junctions{end+1} = node;
            else,                           obj.returnJunctions{end+1} = node;
            end
            DHS.registerName(obj, node);
        end

        function registerJunctionIfNew(obj, node)
            % REGISTERJUNCTIONIFNEW  A junction or T-junction built directly
            %   (DHS.Hydraulic.Junction(...) / TJunction(...), the port-wiring
            %   style) rather than through hn.addJunction still needs to be in
            %   the network's lists for compile()'s node-index map.
            if ~isempty(obj.plantSupply) && node == obj.plantSupply, return; end
            if ~isempty(obj.plantReturn) && node == obj.plantReturn, return; end
            if strcmp(node.side, 'supply'), list = obj.junctions; else, list = obj.returnJunctions; end
            if any(cellfun(@(j) j == node, list)), return; end
            node.network = obj;
            obj.addToList(node);
        end

        function [pS, pR] = pressureWalk(obj, m, pumpFrac)
            % integer-indexed walk: node 1 = plant port, then the junctions of each side
            c = obj.solverData_;
            r = obj.rho;  mu_ = obj.mu;
            dpC = 0;
            if ~isempty(obj.plantPump), dpC = obj.plantPump.curveHead(sum(m), pumpFrac); end
            pS = zeros(1, c.nS);  pR = zeros(1, c.nR);
            pS(1) = obj.pReturnRef + dpC;
            pR(1) = obj.pReturnRef;
            for kk = 1:numel(c.orderS)
                k  = c.orderS(kk);
                Q  = sum(m(c.downS{k}));
                ps = obj.pipes{k};
                [Ks, Hs] = ps.linkLoss(Q, r, mu_);        % a pipe loses K Q^2, an in-line pump also gains H
                dpk = Ks*Q^2 - Hs;
                pS(c.sB(k)) = pS(c.sA(k)) - dpk;         % supply: drops away from the plant
                ps.setFlow(Q, dpk, r);
            end
            for kk = 1:numel(c.orderR)
                k  = c.orderR(kk);
                Q  = sum(m(c.downR{k}));
                pr = obj.returnPipes{k};
                [Kr, Hr] = pr.linkLoss(Q, r, mu_);
                dpk = Kr*Q^2 - Hr;
                pR(c.rA(k)) = pR(c.rB(k)) + dpk;         % return: rises away from the plant
                pr.setFlow(Q, dpk, r);
            end
        end
    end
end

function out = keepTree(list, absorbed)
% the links of LIST that are not folded into a terminal's branch
    out = list;
    for k = numel(list):-1:1
        if any(cellfun(@(x) x == list{k}, absorbed)), out(k) = []; end
    end
end
