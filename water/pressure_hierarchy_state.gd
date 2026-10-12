extends RefCounted
# GPU hierarchy invalidation and immutable coefficient snapshots.
var owner
var rd: RenderingDevice
var snapshot: RID
var previous: RID
var state: RID
var pipeline: RID
var bindings: RID
var payloads=[]
var byte_count=0
var ready=false
func _init(controller):
 owner=controller;rd=owner.rd
 var count=owner.n.x*owner.n.y*owner.n.z
 var capacity=owner.config.get("history_capacity",10000)
 byte_count=(64+32*capacity)*4
 snapshot=owner.track(rd.storage_buffer_create(9*count*4),"immutable preconditioner fine coefficients / mask / connections",9*count*4)
 previous=owner.track(rd.storage_buffer_create(9*count*4),"previous-trial operator audit",9*count*4)
 state=owner.track(rd.storage_buffer_create(byte_count),"hierarchy invalidation and per-trial change counts",byte_count)
 for item in [[snapshot,9*count*4],[previous,9*count*4],[state,byte_count]]:rd.buffer_clear(item[0],0,item[1])
 var compiled=preload("res://water/compute_source.gd").compile(rd,"res://water/shaders/compute/pressure_hierarchy_state.glsl")
 var error=compiled.spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
 if not error.is_empty():push_error(error);return
 var shader=owner.track(rd.shader_create_from_spirv(compiled.spirv),"hierarchy audit shader")
 pipeline=owner.track(rd.compute_pipeline_create(shader),"hierarchy audit pipeline")
 var buffers=[owner.pressure_work,owner.geometry,owner.control,snapshot,previous,state]
 var uniforms: Array[RDUniform]=[]
 for i in buffers.size():
  var u=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(buffers[i]);uniforms.append(u)
 bindings=owner.track(rd.uniform_set_create(uniforms,shader,0),"hierarchy audit bindings")
 assert(owner.config.get("mg_lag",4)>=1,"Hierarchy lag must be at least one trial")
 var mode=["rebuild","structure","lagged"].find(owner.config.get("mg_maintenance","rebuild"));assert(mode>=0)
 for op in 5:payloads.append(PackedInt32Array([owner.n.x,owner.n.y,owner.n.z,op,1 if owner.config.get("periodic_x",false) else 0,mode,owner.config.get("mg_lag",4),capacity]).to_byte_array())
 ready=pipeline.is_valid() and bindings.is_valid()
func record(list: int,finish=false):
 rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,bindings,0)
 for op in [4] if finish else [0,1,2,3]:
  rd.compute_list_set_push_constant(list,payloads[op],32)
  rd.compute_list_dispatch(list,ceili(owner.n.x*owner.n.y*owner.n.z/128.0) if op in [1,3] else 1,1,1);rd.compute_list_add_barrier(list)
 rd.compute_list_bind_compute_pipeline(list,owner.pipeline);rd.compute_list_bind_uniform_set(list,owner.bindings,0);owner.iteration_active=false
