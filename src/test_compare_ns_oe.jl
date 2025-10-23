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


println("\nPlotting NS Layout (Horizontal Strips)...")
results_ns = opti_floor_plan(ps_planta, vec_sup_deptos, vec_num_deptos,
                             layout=:ns,
                             ancho_pasillo=ancho_pasillo,
                             vec_sup_terraza=vec_sup_terraza,
                             vec_min_dimensiones=vec_min_ancho_deptos,
                             min_dimension_escala=min_ancho_escala,
                             area_escala=area_escala)

fig_ns, ax_ns, ax_mat_ns = polyPlot.plotPolyshape2D(ps_planta, "green", 0.2)
polyPlot.plotPolyshape2D(results_ns["ps_pasillo"], "#505050", 0.9, fig=fig_ns, ax=ax_ns, ax_mat=ax_mat_ns)
polyPlot.plotPolyshape2D(results_ns["ps_escala"], "#303030", 0.9, fig=fig_ns, ax=ax_ns, ax_mat=ax_mat_ns)
for apt_poly in results_ns["vec_polyshapes_all"]
    polyPlot.plotPolyshape2D(apt_poly, "red", 0.3, fig=fig_ns, ax=ax_ns, ax_mat=ax_mat_ns)
end
for terrace in results_ns["vec_terrazas_all"]
    if polyShape.polyArea(terrace) > 0.0
        polyPlot.plotPolyshape2D(terrace, "blue", 0.4, fig=fig_ns, ax=ax_ns, ax_mat=ax_mat_ns)
    end
end
ax_ns.set_aspect("equal")
println("  ✓ NS plot created")


println("\nPlotting OE Layout (Vertical Strips)...")
results_oe = opti_floor_plan(ps_planta, vec_sup_deptos, vec_num_deptos,
                             layout=:oe,
                             ancho_pasillo=ancho_pasillo,
                             vec_sup_terraza=vec_sup_terraza,
                             vec_min_dimensiones=vec_min_alto_deptos,
                             min_dimension_escala=min_alto_escala,
                             area_escala=area_escala)

fig_oe, ax_oe, ax_mat_oe = polyPlot.plotPolyshape2D(ps_planta, "green", 0.2)
polyPlot.plotPolyshape2D(results_oe["ps_pasillo"], "#505050", 0.9, fig=fig_oe, ax=ax_oe, ax_mat=ax_mat_oe)
polyPlot.plotPolyshape2D(results_oe["ps_escala"], "#303030", 0.9, fig=fig_oe, ax=ax_oe, ax_mat=ax_mat_oe)
for apt_poly in results_oe["vec_polyshapes_all"]
    polyPlot.plotPolyshape2D(apt_poly, "red", 0.3, fig=fig_oe, ax=ax_oe, ax_mat=ax_mat_oe)
end
for terrace in results_oe["vec_terrazas_all"]
    if polyShape.polyArea(terrace) > 0.0
        polyPlot.plotPolyshape2D(terrace, "blue", 0.4, fig=fig_oe, ax=ax_oe, ax_mat=ax_mat_oe)
    end
end
println("  ✓ OE plot created")
