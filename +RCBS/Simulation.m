classdef Simulation < handle
% RCBS.SIMULATION  Fixed-step implicit (backward-Euler) solver for an RC building.
%
%   The building's thermal network (constant R and C) is Linear Time-Invariant:
%
%       C .* dT/dt = -L*T + g_out*T_outdoor + Q(t)                         (1)
%
%   where  T        [degC]   node temperature vector            (N x 1)
%          C        [J/K]    node heat-capacity vector          (N x 1)
%          L        [W/K]    symmetric conductance (system) matrix (N x N)
%                            L(i,i) = sum of all conductances at node i
%                            L(i,j) = -G_ij  (conductance between i and j)
%          g_out    [W/K]    per-node conductance to the outdoor boundary (N x 1)
%          Q(t)     [W]      external heat injected at each node (solar, internal,
%                            hydronic, user heat sources)
%
%   Backward Euler (unconditionally stable, 1st-order accurate):
%
%       (C/dt + L) * T_{k+1} = (C/dt).*T_k + g_out*T_out,k + Q_k           (2)
%
%   The system matrix  M = C/dt + L  is CONSTANT, so it is factorised once
%   (decomposition, sparse LU) and every step is a cheap back-substitution.
%   This replaces the previous implementation, which re-assembled a dense
%   N x N matrix and called mldivide on every step.
%
%   Discretisation references:
%     - EN ISO 13790:2008 / EN ISO 52016-1:2017  (simple hourly / RC method)
%     - Bacher & Madsen (2011), "Identifying suitable models for the heat
%       dynamics of buildings", Energy and Buildings 43(7), 1511-1522.
%     - Michalak (2022), "Thermal Network Model of a Building...", Energies 15, 3709.
%
%   Backward-compatible public API (unchanged behaviour when no controller or
%   callback is attached):
%     run(totalSeconds)         - advance the whole horizon, fill obj.results
%     buildNodeMap()            - enumerate nodes and connections
%     plotResults()             - quick temperature plot
%
%   New capabilities for control-system studies:
%     obj.controlFcn            - handle f(sim) called BEFORE each physics step
%     obj.stepCallback          - handle f(sim,k,t,T) called AFTER each step
%     obj.act                   - struct actuator registry (set by controllers,
%                                 read by heat-source closures)
%     registerActuator(name,v0) / getActuator(name) / setActuator(name,v)
%     measure(zoneKey[,node])   - LIVE node temperature during a run
%     stepOnce(t,Tout,Q)        - advance exactly one step (external co-simulation)
%     getStateSpace()           - continuous ss() model for LQR / MPC design
%     solverMode                - "cached" (default) | "legacy" | "exact"
%
%   Units summary: temperature degC, capacitance J/K, conductance W/K, heat W,
%   time seconds (obj.timeStep is a duration).

    properties
        building                % RCBS.Building (parent)
        startDate  datetime     % simulation start
        timeStep   duration     % fixed step
        results                 % struct: Time, OutdoorTemperature, <Storey>.<Zone>.T ...
        t                       % current simulation datetime during a run

        % --- control / observation hooks (default [] => no-op) ---
        controlFcn   = []       % f(sim)          : called before each step
        stepCallback = []       % f(sim,k,t,Tvec) : called after each step
        act          = struct() % actuator registry (name -> value)

        solverMode   = "cached" % "cached" | "legacy" | "exact"
        warmStart    = false    % true => run()/buildLinear keep the current state
        k            = 0        % current step index during a run

        % --- live state (valid during and after a run) ---
        Tnow      = []          % N x 1 live node temperatures [degC]
        nodeNames = {}          % 1 x N cellstr, "Storey.Zone.Node"
    end

    properties (SetAccess = private)
        % structural maps, set by buildLinear(), readable by orchestrators
        zoneKeyList = {}        % 1 x nZ "Storey.Zone" keys (keys(zoneMain) order)
        zoneMainRow = []        % 1 x nZ global row of each zone main (air) node
        zoneStorey  = {}        % 1 x nZ storey names
        zoneName    = {}        % 1 x nZ zone names
    end

    properties (Access = private)
        Cvec        = []        % N x 1 [J/K]
        Lmat        = []        % N x N sparse [W/K] system matrix
        goutVec     = []        % N x 1 [W/K] outdoor coupling
        nInfo       = {}        % node info structs (from buildNodeMap)
        ngMap       = struct()  % name -> index maps (from buildNodeMap)
        decompM                 % cached factorisation of (C/dt + L)
        dtFactored  = NaN       % dt for which decompM is valid
        AdEx = []; BdEx = []    % exact ZOH discrete matrices (solverMode "exact")
        builtFor    = ''        % guards against stale linear system
        liveZone    = {}        % 1 x N cell of Zone handles (for fast state push)
        liveNodeIdx = []        % 1 x N node index within its Zone
        hsList      = struct('gidx',{},'hf',{},'isMain',{},'zoneKey',{},'zcol',{})  % flat heat-source list
        T0cap       = []        % captured initial temperatures (restart reference)
    end

    methods
        function obj = Simulation(building)
            obj.building  = building;
            obj.timeStep  = minutes(10);
            obj.startDate = datetime(2000,1,1);
            obj.act       = struct();
        end

        % ================================================================
        %  Linear-system assembly (called once, then cached)
        % ================================================================
        function buildLinear(obj)
            % BUILDLINEAR  Assemble the constant C, L and g_out from the network.
            [ng, ni] = obj.buildNodeMap();
            N = numel(ni);
            C = zeros(N,1);
            gout = zeros(N,1);
            nmax = N + sum(cellfun(@(s) numel(s.resList), ni));   % diag + off-diag upper bound
            rows = zeros(nmax,1); cols = zeros(nmax,1); vals = zeros(nmax,1);
            m = 0;
            for i = 1:N
                C(i) = ni{i}.C;
                for r = 1:numel(ni{i}.resList)
                    rr = ni{i}.resList{r};
                    G  = 1 / rr.R;                      % [W/K]
                    m = m + 1; rows(m) = i; cols(m) = i; vals(m) = G;   % diagonal
                    if strcmp(rr.toType, 'outdoor')
                        gout(i) = gout(i) + G;
                    else
                        m = m + 1; rows(m) = i; cols(m) = rr.toIndex; vals(m) = -G;
                    end
                end
            end
            rows = rows(1:m); cols = cols(1:m); vals = vals(1:m);
            obj.Cvec      = C;
            obj.Lmat      = sparse(rows, cols, vals, N, N);
            obj.goutVec   = gout;
            obj.nInfo     = ni;
            obj.ngMap     = ng;
            obj.nodeNames = cellfun(@(s) s.name, ni, 'UniformOutput', false);
            % Capture the initial temperatures ONCE, from the zone-node values as
            % they stood the first time the network was built. Because a run
            % writes live temperatures back into the zone nodes, re-reading them
            % here would make a second run() warm-start from the first run's end.
            % Capturing once keeps run() restart-reproducible; set warmStart=true
            % (or call resetState / setInitialTemps) to control this explicitly.
            if isempty(obj.T0cap) || numel(obj.T0cap) ~= N
                obj.T0cap = cellfun(@(s) s.T0, ni).';
            end
            if obj.warmStart && ~isempty(obj.Tnow) && numel(obj.Tnow) == N
                % keep obj.Tnow (continue from current state)
            else
                obj.Tnow = obj.T0cap;
            end
            obj.decompM   = [];
            obj.dtFactored = NaN;
            obj.AdEx = []; obj.BdEx = [];

            % --- precompute fast maps (avoid per-step string ops / dispatch) ---
            obj.liveZone    = cell(1, N);
            obj.liveNodeIdx = zeros(1, N);
            for i = 1:N
                p = split(obj.nodeNames{i}, '.');
                z = obj.building.(p{1}).(p{2});
                obj.liveZone{i}    = z;
                obj.liveNodeIdx(i) = find(strcmp({z.nodes.name}, p{3}), 1);
            end
            obj.zoneKeyList = keys(ng.zoneMain);
            nZ = numel(obj.zoneKeyList);
            obj.zoneMainRow = zeros(1, nZ);
            obj.zoneStorey  = cell(1, nZ);
            obj.zoneName    = cell(1, nZ);
            zcolMap = containers.Map(obj.zoneKeyList, num2cell(1:nZ));
            for qi = 1:nZ
                key = obj.zoneKeyList{qi}; p = split(key, '.');
                obj.zoneMainRow(qi) = ng.zoneMain(key);
                obj.zoneStorey{qi}  = p{1};
                obj.zoneName{qi}    = p{2};
            end

            obj.hsList = struct('gidx',{},'hf',{},'isMain',{},'zoneKey',{},'zcol',{});
            for s = 1:numel(obj.building.storeyList)
                sname = obj.building.storeyList{s};
                st    = obj.building.(sname);
                for zz = 1:numel(st.zoneList)
                    zname = st.zoneList{zz};
                    zone  = st.(zname);
                    zkey  = sprintf('%s.%s', sname, zname);
                    for hi = 1:numel(zone.heatSources)
                        hs = zone.heatSources(hi);
                        obj.hsList(end+1) = struct( ...                       %#ok<AGROW>
                            'gidx',    ng.fullName(sprintf('%s.%s', zkey, hs.nodeName)), ...
                            'hf',      hs.hf, ...
                            'isMain',  strcmp(hs.nodeName, 'T_main'), ...
                            'zoneKey', zkey, ...
                            'zcol',    zcolMap(zkey));
                    end
                end
            end
            obj.builtFor  = obj.networkSignature();
        end

        function factor(obj, dt)
            % FACTOR  Cache the factorisation of M = diag(C/dt) + L for step dt [s].
            if isempty(obj.Cvec) || ~strcmp(obj.builtFor, obj.networkSignature())
                obj.buildLinear();
            end
            N = numel(obj.Cvec);
            M = spdiags(obj.Cvec/dt, 0, N, N) + obj.Lmat;
            obj.decompM   = decomposition(M, 'lu');
            obj.dtFactored = dt;
            if obj.solverMode == "exact"
                Cinv  = spdiags(1./obj.Cvec, 0, N, N);
                Adyn  = full(-Cinv * obj.Lmat);                 % [1/s]
                Bdyn  = full(Cinv * [obj.goutVec, speye(N)]);   % inputs [Tout ; Q(1..N)]
                obj.AdEx = expm(Adyn*dt);
                obj.BdEx = Adyn \ (obj.AdEx - eye(N)) * Bdyn;   % ZOH input matrix
            end
        end

        % ================================================================
        %  Single implicit step  (external co-simulation entry point)
        % ================================================================
        function Tnew = stepOnce(obj, currentTime, Tout, Qsrc)
            % STEPONCE  Advance the network exactly one obj.timeStep.
            %   currentTime : datetime of the step start
            %   Tout        : outdoor boundary temperature [degC] (scalar)
            %   Qsrc        : external heat [W]. Either an N x 1 vector aligned
            %                 with obj.nodeNames, or a struct whose fields are
            %                 valid MATLAB names "Storey_Zone_Node" -> W, or a
            %                 containers.Map "Storey.Zone.Node" -> W. Missing
            %                 nodes get 0 W.
            dt = seconds(obj.timeStep);
            if isempty(obj.Cvec), obj.buildLinear(); end
            if isempty(obj.decompM) || obj.dtFactored ~= dt, obj.factor(dt); end
            N = numel(obj.Cvec);
            q = obj.resolveQ(Qsrc, N);

            switch string(obj.solverMode)
                case "cached"
                    rhs  = (obj.Cvec/dt).*obj.Tnow + obj.goutVec*Tout + q;
                    Tnew = obj.decompM \ rhs;
                case "legacy"
                    Tnew = obj.stepLegacyDense(dt, Tout, q);
                case "exact"
                    Tnew = obj.AdEx*obj.Tnow + obj.BdEx*[Tout; q];
                otherwise
                    error('RCBS:Simulation:solverMode', 'Unknown solverMode "%s".', obj.solverMode);
            end

            obj.Tnow = Tnew;
            obj.t    = currentTime;
            obj.pushLiveState();
        end

        % ================================================================
        %  Full-horizon run (backward compatible)
        % ================================================================
        function run(obj, totalSeconds)
            if isempty(obj.timeStep) || obj.timeStep <= 0
                error('Set a valid simulation.timeStep (duration).');
            end
            dt     = seconds(obj.timeStep);
            nsteps = floor(totalSeconds / dt);

            obj.buildLinear();       % sets obj.Tnow from the captured initial temps
            obj.factor(dt);
            N  = numel(obj.Cvec);
            nZ = numel(obj.zoneKeyList);

            hasCtl = ~isempty(obj.controlFcn);
            hasCb  = ~isempty(obj.stepCallback);

            % ---- preallocated buffers (filled in the loop, distributed after) ----
            Time    = obj.startDate + seconds((0:nsteps)' * dt);
            Toutv   = zeros(nsteps+1, 1);
            Tbuf    = zeros(N,  nsteps+1);     % column-contiguous node history
            TzoneM  = zeros(nsteps+1, nZ);
            HzoneM  = zeros(nsteps+1, nZ);

            % ---- initial conditions ----
            obj.k = 0;
            obj.t = obj.startDate;
            obj.pushLiveState();
            Toutv(1)     = obj.building.outdoorTempFunc(obj.t);
            Tbuf(:,1)    = obj.Tnow;
            TzoneM(1,:)  = obj.Tnow(obj.zoneMainRow).';

            % ---- main loop ----
            for kk = 1:nsteps
                currentTime = obj.startDate + seconds((kk-1)*dt);
                obj.k = kk;
                obj.t = currentTime;

                if hasCtl, obj.controlFcn(obj); end

                Tout        = obj.building.outdoorTempFunc(currentTime);
                [q, zheat]  = obj.evalHeatSources(N);

                obj.stepOnce(currentTime + seconds(dt), Tout, q);

                Toutv(kk+1)    = Tout;
                Tbuf(:,kk+1)   = obj.Tnow;
                TzoneM(kk+1,:) = obj.Tnow(obj.zoneMainRow).';
                HzoneM(kk+1,:) = zheat.';

                if hasCb
                    obj.stepCallback(obj, kk, currentTime + seconds(dt), obj.Tnow);
                end
            end

            % ---- assemble results struct (shape preserved from the original) ----
            res = struct();
            res.Time               = Time;
            res.OutdoorTemperature = Toutv;
            for qi = 1:nZ
                res.(obj.zoneStorey{qi}).(obj.zoneName{qi}).T         = TzoneM(:,qi);
                res.(obj.zoneStorey{qi}).(obj.zoneName{qi}).heatInput = HzoneM(:,qi);
            end
            res.time      = Time;                     % convenience alias
            res.nodeNames = obj.nodeNames;
            res.Tall      = Tbuf.';                   % (nsteps+1) x N
            obj.results   = res;
        end

        % ================================================================
        %  Measurement / actuator helpers (for controllers)
        % ================================================================
        function T = measure(obj, zoneKey, nodeName)
            % MEASURE  Live temperature [degC] of "Storey.Zone" main node, or a
            %          specific node if nodeName is given.
            if nargin < 3 || isempty(nodeName)
                if isKey(obj.ngMap.zoneMain, zoneKey)
                    T = obj.Tnow(obj.ngMap.zoneMain(zoneKey)); return
                end
                nodeName = 'T_main';
            end
            full = sprintf('%s.%s', zoneKey, nodeName);
            T = obj.Tnow(obj.ngMap.fullName(full));
        end

        function resetState(obj)
            % RESETSTATE  Restore node temperatures to the captured initial
            %   condition (the values present when the network was first built).
            if isempty(obj.T0cap), obj.buildLinear(); end
            obj.Tnow = obj.T0cap;
            obj.k = 0;
            if ~isempty(obj.liveZone), obj.pushLiveState(); end
        end

        function setInitialTemps(obj, T)
            % SETINITIALTEMPS  Set a new initial condition [degC].
            %   T : scalar (applied to every node) or N x 1 vector aligned with
            %       obj.nodeNames. Also becomes the restart reference for run().
            if isempty(obj.Cvec), obj.buildLinear(); end
            N = numel(obj.Cvec);
            if isscalar(T), T = repmat(T, N, 1); end
            obj.T0cap = T(:);
            obj.Tnow  = T(:);
            obj.pushLiveState();
        end

        function registerActuator(obj, name, v0)
            % REGISTERACTUATOR  Declare an actuator channel with initial value v0.
            if nargin < 3, v0 = 0; end
            obj.act.(name) = v0;
        end
        function v = getActuator(obj, name)
            v = obj.act.(name);
        end
        function setActuator(obj, name, v)
            obj.act.(name) = v;
        end

        % ================================================================
        %  Continuous state-space model  (for LQR / MPC controller design)
        % ================================================================
        function [sysc, io] = getStateSpace(obj)
            % GETSTATESPACE  Continuous ss() model of the building network.
            %   States  : node temperatures [degC], order = obj.nodeNames
            %   Inputs  : u = [ T_outdoor ; Q_node_1 ; ... ; Q_node_N ]  ([degC], [W])
            %   Outputs : y = all node temperatures [degC]
            %   dx/dt = A x + B u ,  A = -diag(1/C)*L ,  B = diag(1/C)*[g_out, I]
            if isempty(obj.Cvec) || ~strcmp(obj.builtFor, obj.networkSignature())
                obj.buildLinear();
            end
            N    = numel(obj.Cvec);
            Cinv = diag(1./obj.Cvec);
            A    = -Cinv * full(obj.Lmat);
            B    =  Cinv * [obj.goutVec, eye(N)];
            Cy   = eye(N);
            D    = zeros(N, N+1);
            sysc = ss(A, B, Cy, D);
            io.stateNames = obj.nodeNames;
            io.inputNames = [{'T_outdoor'}, cellfun(@(s) ['Q_' s], obj.nodeNames, 'UniformOutput', false)];
            io.outputNames = obj.nodeNames;
            io.zoneMainRows = cell2mat(values(obj.ngMap.zoneMain));
        end

        % ================================================================
        %  Node map (unchanged from the original implementation)
        % ================================================================
        function [nodeGlobalMap, nodesInfo] = buildNodeMap(obj)
            nodesInfo = {};
            nodeGlobalMap = struct();
            nodeGlobalMap.zoneMain = containers.Map();
            nodeGlobalMap.zoneObj  = containers.Map();
            nodeGlobalMap.fullName = containers.Map();

            idx = 1;
            for s = 1:numel(obj.building.storeyList)
                sname  = obj.building.storeyList{s};
                storey = obj.building.(sname);
                for z = 1:numel(storey.zoneList)
                    zname = storey.zoneList{z};
                    zone  = storey.(zname);
                    for n = 1:zone.getNodeCount()
                        nd = zone.nodes(n);
                        if nd.C > 0
                            fullName = sprintf('%s.%s.%s', sname, zname, nd.name);
                            info.name = fullName;
                            info.C    = nd.C;
                            info.T0   = nd.T;
                            info.resList = {};
                            nodesInfo{idx} = info; %#ok<AGROW>
                            nodeGlobalMap.fullName(fullName) = idx;
                            if nd.isMain
                                zoneKey = sprintf('%s.%s', sname, zname);
                                nodeGlobalMap.zoneMain(zoneKey) = idx;
                                nodeGlobalMap.zoneObj(zoneKey)  = zone;
                            end
                            idx = idx + 1;
                        end
                    end
                end
            end

            for s = 1:numel(obj.building.storeyList)
                sname  = obj.building.storeyList{s};
                storey = obj.building.(sname);
                for z = 1:numel(storey.zoneList)
                    zname = storey.zoneList{z};
                    zone  = storey.(zname);
                    for r = 1:numel(zone.resistors)
                        res = zone.resistors(r);
                        n1_name = zone.nodes(res.n1).name;
                        n1_full = sprintf('%s.%s.%s', sname, zname, n1_name);
                        g1 = nodeGlobalMap.fullName(n1_full);
                        if ischar(res.n2) && strcmp(res.n2, 'outdoor')
                            nodesInfo{g1}.resList{end+1} = struct('R', res.R, 'toType', 'outdoor', 'toIndex', []);
                        else
                            n2_name = zone.nodes(res.n2).name;
                            n2_full = sprintf('%s.%s.%s', sname, zname, n2_name);
                            g2 = nodeGlobalMap.fullName(n2_full);
                            nodesInfo{g1}.resList{end+1} = struct('R', res.R, 'toType', 'local', 'toIndex', g2);
                            nodesInfo{g2}.resList{end+1} = struct('R', res.R, 'toType', 'local', 'toIndex', g1);
                        end
                    end
                    if isprop(zone, 'crossRes')
                        for r = 1:numel(zone.crossRes)
                            res = zone.crossRes{r};
                            if res.n1.zone == zone
                                % resolve each endpoint by its actual node (idx 1 =
                                % air; a higher idx = a partition/slab mid node)
                                n1nm = res.n1.zone.nodes(res.n1.idx).name;
                                n2nm = res.n2.zone.nodes(res.n2.idx).name;
                                g1 = nodeGlobalMap.fullName(sprintf('%s.%s.%s', ...
                                        res.n1.zone.storey.name, res.n1.zone.name, n1nm));
                                g2 = nodeGlobalMap.fullName(sprintf('%s.%s.%s', ...
                                        res.n2.zone.storey.name, res.n2.zone.name, n2nm));
                                nodesInfo{g1}.resList{end+1} = struct('R', res.R, 'toType', 'cross', 'toIndex', g2);
                                nodesInfo{g2}.resList{end+1} = struct('R', res.R, 'toType', 'cross', 'toIndex', g1);
                            end
                        end
                    end
                end
            end
        end

        function plotResults(obj)
            res   = obj.results;
            times = res.Time;
            figure; hold on;
            legendEntries = {};
            storeyNames = fieldnames(res);
            storeyNames = setdiff(storeyNames, {'Time','time','OutdoorTemperature','nodeNames','Tall'});
            for s = 1:numel(storeyNames)
                sname = storeyNames{s};
                if ~isstruct(res.(sname)), continue; end
                zoneNames = fieldnames(res.(sname));
                for z = 1:numel(zoneNames)
                    zname = zoneNames{z};
                    plot(times, res.(sname).(zname).T);
                    legendEntries{end+1} = sprintf('%s.%s', sname, zname); %#ok<AGROW>
                end
            end
            if isfield(res,'OutdoorTemperature')
                plot(times, res.OutdoorTemperature, '--k', 'LineWidth', 1.5);
                legendEntries{end+1} = 'OutdoorTemperature';
            end
            xlabel('Time'); ylabel('Temperature (\circC)');
            title('Simulation Temperatures');
            legend(legendEntries, 'Interpreter', 'none', 'Location', 'best');
            grid on; hold off;
        end
    end

    % ====================================================================
    %  Private helpers
    % ====================================================================
    methods (Access = private)
        function sig = networkSignature(obj)
            % Cheap structural signature so a rebuilt building invalidates caches.
            n = 0; nres = 0;
            for s = 1:numel(obj.building.storeyList)
                st = obj.building.(obj.building.storeyList{s});
                for z = 1:numel(st.zoneList)
                    zo = st.(st.zoneList{z});
                    n = n + numel(zo.nodes);
                    nres = nres + numel(zo.resistors) + numel(zo.crossRes);
                end
            end
            sig = sprintf('%d|%d|%d', numel(obj.building.storeyList), n, nres);
        end

        function pushLiveState(obj)
            % Write obj.Tnow back into the Zone node structs so getMainTemp() /
            % getNodeTemp() / heat-source closures see the CURRENT temperature.
            % Uses precomputed handle + index maps (no string ops per step).
            for i = 1:numel(obj.Tnow)
                obj.liveZone{i}.nodes(obj.liveNodeIdx(i)).T = obj.Tnow(i);
            end
        end

        function [q, zheat] = evalHeatSources(obj, N)
            % Evaluate every registered heat-source closure at the current time.
            %   q     : N x 1  external heat per node [W]
            %   zheat : nZ x 1 total heat delivered to each zone's main node [W]
            q     = zeros(N, 1);
            zheat = zeros(numel(obj.zoneKeyList), 1);
            for i = 1:numel(obj.hsList)
                hs = obj.hsList(i);
                Qw = hs.hf(obj.building);
                q(hs.gidx) = q(hs.gidx) + Qw;
                if hs.isMain
                    zheat(hs.zcol) = zheat(hs.zcol) + Qw;
                end
            end
        end

        function q = resolveQ(obj, Qsrc, N)
            if isempty(Qsrc)
                q = zeros(N,1);
            elseif isnumeric(Qsrc)
                q = Qsrc(:);
                if numel(q) ~= N
                    error('RCBS:Simulation:Qsize', 'Qsrc has %d entries, expected %d.', numel(q), N);
                end
            elseif isa(Qsrc, 'containers.Map')
                q = zeros(N,1);
                kk = keys(Qsrc);
                for i = 1:numel(kk)
                    q(obj.ngMap.fullName(kk{i})) = Qsrc(kk{i});
                end
            elseif isstruct(Qsrc)
                q = zeros(N,1);
                fn = fieldnames(Qsrc);
                for i = 1:numel(fn)
                    key = strrep(fn{i}, '_', '.');
                    q(obj.ngMap.fullName(key)) = Qsrc.(fn{i});
                end
            else
                error('RCBS:Simulation:Qtype', 'Unsupported Qsrc type "%s".', class(Qsrc));
            end
        end

        function Tnew = stepLegacyDense(obj, dt, Tout, q)
            % Faithful re-implementation of the ORIGINAL per-step dense assembly,
            % kept as a validation oracle (solverMode = "legacy").
            N = numel(obj.Cvec);
            A = zeros(N); b = zeros(N,1);
            for i = 1:N
                A(i,i) = obj.Cvec(i)/dt;
                b(i)   = (obj.Cvec(i)/dt)*obj.Tnow(i) + q(i);
                for r = 1:numel(obj.nInfo{i}.resList)
                    rr = obj.nInfo{i}.resList{r};
                    G  = 1/rr.R;
                    if strcmp(rr.toType, 'outdoor')
                        A(i,i) = A(i,i) + G;
                        b(i)   = b(i)   + G*Tout;
                    else
                        A(i,i)         = A(i,i) + G;
                        A(i,rr.toIndex) = A(i,rr.toIndex) - G;
                    end
                end
            end
            Tnew = A \ b;
        end
    end
end
