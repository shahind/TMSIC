classdef LQR < DHS.controllers.Controller
% DHS.CONTROLLERS.LQR  Discrete linear-quadratic regulator  u = -K x.
%
%   The standard regulator. Given a continuous model  dx/dt = A x + B u  with one
%   input, weights Q (states) and R (input), and the sample time Ts, the gain is
%
%       K = dlqr(Ad, Bd, Q, R)       (Ad, Bd: zero-order-hold discretisation at Ts)
%
%   and each step the law returns  u = clamp( -K x / uScale ).
%
%   CONSTRUCTION
%     c = DHS.controllers.LQR(A, B, Q, R, Ts)
%       A, B    continuous model, B a single column (n x 1)
%       Q       state weight, n x n (a vector is taken as its diagonal)
%       R       input weight, scalar
%       Ts      sample time [s] (default 60)
%
%   PROPERTIES  (set them like the gains of a PID; K is redesigned when any change)
%     A B Q R Ts   the design data above
%     K            gain 1 x n (read-only, from dlqr)
%     state        @(sys) -> x, the state vector the regulator drives to zero
%     uScale       input value that corresponds to u = 1 (default 1), for example
%                  the heat [W] at full valve opening
%
%   There is no reference and no integral state: the regulator takes x to zero.
%   To hold a setpoint, return the error from state, x = x_real - x_ref; for
%   offset-free tracking against constant disturbances, augment A, B, Q with an
%   integral state and return it in x as well.
%
%   EXAMPLE
%     [sysc, io] = building.rcBuilding.simulation.getStateSpace();
%     r  = io.zoneMainRows(1);
%     c  = DHS.controllers.LQR(sysc.A, sysc.B(:, r+1), diag(q), 1e-9, 60);
%     c.uScale = hx.Qcap;
%     c.state  = @(sys) building.rcBuilding.simulation.Tnow - building.setpoint;
%     hx.valve.attachController(c);
%
%   Needs the Control System Toolbox (c2d, dlqr).

    properties
        A  (:,:) double = []
        B  (:,1) double = []
        Q  (:,:) double = []
        R  (1,1) double = 1
        Ts (1,1) double = 60
        state            = []
        uScale (1,1) double = 1
    end
    properties (Dependent, SetAccess = private)
        K
    end
    properties (Access = private)
        Kcache = []
    end

    methods
        function obj = LQR(A, B, Q, R, Ts)
            if nargin >= 1, obj.A = A; end
            if nargin >= 2, obj.B = B; end
            if nargin >= 3, obj.Q = Q; end
            if nargin >= 4, obj.R = R; end
            if nargin >= 5, obj.Ts = Ts; end
        end

        function set.A(obj, v),  obj.A  = v;  obj.Kcache = []; end
        function set.B(obj, v),  obj.B  = v;  obj.Kcache = []; end
        function set.Q(obj, v)
            if isvector(v), v = diag(v); end
            obj.Q = v;  obj.Kcache = [];
        end
        function set.R(obj, v),  obj.R  = v;  obj.Kcache = []; end
        function set.Ts(obj, v), obj.Ts = v;  obj.Kcache = []; end

        function k = get.K(obj)
            if isempty(obj.Kcache), obj.Kcache = obj.design(); end
            k = obj.Kcache;
        end

        function reset(~)
            % memoryless: nothing to clear
        end

        function u = update(obj, sys, ~)
            if ~isa(obj.state, 'function_handle')
                error('DHS:controllers:LQR:noState', ...
                    'LQR "%s" has no state; set c.state = @(sys) x', obj.name);
            end
            x = obj.state(sys);  x = x(:);
            if numel(x) ~= size(obj.A, 1)
                error('DHS:controllers:LQR:stateSize', ...
                    'state returned %d entries, the model has %d states.', numel(x), size(obj.A, 1));
            end
            u = obj.clamp(-obj.K * x / obj.uScale);
        end
    end

    methods (Access = private)
        function k = design(obj)
            n = size(obj.A, 1);
            assert(n > 0 && isequal(size(obj.Q), [n n]) && numel(obj.B) == n, 'DHS:controllers:LQR:model', ...
                'LQR needs A (n x n), B (n x 1) and Q (n x n).');
            sd = c2d(ss(obj.A, obj.B, eye(n), 0), obj.Ts, 'zoh');
            k  = dlqr(sd.A, sd.B, obj.Q, obj.R);
        end
    end
end
