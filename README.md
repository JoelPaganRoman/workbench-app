# Workbench

Docs, Sheets, Slides, Gemini y Drive en una sola app nativa de macOS.

**v2.0** es una reescritura completa en Swift/SwiftUI con WKWebView — la app pasa de ~250 MB (Electron) a ~1 MB, con menor consumo de RAM y batería. La versión Electron original vive en el historial de git (hasta v1.1.3).

## Funciones

- 🗂 Pestañas: Docs, Sheets, Slides, Gemini y Drive (⌘1–⌘5) + Gmail, Calendar, Keep y Meet activables en Preferencias
- ⬅➡ Pantalla dividida (⌘\) con divisor arrastrable y selector de pestaña por panel
- 🔗 Enrutado inteligente de enlaces: un enlace de Docs abierto en Gemini salta a la pestaña de Docs; los enlaces externos van a tu navegador
- ✨ Gemini flotante (⇧⌘G): panel siempre visible sobre cualquier app y en todos los escritorios
- ⌨️ Atajo global ⌥⌘W: muestra/oculta Workbench desde cualquier app
- 📥 Descargas a ~/Descargas con revelado en Finder
- 🔔 Notificaciones web (Gmail/Calendar) como notificaciones nativas de macOS
- 💾 Sesión única de Google compartida entre pestañas; recuerda pestaña activa, split, tamaño y posición de ventana
- 🔄 Aviso de actualizaciones vía GitHub Releases

## Instalación

1. Descarga `Workbench-mac.zip` desde [Releases](https://github.com/JoelPaganRoman/workbench-app/releases)
2. Descomprime y arrastra `Workbench.app` a Aplicaciones
3. **Primera apertura** (la app está firmada ad-hoc, sin notarizar): clic derecho → Abrir → Abrir. Si macOS lo bloquea, ve a Ajustes del Sistema → Privacidad y seguridad → "Abrir de todos modos"
