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
%   PORT-WIRING  (reads like RCBS.Zone.addWall / connectToZone; see
%   DHS.Hydraulic.Junction/Pipe/TJunction)
%     pipe1 = DHS.Hydraulic.Pipe('sup1', 'L',40, 'D',0.11);
%     chp.supplyPort.connectToPipe(pipe1);                        % plant supply -> pipe1
%     tee1  = pipe1.addTjunction('T1', 0.05);                     % pipe1 -> tee T1 (mainDiameter = pipe1.D)
%     pipe2 = DHS.Hydraulic.Pipe('sup2', 'L',50, 'D',0.11);
%     tee1.portB.connectToPipe(pipe2);  pipe2.connectOutput(t2);  % the run of T1
%     r1    = DHS.Hydraulic.Junction('R1', 'return');
%     ret1  = DHS.Hydraulic.Pipe('ret1', 'L',45, 'D',0.13);
%     r1.connectToPipe(ret1);   ret1.connectOutput(chp.returnPort);   % return pipe from R1 to the plant
%     hn.connectBuilding(tee1, bldgAdmin, r1);
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
        maxIter    (1,1) double = 40
    end
    properties (SetAccess = private)
        junctions       cell = {}      % supply junctions
        returnJunctions cell = {}      % return junctions
        pipes           cell = {}      % supply pipes
        returnPipes     cell = {}      % return pipes
        buildings       cell = {}
        compiled  (1,1) logical = false
    end
    properties (SetAccess = private)
        bypassPipe     = []           % DHS.Hydraulic.Pipe from a supply junction to a return junction
        bypassValve    = []           % DHS.Hydraulic.Valve in series with it (sets the minimum flow)
        bypassJunction = []           % supply junction the bypass leaves
        bypassReturnJunction = []     % return junction the bypass joins
    end
    properties (Access = private)
        solverData_ = struct()        % integer-indexed copy of the topology, filled by compile()
    end
    properties
        plantSupply DHS.Hydraulic.Junction
        plantReturn DHS.Hydraulic.Junction
        plantPump                               % a DHS.Hydraulic.Pump: the central pump (owned by the plant)
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

        function p = registerPipe(obj, pipe)
            % REGISTERPIPE  Shared endpoint for both assembly styles: given a
            %   DHS.Hydraulic.Pipe whose nodeA/nodeB are already set, adds it to the supply
            %   or the return tree. Used directly by DHS.Hydraulic.Pipe.connectOutput.
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
            obj.compiled = false;
            p = pipe;
        end

        function connectBuilding(obj, supplyJunction, building, returnJunction)
            % CONNECTBUILDING  hn.connectBuilding(supplyJunction, building, returnJunction)
            %   The building is fed from a supply junction and drains into a return junction
            %   (the plant's own returnPort is allowed). Its two service pipes,
            %   building.connPipeSup and building.connPipeRet, start from building.connLength
            %   and building.connD and can be edited separately afterwards.
            assert(isa(supplyJunction,'DHS.Hydraulic.Junction') && strcmp(supplyJunction.side,'supply'), ...
                'DHS:HydraulicNetwork:conn', 'First argument must be a supply junction.');
            assert(isa(building,'DHS.Building'), 'DHS:HydraulicNetwork:conn', ...
                'Second argument must be a DHS.Building.');
            assert(nargin >= 4 && isa(returnJunction,'DHS.Hydraulic.Junction') && strcmp(returnJunction.side,'return'), ...
                'DHS:HydraulicNetwork:conn', ...
                'Third argument must be a return junction: hn.connectBuilding(supplyJunction, building, returnJunction).');
            building.connPipeSup.nodeA = supplyJunction;
            building.connPipeRet.nodeB = returnJunction;
            building.connPipeSup.L = building.connLength;  building.connPipeSup.D = building.connD;
            building.connPipeRet.L = building.connLength;  building.connPipeRet.D = building.connD;
            if isa(supplyJunction, 'DHS.Hydraulic.TJunction')
                % a building's service connection is always a side tap off the
                % trunk, never a straight-through continuation -- so it always
                % picks up the tee's own branch loss (see TJunction.teeLossK),
                % regardless of how many other pipes already left this tee.
                building.connPipeSup.teeSide = 'branch';
                supplyJunction.markPipeAttached();
            end
            supplyJunction.fedBuildings{end+1} = building;
            returnJunction.fedBuildings{end+1} = building;
            obj.registerJunctionIfNew(supplyJunction);
            obj.registerJunctionIfNew(returnJunction);
            obj.buildings{end+1} = building;
            obj.compiled = false;
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
            %   'KvMinFrac'). The pipe is hn.<name> and hn.bypassPipe, the valve hn.bypassValve;
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
            c = struct();

            % ---- supply tree: node 1 = plant supply port, 2.. = supply junctions
            nJ = numel(obj.junctions);
            c.nS = nJ + 1;
            idxS = containers.Map('KeyType','char','ValueType','double');
            idxS(obj.plantSupply.name) = 1;
            for k = 1:nJ, idxS(obj.junctions{k}.name) = k + 1; end
            order = []; queue = obj.plantSupply.childPipes;
            while ~isempty(queue)
                ps = queue{1}; queue(1) = [];
                order(end+1) = find(cellfun(@(x) x == ps, obj.pipes), 1); %#ok<AGROW>
                queue = [queue, ps.nodeB.childPipes]; %#ok<AGROW>
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
            orderR = []; queue = obj.plantReturn.childPipes;   % pipes arriving at the plant
            while ~isempty(queue)
                pr = queue{1}; queue(1) = [];
                orderR(end+1) = find(cellfun(@(x) x == pr, obj.returnPipes), 1); %#ok<AGROW>
                queue = [queue, pr.nodeA.childPipes]; %#ok<AGROW>
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
                c.sNode(b) = idxS(bd.connPipeSup.nodeA.name);
                c.rNode(b) = idxR(bd.connPipeRet.nodeB.name);
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
                for q = 1:numel(ps.nodeB.childPipes)
                    down = [down, c.downS{find(cellfun(@(x) x == ps.nodeB.childPipes{q}, obj.pipes), 1)}]; %#ok<AGROW>
                end
                c.downS{k} = unique(down);
                ps.downBuildings = c.downS{k}(c.downS{k} <= nB);
            end
            c.downR = cell(1, nPR);
            for kk = numel(orderR):-1:1
                k = orderR(kk);  pr = obj.returnPipes{k};
                down = fedR{c.rA(k)};
                for q = 1:numel(pr.nodeA.childPipes)
                    down = [down, c.downR{find(cellfun(@(x) x == pr.nodeA.childPipes{q}, obj.returnPipes), 1)}]; %#ok<AGROW>
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
                bd = obj.buildings{b};  hx = bd.heatExchanger;
                A  = pi*bd.connD^2/4;
                Kmin = bd.Kminor / (2*r*A^2);
                m0 = max(bd.connPipeSup.mdot, 0.2);
                Kbr(b) = bd.connPipeSup.resistance(m0,r,mu_) + bd.connPipeRet.resistance(m0,r,mu_) ...
                       + hx.primaryResistance(r) + Kmin;
                pumps{b} = hx.pump;
            end

            m = zeros(1,nB);
            for b = 1:nB
                m(b) = max(obj.buildings{b}.connPipeSup.mdot, pumps{b}.solveBranch(Kbr(b), 0, pumps{b}.speed));
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

            w = 0.5;  errPrev = Inf;                   % damping, halved whenever the iteration stops improving
            for it = 1:obj.maxIter %#ok<NASGU>
                [pS, pR] = obj.pressureWalk(m, pumpFrac);
                dpAvail = pS(c.sNode) - pR(c.rNode);
                mNew = zeros(1,nT);
                for b = 1:nB, mNew(b) = pumps{b}.solveBranch(Kbr(b), dpAvail(b), pumps{b}.speed); end
                if hasBp, mNew(nT) = sqrt(max(0, dpAvail(nT)) / Kbp); end
                err = max(abs(mNew - m));
                if err < 1e-9, m = mNew; break; end
                if err > errPrev, w = max(0.02, 0.5*w); end
                errPrev = err;
                m = (1 - w)*m + w*mNew;
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
            dpC = obj.plantPump.curveHead(Mtot, pumpFrac);
            obj.plantPump.head = dpC;  obj.plantPump.mdot = Mtot;

            pSupBranch = zeros(1,nB); pRetBranch = zeros(1,nB); vel = zeros(1,nB);
            for b = 1:nB
                bd = obj.buildings{b};  hx = bd.heatExchanger;
                A  = pi*bd.connD^2/4;
                bd.connPipeSup.mdot = m(b);  bd.connPipeRet.mdot = m(b);
                vel(b) = m(b)/(r*A);
                bd.connPipeSup.vel = vel(b);  bd.connPipeRet.vel = vel(b);
                [~, dpBP] = pumps{b}.solveBranch(Kbr(b), pS(c.sNode(b)) - pR(c.rNode(b)), pumps{b}.speed);
                hx.pump.mdot = m(b);  hx.pump.head = dpBP;
                hx.valve.dp  = hx.valve.resistance(r) * m(b)^2;
                pSupBranch(b) = pS(c.sNode(b)) + dpBP;
                pRetBranch(b) = pR(c.rNode(b));
                bd.inlet.p  = pSupBranch(b);
                bd.outlet.p = pRetBranch(b);
            end
            obj.plantSupply.p = pS(1);  obj.plantReturn.p = pR(1);
            for k = 1:numel(obj.junctions),       obj.junctions{k}.p       = pS(k+1); end
            for k = 1:numel(obj.returnJunctions), obj.returnJunctions{k}.p = pR(k+1); end

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
                [TsupHx(b), ql] = obj.buildings{b}.connPipeSup.outletTemperature( ...
                    Tn(c.sNode(b)), Tground, m(b), cp);
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
                [To, ql] = obj.buildings{b}.connPipeRet.outletTemperature(Thx(b), Tground, m(b), cp);
                Qloss = Qloss + ql;
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
            else,           Tret = mean(Thx);
            end
            Tn(1) = Tret;
            obj.plantReturn.T = Tret;
            for k = 1:numel(obj.returnJunctions), obj.returnJunctions{k}.T = Tn(k+1); end
        end
    end

    methods (Access = private)
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
            dpC = obj.plantPump.curveHead(sum(m), pumpFrac);
            pS = zeros(1, c.nS);  pR = zeros(1, c.nR);
            pS(1) = obj.pReturnRef + dpC;
            pR(1) = obj.pReturnRef;
            for kk = 1:numel(c.orderS)
                k  = c.orderS(kk);
                Q  = sum(m(c.downS{k}));
                ps = obj.pipes{k};
                Ks = ps.resistance(Q, r, mu_);
                pS(c.sB(k)) = pS(c.sA(k)) - Ks*Q^2;      % supply: drops away from the plant
                ps.mdot = Q; ps.dp = Ks*Q^2; ps.vel = Q/(r*pi*ps.D^2/4);
            end
            for kk = 1:numel(c.orderR)
                k  = c.orderR(kk);
                Q  = sum(m(c.downR{k}));
                pr = obj.returnPipes{k};
                Kr = pr.resistance(Q, r, mu_);
                pR(c.rA(k)) = pR(c.rB(k)) + Kr*Q^2;      % return: rises away from the plant
                pr.mdot = Q; pr.dp = Kr*Q^2; pr.vel = Q/(r*pi*pr.D^2/4);
            end
        end
    end
end
