# Constants for better maintainability
const MAX_ITER = 1000
const DELTA_DIST = -0.5
const EPS_AREA = 1e-10
const MIN_AREA_THRESHOLD = 50.0

function calculate_buildable_area(dict_geom, dict_requerimientos, dict_arquitectura, altura, n_pisos)
    # Calculates the buildable footprint area considering setbacks and separations.

    # Calculate separation from neighbors
    distanciamiento = dict_requerimientos["distanciamiento"][1]
    expr_str = expression_converter.parse_python_expression(dict_requerimientos["distanciamiento"][3])
    expr_str = replace(expr_str, "flag_sombra" => false)
    expr_str = replace(expr_str, "altura" => string(altura))
    expr_str = replace(expr_str, "n_pisos" => string(n_pisos))
    expr_str = replace(expr_str, "distanciamiento" => string(distanciamiento))
    expr_str = replace(expr_str, "flag_vano" => string(dict_arquitectura["flag_vano"]))
    sepVecinos = eval(Meta.parse(expr_str))
    
    # Create offset distances vector
    vec_dist = Float64.(copy(dict_geom["vecSecTodos"]))
    vec_dist .= -dict_requerimientos["antejardin"]
    vec_dist[dict_geom["vecSecSinCalle"]] .= -sepVecinos

    return polyShape.partialPolyOffset(dict_geom["ps_combi"], dict_geom["vecSecTodos"], vec_dist)
end

function calculate_theoretical_volumes(ps_bruto, ps_areaEdif, altura_max, rasante)
    # Calculates theoretical building volumes based on height restrictions and setbacks.

    vec_altVolteor = collect(0:0.5:altura_max)
    n_alts = length(vec_altVolteor)
    vec_psVolteor = Vector{PolyShape}(undef, n_alts)
    
    # Pre-calculate offset polygons for better performance
    Threads.@threads for i in 1:n_alts
        alt = vec_altVolteor[i]
        offset_poly = polyClipper.polyOffset(ps_bruto, -alt / rasante)
        vec_psVolteor[i] = polyShape.polyIntersection(offset_poly, ps_areaEdif)
    end
    
    return vec_altVolteor, vec_psVolteor
end

function process_shadow_direction(shadow_poly, constraint_matrix, constraint_vector, edges, direction_key)
    # Helper function to process a single shadow direction and extract constraint data.

    area = polyShape.polyArea(shadow_poly)
    is_active = area >= EPS_AREA
    
    constraint_edges = if is_active
        centroid = polyGdal.shapeCentroid(shadow_poly)
        constraint_values = constraint_matrix * centroid.Vertices'
        edges[constraint_values .>= constraint_vector]
    else
        Int[]
    end
    
    return Dict(
        "flag_$(direction_key)" => is_active,
        "area_$(direction_key)" => area,
        "edges_$(direction_key)" => constraint_edges
    )
end

function setup_shadow_constraints(vec_psVolteor, vec_altVolteor, dict_geom, ps_areaEdif)
    # Sets up shadow constraint calculations and returns shadow data dictionary.

    # Calculate theoretical shadows
    vec_sombraTeor = generaSombraTeor(vec_psVolteor, vec_altVolteor, dict_geom["ps_publico"], dict_geom["ps_calles_contexto"])
    
    # Prepare constraint matrix once
    A0, b0 = polyShape.poly2Constraints(ps_areaEdif)
    edges = collect(1:length(b0))
    
    # Process all shadow directions
    directions = ["p", "o", "s"]
    shadow_data = Dict{String, Any}()
    
    for (i, direction) in enumerate(directions)
        direction_data = process_shadow_direction(vec_sombraTeor[i], A0, b0, edges, direction)
        merge!(shadow_data, direction_data)
    end
    
    # Add theoretical shadow volumes to shadow_data
    shadow_data["ps_sombraVolTeorico_p"] = vec_sombraTeor[1]
    shadow_data["ps_sombraVolTeorico_o"] = vec_sombraTeor[2]
    shadow_data["ps_sombraVolTeorico_s"] = vec_sombraTeor[3]
    
    return shadow_data
end

function optimize_with_shadow_constraints(vec_psVolConSombra, vec_altVolConSombra, shadow_data, floors, 
                                        dict_arquitectura, dict_geom, max_ocupacion_suelo, max_losa_snt, ps_areaEdif_ref)
    # Performs iterative optimization considering shadow constraints.
    
    # Initialize deltas
    delta_p = shadow_data["flag_p"] ? -1.0 : 1000.0
    delta_o = shadow_data["flag_o"] ? -1.0 : 1000.0  
    delta_s = shadow_data["flag_s"] ? -1.0 : 1000.0
    
    # Work with copies to avoid modifying originals - performance optimization
    vec_psVolConSombra_work = copy(vec_psVolConSombra)  # Shallow copy first
    ps_areaEdif_work = deepcopy(ps_areaEdif_ref[])  # Only deep copy when needed
    
    best_result = Dict{String, Any}(
        "objective_val" => 0.0,
        "ps_stack" => [PolyShape([], 1) for _ in 1:dict_arquitectura["K"]],
        "np_stack" => zeros(Int, dict_arquitectura["K"])
    )
    
    iter = 0
    while iter < MAX_ITER && min(delta_p, delta_o, delta_s) < 0
        iter += 1
        
        # Optimize volumes for K stacks
        ps_stack, np_stack, objective_val = quad_opti_vol(
            vec_psVolConSombra_work, vec_altVolConSombra, floors, dict_arquitectura["alturaPiso"],
            max_ocupacion_suelo, max_losa_snt, dict_arquitectura["K"], 
            dict_arquitectura["ancho_crujia_min"], dict_arquitectura["ancho_crujia_max"]
        )
        
        # Calculate actual shadows
        vec_alt_acum = cumsum(np_stack) .* dict_arquitectura["alturaPiso"]
        ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s = 
            generaSombraEdificio(ps_stack, vec_alt_acum, dict_geom["ps_publico"], dict_geom["ps_calles_contexto"])
        
        # Calculate shadow violations more efficiently
        area_act_p = polyShape.polyArea(ps_sombraEdif_p)
        area_act_o = polyShape.polyArea(ps_sombraEdif_o)
        area_act_s = polyShape.polyArea(ps_sombraEdif_s)
        
        # Update deltas efficiently using vectorized approach
        deltas = [delta_p, delta_o, delta_s]
        areas_actual = [area_act_p, area_act_o, area_act_s]
        areas_target = [shadow_data["area_p"], shadow_data["area_o"], shadow_data["area_s"]]
        
        for i in 1:3
            if deltas[i] != 1000.0
                deltas[i] = areas_actual[i] > EPS_AREA ? areas_target[i] / areas_actual[i] - 1 : 1.0
            end
        end
        
        delta_p, delta_o, delta_s = deltas
        
        delta_min = min(delta_p, delta_o, delta_s)
        
        # Adjust buildable area if constraint is violated
        if delta_min < 0
            if delta_p == delta_min && !isempty(shadow_data["edges_p"])
                ps_areaEdif_work = polyShape.partialPolyOffset(ps_areaEdif_work, shadow_data["edges_p"], DELTA_DIST)
            elseif delta_o == delta_min && !isempty(shadow_data["edges_o"])
                ps_areaEdif_work = polyShape.partialPolyOffset(ps_areaEdif_work, shadow_data["edges_o"], DELTA_DIST)
            elseif delta_s == delta_min && !isempty(shadow_data["edges_s"])
                ps_areaEdif_work = polyShape.partialPolyOffset(ps_areaEdif_work, shadow_data["edges_s"], DELTA_DIST)
            end
            
            # Update volumes with new buildable area - performance critical
            for i in eachindex(vec_psVolConSombra_work)
                vec_psVolConSombra_work[i] = polyShape.polyIntersection(vec_psVolConSombra[i], ps_areaEdif_work)
            end
            
        elseif objective_val > best_result["objective_val"]
            # Update best solution - avoid unnecessary deep copies
            best_result["objective_val"] = objective_val
            best_result["ps_stack"] = ps_stack  # Already a copy from quad_opti_vol
            best_result["np_stack"] = np_stack  # Already a copy from quad_opti_vol
            best_result["ps_sombraEdif_p"] = ps_sombraEdif_p
            best_result["ps_sombraEdif_o"] = ps_sombraEdif_o
            best_result["ps_sombraEdif_s"] = ps_sombraEdif_s
        end
    end
    
    return best_result
end

function calculate_shadow_volumes(ps_predio, ps_areaEdif, altura_max, rasante_sombra)
    # Calculates shadow volumes for the given parameters.

    vec_altVolConSombra = collect(0:0.5:altura_max)
    vec_psVolConSombra = Vector{PolyShape}(undef, length(vec_altVolConSombra))
    
    Threads.@threads for i in eachindex(vec_altVolConSombra)
        alt = vec_altVolConSombra[i]
        offset_poly = polyClipper.polyOffset(ps_predio, -alt / rasante_sombra)
        vec_psVolConSombra[i] = polyShape.polyIntersection(offset_poly, ps_areaEdif)
    end
    
    return vec_altVolConSombra, vec_psVolConSombra
end

function generate_floor_combinations(min_pisos, max_pisos, K)
    # Generates valid floor combinations for optimization.

    function generate_stack_vector(pisos_tot, num_stacks)
        if num_stacks <= 0 || pisos_tot < 0
            return Vector{Vector}()
        end

        results = Vector{Vector}()

        function backtrack(current_vec::Vector, remaining_sum, remaining_positions)
            # Base case: filled all positions
            if remaining_positions == 0
                if remaining_sum == 0
                    push!(results, copy(current_vec))
                end
                return
            end

            # Determine the maximum we can place here:
            max_val = remaining_sum
            if !isempty(current_vec)
                max_val = min(max_val, current_vec[end])
            end

            # Try all values from 0 up to that max
            for val in 0:max_val
                push!(current_vec, val)
                backtrack(current_vec, remaining_sum - val, remaining_positions - 1)
                pop!(current_vec)
            end
        end

        backtrack(Int[], pisos_tot, num_stacks)
        return results
    end

    vec_stacks_ = Vector{Vector{Int}}()
    
    for pisos in min_pisos:max_pisos
        vec_stacks_p = generate_stack_vector(pisos, K)
        append!(vec_stacks_, vec_stacks_p)
    end
    
    # Pre-filter to reduce iterations
    return filter(v -> v[1] >= max_pisos - 2, vec_stacks_)
end

function opti_edificio_vol(dict_geom, dict_arquitectura, dict_requerimientos, vec_pisos, max_ocupacion_suelo, max_losa_snt)
    # Main function

    ps_predio = dict_geom["ps_combi"]
    ps_bruto = dict_geom["ps_bruto"]
    alturaPiso = dict_arquitectura["alturaPiso"]
    K = dict_arquitectura["K"]
    flag_sombra = dict_arquitectura["flag_sombra"]
    alturaMax = dict_requerimientos["altura_max"]
    rasante = tan(dict_requerimientos["rasante"] * π / 180)
    rasante_sombra = dict_requerimientos["rasante_sombra"]
    
    min_pisos = minimum(vec_pisos)
    max_pisos = maximum(vec_pisos)

    # Initialize best solution tracking
    best_result = Dict{String, Any}(
        "ps_stack" => [PolyShape([], 1) for _ in 1:K],
        "np_stack" => zeros(Int, K),
        "max_sol" => 0.0,
        "vec_altVolteor" => Float64[],
        "vec_psVolteor" => PolyShape[],
        "vec_altVolConSombra" => Float64[],
        "vec_psVolConSombra" => PolyShape[],
        "ps_sombraEdif_p" => PolyShape[],
        "ps_sombraEdif_o" => PolyShape[],
        "ps_sombraEdif_s" => PolyShape[]
    )

    # Generate floor combinations more efficiently
    vec_stacks = generate_floor_combinations(min_pisos, max_pisos, K)
    
    # Cache variables for performance - avoid recomputing expensive operations
    cached_altura = -1
    cached_ps_areaEdif = PolyShape([], 0)
    cached_volumes = (Float64[], PolyShape[])
    cached_shadow_volumes = (Float64[], PolyShape[])
    
    # Main optimization loop
    for (iter_floors, floors) in enumerate(vec_stacks)
        n_pisos = sum(floors)
        altura = n_pisos * alturaPiso
        
        # Only recalculate when height changes (performance optimization)
        if altura != cached_altura
            cached_altura = altura
            
            # Calculate buildable area with error handling
            try
                cached_ps_areaEdif = calculate_buildable_area(dict_geom, dict_requerimientos, dict_arquitectura, altura, n_pisos)
                
                # Early termination if area too small
                if polyShape.polyArea(cached_ps_areaEdif) < MIN_AREA_THRESHOLD
                    continue
                end
                
                # Calculate theoretical volumes with performance optimization
                cached_volumes = calculate_theoretical_volumes(ps_bruto, cached_ps_areaEdif, alturaMax, rasante)
                vec_altVolteor, vec_psVolteor = cached_volumes
                
                if flag_sombra
                    # Calculate shadow volumes and cache them
                    cached_shadow_volumes = calculate_shadow_volumes(ps_predio, cached_ps_areaEdif, alturaMax, rasante_sombra)
                end
                
            catch e
                @warn "Error calculating buildable area for altura=$altura: $e"
                continue
            end
        end
        
        # Get cached values
        vec_altVolteor, vec_psVolteor = cached_volumes
        
        if flag_sombra
            vec_altVolConSombra, vec_psVolConSombra = cached_shadow_volumes
            shadow_data = setup_shadow_constraints(vec_psVolteor, vec_altVolteor, dict_geom, cached_ps_areaEdif)
            
            # Only proceed if any shadow constraints are active
            if shadow_data["flag_p"] || shadow_data["flag_o"] || shadow_data["flag_s"]
                ps_areaEdif_ref = Ref(cached_ps_areaEdif)
                shadow_result = optimize_with_shadow_constraints(
                    vec_psVolConSombra, vec_altVolConSombra, shadow_data, floors,
                    dict_arquitectura, dict_geom, max_ocupacion_suelo, max_losa_snt, ps_areaEdif_ref
                )
                
                if shadow_result["objective_val"] > best_result["max_sol"]
                    best_result["max_sol"] = shadow_result["objective_val"]
                    best_result["ps_stack"] = shadow_result["ps_stack"]
                    best_result["np_stack"] = shadow_result["np_stack"]
                    best_result["vec_altVolteor"] = vec_altVolteor
                    best_result["vec_psVolteor"] = vec_psVolteor
                    best_result["vec_altVolConSombra"] = vec_altVolConSombra
                    best_result["vec_psVolConSombra"] = vec_psVolConSombra
                    best_result["ps_sombraEdif_p"] = shadow_result["ps_sombraEdif_p"]
                    best_result["ps_sombraEdif_o"] = shadow_result["ps_sombraEdif_o"]
                    best_result["ps_sombraEdif_s"] = shadow_result["ps_sombraEdif_s"]
                    best_result["ps_sombraVolTeorico_p"] = shadow_data["ps_sombraVolTeorico_p"]
                    best_result["ps_sombraVolTeorico_o"] = shadow_data["ps_sombraVolTeorico_o"]
                    best_result["ps_sombraVolTeorico_s"] = shadow_data["ps_sombraVolTeorico_s"]
                end
            end
        else
            # No shadow constraints - direct optimization
            ps_stack, np_stack, objective_val = quad_opti_vol(
                vec_psVolteor, vec_altVolteor, floors, alturaPiso,
                max_ocupacion_suelo, max_losa_snt, K,
                dict_arquitectura["ancho_crujia_min"], dict_arquitectura["ancho_crujia_max"]
            )
            
            if objective_val > best_result["max_sol"]
                best_result["max_sol"] = objective_val
                best_result["ps_stack"] = ps_stack
                best_result["np_stack"] = np_stack
                best_result["vec_altVolteor"] = vec_altVolteor
                best_result["vec_psVolteor"] = vec_psVolteor
                
                # Calculate shadow volumes for output consistency using helper function
                vec_altVolConSombra, vec_psVolConSombra = calculate_shadow_volumes(ps_predio, cached_ps_areaEdif, alturaMax, rasante_sombra)
                
                best_result["vec_altVolConSombra"] = vec_altVolConSombra
                best_result["vec_psVolConSombra"] = vec_psVolConSombra
                
            end
        end
        
        # Early termination if near optimal
        if best_result["max_sol"] >= 0.99 * max_losa_snt
            break
        end
    end

    # Return results in original format
    return (best_result["ps_stack"], best_result["np_stack"], best_result["max_sol"], 
            best_result["vec_psVolteor"], best_result["vec_altVolteor"], 
            best_result["vec_psVolConSombra"], best_result["vec_altVolConSombra"],
            get(best_result, "ps_sombraEdif_p", PolyShape[]),
            get(best_result, "ps_sombraEdif_o", PolyShape[]),
            get(best_result, "ps_sombraEdif_s", PolyShape[]),
            get(best_result, "ps_sombraVolTeorico_p", PolyShape[]),
            get(best_result, "ps_sombraVolTeorico_o", PolyShape[]),
            get(best_result, "ps_sombraVolTeorico_s", PolyShape[]))
end
