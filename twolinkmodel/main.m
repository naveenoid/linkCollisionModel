function [wholeSolution,model,environment] =  main(plane_incl)

    addpath(genpath('utilities'));

    clc;

    environment.plane_inclination = 10 / 180 * pi;
    if exist('plane_incl','var')
        environment.plane_inclination = plane_incl;
    end

    %%Model: two links - One dof
    model = struct();
    %note: numbers are random for now :D
    %foot: box
    model.foot.mass = 0.4; %kg
    model.foot.length = 0.2; %m
    model.foot.height = 0.05; %m
    %foot reference frame: bottom-left angle
    rotI = iDynTree.RotationalInertiaRaw();
    rotI.zero();
    rotI.setVal(1,1,1); rotI.setVal(2, 2,1);
    rotI.setVal(0, 0, model.foot.mass/3 * (model.foot.length^2 + model.foot.height^2));
    pos = iDynTree.Position(0, ...
        model.foot.length / 2, model.foot.height / 2);
    model.foot.I = iDynTree.SpatialInertia(model.foot.mass, pos, rotI);
    model.foot.joint_X_frame = iDynTree.Position(0, model.foot.length / 3, model.foot.height);

    %leg: rod with uniform mass + an additional mass attached to one end.
    %reference frame at the joint (one end of the rod)
    model.leg.length = 0.4;
    model.leg.mass = 10;
    model.upperbody.mass = 20;
    rotI.zero();
    rotI.setVal(1,1,0.1); rotI.setVal(2, 2,0.1);
    rotI.setVal(0, 0, model.leg.mass/3 * model.leg.length^2);
    legI = iDynTree.SpatialInertia(model.leg.mass, iDynTree.Position(0, 0, model.leg.length / 2), rotI);
    rotI.zero();
    rotI.setVal(1,1,0.1); rotI.setVal(2, 2,0.1);
    rotI.setVal(0,0, model.upperbody.mass * model.leg.length^2);
    upperBodyI = iDynTree.SpatialInertia(model.upperbody.mass, iDynTree.Position(0, 0, model.leg.length), rotI);
    model.leg.I = legI + upperBodyI;

    %%Initial state
    q = 0;%pi/2;
    v2 = iDynTree.Twist();
    v2.zero();
    v2.setVal(1, 0);
    v2.setVal(3, 0);
    qdot = 0;

    xpos_0 = [0; 
              0; 
              0.5;...
              quaternionFromEulerRotation(0, [1;0;0]);...
               q];

    xdot_0 = [v2.toMatlab(); qdot];
    x0 = [xpos_0; xdot_0];

    f_ext = iDynTree.Wrench();
    f_ext.zero();

    tspan = [0, 2];
    
    global forces;
    forces = [];

    phaseEvent = {@(t,y)collisionDetection(t,y,environment, model),...
        @(t,y)fullContactCondition(t,y,environment,model),...
        []};
    phaseConstraints = {[],'corner','foot'};    
    phaseName = {'Free-flight','Single-point contact','Full-Foot contact'};

    phaseResetOperator = {[zeros(3), zeros(3); zeros(3), eye(3)], zeros(6), []};
    % phaseResetStateIdx = {9:11,9:9+5,[]};
    impCtrlParams.damp = 3;
    impCtrlParams.stiffness = 20;

    impedCtrl = @(t,x)impedanceCtrl(t,x, 0, impCtrlParams);
    
    wholeSolution.t = [];
    wholeSolution.y = [];
    wholeSolution.event = [];
    wholeSolution.contactForces = [];
    for phase = 1:3

        fprintf('\nPhase %d\n----------\n',phase);

        %% setting options
       % options = odeset(...%'OutputFcn', @odeplot,...
                     % 'OutputSel',[1:3],'Refine',4,...
     %                 'RelTol', 1e-5, ...
                     % 'MaxStep',1e-2,...
      %                'Events',phaseEvent{phase} );
        options = odeset('RelTol', 1e-5,'Events',phaseEvent{phase} );
        %first state: free flying state   
        odesol =  ode15s(@(t,x)odefunc(t, x, impedCtrl, f_ext, phaseConstraints{phase}, model), ...
                        tspan, x0', options);

        wholeSolution.t = [wholeSolution.t, odesol.x];
        wholeSolution.y = [wholeSolution.y, odesol.y];% deval(odesol,linspace(odesol.x(1),odesol.x(end),100));

        if (odesol.x(end) == tspan(end))

            if(phase<3)
                fprintf('%s Phase - No collision detected before t=%f\n',phaseName{phase},odesol.x(end));
            else
                fprintf('%s Phase - terminal time t = %f\n',phaseName{phase},odesol.x(end));
            end
        else
            twistAtImpact = odesol.y(9:9 + 5, 9+6);
            fprintf('%s Phase - Collision detected at time t=%f for event %d\n',phaseName{phase},odesol.x(end), odesol.ie);
            disp('Twist at impact is')
            disp(twistAtImpact')
            %I should start again to integrate but
            %I need to:
            % - v_0 = v^- (angular), 0 * v^- (linear) (only angular twist is
            % preserved)
            % - add position constraint of the contact point

            %reset initial state
            x0 = odesol.y(:, end);
            
            operator = phaseResetOperator{phase};
%             x0(phaseResetStateIdx{phase}) = 0; %set linear twist to zero
            tspan(1) = odesol.x(end);

            if (phase == 1 && size(odesol.ie, 1) == 1 && odesol.ie == 1)
                operator = [zeros(3), zeros(3); zeros(3), eye(3)];
                phaseConstraints{2} = 'left_corner';
            elseif (phase == 1 && size(odesol.ie, 1) == 1 && odesol.ie == 2)
                w_R_f2 = iDynTree.Rotation();
                w_R_f2.fromMatlab(rotationFromQuaternion(odesol.y(4:7,end)));
        %         w_X_f2 = iDynTree.Transform(w_R_f2, iDynTree.Position(odesol.y(1,end), odesol.y(2,end),odesol.y(3,end)));
                pf2_w_X_f2 = iDynTree.Transform(w_R_f2, iDynTree.Position());

                f2_X_rc = iDynTree.Transform(iDynTree.Rotation.Identity(), iDynTree.Position(0, model.foot.length, 0));
                w_X_rc = pf2_w_X_f2 * f2_X_rc;
                operator = w_X_rc.asAdjointTransform().toMatlab() * operator * w_X_rc.inverse().asAdjointTransform().toMatlab();
                phaseConstraints{2} = 'right_corner';
            elseif (phase == 1 && size(odesol.ie, 1) == 2)
                %flat contact
                 %??
            end
            
            x0(9:14) = operator * x0(9:14);
            wholeSolution.event = [wholeSolution.event, odesol.x(end)];
        end
    end
    
    wholeSolution.contactForces = forces;
    
end

function u = impedanceCtrl(~, x, ref, params)
    q = x(8); %joint positiony
    qdot = x(9+6); %joint velocity
    
    u = -params.stiffness * (q - ref) ...
        - params.damp * qdot;
end

function dx = odefunc(t,x, controlfunc, f_ext, constaints, model)
    global forces;
    xpos = x(1:7); %base position
%      q = x(8); %joint position
    xdot = x(9:9+5); %base velocity
    qdot = x(9+6); %joint velocity
    quatDot = quaternionDerivative(xpos(4:end), xdot(4:end), 1);
    
    u = controlfunc(t, x);
    [a, f_c] = twolink_dynamic(t, x, u, f_ext, constaints, model);
    if (~isempty(f_c))
        forces = [forces, [t; f_c]];
    end
    
    dx = [xdot(1:3);
          quatDot;
          qdot;
          a];
%       acc = [acc, [t;a]];
%       Fs = [Fs, [t; F]];
end

function [value,isterminal,direction] = collisionDetection(~,y, environment, model)
    xpos = y(1:7); %base position
    xposLin = xpos(1:3);
    xposRotation = rotationFromQuaternion(xpos(4:7));
    
    %check the lowest (z) point of the foot
    x1Pos = xposLin;
    x2Pos = xposLin + xposRotation * [0;model.foot.length; 0];
   
    value(1) = x1Pos(3) + x1Pos(2) * sin(environment.plane_inclination);
    value(2) = x2Pos(3) + x2Pos(2) * sin(environment.plane_inclination);
    
    isterminal = [1,1];
    direction = [-1, -1];    
end

function [value,isterminal,direction] = fullContactCondition(~,y, environment, ~)
    xpos = y(1:7); %base position
    xposRotation = rotationFromQuaternion(xpos(4:7));
    [xRotation, ~, ~] = rpyFromRotation(xposRotation);
    
    value = xRotation + environment.plane_inclination;
    
    isterminal = 1;
    direction = 0;    
end
