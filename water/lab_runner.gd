extends Node
# Interactive beach simulation controls.
var lab
var solver
var stats={}
var paused=true
var requested=0
var settings={}
var requested_time=0.0
var single_pending=false
var generation=0
var request_wall_us=0
func _init(controller):lab=controller
func _ready():reset()
func reset():
 if solver:solver.close()
 generation+=1
 stats={};requested=0;requested_time=0;single_pending=false;paused=true;request_wall_us=Time.get_ticks_usec()
 var omega=TAU/1.4;var low=0.0;var high=100.0
 # Solve omega^2 = g k tanh(k h) for the existing inlet wave.
 for iteration in 80:
  var k=(low+high)*.5
  if 9.81*k*tanh(k*.45)<omega*omega:low=k
  else:high=k
 var k=(low+high)*.5
 settings={"n":Vector3i(310,48,80),"spacing":Vector3(.025,.025,.05),"origin":Vector3(-1.75,-.6,-2),"eta":0.0,"periodic_x":false,"shape":7,"wave":Vector4(.08,k,omega,.45),"zone_length":2.5,"damping_rate":12.0,"ramp_periods":4.0,"stokes_second":true,"history_capacity":10000,"slope":6,"pressure_backend":"multigrid"}
 solver=preload("res://water/presentation/coastal_view.gd").new(settings)
 var owner_generation=generation
 solver.telemetry.connect(func(packet):
  if owner_generation==generation:stats.merge(packet,true)
 );solver.start()
 lab.material.set_shader_parameter("plane_texture",solver.planes);lab.material.set_shader_parameter("kind_texture",solver.kinds);lab.material.set_shader_parameter("grid",settings.n)
 var lower: Vector3=settings.get("origin",Vector3.ZERO)
 var extent=Vector3(settings.n)*settings.spacing
 lab.material.set_shader_parameter("BMIN",lower);lab.material.set_shader_parameter("BMAX",lower+extent)
 var mesh=BoxMesh.new();mesh.size=extent;lab.volume_proxy.mesh=mesh;lab.volume_proxy.position=lower+extent*.5
 lab.presentation.bind_source(solver,settings)
 lab.orbit_target=lower+extent*Vector3(.5,.35,.5)
 lab.distance=maxf(extent.x,extent.z)*1.7;lab.zoom_min=maxf(extent.x,extent.z)*.15;lab.zoom_max=maxf(extent.x,extent.z)*4;lab.camera.far=lab.zoom_max*2;lab.yaw=.35;lab.pitch=.35
 lab.orbit_target=Vector3(3.1,-.05,0);lab.distance=6;lab.yaw=.15
 lab.orbit()
 lab.presentation.camera_preset(1)
func accrue_wall_request():
 var now=Time.get_ticks_usec()
 if not paused:requested_time+=(now-request_wall_us)/1e6
 request_wall_us=now
func _process(_delta):
 accrue_wall_request()
 var completed=stats.get("accepted_steps",stats.get("steps",0))
 var elapsed=stats.get("accepted_time",completed/120.0)
 if single_pending and completed>=requested:
  single_pending=false;requested_time=maxf(requested_time,elapsed)
 if not paused:
  # Monotonic wall time avoids Godot delta clamping after a slow frame/stall.
  # Never wait for telemetry before submitting more dependent work.
  if stats.get("failure",0)==0:
   solver.request_time(requested_time)
 var status="PAUSED" if paused else "RUNNING"
 if paused and (stats.get("pending",false) or single_pending):status="PAUSING"
 if stats.get("failure",0)>0:status="STOPPED · GPU error %s · R to reset"%stats.failure
 lab.hud.text="WAVES · 4 m beach\nSpace run/pause · N single step · R reset\n1 showcase · 2 side · Right drag orbit · Wheel zoom\nF2 Water / Clay · F3 hide text\n%s · Simulation %.3f s"%[status,elapsed]
func key(event: InputEventKey):
 if event.keycode==KEY_SPACE:
  accrue_wall_request();paused=not paused
  if paused:
   # Cancel future starts; already submitted work / a pending solve can finish.
   # Retain wall-time debt for resume. GPU acceptance remains authoritative.
   requested=stats.get("accepted_steps",stats.get("steps",0));solver.request(requested)
  else:requested_time=maxf(requested_time,stats.get("accepted_time",0))
 if event.keycode==KEY_N and paused and not single_pending and not stats.get("pending",false):
  requested=stats.get("accepted_steps",stats.get("steps",0))+1
  single_pending=true;solver.request(requested)
 if event.keycode==KEY_R:reset()
func _exit_tree():
 if solver:solver.close()
