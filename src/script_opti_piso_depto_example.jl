using LandValue

println("=" ^ 60)
println("APARTMENT FLOOR OPTIMIZATION EXAMPLE")
println("=" ^ 60)

floor_width = 30.0
floor_height = 20.0
rotation_angle = π/6

floor_vertices_base = [
    0.0 0.0;
    floor_width 0.0;
    floor_width floor_height;
    0.0 floor_height
]

centroid_x = floor_width / 2
centroid_y = floor_height / 2
cos_rot = cos(rotation_angle)
sin_rot = sin(rotation_angle)

floor_vertices = similar(floor_vertices_base)
for i in axes(floor_vertices_base, 1)
    dx = floor_vertices_base[i, 1] - centroid_x
    dy = floor_vertices_base[i, 2] - centroid_y
    floor_vertices[i, 1] = dx * cos_rot - dy * sin_rot + centroid_x
    floor_vertices[i, 2] = dx * sin_rot + dy * cos_rot + centroid_y
end

floor_poly = PolyShape([floor_vertices], 1)

println("\nFloor rectangle rotated by $(round(rad2deg(rotation_angle), digits=1))°")

apt_areas = [50.0, 75.0, 100.0]
apt_counts = [2, 3, 2]

println("\nInput Parameters:")
println("  Floor dimensions: $(floor_width)m × $(floor_height)m")
println("  Floor area: $(floor_width * floor_height)m²")
println("  Apartment types: $(length(apt_areas))")
println("  Apartment areas: $(apt_areas)m²")
println("  Apartment counts: $(apt_counts)")
println("  Total apartments: $(sum(apt_counts))")
println("  Total required area: $(sum(apt_areas .* apt_counts))m²")

results = opti_floor_plan(floor_poly, apt_areas, apt_counts)

if results["feasible"]
    println("\nOptimization successful!")

    total_apt_area = sum(apt_areas .* apt_counts)
    total_floor_area = floor_width * floor_height
    core_area = results["core_width"] * results["core_length"]
    efficiency = (total_apt_area / total_floor_area) * 100

    println("\nResults:")
    println("  North strip: $(results["n_apts_north"]) apartments, height: $(results["height_north"])m")
    println("    Areas (W→E): $(results["apt_areas_north"])m²")
    println("  South strip: $(results["n_apts_south"]) apartments, height: $(results["height_south"])m")
    println("    Areas (W→E): $(results["apt_areas_south"])m²")
    println("  Core: $(results["core_width"])m × $(results["core_length"])m = $(round(core_area, digits=2))m²")

    println("\nArea Analysis:")
    println("  Total apartment area: $(round(total_apt_area, digits=2))m²")
    println("  Core area: $(round(core_area, digits=2))m²")
    println("  Unused area: $(round(results["total_unused"], digits=2))m²")
    println("  Total floor area: $(round(total_floor_area, digits=2))m²")
    println("  Efficiency: $(round(efficiency, digits=1))%")

    println("\nApartment PolyShapes:")
    println("  Total apartment polygons: $(length(results["vec_polyshapes_all"]))")

    println("\nAccess individual apartments:")

    fig, ax, ax_mat = polyPlot.plotPolyshape2D(floor_poly, "green", 0.2)   
    fig, ax, ax_mat = polyPlot.plotPolyshape2D(results["core_polyshape"], "gray", 0.5, fig=fig, ax=ax, ax_mat=ax_mat)
    fig, ax, ax_mat = polyPlot.plotPolyshape2D.(results["vec_polyshapes_all"], "red", 0.2, fig=fig, ax=ax, ax_mat=ax_mat)
else
    println("\nOptimization failed!")
    println("Status: $(results["status"])")
end

println("\n" * "=" ^ 60)