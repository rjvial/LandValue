# ============================================================================
# BUILDING VOLUME OPTIMIZATION MODULE
# ============================================================================

# ============================================================================
# CONSTANTS AND CONFIGURATION
# ============================================================================
const MAX_ITER = 1000
const DELTA_DIST = -0.5
const EPS_AREA = 1e-10
const MIN_AREA_THRESHOLD = 50.0


# ============================================================================
# HELPER FUNCTIONS FOR AREA AND VOLUME CALCULATIONS
# ============================================================================
function calculate_buildable_area(dict_geom, dict_requerimientos, dict_arquitectura, altura, n_pisos)
    # Calculates the buildable footprint area considering setbacks and separations.

    # Calculate separation from neighbors
    distanciamiento = dict_requerimientos["norm_distanciamiento"][1]
    expr_str = expression_converter.parse_python_expression(dict_requerimientos["norm_distanciamiento"][3])
    expr_str = replace(expr_str, "flag_sombra" => false)
    expr_str = replace(expr_str, "altura" => string(altura))
    expr_str = replace(expr_str, "n_pisos" => string(n_pisos))
    expr_str = replace(expr_str, "distanciamiento" => string(distanciamiento))
    expr_str = replace(expr_str, "flag_vano" => string(dict_arquitectura["arq_flag_vano"]))
    sepVecinos = eval(Meta.parse(expr_str))
    
    # Create offset distances vector
    vec_dist = Float64.(copy(dict_geom["vecSecTodos"]))
    vec_dist .= -dict_requerimientos["norm_antejardin"]
    vec_dist[dict_geom["vecSecSinCalle"]] .= -sepVecinos

    ps = deepcopy(dict_geom["ps_combi"])
    vec_partial_offset_id = dict_geom["vecSecTodos"]
    vec_partial_offset_dist = vec_dist

    ps_areaEdif = polyShape.partialPolyOffset(ps, vec_partial_offset_id, vec_partial_offset_dist)

    return ps_areaEdif
end

function calculate_theoretical_volumes(ps_bruto, ps_areaEdif, alturaMax, rasante)
    # Calculates theoretical building volumes based on height restrictions and setbacks.

    vec_altVolteor = collect(0:0.5:alturaMax)
    n_alts = length(vec_altVolteor)
    vec_psVolteor = Vector{PolyShape}(undef, n_alts)
    
    # Pre-calculate offset polygons for better performance
    for i in 1:n_alts
        alt = vec_altVolteor[i]
        offset_poly = polyClipper.polyOffset(ps_bruto, -alt / rasante)
        vec_psVolteor[i] = polyShape.polyIntersection(offset_poly, ps_areaEdif)
    end
    
    return vec_altVolteor, vec_psVolteor
end


# ============================================================================
# VOLUME OPTIMIZATION FUNCTIONS
# ============================================================================
function quad_opti_sol_ini(vec_psVolteor, floors)
    if isempty(vec_psVolteor)
        @warn "Volume vector cannot be empty for floors $floors"
        return 0, 0, 0, 0, 0, 0, PolyShape([], 1)
    end

    ps0 = vec_psVolteor[1]
    if isempty(ps0.Vertices)
        @warn "First polygon has no vertices for floors $floors"
        return 0, 0, 0, 0, 0, 0, PolyShape([], 1)
    end

    vertices = ps0.Vertices[1]
    x_coords = vertices[:, 1]
    y_coords = vertices[:, 2]
    width = maximum(x_coords) - minimum(x_coords)
    height = maximum(y_coords) - minimum(y_coords)

    if width <= 0 || height <= 0
        @warn "Invalid polygon dimensions for floors $floors: width=$width, height=$height"
        return 0, 0, 0, 0, 0, 0, PolyShape([], 1)
    end

    best_objective = 0.0
    best_solution = (0, 0, 0, 0, 0, 0, PolyShape([], 1))

    # Try horizontal orientation
    for (orientation, min_w, min_h) in [
        ("horizontal", max(width - 5, 2), 2),
        ("vertical", 2, max(height - 5, 2))
    ]
        try
            model = Model(optimizer_with_attributes(Ipopt.Optimizer, "sb" => "yes"))
            set_silent(model)

            @variable(model, x1)
            @variable(model, y1)
            @variable(model, 0 <= c <= 1)
            @variable(model, -1 <= s <= 1)
            @constraint(model, c^2 + s^2 == 1)
            @variable(model, w >= min_w)
            @variable(model, h >= min_h)

            # Add polygon constraints
            psC_hull = polyGdal.shapeHull(ps0)
            A, b = polyShape.poly2Constraints(psC_hull)

            corners = [[0, 0], [w, 0], [w, h], [0, h]]
            for corner in corners, row in axes(A, 1)
                xg = x1 + c * corner[1] - s * corner[2]
                yg = y1 + s * corner[1] + c * corner[2]
                @constraint(model, A[row, 1] * xg + A[row, 2] * yg <= b[row])
            end

            @objective(model, Max, w * h)

            optimize!(model)
            status = termination_status(model)

            if status in (MOI.LOCALLY_SOLVED, MOI.OPTIMAL, MOI.ALMOST_LOCALLY_SOLVED, MOI.ALMOST_OPTIMAL)
                objective_val = objective_value(model)
                if objective_val > best_objective
                    x1_val = value(x1)
                    y1_val = value(y1)
                    c_val = value(c)
                    s_val = value(s)
                    w_val = value(w)
                    h_val = value(h)

                    if w_val > 0 && h_val > 0
                        coords = Float64[]
                        for (px, py) in [(0, 0), (w_val, 0), (w_val, h_val), (0, h_val)]
                            gx = x1_val + c_val * px - s_val * py
                            gy = y1_val + s_val * px + c_val * py
                            append!(coords, [gx, gy])
                        end

                        mat = reshape(coords, 2, 4)'
                        ps_opt = PolyShape([mat], 1)

                        best_objective = objective_val
                        best_solution = (x1_val, y1_val, c_val, s_val, w_val, h_val, ps_opt)
                    end
                end
            end
        catch e
            @warn "Optimization failed for $orientation orientation with floors $floors: $e"
        end
    end

    if best_objective <= 1e-6
        @warn "No valid solution found for floors $floors"
        return 0, 0, 0, 0, 0, 0, PolyShape([], 1)
    end

    return best_solution
end

function quad_opti_vol(vec_psVolteor, vec_altVolteor, floors, alturaPiso, max_ocupacion_suelo, max_losa_snt, K)

    # Get initial solution
    x1_ini, y1_ini, c_ini, s_ini, w_ini, h_ini, ps0 = quad_opti_sol_ini(vec_psVolteor, floors)

    # Calculate initial dimensions
    width, height = if isempty(ps0.Vertices)
        (0.0, 0.0)
    else
        vertices = ps0.Vertices[1]
        x_coords = vertices[:, 1]
        y_coords = vertices[:, 2]
        (maximum(x_coords) - minimum(x_coords), maximum(y_coords) - minimum(y_coords))
    end

    # Initialize result
    ps_opt = [PolyShape([], 1) for _ in 1:K]
    np_opt = zeros(Int, K)
    objective_val = 0.0

    # Try optimization with two different strategies
    for attempt in 1:2
        try
            model = Model(optimizer_with_attributes(Ipopt.Optimizer, "sb" => "yes"))
            set_silent(model)

            # Variables
            @variable(model, x1)
            @variable(model, y1)
            @variable(model, c)
            @variable(model, s)
            @constraint(model, c^2 + s^2 == 1)

            # Stack dimensions with different bounds per attempt
            if attempt == 1 && width > 0 && height > 0
                if width > height
                    @variables(model, begin
                        w[stack = 1:K] >= width * 0.25
                        h[stack = 1:K] >= 2.0
                    end)
                else
                    @variables(model, begin
                        w[stack = 1:K] >= 2.0
                        h[stack = 1:K] >= height * 0.25
                    end)
                end
            else
                @variables(model, begin
                    w[stack = 1:K] >= 0.1
                    h[stack = 1:K] >= 0.1
                end)
            end

            # Stack offsets
            if K > 1
                @variables(model, begin
                    dx[stack = 2:K] >= 0
                    dy[stack = 2:K] >= 0
                end)
            end

            # Ground occupation constraint
            @constraint(model, w[1] * h[1] <= max_ocupacion_suelo)

            # Nesting constraints
            if K > 1
                for stack in 2:K
                    @constraint(model, dx[stack] + w[stack] <= w[stack - 1])
                    @constraint(model, dy[stack] + h[stack] <= h[stack - 1])
                end
            end

            # Volume constraints for each stack
            num_pisos_acum = 0
            for stack in 1:K
                n_f = floors[stack]
                num_pisos_acum += n_f
                altura_corte_stack = num_pisos_acum * alturaPiso

                # Generate cutting polygon
                psC = generaPoligonoCorte(altura_corte_stack, vec_psVolteor, vec_altVolteor)
                psC = polyGdal.shapeHull(psC)
                A, b = polyShape.poly2Constraints(psC)

                # Stack corner offsets
                ox = stack > 1 ? dx[stack] : 0
                oy = stack > 1 ? dy[stack] : 0

                # Apply constraints to all corners
                corners = [[ox, oy], [ox + w[stack], oy], [ox + w[stack], oy + h[stack]], [ox, oy + h[stack]]]
                for corner in corners, row in axes(A, 1)
                    xg = x1 + c * corner[1] - s * corner[2]
                    yg = y1 + s * corner[1] + c * corner[2]
                    @constraint(model, A[row, 1] * xg + A[row, 2] * yg <= b[row])
                end
            end

            # Constructibility constraint
            @constraint(model, sum(w[stack] * h[stack] * floors[stack] for stack in 1:K) <= max_losa_snt)

            # Objective: maximize total floor area
            @objective(model, Max, sum(w[stack] * h[stack] * floors[stack] for stack in 1:K))

            # Solve
            optimize!(model)
            status = termination_status(model)

            if status in (MOI.LOCALLY_SOLVED, MOI.OPTIMAL, MOI.ALMOST_LOCALLY_SOLVED, MOI.ALMOST_OPTIMAL)
                # Extract solution
                x1_val, y1_val = value(x1), value(y1)
                c_val, s_val = value(c), value(s)
                w_vals = value.(w)
                h_vals = value.(h)
                dx_vals = K > 1 ? value.(dx) : nothing
                dy_vals = K > 1 ? value.(dy) : nothing

                for stack in 1:K
                    ox = stack > 1 ? dx_vals[stack] : 0.0
                    oy = stack > 1 ? dy_vals[stack] : 0.0

                    coords = Float64[]
                    for (px, py) in [(ox, oy), (ox + w_vals[stack], oy), (ox + w_vals[stack], oy + h_vals[stack]), (ox, oy + h_vals[stack])]
                        gx = x1_val + c_val * px - s_val * py
                        gy = y1_val + s_val * px + c_val * py
                        append!(coords, [gx, gy])
                    end

                    mat = reshape(coords, 2, 4)'
                    ps_opt[stack] = PolyShape([mat], 1)
                    np_opt[stack] = floors[stack]
                end

                objective_val = objective_value(model)
                break

            elseif attempt == 2
                @warn "Optimization failed after 2 attempts for floors $floors"
                objective_val = 0.0
            end

        catch e
            @warn "Error in optimization attempt $attempt for floors $floors: $e"
            if attempt == 2
                objective_val = 0.0
            end
        end
    end

    return ps_opt, np_opt, objective_val
end


# ============================================================================
# SHADOW CONSTRAINT PROCESSING FUNCTIONS
# ============================================================================
function process_shadow_direction(shadow_poly, constraint_matrix, constraint_vector, edges, direction_key)
    # Helper function to process a single shadow direction and extract constraint data.

    area = polyShape.polyArea(shadow_poly)
    is_active = area >= EPS_AREA
    
    constraint_edges = if is_active
        centroid = polyGdal.shapeCentroid(shadow_poly)
        constraint_values = vec(constraint_matrix * centroid.Vertices')
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

# ============================================================================
# SHADOW-CONSTRAINED OPTIMIZATION ENGINE
# ============================================================================
function optimize_with_shadow_constraints(vec_psVolConSombra, vec_altVolConSombra, shadow_data, floors,
                                        dict_arquitectura, dict_geom, max_ocupacion_suelo, max_losa_snt, ps_areaEdif)
    # Performs iterative optimization considering shadow constraints.
    
    # Initialize deltas
    delta_p = shadow_data["flag_p"] ? -1.0 : 1000.0
    delta_o = shadow_data["flag_o"] ? -1.0 : 1000.0  
    delta_s = shadow_data["flag_s"] ? -1.0 : 1000.0
    
    # Work with copies to avoid modifying originals - performance optimization
    vec_psVolConSombra_work = copy(vec_psVolConSombra)  # Shallow copy first
    ps_areaEdif_work = deepcopy(ps_areaEdif)  # Only deep copy when needed
    
    best_result = Dict{String, Any}(
        "objective_val" => 0.0,
        "ps_stack" => [PolyShape([], 1) for _ in 1:dict_arquitectura["arq_K"]],
        "np_stack" => zeros(Int, dict_arquitectura["arq_K"])
    )
    
    iter = 0
    while iter < MAX_ITER && min(delta_p, delta_o, delta_s) < 0
        iter += 1
        
        # Optimize volumes for K stacks
        ps_stack, np_stack, objective_val = quad_opti_vol(
            vec_psVolConSombra_work, vec_altVolConSombra, floors, dict_arquitectura["arq_alturaPiso"],
            max_ocupacion_suelo, max_losa_snt, dict_arquitectura["arq_K"]
        )
        
        # Calculate actual shadows
        vec_alt_acum = cumsum(np_stack) .* dict_arquitectura["arq_alturaPiso"]
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
    
    for i in eachindex(vec_altVolConSombra)
        alt = vec_altVolConSombra[i]
        offset_poly = polyClipper.polyOffset(ps_predio, -alt / rasante_sombra)
        vec_psVolConSombra[i] = polyShape.polyIntersection(offset_poly, ps_areaEdif)
    end
    
    return vec_altVolConSombra, vec_psVolConSombra
end

# ============================================================================
# FLOOR COMBINATION GENERATION
# ============================================================================
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

# ============================================================================
# MAIN VOLUME OPTIMIZATION FUNCTION
# ============================================================================
function opti_edificio_vol(dict_geom, dict_arquitectura, dict_requerimientos, vec_pisos, max_ocupacion_suelo, max_losa_snt)

    # ============================================================================
    # 1. PARAMETER INITIALIZATION
    # ============================================================================
    ps_predio = dict_geom["ps_combi"]
    ps_bruto = dict_geom["ps_bruto"]
    alturaPiso = dict_arquitectura["arq_alturaPiso"]
    K = dict_arquitectura["arq_K"]
    flag_sombra = dict_arquitectura["arq_flag_sombra"]
    alturaMax = dict_requerimientos["norm_altura_max"]
    rasante = tan(dict_requerimientos["norm_rasante"] * π / 180)
    rasante_sombra = dict_requerimientos["norm_rasante_sombra"]
    
    min_pisos = minimum(vec_pisos)
    max_pisos = maximum(vec_pisos)

    # ============================================================================
    # 2. SOLUTION TRACKING INITIALIZATION
    # ============================================================================
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

    # ============================================================================
    # 3. FLOOR COMBINATION GENERATION
    # ============================================================================
    vec_stacks = generate_floor_combinations(min_pisos, max_pisos, K)
    
    # ============================================================================
    # 4. PERFORMANCE OPTIMIZATION CACHING
    # ============================================================================
    altura_ant = -1
    ps_areaEdif = PolyShape([], 0)
    vec_altVolteor, vec_psVolteor = (Float64[], PolyShape[])
    vec_altVolConSombra, vec_psVolConSombra = (Float64[], PolyShape[])
    
    # ============================================================================
    # 5. MAIN OPTIMIZATION LOOP
    # ============================================================================
    for (iter_floors, floors) in enumerate(vec_stacks)
        n_pisos = sum(floors)
        altura = n_pisos * alturaPiso
        
        # Only recalculate when height changes (performance optimization)
        if altura != altura_ant
            altura_ant = altura
            
            # Calculate buildable area
            ps_areaEdif = calculate_buildable_area(dict_geom, dict_requerimientos, dict_arquitectura, altura, n_pisos)
                
            # Early termination if area too small
            if polyShape.polyArea(ps_areaEdif) < MIN_AREA_THRESHOLD
                continue
            end
            
            # Calculate theoretical volumes with performance optimization
            vec_altVolteor, vec_psVolteor = calculate_theoretical_volumes(ps_bruto, ps_areaEdif, alturaMax, rasante)
            
            if flag_sombra
                # Calculate shadow volumes and cache them
                vec_altVolConSombra, vec_psVolConSombra = calculate_shadow_volumes(ps_predio, ps_areaEdif, alturaMax, rasante_sombra)
            end

        end
        
        
        if flag_sombra
            shadow_data = setup_shadow_constraints(vec_psVolteor, vec_altVolteor, dict_geom, ps_areaEdif)
            
            # Only proceed if any shadow constraints are active
            if shadow_data["flag_p"] || shadow_data["flag_o"] || shadow_data["flag_s"]
                shadow_result = optimize_with_shadow_constraints(
                    vec_psVolConSombra, vec_altVolConSombra, shadow_data, floors,
                    dict_arquitectura, dict_geom, max_ocupacion_suelo, max_losa_snt, ps_areaEdif
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
                max_ocupacion_suelo, max_losa_snt, K
            )
            
            if objective_val > best_result["max_sol"]
                best_result["max_sol"] = objective_val
                best_result["ps_stack"] = ps_stack
                best_result["np_stack"] = np_stack
                best_result["vec_altVolteor"] = vec_altVolteor
                best_result["vec_psVolteor"] = vec_psVolteor
                
                # Calculate shadow volumes for output consistency using helper function
                vec_altVolConSombra, vec_psVolConSombra = calculate_shadow_volumes(ps_predio, ps_areaEdif, alturaMax, rasante_sombra)
                
                best_result["vec_altVolConSombra"] = vec_altVolConSombra
                best_result["vec_psVolConSombra"] = vec_psVolConSombra
                
            end
        end
        
        # Early termination if near optimal
        if best_result["max_sol"] >= 0.99 * max_losa_snt
            break
        end
    end

    # ============================================================================
    # 6. RESULTS COMPILATION AND RETURN
    # ============================================================================
    return Dict{String, Any}(
        "vec_ps_opt" => best_result["ps_stack"],
        "vec_np_opt" => best_result["np_stack"],
        "max_sol" => best_result["max_sol"],
        "vec_psVolteor" => best_result["vec_psVolteor"],
        "vec_altVolteor" => best_result["vec_altVolteor"],
        "vec_psVolConSombra" => best_result["vec_psVolConSombra"],
        "vec_altVolConSombra" => best_result["vec_altVolConSombra"],
        "ps_sombraEdif_p" => get(best_result, "ps_sombraEdif_p", PolyShape[]),
        "ps_sombraEdif_o" => get(best_result, "ps_sombraEdif_o", PolyShape[]),
        "ps_sombraEdif_s" => get(best_result, "ps_sombraEdif_s", PolyShape[]),
        "ps_sombraVolTeorico_p" => get(best_result, "ps_sombraVolTeorico_p", PolyShape[]),
        "ps_sombraVolTeorico_o" => get(best_result, "ps_sombraVolTeorico_o", PolyShape[]),
        "ps_sombraVolTeorico_s" => get(best_result, "ps_sombraVolTeorico_s", PolyShape[])
    )
end
