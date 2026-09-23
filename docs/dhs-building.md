# DHS.Building: a building on the district loop

`DHS.Building` connects an `RCBS.Building` thermal model to the district network. It adds
the substation (a `DHS.HeatExchanger` with its valve and pump), a solar model, an
occupancy schedule, and the ventilation and free-cooling terms, and it computes every heat
flow that enters the RC nodes at each step. RCBS itself stays a pure RC library. The heat
is calculated here and injected into the right RCBS node with `RCBS.Simulation.stepOnce`.

A building is created with `system.addBuilding(name)` and attached to the network with
`hn.connectBuilding(junction, building)`. It exposes an `inlet` and an `outlet`, the
supply and return ports of its branch.

## One zone

The default case is a building with a single thermal zone. The RC model, the
substation, the solar model and the schedule are attached one by one:

```matlab
b  = sys.addBuilding('Engineering');
b.useRCModel(rcModel);                                        % any one-zone RCBS.Building
hx = b.addHeatExchanger('HX', 'UA',3.5e4, 'Qcap',8e5);
hx.valve.attachController( DHS.controllers.PID(0.14, 1.6e-4, 0) );
b.attachSolar( DHS.Solar('winArea',struct('N',40,'E',60,'S',80,'W',40), 'SHGC',0.44) );
b.attachSchedule( DHS.Schedule('occStartHour',7, 'occEndHour',18, 'Tocc',21, 'Tsetback',18) );
```

A complete, runnable one-zone system is given in [the system page](dhs-system.md).

## Several zones

A building can also have several zones, for example rooms on two storeys coupled by
partition walls and floor slabs (see `+DHS/+examples/campus_multizone.m` for a
thirty-zone campus). One substation still feeds the whole building. The control loop
regulates the area-weighted mean zone temperature toward the area-weighted mean setpoint.
The delivered heat is divided among the zones in proportion to each zone's current heating
demand, $\text{area}\times\max(0,\ \text{setpoint} - T_\text{zone})$, and ventilation and
free cooling act on each zone separately. Each zone is registered with `attachZone`, using
the key `"Storey.Zone"` as it is named in the RC model.

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

b  = sys.addBuilding('Annex');
b.useRCModel(rc);
hx = b.addHeatExchanger('HX', 'UA',6e3, 'Qcap',1.5e5);
hx.valve.attachController( DHS.controllers.PID(0.14, 1.6e-4, 0) );

sched = DHS.Schedule('occStartHour',7, 'occEndHour',18, 'rampHours',1, 'Tocc',21, 'Tsetback',18);
b.attachZone('S1.Lobby',  'area',300, 'roomType','lobby',  'schedule',sched, ...
    'solar',DHS.Solar('winArea',struct('N',5,'E',15,'S',25,'W',15), 'SHGC',0.4, 'massFraction',0.1));
b.attachZone('S1.Office', 'area',300, 'roomType','office', 'schedule',sched, ...
    'solar',DHS.Solar('winArea',struct('N',5,'E',5,'S',5,'W',5), 'SHGC',0.4, 'massFraction',0.1));
```

After a one-week run of this building on the same plant and pipe as in the system example,
`res.bldg(1).Tzones` holds one column per zone, ordered as `res.bldg(1).zoneNames`
(`S1.Lobby`, `S1.Office`). Both rooms stay between 17.8 and 21.4 degC, and their mean bias
against the setpoint during occupied hours is −0.07 K and −0.02 K. With a single
substation the zones cannot be controlled separately. Rooms with very different gains or
ventilation drift apart, as the campus example shows (worst room bias 1.5 K).

## What the building does at each step

`DHS.System.run` drives these four calls. You rarely need them directly, but they are the
place to look when writing a custom co-simulation.

| Call | Inputs | Output or effect |
|---|---|---|
| `prepare(t, wx)` | time, weather sample | Samples the schedule and solar model (per zone if there are several). |
| `control(dt, wx)` | step (s), weather sample | Runs the valve and pump controllers and returns the command in [0, 1]. |
| `exchange(mdot, Tsup_hx)` | primary flow (kg/s), supply temperature at the exchanger (degC) | `[Qdel, Tret]`: delivered heat (W) and primary return temperature (degC). |
| `advance(dt, tNext, wx)` | step, next time, weather sample | Builds the node-heat vector and steps the RC model one interval. |

## Function reference

| Function | Inputs | Output or effect |
|---|---|---|
| `useRCModel(B)` | an `RCBS.Building` | Attaches the thermal model. |
| `addHeatExchanger(name, ...)` | name; `HeatExchanger` properties | Creates, attaches and returns the substation ([heat exchanger page](dhs-heat-exchanger.md)). |
| `attachHeatExchanger(hx)` | a `DHS.HeatExchanger` | Installs a pre-built substation. |
| `attachSolar(s)`, `attachSchedule(s)` | a `DHS.Solar`, a `DHS.Schedule` | Sets the boundary conditions of a one-zone building. |
| `attachZone(key, 'area',A, 'roomType',t, 'solar',s, 'schedule',sc, 'GventOcc',G, 'Ginf',Gi, 'freeCool',tf)` | `"Storey.Zone"`; floor area (m²), a label, and per-zone models and conductances (W/K) | Registers one zone of a multi-zone building. |
| `zoneTemp()` | none | Current air-weighted zone temperature (degC). |
| `.inlet`, `.outlet` | none | Supply and return ports (`DHS.Hydraulic.Junction`). |
| `.connLength`, `.connD`, `.Kminor` | m, m, dimensionless | Service connection length (default 20), diameter (0.05) and sum of minor-loss coefficients (8). |
| `.Ginf`, `.GventOcc` | W/K | Background infiltration and occupied-hours mechanical ventilation (one-zone building). |
| `.freeCool`, `.freeCoolFactor`, `.freeCoolDeadband` | logical, factor, K | Winter free cooling during occupied hours. |
