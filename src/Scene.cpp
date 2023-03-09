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

	std::string load_warnings, load_errors;
	if (!tinyobj::LoadObj(&attrib, &shapes, &ret->m_materials, &load_warnings, &load_errors, filename,
	                      ret->m_base_dir.c_str())) {
		spdlog::error("Failed to load {}", filename);
		return nullptr;
	}

	if (ret->m_materials.empty()) {
		spdlog::error("No material found");
		return nullptr;
	}
	if (!load_errors.empty()) {
		spdlog::error("{}", load_errors.c_str());
		return nullptr;
	}
	if (!load_warnings.empty()) {
		spdlog::warn("{}", load_warnings.c_str());
	}

	ret->extract_shapes(attrib, shapes);
	ret->normalize();

	spdlog::info("{} triangles loaded from {}", ret->m_triangles.size(), filename);

	return ret;
}

void Scene::extract_shapes(const tinyobj::attrib_t &attrib, const std::vector<tinyobj::shape_t> &shapes) {
	bool gen_normal_warn = false;
	size_t i3;
	glm::vec3 positions[3], normals[3], deltas[2];
	glm::vec2 texcoords[3];
	float len;
	
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
					tri.matid = shape.mesh.material_ids[face];

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
					
					tri.positions[0] = positions[0];
					tri.positions[1] = positions[1];
					tri.positions[2] = positions[2];

					// generate normal
					if (index.normal_index == -1) {
						tri.normals[2] = tri.normals[0] = tri.normals[1] = glm::normalize(
						    glm::cross(positions[1] - positions[0], positions[2] - positions[0]));
						gen_normal_warn = true;
					} else {
						tri.normals[0] = normals[0];
						tri.normals[1] = normals[1];
						tri.normals[2] = normals[2];
					}
					
					tri.texcoords[0] = texcoords[0];
					tri.texcoords[1] = texcoords[1];
					tri.texcoords[2] = texcoords[2];
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
