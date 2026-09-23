classdef Solar < handle
% DHS.SOLAR  Transmitted solar heat gain [W] for a single-zone building.
%
%   Part of the DES example. Computes solar heat OUTSIDE the RCBS RC model and
%   hands it back split by node (air / internal mass / opaque wall) so the
%   caller can inject it into the right RCBS node.
%
%   Transposes measured GHI / DHI / DNI onto each façade with the isotropic
%   (Liu & Jordan) sky model, then applies window area and solar heat gain
%   coefficient (SHGC) to get the heat entering the zone.
%
%   PLANE-OF-ARRAY IRRADIANCE  (Duffie & Beckman, "Solar Engineering of Thermal
%   Processes", 4th ed., Eq. 1.6.2 and 2.15.1; Liu & Jordan 1963):
%
%     cos(theta) = cos(theta_z) cos(beta) + sin(theta_z) sin(beta) cos(gamma_s - gamma)
%     I_POA = DNI * max(0, cos(theta))                      % beam
%           + DHI * (1 + cos(beta)) / 2                     % isotropic diffuse
%           + GHI * rho_g * (1 - cos(beta)) / 2             % ground reflected
%
%     theta_z  solar zenith [deg]        beta   surface tilt from horizontal [deg]
%     gamma_s  solar azimuth [deg]       gamma  surface azimuth [deg]
%     (azimuths in COMPASS convention here: N=0, E=90, S=180, W=270)
%
%   For vertical glazing beta = 90  ->  cos(theta) = sin(theta_z) cos(gamma_s - gamma),
%   diffuse term = DHI/2, ground term = GHI*rho/2.
%   For horizontal skylights beta = 0  ->  I_POA = GHI.
%
%   ZONE HEAT GAIN:
%     Q_solar = SUM_faces [ A_win,face * SHGC * I_POA,face ]  +  A_sky * SHGC_sky * GHI
%   Split between the air node and the internal-mass node by massFraction
%   (radiation absorbed by floor/furniture then released):
%     Q_air  = (1 - massFraction) * Q_solar
%     Q_mass = massFraction       * Q_solar
%
%   Optional opaque sol-air gain (disabled by default) adds, per opaque face,
%     Q_opaque = alphaOpaque * I_POA,face * (U_face / hOut) * A_face
%   routed to the wall/roof node (ASHRAE Handbook-Fundamentals, sol-air temp).
%
%   PROPERTIES (SI units)
%     winArea    struct with fields N,E,S,W  -> glazed area per orientation [m^2]
%     skyArea    horizontal skylight glazed area [m^2]                       (default 0)
%     SHGC       window solar heat gain coefficient [-]                      (default 0.40)
%     SHGCsky    skylight SHGC [-]                                           (default SHGC)
%     massFraction  fraction of transmitted solar sent to the mass node [-]  (default 0.10)
%     enableOpaque  logical, include opaque sol-air term                     (default false)
%     opaque     struct: areaN/E/S/W [m^2], areaRoof [m^2], U [W/m2K],
%                alpha [-], hOut [W/m2K]  (only used if enableOpaque)

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
