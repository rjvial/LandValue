function opti_vol_edificio_sombra(vec_psVolConSombra, vec_altVolConSombra, vec_pisos, alturaPiso, ps_areaEdif, ps_calles, ps_publico, ps_bruto,
        areaSombra_p, areaSombra_o, areaSombra_s, max_ocupacion_suelo, maxConstruccionSNT, K, centroidSombra_p, centroidSombra_o, centroidSombra_s;
        ancho_crujia_min = 0, ancho_crujia_max = 0
    )

    # Prepare rasante constraints
    ps_areaEdif_ = deepcopy(ps_areaEdif)
    A0, b0 = polyShape.poly2Constraints(ps_areaEdif_)


    # Identify edges for shadow adjustments (pre-compute matrix operations)
    vec_edges = collect(1:length(b0))
    A0_p = A0 * centroidSombra_p.Vertices'
    A0_o = A0 * centroidSombra_o.Vertices'
    A0_s = A0 * centroidSombra_s.Vertices'

    edges_p = vec_edges[A0_p .>= b0]
    edges_o = vec_edges[A0_o .>= b0]
    edges_s = vec_edges[A0_s .>= b0]

    # Iterative shadow loop params
    iter = 0
    max_iter = 1000  # 50*10 = 500
    delta_p = -1.0
    delta_o = -1.0 
    delta_s = -1.0
    
    delta_dist = -0.1*5

    # Storage for best known
    best_ps = [PolyShape([],1) for _ in 1:K]
    best_np = zeros(Int, K)

    # Pre-allocate variables to avoid repeated allocations
    local ps_stack, np_stack
    local ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s
    local area_act_p, area_act_o, area_act_s
    local delta_min

    # Small epsilon for area comparison
    eps_area = 1e-10
    
    while iter < max_iter && min(delta_p, delta_o, delta_s) < 0
        iter += 1

        # Optimize volumes for K stacks
        ps_stack, np_stack = opti_vol_edificio(vec_psVolConSombra, vec_altVolConSombra, vec_pisos, alturaPiso, max_ocupacion_suelo, maxConstruccionSNT, K, ancho_crujia_min = ancho_crujia_min, ancho_crujia_max = ancho_crujia_max)

        # println("Iteration: $iter, np_stack: $np_stack")
        # Compute cumulative heights once
        vec_alt_acum = cumsum(np_stack) .* alturaPiso

        # Compute shadows cumulatively
        ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s = generaSombraEdificio(ps_stack, vec_alt_acum, ps_publico, ps_calles)
    
        # Sum actual shadow areas
        area_act_p = polyShape.polyArea(ps_sombraEdif_p)
        area_act_o = polyShape.polyArea(ps_sombraEdif_o)
        area_act_s = polyShape.polyArea(ps_sombraEdif_s)

        # Compute ratios more efficiently (avoid repeated comparisons)
        delta_p = area_act_p > eps_area ? areaSombra_p / area_act_p - 1 : 1.0
        delta_o = area_act_o > eps_area ? areaSombra_o / area_act_o - 1 : 1.0
        delta_s = area_act_s > eps_area ? areaSombra_s / area_act_s - 1 : 1.0

        # Find minimum delta more efficiently
        delta_min = min(delta_p, delta_o, delta_s)

        # Adjust buildable footprint on worst violation (simplified logic)
        if delta_min < 0
            if delta_p == delta_min
                ps_areaEdif_ = polyShape.partialPolyOffset(ps_areaEdif_, edges_p, delta_dist)
            elseif delta_o == delta_min
                ps_areaEdif_ = polyShape.partialPolyOffset(ps_areaEdif_, edges_o, delta_dist)
            else  # delta_s == delta_min
                ps_areaEdif_ = polyShape.partialPolyOffset(ps_areaEdif_, edges_s, delta_dist)
            end

            # Update rasante volumes (moved inside if block for efficiency)
            vec_psVolConSombra = [polyShape.polyIntersect(ps, ps_areaEdif_) for ps in vec_psVolConSombra]
        end

        # Store best
        best_ps = deepcopy(ps_stack)
        best_np = deepcopy(np_stack)

        # fig, ax, ax_mat = plotBaseEdificio3D(fpe, alturaPiso, ps_predio, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra, ps_publico, ps_calles, best_ps, best_np, vec_ps_subte, vec_np_subte, tipo_edificio)
    end

    return best_ps, best_np
end