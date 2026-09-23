classdef Controller < handle
% DHS.CONTROLLERS.CONTROLLER  Abstract single-input / single-output feedback law.
%
%   Every controllable actuator in a DHS system (a valve, a pump, the plant
%   firing) is driven by one of these. Swapping PID -> LQR -> your MPC is done by
%   handing a different Controller subclass to  actuator.attachController(c) ; the
%   rest of the model does not change.
%
%   CONTRACT
%     reset(obj)                         clear internal state before a run
%     u = update(obj, meas, ref, dt)     one control step
%     u = update(obj, meas, ref, dt, aux)  optional 5th arg for model-based laws
%
%     meas : measured process value        (scalar, SI units of the loop)
%     ref  : setpoint                       (scalar, same units as meas)
%     dt   : controller sample time         [s], > 0
%     aux  : struct, optional. LQR / MPC read fields such as aux.x (full plant
%            state vector), aux.wx (weather), aux.Tout. PID / Relay ignore it.
%     u    : command, normalised to [0,1] for actuators in this project
%            (0 = shut / no firing, 1 = fully open / max firing); clamped to
%            [obj.uMin, obj.uMax].

    properties
        uMin (1,1) double = 0
        uMax (1,1) double = 1
        name (1,:) char   = ''
    end

    methods (Abstract)
        reset(obj)
        u = update(obj, meas, ref, dt, varargin)
    end

    methods
        function u = clamp(obj, u)
            u = min(obj.uMax, max(obj.uMin, u));
        end
    end
end
