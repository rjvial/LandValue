function optimal_box_volume_sombra_malo(
    vec_psVolRasante, vec_altVolRasante, alt_piso, ps_areaEdif, ps_calles, ps_publico, ps_bruto,
    areaSombra_p, areaSombra_o, areaSombra_s, max_ocupacion_suelo, centroidSombra_p, centroidSombra_o, centroidSombra_s,
    display::Bool = true)

    ps_areaEdif_ = deepcopy(ps_areaEdif)

    A_areaEdif, b_areaEdif = polyShape.poly2Constraints(ps_areaEdif_)
    flag_p = A_areaEdif * centroidSombra_p.Vertices' .>= b_areaEdif
    flag_o = A_areaEdif * centroidSombra_o.Vertices' .>= b_areaEdif
    flag_s = A_areaEdif * centroidSombra_s.Vertices' .>= b_areaEdif
    
    vec_lados_areaEdif = collect(1:length(b_areaEdif))
    vec_lados_areaEdif_p = vec_lados_areaEdif[flag_p]
    vec_lados_areaEdif_o = vec_lados_areaEdif[flag_o]
    vec_lados_areaEdif_s = vec_lados_areaEdif[flag_s]

    ps_opt = PolyShape([], 1)
    np_opt = 0
    rasante_sombra = 5.0
    dist_p = 0.0
    dist_o = 0.0
    dist_s = 0.0

    iter = 0
    max_iter = 20

    delta_sombra_porc_p = -1.0
    delta_sombra_porc_o = -1.0
    delta_sombra_porc_s = -1.0

    while iter < max_iter && (delta_sombra_porc_p < 0 || delta_sombra_porc_o < 0 || delta_sombra_porc_s < 0)
        iter += 1
        if display
            println("####################")
            println("# Iteracion N° $iter")
            println("####################")
        end

        ps_opt_iter, _, np_opt_iter, _ = optimal_box_volume(vec_psVolRasante, vec_altVolRasante, [5], alt_piso, max_ocupacion_suelo, display)
        if display
            println("rasante_sombra: ", rasante_sombra, "\n")
        end

        ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s = generaSombraEdificio(ps_opt_iter, np_opt_iter * alt_piso, ps_publico, ps_calles)
        area_sombra_Edif_p = polyShape.polyArea(ps_sombraEdif_p)
        area_sombra_Edif_o = polyShape.polyArea(ps_sombraEdif_o)
        area_sombra_Edif_s = polyShape.polyArea(ps_sombraEdif_s)

        delta_sombra_porc_p = area_sombra_Edif_p > 0 ? areaSombra_p / area_sombra_Edif_p - 1 : 1
        delta_sombra_porc_o = area_sombra_Edif_o > 0 ? areaSombra_o / area_sombra_Edif_o - 1 : 1
        delta_sombra_porc_s = area_sombra_Edif_s > 0 ? areaSombra_s / area_sombra_Edif_s - 1 : 1

        if delta_sombra_porc_p < delta_sombra_porc_o && delta_sombra_porc_p < delta_sombra_porc_s && delta_sombra_porc_p < 0
            dist_p -= 0.1
            ps_areaEdif_ = polyShape.partialPolyOffset(ps_areaEdif_, vec_lados_areaEdif_p, dist_p)
        elseif delta_sombra_porc_o < delta_sombra_porc_p && delta_sombra_porc_o < delta_sombra_porc_s && delta_sombra_porc_o < 0
            dist_o -= 0.1
            ps_areaEdif_ = polyShape.partialPolyOffset(ps_areaEdif_, vec_lados_areaEdif_o, dist_o)
        elseif delta_sombra_porc_s < delta_sombra_porc_p && delta_sombra_porc_s < delta_sombra_porc_o && delta_sombra_porc_s < 0
            dist_s -= 0.1
            ps_areaEdif_ = polyShape.partialPolyOffset(ps_areaEdif_, vec_lados_areaEdif_s, dist_s)
        end

        if minimum([delta_sombra_porc_p, delta_sombra_porc_o, delta_sombra_porc_s]) < 0
            vec_altVolRasante = collect(0:0.1:50) .* rasante_sombra
            vec_altVolRasante = vec_altVolRasante[vec_altVolRasante .< np_opt_iter * alt_piso]
            push!(vec_altVolRasante, np_opt_iter * alt_piso)
            vec_psVolRasante = [polyShape.polyOffset(ps_bruto, -i / rasante_sombra) for i in vec_altVolRasante]
            vec_psVolRasante = [polyShape.polyIntersect(vec_psVolRasante[i], ps_areaEdif_) for i in eachindex(vec_psVolRasante)]
        end

        ps_opt = ps_opt_iter
        np_opt = np_opt_iter

        if display
            println("delta_sombra_porc_p: ", delta_sombra_porc_p,
                    " delta_sombra_porc_o: ", delta_sombra_porc_o,
                    " delta_sombra_porc_s: ", delta_sombra_porc_s)
        end
    end

    return ps_opt, np_opt
end
