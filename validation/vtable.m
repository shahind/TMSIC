function passed = vtable(name, C)
%VTABLE  Print a validation comparison table and return an overall PASS/FAIL.
%
%   passed = vtable(name, C)
%     name : char, the validation block title
%     C    : struct array, one element per comparison, with fields
%              .label     char
%              .expected  scalar (analytical / published reference value)
%              .actual    scalar (value produced by the component)
%              .tol       scalar tolerance
%              .kind      'rel' (default) | 'abs'  -- how tol and the error are measured
%
%   Used by every validation/validate_*.m so the reports have one format.

    fprintf('\n  %-46s %13s %13s %11s        \n', 'case', 'expected', 'actual', 'error');
    fprintf('  %s\n', repmat('-', 1, 96));
    passed = true;
    for i = 1:numel(C)
        e = C(i).expected;  a = C(i).actual;
        kind = 'rel';
        if isfield(C(i),'kind') && ~isempty(C(i).kind), kind = C(i).kind; end
        if strcmp(kind,'abs')
            err = abs(a - e);
        else
            err = abs(a - e) / max(abs(e), eps);
        end
        ok = err <= C(i).tol;
        passed = passed && ok;
        tag = 'ok  ';  if ~ok, tag = 'FAIL'; end
        fprintf('  %-46s %13.6g %13.6g %11.2e %s (%s, tol %.1e)\n', ...
                C(i).label, e, a, err, tag, kind, C(i).tol);
    end
    fprintf('  %s\n', repmat('-', 1, 96));
    if passed, v = 'PASS'; else, v = 'FAIL'; end
    fprintf('  [%s] %s\n', v, name);
end
