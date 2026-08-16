# Balatro Spotify Connect

Integracion multimedia y reproductor interactivo dentro de Balatro. Permite controlar tu musica directamente desde el juego a traves de un HUD flotante arrastrable, compatible con Spotify, YouTube Music y otros reproductores del sistema operativo (incluidos navegadores).

## Caracteristicas

- Mini reproductor flotante en el HUD con caratula de album en tiempo real, titulo, artista, segundero y controles (pausa, reanudar, anterior, siguiente).
- HUD totalmente arrastrable con el raton y persistencia automatica de posicion en pantalla.
- Soporte multiplataforma y multiapp: funciona con Spotify, YouTube Music, Google Chrome, Microsoft Edge y navegadores mediante las APIs multimedia del sistema (Windows SMTC/WASAPI y Linux MPRIS).
- Selector de fuente en los ajustes para elegir la aplicacion especifica a controlar o dejarlo en deteccion automatica.
- Efectos reactivos de audio: atenuacion suave del volumen al pausar la partida o abrir sobres de cartas (Booster Packs).
- Sincronizacion de volumen entre el juego y la aplicacion activa.
- Silenciado de la musica nativa de Balatro al reproducir audio externo, manteniendo intactos todos los efectos de sonido.
- Soporte completo para caracteres UTF-8 y fuentes CJK (japones, kanji, tildes).
- Menu de configuracion accesible mediante la tecla F8 o desde el menu de mods de Steamodded.

## Stack tecnico

- Lua (Steamodded y Lovely).
- Daemon: Rust (Tokio, Axum, Windows SMTC & WASAPI, Linux MPRIS).
- Comunicacion: IPC REST asincrono mediante subprocesos de Love2D

## Estructura del proyecto

```text
balatro-spotify-connect/
├── balatro-spotify-connect.json
├── bin/
│   ├── daemon-x86_64-windows.exe
│   └── daemon-x86_64-linux
├── build.ps1
├── build.sh
├── daemon/
│   ├── Cargo.toml
│   └── src/
│       ├── main.rs
│       ├── server.rs
│       ├── spotify.rs
│       └── state.rs
├── lovely/
│   ├── audio_hooks.toml
│   └── modules.toml
└── src/
    ├── config.lua
    ├── daemon_manager.lua
    ├── game_hooks.lua
    ├── ipc_client.lua
    ├── ipc_worker.lua
    ├── main.lua
    └── ui/
        ├── draggable_container.lua
        ├── hud_player.lua
        └── modal_browser.lua
```

## Requisitos

- Balatro (Steam o compatible).
- Steamodded.
- Lovely.

## Instalacion

1. Descarga o clona este repositorio dentro de la carpeta `Mods` de Balatro:
   - Windows: `%AppData%/Balatro/Mods/balatro-spotify-connect`
   - Linux: `~/.local/share/Steam/steamapps/compatdata/2379780/pfx/drive_c/users/steamuser/AppData/Roaming/Balatro/Mods/balatro-spotify-connect`
2. Inicia Balatro. El mod iniciara el daemon en segundo plano automaticamente.
3. Abre Spotify, YouTube Music o cualquier reproductor compatible y reproduce musica.

## Controles

- Clic izquierdo sobre los botones del HUD: controlar reproduccion.
- Clic sostenido sobre el marco del HUD: arrastrar y reubicar en la pantalla.
- Tecla F8: abrir menu de opciones y reproductor extendido.

## Compilacion (Opcional)

Si deseas compilar el daemon en Rust desde el codigo fuente:

En Windows (PowerShell):
```powershell
.\build.ps1
```

En Linux (Bash):
```bash
chmod +x build.sh
./build.sh
```

El binario resultante se guardara automaticamente dentro de la carpeta `bin/`.
