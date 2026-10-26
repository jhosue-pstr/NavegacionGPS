# Plan de Desarrollo — Navegador ESP32-C3 + GC9A01

> **Versión:** 1.0 · **Fecha:** 2026-10-22 · **Estado:** planificación cerrada, sin código de app.
>
> Documento de referencia del proyecto. Describe el estado **objetivo**.
> Al día de hoy solo existe el proyecto Flutter en `app/`; ver
> [Estado del repositorio](#13-estado-del-repositorio).

---

## Índice

1. [Objetivo](#1-objetivo)
2. [Decisiones cerradas](#2-decisiones-cerradas)
3. [Alcance de v1](#3-alcance-de-v1)
4. [Arquitectura](#4-arquitectura)
5. [Por qué esta arquitectura](#5-por-qué-esta-arquitectura)
6. [Hardware](#6-hardware)
7. [Stack de software](#7-stack-de-software)
8. [Protocolo](#8-protocolo)
9. [Estrategia offline](#9-estrategia-offline)
10. [Fases](#10-fases)
11. [Métricas de aceptación](#11-métricas-de-aceptación)
12. [Riesgos](#12-riesgos)
13. [Estado del repositorio](#13-estado-del-repositorio)
14. [Supuestos y pendientes](#14-supuestos-y-pendientes)
15. [Anexo técnico](#15-anexo-técnico)

---

## 1. Objetivo

Dispositivo de navegación para moto con pantalla redonda de 1.28". Muestra un mapa
heading-up centrado en la posición, la ruta trazada y la próxima maniobra.

**Restricción de diseño que manda sobre todo lo demás:** el autor domina desarrollo
de apps pero no firmware. Por eso toda la inteligencia vive en el teléfono y el
ESP32-C3 es una pantalla tonta que solo pinta píxeles.

## 2. Decisiones cerradas

| Decisión | Valor | Motivo |
|---|---|---|
| Quién renderiza | Teléfono (Flutter/Android) | Perfil de habilidades del autor |
| Quién pinta | ESP32-C3 + GC9A01 | Es lo que hay |
| Transporte v1 | WebSocket sobre hotspot del teléfono | ~500 KB/s vs ~50 KB/s de BLE |
| Descubrimiento | ESP32 → `WiFi.gatewayIP():8080` | El teléfono es el AP, por tanto el gateway. Cero IPs fijas |
| Formato de píxel | RGB565 **little-endian** | Zero-copy como `uint16_t` en el C3 |
| Granularidad | Tiles 16×16 (grid 15×15) | Deltas baratos; el marcador girando toca 2 tiles |
| Framebuffer en C3 | **Ninguno** | 115 KB por frame, sin PSRAM. Se pinta por tiles |
| Control de flujo | ACK por frame, 1 frame en vuelo | Evita bufferbloat y latencia acumulada |
| Mapa | `flutter_map` + tiles OSM (proveedor por definir) | Flutter puro → capturable con `RepaintBoundary` |
| Ruteo | OSRM, **precalculado antes de salir** | Sin dependencia de red durante la ruta |
| Offline v1 | Ruta + caché pasivo + mapa sobre fondo negro | Barato y suficiente |

## 3. Alcance de v1

### Entra

- Mapa heading-up centrado en la posición
- Ruta con instrucciones turn-by-turn (OSRM, calculada antes de salir)
- HUD: próxima maniobra, distancia, velocidad, hora
- Modo noche (brillo PWM)
- Reconexión automática
- Degradación elegante: sin tiles → fondo negro + línea de ruta + flecha

### No entra en v1

| Función | Versión |
|---|---|
| Pre-descarga de corredor | v1.1 |
| MBTiles / PMTiles regional | v2 |
| Ruteo offline real | v3 (probablemente nunca) |
| Transporte BLE como fallback | v2 |
| Carcasa impresa / visera | v1.1 |
| Botones físicos de zoom | v1.1 |
| Touch | descartado (guantes) |

## 4. Arquitectura

```
┌──────────────── TELÉFONO (Flutter / Android) ───────────────┐
│                                                             │
│  geolocator ──► posición + rumbo GPS                        │
│  http       ──► OSRM (ruta + maniobras)   [antes de salir]  │
│  flutter_map──► tiles + ruta                                │
│  Stack      ──► HUD (flecha, distancia, velocidad)          │
│         │                                                   │
│  RepaintBoundary 480×480                                    │
│         ▼                                                   │
│  downsample 2×2 → 240×240                                   │
│         ▼                                                   │
│  RGB565 LE → diff por tiles 16×16                           │
│         ▼                                                   │
│  WebSocket server :8080   ◄── el ESP32 se conecta al gw     │
└─────────────────────────────────────────────────────────────┘
                          │
┌──────────────── ESP32-C3 ─────────────────┐
│ WebSocketsClient → parse BATCH            │
│ memcpy → lcd.pushImage(x,y,w,h, tileBuf)  │
│ → ACK por frame                           │
└───────────────────────────────────────────┘
```

**Reparto de responsabilidades:** el ESP32 no sabe qué es un mapa. No calcula, no
decide, no persiste estado. Solo pinta rectángulos donde se lo indican.

## 5. Por qué esta arquitectura

### WiFi y no BLE

| | BLE (C3) | WiFi (C3) |
|---|---|---|
| Throughput real | 30–60 KB/s | 500–1000 KB/s |
| Frame completo (115 KB) | 2–4 s | 0.12–0.25 s |
| FPS útiles | ~0.5 | 4–8 |
| Protocolo | GATT, a medida | WebSocket / TCP |
| Debug | Sniffer BLE | `curl`, `websocat` |

El único argumento de BLE era la autonomía, y el dispositivo va alimentado por el
USB de la moto. BLE queda como fallback de v2, con el mismo protocolo.

### Por qué no standalone

El C3 no tiene PSRAM ni motor de ruteo viable. Un standalone real sería
"ruta precalculada en la PC + flechita con GPS", sin recalcular ni tráfico: un
proyecto distinto y más largo. El teléfono ya aporta GPS de calidad y pantalla.

### Por qué `flutter_map` y no MapLibre

`maplibre_gl` es un PlatformView de Android; capturarlo como imagen requiere
`PixelCopy` y un platform channel. `flutter_map` es Flutter puro, así que
`RepaintBoundary.toImage()` funciona directo. El costo es que solo hay tiles
raster, no vectoriales — aceptable para v1.

### Por qué el ESP32 es cliente y no servidor

El teléfono es el hotspot, así que **es** el gateway de la red. El ESP32 lee
`WiFi.gatewayIP()` y se conecta ahí. No hay IP que configurar, no hay mDNS, y
funciona al cambiar de teléfono o de subred.

## 6. Hardware

### BOM

| Componente | Nota |
|---|---|
| ESP32-C3 SuperMini | 400 KB SRAM, sin PSRAM, WiFi 2.4 GHz + BLE 5 |
| GC9A01 1.28" 240×240 SPI | 7–8 pines, ya con header soldado |
| Protoboard + dupont macho-macho | cortos, < 10 cm |
| 100 µF + 100 nF | entre 3V3 y GND, junto al display |
| 2 pulsadores + 2× 10k | v1.1, zoom |
| Impresión 3D de visera | v1.1, ver riesgo de legibilidad |

**No se necesitan:** GPS externo, tarjeta SD, batería, PSRAM.

### Pinout

| GC9A01 | GPIO C3 | Función |
|---|---|---|
| VCC | 3V3 | nunca 5V: evita backfeed |
| GND | GND | |
| SCL | **4** | SCK |
| SDA | **6** | MOSI (no es I2C) |
| DC | **5** | |
| CS | **7** | |
| RES | **3** | |
| BLK | **10** | PWM de brillo vía `panel.config().pin_bl` |

- **Nunca usar GPIO 2, 8 ni 9**: strapping pins / BOOT / LED onboard.
- Libres para v1.1: 0, 1, 20, 21.
- SPI a 40 MHz es marginal en protoboard. Si aparece basura, bajar a 27 MHz
  **antes** de sospechar del código.

### Alimentación

USB de la moto → pad `5V` del SuperMini → LDO → 3V3. Añadir 100 µF + 100 nF
cerca del display: el backlight mete ruido en la línea de SPI.

## 7. Stack de software

### App (`app/`)

| Pieza | Paquete | Nota |
|---|---|---|
| Mapa | `flutter_map` 8.x | raster; capturable |
| Coordenadas | `latlong2` | |
| GPS | `geolocator` 14.x | rumbo GPS, no magnetómetro |
| Ruteo | `http` → OSRM | endpoint público por defecto |
| Pantalla encendida | `wakelock_plus` | |

Servidor WebSocket: `dart:io` `HttpServer` + `WebSocketTransformer` (sin paquetes).

### Firmware (`firmware/nav_display/`)

| Pieza | Librería |
|---|---|
| Panel | LovyanGFX (init sequence GC9A01 + DMA) |
| Red | WiFi (core ESP32) |
| Transporte | `arduinoWebSockets` (Links2004) |

Ajustes de Arduino IDE: board `ESP32C3 Dev Module`, **USB CDC On Boot: Enabled**,
CPU 160 MHz, upload 921600.

### Herramientas (`tools/`)

Banco de pruebas en Python para validar el pipeline sin el teléfono:
`frame_sender.py` (USB) y `ws_server.py` (WebSocket).

## 8. Protocolo

Mensajes WebSocket binarios. Todos los enteros **little-endian**.

```
0x01 HELLO  ESP32→tel   u8 ver | u8 w | u8 h | u8 tile | u16 max_batch
0x02 BATCH  tel→ESP32   u16 seq | u8 flags | u8 count | count×{u8 x,y,w,h | u16 len | u8[] px}
0x03 ACK    ESP32→tel   u16 seq
0x04 CMD    tel→ESP32   u8 sub | payload      (0x01 brillo, 0x02 sleep, 0x03 clear)
0x05 STATS  ESP32→tel   u8 fps10 | u8 heapkb | i8 rssi | u16 drops
```

**Reglas normativas**

- Tiles alineados a 16 px; `x,y,w,h` son `u8` (240 cabe).
- `len == w * h * 2`, en RGB565 little-endian.
- `h <= 16`. Se permite merge horizontal hasta 240×16 para reducir cabeceras.
- `count <= 8` y batch ≤ 4096 B (límite de heap del C3).
- `flags bit0` = último batch del frame. El ACK se manda **por frame**, no por batch.
- El teléfono mantiene **1 frame en vuelo**. Si el FPS no alcanza, subir a 2.
- Al conectar, el teléfono invalida el frame anterior y manda uno completo.

**Presupuesto de datos**

| Acción | Tiles | Bytes |
|---|---|---|
| Marcador gira | 1–4 | ~1–2 KB |
| Scroll normal | ~40–60 | ~25–30 KB |
| Frame completo (zoom) | 225 | 115 KB |

## 9. Estrategia offline

Sin señal **no se cae todo**: solo el mapa base. El hotspot es local y no necesita
red; el enlace con el ESP32 sigue vivo.

| Función | ¿Internet? | Sin señal |
|---|---|---|
| GPS / posición / rumbo | No | ✅ |
| Enlace ESP32 | No | ✅ |
| Ruta dibujada + flecha | No | ✅ |
| Turn-by-turn ya calculado | No | ✅ |
| Tiles del mapa | Sí | ❌ |
| Recalcular ruta | Sí | ❌ |
| Buscar destino | Sí | ❌ |

**El caso "cero tiles" es usable:** con solo la polilínea guardada (~32 KB para
200 km) se muestra posición, ruta, próxima maniobra y velocidad. Es el 80 % del
valor de navegación con 0 MB de mapa. La UI debe diseñarse con esa premisa: el
mapa es decorativo, la ruta es lo esencial.

### Escalera de soluciones

| Nivel | Qué | Cuándo |
|---|---|---|
| 1 | Caché pasivo (`flutter_map_tile_caching`) | v1 |
| 2 | Pre-descarga de corredor (z13–17, ~5 km de ancho) | v1.1 |
| 3 | MBTiles/PMTiles regional en el dispositivo | v2 |

Un corredor de 100 km con 5 niveles pesa 50–100 MB; solo z14–16 baja a ~15 MB.

> ⚠️ **No pre-descargar de `tile.openstreetmap.org`.** Su política de uso prohíbe
> explícitamente la descarga masiva y el bloqueo es silencioso. Usar un proveedor
> que lo permita (MapTiler, Protomaps, tileserver propio).

### Ruteo sin red

La ruta se calcula **antes de salir** y se guarda con sus maniobras. Si hay desvío,
no se recalcula: se muestra "volver a la ruta" (flecha y distancia al punto más
cercano de la polilínea). Rerouting offline real solo con Valhalla / GraphHopper /
BRouter, y eso es v3.

## 10. Fases

| # | Fase | Estimación | Entregable | Criterio de aceptación |
|---|---|---|---|---|
| 0 | Toolchain | 0.5 d | blink + serial, `flutter run` | ves el blink y "hola" por serial |
| 1 | Pantalla viva | 1 d | `lgfx_config.hpp`, test de barras | círculo completo, colores correctos, ≥40 fps |
| 2 | Banco USB ⚠️ | 2 d | parser + `frame_sender.py` | 15 fps de scroll sintético, sin tearing |
| 3 | WiFi + WS | 2.5 d | cliente WS + máquina de estados | ≥5 fps, latencia < 200 ms, reconexión < 5 s |
| 4 | Mapa + GPS | 4 d | `flutter_map` heading-up | mapa usable conduciendo |
| 5 | Captura + envío | 3 d | `RepaintBoundary` → diff → WS | display espeja el teléfono a ≥4 fps |
| 6 | Navegación | 4 d | OSRM + HUD + ruta | completar una ruta acertando maniobras |
| 7 | Endurecer | 3 d | caché, modo noche, reconexión | 30 min de ruta sin cortes |

**Total ≈ 20 días de trabajo (60–90 h).** A ritmo de hobby: 3–4 meses.
Intensivo: 5–6 semanas.

**La Fase 2 es la clave del proyecto:** valida todo el pipeline gráfico sin radios.
Si algo falla ahí, no es WiFi. Es la fase que evita semanas de diagnóstico cruzado.

## 11. Métricas de aceptación

| Métrica | Objetivo |
|---|---|
| FPS sostenido | ≥ 4 |
| Latencia teléfono → pantalla | < 300 ms |
| Datos por frame en scroll | < 30 KB |
| Reconexión tras caída | < 5 s |
| Ruta de 30 min sin cortes | sí |
| Arranque en frío | < 20 s |

## 12. Riesgos

| Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|
| El operador bloquea el hotspot | Media | Alto | Probar en Fase 0; plan B = AP del ESP32 |
| Hotspot en 6 GHz o WPA3 | **Alta** | Alto | Fijar 2.4 GHz + WPA2 antes de todo |
| WiFi más lento de lo previsto | Media | Medio | JPEG en el C3, o BLE con tile-delta |
| **Ilegible bajo el sol** | **Alta** | Alto | Visera impresa 3D; el panel es ~250 nits |
| SPI inestable en protoboard | Media | Medio | Cables < 10 cm; bajar a 27 MHz |
| Android mata la app | Media | Alto | Primer plano; foreground service en v1.1 |
| Heap insuficiente en el C3 | Baja | Alto | Batches ≤ 4 KB, sin framebuffer |
| OSM bloquea por bulk download | Alta | Medio | MapTiler / Protomaps / self-host |
| Vibración suelta los dupont | Alta | Medio | Soldar en v1.1 |
| El auto-apagado del hotspot corta | Media | Medio | Desactivar ahorro de batería |

## 13. Estado del repositorio

### Lo que existe

```
├── AGENTS.md          instrucciones para agentes (gitignored)
├── README.md
├── .gitignore
├── app/               proyecto Flutter Android con dependencias resueltas
├── docs/              este plan
├── tools/             vacío
└── firmware/nav_display/   vacío
```

### Lo que falta

- `app/lib/` — `main.dart` sigue siendo el contador por defecto
- `firmware/nav_display/` — firmware, `lgfx_config.hpp`, `protocol.hpp`, `config.example.h`
- `tools/` — `frame_sender.py`, `ws_server.py`, `requirements.txt`
- `docs/protocol.md` — extracción normativa de la sección 8
- Tests: `app/test/widget_test.dart` es el del contador y fallará al reemplazar `main.dart`

### Primeros tres commits sugeridos

1. `firmware/display_test` — barras de color. Nada más.
2. `tools/frame_sender.py` — genera un PNG 240×240 de prueba.
3. `app/lib/main.dart` — `flutter_map` con GPS y un marcador, sin ESP32.

Tres piezas independientes. Cuando las tres funcionen por separado, la Fase 2 las junta.

## 14. Supuestos y pendientes

### Supuestos

- El teléfono va **montado en la moto** (app en primer plano).
- La moto tiene USB de carga, así que la autonomía no es un requisito.
- v1 usa caché pasivo, no pre-descarga.

### Pendientes de decidir

| Tema | Impacto |
|---|---|
| País/región de uso | define si conviene MBTiles regional |
| Proveedor de tiles | MapTiler free vs Protomaps self-host |
| Teléfono montado vs bolsillo | si va al bolsillo: foreground service + ~2 días |
| Confirmar hotspot 2.4 GHz + WPA2 | bloquea la Fase 3 |

## 15. Anexo técnico

### Configuración LovyanGFX (valores críticos)

| Parámetro | Valor | Si falla |
|---|---|---|
| `spi_host` | `SPI2_HOST` | único en C3 |
| `freq_write` | 40 MHz | bajar a 27 MHz si hay basura |
| `spi_3wire` | `true` | GC9A01 no tiene MISO |
| `invert` | `true` | si se ve invertido → `false` |
| `rgb_order` | `false` | si rojo y azul están cambiados → `true` |
| `pin_bl` | GPIO 10 | habilita `setBrightness()` por PWM |
| `dma_channel` | `SPI_DMA_CH_AUTO` | |

### Las dos trampas del firmware

**1. Alineación.** Tras avanzar la cabecera, el puntero a píxeles puede quedar en
dirección impar. Un `(uint16_t*)p` desalineado en RISC-V es crash o basura silenciosa.
Siempre copiar a un buffer alineado:

```cpp
static uint16_t tileBuf[240 * 16];
memcpy(tileBuf, p, len);
lcd.pushImage(x, y, w, h, tileBuf);
```

**2. WiFi power save.** Por defecto el C3 duerme la radio entre beacons y añade
100–300 ms de latencia. Llamar `WiFi.setSleep(false)` tras conectar.

### Pipeline de captura (app)

```dart
final img = await boundary.toImage(pixelRatio: 1.0);   // 480×480
final rgba = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
// downsample 2×2 por promedio → 240×240 → RGB565 LE
```

Renderizar a 480 y reducir a 240 duplica la nitidez del texto en 1.28" (~187 ppi).

### Heading-up

No rotar con el magnetómetro: cerca del motor y del metal miente. Usar el **rumbo
GPS** cuando la velocidad es > 2 m/s y congelar el último valor al detenerse.
Preferir `mapController.rotate()` de `flutter_map` (rellena las esquinas) antes que
un `Transform.rotate`, que deja huecos en el cuadrado de captura.

### Secuencia de conexión del firmware

```
init display → splash
  → WiFi.begin (timeout 15 s) → "SIN WIFI" si falla
  → WiFi.setSleep(false)
  → ws.begin(gatewayIP, 8080, "/ws") → reintento cada 2 s
  → al conectar: enviar HELLO → "ESPERANDO"
  → primer BATCH → streaming
  → si no hay tráfico 3 s: "SIN ENLACE" (no congelar el último frame)
```

---

*Fin del documento. Actualizar la sección 13 a medida que avancen las fases.*
