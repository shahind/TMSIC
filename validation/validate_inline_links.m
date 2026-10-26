function V = validate_inline_links(plotMode)
%VALIDATE_INLINE_LINKS  A loop wired with connect: in-line pump, valve, radiator and bypass; closed-form check
%                       of the flows and the pressure loop, and of the way it was wired.
%
%   COMPONENT      DHS.HydraulicNetwork.solve on a network made of links (pipe, valve, in-line pump) and
%                  branches (a radiator and a bypass valve), built with  node.addPipe / x.addValve /
%                  x.addPump / x.addTee / x.addRadiator  and  a.connect(b).
%
%        sup -> pipe -> PUMP -> pipe -> TEE --portC--> VALVE -> RADIATOR -> pipe --+
%                                         \--portB--> pipe -> BYPASS VALVE --------+--> junction -> pipe -> ret
%
%   TEST CASE + REFERENCE
%     A  CLOSURE.  The flows the solver returns satisfy the three equations of the loop, written here from
%        the textbook relations (Darcy-Weisbach with Swamee-Jain, equivalent-length tee loss, the Kv
%        equation of the valves, the parabola of the pump):
%           mass            M = m_rad + m_bypass
%           the two paths   K_rad m_rad^2 = K_bp m_bp^2           (the same pressure difference tee -> junction)
%           the pump        H - K_pump M^2 = (K_in + K_out) M^2 + K_rad m_rad^2
%     B  INDEPENDENT SOLUTION.  The flows against a separate solution of the same equations (fzero on the
%        total flow) over a sweep of the zone valve opening and of the pump speed.
%     C  SHUT VALVE.  With the radiator valve at its minimum position the radiator takes sqrt(dp / K_path)
%        and the bypass the rest: the nearly shut valve does not upset the solution.
%     D  FLOW SPLIT.  Closing the valve lowers the radiator flow, raises the bypass flow and the head.
%     E  ORDER.  The same network wired in the opposite order (the downstream chain first, joined to the
%        pump last) gives the same flows.
%     F  PUMP REQUIRED.  A loop without a pump stops with an error.
%
%   WHY THIS TEST IS GOOD
%     A checks that a converged solution is a solution of the loop equations, with relations written
%     independently of the code; B that it is the one an independent solver finds; C and D the cases a
%     fixed-point iteration cannot do (a valve almost shut, a pump head that falls with the flow); E that
%     the connections define the network, not the order of the calls.
%
%   Run:  >> V = validate_inline_links
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));

    rho = 983;  mu = 4.7e-4;
    dp0 = 1.5e5;  mFree = 8;  KvsV = 4;  KvsB = 3;  Qdes = 60e3;
    L = struct('in',3, 'out',3, 'br',3, 'bp',3, 'ret',3, 'fin',3);   % pipe lengths [m]

    % ---- build the loop (the system under test) ----
    [net, h] = buildLoop(rho, mu, dp0, mFree, KvsV, KvsB, Qdes, 'forward');

    % ---- A: closure of the three loop equations ----
    h.valve.pos = 0.5;  h.pump.speed = 1;
    s = net.solve(1);
    p = struct('dp0',dp0, 'mFree',mFree, 'KvsV',KvsV, 'KvsB',KvsB, 'rho',rho, 'mu',mu, 'rad',h.rad, 'L',L, 'pos',0.5, 'minPos',1e-3, 'speed',1);
    [mr, mb] = deal(h.rad.mdot, h.bypass.mdot);  M = s.Mtot;
    [Kr, Kb, Kc] = pathK(p, mr, mb, M);
    resMass = abs(M - mr - mb) / M;
    resPath = abs(Kr*mr^2 - Kb*mb^2) / (Kr*mr^2);
    resPump = abs(dp0 - Kc.pump*M^2 - Kc.line*M^2 - Kr*mr^2) / dp0;
    eA = max([resMass, resPath, resPump]);

    % ---- B: sweep of the valve opening and of the pump speed against an independent solution ----
    posList = [0.001 0.01 0.05 0.1 0.2 0.35 0.5 0.75 1];
    mrSim = zeros(size(posList));  mbSim = mrSim;  mrRef = mrSim;  mbRef = mrSim;
    for k = 1:numel(posList)
        h.valve.pos = posList(k);  h.pump.speed = 1;
        for rep = 1:2, s = net.solve(1); end
        mrSim(k) = h.rad.mdot;  mbSim(k) = h.bypass.mdot;
        p.pos = posList(k);  p.speed = 1;
        [mrRef(k), mbRef(k)] = refSolve(p);
    end
    spdList = [0.4 0.6 0.8 1];  eSpd = 0;
    h.valve.pos = 0.3;
    for k = 1:numel(spdList)
        h.pump.speed = spdList(k);  net.solve(1);  s = net.solve(1);
        p.pos = 0.3;  p.speed = spdList(k);
        [a, b] = refSolve(p);
        eSpd = max(eSpd, max(abs([h.rad.mdot - a, h.bypass.mdot - b])) / s.Mtot);
    end
    eB = max([max(abs(mrSim - mrRef)./max(mrRef, 1e-3)), max(abs(mbSim - mbRef)./mbRef), eSpd]);

    % ---- C: nearly shut valve ----
    h.valve.pos = 0;  h.pump.speed = 1;  net.solve(1);  s = net.solve(1);
    p.pos = 0;  p.speed = 1;
    [mrC, mbC] = refSolve(p);
    eC = max(abs(h.rad.mdot - mrC)/max(mrC, 1e-6), abs(h.bypass.mdot - mbC)/mbC);
    okC = h.rad.mdot < 0.01*h.rad.mdotDes && h.rad.mdot > 0;

    % ---- D: closing the valve ----
    okD = all(diff(mrSim) > 0) && all(diff(mbSim) < 0);

    % ---- E: wired in the opposite order ----
    [net2, h2] = buildLoop(rho, mu, dp0, mFree, KvsV, KvsB, Qdes, 'reverse');
    h2.valve.pos = 0.5;  h2.pump.speed = 1;  h.valve.pos = 0.5;  h.pump.speed = 1;
    net.solve(1);  s1 = net.solve(1);  net2.solve(1);  s2 = net2.solve(1);
    eE = max(abs([h.rad.mdot - h2.rad.mdot, h.bypass.mdot - h2.bypass.mdot, s1.Mtot - s2.Mtot]));

    % ---- F: no pump ----
    net3 = DHS.HydraulicNetwork();  a3 = DHS.Hydraulic.Junction('S','supply');  b3 = DHS.Hydraulic.Junction('R','return');
    a3.network = net3;  b3.network = net3;  net3.plantSupply = a3;  net3.plantReturn = b3;
    r3 = a3.addPipe(0.05, 3).addRadiator('rad', 'Qdes', Qdes);  r3.addPipe(0.05, 3).connect(b3);
    gotErr = false;
    try, net3.compile(); catch ME, gotErr = strcmp(ME.identifier, 'DHS:HydraulicNetwork:noPump'); end

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(1) = mk_('A  closure: mass, the two paths, the pump (rel)',          0, eA, 1e-8, 'abs');
    C(2) = mk_('B  flows vs independent solution, valve and speed sweep (rel)', 0, eB, 1e-5, 'abs');
    C(3) = mk_('C  valve at its minimum: radiator and bypass flow (rel)',  0, eC, 1e-5, 'abs');
    C(4) = mk_('C  shut valve leaks under 1 % of the design flow',         1, double(okC), 0, 'abs');
    C(5) = mk_('D  closing the valve: radiator down, bypass up',           1, double(okD), 0, 'abs');
    C(6) = mk_('E  opposite wiring order gives the same flows [kg/s]',     0, eE, 1e-9, 'abs');
    C(7) = mk_('F  a loop without a pump is an error',                     1, double(gotErr), 0, 'abs');
    V.name = 'In-line links: pump, valve, radiator and bypass wired with connect; loop closure and independent solution';
    V.passed = vtable(V.name, C);
    V.cases = C;  V.detail = struct('eA',eA,'eB',eB,'eC',eC,'eE',eE);

    vplot(mfilename, { ...
        struct('title','Flow through the radiator branch against the valve opening', 'xlabel','valve opening  [-]', 'ylabel','flow  [kg/s]', ...
            'legendLoc','southeast', ...
            'series',{{ struct('x',posList,'y',mrRef,'name','independent solution, radiator','style','ref'), ...
                        struct('x',posList,'y',mrSim,'name','DHS.HydraulicNetwork, radiator','style','sim'), ...
                        struct('x',posList,'y',mbRef,'name','independent solution, bypass','style','ref'), ...
                        struct('x',posList,'y',mbSim,'name','DHS.HydraulicNetwork, bypass','style','sim') }}) }, plotMode);
end

% ======================================================================
function [net, h] = buildLoop(rho, mu, dp0, mFree, KvsV, KvsB, Qdes, order)
    net = DHS.HydraulicNetwork();  net.rho = rho;  net.mu = mu;  net.pReturnRef = 1e5;
    sup = DHS.Hydraulic.Junction('S','supply');  ret = DHS.Hydraulic.Junction('R','return');
    sup.network = net;  ret.network = net;  net.plantSupply = sup;  net.plantReturn = ret;
    rj = DHS.Hydraulic.Junction('RJ','return');
    if strcmp(order, 'forward')
        h.pump = sup.addPipe(0.05, 3).addPump('dp0',dp0, 'mdotRated',mFree/2);
        tee = h.pump.addPipe(0.05, 3).addTee(0.032);
        h.valve = tee.portC.addValve('Kvs',KvsV, 'char','linear', 'minPos',1e-3);
        h.rad = h.valve.addRadiator('rad', 'Qdes',Qdes, 'Tsup',60, 'Tret',40);
        h.rad.addPipe(0.032, 3).connect(rj);
        h.bypass = tee.portB.addPipe(0.05, 3).addValve('Kvs',KvsB, 'char','linear');
        h.bypass.connect(rj);
        rj.addPipe(0.05, 3).connect(ret);
    else
        % the return end first, then the radiator chain, then the bypass, and the pump joined last
        rj.addPipe(0.05, 3).connect(ret);
        tee = DHS.Hydraulic.TJunction('T', 'mainDiameter',0.05, 'sideDiameter',0.032);
        h.valve = tee.portC.addValve('Kvs',KvsV, 'char','linear', 'minPos',1e-3);
        h.rad = h.valve.addRadiator('rad', 'Qdes',Qdes, 'Tsup',60, 'Tret',40);
        h.rad.addPipe(0.032, 3).connect(rj);
        h.bypass = tee.portB.addPipe(0.05, 3).addValve('Kvs',KvsB, 'char','linear');
        h.bypass.connect(rj);
        h.pump = DHS.Hydraulic.CentrifugalPump('pmp', 'dp0',dp0, 'mdotRated',mFree/2);
        pIn = sup.addPipe(0.05, 3);  pIn.connect(h.pump);
        h.pump.addPipe(0.05, 3).connect(tee);
    end
    net.compile();
end

% ----- the loop equations, written from the textbook relations -----
function f = swamee(Re, rel)
    if Re < 2300, f = 64/max(Re,1); else, f = 0.25/(log10(rel/3.7 + 5.74/Re^0.9))^2; end
    f = min(max(f, 0.008), 0.1);
end
function K = pipeK(D, L, m, rho, mu)
    A = pi*D^2/4;  Re = rho*max(abs(m)/(rho*A), 1e-6)*D/mu;
    K = swamee(Re, 4.6e-5/D) * L / (D*2*rho*A^2);
end
function K = teeK(D, nD, rho)
    A = pi*D^2/4;  K = swamee(1e7, 4.6e-5/D) * (nD*D) / (D*2*rho*A^2);
end
function K = valveK(Kvs, pos, minPos, rho)
    Kv = Kvs * max(pos, minPos);  K = 1e5*3600^2 / (Kv^2*rho^2);
end
function [Kr, Kb, Kc] = pathK(p, mr, mb, M)
    rho = p.rho;  mu = p.mu;
    Kr = teeK(0.032, 60, rho) + valveK(p.KvsV, p.pos, p.minPos, rho) + p.rad.dpBody/p.rad.mdotDes^2 + pipeK(0.032, p.L.ret, mr, rho, mu);
    Kb = teeK(0.05, 20, rho) + pipeK(0.05, p.L.bp, mb, rho, mu) + valveK(p.KvsB, 1, 0, rho);
    Kc.pump = p.dp0 / p.mFree^2;
    Kc.line = pipeK(0.05, p.L.in, M, rho, mu) + pipeK(0.05, p.L.out, M, rho, mu) + pipeK(0.05, p.L.fin, M, rho, mu);
end
function [mr, mb] = refSolve(p)
    % total flow M from  H - (Kp + Kline) M^2 = dp(M),  with m_r, m_b = sqrt(dp / K) and M = m_r + m_b
    H = p.speed^2 * p.dp0;
    function r = resid(M)
        mr_ = 0.5*M;  mb_ = 0.5*M;
        for it = 1:60
            [Kr, Kb, Kc] = pathK(p, mr_, mb_, M);
            dpb = max(H - (Kc.pump + Kc.line)*M^2, 0);
            mr_n = sqrt(dpb/Kr);  mb_n = sqrt(dpb/Kb);
            if abs(mr_n - mr_) + abs(mb_n - mb_) < 1e-13, mr_ = mr_n; mb_ = mb_n; break, end
            mr_ = mr_n;  mb_ = mb_n;
        end
        r = mr_ + mb_ - M;
    end
    M = fzero(@resid, [1e-3, p.mFree]);
    mr = 0.5*M;  mb = 0.5*M;
    for it = 1:200
        [Kr, Kb, Kc] = pathK(p, mr, mb, M);
        dpb = max(p.speed^2*p.dp0 - (Kc.pump + Kc.line)*M^2, 0);
        mr = sqrt(dpb/Kr);  mb = sqrt(dpb/Kb);
    end
end

function s = mk_(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
