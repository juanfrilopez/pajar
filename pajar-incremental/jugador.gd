extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.8
const MOUSE_SENSITIVITY = 0.003
const FALL_RESET_Y = -25.0

var paja_en_mano: int = 0
var capacidad_max: int = 15
var oro: int = 0

# --- Sistema de herramientas y mejoras (tienda / futuro granero) ---
var cantidad_por_cosecha: int = 1
var has_guantes: bool = false
var nivel_bolsa: int = 0 # 0 = 15, 1 = 30, futuro 2=45 etc
var mejoras_compradas: Array[String] = []

@onready var camera: Camera3D = $Camera3D
@onready var raycast: RayCast3D = $Camera3D/RayCast3D
@onready var label_paja: Label = get_node_or_null("../UI/VBoxContainer/LabelPaja")
@onready var label_oro: Label = get_node_or_null("../UI/VBoxContainer/LabelOro")
@onready var crosshair: ColorRect = get_node_or_null("../UI/ColorRect")

var hebra_apuntada_idx: int = -1
var pajar_apuntado: Node = null

var gravity: float = 9.8
var spawn_position: Vector3 = Vector3(0, 1.5, 0)
var spawn_rotation_y: float = 0.0

# Tipos de paja
var paja_tipos: Dictionary = {
	0: {"nombre": "Común", "valor": 1},
	1: {"nombre": "Seca", "valor": 2},
	2: {"nombre": "Dorada", "valor": 5}
}

var inventario_paja: Dictionary = {}

func _ready():
	# Guardar spawn
	spawn_position = global_position
	spawn_rotation_y = rotation.y
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	for tipo in paja_tipos:
		inventario_paja[tipo] = 0
	
	gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	
	# Configuracion CharacterBody3D para evitar caidas y deslizamientos raros
	floor_stop_on_slope = true
	floor_constant_speed = true
	floor_block_on_wall = true
	floor_max_angle = deg_to_rad(45)
	# Snap para no caerse por bordes pequeños
	floor_snap_length = 0.3
	# Para Jolt
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_ADD_VELOCITY
	
	# Raycast config
	if raycast:
		raycast.enabled = true
		raycast.collision_mask = 3 # 1 = mundo/vaca, 2 = paja
		raycast.target_position = Vector3(0, 0, -5.5)
	
	DebugLogger.log("Jugador iniciado en %s" % str(spawn_position))
	actualizar_ui()

func _process(_delta):
	actualizar_mira()

func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-85), deg_to_rad(85))
		if raycast:
			raycast.force_raycast_update()
		actualizar_mira()
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Interaccion por click
		try_interact()
	
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func actualizar_mira():
	if not crosshair:
		crosshair = get_node_or_null("../UI/ColorRect")

	if not camera:
		return

	# Si el raycast está colisionando directamente con la vaca o tienda, priorizar eso (no paja detrás)
	if raycast and raycast.is_colliding():
		var col = raycast.get_collider()
		if col and (col.is_in_group("vaca") or col.is_in_group("tienda")):
			hebra_apuntada_idx = -1
			pajar_apuntado = null
			_set_crosshair_style(-1)
			return

	var cam_pos: Vector3 = camera.global_position
	var cam_dir: Vector3 = -camera.global_transform.basis.z.normalized()
	var hit_pos: Vector3 = Vector3.ZERO
	if raycast and raycast.is_colliding():
		hit_pos = raycast.get_collision_point()

	var found_pile: Node = null
	var found_idx: int = -1
	var found_tier: int = -1

	for pile in get_tree().get_nodes_in_group("pajar"):
		if pile.has_method("obtener_hebra_bajo_mira"):
			var info = pile.obtener_hebra_bajo_mira(cam_pos, cam_dir, hit_pos, 5.5)
			if info is Array and info.size() >= 2 and info[0] != -1:
				found_pile = pile
				found_idx = info[0]
				found_tier = info[1]
				break

	hebra_apuntada_idx = found_idx
	pajar_apuntado = found_pile
	_set_crosshair_style(found_tier)

func _set_crosshair_style(tier: int):
	if not crosshair:
		return
	crosshair.pivot_offset = crosshair.size * 0.5
	var gloves_mult = cantidad_por_cosecha if cantidad_por_cosecha > 1 else 1.0
	if tier == 2: # Dorada: dorada brillante y tamaño mayor
		crosshair.color = Color(1.0, 0.84, 0.0, 1.0)
		crosshair.scale = Vector2(1.6, 1.6) * (1.0 + (gloves_mult-1)*0.15)
	elif tier == 1: # Seca: tono marrón claro / canela
		crosshair.color = Color(0.85, 0.70, 0.45, 1.0)
		crosshair.scale = Vector2(1.25, 1.25) * (1.0 + (gloves_mult-1)*0.15)
	elif tier == 0: # Común: tono paja suave
		crosshair.color = Color(0.96, 0.88, 0.70, 1.0)
		crosshair.scale = Vector2(1.1, 1.1) * (1.0 + (gloves_mult-1)*0.15)
	else: # Sin selección / mirando a vaca o entorno
		crosshair.color = Color(1.0, 1.0, 1.0, 0.8)
		crosshair.scale = Vector2(1.0, 1.0)

func try_interact():
	if raycast:
		raycast.force_raycast_update()
	actualizar_mira()

	# 1. Si la mira está seleccionando una hebra exacta del montón:
	if pajar_apuntado and is_instance_valid(pajar_apuntado) and hebra_apuntada_idx != -1:
		if pajar_apuntado.has_method("try_pick_straw"):
			var hit_pt: Vector3 = raycast.get_collision_point() if (raycast and raycast.is_colliding()) else Vector3.ZERO
			pajar_apuntado.try_pick_straw(hebra_apuntada_idx, self, hit_pt)
			actualizar_mira()
			return

	# 2. Si el raycast está colisionando con algo interactuable (vaca, colisión del montón, suelo):
	if raycast and raycast.is_colliding():
		var collider = raycast.get_collider()
		var hit_pos = raycast.get_collision_point()
		if collider and collider.has_method("hacer_clic"):
			collider.hacer_clic(self, hit_pos)
			actualizar_mira()
			return

	# 3. Si la hebra asoma fuera de la colisión física contra el cielo dentro del alcance:
	for pile in get_tree().get_nodes_in_group("pajar"):
		if pile.has_method("intentar_coger_con_mira"):
			if pile.intentar_coger_con_mira(self):
				actualizar_mira()
				return

func _physics_process(delta):
	# Reset si caida al infinito
	if global_position.y < FALL_RESET_Y:
		DebugLogger.log("Jugador caido al vacio, reseteando a spawn")
		reset_to_spawn()
		return
	
	# Gravedad corregida: solo aplicar si no esta en suelo, y resetear velocity.y cuando toca suelo
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		# Si estamos en suelo, asegurar que velocity.y no se acumule negativo
		if velocity.y < 0:
			velocity.y = 0.0
	
	# Salto
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	# Compatibilidad con ui_accept
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	# Movimiento
	var input_dir = Vector2.ZERO
	# Usar InputMap si existe, sino teclas
	if InputMap.has_action("move_left"):
		input_dir.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
		input_dir.y = Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	else:
		# Fallback teclado
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			input_dir.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			input_dir.y += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			input_dir.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			input_dir.x += 1
		input_dir = input_dir.normalized()
	
	# Direccion relativa a camara/jugador
	var direction = Vector3.ZERO
	if input_dir.length() > 0.001:
		var basis = transform.basis
		# Movimiento en plano XZ
		direction = (basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction.length() > 0.001:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		# Frenado suave
		velocity.x = move_toward(velocity.x, 0, SPEED * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0, SPEED * 8.0 * delta)
	
	move_and_slide()
	
	# Si despues de move_and_slide estamos en suelo, asegurar velocity.y 0
	if is_on_floor() and velocity.y < 0:
		velocity.y = 0

func reset_to_spawn():
	global_position = spawn_position + Vector3(0, 1.0, 0)
	velocity = Vector3.ZERO
	rotation.y = spawn_rotation_y
	if camera:
		camera.rotation.x = 0

func actualizar_ui():
	if label_paja and label_oro:
		var valor_total = 0
		for tipo in inventario_paja:
			valor_total += inventario_paja[tipo] * paja_tipos[tipo]["valor"]
		var extra: String = ""
		if has_guantes:
			extra += " 🧤x%d" % cantidad_por_cosecha
		if nivel_bolsa > 0:
			extra += " 🎒%d" % nivel_bolsa
		label_paja.text = "Paja: %d / %d%s\nValor: %d\n[C:%d S:%d D:%d]" % [
			paja_en_mano, capacidad_max, extra, valor_total,
			inventario_paja.get(0,0), inventario_paja.get(1,0), inventario_paja.get(2,0)
		]
		label_oro.text = "Oro: %d" % oro
	else:
		# Intentar re-buscar labels si no existian
		label_paja = get_node_or_null("../UI/VBoxContainer/LabelPaja")
		label_oro = get_node_or_null("../UI/VBoxContainer/LabelOro")

func agregar_paja(tipo_paja: int, cantidad: int = 1) -> bool:
	if tipo_paja not in paja_tipos:
		DebugLogger.log("ERROR: Tipo paja %d no existe" % tipo_paja)
		return false
	if paja_en_mano + cantidad > capacidad_max:
		return false
	paja_en_mano += cantidad
	inventario_paja[tipo_paja] += cantidad
	actualizar_ui()
	return true

func vender_paja_toda_a_vaca() -> int:
	var valor_total = 0
	for tipo in inventario_paja:
		if inventario_paja[tipo] > 0:
			valor_total += inventario_paja[tipo] * paja_tipos[tipo]["valor"]
			inventario_paja[tipo] = 0
	if valor_total > 0:
		oro += valor_total
		paja_en_mano = 0
		actualizar_ui()
	return valor_total

func get_spawn_position() -> Vector3:
	return spawn_position

# --- Métodos de tienda / mejoras ---
func get_cantidad_cosecha() -> int:
	return cantidad_por_cosecha

func tiene_guantes() -> bool:
	return has_guantes

func comprar_guantes():
	has_guantes = true
	cantidad_por_cosecha = 3
	if not "gloves" in mejoras_compradas:
		mejoras_compradas.append("gloves")
	DebugLogger.log("¡Guantes comprados! Ahora coges de %d en %d" % cantidad_por_cosecha)
	actualizar_ui()

func comprar_bolsa(nueva_capacidad: int):
	if nueva_capacidad > capacidad_max:
		capacidad_max = nueva_capacidad
		nivel_bolsa += 1
		if not ("bag_%d" % nueva_capacidad) in mejoras_compradas:
			mejoras_compradas.append("bag_%d" % nueva_capacidad)
		DebugLogger.log("¡Bolsa mejorada! Nueva capacidad: %d" % capacidad_max)
		actualizar_ui()

func tiene_bolsa_grande() -> bool:
	return capacidad_max >= 30
