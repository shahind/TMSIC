function setup()
%SETUP  Put the Thermal Modeling for System Identification and Control Toolbox
%   on the MATLAB path for this session.
%
%   >> setup
%
%   Adds the toolbox root (for the +RCBS and +DHS packages) plus the examples,
%   tests and validation folders.

    toolbox_root = fileparts(mfilename('fullpath'));
    addpath(toolbox_root);
    addpath(fullfile(toolbox_root, 'examples'));
    addpath(fullfile(toolbox_root, 'tests'));
    addpath(fullfile(toolbox_root, 'validation'));

    fprintf('Thermal Modeling for System Identification and Control Toolbox is on the path.\n');
    fprintf('  examples : RCBS_example, dhs_campus, dhs_campus_multizone,\n');
    fprintf('             system_identification, multi_zone_system_identification\n');
    fprintf('  tests    : runtests(''tests'')\n');
    fprintf('  checks   : run(''validation/run_all_validation'')\n');
end
