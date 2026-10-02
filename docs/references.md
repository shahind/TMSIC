# References

The sources below support the equations and default parameter values used in the toolbox.
Each entry states what the toolbox takes from it. DOIs were checked against Crossref. Where
a source has no DOI, the entry gives the publisher or project page, or the ISBN. The
documentation pages and the validation report
([`../validation/README.md`](../validation/README.md)) cite these entries by number.

## Building RC thermal modelling

- <a id="r1"></a>**[1]** EN ISO 13790:2008. *Energy performance of buildings: calculation of energy use for space
  heating and cooling.* Annex C gives the 5R1C hourly method, the wall R/2–C–R/2 element and
  the mass-surface coupling. <https://www.iso.org/standard/41974.html>
- <a id="r2"></a>**[2]** EN ISO 52016-1:2017. *Energy performance of buildings: energy needs for heating and
  cooling, internal temperatures and sensible and latent heat loads. Part 1: Calculation
  procedures.* Successor to ISO 13790, with an hourly dynamic method.
  <https://www.iso.org/standard/65696.html>
- <a id="r3"></a>**[3]** Bacher, P. and Madsen, H. (2011). Identifying suitable models for the heat dynamics of
  buildings. *Energy and Buildings* 43(7), 1511–1522. Grey-box model order selection and
  typical building time constants. DOI: [10.1016/j.enbuild.2011.02.005](https://doi.org/10.1016/j.enbuild.2011.02.005)
- <a id="r4"></a>**[4]** Michalak, P. (2019). A thermal network model for the dynamic simulation of the energy
  performance of buildings with the time varying ventilation flow. *Energy and Buildings*
  202, 109337. DOI: [10.1016/j.enbuild.2019.109337](https://doi.org/10.1016/j.enbuild.2019.109337)
- <a id="r5"></a>**[5]** Michalak, P. (2022). Thermal network model for an assessment of summer indoor comfort in a
  naturally ventilated residential building. *Energies* 15(10), 3709.
  DOI: [10.3390/en15103709](https://doi.org/10.3390/en15103709)
- <a id="r6"></a>**[6]** Reynders, G., Diriken, J. and Saelens, D. (2014). Quality of grey-box models and identified
  parameters as function of the accuracy of input and observation signals. *Energy and
  Buildings* 82, 263–274. Building time constants of 20 to 100 h.
  DOI: [10.1016/j.enbuild.2014.07.025](https://doi.org/10.1016/j.enbuild.2014.07.025)
- <a id="r7"></a>**[7]** ASHRAE Handbook: Fundamentals (2021). Chapter 18 (nonresidential cooling and heating load
  calculations) for internal-gain densities, radiant fractions and areal heat capacities.
  Chapters 25 to 27 for envelope heat transfer. <https://www.ashrae.org/technical-resources/ashrae-handbook>

## Energy codes and schedules

- <a id="r8"></a>**[8]** ANSI/ASHRAE/IES Standard 90.1-2022. *Energy standard for buildings except low-rise
  residential buildings.* Appendix G baseline, climate zone 5 envelope values, setback
  (Section 6.4.3.4), and occupancy, lighting and receptacle schedules.
  <https://www.ashrae.org/technical-resources/bookstore/standard-90-1>
- <a id="r9"></a>**[9]** National Energy Code of Canada for Buildings (NECB) 2020. Envelope values and operating
  schedules for cold Canadian climates. Kelowna is in climate zone 5.
  <https://nrc.canada.ca/en/certifications-evaluations-standards/codes-canada/codes-canada-publications/national-energy-code-canada-buildings-2020>
- <a id="r10"></a>**[10]** ANSI/ASHRAE Standard 62.1. Ventilation rates for offices and classrooms.
  <https://www.ashrae.org/technical-resources/standards-and-guidelines>
- <a id="r11"></a>**[11]** CIBSE Guide H (2009). *Building control systems.* Section 3, optimal start and pre-heat.
  ISBN 978-1-906846-00-8. <https://www.cibse.org/knowledge-research/knowledge-portal/guide-h-building-control-systems-2009>

## Heat exchangers

- <a id="r12"></a>**[12]** Incropera, F.P. and DeWitt, D.P. (2007). *Fundamentals of Heat and Mass Transfer*, 6th ed.,
  Wiley. Section 11.4, the effectiveness–NTU method and the counterflow relation. Sections 5.1 to 5.3,
  the lumped-capacitance method.
  ISBN 978-0-471-45728-2.
- <a id="r13"></a>**[13]** Kays, W.M. and London, A.L. (1984). *Compact Heat Exchangers*, 3rd ed., McGraw-Hill.
  ISBN 978-0-07-033418-2.
- <a id="r14"></a>**[14]** VDI Heat Atlas (2010), 2nd ed., Springer. Plate heat exchanger correlations.
  DOI: [10.1007/978-3-540-77877-6](https://doi.org/10.1007/978-3-540-77877-6)
- <a id="r15"></a>**[15]** ESDU 86018. Design of plate heat exchangers. <https://www.esdu.com>

## Hydraulics

- <a id="r16"></a>**[16]** Swamee, P.K. and Jain, A.K. (1976). Explicit equations for pipe-flow problems. *Journal of
  the Hydraulics Division, ASCE* 102(5), 657–664. The explicit friction factor.
  DOI: [10.1061/JYCEAJ.0004542](https://doi.org/10.1061/JYCEAJ.0004542)
- <a id="r17"></a>**[17]** Colebrook, C.F. (1939). Turbulent flow in pipes, with particular reference to the
  transition region between the smooth and rough pipe laws. *Journal of the Institution of
  Civil Engineers* 11(4), 133–156. DOI: [10.1680/ijoti.1939.13150](https://doi.org/10.1680/ijoti.1939.13150)
- <a id="r18"></a>**[18]** Brkić, D. (2011). Review of explicit approximations to the Colebrook relation for flow
  friction. *Journal of Petroleum Science and Engineering* 77(1), 34–48.
  DOI: [10.1016/j.petrol.2011.02.006](https://doi.org/10.1016/j.petrol.2011.02.006)
- <a id="r19"></a>**[19]** Todini, E. and Pilati, S. (1988). A gradient algorithm for the analysis of pipe networks. In
  *Computer Applications in Water Supply*, Wiley. The global gradient algorithm behind EPANET.
  (No DOI.)
- <a id="r20"></a>**[20]** Rossman, L.A. (2000). *EPANET 2 users manual.* US Environmental Protection Agency,
  EPA/600/R-00/057. <https://nepis.epa.gov/Exe/ZyPURL.cgi?Dockey=P1007WWU.TXT>
- <a id="r21"></a>**[21]** Larock, B.E., Jeppson, R.W. and Watters, G.Z. (2000). *Hydraulics of Pipeline Systems.* CRC
  Press. DOI: [10.1201/9781420050318](https://doi.org/10.1201/9781420050318)
- <a id="r22"></a>**[22]** IEC 60534-2-1:2011. *Industrial-process control valves. Part 2-1: Flow capacity. Sizing
  equations for fluid flow under installed conditions.* The flow coefficient $K_v$. IEC 60534-2-4
  covers the inherent flow characteristics (linear, equal-percentage).
  <https://webstore.iec.ch/en/publication/2461>
- <a id="r23"></a>**[23]** Crane Co. (2009). *Flow of Fluids Through Valves, Fittings, and Pipe.* Technical Paper
  No. 410, metric ed. ISBN 978-1-4005-2712-0 (`paper/references/crane2013`). This edition
  gives the general equivalent-length (L/D) and K-factor methods for valves and fittings
  (Section 2, pages A-27 to A-30), but for tees and wyes specifically it uses a
  correlation in the branch-to-combined flow ratio, the area ratio and the branch angle
  (Eqs. 2-34 to 2-38), stating explicitly that this replaces an earlier, size-only
  convention: "the method used in previous versions of this paper treated K_branch and
  K_run as dependent only on the fitting size... further research has shown that the
  resistance coefficients depend on the cross sectional area ratios of the legs, the
  angle between the legs, the ratio of the flow rates, and whether the flows are
  converging or diverging." The toolbox's 20-diameter (run) / 60-diameter (branch)
  tee convention is that earlier, size-only method, not this edition's own treatment of
  tees; it is reproduced here from secondary engineering references (e.g. SimuPipe's
  K-factor table, <https://simupipe.com/resources/k-factor-table>) since the specific
  numbers are not printed in this edition. <https://tp410.com/>
- <a id="r24"></a>**[24]** Idelchik, I.E. (2007). *Handbook of Hydraulic Resistance*, 4th ed., Begell House. Tee and
  branch loss-coefficient tables (Diagram 7-29): an alternative, flow-split-dependent
  treatment of the same fitting, not a confirmation of [23]'s fixed-multiplier ordering.
  DOI: [10.1615/978-1-56700-251-5.0](https://doi.org/10.1615/978-1-56700-251-5.0)

## Pumps

- <a id="r25"></a>**[25]** Karassik, I.J., Messina, J.P., Cooper, P. and Heald, C.C. (eds.) (2008). *Pump Handbook*,
  4th ed., McGraw-Hill. Chapter 2, centrifugal pump affinity laws. Chapter 9, rotary and
  positive-displacement pumps. ISBN 978-0-07-146044-6.
- <a id="r26"></a>**[26]** Gülich, J.F. (2010). *Centrifugal Pumps*, 2nd ed., Springer. Similarity (affinity) laws and
  the quadratic head–flow curve used by `CentrifugalPump`.
  DOI: [10.1007/978-3-642-12824-0](https://doi.org/10.1007/978-3-642-12824-0)
- <a id="r27"></a>**[27]** Volk, M. (2013). *Pump Characteristics and Applications*, 3rd ed., CRC Press. Chapter 9,
  the idealised positive-displacement pump curve used by `FixedDisplacementPump`.
  DOI: [10.1201/b15559](https://doi.org/10.1201/b15559)

## District heating

- <a id="r28"></a>**[28]** Frederiksen, S. and Werner, S. (2013). *District Heating and Cooling.* Studentlitteratur.
  Temperature levels, distribution pressures and velocities, pump curves and substation
  layouts. A copy could not be independently obtained for this project; `HeatExchanger.dpNomPrimary`'s
  design-range guidance instead cites [29](#r29). ISBN 978-91-44-08530-2.
- <a id="r29"></a>**[29]** Skagestad, B. and Mildenstein, P. (2002). *District Heating and Cooling Connection
  Handbook.* IEA District Heating and Cooling programme, Annex VI, NOVEM. Table 11.4
  ("Permissible pressure losses through a heat exchanger") gives a primary-side design
  pressure loss below 20 kPa for domestic hot water and low-pressure heating substations,
  with a separate 50 to 60 kPa target for the whole substation's supply/return
  differential. <https://www.iea-dhc.org/fileadmin/documents/Annex_VI/DHC_Connection_Handbook.pdf>
- <a id="r30"></a>**[30]** Euroheat and Power (2008). *Guidelines for district heating substations.*
  <https://www.euroheat.org/>
- <a id="r31"></a>**[31]** Logstor and Uponor pre-insulated pipe product data, for pipe conductivity and $U'$.

## Boilers and plant

- <a id="r32"></a>**[32]** ASHRAE Handbook: HVAC Systems and Equipment (2020). Chapter 32 (boilers) and Chapter 13
  (hydronic heating and cooling). <https://www.ashrae.org/technical-resources/ashrae-handbook>
- <a id="r33"></a>**[33]** ANSI/AHRI Standard 1500. *Performance rating of commercial space heating boilers.*
  <https://www.ahrinet.org/search-standards/ahri-1500-i-p-performance-rating-commercial-space-heating-boilers>
- <a id="r34"></a>**[34]** Manufacturer part-load efficiency curves against return-water temperature (for example
  Viessmann Vitocrossal and Buderus SB series), for the condensing-boiler $\eta(T_\text{return})$.

## Solar geometry and irradiance

- <a id="r35"></a>**[35]** Duffie, J.A. and Beckman, W.A. (2013). *Solar Engineering of Thermal Processes*, 4th ed.,
  Wiley. Solar position, angle of incidence (Eq. 1.6.3) and plane-of-array transposition
  (Eq. 2.15.1). DOI: [10.1002/9781118671603](https://doi.org/10.1002/9781118671603)
- <a id="r36"></a>**[36]** Liu, B.Y.H. and Jordan, R.C. (1963). The long-term average performance of flat-plate
  solar-energy collectors. *Solar Energy* 7(2), 53–74. The isotropic sky model.
  DOI: [10.1016/0038-092X(63)90006-9](https://doi.org/10.1016/0038-092X(63)90006-9)
- <a id="r37"></a>**[37]** Perez, R., Ineichen, P., Seals, R., Michalsky, J. and Stewart, R. (1990). Modeling daylight
  availability and irradiance components from direct and global irradiance. *Solar Energy*
  44(5), 271–289. An anisotropic sky model, not implemented.
  DOI: [10.1016/0038-092X(90)90055-H](https://doi.org/10.1016/0038-092X(90)90055-H)

## Ground temperature

- <a id="r38"></a>**[38]** Kusuda, T. and Achenbach, P.R. (1965). Earth temperature and thermal diffusivity at
  selected stations in the United States. *ASHRAE Transactions* 71(1), 61–75. (No DOI.)

## Control

- <a id="r39"></a>**[39]** Åström, K.J. and Hägglund, T. (2006). *Advanced PID Control.* ISA. Parallel form, filtered
  derivative, back-calculation anti-windup, relay feedback and lambda tuning.
  ISBN 978-1-55617-942-6.
- <a id="r40"></a>**[40]** Åström, K.J. and Murray, R.M. (2008). *Feedback Systems: An Introduction for Scientists and
  Engineers.* Princeton University Press. DOI: [10.1515/9781400828739](https://doi.org/10.1515/9781400828739)
- <a id="r41"></a>**[41]** Franklin, G.F., Powell, J.D. and Emami-Naeini, A. (2019). *Feedback Control of Dynamic
  Systems*, 8th ed., Pearson. LQR (Section 7.9), integral control (Section 9.4) and exact
  zero-order-hold discretisation. ISBN 978-0-13-468571-7.
- <a id="r42"></a>**[42]** Anderson, B.D.O. and Moore, J.B. (1990). *Optimal Control: Linear Quadratic Methods.*
  Prentice-Hall; reprinted by Dover (2007), ISBN 978-0-486-45766-6.
- <a id="r43"></a>**[43]** Kristensen, N.R., Madsen, H. and Jørgensen, S.B. (2004). Parameter estimation in stochastic
  grey-box models. *Automatica* 40(2), 225–237.
  DOI: [10.1016/j.automatica.2003.10.001](https://doi.org/10.1016/j.automatica.2003.10.001)

## Related tools

- <a id="r44"></a>**[44]** BRCM Toolbox: Sturzenegger, D., Gyalistras, D., Semeraro, V., Morari, M. and Smith, R.S.
  (2014). BRCM Matlab Toolbox: model generation for model predictive building control. *Proc.
  American Control Conference*, 1063–1069.
  DOI: [10.1109/ACC.2014.6858967](https://doi.org/10.1109/ACC.2014.6858967)
- <a id="r45"></a>**[45]** EnergyPlus. U.S. Department of Energy. <https://energyplus.net>
- <a id="r46"></a>**[46]** Wetter, M., Zuo, W., Nouidui, T.S. and Pang, X. (2014). Modelica Buildings library.
  *Journal of Building Performance Simulation* 7(4), 253–270.
  DOI: [10.1080/19401493.2013.765506](https://doi.org/10.1080/19401493.2013.765506)
- <a id="r47"></a>**[47]** DHNx, district heating network optimisation and simulation. <https://github.com/oemof/DHNx>

## Data sources

- <a id="r48"></a>**[48]** Solcast. Modelled irradiance time series (`solar_data_2025.csv`). <https://solcast.com>
- <a id="r49"></a>**[49]** Environment and Climate Change Canada. Historical climate data,
  <https://climate.weather.gc.ca/>. Station 51117, Kelowna UBCO (climate ID 1123996),
  hourly observations for 2025.
