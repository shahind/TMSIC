function V = validate_building_energy_balance(plotMode)
%VALIDATE_BUILDING_ENERGY_BALANCE  Whole multi-node / multi-zone RCBS building:
%                                  first-law closure and steady-state UA.
%
%   COMPONENT      RCBS.Building + RCBS.Simulation  (the assembled thermal model
%                  a DHS.Building wraps), exercised as a stand-alone RC network.
%
%   TEST CASE + REFERENCE
%     (1) TRANSIENT ENERGY CLOSURE.  For any constant-coefficient RC network the
%         implicit (backward-Euler) update satisfies the discrete first law
%         exactly:
%             sum_k Q_in,k dt  -  sum_k Q_out-to-outdoor,k dt  =  Delta[ sum_i C_i T_i ]
%         where Q_out is the total heat flux leaving to the outdoor boundary,
%         summed over EVERY resistor that ends at 'outdoor' (windows, infiltration,
%         and the outer half-resistor of each wall/roof T-network -- each using
%         its own upstream node temperature).  Internal conduction only moves
%         energy between nodes; it cancels.  Any leak in the assembly -- a
%         dropped conductance, a double-counted capacitance, a mis-signed
%         outdoor coupling -- opens this balance.
%     (2) STEADY-STATE UA.  With constant boundary conditions and a constant heat
%         input Q into a single-zone building, at equilibrium
%             Q = UA_total * (T_zone - T_out) ,
%             UA_total = 1/R_wall + 1/R_roof + 1/R_win + 1/R_inf
%         (whole-building UA).
%         The wall/roof T-network mid nodes carry no source, so at steady state
%         the flux through a wall equals (T_zone - T_out)/R_wall,total.
%     (3) MULTI-ZONE CLOSURE.  The same first-law check on a 2-storey x 2-zone
%         building with partition + slab coupling: energy still closes despite
%         the extra inter-zone paths and mid-node masses.
%
%   WHY THIS TEST IS GOOD
%     Energy conservation is a property the model must have regardless of any
%     analytical solution; checking it to machine precision on the full
%     multi-node and multi-zone assemblies is the strongest structural check on
%     the whole RC layer.  The steady-state UA additionally pins the absolute
%     scale of the envelope losses.
%
%   Run:  >> V = validate_building_energy_balance
    if nargin < 1 || isempty(plotMode), plotMode = 'show'; end
    here = fileparts(mfilename('fullpath'));  addpath(here, fileparts(here));

    % ================= (1) + (2): single-zone building =================
    %   realistic UA (~130 W/K) and modest capacitances so the steady state is
    %   reached in days, not years
    Cair = 3e5;  Cw = 1.5e6;  Cr = 6e5;  Cm = 2.5e6;
    Rw = 0.02;  Rr = 0.03;  Rwin = 0.05;  Rinf = 0.04;  Rmass = 3e-4;
    T0 = 20;
    mkB = @() one(Cair, Cw, Cr, Cm, Rw, Rr, Rwin, Rinf, Rmass, T0);
    UA = 1/Rw + 1/Rr + 1/Rwin + 1/Rinf;

    % --- transient closure ---
    b = mkB();
    b.outdoorTempFunc = @(t) 3 + 9*sin(2*pi*hour(t)/24);
    b.S.Z.connectToExternalSource(@(bb) 6000*(hour(bb.simulation.t)>=6 && hour(bb.simulation.t)<20),'T_main');
    b.simulation.startDate = datetime(2025,1,1);  b.simulation.timeStep = seconds(60);  b.simulate(days(3));
    [eClose1, s1] = firstLawResidual(b, 60, @(tt) 6000*(hour(tt)>=6 && hour(tt)<20), {'S.Z.T_main'});

    % --- steady-state UA ---
    Q = 4000;  Toc = 2;
    bs = mkB();  bs.outdoorTempFunc = @(t) Toc;
    bs.S.Z.connectToExternalSource(@(bb) Q, 'T_main');
    bs.simulation.startDate = datetime(2025,1,1);  bs.simulation.timeStep = seconds(60);  bs.simulate(days(60));
    Tz_ss = bs.simulation.results.S.Z.T(end);
    UA_meas = Q / (Tz_ss - Toc);
    eUA = abs(UA_meas - UA) / UA;

    % ================= (3): multi-zone building closure =================
    bm = twoBytwo(T0);
    bm.outdoorTempFunc = @(t) 4 + 8*sin(2*pi*hour(t)/24);
    bm.S1.Big.connectToExternalSource(@(bb) 9000*(hour(bb.simulation.t)>=7 && hour(bb.simulation.t)<19),'T_main');
    bm.simulation.startDate = datetime(2025,1,1);  bm.simulation.timeStep = seconds(60);  bm.simulate(days(3));
    eClose3 = firstLawResidual(bm, 60, @(tt) 9000*(hour(tt)>=7 && hour(tt)<19), {'S1.Big.T_main'});

    C = struct('label',{},'expected',{},'actual',{},'tol',{},'kind',{});
    C(1) = mk('(1) single-zone transient energy-balance residual',   0, eClose1, 1e-9, 'abs');
    C(2) = mk('(2) steady-state UA  Q/(Tzone-Tout) vs sum(1/R)',     UA, UA_meas, 1e-4, 'rel');
    C(3) = mk('(3) 2x2 multi-zone transient energy-balance residual', 0, eClose3, 1e-9, 'abs');
    V.name = 'Whole building (multi-node + multi-zone): first-law closure + steady-state UA';
    V.passed = vtable(V.name, C);
    V.cases = C;  V.detail = struct('UA',UA,'UA_meas',UA_meas,'eUA',eUA,'eClose1',eClose1,'eClose3',eClose3);

    rss = bs.simulation.results;
    tss = seconds(rss.Time - rss.Time(1)) / 86400;               % days
    vplot(mfilename, { ...
        struct('title','Energy balance over the run', 'xlabel','time  [h]', 'ylabel','cumulative energy  [kWh]', 'legendLoc','northwest', ...
            'series',{{ struct('x',s1.t,'y',s1.stored_plus_out,'name','stored + lost to outdoors','style','ref'), ...
                        struct('x',s1.t,'y',s1.Ein,'name','heat supplied','style','sim') }}), ...
        struct('title','Steady-state zone temperature', 'xlabel','time  [days]', 'ylabel','zone temperature  [\circC]', 'legendLoc','southeast', ...
            'series',{{ struct('x',tss,'y',(Toc + Q/UA) + 0*tss,'name','T_{out} + Q/UA','style','ref'), ...
                        struct('x',tss,'y',rss.S.Z.T,'name','RCBS.Building','style','sim') }}) }, plotMode);
end

% ---------------------------------------------------------------------------
function [res, S] = firstLawResidual(b, dt, Qfcn, heatedNodes)
%   sum Qin dt - sum Qout dt  ==  Delta sum(C .* T)   (relative to Ein)
    r    = b.simulation.results;
    tv   = r.Time;
    Tall = r.Tall;                                   % (nt x N)
    nn   = string(b.simulation.nodeNames);
    Tout = r.OutdoorTemperature;

    [~, ni] = b.simulation.buildNodeMap();
    Cvec = cellfun(@(s) s.C, ni).';                  % (N x 1)

    % all resistors ending at 'outdoor', with their upstream node name
    O = struct('node',{},'R',{});
    for s = 1:numel(b.storeyList)
        sn = b.storeyList{s};  st = b.(sn);
        for z = 1:numel(st.zoneList)
            zn = st.zoneList{z};  zo = st.(zn);
            for k = 1:numel(zo.resistors)
                rr = zo.resistors(k);
                if ischar(rr.n2) && strcmp(rr.n2,'outdoor')
                    O(end+1) = struct('node',[sn '.' zn '.' zo.nodes(rr.n1).name], 'R', rr.R); %#ok<AGROW>
                end
            end
        end
    end

    Qout = zeros(numel(tv)-1, 1);
    for e = 1:numel(O)
        Te = Tall(2:end, nn == string(O(e).node));   % end-of-step temperature
        Qout = Qout + (Te - Tout(2:end)) / O(e).R;
    end
    Qin = zeros(numel(tv)-1, 1);
    for h = 1:numel(heatedNodes) %#ok<*NASGU>
        Qin = Qin + arrayfun(@(k) Qfcn(tv(k)), (1:numel(tv)-1)');
    end
    Ein    = sum(Qin) * dt;
    Eout   = sum(Qout) * dt;
    Estore = sum(Cvec .* (Tall(end,:).' - Tall(1,:).'));
    res = abs(Ein - (Estore + Eout)) / abs(Ein);

    if nargout > 1
        EinC   = cumsum(Qin)  * dt;
        EoutC  = cumsum(Qout) * dt;
        EstoC  = (Tall(2:end,:) - Tall(1,:)) * Cvec;      % (nt-1 x 1) cumulative storage
        S = struct('t', seconds(tv(2:end) - tv(1)) / 3600, ...  % hours
                   'Ein', EinC/3.6e6, 'stored_plus_out', (EstoC + EoutC)/3.6e6);  % kWh
    end
end

function b = one(Cair, Cw, Cr, Cm, Rw, Rr, Rwin, Rinf, Rmass, T0)
    b = RCBS.Building(); b.addStorey('S'); b.S.addZone('Z','C_main',Cair);
    b.S.Z.setAir(Cair, T0);
    b.S.Z.addInternalMass(Rmass, Cm, T0, 'IntMass');
    b.S.Z.addWall(Rw, Cw, T0, 'Wall');
    b.S.Z.addRoof(Rr, Cr, T0, 'Roof');
    b.S.Z.addWindow(Rwin, 'Window');
    b.S.Z.addWindow(Rinf, 'InfVent');
end

function b = twoBytwo(T0)
    b = RCBS.Building();
    for k = 1:2
        s = sprintf('S%d', k);  b.addStorey(s);
        for z = {'Big','Small'}
            zz = z{1};  A = 0.6; if strcmp(zz,'Small'), A = 0.4; end
            b.(s).addZone(zz, 'C_main', 3e6*A);  b.(s).(zz).setAir(3e6*A, T0);
            b.(s).(zz).addInternalMass(5e-3/A, 4e7*A, T0, 'IntMass');
            b.(s).(zz).addWall(3.0/A, 1.5e7*A, T0, 'Wall');
            b.(s).(zz).addWindow(0.8/A, 'Window');
            b.(s).(zz).addWindow(1.2/A, 'InfVent');
            if k == 2, b.(s).(zz).addRoof(5.0/A, 8e6*A, T0, 'Roof'); end
        end
        b.(s).Big.connectToZone(b.(s).Small, 0.05, sprintf('part_%s',s), 4e6, T0);
    end
    b.S1.Big.connectToZone(b.S2.Big,     0.02, 'slab_B', 1.2e7, T0);
    b.S1.Small.connectToZone(b.S2.Small, 0.02, 'slab_S', 0.8e7, T0);
end

function s = mk(label, expected, actual, tol, kind)
    s = struct('label',label,'expected',expected,'actual',actual,'tol',tol,'kind',kind);
end
