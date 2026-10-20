function V = validate_hydraulic_network(plotMode)
%VALIDATE_HYDRAULIC_NETWORK  T-junction mass balance, series / parallel hand
%                            calculations, pump-plus-system operating point, and
%                            the inter-building coupling sign.
%
%   COMPONENT      DHS.HydraulicNetwork (tree solve: segment flows, pressure
%                  walk, closed-form branch, damped fixed point) + DHS.Hydraulic.Junction.
%
%   TEST CASE + REFERENCE
%     Steady incompressible pipe-network hydraulics: continuity (sum of flows
%     into a junction = sum out; the hydraulic analogue of Kirchhoff's current
%     law) and the loop pressure equation  dp = K*Q^2  per branch.
%
%   Sub-cases:
%     A  CONTINUITY: for the assembled 3-building tree, sum(branch mdot) equals
%        the plant flow Mtot exactly, and every supply pipe segment carries the
%        sum of the branch flows in its downstream subtree.
%     B  PARALLEL SYMMETRY: two identical branches (same pipe, valve, HX, pump)
%        off one tee -> equal flow.
%     C  SINGLE-BRANCH OPERATING POINT vs a hand calculation: one branch, no
%        building pump, branch resistance K_b, central pump curve
%        dpC(M) = dp0 (1 - (M/Mmax)^2).  The steady flow solves
%           dp0 (1 - (M/Mmax)^2) = (K_seg + K_b) M^2
%        =>  M = Mmax / sqrt(1 + Mmax^2 (K_seg + K_b) / dp0)     (analytic)
%        solve() is called a few times first so the lagged Darcy friction factor
%        (updated from the previous call's flow) settles.
%     D  COUPLING SIGN: opening one building's valve raises Mtot and lowers the
%        differential pressure at the other tees, so every other branch loses
%        flow (documented physics; verifies the tree solve captures the shared
%        trunk + central-pump curve coupling).
%     E  PIPE HEAT LOSS: one pipe's outlet temperature and heat loss against
%        T_out = T_g + (T_in - T_g) exp(-U'L/(mdot cp)),  Q_loss = mdot cp (T_in - T_out).
%     F  SUPPLY WALK: on the 3-building tree the temperature at each heat-exchanger
%        inlet and the total supply heat loss equal a hand calculation in which
%        every pipe (trunk segments and connection pipes) loses heat once, with the
%        flow it carries -- a trunk shared by several buildings is not counted per
%        building.
%     G  RETURN WALK: the temperature arriving at the plant equals a hand calculation
%        with enthalpy mixing (m cp T) at each junction and heat loss in every return
%        pipe, and the enthalpy flowing in minus out equals the heat lost.
%     H  END-OF-LINE BYPASS: with a building and a bypass in parallel at the last
%        junction, the total flow equals the closed form for a pump curve against
%        K_trunk + K_eq,  K_eq = 1/(1/sqrt(K_building) + 1/sqrt(K_bypass))^2.
%     I  The bypass-to-building flow ratio equals sqrt(K_building / K_bypass).
%     J  VALVE POSITION: closing the building valve cuts the building flow and sends
%        more through the bypass (total = building + bypass flow).
%     K  The bypass water leaves the supply tree, loses heat in its pipe and joins the
%        return by enthalpy mixing; temperatures equal a hand calculation and the plant
%        heat equals the delivered heat plus the pipe losses.
%
%   WHY THIS TEST IS GOOD
%     A is the conservation law the solver must never violate; B checks the
%     topology handling (a tee feeding two branches); C pins the one nonlinear
%     equation against a closed form; D checks the qualitative coupling that the
%     distributed-pumping design is all about.
%
%   Run:  >> V = validate_hydraulic_network
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));

    % ================= A + D: a small assembled tree =================
    sys = DHS.System('startDate', datetime(2025,1,1));
    chp = sys.addCentralHeatPlant('CHP');
    chp.addBoiler('B','QMax',1e6);
    chp.addPump('P','dp0',3.0e5,'mdotMax',16);
    hn = sys.addHydraulicNetwork();
    t1 = hn.addJunction('T1');  t2 = hn.addJunction('T2');  t3 = hn.addJunction('T3');
    hn.addPipe(chp.supplyPort, t1, 'L',30,'D',0.10);
    hn.addPipe(t1, t2, 'L',40,'D',0.10);
    hn.addPipe(t2, t3, 'L',40,'D',0.10);
    tees = {t1, t2, t3};
    for i = 1:3
        b = sys.addBuilding(sprintf('B%d', i));
        b.useRCModel( trivialRC() );
        hx = b.addHeatExchanger('HX','UA',3e4,'Qcap',5e5);
        hx.valve.Kvs = 18;  hx.pump.dp0 = 0.9e5;  hx.pump.mdotMax = 5;  hx.pump.minSpeed = 0.2;
        b.attachSolar(DHS.Solar());  b.attachSchedule(DHS.Schedule());
        hn.connectBuilding(tees{i}, b);
    end
    sys.compile();

    for i = 1:3, hn.buildings{i}.heatExchanger.valve.pos = 0.5;  hn.buildings{i}.heatExchanger.pump.speed = 0.5; end
    s0 = hn.solve(1);
    eCont = abs(sum(s0.mdot) - s0.Mtot);
    % segment k carries the sum of the downstream branch flows
    segErr = 0;
    for k = 1:numel(hn.pipes)
        segErr = max(segErr, abs(hn.pipes{k}.mdot - sum(s0.mdot(hn.pipes{k}.downBuildings))));
    end

    % coupling: open B2
    hn.buildings{2}.heatExchanger.valve.pos = 1.0;  hn.buildings{2}.heatExchanger.pump.speed = 1.0;
    s1 = hn.solve(1);
    okD = s1.mdot(2) > s0.mdot(2) && s1.Mtot > s0.Mtot && s1.dpPump < s0.dpPump ...
        && all(s1.mdot([1 3]) < s0.mdot([1 3]));

    % ================= B: parallel symmetry =================
    sys2 = DHS.System('startDate', datetime(2025,1,1));
    c2 = sys2.addCentralHeatPlant('C');  c2.addBoiler('B','QMax',1e6);  c2.addPump('P','dp0',3e5,'mdotMax',16);
    h2 = sys2.addHydraulicNetwork();  tt = h2.addJunction('TT');
    h2.addPipe(c2.supplyPort, tt, 'L',20,'D',0.12);
    for i = 1:2
        b = sys2.addBuilding(sprintf('P%d',i));  b.useRCModel(trivialRC());
        hx = b.addHeatExchanger('HX','UA',3e4,'Qcap',5e5);
        hx.valve.Kvs = 20;  hx.pump.dp0 = 1e5;  hx.pump.mdotMax = 5;
        b.attachSolar(DHS.Solar()); b.attachSchedule(DHS.Schedule());
        h2.connectBuilding(tt, b);
    end
    sys2.compile();  sB = h2.solve(1);
    eSym = abs(sB.mdot(1) - sB.mdot(2)) / sB.mdot(1);

    % ================= C: single-branch operating point vs analytic =================
    sys3 = DHS.System('startDate', datetime(2025,1,1));
    c3 = sys3.addCentralHeatPlant('C');  c3.addBoiler('B','QMax',1e6);
    dp0 = 2.5e5;  Mmax = 12;
    c3.addPump('P','dp0',dp0,'mdotMax',Mmax);
    h3 = sys3.addHydraulicNetwork();  h3.pReturnRef = 1.5e5;
    tc = h3.addJunction('TC');
    Lm = 25;  Dm = 0.11;
    h3.addPipe(c3.supplyPort, tc, 'L',Lm,'D',Dm);
    b = sys3.addBuilding('S');  b.useRCModel(trivialRC());
    hx = b.addHeatExchanger('HX','UA',1e5,'Qcap',5e5,'dpNomPrimary',1e-6);   % near-zero HX & valve loss
    hx.valve.Kvs = 1e6;  hx.pump.dp0 = 0;  hx.pump.mdotMax = 1e6;  hx.pump.minSpeed = 0;  % no building pump
    b.connLength = 20;  b.connD = 0.05;  b.Kminor = 0;
    b.attachSolar(DHS.Solar()); b.attachSchedule(DHS.Schedule());
    h3.connectBuilding(tc, b);
    sys3.compile();  b.heatExchanger.valve.pos = 1;  b.heatExchanger.pump.speed = 0;
    for it = 1:6, s3 = h3.solve(1); end          % iterate so the lagged pipe friction factor settles
    % reconstruct the branch resistance the solver used (connection pipes only here)
    rho = h3.rho;  mu = h3.mu;
    Ksup = b.connPipeSup.resistance(s3.mdot, rho, mu);
    Kret = b.connPipeRet.resistance(s3.mdot, rho, mu);
    Kmain = 0;
    for k = 1:numel(h3.pipes)
        Kmain = Kmain + h3.pipes{k}.resistance(s3.Mtot, rho, mu) + h3.retPipes{k}.resistance(s3.Mtot, rho, mu);
    end
    Kbr = Ksup + Kret + hx.primaryResistance(rho);
    Kt  = Kmain + Kbr;
    Man = Mmax / sqrt(1 + Mmax^2 * Kt / dp0);
    eC  = abs(s3.Mtot - Man) / Man;

    % ================= E, F, G: temperatures along the same tree (state s0) =================
    cp = 4186;  Tp = 70;  Tg = 5;  m = s0.mdot;
    Q  = [sum(m), sum(m(2:3)), m(3)];                 % trunk segment flows (T1 -> T2 -> T3 chain)
    UL = cellfun(@(p) p.UperM*p.L, hn.pipes(1:3));    % W/K of each trunk pipe
    Ucn = cellfun(@(b) b.connPipeSup.UperM*b.connPipeSup.L, hn.buildings);
    decay = @(UAx, flow) exp(-UAx ./ (flow*cp));
    % E  one pipe: analytic outlet temperature and heat loss
    [ToE, qlE] = hn.pipes{1}.outletTemperature(Tp, Tg, Q(1), cp);
    ToEan = Tg + (Tp - Tg)*decay(UL(1), Q(1));
    eE = max(abs(ToE - ToEan), abs(qlE - Q(1)*cp*(Tp - ToEan))/(Q(1)*cp));
    % F  supply walk: every pipe loses heat ONCE with its own flow (hand chain)
    Tn = zeros(1,3);  Tprev = Tp;  qlF = 0;
    for k = 1:3
        Tn(k) = Tg + (Tprev - Tg)*decay(UL(k), Q(k));
        qlF = qlF + Q(k)*cp*(Tprev - Tn(k));  Tprev = Tn(k);
    end
    ThxAn = Tg + (Tn - Tg).*decay(Ucn, m);
    qlF = qlF + sum(m.*cp.*(Tn - ThxAn));
    [Thx, qlS] = hn.supplyTemperatures(Tp, Tg, m, cp);
    eF = max(max(abs(Thx - ThxAn)), abs(qlS - qlF)/qlF);
    % G  return walk: enthalpy mixing at the tees and heat loss in every return pipe (hand chain)
    Thx0 = [45 40 35];
    Tr = Tg + (Thx0 - Tg).*decay(Ucn, m);             % return connection pipes
    ToR3 = Tg + (Tr(3) - Tg)*decay(UL(3), Q(3));
    Tmix2 = (m(2)*Tr(2) + Q(3)*ToR3)/Q(2);
    ToR2 = Tg + (Tmix2 - Tg)*decay(UL(2), Q(2));
    Tmix1 = (m(1)*Tr(1) + Q(2)*ToR2)/Q(1);
    TretAn = Tg + (Tmix1 - Tg)*decay(UL(1), Q(1));
    [Tret, qlR] = hn.returnTemperatures(Thx0, Tg, m, cp);
    eG1 = abs(Tret - TretAn);
    eG2 = abs(sum(m.*cp.*Thx0) - Q(1)*cp*Tret - qlR)/qlR;      % energy: enthalpy in - out = heat lost

    % ================= H, I, J, K: end-of-line bypass =================
    sys4 = DHS.System('startDate', datetime(2025,1,1));
    c4 = sys4.addCentralHeatPlant('C');  c4.addBoiler('B','QMax',1e6);
    c4.addPump('P','dp0',dp0,'mdotMax',Mmax);
    h4 = sys4.addHydraulicNetwork();  h4.pReturnRef = 1.5e5;
    t4 = h4.addJunction('TB');  h4.addPipe(c4.supplyPort, t4, 'L',Lm,'D',Dm);
    h4.addBypass('L',20, 'D',0.05, 'Kvs',1.5);
    b4 = sys4.addBuilding('S');  b4.useRCModel(trivialRC());
    hx4 = b4.addHeatExchanger('HX','UA',1e5,'Qcap',5e5,'dpNomPrimary',1e-6);
    hx4.valve.Kvs = 25;  hx4.pump.dp0 = 0;  hx4.pump.mdotMax = 1e6;  hx4.pump.minSpeed = 0;
    b4.connLength = 20;  b4.connD = 0.05;  b4.Kminor = 0;
    b4.attachSolar(DHS.Solar()); b4.attachSchedule(DHS.Schedule());
    h4.connectBuilding(t4, b4);
    sys4.compile();  hx4.pump.speed = 0;
    hx4.valve.pos = 1;  for it = 1:10, s4 = h4.solve(1); end
    rho = h4.rho;  mu = h4.mu;
    Kb4  = b4.connPipeSup.resistance(s4.mdot,rho,mu) + b4.connPipeRet.resistance(s4.mdot,rho,mu) + hx4.primaryResistance(rho);
    Kbp  = h4.bypassPipe.resistance(s4.mdotBypass,rho,mu) + h4.bypassValve.resistance(rho);
    Kmn  = h4.pipes{1}.resistance(s4.Mtot,rho,mu) + h4.retPipes{1}.resistance(s4.Mtot,rho,mu);
    Keq  = 1 / (1/sqrt(Kb4) + 1/sqrt(Kbp))^2;                    % two branches in parallel at one junction
    Man4 = Mmax / sqrt(1 + Mmax^2*(Kmn + Keq)/dp0);
    eH = abs(s4.Mtot - Man4)/Man4;
    eI = abs(s4.mdotBypass/s4.mdot - sqrt(Kb4/Kbp))/sqrt(Kb4/Kbp);
    % J  valve position: closing the building valve cuts its flow and sends more through the bypass
    sFull = s4;
    hx4.valve.pos = 0.15;  for it = 1:10, sClosed = h4.solve(1); end
    okJ = sClosed.mdot < 0.5*sFull.mdot && sClosed.mdotBypass > sFull.mdotBypass ...
        && abs(sClosed.Mtot - sum(sClosed.mdot) - sClosed.mdotBypass) < 1e-12 && sClosed.Mtot < sFull.Mtot;
    hx4.valve.pos = 1;  for it = 1:10, s4 = h4.solve(1); end
    % K  temperatures with the bypass: supply walk, bypass stream joins the return at the end junction
    mb = s4.mdot;  mbp = s4.mdotBypass;  M4 = mb + mbp;
    ULt = h4.pipes{1}.UperM*h4.pipes{1}.L;  ULb = h4.bypassPipe.UperM*h4.bypassPipe.L;
    ULc = b4.connPipeSup.UperM*b4.connPipeSup.L;
    T1  = Tg + (Tp - Tg)*decay(ULt, M4);
    ThxB = Tg + (T1 - Tg)*decay(ULc, mb);   Tbp = Tg + (T1 - Tg)*decay(ULb, mbp);
    [ThxN, qlS4] = h4.supplyTemperatures(Tp, Tg, mb, cp);
    Thx0 = 45;  TrB = Tg + (Thx0 - Tg)*decay(ULc, mb);
    Tmx = (mb*TrB + mbp*Tbp)/M4;
    TretB = Tg + (Tmx - Tg)*decay(ULt, M4);
    [TretN, qlR4] = h4.returnTemperatures(Thx0, Tg, mb, cp);
    eK1 = max(abs(ThxN - ThxB), abs(TretN - TretB));
    eK2 = abs(M4*cp*(Tp - TretN) - mb*cp*(ThxN - Thx0) - qlS4 - qlR4)/(M4*cp*(Tp - TretN));   % plant heat = delivered + losses

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(10) = mk('H  with bypass: Mtot vs pump + parallel-branch analytic',  0, eH, 5e-3, 'abs');
    C(11) = mk('I  bypass / building flow = sqrt(K_building/K_bypass)',   0, eI, 1e-3, 'abs');
    C(12) = mk('J  closing the building valve sends the flow to the bypass', 1, double(okJ), 0, 'abs');
    C(13) = mk('K  bypass temperatures vs hand calculation  [K]',          0, eK1, 1e-9, 'abs');
    C(14) = mk('K  plant heat = delivered + pipe losses (rel)',            0, eK2, 1e-9, 'abs');
    C(6) = mk('E  one pipe: outlet temperature and heat loss vs analytic', 0, eE, 1e-9, 'abs');
    C(7) = mk('F  supply walk: each pipe loses heat once, own flow',       0, eF, 1e-9, 'abs');
    C(8) = mk('G  return walk: enthalpy mixing vs hand calculation  [K]',  0, eG1, 1e-9, 'abs');
    C(9) = mk('G  return walk: enthalpy in - out = heat lost (rel)',       0, eG2, 1e-9, 'abs');
    C(1) = mk('A  continuity  sum(branch mdot) = Mtot  [kg/s]',   0, eCont, 1e-9, 'abs');
    C(2) = mk('A  each segment carries its downstream subtree flow',0, segErr, 1e-9, 'abs');
    C(3) = mk('B  identical parallel branches -> equal flow',      0, eSym, 1e-6, 'abs');
    C(4) = mk('C  single-branch Mtot vs pump+system analytic',     Man, s3.Mtot, 5e-3, 'rel');
    C(5) = mk('D  open one valve -> every other branch loses flow',1, double(okD), 0, 'abs');
    V.name = 'Hydraulic network: continuity, symmetry, operating point, coupling, pipe temperatures, bypass';
    V.passed = vtable(V.name, C);
    V.cases = C;  V.detail = struct('eCont',eCont,'segErr',segErr,'eSym',eSym,'Mtot',s3.Mtot,'Man',Man,'eC',eC);

    vplot(mfilename, { ...
        struct('title','Network flow checks', 'ylabel','flow  [kg/s]', 'kind','bars', ...
            'labels',{{'balance (50 %)','balance (B2 open)','parallel pair','operating point'}}, ...
            'expected',[s0.Mtot, s1.Mtot, sB.mdot(1), Man], ...
            'actual',  [sum(s0.mdot), sum(s1.mdot), sB.mdot(2), s3.Mtot]) }, plotMode);
end

function B = trivialRC()
    B = RCBS.Building(); B.addStorey('S'); B.S.addZone('Z','C_main',2e6);
    B.S.Z.setAir(2e6, 20);
    B.S.Z.addWindow(0.02, 'Window');  B.S.Z.addWindow(0.05, 'InfVent');
end

function s = mk(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
