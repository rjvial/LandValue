function opti_vol_edificio(vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra, vec_pisos, alturaPiso, ps_areaEdif, ps_calles, ps_publico, ps_bruto,
        areaSombra_p, areaSombra_o, areaSombra_s, max_ocupacion_suelo, maxConstruccionSNT, K, centroidSombra_p, centroidSombra_o, centroidSombra_s;
        ancho_crujia_min = 0, ancho_crujia_max = 0, flag_sombra = false)


    vecLargoLados, _, _, _ = polyShape.extraeInfoPoly(ps_areaEdif)
    max_lado = maximum(vecLargoLados)
    max_pisos = maximum(vec_pisos)
    min_pisos = ancho_crujia_max > 0 ? min(max_pisos-2, Int(floor(maxConstruccionSNT / (max_lado * ancho_crujia_max)))) : max_pisos - 2

    local ps_stack, np_stack

    if flag_sombra
        max_iter = 1000  # 50*10 = 500
        delta_dist = -0.1*5

        # Prepare rasante constraints
        A0, b0 = polyShape.poly2Constraints(ps_areaEdif)

        # Identify edges for shadow adjustments (pre-compute matrix operations)
        vec_edges = collect(1:length(b0))
        A0_p = A0 * centroidSombra_p.Vertices'
        A0_o = A0 * centroidSombra_o.Vertices'
        A0_s = A0 * centroidSombra_s.Vertices'

        edges_p = vec_edges[A0_p .>= b0]
        edges_o = vec_edges[A0_o .>= b0]
        edges_s = vec_edges[A0_s .>= b0]

        # Storage for best known
        best_ps = [PolyShape([],1) for _ in 1:K]
        best_np = zeros(Int, K)

        # Pre-allocate variables to avoid repeated allocations
        local ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s
        local area_act_p, area_act_o, area_act_s
        local delta_min

        # Small epsilon for area comparison
        eps_area = 1e-10
        max_sol = 0
        flag_continue = true
        
        vec_stacks = []
        for pisos in min_pisos:max_pisos

            vec_stacks_p = generate_stack_vector(pisos, K)
            if pisos == min_pisos
                vec_stacks = vec_stacks_p
            else
                vec_stacks = vcat(vec_stacks, vec_stacks_p)
            end
        end
        vec_stacks = [v for v in vec_stacks if v[1] ≥ max_pisos - K]

        iter_c = 0
        piso_aux = 0
        while flag_continue
            iter_c += 1
            c = vec_stacks[iter_c]

            if piso_aux < sum(c)
                piso_aux = sum(c)
                
            else
            end

            ps_areaEdif_ = deepcopy(ps_areaEdif)

            # Iterative shadow loop params
            delta_p = -1.0
            delta_o = -1.0 
            delta_s = -1.0

            vec_psVolConSombra_ = deepcopy(vec_psVolConSombra)
            iter = 0
            while iter < max_iter && min(delta_p, delta_o, delta_s) < 0
                iter += 1

                try
                    # Optimize volumes for K stacks
                    ps_stack, np_stack, objective_val = quad_opti_vol(vec_psVolConSombra_, vec_altVolConSombra, c, alturaPiso, max_ocupacion_suelo, maxConstruccionSNT, K, ancho_crujia_min = ancho_crujia_min, ancho_crujia_max = ancho_crujia_max)
                    
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
                        vec_psVolConSombra_ = [polyShape.polyIntersect(ps, ps_areaEdif_) for ps in vec_psVolConSombra_]

                    elseif objective_val > max_sol
                        # Store best
                        max_sol = objective_val
                        best_ps = deepcopy(ps_stack)
                        best_np = deepcopy(np_stack)
                    end

                catch  
                    objective_val = 0
                end

            end

            if max_sol >= 0.99 * maxConstruccionSNT || iter_c == length(vec_stacks)
                flag_continue = false
            end
        end
    else
            # Storage for best known
        best_ps = [PolyShape([],1) for _ in 1:K]
        best_np = zeros(Int, K)

        max_sol = 0
        for pisos in min_pisos:max_pisos
            vec_stacks = generate_stack_vector(pisos, K)
            for c in vec_stacks
                ps_stack, np_stack, objective_val = quad_opti_vol(vec_psVolteor, vec_altVolteor, c, alturaPiso, max_ocupacion_suelo, maxConstruccionSNT, K, ancho_crujia_min = ancho_crujia_min, ancho_crujia_max = ancho_crujia_max)
                if objective_val > max_sol
                    # Store best
                    max_sol = objective_val
                    best_ps = deepcopy(ps_stack)
                    best_np = deepcopy(np_stack)
                end
            end
        end

    end

    return best_ps, best_np, max_sol
end

