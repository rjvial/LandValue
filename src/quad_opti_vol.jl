# Constants for better maintainability
const MAX_RETRY_ATTEMPTS = 2
const MIN_DIMENSION = 2.0
const QUARTER_SCALE = 0.25

"""
    validate_quad_inputs(vec_psVolteor, vec_altVolteor, floors, alturaPiso, max_ocupacion_suelo, max_losa_snt, K, ancho_crujia_min, ancho_crujia_max)

Validates input parameters for quadrilateral optimization.
"""
function validate_quad_inputs(vec_psVolteor, vec_altVolteor, floors, alturaPiso, max_ocupacion_suelo, max_losa_snt, K, ancho_crujia_min, ancho_crujia_max)
    length(vec_psVolteor) == length(vec_altVolteor) || throw(ArgumentError("Volume and altitude vectors must have same length"))
    length(floors) == K || throw(ArgumentError("Floors vector must have length K"))
    all(f -> f >= 0, floors) || throw(ArgumentError("All floor counts must be non-negative"))
    alturaPiso > 0 || throw(ArgumentError("Floor height must be positive"))
    max_ocupacion_suelo > 0 || throw(ArgumentError("Max ground occupation must be positive"))
    max_losa_snt > 0 || throw(ArgumentError("Max constructible area must be positive"))
    K > 0 || throw(ArgumentError("Number of stacks must be positive"))
    ancho_crujia_min >= 0 || throw(ArgumentError("Min crujia width must be non-negative"))
    ancho_crujia_max >= ancho_crujia_min || throw(ArgumentError("Max crujia width must be >= min width"))
end

"""
    calculate_initial_dimensions(ps0)

Calculates initial width and height from polygon shape.
"""
function calculate_initial_dimensions(ps0::PolyShape)
    if ps0.Vertices == []
        return 0.0, 0.0
    end
    
    vertices = ps0.Vertices[1]
    x_coords = vertices[:, 1]
    y_coords = vertices[:, 2]
    width = maximum(x_coords) - minimum(x_coords)
    height = maximum(y_coords) - minimum(y_coords)
    
    return width, height
end

"""
    create_optimization_model()

Creates and configures the Ipopt optimization model.
"""
function create_optimization_model()
    model = Model(optimizer_with_attributes(Ipopt.Optimizer, "sb" => "yes"))
    set_silent(model)
    return model
end

"""
    setup_model_variables!(model, K, width, height, attempt)

Sets up all model variables with appropriate bounds based on attempt number.
"""
function setup_model_variables!(model, K, width, height, attempt)
    # Global position and rotation
    @variable(model, x1)
    @variable(model, y1)
    @variable(model, c)
    @variable(model, s)
    @constraint(model, c^2 + s^2 == 1)
    
    # Footprint sizes with dynamic bounds
    if attempt == 1
        # First attempt: use dimensional constraints
        if width > height
            @variables(model, begin
                w[stack = 1:K] >= width * QUARTER_SCALE
                h[stack = 1:K] >= MIN_DIMENSION
            end)
        else
            @variables(model, begin
                w[stack = 1:K] >= MIN_DIMENSION
                h[stack = 1:K] >= height * QUARTER_SCALE
            end)
        end
    else
        # Retry attempt: relaxed bounds
        @variables(model, begin
            w[stack = 1:K] >= 0
            h[stack = 1:K] >= 0
        end)
    end
    
    # Stack offsets for stacks above ground
    if K > 1
        @variables(model, begin
            dx[stack = 2:K] >= 0
            dy[stack = 2:K] >= 0
        end)
    end
end

"""
    add_basic_constraints!(model, K, max_ocupacion_suelo)

Adds basic optimization constraints (ground occupation, nesting).
"""
function add_basic_constraints!(model, K, max_ocupacion_suelo)
    w = model[:w]
    h = model[:h]
    
    # Ground occupation constraint
    @constraint(model, w[1] * h[1] <= max_ocupacion_suelo)
    
    # Nesting constraints for upper stacks
    if K > 1
        dx = model[:dx]
        dy = model[:dy]
        for stack in 2:K
            @constraint(model, dx[stack] + w[stack] <= w[stack - 1])
            @constraint(model, dy[stack] + h[stack] <= h[stack - 1])
        end
    end
end

"""
    add_volume_constraints!(model, K, floors, alturaPiso, vec_psVolteor, vec_altVolteor)

Adds volume confinement constraints for each stack.
"""
function add_volume_constraints!(model, K, floors, alturaPiso, vec_psVolteor, vec_altVolteor)
    x1, y1, c, s = model[:x1], model[:y1], model[:c], model[:s]
    w, h = model[:w], model[:h]
    dx = K > 1 ? model[:dx] : nothing
    dy = K > 1 ? model[:dy] : nothing
    
    num_pisos_acum = 0
    
    for stack in 1:K
        n_f = floors[stack]
        num_pisos_acum += n_f
        altura_corte_stack = num_pisos_acum * alturaPiso
        
        # Generate cutting polygon and constraints
        psC = generaPoligonoCorte(altura_corte_stack, vec_psVolteor, vec_altVolteor)
        psC = polyGdal.shapeHull(psC)
        A, b = polyShape.poly2Constraints(psC)
        
        # Define stack corner offsets
        ox = stack > 1 ? dx[stack] : 0
        oy = stack > 1 ? dy[stack] : 0
        
        # Stack corners in local coordinates
        corners = [[ox, oy], [ox + w[stack], oy], [ox + w[stack], oy + h[stack]], [ox, oy + h[stack]]]
        
        # Apply constraints to all corners
        for corner in corners, row in axes(A, 1)
            xg = x1 + c * corner[1] - s * corner[2]
            yg = y1 + s * corner[1] + c * corner[2]
            @constraint(model, A[row, 1] * xg + A[row, 2] * yg <= b[row])
        end
    end
end

"""
    set_objective_and_constraints!(model, K, floors, max_losa_snt)

Sets the objective function and constructibility constraint.
"""
function set_objective_and_constraints!(model, K, floors, max_losa_snt)
    w, h = model[:w], model[:h]
    
    # Constructibility constraint
    @constraint(model, sum(w[stack] * h[stack] * floors[stack] for stack in 1:K) <= max_losa_snt)
    
    # Objective function: maximize total floor area
    @objective(model, Max, sum(w[stack] * h[stack] * floors[stack] for stack in 1:K))
end

"""
    extract_solution(model, K, floors)

Extracts the optimized solution from the model.
Returns (ps_opt, np_opt, objective_val).
"""
function extract_solution(model, K, floors)
    ps_opt = Vector{PolyShape}(undef, K)
    np_opt = Vector{Int}(undef, K)
    
    x1_val, y1_val = value(model[:x1]), value(model[:y1])
    c_val, s_val = value(model[:c]), value(model[:s])
    w_vals = value.(model[:w])
    h_vals = value.(model[:h])
    dx_vals = K > 1 ? value.(model[:dx]) : nothing
    dy_vals = K > 1 ? value.(model[:dy]) : nothing
    
    for stack in 1:K
        # Calculate stack offsets
        ox = stack > 1 ? dx_vals[stack] : 0.0
        oy = stack > 1 ? dy_vals[stack] : 0.0
        
        # Generate stack corners and transform to global coordinates
        coords = Float64[]
        local_corners = ((ox, oy), (ox + w_vals[stack], oy), 
                        (ox + w_vals[stack], oy + h_vals[stack]), (ox, oy + h_vals[stack]))
        
        for (px, py) in local_corners
            gx = x1_val + c_val * px - s_val * py
            gy = y1_val + s_val * px + c_val * py
            append!(coords, [gx, gy])
        end
        
        # Create polygon from coordinates
        mat = reshape(coords, 2, 4)'  # 4×2 matrix
        ps_opt[stack] = PolyShape([mat], 1)
        np_opt[stack] = floors[stack]
    end
    
    return ps_opt, np_opt, objective_value(model)
end

"""
    solve_optimization_problem(model)

Solves the optimization problem and returns success status.
"""
function solve_optimization_problem(model)
    try
        optimize!(model)
        status = termination_status(model)
        return status in (MOI.LOCALLY_SOLVED, MOI.OPTIMAL, MOI.ALMOST_LOCALLY_SOLVED, MOI.ALMOST_OPTIMAL)
    catch e
        @warn "Optimization failed: $e"
        return false
    end
end

function quad_opti_vol(vec_psVolteor, vec_altVolteor, floors, alturaPiso, max_ocupacion_suelo, max_losa_snt, K, ancho_crujia_min, ancho_crujia_max)
    # Input validation
    validate_quad_inputs(vec_psVolteor, vec_altVolteor, floors, alturaPiso, max_ocupacion_suelo, max_losa_snt, K, ancho_crujia_min, ancho_crujia_max)
    
    # Get initial solution and dimensions
    x1_ini, y1_ini, c_ini, s_ini, w_ini, h_ini, ps0 = quad_opti_sol_ini(vec_psVolteor, ancho_crujia_max)
    width, height = calculate_initial_dimensions(ps0)
    
    # Initialize result variables
    ps_opt = [PolyShape([], 1) for _ in 1:K]
    np_opt = zeros(Int, K)
    objective_val = 0.0
    
    # Optimization retry loop
    for attempt in 1:MAX_RETRY_ATTEMPTS
        try
            # Create and setup model
            model = create_optimization_model()
            setup_model_variables!(model, K, width, height, attempt)
            add_basic_constraints!(model, K, max_ocupacion_suelo)
            add_volume_constraints!(model, K, floors, alturaPiso, vec_psVolteor, vec_altVolteor)
            set_objective_and_constraints!(model, K, floors, max_losa_snt)
            
            # Solve optimization problem
            if solve_optimization_problem(model)
                ps_opt, np_opt, objective_val = extract_solution(model, K, floors)
                break  # Success - exit retry loop
            elseif attempt == MAX_RETRY_ATTEMPTS
                @warn "Optimization failed after $MAX_RETRY_ATTEMPTS attempts"
                objective_val = 0.0
            end
        catch e
            @warn "Error in optimization attempt $attempt: $e"
            if attempt == MAX_RETRY_ATTEMPTS
                objective_val = 0.0
            end
        end
    end


    return ps_opt, np_opt, objective_val
end
