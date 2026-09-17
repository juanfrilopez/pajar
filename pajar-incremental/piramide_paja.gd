extends StaticBody3D

# Configuración de la pirámide orgánica
@export var base_radius: float = 3.0  # Radio base del montón
@export var height_levels: int = 5     # Niveles de altura
@export var cell_density: float = 0.8  # Densidad de celdas

# Tipos de paja con sus valores y colores mejorados
enum StrawTier {
	TIER_1_COMMON = 0,  # Paja Común
	TIER_2_DRY = 1,     # Paja Seca  
	TIER_3_GOLDEN = 2   # Paja Dorada
}

const STRAW_TIERS = {
	StrawTier.TIER_1_COMMON: {
		"name": "Paja Común", 
		"sell_value": 1, 
		"weight": 1.0, 
		"color": Color("f0d0a0")
	},
	StrawTier.TIER_2_DRY: {
		"name": "Paja Seca", 
		"sell_value": 2, 
		"weight": 0.8, 
		"color": Color("c8a878")
	},
	StrawTier.TIER_3_GOLDEN: {
		"name": "Paja Dorada", 
		"sell_value": 5, 
		"weight": 0.5, 
		"color": Color("ffd700")
	}
}

# Estructura de datos para la pirámide
class StrawCell:
	var tier: StrawTier
	var is_empty: bool = true
	var is_exposed: bool = false
	var position: Vector3
	var rotation_offset: float
	var scale_variation: float
	
	func _init(t: int, pos: Vector3):
		tier = t
		position = pos
		if t >= 0:
			is_empty = false
			# Variaciones aleatorias para aspecto orgánico
			rotation_offset = randf_range(0.0, TAU)
			scale_variation = randf_range(0.8, 1.2)
	
	func get_sell_value() -> int:
		return STRAW_TIERS[tier]["sell_value"]
	
	func get_color() -> Color:
		return STRAW_TIERS[tier]["color"]
	
	func get_tier_name() -> String:
		return STRAW_TIERS[tier]["name"]

@onready var malla: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var selection_area: Area3D = $SelectionArea

var pyramid_cells: Array = []  # Array de StrawCell
var exposed_cells: Array = []  # Índices de celdas expuestas
var current_total: int = 0

# Called when the node enters the scene tree for the first time.
func _ready():
	DebugLogger.log("Inicializando pirámide de paja de forma orgánica")
	initialize_organic_pyramid()
	regenerate_mesh()
	update_exposed_cells()
	setup_selection_area()

# Inicializa la pirámide con forma orgánica (cónica/dome)
func initialize_organic_pyramid():
	pyramid_cells.clear()
	exposed_cells.clear()
	current_total = 0
	
	# Radio se reduce con la altura para forma cónica
	for level in range(height_levels):
		var level_radius = base_radius * (1.0 - float(level) / height_levels)
		var level_height = float(level) * 0.6  # Espaciado vertical
		
		# Número de celdas en este nivel (circunferencia)
		var cells_in_level = int(PI * level_radius * level_radius * cell_density)
		cells_in_level = max(cells_in_level, 3)  # Mínimo 3 celdas
		
		for i in range(cells_in_level):
			# Distribución circular con algo de aleatoriedad
			var angle = float(i) / cells_in_level * TAU * 2.0 + randf_range(-0.2, 0.2)
			var radius_variation = randf_range(0.7, 1.3)
			var effective_radius = level_radius * radius_variation
			
			# Posición en círculo con algo de ruido para aspecto orgánico
			var x = sin(angle) * effective_radius + randf_range(-0.1, 0.1)
			var z = cos(angle) * effective_radius + randf_range(-0.1, 0.1)
			var y = level_height + randf_range(-0.05, 0.05)
			
			# Determinar tier basado en altura (mayor altura = mejor tier)
			var tier_ratio = float(level) / height_levels
			var tier = determine_tier_by_ratio(tier_ratio)
			
			# Crear celda
			var cell = StrawCell.new(tier, Vector3(x, y, z))
			pyramid_cells.append(cell)
			current_total += 1
	
	DebugLogger.log("Pirámide orgánica creada con " + str(current_total) + " briznas de paja")

# Determina el tier basado en la posición en la altura
func determine_tier_by_ratio(ratio: float) -> StrawTier:
	# Usar distribución no lineal para crear más paja común en la base
	if ratio < 0.4:
		return StrawTier.TIER_1_COMMON
	elif ratio < 0.75:
		return StrawTier.TIER_2_DRY
	else:
		return StrawTier.TIER_3_GOLDEN# Actualiza qué celdas están expuestas para recolección
func update_exposed_cells():
	exposed_cells.clear()
	
	# En la pirámide orgánica, todas las celdas no vacías en la superficie están expuestas
	for i in range(pyramid_cells.size()):
		var cell = pyramid_cells[i]
		if not cell.is_empty:
			cell.is_exposed = true
			exposed_cells.append(i)
	
	DebugLogger.log("Celdas expuestas actualizadas: " + str(exposed_cells.size()))

# Regenera la malla basada en los datos actuales (sin Z-fighting)
func regenerate_mesh():
	var mesh_arrays = []
	mesh_arrays.resize(Mesh.ARRAY_MAX)
	
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var colors = PackedColorArray()
	var indices = PackedInt32Array()
	
	# Crear cada brizna de paja como un pequeño cilindro/rectángulo delgado
	for i in range(pyramid_cells.size()):
		var cell = pyramid_cells[i]
		
		if cell.is_empty:
			continue
		
		# Crear una pequeña "brizna" de paja
		add_straw_strand(vertices, normals, colors, indices, 
						cell.position, cell.rotation_offset, 
						cell.scale_variation, cell.get_color())
	
	if vertices.size() == 0:
		# Crear una brizna de prueba si no hay nada
		add_straw_strand(vertices, normals, colors, indices,
						Vector3(0, 0.5, 0), 0.0, 1.0, Color.YELLOW)
	
	# Configurar arrays
	mesh_arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh_arrays[Mesh.ARRAY_NORMAL] = normals
	mesh_arrays[Mesh.ARRAY_COLOR] = colors
	mesh_arrays[Mesh.ARRAY_INDEX] = indices
	
	# Crear malla
	var mesh_obj = ArrayMesh.new()
	mesh_obj.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
	
	# Crear material con propiedades específicas por tier
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.metallic = 0.0
	material.roughness = 0.7
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_BACK
	
	# Aplicar malla y material
	if malla:
		malla.mesh = mesh_obj
		malla.material_override = material
	
	# Actualizar área de colisión para mejor selección
	update_collision_shape()# Añade una brizna individual de paja (cilindro delgado)
func add_straw_strand(vertices: PackedVector3Array, normals: PackedVector3Array,
					 colors: PackedColorArray, indices: PackedInt32Array,
					 position: Vector3, rotation: float, scale_var: float, color: Color):
	
	var strand_height = 0.5 * scale_var
	var strand_radius = 0.05 * scale_var
	var segments = 6  # Baja resolución para aspecto orgánico
	
	var base_index = vertices.size()
	
	# Crear vértices para el cilindro
	for i in range(segments + 1):
		var angle = float(i) / segments * TAU + rotation
		var x = cos(angle) * strand_radius
		var z = sin(angle) * strand_radius
		
		# Vértice inferior
		vertices.append(position + Vector3(x, 0, z))
		normals.append(Vector3(x, 0, z).normalized())
		colors.append(color.lightened(0.1))  # Más claro en la base
		
		# Vértice superior
		vertices.append(position + Vector3(x, strand_height, z))
		normals.append(Vector3(x, 0, z).normalized())
		colors.append(color.darkened(0.1))  # Más oscuro en la punta
	
	# Crear índices para el cilindro
	for i in range(segments):
		var idx_base = base_index + i * 2
		
		# Lados del cilindro
		indices.append(idx_base)      # Vértice inferior i
		indices.append(idx_base + 1)  # Vértice superior i
		indices.append(idx_base + 2)  # Vértice inferior i+1
		
		indices.append(idx_base + 2)  # Vértice inferior i+1
		indices.append(idx_base + 1)  # Vértice superior i
		indices.append(idx_base + 3)  # Vértice superior i+1
	
	# Tapas superior e inferior
	var center_bottom = base_index + (segments + 1) * 2
	var center_top = center_bottom + 1
	
	vertices.append(position)  # Centro inferior
	normals.append(Vector3.DOWN)
	colors.append(color.lightened(0.2))
	
	vertices.append(position + Vector3(0, strand_height, 0))  # Centro superior
	normals.append(Vector3.UP)
	colors.append(color.darkened(0.2))
	
	# Tapa inferior
	for i in range(segments):
		indices.append(center_bottom)
		indices.append(base_index + (i * 2))
		indices.append(base_index + (((i + 1) % segments) * 2))
	
	# Tapa superior
	for i in range(segments):
		indices.append(center_top)
		indices.append(base_index + (i * 2) + 1)
		indices.append(base_index + (((i + 1) % segments) * 2) + 1)

# Actualiza la forma de colisión para selección más fácil
func update_collision_shape():
	# Usar una forma convexa simple que cubra toda la pirámide
	if collision:
		var shape = ConvexPolygonShape3D.new()
		var points = PackedVector3Array()
		
		# Crear puntos aproximados que cubran la pirámide
		points.append(Vector3(-base_radius, 0, -base_radius))
		points.append(Vector3(base_radius, 0, -base_radius))
		points.append(Vector3(-base_radius, 0, base_radius))
		points.append(Vector3(base_radius, 0, base_radius))
		points.append(Vector3(0, height_levels * 0.6, 0))  # Punta superior
		
		shape.points = points
		collision.shape = shape

# Configura el área de selección para mejor detección de clics
func setup_selection_area():
	# Verificar si ya existe el área de selección
	if has_node("SelectionArea"):
		selection_area = $SelectionArea
		DebugLogger.log("Área de selección encontrada con radio: " + str($SelectionArea/CollisionShape3D.shape.radius))
		return
	
	DebugLogger.log("Configurando área de selección desde código")
	
	# Crear una esfera grande alrededor de la pirámide
	var area = Area3D.new()
	area.name = "SelectionArea"
	area.collision_layer = 2
	area.collision_mask = 2
	add_child(area)
	area.owner = get_tree().get_edited_scene_root() if Engine.is_editor_hint() else self
	
	var col_shape = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = base_radius + 1.0
	col_shape.shape = shape
	area.add_child(col_shape)
	
	# Conectar señales de entrada para mejor detección
	area.input_event.connect(_on_selection_area_input_event)
	area.mouse_entered.connect(_on_selection_area_mouse_entered)
	area.mouse_exited.connect(_on_selection_area_mouse_exited)
	
	DebugLogger.log("Área de selección creada con radio: " + str(shape.radius))

# Señales del área de selección
func _on_selection_area_input_event(camera: Camera3D, event: InputEvent, position: Vector3, normal: Vector3, shape_idx: int):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Buscar jugador en la escena
		var jugador = get_tree().get_first_node_in_group("jugador")
		if jugador:
			hacer_clic(jugador)

func _on_selection_area_mouse_entered():
	# Podrías añadir highlight aquí
	pass

func _on_selection_area_mouse_exited():
	# Quitar highlight
	pass# Animación cuando se recolecta paja
func animar_recoleccion():
	if malla:
		var tween = create_tween()
		tween.tween_property(malla, "scale", Vector3(1.1, 0.9, 1.1), 0.05)
		tween.tween_property(malla, "scale", Vector3(1.0, 1.0, 1.0), 0.15).set_trans(Tween.TRANS_BOUNCE)

# Crear texto flotante
func crear_texto_flotante(texto: String, color: Color):
	var label = Label3D.new()
	label.text = texto
	label.font_size = 48
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	
	var offset = Vector3(randf_range(-0.3, 0.3), 1.5, randf_range(-0.3, 0.3))
	label.global_position = global_position + offset
	
	get_tree().current_scene.add_child(label)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(label, "global_position:y", label.global_position.y + 1.2, 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.7)
	tween.chain().tween_callback(label.queue_free)

# Regenera la pirámide completa cuando está vacía
func regenerate_full_pyramid():
	initialize_organic_pyramid()
	regenerate_mesh()
	update_exposed_cells()
	DebugLogger.log("Pirámide regenerada con " + str(current_total) + " briznas de paja")

# Método llamado cuando el jugador hace clic en la pirámide
func hacer_clic(jugador):
	DebugLogger.log("=== PIRÁMIDE: CLIC ===")
	DebugLogger.log("Paja en mano del jugador: " + str(jugador.paja_en_mano) + "/" + str(jugador.capacidad_max))
	
	# Asegurarnos de que el jugador tiene espacio para más paja
	if jugador.paja_en_mano >= jugador.capacidad_max:
		crear_texto_flotante("¡Mano llena!", Color.RED)
		DebugLogger.log("MANO LLENA: No se puede agregar más paja")
		return
	
	if exposed_cells.size() > 0:
		# Seleccionar una celda expuesta aleatoria para simular clic en cualquier parte
		var random_index = randi() % exposed_cells.size()
		var cell_index = exposed_cells[random_index]
		var cell = pyramid_cells[cell_index]
		
		DebugLogger.log("Brizna seleccionada: Tier=" + str(cell.tier) + " Nombre=" + cell.get_tier_name() + " Valor=" + str(cell.get_sell_value()))
		
		# Intentar agregar paja
		var tipo_paja = cell.tier
		DebugLogger.log("Intentando agregar paja tipo: " + str(tipo_paja))
		
		var agregado_exitoso = false
		if jugador.has_method("agregar_paja"):
			agregado_exitoso = jugador.agregar_paja(tipo_paja, 1)
		else:
			# Método alternativo si el jugador no tiene el método específico
			if jugador.paja_en_mano < jugador.capacidad_max:
				jugador.paja_en_mano += 1
				agregado_exitoso = true
				if jugador.has_method("actualizar_ui"):
					jugador.actualizar_ui()
		
		if agregado_exitoso:
			# Marcar como vacía
			cell.is_empty = true
			cell.is_exposed = false
			
			# Remover de las celdas expuestas
			exposed_cells.remove_at(random_index)
			
			# Actualizar malla
			regenerate_mesh()
			update_exposed_cells()
			
			# Animación de recolección
			animar_recoleccion()
			crear_texto_flotante("+1 " + cell.get_tier_name(), cell.get_color())
			
			DebugLogger.log("Paja recolectada exitosamente")
			
			# Si la pirámide está completamente vacía, regenerarla
			if exposed_cells.size() == 0 and current_total > 0:
				regenerate_full_pyramid()
		else:
			DebugLogger.log("FALLÓ al agregar paja")
			crear_texto_flotante("¡Mano llena!", Color.RED)
	else:
		DebugLogger.log("NO HAY briznas expuestas")
		crear_texto_flotante("¡Sin paja disponible!", Color.WHITE)
	
	DebugLogger.log("=== FIN CLIC PIRÁMIDE ===")

# Para depuración: muestra información de la pirámide
func debug_info():
	DebugLogger.log("=== Pirámide Debug ===")
	DebugLogger.log("Total de briznas: " + str(current_total))
	DebugLogger.log("Briznas expuestas: " + str(exposed_cells.size()))
	
	# Contar por tier
	var tier_counts = [0, 0, 0]
	for cell in pyramid_cells:
		if not cell.is_empty:
			tier_counts[cell.tier] += 1
	
	DebugLogger.log("Comunes: " + str(tier_counts[0]) + " Secas: " + str(tier_counts[1]) + " Doradas: " + str(tier_counts[2]))
