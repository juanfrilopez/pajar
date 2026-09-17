extends StaticBody3D

@onready var malla: MeshInstance3D = get_parent() as MeshInstance3D

func hacer_clic(jugador):
	if jugador.paja_en_mano < jugador.capacidad_max:
		jugador.paja_en_mano += 1
		jugador.actualizar_ui()
		animar_rebote()
		crear_texto_flotante("+1 Paja", Color.YELLOW)
	else:
		crear_texto_flotante("¡Mano llena!", Color.RED)

func animar_rebote():
	if malla:
		var tween = create_tween()
		tween.tween_property(malla, "scale", Vector3(1.15, 0.85, 1.15), 0.04)
		tween.tween_property(malla, "scale", Vector3(1.0, 1.0, 1.0), 0.12).set_trans(Tween.TRANS_SPRING)

func crear_texto_flotante(texto: String, color: Color):
	var label = Label3D.new()
	label.text = texto
	label.font_size = 56
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	
	var offset = Vector3(randf_range(-0.3, 0.3), 1.2, randf_range(-0.3, 0.3))
	label.global_position = global_position + offset
	
	get_tree().current_scene.add_child(label)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(label, "global_position:y", label.global_position.y + 1.0, 0.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(label.queue_free)
