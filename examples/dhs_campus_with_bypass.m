%% DHS_CAMPUS_WITH_BYPASS
%  The campus of dhs_campus with an end-of-line bypass added to the supply main.
%
%  A bypass is a pipe and a valve from the last supply junction to the return
%  side. Water the buildings do not draw (their valves are partly closed) passes
%  through it and joins the return, so the main keeps a minimum flow. The
%  default campus has no bypass: its central pump slows down instead.
%
%  Adding a bypass takes one line, before the system is compiled:
%
%      hn = campus.network;
%      hn.addBypass(hn.T_Engineering, hn.R_Engineering, 'L',10, 'D',0.05, 'Kvs',1.5);
%
%  The first two arguments are the supply junction the bypass leaves and the return
%  junction it joins, here the end of both mains. 'L' and 'D' are the bypass pipe's
%  length and diameter, 'Kvs' the valve's full-open flow coefficient [m3/h at 1 bar]
%  and 'pos' (default 1) its fixed position. Attach a controller to
%  campus.network.bypassValve to move it (see "controlled bypass" below).
%
%  Run:  >> dhs_campus_with_bypass

clear;  clc;
example_dir  = fileparts(mfilename('fullpath'));
project_root = fileparts(example_dir);
addpath(example_dir, project_root);

simulation_days = 14;

%% --------------------------- build the campus --------------------------
campus = DHS.examples.campus('startDate', datetime(2025, 1, 1));

% end-of-line bypass at the last supply junction, valve fixed fully open
hn = campus.network;
hn.addBypass(hn.T_Engineering, hn.R_Engineering, 'L', 10, 'D', 0.05, 'Kvs', 1.5);

campus.compile();

% controlled bypass (optional): open the valve when the differential pressure across
% the bypass rises above 3.3 bar, close it below
%   c = DHS.controllers.PID('Kp', 1/1e5, 'Ki', 0, 'dir', -1);
%   c.measure   = @(sys) hn.T_Engineering.p - hn.R_Engineering.p;
%   c.reference = 3.3e5;
%   campus.network.bypassValve.attachController(c);
%
% or hold it at a constant position with a callback
%   campus.network.bypassValve.attachController( DHS.controllers.Callback(@(sys, dt) 0.5) );
fprintf('Bypass             : %.0f m, %.0f mm, valve Kvs %.1f\n', ...
    campus.network.bypassPipe.L, 1e3 * campus.network.bypassPipe.D, campus.network.bypassValve.Kvs);

%% ------------------------------- run ----------------------------------
fprintf('\nRunning %d days ...\n', simulation_days);
tic;
results = campus.run(days(simulation_days));
fprintf('  %.1f s of wall-clock for %d time steps\n', toc, numel(results.time));

%% --------------------------- quick summary ---------------------------
plant = results.plant;
fprintf('\n--- summary ---\n');
fprintf('  plant supply temperature : %.1f - %.1f degC   (setpoint %.0f)\n', ...
    min(plant.Tsupply), max(plant.Tsupply), mean(plant.TsupSet));
fprintf('  boiler efficiency        : %.3f - %.3f\n', min(plant.eta), max(plant.eta));
fprintf('  peak gas input           : %.0f kW   (cap %.0f kW)\n', ...
    max(plant.Qgas) / 1e3, campus.plant.QgasMax() / 1e3);
fprintf('  bypass flow              : mean %.2f kg/s, %.1f %% of the total flow\n', ...
    mean(plant.Mbypass), 100 * sum(plant.Mbypass) / sum(plant.Mtot));
fprintf('  14-day energy closure    : %.2f %%   (should be near zero)\n', ...
    100 * results.energy.closure_err);

%% ------------------------------ plots --------------------------------
campus.visualize();

figure('Name', 'DHS campus with bypass - flows', 'Color', 'w', 'Position', [80 80 1000 520]);
tiledlayout(2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;  hold on;  grid on;
plot(results.time, plant.Mtot, 'k');
plot(results.time, plant.Mbypass, 'm');
ylabel('kg/s');  title('total flow and the part that passes through the bypass');
legend({'total', 'bypass'}, 'Location', 'best');

nexttile;  hold on;  grid on;
plot(results.time, plant.Tsupply, 'r');
plot(results.time, plant.Treturn, 'b');
ylabel('\circC');  xlabel('date');  title('plant supply and return temperatures');
legend({'supply', 'return'}, 'Location', 'best');
