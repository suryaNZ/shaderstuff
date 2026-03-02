extends Node



@onready var objectsparent = $"../objectsparent"
@onready var spheresParent = $"../spheresParent"
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
	
	setup_compute()
	var imagebytes = render()
	Image.create_from_data(image_size.x, image_size.y, false, Image.FORMAT_RGBAF, imagebytes).save_png("res://a.png")

func setup_compute():

	var shader_file := load("res://shaders/3_compute_shader.glsl")
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
	camera_bytes.append_array(PackedFloat32Array([
		camera.global_transform.basis.x.x,
		camera.global_transform.basis.x.y,
		camera.global_transform.basis.x.z, 1,
		camera.global_transform.basis.y.x,
		camera.global_transform.basis.y.y,
		camera.global_transform.basis.y.z, 1,
		camera.global_transform.basis.z.x,
		camera.global_transform.basis.z.y,
		camera.global_transform.basis.z.z, 1,
		camera.global_transform.origin.x,
		camera.global_transform.origin.y,
		camera.global_transform.origin.z, 1
	]).to_byte_array())
	camera_bytes.append_array(PackedFloat32Array([camera.fov, camera.far, camera.near]).to_byte_array())
	var camera_buffer = rd.storage_buffer_create(camera_bytes.size(), camera_bytes)
	var camera_uniform := RDUniform.new()
	camera_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	camera_uniform.binding = 1
	camera_uniform.add_id(camera_buffer)
	
	# TODO Faces of all objects
	var faces = []
	var albedo : Array[Color] = []
	var emission_colour : Array[Color] = []
	var emission_strength : Array [float] = []
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
	
	var material_bytes = PackedColorArray(albedo).to_byte_array()
	var material_buffer = rd.storage_buffer_create(material_bytes.size(), material_bytes)
	var material_uniform = RDUniform.new()
	material_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	material_uniform.binding = 3
	material_uniform.add_id(material_buffer)
	
	var spheres: Array[Vector4] = []
	var sphere_material_bytes : PackedByteArray
	albedo.clear()
	emission_colour.clear()
	emission_strength.clear()
	for meshinstance : MeshInstance3D in spheresParent.get_children():
		var m : SphereMesh = meshinstance.mesh
		spheres.append(Vector4(
			meshinstance.global_transform.origin.x,
			meshinstance.global_transform.origin.y,
			meshinstance.global_transform.origin.z,
			m.radius
		))
		albedo.append(meshinstance.get_active_material(0).albedo_color)
		emission_colour.append(
			meshinstance.get_active_material(0).emission
			if meshinstance.get_active_material(0).emission_enabled
			else Color.BLACK
		)
		emission_strength.append(
			meshinstance.get_active_material(0).emission_energy_multiplier
			if meshinstance.get_active_material(0).emission_enabled
			else 0.0
		)
		sphere_material_bytes.append_array(PackedColorArray([albedo[-1]]).to_byte_array())
		sphere_material_bytes.append_array(PackedColorArray([emission_colour[-1]]).to_byte_array())
		sphere_material_bytes.append_array(PackedFloat32Array([emission_strength[-1]]).to_byte_array())
		sphere_material_bytes.append_array(PackedFloat32Array([0.0]).to_byte_array()) # padding for std430
		sphere_material_bytes.append_array(PackedFloat32Array([0.0]).to_byte_array()) # padding for std430
		sphere_material_bytes.append_array(PackedFloat32Array([0.0]).to_byte_array()) # padding for std430
		
	var sphere_bytes = PackedVector4Array(spheres).to_byte_array()
	var sphere_buffer = rd.storage_buffer_create(sphere_bytes.size(), sphere_bytes)
	var sphere_uniform = RDUniform.new()
	sphere_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	sphere_uniform.binding = 4
	sphere_uniform.add_id(sphere_buffer)
	
	#var sphere_material_bytes = PackedColorArray(albedo).to_byte_array()
	#sphere_material_bytes.append_array(PackedColorArray(emission_colour).to_byte_array())
	#sphere_material_bytes.append_array(PackedFloat32Array(emission_strength).to_byte_array())
	print(sphere_material_bytes.size())
	var sphere_material_buffer = rd.storage_buffer_create(sphere_material_bytes.size(), sphere_material_bytes)
	var sphere_material_uniform = RDUniform.new()
	sphere_material_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	sphere_material_uniform.binding = 5
	sphere_material_uniform.add_id(sphere_material_buffer)
	
	bindings = [
		output_uniform,
		camera_uniform,
		face_uniform,
		material_uniform,
		sphere_uniform,
		sphere_material_uniform
		# TODO other uniforms
	]
	
	uniform_set = rd.uniform_set_create(bindings, shader, 0)

func update_compute():
	# Camera info uniform buffer
	var projection_mat = PackedVector4Array([
		camera.get_camera_projection().x,
		camera.get_camera_projection().y,
		camera.get_camera_projection().z,
		camera.get_camera_projection().w,
	])
	var camera_bytes = projection_mat.to_byte_array()
	camera_bytes.append_array(PackedFloat32Array([camera.fov, camera.far, camera.near]).to_byte_array())
	camera_bytes.append_array(PackedFloat32Array([
		camera.global_transform.basis.x.x,
		camera.global_transform.basis.x.y,
		camera.global_transform.basis.x.z, 1,
		camera.global_transform.basis.y.x,
		camera.global_transform.basis.y.y,
		camera.global_transform.basis.y.z, 1,
		camera.global_transform.basis.z.x,
		camera.global_transform.basis.z.y,
		camera.global_transform.basis.z.z, 1,
		camera.global_transform.origin.x,
		camera.global_transform.origin.y,
		camera.global_transform.origin.z, 1
	]).to_byte_array())
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
	
	var material_bytes = PackedColorArray(albedo).to_byte_array()
	var material_buffer = rd.storage_buffer_create(material_bytes.size(), material_bytes)
	var material_uniform = RDUniform.new()
	material_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	material_uniform.binding = 3
	material_uniform.add_id(material_buffer)
	
	var spheres: Array[Vector4] = []
	albedo.clear()
	for meshinstance : MeshInstance3D in spheresParent.get_children():
		var m : SphereMesh = meshinstance.mesh
		spheres.append(Vector4(
			meshinstance.position.x,
			meshinstance.position.y,
			meshinstance.position.z,
			m.radius
		))
		albedo.append(meshinstance.get_active_material(0).albedo_color)
		
	var sphere_bytes = PackedVector4Array(spheres).to_byte_array()
	var sphere_buffer = rd.storage_buffer_create(sphere_bytes.size(), sphere_bytes)
	var sphere_uniform = RDUniform.new()
	sphere_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	sphere_uniform.binding = 4
	sphere_uniform.add_id(sphere_buffer)
	
	var sphere_material_bytes = PackedColorArray(albedo).to_byte_array()
	var sphere_material_buffer = rd.storage_buffer_create(sphere_material_bytes.size(), sphere_material_bytes)
	var sphere_material_uniform = RDUniform.new()
	sphere_material_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	sphere_material_uniform.binding = 5
	sphere_material_uniform.add_id(sphere_material_buffer)
	
	bindings[1] = camera_uniform
	bindings[2] = face_uniform
	bindings[3] = material_uniform
	bindings[4] = sphere_uniform
	bindings[5] = sphere_material_uniform
	
	uniform_set = rd.uniform_set_create(bindings, shader, 0)


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
#func _process(delta: float) -> void:
	#update_compute()
	#var imagebytes = render()
	#Image.create_from_data(image_size.x, image_size.y, false, Image.FORMAT_RGBAF, imagebytes).save_png("res://a.png")
