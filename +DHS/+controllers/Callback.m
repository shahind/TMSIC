classdef Callback < DHS.controllers.Controller
% DHS.CONTROLLERS.CALLBACK  A control law given as a function handle.
%
%   c = DHS.controllers.Callback(@(sys, dt) 0.4*(21 - sys.Hall.Tzone));
%   hx.valve.attachController(c);
%   The handle receives the DHS.System and the step [s] and returns the command, limited to
%   [uMin, uMax]. A law that needs memory can capture a variable; 'resetFcn', @() ... clears it
%   before each run. See docs/dhs-controllers.md.

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
