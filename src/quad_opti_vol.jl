function quad_opti_vol(vec_psVolteor, vec_altVolteor, floors, alturaPiso, max_ocupacion_suelo, max_losa_snt, K, ancho_crujia_min, ancho_crujia_max)


    x1_ini, y1_ini, c_ini, s_ini, w_ini, h_ini, ps0 = quad_opti_sol_ini(vec_psVolteor, ancho_crujia_max)

    if ps0.Vertices == []
        width = 0.0
        height = 0.0
    else
        vertices = ps0.Vertices[1]
        x_coords = vertices[:, 1]
        y_coords = vertices[:, 2]
        width = maximum(x_coords) - minimum(x_coords)
        height = maximum(y_coords) - minimum(y_coords)

    end



    ps_opt  = [PolyShape([],1) for _ in 1:K]
    np_opt  = zeros(Int, K)
    objective_val = 0

    flag_continue = true
    cont_continue = 0
    while flag_continue

        model = Model(optimizer_with_attributes(Ipopt.Optimizer, "sb" => "yes"))
        set_silent(model)

        # Global position and rotation
        @variable(model, x1)
        @variable(model, y1)
        @variable(model, c)
        @variable(model, s)

        @constraint(model, c^2 + s^2 == 1)

        # Footprint sizes
        if cont_continue == 1
            @variables(model, begin
                w[stack = 1:K] >= 0
                h[stack = 1:K] >= 0
            end)
        else 
            if width > height
                @variables(model, begin
                    w[stack = 1:K] >= width/4
                    h[stack = 1:K] >= 2
                end)
            else
                @variables(model, begin
                    w[stack = 1:K] >= 2
                    h[stack = 1:K] >= height/4
                end)
            end
        end


        # Offsets for stacks above ground
        if K > 1
            @variables(model, begin
                dx[stack = 2:K] >= 0
                dy[stack = 2:K] >= 0
            end)
        end

        # Restricciones de ocupación de suelo y ancho crujía
        @constraint(model, w[1] * h[1] <= max_ocupacion_suelo)

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
            psC = polyShape.shapeHull(psC)
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
        @constraint(model, sum(w[stack] * h[stack] * floors[stack] for stack in 1:K) <= max_losa_snt)

        # Función Objetivo
        @objective(model, Max, sum(w[stack] * h[stack] * floors[stack] for stack in 1:K))
        optimize!(model)

        cont_continue += 1


        if termination_status(model) in (MOI.LOCALLY_SOLVED, MOI.OPTIMAL, MOI.ALMOST_LOCALLY_SOLVED, MOI.ALMOST_OPTIMAL)
            objective_val = objective_value(model)
            flag_continue = false

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
        if cont_continue == 2
            flag_continue = false
        end
    
    end


    return ps_opt, np_opt, objective_val
end
