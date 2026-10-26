function p = stoppedPump()
%DHS.HYDRAULIC.STOPPEDPUMP  The pump of a branch that has none: stopped, so it adds no head and no resistance.
    persistent pump
    if isempty(pump)
        pump = DHS.Hydraulic.CentrifugalPump('none', 'speed', 0);
    end
    p = pump;
end
