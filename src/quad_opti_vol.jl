function quad_opti_vol(vec_psVolteor, vec_altVolteor, floors, alturaPiso, max_ocupacion_suelo, maxConstruccionSNT, K, ancho_crujia_min, ancho_crujia_max)

    # Orientación del predio
    ps0 = vec_psVolteor[1]
    V0 = ps0.Vertices[1]
    flag_horizontal = abs(V0[2,1] - V0[1,1]) > abs(V0[2,2] - V0[1,2])

    ps_opt  = [PolyShape([],1) for _ in 1:K]
    np_opt  = zeros(Int, K)

    model = Model(optimizer_with_attributes(Ipopt.Optimizer, "sb" => "yes"))
    set_silent(model)

    # Global position and rotation
    @variable(model, x1)
    @variable(model, y1)
    @variable(model, c)
    @variable(model, s)
    @constraint(model, c^2 + s^2 == 1)

    # Footprint sizes
    @variables(model, begin
        w[stack = 1:K] >= 0
        h[stack = 1:K] >= 0
    end)

    # Offsets for stacks above ground
    if K > 1
        @variables(model, begin
            dx[stack = 2:K] >= 0
            dy[stack = 2:K] >= 0
        end)
    end

    # Restricciones de ocupación de suelo y ancho crujía
    @constraint(model, w[1] * h[1] <= max_ocupacion_suelo)
    if ancho_crujia_min >= 1
        if flag_horizontal
            @constraint(model, h[1] >= ancho_crujia_min)
            @constraint(model, h[1] <= ancho_crujia_max)
        else
            @constraint(model, w[1] >= ancho_crujia_min)
            @constraint(model, w[1] <= ancho_crujia_max)
        end
    end

    # Nesting constraints for above stacks
    for stack in 2:K
        @constraint(model, dx[stack] + w[stack] <= w[stack - 1])
        @constraint(model, dy[stack] + h[stack] <= h[stack - 1])
    end

    num_pisos_acum = 0
    # Restricciones de confinamiento al volúmen teórico
    for stack in 1:K
        n_f = floors[stack]
        num_pisos_acum += n_f
        altura_corte_stack = num_pisos_acum * alturaPiso #min(num_pisos_acum * alturaPiso, alt_max)
        psC = generaPoligonoCorte(altura_corte_stack, vec_psVolteor, vec_altVolteor)
        A, b = polyShape.poly2Constraints(psC)

        # Define local rectangle corners
        ox = stack > 1 ? dx[stack] : 0
        oy = stack > 1 ? dy[stack] : 0
        stack_corners = [[ox, oy], [ox + w[stack], oy], [ox + w[stack], oy + h[stack]], [ox, oy + h[stack]]]

        for corner in stack_corners, row in eachindex(A[:,1])
            xg = x1 + c * corner[1] - s * corner[2]
            yg = y1 + s * corner[1] + c * corner[2]
            @constraint(model, A[row,1] * xg + A[row,2] * yg <= b[row])
        end
    end

    # Restriccion de constructibilidad
    @constraint(model, sum(w[stack] * h[stack] * floors[stack] for stack in 1:K) <= maxConstruccionSNT)

    # Función Objetivo
    @objective(model, Max, sum(w[stack] * h[stack] * floors[stack] for stack in 1:K))
    optimize!(model)

    if termination_status(model) in (MOI.LOCALLY_SOLVED, MOI.OPTIMAL, MOI.ALMOST_LOCALLY_SOLVED, MOI.ALMOST_OPTIMAL)
        objective_val = objective_value(model)

        for stack in 1:K
            ox = stack > 1 ? value(dx[stack]) : 0
            oy = stack > 1 ? value(dy[stack]) : 0
            coords = Float64[]
            for (px, py) in ((ox, oy), (ox + value(w[stack]), oy),
                                (ox + value(w[stack]), oy + value(h[stack])), (ox, oy + value(h[stack])))
                gx = value(x1) + value(c) * px - value(s) * py
                gy = value(y1) + value(s) * px + value(c) * py
                append!(coords, [gx, gy])
            end
            mat = reshape(coords, 2, 4)'  # 4×2 matrix
            ps_opt[stack] = PolyShape([mat], 1)
            np_opt[stack] = floors[stack]
        end
    else
        objective_val = 0.0
    end


    return ps_opt, np_opt, objective_val
end
