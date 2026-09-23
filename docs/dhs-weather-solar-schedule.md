# DHS.Weather, DHS.Solar and DHS.Schedule: boundary conditions and gains

These three classes supply what a building needs from outside: the weather, the sunlight
that reaches its windows, and the people and equipment inside. `DHS.Weather` reads the
measured or modelled climate. `DHS.Solar` and `DHS.Schedule` turn it, together with the
calendar, into the heat flows that `DHS.Building` injects into the RC model at each step.

## Weather

`DHS.Weather` reads a CSV file and returns interpolated values at any time inside its span.
The file needs nine columns:

| Column | Content |
|---|---|
| `period_end` | End of each period, as an ISO 8601 time stamp with offset, for example `2025-01-01T00:05:00-08:00`. |
| `ghi`, `dhi`, `dni` | Global horizontal, diffuse horizontal and direct normal irradiance (W/m²). |
| `zenith`, `azimuth` | Solar zenith angle (0 = overhead) and azimuth in the Solcast convention (degrees; 0 = north, negative = east, positive = west, ±180 = south). |
| `albedo` | Ground reflectance (0 to 1). |
| `t_outdoor_C`, `t_ground_C` | Outdoor air temperature and undisturbed ground temperature (degC). |

The file `solar_data_2025.csv` in the toolbox root has 5-minute values from 1 January to
30 June 2025 for Kelowna, Canada (irradiance from Solcast, temperatures from Environment
and Climate Change Canada station 51117). Outside the file's span, `Weather.at` warns and
uses the nearest sample.

```matlab
w  = DHS.Weather('solar_data_2025.csv');
wx = w.at(datetime(2025,1,15,12,0,0));
```

```
wx.ghi = 233   wx.dhi = 157   wx.dni = 236    (W/m^2)
wx.sunZen = 71   wx.sunAz = 178   wx.sunEl = 19    (degrees)
wx.albedo = 0.46   wx.Tout = 0.7   wx.Tground = 2.5   (degC)
```

| Function | Inputs | Output or effect |
|---|---|---|
| `Weather(csvPath)` | path to the CSV | Loads and indexes the file. |
| `at(t)` | a `datetime`, or seconds since the first sample | A structure with `Tout`, `Tground`, `ghi`, `dhi`, `dni`, `sunZen`, `sunAz`, `sunEl`, `albedo`. Azimuth is converted to a compass angle (0 = N, 90 = E, 180 = S, 270 = W). |
| `atVec(tt)` | a `datetime` array | The same fields as vectors. `DHS.System` uses it once per run. |
| `timeVector()` | none | The time grid of the file. |

## Solar gain

`DHS.Solar` computes the irradiance on each facade with the isotropic sky model of Liu and
Jordan (Duffie and Beckman, *Solar Engineering of Thermal Processes*, 4th ed.):

$$I = I_\text{DNI}\max(0,\cos\theta) + I_\text{DHI}\,\frac{1+\cos\beta}{2} + I_\text{GHI}\,\rho\,\frac{1-\cos\beta}{2}.$$

Here $\beta$ is the tilt of the surface (90 degrees for a wall), $\rho$ is the albedo, and
the angle of incidence is $\cos\theta = \cos\theta_z\cos\beta + \sin\theta_z\sin\beta\cos(\gamma_s - \gamma)$,
with $\theta_z$ the solar zenith angle, $\gamma_s$ the solar azimuth and $\gamma$ the facade
azimuth. The gain through the glazing of a zone is $Q_\text{sol} = \sum_f A_f\,\mathrm{SHGC}\,I_f$,
summed over the four facades. A fixed fraction goes to the internal-mass node and the rest to
the air node.

```matlab
sol = DHS.Solar('winArea',struct('N',40,'E',60,'S',80,'W',40), 'SHGC',0.44, 'massFraction',0.12);
[Qair, Qmass, Qwall, detail] = sol.heatGain(wx);      % wx from the weather example above
```

With the sample above (the sun 19 degrees above the horizon, almost due south) the gain is
18.3 kW to the air node and 2.5 kW to the mass node. The south facade receives most of it.

| Function | Inputs | Output or effect |
|---|---|---|
| `Solar('winArea',struct('N',..,'E',..,'S',..,'W',..), 'SHGC',c, 'massFraction',f)` | window area per facade (m²), solar heat-gain coefficient, fraction of gain sent to the mass node | A solar model. |
| `heatGain(wx)` | a weather sample from `Weather.at` | `[Qair, Qmass, Qwall, detail]` in watts. |
| `totalWindowArea()` | none | Sum of the four facade areas (m²). |

## Occupancy schedule

`DHS.Schedule` describes occupancy, the heating setpoint and the internal gains on a weekly
cycle. Workdays have one occupied window. An optional window can be set for weekends. Before
occupancy the setpoint rises linearly from the setback value to the occupied value over
`rampHours` (optimal start, with slope $(T_\text{occ} - T_\text{sb})/t_\text{ramp}$). The
internal gain is a single power level, occupied or base, split between a convective part
on the air node and a radiant part on the mass node.

```matlab
s = DHS.Schedule('occStartHour',7, 'occEndHour',18, 'rampHours',1, ...
    'weekendOccupied',false, 'Tocc',21, 'Tsetback',18, ...
    'gainOccW',15*3700, 'gainMassFraction',0.30);

t = datetime(2025,1,7) + hours(6.5);          % Tuesday 06:30
[Tsp, Qair, Qmass] = s.at(t);                 % 19.5 degC, 5,828 W, 2,498 W
```

| Time | Occupied | Setpoint (degC) | Internal gain (kW) |
|---|---|---|---|
| Tuesday 03:00 | no | 18.0 | 8.3 |
| Tuesday 06:30 | no | 19.5 (on the ramp) | 8.3 |
| Tuesday 07:30 | yes | 21.0 | 55.5 |
| Tuesday 12:00 | yes | 21.0 | 55.5 |
| Tuesday 19:00 | no | 18.0 | 8.3 |
| Saturday 12:00 | no | 18.0 | 8.3 |

The base gain is 15 percent of the occupied gain by default, and 30 percent of every gain
goes to the mass node.

| Function | Inputs | Output or effect |
|---|---|---|
| `Schedule('occStartHour',.., 'occEndHour',.., 'rampHours',.., 'weekendOccupied',.., 'weekendStartHour',.., 'weekendEndHour',.., 'Tocc',.., 'Tsetback',.., 'gainOccW',.., 'gainMassFraction',..)` | hours of day, logical, temperatures (degC), gain (W), fraction | A weekly schedule. |
| `isOccupied(t)` | a `datetime` | Logical. |
| `setpoint(t)` | a `datetime` | Heating setpoint (degC): occupied, setback or on the ramp. |
| `internalGain(t)` | a `datetime` | `[Qair, Qmass, Qtot]` in watts. |
| `at(t)` | a `datetime` | `[Tsp, Qair, Qmass]` in one call. |

The accuracy of the solar transposition and of the schedule logic is checked against
hand-computable cases in [`../validation/README.md`](../validation/README.md).
