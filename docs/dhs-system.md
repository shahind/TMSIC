# DHS.System: assembling and running a district heating system

`DHS.System` is the top-level object of the district heating package. It owns one
central heat plant, one hydraulic network and any number of buildings, and it advances
all of them together on a fixed time step. You build a system by naming its parts and
connecting them, then call `run`. Assembly code follows the plant diagram, so a
reader can compare the script with the drawing.

![Schematic of the five-building campus drawn by system.visualize()](images/dhs_schematic.png)

## Example

Below, a script builds a one-building system, draws it and simulates one week. It models an
office hall with a 4 kW/K envelope, a substation with a PID-controlled valve, and a
schedule that occupies the hall from 07:00 to 18:00.

```matlab
rc = RCBS.Building();                                    % thermal model of the hall
rc.addStorey('S1');
rc.S1.addZone('Hall');
rc.S1.Hall.setAir(2e7, 20);
rc.S1.Hall.addWall(0.0004, 3e8, [], 'Wall');
rc.S1.Hall.addWindow(0.00067, 'Window');
rc.S1.Hall.addInternalMass(0.0002, 5e8, [], 'Mass');

sys = DHS.System('weather','solar_data_2025.csv', 'startDate',datetime(2025,1,1));

chp = sys.addCentralHeatPlant('CHP');                    % plant: one boiler, one pump
chp.addBoiler('B1', 'QMax',1.0e6);
chp.addPump('P0', 'dp0',3.0e5, 'mdotMax',12);
chp.setSupplySetpoint(70);

hn = sys.addHydraulicNetwork();                          % network: one tee, one pipe
t1 = hn.addJunction('T1');
hn.addPipe(chp.supplyPort, t1, 'L',40, 'D',0.10);

b  = sys.addBuilding('Hall');                            % building and its substation
b.useRCModel(rc);
hx = b.addHeatExchanger('HX', 'UA',8e3, 'Qcap',2e5);
hx.valve.attachController( DHS.controllers.PID(0.14, 1.6e-4, 0) );
b.attachSolar( DHS.Solar('winArea',struct('N',20,'E',20,'S',20,'W',20), ...
    'SHGC',0.4, 'massFraction',0.1) );
b.attachSchedule( DHS.Schedule('occStartHour',7, 'occEndHour',18, 'rampHours',1, ...
    'Tocc',21, 'Tsetback',18, 'gainOccW',20e3, 'gainMassFraction',0.3) );
hn.connectBuilding(t1, b);

sys.visualize();                                         % draw the assembled system
res = sys.run(days(7));                                  % 10,081 one-minute steps
```

Running it takes about 5 s. During occupied hours the zone temperature follows the 21 degC
setpoint with a mean bias of +0.02 K and a root-mean-square deviation of 0.07 K, and it
falls to 17.6 degC overnight. Supply temperature at the plant stays between 69.5 and
75.8 degC around its 70 degC setpoint. Over the week the boiler burns 13,511 kWh of gas
and the substation delivers 10,102 kWh to the building. Closure of the energy balance
is 1e-10 of the gas input, the quantity `res.energy.closure_err` reports.

The result structure has the fields below. Every field is a vector with one value per
time step unless stated otherwise.

| Field | Content |
|---|---|
| `res.time`, `res.Tout` | Time stamps (`datetime`) and outdoor temperature (degC). |
| `res.plant.Tsupply`, `.Tboiler`, `.Treturn`, `.TreturnNet`, `.TsupSet` | Plant temperatures (degC): supply, boiler water, return header, return from the network, supply setpoint. |
| `res.plant.Qgas`, `.Qboiler`, `.Qdist_loss`, `.Qbase`, `.eta`, `.firing` | Gas input, heat to the water, distribution loss (W), base load (W), efficiency, burner firing fraction. |
| `res.plant.Mtot`, `.dpPump`, `.pSupHeader` | Total flow (kg/s), central pump head (Pa) and supply-header gauge pressure (Pa). |
| `res.bldg(i).Tzone`, `.setpoint`, `.Tzones`, `.zoneNames` | Air temperature and setpoint (degC); per-zone temperatures for a multi-zone building. |
| `res.bldg(i).Qdeliv`, `.Qsolar`, `.Qint`, `.Qvent`, `.Qfreecool` | Heat delivered by the substation, solar gain, internal gain, ventilation loss, free cooling (W). |
| `res.bldg(i).valve`, `.pump`, `.mdot`, `.vel` | Valve position and pump speed (0 to 1), branch flow (kg/s), velocity (m/s). |
| `res.bldg(i).Tsup_hx`, `.Tret_primary`, `.pSup`, `.pRet` | Primary supply and return temperatures at the exchanger (degC) and gauge pressures at the tee (Pa). |
| `res.energy.gas_kWh`, `.boiler_kWh`, `.delivered_kWh`, `.dist_loss_kWh`, `.base_kWh` | Scalars: energy totals over the run. |
| `res.energy.plant_eff`, `.closure_err` | Scalars: delivered plus losses over gas input, and the relative closure error of the energy balance. |

## What happens in one time step

The scheme is sequential (Gauss–Seidel), with an inner loop that makes the plant supply
temperature consistent with the network return.

1. Sample the weather.
2. Each building's schedule and solar model produce a setpoint, occupancy and heat gains.
3. Each building's controllers compute valve and pump commands.
4. Branch flows, velocities and node pressures come from the hydraulic network solve.
5. The plant's firing controller sets the burner input.
6. Supply-pipe heat loss sets each exchanger's inlet temperature, each exchanger delivers
   heat, return-pipe loss and mixing set the plant return temperature, and the boiler is
   re-evaluated. Step 6 repeats `couplingIterations` times.
7. New water temperatures are committed to the plant.
8. Each building advances its RC model by one step.
9. Signals are logged and `stepCallback(sys, k, t)` is called.

## Function reference

| Function | Inputs | Output or effect |
|---|---|---|
| `DHS.System('weather',csv, 'startDate',dt, 'timeStep',dur, 'couplingIterations',n, 'pumpFrac',f, 'baseHeatW',W)` | All optional. `weather`: Solcast-style CSV; `timeStep`: `duration` (default 60 s); `pumpFrac`: central pump speed, 0 to 1 | A system with no parts yet. |
| `addCentralHeatPlant(name)` | name | A `DHS.CentralHeatPlant` ([plant page](dhs-plant.md)). |
| `addHydraulicNetwork()` | none | A `DHS.HydraulicNetwork`, linked to the plant's ports ([hydraulics page](dhs-hydraulic.md)). |
| `addBuilding(name)` | name | A `DHS.Building` ([building page](dhs-building.md)). |
| `setWeather(csv)` | path to CSV | Loads or replaces the weather source. |
| `compile()` | none | Freezes the topology. `run` calls it when needed. |
| `run(duration)` | a `duration`, for example `days(14)` | The result structure described above. |
| `visualize()` | none | Draws the plant, the mains, every T-junction and every building with its pump type, valve, exchanger and controllers. |
| `snapshot()` | none | The live state, for use inside `stepCallback`. |
| `.stepCallback` | `@(sys,k,t) ...` | Called after every step. Use it to log extra signals or to steer the run. |
| `.pumpFrac` | 0 to 1 | Speed of the central pump. |

A weather file must cover the simulated period. `solar_data_2025.csv` covers 1 January
to 30 June 2025, and `DHS.Weather` warns and clamps to the nearest sample outside that
range.
