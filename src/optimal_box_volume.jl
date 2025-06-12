function optimal_box_volume(
    vec_psVolteor, vec_altVolteor, vec_pisos,
    alt_piso, max_ocupacion_suelo, display::Bool = true
)

    alt_max = maximum(vec_altVolteor)
    max_pisos = maximum(vec_pisos)

    sup_opt = 0.0
    ps1_opt = PolyShape([], 1)
    ps2_opt = PolyShape([], 1)
    np1_opt = 0
    np2_opt = 0
    h1_opt = 0.0
    w1_opt = 0.0
    h2_opt = 0.0
    w2_opt = 0.0
    x1_opt = 0.0
    y1_opt = 0.0
    dx2_opt = 0.0
    dy2_opt = 0.0
    theta_opt = 0.0

    for np in vec_pisos

        np1 = np
        np2 = max_pisos - np1

        model = Model(Ipopt.Optimizer)
        set_silent(model)

        @variable(model, x1)
        @variable(model, y1)
        @variable(model, dx2 >= 0)
        @variable(model, dy2 >= 0)

        @variable(model, w1 >= 0)
        @variable(model, h1 >= 0)
        @variable(model, w2 >= 0)
        @variable(model, h2 >= 0)
        @variable(model, c)
        @variable(model, s)

        @constraint(model, c^2 + s^2 == 1)
        @constraint(model, dx2 + w2 <= w1)
        @constraint(model, dy2 + h2 <= h1)
        @constraint(model, w1 * h1 <= max_ocupacion_suelo)

        alt1 = min(np1 * alt_piso, alt_max)
        psCorte1 = generaPoligonoCorte(alt1, vec_psVolteor, vec_altVolteor)
        A1, b1 = polyShape.poly2Constraints(psCorte1)

        local_corners1 = [[0, 0], [w1, 0], [w1, h1], [0, h1]]
        m1 = size(A1, 1)
        for corner in local_corners1
            x1_corner = x1 + (c * corner[1] - s * corner[2])
            y1_corner = y1 + (s * corner[1] + c * corner[2])
            for i in 1:m1
                @constraint(model, A1[i,1] * x1_corner + A1[i,2] * y1_corner <= b1[i])
            end
        end

        alt2 = min((np1 + np2) * alt_piso, alt_max)
        psCorte2 = generaPoligonoCorte(alt2, vec_psVolteor, vec_altVolteor)
        A2, b2 = polyShape.poly2Constraints(psCorte2)

        local_corners2 = [[dx2, dy2], [dx2+w2, dy2], [dx2+w2, dy2+h2], [dx2, dy2+h2]]
        m2 = size(A2, 1)
        for corner in local_corners2
            x2_corner = x1 + (c * corner[1] - s * corner[2])
            y2_corner = y1 + (s * corner[1] + c * corner[2])
            for i in 1:m2
                @constraint(model, A2[i,1] * x2_corner + A2[i,2] * y2_corner <= b2[i])
            end
        end

        @objective(model, Max, w1 * h1 * np1 + w2 * h2 * np2)

        optimize!(model)

        if termination_status(model) in [MOI.LOCALLY_SOLVED, MOI.OPTIMAL]

            local_corners = [[0, 0], [value(w1), 0], [value(w1), value(h1)], [0, value(h1)]]
            V1_opt_np = [0 0]
            for corner in local_corners
                x1_rot_opt = value(x1) + value(c) * corner[1] - value(s) * corner[2]
                y1_rot_opt = value(y1) + value(s) * corner[1] + value(c) * corner[2]
                V1_opt_np = vcat(V1_opt_np, [x1_rot_opt y1_rot_opt])
            end
            V1_opt_np = V1_opt_np[2:end, :]
            ps_planta1_np = PolyShape([V1_opt_np], 1)

            local_corners = [[value(dx2), value(dy2)], [value(dx2)+value(w2), value(dy2)],
                             [value(dx2)+value(w2), value(dy2)+value(h2)], [value(dx2), value(dy2)+value(h2)]]
            V2_opt_np = [0 0]
            for corner in local_corners
                x2_rot_opt = value(x1) + value(c) * corner[1] - value(s) * corner[2]
                y2_rot_opt = value(y1) + value(s) * corner[1] + value(c) * corner[2]
                V2_opt_np = vcat(V2_opt_np, [x2_rot_opt y2_rot_opt])
            end
            V2_opt_np = V2_opt_np[2:end, :]
            ps_planta2_np = PolyShape([V2_opt_np], 1)

            sup_edif_np = polyShape.polyArea(ps_planta1_np) * np1 + polyShape.polyArea(ps_planta2_np) * np2

            if display
                println("Calculando caja óptima para $np pisos... $sup_edif_np m²")
            end

            if sup_edif_np > sup_opt
                ps1_opt = deepcopy(ps_planta1_np)
                ps2_opt = deepcopy(ps_planta2_np)
                sup_opt = sup_edif_np
                np1_opt = np1
                np2_opt = np2
                h1_opt = value(h1)
                w1_opt = value(w1)
                h2_opt = value(h2)
                w2_opt = value(w2)
                x1_opt = value(x1)
                y1_opt = value(y1)
                dx2_opt = value(dx2)
                dy2_opt = value(dy2)
                theta_opt = value(acos(value(c)) * 180 / pi)
            end
        end
    end

    if display
        println("h1_opt: ", h1_opt, " m, w1_opt: ", w1_opt, " m, h2_opt: ", h2_opt, " m, w2_opt: ", w2_opt, " m")
        println("x1_opt: ", x1_opt, " m, y1_opt: ", y1_opt, " m, dx2_opt: ", dx2_opt, " m, dy2_opt: ", dy2_opt, " m")
        println("theta: ", theta_opt)
    end

    return ps1_opt, ps2_opt, np1_opt, np2_opt
end
