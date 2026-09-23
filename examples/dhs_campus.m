%% DHS_CAMPUS
%  Assemble and run a small district heating campus with the DHS library:
%  one central gas heat plant feeding five campus buildings through a
%  trunk-and-branch pipe network.  Every building wraps a single-zone RCBS
%  thermal model plus a substation (heat exchanger + control valve + pump +
%  PID controller).
%
%  The full part-by-part assembly lives in  +DHS/+examples/campus.m  -- open it
%  to see how the plant, boilers, pump, pipes, junctions, buildings and
%  controllers are put together with the DHS API.  This script builds that
%  campus, runs it for two weeks, prints a short plausibility summary, and
%  plots the plant and building signals.
%
%  Run:  >> dhs_campus

clear;  clc;
example_dir  = fileparts(mfilename('fullpath'));
project_root = fileparts(example_dir);
addpath(example_dir, project_root);

simulation_days = 14;

%% --------------------------- build the campus --------------------------
campus = DHS.examples.campus('startDate', datetime(2025, 1, 1));
campus.compile();

fprintf('Central heat plant : %s  (%d boiler, max gas %.2f MW)\n', ...
    campus.plant.name, numel(campus.plant.boilers), campus.plant.QgasMax() / 1e6);
fprintf('Buildings          : %d\n', campus.nB);
fprintf('Pipe network       : %d junctions, %d supply pipes\n', ...
    numel(campus.network.junctions), numel(campus.network.pipes));

%% ------------------------------- run ----------------------------------
fprintf('\nRunning %d days ...\n', simulation_days);
tic;
results = campus.run(days(simulation_days));
fprintf('  %.1f s of wall-clock for %d time steps\n', toc, numel(results.time));

%% --------------------------- quick summary ---------------------------
plant = results.plant;
occupied = hour(results.time) >= 9 & hour(results.time) < 16 ...
         & weekday(results.time) >= 2 & weekday(results.time) <= 6;

fprintf('\n--- summary ---\n');
fprintf('  plant supply temperature : %.1f - %.1f degC   (setpoint %.0f)\n', ...
    min(plant.Tsupply), max(plant.Tsupply), mean(plant.TsupSet));
fprintf('  boiler efficiency        : %.3f - %.3f\n', min(plant.eta), max(plant.eta));
fprintf('  peak gas input           : %.0f kW   (cap %.0f kW)\n', ...
    max(plant.Qgas) / 1e3, campus.plant.QgasMax() / 1e3);
fprintf('  supply header pressure   : %.1f - %.1f bar (gauge)\n', ...
    min(plant.pSupHeader) / 1e5, max(plant.pSupHeader) / 1e5);
for b = 1:campus.nB
    building = results.bldg(b);
    occupied_bias = mean(building.Tzone(occupied) - building.setpoint(occupied));
    fprintf('  %-14s zone temp %.1f - %.1f degC,  occupied-hours bias %+.2f degC\n', ...
        building.name, min(building.Tzone), max(building.Tzone), occupied_bias);
end
fprintf('  14-day energy closure    : %.2f %%   (should be near zero)\n', ...
    100 * results.energy.closure_err);

%% ------------------------------ plots --------------------------------
colours = lines(campus.nB);

figure('Name', 'DHS campus - central plant', 'Color', 'w', 'Position', [80 80 1000 720]);
tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;  hold on;  grid on;
plot(results.time, plant.Tsupply, 'r');
plot(results.time, plant.TsupSet, 'r:');
plot(results.time, plant.Treturn, 'b');
plot(results.time, results.Tout, 'Color', [0.5 0.5 0.5]);
ylabel('\circC');  title('plant temperatures');
legend({'supply', 'setpoint', 'return', 'outdoor'}, 'Location', 'best');

nexttile;  hold on;  grid on;
plot(results.time, plant.Qgas / 1e3, 'm');
plot(results.time, plant.Qboiler / 1e3, 'k');
ylabel('kW');  title('plant heat rates');
legend({'gas input', 'delivered to loop'}, 'Location', 'best');

nexttile;  hold on;  grid on;
yyaxis left;   plot(results.time, plant.eta);   ylabel('efficiency');  ylim([0.8 1]);
yyaxis right;  plot(results.time, plant.Mtot);  ylabel('primary flow  [kg/s]');
xlabel('date');  title('efficiency and primary mass flow');

figure('Name', 'DHS campus - buildings', 'Color', 'w', 'Position', [80 80 1000 720]);
tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;  hold on;  grid on;
for b = 1:campus.nB
    plot(results.time, results.bldg(b).Tzone, 'Color', colours(b, :));
end
plot(results.time, results.bldg(1).setpoint, 'k:');
ylabel('\circC');  title('zone air temperature');
legend([{results.bldg.name}, {'setpoint'}], 'Interpreter', 'none', 'Location', 'best');

nexttile;  hold on;  grid on;
for b = 1:campus.nB
    plot(results.time, results.bldg(b).Qdeliv / 1e3, 'Color', colours(b, :));
end
ylabel('kW');  title('delivered hydronic heat per building');

nexttile;  hold on;  grid on;
for b = 1:campus.nB
    plot(results.time, results.bldg(b).valve, 'Color', colours(b, :));
end
ylabel('valve position  [0-1]');  xlabel('date');
title('substation control-valve position');
