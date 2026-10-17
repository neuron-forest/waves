extends "res://water/pressure_gpu.gd"
# Split geometric VOF transport and MAC pressure projection.
var motion_work: RID
var history: RID
var collecting_commands=false
var collected_commands=[]
func _init(settings: Dictionary):
 super(settings)
 config.transport_cache=true
 config.transport_interior=false
 config.reconstruct=true
 config.control_bytes=256
 config.pressure_work_fields=14
 iterations_per_batch=8
 if not config.has("batches"):config.batches=4
func _params(op: int,steps: float) -> PackedByteArray:
 var result=super._params(op,steps)
 result.append_array(PackedFloat32Array([config.get("shape",0),config.get("gravity",1),1 if config.get("max_face_cfl",false) else 0,config.get("history_capacity",2400)]).to_byte_array())
 var wave: Vector4=config.get("wave",Vector4.ZERO)
 result.append_array(PackedFloat32Array([wave.x,wave.y,wave.z,wave.w]).to_byte_array())
 result.append_array(PackedFloat32Array([config.get("pressure_tolerance",1e-4),1 if config.get("linear_air",false) else 0,1 if config.get("stokes_second",false) else 0,(1 if config.get("height_normals",false) else 0)+(2 if config.get("active_advection",true) else 0)+(4 if config.get("transport_cache",false) else 0)+(8 if config.get("transport_interior",false) else 0)]).to_byte_array())
 return result
func _extra_uniforms(count: int) -> Array[RDUniform]:
 var face_count=(n.x+1)*n.y*n.z+n.x*(n.y+1)*n.z+n.x*n.y*(n.z+1)
 var sizes=[(4*count+(12 if config.get("transport_cache",false) else 6)*face_count)*4,config.get("history_capacity",2400)*4*16]
 var names=["VOF / MacCormack / extension / banked validity masks","every coupled sweep and accepted step"]
 var result: Array[RDUniform]=[]
 for i in 2:
  var buffer=track(rd.storage_buffer_create(sizes[i]),names[i],sizes[i]);rd.buffer_clear(buffer,0,sizes[i])
  if i==0:motion_work=buffer
  if i==1:history=buffer
  var u=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i+9;u.add_id(buffer);result.append(u)
 return result
func _initial_commands(list: int,count: int):
 var cg=ceili(count/128.0)
 _dispatch(list,0,ceili(physical_stride/128.0),0)
 for op in [40,17,18,16,19,41,42,49]:_dispatch(list,op,1 if op==42 else (ceili(physical_stride/128.0) if op in [40,49] else cg),0)
func _record_commands(list: int,steps: float):
 var cg=ceili(n.x*n.y*n.z/128.0);var sg=ceili(physical_stride/128.0)
 var fg=ceili(((n.x+1)*n.y*n.z+n.x*(n.y+1)*n.z+n.x*n.y*(n.z+1))/128.0)
 _dispatch(list,43,1,steps);_dispatch(list,1,1,steps)
 _dispatch(list,20,cg,steps);_dispatch(list,21,1,steps);_dispatch(list,45,cg,steps);_dispatch(list,46,1,steps);_dispatch(list,22,sg,steps)
 for axis in 3:
  _dispatch(list,23,cg,steps);_dispatch(list,24,fg,steps);_dispatch(list,55,cg,steps);_dispatch(list,56,1,steps);_dispatch(list,25,cg,steps);_dispatch(list,26,1,steps)
 _dispatch(list,27,fg,steps);_dispatch(list,28,fg,steps)
 _after_advection(list,steps)
 for op in [17,18,16]:_dispatch(list,op,cg,steps)
 _dispatch(list,2,sg,steps);_dispatch(list,47,fg,steps);_dispatch(list,63,1,steps);_dispatch(list,64,cg,steps)
 if multigrid:_dispatch(list,200,cg,steps)
 _dispatch(list,3,cg,steps);_dispatch(list,4,1,steps)
 for iteration in iterations_per_batch:
  for op in [5,6,7,8,9,10]:_dispatch(list,op,1 if op in [7,9] else cg,steps)
 _dispatch(list,11,sg,steps);_dispatch(list,65,cg,steps);_dispatch(list,47,fg,steps)
 for op in [30,31,32,33,34,47,48]:_dispatch(list,op,fg,steps)
 _dispatch(list,35,cg,steps);_dispatch(list,36,1,steps)
 _dispatch(list,62,cg,steps);_dispatch(list,66,1,steps);_dispatch(list,12,cg,steps);_dispatch(list,13,1,steps);_dispatch(list,44,1,steps);_dispatch(list,19,cg,steps)
func _after_advection(_list: int,_steps: float):pass
func _stats(data: PackedByteArray):
 var v=data.to_float32_array()
 var reported=v.duplicate()
 var recoverable=(v[7]==20 or (v[7]>=10 and v[7]<=12)) and v[29]<2
 if recoverable:reported[7]=0
 super._stats(reported.to_byte_array())
 var packet={"transport_cache":config.transport_cache,"rhs_integrated_divergence_l2":v[62],"residual_integrated_divergence_l2":v[63],"true_relative_residual":v[60],"pressure_defect_corrections":int(v[58]),"boundary_outflow_m3":v[40],"tentative_outflow_m3":v[39],"raw_compression_volume_m3":v[38],"compression_volume_m3":v[35],"compression_coverage_errors":int(v[36]),"step_start_volume_m3":v[37],"trial_count":int(v[32]),"trial_failure":int(v[7]),"retry_count":int(v[29]),"last_rejection_code":int(v[33]),"last_rejected_dt":v[34],"dt":v[20],"signed_roundoff_m3":v[24],"absolute_roundoff_m3":v[25],"max_CFL":v[27],"mass_defect_m3":v[28],"initial_volume_m3":v[26],"coupled":true,"allocated_bytes":manifest.reduce(func(acc,item):return acc+item.bytes,0)}
 telemetry.emit.call_deferred(packet)
func command_chunks() -> Array:
 collecting_commands=true;collected_commands=[]
 _record_commands(-1,0)
 collecting_commands=false
 var result=[];var chunk=[]
 for command in collected_commands:
  chunk.append(command)
  if command[0] in [22,26,27,28,88,16,4,10,65,36,44,19,61,89]:
   result.append(chunk);chunk=[]
 if not chunk.is_empty():result.append(chunk)
 return result
func _dispatch(list: int,op: int,groups: int,steps: float):
 if collecting_commands:collected_commands.append([op,groups]);return
 super._dispatch(list,op,groups,steps)
