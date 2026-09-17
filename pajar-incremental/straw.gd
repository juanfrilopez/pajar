extends StaticBody3D
# Cada hebra individual de paja con colision propia

var pile: Node = null
var straw_index: int = -1
var tier: int = 0

func hacer_clic(jugador, _hit_pos: Vector3 = Vector3.ZERO) -> void:
	if pile and pile.has_method("try_pick_straw"):
		pile.try_pick_straw(straw_index, jugador)
