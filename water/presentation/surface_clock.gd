extends RefCounted
var texture=Texture2DRD.new()
var rd: RenderingDevice
var pipeline: RID
var bindings: RID
var rids: Array[RID]=[]
var ready=false
func keep(rid: RID) -> RID:rids.append(rid);return rid
func initialize(owner):
 rd=owner.rd
 var compiled=preload("res://water/compute_source.gd").compile(rd,"res://water/presentation/surface_clock.glsl")
 var error=compiled.spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
 if not error.is_empty():push_error(error);return
 var shader=keep(rd.shader_create_from_spirv(compiled.spirv));pipeline=keep(rd.compute_pipeline_create(shader))
 var f=RDTextureFormat.new();f.texture_type=RenderingDevice.TEXTURE_TYPE_2D;f.width=1;f.height=1;f.depth=1
 f.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
 f.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
 var bytes=PackedByteArray();bytes.resize(16)
 texture.texture_rd_rid=keep(rd.texture_create(f,RDTextureView.new(),[bytes]))
 var u=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=0;u.add_id(owner.control)
 var v=RDUniform.new();v.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;v.binding=1;v.add_id(texture.texture_rd_rid)
 bindings=keep(rd.uniform_set_create([u,v],shader,0));ready=pipeline.is_valid() and bindings.is_valid()
func record(list: int):
 rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,bindings,0)
 rd.compute_list_set_push_constant(list,PackedByteArray(),0)
 rd.compute_list_dispatch(list,1,1,1);rd.compute_list_add_barrier(list)
func release_gpu():
 ready=false;texture.texture_rd_rid=RID()
 for i in range(rids.size()-1,-1,-1):
  if rids[i].is_valid():rd.free_rid(rids[i])
 rids.clear()
