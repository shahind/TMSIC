classdef (Abstract) Pump < handle
% DHS.HYDRAULIC.PUMP  Abstract circulating pump: the common interface every pump
%                     type in +DHS implements.
%
%   Two concrete kinds ship with the toolbox:
%     DHS.Hydraulic.CentrifugalPump        quadratic head-flow curve + affinity laws
%     DHS.Hydraulic.FixedDisplacementPump  flow set by speed, capped by a relief valve
%
%   One sits at the plant (the central pump, chp.supplyPump) and one on the
%   primary side of each building's heat exchanger (hx.pump). Its speed can be
%   held fixed or driven by a controller:
%       pump.attachController( DHS.controllers.PID(...) )
%
%   HOW THE NETWORK USES A PUMP
%     curveHead(mdot, frac)         central-pump role: the head this pump adds
%                                   at the plant header for a given total network
%                                   flow -- used once, at the network root, in
%                                   DHS.HydraulicNetwork's pressure walk.
%     solveBranch(Kbr, dpAvail, frac)   substation-pump role: given the branch's
%                                   own hydraulic resistance Kbr [Pa/(kg/s)^2] and
%                                   the differential pressure dpAvail already
%                                   available at its tee, return the flow this
%                                   pump settles the branch to. This is where the
%                                   two pump types genuinely differ -- a
%                                   centrifugal pump's curve intersects the branch
%                                   resistance at one point; a fixed-displacement
%                                   pump forces its rated flow unless that would
%                                   need more head than its relief valve allows.
%
%   PROPERTIES (SI)
%     name      char
%     speed     [-]     0..1 speed fraction (control input; default 1)
%     minSpeed  [-]     floor applied to speed                     (0)
%     controller        [] or a DHS.controllers.Controller
%     hostPort          the DHS.Hydraulic.Junction this pump is attached at
%                        (set by chp.attachPump / heatExchanger.attachPump); its
%                        .inlet and .outlet both alias this port, since the
%                        plant and each substation are modelled as one lumped
%                        pressure node -- see DHS.Hydraulic.Pump/inlet.
%   LIVE STATE
%     head      [Pa]    delivered head this step
%     mdot      [kg/s]  flow this step

    properties
        name      (1,:) char = ''
        speed     (1,1) double = 1
        minSpeed  (1,1) double = 0
        controller             = []
        hostPort                = []
    end
    properties (SetAccess = ?DHS.HydraulicNetwork)
        head (1,1) double = 0
        mdot (1,1) double = 0
    end

    methods (Abstract)
        h = curveHead(obj, mdot, frac)
        [m, h] = solveBranch(obj, Kbranch, dpAvailable, frac)
    end

    methods
        function obj = Pump(name, varargin)
            if nargin >= 1, obj.name = name; end
            for i = 1:2:numel(varargin), obj.(varargin{i}) = varargin{i+1}; end
        end

        function attachController(obj, c)
            % ATTACHCONTROLLER  Attach a feedback law that will set obj.speed each step.
            assert(isa(c,'DHS.controllers.Controller'), 'DHS:Pump:ctrl', ...
                'Controller must be a DHS.controllers.Controller.');
            obj.controller = c;
        end

        function j = inlet(obj)
            % INLET  Port-wiring target for a pipe feeding this pump.
            %   The plant and each substation are one lumped pressure node in
            %   this model (their internal pump does not add a separate node),
            %   so inlet and outlet both resolve to obj.hostPort -- see
            %   DHS.CentralHeatPlant.attachPump / DHS.HeatExchanger.attachPump.
            %   A pipe wired end-to-end between a pump's own inlet and outlet
            %   (e.g. a purely illustrative "boiler -> pump" stub) is therefore
            %   wired for the diagram but contributes no resistance of its own.
            j = obj.checkedHostPort();
        end

        function j = outlet(obj)
            % OUTLET  see inlet().
            j = obj.checkedHostPort();
        end
    end

    methods (Access = private)
        function j = checkedHostPort(obj)
            assert(~isempty(obj.hostPort), 'DHS:Pump:noHost', ...
                ['Pump "%s" is not attached to a plant or a heat exchanger yet -- ', ...
                 'use chp.attachPump(pump) or heatExchanger.attachPump(pump) first.'], obj.name);
            j = obj.hostPort;
        end
    end
end
