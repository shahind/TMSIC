# DHS.Hydraulic: pipes, junctions, pumps and valves

The hydraulic parts of a district network live in the package `DHS.Hydraulic`: `Pipe`,
`Junction`, `TJunction`, the two pump types `CentrifugalPump` and `FixedDisplacementPump`
(both derived from the abstract `Pump`), and `Valve`. The network that joins them,
`DHS.HydraulicNetwork`, and the co-simulation loop sit one level up in `+DHS`.

The network is two trees that you define separately. The supply tree starts at the plant's supply
port and its pipes flow away from the plant. The return tree starts at the plant's return port and its
pipes flow toward the plant. Junctions are the branch points of each tree, and each building joins one
supply junction and one return junction. The two sides need not look alike: the return branch may be
longer or shorter than the supply branch, with other diameters, roughness or heat loss. The plant has one
central pump, and each building's flow is set by its control valve, so the flow in one branch depends on
the flow in all the others. Opening one building's valve raises the total flow, lowers the central
pump's head and reduces the flow in every other branch (checked in
`validation/README.md`, section 2.7). A booster pump on a building's branch is optional and
stopped by default.

![The five-building campus network drawn by system.visualize()](images/dhs_schematic.png)

## Building a network

Two ways of describing the same network are available. The declarative style names the
two nodes a pipe joins. The port-wiring style builds a pipe, connects its input, and
connects its output, in the way `RCBS.Zone.addWall` and `connectToZone` build a zone. Both
call the same registration routine inside `DHS.HydraulicNetwork`, so the solver cannot
tell which one you used. Pick the one that reads better for the task.

The two examples below build a plant with two buildings on a trunk that has two
T-junctions. Both use this helper, which creates a building with a one-zone thermal model
and a substation. Save it as `addTestBuilding.m`.

```matlab
function b = addTestBuilding(sys, name)
    rc = RCBS.Building();  rc.addStorey('S');  rc.S.addZone('Z');
    rc.S.Z.setAir(2e7, 20);  rc.S.Z.addWindow(0.001, 'Window');
    b = sys.addBuilding(name);  b.useRCModel(rc);
    b.addHeatExchanger('HX', 'UA',8e3, 'Qcap',2e5);
    b.attachSolar(DHS.Solar());  b.attachSchedule(DHS.Schedule());
end
```

### Declarative style

```matlab
sys = DHS.System('weather','solar_data_2025.csv');
chp = sys.addCentralHeatPlant('CHP');
chp.addBoiler('B1', 'QMax',1e6);
chp.addPump('P0', 'dp0',3e5, 'mdotMax',12);
hn  = sys.addHydraulicNetwork();

t1 = hn.addJunction('T1', 'type','tee', 'mainDiameter',0.11, 'sideDiameter',0.05);
t2 = hn.addJunction('T2', 'type','tee', 'mainDiameter',0.11, 'sideDiameter',0.05);
hn.addPipe(chp.supplyPort, t1, 'name','pipe1', 'L',40, 'D',0.11);
hn.addPipe(t1, t2, 'name','pipe2', 'L',50, 'D',0.11);

r1 = hn.addJunction('R1', 'side','return');          % the return side, defined on its own
r2 = hn.addJunction('R2', 'side','return');
hn.addPipe(r1, chp.returnPort, 'name','ret1', 'L',45, 'D',0.13);   % flows from R1 to the plant
hn.addPipe(r2, r1, 'name','ret2', 'L',55, 'D',0.13);

hn.connectBuilding(t1, addTestBuilding(sys, 'North'), r1);   % supply junction, building, return junction
hn.connectBuilding(t2, addTestBuilding(sys, 'South'), r2);

sys.compile();
s = hn.solve(1);            % central pump at full speed
```

### Port-wiring style

```matlab
sys = DHS.System('weather','solar_data_2025.csv');
chp = sys.addCentralHeatPlant('CHP');
chp.addBoiler('B1', 'QMax',1e6);
chp.addPump('P0', 'dp0',3e5, 'mdotMax',12);
hn  = sys.addHydraulicNetwork();

pipe1 = DHS.Hydraulic.Pipe('pipe1', 'L',40, 'D',0.11);
chp.supplyPort.connectToPipe(pipe1);                 % plant output -> pipe1
t1 = DHS.Hydraulic.TJunction('T1', 'mainDiameter',0.11, 'sideDiameter',0.05);
pipe1.connectOutput(t1);                             % pipe1 -> tee T1

pipe2 = DHS.Hydraulic.Pipe('pipe2', 'L',50, 'D',0.11);
t1.portB.connectToPipe(pipe2);                       % the run of T1 -> pipe2
t2 = DHS.Hydraulic.TJunction('T2', 'mainDiameter',0.11, 'sideDiameter',0.05);
pipe2.connectOutput(t2.portA);                        % pipe2 -> the inlet of tee T2 (t2 itself works too)

r1 = DHS.Hydraulic.Junction('R1', 'return');         % the return side, wired the same way
r2 = DHS.Hydraulic.Junction('R2', 'return');
ret1 = DHS.Hydraulic.Pipe('ret1', 'L',45, 'D',0.13);
r1.connectToPipe(ret1);   ret1.connectOutput(chp.returnPort);      % R1 -> plant
ret2 = DHS.Hydraulic.Pipe('ret2', 'L',55, 'D',0.13);
r2.connectToPipe(ret2);   ret2.connectOutput(r1);                  % R2 -> R1

hn.connectBuilding(t1, addTestBuilding(sys, 'North'), r1);
hn.connectBuilding(t2, addTestBuilding(sys, 'South'), r2);

sys.compile();
s = hn.solve(1);
```

Both scripts give the same answer to the last bit:

```
s.mdot   = [3.9375  3.9235]   kg/s      (North, South)
s.Mtot   = 7.8609             kg/s
s.dpPump = 171,263            Pa
```

`pipe.addTjunction(name, sideDiameter)` is a shortcut for the two lines that create a
tee and connect a pipe to it. The tee's main diameter is the pipe's own diameter, and the
tee is returned:

```matlab
tee = pipe1.addTjunction('T1', 0.05);
```

A building's service connection starts from `building.connLength` and `building.connD` for both of
its pipes, `building.connPipeSup` and `building.connPipeRet`, which can be edited separately afterwards.
The connection is folded into the branch closure in `solve`, so the last hop to a building is always
`hn.connectBuilding(supplyJunction, building, returnJunction)`; the return junction may be the plant's
own `chp.returnPort`. When the supply junction is a `TJunction`, the building takes the tee's branch leg
regardless of how many other pipes already leave that tee.

### Parts by name

Every junction and pipe is reachable on the network by its name, in either style, so a part is
read or changed without searching the cell arrays. A tee's three ports are objects as well:

```matlab
hn.pipe1.L = 60;                       % supply pipe 1; the return pipes are separate (hn.ret1.L)
hn.T1.portC.D = 0.06;                  % side-branch diameter of tee T1 (portA and portB: main diameter)
hn.T1.portC.p                          % gauge pressure at the tee, live
hn.T1.portB.pipe.mdot                  % the pipe attached to the run (portC.pipe: the branch)
hn.pipe2.Input.p - hn.pipe2.Output.p   % pressure at the two ends of a pipe
hn.R2.p                                % gauge pressure at return junction R2
hn.T1.portB.connectToPipe(pipe3);      % wiring through a port object ...
hn.T1.connectToPipe('portB', pipe3);   % ... or with the port named as text: the same wire
```

Names are yours. The toolbox gives no part a fixed name: you name each junction, pipe, boiler, pump,
valve, heat exchanger and building when you create it, and that name is the handle. The plant is
`sys.CHP` with its boilers and pump by name (`sys.CHP.B1.QMax`, `sys.CHP.P0.dp0`), a building is
`sys.North` with its exchanger and the exchanger's valve and pump (`sys.North.HX.V1.Kvs`), and the bypass is
`hn.bypass` or the name you gave it.

**Supply and return are separate.** Nothing is copied from one side to the other. You create and name the
return junctions and pipes as you do the supply ones (`hn.addJunction('R1', 'side','return')`, then
`hn.addPipe(r1, chp.returnPort, ...)`), with their own lengths, diameters, roughness and heat-loss
coefficient. A return pipe runs from its first node toward its second, toward the plant.

**Parameters.** Every part takes its parameters as name-value pairs when it is created and as plain
assignment afterwards: `hn.addPipe(a, b, 'name','pipe1', 'L',40, 'D',0.11)` and `hn.pipe1.D = 0.15`, `hn.addJunction('T1',
'type','tee', 'sideDiameter',0.05, 'roughness',1e-4)`, `chp.addBoiler('B1', 'QMax',1.5e6)`,
`chp.addPump('P0', 'dp0',3e5)`, `DHS.Hydraulic.Valve('V1', 'Kvs',12)`, `sys.addBuilding('Hall', 'connD',0.05)`,
`sys.addHydraulicNetwork('rho',970)`, `sys.addCentralHeatPlant('CHP', 'TboilerMax',85)`. A name that is not a valid MATLAB identifier (the declarative default
`'CHP.supply->T1'` is one) is not registered: give the pipe a `'name'`. A name that a property
of the object already uses, such as `pipes`, is skipped with a warning.

### Swapping a part

A pump or a valve can be replaced after the network has been built. Here the North
substation gets a fixed-displacement booster pump that delivers 3 kg/s, capped at 250 kPa.
A pump you attach runs at full speed until you change `speed`:

```matlab
north = sys.buildings{1};
north.heatExchanger.attachPump( ...
    DHS.Hydraulic.FixedDisplacementPump('North.pump', 'mdotRated',3, 'dpMax',2.5e5) );
sys.compile();
s = hn.solve(1);            % s.mdot = [3.0000  4.1747]
```

North now receives exactly its commanded flow, and South, which shares the trunk, adjusts.

## Physical models

### Pipe

Pressure drop follows Darcy–Weisbach with the explicit Swamee–Jain friction factor [16](references.md#r16), an approximation of the
implicit Colebrook–White equation [17](references.md#r17):

$$\Delta p = K\,\dot m^2,\qquad K = \frac{f\,L}{D\cdot 2\rho A^2},\qquad
f = \frac{0.25}{\left[\log_{10}\!\left(\dfrac{\varepsilon/D}{3.7}+\dfrac{5.74}{\mathrm{Re}^{0.9}}\right)\right]^2}.$$

The factor is clamped to the range 0.008 to 0.1, and $f = 64/\mathrm{Re}$ below
$\mathrm{Re} = 2300$. A pipe also loses heat to the ground. For steady flow $\dot m$ with a
constant loss coefficient $U'$ (W/m/K), water entering at $T_\text{in}$ leaves at

$$T_\text{out} = T_g + (T_\text{in} - T_g)\,\exp\!\left(-\frac{U' L}{\dot m\,c_p}\right),\qquad
\dot Q_\text{loss} = \dot m\,c_p\,(T_\text{in} - T_\text{out}).$$

The network applies this to every pipe, supply and return, with the flow that pipe carries.
A junction splits the flow and passes the temperature on without loss; in the return tree
the streams meeting at a junction mix by enthalpy flow, $\sum \dot m\,c_p\,T$. So the plant
supply temperature, pressure and flow enter pipe A, leave it changed by its loss, and reach
the next junction, which divides the flow between its two outlets.

This matches MathWorks' Simscape Pipe (TL) block [50](references.md#r50): the same
$K\dot m^2$ Darcy-Weisbach term and the same $f=64/\mathrm{Re}$ laminar law (Simscape uses
the Haaland equation rather than Swamee-Jain in the turbulent range; the two agree to within
about 2% [18](references.md#r18)). Pipes here are assumed level (no $\rho g\,\Delta z$ term)
and the network is solved quasi-statically, without fluid inertia or wave dynamics.

### T-junction

A `TJunction` adds the minor loss of a real T-fitting, using the equivalent-length method
for a standard tee: an equivalent length of 20 pipe diameters when the flow goes straight
through (the run) and 60 diameters when the flow turns into the side leg (the branch),
independent of how the flow actually splits between them:

$$K_\text{run} = f(\mathrm{Re}_\text{main})\,\frac{20\,D_\text{main}}{D_\text{main}\,2\rho A_\text{main}^2},\qquad
K_\text{branch} = f(\mathrm{Re}_\text{side})\,\frac{60\,D_\text{side}}{D_\text{side}\,2\rho A_\text{side}^2},$$

where $f$ is the same Swamee–Jain/laminar friction factor used for pipes (the formula
above the T-junction section). This matches MATLAB/Simscape's own default T-Junction (TL)
model [51](references.md#r51), which cites Crane Technical Paper 410's 1981 edition
[52](references.md#r52). A newer edition [23](references.md#r23), Idelchik
[24](references.md#r24) and Rennels and Hudson [53](references.md#r53) instead give a
correlation in the flow-split ratio and the branch angle; see `validation/README.md` for
the comparison.

The Reynolds number each leg's $f$ is evaluated at depends on `frictionModel`:

$$\mathrm{Re}_\text{leg} =
\begin{cases}
10^7, & \texttt{frictionModel = 'fixed'} \text{ (default)},\\[6pt]
\dfrac{\rho\,v_\text{leg}\,D_\text{leg}}{\mu},\quad v_\text{leg}=\dfrac{\dot m_\text{leg}}{\rho A_\text{leg}}, & \texttt{frictionModel = 'actual'}.
\end{cases}$$

`'fixed'` pins $f$ at the fully turbulent asymptote for that leg's own diameter, matching
Simscape's own $f_T$, a tabulated per-size constant, independent of flow. `'actual'`
instead evaluates $f$ at the leg's own instantaneous flow $\dot m_\text{leg}$, the same
Reynolds number and laminar/turbulent rule `Pipe.resistance` uses, for users who want more
accuracy than the fixed-$f_T$ convention gives.

The coefficient is added to the Darcy–Weisbach term of the pipe that leaves the tee by
`portB` (run) or `portC` (branch). For a 0.10 m main and a 0.05 m side leg the two
coefficients are 2.73 and 153.5 Pa/(kg/s)$^2$. The loss is applied on the supply side
only; return junctions are plain junctions.

### Centrifugal pump

The head–flow curve is a parabola, and speed scaling follows the affinity laws
(Karassik et al. [25](references.md#r25); Gülich [26](references.md#r26)):

$$H(\dot m, s) = s^2\,\Delta p_0 - \Delta p_0\,\frac{\dot m^2}{\dot m_\text{max}^2}.$$

Closed onto a branch of resistance $K$ with differential pressure $\Delta p_\text{avail}$
already available at its tee, the flow is

$$\dot m = \sqrt{\frac{s^2\Delta p_0 + \Delta p_\text{avail}}{K + \Delta p_0/\dot m_\text{max}^2}}.$$

This is the special case of MATLAB/Simscape's Centrifugal Pump (TL) general affinity-law
model [54](references.md#r54) for a quadratic reference head curve.

### Fixed-displacement pump

A gear, screw or piston pump delivers a flow set by its speed almost regardless of the
pressure, until a relief valve opens (Karassik et al. [25](references.md#r25)):

$$\dot m = \min\!\left(s\,\dot m_\text{rated},\ \sqrt{\frac{\max(0,\ \Delta p_\text{max} + \Delta p_\text{avail})}{K}}\right).$$

As the central plant pump, this type reports its relief-valve pressure $\Delta p_\text{max}$
as the header head whenever it runs. A full positive-displacement solve, in which the pump
sets the flow of the whole network, is not implemented.

MATLAB/Simscape's Fixed-Displacement Pump (TL) [55](references.md#r55) models the same
pump type in more detail, with shaft torque/speed, volumetric leakage and friction torque;
this is a simpler commanded-flow-with-relief-valve model of the same physics.

### Control valve

The valve follows the IEC 60534 flow coefficient [22](references.md#r22), $Q\,[\mathrm{m^3/h}] = K_v\sqrt{\Delta p\,[\mathrm{bar}]}$,
which gives $\Delta p = K\,\dot m^2$ with $K = 10^5\cdot 3600^2/(K_v^2\rho^2)$. The
coefficient depends on the travel $\text{pos}$ through the inherent characteristic, linear
($K_v/K_{vs} = \text{pos}$) or equal-percentage ($K_v/K_{vs} = R^{\text{pos}-1}$, with
rangeability $R$, usually 25 to 50). Travel is floored at 0.02 to avoid a division by zero.

MATLAB/Simscape's Gate Valve (TL) block [58](references.md#r58) models a different valve
archetype -- a discharge coefficient and gate opening area -- rather than the $K_v$
flow-coefficient model used here.

## Function reference

### `DHS.Hydraulic.Pipe`

| Function | Inputs | Output or effect |
|---|---|---|
| `Pipe(name, 'L',L, 'D',D, 'eps',e, 'UperM',U)` | name; length (m), inner diameter (m), roughness (m, default 4.6e-5), heat-loss coefficient (W/m/K, default 0.30) | A pipe with no ends yet. `Pipe(name, nodeA, nodeB, ...)` also sets the ends. |
| `connectOutput(port)` | a junction or a tee port | Ends the pipe at `port` and registers it with the network its input belongs to. Returns the pipe. |
| `.Input`, `.Output` | none | The nodes the pipe starts and ends at (`.p`, `.T`). |
| `addTjunction(name, sideDiameter)` | name; side-leg diameter (m) | Creates a `TJunction` of this pipe's diameter at its downstream end and returns it. |
| `resistance(mdot, rho, mu)` | flow (kg/s), density (kg/m³), viscosity (Pa·s) | $K$ in Pa/(kg/s)², including any tee loss. |
| `outletTemperature(Tin, Tground, mdot, cp)` | inlet and ground temperatures (degC), flow (kg/s), specific heat (J/kg/K) | `[Tout, Qloss]`: outlet temperature (degC) and heat lost (W). Also sets `.Tin`, `.Tout`, `.Tdrop` and `.Qloss`. |
| `.mdot`, `.vel`, `.dp`, `.f` | none | Live flow, velocity, pressure drop and friction factor, filled by `solve`. |
| `.Tin`, `.Tout`, `.Tdrop`, `.Qloss` | none | Live inlet and outlet temperature, temperature drop and heat loss, filled by the temperature walks. |

### `DHS.Hydraulic.Junction` and `TJunction`

| Function | Inputs | Output or effect |
|---|---|---|
| `Junction(name, side)` | name; `'supply'` or `'return'` | A hydraulic node of the supply or the return tree. |
| `connectToPipe(pipe)` | a `Pipe` | Attaches the pipe downstream of the node. Returns the pipe. |
| `TJunction(name, 'mainDiameter',Dm, 'sideDiameter',Ds)` | name; diameters (m) | A tee with the ports `portA` (inlet), `portB` (run) and `portC` (side branch). |
| `portB.connectToPipe(pipe)`, `portC.connectToPipe(pipe)` | a `Pipe` | Wires the run or the side branch. Returns the pipe. |
| `connectToPipe('portB', pipe)`, `connectToPipe('portC', pipe)` | port name, a `Pipe` | The same wiring with the port named as text. `connectToPipe(pipe)` alone means `portB`, the run. |
| `portX.D` | none | Diameter at the port (m), read and write: the main diameter for `portA` and `portB`, the side diameter for `portC`. |
| `portX.p`, `portX.T`, `portX.pipe` | none | Gauge pressure (Pa) and temperature (degC) at the tee, and the pipe attached at that port (`[]` if none; for `portC` a building's service pipe counts). |
| `teeLossK(side, rho, mu, mdot)` | `'run'` or `'branch'`, density, viscosity, flow (kg/s, only used when `frictionModel='actual'`) | The coefficient $K_\text{run}$ or $K_\text{branch}$ in Pa/(kg/s)². |
| `.frictionModel` | `'fixed'` (default) or `'actual'` | Whether $f$ is evaluated at the fully turbulent asymptote or at the leg's own flow. |
| `.p`, `.T`, `.mdotThrough` | none | Live gauge pressure (Pa), water temperature (degC) and through flow (kg/s). |

### `DHS.Hydraulic.CentrifugalPump` and `FixedDisplacementPump`

| Function | Inputs | Output or effect |
|---|---|---|
| `CentrifugalPump(name, 'dp0',dp0, 'mdotMax',m, 'minSpeed',s)` | name; shut-off head (Pa), run-out flow (kg/s), speed floor | A centrifugal pump. |
| `FixedDisplacementPump(name, 'mdotRated',m, 'dpMax',dp, 'minSpeed',s)` | name; rated flow (kg/s), relief pressure (Pa), speed floor | A positive-displacement pump. |
| `curveHead(mdot, frac)` | total flow (kg/s), speed fraction | Head (Pa) at the plant header, the central-pump role. |
| `solveBranch(K, dpAvail, frac)` | branch resistance, available differential pressure (Pa), speed fraction | `[m, h]`: the flow and head the pump settles to on that branch, the substation-pump role. |
| `attachController(c)` | a `DHS.controllers.Controller` | Drives `.speed` from the controller at every step. |
| `.speed`, `.minSpeed` | 0 to 1 | Speed command and its floor. Speed 0 means stopped: as a substation pump it adds no head and no resistance, and the branch flow is $\sqrt{\Delta p/K}$. A building's pump is stopped by default. |
| `.head`, `.mdot` | none | Live head and flow, filled by `solve`. |

Example values for a pump with $\Delta p_0 = 300$ kPa and $\dot m_\text{max} = 14$ kg/s: the
head is 300 kPa at zero flow, 202 kPa at 8 kg/s and 94 kPa at 8 kg/s and speed 0.8. On a
branch with $K = 3000$ Pa/(kg/s)² it settles at 8.14 kg/s. A fixed-displacement pump
(5 kg/s, 300 kPa) on the same branch delivers 5.00 kg/s, and on a branch with
$K = 4\times10^5$ it is limited to 0.87 kg/s.

### `DHS.Hydraulic.Valve`

| Function | Inputs | Output or effect |
|---|---|---|
| `Valve(name, 'Kvs',Kvs, 'char',c, 'rangeability',R)` | name; rated $K_v$ (m³/h/√bar, default 25), `'eqpct'` or `'linear'`, rangeability (default 50) | A control valve. |
| `resistance(rho, pos)` | density (kg/m³), travel 0 to 1 (default `.pos`) | $K$ in Pa/(kg/s)². |
| `attachController(c)` | a `Controller` | Drives `.pos` from the controller at every step. The controller chooses what to measure. |
| `.pos` | 0 to 1 | Travel. Fixed unless a controller is attached. |

For $K_{vs} = 18$ and $R = 50$ the coefficient is 4,182 Pa/(kg/s)² fully open, which is
37.6 kPa at 3 kg/s. At half travel it is 209,099 Pa/(kg/s)².

### `DHS.HydraulicNetwork`

| Function | Inputs | Output or effect |
|---|---|---|
| `addJunction(name, 'type',t, ...)` | name; `'plain'` (default) or `'tee'`; any property of the junction, for a tee `'mainDiameter'`, `'sideDiameter'`, `'roughness'`, `'frictionModel'` | A supply junction, reachable as `hn.<name>`. |
| `addPipe(nodeA, nodeB, 'name',n, 'L',L, 'D',D, ...)` | two nodes (junctions or `chp.supplyPort`); any pipe property | Registers a supply pipe and its return pipe, reachable as `hn.<name>` when `name` is a valid identifier. Returns the pipe. |
| `connectBuilding(supplyJunction, building, returnJunction)` | a supply junction, a `DHS.Building`, a return junction (or `chp.returnPort`) | Feeds the building from the supply junction and drains it into the return junction. |
| `addBypass(supplyJunction, returnJunction, 'name',n, 'L',L, 'D',D, 'Kvs',Kvs, 'pos',p, ...)` | the supply junction it leaves and the return junction it joins; any pipe property (`name` default `'bypass'`, `L`, `D`, `eps`, `UperM`) and valve property (`Kvs`, `pos` default 1, `char`, `rangeability`, `KvMinFrac`) | Joins a supply junction to a return junction through a pipe and a valve. The pipe is `hn.<name>` and `hn.bypassPipe`, the valve `hn.bypassValve`. The position is fixed unless the valve gets a controller. `hasBypass()` tells whether one exists. |
| `compile()` | none | Freezes the topology into index arrays. `solve` calls it when needed. |
| `solve(pumpFrac)` | central pump speed, 0 to 1 (default 1) | A structure with `Mtot` (kg/s, buildings plus bypass), `mdotBypass` (kg/s), `dpPump` and `pSupHeader` (Pa), and per building `mdot`, `vel`, `pSupBranch`, `pRetBranch`. |
| `supplyTemperatures(Tplant, Tground, m, cp)` | plant supply temperature, ground temperature (degC), building flows `m` (kg/s), specific heat | `[TsupHx, Qloss]`: water temperature at each building's heat-exchanger inlet (degC) and the total supply-side heat loss (W). Walks the supply tree pipe by pipe. |
| `returnTemperatures(Thx, Tground, m, cp)` | heat-exchanger outlet temperatures (degC), ground temperature, flows, specific heat | `[Tret, Qloss]`: temperature arriving at the plant (degC) and the total return-side heat loss (W), with enthalpy mixing at each junction. |
| `.rho`, `.mu`, `.pReturnRef` | scalars | Density (978 kg/m³), viscosity (4.0e-4 Pa·s) and the return-side reference gauge pressure (1.5e5 Pa). |
| `.junctions`, `.returnJunctions`, `.pipes`, `.returnPipes`, `.buildings` | none | The registered parts, as cell arrays. |

The solver walks the tree from the plant, computes each segment's flow from the branch
flows below it, subtracts $K\,\dot m^2$ along every pipe, closes each building branch
through its own pump's `solveBranch` (a stopped pump adds nothing), and repeats with damping until the total flow
converges. `DHS.System` then calls `supplyTemperatures` and `returnTemperatures` with those flows each step. Its accuracy is checked against closed-form solutions in
[`../validation/README.md`](../validation/README.md).

**What sets a branch flow.** A branch's flow is not fixed by its diameter. It follows from the
pressure balance at its junction: the differential pressure left there by the central pump and
the trunk friction must equal the branch's total resistance
$K = K_\text{service pipes} + K_\text{valve}(\text{pos}) + K_\text{exchanger} + K_\text{minor}$
(plus the T-junction's own branch loss) minus the head of a booster pump if one runs. The
diameters enter only through the pipe and fitting resistances. The valve position changes
$K_\text{valve}$ directly, so closing a valve cuts that branch's flow and raises the pressure
left for the others.

**End-of-line bypass.** A network does not need one: with the valves nearly shut, a pump under
differential-pressure control slows down instead, and the campus examples have none. With the
buildings' valves partly closed, not all of the supply water is drawn, and `hn.addBypass(...)` adds a pipe and a valve from the last supply junction, through
its run port, to the return side. The bypass is one more branch without a pump, whose flow is
$\dot m_\text{bp} = \sqrt{\Delta p/K_\text{bp}}$ with $\Delta p$ the supply-minus-return pressure at
that junction and $K_\text{bp}$ the pipe plus valve resistance. It is counted in every trunk pipe's
flow upstream of it and in the plant's total flow, loses heat in its own pipe, and its water
joins the return at that junction, mixing by enthalpy flow with the building returns.

**Controlling the bypass valve.** The bypass valve holds the position given to `addBypass` unless
you attach a controller, like any other actuator. The controller is sampled once per step on the
previous step's pressures:

```matlab
c = DHS.controllers.PID('Kp',1/2e5, 'Ki',0, 'dir',-1);      % open when dp > reference
c.measure   = @(sys) hn.bypassJunction.p - hn.bypassReturnJunction.p;   % across the bypass, Pa
c.reference = 3.5e5;                                        % Pa
hn.bypassValve.attachController(c);
```

**Controlling the central pump.** The central pump runs at the speed `sys.pumpFrac` unless it has a
controller. Attach one like any other and let it say what it measures and what it holds:

```matlab
tee = hn.T2;  ret = hn.R2;                                  % the last supply and return junctions
c = DHS.controllers.PID('Kp',2.5e-7, 'Ki',2.1e-9, 'uMin',0.3);
c.measure   = @(sys) tee.p - ret.p;                         % supply minus return pressure, Pa
c.reference = 3.0e5;                                        % Pa, or a function @(sys) ...
pump0.attachController(c);
```

The measure can be anything the controller can read from `sys`: the pump head (`pump0.head`), another junction, a
flow, and the reference can change with time (`sys.time`). The campus examples hold 3 bar at the last tee, which their narrow service pipes and valves
need at peak load.
