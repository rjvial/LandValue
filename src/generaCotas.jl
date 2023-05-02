function generaCotas(template, minPisos, maxPisos, V_areaEdif, sepNaves, maxDiagonal, anchoMin, anchoMax)

    max_ancho_bbo = 6 #anchoMax
    min_pisos_bbo = min(minPisos, maxPisos - 1) 
    if template == 0
        min_pisos = min(minPisos, maxPisos - 1)
        max_pisos = maxPisos
        min_theta = -pi
        max_theta = pi
        xmin = minimum(V_areaEdif[:, 1])
        xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2])
        ymax = maximum(V_areaEdif[:, 2])
        min_largo = sepNaves
        max_largo = maxDiagonal
        min_ancho = anchoMin
        max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_ancho, min_largo]
        ub = [max_pisos, max_theta, xmax, ymax, max_ancho, max_largo]
        lb_bbo = [min_pisos_bbo, min_theta, xmin, ymin, min_ancho, min_largo]
        ub_bbo = [max_pisos, max_theta, xmax, ymax, max_ancho_bbo, max_largo]

    elseif template == 1
        min_pisos = min(minPisos, maxPisos - 1)
        max_pisos = maxPisos
        min_theta = -pi
        max_theta = pi
        xmin = minimum(V_areaEdif[:, 1])
        xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2])
        ymax = maximum(V_areaEdif[:, 2])
        min_alfa = 0
        max_alfa = pi / 2
        min_largo1 = sepNaves
        max_largo1 = maxDiagonal
        min_largo2 = sepNaves
        max_largo2 = maxDiagonal
        min_ancho = anchoMin
        max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_alfa, min_largo1, min_largo2, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_alfa, max_largo1, max_largo2, max_ancho]
        lb_bbo = [min_pisos_bbo, min_theta, xmin, ymin, min_alfa, min_largo1, min_largo2, min_ancho]
        ub_bbo = [max_pisos, max_theta, xmax, ymax, max_alfa, max_largo1, max_largo2, max_ancho_bbo]

    elseif template == 2
        min_pisos = min(minPisos, maxPisos - 1)
        max_pisos = maxPisos
        min_theta = -pi
        max_theta = pi
        xmin = minimum(V_areaEdif[:, 1])
        xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2])
        ymax = maximum(V_areaEdif[:, 2])
        min_phi1 = 0
        max_phi1 = pi / 2
        min_phi2 = -pi
        max_phi2 = 0
        min_largo0 = min(maxDiagonal - 0.01, 3 * sepNaves)
        max_largo0 = maxDiagonal
        min_largo1 = sepNaves
        max_largo1 = maxDiagonal
        min_largo2 = sepNaves
        max_largo2 = maxDiagonal
        min_ancho = anchoMin
        max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_phi1, min_phi2, min_largo0, min_largo1, min_largo2, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_phi1, max_phi2, max_largo0, max_largo1, max_largo2, max_ancho]
        lb_bbo = [min_pisos_bbo, min_theta, xmin, ymin, min_phi1, min_phi2, min_largo0, min_largo1, min_largo2, min_ancho]
        ub_bbo = [max_pisos, max_theta, xmax, ymax, max_phi1, max_phi2, max_largo0, max_largo1, max_largo2, max_ancho_bbo]

    elseif template == 3
        min_pisos = min(minPisos, maxPisos - 1)
        max_pisos = maxPisos
        min_theta = -pi
        max_theta = pi
        xmin = minimum(V_areaEdif[:, 1])
        xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2])
        ymax = maximum(V_areaEdif[:, 2])
        min_unidades = 0.5001
        max_unidades = 5.4999
        min_largo = sepNaves
        max_largo = maxDiagonal
        min_var = -50
        max_var = 50
        min_sep = sepNaves
        max_sep = 100
        min_ancho = anchoMin
        max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_unidades, min_largo, min_var, min_sep, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_unidades, max_largo, max_var, max_sep, max_ancho]
        lb_bbo = [min_pisos_bbo, min_theta, xmin, ymin, min_unidades, min_largo, min_var, min_sep, min_ancho]
        ub_bbo = [max_pisos, max_theta, xmax, ymax, max_unidades, max_largo, max_var, max_sep, max_ancho_bbo]

    elseif template == 4
        min_pisos = min(minPisos, maxPisos - 1)
        max_pisos = maxPisos
        min_theta = -pi
        max_theta = pi
        xmin = minimum(V_areaEdif[:, 1])
        xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2])
        ymax = maximum(V_areaEdif[:, 2])
        min_alfa = 0
        max_alfa = pi / 2
        min_largo1 = sepNaves
        max_largo1 = maxDiagonal
        min_largo2 = sepNaves
        max_largo2 = maxDiagonal
        min_ancho = anchoMin
        max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_alfa, min_largo1, min_largo2, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_alfa, max_largo1, max_largo2, max_ancho]
        lb_bbo = [min_pisos_bbo, min_theta, xmin, ymin, min_alfa, min_largo1, min_largo2, min_ancho]
        ub_bbo = [max_pisos, max_theta, xmax, ymax, max_alfa, max_largo1, max_largo2, max_ancho_bbo]

    elseif template == 5
        min_pisos = min(minPisos, maxPisos - 1)
        max_pisos = dcn.maxPisos
        min_theta = -pi
        max_theta = pi
        xmin = minimum(V_areaEdif[:, 1])
        xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2])
        ymax = maximum(V_areaEdif[:, 2])
        largos, angulosExt, angulosInt, largosDiag = polyShape.extraeInfoPoly(ps_areaEdif)
        maxDiagonal = maximum(largosDiag)
        min_largo = sepNaves
        max_largo = maxDiagonal
        min_largo1_ = sepNaves
        max_largo1_ = maxDiagonal
        min_largo1 = sepNaves
        max_largo1 = maxDiagonal
        min_largo2_ = sepNaves
        max_largo2_ = maxDiagonal
        min_largo2 = sepNaves
        max_largo2 = maxDiagonal
        min_ancho = anchoMin
        max_ancho = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_largo, min_largo1_, min_largo1, min_largo2_, min_largo2, min_ancho]
        ub = [max_pisos, max_theta, xmax, ymax, max_largo, max_largo1_, max_largo1, max_largo2_, max_largo2, max_ancho]
        lb_bbo = [min_pisos_bbo, min_theta, xmin, ymin, min_largo, min_largo1_, min_largo1, min_largo2_, min_largo2, min_ancho]
        ub_bbo = [max_pisos, max_theta, xmax, ymax, max_largo, max_largo1_, max_largo1, max_largo2_, max_largo2, max_ancho_bbo]

    elseif template == 6
        min_pisos = min(minPisos, maxPisos - 1)
        max_pisos = maxPisos
        min_theta = -pi
        max_theta = pi
        xmin = minimum(V_areaEdif[:, 1])
        xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2])
        ymax = maximum(V_areaEdif[:, 2])
        min_phi1 = 0
        max_phi1 = pi / 2
        min_phi2 = -pi
        max_phi2 = 0
        min_largo0 = min(maxDiagonal - 0.01, 3 * sepNaves)
        max_largo0 = maxDiagonal
        min_largo1 = sepNaves
        max_largo1 = maxDiagonal
        min_largo2 = sepNaves
        max_largo2 = maxDiagonal
        min_ancho0 = anchoMin
        max_ancho0 = anchoMax
        min_ancho1 = anchoMin
        max_ancho1 = anchoMax
        min_ancho2 = anchoMin
        max_ancho2 = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_phi1, min_phi2, min_largo0, min_largo1, min_largo2, min_ancho0, min_ancho1, min_ancho2]
        ub = [max_pisos, max_theta, xmax, ymax, max_phi1, max_phi2, max_largo0, max_largo1, max_largo2, max_ancho0, max_ancho1, max_ancho2]
        lb_bbo = [min_pisos_bbo, min_theta, xmin, ymin, min_phi1, min_phi2, min_largo0, min_largo1, min_largo2, min_ancho0, min_ancho1, min_ancho2]
        ub_bbo = [max_pisos, max_theta, xmax, ymax, max_phi1, max_phi2, max_largo0, max_largo1, max_largo2, max_ancho_bbo, max_ancho_bbo, max_ancho_bbo]

    elseif template == 7
        min_pisos = min(minPisos, maxPisos - 1)
        max_pisos = maxPisos
        min_theta = -pi
        max_theta = pi
        xmin = minimum(V_areaEdif[:, 1])
        xmax = maximum(V_areaEdif[:, 1])
        ymin = minimum(V_areaEdif[:, 2])
        ymax = maximum(V_areaEdif[:, 2])
        min_phi1 = 0
        max_phi1 = pi / 2
        min_phi2 = -pi
        max_phi2 = 0
        min_largo0 = min(maxDiagonal - 0.01, 3 * sepNaves)
        max_largo0 = maxDiagonal
        min_largo1 = sepNaves
        max_largo1 = maxDiagonal
        min_largo2 = sepNaves
        max_largo2 = maxDiagonal
        min_ancho0 = anchoMin
        max_ancho0 = anchoMax
        min_ancho1 = anchoMin
        max_ancho1 = anchoMax
        min_ancho2 = anchoMin
        max_ancho2 = anchoMax
        lb = [min_pisos, min_theta, xmin, ymin, min_phi1, min_phi2, min_largo0, min_largo1, min_largo2, min_ancho0, min_ancho1, min_ancho2]
        ub = [max_pisos, max_theta, xmax, ymax, max_phi1, max_phi2, max_largo0, max_largo1, max_largo2, max_ancho0, max_ancho1, max_ancho2]
        lb_bbo = [min_pisos_bbo, min_theta, xmin, ymin, min_phi1, min_phi2, min_largo0, min_largo1, min_largo2, min_ancho0, min_ancho1, min_ancho2]
        ub_bbo = [max_pisos, max_theta, xmax, ymax, max_phi1, max_phi2, max_largo0, max_largo1, max_largo2, max_ancho_bbo, max_ancho_bbo, max_ancho_bbo]

    end

    return lb, ub, lb_bbo, ub_bbo
end