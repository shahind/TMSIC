classdef HydraulicNetwork < handle
% DHS.HYDRAULICNETWORK  The district pipe network: a tree of junctions and pipes
%                       rooted at the central heat plant, with buildings hanging
%                       off junctions. Distributed pumping (one central pump +
%                       one pump per building).
%
%   Two equivalent ways to build the same network -- both end up compiled into
%   the same integer-indexed tree, so solve() cannot tell which one you used.
%
%   DECLARATIVE
%     hn = sys.addHydraulicNetwork();
%     t1 = hn.addJunction('T1');
%     hn.addPipe(hn.plantSupply, t1, 'L',40, 'D',0.11);   % supply; return auto-mirrored
%     t2 = hn.addJunction('T2', 'type','tee', 'mainDiameter',0.11, 'sideDiameter',0.05);
%     hn.addPipe(t1, t2, 'L',50, 'D',0.11);                % a continuing trunk pipe = the run
%     hn.connectBuilding(t2, bldgArts);                    % a building is always the branch
%
%   PORT-WIRING  (reads like RCBS.Zone.addWall / connectToZone; see
%   DHS.Hydraulic.Junction/Pipe/TJunction)
%     hn = sys.addHydraulicNetwork();
%     pipe1 = DHS.Hydraulic.Pipe('CHP->T1', 'L',40, 'D',0.11);
%     chp.supplyPort.connectToPipe(pipe1);
%     tee1  = pipe1.addTjunction('T1', 0.05);              % mainDiameter = pipe1.D
%     pipe2 = DHS.Hydraulic.Pipe('T1->T2', 'L',50, 'D',0.11);
%     tee1.connectToPipe('portB', pipe2);  pipe2.connectOutput(t2);   % run
%     hn.connectBuilding(tee1, bldgAdmin);                            % always the branch
%
%   Each supply junction has a matching RETURN junction (its .mirror); every
%   supply pipe has a matching return pipe of the same L and D. You build the
%   SUPPLY tree; DHS mirrors it for the return. A building's own service
%   connection is sized by its connLength/connD rather than a separately-wired
%   pipe object, so the last hop to a building is hn.connectBuilding(tee,
%   building) in both styles.
%
%   SOLVE  (each co-simulation step, given the central pump speed pumpFrac):
%     * segment flow  Q_seg  = sum of the branch flows in the subtree below a pipe
%     * central pump head  dpC = plantPump.curveHead(Mtot, pumpFrac)
%     * pressure walk from the plant out to every junction, losing  K*Q_seg^2
%       on each supply pipe (plus a T-junction's own run/branch loss where one
%       sits, see DHS.Hydraulic.TJunction) and gaining it back on each return pipe
%     * each building branch (connection pipe + valve + HX body), given the
%       differential pressure left at its tee, closes through its own pump's
%       solveBranch -- the one nonlinear equation a centrifugal and a
%       fixed-displacement pump answer differently, see DHS.Hydraulic.Pump
%     * damped fixed-point on Mtot (segment flows and dpC depend on it)
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
        junctions cell = {}
        pipes     cell = {}
        retPipes  cell = {}
        buildings cell = {}
        pipeOrder double = []
        compiled  (1,1) logical = false
        % --- compiled integer-indexed topology (filled by compile(), no strings
        %     touched per step -- this is what keeps solve() fast) ---
        nS       (1,1) double = 0     % number of supply pressure nodes (junctions + plant)
        idxPlantS (1,1) double = 0
        pipeA double = []             % 1 x nPipes  supply node index of nodeA (toward plant)
        pipeB double = []             % 1 x nPipes  supply node index of nodeB (toward leaves)
        branchNode double = []        % 1 x nB      supply node index feeding each building
        downB   cell = {}             % 1 x nPipes  building indices in each pipe's subtree
    end
    properties
        plantSupply DHS.Hydraulic.Junction
        plantReturn DHS.Hydraulic.Junction
        plantPump                               % a DHS.Hydraulic.Pump: the central pump (owned by the plant)
    end

    methods
        % ---- assembly API (declarative) -----------------------------------
        function j = addJunction(obj, name, varargin)
            % ADDJUNCTION  hn.addJunction('T1')  for a plain tee, or
            %   hn.addJunction('T1','type','tee','mainDiameter',Dm,'sideDiameter',Ds)
            %   for one with its own minor-loss physics (see DHS.Hydraulic.TJunction).
            p = inputParser;  p.KeepUnmatched = true;
            p.addParameter('type', 'plain');
            p.addParameter('mainDiameter', 0.10);
            p.addParameter('sideDiameter', 0.05);
            p.parse(varargin{:});
            r = p.Results;
            if strcmpi(r.type, 'tee')
                js = DHS.Hydraulic.TJunction(name, 'mainDiameter',r.mainDiameter, 'sideDiameter',r.sideDiameter);
            else
                js = DHS.Hydraulic.Junction(name, 'supply');
            end
            js.network = obj;   % js.mirror is created automatically by the constructor
            obj.junctions{end+1} = js;
            j = js;
            obj.compiled = false;
        end

        function p = addPipe(obj, nodeA, nodeB, varargin)
            ps = DHS.Hydraulic.Pipe([nodeA.name '->' nodeB.name], nodeA, nodeB, varargin{:});
            if isa(nodeA, 'DHS.Hydraulic.TJunction')
                if nodeA.attachedCount() == 0, ps.teeSide = 'run'; else, ps.teeSide = 'branch'; end
                nodeA.markPipeAttached();
            end
            p = obj.registerPipe(ps);
        end

        function p = registerPipe(obj, pipe)
            % REGISTERPIPE  Shared endpoint for both assembly styles: given a
            %   DHS.Hydraulic.Pipe whose nodeA/nodeB are already set, builds and
            %   registers its return-side mirror exactly as addPipe always has.
            %   Used directly by DHS.Hydraulic.Pipe.connectOutput (port-wiring).
            nodeA = pipe.nodeA;  nodeB = pipe.nodeB;
            assert(~isempty(nodeA) && ~isempty(nodeB), 'DHS:HydraulicNetwork:registerPipe', ...
                'Pipe "%s" needs both ends wired before it can be used.', pipe.name);
            if nodeA == nodeB
                pipe.decorative = true;   % a same-node round trip inside a lumped
                p = pipe;  return          % component (e.g. boiler->pump); not solved
            end
            pr = DHS.Hydraulic.Pipe([nodeB.mirror.name '->' nodeA.mirror.name], nodeB.mirror, nodeA.mirror, ...
                'L',pipe.L, 'D',pipe.D, 'eps',pipe.eps, 'UperM',pipe.UperM);
            nodeB.parentPipe = pipe;
            nodeA.childPipes{end+1} = pipe;
            nodeB.network = obj;
            obj.pipes{end+1}    = pipe;
            obj.retPipes{end+1} = pr;
            obj.registerJunctionIfNew(nodeB);
            obj.compiled = false;
            p = pipe;
        end

        function connectBuilding(obj, junction, building)
            assert(isa(junction,'DHS.Hydraulic.Junction') && strcmp(junction.side,'supply'), ...
                'DHS:HydraulicNetwork:conn', 'First argument must be a supply junction.');
            assert(isa(building,'DHS.Building'), 'DHS:HydraulicNetwork:conn', ...
                'Second argument must be a DHS.Building.');
            building.inlet.parentPipe  = junction;
            building.outlet.parentPipe = junction.mirror;
            building.connPipeSup.nodeA = junction;
            building.connPipeSup.L = building.connLength;  building.connPipeSup.D = building.connD;
            building.connPipeRet.L = building.connLength;  building.connPipeRet.D = building.connD;
            if isa(junction, 'DHS.Hydraulic.TJunction')
                % a building's service connection is always a side tap off the
                % trunk, never a straight-through continuation -- so it always
                % picks up the tee's own branch loss (see TJunction.teeLossK),
                % regardless of how many other pipes already left this tee.
                building.connPipeSup.teeSide = 'branch';
                junction.markPipeAttached();
            end
            junction.fedBuildings{end+1} = building;
            obj.buildings{end+1} = building;
            obj.compiled = false;
        end

        % ---- compile / solve ------------------------------------------------
        function compile(obj)
            % COMPILE  Freeze the tree into integer-indexed arrays so solve()
            %   never touches a string or a containers.Map per step.
            assert(~isempty(obj.plantSupply), 'DHS:HydraulicNetwork:noPlant', ...
                'Connect the plant to the network first.');

            % node index map: 1 = plant supply, 2..nS = junctions (supply side)
            nJ = numel(obj.junctions);
            obj.nS = nJ + 1;
            obj.idxPlantS = 1;
            nodeIdx = containers.Map('KeyType','char','ValueType','double');
            nodeIdx(obj.plantSupply.name) = 1;
            for k = 1:nJ, nodeIdx(obj.junctions{k}.name) = k + 1; end

            % BFS from the plant -> parent-before-child pipe order
            order = []; queue = obj.plantSupply.childPipes;
            while ~isempty(queue)
                ps = queue{1}; queue(1) = [];
                idx = find(cellfun(@(x) x == ps, obj.pipes), 1);
                order(end+1) = idx; %#ok<AGROW>
                queue = [queue, ps.nodeB.childPipes]; %#ok<AGROW>
            end
            obj.pipeOrder = order;

            nP = numel(obj.pipes);
            obj.pipeA = zeros(1,nP);  obj.pipeB = zeros(1,nP);
            for k = 1:nP
                obj.pipeA(k) = nodeIdx(obj.pipes{k}.nodeA.name);
                obj.pipeB(k) = nodeIdx(obj.pipes{k}.nodeB.name);
            end

            nB = numel(obj.buildings);
            obj.branchNode = zeros(1,nB);
            fedAt = cell(1, obj.nS);
            for b = 1:nB
                ni = nodeIdx(obj.buildings{b}.inlet.parentPipe.name);
                obj.branchNode(b) = ni;
                fedAt{ni} = [fedAt{ni}, b];
            end

            % subtree building sets, post-order (leaf pipes are last in `order`)
            obj.downB = cell(1, nP);
            for kk = numel(order):-1:1
                k  = order(kk);
                ps = obj.pipes{k};
                down = fedAt{obj.pipeB(k)};
                for c = 1:numel(ps.nodeB.childPipes)
                    ci = find(cellfun(@(x) x == ps.nodeB.childPipes{c}, obj.pipes), 1);
                    down = [down, obj.downB{ci}]; %#ok<AGROW>
                end
                obj.downB{k} = unique(down);
                ps.downBuildings = obj.downB{k};
            end
            obj.compiled = true;
        end

        function s = solve(obj, pumpFrac)
            if nargin < 1 || isempty(pumpFrac), pumpFrac = 1; end
            if ~obj.compiled, obj.compile(); end
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
            bn = obj.branchNode;

            for it = 1:obj.maxIter %#ok<NASGU>
                [pS, pR] = obj.pressureWalk(m, pumpFrac);
                dpAvail = pS(bn) - pR(bn);
                mNew = zeros(1,nB);
                for b = 1:nB, mNew(b) = pumps{b}.solveBranch(Kbr(b), dpAvail(b), pumps{b}.speed); end
                if max(abs(mNew - m)) < 1e-9, m = mNew; break; end
                m = 0.5*m + 0.5*mNew;
            end

            Mtot = sum(m);
            [pS, pR] = obj.pressureWalk(m, pumpFrac);
            dpC = obj.plantPump.curveHead(Mtot, pumpFrac);

            pSupBranch = zeros(1,nB); pRetBranch = zeros(1,nB); vel = zeros(1,nB);
            for b = 1:nB
                bd = obj.buildings{b};  hx = bd.heatExchanger;
                A  = pi*bd.connD^2/4;
                bd.connPipeSup.mdot = m(b);  bd.connPipeRet.mdot = m(b);
                vel(b) = m(b)/(r*A);
                bd.connPipeSup.vel = vel(b);  bd.connPipeRet.vel = vel(b);
                [~, dpBP] = pumps{b}.solveBranch(Kbr(b), pS(bn(b)) - pR(bn(b)), pumps{b}.speed);
                hx.pump.mdot = m(b);  hx.pump.head = dpBP;
                hx.valve.dp  = hx.valve.resistance(r) * m(b)^2;
                pSupBranch(b) = pS(bn(b)) + dpBP;
                pRetBranch(b) = pR(bn(b));
                bd.inlet.p  = pSupBranch(b);
                bd.outlet.p = pRetBranch(b);
            end
            for k = 1:numel(obj.junctions)
                obj.junctions{k}.p        = pS(k+1);
                obj.junctions{k}.mirror.p = pR(k+1);
            end

            s = struct('Mtot',Mtot, 'dpPump',dpC, 'pSupHeader',obj.pReturnRef + dpC, ...
                       'mdot',m, 'vel',vel, 'pSupBranch',pSupBranch, 'pRetBranch',pRetBranch);
        end
    end

    methods (Access = private)
        function registerJunctionIfNew(obj, node)
            % REGISTERJUNCTIONIFNEW  A junction or T-junction built directly
            %   (DHS.Hydraulic.Junction(...) / TJunction(...), the port-wiring
            %   style) rather than through hn.addJunction still needs to be in
            %   obj.junctions for compile()'s node-index map.
            if node == obj.plantSupply, return; end
            if any(cellfun(@(j) j == node, obj.junctions)), return; end
            obj.junctions{end+1} = node;
        end

        function [pS, pR] = pressureWalk(obj, m, pumpFrac)
            % integer-indexed walk: node 1 = plant, nodes 2..nS = junctions
            r = obj.rho;  mu_ = obj.mu;
            dpC = obj.plantPump.curveHead(sum(m), pumpFrac);
            pS = zeros(1, obj.nS);  pR = zeros(1, obj.nS);
            pS(obj.idxPlantS) = obj.pReturnRef + dpC;
            pR(obj.idxPlantS) = obj.pReturnRef;
            for kk = 1:numel(obj.pipeOrder)
                k  = obj.pipeOrder(kk);
                Q  = sum(m(obj.downB{k}));
                ps = obj.pipes{k};  pr = obj.retPipes{k};
                Ks = ps.resistance(Q, r, mu_);
                Kr = pr.resistance(Q, r, mu_);
                a  = obj.pipeA(k);  b = obj.pipeB(k);
                pS(b) = pS(a) - Ks*Q^2;      % supply: drops away from the plant
                pR(b) = pR(a) + Kr*Q^2;      % return: rises away from the plant
                ps.mdot = Q; ps.dp = Ks*Q^2; ps.vel = Q/(r*pi*ps.D^2/4);
                pr.mdot = Q; pr.dp = Kr*Q^2; pr.vel = Q/(r*pi*pr.D^2/4);
            end
        end
    end
end
