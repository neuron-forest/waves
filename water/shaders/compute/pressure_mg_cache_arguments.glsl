#[compute]
#version 450
layout(local_size_x=128) in;
layout(std430,set=0,binding=0) readonly buffer Control {float c[];};
layout(std430,set=0,binding=1) readonly buffer Levels {int meta[];};
layout(std430,set=0,binding=2) writeonly buffer Arguments {uint args[];};
layout(std430,set=0,binding=3) readonly buffer Maintenance {uint state[];};
layout(push_constant,std430) uniform Parameters {ivec4 run;ivec4 settings;} pc;
void main(){
 int l=int(gl_GlobalInvocationID.x);if(l>=pc.settings.x)return;
 bool on=c[7]<.5;
 if(pc.run.z==2)on=on&&c[5]>.5;
 else if(pc.run.z==0)on=on&&(c[5]>.5||(pc.settings.w!=0&&c[57]==2))&&c[6]<.5;
 else on=on&&c[4]>.5&&c[6]<.5;
 int count=meta[16*l+8];
 for(int kind=0;kind<6;kind++){
  bool selected=on;
  if(pc.run.z==2)selected=selected&&(kind==3?state[9]!=0:(kind==4?(state[14]==0||state[20+l+1]!=0):state[8]!=0));
  uint groups=kind==5?1:uint((count*(kind==1?125:(kind==2?meta[16*l+11]:1))+127)/128);
  uint y=(groups+65534)/65535,x=(groups+y-1)/y;
  args[18*l+3*kind]=(selected?1:0)*x;args[18*l+3*kind+1]=y;args[18*l+3*kind+2]=1;
 }
}
