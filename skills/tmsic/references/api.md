# TMSIC API reference (public calls)

Units: temperature degC, resistance K/W, capacity J/K, conductance W/K, heat W, flow kg/s, pressure Pa, length m.
Name-value pairs set any property of the object that is created, for example `'L',40`.

## RCBS (building thermal models)

| Call | Meaning |
|---|---|
| `b = RCBS.Building()` | Empty building. `b.outdoorTempFunc = @(t) ...` (degC for a `datetime`), `b.simulation.startDate`, `b.simulation.timeStep` |
| `b.addStorey(name)` | Storey `b.<name>` |
| `b.<storey>.addZone(name, 'C_main', C)` | Zone `b.<storey>.<name>` |
| `z.setAir(C_air, T0)` | Air node |
| `z.addWall(R, C, T0, name)`, `z.addRoof(R, C, T0, name)` | 2R1C element; `T0 = []` uses the air value |
| `z.addWindow(R, name)` | Conductance to the outdoors, no state. `addWindow(R, C, T0, name)` gives a 2R1C element |
| `z.addInternalMass(R, C, T0, name)` | Mass node tied to the air |
| `z.addNode(name, C, T0)` | Bare node |
| `z.connectToZone(other, R, name, C_mid, T0, kind)` | Plain conductance without `C_mid`; capacitive partition or slab with it |
| `z.connectToExternalSource(hf, nodeName)` | `hf(building)` returns watts, injected at `nodeName` (default `'T_main'`) every step |
| `z.getNodeTemp(name)`, `z.setNodeTemp(name,T)`, `z.getMainTemp()` | Live temperatures |
| `z.<part>.R`, `.C`, `.T` | Parts by name (`z.Wall.R = 0.03`); `z.Air.T` |
| `b.simulate(duration)` | Runs; results in `b.simulation.results` (`Time`, `Tall`, `OutdoorTemperature`, `<Storey>.<Zone>.T`) |
| `b.getAllZoneTemps()` | `containers.Map` of current zone temperatures |
| `b.visualize()` | Draws the RC network |
| `[sysc, io] = b.simulation.getStateSpace()` | Continuous `ss` model; `io.stateNames`, `io.inputNames`, `io.zoneMainRows` |
| `b.simulation.solverMode` | `"cached"` (backward Euler, default), `"forwardEuler"`, `"exact"`, `"legacy"` |
| `b.simulation.stepOnce(t, Tout, Q)` | One step for co-simulation |

## DHS (district heating)

### System
| Call | Meaning |
|---|---|
| `sys = DHS.System('weather',csv, 'startDate',dt, 'timeStep',dur, 'couplingIterations',n, 'pumpFrac',f, 'baseHeatW',W, 'integrator',m)` | Top object |
| `sys.addCentralHeatPlant(name)` | Plant `sys.<name>` |
| `sys.addHydraulicNetwork()` | Network (`'rho'`, `'mu'`, `'pReturnRef'`) |
| `sys.addBuilding(name, 'connD',.., 'connLength',.., 'Kminor',..)` | Building `sys.<name>` |
| `sys.run(duration)` | Result structure: `time`, `Tout`, `plant`, `bldg(i)`, `energy` |
| `sys.visualize()`, `sys.compile()`, `sys.setWeather(csv)` | Drawing, freeze, weather |
| `sys.startFunction`, `sys.stepFunction`, `sys.stopFunction` | Hooks `@(sys) ...` (named functions if they assign) |
| `sys.userData`, `sys.result`, `sys.time`, `sys.stepIndex`, `sys.wx` | Shared data, results, step time, step number, weather |

Result fields: `res.plant.Tsupply Tboiler Treturn TsupSet Qgas Qboiler eta firing Mtot Mbypass dpPump pSupHeader pumpSpeed`;
`res.bldg(i).name Tzone setpoint Tzones zoneNames Qdeliv Qsolar Qint Qvent valve pump mdot Tint_sup Tint_ret mdot_int Qzones`;
`res.energy.gas_kWh boiler_kWh delivered_kWh dist_loss_kWh plant_eff closure_err`.

### Plant
| Call | Meaning |
|---|---|
| `chp.addBoiler(name, 'QMax',W, 'etaRef',.., 'etaSlope',.., 'TetaRef',.., 'etaMin',.., 'etaMax',.., 'etaCurve',f)` | Boiler with a default firing PID |
| `chp.addPump(name, 'dp0',Pa, 'mdotRated',kg/s)` / `chp.attachPump(pump)` | Central pump |
| `chp.setSupplySetpoint(T)`, `chp.QgasMax()` | Setpoint, total capacity |
| `chp.supplyPort`, `chp.returnPort`, `chp.supplyPump`, `chp.boilers` | Ports, pump, boilers |
| `chp.Cw`, `Cw_rh`, `Cw_sh`, `mdotMinBoiler`, `TboilerMax`, `standbyLossW`, `sensorTau`, `firingSlewPerMin` | Plant parameters |
| `boiler.attachController(c)`, `boiler.etaOf(Tret)` | Firing law, efficiency |

### Network parts (`DHS.Hydraulic`)
| Call | Meaning |
|---|---|
| `DHS.Hydraulic.Pipe(name, 'L',m, 'D',m, 'eps',m, 'UperM',W/m/K)` | Pipe |
| `DHS.Hydraulic.Junction(name, 'supply'\|'return')` | Node |
| `DHS.Hydraulic.TJunction(name, 'mainDiameter',m, 'sideDiameter',m, 'roughness',m, 'frictionModel','fixed'\|'actual')` | Tee; ports `portA` (in), `portB` (run), `portC` (side) |
| `DHS.Hydraulic.Valve(name, 'Kvs',.., 'char','eqpct'\|'linear', 'rangeability',.., 'minPos',.., 'lag',s)`; `Valve.kvsFor(mdot, dp, rho)` | Control valve; `.pos`, `.posActual` |
| `DHS.Hydraulic.CentrifugalPump(name, 'dp0',.., 'mdotRated',.., 'dpRated',.., 'nMax',.., 'minSpeed',..)` | Pump; `.speed` (0 to 1), `.rpm`, `.mdotFree` |
| `DHS.Hydraulic.FixedDisplacementPump(name, 'mdotRated',.., 'dpMax',..)` | Positive-displacement pump |
| `a.connect(b)` | Join `b` downstream of `a` (junction, tee port, pipe, valve, pump, radiator, building) |
| `a.addPipe(D,L,...)`, `a.addValve(...)`, `a.addPump(...)`, `a.addTee(sideD,...)`, `a.addRadiator(name,...)` | Create, join, return |
| `hn.addJunction(name,'type','tee'\|'plain','side','return',...)`, `hn.addPipe(nodeA,nodeB,'name',n,'L',..,'D',..)`, `hn.addPump(nodeA,nodeB,...)`, `hn.connectBuilding(supplyJ,building,returnJ)` | Declarative style |
| `hn.addBypass(supplyJ, returnJ, 'L',..,'D',..,'Kvs',..,'pos',..)` | End-of-line bypass; `hn.bypassValve` |
| `hn.solve(pumpFrac)`, `hn.solver` (`'newton'`, `'anderson'`, `'fixedPoint'`), `hn.maxIter`, `hn.tol` | Flow solve and settings |
| `hn.<name>` | Parts by name, e.g. `hn.pipe1.L`, `hn.T1.portC.p` |

### Building
| Call | Meaning |
|---|---|
| `b.useRCModel(rc)` | Attach an `RCBS.Building` |
| `b.attachHeatExchanger(hx)`, `b.addHeatExchanger(name, 'UA',..,'Qcap',..)` | Substation (the second creates a plate exchanger) |
| `b.attachSolar(DHS.Solar(...))`, `b.attachSchedule(DHS.Schedule(...))` | Gains and schedule (one zone) |
| `b.attachZone('Storey.Zone', 'area',A, 'roomType',t, 'solar',s, 'schedule',sc, 'GventOcc',G, 'Ginf',G, 'freeCool',tf)` | Zone of a multi-zone building |
| `b.connect(returnJunction)` | Drain into the return side |
| `b.Tzone`, `b.setpoint`, `b.occupied`, `b.TintSup`, `b.TintRet`, `b.mdotInt` | Live values |
| `b.connLength`, `b.connD`, `b.Kminor`, `b.Ginf`, `b.GventOcc`, `b.loopCapacity` | Parameters |

### Heat exchangers
| Class | Use | Own parameters |
|---|---|---|
| `DHS.IdealHeatExchanger(name, 'Qnom',W, 'dTnom',K, 'exponent',n)` | No internal loop | radiator law |
| `DHS.ENTUPlateHeatExchanger(name, 'UA',W/K, 'Qcap',W)` | Internal loop | effectiveness-NTU |
| `DHS.FixedEffectivenessHeatExchanger(name, 'effectiveness',e, 'Qcap',W)` | Internal loop | fixed effectiveness |

Common: `Qcap`, `internalVolume`, `dpNomPrimary`, `mdotNomPrimary`; `hx.valve`, `hx.pump` (booster, stopped by default);
`hx.internalOutlet`, `hx.internalInlet` (where the loop starts and ends); `hx.attachPump(p)`, `hx.attachValve(v)`.

### Radiator
`DHS.Radiator(name, 'Qdes',W, 'Tsup',degC, 'Tret',degC, 'Tair',degC)`; `rad.connect(zone, R)` heats an RCBS zone;
`rad.connect(pipeOrJunction)` sends the water on; `rad.Tzone`, `rad.setpoint`, `rad.mdotDes`, `rad.pipeD`.

### Boundary conditions
- `DHS.Weather(csv)`; `w.at(datetime)` returns `Tout Tground ghi dhi dni sunZen sunAz sunEl albedo`.
- `DHS.Solar('winArea',struct('N',..,'E',..,'S',..,'W',..), 'SHGC',c, 'massFraction',f, 'skyArea',A)`.
- `DHS.Schedule('occStartHour',h, 'occEndHour',h, 'rampHours',h, 'weekendOccupied',tf, 'Tocc',T, 'Tsetback',T, 'gainOccW',W, 'gainMassFraction',f, 'workdays',2:6)`.

### Controllers (`DHS.controllers`)
| Class | Use |
|---|---|
| `PID(Kp, Ki, Kd [, Tf])` or `PID('Kp',..,'Ki',..,'Kd',..,'Tf',..,'Tt',..,'dir',..,'uMin',..,'uMax',..)` | `.measure = @(sys) ...`, `.reference = number or @(sys) ...` |
| `Relay(h)` | On/off with hysteresis; `.measure`, `.reference` |
| `LQR(A, B, Q, R, Ts)` | `.state = @(sys) x`, `.uScale`; needs the Control System Toolbox |
| `Callback(@(sys,dt) u)` | A function handle as a law |
| subclass of `Controller` | Implement `reset()` and `u = update(sys, dt)`; use `obj.clamp(u)` |

Attach with `actuator.attachController(c)` to `hx.valve`, `hx.pump`, a valve or pump you created, `chp.supplyPump`,
`hn.bypassValve` or a boiler. The command is limited to `[uMin, uMax]` (default 0 to 1).
