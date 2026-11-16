classdef Weather < handle
% DHS.WEATHER  Outdoor air, ground and solar data read from a CSV file.
%
%   w  = DHS.Weather('solar_data_2025.csv');
%   wx = w.at(datetime(2025,1,1,12,0,0));    % or w.at(seconds since w.t0)
%   wx: Tout, Tground [degC]; ghi, dhi, dni [W/m^2]; sunZen, sunAz, sunEl [deg, compass: 0=N 90=E 180=S 270=W];
%   albedo [-].
%
%   CSV columns: period_end (ISO 8601, end of the interval), ghi, dhi, dni, zenith, azimuth (Solcast
%   convention), albedo, t_outdoor_C, t_ground_C. The time offset is dropped and the wall clock kept.
%   See docs/dhs-weather-solar-schedule.md.

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
