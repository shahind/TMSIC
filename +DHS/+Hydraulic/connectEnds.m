function connectEnds(src, dst, varargin)
%DHS.HYDRAULIC.CONNECTENDS  The one wiring rule behind every connect call.
%   src.connect(dst) makes DST the next component downstream of SRC. Both can be a junction or a tee
%   port (a node), a pipe, valve or pump (a link), or a radiator or building (a terminal that takes
%   water from the supply side and returns it on the return side). Between two links, or a link and
%   a terminal, a node is made on the spot. A radiator can also be connected to a zone, which is the
%   thermal connection: rad.connect(zone, R).
%
%   The connections only record the topology. A link or terminal is added to its hydraulic network
%   as soon as one of its nodes belongs to one, and whatever is left is found by
%   DHS.HydraulicNetwork.discover, starting at the plant, when the network is solved.
    [sk, sNode, sPort] = classify(src);
    [dk, dNode, dPort] = classify(dst);
    if strcmp(sk, 'none') || strcmp(dk, 'none')
        error('DHS:Hydraulic:connect', 'Cannot connect %s to %s.', describe(src), describe(dst));
    end
    switch [sk '>' dk]
        case 'node>link'
            startLink(sNode, sPort, dst);
        case 'node>terminal'
            startTerminal(sNode, sPort, dst);
        case 'link>node'
            assertInlet(dPort, dst);
            endLink(src, dNode);
        case 'link>link'
            J = makeNode(sideAfter(src));
            endLink(src, J);
            startLink(J, '', dst);
        case 'link>terminal'
            J = makeNode(sideAfter(src));
            endLink(src, J);
            startTerminal(J, '', dst);
        case 'terminal>link'
            J = makeNode('return');
            returnTo(src, J);
            startLink(J, '', dst);
        case 'terminal>node'
            assertInlet(dPort, dst);
            returnTo(src, dNode);
        case 'terminal>zone'
            src.connectZone(dst, varargin{:});
        otherwise
            error('DHS:Hydraulic:connect', 'Cannot connect %s to %s.', describe(src), describe(dst));
    end
end

% ---------------------------------------------------------------------------------
function [kind, node, port] = classify(x)
    kind = 'none';  node = [];  port = '';
    if isa(x, 'DHS.Hydraulic.Port')
        kind = 'node';  node = x.node;  port = x.name;
    elseif isa(x, 'DHS.Hydraulic.Junction')
        kind = 'node';  node = x;
    elseif isa(x, 'DHS.Hydraulic.Link')
        kind = 'link';
    elseif ismethod(x, 'branchResistance')
        kind = 'terminal';
    elseif isa(x, 'RCBS.Zone')
        kind = 'zone';
    end
end

function s = describe(x)
    if isobject(x) && isprop(x, 'name'), s = sprintf('%s "%s"', class(x), x.name); else, s = class(x); end
end

function assertInlet(port, dst)
    if ~isempty(port) && ~strcmp(port, 'portA')
        error('DHS:Hydraulic:connect', ...
            '%s.%s leaves the tee: connect INTO the tee (or its portA).', dst.node.name, port);
    end
end

function side = sideAfter(link)
    if isempty(link.nodeA)
        error('DHS:Hydraulic:connect', ...
            'Connect "%s" to a node first (for example tee.portC.connect(link)), then continue the chain.', link.name);
    end
    side = link.nodeA.side;
end

function J = makeNode(side)
    J = DHS.Hydraulic.Junction(DHS.Hydraulic.autoName('node'), side);
end

% ---------------------------------------------------------------------------------
function startLink(node, port, link)
    % the link leaves NODE (through PORT of a tee)
    if ~isempty(link.nodeA) && link.nodeA ~= node
        error('DHS:Hydraulic:connect', '"%s" is already connected to "%s".', link.name, link.nodeA.name);
    end
    node.markStart(port, link);
    link.nodeA = node;
    node.outLinks{end+1} = link;
    if ~isempty(link.nodeB), finishLink(link); end
end

function endLink(link, node)
    if ~isempty(link.nodeB)
        error('DHS:Hydraulic:connect', '"%s" already ends at "%s".', link.name, link.nodeB.name);
    end
    link.nodeB = node;
    node.inLinks{end+1} = link;
    if ~isempty(link.nodeA), finishLink(link); end
end

function finishLink(link)
    sA = link.nodeA.side;  sB = link.nodeB.side;
    if strcmp(sA, 'return') && strcmp(sB, 'supply')
        error('DHS:Hydraulic:connect', '"%s" would run from the return side to the supply side.', link.name);
    end
    net = firstNetwork(link.nodeA, link.nodeB);
    if strcmp(sA, 'supply') && strcmp(sB, 'return')
        % a link between the two sides carries water from supply to return: a branch like a building
        cl = DHS.Hydraulic.CrossLink(link);
        link.nodeA.terminals{end+1} = cl;
        if ~isempty(net), net.connectBuilding(link.nodeA, cl, link.nodeB); end
    elseif ~isempty(net)
        net.registerPipe(link);
    end
end

function startTerminal(node, port, term)
    term.supplyNode = node;
    node.markStart(port, term);
    node.terminals{end+1} = term;
    finishTerminal(term);
end

function returnTo(term, node)
    term.returnNode = node;
    finishTerminal(term);
end

function finishTerminal(term)
    if isempty(term.supplyNode) || isempty(term.returnNode), return, end
    net = firstNetwork(term.supplyNode, term.returnNode);
    if ~isempty(net), net.connectBuilding(term.supplyNode, term, term.returnNode); end
end

function net = firstNetwork(a, b)
    net = [];
    if ~isempty(a) && ~isempty(a.network), net = a.network; end
    if isempty(net) && ~isempty(b) && ~isempty(b.network), net = b.network; end
end
