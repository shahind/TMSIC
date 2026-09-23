classdef LQR < DHS.controllers.Controller
% DHS.CONTROLLERS.LQR  Integral-augmented discrete LQR for zone-temperature tracking.
%
%   A model-based drop-in replacement for DHS.controllers.PID on a building's
%   valve/pump loop. It uses that building's own linearised state-space model
%   (RCBS.Simulation.getStateSpace) with full-state feedback plus an integral
%   state for offset-free setpoint tracking.
%
%   PLANT (continuous, from getStateSpace):
%       dx/dt = A x + Bu*Qh + Bd*d ,   y = Cy x        (y = zone air temp [degC])
%
%   AUGMENTED DESIGN:
%       xi_{k+1} = xi_k + Ts*(r - y)
%       K = dlqr(Ad_aug, Bd_aug, Q, R)  at sample time Ts
%       Qh = -Kx*(x - r) - Ki*xi                       (Watts)
%       u  = clamp( Qh / uMaxW , 0, 1 )
%   with conditional anti-windup on xi when u saturates.
%
%   Refs: Anderson & Moore (1990); Franklin, Powell & Emami-Naeini (2019) Sec.7.9, 9.
%
%   USAGE
%     [sysc, io] = building.rcBuilding.simulation.getStateSpace();
%     c = DHS.controllers.LQR(sysc, struct('io',io,'Ts',60,'uMaxW',8e5, ...
%                             'qZone',6e3,'qInt',8e-2,'R',1e-9));
%     u = c.update(T_zone, T_setpoint, 60, struct('x', building.rcBuilding.simulation.Tnow));
%
%   aux.x (full node-temperature vector) is REQUIRED.

    properties
        Kx    (1,:) double = []
        Ki    (1,1) double = 0
        uMaxW (1,1) double = 1e5
        Ts    (1,1) double = 60
        yRow  (1,1) double = 1
    end
    properties (Access = private)
        xi (1,1) double = 0
        nx (1,1) double = 0
    end

    methods
        function obj = LQR(sysc, opts)
            if nargin < 2, opts = struct(); end
            g = @(f,d) DHS.controllers.LQR.getf(opts, f, d);

            Ts_    = g('Ts',    60);
            uMaxW_ = g('uMaxW', 1e5);
            qZone  = g('qZone', 4e3);
            qOther = g('qOther',1e0);
            qInt   = g('qInt',  5e-2);
            Rw     = g('R',     1e-9);

            A = sysc.A; B = sysc.B; nx = size(A,1);
            if isfield(opts,'yRow')
                yR = opts.yRow;
            elseif isfield(opts,'io') && isfield(opts.io,'zoneMainRows')
                yR = opts.io.zoneMainRows(1);
            else
                yR = 1;
            end
            if isfield(opts,'uCol'), uC = opts.uCol; else, uC = yR + 1; end

            Bu = B(:, uC);
            Cy = zeros(1, nx); Cy(yR) = 1;
            Aa = [A, zeros(nx,1); -Cy, 0];
            Ba = [Bu; 0];
            sysd = c2d(ss(Aa, Ba, eye(nx+1), 0), Ts_, 'zoh');
            Qd = diag([repmat(qOther,1,nx), qInt]);
            Qd(yR,yR) = qZone;
            Kd = dlqr(sysd.A, sysd.B, Qd, Rw);

            obj.Kx = Kd(1:nx);  obj.Ki = Kd(nx+1);
            obj.uMaxW = uMaxW_;  obj.Ts = Ts_;  obj.yRow = yR;  obj.nx = nx;
            obj.reset();
        end

        function reset(obj), obj.xi = 0; end

        function u = update(obj, meas, ref, dt, aux)
            if nargin < 5 || ~isstruct(aux) || ~isfield(aux,'x')
                error('DHS:controllers:LQR:noState', ...
                    'LQR.update requires aux.x (full node-temperature vector).');
            end
            x = aux.x(:);
            if numel(x) ~= obj.nx
                error('DHS:controllers:LQR:stateSize', ...
                    'aux.x has %d entries, model has %d states.', numel(x), obj.nx);
            end
            xiTrial = obj.xi + (ref - meas) * dt;
            Qh   = -obj.Kx * (x - ref) - obj.Ki * xiTrial;
            uRaw = Qh / obj.uMaxW;
            u    = obj.clamp(uRaw);
            if u == uRaw, obj.xi = xiTrial; end
        end
    end

    methods (Static, Access = private)
        function v = getf(s, f, d)
            if isfield(s, f), v = s.(f); else, v = d; end
        end
    end
end
