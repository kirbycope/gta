shader_type spatial;
// Stealth: the model becomes a pale ghost of itself. depth_prepass_alpha writes the body's depth before it is drawn
// see-through, so only the nearest surface shows: arms never bleed through the torso the way plain transparency does.
render_mode depth_prepass_alpha, cull_back;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform vec4 tint : source_color = vec4(0.78, 0.88, 1.0, 1.0); // A cold shimmer over the washed-out colours
uniform float brighten : hint_range(0.0, 1.0) = 0.6; // How far the model's colours wash out toward white
uniform float alpha : hint_range(0.0, 1.0) = 1.0; // 1 is solid; the Player tweens it down as stealth settles in
uniform float rim : hint_range(0.0, 1.0) = 0.5; // Edges keep this much more of their opacity, so the silhouette still reads

void fragment() {
	vec4 base = albedo_color;
	if (use_texture) {
		base *= texture(albedo_texture, UV);
	}
	float fresnel = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge_alpha = alpha + rim * (1.0 - alpha);
	ALBEDO = mix(base.rgb, vec3(1.0), brighten) * tint.rgb;
	ALPHA = base.a * mix(alpha, edge_alpha, fresnel * fresnel);
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
}
