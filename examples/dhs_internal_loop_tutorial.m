%% DHS_INTERNAL_LOOP_TUTORIAL  A building with its own water loop and a radiator.
%
%  The building of dhs_tutorial, now with an internal loop. The district water heats the
%  loop water in a plate heat exchanger. A pump circulates the loop water through a valve
%  and a radiator, and the radiator heats the room.
%
%    district side:   plant -> supply pipe -> tee -> (building) -> return pipe -> plant
%    loop side:       exchanger -> pipe -> pump -> pipe -> tee -+-> valve -> pipe -> radiator -> pipe -+
%                                                               |                                    |
%                                                               +-> pipe -> bypass valve -----> return junction -> pipe -> exchanger
%
%  Three controllers act: the zone valve holds the room temperature, the loop pump holds
%  the loop flow, and the district valve holds the loop supply temperature.
%
%  Steps:
%    1. the thermal model, the plant and the district pipes;
%    2. the building and its plate heat exchanger;
%    3. the radiator and the loop pipes, valves and pump;
%    4. the three controllers;
%    5. run and plot.
%
%  Units: temperature in degC, flow in kg/s, pressure in Pa, heat in W, length in m.
%
%  Run:  >> dhs_internal_loop_tutorial

clear;  clc;
example_dir  = fileparts(mfilename('fullpath'));
project_root = fileparts(example_dir);
addpath(example_dir, project_root);

%% 1. Thermal model, plant and district pipes (as in dhs_tutorial)
rc = RCBS.Building();
rc.addStorey('S1');
rc.S1.addZone('Hall');
rc.S1.Hall.setAir(2e7, 20);
rc.S1.Hall.addWall(0.0004, 3e8, [], 'Wall');
rc.S1.Hall.addWindow(0.00067, 'Window');
rc.S1.Hall.addInternalMass(0.0002, 5e8, [], 'Mass');

sys = DHS.System('weather', fullfile(project_root, 'solar_data_2025.csv'), 'startDate', datetime(2025, 1, 1));

chp = sys.addCentralHeatPlant('CHP');
chp.addBoiler('B1', 'QMax', 1.0e6);
chp.addPump('P0', 'dp0', 3.0e5, 'mdotRated', 6);
chp.setSupplySetpoint(70);
network = sys.addHydraulicNetwork();

% One-call style: addPipe creates a pipe and connects it, addTee does the same for a tee.
tee         = chp.supplyPort.addPipe(0.10, 40).addTee(0.05);   % diameter [m], length [m]; tee side diameter [m]
return_junction = DHS.Hydraulic.Junction('R1', 'return');
return_junction.addPipe(0.10, 40).connect(chp.returnPort);

%% 2. The building and its plate heat exchanger
building = sys.addBuilding('Hall');
building.useRCModel(rc);

% addHeatExchanger creates a plate heat exchanger (effectiveness-NTU). Use it when the
% building has a loop. UA is its conductance [W/K] and Qcap the most heat it can deliver [W].
exchanger = building.addHeatExchanger('HX', 'UA', 8e3, 'Qcap', 2e5);

tee.portC.connect(building);                         % hangs on the side branch of the tee
building.connect(return_junction);                   % drains into the return junction

%% 3. The loop
design_load  = 144e3;                                % heat the hall needs on a design day [W]
main_diameter = 0.08;                                % diameter of the loop mains [m]
% Pipe lengths [m]:  feed, pump to tee, branch to the radiator (each way), return main, bypass
length = [12 84 12 108 12];

% The radiator is sized from its design heat output and design temperatures.
radiator = DHS.Radiator('rad1', 'Qdes', design_load, 'Tsup', 60, 'Tret', 40);
radiator.connect(rc.S1.Hall);                        % the radiator heats this zone

% Pump size: it must push the radiator flow plus the bypass flow through the mains.
pump_flow     = 1.5 * radiator.mdotDes;              % radiator design flow plus the bypass flow [kg/s]
mains_pipe    = DHS.Hydraulic.Pipe('mains', 'L', length(1) + length(2) + length(4), 'D', main_diameter);
mains_K       = mains_pipe.resistance(pump_flow, 983, 4.7e-4);      % flow, density, viscosity
bypass_K      = 1.2e4 / (0.5 * radiator.mdotDes)^2;
pump_shutoff  = 1.6 * (mains_K + bypass_K) * pump_flow^2;           % shut-off head [Pa]

% Loop, from the exchanger's internal outlet to its internal inlet.
pump = exchanger.internalOutlet.addPipe(main_diameter, length(1), 'UperM', 0.15).addPump( ...
    'dp0', pump_shutoff, 'mdotRated', pump_flow);

loop_tee = pump.addPipe(main_diameter, length(2), 'UperM', 0.15).addTee(radiator.pipeD);

% Branch to the radiator: tee side port -> valve -> pipe -> radiator.
zone_valve = loop_tee.portC.addValve( ...
    'Kvs', DHS.Hydraulic.Valve.kvsFor(radiator.mdotDes, 5e3), ...   % flow coefficient for 5 kPa at design flow
    'char', 'linear', 'minPos', 1e-3);
zone_valve.addPipe(radiator.pipeD, length(3), 'UperM', 0.15).connect(radiator);

% Return: radiator -> pipe -> loop return junction -> pipe -> exchanger internal inlet.
loop_return = DHS.Hydraulic.Junction('loopReturn', 'return');
radiator.addPipe(radiator.pipeD, length(3), 'UperM', 0.15).connect(loop_return);
loop_return.addPipe(main_diameter, length(4), 'UperM', 0.15).connect(exchanger.internalInlet);

% Bypass: tee run -> pipe -> valve -> loop return junction. It takes the water the radiator does not.
bypass_valve = loop_tee.portB.addPipe(main_diameter, length(5), 'UperM', 0.15).addValve( ...
    'Kvs', DHS.Hydraulic.Valve.kvsFor(0.5 * radiator.mdotDes, 1.2e4), 'char', 'linear');
bypass_valve.connect(loop_return);

%% 4. Controllers
% (a) The zone valve holds the room temperature at its setpoint.
zone_controller = DHS.controllers.PID(0.6, 2e-3, 0);
zone_controller.measure   = @(sys) radiator.Tzone;
zone_controller.reference = @(sys) radiator.setpoint;
zone_valve.attachController(zone_controller);

% (b) The loop pump holds the loop flow. Its gains are small because the flow follows the
% pump speed within one step.
flow_controller = DHS.controllers.PID('Kp', 0.03 / radiator.mdotDes, 'Ki', 0.002 / radiator.mdotDes, 'uMin', 0.3);
flow_controller.measure   = @(sys) sys.Hall.mdotInt;
flow_controller.reference = pump_flow;
pump.attachController(flow_controller);

% (c) The district valve holds the loop supply temperature at 60 degC.
supply_controller = DHS.controllers.PID(0.02, 4e-5, 0);
supply_controller.measure   = @(sys) sys.Hall.TintSup;
supply_controller.reference = 60;
exchanger.valve.attachController(supply_controller);

% Solar gains and the occupancy schedule, as in dhs_tutorial.
building.attachSolar(DHS.Solar('winArea', struct('N', 20, 'E', 20, 'S', 20, 'W', 20), ...
    'SHGC', 0.4, 'massFraction', 0.1));
building.attachSchedule(DHS.Schedule('occStartHour', 7, 'occEndHour', 18, 'rampHours', 1, ...
    'Tocc', 21, 'Tsetback', 18, 'gainOccW', 20e3, 'gainMassFraction', 0.3));

%% 5. Run and look at the results
sys.visualize();

fprintf('Running 7 days ...\n');
tic;
results = sys.run(days(7));
fprintf('  %.1f s for %d steps\n', toc, numel(results.time));

hall = results.bldg(1);
occupied = hour(results.time) >= 9 & hour(results.time) < 16 ...
         & weekday(results.time) >= 2 & weekday(results.time) <= 6;
error_in_use = hall.Tzone(occupied) - hall.setpoint(occupied);

fprintf('\nHall temperature in occupied hours: mean error %+.3f K, rms %.3f K\n', ...
    mean(error_in_use), sqrt(mean(error_in_use.^2)));
fprintf('Loop supply temperature  : %.1f to %.1f degC (5th to 95th percentile; setpoint 60)\n', ...
    prctile(hall.Tint_sup, 5), prctile(hall.Tint_sup, 95));
fprintf('Loop flow                : %.2f to %.2f kg/s (5th to 95th percentile; reference %.2f)\n', ...
    prctile(hall.mdot_int, 5), prctile(hall.mdot_int, 95), pump_flow);
fprintf('Water in the loop        : %.0f litres\n', sys.Hall.loopCap / (983 * 4186) * 1000);
fprintf('Exchanger delivered %.0f kWh; the radiator gave %.0f kWh to the hall\n', ...
    results.energy.delivered_kWh, sum(hall.Qzones) * 60 / 3.6e6);
fprintf('Energy balance closure   : %.1e\n', results.energy.closure_err);

figure('Name', 'DHS internal loop tutorial', 'Color', 'w', 'Position', [80 80 900 800]);
tiledlayout(4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;  hold on;  grid on;
plot(results.time, hall.Tzone);  plot(results.time, hall.setpoint, ':');
ylabel('degC');  title('hall temperature');  legend({'zone', 'setpoint'}, 'Location', 'best');

nexttile;  hold on;  grid on;
plot(results.time, hall.Tint_sup, 'r');  plot(results.time, hall.Tint_ret, 'b');
ylabel('degC');  title('loop supply and return temperature');  legend({'supply', 'return'}, 'Location', 'best');

nexttile;  hold on;  grid on;
plot(results.time, hall.mdot_int);
ylabel('kg/s');  title('loop flow');

nexttile;  hold on;  grid on;
plot(results.time, hall.Qdeliv / 1e3);  plot(results.time, hall.Qzones / 1e3);
ylabel('kW');  xlabel('date');  title('heat from the exchanger and heat to the zone');
legend({'exchanger', 'radiator'}, 'Location', 'best');
