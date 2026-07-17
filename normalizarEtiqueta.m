function lab = normalizarEtiqueta(s)
% NORMALIZARETIQUETA  Convierte el texto libre del campo 'frase' en una de
% las tres clases canonicas: "Agua", "Cine", "Pelicula".
%
% Es tolerante a mayusculas, espacios y tildes ("Pelicula", "película",
% "PELICULA" -> todos caen en "Pelicula").
%
% Devuelve "" (string vacio) si la etiqueta no se reconoce.

    s = lower(strtrim(string(s)));

    if s == ""
        lab = "";
        return;
    end

    if startsWith(s, "agua")
        lab = "Agua";
    elseif startsWith(s, "cine")
        lab = "Cine";
    elseif startsWith(s, "pel")          % pelicula / película
        lab = "Pelicula";
    else
        lab = "";
    end
end
