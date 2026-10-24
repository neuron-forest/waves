shader_type sky;
#include "daylight.gdshaderinc"
void sky(){COLOR=daylight(EYEDIR);}
