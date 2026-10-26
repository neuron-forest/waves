extends Node
# Appearance state is independent of simulation controls.
var lab
var water_material=ShaderMaterial.new()
var water_environment=Environment.new()
var clay_environment: Environment
var light=DirectionalLight3D.new()
var bed=MeshInstance3D.new()
var toggle=Button.new()
var appearance_controls=PanelContainer.new()
var distance_slider=HSlider.new()
var colour_picker=ColorPickerButton.new()
var distance_label=Label.new()
var attenuation_distance=0.18
var water_colour=Color("078f9f")
var enabled=true
var bound=false
var source
func _init(controller):lab=controller
func _ready():
 water_material.shader=load("res://water/presentation/water.gdshader")
 clay_environment=lab.world_environment.environment
 var sky=Sky.new();var sky_material=ShaderMaterial.new();sky_material.shader=load("res://water/presentation/daylight.gdshader");sky.sky_material=sky_material
 water_environment.background_mode=Environment.BG_SKY;water_environment.sky=sky
 water_environment.ambient_light_source=Environment.AMBIENT_SOURCE_SKY;water_environment.ambient_light_energy=.35
 water_environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC;water_environment.tonemap_exposure=.9
 light.light_color=Color(1,.94,.83);light.light_energy=1.1;light.shadow_enabled=true
 add_child(light);light.look_at(-Vector3(-.45,.65,-.63).normalized(),Vector3.UP)
 bed.material_override=ShaderMaterial.new();bed.material_override.shader=load("res://water/presentation/sand.gdshader")
 add_child(bed);bed.visible=false;light.visible=false
 var canvas=CanvasLayer.new();add_child(canvas)
 var controls=Control.new();canvas.add_child(controls);controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);controls.mouse_filter=Control.MOUSE_FILTER_IGNORE
 controls.add_child(toggle)
 toggle.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
 toggle.offset_left=-262;toggle.offset_right=-24;toggle.offset_top=20;toggle.offset_bottom=60
 toggle.toggle_mode=true;toggle.focus_mode=Control.FOCUS_NONE;toggle.visible=false
 toggle.tooltip_text="Switch appearance without changing the simulation (F2)"
 toggle.toggled.connect(set_water)
 controls.add_child(appearance_controls);appearance_controls.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
 appearance_controls.offset_left=-262;appearance_controls.offset_right=-24;appearance_controls.offset_top=68
 var panel=StyleBoxFlat.new();panel.bg_color=Color(.035,.065,.08,.92);panel.set_content_margin_all(12);panel.set_corner_radius_all(5)
 appearance_controls.add_theme_stylebox_override("panel",panel)
 var box=VBoxContainer.new();box.add_theme_constant_override("separation",7);appearance_controls.add_child(box)
 box.add_child(distance_label);distance_label.add_theme_font_size_override("font_size",14)
 distance_slider.min_value=.04;distance_slider.max_value=1.5;distance_slider.step=.01;distance_slider.value=attenuation_distance;distance_slider.focus_mode=Control.FOCUS_NONE
 distance_slider.tooltip_text="Distance through water retaining 37% green-light transmission. Shorter = stronger water colour."
 box.add_child(distance_slider);distance_slider.value_changed.connect(set_attenuation)
 var row=HBoxContainer.new();box.add_child(row)
 var label=Label.new();label.text="Water colour";label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;label.add_theme_font_size_override("font_size",14);row.add_child(label)
 colour_picker.color=water_colour;colour_picker.edit_alpha=false;colour_picker.custom_minimum_size=Vector2(68,26);colour_picker.focus_mode=Control.FOCUS_NONE;row.add_child(colour_picker)
 colour_picker.color_changed.connect(set_water_colour)
 appearance_controls.visible=false;set_attenuation(attenuation_distance);set_water_colour(water_colour)
func set_attenuation(value: float):
 attenuation_distance=value;distance_label.text="Transmission distance: %.2f m"%value
 water_material.set_shader_parameter("attenuation_distance",value)
func set_water_colour(value: Color):
 water_colour=value;water_material.set_shader_parameter("water_tint",value)
func bind_source(owner,settings: Dictionary):
 source=owner;bound=true
 var n: Vector3i=settings.n;var origin: Vector3=settings.origin;var extent=Vector3(n)*settings.spacing
 water_material.set_shader_parameter("plane_texture",owner.planes);water_material.set_shader_parameter("kind_texture",owner.kinds)
 water_material.set_shader_parameter("grid",n);water_material.set_shader_parameter("BMIN",origin);water_material.set_shader_parameter("BMAX",origin+extent)
 water_material.set_shader_parameter("clock_texture",owner.surface_clock.texture)
 water_material.set_shader_parameter("clock_ready",false)
 water_material.set_shader_parameter("bed_slope",settings.get("slope",6.0))
 build_bed(n,origin,settings.spacing,settings.get("slope",6.0))
 toggle.visible=true;set_water(enabled)
func _process(_delta):
 if bound and source and source.surface_clock.ready:water_material.set_shader_parameter("clock_ready",true)
func set_water(value: bool):
 enabled=value
 toggle.set_pressed_no_signal(enabled);toggle.text="Water / Clay: %s  [F2]"%("Water" if enabled else "Clay")
 if not bound:return
 lab.volume_proxy.material_override=water_material if enabled else lab.material
 lab.world_environment.environment=water_environment if enabled else clay_environment
 bed.visible=enabled;light.visible=enabled
 appearance_controls.visible=enabled
 lab.hud.add_theme_color_override("font_shadow_color",Color(0.05,0.10,0.13,.9) if enabled else Color.TRANSPARENT)
 lab.hud.add_theme_constant_override("shadow_offset_x",1 if enabled else 0);lab.hud.add_theme_constant_override("shadow_offset_y",1 if enabled else 0)
func toggle_water():set_water(not enabled)
func camera_preset(index: int):
 if not bound:return
 var wide=source.n.z*source.spacing.z>1.0
 lab.camera.projection=Camera3D.PROJECTION_ORTHOGONAL
 if index==1:
  lab.orbit_target=Vector3(2.15,-.12,0) if wide else Vector3(3.45,-.08,0)
  lab.camera.position=lab.orbit_target+(Vector3(2.5,4.45,5.7) if wide else Vector3(1.5,2,3))
  lab.camera.size=5.25 if wide else 1.5
 else:
  lab.orbit_target=Vector3(3.2,.05,0);lab.camera.position=Vector3(3.2,.25,4);lab.camera.size=2.1 if wide else 1.7
 lab.camera.look_at(lab.orbit_target)
 var offset=lab.camera.position-lab.orbit_target;lab.distance=offset.length();lab.yaw=atan2(offset.x,offset.z);lab.pitch=asin(offset.y/lab.distance)
func bed_height(x: float,slope: float) -> float:return -.45+maxf(0,x-1.5)/slope
func build_bed(n: Vector3i,origin: Vector3,h: Vector3,slope: float):
 var vertices=PackedVector3Array();var normals=PackedVector3Array()
 var quad=func(a: Vector3,b: Vector3,c: Vector3,d: Vector3,normal: Vector3):
  # Godot front faces wind clockwise. Outward normals must face the same side.
  vertices.append_array(PackedVector3Array([a,c,b,a,d,c]));for i in 6:normals.append(normal)
 var z0=origin.z;var z1=z0+n.z*h.z;var bottom=origin.y-.08
 for i in n.x:
  var x0=origin.x+i*h.x;var x1=x0+h.x;var y0=bed_height(x0,slope);var y1=bed_height(x1,slope)
  var normal=Vector3(-1.0/slope if x0+.5*h.x>1.5 else 0.0,1,0).normalized()
  quad.call(Vector3(x0,y0,z0),Vector3(x0,y0,z1),Vector3(x1,y1,z1),Vector3(x1,y1,z0),normal)
  quad.call(Vector3(x0,bottom,z0),Vector3(x0,y0,z0),Vector3(x1,y1,z0),Vector3(x1,bottom,z0),Vector3.FORWARD)
  quad.call(Vector3(x1,bottom,z1),Vector3(x1,y1,z1),Vector3(x0,y0,z1),Vector3(x0,bottom,z1),Vector3.BACK)
 var x=origin.x+n.x*h.x
 var end=bed_height(x,slope)
 quad.call(Vector3(x,bottom,z0),Vector3(x,end,z0),Vector3(x,end,z1),Vector3(x,bottom,z1),Vector3.RIGHT)
 var start=bed_height(origin.x,slope)
 quad.call(Vector3(origin.x,bottom,z1),Vector3(origin.x,start,z1),Vector3(origin.x,start,z0),Vector3(origin.x,bottom,z0),Vector3.LEFT)
 var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
 var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);bed.mesh=mesh
