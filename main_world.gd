extends Node2D

var noise

@export var player : CharacterBody2D

@export_category("Tile Map Layers")
@export var dirtMap : TileMapLayer
@export var backgroundMap : TileMapLayer
@export var foliage : TileMapLayer
@export var tree_map : TileMapLayer


@export_category("Entity Scenes")
@export var butterfly : Resource
@export var slime : Resource
@export var shroomy : Resource


#Chunk Data
var LOADED_MAP_DICT : Dictionary = {}
var CHUNK_LOAD_RANGE = 12
var CHUNK_SIZE = 8
var MAP_SIZE = 1024
var SHADOWS_RESOLUTION_MULTIPLAYER = 2
@export_category("Chunk Loading")
@export var chunk_load_timer : Timer
@export var CHUNK_LOADER : Node2D

#Map Data. Responsible for tiles and lighting
var MAP_DATA : Image
var LIGHT_IMAGE = Image.create_empty(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8)
var LIGHT_TEXTURE : ImageTexture
var BLOCK_DATA = {}

var currNearestChunks : Dictionary = {}
var prevNearestChunks : Dictionary = {}
var distantChunks : Dictionary = {}
var light_sources : Array = []
var max_chunks = 500

var loaded_chunk_count = 0

#Shadow Texture. The Shadow_text is a child of the player so it follows the player around.
# This is to avoid having the sprite be the size of the entire map. so it only renders what is in the sprite's region rect
var shadow_rect_offset = MAP_SIZE/(8 * (MAP_SIZE / 1024))
@export var Shadow_text : Sprite2D


# IMPORTANT: You'll notice me using the number 8 everywhere. This is because my tiles are 8x8 pixels. This will likely have to change if your tiles are different dimensions.

func _process(delta):
	# Updates the rectanlge position in the shadow texture.
	Shadow_text.region_rect = Rect2((player.position.x / 8  - shadow_rect_offset) * SHADOWS_RESOLUTION_MULTIPLAYER, (player.position.y / 8 - shadow_rect_offset) * SHADOWS_RESOLUTION_MULTIPLAYER,256 * SHADOWS_RESOLUTION_MULTIPLAYER, 256 * SHADOWS_RESOLUTION_MULTIPLAYER)
	
	light_source_test()


func _ready() -> void:
	build_world()
	light_sources.append({"color" : Color.CHARTREUSE, "intensity" : 2, "object" : player.staff.spellPoint, "radius" : 2})	


func build_world():
	CHUNK_LOADER.MAP_SIZE = MAP_SIZE
	CHUNK_LOADER.SHADOWS_RESOLUTION_MULTIPLAYER = SHADOWS_RESOLUTION_MULTIPLAYER
	
	load_block_id_data()
	
	noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.01
	CHUNK_LOADER.noise = noise
	CHUNK_LOADER.build_chunk()
	
	check_chunks()
	chunk_load_timer.timeout.connect(check_chunks)
	
	setup_lightmap()
	
	#Spawns player in the middle of the map.
	player.position.x = MAP_SIZE / 2 * 8
	player.position.y = 1500

func load_block_id_data():
	var dataFile = FileAccess.open("res://Block_ids.json", FileAccess.READ)
	var RAW_DATA = JSON.parse_string(dataFile.get_as_text())
	for key in RAW_DATA.keys():
		BLOCK_DATA[int(key)] = RAW_DATA[key]
	dataFile.close()

func check_chunks():
	if !player:
		return

	var playerChunk = Vector2i(
		int(player.position.x / (CHUNK_SIZE * 8)),
		int(player.position.y / (CHUNK_SIZE * 8))
	)

	var newNearestChunks = {}

	for x in range(-CHUNK_LOAD_RANGE, CHUNK_LOAD_RANGE + 1):
		for y in range(-CHUNK_LOAD_RANGE, CHUNK_LOAD_RANGE + 1):
			var offset = Vector2i(x, y)
			if offset.length() > CHUNK_LOAD_RANGE:
				continue

			var chunk = playerChunk + offset

			newNearestChunks[chunk] = true

			if !LOADED_MAP_DICT.has(chunk):
				load_chunk(chunk)
				LOADED_MAP_DICT[chunk] = true
				loaded_chunk_count += 1
				await get_tree().process_frame

	# TODO: Must optimize this unloading. Runs well on small test map for now but should thread this or similar.
	#for chunk in prevNearestChunks.keys():
		#if !newNearestChunks.has(chunk):
			#unload_chunk(chunk)
			#LOADED_MAP_DICT.erase(chunk)
			#loaded_chunk_count -= 1

	# Swap
	prevNearestChunks = currNearestChunks
	currNearestChunks = newNearestChunks
	
func load_chunk(chunk):
	if(chunk.x < 0 || chunk.y < 0 || chunk.y * CHUNK_SIZE >= MAP_SIZE || chunk.y * CHUNK_SIZE >= MAP_SIZE):
		return
	for x in range(chunk.x * CHUNK_SIZE , (chunk.x + 1) * CHUNK_SIZE):
		for y in range(chunk.y * CHUNK_SIZE , (chunk.y + 1) * CHUNK_SIZE):
			if(x > MAP_SIZE || y > MAP_SIZE):
				continue
			if(CHUNK_LOADER.get_pixelv("FOREGROUND", Vector2i(x,y)) != 0):
				clean_up(dirtMap, Vector2i(x,y), "FOREGROUND")
				
			if(CHUNK_LOADER.get_pixelv("BACKGROUND", Vector2i(x,y)) != 0):
				clean_up(backgroundMap, Vector2i(x,y), "BACKGROUND")

	
func unload_chunk(chunk):
	if(chunk.x < 0 || chunk.y < 0 || chunk.y * CHUNK_SIZE >= MAP_SIZE || chunk.y * CHUNK_SIZE >= MAP_SIZE):
		return
	for x in range(chunk.x * CHUNK_SIZE , (chunk.x + 1) * CHUNK_SIZE):
		for y in range(chunk.y * CHUNK_SIZE , (chunk.y + 1) * CHUNK_SIZE):
			dirtMap.erase_cell(Vector2i(x,y))
			backgroundMap.erase_cell(Vector2i(x,y))
			
			if(y % (CHUNK_SIZE) == 0):
				await get_tree().process_frame


func clean_up(map, cell, image):
	var tile = Vector2i(cell.x,cell.y)

	var north = int(tile.y - 1 >= 0 and CHUNK_LOADER.get_pixelv(image, Vector2i(tile.x, tile.y - 1)) != 0)
	var east  = int(tile.x + 1 < MAP_SIZE and CHUNK_LOADER.get_pixelv(image, Vector2i(tile.x + 1, tile.y)) != 0)
	var south = int(tile.y + 1 < MAP_SIZE and CHUNK_LOADER.get_pixelv(image, Vector2i(tile.x, tile.y + 1)) != 0)
	var west  = int(tile.x - 1 >= 0 and CHUNK_LOADER.get_pixelv(image, Vector2i(tile.x - 1, tile.y)) != 0)

	var cardinal_truths = 0
	cardinal_truths += (north << 3)
	cardinal_truths += (east  << 2)
	cardinal_truths += (south << 1)
	cardinal_truths += (west)

	var source_id = 0
	
	var key = int(CHUNK_LOADER.get_pixelv(image, Vector2i(tile.x, tile.y)))
	source_id = BLOCK_DATA[key]["tile_set"] if BLOCK_DATA.has(key) else 0
	
	var randOffset = randi_range(0,1)
	var is_tile = 1
	var scene_id = BLOCK_DATA[key]["scene_id"]
	if BLOCK_DATA[key]["is_scene"]:
		is_tile = 0
	match cardinal_truths:
		0b0111:
			map.set_cell(tile, source_id, Vector2i(2 + randOffset,0) * is_tile , scene_id)
			check_foliage(tile, cardinal_truths)
			spawn_entity(tile)
		0b1101:
			map.set_cell(tile, source_id, Vector2i(2 + randOffset,1) * is_tile , scene_id)
			check_foliage(tile, cardinal_truths)
		0b0011:
			map.set_cell(tile, source_id, Vector2i(0,2 + randOffset) * is_tile , scene_id)
		0b1001:
			map.set_cell(tile, source_id, Vector2i(4,randOffset) * is_tile , scene_id)
		0b1100:
			map.set_cell(tile, source_id, Vector2i(5,randOffset) * is_tile , scene_id)
		0b0110:
			map.set_cell(tile, source_id, Vector2i(1,2 + randOffset) * is_tile , scene_id)
		0b0001:
			map.set_cell(tile, source_id, Vector2i(2 + randOffset,4) * is_tile , scene_id)
		0b0010:
			map.set_cell(tile, source_id, Vector2i(randOffset,4) * is_tile , scene_id)
		0b0100:
			map.set_cell(tile, source_id, Vector2i(2 + randOffset,5) * is_tile , scene_id)
		0b1000:
			map.set_cell(tile, source_id, Vector2i(randOffset,5) * is_tile , scene_id)
		0b0101:
			map.set_cell(tile, source_id, Vector2i(4 + randOffset,5) * is_tile , scene_id)
			check_foliage(tile, cardinal_truths)
		0b0000:
			map.set_cell(tile, source_id, Vector2i(4 + randOffset,4) * is_tile , scene_id)
		0b1011:
			map.set_cell(tile, source_id, Vector2i(3,2 + randOffset) * is_tile , scene_id)
		0b1110:
			map.set_cell(tile, source_id, Vector2i(2,2 + randOffset) * is_tile , scene_id)
		_:
			map.set_cell(tile, source_id, Vector2i(randi_range(0,1),randi_range(0,1)) * is_tile , scene_id)


	
func spawn_entity(tile):
	var choice = randf()
	if(choice > 0.05):
		return
	var worldCoords = Vector2i(tile.x * 8, (tile.y - 10) * 8)
	
	var instance
	if(choice > 0.01):
		instance = butterfly.instantiate()
	else:
		instance = shroomy.instantiate()
	instance.position = worldCoords
	call_deferred("add_child", instance)
	

func check_foliage(tile, cardinals):
	var belowTile = tile - Vector2i(0,1)
	if(CHUNK_LOADER.get_pixel("FOLIAGE", belowTile.x, belowTile.y) != 0):
		var flower = randi_range(-1,4)
		if(flower == -1):
			tree_map.build_tree(tile + Vector2i.UP)
		else:
			foliage.set_cell(tile, 0, Vector2i(flower,1) , 0)
			foliage.set_cell(tile - Vector2i(0,1), 0, Vector2i(flower,0) , 0)
	var aboveTile = tile + Vector2i(0,1)
	if(tile.y < MAP_SIZE - 1 && CHUNK_LOADER.get_pixel("FOLIAGE", aboveTile.x, aboveTile.y) != 0):
		var flower = randi_range(5,6)
		foliage.set_cell(tile, 0, Vector2i(flower,0) , 0)

#Updates any light source in the shadow map shader.
func light_source_test():
	if(!CHUNK_LOADER.MAPS_DATA.has("SHADOWS")):
		return
	var lightData = CHUNK_LOADER.apply_light_shader(light_sources, player)

	Shadow_text.material.set_shader_parameter("light_count", lightData["positions"].size())
	Shadow_text.material.set_shader_parameter("light_positions", lightData["positions"])
	Shadow_text.material.set_shader_parameter("light_colors", lightData["colors"])
	Shadow_text.material.set_shader_parameter("light_intensities", lightData["intensities"])


func setup_lightmap():
	var image = Image.create_from_data(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8, CHUNK_LOADER.MAPS_DATA["LIGHTS_IMAGE"])
	LIGHT_TEXTURE = ImageTexture.create_from_image(image)
	var texture = ImageTexture.create_from_image(CHUNK_LOADER.SHADOW_IMAGE)
	Shadow_text.texture = texture
	Shadow_text.scale = Vector2(8 / SHADOWS_RESOLUTION_MULTIPLAYER, 8 / SHADOWS_RESOLUTION_MULTIPLAYER)
	
	var region_origin = Shadow_text.region_rect.position
	var region_size =  Shadow_text.region_rect.size
	var resolution = MAP_SIZE * SHADOWS_RESOLUTION_MULTIPLAYER
	
	# Creates an image of the terrain at the resolution of the shadow map as to access the same UV coordinate.
	var dirtCopy: Image = Image.create_from_data(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8, CHUNK_LOADER.MAPS_DATA["FOREGROUND"])
	dirtCopy.resize(MAP_SIZE * SHADOWS_RESOLUTION_MULTIPLAYER, MAP_SIZE * SHADOWS_RESOLUTION_MULTIPLAYER,Image.Interpolation.INTERPOLATE_CUBIC)

	var dirt = ImageTexture.create_from_image(dirtCopy)
	Shadow_text.material.set_shader_parameter("region_origin", region_origin) 
	Shadow_text.material.set_shader_parameter("region_size", region_size) 
	Shadow_text.material.set_shader_parameter("resolution", resolution) 
	Shadow_text.material.set_shader_parameter("dirt_map", dirt)
	Shadow_text.material.set_shader_parameter("map_size", MAP_SIZE)
	Shadow_text.material.set_shader_parameter("light_map", LIGHT_TEXTURE)
