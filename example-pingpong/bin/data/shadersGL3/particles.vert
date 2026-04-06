#version 150

uniform sampler2DRect uPositionLifeTex;
uniform sampler2DRect uVelocityFlagTex;
uniform ivec2 uStorageSize;
uniform float uPointScale;

out vec4 vColor;

void main() {
    int index = gl_VertexID;
    int x = index % uStorageSize.x;
    int y = index / uStorageSize.x;

    vec4 posLife = texelFetch(uPositionLifeTex, ivec2(x, y));
    vec4 velFlag = texelFetch(uVelocityFlagTex, ivec2(x, y));

    float life = clamp(posLife.a, 0.0, 1.0);
    float speed = length(velFlag.xy);

    gl_Position = vec4(posLife.xyz, 1.0);
    gl_PointSize = max(1.0, uPointScale * (0.5 + 1.5 * life));

    vColor = vec4(0.15 + speed * 6.0,
                  0.25 + life * 0.70,
                  0.85 - min(speed * 1.2, 0.5),
                  0.2 + life * 0.8);
}
