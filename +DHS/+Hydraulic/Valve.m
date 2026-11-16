classdef Valve < DHS.Hydraulic.Link
% DHS.HYDRAULIC.VALVE  A control valve sized by its flow coefficient Kv (IEC 60534).
%
%   valve = DHS.Hydraulic.Valve('V1', 'Kvs',18, 'char','eqpct');    % or pipe.addValve('Kvs',18)
%   Q [m3/h] = Kv*sqrt(dp [bar]); Kv = Kvs*pos ('linear') or Kvs*rangeability^(pos-1) ('eqpct').
%   pos [0..1] is the command. The valve follows it with a first-order lag of time constant lag [s]
%   (default 60; 0 = none), and the flow uses posActual. Attach a controller with valve.attachController(c).
%   Kvs [m3/h/sqrt(bar)] (25), rangeability (50), minPos (0.02). A valve joined from the supply side to a
%   return junction is a bypass. See docs/dhs-hydraulic.md.

    properties
        name         (1,:) char = ''
        Kvs          (1,1) double = 25
        char         (1,:) char = 'eqpct'
        rangeability (1,1) double = 50
        minPos    (1,1) double = 0.02
        pos          (1,1) double = 1
        lag          (1,1) double {mustBeNonnegative} = 60
        controller             = []
    end
    properties (SetAccess = private)
        posActual    (1,1) double = 1
    end
    properties (Access = private)
        running (1,1) logical = false
    end
    properties (SetAccess = {?DHS.HydraulicNetwork, ?DHS.Building, ?DHS.Radiator})
        dp (1,1) double = 0
    end
    properties (SetAccess = private)
        mdot (1,1) double = 0
        Tin  (1,1) double = NaN
        Tout (1,1) double = NaN
    end

    methods
        function obj = Valve(name, varargin)
            if nargin >= 1, obj.name = name; end
            for i = 1:2:numel(varargin), obj.(varargin{i}) = varargin{i+1}; end
        end

        function attachController(obj, c)
            % ATTACHCONTROLLER  Attach a feedback law that will set obj.pos each step.
            assert(isa(c,'DHS.controllers.Controller'), 'DHS:Valve:ctrl', ...
                'Controller must be a DHS.controllers.Controller.');
            obj.controller = c;
        end

        function beginRun(obj)
            % BEGINRUN  Start of a run: the valve is at its command and the lag applies from here on.
            obj.running = true;  obj.posActual = obj.pos;
        end

        function endRun(obj)
            obj.running = false;
        end

        function advance(obj, dt)
            % ADVANCE  Move the actual position toward the command over a step dt [s] (first-order lag).
            if ~obj.running, return, end
            if obj.lag <= 0
                obj.posActual = obj.pos;
            else
                obj.posActual = obj.posActual + (1 - exp(-dt/obj.lag)) * (obj.pos - obj.posActual);
            end
        end

        function p = position(obj)
            % POSITION  The travel the flow equation uses: posActual during a run, else the command.
            if obj.running && obj.lag > 0, p = obj.posActual; else, p = obj.pos; end
        end

        function [K, H] = linkLoss(obj, mdot, rho, mu) %#ok<INUSD>
            % LINKLOSS  As a link of a network the valve loses K*mdot^2 (K from its position) and gains no head.
            K = obj.resistance(rho);  H = 0;
            if ~isempty(obj.teeSide) && isa(obj.nodeA, 'DHS.Hydraulic.TJunction')
                K = K + obj.nodeA.teeLossK(obj.teeSide, rho, mu, mdot);
            end
        end

        function setFlow(obj, Q, dp, rho) %#ok<INUSD>
            % SETFLOW  Store the solved flow and pressure drop.
            obj.mdot = Q;  obj.dp = dp;
        end

        function [Tout, Qloss] = outletTemperature(obj, Tin, ~, ~, ~)
            % OUTLETTEMPERATURE  The water passes through unchanged.
            Tout = Tin;  Qloss = 0;  obj.Tin = Tin;  obj.Tout = Tout;
        end

        function K = resistance(obj, rho, pos)
            % RESISTANCE  Pa/(kg/s)^2 at travel pos (default: the position the valve has reached).
            if nargin < 3, pos = obj.position(); end
            x = min(1, max(0, pos));
            switch lower(obj.char)
                case 'linear', Kv = obj.Kvs * max(x, obj.minPos);
                case 'eqpct',  Kv = obj.Kvs * obj.rangeability^(max(x,obj.minPos) - 1);
                otherwise, error('DHS:Valve:char', 'Unknown characteristic "%s".', obj.char);
            end
            K = 1e5 * 3600^2 / (Kv^2 * rho^2);
        end
    end

    methods (Static)
        function Kvs = kvsFor(mdot, dp, rho)
            % KVSFOR  Rated Kv [m3/h/sqrt(bar)] that passes MDOT [kg/s] at the pressure drop DP [Pa] fully open.
            %   Kvs = DHS.Hydraulic.Valve.kvsFor(0.5, 5e3, 983)
            if nargin < 3, rho = 983; end
            Kvs = (mdot/rho*3600) / sqrt(dp/1e5);
        end
    end
end
