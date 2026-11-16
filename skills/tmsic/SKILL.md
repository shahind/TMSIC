---
name: tmsic
description: Build, simulate and control resistance-capacitance (RC) thermal models of buildings and district heating systems with the TMSIC MATLAB toolbox (packages RCBS and DHS). Use it when the user wants to model a building's thermal behaviour, assemble a gas plant with pipes, pumps, valves, heat exchangers and buildings, export a linear state-space model, fit RC parameters to measured data, or attach PID, LQR or custom controllers in MATLAB.
license: GPL-3.0
compatibility: Needs MATLAB R2020a or newer (developed on R2025b). The Control System Toolbox is needed for getStateSpace and the LQR controller, and the Optimization Toolbox for the identification examples. No Simulink.
---

# TMSIC: thermal models of buildings and district heating

TMSIC has two packages. `RCBS` describes a building as a resistance-capacitance network (storeys, zones, walls,
windows, internal mass). `DHS` joins such buildings to a gas heat plant through a pipe network with pumps, valves,
heat exchangers and controllers, and simulates the whole system in one-minute steps. Everything is plain MATLAB.

Use this skill to write correct TMSIC code. Do not invent function names: use only the calls in this file and in
`references/api.md`. When unsure, read the toolbox documentation in `docs/` (see "Where to look").

## Setup

1. The user needs the toolbox folder on the MATLAB path: `cd` into it and run `setup`.
2. The weather file `solar_data_2025.csv` in the toolbox root covers 1 January to 30 June 2025. Use it for
   `DHS.System('weather', ...)` and keep the start date inside that range.

## Running MATLAB code

- If MATLAB tools are available (for example the MATLAB MCP server's `evaluate_matlab_code` or
  `run_matlab_file`), run the code yourself, starting from the toolbox folder, and check the output.
- Otherwise write a script the user can run, say which file to run, and ask for the output or the error text.
- Always check a DHS run: `res.energy.closure_err` should be near zero, and a controlled temperature should be near
  its setpoint.

## Workflow

1. **Decide what is needed.** A building alone (RCBS), or a district system (DHS)?
2. **Build the RC model** of each building with `RCBS`.
3. **For a district system**, create the system, the plant, the network, the buildings, their substations and
   controllers, and join them (see below).
4. **Simulate** with `building.simulate(duration)` (RCBS) or `sys.run(duration)` (DHS).
5. **Read the results** from `building.simulation.results` or from the structure `run` returns.
6. **Check** energy closure, setpoint tracking and plausible temperatures.

## RCBS in short

Units: degC, W, K/W (resistance), J/K (capacity), W/K (conductance).

```matlab
b = RCBS.Building();
b.addStorey('S1');
b.S1.addZone('Lab');
z = b.S1.Lab;
z.setAir(1.0e6, 20);                          % air capacity [J/K], initial temperature [degC]
z.addWall(0.02, 2e7, [], 'Wall');             % total R [K/W], C [J/K], initial T ([] = air value), name
z.addWindow(0.01, 'Window');                  % R [K/W], no state
z.addInternalMass(0.002, 5e7, [], 'Mass');    % R to air [K/W], C [J/K], initial T, name
z.connectToExternalSource(@(bb) 1500, 'T_main');   % heat input in W at a node, evaluated every step
b.S1.addZone('Corridor');  b.S1.Corridor.setAir(6e5, 20);
z.connectToZone(b.S1.Corridor, 0.02, 'Partition', 5e6);   % other zone, R, name, mid capacity (omit for an air path)

b.outdoorTempFunc      = @(t) 4 + 8*sin(2*pi*(hour(t) - 8)/24);   % t is a datetime
b.simulation.startDate = datetime(2025,1,1);
b.simulation.timeStep  = minutes(15);
b.simulate(days(3));
T = b.simulation.results.S1.Lab.T;            % one value per step
[sysc, io] = b.simulation.getStateSpace();    % continuous ss model; io.inputNames, io.stateNames
z.Wall.R = 0.03;                              % parts are reachable by name: .R, .C (read/write), .T (read)
```

## DHS in short

Build order matters: system, then plant, then the network, then pipes, then buildings.

```matlab
sys = DHS.System('weather','solar_data_2025.csv', 'startDate',datetime(2025,1,1));
chp = sys.addCentralHeatPlant('CHP');
chp.addBoiler('B1', 'QMax',1.0e6);                       % burner capacity [W]
chp.addPump('P0', 'dp0',3.0e5, 'mdotRated',6);           % shut-off head [Pa], rated flow [kg/s]
chp.setSupplySetpoint(70);                               % [degC]
hn = sys.addHydraulicNetwork();                          % needed before any pipe is added

tee1 = chp.supplyPort.addPipe(0.10, 40).addTee(0.05);    % pipe (D [m], L [m]), then a tee (side diameter [m])
r1   = DHS.Hydraulic.Junction('R1', 'return');           % the return side is wired separately
r1.addPipe(0.10, 40).connect(chp.returnPort);

b = sys.addBuilding('Hall');                             % reachable later as sys.Hall
b.useRCModel(rc);                                        % rc = an RCBS.Building (see above)
hx = DHS.IdealHeatExchanger('HX', 'Qnom',2e5);           % building WITHOUT an internal loop
b.attachHeatExchanger(hx);
c = DHS.controllers.PID(0.14, 1.6e-4, 0);                % the valve holds the zone at its setpoint
c.measure = @(sys) sys.Hall.Tzone;  c.reference = @(sys) sys.Hall.setpoint;
hx.valve.attachController(c);
b.attachSolar(DHS.Solar('winArea',struct('N',20,'E',20,'S',20,'W',20), 'SHGC',0.4, 'massFraction',0.1));
b.attachSchedule(DHS.Schedule('occStartHour',7, 'occEndHour',18, 'Tocc',21, 'Tsetback',18, 'gainOccW',20e3));
tee1.portC.connect(b);                                   % the building hangs on the tee's side port
b.connect(r1);                                           % and drains into a return junction

res = sys.run(days(7));                                  % res.plant, res.bldg(i), res.energy
```

Every component has `a.connect(b)`. `a.addPipe(D,L)`, `addValve`, `addPump`, `addTee(sideD)` and `addRadiator`
create a component, connect it downstream of `a` and return it. `attach...` is used for controllers, solar models,
schedules, heat exchangers and RC models.

## Rules that avoid errors

- **Heat exchanger type follows the building.** No internal loop: `DHS.IdealHeatExchanger` with
  `b.attachHeatExchanger(hx)`. Internal loop: `b.addHeatExchanger('HX','UA',..,'Qcap',..)` (plate exchanger) or
  `DHS.FixedEffectivenessHeatExchanger`, with both `hx.internalOutlet` and `hx.internalInlet` connected. A mismatch
  stops the run with an error that names the ports.
- **A network needs at least one pump.** The central pump comes from `chp.addPump`.
- **Add the hydraulic network before pipes:** `sys.addHydraulicNetwork()`.
- **A building hangs on `tee.portC`** (the side branch) and drains into a return junction.
- **Names must be valid MATLAB identifiers** and are the handles: `sys.CHP`, `sys.Hall`, `sys.Hall.S1.Lab.Wall.R`.
- **Controllers read what they need from `sys`**: `c.measure = @(sys) sys.Hall.Tzone`. A reference is a number or
  `@(sys) ...`. A custom law subclasses `DHS.controllers.Controller` and implements `reset` and `update(sys, dt)`.
- **`Tzone` is the area-weighted mean** of the zone air temperatures of a building.
- **A building with several zones** registers each zone with `b.attachZone('S1.Lobby', 'area',A, 'schedule',s, 'solar',sol)`.
- **Valves have a 60 s actuator lag** by default (`valve.lag`), and a command is limited to 0 to 1.
- **The default step is one minute.** Change it with `'timeStep', seconds(30)` in `DHS.System`.
- **Do not edit the package code** to make a model work. Use the public calls; legacy aliases `connectToPipe` and
  `connectOutput` exist but prefer `connect`.

## Identification and control design

- Fit RC parameters to data: run `examples/system_identification.m` (one zone) or
  `examples/multi_zone_system_identification.m`. Put `data` and `data_validation` structures in the workspace
  (`t`, `T_in`, `T_out`, `Q_in_data`) to use your own measurements.
- Design a controller: export `[sysc, io] = building.simulation.getStateSpace()` and use `DHS.controllers.LQR`
  (see `docs/dhs-controllers.md`).

## Where to look

- `references/api.md`: the public classes, properties and methods in one list.
- `references/recipes.md`: ready-to-run code for common tasks.
- `docs/` in the toolbox: one page per part (`rcbs-building.md`, `dhs-system.md`, `dhs-hydraulic.md`,
  `dhs-internal-loop.md`, `dhs-heat-exchanger.md`, `dhs-plant.md`, `dhs-controllers.md`, `dhs-solvers.md`,
  `dhs-weather-solar-schedule.md`, `examples.md`).
- `examples/`: `rcbs_tutorial.m`, `dhs_tutorial.m` and `dhs_internal_loop_tutorial.m` are the best templates.
- `validation/README.md`: how accurate each component is.
