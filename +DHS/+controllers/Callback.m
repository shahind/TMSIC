classdef Callback < DHS.controllers.Controller
% DHS.CONTROLLERS.CALLBACK  A control law given as a function handle.
%
%   Lets you attach a custom law to a valve, a pump or the burner without
%   writing a class. The handle is called at every control step:
%
%       u = fcn(meas, ref, dt, aux)
%
%     meas : measured process value          ref : setpoint (same units)
%     dt   : step [s]                        aux : struct (aux.x, aux.wx, aux.Tout)
%     u    : command, clamped to [uMin, uMax] (default 0 to 1)
%
%   USAGE
%     c = DHS.controllers.Callback(@(y, r, dt, aux) 0.4*(r - y));
%     hx.valve.attachController(c);
%
%   A law that needs memory can keep it in a variable the handle captures
%   (for example a struct or a handle object). Pass 'resetFcn', @() ... to
%   clear that memory before each run.

    properties
        fcn      function_handle = @(meas, ref, dt, aux) 0
        resetFcn                 = []
    end

    methods
        function obj = Callback(fcn, varargin)
            assert(isa(fcn, 'function_handle'), 'DHS:controllers:Callback:fcn', ...
                'Callback needs a function handle @(meas, ref, dt, aux) -> u.');
            obj.fcn = fcn;
            for i = 1:2:numel(varargin), obj.(varargin{i}) = varargin{i+1}; end
        end

        function reset(obj)
            if ~isempty(obj.resetFcn), obj.resetFcn(); end
        end

        function u = update(obj, meas, ref, dt, aux)
            if nargin < 5, aux = struct(); end
            u = obj.clamp(obj.fcn(meas, ref, dt, aux));
        end
    end
end
