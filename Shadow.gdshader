shader_type canvas_item;
render_mode unshaded;


uniform sampler2D dirt_map;
uniform sampler2D light_map;
uniform vec2 region_origin;
uniform vec2 region_size;
uniform float resolution;
uniform float map_size;

uniform int light_count = 0;
uniform vec2 light_positions[512]; // screen-space positions
uniform vec4 light_colors[512];    // RGBA colors
uniform float light_intensities[512];

void fragment() {
    vec2 light_uv = ((UV * region_size) + region_origin) / resolution;
    vec4 light = texture(light_map, UV);
    vec4 color = texture(TEXTURE, UV);
	float dirt_present = texture(dirt_map, UV).a;

	float newAlpha = 1.0;
	vec3 newColor = vec3(1.0);
	for(int i = 0; i < light_count; i++){
		vec3 light_color = light_colors[i].rgb;
		float dist = distance(light_positions[i], UV * resolution);
		newAlpha *= pow(clamp(1.0 / (light_intensities[i] / dist) + (dirt_present * 0.8), 0.1, 1.0), 0.5);

	}
	float finalAlpha = clamp(newAlpha, 0.1, 1.0);

    COLOR = vec4(color.rgb , pow(color.a * finalAlpha, 2));

}
