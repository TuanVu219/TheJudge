shader_type spatial;
render_mode cull_front, unshaded;

uniform vec4 outline_color : source_color = vec4(0.227, 0.141, 0.094, 1.0);
uniform float outline_width : hint_range(0.0, 0.08) = 0.03;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
