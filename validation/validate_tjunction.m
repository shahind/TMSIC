function V = validate_tjunction(plotMode)
%VALIDATE_TJUNCTION  T-fitting minor loss vs the equivalent-length
%                    method, its wiring into DHS.Hydraulic.Pipe.resistance,
%                    and its effect on a network's operating point.
%
%   COMPONENT      DHS.Hydraulic.TJunction.teeLossK(side, rho, mu, mdot)
%                    K_run    = f(D_main) * (20*D_main) / (D_main * 2*rho*A_main^2)
%                    K_branch = f(D_side) * (60*D_side) / (D_side * 2*rho*A_side^2)
%                  where f is the same Swamee-Jain/laminar friction factor
%                  DHS.Hydraulic.Pipe uses, evaluated at that leg's own actual
%                  Reynolds number (from mdot) -- the same laminar/turbulent
%                  rule the pipe itself follows, not a fixed turbulent guess.
%
%   TEST CASE + REFERENCE
%     A standard tee has an equivalent length, in pipe
%     diameters, of 20 used as a straight run and 60 used as a branch (the
%     "equivalent length" or "L/D" method is the standard hand-calculation
%     approach for fitting losses; branch flow always loses substantially more
%     head than the straight run).
%
%   Sub-cases:
%     A  K_run formula: teeLossK('run',...) matches the hand-built
%        expression exactly.
%     B  K_branch formula: teeLossK('branch',...) matches the hand-built
%        expression exactly.
%     C  DIMENSIONLESS RATIO (independent of rho, mu, D): for a tee where
%        mainDiameter = sideDiameter (so f is identical for both legs and A
%        cancels), K_branch/K_run = 60/20 = 3 exactly -- the equivalent-length
%        ratio, decoupled from any specific fluid or
%        pipe size.
%     D  PIPE INTEGRATION: a pipe wired to portB picks up exactly K_run on top
%        of its own Darcy-Weisbach term; a pipe wired to portC picks up
%        exactly K_branch; a pipe with no teeSide (or not leaving a TJunction)
%        picks up neither (no false positive).
%     E  NETWORK-LEVEL EFFECT: assemble the same single-branch network twice --
%        once through a plain DHS.Hydraulic.Junction, once through a
%        DHS.Hydraulic.TJunction wired identically -- and confirm the tee
%        version's total flow matches the analytic prediction obtained by
%        adding the tee's own K_branch to the hand-reconstructed branch
%        resistance in the pump/system closed form (Mmax/sqrt(1+Mmax^2 Kt/dp0),
%        the same closed form validate_hydraulic_network uses).
%     F  BOTH WIRING STYLES AGREE: the declarative bridge
%        (hn.addJunction(name,'type','tee',...)) and the port-wiring style
%        (tee.connectToPipe('portB'/'portC', pipe)) produce numerically
%        identical tee losses for the same geometry.
%     G  LAMINAR CONSISTENCY: at a flow low enough that the branch leg's own
%        Reynolds number is below 2300, teeLossK's friction factor equals the
%        laminar value 64/Re, exactly tracking DHS.Hydraulic.Pipe's own
%        laminar/turbulent rule rather than assuming the flow is always
%        turbulent.
%
%   WHY THIS TEST IS GOOD
%     A and B pin the formula itself; C is a fluid- and size-independent sanity
%     check straight from the equivalent lengths (branch resistance is exactly 3x the
%     run resistance at equal diameter, by construction of the 60D/20D
%     equivalent lengths); D confirms the loss is wired into the one place the
%     solver actually reads (Pipe.resistance) with no double-counting or
%     missing term; E closes the loop end-to-end, showing the tee measurably
%     changes a real network's operating point by the predicted amount; F
%     confirms neither assembly API silently uses different physics; G confirms
%     the fitting's friction factor cannot silently drift out of step with the
%     pipe's own friction factor at low flow.
%
%   EXPECTED OUTPUT: A, B, C exact to 1e-12; D exact to 1e-9 (relative); E
%     matches the analytic prediction to 1e-3 (relative, limited by the lagged
%     friction-factor fixed point); F exact to 1e-9; G exact to 1e-12.
%
%   Run:  >> V = validate_tjunction
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));

    rho = 978;  mu = 4.0e-4;  mdotTest = 2.0;

    % ---- A, B: formula match, at the tee's own actual flow ----
    tee = DHS.Hydraulic.TJunction('T', 'mainDiameter',0.10, 'sideDiameter',0.05);
    Krun    = tee.teeLossK('run',    rho, mu, mdotTest);
    Kbranch = tee.teeLossK('branch', rho, mu, mdotTest);

    ARun = pi*tee.mainDiameter^2/4;
    ReRun = rho * (mdotTest/(rho*ARun)) * tee.mainDiameter / mu;
    fRun = DHS.Hydraulic.Pipe.swameeJain(ReRun, tee.roughness/tee.mainDiameter);
    KrunRef = fRun * (20*tee.mainDiameter) / (tee.mainDiameter * 2*rho*ARun^2);

    ABr = pi*tee.sideDiameter^2/4;
    ReBr = rho * (mdotTest/(rho*ABr)) * tee.sideDiameter / mu;
    fBr = DHS.Hydraulic.Pipe.swameeJain(ReBr, tee.roughness/tee.sideDiameter);
    KbranchRef = fBr * (60*tee.sideDiameter) / (tee.sideDiameter * 2*rho*ABr^2);

    eA = abs(Krun - KrunRef) / KrunRef;
    eB = abs(Kbranch - KbranchRef) / KbranchRef;

    % ---- C: dimensionless 3x ratio at equal diameter (same D, same mdot on
    % both legs => same Re => f cancels in the ratio regardless of flow) ----
    teeEq = DHS.Hydraulic.TJunction('Teq', 'mainDiameter',0.08, 'sideDiameter',0.08);
    ratio = teeEq.teeLossK('branch', rho, mu, mdotTest) / teeEq.teeLossK('run', rho, mu, mdotTest);
    eC = abs(ratio - 3) / 3;

    % ---- G: laminar consistency at a deliberately low flow. mdotLow is chosen
    % so the branch leg's Re lands comfortably inside (2300, 640) -- laminar,
    % but above the Re=640 point where 64/Re first hits swameeJain's own
    % [0.008,0.1] floor/ceiling clamp, so this probes the laminar law itself,
    % not that clamp. ----
    mdotLow = 0.015;
    KbranchLow = tee.teeLossK('branch', rho, mu, mdotLow);
    ReBrLow = rho * (mdotLow/(rho*ABr)) * tee.sideDiameter / mu;
    fBrLow = DHS.Hydraulic.Pipe.swameeJain(ReBrLow, tee.roughness/tee.sideDiameter);
    KbranchLowRef = fBrLow * (60*tee.sideDiameter) / (tee.sideDiameter * 2*rho*ABr^2);
    eG = abs(KbranchLow - KbranchLowRef) / KbranchLowRef;
    okG_laminar = ReBrLow < 2300 && abs(fBrLow - 64/ReBrLow) < 1e-12;

    % ---- D: pipe integration, both ports, and a no-op control ----
    pRun = DHS.Hydraulic.Pipe('run',  'D',tee.mainDiameter, 'L',10);
    tee.connectToPipe('portB', pRun);
    KrunTotal = pRun.resistance(mdotTest, rho, mu);
    Kpipe_run_only = DHS.Hydraulic.Pipe('run2', 'D',tee.mainDiameter, 'L',10);   % identical pipe, no tee
    KrunBase = Kpipe_run_only.resistance(mdotTest, rho, mu);
    eD1 = abs(KrunTotal - (KrunBase + Krun)) / KrunTotal;

    pBranch = DHS.Hydraulic.Pipe('side', 'D',tee.sideDiameter, 'L',6);
    tee.connectToPipe('portC', pBranch);
    KbranchTotal = pBranch.resistance(mdotTest, rho, mu);
    Kpipe_branch_only = DHS.Hydraulic.Pipe('side2', 'D',tee.sideDiameter, 'L',6);  % identical pipe, no tee
    Kbase = Kpipe_branch_only.resistance(mdotTest, rho, mu);
    eD2 = abs(KbranchTotal - (Kbase + Kbranch)) / KbranchTotal;

    pPlain = DHS.Hydraulic.Pipe('plain', 'D',0.10, 'L',10);   % no teeSide at all
    Kplain = pPlain.resistance(mdotTest, rho, mu);
    KplainBase = DHS.Hydraulic.Pipe('plainBase', 'D',0.10, 'L',10).resistance(mdotTest, rho, mu);
    eD3 = abs(Kplain - KplainBase);   % must be exactly the bare Darcy term -- no spurious tee loss

    % ---- E: network-level effect of a real tee vs a plain junction ----
    dp0 = 2.5e5;  Mmax = 12;  Lm = 25;  Dm = 0.11;  Dside = 0.05;
    [Mplain, KtPlain] = singleBranchNetwork(dp0, Mmax, Lm, Dm, 'plain', Dside); %#ok<ASGLU>
    [Mtee,   KtTee]   = singleBranchNetwork(dp0, Mmax, Lm, Dm, 'tee',   Dside);
    Man_tee = Mmax / sqrt(1 + Mmax^2 * KtTee / dp0);
    eE = abs(Mtee - Man_tee) / Man_tee;
    okE_direction = Mtee < Mplain;   % adding the tee's own loss can only reduce flow

    % ---- F: declarative vs port-wiring produce the same tee loss ----
    hn = DHS.HydraulicNetwork();
    tDecl = hn.addJunction('Td', 'type','tee', 'mainDiameter',0.10, 'sideDiameter',0.05);
    KdeclRun    = tDecl.teeLossK('run',    rho, mu, mdotTest);
    KdeclBranch = tDecl.teeLossK('branch', rho, mu, mdotTest);
    tWire = DHS.Hydraulic.TJunction('Tw', 'mainDiameter',0.10, 'sideDiameter',0.05);
    KwireRun    = tWire.teeLossK('run',    rho, mu, mdotTest);
    KwireBranch = tWire.teeLossK('branch', rho, mu, mdotTest);
    eF = max(abs(KdeclRun-KwireRun), abs(KdeclBranch-KwireBranch)) / KwireBranch;

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(1) = mk('A  K_run matches equivalent-length formula',     KrunRef, Krun, 1e-12, 'rel');
    C(2) = mk('B  K_branch matches equivalent-length formula',  KbranchRef, Kbranch, 1e-12, 'rel');
    C(3) = mk('C  equal-D ratio  K_branch/K_run = 60/20 = 3',         3, ratio, 1e-12, 'rel');
    C(4) = mk('D  run-port pipe picks up exactly K_run',              0, eD1, 1e-9, 'abs');
    C(5) = mk('D  branch-port pipe picks up exactly K_branch',        0, eD2, 1e-9, 'abs');
    C(6) = mk('D  a plain (non-tee) pipe is unaffected',              0, eD3, 1e-12, 'abs');
    C(7) = mk('E  network Mtot with tee vs analytic (Kt+K_branch)',   Man_tee, Mtee, 1e-3, 'rel');
    C(8) = mk('E  tee reduces flow vs the plain-junction network',    1, double(okE_direction), 0, 'abs');
    C(9) = mk('F  declarative vs port-wiring: identical tee loss',    0, eF, 1e-9, 'abs');
    C(10) = mk('G  friction factor matches laminar 64/Re at low flow', 0, eG, 1e-12, 'abs');
    C(11) = mk('G  the low-flow probe is actually laminar (Re<2300)',  1, double(okG_laminar), 0, 'abs');
    V.name = 'T-junction (equivalent-length method) vs formula, pipe integration, network effect';
    V.passed = vtable(V.name, C);
    V.cases = C;  V.detail = struct('Krun',Krun,'Kbranch',Kbranch,'ratio',ratio,'Mplain',Mplain,'Mtee',Mtee,'Man_tee',Man_tee);

    Dg = linspace(0.03, 0.15, 60);
    teeSweep = DHS.Hydraulic.TJunction('Tsw','mainDiameter',0.10,'sideDiameter',0.10);
    KrunSweep = zeros(size(Dg));  KbranchSweep = zeros(size(Dg));
    KrunEx = zeros(size(Dg));     KbranchEx = zeros(size(Dg));
    for i = 1:numel(Dg)
        teeSweep.mainDiameter = Dg(i);  teeSweep.sideDiameter = Dg(i);
        KrunSweep(i)    = teeSweep.teeLossK('run',    rho, mu, mdotTest);
        KbranchSweep(i) = teeSweep.teeLossK('branch', rho, mu, mdotTest);
        Ai = pi*Dg(i)^2/4;
        Rei = rho * (mdotTest/(rho*Ai)) * Dg(i) / mu;
        fD = DHS.Hydraulic.Pipe.swameeJain(Rei, teeSweep.roughness/Dg(i));
        KrunEx(i)    = fD * 20 / (2*rho*Ai^2);
        KbranchEx(i) = fD * 60 / (2*rho*Ai^2);
    end
    Man_plain = Mmax / sqrt(1 + Mmax^2 * KtPlain / dp0);
    vplot(mfilename, { ...
        struct('title','Tee loss coefficient (main and side diameter equal)', 'xlabel','pipe diameter  D  [m]', ...
            'ylabel','K  [Pa/(kg/s)^2]', 'yscale','log', 'legendLoc','northeast', ...
            'series',{{ struct('x',Dg,'y',KrunEx,'name','run (20 D)','style','ref'), ...
                        struct('x',Dg,'y',KbranchEx,'name','branch (60 D)','style','ref'), ...
                        struct('x',Dg,'y',KrunSweep,'name','run','style','sim'), ...
                        struct('x',Dg,'y',KbranchSweep,'name','branch','style','sim') }}), ...
        struct('title','Total flow of a one-branch network', 'ylabel','flow  [kg/s]', 'kind','bars', ...
            'labels',{{'plain junction','T-junction'}}, 'expected',[Man_plain, Man_tee], 'actual',[Mplain, Mtee]) }, plotMode);
end

function [Mtot, Kt] = singleBranchNetwork(dp0, Mmax, Lm, Dm, junctionType, Dside)
% Build one central plant feeding one substation through a single trunk pipe,
% either through a plain junction or through a T-junction (branch leg feeding
% the substation), and return the solved total flow plus the hand-reconstructed
% total branch resistance (everything the flow passes through).
    sys = DHS.System('startDate', datetime(2025,1,1));
    c = sys.addCentralHeatPlant('C');  c.addBoiler('B','QMax',1e6);
    c.addPump('P','dp0',dp0,'mdotMax',Mmax);
    hn = sys.addHydraulicNetwork();  hn.pReturnRef = 1.5e5;
    if strcmpi(junctionType, 'tee')
        node = hn.addJunction('T', 'type','tee', 'mainDiameter',Dm, 'sideDiameter',Dside);
    else
        node = hn.addJunction('T');
    end
    hn.addPipe(c.supplyPort, node, 'L',Lm, 'D',Dm);
    b = sys.addBuilding('S');  b.useRCModel(trivialRC());
    hx = b.addHeatExchanger('HX', 'UA',1e5, 'Qcap',5e5, 'dpNomPrimary',1e-6);
    hx.valve.Kvs = 1e6;  hx.pump.dp0 = 0;  hx.pump.mdotMax = 1e6;  hx.pump.minSpeed = 0;
    b.connLength = 15;  b.connD = 0.05;  b.Kminor = 0;
    b.attachSolar(DHS.Solar());  b.attachSchedule(DHS.Schedule());
    hn.connectBuilding(node, b);
    sys.compile();  hx.valve.pos = 1;  hx.pump.speed = 0;
    for it = 1:6, s = hn.solve(1); end
    rho = hn.rho;  mu = hn.mu;
    Ksup = b.connPipeSup.resistance(s.mdot, rho, mu);
    Kret = b.connPipeRet.resistance(s.mdot, rho, mu);
    Kmain = 0;
    for k = 1:numel(hn.pipes)
        Kmain = Kmain + hn.pipes{k}.resistance(s.Mtot, rho, mu) + hn.retPipes{k}.resistance(s.Mtot, rho, mu);
    end
    Kt = Kmain + Ksup + Kret + hx.primaryResistance(rho);
    Mtot = s.Mtot;
end

function B = trivialRC()
    B = RCBS.Building(); B.addStorey('S'); B.S.addZone('Z','C_main',2e6);
    B.S.Z.setAir(2e6, 20);
    B.S.Z.addWindow(0.02, 'Window');  B.S.Z.addWindow(0.05, 'InfVent');
end

function s = mk(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
