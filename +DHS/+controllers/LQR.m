classdef LQR < DHS.controllers.Controller
% DHS.CONTROLLERS.LQR  Discrete linear-quadratic regulator u = -K x for one input.
%
%   c = DHS.controllers.LQR(A, B, Q, R, Ts)
%   A, B: continuous model dx/dt = A x + B u (B a single column); Q: state weight (n x n, or a vector for
%   its diagonal); R: input weight; Ts: sample time [s] (60). K comes from dlqr on the zero-order-hold model.
%   c.state = @(sys) x       the state to drive to zero; return x = x_real - x_ref to hold a setpoint
%   c.uScale                 the input value that corresponds to u = 1 (for example heat in W)
%   c.K                      the gain (read only)
%   There is no integral action. Needs the Control System Toolbox. See docs/dhs-controllers.md.

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
