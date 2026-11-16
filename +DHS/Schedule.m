classdef Schedule < handle
% DHS.SCHEDULE  Weekly occupancy: heating setpoint and internal gains.
%
%   s = DHS.Schedule('occStartHour',7, 'occEndHour',18, 'Tocc',21, 'Tsetback',18, 'gainOccW',20e3);
%   [Tsp, Qair, Qmass] = s.at(t);        % t is a datetime
%
%   occStartHour, occEndHour [h] (7, 18); workdays (weekday codes, 2:6); weekendOccupied, weekendStartHour,
%   weekendEndHour; Tocc, Tsetback [degC] (21, 16); rampHours [h] ramps the setpoint up before occupancy;
%   preheatHours [h]; gainOccW, gainBaseW [W] (base defaults to 15 % of gainOccW); gainMassFraction (0.3).
%   See docs/dhs-weather-solar-schedule.md.

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
