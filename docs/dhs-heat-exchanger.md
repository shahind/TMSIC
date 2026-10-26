# DHS.HeatExchanger: the building substation

`DHS.HeatExchanger` is the heat exchanger at a building's substation, together with the control valve
and the pump on its primary (district) side. It transfers heat from the district water to the
building and sets the hydraulic resistance of the building's branch. It is an abstract class with
three types, in the same way a pump is a `CentrifugalPump` or a `FixedDisplacementPump`. Which one to use
depends on whether the building has an [internal loop](dhs-internal-loop.md):

| Building | Type | Heat | Parameters of its own |
|---|---|---|---|
| with an internal loop | `DHS.ENTUPlateHeatExchanger` | effectiveness–NTU of a counterflow plate exchanger between the district water and the loop water | `UA` |
| with an internal loop | `DHS.FixedEffectivenessHeatExchanger` | effectiveness fixed by the user, between the district water and the loop water | `effectiveness` |
| without a loop | `DHS.IdealHeatExchanger` | the exchanger is a simple radiator that the district water flows through (radiator law of EN 442) | `Qnom`, `dTnom`, `exponent` |

`building.addHeatExchanger(name, ...)` creates the default type, an `ENTUPlateHeatExchanger`, the way
`chp.addPump` creates a `CentrifugalPump`. Any other type is built and handed in:

```matlab
hx = building.addHeatExchanger('HX', 'UA',3.5e4, 'Qcap',8e5);                       % ENTUPlateHeatExchanger
hx = DHS.FixedEffectivenessHeatExchanger('HX', 'effectiveness',0.85, 'Qcap',8e5);   building.attachHeatExchanger(hx);
hx = DHS.IdealHeatExchanger('HX', 'Qnom',8e5);                                      building.attachHeatExchanger(hx);
```

All the parameters of a type (and the common ones below) are properties: set them when you create the
exchanger as name-value pairs, or later with `hx.effectiveness = 0.9`.

## Ports

An exchanger has four ports. The district side, `hx.districtInlet` and `hx.districtOutlet` (the building's
supply and return junctions), is connected to the district network with
`tee.portC.connect(building); building.connect(returnJunction)`. The internal side, `hx.internalOutlet` and
`hx.internalInlet`, is where the building's internal loop starts and ends. A loop exchanger
(`ENTUPlateHeatExchanger`, `FixedEffectivenessHeatExchanger`) needs both internal ports connected, and an
`IdealHeatExchanger` needs a building without a loop. A building that does not satisfy this stops at the
start of the run with an error that names the ports (`DHS:Building:heatExchangerPorts`,
`DHS:Building:idealWithLoop`), and a building that is not connected to the district network stops when the
system is compiled.

## Model

### With an internal loop

The heat depends on the district water and on the water coming back from the loop. With
$\dot C_p = \dot m_p c_p$ on the primary side, $\dot C_s = \dot m_s c_p$ on the internal side and
$\dot C_{\min} = \min(\dot C_p,\dot C_s)$, the heat and the temperatures are, with the delivery limited
to the substation's capacity $\dot Q_\text{cap}$ and prevented from reversing,

$$\dot Q = \mathrm{clip}\big(\varepsilon\,\dot C_{\min}(T_{p,\text{in}}-T_{s,\text{in}}),\,0,\,\dot Q_\text{cap}\big),\qquad
T_{p,\text{out}} = T_{p,\text{in}} - \dot Q/\dot C_p ,\qquad T_{s,\text{out}} = T_{s,\text{in}} + \dot Q/\dot C_s .$$

The two loop types differ in the effectiveness $\varepsilon$:

- **`ENTUPlateHeatExchanger`**: the effectiveness–NTU method for a counterflow exchanger (Incropera and
  DeWitt [12](references.md#r12)). With $C_r = \dot C_{\min}/\dot C_{\max}$ and $\mathrm{NTU} = UA/\dot C_{\min}$,

  $$\varepsilon = \begin{cases}\dfrac{1-e^{-\mathrm{NTU}(1-C_r)}}{1-C_r\,e^{-\mathrm{NTU}(1-C_r)}}, & C_r<1,\\[8pt] \dfrac{\mathrm{NTU}}{1+\mathrm{NTU}}, & C_r=1,\end{cases}$$

  so $\varepsilon$ changes with the flows. MATLAB/Simscape's Heat Exchanger (TL-TL) and Plate Heat Exchanger
  (TL-TL) blocks [56](references.md#r56), [57](references.md#r57) use the same relation; the plate version
  adds chevron-angle-dependent friction and Nusselt correlations and plate thermal mass, not replicated here.
- **`FixedEffectivenessHeatExchanger`**: $\varepsilon$ is the property `effectiveness` (0 to 1, default 0.8).
  The Modelica Buildings library's plate heat exchanger model (`PlateHeatExchangerEffectivenessNTU`) offers
  the same choice, a constant effectiveness with the default 0.8 [63](references.md#r63), and the City Energy
  Analyst sizes its substation exchangers for a design effectiveness of 0.9 [64](references.md#r64).

### Without an internal loop: the ideal exchanger

Without a loop the building side is not modelled, and there is no internal water for an exchanger to
exchange heat with. `IdealHeatExchanger` therefore stands for the whole substation and the emitters behind
it as a simple radiator that the district water flows through. The heat the radiator gives to the room is
proportional to the mean water-to-room temperature difference raised to a power $n$ (the characteristic
equation of radiators, EN 442), with the mean water temperature the arithmetic mean of supply and return:

$$\dot Q = \dot Q_\text{nom}\left(\frac{\bar T_w - T_\text{zone}}{\Delta T_\text{nom}}\right)^{n},\qquad
\bar T_w = T_{p,\text{in}} - \frac{\dot Q}{2\dot C_p},\qquad T_{p,\text{out}} = T_{p,\text{in}} - \frac{\dot Q}{\dot C_p}.$$

$\dot Q_\text{nom}$ is `Qnom`, the heat at the nominal temperature difference $\Delta T_\text{nom}$ = `dTnom`
(50 K, the EN 442 rating point of 75/65/20 °C), and $n$ = `exponent` (1.3). The heat depends on the
district supply temperature, the primary flow that the valve sets and the room temperature, and on nothing
else: the exchanger has no conductance and no effectiveness. `hx.idealTransfer` solves the equation for
$\dot Q$ by bisection (the left side grows and the right side falls with $\dot Q$, so the solution is unique),
limits it to `Qcap` (unlimited by default) and returns zero when the supply is no warmer than the room.

**References for the radiator law:**

- Skagestad and Mildenstein, the IEA District Heating and Cooling connection handbook [29](references.md#r29)
  (Part II, the passage before Table 11.2): the output of a heat
  emitter is a power of the ratio of mean temperatures, with the index $n$ = 1.3 for radiators, 1.4 for natural
  convectors and 1.0 for forced convectors, including the heating coils of air handling units, and the mean
  temperature is the mean of supply and return (76.5 °C for 82/71 °C). Use `exponent` 1.0 for an air handling unit coil.
- The European standards EN 442-1 and EN 442-2:2014 [60](references.md#r60) define the characteristic equation of radiators
  and convectors. Stauffer et al. [59](references.md#r59) quote the equation,
  $\Phi = \Phi_{50}((T_m - T_a)/50)^n$ with $T_m$ the mean of the measured inlet and outlet fluid temperatures
  and $n$ "typically 1.1 to 1.4", usually taken as 1.3, and list measured exponents of 1.28 to 1.37 (their Table 1).
- The Modelica Buildings library's `RadiatorEN442_2` model [62](references.md#r62) uses the same power law with the
  exponent as a parameter, default 1.24, and takes its nominal data from EN 442-2.
- Marchesi et al. [61](references.md#r61) measure how far a radiator's output departs from the standard's
  model when it is installed and operated away from the reference conditions.

The arithmetic mean temperature is a simplification of the logarithmic mean that is often used in rating
(at the 75/65/20 °C reference they are 50 K and 49.8 K).

### Pressure loss

The primary side loses pressure in the valve (see [the hydraulics page](dhs-hydraulic.md)) and in the exchanger body. A manufacturer quotes
the body loss as a design pressure drop at a design flow. Design guidance for a plate
exchanger in a district heating substation puts the primary-side drop at a few tens of
kPa: the IEA District Heating and Cooling programme's connection handbook gives below
20 kPa for the exchanger itself, with a separate 50 to 60 kPa target for the whole
substation's supply/return differential [29](references.md#r29). The toolbox takes the same two numbers,
`dpNomPrimary` and `mdotNomPrimary`, and computes

$$K_\text{hx} = \frac{\Delta p_\text{nom}}{\dot m_\text{nom}^2},\qquad
K_\text{primary} = K_\text{valve}(\text{pos}) + K_\text{hx}.$$

The loss is proportional to the square of the flow, as for a pipe or a valve, and each
unit has its own rating. If `mdotNomPrimary` is empty it defaults to
$\max(\dot Q_\text{cap}/(c_p\cdot 20\,\text{K}),\ 0.5)$ kg/s, which assumes a 20 K design
temperature drop. This is the same fixed $K=\Delta p_\text{nom}/\dot m_\text{nom}^2$ form as
the "Pressure loss coefficient" option of MATLAB/Simscape's Heat Exchanger (TL-TL) block
[56](references.md#r56).

## Example

A substation with 35 kW/K of conductance, an 800 kW delivery limit and a 30 kPa body loss
at 4.5 kg/s:

```matlab
hx = DHS.ENTUPlateHeatExchanger('HX', 'UA',3.5e4, 'Qcap',8e5, ...
        'dpNomPrimary',3.0e4, 'mdotNomPrimary',4.5);
hx.valve.Kvs = 18;  hx.valve.char = 'eqpct';  hx.valve.rangeability = 50;

[Q, Tret] = hx.transfer(4, 70, 45);     % 4 kg/s of 70 degC water, secondary return at 45 degC
% Q = 314.5 kW,  Tret = 51.2 degC

K = hx.primaryResistance(978);          % valve fully open: 4,182 + 1,481 = 5,663 Pa/(kg/s)^2
dp = K * 4.5^2;                         % 114.7 kPa at the design flow (84.7 kPa valve + 30 kPa body)
```

The same flows and temperatures through the fixed-effectiveness type, with the default internal flow of 6 kg/s:

```matlab
fx = DHS.FixedEffectivenessHeatExchanger('HX', 'effectiveness',0.85, 'Qcap',8e5);
[Q, Tret] = fx.transfer(4, 70, 45);     % Q = 355.8 kW,  Tret = 48.8 degC
```

The ideal exchanger of a building without a loop, a radiator for 800 kW at 50 K, with 4 kg/s of 70 °C water and the room at 20 °C:

```matlab
id = DHS.IdealHeatExchanger('HX', 'Qnom',8e5, 'dTnom',50, 'exponent',1.3);
[Q, Tret] = id.idealTransfer(4, 70, 20);
% Q = 502.9 kW,  Tret = 40.0 degC
```

Inside a building the exchanger's valve sets the building's flow and receives a controller
(`hx.valve.attachController(c)`). Its pump is a booster in series with the valve and is
stopped by default; set `hx.pump.speed`, attach a controller, or install a different pump to use it:

```matlab
hx = DHS.IdealHeatExchanger('HX', 'Qnom',8e5);   building.attachHeatExchanger(hx);
c = DHS.controllers.PID(0.14, 1.6e-4, 0);
c.measure = @(sys) building.Tzone;  c.reference = @(sys) building.setpoint;   % zone temperature held at the setpoint
hx.valve.attachController(c);
hx.attachPump( DHS.Hydraulic.FixedDisplacementPump('HX.pump', 'mdotRated',4, 'dpMax',2.5e5) );
```

## Function reference

| Function | Inputs | Output or effect |
|---|---|---|
| `ENTUPlateHeatExchanger(name, 'UA',.., 'Qcap',.., ...)` | name; conductance (W/K, default 4e4) and the common parameters below | The counterflow plate exchanger of a building with a loop. |
| `FixedEffectivenessHeatExchanger(name, 'effectiveness',.., 'Qcap',.., ...)` | name; effectiveness (0 to 1, default 0.8) and the common parameters | Fixed effectiveness, for a building with a loop. |
| `IdealHeatExchanger(name, 'Qnom',.., 'dTnom',.., 'exponent',.., ...)` | name; heat (W, 5e5) at the nominal temperature difference (K, 50) and the exponent (1.3), and the common parameters | The simple radiator of a building without a loop; `Qcap` is unlimited by default. |
| common parameters | `Qcap` (W, 5e5), `internalVolume` (L, 5), `cp`, `dpNomPrimary` (Pa, 3e4), `mdotNomPrimary` (kg/s, from `Qcap`) | Set as name-value pairs or by assignment. Every exchanger has a default valve and a default centrifugal pump, stopped (`speed` 0). |
| `mdotSecNom` | kg/s (6) | Loop types only: the internal flow assumed when `transfer` is called without one. |
| `usesInternalLoop()` | none | True for the loop types, false for `IdealHeatExchanger`. |
| `effectivenessCmin(mdotPrimary, mdotSec)` | the two flows (kg/s) | Loop types: $\varepsilon\,\dot C_{\min}$ in W/K, what distinguishes them. |
| `transfer(mdotPrimary, TsupPrimary, TsecIn, mdotSec)` | primary flow (kg/s), primary supply and secondary inlet temperatures (degC), internal flow (kg/s, default `mdotSecNom`) | Loop types: `[Qdel, TretPrimary, TsecOut]`: delivered heat (W), primary return temperature (degC) and the internal water leaving the exchanger (degC). A building passes the loop's actual flow and return temperature. |
| `idealTransfer(mdotPrimary, TsupPrimary, Tzone)` | primary flow (kg/s), primary supply and zone air temperatures (degC) | `IdealHeatExchanger`: `[Qdel, TretPrimary]`, the heat and the primary return temperature of the radiator law above. |
| `primaryResistance(rho)` | density (kg/m³) | $K_\text{primary}$ in Pa/(kg/s)². |
| `attachPump(pump)` | any `DHS.Hydraulic.Pump` | Installs a pre-built primary booster pump, reachable under its own name. It runs at full speed until `speed` is changed. |
| `attachValve(valve)` | a `DHS.Hydraulic.Valve` | Installs a pre-built primary valve, reachable under its own name: `hx.attachValve(DHS.Hydraulic.Valve('V1','Kvs',12))` gives `hx.V1.Kvs`. |
| `.valve`, `.pump` | none | The owned valve and booster pump. Attach a controller to either with `attachController(c)`; the controller chooses what to measure. |
| `.districtInlet`, `.districtOutlet` | none | The host building's supply and return junctions (the district side). |
| `.internalOutlet`, `.internalInlet` | none | The supply and return junctions of the building's internal loop, where its first pipe starts and its last pipe ends. The first use of either creates the loop. |
| `.Qdel`, `.TretPrimary` | none | Live delivered heat and primary return temperature. |
