clear all 
clc

% Load in A,b, C,d cell arrays
load('pendulum_controlled_pwa.mat');
X = Polyhedron('lb', [-pi; -pi], 'ub', [pi; pi]);
U = Polyhedron('lb', -5, 'ub', 5);

num_regions = length(A);
for i = 1:num_regions
    systems(i) = LTISystem('A', C{i}(:,1:2), 'B', C{i}(:,3), 'f', d{i}, 'domain', Polyhedron(A{i}, b{i}));
end

% pwa = PWASystem('A', dyn_A, 'B', dyn_B, 'f', dyn_f, 'domain', dyn_P);
pwa = PWASystem(systems);
tic;
S = pwa.invariantSet('X', X, 'U', U, 'maxIterations', 2);
t = toc;
plot(S)
xlabel("Angle (rad)")
ylabel("Angular Velocity (rad/s)")
% xlim([-2.5 2.5])
% ylim([-3 3])

% Save concactenated Ab H-rep of the control invariant set
Ab = S.H;
% save("cntrl_invariant.mat", 'Ab');




