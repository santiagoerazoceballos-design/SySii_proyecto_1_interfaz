% =========================================================================
% evaluarLOSO.m  --  Evaluacion Leave-One-Subject-Out
% -------------------------------------------------------------------------
% El 70/30 de entrenarYEvaluar.m depende del sorteo de sujetos: con pocos
% sujetos, cambiar el rng puede mover el accuracy 15 puntos. LOSO usa a
% todos los sujetos como test una vez y da un numero mucho mas estable,
% ademas de la desviacion entre sujetos.
%
% Este es el numero que conviene reportar como resultado principal.
% Requiere: features_emg.mat
% =========================================================================

clear; clc; close all;

load('features_emg.mat', 'X', 'Y', 'SubjWin', 'RepID', 'cfg');
clases = cellstr(cfg.clases);

Kopt    = 15;
distOpt = 'cityblock';

sujUnicos = unique(SubjWin);
nSuj = numel(sujUnicos);

accKNN  = nan(nSuj,1);
accCent = nan(nSuj,1);
todosPred = categorical.empty(0,1);
todosTrue = categorical.empty(0,1);

fprintf('=== LEAVE-ONE-SUBJECT-OUT (%d sujetos) ===\n', nSuj);

for k = 1:nSuj
    idxTe = (SubjWin == sujUnicos(k));
    idxTr = ~idxTe;

    ytr = removecats(Y(idxTr));
    yte = removecats(Y(idxTe));
    if numel(categories(ytr)) < numel(clases), continue; end

    mu = mean(X(idxTr,:),1);
    sg = std(X(idxTr,:),0,1);  sg(sg<eps)=1;
    Ztr = (X(idxTr,:)-mu)./sg;
    Zte = (X(idxTe,:)-mu)./sg;

    % --- KNN ---
    mdl  = fitcknn(Ztr, ytr, 'NumNeighbors', Kopt, 'Distance', distOpt);
    yhat = predict(mdl, Zte);
    [pr, tr] = votoLOSO(yhat, Y(idxTe), RepID(idxTe), clases);
    accKNN(k) = mean(pr == tr);

    todosPred = [todosPred; pr]; %#ok<AGROW>
    todosTrue = [todosTrue; tr]; %#ok<AGROW>

    % --- Centroide (euclidiana) ---
    yhatC = clasifCentroide(Ztr, ytr, Zte, 'euclidiana');
    [prC, trC] = votoLOSO(yhatC, Y(idxTe), RepID(idxTe), clases);
    accCent(k) = mean(prC == trC);

    fprintf('  %-8s  KNN: %5.1f%%   Centroide: %5.1f%%\n', ...
        sujUnicos(k), 100*accKNN(k), 100*accCent(k));
end

fprintf('\n--- RESUMEN LOSO ---\n');
fprintf('KNN       : %.1f%% +/- %.1f  (min %.1f%%, max %.1f%%)\n', ...
    100*mean(accKNN,'omitnan'), 100*std(accKNN,'omitnan'), ...
    100*min(accKNN), 100*max(accKNN));
fprintf('Centroide : %.1f%% +/- %.1f\n', ...
    100*mean(accCent,'omitnan'), 100*std(accCent,'omitnan'));
fprintf('Azar      : %.1f%%\n', 100/numel(clases));

figure('Name','Matriz de confusion LOSO acumulada','Position',[100 100 560 480]);
confusionchart(todosTrue, todosPred, 'RowSummary','row-normalized', ...
    'Title', sprintf('KNN LOSO acumulado - %.1f%%', 100*mean(todosPred==todosTrue)));

figure('Name','Accuracy por sujeto','Position',[700 100 700 400]);
bar([accKNN, accCent]*100);
yline(100/numel(clases), 'r--', 'Azar', 'LineWidth', 1.5);
set(gca, 'XTick', 1:nSuj, 'XTickLabel', sujUnicos, 'XTickLabelRotation', 45);
ylabel('Accuracy (%)'); legend({'KNN','Centroide'}, 'Location','best');
title('Desempeño por sujeto excluido'); grid on;

% =========================================================================
function [predRep, trueRep] = votoLOSO(yhat, ytrue, repIDs, clases)
    reps = unique(repIDs);
    predRep = strings(numel(reps),1);
    trueRep = strings(numel(reps),1);
    for r = 1:numel(reps)
        m = (repIDs == reps(r));
        predRep(r) = string(mode(yhat(m)));
        trueRep(r) = string(ytrue(find(m,1)));
    end
    predRep = categorical(predRep, clases);
    trueRep = categorical(trueRep, clases);
end
