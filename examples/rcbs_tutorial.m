%% RCBS_TUTORIAL  Build, simulate and export a small building, one step at a time.
%
%  This script shows the basic RCBS calls on a two-zone building:
%    1. create a building, a storey and zones;
%    2. add walls, windows and internal mass to a zone;
%    3. couple two zones with a partition wall;
%    4. add a heat input (a heater with a schedule);
%    5. set the outdoor temperature and the clock, and simulate;
%    6. read and plot the results;
%    7. change a parameter by name and simulate again;
%    8. export the linear state-space model.
%
%  Units: temperature in degC, resistance in K/W, capacity in J/K, heat in W.
%
%  Run:  >> rcbs_tutorial

clear;  clc;
example_dir = fileparts(mfilename('fullpath'));
addpath(example_dir, fileparts(example_dir));

%% 1. A building with one storey and two zones
building = RCBS.Building();
building.addStorey('Ground');                  % a storey is reached as building.Ground
building.Ground.addZone('Lab');                % a zone is reached as building.Ground.Lab
building.Ground.addZone('Corridor');

lab      = building.Ground.Lab;                % keep a short name for the zone we edit most
corridor = building.Ground.Corridor;

%% 2. The elements of each zone
% Air node: heat capacity of the air and furniture [J/K], initial temperature [degC].
lab.setAir(1.0e6, 20);
corridor.setAir(0.6e6, 20);

% Wall: total resistance [K/W], heat capacity [J/K], initial temperature ([] = same as the air), name.
% The wall is one node joined to the air and to the outdoors by R/2 each.
lab.addWall(0.02, 2.0e7, [], 'ExteriorWall');

% Window: one resistance [K/W] from the air to the outdoors, with no heat capacity.
lab.addWindow(0.01, 'Window');
corridor.addWindow(0.02, 'Window');

% Internal mass (furniture, floor): resistance to the air [K/W], capacity [J/K], initial temperature, name.
lab.addInternalMass(0.002, 5.0e7, [], 'Furniture');

%% 3. Couple the two zones with a partition wall
% Arguments: the other zone, total resistance [K/W], name, and the heat capacity of the wall [J/K].
% Leave out the capacity to get a plain opening (an open doorway) instead of a wall.
lab.connectToZone(corridor, 0.02, 'Partition', 5e6);

%% 4. A heat input: a 1.5 kW heater in the lab between 08:00 and 18:00
% A heat input is a function of the building. It returns watts and is called at every step.
heater = @(b) 1500 * (hour(b.simulation.t) >= 8 && hour(b.simulation.t) < 18);
lab.connectToExternalSource(heater, 'T_main');       % 'T_main' is the air node

%% 5. The outdoor temperature, the clock and the simulation
building.outdoorTempFunc      = @(t) 2 + 6*sin(2*pi*(hour(t) - 9)/24);   % a daily swing around 2 degC
building.simulation.startDate = datetime(2025, 1, 13);
building.simulation.timeStep  = minutes(15);

building.simulate(days(3));

%% 6. Results
results = building.simulation.results;
time    = results.Time;
T_lab   = results.Ground.Lab.T;
T_corr  = results.Ground.Corridor.T;

fprintf('Lab      : %.1f to %.1f degC\n', min(T_lab), max(T_lab));
fprintf('Corridor : %.1f to %.1f degC\n', min(T_corr), max(T_corr));

figure('Name', 'RCBS tutorial', 'Color', 'w');
plot(time, T_lab, time, T_corr, time, results.OutdoorTemperature, '--');
grid on;  ylabel('degC');  legend({'Lab', 'Corridor', 'Outdoor'}, 'Location', 'best');
title('Zone air temperatures');

building.visualize();                          % draw the RC network

%% 7. Change a parameter by name and simulate again
% Every wall, window and mass is reachable by its name; R and C can be read and written.
fprintf('\nWindow resistance: %.3f K/W\n', lab.Window.R);
lab.Window.R = 0.02;                           % a better window: half the heat loss
fprintf('Window resistance: %.3f K/W\n', lab.Window.R);

building.simulate(days(3));
T_lab_new = building.simulation.results.Ground.Lab.T;
fprintf('Lab with the better window: %.1f to %.1f degC\n', min(T_lab_new), max(T_lab_new));

%% 8. The linear state-space model (needs the Control System Toolbox)
% x' = A x + B u, with one state per node and the inputs listed in io.inputNames.
if license('test', 'Control_Toolbox')
    [sysc, io] = building.simulation.getStateSpace();
    fprintf('\nState-space model: %d states, %d inputs\n', size(sysc.A, 1), size(sysc.B, 2));
    disp(io.stateNames);
    disp(io.inputNames);
end
