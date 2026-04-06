#include <metal_stdlib>

using namespace metal;

struct MockSimParams {
    float deltaTime;
    float lifeDecay;
};

kernel void writeDebugPattern(texture2d<float, access::write> outputStorage [[texture(0)]],
                              uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= outputStorage.get_width() || gid.y >= outputStorage.get_height()) {
        return;
    }

    const float x = static_cast<float>(gid.x);
    const float y = static_cast<float>(gid.y);

    // Coordinate convention used by this addon:
    // gid = integer texel coordinate, row-major, (0,0) is the first row copied back on CPU.
    outputStorage.write(float4(x, y, 1000.0f + x + 100.0f * y, 1.0f), gid);
}

kernel void writeDebugPatternRG32Float(texture2d<float, access::write> outputStorage [[texture(0)]],
                                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= outputStorage.get_width() || gid.y >= outputStorage.get_height()) {
        return;
    }

    outputStorage.write(float4(static_cast<float>(gid.x), static_cast<float>(gid.y), 0.0f, 0.0f), gid);
}

kernel void writeDebugPatternRGBA16Float(texture2d<half, access::write> outputStorage [[texture(0)]],
                                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= outputStorage.get_width() || gid.y >= outputStorage.get_height()) {
        return;
    }

    const half x = static_cast<half>(gid.x);
    const half y = static_cast<half>(gid.y);
    outputStorage.write(half4(x, y, static_cast<half>(1000 + gid.x + 100 * gid.y), half(1.0)), gid);
}

kernel void mockPingPongSim(texture2d<float, access::read> inputStorage [[texture(0)]],
                            texture2d<float, access::write> outputStorage [[texture(1)]],
                            constant MockSimParams& params [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= outputStorage.get_width() || gid.y >= outputStorage.get_height()) {
        return;
    }

    const float4 prev = inputStorage.read(gid);
    float4 nextValue = prev;
    nextValue.xyz += float3(0.10f, 0.20f, 0.30f) * params.deltaTime;
    nextValue.w = max(0.0f, prev.w - params.lifeDecay * params.deltaTime);

    outputStorage.write(nextValue, gid);
}
