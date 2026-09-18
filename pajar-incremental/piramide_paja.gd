extends Node3D
# v5 - Montón de paja MACIZO: núcleo opaco + costra densa de hebras.
#
# Problema de la v4: las hebras se repartían por el VOLUMEN del montón
# (unos 231 m³) y 18.000 hebras finas sólo rellenaban el ~1.5% de ese
# volumen, así que se veía el cielo / el otro lado a través de la paja.
#
# La v5 cambia el enfoque: la paja no "rellena" un volumen, forma una
# COSTRA sobre un NÚCLEO MACIZO.
#   1) NÚCLEO OPACO (ArrayMesh generado por código): el mismo sólido de
#      revolución del perfil, con relieve de ruido y una textura de briznas
#      procedimental. Es OPACO: aunque el jugador arranque hebras, nunca se
#      ve "a través" del montón, sólo paja más compacta y en sombra.
#   2) TODAS las hebras viven en una capa de ~10 cm alrededor de la
#      superficie y van TANGENTES a ella (como paja tumbada sobre el montón),
#      en vez de flotar por el interior donde no se ven. A ~240 hebras/m² la
#      cobertura del núcleo pasa de ~2% a ~99%: los huecos que quedan son de
#      sombra, no de "se ve el fondo".
#   3) FALDA de hebras sueltas alrededor de la base para que no se vea la
#      costura entre el montón y el suelo. La falda y las hebras bajas de la
#      ladera quedan FUERA de la hitbox del montón, así que el suelo dentro
#      de la zona de recogida también es clickeable: suelo_click.gd reenvía
#      esos clics a punto_dentro_de_zona() / hacer_clic() de este script.
#
# Geometría del montón (sin cambios): perfil r(f) = base_radius*(1-f)^0.8,
# cóncavo => sólido CONVEXO => un único ConvexPolygonShape3D para caminar y
# recoger. Pendiente base ~29° (el jugador soporta 45°): se sube andando.
#
# MUY IMPORTANTE (regresión ya sufrida): la transform de cada hebra se
# construye escalando las COLUMNAS de la base (escala en el marco LOCAL del
# cilindro). NO usar Basis.scaled() para esto: en Godot scaled() multiplica
# las FILAS (escala en el marco del PADRE), lo que aplasta el alcance
# horizontal de la hebra al grosor y deja "agujas" casi VERTICALES.
# Véase _straw_transform() y _verify_straws_are_flat().

@export var total_straws: int = 50000
@export var base_radius: float = 7.5
@export var pile_height: float = 3.4
@export var auto_regenerate: bool = true
@export var regenerate_delay: float = 2.0
@export var use_seed: bool = true
@export var pile_seed: int = 1900
@export var core_enabled: bool = true   # núcleo opaco: si se apaga, vuelven los huecos

const MOUND_EXP: float = 0.8            # Perfil: r(f) = R * (1 - f)^MOUND_EXP

# --- Capa superficial de hebras ---
const SKIRT_RATIO: float = 0.07         # Fracción de hebras sueltas en el suelo (falda)
const SKIRT_OUTER: float = 1.18         # Hasta dónde llega la falda (× base_radius)
const SHELL_OUT: float = 0.04           # Cuánto sobresale la hebra de la superficie
const SHELL_IN: float = 0.06            # Cuánto se hunde hacia el núcleo
const STRAW_TILT_DEG: float = 12.0      # Desorden: salida del plano tangente (grados)
const STRAW_FLATTEN: float = 0.88       # 1 = pegada al perfil, <1 = más tumbada
const STRAW_LEN_MIN: float = 0.50
const STRAW_LEN_MAX: float = 1.15
const STRAW_THICK_MIN: float = 0.009    # Radio de la hebra (m) -> Ø 1.8-3.0 cm
const STRAW_THICK_MAX: float = 0.015

# --- Núcleo macizo opaco ---
const CORE_INSET: float = 0.05          # El núcleo queda 5 cm por debajo de la superficie
const CORE_SEGS: int = 96               # Segmentos alrededor del montón
const CORE_RINGS: int = 40              # Anillos de la base a la punta
const CORE_NOISE_AMP: float = 0.05      # Relieve del núcleo (m)
const CORE_NOISE_FADE: float = 0.10     # El relieve se apaga en la base y en la punta

# --- Textura procedural de briznas del núcleo ---
const TEX_SIZE: int = 256
const TEX_U_REPEAT: float = 4.0         # Vueltas de la textura alrededor del montón
const TEX_V_REPEAT: float = 3.0         # Vueltas de la base a la punta
const TEX_FIBERS: int = 2600            # Briznas dibujadas encima de la textura

# --- Varios ---
const SURFACE_CDF_STEPS: int = 128      # Muestreo por área de la superficie
const MOUND_RINGS: int = 15             # Muestras del perfil para la colisión
const MOUND_SEGS: int = 20              # Muestras radiales para la colisión
const SETTLE_RADIUS: float = 0.45       # Radio del "asentamiento" al recoger
const SETTLE_DEPTH: float = 0.02        # Cuánto se hunde la paja vecina (m)
const ZONA_EXTRA: float = 0.3           # Margen extra de la zona clickeable del suelo

# --- Zona clickeable del suelo alrededor de la base ---
# La hitbox del montón (ConvexPolygonShape3D) sólo cubre hasta base_radius,
# pero la falda de hebras sueltas llega hasta base_radius*SKIRT_OUTER y las
# hebras de la base de la ladera asoman media longitud más allá del borde.
# Esos clics morían en el suelo sin recoger nada. Para arreglarlo, el suelo
# (suelo_click.gd) nos reenvía los clics que caen dentro de esta zona y aquí
# se recoge la hebra más cercana al impacto, igual que en la ladera.
func punto_dentro_de_zona(world_pos: Vector3) -> bool:
	var local: Vector3 = to_local(world_pos)
	if local.y < -0.6 or local.y > 0.6:
		return false
	var r_horizontal: float = Vector2(local.x, local.z).length()
	return r_horizontal <= base_radius * SKIRT_OUTER + STRAW_LEN_MAX * 0.5 + ZONA_EXTRA

enum StrawTier {
	TIER_1_COMMON = 0,
	TIER_2_DRY = 1,
	TIER_3_GOLDEN = 2
}

const STRAW_TIERS: Dictionary = {
	StrawTier.TIER_1_COMMON: {
		"name": "Paja Común",
		"sell_value": 1,
		"color": Color(0.94, 0.82, 0.62),
	},
	StrawTier.TIER_2_DRY: {
		"name": "Paja Seca",
		"sell_value": 2,
		"color": Color(0.78, 0.66, 0.47),
	},
	StrawTier.TIER_3_GOLDEN: {
		"name": "Paja Dorada",
		"sell_value": 5,
		"color": Color(1.0, 0.84, 0.0),
	},
}

# Paleta del núcleo (más oscura que las hebras: lo que se ve entre hebra y
# hebra debe leerse como SOMBRA de paja compacta, no como un hueco).
const CORE_DARK: Color = Color(0.34, 0.27, 0.16)
const CORE_MID: Color = Color(0.52, 0.42, 0.26)
const CORE_LIGHT: Color = Color(0.72, 0.61, 0.40)

class StrawData:
	var index: int
	var tier: int
	var mm_index: int = -1
	var position: Vector3
	var axis_dir: Vector3  # Dirección del eje de la hebra (≈ tangente a la superficie)
	var length: float
	var half_length: float
	var thickness: float
	var depth: float       # <0 = fuera de la superficie, >CORE_INSET = enterrada en el núcleo
	var color: Color
	var is_removed: bool = false
	var q0: Vector3        # Extremo inicial del segmento cilíndrico
	var q1: Vector3        # Extremo final del segmento cilíndrico
	var last_query_id: int = 0

	func _init(idx: int, t: int, pos: Vector3, axis: Vector3, len_m: float, thick: float, dep: float, col: Color):
		index = idx
		tier = t
		position = pos
		axis_dir = axis
		length = len_m
		half_length = len_m * 0.5
		thickness = thick
		depth = dep
		color = col
		update_endpoints()

	func update_endpoints() -> void:
		half_length = length * 0.5
		q0 = position - axis_dir * half_length
		q1 = position + axis_dir * half_length

# --- Particionamiento espacial para búsqueda precisa de hebras ---
const GRID_CELL_SIZE: float = 1.5
const GRID_MIN: float = -10.5
const GRID_MAX: float = 10.5
const GRID_CELLS: int = 14

var _spatial_grid: Array = []
var _query_id: int = 0

func _init_grid() -> void:
	_spatial_grid.clear()
	_spatial_grid.resize(GRID_CELLS * GRID_CELLS)
	for i in range(_spatial_grid.size()):
		_spatial_grid[i] = []

func _get_cell_coord(val: float) -> int:
	return clampi(int(floor((val - GRID_MIN) / GRID_CELL_SIZE)), 0, GRID_CELLS - 1)

func _insert_straw_in_grid(s: StrawData) -> void:
	var min_x: float = minf(s.q0.x, s.q1.x) - s.thickness
	var max_x: float = maxf(s.q0.x, s.q1.x) + s.thickness
	var min_z: float = minf(s.q0.z, s.q1.z) - s.thickness
	var max_z: float = maxf(s.q0.z, s.q1.z) + s.thickness

	var min_cx: int = _get_cell_coord(min_x)
	var max_cx: int = _get_cell_coord(max_x)
	var min_cz: int = _get_cell_coord(min_z)
	var max_cz: int = _get_cell_coord(max_z)

	for cz in range(min_cz, max_cz + 1):
		var row: int = cz * GRID_CELLS
		for cx in range(min_cx, max_cx + 1):
			_spatial_grid[row + cx].append(s.index)

var straws: Array[StrawData] = []
var straws_container: Node3D
var core_instance: MeshInstance3D
var pile_collision_body: StaticBody3D
var is_regenerating: bool = false

var _mmis: Array[MultiMeshInstance3D] = []
var _mms: Array[MultiMesh] = []
var _straw_mesh: CylinderMesh
var _pickup_mesh: CylinderMesh
var _tier_mats: Array[StandardMaterial3D] = []
var _core_mat: StandardMaterial3D
var _core_mesh: ArrayMesh
var _core_tex: ImageTexture
var _core_key: String = ""
var _cdf: PackedFloat32Array = PackedFloat32Array()

const _pile_click_script = preload("res://pile_click.gd")

func _ready():
	# suelo_click.gd nos busca por grupo para reenviarnos los clics del suelo
	add_to_group("pajar")

	if has_node("Straws"):
		straws_container = $Straws
	else:
		straws_container = Node3D.new()
		straws_container.name = "Straws"
		add_child(straws_container)

	if has_node("MoundCore"):
		core_instance = $MoundCore
	else:
		core_instance = MeshInstance3D.new()
		core_instance.name = "MoundCore"
		add_child(core_instance)

	_ensure_shared_resources()
	_ensure_core()
	_ensure_multimeshes()
	_ensure_pile_collision()
	generate_pile()
	DebugLogger.log("Monton de paja v5 inicializado: núcleo macizo + %d hebras en la superficie" % total_straws)

func _ensure_shared_resources():
	if _straw_mesh == null:
		_straw_mesh = CylinderMesh.new()
		_straw_mesh.top_radius = 1.0
		_straw_mesh.bottom_radius = 1.0
		_straw_mesh.height = 1.0
		_straw_mesh.radial_segments = 6
		_straw_mesh.rings = 1
		# Sin tapas: las hebras se ven por el lateral, así que las tapas (12 de
		# los 24 triángulos) no aportan nada y cuestan la mitad del dibujado.
		# Con culling activado el tubo abierto se ve exactamente igual.
		# Se usa Object.set() y no asignación directa porque cap_top/cap_bottom
		# no existen en todas las versiones de Godot 4: set() es un "no-op"
		# silencioso si la propiedad no existe, mientras que asignar a secas
		# reventaría el script en las versiones antiguas.
		_straw_mesh.set("cap_top", false)
		_straw_mesh.set("cap_bottom", false)
	if _pickup_mesh == null:
		_pickup_mesh = _straw_mesh
	if _core_mat == null:
		_core_mat = StandardMaterial3D.new()
		_core_mat.vertex_color_use_as_albedo = true
		_core_mat.roughness = 0.93
		_core_mat.metallic = 0.0
		_core_mat.cull_mode = BaseMaterial3D.CULL_BACK
		_core_mat.albedo_texture = _get_core_texture()
	if _tier_mats.size() == 3:
		return
	_tier_mats.clear()
	for tier in range(3):
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.88
		mat.metallic = 0.0
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		if tier == StrawTier.TIER_3_GOLDEN:
			mat.emission_enabled = true
			mat.emission = Color(0.35, 0.24, 0.0)
			mat.emission_energy_multiplier = 0.22
		_tier_mats.append(mat)

func _ensure_multimeshes():
	if _mmis.size() == 3:
		return
	_mmis.clear()
	_mms.clear()
	for tier in range(3):
		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mmi.name = "StrawsMM_%d" % tier
		mmi.material_override = _tier_mats[tier]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		straws_container.add_child(mmi)
		_mmis.append(mmi)
		_mms.append(null)

func _ensure_core() -> void:
	if core_instance == null:
		return
	core_instance.material_override = _core_mat
	core_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	core_instance.visible = core_enabled
	var key: String = "%.3f_%.3f_%d" % [base_radius, pile_height, pile_seed]
	if _core_mesh == null or key != _core_key:
		_core_mesh = _build_core_mesh()
		_core_key = key
	core_instance.mesh = _core_mesh

func _ensure_pile_collision():
	if has_node("PileCollision"):
		pile_collision_body = $PileCollision
	else:
		pile_collision_body = StaticBody3D.new()
		pile_collision_body.name = "PileCollision"
		add_child(pile_collision_body)
	pile_collision_body.collision_layer = 1
	pile_collision_body.collision_mask = 1
	if pile_collision_body.get_script() != _pile_click_script:
		pile_collision_body.set_script(_pile_click_script)

# ---------- Geometria del montón ----------

# Radio del perfil a una fracción f de la altura (0 = base, 1 = punta)
func profile_radius(f: float) -> float:
	var t: float = clampf(1.0 - f, 0.0, 1.0)
	return base_radius * pow(t, MOUND_EXP)

func profile_radius_at_y(y: float) -> float:
	if pile_height <= 0.001:
		return base_radius
	return profile_radius(y / pile_height)

# dr/df del perfil (negativo: al subir el montón se estrecha)
func _dr_df(f: float) -> float:
	return -MOUND_EXP * base_radius * pow(maxf(1.0 - f, 1e-4), MOUND_EXP - 1.0)

# ds/df: longitud de arco del perfil (para muestrear por área)
func _ds_df(f: float) -> float:
	var d: float = _dr_df(f)
	return sqrt(d * d + pile_height * pile_height)

# Normal exterior de la superficie en (f, theta).
# En el plano (radial, vertical) la tangente al perfil es (dr/df, H), así que
# la normal es (H, -dr/df): radial = H, vertical = -dr/df.
func _surface_normal(f: float, theta: float) -> Vector3:
	var v: Vector3 = Vector3(cos(theta) * pile_height, -_dr_df(f), sin(theta) * pile_height)
	if v.length_squared() < 1e-8:
		return Vector3.UP
	return v.normalized()

# Punto sobre la superficie del montón
func _surface_point(f: float, theta: float) -> Vector3:
	var r: float = profile_radius(f)
	return Vector3(cos(theta) * r, f * pile_height, sin(theta) * r)

# ---------- Ruido procedural (suma de senos encajada en la malla) ----------
#
# Se usan frecuencias ENTERAS en u (0..1 = una vuelta al montón) para que el
# patrón sea continuo en la costura theta=0 y, en el caso de la textura, que
# además embalde sin costura al repetirla.

# Bultos grandes del núcleo (longitudes de onda ~0.8-3 m)
static func _lump_noise(u: float, v: float) -> float:
	var s: float = 0.0
	s += 0.50 * sin(TAU * (5.0 * u + 3.0 * v) + 0.4)
	s += 0.30 * sin(TAU * (8.0 * u + 5.0 * v) + 2.3)
	s += 0.22 * sin(TAU * (11.0 * u - 4.0 * v) + 4.1)
	s += 0.15 * sin(TAU * (16.0 * u + 7.0 * v) + 1.7)
	s += 0.10 * sin(TAU * (19.0 * u + 9.0 * v) + 5.2)
	return clampf(s * 0.79, -1.0, 1.0)

# Veteado fino de la textura: rasgos ~1 m de ancho por ~8 cm de alto, es
# decir, briznas tumbadas en horizontal.
static func _streak_noise(u: float, v: float) -> float:
	var s: float = 0.0
	s += 0.45 * sin(TAU * (7.0 * u + 23.0 * v) + 0.7)
	s += 0.28 * sin(TAU * (13.0 * u + 41.0 * v) + 2.1)
	s += 0.18 * sin(TAU * (21.0 * u + 61.0 * v) + 4.3)
	s += 0.14 * sin(TAU * (29.0 * u + 17.0 * v) + 1.2)
	s += 0.12 * sin(TAU * (11.0 * u - 31.0 * v) + 5.6)
	return clampf(s * 0.75, -1.0, 1.0)

# ---------- Núcleo opaco ----------

func _core_vertex_color(lump: float, f: float) -> Color:
	var t: float = clampf(lump * 0.5 + 0.5, 0.0, 1.0)
	var bright: float = 0.72 + 0.38 * t
	bright *= 0.86 + 0.24 * clampf(f, 0.0, 1.0)   # base en sombra, punta más seca
	return Color(bright, bright * 0.985, bright * 0.96)

# Sólido de revolución del perfil, hundido CORE_INSET, con relieve y color.
# El mallado va de la base (f=0) a la punta (f=1); el último anillo colapsa
# en el vértice superior, así que no hay triángulos degenerados intermedios.
func _build_core_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols: int = CORE_SEGS + 1
	var rows: int = CORE_RINGS + 1
	for k in range(rows):
		var f: float = float(k) / float(CORE_RINGS)
		var r: float = profile_radius(f)
		var fade: float = clampf(f / CORE_NOISE_FADE, 0.0, 1.0) * clampf((1.0 - f) / 0.12, 0.0, 1.0)
		for s in range(cols):
			var theta: float = TAU * float(s) / float(CORE_SEGS)
			var lump: float = 0.0
			var p: Vector3
			if k == CORE_RINGS:
				# La punta colapsa en un ÚNICO punto: si cada columna pusiera su
				# propio vértice (el radio es 0 pero la normal radial no lo es
				# del todo) salían 96 triángulos minúsculos con la normal
				# invertida asomando por la punta.
				p = Vector3(0.0, pile_height - CORE_INSET, 0.0)
			else:
				var n: Vector3 = _surface_normal(f, theta)
				lump = _lump_noise(float(s) / float(CORE_SEGS) * 3.0, f)
				p = _surface_point(f, theta) - n * (CORE_INSET - lump * CORE_NOISE_AMP * fade)
			if p.y < -0.04:
				p.y = -0.04
			st.set_uv(Vector2(float(s) / float(CORE_SEGS) * TEX_U_REPEAT, f * TEX_V_REPEAT))
			st.set_color(_core_vertex_color(lump, f))
			st.add_vertex(p)
	# Winding (a, c, b) + (b, c, d): deja las normales mirando hacia fuera
	# (comprobado con el producto vectorial de las dos tangentes del perfil).
	for k in range(CORE_RINGS):
		for s in range(CORE_SEGS):
			var a: int = k * cols + s
			var b: int = k * cols + (s + 1)
			var c: int = (k + 1) * cols + s
			var d: int = (k + 1) * cols + (s + 1)
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)
	st.generate_normals()
	return st.commit()

func _get_core_texture() -> ImageTexture:
	if _core_tex != null:
		return _core_tex
	# Sin mipmaps al crear: primero se rellena el nivel 0 y luego se generan,
	# si no los niveles pequeños se quedan con lo que hubiera en memoria.
	var img: Image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(TEX_SIZE):
		var v: float = float(y) / float(TEX_SIZE)
		for x in range(TEX_SIZE):
			var u: float = float(x) / float(TEX_SIZE)
			var t: float = clampf(_streak_noise(u, v) * 0.5 + 0.5, 0.0, 1.0)
			var c: Color
			if t < 0.5:
				c = CORE_DARK.lerp(CORE_MID, t * 2.0)
			else:
				c = CORE_MID.lerp(CORE_LIGHT, (t - 0.5) * 2.0)
			img.set_pixel(x, y, c)
	# Briznas: trazos cortos casi horizontales, con wrap-around para que la
	# textura siga embaldosando sin costura.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = pile_seed * 7919 + 13
	for i in range(TEX_FIBERS):
		var ang: float = rng.randf_range(-PI * 0.18, PI * 0.18)
		var length: int = rng.randi_range(10, 34)
		var bright: float = rng.randf_range(0.70, 1.30)
		var c2: Color = Color(0.62 * bright, 0.50 * bright, 0.30 * bright)
		_draw_fiber(img, rng.randi_range(0, TEX_SIZE - 1), rng.randi_range(0, TEX_SIZE - 1),
				cos(ang), sin(ang), length, c2)
	img.generate_mipmaps()
	_core_tex = ImageTexture.create_from_image(img)
	return _core_tex

func _draw_fiber(img: Image, x0: int, y0: int, dx: float, dy: float, steps: int, c: Color) -> void:
	var darker: Color = c * 0.9
	var fx: float = float(x0)
	var fy: float = float(y0)
	for i in range(steps):
		var px: int = posmod(int(floor(fx)), TEX_SIZE)
		var py: int = posmod(int(floor(fy)), TEX_SIZE)
		img.set_pixel(px, py, c)
		img.set_pixel(px, posmod(py + 1, TEX_SIZE), darker)
		fx += dx
		fy += dy

# ---------- Muestreo de la superficie ----------

# Tabla de probabilidad acumulada para repartir las hebras por ÁREA: cada
# franja de altura recibe hebras proporcionalmente a 2*pi*r*ds/df.
func _build_area_cdf() -> void:
	_cdf = PackedFloat32Array()
	_cdf.resize(SURFACE_CDF_STEPS + 1)
	var acc: float = 0.0
	_cdf[0] = 0.0
	for k in range(SURFACE_CDF_STEPS):
		var f: float = (float(k) + 0.5) / float(SURFACE_CDF_STEPS)
		acc += profile_radius(f) * _ds_df(f)
		_cdf[k + 1] = acc
	if acc > 1e-9:
		for k in range(SURFACE_CDF_STEPS + 1):
			_cdf[k] = _cdf[k] / acc

func _sample_surface_f() -> float:
	if _cdf.size() < 2:
		return randf()
	var u: float = randf()
	var lo: int = 0
	var hi: int = SURFACE_CDF_STEPS
	while lo < hi:
		var mid: int = (lo + hi) / 2
		if _cdf[mid] < u:
			lo = mid + 1
		else:
			hi = mid
	var k: int = maxi(lo - 1, 0)
	var span: float = _cdf[k + 1] - _cdf[k]
	var t: float = 0.5
	if span > 1e-9:
		t = clampf((u - _cdf[k]) / span, 0.0, 1.0)
	return (float(k) + t) / float(SURFACE_CDF_STEPS)

# Hebra sobre la costra del montón: posición hundida/sobresalida respecto a
# la superficie y eje TANGENTE a ella (más un poco de desorden).
func _place_shell_straw() -> Array:
	var f: float = _sample_surface_f()
	var theta: float = randf() * TAU
	var n: Vector3 = _surface_normal(f, theta)
	var depth: float = randf_range(-SHELL_OUT, SHELL_IN)
	var pos: Vector3 = _surface_point(f, theta) - n * depth
	if pos.y < 0.012:
		pos.y = 0.012  # en la base la paja se apoya en el suelo, no se hunde

	# Base tangente: t_up = subiendo por el perfil, t_az = rodeando el montón
	var t_up: Vector3 = Vector3(cos(theta) * _dr_df(f), pile_height, sin(theta) * _dr_df(f))
	if t_up.length_squared() > 1e-8:
		t_up = t_up.normalized()
	else:
		t_up = Vector3(-sin(theta), 0.0, cos(theta))
	var t_az: Vector3 = Vector3(-sin(theta), 0.0, cos(theta))

	var phi: float = randf() * TAU
	var dir: Vector3 = t_up * cos(phi) + t_az * sin(phi)
	var psi: float = deg_to_rad(randf_range(-STRAW_TILT_DEG, STRAW_TILT_DEG))
	var axis: Vector3 = dir * cos(psi) + n * sin(psi)
	axis.y *= STRAW_FLATTEN
	if axis.length_squared() < 1e-8:
		axis = t_az
	axis = axis.normalized()
	return [pos, axis, depth, f]

# Hebra suelta en el suelo alrededor de la base (falda): tapa la costura
# entre el montón y el suelo y hace que el montón no parezca un cono de
# plastilina plantado en el césped.
func _place_skirt_straw() -> Array:
	var theta: float = randf() * TAU
	var rr: float = base_radius * (1.0 + (SKIRT_OUTER - 1.0) * pow(randf(), 1.6))
	var pos: Vector3 = Vector3(cos(theta) * rr, randf_range(0.008, 0.045), sin(theta) * rr)
	var axis: Vector3 = Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, randf() * TAU)
	axis = axis.rotated(Vector3.RIGHT, deg_to_rad(randf_range(-8.0, 8.0))).normalized()
	return [pos, axis, -1.0, 0.0]

# ---------- Colisión ----------

func _build_mound_points() -> PackedVector3Array:
	var pts: PackedVector3Array = PackedVector3Array()
	pts.append(Vector3(0, 0, 0))
	for k in range(MOUND_RINGS):
		var f: float = float(k) / float(MOUND_RINGS)
		var rr: float = profile_radius(f)
		var y: float = f * pile_height
		for s in range(MOUND_SEGS):
			var a: float = TAU * float(s) / float(MOUND_SEGS)
			pts.append(Vector3(cos(a) * rr, y, sin(a) * rr))
	pts.append(Vector3(0, pile_height, 0))  # punta: sitio de la aguja futura
	return pts

func _sync_pile_collision() -> void:
	if pile_collision_body == null:
		return
	var shape_node: CollisionShape3D = null
	for child in pile_collision_body.get_children():
		if child is CollisionShape3D:
			shape_node = child
			break
	if shape_node == null:
		shape_node = CollisionShape3D.new()
		pile_collision_body.add_child(shape_node)
	shape_node.position = Vector3.ZERO
	var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	shape.points = _build_mound_points()
	shape_node.shape = shape

# ---------- Generacion ----------

func clear_pile():
	straws.clear()
	for c in range(_spatial_grid.size()):
		_spatial_grid[c].clear()
	for mm in _mms:
		if mm:
			mm.instance_count = 0

func generate_pile():
	if is_regenerating:
		return
	clear_pile()
	if use_seed:
		seed(pile_seed)

	_ensure_core()
	_build_area_cdf()
	_init_grid()

	straws = []
	var buckets: Array = [[], [], []]

	for i in range(total_straws):
		var placed: Array
		if randf() < SKIRT_RATIO:
			placed = _place_skirt_straw()
		else:
			placed = _place_shell_straw()

		var pos: Vector3 = placed[0]
		var axis: Vector3 = placed[1]
		var depth: float = placed[2]
		var f: float = placed[3]

		var tier: int = determine_tier_by_height(clampf(f, 0.0, 1.0))
		var thickness: float = randf_range(STRAW_THICK_MIN, STRAW_THICK_MAX)
		var length: float = randf_range(STRAW_LEN_MIN, STRAW_LEN_MAX)

		var base_color: Color = STRAW_TIERS[tier]["color"]
		var varied: Color = Color(
			clampf(base_color.r * randf_range(0.88, 1.10), 0.0, 1.0),
			clampf(base_color.g * randf_range(0.88, 1.10), 0.0, 1.0),
			clampf(base_color.b * randf_range(0.88, 1.12), 0.0, 1.0)
		)
		var data: StrawData = StrawData.new(i, tier, pos, axis, length, thickness, depth, varied)
		straws.append(data)
		buckets[tier].append(data)
		_insert_straw_in_grid(data)

	_fill_multimeshes(buckets)
	_sync_pile_collision()
	DebugLogger.log("Montón v5 generado: %d hebras (%s) sobre núcleo macizo (R=%.1f m, H=%.1f m)" % [
		straws.size(), _coverage_report(), base_radius, pile_height])

# Cobertura estimada del núcleo: con N hebras de área proyectada L*Ø sobre una
# superficie A, la fracción tapada es 1 - exp(-N*L*Ø/A) (solapamiento de Poisson).
func _coverage_report() -> String:
	var area: float = 0.0
	for k in range(64):
		var f: float = (float(k) + 0.5) / 64.0
		area += TAU * profile_radius(f) * _ds_df(f) / 64.0
	if area <= 0.0:
		return "cobertura n/d"
	var covered: float = 0.0
	for s in straws:
		# sólo cuenta la paja que asoma por encima de la superficie del núcleo
		if s.depth < CORE_INSET:
			covered += s.length * s.thickness * 2.0
	var k: float = covered / area
	var pct: float = (1.0 - exp(-k)) * 100.0
	return "cobertura del núcleo ~%.1f%%, %.0f hebras/m²" % [pct, float(straws.size()) / area]

func _fill_multimeshes(buckets: Array) -> void:
	for tier in range(3):
		var list: Array = buckets[tier]
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _straw_mesh
		mm.instance_count = maxi(list.size(), 1)
		if list.is_empty():
			mm.set_instance_transform(0, Transform3D(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3(0, -50, 0)))
			mm.set_instance_color(0, Color(1, 1, 1, 0))
		else:
			for j in range(list.size()):
				var s: StrawData = list[j]
				s.mm_index = j
				mm.set_instance_transform(j, _straw_transform(s))
				mm.set_instance_color(j, s.color)
		_mms[tier] = mm
		_mmis[tier].multimesh = mm
	_verify_straws_are_flat()

# Anti-regresión: lee las transforms YA SUBIDAS al MultiMesh y comprueba que
# el eje del cilindro está tumbado (tangente a la superficie del montón, que
# como mucho sube 29°). Si alguna semántica de Godot cambia y las hebras
# vuelven a salir verticales ("agujas"), esto avisa por el log en vez de
# quedarse en un bug silencioso (ya nos pasó con Basis.scaled()).
func _verify_straws_are_flat() -> void:
	var checked: int = 0
	var bad: int = 0
	var max_deg: float = 0.0
	for tier in range(3):
		var mm: MultiMesh = _mms[tier]
		if mm == null or mm.instance_count == 0:
			continue
		var samples: int = mini(mm.instance_count, 96)
		for j in range(samples):
			var t: Transform3D = mm.get_instance_transform(j)
			# `basis.y` es la COLUMNA 1 de la matriz (equivalente a `basis * Vector3.UP`).
			# OJO: `Basis.get_column()` existe solo en C++, NO está expuesto a GDScript.
			var axis_y: Vector3 = t.basis.y
			var len_sq: float = axis_y.length_squared()
			if len_sq < 1e-10:
				continue  # instancia oculta
			var axis: Vector3 = axis_y / sqrt(len_sq)
			# OJO: en Godot no existe `asinf()`, la función es `asin()` (sin sufijo f).
			var ang: float = rad_to_deg(asin(clampf(absf(axis.y), 0.0, 1.0)))
			max_deg = maxf(max_deg, ang)
			checked += 1
			if ang > 45.0:
				bad += 1
	if checked == 0:
		return
	if bad > 0:
		DebugLogger.log("AVISO REGRESIÓN: %d/%d hebras muestreadas salen inclinadas >45° (máx %.0f°); revisa _straw_transform()" % [bad, checked, max_deg])
	else:
		DebugLogger.log("OK: %d hebras muestreadas van tumbadas sobre el montón (inclinación máx %.1f°)" % [checked, max_deg])

# Transform de una hebra para el MultiMesh.
#
# El cilindro base crece sobre +Y, así que la COLUMNA Y de la base debe ser
# `axis_dir * length` (la hebra tumbada), y las columnas X/Z el grosor.
# Se escala en el marco LOCAL construyendo las columnas a mano:
# columna i = (base_rot * e_i) * escala_i.
#
# OJO: NO usar `basis.scaled(Vector3(th, len, th))` aquí. En Godot,
# Basis.scaled() multiplica las FILAS por el vector de escala, es decir,
# aplica la escala en el marco del PADRE. Con eso el eje largo de la hebra
# queda apuntando casi al +Y del mundo y la hebra se ve VERTICAL (además de
# encogerse). Este fue el bug que hacía que las pajas se vieran de pie.
func _straw_transform(data: StrawData) -> Transform3D:
	var rot: Basis = _straw_basis(data.axis_dir)
	# En GDScript, `basis.x/.y/.z` SON las columnas de la matriz (x = columna 0,
	# y = columna 1, z = columna 2), es decir, a dónde va cada eje local.
	# Equivalente a `rot * Vector3(1,0,0)` etc. NO usar `rot.get_column(i)`:
	# ese método es solo de C++ y no existe en GDScript (error de parseo).
	var col_x: Vector3 = rot.x * data.thickness
	var col_y: Vector3 = rot.y * data.length
	var col_z: Vector3 = rot.z * data.thickness
	return Transform3D(col_x, col_y, col_z, data.position)

# Base ortogonal cuyo eje Y apunta a la dirección del eje de la hebra.
# Construida con Basis(axis, angle) (constructor eje-ángulo) en vez de
# set_columns(), que no está expuesto en todas las versiones. La rotación
# lleva +Y exactamente a `axis`, así que el cilindro queda alineado con la
# dirección de la hebra.
func _straw_basis(axis: Vector3) -> Basis:
	var d: float = clampf(Vector3.UP.dot(axis), -1.0, 1.0)
	if d > 0.999999:
		return Basis()  # axis == +Y: sin rotación
	if d < -0.999999:
		return Basis(Vector3.RIGHT, PI)  # axis == -Y: media vuelta sobre X
	var rot_axis: Vector3 = Vector3.UP.cross(axis).normalized()
	return Basis(rot_axis, acos(d))

func _hide_instance(data: StrawData) -> void:
	if data.mm_index < 0:
		return
	var mm: MultiMesh = _mms[data.tier]
	if mm == null:
		return
	mm.set_instance_transform(data.mm_index, Transform3D(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3(0, -80, 0)))

func _sync_instance(data: StrawData) -> void:
	if data.is_removed or data.mm_index < 0:
		return
	var mm: MultiMesh = _mms[data.tier]
	if mm == null:
		return
	mm.set_instance_transform(data.mm_index, _straw_transform(data))

func determine_tier_by_height(ratio: float) -> int:
	if ratio < 0.45:
		return StrawTier.TIER_1_COMMON if randf() < 0.85 else StrawTier.TIER_2_DRY
	elif ratio < 0.78:
		var r: float = randf()
		if r < 0.4:
			return StrawTier.TIER_1_COMMON
		elif r < 0.85:
			return StrawTier.TIER_2_DRY
		else:
			return StrawTier.TIER_3_GOLDEN
	else:
		var r2: float = randf()
		if r2 < 0.2:
			return StrawTier.TIER_1_COMMON
		elif r2 < 0.55:
			return StrawTier.TIER_2_DRY
		else:
			return StrawTier.TIER_3_GOLDEN

# ---------- Recolección y Selección con Mira ----------

# Distancia mínima 3D entre un rayo (O + D*s, s en [0, s_max]) y el segmento de la hebra (C + A*t, t en [-half_len, half_len]).
# D y A son vectores unitarios.
# Devuelve [dist, s, t]:
#   dist: distancia euclídea entre la línea de visión y el eje de la hebra
#   s: distancia a lo largo del rayo desde la cámara (profundidad visual)
#   t: posición a lo largo de la hebra [-half_len, half_len]
func _ray_straw_closest(O: Vector3, D: Vector3, C: Vector3, A: Vector3, half_len: float, s_max: float) -> Array:
	var w0: Vector3 = O - C
	var b: float = D.dot(A)
	var d: float = D.dot(w0)
	var e: float = A.dot(w0)
	var denom: float = 1.0 - b * b
	var s: float = 0.0
	var t: float = 0.0
	if denom < 1e-6:
		t = clampf(e, -half_len, half_len)
		s = clampf(t * b - d, 0.0, s_max)
		t = clampf(e + s * b, -half_len, half_len)
	else:
		var s_raw: float = (b * e - d) / denom
		var t_raw: float = (e - b * d) / denom
		t = clampf(t_raw, -half_len, half_len)
		s = clampf(t * b - d, 0.0, s_max)
		t = clampf(e + s * b, -half_len, half_len)
	var P: Vector3 = O + D * s
	var Q: Vector3 = C + A * t
	var dist: float = P.distance_to(Q)
	return [dist, s, t]

func _collect_candidate_straws(local_cam_pos: Vector3, local_cam_dir: Vector3, local_hit: Vector3, max_reach: float) -> Array[StrawData]:
	_query_id += 1
	var candidates: Array[StrawData] = []
	if _spatial_grid.is_empty():
		return candidates

	if local_hit != Vector3.ZERO:
		var search_rad: float = 1.8
		var min_cx: int = _get_cell_coord(local_hit.x - search_rad)
		var max_cx: int = _get_cell_coord(local_hit.x + search_rad)
		var min_cz: int = _get_cell_coord(local_hit.z - search_rad)
		var max_cz: int = _get_cell_coord(local_hit.z + search_rad)
		for cz in range(min_cz, max_cz + 1):
			var row: int = cz * GRID_CELLS
			for cx in range(min_cx, max_cx + 1):
				var cell: Array = _spatial_grid[row + cx]
				for idx in cell:
					var s: StrawData = straws[idx]
					if s.last_query_id != _query_id:
						s.last_query_id = _query_id
						if not s.is_removed:
							candidates.append(s)
	else:
		var step_size: float = 1.0
		var num_steps: int = maxi(1, int(ceil(max_reach / step_size)))
		for step in range(num_steps + 1):
			var t: float = minf(float(step) * step_size, max_reach)
			var pt: Vector3 = local_cam_pos + local_cam_dir * t
			if pt.x * pt.x + pt.z * pt.z > 120.0:
				continue
			var cx_center: int = _get_cell_coord(pt.x)
			var cz_center: int = _get_cell_coord(pt.z)
			var min_cx: int = maxi(0, cx_center - 1)
			var max_cx: int = mini(GRID_CELLS - 1, cx_center + 1)
			var min_cz: int = maxi(0, cz_center - 1)
			var max_cz: int = mini(GRID_CELLS - 1, cz_center + 1)
			for cz in range(min_cz, max_cz + 1):
				var row: int = cz * GRID_CELLS
				for cx in range(min_cx, max_cx + 1):
					var cell: Array = _spatial_grid[row + cx]
					for idx in cell:
						var s: StrawData = straws[idx]
						if s.last_query_id != _query_id:
							s.last_query_id = _query_id
							if not s.is_removed:
								candidates.append(s)
	return candidates

func _find_closest_straw_to_point(candidates: Array[StrawData], local_pos: Vector3) -> int:
	var best_idx: int = -1
	var best_dist: float = 1e9
	for s in candidates:
		if s.depth > CORE_INSET + 0.02:
			continue
		var seg_v: Vector3 = s.q1 - s.q0
		var seg_len_sq: float = seg_v.length_squared()
		var d: float = 0.0
		if seg_len_sq < 1e-8:
			d = local_pos.distance_to(s.position)
		else:
			var t: float = clampf((local_pos - s.q0).dot(seg_v) / seg_len_sq, 0.0, 1.0)
			var proj: Vector3 = s.q0 + seg_v * t
			d = local_pos.distance_to(proj)
		if d < best_dist:
			best_dist = d
			best_idx = s.index
	return best_idx

# Encuentra la hebra exacta apuntada por la mira de la cámara.
# Devuelve el índice en straws[], o -1 si no hay ninguna.
func find_straw_under_crosshair(cam_origin: Vector3, cam_dir: Vector3, hit_pos: Vector3 = Vector3.ZERO, max_reach: float = 5.5) -> int:
	var local_cam_pos: Vector3 = to_local(cam_origin)
	var local_cam_dir: Vector3 = (to_local(cam_origin + cam_dir) - local_cam_pos).normalized()
	var local_hit: Vector3 = Vector3.ZERO
	if hit_pos != Vector3.ZERO:
		local_hit = to_local(hit_pos)
		var hit_reach: float = local_cam_pos.distance_to(local_hit) + 0.6
		if hit_reach < max_reach:
			max_reach = hit_reach

	var candidates: Array[StrawData] = _collect_candidate_straws(local_cam_pos, local_cam_dir, local_hit, max_reach)
	if candidates.is_empty():
		return -1

	var best_direct_idx: int = -1
	var best_direct_cam_dist: float = 1e9
	var best_direct_ray_dist: float = 1e9

	var best_assist_idx: int = -1
	var best_assist_score: float = 1e9

	const DIRECT_TOLERANCE: float = 0.003 # 3 mm de margen sobre el radio cilíndrico
	const MAX_ASSIST_DIST: float = 0.08   # 8 cm para asistencia si la mira pasa muy cerca
	const MAX_BURIED_DEPTH: float = CORE_INSET + 0.015

	for s in candidates:
		if s.depth > MAX_BURIED_DEPTH:
			continue

		var res: Array = _ray_straw_closest(local_cam_pos, local_cam_dir, s.position, s.axis_dir, s.half_length, max_reach)
		var ray_dist: float = res[0]
		var cam_dist: float = res[1]

		if cam_dist >= max_reach:
			continue

		var hit_radius: float = s.thickness + DIRECT_TOLERANCE
		if ray_dist <= hit_radius:
			# Hebra directamente atravesada por la línea de visión:
			# Priorizar la que está en primer término (menor cam_dist).
			# Si dos hebras están prácticamente a la misma distancia (dentro de 2 cm),
			# la que esté más centrada respecto al retículo gana.
			if cam_dist < best_direct_cam_dist - 0.02:
				best_direct_cam_dist = cam_dist
				best_direct_ray_dist = ray_dist
				best_direct_idx = s.index
			elif absf(cam_dist - best_direct_cam_dist) <= 0.02:
				if ray_dist < best_direct_ray_dist:
					best_direct_cam_dist = cam_dist
					best_direct_ray_dist = ray_dist
					best_direct_idx = s.index
		elif best_direct_idx == -1 and ray_dist <= MAX_ASSIST_DIST:
			var assist_score: float = ray_dist * 10.0 + cam_dist * 0.1
			if assist_score < best_assist_score:
				best_assist_score = assist_score
				best_assist_idx = s.index

	if best_direct_idx != -1:
		return best_direct_idx
	if best_assist_idx != -1:
		return best_assist_idx

	if local_hit != Vector3.ZERO:
		return _find_closest_straw_to_point(candidates, local_hit)

	return -1

# Devuelve [straw_index, tier] para la hebra seleccionada por la mira, o [-1, -1]
func obtener_hebra_bajo_mira(cam_origin: Vector3, cam_dir: Vector3, hit_pos: Vector3 = Vector3.ZERO, max_reach: float = 5.5) -> Array:
	var idx: int = find_straw_under_crosshair(cam_origin, cam_dir, hit_pos, max_reach)
	if idx >= 0 and idx < straws.size():
		var s: StrawData = straws[idx]
		if not s.is_removed:
			return [idx, s.tier]
	return [-1, -1]

# ---------- Sistema de cosecha mejorada (guantes) ----------
func _get_cosecha_cantidad(jugador) -> int:
	if jugador and jugador.has_method("get_cantidad_cosecha"):
		return jugador.get_cantidad_cosecha()
	if jugador and "cantidad_por_cosecha" in jugador:
		return jugador.cantidad_por_cosecha
	return 1

# Coge varias hebras alrededor de un punto local. Devuelve cuántas se cogieron.
func try_pick_multiple_around(jugador, center_local: Vector3, cantidad: int) -> int:
	if cantidad <= 0:
		return 0
	if jugador.paja_en_mano >= jugador.capacidad_max:
		crear_texto_flotante("¡Mano llena!", Color.RED, to_global(center_local))
		return 0

	# Recoger candidatos cerca del centro
	var candidates: Array[StrawData] = []
	var search_rad: float = 1.2 + (cantidad - 1) * 0.25
	if _spatial_grid.is_empty():
		candidates = straws.duplicate()
	else:
		_query_id += 1
		var min_cx: int = _get_cell_coord(center_local.x - search_rad)
		var max_cx: int = _get_cell_coord(center_local.x + search_rad)
		var min_cz: int = _get_cell_coord(center_local.z - search_rad)
		var max_cz: int = _get_cell_coord(center_local.z + search_rad)
		for cz in range(min_cz, max_cz + 1):
			var row: int = cz * GRID_CELLS
			if row < 0 or row >= GRID_CELLS * GRID_CELLS:
				continue
			for cx in range(min_cx, max_cx + 1):
				if cx < 0 or cx >= GRID_CELLS:
					continue
				var cell_idx: int = row + cx
				if cell_idx < 0 or cell_idx >= _spatial_grid.size():
					continue
				var cell: Array = _spatial_grid[cell_idx]
				for idx in cell:
					var s: StrawData = straws[idx]
					if s.last_query_id != _query_id:
						s.last_query_id = _query_id
						if not s.is_removed:
							candidates.append(s)
		if candidates.is_empty():
			for s in straws:
				if not s.is_removed:
					candidates.append(s)

	# Ordenar por cercanía al centro
	candidates.sort_custom(func(a, b): return a.position.distance_squared_to(center_local) < b.position.distance_squared_to(center_local))

	var picked: int = 0
	var picked_tiers: Dictionary = {}
	var last_world_pos: Vector3 = to_global(center_local)

	for s in candidates:
		if picked >= cantidad:
			break
		if s.is_removed:
			continue
		if s.depth > CORE_INSET + 0.02:
			continue
		if jugador.paja_en_mano >= jugador.capacidad_max:
			break
		var agregado: bool = false
		if jugador.has_method("agregar_paja"):
			agregado = jugador.agregar_paja(s.tier, 1)
		else:
			if jugador.paja_en_mano < jugador.capacidad_max:
				jugador.paja_en_mano += 1
				agregado = true
				if jugador.has_method("actualizar_ui"):
					jugador.actualizar_ui()
		if not agregado:
			break
		s.is_removed = true
		_hide_instance(s)
		animar_recoleccion_hebra(s)
		picked += 1
		last_world_pos = to_global(s.position)
		picked_tiers[s.tier] = picked_tiers.get(s.tier, 0) + 1

	if picked > 0:
		if picked_tiers.size() == 1:
			var tier: int = picked_tiers.keys()[0]
			var tier_info: Dictionary = STRAW_TIERS[tier]
			if picked == 1:
				crear_texto_flotante("+1 %s" % tier_info["name"], tier_info["color"], last_world_pos)
			else:
				crear_texto_flotante("+%d %s 🧤" % [picked, tier_info["name"]], tier_info["color"], last_world_pos)
		else:
			crear_texto_flotante("+%d Paja 🧤" % picked, Color(0.6, 1.0, 0.6), last_world_pos)

		var remaining: int = get_remaining_count()
		if remaining == 0 and auto_regenerate:
			if not is_regenerating:
				is_regenerating = true
				await get_tree().create_timer(regenerate_delay).timeout
				is_regenerating = false
				generate_pile()
				crear_texto_flotante("¡Montón renovado!", Color.GREEN)
		elif remaining > 0:
			_apply_settle_effect(center_local)
	else:
		if jugador.paja_en_mano >= jugador.capacidad_max:
			crear_texto_flotante("¡Mano llena!", Color.RED, to_global(center_local))
	return picked

func _try_pick_single(index: int, jugador, _hit_pos: Vector3 = Vector3.ZERO) -> int:
	if index < 0 or index >= straws.size():
		return 0
	var data: StrawData = straws[index]
	if data.is_removed:
		return 0
	return try_pick_multiple_around(jugador, data.position, 1)

# Clic directo con la mira cuando no hay colisión física (por ejemplo, en la silueta)
func intentar_coger_con_mira(jugador) -> bool:
	if not jugador or not is_instance_valid(jugador):
		return false
	var cam = jugador.camera if "camera" in jugador else null
	if not cam or not is_instance_valid(cam):
		return false
	var cam_pos: Vector3 = cam.global_position
	var cam_dir: Vector3 = -cam.global_transform.basis.z.normalized()
	var idx: int = find_straw_under_crosshair(cam_pos, cam_dir, Vector3.ZERO, 5.5)
	if idx >= 0 and idx < straws.size():
		var cantidad: int = _get_cosecha_cantidad(jugador)
		if cantidad <= 1:
			_try_pick_single(idx, jugador)
		else:
			var center: Vector3 = straws[idx].position
			try_pick_multiple_around(jugador, center, cantidad)
		return true
	return false

func try_pick_straw(index: int, jugador, hit_pos: Vector3 = Vector3.ZERO):
	if index < 0 or index >= straws.size():
		return
	var cantidad: int = _get_cosecha_cantidad(jugador)
	if cantidad <= 1:
		_try_pick_single(index, jugador, hit_pos)
		return
	# Con guantes: coger varias alrededor del punto
	var center_local: Vector3
	if hit_pos != Vector3.ZERO:
		center_local = to_local(hit_pos)
	else:
		center_local = straws[index].position
	try_pick_multiple_around(jugador, center_local, cantidad)

func get_remaining_count() -> int:
	var c: int = 0
	for s in straws:
		if not s.is_removed:
			c += 1
	return c

# Al arrancar una hebra, la paja de alrededor se hunde un poco (se compacta).
# Se hunde siguiendo la NORMAL de la superficie, no en vertical, para que la
# costra no se descuelgue del núcleo.
func _apply_settle_effect(removed_pos: Vector3) -> void:
	var candidates: Array[StrawData] = []
	if not _spatial_grid.is_empty():
		var min_cx: int = _get_cell_coord(removed_pos.x - SETTLE_RADIUS)
		var max_cx: int = _get_cell_coord(removed_pos.x + SETTLE_RADIUS)
		var min_cz: int = _get_cell_coord(removed_pos.z - SETTLE_RADIUS)
		var max_cz: int = _get_cell_coord(removed_pos.z + SETTLE_RADIUS)
		_query_id += 1
		for cz in range(min_cz, max_cz + 1):
			var row: int = cz * GRID_CELLS
			for cx in range(min_cx, max_cx + 1):
				var cell: Array = _spatial_grid[row + cx]
				for idx in cell:
					var s: StrawData = straws[idx]
					if s.last_query_id != _query_id:
						s.last_query_id = _query_id
						if not s.is_removed:
							candidates.append(s)
	else:
		candidates = straws

	for s in candidates:
		if s.is_removed:
			continue
		var dist: float = s.position.distance_to(removed_pos)
		if dist >= SETTLE_RADIUS:
			continue
		var k: float = 1.0 - dist / SETTLE_RADIUS
		var f: float = clampf(s.position.y / pile_height, 0.0, 1.0)
		var n: Vector3 = _surface_normal(f, atan2(s.position.z, s.position.x))
		var sink: float = k * k * SETTLE_DEPTH
		s.position -= n * sink
		if s.position.y < 0.005:
			s.position.y = 0.005
		s.depth += sink
		s.update_endpoints()
		_sync_instance(s)

func animar_recoleccion_hebra(data: StrawData):
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = _pickup_mesh
	node.material_override = _tier_mats[data.tier]
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.transform = _straw_transform(data)
	straws_container.add_child(node)
	var tween: Tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "position:y", node.position.y + 0.45, 0.15)
	tween.tween_property(node, "scale", Vector3(0.08, 0.08, 0.08), 0.2).set_delay(0.05)
	tween.chain().tween_callback(node.queue_free)

func hacer_clic(jugador, hit_pos: Vector3 = Vector3.ZERO):
	var cam = jugador.camera if (jugador and "camera" in jugador) else null
	if cam and is_instance_valid(cam):
		var cam_pos: Vector3 = cam.global_position
		var cam_dir: Vector3 = -cam.global_transform.basis.z.normalized()
		var picked_idx: int = find_straw_under_crosshair(cam_pos, cam_dir, hit_pos, 5.5)
		if picked_idx != -1:
			try_pick_straw(picked_idx, jugador, hit_pos)
			return

	if hit_pos != Vector3.ZERO:
		var closest_idx: int = find_closest_straw(hit_pos)
		if closest_idx != -1:
			try_pick_straw(closest_idx, jugador, hit_pos)
			return
	var candidates: Array = get_exposed_straws()
	if candidates.size() > 0:
		var rnd: int = candidates[randi() % candidates.size()]
		try_pick_straw(rnd, jugador, hit_pos)
	else:
		crear_texto_flotante("¡Sin paja!", Color.WHITE)

func find_closest_straw(world_pos: Vector3) -> int:
	var local_pos: Vector3 = to_local(world_pos)
	if not _spatial_grid.is_empty():
		var min_cx: int = _get_cell_coord(local_pos.x - 2.0)
		var max_cx: int = _get_cell_coord(local_pos.x + 2.0)
		var min_cz: int = _get_cell_coord(local_pos.z - 2.0)
		var max_cz: int = _get_cell_coord(local_pos.z + 2.0)
		_query_id += 1
		var candidates: Array[StrawData] = []
		for cz in range(min_cz, max_cz + 1):
			var row: int = cz * GRID_CELLS
			for cx in range(min_cx, max_cx + 1):
				var cell: Array = _spatial_grid[row + cx]
				for idx in cell:
					var s: StrawData = straws[idx]
					if s.last_query_id != _query_id:
						s.last_query_id = _query_id
						if not s.is_removed:
							candidates.append(s)
		if not candidates.is_empty():
			return _find_closest_straw_to_point(candidates, local_pos)

	var best_idx: int = -1
	var best_score: float = 1e9
	for i in range(straws.size()):
		var s: StrawData = straws[i]
		if s.is_removed:
			continue
		var d: float = s.position.distance_to(local_pos)
		var score: float = d + maxf(0.0, s.depth - CORE_INSET) * 0.75
		if score < best_score:
			best_score = score
			best_idx = i
	return best_idx

# Hebras "expuestas": las que asoman por encima de la superficie del núcleo.
func get_exposed_straws() -> Array:
	var exposed: Array = []
	for i in range(straws.size()):
		var s: StrawData = straws[i]
		if s.is_removed:
			continue
		if s.depth < CORE_INSET + 0.02:
			exposed.append(i)
	if exposed.size() < 10:
		exposed.clear()
		for i in range(straws.size()):
			if not straws[i].is_removed:
				exposed.append(i)
	return exposed

func crear_texto_flotante(texto: String, color: Color, world_pos: Vector3 = Vector3.ZERO):
	var label: Label3D = Label3D.new()
	label.text = texto
	label.font_size = 48
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.no_depth_test = false
	if world_pos != Vector3.ZERO:
		label.global_position = world_pos + Vector3(0, 0.35, 0)
	else:
		label.global_position = global_position + Vector3(randf_range(-0.5, 0.5), pile_height + 1.0 + randf_range(0, 0.5), randf_range(-0.5, 0.5))
	get_tree().current_scene.add_child(label)
	var tween: Tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", label.global_position.y + 0.9, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(label.queue_free)

func debug_info():
	DebugLogger.log("=== Monton Debug v5 (núcleo macizo + costra de paja) ===")
	DebugLogger.log("Total: %d Restantes: %d" % [straws.size(), get_remaining_count()])
	DebugLogger.log("Montón: R=%.1f m  H=%.1f m  (pendiente base ~29°, se sube andando)" % [base_radius, pile_height])
	DebugLogger.log("Núcleo opaco: %s | %s" % ["sí" if core_enabled else "no", _coverage_report()])
	var counts: Array[int] = [0, 0, 0]
	for s in straws:
		if not s.is_removed:
			counts[s.tier] += 1
	DebugLogger.log("Comunes: %d Secas: %d Doradas: %d" % [counts[0], counts[1], counts[2]])
