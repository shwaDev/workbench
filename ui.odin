package workbench

using import "core:runtime"
using import "core:math"
using import "core:fmt"
      import "core:mem"

      import odingl "shared:odin-gl"

//
// UI state
//
hot:  IMGUI_ID = -1;
warm: IMGUI_ID = -1;
scroll_initial_cursor_position: Vec2;

IMGUI_ID :: int;

id_counts: map[string]int;

all_imgui_mappings: [dynamic]Location_ID_Mapping;

Location_ID_Mapping :: struct {
	id: IMGUI_ID,
	using loc: Source_Code_Location,
	index: int,
}

_update_ui :: proc(dt: f32) {
	// rendering_unit_space();
	// push_quad(shader_rgba, Vec2{0.1, 0.1}, Vec2{0.2, 0.2}, COLOR_BLUE, 100);

	clear(&id_counts);
	assert(len(ui_rect_stack) == 0 || len(ui_rect_stack) == 1);
	clear(&ui_rect_stack);
	ui_current_rect_pixels = Pixel_Rect{};
	ui_current_rect_unit = Unit_Rect{};

	ui_push_rect(0, 0, 1, 1, 0, 0, 0, 0);
	// ui_push_rect(0.3, 0.3, 0.7, 0.7, 0, 0, 0, 0);
}

get_id_from_location :: proc(loc: Source_Code_Location) -> IMGUI_ID {
	count, ok := id_counts[loc.file_path];
	if !ok {
		id_counts[loc.file_path] = 0;
		count = 0;
	}
	else {
		count += 1;
		id_counts[loc.file_path] = count;
	}

	// for val, idx in all_imgui_mappings {
	// 	if val.line != loc.line do continue;
	// 	if val.column != loc.column do continue;
	// 	if val.index != count do continue;
	// 	if val.file_path != loc.file_path do continue;
	// 	return val.id;
	// }

	id := len(all_imgui_mappings);
	mapping := Location_ID_Mapping{id, loc, count};
	append(&all_imgui_mappings, mapping);
	return 1;
}

//
// Positioning
//
Rect :: struct(kind: typeid) {
	x1, y1, x2, y2: kind,
}

Pixel_Rect :: Rect(int);
Unit_Rect  :: Rect(f32);

UI_Rect :: struct {
	pixel_rect: Pixel_Rect,
	unit_rect: Unit_Rect,
}

ui_rect_stack: [dynamic]UI_Rect;
ui_current_rect_unit:   Unit_Rect;
ui_current_rect_pixels: Pixel_Rect;

ui_push_rect :: inline proc(x1, y1, x2, y2: f32, top := 0, right := 0, bottom := 0, left := 0, pivot := Vec2{0.5, 0.5}, loc := #caller_location) {
	current_rect: Unit_Rect;
	if len(ui_rect_stack) == 0 {
		current_rect = Unit_Rect{0, 0, 1, 1};
	}
	else {
		current_rect = ui_current_rect_unit;
	}

	cur_w := current_rect.x2 - current_rect.x1;
	cur_h := current_rect.y2 - current_rect.y1;

	new_x1 := current_rect.x1 + (cur_w * x1) + ((cast(f32)left / cast(f32)current_window_width));
	new_y1 := current_rect.y1 + (cur_h * y1) + ((cast(f32)bottom / cast(f32)current_window_height));

	new_x2 := current_rect.x2 - cast(f32)cur_w * (1-x2) - ((cast(f32)right / cast(f32)current_window_width));
	new_y2 := current_rect.y2 - cast(f32)cur_h * (1-y2) - ((cast(f32)top / cast(f32)current_window_height));

	ui_current_rect_unit = Unit_Rect{new_x1, new_y1, new_x2, new_y2};
	cww := current_window_width;
	cwh := current_window_height;
	ui_current_rect_pixels = Pixel_Rect{cast(int)(ui_current_rect_unit.x1 * cast(f32)cww), cast(int)(ui_current_rect_unit.y1 * cast(f32)cwh), cast(int)(ui_current_rect_unit.x2 * cast(f32)cww), cast(int)(ui_current_rect_unit.y2 * cast(f32)cwh)};

	when DEVELOPER {
		maybe_add_ui_debug_rect(loc);
	}

	append(&ui_rect_stack, UI_Rect{ui_current_rect_pixels, ui_current_rect_unit});
}

ui_pop_rect :: inline proc(loc := #caller_location) -> UI_Rect {
	popped_rect := pop(&ui_rect_stack);
	rect := ui_rect_stack[len(ui_rect_stack)-1];
	ui_current_rect_pixels = rect.pixel_rect;
	ui_current_rect_unit = rect.unit_rect;

	when DEVELOPER {
		// maybe_add_ui_debug_rect(loc);
	}

	return popped_rect;
}

ui_scissor :: proc() {
	odingl.Enable(odingl.SCISSOR_TEST);
	odingl.Scissor(ui_current_rect_pixels.x1, ui_current_rect_pixels.y1, ui_current_rect_pixels.x2 - ui_current_rect_pixels.x1, ui_current_rect_pixels.y2 - ui_current_rect_pixels.y1);
}

ui_end_scissor :: proc() {
	odingl.Disable(odingl.SCISSOR_TEST);
	odingl.Scissor(0, 0, current_window_width, current_window_height);
}

// todo(josh): not sure if the grow_forever_on_* feature is worth the complexity
ui_fit_to_aspect :: inline proc(ww, hh: f32, grow_forever_on_x := false, grow_forever_on_y := false, loc := #caller_location) {
	assert((grow_forever_on_x == false || grow_forever_on_y == false), "Cannot have grow_forever_on_y and grow_forever_on_x both be true.");

	current_rect_width  := (cast(f32)ui_current_rect_pixels.x2 - cast(f32)ui_current_rect_pixels.x1);
	current_rect_height := (cast(f32)ui_current_rect_pixels.y2 - cast(f32)ui_current_rect_pixels.y1);

	assert(current_rect_height != 0);
	current_rect_aspect : f32 = cast(f32)(ui_current_rect_pixels.y2 - ui_current_rect_pixels.y1) / cast(f32)(ui_current_rect_pixels.x2 - ui_current_rect_pixels.x1);

	aspect := hh / ww;
	width:  f32;
	height: f32;
	if grow_forever_on_y || (!grow_forever_on_x && aspect < current_rect_aspect) {
		width  = current_rect_width;
		height = current_rect_width * aspect;
	}
	else if grow_forever_on_x || aspect >= current_rect_aspect {
		aspect = ww / hh;
		height = current_rect_height;
		width  = current_rect_height * aspect;
	}

	h_width  := cast(int)round(width  / 2);
	h_height := cast(int)round(height / 2);

	ui_push_rect(0.5, 0.5, 0.5, 0.5, -h_height, -h_width, -h_height, -h_width, {}, loc);
}

ui_end_fit_to_aspect :: inline proc(loc := #caller_location) {
	ui_pop_rect(loc);
}

//
// Directional Layout Groups
//

Directional_Layout_Group :: struct {
	x1, y1, x2, y2: f32,
	origin: Vec2,
	direction: Vec2,
	using _: struct { // runtime fields
		num_items_so_far: int,
	},
}

direction_layout_group_next :: proc(dlg: ^Directional_Layout_Group) {
	rect := ui_pop_rect();
}

//
// Scroll View
//

Scroll_View :: struct {
	cur_scroll: f32,
	is_held: bool,
}

scroll_view :: proc(x1, y1, x2, y2: f32, top := 0, right := 0, bottom := 0, left := 0, loc := #caller_location) {
	ui_push_rect(x1, y1, x2, y2, top, right, bottom, left, {}, loc);
	defer ui_pop_rect(loc);
}

//
// Grids
//

// Grid_Layout :: struct {
// 	w, h: int,

// 	using _: struct { // runtime fields
// 		cur_x, cur_y: int,
// 		// pixel padding, per element
// 		top, right, bottom, left: int,
// 	},
// }

// grid_start :: proc(ww, hh: int, x1, y1, x2, y2: f32, top := 0, right := 0, bottom := 0, left := 0) -> Grid_Layout {
// 	assert(ww == -1 || hh == -1 && ww != hh, "Can only pass a width _or_ a height, since we grow forever.");

// 	grid := Grid_Layout{ww, hh, {}};
// 	if grid.w == -1 {

// 	}
// 	else {
// 		assert(grid.h == -1, "???? We're supposed to protect against this in grid_start()");
// 	}
// 	return grid;
// }

// grid_next :: proc(grid: ^Grid_Layout) {
// 	if grid.w == -1 {
// 		grid.cur_h
// 	}
// 	else {
// 		assert(grid.h == -1, "???? We're supposed to protect against this in grid_start()");
// 	}
// }

// grid_start :: inline proc(grid: ^Grid_Layout) {
// 	ui_push_rect(0, 0, 1, 1); // doesn't matter, gets popped immediately

// 	grid.cur_x = 0;
// 	grid.cur_y = grid.h;

// 	grid_next(grid);
// }

// grid_next :: inline proc(grid: ^Grid_Layout) {
// 	grid.cur_y -= 1;
// 	if grid.cur_y == -1 {
// 		grid.cur_x += 1; // (grid.cur_x + 1) % grid.w;
// 		grid.cur_y = grid.h-1;
// 	}

// 	ui_pop_rect();
// 	x1 := cast(f32)grid.cur_x / cast(f32)grid.w;
// 	y1 := cast(f32)grid.cur_y / cast(f32)grid.h;
// 	ui_push_rect(x1, y1, x1 + 1.0 / cast(f32)grid.w, y1 + 1.0 / cast(f32)grid.h, grid.top, grid.right, grid.bottom, grid.left);
// }

// grid_end :: inline proc(grid: ^Grid_Layout) {
// 	ui_pop_rect();
// }

//
// Drawing
//

ui_draw_colored_quad :: proc[ui_draw_colored_quad_current, ui_draw_colored_quad_push];
ui_draw_colored_quad_current :: inline proc(color: Colorf) {
	rect := ui_current_rect_pixels;

	min := Vec2{cast(f32)rect.x1, cast(f32)rect.y1};
	max := Vec2{cast(f32)rect.x2, cast(f32)rect.y2};

	push_quad(pixel_to_viewport, shader_rgba, to_vec3(min), to_vec3(max), color);
}
ui_draw_colored_quad_push :: inline proc(color: Colorf, x1, y1, x2, y2: f32, top := 0, right := 0, bottom := 0, left := 0, loc := #caller_location) {
	ui_push_rect(x1, y1, x2, y2, top, right, bottom, left, {}, loc);
	ui_draw_colored_quad(color);
	ui_pop_rect(loc);
}

//
// Buttons
//

Button_Data :: struct {
	x1, y1, x2, y2: f32,
	top, right, bottom, left: int,

	on_hover: proc(button: ^Button_Data),
	on_pressed: proc(button: ^Button_Data),
	on_released: proc(button: ^Button_Data),
	on_clicked: proc(button: ^Button_Data),

	color: Colorf,
	clicked: u64,
}

default_button_data := Button_Data{0, 0, 1, 1, 0, 0, 0, 0, default_button_hover, default_button_pressed, default_button_released, nil, Colorf{0, 0, 0, 0}, 0};
default_button_hover :: proc(button: ^Button_Data) {

}
default_button_pressed :: proc(button: ^Button_Data) {
	tween(&button.x1, 0.05, 0.25, ease_out_quart);
	tween(&button.y1, 0.05, 0.25, ease_out_quart);
	tween(&button.x2, 0.95, 0.25, ease_out_quart);
	tween(&button.y2, 0.95, 0.25, ease_out_quart);
}
default_button_released :: proc(button: ^Button_Data) {
	tween(&button.x1, 0, 0.25, ease_out_back);
	tween(&button.y1, 0, 0.25, ease_out_back);
	tween(&button.x2, 1, 0.25, ease_out_back);
	tween(&button.y2, 1, 0.25, ease_out_back);
}

ui_button :: proc(using button: ^Button_Data, loc := #caller_location) -> bool {
	clicked_this_frame := button.clicked == frame_count;
	if clicked_this_frame {
		if button.on_clicked != nil {
			button.on_clicked(button);
		}
		return true;
	}

	// todo(josh): not sure about this, since the rect ends up being _much_ larger most of the time, maybe?
	full_button_rect_unit := ui_current_rect_unit;

	ui_push_rect(x1, y1, x2, y2, top, right, bottom, left, {}, loc);
	defer ui_pop_rect(loc);

	ui_draw_colored_quad(color);

	id := get_id_from_location(loc);
	cursor_in_rect := cursor_unit_position.y < full_button_rect_unit.y2 && cursor_unit_position.y > full_button_rect_unit.y1 && cursor_unit_position.x < full_button_rect_unit.x2 && cursor_unit_position.x > full_button_rect_unit.x1;

	if cursor_in_rect {
		if warm != id && hot == id {
			if button.on_pressed != nil {
				button.on_pressed(button);
			}
		}
		warm = id;
		if get_mouse_down(Mouse.Left) {
			if button.on_pressed != nil {
				button.on_pressed(button);
			}
			hot = id;
		}
	}
	else {
		if warm == id || hot == id {
			if button.on_released != nil {
				button.on_released(button);
			}
			warm = -1;
		}
	}

	if hot == id {
		if !get_mouse(Mouse.Left) {
			hot = -1;
			if warm == id {
				if button.on_released != nil {
					button.on_released(button);
				}
				if button.on_clicked != nil {
					button.on_clicked(button);
				}
				return true;
			}
		}
	}

	return false;
}

ui_click :: inline proc(using button: ^Button_Data) {
	clicked = frame_count;
}

ui_text :: proc(font: ^Font, str: string, size: f32, color: Colorf, center_vertically := true, center_horizontally := true, x1 := cast(f32)0, y1 := cast(f32)0, x2 := cast(f32)1, y2 := cast(f32)1, top := 0, right := 0, bottom := 0, left := 0, loc := #caller_location) {
	ui_push_rect(x1, y1, x2, y2, top, right, bottom, left, {}, loc);
	defer ui_pop_rect(loc);

/*

	min := Vec2{cast(f32)ui_current_rect_pixels.x1, cast(f32)ui_current_rect_pixels.y1};
	max := Vec2{cast(f32)ui_current_rect_pixels.x2, cast(f32)ui_current_rect_pixels.y2};
	center_of_rect := min + ((max - min) / 2);
	size := cast(f32)(ui_current_rect_pixels.y2 - ui_current_rect_pixels.y1);
	string_width : f32 = cast(f32)get_string_width(font, str, size);

	position := Vec2{center_of_rect.x - (string_width / 2), cast(f32)ui_current_rect_pixels.y1};
	*/

	// min := Vec2{ui_current_rect_unit.x1, ui_current_rect_unit.y1};
	// max := Vec2{ui_current_rect_unit.x2, ui_current_rect_unit.y2};
	// center_of_rect := min + ((max - min) / 2);
	// height := ui_current_rect_unit.y2 - ui_current_rect_unit.y1;
	// string_width : f32 = cast(f32)get_string_width(font, str, height);
	// logln(string_width);
	// position := Vec2{center_of_rect.x - (string_width / 2), ui_current_rect_unit.y1};
	position := Vec2{cast(f32)ui_current_rect_unit.x1, cast(f32)ui_current_rect_unit.y1};
	height := (ui_current_rect_unit.y2 - ui_current_rect_unit.y1) * cast(f32)current_window_height / font.size;
	draw_string(unit_to_viewport, font, str, position, color, height * size, 9999); // todo(josh): proper render order on text
}

// draw_string :: proc(font: ^Font, str: string, position: Vec2, color: Colorf, _size: f32, layer: int) -> f32 {
// 	start := position;
// 	for c in str {
// 		min, max: Vec2;
// 		quad: stb.Aligned_Quad;
// 		{
// 			//
// 			size_pixels: Vec2;
// 			// NOTE!!!!!!!!!!! quad x0 y0 is TOP LEFT and x1 y1 is BOTTOM RIGHT. // I think?!!!!???!!!!
// 			quad = stb.get_baked_quad(font.chars, font.dim, font.dim, cast(int)c, &size_pixels.x, &size_pixels.y, true);
// 			size_pixels.y = abs(quad.y1 - quad.y0);

// 			ww := cast(f32)current_window_width;
// 			hh := cast(f32)current_window_height;
// 			min = position + (Vec2{quad.x0, -quad.y1} / font.size * _size * Vec2{hh/ww, 1});
// 			max = position + (Vec2{quad.x1, -quad.y0} / font.size * _size * Vec2{hh/ww, 1});
// 		}

// 		sprite: Sprite;
// 		{
// 			uv0 := Vec2{quad.s0, quad.t1};
// 			uv1 := Vec2{quad.s0, quad.t0};
// 			uv2 := Vec2{quad.s1, quad.t0};
// 			uv3 := Vec2{quad.s1, quad.t1};
// 			sprite = Sprite{{uv0, uv1, uv2, uv3}, 0, 0, font.id};
// 		}

// 		push_quad(shader_text, min, max, sprite, color, layer);
// 		position.x += max.x - min.x;
// 	}

// 	width := position.x - start.x;
// 	return width;
// }

// button :: proc(font: ^Font, text: string, text_size: f32, text_color: Colorf, min, max: Vec2, button_color: Colorf, render_order: int, scale: f32 = 1, alpha: f32 = 1) -> bool {
// 	rendering_unit_space();

// 	text_color.a   = alpha;
// 	button_color.a = alpha;

// 	half_width  := (max.x - min.x) / 2;
// 	half_height := (max.y - min.y) / 2;
// 	middle := min + ((max-min) / 2);

// 	p0 := middle + (Vec2{-half_width, -half_height} * scale);
// 	p1 := middle + (Vec2{-half_width,  half_height} * scale);
// 	p2 := middle + (Vec2{ half_width,  half_height} * scale);
// 	p3 := middle + (Vec2{ half_width, -half_height} * scale);

// 	push_quad(shader_rgba, p0, p1, p2, p3, button_color, render_order);
// 	baseline := get_centered_baseline(font, text, text_size * scale, p0, p2);
// 	draw_string(font, text, baseline, text_color, text_size * scale, render_order+1);

// 	assert(current_render_mode == rendering_unit_space);
// 	mouse_pos := cursor_unit_position;
// 	if get_mouse_up(Mouse.Left) && mouse_pos.x >= min.x && mouse_pos.y >= min.y && mouse_pos.x <= max.x && mouse_pos.y <= max.y {
// 		return true;
// 	}

// 	return false;
// }

//
// Debug
//

UI_Debug_Rect :: struct {
	using rect: Rect(int),
	location: Source_Code_Location,
}

ui_debug_cur_idx: int;
ui_debug_rects:   [dynamic]UI_Debug_Rect;

ui_debugging: bool;
ui_debug_drawing_rects: bool;

maybe_add_ui_debug_rect :: proc(location: Source_Code_Location) {
	if ui_debugging && !ui_debug_drawing_rects {
		append(&ui_debug_rects, UI_Debug_Rect{ui_current_rect_pixels, location});
	}
}

_ui_debug_screen_update :: proc(dt: f32) {
	if get_key_down(Key.F5) {
		ui_debugging = !ui_debugging;
	}

	if ui_debugging {
		ui_debug_drawing_rects = true;
		defer ui_debug_drawing_rects = false;

		ui_debug_cur_idx += cast(int)cursor_scroll;
		if ui_debug_cur_idx < 0 do ui_debug_cur_idx = 0;
		if ui_debug_cur_idx >= len(ui_debug_rects) do ui_debug_cur_idx = len(ui_debug_rects)-1;

		if len(ui_debug_rects) > 0 {
			for rect, i in ui_debug_rects {
				if ui_debug_cur_idx == i {
					min := Vec2{cast(f32)rect.x1, cast(f32)rect.y1};
					max := Vec2{cast(f32)rect.x2, cast(f32)rect.y2};
					draw_debug_box(pixel_to_viewport, to_vec3(min), to_vec3(max), COLOR_GREEN);

					ui_push_rect(0.5, 0.9, 0.5, 1, 0, 0, 0, 0);
					defer ui_pop_rect();

					buf: [2048]byte;
					str := bprint(buf[:], file_from_path(rect.location.file_path), ":", rect.location.line);
					ui_text(font_default, str, 1, COLOR_BLACK);
				}
			}
		}
	}

	clear(&ui_debug_rects);
}