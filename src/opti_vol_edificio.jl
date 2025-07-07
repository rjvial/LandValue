function opti_vol_edificio(vec_psVolteor, vec_altVolteor, vec_pisos, alturaPiso, max_ocupacion_suelo, maxConstruccionSNT, K;
                             ancho_crujia_min = 0, ancho_crujia_max = 0)


    # Helper to generate all K-length floor combinations summing ≤ max_pisos_total
    # and enforce: if ni = 0 then all subsequent nj = 0
    function generate_floor_combinations(vec_pisos, max_pisos_total, K::Int)
        all_combos = Vector{Vector{Int}}()
        
        # Generate combinations for each target sum from 3 to max_pisos_total
        for target_sum in 3:max_pisos_total
            combos = Vector{Vector{Int}}()
            current = Int[]
            
            function rec_(sum_current, depth)
                if depth > K
                    # Only add combination if it sums to current target_sum
                    if sum_current == target_sum
                        push!(combos, copy(current))
                    end
                else
                    if depth == 1
                        # First stack must pick from vec_pisos
                        for n in vec_pisos
                            if n <= max_pisos_total
                                push!(current, n)
                                rec_(n, depth + 1)
                                pop!(current)
                            end
                        end
                    else
                        # If previous stack has 0 floors, force zeros for all remaining
                        if current[depth - 1] == 0
                            push!(current, 0)
                            rec_(sum_current, depth + 1)
                            pop!(current)
                        else
                            # Subsequent stacks can take 0 to remaining floors
                            max_available = max_pisos_total - sum_current
                            for n in 0:max_available
                                # Only continue if we don't exceed target_sum
                                if sum_current + n <= target_sum
                                    push!(current, n)
                                    rec_(sum_current + n, depth + 1)
                                    pop!(current)
                                end
                            end
                        end
                    end
                end
            end
            
            rec_(0, 1)
            append!(all_combos, combos)
        end
        
        return all_combos
    end

    # Orientation of the lot
    ps0 = vec_psVolteor[1]
    V0 = ps0.Vertices[1]
    flag_horizontal = abs(V0[2,1] - V0[1,1]) > abs(V0[2,2] - V0[1,2])

    vecLargoLados, _, _, _ = polyShape.extraeInfoPoly(ps0)
    max_lado = maximum(vecLargoLados)
    alt_max   = maximum(vec_altVolteor)
    max_pisos = maximum(vec_pisos)
    min_pisos = ancho_crujia_max > 0 ? min(max_pisos-2, Int(floor(maxConstruccionSNT / (max_lado * ancho_crujia_max)))) : max_pisos - 2


    combos    = generate_floor_combinations(vec_pisos[vec_pisos .>= min_pisos-1], max_pisos, K)

    sup_opt = 0.0
    ps_opt  = [PolyShape([],1) for _ in 1:K]
    np_opt  = zeros(Int, K)

    combos = combos[sum.(combos) .>= min_pisos]

    for floors in combos #reverse(combos) #
        if sum(floors) > max_pisos
            continue
        end

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

        # Ground constraints for stack 1
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
        # Buildable-area constraints per stack
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

        @objective(model, Max, sum(w[stack] * h[stack] * floors[stack] for stack in 1:K))
        optimize!(model)

        if termination_status(model) in (MOI.LOCALLY_SOLVED, MOI.OPTIMAL, MOI.ALMOST_LOCALLY_SOLVED, MOI.ALMOST_OPTIMAL)
            objective_val = objective_value(model)

            if objective_val > sup_opt
                sup_opt = objective_val
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
            end
        end
        # fig, ax, ax_mat = plotBaseEdificio3D(fpe, alturaPiso, ps_predio, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra, ps_publico, ps_calles, ps_opt, np_opt, vec_ps_subte, vec_np_subte, tipo_edificio)

        if sum(value(w[stack]) * value(h[stack]) * floors[stack] for stack in 1:K) >= .99 * maxConstruccionSNT
            # If we reach near the limit, stop further iterations
            break
        end

    end

    return ps_opt, np_opt
end
