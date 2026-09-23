%% RCBS_EXAMPLE
%  Build a multi-zone building with the RCBS library and draw its RC schematic.
%
%  The building has 3 storeys and 7 zones: storeys 1 and 2 have three and two
%  zones, storey 3 has two.  Each zone is assembled from the standard RCBS
%  elements (exterior wall, window, infiltration vent, internal thermal mass,
%  and a roof on the top storey), and the zones are tied together with
%  RCBS.Zone.connectToZone:
%     - wall-to-wall partitions between neighbouring zones on a storey;
%     - floor slabs between vertically stacked zones;
%     - two plain open air paths (no thermal mass).
%  Two external heat inputs drive an office and a laboratory.
%
%  Run:  >> RCBS_example

clear;  clc;
example_dir = fileparts(mfilename('fullpath'));
addpath(example_dir, fileparts(example_dir));

building = RCBS.Building();
building.addStorey('S1');
building.addStorey('S2');
building.addStorey('S3');

%% ------------------------------ zones ------------------------------------
% one row per zone: {name, storey, floor area [m2], has internal mass?, has roof?}
zone_table = { ...
    'Lobby',    'S1', 320, false, false ;
    'Offices',  'S1', 250, true,  false ;
    'Corridor', 'S1', 90,  false, false ;
    'Classes',  'S2', 300, true,  false ;
    'Labs',     'S2', 300, true,  false ;
    'Dinning',  'S3', 350, false, true  ;
    'Archive',  'S3', 150, true,  true  };

initial_temperature = 20;
storey_height       = 3.4;   % m

for row = 1:size(zone_table, 1)
    zone_name   = zone_table{row, 1};
    storey_name = zone_table{row, 2};
    floor_area  = zone_table{row, 3};
    has_internal_mass = zone_table{row, 4};
    has_roof          = zone_table{row, 5};

    building.(storey_name).addZone(zone_name);
    zone = building.(storey_name).(zone_name);

    % air node: capacitance = density * specific heat * volume * furniture factor
    air_capacitance = 1.2 * 1005 * (floor_area * storey_height) * 5;
    zone.setAir(air_capacitance, initial_temperature);

    % exterior envelope
    wall_area = 0.55 * floor_area;
    zone.addWall(1 / (0.30 * wall_area), 1.5e5 * wall_area, initial_temperature, 'Wall');   % U = 0.30 W/m2K
    zone.addWindow(1 / (2.0 * 0.30 * wall_area), 'Window');                                 % 30 % glazing, U = 2.0
    zone.addWindow(1 / (0.12 * floor_area), 'InfVent');                                     % background infiltration

    if has_internal_mass
        zone.addInternalMass(1 / (6 * floor_area), 9.0e4 * floor_area, initial_temperature, 'IntMass');
    end
    if has_roof
        zone.addRoof(1 / (0.20 * floor_area), 1.0e5 * floor_area, initial_temperature, 'Roof');
    end
end

% the laboratory has extra roof glazing and a stronger exhaust
building.S2.Labs.addWindow(1 / (1.8 * 40),    'SkyGlaze');
building.S2.Labs.addWindow(1 / (0.35 * 260),  'ExhVent');

%% -------------------------- zone couplings -----------------------------
% wall-to-wall partitions between neighbouring zones on a storey (capacitive)
add_wall(building.S1.Offices, building.S1.Lobby, 'wall_Offices_Lobby');
add_wall(building.S1.Offices, building.S1.Corridor, 'wall_Offices_Corridor');
add_wall(building.S2.Classes,  building.S2.Labs,  'wall_Classes_Labs');
add_wall(building.S3.Dinning,   building.S3.Archive, 'wall_Dinning_Archive');

% open air paths (plain conductance, no thermal mass)
add_air(building.S1.Lobby,   building.S1.Offices,  'air_Lobby_Offices');
add_air(building.S1.Offices,  building.S1.Corridor, 'air_Offices_Corridor');

% roof / floor slabs between vertically stacked zones (capacitive)
add_slab(building.S2.Classes,  building.S1.Offices,  'slab_Classes_Offices');
add_slab(building.S2.Labs,     building.S1.Corridor, 'slab_Labs_Corridor');
add_slab(building.S3.Dinning,  building.S2.Classes,  'slab_Dinning_Classes');
add_slab(building.S3.Archive,  building.S2.Labs,     'slab_Archive_Labs');

%% -------------------------- external heat ------------------------------
% each heat source is a function of the building at the current time step
offices_heater = @(b) 4000 * (hour(b.simulation.t) >= 7 && hour(b.simulation.t) < 18);
lab_equipment = @(b) 2500 * (weekday(b.simulation.t) >= 2 && weekday(b.simulation.t) <= 6);
building.S1.Offices.connectToExternalSource(offices_heater, 'T_main');
building.S2.Labs.connectToExternalSource(lab_equipment,     'IntMass');

%% ----------------------- climate and simulation -----------------------
building.outdoorTempFunc      = @(t) 4 + 9 * sin(2*pi*(hour(t) + minute(t)/60 - 4) / 24);
building.simulation.startDate = datetime(2025, 1, 13);
building.simulation.timeStep  = minutes(15);

fprintf('Simulating 3 days ...\n');
building.simulate(days(3));
building.simulation.plotResults();

%% ---------------------------- schematic -------------------------------
building.visualize();


%% ========================= local helpers =============================
function add_wall(zone_a, zone_b, name)
    % a capacitive interior partition wall between two zones on the same storey
    partition_resistance  = 0.045;   % K/W  (total, split R/2 - C - R/2 internally)
    partition_capacitance = 5.0e6;   % J/K
    zone_a.connectToZone(zone_b, partition_resistance, name, partition_capacitance, 20, 'wall');
end

function add_slab(zone_below, zone_above, name)
    % a capacitive floor slab: the lower zone's ceiling is the upper zone's floor
    slab_resistance  = 0.02;    % K/W
    slab_capacitance = 1.4e7;   % J/K
    zone_below.connectToZone(zone_above, slab_resistance, name, slab_capacitance, 20, 'slab');
end

function add_air(zone_a, zone_b, name)
    % a plain open air path (no thermal mass) between two zones
    zone_a.connectToZone(zone_b, 0.02, name);
end
