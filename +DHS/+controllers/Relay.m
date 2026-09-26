classdef Relay < DHS.controllers.Controller
% DHS.CONTROLLERS.RELAY  On/off (bang-bang) controller with symmetric hysteresis.
%
%     e = dir*(ref - meas)
%     u = uMax   if e > +h        (call for heat)
%     u = uMin   if e < -h        (stop)
%     u = hold   otherwise        (inside the deadband)
%
%   Construction:  Relay(h)  or  Relay('h',..,'dir',..,'uMin',..,'uMax',..)

    properties
        h   (1,1) double = 0.5
        dir (1,1) double = 1
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

        function u = update(obj, meas, ref, ~, ~)
            e = obj.dir * (ref - meas);
            if     e >  obj.h, u = obj.uMax;
            elseif e < -obj.h, u = obj.uMin;
            else,              u = obj.uLast;
            end
            obj.uLast = u;
        end
    end
end
