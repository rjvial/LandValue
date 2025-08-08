# Constants for better maintainability
const DEFAULT_ANCHO_CRUJIA_MIN = 2
const DIMENSION_BUFFER = 5
const COORDINATE_TOLERANCE = 1e-6

"""
    OrientationConfig

Configuration for different rectangle orientations.
"""
struct OrientationConfig
    name::String
    width_constraint::Function  # Function that takes (width, height) -> min_width
    height_constraint::Function # Function that takes (width, height) -> min_height
end

"""
    validate_quad_sol_ini_inputs(vec_psVolteor, ancho_crujia_max)

Validates input parameters for initial quadrilateral solution.
"""
function validate_quad_sol_ini_inputs(vec_psVolteor, ancho_crujia_max)
    isempty(vec_psVolteor) && throw(ArgumentError("Volume vector cannot be empty"))
    ancho_crujia_max > 0 || throw(ArgumentError("Max crujia width must be positive"))
    
    # Validate first polygon
    ps0 = vec_psVolteor[1]
    isempty(ps0.Vertices) && throw(ArgumentError("First polygon has no vertices"))
    
    vertices = ps0.Vertices[1]
    size(vertices, 2) >= 2 || throw(ArgumentError("Vertices must have at least 2 dimensions"))
    size(vertices, 1) >= 3 || throw(ArgumentError("Polygon must have at least 3 vertices"))
end

"""
    calculate_polygon_dimensions(ps0)

Calculates width and height of polygon bounding box.
"""
function calculate_polygon_dimensions(ps0::PolyShape)
    if isempty(ps0.Vertices)
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
    create_orientation_configs(width, height)

Creates configuration for different rectangle orientations.
"""
function create_orientation_configs(width::Real, height::Real)
    return [
        OrientationConfig(
            "horizontal",
            (w, h) -> max(width - DIMENSION_BUFFER, DEFAULT_ANCHO_CRUJIA_MIN),
            (w, h) -> DEFAULT_ANCHO_CRUJIA_MIN
        ),
        OrientationConfig(
            "vertical", 
            (w, h) -> DEFAULT_ANCHO_CRUJIA_MIN,
            (w, h) -> max(height - DIMENSION_BUFFER, DEFAULT_ANCHO_CRUJIA_MIN)
        )
    ]
end

"""
    create_optimization_model_ini()

Creates and configures the initial optimization model.
"""
function create_optimization_model_ini()
    model = Model(optimizer_with_attributes(Ipopt.Optimizer, "sb" => "yes"))
    set_silent(model)
    return model
end

"""
    setup_model_variables_ini!(model, config, width, height)

Sets up model variables based on orientation configuration.
"""
function setup_model_variables_ini!(model, config::OrientationConfig, width::Real, height::Real)
    # Global position and rotation
    @variable(model, x1)
    @variable(model, y1)
    @variable(model, 0 <= c <= 1)
    @variable(model, -1 <= s <= 1)
    @constraint(model, c^2 + s^2 == 1)
    
    # Footprint sizes based on orientation
    min_width = config.width_constraint(width, height)
    min_height = config.height_constraint(width, height)
    
    @variable(model, w >= min_width)
    @variable(model, h >= min_height)
end

"""
    add_polygon_constraints_ini!(model, ps_constraint)

Adds polygon confinement constraints to the model.
"""
function add_polygon_constraints_ini!(model, ps_constraint::PolyShape)
    try
        # Get constraint matrix from polygon
        psC_hull = polyGdal.shapeHull(ps_constraint)
        A, b = polyShape.poly2Constraints(psC_hull)
        
        # Get model variables
        x1, y1, c, s = model[:x1], model[:y1], model[:c], model[:s]
        w, h = model[:w], model[:h]
        
        # Define rectangle corners in local coordinates
        corners = [[0, 0], [w, 0], [w, h], [0, h]]
        
        # Apply constraints to all corners
        for corner in corners, row in axes(A, 1)
            xg = x1 + c * corner[1] - s * corner[2]
            yg = y1 + s * corner[1] + c * corner[2]
            @constraint(model, A[row, 1] * xg + A[row, 2] * yg <= b[row])
        end
        
    catch e
        @warn "Failed to add polygon constraints: $e"
        throw(ArgumentError("Invalid polygon constraint: cannot generate constraint matrix"))
    end
end

"""
    set_objective_ini!(model)

Sets the objective function for initial optimization.
"""
function set_objective_ini!(model)
    w, h = model[:w], model[:h]
    @objective(model, Max, w * h)
end

"""
    solve_orientation_problem(model)

Solves the optimization problem and returns success status and objective value.
"""
function solve_orientation_problem(model)
    try
        optimize!(model)
        status = termination_status(model)
        
        if status in (MOI.LOCALLY_SOLVED, MOI.OPTIMAL, MOI.ALMOST_LOCALLY_SOLVED, MOI.ALMOST_OPTIMAL)
            return true, objective_value(model)
        else
            @warn "Optimization failed with status: $status"
            return false, 0.0
        end
    catch e
        @warn "Optimization error: $e"
        return false, 0.0
    end
end

"""
    extract_solution_ini(model)

Extracts the optimized solution from the model.
Returns (x1, y1, c, s, w, h, ps_opt).
"""
function extract_solution_ini(model)
    try
        # Extract variable values
        x1_val = value(model[:x1])
        y1_val = value(model[:y1])
        c_val = value(model[:c])
        s_val = value(model[:s])
        w_val = value(model[:w])
        h_val = value(model[:h])
        
        # Validate solution
        if w_val <= 0 || h_val <= 0
            @warn "Invalid solution: negative dimensions w=$w_val, h=$h_val"
            return 0, 0, 0, 0, 0, 0, PolyShape([], 1)
        end
        
        # Generate polygon from solution
        coords = Float64[]
        corners = [(0, 0), (w_val, 0), (w_val, h_val), (0, h_val)]
        
        for (px, py) in corners
            gx = x1_val + c_val * px - s_val * py
            gy = y1_val + s_val * px + c_val * py
            append!(coords, [gx, gy])
        end
        
        # Create polygon
        mat = reshape(coords, 2, 4)'  # 4×2 matrix
        ps_opt = PolyShape([mat], 1)
        
        return x1_val, y1_val, c_val, s_val, w_val, h_val, ps_opt
        
    catch e
        @warn "Failed to extract solution: $e"
        return 0, 0, 0, 0, 0, 0, PolyShape([], 1)
    end
end

"""
    optimize_single_orientation(config, ps_constraint, width, height)

Optimizes a single orientation and returns solution data.
"""
function optimize_single_orientation(config::OrientationConfig, ps_constraint::PolyShape, width::Real, height::Real)
    try
        # Create and setup model
        model = create_optimization_model_ini()
        setup_model_variables_ini!(model, config, width, height)
        add_polygon_constraints_ini!(model, ps_constraint)
        set_objective_ini!(model)
        
        # Solve optimization
        success, objective_val = solve_orientation_problem(model)
        
        if success
            solution = extract_solution_ini(model)
            return true, objective_val, solution
        else
            return false, 0.0, (0, 0, 0, 0, 0, 0, PolyShape([], 1))
        end
        
    catch e
        @warn "Error optimizing $(config.name) orientation: $e"
        return false, 0.0, (0, 0, 0, 0, 0, 0, PolyShape([], 1))
    end
end

function quad_opti_sol_ini(vec_psVolteor, ancho_crujia_max)
    # Input validation
    validate_quad_sol_ini_inputs(vec_psVolteor, ancho_crujia_max)
    
    # Get polygon dimensions
    ps0 = vec_psVolteor[1]
    width, height = calculate_polygon_dimensions(ps0)
    
    if width <= 0 || height <= 0
        @warn "Invalid polygon dimensions: width=$width, height=$height"
        return 0, 0, 0, 0, 0, 0, PolyShape([], 1)
    end
    
    # Create orientation configurations
    orientation_configs = create_orientation_configs(width, height)
    
    # Initialize best solution tracking
    best_objective = 0.0
    best_solution = (0, 0, 0, 0, 0, 0, PolyShape([], 1))
    
    # Try each orientation
    for config in orientation_configs
        success, objective_val, solution = optimize_single_orientation(config, ps0, width, height)
        
        if success && objective_val > best_objective
            best_objective = objective_val
            best_solution = solution
            @debug "Found better solution with $(config.name) orientation: objective=$objective_val"
        end
    end
    
    # Validate final solution
    if best_objective <= COORDINATE_TOLERANCE
        @warn "No valid solution found, returning empty result"
        return 0, 0, 0, 0, 0, 0, PolyShape([], 1)
    end
    
    return best_solution
end
