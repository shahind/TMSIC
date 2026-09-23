classdef Schedule < handle
% DHS.SCHEDULE  Weekly occupancy schedule: heating setpoint + internal gains.
%
%   Part of the DES example (not the RCBS library). Produces the setpoint and
%   the internal-gain split that the caller injects into the RCBS zone nodes.
%
%   A commercial academic building is "occupied" on workdays between
%   occStartHour and occEndHour (optionally also on weekends, e.g. a library).
%   During occupied hours the heating setpoint is Tocc and internal gains are at
%   their full value; otherwise the setpoint drops to Tsetback and only base
%   (standby) internal gains remain.
%
%   References
%     ASHRAE Standard 90.1-2019, Appendix G and the accompanying schedules for
%       office / school occupancy, lighting and receptacle fractions.
%     National Energy Code of Canada for Buildings (NECB) 2020, schedules A-G.
%     ASHRAE Handbook-Fundamentals (2021), Ch.18 "Nonresidential Cooling and
%       Heating Load Calculations" -- internal gain densities and radiant/
%       convective split (~30% radiant to mass for people+equipment, higher for
%       lighting; a single 0.3 mass fraction is used here as a simplification).
%
%   PROPERTIES
%     occStartHour, occEndHour  [h]     occupied window on an occupied day (7, 18)
%     workdays        vector, MATLAB weekday() codes 1=Sun..7=Sat  (2:6 = Mon-Fri)
%     weekendOccupied logical           treat Sat/Sun as occupied too (false)
%     weekendStartHour, weekendEndHour  [h] window if weekendOccupied (9, 17)
%     Tocc            [degC]  occupied heating setpoint          (21)
%     Tsetback        [degC]  unoccupied heating setpoint        (16)
%     Tcool           [degC]  cooling setpoint (not used by the heating plant) (24)
%     gainOccW        [W]     total internal gain when occupied  (building-sized)
%     gainBaseW       [W]     internal gain when unoccupied      (~0.15*gainOccW)
%     gainMassFraction [-]    fraction of internal gain to the mass node (0.30)
%     preheatHours    [h]     start ramping to Tocc this many hours early (0)

    properties
        occStartHour     (1,1) double = 7
        occEndHour       (1,1) double = 18
        workdays         (1,:) double = 2:6
        weekendOccupied  (1,1) logical = false
        weekendStartHour (1,1) double = 9
        weekendEndHour   (1,1) double = 17
        Tocc             (1,1) double = 21
        Tsetback         (1,1) double = 16
        Tcool            (1,1) double = 24
        gainOccW         (1,1) double = 0
        gainBaseW        (1,1) double = 0
        gainMassFraction (1,1) double = 0.30
        preheatHours     (1,1) double = 0
        rampHours        (1,1) double = 0   % linear setpoint ramp Tsetback->Tocc before occStart
    end

    methods
        function obj = Schedule(varargin)
            for i = 1:2:numel(varargin)
                obj.(varargin{i}) = varargin{i+1};
            end
            if obj.gainBaseW == 0 && obj.gainOccW > 0
                obj.gainBaseW = 0.15 * obj.gainOccW;
            end
        end

        function tf = isOccupied(obj, t)
            % ISOCCUPIED  True if datetime t is within an occupied window.
            wd = weekday(t);                       % 1=Sun .. 7=Sat
            h  = hour(t) + minute(t)/60 + second(t)/3600;
            if ismember(wd, obj.workdays)
                tf = h >= (obj.occStartHour - obj.preheatHours) && h < obj.occEndHour;
            elseif obj.weekendOccupied
                tf = h >= obj.weekendStartHour && h < obj.weekendEndHour;
            else
                tf = false;
            end
        end

        function Tsp = setpoint(obj, t)
            % SETPOINT  Heating setpoint [degC] at datetime t.
            %   With rampHours > 0 the setpoint ramps linearly from Tsetback to
            %   Tocc over the rampHours window ending at occStartHour (optimal
            %   start) -- this spreads the morning recovery load and avoids the
            %   zone-temperature overshoot of a hard setpoint step.
            if obj.isOccupied(t)
                Tsp = obj.Tocc;
                return
            end
            Tsp = obj.Tsetback;
            if obj.rampHours > 0
                wd = weekday(t);
                h  = hour(t) + minute(t)/60 + second(t)/3600;
                if ismember(wd, obj.workdays)
                    s0 = obj.occStartHour - obj.rampHours;
                elseif obj.weekendOccupied
                    s0 = obj.weekendStartHour - obj.rampHours;
                else
                    return
                end
                if h >= s0 && h < s0 + obj.rampHours
                    frac = (h - s0) / obj.rampHours;
                    Tsp  = obj.Tsetback + frac*(obj.Tocc - obj.Tsetback);
                end
            end
        end

        function [Qair, Qmass, Qtot] = internalGain(obj, t)
            % INTERNALGAIN  Internal heat [W] at datetime t, split air / mass.
            if obj.isOccupied(t), Qtot = obj.gainOccW; else, Qtot = obj.gainBaseW; end
            Qmass = obj.gainMassFraction * Qtot;
            Qair  = Qtot - Qmass;
        end

        function [Tsp, Qair, Qmass] = at(obj, t)
            % AT  Convenience: setpoint and internal-gain split in one call.
            Tsp = obj.setpoint(t);
            [Qair, Qmass] = obj.internalGain(t);
        end
    end
end
