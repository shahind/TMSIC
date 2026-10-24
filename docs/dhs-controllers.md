# DHS.controllers: swappable control laws

Every controllable actuator in a DHS system (a building's valve, a pump, a boiler's burner, the
bypass valve) is driven by an object derived from `DHS.controllers.Controller`. There is one way
to attach a controller to any of them, `actuator.attachController(c)`, so replacing one law with
another changes one line and leaves the rest of the model alone:

```matlab
heatExchanger.valve.attachController(c1);     % building valve
heatExchanger.pump.attachController(c2);      % building booster pump (stopped by default)
plant.supplyPump.attachController(c3);        % central pump
network.bypassValve.attachController(c4);     % end-of-line bypass valve
boiler.attachController(c5);                  % burner firing
```

Four laws are supplied: `PID`, `LQR`, `Relay` and `Callback`, which wraps a function handle. You
can add your own, for example a model predictive controller, by subclassing `Controller`.

## The interface

A controller receives the whole simulation, the `DHS.System`, and decides what to measure and
how. At every step the actuator calls

```matlab
u = c.update(sys, dt)
```

and applies `u` to the actuator. So a building's valve controller may read the zone
temperature, while the central pump's controller reads the pressure at two points of the
network, a boiler's controller the supply temperature, and a bypass-valve controller anything
or nothing.

| Function or property | Inputs | Output or effect |
|---|---|---|
| `reset()` | none | Clears internal state. Called before a run. |
| `u = update(sys, dt)` | the `DHS.System`; step in seconds (greater than zero) | The command `u`, clamped to `[uMin, uMax]` (default 0 to 1). Zero means shut, stopped or no firing, one means fully open, full speed or full firing. |
| `.uMin`, `.uMax`, `.name` | numbers, text | Output limits and a label. |

The parent class holds only these. Each law carries its own parameters as properties: a `PID` its
gains, `measure` and `reference`, a `Relay` its band, `measure` and `reference`, an `LQR` its model,
`Q`, `R` and the state it regulates. The simulation exposes its parts through handles, for example `sys.time` (start of the step),
`sys.wx` (weather), `sys.plant`, `sys.network` and `sys.buildings{i}`, and a measure can also
capture any handle you hold, such as a junction `tee`:

```matlab
c = DHS.controllers.PID('Kp',2.5e-7, 'Ki',2.1e-9, 'uMin',0.3);
c.measure   = @(sys) tee.p - ret.p;            % supply minus return pressure, two junctions, Pa
c.reference = 3.0e5;                           % Pa
plant.supplyPump.attachController(c);

c = DHS.controllers.PID(0.14, 1.6e-4, 0, 40);
c.measure   = @(sys) building.Tzone;           % a building's valve follows its zone temperature
c.reference = @(sys) building.setpoint;
building.heatExchanger.valve.attachController(c);
```

A custom law needs `reset` and `update`, and its own parameters. A proportional controller takes
a few lines:

```matlab
classdef Proportional < DHS.controllers.Controller
    properties, Kp = 0.5; measure; reference; end
    methods
        function reset(obj), end
        function u = update(obj, sys, dt)
            u = obj.clamp(obj.Kp * (obj.reference(sys) - obj.measure(sys)));
        end
    end
end
```

## PID

The PID is in parallel form with a filtered derivative and back-calculation anti-windup
(Åström and Hägglund, *Advanced PID Control*, 2006):

$$u = K_p\,e + K_i\!\int e\,\mathrm{d}t + K_d\,\dot e_f,\qquad e = \mathrm{dir}\,(r - y).$$

When the output saturates, the integrator is corrected by $(\Delta t/T_t)(u - u_\text{raw})$,
which lets it leave saturation as soon as the error changes sign.

| Function | Inputs | Output or effect |
|---|---|---|
| `PID(Kp, Ki, Kd)` or `PID(Kp, Ki, Kd, Tf)` | gains; derivative filter time constant $T_f$ in seconds (default 20) | A PID controller. |
| `.measure`, `.reference` | `@(sys) ...` returning the measured value; a number or `@(sys) ...` | What the PID holds at the setpoint. |
| `PID('Kp',.., 'Ki',.., 'Kd',.., 'Tf',.., 'Tt',.., 'dir',.., 'uMin',.., 'uMax',..)` | name-value pairs | The same, with the anti-windup time $T_t$ (default chosen automatically) and the action `dir` (+1 direct, −1 reverse). |

Consider a room with 300 W/K of loss, a 10 MJ/K heat capacity and an 8 kW heater. It starts
at 15 degC, the outdoor temperature is 5 degC and the setpoint is 21 degC:

```matlab
c  = DHS.controllers.PID(0.5, 5e-4, 0);
c.measure = @(s) s.T;  c.reference = 21;       % here the "simulation" is a struct holding T
dt = 60;  T = 15;  Tout = 5;
UA = 300;  Qmax = 8000;  C = 1e7;
for k = 1:720                                   % twelve hours of one-minute steps
    u = c.update(struct('T',T), dt);            % heating command between 0 and 1
    T = T + dt*(-UA*(T - Tout) + Qmax*u)/C;
end
```

After one hour the room is at 16.7 degC, after three at 19.6 degC, after six at 20.9 degC
and after twelve at 21.00 degC, when the command has settled at 0.60 (4.8 kW balances the
4.8 kW loss).

## LQR

`LQR` is the standard discrete regulator. Given the continuous model $\dot x = A x + B u$ of one
input, the weights $Q$ and $R$ and the sample time $T_s$, it discretises the model by zero-order
hold, solves `dlqr` for the gain $K$ ([40](references.md#r40), [41](references.md#r41),
[42](references.md#r42)) and applies

$$u = \mathrm{clamp}\!\left(-K x\,/\,u_\text{scale},\ u_\text{min},\ u_\text{max}\right).$$

It regulates the state to zero and has no reference of its own. To hold a setpoint, return the error
$x = x_\text{real} - x_\text{ref}$ from `state`. Offset-free tracking against constant disturbances needs an
integral state, which you add to $A$, $B$ and $Q$ and return in `x` as well. `LQR` needs the Control
System Toolbox.

| Function | Inputs | Output or effect |
|---|---|---|
| `LQR(A, B, Q, R, Ts)` | continuous model `A` ($n\times n$) and `B` ($n\times 1$); state weight `Q` ($n\times n$, or a vector for its diagonal); input weight `R`; sample time `Ts` in seconds (default 60) | An LQR controller. |
| `.A`, `.B`, `.Q`, `.R`, `.Ts` | as above | Design data. The gain is redesigned when any of them changes. |
| `.K` | none (read-only) | The gain row from `dlqr`. |
| `.state` | `@(sys)` returning the state vector $x$ | The state the regulator drives to zero. |
| `.uScale` | number (default 1) | The input value that corresponds to $u = 1$, for example the heat in watts at full valve opening. |

```matlab
[sysc, io] = building.rcBuilding.simulation.getStateSpace();
r = io.zoneMainRows(1);                           % the zone air node
Q = ones(size(sysc.A,1), 1);  Q(r) = 6e3;         % weight on each node temperature
c = DHS.controllers.LQR(sysc.A, sysc.B(:, r+1), Q, 1e-9, 60);   % B column: heat into the air node
c.uScale = hx.Qcap;
c.state  = @(sys) building.rcBuilding.simulation.Tnow - building.setpoint;   % x = x_real - x_ref
hx.valve.attachController(c);
```

## Relay

The relay is an on/off controller with symmetric hysteresis. With $e = \mathrm{dir}\,(r - y)$
and half-width $h$, it switches on when $e > h$, off when $e < -h$, and holds its last
command in between (Åström and Hägglund, Sec. 7.4).

| Function | Inputs | Output or effect |
|---|---|---|
| `Relay(h)` or `Relay('h',.., 'dir',.., 'uMin',.., 'uMax',..)` | half-width of the dead band, in the units of the loop | A relay controller. |
| `.measure`, `.reference` | `@(sys) ...` returning the measured value; a number or `@(sys) ...` | What the relay switches on. |

With `Relay(0.5)`, `measure` reading the room temperature and a setpoint of 21 degC, successive measurements of 19.0, 20.4, 21.0,
21.6, 21.0, 20.4 and 20.0 give the commands 1, 1, 1, 0, 0, 1 and 1. Because the second reading of
21.0 lies inside the dead band, the command stays at 0.

## Callback

`Callback` turns a function handle into a controller, so a custom law can be attached to a
valve, a pump or a burner without writing a class. The handle receives the simulation and the
step in seconds and returns the command, which is clamped to `[uMin, uMax]`.

| Function | Inputs | Output or effect |
|---|---|---|
| `Callback(fcn)` or `Callback(fcn, 'resetFcn',@() ..., 'uMin',.., 'uMax',..)` | `fcn(sys, dt)` returning `u`; optional function called before each run to clear any state the handle keeps | A controller that calls `fcn` at every step. |

```matlab
hx.valve.attachController( DHS.controllers.Callback(@(sys, dt) 0.4*(21 - building.Tzone)) );
network.bypassValve.attachController( DHS.controllers.Callback(@(sys, dt) 0.5) );   % a constant position
```

## Comparing laws on one building

We ran the one-hall system of [the system page](dhs-system.md) for seven days with each law
on the substation valve. The figures cover occupied hours, when the setpoint is 21 degC.

| Law | Mean bias (K) | Root-mean-square error (K) |
|---|---|---|
| `LQR`, `Q` 6e3 on the air node, `R` 1e-9 | −0.030 | 0.032 |
| `PID(0.14, 1.6e-4, 0)` | +0.022 | 0.076 |
| `Relay(0.3)` | +0.010 | 0.226 |
| `Proportional`, `Kp` 0.5 | −0.626 | 0.631 |

A proportional law leaves a steady offset, as expected without integral action, and so does the
plain LQR regulator, whose offset is small only because its gain is high. The relay shows no
offset, and its output cycles inside the dead band. The PID and LQR settings are those
used in the toolbox examples. The relay band and the proportional gain are illustrative, and
none of the settings has been tuned for this building.
