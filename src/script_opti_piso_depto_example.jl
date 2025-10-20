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

results = opti_piso_depto(floor_poly, apt_areas, apt_counts)

if results["feasible"]
    println("\nOptimization successful!")

    total_used_north = sum(results["widths_north"]) * results["height_north"]
    total_used_south = sum(results["widths_south"]) * results["height_south"]
    total_used = total_used_north + total_used_south
    total_area = floor_width * floor_height
    efficiency = (total_used / total_area) * 100

    println("\nArea Analysis:")
    println("  North strip area: $(round(results["height_north"] * floor_width, digits=2))m²")
    println("  South strip area: $(round(results["height_south"] * floor_width, digits=2))m²")
    println("  Used area: $(round(total_used, digits=2))m²")
    println("  Total floor area: $(round(total_area, digits=2))m²")
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