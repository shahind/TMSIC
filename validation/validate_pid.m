function V = validate_pid(plotMode)
%VALIDATE_PID  Discrete PID vs an analytically known closed-loop response.
%
%   COMPONENT      DHS.controllers.PID (parallel form, filtered derivative,
%                  back-calculation anti-windup)
%
%   TEST CASE + REFERENCE
%     Plant:  first-order  G(s) = K/(tau s + 1)  (an RC zone: dT/dt = (-T + K u)/tau).
%     PI controller tuned by INTERNAL MODEL CONTROL / lambda tuning:
%         Ti = tau ,   Kp = tau / (K * lambda)
%     With Ti = tau the controller zero cancels the plant pole, and the
%     closed-loop transfer function is EXACTLY first order:
%         y(s)/r(s) = 1 / (lambda s + 1)
%     so a unit step reference gives  y(t) = 1 - exp(-t/lambda)  with zero
%     steady-state error (integral action).
%
%   Sub-cases:
%     A  step-reference response matches  1 - exp(-t/lambda)   (form, gain, sign)
%     B  steady-state error to a step reference is zero (integral action)
%     C  steady-state error to a constant output disturbance is zero
%     D  anti-windup: after a saturating step the controller comes off the limit
%        promptly once the error changes sign (integrator not wound up)
%
%   WHY THIS TEST IS GOOD
%     The lambda-tuned first-order plant has an exact analytical closed-loop
%     response, so case A simultaneously validates the proportional gain, the
%     integral discretisation, the parallel-form assembly and the loop sign.
%     B and C validate the integrator; D validates the back-calculation
%     anti-windup that keeps the plant loops well-behaved at saturation.
%
%   EXPECTED OUTPUT
%     A  max |y - (1 - exp(-t/lambda))| < 0.01 over the transient (dt small)
%     B, C  |steady-state error| < 1e-3
%     D  controller leaves the upper limit within a few samples of the sign flip
%
%   Run:  >> V = validate_pid
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));

    K = 2.0;  tau = 600;  lambda = 150;  dt = 1;      % s
    Kp = tau/(K*lambda);  Ti = tau;  Ki = Kp/Ti;

    % ---- A + B: step-reference tracking ----
    c = DHS.controllers.PID(Kp, Ki, 0, 0);           % Tf = 0: no derivative filter, Kd = 0
    c.uMin = -1e9;  c.uMax = 1e9;  c.reset();
    y = 0;  r = 1;  N = round(8*lambda/dt);
    t = (0:N-1)*dt;  Y = zeros(1,N);
    for k = 1:N
        u = c.update(y, r, dt);
        y = y + dt*(-y + K*u)/tau;                    % explicit Euler on the plant
        Y(k) = y;
    end
    Yref = 1 - exp(-t/lambda);
    eA = max(abs(Y - Yref));
    eB = abs(Y(end) - 1);

    % ---- C: constant output disturbance rejection ----
    %   load-disturbance rejection settles with the plant time constant tau
    %   (not lambda), so run for many tau
    c2 = DHS.controllers.PID(Kp, Ki, 0, 0);  c2.uMin=-1e9; c2.uMax=1e9; c2.reset();
    y = 0;  d = 0.3;  Nc = round(20*tau/dt);  Yd = zeros(1,Nc);
    for k = 1:Nc
        u = c2.update(y, 0, dt);
        y = y + dt*(-y + K*u)/tau + dt*d/tau;        % load disturbance added to the state
        Yd(k) = y;
    end
    eC = abs(y - 0);

    % ---- D: anti-windup ----
    c3 = DHS.controllers.PID(1.0, 0.5, 0, 0);  c3.uMin = 0;  c3.uMax = 1;  c3.reset();
    for k = 1:400, u = c3.update(0, 10, 1); end       % huge error -> saturate high for a long time
    assert(abs(u - 1) < 1e-9, 'expected saturation');
    kOff = NaN;
    for k = 1:200
        u = c3.update(11, 10, 1);                     % meas now ABOVE ref -> error sign flips
        if u < 1 - 1e-6, kOff = k; break; end
    end
    okD = ~isnan(kOff) && kOff <= 5;

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(1) = mk('A  step response vs 1 - exp(-t/lambda)  max err',  0, eA, 0.01, 'abs');
    C(2) = mk('B  steady-state error to step reference',          0, eB, 1e-3, 'abs');
    C(3) = mk('C  steady-state error to load disturbance',        0, eC, 1e-3, 'abs');
    C(4) = mk('D  samples to leave the limit after sign flip',    1, double(okD), 0, 'abs');
    V.name = 'Discrete PID vs IMC/lambda-tuned analytical first-order closed loop';
    V.passed = vtable(V.name, C);
    V.cases = C;  V.detail = struct('eA',eA,'eB',eB,'eC',eC,'kOff',kOff,'Kp',Kp,'Ki',Ki,'lambda',lambda);

    td = (1:Nc)*dt;
    vplot(mfilename, { ...
        struct('title','Tracking a setpoint step', 'xlabel','t / \lambda', 'ylabel','output', 'legendLoc','southeast', ...
            'series',{{ struct('x',t/lambda,'y',Yref,'name','1 - e^{-t/\lambda}','style','ref'), ...
                        struct('x',t/lambda,'y',Y,'name','PID and first-order plant','style','sim') }}), ...
        struct('title','Rejecting a load disturbance', 'xlabel','t / \tau', 'ylabel','output', ...
            'series',{{ struct('x',td/tau,'y',0*td,'name','zero steady-state error','style','ref'), ...
                        struct('x',td/tau,'y',Yd,'name','PID and first-order plant','style','sim') }}) }, plotMode);
end

function s = mk(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
