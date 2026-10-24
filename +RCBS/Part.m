classdef Part < handle
% RCBS.PART  A named element of a zone: a wall, roof, window, internal mass or the air node.
%
%   Every element added to a zone with addWall, addRoof, addWindow or
%   addInternalMass can be reached by its name, and the zone's air node as Air:
%
%       z = building.Storey1.Zone2;
%       z.Wall.R            total resistance [K/W]        (read and write)
%       z.Wall.C            capacitance [J/K]             (read and write)
%       z.Wall.T            temperature [degC]            (read only; live during a run)
%       z.Window.R = 2*z.Window.R;
%       z.Air.T             indoor-air temperature
%
%   R is the total resistance of the element: both halves of a wall's T-network
%   together, the single resistor of a window or an internal mass. A window has no
%   capacitance and no temperature, and the air node has no resistance. Writing R
%   or C changes the model, and a running simulation picks the change up on its next step.

    properties (SetAccess = private)
        name = ''
        zone
    end
    properties (Dependent)
        R
        C
    end
    properties (Dependent, SetAccess = private)
        T
    end

    methods
        function obj = Part(zone, name)
            obj.zone = zone;  obj.name = name;
        end

        function v = get.R(obj)
            idx = obj.resistorIndex();
            v = sum([obj.zone.resistors(idx).R]);
        end
        function set.R(obj, v)
            idx = obj.resistorIndex();
            for i = idx, obj.zone.resistors(i).R = v / numel(idx); end
            obj.zone.touch();
        end

        function v = get.C(obj)
            v = obj.zone.nodes(obj.nodeIndex()).C;
        end
        function set.C(obj, v)
            k = obj.nodeIndex();
            obj.zone.nodes(k).C = v;
            if k == 1, obj.zone.C_main = v; end
            obj.zone.touch();
        end

        function v = get.T(obj)
            v = obj.zone.nodes(obj.nodeIndex()).T;
        end
    end

    methods (Access = private)
        function k = nodeIndex(obj)
            k = find(strcmp({obj.zone.nodes.name}, obj.name), 1);
            if isempty(k)
                error('RCBS:Part:noNode', '"%s" has no capacitance or temperature (it is a massless element).', obj.name);
            end
        end

        function idx = resistorIndex(obj)
            rn  = {obj.zone.resistors.name};
            idx = find(strcmp(rn, obj.name), 1);                       % a window: one resistor
            if isempty(idx)
                idx = find(strcmp(rn, [obj.name '_m']) | strcmp(rn, [obj.name '_o']));   % a wall: two halves
            end
            if isempty(idx)
                error('RCBS:Part:noResistance', '"%s" has no resistance.', obj.name);
            end
        end
    end
end
