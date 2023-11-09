#version 450

#define ACCELERATED_SCENE_SET 0
#include "accelerated_scene.glsl"
#define CAMERA_SET 1
#include "camera.glsl"

layout(location = 0) out vec4 oColor;
layout(push_constant) uniform uuPushConstant { float uWidth1, uHeight1; };

#define ONEof22 0.45454545454545454545454545f

void main() {
	uint tri_idx;
	vec2 tri_uv;
	vec3 camDir = CameraGenRay(fma(gl_FragCoord.xy, vec2(uWidth1, uHeight1), vec2(-1.0f)));
	BVHIntersection(vec4(uPosition.xyz, 1e-6), camDir, tri_idx, tri_uv);

	if (tri_idx != 0xffffffffu) {
		// oColor = vec4(TriangleFetchNormal(tri_idx, tri_uv) * 0.5 + 0.5, 1);
		oColor = vec4(pow(TriangleFetchDiffuse(tri_idx, tri_uv), vec3(ONEof22)), 1);
	} else {
		oColor = vec4(1, 172.0/255.0, 28.0/255.0, 0);
	}
}
