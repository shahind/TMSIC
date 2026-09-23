%% DHS_CAMPUS_MULTIZONE
%  The same district heating campus as dhs_campus, but every building is now
%  several thermal zones (two per storey, coupled by partition walls and floor
%  slabs), each zone given the character of a room type - classroom, office,
%  dining hall, lobby, laboratory, and so on.
%
%  One substation still feeds each whole building, regulating the area-weighted
%  mean zone temperature.  The example shows how far a single building-level
%  control loop can hold a set of rooms with different gains and ventilation
%  rates, and where per-zone control would be needed.
%
%  The assembly lives in  +DHS/+examples/campus_multizone.m .  This script
%  builds that campus, runs it for two weeks, prints a per-zone tracking
%  table, and plots the zone temperatures for each building.
%
%  Run:  >> dhs_campus_multizone

clear;  clc;
example_dir  = fileparts(mfilename('fullpath'));
project_root = fileparts(example_dir);
addpath(example_dir, project_root);

simulation_days = 14;

%% --------------------------- build the campus --------------------------
campus = DHS.examples.campus_multizone('startDate', datetime(2025, 1, 1));
campus.compile();

total_zones = sum(cellfun(@(building) numel(building.zones), campus.buildings));
fprintf('Buildings : %d,   thermal zones in total : %d\n', campus.nB, total_zones);
fprintf('Plant     : %s  (max gas %.2f MW)\n', campus.plant.name, campus.plant.QgasMax() / 1e6);

%% ------------------------------- run ----------------------------------
fprintf('\nRunning %d days ...\n', simulation_days);
tic;
results = campus.run(days(simulation_days));
fprintf('  %.1f s of wall-clock for %d time steps\n', toc, numel(results.time));

%% --------------------- per-zone tracking table ----------------------
occupied = hour(results.time) >= 9 & hour(results.time) < 16 ...
         & weekday(results.time) >= 2 & weekday(results.time) <= 6;

fprintf('\n--- per-zone temperature vs its own setpoint, occupied hours ---\n');
worst_bias = 0;
for b = 1:campus.nB
    zone_temperatures = results.bldg(b).Tzones;
    zone_names        = results.bldg(b).zoneNames;
    room_types        = {campus.buildings{b}.zones.roomType};
    fprintf(' %s\n', results.bldg(b).name);
    for z = 1:numel(zone_names)
        schedule  = campus.buildings{b}.zones(z).schedule;
        setpoint  = arrayfun(@(t) schedule.setpoint(t), results.time(occupied));
        mean_bias = mean(zone_temperatures(occupied, z) - setpoint);
        overnight_minimum = min(zone_temperatures(:, z));
        worst_bias = max(worst_bias, abs(mean_bias));
        fprintf('   %-10s %-10s  mean bias %+5.2f degC   overnight min %.1f degC\n', ...
            zone_names{z}, room_types{z}, mean_bias, overnight_minimum);
    end
end
fprintf('\n worst occupied-hours mean bias across all zones: %.2f degC\n', worst_bias);
fprintf(['\n One substation regulated on the building mean cannot hold every room:\n' ...
         ' high-gain rooms run warm and high-ventilation rooms run cool.  Adding a\n' ...
         ' valve per zone would be the next modelling step.\n']);

%% ---------------------- zone temperature plots ----------------------
figure('Name', 'DHS campus - multi-zone', 'Color', 'w', 'Position', [60 60 1200 780]);
tiledlayout(campus.nB, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
for b = 1:campus.nB
    nexttile;  hold on;  grid on;
    zone_temperatures = results.bldg(b).Tzones;
    room_types = {campus.buildings{b}.zones.roomType};
    legend_labels = arrayfun(@(z) sprintf('%s (%s)', results.bldg(b).zoneNames{z}, room_types{z}), ...
        1:numel(room_types), 'UniformOutput', false);
    colours = lines(size(zone_temperatures, 2));
    for z = 1:size(zone_temperatures, 2)
        plot(results.time, zone_temperatures(:, z), 'Color', colours(z, :));
    end
    ylabel('\circC');  ylim([16 24]);
    title(results.bldg(b).name, 'Interpreter', 'none');
    legend(legend_labels, 'Interpreter', 'none', 'Location', 'eastoutside', 'FontSize', 7);
end
xlabel('date');
