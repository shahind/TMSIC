classdef (Abstract) Pump < DHS.Hydraulic.Link
% DHS.HYDRAULIC.PUMP  Abstract pump: the interface of CentrifugalPump and FixedDisplacementPump.
%
%   The central pump is chp.supplyPump and a building's booster pump is hx.pump. A pump can also sit in
%   line between two nodes: pipe.addPump('dp0',5e4, 'mdotRated',1.5).
%   speed [0..1] is the fraction of nMax [rpm] (2900); rpm reads and writes it in rpm; minSpeed is a floor.
%   A stopped substation pump (speed 0) adds no head and no resistance.
%   curveHead(mdot, frac) gives the head at the plant header and solveBranch(K, dpAvail, frac) the flow
%   and head on a branch. pump.attachController(c) drives speed. Live: head, mdot.
%   See docs/dhs-hydraulic.md.

    properties
        name      (1,:) char = ''
        speed     (1,1) double = 1
        nMax      (1,1) double = 2900
        minSpeed  (1,1) double = 0
        controller             = []
        hostPort                = []
    end
    properties (SetAccess = {?DHS.HydraulicNetwork, ?DHS.Building, ?DHS.Radiator, ?DHS.Hydraulic.Pump})
        head (1,1) double = 0
        mdot (1,1) double = 0
    end
    properties (SetAccess = private)
        Tin  (1,1) double = NaN
        Tout (1,1) double = NaN
        Qloss (1,1) double = 0
        dp   (1,1) double = 0
    end
    properties (Dependent)
        rpm                                  % rotational speed [rpm] = speed * nMax
    end

    methods (Abstract)
        h = curveHead(obj, mdot, frac)
        [m, h] = solveBranch(obj, Kbranch, dpAvailable, frac)
        [K, H] = inlineCurve(obj)
    end

    methods
        function v = get.rpm(obj),  v = obj.speed * obj.nMax; end
        function set.rpm(obj, v),   obj.speed = v / obj.nMax; end

        function [K, H] = linkLoss(obj, mdot, rho, mu) %#ok<INUSD>
            % LINKLOSS  The pump as a link: head gain H and internal loss K mdot^2 at its speed.
            [K, H] = obj.inlineCurve();
            if obj.speed <= 0, K = 0;  H = 0; end                % stopped: bypassed, no head and no resistance
        end

        function setFlow(obj, Q, dp, rho) %#ok<INUSD>
            % SETFLOW  Store the solved flow and the pressure change across the pump.
            obj.mdot = Q;  obj.dp = dp;  obj.head = -dp;
        end

        function [Tout, Qloss] = outletTemperature(obj, Tin, Tground, mdot, cp) %#ok<INUSD>
            % OUTLETTEMPERATURE  The water passes through unchanged (pump heat is ignored).
            Tout = Tin;  Qloss = 0;
            obj.Tin = Tin;  obj.Tout = Tout;  obj.Qloss = 0;
        end

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
            % INLET  Wiring target for a pipe feeding this pump.
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
