function V = validate_radiator(plotMode)
%VALIDATE_RADIATOR  Radiator (water -> metal -> zone air): design point, step response, energy
%                   balance, flow dependence and no-flow decay; exchanger with a secondary flow.
%
%   COMPONENT      DHS.Radiator.response(mdot, Tin, Tzone, dt)  and  DHS.HeatExchanger.transfer(.., mdotInt)
%                    water cools along the radiator against the metal temperature Tm:
%                        Tout = Tm + (Tin - Tm) exp(-UAwm/(mdot cp))
%                    so the water-side conductance is  a(mdot) = mdot cp (1 - exp(-UAwm/(mdot cp)))
%                    and the metal (capacity C) gives heat to the zone air through UAma:
%                        C dTm/dt = a (Tin - Tm) - UAma (Tm - Tzone)         Qair = UAma (Tm - Tzone)
%
%   TEST CASE + REFERENCE
%     A  DESIGN POINT.  Sized from Qdes with the design temperatures, the radiator at steady state with
%        the design flow, supply temperature and air temperature gives exactly Qdes and the design
%        return temperature (closed form from the sizing relations).
%     B  STEP RESPONSE.  With constant inflow the metal temperature approaches its steady value as
%        Tm(t) = Tss + (Tm0 - Tss) exp(-(a + UAma) t / C), the exact solution of the linear ODE; the
%        backward-Euler step reproduces it to O(dt).
%     C  ENERGY BALANCE.  In every step  Qwater - Qair = C (Tm' - Tm)/dt  and  Qwater = mdot cp (Tin - Tout).
%     D  FLOW DEPENDENCE.  The effective water-to-metal conductance Qwater / (Tin - Tm') equals a(mdot)
%        at several flows; it rises with the flow and never exceeds UAwm or mdot cp. This is the
%        non-constant resistance the radiator model carries instead of a fixed R.
%     E  NO FLOW.  With the valve shut, Qwater = 0 and the metal relaxes to the zone temperature as
%        exp(-UAma t / C).
%     F  EXCHANGER WITH A SECONDARY FLOW.  Qdel = Cs (TsecOut - TsecIn) = Cp (Tsup - TretP), and a larger
%        secondary flow (more heat capacity rate) delivers more heat at the same temperatures.
%
%     G  INTEGRATORS.  The metal temperature can be advanced by 'backwardEuler' (default), 'forwardEuler' or
%        'exact' (r.integrator). For constant inputs 'exact' reproduces the solution of the ODE at any step
%        (here 10 minutes), forward Euler is first order (halving the step halves the error), and all three
%        keep the first law in every step (the heats are the step averages).
%
%   WHY THIS TEST IS GOOD
%     A ties the sizing to the model, B and E check the metal's dynamics against exact solutions, C
%     checks the first law in every step, D checks the flow-dependent resistance directly, and F that
%     the exchanger's secondary side conserves energy with the loop's actual flow.
%
%   Run:  >> V = validate_radiator
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));

    Qdes = 8e3;  cp = 4186;
    r = DHS.Radiator('R', 'Qdes', Qdes, 'Tsup', 70, 'Tret', 50, 'Tair', 20, 'epsDes', 0.9);

    % ---- A: design point at steady state ----
    m = r.mdotDes;  Tin = 70;  Ta = 20;
    a  = m*cp*(1 - exp(-r.UAwm/(m*cp)));
    Tss = (a*Tin + r.UAma*Ta) / (a + r.UAma);
    r.reset(Tss);
    [QairA, ToutA] = r.response(m, Tin, Ta, 60);
    eA = max(abs(QairA - Qdes)/Qdes, abs(ToutA - 50)/50);

    % ---- B: step response from the zone temperature ----
    r.reset(20);  dt = 1;  N = 2000;  Tm = zeros(1,N);  t = (1:N)*dt;
    for k = 1:N
        [Qa, To, TmN, Qw] = r.response(m, Tin, Ta, dt);
        r.store(m, Tin, To, Qw, Qa, TmN);  r.commit();  Tm(k) = TmN;
    end
    TmAn = Tss + (20 - Tss)*exp(-(a + r.UAma)*t/r.C);
    eB = max(abs(Tm - TmAn));

    % ---- C: energy balance in every step ----
    r.reset(25);  eC = 0;
    for k = 1:200
        mk = r.mdotDes*(0.2 + 0.8*abs(sin(k/17)));  Tk = 55 + 15*sin(k/31);  dtk = 30;
        Tm0 = r.Tmetal;
        [Qa, To, TmN, Qw] = r.response(mk, Tk, Ta, dtk);
        r.store(mk, Tk, To, Qw, Qa, TmN);  r.commit();
        eC = max([eC, abs((Qw - Qa) - r.C*(TmN - Tm0)/dtk)/max(Qw,1), abs(Qw - mk*cp*(Tk - To))/max(Qw,1)]);
    end

    % ---- D: water-side conductance against flow ----
    mg = r.mdotDes*[0.05 0.1 0.25 0.5 1 1.5 2];  aSim = zeros(size(mg));  aAn = aSim;
    for k = 1:numel(mg)
        r.reset(40);
        [~, ~, TmN, Qw] = r.response(mg(k), 70, Ta, 60);
        aSim(k) = Qw/(70 - TmN);
        aAn(k)  = mg(k)*cp*(1 - exp(-r.UAwm/(mg(k)*cp)));
    end
    eD = max(abs(aSim - aAn)./aAn);
    okD = all(diff(aSim) > 0) && all(aSim <= r.UAwm*(1+1e-12)) && all(aSim <= mg*cp*(1+1e-12));

    % ---- E: no flow ----
    r.reset(60);  Nn = 3000;  dtn = 1;  Te = zeros(1,Nn);  QwE = 0;
    for k = 1:Nn
        [Qa, To, TmN, Qw] = r.response(0, 70, Ta, dtn);
        r.store(0, 70, To, Qw, Qa, TmN);  r.commit();  Te(k) = TmN;  QwE = max(QwE, abs(Qw));
    end
    TeAn = Ta + (60 - Ta)*exp(-r.UAma*(1:Nn)*dtn/r.C);
    eE = max(abs(Te - TeAn));

    % ---- F: exchanger with a secondary flow ----
    hx = DHS.ENTUPlateHeatExchanger('X', 'UA',1.2e4, 'Qcap',1e9);
    mp = 2.0;  Tsup = 70;  TsecIn = 35;  eF = 0;  Qlist = zeros(1,3);  msList = [0.4 0.8 1.6];
    for j = 1:3
        ms = msList(j);
        [Qd, TrP, TsO] = hx.transfer(mp, Tsup, TsecIn, ms);
        Qlist(j) = Qd;
        eF = max([eF, abs(Qd - ms*cp*(TsO - TsecIn))/Qd, abs(Qd - mp*cp*(Tsup - TrP))/Qd]);
    end
    okF = all(diff(Qlist) > 0);

    % ---- G: integrators ----
    lam = (a + r.UAma)/r.C;
    r.integrator = 'exact';  r.reset(20);  dtG = 600;  eG1 = 0;
    for k = 1:6
        Tm0 = r.Tmetal;
        [Qa, To, TmN, Qw] = r.response(m, Tin, Ta, dtG);
        r.store(m, Tin, To, Qw, Qa, TmN);  r.commit();
        eG1 = max(eG1, abs(TmN - (Tss + (20 - Tss)*exp(-lam*k*dtG))));
        eG1 = max(eG1, abs((Qw - Qa) - r.C*(TmN - Tm0)/dtG)/max(Qw,1));
    end
    errFE = zeros(1,2);  dtList = [2 1];
    for j = 1:2
        r.integrator = 'forwardEuler';  r.reset(20);  nSteps = 100/dtList(j);  lawFE = 0;
        for k = 1:nSteps
            Tm0 = r.Tmetal;
            [Qa, To, TmN, Qw] = r.response(m, Tin, Ta, dtList(j));
            r.store(m, Tin, To, Qw, Qa, TmN);  r.commit();
            lawFE = max(lawFE, abs((Qw - Qa) - r.C*(TmN - Tm0)/dtList(j))/max(Qw,1));
        end
        errFE(j) = abs(r.Tmetal - (Tss + (20 - Tss)*exp(-lam*100)));
    end
    ratioFE = errFE(1)/errFE(2);
    okG = ratioFE > 1.8 && ratioFE < 2.2 && lawFE < 1e-9;
    r.integrator = 'backwardEuler';

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(1) = mk_('A  design point: Qair = Qdes and Tout = Tret (rel)',      0, eA, 1e-9, 'abs');
    C(2) = mk_('B  step response vs exact exponential [K]',               0, eB, 5e-2, 'abs');
    C(3) = mk_('C  first law in every step (rel)',                        0, eC, 1e-9, 'abs');
    C(4) = mk_('D  water-side conductance vs a(mdot) (rel)',              0, eD, 1e-9, 'abs');
    C(5) = mk_('D  conductance rises with flow, below UAwm and mdot cp',  1, double(okD), 0, 'abs');
    C(6) = mk_('E  no flow: Qwater = 0 [W]',                              0, QwE, 1e-9, 'abs');
    C(7) = mk_('E  no flow: metal relaxes to the zone vs exp [K]',        0, eE, 0.1, 'abs');
    C(8) = mk_('F  exchanger energy balance, both sides (rel)',           0, eF, 1e-12, 'abs');
    C(9) = mk_('F  more secondary flow delivers more heat',               1, double(okF), 0, 'abs');
    C(10) = mk_('G  exact integrator vs the ODE solution; first law [K]', 0, eG1, 1e-9, 'abs');
    C(11) = mk_('G  forward Euler is first order (error ratio 2); first law', 1, double(okG), 0, 'abs');
    V.name = 'Radiator: design point, step response, energy balance, flow-dependent conductance; exchanger with secondary flow';
    V.passed = vtable(V.name, C);
    V.cases = C;  V.detail = struct('eA',eA,'eB',eB,'eC',eC,'eD',eD,'eE',eE,'eF',eF,'UAwm',r.UAwm,'UAma',r.UAma,'C',r.C);

    vplot(mfilename, { ...
        struct('title','Metal temperature after a step in the water supply', 'xlabel','time  [s]', 'ylabel','T_{metal}  [\circC]', ...
            'legendLoc','southeast', ...
            'series',{{ struct('x',t,'y',TmAn,'name','exact exponential','style','ref'), ...
                        struct('x',t,'y',Tm,'name','DHS.Radiator','style','sim') }}), ...
        struct('title','Water-side conductance against flow', 'xlabel','flow / design flow  [-]', 'ylabel','a  [W/K]', ...
            'legendLoc','southeast', ...
            'series',{{ struct('x',mg/r.mdotDes,'y',aAn,'name','m c_p (1 - e^{-UA/(m c_p)})','style','ref'), ...
                        struct('x',mg/r.mdotDes,'y',aSim,'name','DHS.Radiator','style','sim') }}) }, plotMode);
end

function s = mk_(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
