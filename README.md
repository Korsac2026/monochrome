# Monochrome ESP

Script standalone para el juego **MONOCHROME** (PlaceId `134208374070897`).
No depende de Uranium ni de ninguna librería. Proyecto aparte.

## Qué incluye

1. **Monster ESP** — detecta al monstruo y lo marca con contorno + nombre + distancia.
2. **Key ESP** — marca la ubicación de las llaves del mapa.
3. **Code ESP** — marca keypads / notas / cajas fuertes y lee el código
   si aparece en algún texto (pantalla, nota, prompt).

Todo en blanco y negro (monocromo).

## Uso

Ejecutá `monochrome-esp.lua` directamente en tu executor.

- **RightShift**: muestra / oculta la GUI.
- **X**: cierra el script y limpia todo el ESP.
- La GUI es arrastrable desde el título.

## Opciones en la GUI

| Opción | Qué hace |
|---|---|
| MONSTER ESP | Activa / apaga el ESP del monstruo |
| KEY ESP | Activa / apaga el ESP de llaves |
| CODE ESP | Activa / apaga el ESP de códigos |
| NPC SCAN | Marca cualquier humanoide no-jugador como monstruo (por si el monstruo usa un nombre raro) |
| MAX DIST | Distancia máxima del ESP (150m / 300m / 500m / 1000m / INF) |

## Ajustar nombres

Si el monstruo, las llaves o los códigos del juego usan otros nombres,
editá las listas al inicio del script:

- `MONSTER_NAMES` / `MONSTER_FOLDERS`
- `KEY_NAMES`
- `CODE_KINDS`
