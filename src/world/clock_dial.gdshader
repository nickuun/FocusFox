shader_type canvas_item;

// Circular progress dial. The sprite's own TEXTURE is the "empty" clock; `full_tex`
// is the "full" clock. As `fill` goes 0 -> 1 we reveal the full art in an angular
// sweep, so the ornate outer ring lights up like a progress bar. The middle of the
// clock is identical in both textures (deadspace), so it never visibly changes.

uniform sampler2D full_tex : filter_nearest;
uniform float fill : hint_range(0.0, 1.0) = 0.0;
// Centre of the ring in UV space (the clock art isn't centred in its canvas).
uniform vec2 center = vec2(0.5693, 0.4713);
// Where the sweep begins, in degrees (screen space: 0 = right, 90 = down,
// 135 = bottom-left). Default fills up from the bottom-left.
uniform float start_deg = 135.0;
// Aspect (texture width / height) so the sweep boundary stays radial, not skewed.
uniform float aspect = 1.7777778;
uniform bool clockwise = true;

void fragment() {
	vec4 empty_col = texture(TEXTURE, UV);
	vec4 full_col = texture(full_tex, UV);

	vec2 d = UV - center;
	d.x *= aspect; // undo the canvas aspect so angles match true pixels
	float ang = atan(d.y, d.x);
	float rel = ang - radians(start_deg);
	rel = clockwise ? rel : -rel;
	rel = mod(rel, TAU) / TAU; // 0..1 fraction swept from the start

	float shown = step(rel, fill);
	COLOR = mix(empty_col, full_col, shown);
}
