function drawSchematic(sys)
%DHS.DRAWSCHEMATIC  Schematic of an assembled DHS.System.
%
%   Called by DHS.System.visualize(). Draws the closed district loop:
%
%     * the central heat plant (boilers, central pump, supply setpoint);
%     * the SUPPLY pipes (red) from the plant out to every junction, and the matching
%       RETURN pipes (blue) from every junction back into the plant, each labelled with
%       its name, length and diameter;
%     * every junction: a square for a T-junction (with its main/side diameters), a
%       circle for a plain junction, on both the supply and the return side;
%     * every building as a plain rectangle, with its number of zones in parentheses
%       under its name, and its service pipes (length, diameter) joining the supply
%       junction above to the return junction below.
%
%   The loop is closed through the buildings: the last supply junction feeds the last
%   building, whose return meets the first return junction. Arrows give the flow
%   direction. For a building's RC-network detail call  building.rcBuilding.visualize().

    net = sys.network;  plant = sys.plant;
    nJ = numel(net.junctions);  nB = numel(sys.buildings);

    cSup = [0.85 0.10 0.10];  cRet = [0.10 0.25 0.85];  cGrey = [0.35 0.35 0.35];
    lwMain = 3;  lwSvc = 2.2;

    f = figure('Name','DHS.System schematic','NumberTitle','off','Color','w');
    ax = axes(f); hold(ax,'on'); axis(ax,'equal'); axis(ax,'off');

    ySup = 0;  yRet = -10;  dx = 11;
    pw = 7.2;  ph = (ySup - yRet) + 3;  x0 = 0;  yP = (ySup + yRet)/2;     % plant box
    xFirst = x0 + pw/2 + dx;                                               % first junction

    % --- junction x-positions in tree (BFS) order ------------------------------
    jx = containers.Map('KeyType','char','ValueType','double');
    for k = 1:numel(net.pipeOrder)
        p = net.pipes{net.pipeOrder(k)};
        jx(p.nodeB.name) = xFirst + (k-1)*dx;
    end
    xEnd = xFirst;  if nJ > 0, xEnd = max(cellfun(@(j) jx(j.name), net.junctions)); end
    xPlantR = x0 + pw/2;

    % --- plant -------------------------------------------------------------------
    rectangle(ax,'Position',[x0-pw/2, yP-ph/2, pw, ph],'LineWidth',2,'FaceColor',[1 .93 .85]);
    text(ax, x0, yP+ph/2-0.6, plant.name, 'HorizontalAlignment','center','FontWeight','bold', ...
        'FontSize',11,'Interpreter','none');
    nb = max(1, numel(plant.boilers));
    for bi = 1:nb
        text(ax, x0, yP+1.0-(bi-1)*1.7, boilerLabel(plant, bi), 'HorizontalAlignment','center', ...
            'FontSize',9,'Interpreter','none');
    end
    text(ax, x0, yP-ph/2+1.5, sprintf('supply setpoint\n%.0f\\circC', plant.TsupSet), ...
        'HorizontalAlignment','center','FontSize',9);

    % central pump on the supply stub leaving the plant
    xPump = xPlantR + 1.5;
    plot(ax, [xPlantR, xFirst], [ySup ySup], '-', 'Color',cSup, 'LineWidth',lwMain);
    th = linspace(0, 2*pi, 40);
    fill(ax, xPump+0.75*cos(th), ySup+0.75*sin(th), [1 1 1], 'EdgeColor','k', 'LineWidth',1.5);
    plot(ax, xPump+0.75*[cos(pi/3) 1 cos(-pi/3)], ySup+0.75*[sin(pi/3) 0 sin(-pi/3)], 'k-', 'LineWidth',1.5);
    text(ax, xPump, ySup-1.1, sprintf('%s\n%s', plant.supplyPump.name, pumpTypeTag(plant.supplyPump)), ...
        'HorizontalAlignment','center','VerticalAlignment','top','FontSize',8,'Interpreter','none');

    % --- supply and return pipes -------------------------------------------------------
    plot(ax, [xPlantR, xFirst], [yRet yRet], '-', 'Color',cRet, 'LineWidth',lwMain);
    for k = 1:numel(net.pipeOrder)
        p  = net.pipes{net.pipeOrder(k)};
        xb = jx(p.nodeB.name);
        if isKey(jx, p.nodeA.name), xa = jx(p.nodeA.name); else, xa = xPlantR; end
        plot(ax, [xa xb], [ySup ySup], '-', 'Color',cSup, 'LineWidth',lwMain);
        plot(ax, [xa xb], [yRet yRet], '-', 'Color',cRet, 'LineWidth',lwMain);
    end
    % plant -> first junction segment is the first pipe: label it from the plant edge
    for k = 1:numel(net.pipeOrder)
        p  = net.pipes{net.pipeOrder(k)};
        xb = jx(p.nodeB.name);
        if isKey(jx, p.nodeA.name), xa = jx(p.nodeA.name); else, xa = xPlantR; end
        xm = (xa + xb)/2;
        pipeLabel(ax, xm, ySup+0.35, 'bottom', p.name, p.L, p.D, cSup);
        pr = net.retPipes{net.pipeOrder(k)};
        pipeLabel(ax, xm, yRet-0.35, 'top', [p.name ' (return)'], pr.L, pr.D, cRet, true);
        arrow(ax, xa + 0.62*(xb-xa), ySup, +1, cSup);
        arrow(ax, xa + 0.38*(xb-xa), yRet, -1, cRet);
    end

    % --- junctions ---------------------------------------------------------------------------
    for k = 1:nJ
        j = net.junctions{k};  x = jx(j.name);
        isTee = isa(j, 'DHS.Hydraulic.TJunction');
        drawNode(ax, x, ySup, cSup, isTee);   drawNode(ax, x, yRet, cRet, isTee);
        text(ax, x, ySup+1.45+0.9, j.name, 'HorizontalAlignment','center','FontWeight','bold', ...
            'FontSize',9,'Interpreter','none');
        text(ax, x, yRet-1.45-0.9, j.mirror.name, 'HorizontalAlignment','center','FontWeight','bold', ...
            'FontSize',9,'Interpreter','none','Color',cRet*0.8);
        if isTee
            text(ax, x-0.45, ySup-0.9, sprintf('T-junction\nmain %.0f / side %.0f mm', ...
                1000*j.mainDiameter, 1000*j.sideDiameter), 'HorizontalAlignment','right', ...
                'VerticalAlignment','top','FontSize',8,'Color',cGrey);
        end
    end

    % --- buildings: simple rectangles joined to the supply and return junctions ------------------
    bw = 5.4;  bh = 3.2;  yB = (ySup + yRet)/2;
    for b = 1:nB
        bd = sys.buildings{b};
        x  = jx(bd.inlet.parentPipe.name);
        plot(ax, [x x], [ySup, yB+bh/2], '-', 'Color',cSup, 'LineWidth',lwSvc);
        plot(ax, [x x], [yRet, yB-bh/2], '-', 'Color',cRet, 'LineWidth',lwSvc);
        arrow(ax, x, (ySup + yB+bh/2)/2, 0, cSup);
        arrow(ax, x, (yRet + yB-bh/2)/2, 0, cRet);
        rectangle(ax,'Position',[x-bw/2, yB-bh/2, bw, bh],'LineWidth',1.8,'FaceColor',[.93 .95 1]);
        text(ax, x, yB+0.35, bd.name, 'HorizontalAlignment','center','FontWeight','bold', ...
            'FontSize',10,'Interpreter','none');
        text(ax, x, yB-0.55, sprintf('(%s)', zoneCount(bd.rcBuilding)), 'HorizontalAlignment','center', ...
            'FontSize',10,'Color',cGrey);
        svc = sprintf('%g m / D%.0f mm', bd.connLength, 1000*bd.connD);
        text(ax, x+0.4, (ySup + yB+bh/2)/2, svc, 'HorizontalAlignment','left','FontSize',8,'Color',cSup*0.85);
        text(ax, x+0.4, (yRet + yB-bh/2)/2, svc, 'HorizontalAlignment','left','FontSize',8,'Color',cRet*0.85);
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

    xLo = x0 - pw/2 - 1.5;  xHi = max(xEnd + 7.5, xL + 4*st + 8);  yLo = yL - 1.5;  yHi = ySup + 5.2;
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
