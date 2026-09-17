extends StaticBody3D

@onready var malla: MeshInstance3D = get_parent() as MeshInstance3D

func hacer_clic(jugador):
	if jugador.paja_en_mano > 0:
		# Usar la nueva función del jugador que considera tipos de paja
		if jugador.has_method("vender_paja_toda_a_vaca"):
			var oro_ganado = jugador.vender_paja_toda_a_vaca()
			crear_texto_flotante("+" + str(oro_ganado) + " Oro! 🐮", Color.GOLD)
			animar_masticar()
		else:
			# Método viejo por compatibilidad
			var oro_ganado = jugador.paja_en_mano * 1 # 1 oro por unidad de paja
			jugador.oro += oro_ganado
			jugador.paja_en_mano = 0
			jugador.actualizar_ui()
			crear_texto_flotante("+" + str(oro_ganado) + " Oro! 🐮", Color.GOLD)
			animar_masticar()
	else:
		crear_texto_flotante("¡Trae paja!", Color.WHITE)

func animar_masticar():
	if malla:
		var tween = create_tween()
		# Simula que traga o masca encogiéndose rápido
		tween.tween_property(malla, "scale", Vector3(1.2, 0.7, 1.2), 0.08)
		tween.tween_property(malla, "scale", Vector3(1.0, 1.0, 1.0), 0.15).set_trans(Tween.TRANS_BOUNCE)

func crear_texto_flotante(texto: String, color: Color):
	var label = Label3D.new()
	label.text = texto
	label.font_size = 64
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	
	label.global_position = global_position + Vector3(0, 1.2, 0)
	get_tree().current_scene.add_child(label)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(label, "global_position:y", label.global_position.y + 1.2, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(label.queue_free)
