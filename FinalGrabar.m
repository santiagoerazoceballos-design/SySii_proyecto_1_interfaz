classdef FinalGrabar < matlab.apps.AppBase
% FINALGRABAR v4  —  Archivo unico del Proyecto 2
%
% Contiene TODO sin archivos externos adicionales:
%   - Interfaz grafica (grabacion + clasificacion)
%   - Funciones de procesamiento (preprocesarEMG, detectarActividad, etc.)
%   - Pipeline de entrenamiento (construir dataset, entrenar, LOSO, despliegue)
%
% Solo requiere en la misma carpeta:
%   modelo_final.mat   (se genera con el pipeline integrado)
%   dataset_parc2.mat  (el dataset de señales)
%
% Uso: FinalGrabar   (en la Command Window)

    % =====================================================================
    properties (Access = public)
        UIFigure                     matlab.ui.Figure

        % Graficas
        UIAxes                       matlab.ui.control.UIAxes
        axesSenal                    matlab.ui.control.UIAxes

        % Panel Grabacion
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

        % Info modelo
        lblModelInfo                 matlab.ui.control.Label

        % Panel Clasificacion
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

        % Resultado
        lblResultado                 matlab.ui.control.Label
        lblConf                      matlab.ui.control.Label

        % Panel Evaluacion
        PanelEval                    matlab.ui.container.Panel
        lblResumen                   matlab.ui.control.Label
        tablaHistorial               matlab.ui.control.Table
        btnMatrizKNN                 matlab.ui.control.Button
        btnMatrizCentroide           matlab.ui.control.Button
        btnGuardarCSV                matlab.ui.control.Button
        btnBorrarHistorial           matlab.ui.control.Button
        btnPipeline                  matlab.ui.control.Button
    end

    % =====================================================================
    properties (Access = private)
        Etapa = 0;  dataset;  genero
        archivo = 'dataset_parc2.mat'
        sobreescribir = 0;  omitir = 0

        modelo;  dtsClasif;  zvec;  idxIni;  idxFin
        etiquetaActual = "";  sujetoActual = ""
        historial
        LOG = 'historial_clasificacion.csv'
    end

    % =====================================================================
    methods (Access = private)   % helpers de instancia

        function cargarModelo(app)
            if ~isfile('modelo_final.mat'), return; end
            try, S = load('modelo_final.mat','modelo'); app.modelo = S.modelo; catch, end
        end

        function procesarYMostrar(app, senal)
            if isempty(app.modelo)
                app.lblResultado.Text = 'Sin modelo — usa el Pipeline para entrenar.'; return;
            end
            cfg = app.modelo.cfg; Fs = cfg.Fs;
            if size(senal,1) < size(senal,2), senal = senal.'; end

            s = FinalGrabar.preprocesarEMG(senal, Fs);
            e = prctile(abs(s(cfg.idxBase,:)), cfg.percentil, 1); e(e<eps)=1;
            s = s ./ e;

            t = (0:size(s,1)-1)/Fs;
            cla(app.axesSenal); hold(app.axesSenal,'on');
            plot(app.axesSenal, t, s(:,1), 'Color',[0 0.7 0.9], 'LineWidth',0.7);
            plot(app.axesSenal, t, s(:,2), 'Color',[0.9 0.4 0],  'LineWidth',0.7);
            legend(app.axesSenal,{'Canal 1','Canal 2'},'TextColor','w','Color','none','Location','northeast');
            hold(app.axesSenal,'off');

            [ii, ff, info] = FinalGrabar.detectarActividad(s, Fs, cfg.det);
            app.zvec=[]; app.idxIni=[]; app.idxFin=[];

            if info.ok
                app.idxIni=ii; app.idxFin=ff;
                fvec = FinalGrabar.extraerFeaturesBurst(s, ii, ff, Fs, cfg.idxBase, cfg.thr);
                app.zvec = (fvec - app.modelo.mu) ./ app.modelo.sg;
                app.lblConf.Text = sprintf('Señal lista  |  %s  |  Duracion: %.0f ms', char(app.etiquetaActual), info.durMs);
                app.lblResultado.Text='--'; app.lblResultado.FontColor=[0.6 0.6 0.6];
                app.btnClasificar.Enable='on';
            else
                app.lblConf.Text = 'Sin actividad detectada — revisa la señal';
                app.lblResultado.Text='Sin actividad'; app.lblResultado.FontColor=[0.8 0.3 0.3];
                app.btnClasificar.Enable='off';
            end
        end

        function refrescarTabla(app)
            if isempty(app.historial) || height(app.historial)==0
                app.tablaHistorial.Data={}; app.lblResumen.Text='Sin clasificaciones registradas'; return;
            end
            r=app.historial; n=min(height(r),6);
            sub=r(end-n+1:end,{'Verdadera','Predicha','Modelo','Distancia','Conf'});
            d=table2cell(sub);
            for k=1:numel(d)
                v=d{k};
                if (isstring(v)||iscategorical(v)) && any(ismissing(v)), d{k}='';
                elseif isstring(v)||ischar(v), d{k}=char(v);
                elseif isnumeric(v), d{k}=double(v);
                else, d{k}='';
                end
            end
            app.tablaHistorial.Data=d;
            con=r(r.Verdadera~="",:);
            if height(con)==0
                app.lblResumen.Text=sprintf('%d clasificaciones (sin etiqueta real)',height(r));
            else
                ac=sum(con.Verdadera==con.Predicha);
                app.lblResumen.Text=sprintf('Aciertos: %d/%d (%.0f%%)  |  Total: %d', ac,height(con),100*ac/height(con),height(r));
            end
        end

        function anotarResultado(app, predicha, modelo_n, dist_n, conf, durMs)
            fila=table(string(datetime('now')),app.etiquetaActual,predicha, ...
                string(modelo_n),string(dist_n),conf,durMs,string(app.sujetoActual), ...
                'VariableNames',{'Fecha','Verdadera','Predicha','Modelo','Distancia','Conf','DurMs','Sujeto'});
            if isempty(app.historial), app.historial=fila;
            else, app.historial=[app.historial;fila]; end
            try, writetable(app.historial,app.LOG); catch, end
            app.refrescarTabla();
        end

        function md = distanciaAMatlab(~,nombre)
            switch lower(string(nombre))
                case 'manhattan', md='cityblock'; case 'euclidiana', md='euclidean';
                case 'coseno',    md='cosine';    otherwise, md=char(nombre);
            end
        end

        function s = distanciaAmigable(~, d)
            switch lower(string(d))
                case 'cityblock', s='Manhattan'; case 'euclidean', s='Euclidiana';
                case 'cosine',    s='Coseno';    otherwise, s=char(d);
            end
        end
    end

    % =====================================================================
    methods (Access = private)   % callbacks

        %% -- Grabacion ---------------------------------------------------
        function ContinuarButtonPushed(app, event)
            switch app.Etapa
                case 0
                    if (ischar(app.archivo)||isstring(app.archivo)) && exist(app.archivo,'file')
                        load(app.archivo,'dts'); app.dataset=dts;
                    else, app.dataset=struct([]); end
                    indicesSujeto=[];
                    for i=1:length(app.dataset)
                        if strcmpi(app.dataset(i).idSujeto,app.IdentificadorEditField.Value)
                            indicesSujeto(end+1)=i; end
                    end
                    if isempty(indicesSujeto)
                        app.LabelTop.Text="Nuevo ID. Presiona Continuar para grabar.";
                        app.genero=app.SexoDropDown.Value;
                    else
                        app.LabelTop.Text="ID ya existe. Presiona Continuar para grabar.";
                        app.genero=app.dataset(indicesSujeto(1)).genero;
                    end
                    app.Etapa=1;
                    app.SexoDropDown.Enable="off"; app.IdentificadorEditField.Enable="off";
                    app.EscogerDatasetButton.Enable="off"; app.FraseEditField.Enable="off";

                case {1,2,3,4,5}
                    app.sobreescribir=0; app.omitir=0;
                    app.RepeticionEditField.Value=app.Etapa;
                    indiceExistente=[];
                    for i=1:length(app.dataset)
                        if strcmpi(app.dataset(i).idSujeto,app.IdentificadorEditField.Value) && app.dataset(i).repeticion==app.Etapa
                            indiceExistente=i; break; end
                    end
                    if ~isempty(indiceExistente)
                        a=uiconfirm(app.UIFigure,'¿Sobreescribir?','Repeticion #'+string(app.Etapa)+' ya existe','Options',{'Si','No'});
                        if strcmp(a,'Si'), app.sobreescribir=1; else, app.omitir=1; end
                    else
                        a=uiconfirm(app.UIFigure,'¿Que deseas hacer?','Repeticion #'+string(app.Etapa),'Options',{'Capturar','Omitir'});
                        if strcmp(a,'Omitir'), app.omitir=1; end
                    end
                    senal=[];
                    if app.omitir==0
                        app.ContinuarButton.Enable="off";
                        sp=serialport(app.efCOM.Value,115200); flush(sp);
                        Fs=1000; hablar=2500; silencio=1000; N=2*silencio+hablar;
                        data=zeros(2,N); time=(0:N-1)/Fs; plot(app.UIAxes,time,data);
                        i=1; cnt=0;
                        app.LabelTop.Text="Silencio..."; app.LabelTop.BackgroundColor="yellow"; app.LabelTop.FontColor="black";
                        while i<N+1
                            if sp.NumBytesAvailable>0
                                v=split(readline(sp));
                                if numel(v)>=2
                                    v1=str2double(v(1)); v2=str2double(v(2));
                                    if ~isnan(v1)&&~isnan(v2)
                                        data(1,i)=v1; data(2,i)=v2; i=i+1; cnt=cnt+1;
                                        if cnt>=250, plot(app.UIAxes,time,data); cnt=0; end
                                        switch i
                                            case silencio, app.LabelTop.Text="Habla!"; app.LabelTop.BackgroundColor="green";
                                            case (silencio+hablar), app.LabelTop.Text="Silencio..."; app.LabelTop.BackgroundColor="yellow";
                                        end
                                    end
                                end
                            end
                        end
                        senal=data; plot(app.UIAxes,time,senal);
                        app.LabelTop.BackgroundColor="black"; app.LabelTop.FontColor="white";
                        app.ContinuarButton.Enable="on"; clear sp;
                        if ~isempty(app.modelo)
                            app.etiquetaActual=FinalGrabar.normalizarEtiqueta(app.FraseEditField.Value);
                            app.sujetoActual=regexprep(string(app.IdentificadorEditField.Value),'\d+$','');
                            app.procesarYMostrar(senal);
                        end
                    end
                    if size(senal,1)~=2&&app.omitir==0, app.LabelTop.Text='Error: 2 canales requeridos.'; return; end
                    if any(isnan(senal),'all')&&app.omitir==0, app.LabelTop.Text='Error: NaN.'; return; end
                    if any(isinf(senal),'all')&&app.omitir==0, app.LabelTop.Text='Error: Inf.'; return; end
                    if app.omitir==0||app.sobreescribir==1
                        registro.idSujeto=app.IdentificadorEditField.Value; registro.genero=app.genero;
                        registro.repeticion=app.Etapa; registro.senal=senal; registro.frase=app.FraseEditField.Value;
                    end
                    if isempty(app.dataset)&&(app.omitir==0), app.dataset=registro; app.LabelTop.Text='Primera repeticion guardada.';
                    elseif isempty(indiceExistente)&&(app.omitir==0), app.dataset(end+1)=registro; app.LabelTop.Text='Repeticion #'+string(app.Etapa)+' guardada.';
                    elseif app.sobreescribir==1, app.dataset(indiceExistente)=registro; app.LabelTop.Text='Repeticion #'+string(app.Etapa)+' sobreescrita.';
                    elseif app.omitir==1, app.LabelTop.Text='Repeticion #'+string(app.Etapa)+' omitida.'; end
                    dts=app.dataset; save(app.archivo,'dts');
                    if app.Etapa==5
                        a=uiconfirm(app.UIFigure,'¿Otro sujeto?','Listo','Options',{'Si','No'});
                        if strcmp(a,'No'), delete(app); return; end
                        app.Etapa=0; app.LabelTop.Text="Ingresa los datos del sujeto.";
                        app.EscogerDatasetButton.Enable="on"; app.SexoDropDown.Enable="on";
                        app.IdentificadorEditField.Enable="on"; app.FraseEditField.Enable="on";
                        app.RepeticionEditField.Value=0;
                    else, app.Etapa=app.Etapa+1; end
            end
        end

        function EscogerDatasetButtonPushed(app,~)
            app.archivo=uigetfile; app.DatasetNombre.Value=string(app.archivo);
        end

        %% -- Clasificacion -----------------------------------------------
        function ddClasificadorValueChanged(app,~)
            esKNN=strcmp(app.ddClasificador.Value,'KNN');
            if esKNN, app.efK.Enable='on'; app.lblK.FontColor=[0.9 0.9 0.9];
            else,     app.efK.Enable='off'; app.lblK.FontColor=[0.45 0.45 0.45]; end
        end

        function btnCargarDatasetPushed(app,~)
            if isempty(app.modelo), uialert(app.UIFigure,'Sin modelo. Usa el Pipeline.','Aviso'); return; end
            if isempty(app.dtsClasif)
                [f,p]=uigetfile('*.mat','Dataset'); if isequal(f,0), return; end
                try, S=load(fullfile(p,f),'dts'); app.dtsClasif=S.dts;
                catch, uialert(app.UIFigure,'Archivo invalido.','Error'); return; end
            end
            n=numel(app.dtsClasif); items=strings(n,1);
            for k=1:n, items(k)=sprintf('%3d | %-14s | %s',k,string(app.dtsClasif(k).idSujeto),string(app.dtsClasif(k).frase)); end
            [ix,ok]=listdlg('PromptString','Selecciona un registro:','SelectionMode','single','ListString',cellstr(items),'ListSize',[310 380],'Name','Dataset');
            if ~ok, return; end
            reg=app.dtsClasif(ix);
            app.etiquetaActual=FinalGrabar.normalizarEtiqueta(reg.frase);
            app.sujetoActual=regexprep(string(reg.idSujeto),'\d+$','');
            app.procesarYMostrar(double(reg.senal));
        end

        function btnClasificarPushed(app,~)
            if isempty(app.zvec), uialert(app.UIFigure,'Primero captura o carga una señal.','Sin señal'); return; end
            clases=app.modelo.clases; dist_ui=app.ddDistancia.Value; dist_ml=app.distanciaAMatlab(dist_ui);
            durMs=0;
            if ~isempty(app.idxIni)&&~isempty(app.idxFin), durMs=1000*(app.idxFin-app.idxIni+1)/app.modelo.cfg.Fs; end
            switch app.ddClasificador.Value
                case 'KNN'
                    K=max(1,round(app.efK.Value));
                    if isfield(app.modelo,'Ztr')&&isfield(app.modelo,'Ytr')
                        mdlT=fitcknn(app.modelo.Ztr,app.modelo.Ytr,'NumNeighbors',K,'Distance',dist_ml);
                        [pred,score]=predict(mdlT,app.zvec);
                    else, [pred,score]=predict(app.modelo.mdl,app.zvec); dist_ui=app.distanciaAmigable(app.modelo.dist); end
                    predicha=string(pred); conf=max(score); modelo_n=sprintf('KNN (K=%d)',K);
                case 'Centroide - Minima Distancia'
                    C=app.modelo.centroides;
                    switch dist_ml
                        case 'euclidean', D=pdist2(app.zvec,C,'euclidean');
                        case 'cityblock', D=pdist2(app.zvec,C,'cityblock');
                        case 'cosine',    D=pdist2(app.zvec,C,'cosine');
                    end
                    [~,idx]=min(D); predicha=string(clases{idx});
                    sumD=sum(D); if sumD<eps, sumD=1; end; conf=1-min(D)/sumD; modelo_n='Centroide';
            end
            app.lblResultado.Text=char(predicha);
            if app.etiquetaActual~=""
                if predicha==app.etiquetaActual, app.lblResultado.FontColor=[0.2 0.85 0.2]; marca='ACIERTO';
                else, app.lblResultado.FontColor=[0.9 0.2 0.2]; marca=sprintf('FALLO (real: %s)',app.etiquetaActual); end
                app.lblConf.Text=sprintf('Confianza: %.0f%%  |  %s  |  Dist: %s',100*conf,marca,dist_ui);
            else
                app.lblResultado.FontColor=[1 1 1];
                app.lblConf.Text=sprintf('Confianza: %.0f%%  |  Dist: %s',100*conf,dist_ui);
            end
            app.anotarResultado(predicha,modelo_n,dist_ui,conf,durMs);
        end

        %% -- Evaluacion --------------------------------------------------
        function btnMatrizKNNPushed(app,~)
            if isempty(app.historial), uialert(app.UIFigure,'Sin historial.','Aviso'); return; end
            r=app.historial(contains(lower(string(app.historial.Modelo)),'knn')&app.historial.Verdadera~="",:);
            if height(r)<2, uialert(app.UIFigure,'Minimo 2 pruebas KNN con etiqueta real.','Aviso'); return; end
            cl=app.modelo.clases;
            figure('Name','Matriz — KNN','Position',[200 200 560 480]);
            confusionchart(categorical(r.Verdadera,cl),categorical(r.Predicha,cl),'RowSummary','row-normalized', ...
                'Title',sprintf('KNN — %.0f%%  (n=%d)',100*mean(r.Verdadera==r.Predicha),height(r)));
        end

        function btnMatrizCentroidePushed(app,~)
            if isempty(app.historial), uialert(app.UIFigure,'Sin historial.','Aviso'); return; end
            r=app.historial(lower(string(app.historial.Modelo))=="centroide"&app.historial.Verdadera~="",:);
            if height(r)<2, uialert(app.UIFigure,'Minimo 2 pruebas de Centroide con etiqueta real.','Aviso'); return; end
            cl=app.modelo.clases;
            figure('Name','Matriz — Centroide','Position',[240 240 560 480]);
            confusionchart(categorical(r.Verdadera,cl),categorical(r.Predicha,cl),'RowSummary','row-normalized', ...
                'Title',sprintf('Centroide — %.0f%%  (n=%d)',100*mean(r.Verdadera==r.Predicha),height(r)));
        end

        function btnGuardarCSVPushed(app,~)
            if isempty(app.historial)||height(app.historial)==0, uialert(app.UIFigure,'Nada que guardar.','Aviso'); return; end
            [f,p]=uiputfile('*.csv','Guardar','resultados_clasificacion.csv'); if isequal(f,0), return; end
            writetable(app.historial,fullfile(p,f));
            uialert(app.UIFigure,'Guardado.','Listo','Icon','success');
        end

        function btnBorrarHistorialPushed(app,~)
            a=uiconfirm(app.UIFigure,'¿Borrar historial?','Confirmar','Options',{'Si','Cancelar'},'DefaultOption','Cancelar','CancelOption','Cancelar');
            if strcmp(a,'Cancelar'), return; end
            app.historial=[]; if isfile(app.LOG), delete(app.LOG); end; app.refrescarTabla();
        end

        %% -- Pipeline ----------------------------------------------------
        function btnPipelinePushed(app,~)
            [f,p]=uigetfile('*.mat','Seleccionar dataset para entrenar');
            if isequal(f,0), return; end
            archivoDataset=fullfile(p,f);
            app.lblConf.Text='Entrenando... puede tardar 1-2 minutos.';
            app.btnPipeline.Enable='off'; drawnow;
            try
                FinalGrabar.p_construirDataset(archivoDataset);
                FinalGrabar.p_entrenarYEvaluar();
                FinalGrabar.p_evaluarLOSO();
                FinalGrabar.p_entrenarModeloFinal();
                app.cargarModelo();
                if ~isempty(app.modelo)
                    app.efK.Value=app.modelo.K;
                    app.lblModelInfo.Text=sprintf('Modelo listo: KNN K=%d  |  %d sujetos  |  norm: %s', ...
                        app.modelo.K, app.modelo.nSujetos, app.modelo.cfg.normaliza);
                    app.lblConf.Text='Modelo entrenado y cargado correctamente.';
                end
            catch ME
                app.lblConf.Text=sprintf('Error durante el entrenamiento: %s', ME.message);
            end
            app.btnPipeline.Enable='on';
        end
    end

    % =====================================================================
    methods (Static, Access = private)

        %% ---- FUNCIONES DE PROCESAMIENTO --------------------------------

        function xf = preprocesarEMG(x, Fs)
            persistent dNotch dBP FsCache
            x=double(x); if size(x,1)<size(x,2), x=x.'; end
            x(~isfinite(x))=0; x=x-mean(x,1);
            if isempty(FsCache)||FsCache~=Fs||isempty(dBP)
                FsCache=Fs; f0s=[60 120 180 240]; f0s=f0s(f0s<0.45*Fs);
                dNotch=cell(1,numel(f0s));
                for k=1:numel(f0s)
                    dNotch{k}=designfilt('bandstopiir','FilterOrder',4, ...
                        'HalfPowerFrequency1',f0s(k)-2,'HalfPowerFrequency2',f0s(k)+2,'SampleRate',Fs);
                end
                dBP=designfilt('bandpassiir','FilterOrder',6, ...
                    'HalfPowerFrequency1',20,'HalfPowerFrequency2',min(400,0.45*Fs),'SampleRate',Fs);
            end
            for k=1:numel(dNotch), x=filtfilt(dNotch{k},x); end
            xf=filtfilt(dBP,x);
        end

        function [idxIni, idxFin, info] = detectarActividad(s, Fs, opts)
            if nargin<3, opts=struct(); end
            def=struct('idxBase',1:900,'idxBusca',900:4000,'kOn',4.0,'kOff',2.0, ...
                       'suavizado',100,'minDur',150,'maxGap',120,'margen',50);
            for fn=fieldnames(def).',  if ~isfield(opts,fn{1}), opts.(fn{1})=def.(fn{1}); end, end
            N=size(s,1); nCh=size(s,2);
            idxBase=opts.idxBase(opts.idxBase<=N); idxBusca=opts.idxBusca(opts.idxBusca<=N);
            win=max(3,round(opts.suavizado*Fs/1000));
            envCh=movmean(abs(s),win,1); z=zeros(N,nCh);
            for c=1:nCh
                mu=mean(envCh(idxBase,c)); sd=std(envCh(idxBase,c)); if sd<eps, sd=1; end
                z(:,c)=(envCh(:,c)-mu)/sd;
            end
            env=mean(z,2); info.env=env; info.thrOn=opts.kOn; info.thrOff=opts.kOff;
            activo=false(N,1); enc=false;
            for n=idxBusca
                if ~enc&&env(n)>opts.kOn, enc=true; elseif enc&&env(n)<opts.kOff, enc=false; end
                activo(n)=enc;
            end
            if ~any(activo), idxIni=[]; idxFin=[]; info.durMs=0; info.ok=false; return; end
            activo=FinalGrabar.cerrarHuecos(activo,round(opts.maxGap*Fs/1000));
            d=diff([0;activo;0]); inis=find(d==1); fins=find(d==-1)-1;
            [dur,kMax]=max(fins-inis+1);
            if dur<round(opts.minDur*Fs/1000), idxIni=[]; idxFin=[]; info.durMs=1000*dur/Fs; info.ok=false; return; end
            mg=round(opts.margen*Fs/1000);
            idxIni=max(1,inis(kMax)-mg); idxFin=min(N,fins(kMax)+mg);
            info.durMs=1000*(idxFin-idxIni+1)/Fs; info.ok=true;
        end

        function a = cerrarHuecos(a, gapMax)
            d=diff([1;a;1]); iH=find(d==-1); fH=find(d==1)-1;
            for k=1:numel(iH), if (fH(k)-iH(k)+1)<=gapMax, a(iH(k):fH(k))=true; end, end
        end

        function [f, nombres] = extraerFeaturesBurst(s, ii, ff, Fs, idxBase, thr)
            if nargin<5||isempty(idxBase), idxBase=1:900; end
            if nargin<6||isempty(thr),     thr=0.05;      end
            idxBase=idxBase(idxBase<=size(s,1));
            burst=s(ii:ff,:); base=s(idxBase,:); L=size(burst,1); nCh=size(burst,2);
            f=[]; nombres={};
            durMs=1000*L/Fs; f=[f,log(durMs)]; nombres=[nombres,{'logDur'}];
            for c=1:nCh
                xb=burst(:,c); xr=base(:,c);
                rr=rms(xb)/max(rms(xr),eps); f=[f,log(rr)]; nombres=[nombres,{sprintf('C%d_logRatioRMS',c)}]; %#ok<AGROW>
                [MNF,MDF]=FinalGrabar.espectrales(xb,Fs);
                f=[f,MNF,MDF]; nombres=[nombres,{sprintf('C%d_MNF',c),sprintf('C%d_MDF',c)}]; %#ok<AGROW>
            end
            b=round(linspace(1,L+1,4));
            for c=1:nCh
                for t=1:3
                    seg=burst(b(t):b(t+1)-1,c); if numel(seg)<4, seg=[seg;zeros(4-numel(seg),1)]; end
                    d=diff(seg);
                    MAV=mean(abs(seg)); WL=log(sum(abs(d))+eps);
                    ZC=sum((seg(1:end-1).*seg(2:end)<0)&(abs(d)>thr))/max(numel(seg),1);
                    MNFt=FinalGrabar.espectrales(seg,Fs);
                    f=[f,MAV,WL,ZC,MNFt]; %#ok<AGROW>
                    nombres=[nombres,{sprintf('C%d_T%d_MAV',c,t),sprintf('C%d_T%d_logWL',c,t), ...
                        sprintf('C%d_T%d_ZCn',c,t),sprintf('C%d_T%d_MNF',c,t)}]; %#ok<AGROW>
                end
            end
            e=mean(burst.^2,2); et=[sum(e(b(1):b(2)-1)),sum(e(b(2):b(3)-1)),sum(e(b(3):b(4)-1))];
            et=et/max(sum(et),eps); f=[f,et]; nombres=[nombres,{'E_T1','E_T2','E_T3'}];
            if nCh==2
                if std(burst(:,1))<eps||std(burst(:,2))<eps, r=0; else, r=corr(burst(:,1),burst(:,2)); end
                if ~isfinite(r), r=0; end
                m1=mean(abs(burst(:,1))); m2=mean(abs(burst(:,2)));
                bal=(m1-m2)/max(m1+m2,eps); f=[f,r,bal]; nombres=[nombres,{'X_corr','X_balance'}];
            end
            env=movmean(mean(abs(burst),2),max(3,round(0.05*Fs)));
            [pico,iPico]=max(env); tPR=iPico/L; crest=pico/max(mean(env),eps);
            f=[f,tPR,crest]; nombres=[nombres,{'Env_tPicoRel','Env_cresta'}];
            f(~isfinite(f))=0;
        end

        function [MNF, MDF] = espectrales(x, Fs)
            N=numel(x); P=abs(fft(x.*hamming(N))).^2; P=P(1:floor(N/2)+1);
            fr=(0:floor(N/2)).'*(Fs/N); sP=sum(P);
            if sP<eps, MNF=0; MDF=0; return; end
            MNF=sum(fr.*P)/sP; acum=cumsum(P); MDF=fr(find(acum>=acum(end)/2,1,'first'));
        end

        function lab = normalizarEtiqueta(s)
            s=lower(strtrim(string(s)));
            if s=="", lab=""; return; end
            if startsWith(s,"agua"), lab="Agua";
            elseif startsWith(s,"cine"), lab="Cine";
            elseif startsWith(s,"pel"), lab="Pelicula";
            else, lab=""; end
        end

        function [yhat, C, clases] = clasifCentroide(Ztr, ytr, Zte, dist)
            clases=categories(removecats(ytr)); nCl=numel(clases);
            C=zeros(nCl,size(Ztr,2));
            for k=1:nCl, C(k,:)=mean(Ztr(ytr==clases{k},:),1); end
            switch lower(string(dist))
                case "euclidiana", m='euclidean'; case "manhattan", m='cityblock';
                case "coseno",     m='cosine';    otherwise, m=char(dist);
            end
            D=pdist2(Zte,C,m); [~,idx]=min(D,[],2);
            yhat=categorical(clases(idx),clases);
        end

        %% ---- PIPELINE --------------------------------------------------

        function p_construirDataset(archivoDataset)
            if nargin<1||isempty(archivoDataset), archivoDataset='dataset_parc2.mat'; end
            cfg.archivo=archivoDataset; cfg.salida='features_emg.mat';
            cfg.Fs=1000; cfg.clases=["Agua","Cine","Pelicula"];
            cfg.idxBase=1:900; cfg.thr=0.05; cfg.percentil=95; cfg.normaliza='reposo';
            cfg.det=struct('idxBase',cfg.idxBase,'idxBusca',900:4000,'kOn',4.0,'kOff',2.0, ...
                           'suavizado',100,'minDur',150,'maxGap',120,'margen',50);
            S=load(cfg.archivo,'dts'); dts=S.dts; n=numel(dts);
            fprintf('\nCargados %d registros.\nPasada 1/2: preprocesando...\n',n);
            sigProc=cell(n,1); sujetos=strings(n,1); frases=strings(n,1);
            for i=1:n
                sigProc{i}=FinalGrabar.preprocesarEMG(dts(i).senal,cfg.Fs);
                sujetos(i)=regexprep(string(dts(i).idSujeto),'\d+$','');
                frases(i)=FinalGrabar.normalizarEtiqueta(dts(i).frase);
                if mod(i,50)==0, fprintf('   %d/%d\n',i,n); end
            end
            malos=(frases=="");
            nCh=size(sigProc{find(~malos,1)},2); escalaReg=ones(n,nCh);
            for i=1:n
                if malos(i), continue; end
                e=prctile(abs(sigProc{i}(cfg.idxBase,:)),cfg.percentil,1); e(e<eps)=1; escalaReg(i,:)=e;
            end
            fprintf('Pasada 2/2: extrayendo caracteristicas...\n');
            iS=find(~malos,1); sS=sigProc{iS}./escalaReg(iS,:);
            [iiS,ffS]=FinalGrabar.detectarActividad(sS,cfg.Fs,cfg.det);
            [fS,nombres]=FinalGrabar.extraerFeaturesBurst(sS,iiS,ffS,cfg.Fs,cfg.idxBase,cfg.thr);
            nFeat=numel(fS); fprintf('Caracteristicas: %d\n',nFeat);
            X=zeros(n,nFeat); Ystr=strings(n,1); SubjWin=strings(n,1); RepID=zeros(n,1); durMs=zeros(n,1);
            fila=0; fallos=[];
            for i=1:n
                if malos(i), continue; end
                s=sigProc{i}./escalaReg(i,:);
                [ii,ff,info]=FinalGrabar.detectarActividad(s,cfg.Fs,cfg.det);
                if ~info.ok, fallos(end+1)=i; continue; end %#ok<AGROW>
                fila=fila+1;
                X(fila,:)=FinalGrabar.extraerFeaturesBurst(s,ii,ff,cfg.Fs,cfg.idxBase,cfg.thr);
                Ystr(fila)=frases(i); SubjWin(fila)=sujetos(i); RepID(fila)=i; durMs(fila)=info.durMs;
                if mod(i,50)==0, fprintf('   %d/%d\n',i,n); end
            end
            X=X(1:fila,:); Ystr=Ystr(1:fila); SubjWin=SubjWin(1:fila); RepID=RepID(1:fila); durMs=durMs(1:fila);
            Y=categorical(Ystr,cellstr(cfg.clases));
            fprintf('\nRepeticiones: %d (descartadas: %d) | Sujetos: %d\n',size(X,1),numel(fallos),numel(unique(SubjWin)));
            summary(Y)
            save(cfg.salida,'X','Y','SubjWin','RepID','nombres','cfg','durMs');
            fprintf('Guardado en %s\n',cfg.salida);
        end

        function p_entrenarYEvaluar()
            load('features_emg.mat','X','Y','SubjWin','RepID','cfg');
            clases=cellstr(cfg.clases);
            rng(42); sujUnicos=unique(SubjWin); nSuj=numel(sujUnicos);
            p=randperm(nSuj); nTr=max(1,round(0.7*nSuj));
            sTr=sujUnicos(p(1:nTr)); sTe=sujUnicos(p(nTr+1:end));
            idxTr=ismember(SubjWin,sTr); idxTe=~idxTr;
            fprintf('\n=== PARTICION  Train: %d sujetos | Test: %d sujetos ===\n',numel(sTr),numel(sTe));
            Xtr=X(idxTr,:); ytr=removecats(Y(idxTr)); Xte=X(idxTe,:); yte=removecats(Y(idxTe));
            mu=mean(Xtr,1); sg=std(Xtr,0,1); sg(sg<eps)=1;
            Ztr=(Xtr-mu)./sg; Zte=(Xte-mu)./sg;
            % Centroide
            fprintf('\n=== CENTROIDE ===\n'); distsCent=["euclidiana","manhattan","coseno"];
            resCent=struct('dist',{},'accRep',{},'yhat',{});
            for k=1:numel(distsCent)
                yhat=FinalGrabar.clasifCentroide(Ztr,ytr,Zte,distsCent(k));
                [pr,tr]=FinalGrabar.votoMayoritario(yhat,yte,RepID(idxTe),clases);
                resCent(k).dist=distsCent(k); resCent(k).accRep=mean(pr==tr); resCent(k).yhat=yhat;
                fprintf('  %-12s  %.1f%%\n',distsCent(k),100*resCent(k).accRep);
            end
            [~,bC]=max([resCent.accRep]);
            % KNN CV
            fprintf('\n=== KNN (CV en train) ===\n');
            Ks=[1 3 5 7 9 11 15 21]; dK={'euclidean','cityblock','cosine'}; nDK={'Euclidiana','Manhattan','Coseno'};
            nFold=min(5,numel(sTr)); folds=FinalGrabar.asignarFolds(SubjWin(idxTr),sTr,nFold);
            accCV=zeros(numel(Ks),numel(dK));
            for a=1:numel(Ks), for b=1:numel(dK)
                acc=zeros(nFold,1);
                for f=1:nFold
                    iV=(folds==f); iF=~iV;
                    if ~any(iV)||numel(categories(removecats(ytr(iF))))<2, acc(f)=NaN; continue; end
                    m2=mean(Ztr(iF,:),1); s2=std(Ztr(iF,:),0,1); s2(s2<eps)=1;
                    mdl=fitcknn((Ztr(iF,:)-m2)./s2,ytr(iF),'NumNeighbors',Ks(a),'Distance',dK{b});
                    acc(f)=mean(predict(mdl,(Ztr(iV,:)-m2)./s2)==ytr(iV));
                end
                accCV(a,b)=mean(acc,'omitnan');
            end, end
            disp(array2table(100*accCV,'RowNames',compose('K=%d',Ks),'VariableNames',nDK));
            [~,lin]=max(accCV(:)); [aB,bB]=ind2sub(size(accCV),lin);
            Kopt=Ks(aB); distOpt=dK{bB};
            fprintf('-> K=%d, %s (CV %.1f%%)\n',Kopt,nDK{bB},100*accCV(aB,bB));
            mdlKNN=fitcknn(Ztr,ytr,'NumNeighbors',Kopt,'Distance',distOpt);
            [prKNN,trKNN]=FinalGrabar.votoMayoritario(predict(mdlKNN,Zte),yte,RepID(idxTe),clases);
            fprintf('\n=== KNN TEST  %.1f%% ===\n',100*mean(prKNN==trKNN));
            try
                [prL,~]=FinalGrabar.votoMayoritario(predict(fitcdiscr(Ztr,ytr,'DiscrimType','pseudolinear'),Zte),yte,RepID(idxTe),clases);
                [prN,~]=FinalGrabar.votoMayoritario(predict(fitcnb(Ztr,ytr),Zte),yte,RepID(idxTe),clases);
                fprintf('LDA: %.1f%%  |  Naive Bayes: %.1f%%\n',100*mean(prL==trKNN),100*mean(prN==trKNN));
            catch, end
            figure('Name','Matrices 70/30','Position',[100 100 1000 420]);
            [prC,trC]=FinalGrabar.votoMayoritario(resCent(bC).yhat,yte,RepID(idxTe),clases);
            subplot(1,2,1); confusionchart(trC,prC,'RowSummary','row-normalized','Title',sprintf('Centroide (%s) %.1f%%',resCent(bC).dist,100*mean(prC==trC)));
            subplot(1,2,2); confusionchart(trKNN,prKNN,'RowSummary','row-normalized','Title',sprintf('KNN K=%d %s %.1f%%',Kopt,nDK{bB},100*mean(prKNN==trKNN)));
            fprintf('\n--- Desempeño por clase KNN ---\n'); FinalGrabar.reportePorClase(trKNN,prKNN,clases);
            fprintf('K optimo: %d | Distancia: %s\n',Kopt,nDK{bB});
        end

        function p_evaluarLOSO()
            load('features_emg.mat','X','Y','SubjWin','RepID','cfg');
            clases=cellstr(cfg.clases); Kopt=15; distOpt='cityblock';
            sujUnicos=unique(SubjWin); nSuj=numel(sujUnicos);
            accKNN=nan(nSuj,1); accCent=nan(nSuj,1);
            todosPred=categorical.empty(0,1); todosTrue=categorical.empty(0,1);
            fprintf('\n=== LOSO (%d sujetos) ===\n',nSuj);
            for k=1:nSuj
                idxTe=(SubjWin==sujUnicos(k)); idxTr=~idxTe;
                ytr=removecats(Y(idxTr)); yte=removecats(Y(idxTe));
                if numel(categories(ytr))<numel(clases), continue; end
                mu=mean(X(idxTr,:),1); sg=std(X(idxTr,:),0,1); sg(sg<eps)=1;
                Ztr=(X(idxTr,:)-mu)./sg; Zte=(X(idxTe,:)-mu)./sg;
                [pr,tr]=FinalGrabar.votoMayoritario(predict(fitcknn(Ztr,ytr,'NumNeighbors',Kopt,'Distance',distOpt),Zte),Y(idxTe),RepID(idxTe),clases);
                accKNN(k)=mean(pr==tr); todosPred=[todosPred;pr]; todosTrue=[todosTrue;tr]; %#ok<AGROW>
                [prC,~]=FinalGrabar.votoMayoritario(FinalGrabar.clasifCentroide(Ztr,ytr,Zte,'euclidiana'),Y(idxTe),RepID(idxTe),clases);
                accCent(k)=mean(prC==tr);
                fprintf('  %-10s  KNN: %5.1f%%   Centroide: %5.1f%%\n',sujUnicos(k),100*accKNN(k),100*accCent(k));
            end
            fprintf('\nKNN: %.1f%% +/- %.1f  |  Centroide: %.1f%% +/- %.1f  |  Azar: %.1f%%\n', ...
                100*mean(accKNN,'omitnan'),100*std(accKNN,'omitnan'), ...
                100*mean(accCent,'omitnan'),100*std(accCent,'omitnan'),100/numel(clases));
            figure('Name','LOSO acumulado','Position',[100 100 560 480]);
            confusionchart(todosTrue,todosPred,'RowSummary','row-normalized','Title',sprintf('KNN LOSO — %.1f%%',100*mean(todosPred==todosTrue)));
        end

        function p_entrenarModeloFinal()
            Kopt=15; distOpt='cityblock';
            load('features_emg.mat','X','Y','SubjWin','nombres','cfg');
            clases=cellstr(cfg.clases);
            fprintf('\n=== MODELO FINAL  %d rep | %d sujetos ===\n',size(X,1),numel(unique(SubjWin)));
            mu=mean(X,1); sg=std(X,0,1); sg(sg<eps)=1; Z=(X-mu)./sg;
            mdl=fitcknn(Z,Y,'NumNeighbors',Kopt,'Distance',distOpt);
            C=zeros(numel(clases),size(Z,2));
            for k=1:numel(clases), C(k,:)=mean(Z(Y==clases{k},:),1); end
            modelo.tipo='knn'; modelo.mdl=mdl; modelo.K=Kopt; modelo.dist=distOpt;
            modelo.mu=mu; modelo.sg=sg; modelo.clases=clases; modelo.cfg=cfg;
            modelo.nombres=nombres; modelo.centroides=C;
            modelo.nSujetos=numel(unique(SubjWin)); modelo.nMuestras=size(X,1);
            modelo.fecha=string(datetime('now')); modelo.Ztr=Z; modelo.Ytr=Y;
            save('modelo_final.mat','modelo');
            fprintf('Guardado. Expectativa cross-subject: ~71%% (+/-19). Azar: 33%%.\n');
        end

        %% ---- HELPERS DEL PIPELINE --------------------------------------

        function folds = asignarFolds(subjVec, sujUnicos, nFold)
            rng(7); perm=randperm(numel(sujUnicos)); fd=zeros(numel(sujUnicos),1);
            fd(perm)=mod(0:numel(sujUnicos)-1,nFold)+1;
            [~,loc]=ismember(subjVec,sujUnicos); folds=fd(loc);
        end

        function [predRep, trueRep] = votoMayoritario(yhat, ytrue, repIDs, clases)
            reps=unique(repIDs); predRep=strings(numel(reps),1); trueRep=strings(numel(reps),1);
            for r=1:numel(reps)
                m=(repIDs==reps(r)); predRep(r)=string(mode(yhat(m))); trueRep(r)=string(ytrue(find(m,1)));
            end
            predRep=categorical(predRep,clases); trueRep=categorical(trueRep,clases);
        end

        function reportePorClase(ytrue, ypred, clases)
            fprintf('  %-10s %9s %9s %8s\n','Clase','Precision','Recall','F1');
            for k=1:numel(clases)
                c=clases{k}; tp=sum(ypred==c&ytrue==c); fp=sum(ypred==c&ytrue~=c); fn=sum(ypred~=c&ytrue==c);
                pr=tp/max(tp+fp,1); rc=tp/max(tp+fn,1); f1=2*pr*rc/max(pr+rc,eps);
                fprintf('  %-10s %8.1f%% %8.1f%% %7.1f%%\n',c,100*pr,100*rc,100*f1);
            end
            fprintf('  GLOBAL: %.1f%%\n\n',100*mean(ypred==ytrue));
        end
    end

    % =====================================================================
    methods (Access = private)

        function createComponents(app)
            gris=[0.149 0.149 0.149]; negro=[0.10 0.10 0.10];
            app.UIFigure=uifigure('Visible','off');
            app.UIFigure.Position=[100 80 1150 760];
            app.UIFigure.Name='Grabacion y Clasificacion EMG';
            app.UIFigure.Color=negro;

            % -- Graficas izquierda --
            app.UIAxes=uiaxes(app.UIFigure);
            title(app.UIAxes,'1. Señal Grabada en Tiempo Real');
            xlabel(app.UIAxes,'Tiempo (s)'); ylabel(app.UIAxes,'Voltaje (V)');
            app.UIAxes.XLimitMethod='tight'; app.UIAxes.XGrid='on'; app.UIAxes.YGrid='on';
            app.UIAxes.Position=[15 400 560 340];

            app.axesSenal=uiaxes(app.UIFigure);
            title(app.axesSenal,'2. Señal Procesada (filtrada y escalada)');
            xlabel(app.axesSenal,'Tiempo (s)'); ylabel(app.axesSenal,'Amplitud');
            app.axesSenal.Position=[15 35 560 340];
            app.axesSenal.Color=[0 0 0]; app.axesSenal.XColor=[0.9 0.9 0.9]; app.axesSenal.YColor=[0.9 0.9 0.9];
            app.axesSenal.Title.Color=[1 1 1]; app.axesSenal.XGrid='on'; app.axesSenal.YGrid='on';
            app.axesSenal.GridColor=[0.4 0.4 0.4];

            % -- Panel Grabacion --
            app.PanelGrab=uipanel(app.UIFigure);
            app.PanelGrab.Title='Grabacion de Dataset'; app.PanelGrab.TitlePosition='centertop';
            app.PanelGrab.FontWeight='bold'; app.PanelGrab.FontSize=13;
            app.PanelGrab.ForegroundColor=[0.9 0.9 0.9]; app.PanelGrab.BackgroundColor=gris;
            app.PanelGrab.Position=[590 530 545 215];

            app.LabelTop=uilabel(app.PanelGrab); app.LabelTop.BackgroundColor=[0 0 0];
            app.LabelTop.FontColor=[1 1 1]; app.LabelTop.HorizontalAlignment='center';
            app.LabelTop.WordWrap='on'; app.LabelTop.FontSize=12;
            app.LabelTop.Position=[10 163 380 30]; app.LabelTop.Text='Ingresa los datos del sujeto.';

            app.ContinuarButton=uibutton(app.PanelGrab,'push');
            app.ContinuarButton.ButtonPushedFcn=createCallbackFcn(app,@ContinuarButtonPushed,true);
            app.ContinuarButton.Position=[395 163 140 30]; app.ContinuarButton.Text='Continuar';
            app.ContinuarButton.FontSize=13; app.ContinuarButton.FontWeight='bold';

            app.IdentificadorEditFieldLabel=uilabel(app.PanelGrab); app.IdentificadorEditFieldLabel.Text='ID';
            app.IdentificadorEditFieldLabel.Position=[10 128 20 22];
            app.IdentificadorEditField=uieditfield(app.PanelGrab,'text'); app.IdentificadorEditField.Position=[34 128 105 22];

            app.SexoDropDownLabel=uilabel(app.PanelGrab); app.SexoDropDownLabel.Text='Sexo';
            app.SexoDropDownLabel.HorizontalAlignment='right'; app.SexoDropDownLabel.Position=[148 128 35 22];
            app.SexoDropDown=uidropdown(app.PanelGrab); app.SexoDropDown.Items={'Masculino','Femenino'};
            app.SexoDropDown.Value='Masculino'; app.SexoDropDown.Position=[187 128 105 22];

            app.RepeticionEditFieldLabel=uilabel(app.PanelGrab); app.RepeticionEditFieldLabel.Text='Repeticion';
            app.RepeticionEditFieldLabel.HorizontalAlignment='right'; app.RepeticionEditFieldLabel.Enable='off';
            app.RepeticionEditFieldLabel.Position=[300 128 72 22];
            app.RepeticionEditField=uieditfield(app.PanelGrab,'numeric'); app.RepeticionEditField.Enable='off';
            app.RepeticionEditField.Position=[376 128 60 22];

            app.DatasetEditFieldLabel=uilabel(app.PanelGrab); app.DatasetEditFieldLabel.Text='Dataset';
            app.DatasetEditFieldLabel.Enable='off'; app.DatasetEditFieldLabel.Position=[10 96 48 22];
            app.DatasetNombre=uieditfield(app.PanelGrab,'text'); app.DatasetNombre.Enable='off';
            app.DatasetNombre.Position=[62 96 130 22];

            app.EscogerDatasetButton=uibutton(app.PanelGrab,'push');
            app.EscogerDatasetButton.ButtonPushedFcn=createCallbackFcn(app,@EscogerDatasetButtonPushed,true);
            app.EscogerDatasetButton.Position=[198 94 200 25]; app.EscogerDatasetButton.Text='Escoger Dataset';

            app.lblCOM=uilabel(app.PanelGrab); app.lblCOM.Text='COM:';
            app.lblCOM.FontColor=[0.9 0.9 0.9]; app.lblCOM.Position=[404 96 32 22];
            app.efCOM=uieditfield(app.PanelGrab,'text'); app.efCOM.Value='COM4';
            app.efCOM.Position=[439 94 96 25];

            app.FraseEditFieldLabel=uilabel(app.PanelGrab); app.FraseEditFieldLabel.Text='Frase';
            app.FraseEditFieldLabel.Position=[10 62 38 22];
            app.FraseEditField=uieditfield(app.PanelGrab,'text'); app.FraseEditField.Position=[52 62 483 22];

            % -- Label info modelo --
            app.lblModelInfo=uilabel(app.UIFigure); app.lblModelInfo.Position=[590 513 545 15];
            app.lblModelInfo.HorizontalAlignment='center'; app.lblModelInfo.FontSize=10;
            app.lblModelInfo.FontColor=[0.55 0.55 0.55]; app.lblModelInfo.Text='Cargando modelo...';

            % -- Panel Clasificacion --
            app.PanelClas=uipanel(app.UIFigure); app.PanelClas.Title='Clasificacion';
            app.PanelClas.TitlePosition='centertop'; app.PanelClas.FontWeight='bold'; app.PanelClas.FontSize=13;
            app.PanelClas.ForegroundColor=[0.9 0.9 0.9]; app.PanelClas.BackgroundColor=gris;
            app.PanelClas.Position=[590 345 545 163];

            app.lblModeloClas=uilabel(app.PanelClas); app.lblModeloClas.Text='Modelo:';
            app.lblModeloClas.FontColor=[0.9 0.9 0.9]; app.lblModeloClas.Position=[10 115 55 22];
            app.ddClasificador=uidropdown(app.PanelClas);
            app.ddClasificador.Items={'KNN','Centroide - Minima Distancia'};
            app.ddClasificador.Value='KNN'; app.ddClasificador.Position=[68 112 170 25];
            app.ddClasificador.ValueChangedFcn=createCallbackFcn(app,@ddClasificadorValueChanged,true);

            app.lblK=uilabel(app.PanelClas); app.lblK.Text='K:';
            app.lblK.FontColor=[0.9 0.9 0.9]; app.lblK.HorizontalAlignment='right';
            app.lblK.Position=[246 115 20 22];
            app.efK=uieditfield(app.PanelClas,'numeric'); app.efK.Value=15;
            app.efK.Limits=[1 Inf]; app.efK.RoundFractionalValues='on';
            app.efK.Position=[269 112 48 25];

            app.lblDistanciaClas=uilabel(app.PanelClas); app.lblDistanciaClas.Text='Distancia:';
            app.lblDistanciaClas.FontColor=[0.9 0.9 0.9]; app.lblDistanciaClas.HorizontalAlignment='right';
            app.lblDistanciaClas.Position=[322 115 68 22];
            app.ddDistancia=uidropdown(app.PanelClas);
            app.ddDistancia.Items={'Euclidiana','Manhattan','Coseno'}; app.ddDistancia.Value='Manhattan';
            app.ddDistancia.Position=[394 112 138 25];

            app.lblInfoClas=uilabel(app.PanelClas);
            app.lblInfoClas.Text='La distancia aplica a ambos clasificadores. K solo aplica al KNN.';
            app.lblInfoClas.FontColor=[0.55 0.55 0.55]; app.lblInfoClas.FontSize=10;
            app.lblInfoClas.Position=[10 90 525 16];

            app.btnCargarDataset=uibutton(app.PanelClas,'push');
            app.btnCargarDataset.ButtonPushedFcn=createCallbackFcn(app,@btnCargarDatasetPushed,true);
            app.btnCargarDataset.Position=[10 52 253 30]; app.btnCargarDataset.Text='Cargar del Dataset';
            app.btnCargarDataset.FontSize=12; app.btnCargarDataset.BackgroundColor=[0.25 0.25 0.25];
            app.btnCargarDataset.FontColor=[1 1 1];

            app.btnClasificar=uibutton(app.PanelClas,'push');
            app.btnClasificar.ButtonPushedFcn=createCallbackFcn(app,@btnClasificarPushed,true);
            app.btnClasificar.Position=[272 49 263 34]; app.btnClasificar.Text='Clasificar';
            app.btnClasificar.FontSize=15; app.btnClasificar.FontWeight='bold';
            app.btnClasificar.BackgroundColor=[0.2 0.35 0.6]; app.btnClasificar.FontColor=[1 1 1];
            app.btnClasificar.Enable='off';

            % -- Resultado --
            app.lblResultado=uilabel(app.UIFigure); app.lblResultado.Position=[590 305 545 38];
            app.lblResultado.HorizontalAlignment='center'; app.lblResultado.FontSize=32;
            app.lblResultado.FontWeight='bold'; app.lblResultado.FontColor=[0.6 0.6 0.6];
            app.lblResultado.BackgroundColor=[0 0 0]; app.lblResultado.Text='--';

            app.lblConf=uilabel(app.UIFigure); app.lblConf.Position=[590 288 545 16];
            app.lblConf.HorizontalAlignment='center'; app.lblConf.FontSize=11;
            app.lblConf.FontColor=[0.8 0.8 0.8]; app.lblConf.Text='';

            % -- Panel Evaluacion (con Pipeline integrado) --
            app.PanelEval=uipanel(app.UIFigure); app.PanelEval.Title='Evaluacion de Desempeño';
            app.PanelEval.TitlePosition='centertop'; app.PanelEval.FontWeight='bold'; app.PanelEval.FontSize=13;
            app.PanelEval.ForegroundColor=[0.9 0.9 0.9]; app.PanelEval.BackgroundColor=gris;
            app.PanelEval.Position=[590 15 545 268];

            app.lblResumen=uilabel(app.PanelEval); app.lblResumen.Position=[10 240 525 18];
            app.lblResumen.HorizontalAlignment='center'; app.lblResumen.FontSize=12;
            app.lblResumen.FontWeight='bold'; app.lblResumen.FontColor=[1 1 1];
            app.lblResumen.Text='Sin clasificaciones registradas';

            app.tablaHistorial=uitable(app.PanelEval); app.tablaHistorial.Position=[10 133 525 103];
            app.tablaHistorial.ColumnName={'Real','Predicha','Modelo','Distancia','Conf'};
            app.tablaHistorial.ColumnWidth={75,80,120,88,55};

            app.btnMatrizKNN=uibutton(app.PanelEval,'push');
            app.btnMatrizKNN.ButtonPushedFcn=createCallbackFcn(app,@btnMatrizKNNPushed,true);
            app.btnMatrizKNN.Position=[10 97 255 30]; app.btnMatrizKNN.Text='Matriz de Confusion KNN';
            app.btnMatrizKNN.BackgroundColor=[0.18 0.23 0.42]; app.btnMatrizKNN.FontColor=[1 1 1];

            app.btnMatrizCentroide=uibutton(app.PanelEval,'push');
            app.btnMatrizCentroide.ButtonPushedFcn=createCallbackFcn(app,@btnMatrizCentroidePushed,true);
            app.btnMatrizCentroide.Position=[272 97 263 30]; app.btnMatrizCentroide.Text='Matriz Centroide';
            app.btnMatrizCentroide.BackgroundColor=[0.18 0.23 0.42]; app.btnMatrizCentroide.FontColor=[1 1 1];

            app.btnGuardarCSV=uibutton(app.PanelEval,'push');
            app.btnGuardarCSV.ButtonPushedFcn=createCallbackFcn(app,@btnGuardarCSVPushed,true);
            app.btnGuardarCSV.Position=[10 60 255 30]; app.btnGuardarCSV.Text='Guardar Historial CSV';
            app.btnGuardarCSV.BackgroundColor=[0.25 0.25 0.25]; app.btnGuardarCSV.FontColor=[1 1 1];

            app.btnBorrarHistorial=uibutton(app.PanelEval,'push');
            app.btnBorrarHistorial.ButtonPushedFcn=createCallbackFcn(app,@btnBorrarHistorialPushed,true);
            app.btnBorrarHistorial.Position=[272 60 263 30]; app.btnBorrarHistorial.Text='Borrar Historial';
            app.btnBorrarHistorial.BackgroundColor=[0.42 0.12 0.12]; app.btnBorrarHistorial.FontColor=[1 1 1];

            app.btnPipeline=uibutton(app.PanelEval,'push');
            app.btnPipeline.ButtonPushedFcn=createCallbackFcn(app,@btnPipelinePushed,true);
            app.btnPipeline.Position=[10 10 525 42]; app.btnPipeline.Text='⚙  Entrenar Modelo';
            app.btnPipeline.FontSize=13; app.btnPipeline.FontWeight='bold';
            app.btnPipeline.BackgroundColor=[0.15 0.28 0.15]; app.btnPipeline.FontColor=[0.6 1 0.6];

            app.UIFigure.Visible='on';
        end
    end

    % =====================================================================
    methods (Access = public)
        function app = FinalGrabar
            createComponents(app)
            registerApp(app,app.UIFigure)
            app.cargarModelo();
            if ~isempty(app.modelo)
                app.efK.Value=app.modelo.K;
                app.lblModelInfo.Text=sprintf('Modelo: KNN K=%d  |  %d sujetos  |  norm: %s', ...
                    app.modelo.K, app.modelo.nSujetos, app.modelo.cfg.normaliza);
            else
                app.lblModelInfo.Text='Sin modelo — usa el boton Pipeline de Entrenamiento para crear uno';
            end
            if isfile(app.LOG)
                try, app.historial=readtable(app.LOG,'TextType','string'); app.refrescarTabla(); catch, end
            end
            if nargout==0, clear app; end
        end

        function delete(app), delete(app.UIFigure); end
    end
end
