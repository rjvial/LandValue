module poly2D

using  LazySets


function  checkConvex(V::Array{Float64,1})::Bool
# Given a set of points determine if they form a convex polygon

    px=V[:,1];
    py=V[:,2];

    isConvex = false;

    numPoints = length(px);
    if numPoints < 4
        isConvex = true;
        return isConvex
    end

    # can determine if the polygon is convex based on the direction the angles
    # turn.  If all angles are the same direction, it is convex.
    v1 = [px[1] - px[end], py[1] - py[end]];
    v2 = [px[2] - px[1], py[2] - py[1]];
    signPoly = sign(det([v1'; v2']));

    # check subsequent vertices
    for k = 2:numPoints-1
        v1 = v2;
        v2 = [px[k+1] - px[k], py[k+1] - py[k]];
        curr_signPoly = sign(det([v1'; v2']));
        # check that the signs match
        if curr_signPoly != signPoly
            isConvex = false;
            return isConvex
        end
    end

    # check the last vectors
    v1 = v2;
    v2 = [px[1] - px[end], py[1] - py[end]];
    curr_signPoly = sign(det([v1'; v2']));
    if curr_signPoly != signPoly
        isConvex = false;
    else
        isConvex = true;
    end

    return isConvex
end


function createLine(p1,p2)

    # first input parameter is first point, and second input is the
    # second point.
    x = p1[1]
    y = p1[2]
    dx = p2[1]-p1[1]
    dy = p2[2]-p1[2]

    line = [x y dx dy];
    return line
end



function intersectLines(line1, line2)
    # intersectLines([x1_0, y1_0, x1_1, y1_1], [x2_0, y2_0, x2_1, y2_1])

    # extract tolerance
    tol = 1e-14;


    # Check parallel and colinear lines

    # coordinate differences of origin points
    dx = line2[1] - line1[1];
    dy = line2[2] - line1[2];

    # indices of parallel lines
    denom = line1[3] .* line2[4] - line2[3] .* line1[4];
    par = abs(denom) < tol;

    # initialize result array
    x0 = 0;
    y0 = 0;

    # initialize result for parallel lines
    if par
        x0 = Inf;
        y0 = Inf;
        point = [x0 y0];
        return;
    end

    # Extract coordinates of itnersecting lines

    # extract base coordinates of first lines
    x1 =  line1[1];
    y1 =  line1[2];
    dx1 = line1[3];
    dy1 = line1[4];

    # extract base coordinates of second lines
    x2 =  line2[1];
    y2 =  line2[2];
    dx2 = line2[3];
    dy2 = line2[4];

    # re-compute coordinate differences of origin points
    dx = line2[1] - line1[1];
    dy = line2[2] - line1[2];


    # Compute intersection points

    x0 = (x2 .* dy2 .* dx1 - dy .* dx1 .* dx2 - x1 .* dy1 .* dx2) ./ denom ;
    y0 = (dx .* dy1 .* dy2 + y1 .* dx1 .* dy2 - y2 .* dx2 .* dy1) ./ denom ;

    # concatenate result
    point = [x0 y0];
end




function lineAngle(line)

    # angle of one line with horizontal
    theta = mod(atan(line[4], line[3]) + 2*pi, 2*pi);

    return theta
end


function parallelLine(line, dist)

    # use a distance. Compute position of point located at distance DIST on
    # the line orthogonal to the first one.
    point = pointOnLine([line[1] line[2] line[4] -line[3]], dist);

    res = [point' (line[3:4])'];
    return res
end




function pointOnLine(line, pos)

    angle = lineAngle(line);
    point = [line[1] + pos .* cos(angle), line[2] + pos .* sin(angle)];

    return point 
end


function polyArea(V::Array{Float64,2})::Float64

    if V != []
      X=V[:,1];
      Y=V[:,2];
      numPoints=size(X,1);

      area = 0;   # Accumulates area
      j = numPoints;

      for i = 1:numPoints
        area = area + (X[j]+X[i])*(Y[j]-Y[i]);
        j = i;  #j is previous vertex to i
      end

      return out=abs(area/2);
    else
      return out=0;
    end

    return out
end



function rotationMatrix(theta::Float64)::Array{Float64,2}
    R=[cos(theta) -sin(theta); sin(theta) cos(theta)];
end


function convHull(V::Array{Float64,2})::Array{Float64,2}

    n = size(V,1)
    v = [[V[i,1], V[i,2]] for i=1:n]
    ch_v = LazySets.convex_hull(v)

    V_out = [0 0]; for i in eachindex(ch_v); V_out=[V_out; ch_v[i]']; end; V_out = V_out[2:end,:]

    return V_out
end


function distPointLine(q, p1, p2)
    dist = sqrt(sum( ((q-p1) - ((q-p1)'*(p2-p1)) / ((p2-p1)'*(p2-p1)) * (p2-p1) ).^2))
    return dist
end


function intersectEdges(edge1, edge2)

    x1_ini  = edge1[1];
    y1_ini  = edge1[2];
    x1_fin  = edge1[3];
    y1_fin  = edge1[4];
    dx1 = x1_fin - x1_ini;
    dy1 = y1_fin - y1_ini;
    m1 = dy1 / dx1;

    x2_ini  = edge2[1];
    y2_ini  = edge2[2];
    x2_fin  = edge2[3];
    y2_fin  = edge2[4];
    dx2 = x2_fin - x2_ini;
    dy2 = y2_fin - y2_ini;
    m2 = dy2 / dx2;

    min_e1_x = min(x1_ini,x1_fin)
    min_e2_x = min(x2_ini,x2_fin)
    max_e1_x = max(x1_ini,x1_fin)
    max_e2_x = max(x2_ini,x2_fin)

    min_e1_y = min(y1_ini,y1_fin)
    min_e2_y = min(y2_ini,y2_fin)
    max_e1_y = max(y1_ini,y1_fin)
    max_e2_y = max(y2_ini,y2_fin)

    # tolerance for precision
    tol = 1e-3; #1e-14; 

    # initialize result array
    x0  = 0;
    y0  = 0;

    # indices of parallel edges
    par = abs(m1 - m2) < tol;

    # Parallel edges have no intersection -> return [NaN NaN]
    if par
        x0 = NaN;
        y0 = NaN;
    end

    # Process non parallel cases

    # compute intersection points of supporting lines
    delta = dx2 * dy1 - dx1 * dy2;
    x0 = ((y2_ini - y1_ini) * dx1 * dx2 + x1_ini * dy1 * dx2 - x2_ini * dy2 * dx1) / delta;
    y0 = ((x2_ini - x1_ini) * dy1 * dy2 + y1_ini * dx1 * dy2 - y2_ini * dx2 * dy1) / -delta;

    if  x0 < min_e1_x-tol || x0 < min_e2_x-tol || x0 > max_e1_x+tol || x0 > max_e2_x+tol || 
        y0 < min_e1_y-tol || y0 < min_e2_y-tol || y0 > max_e1_y+tol || y0 > max_e2_y+tol
        point = [NaN NaN];
    else
        point = [x0 y0];    
    end

end


function intersectPoly2d(V1, V2)

    V1 = [V1; V1[1,:]'];
    V2 = [V2; V2[1,:]'];
    N1 = size(V1, 1)
    N2 = size(V2, 1)

    # Loop over segments of V1
    i=1
    X=[NaN NaN NaN NaN]
    for n1 = 1:N1-1
        for n2 = 1:N2-1
            e1 = [V1[n1,:]' V1[n1+1,:]'] 
            e2 = [V2[n2,:]' V2[n2+1,:]']
            pInt = intersectEdges(e1, e2)
            if abs(pInt[1])>0
                if i==1
                    X[:] = [n1 n2 pInt]
                else
                    X = [X; [n1 n2 pInt]]
                end
                i=i+1      
            end
        end
    end
    
    return X
end


function distanceMat(points1,points2)

    numPoints1=size(points1,1)
    numPoints2=size(points2,1)

    distMat=zeros(numPoints1,numPoints2)
    for i=1:numPoints1
        point_i=points1[i,:]
        for j=1:numPoints2
            point_j=points2[j,:]
            distMat[i,j]=sqrt(sum((point_i-point_j).^2))
        end
    end

    return distMat

end


export  checkConvex, convHull, createLine, intersectLines, lineAngle, parallelLine, pointOnLine, polyArea, rotationMatrix,
        distPointLine, intersectEdges, intersectPoly2d, distanceMat
end
