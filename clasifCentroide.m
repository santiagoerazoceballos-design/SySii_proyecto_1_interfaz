function [yhat, C, clases] = clasifCentroide(Ztr, ytr, Zte, dist)
% CLASIFCENTROIDE  Clasificador de minima distancia al centroide.
%
%   [yhat, C, clases] = clasifCentroide(Ztr, ytr, Zte, dist)
%
%   Ztr    : [nTr x nFeat] entrenamiento YA estandarizado (z-score).
%   ytr    : [nTr x 1] categorical con las etiquetas de entrenamiento.
%   Zte    : [nTe x nFeat] prueba, estandarizado con mu/sigma del TRAIN.
%   dist   : 'euclidiana' | 'manhattan' | 'coseno'
%
%   yhat   : [nTe x 1] categorical con la prediccion.
%   C      : [nClases x nFeat] centroides (utiles para el modo tiempo real).
%   clases : cellstr con el orden de las filas de C.
%
%   Implementa la spec IV.2. El z-score es obligatorio: sin el, las
%   caracteristicas de rango grande dominan la distancia y el clasificador
%   ignora las demas.

    clases = categories(removecats(ytr));
    nCl    = numel(clases);
    C      = zeros(nCl, size(Ztr,2));

    for k = 1:nCl
        C(k,:) = mean(Ztr(ytr == clases{k}, :), 1);
    end

    switch lower(string(dist))
        case "euclidiana", metrica = 'euclidean';
        case "manhattan",  metrica = 'cityblock';
        case "coseno",     metrica = 'cosine';
        otherwise
            error('clasifCentroide:dist', ...
                  'Distancia no valida: %s. Use euclidiana|manhattan|coseno.', dist);
    end

    D = pdist2(Zte, C, metrica);
    [~, idx] = min(D, [], 2);
    yhat = categorical(clases(idx), clases);
end
