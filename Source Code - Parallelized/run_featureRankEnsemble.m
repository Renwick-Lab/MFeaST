function [ranking_results, alg_names] = run_featureRankEnsemble(data, classes, c, UseParallel, IS_max_iterations, selectedAlgs)
% runs feature selections with cross-validation
% return cross-validated average ranking of the features for each algorithm
%INPUT: 
%   data - numeric array, where columns are samples and rows are features
%   classes - binary vector indicating 2 types of classes (0 and 1)
%   c - cvpartition for cross-validation
%   UseParallel - boolean to use parallel processors
%OUTPUT:
%   ranking_results     -  numeric array of ranked features for each
%                           algorithm. Rows are features, columns are
%                           ranking results. First column is the overall
%                           ranking. Results are standardized between 0 and
%                           1, where 1 is the highest rank.
%   alg_names           -  celldata vector indicating names of the
%                           algorithms matching the ranking_results order
% Required functions:
%  FeatureRankEnsemble_v3, greedyFeatureSelEnsamble 
%
% Required toolboxes:
%   Statistics and Machine Learning toolbox
%   Parallel Computing Toolbox
%
% AUTHOR: Kathrin Tyryshkin
% Date: May 6th, 2018
% Version: 3
%
% Modified by: Yiheng Li
% Date: April 10th, 2023



alg_names = {};
ranks = [];
ranked_features = [];


% Ranking algorthims
for i=1:c.NumTestSets
    trainingset = training(c,i);
    currdata = data(:,trainingset);
    currclasses = classes(trainingset);
    [r_res, num] = FeatureRankEnsemble_v3(currdata, currclasses, selectedAlgs);
    ranks = [ranks r_res];
end

%average the results of cross validation
totalNumRankAlg = num;
if totalNumRankAlg ~= 0 
    ranked_features = zeros(length(ranks(:, 1)), totalNumRankAlg);
    for i=1:totalNumRankAlg
        t = ranks(:, i:totalNumRankAlg:end);
        ranked_features(:, i) = mean(t,2);
    end
else
    ranked_features = [];
end

%___________________________________________________________________
%run ensmble classifiers - predictor importance
%___________________________________________________________________

t = templateTree('surrogate','all');
s = struct('CVPartition', c, 'ShowPlots', false);

%settings for the iterative sequentialfs algorithm
IS_options = statset('display','iter','UseParallel',UseParallel);

% Parfor for tree ensemble algorthims
parfor i = 1:length(selectedAlgs)
    if (selectedAlgs(i) == "ensembleBag")
        ens = pfitcensemble(data',classes, 'Method','Bag', 'Learners', t,...
            'OptimizeHyperparameters', 'all', 'HyperparameterOptimizationOptions',s);
        [imp1,~] = predictorImportance(ens);
        ranked_features = [ranked_features minmax_standardize(imp1',1)];
    end

    if (selectedAlgs(i) ==  "ensembleGentleBoost")
        ens = fitcensemble(data',classes, 'Method','GentleBoost', 'Learners', t,...
            'OptimizeHyperparameters', 'all', 'HyperparameterOptimizationOptions',s);
        [imp2,~] = predictorImportance(ens);
        ranked_features = [ranked_features minmax_standardize(imp2',1)];

    end
    if (selectedAlgs(i)== "ensembleRUSBoost")
        %'RUSBoost' - good for unbalanced classes
        ens = fitcensemble(data',classes, 'Method','RUSBoost', 'Learners', t,...
            'OptimizeHyperparameters', 'all', 'HyperparameterOptimizationOptions',s);
        [imp3,~] = predictorImportance(ens);
        % imp6 = oobPermutedPredictorImportance(ens);
        ranked_features = [ranked_features minmax_standardize(imp3')];
    end
end

% Sequential algorthims, they are in serial order
if (any(strcmpi(selectedAlgs, "Sequential_knn")))
    res_seqfs = iterSequantialfs_v2(data', classes, 'knn', c, 'forward',...
        IS_options, IS_max_iterations, UseParallel);
    ranked_features = [ranked_features minmax_standardize(res_seqfs,1)];
end
if (any(strcmpi(selectedAlgs, "Sequential_tree")))
    res_seqfs = iterSequantialfs_v2(data', classes, 'tree', c, 'forward',...
        IS_options, IS_max_iterations, UseParallel);
    ranked_features = [ranked_features minmax_standardize(res_seqfs,1)];
end
    % %this one is too slow - even for small sets  - don't use it if there are
    % %many features
    % res_seqfs = iterSequantialfs_v2(data', classes, 'lin_lda', c, 'forward',...
    %     IS_options, IS_max_iterations, UseParallel);
    % ranked_features = [ranked_features minmax_standardize(res_seqfs,1)];
    % alg_names = [alg_names 'iterSeq_linLDA'];
if (any(strcmpi(selectedAlgs, "Sequential_ensbl")))
    res_seqfs = iterSequantialfs_v2(data', classes, 'ensbl', c, 'forward',...
        IS_options, IS_max_iterations, UseParallel);
    ranked_features = [ranked_features minmax_standardize(res_seqfs,1)];
end
if (any(strcmpi(selectedAlgs, "Sequential_svm")))
    res_seqfs = iterSequantialfs_v2(data', classes, 'svm', c, 'forward',...
        IS_options, IS_max_iterations, UseParallel);
    ranked_features = [ranked_features minmax_standardize(res_seqfs,1)];
end
if (any(strcmpi(selectedAlgs, "Sequential_quadrLDA")))
    res_seqfs = iterSequantialfs_v2(data', classes, 'quad_lda', c, 'forward',...
        IS_options, IS_max_iterations, UseParallel);
    ranked_features = [ranked_features minmax_standardize(res_seqfs,1)];
end

% Combine all the selected algorthims names to cell structure and stored in
% alg_names
resultcell = cellstr(selectedAlgs);
alg_names = [alg_names resultcell];

%replace any NaN results in ranking with 0
ranked_features(isnan(ranked_features)) = 0;

%rank the features using greedy algorithms
overall_rank = greedyFeatureSelEnsamble(ranked_features);

x = 1:length(overall_rank);
[~, ind] = sort(overall_rank);
ranking_results = [((x(ind)))' ranked_features];
alg_names = ['overall_rank' alg_names];
disp('done ranking');
