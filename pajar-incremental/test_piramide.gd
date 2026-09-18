extends Node3D
# Script de prueba para verificar la piramide de paja

@onready var jugador = get_node_or_null("../Jugador")
@onready var piramide = $PiramidePaja

func _ready():
	print("=== PRUEBA PIRAMIDE DE PAJA ===")
	print("Jugador cargado: ", "Sí" if jugador else "No")
	print("Piramide cargada: ", "Sí" if piramide else "No")
	print("Metodo hacer_clic en piramide: ", "Sí" if piramide and piramide.has_method("hacer_clic") else "No")
	print("Metodo agregar_paja en jugador: ", "Sí" if jugador and jugador.has_method("agregar_paja") else "No")
	call_deferred("probar_funcionalidades")

func probar_funcionalidades():
	print("\n=== PROBANDO FUNCIONALIDADES ===")
	if piramide and piramide.has_method("debug_info"):
		piramide.debug_info()
	print("\n=== LISTO PARA PROBAR ===")
	print("- Haz clic izquierdo en una hebra para recolectar paja")
	print("- Cada hebra es individual y se ve el agujero")
	print("- Lleva la paja a la vaca para venderla")
	print("- Paja comun (claro): 1 oro")
	print("- Paja seca (marron): 2 oro")
	print("- Paja dorada (dorado): 5 oro")
