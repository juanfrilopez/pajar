extends Node3D
class_name DebugLogger

const LOG_FILE = "user://debug_output.txt"
var log_enabled: bool = false # Desactivado por defecto para no spamear

func _ready():
	if log_enabled:
		# Limpiar archivo al inicio
		var file = FileAccess.open(LOG_FILE, FileAccess.WRITE)
		if file:
			file.store_line("=== INICIO SESION " + Time.get_datetime_string_from_system() + " ===")
			file.close()
		print("DebugLogger iniciado: ", LOG_FILE)

func log_to_file(message: String, also_print: bool = true):
	if not log_enabled:
		if also_print:
			print(message)
		return
	var timestamp = Time.get_time_string_from_system()
	var log_line = "[" + timestamp + "] " + message
	# Append real
	var file = FileAccess.open(LOG_FILE, FileAccess.READ_WRITE)
	if file:
		file.seek_end()
		file.store_line(log_line)
		file.close()
	else:
		# crear si no existe
		file = FileAccess.open(LOG_FILE, FileAccess.WRITE)
		if file:
			file.store_line(log_line)
			file.close()
	if also_print:
		print(log_line)

static func log(message: String, also_print: bool = true):
	var tree = Engine.get_main_loop()
	if tree is SceneTree and tree.current_scene:
		var loggers = tree.current_scene.find_children("*", "DebugLogger", true, false)
		if loggers.size() > 0:
			loggers[0].log_to_file(message, also_print)
			return
	print(message)
