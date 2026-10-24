classdef Controller < handle
% DHS.CONTROLLERS.CONTROLLER  Abstract control law: the general form every controller follows.
%
%   Every controllable actuator in a DHS system (a building's valve, a pump, a
%   boiler's burner, the bypass valve) is driven by an object derived from this
%   class and attached with one call:
%
%       actuator.attachController(c)
%
%   At every step the actuator asks its controller for a command, passing the
%   whole simulation:
%
%       u = c.update(sys, dt)
%
%     sys : the DHS.System being run. The controller reads whatever it needs
%           from it (building temperatures, junction pressures, weather,
%           sys.time, ...) and decides what to measure and how.
%     dt  : step [s], greater than zero.
%     u   : command, clamped to [uMin, uMax] (default 0 to 1). Zero means shut,
%           stopped or no firing, one means fully open, full speed or full firing.
%
%   Each law carries its own parameters as properties: a PID its gains, measure
%   and reference; a Relay its band, measure and reference; an LQR its model, Q, R
%   and the state it regulates. The base class holds only the command limits and
%   a label.
%
%   Shipped laws: PID, LQR, Relay and Callback (a function handle). A law of your
%   own subclasses Controller and implements reset() and update(sys, dt).

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
