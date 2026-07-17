% =========================================================================
% construirDataset.m  --  VERSION 2 (por burst)
% -------------------------------------------------------------------------
% REEMPLAZA por completo la version anterior. Borra el archivo viejo.
%
% Cambio de fondo respecto a la v1: la unidad de clasificacion ya no es una
% ventana fija de 250 ms, sino el BURST DE HABLA COMPLETO detectado. El
% diagnostico mostro que lo discriminante es la duracion del burst
% (Pelicula ~1044 ms vs Agua/Cine ~770 ms) y la distribucion de energia
% dentro de el (Cine carga el tercio central). Una ventana fija de 250 ms
% no puede ver ninguna de las dos cosas.
%
% Resultado: 1 vector por repeticion -> ~284 filas x 38 caracteristicas.
%
% Salida: features_emg.mat con X, Y, SubjWin, RepID, nombres, cfg, durMs
%   Mantiene los mismos nombres de variables que la v1, asi que
%   entrenarYEvaluar.m y evaluarLOSO.m funcionan sin cambiarles nada.
%   Como RepID es unico por fila, el voto mayoritario queda como identidad.
% =========================================================================

% =========================================================================
% construirDataset.m  --  VERSION 2 (por burst)
% -------------------------------------------------------------------------
% REEMPLAZA por completo la version anterior. Borra el archivo viejo.
%
% Cambio de fondo respecto a la v1: la unidad de clasificacion ya no es una
% ventana fija de 250 ms, sino el BURST DE HABLA COMPLETO detectado. El
% diagnostico mostro que lo discriminante es la duracion del burst
% (Pelicula ~1044 ms vs Agua/Cine ~770 ms) y la distribucion de energia
% dentro de el (Cine carga el tercio central). Una ventana fija de 250 ms
% no puede ver ninguna de las dos cosas.
%
% Resultado: 1 vector por repeticion -> ~284 filas x 38 caracteristicas.
%
% Salida: features_emg.mat con X, Y, SubjWin, RepID, nombres, cfg, durMs
%   Mantiene los mismos nombres de variables que la v1, asi que
%   entrenarYEvaluar.m y evaluarLOSO.m funcionan sin cambiarles nada.
%   Como RepID es unico por fila, el voto mayoritario queda como identidad.
% =========================================================================

clear; clc;

%% ------------------------------------------------------ configuracion
cfg.archivo   = 'dataset_parc2.mat';
cfg.salida    = 'features_emg.mat';
cfg.Fs        = 1000;
cfg.clases    = ["Agua","Cine","Pelicula"];
cfg.idxBase   = 1:900;          % reposo, para RatioRMS y para el detector
cfg.thr       = 0.05;
cfg.percentil = 95;
cfg.unidad    = 'burst';

% MODO DE NORMALIZACION -- cambia esta linea para comparar:
%   'sujeto' : p95 de TODAS las grabaciones del sujeto. Mejor estadistica,
%              pero requiere tener al sujeto ya grabado -> NO sirve en vivo
%              con una persona nueva sin calibracion previa.
%   'reposo' : p95 del tramo de reposo de CADA grabacion. Es causal, no
%              necesita calibracion y funciona con cualquiera desde la
%              primera repeticion. Usa solo informacion del propio registro.
cfg.normaliza = 'reposo';

% Opciones del detector (las mismas que dieron 284/285 en el diagnostico)
cfg.det = struct('idxBase', cfg.idxBase, 'idxBusca', 900:4000, ...
                 'kOn', 4.0, 'kOff', 2.0, 'suavizado', 100, ...
                 'minDur', 150, 'maxGap', 120, 'margen', 50);

S = load(cfg.archivo, 'dts');
dts = S.dts;
n = numel(dts);
fprintf('Cargados %d registros de %s\n', n, cfg.archivo);

%% ================= PASADA 1: preprocesar y escalar por sujeto ==========
fprintf('Pasada 1/2: preprocesando...\n');

sigProc = cell(n,1);
sujetos = strings(n,1);
frases  = strings(n,1);

for i = 1:n
    sigProc{i} = preprocesarEMG(dts(i).senal, cfg.Fs);

    % El sufijo numerico de idSujeto codifica la PALABRA, no la persona
    % (Mateo1=Agua, Mateo2=Cine, Mateo3=Pelicula). Se quita para que la
    % particion por sujeto sea real.
    sujetos(i) = regexprep(string(dts(i).idSujeto), '\d+$', '');
    frases(i)  = normalizarEtiqueta(dts(i).frase);

    if mod(i,50)==0, fprintf('   %d/%d\n', i, n); end
end

malos = (frases == "");
if any(malos)
    warning('Descartando %d registros con frase no reconocida.', sum(malos));
end

% ---------------------------------------------------------- escala
% escalaReg(i,:) es el divisor de cada canal del registro i.
nCh      = size(sigProc{find(~malos,1)}, 2);
escalaReg = ones(n, nCh);

switch lower(cfg.normaliza)
    case 'sujeto'
        % p95 de |x| sobre TODAS las señales del sujeto (las tres palabras
        % juntas). Compensa la impedancia piel-electrodo de cada persona
        % sin borrar las diferencias entre palabras.
        sujUnicos = unique(sujetos(~malos));
        for k = 1:numel(sujUnicos)
            idx = find(sujetos == sujUnicos(k) & ~malos);
            e = prctile(abs(vertcat(sigProc{idx})), cfg.percentil, 1);
            e(e < eps) = 1;
            escalaReg(idx,:) = repmat(e, numel(idx), 1);
        end
        fprintf('Escala por SUJETO (%d sujetos).\n', numel(sujUnicos));

    case 'reposo'
        % p95 de |x| en el tramo de reposo del PROPIO registro. Causal:
        % solo mira el segundo de silencio que precede a la palabra, que el
        % protocolo garantiza siempre. Funciona con una persona nueva sin
        % ninguna calibracion previa.
        for i = 1:n
            if malos(i), continue; end
            base = sigProc{i}(cfg.idxBase, :);
            e = prctile(abs(base), cfg.percentil, 1);
            e(e < eps) = 1;
            escalaReg(i,:) = e;
        end
        fprintf('Escala por REPOSO de cada registro (causal).\n');

    otherwise
        error('cfg.normaliza debe ser ''sujeto'' o ''reposo''.');
end

%% ============ PASADA 2: detectar burst y extraer caracteristicas =======
fprintf('Pasada 2/2: detectando bursts y extrayendo...\n');

% Sonda para conocer nFeat y los nombres
iS = find(~malos, 1);
sS = sigProc{iS} ./ escalaReg(iS,:);
[iiS, ffS] = detectarActividad(sS, cfg.Fs, cfg.det);
[fS, nombres] = extraerFeaturesBurst(sS, iiS, ffS, cfg.Fs, cfg.idxBase, cfg.thr);
nFeat = numel(fS);
fprintf('Caracteristicas por repeticion: %d\n', nFeat);

X       = zeros(n, nFeat);
Ystr    = strings(n, 1);
SubjWin = strings(n, 1);
RepID   = zeros(n, 1);
durMs   = zeros(n, 1);
fila    = 0;
fallos  = [];

for i = 1:n
    if malos(i), continue; end

    s = sigProc{i} ./ escalaReg(i,:);
    [ii, ff, info] = detectarActividad(s, cfg.Fs, cfg.det);

    if ~info.ok
        fallos(end+1) = i; %#ok<SAGROW>
        continue;          % sin burst detectado no hay nada que clasificar
    end

    fila = fila + 1;
    X(fila,:)     = extraerFeaturesBurst(s, ii, ff, cfg.Fs, cfg.idxBase, cfg.thr);
    Ystr(fila)    = frases(i);
    SubjWin(fila) = sujetos(i);
    RepID(fila)   = i;          % unico por fila -> el voto es identidad
    durMs(fila)   = info.durMs;

    if mod(i,50)==0, fprintf('   %d/%d\n', i, n); end
end

X       = X(1:fila,:);
Ystr    = Ystr(1:fila);
SubjWin = SubjWin(1:fila);
RepID   = RepID(1:fila);
durMs   = durMs(1:fila);

Y = categorical(Ystr, cellstr(cfg.clases));

%% ------------------------------------------------------------ resumen
fprintf('\n=== DATASET DE CARACTERISTICAS ===\n');
fprintf('Repeticiones     : %d  (descartadas por no detectar: %d)\n', ...
    size(X,1), numel(fallos));
if ~isempty(fallos)
    fprintf('   indices: %s\n', mat2str(fallos));
end
fprintf('Caracteristicas  : %d\n', size(X,2));
fprintf('Sujetos          : %d\n', numel(unique(SubjWin)));
fprintf('Normalizacion    : %s\n', cfg.normaliza);
fprintf('Muestras por caracteristica: %.1f\n', size(X,1)/size(X,2));
fprintf('\nRepeticiones por clase:\n');
summary(Y)

% Aviso sobre bursts anormalmente largos (los outliers del boxplot)
sosp = find(durMs > 2000);
if ~isempty(sosp)
    fprintf('\nAVISO: %d bursts de mas de 2000 ms.\n', numel(sosp));
    fprintf('Probablemente el detector fusiono dos bursts o agarro ruido.\n');
    fprintf('Estan incluidos (logDur los comprime), pero vale la pena mirar\n');
    fprintf('los registros: %s\n', mat2str(RepID(sosp).'));
end

save(cfg.salida, 'X', 'Y', 'SubjWin', 'RepID', 'nombres', 'cfg', 'durMs');
fprintf('\nGuardado en %s\n', cfg.salida);