function [T,M,Ti,Mi] = pcm_recipe_nonlinear
% Fit series of non-linear & noise-ceiling models (see 3.3 in PCM_toolbox).
% Non-linear models are defined by function that returns an estimated G
% matrix and the derivatives of G with respect to theta parameters.
% Derivitives used for 'minimize' function with employs gradient descent to 
% find theta params that yeild G with highest likelihood for that model.
%
%
% Data for this recipe are from {REF}. Dataset contains M1 activity patterns 
% for 4 subjects. The data structure is as follows:
%   'betaW': Multivariate noise normalized beta patterns for each condition
%   'tt'   : Trial type of corresponding betaW (used for G crossvalidation)
%   'run'  : Scanning run for corresponding betaW (used for G crossvalidation)
% There are 160 regressors: 8 runs of 20 conditions. The 20 conditions are
% pressing one finger of the right hand either 2,4,8, or 16 times in 6
% seconds (5 fingers * 4 speeds = 20 conds). 
%
%
% The ratio between paired finger pattern distances remains stable as activity 
% increases (i.e. as # of presses increase), but the distances increase. In 
% this recipe, we attept to model how the finger patterns scaling as the
% number of presses increases. We do this by fitting three nonlinear models
% of interest:
%   'Scaling':  patterns multiplicatively scaled by constant dependent
%               on the number of presses (Y = s*f, where f are finger
%               patterns and s is # presses scaling constant)
%   'Additive': patterns scaled by additive constant (Y = f + a, where a is
%               pressing-dependent background activity pattern)
%   'Combo':    patterns scale as combo of additive and scaling functions 
%               (Y = s*f + a). Scaling and additive models are orthogonal.
% 
% In addition to the three models of interest, we fit two additional
% models:
%   'Null':     model that returns data where all distances are equal (i.e.
%               a bad model). This is used as the zero point when scaling 
%               likelihoods to an interpretable value
%   'NoiseCeiling': naive averaging model that overfits data. Uses the
%                   observed G as a fixed model, meaning it is the best possible 
%                   model. Likelihood of the non-crossvalidated group fit
%                   of this model is set to be 1 when scaling likelihoods.
% Note that these models don't predict actual pattern estimates, rather
% their (co-)variances, but it is easier to understand the model functions
% when described in relation to actual patterns.
%
% SArbuckle 2016
  
load data_recipe_nonlinear.mat % loads struct I
runEffect = 'random'; % The run effect is considered a random effect with zero mean 
                        % this is important, as we want to preserve the
                        % information of where the baseline sits 
% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
% (1) Estimate crossvalidated G from acivity patterns
% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
for s=1:length(I) % Each row of I is one subject
    N      = length(I(s).run);      % number of condition regressors
    Y{s}   = I(s).betaW(1:N,:);    % condition-specific activity pattern
    conditionVec{s}  = I(s).tt;       
    partitionVec{s}  = I(s).run;
    G_hat(:,:,s) = pcm_estGCrossval(Y{s},I(s).run,I(s).tt);
end;
     

% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
% (2) Guess starting theta values
% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
% PCM toolbox cannot estimate starting values for nonlinear models.
% Starting vals can be arbitrary but can drastically increase computation
% time.
scale_vals = [log(0.30);log(0.62);log(0.85)];
add_vals = [log(0.2);log(0.62);log(1)];

% Get starting values for the finger structure (Omega). Because we're interested
% in how these patterns scale, we will take finger params of G for that
% reflect the (co-)variances of the fingers at the same number of presses.
% These values will be used to estimate the (co-)variances of the fingers
% at the other three number of presses. Importantly, results will be the same 
% no matter what of the 4 different pressing conditions are used to
% determine the starting values. Here we take the 15 G values for 16
% presses. We can further reduce the number of parameters to minimize by
% scaling the parameters such that the first param is equal to 1.
G_mean = mean(G_hat,3);
[Fx0,~,~] = ra_free_startingval(G_mean([16:20],[16:20])); 


% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
% (3) Specify Models
% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
% Null model- all distances equal 
M(1).type       = 'fixed'; 
M(1).name       = 'Null';
M(1).Gc         = eye(20);
M(1).numGparams = 0;

% Scaling model- distances multiplied by constant scaler dependent on number of presses
M(2).type       = 'nonlinear'; 
M(2).name       = 'Scaling';
M(2).modelpred  = @ra_modelpred_scale;
M(2).numGparams = 17; % 14 free theta params in Fx0 and 3 free scaling params
M(2).theta0     = [Fx0;scale_vals];                 

% Additive independent model- adds independent pattern that scales with the
% number of presses (independent of the scaling model)
M(3).type       = 'nonlinear'; 
M(3).name       = 'Additive';
M(3).modelpred  = @ra_modelpred_add;
M(3).numGparams = 17;
M(3).theta0     = [Fx0;add_vals];   

% Combo model: additive independent & scaling models combined
M(4).type       = 'nonlinear';
M(4).name       = 'Combo';
M(4).modelpred  = @ra_modelpred_addsc;
M(4).numGparams = 20;
M(4).theta0     = [Fx0;scale_vals;add_vals];   

% Naive averaring model- noise ceiling
M(5).type       = 'noiseceiling';         
M(5).numGparams = 0; % totally fixed model- no free params
M(5).theta0     = [];
%   Use likelihood fit of this model as 1 scaling point in each subject

% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
% (4) Fit Models and plot group lvl results
% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
[T,M] = pcm_fitModelCrossval(Y,M,partitionVec,conditionVec,'runEffect',runEffect,'isCheckDeriv',0);
T = pcm_plotModelLikelihood(T,M);
% Returns T with subfields for scaled likelihoods (relative to null model (M1)
% and noise ceiling (M5). 
        
% We can also plot and compare the real/observed and estimate (co-)variance
% matrices.
pcm_plotFittedG(G_hat,T,M);
        
 
% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
% (5) Fit Model to single subjects and plot fits for one subj
% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
[Ti,Mi] = pcm_fitModelIndivid(Y,M,partitionVec,conditionVec,'runEffect',runEffect,'isCheckDeriv',0);
sn = 4;
sf = @(x) x(sn,:);
S  = structfun(sf,Ti,'UniformOutput',false); % take only outputs for specified subject and pass through plotting func
S  = pcm_plotModelLikelihood(S,M);
% No real "noise ceiling" in single subject fit plots, so bound is just 1. 

% We can plot this subject's real and predcited G-matrices, too.
pcm_plotFittedG(G_hat,Ti,Mi,'Subj',sn);
