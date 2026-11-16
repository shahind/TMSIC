# DHS.HeatExchanger: the building substation

`DHS.HeatExchanger` is the heat exchanger at a building's substation, together with the control valve and the
pump on its primary (district) side. It passes heat from the district water to the building and sets the
hydraulic resistance of the building's branch. It is an abstract class with three types, in the same way a pump
is a `CentrifugalPump` or a `FixedDisplacementPump`. The choice depends on whether the building has an
[internal loop](dhs-internal-loop.md):

| Building | Type | Heat | Parameters of its own |
|---|---|---|---|
| with an internal loop | `DHS.ENTUPlateHeatExchanger` | effectiveness–NTU of a counterflow plate exchanger between the district water and the loop water | `UA` |
| with an internal loop | `DHS.FixedEffectivenessHeatExchanger` | a fixed effectiveness between the district water and the loop water | `effectiveness` |
| without a loop | `DHS.IdealHeatExchanger` | the exchanger and the emitters behind it act as one radiator that the district water flows through (EN 442 radiator law) | `Qnom`, `dTnom`, `exponent` |

`building.addHeatExchanger(name, ...)` creates the default type, an `ENTUPlateHeatExchanger`, the way
`chp.addPump` creates a `CentrifugalPump`. Any other type is built and handed in:

```matlab
hx = building.addHeatExchanger('HX', 'UA',3.5e4, 'Qcap',8e5);                       % ENTUPlateHeatExchanger
hx = DHS.FixedEffectivenessHeatExchanger('HX', 'effectiveness',0.85, 'Qcap',8e5);   building.attachHeatExchanger(hx);
hx = DHS.IdealHeatExchanger('HX', 'Qnom',8e5);                                      building.attachHeatExchanger(hx);
```

Each parameter is a property. Set it when you create the exchanger as a name-value pair, or later, for example
`hx.effectiveness = 0.9`.

## Ports

An exchanger has four ports. The district side, `hx.districtInlet` and `hx.districtOutlet`, is the building's supply
and return junctions, joined to the network with `tee.portC.connect(building); building.connect(returnJunction)`.
The internal side, `hx.internalOutlet` and `hx.internalInlet`, is where the internal loop starts and ends.

A loop exchanger needs both internal ports connected, and an `IdealHeatExchanger` needs a building without a
loop. A building that breaks this rule stops at the start of the run with an error that names the ports
(`DHS:Building:heatExchangerPorts` or `DHS:Building:idealWithLoop`). A building that is not connected to the
district network stops when the system is compiled.

## Models

### With an internal loop

The heat depends on the district water and on the water coming back from the loop. With
$\dot C_p = \dot m_p c_p$ on the primary side, $\dot C_s = \dot m_s c_p$ on the internal side and
$\dot C_{\min} = \min(\dot C_p,\dot C_s)$, the heat and the temperatures are the following, with the delivery
limited to the substation's capacity $\dot Q_\text{cap}$ and prevented from reversing:

$$\dot Q = \mathrm{clip}\big(\varepsilon\,\dot C_{\min}(T_{p,\text{in}}-T_{s,\text{in}}),\,0,\,\dot Q_\text{cap}\big),\qquad
T_{p,\text{out}} = T_{p,\text{in}} - \dot Q/\dot C_p ,\qquad T_{s,\text{out}} = T_{s,\text{in}} + \dot Q/\dot C_s .$$

The two loop types differ in the effectiveness $\varepsilon$:

- **`ENTUPlateHeatExchanger`** uses the effectiveness–NTU method for a counterflow exchanger (Incropera and
  DeWitt [12](references.md#r12)). With $C_r = \dot C_{\min}/\dot C_{\max}$ and $\mathrm{NTU} = UA/\dot C_{\min}$,

  $$\varepsilon = \begin{cases}\dfrac{1-e^{-\mathrm{NTU}(1-C_r)}}{1-C_r\,e^{-\mathrm{NTU}(1-C_r)}}, & C_r<1,\\[8pt] \dfrac{\mathrm{NTU}}{1+\mathrm{NTU}}, & C_r=1,\end{cases}$$

  so $\varepsilon$ changes with the flows. MATLAB/Simscape's Heat Exchanger (TL-TL) and Plate Heat Exchanger
  (TL-TL) blocks [56](references.md#r56), [57](references.md#r57) use the same relation. The plate version also
  has chevron-angle friction and Nusselt correlations and plate thermal mass, which are not replicated here.
- **`FixedEffectivenessHeatExchanger`** takes $\varepsilon$ from the property `effectiveness` (0 to 1, default
  0.8). The Modelica Buildings library's plate exchanger offers the same choice, with a default of 0.8
  [63](references.md#r63), and the City Energy Analyst sizes its substation exchangers for a design
  effectiveness of 0.9 [64](references.md#r64).

### Without an internal loop: the ideal exchanger

Without a loop the building side is not modelled, so there is no internal water to exchange heat with.
`IdealHeatExchanger` stands for the whole substation and the emitters behind it as one radiator that the
district water flows through. The heat the radiator gives to the room is proportional to the mean
water-to-room temperature difference raised to a power $n$ (the characteristic equation of radiators, EN 442),
with the mean water temperature the average of supply and return:

$$\dot Q = \dot Q_\text{nom}\left(\frac{\bar T_w - T_\text{zone}}{\Delta T_\text{nom}}\right)^{n},\qquad
\bar T_w = T_{p,\text{in}} - \frac{\dot Q}{2\dot C_p},\qquad T_{p,\text{out}} = T_{p,\text{in}} - \frac{\dot Q}{\dot C_p}.$$

$\dot Q_\text{nom}$ is `Qnom`, the heat at the nominal temperature difference $\Delta T_\text{nom}$ = `dTnom` (50 K,
the EN 442 rating point of 75/65/20 °C), and $n$ = `exponent` (1.3). The heat depends only on the district supply
temperature, the primary flow that the valve sets, and the room temperature. The exchanger has no conductance and
no effectiveness. `hx.idealTransfer` solves the equation for $\dot Q$ by bisection (the left side grows and the
right side falls with $\dot Q$, so the solution is unique), limits it to `Qcap` (unlimited by default), and
returns zero when the supply is no warmer than the room.

**References for the radiator law.**

- Skagestad and Mildenstein, the IEA District Heating and Cooling connection handbook [29](references.md#r29)
  (Part II, the passage before Table 11.2): the output of an emitter is a power of the ratio of mean
  temperatures, with $n$ = 1.3 for radiators, 1.4 for natural convectors and 1.0 for forced convectors, including
  the heating coils of air handling units. Use `exponent` 1.0 for an air handling unit coil.
- The European standards EN 442-1 and EN 442-2:2014 [60](references.md#r60) define the characteristic equation.
  Stauffer et al. [59](references.md#r59) quote it as $\Phi = \Phi_{50}((T_m - T_a)/50)^n$ with $n$ "typically 1.1
  to 1.4", usually 1.3, and list measured exponents of 1.28 to 1.37.
- The Modelica Buildings library's `RadiatorEN442_2` model [62](references.md#r62) uses the same power law with the
  exponent as a parameter (default 1.24).
- Marchesi et al. [61](references.md#r61) measure how far a radiator's output departs from the standard's model
  away from the reference conditions.

The arithmetic mean temperature is a simplification of the logarithmic mean that is often used in rating. At the
75/65/20 °C reference they are 50 K and 49.8 K.

### Pressure loss

The primary side loses pressure in the valve (see [hydraulics](dhs-hydraulic.md)) and in the exchanger body. A
manufacturer quotes the body loss as a design pressure drop at a design flow. Design guidance for a plate
exchanger in a district heating substation puts it below 20 kPa, with a separate 50 to 60 kPa target for the
whole substation's supply/return differential [29](references.md#r29). The toolbox takes the two numbers
`dpNomPrimary` and `mdotNomPrimary` and computes

$$K_\text{hx} = \frac{\Delta p_\text{nom}}{\dot m_\text{nom}^2},\qquad
K_\text{primary} = K_\text{valve}(\text{pos}) + K_\text{hx}.$$

The loss is proportional to the square of the flow, as for a pipe or a valve, and each unit has its own rating. If
`mdotNomPrimary` is empty it defaults to $\max(\dot Q_\text{cap}/(c_p\cdot 20\,\text{K}),\ 0.5)$ kg/s, which assumes
a 20 K design temperature drop. This is the same form as the "Pressure loss coefficient" option of
MATLAB/Simscape's Heat Exchanger (TL-TL) block [56](references.md#r56).

## Example

A substation with 35 kW/K of conductance, an 800 kW delivery limit and a 30 kPa body loss at 4.5 kg/s:

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

The ideal exchanger of a building without a loop: a radiator for 800 kW at 50 K, with 4 kg/s of 70 °C water and the
room at 20 °C:

```matlab
id = DHS.IdealHeatExchanger('HX', 'Qnom',8e5, 'dTnom',50, 'exponent',1.3);
[Q, Tret] = id.idealTransfer(4, 70, 20);
% Q = 502.9 kW,  Tret = 40.0 degC
```

Inside a building, the exchanger's valve sets the building's flow and takes a controller
(`hx.valve.attachController(c)`). Its pump is a booster in series with the valve and is stopped by default. To use
it, set `hx.pump.speed`, attach a controller, or install a different pump:

```matlab
hx = DHS.IdealHeatExchanger('HX', 'Qnom',8e5);   building.attachHeatExchanger(hx);
c = DHS.controllers.PID(0.14, 1.6e-4, 0);
c.measure = @(sys) building.Tzone;  c.reference = @(sys) building.setpoint;   % the zone temperature is held at the setpoint
hx.valve.attachController(c);
hx.attachPump( DHS.Hydraulic.FixedDisplacementPump('HX.pump', 'mdotRated',4, 'dpMax',2.5e5) );
```

## Function reference

| Function or property | Inputs | Output or effect |
|---|---|---|
| `ENTUPlateHeatExchanger(name, 'UA',.., 'Qcap',.., ...)` | name; conductance (W/K, default 4e4) and the common parameters below | The counterflow plate exchanger of a building with a loop. |
| `FixedEffectivenessHeatExchanger(name, 'effectiveness',.., 'Qcap',.., ...)` | name; effectiveness (0 to 1, default 0.8) and the common parameters | A fixed-effectiveness exchanger for a building with a loop. |
| `IdealHeatExchanger(name, 'Qnom',.., 'dTnom',.., 'exponent',.., ...)` | name; heat (W, 5e5) at the nominal temperature difference (K, 50), the exponent (1.3), and the common parameters | The simple radiator of a building without a loop. `Qcap` is unlimited by default. |
| common parameters | `Qcap` (W, 5e5), `internalVolume` (L, 5), `cp`, `dpNomPrimary` (Pa, 3e4), `mdotNomPrimary` (kg/s, from `Qcap`) | Set as name-value pairs or by assignment. Every exchanger has a default valve and a default centrifugal pump (stopped, `speed` 0). |
| `.mdotSecNom` | kg/s (6) | Loop types only: the internal flow assumed when `transfer` is called without one. |
| `usesInternalLoop()` | none | True for the loop types, false for `IdealHeatExchanger`. |
| `effectivenessCmin(mdotPrimary, mdotSec)` | the two flows (kg/s) | Loop types: $\varepsilon\,\dot C_{\min}$ in W/K, which is what distinguishes them. |
| `transfer(mdotPrimary, TsupPrimary, TsecIn, mdotSec)` | primary flow (kg/s), primary supply and secondary inlet temperatures (degC), internal flow (kg/s, default `mdotSecNom`) | Loop types: `[Qdel, TretPrimary, TsecOut]`: delivered heat (W), primary return temperature (degC) and the internal water leaving the exchanger (degC). |
| `idealTransfer(mdotPrimary, TsupPrimary, Tzone)` | primary flow (kg/s), primary supply and zone air temperatures (degC) | `IdealHeatExchanger`: `[Qdel, TretPrimary]` from the radiator law above. |
| `primaryResistance(rho)` | density (kg/m³) | $K_\text{primary}$ in Pa/(kg/s)². |
| `attachPump(pump)` | any `DHS.Hydraulic.Pump` | Installs a pre-built primary booster pump, reachable under its own name. It runs at full speed until `speed` is changed. |
| `attachValve(valve)` | a `DHS.Hydraulic.Valve` | Installs a pre-built primary valve, reachable under its own name: `hx.attachValve(DHS.Hydraulic.Valve('V1','Kvs',12))` gives `hx.V1.Kvs`. |
| `.valve`, `.pump` | none | The valve and booster pump that belong to the exchanger. Attach a controller to either with `attachController(c)`. |
| `.districtInlet`, `.districtOutlet` | none | The host building's supply and return junctions. |
| `.internalOutlet`, `.internalInlet` | none | The supply and return junctions of the internal loop. The first use of either creates the loop. |
| `.Qdel`, `.TretPrimary` | none | Live delivered heat and primary return temperature. |
