# TV y Radio Mundial (iPhone)

App nativa para iPhone (Swift + SwiftUI) para **ver canales de TV gratuitos de todo el mundo** y **escuchar emisoras de radio de todos los países**, con un **mapa/globo terráqueo** para explorar.

## Qué hace

| Pestaña | Qué hay |
|---|---|
| **Mapa** | Globo satelital. Modo 📻 Radio: acercas un país y aparecen puntos verdes (cada uno es una emisora en su ciudad); tocas uno y suena. Botón 🔀 para viajar a una radio al azar del mundo. Modo 📺 TV: tocas la bandera de un país y salen sus canales. |
| **TV** | Canales de tu país, por país, por tema (noticias, deportes, películas, infantiles…), por idioma, o todos. Pantalla completa de Apple con AirPlay e imagen dentro de imagen. |
| **Radio** | Buscador mundial, más escuchadas, por país, por género. Sigue sonando con la pantalla bloqueada, con controles en la pantalla de bloqueo y el nombre de la canción cuando la emisora lo manda. |
| **Favoritos** | Estrella ☆ en cualquier canal o emisora. |

## De dónde salen los canales y emisoras (fuentes libres y legales)

- **TV**: listas públicas de [iptv-org](https://github.com/iptv-org/iptv) (solo canales que se transmiten gratis y abiertos por internet). Algunos pueden estar caídos o bloqueados fuera de su país.
- **Radio**: directorio libre [Radio Browser](https://www.radio-browser.info) (más de 40.000 emisoras).

## Requisitos

iPhone con iOS 17 o más nuevo.

## Cómo se compila

GitHub Actions (`.github/workflows/ios.yml`) usa una Mac de GitHub, genera el proyecto con XcodeGen y compila
un **.ipa sin firmar**. Sale en *Actions › artifact `MundoTVRadio-ipa`* y en *Releases*.

## Cómo instalarlo en el iPhone (igual que Escáner 3D)

1. Descargar `MundoTVRadio.ipa` de *Releases*.
2. Abrir **Sideloadly** en la PC, conectar el iPhone por cable, arrastrar el .ipa, poner tu Apple ID y *Start*.
3. En el iPhone: *Ajustes › General › VPN y gestión de dispositivos* → confiar en tu Apple ID (el Modo de desarrollador ya lo tienes activado).

Con Apple ID gratis dura **7 días**; luego se vuelve a instalar igual (los favoritos se conservan).
