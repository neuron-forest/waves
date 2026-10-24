#[compute]
#version 450
layout(local_size_x=1) in;
layout(std430,set=0,binding=0) readonly buffer Control {float c[];};
layout(rgba32f,set=0,binding=1) uniform writeonly image2D clock_image;
// Read committed time after PLIC export, including when a trial was rejected.
void main(){imageStore(clock_image,ivec2(0),vec4(c[1],c[2],0,0));}
