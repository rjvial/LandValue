function quad_opti_vol(vec_psVolteor, vec_altVolteor, floors, alturaPiso, max_ocupacion_suelo, max_losa_snt, K, ancho_crujia_min, ancho_crujia_max)

    # Get initial solution
    x1_ini, y1_ini, c_ini, s_ini, w_ini, h_ini, ps0 = quad_opti_sol_ini(vec_psVolteor, ancho_crujia_max, floors)

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