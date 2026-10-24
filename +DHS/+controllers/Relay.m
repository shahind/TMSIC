classdef Relay < DHS.controllers.Controller
% DHS.CONTROLLERS.RELAY  On/off (bang-bang) controller with symmetric hysteresis.
%
%     e = dir*(ref - meas)
%     u = uMax   if e > +h        (call for heat)
%     u = uMin   if e < -h        (stop)
%     u = hold   otherwise        (inside the deadband)
%
%   with ref = c.reference and meas = c.measure(sys).
%   Construction:  Relay(h)  or  Relay('h',..,'dir',..,'uMin',..,'uMax',..)

    properties
        h   (1,1) double = 0.5
        dir (1,1) double = 1
        measure   = []             % @(sys) -> the measured value
        reference = []             % a number, or @(sys) -> the setpoint
    end
    properties (Access = private)
        uLast (1,1) double = 0
    end

    methods
        function obj = Relay(varargin)
            if nargin >= 1 && isnumeric(varargin{1})
                obj.h = varargin{1};
            else
                for i = 1:2:numel(varargin), obj.(varargin{i}) = varargin{i+1}; end
            end
            obj.reset();
        end

        function reset(obj)
            obj.uLast = obj.uMin;
        end

        function u = update(obj, sys, ~)
            e = obj.dir * (obj.readReference(sys) - obj.readMeasure(sys));
            if     e >  obj.h, u = obj.uMax;
            elseif e < -obj.h, u = obj.uMin;
            else,              u = obj.uLast;
            end
            obj.uLast = u;
        end
    end

    methods (Access = private)
        function y = readMeasure(obj, sys)
            if ~isa(obj.measure, 'function_handle')
                error('DHS:controllers:noMeasure', ...
                    'Controller "%s" has no measure; set c.measure = @(sys) ...', obj.name);
            end
            y = obj.measure(sys);
        end

        function r = readReference(obj, sys)
            r = obj.reference;
            if isa(r, 'function_handle'), r = r(sys); end
            if isempty(r)
                error('DHS:controllers:noReference', ...
                    'Controller "%s" has no reference; set c.reference = number or @(sys) ...', obj.name);
            end
        end
    end
end
