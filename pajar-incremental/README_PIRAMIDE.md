# Implementación de Pirámide de Paja Orgánica - Sistema de Recolección con Forma Natural

## Descripción General
Este sistema implementa una pirámide de paja interactiva en 3D con forma orgánica (cono/domo) y recolección por briznas individuales. Los jugadores pueden recolectar paja de la pirámide, la cual mostrará una forma natural que se reduce a medida que se recolecta.

## Archivos Creados

### 1. piramide_paja.gd
**Path:** `/Users/juanfran/pajar-incremental/piramide_paja.gd`

**Responsabilidades:**
- Gestión de la estructura de datos de briznas de paja
- Sistema de Tiers de paja (Común, Seca, Dorada)
- Generación procedural de malla con forma orgánica
- Eliminación de Z-fighting mediante diseño de malla sin caras solapadas
- Lógica de recolección con detección de briznas expuestas
- Animaciones y efectos visuales
- Regeneración automática de la pirámide
- Área de colisión amplia para mejor detección de clics

**Configuración Exportada:**
- `base_radius`: Radio base del montón (ej. 3.0)
- `height_levels`: Niveles de altura (ej. 5)
- `cell_density`: Densidad de briznas (ej. 0.8)

### 2. piramide_paja.tscn
**Path:** `/Users/juanfran/pajar-incremental/piramide_paja.tscn`

**Estructura de Nodos:**
- `PiramidePaja` (StaticBody3D)
  - `MeshInstance3D` (malla generada proceduralmente con forma orgánica)
  - `CollisionShape3D` (colisión para física)
  - `SelectionArea` (Area3D con esfera grande para mejor detección de clics)

### 3. Actualizaciones a jugador.gd
**Path:** `/Users/juanfran/pajar-incremental/jugador.gd`

**Nuevas Características:**
- Sistema de inventario por tipos de paja
- Funciones para gestionar paja de diferentes calidades
- UI actualizada para mostrar valor total de paja

### 4. Actualizaciones a vaca.gd
**Path:** `/Users/juanfran/pajar-incremental/vaca.gd`

**Compatibilidad:**
- Sistema de venta que considera tipos de paja
- Compatibilidad con sistema antiguo y nuevo

## Cómo Añadir la Pirámide al Editor de Godot

### Paso 1: Abrir el Proyecto
1. Abre Godot Engine 4.3
2. Carga el proyecto `PajarIncremental`
3. Abre la escena `main.tscn`

### Paso 2: Añadir la Pirámide a la Escena Principal
1. En la vista de escena (Scene tab), selecciona el nodo raíz `Main`
2. Arrastra el archivo `piramide_paja.tscn` desde el FileSystem dock hasta la vista de escena
3. La pirámide se agregará como hijo del nodo `Main`

### Paso 3: Posicionar la Pirámide
1. Selecciona el nodo `PiramidePaja` en la vista de escena
2. En el Inspector (Inspect tab):
   - **Transform:**
     - Posición: `0, 0.5, 0` (ajustar según sea necesario)
     - Rotación: `0, 0, 0`
     - Escala: `1, 1, 1`
   - **Script Parameters:**
     - `base_radius`: 3.0
     - `height_levels`: 5
     - `cell_density`: 0.8

### Paso 4: Configurar Propiedades de la Pirámide
1. Con el nodo `PiramidePaja` seleccionado:
   - **Properties:**
     - `base_radius`: Radio base (recomendado: 2.0-5.0)
     - `height_levels`: Niveles de altura (recomendado: 3-7)
     - `cell_density`: Densidad de briznas (recomendado: 0.5-1.2)

### Paso 5: Verificar la Conexión
1. Asegúrate de que el jugador pueda interactuar:
   - El sistema usa un área de colisión esférica grande para detección de clics
   - El jugador debe estar dentro del radio de la pirámide
2. Prueba haciendo clic en la pirámide con el mouse

## Sistema de Tiers de Paja

### Tres Niveles de Calidad:
1. **Tier 1: Paja Común**
   - Valor de venta: 1 oro
   - Color: Amarillo pálido (#f0d0a0)
   - Aparece en: Niveles inferiores/base

2. **Tier 2: Paja Seca**
   - Valor de venta: 2 oro
   - Color: Marrón claro (#c8a878)
   - Aparece en: Niveles medios

3. **Tier 3: Paja Dorada**
   - Valor de venta: 5 oro
   - Color: Dorado (#ffd700)
   - Aparece en: Niveles superiores/punta

## Mecánica de Forma Orgánica

### Sistema de Briznas Individuales:
- La pirámide tiene forma de cono/domo natural
- Cada brizna de paja es un cilindro delgado generado proceduralmente
- Las briznas tienen variaciones aleatorias para aspecto orgánico
- Al recolectar una brizna, se marca como vacía y se regenera la malla
- Esto crea un efecto de reducción gradual del montón

### Distribución Natural:
- Las briznas se distribuyen en patrones circulares con ruido
- El radio disminuye con la altura para forma cónica
- Mayor densidad en niveles bajos, menor en niveles altos
- Las briznas expuestas son las que están en la superficie visible

## Funcionalidades Avanzadas

### Regeneración Automática:
- Cuando todas las briznas están vacías
- La pirámide se regenera completamente
- Mantiene la configuración original

### Sistema de Inventario por Calidad:
- El jugador lleva registro por tipo de paja
- La vaca calcula el valor total basado en calidad
- UI muestra valor total, no solo cantidad

### Eliminación de Z-Fighting:
- Diseño de malla sin caras solapadas
- Cada brizna es independiente sin superposición de geometría
- Material optimizado para renderizado eficiente

### Área de Selección Mejorada:
- Uso de Area3D con forma esférica grande
- Mayor tolerancia para detección de clics
- No requiere apuntar exactamente al centro de una brizna

### Compatibilidad:
- Funciona con sistema de paja existente
- Compatible con escenas actuales
- No rompe funcionalidad existente

## Troubleshooting

### Problema: La pirámide no se muestra
- Verifica que el nodo MeshInstance3D tenga malla
- Revisa el código de regeneración de malla
- Comprueba que no haya errores en la consola

### Problema: No se puede recolectar paja
- Verifica que el área de selección esté configurada
- Asegúrate que el jugador esté cerca de la pirámide
- Comprueba que hay briznas expuestas disponibles

### Problema: Texto flotante no aparece
- Verifica el código de crear_texto_flotante
- Asegúrate de que el Label3D se añada a la escena correcta
- Revisa las posiciones de los textos

## Optimizaciones Futuras

### Mejoras Posibles:
1. Sistema de raycasting para selección precisa de briznas
2. Transiciones suaves para deformación de malla
3. Sistema de respawn programado de pirámide
4. Más niveles de calidad de paja
5. Efectos de partículas para recolección
6. Mejora en la generación de forma orgánica con ruido Perlin

### Performance:
- Malla procedural optimizada
- Solo se regenera cuando se modifican datos
- Sistema de pooling para textos flotantes

## Conclusión

El sistema de pirámide de paja orgánica agrega profundidad al juego con:
- Mecánica de recolección estratégica
- Sistema de calidad de recursos
- Forma natural y visualmente atractiva
- Eliminación de problemas técnicos como Z-fighting
- Área de interacción mejorada para mejor experiencia
- Compatibilidad con sistemas existentes

Para probarlo, simplemente añade la escena `piramide_paja.tscn` a tu escena principal y posiciona la pirámide donde desees que aparezca en el mundo.