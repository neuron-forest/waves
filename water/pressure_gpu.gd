extends RefCounted
# GPU pressure resources and accepted-state scheduling.
signal telemetry(packet: Dictionary)
var planes=Texture3DRD.new()
var kinds=Texture3DRD.new()
var config: Dictionary
var n: Vector3i
var spacing: Vector3
var origin: Vector3
var rd: RenderingDevice
var shader: RID
var pipeline: RID
var iteration_active=false
var bindings: RID
var banks: Array[RID]=[]
var rids: Array[RID]=[]
var control: RID
var geometry: RID
var pressure_work: RID
var reduction_work: RID
var multigrid
var manifest: Array[Dictionary]=[]
var target=0.0
var lock=Mutex.new()
var closed=false
var ready=false
var iterations_per_batch=8
var total_record_us=0
var total_gpu_ns=0
var timestamp_seen=-1
var timestamp_prefix=""
var physical_stride=0
var parameter_cache={}
var parameter_target=INF
var batches_last_frame=0
var last_stats={}
var work_scheduler
var scheduled_dispatches=0
var scheduled_iterations=0
func _init(settings: Dictionary):
 config=settings.duplicate(true);n=config.n;spacing=config.spacing;origin=config.origin
 config.mg_smoother="chebyshev";config.mg_smoothing=3
 config.mg_maintenance="lagged";config.mg_lag=8;config.mg_aggregate_from=2
 timestamp_prefix="pressure_"+str(get_instance_id())
func start():
 RenderingServer.call_on_render_thread(_initialize)
 RenderingServer.frame_pre_draw.connect(_pre_draw)
func request(steps: int):
 lock.lock();target=steps;lock.unlock()
# Negative quota means an absolute accepted-time deadline; positive means steps.
# Reissuing either quota is idempotent. Only GPU acceptance advances the clock.
func request_time(seconds: float):
 assert(is_finite(seconds) and seconds>=0)
 lock.lock();target=-seconds;lock.unlock()
func close():
 if closed:return
 closed=true
 if RenderingServer.frame_pre_draw.is_connected(_pre_draw):RenderingServer.frame_pre_draw.disconnect(_pre_draw)
 RenderingServer.call_on_render_thread(_free)
func _pre_draw():
 lock.lock();var count=target;lock.unlock()
 RenderingServer.call_on_render_thread(_frame.bind(count))
func track(rid: RID,name: String,bytes=0) -> RID:
 rids.append(rid);rd.set_resource_name(rid,name)
 if bytes>0:manifest.append({"name":name,"bytes":bytes})
 return rid
func _params(op: int,steps: float) -> PackedByteArray:
 return PackedFloat32Array([n.x,n.y,n.z,op,spacing.x,spacing.y,spacing.z,config.get("dt",1.0/120),origin.x,origin.y,origin.z,config.eta,1 if config.get("periodic_x",false) else 0,config.get("slope",0),config.get("corrugation",0),steps]).to_byte_array()
func _dispatch(list: int,op: int,groups: int,steps: float):
 if op==200:
  if multigrid:multigrid.record(list,true)
  return
 if multigrid and (op==4 or op==9):
  multigrid.record(list,false,op==4)
 scheduled_dispatches+=1
 if op==5:scheduled_iterations+=1
 if parameter_target!=steps:parameter_cache.clear();parameter_target=steps
 if not parameter_cache.has(op):parameter_cache[op]=_params(op,steps)
 var params: PackedByteArray=parameter_cache[op]
 rd.compute_list_set_push_constant(list,params,params.size())
 rd.compute_list_dispatch(list,groups,1,1);rd.compute_list_add_barrier(list)
func _initialize():
 rd=RenderingServer.get_rendering_device()
 if rd==null:push_error("Waves requires a Vulkan RenderingDevice");telemetry.emit.call_deferred({"failure":99});return
 var compilation=preload("res://water/compute_source.gd").compile(rd,config.shader)
 var spirv=compilation.spirv
 telemetry.emit.call_deferred({"shader_source_sha256":compilation.source_sha256})
 var error=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
 if not error.is_empty():push_error(error);telemetry.emit.call_deferred({"failure":99,"compile_error":error});return
 shader=track(rd.shader_create_from_spirv(spirv),"VOF pressure",0)
 pipeline=track(rd.compute_pipeline_create(shader),"VOF pipeline",0)
 var count=n.x*n.y*n.z
 physical_stride=2*count+(n.x+1)*n.y*n.z+n.x*(n.y+1)*n.z+n.x*n.y*(n.z+1)
 var sizes=[physical_stride*4,physical_stride*4,count*config.get("pressure_work_fields",13)*4,count*8,ceili(count/128.0)*16,config.get("control_bytes",128)]
 var names=["physical bank A F/u/v/w/p","physical bank B F/u/v/w/p","PCG vectors and cached face coefficients","analytic phi / flags","reduction partials","acceptance / PCG control"]
 var uniforms: Array[RDUniform]=[]
 for i in sizes.size():
  var buffer=track(rd.storage_buffer_create(sizes[i]),names[i],sizes[i])
  rd.buffer_clear(buffer,0,sizes[i])
  if i<2:banks.append(buffer)
  if i==5:control=buffer
  if i==3:geometry=buffer
  if i==2:pressure_work=buffer
  if i==4:reduction_work=buffer
  var u=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(buffer);uniforms.append(u)
 for i in 2:
  var format=RDTextureFormat.new();format.texture_type=RenderingDevice.TEXTURE_TYPE_3D
  format.width=n.x;format.height=n.y;format.depth=n.z
  format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT if i==0 else RenderingDevice.DATA_FORMAT_R32_SFLOAT
  format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
  if not rd.texture_is_format_supported_for_usage(format.format,format.usage_bits):push_error("Water export format unsupported");telemetry.emit.call_deferred({"failure":98});return
  var image=track(rd.texture_create(format,RDTextureView.new(),[]),"accepted planes" if i==0 else "accepted kinds",count*(16 if i==0 else 4))
  var u=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;u.binding=6+i;u.add_id(image);uniforms.append(u)
  if i==0:planes.texture_rd_rid=image
  else:kinds.texture_rd_rid=image
 var plane_buffer=track(rd.storage_buffer_create(count*16),"reconstructed local PLIC",count*16)
 var plane_binding=RDUniform.new();plane_binding.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;plane_binding.binding=8;plane_binding.add_id(plane_buffer);uniforms.append(plane_binding)
 uniforms.append_array(_extra_uniforms(count))
 bindings=track(rd.uniform_set_create(uniforms,shader,0),"VOF bindings")
 multigrid=preload("res://water/pressure_multigrid.gd").new(self)
 if not multigrid.initialize():telemetry.emit.call_deferred({"failure":97});return
 iteration_active=false
 var list=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,bindings,0)
 _initial_commands(list,count)
 rd.compute_list_end();ready=true
 work_scheduler=preload("res://water/work_scheduler.gd").new(self)
 telemetry.emit.call_deferred({"initialized":true,"manifest":manifest.duplicate(true),"allocated_bytes":sizes.reduce(func(acc,value):return acc+value,0)+count*36})
func _initial_commands(_list: int,_count: int):pass
func _extra_uniforms(_count: int) -> Array[RDUniform]:return []
func _frame(steps: float):
 if not ready or closed:return
 work_scheduler.frame(steps)
func _stats(data: PackedByteArray):
 var v=data.to_float32_array()
 var p={"pressure_backend":"multigrid","batches_last_frame":batches_last_frame,"iterations_per_batch":iterations_per_batch,"accepted_index":int(v[0]),"accepted_time":v[1],"accepted_steps":int(v[2]),"rejections":int(v[3]),"pending":v[4]>0.5,"converged":v[6]>0.5,"failure":int(v[7]),"iterations":int(v[8]),"relative_residual":v[13],"max_dt_divergence":v[14],"max_face_speed":v[15],"hydrostatic_error_pa":v[16],"volume_m3":v[17],"total_iterations":int(v[18]),"record_us":total_record_us,"gpu_ns":total_gpu_ns,"R_fluid":total_gpu_ns/1e9/v[1] if v[1]>0 else -1}
 last_stats=p
 telemetry.emit.call_deferred(p)
func _free():
 if work_scheduler:work_scheduler.owner=null;work_scheduler=null
 if multigrid:
  if multigrid.maintenance:multigrid.maintenance.owner=null;multigrid.maintenance=null
  multigrid.owner=null;multigrid=null
 planes.texture_rd_rid=RID();kinds.texture_rd_rid=RID()
 if rd==null:return
 rids.reverse()
 for rid in rids:
  if rid.is_valid():rd.free_rid(rid)
 rids.clear()
 ready=false
