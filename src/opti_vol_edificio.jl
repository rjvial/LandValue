function opti_vol_edificio(vec_psVolteor, vec_altVolteor, vec_pisos, alturaPiso, max_ocupacion_suelo, maxConstruccionSNT, K;
                             ancho_crujia_edificio = 0, flag_reverse = false)


    # Helper to generate all K-length floor combinations summing ≤ max_pisos_total
    # and enforce: if ni = 0 then all subsequent nj = 0
    function generate_floor_combinations(vec_pisos, max_pisos_total, K::Int)
        combos = Vector{Vector{Int}}()
        current = Int[]
        function rec_(sum_current, depth)
            if depth > K
                push!(combos, copy(current))
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
                        for n in 0:(max_pisos_total - sum_current)
                            push!(current, n)
                            rec_(sum_current + n, depth + 1)
                            pop!(current)
                        end
                    end
                end
            end
        end
        rec_(0, 1)
        return combos
    end

    # Orientation of the lot
    ps0 = vec_psVolteor[1]
    V0 = ps0.Vertices[1]
    flag_horizontal = abs(V0[2,1] - V0[1,1]) > abs(V0[2,2] - V0[1,2])

    vecLargoLados, _, _, _ = polyShape.extraeInfoPoly(ps0)
    max_lado = maximum(vecLargoLados)
    min_pisos = ancho_crujia_edificio > 0 ? Int(floor(maxConstruccionSNT / (max_lado * ancho_crujia_edificio))) : 1

    alt_max   = maximum(vec_altVolteor)
    max_pisos = maximum(vec_pisos)
    combos    = generate_floor_combinations(vec_pisos[vec_pisos .>= min_pisos-1], max_pisos, K)

    sup_opt = 0.0
    ps_opt  = [PolyShape([],1) for _ in 1:K]
    np_opt  = zeros(Int, K)

    if flag_reverse
        combos = reverse(combos)
    end

    for floors in combos
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
            w[i = 1:K] >= 0
            h[i = 1:K] >= 0
        end)

        # Offsets for stacks above ground
        if K > 1
            @variables(model, begin
                dx[i = 2:K] >= 0
                dy[i = 2:K] >= 0
            end)
        end

        # Ground constraints for stack 1
        @constraint(model, w[1] * h[1] <= max_ocupacion_suelo)
        if ancho_crujia_edificio >= 1
            if flag_horizontal
                @constraint(model, h[1] <= ancho_crujia_edificio)
            else
                @constraint(model, w[1] <= ancho_crujia_edificio)
            end
        end

        # Nesting constraints for above stacks
        for i in 2:K
            @constraint(model, dx[i] + w[i] <= w[i - 1])
            @constraint(model, dy[i] + h[i] <= h[i - 1])
        end

        total_floors_acc = 0
        # Buildable-area constraints per stack
        for i in 1:K
            n_f = floors[i]
            total_floors_acc += n_f
            height_cut = min(total_floors_acc * alturaPiso, alt_max)
            psC = generaPoligonoCorte(height_cut, vec_psVolteor, vec_altVolteor)
            A, b = polyShape.poly2Constraints(psC)

            # Define local rectangle corners
            ox = i > 1 ? dx[i] : 0
            oy = i > 1 ? dy[i] : 0
            locals = [[ox, oy], [ox + w[i], oy],
                      [ox + w[i], oy + h[i]], [ox, oy + h[i]]]

            for corner in locals, row in eachindex(A[:,1])
                xg = x1 + c * corner[1] - s * corner[2]
                yg = y1 + s * corner[1] + c * corner[2]
                @constraint(model, A[row,1] * xg + A[row,2] * yg <= b[row])
            end
        end

        # Restriccion de constructibilidad
        @constraint(model, sum(w[i] * h[i] * floors[i] for i in 1:K) <= maxConstruccionSNT)

        @objective(model, Max, sum(w[i] * h[i] * floors[i] for i in 1:K))
        optimize!(model)

        if termination_status(model) in (MOI.LOCALLY_SOLVED, MOI.OPTIMAL)
            objective_val = objective_value(model)
            if objective_val > sup_opt
                sup_opt = objective_val
                for i in 1:K
                    ox = i > 1 ? value(dx[i]) : 0
                    oy = i > 1 ? value(dy[i]) : 0
                    coords = Float64[]
                    for (px, py) in ((ox, oy), (ox + value(w[i]), oy),
                                      (ox + value(w[i]), oy + value(h[i])), (ox, oy + value(h[i])))
                        gx = value(x1) + value(c) * px - value(s) * py
                        gy = value(y1) + value(s) * px + value(c) * py
                        append!(coords, [gx, gy])
                    end
                    mat = reshape(coords, 2, 4)'  # 4×2 matrix
                    ps_opt[i] = PolyShape([mat], 1)
                    np_opt[i] = floors[i]
                end
            end
        end

        if sum(value(w[i]) * value(h[i]) * floors[i] for i in 1:K) >= .99 * maxConstruccionSNT
            # If we reach near the limit, stop further iterations
            break
        end

    end


    return ps_opt, np_opt
end
