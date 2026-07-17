function [idxIni, idxFin, info] = detectarActividad(s, Fs, opts)
% DETECTARACTIVIDAD  Encuentra el tramo de habla dentro de una señal EMG.
%
%   [idxIni, idxFin, info] = detectarActividad(s, Fs, opts)
%
%   s    : [N x nCh] señal YA preprocesada (salida de preprocesarEMG).
%   Fs   : frecuencia de muestreo (Hz).
%   opts : struct opcional con campos
%            .idxBase   muestras usadas como reposo   (def 1:900)
%            .idxBusca  rango donde buscar el burst   (def 900:4000)
%            .kOn       umbral de encendido, en sigmas de la base (def 4.0)
%            .kOff      umbral de apagado,  en sigmas de la base (def 2.0)
%            .suavizado ventana de la envolvente en ms (def 100)
%            .minDur    duracion minima del burst en ms (def 150)
%            .maxGap    huecos menores a esto se fusionan, en ms (def 120)
%            .margen    margen que se añade a cada lado, en ms (def 50)
%
%   idxIni, idxFin : indices de inicio y fin del burst. Vacios si no detecta.
%   info : struct con .env (envolvente normalizada), .thrOn, .thrOff,
%          .durMs, .ok (true si la deteccion fue exitosa)
%
%   METODO
%   Envolvente = |x| suavizado, por canal. Cada canal se normaliza contra
%   SU PROPIA estadistica de reposo (media y sigma del tramo "antes"), lo
%   cual es necesario porque los dos canales tienen lineas base distintas
%   (se ve en las graficas: un canal siempre esta mas arriba que el otro).
%   Luego se promedian los dos canales y se aplica un umbral con HISTERESIS:
%   el burst enciende en kOn sigmas y no se apaga hasta bajar de kOff. Eso
%   evita que un pico momentaneo parta el burst en pedazos.

    % ------------------------------------------------ opciones por defecto
    if nargin < 3, opts = struct(); end
    def = struct('idxBase', 1:900, 'idxBusca', 900:4000, ...
                 'kOn', 4.0, 'kOff', 2.0, 'suavizado', 100, ...
                 'minDur', 150, 'maxGap', 120, 'margen', 50);
    campos = fieldnames(def);
    for k = 1:numel(campos)
        if ~isfield(opts, campos{k}), opts.(campos{k}) = def.(campos{k}); end
    end

    N   = size(s,1);
    nCh = size(s,2);
    idxBase  = opts.idxBase(opts.idxBase  <= N);
    idxBusca = opts.idxBusca(opts.idxBusca <= N);

    % ------------------------------------------ envolvente normalizada
    win = max(3, round(opts.suavizado * Fs / 1000));
    envCh = movmean(abs(s), win, 1);            % [N x nCh]

    z = zeros(N, nCh);
    for c = 1:nCh
        mu = mean(envCh(idxBase, c));
        sd = std(envCh(idxBase, c));
        if sd < eps, sd = 1; end
        z(:,c) = (envCh(:,c) - mu) / sd;        % en sigmas de reposo
    end
    env = mean(z, 2);                            % combina los dos canales

    info.env    = env;
    info.thrOn  = opts.kOn;
    info.thrOff = opts.kOff;

    % ------------------------------------- histeresis dentro del rango
    activo = false(N,1);
    encendido = false;
    for n = idxBusca
        if ~encendido && env(n) > opts.kOn
            encendido = true;
        elseif encendido && env(n) < opts.kOff
            encendido = false;
        end
        activo(n) = encendido;
    end

    if ~any(activo)
        idxIni = []; idxFin = [];
        info.durMs = 0; info.ok = false;
        return;
    end

    % ------------------------------------------- fusionar huecos cortos
    gapMax = round(opts.maxGap * Fs / 1000);
    activo = cerrarHuecos(activo, gapMax);

    % ------------------------------- quedarse con el segmento mas largo
    d = diff([0; activo; 0]);
    inis = find(d ==  1);
    fins = find(d == -1) - 1;
    [dur, kMax] = max(fins - inis + 1);

    if dur < round(opts.minDur * Fs / 1000)
        idxIni = []; idxFin = [];
        info.durMs = 1000*dur/Fs; info.ok = false;
        return;
    end

    % ------------------------------------------------- margen y recorte
    mg = round(opts.margen * Fs / 1000);
    idxIni = max(1, inis(kMax) - mg);
    idxFin = min(N, fins(kMax) + mg);

    info.durMs = 1000 * (idxFin - idxIni + 1) / Fs;
    info.ok    = true;
end

% =========================================================================
function a = cerrarHuecos(a, gapMax)
% Une segmentos activos separados por menos de gapMax muestras.
    d = diff([1; a; 1]);
    inisHueco = find(d == -1);
    finsHueco = find(d ==  1) - 1;
    for k = 1:numel(inisHueco)
        if (finsHueco(k) - inisHueco(k) + 1) <= gapMax
            a(inisHueco(k):finsHueco(k)) = true;
        end
    end
end
