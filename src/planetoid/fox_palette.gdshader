shader_type canvas_item;
render_mode unshaded;

// Swaps the fox's two body colours (#d67941 light, #9d5021 dark) for a variant
// pair. Outline, belly and eyes are left untouched. Defaults are identity.
uniform vec4 source_a : source_color = vec4(0.839216, 0.474510, 0.254902, 1.0); // #d67941
uniform vec4 source_b : source_color = vec4(0.615686, 0.313726, 0.129412, 1.0); // #9d5021
uniform vec4 target_a : source_color = vec4(0.839216, 0.474510, 0.254902, 1.0);
uniform vec4 target_b : source_color = vec4(0.615686, 0.313726, 0.129412, 1.0);
uniform float tolerance = 0.04;

// In a canvas_item vertex shader COLOR carries the node's final modulate
// (opacity + the hover highlight tint). We stash it and re-apply it in the
// fragment, which a custom fragment() would otherwise discard.
varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	vec3 rgb = texel.rgb;
	if (texel.a > 0.0) {
		if (distance(texel.rgb, source_a.rgb) <= tolerance) {
			rgb = target_a.rgb;
		} else if (distance(texel.rgb, source_b.rgb) <= tolerance) {
			rgb = target_b.rgb;
		}
	}
	COLOR = vec4(rgb, texel.a) * v_modulate;
}
