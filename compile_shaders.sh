#!/bin/bash

$VULKAN_SDK/bin/glslc shader/quad.vert -o shader/include/spirv/quad.vert.u32 -O -Os -mfmt=num
$VULKAN_SDK/bin/glslc shader/sobol.comp -o shader/include/spirv/sobol.comp.u32 -O -Os -mfmt=num
$VULKAN_SDK/bin/glslc shader/ray_tracer.frag -o shader/include/spirv/ray_tracer.frag.u32 -O -Os -mfmt=num
