function V = validate_schedule(plotMode)
%VALIDATE_SCHEDULE  Weekly occupancy / setpoint / internal-gain schedule.
%
%   COMPONENT      DHS.Schedule.isOccupied(t) / setpoint(t) / internalGain(t)
%
%   TEST CASE + REFERENCE
%     A commercial building schedule: occupied on workdays inside a daily window,
%     setback otherwise, with an optimal-start ramp and a radiant/convective
%     split of internal gains. Conforms to:
%       ASHRAE Standard 90.1-2019, Appendix G (prototype schedules for occupancy,
%         lighting and receptacle fractions);
%       National Energy Code of Canada for Buildings (NECB) 2020, Schedules A-G;
%       ASHRAE Handbook-Fundamentals (2021), Ch. 18 (internal-gain radiant
%         fractions: people ~ 0.30, equipment ~ 0.2-0.3, so a single 0.3 is a
%         standard simplification);
%       optimal start / pre-heat: CIBSE Guide H (2009), Sec. 3.
%
%   Sub-cases:
%     A  occupancy window: occupied exactly on [occStart, occEnd) on workdays,
%        never on the weekend (weekendOccupied = false)
%     B  weekend override: with weekendOccupied = true, occupied on Sat/Sun
%        inside the weekend window
%     C  setpoint = Tocc when occupied, Tsetback when unoccupied
%     D  optimal-start ramp: over the rampHours before occStart the setpoint is
%        linear from Tsetback to Tocc; slope = (Tocc - Tsetback)/rampHours;
%        value at occStart-  equals Tocc (continuity)
%     E  internal-gain split: Qmass = gainMassFraction * Qtot, Qair = Qtot - Qmass;
%        occupied -> gainOccW, unoccupied -> gainBaseW (default 0.15 * gainOccW)
%
%   WHY THIS TEST IS GOOD
%     The schedule sets the daily and weekly rhythm of the whole plant demand;
%     an off-by-one on the window edges, a wrong weekday code, a ramp that is not
%     continuous at hand-over, or a mis-split of the gains all show up as a
%     visibly wrong load shape. Each edge here is checked against the exact
%     specified rule.
%
%   Run:  >> V = validate_schedule
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));

    occS = 7;  occE = 18;  Tocc = 21;  Tset = 17;  ramp = 1;  gOcc = 1.2e5;  mf = 0.30;

    s = DHS.Schedule('occStartHour',occS,'occEndHour',occE, ...
        'Tocc',Tocc,'Tsetback',Tset,'rampHours',ramp, ...
        'gainOccW',gOcc,'gainMassFraction',mf,'weekendOccupied',false);

    day = @(h) datetime(2025,1,7) + hours(h);        % 2025-01-07 is a Tuesday
    sat = @(h) datetime(2025,1,4) + hours(h);        % Saturday

    % ---- A: occupancy window ----
    okA = ~s.isOccupied(day(occS - 0.01)) && s.isOccupied(day(occS + 0.01)) ...
        &&  s.isOccupied(day(occE - 0.01)) && ~s.isOccupied(day(occE + 0.01)) ...
        && ~s.isOccupied(sat(12));

    % ---- B: weekend override ----
    sB = DHS.Schedule('occStartHour',occS,'occEndHour',occE,'Tocc',Tocc,'Tsetback',Tset, ...
        'weekendOccupied',true,'weekendStartHour',10,'weekendEndHour',16);
    okB = ~sB.isOccupied(sat(9)) && sB.isOccupied(sat(12)) && ~sB.isOccupied(sat(17));

    % ---- C: setpoint levels ----
    okC = abs(s.setpoint(day(12)) - Tocc) < 1e-12 && abs(s.setpoint(day(3)) - Tset) < 1e-12;

    % ---- D: optimal-start ramp ----
    hs = linspace(occS - ramp + 1e-3, occS - 1e-3, 25);
    sp = arrayfun(@(h) s.setpoint(day(h)), hs);
    slopeMeas = (sp(end) - sp(1)) / (hs(end) - hs(1));          % degC per hour
    slopeRef  = (Tocc - Tset) / ramp;
    linRes = max(abs(sp - (Tset + (hs - (occS - ramp))/ramp * (Tocc - Tset))));
    contRes = abs(s.setpoint(day(occS - 1e-7)) - Tocc);      % ramp value just before hand-over

    % ---- E: internal-gain split ----
    [Qa, Qm, Qt] = s.internalGain(day(12));
    [~,  ~,  QtN] = s.internalGain(day(3));
    okE = abs(Qt - gOcc) < 1e-6 && abs(Qm/Qt - mf) < 1e-12 && abs((Qa+Qm) - Qt) < 1e-9 ...
        && abs(QtN - 0.15*gOcc) < 1e-6;

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(1) = mk('A  occupied exactly on [occStart, occEnd), not weekend', 1, double(okA), 0, 'abs');
    C(2) = mk('B  weekendOccupied override inside its window',          1, double(okB), 0, 'abs');
    C(3) = mk('C  setpoint = Tocc / Tsetback',                         1, double(okC), 0, 'abs');
    C(4) = mk('D  optimal-start ramp slope [degC/h]',   slopeRef, slopeMeas, 1e-6, 'rel');
    C(5) = mk('D  ramp is linear (max residual) [degC]',              0, linRes, 1e-9, 'abs');
    C(6) = mk('D  ramp meets Tocc at occStart (continuity) [degC]',    0, contRes, 1e-4, 'abs');
    C(7) = mk('E  gain split + occ/base levels correct',              1, double(okE), 0, 'abs');
    V.name = 'Occupancy / setpoint / internal-gain schedule vs the specified rules';
    V.passed = vtable(V.name, C);
    V.cases = C;  V.detail = struct('slopeMeas',slopeMeas,'slopeRef',slopeRef,'linRes',linRes,'contRes',contRes);

    % one week from Monday 2025-01-06 (Sat/Sun = 11th/12th), 5-min grid
    tg = datetime(2025,1,6) + minutes(0:5:7*1440);
    nT = numel(tg);  spW = zeros(1,nT);  occW = zeros(1,nT);  QtW = zeros(1,nT);
    for i = 1:nT
        spW(i)  = s.setpoint(tg(i));
        occW(i) = double(s.isOccupied(tg(i)));
        [~,~,QtW(i)] = s.internalGain(tg(i));
    end
    thr = hours(tg - tg(1));
    hod = mod(thr, 24);  dow = floor(thr/24);  wkd = dow < 5;
    spExp = Tset + 0*thr;
    onRamp = wkd & hod >= occS-ramp & hod < occS;
    spExp(onRamp) = Tset + (hod(onRamp) - (occS-ramp))/ramp * (Tocc - Tset);
    spExp(wkd & hod >= occS & hod < occE) = Tocc;
    vplot(mfilename, { ...
        struct('title','Heating setpoint over one week', 'xlabel','time  [h from Monday 00:00]', 'ylabel','setpoint  [\circC]', ...
            'legendLoc','southoutside', ...
            'series',{{ struct('x',thr,'y',spExp,'name','specified schedule','style','ref'), ...
                        struct('x',thr,'y',spW,'name','DHS.Schedule.setpoint','style','sim') }}) }, plotMode);
end

function s = mk(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
