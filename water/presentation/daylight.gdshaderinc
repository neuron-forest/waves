// Shared procedural daylight: identical radiance for sky and water reflection.
uniform vec3 sun_direction=vec3(-0.45,0.65,-0.63);
vec3 daylight_reflection(vec3 d){
 float up=clamp(d.y,0.0,1.0);
 vec3 sky=mix(vec3(0.24,0.43,0.55),vec3(0.065,0.19,0.35),pow(up,0.45));
 if(d.y<0.0)sky=mix(vec3(0.43,0.34,0.21),vec3(0.24,0.43,0.55),exp(d.y*12.0));
 float sun=max(dot(normalize(sun_direction),d),0.0);
 sky+=vec3(1.0,0.87,0.65)*0.035*pow(sun,32.0);
 return sky;
}
vec3 daylight(vec3 d){
 float sun=max(dot(normalize(sun_direction),d),0.0);
 // The visible sky has a disk. Water accounts for reflected sunlight once,
 // through its rough specular lobe, rather than a second perfect mirror disk.
 return daylight_reflection(d)+vec3(1.0,0.87,0.65)*2.0*pow(sun,1800.0);
}
