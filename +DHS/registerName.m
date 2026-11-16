function registerName(owner, part, name)
%DHS.REGISTERNAME  Make a part reachable by its name on its owner: owner.<name>.
%   A name that is not a valid identifier is skipped, a name that a property of the owner already
%   uses is skipped with a warning, and a name used before is re-pointed.
    if nargin < 3, name = part.name; end
    if ~isvarname(name), return, end
    mp = findprop(owner, name);
    if isempty(mp)
        mp = addprop(owner, name);
        owner.(name) = part;
    elseif isa(mp, 'meta.DynamicProperty')
        owner.(name) = part;                              % rebuilt with the same name
    else
        warning('DHS:registerName', ...
            '"%s" is already a property of %s, so the part is not reachable by that name.', name, class(owner));
    end
end
