classdef Controller < handle
% DHS.CONTROLLERS.CONTROLLER  Abstract control law. Every actuator (a valve, a pump, a boiler) takes one:
%
%   actuator.attachController(c)
%   u = c.update(sys, dt)       % sys is the DHS.System, dt the step [s]; u is limited to [uMin, uMax]
%
%   The law decides what to measure by reading sys, for example @(sys) sys.Hall.Tzone. Shipped laws:
%   PID, LQR, Relay and Callback. A law of your own subclasses Controller and implements reset() and
%   update(sys, dt); use obj.clamp(u) to limit the command. uMin 0, uMax 1, name (a label).
%   See docs/dhs-controllers.md.

    properties
        uMin (1,1) double = 0
        uMax (1,1) double = 1
        name (1,:) char   = ''
    end

    methods (Abstract)
        reset(obj)
        u = update(obj, sys, dt)
    end

    methods
        function u = clamp(obj, u)
            u = min(obj.uMax, max(obj.uMin, u));
        end
    end
end
