function R = rotationFromQuaternion(q)
    %Rodriques's formula
    % R = I3 + 2s S(r) + 2S(r)2,
    R = eye(3) + 2 * q(1) * skew(q(2:4)) + 2 *  skew(q(2:4))^2;
end
