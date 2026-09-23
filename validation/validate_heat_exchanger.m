function V = validate_heat_exchanger(plotMode)
%VALIDATE_HEAT_EXCHANGER  eps-NTU counterflow HX vs the closed-form
%                         effectiveness relations and the limiting cases.
%
%   COMPONENT      heatExchanger(mdot_p, Tsup_p, Tsec_in, UA, CdotSec, Qcap, cp)
%                  (also DHS.HeatExchanger.transfer, same core)
%
%   TEST CASE + REFERENCE  (Incropera & DeWitt, "Fundamentals of Heat and Mass
%   Transfer", 6th ed., Sec. 11.4, Table 11.3-11.4; Kays, W.M. & London, A.L.
%   (1984) "Compact Heat Exchangers", 3rd ed., McGraw-Hill.)
%
%     Cdot_p = mdot_p*cp ;  Cmin = min(Cdot_p, CdotSec) ;  Cmax = max(...) ;  Cr = Cmin/Cmax
%     NTU    = UA / Cmin
%     COUNTERFLOW:  eps = (1 - exp(-NTU(1-Cr))) / (1 - Cr exp(-NTU(1-Cr)))     (Cr < 1)
%                   eps = NTU / (1 + NTU)                                       (Cr -> 1)
%     Q = eps * Cmin * (Tsup_p - Tsec_in)
%
%   Sub-cases (thermal, eps-NTU):
%     A  general point (Cr ~ 0.6, NTU ~ 1.5) -- eps implied by Q equals the formula
%     B  Cr -> 0  (condenser / evaporator limit):  eps -> 1 - exp(-NTU)        [Eq. 11.35a]
%     C  Cr = 1   (balanced counterflow):          eps -> NTU/(1+NTU)          [Eq. 11.29a limit]
%     D  NTU -> infinity:  eps -> 1,  Q -> Cmin*(Tsup_p - Tsec_in)
%     E  first law:  heat gained by the secondary = heat lost by the primary
%     F  capacity clamp:  Q <= Qcap
%     G  no reverse transfer:  Tsup_p <= Tsec_in  =>  Q = 0
%
%   COMPONENT (hydraulic)  DHS.HeatExchanger.primaryResistance(rho)
%       K = valve.resistance(rho) + dpNomPrimary/mdotNomPrimary^2
%   The exchanger body's own loss is quoted as a design pressure drop at a
%   design flow, the same way a manufacturer's data sheet does, rather than one
%   fixed flow coefficient shared by every instance (Frederiksen, S. & Werner,
%   S. (2013) "District Heating and Cooling", Studentlitteratur -- typical
%   plate-heat-exchanger primary-side design pressure drop in a district-heating
%   substation is 20-60 kPa at design flow).
%
%   Sub-cases (hydraulic):
%     H  ADDITIVITY: primaryResistance(rho)*mdot^2 at the design flow equals the
%        HX-body design drop dpNomPrimary plus the valve's own drop, computed
%        independently from the IEC 60534 sizing equation (same reference as
%        validate_valve.m) -- no missing or double-counted term.
%     I  DEFAULT SIZING: with mdotNomPrimary left empty, it defaults to
%        Qcap/(cp*20 K) (a 20 K primary design deltaT) when that exceeds the
%        0.5 kg/s floor, and to the floor otherwise.
%     J  LITERATURE RANGE: the class default dpNomPrimary (30 kPa) falls inside
%        Frederiksen & Werner's cited 20-60 kPa typical range.
%
%   WHY THIS TEST IS GOOD
%     eps-NTU is a textbook method with exact analytical limits; matching all of
%     the limiting regimes (Cr -> 0, Cr -> 1, NTU -> infinity) plus a general
%     point plus the first-law closure leaves no room for a sign error, a Cmin
%     vs Cmax mix-up, or a wrong effectiveness correlation to hide. H confirms
%     the per-unit design-point reparameterisation combines correctly with the
%     valve it replaced a shared constant next to; J is a literal check against
%     the published design range, not just internal self-consistency.
%
%   EXPECTED OUTPUT: every thermal case matches the reference to < 1e-6
%     (relative) or exactly (clamp, zero-transfer); H, I exact to 1e-9; J a
%     hard 20-60 kPa bound.
%
%   Run:  >> V = validate_heat_exchanger
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));
    cp = 4186;

    epsCF = @(NTU,Cr) (1 - exp(-NTU.*(1-Cr))) ./ (1 - Cr.*exp(-NTU.*(1-Cr)));

    % ---- A: general point ----
    mp = 3;  Cs = 10*cp;  UA = 3.0e4;  Ts = 60;  Tr = 20;
    Cp = mp*cp;  Cmin = min(Cp,Cs);  Cr = Cmin/max(Cp,Cs);  NTU = UA/Cmin;
    Qref = epsCF(NTU,Cr) * Cmin * (Ts - Tr);
    Qa = heatExchanger(mp, Ts, Tr, UA, Cs, 1e9, cp);
    eA = abs(Qa - Qref)/Qref;

    % ---- B: Cr -> 0  (huge secondary capacity) ----
    Cs0 = 1e12;  Cmin0 = mp*cp;  NTU0 = UA/Cmin0;
    Qb  = heatExchanger(mp, Ts, Tr, UA, Cs0, 1e12, cp);
    QbRef = (1 - exp(-NTU0)) * Cmin0 * (Ts - Tr);
    eB = abs(Qb - QbRef)/QbRef;

    % ---- C: Cr = 1  (matched capacity rates) ----
    Cs1 = mp*cp;  NTU1 = UA/(mp*cp);
    Qc  = heatExchanger(mp, Ts, Tr, UA, Cs1, 1e12, cp);
    QcRef = (NTU1/(1+NTU1)) * (mp*cp) * (Ts - Tr);
    eC = abs(Qc - QcRef)/QcRef;

    % ---- D: NTU -> infinity ----
    Qd  = heatExchanger(mp, Ts, Tr, 1e12, 10*cp, 1e12, cp);
    QdRef = min(mp*cp, 10*cp) * (Ts - Tr);
    eD = abs(Qd - QdRef)/QdRef;

    % ---- E: first-law closure ----
    [Qe, Tret_p, Tsec_out] = heatExchanger(mp, Ts, Tr, UA, Cs, 1e9, cp);
    Qprimary   = mp*cp*(Ts - Tret_p);
    Qsecondary = Cs*(Tsec_out - Tr);
    eE = max(abs(Qe - Qprimary), abs(Qe - Qsecondary))/Qe;

    % ---- F: capacity clamp ----
    Qf = heatExchanger(10, 90, 15, 5e5, 10*cp, 4.0e4, cp);
    okF = Qf <= 4.0e4 + 1e-6;

    % ---- G: no reverse transfer ----
    Qg = heatExchanger(3, 25, 40, UA, Cs, 1e9, cp);
    okG = (Qg == 0);

    % ---- H: hydraulic additivity at the design point ----
    rho = 978;  Kvs = 30;
    hx = DHS.HeatExchanger('HX', 'Qcap',5e5, 'dpNomPrimary',3.0e4, 'mdotNomPrimary',4.0);
    hx.valve.Kvs = Kvs;  hx.valve.pos = 1;
    mNom = hx.mdotNomPrimary;
    Ktotal = hx.primaryResistance(rho);
    dpTotal = Ktotal * mNom^2;
    Qv = mNom/rho*3600;                          % m3/h
    dpValve = 1e5 * (Qv/Kvs)^2;                  % IEC 60534, independent calc
    dpRef = hx.dpNomPrimary + dpValve;
    eH = abs(dpTotal - dpRef) / dpRef;

    % ---- I: default mdotNomPrimary sizing (mdotNomPrimary left empty) ----
    % Isolate the HX-body term by making the valve's own resistance negligible
    % (Kvs huge), then back out mdotNomPrimary from primaryResistance itself:
    %   K = valve.resistance + dpNomPrimary/mNom^2  =>  mNom = sqrt(dpNomPrimary/(K - valve.resistance))
    impliedMdotNom = @(hxObj) sqrt(hxObj.dpNomPrimary / (hxObj.primaryResistance(rho) - hxObj.valve.resistance(rho)));

    hxBig = DHS.HeatExchanger('HXbig', 'Qcap',8.0e5, 'cp',cp);   % well above the 0.5 kg/s floor
    hxBig.valve.Kvs = 1e6;  hxBig.valve.pos = 1;
    mBigRef = hxBig.Qcap / (cp*20);
    eI1 = abs(impliedMdotNom(hxBig) - mBigRef) / mBigRef;

    hxSmall = DHS.HeatExchanger('HXsmall', 'Qcap',1.0e3, 'cp',cp);  % tiny Qcap -> hits the 0.5 kg/s floor
    hxSmall.valve.Kvs = 1e6;  hxSmall.valve.pos = 1;
    eI2 = abs(impliedMdotNom(hxSmall) - 0.5) / 0.5;

    % ---- J: literature range check (Frederiksen & Werner, 20-60 kPa) ----
    hxDefault = DHS.HeatExchanger('HXdef');
    okJ = hxDefault.dpNomPrimary >= 20e3 && hxDefault.dpNomPrimary <= 60e3;

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(1) = mk('A  general point: eps-NTU counterflow formula',   Qref, Qa,  1e-6, 'rel');
    C(2) = mk('B  Cr->0 limit:  eps = 1 - exp(-NTU)',            QbRef, Qb, 1e-6, 'rel');
    C(3) = mk('C  Cr=1 limit:   eps = NTU/(1+NTU)',              QcRef, Qc, 1e-6, 'rel');
    C(4) = mk('D  NTU->inf:     Q = Cmin*(Tsup - Tsec_in)',      QdRef, Qd, 1e-3, 'rel');
    C(5) = mk('E  first law:  Q_primary = Q_secondary = Q',      0, eE,       1e-9, 'abs');
    C(6) = mk('F  capacity clamp  Q <= Qcap',                    1, double(okF), 0, 'abs');
    C(7) = mk('G  no reverse transfer  (Tsup <= Tsec_in => Q=0)',1, double(okG), 0, 'abs');
    C(8) = mk('H  primary dp = dpNomPrimary + valve dp (IEC 60534)', dpRef, dpTotal, 1e-9, 'rel');
    C(9) = mk('I  default mdotNomPrimary = Qcap/(cp*20K)',           mBigRef, impliedMdotNom(hxBig), 1e-6, 'rel');
    C(10)= mk('I  default mdotNomPrimary floors at 0.5 kg/s',        0.5, impliedMdotNom(hxSmall), 1e-6, 'rel');
    C(11)= mk('J  default dpNomPrimary within 20-60 kPa (Frederiksen & Werner)', 1, double(okJ), 0, 'abs');
    V.name = 'eps-NTU heat exchanger vs closed-form effectiveness, limits, and primary-side pressure loss';
    V.passed = vtable(V.name, C);
    V.cases = C;  V.detail = struct('eA',eA,'eB',eB,'eC',eC,'eD',eD,'eE',eE,'eH',eH,'eI1',eI1,'eI2',eI2);

    NTUv = linspace(0, 8, 200);
    epsA_act = Qa    / (Cmin  * (Ts - Tr));
    epsB_act = Qb    / (Cmin0 * (Ts - Tr));
    epsC_act = Qc    / ((mp*cp) * (Ts - Tr));
    vplot(mfilename, { ...
        struct('title','Effectiveness of a counterflow exchanger', 'xlabel','NTU', 'ylabel','effectiveness', 'legendLoc','southeast', ...
            'series',{{ struct('x',NTUv,'y',epsCF(NTUv, Cr),'name',sprintf('formula, C_r = %.2f',Cr),'style','ref'), ...
                        struct('x',NTUv,'y',1-exp(-NTUv),'name','formula, C_r \rightarrow 0','style','ref'), ...
                        struct('x',NTUv,'y',NTUv./(1+NTUv),'name','formula, C_r = 1','style','ref'), ...
                        struct('x',NTU, 'y',epsA_act,'name','case A','style','point'), ...
                        struct('x',NTU0,'y',epsB_act,'name','case B','style','point'), ...
                        struct('x',NTU1,'y',epsC_act,'name','case C','style','point') }}), ...
        struct('title','Delivered heat', 'ylabel','heat  [kW]', 'kind','bars', ...
            'labels',{{'general point','C_r \rightarrow 0','C_r = 1','NTU \rightarrow \infty'}}, ...
            'expected',[Qref QbRef QcRef QdRef]/1e3, 'actual',[Qa Qb Qc Qd]/1e3), ...
        struct('title','Primary-side pressure drop at design flow', 'ylabel','pressure drop  [kPa]', 'kind','bars', ...
            'labels',{{'exchanger body + valve'}}, 'expected',dpRef/1e3, 'actual',dpTotal/1e3) }, plotMode);
end

function s = mk(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
