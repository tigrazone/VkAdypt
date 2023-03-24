#include "Scene.hpp"
#include "../shader/compress.glsl"
#include <spdlog/spdlog.h>
#include <tiny_obj_loader.h>

std::shared_ptr<Scene> Scene::CreateFromFile(const char *filename) {
	std::shared_ptr<Scene> ret = std::make_shared<Scene>();
	// get base dir
	{
		size_t len = strlen(filename);
		if (len == 0) {
			spdlog::error("Filename {} invalid", filename);
			return nullptr;
		}
		const char *s = filename + len;
		while (*(s - 1) != '/' && *(s - 1) != '\\' && s > filename)
			s--;
		ret->m_base_dir = {filename, s};
	}

	tinyobj::attrib_t attrib;
	std::vector<tinyobj::shape_t> shapes;
	
	tinyobj::material_t defaultMaterial;
	defaultMaterial.diffuse[0] = 0.5f;
	defaultMaterial.diffuse[1] = 0.5f;
	defaultMaterial.diffuse[2] = 0.5f;
	
	bool noMaterials;

	std::string load_warnings, load_errors;
	if (!tinyobj::LoadObj(&attrib, &shapes, &ret->m_materials, &load_warnings, &load_errors, filename,
	                      ret->m_base_dir.c_str())) {
		spdlog::error("Failed to load {}", filename);
		return nullptr;
	}

	if (noMaterials = ret->m_materials.empty()) {
		spdlog::warn("No material found. Use default");
		ret->m_materials.push_back(defaultMaterial);
	}
	if (!load_errors.empty()) {
		spdlog::error("{}", load_errors.c_str());
		return nullptr;
	}
	if (!load_warnings.empty()) {
		spdlog::warn("{}", load_warnings.c_str());
	}

	ret->extract_shapes(attrib, shapes, noMaterials);
	ret->normalize();

	spdlog::info("{} triangles loaded from {}", ret->m_triangles.size(), filename);

	return ret;
}

void Scene::extract_shapes(const tinyobj::attrib_t &attrib, const std::vector<tinyobj::shape_t> &shapes, const bool noMaterials) {
	bool gen_normal_warn = false;
	size_t i3;
	glm::vec3 positions[3], normals[3], delta;
	glm::vec2 texcoords[3];
	float len;
	
	float m_p1l, m_p2l, m_p3l;
	
	TrianglePkd triPkd;
	
	// Loop over shapes
	for (const auto &shape : shapes) {
		size_t index_offset = 0, face = 0;

		// Loop over faces(polygon)
		for (const auto &num_face_vertex : shape.mesh.num_face_vertices) {
			// Loop over triangles in the face.
			for (size_t v = 0; v < num_face_vertex; v += 3) {
				m_triangles.emplace_back();
				Triangle &tri = m_triangles.back();

				{
					tinyobj::index_t index = shape.mesh.indices[index_offset + v];
					{
						i3 = index.vertex_index + index.vertex_index + index.vertex_index;
						positions[0] = {attrib.vertices[i3],
						                attrib.vertices[i3 + 1],
						                attrib.vertices[i3 + 2]};
						if (~index.normal_index) {
							i3 = index.normal_index + index.normal_index + index.normal_index;
							normals[0] = {attrib.normals[i3],
							              attrib.normals[i3 + 1],
							              attrib.normals[i3 + 2]};
						}

						if (~index.texcoord_index) {
							i3 = index.texcoord_index + index.texcoord_index;
							texcoords[0] = {attrib.texcoords[i3],
							                1.0f - attrib.texcoords[i3 + 1]};
						} else {
							texcoords[0] = {0, 0};
						}
					}
					index = shape.mesh.indices[index_offset + v + 1];
					{
						i3 = index.vertex_index + index.vertex_index + index.vertex_index;
						positions[1] = {attrib.vertices[i3],
						                attrib.vertices[i3 + 1],
						                attrib.vertices[i3 + 2]};
						if (~index.normal_index) {
							i3 = index.normal_index + index.normal_index + index.normal_index;
							normals[1] = {attrib.normals[i3],
							              attrib.normals[i3 + 1],
							              attrib.normals[i3 + 2]};
						}

						if (~index.texcoord_index) {
							i3 = index.texcoord_index + index.texcoord_index;
							texcoords[1] = {attrib.texcoords[i3],
							                1.0f - attrib.texcoords[i3 + 1]};
						} else {
							texcoords[1] = {0, 0};
						}
					}

					index = shape.mesh.indices[index_offset + v + 2];
					{
						
						i3 = index.vertex_index + index.vertex_index + index.vertex_index;
						positions[2] = {attrib.vertices[i3],
						                attrib.vertices[i3 + 1],
						                attrib.vertices[i3 + 2]};
						if (~index.normal_index) {
							i3 = index.normal_index + index.normal_index + index.normal_index;
							normals[2] = {attrib.normals[i3],
							              attrib.normals[i3 + 1],
							              attrib.normals[i3 + 2]};
						}

						if (~index.texcoord_index) {
							i3 = index.texcoord_index + index.texcoord_index;
							texcoords[2] = {attrib.texcoords[i3],
							                1.0f - attrib.texcoords[i3 + 1]};
						} else {
							texcoords[2] = {0, 0};
						}
					}

					// generate normal
					if (index.normal_index == -1) {
						normals[2] = normals[1] = normals[0] = glm::normalize(
						    glm::cross(positions[1] - positions[0], positions[2] - positions[0]));
						gen_normal_warn = true;
					}
					
					tri.positions[0] = positions[0];
					tri.positions[1] = positions[1];
					tri.positions[2] = positions[2];

					//save packed triangle data
					triPkd.m_material_id = noMaterials ? 0 : shape.mesh.material_ids[face];

					//calculate compressed version of positions, texture coords, normals
					len = glm::length(positions[0]);
					triPkd.m_p1v = compress_unit_vec( positions[0] / len );
					m_p1l = len;

					delta = positions[1] - positions[0];
					len = glm::length(delta);
					triPkd.m_p2v = compress_unit_vec( delta / len );
					m_p2l = len;

					delta = positions[2] - positions[0];
					len = glm::length(delta);
					triPkd.m_p3v = compress_unit_vec( delta / len );
					m_p3l = len;

					delta = vec3(m_p1l, m_p2l, m_p3l);
					len = glm::length(delta);
					triPkd.m_ppp = compress_unit_vec( delta / len );
					m_p3l = len;

					triPkd.m_n1 = compress_unit_vec( normals[0] );
					triPkd.m_n2 = compress_unit_vec( normals[1] );
					triPkd.m_n3 = compress_unit_vec( normals[2] );

					delta = vec3(texcoords[0][0], texcoords[0][1], texcoords[1][0]);
					len = glm::length(delta);
					triPkd.m_tcP1 = compress_unit_vec( delta / len );
					m_p1l = len;

					delta = vec3(texcoords[1][1], texcoords[2][0], texcoords[2][1]);
					len = glm::length(delta);
					triPkd.m_tcP2 = compress_unit_vec( delta / len );
					m_p2l = len;

					delta = vec3(m_p1l, m_p2l, m_p3l);
					len = glm::length(delta);
					triPkd.m_px = compress_unit_vec( delta / len );
					triPkd.m_pxl = len;

					m_trianglesPkd.push_back(triPkd);
				}
				m_aabb.Expand(tri.GetAABB());
			}
			index_offset += num_face_vertex;
			face++;
		}
	}
	if (gen_normal_warn)
		spdlog::warn("Missing triangle normal");
}

void Scene::normalize() {
	glm::vec3 extent3 = m_aabb.GetExtent();
	float extent = glm::max(extent3.x, glm::max(extent3.y, extent3.z)) * 0.5f;
	float inv_extent = 1.0f / extent;
	glm::vec3 center = m_aabb.GetCenter();
	for (auto &i : m_triangles) {
		i.positions[0] = (i.positions[0] - center) * inv_extent;
		i.positions[1] = (i.positions[1] - center) * inv_extent;
		i.positions[2] = (i.positions[2] - center) * inv_extent;
	}
	m_aabb.min = (m_aabb.min - center) * inv_extent;
	m_aabb.max = (m_aabb.max - center) * inv_extent;

	spdlog::info("triangles normalized to ({}, {}, {}), ({}, {}, {})", m_aabb.min.x, m_aabb.min.y, m_aabb.min.z,
	             m_aabb.max.x, m_aabb.max.y, m_aabb.max.z);
}
