shader_type spatial;
render_mode unshaded, fog_disabled, cull_front;
uniform sampler3D plane_texture : filter_nearest, repeat_disable;
uniform sampler3D kind_texture : filter_nearest, repeat_disable;
uniform ivec3 grid=ivec3(96,64,64);
uniform vec3 BMIN=vec3(-1.0,-0.6,-0.7);
uniform vec3 BMAX=vec3(1.0,0.6,0.7);
void fragment(){
 vec3 origin=INV_VIEW_MATRIX[3].xyz;
 vec3 proxy=(INV_VIEW_MATRIX*vec4(VERTEX,1.0)).xyz;
 vec3 dir=normalize(proxy-origin);
 // Orthographic rays share a direction but have distinct origins.
 if(PROJECTION_MATRIX[3][3]>.5){dir=-normalize(INV_VIEW_MATRIX[2].xyz);origin=proxy-dir*dot(proxy-origin,dir);}
 vec3 safe_dir=vec3(abs(dir.x)<1e-8?1e-8:dir.x,abs(dir.y)<1e-8?1e-8:dir.y,abs(dir.z)<1e-8?1e-8:dir.z);
 vec3 t0=(BMIN-origin)/safe_dir,t1=(BMAX-origin)/safe_dir;
 vec3 lo=min(t0,t1),hi=max(t0,t1);
 float start=max(0.0,max(lo.x,max(lo.y,lo.z))), finish=min(hi.x,min(hi.y,hi.z));
 if(finish<=start)discard;
 vec3 h=(BMAX-BMIN)/vec3(grid);
 float t=start+1e-6;
 float first=-1.0, occupied=0.0;
 vec3 first_normal=vec3(0,1,0),entry_normal=vec3(0,1,0);
 int queries=0;
 bool overflow=true;
 for(int step=0;step<512;step++){
  if(t>=finish-1e-6){overflow=false;break;}
  vec3 x=origin+dir*t;
  ivec3 cell=clamp(ivec3(floor((x-BMIN)/h)),ivec3(0),grid-ivec3(1));
  vec3 corner=BMIN+vec3(cell)*h;
  vec3 next_face=corner+vec3(dir.x>=0.0?h.x:0.0,dir.y>=0.0?h.y:0.0,dir.z>=0.0?h.z:0.0);
  vec3 exits=(next_face-origin)/safe_dir;
  float end=min(finish,min(exits.x,min(exits.y,exits.z)));
  end=max(t+1e-7,end);
  vec3 uv=(vec3(cell)+0.5)/vec3(grid);
  float kind=texture(kind_texture,uv).r; queries++;
  float enter_liquid=t,exit_liquid=end;
  vec3 normal=entry_normal;
  if(kind>1.5){
   vec4 plane=texture(plane_texture,uv);queries++;
   float rate=dot(plane.xyz,dir/h);
   float value=dot(plane.xyz,(origin-corner)/h)-plane.w;
   if(abs(rate)<1e-10){if(value>0.0)exit_liquid=enter_liquid;}
   else{
    float crossing=-value/rate;
    if(rate<0.0){
     if(crossing>enter_liquid){enter_liquid=crossing;normal=normalize(plane.xyz/h);}
    }else exit_liquid=min(exit_liquid,crossing);
   }
  }else if(kind<0.5){exit_liquid=enter_liquid;}
  enter_liquid=max(t,enter_liquid);exit_liquid=min(end,exit_liquid);
  if(exit_liquid>enter_liquid+1e-7){
   occupied+=exit_liquid-enter_liquid;
   if(first<0.0){first=enter_liquid;first_normal=normal;overflow=false;break;}
  }
  if(exits.x<=exits.y&&exits.x<=exits.z)entry_normal=vec3(-sign(dir.x),0,0);
  else if(exits.y<=exits.z)entry_normal=vec3(0,-sign(dir.y),0);
  else entry_normal=vec3(0,0,-sign(dir.z));
  t=end+1e-6;
 }
 if(first<0.0)discard;
 vec3 hit=origin+dir*first;
 vec4 clip=PROJECTION_MATRIX*VIEW_MATRIX*vec4(hit,1.0);
 DEPTH=clip.z/clip.w;
 float diffuse=0.28+0.72*max(0.0,dot(first_normal,normalize(vec3(-0.4,0.8,0.5))));
 ALBEDO=vec3(0.54)*diffuse;
 if(overflow)ALBEDO=vec3(1,0,1);
}
