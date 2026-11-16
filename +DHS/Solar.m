classdef Solar < handle
% DHS.SOLAR  Solar heat gain through the windows of a building.
%
%   s = DHS.Solar('winArea', struct('N',20,'E',20,'S',20,'W',20), 'SHGC',0.4, 'massFraction',0.1);
%   [Qair, Qmass, Qwall, detail] = s.heatGain(wx);      % W, wx from DHS.Weather.at
%
%   Irradiance on each facade follows the isotropic sky model; Q = sum(A*SHGC*I). massFraction of the gain
%   goes to the internal-mass node. winArea [m^2] per facade; skyArea [m^2] and SHGCsky for a skylight;
%   enableOpaque and opaque add the sol-air gain of opaque surfaces. See docs/dhs-weather-solar-schedule.md.

    properties
        winArea      = struct('N',0,'E',0,'S',0,'W',0)
        skyArea      (1,1) double = 0
        SHGC         (1,1) double = 0.40
        SHGCsky      (1,1) double = NaN
        massFraction (1,1) double = 0.10
        enableOpaque (1,1) logical = false
        opaque       = struct('areaN',0,'areaE',0,'areaS',0,'areaW',0, ...
                              'areaRoof',0,'U',0.3,'alpha',0.6,'hOut',20)
    end

    properties (Constant, Access = private)
        FACE_AZ = struct('N',0,'E',90,'S',180,'W',270)
    end

    methods
        function obj = Solar(varargin)
            % DHS.Solar('winArea',struct('N',..,'E',..,'S',..,'W',..),'SHGC',..,...)
            for i = 1:2:numel(varargin)
                obj.(varargin{i}) = varargin{i+1};
            end
            if isnan(obj.SHGCsky), obj.SHGCsky = obj.SHGC; end
        end

        function [Qair, Qmass, Qwall, detail] = heatGain(obj, wx)
            % HEATGAIN  Solar heat [W] entering the zone for weather sample wx
            %   wx : struct from DHS.Weather.at(t) with fields
            %        ghi, dhi, dni [W/m^2], sunZen [deg], sunAz [deg, compass],
            %        albedo [-].
            %   Returns Qair, Qmass (transmitted, split by massFraction) and
            %   Qwall (opaque sol-air term, 0 unless enableOpaque), plus a
            %   detail struct with per-face POA irradiance [W/m^2].
            Qair = 0; Qmass = 0; Qwall = 0;
            detail = struct('poaN',0,'poaE',0,'poaS',0,'poaW',0,'poaRoof',wx.ghi);
            if wx.sunZen >= 90 || (wx.ghi <= 0 && wx.dni <= 0)
                return                                   % sun down
            end

            thz = wx.sunZen;  gs = wx.sunAz;  rho = wx.albedo;
            faces = {'N','E','S','W'};
            Qtrans = 0;
            for i = 1:4
                f  = faces{i};
                g  = obj.FACE_AZ.(f);
                cosAOI = sind(thz) * cosd(gs - g);        % vertical surface
                poa = wx.dni * max(0, cosAOI) + wx.dhi * 0.5 + wx.ghi * rho * 0.5;
                detail.(['poa' f]) = poa;
                Qtrans = Qtrans + obj.winArea.(f) * obj.SHGC * poa;
                if obj.enableOpaque
                    A = obj.opaque.(['area' f]);
                    Qwall = Qwall + obj.opaque.alpha * poa * (obj.opaque.U/obj.opaque.hOut) * A;
                end
            end
            % skylights (horizontal): I_POA = GHI
            Qtrans = Qtrans + obj.skyArea * obj.SHGCsky * wx.ghi;
            if obj.enableOpaque
                Qwall = Qwall + obj.opaque.alpha * wx.ghi * (obj.opaque.U/obj.opaque.hOut) * obj.opaque.areaRoof;
            end

            Qair  = (1 - obj.massFraction) * Qtrans;
            Qmass =      obj.massFraction  * Qtrans;
        end

        function A = totalWindowArea(obj)
            A = obj.winArea.N + obj.winArea.E + obj.winArea.S + obj.winArea.W + obj.skyArea;
        end
    end
end
