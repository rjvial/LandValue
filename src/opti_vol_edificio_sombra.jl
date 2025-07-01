function opti_vol_edificio_sombra(vec_psVolRasante, vec_altVolRasante, vec_pisos, alturaPiso, ps_areaEdif, ps_calles, ps_publico, ps_bruto,
        areaSombra_p, areaSombra_o, areaSombra_s, max_ocupacion_suelo, maxConstruccionSNT, K, centroidSombra_p, centroidSombra_o, centroidSombra_s;
        ancho_crujia_edificio = 0
    )

    # Prepare rasante constraints
    ps_areaEdif_ = deepcopy(ps_areaEdif)
    A0, b0 = polyShape.poly2Constraints(ps_areaEdif_)

    # Identify edges for shadow adjustments
    flags = A0 * centroidSombra_p.Vertices' .>= b0
    vec_edges = collect(1:length(b0))
    edges_p = vec_edges[A0 * centroidSombra_p.Vertices' .>= b0]
    edges_o = vec_edges[A0 * centroidSombra_o.Vertices' .>= b0]
    edges_s = vec_edges[A0 * centroidSombra_s.Vertices' .>= b0]

    # Iterative shadow loop params
    ratio = 5.0
    dist_p=0.0; dist_o=0.0; dist_s=0.0
    iter=0; max_iter=50
    delta_p=-1.0; delta_o=-1.0; delta_s=-1.0

    # Storage for best known
    best_ps = [PolyShape([],1) for i in 1:K]
    best_np = zeros(Int, K)

    while iter < max_iter && min(delta_p, delta_o, delta_s) < 0
        iter += 1

        # Optimize volumes for K stacks
        ps_candidates, np_cand = opti_vol_edificio(vec_psVolRasante, vec_altVolRasante,
            vec_pisos, alturaPiso, max_ocupacion_suelo, maxConstruccionSNT, K; ancho_crujia_edificio = ancho_crujia_edificio, flag_reverse = true
        )

        # Compute shadows cumulatively
        ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s = generaSombraEdificio(
            ps_candidates,
            cumsum(np_cand).*alturaPiso,
            ps_publico,
            ps_calles
        )
    

        # Sum actual shadow areas
        area_act_p = polyShape.polyArea(ps_sombraEdif_p)
        area_act_o = polyShape.polyArea(ps_sombraEdif_o)
        area_act_s = polyShape.polyArea(ps_sombraEdif_s)

        # Compute ratios (positive=ok)
        delta_p = areaSombra_p>0 ? areaSombra_p/area_act_p -1 : 1
        delta_o = areaSombra_o>0 ? areaSombra_o/area_act_o -1 : 1
        delta_s = areaSombra_s>0 ? areaSombra_s/area_act_s -1 : 1

        delta_min = minimum((delta_p, delta_o, delta_s))

        # Adjust buildable footprint on worst violation
        if delta_p == delta_min && delta_p < 0
            dist_p -= 0.1
            ps_areaEdif_ = polyShape.partialPolyOffset(ps_areaEdif_, edges_p, dist_p)
        elseif delta_o == delta_min && delta_o < 0
            dist_o -= 0.1
            ps_areaEdif_ = polyShape.partialPolyOffset(ps_areaEdif_, edges_o, dist_o)
        elseif delta_s == delta_min && delta_s < 0
            dist_s -= 0.1
            ps_areaEdif_ = polyShape.partialPolyOffset(ps_areaEdif_, edges_s, dist_s)
        end

        # Update rasante volumes if still violated
        if minimum((delta_p, delta_o, delta_s)) < 0
            levels = collect(0:0.1:maximum(vec_altVolRasante))*ratio
            levels = filter(x -> x < sum(np_cand)*alturaPiso, levels)
            push!(levels, sum(np_cand)*alturaPiso)
            vec_altVolRasante = levels
            vec_psVolRasante = [polyShape.polyOffset(ps_bruto, -lev/ratio) for lev in levels]
            vec_psVolRasante = [polyShape.polyIntersect(ps, ps_areaEdif_) for ps in vec_psVolRasante]
        end

        # Store best
        best_ps .= ps_candidates
        best_np .= np_cand

    end

    return best_ps, best_np
end