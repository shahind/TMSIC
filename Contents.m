% Thermal Modeling for System Identification and Control Toolbox
% Version 1.0
%
% Pure-MATLAB RC thermal modelling of buildings, district heating system
% assembly, grey-box parameter identification, and controller design.
%
% RC building models (+RCBS)
%   RCBS.Building      - a building: storeys, zones, envelope elements, couplings
%   RCBS.Storey        - a storey holding zones
%   RCBS.Zone          - a thermal zone: air node, walls, roof, windows,
%                        internal mass, connectToZone couplings, heat sources
%   RCBS.Simulation    - the solver: stepOnce, simulate, getStateSpace
%
% District heating systems (+DHS)
%   DHS.System             - the top object: plant + network + buildings, run()
%   DHS.CentralHeatPlant   - boilers, pump, plant-side water dynamics, firing PID
%   DHS.Boiler             - a burner stage in the plant
%   DHS.HeatExchanger      - substation plate heat exchanger (eps-NTU) + valve + pump
%   DHS.Hydraulic.Pipe / .Junction / .TJunction / .Valve  - pipe-network parts
%   DHS.Hydraulic.Pump / .CentrifugalPump / .FixedDisplacementPump - pump types
%   DHS.HydraulicNetwork   - trunk-and-branch pipe-network solver
%   DHS.Building            - one building on the loop, wraps an RCBS.Building
%   DHS.Weather / DHS.Solar / DHS.Schedule - boundary conditions and gains
%   DHS.drawSchematic      - draw an assembled system
%
% Controllers (+DHS/+controllers)
%   DHS.controllers.Controller - abstract interface (reset, update)
%   DHS.controllers.PID        - discrete PID, filtered derivative, anti-windup
%   DHS.controllers.LQR        - integral-augmented discrete LQR
%   DHS.controllers.Relay      - on/off
%   DHS.controllers.Callback   - a custom law given as a function handle
%
% Examples (examples/)
%   RCBS_example                    - build a 7-zone building, draw its schematic
%   dhs_campus                      - assemble and run a 5-building campus
%   dhs_campus_multizone            - the campus with multi-zone buildings
%   system_identification           - fit a single-zone RC model to data
%   multi_zone_system_identification - fit an 8-zone building to data
%
% Tests and validation
%   runtests('tests')                    - unit / regression suites
%   run('validation/run_all_validation') - 18 component accuracy checks
%
% Run setup.m once per session to put the toolbox on the MATLAB path.
