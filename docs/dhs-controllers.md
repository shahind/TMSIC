# DHS.controllers: swappable control laws

Every controllable actuator in a DHS system (a valve, a pump, the plant's burner) is driven
by an object derived from `DHS.controllers.Controller`. An actuator accepts whichever
law it receives, so replacing one law with another changes one line and leaves the rest of
the model alone:

```matlab
heatExchanger.valve.attachController(c1);     % building valve
heatExchanger.pump.attachController(c2);      % building pump
plant.supplyPump.attachController(c3);        % central pump
plant.attachFiringController(c4);             % burner firing
```

Three laws are supplied: `PID`, `LQR` and `Relay`. You can add your own, for example a
model predictive controller, by subclassing `Controller`.

## The interface

A controller is a single-input, single-output feedback law with two methods.

| Function | Inputs | Output or effect |
|---|---|---|
| `reset()` | none | Clears internal state. Called before a run. |
| `u = update(meas, ref, dt)` | measured value, setpoint (same units), step in seconds (greater than zero) | The command `u`, clamped to `[uMin, uMax]` (default 0 to 1). Zero means shut or no firing, one means fully open or full firing. |
| `u = update(meas, ref, dt, aux)` | as above, plus a structure `aux` | Model-based laws read `aux.x` (the full state vector), `aux.wx` (weather) and `aux.Tout`. `PID` and `Relay` ignore `aux`. |
| `.uMin`, `.uMax`, `.name` | numbers, text | Output limits and a label shown in `system.visualize()`. |

A custom law needs only these two methods. A proportional controller takes four lines:

```matlab
classdef Proportional < DHS.controllers.Controller
    properties, Kp = 0.5; end
    methods
        function reset(obj), end
        function u = update(obj, meas, ref, dt, varargin)
            u = obj.clamp(obj.Kp * (ref - meas));
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
| `PID('Kp',.., 'Ki',.., 'Kd',.., 'Tf',.., 'Tt',.., 'dir',.., 'uMin',.., 'uMax',..)` | name-value pairs | The same, with the anti-windup time $T_t$ (default chosen automatically) and the action `dir` (+1 direct, −1 reverse). |

Consider a room with 300 W/K of loss, a 10 MJ/K heat capacity and an 8 kW heater. It starts
at 15 degC, the outdoor temperature is 5 degC and the setpoint is 21 degC:

```matlab
c  = DHS.controllers.PID(0.5, 5e-4, 0);
dt = 60;  T = 15;  ref = 21;  Tout = 5;
UA = 300;  Qmax = 8000;  C = 1e7;
for k = 1:720                                   % twelve hours of one-minute steps
    u = c.update(T, ref, dt);                   % heating command between 0 and 1
    T = T + dt*(-UA*(T - Tout) + Qmax*u)/C;
end
```

After one hour the room is at 16.7 degC, after three at 19.6 degC, after six at 20.9 degC
and after twelve at 21.00 degC, when the command has settled at 0.60 (4.8 kW balances the
4.8 kW loss).

## LQR

`LQR` designs a full-state feedback law from a building's own linear model. The plant from
`RCBS.Simulation.getStateSpace` is augmented with the integral of the tracking error,
discretised at the control step $T_s$ by zero-order hold, and solved with `dlqr`
(Franklin, Powell and Emami-Naeini, *Feedback Control of Dynamic Systems*):

$$Q_h = -K_x\,(x - r) - K_i\,x_i,\qquad u = \mathrm{clamp}\!\left(Q_h/\dot Q_\text{max},\,0,\,1\right).$$

The integral state makes the response offset-free for constant setpoints and constant
disturbances. `LQR` needs the Control System Toolbox.

| Function | Inputs | Output or effect |
|---|---|---|
| `LQR(sysc, opts)` | `sysc`: state-space model from `getStateSpace`. `opts.io`: its `io` structure. `opts.Ts`: sample time (s). `opts.uMaxW`: heat that corresponds to `u = 1` (W). Weights: `opts.qZone`, `opts.qOther`, `opts.qInt`, `opts.R` | An LQR controller with the gains `.Kx` and `.Ki`. |
| `update(meas, ref, dt, aux)` | `aux.x` is required and must hold the node-temperature vector | The command in [0, 1]. |

```matlab
[sysc, io] = building.rcBuilding.simulation.getStateSpace();
hx.valve.attachController( DHS.controllers.LQR(sysc, struct('io',io, 'Ts',60, ...
    'uMaxW',hx.Qcap, 'qZone',6e3, 'qInt',8e-2, 'R',1e-9)) );
```

## Relay

The relay is an on/off controller with symmetric hysteresis. With $e = \mathrm{dir}\,(r - y)$
and half-width $h$, it switches on when $e > h$, off when $e < -h$, and holds its last
command in between (Åström and Hägglund, Sec. 7.4).

| Function | Inputs | Output or effect |
|---|---|---|
| `Relay(h)` or `Relay('h',.., 'dir',.., 'uMin',.., 'uMax',..)` | half-width of the dead band, in the units of the loop | A relay controller. |

With `Relay(0.5)` and a setpoint of 21 degC, successive measurements of 19.0, 20.4, 21.0,
21.6, 21.0, 20.4 and 20.0 give the commands 1, 1, 1, 0, 0, 1 and 1. Because the second reading of
21.0 lies inside the dead band, the command stays at 0.

## Comparing laws on one building

We ran the one-hall system of [the system page](dhs-system.md) for seven days with each law
on the substation valve. The figures cover occupied hours, when the setpoint is 21 degC.

| Law | Mean bias (K) | Root-mean-square error (K) |
|---|---|---|
| `LQR`, `qZone` 6e3, `qInt` 8e-2 | +0.001 | 0.008 |
| `PID(0.14, 1.6e-4, 0)` | +0.022 | 0.074 |
| `Relay(0.3)` | +0.010 | 0.226 |
| `Proportional`, `Kp` 0.5 | −0.619 | 0.623 |

A proportional law leaves a steady offset, as expected without integral action. The relay
shows no offset, and its output cycles inside the dead band. The PID and LQR settings are those
used in the toolbox examples. The relay band and the proportional gain are illustrative, and
none of the settings has been tuned for this building.
