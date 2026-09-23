classdef Weather < handle
% DHS.WEATHER  Boundary-condition provider: outdoor air, ground, and solar.
%
%   Loads a Solcast-style CSV (irradiance from Solcast, outdoor and ground
%   temperature columns added from ECCC station data) and exposes fast interpolants of every
%   channel over simulation time. Part of the DES example, not of the RCBS
%   library.
%
%   EXPECTED COLUMNS (header names, any order)
%     ghi          global horizontal irradiance            [W/m^2]
%     dhi          diffuse horizontal irradiance           [W/m^2]
%     dni          direct normal irradiance                [W/m^2]
%     zenith       solar zenith angle                      [deg]  (0 = overhead)
%     azimuth      solar azimuth, Solcast convention       [deg]  (0 = N,
%                  negative = East, positive = West, +/-180 = S)
%     albedo       ground albedo                           [-]
%     period_end   ISO-8601 timestamp with fixed offset, END of the interval
%     t_outdoor_C  dry-bulb outdoor air temperature        [degC]   (added by tool)
%     t_ground_C   undisturbed ground temperature          [degC]   (added by tool)
%
%   TIME
%     "period_end" carries a fixed offset (e.g. -08:00). The offset is stripped
%     and the wall clock kept; the ECCC air temperature added by the tool is in
%     the same Local Standard Time, so all channels share one clock. Internally
%     time is seconds since the first sample (obj.t0).
%
%   USAGE
%     w = DHS.Weather('solar_data_2025.csv');
%     s = w.at(datetime(2025,1,1,12,0,0));      % struct of scalars at that time
%     s = w.at(3600);                           % or seconds since w.t0
%     % s.Tout [degC]  s.Tground [degC]  s.ghi s.dhi s.dni [W/m^2]
%     % s.sunZen s.sunAz [deg, COMPASS: 0=N,90=E,180=S,270=W]  s.sunEl [deg]
%     % s.albedo [-]
%
%   The compass azimuth is  mod(-azimuth_solcast, 360)  so it can be differenced
%   directly with surface azimuths (N=0, E=90, S=180, W=270) in DHS.Solar.

    properties (SetAccess = private)
        t0        datetime          % time of the first sample (defines t=0)
        tEnd      datetime
        csvPath   char
        raw       table
    end
    properties (Access = private)
        Fghi; Fdhi; Fdni; Fzen; Faz; Falb; Ftout; Ftgnd
        tsec  double                % sample times [s] since t0
        warned logical = false
    end

    methods
        function obj = Weather(csvPath)
            arguments
                csvPath (1,:) char
            end
            assert(isfile(csvPath), 'DHS:Weather:file', 'CSV not found: %s', csvPath);
            obj.csvPath = csvPath;
            T = readtable(csvPath, 'TextType', 'string', 'VariableNamingRule', 'preserve');
            obj.raw = T;

            ts   = string(T.("period_end"));
            tloc = datetime(extractBefore(ts, strlength(ts) - 5), ...
                            'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss');
            [tloc, ord] = sort(tloc);
            T = T(ord, :);

            obj.t0   = tloc(1);
            obj.tEnd = tloc(end);
            obj.tsec = seconds(tloc - obj.t0);

            get = @(name, alt) obj.column(T, name, alt);
            ghi  = get("ghi",  []);
            dhi  = get("dhi",  []);
            dni  = get("dni",  []);
            zen  = get("zenith", "zen");
            azS  = get("azimuth", "az");
            alb  = get("albedo", []);
            tout = get("t_outdoor_C", "Tout");
            tgnd = get("t_ground_C",  "Tground");

            if isempty(tout)
                error('DHS:Weather:noTemp', ['Column t_outdoor_C not found in %s. ' ...
                    'Add an outdoor-temperature column to the weather CSV.'], csvPath);
            end
            if isempty(tgnd)
                tgnd = 0.5*mean(tout) + 0*tout;   % crude fallback
                warning('DHS:Weather:noGround', 't_ground_C missing; using a flat estimate.');
            end

            azCompass = mod(-azS, 360);            % -> N=0,E=90,S=180,W=270

            mk = @(v) griddedInterpolant(obj.tsec, double(v), 'linear', 'nearest');
            obj.Fghi  = mk(ghi);   obj.Fdhi = mk(dhi);   obj.Fdni = mk(dni);
            obj.Fzen  = mk(zen);   obj.Faz  = mk(azCompass);
            obj.Falb  = mk(alb);   obj.Ftout = mk(tout);  obj.Ftgnd = mk(tgnd);
        end

        function s = at(obj, t)
            % AT  Sample every channel at time t (datetime, duration, or seconds).
            tq = obj.toSec(t);
            tol = 360;   % tolerate up to one ~5-min interval outside the grid silently
            if ~obj.warned && (tq < obj.tsec(1) - tol || tq > obj.tsec(end) + tol)
                warning('DHS:Weather:range', ...
                    'Query time outside data span [%s .. %s]; clamping.', ...
                    char(obj.t0), char(obj.tEnd));
                obj.warned = true;
            end
            s.ghi     = max(0, obj.Fghi(tq));
            s.dhi     = max(0, obj.Fdhi(tq));
            s.dni     = max(0, obj.Fdni(tq));
            s.sunZen  = obj.Fzen(tq);
            s.sunAz   = obj.Faz(tq);
            s.sunEl   = 90 - s.sunZen;
            s.albedo  = min(1, max(0, obj.Falb(tq)));
            s.Tout    = obj.Ftout(tq);
            s.Tground = obj.Ftgnd(tq);
        end

        function W = atVec(obj, tt)
            % ATVEC  Vectorised sampling: all channels at all times tt (datetime
            %   array / seconds vector) -> struct of column-vector fields with
            %   the same names as at(). Use this to pre-sample a whole run.
            tq = obj.toSec(tt); tq = tq(:);
            W.ghi     = max(0, obj.Fghi(tq));
            W.dhi     = max(0, obj.Fdhi(tq));
            W.dni     = max(0, obj.Fdni(tq));
            W.sunZen  = obj.Fzen(tq);
            W.sunAz   = obj.Faz(tq);
            W.sunEl   = 90 - W.sunZen;
            W.albedo  = min(1, max(0, obj.Falb(tq)));
            W.Tout    = obj.Ftout(tq);
            W.Tground = obj.Ftgnd(tq);
        end

        function tt = timeVector(obj)
            % TIMEVECTOR  All sample datetimes (for plotting / validation).
            tt = obj.t0 + seconds(obj.tsec);
        end

        function tq = toSec(obj, t)
            % TOSEC  Convert datetime / duration / numeric to seconds since t0.
            if isdatetime(t)
                tq = seconds(t - obj.t0);
            elseif isduration(t)
                tq = seconds(t);
            else
                tq = double(t);
            end
        end
    end

    methods (Static, Access = private)
        function v = column(T, primary, alt)
            % Return column 'primary' (or 'alt') as a double vector, else [].
            vn = string(T.Properties.VariableNames);
            hit = find(strcmpi(vn, primary), 1);
            if isempty(hit) && ~isempty(alt) && strlength(alt) > 0
                hit = find(strcmpi(vn, alt), 1);
            end
            if isempty(hit), v = []; else, v = double(T{:, hit}); end
        end
    end
end
