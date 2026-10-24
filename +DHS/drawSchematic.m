function drawSchematic(sys)
%DHS.DRAWSCHEMATIC  Schematic of an assembled DHS.System.
%
%   Called by DHS.System.visualize(). Draws the closed district loop:
%
%     * the central heat plant (boilers and the central pump);
%     * the SUPPLY pipes (red) from the plant out to every supply junction, and the RETURN
%       pipes (blue) from the return junctions back into the plant, each labelled with
%       its name, length and diameter (the two sides are defined separately and may differ);
%     * every junction: a square for a T-junction (with its main/side diameters), a
%       circle for a plain junction, on both the supply and the return side;
%     * every building as a plain rectangle, with its number of zones in parentheses
%       under its name, and its service pipes (length, diameter) joining the supply
%       junction above to the return junction below.
%
%   The loop is closed through the buildings: each building joins its supply junction to its
%   return junction; an end-of-line bypass, when the network has one, joins its supply junction
%   to its return junction. A return junction is drawn under the buildings that drain into it.
%   Arrows give the flow direction. For a building's RC-network detail call  building.rcBuilding.visualize().

    net = sys.network;  plant = sys.plant;
    nJ = numel(net.junctions) + numel(net.returnJunctions);  nB = numel(sys.buildings);

    cSup = [0.85 0.10 0.10];  cRet = [0.10 0.25 0.85];  cGrey = [0.35 0.35 0.35];
    lwMain = 3;  lwSvc = 2.2;

    f = figure('Name','DHS.System schematic','NumberTitle','off','Color','w');
    ax = axes(f); hold(ax,'on'); axis(ax,'equal'); axis(ax,'off');

    ySup = 0;  yRet = -10;  dx = 11;
    pw = 7.2;  ph = (ySup - yRet) + 3;  x0 = 0;  yP = (ySup + yRet)/2;     % plant box
    xFirst = x0 + pw/2 + dx;                                               % first junction

    % --- x-positions: supply junctions along the main, return junctions under their buildings ---
    orderS = pipesFrom(net.plantSupply, 'supply');
    jx = containers.Map('KeyType','char','ValueType','double');
    for k = 1:numel(orderS), jx(orderS{k}.nodeB.name) = xFirst + (k-1)*dx; end
    xEnd = xFirst;  if ~isempty(orderS), xEnd = max(cellfun(@(p) jx(p.nodeB.name), orderS)); end
    xPlantR = x0 + pw/2;
    rx = containers.Map('KeyType','char','ValueType','double');
    rx(net.plantReturn.name) = xPlantR;
    orderR = pipesFrom(net.plantReturn, 'return');
    for k = numel(orderR):-1:1, returnX(orderR{k}.nodeA, rx, jx, net, xFirst); end

    % --- plant -------------------------------------------------------------------
    rectangle(ax,'Position',[x0-pw/2, yP-ph/2, pw, ph],'LineWidth',2,'FaceColor',[1 .93 .85]);
    text(ax, x0, yP+ph/2-0.6, plant.name, 'HorizontalAlignment','center','FontWeight','bold', ...
        'FontSize',11,'Interpreter','none');
    nb = max(1, numel(plant.boilers));
    for bi = 1:nb
        text(ax, x0, yP+1.0-(bi-1)*1.7, boilerLabel(plant, bi), 'HorizontalAlignment','center', ...
            'FontSize',9,'Interpreter','none');
    end
    text(ax, x0, yP-ph/2+1.6, sprintf('pump %s\n%s', plant.supplyPump.name, pumpTypeTag(plant.supplyPump)), ...
        'HorizontalAlignment','center','FontSize',9,'Interpreter','none');

    % --- supply pipes -------------------------------------------------------------------
    for k = 1:numel(orderS)
        p  = orderS{k};
        xb = jx(p.nodeB.name);
        if isKey(jx, p.nodeA.name), xa = jx(p.nodeA.name); else, xa = xPlantR; end
        plot(ax, [xa xb], [ySup ySup], '-', 'Color',cSup, 'LineWidth',lwMain);
        pipeLabel(ax, (xa+xb)/2, ySup+0.35, 'bottom', p.name, p.L, p.D, cSup);
        arrow(ax, xa + 0.62*(xb-xa), ySup, +1, cSup);
    end

    % --- return pipes -------------------------------------------------------------------------
    for k = 1:numel(orderR)
        p  = orderR{k};
        xa = rx(p.nodeA.name);  xb = rx(p.nodeB.name);          % flow runs from xa toward the plant
        plot(ax, [xa xb], [yRet yRet], '-', 'Color',cRet, 'LineWidth',lwMain);
        if abs(xb - xa) > 1.5
            pipeLabel(ax, (xa+xb)/2, yRet-0.35, 'top', p.name, p.L, p.D, cRet, true);
            arrow(ax, xa + 0.5*(xb-xa), yRet, sign(xb-xa), cRet);
        end
    end

    % --- junctions ---------------------------------------------------------------------------
    for k = 1:numel(net.junctions)
        j = net.junctions{k};
        if ~isKey(jx, j.name), continue, end
        x = jx(j.name);
        isTee = isa(j, 'DHS.Hydraulic.TJunction');
        drawNode(ax, x, ySup, cSup, isTee);
        text(ax, x, ySup+1.45+0.9, j.name, 'HorizontalAlignment','center','FontWeight','bold', ...
            'FontSize',9,'Interpreter','none');
        if isTee
            text(ax, x-0.45, ySup-0.9, sprintf('T-junction\nmain %.0f / side %.0f mm', ...
                1000*j.mainDiameter, 1000*j.sideDiameter), 'HorizontalAlignment','right', ...
                'VerticalAlignment','top','FontSize',8,'Color',cGrey);
        end
    end
    for k = 1:numel(net.returnJunctions)
        j = net.returnJunctions{k};
        if ~isKey(rx, j.name), continue, end
        x = rx(j.name);
        drawNode(ax, x, yRet, cRet, false);
        text(ax, x, yRet-1.45-0.9, j.name, 'HorizontalAlignment','center','FontWeight','bold', ...
            'FontSize',9,'Interpreter','none','Color',cRet*0.8);
    end

    % --- end-of-line bypass: its supply junction -> its return junction ----------------------------
    xRight = xEnd + 7.5;
    if net.hasBypass()
        xj = jx(net.bypassJunction.name);  xr = rx(net.bypassReturnJunction.name);
        xB = xj + 7.5;  yM = (ySup + yRet)/2;
        plot(ax, [xj xB], [ySup ySup], '-', 'Color',cSup, 'LineWidth',lwMain);
        plot(ax, [xB xB], [ySup yM], '-', 'Color',cSup, 'LineWidth',lwMain);
        plot(ax, [xB xB], [yM yRet], '-', 'Color',cRet, 'LineWidth',lwMain);
        plot(ax, [xB xr], [yRet yRet], '-', 'Color',cRet, 'LineWidth',lwMain);
        s = 0.55;                                              % bypass valve (bow-tie across the pipe)
        fill(ax, xB+[-s s -s s], yM+[s s -s -s], [1 1 1], 'EdgeColor','k', 'LineWidth',1.5);
        arrow(ax, xj + 0.55*(xB-xj), ySup, +1, cSup);
        arrow(ax, xB, (ySup + yM)/2 + 0.8, 0, cSup);
        arrow(ax, xB, (yM + yRet)/2 - 0.8, 0, cRet);
        arrow(ax, xr + 0.45*(xB-xr), yRet, -1, cRet);
        text(ax, xB+0.8, yM+1.0, net.bypassPipe.name, 'FontWeight','bold','FontSize',9,'HorizontalAlignment','left','Interpreter','none');
        text(ax, xB+0.8, yM-0.1, sprintf('L = %g m,  D = %.0f mm', net.bypassPipe.L, 1000*net.bypassPipe.D), ...
            'FontSize',8,'HorizontalAlignment','left','VerticalAlignment','top');
        text(ax, xB+0.8, yM-1.2, bypassValveLabel(net.bypassValve), ...
            'FontSize',8,'HorizontalAlignment','left','VerticalAlignment','top','Color',cGrey);
        xRight = xB + 7;
    end

    % --- buildings: simple rectangles joined to their supply and return junctions ----------------
    bw = 5.4;  bh = 3.2;  yB = (ySup + yRet)/2;
    for b = 1:nB
        bd = sys.buildings{b};
        x  = jx(bd.connPipeSup.nodeA.name);
        xrj = rx(bd.connPipeRet.nodeB.name);
        plot(ax, [x x], [ySup, yB+bh/2], '-', 'Color',cSup, 'LineWidth',lwSvc);
        plot(ax, [x x], [yRet, yB-bh/2], '-', 'Color',cRet, 'LineWidth',lwSvc);
        if abs(xrj - x) > 0.01, plot(ax, [x xrj], [yRet yRet], '-', 'Color',cRet, 'LineWidth',lwSvc); end
        arrow(ax, x, (ySup + yB+bh/2)/2, 0, cSup);
        arrow(ax, x, (yRet + yB-bh/2)/2, 0, cRet);
        rectangle(ax,'Position',[x-bw/2, yB-bh/2, bw, bh],'LineWidth',1.8,'FaceColor',[.93 .95 1]);
        text(ax, x, yB+0.35, bd.name, 'HorizontalAlignment','center','FontWeight','bold', ...
            'FontSize',10,'Interpreter','none');
        text(ax, x, yB-0.55, sprintf('(%s)', zoneCount(bd.rcBuilding)), 'HorizontalAlignment','center', ...
            'FontSize',10,'Color',cGrey);
        text(ax, x+0.4, (ySup + yB+bh/2)/2, sprintf('%g m / D%.0f mm', bd.connPipeSup.L, 1000*bd.connPipeSup.D), ...
            'HorizontalAlignment','left','FontSize',8,'Color',cSup*0.85);
        text(ax, x+0.4, (yRet + yB-bh/2)/2, sprintf('%g m / D%.0f mm', bd.connPipeRet.L, 1000*bd.connPipeRet.D), ...
            'HorizontalAlignment','left','FontSize',8,'Color',cRet*0.85);
    end

    % --- legend ---------------------------------------------------------------------------------------
    yL = yRet - 5.2;  xL = x0 - pw/2;  st = 9.5;
    plot(ax, xL+[0 2], [yL yL], '-', 'Color',cSup, 'LineWidth',lwMain);
    text(ax, xL+2.4, yL, 'supply pipe', 'FontSize',9, 'VerticalAlignment','middle');
    plot(ax, xL+st+[0 2], [yL yL], '-', 'Color',cRet, 'LineWidth',lwMain);
    text(ax, xL+st+2.4, yL, 'return pipe', 'FontSize',9, 'VerticalAlignment','middle');
    drawNode(ax, xL+2*st+1, yL, [0.6 0.6 0.6], true);
    text(ax, xL+2*st+1.7, yL, 'T-junction', 'FontSize',9, 'VerticalAlignment','middle');
    drawNode(ax, xL+3*st+1, yL, [0.6 0.6 0.6], false);
    text(ax, xL+3*st+1.7, yL, 'plain junction', 'FontSize',9, 'VerticalAlignment','middle');
    arrow(ax, xL+4*st+1, yL, +1, [0.4 0.4 0.4]);
    text(ax, xL+4*st+1.7, yL, 'flow direction', 'FontSize',9, 'VerticalAlignment','middle');

    xLo = x0 - pw/2 - 1.5;  xHi = max(xRight, xL + 4*st + 8);  yLo = yL - 1.5;  yHi = ySup + 5.2;
    xlim(ax,[xLo, xHi]); ylim(ax,[yLo, yHi]);
    title(ax, sprintf('District heating network  -  %d building(s), %d junction(s)', nB, nJ), ...
        'Interpreter','none','FontSize',12);

    % size the figure to the content so the labels have room
    ppu  = min(28, 1480/(xHi - xLo));                  % pixels per data unit (fits a laptop screen)
    figW = min(2600, max(900, round(ppu*(xHi-xLo))));
    figH = min(1500, max(520, round(ppu*(yHi-yLo))));
    set(f, 'Position', [40 60 figW figH]);
    set(ax, 'Position', [0.01 0.01 0.98 0.93]);
end

% ===================== helpers =====================
function drawNode(ax, x, y, color, isTee)
    % T-junction: filled square; plain junction: filled circle
    if isTee
        rectangle(ax,'Position',[x-0.3,y-0.3,0.6,0.6],'Curvature',0, ...
            'FaceColor',color,'EdgeColor','k','LineWidth',1.2);
    else
        rectangle(ax,'Position',[x-0.3,y-0.3,0.6,0.6],'Curvature',[1 1], ...
            'FaceColor',color,'EdgeColor','k','LineWidth',1.2);
    end
end

function pipeLabel(ax, x, y, va, name, L, D, color, isReturn)
    % two-line label: pipe name, then length and diameter
    if nargin < 9, isReturn = false; end %#ok<NASGU>
    dim = sprintf('L = %g m,  D = %.0f mm', L, 1000*D);
    if strcmp(va,'bottom')
        text(ax, x, y,      name, 'HorizontalAlignment','center','VerticalAlignment','bottom', ...
            'FontSize',8,'Color',color*0.85,'Interpreter','none','FontAngle','italic');
        text(ax, x, y+0.85, dim,  'HorizontalAlignment','center','VerticalAlignment','bottom', ...
            'FontSize',8,'Color',[0.15 0.15 0.15]);
    else
        text(ax, x, y,      name, 'HorizontalAlignment','center','VerticalAlignment','top', ...
            'FontSize',8,'Color',color*0.85,'Interpreter','none','FontAngle','italic');
        text(ax, x, y-0.85, dim,  'HorizontalAlignment','center','VerticalAlignment','top', ...
            'FontSize',8,'Color',[0.15 0.15 0.15]);
    end
end

function arrow(ax, x, y, dir, color)
    % flow arrowhead: dir +1 right, -1 left, 0 down, 2 up
    s = 0.42;
    switch dir
        case  1, P = [x+s y; x-s y+s; x-s y-s];
        case -1, P = [x-s y; x+s y+s; x+s y-s];
        case  0, P = [x y-s; x-s y+s; x+s y+s];
        otherwise, P = [x y+s; x-s y-s; x+s y-s];
    end
    patch(ax, P(:,1), P(:,2), color, 'EdgeColor','none');
end

function s = pumpTypeTag(pump)
    if isempty(pump), s = ''; return; end
    switch class(pump)
        case 'DHS.Hydraulic.CentrifugalPump',        s = '(centrifugal)';
        case 'DHS.Hydraulic.FixedDisplacementPump',  s = '(fixed-displacement)';
        otherwise,                                   s = '';
    end
end

function s = zoneCount(rc)
    % "N zones" (or "1 zone"): number of thermal zones in the building's RC model
    n = 0;
    for si = 1:numel(rc.storeyList)
        n = n + numel(rc.(rc.storeyList{si}).zoneList);
    end
    if n == 1, s = '1 zone'; else, s = sprintf('%d zones', n); end
end

function lbl = boilerLabel(plant, bi)
    if bi <= numel(plant.boilers)
        b = plant.boilers{bi};
        lbl = sprintf('boiler %s\n%.0f kW', b.name, b.QMax/1e3);
    else
        lbl = '';
    end
end

function s = bypassValveLabel(v)
    if isempty(v.controller), s = sprintf('valve Kvs = %g\nposition %g (fixed)', v.Kvs, v.pos);
    else,                     s = sprintf('valve Kvs = %g\ncontrolled', v.Kvs);
    end
end

function order = pipesFrom(root, side)
    % the pipes of one tree in order from the plant outward (breadth first)
    order = {};
    queue = root.childPipes;
    while ~isempty(queue)
        p = queue{1};  queue(1) = [];
        order{end+1} = p; %#ok<AGROW>
        if strcmp(side, 'supply'), queue = [queue, p.nodeB.childPipes]; %#ok<AGROW>
        else,                      queue = [queue, p.nodeA.childPipes]; %#ok<AGROW>
        end
    end
end

function x = returnX(node, rx, jx, net, xFirst)
    % x-position of a return junction: the mean x of the buildings (and bypass) draining into it, or, when
    % there are none, of the return branches arriving at it. rx caches the result (a handle).
    if isKey(rx, node.name), x = rx(node.name); return, end
    v = [];
    for q = 1:numel(node.fedBuildings), v(end+1) = jx(node.fedBuildings{q}.connPipeSup.nodeA.name); end %#ok<AGROW>
    if net.hasBypass() && node == net.bypassReturnJunction, v(end+1) = jx(net.bypassJunction.name); end %#ok<AGROW>
    if isempty(v)                       % no building of its own: halfway between the branches arriving at it
        for q = 1:numel(node.childPipes), v(end+1) = returnX(node.childPipes{q}.nodeA, rx, jx, net, xFirst); end %#ok<AGROW>
    end
    if isempty(v), x = xFirst; else, x = mean(v); end
    rx(node.name) = x;
end
