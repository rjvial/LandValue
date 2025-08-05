function opti_edificio_vol(dict_geom, dict_arquitectura, dict_requerimientos, vec_pisos, max_ocupacion_suelo, max_losa_snt)

    ps_predio = dict_geom["ps_predio"]
    ps_calles = dict_geom["ps_calles"]
    ps_publico = dict_geom["ps_publico"]
    ps_bruto = dict_geom["ps_bruto"]
    vecSecTodos = dict_geom["vecSecTodos"]
    vecSecSinCalle = dict_geom["vecSecSinCalle"]

    alturaPiso = dict_arquitectura["alturaPiso"]
    K = dict_arquitectura["K"]
    ancho_crujia_min = dict_arquitectura["ancho_crujia_min"]
    ancho_crujia_max = dict_arquitectura["ancho_crujia_max"]
    flag_sombra = dict_arquitectura["flag_sombra"]
    flag_vano = dict_arquitectura["flag_vano"]

    antejardin = dict_requerimientos["antejardin"] # 8 # 12 # 
    alturaMax = dict_requerimientos["altura_max"]
    rasante = tan(dict_requerimientos["rasante"]*pi/180)

    rasante_sombra = dict_requerimientos["rasante_sombra"]

    min_pisos = minimum(vec_pisos)
    max_pisos = maximum(vec_pisos)

    local ps_stack, np_stack

    max_iter = 1000  
    delta_dist = -0.1*5

    # Storage for best known
    best_ps = [PolyShape([],1) for _ in 1:K]
    best_np = zeros(Int, K)

    local best_vec_altVolteor, best_vec_psVolteor, best_vec_altVolConSombra, best_vec_psVolConSombra 
    vec_altVolteor = []
    vec_psVolteor = []
    vec_altVolConSombra = []
    vec_psVolConSombra = [] 

    # Pre-allocate variables to avoid repeated allocations
    local ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s
    local area_act_p, area_act_o, area_act_s
    local delta_min, ps_areaEdif

    local flag_p, flag_o, flag_s
    local areaSombra_p, areaSombra_o, areaSombra_s
    local edges_p, edges_o, edges_s


    # Small epsilon for area comparison
    eps_area = 1e-10
    max_sol = 0
    
    vec_stacks_ = []
    for pisos in min_pisos:max_pisos

        vec_stacks_p = generate_stack_vector(pisos, K)
        if pisos == min_pisos
            vec_stacks_ = vec_stacks_p
        else
            vec_stacks_ = vcat(vec_stacks_, vec_stacks_p)
        end
    end
    vec_stacks = [v for v in vec_stacks_ if v[1] ≥ max_pisos - 2]

    flag_continue = true
    iter_floors = 0
    pisos_aux = 0
    while flag_continue
        iter_floors += 1
        floors = vec_stacks[iter_floors]

        if pisos_aux < sum(floors) # Cuando aumenta el numero de pisos
            n_pisos = sum(floors)
            pisos_aux = n_pisos

            altura = n_pisos * alturaPiso
            distanciamiento = dict_requerimientos["distanciamiento"][1]
            expr_str = expression_converter.parse_python_expression(dict_requerimientos["distanciamiento"][3])
            expr_str = replace(expr_str, "flag_sombra" => false) # Nunca se usa sombra para el cálculo del distanciamiento
            expr_str = replace(expr_str, "altura"  => string(altura))
            expr_str = replace(expr_str, "n_pisos" => string(n_pisos))
            expr_str = replace(expr_str, "distanciamiento" => string(distanciamiento))
            expr_str = replace(expr_str, "flag_vano" => string(flag_vano))
            sepVecinos = eval(Meta.parse(expr_str))

            vec_dist = Float64.(copy(vecSecTodos))
            vec_dist .= -antejardin
            vec_dist[vecSecSinCalle] .= -sepVecinos
            ps_areaEdif = polyShape.partialPolyOffset(ps_predio, vecSecTodos, vec_dist)

            if polyShape.polyArea(ps_areaEdif) < 50
                flag_continue = false
                continue
            end
            # Calcula el Volumen Teórico
            vec_altVolteor = collect(0:0.5:alturaMax)
            vec_psVolteor = [polyShape.polyOffset(ps_bruto, -i / rasante) for i in vec_altVolteor]
            vec_psVolteor = [polyShape.polyIntersect(vec_psVolteor[i], ps_areaEdif) for i in eachindex(vec_psVolteor)]

            if flag_sombra == true 
                # Prepare rasante constraints
                A0, b0 = polyShape.poly2Constraints(ps_areaEdif)
                vec_edges = collect(1:length(b0))

                # Calcula sombra del Volumen Teórico
                @time ps_sombraVolTeorico_p, ps_sombraVolTeorico_o, ps_sombraVolTeorico_s = generaSombraTeor(vec_psVolteor, vec_altVolteor, ps_publico, ps_calles)

                flag_p = true; flag_o = true; flag_s = true
            
                areaSombra_p = polyShape.polyArea(ps_sombraVolTeorico_p)
                if areaSombra_p < eps_area
                    flag_p = false
                end
                centroidSombra_p = polyShape.shapeCentroid(ps_sombraVolTeorico_p)
                A0_p = A0 * centroidSombra_p.Vertices'
                edges_p = vec_edges[A0_p .>= b0]

                areaSombra_o = polyShape.polyArea(ps_sombraVolTeorico_o)
                if areaSombra_o < eps_area
                    flag_o = false
                end
                centroidSombra_o = polyShape.shapeCentroid(ps_sombraVolTeorico_o)
                A0_o = A0 * centroidSombra_o.Vertices'
                edges_o = vec_edges[A0_o .>= b0]

                areaSombra_s = polyShape.polyArea(ps_sombraVolTeorico_s)
                if areaSombra_s < eps_area
                    flag_s = false
                end
                centroidSombra_s = polyShape.shapeCentroid(ps_sombraVolTeorico_s)
                A0_s = A0 * centroidSombra_s.Vertices'
                edges_s = vec_edges[A0_s .>= b0]

                # Calcula el volumen sin restricciones
                vec_altVolConSombra = collect(0:0.5:alturaMax)
                vec_psVolConSombra = [polyShape.polyOffset(ps_predio, - alt/rasante_sombra) for alt in vec_altVolConSombra]
                vec_psVolConSombra = [polyShape.polyIntersect(vec_psVolConSombra[i], ps_areaEdif) for i in eachindex(vec_psVolConSombra)]
            end
        end

        if flag_sombra == true

            # Iterative shadow loop params
            delta_p = flag_p ? -1.0 : 1000
            delta_o = flag_o ? -1.0 : 1000
            delta_s = flag_s ? -1.0 : 1000

            ps_areaEdif_ = deepcopy(ps_areaEdif)
            vec_psVolConSombra_ = deepcopy(vec_psVolConSombra)
            iter = 0
            while iter < max_iter && min(delta_p, delta_o, delta_s) < 0
                iter += 1

                # Optimize volumes for K stacks
                ps_stack, np_stack, objective_val = quad_opti_vol(vec_psVolConSombra_, vec_altVolConSombra, floors, alturaPiso, max_ocupacion_suelo, max_losa_snt, K, ancho_crujia_min, ancho_crujia_max)

                # Compute cumulative heights once
                vec_alt_acum = cumsum(np_stack) .* alturaPiso

                # Compute shadows cumulatively
                ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s = generaSombraEdificio(ps_stack, vec_alt_acum, ps_publico, ps_calles)
            
                # Sum actual shadow areas
                area_act_p = polyShape.polyArea(ps_sombraEdif_p)
                area_act_o = polyShape.polyArea(ps_sombraEdif_o)
                area_act_s = polyShape.polyArea(ps_sombraEdif_s)

                # Compute ratios more efficiently (avoid repeated comparisons)
                delta_p = delta_p == 1000 ? 1000 : area_act_p > eps_area ? areaSombra_p / area_act_p - 1 : 1.0
                delta_o = delta_o == 1000 ? 1000 : area_act_o > eps_area ? areaSombra_o / area_act_o - 1 : 1.0
                delta_s = delta_s == 1000 ? 1000 : area_act_s > eps_area ? areaSombra_s / area_act_s - 1 : 1.0

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
                    best_vec_altVolteor = deepcopy(vec_altVolteor)
                    best_vec_psVolteor = deepcopy(vec_psVolteor)
                    best_vec_altVolConSombra = deepcopy(vec_altVolConSombra)
                    best_vec_psVolConSombra  = deepcopy(vec_psVolConSombra)
                end
            end

        else
            ps_stack, np_stack, objective_val = quad_opti_vol(vec_psVolteor, vec_altVolteor, floors, alturaPiso, max_ocupacion_suelo, max_losa_snt, K, ancho_crujia_min, ancho_crujia_max)
            if objective_val > max_sol
                # Store best
                max_sol = objective_val
                best_ps = deepcopy(ps_stack)
                best_np = deepcopy(np_stack)
                best_vec_altVolteor = deepcopy(vec_altVolteor)
                best_vec_psVolteor = deepcopy(vec_psVolteor)

                best_vec_altVolConSombra = collect(0:0.5:alturaMax)
                best_vec_psVolConSombra = [polyShape.polyOffset(ps_predio, - alt/rasante_sombra) for alt in best_vec_altVolConSombra]
                best_vec_psVolConSombra = [polyShape.polyIntersect(best_vec_psVolConSombra[i], ps_areaEdif) for i in eachindex(best_vec_altVolConSombra)]
            end
        end

        if max_sol >= 0.99 * max_losa_snt || iter_floors == length(vec_stacks)
            flag_continue = false
        end
    end


    return best_ps, best_np, max_sol, best_vec_psVolteor, best_vec_altVolteor, best_vec_psVolConSombra, best_vec_altVolConSombra
end

