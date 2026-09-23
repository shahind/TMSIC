%% MULTI_ZONE_SYSTEM_IDENTIFICATION
%  Estimate the thermal parameters of a whole multi-zone building from measured
%  zone temperatures, using an RCBS.Building as the forward model.  Companion to
%  system_identification.m; the workflow is the same, extended to many zones and
%  many outputs.
%
%  The building
%    4 storeys, 2 zones per storey (8 zones), 3500 m2 per storey.
%      - each zone: air node, exterior-wall T-network, window, internal mass;
%      - the top-storey zones also have a roof;
%      - the bottom-storey zones also have a slab-on-grade path to a fixed
%        ground temperature;
%      - the two zones on a storey are joined by a capacitive partition wall;
%      - vertically stacked zones are joined by a capacitive floor slab.
%
%  What is known and what is fitted
%    The GEOMETRY is known: zone floor areas follow from the 3500 m2/storey and
%    the given per-zone volume ratios.  The per-unit THERMAL properties are
%    unknown and fitted separately for each zone (U-values in W/m2K, areal heat
%    capacities kappa in J/m2K, an air-capacitance multiplier), giving
%    75 parameters in total.  Q_in and the solar gains are split between zones
%    in proportion to the volume ratios.
%
%  Input data
%    Two workspace structs, `data` (training) and `data_validation`, each with
%    equal-length column vectors:
%        .t                     time stamps (datetime or seconds), evenly spaced
%        .T_zone1 ... .T_zone8   measured zone air temperatures  [degC]  <- fit targets
%        .T_out                  outdoor air temperature         [degC]
%        .Q_in_data              whole-building heat input        [W]
%    For input_channels 'solar_split' (default) also:
%        .Q_solar_wall  .Q_solar_roof  .Q_solar_window_abs  .Q_solar_window_trans  [W]
%    For 'solar_lumped':  .Q_solar_est .  For 'basic':  none of the solar columns.
%    If the structs are absent, a synthetic train + validation record is
%    generated from a known "true" building so the fit can be graded.
%
%  Runtime: about 2 minutes for the synthetic run.  Zone-temperature-only data
%  pins the fast heat paths (windows, internal mass, air capacitance) well and
%  the slow wall parameters only loosely; the parameter figure shows which.
%
%  Run:  >> multi_zone_system_identification

%% ----------------------------- SETTINGS ---------------------------------
example_dir  = fileparts(mfilename('fullpath'));
project_root = fileparts(example_dir);
addpath(example_dir, project_root);
weather_csv  = fullfile(project_root, 'solar_data_2025.csv');

parameter_scaling    = 'perparam';    % 'perparam' (log for U/kappa, linear for temperatures) | 'linear' | 'log' | 'off'
time_discretisation  = 'exact';       % 'exact' (matrix exponential) | 'euler'
error_metric         = 'MSE';         % SSE | MSE | MAE | RL1 | RL2 | NORM1 | NORM2 | SLOPE | ASYMM | NRMSE
input_channels       = 'solar_split'; % 'solar_split' | 'solar_lumped' | 'basic'
optimizer_iterations = 100;

zone_volume_ratio = [35; 25; 35; 25; 25; 35; 10; 50];   % relative volume of Z1..Z8

%% ------------------------------ MODEL ---------------------------------
model = define_model(parameter_scaling, time_discretisation, input_channels, zone_volume_ratio);

%% ------------------------------- DATA -----------------------------------
if exist('data', 'var') && exist('data_validation', 'var')
    training_data   = data;
    validation_data = data_validation;
    true_parameters = [];
else
    fprintf('No data in the workspace - generating a synthetic record.\n');
    [training_data, validation_data, true_parameters] = make_synthetic_dataset(model, weather_csv);
end

%% --------------------------- OPTIMISATION -----------------------------
fprintf('Fitting the 8-zone model (%d parameters) with fmincon ...\n', model.n_parameters);

cost_of = @(scaled_params) evaluate_cost(scaled_params, model, training_data, error_metric);
solver_options = optimoptions('fmincon', 'Display', 'iter-detailed', ...
    'MaxIterations', optimizer_iterations, 'MaxFunctionEvaluations', 5e5);

[fitted_scaled_params, final_cost] = fmincon( ...
    cost_of, model.initial_guess_scaled, [], [], [], [], ...
    model.lower_bound_scaled, model.upper_bound_scaled, [], solver_options);

fitted_parameters = unscale_parameters(fitted_scaled_params, model);

measured_training    = zone_temperature_matrix(training_data);
measured_validation  = zone_temperature_matrix(validation_data);
predicted_training   = simulate_model(fitted_scaled_params, model, training_data);
predicted_validation = simulate_model(fitted_scaled_params, model, validation_data);

rmse_training        = sqrt(mean((measured_training(:)   - predicted_training(:)).^2));
rmse_validation      = sqrt(mean((measured_validation(:) - predicted_validation(:)).^2));
rmse_validation_zone = sqrt(mean((measured_validation - predicted_validation).^2, 1));

%% ---------------------------- RESULTS --------------------------------
report_results(model, fitted_parameters, true_parameters, ...
    rmse_training, rmse_validation, rmse_validation_zone);

plot_zone_fits(validation_data, model, measured_validation, predicted_validation, rmse_validation_zone);
plot_parameter_recovery(model, fitted_parameters, true_parameters);

%% ----------------------- VISUALISE THE MODEL -------------------------
fitted_building = model.build(fitted_parameters);
fitted_building.visualize();
set(gcf, 'Name', '8-zone identified building');


%% ======================= LOCAL FUNCTIONS ==============================

function model = define_model(scaling, discretisation, input_channels, zone_volume_ratio)
% DEFINE_MODEL  Known geometry + the list of 75 per-unit thermal parameters +
%   a function that builds the 8-zone RCBS.Building from a parameter vector.

    % ----- known geometry -----
    geometry = struct();
    geometry.n_storeys           = 4;
    geometry.storey_area         = 3500;         % m2 per storey (given)
    geometry.storey_height       = 3.6;          % m
    geometry.window_to_wall_ratio = 0.30;
    geometry.wall_area_per_floor_area = 0.60;    % m2 of exterior wall per m2 of zone floor
    geometry.air_heat_capacity_per_volume = 1.2 * 1005;   % rho*cp of air, J/m3/K

    ratio = zone_volume_ratio(:);
    storey_ratio_sum = ratio(1:2:end) + ratio(2:2:end);   % the pair sum on each storey
    geometry.zone_floor_area = zeros(8, 1);
    for zone = 1:8
        geometry.zone_floor_area(zone) = geometry.storey_area * ratio(zone) / storey_ratio_sum(ceil(zone/2));
    end
    geometry.zone_volume       = geometry.zone_floor_area * geometry.storey_height;
    geometry.zone_input_weight = ratio / sum(ratio);                     % how Q_in and solar split between zones
    geometry.top_zone_weight   = [ratio(7) ratio(8)] / (ratio(7) + ratio(8));   % roof-solar split between the two top zones
    geometry.partition_area    = geometry.storey_height * sqrt(geometry.storey_area);
    geometry.slab_area = zeros(6, 1);
    for gap = 1:6
        geometry.slab_area(gap) = min(geometry.zone_floor_area(gap), geometry.zone_floor_area(gap + 2));
    end
    geometry.zone_volume_ratio = ratio;

    % ----- parameter list, built row by row -----
    %   each row: name, lower bound, upper bound, initial guess, scale
    param_table = struct('name', {}, 'lower', {}, 'upper', {}, 'guess', {}, 'scale', {});
    row = @(name, lower, upper, guess, scale) struct('name', name, 'lower', lower, ...
        'upper', upper, 'guess', guess, 'scale', scale);

    for zone = 1:8      % per-zone envelope and mass parameters
        param_table(end+1) = row(sprintf('U_wall_Z%d',    zone), 0.05, 2.0,  0.35,  "log");   %#ok<AGROW>
        param_table(end+1) = row(sprintf('kappa_wall_Z%d', zone), 1e4, 1e6,  1.8e5, "log");   %#ok<AGROW>
        param_table(end+1) = row(sprintf('U_win_Z%d',     zone), 0.5,  6.0,  2.4,   "log");   %#ok<AGROW>
        param_table(end+1) = row(sprintf('U_mass_Z%d',    zone), 0.5,  30,   5.0,   "log");   %#ok<AGROW>
        param_table(end+1) = row(sprintf('kappa_mass_Z%d', zone), 5e3, 5e5,  9.0e4, "log");   %#ok<AGROW>
        param_table(end+1) = row(sprintf('air_cap_mult_Z%d', zone), 1.0, 15, 6.0,   "log");   %#ok<AGROW>
    end
    for zone = [7 8]    % roof parameters, top storey only
        param_table(end+1) = row(sprintf('U_roof_Z%d',     zone), 0.05, 2.0, 0.22,  "log");   %#ok<AGROW>
        param_table(end+1) = row(sprintf('kappa_roof_Z%d', zone), 1e4,  1e6, 9.0e4, "log");   %#ok<AGROW>
    end
    for zone = [1 2]    % ground conductance, bottom storey only
        param_table(end+1) = row(sprintf('U_grnd_Z%d', zone), 0.02, 3.0, 0.40, "log");        %#ok<AGROW>
    end
    param_table(end+1) = row('T_grnd', 5, 18, 11, "linear");    % one shared ground temperature
    for storey = 1:4   % partition wall between the two zones on each storey
        param_table(end+1) = row(sprintf('U_part_S%d',     storey), 0.1, 10,  2.0,   "log");  %#ok<AGROW>
        param_table(end+1) = row(sprintf('kappa_part_S%d', storey), 1e4, 1e6, 2.2e5, "log");  %#ok<AGROW>
    end
    for gap = 1:6      % floor slab between each pair of vertically stacked zones
        param_table(end+1) = row(sprintf('U_slab_%d',     gap), 0.1, 10,  1.4,   "log");      %#ok<AGROW>
        param_table(end+1) = row(sprintf('kappa_slab_%d', gap), 1e4, 1e6, 2.2e5, "log");      %#ok<AGROW>
    end

    model.name             = 'RC 8-zone (4 storeys x 2 zones), per-zone parameters';
    model.parameter_names  = string({param_table.name});
    model.n_parameters     = numel(param_table);
    model.discretisation   = lower(discretisation);
    model.input_channels   = lower(input_channels);
    model.geometry         = geometry;

    % ----- name -> position lookups, so build_topology can address parameters by role -----
    names = model.parameter_names;
    position_of = @(name) find(names == name, 1);
    index = struct();
    for zone = 1:8
        index.U_wall(zone)         = position_of(sprintf("U_wall_Z%d", zone));
        index.kappa_wall(zone)     = position_of(sprintf("kappa_wall_Z%d", zone));
        index.U_win(zone)          = position_of(sprintf("U_win_Z%d", zone));
        index.U_mass(zone)         = position_of(sprintf("U_mass_Z%d", zone));
        index.kappa_mass(zone)     = position_of(sprintf("kappa_mass_Z%d", zone));
        index.air_cap_mult(zone)   = position_of(sprintf("air_cap_mult_Z%d", zone));
    end
    index.U_roof = nan(1,8);  index.kappa_roof = nan(1,8);  index.U_grnd = nan(1,8);
    for zone = [7 8]
        index.U_roof(zone)     = position_of(sprintf("U_roof_Z%d", zone));
        index.kappa_roof(zone) = position_of(sprintf("kappa_roof_Z%d", zone));
    end
    for zone = [1 2]
        index.U_grnd(zone) = position_of(sprintf("U_grnd_Z%d", zone));
    end
    index.T_grnd = position_of("T_grnd");
    for storey = 1:4
        index.U_part(storey)     = position_of(sprintf("U_part_S%d", storey));
        index.kappa_part(storey) = position_of(sprintf("kappa_part_S%d", storey));
    end
    for gap = 1:6
        index.U_slab(gap)     = position_of(sprintf("U_slab_%d", gap));
        index.kappa_slab(gap) = position_of(sprintf("kappa_slab_%d", gap));
    end
    model.index = index;
    model.per_zone_roles = ["U_wall", "kappa_wall", "U_win", "U_mass", "kappa_mass", "air_cap_mult"];

    model.build = @(physical_params) build_topology(physical_params, model.geometry, model.index);

    % ----- scaling: log for U and kappa, linear for the temperature -----
    model.parameter_scale = string({param_table.scale}).';
    switch lower(scaling)
        case 'perparam'   % keep the per-parameter scales above
        case 'linear',    model.parameter_scale(:) = "linear";
        case 'log',       model.parameter_scale(:) = "log";
        case 'off',       model.parameter_scale(:) = "off";
        otherwise
            error('multi_zone_system_identification:unknownScaling', 'Unknown parameter_scaling "%s".', scaling);
    end
    model.lower_bound_physical   = [param_table.lower].';
    model.upper_bound_physical   = [param_table.upper].';
    model.initial_guess_physical = [param_table.guess].';
    model.initial_guess_scaled   = scale_parameters(model.initial_guess_physical, model);
    model.lower_bound_scaled     = scale_parameters(model.lower_bound_physical,   model);
    model.upper_bound_scaled     = scale_parameters(model.upper_bound_physical,   model);
end

% ---------------------------------------------------------------------------
function building = build_topology(physical_params, geometry, index)
% BUILD_TOPOLOGY  Assemble the 8-zone RCBS.Building.  Each zone reads its own
%   U-values and heat capacities; geometry turns them into R and C.

    initial_temp = 18;
    building = RCBS.Building();
    for storey = 1:geometry.n_storeys
        building.addStorey(sprintf('S%d', storey));
    end

    for zone = 1:8
        storey_index = ceil(zone / 2);
        storey = building.(sprintf('S%d', storey_index));
        storey.addZone(sprintf('Z%d', zone));
        rc_zone = storey.(sprintf('Z%d', zone));

        floor_area = geometry.zone_floor_area(zone);
        wall_area  = geometry.wall_area_per_floor_area * floor_area;
        window_area = geometry.window_to_wall_ratio * wall_area;

        air_capacitance = geometry.air_heat_capacity_per_volume * geometry.zone_volume(zone) ...
                          * physical_params(index.air_cap_mult(zone));
        rc_zone.setAir(air_capacitance, initial_temp);

        rc_zone.addWall(1 / (physical_params(index.U_wall(zone)) * wall_area), ...
                        physical_params(index.kappa_wall(zone)) * wall_area, initial_temp, 'Wall');
        rc_zone.addWindow(1 / (physical_params(index.U_win(zone)) * window_area), 'Win');
        rc_zone.addInternalMass(1 / (physical_params(index.U_mass(zone)) * floor_area), ...
                                physical_params(index.kappa_mass(zone)) * floor_area, initial_temp, 'IntMass');
        if storey_index == geometry.n_storeys
            rc_zone.addRoof(1 / (physical_params(index.U_roof(zone)) * floor_area), ...
                            physical_params(index.kappa_roof(zone)) * floor_area, initial_temp, 'Roof');
        end
        % the slab-on-grade path for the bottom-storey zones is added in build_discrete_model
    end

    % partition wall: capacitive coupling between the two zones on each storey
    for storey = 1:geometry.n_storeys
        zone_a = building.(sprintf('S%d', storey)).(sprintf('Z%d', 2*storey - 1));
        zone_b = building.(sprintf('S%d', storey)).(sprintf('Z%d', 2*storey));
        partition_resistance  = 1 / (physical_params(index.U_part(storey)) * geometry.partition_area);
        partition_capacitance = physical_params(index.kappa_part(storey)) * geometry.partition_area;
        zone_a.connectToZone(zone_b, partition_resistance, sprintf('part_S%d', storey), ...
                             partition_capacitance, initial_temp);
    end

    % floor slab: capacitive coupling between each pair of vertically stacked zones
    for gap = 1:6
        lower_storey = ceil(gap / 2);
        zone_below = building.(sprintf('S%d', lower_storey)).(sprintf('Z%d', gap));
        zone_above = building.(sprintf('S%d', lower_storey + 1)).(sprintf('Z%d', gap + 2));
        slab_resistance  = 1 / (physical_params(index.U_slab(gap)) * geometry.slab_area(gap));
        slab_capacitance = physical_params(index.kappa_slab(gap)) * geometry.slab_area(gap);
        zone_below.connectToZone(zone_above, slab_resistance, sprintf('slab_%d_%d', gap, gap+2), ...
                                 slab_capacitance, initial_temp);
    end
end

% ---------------------------------------------------------------------------
function [A_disc, B_disc, C_output, inputs] = build_discrete_model(model, physical_params, record)
% BUILD_DISCRETE_MODEL  8-zone RCBS building -> discrete-time linear model.
%   Input columns:  [T_out, Q_in(->air), Q_solar(->air), Q_solar(->wall), Q_solar(->roof), T_grnd]
%   Output rows: the 8 zone air temperatures Z1..Z8.

    geometry = model.geometry;
    index    = model.index;
    building = model.build(physical_params);
    [continuous_ss, info] = building.simulation.getStateSpace();
    A_continuous = continuous_ss.A;
    B_continuous = continuous_ss.B;
    state_names  = string(info.stateNames);
    n_states     = size(A_continuous, 1);

    air_row  = zeros(8, 1);   wall_row = zeros(8, 1);   roof_row = nan(8, 1);
    for zone = 1:8
        prefix = sprintf("S%d.Z%d.", ceil(zone/2), zone);
        air_row(zone)  = find(state_names == prefix + "T_main", 1);
        wall_row(zone) = find(state_names == prefix + "Wall", 1);
        maybe_roof = find(state_names == prefix + "Roof", 1);
        if ~isempty(maybe_roof), roof_row(zone) = maybe_roof; end
    end

    n_steps = size(zone_temperature_matrix(record), 1);

    % whole-building solar, routed to the nodes each channel physically heats
    switch model.input_channels
        case 'basic'
            solar_to_air = zeros(n_steps, 1);  solar_to_wall = zeros(n_steps, 1);  solar_to_roof = zeros(n_steps, 1);
        case 'solar_lumped'
            solar_to_air  = column_or_zeros(record, 'Q_solar_est', n_steps);
            solar_to_wall = zeros(n_steps, 1);  solar_to_roof = zeros(n_steps, 1);
        case 'solar_split'
            solar_to_air  = column_or_zeros(record, 'Q_solar_window_trans', n_steps);
            solar_to_wall = column_or_zeros(record, 'Q_solar_wall', n_steps) ...
                          + column_or_zeros(record, 'Q_solar_window_abs', n_steps);
            solar_to_roof = column_or_zeros(record, 'Q_solar_roof', n_steps);
        otherwise
            error('multi_zone_system_identification:unknownInput', 'Unknown input_channels "%s".', model.input_channels);
    end

    inputs  = [column_or_zeros(record, 'T_out', n_steps), ...
               column_or_zeros(record, 'Q_in_data', n_steps), ...
               solar_to_air, solar_to_wall, solar_to_roof, zeros(n_steps, 1)];
    B_input = zeros(n_states, 6);
    B_input(:, 1) = B_continuous(:, 1);
    for zone = 1:8
        w = geometry.zone_input_weight(zone);
        B_input(:, 2) = B_input(:, 2) + w * B_continuous(:, 1 + air_row(zone));    % Q_in     -> air
        B_input(:, 3) = B_input(:, 3) + w * B_continuous(:, 1 + air_row(zone));    % air solar -> air
        B_input(:, 4) = B_input(:, 4) + w * B_continuous(:, 1 + wall_row(zone));   % wall solar -> wall node
    end
    if any(~isnan(roof_row))
        B_input(:, 5) = geometry.top_zone_weight(1) * B_continuous(:, 1 + roof_row(7)) ...
                      + geometry.top_zone_weight(2) * B_continuous(:, 1 + roof_row(8));
    end

    % slab-on-grade: bottom-storey zones lose heat to the constant T_grnd
    ground_column = zeros(n_states, 1);
    for zone = 1:2
        air_capacitance    = 1 / B_continuous(air_row(zone), 1 + air_row(zone));
        ground_conductance = physical_params(index.U_grnd(zone)) * geometry.zone_floor_area(zone);
        A_continuous(air_row(zone), air_row(zone)) = A_continuous(air_row(zone), air_row(zone)) ...
                                                     - ground_conductance / air_capacitance;
        ground_column(air_row(zone)) = ground_conductance / air_capacitance;
    end
    inputs(:, 6)  = physical_params(index.T_grnd);
    B_input(:, 6) = ground_column;

    C_output = continuous_ss.C(air_row, :);
    [A_disc, B_disc] = discretise(A_continuous, B_input, time_step_seconds(record.t), model.discretisation);
end

function column = column_or_zeros(record, name, n_steps)
    if isfield(record, name)
        column = record.(name)(:);
    else
        warning('multi_zone_system_identification:missingChannel', ...
            'record has no column "%s"; treated as zero.', name);
        column = zeros(n_steps, 1);
    end
end

function [A_disc, B_disc] = discretise(A_continuous, B_continuous, dt, method)
    switch lower(method)
        case 'exact'       % zero-order hold via the Van Loan block matrix exponential
            n = size(A_continuous, 1);
            m = size(B_continuous, 2);
            block = expm([A_continuous * dt, B_continuous * dt; zeros(m, n + m)]);
            A_disc = block(1:n, 1:n);
            B_disc = block(1:n, n+1:end);
        case 'euler'
            A_disc = eye(size(A_continuous, 1)) + dt * A_continuous;
            B_disc = dt * B_continuous;
        otherwise
            error('multi_zone_system_identification:unknownDiscretisation', 'Unknown discretisation "%s".', method);
    end
end

function dt = time_step_seconds(t)
    if isdatetime(t) || isduration(t)
        dt = seconds(t(2) - t(1));
    else
        dt = t(2) - t(1);
    end
end

% ---------------------------------------------------------------------------
function predicted = simulate_model(scaled_params, model, record)
% SIMULATE_MODEL  Run the 8-zone model over the record and return the predicted
%   zone temperatures (n_steps x 8).  The hidden initial state is recovered by
%   one least-squares fit against all 8 measured zone temperatures at once.

    physical_params = unscale_parameters(scaled_params, model);
    [A_disc, B_disc, C_output, inputs] = build_discrete_model(model, physical_params, record);

    measured = zone_temperature_matrix(record);
    [n_steps, n_outputs] = size(measured);
    n_states = size(A_disc, 1);

    % output_from_x0(k, :, o) is  C_output(o, :) * A_disc^(k-1)
    output_from_x0 = zeros(n_steps, n_states, n_outputs);
    forced_output  = zeros(n_steps, n_outputs);

    observability_row = C_output;          % C_output * A_disc^(k-1)
    forced_state      = zeros(n_states, 1);
    for k = 1:n_steps
        output_from_x0(k, :, :) = permute(observability_row, [3 2 1]);
        forced_output(k, :) = (C_output * forced_state).';
        observability_row = observability_row * A_disc;
        forced_state      = A_disc * forced_state + B_disc * inputs(k, :).';
    end

    % stack the outputs (output first, then time) so the least squares sees one tall system
    stacked_map = reshape(permute(output_from_x0, [1 3 2]), n_steps * n_outputs, n_states);
    residual    = measured - forced_output;
    initial_state = stacked_map \ residual(:);
    predicted   = forced_output + reshape(stacked_map * initial_state, n_steps, n_outputs);
end

function temperatures = zone_temperature_matrix(record)
    temperatures = [record.T_zone1(:), record.T_zone2(:), record.T_zone3(:), record.T_zone4(:), ...
                    record.T_zone5(:), record.T_zone6(:), record.T_zone7(:), record.T_zone8(:)];
end

% ---------------------------------------------------------------------------
function cost = evaluate_cost(scaled_params, model, record, metric)
% EVALUATE_COST  Scalar fit error over all 8 zone temperatures stacked together.

    predicted = simulate_model(scaled_params, model, record);
    measured  = zone_temperature_matrix(record);
    measured  = measured(:);
    predicted = predicted(:);
    residual  = measured - predicted;

    penalty_weight = numel(residual);
    if strcmpi(metric, 'SLOPE'), penalty_weight = 50;  end
    if strcmpi(metric, 'ASYMM'), penalty_weight = 10;  end
    prior_deviation = scaled_params - model.initial_guess_scaled;

    switch upper(string(metric))
        case 'SSE',   cost = sum(residual.^2);
        case 'MSE',   cost = mean(residual.^2);
        case 'MAE',   cost = mean(abs(residual));
        case 'RL2',   cost = sum(residual.^2) + penalty_weight * sum(prior_deviation.^2);
        case 'RL1',   cost = sum(residual.^2) + penalty_weight * sum(abs(prior_deviation));
        case 'NORM1', cost = norm(residual, 2) + norm(scaled_params, 1);
        case 'NORM2', cost = norm(residual, 2) + norm(scaled_params, 2);
        case 'SLOPE'
            rate_residual = diff(measured) - diff(predicted);
            cost = mean(residual(2:end).^2) + penalty_weight * mean(rate_residual.^2);
        case 'ASYMM'
            weight = ones(size(residual));
            weight(predicted > measured) = penalty_weight;
            cost = sum(weight .* residual.^2);
        case 'NRMSE'
            cost = sqrt(mean(residual.^2)) / (max(measured) - min(measured));
        otherwise
            error('multi_zone_system_identification:unknownMetric', 'Unknown error_metric "%s".', metric);
    end
end

% ---------------------------------------------------------------------------
function scaled = scale_parameters(physical, model)
    physical    = physical(:);
    lower_bound = model.lower_bound_physical(:);
    upper_bound = model.upper_bound_physical(:);
    scaled      = zeros(size(physical));
    for p = 1:numel(physical)
        switch model.parameter_scale(p)
            case "log"
                scaled(p) = (log(physical(p)) - log(lower_bound(p))) / (log(upper_bound(p)) - log(lower_bound(p)));
            case "linear"
                scaled(p) = (physical(p) - lower_bound(p)) / (upper_bound(p) - lower_bound(p));
            case "off"
                scaled(p) = physical(p);
        end
    end
end

function physical = unscale_parameters(scaled, model)
    scaled      = scaled(:);
    lower_bound = model.lower_bound_physical(:);
    upper_bound = model.upper_bound_physical(:);
    physical    = zeros(size(scaled));
    for p = 1:numel(scaled)
        switch model.parameter_scale(p)
            case "log"
                physical(p) = exp(log(lower_bound(p)) + scaled(p) * (log(upper_bound(p)) - log(lower_bound(p))));
            case "linear"
                physical(p) = lower_bound(p) + scaled(p) * (upper_bound(p) - lower_bound(p));
            case "off"
                physical(p) = scaled(p);
        end
    end
end

% ---------------------------------------------------------------------------
function report_results(model, fitted_parameters, true_parameters, ...
        rmse_training, rmse_validation, rmse_validation_zone)

    fprintf('\n===== 8-zone identification summary (%d parameters) =====\n', model.n_parameters);
    fprintf('  training RMSE   : %.4f degC\n', rmse_training);
    fprintf('  validation RMSE : %.4f degC\n', rmse_validation);
    fprintf('  per-zone validation RMSE [degC]: %s\n\n', strjoin(compose('%.3f', rmse_validation_zone), '  '));

    roles = model.per_zone_roles;
    header = sprintf('  %-4s', 'zone');
    for r = 1:numel(roles), header = [header sprintf(' %14s', roles(r))]; end %#ok<AGROW>
    fprintf('%s\n', header);
    for zone = 1:8
        line = sprintf('  Z%-3d', zone);
        for r = 1:numel(roles)
            fitted_value = fitted_parameters(model.index.(roles(r))(zone));
            if ~isempty(true_parameters)
                true_value = true_parameters(model.index.(roles(r))(zone));
                line = [line sprintf(' %+13.1f%%', 100 * (fitted_value - true_value) / abs(true_value))]; %#ok<AGROW>
            else
                line = [line sprintf(' %14.4g', fitted_value)]; %#ok<AGROW>
            end
        end
        fprintf('%s\n', line);
    end
    if ~isempty(true_parameters)
        relative_error_pct = 100 * abs(fitted_parameters(:) - true_parameters(:)) ./ abs(true_parameters(:));
        fprintf('\n  median |relative error| over all %d parameters: %.1f %%  (max %.0f %%)\n\n', ...
            model.n_parameters, median(relative_error_pct), max(relative_error_pct));
    else
        fprintf('\n');
    end
end

% ---------------------------------------------------------------------------
function plot_zone_fits(validation_data, model, measured, predicted, rmse_per_zone)
    blue = [0 0.45 0.74];
    figure('Name', '8-zone identification: validation fit', 'Color', 'w', 'Position', [60 60 1180 820]);
    layout = tiledlayout(4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(layout, 'Held-out validation: measured (black) vs identified 8-zone RCBS model', 'FontWeight', 'bold');
    for zone = 1:8
        nexttile;  hold on;  grid on;  box on;
        plot(validation_data.t, measured(:, zone),  'k-', 'LineWidth', 1.2);
        plot(validation_data.t, predicted(:, zone), '-', 'Color', blue, 'LineWidth', 1.0);
        title(sprintf('Z%d   (volume ratio %d,  RMSE %.2f \\circC)', zone, ...
            model.geometry.zone_volume_ratio(zone), rmse_per_zone(zone)), 'FontSize', 9);
        if zone >= 7, xlabel('time'); end
        ylabel('T  [\circC]');
    end
end

% ---------------------------------------------------------------------------
function plot_parameter_recovery(model, fitted_parameters, true_parameters)
    blue   = [0 0.45 0.74];
    orange = [0.85 0.33 0.10];
    figure('Name', '8-zone identification: parameters', 'Color', 'w', 'Position', [80 80 1150 460]);
    tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    % left panel: per-zone parameters as an 8 x 6 grid
    roles = model.per_zone_roles;
    grid_values = zeros(8, numel(roles));
    for zone = 1:8
        for r = 1:numel(roles)
            fitted_value = fitted_parameters(model.index.(roles(r))(zone));
            if ~isempty(true_parameters)
                true_value = true_parameters(model.index.(roles(r))(zone));
                grid_values(zone, r) = 100 * (fitted_value - true_value) / abs(true_value);
            else
                grid_values(zone, r) = fitted_value;
            end
        end
    end
    nexttile;  imagesc(grid_values);
    set(gca, 'XTick', 1:numel(roles), 'XTickLabel', cellstr(roles), 'XTickLabelRotation', 25, ...
        'YTick', 1:8, 'YTickLabel', compose('Z%d', 1:8), 'FontSize', 8);
    colour_bar = colorbar;
    if ~isempty(true_parameters)
        title('per-zone parameter error  [%]  (fitted - true)/|true|');
        colour_bar.Label.String = '%';
        limit = max(30, ceil(max(abs(grid_values(:)))));
        clim([-limit limit]);
        colormap(gca, blue_white_red(256));
    else
        title('per-zone parameter values');
        set(gca, 'ColorScale', 'log');
    end

    % right panel: the coupling / roof / ground parameters
    coupling_index = [model.index.U_roof(7), model.index.U_roof(8), ...
                      model.index.kappa_roof(7), model.index.kappa_roof(8), ...
                      model.index.U_grnd(1), model.index.U_grnd(2), model.index.T_grnd, ...
                      model.index.U_part(:).', model.index.kappa_part(:).', ...
                      model.index.U_slab(:).', model.index.kappa_slab(:).'];
    coupling_labels = [ "U_roof_Z7", "U_roof_Z8", "kappa_roof_Z7", "kappa_roof_Z8", ...
                        "U_grnd_Z1", "U_grnd_Z2", "T_grnd", ...
                        compose("U_part_S%d", 1:4), compose("kappa_part_S%d", 1:4), ...
                        compose("U_slab_%d", 1:6), compose("kappa_slab_%d", 1:6) ];
    fitted_coupling = fitted_parameters(coupling_index);

    nexttile;  hold on;  grid on;  box on;
    if ~isempty(true_parameters)
        relative_error_pct = 100 * (fitted_coupling(:) - true_parameters(coupling_index(:))) ...
                                   ./ abs(true_parameters(coupling_index(:)));
        bars = bar(relative_error_pct, 0.7, 'FaceColor', 'flat', 'EdgeColor', 'none');
        bars.CData = repmat(blue, numel(relative_error_pct), 1);
        bars.CData(abs(relative_error_pct) > 50, :) = repmat(orange, nnz(abs(relative_error_pct) > 50), 1);
        ylabel('(fitted - true) / |true|   [%]');
        title('coupling / roof / ground parameters: recovery error');
    else
        bar(fitted_coupling(:), 0.7, 'FaceColor', blue, 'EdgeColor', 'none');
        set(gca, 'YScale', 'log');
        ylabel('fitted value');
        title('coupling / roof / ground parameters');
    end
    set(gca, 'XTick', 1:numel(coupling_labels), 'XTickLabel', cellstr(coupling_labels), ...
        'XTickLabelRotation', 40, 'FontSize', 7);
    xlim([0.4 numel(coupling_labels) + 0.6]);
end

function colours = blue_white_red(n)
    if nargin < 1, n = 256; end
    half = floor(n / 2);
    ramp_up   = linspace(0, 1, half).';
    ramp_down = linspace(1, 0, n - half).';
    colours = [ [ramp_up*0.85 + 0.10, ramp_up*0.85 + 0.10, ones(half,1)*0.95] ; ...
                [ones(n-half,1)*0.95, ramp_down*0.80 + 0.10, ramp_down*0.80 + 0.10] ];
end

% ---------------------------------------------------------------------------
function [training_data, validation_data, true_parameters] = make_synthetic_dataset(model, weather_csv)
% MAKE_SYNTHETIC_DATASET  Generate a train + validation record from a known
%   8-zone building (the nominal parameters, jittered independently per
%   parameter) driven by real Kelowna weather + a random whole-building heating
%   signal + 0.12 degC of per-zone sensor noise.

    rng(11);

    % the "true" parameters: nominal values with a per-parameter random jitter
    true_parameters = model.initial_guess_physical;
    for p = 1:model.n_parameters
        if model.parameter_scale(p) == "log"
            true_parameters(p) = true_parameters(p) * exp(0.25 * randn);
        else
            true_parameters(p) = true_parameters(p) * (1 + 0.12 * randn);
        end
    end
    true_parameters = min(max(true_parameters, model.lower_bound_physical * 1.001), ...
                                               model.upper_bound_physical * 0.999);

    sample_step = minutes(15);
    if isfile(weather_csv)
        weather    = DHS.Weather(weather_csv);
        start_time = weather.timeVector();
        start_time = start_time(1) + days(6);
        time       = (start_time : sample_step : start_time + days(20)).';
        sampled    = weather.atVec(time);
        outdoor_temp = sampled.Tout;
        irradiance   = sampled.ghi;
    else
        warning('multi_zone_system_identification:noWeather', 'weather file not found - using a sinusoidal climate.');
        time = (datetime(2025,1,6) : sample_step : datetime(2025,1,6) + days(20)).';
        hour_of_day = hours(time - dateshift(time, 'start', 'day'));
        outdoor_temp = -3 + 6*sin(2*pi*(hour_of_day - 8)/24) + 2.5*sin(2*pi*days(time - time(1))/8);
        irradiance   = max(0, 520*sin(pi*max(0, hour_of_day - 7)/10)) .* (hour_of_day > 7 & hour_of_day < 17);
    end
    n_steps = numel(time);

    % whole-building heating: a random staircase plus a morning boost
    staircase   = cumsum(randn(ceil(n_steps/20), 1));
    staircase   = interp1(linspace(1, n_steps, numel(staircase)), staircase, 1:n_steps, 'previous', 'extrap').';
    staircase   = 4.5e4 + 1.6e5 * (staircase - min(staircase)) / max(max(staircase) - min(staircase), eps);
    hour_of_day = hours(time - dateshift(time, 'start', 'day'));
    heat_input  = max(0, staircase + 1.2e5 * max(0, sin(2*pi*(hour_of_day - 6)/24)) - 6e4);

    geometry     = model.geometry;
    total_wall_area   = geometry.wall_area_per_floor_area * sum(geometry.zone_floor_area);
    total_window_area = geometry.window_to_wall_ratio * total_wall_area;
    total_roof_area   = geometry.zone_floor_area(7) + geometry.zone_floor_area(8);
    solar_wall          = 0.020 * total_wall_area   * irradiance;   % opaque-wall sol-air   [W]
    solar_roof          = 0.030 * total_roof_area   * irradiance;   % roof sol-air          [W]
    solar_window_abs    = 0.05  * total_window_area * irradiance;   % absorbed in the glass [W]
    solar_window_trans  = 0.14  * total_window_area * irradiance;   % transmitted into rooms[W]

    driving_record = struct('t', time, 'T_out', outdoor_temp, 'Q_in_data', heat_input, ...
        'Q_solar_wall', solar_wall, 'Q_solar_roof', solar_roof, ...
        'Q_solar_window_abs', solar_window_abs, 'Q_solar_window_trans', solar_window_trans);
    for zone = 1:8
        driving_record.(sprintf('T_zone%d', zone)) = zeros(n_steps, 1);
    end

    [A_disc, B_disc, C_output, inputs] = build_discrete_model(model, true_parameters, driving_record);
    state = 12 * ones(size(A_disc, 1), 1);
    clean_zone_temp = zeros(n_steps, 8);
    for k = 1:n_steps
        clean_zone_temp(k, :) = (C_output * state).';
        state = A_disc * state + B_disc * inputs(k, :).';
    end
    zone_temp = clean_zone_temp + 0.12 * randn(n_steps, 8);

    is_training = time < time(1) + days(13);   % first 13 days for training
    make_record = @(mask) build_record(time(mask), outdoor_temp(mask), heat_input(mask), ...
        solar_wall(mask), solar_roof(mask), solar_window_abs(mask), solar_window_trans(mask), zone_temp(mask, :));
    training_data   = make_record(is_training);
    validation_data = make_record(~is_training);
end

function record = build_record(time, outdoor_temp, heat_input, solar_wall, solar_roof, ...
        solar_window_abs, solar_window_trans, zone_temp)
    record = struct('t', time, 'T_out', outdoor_temp(:), 'Q_in_data', heat_input(:), ...
        'Q_solar_wall', solar_wall(:), 'Q_solar_roof', solar_roof(:), ...
        'Q_solar_window_abs', solar_window_abs(:), 'Q_solar_window_trans', solar_window_trans(:));
    for zone = 1:8
        record.(sprintf('T_zone%d', zone)) = zone_temp(:, zone);
    end
end
