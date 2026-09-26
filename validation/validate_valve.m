function V = validate_valve(plotMode)
%VALIDATE_VALVE  Control valve: Kv sizing equation, inherent characteristics,
%                and installed-authority behaviour.
%
%   COMPONENT      DHS.Hydraulic.Valve.resistance(rho, pos)  ->  K  such that  dp = K*mdot^2
%                    K = 1e5 * 3600^2 / (Kv(pos)^2 * rho^2)
%                    Kv(pos) = Kvs * pos                  ("linear")
%                    Kv(pos) = Kvs * rangeability^(pos-1) ("eqpct")
%
%   TEST CASE + REFERENCE
%     The flow coefficient definition:
%         Q [m3/h] = Kv * sqrt(dp [bar] / SG)          (SG = 1 for water)
%     so for a mass flow mdot [kg/s]:  Q = mdot/rho*3600 ,  dp[Pa] = 1e5*(Q/Kv)^2
%     which is exactly  dp = K*mdot^2  with the K above.  Inherent characteristics
%     linear  Kv/Kvs = pos ;  equal-percentage  Kv/Kvs =
%     R^(pos-1)  with rangeability R (typ. 25-50).
%
%   Sub-cases:
%     A  round-trip: pick mdot, get dp from resistance(), recover Kv from the
%        definition -> equals Kvs at pos = 1
%     B  equal-percentage inherent curve:  Kv(0.5)/Kvs = R^(-0.5)  (R = 50 -> 0.1414)
%     C  linear inherent curve:            Kv(pos)/Kvs = pos
%     D  installed characteristic / authority:  a valve of authority
%        beta = dp_valve,open / (dp_valve,open + dp_fixed) in series with a fixed
%        resistance.  As beta -> 1 the installed flow-vs-travel curve of an
%        equal-percentage valve approaches linear .  Check the
%        installed curve is monotone, spans [~0, full flow], and is "more linear"
%        (smaller curvature) at beta ~ 0.7 than the inherent eqpct curve.
%
%   WHY THIS TEST IS GOOD
%     A pins the sizing equation and the units (bar<->Pa, m3/h<->kg/s); B and C
%     pin the two inherent characteristics against their definitions; D checks
%     the emergent installed behaviour that determines whether the building
%     control loop sees usable gain.
%
%   Run:  >> V = validate_valve
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));

    rho = 978;  Kvs = 25;  R = 50;

    % ---- A: round-trip at pos = 1 (eqpct: R^0 = 1 so Kv = Kvs) ----
    v = DHS.Hydraulic.Valve('V','Kvs',Kvs,'char','eqpct','rangeability',R);
    mdot = 2.0;
    K1 = v.resistance(rho, 1);
    dp = K1 * mdot^2;                                  % Pa
    Q  = mdot/rho*3600;                                % m3/h
    Kv_recovered = Q / sqrt(dp/1e5);
    eA = abs(Kv_recovered - Kvs)/Kvs;

    % ---- B: equal-percentage inherent curve ----
    Kv_of = @(vv,pos) sqrt(1e5*3600^2 / (vv.resistance(rho,pos) * rho^2));
    ratioB   = Kv_of(v, 0.5) / Kvs;
    ratioBref = R^(0.5 - 1);
    eB = abs(ratioB - ratioBref)/ratioBref;

    % ---- C: linear inherent curve ----
    vl = DHS.Hydraulic.Valve('VL','Kvs',Kvs,'char','linear');
    posL = [0.2 0.5 0.8];  eC = 0;
    for pp = posL
        eC = max(eC, abs(Kv_of(vl,pp)/Kvs - pp)/pp);
    end

    % ---- D: installed characteristic / authority ----
    x = linspace(0.05, 1, 40);
    Kfixed = 0.7 * v.resistance(rho, 1);              % choose so beta ~ 0.6-0.7 at open
    q_inst = zeros(size(x));
    for i = 1:numel(x)
        Ktot = v.resistance(rho, x(i)) + Kfixed;      % dp_supply held fixed
        q_inst(i) = sqrt(1 / Ktot);                   % mdot ~ sqrt(dp/Ktot), dp const
    end
    q_inst = q_inst / q_inst(end);
    beta = v.resistance(rho,1) / (v.resistance(rho,1) + Kfixed);
    q_inh = R.^(x-1);  q_inh = q_inh / q_inh(end);
    % "more linear" = closer to the straight line from (x(1),q(1)) to (1,1)
    lin = (x - x(1))/(1 - x(1)) * (1 - q_inst(1)) + q_inst(1);
    curv_inst = max(abs(q_inst - lin));
    lin2 = (x - x(1))/(1 - x(1)) * (1 - q_inh(1)) + q_inh(1);
    curv_inh = max(abs(q_inh - lin2));
    okD = all(diff(q_inst) > -1e-9) && q_inst(1) < 0.3 && curv_inst < curv_inh;

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(1) = mk('A  Kv recovered from resistance() at pos=1',   Kvs, Kv_recovered, 1e-9, 'rel');
    C(2) = mk('B  eqpct inherent  Kv(0.5)/Kvs = R^(-0.5)',    ratioBref, ratioB, 1e-9, 'rel');
    C(3) = mk('C  linear inherent  Kv(pos)/Kvs = pos',        0, eC, 1e-9, 'abs');
    C(4) = mk(sprintf('D  installed eqpct (beta=%.2f) monotone & more linear', beta), 1, double(okD), 0, 'abs');
    V.name = 'Control valve: Kv equation, inherent characteristics, installed authority';
    V.passed = vtable(V.name, C);
    V.cases = C;  V.detail = struct('eA',eA,'eB',eB,'eC',eC,'beta',beta,'curv_inst',curv_inst,'curv_inh',curv_inh);

    pg  = linspace(0.02, 1, 100);
    kEq = arrayfun(@(pp) Kv_of(v, pp), pg) / Kvs;
    pg   = linspace(0.02, 1, 100);
    kEq  = arrayfun(@(pp) Kv_of(v,  pp), pg) / Kvs;
    kLin = arrayfun(@(pp) Kv_of(vl, pp), pg) / Kvs;
    vplot(mfilename, { ...
        struct('title','Inherent flow characteristics', 'xlabel','valve travel', 'ylabel','K_v / K_{vs}', 'legendLoc','northwest', ...
            'series',{{ struct('x',pg,'y',R.^(pg-1),'name','equal-percentage, R^{pos-1}','style','ref'), ...
                        struct('x',pg,'y',pg,'name','linear, pos','style','ref'), ...
                        struct('x',pg,'y',kEq,'name','equal-percentage','style','sim'), ...
                        struct('x',pg,'y',kLin,'name','linear','style','sim') }}) }, plotMode);
end

function s = mk(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
