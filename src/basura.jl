using LandValue

ps = PolyShape([[0 0;50 0;50 50;60 60;100 60;100 90;40 90;0 55]],1)
#ps = PolyShape([[0 0;30 30;60 0;60 70;30 40;0 70]],1)
ps_ = polyShape.polyExpand(ps,20)
vev = polyShape.polyShape2lineVec(ps)
e1 = vev[1]
e5 = vev[5]
int = polyShape.intersectLines(polyShape.extendLine(e1,100), polyShape.extendLine(e5,100))
V = ps.Vertices[1]
ps_aux = PolyShape([[V[1,:]'; int.Vertices[1,:]'; V[6:8,:]]],1)
ps_aux_ = polyShape.polyDifference(ps_aux, ps)
ps_delta = polyShape.polyIntersect(ps_, ps_aux_)

fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps, 0, "green", 0.2)
fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_delta, 0, "black", 0.2, fig=fig, ax=ax, ax_mat=ax_mat)

ps_union = polyShape.polyUnion(ps, ps_delta)

vec_niveles = [polyShape.polyExpand(ps_union, -i) for i = 2:2:30]
num_niveles = length(vec_niveles)

vec_altura = [3*i for i=1:14]
vec_niveles_ = [polyShape.polyDifference(vec_niveles[i], ps_delta) for i = 1:14]

polyShape.plotPolyshape2DVecin3D(vec_niveles_, vec_altura, "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)


