classdef Zone < dynamicprops & handle
    % Every wall, roof, window and internal mass added to a zone is reachable by its name,
    % and the air node as Air: zone.Wall.R, zone.Wall.C, zone.Wall.T (see RCBS.Part).
    properties
        name
        building % parent building
        storey   % parent storey
        crossRes
        
        % Node list: struct array with fields: name, C, T, isMain (logical)
        nodes = struct('name',{}, 'C',{}, 'T',{}, 'isMain', {});
        % Resistors: struct array with fields: n1 (index), n2 (index or 'outdoor'), R, name
        resistors = struct('n1',{}, 'n2',{}, 'R',{}, 'name',{});
        
        % heat source functions: cell of function handles hf(building) -> W
        heatSources = struct('hf',{}, 'nodeName',{});
        
        % defaults (modifiable)
        C_main = 1e5; % J/K default main capacitance
        R_default = 5e-3; % K/W default resistor
    end
    properties (SetAccess = private)
        version = 0   % raised whenever a resistance or capacitance changes (a running simulation rebuilds)
    end
    
    methods
        function obj = Zone(name, building, storey)
            obj.name = name;
            obj.building = building;
            obj.storey = storey;
            obj.crossRes = {};
            % create main node
            obj.nodes(1).name = 'T_main';
            obj.nodes(1).C = obj.C_main;
            obj.nodes(1).T = 20; % default initial temp
            obj.nodes(1).isMain = true;
            obj.addPart('Air', 'T_main');
        end

        function touch(obj)
            % TOUCH  Record that a parameter of this zone changed (used by RCBS.Part).
            obj.version = obj.version + 1;
        end
        
        function set.C_main(obj, val)
            % SET.C_MAIN  Keep the main (air) node capacitance in sync with C_main.
            %   Fixes the long-standing bug where addZone(name,'C_main',val) or a
            %   later  z.C_main = val  assignment did NOT update nodes(1).C, so
            %   every zone silently kept the 1e5 J/K default.
            %   Units: val in J/K.
            obj.C_main = val;
            if ~isempty(obj.nodes)
                obj.nodes(1).C = val;
                obj.version = obj.version + 1;
            end
        end

        function addPart(obj, name, key)
            % ADDPART  Make the element reachable as zone.<name> (skipped if the name is not a
            %   valid identifier or is already taken).
            if nargin < 3, key = name; end
            if ~isvarname(name) || isprop(obj, name), return, end
            p = addprop(obj, name);
            obj.(name) = RCBS.Part(obj, key);
            p.SetAccess = 'private';
        end

        function setAir(obj, C_air, T0)
            % SETAIR  Set the main (indoor-air) node capacitance and initial temp.
            %   setAir(C_air)         C_air [J/K]
            %   setAir(C_air, T0)     T0    [degC] initial air temperature
            obj.nodes(1).C = C_air;
            obj.C_main     = C_air;
            obj.version    = obj.version + 1;
            if nargin > 2 && ~isempty(T0)
                obj.nodes(1).T = T0;
            end
        end

        function T = getNodeTemp(obj, nodeName)
            % GETNODETEMP  Current temperature [degC] of a named node in this zone.
            %   During a run this reflects the LIVE state (Simulation writes it back
            %   every step); outside a run it is the last stored / initial value.
            k = find(strcmp({obj.nodes.name}, nodeName), 1);
            if isempty(k)
                error('Zone:getNodeTemp:noNode', 'Node "%s" not in zone "%s".', nodeName, obj.name);
            end
            T = obj.nodes(k).T;
        end

        function setNodeTemp(obj, nodeName, T)
            % SETNODETEMP  Write a node temperature [degC]. Used by Simulation to
            %   push live state so heat-source closures / controllers can read it.
            k = find(strcmp({obj.nodes.name}, nodeName), 1);
            if isempty(k)
                error('Zone:setNodeTemp:noNode', 'Node "%s" not in zone "%s".', nodeName, obj.name);
            end
            obj.nodes(k).T = T;
        end

        function idx = addNode(obj, nodename, C, T0)
            if nargin<4 || isempty(T0), T0 = obj.nodes(1).T; end
            nd.name = nodename;
            nd.C = C;
            nd.T = T0;
            nd.isMain = false;
            obj.nodes(end+1) = nd;
            idx = numel(obj.nodes);
        end
        
        function addWall(obj, R_wall, C_wall, T0, name)
            % Corrected T-Network Model: R_wall is the TOTAL resistance,
            % so we split it into two halves for the model.
            if nargin<5, name = sprintf('Wall%d', sum(strncmp({obj.nodes.name},'Wall',4))+1); end
            idx = obj.addNode(sprintf('%s', name), C_wall, T0);
            % resistor main <-> wall (uses R/2)
            obj.resistors(end+1) = struct('n1', 1, 'n2', idx, 'R', R_wall/2, 'name', [name '_m']);
            % resistor wall <-> outdoor (uses R/2)
            obj.resistors(end+1) = struct('n1', idx, 'n2', 'outdoor', 'R', R_wall/2, 'name', [name '_o']);
            obj.addPart(name);
        end
        
        function addRoof(obj, R_roof, C_roof, T0, name)
            % Corrected T-Network Model for roofs as well
            if nargin<5, name = sprintf('Roof%d', sum(strncmp({obj.nodes.name},'Roof',4))+1); end
            idx = obj.addNode(name, C_roof, T0);
            obj.resistors(end+1) = struct('n1', 1, 'n2', idx, 'R', R_roof/2, 'name', [name '_m']);
            obj.resistors(end+1) = struct('n1', idx, 'n2', 'outdoor', 'R', R_roof/2, 'name', [name '_o']);
            obj.addPart(name);
        end
        
        function addWindow(obj, R_window, varargin)
            % ADDWINDOW  A window or vent: by default a single resistance from the zone air to
            %   the outdoor boundary, with no state.
            %     addWindow(R)  addWindow(R, name)
            %   Give a heat capacity as well and it becomes a 2R1C element like a wall or a roof:
            %   one node joined to the air and to the outdoor by R/2 each, R the total.
            %     addWindow(R, C)  addWindow(R, C, T0)  addWindow(R, C, T0, name)
            %   R [K/W], C [J/K], T0 [degC] initial temperature ([] for the air value).
            C = [];  T0 = [];  name = '';
            if ~isempty(varargin) && (ischar(varargin{1}) || isstring(varargin{1}))
                name = char(varargin{1});
            elseif ~isempty(varargin)
                C = varargin{1};
                if numel(varargin) >= 2, T0 = varargin{2}; end
                if numel(varargin) >= 3, name = char(varargin{3}); end
            end
            if isempty(name)
                base = unique(regexprep({obj.resistors.name}, '_[mo]$', ''));
                name = sprintf('Window%d', sum(strncmp(base, 'Window', 6)) + 1);
            end
            if isempty(C)
                % a direct resistor from the main node to the outdoor
                obj.resistors(end+1) = struct('n1', 1, 'n2', 'outdoor', 'R', R_window, 'name', name);
            else
                idx = obj.addNode(name, C, T0);
                obj.resistors(end+1) = struct('n1', 1, 'n2', idx, 'R', R_window/2, 'name', [name '_m']);
                obj.resistors(end+1) = struct('n1', idx, 'n2', 'outdoor', 'R', R_window/2, 'name', [name '_o']);
            end
            obj.addPart(name);
        end

        function addInternalMass(obj, R_int, C_int, T0, name)
            if nargin<5, name = sprintf('IntMass%d', sum(strncmp({obj.nodes.name},'Int',3))+1); end
            idx = obj.addNode(name, C_int, T0);
            obj.resistors(end+1) = struct('n1', 1, 'n2', idx, 'R', R_int, 'name', [name '_m']);
            obj.addPart(name);
        end
        
        function connectToZone(obj, otherZone, R_between, name, C_mid, T0, kind)
            % CONNECTTOZONE  Couple this zone's air node to another zone's air node.
            %
            %   connectToZone(other, R, name)
            %       a plain conductance G = 1/R between the two zone air nodes
            %       (a lightweight air path / open doorway).
            %
            %   connectToZone(other, R_total, name, C_mid, T0)
            %       a capacitive T-network  R_total/2 - C_mid - R_total/2  between
            %       the two zone air nodes: an interior PARTITION WALL (same
            %       storey) or a FLOOR/CEILING SLAB (this zone's ceiling = the
            %       other zone's floor). The mid node (thermal mass of the
            %       partition / deck) is created inside THIS zone; T0 is its
            %       initial temperature (default = this zone's air temperature).
            %
            %   connectToZone(other, R_total, name, C_mid, T0, kind)
            %       KIND is a drawing hint only ('wall' | 'slab' | 'air'); it does
            %       not change the physics.  It tells RCBS.Building.visualize how
            %       to route the coupling: 'wall' - between the facing side edges,
            %       'slab' - between the lower ceiling and the upper floor edges,
            %       'air' - straight between the air nodes.  Default: 'wall' for a
            %       capacitive coupling, 'air' for a plain one.
            %
            %   R_total [K/W], C_mid [J/K]. The connection is registered on both
            %   zones; RCBS.Simulation resolves it once.
            if nargin < 4 || isempty(name), name = sprintf('%s_to_%s', obj.name, otherZone.name); end
            isCap = nargin >= 5 && ~isempty(C_mid) && C_mid > 0;
            if nargin < 7 || isempty(kind)
                if isCap, kind = 'wall'; else, kind = 'air'; end
            end

            if isCap
                if nargin < 6 || isempty(T0), T0 = obj.nodes(1).T; end
                idxMid = obj.addNode([name '_c'], C_mid, T0);
                % this-zone air  <->  mid node   (R/2, a normal in-zone resistor)
                obj.resistors(end+1) = struct('n1', 1, 'n2', idxMid, 'R', R_between/2, 'name', [name '_a']);
                % mid node  <->  other-zone air  (R/2, a cross-zone resistor)
                r = struct('n1', struct('zone', obj,       'idx', idxMid), ...
                           'n2', struct('zone', otherZone, 'idx', 1), ...
                           'R', R_between/2, 'name', [name '_b'], 'kind', kind);
            else
                r = struct('n1', struct('zone', obj,       'idx', 1), ...
                           'n2', struct('zone', otherZone, 'idx', 1), ...
                           'R', R_between, 'name', name, 'kind', kind);
            end

            obj.crossRes{end+1} = r;
            otherZone.crossRes{end+1} = r;
        end
        
        function connectToExternalSource(obj, hf, nodeName)
            % connectToExternalSource(hf, 'NodeName')
            % hf is function handle: hf(building) -> heat in Watts
            % nodeName is the name of the target node (e.g., 'T_main', 'IntMass1')
            
            % Default to the main node if no name is provided
            if nargin < 3, nodeName = 'T_main'; end
            
            % Check if the node exists in this zone
            if ~ismember(nodeName, {obj.nodes.name})
                error('Node "%s" does not exist in Zone "%s".', nodeName, obj.name);
            end

            obj.heatSources(end+1) = struct('hf', hf, 'nodeName', nodeName);
        end
        
        function T = getMainTemp(obj)
            T = obj.nodes(1).T;
        end
        
        function nodeCount = getNodeCount(obj)
            nodeCount = numel(obj.nodes);
        end
    end
end