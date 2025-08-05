function quad_opti_sol_ini(vec_psVolteor, ancho_crujia_max)

    ps0 = vec_psVolteor[1]
    vertices = ps0.Vertices[1]

    x_coords = vertices[:, 1]
    y_coords = vertices[:, 2]
    
    width = maximum(x_coords) - minimum(x_coords)
    height = maximum(y_coords) - minimum(y_coords)
    
    ps_opt  = PolyShape([],1)
    ancho_crujia_min = 2
    objective_val_opt = 0.0
    x1_opt, y1_opt, c_opt, s_opt, w_opt, h_opt = 0, 0, 0, 0, 0, 0
    for i = 1:2
        model = Model(optimizer_with_attributes(Ipopt.Optimizer, "sb" => "yes"))
        set_silent(model)

        # Global position and rotation
        @variable(model, x1)
        @variable(model, y1)
        @variable(model, 0 <= c <= 1)
        @variable(model, -1 <= s <= 1)

        @constraint(model, c^2 + s^2 == 1)

        # Footprint sizes
        if i == 1
            @variables(model, begin
                w >= width - 5
                h >= ancho_crujia_min
            end)
              # @constraint(model, w >= 1.4 * h)

        elseif i == 2
            @variables(model, begin
                w >= ancho_crujia_min
                h >= height - 5
            end)
            # @constraint(model, h >= 1.4 * w)
        end

        psC = vec_psVolteor[1]
        psC = polyShape.shapeHull(psC)
        A, b = polyShape.poly2Constraints(psC)

        # Define local rectangle corners
        corners = [[0, 0], [w, 0], [w, h], [0, h]]

        for corner in corners, row in eachindex(A[:,1])
            xg = x1 + c * corner[1] - s * corner[2]
            yg = y1 + s * corner[1] + c * corner[2]
            @constraint(model, A[row,1] * xg + A[row,2] * yg <= b[row])
        end

        # Función Objetivo
        @objective(model, Max, sum(w * h))
        optimize!(model)

        if termination_status(model) in (MOI.LOCALLY_SOLVED, MOI.OPTIMAL, MOI.ALMOST_LOCALLY_SOLVED, MOI.ALMOST_OPTIMAL)
            objective_val = objective_value(model)
            if objective_val > objective_val_opt
                objective_val_opt = objective_val

                x1_opt, y1_opt, c_opt, s_opt, w_opt, h_opt = value(x1), value(y1), value(c), value(s), value(w), value(h)

                coords = Float64[]
                for (px, py) in ((0, 0), (value(w), 0), (value(w), value(h)), (0, value(h)))
                    gx = value(x1) + value(c) * px - value(s) * py
                    gy = value(y1) + value(s) * px + value(c) * py
                    append!(coords, [gx, gy])
                end
                mat = reshape(coords, 2, 4)'  # 4×2 matrix
                ps_opt = PolyShape([mat], 1)

            end
        end
    end


    return x1_opt, y1_opt, c_opt, s_opt, w_opt, h_opt, ps_opt
end
