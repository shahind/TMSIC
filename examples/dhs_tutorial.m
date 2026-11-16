%% DHS_TUTORIAL  Build and run a district heating system, one step at a time.
%
%  This script assembles the smallest complete system: a gas heat plant, a short
%  pipe network, and one office hall whose substation valve is controlled by a PID.
%
%    1. the thermal model of the building (RCBS);
%    2. the system and its weather file;
%    3. the heat plant: a boiler and a pump;
%    4. the pipes: a supply pipe, a tee, and a return pipe;
%    5. the building: substation, controller, solar gains and schedule;
%    6. joining the building to the pipes;
%    7. drawing, running and plotting.
%
%  Units: temperature in degC, flow in kg/s, pressure in Pa, heat in W, length in m.
%
%  Run:  >> dhs_tutorial

clear;  clc;
example_dir  = fileparts(mfilename('fullpath'));
project_root = fileparts(example_dir);
addpath(example_dir, project_root);

%% 1. The thermal model of the building
% One zone, "Hall", with a wall, a window and internal mass. The numbers describe a
% building of about 1,200 m2 with a heat loss of roughly 4 kW/K.
rc = RCBS.Building();
rc.addStorey('S1');
rc.S1.addZone('Hall');
rc.S1.Hall.setAir(2e7, 20);                          % air capacity [J/K], initial temperature [degC]
rc.S1.Hall.addWall(0.0004, 3e8, [], 'Wall');         % R [K/W], C [J/K], initial temperature, name
rc.S1.Hall.addWindow(0.00067, 'Window');             % R [K/W]
rc.S1.Hall.addInternalMass(0.0002, 5e8, [], 'Mass'); % R [K/W], C [J/K], initial temperature, name

%% 2. The system and its weather file
% The weather file gives outdoor temperature and sunshine from 1 January to 30 June 2025.
weather_file = fullfile(project_root, 'solar_data_2025.csv');
sys = DHS.System('weather', weather_file, 'startDate', datetime(2025, 1, 1));

%% 3. The central heat plant
chp    = sys.addCentralHeatPlant('CHP');
boiler = chp.addBoiler('B1', 'QMax', 1.0e6);         % burner capacity [W]
pump   = chp.addPump('P0', 'dp0', 3.0e5, 'mdotRated', 6);   % shut-off head [Pa], rated flow [kg/s]
chp.setSupplySetpoint(70);                           % the burner holds this supply temperature [degC]

network = sys.addHydraulicNetwork();                 % the pipe network that belongs to the system

%% 4. The pipes
% Supply side: plant -> pipe -> tee. The tee has a straight run (portB) and a side branch (portC).
supply_pipe = DHS.Hydraulic.Pipe('SupplyPipe', 'L', 40, 'D', 0.10);   % length [m], inner diameter [m]
chp.supplyPort.connect(supply_pipe);                 % the plant's supply port feeds the pipe

tee = DHS.Hydraulic.TJunction('Tee1', 'mainDiameter', 0.10, 'sideDiameter', 0.05);
supply_pipe.connect(tee);                            % the pipe ends at the tee

% Return side: return junction -> pipe -> plant. The return side is built separately.
return_junction = DHS.Hydraulic.Junction('R1', 'return');
return_pipe     = DHS.Hydraulic.Pipe('ReturnPipe', 'L', 40, 'D', 0.10);
return_junction.connect(return_pipe);
return_pipe.connect(chp.returnPort);                 % the return pipe ends at the plant

%% 5. The building
building = sys.addBuilding('Hall');                  % reachable later as sys.Hall
building.useRCModel(rc);                             % attach the thermal model of step 1

% Substation: this building has no water loop of its own, so it uses an ideal heat
% exchanger. It behaves like a radiator through which the district water flows.
exchanger = DHS.IdealHeatExchanger('HX', 'Qnom', 2e5);   % heat at 50 K temperature difference [W]
building.attachHeatExchanger(exchanger);

% Controller: the substation valve opens and closes to hold the zone at its setpoint.
% A controller reads what it needs from the system, here the hall's temperature and setpoint.
valve_controller = DHS.controllers.PID(0.14, 1.6e-4, 0);   % Kp, Ki, Kd
valve_controller.measure   = @(sys) sys.Hall.Tzone;
valve_controller.reference = @(sys) sys.Hall.setpoint;
exchanger.valve.attachController(valve_controller);

% Sunshine through the windows: glazed area on each side [m2], solar heat gain coefficient.
building.attachSolar(DHS.Solar('winArea', struct('N', 20, 'E', 20, 'S', 20, 'W', 20), ...
    'SHGC', 0.4, 'massFraction', 0.1));

% Occupancy: heated to 21 degC from 07:00 to 18:00, 18 degC otherwise, with internal gains.
building.attachSchedule(DHS.Schedule('occStartHour', 7, 'occEndHour', 18, 'rampHours', 1, ...
    'Tocc', 21, 'Tsetback', 18, 'gainOccW', 20e3, 'gainMassFraction', 0.3));

%% 6. Join the building to the pipes
tee.portC.connect(building);                         % the building hangs on the side branch of the tee
building.connect(return_junction);                   % and drains into the return junction

%% 7. Draw, run, and look at the results
sys.visualize();                                     % draws the plant, pipes and building

fprintf('Running 7 days ...\n');
tic;
results = sys.run(days(7));                          % one-minute steps
fprintf('  %.1f s for %d steps\n', toc, numel(results.time));

hall = results.bldg(1);
occupied = hour(results.time) >= 9 & hour(results.time) < 16 ...
         & weekday(results.time) >= 2 & weekday(results.time) <= 6;
error_in_use = hall.Tzone(occupied) - hall.setpoint(occupied);

fprintf('\nHall temperature in occupied hours: mean error %+.3f K, rms %.3f K\n', ...
    mean(error_in_use), sqrt(mean(error_in_use.^2)));
fprintf('Plant supply temperature : %.1f to %.1f degC (setpoint 70)\n', ...
    min(results.plant.Tsupply), max(results.plant.Tsupply));
fprintf('Gas burned %.0f kWh, heat delivered to the hall %.0f kWh\n', ...
    results.energy.gas_kWh, results.energy.delivered_kWh);
fprintf('Energy balance closure   : %.1e\n', results.energy.closure_err);

figure('Name', 'DHS tutorial', 'Color', 'w', 'Position', [80 80 900 650]);
tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;  hold on;  grid on;
plot(results.time, hall.Tzone);
plot(results.time, hall.setpoint, ':');
ylabel('degC');  title('hall temperature');  legend({'zone', 'setpoint'}, 'Location', 'best');

nexttile;  hold on;  grid on;
plot(results.time, results.plant.Tsupply, 'r');
plot(results.time, results.plant.Treturn, 'b');
ylabel('degC');  title('plant supply and return temperature');  legend({'supply', 'return'}, 'Location', 'best');

nexttile;  hold on;  grid on;
plot(results.time, hall.Qdeliv / 1e3);
ylabel('kW');  xlabel('date');  title('heat delivered to the hall');
