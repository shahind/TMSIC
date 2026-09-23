function drawSchematic(sys)
%DHS.DRAWSCHEMATIC  Schematic of an assembled DHS.System.
%
%   Called by DHS.System.visualize(). Draws the central heat plant, the supply
%   and return mains, every tee junction, and every building (with its primary
%   pump, control valve and heat exchanger, and any attached controller). It is
%   a topology/among-parts view; call  building.rcBuilding.visualize()  for a
%   building's RC-network detail.

    net = sys.network;  plant = sys.plant;
    nJ = numel(net.junctions);  nB = numel(sys.buildings);

    f = figure('Name','DHS.System schematic','NumberTitle','off','Color','w');
    ax = axes(f); hold(ax,'on'); axis(ax,'equal'); axis(ax,'off');

    ySup = 0; yRet = -7; dx = 6;

    % --- junction x-positions in tree (BFS) order -----------------------------
    jx = containers.Map('KeyType','char','ValueType','double');
    for k = 1:numel(net.pipeOrder)
        p = net.pipes{net.pipeOrder(k)};
        jx(p.nodeB.name) = k * dx;
    end
    x0 = -dx;                                     % plant column

    % --- plant box ---------------------------------------------------------
    pw = 3.7; ph = 3.0;
    rectangle(ax,'Position',[x0-pw/2, ySup-ph/2, pw, ph],'LineWidth',2,'FaceColor',[1 .93 .85]);
    text(ax,x0, ySup+ph/2+0.35, sprintf('%s', plant.name),'HorizontalAlignment','center', ...
        'FontWeight','bold','FontSize',9,'Interpreter','none');
    nb = max(1,numel(plant.boilers));
    for bi = 1:nb
        text(ax, x0, ySup+0.95 - (bi-1)*0.45, sprintf('boiler %s', boilerLabel(plant, bi)), ...
            'HorizontalAlignment','center','FontSize',7,'Interpreter','none');
    end
    drawPump(ax, [x0, ySup+0.1], 0.32, '');
    text(ax, x0, ySup-0.55, sprintf('%s  %s', plant.supplyPump.name, pumpTypeTag(plant.supplyPump)), ...
        'HorizontalAlignment','center','FontSize',6,'Color',[0.35 0.35 0.35]);
    text(ax, x0, ySup-1.05, sprintf('set %.0f\\circC', plant.TsupSet), ...
        'HorizontalAlignment','center','FontSize',7);
    % plant -> supply bus / return bus stubs
    plot(ax,[x0+pw/2, 0.0],[ySup ySup],'r-','LineWidth',2);
    plot(ax,[x0+pw/2, 0.0],[yRet yRet],'b-','LineWidth',2);
    plot(ax,[x0 x0],[ySup-ph/2, yRet],'k-','LineWidth',1);      % plant riser (visual)

    % --- supply & return mains + junctions --------------------------------
    xs = cellfun(@(j) jx(j.name), net.junctions);
    xmax = max([xs, 0]) + dx*0.5;
    plot(ax,[0 xmax],[ySup ySup],'r-','LineWidth',2);
    plot(ax,[0 xmax],[yRet yRet],'b-','LineWidth',2);
    text(ax, xmax, ySup+0.3, 'supply main','FontSize',7,'Color',[0.7 0 0]);
    text(ax, xmax, yRet-0.3, 'return main','FontSize',7,'Color',[0 0 0.7]);
    for k = 1:nJ
        j = net.junctions{k};  x = jx(j.name);
        if isa(j, 'DHS.Hydraulic.TJunction')
            drawTee(ax, x, ySup, 'r');   drawTee(ax, x, yRet, 'b');
            text(ax, x+0.35, ySup-0.55, sprintf('side D%.0fmm', 1000*j.sideDiameter), ...
                'HorizontalAlignment','left','FontSize',5.5,'Color',[0.5 0.35 0]);
        else
            plot(ax, x, ySup, 'ko','MarkerFaceColor','r','MarkerSize',7);
            plot(ax, x, yRet, 'ko','MarkerFaceColor','b','MarkerSize',7);
        end
        text(ax, x, ySup+0.3, j.name,'HorizontalAlignment','center','FontSize',7,'Interpreter','none');
    end
    % pipe length labels on each supply segment
    for k = 1:numel(net.pipeOrder)
        p  = net.pipes{net.pipeOrder(k)};
        xb = jx(p.nodeB.name);
        if isKey(jx, p.nodeA.name), xa = jx(p.nodeA.name); else, xa = 0; end
        text(ax,(xa+xb)/2, ySup+0.75, sprintf('%gm / D%.0fmm', p.L, 1000*p.D), ...
            'HorizontalAlignment','center','FontSize',6,'Color',[0.4 0.4 0.4]);
    end

    % --- buildings -------------------------------------------------------
    bw = 4.4; bh = 3.0; yB = (ySup + yRet)/2;
    for b = 1:nB
        bd = sys.buildings{b};
        x  = jx(bd.inlet.parentPipe.name);
        % risers
        plot(ax,[x x],[ySup, yB+bh/2],'r-','LineWidth',1.5);
        plot(ax,[x x],[yRet, yB-bh/2],'b-','LineWidth',1.5);
        rectangle(ax,'Position',[x-bw/2, yB-bh/2, bw, bh],'LineWidth',1.5,'FaceColor',[.92 .95 1]);
        text(ax, x, yB+bh/2-0.3, bd.name,'HorizontalAlignment','center','FontWeight','bold', ...
            'FontSize',8,'Interpreter','none');
        % primary train:  pump -> valve -> HX (top to bottom inside the box)
        drawPump(ax, [x, yB+0.55], 0.28, '');
        drawValve(ax,[x, yB-0.15], 0.30);
        drawHX(ax,  [x, yB-0.95], 0.9, 0.5);
        pumpTag = strtrim([ctrlTag(bd.heatExchanger.pump) ' ' pumpTypeTag(bd.heatExchanger.pump)]);
        text(ax, x+bw/2-0.15, yB+0.55, pumpTag, 'HorizontalAlignment','right','FontSize',6,'Color',[0 .5 0]);
        text(ax, x+bw/2-0.15, yB-0.15, ctrlTag(bd.heatExchanger.valve),'HorizontalAlignment','right','FontSize',6,'Color',[0 .5 0]);
        text(ax, x-bw/2+0.15, yB-0.95, sprintf('UA %.0fk', bd.heatExchanger.UA/1e3), ...
            'HorizontalAlignment','left','FontSize',6,'Color',[0.3 0.3 0.3]);
    end

    xLo = x0-pw-1;  xHi = xmax+2;  yLo = yRet-bh-1;  yHi = ySup+bh+0.5;
    xlim(ax,[xLo, xHi]); ylim(ax,[yLo, yHi]);
    title(ax, sprintf('%s  --  %d building(s), %d tee(s)', class(sys), nB, nJ), ...
        'Interpreter','none');

    % size the figure to the content instead of MATLAB's small default, so the
    % labels have room and nothing is crammed together
    ppu  = 24;                                          % pixels per data unit
    figW = min(2400, max(760, round(ppu*(xHi-xLo))));
    figH = min(1400, max(420, round(ppu*(yHi-yLo))));
    set(f, 'Position', [40 60 figW figH]);
    set(ax, 'Position', [0.01 0.02 0.98 0.92]);
end

% ===================== glyph helpers =====================
function drawPump(ax, c, rad, label)
    th = linspace(0,2*pi,40);
    plot(ax, c(1)+rad*cos(th), c(2)+rad*sin(th), 'k-','LineWidth',1.2);
    plot(ax, [c(1) c(1)+rad], [c(2) c(2)], 'k-');                 % impeller mark
    if ~isempty(label)
        text(ax, c(1), c(2)-rad-0.18, label,'HorizontalAlignment','center','FontSize',6);
    end
end
function drawTee(ax, x, y, color)
    % DRAWTEE  A real tee glyph: a square fitting on the main line with a short
    %   spur, distinct from the plain circle used for an ordinary junction.
    sgn = 1;  if strcmp(color,'b'), sgn = -1; end   % return main's branch points up
    rectangle(ax,'Position',[x-0.11,y-0.11,0.22,0.22],'Curvature',0, ...
        'FaceColor',color,'EdgeColor','k','LineWidth',1);
    plot(ax,[x x],[y y+sgn*0.32],'-','Color',color,'LineWidth',2);
end
function s = pumpTypeTag(pump)
    if isempty(pump), s = ''; return; end
    switch class(pump)
        case 'DHS.Hydraulic.CentrifugalPump',        s = '(centrifugal)';
        case 'DHS.Hydraulic.FixedDisplacementPump',  s = '(fixed-disp.)';
        otherwise,                                    s = '';
    end
end
function drawValve(ax, c, s)
    plot(ax, c(1)+[-s -s s s -s], c(2)+[-s s -s s -s]*0.7, 'k-','LineWidth',1.2);  % bow-tie
end
function drawHX(ax, c, w, h)
    rectangle(ax,'Position',[c(1)-w/2, c(2)-h/2, w, h],'LineWidth',1.2);
    plot(ax, c(1)+[-w/2 w/2], c(2)+[-h/2 h/2], 'k-');
    plot(ax, c(1)+[-w/2 w/2], c(2)+[ h/2 -h/2], 'k-');
end
function s = ctrlTag(actuator)
    if isempty(actuator.controller)
        s = '';
    else
        c = actuator.controller;
        nm = class(c); nm = nm(find(nm=='.',1,'last')+1:end);
        s = ['[' nm ']'];
    end
end
function lbl = boilerLabel(plant, bi)
    if bi <= numel(plant.boilers)
        b = plant.boilers{bi};
        lbl = sprintf('%s %.0fkW', b.name, b.QMax/1e3);
    else
        lbl = '';
    end
end
