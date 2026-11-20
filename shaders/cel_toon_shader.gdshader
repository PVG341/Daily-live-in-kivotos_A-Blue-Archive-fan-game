shader_type spatial;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform vec4 shadow_color : source_color = vec4(0.65, 0.65, 0.75, 1.0);
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.45;
uniform float shadow_smoothness : hint_range(0.001, 0.2) = 0.03;

void fragment() {
	vec4 tex_color = texture(albedo_texture, UV);
	ALBEDO = albedo_color.rgb * tex_color.rgb;
}

void light() {
	float ndotl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float cel_band = smoothstep(
		shadow_threshold - shadow_smoothness,
		shadow_threshold + shadow_smoothness,
		ndotl
	);
	vec3 band_color = mix(shadow_color.rgb, vec3(1.0), cel_band);
	DIFFUSE_LIGHT += ALBEDO * band_color * LIGHT_COLOR * ATTENUATION;
}
