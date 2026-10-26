classdef CrossLink < handle
% DHS.HYDRAULIC.CROSSLINK  A pipe or valve that joins the supply side straight to the return side.
%
%   A bypass is made by connecting a link to a return junction:
%
%       tee.portB.addPipe(0.05, 5).addValve('Kvs',2).connect(returnJunction)
%
%   The valve (or pipe) that ends on the return side carries the water the radiators or buildings do
%   not take, so it is a branch of the network like a building is. This object is that branch; it is
%   made by connect and is not created by hand. Its flow is the link's flow (valve.mdot).

    properties
        link
        supplyNode = []
        returnNode = []
        teeSide (1,:) char = ''
        Tpass (1,1) double = NaN        % temperature of the water leaving the branch [degC]
    end

    methods
        function obj = CrossLink(link)
            obj.link = link;  obj.supplyNode = link.nodeA;  obj.returnNode = link.nodeB;
        end

        function K = branchResistance(obj, rho, mu, m)
            if nargin < 4, m = obj.link.mdot; end
            K = obj.link.linkLoss(max(m, 0.05), rho, mu);
        end

        function p = branchPump(~)
            p = DHS.Hydraulic.stoppedPump();
        end

        function m = branchFlow(obj),  m = obj.link.mdot; end

        function vel = setBranchResult(obj, m, rho, ~, ~, ~)
            K = obj.branchResistance(rho, 1e-3);
            obj.link.setFlow(m, K*m^2, rho);
            vel = 0;
            if isprop(obj.link, 'D'), vel = m/(rho*pi*obj.link.D^2/4); end
        end

        function [T, ql] = inletTemperature(obj, Tnode, Tground, m, cp)
            [T, ql] = obj.link.outletTemperature(Tnode, Tground, m, cp);
            obj.Tpass = T;
        end

        function [T, ql] = outletTemperature(~, Tthrough, ~, ~, ~)
            T = Tthrough;  ql = 0;
        end
    end
end
