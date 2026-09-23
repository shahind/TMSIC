function results = run_all_validation(plotMode)
%RUN_ALL_VALIDATION  Run every validation/validate_*.m and print a summary.
%
%   Each validate_*.m compares a component of the model against an analytical
%   solution, a published correlation, an independent solver, or an exact
%   conservation law, prints a per-case table, and writes a comparison figure
%   to validation/figures/<name>.png. This driver runs them all and returns a
%   struct array with each block's name, PASS/FAIL and cases.
%
%   run_all_validation            regenerate every figure PNG (windows stay closed)
%   run_all_validation('show')    also leave every figure open
%   run_all_validation('none')    skip plotting entirely (fastest)
%
%   See validation/README.md for the scientific rationale and references of
%   each test.

    if nargin < 1 || isempty(plotMode), plotMode = 'save'; end
    here = fileparts(mfilename('fullpath'));
    addpath(here, fileparts(here));

    names = { ...
        'validate_rc_zone', ...
        'validate_wall_tnetwork', ...
        'validate_interzone_slab', ...
        'validate_bdf_solver', ...
        'validate_building_energy_balance', ...
        'validate_heat_exchanger', ...
        'validate_pump', ...
        'validate_fixed_displacement_pump', ...
        'validate_valve', ...
        'validate_pipe_friction', ...
        'validate_tjunction', ...
        'validate_hydraulic_network', ...
        'validate_pid', ...
        'validate_lqr', ...
        'validate_plant_dynamics', ...
        'validate_solar_poa', ...
        'validate_schedule', ...
        'validate_desBuilding' };

    results = struct('name',{},'passed',{},'cases',{});
    fprintf('\n############### MODEL VALIDATION SUITE ###############\n');
    for i = 1:numel(names)
        fprintf('\n>>> %s\n', names{i});
        try
            V = feval(names{i}, plotMode);
        catch ME
            fprintf(2, '  ERROR: %s\n', ME.message);
            V = struct('name',names{i},'passed',false,'cases',struct([]));
        end
        results(i) = struct('name',V.name,'passed',V.passed,'cases',V.cases);
    end

    fprintf('\n############### SUMMARY ###############\n');
    np = 0;
    for i = 1:numel(results)
        tag = 'PASS'; if ~results(i).passed, tag = 'FAIL'; np = np + 1; end
        fprintf('  [%s]  %-40s  %s\n', tag, names{i}, results(i).name);
    end
    if np == 0
        fprintf('\n  ALL %d VALIDATION BLOCKS PASSED\n\n', numel(results));
    else
        fprintf('\n  %d of %d VALIDATION BLOCKS FAILED\n\n', np, numel(results));
    end
end
