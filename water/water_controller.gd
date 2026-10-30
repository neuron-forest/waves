extends Node3D
var camera=Camera3D.new()
var volume_proxy=MeshInstance3D.new()
var material=ShaderMaterial.new()
var hud=Label.new()
var yaw=0.35
var pitch=0.25
var distance=2.6
var zoom_min=0.6
var zoom_max=5.0
var orbit_target=Vector3.ZERO
var fixture_runner
var world_environment: WorldEnvironment
var presentation
func _ready():
 if RenderingServer.get_current_rendering_method()!="forward_plus":
  push_error("Waves requires Forward+ with Vulkan.");get_tree().quit(1);return
 get_viewport().use_taa=false
 get_viewport().screen_space_aa=Viewport.SCREEN_SPACE_AA_FXAA
 var env=WorldEnvironment.new();env.environment=Environment.new()
 world_environment=env
 env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(0.075,0.09,0.11)
 env.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
 add_child(env)
 camera.near=0.03;camera.far=20;camera.fov=49;add_child(camera);camera.current=true
 material.shader=load("res://water/shaders/render/clay.gdshader")
 var proxy=volume_proxy;var box=BoxMesh.new();box.size=Vector3(2,1.2,1.4)
 proxy.mesh=box;proxy.material_override=material;proxy.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(proxy)
 var canvas=CanvasLayer.new();add_child(canvas);canvas.add_child(hud)
 hud.position=Vector2(24,20);hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
 presentation=preload("res://water/presentation/presentation.gd").new(self);add_child(presentation)
 fixture_runner=preload("res://water/lab_runner.gd").new(self);add_child(fixture_runner)
func _unhandled_input(event):
 if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_1,KEY_2] and presentation.bound:
  presentation.camera_preset(event.keycode-KEY_0);get_viewport().set_input_as_handled();return
 if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F2 and presentation.bound:
  presentation.toggle_water();get_viewport().set_input_as_handled();return
 if fixture_runner!=null and event is InputEventKey and event.pressed and not event.echo:
  if event.keycode==KEY_F3:hud.visible=not hud.visible
  fixture_runner.key(event);return
 if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
  if camera.projection==Camera3D.PROJECTION_ORTHOGONAL:
   camera.size=clampf(camera.size*(.9 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.1),.4,20);return
  distance=clampf(distance*(0.9 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.1),zoom_min,zoom_max);orbit()
 if event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_RIGHT:
  yaw-=event.relative.x*0.004;pitch=clampf(pitch+event.relative.y*0.004,-1.2,1.4);orbit()
func orbit():
 camera.position=orbit_target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance;camera.look_at(orbit_target)
