%% DHS_CAMPUS_WITH_BYPASS  The campus with an end-of-line bypass on the supply main.
%
%  A bypass is a pipe and a valve from the last supply junction to the return side. Water that the
%  buildings do not draw passes through it and joins the return, so the main keeps a minimum flow.
%  One call, before compile, adds it:
%      hn.addBypass(hn.T_Engineering, hn.R_Engineering, 'L',10, 'D',0.05, 'Kvs',1.5);
%  The arguments are the supply junction it leaves and the return junction it joins, then the pipe
%  length [m] and diameter [m], the valve's full-open flow coefficient Kvs [m3/h/sqrt(bar)] and its
%  position 'pos' (default 1). Attach a controller to hn.bypassValve to move it (see below).
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
