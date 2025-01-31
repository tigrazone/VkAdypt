#ifndef ACCELERATED_SCENE_SET
#define ACCELERATED_SCENE_SET 0
#endif

#extension GL_EXT_nonuniform_qualifier : enable

#define kTraversalStackSize 23*10

#include "common.h"
#include "compress.glsl"

struct Node {
	vec4 m_head;
	uvec4 m_base_meta, m_lox_loy, m_loz_hix, m_hiy_hiz;
};

struct Woop {
	vec4 m0, m1, m2;
};

layout(set = ACCELERATED_SCENE_SET, binding = 0) uniform sampler2D uTextures[];
layout(std430, set = ACCELERATED_SCENE_SET, binding = 1) readonly buffer uuTriangles { TrianglePkd uTriangles[]; };
layout(std430, set = ACCELERATED_SCENE_SET, binding = 2) readonly buffer uuTriMaterials { Material uTriMaterials[]; };
layout(std430, set = ACCELERATED_SCENE_SET, binding = 3) readonly buffer uuBVHNodes { Node uBVHNodes[]; };
layout(std430, set = ACCELERATED_SCENE_SET, binding = 4) readonly buffer uuBVHTriIndices { uint uBVHTriIndices[]; };
layout(std430, set = ACCELERATED_SCENE_SET, binding = 5) readonly buffer uuBVHTriMatrices { Woop uBVHTriMatrices[]; };

uvec2 stack[kTraversalStackSize];
const float ooeps = exp2(-64.0f);

void BVHIntersection(in const vec4 origin_tmin, vec3 dir, inout uint o_hit_tri_idx, out vec2 o_hit_uv) {
	dir.x = abs(dir.x) > ooeps ? dir.x : (dir.x >= 0 ? ooeps : -ooeps);
	dir.y = abs(dir.y) > ooeps ? dir.y : (dir.y >= 0 ? ooeps : -ooeps);
	dir.z = abs(dir.z) > ooeps ? dir.z : (dir.z >= 0 ? ooeps : -ooeps);
	dir = normalize(dir);
	vec3 idir = 1.0f / dir;
	uint octinv = 7u - ((dir.x < 0 ? 1 : 0) | (dir.y < 0 ? 2 : 0) | (dir.z < 0 ? 4 : 0));
	uint octinv4 = octinv * 0x01010101u;

	vec3 origin = origin_tmin.xyz;

	float hit_tmin = origin_tmin.w;
	float hit_t = 1e9f;
	o_hit_tri_idx = 0xffffffffu;

	// stack
	uint stack_ptr = 0;

	// traversal states
	uvec2 tri_group, node_group = uvec2(0u, 0x80000000u);

	// aabb intersection variables
	vec4 txmin, tymin, tzmin, txmax, tymax, tzmax;
	float ctmin, ctmax;

	// triangle intersection variables
	vec4 tv00, tv11, tv22;
	float tt, tu, tv;
	
	vec3 position;

	while (true) {
		if (node_group.y > 0x00ffffffu) {
			// G represents a node group
			// n <- GetClosestNode(G, r)
			uint imask = node_group.y;
			uint child_bit_index = findMSB(node_group.y);
			uint child_node_base_index = node_group.x;

			// Clear corresponding bit in hits field
			// G <- G / n
			node_group.y &= ~(1u << child_bit_index);

			if (node_group.y > 0x00ffffffu)
				stack[stack_ptr++] = node_group;

			// Intersect with n
			// G, Gt <- IntersectChildren(n, r)
			uint slot_index = (child_bit_index - 24) ^ octinv;
			uint relative_index = bitCount(imask & ~(0xffffffffu << slot_index));
			uint child_node_index = child_node_base_index + relative_index;

			// read node data
			vec4 head = uBVHNodes[child_node_index].m_head;
			uint head_w = floatBitsToUint(head.w);
			uvec4 base_meta = uBVHNodes[child_node_index].m_base_meta;
			uvec4 lox_loy = uBVHNodes[child_node_index].m_lox_loy;
			uvec4 loz_hix = uBVHNodes[child_node_index].m_loz_hix;
			uvec4 hiy_hiz = uBVHNodes[child_node_index].m_hiy_hiz;

			float adjusted_idir_x = uintBitsToFloat(((head_w)&0xffu) << 23u) * idir.x;
			float adjusted_idir_y = uintBitsToFloat(((head_w >> 8u) & 0xffu) << 23u) * idir.y;
			float adjusted_idir_z = uintBitsToFloat(((head_w >> 16u) & 0xffu) << 23u) * idir.z;
			vec3 adjusted_origin = (head.xyz - origin) * idir;

			node_group.x = base_meta.x;
			tri_group.x = base_meta.y;
			tri_group.y = 0u;

			uint hitmask = 0u;
			{
				uint meta4 = base_meta.z;
				uint is_inner4 = (meta4 & (meta4 << 1u)) & 0x10101010u;
				uint bit_index4 = (meta4 ^ (octinv4 & (is_inner4 >> 4u) * 0xffu)) & 0x1f1f1f1fu;
				uint child_bits4 = (meta4 >> 5u) & 0x07070707u;

				uint swizzled_lox = (idir.x < 0) ? loz_hix.z : lox_loy.x;
				uint swizzled_hix = (idir.x < 0) ? lox_loy.x : loz_hix.z;

				uint swizzled_loy = (idir.y < 0) ? hiy_hiz.x : lox_loy.z;
				uint swizzled_hiy = (idir.y < 0) ? lox_loy.z : hiy_hiz.x;

				uint swizzled_loz = (idir.z < 0) ? hiy_hiz.z : loz_hix.x;
				uint swizzled_hiz = (idir.z < 0) ? loz_hix.x : hiy_hiz.z;

				txmin = vec4(ivec4(swizzled_lox, swizzled_lox >> 8, swizzled_lox >> 16, swizzled_lox >> 24) & 0xffu) * adjusted_idir_x + vec4(adjusted_origin.x);
				
				tymin = vec4(ivec4(swizzled_loy, swizzled_loy >> 8, swizzled_loy >> 16, swizzled_loy >> 24) & 0xffu) * adjusted_idir_y + vec4(adjusted_origin.y);
				
				tzmin = vec4(ivec4(swizzled_loz, swizzled_loz >> 8, swizzled_loz >> 16, swizzled_loz >> 24) & 0xffu) * adjusted_idir_z + vec4(adjusted_origin.z);

				txmax = vec4(ivec4(swizzled_hix, swizzled_hix >> 8, swizzled_hix >> 16, swizzled_hix >> 24) & 0xffu) * adjusted_idir_x + vec4(adjusted_origin.x);
				
				tymax = vec4(ivec4(swizzled_hiy, swizzled_hiy >> 8, swizzled_hiy >> 16, swizzled_hiy >> 24) & 0xffu) * adjusted_idir_y + vec4(adjusted_origin.y);
				
				tzmax = vec4(ivec4(swizzled_hiz, swizzled_hiz >> 8, swizzled_hiz >> 16, swizzled_hiz >> 24) & 0xffu) * adjusted_idir_z + vec4(adjusted_origin.z);

				ctmin = max(max(txmin[0], tymin[0]), max(tzmin[0], hit_tmin));
				ctmax = min(min(txmax[0], tymax[0]), min(tzmax[0], hit_t));
				if (ctmin <= ctmax)
					hitmask |= ((child_bits4)&0xffu) << ((bit_index4)&0xffu);

				ctmin = max(max(txmin[1], tymin[1]), max(tzmin[1], hit_tmin));
				ctmax = min(min(txmax[1], tymax[1]), min(tzmax[1], hit_t));
				if (ctmin <= ctmax)
					hitmask |= ((child_bits4 >> 8u) & 0xffu) << ((bit_index4 >> 8u) & 0xffu);

				ctmin = max(max(txmin[2], tymin[2]), max(tzmin[2], hit_tmin));
				ctmax = min(min(txmax[2], tymax[2]), min(tzmax[2], hit_t));
				if (ctmin <= ctmax)
					hitmask |= ((child_bits4 >> 16u) & 0xffu) << ((bit_index4 >> 16u) & 0xffu);

				ctmin = max(max(txmin[3], tymin[3]), max(tzmin[3], hit_tmin));
				ctmax = min(min(txmax[3], tymax[3]), min(tzmax[3], hit_t));
				if (ctmin <= ctmax)
					hitmask |= ((child_bits4 >> 24u) & 0xffu) << ((bit_index4 >> 24u) & 0xffu);
			}

			{
				uint meta4 = base_meta.w;
				uint is_inner4 = (meta4 & (meta4 << 1u)) & 0x10101010u;
				uint bit_index4 = (meta4 ^ (octinv4 & (is_inner4 >> 4u) * 0xffu)) & 0x1f1f1f1fu;
				uint child_bits4 = (meta4 >> 5u) & 0x07070707u;

				uint swizzled_lox = (idir.x < 0) ? loz_hix.w : lox_loy.y;
				uint swizzled_hix = (idir.x < 0) ? lox_loy.y : loz_hix.w;

				uint swizzled_loy = (idir.y < 0) ? hiy_hiz.y : lox_loy.w;
				uint swizzled_hiy = (idir.y < 0) ? lox_loy.w : hiy_hiz.y;

				uint swizzled_loz = (idir.z < 0) ? hiy_hiz.w : loz_hix.y;
				uint swizzled_hiz = (idir.z < 0) ? loz_hix.y : hiy_hiz.w;

				txmin = vec4(ivec4(swizzled_lox, swizzled_lox >> 8, swizzled_lox >> 16, swizzled_lox >> 24) & 0xffu) * adjusted_idir_x + vec4(adjusted_origin.x);
				
				tymin = vec4(ivec4(swizzled_loy, swizzled_loy >> 8, swizzled_loy >> 16, swizzled_loy >> 24) & 0xffu) * adjusted_idir_y + vec4(adjusted_origin.y);
				
				tzmin = vec4(ivec4(swizzled_loz, swizzled_loz >> 8, swizzled_loz >> 16, swizzled_loz >> 24) & 0xffu) * adjusted_idir_z + vec4(adjusted_origin.z);

				txmax = vec4(ivec4(swizzled_hix, swizzled_hix >> 8, swizzled_hix >> 16, swizzled_hix >> 24) & 0xffu) * adjusted_idir_x + vec4(adjusted_origin.x);
				
				tymax = vec4(ivec4(swizzled_hiy, swizzled_hiy >> 8, swizzled_hiy >> 16, swizzled_hiy >> 24) & 0xffu) * adjusted_idir_y + vec4(adjusted_origin.y);
				
				tzmax = vec4(ivec4(swizzled_hiz, swizzled_hiz >> 8, swizzled_hiz >> 16, swizzled_hiz >> 24) & 0xffu) * adjusted_idir_z + vec4(adjusted_origin.z);

				ctmin = max(max(txmin[0], tymin[0]), max(tzmin[0], hit_tmin));
				ctmax = min(min(txmax[0], tymax[0]), min(tzmax[0], hit_t));
				if (ctmin <= ctmax)
					hitmask |= ((child_bits4)&0xffu) << ((bit_index4)&0xffu);

				ctmin = max(max(txmin[1], tymin[1]), max(tzmin[1], hit_tmin));
				ctmax = min(min(txmax[1], tymax[1]), min(tzmax[1], hit_t));
				if (ctmin <= ctmax)
					hitmask |= ((child_bits4 >> 8u) & 0xffu) << ((bit_index4 >> 8u) & 0xffu);

				ctmin = max(max(txmin[2], tymin[2]), max(tzmin[2], hit_tmin));
				ctmax = min(min(txmax[2], tymax[2]), min(tzmax[2], hit_t));
				if (ctmin <= ctmax)
					hitmask |= ((child_bits4 >> 16u) & 0xffu) << ((bit_index4 >> 16u) & 0xffu);

				ctmin = max(max(txmin[3], tymin[3]), max(tzmin[3], hit_tmin));
				ctmax = min(min(txmax[3], tymax[3]), min(tzmax[3], hit_t));
				if (ctmin <= ctmax)
					hitmask |= ((child_bits4 >> 24u) & 0xffu) << ((bit_index4 >> 24u) & 0xffu);
			}

			node_group.y = (hitmask & 0xff000000u) | ((head_w >> 24u) & 0xffu);
			tri_group.y = hitmask & 0x00ffffffu;
		} else {
			tri_group = node_group;
			node_group = uvec2(0);
		}

		while (tri_group.y != 0) {
			uint tridx = findLSB(tri_group.y);
			tri_group.y &= ~(1u << tridx);
			tridx += tri_group.x;

			tv00 = uBVHTriMatrices[tridx].m0;
			tv11 = uBVHTriMatrices[tridx].m1;
			tv22 = uBVHTriMatrices[tridx].m2;
			
			tt = (tv00.w - dot(origin, tv00.xyz)) / dot(dir, tv00.xyz);
		
			if (tt > hit_tmin && tt < hit_t) {
				position = origin + tt*dir;
				tu = tv11.w + dot(position, tv11.xyz);
				if (tu >= 0.0 && tu <= 1.0) {
					tv = tv22.w + dot(position, tv22.xyz);
					if (tv >= 0.0 && tu + tv <= 1.0) {
						hit_t = tt;
						o_hit_uv = vec2(tu, tv);
						o_hit_tri_idx = tridx;
					}
				}
			}
		}

		if (node_group.y <= 0x00ffffffu) {
			if (stack_ptr == 0u)
				break;
			node_group = stack[--stack_ptr];
		}
	}

	if (o_hit_tri_idx != 0xffffffffu)
		o_hit_tri_idx = uBVHTriIndices[o_hit_tri_idx];
}

bool BVHIntersection(in const vec4 origin_tmin, vec3 dir) {
	dir.x = abs(dir.x) > ooeps ? dir.x : (dir.x >= 0 ? ooeps : -ooeps);
	dir.y = abs(dir.y) > ooeps ? dir.y : (dir.y >= 0 ? ooeps : -ooeps);
	dir.z = abs(dir.z) > ooeps ? dir.z : (dir.z >= 0 ? ooeps : -ooeps);
	dir = normalize(dir);
	vec3 idir = 1.0f / dir;
	uint octinv = 7u - ((dir.x < 0 ? 1 : 0) | (dir.y < 0 ? 2 : 0) | (dir.z < 0 ? 4 : 0));
	uint octinv4 = octinv * 0x01010101u;

	vec3 origin = origin_tmin.xyz;

	float hit_tmin = origin_tmin.w;
	float hit_t = 1e9f;

	// stack
	uint stack_ptr = 0;

	// traversal states
	uvec2 tri_group, node_group = uvec2(0u, 0x80000000u);

	// aabb intersection variables
	vec4 txmin, tymin, tzmin, txmax, tymax, tzmax;
	float ctmin, ctmax;

	// triangle intersection variables
	vec4 tv00, tv11, tv22;
	
	float tt, tu, tv;
	
	vec3 position;

	while (true) {
		if (node_group.y > 0x00ffffffu) {
			// G represents a node group
			// n <- GetClosestNode(G, r)
			uint imask = node_group.y;
			uint child_bit_index = findMSB(node_group.y);
			uint child_node_base_index = node_group.x;

			// Clear corresponding bit in hits field
			// G <- G / n
			node_group.y &= ~(1u << child_bit_index);

			if (node_group.y > 0x00ffffffu)
				stack[stack_ptr++] = node_group;

			// Intersect with n
			// G, Gt <- IntersectChildren(n, r)
			uint slot_index = (child_bit_index - 24) ^ octinv;
			uint relative_index = bitCount(imask & ~(0xffffffffu << slot_index));
			uint child_node_index = child_node_base_index + relative_index;

			// read node data
			vec4 head = uBVHNodes[child_node_index].m_head;
			uint head_w = floatBitsToUint(head.w);
			uvec4 base_meta = uBVHNodes[child_node_index].m_base_meta;
			uvec4 lox_loy = uBVHNodes[child_node_index].m_lox_loy;
			uvec4 loz_hix = uBVHNodes[child_node_index].m_loz_hix;
			uvec4 hiy_hiz = uBVHNodes[child_node_index].m_hiy_hiz;

			float adjusted_idir_x = uintBitsToFloat(((head_w)&0xffu) << 23u) * idir.x;
			float adjusted_idir_y = uintBitsToFloat(((head_w >> 8u) & 0xffu) << 23u) * idir.y;
			float adjusted_idir_z = uintBitsToFloat(((head_w >> 16u) & 0xffu) << 23u) * idir.z;
			vec3 adjusted_origin = (head.xyz - origin) * idir;

			node_group.x = base_meta.x;
			tri_group.x = base_meta.y;
			tri_group.y = 0u;

			uint hitmask = 0u;
			{
				uint meta4 = base_meta.z;
				uint is_inner4 = (meta4 & (meta4 << 1u)) & 0x10101010u;
				uint bit_index4 = (meta4 ^ (octinv4 & (is_inner4 >> 4u) * 0xffu)) & 0x1f1f1f1fu;
				uint child_bits4 = (meta4 >> 5u) & 0x07070707u;

				uint swizzled_lox = (idir.x < 0) ? loz_hix.z : lox_loy.x;
				uint swizzled_hix = (idir.x < 0) ? lox_loy.x : loz_hix.z;

				uint swizzled_loy = (idir.y < 0) ? hiy_hiz.x : lox_loy.z;
				uint swizzled_hiy = (idir.y < 0) ? lox_loy.z : hiy_hiz.x;

				uint swizzled_loz = (idir.z < 0) ? hiy_hiz.z : loz_hix.x;
				uint swizzled_hiz = (idir.z < 0) ? loz_hix.x : hiy_hiz.z;

				txmin = vec4(ivec4(swizzled_lox, swizzled_lox >> 8, swizzled_lox >> 16, swizzled_lox >> 24) & 0xffu) * adjusted_idir_x + vec4(adjusted_origin.x);
				
				tymin = vec4(ivec4(swizzled_loy, swizzled_loy >> 8, swizzled_loy >> 16, swizzled_loy >> 24) & 0xffu) * adjusted_idir_y + vec4(adjusted_origin.y);
				
				tzmin = vec4(ivec4(swizzled_loz, swizzled_loz >> 8, swizzled_loz >> 16, swizzled_loz >> 24) & 0xffu) * adjusted_idir_z + vec4(adjusted_origin.z);

				txmax = vec4(ivec4(swizzled_hix, swizzled_hix >> 8, swizzled_hix >> 16, swizzled_hix >> 24) & 0xffu) * adjusted_idir_x + vec4(adjusted_origin.x);
				
				tymax = vec4(ivec4(swizzled_hiy, swizzled_hiy >> 8, swizzled_hiy >> 16, swizzled_hiy >> 24) & 0xffu) * adjusted_idir_y + vec4(adjusted_origin.y);
				
				tzmax = vec4(ivec4(swizzled_hiz, swizzled_hiz >> 8, swizzled_hiz >> 16, swizzled_hiz >> 24) & 0xffu) * adjusted_idir_z + vec4(adjusted_origin.z);

				ctmin = max(max(txmin[0], tymin[0]), max(tzmin[0], hit_tmin));
				ctmax = min(min(txmax[0], tymax[0]), min(tzmax[0], hit_t));
				if (ctmin <= ctmax)
					hitmask |= ((child_bits4)&0xffu) << ((bit_index4)&0xffu);

				ctmin = max(max(txmin[1], tymin[1]), max(tzmin[1], hit_tmin));
				ctmax = min(min(txmax[1], tymax[1]), min(tzmax[1], hit_t));
				if (ctmin <= ctmax)
					hitmask |= ((child_bits4 >> 8u) & 0xffu) << ((bit_index4 >> 8u) & 0xffu);

				ctmin = max(max(txmin[2], tymin[2]), max(tzmin[2], hit_tmin));
				ctmax = min(min(txmax[2], tymax[2]), min(tzmax[2], hit_t));
				if (ctmin <= ctmax)
					hitmask |= ((child_bits4 >> 16u) & 0xffu) << ((bit_index4 >> 16u) & 0xffu);

				ctmin = max(max(txmin[3], tymin[3]), max(tzmin[3], hit_tmin));
				ctmax = min(min(txmax[3], tymax[3]), min(tzmax[3], hit_t));
				if (ctmin <= ctmax)
					hitmask |= ((child_bits4 >> 24u) & 0xffu) << ((bit_index4 >> 24u) & 0xffu);
			}

			{
				uint meta4 = base_meta.w;
				uint is_inner4 = (meta4 & (meta4 << 1u)) & 0x10101010u;
				uint bit_index4 = (meta4 ^ (octinv4 & (is_inner4 >> 4u) * 0xffu)) & 0x1f1f1f1fu;
				uint child_bits4 = (meta4 >> 5u) & 0x07070707u;

				uint swizzled_lox = (idir.x < 0) ? loz_hix.w : lox_loy.y;
				uint swizzled_hix = (idir.x < 0) ? lox_loy.y : loz_hix.w;

				uint swizzled_loy = (idir.y < 0) ? hiy_hiz.y : lox_loy.w;
				uint swizzled_hiy = (idir.y < 0) ? lox_loy.w : hiy_hiz.y;

				uint swizzled_loz = (idir.z < 0) ? hiy_hiz.w : loz_hix.y;
				uint swizzled_hiz = (idir.z < 0) ? loz_hix.y : hiy_hiz.w;

				txmin = vec4(ivec4(swizzled_lox, swizzled_lox >> 8, swizzled_lox >> 16, swizzled_lox >> 24) & 0xffu) * adjusted_idir_x + vec4(adjusted_origin.x);
				
				tymin = vec4(ivec4(swizzled_loy, swizzled_loy >> 8, swizzled_loy >> 16, swizzled_loy >> 24) & 0xffu) * adjusted_idir_y + vec4(adjusted_origin.y);
				
				tzmin = vec4(ivec4(swizzled_loz, swizzled_loz >> 8, swizzled_loz >> 16, swizzled_loz >> 24) & 0xffu) * adjusted_idir_z + vec4(adjusted_origin.z);

				txmax = vec4(ivec4(swizzled_hix, swizzled_hix >> 8, swizzled_hix >> 16, swizzled_hix >> 24) & 0xffu) * adjusted_idir_x + vec4(adjusted_origin.x);
				
				tymax = vec4(ivec4(swizzled_hiy, swizzled_hiy >> 8, swizzled_hiy >> 16, swizzled_hiy >> 24) & 0xffu) * adjusted_idir_y + vec4(adjusted_origin.y);
				
				tzmax = vec4(ivec4(swizzled_hiz, swizzled_hiz >> 8, swizzled_hiz >> 16, swizzled_hiz >> 24) & 0xffu) * adjusted_idir_z + vec4(adjusted_origin.z);

				ctmin = max(max(txmin[0], tymin[0]), max(tzmin[0], hit_tmin));
				ctmax = min(min(txmax[0], tymax[0]), min(tzmax[0], hit_t));
				if (ctmin <= ctmax)
					hitmask |= ((child_bits4)&0xffu) << ((bit_index4)&0xffu);

				ctmin = max(max(txmin[1], tymin[1]), max(tzmin[1], hit_tmin));
				ctmax = min(min(txmax[1], tymax[1]), min(tzmax[1], hit_t));
				if (ctmin <= ctmax)
					hitmask |= ((child_bits4 >> 8u) & 0xffu) << ((bit_index4 >> 8u) & 0xffu);

				ctmin = max(max(txmin[2], tymin[2]), max(tzmin[2], hit_tmin));
				ctmax = min(min(txmax[2], tymax[2]), min(tzmax[2], hit_t));
				if (ctmin <= ctmax)
					hitmask |= ((child_bits4 >> 16u) & 0xffu) << ((bit_index4 >> 16u) & 0xffu);

				ctmin = max(max(txmin[3], tymin[3]), max(tzmin[3], hit_tmin));
				ctmax = min(min(txmax[3], tymax[3]), min(tzmax[3], hit_t));
				if (ctmin <= ctmax)
					hitmask |= ((child_bits4 >> 24u) & 0xffu) << ((bit_index4 >> 24u) & 0xffu);
			}

			node_group.y = (hitmask & 0xff000000u) | ((head_w >> 24u) & 0xffu);
			tri_group.y = hitmask & 0x00ffffffu;
		} else {
			tri_group = node_group;
			node_group = uvec2(0);
		}

		while (tri_group.y != 0) {
			uint tridx = findLSB(tri_group.y);
			tri_group.y &= ~(1u << tridx);
			tridx += tri_group.x;

			tv00 = uBVHTriMatrices[tridx].m0;
			tv11 = uBVHTriMatrices[tridx].m1;
			tv22 = uBVHTriMatrices[tridx].m2;
			
			tt = (tv00.w - dot(origin, tv00.xyz)) / dot(dir, tv00.xyz);
		
			if (tt > hit_tmin && tt < hit_t) {
				position = origin + tt*dir;
				tu = tv11.w + dot(position, tv11.xyz);
				if (tu >= 0.0 && tu <= 1.0) {
					tv = tv22.w + dot(position, tv22.xyz);
					if (tv >= 0.0 && tu + tv <= 1.0) {
						hit_t = tt;
						return true;
					}
				}
			}
		}

		if (node_group.y <= 0x00ffffffu) {
			if (stack_ptr == 0u)
				break;
			node_group = stack[--stack_ptr];
		}
	}
	return false;
}

void TriangleFetchInfo(in const uint tri_idx,
                       in const vec2 tri_uv,
                       out vec3 position,
                       out vec3 normal,
                       out vec3 emissive,
                       out vec3 diffuse,
                       out vec3 specular,
                       inout Material mtl) {
	TrianglePkd tri = uTriangles[tri_idx];
	mtl = uTriMaterials[tri.m_material_id];
	normal = normalize(decompress_unit_vec(tri.m_n1) * tri_uv.x +
	                   decompress_unit_vec(tri.m_n2) * tri_uv.y +
	                   decompress_unit_vec(tri.m_n3) * (1.0 - tri_uv.x - tri_uv.y));
	
	//m_tcP1len, m_tcP2len, m_pppl
	vec3 m_pxUnpacked = decompress_unit_vec(tri.m_px) * tri.m_pxl;
	 
	//vec3 m_ppp = decompress_unit_vec(tri.m_ppp) * tri.m_pppl;
	vec3 m_ppp = decompress_unit_vec(tri.m_ppp) * m_pxUnpacked[2];
	
	vec3 m_p1 = decompress_unit_vec(tri.m_p1v) * m_ppp[0];
	vec3 m_p2 = decompress_unit_vec(tri.m_p2v) * m_ppp[1] + m_p1;
	vec3 m_p3 = decompress_unit_vec(tri.m_p3v) * m_ppp[2] + m_p1;
	position = m_p1 * tri_uv.x +
	           m_p2 * tri_uv.y +
	           m_p3 * (1.0 - tri_uv.x - tri_uv.y);
	if (mtl.m_dtex != 0xffffffffu) {
		//vec3 m_tc1 = decompress_unit_vec(tri.m_tcP1) * tri.m_tcP1len;
		//vec3 m_tc2 = decompress_unit_vec(tri.m_tcP2) * tri.m_tcP2len;
		vec3 m_tc1 = decompress_unit_vec(tri.m_tcP1) * m_pxUnpacked[0];
		vec3 m_tc2 = decompress_unit_vec(tri.m_tcP2) * m_pxUnpacked[1];
		vec2 texcoords = vec2(m_tc1[0], m_tc1[1]) * tri_uv.x + vec2(m_tc1[2], m_tc2[0]) * tri_uv.y +
		                 vec2(m_tc2[1], m_tc2[2]) * (1.0 - tri_uv.x - tri_uv.y);
		diffuse = texture(uTextures[mtl.m_dtex], texcoords).rgb;
	} else
		diffuse = mtl.m_diffuse;
	specular = mtl.m_specular;
	emissive = mtl.m_emission;
}

vec3 TriangleFetchDiffuse(in const uint tri_idx, in const vec2 tri_uv) {
	TrianglePkd tri = uTriangles[tri_idx];
	Material mtl = uTriMaterials[tri.m_material_id];
	if (mtl.m_dtex != 0xffffffffu) {
		//m_tcP1len, m_tcP2len, m_pppl
		vec3 m_pxUnpacked = decompress_unit_vec(tri.m_px) * tri.m_pxl;
	
		vec3 m_tc1 = decompress_unit_vec(tri.m_tcP1) * m_pxUnpacked[0];
		vec3 m_tc2 = decompress_unit_vec(tri.m_tcP2) * m_pxUnpacked[1];
		vec2 texcoords = vec2(m_tc1[0], m_tc1[1]) * tri_uv.x + vec2(m_tc1[2], m_tc2[0]) * tri_uv.y +
		                 vec2(m_tc2[1], m_tc2[2]) * (1.0 - tri_uv.x - tri_uv.y);
		return texture(uTextures[mtl.m_dtex], texcoords).rgb;
	} else
		return mtl.m_diffuse;
}

vec3 TriangleFetchNormal(in const uint tri_idx, in const vec2 tri_uv) {
	TrianglePkd tri = uTriangles[tri_idx];
	return normalize(decompress_unit_vec(tri.m_n1) * tri_uv.x +
	                 decompress_unit_vec(tri.m_n2) * tri_uv.y +
	                 decompress_unit_vec(tri.m_n3) * (1.0 - tri_uv.x - tri_uv.y));
}
