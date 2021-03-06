function data = readStateExt(n, filename)

format = '%d %f ';
fid    = fopen(filename);

for j = 1 : 10
   format = [format, '('];
   for i = 1 : n
      if j < 9
         format = [format, '%f '];
      else
         format = [format, '%d '];
      end
   end
   format = [format, ') [ok] '];
end
C    = textscan(fid, format);
time = C{1, 2};
q    = cell2mat(C(1, 3    :3+  n-1));
dq   = cell2mat(C(1, 3+  n:3+2*n-1));
d2q  = cell2mat(C(1, 3+2*n:3+3*n-1));
%torque is the 7th block
tau  = cell2mat(C(1, 3+6*n:3+7*n-1));



[tu,iu] = unique(time);
data = struct;
data.time    = tu;
data.q       = q(iu, :);
data.dq      = dq(iu, :);
data.d2q     = d2q(iu, :);
data.tau     = tau(iu, :);


if fclose(fid) == -1
   error('[ERROR] there was a problem in closing the file')
end
