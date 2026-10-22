# Navegación — ESP32-C3 + GC9A01

Navegador GPS para moto: un display redondo de 1.28" que muestra un mapa
heading-up, la ruta y la próxima maniobra. El teléfono (Android/Flutter) hace
todo el trabajo pesado; el ESP32-C3 solo pinta píxeles.

```
TELÉFONO (Flutter)  ──WebSocket sobre hotspot──►  ESP32-C3 + GC9A01
GPS, mapa, ruta, HUD        tiles RGB565            recibe y blit-ea
```

## Estructura

| Ruta                    | Qué es                                                    |
| ----------------------- | --------------------------------------------------------- |
| `app/`                  | App Flutter (Android). Renderiza, captura y envía frames. |
| `firmware/nav_display/` | Firmware Arduino del ESP32-C3.                            |
| `tools/`                | Banco de pruebas en Python (USB y WebSocket).             |
| `docs/PLAN.md`          | Plan de desarrollo completo y por fases.                  |
| `docs/protocol.md`      | Especificación normativa del protocolo.                   |

## Arranque rápido

**1. Firmware**

```bash
cd firmware/nav_display
cp config.example.h config.h
```

Abrir `nav_display.ino` en Arduino IDE con:

- Board: `ESP32C3 Dev Module`
- USB CDC On Boot: `Enabled`
- CPU Frequency: `160MHz`
- Upload Speed: `921600`

**2. Banco de pruebas (sin teléfono)**

```bash
cd tools
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# Fase 2: por USB
python3 frame_sender.py --port /dev/ttyACM0 --mode anim

# Fase 3: por WiFi (el ESP32 se conecta al hotspot del PC/teléfono)
python3 ws_server.py --mode anim
```

**3. App**

```bash
cd app
flutter run
```

## Estado

- [x] Plan y protocolo definidos
- [x] Esqueleto de repositorio
- [ ] Fase 1 — pantalla viva
- [ ] Fase 2 — banco de pruebas USB
- [ ] Fase 3 — WebSocket sobre WiFi
- [ ] Fase 4 — mapa y GPS en Flutter
- [ ] Fase 5 — captura y envío
- [ ] Fase 6 — navegación con ruta
- [ ] Fase 7 — endurecer
