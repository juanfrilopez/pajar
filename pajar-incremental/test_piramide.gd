extends Node3D

# Script de prueba para verificar la pirámide de paja
@onready var jugador = $"../Jugador"
@onready var piramide = $PiramidePaja

func _ready():
	print("=== PRUEBA PIRÁMIDE DE PAJA ===")
	print("1. Jugador cargado:", "Sí" if jugador else "No")
	print("2. Pirámide cargada:", "Sí" if piramide else "No")
	print("3. Método hacer_clic en pirámide:", "Sí" if piramide.has_method("hacer_clic") else "No")
	print("4. Método agregar_paja en jugador:", "Sí" if jugador.has_method("agregar_paja") else "No")
	
	# Probaremos algunas funciones después de un breve delay
	call_deferred("probar_funcionalidades")

func probar_funcionalidades():
	print("\n=== PROBANDO FUNCIONALIDADES ===")
	
	# Simular recolección de paja
	if piramide.has_method("debug_info"):
		piramide.debug_info()
	
	print("\n=== LISTO PARA PROBAR ===")
	print("- Haz clic izquierdo en la pirámide para recolectar paja")
	print("- Lleva la paja a la vaca para venderla")
	print("- Los tipos de paja tienen diferente valor")
	print("- Paja común (amarillo): 1 oro")
	print("- Paja seca (marrón): 2 oro")
	print("- Paja dorada (dorado): 5 oro")