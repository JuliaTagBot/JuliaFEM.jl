# This file is a part of JuliaFEM.
# License is MIT: see https://github.com/JuliaFEM/JuliaFEM.jl/blob/master/LICENSE.md

# Mortar projection calculation for 3d cases

""" Construct auxiliary plane for surface. """
function create_auxiliary_plane{E}(element::Element{E}, time::Real)
    xi = get_reference_element_midpoint(E)
    x0 = element("geometry", xi, time)
    ntbasis = element("normal-tangential coordinates", xi, time)
    return x0, ntbasis
end


"""
Project point q onto a plane given by a point p and normal n.

Parameters
----------
q::Array{Float64, 2}
    point to project (row vector)
x0::Array{Float64, 2}
    origo of plane
n::Array{Float64, 2}
    normal vector of plane

Returns
-------
y::Array{Float64, 2}
    projected point

Examples
--------
julia> p = [-0.5 -1.0 4.0]'
julia> x0 = [0.0 0.075 0.675]'
julia> n = [0.1485860 0.0784519 0.9857830]'
julia> project_node_to_auxiliary_plane(p, x0, n)
3-element Array{Float64,1}:
  0.963455
 -1.2447
  0.925247

Notes
-----
[1](http://stackoverflow.com/questions/8942950/how-do-i-find-the-orthogonal-projection-of-a-point-onto-a-plane)

"""
function project_vertex_to_auxiliary_plane(p::Vector, x0::Vector, Q::Matrix)
    n = Q[:,1]
    ph = p - dot(p-x0, n)*n
    qproj = Q'*(ph-x0)
    if abs(qproj[1]) > 1.0e-2
        # we should have something very little for normal direction if projected
        # properly
        info("project_point_to_auxiliary_plane(): vertex not projected correctly.")
        info("p: $(ForwardDiff.get_value(p))")
        info("x0: $(ForwardDiff.get_value(x0))")
        info("Q: \n$(ForwardDiff.get_value(Q))")
        info("qproj: $(ForwardDiff.get_value(qproj))")
        error("Failed to project vertex to auxiliary plane.")
    end
    return qproj[2:3]
end

project_point_to_auxiliary_plane = project_vertex_to_auxiliary_plane

"""
Find edge intersections of two planar arbitrary shape polygons.

Parameters
----------
S::Array{Float64,2}
M::Array{Float64,2}

Matrices with size (2, n) where n is number of vertices of each polygon.

Returns
-------
P::Array{Float64,2}
    Intersection points of polygons
n::Array{Float64,2}
    Neighbour info matrix with size (ns, mn). This keeps information which
    edges of polygons are intersecting. See further explanation in example
    below.

Examples
--------
Find intersection points of two triangles:

julia> S = [0 0; 3 0; 0 3]'
julia> M = [-1 1; 2 -1/2; 1 3/2]'
julia> P, n = get_edge_intersections(S, M)
julia> P
2x4 Array{Float64,2}:
 1.0  1.75  0.0  0.0
 0.0  0.0   0.5  1.25
julia> n
3x3 Array{Int64,2}:
 1  1  0
 0  0  0
 1  0  1)

So intersection points are: (1.00, 0.00), (1.75, 0.00), (0.00, 0.50), (0.00, 1.25).
"Neighbour matrix" can be interpreted as following:

    1 1 0 <--> First edge of S intersects edges 1 and 2 of M
    0 0 0 <--> Second edge of S doesn't intersect at all
    1 0 1 <--> Third edge of S intersects with edges 1 and 3 of M

"""
function get_edge_intersections(S::Matrix, M::Matrix)
    ns = size(S, 2)
    nm = size(M, 2)
    P = zeros(2, 0)
    n = zeros(Int64, ns, nm)
    k = 0
    for i=1:ns
        for j=1:nm
            b = M[:,j]-S[:,i]
            A = [S[:,mod(i,ns)+1]-S[:,i]  -M[:,mod(j,nm)+1]+M[:,j]]
            if rank(ForwardDiff.get_value(A)) == 2
                r = A\b
                if (r[1]>=0) & (r[1]<=1) & (r[2]>=0) & (r[2]<=1)  # intersection found
                    k += 1
                    f = S[:,i]+r[1]*(S[:,mod(i,ns)+1] - S[:,i])
                    f = f''
                    P = hcat(P, f)
                    n[i, j] = 1
                end
            end
        end
    end
    return P, n
end


"""
Find any points laying inside or border of triangle.

Parameters
----------
Y::Array{Float64, 2}
    Triangle coordinates in 2×3 matrix
X::Array{Float64, 2}
    List of points to test in 2×n matrix

Returns
-------
P::Array{Float64, 2}
    List of points in triangle in 2×m matrix, where m is number of points inside triangle

Examples
--------
julia> S = [0.0 0.0; 3.0 0.0; 0.0 3.0]'  # triangle corner points
julia> pts = [-1.0 1.0; 2.0 -0.5; 1.0 1.5; 0.5 1.5]'  # points to tests
julia> points_in_triangle(S, pts)
2x2 Array{Float64,2}:
 1.0  0.5
 1.5  1.5
"""
function get_points_inside_triangle(Y::Matrix, X::Matrix)
    @assert size(Y, 2) == 3  # "Point in TRIANGLE..."
    P = zeros(2, 0)
    v0 = Y[:,2] - Y[:,1]
    v1 = Y[:,3] - Y[:,1] # find interior points of X in Y
    d00 = (v0'*v0)[1]
    d01 = (v0'*v1)[1]
    d11 = (v1'*v1)[1]  # using baricentric coordinates
    id = 1/(d00*d11 - d01*d01)
    for i=1:size(X, 2)
        v2 = X[:,i] - Y[:,1]
        d02 = (v0'*v2)[1]
        d12 = (v1'*v2)[1]
        u = (d11*d02-d01*d12)*id
        v = (d00*d12-d01*d02)*id
        if (u>=0) & (v>=0) & (u+v<=1)  # also include nodes on the boundary
            P = hcat(P, X[:,i]'')
        end
    end
    return P
end

"""
Determine is point P inside or on boudary of polygon X.

http://paulbourke.net/geometry/polygonmesh/#insidepoly
"""
function is_point_inside_convex_polygon(P, X)
    x, y = P
    for i=1:length(X)
        x0, y0 = X[i]
        x1, y1 = X[mod(i, length(X))+1]
        if (y-y0)*(x1-x0) - (x-x0)*(y1-y0) < 0
            return false
        end
    end
    return true
end

function get_points_inside_convex_polygon(pts, X)
    # TODO: Make more readable
    X2 = [X[:,i] for i=1:size(X,2)]
    c = filter(P->is_point_inside_convex_polygon(P, X2), [pts[:,i] for i=1:size(pts, 2)])
    return length(c) == 0 ? zeros(2, 0) : hcat(c...)
end

""" Return unique objects with some given tolerance. This is used in next function
    because traditional unique() command returns row vectors as non-unique if they
    differs only a "little".
"""
function uniquetol(P, dim::Int; args...)
    @assert dim == 2
    items = Vector[P[:,i] for i=1:size(P,dim)]
    new_items = Vector[]
    for item in items
        has_found = false
        for new_item in new_items
            if isapprox(ForwardDiff.get_value(item), ForwardDiff.get_value(new_item); args...)
                has_found = true
                break
            end
        end
        if !has_found
            push!(new_items, item)
        end
    end
    return reshape([new_items...;], length(new_items[]), length(new_items))
end


"""
Make polygon clipping of shapes S and M.

Parameters
----------
S::Array{Float64, 2}
M::Array{Float64, 2}
    Shapes to clip. Needs to be triangles at the moment.

Returns
-------
Array{Float64, 2}, Array{Float64, 2}
- Polygon vertices in 2×n matrix, sorted in counter-clockwise order.
- 3×3 "neighbouring" matrix, see example.

Examples
--------
julia> S = [0 0; 3 0; 0 3]'
julia> M = [-1 1; 2 -1/2; 2 2]'
julia> P, n = clip_polygon(S, M)
julia> P
2x6 Array{Float64,2}:
 0.0  1.0  2.0  2.0  1.25  0.0
 0.5  0.0  0.0  1.0  1.75  1.33333,
julia> n
3x3 Array{Int64,2}:
 1  0  1 <- first edge of M ([-1 1; 2 -1/2]') intersects with edges 1 and 3 of S ([0 0; 3 0]' and [0 3; 0 0]')
 1  1  0 <- second edge of M ([2 -1/2; 2 2]') intersects with edges 1 and 2 of S
 0  1  1 <- third edge of M ([2 2; -1 1]') intersects with edgse 2 and 3 of S

"""
function clip_polygon(S::Matrix, M::Matrix)
    P1, neighbours = get_edge_intersections(M, S)
    #P2 = get_points_inside_triangle(M, S)
    #P3 = get_points_inside_triangle(S, M)
    P2 = get_points_inside_convex_polygon(M, S)
    P3 = get_points_inside_convex_polygon(S, M)
#   info("polygon clipping: P1 = $P1")
#   info("polygon clipping: P2 = $P2")
#   info("polygon clipping: P3 = $P3")
#   info("hcat P = $P")
    P = hcat(P1, P2, P3)
    if length(P) == 0
        return nothing, nothing
    end
    P = uniquetol(P, 2)
    meanval = mean(P, 2)
    tmp = P .- meanval
    angles = atan2(tmp[2,:], tmp[1,:])
    angles = reshape(angles, length(angles))
    order = sortperm(angles)
    return P[:, order], neighbours
end


"""
Calculate polygon geometric center point

Parameters
----------
P::Array{Float64, 2}
    Polygon vertices in 2×n matrix

Returns
-------
Array{Float63, 2}
    Center point

Examples
--------
julia> P
2x6 Array{Float64,2}:
 0.0  1.0  2.0  2.0  1.25  0.0
 0.5  0.0  0.0  1.0  1.75  1.33333,
julia> C = get_polygon_cp(P)
2x1 Array{Float64,2}:
 1.039740
 0.804701

"""
function calculate_polygon_centerpoint(P::Matrix)
    n = size(P, 2)
    A = 0.0
    for i=1:n
        A += 1/2*(P[1,i]*P[2,mod(i,n)+1] - P[1,mod(i,n)+1]*P[2,i])
    end
    Cx = 0.0
    Cy = 0.0
    for i=1:n
        inext = mod(i, n)+1
        Cx += 1/(6*A)*(P[1,i] + P[1,inext])*(P[1,i]*P[2,inext] - P[1,inext]*P[2,i])
        Cy += 1/(6*A)*(P[2,i] + P[2,inext])*(P[1,i]*P[2,inext] - P[1,inext]*P[2,i])
    end
    return [Cx, Cy]
end

"""
Project point from auxiliary plane to parametric surface given by (ξ₁, ξ₂)

Parameters
----------
p::Array{Float64,1}
    point in auxiliary plane, in (n,t1,t2) coordinate system
x0::Array{Float64,1}
    origo of auxiliary plane cs
Q::Array{Float64,2}
    basis of auxiliary plane cs
x::Array{Float64,2}
    surface node coords
basis::Array{Float64,2}
    surface basis functions
dbasis::Array{Float64,2}
    partial derivatives of surface basis functions

Returns
-------
Array{Float64,2}
    solution vector (d, ξ₁, ξ₂) where d is distance to surface

Examples
--------
Define surface with node points, basis + dbasis

julia> xquad = [
...     -2.5 -2.0 1.0
...      2.5 -2.0 0.7
...      2.0  2.3 0.0
...     -2.0  2.0 1.0]'
julia> basis(xi) = [
...     (1-xi[1])(1-xi[2])/4
...     (1+xi[1])(1-xi[2])/4
...     (1+xi[1])(1+xi[2])/4
...     (1-xi[1])(1+xi[2])/4]
julia> dbasis(xi) = [
...     -(1-xi[2])/4    -(1-xi[1])/4
...      (1-xi[2])/4    -(1+xi[1])/4
...      (1+xi[2])/4     (1+xi[1])/4
...     -(1+xi[2])/4     (1-xi[1])/4]

We aim to find point p, which we first project to auxiliary plane defined as following
julia> p = [-2.5 -2.0 1.0]'
julia> x0 = [0.0 0.075 0.675]'
julia> Q = [
...     0.1485860   0.9888990   0.0000000
...     0.0784519  -0.0117877   0.9968480
...     0.9857830  -0.1481180  -0.0793325]

Our projected point is therefore
julia> n = Q[:,1] # first component is normal direction
julia> ph = project_node_to_auxiliary_plane(p, x0, n)
julia> ph = Q'(ph-x0)
julia> ph
3x1 Array{Float64,2}:
  1.33264e-7
 -2.49593
 -2.09424

Our point ph is now in auxiliary plane in n,t1,t2 coordinate system. Next we
project it back to surface defined by xquad*basis

julia> theta = project_point_from_plane_to_surface(ph, x0, Q, xquad, basis, dbasis)
julia> theta
3x1 Array{Float64,2}:
 -0.213874
 -0.999999
 -1.0

We see that our ξ₁ = ξ₂ = -1 so we found first point of xquad
[-2.5 -2.0 1.0]' correctly.

julia> xquad*basis(theta[2:3])
3-element Array{Float64,1}:
 -2.5
 -2.0
  1.0

"""
function project_point_from_plane_to_surface{E}(p::Vector, x0::Vector, Q::Matrix,
    element::Element{E}, time::Real; max_iterations::Int=10, iter_tol::Float64=1.0e-9)
    x = element("geometry", time)
    return project_point_from_plane_to_surface(p, x0, Q, element, x, time;
            max_iterations=max_iterations, iter_tol=iter_tol)
end
function project_vertex_from_plane_to_surface{E}(p::Vector, x0::Vector, Q::Matrix,
    element::Element{E}, x, time::Real; max_iterations::Int=10, iter_tol::Float64=1.0e-9)
    basis(xi) = get_basis(E, xi)
    dbasis(xi) = get_dbasis(E, xi)
    ph = Q*[0; p] + x0
    n = Q[:,1]
    b(theta) = ph + theta[1]*n - basis(theta[2:3])*x
    J(theta) = [n -dbasis(theta[2:3])*x]
    theta = zeros(3)
    dtheta = zeros(3)
    for i=1:max_iterations
        # FIXME: gives NaN if partials in J
        dtheta = ForwardDiff.get_value(J(theta)) \ -b(theta)
        theta += dtheta
        if norm(ForwardDiff.get_value(dtheta)) < iter_tol
            return theta
        end
    end
    info("failed to project vertex from auxiliary plane back to surface")
    info("element type: $E")
    info("element connectivity: $(get_connectivity(element))")
    info("auxiliary plane: x0 = $(ForwardDiff.get_value(x0)), Q = $(ForwardDiff.get_value(Q))")
    info("point coordinates on plane: $(ForwardDiff.get_value(p))")
    info("element geometry: $(ForwardDiff.get_value(x.data))")
    info("ph: $(ForwardDiff.get_value(ph))")
    info("normal direction: $(ForwardDiff.get_value(n))")
    info("parameter vector before giving up: $(ForwardDiff.get_value(theta))")
    info("increment in parameter vector before giving up: $(ForwardDiff.get_value(dtheta))")
    info("b([0.0, 0.0, 0.0]) = $(ForwardDiff.get_value(b([0.0, 0.0, 0.0])))")
    info("J([0.0, 0.0, 0.0]) = $(ForwardDiff.get_value(J([0.0, 0.0, 0.0])))")

    info("iterations were")
    theta = zeros(3)
    dtheta = zeros(3)
    for i=1:max_iterations
        info("iter $i, theta = $(ForwardDiff.get_value(theta))")
        info("b = $(ForwardDiff.get_value(b(theta)))")
        info("J = $(ForwardDiff.get_value(J(theta)))")
        dtheta = ForwardDiff.get_value(J(theta)) \ -b(theta)
        info("dtheta = $(ForwardDiff.get_value(dtheta))")
        theta += dtheta
        if norm(dtheta) < iter_tol
            return theta
        end
    end

    error("project_point_to_surface: did not converge in $max_iterations iterations!")
end

typealias MortarElements3D Union{Tri3, Quad4}

function assemble!{E<:MortarElements3D}(assembly::Assembly, problem::Problem{Mortar},
                                        slave_element::Element{E}, time::Real, ::Type{Val{:total}})
    assemble!(assembly, problem, slave_element, time, Val{problem.properties.formulation})
end

function assemble!{E<:MortarElements3D}(assembly::Assembly, problem::Problem{Mortar},
                                        slave_element::Element{E}, time::Real, ::Type{Val{:total}})
    haskey(slave_element, "master elements") || return
    field_dim = get_unknown_field_dimension(problem)
    field_name = get_parent_field_name(problem)
    slave_dofs = get_gdofs(slave_element, field_dim)

    props = problem.properties
    if props.formulation == :Standard && props.normal_condition == :Contact
        error("for contact choose Dual formulation.""")
    end

    # create auxiliary plane and project slave nodes to it
    # x0 = origo, Q = local basis
    x0, Q = create_auxiliary_plane(slave_element, time)

    # 1. project slave nodes to auxiliary plane
    Sl = Vector{Float64}[]
    for p in slave_element("geometry", time)
        push!(Sl, project_point_to_auxiliary_plane(p, x0, Q))
    end
    S = hcat(Sl...)

    for master_element in slave_element["master elements"]

        # if distance between elements is "far enough" cannot expect contact
        if (props.normal_condition == :Contact) || props.inequality_constraints
            slave_midpoint = slave_element("geometry", [0.0, 0.0], time)
            master_midpoint = master_element("geometry", [0.0, 0.0], time)
            if norm(slave_midpoint - master_midpoint) > props.minimum_distance
                continue
            end
        end

        master_dofs = get_gdofs(master_element, field_dim)

        # 2. project master nodes to auxiliary plane
        M = Vector{Float64}[]
        for p in master_element("geometry", time)
            push!(M, project_point_to_auxiliary_plane(p, x0, Q))
        end
        M = hcat(M...)

        # 3. create polygon clipping on auxiliary plane
        P = nothing
        neighbours = nothing
        try
            P, neighbours = clip_polygon(S, M)
        catch
            info("polygon clipping failed")
            info("S = ")
            dump(S)
            info("M = ")
            dump(M)
            info("original Sl = ")
            info(Sl)
            error("cannot continue")
        end
        isa(P, Void) && continue # no clipping

        # shared edge but no shared volume. skipping
        size(P, 2) < 3 && continue

        C = calculate_polygon_centerpoint(P)
        npts = size(P, 2) # number of vertices in polygon

        # loop vertices and create temporary integrate cells
        # TODO: basically when npts == 3 or npts == 4 we could integrate without splitting to cells.
        nnodes = size(slave_element, 2)
        C1S3 = zeros(3*nnodes, 3*nnodes)
        C1M3 = zeros(3*nnodes, 3*nnodes)

        for pnt=1:npts # integration of mortar matrices begin
            cell = Field(Vector{Float64}[C, P[:,pnt], P[:,mod(pnt,npts)+1]])

            # calculate slave side projection matrix D
            # construct dual basis
            Ae = zeros(nnodes, nnodes)
            De = zeros(nnodes, nnodes)
            Me = zeros(nnodes, nnodes)
            if problem.properties.formulation == :Dual # Construct dual basis
                for ip in get_integration_points(Tri3, Val{5})
                    N = get_basis(Tri3, ip.xi)
                    xi = vec(N*cell)
                    theta = project_point_from_plane_to_surface(xi, x0, Q, slave_element, time)
                    xi_slave = theta[2:3]
                    N1 = slave_element(xi_slave, time)
                    # jacobian determinant on integration cell
                    dNC = get_dbasis(Tri3, ip.xi)
                    JC = sum([kron(dNC[:,j], cell[j]') for j=1:length(cell)])
                    wC = ip.weight*det(JC)
                    De += wC*diagm(vec(N1))
                    Me += wC*N1'*N1
                end
                Ae = De*inv(Me)
            end
            for i=1:field_dim
                C1S3[i:field_dim:end,i:field_dim:end] += De
            end

            # Calculate master side projection matrix M
            for ip in get_integration_points(Tri3, Val{5})
                # gauss point in auxiliary plane
                #N = get_basis(E, ip.xi)
                N = get_basis(Tri3, ip.xi)
                xi = vec(N*cell)  # xi defined in auxilary plane

                # find projection of gauss point to master and slave elements
                theta1 = project_point_from_plane_to_surface(xi, x0, Q, slave_element, time)
                theta2 = project_point_from_plane_to_surface(xi, x0, Q, master_element, time)
                xi_slave = theta1[2:3]
                xi_master = theta2[2:3]

                # evaluate shape functions values in gauss point and add contribution to matrices
                N1 = slave_element(xi_slave, time)
                N2 = master_element(xi_master, time)

                # jacobian determinant on integration cell
                dNC = get_dbasis(Tri3, ip.xi)
                JC = sum([kron(dNC[:,j], cell[j]') for j=1:length(cell)])
                wC = ip.weight*det(JC)

                # extend matrices according to the problem dimension (3)
                @assert length(slave_dofs) == length(master_dofs)
                Me = wC*Ae*N1'*N2
                for k=1:field_dim
                    C1M3[k:field_dim:end,k:field_dim:end] += Me
                end
            end
        end  # integration of mortar matrices done.

        # constraints in normal-tangential direction and initial weighted gap
        X1 = vec(slave_element("geometry", time))
        X2 = vec(master_element("geometry", time))
        Q_ = slave_element("normal-tangential coordinates", time)
        Z = zeros(3, 3)
        if nnodes == 3
            Q3 = [Q Z Z; Z Q Z; Z Z Q]
        elseif nnodes == 4
            Q3 = [Q Z Z Z; Z Q Z Z; Z Z Q Z; Z Z Z Q]
        end
        D3 = zeros(3*nnodes, 3*nnodes)
        C2S3 = Q3'*C1S3
        C2M3 = Q3'*C1M3
        G = -(C2S3*X1 - C2M3*X2)

        # complementarity condition
        if haskey(slave_element, "displacement")
            u1 = vec(slave_element("displacement", time))
        else
            u1 = zeros(3*nnodes)
        end
        if haskey(master_element, "displacement")
            u2 = vec(master_element("displacement", time))
        else
            u2 = zeros(3*nnodes)
        end
        x1 = X1 + u1
        x2 = X2 + u2
        if  haskey(slave_element, "reaction force")
            la = vec(slave_element("reaction force", time))
        else
            la = zeros(3*nnodes)
        end
        g = -(C2S3*x1 - C2M3*x2)
        c = Q3'*la - g
        inactive_nodes = find(c[1:field_dim:end] .<= 0)
        active_nodes = find(c[1:field_dim:end] .> 0)

        # normal constraint: remove inactive nodes if normal condition is set to contact
        if problem.properties.normal_condition == :Contact
            for j in inactive_nodes
                dofs = [3*(j-1)+1, 3*(j-1)+2, 3*(j-1)+3]
                G[dofs] = 0
                C1S3[dofs,:] = 0
                C1M3[dofs,:] = 0
                C2S3[dofs,:] = 0
                C2M3[dofs,:] = 0
            end
        end

        # tangential constraint: stick or slip
        if problem.properties.tangential_condition == :Slip
            D3 = copy(C2S3)
            D3[1:field_dim:end, :] = 0
            C2S3[2:field_dim:end, :] = 0
            C2M3[2:field_dim:end, :] = 0
            C2S3[3:field_dim:end, :] = 0
            C2M3[3:field_dim:end, :] = 0
        end

        # add contributions
        add!(assembly.C1, slave_dofs, slave_dofs, C1S3)
        add!(assembly.C1, slave_dofs, master_dofs, -C1M3)
        add!(assembly.C2, slave_dofs, slave_dofs, C2S3)
        add!(assembly.C2, slave_dofs, master_dofs, -C2M3)
        add!(assembly.D, slave_dofs, slave_dofs, D3)
        add!(assembly.c, slave_dofs, c)
        add!(assembly.g, slave_dofs, G)
    end
end

