# Anime Video Studio

Aplicación local para analizar un video, comparar métodos y redibujarlo fotograma por fotograma.

## Método recomendado y gratuito

**Dibujo Anime Local — Gratis** funciona sin Internet, API, créditos ni suscripciones. Aplica siempre el mismo tratamiento para evitar parpadeos:

- suavizado de pintura;
- conservación de los colores originales;
- sombreado tipo cel adaptativo;
- contornos de tinta oscuros;
- restauración del audio, FPS y resolución del video original.

No es un modelo generativo y, por lo tanto, no inventa personajes o detalles como un servicio de IA. Su ventaja es que es gratuito, estable y compatible con este equipo.

## Uso

1. Abrir `INICIAR_ANIME_VIDEO_STUDIO.cmd`.
2. Elegir un video y pulsar **Analizar**.
3. Seleccionar **Dibujo Anime Local — Gratis**.
4. Pulsar **VISTA PREVIA 6 S**. El resultado se abre automáticamente.
5. Si el estilo sirve, pulsar **PROCESAR VIDEO**.

Los trabajos se guardan en `AnimeVideoStudio/jobs/`. El archivo original nunca se modifica.

## Editar cualquier tramo con EbSynth

Abrí `ABRIR_EBSYNTH_EDITOR.cmd` o pulsá **EDITAR TRAMO EBSYNTH** en la aplicación principal.

1. Elegí y analizá el video.
2. Escribí el tiempo de inicio y final del intervalo.
3. Prepará el tramo: la herramienta crea un MP4 720p y cinco fotogramas de referencia.
4. Editá o pintá los fotogramas en `https://ebsynth.com/app` y descargá el MP4.
5. Importá el resultado. La herramienta lo reinserta exactamente en su posición y restaura el audio original.

Para cubrir un video entero, pulsá **USAR VIDEO COMPLETO** y después **KEYFRAMES DE TODO EL VIDEO**. El sistema detecta cambios de escena, añade como máximo dos segundos entre cuadros de referencia y crea:

- `01_ORIGINALES`: fotogramas exactos del video;
- `02_CARTOON_VIBRANTE`: los mismos fotogramas estilizados;
- `keyframes_manifest.csv`: número, escena, frame y tiempo de cada keyframe.

La aplicación web gratuita de EbSynth requiere trabajo manual en el navegador y exporta hasta 720p. La automatización por línea de comandos pertenece al plan Studio de EbSynth.

## Generar todos los keyframes con IA local

Después de crear `KEYFRAMES_TODO_EL_VIDEO`, pulsá **GENERAR KEYFRAMES CON IA LOCAL** desde el editor EbSynth. También podés abrir `ABRIR_GENERADOR_IA_KEYFRAMES.cmd` y elegir esa carpeta manualmente.

1. Pulsá **INSTALAR IA LOCAL**. Descarga una vez `stable-diffusion.cpp`, Stable Diffusion 1.5, LCM y ControlNet Canny (aproximadamente 5,9 GB en total).
2. Elegí Anime, Cartoon o Cómic y ajustá la fuerza. `0.45` es el punto inicial recomendado; valores mayores redibujan más.
3. Usá **PROBAR 1 KEYFRAME** para ver el estilo.
4. Si sirve, pulsá **GENERAR TODOS**. Los resultados conservan los nombres originales en `03_IA_LOCAL`.
5. Si el proceso se interrumpe, volvé a pulsar **GENERAR TODOS**: omite automáticamente los PNG ya terminados.

El generador usa cada keyframe cartoon como imagen inicial, una semilla fija y el mismo prompt para reducir cambios de diseño. ControlNet Canny conserva los contornos del frame original y LCM permite trabajar en 2 a 8 pasos; el valor predeterminado es 4. En este equipo trabaja por CPU porque la GeForce 940MX tiene solo 2 GB de VRAM; un cuadro puede tardar varios minutos. La propagación final entre keyframes se realiza en EbSynth.

AnimeGANv3 Hayao y Shinkai siguen disponibles como métodos alternativos con aceleración DirectML. La difusión sobre cada fotograma del video completo continúa deshabilitada por falta de VRAM; el generador nuevo aplica difusión solo a los keyframes y delega los cuadros intermedios a EbSynth.

## Generar TODO el video con IA por fotograma (Nano Banan Pro)

Ahora existe un método directo en la app principal: **Nano Banan Pro — Video completo IA**.

Este modo:

- procesa cada fotograma del video con una API de imagen remota;
- reanuda si se corta (omite frames ya generados);
- arma automáticamente el MP4 y restaura resolución/FPS/audio original al final.

### Configuración rápida

Antes de abrir `INICIAR_ANIME_VIDEO_STUDIO.cmd`, definí estas variables de entorno en PowerShell:

```powershell
$env:NANO_BANAN_API_KEY = "tu_api_key"
$env:NANO_BANAN_BASE_URL = "https://api.openai.com/v1"   # opcional
$env:NANO_BANAN_MODEL = "gpt-image-1"                    # opcional
$env:NANO_BANAN_PROMPT = "hand-drawn 2D anime film frame, clean ink lines, cel shading, preserve composition"
$env:NANO_BANAN_NEGATIVE_PROMPT = "photorealistic, 3d render, watermark, logo, text"
```

### Uso

1. Abrí `INICIAR_ANIME_VIDEO_STUDIO.cmd`.
2. Elegí un video y pulsá **Analizar**.
3. En **Método**, seleccioná **Nano Banan Pro — Video completo IA**.
4. Probá primero **VISTA PREVIA 6 S**.
5. Si el estilo te gusta, pulsá **PROCESAR VIDEO**.

Los temporales de este modo quedan en la carpeta del trabajo dentro de `nanobanan_frames`.
