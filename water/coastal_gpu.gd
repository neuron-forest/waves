extends "res://water/coupled_gpu.gd"
# Offshore forcing and water-volume accounting.
var coastal_history: RID
var target_probe: RID
func _init(settings: Dictionary):
 super(settings)
 config.shader="res://water/shaders/compute/coastal.glsl"
 config.control_bytes=384
func _extra_uniforms(count: int) -> Array[RDUniform]:
 var uniforms=super._extra_uniforms(count)
 var right_scale=float(config.get("right_absorption",1.0));assert(right_scale>=0 and right_scale<=1)
 var options=track(rd.storage_buffer_create(16,PackedFloat32Array([right_scale,0,0,0]).to_byte_array()),"flat-tank boundary comparison options",16)
 var options_uniform=RDUniform.new();options_uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;options_uniform.binding=11;options_uniform.add_id(options);uniforms.append(options_uniform)
 target_probe=track(rd.storage_buffer_create(128),"wave target probes",128)
 var bytes=config.get("history_capacity",2400)*80
 coastal_history=track(rd.storage_buffer_create(bytes),"every accepted coastal step and gauge",bytes)
 rd.buffer_clear(coastal_history,0,bytes)
 for pair in [[12,target_probe],[13,coastal_history]]:
  var u=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=pair[0];u.add_id(pair[1]);uniforms.append(u)
 return uniforms
func _params(op: int,steps: float) -> PackedByteArray:
 var result=super._params(op,steps)
 result.encode_float(104,1 if config.get("stokes_second",true) else 0)
 result.append_array(PackedFloat32Array([origin.x,config.get("zone_length",2.5),config.get("damping_rate",12.0),config.get("ramp_periods",4.0)]).to_byte_array())
 return result
func _initial_commands(list: int,count: int):
 super._initial_commands(list,count);_dispatch(list,85,1,0);_dispatch(list,86,1,0)
func _after_advection(list: int,steps: float):
 var cg=ceili(n.x*n.y*n.z/128.0)
 var fg=ceili(((n.x+1)*n.y*n.z+n.x*(n.y+1)*n.z+n.x*n.y*(n.z+1))/128.0)
 for op in [80,81,82,83,84,87,88]:_dispatch(list,op,1 if op in [81,84,88] else (fg if op==82 else cg),steps)
func _record_commands(list: int,steps: float):
 super._record_commands(list,steps);_dispatch(list,85,1,steps);_dispatch(list,89,1,steps)
func _stats(data: PackedByteArray):
 super._stats(data)
 var v=data.to_float32_array()
 telemetry.emit.call_deferred({"forcing_min_F":v[88],"forcing_max_F":v[89],"forcing_volume_m3":v[72],"ocean_inflow_m3":v[73],"ocean_outflow_m3":v[74],"forcing_momentum_kg_mps":Array(v.slice(75,78)),"staged_forcing_volume_m3":v[64],"staged_ocean_inflow_m3":v[65],"staged_ocean_outflow_m3":v[66],"gauges_m":Array(v.slice(80,88))})

