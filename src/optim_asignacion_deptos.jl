using JuMP
using HiGHS

"""
    optim_asignacion_deptos(W, H, num_strips, set_i, set_w, vec_w, mat_h, vec_a, vec_pasillo_a, vec_t_w, vec_t_h, vec_t_a, mat_p, mat_pc, mat_pcc, min_deptos, max_deptos)

Optimiza la asignación de departamentos en strips horizontales para maximizar superficie total.

# Argumentos
- `W::Float64`: Ancho del edificio (m)
- `H::Float64`: Altura total del edificio (m)
- `num_strips::Int`: Número de strips horizontales
- `set_i::Vector{Int}`: Conjunto de índices de tipos de departamentos
- `set_w::Vector{Int}`: Conjunto de índices de alturas
- `vec_w`: Vector de anchos por tipo de departamento i
- `mat_h`: Matriz de alturas [i,h] por tipo de departamento e índice de altura
- `vec_a`: Vector de áreas por tipo i
- `vec_pasillo_a`: Vector de áreas de pasillo por tipo i
- `vec_t_w`: Vector de anchos de terraza por tipo i
- `vec_t_h`: Vector de alturas de terraza por tipo i
- `vec_t_a`: Vector de áreas de terraza por tipo i
- `mat_p, mat_pc, mat_pcc`: Matrices de perímetros [i,h] (regular, corner, corner2)
- `min_deptos::Int`: Número mínimo de departamentos
- `max_deptos::Int`: Número máximo de departamentos

# Tipos de departamentos
- `z`: Departamentos regulares
- `z_c`: Departamentos en esquina (corner) - siempre 2 por strip
- `z_cc`: Departamentos en esquina doble (corner2) - máximo 1 por strip

# Returns
- `Dict{String,Any}`: Diccionario con resultados de optimización
"""
function optim_asignacion_deptos(
    W::Float64,
    H::Float64,
    num_strips::Int,
    set_i::Vector{Int},
    set_w::Vector{Int},
    vec_w, mat_h, vec_a, vec_pasillo_a,
    vec_t_w, vec_t_h, vec_t_a,
    mat_p, mat_pc, mat_pcc,
    min_deptos::Int,
    max_deptos::Int)

    model = Model(HiGHS.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, 300.0)
    set_optimizer_attribute(model, "mip_rel_gap", 0.01)
    set_optimizer_attribute(model, "presolve", "on")

    S = 1:num_strips

    max_z_bounds = Dict()
    for i in set_i, j in set_w
        if (mat_h[i,j] + vec_t_h[i]) <= H && vec_w[i] <= W
            max_by_width = floor(Int, W / vec_w[i])
            max_by_height = floor(Int, H / (mat_h[i,j] + vec_t_h[i]))
            max_by_area = floor(Int, (W * H) / (vec_a[i] + vec_t_a[i]))
            max_z_bounds[(i,j)] = min(max_by_width, max_by_height, max_by_area, max_deptos)
        else
            max_z_bounds[(i,j)] = 0
        end
    end

    @variables(model, begin
        H_s[s in S] >= 0

        0 <= z[s in S, i in set_i, j in set_w] <= max_z_bounds[(i,j)], Int
        0 <= z_c[s in S, i in set_i, j in set_w] <= max_z_bounds[(i,j)], Int
        0 <= z_cc[s in S, i in set_i, j in set_w] <= max_z_bounds[(i,j)], Int

        x[s in S, i in set_i, j in set_w], Bin
        x_c[s in S, i in set_i, j in set_w], Bin
        x_cc[s in S, i in set_i, j in set_w], Bin

        y_c[s in S], Bin
        y_cc[s in S], Bin
    end)

    # Exactly 2 corner apartments per strip if corner type is used
    @constraint(model, constraint_uso_strip_c[s in S],
        sum(z_c[s,i,j] for i in set_i, j in set_w) == 2 * y_c[s]
    )

    # Exactly 1 double corner apartment per strip if double corner type is used
    @constraint(model, constraint_uso_strip_cc[s in S],
        sum(z_cc[s,i,j] for i in set_i, j in set_w) == y_cc[s]
    )
    # Allows only one double corner apartment or several regular apartments. Not both.
    @constraint(model, constraint_y_cc[s in S],
        sum(x_cc[s,i,j] + x[s,i,j] for i in set_i, j in set_w) <= y_cc[s] + (1 - y_cc[s]) * max_deptos
    )
    # Strip can use either corner or double corner, not both
    @constraint(model, constraint_corner_c_o_cc[s in S],
        y_c[s] + y_cc[s] <= 1
    )

    # Total count of all apartment types across all strips
    @expression(model, deptos_total,
        sum(z[s,i,j] for s in S, i in set_i, j in set_w) +
        sum(z_c[s,i,j] for s in S, i in set_i, j in set_w) +
        sum(z_cc[s,i,j] for s in S, i in set_i, j in set_w)
    )
    # Total apartment count must be within specified bounds
    @constraint(model, constraint_min_max_deptos,
        min_deptos <= deptos_total <= max_deptos
    )

    # Sum of all strip depths cannot exceed building height
    @constraint(model, constraint_suma_profundidades,
        sum(H_s[s] for s in S) <= H
    )

    # Each strip must have minimum depth of 7.0m
    @constraint(model, constraint_profundidad_strip[s in S],
        H_s[s] >= 8.0
    )

    # Symmetry breaking: order strips by depth (larger strips first)
    if num_strips > 1
        @constraint(model, constraint_symmetry_strip_order[s in 1:(num_strips-1)],
            H_s[s] >= H_s[s+1]
        )
    end


    # Apartment height must fit within strip depth
    @constraints(model, begin
        constraint_profundidad_strip_z[s in S, i in set_i, j in set_w], x[s,i,j] * (mat_h[i,j] + vec_t_h[i]) <= H_s[s]
        constraint_profundidad_strip_z_c[s in S, i in set_i, j in set_w], x_c[s,i,j] * (mat_h[i,j] + vec_t_h[i]) <= H_s[s]
        constraint_profundidad_strip_z_cc[s in S, i in set_i, j in set_w], x_cc[s,i,j] * (mat_h[i,j] + vec_t_h[i]) <= H_s[s]
    end)


    # Total apartment area per strip cannot exceed strip footprint
    @constraint(model, constraint_area_strip[s in S],
        sum((z[s,i,j] + z_c[s,i,j] + z_cc[s,i,j]) * (vec_a[i] + vec_t_a[i]) for i in set_i, j in set_w) <= W * H_s[s]
    )


    # Apartment count is positive only if apartment type is selected (Big-M)
    @constraints(model, begin
        constraint_big_m_z[s in S, i in set_i, j in set_w], z[s,i,j] <= max_deptos * x[s,i,j]
        constraint_big_m_z_c[s in S, i in set_i, j in set_w], z_c[s,i,j] <= max_deptos * x_c[s,i,j]
        constraint_big_m_z_cc[s in S, i in set_i, j in set_w], z_cc[s,i,j] <= max_deptos * x_cc[s,i,j]
    end)


    # Total apartment widths per strip cannot exceed building width
    @constraint(model, constraint_ancho_strip[s in S],
        sum((z[s,i,j] + z_c[s,i,j] + z_cc[s,i,j]) * vec_w[i] for i in set_i, j in set_w) <= W
    )

    # Apartment perimeters must cover strip perimeter (ensures full coverage)
    @constraint(model, constraint_perimetro[s in S],
        sum(z[s,i,j] * mat_p[i,j] for i in set_i, j in set_w) +
        sum(z_c[s,i,j] * mat_pc[i,j] for i in set_i, j in set_w) +
        sum(z_cc[s,i,j] * mat_pcc[i,j] for i in set_i, j in set_w) >= 2*H_s[s] + W - 5
    )


    # Total surface area of all apartments (objective function value)
    @expression(model, sup_deptos_total,
        sum((z[s,i,j] + z_c[s,i,j] + z_cc[s,i,j]) * vec_a[i] for s in S, i in set_i, j in set_w)
    )
    # Maximize total apartment surface area
    @objective(model, Max, sup_deptos_total)

    optimize!(model)

    results = Dict{String,Any}()
    results["status"] = termination_status(model)
    results["solve_time"] = solve_time(model)
    results["z"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["z_c"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["z_cc"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["x"] = Dict{Tuple{Int,Int,Int},Int}()
    results["x_c"] = Dict{Tuple{Int,Int,Int},Int}()
    results["x_cc"] = Dict{Tuple{Int,Int,Int},Int}()
    results["H_s"] = Dict{Int,Float64}()
    results["perimetro_strip"] = Dict{Int,Float64}()
    results["apartment_area_strip"] = Dict{Int,Float64}()
    results["terrace_area_strip"] = Dict{Int,Float64}()
    results["pasillo_area_strip"] = Dict{Int,Float64}()
    results["vec_t_a"] = vec_t_a
    results["vec_t_w"] = vec_t_w
    results["vec_t_h"] = vec_t_h
    results["vec_a"] = vec_a
    results["vec_pasillo_a"] = vec_pasillo_a
    results["vec_w"] = vec_w
    results["mat_h"] = mat_h

    if has_values(model)
        results["objective_value"] = objective_value(model)

        for s in S
            results["H_s"][s] = value(H_s[s])

            perimetro_s = sum(value(z[s,i,j]) * mat_p[i,j] for i in set_i, j in set_w) +
                          sum(value(z_c[s,i,j]) * mat_pc[i,j] for i in set_i, j in set_w) +
                          sum(value(z_cc[s,i,j]) * mat_pcc[i,j] for i in set_i, j in set_w)
            results["perimetro_strip"][s] = perimetro_s

            apartment_area_s = sum(value(z[s,i,j]) * vec_a[i] for i in set_i, j in set_w) +
                               sum(value(z_c[s,i,j]) * vec_a[i] for i in set_i, j in set_w) +
                               sum(value(z_cc[s,i,j]) * vec_a[i] for i in set_i, j in set_w)
            results["apartment_area_strip"][s] = apartment_area_s

            terrace_area_s = sum(value(z[s,i,j]) * vec_t_a[i] for i in set_i, j in set_w) +
                             sum(value(z_c[s,i,j]) * vec_t_a[i] for i in set_i, j in set_w) +
                             sum(value(z_cc[s,i,j]) * vec_t_a[i] for i in set_i, j in set_w)
            results["terrace_area_strip"][s] = terrace_area_s

            pasillo_area_s = sum(value(z[s,i,j]) * vec_pasillo_a[i] for i in set_i, j in set_w) +
                             sum(value(z_c[s,i,j]) * vec_pasillo_a[i] for i in set_i, j in set_w) +
                             sum(value(z_cc[s,i,j]) * vec_pasillo_a[i] for i in set_i, j in set_w)
            results["pasillo_area_strip"][s] = pasillo_area_s

            for i in set_i, h in set_w
                for (var, key, threshold, is_binary) in [
                    (z[s,i,h], "z", 0.001, false),
                    (z_c[s,i,h], "z_c", 0.001, false),
                    (z_cc[s,i,h], "z_cc", 0.001, false),
                    (x[s,i,h], "x", 0.5, true),
                    (x_c[s,i,h], "x_c", 0.5, true),
                    (x_cc[s,i,h], "x_cc", 0.5, true)]

                    val = value(var)
                    if val > threshold
                        results[key][(s,i,h)] = is_binary ? 1 : val
                    end
                end
            end
        end

        results["total_deptos"] = sum(sum(values(results[k])) for k in ["z", "z_c", "z_cc"])
        results["total_apartment_area"] = sum(values(results["apartment_area_strip"]))
        results["total_terrace_area"] = sum(values(results["terrace_area_strip"]))
        results["total_pasillo_area"] = sum(values(results["pasillo_area_strip"]))
    else
        results["objective_value"] = nothing
        results["total_deptos"] = 0.0
        println("\n⚠️  WARNING: No feasible solution found!")
        println("Status: $(results["status"])")
    end

    return results
end

function print_results(results::Dict)
    println("\n" * "="^60)
    println("RESULTADOS OPTIMIZACIÓN ASIGNACIÓN DEPTOS")
    println("="^60)
    println("Estado: $(results["status"])")

    if isnothing(results["objective_value"])
        println("Valor objetivo: N/A (sin solución factible)")
    else
        println("Valor objetivo: $(round(results["objective_value"], digits=2))")
    end

    println("Tiempo de solución: $(round(results["solve_time"], digits=2)) segundos")
    println("Total departamentos: $(round(results["total_deptos"], digits=0))")

    if !isnothing(results["objective_value"])
        total_apt_area = get(results, "total_apartment_area", 0.0)
        total_terrace_area = get(results, "total_terrace_area", 0.0)
        total_pasillo_area = get(results, "total_pasillo_area", 0.0)
        println("\nÁrea total departamentos: $(round(total_apt_area, digits=2)) m²")
        println("Área total terrazas: $(round(total_terrace_area, digits=2)) m²")
        println("Área total pasillos: $(round(total_pasillo_area, digits=2)) m²")
        println("Área total combinada: $(round(total_apt_area + total_terrace_area + total_pasillo_area, digits=2)) m²")
    end

    println("\n" * "-"^60)
    println("ASIGNACIÓN POR STRIP:")
    println("-"^60)

    for (strip, profundidad) in sort(collect(results["H_s"]))
        perimetro = get(results["perimetro_strip"], strip, 0.0)
        apt_area = get(results["apartment_area_strip"], strip, 0.0)
        terrace_area = get(results["terrace_area_strip"], strip, 0.0)
        pasillo_area = get(results["pasillo_area_strip"], strip, 0.0)
        println("\nStrip $strip - profundidad: $(round(profundidad, digits=2)) m - Perímetro: $(round(perimetro, digits=2)) m")
        println("  Área departamentos: $(round(apt_area, digits=2)) m²")
        println("  Área terrazas: $(round(terrace_area, digits=2)) m²")
        println("  Área pasillos: $(round(pasillo_area, digits=2)) m²")

        for (key, label) in [("z", "regulares"), ("z_c", "corner"), ("z_cc", "corner 2")]
            strip_deptos = filter(p -> p[1][1] == strip, collect(results[key]))
            if !isempty(strip_deptos)
                println("  Deptos $label:")
                vec_a = results["vec_a"]
                vec_t_a = results["vec_t_a"]
                vec_pasillo_a = results["vec_pasillo_a"]
                vec_t_h = results["vec_t_h"]
                for ((s, i, h), count) in strip_deptos
                    apt_area_unit = vec_a[i]
                    t_area = vec_t_a[i]
                    p_area = vec_pasillo_a[i]
                    t_height = vec_t_h[i]
                    println("    Tipo ($i,$h): $(round(count, digits=0)) unidades - Depto: $(round(apt_area_unit, digits=2)) m² | Terraza: $(round(t_area, digits=2)) m² | Pasillo: $(round(p_area, digits=2)) m² (prof: $(round(t_height, digits=2)) m)")
                end
            end
        end
    end
    println("\n" * "="^60)
end
