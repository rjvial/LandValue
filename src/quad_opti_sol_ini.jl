function quad_opti_sol_ini(vec_psVolteor, ancho_crujia_max, floors)
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