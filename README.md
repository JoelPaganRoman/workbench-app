# Workbench

App de escritorio para macOS que unifica Docs, Sheets, Slides, Gemini y Drive
en una sola ventana con pestañas, enrutamiento automático de archivos abiertos
desde Drive, y modo de pantalla dividida.

## Cómo generar una nueva build firmada

Cada vez que quieras publicar una nueva versión ya compilada y firmada
(ad-hoc, sin necesidad de una Mac propia ni de pagar Apple Developer):

```bash
git tag v1.0.1
git push origin v1.0.1
```

Esto dispara el workflow `.github/workflows/build-mac.yml`, que:
1. Compila la app en un runner real de macOS (arquitectura universal: Apple Silicon + Intel).
2. La firma con una firma ad-hoc (gratuita, suficiente para que Gatekeeper
   ofrezca el botón "Abrir de todos modos" en vez de bloquear con "dañado").
3. Publica el `.zip` firmado como un GitHub Release descargable.

También puedes disparar el build manualmente sin crear un tag: pestaña
**Actions** del repo → **Build & Sign Workbench (macOS)** → **Run workflow**.

## Desarrollo local

```bash
npm install
npm start
```
