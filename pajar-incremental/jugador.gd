extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.003

var paja_en_mano: int = 0
var capacidad_max: int = 15
var oro: int = 0

@onready var camera: Camera3D = $Camera3D
@onready var raycast: RayCast3D = $Camera3D/RayCast3D
@onready var label_paja: Label = $"../UI/VBoxContainer/LabelPaja"
@onready var label_oro: Label = $"../UI/VBoxContainer/LabelOro"

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# Tipos de paja y sus valores
var paja_tipos: Dictionary = {
	0: {"nombre": "Común", "valor": 1},
	1: {"nombre": "Seca", "valor": 2},
	2: {"nombre": "Dorada", "valor": 5}
}

# Seguimiento de qué tipos de paja tenemos
var inventario_paja: Dictionary = {}  # tipo: cantidad

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Inicializar inventario vacío
	for tipo in paja_tipos:
		inventario_paja[tipo] = 0
	DebugLogger.log("Jugador inicializado. Tipos de paja definidos: " + str(paja_tipos))
	DebugLogger.log("Inventario inicial: " + str(inventario_paja))
	actualizar_ui()
	
	# Configuración específica para Godot 4.x CharacterBody3D
	floor_stop_on_slope = true
	floor_constant_speed = false
	floor_block_on_wall = true
	floor_max_angle = PI / 4  # 45 grados

func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if raycast.is_colliding():
			var objeto = raycast.get_collider()
			if objeto.has_method("hacer_clic"):
				objeto.hacer_clic(self) # Le pasamos el jugador al objeto interactuado

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta):
	# Aplicar gravedad solo si no está en el suelo
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W): input_dir.y -= 1
	if Input.is_key_pressed(KEY_S): input_dir.y += 1
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D): input_dir.x += 1
	input_dir = input_dir.normalized()

	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

func actualizar_ui():
	if label_paja and label_oro:
		# Calcular valor total de la paja en mano
		var valor_total_paja = 0
		for tipo in inventario_paja:
			valor_total_paja += inventario_paja[tipo] * paja_tipos[tipo]["valor"]
		
		label_paja.text = "Paja en mano: " + str(paja_en_mano) + " / " + str(capacidad_max) + \
						  "\nValor: " + str(valor_total_paja)
		label_oro.text = "Oro: " + str(oro)
		
		# Mostrar desglose de tipos de paja (opcional, puedes añadir más UI para esto)
		#print("Inventario: Común=", inventario_paja[0], 
		#      " Seca=", inventario_paja[1], 
		#      " Dorada=", inventario_paja[2])

# Añadir paja de un tipo específico
func agregar_paja(tipo_paja: int, cantidad: int = 1) -> bool:
	if tipo_paja not in paja_tipos:
		DebugLogger.log("ERROR: Tipo de paja " + str(tipo_paja) + " no existe en paja_tipos")
		return false
	
	if paja_en_mano + cantidad <= capacidad_max:
		paja_en_mano += cantidad
		inventario_paja[tipo_paja] += cantidad
		DebugLogger.log("Paja añadida: Tipo=" + str(tipo_paja) + " Cantidad=" + str(cantidad) + 
			  " Total=" + str(paja_en_mano) + "/" + str(capacidad_max) +
			  " Inventario[" + str(tipo_paja) + "]=" + str(inventario_paja[tipo_paja]))
		actualizar_ui()
		return true
	else:
		DebugLogger.log("No se puede agregar paja: capacidad llena")
		return false

# Vender toda la paja a la vaca (modificada para considerar tipos)
func vender_paja_toda_a_vaca() -> int:
	var valor_total = 0
	DebugLogger.log("=== INICIO VENTA ===")
	DebugLogger.log("Inventario antes: " + str(inventario_paja))
	DebugLogger.log("Paja en mano antes: " + str(paja_en_mano))
	DebugLogger.log("Oro antes: " + str(oro))
	
	for tipo in inventario_paja:
		if inventario_paja[tipo] > 0:
			valor_total += inventario_paja[tipo] * paja_tipos[tipo]["valor"]
			inventario_paja[tipo] = 0
	
	if valor_total > 0:
		oro += valor_total
		paja_en_mano = 0
		DebugLogger.log("Venta realizada: Valor=" + str(valor_total) + " Oro total ahora=" + str(oro))
		actualizar_ui()
		DebugLogger.log("Inventario después: " + str(inventario_paja))
		DebugLogger.log("=== FIN VENTA ===")
		return valor_total
	
	DebugLogger.log("No hay paja para vender")
	DebugLogger.log("=== FIN VENTA ===")
	return 0
