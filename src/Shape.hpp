//
// Created by adamyuan on 7/22/18.
//

#ifndef PATHGL_BVH_SHAPE_HPP
#define PATHGL_BVH_SHAPE_HPP

#include <cfloat>
#include <cinttypes>
#include <cmath>
#include <glm/glm.hpp>

extern glm::vec3 decompress_unit_vec(glm::uint packed);

struct AABB {
	glm::vec3 min, max;

	inline AABB() : min{FLT_MAX}, max{-FLT_MAX} {} // initialize with empty
	inline AABB(const glm::vec3 &t_min, const glm::vec3 &t_max) : min{t_min}, max{t_max} {}

	inline AABB(const AABB &t_a, const AABB &t_b) : min{glm::min(t_a.min, t_b.min)}, max{glm::max(t_a.max, t_b.max)} {}

	inline void Expand(const glm::vec3 &vec) {
		min = glm::min(vec, min);
		max = glm::max(vec, max);
	}
	inline void Expand(const AABB &aabb) {
		min = glm::min(aabb.min, min);
		max = glm::max(aabb.max, max);
	}
	inline void IntersectAABB(const AABB &aabb) {
		min = glm::max(min, aabb.min);
		max = glm::min(max, aabb.max);
	}
	inline bool Valid() const { return min.x <= max.x && min.y <= max.y && min.z <= max.z; }
	inline glm::vec3 GetCenter() const { return (min + max) * 0.5f; }
	template <int DIM> inline float GetDimCenter() const { return (min[DIM] + max[DIM]) * 0.5f; }
	inline float GetDimCenter(int dim) const { return (min[dim] + max[dim]) * 0.5f; }
	inline glm::vec3 GetExtent() const { return max - min; }
	inline float GetHalfArea() const {
		glm::vec3 extent = GetExtent();
		return (extent.x * (extent.y + extent.z) + extent.y * extent.z);
	}
};

struct Triangle {
	glm::vec3 positions[3];

	inline AABB GetAABB() const {
		return {glm::min(positions[0], glm::min(positions[1], positions[2])),
		        glm::max(positions[0], glm::max(positions[1], positions[2]))};
	}
};

// can be directly put into gpu
struct TrianglePkd {
	uint32_t m_p1v, m_p2v, m_p3v, m_n1, m_n2, m_n3, m_tcP1, m_tcP2, m_ppp, m_px;
	float m_pxl;
	uint32_t m_material_id;

	inline AABB GetAABB() const {
	glm::vec3 positions[3], m_pxUnpacked, m_pppV;
			
	//m_tcP1len, m_tcP2len, m_pppl
	m_pxUnpacked = decompress_unit_vec(m_px) * m_pxl;
	 
	//vec3 m_ppp = decompress_unit_vec(tri.m_ppp) * tri.m_pppl;
	m_pppV = decompress_unit_vec(m_ppp) * m_pxUnpacked[2];
	
	positions[0] = decompress_unit_vec(m_p1v) * m_pppV[0];
	positions[1] = decompress_unit_vec(m_p2v) * m_pppV[1] + positions[0];
	positions[2] = decompress_unit_vec(m_p3v) * m_pppV[2] + positions[0];
	
		return {glm::min(positions[0], glm::min(positions[1], positions[2])),
		        glm::max(positions[0], glm::max(positions[1], positions[2]))};
	}
};

#endif // PATHGL_BVH_SHAPE_HPP
