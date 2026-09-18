extends StaticBody3D
# Tienda / puesto de venta de herramientas y mejoras
# Reutiliza la idea de vaca.gd: caja con objeto encima, clic para comprar
# Preparado para escalar a varias bolsas y herramientas en baldas de granero

@export var item_type: String = "gloves" # "gloves" | "bag_30"
@export var item_name: String = "Guantes de Paja"
@export var cost: int = 75
@export var description: String = "Coge de 3 en 3"

@onready var malla: MeshInstance3D = get_parent() as MeshInstance3D
@onready var label_precio: Label3D = get_node_or_null("../LabelPrecio") as Label3D

var purchased_visual_hidden: bool = false

func _ready():
	collision_layer = 1
	collision_mask = 1
	add_to_group("tienda")
	_actualizar_label()

func _actualizar_label():
	if label_precio:
		if item_type == "gloves":
			label_precio.text = "%s\n%d Oro\n%s" % [item_name, cost, description]
		elif item_type == "bag_30":
			label_precio.text = "%s\n%d Oro\nCapacidad 30" % [item_name, cost]
		else:
			label_precio.text = "%s\n%d Oro" % [item_name, cost]

func hacer_clic(jugador, _hit_pos: Vector3 = Vector3.ZERO):
	if not jugador:
		return

	# Lógica de compra según tipo
	if item_type == "gloves":
		if jugador.has_method("tiene_guantes") and jugador.tiene_guantes():
			crear_texto_flotante("¡Ya tienes guantes! 🧤", Color.WHITE)
			animar_rechazo()
			return
		if jugador.oro < cost:
			crear_texto_flotante("Falta oro: %d/%d 🪙" % [jugador.oro, cost], Color(1, 0.3, 0.3))
			animar_rechazo()
			return
		# Comprar
		jugador.oro -= cost
		if jugador.has_method("comprar_guantes"):
			jugador.comprar_guantes()
		else:
			if "cantidad_por_cosecha" in jugador:
				jugador.cantidad_por_cosecha = 3
		if jugador.has_method("actualizar_ui"):
			jugador.actualizar_ui()
		crear_texto_flotante("¡Guantes comprados! 🧤 x3", Color.GREEN)
		animar_compra()
		_marcar_como_vendido()

	elif item_type == "bag_30":
		if jugador.capacidad_max >= 30:
			crear_texto_flotante("¡Ya tienes bolsa grande! 🎒", Color.WHITE)
			animar_rechazo()
			return
		if jugador.oro < cost:
			crear_texto_flotante("Falta oro: %d/%d 🪙" % [jugador.oro, cost], Color(1, 0.3, 0.3))
			animar_rechazo()
			return
		jugador.oro -= cost
		if jugador.has_method("comprar_bolsa"):
			jugador.comprar_bolsa(30)
		else:
			jugador.capacidad_max = 30
		if jugador.has_method("actualizar_ui"):
			jugador.actualizar_ui()
		crear_texto_flotante("¡Bolsa 30 comprada! 🎒", Color.GREEN)
		animar_compra()
		_marcar_como_vendido()
	else:
		crear_texto_flotante("Objeto desconocido", Color.WHITE)

func animar_compra():
	if malla:
		var tween = create_tween()
		tween.tween_property(malla, "scale", Vector3(1.15, 0.85, 1.15), 0.08)
		tween.tween_property(malla, "scale", Vector3(1.0, 1.0, 1.0), 0.18).set_trans(Tween.TRANS_BOUNCE)
	# También animar el objeto encima si existe
	var item_visual = get_node_or_null("../ItemVisual")
	if item_visual and item_visual is Node3D:
		var t2 = create_tween()
		t2.tween_property(item_visual, "scale", Vector3(1.3, 1.3, 1.3), 0.08)
		t2.tween_property(item_visual, "scale", Vector3(1.0, 1.0, 1.0), 0.18).set_trans(Tween.TRANS_BOUNCE)

func animar_rechazo():
	if malla:
		var orig = malla.position
		var tween = create_tween()
		tween.tween_property(malla, "position:x", orig.x + 0.08, 0.05)
		tween.tween_property(malla, "position:x", orig.x - 0.08, 0.05)
		tween.tween_property(malla, "position:x", orig.x, 0.05)

func _marcar_como_vendido():
	# Cambia label a VENDIDO y opcionalmente oscurece visual
	if label_precio:
		label_precio.text = "%s\n¡VENDIDO!" % item_name
		label_precio.modulate = Color(0.6, 1.0, 0.6)
	# No ocultamos el modelo para que se siga viendo la tienda,
	# pero podríamos hacerlo translúcido si se quiere.
	# Si quieres que desaparezca, descomenta:
	# var item_visual = get_node_or_null("../ItemVisual")
	# if item_visual:
	# 	item_visual.visible = false

func crear_texto_flotante(texto: String, color: Color):
	var label = Label3D.new()
	label.text = texto
	label.font_size = 64
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.position = Vector3(0, 1.5, 0)
	add_child(label)
	label.global_position = global_position + Vector3(0, 1.5, 0)
	get_tree().current_scene.add_child(label)
	label.global_position = global_position + Vector3(0, 1.5, 0)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(label, "global_position:y", label.global_position.y + 1.2, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(label.queue_free)
