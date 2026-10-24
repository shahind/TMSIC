classdef Callback < DHS.controllers.Controller
% DHS.CONTROLLERS.CALLBACK  A control law given as a function handle.
%
%   Lets you attach a custom law to any actuator without writing a class. The
%   handle gets the whole simulation, like every controller, and returns the command:
%
%       u = fcn(sys, dt)
%
%     sys : the DHS.System (read what you need from it)     dt : step [s]
%     u   : command, clamped to [uMin, uMax] (default 0 to 1)
%
%   USAGE
%     c = DHS.controllers.Callback(@(sys, dt) 0.4*(21 - building.Tzone));
%     hx.valve.attachController(c);
%
%     bypass valve held at a constant position:
%     network.bypassValve.attachController( DHS.controllers.Callback(@(sys, dt) 0.5) );
%
%   A law that needs memory can keep it in a variable the handle captures
%   (for example a struct or a handle object). Pass 'resetFcn', @() ... to
%   clear that memory before each run.

    properties
        fcn      function_handle = @(sys, dt) 0
        resetFcn                 = []
    end

    methods
        function obj = Callback(fcn, varargin)
            assert(isa(fcn, 'function_handle'), 'DHS:controllers:Callback:fcn', ...
                'Callback needs a function handle @(sys, dt) -> u.');
            obj.fcn = fcn;
            for i = 1:2:numel(varargin), obj.(varargin{i}) = varargin{i+1}; end
        end

        function reset(obj)
            if ~isempty(obj.resetFcn), obj.resetFcn(); end
        end

        function u = update(obj, sys, dt)
            u = obj.clamp(obj.fcn(sys, dt));
        end
    end
end
