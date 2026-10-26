function out = addOn(src, kind, varargin)
%DHS.HYDRAULIC.ADDON  Create a component and connect it downstream of SRC (the add* calls).
%   Behind  tee.portC.addPipe(D, L)  and  pipe.addValve('Kvs',4)  and  rad.addPipe(D, L)  and so on.
%   KIND is 'pipe', 'valve', 'pump', 'tee', 'radiator' or 'junction'. On a tee, a leading port name
%   ('portB' or 'portC') says which port the new component leaves from (portB when omitted).
    port = '';
    if ~isempty(varargin) && (ischar(varargin{1}) || isstring(varargin{1})) ...
            && any(strcmpi(char(varargin{1}), {'portA','portB','portC'}))
        port = char(varargin{1});  varargin(1) = [];
    end
    switch kind
        case 'pipe'                                   % addPipe(D, L, name-value pairs)
            [num, nv] = leadingNumbers(varargin, 2);
            out = DHS.Hydraulic.Pipe(DHS.Hydraulic.autoName('pipe'));
            if numel(num) >= 1, out.D = num(1); end
            if numel(num) >= 2, out.L = num(2); end
            setProps(out, nv);
        case 'valve'                                  % addValve(name-value pairs)
            out = DHS.Hydraulic.Valve(DHS.Hydraulic.autoName('valve'));
            setProps(out, varargin);
        case 'pump'                                   % addPump(name-value pairs)
            out = DHS.Hydraulic.CentrifugalPump(DHS.Hydraulic.autoName('pump'));
            setProps(out, varargin);
        case 'tee'                                    % addTee(sideD) on a pipe, addTee(mainD, sideD) elsewhere
            if isa(src, 'DHS.Hydraulic.Pipe'), nNum = 1; else, nNum = 2; end
            [num, nv] = leadingNumbers(varargin, nNum);
            out = DHS.Hydraulic.TJunction(DHS.Hydraulic.autoName('tee'));
            if isa(src, 'DHS.Hydraulic.Pipe')
                out.mainDiameter = src.D;
                if numel(num) >= 1, out.sideDiameter = num(1); end
            else
                if numel(num) >= 1, out.mainDiameter = num(1); end
                if numel(num) >= 2, out.sideDiameter = num(2); end
            end
            setProps(out, nv);
        case 'radiator'                               % addRadiator(name, name-value pairs)
            nm = DHS.Hydraulic.autoName('radiator');
            if ~isempty(varargin) && (ischar(varargin{1}) || isstring(varargin{1})) && mod(numel(varargin), 2) == 1
                nm = char(varargin{1});  varargin(1) = [];
            end
            out = DHS.Radiator(nm, varargin{:});
        case 'junction'                               % addJunction(name)
            side = 'supply';
            if isa(src, 'DHS.Hydraulic.Link') && ~isempty(src.nodeA), side = src.nodeA.side; end
            if isa(src, 'DHS.Radiator') || ismethod(src, 'branchResistance'), side = 'return'; end
            nm = DHS.Hydraulic.autoName('node');
            if ~isempty(varargin), nm = char(varargin{1}); end
            out = DHS.Hydraulic.Junction(nm, side);
        otherwise
            error('DHS:Hydraulic:addOn', 'Unknown component "%s".', kind);
    end
    if ~isempty(port) && (isa(src, 'DHS.Hydraulic.Junction'))
        src = src.(port);
    end
    DHS.Hydraulic.connectEnds(src, out);
end

function [num, rest] = leadingNumbers(args, maxN)
    num = [];
    while numel(args) >= 1 && numel(num) < maxN && isnumeric(args{1}) && isscalar(args{1})
        num(end+1) = args{1};  args(1) = []; %#ok<AGROW>
    end
    rest = args;
end

function setProps(obj, nv)
    for i = 1:2:numel(nv), obj.(nv{i}) = nv{i+1}; end
end
