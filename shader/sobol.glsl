#ifndef SOBOL_GLSL
#define SOBOL_GLSL

#ifndef SOBOL_SET
#define SOBOL_SET 3
#endif

#define ONEofBiggestLONG 0.00000000023283064365386962890625

layout(std430, set = SOBOL_SET, binding = 0) buffer uuSobol { uint uSobol[]; };

vec2 Sobol_GetVec2(in const uint i) { return vec2(uSobol[i << 1u], uSobol[i << 1u | 1u]) * ONEofBiggestLONG; }

#define Sobol_Current(dim) (uSobol[dim])

vec2 Sobol_GetVec20 = vec2(uSobol[0], uSobol[1]) * ONEofBiggestLONG;

#endif
