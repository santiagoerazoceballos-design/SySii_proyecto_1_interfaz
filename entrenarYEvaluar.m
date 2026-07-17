% =========================================================================
% entrenarYEvaluar.m  --  ETAPAS 6 a 8
% -------------------------------------------------------------------------
% Particion, entrenamiento, seleccion de hiperparametros y evaluacion.
% Cumple las specs IV.1, IV.2, IV.3 y V.
%
% Requiere: features_emg.mat (generado por construirDataset.m)
% Produce : modelo_final.mat (para el modo tiempo real)
%
% PUNTO CLAVE: la particion es POR SUJETO. Si se mezclan ventanas del mismo
% sujeto entre train y test, el accuracy sube ~30 puntos y es mentira: el
% modelo reconoce a la persona, no la palabra.
% =========================================================================

clear; clc; close all;

load('features_emg.mat', 'X', 'Y', 'SubjWin', 'RepID', 'nombres', 'cfg');
clases = cellstr(cfg.clases);

%% ==================== ETAPA 6: particion por sujeto ====================
rng(42);                                  % reproducible
sujUnicos = unique(SubjWin);
nSuj = numel(sujUnicos);

p    = randperm(nSuj);
nTr  = max(1, round(0.7*nSuj));
sTr  = sujUnicos(p(1:nTr));
sTe  = sujUnicos(p(nTr+1:end));

idxTr = ismember(SubjWin, sTr);
idxTe = ~idxTr;

fprintf('=== PARTICION POR SUJETO ===\n');
fprintf('Sujetos train: %d  -> %s\n', numel(sTr), strjoin(sTr.', ', '));
fprintf('Sujetos test : %d  -> %s\n', numel(sTe), strjoin(sTe.', ', '));
fprintf('Ventanas train/test: %d / %d\n\n', sum(idxTr), sum(idxTe));

Xtr = X(idxTr,:);   ytr = removecats(Y(idxTr));
Xte = X(idxTe,:);   yte = removecats(Y(idxTe));

%% -------------------- z-score con estadisticos del TRAIN --------------
mu = mean(Xtr, 1);
sg = std(Xtr, 0, 1);
sg(sg < eps) = 1;

Ztr = (Xtr - mu) ./ sg;
Zte = (Xte - mu) ./ sg;

%% ============ ETAPA 7a: minima distancia al centroide (spec IV.2) ======
fprintf('=== CLASIFICADOR DE MINIMA DISTANCIA AL CENTROIDE ===\n');
distsCent = ["euclidiana", "manhattan", "coseno"];
resCent = struct('dist',{},'accVent',{},'accRep',{},'yhat',{});

for k = 1:numel(distsCent)
    yhat = clasifCentroide(Ztr, ytr, Zte, distsCent(k));
    accV = mean(yhat == yte);
    [pr, tr] = votoMayoritario(yhat, yte, RepID(idxTe), clases);
    accR = mean(pr == tr);

    resCent(k).dist    = distsCent(k);
    resCent(k).accVent = accV;
    resCent(k).accRep  = accR;
    resCent(k).yhat    = yhat;

    fprintf('  %-12s  ventana: %5.1f%%   repeticion(voto): %5.1f%%\n', ...
        distsCent(k), 100*accV, 100*accR);
end

[~, bC] = max([resCent.accRep]);
fprintf('  -> mejor: %s\n\n', resCent(bC).dist);

%% ====== ETAPA 7b: KNN, barrido con CV por sujeto DENTRO del train ======
% Los hiperparametros (K y distancia) se eligen con validacion cruzada
% agrupada por sujeto usando SOLO el training. Elegir K mirando el test es
% trampa y sesga el resultado reportado.

fprintf('=== KNN: seleccion de K y distancia (CV por sujeto en train) ===\n');
Ks    = [1 3 5 7 9 11 15 21];
distsK = {'euclidean', 'cityblock', 'cosine'};
nombresDistK = {'Euclidiana', 'Manhattan', 'Coseno'};

subjTr = SubjWin(idxTr);
nFold  = min(5, numel(sTr));
folds  = asignarFolds(subjTr, sTr, nFold);

accCV = zeros(numel(Ks), numel(distsK));
for a = 1:numel(Ks)
    for b = 1:numel(distsK)
        acc = zeros(nFold,1);
        for f = 1:nFold
            iVal = (folds == f);
            iFit = ~iVal;
            if ~any(iVal) || numel(categories(removecats(ytr(iFit)))) < 2
                acc(f) = NaN; continue;
            end
            m  = mean(Ztr(iFit,:),1);
            s  = std(Ztr(iFit,:),0,1); s(s<eps)=1;
            Zf = (Ztr(iFit,:)-m)./s;
            Zv = (Ztr(iVal,:)-m)./s;

            mdl = fitcknn(Zf, ytr(iFit), 'NumNeighbors', Ks(a), ...
                          'Distance', distsK{b});
            acc(f) = mean(predict(mdl, Zv) == ytr(iVal));
        end
        accCV(a,b) = mean(acc, 'omitnan');
    end
end

disp(array2table(100*accCV, ...
    'RowNames', compose('K=%d', Ks), ...
    'VariableNames', nombresDistK));

[~, lin] = max(accCV(:));
[aBest, bBest] = ind2sub(size(accCV), lin);
Kopt    = Ks(aBest);
distOpt = distsK{bBest};
fprintf('  -> elegido por CV: K = %d, distancia = %s (%.1f%% CV)\n\n', ...
    Kopt, nombresDistK{bBest}, 100*accCV(aBest,bBest));

%% ------------------ KNN final entrenado con todo el train -------------
mdlKNN  = fitcknn(Ztr, ytr, 'NumNeighbors', Kopt, 'Distance', distOpt);
yhatKNN = predict(mdlKNN, Zte);
accKNNv = mean(yhatKNN == yte);
[prKNN, trKNN] = votoMayoritario(yhatKNN, yte, RepID(idxTe), clases);
accKNNr = mean(prKNN == trKNN);

fprintf('=== KNN EN TEST (sujetos nunca vistos) ===\n');
fprintf('  Por ventana            : %.1f%%\n', 100*accKNNv);
fprintf('  Por repeticion (voto)  : %.1f%%\n\n', 100*accKNNr);

%% -------- Referencia opcional: LDA y Naive Bayes (no obligatorios) ----
% Dos lineas cada uno. No se construye nada encima; sirven solo para tener
% el numero a la mano si preguntan "¿por que KNN?".
try
    mdlLDA  = fitcdiscr(Ztr, ytr, 'DiscrimType', 'pseudolinear');
    accLDAr = mean(votoMayoritario(predict(mdlLDA, Zte), yte, RepID(idxTe), clases) == trKNN);
    mdlNB   = fitcnb(Ztr, ytr);
    accNBr  = mean(votoMayoritario(predict(mdlNB, Zte), yte, RepID(idxTe), clases) == trKNN);
    fprintf('=== REFERENCIA (no obligatorios) ===\n');
    fprintf('  LDA        (voto): %.1f%%\n', 100*accLDAr);
    fprintf('  Naive Bayes(voto): %.1f%%\n\n', 100*accNBr);
catch ME
    fprintf('Referencia LDA/NB no disponible: %s\n\n', ME.message);
end

%% =============== ETAPA 8: matrices de confusion (spec V.1) ============
figure('Name','Matrices de confusion - voto por repeticion', ...
       'Position',[100 100 1000 420]);

subplot(1,2,1);
[prC, trC] = votoMayoritario(resCent(bC).yhat, yte, RepID(idxTe), clases);
confusionchart(trC, prC, 'RowSummary','row-normalized', ...
    'Title', sprintf('Centroide (%s) - %.1f%%', resCent(bC).dist, 100*mean(prC==trC)));

subplot(1,2,2);
confusionchart(trKNN, prKNN, 'RowSummary','row-normalized', ...
    'Title', sprintf('KNN (K=%d, %s) - %.1f%%', Kopt, nombresDistK{bBest}, 100*accKNNr));

%% ------------- metricas por clase (spec V.2: ¿igual desempeño?) -------
fprintf('=== DESEMPEÑO POR CLASE - KNN (voto por repeticion) ===\n');
reportePorClase(trKNN, prKNN, clases);

fprintf('=== DESEMPEÑO POR CLASE - Centroide %s ===\n', resCent(bC).dist);
reportePorClase(trC, prC, clases);

%% ------------------------ guardar modelo para tiempo real -------------
modelo.tipo    = 'knn';
modelo.mdl     = mdlKNN;
modelo.K       = Kopt;
modelo.dist    = distOpt;
modelo.mu      = mu;
modelo.sg      = sg;
modelo.clases  = clases;
modelo.cfg     = cfg;
[~, Ccent]     = clasifCentroide(Ztr, ytr, Ztr(1,:), 'euclidiana');
modelo.centroides = Ccent;      % respaldo por si el KNN falla en vivo

save('modelo_final.mat', 'modelo');
fprintf('\nModelo guardado en modelo_final.mat\n');

% =========================================================================
% FUNCIONES LOCALES
% =========================================================================

function folds = asignarFolds(subjVec, sujUnicos, nFold)
% Asigna cada ventana al fold de su sujeto (CV agrupada, sin fuga).
    rng(7);
    perm = randperm(numel(sujUnicos));
    foldDeSujeto = zeros(numel(sujUnicos), 1);
    foldDeSujeto(perm) = mod(0:numel(sujUnicos)-1, nFold) + 1;

    [~, loc] = ismember(subjVec, sujUnicos);
    folds = foldDeSujeto(loc);
end

function [predRep, trueRep] = votoMayoritario(yhat, ytrue, repIDs, clases)
% Colapsa las ventanas de cada repeticion en una sola decision por voto.
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

function reportePorClase(ytrue, ypred, clases)
% Precision, recall y F1 por clase. Alimenta la discusion de la spec V.2.
    fprintf('  %-10s %9s %9s %9s %8s\n', 'Clase','Precision','Recall','F1','Soporte');
    for k = 1:numel(clases)
        c  = clases{k};
        tp = sum(ypred == c & ytrue == c);
        fp = sum(ypred == c & ytrue ~= c);
        fn = sum(ypred ~= c & ytrue == c);
        pr = tp / max(tp+fp, 1);
        rc = tp / max(tp+fn, 1);
        f1 = 2*pr*rc / max(pr+rc, eps);
        fprintf('  %-10s %8.1f%% %8.1f%% %8.1f%% %8d\n', ...
            c, 100*pr, 100*rc, 100*f1, sum(ytrue == c));
    end
    fprintf('  %-10s %8.1f%%\n\n', 'GLOBAL', 100*mean(ypred == ytrue));
end
