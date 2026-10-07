#[compute]
#version 450
#define COUPLED
#define COASTAL
#include "periodic_index.glslinc"
#include "pressure_core.glslinc"
#include "plic_math.glslinc"
#include "coastal_target.glslinc"
#include "pressure_geometry.glslinc"
#include "height_normal.glslinc"
#include "pressure_iterations.glslinc"
#include "pressure_pass.glslinc"
#include "coupled_motion.glslinc"
#include "coastal_pass.glslinc"
void main(){int op=int(pc.dims_op.w);if(op>=80)coastal_pass();else if(op>=20)motion_pass();else pressure_pass();}
