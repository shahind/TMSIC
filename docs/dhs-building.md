# DHS.Building: a building on the district network

`DHS.Building` connects an `RCBS.Building` thermal model to the district network. It adds the substation (a
heat exchanger with its valve and an optional booster pump), a solar model, an occupancy schedule, and the
ventilation and free-cooling terms. At every step it computes the heat that enters each RC node and injects it
with `RCBS.Simulation.stepOnce`. The RC library itself stays free of district heating code.

A building is created with `sys.addBuilding(name)`. It is connected like any other network component: it
hangs on a supply junction or a tee port and drains into a return junction,

```matlab
tee.portC.connect(building);        % the building takes the side branch of the tee
building.connect(returnJunction);   % and drains into a return junction
```

Its `inlet` and `outlet` are the supply and return ports of its branch. The declarative form is
`hn.connectBuilding(supplyJunction, building, returnJunction)`.

The substation can be ideal, with the exchanger's heat going straight to the zones, or it can have an
[internal loop](dhs-internal-loop.md) with a radiator and a valve at every zone. In the ideal case the heat
is shared between zones in proportion to their demand, $\text{area}\times\max(0,\ \text{setpoint} - T)$, which
is only a rough split. With a loop, each zone gets what its radiator gives.

## One zone

The default case is one thermal zone. You attach the RC model, the substation, the solar model and the
schedule one by one. A complete, runnable system is on [the system page](dhs-system.md).

```matlab
b  = sys.addBuilding('Engineering');
b.useRCModel(rcModel);                                    % any one-zone RCBS.Building
hx = DHS.IdealHeatExchanger('HX', 'Qnom',8e5);            % a building without an internal loop
b.attachHeatExchanger(hx);
hx.valve.attachController( DHS.controllers.PID(0.14, 1.6e-4, 0) );   % add measure and reference as in the system example
b.attachSolar( DHS.Solar('winArea',struct('N',40,'E',60,'S',80,'W',40), 'SHGC',0.44) );
b.attachSchedule( DHS.Schedule('occStartHour',7, 'occEndHour',18, 'Tocc',21, 'Tsetback',18) );
```

## Several zones

A building can have several zones, for example rooms on two storeys coupled by partition walls and floor slabs
(`+DHS/+examples/campus_multizone.m` has a thirty-zone campus). One substation still feeds the whole
building. The control loop regulates the area-weighted mean zone temperature toward the area-weighted mean
setpoint, and the delivered heat is divided among the zones by their heating demand. Ventilation and free
cooling act on each zone separately. You register each zone with `attachZone`, using the key
`"Storey.Zone"` from the RC model.

This annex has two zones coupled by a capacitive partition. It hangs on a plant like the one on the system page:

```matlab
rc = RCBS.Building();
rc.addStorey('S1');
rc.S1.addZone('Lobby');   rc.S1.Lobby.setAir(1.0e7, 20);
rc.S1.Lobby.addWall(0.0008, 1.5e8, [], 'Wall');
rc.S1.Lobby.addWindow(0.0012, 'Window');
rc.S1.addZone('Office');  rc.S1.Office.setAir(1.0e7, 20);
rc.S1.Office.addWall(0.0008, 1.5e8, [], 'Wall');
rc.S1.Office.addWindow(0.0030, 'Window');
rc.S1.Lobby.connectToZone(rc.S1.Office, 0.0005, 'Partition', 2e8);   % capacitive partition

sys = DHS.System('weather','solar_data_2025.csv', 'startDate',datetime(2025,1,1));
chp = sys.addCentralHeatPlant('CHP');
chp.addBoiler('B1', 'QMax',1.0e6);
chp.addPump('P0', 'dp0',3.0e5, 'mdotRated',6);
hn   = sys.addHydraulicNetwork();
tee1 = chp.supplyPort.addPipe(0.10, 40).addTee(0.05);
r1   = DHS.Hydraulic.Junction('R1', 'return');
r1.addPipe(0.10, 40).connect(chp.returnPort);

b  = sys.addBuilding('Annex');
b.useRCModel(rc);
hx = DHS.IdealHeatExchanger('HX', 'Qnom',1.5e5);
b.attachHeatExchanger(hx);
c = DHS.controllers.PID(0.14, 1.6e-4, 0);
c.measure = @(sys) sys.Annex.Tzone;  c.reference = @(sys) sys.Annex.setpoint;
hx.valve.attachController(c);

sched = DHS.Schedule('occStartHour',7, 'occEndHour',18, 'rampHours',1, 'Tocc',21, 'Tsetback',18);
b.attachZone('S1.Lobby',  'area',300, 'roomType','lobby',  'schedule',sched, ...
    'solar',DHS.Solar('winArea',struct('N',5,'E',15,'S',25,'W',15), 'SHGC',0.4, 'massFraction',0.1));
b.attachZone('S1.Office', 'area',300, 'roomType','office', 'schedule',sched, ...
    'solar',DHS.Solar('winArea',struct('N',5,'E',5,'S',5,'W',5), 'SHGC',0.4, 'massFraction',0.1));

tee1.portC.connect(b);
b.connect(r1);
res = sys.run(days(7));
```

`res.bldg(1).Tzones` holds one column per zone, in the order of `res.bldg(1).zoneNames` (`S1.Lobby`, `S1.Office`).
Both rooms stay between 17.8 and 21.4 degC, and their mean bias against the setpoint during occupied hours is
0.00 K and +0.04 K. With one substation the zones cannot be controlled separately, so rooms with very
different gains or ventilation drift apart, as the [campus example](examples.md) shows.

## What the building does at each step

`DHS.System.run` makes these calls. You rarely need them, but they are the place to look when you write a
custom co-simulation.

| Call | Inputs | Output or effect |
|---|---|---|
| `prepare(t, wx)` | time, weather sample | Samples the schedule and solar model (per zone if there are several). |
| `control(sys, dt)` | the `DHS.System`, step (s) | Runs the valve controller (and those of the booster pump, zone valves and loop pumps, if any) and returns the valve command in [0, 1]. |
| `solveInternalLoop()` | none | With an internal loop, solves its flows for the current valve positions and pump speeds. |
| `exchange(mdot, Tsup_hx)` | primary flow (kg/s), supply temperature at the exchanger (degC) | `[Qdel, Tret]`: delivered heat (W) and primary return temperature (degC). With a loop it also advances the loop water and the radiators. |
| `advance(dt, tNext, wx)` | step, next time, weather sample | Builds the node-heat vector and steps the RC model one interval. |

## Function reference

| Function or property | Inputs | Output or effect |
|---|---|---|
| `useRCModel(B)` | an `RCBS.Building` | Attaches the thermal model. Storeys, zones and elements become reachable by name, for example `sys.Annex.S1.Lobby.Wall.R`. |
| `addHeatExchanger(name, ...)` | name; heat exchanger properties | Creates, attaches and returns an `ENTUPlateHeatExchanger`, the type for a building with an internal loop ([heat exchangers](dhs-heat-exchanger.md)). |
| `attachHeatExchanger(hx)` | a `DHS.HeatExchanger` | Installs a pre-built substation: an `IdealHeatExchanger` (no loop), or a `FixedEffectivenessHeatExchanger` or `ENTUPlateHeatExchanger` (with a loop). |
| `connect(dst)`, `addPipe(...)`, `addValve(...)`, `addPump(...)` | see [internal loop](dhs-internal-loop.md) | Connect the building to its return junction, or create a component on the return side. |
| `.heatExchanger.internalOutlet`, `.internalInlet` | none | Where the internal loop starts and ends. |
| `attachSolar(s)`, `attachSchedule(s)` | a `DHS.Solar`, a `DHS.Schedule` | Set the boundary conditions of a one-zone building. |
| `attachZone(key, 'area',A, 'roomType',t, 'solar',s, 'schedule',sc, 'GventOcc',G, 'Ginf',Gi, 'freeCool',tf)` | `"Storey.Zone"`; floor area (m²), a label, per-zone models, and conductances (W/K) | Registers one zone of a multi-zone building. |
| `zoneTemp()` | none | The current zone temperature (degC); the area-weighted mean for several zones. |
| `.Tzone`, `.setpoint`, `.occupied` | none | The live zone temperature and setpoint (degC) and whether the building is occupied. For several zones they are the area-weighted means. |
| `.inlet`, `.outlet` | none | The supply and return ports of the branch. |
| `.connLength`, `.connD`, `.Kminor` | m, m, dimensionless | Service connection length (default 20), diameter (0.05) and the sum of minor-loss coefficients (8). `.connPipeSup` and `.connPipeRet` are the two pipes. |
| `.Ginf`, `.GventOcc` | W/K | Background infiltration and occupied-hours mechanical ventilation of a one-zone building. |
| `.freeCool`, `.freeCoolFactor`, `.freeCoolDeadband` | logical, factor, K | Winter free cooling during occupied hours (defaults true, 6, 0.5). |
| `.loopCapacity` | J/K | Heat capacity of the loop water; `NaN` (default) computes it from the pipe volumes. |
| `.integrator` | `'backwardEuler'`, `'forwardEuler'`, `'exact'` | How the building advances its loop water and radiators. `DHS.System` sets it. |
