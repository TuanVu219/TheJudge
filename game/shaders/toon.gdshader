shader_type spatial;

uniform vec4 albedo_color : source_color = vec4(0.42, 0.82, 0.72, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.52, 0.60, 0.76, 1.0);
uniform vec4 highlight_tint : source_color = vec4(1.0, 0.96, 0.84, 1.0);
uniform vec3 rim_color : source_color = vec3(1.0, 0.86, 0.62);
uniform float rim_strength : hint_range(0.0, 0.5) = 0.12;
uniform float specular_dot_strength : hint_range(0.0, 0.4) = 0.12;

void fragment() {
	ALBEDO = albedo_color.rgb;
	ROUGHNESS = 0.82;
	METALLIC = 0.0;
	SPECULAR = 0.18;

	float view_rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 3.0);
	EMISSION = rim_color * view_rim * rim_strength;
}

void light() {
	float ndotl = max(dot(normalize(NORMAL), normalize(LIGHT)), 0.0);
	float lower_band = smoothstep(0.10, 0.18, ndotl);
	float middle_band = smoothstep(0.43, 0.51, ndotl);
	float upper_band = smoothstep(0.78, 0.86, ndotl);

	vec3 tone = shadow_tint.rgb;
	tone = mix(tone, vec3(0.68), lower_band);
	tone = mix(tone, vec3(0.90), middle_band);
	tone = mix(tone, highlight_tint.rgb, upper_band);
	DIFFUSE_LIGHT += albedo_color.rgb * tone * LIGHT_COLOR * ATTENUATION;

	vec3 half_vector = normalize(LIGHT + VIEW);
	float specular_dot = pow(max(dot(normalize(NORMAL), half_vector), 0.0), 56.0);
	SPECULAR_LIGHT += vec3(specular_dot * specular_dot_strength) * LIGHT_COLOR * ATTENUATION;
}
