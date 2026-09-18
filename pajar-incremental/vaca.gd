extends StaticBody3D

@onready var malla: MeshInstance3D = get_parent() as MeshInstance3D

func _ready():
	# Asegurar colision layer para raycast
	collision_layer = 1
	collision_mask = 1
	add_to_group("vaca")

func hacer_clic(jugador, _hit_pos: Vector3 = Vector3.ZERO):
	if jugador.paja_en_mano > 0:
		var oro_ganado = 0
		if jugador.has_method("vender_paja_toda_a_vaca"):
			oro_ganado = jugador.vender_paja_toda_a_vaca()
		else:
			oro_ganado = jugador.paja_en_mano * 1
			jugador.oro += oro_ganado
			jugador.paja_en_mano = 0
			if jugador.has_method("actualizar_ui"):
				jugador.actualizar_ui()
		
		if oro_ganado > 0:
			crear_texto_flotante("+%d Oro! 🐮" % oro_ganado, Color.GOLD)
			animar_masticar()
		else:
			crear_texto_flotante("¡Sin valor!", Color.WHITE)
	else:
		crear_texto_flotante("¡Trae paja! 🌾", Color.WHITE)

func animar_masticar():
	if malla:
		var tween = create_tween()
		tween.tween_property(malla, "scale", Vector3(1.2, 0.7, 1.2), 0.08)
		tween.tween_property(malla, "scale", Vector3(1.0, 1.0, 1.0), 0.15).set_trans(Tween.TRANS_BOUNCE)

func crear_texto_flotante(texto: String, color: Color):
	var label = Label3D.new()
	label.text = texto
	label.font_size = 64
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.position = Vector3(0, 1.5, 0)
	add_child(label)
	# Usar global para que no se mueva con vaca si se escala
	label.global_position = global_position + Vector3(0, 1.5, 0)
	get_tree().current_scene.add_child(label)
	label.global_position = global_position + Vector3(0, 1.5, 0)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(label, "global_position:y", label.global_position.y + 1.2, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(label.queue_free)
