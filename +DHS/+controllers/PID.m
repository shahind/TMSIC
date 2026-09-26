classdef PID < DHS.controllers.Controller
% DHS.CONTROLLERS.PID  Discrete PID with filtered derivative and anti-windup.
%
%   Parallel form   u = Kp*e + Ki*Int(e) + Kd*d/dt(e_filt) ,  e = dir*(ref-meas)
%
%   Discretisation (step dt):
%     I    += Ki*e*dt
%     d_f  += (dt/Tf)*((e-e_prev)/dt - d_f)          (Tf > 0)
%     u_raw = Kp*e + I + Kd*d_f
%     u     = clamp(u_raw, uMin, uMax)
%     I    += (dt/Tt)*(u - u_raw)                     (back-calculation anti-windup)
%
%   CONSTRUCTION
%     PID(Kp, Ki, Kd)                positional (Tf defaults to 20 s)
%     PID(Kp, Ki, Kd, Tf)           positional with derivative filter
%     PID('Kp',..,'Ki',..,'Kd',..,'Tf',..,'Tt',..,'dir',..,'uMin',..,'uMax',..,'name',..)
%
%   Example:  c = DHS.controllers.PID(0.14, 1.6e-4, 0);

    properties
        Kp  (1,1) double = 1
        Ki  (1,1) double = 0
        Kd  (1,1) double = 0
        Tf  (1,1) double = 20      % derivative filter time constant [s]
        Tt  (1,1) double = NaN     % anti-windup tracking time [s]; NaN => auto
        dir (1,1) double = 1       % +1 direct acting, -1 reverse acting
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

        function u = update(obj, meas, ref, dt, ~)
            if dt <= 0, error('DHS:controllers:PID:dt', 'dt must be > 0.'); end
            e = obj.dir * (ref - meas);
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
end
