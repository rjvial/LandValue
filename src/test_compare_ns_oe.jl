using LandValue

println("=" ^ 80)
println("COMPARING NS (Norte-Sur) vs OE (Oeste-Este) FLOOR PLAN LAYOUTS")
println("=" ^ 80)

ancho_planta = 30.0
alto_planta = 20.0
rotation_angle = π/6

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

vec_sup_deptos = [50.0, 75.0, 100.0]
vec_num_deptos = [2, 2, 1]
vec_sup_terraza = [5.0, 7.5, 10.0]
vec_min_ancho_deptos = [4.0, 4.5, 5.0]
vec_min_alto_deptos = [4.0, 4.5, 5.0]
min_ancho_escala = 4.0
min_alto_escala = 4.0
area_escala = 20.0
ancho_pasillo = 1.5

total_apt_area_input = sum(vec_sup_deptos .* vec_num_deptos)
total_terrace_area = sum(vec_sup_terraza .* vec_num_deptos)
total_floor_area = ancho_planta * alto_planta

println("\nFloor Parameters:")
println("  Dimensions: $(ancho_planta)m × $(alto_planta)m")
println("  Total area: $(total_floor_area)m²")
println("  Apartment types: $(length(vec_sup_deptos))")
println("  Apartment areas: $(vec_sup_deptos)m²")
println("  Apartment counts: $(vec_num_deptos)")
println("  Total apartments: $(sum(vec_num_deptos))")
println("  Total apartment area: $(round(total_apt_area_input, digits=2))m²")
println("  Total terrace area: $(round(total_terrace_area, digits=2))m²")
println("  Staircase area: $(area_escala)m²")
println("  Hallway width: $(ancho_pasillo)m")

println("\n" * "=" ^ 80)
println("NS LAYOUT (Horizontal Strips: Norte + Sur)")
println("=" ^ 80)

results_ns = opti_floor_plan_ns(ps_planta, vec_sup_deptos, vec_num_deptos,
                             ancho_pasillo=ancho_pasillo,
                             vec_sup_terraza=vec_sup_terraza,
                             vec_min_ancho_deptos=vec_min_ancho_deptos,
                             min_ancho_escala=min_ancho_escala,
                             area_escala=area_escala)

if results_ns["feasible"]
    println("\n✓ NS Optimization successful!")

    core_area_ns = results_ns["ancho_pasillo"] * results_ns["largo_pasillo"]
    efficiency_ns = (total_apt_area_input / total_floor_area) * 100

    println("\nNS Results:")
    println("  Norte strip: $(results_ns["n_apts_norte"]) apartments, height: $(results_ns["height_norte"])m")
    println("    Areas (W→E): $(results_ns["vec_sup_deptos_norte"])m²")
    println("  Sur strip: $(results_ns["n_apts_sur"]) apartments, height: $(results_ns["height_sur"])m")
    println("    Areas (W→E): $(results_ns["vec_sup_deptos_sur"])m²")
    println("  Horizontal hallway: $(results_ns["ancho_pasillo"])m × $(results_ns["largo_pasillo"])m = $(round(core_area_ns, digits=2))m²")
    println("  Staircase: $(results_ns["ancho_escala"])m × $(results_ns["alto_escala"])m = $(results_ns["area_escala"])m²")
    println("  Efficiency: $(round(efficiency_ns, digits=1))%")
    println("  Total apartments plotted: $(length(results_ns["vec_polyshapes_all"]))")
    println("  Total terraces plotted: $(length(results_ns["vec_terrazas_all"]))")
else
    println("\n✗ NS Optimization failed!")
    println("Status: $(results_ns["status"])")
end

println("\n" * "=" ^ 80)
println("OE LAYOUT (Vertical Strips: Oeste + Este)")
println("=" ^ 80)

results_oe = opti_floor_plan_oe(ps_planta, vec_sup_deptos, vec_num_deptos,
                             ancho_pasillo=ancho_pasillo,
                             vec_sup_terraza=vec_sup_terraza,
                             vec_min_alto_deptos=vec_min_alto_deptos,
                             min_alto_escala=min_alto_escala,
                             area_escala=area_escala)

if results_oe["feasible"]
    println("\n✓ OE Optimization successful!")

    core_area_oe = results_oe["ancho_pasillo"] * results_oe["largo_pasillo"]
    efficiency_oe = (total_apt_area_input / total_floor_area) * 100

    println("\nOE Results:")
    println("  Este strip: $(results_oe["n_apts_este"]) apartments, width: $(results_oe["width_este"])m")
    println("    Areas (S→N): $(results_oe["vec_sup_deptos_este"])m²")
    println("  Oeste strip: $(results_oe["n_apts_oeste"]) apartments, width: $(results_oe["width_oeste"])m")
    println("    Areas (S→N): $(results_oe["vec_sup_deptos_oeste"])m²")
    println("  Vertical hallway: $(results_oe["ancho_pasillo"])m × $(results_oe["largo_pasillo"])m = $(round(core_area_oe, digits=2))m²")
    println("  Staircase: $(results_oe["ancho_escala"])m × $(results_oe["alto_escala"])m = $(results_oe["area_escala"])m²")
    println("  Efficiency: $(round(efficiency_oe, digits=1))%")
    println("  Total apartments plotted: $(length(results_oe["vec_polyshapes_all"]))")
    println("  Total terraces plotted: $(length(results_oe["vec_terrazas_all"]))")
else
    println("\n✗ OE Optimization failed!")
    println("Status: $(results_oe["status"])")
end

println("\n" * "=" ^ 80)
println("VISUALIZATION")
println("=" ^ 80)

if results_ns["feasible"]
    println("\nPlotting NS Layout (Horizontal Strips)...")

    fig_ns, ax_ns, ax_mat_ns = polyPlot.plotPolyshape2D(ps_planta, "green", 0.2)
    polyPlot.plotPolyshape2D(results_ns["ps_pasillo"], "#505050", 0.8, fig=fig_ns, ax=ax_ns, ax_mat=ax_mat_ns)
    polyPlot.plotPolyshape2D(results_ns["ps_escala"], "#303030", 0.9, fig=fig_ns, ax=ax_ns, ax_mat=ax_mat_ns)

    for apt_poly in results_ns["vec_polyshapes_all"]
        polyPlot.plotPolyshape2D(apt_poly, "red", 0.3, fig=fig_ns, ax=ax_ns, ax_mat=ax_mat_ns)
    end

    for terrace in results_ns["vec_terrazas_all"]
        if polyShape.polyArea(terrace) > 0.0
            polyPlot.plotPolyshape2D(terrace, "blue", 0.4, fig=fig_ns, ax=ax_ns, ax_mat=ax_mat_ns)
        end
    end

    ax_ns.set_title("NS Layout: Horizontal Strips (Norte-Sur)", fontsize=14, fontweight="bold")
    ax_ns.set_xlabel("X (meters)", fontsize=11)
    ax_ns.set_ylabel("Y (meters)", fontsize=11)
    ax_ns.grid(true, alpha=0.3)
    ax_ns.set_aspect("equal")

    println("  ✓ NS plot created")
end

if results_oe["feasible"]
    println("\nPlotting OE Layout (Vertical Strips)...")

    fig_oe, ax_oe, ax_mat_oe = polyPlot.plotPolyshape2D(ps_planta, "green", 0.2)
    polyPlot.plotPolyshape2D(results_oe["ps_pasillo"], "#505050", 0.8, fig=fig_oe, ax=ax_oe, ax_mat=ax_mat_oe)
    polyPlot.plotPolyshape2D(results_oe["ps_escala"], "#303030", 0.9, fig=fig_oe, ax=ax_oe, ax_mat=ax_mat_oe)

    for apt_poly in results_oe["vec_polyshapes_all"]
        polyPlot.plotPolyshape2D(apt_poly, "red", 0.3, fig=fig_oe, ax=ax_oe, ax_mat=ax_mat_oe)
    end

    for terrace in results_oe["vec_terrazas_all"]
        if polyShape.polyArea(terrace) > 0.0
            polyPlot.plotPolyshape2D(terrace, "blue", 0.4, fig=fig_oe, ax=ax_oe, ax_mat=ax_mat_oe)
        end
    end

    ax_oe.set_title("OE Layout: Vertical Strips (Oeste-Este)", fontsize=14, fontweight="bold")
    ax_oe.set_xlabel("X (meters)", fontsize=11)
    ax_oe.set_ylabel("Y (meters)", fontsize=11)
    ax_oe.grid(true, alpha=0.3)
    ax_oe.set_aspect("equal")

    println("  ✓ OE plot created")
end

println("\n" * "=" ^ 80)
println("COMPARISON SUMMARY")
println("=" ^ 80)

if results_ns["feasible"] && results_oe["feasible"]
    println("\nLayout Comparison:")
    println("  NS: Norte ($(results_ns["n_apts_norte"]) apts) + Sur ($(results_ns["n_apts_sur"]) apts)")
    println("  OE: Este ($(results_oe["n_apts_este"]) apts) + Oeste ($(results_oe["n_apts_oeste"]) apts)")

    println("\nHallway Orientation:")
    println("  NS: Horizontal hallway ($(results_ns["largo_pasillo"])m length)")
    println("  OE: Vertical hallway ($(results_oe["largo_pasillo"])m length)")

    println("\nColor Legend:")
    println("  Green: Floor boundary")
    println("  Red: Apartments")
    println("  Blue: Terraces")
    println("  Dark Gray: Hallway (pasillo)")
    println("  Darker Gray: Staircase (escala)")
end

println("\n" * "=" ^ 80)
println("TEST COMPLETED")
println("=" ^ 80)