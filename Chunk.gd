extends Node2D

@export var noise : Noise
@export var tunnel_noise : Noise

@onready var MAPS_DATA : Dictionary = {}

var MAP_IMAGE : Image
var SHADOW_IMAGE : Image
var BACKGROUND_IMAGE : Image
var FOLIAGE_IMAGE : Image
var LIGHTS_IMAGE : Image

var MAP_SIZE
var SHADOWS_RESOLUTION_MULTIPLAYER

var steps = []

func build_chunk():
	#
	MAP_IMAGE = Image.create_empty(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8)
	BACKGROUND_IMAGE = Image.new()
	FOLIAGE_IMAGE = Image.create_empty(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8)
	SHADOW_IMAGE = Image.create_empty(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8)
	LIGHTS_IMAGE = Image.create_empty(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8)
	
	SHADOW_IMAGE.fill(0x88ffff1f)
	LIGHTS_IMAGE.fill(Color.WHITE)
	
	MAPS_DATA["FOREGROUND"] = MAP_IMAGE.get_data()
	MAPS_DATA["FOLIAGE"] = FOLIAGE_IMAGE.get_data()
	dirt_map_shader()
	place_dirt()
	place_stone()
	place_more_dirt()
	
	BACKGROUND_IMAGE = Image.create_from_data(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8, MAPS_DATA["FOREGROUND"])
	MAPS_DATA["BACKGROUND"] = BACKGROUND_IMAGE.get_data()
	
	
	shapeWorld()
	make_caverns()
	place_foliage()
	
	MAP_IMAGE = Image.create_from_data(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8, MAPS_DATA["FOREGROUND"])
	

	MAPS_DATA["SHADOWS"] = SHADOW_IMAGE.get_data()
	MAPS_DATA["LIGHTS_IMAGE"] = LIGHTS_IMAGE.get_data()
	
	
	var start_time = Time.get_ticks_msec()
	SHADOW_IMAGE = Image.create_from_data(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8, _set_up_compute_shader())
	SHADOW_IMAGE.resize(MAP_SIZE * SHADOWS_RESOLUTION_MULTIPLAYER, MAP_SIZE * SHADOWS_RESOLUTION_MULTIPLAYER, Image.Interpolation.INTERPOLATE_CUBIC)
	
	print((Time.get_ticks_msec() - start_time) / 1000.0)
	SHADOW_IMAGE.save_png("res://Assets/ShadowMap.png")
	print("MapGenerated")
	
func _exit_tree():
	Image.create_from_data(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8, MAPS_DATA["FOREGROUND"])
	MAP_IMAGE.save_png("res://Assets/TestMap.png")


func get_pixelv(map, pixel: Vector2i) -> int:
	var index := int((pixel.y * MAP_SIZE) + pixel.x) << 2  # Multiply by 4 using bit shift
	var data := PackedByteArray(MAPS_DATA[map])
	return data[index] | (data[index + 1] << 8) | (data[index + 2] << 16) | (data[index + 3] << 24)

func get_pixel_raw(data : PackedByteArray, pixel : Vector2i) -> int:
	var index := int((pixel.y * MAP_SIZE) + pixel.x) << 2 
	return data[index] | (data[index + 1] << 8) | (data[index + 2] << 16) | (data[index + 3] << 24)
	
func get_pixel(map, pixelx, pixely):
	var data = MAPS_DATA[map]
	var index = (pixely * MAP_SIZE + pixelx) * 4
	var r = data[index]
	var g = data[index + 1]
	var b = data[index + 2]
	var a = data[index + 3]
	return r + (g << 8) + (b << 16) + (a << 24)
	
func set_pixel(map, pixelx, pixely, color : int):
	
	var index = (pixely * MAP_SIZE + pixelx) * 4
	var r = (color) & 0xFF
	var g = (color >> 8) & 0xFF
	var b = (color >> 16) & 0xFF
	var a = (color >> 24) & 0xFF
	MAPS_DATA[map][index] = r
	MAPS_DATA[map][index + 1] = g
	MAPS_DATA[map][index + 2] = b
	MAPS_DATA[map][index + 3] = a
	
func set_shadow_pixel(map, pixelx, pixely, color : int):
	
	var index = int(pixely * MAP_SIZE + pixelx) * 4
	var r = (color) & 0xFF
	var g = (color >> 8) & 0xFF
	var b = (color >> 16) & 0xFF
	var a = (color >> 24) & 0xFF
	MAPS_DATA[map][index] = r
	MAPS_DATA[map][index + 1] = g
	MAPS_DATA[map][index + 2] = b
	MAPS_DATA[map][index + 3] = a
	
func shapeWorld():
	for i in 45:
		make_tunnels()

#places the initial dirt one vertical column at a time
func  place_dirt():
	for x in range(0, MAP_SIZE):
		placeBlockStack(((noise.get_noise_1d(x)) + 1) / 2, x)

#randomly places stone within the dirt
func place_stone():
	var stone_spread_factor = float(MAP_SIZE)
	for x in range(0, MAP_SIZE):
		for y in range(0, MAP_SIZE):
			if(get_pixel("FOREGROUND", x,y) == 0):
				continue
			if((noise.get_noise_2d(-x, y) + 1.0) / 2.0 < pow(float(y) / stone_spread_factor, 0.2)-0.1):
				set_pixel("FOREGROUND",x,y,Utils.STONE_COLOR)

#places more dirt to break up some of the stone
func place_more_dirt():
	var stone_spread_factor = float(MAP_SIZE)
	for x in range(0, MAP_SIZE):
		for y in range(0, MAP_SIZE):
			if(get_pixel("FOREGROUND", x,y) == 0):
				continue
			if((noise.get_noise_2d(x, y) + 1.0) / 2.0 > pow(float(y) / stone_spread_factor, 0.5)-0.2):
				set_pixel("FOREGROUND",x,y,Utils.DIRT_COLOR)

func place_foliage():
	for x in range(0, MAP_SIZE):
		for y in range(0, MAP_SIZE - 1):
			if(get_pixel("FOREGROUND", x, y) != Utils.DIRT_COLOR):
				continue
				
			var choice = randi_range(-4,4)
			if(choice < -1):
				continue
				
			var cardinal_truths = ""
			cardinal_truths += "0" if(y + 1 > MAP_SIZE || get_pixel("FOREGROUND",x, y + 1) == 0) else "1"
			cardinal_truths += "0" if(y - 1 < 0 || get_pixel("FOREGROUND",x, y - 1) == 0) else "1"
			
			if(cardinal_truths.split("")[0] == "0"):
				set_pixel("FOLIAGE", x,y + 1, Utils.FOLIAGE_COLOR)
			choice = randi_range(-4,4)
			if(choice < -1):
				continue
			if(cardinal_truths.split("")[1] == "0"):
				set_pixel("FOLIAGE", x,y - 1, Utils.FOLIAGE_COLOR)

	
#uses a perlin worm approach to make tunnels
func make_tunnels():
	var startingPoint = Vector2(randi_range(0, MAP_SIZE/4) * 4, randi_range(MAP_SIZE/3, MAP_SIZE))
	var direction = Vector2(randf_range(-1, 1), randf_range(0,1))
	var stepLength = randi_range(1,3)
	var turnAmount = deg_to_rad(randi_range(1,5) * 10)
	turnAmount = turnAmount * [-1,1].pick_random()
	var tunnel_length = 1000
	steps = [startingPoint]
	
	for x in range(1, tunnel_length):
		var nextStep = steps[x - 1] + direction * stepLength
		steps.append(nextStep)
		direction = direction.rotated(turnAmount * tunnel_noise.get_noise_1d(x))
	for step in steps:
		var radius = randi_range(stepLength, stepLength * 2)
		var startingTile = Vector2i(int(step.x), int(step.y))
		get_surrounding_tunnel_tiles(radius, startingTile)
	pass

func make_caverns():
	var cave_spread = float(MAP_SIZE)
	for x in range(0, MAP_SIZE):
		for y in range(0, MAP_SIZE):
			if(get_pixel("FOREGROUND",x,y) == 0):
				continue
			if(pow((noise.get_noise_2d(y, x) + 1.0), 1.2) / 2 > pow(float(MAP_SIZE - y) / cave_spread, 5) + 0.5):
				set_pixel("FOREGROUND",x,y,0x00000000)
				place_crystal(Vector2i(x,y))
	
#helper function for carving the tunnels out
func get_surrounding_tunnel_tiles(radius, startingTile):
	for i in range(-radius, radius):
		for j in range(-radius, radius):
			var currTile = Vector2(startingTile.x + i, startingTile.y + j)
			if(currTile.x < 0 || currTile.x >= MAP_SIZE || currTile.y < 0 || currTile.y >= MAP_SIZE):
				continue
			if(i*i + j*j < radius * radius):
				set_pixel("FOREGROUND", startingTile.x + i,startingTile.y + j,0x00000000)
				

func place_crystal(pixel):
	if(noise.get_noise_2d(pixel.x * 5, pixel.y * -3) > 0.7 && pixel.y > 350):
		set_pixel("FOREGROUND", pixel.x, pixel.y, Utils.CRYSTAL_COLOR)
	

# Loops through all the lightsources in the world and pumps their data into a buffer for the compute shader.
func apply_light_shader(light_sources, player):
	var lightData = {"positions" : [] , "colors" : [] , "intensities" : []}
	for light in light_sources:
		if(!light["object"]):
			continue
		lightData["positions"].append(light["object"].global_position * SHADOWS_RESOLUTION_MULTIPLAYER / 8)
		lightData["colors"].append(light["color"])
		lightData["intensities"].append(light["intensity"] * SHADOWS_RESOLUTION_MULTIPLAYER)
		if(light_sources.size() > 2):
			pass
	# Always updates the players position.
	lightData["positions"].append(player.position * SHADOWS_RESOLUTION_MULTIPLAYER / 8)
	lightData["colors"].append(Color.WHITE)
	lightData["intensities"].append(10.0 * SHADOWS_RESOLUTION_MULTIPLAYER)
	return lightData
		


func is_outside(pixel):
	if(pixel.x < 0 || pixel.x >= MAP_SIZE || pixel.y < 0 || pixel.y >= MAP_SIZE):
		return true
	return false
	

func placeBlockStack(height, x):
	var dirtStart = 256
	var mountain_intensity = 25
	height = dirtStart + height * mountain_intensity
	var h = MAP_SIZE - 1
	while(h >= height):  
		set_pixel("FOREGROUND",x,h,Utils.DIRT_COLOR)
		#SHADOW_IMAGE.set_pixel(x,h, Color.hex(Utils.DIRT_COLOR) - Color(0.8,0.8,0.8,0.0))
		h -= 1
		 

# Boiler plate for the Shadow Lighting compute shader.
func _set_up_compute_shader():
	var rd = RenderingServer.create_local_rendering_device()
	var shader_file = preload("res://ShadowMapper.glsl")
	var shader_spirv = shader_file.get_spirv()
	var shader = rd.shader_create_from_spirv(shader_spirv)
	var pipeline = rd.compute_pipeline_create(shader)

	var foreground_image := Image.create_from_data(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8, MAPS_DATA["FOREGROUND"])
	var shadow_image := Image.create_from_data(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8, MAPS_DATA["SHADOWS"])
	var output_image := Image.create_from_data(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8, MAPS_DATA["SHADOWS"])
	
	# 2. Define Texture Format
	var tex_format := RDTextureFormat.new()
	tex_format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tex_format.width = MAP_SIZE
	tex_format.height = MAP_SIZE
	tex_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	# Define Texture View
	var tex_view := RDTextureView.new()

	var foreground_tex = rd.texture_create(tex_format, tex_view, [foreground_image.get_data()])
	var shadow_tex = rd.texture_create(tex_format, tex_view, [shadow_image.get_data()])
	var output_tex = rd.texture_create(tex_format, tex_view, [output_image.get_data()])
	
	# Bind input/output images as RDUniforms
	var bindings := []

	var u_foreground := RDUniform.new()
	u_foreground.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_foreground.binding = 0
	u_foreground.add_id(foreground_tex)
	bindings.append(u_foreground)

	var u_shadow := RDUniform.new()
	u_shadow.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_shadow.binding = 1
	u_shadow.add_id(shadow_tex)
	bindings.append(u_shadow)

	var u_output := RDUniform.new()
	u_output.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_output.binding = 2
	u_output.add_id(output_tex)
	bindings.append(u_output)

	var uniform_set: RID = rd.uniform_set_create(bindings, shader, 0)
	# Dispatch the compute shader
	var image_height = MAP_SIZE
	var x_groups = MAP_SIZE / 1024
	var y_groups = int(ceil(float(image_height)))

	var ping = shadow_tex
	var pong = output_tex

	#This uses something called the ping pong method. A compute shader thing.
	for i in MAP_SIZE:
		# Update uniform set to use ping as input, pong as output
		bindings[1].clear_ids()
		bindings[1].add_id(ping)
		bindings[2].clear_ids()
		bindings[2].add_id(pong)
		uniform_set = rd.uniform_set_create(bindings, shader, 0)

		var compute_list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()
		rd.submit()
		rd.sync() # <-- needed to ensure results are visible before next pass

		# Swap ping-pong textures
		var temp = ping
		ping = pong
		pong = temp

	
	var result_data = rd.texture_get_data(ping, 0)
	var debug_image = Image.create_from_data(MAP_SIZE,MAP_SIZE,false, Image.FORMAT_RGBA8, result_data)
	debug_image.save_png("res://Compute_Test.png")
	return result_data

func dirt_map_shader():
	var rd = RenderingServer.create_local_rendering_device()
	var shader_file = preload("res://BuildMap.glsl")
	var shader_spirv = shader_file.get_spirv()
	var shader = rd.shader_create_from_spirv(shader_spirv)
	var pipeline = rd.compute_pipeline_create(shader)

	var noise_data := FastNoiseLite.new().get_image(MAP_SIZE, MAP_SIZE,false, false, true)
	noise_data.convert(Image.FORMAT_RGBA8)
	var noise_image := Image.create_from_data(MAP_SIZE, MAP_SIZE,false,  Image.FORMAT_RGBA8, noise_data.get_data())
	var output_image := Image.create_empty(MAP_SIZE, MAP_SIZE,false,  Image.FORMAT_RGBA8)
	
	# 2. Define Texture Format
	var tex_format := RDTextureFormat.new()
	tex_format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tex_format.width = MAP_SIZE
	tex_format.height = MAP_SIZE
	tex_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	# 3. Define Texture View
	var tex_view := RDTextureView.new()

	var noise_tex = rd.texture_create(tex_format, tex_view, [noise_image.get_data()])
	var output_tex = rd.texture_create(tex_format, tex_view, [output_image.get_data()])
	
	# Bind input/output images as RDUniforms
	var bindings := []

	var u_noise := RDUniform.new()
	u_noise.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_noise.binding = 0
	u_noise.add_id(noise_tex)
	bindings.append(u_noise)


	var u_output := RDUniform.new()
	u_output.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_output.binding = 1
	u_output.add_id(output_tex)
	bindings.append(u_output)
	
	var params_data := PackedByteArray()
	
	append_f32(params_data,25.0)
	append_f32(params_data, float(MAP_SIZE))
	
	while params_data.size() < 32:
		params_data.append(0)
		
	var uniform_buffer = rd.uniform_buffer_create(params_data.size(), params_data)
	var u_params := RDUniform.new()
	u_params.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u_params.binding = 2  # must match shader
	u_params.add_id(uniform_buffer)
	bindings.append(u_params)

	var uniform_set: RID = rd.uniform_set_create(bindings, shader, 0)
	# Dispatch the compute shader
	var image_height = MAP_SIZE
	var x_groups = MAP_SIZE / 1024
	var y_groups = int(ceil(float(image_height)))

	uniform_set = rd.uniform_set_create(bindings, shader, 0)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync() # <-- needed to ensure results are visible before next pass


	var result_data = rd.texture_get_data(output_tex, 0)
	var debug_image = Image.create_from_data(MAP_SIZE,MAP_SIZE,false, Image.FORMAT_RGBA8, result_data)
	debug_image.save_png("res://DirtComputeTest.png")
	return result_data

#Helpers for adding float and int data to the shader buffer.
func append_f32(arr: PackedByteArray, value: float):
	arr.append_array(PackedByteArray([value]))
	
func append_i32(arr: PackedByteArray, value: int):
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_s32(0, value)
	arr.append_array(bytes)
