%% SYSTEM_IDENTIFICATION
%  Estimate the thermal R and C parameters of a single-zone building from a
%  measured temperature record, using an RCBS.Building as the forward model.
%
%  Workflow
%    1. pick a model topology (how many R and C elements, how they connect);
%    2. build that topology as an RCBS.Building and export its state-space form;
%    3. simulate it over the measured inputs and compare with the measured
%       indoor temperature;
%    4. let fmincon adjust the R/C parameters until the simulated temperature
%       matches the measurement, on a training slice of the data;
%    5. check the fitted model on a held-out validation slice.
%
%  The hidden initial temperatures of the internal nodes are NOT parameters:
%  for a linear model they are recovered exactly by least squares on each
%  record, so only the physical R/C values are searched.
%
%  Input data
%    The script looks for two structs in the workspace, `data` (training) and
%    `data_validation`, each with equal-length column vectors:
%        .t          time stamps (datetime or seconds), evenly spaced
%        .T_in       measured indoor air temperature   [degC]   <- fit target
%        .T_out      outdoor air temperature           [degC]
%        .Q_in_data  measured heat delivered to the room [W]
%    With `input_channels` set to 'solar_lumped' or 'solar_split' the records
%    must also carry the matching Q_solar_* columns (see below).
%    If those structs are absent, a synthetic train + validation record is
%    generated from a known "true" building so the fit can be graded.
%
%  Run:  >> system_identification

%% ----------------------------- SETTINGS -----------------------------------
example_dir  = fileparts(mfilename('fullpath'));
project_root = fileparts(example_dir);
addpath(example_dir, project_root);
weather_csv  = fullfile(project_root, 'solar_data_2025.csv');

model_topology      = 'R5C4';   % R1C1 | R2C2 | R4C4 | R4C5 | R5C4  (append '-MAD' to add a measured air-side heat channel)
parameter_scaling   = 'perparam';   % 'perparam' (log for R/C, linear for temperatures) | 'linear' | 'log' | 'off'
time_discretisation = 'exact';      % 'exact' (matrix-exponential, always stable) | 'euler'
error_metric        = 'MSE';        % SSE | MSE | MAE | RL1 | RL2 | NORM1 | NORM2 | SLOPE | ASYMM | NRMSE
input_channels      = 'basic';      % 'basic' (T_out + Q_in) | 'solar_lumped' | 'solar_split'
optimizer_iterations = 200;

%% ------------------------------- DATA -----------------------------------
model = define_model(model_topology, parameter_scaling, time_discretisation, input_channels);

if exist('data', 'var') && exist('data_validation', 'var')
    training_data   = data;
    validation_data = data_validation;
    true_parameters = [];                   % real measurements: no ground truth to compare against
else
    fprintf('No data in the workspace - generating a synthetic record.\n');
    [training_data, validation_data, true_parameters] = make_synthetic_dataset(model, weather_csv);
end

cost_of  = @(scaled_params) evaluate_cost(scaled_params, model, training_data, error_metric);

%% --------------------------- OPTIMISATION -----------------------------
fprintf('Fitting %s (%d parameters) with fmincon ...\n', model.name, model.n_parameters);

solver_options = optimoptions('fmincon', 'Display', 'iter-detailed', ...
    'MaxIterations', optimizer_iterations, 'MaxFunctionEvaluations', 5e5);

[fitted_scaled_params, final_cost] = fmincon( ...
    cost_of, model.initial_guess_scaled, [], [], [], [], ...
    model.lower_bound_scaled, model.upper_bound_scaled, [], solver_options);

fitted_parameters = unscale_parameters(fitted_scaled_params, model);

% simulate the fitted model on both slices
predicted_training   = simulate_model(fitted_scaled_params, model, training_data);
predicted_validation = simulate_model(fitted_scaled_params, model, validation_data);

rmse_training   = rms_error(training_data.T_in,   predicted_training);
rmse_validation = rms_error(validation_data.T_in, predicted_validation);

%% ---------------------------- RESULTS --------------------------------
fprintf('\n===== Identification summary: %s =====\n', model.name);
fprintf('  training RMSE   : %.4f degC\n', rmse_training);
fprintf('  validation RMSE : %.4f degC\n', rmse_validation);
for p = 1:model.n_parameters
    line = sprintf('  %-8s = %10.4g', model.parameter_names(p), fitted_parameters(p));
    if ~isempty(true_parameters)
        rel_error_pct = 100 * (fitted_parameters(p) - true_parameters(p)) / abs(true_parameters(p));
        line = sprintf('%s   (true %10.4g, %+6.1f %%)', line, true_parameters(p), rel_error_pct);
    end
    fprintf('%s\n', line);
end
fprintf('\n');

plot_identification(training_data, validation_data, model, ...
    predicted_training, predicted_validation, ...
    fitted_parameters, true_parameters, rmse_validation);


%% ======================= LOCAL FUNCTIONS ==============================

function model = define_model(topology, scaling, discretisation, input_channels)
% DEFINE_MODEL  Describe a candidate RC topology: which parameters it has,
%   plausible bounds, how to build it as an RCBS.Building, and how the input
%   data channels map onto its nodes.

    topology_name  = upper(string(topology));
    uses_mad       = endsWith(topology_name, "-MAD");   % extra measured air-side heat input
    base_topology  = erase(topology_name, "-MAD");

    % parameter_names / initial_guess / bounds are given in physical units:
    %   resistances in K/W, capacitances in J/K, temperatures in degC.
    switch base_topology
        case "R1C1"
            parameter_names = ["R", "C"];
            initial_guess   = [3e-4;  4e9];
            lower_bound     = [1e-7;  1e5];
            upper_bound     = [1e-1;  1e10];

        case "R2C2"     % air --Rzone-- wall mass --Rwall-- outdoor
            parameter_names = ["R_wall", "C_wall", "R_zone", "C_zone"];
            initial_guess   = [2e-4;  1e9;   1e-2;  1e9];
            lower_bound     = [1e-7;  1e5;   1e-7;  1e5];
            upper_bound     = [1e-1;  1e10;  1e-1;  1e10];

        case "R4C4"     % wall + roof T-networks, plain window, dead-end internal mass
            parameter_names = ["R_wall","C_wall","R_roof","C_roof","R_intm","C_intm","R_wind","C_zone"];
            initial_guess   = [1e-3; 6e8;  1e-3; 7e8;  6e-6; 1e9;  3e-4; 4e8];
            lower_bound     = [1e-7; 1e5;  1e-7; 1e5;  1e-7; 1e5;  1e-7; 1e5];
            upper_bound     = [1e-1; 1e10; 1e-1; 1e10; 1e-1; 1e10; 1e-1; 1e10];

        case "R5C4"     % R4C4 plus a slab-on-grade path to a fixed ground temperature
            parameter_names = ["R_wall","C_wall","R_roof","C_roof","R_intm","C_intm","R_wind","C_zone","R_grnd","T_grnd"];
            initial_guess   = [1.015e-3; 6.2e8; 1.209e-3; 7.251e8; 6e-6; 1.23e9; 3.438e-4; 4.219e8; 3e-3; 12];
            lower_bound     = [1e-7; 1e5; 1e-7; 1e5; 1e-7; 1e5; 1e-7; 1e5; 1e-7; 8];
            upper_bound     = [1e-1; 1e10; 1e-1; 1e10; 1e-1; 1e10; 1e-1; 1e10; 1e-1; 15];

        case "R4C5"     % the window gets its own thermal mass
            parameter_names = ["R_wall","C_wall","R_roof","C_roof","R_wind","C_wind","R_intm","C_intm","C_zone"];
            initial_guess   = [1.015e-3; 6.2e8; 1.209e-3; 7.251e8; 3e-4; 1.23e7; 6e-6; 1.23e9; 4.219e8];
            lower_bound     = [1e-7; 1e5; 1e-7; 1e5; 1e-7; 1e5; 1e-7; 1e5; 1e5];
            upper_bound     = [1e-1; 1e10; 1e-1; 1e10; 1e-1; 1e9; 1e-1; 1e10; 1e10];

        otherwise
            error('system_identification:unknownTopology', 'Unknown topology "%s".', topology);
    end

    model.name            = char(topology_name);
    model.base_topology   = char(base_topology);
    model.parameter_names = parameter_names;
    model.n_parameters    = numel(initial_guess);
    model.discretisation  = lower(discretisation);

    % name -> position in the parameter vector, so build_topology can ask for
    % parameters by name instead of by index
    model.index = struct();
    for p = 1:numel(parameter_names)
        model.index.(char(parameter_names(p))) = p;
    end
    model.build = @(physical_params) build_topology(base_topology, physical_params, model.index);

    % R5C4 has a second fixed-temperature boundary (the ground); it is added to
    % the state-space model in build_discrete_model, not by RCBS itself
    if base_topology == "R5C4"
        model.ground_path = struct('resistance_param', 'R_grnd', 'temperature_param', 'T_grnd');
    else
        model.ground_path = [];
    end

    % which measured data column drives which RC node
    model.input_map = { struct('column', 'T_out',     'node', 'outdoor'), ...
                        struct('column', 'Q_in_data', 'node', 'air') };
    switch lower(input_channels)
        case 'basic'
            % nothing more
        case 'solar_lumped'
            model.input_map{end+1} = struct('column', 'Q_solar_est', 'node', 'air');
        case 'solar_split'
            model.input_map{end+1} = struct('column', 'Q_solar_wall',         'node', 'Wall');
            model.input_map{end+1} = struct('column', 'Q_solar_roof',         'node', 'Roof');
            model.input_map{end+1} = struct('column', 'Q_solar_window_abs',   'node', 'Wind');
            model.input_map{end+1} = struct('column', 'Q_solar_window_trans', 'node', 'air');
        otherwise
            error('system_identification:unknownInput', 'Unknown input_channels "%s".', input_channels);
    end
    if uses_mad
        model.input_map{end+1} = struct('column', 'MAD_cum', 'node', 'air');
    end

    % Search in a scaled space: a log map for R and C (they span many decades),
    % a linear map for temperatures. This keeps fmincon's steps well conditioned.
    model.parameter_scale = repmat("log", model.n_parameters, 1);
    model.parameter_scale(startsWith(parameter_names(:), "T_")) = "linear";
    switch lower(scaling)
        case 'perparam'  % keep the per-parameter map above
        case 'linear',   model.parameter_scale(:) = "linear";
        case 'log',      model.parameter_scale(:) = "log";
        case 'off',      model.parameter_scale(:) = "off";
        otherwise
            error('system_identification:unknownScaling', 'Unknown parameter_scaling "%s".', scaling);
    end

    model.lower_bound_physical  = lower_bound;
    model.upper_bound_physical  = upper_bound;
    model.initial_guess_physical = initial_guess;
    model.initial_guess_scaled = scale_parameters(initial_guess, model);
    model.lower_bound_scaled   = scale_parameters(lower_bound,   model);
    model.upper_bound_scaled   = scale_parameters(upper_bound,   model);
end

% ---------------------------------------------------------------------------
function building = build_topology(base_topology, physical_params, index)
% BUILD_TOPOLOGY  Assemble the chosen topology as an RCBS.Building.  The
%   initial node temperatures set here do not matter: they are re-estimated
%   from the data every time the model is simulated.

    value = @(param_name) physical_params(index.(param_name));
    initial_temp = 20;

    building = RCBS.Building();
    building.addStorey('S');
    building.S.addZone('Z');
    zone = building.S.Z;

    switch char(base_topology)
        case 'R1C1'
            zone.setAir(value('C'), initial_temp);
            zone.addWindow(value('R'), 'Win');

        case 'R2C2'
            zone.setAir(value('C_zone'), initial_temp);
            wall_node = zone.addNode('Wall', value('C_wall'), initial_temp);
            zone.resistors(end+1) = struct('n1', 1,         'n2', wall_node,  'R', value('R_zone'), 'name', 'air_wall');
            zone.resistors(end+1) = struct('n1', wall_node, 'n2', 'outdoor', 'R', value('R_wall'), 'name', 'wall_out');

        case {'R4C4', 'R5C4'}
            zone.setAir(value('C_zone'), initial_temp);
            zone.addWall(value('R_wall'), value('C_wall'), initial_temp, 'Wall');
            zone.addRoof(value('R_roof'), value('C_roof'), initial_temp, 'Roof');
            zone.addWindow(value('R_wind'), 'Wind');
            zone.addInternalMass(value('R_intm'), value('C_intm'), initial_temp, 'IntMass');
            % the R5C4 ground path is added in build_discrete_model

        case 'R4C5'
            zone.setAir(value('C_zone'), initial_temp);
            zone.addWall(value('R_wall'), value('C_wall'), initial_temp, 'Wall');
            zone.addRoof(value('R_roof'), value('C_roof'), initial_temp, 'Roof');
            zone.addWall(value('R_wind'), value('C_wind'), initial_temp, 'Wind');   % a wall element models the glazing mass
            zone.addInternalMass(value('R_intm'), value('C_intm'), initial_temp, 'IntMass');

        otherwise
            error('system_identification:unknownTopology', 'Unknown topology "%s".', base_topology);
    end
end

% ---------------------------------------------------------------------------
function [A_disc, B_disc, C_output, inputs] = build_discrete_model(model, physical_params, record)
% BUILD_DISCRETE_MODEL  Turn the RCBS building into a discrete-time linear
%   model  x[k+1] = A_disc x[k] + B_disc u[k] ,  y[k] = C_output x[k]
%   sampled at the record's time step, and assemble the input matrix `inputs`
%   whose columns line up with B_disc.

    building = model.build(physical_params);
    [continuous_ss, info] = building.simulation.getStateSpace();
    A_continuous = continuous_ss.A;
    B_continuous = continuous_ss.B;              % columns: [T_out, Q_node1, Q_node2, ...]
    state_names  = string(info.stateNames);
    air_row      = info.zoneMainRows(1);
    n_states     = size(A_continuous, 1);

    n_steps  = numel(record.t);
    n_inputs = numel(model.input_map);
    inputs   = zeros(n_steps, n_inputs);
    B_input  = zeros(n_states, n_inputs);

    for c = 1:n_inputs
        channel = model.input_map{c};
        if isfield(record, channel.column)
            inputs(:, c) = record.(channel.column)(:);
        else
            warning('system_identification:missingChannel', ...
                'record has no column "%s"; treated as zero.', channel.column);
        end
        if strcmpi(channel.node, 'outdoor')
            B_input(:, c) = B_continuous(:, 1);
        else
            node_row = node_row_for(state_names, channel.node, air_row);
            B_input(:, c) = B_continuous(:, 1 + node_row);
        end
    end

    % add the fixed-temperature ground path for R5C4:
    %   a conductance from the air node to a constant boundary T_grnd
    if ~isempty(model.ground_path)
        ground_conductance = 1 / physical_params(model.index.(model.ground_path.resistance_param));
        ground_temperature = physical_params(model.index.(model.ground_path.temperature_param));
        air_capacitance    = 1 / B_continuous(air_row, 1 + air_row);   % B(air, Q_air) equals 1/C_air
        A_continuous(air_row, air_row) = A_continuous(air_row, air_row) - ground_conductance / air_capacitance;
        B_input(:, end+1) = 0;
        B_input(air_row, end) = ground_conductance / air_capacitance;
        inputs(:, end+1) = ground_temperature;                        % a constant input column
    end

    C_output = continuous_ss.C(air_row, :);      % the model output is the indoor air temperature
    [A_disc, B_disc] = discretise(A_continuous, B_input, time_step_seconds(record.t), model.discretisation);
end

function row = node_row_for(state_names, node_name, air_row)
    if strcmpi(node_name, 'air')
        row = air_row;
        return;
    end
    row = find(endsWith(state_names, "." + string(node_name)), 1);
    if isempty(row)
        warning('system_identification:noNode', ...
            'node "%s" not found in this topology; routed to the air node instead.', node_name);
        row = air_row;
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
        case 'euler'       % forward Euler (only stable for small dt)
            A_disc = eye(size(A_continuous, 1)) + dt * A_continuous;
            B_disc = dt * B_continuous;
        otherwise
            error('system_identification:unknownDiscretisation', 'Unknown discretisation "%s".', method);
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
function predicted_temp = simulate_model(scaled_params, model, record)
% SIMULATE_MODEL  Run the model over the record's inputs and return the
%   predicted indoor temperature.
%
%   The output of a linear model is  y = output_from_x0 * x0 + forced_output,
%   linear in the unknown initial state x0.  So x0 is found in one least-squares
%   step from the measured temperature, and no initial temperatures need to be
%   part of the optimisation.

    physical_params = unscale_parameters(scaled_params, model);
    [A_disc, B_disc, C_output, inputs] = build_discrete_model(model, physical_params, record);

    n_steps  = size(inputs, 1);
    n_states = size(A_disc, 1);

    output_from_x0 = zeros(n_steps, n_states);   % row k is  C_output * A_disc^(k-1)
    forced_output  = zeros(n_steps, 1);          % response with x0 = 0

    transition_power = eye(n_states);            % A_disc^(k-1)
    forced_state     = zeros(n_states, 1);
    for k = 1:n_steps
        output_from_x0(k, :) = C_output * transition_power;
        forced_output(k)     = C_output * forced_state;
        transition_power = A_disc * transition_power;
        forced_state     = A_disc * forced_state + B_disc * inputs(k, :).';
    end

    initial_state  = output_from_x0 \ (record.T_in(:) - forced_output);   % least squares
    predicted_temp = forced_output + output_from_x0 * initial_state;
end

% ---------------------------------------------------------------------------
function cost = evaluate_cost(scaled_params, model, record, metric)
% EVALUATE_COST  Scalar goodness-of-fit that fmincon minimises.

    predicted = simulate_model(scaled_params, model, record);
    measured  = record.T_in(:);
    residual  = measured - predicted(:);

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
        case 'SLOPE'  % also penalise mismatch of the temperature rate of change
            rate_residual = diff(measured) - diff(predicted(:));
            cost = mean(residual(2:end).^2) + penalty_weight * mean(rate_residual.^2);
        case 'ASYMM'  % penalise over-prediction more than under-prediction
            weight = ones(size(residual));
            weight(predicted(:) > measured) = penalty_weight;
            cost = sum(weight .* residual.^2);
        case 'NRMSE'
            cost = sqrt(mean(residual.^2)) / (max(measured) - min(measured));
        otherwise
            error('system_identification:unknownMetric', 'Unknown error_metric "%s".', metric);
    end
end

function value = rms_error(measured, predicted)
    value = sqrt(mean((measured(:) - predicted(:)).^2));
end

% ---------------------------------------------------------------------------
function scaled = scale_parameters(physical, model)
% SCALE_PARAMETERS  Physical units -> the optimiser's search space.
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
% UNSCALE_PARAMETERS  Inverse of scale_parameters.
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
function plot_identification(training_data, validation_data, model, ...
        predicted_training, predicted_validation, fitted_parameters, true_parameters, rmse_validation)

    blue = [0 0.45 0.74];
    figure('Name', 'System identification', 'Color', 'w', 'Position', [80 80 1200 760]);
    layout = tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(layout, sprintf('RCBS grey-box identification  -  %s', model.name), 'FontWeight', 'bold');

    nexttile;  hold on;  grid on;  box on;
    plot(training_data.t, training_data.T_in, 'k-', 'LineWidth', 1.4);
    plot(training_data.t, predicted_training, '-', 'Color', blue, 'LineWidth', 1.1);
    ylabel('T_{in}  [\circC]');  title('training fit');
    legend({'measured', 'model'}, 'Location', 'best');

    nexttile;  hold on;  grid on;  box on;
    plot(validation_data.t, validation_data.T_in, 'k-', 'LineWidth', 1.4);
    plot(validation_data.t, predicted_validation, '-', 'Color', blue, 'LineWidth', 1.1);
    ylabel('T_{in}  [\circC]');  title(sprintf('held-out validation (RMSE %.2f \\circC)', rmse_validation));
    legend({'measured', 'model'}, 'Location', 'best');

    nexttile;  hold on;  grid on;  box on;
    plot(validation_data.t, validation_data.T_in - predicted_validation, '-', 'Color', blue);
    yline(0, 'k--', 'HandleVisibility', 'off');
    xlabel('time');  ylabel('error  [\circC]');  title('validation residual');

    nexttile;  grid on;  box on;
    if ~isempty(true_parameters)
        relative_error_pct = 100 * (fitted_parameters(:) - true_parameters(:)) ./ abs(true_parameters(:));
        bar(relative_error_pct, 0.6, 'FaceColor', blue, 'EdgeColor', 'none');
        ylabel('(fitted - true) / |true|   [%]');
        title('parameter recovery vs ground truth');
    else
        bar(fitted_parameters(:), 0.6, 'FaceColor', blue, 'EdgeColor', 'none');
        set(gca, 'YScale', 'log');  ylabel('fitted value  (physical units)');
        title('identified parameters');
    end
    set(gca, 'XTick', 1:model.n_parameters, 'XTickLabel', cellstr(model.parameter_names), ...
        'XTickLabelRotation', 30, 'FontSize', 8);
end

% ---------------------------------------------------------------------------
function [training_data, validation_data, true_parameters] = make_synthetic_dataset(model, weather_csv)
% MAKE_SYNTHETIC_DATASET  Generate a train + validation record from a known
%   building of the SAME topology being fitted, driven by real Kelowna
%   weather, a random heating signal and 0.15 degC of sensor noise, so the fit
%   can be graded against the truth.

    rng(7);
    reference_model = model;

    % the "true" parameters: the topology's nominal values, jittered a little
    true_parameters = model.initial_guess_physical;
    for p = 1:numel(true_parameters)
        if model.parameter_scale(p) == "linear"
            true_parameters(p) = true_parameters(p) + 1.5 * randn;
        else
            true_parameters(p) = true_parameters(p) * exp(0.20 * randn);
        end
    end
    true_parameters = min(max(true_parameters, model.lower_bound_physical * 1.01), ...
                                               model.upper_bound_physical * 0.99);

    sample_step = minutes(15);
    if isfile(weather_csv)
        weather    = DHS.Weather(weather_csv);
        start_time = weather.timeVector();
        start_time = start_time(1) + days(4);
        time       = (start_time : sample_step : start_time + days(27)).';
        sampled    = weather.atVec(time);
        outdoor_temp = sampled.Tout;
        irradiance   = sampled.ghi;
    else
        warning('system_identification:noWeather', 'weather file not found - using a sinusoidal climate.');
        time = (datetime(2025,1,4) : sample_step : datetime(2025,1,4) + days(27)).';
        hour_of_day = hours(time - dateshift(time, 'start', 'day'));
        day_index   = days(time - time(1));
        outdoor_temp = -4 + 6*sin(2*pi*(hour_of_day - 8)/24) + 3*sin(2*pi*day_index/9);
        irradiance   = max(0, 550*sin(pi*max(0, hour_of_day - 7)/10)) .* (hour_of_day > 7 & hour_of_day < 17);
    end
    n_steps = numel(time);

    % heating input: a random staircase plus a morning boost
    staircase   = cumsum(randn(ceil(n_steps/24), 1));
    staircase   = interp1(linspace(1, n_steps, numel(staircase)), staircase, 1:n_steps, 'previous', 'extrap').';
    staircase   = 3500 + 2500 * (staircase - min(staircase)) / max(max(staircase) - min(staircase), eps);
    hour_of_day = hours(time - dateshift(time, 'start', 'day'));
    heat_input  = max(0, staircase + 3000*max(0, sin(2*pi*(hour_of_day - 6)/24)) - 1500);

    solar_gain = 0.045 * irradiance;    % lumped effective solar aperture [W]

    % run the true model with a fixed cold start to get the noise-free temperature
    driving_record = struct('t', time, 'T_in', zeros(n_steps, 1), 'T_out', outdoor_temp, ...
                            'Q_in_data', heat_input, 'Q_solar_est', solar_gain);
    [A_disc, B_disc, C_output, inputs] = build_discrete_model(reference_model, true_parameters, driving_record);
    state = 9 * ones(size(A_disc, 1), 1);
    clean_temp = zeros(n_steps, 1);
    for k = 1:n_steps
        clean_temp(k) = C_output * state;
        state = A_disc * state + B_disc * inputs(k, :).';
    end
    indoor_temp = clean_temp + 0.15 * randn(n_steps, 1);

    % first 18 days for training, the rest for validation
    is_training = time < time(1) + days(18);
    make_record = @(mask) struct( ...
        't', time(mask), 'T_in', indoor_temp(mask), 'T_out', outdoor_temp(mask), ...
        'Q_in_data', heat_input(mask), 'Q_solar_est', solar_gain(mask), ...
        'Q_solar_wall',         0.012 * irradiance(mask), ...
        'Q_solar_roof',         0.010 * irradiance(mask), ...
        'Q_solar_window_abs',   0.006 * irradiance(mask), ...
        'Q_solar_window_trans', 0.017 * irradiance(mask), ...
        'MAD_cum', zeros(nnz(mask), 1));
    training_data   = make_record(is_training);
    validation_data = make_record(~is_training);
end
