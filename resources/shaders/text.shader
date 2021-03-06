@vert

#version 330 core

// from vbo
layout(location = 0) in vec3 vbo_vertex_position;
layout(location = 1) in vec2 vbo_tex_coord;
layout(location = 2) in vec4 vbo_color;
layout(location = 3) in vec3 vbo_normal;

uniform vec4 mesh_color;

uniform mat4 model_matrix;
uniform mat4 view_matrix;
uniform mat4 projection_matrix;

out vec4 vert_color;
out vec3 vert_normal;
out vec2 tex_coord;

void main() {
    vec4 result = projection_matrix * view_matrix * model_matrix * vec4(vbo_vertex_position, 1);
    gl_Position = result;
    vert_color = vbo_color * mesh_color;
    vert_normal = vbo_normal;
    tex_coord = vbo_tex_coord;
}


@frag

#version 330 core

in vec2 tex_coord;
in vec4 vert_color;

uniform sampler2D texture_handle;

out vec4 color;

void main() {
	uvec4 bytes = uvec4(texture(texture_handle, tex_coord) * 255);
	uvec4 desired = uvec4(vert_color * 255);

	uint old_r = bytes.r;

	bytes.r = desired.r;
	bytes.g = desired.g;
	bytes.b = desired.b;
	bytes.a &= old_r & desired.a;

	color = vec4(bytes.r, bytes.g, bytes.b, bytes.a) / 255;
}
