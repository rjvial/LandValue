using LandValue

println("=" ^ 60)
println("APARTMENT FLOOR OPTIMIZATION - 5 EXAMPLES")
println("=" ^ 60)

examples = [
    (width=30.0, height=20.0, rotation=π/6, vec_sup_deptos=[50.0, 75.0, 100.0], vec_num_deptos=[2, 2, 1], ancho_pasillo=2.0, vec_sup_terraza=[5.0, 7.5, 10.0], vec_min_ancho_deptos=[4.0, 4.5, 5.0], min_ancho_escala=4.0, area_escala=20.0),
    (width=25.0, height=25.0, rotation=π/4, vec_sup_deptos=[60.0, 80.0], vec_num_deptos=[2, 2], ancho_pasillo=2.0, vec_sup_terraza=[6.0, 8.0], vec_min_ancho_deptos=[3.8, 4.2], min_ancho_escala=4.0, area_escala=20.0),
    (width=35.0, height=18.0, rotation=0.0, vec_sup_deptos=[45.0, 65.0, 85.0, 110.0], vec_num_deptos=[2, 2, 1, 1], ancho_pasillo=2.0, vec_sup_terraza=[4.5, 6.5, 8.5, 11.0], vec_min_ancho_deptos=[3.2, 3.8, 4.0, 4.5], min_ancho_escala=4.0, area_escala=20.0),
    (width=28.0, height=22.0, rotation=-π/8, vec_sup_deptos=[55.0, 90.0], vec_num_deptos=[3, 2], ancho_pasillo=2.0, vec_sup_terraza=[5.5, 9.0], vec_min_ancho_deptos=[3.5, 4.5], min_ancho_escala=4.0, area_escala=20.0),
    (width=32.0, height=16.0, rotation=π/3, vec_sup_deptos=[40.0, 70.0, 100.0], vec_num_deptos=[2, 2, 1], ancho_pasillo=1.8, vec_sup_terraza=[4.0, 7.0, 10.0], vec_min_ancho_deptos=[3.0, 4.0, 4.8], min_ancho_escala=4.0, area_escala=20.0)
]

for (idx, example) in enumerate(examples)
    println("\n" * "=" ^ 60)
    println("EXAMPLE $idx")
    println("=" ^ 60)

    ancho_planta = example.width
    alto_planta = example.height
    rotation_angle = example.rotation

    floor_vertices_base = [
        0.0 0.0;
        ancho_planta 0.0;
        ancho_planta alto_planta;
        0.0 alto_planta
    ]

    centroid_x = ancho_planta / 2
    centroid_y = alto_planta / 2
    cos_rot = cos(rotation_angle)
    sin_rot = sin(rotation_angle)

    floor_vertices = similar(floor_vertices_base)
    for i in axes(floor_vertices_base, 1)
        dx = floor_vertices_base[i, 1] - centroid_x
        dy = floor_vertices_base[i, 2] - centroid_y
        floor_vertices[i, 1] = dx * cos_rot - dy * sin_rot + centroid_x
        floor_vertices[i, 2] = dx * sin_rot + dy * cos_rot + centroid_y
    end

    ps_planta = PolyShape([floor_vertices], 1)

    println("\nFloor rectangle rotated by $(round(rad2deg(rotation_angle), digits=1))°")

    vec_sup_deptos = example.vec_sup_deptos
    vec_num_deptos = example.vec_num_deptos
    vec_sup_terraza = example.vec_sup_terraza
    vec_min_ancho_deptos = example.vec_min_ancho_deptos
    min_ancho_escala = example.min_ancho_escala
    area_escala = example.area_escala

    total_apt_area_input = sum(vec_sup_deptos .* vec_num_deptos)
    total_terrace_area = sum(vec_sup_terraza .* vec_num_deptos)
    estimated_hallway = example.ancho_pasillo * ancho_planta
    total_required = total_apt_area_input + total_terrace_area + area_escala + estimated_hallway

    println("\nInput Parameters:")
    println("  Floor dimensions: $(ancho_planta)m × $(alto_planta)m")
    println("  Floor area: $(ancho_planta * alto_planta)m²")
    println("  Apartment types: $(length(vec_sup_deptos))")
    println("  Apartment areas: $(vec_sup_deptos)m²")
    println("  Apartment counts: $(vec_num_deptos)")
    println("  Total apartments: $(sum(vec_num_deptos))")
    println("  Apartment area: $(round(total_apt_area_input, digits=2))m²")
    println("  Terrace area: $(round(total_terrace_area, digits=2))m²")
    println("  Staircase area: $(area_escala)m²")
    println("  Estimated hallway: $(round(estimated_hallway, digits=2))m²")
    println("  Total required: $(round(total_required, digits=2))m² ($(round(100*total_required/(ancho_planta*alto_planta), digits=1))%)")
    println("  Core width: $(example.ancho_pasillo)m")
    println("  Terrace areas per type: $(vec_sup_terraza)m²")
    println("  Minimum apartment widths: $(vec_min_ancho_deptos)m")
    println("  Minimum staircase width: $(min_ancho_escala)m")

    results = opti_floor_plan(ps_planta, vec_sup_deptos, vec_num_deptos, ancho_pasillo=example.ancho_pasillo, vec_sup_terraza=vec_sup_terraza, vec_min_ancho_deptos=vec_min_ancho_deptos, min_ancho_escala=min_ancho_escala, area_escala=area_escala)

    if results["feasible"]
        println("\nOptimization successful!")

        total_apt_area = sum(vec_sup_deptos .* vec_num_deptos)
        total_floor_area = ancho_planta * alto_planta
        core_area = results["ancho_pasillo"] * results["largo_pasillo"]
        efficiency = (total_apt_area / total_floor_area) * 100

        println("\nResults:")
        println("  norte franja: $(results["n_apts_norte"]) apartments, height: $(results["height_norte"])m")
        println("    Areas (W→E): $(results["vec_sup_deptos_norte"])m²")
        println("  sur franja: $(results["n_apts_sur"]) apartments, height: $(results["height_sur"])m")
        println("    Areas (W→E): $(results["vec_sup_deptos_sur"])m²")
        println("  Core: $(results["ancho_pasillo"])m × $(results["largo_pasillo"])m = $(round(core_area, digits=2))m²")
        println("  Stair: $(results["ancho_escala"])m × $(results["alto_escala"])m = $(results["area_escala"])m²")

        println("\nArea Analysis:")
        println("  Total apartment area: $(round(total_apt_area, digits=2))m²")
        println("  Core area: $(round(core_area, digits=2))m²")
        println("  Total floor area: $(round(total_floor_area, digits=2))m²")
        println("  Efficiency: $(round(efficiency, digits=1))%")

        println("\nApartment PolyShapes:")
        println("  Total apartment polygons: $(length(results["vec_polyshapes_all"]))")

        println("  Total terrace polygons: $(length(results["vec_terrazas_all"]))")

        println("\nTerrace Dimensions by Apartment Type:")
        for (i, terrace_area) in enumerate(vec_sup_terraza)
            if terrace_area > 0.0
                apt_area = vec_sup_deptos[i]
                franja_height = i <= length(results["vec_sup_deptos_norte"]) ? results["height_norte"] : results["height_sur"]
                apt_width = apt_area / franja_height

                terrace_height_default = 1.75
                terrace_width_calc = terrace_area / terrace_height_default

                if terrace_width_calc > apt_width
                    terrace_width_final = apt_width
                    terrace_height_final = terrace_area / terrace_width_final
                else
                    terrace_width_final = terrace_width_calc
                    terrace_height_final = terrace_height_default
                end

                println("  Type $(i): Area=$(apt_area)m², Terrace=$(terrace_area)m² → $(round(terrace_width_final, digits=2))m × $(round(terrace_height_final, digits=2))m")
            end
        end


        fig, ax, ax_mat = polyPlot.plotPolyshape2D(ps_planta, "green", 0.2)
        polyPlot.plotPolyshape2D(results["ps_pasillo"], "gray", 0.5, fig=fig, ax=ax, ax_mat=ax_mat)
        polyPlot.plotPolyshape2D(results["ps_escala"], "orange", 0.5, fig=fig, ax=ax, ax_mat=ax_mat)

        for apt_poly in results["vec_polyshapes_all"]
            polyPlot.plotPolyshape2D(apt_poly, "red", 0.2, fig=fig, ax=ax, ax_mat=ax_mat)
        end

        for terrace in results["vec_terrazas_all"]
            if terrace.NumRegions > 0
                polyPlot.plotPolyshape2D(terrace, "blue", 0.3, fig=fig, ax=ax, ax_mat=ax_mat)
            end
        end
    else
        println("\nOptimization failed!")
        println("Status: $(results["status"])")
    end
end

println("\n" * "=" ^ 60)
println("ALL EXAMPLES COMPLETED")
println("=" ^ 60)