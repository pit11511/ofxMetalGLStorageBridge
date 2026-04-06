#version 150

in vec4 vColor;

out vec4 outputColor;

void main() {
    vec2 p = gl_PointCoord * 2.0 - 1.0;
    float radius2 = dot(p, p);
    if (radius2 > 1.0) {
        discard;
    }

    float falloff = smoothstep(1.0, 0.0, radius2);
    outputColor = vec4(vColor.rgb * (0.35 + 0.65 * falloff), vColor.a * falloff);
}
