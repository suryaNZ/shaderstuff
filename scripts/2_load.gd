extends Node



@onready var objectsparent = $"../objectsparent"
@onready var camera = $"../Camera3D"
#var sphere1TM: TriangleMesh


var image_size : Vector2i

var rd := RenderingServer.create_local_rendering_device()
var uniform_set
var pipeline
var bindings: Array
var shader
var output: RID




var input = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
var input_bytes = PackedFloat32Array(input).to_byte_array()
var buffer = rd.storage_buffer_create(input_bytes.size(), input_bytes)

var uniform := RDUniform.new()
	

# Called when the node enters the scene tree for the first time.
func _ready() -> void:

	
	image_size.x = ProjectSettings.get_setting("display/window/size/viewport_width")
	image_size.y = ProjectSettings.get_setting("display/window/size/viewport_height")
	
	print("begin compute")
	setup_compute()
	print("begin render")
	var imagebytes = render()
	print("finish render")
	Image.create_from_data(image_size.x, image_size.y, false, Image.FORMAT_RGBAF, imagebytes).save_png("res://a.png")

func setup_compute():
	var shader_file := load("res://shaders/2_compute_shader.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)

	# Output uniform buffer
	var fmt = RDTextureFormat.new()
	fmt.width = image_size.x
	fmt.height = image_size.y
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var view = RDTextureView.new()
	var output_image = Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGBAF)
	output = rd.texture_create(fmt, view, [output_image.get_data()])
	var output_uniform = RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output_uniform.binding = 0
	output_uniform.add_id(output)
	
	# Camera info uniform buffer
	var projection_mat = PackedVector4Array([
		camera.get_camera_projection().x,
		camera.get_camera_projection().y,
		camera.get_camera_projection().z,
		camera.get_camera_projection().w,
	])
	var camera_bytes = projection_mat.to_byte_array()
	camera_bytes.append_array(PackedFloat32Array([camera.fov, camera.far, camera.near]).to_byte_array())
	var camera_buffer = rd.storage_buffer_create(camera_bytes.size(), camera_bytes)
	var camera_uniform := RDUniform.new()
	camera_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	camera_uniform.binding = 1
	camera_uniform.add_id(camera_buffer)
	
	# TODO Faces of all objects
	var faces = []
	var albedo : Array[Color] = []
	for meshinstance : MeshInstance3D in objectsparent.get_children():
		for i in range (meshinstance.mesh.get_surface_count()):
			albedo.append(meshinstance.get_active_material(0).albedo_color)
		for face in meshinstance.mesh.get_faces():
			faces.append(face + meshinstance.position)
	
	var face_bytes = PackedVector3Array(faces).to_byte_array()
	var face_buffer = rd.storage_buffer_create(face_bytes.size(), face_bytes)
	var face_uniform = RDUniform.new()
	face_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	face_uniform.binding = 2
	face_uniform.add_id(face_buffer)
	
	var albedo_bytes = PackedColorArray(albedo).to_byte_array()
	var albedo_buffer = rd.storage_buffer_create(albedo_bytes.size(), albedo_bytes)
	var albedo_uniform = RDUniform.new()
	albedo_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	albedo_uniform.binding = 3
	albedo_uniform.add_id(albedo_buffer)
	
	
	bindings = [
		output_uniform,
		camera_uniform,
		face_uniform,
		albedo_uniform,
		# TODO other uniforms
	]
	
	uniform_set = rd.uniform_set_create(bindings, shader, 0)

func update_compute():
	pass # TODO

func render():
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, image_size.x/8, image_size.y/8, 1)
	
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	
	var byte_data = rd.texture_get_data(output, 0)
	return byte_data





# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
