# DHS.HeatExchanger: the building substation

`DHS.HeatExchanger` is the plate heat exchanger at a building's substation, together with
the control valve and the pump on its primary (district) side. It transfers heat from the
district water to the building's secondary circuit and sets the hydraulic resistance of the
building's branch. You create it with `building.addHeatExchanger(name, ...)`.

## Model

**Heat transfer.** The exchanger is a counterflow unit described by the
effectiveness–NTU method (Incropera and DeWitt [12](references.md#r12)). With $\dot C_p = \dot m_p c_p$ on the primary side, $\dot C_s =
\dot m_{s,\text{nom}}c_p$ on the secondary side, $\dot C_{\min} = \min(\dot C_p,\dot C_s)$,
$C_r = \dot C_{\min}/\dot C_{\max}$ and $\mathrm{NTU} = UA/\dot C_{\min}$, the effectiveness is

$$\varepsilon = \begin{cases}\dfrac{1-e^{-\mathrm{NTU}(1-C_r)}}{1-C_r\,e^{-\mathrm{NTU}(1-C_r)}}, & C_r<1,\\[8pt] \dfrac{\mathrm{NTU}}{1+\mathrm{NTU}}, & C_r=1.\end{cases}$$

The delivered heat and the primary return temperature follow, with the delivery limited
to the substation's capacity $\dot Q_\text{cap}$ and prevented from reversing:

$$\dot Q = \mathrm{clip}\big(\varepsilon\,\dot C_{\min}(T_{p,\text{in}}-T_{s,\text{in}}),\,0,\,\dot Q_\text{cap}\big),\qquad
T_{p,\text{out}} = T_{p,\text{in}} - \dot Q/\dot C_p .$$

MATLAB/Simscape's Heat Exchanger (TL-TL) and Plate Heat Exchanger (TL-TL) blocks
[56](references.md#r56), [57](references.md#r57) use the same effectiveness-NTU
relation; the plate version adds chevron-angle-dependent friction and Nusselt
correlations and plate thermal mass, not replicated here.

**Pressure loss.** The primary side loses pressure in the valve (see
[the hydraulics page](dhs-hydraulic.md)) and in the exchanger body. A manufacturer quotes
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
hx = DHS.HeatExchanger('HX', 'UA',3.5e4, 'Qcap',8e5, ...
        'dpNomPrimary',3.0e4, 'mdotNomPrimary',4.5);
hx.valve.Kvs = 18;  hx.valve.char = 'eqpct';  hx.valve.rangeability = 50;

[Q, Tret] = hx.transfer(4, 70, 45);     % 4 kg/s of 70 degC water, secondary return at 45 degC
% Q = 314.5 kW,  Tret = 51.2 degC

K = hx.primaryResistance(978);          % valve fully open: 4,182 + 1,481 = 5,663 Pa/(kg/s)^2
dp = K * 4.5^2;                         % 114.7 kPa at the design flow (84.7 kPa valve + 30 kPa body)
```

Inside a building the same object is created with `addHeatExchanger`, and its valve and
pump receive controllers. A different primary pump can be installed afterwards:

```matlab
hx = building.addHeatExchanger('HX', 'UA',3.5e4, 'Qcap',8e5, 'mdotSecNom',6, 'secApproach',28);
hx.valve.attachController( DHS.controllers.PID(0.14, 1.6e-4, 0) );
hx.attachPump( DHS.Hydraulic.FixedDisplacementPump('HX.pump', 'mdotRated',4, 'dpMax',2.5e5) );
```

## Function reference

| Function | Inputs | Output or effect |
|---|---|---|
| `HeatExchanger(name, 'UA',.., 'Qcap',.., 'mdotSecNom',.., 'secApproach',.., 'dpNomPrimary',.., 'mdotNomPrimary',..)` | name; conductance (W/K), delivery limit (W), secondary nominal flow (kg/s, default 6), emitter approach (K, default 28), body pressure drop (Pa, default 3.0e4), design flow (kg/s, default empty) | A substation with a default valve and a default centrifugal pump. The secondary return entering the exchanger is the zone air temperature plus `secApproach`. |
| `transfer(mdotPrimary, TsupPrimary, TsecIn)` | primary flow (kg/s), primary supply and secondary inlet temperatures (degC) | `[Qdel, TretPrimary]`: delivered heat (W) and primary return temperature (degC). |
| `primaryResistance(rho)` | density (kg/m³) | $K_\text{primary}$ in Pa/(kg/s)². |
| `attachPump(pump)` | any `DHS.Hydraulic.Pump` | Installs a pre-built primary pump. |
| `attachValve(valve)` | a `DHS.Hydraulic.Valve` | Installs a pre-built primary valve. |
| `.valve`, `.pump` | none | The owned valve and pump. Attach controllers with `hx.valve.attachController(c)` and `hx.pump.attachController(c)`. |
| `inlet()`, `outlet()` | none | The host building's supply and return ports, for port-wiring diagrams. The substation is one lumped branch fed from the building's inlet junction. |
| `.Qdel`, `.TretPrimary` | none | Live delivered heat and primary return temperature. |
| `.dpNomPrimary`, `.mdotNomPrimary` | Pa, kg/s | Body pressure drop and the flow at which it is quoted. |
