extends Node3D
# Pajar - Monton de paja con hebras individuales visibles y agujero natural

@export var total_straws: int = 350
@export var base_radius: float = 3.0
@export var pile_height: float = 1.8
@export var auto_regenerate: bool = true
@export var regenerate_delay: float = 2.0

enum StrawTier {
	TIER_1_COMMON = 0,
	TIER_2_DRY = 1,
	TIER_3_GOLDEN = 2
}

const STRAW_TIERS = {
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
	var tier: int
	var position: Vector3
	var rotation: Vector3
	var length: float
	var thickness: float
	var node: Node3D = null
	var is_removed: bool = false
	func _init(t: int, pos: Vector3, rot: Vector3, len: float, thick: float):
		tier = t
		position = pos
		rotation = rot
		length = len
		thickness = thick

var straws: Array[StrawData] = []
var straws_container: Node3D
var pile_collision_body: StaticBody3D
var is_regenerating: bool = false

@onready var straw_script = preload("res://straw.gd")

func _ready():
	# Crear contenedor si no existe
	if has_node("Straws"):
		straws_container = $Straws
	else:
		straws_container = Node3D.new()
		straws_container.name = "Straws"
		add_child(straws_container)
	
	# Crear colision grande para que el jugador pueda subirse (opcional)
	_ensure_pile_collision()
	
	# Generar monton
	generate_pile()
	DebugLogger.log("Piramide paja inicializada con %d hebras" % total_straws)

func _ensure_pile_collision():
	if has_node("PileCollision"):
		pile_collision_body = $PileCollision
		return
	pile_collision_body = StaticBody3D.new()
	pile_collision_body.name = "PileCollision"
	pile_collision_body.collision_layer = 1
	pile_collision_body.collision_mask = 1
	var col_shape = CollisionShape3D.new()
	var cyl = CylinderShape3D.new()
	cyl.height = pile_height
	cyl.radius = base_radius
	col_shape.shape = cyl
	col_shape.position = Vector3(0, pile_height * 0.5, 0)
	pile_collision_body.add_child(col_shape)
	add_child(pile_collision_body)

func clear_pile():
	for s in straws:
		if s.node and is_instance_valid(s.node):
			s.node.queue_free()
	straws.clear()
	# limpiar hijos del contenedor por si acaso
	for child in straws_container.get_children():
		child.queue_free()

func generate_pile():
	if is_regenerating:
		return
	clear_pile()
	straws = []
	
	# Generar distribución cónica/domo
	for i in range(total_straws):
		# Altura con mas densidad abajo
		var height_factor = pow(randf(), 1.35) # 0=abajo, 1=arriba
		var y = height_factor * pile_height + randf_range(-0.03, 0.03)
		
		# Radio maximo decrece con altura (forma monton)
		var max_r = base_radius * (1.0 - height_factor * 0.55)
		# Distribucion uniforme en disco
		var r = sqrt(randf()) * max_r
		var angle = randf() * TAU
		
		var x = cos(angle) * r + randf_range(-0.06, 0.06)
		var z = sin(angle) * r + randf_range(-0.06, 0.06)
		
		var tier = determine_tier_by_height(height_factor)
		var length = randf_range(0.85, 1.5)
		var thickness = randf_range(0.035, 0.07)
		
		# Rotacion: paja tumbada horizontal, orientacion aleatoria
		# Las briznas en la base mas horizontales, arriba un poco mas desordenadas
		var rot_y = randf() * TAU
		# 90 grados = horizontal. Variacion de +-25 grados
		var tilt_range = lerp(15.0, 35.0, height_factor)
		var rot_x = deg_to_rad(90.0 + randf_range(-tilt_range, tilt_range))
		var rot_z = deg_to_rad(randf_range(-18.0, 18.0))
		
		# Un poco de inclinacion hacia el centro para forma de monton
		var to_center = Vector2(-x, -z).normalized()
		if to_center.length() > 0.001:
			# inclinar ligeramente hacia dentro
			rot_x += to_center.x * 0.05
			rot_z += to_center.y * 0.05
		
		var data = StrawData.new(tier, Vector3(x, y, z), Vector3(rot_x, rot_y, rot_z), length, thickness)
		straws.append(data)
		_create_straw_node(i, data)
	
	# Actualizar colision de pila
	if pile_collision_body and pile_collision_body.get_child_count() > 0:
		var col = pile_collision_body.get_child(0) as CollisionShape3D
		if col and col.shape is CylinderShape3D:
			(col.shape as CylinderShape3D).height = pile_height
			(col.shape as CylinderShape3D).radius = base_radius
	
	DebugLogger.log("Monton generado: %d hebras" % straws.size())

func determine_tier_by_height(ratio: float) -> int:
	# ratio 0=base, 1=punta
	if ratio < 0.45:
		# Base: 85% comun, 15% seca
		return StrawTier.TIER_1_COMMON if randf() < 0.85 else StrawTier.TIER_2_DRY
	elif ratio < 0.78:
		# Medio: 40% comun, 45% seca, 15% dorada
		var r = randf()
		if r < 0.4:
			return StrawTier.TIER_1_COMMON
		elif r < 0.85:
			return StrawTier.TIER_2_DRY
		else:
			return StrawTier.TIER_3_GOLDEN
	else:
		# Punta: 20% comun, 35% seca, 45% dorada
		var r2 = randf()
		if r2 < 0.2:
			return StrawTier.TIER_1_COMMON
		elif r2 < 0.55:
			return StrawTier.TIER_2_DRY
		else:
			return StrawTier.TIER_3_GOLDEN

func _create_straw_node(index: int, data: StrawData):
	var root = Node3D.new()
	root.name = "Straw_%d" % index
	root.position = data.position
	root.rotation = data.rotation
	
	# Mesh: usar BoxMesh alargada para ver hebra bien
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	var box = BoxMesh.new()
	# BoxMesh size = (grosor, grosor, largo)
	box.size = Vector3(data.thickness, data.thickness, data.length)
	# Material por tier con variacion
	var mat = StandardMaterial3D.new()
	var base_color: Color = STRAW_TIERS[data.tier]["color"]
	# Variacion ligera
	var var_r = randf_range(0.92, 1.08)
	var var_g = randf_range(0.92, 1.08)
	var var_b = randf_range(0.92, 1.08)
	var varied = Color(
		clamp(base_color.r * var_r, 0, 1),
		clamp(base_color.g * var_g, 0, 1),
		clamp(base_color.b * var_b, 0, 1)
	)
	mat.albedo_color = varied
	mat.roughness = 0.82
	mat.metallic = 0.0
	# Hacer que se vea mejor con luz
	mat.roughness_texture = null
	# Un poco de emision sutil para dorada
	if data.tier == StrawTier.TIER_3_GOLDEN:
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.22, 0.0)
		mat.emission_energy_multiplier = 0.15
	
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	# Sombra
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	root.add_child(mesh_inst)
	
	# Body para seleccion con raycast (capa 2)
	var body = StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 2
	body.collision_mask = 0
	# Asignar script straw.gd
	body.set_script(straw_script)
	body.pile = self
	body.straw_index = index
	body.tier = data.tier
	body.add_to_group("straw")
	
	var col_shape = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	# Colision un poco mas grande para facilitar click
	shape.size = Vector3(data.thickness * 2.5, data.thickness * 2.5, data.length * 1.1)
	col_shape.shape = shape
	body.add_child(col_shape)
	
	root.add_child(body)
	
	straws_container.add_child(root)
	data.node = root

# Llamado desde straw.gd o desde raycast general
func try_pick_straw(index: int, jugador, _hit_pos: Vector3 = Vector3.ZERO):
	if index < 0 or index >= straws.size():
		return
	var data = straws[index]
	if data.is_removed:
		return
	
	if jugador.paja_en_mano >= jugador.capacidad_max:
		crear_texto_flotante("¡Mano llena!", Color.RED)
		return
	
	# Intentar agregar al inventario
	var agregado = false
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
	
	# Animacion de recoleccion y remover
	data.is_removed = true
	animar_recoleccion_hebra(data)
	
	var tier_info = STRAW_TIERS[data.tier]
	crear_texto_flotante("+1 %s" % tier_info["name"], tier_info["color"])
	
	# Comprobar si queda paja
	var remaining = get_remaining_count()
	if remaining == 0 and auto_regenerate:
		# Regenerar tras delay
		if not is_regenerating:
			is_regenerating = true
			await get_tree().create_timer(regenerate_delay).timeout
			generate_pile()
			is_regenerating = false
			crear_texto_flotante("¡Montón renovado!", Color.GREEN)
	elif remaining > 0:
		# Efecto de asentamiento: hebras cercanas caen un poco para hacer agujero mas natural
		_apply_settle_effect(data.position)

func get_remaining_count() -> int:
	var c = 0
	for s in straws:
		if not s.is_removed:
			c += 1
	return c

func _apply_settle_effect(removed_pos: Vector3):
	# Las hebras cercanas a la removida caen un poco (simula gravedad)
	for s in straws:
		if s.is_removed or s.node == null:
			continue
		var dist = s.position.distance_to(removed_pos)
		if dist < 0.6:
			# Cuanto mas cerca, mas cae
			var fall_amount = (0.6 - dist) * 0.15
			var target_y = max(0.02, s.position.y - fall_amount)
			# Tween
			if is_instance_valid(s.node):
				var tween = get_tree().create_tween()
				tween.tween_property(s.node, "position:y", target_y, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				s.position.y = target_y

func animar_recoleccion_hebra(data: StrawData):
	if data.node == null or not is_instance_valid(data.node):
		return
	var node = data.node
	# Animacion: se levanta y se hace pequeña hacia la camara
	var tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "position:y", node.position.y + 0.5, 0.15)
	tween.tween_property(node, "scale", Vector3(0.1, 0.1, 0.1), 0.2).set_delay(0.05)
	tween.chain().tween_callback(func(): 
		if is_instance_valid(node):
			node.queue_free()
	)

# Para cuando el raycast golpea el PileCollision grande, no una hebra especifica
func hacer_clic(jugador, hit_pos: Vector3 = Vector3.ZERO):
	# Si nos dan posicion de impacto, buscar la hebra mas cercana a ese punto
	if hit_pos != Vector3.ZERO:
		var closest_idx = find_closest_straw(hit_pos)
		if closest_idx != -1:
			try_pick_straw(closest_idx, jugador, hit_pos)
			return
	# Fallback: hebra aleatoria de la superficie exterior
	var candidates = get_exposed_straws()
	if candidates.size() > 0:
		var rnd = candidates[randi() % candidates.size()]
		try_pick_straw(rnd, jugador, hit_pos)
	else:
		crear_texto_flotante("¡Sin paja!", Color.WHITE)

func find_closest_straw(world_pos: Vector3) -> int:
	var local_pos = to_local(world_pos)
	var best_idx = -1
	var best_dist = 1000.0
	for i in range(straws.size()):
		var s = straws[i]
		if s.is_removed:
			continue
		var d = s.position.distance_to(local_pos)
		# Preferir hebras que esten mas arriba (visibles)
		# penalizar ligeramente las muy bajas si hay otras cerca
		if d < best_dist and d < 0.8:
			best_dist = d
			best_idx = i
	# Si no encontramos dentro de 0.8, buscar la mas cercana sin limite pero con preferencia exterior
	if best_idx == -1:
		best_dist = 1000.0
		for i in range(straws.size()):
			var s = straws[i]
			if s.is_removed:
				continue
			var d = s.position.distance_to(local_pos)
			if d < best_dist:
				best_dist = d
				best_idx = i
	return best_idx

func get_exposed_straws() -> Array:
	# Hebras expuestas = las mas externas en cada direccion, o las de arriba
	var exposed: Array = []
	for i in range(straws.size()):
		var s = straws[i]
		if s.is_removed:
			continue
		# Consideramos expuesta si esta relativamente alta o lejos del centro
		var dist_from_center = Vector2(s.position.x, s.position.z).length()
		var max_r_at_height = base_radius * (1.0 - (s.position.y / pile_height) * 0.5)
		# Si esta cerca del borde exterior, es expuesta
		if dist_from_center > max_r_at_height * 0.65 or s.position.y > pile_height * 0.5:
			exposed.append(i)
	# Si no hay suficientes, devolver todas las restantes
	if exposed.size() < 10:
		exposed.clear()
		for i in range(straws.size()):
			if not straws[i].is_removed:
				exposed.append(i)
	return exposed

func crear_texto_flotante(texto: String, color: Color):
	var label = Label3D.new()
	label.text = texto
	label.font_size = 48
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.no_depth_test = false
	label.position = Vector3(randf_range(-0.5, 0.5), pile_height + 1.0 + randf_range(0, 0.5), randf_range(-0.5, 0.5))
	add_child(label)
	var tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 1.2, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(label.queue_free)

func debug_info():
	DebugLogger.log("=== Piramide Debug ===")
	DebugLogger.log("Total: %d Restantes: %d" % [straws.size(), get_remaining_count()])
	var counts = [0,0,0]
	for s in straws:
		if not s.is_removed:
			counts[s.tier] += 1
	DebugLogger.log("Comunes: %d Secas: %d Doradas: %d" % [counts[0], counts[1], counts[2]])
