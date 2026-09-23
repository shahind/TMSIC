classdef HeatExchanger < handle
% DHS.HEATEXCHANGER  Substation plate heat exchanger + its primary valve & pump.
%
%   Transfers heat from the district PRIMARY water to a building's SECONDARY
%   hydronic circuit by the effectiveness-NTU method (counterflow; Incropera &
%   DeWitt, "Fundamentals of Heat and Mass Transfer" 6e Sec.11.4). Heating-only:
%   delivered heat is clamped to [0, Qcap].
%
%       Cp = mdot_p*cp ;  Cmin = min(Cp, mdotSecNom*cp) ;  Cr = Cmin/Cmax
%       NTU = UA/Cmin
%       eps = (1-exp(-NTU(1-Cr)))/(1-Cr*exp(-NTU(1-Cr)))      (Cr < 1)
%           = NTU/(1+NTU)                                      (Cr -> 1)
%       Q   = clamp( eps*Cmin*(Tsup_primary - Tsec_in) , 0 , Qcap )
%       Tret_primary = Tsup_primary - Q/Cp
%
%   PRIMARY-SIDE PRESSURE LOSS  The valve (IEC 60534) plus the exchanger body
%   itself. The body loss is quoted, the same way a manufacturer's data sheet
%   does, as a design pressure drop dpNomPrimary at a design flow mdotNomPrimary
%   (typical plate heat exchanger primary-side design drop in a district-heating
%   substation is 20-60 kPa: Frederiksen, S. & Werner, S., "District Heating and
%   Cooling", Studentlitteratur, 2013), giving a fixed K = dpNomPrimary/mdotNomPrimary^2
%   -- the same dp ~ mdot^2 turbulent-flow form as a pipe or a valve, but sized to
%   each unit's own rating rather than one constant every instance shares.
%
%   Owns a pump and a valve on the primary side (obj.pump, obj.valve; a
%   DHS.Hydraulic.CentrifugalPump by default). Attach controllers to either:
%       hx.valve.attachController(c) ,  hx.pump.attachController(c)
%   or swap the pump type entirely:
%       hx.attachPump( DHS.Hydraulic.FixedDisplacementPump('P','mdotRated',4,'dpMax',2e5) )
%   Create with  building.addHeatExchanger('HX', 'UA',..,'Qcap',..).
%
%   PROPERTIES (SI)
%     name          char
%     UA            [W/K]   heat-exchanger conductance
%     Qcap          [W]     substation heat-delivery limit
%     mdotSecNom    [kg/s]  secondary-loop nominal mass flow
%     secApproach   [K]     emitter approach: secondary return into the HX = zone air + this
%     cp            [J/kg/K] water specific heat                         (4186)
%     dpNomPrimary  [Pa]    HX-body primary pressure drop at mdotNomPrimary (3.0e4)
%     mdotNomPrimary [kg/s] primary flow the dpNomPrimary rating is quoted at;
%                           defaults from Qcap/(cp*20 K) if left empty
%     valve         DHS.Hydraulic.Valve  (primary control valve)
%     pump          DHS.Hydraulic.Pump   (primary variable-speed pump)
%   LIVE STATE
%     Qdel        [W]     delivered heat this step
%     TretPrimary [degC]  primary return temperature this step

    properties
        name           (1,:) char = 'HX'
        UA             (1,1) double = 4.0e4
        Qcap           (1,1) double = 5.0e5
        mdotSecNom     (1,1) double = 6
        secApproach    (1,1) double = 28
        cp             (1,1) double = 4186
        dpNomPrimary   (1,1) double = 3.0e4
        mdotNomPrimary        double = []
        valve          DHS.Hydraulic.Valve
        pump                                   % a DHS.Hydraulic.Pump: the primary pump
    end
    properties (SetAccess = private)
        Qdel        (1,1) double = 0
        TretPrimary (1,1) double = NaN
    end
    properties (Access = ?DHS.Building)
        hostBuilding = []     % the DHS.Building this substation belongs to
    end

    methods
        function obj = HeatExchanger(name, varargin)
            if nargin >= 1, obj.name = name; end
            obj.valve = DHS.Hydraulic.Valve([name '.valve']);
            obj.pump  = DHS.Hydraulic.CentrifugalPump([name '.pump']);
            for i = 1:2:numel(varargin), obj.(varargin{i}) = varargin{i+1}; end
        end

        function attachPump(obj, p)
            % ATTACHPUMP  Install a pre-built primary pump (centrifugal or
            %   fixed-displacement) in place of the default.
            assert(isa(p,'DHS.Hydraulic.Pump'), 'DHS:HeatExchanger:pump', ...
                'Expected a DHS.Hydraulic.Pump.');
            if ~isempty(obj.hostBuilding), p.hostPort = obj.hostBuilding.inlet; end
            obj.pump = p;
        end

        function attachValve(obj, v)
            % ATTACHVALVE  Install a pre-built primary control valve.
            assert(isa(v,'DHS.Hydraulic.Valve'), 'DHS:HeatExchanger:valve', ...
                'Expected a DHS.Hydraulic.Valve.');
            obj.valve = v;
        end

        function j = inlet(obj)
            % INLET  Diagnostic port accessor -- the substation's own primary
            %   train (pump/valve/HX) is one lumped branch fed from the
            %   building's inlet junction; see DHS.Building.
            assert(~isempty(obj.hostBuilding), 'DHS:HeatExchanger:noHost', ...
                'Heat exchanger "%s" is not attached to a building yet.', obj.name);
            j = obj.hostBuilding.inlet;
        end

        function j = outlet(obj)
            % OUTLET  see inlet().
            assert(~isempty(obj.hostBuilding), 'DHS:HeatExchanger:noHost', ...
                'Heat exchanger "%s" is not attached to a building yet.', obj.name);
            j = obj.hostBuilding.outlet;
        end

        function [Qdel, TretP] = transfer(obj, mdotPrimary, TsupPrimary, TsecIn)
            % TRANSFER  eps-NTU heat transfer for the resolved primary flow.
            if mdotPrimary <= 1e-6 || TsupPrimary <= TsecIn
                Qdel = 0; TretP = TsupPrimary;
            else
                Cp   = mdotPrimary * obj.cp;
                Cs   = obj.mdotSecNom * obj.cp;
                Cmin = min(Cp, Cs);  Cmax = max(Cp, Cs);
                Cr   = Cmin / Cmax;
                NTU  = obj.UA / Cmin;
                if abs(1 - Cr) < 1e-6
                    eps = NTU / (1 + NTU);
                else
                    ex  = exp(-NTU * (1 - Cr));
                    eps = (1 - ex) / (1 - Cr * ex);
                end
                Qdel  = min(max(eps * Cmin * (TsupPrimary - TsecIn), 0), obj.Qcap);
                TretP = TsupPrimary - Qdel / Cp;
            end
            obj.Qdel = Qdel;  obj.TretPrimary = TretP;
        end

        function K = primaryResistance(obj, rho)
            % PRIMARYRESISTANCE  valve + HX-body hydraulic resistance [Pa/(kg/s)^2].
            mNom = obj.mdotNomPrimary;
            if isempty(mNom), mNom = max(obj.Qcap/(obj.cp*20), 0.5); end   % 20 K design drop
            Khx = obj.dpNomPrimary / mNom^2;
            K   = obj.valve.resistance(rho) + Khx;
        end
    end
end
