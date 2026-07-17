classdef FinalGrabar < matlab.apps.AppBase
% FINALGRABAR v3  —  Grabacion + Clasificacion EMG
%
% Layout horizontal (inspirado en Clasificador_Interface):
%   Izquierda : dos graficas apiladas (señal grabada / señal procesada)
%   Derecha   : paneles de Grabacion, Clasificacion y Evaluacion
%
% Clasificadores: KNN (con selector de K) y Centroide de Minima Distancia.
% Distancias    : Euclidiana, Manhattan, Coseno (aplica a ambos).
%
% Requiere: modelo_final.mat, preprocesarEMG.m, detectarActividad.m,
%           extraerFeaturesBurst.m, normalizarEtiqueta.m, clasifCentroide.m

    % =====================================================================
    properties (Access = public)
        UIFigure                     matlab.ui.Figure

        %% -- Graficas (izquierda) --
        UIAxes                       matlab.ui.control.UIAxes   % grabacion
        axesSenal                    matlab.ui.control.UIAxes   % procesada

        %% -- Panel Grabacion (derecha arriba) --
        PanelGrab                    matlab.ui.container.Panel
        LabelTop                     matlab.ui.control.Label
        ContinuarButton              matlab.ui.control.Button
        IdentificadorEditFieldLabel  matlab.ui.control.Label
        IdentificadorEditField       matlab.ui.control.EditField
        SexoDropDownLabel            matlab.ui.control.Label
        SexoDropDown                 matlab.ui.control.DropDown
        RepeticionEditFieldLabel     matlab.ui.control.Label
        RepeticionEditField          matlab.ui.control.NumericEditField
        DatasetEditFieldLabel        matlab.ui.control.Label
        DatasetNombre                matlab.ui.control.EditField
        EscogerDatasetButton         matlab.ui.control.Button
        lblCOM                       matlab.ui.control.Label
        efCOM                        matlab.ui.control.EditField
        FraseEditFieldLabel          matlab.ui.control.Label
        FraseEditField               matlab.ui.control.EditField

        %% -- Info modelo (etiqueta entre paneles) --
        lblModelInfo                 matlab.ui.control.Label

        %% -- Panel Clasificacion (derecha centro) --
        PanelClas                    matlab.ui.container.Panel
        lblModeloClas                matlab.ui.control.Label
        ddClasificador               matlab.ui.control.DropDown
        lblK                         matlab.ui.control.Label
        efK                          matlab.ui.control.NumericEditField
        lblDistanciaClas             matlab.ui.control.Label
        ddDistancia                  matlab.ui.control.DropDown
        lblInfoClas                  matlab.ui.control.Label
        btnCargarDataset             matlab.ui.control.Button
        btnClasificar                matlab.ui.control.Button

        %% -- Resultado (fuera de panel, destacado) --
        lblResultado                 matlab.ui.control.Label
        lblConf                      matlab.ui.control.Label

        %% -- Panel Evaluacion (derecha abajo) --
        PanelEval                    matlab.ui.container.Panel
        lblResumen                   matlab.ui.control.Label
        tablaHistorial               matlab.ui.control.Table
        btnMatrizKNN                 matlab.ui.control.Button
        btnMatrizCentroide           matlab.ui.control.Button
        btnGuardarCSV                matlab.ui.control.Button
        btnBorrarHistorial           matlab.ui.control.Button
    end

    % =====================================================================
    properties (Access = private)
        %% -- Grabacion --
        Etapa = 0
        dataset
        genero
        archivo = 'dataset_emg.mat'
        sobreescribir = 0
        omitir = 0

        %% -- Clasificacion --
        modelo
        dtsClasif
        zvec
        idxIni
        idxFin
        etiquetaActual = ""
        sujetoActual   = ""
        historial
        LOG = 'historial_clasificacion.csv'
    end

    % =====================================================================
    methods (Access = private)   % ---- helpers ----

        function cargarModelo(app)
            if ~isfile('modelo_final.mat'), return; end
            try
                S = load('modelo_final.mat','modelo');
                app.modelo = S.modelo;
            catch
            end
        end

        % ------------------------------------------------------------------
        function procesarYMostrar(app, senal)
        % Preprocesa la señal, actualiza axesSenal (solo la señal filtrada,
        % sin marcas de burst), extrae features y deja app.zvec listo.
            if isempty(app.modelo)
                app.lblResultado.Text = 'Sin modelo — corre entrenarModeloFinal.m';
                return;
            end
            cfg = app.modelo.cfg;
            Fs  = cfg.Fs;
            if size(senal,1) < size(senal,2), senal = senal.'; end

            % Preprocesar
            s = preprocesarEMG(senal, Fs);

            % Escala causal por reposo
            e = prctile(abs(s(cfg.idxBase,:)), cfg.percentil, 1);
            e(e < eps) = 1;
            s = s ./ e;

            % Graficar la señal filtrada limpia (sin envolvente, sin burst)
            t = (0:size(s,1)-1) / Fs;
            cla(app.axesSenal);
            hold(app.axesSenal,'on');
            plot(app.axesSenal, t, s(:,1), 'Color',[0 0.7 0.9], 'LineWidth',0.7);
            plot(app.axesSenal, t, s(:,2), 'Color',[0.9 0.4 0],  'LineWidth',0.7);
            legend(app.axesSenal,{'Canal 1','Canal 2'}, ...
                   'TextColor','w','Color','none','Location','northeast');
            hold(app.axesSenal,'off');

            % Detectar burst (solo para extraer features, no se visualiza)
            [ii, ff, info] = detectarActividad(s, Fs, cfg.det);
            app.zvec = []; app.idxIni = []; app.idxFin = [];

            if info.ok
                app.idxIni = ii; app.idxFin = ff;
                fvec = extraerFeaturesBurst(s, ii, ff, Fs, cfg.idxBase, cfg.thr);
                app.zvec = (fvec - app.modelo.mu) ./ app.modelo.sg;
                app.lblConf.Text = sprintf('Señal lista  |  %s  |  Duracion: %.0f ms', ...
                    char(app.etiquetaActual), info.durMs);
                app.lblResultado.Text = '--';
                app.lblResultado.FontColor = [0.6 0.6 0.6];
                app.btnClasificar.Enable = 'on';
            else
                app.lblConf.Text = 'Sin actividad detectada — revisa la señal';
                app.lblResultado.Text = 'Sin actividad';
                app.lblResultado.FontColor = [0.8 0.3 0.3];
                app.btnClasificar.Enable = 'off';
            end
        end

        % ------------------------------------------------------------------
        function refrescarTabla(app)
            if isempty(app.historial) || height(app.historial) == 0
                app.tablaHistorial.Data = {};
                app.lblResumen.Text = 'Sin clasificaciones registradas';
                return;
            end
            r  = app.historial;
            n  = min(height(r), 6);
            sub = r(end-n+1:end, {'Verdadera','Predicha','Modelo','Distancia','Conf'});
            d  = table2cell(sub);
            % uitable exige char/numeric/logical — nunca string ni <missing>
            for k = 1:numel(d)
                val = d{k};
                if (isstring(val) || iscategorical(val)) && any(ismissing(val))
                    d{k} = '';
                elseif isstring(val) || ischar(val)
                    d{k} = char(val);
                elseif isnumeric(val)
                    d{k} = double(val);
                else
                    d{k} = '';
                end
            end
            app.tablaHistorial.Data = d;

            con = r(r.Verdadera ~= "",:);
            if height(con) == 0
                app.lblResumen.Text = sprintf('%d clasificaciones (sin etiqueta real)', height(r));
            else
                ac = sum(con.Verdadera == con.Predicha);
                app.lblResumen.Text = sprintf('Aciertos: %d / %d  (%.0f%%)   |   Total: %d', ...
                    ac, height(con), 100*ac/height(con), height(r));
            end
        end

        % ------------------------------------------------------------------
        function anotarResultado(app, predicha, modelo_n, dist_n, conf, durMs)
            fila = table(string(datetime('now')), app.etiquetaActual, predicha, ...
                string(modelo_n), string(dist_n), conf, durMs, string(app.sujetoActual), ...
                'VariableNames', ...
                {'Fecha','Verdadera','Predicha','Modelo','Distancia','Conf','DurMs','Sujeto'});
            if isempty(app.historial)
                app.historial = fila;
            else
                app.historial = [app.historial; fila];
            end
            try, writetable(app.historial, app.LOG); catch, end
            app.refrescarTabla();
        end

        % ------------------------------------------------------------------
        function md = distanciaAMatlab(~, nombre)
            switch lower(string(nombre))
                case 'manhattan',  md = 'cityblock';
                case 'euclidiana', md = 'euclidean';
                case 'coseno',     md = 'cosine';
                otherwise,         md = char(nombre);
            end
        end

        function s = distanciaAmigable(~, matlab_d)
            switch lower(string(matlab_d))
                case 'cityblock',  s = 'Manhattan';
                case 'euclidean',  s = 'Euclidiana';
                case 'cosine',     s = 'Coseno';
                otherwise,         s = char(matlab_d);
            end
        end
    end

    % =====================================================================
    methods (Access = private)   % ---- callbacks ----

        %% ------- Grabacion (identico al original) -----------------------

        function ContinuarButtonPushed(app, event)
            switch app.Etapa
                case 0
                    if (ischar(app.archivo)||isstring(app.archivo)) && exist(app.archivo,'file')
                        load(app.archivo,'dts'); app.dataset = dts;
                    else
                        app.dataset = struct([]);
                    end
                    indicesSujeto = [];
                    for i = 1:length(app.dataset)
                        if strcmpi(app.dataset(i).idSujeto, app.IdentificadorEditField.Value)
                            indicesSujeto(end+1) = i;
                        end
                    end
                    if isempty(indicesSujeto)
                        app.LabelTop.Text = "Nuevo ID. Presiona Continuar para grabar.";
                        app.genero = app.SexoDropDown.Value;
                    else
                        app.LabelTop.Text = "ID ya existe. Presiona Continuar para grabar.";
                        app.genero = app.dataset(indicesSujeto(1)).genero;
                    end
                    app.Etapa = 1;
                    app.SexoDropDown.Enable         = "off";
                    app.IdentificadorEditField.Enable= "off";
                    app.EscogerDatasetButton.Enable = "off";
                    app.FraseEditField.Enable       = "off";

                case {1,2,3,4,5}
                    app.sobreescribir = 0; app.omitir = 0;
                    app.RepeticionEditField.Value = app.Etapa;
                    indiceExistente = [];
                    for i = 1:length(app.dataset)
                        if strcmpi(app.dataset(i).idSujeto, app.IdentificadorEditField.Value) ...
                                && app.dataset(i).repeticion == app.Etapa
                            indiceExistente = i; break;
                        end
                    end
                    if ~isempty(indiceExistente)
                        a = uiconfirm(app.UIFigure,'¿Sobreescribir esta repeticion?', ...
                            'Repeticion #'+string(app.Etapa)+' ya existe','Options',{'Si','No'});
                        if strcmp(a,'Si'), app.sobreescribir=1; else, app.omitir=1; end
                    else
                        a = uiconfirm(app.UIFigure,'¿Que deseas hacer?', ...
                            'Repeticion #'+string(app.Etapa),'Options',{'Capturar','Omitir'});
                        if strcmp(a,'Omitir'), app.omitir=1; end
                    end

                    senal = [];
                    if app.omitir == 0
                        app.ContinuarButton.Enable = "off";
                        s_port = serialport(app.efCOM.Value, 115200); flush(s_port);
                        Fs=1000; hablar=2500; silencio=1000; N=2*silencio+hablar;
                        data = zeros(2,N); time = (0:N-1)/Fs;
                        plot(app.UIAxes, time, data);
                        i=1; cnt=0;
                        app.LabelTop.Text="Silencio...";
                        app.LabelTop.BackgroundColor="yellow";
                        app.LabelTop.FontColor="black";
                        while i < N+1
                            if s_port.NumBytesAvailable > 0
                                raw = readline(s_port); v = split(raw);
                                if numel(v)>=2
                                    v1=str2double(v(1)); v2=str2double(v(2));
                                    if ~isnan(v1)&&~isnan(v2)
                                        data(1,i)=v1; data(2,i)=v2; i=i+1; cnt=cnt+1;
                                        if cnt>=250, plot(app.UIAxes,time,data); cnt=0; end
                                        switch i
                                            case silencio
                                                app.LabelTop.Text="Habla!";
                                                app.LabelTop.BackgroundColor="green";
                                            case (silencio+hablar)
                                                app.LabelTop.Text="Silencio...";
                                                app.LabelTop.BackgroundColor="yellow";
                                        end
                                    end
                                end
                            end
                        end
                        senal = data;
                        plot(app.UIAxes, time, senal);
                        app.LabelTop.BackgroundColor="black";
                        app.LabelTop.FontColor="white";
                        app.ContinuarButton.Enable="on";
                        clear s_port;

                        % Auto-procesar en el panel de clasificacion
                        if ~isempty(app.modelo)
                            app.etiquetaActual = normalizarEtiqueta(app.FraseEditField.Value);
                            app.sujetoActual   = regexprep(string(app.IdentificadorEditField.Value),'\d+$','');
                            app.procesarYMostrar(senal);
                        end
                    end

                    if size(senal,1)~=2 && app.omitir==0
                        app.LabelTop.Text='Error: la señal debe tener 2 canales.'; return; end
                    if any(isnan(senal),'all') && app.omitir==0
                        app.LabelTop.Text='Error: NaN en la señal.'; return; end
                    if any(isinf(senal),'all') && app.omitir==0
                        app.LabelTop.Text='Error: Inf en la señal.'; return; end

                    if app.omitir==0 || app.sobreescribir==1
                        registro.idSujeto  = app.IdentificadorEditField.Value;
                        registro.genero    = app.genero;
                        registro.repeticion= app.Etapa;
                        registro.senal     = senal;
                        registro.frase     = app.FraseEditField.Value;
                    end
                    if isempty(app.dataset)&&(app.omitir==0)
                        app.dataset=registro;
                        app.LabelTop.Text='Primera repeticion guardada.';
                    elseif isempty(indiceExistente)&&(app.omitir==0)
                        app.dataset(end+1)=registro;
                        app.LabelTop.Text='Repeticion #'+string(app.Etapa)+' guardada.';
                    elseif app.sobreescribir==1
                        app.dataset(indiceExistente)=registro;
                        app.LabelTop.Text='Repeticion #'+string(app.Etapa)+' sobreescrita.';
                    elseif app.omitir==1
                        app.LabelTop.Text='Repeticion #'+string(app.Etapa)+' omitida.';
                    end
                    dts=app.dataset; save(app.archivo,'dts');

                    if app.Etapa==5
                        a=uiconfirm(app.UIFigure,'¿Ingresar otro sujeto?','Registro finalizado','Options',{'Si','No'});
                        if strcmp(a,'No'), delete(app); return; end
                        app.Etapa=0;
                        app.LabelTop.Text="Ingresa los datos del sujeto.";
                        app.EscogerDatasetButton.Enable="on";
                        app.SexoDropDown.Enable="on";
                        app.IdentificadorEditField.Enable="on";
                        app.FraseEditField.Enable="on";
                        app.RepeticionEditField.Value=0;
                    else
                        app.Etapa=app.Etapa+1;
                    end
            end
        end

        function EscogerDatasetButtonPushed(app, event)
            app.archivo = uigetfile;
            app.DatasetNombre.Value = string(app.archivo);
        end

        %% ------- Clasificacion ------------------------------------------

        function ddClasificadorValueChanged(app, event)
            % Habilita el campo K solo cuando se selecciona KNN
            esKNN = strcmp(app.ddClasificador.Value,'KNN');
            if esKNN
                app.efK.Enable = 'on';
                app.lblK.FontColor = [0.9 0.9 0.9];
            else
                app.efK.Enable = 'off';
                app.lblK.FontColor = [0.45 0.45 0.45];
            end
        end

        function btnCargarDatasetPushed(app, event)
            if isempty(app.modelo)
                uialert(app.UIFigure,'Sin modelo. Corre entrenarModeloFinal.m.','Aviso'); return;
            end
            if isempty(app.dtsClasif)
                [f,p] = uigetfile('*.mat','Seleccionar dataset');
                if isequal(f,0), return; end
                try
                    S = load(fullfile(p,f),'dts'); app.dtsClasif = S.dts;
                catch
                    uialert(app.UIFigure,'Archivo invalido o sin variable dts.','Error'); return;
                end
            end
            n = numel(app.dtsClasif);
            items = strings(n,1);
            for k=1:n
                items(k)=sprintf('%3d | %-14s | %s',k, ...
                    string(app.dtsClasif(k).idSujeto),string(app.dtsClasif(k).frase));
            end
            [ix,ok]=listdlg('PromptString','Selecciona un registro:', ...
                'SelectionMode','single','ListString',cellstr(items), ...
                'ListSize',[310 380],'Name','Dataset');
            if ~ok, return; end
            reg = app.dtsClasif(ix);
            app.etiquetaActual = normalizarEtiqueta(reg.frase);
            app.sujetoActual   = regexprep(string(reg.idSujeto),'\d+$','');
            app.procesarYMostrar(double(reg.senal));
        end

        function btnClasificarPushed(app, event)
            if isempty(app.zvec)
                uialert(app.UIFigure,'Primero captura o carga una señal.','Sin señal'); return;
            end
            clases  = app.modelo.clases;
            dist_ui = app.ddDistancia.Value;
            dist_ml = app.distanciaAMatlab(dist_ui);
            durMs   = 0;
            if ~isempty(app.idxIni)&&~isempty(app.idxFin)
                durMs = 1000*(app.idxFin-app.idxIni+1)/app.modelo.cfg.Fs;
            end

            switch app.ddClasificador.Value
                case 'KNN'
                    K = max(1, round(app.efK.Value));
                    if isfield(app.modelo,'Ztr') && isfield(app.modelo,'Ytr')
                        mdlTemp = fitcknn(app.modelo.Ztr, app.modelo.Ytr, ...
                            'NumNeighbors',K,'Distance',dist_ml);
                        [pred, score] = predict(mdlTemp, app.zvec);
                    else
                        % Fallback si el modelo no tiene los datos de entrenamiento
                        [pred, score] = predict(app.modelo.mdl, app.zvec);
                        dist_ui = app.distanciaAmigable(app.modelo.dist);
                    end
                    predicha = string(pred);
                    conf     = max(score);
                    modelo_n = sprintf('KNN (K=%d)', K);

                case 'Centroide - Minima Distancia'
                    C = app.modelo.centroides;
                    switch dist_ml
                        case 'euclidean', D = pdist2(app.zvec,C,'euclidean');
                        case 'cityblock', D = pdist2(app.zvec,C,'cityblock');
                        case 'cosine',    D = pdist2(app.zvec,C,'cosine');
                    end
                    [~,idx] = min(D);
                    predicha = string(clases{idx});
                    sumD = sum(D); if sumD<eps, sumD=1; end
                    conf = 1 - min(D)/sumD;
                    modelo_n = 'Centroide';
            end

            % Mostrar resultado
            app.lblResultado.Text = char(predicha);
            if app.etiquetaActual ~= ""
                if predicha == app.etiquetaActual
                    app.lblResultado.FontColor = [0.2 0.85 0.2];
                    marca = 'ACIERTO';
                else
                    app.lblResultado.FontColor = [0.9 0.2 0.2];
                    marca = sprintf('FALLO  (real: %s)', app.etiquetaActual);
                end
                app.lblConf.Text = sprintf('Confianza: %.0f%%   |   %s   |   Dist: %s', ...
                    100*conf, marca, dist_ui);
            else
                app.lblResultado.FontColor = [1 1 1];
                app.lblConf.Text = sprintf('Confianza: %.0f%%   |   Dist: %s', 100*conf, dist_ui);
            end

            app.anotarResultado(predicha, modelo_n, dist_ui, conf, durMs);
        end

        %% ------- Evaluacion ---------------------------------------------

        function btnMatrizKNNPushed(app, event)
            if isempty(app.historial)
                uialert(app.UIFigure,'Sin historial.','Aviso'); return; end
            r = app.historial(contains(lower(string(app.historial.Modelo)),'knn') & ...
                app.historial.Verdadera~="",:);
            if height(r)<2
                uialert(app.UIFigure,'Se necesitan al menos 2 pruebas KNN con etiqueta real.','Aviso'); return; end
            cl = app.modelo.clases;
            figure('Name','Matriz de Confusion — KNN','Position',[200 200 560 480]);
            confusionchart(categorical(r.Verdadera,cl),categorical(r.Predicha,cl), ...
                'RowSummary','row-normalized', ...
                'Title',sprintf('KNN — %.0f%%  (n=%d)',100*mean(r.Verdadera==r.Predicha),height(r)));
        end

        function btnMatrizCentroidePushed(app, event)
            if isempty(app.historial)
                uialert(app.UIFigure,'Sin historial.','Aviso'); return; end
            r = app.historial(lower(string(app.historial.Modelo))=="centroide" & ...
                app.historial.Verdadera~="",:);
            if height(r)<2
                uialert(app.UIFigure,'Se necesitan al menos 2 pruebas de Centroide con etiqueta real.','Aviso'); return; end
            cl = app.modelo.clases;
            figure('Name','Matriz de Confusion — Centroide','Position',[240 240 560 480]);
            confusionchart(categorical(r.Verdadera,cl),categorical(r.Predicha,cl), ...
                'RowSummary','row-normalized', ...
                'Title',sprintf('Centroide — %.0f%%  (n=%d)',100*mean(r.Verdadera==r.Predicha),height(r)));
        end

        function btnGuardarCSVPushed(app, event)
            if isempty(app.historial)||height(app.historial)==0
                uialert(app.UIFigure,'No hay nada que guardar.','Aviso'); return; end
            [f,p]=uiputfile('*.csv','Guardar historial','resultados_clasificacion.csv');
            if isequal(f,0), return; end
            writetable(app.historial,fullfile(p,f));
            uialert(app.UIFigure,'Guardado correctamente.','Listo','Icon','success');
        end

        function btnBorrarHistorialPushed(app, event)
            a=uiconfirm(app.UIFigure,'¿Borrar todo el historial?','Confirmar', ...
                'Options',{'Si, borrar','Cancelar'},'DefaultOption','Cancelar','CancelOption','Cancelar');
            if strcmp(a,'Cancelar'), return; end
            app.historial=[];
            if isfile(app.LOG), delete(app.LOG); end
            app.refrescarTabla();
        end
    end

    % =====================================================================
    methods (Access = private)

        function createComponents(app)
            gris  = [0.149 0.149 0.149];
            negro = [0.10  0.10  0.10 ];

            % Ventana: 1150 x 760
            app.UIFigure = uifigure('Visible','off');
            app.UIFigure.Position = [100 80 1150 760];
            app.UIFigure.Name  = 'Grabacion y Clasificacion EMG';
            app.UIFigure.Color = negro;

            % =============================================================
            % LADO IZQUIERDO: dos graficas apiladas
            % =============================================================

            % Grafica 1: señal grabada en tiempo real
            app.UIAxes = uiaxes(app.UIFigure);
            title(app.UIAxes,'1. Señal Grabada en Tiempo Real');
            xlabel(app.UIAxes,'Tiempo (s)'); ylabel(app.UIAxes,'Voltaje (V)');
            app.UIAxes.XLimitMethod = 'tight';
            app.UIAxes.XGrid = 'on'; app.UIAxes.YGrid = 'on';
            app.UIAxes.Position = [15 400 560 340];

            % Grafica 2: señal procesada (limpia, sin burst marcado)
            app.axesSenal = uiaxes(app.UIFigure);
            title(app.axesSenal,'2. Señal Procesada (filtrada y escalada)');
            xlabel(app.axesSenal,'Tiempo (s)'); ylabel(app.axesSenal,'Amplitud');
            app.axesSenal.Position = [15 35 560 340];
            app.axesSenal.Color    = [0 0 0];
            app.axesSenal.XColor   = [0.9 0.9 0.9];
            app.axesSenal.YColor   = [0.9 0.9 0.9];
            app.axesSenal.Title.Color = [1 1 1];
            app.axesSenal.XGrid = 'on'; app.axesSenal.YGrid = 'on';
            app.axesSenal.GridColor = [0.4 0.4 0.4];

            % =============================================================
            % LADO DERECHO: paneles
            % =============================================================

            %% ---- Panel Grabacion  [590 530 545 215] --------------------
            app.PanelGrab = uipanel(app.UIFigure);
            app.PanelGrab.Title = 'Grabacion de Dataset';
            app.PanelGrab.TitlePosition = 'centertop';
            app.PanelGrab.FontWeight = 'bold'; app.PanelGrab.FontSize = 13;
            app.PanelGrab.ForegroundColor = [0.9 0.9 0.9];
            app.PanelGrab.BackgroundColor = gris;
            app.PanelGrab.Position = [590 530 545 215];

            % LabelTop (estado del proceso)
            app.LabelTop = uilabel(app.PanelGrab);
            app.LabelTop.BackgroundColor = [0 0 0];
            app.LabelTop.FontColor = [1 1 1];
            app.LabelTop.HorizontalAlignment = 'center';
            app.LabelTop.WordWrap = 'on';
            app.LabelTop.FontSize = 12;
            app.LabelTop.Position = [10 163 380 30];
            app.LabelTop.Text = 'Ingresa los datos del sujeto.';

            % Boton Continuar
            app.ContinuarButton = uibutton(app.PanelGrab,'push');
            app.ContinuarButton.ButtonPushedFcn = createCallbackFcn(app,@ContinuarButtonPushed,true);
            app.ContinuarButton.Position = [395 163 140 30];
            app.ContinuarButton.Text = 'Continuar';
            app.ContinuarButton.FontSize = 13; app.ContinuarButton.FontWeight = 'bold';

            % Fila 1: Identificador | Sexo | Repeticion
            app.IdentificadorEditFieldLabel = uilabel(app.PanelGrab);
            app.IdentificadorEditFieldLabel.Text = 'ID';
            app.IdentificadorEditFieldLabel.Position = [10 128 20 22];

            app.IdentificadorEditField = uieditfield(app.PanelGrab,'text');
            app.IdentificadorEditField.Position = [34 128 105 22];

            app.SexoDropDownLabel = uilabel(app.PanelGrab);
            app.SexoDropDownLabel.Text = 'Sexo';
            app.SexoDropDownLabel.HorizontalAlignment = 'right';
            app.SexoDropDownLabel.Position = [148 128 35 22];

            app.SexoDropDown = uidropdown(app.PanelGrab);
            app.SexoDropDown.Items = {'Masculino','Femenino'};
            app.SexoDropDown.Value = 'Masculino';
            app.SexoDropDown.Position = [187 128 105 22];

            app.RepeticionEditFieldLabel = uilabel(app.PanelGrab);
            app.RepeticionEditFieldLabel.Text = 'Repeticion';
            app.RepeticionEditFieldLabel.HorizontalAlignment = 'right';
            app.RepeticionEditFieldLabel.Enable = 'off';
            app.RepeticionEditFieldLabel.Position = [300 128 72 22];

            app.RepeticionEditField = uieditfield(app.PanelGrab,'numeric');
            app.RepeticionEditField.Enable = 'off';
            app.RepeticionEditField.Position = [376 128 60 22];

            % Fila 2: Dataset
            app.DatasetEditFieldLabel = uilabel(app.PanelGrab);
            app.DatasetEditFieldLabel.Text = 'Dataset';
            app.DatasetEditFieldLabel.Enable = 'off';
            app.DatasetEditFieldLabel.Position = [10 96 48 22];

            app.DatasetNombre = uieditfield(app.PanelGrab,'text');
            app.DatasetNombre.Enable = 'off';
            app.DatasetNombre.Position = [62 96 175 22];

            app.EscogerDatasetButton = uibutton(app.PanelGrab,'push');
            app.EscogerDatasetButton.ButtonPushedFcn = createCallbackFcn(app,@EscogerDatasetButtonPushed,true);
            app.EscogerDatasetButton.Position = [244 94 200 25];
            app.EscogerDatasetButton.Text = 'Escoger Dataset';

            app.lblCOM = uilabel(app.PanelGrab);
            app.lblCOM.Text = 'COM:';
            app.lblCOM.FontColor = [0.9 0.9 0.9];
            app.lblCOM.Position = [452 96 32 22];

            app.efCOM = uieditfield(app.PanelGrab,'text');
            app.efCOM.Value = 'COM4';
            app.efCOM.Position = [487 94 48 25];

            % Fila 3: Frase
            app.FraseEditFieldLabel = uilabel(app.PanelGrab);
            app.FraseEditFieldLabel.Text = 'Frase';
            app.FraseEditFieldLabel.Position = [10 62 38 22];

            app.FraseEditField = uieditfield(app.PanelGrab,'text');
            app.FraseEditField.Position = [52 62 483 22];

            %% ---- Label info del modelo ---------------------------------
            app.lblModelInfo = uilabel(app.UIFigure);
            app.lblModelInfo.Position = [590 513 545 15];
            app.lblModelInfo.HorizontalAlignment = 'center';
            app.lblModelInfo.FontSize = 10;
            app.lblModelInfo.FontColor = [0.55 0.55 0.55];
            app.lblModelInfo.Text = 'Cargando modelo...';

            %% ---- Panel Clasificacion  [590 345 545 163] ----------------
            app.PanelClas = uipanel(app.UIFigure);
            app.PanelClas.Title = 'Clasificacion';
            app.PanelClas.TitlePosition = 'centertop';
            app.PanelClas.FontWeight = 'bold'; app.PanelClas.FontSize = 13;
            app.PanelClas.ForegroundColor = [0.9 0.9 0.9];
            app.PanelClas.BackgroundColor = gris;
            app.PanelClas.Position = [590 345 545 163];

            % Fila modelo + K + distancia
            app.lblModeloClas = uilabel(app.PanelClas);
            app.lblModeloClas.Text = 'Modelo:';
            app.lblModeloClas.FontColor = [0.9 0.9 0.9];
            app.lblModeloClas.Position = [10 115 55 22];

            app.ddClasificador = uidropdown(app.PanelClas);
            app.ddClasificador.Items = {'KNN','Centroide - Minima Distancia'};
            app.ddClasificador.Value = 'KNN';
            app.ddClasificador.Position = [68 112 170 25];
            app.ddClasificador.ValueChangedFcn = createCallbackFcn(app,@ddClasificadorValueChanged,true);

            app.lblK = uilabel(app.PanelClas);
            app.lblK.Text = 'K:';
            app.lblK.FontColor = [0.9 0.9 0.9];
            app.lblK.HorizontalAlignment = 'right';
            app.lblK.Position = [246 115 20 22];

            app.efK = uieditfield(app.PanelClas,'numeric');
            app.efK.Value = 15;
            app.efK.Limits = [1 Inf];
            app.efK.RoundFractionalValues = 'on';
            app.efK.Position = [269 112 48 25];

            app.lblDistanciaClas = uilabel(app.PanelClas);
            app.lblDistanciaClas.Text = 'Distancia:';
            app.lblDistanciaClas.FontColor = [0.9 0.9 0.9];
            app.lblDistanciaClas.HorizontalAlignment = 'right';
            app.lblDistanciaClas.Position = [322 115 68 22];

            app.ddDistancia = uidropdown(app.PanelClas);
            app.ddDistancia.Items = {'Euclidiana','Manhattan','Coseno'};
            app.ddDistancia.Value = 'Manhattan';
            app.ddDistancia.Position = [394 112 138 25];

            % Nota informativa
            app.lblInfoClas = uilabel(app.PanelClas);
            app.lblInfoClas.Text = 'La distancia aplica a ambos clasificadores. K solo aplica al KNN.';
            app.lblInfoClas.FontColor = [0.55 0.55 0.55];
            app.lblInfoClas.FontSize = 10;
            app.lblInfoClas.Position = [10 90 525 16];

            % Botones
            app.btnCargarDataset = uibutton(app.PanelClas,'push');
            app.btnCargarDataset.ButtonPushedFcn = createCallbackFcn(app,@btnCargarDatasetPushed,true);
            app.btnCargarDataset.Position = [10 52 253 30];
            app.btnCargarDataset.Text = 'Cargar del Dataset';
            app.btnCargarDataset.FontSize = 12;
            app.btnCargarDataset.BackgroundColor = [0.25 0.25 0.25];
            app.btnCargarDataset.FontColor = [1 1 1];

            app.btnClasificar = uibutton(app.PanelClas,'push');
            app.btnClasificar.ButtonPushedFcn = createCallbackFcn(app,@btnClasificarPushed,true);
            app.btnClasificar.Position = [272 49 263 34];
            app.btnClasificar.Text = 'Clasificar';
            app.btnClasificar.FontSize = 15; app.btnClasificar.FontWeight = 'bold';
            app.btnClasificar.BackgroundColor = [0.2 0.35 0.6];
            app.btnClasificar.FontColor = [1 1 1];
            app.btnClasificar.Enable = 'off';

            %% ---- Resultado (destacado, fuera del panel) ----------------
            app.lblResultado = uilabel(app.UIFigure);
            app.lblResultado.Position = [590 305 545 38];
            app.lblResultado.HorizontalAlignment = 'center';
            app.lblResultado.FontSize = 32; app.lblResultado.FontWeight = 'bold';
            app.lblResultado.FontColor = [0.6 0.6 0.6];
            app.lblResultado.BackgroundColor = [0 0 0];
            app.lblResultado.Text = '--';

            app.lblConf = uilabel(app.UIFigure);
            app.lblConf.Position = [590 288 545 16];
            app.lblConf.HorizontalAlignment = 'center';
            app.lblConf.FontSize = 11;
            app.lblConf.FontColor = [0.8 0.8 0.8];
            app.lblConf.Text = '';

            %% ---- Panel Evaluacion  [590 15 545 268] --------------------
            app.PanelEval = uipanel(app.UIFigure);
            app.PanelEval.Title = 'Evaluacion de Desempeño';
            app.PanelEval.TitlePosition = 'centertop';
            app.PanelEval.FontWeight = 'bold'; app.PanelEval.FontSize = 13;
            app.PanelEval.ForegroundColor = [0.9 0.9 0.9];
            app.PanelEval.BackgroundColor = gris;
            app.PanelEval.Position = [590 15 545 268];

            app.lblResumen = uilabel(app.PanelEval);
            app.lblResumen.Position = [10 242 525 18];
            app.lblResumen.HorizontalAlignment = 'center';
            app.lblResumen.FontSize = 12; app.lblResumen.FontWeight = 'bold';
            app.lblResumen.FontColor = [1 1 1];
            app.lblResumen.Text = 'Sin clasificaciones registradas';

            app.tablaHistorial = uitable(app.PanelEval);
            app.tablaHistorial.Position = [10 128 525 110];
            app.tablaHistorial.ColumnName  = {'Real','Predicha','Modelo','Distancia','Conf'};
            app.tablaHistorial.ColumnWidth = {75,80,120,88,55};

            % Fila botones 1
            app.btnMatrizKNN = uibutton(app.PanelEval,'push');
            app.btnMatrizKNN.ButtonPushedFcn = createCallbackFcn(app,@btnMatrizKNNPushed,true);
            app.btnMatrizKNN.Position = [10 88 255 30];
            app.btnMatrizKNN.Text = 'Matriz de Confusion KNN';
            app.btnMatrizKNN.BackgroundColor = [0.18 0.23 0.42];
            app.btnMatrizKNN.FontColor = [1 1 1];

            app.btnMatrizCentroide = uibutton(app.PanelEval,'push');
            app.btnMatrizCentroide.ButtonPushedFcn = createCallbackFcn(app,@btnMatrizCentroidePushed,true);
            app.btnMatrizCentroide.Position = [272 88 263 30];
            app.btnMatrizCentroide.Text = 'Matriz de Confusion Centroide';
            app.btnMatrizCentroide.BackgroundColor = [0.18 0.23 0.42];
            app.btnMatrizCentroide.FontColor = [1 1 1];

            % Fila botones 2
            app.btnGuardarCSV = uibutton(app.PanelEval,'push');
            app.btnGuardarCSV.ButtonPushedFcn = createCallbackFcn(app,@btnGuardarCSVPushed,true);
            app.btnGuardarCSV.Position = [10 48 255 30];
            app.btnGuardarCSV.Text = 'Guardar Historial CSV';
            app.btnGuardarCSV.BackgroundColor = [0.25 0.25 0.25];
            app.btnGuardarCSV.FontColor = [1 1 1];

            app.btnBorrarHistorial = uibutton(app.PanelEval,'push');
            app.btnBorrarHistorial.ButtonPushedFcn = createCallbackFcn(app,@btnBorrarHistorialPushed,true);
            app.btnBorrarHistorial.Position = [272 48 263 30];
            app.btnBorrarHistorial.Text = 'Borrar Historial';
            app.btnBorrarHistorial.BackgroundColor = [0.42 0.12 0.12];
            app.btnBorrarHistorial.FontColor = [1 1 1];

            app.UIFigure.Visible = 'on';
        end
    end

    % =====================================================================
    methods (Access = public)

        function app = FinalGrabar
            createComponents(app)
            registerApp(app, app.UIFigure)

            % Cargar modelo
            app.cargarModelo();
            if ~isempty(app.modelo)
                app.efK.Value = app.modelo.K;
                app.lblModelInfo.Text = sprintf( ...
                    'Modelo: KNN K=%d  |  %d sujetos  |  Centroide: %d clases  |  norm: %s', ...
                    app.modelo.K, app.modelo.nSujetos, numel(app.modelo.clases), ...
                    app.modelo.cfg.normaliza);
            else
                app.lblModelInfo.Text = 'Sin modelo — ejecuta entrenarModeloFinal.m primero';
            end

            % Cargar historial previo
            if isfile(app.LOG)
                try
                    app.historial = readtable(app.LOG,'TextType','string');
                    app.refrescarTabla();
                catch, end
            end

            if nargout == 0, clear app; end
        end

        function delete(app)
            delete(app.UIFigure)
        end
    end
end
