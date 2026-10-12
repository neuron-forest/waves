extends RefCounted
# Cached Galerkin preconditioner; the current fine operator stays authoritative.
var owner
var maintenance
var transfer_buffer: RID
var transfer_count=0
var argument_stride=36
var rd: RenderingDevice
var levels=[]
var matrices: RID
var vectors: RID
var arguments: RID
var rows: RID
var row_count=0
var pipeline: RID
var bindings: RID
var build_pipeline: RID
var build_bindings: RID
var coarse_pipeline: RID
var coarse_bindings: RID
var argument_pipeline: RID
var argument_bindings: RID
var build_commands=[]
var cycle_commands=[]
var payloads={}
var matrix_count=0
var node_count=0
var source_hash=""
var structural_record_us=0
var smoothing=1
var smoother="jacobi"
func _init(controller):owner=controller;rd=owner.rd;smoothing=owner.config.get("mg_smoothing",1);smoother=owner.config.get("mg_smoother","jacobi")
func initialize() -> bool:
 assert(smoother in ["jacobi","chebyshev"] and smoothing>=1 and smoothing<=8)
 argument_stride=72
 var structural_begin=Time.get_ticks_usec()
 var n=owner.n;var h=owner.spacing;var metadata=PackedInt32Array()
 var stencil=[Vector3i.ZERO,Vector3i(-1,0,0),Vector3i(1,0,0),Vector3i(0,-1,0),Vector3i(0,1,0),Vector3i(0,0,-1),Vector3i(0,0,1)]
 var stencils=[]
 while true:
  var count=n.x*n.y*n.z
  var f=Vector3i.ONE
  if count>64:
   var smallest=INF
   for axis in 3:
    if n[axis]>2:smallest=minf(smallest,h[axis])
   for axis in 3:
    if n[axis]>2 and h[axis]<1.8*smallest:f[axis]=2
   if owner.config.get("periodic_x",false) and n.x%2:f.x=1
   if n.z%2:f.z=1
  var aggregate=levels.size()>=owner.config.get("mg_aggregate_from",99)
  stencils.append(stencil)
  levels.append({"n":n,"count":count,"offset":node_count,"matrix_offset":matrix_count,"factor":f,"stencil_count":stencil.size(),"aggregate":aggregate})
  metadata.append_array(PackedInt32Array([n.x,n.y,n.z,node_count,matrix_count,f.x,f.y,f.z,count,0,0,0,0,0,0,1 if aggregate else 0]))
  node_count+=count
  if levels.size()>1:matrix_count+=count*125
  if count<=64 or f==Vector3i.ONE:break
  stencil=_coarse_stencil(stencil,f,aggregate)
  n=Vector3i(ceili(float(n.x)/f.x),ceili(float(n.y)/f.y),ceili(float(n.z)/f.z));h*=Vector3(f)
 assert(levels.size()<=12,"Hierarchy audit supports at most twelve levels")
 for l in levels.size():
  metadata[16*l+10]=metadata.size();metadata[16*l+11]=stencils[l].size()
  metadata[16*l+12]=row_count
  metadata[16*l+13]=transfer_count;metadata[16*l+14]=1 if levels[l].aggregate else levels[l].factor.x*levels[l].factor.y*levels[l].factor.z
  if l+1<levels.size():transfer_count+=levels[l].count*metadata[16*l+14]
  if l>0:row_count+=levels[l].count*stencils[l].size()
  for off in stencils[l]:metadata.append_array(PackedInt32Array([off.x,off.y,off.z]))
 metadata[(levels.size()-1)*16+9]=matrix_count
 matrix_count+=levels[-1].count*levels[-1].count
 structural_record_us=Time.get_ticks_usec()-structural_begin
 var description=owner.track(rd.storage_buffer_create(metadata.size()*4,metadata.to_byte_array()),"MG geometry / level descriptors",metadata.size()*4)
 matrices=owner.track(rd.storage_buffer_create(matrix_count*4),"MG complete symmetric coarse matrices and factor",matrix_count*4)
 vectors=owner.track(rd.storage_buffer_create(node_count*8*4),"MG residual / correction / active / l1 scale",node_count*8*4)
 arguments=owner.track(rd.storage_buffer_create(levels.size()*argument_stride,PackedByteArray(),RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT),"MG GPU-active indirect arguments",levels.size()*argument_stride)
 rows=owner.track(rd.storage_buffer_create(maxi(row_count,1)*8),"MG cached sparse rows",maxi(row_count,1)*8)
 maintenance=preload("res://water/pressure_hierarchy_state.gd").new(owner)
 if not maintenance.ready:return false

 transfer_buffer=owner.track(rd.storage_buffer_create(transfer_count*8),"cached interpolation IDs and weights",transfer_count*8)
 rd.buffer_clear(vectors,0,node_count*8*4)
 var compilation=preload("res://water/compute_source.gd").compile(rd,_shader_path("vectors"))
 source_hash=compilation.source_sha256
 var error=compilation.spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
 if not error.is_empty():push_error(error);return false
 var shader=owner.track(rd.shader_create_from_spirv(compilation.spirv),"MG full Galerkin shader")
 pipeline=owner.track(rd.compute_pipeline_create(shader),"MG pipeline")
 var uniforms: Array[RDUniform]=[]
 var buffers=[owner.pressure_work,owner.geometry,owner.control,description,matrices,vectors,arguments,owner.reduction_work,rows]
 buffers.append_array([maintenance.snapshot,transfer_buffer,maintenance.state])
 for i in buffers.size():
  if i in [1,6,11]:continue
  var u=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(buffers[i]);uniforms.append(u)
 bindings=owner.track(rd.uniform_set_create(uniforms,shader,0),"MG bindings")
 var build_compilation=preload("res://water/compute_source.gd").compile(rd,_shader_path("build"))
 if not build_compilation.spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty():push_error("MG Galerkin build: "+build_compilation.spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE));return false
 var build_shader=owner.track(rd.shader_create_from_spirv(build_compilation.spirv),"MG Galerkin builder")
 build_pipeline=owner.track(rd.compute_pipeline_create(build_shader),"MG build pipeline")
 var build_uniforms: Array[RDUniform]=[]
 for i in [0,1,2,3,4,5,8,9,10,11]:
  var u=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(buffers[i]);build_uniforms.append(u)
 build_bindings=owner.track(rd.uniform_set_create(build_uniforms,build_shader,0),"MG build bindings")
 var coarse_compilation=preload("res://water/compute_source.gd").compile(rd,_shader_path("coarse"))
 if not coarse_compilation.spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty():push_error("MG coarse solve: "+coarse_compilation.spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE));return false
 var coarse_shader=owner.track(rd.shader_create_from_spirv(coarse_compilation.spirv),"MG exact coarse solve")
 coarse_pipeline=owner.track(rd.compute_pipeline_create(coarse_shader),"MG coarse pipeline")
 var coarse_uniforms: Array[RDUniform]=[]
 for i in [2,3,4,5,11]:
  var u=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(buffers[i]);coarse_uniforms.append(u)
 coarse_bindings=owner.track(rd.uniform_set_create(coarse_uniforms,coarse_shader,0),"MG coarse bindings")
 var arg_compilation=preload("res://water/compute_source.gd").compile(rd,_shader_path("arguments"))
 if not arg_compilation.spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty():push_error("MG indirect arguments: "+arg_compilation.spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE));return false
 var arg_shader=owner.track(rd.shader_create_from_spirv(arg_compilation.spirv),"MG indirect argument producer")
 argument_pipeline=owner.track(rd.compute_pipeline_create(arg_shader),"MG argument pipeline")
 var arg_uniforms: Array[RDUniform]=[]
 var arg_buffers=[owner.control,description,arguments]
 arg_buffers.append(maintenance.state)
 for i in arg_buffers.size():
  var u=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(arg_buffers[i]);arg_uniforms.append(u)
 argument_bindings=owner.track(rd.uniform_set_create(arg_uniforms,arg_shader,0),"MG arguments only writable in producer")
 
 build_commands=[[0,0,0,-1]]
 for l in levels.size():build_commands.append([1,l,0,3])
 build_commands.append([0,0,0,-1])
 for l in levels.size()-1:build_commands.append([16,l,0,4])
 build_commands.append([4,0,0,0])
 for l in range(1,levels.size()):build_commands.append_array([[2,l,0,1],[3,l-1,0,2],[4,l,0,0]])
 for l in range(1,levels.size()):build_commands.append([13,l,0,0])
 if levels[-1].count<=64:build_commands.append([11,levels.size()-1,0,5])
 cycle_commands=[[0,0,0,-1],[5,0,0,0]]
 var final_field=_cycle(0)
 cycle_commands.append([10,0,final_field,0])
 var cache_bytes=transfer_count*8+(18*owner.n.x*owner.n.y*owner.n.z*4+maintenance.byte_count if maintenance else 0)
 owner.telemetry.emit.call_deferred({"pressure_backend":"multigrid","mg_maintenance":owner.config.get("mg_maintenance","rebuild"),"mg_lag":owner.config.get("mg_lag",4),"mg_aggregate_from":owner.config.get("mg_aggregate_from",99),"mg_structural_cpu_us":structural_record_us,"mg_levels":levels,"mg_smoothing":smoothing,"mg_smoother":smoother,"mg_shader_sha256":source_hash,"mg_shader_hashes":{"vectors":source_hash,"build":build_compilation.source_sha256,"coarse":coarse_compilation.source_sha256,"arguments":arg_compilation.source_sha256},"mg_bytes":cache_bytes+row_count*8+matrix_count*4+node_count*32+metadata.size()*4+levels.size()*argument_stride})
 return true
func _smooth(l: int,field: int,zero: bool) -> int:
 for sweep in smoothing:
  if smoother=="chebyshev":cycle_commands.append([15,l,field+4*(sweep+1),0])
  else:cycle_commands.append([14 if zero and sweep==0 else 6,l,field,0])
  field=3-field
 return field
func _cycle(l: int) -> int:
 if l==levels.size()-1:
  if levels[l].count<=64:cycle_commands.append([12,l,0,-1]);return 1
  # Odd periodic dimensions are not wrapped onto an unrelated coarse grid.
  # A fixed positive polynomial is the terminal solve when coarsening stops.
  var terminal_field=1
  for sweep in 32:
   cycle_commands.append([14 if sweep==0 else 6,l,terminal_field,0]);terminal_field=3-terminal_field
  return terminal_field
 var field=_smooth(l,1,true)
 cycle_commands.append([7,l,field,0]);cycle_commands.append([8,l+1,0,0])
 var coarse_field=_cycle(l+1)
 cycle_commands.append([9,l,field+4*coarse_field,0])
 return _smooth(l,field,false)
func record(list: int,build: bool,initial=false):
 if build and maintenance:
  maintenance.record(list)
 var phase=2 if build else (0 if initial else 1)
 var previous=-1
 for command in build_commands if build else cycle_commands:
  var op=command[0];var l=command[1];var field=command[2];var kind=command[3]
  owner.scheduled_dispatches+=1
  var key=op+32*l+512*phase+2048*field
  if not payloads.has(key):payloads[key]=PackedInt32Array([op,l,phase,field,levels.size(),1 if owner.config.get("periodic_x",false) else 0,smoothing,1 if owner.config.get("control_bytes",128)>=256 else 0]).to_byte_array()
  var selected=0 if op==0 else (3 if op in [11,12] else (1 if build else 2))
  if selected!=previous:
   var pipes=[argument_pipeline,build_pipeline,pipeline,coarse_pipeline];var sets=[argument_bindings,build_bindings,bindings,coarse_bindings]
   rd.compute_list_bind_compute_pipeline(list,pipes[selected]);rd.compute_list_bind_uniform_set(list,sets[selected],0);previous=selected
  rd.compute_list_set_push_constant(list,payloads[key],32)
  if kind<0:rd.compute_list_dispatch(list,1,1,1)
  else:rd.compute_list_dispatch_indirect(list,arguments,l*argument_stride+kind*12)
  rd.compute_list_add_barrier(list)
 if build and maintenance:
  maintenance.record(list,true)
 # Restore the fluid pipeline after hierarchy work.
 rd.compute_list_bind_compute_pipeline(list,owner.pipeline);rd.compute_list_bind_uniform_set(list,owner.bindings,0);owner.iteration_active=false

# Structural support of P^T A P, computed once from lattice offsets. No liquid
# cells are scanned on CPU. Cancellation may yield zero entries inside this set;
# nothing outside the set is dropped. GPU builder rejects any out-of-range term.
func _basis(q: Vector3i,f: Vector3i,aggregate=false) -> Array:
 if aggregate:return [Vector3i(floori(float(q.x)/f.x),floori(float(q.y)/f.y),floori(float(q.z)/f.z))]
 var base=Vector3i(floori((q.x+.5)/f.x-.5),floori((q.y+.5)/f.y-.5),floori((q.z+.5)/f.z-.5))
 var result=[]
 for z in f.z:
  for y in f.y:
   for x in f.x:result.append(base+Vector3i(x,y,z))
 return result
func _coarse_stencil(stencil: Array,f: Vector3i,aggregate=false) -> Array:
 var result={}
 for z in f.z:
  for y in f.y:
   for x in f.x:
    var q=Vector3i(x,y,z);var left=_basis(q,f,aggregate)
    for off in stencil:
     for a in left:
      for b in _basis(q+off,f,aggregate):result[b-a]=true
 return result.keys()

func _shader_path(kind: String) -> String:
 return "res://water/shaders/compute/pressure_mg_cache_"+kind+".glsl"
