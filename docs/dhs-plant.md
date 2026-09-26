# DHS.CentralHeatPlant and DHS.Boiler: the heat source

`DHS.CentralHeatPlant` models the water side of a gas-fired heat plant and the control
loop that fires its burner. It holds one or more `DHS.Boiler` objects (each a burner
capacity with a part-load efficiency curve) and one central pump. The plant is created
with `system.addCentralHeatPlant(name)` and is connected to the pipe network through its
`supplyPort` and `returnPort`.

## Model

Three stirred-tank water masses in series represent the return header ($C_{w,rh}$), the
boiler and its buffer ($C_w$) and the supply header ($C_{w,sh}$). A low-loss header sends
surplus boiler-loop flow back to the return whenever the network draws less than the
minimum boiler flow $\dot m_{B,\min}$. With $\dot m_B = \max(\dot m_\text{net}, \dot m_{B,\min})$,
a recirculation fraction $f_\text{rec} = \max(0,\,(\dot m_B - \dot m_\text{net})/\dot m_B)$,
$\dot C_B = \dot m_B c_p$ and one implicit step of size $\Delta t$, the three water
temperatures are

$$T_{rh}^+ = \frac{(C_{w,rh}/\Delta t)\,T_{rh} + \dot C_B\big[(1-f_\text{rec})T_\text{ret,net} + f_\text{rec}T_\text{sup}\big]}{C_{w,rh}/\Delta t + \dot C_B},$$

$$T_b^+ = \frac{(C_w/\Delta t)\,T_b + \eta\,\dot Q_\text{gas} + \dot C_B\,T_{rh}^+ - \dot Q_\text{base} - \dot Q_\text{standby}}{C_w/\Delta t + \dot C_B},$$

$$T_\text{sup}^+ = \frac{(C_{w,sh}/\Delta t)\,T_\text{sup} + \dot C_B\,T_b^+}{C_{w,sh}/\Delta t + \dot C_B}.$$

The efficiency of a condensing boiler rises as the return water cools ([32](references.md#r32)). `Boiler.etaOf` uses a supplied curve or the line

$$\eta(T_\text{ret}) = \mathrm{clip}\big(\eta_\text{ref} - \sigma\,(T_\text{ret} - T_{\eta,\text{ref}}),\ \eta_\text{min},\ \eta_\text{max}\big),$$

with defaults $\eta_\text{ref} = 0.92$ at 50 degC, $\sigma = 0.0025$ per K, and limits 0.80
and 0.98.

A firing fraction $u \in [0,1]$ from a controller (by default a PID on the sensor-lagged
supply temperature) sets the gas input $\dot Q_\text{gas} = u\,\dot Q_\text{gas,max}$. The
change in $u$ is limited by a slew rate, and a high-limit aquastat cuts the burner when the
boiler water reaches $T_{b,\max}$. The controller works to hold the supply temperature at
a fixed setpoint while the load and the return temperature swing.

## Example

```matlab
chp = sys.addCentralHeatPlant('CHP');
chp.Cw = 8.0e7;  chp.Cw_rh = 4.0e6;  chp.Cw_sh = 5.0e6;      % water masses [J/K]
chp.mdotMinBoiler = 2.5;  chp.TboilerMax = 90;               % low-loss header, aquastat
chp.setSupplySetpoint(70);                                   % supply setpoint [degC]

boiler1 = chp.addBoiler('B1', 'QMax',1.5e6, 'etaRef',0.92, 'etaSlope',0.0025);
pump0   = DHS.Hydraulic.CentrifugalPump('P0', 'dp0',3.0e5, 'mdotMax',14);
chp.attachPump(pump0);                                       % any DHS.Hydraulic.Pump
boiler1.connectTo(pump0);                                    % records the link for the drawing
chp.attachFiringController( DHS.controllers.PID(0.045, 3e-5, 1.5, 150) );

boiler1.etaOf(30)    % 0.970
boiler1.etaOf(60)    % 0.895
boiler1.etaOf(80)    % 0.845
```

In the five-building campus example (`+DHS/+examples/campus.m`) this plant holds the
supply temperature between 65.8 and 74.9 degC around a 70 degC setpoint over 14 days,
its efficiency ranges from 0.885 to 0.927, and its peak gas input is 1,108 kW against a
1,500 kW capacity.

## Function reference

### `DHS.CentralHeatPlant`

| Function | Inputs | Output or effect |
|---|---|---|
| `CentralHeatPlant(name)` | name | A plant with a default firing PID and the two ports `supplyPort` and `returnPort`. |
| `addBoiler(name, ...)` | name; `Boiler` properties as name-value pairs | Creates a `DHS.Boiler`, adds it to the plant and returns it. |
| `addPump(name, 'dp0',.., 'mdotMax',..)` | name; pump properties | Builds a `CentrifugalPump`, installs it as the central pump and returns it. |
| `attachPump(pump)` | any `DHS.Hydraulic.Pump` | Installs a pre-built pump, for example a `FixedDisplacementPump`. |
| `attachFiringController(c)` | a `DHS.controllers.Controller` | Replaces the burner-firing law. |
| `setSupplySetpoint(T)` | temperature (degC) | Sets the fixed supply setpoint. |
| `QgasMax()` | none | Sum of the boilers' `QMax` (W). |
| `.Cw`, `.Cw_rh`, `.Cw_sh` | J/K | Water-mass heat capacities. |
| `.mdotMinBoiler`, `.TboilerMax`, `.standbyLossW` | kg/s, degC, W | Minimum boiler-loop flow, aquastat limit, standby loss. |
| `.sensorTau`, `.firingSlewPerMin` | s, 1/min | Supply-sensor lag and the limit on the change of firing fraction. |
| `.Tboiler`, `.TretHdr`, `.Tsupply`, `.Qgas`, `.Qboiler`, `.eta`, `.firing` | none | Live state, updated every step. |

### `DHS.Boiler`

| Function | Inputs | Output or effect |
|---|---|---|
| `Boiler(name, 'QMax',W, 'etaCurve',f, 'etaRef',.., 'etaSlope',.., 'TetaRef',.., 'etaMin',.., 'etaMax',..)` | name; capacity (W); optional curve `@(Tret)` returning efficiency; line parameters | A burner stage. Normally created with `chp.addBoiler`. |
| `etaOf(Tret)` | return-water temperature (degC) | Efficiency between 0 and 1. |
| `connectTo(pump)` | a pump | Records that the boiler discharges into `pump`, for the drawing. |
| `connectToPipe('output', pipe)` | port name, a `Pipe` | Port-wiring: connects `pipe` to the plant's supply port. The boiler and pump form one lumped pressure node, so a pipe wired between them has no resistance of its own. |
| `outlet()` | none | The plant's supply port. |
