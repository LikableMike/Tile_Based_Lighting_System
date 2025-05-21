#[compute]

#version 450

layout(local_size_x = 1024, local_size_y = 1, local_size_z = 1) in;

layout(binding = 0, rgba8) uniform readonly image2D foreground;
layout(binding = 1, rgba8) uniform readonly image2D shadow_map;
layout(binding = 2, rgba8) uniform writeonly image2D output_image;

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);

    // Skip out-of-bounds safety (optional)
    if (coord.y == 0) return;

    vec4 above_pixel = imageLoad(shadow_map, coord + ivec2(0, -1));
    vec4 fg_pixel = imageLoad(foreground, coord);

    float alpha = above_pixel.a;

    // If foreground pixel is not transparent, increase alpha
    if (fg_pixel.a > 0.0) {
        alpha += 20.0 / 255.0;
    }

    alpha = clamp(alpha, 0.0, 0.98);
    vec3 mixColor = mix(above_pixel.rgb, vec3(0.01), 0.5);
    vec4 result = vec4(mixColor, alpha);
    imageStore(output_image, coord, result);
}
