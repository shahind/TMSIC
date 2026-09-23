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
%     law) and the loop pressure equation  dp = K*Q^2  per branch. General
%     method: Todini, E. & Pilati, S. (1988) "A gradient algorithm for the
%     analysis of pipe networks", in "Computer Applications in Water Supply",
%     Wiley (the global-gradient method behind EPANET); Larock, B.E., Jeppson,
%     R.W. & Watters, G.Z. (2000) "Hydraulics of Pipeline Systems", CRC Press,
%     Ch. 5-6.
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

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(1) = mk('A  continuity  sum(branch mdot) = Mtot  [kg/s]',   0, eCont, 1e-9, 'abs');
    C(2) = mk('A  each segment carries its downstream subtree flow',0, segErr, 1e-9, 'abs');
    C(3) = mk('B  identical parallel branches -> equal flow',      0, eSym, 1e-6, 'abs');
    C(4) = mk('C  single-branch Mtot vs pump+system analytic',     Man, s3.Mtot, 5e-3, 'rel');
    C(5) = mk('D  open one valve -> every other branch loses flow',1, double(okD), 0, 'abs');
    V.name = 'Hydraulic network: continuity, symmetry, operating point, coupling';
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
