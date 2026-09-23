function vplot(fname, panels, mode)
%VPLOT  Standard "expected versus component output" figure for a validation check.
%
%   vplot(fname, panels)            show the figure and save it as a PNG
%   vplot(fname, panels, 'save')    save the PNG and close the window
%   vplot(fname, panels, 'none')    do nothing (skip plotting)
%
%   Every validate_*.m calls this once. The figure contains one or two panels,
%   and each panel shows only two things: the value the reference predicts
%   (grey, dashed, drawn thick underneath) and the value the component produced
%   (coloured, drawn on top). Agreement appears as the coloured line lying on
%   top of the grey one. The PNG is written to validation/figures/<fname>.png.
%
%   panels  cell array of panel structs (at most two are laid out per row):
%     .title  .xlabel  .ylabel   char
%     .xscale .yscale            'linear' (default) | 'log'
%     .legendLoc                 passed to legend()
%     .kind                      'xy' (default) | 'bars'
%
%   kind = 'xy'    .series : cell of structs with fields
%       .x, .y     numeric vectors (.x optional)
%       .name      legend text ('' hides the entry)
%       .style     'ref'       expected curve  (grey, dashed)
%                  'sim'       component output curve (solid, coloured)
%                  'refpoint'  expected values as open circles
%                  'point'     component output values as filled circles
%
%   kind = 'bars'  .labels (cellstr), .expected, .actual, optional .legendNames
%                  One pair of bars per label: expected (grey) next to the
%                  component output (blue).

    if nargin < 3 || isempty(mode), mode = 'show'; end
    if strcmpi(mode, 'none'), return; end

    np   = numel(panels);
    ncol = min(np, 2);
    nrow = ceil(np / ncol);

    vis = 'on';  if strcmpi(mode, 'save'), vis = 'off'; end
    f = figure('Visible', vis, 'Color', 'w', 'Name', fname, ...
               'Position', [70 70 560*ncol 420*nrow]);
    tl = tiledlayout(f, nrow, ncol, 'TileSpacing', 'compact', 'Padding', 'compact');

    for i = 1:np
        P  = panels{i};
        ax = nexttile(tl);  hold(ax, 'on');  grid(ax, 'on');  box(ax, 'on');
        set(ax, 'FontSize', 10, 'GridAlpha', 0.15, 'MinorGridAlpha', 0.08);
        kind = 'xy';  if isfield(P,'kind') && ~isempty(P.kind), kind = P.kind; end
        if strcmpi(kind, 'bars'), drawBars(ax, P); else, drawXY(ax, P); end
        if isfield(P,'xscale') && ~isempty(P.xscale), set(ax,'XScale',P.xscale); end
        if isfield(P,'yscale') && ~isempty(P.yscale), set(ax,'YScale',P.yscale); end
        if isfield(P,'title')  && ~isempty(P.title),  title(ax, P.title, 'FontWeight', 'bold', 'FontSize', 10); end
        if isfield(P,'xlabel') && ~isempty(P.xlabel), xlabel(ax, P.xlabel); end
        if isfield(P,'ylabel') && ~isempty(P.ylabel), ylabel(ax, P.ylabel); end
    end

    figdir = fullfile(fileparts(mfilename('fullpath')), 'figures');
    if ~exist(figdir, 'dir'), mkdir(figdir); end
    png = fullfile(figdir, [fname '.png']);
    try
        exportgraphics(f, png, 'Resolution', 140);
    catch
        try, saveas(f, png); catch, end
    end
    if strcmpi(mode, 'save'), close(f); end
end

% -------------------------------------------------------------------------
function drawXY(ax, P)
    cSim  = [0.00 0.45 0.74];
    cRef  = [0.35 0.35 0.35];
    palette = [0.00 0.45 0.74; 0.85 0.33 0.10; 0.47 0.67 0.19; 0.49 0.18 0.56];
    S = P.series;  h = [];  leg = {};  iSim = 0;
    nSim = 0;
    for k = 1:numel(S)
        st = 'sim'; if isfield(S{k},'style') && ~isempty(S{k}.style), st = S{k}.style; end
        if any(strcmpi(st, {'sim','point'})), nSim = nSim + 1; end
    end
    % expected first so the component output is drawn on top of it
    order = [find(cellfun(@(s) any(strcmpi(getStyle(s), {'ref','refpoint'})), S)), ...
             find(cellfun(@(s) ~any(strcmpi(getStyle(s), {'ref','refpoint'})), S))];
    for k = order
        s = S{k};  style = lower(getStyle(s));
        y = s.y(:);
        if isfield(s,'x') && ~isempty(s.x), x = s.x(:); else, x = (1:numel(y)).'; end
        name = ''; if isfield(s,'name'), name = s.name; end
        switch style
            case 'ref'
                hh = plot(ax, x, y, '--', 'Color', cRef, 'LineWidth', 3.2);
                hh.Color(4) = 0.55;
                if ~isempty(name), name = ['Expected: ' name]; end
            case 'refpoint'
                hh = plot(ax, x, y, 'o', 'MarkerFaceColor', 'w', 'MarkerEdgeColor', cRef, ...
                    'MarkerSize', 10, 'LineWidth', 1.8, 'LineStyle', 'none');
                if ~isempty(name), name = ['Expected: ' name]; end
            case 'point'
                iSim = iSim + 1;
                col = cSim; if nSim > 1, col = palette(mod(iSim-1,size(palette,1))+1,:); end
                hh = plot(ax, x, y, 'o', 'MarkerFaceColor', col, 'MarkerEdgeColor', col, ...
                    'MarkerSize', 5, 'LineStyle', 'none');
                if ~isempty(name), name = ['Output: ' name]; end
            otherwise
                iSim = iSim + 1;
                col = cSim; if nSim > 1, col = palette(mod(iSim-1,size(palette,1))+1,:); end
                hh = plot(ax, x, y, '-', 'Color', col, 'LineWidth', 1.6);
                if ~isempty(name), name = ['Output: ' name]; end
        end
        if ~isempty(name), h(end+1) = hh; leg{end+1} = name; end %#ok<AGROW>
    end
    if ~isempty(leg)
        loc = 'best';  if isfield(P,'legendLoc') && ~isempty(P.legendLoc), loc = P.legendLoc; end
        legend(ax, h, leg, 'Location', loc, 'FontSize', 8, 'Box', 'off');
    end
end

function st = getStyle(s)
    st = 'sim';  if isfield(s,'style') && ~isempty(s.style), st = s.style; end
end

% -------------------------------------------------------------------------
function drawBars(ax, P)
    cExp = [0.72 0.72 0.72];  cSim = [0.00 0.45 0.74];
    lab = P.labels(:).';
    e = P.expected(:).';  a = P.actual(:).';
    n = numel(lab);
    b = bar(ax, 1:n, [e; a].', 0.8);
    b(1).FaceColor = cExp;  b(1).EdgeColor = 'none';
    b(2).FaceColor = cSim;  b(2).EdgeColor = 'none';
    ln = {'Expected', 'Component output'};
    if isfield(P,'legendNames') && ~isempty(P.legendNames), ln = P.legendNames; end
    legend(ax, ln, 'Location', 'northoutside', 'Orientation', 'horizontal', 'FontSize', 8, 'Box', 'off');
    set(ax, 'XTick', 1:n, 'XTickLabel', lab, 'XTickLabelRotation', 20, 'FontSize', 9);
    xlim(ax, [0.4 n+0.6]);
end
