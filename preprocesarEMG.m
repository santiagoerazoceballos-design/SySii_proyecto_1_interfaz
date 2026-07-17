function xf = preprocesarEMG(x, Fs)
% PREPROCESAREMG  Adecuacion de señales EMG crudas.
%
%   xf = preprocesarEMG(x, Fs)
%
%   x  : matriz de señal. Acepta [N x nCh] o [nCh x N] (se reorienta sola).
%   Fs : frecuencia de muestreo en Hz (en tu dataset: 1000).
%   xf : señal filtrada, siempre [N x nCh].
%
%   Cadena de procesamiento (spec III.1):
%     1. Saneo de NaN / Inf
%     2. Eliminacion de linea base (offset DC)
%     3. Notch 60 Hz + armonicos (120, 180, 240)
%     4. Pasabanda 20-400 Hz (banda util de EMG superficial)
%
%   Los filtros se diseñan una sola vez y se cachean (persistent), porque
%   designfilt es lento y esto se llama 270 veces.

    % ---- Orientacion: forzar [N x nCh] -------------------------------
    x = double(x);
    if size(x,1) < size(x,2)
        x = x.';
    end

    % ---- Saneo (spec 1.3.2: eliminacion de NaN/Inf) -------------------
    x(~isfinite(x)) = 0;

    % ---- Eliminacion de offset / linea base ---------------------------
    x = x - mean(x, 1);

    % ---- Diseño cacheado de los filtros -------------------------------
    persistent dNotch dBP FsCache
    if isempty(FsCache) || FsCache ~= Fs || isempty(dBP)
        FsCache = Fs;

        f0s = [60 120 180 240];
        f0s = f0s(f0s < 0.45*Fs);      % descarta armonicos fuera de banda
        dNotch = cell(1, numel(f0s));
        for k = 1:numel(f0s)
            dNotch{k} = designfilt('bandstopiir', ...
                'FilterOrder', 4, ...
                'HalfPowerFrequency1', f0s(k)-2, ...
                'HalfPowerFrequency2', f0s(k)+2, ...
                'SampleRate', Fs);
        end

        fHigh = min(400, 0.45*Fs);
        dBP = designfilt('bandpassiir', ...
            'FilterOrder', 6, ...
            'HalfPowerFrequency1', 20, ...
            'HalfPowerFrequency2', fHigh, ...
            'SampleRate', Fs);
    end

    % ---- Aplicacion (filtfilt = fase cero, no distorsiona timing) -----
    for k = 1:numel(dNotch)
        x = filtfilt(dNotch{k}, x);
    end
    xf = filtfilt(dBP, x);
end
