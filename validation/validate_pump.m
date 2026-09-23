function V = validate_pump(plotMode)
%VALIDATE_PUMP  Centrifugal pump curve + affinity laws + operating point.
%
%   COMPONENT      DHS.Hydraulic.CentrifugalPump.curveHead(mdot, speed)
%                    head(m, s) = max(0,  s^2*dp0  -  dp0 * m^2 / mdotMax^2 )
%
%   TEST CASE + REFERENCE
%     A quadratic (parabolic) head-flow curve is the standard first model of a
%     centrifugal pump (Karassik, I.J. et al. (2008) "Pump Handbook", 4th ed.,
%     McGraw-Hill; Gulich, J.F. (2010) "Centrifugal Pumps", 2nd ed., Springer,
%     Ch. 4; Sarbu, I. (2016) "Advances in Building Services Engineering",
%     Springer). The pump AFFINITY LAWS (Hydraulic Institute ANSI/HI 9.6.7;
%     Karassik Ch. 2) state that for a change of speed ratio s a homologous
%     operating point (Q, H) maps to (s*Q, s^2*H):
%         Q2/Q1 = s ,   H2/H1 = s^2 ,   P2/P1 = s^3
%     The quadratic model satisfies this exactly:
%         head(s*Q, s) = s^2 dp0 - dp0 (sQ)^2/mmax^2 = s^2 (dp0 - dp0 Q^2/mmax^2)
%                      = s^2 * head(Q, 1)
%
%   Sub-cases:
%     A  shut-off head  head(0, 1) = dp0
%     B  run-out        head(mdotMax, 1) = 0
%     C  affinity law   head(s*Q, s) = s^2 * head(Q, 1)   for several Q, s
%     D  operating point against a quadratic system curve  H_sys = K*Q^2:
%          intersection  Q* = mdotMax * s / sqrt(1 + K*mdotMax^2/dp0)  (analytic)
%     E  BRANCH-CLOSURE ROLE  solveBranch(Kbranch, dpAvailable, s) -- the method
%        DHS.HydraulicNetwork.solve actually calls at every substation pump --
%        matches its own closed form
%          mdot = sqrt( (s^2 dp0 + dpAvailable) / (Kbranch + dp0/mdotMax^2) )
%        over a grid of (Kbranch, dpAvailable, s).
%     F  SELF-CONSISTENCY  at the solveBranch solution, the pump's own curve
%        head(mdot,s) must equal the branch's pressure balance
%        Kbranch*mdot^2 - dpAvailable (the equation solveBranch is solving) --
%        checks solveBranch and curveHead cannot silently disagree with each
%        other after an edit to either one.
%
%   WHY THIS TEST IS GOOD
%     A is the pressure scale, B is the flow scale, C is the speed-scaling
%     physics that the distributed-pumping model relies on (each building pump
%     and the central pump ride this curve), D checks that the curve produces
%     the right operating point when closed onto a resistance at the *central*
%     pump position, and E/F do the same for the *substation* pump position --
%     the polymorphic seam every pump type (CentrifugalPump,
%     FixedDisplacementPump; see validate_fixed_displacement_pump.m) must
%     implement identically for DHS.HydraulicNetwork.solve to be agnostic to
%     which pump type is attached.
%
%   EXPECTED OUTPUT: A, B exact; C exact to 1e-12; D matches the analytic
%     intersection to 1e-9 (relative); E, F exact to 1e-12.
%
%   Run:  >> V = validate_pump
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));

    dp0 = 3.0e5;  mmax = 14;
    p = DHS.Hydraulic.CentrifugalPump('P','dp0',dp0,'mdotMax',mmax);

    hShut = p.curveHead(0, 1);
    hRun  = p.curveHead(mmax, 1);

    % affinity law over a grid
    Qg = [1 3 6 9];  Sg = [0.4 0.6 0.8 1.0];
    eAff = 0;
    for s = Sg
        for Q = Qg
            lhs = p.curveHead(s*Q, s);
            rhs = s^2 * p.curveHead(Q, 1);
            eAff = max(eAff, abs(lhs - rhs)/max(abs(rhs),eps));
        end
    end

    % operating point vs system curve  H_sys = K Q^2  at speed s
    K = 1200;  s = 0.85;
    Qstar_an = mmax*s / sqrt(1 + K*mmax^2/dp0);
    Hstar_an = K*Qstar_an^2;
    % solve head(Q,s) = K Q^2  ->  s^2 dp0 = Q^2 (K + dp0/mmax^2)
    Qstar = sqrt(s^2*dp0 / (K + dp0/mmax^2));
    eQ = abs(Qstar - Qstar_an)/Qstar_an;
    % and check the pump head there equals the system head
    eH = abs(p.curveHead(Qstar, s) - K*Qstar^2) / (K*Qstar^2);

    % ---- E, F: substation branch-closure role (solveBranch) ----
    % Kbr_g is chosen so that even the worst case (s=1, dpAv=max(dpAv_g)) keeps
    % the solved flow within the pump's own curve (m < mdotMax); outside that
    % envelope the unclamped branch-closure algebra and curveHead's own
    % max(0,...) floor legitimately part ways (the branch is asking for more
    % flow than the pump curve can physically supply at that speed), which
    % would make case F fail for a reason that has nothing to do with a bug.
    Kbr_g   = [3000 6000 12000];
    dpAv_g  = [0 3e4 8e4];
    s_g     = [0.4 0.7 1.0];
    eBranch = 0;  eSelf = 0;
    for Kbr = Kbr_g
        for dpAv = dpAv_g
            for sb = s_g
                [mSim, hSim] = p.solveBranch(Kbr, dpAv, sb);
                mRef = sqrt((sb^2*dp0 + dpAv) / (Kbr + dp0/mmax^2));
                eBranch = max(eBranch, abs(mSim - mRef)/max(mRef,eps));
                eSelf = max(eSelf, abs(hSim - (Kbr*mSim^2 - dpAv)) / max(Kbr*mSim^2,eps));
            end
        end
    end

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(1) = mk('A  shut-off head  head(0,1) = dp0  [Pa]',       dp0, hShut, 1e-12, 'rel');
    C(2) = mk('B  run-out        head(mdotMax,1) [Pa]',        0,   hRun,  1e-9,  'abs');
    C(3) = mk('C  affinity law   head(sQ,s) = s^2 head(Q,1)',  0,   eAff,  1e-12, 'abs');
    C(4) = mk('D  operating point Q* vs analytic intersection',Qstar_an, Qstar, 1e-9, 'rel');
    C(5) = mk('D  pump head = system head at Q*',              0,   eH,    1e-12, 'abs');
    C(6) = mk('E  solveBranch matches its own closed form',    0,   eBranch, 1e-12, 'abs');
    C(7) = mk('F  solveBranch/curveHead self-consistency',     0,   eSelf,   1e-12, 'abs');
    V.name = 'Centrifugal pump: curve, affinity laws, operating point, branch closure';
    V.passed = vtable(V.name, C);
    V.cases = C;  V.detail = struct('hShut',hShut,'hRun',hRun,'eAff',eAff,'Qstar',Qstar,'Qstar_an',Qstar_an,'Hstar_an',Hstar_an,'eBranch',eBranch,'eSelf',eSelf);

    mg = linspace(0, mmax, 200);
    h1 = arrayfun(@(m) p.curveHead(m, 1.0), mg) / 1e3;
    h6 = arrayfun(@(m) p.curveHead(m, 0.6), mg) / 1e3;
    mg    = linspace(0, mmax, 200);
    sOp   = 0.85;
    expHd = @(m, sp) max(0, sp^2*dp0 - dp0*m.^2/mmax^2) / 1e3;
    Kg    = logspace(2.5, 4.5, 60);  dpAvG = 3e4;  sG = 0.7;
    mBrRef = sqrt((sG^2*dp0 + dpAvG) ./ (Kg + dp0/mmax^2));
    mBrSim = arrayfun(@(Kb) p.solveBranch(Kb, dpAvG, sG), Kg);
    vplot(mfilename, { ...
        struct('title','Head-flow curve and operating point', 'xlabel','flow  [kg/s]', 'ylabel','head  [kPa]', 'legendLoc','northeast', ...
            'series',{{ struct('x',mg,'y',expHd(mg,1),'name','curve, full speed','style','ref'), ...
                        struct('x',mg,'y',expHd(mg,sOp),'name',sprintf('curve, speed %.2f',sOp),'style','ref'), ...
                        struct('x',mg,'y',arrayfun(@(m) p.curveHead(m,1),mg)/1e3,'name','curve, full speed','style','sim'), ...
                        struct('x',mg,'y',arrayfun(@(m) p.curveHead(m,sOp),mg)/1e3,'name',sprintf('curve, speed %.2f',sOp),'style','sim'), ...
                        struct('x',Qstar_an,'y',Hstar_an/1e3,'name','operating point','style','refpoint'), ...
                        struct('x',Qstar,'y',p.curveHead(Qstar,sOp)/1e3,'name','operating point','style','point') }}), ...
        struct('title','Flow delivered to a branch (substation pump)', 'xlabel','branch resistance  K  [Pa/(kg/s)^2]', ...
            'ylabel','flow  [kg/s]', 'xscale','log', ...
            'series',{{ struct('x',Kg,'y',mBrRef,'name','closed form','style','ref'), ...
                        struct('x',Kg,'y',mBrSim,'name','solveBranch','style','sim') }}) }, plotMode);
end

function s = mk(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
