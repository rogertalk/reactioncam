#include <metal_stdlib>
using namespace metal;

struct VertexOutput
{
    float4 position [[position]];
    float2 uv;
    float alpha;
};

typedef struct
{
    packed_float3 position;
    packed_float2 texCoord;
    float alpha;
} vertex_t;

vertex VertexOutput basicVertex(device vertex_t* vertex_array [[ buffer(0) ]],
                                uint vid [[ vertex_id ]])
{
    float3 position = float3(vertex_array[vid].position);
    float2 uv = float2(vertex_array[vid].texCoord);
    float alpha = vertex_array[vid].alpha;

    VertexOutput out;
    out.position = float4(position, 1.0);
    out.uv = uv;
    out.alpha = alpha;

    return out;
}

fragment half4 basicFragment(VertexOutput in [[ stage_in ]],
                             texture2d<half> tex [[ texture(0) ]])
{
    constexpr sampler s(filter::linear);
    // TODO: return tex.sample(s, in.uv) * in.alpha;
    return tex.sample(s, in.uv);
}
