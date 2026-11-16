% Thermal Modeling for System Identification and Control Toolbox (TMSIC)
% Version 1.0
%
% RC models of buildings, district heating systems, parameter identification and
% controller design. Run setup once per session to put the toolbox on the path.
%
% Building thermal models (+RCBS)
%   RCBS.Building       - a building: storeys, zones, envelope elements, couplings
%   RCBS.Storey         - a storey that holds zones
%   RCBS.Zone           - a zone: air node, walls, roof, windows, internal mass, zone links, heat sources
%   RCBS.Part           - a named element of a zone (R, C, T)
%   RCBS.Simulation     - the solver: run, stepOnce, getStateSpace
%
% District heating (+DHS)
%   DHS.System                         - plant + network + buildings; run
%   DHS.CentralHeatPlant               - boilers, central pump, plant water, firing control
%   DHS.Boiler                         - a burner stage
%   DHS.HydraulicNetwork               - supply and return pipe trees and the flow solver
%   DHS.Building                       - a building on the network; wraps an RCBS.Building
%   DHS.Radiator                       - a zone radiator on a building's internal loop
%   DHS.HeatExchanger                  - abstract substation exchanger with valve and pump
%   DHS.ENTUPlateHeatExchanger         - plate exchanger, effectiveness-NTU (building with a loop)
%   DHS.FixedEffectivenessHeatExchanger - fixed effectiveness (building with a loop)
%   DHS.IdealHeatExchanger             - radiator law (building without a loop)
%   DHS.Weather, DHS.Solar, DHS.Schedule - weather, solar gains, occupancy
%
% Network parts (+DHS/+Hydraulic)
%   Pipe, Valve, Pump, CentrifugalPump, FixedDisplacementPump  - links, joined with connect or add...
%   Junction, TJunction                                       - nodes (a tee has ports portA, portB, portC)
%
% Controllers (+DHS/+controllers)
%   Controller, PID, LQR, Relay, Callback  - attach with actuator.attachController(c)
%
% Examples (examples/)
%   rcbs_tutorial, dhs_tutorial, dhs_internal_loop_tutorial
%   RCBS_example, dhs_campus, dhs_campus_with_bypass, dhs_campus_multizone
%   system_identification, multi_zone_system_identification
%
% Tests and validation
%   runtests('tests')    - unit tests
%   run_all_validation   - 20 component accuracy checks
%
% AI assistants
%   install_ai_skill     - install the skill in skills/ for Claude Code, Codex or Claude.ai
