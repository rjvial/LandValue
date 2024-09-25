using LandValue, Clipper


ps_predio = PolyShape([[24.08  48.02;
 10.79  33.14;
  0.0   16.33;
 26.7    0.0;
 45.62  29.31;
 56.53  41.58;
 89.1   61.13;
 65.22  83.99]],1)

 fig, ax, ax_mat = polyShape.plotPolyshape2D(ps_predio, "green", 0.05)

# vec_id_ps_partial_offset = [2,3,5,6,8]; dist = 10; # vecDist = [-2,-1,-4,-2,-5] #vecDist = [20,10,-4,20,-5]
# vec_id_ps_partial_offset = [1,2,3,5,8]; dist = 10; # vecDist = [10,20,10,10,20,15]
# vec_id_ps_partial_offset = [1,2,5,6,7,8]; dist = 10; # vecDist = [10,20,10,10,20,15]
# vec_id_ps_partial_offset = [1,3,5,7,8]; dist = 10; # vecDist = [20,10,10,20,15] 
# vec_id_ps_partial_offset = [1,3,5,7]; dist = 10; # vecDist = [20,10,20,15]  
# vec_id_ps_partial_offset = [1,2,3,4,5,6,7]; dist = 10; # vecDist = [15,10,20,10,10,20,15]

# ps_offset = polyShape.polyOffset(ps_predio, dist)
# fig, ax, ax_mat = polyShape.plotPolyshape2D(ps_offset, "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)

# ps_out_2 = polyShape.partialPolyOffset(ps_predio, vec_id_ps_partial_offset, dist)
# fig, ax, ax_mat = polyShape.plotPolyshape2D(ps_out_2, "blue", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)

vec_id_ps_partial_offset = [1,2,3,5,8]; vecDist = 100

# vec_id_ps_partial_offset = [2,3,5,6,8]; vecDist = [20,10,-4,20,-5]
# vec_id_ps_partial_offset = [2,3]; vecDist = [20,-5]
# vec_id_ps_partial_offset = [1,2,3,5,8]; vecDist = [-4,20,-5,10,20]
# vec_id_ps_partial_offset = [1,2,5,6,7,8]; vecDist = [10,20,10,-4,20,-5]
# vec_id_ps_partial_offset = [1,3,5,7,8]; vecDist = [20,-4,-5,20,15] 
# vec_id_ps_partial_offset = [1,3,5,7]; vecDist = [20,-4,20,-5]  
# vec_id_ps_partial_offset = [1,2,3,4,5,6,7]; vecDist = [15,-5,20,-4,10,20,-5]

ps_out_2 = polyShape.partialPolyOffset(ps_predio, vec_id_ps_partial_offset, vecDist)
fig, ax, ax_mat = polyShape.plotPolyshape2D(ps_out_2, "blue", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)

