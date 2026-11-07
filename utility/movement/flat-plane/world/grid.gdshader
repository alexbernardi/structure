shader_type spatial;
// Measurement grid projected in world space on every surface (floor, ramps, stair risers, walls):
// 1 m minor lines, 10 m major lines, X axis red, Z axis blue.

uniform vec3 base_color : source_color = vec3(0.62, 0.64, 0.68);
uniform vec3 minor_color : source_color = vec3(0.45, 0.47, 0.52);
uniform vec3 major_color : source_color = vec3(0.12, 0.14, 0.18);
uniform float minor_spacing = 1.0;
uniform float major_spacing = 10.0;
uniform float minor_width = 1.0;
uniform float major_width = 1.8;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float lines(vec2 p, float spacing, float width) {
	vec2 coord = p / spacing;
	vec2 g = abs(fract(coord - 0.5) - 0.5) / max(fwidth(coord), vec2(0.0001));
	return 1.0 - clamp(min(g.x, g.y) / width, 0.0, 1.0);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 p = world_pos.xz;
	if (n.x > n.y && n.x > n.z) {
		p = world_pos.zy;
	} else if (n.z > n.y) {
		p = world_pos.xy;
	}
	vec3 col = base_color;
	col = mix(col, minor_color, lines(p, minor_spacing, minor_width) * 0.8);
	col = mix(col, major_color, lines(p, major_spacing, major_width));
	if (n.y > 0.5) {
		float ax = 1.0 - clamp(abs(world_pos.z) / (fwidth(world_pos.z) * 2.0 + 0.0001), 0.0, 1.0);
		float az = 1.0 - clamp(abs(world_pos.x) / (fwidth(world_pos.x) * 2.0 + 0.0001), 0.0, 1.0);
		col = mix(col, vec3(0.85, 0.2, 0.2), ax);
		col = mix(col, vec3(0.2, 0.35, 0.9), az);
	}
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
