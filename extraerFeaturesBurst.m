function [f, nombres] = extraerFeaturesBurst(s, ii, ff, Fs, idxBase, thr)
% EXTRAERFEATURESBURST  Vector de caracteristicas de un burst de habla.
%
%   [f, nombres] = extraerFeaturesBurst(s, ii, ff, Fs, idxBase, thr)
%
%   s       : [N x nCh] señal completa, preprocesada y escalada por sujeto.
%   ii, ff  : indices de inicio y fin del burst (de detectarActividad).
%   Fs      : frecuencia de muestreo (Hz).
%   idxBase : indices del tramo de reposo (def 1:900).
%   thr     : umbral para ZC (def 0.05).
%
%   f       : vector FILA de 38 caracteristicas.
%   nombres : cellstr con el nombre de cada columna.
%
%   DISEÑO
%   Un vector por REPETICION, no por ventana fija. Motivo: el diagnostico
%   mostro que la informacion discriminante esta en la duracion del burst
%   (Pelicula ~1044 ms vs Agua/Cine ~770 ms) y en la distribucion de
%   energia a lo largo del burst (Cine carga el tercio central). Una
%   ventana fija de 250 ms no puede ver ninguna de las dos cosas.
%
%   El burst se divide en TERCIOS RELATIVOS (no absolutos), de modo que la
%   forma se compara entre bursts de distinta duracion.
%
%   Lo que NO se incluye a proposito:
%     - Instante de inicio: es tiempo de reaccion del sujeto, no de la
%       palabra. Incluirlo seria aprender un artefacto del protocolo.
%     - Amplitud absoluta: se cancela con la escala por sujeto. En su lugar
%       va RatioRMS (burst/reposo), que es adimensional y sobrevive a la
%       normalizacion.

    if nargin < 5 || isempty(idxBase), idxBase = 1:900;  end
    if nargin < 6 || isempty(thr),     thr     = 0.05;   end

    idxBase = idxBase(idxBase <= size(s,1));
    burst   = s(ii:ff, :);
    base    = s(idxBase, :);
    L       = size(burst, 1);
    nCh     = size(burst, 2);

    f = zeros(1,0);
    nombres = {};

    % ---------------------------------------------------- 1. duracion
    % En log: comprime los outliers de 2500-2900 ms sin descartarlos.
    durMs = 1000 * L / Fs;
    f = [f, log(durMs)];
    nombres = [nombres, {'logDur'}];

    % ------------------------------------ 2. features globales por canal
    for c = 1:nCh
        xb = burst(:,c);
        xr = base(:,c);

        % RatioRMS: energia del burst contra el reposo del MISMO registro.
        % Es la medida que en el diagnostico dio 4.20 / 2.46 / 3.66.
        rr = rms(xb) / max(rms(xr), eps);
        f = [f, log(rr)]; %#ok<AGROW>
        nombres = [nombres, {sprintf('C%d_logRatioRMS', c)}]; %#ok<AGROW>

        [MNF, MDF] = espectrales(xb, Fs);
        f = [f, MNF, MDF]; %#ok<AGROW>
        nombres = [nombres, {sprintf('C%d_MNF', c), sprintf('C%d_MDF', c)}]; %#ok<AGROW>
    end

    % --------------------------- 3. features por tercio relativo y canal
    b = round(linspace(1, L+1, 4));      % 3 tramos de igual largo relativo
    for c = 1:nCh
        for t = 1:3
            seg = burst(b(t):b(t+1)-1, c);
            if numel(seg) < 4, seg = [seg; zeros(4-numel(seg),1)]; end
            d = diff(seg);

            MAV = mean(abs(seg));
            WL  = log(sum(abs(d)) + eps);
            ZC  = sum( (seg(1:end-1).*seg(2:end) < 0) & (abs(d) > thr) ) ...
                  / max(numel(seg), 1);          % normalizado por largo
            MNFt = espectrales(seg, Fs);

            f = [f, MAV, WL, ZC, MNFt]; %#ok<AGROW>
            nombres = [nombres, ...
                {sprintf('C%d_T%d_MAV',  c, t), ...
                 sprintf('C%d_T%d_logWL',c, t), ...
                 sprintf('C%d_T%d_ZCn',  c, t), ...
                 sprintf('C%d_T%d_MNF',  c, t)}]; %#ok<AGROW>
        end
    end

    % ------------------------- 4. fraccion de energia por tercio (forma)
    % Esta es la familia que separo Cine: T1=0.203 contra ~0.41 del resto.
    e = mean(burst.^2, 2);
    et = [sum(e(b(1):b(2)-1)), sum(e(b(2):b(3)-1)), sum(e(b(3):b(4)-1))];
    et = et / max(sum(et), eps);
    f = [f, et];
    nombres = [nombres, {'E_T1','E_T2','E_T3'}];

    % ------------------------------------- 5. relacion entre los canales
    if nCh == 2
        if std(burst(:,1)) < eps || std(burst(:,2)) < eps
            r = 0;
        else
            r = corr(burst(:,1), burst(:,2));
        end
        if ~isfinite(r), r = 0; end

        m1 = mean(abs(burst(:,1)));  m2 = mean(abs(burst(:,2)));
        balance = (m1 - m2) / max(m1 + m2, eps);

        f = [f, r, balance];
        nombres = [nombres, {'X_corr','X_balance'}];
    end

    % ------------------------------------- 6. forma de la envolvente
    env = movmean(mean(abs(burst), 2), max(3, round(0.05*Fs)));
    [pico, iPico] = max(env);
    tPicoRel = iPico / L;                          % en [0,1]
    cresta   = pico / max(mean(env), eps);
    f = [f, tPicoRel, cresta];
    nombres = [nombres, {'Env_tPicoRel','Env_cresta'}];

    f(~isfinite(f)) = 0;
end

% =========================================================================
function [MNF, MDF] = espectrales(x, Fs)
% Frecuencia media y mediana del espectro de potencia.
    N = numel(x);
    P = abs(fft(x .* hamming(N))).^2;
    P = P(1:floor(N/2)+1);
    fr = (0:floor(N/2)).' * (Fs/N);
    sP = sum(P);
    if sP < eps
        MNF = 0; MDF = 0; return;
    end
    MNF = sum(fr .* P) / sP;
    acum = cumsum(P);
    MDF  = fr(find(acum >= acum(end)/2, 1, 'first'));
end
