# References

The sources below support the equations and default parameter values used in the toolbox.
Each entry states what the toolbox takes from it. The validation report
([`../validation/README.md`](../validation/README.md)) lists the sources used to check each
component.

## Building RC thermal modelling

- EN ISO 13790:2008. *Energy performance of buildings: calculation of energy use for space
  heating and cooling.* Annex C gives the 5R1C hourly method, the wall R/2–C–R/2 element
  and the mass-surface coupling.
- EN ISO 52016-1:2017. Successor to ISO 13790, with an hourly dynamic method.
- Bacher, P. and Madsen, H. (2011). Identifying suitable models for the heat dynamics of
  buildings. *Energy and Buildings* 43(7), 1511–1522. Grey-box model order selection and
  typical building time constants.
- Michalak, P. (2022). A thermal network model for the dynamic simulation of the energy
  performance of buildings with a time varying ventilation flow. *Energies* 15, 3709.
- Reynders, G., Diriken, J. and Saelens, D. (2014). Quality of grey-box models and
  identified parameters as function of the accuracy of input and observation signals.
  *Energy and Buildings* 82, 263–274. Building time constants of 20 to 100 h.
- ASHRAE Handbook: Fundamentals (2021). Chapter 18 (nonresidential cooling and heating
  load calculations) for internal-gain densities, radiant fractions and areal heat
  capacities. Chapters 25 to 27 for envelope heat transfer.

## Energy codes and schedules

- ANSI/ASHRAE/IES Standard 90.1-2019. *Energy standard for buildings except low-rise
  residential buildings.* Appendix G baseline, climate zone 5 envelope values, setback
  (Section 6.4.3.4), and occupancy, lighting and receptacle schedules.
- National Energy Code of Canada for Buildings (NECB) 2020. Envelope values and operating
  schedules for cold Canadian climates. Kelowna is in climate zone 5.
- ANSI/ASHRAE Standard 62.1. Ventilation rates for offices and classrooms.
- CIBSE Guide H (2009). *Building control systems.* Section 3, optimal start and pre-heat.

## Heat exchangers

- Incropera, F.P. and DeWitt, D.P. *Fundamentals of Heat and Mass Transfer*, 6th ed.,
  Wiley. Section 11.4, the effectiveness–NTU method and the counterflow relation.
- Kays, W.M. and London, A.L. (1984). *Compact Heat Exchangers*, 3rd ed., McGraw-Hill.
- VDI Heat Atlas (2010), Springer. Plate heat exchanger correlations.
- ESDU 86018. Design of plate heat exchangers.

## Hydraulics

- Swamee, P.K. and Jain, A.K. (1976). Explicit equations for pipe-flow problems.
  *Journal of the Hydraulics Division, ASCE* 102(5), 657–664. The explicit friction factor.
- Colebrook, C.F. (1939). Turbulent flow in pipes, with particular reference to the
  transition region between the smooth and rough pipe laws. *Journal of the Institution of
  Civil Engineers* 11, 133–156.
- Brkić, D. (2011). Review of explicit approximations to the Colebrook relation for flow
  friction. *Journal of Petroleum Science and Engineering* 77(1), 34–48.
- Todini, E. and Pilati, S. (1988). A gradient algorithm for the analysis of pipe networks.
  In *Computer Applications in Water Supply*, Wiley. The global gradient algorithm behind
  EPANET.
- Rossman, L.A. (2000). *EPANET 2 users manual.* US Environmental Protection Agency.
- Larock, B.E., Jeppson, R.W. and Watters, G.Z. (2000). *Hydraulics of Pipeline Systems.*
  CRC Press.
- IEC 60534-2-1. Control valve sizing, the flow coefficient $K_v$. IEC 60534-2-4, inherent
  flow characteristics (linear and equal-percentage).
- Crane Co. (2013). *Flow of Fluids Through Valves, Fittings, and Pipe.* Technical Paper
  No. 410. The equivalent-length method for fitting losses. The toolbox uses the standard
  tee values of 20 diameters (run) and 60 diameters (branch).
- Idelchik, I.E. (2007). *Handbook of Hydraulic Resistance*, 4th ed., Begell House. Tee and
  branch loss-coefficient tables (Diagram 7-29), used as a qualitative cross-check.

## Pumps

- Karassik, I.J., Messina, J.P., Cooper, P. and Heald, C.C. (eds.) (2008). *Pump Handbook*,
  4th ed., McGraw-Hill. Chapter 2, centrifugal pump affinity laws. Chapter 9, rotary and
  positive-displacement pumps.
- Hydraulic Institute. ANSI/HI 9.6.7. Effects of liquid viscosity on rotodynamic pump
  performance. The affinity-law reference for `CentrifugalPump` speed scaling.
- Gülich, J.F. (2010). *Centrifugal Pumps*, 2nd ed., Springer.
- Volk, M. (2013). *Pump Characteristics and Applications*, 3rd ed., CRC Press. Chapter 9,
  the idealised positive-displacement pump curve used by `FixedDisplacementPump`.

## District heating

- Frederiksen, S. and Werner, S. (2013). *District Heating and Cooling.* Studentlitteratur.
  Temperature levels, distribution pressures and velocities, pump curves and substation
  layouts. The 20 to 60 kPa primary-side design pressure drop of a plate exchanger, used
  for `HeatExchanger.dpNomPrimary`.
- IEA DHC (International Energy Agency, District Heating and Cooling programme), Annex TS
  reports. Low-temperature design ranges and pre-insulated pipe heat loss
  ($U' \approx 0.2$ to $0.4$ W/(m·K)).
- Euroheat and Power (2008). *Guidelines for district heating substations.*
- Logstor and Uponor pre-insulated pipe product data, for pipe conductivity and $U'$.

## Boilers and plant

- ASHRAE Handbook: HVAC Systems and Equipment (2020). Chapter 32 (boilers) and Chapter 13
  (hydronic heating and cooling).
- AHRI Standard 1500. *Performance rating of commercial space heating boilers.*
- Manufacturer part-load efficiency curves against return-water temperature (for example
  Viessmann Vitocrossal and Buderus SB series), for the condensing-boiler $\eta(T_\text{return})$.

## Solar geometry and irradiance

- Duffie, J.A. and Beckman, W.A. (2013). *Solar Engineering of Thermal Processes*, 4th ed.,
  Wiley. Solar position, angle of incidence (Eq. 1.6.2) and plane-of-array transposition
  (Eq. 2.15.1).
- Liu, B.Y.H. and Jordan, R.C. (1963). The long-term average performance of flat-plate
  solar-energy collectors. *Solar Energy* 7(2), 53–74. The isotropic sky model.
- Perez, R. et al. (1990). Modeling daylight availability and irradiance components from
  direct and global irradiance. *Solar Energy* 44(5). An anisotropic sky model, not
  implemented.

## Ground temperature

- Kusuda, T. and Achenbach, P.R. (1965). Earth temperature and thermal diffusivity at
  selected stations in the United States. *ASHRAE Transactions* 71(1), 61–75.

## Control

- Åström, K.J. and Hägglund, T. (2006). *Advanced PID Control.* ISA. Parallel form,
  filtered derivative, back-calculation anti-windup, relay feedback and lambda tuning.
- Åström, K.J. and Murray, R.M. (2008). *Feedback Systems: An Introduction for Scientists
  and Engineers.* Princeton University Press.
- Franklin, G.F., Powell, J.D. and Emami-Naeini, A. (2019). *Feedback Control of Dynamic
  Systems*, 8th ed., Pearson. LQR (Section 7.9), integral control (Section 9.4) and exact
  zero-order-hold discretisation.
- Anderson, B.D.O. and Moore, J.B. (1990). *Optimal Control: Linear Quadratic Methods.*
  Prentice-Hall.

## Data sources

- Solcast. Modelled irradiance time series (`solar_data_2025.csv`).
- Environment and Climate Change Canada. Historical climate data,
  <https://climate.weather.gc.ca/>. Station 51117, Kelowna UBCO (climate ID 1123996),
  hourly observations for 2025.
