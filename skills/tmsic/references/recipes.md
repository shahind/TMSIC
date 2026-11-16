# TMSIC recipes

Run each recipe from the toolbox folder after `setup`. Recipes 1 to 6 were run as printed. Recipes 7 and 8 point to
example scripts. Longer, commented versions are in `examples/rcbs_tutorial.m`, `examples/dhs_tutorial.m` and
`examples/dhs_internal_loop_tutorial.m`.

## 1. Simulate one zone and read the temperature

```matlab
b = RCBS.Building();
b.addStorey('S1');
b.S1.addZone('Office');
b.S1.Office.setAir(1.2e6, 20);
b.S1.Office.addWall(0.02, 2.0e7, [], 'Wall');
b.S1.Office.addWindow(0.01, 'Window');
b.S1.Office.addInternalMass(0.002, 5.0e7, [], 'IntMass');
b.S1.Office.connectToExternalSource( ...
    @(bb) 3000*(hour(bb.simulation.t) >= 8 && hour(bb.simulation.t) < 18), 'T_main');
b.outdoorTempFunc      = @(t) 4 + 8*sin(2*pi*(hour(t) - 8)/24);
b.simulation.startDate = datetime(2025,1,1);
b.simulation.timeStep  = minutes(15);
b.simulate(days(3));
T = b.simulation.results.S1.Office.T;      % 20.0 to 14.1 degC over the three days
```

## 2. Export the linear model

```matlab
[sysc, io] = b.simulation.getStateSpace();   % needs the Control System Toolbox
A = sysc.A;  B = sysc.B;                      % x' = A x + B u
io.inputNames                                 % {'T_outdoor','Q_S1.Office.T_main','Q_S1.Office.Wall','Q_S1.Office.IntMass'}
```

## 3. A district system with one building and an ideal substation

```matlab
rc = RCBS.Building();  rc.addStorey('S1');  rc.S1.addZone('Hall');
rc.S1.Hall.setAir(2e7, 20);
rc.S1.Hall.addWall(0.0004, 3e8, [], 'Wall');
rc.S1.Hall.addWindow(0.00067, 'Window');
rc.S1.Hall.addInternalMass(0.0002, 5e8, [], 'Mass');

sys = DHS.System('weather','solar_data_2025.csv', 'startDate',datetime(2025,1,1));
chp = sys.addCentralHeatPlant('CHP');
chp.addBoiler('B1', 'QMax',1.0e6);
chp.addPump('P0', 'dp0',3.0e5, 'mdotRated',6);
chp.setSupplySetpoint(70);
hn   = sys.addHydraulicNetwork();
tee1 = chp.supplyPort.addPipe(0.10, 40).addTee(0.05);
r1   = DHS.Hydraulic.Junction('R1', 'return');
r1.addPipe(0.10, 40).connect(chp.returnPort);

b  = sys.addBuilding('Hall');
b.useRCModel(rc);
hx = DHS.IdealHeatExchanger('HX', 'Qnom',2e5);
b.attachHeatExchanger(hx);
c = DHS.controllers.PID(0.14, 1.6e-4, 0);
c.measure = @(sys) sys.Hall.Tzone;  c.reference = @(sys) sys.Hall.setpoint;
hx.valve.attachController(c);
b.attachSolar(DHS.Solar('winArea',struct('N',20,'E',20,'S',20,'W',20), 'SHGC',0.4, 'massFraction',0.1));
b.attachSchedule(DHS.Schedule('occStartHour',7, 'occEndHour',18, 'rampHours',1, ...
    'Tocc',21, 'Tsetback',18, 'gainOccW',20e3, 'gainMassFraction',0.3));
tee1.portC.connect(b);
b.connect(r1);

res = sys.run(days(7));
fprintf('closure %.1e, mean supply %.1f degC\n', res.energy.closure_err, mean(res.plant.Tsupply));
```

Expect about 5 s, supply temperature 69.4 to 75.5 degC, and closure near 1e-11.

## 4. Add a second building

Repeat the building block of recipe 3 with another name, another tee and another return junction:

```matlab
tee2 = tee1.portB.addPipe(0.10, 50).addTee(0.05);      % the run of the first tee continues to a second tee
r2   = DHS.Hydraulic.Junction('R2', 'return');
r2.addPipe(0.10, 50).connect(r1);                       % the second return junction drains into the first
% ... create building 'Office', attach the model, exchanger, controller, solar, schedule ...
tee2.portC.connect(officeBuilding);
officeBuilding.connect(r2);
```

## 5. A custom controller

Save as `Proportional.m`:

```matlab
classdef Proportional < DHS.controllers.Controller
    properties
        Kp = 0.5;
        measure;
        reference;
    end
    methods
        function reset(obj)
        end
        function u = update(obj, sys, dt)
            r = obj.reference;
            if isa(r, 'function_handle'), r = r(sys); end
            u = obj.clamp(obj.Kp * (r - obj.measure(sys)));
        end
    end
end
```

Use it: `c = Proportional(); c.measure = @(sys) sys.Hall.Tzone; c.reference = 21; hx.valve.attachController(c);`

## 6. Change a parameter during a run

```matlab
sys.stepFunction = @(sys) setWindow(sys);
function setWindow(sys)
    if sys.stepIndex == 500
        z = sys.Hall.S1.Hall;
        z.Window.R = z.Window.R / 2;
    end
end
```

(A hook that assigns values must be a named function; put it at the end of the script.)

## 7. A building with an internal loop and radiator

Use `examples/dhs_internal_loop_tutorial.m` as the template. The pattern is:
`hx = b.addHeatExchanger('HX','UA',8e3,'Qcap',2e5)`, then connect pipes, a pump, a tee, a zone valve and a radiator
from `hx.internalOutlet` to `hx.internalInlet`, size the radiator with `DHS.Radiator('rad1','Qdes',W,'Tsup',60,'Tret',40)`,
and attach controllers to the zone valve, the loop pump and `hx.valve`.

## 8. Fit RC parameters to measurements

Put the measurements in the workspace and run `examples/system_identification.m`:

```matlab
data.t = ...;  data.T_in = ...;  data.T_out = ...;  data.Q_in_data = ...;   % equal-length column vectors
data_validation = ...;                                                       % same fields, a held-out period
system_identification
```

## 9. Check the toolbox

```matlab
runtests('tests')            % unit tests
run_all_validation           % 20 accuracy checks
```
