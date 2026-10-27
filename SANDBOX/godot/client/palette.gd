## Placeholder colours/materials (deliberately plain: no art direction yet).
extends RefCounted

const GROUND := Color(0.42, 0.46, 0.40)
const GROUND_LINE := Color(0.36, 0.40, 0.34)
const OBSTACLE := Color(0.33, 0.33, 0.36)
const PLATFORM := Color(0.62, 0.62, 0.60)
const BLOCK := Color(0.80, 0.72, 0.55)
const RESOURCE := Color(0.85, 0.52, 0.22)
const AVATAR := Color(0.25, 0.45, 0.80)
const VISOR := Color(0.10, 0.10, 0.12)

static var _cache := {}


static func material(color: Color) -> StandardMaterial3D:
	if not _cache.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		_cache[color] = m
	return _cache[color]


## Two-tone grid texture so movement is readable on the flat ground.
static func ground_material() -> StandardMaterial3D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(GROUND)
	for i in 64:
		img.set_pixel(i, 0, GROUND_LINE)
		img.set_pixel(0, i, GROUND_LINE)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_scale = Vector3(90, 90, 1)
	m.roughness = 1.0
	return m
