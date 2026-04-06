#version 150

uniform sampler2DRect uStorageTex;
uniform vec2 uStorageSize;

in vec2 vStorageCoord;

out vec4 outputColor;

void main() {
    ivec2 maxCoord = ivec2(uStorageSize) - ivec2(1);
    ivec2 coord = clamp(ivec2(floor(vStorageCoord)), ivec2(0), maxCoord);
    vec4 raw = texelFetch(uStorageTex, coord);

    float nx = raw.r / max(uStorageSize.x - 1.0, 1.0);
    float ny = raw.g / max(uStorageSize.y - 1.0, 1.0);
    float signature = fract(raw.b * 0.01);

    outputColor = vec4(nx, ny, signature, 1.0);
}
