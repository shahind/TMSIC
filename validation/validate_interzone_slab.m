function V = validate_interzone_slab(plotMode)
%VALIDATE_INTERZONE_SLAB  Capacitive inter-zone element (partition wall / floor
%                         slab) vs ode45 and an analytic steady state.
%
%   COMPONENT      RCBS.Zone.connectToZone(other, R_total, name, C_mid, T0)
%                  -- inserts  R/2 - C_mid - R/2  between two zone AIR nodes,
%                  representing a shared partition wall or a floor/ceiling slab.
%
%   TEST CASE
%     Two zones (air capacitances C_A, C_B), each losing heat to a constant
%     outdoor temperature through its own window (R_ext), joined by one
%     capacitive slab (R_s total, mid mass C_s). A constant heat input Q into
%     zone A. Sub-cases:
%       (1) TRANSIENT: all three node temperatures vs ode45 on the 3-state system.
%       (2) STEADY STATE: analytic solution of the linear network.
%
%     Steady state (no source at the slab mid node, so at equilibrium the mid
%     node sits at the mean of the two air nodes):
%       Q = (T_A - T_out)/R_ext + (T_A - T_B)/R_s        (balance at A)
%       (T_A - T_B)/R_s = (T_B - T_out)/R_ext            (balance at B)
%     Solving:  let g = 1/R_ext , k = 1/R_s.
%       T_B = T_out + Q * k / (g*(g + 2*k))
%       T_A = T_out + Q * (g + k) / (g*(g + 2*k))
%
%   REFERENCE
%     The T-network for an interior partition / slab is the same lumped element
%     as a wall layer.
%
%   WHY THIS TEST IS GOOD
%     It exercises the part of RCBS that was newly extended: the mid node must be
%     created with capacitance C_mid, wired R/2 to zone A's air and R/2 to zone
%     B's air (a CROSS-zone resistor whose endpoint is a non-main node), and the
%     global node map must resolve that cross resistor to the right global
%     indices. Any of: missing mid capacitance, R vs R/2, wrong endpoint, or a
%     cross resistor collapsed to the zone main node -> the steady state and the
%     transient both deviate from the analytic / ode45 reference.
%
%   EXPECTED OUTPUT
%     transient max|T - ode45| < 0.03 degC over the whole 25-day approach;
%     converged T_A, T_B, T_mid match the analytic formulae to < 0.02 degC.
%
%   Run:  >> V = validate_interzone_slab
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));

    CA = 2.0e6;  CB = 2.0e6;  Cs = 8.0e6;
    Rext = 0.03;  Rs = 0.05;  Tout = 5;  Q = 1500;  T0 = 20;  dt = 30;

    b = RCBS.Building();
    b.addStorey('L');  b.addStorey('U');
    b.L.addZone('Z','C_main',CA);  b.L.Z.nodes(1).T = T0;  b.L.Z.addWindow(Rext,'W');
    b.U.addZone('Z','C_main',CB);  b.U.Z.nodes(1).T = T0;  b.U.Z.addWindow(Rext,'W');
    b.L.Z.connectToZone(b.U.Z, Rs, 'slab', Cs, T0);
    b.L.Z.connectToExternalSource(@(bb) Q, 'T_main');
    b.outdoorTempFunc = @(t) Tout;
    b.simulation.startDate = datetime(2025,1,1);  b.simulation.timeStep = seconds(dt);
    b.simulate(days(25));   % many time constants -> converged to steady state
    r  = b.simulation.results;
    ts = seconds(r.Time - r.Time(1));
    nn = string(b.simulation.nodeNames);
    iA = find(nn == "L.Z.T_main");  iM = find(nn == "L.Z.slab_c");  iB = find(nn == "U.Z.T_main");
    TA = r.Tall(:,iA);  TM = r.Tall(:,iM);  TB = r.Tall(:,iB);

    % ode45 reference (3-state)
    gh = 1/(Rs/2);  ge = 1/Rext;
    f = @(s,x)[ (gh*(x(2)-x(1)) + ge*(Tout-x(1)) + Q) / CA ;
                (gh*(x(1)-x(2)) + gh*(x(3)-x(2)))       / Cs ;
                (gh*(x(2)-x(3)) + ge*(Tout-x(3)))       / CB ];
    sol = ode45(f,[0 ts(end)],[T0;T0;T0],odeset('RelTol',1e-10,'AbsTol',1e-10));
    Xr = deval(sol, ts);
    eTr = max(max(abs([TA TM TB].' - Xr)));

    % analytic steady state
    g = 1/Rext;  k = 1/Rs;
    TB_an = Tout + Q*k       / (g*(g + 2*k));
    TA_an = Tout + Q*(g + k) / (g*(g + 2*k));

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(1) = mk('transient max|T - ode45| (3 nodes) [degC]', 0, eTr, 0.03, 'abs');
    C(2) = mk('steady T_A  (heated zone)  [degC]',  TA_an, TA(end), 0.02, 'abs');
    C(3) = mk('steady T_B  (coupled zone) [degC]',  TB_an, TB(end), 0.02, 'abs');
    C(4) = mk('steady slab mid = mean(T_A,T_B) [degC]', 0.5*(TA(end)+TB(end)), TM(end), 0.02, 'abs');
    V.name = 'Capacitive inter-zone slab (connectToZone) vs ode45 + analytic steady state';
    V.passed = vtable(V.name, C);
    V.cases = C;  V.detail = struct('eTransient',eTr,'TA',TA(end),'TB',TB(end),'TA_an',TA_an,'TB_an',TB_an);

    td = ts/86400;
    vplot(mfilename, { ...
        struct('title','Transient response of two coupled zones', 'xlabel','time  [days]', 'ylabel','temperature  [\circC]', ...
            'legendLoc','southeast', ...
            'series',{{ struct('x',td,'y',Xr(1,:).','name','heated zone (ode45)','style','ref'), ...
                        struct('x',td,'y',Xr(3,:).','name','coupled zone (ode45)','style','ref'), ...
                        struct('x',td,'y',TA,'name','heated zone','style','sim'), ...
                        struct('x',td,'y',TB,'name','coupled zone','style','sim') }}), ...
        struct('title','Steady-state temperatures', 'ylabel','temperature  [\circC]', 'kind','bars', ...
            'labels',{{'heated zone','coupled zone','slab mid-point'}}, ...
            'expected',[TA_an, TB_an, 0.5*(TA_an+TB_an)], 'actual',[TA(end), TB(end), TM(end)]) }, plotMode);
end

function s = mk(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
