shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
// The PS1 material for decals that sit just off a surface (car liveries):
// same look, plus a depth offset so the surface below never shows through.
#define PSX_DECAL
#include "res://assets/vfx/shaders/psx_lit.gdshaderinc"
