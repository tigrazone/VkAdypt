//gpu & cpu common data
#ifndef COMMON_H
#define COMMON_H

#ifdef __cplusplus
using namespace glm;
#endif

struct TrianglePkd {
	uint m_p1v, m_p2v, m_p3v, m_n1, m_n2, m_n3, m_tcP1, m_tcP2, m_ppp, m_px;	// 10
	float m_pxl;																// 1
	uint m_material_id;															// 1 -> 12
};	
	
struct Material {
	vec3 m_diffuse;
	uint m_dtex;
		
	vec3 m_emission;
	uint m_etex;
	
	vec3 m_specular;
	uint m_stex;
	
	uint m_illum;
	float m_shininess;
	float m_dissolve;
	float m_ior;
};

#endif  // COMMON_H
