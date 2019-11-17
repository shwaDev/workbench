package animation

using import "../math"
using import        "core:fmt"
using import        "../gpu"
using import        "../logging"
      import        "core:os"
      import        "core:sort"
      import rt     "core:runtime"
      import        "core:strings"
      import        "core:mem"

      import ai     "../external/assimp"

loaded_animations: map[string]Animation;

load_animations_from_ai_scene :: proc(scene: ^ai.Scene) {
    root_node := scene.root_node;

    ai_animations := mem.slice_ptr(scene.animations, cast(int) scene.num_animations);
    for _, anim_idx in ai_animations {
        ai_animation := ai_animations[anim_idx];

        animation := Animation{};
        animation.channels = make([dynamic]Anim_Channel, 0, int(ai_animation.num_channels));
        animation.name = strings.clone(strings.string_from_ptr(&ai_animation.name.data[0], cast(int)ai_animation.name.length));
        animation.duration = ai_animation.duration;
        animation.ticks_per_second = ai_animation.ticks_per_second;

        animation_channels := mem.slice_ptr(ai_animation.channels, cast(int) ai_animation.num_channels);
        for channel in animation_channels {
            node_name := strings.clone(strings.string_from_ptr(&channel.node_name.data[0], cast(int)channel.node_name.length));

            pos_frames := make([dynamic]Anim_Frame, 0, channel.num_position_keys);
            scale_frames := make([dynamic]Anim_Frame, 0, channel.num_scaling_keys);
            rot_frames := make([dynamic]Anim_Frame, 0, channel.num_rotation_keys);

            position_keys := mem.slice_ptr(channel.position_keys, cast(int) channel.num_position_keys);
            for pos_key in position_keys {
                append(&pos_frames, Anim_Frame{
                    pos_key.time,
                    Anim_Frame_Pos {ai_to_wb(pos_key.value)},
                });
            }

            rotation_keys := mem.slice_ptr(channel.rotation_keys, cast(int) channel.num_rotation_keys);
            for rot_key in rotation_keys {
                append(&rot_frames, Anim_Frame{
                    rot_key.time,
                    Anim_Frame_Rotation{ai_to_wb(rot_key.value)},
                });
            }

            scaling_keys := mem.slice_ptr(channel.scaling_keys, cast(int) channel.num_scaling_keys);
            for scale_key in scaling_keys {
                append(&scale_frames, Anim_Frame{
                    scale_key.time,
                    Anim_Frame_Scale{ai_to_wb(scale_key.value)},
                });
            }

            pos_frame_slice := pos_frames[:];
            sort.quick_sort_proc(pos_frame_slice, frame_sort_proc);

            scale_frame_slice := scale_frames[:];
            sort.quick_sort_proc(scale_frame_slice, frame_sort_proc);

            rot_frame_slice := rot_frames[:];
            sort.quick_sort_proc(rot_frame_slice, frame_sort_proc);

            append(&animation.channels, Anim_Channel{
                node_name,
                pos_frame_slice,
                scale_frame_slice,
                rot_frame_slice
            });
        }

        loaded_animations[animation.name] = animation;
    }
}

get_animation_data :: proc(mesh: Mesh, animation_name: string, time: f32, current_state: ^[dynamic]Mat4) {
    if !(animation_name in loaded_animations) do return;
    if len(current_state) < 1 do return;

    animation := loaded_animations[animation_name];

    for bone in mesh.skin.root_bones {
        read_bone_hierarchy(mesh, time, animation, bone, bone.parent_transform, current_state);
    }
}

read_bone_hierarchy :: proc(mesh: Mesh, time: f32, animation: Animation, bone: ^Bone, parent_transform: Mat4, current_state: ^[dynamic]Mat4) {
    channel, exists := get_animation_channel(animation, bone.name);
    if !exists do return;

    translation_transform := identity(Mat4);
    scale_transform := identity(Mat4);
    rotation_transform := identity(Mat4);

    // interpolate to position
    if len(channel.pos_frames) > 1 {
        pos_frame := 0;
        next_pos_frame := 0;
        pos_set := false;

        for frame, i in channel.pos_frames {
            if time > f32(frame.time) do break;

            if !pos_set {
                pos_frame = i;
                pos_set = true;
            } else if pos_frame != i {
                next_pos_frame = i;
                break;
            }
        }

        current_frame := channel.pos_frames[pos_frame];
        next_frame := channel.pos_frames[next_pos_frame];

        delta_time := f32(next_frame.time) - f32(current_frame.time);
        if delta_time == 0 do delta_time = 1;
        factor := (time - f32(current_frame.time)) / delta_time;

        start := current_frame.kind.(Anim_Frame_Pos).position;
        end := next_frame.kind.(Anim_Frame_Pos).position;
        delta := end - start;

        final_pos := start + (delta * factor);
        translation_transform[0][3] = final_pos.x;
        translation_transform[1][3] = final_pos.y;
        translation_transform[2][3] = final_pos.z;
    } else if len(channel.pos_frames) == 1 {
        f := channel.pos_frames[0];
        translation_transform[0][3] = f.kind.(Anim_Frame_Pos).position.x;
        translation_transform[1][3] = f.kind.(Anim_Frame_Pos).position.y;
        translation_transform[2][3] = f.kind.(Anim_Frame_Pos).position.z;
    }

    // interpolate scale
    if len(channel.scale_frames) > 1 {
        scale_frame := 0;
        next_scale_frame := 0;
        scale_set := false;
        for frame, i in channel.scale_frames {
            if time > f32(frame.time) do break;

            if !scale_set {
                scale_frame = i;
                scale_set = true;
            } else if scale_frame != i {
                next_scale_frame = i;
                break;
            }
        }
        current_frame := channel.scale_frames[scale_frame];
        next_frame := channel.scale_frames[next_scale_frame];

        delta_time := f32(next_frame.time) - f32(current_frame.time);
        if delta_time == 0 do delta_time = 1;
        factor := (time - f32(current_frame.time)) / delta_time;

        start := current_frame.kind.(Anim_Frame_Scale).scale;
        end := next_frame.kind.(Anim_Frame_Scale).scale;
        delta := end - start;

        final_scale := start + (delta * factor);
        scale_transform[0][0] = final_scale.x;
        scale_transform[1][1] = final_scale.y;
        scale_transform[2][2] = final_scale.z;
    } else if len(channel.scale_frames) == 1 {
        f := channel.scale_frames[0];
        scale_transform[0][0] = f.kind.(Anim_Frame_Scale).scale.x;
        scale_transform[1][1] = f.kind.(Anim_Frame_Scale).scale.y;
        scale_transform[2][2] = f.kind.(Anim_Frame_Scale).scale.z;
    }

    // interpolate rotation
    if len(channel.rot_frames) > 1 {
        rot_frame := 0;
        next_rot_frame := 0;
        rot_set := false;

        for frame, i in channel.rot_frames {
            if time > f32(frame.time) do break;

            if !rot_set {
                rot_frame = i;
                rot_set = true;
            } else if rot_frame != i {
                next_rot_frame = i;
                break;
            }
        }

        current_frame := channel.rot_frames[rot_frame];
        next_frame := channel.rot_frames[next_rot_frame];

        delta_time := f32(next_frame.time) - f32(current_frame.time);
        if delta_time == 0 do delta_time = 1;
        factor := (time - f32(current_frame.time)) / delta_time;

        start := current_frame.kind.(Anim_Frame_Rotation).rotation;
        end := next_frame.kind.(Anim_Frame_Rotation).rotation;

        final_rot := quat_norm(slerp(start, end, factor));
        rotation_transform = quat_to_mat4(final_rot);

    } else if len(channel.rot_frames) == 1 {
        f := channel.rot_frames[0];
        rotation_transform = quat_to_mat4(f.kind.(Anim_Frame_Rotation).rotation);
    }

    node_transform : Mat4;
    if len(channel.rot_frames) == 0 && len(channel.pos_frames) == 0 && len(channel.scale_frames) == 0 {
        node_transform = bone.node_transform;
    } else {
        node_transform = mul(mul(translation_transform, rotation_transform), scale_transform);
    }

    global_transform := mul(parent_transform, node_transform);

    if bone.name in mesh.skin.name_mapping {
        bone_index := mesh.skin.name_mapping[bone.name];
        current_state[bone_index] = mul(mul(mesh.skin.global_inverse, global_transform), bone.offset);
    }

    for child in bone.children {
        read_bone_hierarchy(mesh, time, animation, child, global_transform, current_state);
    }
}

get_animation_channel :: proc(using anim: Animation, channel_id: string) -> (Anim_Channel, bool) {
    for channel in channels {
        if channel.name == channel_id {
            return channel, true;
        }
    }

    return {}, false;
}

frame_sort_proc :: proc(f1, f2: Anim_Frame) -> int {
    if f1.time > f2.time do return  1;
    if f1.time < f2.time do return -1;
    return 0;
}

ai_to_wb :: proc{ai_to_wb_vec3, ai_to_wb_quat};
ai_to_wb_vec3 :: proc(vec_in: ai.Vector3D) -> Vec3 {
    return Vec3{vec_in.x, vec_in.y, vec_in.z};
}

ai_to_wb_quat :: proc (quat_in: ai.Quaternion) -> Quat {
    return Quat{quat_in.x, quat_in.y, quat_in.z, quat_in.w};
}

Animation :: struct {
    name: string,
    channels: [dynamic]Anim_Channel,

    duration: f64,
    ticks_per_second: f64,
}

Anim_Channel :: struct {
    name: string,

    pos_frames: []Anim_Frame,
    scale_frames: []Anim_Frame,
    rot_frames: []Anim_Frame,
}

Anim_Frame :: struct {
    time: f64,

    kind: union {
        Anim_Frame_Pos,
        Anim_Frame_Rotation,
        Anim_Frame_Scale
    }
}

Anim_Frame_Pos :: struct {
    position: Vec3,
}
Anim_Frame_Rotation :: struct {
    rotation: Quat,
}
Anim_Frame_Scale :: struct {
    scale: Vec3,
}