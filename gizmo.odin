package workbench

import "core:fmt"

import "basic"
import "types"
import "logging"

import "platform"
import "collision"
import "math"
import "gpu"
import "external/imgui"
import "external/gl"

direction_unary := [3]Vec3{ Vec3{1,0,0}, Vec3{0,1,0}, Vec3{0,0,1}  };
direction_color := [4]Colorf{ Colorf{1,0,0,1}, Colorf{0,1,0,1}, Colorf{0,0,1,1}, Colorf{1,1,1,1} };
selection_color := Colorf{1,1,0.1,1};

Gizmo_State :: struct {
    size: f32,
    last_point: Vec3,
    move_type: Move_Type,
    mouse_pixel_position_on_rotate_clicked: Vec2,
    rotation_on_rotate_clicked: Quat,
}

operation: Operation;
manipulation_mode: Manipulation_Mode;
gizmo_mesh: Model;

init_gizmo :: proc() {
    add_mesh_to_model(&gizmo_mesh, []Vertex3D{}, []u32{}, {}, {});
}

gizmo_new_frame :: proc() {
    clear(&im_gizmos);
}

gizmo_manipulate :: proc(position: ^Vec3, scale: ^Vec3, rotation: ^Quat, using gizmo_state: ^Gizmo_State) {
    rotation^ = quat_norm(rotation^);

    if !platform.get_input(.Mouse_Left) {
        move_type = .NONE;
    }

    camera_pos := main_camera.position;
    origin := position^;

    direction_to_camera := norm(origin - camera_pos);

    plane_dist := dot(-direction_to_camera, (camera_pos - origin)) * -1;
    translation_vec := -direction_to_camera * plane_dist;
    plane_point := origin + translation_vec;

    size = magnitude(plane_point - camera_pos) * 0.05;

    if move_type == .NONE && !platform.get_input(.Mouse_Button_2) {
        if platform.get_input_down(.Q) do if manipulation_mode == .World do manipulation_mode = .Local else do manipulation_mode = .World;
        if platform.get_input_down(.W) do operation = .Translate;
        if platform.get_input_down(.E) do operation = .Rotate;
        if platform.get_input_down(.R) do operation = .Scale;
        if platform.get_input_down(.T) do operation = .None;
    }



    #partial
    switch operation {
        case .Translate: {
            mouse_world := get_mouse_world_position(main_camera, platform.mouse_unit_position);
            mouse_direction := get_mouse_direction_from_camera(main_camera, platform.mouse_unit_position);


            was_active := move_type != .NONE;
            if move_type == .NONE {
                // arrows
                current_closest := max(f32);
                outer: for i in 0..2 {
                    center_on_screen := world_to_unit(origin, main_camera);
                    tip_on_screen := world_to_unit(origin + rotated_direction(rotation^, direction_unary[i]) * size, main_camera);
                    // draw_debug_line(origin, origin + rotated_direction(rotation^, direction_unary[i]) * size, Colorf{1, 0, 1, 1});

                    p := collision.closest_point_on_line(to_vec3(platform.mouse_unit_position), center_on_screen, tip_on_screen);
                    dist := length(p - to_vec3(platform.mouse_unit_position));
                    if dist < 0.005 && dist < current_closest {
                        current_closest = dist;
                        move_type = Move_Type.MOVE_X + Move_Type(i);
                    }
                }
            }

            // planes
            if move_type == .NONE {
                for i in  0..2 {
                    dir   := rotated_direction(rotation^, direction_unary[i]) * size;
                    dir_x := rotated_direction(rotation^, direction_unary[(i+1) %3]) * size;
                    dir_y := rotated_direction(rotation^, direction_unary[(i+2) %3]) * size;

                    quad_size: f32 = 0.5;
                    quad_origin := origin + (dir_y + dir_x) * 0.2;

                    plane_norm := rotated_direction(rotation^, direction_unary[i]);

                    diff := mouse_world - quad_origin;
                    prod := dot(diff, plane_norm);
                    prod2 := dot(mouse_direction, plane_norm);
                    prod3 := prod / prod2;
                    q_i := mouse_world - mouse_direction * prod3;

                    q_p1 := quad_origin;
                    q_p2 := quad_origin + (dir_y + dir_x)*quad_size;
                    min := Vec3{ min(q_p1.x, q_p2.x), min(q_p1.y, q_p2.y), min(q_p1.z, q_p2.z) };
                    max := Vec3{ max(q_p1.x, q_p2.x), max(q_p1.y, q_p2.y), max(q_p1.z, q_p2.z) };

                    contains :=
                        q_i.x >= min.x &&
                        q_i.x <= max.x &&
                        q_i.y >= min.y &&
                        q_i.y <= max.y &&
                        q_i.z >= min.z &&
                        q_i.z <= max.z;

                    if contains {
                        move_type = Move_Type.MOVE_YZ + Move_Type(i);
                        break;
                    }
                }
            }

            if move_type != .NONE {
                plane_norm: Vec3;
                #partial
                switch move_type {
                    case .MOVE_X:  plane_norm = rotated_direction(rotation^, Vec3{0, 0, 1});
                    case .MOVE_Y:  plane_norm = rotated_direction(rotation^, Vec3{0, 0, 1});
                    case .MOVE_Z:  plane_norm = rotated_direction(rotation^, Vec3{1, 0, 0});
                    case .MOVE_XY: plane_norm = rotated_direction(rotation^, Vec3{0, 0, 1});
                    case .MOVE_YZ: plane_norm = rotated_direction(rotation^, Vec3{1, 0, 0});
                    case .MOVE_ZX: plane_norm = rotated_direction(rotation^, Vec3{0, 1, 0});
                    case: panic(fmt.tprint(move_type)); // note(josh): this was a return
                }

                diff := mouse_world - origin;
                prod := dot(diff, plane_norm);
                prod2 := dot(mouse_direction, plane_norm);
                prod3 := prod / prod2;
                intersect := mouse_world - mouse_direction * prod3;

                if !was_active {
                    last_point = intersect;
                }

                if platform.get_input(.Mouse_Left) {
                    full_delta_move := intersect - last_point;
                    delta_move: Vec3;

                    #partial
                    switch move_type {
                        case .MOVE_X: {
                            delta_move.x = dot(full_delta_move, rotated_direction(rotation^, direction_unary[0]));
                            break;
                        }
                        case .MOVE_Y: {
                            delta_move.y = dot(full_delta_move, rotated_direction(rotation^, direction_unary[1]));
                            break;
                        }
                        case .MOVE_Z: {
                            delta_move.z = dot(full_delta_move, rotated_direction(rotation^, direction_unary[2]));
                            break;
                        }
                        case .MOVE_YZ: {
                            delta_move.y = dot(full_delta_move, rotated_direction(rotation^, direction_unary[1]));
                            delta_move.z = dot(full_delta_move, rotated_direction(rotation^, direction_unary[2]));
                            break;
                        }
                        case .MOVE_ZX: {
                            delta_move.x = dot(full_delta_move, rotated_direction(rotation^, direction_unary[0]));
                            delta_move.z = dot(full_delta_move, rotated_direction(rotation^, direction_unary[2]));
                            break;
                        }
                        case .MOVE_XY: {
                            delta_move.x = dot(full_delta_move, rotated_direction(rotation^, direction_unary[0]));
                            delta_move.y = dot(full_delta_move, rotated_direction(rotation^, direction_unary[1]));
                            break;
                        }
                        case: {
                            delta_move = full_delta_move;
                        }
                    }

                    position^ += rotated_direction(rotation^, delta_move);
                    last_point = intersect;
                }
            }

            break;
        }
        case .Rotate: {
            mouse_world := get_mouse_world_position(main_camera, platform.mouse_unit_position);
            mouse_direction := get_mouse_direction_from_camera(main_camera, platform.mouse_unit_position);

            if move_type == .NONE {

                plane_intersect :: proc(plane_pos, plane_normal: Vec3, ray_pos, ray_direction: Vec3) -> (Vec3, bool) {
                    directions_dot := dot(plane_normal, ray_direction);
                    if directions_dot == 0 { // plane and ray are parallel
                        return {}, false;
                    }

                    plane_to_ray := norm(ray_pos - plane_pos);
                    plane_to_ray_dot := dot(plane_to_ray, plane_normal);
                    if plane_to_ray_dot > 0 { // the ray origin is in front of the plane
                        if directions_dot > 0 {
                            return {}, false;
                        }
                    }
                    else { // the ray origin is behind the plane
                        if directions_dot < 0 {
                            return {}, false;
                        }
                    }

                    diff := ray_pos - plane_pos;
                    return (diff + plane_pos) + (ray_direction * (-dot(diff, plane_normal) / dot(ray_direction, plane_normal))), true;
                }

                closest_plane_distance := max(f32);
                closest_index := -1;
                for i in 0..2 {
                    dir := rotated_direction(rotation^, direction_unary[i]);
                    intersect_point, ok := plane_intersect(position^, dir, camera_pos, mouse_direction);
                    if ok && length(position^ - intersect_point) < size*2 { // todo(josh): I don't think we should need a `*2` here, `size` should be the radius of the rotation gizmo I think?
                        dist := length(camera_pos - intersect_point);
                        if dist < closest_plane_distance {
                            closest_plane_distance = dist;
                            closest_index = i;
                        }
                    }
                }

                if closest_index >= 0 {
                    mouse_pixel_position_on_rotate_clicked = platform.mouse_screen_position;
                    rotation_on_rotate_clicked = rotation^;

                    move_type = .ROTATE_X + Move_Type(closest_index);
                }
            }



            if move_type != .NONE {
                sensitivity : f32 = 0.01;
                if platform.get_input(.Left_Alt) do sensitivity *= 0.5;
                else if platform.get_input(.Left_Shift) do sensitivity *= 2;
                rads := (platform.mouse_screen_position.x - mouse_pixel_position_on_rotate_clicked.x) * sensitivity;

                dir_idx := -1;
                #partial
                switch move_type {
                    case .ROTATE_X: dir_idx = 0;
                    case .ROTATE_Y: dir_idx = 1;
                    case .ROTATE_Z: dir_idx = 2;
                }
                rot := mul(Quat{0, 0, 0, 1}, axis_angle(rotated_direction(rotation_on_rotate_clicked, direction_unary[dir_idx]), rads));
                rotation^ = mul(rot, rotation_on_rotate_clicked);
            }

            break;
        }
        case .Scale: {
            break;
        }
    }

    append(&im_gizmos, IM_Gizmo{position^, scale^, rotation^, gizmo_state^});
}

rotated_direction :: proc(entity_rotation: Quat, direction: Vec3) -> Vec3 {
    if manipulation_mode == .World {
        return direction;
    }
    assert(manipulation_mode == .Local);
    return quat_mul_vec3(entity_rotation, direction);
}

IM_Gizmo :: struct {
    position: Vec3,
    scale: Vec3,
    rotation: Quat,
    state: Gizmo_State,
}

im_gizmos: [dynamic]IM_Gizmo;

gizmo_render :: proc() {
    PUSH_RENDERMODE(.World);
    PUSH_GPU_ENABLED(.Cull_Face, false);
    gpu.use_program(get_shader(&wb_catalog, "default"));

    for g in im_gizmos {
        g := g;

        using g;
        using g.state;

        rotation = quat_norm(rotation);
        if manipulation_mode == .World {
            rotation = Quat{0, 0, 0, 1};
        }

        #partial
        switch operation {
            case .Translate: {
                detail :: 10;

                verts: [detail*4]Vertex3D;
                head_verts: [detail*3]Vertex3D;
                quad_verts : [4]Vertex3D;

                for i in 0..2 {
                    dir   := direction_unary[i] * size;
                    dir_x := direction_unary[(i+1) % 3] * size;
                    dir_y := direction_unary[(i+2) % 3] * size;

                    color := direction_color[i];

                    if move_type == Move_Type.MOVE_X + Move_Type(i) || move_type == Move_Type.MOVE_YZ + Move_Type(i) {
                        color = selection_color;
                    }

                    RAD :: 0.03;

                    step := 0;
                    for i := 0; i < int(detail)*4; i+=4 {

                        theta := TAU * f32(step) / f32(detail);
                        theta2 := TAU * f32(step+1) / f32(detail);

                        pt := dir_x * cos(theta) * RAD;
                        pt += dir_y * sin(theta) * RAD;
                        pt += dir;
                        verts[i] = Vertex3D {
                            pt, {}, color, {}, {}, {}
                        };

                        pt = dir_x * cos(theta2) * RAD;
                        pt  += dir_y *sin(theta2) * RAD;
                        pt += dir;
                        verts[i+1] = Vertex3D {
                            pt, {}, color, {}, {}, {}
                        };

                        pt = dir_x * cos(theta) * RAD;
                        pt += dir_y *sin(theta) * RAD;
                        verts[i+2] = Vertex3D{
                            pt, {}, color, {}, {}, {}
                        };

                        pt = dir_x * cos(theta2) * RAD;
                        pt += dir_y *sin(theta2) * RAD;
                        verts[i+3] = Vertex3D{
                            pt, {}, color, {}, {}, {}
                        };

                        step += 1;
                    }

                    rad2 : f32 = 0.1;
                    step = 0;
                    for i:= 0; i < int(detail*3); i+=3 {
                        theta := TAU * f32(step) / f32(detail);
                        theta2 := TAU * f32(step+1) / f32(detail);

                        pt := dir_x * cos(theta) * rad2;
                        pt += dir_y * sin(theta) * rad2;
                        pt += dir;
                        head_verts[i] = Vertex3D {
                            pt, {}, color, {}, {}, {}
                        };

                        pt = dir_x * cos(theta2) * rad2;
                        pt  += dir_y *sin(theta2) * rad2;
                        pt += dir;
                        head_verts[i+1] = Vertex3D {
                            pt, {}, color, {}, {}, {}
                        };

                        pt = (dir * 1.25);
                        head_verts[i+2] = Vertex3D{
                            pt, {}, color, {}, {}, {}
                        };

                        step += 1;
                    }

                    quad_size: f32 = 0.5;
                    quad_origin := (dir_y + dir_x) * 0.2;
                    quad_verts[0] = Vertex3D{quad_origin, {}, color, {}, {}, {} };
                    quad_verts[1] = Vertex3D{quad_origin + dir_y*quad_size, {}, color, {}, {}, {} };
                    quad_verts[2] = Vertex3D{quad_origin + (dir_y + dir_x)*quad_size, {}, color, {}, {}, {} };
                    quad_verts[3] = Vertex3D{quad_origin + dir_x*quad_size, {}, color, {}, {}, {} };

                    prev_draw_mode := main_camera.draw_mode;
                    main_camera.draw_mode = gpu.Draw_Mode.Triangle_Fan;
                    defer main_camera.draw_mode = prev_draw_mode;

                    update_mesh(&gizmo_mesh, 0, quad_verts[:], []u32{});
                    draw_model(gizmo_mesh, position, {1,1,1}, rotation, {}, {1, 1, 1, 1}, false);

                    update_mesh(&gizmo_mesh, 0, head_verts[:], []u32{});
                    draw_model(gizmo_mesh, position, {1,1,1}, rotation, {}, {1, 1, 1, 1}, false);

                    update_mesh(&gizmo_mesh, 0, verts[:], []u32{});
                    draw_model(gizmo_mesh, position, {1,1,1}, rotation, {}, {1, 1, 1, 1}, false);
                }
                break;
            }
            case .Rotate: {

                hoop_segments :: 52;
                tube_segments :: 10;
                hoop_radius :f32= 1.25;
                tube_radius :f32= 0.02;

                for direction in 0..2 {
                    dir_x := direction_unary[(direction+1) % 3] * size;
                    dir_y := direction_unary[(direction+2) % 3] * size;
                    dir_z := direction_unary[ direction       ] * size;
                    color := direction_color[ direction       ];

                    if move_type == Move_Type.ROTATE_X + Move_Type(direction) do color = selection_color;

                    verts: [hoop_segments * tube_segments * 6]Vertex3D;
                    vi := 0;

                    start : f32 = 0;
                    end : f32 = hoop_segments;

                    start_angle :f32= 0;
                    if direction == 0 do start_angle = -PI / 5;
                    if direction == 1 do start_angle = -PI / 5;
                    if direction == 2 do start_angle = -PI / 2.4 + PI / 5;

                    offset_rot : f32 = -PI/4;

                    for i : f32 = start; i < end; i+=1 {
                        angle_a1 := start_angle + TAU * (i-1) / hoop_segments;
                        angle_a2 := start_angle + TAU * i / hoop_segments;

                        for j : f32 = 0; j < tube_segments; j += 1 {
                            angle_b1 := TAU * ((j-1) / tube_segments);
                            angle_b2 := TAU * (j / tube_segments);

                            make_point :: proc(input: Vec3, dir_x, dir_y, dir_z: Vec3) -> Vec3 {
                                pt := dir_x * input.x;
                                pt += dir_y * input.y;
                                pt += dir_z * input.z;
                                return pt;
                            }

                            // triangle 1
                            pt1 := make_point(Vec3 {
                                (hoop_radius + tube_radius * cos(angle_b1)) * cos(angle_a1),
                                (hoop_radius + tube_radius * cos(angle_b1)) * sin(angle_a1),
                                tube_radius * sin(angle_b1)
                            }, dir_x, dir_y, dir_z);

                            pt2 := make_point(Vec3 {
                                (hoop_radius + tube_radius * cos(angle_b2)) * cos(angle_a1),
                                (hoop_radius + tube_radius * cos(angle_b2)) * sin(angle_a1),
                                tube_radius * sin(angle_b2)
                            }, dir_x, dir_y, dir_z);

                            pt3 := make_point(Vec3 {
                                (hoop_radius + tube_radius * cos(angle_b1)) * cos(angle_a2),
                                (hoop_radius + tube_radius * cos(angle_b1)) * sin(angle_a2),
                                tube_radius * sin(angle_b1)
                            }, dir_x, dir_y, dir_z);

                            // triangle 2
                            pt4 := make_point(Vec3 {
                                (hoop_radius + tube_radius * cos(angle_b2)) * cos(angle_a2),
                                (hoop_radius + tube_radius * cos(angle_b2)) * sin(angle_a2),
                                tube_radius * sin(angle_b2)
                            }, dir_x, dir_y, dir_z);

                            pt5 := make_point(Vec3 {
                                (hoop_radius + tube_radius * cos(angle_b1)) * cos(angle_a2),
                                (hoop_radius + tube_radius * cos(angle_b1)) * sin(angle_a2),
                                tube_radius * sin(angle_b1)
                            }, dir_x, dir_y, dir_z);

                            pt6 := make_point(Vec3 {
                                (hoop_radius + tube_radius * cos(angle_b2)) * cos(angle_a1),
                                (hoop_radius + tube_radius * cos(angle_b2)) * sin(angle_a1),
                                tube_radius * sin(angle_b2)
                            }, dir_x, dir_y, dir_z);

                            verts[vi] = Vertex3D { pt1, {}, color, {}, {}, {} };
                            vi += 1;
                            verts[vi] = Vertex3D { pt2, {}, color, {}, {}, {} };
                            vi += 1;
                            verts[vi] = Vertex3D { pt3, {}, color, {}, {}, {} };
                            vi += 1;

                            verts[vi] = Vertex3D { pt4, {}, color, {}, {}, {} };
                            vi += 1;
                            verts[vi] = Vertex3D { pt5, {}, color, {}, {}, {} };
                            vi += 1;
                            verts[vi] = Vertex3D { pt6, {}, color, {}, {}, {} };
                            vi += 1;
                        }
                    }

                    update_mesh(&gizmo_mesh, 0, verts[:], []u32{});
                    draw_model(gizmo_mesh, position, {1,1,1}, rotation, {}, {1, 1, 1, 1}, false);
                }

                break;
            }
            case .Scale: {
                break;
            }
        }
    }
}

Manipulation_Mode :: enum {
    World,
    Local,
}

Operation :: enum {
    Translate,
    Rotate,
    Scale,
    None,
}

Move_Type :: enum {
    NONE,

    MOVE_X, MOVE_BEGIN = MOVE_X,
    MOVE_Y,
    MOVE_Z,
    MOVE_YZ,
    MOVE_ZX,
    MOVE_XY, MOVE_END = MOVE_XY,

    ROTATE_X, ROTATE_BEGIN = ROTATE_X,
    ROTATE_Y,
    ROTATE_Z, ROTATE_END = ROTATE_Z,
}