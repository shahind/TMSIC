classdef Storey < dynamicprops & handle
    properties
        name
        parentBuilding
        zoneList = {}
    end
    methods
        function obj = Storey(name, parent)
            obj.name = name;
            obj.parentBuilding = parent;
        end
        
        function addZone(obj, name, varargin)
            % addZone(name, 'C_main', value, 'R_default', value)
            if isprop(obj, name)
                error('Zone "%s" already exists in storey %s.', name, obj.name);
            end
            p = addprop(obj, name);
            % create zone object
            z = RCBS.Zone(name, obj.parentBuilding, obj);
            % parse optional args
            for k=1:2:numel(varargin)
                if k+1<=numel(varargin)
                    z.(varargin{k}) = varargin{k+1};
                end
            end
            obj.(name) = z;
            obj.zoneList{end+1} = name;
        end
    end
end