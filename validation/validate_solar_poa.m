function V = validate_solar_poa(plotMode)
%VALIDATE_SOLAR_POA  Isotropic-sky plane-of-array transposition (DHS.Solar)
%                    against the closed-form limiting cases.
%
%   COMPONENT      DHS.Solar.heatGain(wx)  ->  [Qair, Qmass, Qwall]
%                  POA per face:  I = DNI*max(0,cos th) + DHI*(1+cos b)/2
%                                     + GHI*rho*(1-cos b)/2
%                  Q_solar = sum_faces A_win * SHGC * I   (+ skylight A*SHGC*GHI)
%
%   TEST CASE + REFERENCE  (angle of incidence and the isotropic sky model)
%
%     cos(theta) = cos(theta_z) cos(beta) + sin(theta_z) sin(beta) cos(gamma_s - gamma)
%     For a VERTICAL wall (beta = 90):  cos(theta) = sin(theta_z) cos(gamma_s - gamma),
%     isotropic diffuse term = DHI/2,  ground-reflected term = GHI*rho/2.
%     For a HORIZONTAL skylight (beta = 0):  I = GHI.
%
%   Sub-cases (each isolates one transposition term with a hand value):
%     A  beam only, sun low due south (theta_z=88, gamma_s=180): cos(theta) on
%        the south wall = sin(88 deg)  ->  I_S = DNI*sin(88 deg)
%     B  isotropic diffuse only (DNI=0, GHI=DHI as required physically, albedo=0)
%        ->  each vertical face gets DHI/2 ; the skylight gets GHI = DHI
%     C  ground reflection only (DNI=DHI=0, GHI>0, albedo rho)  ->  vertical face GHI*rho/2
%     D  horizontal skylight  ->  I = GHI exactly
%     E  night (theta_z >= 90 and no irradiance)  ->  all outputs zero
%     F  south vs north window under a low southern winter sun: Q_S >> Q_N
%     G  air/mass split by massFraction:  Qmass/(Qair+Qmass) = massFraction
%
%   WHY THIS TEST IS GOOD
%     Each of A-D pins exactly one term of the isotropic transposition against a
%     value you can compute by hand; a sign error in the
%     azimuth convention, a factor-of-two in the view factors, or a wrong tilt
%     assumption breaks at least one of them. E and G check the housekeeping.
%
%   Run:  >> V = validate_solar_poa
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));

    SHGC = 0.5;  mf = 0.12;
    AS = 40;  AN = 40;  AE = 30;  AW = 30;  Asky = 10;
    sg = DHS.Solar('winArea', struct('N',AN,'E',AE,'S',AS,'W',AW), ...
                   'skyArea', Asky, 'SHGC', SHGC, 'massFraction', mf);

    % ---- A: beam only, sun low due south (zenith 88 so the model does not treat
    %        it as "sun down"; direct only, no diffuse, no ground) ----
    DNI = 700;  zenA = 88;
    wxA = wx(1e-6, 0, DNI, zenA, 180, 0.0);
    [QaA, QmA] = sg.heatGain(wxA);
    QtotA = QaA + QmA;
    QrefA = AS*SHGC*DNI*sind(zenA);            % S face: cos(theta) = sin(theta_z); N,E,W: cos<0 -> 0
    eA = abs(QtotA - QrefA)/QrefA;

    % ---- B: isotropic diffuse only.  Physically GHI = DNI*cos(zen) + DHI, so
    %        with DNI = 0 the global equals the diffuse; albedo 0 kills the
    %        ground term, isolating the DHI/2 sky-view factor on each wall ----
    DHI = 120;
    wxB = wx(DHI, DHI, 0, 60, 180, 0.0);
    [QaB, QmB] = sg.heatGain(wxB);
    QtotB = QaB + QmB;
    QrefB = (AN+AE+AS+AW)*SHGC*(DHI/2) + Asky*SHGC*DHI;   % skylight I = GHI = DHI
    eB = abs(QtotB - QrefB)/QrefB;

    % ---- C: ground reflection only ----
    GHI = 300;  rho = 0.35;
    wxC = wx(GHI, 0, 0, 80, 180, rho);
    [QaC, QmC] = sg.heatGain(wxC);
    QtotC = QaC + QmC;
    Qvert = (AN+AE+AS+AW)*SHGC*(GHI*rho/2);
    Qsky  = Asky*SHGC*GHI;                     % horizontal skylight: I = GHI
    QrefC = Qvert + Qsky;
    eC = abs(QtotC - QrefC)/QrefC;

    % ---- D: skylight only (isolate with a skylight-only solar object) ----
    sgk = DHS.Solar('winArea', struct('N',0,'E',0,'S',0,'W',0), 'skyArea', Asky, 'SHGC', SHGC);
    wxD = wx(GHI, 0, 0, 80, 180, 0.2);
    [QaD, QmD] = sgk.heatGain(wxD);
    QrefD = Asky*SHGC*GHI;
    eD = abs((QaD+QmD) - QrefD)/QrefD;

    % ---- E: night ----
    [QaE, QmE, QwE] = sg.heatGain(wx(0,0,0,110,0,0.2));
    okE = (QaE + QmE + QwE) == 0;

    % ---- F: south vs north under a low southern sun ----
    wxF = wx(300, 90, 620, 74, 180, 0.2);     % winter noon, sun ~16 deg elevation, due south
    sS = DHS.Solar('winArea', struct('N',0,'E',0,'S',100,'W',0), 'SHGC', SHGC);
    sN = DHS.Solar('winArea', struct('N',100,'E',0,'S',0,'W',0), 'SHGC', SHGC);
    QS = sum([sS.heatGain(wxF)]); QN = sum([sN.heatGain(wxF)]);
    okF = QS > 5*QN && QN >= 0;

    % ---- G: air/mass split ----
    eG = abs(QmB/(QaB+QmB) - mf);

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(1) = mk('A  beam, sun low due south:  I_S = DNI sin(theta_z)', QrefA, QtotA, 1e-9, 'rel');
    C(2) = mk('B  isotropic diffuse:  wall I = DHI/2, sky I = DHI',   QrefB, QtotB, 1e-9, 'rel');
    C(3) = mk('C  ground reflection on vertical:  I = GHI*rho/2',QrefC, QtotC, 1e-9, 'rel');
    C(4) = mk('D  horizontal skylight:  I = GHI',               QrefD, QaD+QmD, 1e-9, 'rel');
    C(5) = mk('E  night -> zero gain',                          1, double(okE), 0, 'abs');
    C(6) = mk('F  low southern sun:  Q_S > 5 Q_N',              1, double(okF), 0, 'abs');
    C(7) = mk('G  air/mass split = massFraction',               0, eG, 1e-12, 'abs');
    V.name = 'Isotropic solar transposition (DHS.Solar) vs hand-computed limiting cases';
    V.passed = vtable(V.name, C);
    V.cases = C;  V.detail = struct('eA',eA,'eB',eB,'eC',eC,'eD',eD,'QS',QS,'QN',QN,'eG',eG);

    % directional check: one 100 m^2 window per orientation, sun swept in azimuth
    az = 0:4:360;  zen = 70;  dni = 600;  dhi = 100;  ghi = dni*cosd(zen) + dhi;
    faces = {'S','E','N','W'};  Qdir = zeros(numel(faces), numel(az));
    for fi = 1:numel(faces)
        wa = struct('N',0,'E',0,'S',0,'W',0);  wa.(faces{fi}) = 100;
        so = DHS.Solar('winArea', wa, 'SHGC', SHGC);
        for a = 1:numel(az)
            Qdir(fi,a) = sum([so.heatGain(wx(ghi,dhi,dni,zen,az(a),0.2))]);
        end
    end
    vplot(mfilename, { ...
        struct('title','Window solar gain in four limiting cases', 'ylabel','solar gain  [W]', 'kind','bars', ...
            'labels',{{'direct beam','isotropic diffuse','ground reflection','horizontal skylight'}}, ...
            'expected',[C(1:4).expected], 'actual',[C(1:4).actual]) }, plotMode);
end

function w = wx(ghi, dhi, dni, zen, az, alb)
    w = struct('ghi',ghi,'dhi',dhi,'dni',dni,'sunZen',zen,'sunAz',az, ...
               'sunEl',90-zen,'albedo',alb);
end

function s = mk(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
