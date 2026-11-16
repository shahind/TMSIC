# DHS.Radiator and the building's internal loop

A building can have a water loop of its own between its heat exchanger and its zones. The district side of the
exchanger heats the loop water, a pump circulates it through a valve and a radiator at every zone, and each
radiator gives its heat to the zone air. The zones stay RC models: the radiator computes the heat, the building
injects it at the zone's air node, and the RC library is unchanged.

You build the loop from the same pipes, valves, pumps and tees as the district network, with the same two calls,
`connect` and `add...`. There is no loop object. The loop starts at the heat exchanger's internal outlet,
`hx.internalOutlet`, ends at its internal inlet, `hx.internalInlet`, and exists as soon as you connect something
to either one.

A building without a loop has an ideal substation: a `DHS.IdealHeatExchanger` stands for the exchanger and the
emitters behind it as one radiator through which the district water flows (see
[heat exchangers](dhs-heat-exchanger.md)), and its heat goes straight to the zones. A building with a loop uses
an `ENTUPlateHeatExchanger` or a `FixedEffectivenessHeatExchanger` and needs both internal ports connected. A run
stops with an error if a loop exchanger has unconnected ports, or if an ideal exchanger is used with a loop. Use
a loop when the heat that reaches each zone should depend on water temperature and flow.

```
hx.internalOutlet --> pipe --> pump --> pipe --> tee --portC--> valve --> pipe --> radiator --> pipe --+
                                                  |                                                   |
                                                  +--portB--> pipe --> bypass valve ----------> return junction --> pipe --> hx.internalInlet
```

## Connecting components

`a.connect(b)` makes `b` the next component downstream of `a`. Each of `a` and `b` can be a junction, a tee port,
a pipe, a valve, a pump, a radiator or a building. Between two components that are not nodes, a node is made for
you.

```matlab
tee.portC.connect(pipe1);        % tee side port -> pipe
pipe1.connect(valve1);           % pipe -> valve
valve1.connect(pipe2);
pipe2.connect(rad1);             % pipe -> radiator
rad1.connect(returnPipe1);       % radiator -> return pipe
returnPipe1.connect(returnJunction);
rad1.connect(zone1, R);          % radiator -> RCBS zone: heat to the zone through R [K/W]
```

`add...` creates a component, connects it and returns it, so calls chain:

```matlab
pipe1  = tee.portC.addPipe(0.05, 12);          % diameter D, length L; any property as 'name',value
valve1 = pipe1.addValve('Kvs',4, 'minPos',1e-3);
pipe2  = valve1.addPipe(0.05, 3);
rad1   = pipe2.addRadiator('rad1', 'Qdes',8e3);
tee2   = pipe2.addTee(0.032);                  % side diameter; the main diameter is pipe2.D
pump   = pipe2.addPump('dp0',3e4, 'mdotRated',1);
```

`connect` and `add...` are methods of the component you start from, so the start of a chain is always clear:
`tee.portC...` leaves the side port of a tee, and `hx.internalOutlet...` leaves the exchanger. A chain starts at a
node (a junction, a tee port or an exchanger port), and chains built apart can be joined later in any order.
`attach` is used only for controllers (`valve.attachController(c)`). A network needs at least one pump; without
one, solving it stops with an error.

| Component | Created with | Notes |
|---|---|---|
| Pipe | `DHS.Hydraulic.Pipe(name, 'L',..,'D',..)` or `x.addPipe(D, L)` | Heat loss to the room (`UperM`), friction, tee loss. |
| Valve | `DHS.Hydraulic.Valve(name, 'Kvs',..)` or `x.addValve(...)` | The same valve everywhere. `minPos` is its lowest opening (0.001 shuts tight; default 0.02). |
| Pump | `DHS.Hydraulic.CentrifugalPump(name, 'dp0',..,'mdotRated',..)` or `x.addPump(...)` | Adds its head where it sits. |
| Tee | `DHS.Hydraulic.TJunction(name, 'mainDiameter',..,'sideDiameter',..)` or `x.addTee(...)` | `portB` is the run, `portC` the side branch. |
| Junction | `DHS.Hydraulic.Junction(name, 'supply' or 'return')` | A node where branches meet. |
| Radiator | `DHS.Radiator(name, 'Qdes',..)` or `x.addRadiator(name, ...)` | Heats a zone. |

A pipe or valve joined from the supply side to a return junction carries water straight across: it is a bypass.
Connect it from the run of a tee (`tee.portB`) or from any supply node. Its flow is `valve.mdot`, and it takes
what the radiators do not. A radiator or valve whose name is a valid identifier is reachable on the building
once it is connected, for example `building.rad1`.

## The radiator

A radiator is a lump of metal that takes heat from the water and gives it to the zone air: a water, metal, air
chain with the resistances $1/a(\dot m)$ and $1/UA_{ma}$ around a capacity $C$. The water cools as it crosses
the radiator, against the metal temperature $T_m$:

$$T_\text{out} = T_m + (T_\text{in} - T_m)\,e^{-UA_{wm}/(\dot m c_p)} .$$

The heat from the water is $Q_w = a\,(T_\text{in} - T_m)$, with a water-side conductance that depends on the flow,

$$a(\dot m) = \dot m c_p\left(1 - e^{-UA_{wm}/(\dot m c_p)}\right),$$

which grows with the flow and saturates at $\dot m c_p$. So the first resistance is not a constant: the valve sets
$\dot m$, and with it $a$. The metal and the air side are linear:

$$C\,\frac{dT_m}{dt} = Q_w - Q_\text{air}, \qquad Q_\text{air} = UA_{ma}\,(T_m - T_\text{zone}).$$

Each step the radiator solves this implicitly for $T_m$, which is linear for a given flow, so no iteration is
needed. It gives $Q_\text{air}$ for the zone and the water outlet temperature. With the valve shut the
water-side conductance is zero and the metal cools to the zone temperature. Other emitters, such as a fan coil,
can be added in the same way: compute $Q$ from the water and the zone, and leave the zone an RC model.

### Sizing

Give the design heat output and the radiator is sized from it:

```matlab
rad = DHS.Radiator('Lobby', 'Qdes',8e3, 'Tsup',60, 'Tret',40);
rad.connect(rc.S1.Lobby);          % the zone it heats
```

| Property | Meaning | Default |
|---|---|---|
| `Qdes` | design heat output (W) | none |
| `Tsup`, `Tret`, `Tair` | design supply, return and air temperatures (degC) | 70, 50, 20 |
| `epsDes` | design water-to-metal effectiveness | 0.9 |
| `mdotDes` | design flow (kg/s) | $Q_\text{des}/(c_p(T_\text{sup}-T_\text{ret}))$ |
| `UAwm` | water-to-metal conductance (W/K) | $-\dot m_\text{des} c_p \ln(1-\varepsilon_\text{des})$ |
| `UAma` | metal-to-air conductance (W/K) | $Q_\text{des}/(T_m - T_\text{air})$ at design; $1/R$ when connected to a zone with `R` |
| `C` | metal and water capacity (J/K) | 20 kJ/K per kW of `Qdes` |
| `dpBody` | pressure drop of the radiator at the design flow (Pa) | 5000 |
| `pipeD` | pipe diameter for 0.8 m/s at the design flow (m), read only | from `mdotDes` |

The radiator has no valve or service pipe of its own. The valve, the pipes before and after it, and any bypass
are components you connect. `rad.pipeD` is a size to start from for the branch pipes, and the valve size is your
choice, for example `DHS.Hydraulic.Valve.kvsFor(rad.mdotDes, 5e3)` for 5 kPa fully open at the design flow. You
can give any of `UAwm`, `UAma`, `C` and `mdotDes` directly instead of deriving it. At the design flow, supply
temperature and air temperature, the steady radiator gives exactly `Qdes` and the design return temperature
(see [validation 2.8](../validation/README.md#28-radiator)).

## The heat exchanger with a loop

With a loop, the exchanger's internal side carries the loop's actual flow, $C_s = \dot m_\text{int} c_p$, and the
water that returns from the zones. The effectiveness-NTU relation is the one on the
[heat exchanger page](dhs-heat-exchanger.md), which also gives the temperature of the internal water leaving the
exchanger, $T_\text{secOut} = T_\text{secIn} + Q/C_s$. The loop water is a lumped capacity $C_\ell$ at the supply
side:

$$C_\ell\,\frac{dT_\text{int,sup}}{dt} = \dot m_\text{int} c_p\,(T_\text{secOut} - T_\text{int,sup}),$$

so the supply temperature `building.TintSup` follows the exchanger outlet with the lag of the water in the loop.
$C_\ell$ is the heat capacity of the loop water: the volume of all loop pipes ($\pi D^2 L/4$ each) plus the water
in the exchanger's internal side, `hx.internalVolume` (litres, default 5), times $\rho c_p$. Set
`building.loopCapacity` (J/K) to use another value; the value in use is `building.loopCap`. The heat the exchanger
delivers and the heat the radiators give differ only by what the loop water and the radiators store.

## Control

Every actuator takes a controller with the same call, `actuator.attachController(c)`:

| Actuator | Usual measurement | Notes |
|---|---|---|
| zone valve | the zone temperature, `rad.Tzone`, against `rad.setpoint` | one PID per zone |
| loop pump | the internal flow, `building.mdotInt`, against a constant | speed 1 unless a controller is attached |
| district valve `building.heatExchanger.valve` | the internal supply temperature, `building.TintSup`, against a fixed value | replaces the zone-temperature loop of an ideal substation |

```matlab
zc = DHS.controllers.PID(0.6, 2e-3, 0);
zc.measure = @(sys) rad.Tzone;  zc.reference = @(sys) rad.setpoint;
valve.attachController(zc);

fc = DHS.controllers.PID('Kp',0.03/rad.mdotDes, 'Ki',0.002/rad.mdotDes, 'uMin',0.3);
fc.measure = @(sys) building.mdotInt;  fc.reference = 1.5*rad.mdotDes;
pump.attachController(fc);

pc = DHS.controllers.PID(0.02, 4e-5, 0);
pc.measure   = @(sys) building.TintSup;
pc.reference = 60;                                    % internal supply temperature [degC]
building.heatExchanger.valve.attachController(pc);
```

The flow controller acts on an algebraic plant (the flow follows the pump speed within the step), so its gains
must be small: a gain of 0.5 per unit of design flow oscillates between the ends of the speed range, and 0.03
holds the flow.

**Holding the flow constant.** The pump can hold the loop flow constant only if the water has somewhere to go when
the zone valves close. That is the bypass: a valve between the supply and the return that takes what the
radiators do not. The total flow the pump holds is the radiator's design flow plus the bypass flow at the design
head. Size the bypass for its share at that head (`kvsFor(bypassFlow, head)`), and the pump for the head that
pushes the whole flow through the bypass alone, which is higher. A bypass that is too small leaves the pump at
full speed with the flow below its reference.

## Example: the one-hall system with a loop

The office hall of [the system page](dhs-system.md), with an internal loop and a radiator.

```matlab
rc = RCBS.Building();                                    % thermal model of the hall
rc.addStorey('S1');
rc.S1.addZone('Hall');
rc.S1.Hall.setAir(2e7, 20);
rc.S1.Hall.addWall(0.0004, 3e8, [], 'Wall');
rc.S1.Hall.addWindow(0.00067, 'Window');
rc.S1.Hall.addInternalMass(0.0002, 5e8, [], 'Mass');

sys = DHS.System('weather','solar_data_2025.csv', 'startDate',datetime(2025,1,1));
chp = sys.addCentralHeatPlant('CHP');
chp.addBoiler('B1', 'QMax',1.0e6);
chp.addPump('P0', 'dp0',3.0e5, 'mdotRated',6);
chp.setSupplySetpoint(70);

hn = sys.addHydraulicNetwork();                          % district side: a pipe, a tee and a return pipe
tee1 = chp.supplyPort.addPipe(0.10, 40).addTee(0.05);
ret1 = DHS.Hydraulic.Junction('R1', 'return');
ret1.addPipe(0.10, 40).connect(chp.returnPort);

b  = sys.addBuilding('Hall');
b.useRCModel(rc);
hx = b.addHeatExchanger('HX', 'UA',8e3, 'Qcap',2e5);     % a plate exchanger: this building has a loop
tee1.portC.connect(b);                                   % the building hangs on the tee's side port
b.connect(ret1);                                         % and drains into the return junction

% internal loop: hx.internalOutlet -> pipe -> pump -> pipe -> tee -> valve -> pipe -> radiator -> pipe -> hx.internalInlet
Qpk  = 144e3;                                            % design heat load of the hall [W]
D    = 0.08;                                             % loop main diameter [m]
L    = [12 84 12 108 12];                                % feed, pump to tee, branch to the radiator, return main, bypass [m]
rad  = DHS.Radiator('rad1', 'Qdes',Qpk, 'Tsup',60, 'Tret',40);
rad.connect(rc.S1.Hall);                                 % the radiator heats the hall

Mref  = 1.5*rad.mdotDes;                                 % pump flow: the radiator's design flow plus the bypass
Kmain = DHS.Hydraulic.Pipe('mains', 'L',L(1)+L(2)+L(4), 'D',D).resistance(Mref, 983, 4.7e-4);
Kbyp  = 1.2e4/(0.5*rad.mdotDes)^2;
pump  = hx.internalOutlet.addPipe(D, L(1), 'UperM',0.15).addPump( ...
            'dp0',1.6*(Kmain + Kbyp)*Mref^2, 'mdotRated',Mref);
tee   = pump.addPipe(D, L(2), 'UperM',0.15).addTee(rad.pipeD);        % side port: the branch to the radiator
valve = tee.portC.addValve('Kvs',DHS.Hydraulic.Valve.kvsFor(rad.mdotDes, 5e3), 'char','linear', 'minPos',1e-3);
valve.addPipe(rad.pipeD, L(3), 'UperM',0.15).connect(rad);

retJ  = DHS.Hydraulic.Junction('loopReturn', 'return');
rad.addPipe(rad.pipeD, L(3), 'UperM',0.15).connect(retJ);
retJ.addPipe(D, L(4), 'UperM',0.15).connect(hx.internalInlet);

bypass = tee.portB.addPipe(D, L(5), 'UperM',0.15).addValve('Kvs',DHS.Hydraulic.Valve.kvsFor(0.5*rad.mdotDes, 1.2e4), 'char','linear');
bypass.connect(retJ);                                    % the run of the tee ends in a bypass to the return

zc = DHS.controllers.PID(0.6, 2e-3, 0);                  % the zone valve holds the zone temperature
zc.measure = @(sys) rad.Tzone;  zc.reference = @(sys) rad.setpoint;
valve.attachController(zc);

fc = DHS.controllers.PID('Kp',0.03/rad.mdotDes, 'Ki',0.002/rad.mdotDes, 'uMin',0.3);
fc.measure = @(sys) b.mdotInt;  fc.reference = Mref;     % the pump holds the internal flow
pump.attachController(fc);

pc = DHS.controllers.PID(0.02, 4e-5, 0);                 % the district valve holds the internal supply
pc.measure   = @(sys) b.TintSup;                         % temperature at 60 degC
pc.reference = 60;
hx.valve.attachController(pc);

b.attachSolar( DHS.Solar('winArea',struct('N',20,'E',20,'S',20,'W',20), 'SHGC',0.4, 'massFraction',0.1) );
b.attachSchedule( DHS.Schedule('occStartHour',7, 'occEndHour',18, 'rampHours',1, ...
    'Tocc',21, 'Tsetback',18, 'gainOccW',20e3, 'gainMassFraction',0.3) );

res = sys.run(days(7));
```

The run takes about 13 s. During occupied hours the zone temperature has a mean bias of +0.002 K and a
root-mean-square deviation of 0.07 K around the 21 degC setpoint. The internal supply temperature is 58.7 to
61.3 degC (5th to 95th percentile) and within 3 K of the 60 degC setpoint 98 % of the time. It starts from 40 degC
and peaks at 68 degC in the first warm-up. The pump holds the loop flow within 10 % of its 2.58 kg/s reference
87 % of the time. The loop pipes (240 m) and the exchanger's internal side hold 1,140 litres of water, 4.7e6 J/K.
The exchanger delivers 10,138 kWh over the week and the radiator gives 9,885 kWh to the hall. Most of the 253 kWh
difference is the heat the loop pipes lose into the hall (about 1.4 kW), and the rest is what the radiator and
the loop water have stored at the end. The energy balance of the plant closes to 1e-10.

The valves have a 60 s actuator lag (`valve.lag`, see [hydraulics](dhs-hydraulic.md)), so the zone valve moves
toward the commanded position over about a minute. Set `valve.lag = 0` for an ideal valve.

### Sizing the loop

The toolbox does not size pipes: the water in the loop, and with it how slowly the supply temperature follows the
exchanger, comes from the lengths and diameters you give. As a guide, a radiator system with an air handling unit
has about 0.2 m of pipe per m² of floor. With 100 mm pipes, a 3 to 4 storey building of 10,000 to 20,000 m² has
2,000 to 4,000 m of pipe and 15,000 to 30,000 litres of water. The hall above (1,200 m²) has 240 m. The
[campus examples](../+DHS/+examples/campus.m) give each building a fixed set of pipe lengths of this size (680
to 3,840 m, 5 to 30 m³ of water), with the pump sized from the pipe resistance. With so much water, the supply
temperature takes hours to respond, so the supply-temperature controller has to be slow.

With a loop, the result structure has `res.bldg(i).Tint_sup`, `.Tint_ret` and `.mdot_int` (loop supply and return
temperature in degC, and loop flow in kg/s), and `res.bldg(i).Qzones`, the heat each zone receives in W, with one
column per zone.

## Function reference

### `DHS.Building` (loop-related)

| Function or property | Inputs | Output or effect |
|---|---|---|
| `connect(dst)` | a return junction, or the first component of a return line | The building drains there. It is fed from a tee port: `tee.portC.connect(building)`. |
| `.heatExchanger.internalOutlet`, `.internalInlet` | none | The junctions where the loop starts and ends; the first use of either creates the loop. |
| `solveInternalLoop()` | none | Solves the loop's flows for the current valve positions and pump speeds. `DHS.System` calls it each step. |
| `.radiators` | none | The radiators of the loop, found when the run starts (empty for an ideal substation). |
| `.loopCapacity`, `.loopCap` | J/K | Heat capacity of the loop water: the value you give (`NaN` computes it from the pipe volumes), and the value in use. |
| `.TintSup`, `.TintRet`, `.mdotInt` | none | Live loop supply and return temperature (degC) and total flow (kg/s). |

### `DHS.Radiator`

| Function or property | Inputs | Output or effect |
|---|---|---|
| `Radiator(name, ...)` | name; properties of the table above as name-value pairs | A radiator. Normally connected with `pipe.connect(rad)` or created with `pipe.addRadiator(name, ...)`. |
| `connect(dst, R)` | a return pipe or junction; or an RCBS zone and the resistance `R` (K/W) to its air | The water leaves to `dst`, or the radiator heats the zone. |
| `response(mdot, Tin, Tzone, dt)` | flow (kg/s), water inlet and zone temperatures (degC), step (s) | `[Qair, Tout, TmNew, Qwater]`: heat to the zone, water outlet temperature, new metal temperature and heat from the water. It does not change the state. |
| `.Tmetal` | none | Metal temperature (degC). |
| `.mdot`, `.Tin`, `.Tout`, `.Qwater`, `.Qair`, `.dp` | none | Flow, water temperatures, heat flows and pressure drop of the last step. |
| `.Tzone`, `.setpoint` | none | The zone's air temperature and setpoint, set by the building each step, for controllers. |
| `.integrator` | `'backwardEuler'`, `'forwardEuler'`, `'exact'` | How the metal temperature is advanced. `DHS.System` sets it. |
