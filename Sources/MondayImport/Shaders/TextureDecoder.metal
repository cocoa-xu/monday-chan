#include <metal_stdlib>
using namespace metal;

kernel void decodeASTC(texture2d<float, access::sample> source [[texture(0)]],
                       texture2d<float, access::write> destination [[texture(1)]],
                       uint2 pixel [[thread_position_in_grid]]) {
    if (pixel.x >= destination.get_width() || pixel.y >= destination.get_height()) return;
    constexpr sampler nearest(coord::pixel, address::clamp_to_edge, filter::nearest);
    float2 position(pixel.x + 0.5f, source.get_height() - pixel.y - 0.5f);
    float4 decoded = source.sample(nearest, position, level(0));
    float4 unorm8 = min(floor(decoded * 256.0f), 255.0f) / 255.0f;
    destination.write(unorm8, pixel);
}
