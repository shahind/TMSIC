function V = validate_fixed_displacement_pump(plotMode)
%VALIDATE_FIXED_DISPLACEMENT_PUMP  Positive-displacement pump: rated-flow
%                                  plateau, relief-valve cap, and the
%                                  transition between the two regimes.
%
%   COMPONENT      DHS.Hydraulic.FixedDisplacementPump.solveBranch(Kbranch, dpAvailable, frac)
%                    mdot = min( frac*mdotRated , sqrt(max(0,(dpMax+dpAvailable))/Kbranch) )
%
%   TEST CASE + REFERENCE
%     A positive-displacement (gear/piston/screw) pump delivers a flow set by
%     its speed and displacement, essentially independent of the downstream
%     resistance, until the required head would exceed the unit's
%     working-pressure limit -- at that point an internal relief valve opens
%     and the flow drops below the commanded value (Karassik, I.J. et al.
%     (2008) "Pump Handbook", 4th ed., McGraw-Hill, Ch. 9 "Rotary Pumps"; Volk,
%     M. (2013) "Pump Characteristics and Applications", 3rd ed., CRC Press,
%     Ch. 9 -- the idealised PD-pump curve is a vertical line at Q = speed x
%     displacement, clipped horizontally at the relief-valve set pressure,
%     unlike a centrifugal pump's smooth head-flow parabola).
%
%   Sub-cases:
%     A  UNSATURATED (low resistance): the pump forces its commanded rated
%        flow, unaffected by Kbranch, exactly as the idealised PD curve says.
%     B  SATURATED (high resistance): the relief valve caps the head at dpMax,
%        so the flow falls below the commanded rate and matches the closed
%        form sqrt((dpMax+dpAvailable)/Kbranch).
%     C  TRANSITION BOUNDARY: at the exact Kbranch* where the unsaturated and
%        saturated formulas cross (Kbranch* = (dpMax+dpAvailable)/mdotRated^2),
%        the flow equals mdotRated from both sides -- continuous, no jump.
%     D  SPEED SCALING (unsaturated regime): commanded flow is exactly
%        proportional to the speed fraction, mdot = frac*mdotRated.
%     E  MINSPEED FLOOR: a commanded fraction below minSpeed is clamped to
%        minSpeed, exactly as CentrifugalPump.solveBranch already does (shared
%        Pump base-class contract).
%     F  CENTRAL-PUMP ROLE (curveHead): reports the relief-valve ceiling dpMax
%        while running (frac>0), 0 when stopped -- documented scope: the full
%        flow-vs-resistance physics of B-C is only modelled at the branch
%        (substation-pump) position.
%
%   WHY THIS TEST IS GOOD
%     A and B pin the two physical regimes of a PD pump against their closed
%     forms; C is the sharpest test of the two formulas -- they must meet
%     exactly at the boundary or the pump would show a discontinuous flow;
%     D and E confirm the same speed-command contract the centrifugal pump
%     honours (validate_pump.m); F documents the deliberately scoped
%     central-pump approximation so it is checked, not just asserted in a
%     comment.
%
%   EXPECTED OUTPUT: A, C, D, E exact to 1e-12; B matches the closed form to
%     1e-12; F exact.
%
%   Run:  >> V = validate_fixed_displacement_pump
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));

    mdotRated = 5;  dpMax = 3.0e5;  dpAvail = 0;
    pd = DHS.Hydraulic.FixedDisplacementPump('PD', 'mdotRated',mdotRated, 'dpMax',dpMax, 'minSpeed',0.15);

    % ---- A: unsaturated, low resistance ----
    KbrLow = 4000;
    [mA, hA] = pd.solveBranch(KbrLow, dpAvail, 1);
    eA = abs(mA - mdotRated) / mdotRated;
    okA_head = hA < dpMax;   % relief valve not open

    % ---- B: saturated, high resistance ----
    KbrHigh = 4.0e5;
    [mB, hB] = pd.solveBranch(KbrHigh, dpAvail, 1);
    mBref = sqrt((dpMax + dpAvail) / KbrHigh);
    eB = abs(mB - mBref) / mBref;
    eBhead = abs(hB - dpMax) / dpMax;
    okB_below = mB < mdotRated;

    % ---- C: transition boundary ----
    KbrStar = (dpMax + dpAvail) / mdotRated^2;
    [mC_at, ~] = pd.solveBranch(KbrStar, dpAvail, 1);
    [mC_below, ~] = pd.solveBranch(0.98*KbrStar, dpAvail, 1);   % just unsaturated side
    [mC_above, ~] = pd.solveBranch(1.02*KbrStar, dpAvail, 1);   % just saturated side
    eC = abs(mC_at - mdotRated) / mdotRated;
    % continuity: no jump larger than the 2% step in Kbranch could plausibly cause
    contJump = abs(mC_above - mC_below) / mdotRated;

    % ---- D: speed scaling, unsaturated regime ----
    fracs = [0.3 0.5 0.7 1.0];
    eD = 0;
    for fr = fracs
        [m,~] = pd.solveBranch(KbrLow, dpAvail, fr);
        eD = max(eD, abs(m - fr*mdotRated)/(fr*mdotRated));
    end

    % ---- E: minSpeed floor ----
    [mE, ~] = pd.solveBranch(KbrLow, dpAvail, 0.05);   % below minSpeed = 0.15
    eE = abs(mE - pd.minSpeed*mdotRated) / (pd.minSpeed*mdotRated);

    % ---- F: central-pump curveHead role ----
    hRun  = pd.curveHead(0, 1);
    hStop = pd.curveHead(0, 0);
    eF = abs(hRun - dpMax)/dpMax + abs(hStop - 0);

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(1) = mk('A  unsaturated: forced rated flow = mdotRated',    0, eA, 1e-12, 'abs');
    C(2) = mk('A  head stays below the relief-valve ceiling',     1, double(okA_head), 0, 'abs');
    C(3) = mk('B  saturated: mdot = sqrt((dpMax+dpAvail)/Kbr)',   mBref, mB, 1e-12, 'rel');
    C(4) = mk('B  head pinned at dpMax  (relief valve open)',     0, eBhead, 1e-9, 'abs');
    C(5) = mk('B  saturated flow is below the rated command',     1, double(okB_below), 0, 'abs');
    C(6) = mk('C  flow = mdotRated exactly at the transition Kbr*',0, eC, 1e-12, 'abs');
    C(7) = mk('C  no discontinuity crossing the transition',      0, contJump, 0.03, 'abs');
    C(8) = mk('D  unsaturated flow proportional to speed',        0, eD, 1e-12, 'abs');
    C(9) = mk('E  minSpeed floor clamps low speed commands',      0, eE, 1e-12, 'abs');
    C(10)= mk('F  central-pump curveHead reports dpMax / 0',      0, eF, 1e-9, 'abs');
    V.name = 'Fixed-displacement pump: rated-flow plateau, relief-valve cap, transition';
    V.passed = vtable(V.name, C);
    V.cases = C;  V.detail = struct('mA',mA,'mB',mB,'mBref',mBref,'KbrStar',KbrStar,'contJump',contJump);

    Kg = logspace(2, 6, 200);
    mg = arrayfun(@(K) pd.solveBranch(K, dpAvail, 1), Kg);
    mgRef = min(mdotRated, sqrt((dpMax+dpAvail)./Kg));
    vplot(mfilename, { ...
        struct('title','Flow against branch resistance at full speed', ...
            'xlabel','branch resistance  K  [Pa/(kg/s)^2]', 'ylabel','flow  [kg/s]', 'xscale','log', 'legendLoc','northeast', ...
            'series',{{ struct('x',Kg,'y',mgRef,'name','min(rated flow, relief-valve limit)','style','ref'), ...
                        struct('x',Kg,'y',mg,'name','solveBranch','style','sim') }}) }, plotMode);
end

function s = mk(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
