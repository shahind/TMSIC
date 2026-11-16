classdef PID < DHS.controllers.Controller
% DHS.CONTROLLERS.PID  Discrete PID with a filtered derivative and back-calculation anti-windup.
%
%   c = DHS.controllers.PID(0.14, 1.6e-4, 0);            % Kp, Ki, Kd (Tf defaults to 20 s)
%   c = DHS.controllers.PID(Kp, Ki, Kd, Tf);              % with a derivative filter time constant [s]
%   c = DHS.controllers.PID('Kp',..,'Ki',..,'Kd',..,'Tf',..,'Tt',..,'dir',..,'uMin',..,'uMax',..);
%   c.measure   = @(sys) sys.Hall.Tzone;                  % the measured value
%   c.reference = @(sys) sys.Hall.setpoint;               % a number or @(sys) ...
%   hx.valve.attachController(c);
%
%   u = Kp*e + I + Kd*de_filtered/dt with e = dir*(reference - measure); dir is +1 (direct) or -1 (reverse).
%   Tt is the anti-windup time constant (chosen automatically). See docs/dhs-controllers.md.

    properties
        Kp  (1,1) double = 1
        Ki  (1,1) double = 0
        Kd  (1,1) double = 0
        Tf  (1,1) double = 20      % derivative filter time constant [s]
        Tt  (1,1) double = NaN     % anti-windup tracking time [s]; NaN => auto
        dir (1,1) double = 1       % +1 direct acting, -1 reverse acting
        measure   = []             % @(sys) -> the measured value
        reference = []             % a number, or @(sys) -> the setpoint
    end
    properties (Access = private)
        Iterm (1,1) double = 0
        ePrev (1,1) double = 0
        dFilt (1,1) double = 0
        started (1,1) logical = false
    end

    methods
        function obj = PID(varargin)
            if nargin >= 1 && isnumeric(varargin{1})
                % positional: Kp, Ki, Kd [, Tf]
                p = [varargin{:}];
                if numel(p) >= 1, obj.Kp = p(1); end
                if numel(p) >= 2, obj.Ki = p(2); end
                if numel(p) >= 3, obj.Kd = p(3); end
                if numel(p) >= 4, obj.Tf = p(4); end
            else
                for i = 1:2:numel(varargin)
                    obj.(varargin{i}) = varargin{i+1};
                end
            end
            obj.reset();
        end

        function reset(obj)
            obj.Iterm = 0; obj.ePrev = 0; obj.dFilt = 0; obj.started = false;
        end

        function u = update(obj, sys, dt)
            if dt <= 0, error('DHS:controllers:PID:dt', 'dt must be > 0.'); end
            e = obj.dir * (obj.readReference(sys) - obj.readMeasure(sys));
            if ~obj.started, obj.ePrev = e; obj.started = true; end

            dterm = 0;
            if obj.Kd ~= 0
                dRaw = (e - obj.ePrev) / dt;
                if obj.Tf > 0
                    obj.dFilt = obj.dFilt + (dt/obj.Tf)*(dRaw - obj.dFilt);
                else
                    obj.dFilt = dRaw;
                end
                dterm = obj.Kd * obj.dFilt;
            end

            Iprov = obj.Iterm + obj.Ki * e * dt;
            uRaw  = obj.Kp * e + Iprov + dterm;
            u     = obj.clamp(uRaw);

            if obj.Ki ~= 0
                Tt_ = obj.Tt;
                if ~isfinite(Tt_) || Tt_ <= 0
                    Ti = obj.Kp / obj.Ki;
                    if obj.Kd ~= 0 && obj.Kp ~= 0
                        Tt_ = sqrt(max(Ti,eps) * max(obj.Kd/obj.Kp, eps));
                    else
                        Tt_ = max(Ti, dt);
                    end
                end
                obj.Iterm = Iprov + (dt/Tt_) * (u - uRaw);
            else
                obj.Iterm = Iprov;
            end
            obj.ePrev = e;
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
