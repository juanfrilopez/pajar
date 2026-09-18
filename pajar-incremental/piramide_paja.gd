extends Node3D
# v3 - Montón de paja ultrafina (~1900 hebras) con MultiMesh.
# Un draw call por tier; un solo cuerpo de colisión para caminar y recoger.

@export var total_straws: int = 1900
@export var base_radius: float = 2.5
@export var pile_height: float = 1.65
@export var auto_regenerate: bool = true
@export var regenerate_delay: float = 2.0
@export var use_seed: bool = true
@export var pile_seed: int = 1900

enum StrawTier {
	TIER_1_COMMON = 0,
	TIER_2_DRY = 1,
	TIER_3_GOLDEN = 2
}

const STRAW_TIERS: Dictionary = {
	StrawTier.TIER_1_COMMON: {
		"name": "Paja Común",
		"sell_value": 1,
		"color": Color(0.94, 0.82, 0.62),
	},
	StrawTier.TIER_2_DRY: {
		"name": "Paja Seca",
		"sell_value": 2,
		"color": Color(0.78, 0.66, 0.47),
	},
	StrawTier.TIER_3_GOLDEN: {
		"name": "Paja Dorada",
		"sell_value": 5,
		"color": Color(1.0, 0.84, 0.0),
	}
}

class StrawData:
	var index: int
	var tier: int
	var mm_index: int = -1
	var position: Vector3
	var rotation: Vector3
	var length: float
	var thickness: float
	var color: Color
	var is_removed: bool = false
	func _init(idx: int, t: int, pos: Vector3, rot: Vector3, len: float, thick: float, col: Color):
		index = idx
		tier = t
		position = pos
		rotation = rot
		length = len
		thickness = thick
		color = col

var straws: Array[StrawData] = []
var straws_container: Node3D
var pile_collision_body: StaticBody3D
var is_regenerating: bool = false

var _mmis: Array[MultiMeshInstance3D] = []
var _mms: Array[MultiMesh] = []
var _straw_mesh: CylinderMesh
var _pickup_mesh: CylinderMesh
var _tier_mats: Array[StandardMaterial3D] = []

const _pile_click_script = preload("res://pile_click.gd")

func _ready():
	if has_node("Straws"):
		straws_container = $Straws
	else:
		straws_container = Node3D.new()
		straws_container.name = "Straws"
		add_child(straws_container)

	_ensure_shared_resources()
	_ensure_multimeshes()
	_ensure_pile_collision()
	generate_pile()
	DebugLogger.log("Piramide paja v3 inicializada con %d hebras ultrafinas" % total_straws)

func _ensure_shared_resources():
	if _straw_mesh == null:
		_straw_mesh = CylinderMesh.new()
		_straw_mesh.top_radius = 1.0
		_straw_mesh.bottom_radius = 1.0
		_straw_mesh.height = 1.0
		_straw_mesh.radial_segments = 6
		_straw_mesh.rings = 1
	if _pickup_mesh == null:
		_pickup_mesh = _straw_mesh
	if _tier_mats.size() == 3:
		return
	_tier_mats.clear()
	for tier in range(3):
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.88
		mat.metallic = 0.0
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if tier == StrawTier.TIER_3_GOLDEN:
			mat.emission_enabled = true
			mat.emission = Color(0.35, 0.24, 0.0)
			mat.emission_energy_multiplier = 0.22
		_tier_mats.append(mat)

func _ensure_multimeshes():
	if _mmis.size() == 3:
		return
	_mmis.clear()
	_mms.clear()
	for tier in range(3):
		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mmi.name = "StrawsMM_%d" % tier
		mmi.material_override = _tier_mats[tier]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		straws_container.add_child(mmi)
		_mmis.append(mmi)
		_mms.append(null)

func _ensure_pile_collision():
	if has_node("PileCollision"):
		pile_collision_body = $PileCollision
	else:
		pile_collision_body = StaticBody3D.new()
		pile_collision_body.name = "PileCollision"
		var col_shape: CollisionShape3D = CollisionShape3D.new()
		var cyl: CylinderShape3D = CylinderShape3D.new()
		cyl.height = pile_height
		cyl.radius = base_radius
		col_shape.shape = cyl
		col_shape.position = Vector3(0, pile_height * 0.5, 0)
		pile_collision_body.add_child(col_shape)
		add_child(pile_collision_body)
	pile_collision_body.collision_layer = 1
	pile_collision_body.collision_mask = 1
	if pile_collision_body.get_script() != _pile_click_script:
		pile_collision_body.set_script(_pile_click_script)

func clear_pile():
	straws.clear()
	for mm in _mms:
		if mm:
			mm.instance_count = 0

func generate_pile():
	if is_regenerating:
		return
	clear_pile()
	if use_seed:
		seed(pile_seed)

	straws = []
	var buckets: Array = [[], [], []]

	for i in range(total_straws):
		var height_factor: float = pow(randf(), 1.45)
		var y: float = height_factor * pile_height + randf_range(-0.02, 0.02)
		var max_r: float = base_radius * (1.0 - height_factor * 0.58)
		var r: float = sqrt(randf()) * max_r
		var angle: float = randf() * TAU
		var x: float = cos(angle) * r + randf_range(-0.04, 0.04)
		var z: float = sin(angle) * r + randf_range(-0.04, 0.04)

		var tier: int = determine_tier_by_height(height_factor)
		# Ultrafina: radio ~0.6–1.4 cm (antes las cajas medían 3.5–7 cm)
		var thickness: float = randf_range(0.006, 0.014)
		var length: float = randf_range(0.55, 1.25)

		var rot_y: float = randf() * TAU
		var tilt_range: float = lerpf(12.0, 32.0, height_factor)
		var rot_x: float = deg_to_rad(90.0 + randf_range(-tilt_range, tilt_range))
		var rot_z: float = deg_to_rad(randf_range(-16.0, 16.0))
		var to_center: Vector2 = Vector2(-x, -z)
		if to_center.length() > 0.001:
			to_center = to_center.normalized()
			rot_x += to_center.x * 0.04
			rot_z += to_center.y * 0.04

		var base_color: Color = STRAW_TIERS[tier]["color"]
		var varied: Color = Color(
			clampf(base_color.r * randf_range(0.88, 1.10), 0.0, 1.0),
			clampf(base_color.g * randf_range(0.88, 1.10), 0.0, 1.0),
			clampf(base_color.b * randf_range(0.88, 1.12), 0.0, 1.0)
		)
		var data: StrawData = StrawData.new(i, tier, Vector3(x, y, z), Vector3(rot_x, rot_y, rot_z), length, thickness, varied)
		straws.append(data)
		buckets[tier].append(data)

	_fill_multimeshes(buckets)
	_sync_pile_collision()
	DebugLogger.log("Monton v3 generado: %d hebras ultrafinas" % straws.size())

func _fill_multimeshes(buckets: Array) -> void:
	for tier in range(3):
		var list: Array = buckets[tier]
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _straw_mesh
		mm.instance_count = maxi(list.size(), 1)
		if list.is_empty():
			mm.set_instance_transform(0, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0)))
			mm.set_instance_color(0, Color(1, 1, 1, 0))
		else:
			for j in range(list.size()):
				var s: StrawData = list[j]
				s.mm_index = j
				mm.set_instance_transform(j, _straw_transform(s))
				mm.set_instance_color(j, s.color)
		_mms[tier] = mm
		_mmis[tier].multimesh = mm

func _straw_transform(data: StrawData) -> Transform3D:
	var basis: Basis = Basis.from_euler(data.rotation)
	basis = basis.scaled(Vector3(data.thickness, data.length, data.thickness))
	return Transform3D(basis, data.position)

func _hide_instance(data: StrawData) -> void:
	if data.mm_index < 0:
		return
	var mm: MultiMesh = _mms[data.tier]
	if mm == null:
		return
	mm.set_instance_transform(data.mm_index, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -80, 0)))

func _sync_instance(data: StrawData) -> void:
	if data.is_removed or data.mm_index < 0:
		return
	var mm: MultiMesh = _mms[data.tier]
	if mm == null:
		return
	mm.set_instance_transform(data.mm_index, _straw_transform(data))

func _sync_pile_collision() -> void:
	if pile_collision_body == null:
		return
	for child in pile_collision_body.get_children():
		if child is CollisionShape3D and child.shape is CylinderShape3D:
			(child.shape as CylinderShape3D).height = pile_height
			(child.shape as CylinderShape3D).radius = base_radius
			child.position = Vector3(0, pile_height * 0.5, 0)

func determine_tier_by_height(ratio: float) -> int:
	if ratio < 0.45:
		return StrawTier.TIER_1_COMMON if randf() < 0.85 else StrawTier.TIER_2_DRY
	elif ratio < 0.78:
		var r: float = randf()
		if r < 0.4:
			return StrawTier.TIER_1_COMMON
		elif r < 0.85:
			return StrawTier.TIER_2_DRY
		else:
			return StrawTier.TIER_3_GOLDEN
	else:
		var r2: float = randf()
		if r2 < 0.2:
			return StrawTier.TIER_1_COMMON
		elif r2 < 0.55:
			return StrawTier.TIER_2_DRY
		else:
			return StrawTier.TIER_3_GOLDEN

func try_pick_straw(index: int, jugador, _hit_pos: Vector3 = Vector3.ZERO):
	if index < 0 or index >= straws.size():
		return
	var data: StrawData = straws[index]
	if data.is_removed:
		return

	if jugador.paja_en_mano >= jugador.capacidad_max:
		crear_texto_flotante("¡Mano llena!", Color.RED)
		return

	var agregado: bool = false
	if jugador.has_method("agregar_paja"):
		agregado = jugador.agregar_paja(data.tier, 1)
	else:
		if jugador.paja_en_mano < jugador.capacidad_max:
			jugador.paja_en_mano += 1
			agregado = true
			if jugador.has_method("actualizar_ui"):
				jugador.actualizar_ui()

	if not agregado:
		crear_texto_flotante("¡Mano llena!", Color.RED)
		return

	data.is_removed = true
	_hide_instance(data)
	animar_recoleccion_hebra(data)

	var tier_info: Dictionary = STRAW_TIERS[data.tier]
	crear_texto_flotante("+1 %s" % tier_info["name"], tier_info["color"])

	var remaining: int = get_remaining_count()
	if remaining == 0 and auto_regenerate:
		if not is_regenerating:
			is_regenerating = true
			await get_tree().create_timer(regenerate_delay).timeout
			is_regenerating = false
			generate_pile()
			crear_texto_flotante("¡Montón renovado!", Color.GREEN)
	elif remaining > 0:
		_apply_settle_effect(data.position)

func get_remaining_count() -> int:
	var c: int = 0
	for s in straws:
		if not s.is_removed:
			c += 1
	return c

func _apply_settle_effect(removed_pos: Vector3):
	for s in straws:
		if s.is_removed:
			continue
		var dist: float = s.position.distance_to(removed_pos)
		if dist < 0.55:
			var fall_amount: float = (0.55 - dist) * 0.12
			var target_y: float = maxf(0.02, s.position.y - fall_amount)
			s.position.y = target_y
			_sync_instance(s)

func animar_recoleccion_hebra(data: StrawData):
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = _pickup_mesh
	node.material_override = _tier_mats[data.tier]
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.transform = _straw_transform(data)
	straws_container.add_child(node)
	var tween: Tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "position:y", node.position.y + 0.45, 0.15)
	tween.tween_property(node, "scale", Vector3(0.08, 0.08, 0.08), 0.2).set_delay(0.05)
	tween.chain().tween_callback(node.queue_free)

func hacer_clic(jugador, hit_pos: Vector3 = Vector3.ZERO):
	if hit_pos != Vector3.ZERO:
		var closest_idx: int = find_closest_straw(hit_pos)
		if closest_idx != -1:
			try_pick_straw(closest_idx, jugador, hit_pos)
			return
	var candidates: Array = get_exposed_straws()
	if candidates.size() > 0:
		var rnd: int = candidates[randi() % candidates.size()]
		try_pick_straw(rnd, jugador, hit_pos)
	else:
		crear_texto_flotante("¡Sin paja!", Color.WHITE)

func find_closest_straw(world_pos: Vector3) -> int:
	var local_pos: Vector3 = to_local(world_pos)
	var best_idx: int = -1
	var best_score: float = 1e9
	for i in range(straws.size()):
		var s: StrawData = straws[i]
		if s.is_removed:
			continue
		var d: float = s.position.distance_to(local_pos)
		# Preferir hebras de la superficie (más altas) si están cerca del impacto
		var score: float = d - s.position.y * 0.12
		if score < best_score:
			best_score = score
			best_idx = i
	return best_idx

func get_exposed_straws() -> Array:
	var exposed: Array = []
	for i in range(straws.size()):
		var s: StrawData = straws[i]
		if s.is_removed:
			continue
		var dist_from_center: float = Vector2(s.position.x, s.position.z).length()
		var height_ratio: float = 0.0
		if pile_height > 0.001:
			height_ratio = s.position.y / pile_height
		var max_r_at_height: float = base_radius * (1.0 - height_ratio * 0.5)
		if dist_from_center > max_r_at_height * 0.65 or s.position.y > pile_height * 0.5:
			exposed.append(i)
	if exposed.size() < 10:
		exposed.clear()
		for i in range(straws.size()):
			if not straws[i].is_removed:
				exposed.append(i)
	return exposed

func crear_texto_flotante(texto: String, color: Color):
	var label: Label3D = Label3D.new()
	label.text = texto
	label.font_size = 48
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.no_depth_test = false
	label.position = Vector3(randf_range(-0.5, 0.5), pile_height + 1.0 + randf_range(0, 0.5), randf_range(-0.5, 0.5))
	add_child(label)
	var tween: Tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 1.2, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(label.queue_free)

func debug_info():
	DebugLogger.log("=== Piramide Debug v3 ===")
	DebugLogger.log("Total: %d Restantes: %d" % [straws.size(), get_remaining_count()])
	var counts: Array[int] = [0, 0, 0]
	for s in straws:
		if not s.is_removed:
			counts[s.tier] += 1
	DebugLogger.log("Comunes: %d Secas: %d Doradas: %d" % [counts[0], counts[1], counts[2]])
