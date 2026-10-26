# Solvers and time stepping

A run uses three kinds of numerical method, and each can be chosen and adjusted.

| What | Property | Choices | Default |
|---|---|---|---|
| Flows in a pipe network | `hn.solver` | `'newton'`, `'anderson'`, `'fixedPoint'` | `'newton'` |
| Time integration of the buildings' RC models, the radiators and the loop water | `sys.integrator` | `'backwardEuler'`, `'forwardEuler'`, `'exact'` | `'backwardEuler'` |
| Step of the whole co-simulation | `sys.timeStep` | any duration | 60 s |

## Hydraulic solver

At every step the network finds the branch flows $\dot m$ that satisfy $\dot m = G(\dot m)$, where
$G(\dot m)$ is the flow each branch passes at the pressure difference that the flows $\dot m$ leave across it
(see [the hydraulics page](dhs-hydraulic.md)). The district network and each building's internal loop are
solved separately, each by its own `DHS.HydraulicNetwork`, and each has its own settings:

```matlab
hn.solver  = 'newton';     % or 'anderson', 'fixedPoint'
hn.maxIter = 40;           % most iterations of one solve
hn.tol     = 1e-9;         % the flow change [kg/s] that ends the iteration
hn.damping = 0.5;          % first step of 'anderson' and 'fixedPoint'
hn.andersonDepth = 5;      % iterates 'anderson' combines
```

For the loop of a building, `building.internalLoop` is its network.

- **`'newton'`** (default). Newton's method on $F(\dot m) = \dot m - G(\dot m) = 0$. The Jacobian is built once by
  finite differences, updated by Broyden's rule and kept for the next step, whose flows are close, so a solve
  takes a handful of evaluations. A backtracking line search keeps the residual falling. It converges with
  pump curves that couple the branches strongly and with valves that are almost shut, the cases in
  which a plain iteration does not.
- **`'anderson'`**. A damped first step, then Anderson acceleration of the fixed point $\dot m = G(\dot m)$ over the
  last `andersonDepth` iterates. Cheaper per iteration, but it can fail when a valve is almost shut.
- **`'fixedPoint'`**. $\dot m \leftarrow \dot m + w\,(G(\dot m) - \dot m)$ with the damping $w$ halved whenever the error
  stops falling. The simplest method and the slowest; it may not converge for a loop with a bypass or a nearly shut valve.

On a network where all three converge (a district main with two buildings) they give the same flows to 1e-6 kg/s (a unit test checks it).
After a solve, `hn.lastIter` is the number of evaluations of $G$ it used and `hn.lastErr` the flow change of the last one.

Chains of links that carry the flow of a single branch (a valve and the pipes before a radiator) are added to
that branch's resistance whichever method is used, so a nearly shut valve does not make the problem stiff.

## Time integration

The dynamic elements are first-order: the thermal nodes of a building's RC model (`RCBS.Simulation`), the
metal of a radiator and the water of a loop. `sys.integrator` selects how they are advanced over a step
$\Delta t$:

- **`'backwardEuler'`** (default): implicit, stable for any step, first-order accurate. The RC model uses a
  cached sparse factorisation, and the radiator metal and the loop water are solved without iteration.
- **`'forwardEuler'`**: explicit, first-order accurate, cheap, and stable only for $\Delta t$ below twice the
  smallest time constant. The RC model estimates its limit from the conductance and capacity of every node and
  warns (`RCBS:Simulation:forwardEulerUnstable`) when the step is beyond it. A radiator warns when
  $\Delta t\,(a + UA_{ma})/C > 2$ and the loop water when $\dot m c_p\,\Delta t / C_\ell > 2$, so a loop with little
  water needs a small step.
- **`'exact'`**: the exact solution for inputs held constant over the step (a zero-order hold): the matrix
  exponential for the RC model, the exponential response for a radiator and for the loop water. It has no step-size error
  for the dynamics themselves; the remaining error is from the inputs changing within the step.

```matlab
sys = DHS.System('weather','solar_data_2025.csv', 'timeStep',seconds(30), 'integrator','exact');
sys.integrator = 'forwardEuler';                   % or change it later
b.sim.solverMode = "forwardEuler";                 % one building's RC model alone (RCBS.Simulation.solverMode)
```

Setting `sys.integrator` sets the `solverMode` of every building's `RCBS.Simulation` ("cached" for backward
Euler, "forwardEuler", "exact") and the integrator of its radiators and loop water at the start of a run. The plant's
water and the boilers (`DHS.CentralHeatPlant`) are not affected: they have their own implicit update.
Backward Euler stays the default because the controllers act on algebraic processes (a valve position
sets a flow within the step), and an implicit update keeps those loops well behaved at a 60 s step.

## Step and coupling

`sys.timeStep` is the step of the whole co-simulation: the weather, the controllers, the hydraulic solve and the thermal update
all use it. A smaller step follows faster dynamics (a stiff controller, a small loop volume with forward Euler) at proportional cost.
`sys.couplingIterations` (default 2) is the number of passes between the supply and return temperature walks and the plant within a step.
