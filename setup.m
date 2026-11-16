function setup()
%SETUP  Put the TMSIC toolbox on the MATLAB path for this session.
%
%   >> setup
%
%   Adds the toolbox root (for the +RCBS and +DHS packages) and the examples,
%   tests and validation folders.

    toolbox_root = fileparts(mfilename('fullpath'));
    addpath(toolbox_root);
    addpath(fullfile(toolbox_root, 'examples'));
    addpath(fullfile(toolbox_root, 'tests'));
    addpath(fullfile(toolbox_root, 'validation'));

    fprintf('TMSIC is on the path.\n');
    fprintf('  tutorials : rcbs_tutorial, dhs_tutorial, dhs_internal_loop_tutorial\n');
    fprintf('  examples  : see docs/examples.md\n');
    fprintf('  tests     : runtests(''tests'')\n');
    fprintf('  checks    : run_all_validation\n');
end
