extends "res://water/coastal_gpu.gd"
# Publish the committed clock immediately after accepted surface export.
var surface_clock=preload("res://water/presentation/surface_clock.gd").new()
func _initialize():
 super._initialize()
 if not surface_clock.ready:
  ready=false;telemetry.emit.call_deferred({"failure":99})
func _extra_uniforms(count: int) -> Array[RDUniform]:
 var result=super._extra_uniforms(count)
 surface_clock.initialize(self)
 return result
func _dispatch(list: int,op: int,groups: int,steps: float):
 super._dispatch(list,op,groups,steps)
 if op==19 and not collecting_commands and surface_clock.ready:
  surface_clock.record(list)
  rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,bindings,0);iteration_active=false
func _free():
 surface_clock.release_gpu()
 super._free()
