% =========================================================================
% entrenarModeloFinal.m
% -------------------------------------------------------------------------
% Entrena el modelo que va al sistema en vivo, usando TODOS los sujetos.
%
% Esto NO es evaluacion. La evaluacion honesta es evaluarLOSO.m, que
% reporta 71.3% +/- 18.6 y ese sigue siendo el numero valido para una
% persona nueva. Aqui simplemente se aprovecha todo el dato disponible
% para el modelo que se va a desplegar: un KNN entrenado con 19 sujetos
% generaliza un poco mejor que uno entrenado con 13.
%
% El accuracy sobre estos mismos datos seria ~100% (el KNN se ve a si
% mismo) y no significa nada, por eso ni se calcula.
%
% Corre DESPUES de entrenarYEvaluar.m. Sobreescribe modelo_final.mat.
% =========================================================================

clear; clc;

%% ------------------------------------------------------ hiperparametros
% Salieron de la CV por sujeto en entrenarYEvaluar.m. Ojo: la tabla de CV
% estaba plana (64-72% en todo el rango), asi que K=15/Manhattan no es un
% optimo marcado sino una zona estable. No lo vendas como "el K optimo".
Kopt    = 15;
distOpt = 'cityblock';       % 'cityblock' = Manhattan en MATLAB

load('features_emg.mat', 'X', 'Y', 'SubjWin', 'nombres', 'cfg');
clases = cellstr(cfg.clases);

fprintf('=== MODELO DE DESPLIEGUE ===\n');
fprintf('Repeticiones   : %d\n', size(X,1));
fprintf('Caracteristicas: %d\n', size(X,2));
fprintf('Sujetos        : %d\n', numel(unique(SubjWin)));
fprintf('Normalizacion  : %s\n', cfg.normaliza);
fprintf('KNN            : K=%d, distancia=%s\n\n', Kopt, distOpt);

if ~strcmpi(cfg.normaliza, 'reposo')
    warning(['features_emg.mat se construyo con normalizacion "%s". ' ...
             'El sistema en vivo necesita "reposo" para funcionar con ' ...
             'una persona nueva sin calibracion previa.'], cfg.normaliza);
end

%% ---------------------------------- z-score sobre TODO el dataset
% Aqui si es correcto usar todos los datos: mu y sg son parametros del
% modelo que se despliega, no hay conjunto de prueba que contaminar.
mu = mean(X, 1);
sg = std(X, 0, 1);
sg(sg < eps) = 1;
Z = (X - mu) ./ sg;

%% ------------------------------------------------ entrenamiento
mdl = fitcknn(Z, Y, 'NumNeighbors', Kopt, 'Distance', distOpt);

% Centroides de respaldo (mismo formato que clasifCentroide)
C = zeros(numel(clases), size(Z,2));
for k = 1:numel(clases)
    C(k,:) = mean(Z(Y == clases{k}, :), 1);
end

%% ------------------------------------------------------ guardar
modelo.tipo       = 'knn';
modelo.mdl        = mdl;
modelo.K          = Kopt;
modelo.dist       = distOpt;
modelo.mu         = mu;
modelo.sg         = sg;
modelo.clases     = clases;
modelo.cfg        = cfg;
modelo.nombres    = nombres;
modelo.centroides = C;
modelo.nSujetos   = numel(unique(SubjWin));
modelo.nMuestras  = size(X,1);
modelo.fecha      = string(datetime('now'));
% Datos de entrenamiento: la interfaz los necesita para poder
% reentrenar el KNN con cualquier distancia sin depender del modelo
% guardado con una distancia fija.
modelo.Ztr        = Z;
modelo.Ytr        = Y;

save('modelo_final.mat', 'modelo');

fprintf('Guardado en modelo_final.mat\n');
fprintf('Entrenado con %d repeticiones de %d sujetos.\n', ...
    modelo.nMuestras, modelo.nSujetos);
fprintf('\nExpectativa realista con una persona nueva: ~71%% (+/- 19).\n');
fprintf('El azar es 33%%.\n');
