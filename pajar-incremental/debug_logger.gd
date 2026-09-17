extends Node3D

# Sistema de logging para escribir en archivo
class_name DebugLogger

const LOG_FILE = "debug_output.txt"
var log_file_path: String
var log_enabled = true

func _ready():
	# Obtener la ruta actual del proyecto
	log_file_path = "res://" + LOG_FILE
	print("Sistema de logging inicializado. Archivo: ", log_file_path)
	
	# Limpiar el archivo al inicio
	log_to_file("=== INICIO DE SESIÓN " + Time.get_datetime_string_from_system() + " ===")
	log_to_file("Sistema de logging activado")

# Función para escribir en el archivo
func log_to_file(message: String, also_print: bool = true):
	if not log_enabled:
		return
	
	# Añadir timestamp
	var timestamp = Time.get_time_string_from_system()
	var log_line = "[" + timestamp + "] " + message
	
	# Escribir en archivo en modo append para no sobrescribir
	var file = FileAccess.open(log_file_path, FileAccess.WRITE)
	if file:
		# Ir al final del archivo antes de escribir (esto simula APPEND)
		file.seek_end()
		file.store_line(log_line)
		# Asegurarse de que se escriba inmediatamente
		file.flush()
		file.close()
	else:
		# Si hay problemas, intentar crear/reabrir
		file = FileAccess.open(log_file_path, FileAccess.WRITE)
		if file:
			file.seek_end()
			file.store_line(log_line)
			file.flush()
			file.close()
	
	# También imprimir en consola si se solicita
	if also_print:
		print(log_line)

# Helper estático para fácil acceso
static func log(message: String, also_print: bool = true):
	# Intenta encontrar el logger en la escena
	var tree = Engine.get_main_loop()
	if tree is SceneTree and tree.current_scene:
		# Buscar nodos con DebugLogger
		var loggers = tree.current_scene.find_children("*", "DebugLogger", true, false)
		if loggers.size() > 0:
			loggers[0].log_to_file(message, also_print)
		else:
			# Si no hay logger, solo imprimir
			print(message)
	else:
		print(message)
