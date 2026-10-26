function name = autoName(kind)
%DHS.HYDRAULIC.AUTONAME  A fresh name for a component made without one: 'pipe_1', 'valve_2', ...
    persistent n
    if isempty(n), n = 0; end
    n = n + 1;
    name = sprintf('%s_%d', kind, n);
end
