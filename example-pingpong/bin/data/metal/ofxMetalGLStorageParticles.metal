#include <metal_stdlib>

using namespace metal;

struct ParticleSimParams {
    float deltaTime;
    float time;
    float bounds;
    float damping;
};

float hash12(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

kernel void initParticleState(texture2d<float, access::write> positionLife [[texture(0)]],
                              texture2d<float, access::write> velocityFlag [[texture(1)]],
                              uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= positionLife.get_width() || gid.y >= positionLife.get_height()) {
        return;
    }

    const float2 size = float2(positionLife.get_width(), positionLife.get_height());
    const float2 uv = (float2(gid) + 0.5) / size;
    const float2 centered = uv * 2.0 - 1.0;
    const float noise = hash12(float2(gid));
    const float angle = atan2(centered.y, centered.x);
    const float radius = 0.15 + 0.70 * min(length(centered), 1.0);

    const float2 pos = float2(cos(angle), sin(angle)) * radius;
    const float2 tangent = normalize(float2(-pos.y, pos.x));
    const float2 vel = tangent * (0.18 + noise * 0.32);
    const float life = 0.35 + 0.65 * hash12(float2(gid.yx) + 17.0);

    positionLife.write(float4(pos.x, pos.y, 0.0, life), gid);
    velocityFlag.write(float4(vel.x, vel.y, 0.0, 1.0), gid);
}

kernel void updateParticleState(texture2d<float, access::read> positionLifeIn [[texture(0)]],
                                texture2d<float, access::read> velocityFlagIn [[texture(1)]],
                                texture2d<float, access::write> positionLifeOut [[texture(2)]],
                                texture2d<float, access::write> velocityFlagOut [[texture(3)]],
                                constant ParticleSimParams& params [[buffer(0)]],
                                uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= positionLifeOut.get_width() || gid.y >= positionLifeOut.get_height()) {
        return;
    }

    float4 posLife = positionLifeIn.read(gid);
    float4 velFlag = velocityFlagIn.read(gid);

    float2 pos = posLife.xy;
    float2 vel = velFlag.xy;
    float life = posLife.w;

    const float swirlPhase = params.time * 0.75 + float(gid.x) * 0.03 + float(gid.y) * 0.07;
    const float2 swirlForce = float2(-pos.y, pos.x) * (0.15 + 0.10 * sin(swirlPhase));

    vel += swirlForce * params.deltaTime;
    pos += vel * params.deltaTime;

    if (pos.x < -params.bounds || pos.x > params.bounds) {
        pos.x = clamp(pos.x, -params.bounds, params.bounds);
        vel.x *= -params.damping;
    }
    if (pos.y < -params.bounds || pos.y > params.bounds) {
        pos.y = clamp(pos.y, -params.bounds, params.bounds);
        vel.y *= -params.damping;
    }

    life -= params.deltaTime * (0.08 + 0.10 * hash12(float2(gid) + 29.0));
    if (life <= 0.0) {
        const float respawnPhase = hash12(float2(gid) + params.time * 13.0) * 6.2831853;
        pos = float2(cos(respawnPhase), sin(respawnPhase)) * 0.10;
        vel = float2(cos(respawnPhase + 1.5707963), sin(respawnPhase + 1.5707963)) *
              (0.22 + 0.25 * hash12(float2(gid.yx) + params.time * 7.0));
        life = 1.0;
    }

    positionLifeOut.write(float4(pos.x, pos.y, 0.0, life), gid);
    velocityFlagOut.write(float4(vel.x, vel.y, 0.0, velFlag.w), gid);
}
