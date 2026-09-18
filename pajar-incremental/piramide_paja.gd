extends Node3D
# v4 - "Megamontón" de paja: montículo enorme con hebras CORTAS y HORIZONTALES.
#
# Montón (deja sitio para la AGUJA futura en la punta):
# - Perfil r(f) = base_radius * (1 - f)^MOUND_EXP, con f = y / pile_height.
#   El perfil es cóncavo, así que el sólido de revolución es CONVEXO:
#   basta un único ConvexPolygonShape3D como colisión (caminar y recoger).
# - Pendiente base ~29°: se puede subir ANDANDO por el montón
#   (el jugador tiene floor_max_angle de 45°).
# - La punta queda afilada: ahí irá la aguja en el futuro.
#
# Hebras:
# - MultiMesh (un draw call por tier), total_straws hebras.
# - Cortas (0.35-0.8 m), ultrafinas, tumbadas casi en HORIZONTAL
#   (±14° de inclinación respecto al suelo).
# - 25% pegadas a la superficie (costra "peluda"), el resto rellena
#   el interior en proporción al volumen del montón.

@export var total_straws: int = 18000
@export var base_radius: float = 7.5
@export var pile_height: float = 3.4
@export var auto_regenerate: bool = true
@export var regenerate_delay: float = 2.0
@export var use_seed: bool = true
@export var pile_seed: int = 1900

const MOUND_EXP: float = 0.8            # Perfil: r(f) = R * (1 - f)^MOUND_EXP
const SURFACE_LAYER_RATIO: float = 0.25 # Fracción de hebras sobre la superficie
const STRAW_TILT_DEG: float = 14.0      # Inclinación máx. respecto al horizontal (grados)
const STRAW_LEN_MIN: float = 0.35
const STRAW_LEN_MAX: float = 0.80
const MOUND_RINGS: int = 15             # Muestras del perfil para la colisión
const MOUND_SEGS: int = 20              # Muestras radiales para la colisión

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
	var axis_dir: Vector3  # Dirección del eje de la hebra (≈horizontal)
	var length: float
	var thickness: float
	var color: Color
	var is_removed: bool = false
	func _init(idx: int, t: int, pos: Vector3, axis: Vector3, len: float, thick: float, col: Color):
		index = idx
		tier = t
		position = pos
		axis_dir = axis
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
	DebugLogger.log("Monton de paja v4 inicializado: megamontón de %d hebras cortas y horizontales" % total_straws)

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
		add_child(pile_collision_body)
	pile_collision_body.collision_layer = 1
	pile_collision_body.collision_mask = 1
	if pile_collision_body.get_script() != _pile_click_script:
		pile_collision_body.set_script(_pile_click_script)

# ---------- Geometria del montón ----------

# Radio del perfil a una fracción f de la altura (0 = base, 1 = punta)
func profile_radius(f: float) -> float:
	var t: float = clampf(1.0 - f, 0.0, 1.0)
	return base_radius * pow(t, MOUND_EXP)

func profile_radius_at_y(y: float) -> float:
	if pile_height <= 0.001:
		return base_radius
	return profile_radius(y / pile_height)

# Eje de una hebra tumbada: casi horizontal, azimut aleatorio
func _horizontal_axis() -> Vector3:
	var azimuth: float = randf() * TAU
	var tilt: float = deg_to_rad(randf_range(-STRAW_TILT_DEG, STRAW_TILT_DEG))
	var dir: Vector3 = Vector3(0, 0, 1)
	dir = dir.rotated(Vector3.RIGHT, tilt)   # sale del plano horizontal
	dir = dir.rotated(Vector3.UP, azimuth)  # orientación en el plano horizontal
	return dir.normalized()

# Hebra sobre la superficie del montón (costra peluda)
func _surface_position() -> Vector3:
	var r: float = sqrt(randf()) * base_radius
	var f: float = 1.0 - pow(r / base_radius, 1.0 / MOUND_EXP)
	var y: float = clampf(f * pile_height + randf_range(0.0, 0.12), 0.02, pile_height + 0.12)
	var angle: float = randf() * TAU
	var rr: float = r * randf_range(0.97, 1.0)
	return Vector3(cos(angle) * rr, y, sin(angle) * rr)

# Hebra en el interior, distribuida en proporción al volumen: F(f) = 1 - (1-f)^(2*MOUND_EXP+1)
func _interior_position() -> Vector3:
	var f: float = 1.0 - pow(1.0 - randf(), 1.0 / (2.0 * MOUND_EXP + 1.0))
	var max_r: float = profile_radius(f)
	var r: float = sqrt(randf()) * max_r
	var angle: float = randf() * TAU
	var y: float = clampf(f * pile_height + randf_range(-0.02, 0.02), 0.02, pile_height)
	return Vector3(cos(angle) * r, y, sin(angle) * r)

# Base ortogonal cuyo eje Y apunta a la dirección del eje de la hebra
func _straw_basis(axis: Vector3) -> Basis:
	var x_axis: Vector3 = axis.cross(Vector3.UP)
	if x_axis.length_squared() < 0.0001:
		x_axis = Vector3.RIGHT
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(axis)
	var b: Basis = Basis()
	b.set_columns(x_axis, axis, z_axis)
	return b

# Puntos para el hull convexo del montón (perfil cóncavo => sólido convexo)
func _build_mound_points() -> PackedVector3Array:
	var pts: PackedVector3Array = PackedVector3Array()
	pts.append(Vector3(0, 0, 0))
	for k in range(MOUND_RINGS):
		var f: float = float(k) / float(MOUND_RINGS)
		var rr: float = profile_radius(f)
		var y: float = f * pile_height
		for s in range(MOUND_SEGS):
			var a: float = TAU * float(s) / float(MOUND_SEGS)
			pts.append(Vector3(cos(a) * rr, y, sin(a) * rr))
	pts.append(Vector3(0, pile_height, 0))  # punta afilada: sitio de la aguja futura
	return pts

func _sync_pile_collision() -> void:
	if pile_collision_body == null:
		return
	var shape_node: CollisionShape3D = null
	for child in pile_collision_body.get_children():
		if child is CollisionShape3D:
			shape_node = child
			break
	if shape_node == null:
		shape_node = CollisionShape3D.new()
		pile_collision_body.add_child(shape_node)
	shape_node.position = Vector3.ZERO
	var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	shape.points = _build_mound_points()
	shape_node.shape = shape

# ---------- Generacion ----------

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
		var pos: Vector3
		if randf() < SURFACE_LAYER_RATIO:
			pos = _surface_position()
		else:
			pos = _interior_position()

		var tier: int = determine_tier_by_height(pos.y / pile_height)
		# Ultrafina y corta: radio ~0.6-1.5 cm, longitud 0.35-0.8 m
		var thickness: float = randf_range(0.006, 0.015)
		var length: float = randf_range(STRAW_LEN_MIN, STRAW_LEN_MAX)
		var axis: Vector3 = _horizontal_axis()

		var base_color: Color = STRAW_TIERS[tier]["color"]
		var varied: Color = Color(
			clampf(base_color.r * randf_range(0.88, 1.10), 0.0, 1.0),
			clampf(base_color.g * randf_range(0.88, 1.10), 0.0, 1.0),
			clampf(base_color.b * randf_range(0.88, 1.12), 0.0, 1.0)
		)
		var data: StrawData = StrawData.new(i, tier, pos, axis, length, thickness, varied)
		straws.append(data)
		buckets[tier].append(data)

	_fill_multimeshes(buckets)
	_sync_pile_collision()
	DebugLogger.log("Megamontón v4 generado: %d hebras cortas y horizontales (R=%.1f m, H=%.1f m)" % [straws.size(), base_radius, pile_height])

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
	var basis: Basis = _straw_basis(data.axis_dir)
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

# ---------- Recoleccion ----------

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

# Hebras "expuestas": las que están cerca de la superficie del montón
func get_exposed_straws() -> Array:
	var exposed: Array = []
	for i in range(straws.size()):
		var s: StrawData = straws[i]
		if s.is_removed:
			continue
		var dist_from_center: float = Vector2(s.position.x, s.position.z).length()
		var f: float = 0.0
		if pile_height > 0.001:
			f = s.position.y / pile_height
		var max_r_at_height: float = profile_radius(f)
		if dist_from_center > max_r_at_height * 0.8 or s.position.y > pile_height * 0.8:
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
	DebugLogger.log("=== Monton Debug v4 (megamontón) ===")
	DebugLogger.log("Total: %d Restantes: %d" % [straws.size(), get_remaining_count()])
	DebugLogger.log("Montón: R=%.1f m  H=%.1f m  (pendiente base ~29°, se sube andando)" % [base_radius, pile_height])
	var counts: Array[int] = [0, 0, 0]
	for s in straws:
		if not s.is_removed:
			counts[s.tier] += 1
	DebugLogger.log("Comunes: %d Secas: %d Doradas: %d" % [counts[0], counts[1], counts[2]])
