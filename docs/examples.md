# Examples

The scripts in `examples/` run without extra data. Each one prints a short summary and draws figures. Run `setup`
once per session, then call a script by name:

```matlab
setup
rcbs_tutorial
```

The tutorials are written to be read. They use long names, one call per line and a comment on every step, so you
can copy the part you need and change the numbers. The other scripts are larger studies.

| Script | What it shows | Run time |
|---|---|---|
| `rcbs_tutorial.m` | A two-zone building built call by call: zones, wall, window, internal mass, a partition, a scheduled heater, simulation, plots, changing a parameter by name, and the state-space export. | 1 s |
| `dhs_tutorial.m` | The smallest district heating system: a plant with one boiler and one pump, a supply pipe, a tee, a return pipe, and one building with an ideal substation, a PID valve controller, solar gains and a schedule. | 5 s |
| `dhs_internal_loop_tutorial.m` | The same building with its own water loop: a plate heat exchanger, a loop pump, a radiator with a zone valve, a bypass, and three controllers. | 10 s |
| `RCBS_example.m` | A three-storey, seven-zone building: walls, windows, internal mass, capacitive partitions and slabs, open air paths, two heat inputs. It simulates three days and draws the schematic. | 1 s |
| `dhs_campus.m` | A five-building campus on one gas plant, run for 14 days. The assembly is in `+DHS/+examples/campus.m`. | 1 min |
| `dhs_campus_with_bypass.m` | The campus with an end-of-line bypass added by one `addBypass` call, and the flow through it plotted. | 1 min |
| `dhs_campus_multizone.m` | The campus with 30 zones of different room types, each with a radiator and valve. It prints the temperature error of every zone. | 3 min |
| `system_identification.m` | Fits a 10-parameter single-zone RC model to a temperature record with `fmincon` and checks it on held-out data. | 15 s |
| `multi_zone_system_identification.m` | The same for an eight-zone building with 75 parameters and eight measured zone temperatures. | 2.5 min |

## rcbs_tutorial

Builds a laboratory and a corridor, couples them with a partition, heats the laboratory from 08:00 to 18:00 and
simulates three days. It then makes the window twice as good by writing `lab.Window.R = 0.02` and simulates
again. The laboratory minimum rises from 11.5 to 13.9 degC. The last step exports a 5-state model with
`getStateSpace`. See [the RCBS page](rcbs-building.md) for every call.

## dhs_tutorial

The assembly follows the order of the plant diagram:

1. the thermal model of the building (RCBS);
2. the system and its weather file;
3. the plant: `addCentralHeatPlant`, `addBoiler`, `addPump`;
4. the pipes: `Pipe`, `TJunction` and `Junction`, wired with `connect`;
5. the building: `addBuilding`, `useRCModel`, `attachHeatExchanger`, `attachController`, `attachSolar` and
   `attachSchedule`;
6. `tee.portC.connect(building)` and `building.connect(return_junction)`;
7. `visualize`, `run` and the plots.

Expected output: the hall is within 0.003 K of its 21 degC setpoint on average during occupied hours (root-mean-square
0.021 K), the plant supply temperature stays between 69.4 and 75.5 degC, and the boiler burns 13,585 kWh over the week
to deliver 10,257 kWh to the hall.

To adapt it, change the numbers in step 1 for your building, the lengths and diameters in step 4 for your network,
and the schedule in step 5. To add a second building, repeat steps 1, 5 and 6 with a second tee. See
[the system page](dhs-system.md), [the hydraulics page](dhs-hydraulic.md) and
[the building page](dhs-building.md).

## dhs_internal_loop_tutorial

The building has a plate heat exchanger and a loop instead of an ideal substation. The script builds the loop
from the heat exchanger's internal outlet to its internal inlet and attaches three controllers: the zone valve
holds the room temperature, the loop pump holds the loop flow, and the district valve holds the loop supply
temperature.

Expected output: the hall is within 0.002 K of its setpoint on average (root-mean-square 0.07 K), the loop
supply temperature is 58.7 to 61.3 degC for 90 % of the week, the loop holds 1,143 litres of water, the exchanger
delivers 10,138 kWh and the radiator gives 9,885 kWh to the hall. See
[the internal loop page](dhs-internal-loop.md).

## The campus examples

`DHS.examples.campus` builds five buildings (Administration, Arts, Science, Engineering, Library) on one plant
with a branching supply and return main. Each building has an RC model, a plate heat exchanger, an internal loop
with a zone valve and radiator, a solar model and a weekly schedule. The function is one long script of
assembly calls: read it next to `dhs_campus.m` to see how a larger system is put together.

| Script | Result over 14 days |
|---|---|
| `dhs_campus.m` | The plant supply temperature stays between 63.4 and 74.2 degC around its 70 degC setpoint, the boiler efficiency is 0.876 to 0.942, and the energy balance closes to 0.00 %. |
| `dhs_campus_with_bypass.m` | Adds `hn.addBypass(hn.T_Engineering, hn.R_Engineering, 'L',10, 'D',0.05, 'Kvs',1.5)` before `compile`. About 12 % of the flow passes through the bypass (mean 0.67 kg/s), and the script prints the share. |
| `dhs_campus_multizone.m` | 30 zones. A building-level control loop cannot hold rooms with very different gains and ventilation, so the dining rooms run warm: the worst room is about 2.6 K above its setpoint during occupied hours. |

## The identification examples

Both scripts use an `RCBS.Building` as the forward model. They do five things:

1. choose a topology (from R1C1 up to R5C4);
2. build it as an `RCBS.Building` and export its state-space form;
3. simulate it over the measured inputs;
4. adjust the parameters with `fmincon` until the simulated temperature matches the measurement, on a training
   slice;
5. check the fit on a held-out slice.

The hidden initial temperatures are not parameters: for a linear model they follow from one least-squares solve.
If your workspace holds the structures `data` and `data_validation` (a `datetime` or seconds vector `t`, the
indoor temperature `T_in`, the outdoor temperature `T_out`, and the measured heat `Q_in_data`), the script
fits your data. Otherwise it generates a synthetic record from a known building, so that the fit can be graded.
On the synthetic record the single-zone validation error is 0.15 degC. The multi-zone script recovers the
well-conditioned parameters (windows, infiltration, air capacity) to within a few percent and shows which slow
wall parameters the temperature data constrain only loosely.
