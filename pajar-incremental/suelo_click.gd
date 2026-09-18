extends StaticBody3D
# El suelo alrededor del montón también es clickeable.
#
# Problema que resuelve: la hitbox del montón (ConvexPolygonShape3D) sólo
# cubre hasta base_radius, pero la falda de hebras sueltas se apoya en el
# suelo hasta base_radius*SKIRT_OUTER (~8.85 m) y las hebras de la parte
# baja de la ladera asoman media longitud más allá del borde del montón.
# Antes, al apuntar a esa paja el raycast golpeaba el suelo (sin hacer_clic)
# y no pasaba nada: parecía que "se salía de la hitbox".
#
# Este script reenvía al montón los clics que caen dentro de su zona de
# recogida; el montón ya se encarga de coger la hebra más cercana al impacto.
# No añade física nueva (el suelo ya era sólido) ni roba clics a la vaca:
# el raycast golpea el cuerpo de la vaca antes que el suelo.

func hacer_clic(jugador, hit_pos: Vector3 = Vector3.ZERO) -> void:
	if hit_pos == Vector3.ZERO:
		return
	for pile in get_tree().get_nodes_in_group("pajar"):
		if pile.has_method("punto_dentro_de_zona") and pile.punto_dentro_de_zona(hit_pos):
			if pile.has_method("hacer_clic"):
				pile.hacer_clic(jugador, hit_pos)
			return
