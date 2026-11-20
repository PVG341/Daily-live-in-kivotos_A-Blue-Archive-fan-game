shader_type spatial;
render_mode cull_front, unshaded;

uniform vec4 outline_color : source_color = vec4(0.12, 0.12, 0.16, 1.0);
uniform float outline_width : hint_range(0.0, 0.05) = 0.008;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
