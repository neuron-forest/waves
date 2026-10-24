shader_type spatial;
render_mode cull_back;
varying vec3 world;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float grain=hash(floor((world.xz+world.y*vec2(.73,.47))*240.0));
 float ribbons=sin(world.x*19.0+sin(world.z*4.0)*1.8)*0.006;
 float damp=1.0-smoothstep(-0.02,0.20,world.y);
 vec3 sand=mix(vec3(0.88,0.69,0.42),vec3(0.56,0.41,0.23),damp*0.55);
 ALBEDO=sand*(0.98+grain*0.04+ribbons);ROUGHNESS=mix(0.92,0.82,damp);
}
