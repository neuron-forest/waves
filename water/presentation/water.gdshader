shader_type spatial;
render_mode unshaded, fog_disabled, cull_front, depth_draw_always;
#include "daylight.gdshaderinc"
uniform sampler3D plane_texture : filter_nearest, repeat_disable;
uniform sampler3D kind_texture : filter_nearest, repeat_disable;
uniform sampler2D clock_texture : filter_nearest, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform ivec3 grid=ivec3(310,48,8);
uniform vec3 BMIN=vec3(-1.75,-0.6,-0.2);
uniform vec3 BMAX=vec3(6.0,0.6,0.2);
uniform vec3 water_tint : source_color=vec3(0.02745,0.56078,0.62353);
// Metres at which green-channel direct transmission falls to exp(-1).
uniform float attenuation_distance : hint_range(0.04,1.5)=0.18;
uniform float ripple_strength : hint_range(0.0,0.1)=0.0025;
uniform float surface_roughness : hint_range(0.03,0.5)=0.30;
uniform float bed_slope=6.0;
uniform bool contact_correction=true;
uniform bool clock_ready=false;

vec3 safe_ray(vec3 d){return mix(d,vec3(1e-8),lessThan(abs(d),vec3(1e-8)));}
// Sum occupied PLIC intervals, excluding air gaps and clipping to opaque depth.
vec4 trace_water(vec3 origin,vec3 dir,float opaque_limit,out vec3 first_normal,out float first_exit,out bool complete){
 vec3 sd=safe_ray(dir),h=(BMAX-BMIN)/vec3(grid);
 vec3 a=(BMIN-origin)/sd,b=(BMAX-origin)/sd,lo=min(a,b),hi=max(a,b);
 float start=max(0.0,max(lo.x,max(lo.y,lo.z))),finish=min(opaque_limit,min(hi.x,min(hi.y,hi.z)));
 float first=-1.0,occupied=0.0,last_end=-1.0;first_exit=-1.0;complete=true;
 first_normal=vec3(0,1,0);vec3 entry=vec3(0,1,0);
 if(lo.x>=lo.y&&lo.x>=lo.z)entry=vec3(-sign(dir.x),0,0);
 else if(lo.y>=lo.z)entry=vec3(0,-sign(dir.y),0);
 else entry=vec3(0,0,-sign(dir.z));
 if(finish<=start)return vec4(-1,0,0,0);
 float t=start;int queries=0;bool open_first=false;
 for(int step=0;step<640;step++){
  if(t>=finish-1e-7)break;
  vec3 probe=origin+dir*(t+1e-6);
  ivec3 cell=clamp(ivec3(floor((probe-BMIN)/h)),ivec3(0),grid-ivec3(1));
  vec3 corner=BMIN+vec3(cell)*h;
  vec3 next=corner+mix(vec3(0),h,greaterThanEqual(dir,vec3(0)));
  vec3 exits=(next-origin)/sd;
  float end=min(finish,min(exits.x,min(exits.y,exits.z)));
  if(end<=t+1e-8){t+=1e-6;continue;}
  float kind=texelFetch(kind_texture,cell,0).r;queries++;
  vec4 plane=vec4(0);
  if(kind>1.5)plane=texelFetch(plane_texture,cell,0);
  // Extend only the wet footprint from voxel top to smooth bed (<= 14.6 mm).
  // This presentation correction never writes fluid fields or fills the cavity.
  float bed_x=BMIN.x+(float(cell.x)+0.5)*h.x;
  float bed_center=-0.45+max(0.0,bed_x-1.5)/bed_slope;
  int bottom=int(floor((bed_center-BMIN.y)/h.y-0.5))+1;
  if(BMIN.y+(float(bottom)+0.5)*h.y<=bed_center)bottom++;
  if(BMIN.y+(float(bottom)-0.5)*h.y>bed_center)bottom--;
  if(contact_correction&&cell.y==bottom-1&&bottom>=0&&bottom<grid.y){
   ivec3 above=ivec3(cell.x,bottom,cell.z);
   kind=texelFetch(kind_texture,above,0).r;
   if(kind>1.5){plane=texelFetch(plane_texture,above,0);plane.y=0.0;}
  }
  float enter=t,leave=end;vec3 normal=entry;
  if(kind>1.5){
   vec4 p=plane;queries++;
   float rate=dot(p.xyz,dir/h),value=dot(p.xyz,(origin-corner)/h)-p.w;
   if(abs(rate)<1e-10){if(value>0.0)leave=enter;}
   else if(rate<0.0){float crossing=-value/rate;if(crossing>enter){enter=crossing;normal=normalize(p.xyz/h);}}
   else leave=min(leave,-value/rate);
  }else if(kind<0.5)leave=enter;
  if(contact_correction){
   // Identical continuous bathymetry to the opaque sand mesh. Clip buried
   // PLIC water, including when an oblique ray leaves and re-enters terrain.
   float gradient=bed_x>1.5?1.0/bed_slope:0.0;
   float value=origin.y-bed_center-gradient*(origin.x-bed_x);
   float rate=dir.y-gradient*dir.x;
   if(abs(rate)<1e-10){if(value<0.0)leave=enter;}
   else if(rate>0.0){float crossing=-value/rate;if(crossing>enter){enter=crossing;normal=normalize(vec3(gradient,-1,0));}}
   else leave=min(leave,-value/rate);
  }
  enter=max(t,enter);leave=min(end,leave);
  if(leave>enter+1e-7){
   occupied+=leave-enter;
   if(first<0.0){first=enter;first_normal=normal;open_first=true;}
   else if(enter>last_end+4e-6)open_first=false;
   if(open_first)first_exit=leave;
   last_end=leave;
  }else if(first>=0.0)open_first=false;
  if(exits.x<=exits.y&&exits.x<=exits.z)entry=vec3(-sign(dir.x),0,0);
  else if(exits.y<=exits.z)entry=vec3(0,-sign(dir.y),0);
  else entry=vec3(0,0,-sign(dir.z));
  t=end;
  if(step==639&&t<finish-1e-6)complete=false;
 }
 return vec4(first,occupied,finish,float(queries));
}
float normal_weight(float x){
 x=abs(x);
 return x<0.5?0.75-x*x:0.5*pow(max(0.0,1.5-x),2.0);
}
vec3 optical_normal(vec3 hit,vec3 geometric){
 vec3 h=(BMAX-BMIN)/vec3(grid),local=(hit-BMIN)/h-0.5;
 ivec3 lower=ivec3(floor(local));vec3 anchor=geometric;float closest=1e10;
 // A cell-face seam normal is not a physical surface normal. Find the nearest
 // interface orientation first, then average only compatible nearby planes.
 for(int z=0;z<2;z++)for(int y=0;y<2;y++)for(int x=0;x<2;x++){
  ivec3 q=lower+ivec3(x,y,z);
  if(any(lessThan(q,ivec3(0)))||any(greaterThanEqual(q,grid)))continue;
  if(texelFetch(kind_texture,q,0).r<1.5)continue;
  vec4 plane=texelFetch(plane_texture,q,0);vec3 raw=plane.xyz/h;
  float length_n=length(raw);if(length_n<1e-8)continue;vec3 normal=raw/length_n;
  float distance=abs(dot(plane.xyz,(hit-BMIN)/h-vec3(q))-plane.w)/length_n;
  float score=distance/min(h.x,h.y)+0.15*length(local-vec3(q));
  if(distance<0.8*min(h.x,h.y)&&score<closest){closest=score;anchor=normal;}
 }
 vec3 sum=vec3(0);float weights=0.0;ivec3 center=ivec3(floor((hit-BMIN)/h));
 for(int z=-1;z<=1;z++)for(int y=-1;y<=1;y++)for(int x=-2;x<=2;x++){
  ivec3 q=center+ivec3(x,y,z);
  if(any(lessThan(q,ivec3(0)))||any(greaterThanEqual(q,grid)))continue;
  if(texelFetch(kind_texture,q,0).r<1.5)continue;
  vec4 plane=texelFetch(plane_texture,q,0);vec3 raw=plane.xyz/h;
  float length_n=length(raw);if(length_n<1e-8)continue;vec3 normal=raw/length_n;
  float distance=abs(dot(plane.xyz,(hit-BMIN)/h-vec3(q))-plane.w)/length_n;
  vec3 delta=local-vec3(q);
  float weight=normal_weight(delta.x*0.6)*normal_weight(delta.y)*normal_weight(delta.z)*smoothstep(0.15,0.8,dot(normal,anchor))*(1.0-smoothstep(0.7,1.5,distance/min(h.x,h.y)));
  sum+=normal*weight;weights+=weight;
 }
 return weights>0.001?normalize(sum):anchor;
}
void fragment(){
 vec3 origin=INV_VIEW_MATRIX[3].xyz,proxy=(INV_VIEW_MATRIX*vec4(VERTEX,1.0)).xyz;
 vec3 dir=normalize(proxy-origin);
 if(PROJECTION_MATRIX[3][3]>.5){dir=-normalize(INV_VIEW_MATRIX[2].xyz);origin=proxy-dir*dot(proxy-origin,dir);}
 float depth=textureLod(depth_texture,SCREEN_UV,0.0).r,opaque_limit=10000.0;
 if(depth>1e-7){vec4 q=INV_PROJECTION_MATRIX*vec4(SCREEN_UV*2.0-1.0,depth,1.0);vec3 world=(INV_VIEW_MATRIX*vec4(q.xyz/q.w,1.0)).xyz;opaque_limit=max(0.0,dot(world-origin,dir));}
 vec3 gn;float first_exit;bool complete;
 vec4 trace=trace_water(origin,dir,opaque_limit,gn,first_exit,complete);
 if(trace.x<0.0||!complete)discard;
 vec3 hit=origin+dir*trace.x;
 vec4 clip=PROJECTION_MATRIX*VIEW_MATRIX*vec4(hit,1.0);DEPTH=clip.z/clip.w;
 vec3 n=optical_normal(hit,gn);if(dot(n,-dir)<0.0)n=-n;
 vec3 smooth_normal=n;
 float time=clock_ready?texelFetch(clock_texture,ivec2(0),0).r:0.0;
 // Tangential detail only: never displaces the represented surface or depth.
 vec3 ripple=vec3(cos(hit.x*75.0+hit.z*31.0-time*2.5),0.0,sin(hit.z*103.0-hit.x*22.0+time*3.1));
 ripple+=0.35*vec3(sin(hit.z*160.0+time*4.0),cos(hit.x*95.0+time),cos(hit.x*140.0-time*3.0));
 n=normalize(n+ripple_strength*(ripple-n*dot(ripple,n)));
 float nv=clamp(dot(smooth_normal,-dir),0.0,1.0);
 float fresnel=0.02037+(0.97963-surface_roughness*0.35)*pow(1.0-nv,5.0);
 vec3 reflection=daylight_reflection(reflect(dir,n));
 // Opaque-screen refraction is deliberately bounded and validated. Optical
 // depth remains the sum of actual water intervals on the viewing ray.
 vec2 uv=SCREEN_UV;vec3 refracted=refract(dir,n,1.0/1.333);
 vec3 target=hit+refracted*min(max(first_exit-trace.x,0.0),0.35);
 vec4 target_clip=PROJECTION_MATRIX*VIEW_MATRIX*vec4(target,1.0);
 vec2 trial=target_clip.xy/target_clip.w*0.5+0.5;
 trial=SCREEN_UV+clamp((trial-SCREEN_UV)*0.15,vec2(-0.003),vec2(0.003));
 if(all(greaterThan(trial,vec2(0.003)))&&all(lessThan(trial,vec2(0.997)))){
  float other=textureLod(depth_texture,trial,0.0).r;
  if(other>1e-7){
   vec4 v=INV_PROJECTION_MATRIX*vec4(trial*2.0-1.0,other,1.0);vec3 w=(INV_VIEW_MATRIX*vec4(v.xyz/v.w,1.0)).xyz;
   // Reject foreground silhouettes and large depth jumps, never sample a
   // foreground object across the water edge. Sky/off-screen use original UV.
   float along=dot(w-origin,dir);
   if(along>trace.x+0.003&&abs(along-opaque_limit)<0.5)uv=trial;
  }
 }
 vec3 behind=textureLod(screen_texture,uv,0.0).rgb;
 vec3 absorption=vec3(1.4,1.0,0.85)/max(attenuation_distance,0.01);
 vec3 transmission=exp(-absorption*trace.y);
 float deeper=1.0-exp(-trace.y/0.45);
 vec3 scatter=water_tint*mix(vec3(0.65,1.18,1.0),vec3(0.4,0.65,0.92),deeper);
 scatter*=0.55+0.45*max(dot(smooth_normal,normalize(sun_direction)),0.0);
 vec3 body=behind*transmission+scatter*(vec3(1.0)-transmission);
 vec3 half_vector=normalize(normalize(sun_direction)-dir);
 float nh=max(dot(n,half_vector),0.0),a=surface_roughness*surface_roughness,a2=a*a;
 float distribution=a2/(3.14159265*pow(max(nh*nh*(a2-1.0)+1.0,0.001),2.0));
 float nl=max(dot(n,normalize(sun_direction)),0.0);
 vec3 sun=vec3(1.0,0.90,0.74)*min(0.6,distribution*0.007)*nl;
 vec3 color=mix(body,reflection,fresnel)+sun;
 ALBEDO=color;ALPHA=1.0;
}
