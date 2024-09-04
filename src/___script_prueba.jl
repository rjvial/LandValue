using LandValue, Clipper#, Devices


# ps1 = PolyShape([[0 0; 2 0; 2 2; 0 2],[1 1; 3 1; 3 3; 1 3]],2)
# ps2 = PolyShape([[4 4; 6 4; 6 6; 4 6],[3 4; 5 4; 5 6; 3 6]],2)

ps1 = PolyShape([[0 0; 2 0; 2 2; 0 2],[4 4; 6 4; 6 6; 4 6], [1 1; 2 0; 5 7; 4 6]],3)
ps2 = PolyShape([[1 1; 3 1; 3 3; 1 3],[3 4; 5 4; 5 6; 3 6]],2)

delta = -.2

path1 = polyShape.polyshape2clipper(ps1)
path2 = polyShape.polyshape2clipper(ps2)

u_path_a = polyShape.clipper_union(path1, path2)
ps_ua = polyShape.clipper2polyshape(u_path_a)
fig, ax, ax_mat = polyShape.plotPolyshape2D(ps_ua,"red",.5)
ps_offset = polyShape.polyExpand(ps_ua, delta)
polyShape.plotPolyshape2D(ps_offset,"red",.5, fig=fig, ax=ax, ax_mat=ax_mat )

u_path_b = polyShape.clipper_union(path1)
ps_ub = polyShape.clipper2polyshape(u_path_b)
fig, ax, ax_mat = polyShape.plotPolyshape2D(ps_ub,"red",.5)
ps_offset = polyShape.polyExpand(ps_ub, delta)
polyShape.plotPolyshape2D(ps_offset,"red",.5, fig=fig, ax=ax, ax_mat=ax_mat )

d_path = polyShape.clipper_difference(path1, path2)
ps_d = polyShape.clipper2polyshape(d_path)
fig, ax, ax_mat = polyShape.plotPolyshape2D(ps_d,"red",.5)
ps_offset = polyShape.polyExpand(ps_d, delta)
polyShape.plotPolyshape2D(ps_offset,"red",.5, fig=fig, ax=ax, ax_mat=ax_mat )

i_path = polyShape.clipper_intersection(path1, path2)
ps_i = polyShape.clipper2polyshape(i_path)
fig, ax, ax_mat = polyShape.plotPolyshape2D(ps_i,"red",.5)
ps_offset = polyShape.polyExpand(ps_i, delta)
polyShape.plotPolyshape2D(ps_offset,"red",.5, fig=fig, ax=ax, ax_mat=ax_mat )

