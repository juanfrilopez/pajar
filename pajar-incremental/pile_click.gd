extends StaticBody3D
# Reenvía el clic del montón al script de la pirámide (el raycast golpea este body).

func hacer_clic(jugador, hit_pos: Vector3 = Vector3.ZERO) -> void:
	var pile = get_parent()
	if pile and pile.has_method("hacer_clic"):
		pile.hacer_clic(jugador, hit_pos)
