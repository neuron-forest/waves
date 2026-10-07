#[compute]
#version 450
// Current operator is read-only. The preconditioner receives a separate snapshot.
layout(local_size_x=128) in;
layout(std430,set=0,binding=0) readonly buffer FineWork {float work[];};
layout(std430,set=0,binding=1) readonly buffer Geometry {vec2 geo[];};
layout(std430,set=0,binding=2) buffer Control {float c[];};
layout(std430,set=0,binding=3) buffer Snapshot {float cached[];};
layout(std430,set=0,binding=4) buffer Previous {float previous[];};
layout(std430,set=0,binding=5) buffer Audit {uint state[];};
layout(push_constant,std430) uniform Params {ivec4 dims;ivec4 policy;} pc;
// dims=nx,ny,nz,op; policy=periodic x, mode(0 rebuild/1 structure/2 lag), max age, history capacity.
// Header [0 initialized,1..7 differences,8 numeric,9 structural,10 age,
// 11 builds,12 structure builds,13 trials,14 initialized-before,15 invalid,16 active].
// Level mask-change counts at20..31. Records:64+32*(trial-1).
shared uvec4 part0[128];shared uvec4 part1[128];shared uvec4 part2[128];
int N(){return pc.dims.x*pc.dims.y*pc.dims.z;}
int modp(int x,int n){return x>=0?x%n:(n-1)-((-1-x)%n);}
uint signature(int i){
 if(geo[i].y<.5)return 0;int n=N();ivec3 q=ivec3(i%pc.dims.x,(i/pc.dims.x)%pc.dims.y,i/(pc.dims.x*pc.dims.y));uint result=0;
 for(int axis=0;axis<3;axis++)for(int side=0;side<2;side++){
  ivec3 nb=q;nb[axis]+=2*side-1;nb.z=modp(nb.z,pc.dims.z);if(pc.policy.x!=0)nb.x=modp(nb.x,pc.dims.x);
  bool inside=nb.x>=0&&nb.x<pc.dims.x&&nb.y>=0&&nb.y<pc.dims.y;
  bool wet=inside&&geo[nb.x+pc.dims.x*(nb.y+pc.dims.y*nb.z)].y>.5;
  uint kind=work[(6+2*axis+side)*n+i]>0?(wet?1:2):0;result|=kind<<uint(2*(2*axis+side));
 }return result;
}
void main(){
 if(c[5]<.5||c[7]>.5)return;int i=int(gl_GlobalInvocationID.x),lid=int(gl_LocalInvocationID.x),op=pc.dims.w,n=N();
 if(op==0){if(i==0){for(int k=1;k<=7;k++)state[k]=0;state[14]=state[0];state[15]=0;state[16]=0;for(int k=20;k<32;k++)state[k]=0;}return;}
 if(op==1){
  uvec4 a=uvec4(0),b=uvec4(0),d=uvec4(0);
  if(i<n){
   a.x=uint(geo[i].y!=cached[7*n+i]);a.w=uint(geo[i].y!=previous[7*n+i]);d.y=uint(geo[i].y>.5);
   uint sig=signature(i),old=uint(cached[8*n+i]),prev=uint(previous[8*n+i]);
   for(int face=0;face<6;face++){a.y+=uint(((sig>>uint(2*face))&3)!=((old>>uint(2*face))&3));b.x+=uint(((sig>>uint(2*face))&3)!=((prev>>uint(2*face))&3));}
   float ratio=0;
   for(int k=0;k<7;k++){
    float value=work[(6+k)*n+i],was=cached[k*n+i];
    a.z+=uint(floatBitsToUint(value)!=floatBitsToUint(was));b.y+=uint(floatBitsToUint(value)!=floatBitsToUint(previous[k*n+i]));
    if(was>0)ratio=max(ratio,abs(value-was)/was);
    if(isnan(value)||isinf(value)||value<0)d.x=1;
   }b.z=floatBitsToUint(ratio);
  }
  part0[lid]=a;part1[lid]=b;part2[lid]=d;barrier();
  for(int s=64;s>0;s>>=1){if(lid<s){part0[lid]+=part0[lid+s];part1[lid].xy+=part1[lid+s].xy;part1[lid].z=max(part1[lid].z,part1[lid+s].z);part2[lid]+=part2[lid+s];}barrier();}
  if(lid==0){for(int k=0;k<4;k++)atomicAdd(state[1+k],part0[0][k]);atomicAdd(state[5],part1[0].x);atomicAdd(state[6],part1[0].y);atomicMax(state[7],part1[0].z);atomicAdd(state[15],part2[0].x);atomicAdd(state[16],part2[0].y);}return;
 }
 if(op==2){
  if(i!=0)return;if(state[15]>0){c[7]=34;return;}
  bool incompatible=state[0]==0||state[1]>0||state[2]>0;
  bool structural=pc.policy.y==0||incompatible;
  bool numerical=pc.policy.y==0||incompatible||(state[3]>0&&(pc.policy.y==1||state[10]+1>=uint(pc.policy.z)));
  state[8]=numerical?1:0;state[9]=structural?1:0;state[10]=numerical||state[3]==0?0:state[10]+1;state[11]+=state[8];state[12]+=state[9];state[13]++;state[0]=1;
  if(state[13]<=uint(pc.policy.w)){
   uint row=64+32*(state[13]-1);state[row]=state[13];state[row+1]=floatBitsToUint(c[1]);
   for(int k=1;k<=7;k++)state[row+1+k]=state[k];
   state[row+9]=state[8];state[row+10]=state[9];state[row+11]=state[10];state[row+12]=state[16];state[row+13]=state[11];
  }return;
 }
 if(op==3){
  if(i>=n)return;
  for(int k=0;k<7;k++){float value=work[(6+k)*n+i];previous[k*n+i]=value;if(state[8]!=0)cached[k*n+i]=value;}
  previous[7*n+i]=geo[i].y;previous[8*n+i]=float(signature(i));
  if(state[8]!=0){cached[7*n+i]=previous[7*n+i];cached[8*n+i]=previous[8*n+i];}return;
 }
 if(op==4){if(i==0&&state[13]<=uint(pc.policy.w)){uint row=64+32*(state[13]-1);for(int l=0;l<12;l++)state[row+16+l]=state[20+l];}return;}
}
