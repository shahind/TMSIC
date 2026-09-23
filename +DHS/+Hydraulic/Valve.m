classdef Valve < handle
% DHS.HYDRAULIC.VALVE  Control valve sized by its flow coefficient Kv.
%
%       Q [m3/h] = Kv * sqrt(dp [bar])      ->  K = 1e5*3600^2 / (Kv^2 * rho^2)
%       Kv(pos)  = Kvs * pos                         ('linear')
%       Kv(pos)  = Kvs * rangeability^(pos-1)        ('eqpct', IEC 60534 default)
%
%   Its position can be held fixed or driven by a controller:
%       valve.attachController( DHS.controllers.PID(...) )
%
%   PROPERTIES (SI)
%     name          char
%     Kvs           [m3/h/sqrt(bar)]  rated flow coefficient (fully open)
%     char          'eqpct' | 'linear'
%     rangeability  [-]   equal-percentage rangeability      (50)
%     KvMinFrac     [-]   floor on pos to avoid div/0        (0.02)
%     pos           [-]   0..1 travel (control input; default 1)
%     controller          [] or a DHS.controllers.Controller
%   LIVE STATE
%     dp            [Pa]  pressure drop this step

    properties
        name         (1,:) char = ''
        Kvs          (1,1) double = 25
        char         (1,:) char = 'eqpct'
        rangeability (1,1) double = 50
        KvMinFrac    (1,1) double = 0.02
        pos          (1,1) double = 1
        controller             = []
    end
    properties (SetAccess = ?DHS.HydraulicNetwork)
        dp (1,1) double = 0
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

        function K = resistance(obj, rho, pos)
            % RESISTANCE  Pa/(kg/s)^2 at travel pos (default obj.pos).
            if nargin < 3, pos = obj.pos; end
            x = min(1, max(0, pos));
            switch lower(obj.char)
                case 'linear', Kv = obj.Kvs * max(x, obj.KvMinFrac);
                case 'eqpct',  Kv = obj.Kvs * obj.rangeability^(max(x,obj.KvMinFrac) - 1);
                otherwise, error('DHS:Valve:char', 'Unknown characteristic "%s".', obj.char);
            end
            K = 1e5 * 3600^2 / (Kv^2 * rho^2);
        end
    end
end
