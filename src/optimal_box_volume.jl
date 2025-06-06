function optimal_box_volume(vec_psVolteor, vec_altVolteor, vec_pisos, alt_piso)

    alt_max = maximum(vec_altVolteor)

    sup_opt = 0.0
    ps_opt = PolyShape([],1)
    np_opt = 0
    for np in vec_pisos

        alt = min(np * alt_piso, alt_max)
        psCorte = generaPoligonoCorte(alt, vec_psVolteor, vec_altVolteor)
        
        A, b = polyShape.poly2Constraints(psCorte) 

        model = Model(Ipopt.Optimizer)
        set_silent(model)

        # Lower-left corner
        @variable(model, x0)
        @variable(model, y0)

        # Rectangle dimensions
        @variable(model, w >= 0)
        @variable(model, h >= 0)

        # Rotation matrix elements
        @variable(model, c)  # cos(θ)
        @variable(model, s)  # sin(θ)

        # Ensure R is a rotation matrix
        @constraint(model, c^2 + s^2 == 1)

        # Local rectangle corners: relative to (x0, y0)
        local_corners = [[0, 0], [w, 0], [w, h], [0, h]]

        m = size(A, 1)

        for corner in local_corners
            # Apply rotation and translation
            x_rot = x0 + c * corner[1] - s * corner[2]
            y_rot = y0 + s * corner[1] + c * corner[2]

            # All polygon constraints must be satisfied
            for i in 1:m
                @constraint(model, A[i,1] * x_rot + A[i,2] * y_rot <= b[i])
            end
        end

        # Maximize area = w * h
        @objective(model, Max, w * h)

        optimize!(model)

        if termination_status(model) in [MOI.LOCALLY_SOLVED, MOI.OPTIMAL]
            x0_opt_np = value(x0)
            y0_opt_np = value(y0)
            w_opt_np = value(w)
            h_opt_np = value(h)
            c_opt_np = value(c)
            s_opt_np = value(s)
            θ_np = atan(s_opt_np, c_opt_np)

            # Compute global coordinates of rectangle vertices
            local_corners = [[0, 0], [w_opt_np, 0], [w_opt_np, h_opt_np], [0, h_opt_np]]
            V_opt_np = [0 0]
            for corner in local_corners
                x = x0_opt_np + c_opt_np * corner[1] - s_opt_np * corner[2]
                y = y0_opt_np + s_opt_np * corner[1] + c_opt_np * corner[2]
                V_opt_np = vcat(V_opt_np, [x y])
            end
            V_opt_np = V_opt_np[2:end, :]  # Remove the initial zero row
        end
        ps_planta_np = PolyShape([V_opt_np], 1)
        sup_edif_np = polyShape.polyArea(ps_planta_np) * np

        print("Calculando caja óptima para $np pisos... $sup_edif_np m²\n")

        if sup_edif_np > sup_opt
            ps_opt = deepcopy(ps_planta_np)
            sup_opt = sup_edif_np
            np_opt = np
        end

    end

    return ps_opt, sup_opt, np_opt

end