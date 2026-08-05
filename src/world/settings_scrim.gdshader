shader_type canvas_item;

// Backdrop blur + darken for the scrim behind the settings panel, so the den,
// the clock and the stats stop competing with the panel for attention.
//
// The blur is an explicit tap kernel rather than textureLod() on a mipmapped
// screen texture: the project renders with the Compatibility backend, which
// doesn't hand canvas shaders a mipmapped screen texture to sample from.
// 13 taps is cheap enough for a static, full-screen UI backdrop.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float radius : hint_range(0.0, 12.0) = 4.0;
uniform vec4 tint : source_color = vec4(0.16, 0.10, 0.06, 1.0);
uniform float darken : hint_range(0.0, 1.0) = 0.32;

void fragment() {
	// The canvas modulate arrives in COLOR, which is how the scrim fades in and
	// out — grab it before overwriting COLOR with the blurred backdrop.
	float fade = COLOR.a;

	vec2 step = SCREEN_PIXEL_SIZE * radius;
	vec3 sum = texture(screen_tex, SCREEN_UV).rgb;
	float weight = 1.0;

	// Inner ring: four axis-aligned taps.
	sum += texture(screen_tex, SCREEN_UV + vec2(step.x, 0.0)).rgb * 0.75;
	sum += texture(screen_tex, SCREEN_UV - vec2(step.x, 0.0)).rgb * 0.75;
	sum += texture(screen_tex, SCREEN_UV + vec2(0.0, step.y)).rgb * 0.75;
	sum += texture(screen_tex, SCREEN_UV - vec2(0.0, step.y)).rgb * 0.75;
	weight += 3.0;

	// Inner ring: four diagonals.
	sum += texture(screen_tex, SCREEN_UV + vec2(step.x, step.y)).rgb * 0.55;
	sum += texture(screen_tex, SCREEN_UV + vec2(step.x, -step.y)).rgb * 0.55;
	sum += texture(screen_tex, SCREEN_UV + vec2(-step.x, step.y)).rgb * 0.55;
	sum += texture(screen_tex, SCREEN_UV + vec2(-step.x, -step.y)).rgb * 0.55;
	weight += 2.2;

	// Outer ring: four axis-aligned taps at double the radius, to widen the
	// falloff without paying for a full second ring.
	sum += texture(screen_tex, SCREEN_UV + vec2(step.x * 2.0, 0.0)).rgb * 0.35;
	sum += texture(screen_tex, SCREEN_UV - vec2(step.x * 2.0, 0.0)).rgb * 0.35;
	sum += texture(screen_tex, SCREEN_UV + vec2(0.0, step.y * 2.0)).rgb * 0.35;
	sum += texture(screen_tex, SCREEN_UV - vec2(0.0, step.y * 2.0)).rgb * 0.35;
	weight += 1.4;

	COLOR = vec4(mix(sum / weight, tint.rgb, darken), fade);
}
