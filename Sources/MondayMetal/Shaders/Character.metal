#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float4 position;
    float4 uv;
    uint4 joints;
    float4 weights;
};

struct Uniforms {
    float4x4 viewProjection;
    float4x4 model;
    float4 color;
    float4 parameters;
    uint alphaMode;
};

enum AlphaMode : uint { Opaque = 0, Mask = 1, Blend = 2 };

struct Raster {
    float4 position [[position]];
    float2 uv;
};

struct MorphInfluence {
    uint index;
    float weight;
};

vertex Raster characterVertex(uint index [[vertex_id]],
                              const device Vertex *vertices [[buffer(0)]],
                              constant Uniforms &uniforms [[buffer(1)]],
                              const device float4x4 *joints [[buffer(2)]],
                              const device float4 *morphs [[buffer(3)]],
                              constant MorphInfluence *influences [[buffer(4)]]) {
    Vertex inputVertex = vertices[index];
    float4 position = inputVertex.position;
    for (uint target = 0; target < uint(uniforms.parameters.y); ++target) {
        MorphInfluence influence = influences[target];
        position += morphs[influence.index * uint(uniforms.parameters.z) + index] * influence.weight;
    }
    float4 world;
    if (uniforms.parameters.w > 0) {
        world = float4(0);
        for (uint joint = 0; joint < 4; ++joint) {
            world += joints[inputVertex.joints[joint]] * position * inputVertex.weights[joint];
        }
    } else {
        world = uniforms.model * position;
    }
    return { uniforms.viewProjection * world, inputVertex.uv.xy };
}

fragment float4 characterFragment(Raster input [[stage_in]],
                                  constant Uniforms &uniforms [[buffer(1)]],
                                  texture2d<float> colorTexture [[texture(0)]],
                                  sampler colorSampler [[sampler(0)]]) {
    float4 color = colorTexture.sample(colorSampler, input.uv) * uniforms.color;
    if (uniforms.alphaMode == Opaque) {
        color.a = 1;
    } else if (uniforms.alphaMode == Mask) {
        if (color.a < uniforms.parameters.x) discard_fragment();
        color.a = 1;
    } else if (color.a < 0.001f) {
        discard_fragment();
    }
    return float4(color.rgb * color.a, color.a);
}

kernel void extractCoverage(texture2d<float, access::read> image [[texture(0)]],
                            device uchar *alpha [[buffer(0)]],
                            uint2 pixel [[thread_position_in_grid]]) {
    if (pixel.x >= image.get_width() || pixel.y >= image.get_height()) return;
    alpha[pixel.y * image.get_width() + pixel.x] = uchar(round(image.read(pixel).a * 255));
}
