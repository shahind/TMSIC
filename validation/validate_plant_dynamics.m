function V = validate_plant_dynamics(plotMode)
%VALIDATE_PLANT_DYNAMICS  Boiler / plant water dynamics: first-order stirred-tank
%                         response, steady-state energy balance, aquastat, and
%                         the condensing-efficiency curve.
%
%   COMPONENT      DHS.CentralHeatPlant  (evalBoiler / stepControl / commit,
%                  reduced to the single boiler water mass by setting the header
%                  masses and sensor lag to zero)
%
%   TEST CASE + REFERENCE
%     With Cw_rh = Cw_sh = 0, sensorTau = 0, standbyLossW = 0, firingSlewPerMin
%     = 0 and a fixed firing fraction, the plant is a single stirred tank:
%
%         Cw dT_b/dt = eta*Q_gas + mdot_B cp (T_ret - T_b) - Q_base
%
%     which is first order with time constant  tau = Cw / (mdot_B cp)  and
%     steady state  T_b,inf = T_ret + (eta*Q_gas - Q_base) / (mdot_B cp) .
%     (continuous stirred-tank / lumped-capacitance dynamics).
%
%     Condensing gas-boiler efficiency rises as the return-water temperature
%     falls below the flue-gas dew point (~55 degC for natural gas); a piecewise-
%     linear curve clamped to [eta_min, eta_max] is the standard reduced model.
%
%   Sub-cases:
%     A  step response of T_b toward the analytic exponential
%     B  steady-state first-law balance:  eta*Q_gas = mdot*cp*(T_sup - T_ret) + Q_base
%     C  boiler high-limit aquastat: with excess firing, T_b saturates at
%        <= TboilerMax + hysteresis
%     D  efficiency curve monotone decreasing in T_ret and clamped to [eta_min, eta_max]
%
%   WHY THIS TEST IS GOOD
%     The plant supply temperature "wanders but does not chatter" behaviour that
%     the whole DES relies on is a consequence of these three ingredients being
%     right: a genuine first-order lag (A), a closing energy balance (B), and a
%     safety limit that actually bounds the state (C). D checks the efficiency
%     model has the correct qualitative shape and bounds.
%
%   Run:  >> V = validate_plant_dynamics
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));
    cp = 4186;

    % ---- A + B: single-mass step response and steady state ----
    Cw = 3.0e7;  mdotB = 4;  Tret = 45;  QgasMax = 8e5;  Qbase = 0;
    p = DHS.CentralHeatPlant('P');
    p.Cw = Cw;  p.Cw_rh = 0;  p.Cw_sh = 0;  p.sensorTau = 0;  p.standbyLossW = 0;
    p.firingSlewPerMin = 0;  p.mdotMinBoiler = mdotB;  p.TboilerMax = 1e4;   % disable aquastat
    p.addBoiler('B1','QMax',QgasMax,'etaRef',0.90,'etaSlope',0,'TetaRef',50,'etaMin',0.5,'etaMax',1.0);
    p.TsupSet = 1e4;                          % huge -> firing controller pegs u = 1 -> Qgas = QgasMax
    Tb0 = 40;  p.reset(Tb0, Tb0);
    eta = p.etaOf(Tret);                      % 0.90 (flat curve here)
    tau  = Cw/(mdotB*cp);
    Tinf = Tret + (eta*QgasMax - Qbase)/(mdotB*cp);

    dt = 30;  N = round(20*tau/dt);  t = (0:N)*dt;  Tb = zeros(1,N+1);  Tb(1) = Tb0;
    for k = 1:N
        p.stepControl(dt, struct('Mtot',mdotB,'Tout',0));
        [Ts, Tbn, Trh, Qloop, e] = p.evalBoiler(mdotB, Tret, dt, Qbase); %#ok<ASGLU>
        p.commit(Tbn, Trh, Ts, Qloop, e);
        Tb(k+1) = p.Tboiler;
    end
    Tban = Tinf + (Tb0 - Tinf).*exp(-t./tau);
    eStep = max(abs(Tb - Tban)) / abs(Tinf - Tb0);
    % steady-state energy balance at the end
    eBal = abs(e*p.Qgas - (mdotB*cp*(p.Tsupply - Tret) + Qbase)) / (e*p.Qgas);

    % ---- C: aquastat ----
    p2 = DHS.CentralHeatPlant('P2');
    p2.Cw = 5e6;  p2.Cw_rh = 0;  p2.Cw_sh = 0;  p2.sensorTau = 0;  p2.standbyLossW = 0;
    p2.firingSlewPerMin = 0;  p2.mdotMinBoiler = 1;  p2.TboilerMax = 90;
    p2.addBoiler('B','QMax',2e6,'etaRef',0.95,'etaSlope',0,'TetaRef',50);
    p2.TsupSet = 1e4;  p2.reset(70,70);
    for k = 1:5000
        p2.stepControl(60, struct('Mtot',1,'Tout',0));
        [Ts,Tbn,Trh,Ql,e2] = p2.evalBoiler(1, 60, 60, 0);
        p2.commit(Tbn,Trh,Ts,Ql,e2);
    end
    okC = p2.Tboiler <= 90 + 1;

    % ---- D: efficiency curve ----
    pe = DHS.CentralHeatPlant('Pe');
    pe.addBoiler('B','QMax',1e6,'etaRef',0.92,'etaSlope',0.0025,'TetaRef',50,'etaMin',0.80,'etaMax',0.98);
    Tr = 20:5:80;  ev = arrayfun(@(x) pe.etaOf(x), Tr);
    okD = all(diff(ev) <= 1e-12) && min(ev) >= 0.80 - 1e-9 && max(ev) <= 0.98 + 1e-9;

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(1) = mk('A  T_b step response vs exp  (norm. max err)',   0, eStep, 0.02, 'abs');
    C(2) = mk('B  steady state  eta*Qgas = mdot*cp*dT + Qbase',  0, eBal,  1e-6, 'abs');
    C(3) = mk('C  aquastat bounds T_b at <= TboilerMax + hyst',  1, double(okC), 0, 'abs');
    C(4) = mk('D  eta(T_ret) monotone-decreasing, in [0.80,0.98]',1, double(okD), 0, 'abs');
    V.name = 'Plant water dynamics: stirred-tank response, energy balance, aquastat, eta curve';
    V.passed = vtable(V.name, C);
    V.cases = C;  V.detail = struct('tau',tau,'Tinf',Tinf,'eStep',eStep,'eBal',eBal,'Tb_aqua',p2.Tboiler);

    vplot(mfilename, { ...
        struct('title','Boiler water temperature after a firing step', 'xlabel','t / \tau', 'ylabel','T_b  [\circC]', 'legendLoc','southeast', ...
            'series',{{ struct('x',t/tau,'y',Tban,'name','first-order response','style','ref'), ...
                        struct('x',t/tau,'y',Tb,'name','CentralHeatPlant','style','sim') }}), ...
        struct('title','Condensing efficiency against return temperature', 'xlabel','return water temperature  [\circC]', 'ylabel','efficiency', ...
            'series',{{ struct('x',Tr,'y',0.80+0*Tr,'name','admissible range 0.80 to 0.98','style','ref'), ...
                        struct('x',Tr,'y',0.98+0*Tr,'name','','style','ref'), ...
                        struct('x',Tr,'y',ev,'name','efficiency curve','style','sim') }}) }, plotMode);
end

function s = mk(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
