classdef Building < dynamicprops & handle
    properties
        simulation  % RCBS.Simulation object
        outdoorTempFunc % function handle: datetime -> temperature (degC)
        storeyList = {} % names
    end
    
    methods
        function obj = Building()
            obj.simulation = RCBS.Simulation(obj);
            obj.outdoorTempFunc = @(t) 10; % default constant 10°C
        end
        
        function addStorey(obj, name)
            if isprop(obj, name)
                error('Storey "%s" already exists.', name);
            end
            p = addprop(obj, name);
            obj.(name) = RCBS.Storey(name, obj);
            obj.storeyList{end+1} = name;
        end
        
        function simulate(obj, varargin)
            % B.simulate(duration)
            % or B.simulate(years, months, days, hours, minutes)
            %
            % Example:
            %   B.simulate(hours(5))
            %   B.simulate(0,0,1,0,0)  % 1 day
            
            % --- Case 1: duration input (preferred)
            if numel(varargin) == 1 && isa(varargin{1}, 'duration')
                simDuration = varargin{1};
                
            % --- Case 2: numeric [y,m,d,h,min] input
            elseif numel(varargin) == 5
                [y,m,d,h,minu] = deal(varargin{:});
                simDuration = years(y) + calmonths(m) + days(d) + hours(h) + minutes(minu);
                
            else
                error('Usage: B.simulate(duration) or B.simulate(y,m,d,h,min)');
            end
            
            % --- Validation
            if isempty(obj.simulation.startDate)
                error('Set B.simulation.startDate before calling simulate().');
            end
            if isempty(obj.simulation.timeStep) || obj.simulation.timeStep <= seconds(0)
                error('Set B.simulation.timeStep (duration) before calling simulate().');
            end
            
            % --- Compute total duration in seconds (approx for months/years)
            % Convert to seconds (1 year ≈ 365.25 days)
            dt_seconds = seconds(obj.simulation.timeStep);
            endDate = obj.simulation.startDate + simDuration;
            totalSeconds = seconds(endDate - obj.simulation.startDate);
            
            % --- Run the simulation
            obj.simulation.run(totalSeconds);
        end

        function visualize(obj, varargin)
            %VISUALIZE  Draw the building's RC network as a labelled schematic.
            %
            %   B.visualize()          new figure
            %   B.visualize(ax)        draw into an existing axes
            %
            %   Every zone uses the SAME fixed-size template.  A thin shell
            %   frames the room; the RC ladders rise from the room edges:
            %
            %          (T_outdoor)                     one per exterior element
            %              |
            %            [ R ]                         outer half
            %          -- * --||-- C   T_wall          node in the wall, cap aside
            %            [ R ]                         inner half
            %       +======|=================+  <- thin shell / room border
            %       |  ||   |                |
            %       |  C -[R]- * T_main      |  <- internal mass on the left,
            %       |          (zone)        |     one R to the air node
            %       +======|=================+
            %          [ window ]                <- node in the pane, pane height
            %              |                        = wall-border thickness
            %            [ R ]
            %              |
            %          (T_outdoor)
            %
            %   Missing parts are left out, the slots stay.  Inter-zone links
            %   attach at the shell EDGES (grey while inside a card): a single
            %   resistor for a plain air path, R/2 - node+C - R/2 for a
            %   capacitive partition wall or floor/ceiling slab.

            haveAx = ~isempty(varargin) && isa(varargin{1}, 'matlab.graphics.axis.Axes');
            if haveAx, ax = varargin{1};  f = ancestor(ax, 'figure'); end

            C_WIRE = [0 0 0];        C_GREY = [0.62 0.62 0.62];   C_NODE = [0.12 0.12 0.12];
            C_OUT  = [0.15 0.55 0.9];   C_WIN = [0.20 0.58 0.95];
            C_HEAT = [0.90 0.45 0.10];  C_ZONE = [0.78 0 0];
            C_SHELL_F = [0.965 0.965 0.965];  C_SHELL_E = [0.78 0.78 0.78];
            FS = 8;
            lbl = {'FontSize', FS, 'Interpreter', 'tex', 'Margin', 0.5, ...
                   'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'Clipping', 'off'};

            % ---------- collect + classify ----------
            nS = numel(obj.storeyList);
            zc = cell(nS,1);  cls = cell(nS,1);
            for s = 1:nS
                st = obj.(obj.storeyList{s});
                zc{s} = st.zoneList;
                cls{s} = cellfun(@(zn) classify(st.(zn)), st.zoneList, 'UniformOutput', false);
            end
            zCount = cellfun(@numel, zc);
            maxZ = max([zCount(:); 1]);   nZtot = sum(zCount);
            allc = [cls{:}];
            nEnv = max([cellfun(@(c) numel(c.envN), allc), 1]);
            nWin = max([cellfun(@(c) numel(c.winR), allc), 1]);
            nIm  = max([cellfun(@(c) numel(c.imN),  allc), 0]);
            nGen = max([cellfun(@(c) numel(c.genN), allc), 0]);

            % ---------- fixed template geometry ----------
            wb = 2.2;                                        % shell / room border ("wall thickness")
            RW = max(9.5, 3.2*max(nEnv, nWin) + 2.4);        % room width
            RH = max(5.6, 2.1*max([nIm, nGen, 1]) + 3.4);    % room height
            TB = 4.4;   BB = 4.0;   SM = 5.4;                % bands above/below the shell + side margin
            CW = RW + 2*SM;   CH = TB + RH + 2*wb + BB;
            GX = 5.6;   GY = 6.6;
            PX = CW + GX;   PY = CH + GY;

            if ~haveAx
                f = figure('Name', 'RCBS building schematic', 'NumberTitle', 'off', 'Color', 'w');
                ax = axes(f);
            end
            hold(ax, 'on');  set(ax, 'Clipping', 'off');

            % ---------- anchors ----------
            A = containers.Map('KeyType', 'char', 'ValueType', 'any');
            for s = 1:nS
                nZ = zCount(s);
                for k = 1:nZ
                    x0 = (k-1)*PX + (maxZ - nZ)*PX/2;
                    y0 = (s-1)*PY;
                    room  = [x0 + SM, y0 + BB + wb, RW, RH];
                    shell = [room(1)-wb, room(2)-wb, room(3)+2*wb, room(4)+2*wb];
                    A(sprintf('%s.%s', obj.storeyList{s}, zc{s}{k})) = struct( ...
                        'x0', x0, 'y0', y0, 'room', room, 'shell', shell, ...
                        'air', [room(1)+room(3)/2, room(2)+room(4)/2]);
                end
                text(ax, -0.85*GX, (s-1)*PY + CH/2, obj.storeyList{s}, 'Rotation', 90, ...
                    lbl{:}, 'FontWeight', 'bold', 'FontSize', FS+3, 'Color', [0.4 0.4 0.4]);
            end

            for s = 1:nS
                for k = 1:zCount(s)
                    key = sprintf('%s.%s', obj.storeyList{s}, zc{s}{k});
                    drawCard(obj.(obj.storeyList{s}).(zc{s}{k}), cls{s}{k}, A(key));
                end
            end

            seen = strings(0,1);
            for s = 1:nS
                for k = 1:zCount(s)
                    z = obj.(obj.storeyList{s}).(zc{s}{k});
                    for c = 1:numel(z.crossRes)
                        r = z.crossRes{c};
                        base = regexprep(r.name, '_[ab]$', '');
                        if any(seen == string(base)) || ~isEndpointZone(r.n1, z), continue; end
                        drawCross(r, base);
                        seen(end+1) = string(base); %#ok<AGROW>
                    end
                end
            end

            drawLegend();
            hold(ax, 'off');  axis(ax, 'off');  daspect(ax, [1 1 1]);
            title(ax, sprintf('RC schematic  \\bullet  %d storey(s),  %d zone(s)', nS, nZtot), ...
                'FontSize', FS+3, 'FontWeight', 'bold');

            drawnow;
            [bx, by] = contentBounds(ax);
            mrg = 0.012*max(bx(2)-bx(1), by(2)-by(1)) + 0.8;
            xlim(ax, [bx(1)-mrg, bx(2)+mrg]);  ylim(ax, [by(1)-mrg, by(2)+mrg]);
            if ~haveAx
                dx = diff(xlim(ax));  dy = diff(ylim(ax));  scr = get(0, 'ScreenSize');
                ppu  = 20;
                figW = min(scr(3)*0.94, max(720, ppu*dx));
                figH = min(scr(4)*0.86, max(420, ppu*dy));
                set(f, 'Position', [40, 60, round(figW), round(figH)]);
                set(ax, 'Position', [0.015 0.015 0.97 0.93]);
            end

            % ================= classification =================
            function c = classify(z)
                R = z.resistors;  N = z.nodes;  nN = numel(N);
                isOut = @(r) ischar(r.n2) && strcmp(r.n2, 'outdoor');
                tch = @(r,i) isequal(r.n1,i) || isequal(r.n2,i);
                c = struct('envN',[], 'envRi',[], 'envRo',[], 'envRoof',[], 'winR',[], ...
                           'imN',[], 'imRi',[], 'midN',[], 'genN',[], 'genRi',[]);
                for i = 2:nN
                    ri = find(arrayfun(@(r) ~isOut(r) && tch(r,i) && (isequal(r.n1,1)||isequal(r.n2,1)), R), 1);
                    ro = find(arrayfun(@(r) isOut(r) && isequal(r.n1,i), R), 1);
                    if ~isempty(ri) && ~isempty(ro)
                        c.envN(end+1) = i;  c.envRi(end+1) = ri;  c.envRo(end+1) = ro;
                        c.envRoof(end+1) = contains(lower(N(i).name), 'roof');
                    elseif endsWith(string(N(i).name), "_c")
                        c.midN(end+1) = i;
                    elseif ~isempty(ri)
                        c.imN(end+1) = i;  c.imRi(end+1) = ri;
                    else
                        rg = find(arrayfun(@(r) tch(r,i), R), 1);
                        c.genN(end+1) = i;  c.genRi(end+1) = z0(rg);
                    end
                end
                c.winR = find(arrayfun(@(r) isOut(r) && isequal(r.n1,1), R));
            end
            function v = z0(x), if isempty(x), v = 0; else, v = x; end, end

            % ================= one zone card =================
            function drawCard(z, c, a)
                x0 = a.x0;  sh = a.shell;  rb = a.room;
                cx = a.air(1);  cy = a.air(2);
                rL = rb(1);  rR = rb(1)+rb(3);  rT = rb(2)+rb(4);  rBo = rb(2);
                shT = sh(2)+sh(4);   shBo = sh(2);
                pos = containers.Map('KeyType','char','ValueType','any');

                rectangle(ax, 'Position', sh, 'FaceColor', C_SHELL_F, 'EdgeColor', C_SHELL_E, 'LineWidth', 1);
                rectangle(ax, 'Position', rb, 'FaceColor', 'w', 'EdgeColor', C_WIRE, 'LineWidth', 1.6);

                % central spine  (window - air node - wall/roof)
                busT = rT - 1.6;   busB = rBo + 1.4;
                wire([cx, busB], [cx, busT]);
                dot([cx, cy]);  pos('T_main') = [cx, cy];
                text(ax, cx + 0.8, cy + 0.5,  'T_{main}', lbl{:}, 'FontSize', FS-0.5, 'HorizontalAlignment', 'left');
                text(ax, cx + 0.8, cy - 0.1,  ['\bf' tex(z.name)], lbl{:}, 'Color', C_ZONE, ...
                    'FontSize', FS+1, 'HorizontalAlignment', 'left');
                text(ax, cx + 0.8, cy - 0.7,  ['C=' fmt(z.nodes(1).C)], lbl{:}, 'FontSize', FS-1.5, ...
                    'Color', [0.45 0.45 0.45], 'HorizontalAlignment', 'left');

                % ----- exterior elements: node in the MIDDLE of the border, one
                %       resistor crossing the inner edge, one the outer edge -----
                envRoofs = c.envN(logical(c.envRoof));   envWalls = c.envN(~logical(c.envRoof));
                roofRi = c.envRi(logical(c.envRoof));    roofRo = c.envRo(logical(c.envRoof));
                wallRi = c.envRi(~logical(c.envRoof));   wallRo = c.envRo(~logical(c.envRoof));
                hasRoof = ~isempty(envRoofs);
                bias = crossSideBias(z, a);

                % roofs (and walls when there is no roof): on the top border
                if hasRoof
                    topN = envRoofs;  topRi = roofRi;  topRo = roofRo;
                else
                    topN = envWalls;  topRi = wallRi;  topRo = wallRo;
                end
                nt = numel(topN);
                for j = 1:nt
                    nd = z.nodes(topN(j));  Ri = z.resistors(topRi(j)).R;  Ro = z.resistors(topRo(j)).R;
                    if nt == 1, lx = cx;
                    else,       lx = rL + rb(3)*(0.18 + 0.64*(j-1)/(nt-1)); end
                    yN = rT + wb/2;   yIn = rT - 1.6;   yEx = shT + 1.6;   yO = shT + 3.0;
                    wire([lx, busT], [lx, yIn]);
                    if abs(lx - cx) > 1e-6, wire([lx, busT], [cx, busT]); end
                    res([lx, yIn], [lx, yN], Ri);            % crosses the inner rectangle
                    res([lx, yN], [lx, yEx], Ro);            % crosses the outer rectangle
                    wire([lx, yEx], [lx, yO]);
                    dot([lx, yN]);
                    cs = 1;  if lx < cx - 1e-6, cs = -1; end
                    cap([lx + 1.15*cs, yN], [cs 0], nd.C, ternstr(cs>0,'right','left'));
                    wire([lx, yN], [lx + 1.15*cs, yN]);
                    term([lx, yO], [0 1]);
                    text(ax, lx - 1.2*cs, yN, tex(nd.name), lbl{:}, 'FontSize', FS-1, ...
                        'HorizontalAlignment', ternstr(cs<0,'left','right'));
                    pos(nd.name) = [lx, yN];
                end

                % walls on the side border, only when the zone also has a roof
                if hasRoof
                    for j = 1:numel(envWalls)
                        nd = z.nodes(envWalls(j));  Ri = z.resistors(wallRi(j)).R;  Ro = z.resistors(wallRo(j)).R;
                        onLeft = (mod(j,2) == 1);
                        if bias > 0, onLeft = ~onLeft; end
                        ly = cy + spread(ceil(j/2), max(ceil(numel(envWalls)/2),1), RH*0.28);
                        if onLeft, sg = -1;  re = rL;  se = sh(1);
                        else,      sg = 1;   re = rR;  se = sh(1)+sh(3);  end
                        xN = re + sg*(wb/2);   xIn = re - sg*1.6;   xEx = se + sg*1.6;   xO = se + sg*3.0;
                        wire([xIn, ly], [cx, ly]);              % wall node -> air node (real)
                        res([xIn, ly], [xN, ly], Ri);           % crosses the inner rectangle
                        res([xN, ly], [xEx, ly], Ro);           % crosses the outer rectangle
                        wire([xEx, ly], [xO, ly]);
                        dot([xN, ly]);
                        cap([xN, ly - 1.1], [0 -1], nd.C, 'right');
                        wire([xN, ly], [xN, ly - 1.1]);
                        term([xO, ly], [0 1]);
                        text(ax, xN, ly + 1.0, tex(nd.name), lbl{:}, 'FontSize', FS-1, 'HorizontalAlignment', 'center');
                        pos(nd.name) = [xN, ly];
                    end
                end

                % ----- windows / vents  (pane fills the border exactly; R crosses the outer edge) -----
                nw = numel(c.winR);
                for j = 1:nw
                    r = z.resistors(c.winR(j));
                    wx = rL + rb(3)*j/(nw+1);
                    yWn = rBo - wb/2;                       % pane / node centre = border middle
                    yO  = shBo - 2.4;
                    wire([wx, busB], [wx, yWn]);
                    if abs(wx - cx) > 1e-6, wire([wx, busB], [cx, busB]); end
                    pane([wx, yWn], wb);                    % height = inner-to-outer distance
                    dot([wx, yWn]);
                    res([wx, shBo + 0.4], [wx, yO], r.R);   % crosses the outer rectangle
                    wire([wx, yWn], [wx, shBo + 0.4]);
                    term([wx, yO], [0 -1]);
                    stag = 1.1 * mod(j-1, 2);
                    text(ax, wx - 1.5, yWn + stag, tex(r.name), lbl{:}, 'FontSize', FS-1.5, ...
                        'Color', C_WIN*0.7, 'HorizontalAlignment', 'right');
                    pos(r.name) = [wx, yWn];
                end

                % ----- internal-mass nodes (cap attached straight to the node) -----
                ni = numel(c.imN);
                for j = 1:ni
                    nd = z.nodes(c.imN(j));  Rv = z.resistors(c.imRi(j)).R;
                    if ni == 1, iy = cy; else, iy = cy + spread(j, ni, RH*0.26); end
                    ix = rL + rb(3)*0.24;
                    res([ix, iy], [cx, iy], Rv);
                    dot([ix, iy]);
                    cap([ix, iy], [0 1], nd.C, 'right');
                    text(ax, ix - 0.3, iy - 1.0, tex(nd.name), lbl{:}, 'FontSize', FS-1.5, 'HorizontalAlignment', 'center');
                    pos(nd.name) = [ix, iy];
                end

                % ----- generic nodes -----
                ng = numel(c.genN);
                for j = 1:ng
                    nd = z.nodes(c.genN(j));
                    gy = cy + spread(j, ng, RH*0.26);
                    gx = rR - rb(3)*0.24;
                    if c.genRi(j) > 0, res([gx, gy], [cx, gy], z.resistors(c.genRi(j)).R);
                    else,              wire([gx, gy], [cx, gy]); end
                    dot([gx, gy]);
                    if nd.C > 0, cap([gx, gy], [0 -1], nd.C, 'right'); end
                    text(ax, gx + 1.0, gy, tex(nd.name), lbl{:}, 'FontSize', FS-1.5, 'HorizontalAlignment', 'left');
                    pos(nd.name) = [gx, gy];
                end

                % ----- external heat (short arrow from the upper right) -----
                for j = 1:numel(z.heatSources)
                    hs = z.heatSources(j);
                    if isKey(pos, hs.nodeName), pT = pos(hs.nodeName); else, pT = [cx, cy]; end
                    pF = [pT(1) + 2.6, pT(2) + 2.4 + (j-1)*1.3];
                    harrow(pF, [pT(1) + 0.45, pT(2) + 0.4]);
                    text(ax, pF(1) + 0.3, pF(2) + 0.5, ['Q \rightarrow ' tex(hs.nodeName)], ...
                        lbl{:}, 'Color', C_HEAT, 'FontSize', FS-1, 'HorizontalAlignment', 'left');
                end
            end

            % which side to keep envelope nodes clear of (based on cross links)
            function b = crossSideBias(z, a)
                b = 0;
                for c = 1:numel(z.crossRes)
                    r = z.crossRes{c};
                    o = otherZoneOf(r, z);  if isempty(o), continue; end
                    ok = sprintf('%s.%s', o.storey.name, o.name);
                    if ~isKey(A, ok), continue; end
                    b = b + sign(A(ok).air(1) - a.air(1));
                end
                b = -sign(b);         % lean AWAY from the busier side
            end
            function o = otherZoneOf(r, z)
                o = [];
                if isstruct(r.n1) && r.n1.zone ~= z, o = r.n1.zone; end
                if isstruct(r.n2) && r.n2.zone ~= z, o = r.n2.zone; end
            end
            function lx = envLaneX(j, ne, rL, RW)
                if ne == 1, lx = rL + RW*0.5;
                else,       lx = rL + RW*(0.17 + 0.66*(j-1)/(ne-1)); end
            end

            % ================= inter-zone coupling =================
            function tf = isEndpointZone(ep, z)
                tf = isstruct(ep) && isfield(ep, 'zone') && ep.zone == z;
            end

            function drawCross(r, base)
                z1 = r.n1.zone;  z2 = r.n2.zone;
                a1 = A(sprintf('%s.%s', z1.storey.name, z1.name));
                a2 = A(sprintf('%s.%s', z2.storey.name, z2.name));
                mi = find(strcmp({z1.nodes.name}, [base '_c']), 1);
                isCap = ~isempty(mi);
                midC  = 0;  if isCap, midC = z1.nodes(mi).C; end
                kind = 'air';
                if isfield(r, 'kind') && ~isempty(r.kind), kind = r.kind; end
                dv = a2.air - a1.air;
                interstorey = strcmp(kind, 'slab') || (abs(dv(2)) > abs(dv(1)) && abs(dv(2)) > 1e-6);

                if interstorey
                    % roof / floor slab: port on the lower ceiling, port on the
                    % upper floor, leaning toward each other in x
                    lo = a1;  up = a2;  if a1.air(2) > a2.air(2), lo = a2;  up = a1;  end
                    px1 = clamp(up.air(1), lo.shell(1)+2, lo.shell(1)+lo.shell(3)-2);
                    px2 = clamp(lo.air(1), up.shell(1)+2, up.shell(1)+up.shell(3)-2);
                    p1 = [px1, lo.shell(2)+lo.shell(4)];
                    p2 = [px2, up.shell(2)];
                    port(p1);  port(p2);
                    drawLink(p1, p2, isCap, r.R, midC, [1 0], 'right');
                    mp = (p1+p2)/2;
                    text(ax, mp(1)+1.3, mp(2), tex(base), lbl{:}, 'FontSize', FS-1.5, ...
                        'Color', [0.3 0.3 0.3], 'HorizontalAlignment', 'left');
                else
                    % same storey: ports on the facing side edges
                    if a1.air(1) < a2.air(1)
                        p1 = [a1.shell(1)+a1.shell(3), a1.air(2)];  p2 = [a2.shell(1), a2.air(2)];
                    else
                        p1 = [a1.shell(1), a1.air(2)];  p2 = [a2.shell(1)+a2.shell(3), a2.air(2)];
                    end
                    if strcmp(kind, 'air')
                        wireG(a1.air, p1);  wireG(a2.air, p2);
                    end
                    port(p1);  port(p2);
                    drawLink(p1, p2, isCap, r.R, midC, [0 -1], 'right');
                    mp = (p1+p2)/2;
                    text(ax, mp(1), mp(2) - 2.7, tex(base), lbl{:}, 'FontSize', FS-1.5, 'Color', [0.3 0.3 0.3]);
                end
            end

            function drawLink(p1, p2, isCap, R, C, cdir, cside)
                mp = (p1+p2)/2;
                if isCap
                    q1 = p1 + (mp - p1)*0.42;  q2 = p2 + (mp - p2)*0.42;
                    res(p1, q1, R);  res(p2, q2, []);
                    wire(q1, mp);  wire(q2, mp);  dot(mp);
                    cap(mp + 0.9*cdir, cdir, C, cside);  wire(mp, mp + 0.9*cdir);
                else
                    res(p1, p2, R);  dot(mp);
                end
            end
            function q = clamp(v, lo, hi), q = min(max(v, lo), hi);  end

            % ================= glyphs =================
            function wire(p1, p2),  plot(ax, [p1(1) p2(1)], [p1(2) p2(2)], '-', 'Color', C_WIRE, 'LineWidth', 0.9);  end
            function wireG(p1, p2), plot(ax, [p1(1) p2(1)], [p1(2) p2(2)], '-', 'Color', C_GREY, 'LineWidth', 0.9);  end
            function dot(p),        plot(ax, p(1), p(2), 'o', 'MarkerSize', 5, 'MarkerFaceColor', C_NODE, 'MarkerEdgeColor', C_NODE);  end
            function port(p),       plot(ax, p(1), p(2), 'o', 'MarkerSize', 7, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', C_WIRE, 'LineWidth', 1.3);  end

            function res(p1, p2, val)
                p1 = p1(:).';  p2 = p2(:).';  v = p2 - p1;  L = norm(v);
                if L < 1e-6, return; end
                u = v/L;  w = [-u(2) u(1)];
                bl = min(1.5, 0.62*L);  bh = 0.40;  mc = (p1+p2)/2;
                aa = mc - bl/2*u;  bb = mc + bl/2*u;
                wire(p1, aa);  wire(bb, p2);
                cn = [aa+bh/2*w; bb+bh/2*w; bb-bh/2*w; aa-bh/2*w];
                patch(ax, cn(:,1), cn(:,2), 'w', 'EdgeColor', C_WIRE, 'LineWidth', 1.1);
                if nargin > 2 && ~isempty(val) && ~isnan(val)
                    vert = abs(u(2)) > abs(u(1));
                    if vert, lp = mc + 0.8*w;  rot = 90;
                    else,    lp = mc + 1.0*[0 -1];  rot = 0;  end
                    text(ax, lp(1), lp(2), fmt(val), lbl{:}, 'FontSize', FS-1.5, 'Rotation', rot);
                end
            end

            function cap(p, dir, val, side)
                dir = dir(:).'/max(norm(dir), eps);  w = [-dir(2) dir(1)];
                pl = 0.95;   gp = 0.38;               % wider plate gap so the two lines read
                c1 = p + 0.32*dir;   c2 = c1 + gp*dir;
                wire(p, c1);
                plot(ax, c1(1)+[-pl/2 pl/2]*w(1), c1(2)+[-pl/2 pl/2]*w(2), '-', 'Color', C_WIRE, 'LineWidth', 1.9);
                plot(ax, c2(1)+[-pl/2 pl/2]*w(1), c2(2)+[-pl/2 pl/2]*w(2), '-', 'Color', C_WIRE, 'LineWidth', 1.9);
                g0 = c2 + 0.32*dir;   wire(c2, g0);
                for gi = 0:2
                    ww = 0.62 - 0.19*gi;   gg = g0 + 0.13*gi*dir;
                    plot(ax, gg(1)+[-ww/2 ww/2]*w(1), gg(2)+[-ww/2 ww/2]*w(2), '-', 'Color', C_WIRE, 'LineWidth', 1);
                end
                if nargin > 2 && ~isempty(val) && ~isnan(val)
                    sgn = 1;  if strcmp(side, 'left'), sgn = -1; end
                    lp = c1 + sgn*(pl/2 + 0.75)*w;
                    vert = abs(w(2)) > abs(w(1));
                    if vert
                        text(ax, lp(1), lp(2), fmt(val), lbl{:}, 'FontSize', FS-1.5, 'Rotation', 90);
                    else
                        ha = 'center';
                        if sgn*w(1) > 0.3, ha = 'left'; elseif sgn*w(1) < -0.3, ha = 'right'; end
                        text(ax, lp(1), lp(2), fmt(val), lbl{:}, 'FontSize', FS-1.5, 'HorizontalAlignment', ha);
                    end
                end
            end

            function term(p, dir)
                plot(ax, p(1), p(2), 'o', 'MarkerSize', 9, 'MarkerFaceColor', C_OUT, ...
                    'MarkerEdgeColor', C_OUT*0.6, 'LineWidth', 0.8);
                d = dir(:).'/max(norm(dir), eps);
                lp = p + 1.7*d;
                ha = 'center';
                if d(1) > 0.3, ha = 'left'; elseif d(1) < -0.3, ha = 'right'; end
                text(ax, lp(1), lp(2), 'T_{outdoor}', lbl{:}, 'Color', C_OUT*0.85, 'FontSize', FS-1, ...
                    'HorizontalAlignment', ha);
            end

            function pane(pc, h)
                pw = 2.0;
                rectangle(ax, 'Position', [pc(1)-pw/2, pc(2)-h/2, pw, h], ...
                    'FaceColor', [C_WIN 0.30], 'EdgeColor', C_WIN, 'LineWidth', 1.6);
                plot(ax, pc(1)+[-pw/2 pw/2], pc(2)+[-h/2 h/2], '-', 'Color', C_WIN, 'LineWidth', 0.7);
            end

            function harrow(p1, p2)
                v = p2 - p1;  L = norm(v);  u = v/max(L, eps);  w = [-u(2) u(1)];
                pb = p2 - 0.6*u;
                plot(ax, [p1(1) pb(1)], [p1(2) pb(2)], '-', 'Color', C_HEAT, 'LineWidth', 2.2);
                patch(ax, [p2(1); pb(1)+0.3*w(1); pb(1)-0.3*w(1)], ...
                          [p2(2); pb(2)+0.3*w(2); pb(2)-0.3*w(2)], C_HEAT, 'EdgeColor', C_HEAT);
            end

            function drawLegend()
                [bxx, ~] = contentBounds(ax);
                y0 = (nS-1)*PY + CH + 2.6;   x = bxx(1);
                step = max(8.0, ((maxZ*PX) - 4) / 5);
                cc = [lbl, {'HorizontalAlignment', 'left', 'FontSize', FS-1}];
                res([x, y0], [x+1.6, y0], []);        text(ax, x+2.3, y0, 'resistance', cc{:});
                x = x + step;
                cap([x, y0], [0 -1], [], 'right');    text(ax, x+1.1, y0, 'capacitance', cc{:});
                x = x + step;
                plot(ax, x, y0, 'o', 'MarkerSize', 9, 'MarkerFaceColor', C_OUT, 'MarkerEdgeColor', C_OUT*0.6);
                text(ax, x+1.1, y0, 'outdoor / fixed T', cc{:});
                x = x + step;
                harrow([x, y0], [x+1.7, y0]);         text(ax, x+2.3, y0, 'heat input', cc{:});
                x = x + step;
                pane([x+0.7, y0], 1.4);               text(ax, x+2.1, y0, 'window / vent', cc{:});
            end

            % ================= misc =================
            function d = spread(j, n, span)
                if n <= 1, d = 0; else, d = (j - (n+1)/2) / (n-1) * span; end
            end
            function tv = ternstr(tc, ta, tb), if tc, tv = ta; else, tv = tb; end, end
            function s = tex(name),  s = strrep(char(name), '_', '\_');  end
            function [bx, by] = contentBounds(axh)
                xs = [];  ys = [];
                for h = axh.Children(:).'
                    try
                        if isprop(h, 'XData') && ~isempty(h.XData)
                            xs = [xs, h.XData(:).'];  ys = [ys, h.YData(:).']; %#ok<AGROW>
                        elseif strcmp(h.Type, 'rectangle')
                            p = h.Position;  xs = [xs, p(1), p(1)+p(3)];  ys = [ys, p(2), p(2)+p(4)]; %#ok<AGROW>
                        elseif strcmp(h.Type, 'text')
                            e = h.Extent;  xs = [xs, e(1), e(1)+e(3)];  ys = [ys, e(2), e(2)+e(4)]; %#ok<AGROW>
                        end
                    catch
                    end
                end
                if isempty(xs), xs = [0 1];  ys = [0 1]; end
                bx = [min(xs), max(xs)];  by = [min(ys), max(ys)];
            end
            function str = fmt(v)
                if isempty(v) || (isscalar(v) && isnan(v)), str = ''; return; end
                if     v >= 1e9, str = sprintf('%.3gG', v/1e9);
                elseif v >= 1e6, str = sprintf('%.3gM', v/1e6);
                elseif v >= 1e3, str = sprintf('%.3gk', v/1e3);
                elseif v >= 1,   str = sprintf('%.3g', v);
                elseif v > 0,    str = sprintf('%.3gm', v*1e3);
                else,            str = sprintf('%.3g', v);
                end
            end
        end
        
        function temps = getAllZoneTemps(obj)
            % helper: collect main node temps of all zones
            temps = containers.Map();
            for i = 1:numel(obj.storeyList)
                sname = obj.storeyList{i};
                storey = obj.(sname);
                for j=1:numel(storey.zoneList)
                    zname = storey.zoneList{j};
                    zone = storey.(zname);
                    temps(sprintf('%s.%s', sname, zname)) = zone.getMainTemp();
                end
            end
        end
    end
end