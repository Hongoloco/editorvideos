param(
    [Parameter(Mandatory=$true)][string]$InputVideo,
    [Parameter(Mandatory=$true)][string]$JobDir
)

$ErrorActionPreference = 'Stop'
$studioRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolRoot = Join-Path $studioRoot 'tools'
if (-not (Test-Path -LiteralPath $toolRoot)) {
    $workspace = Split-Path -Parent $studioRoot
    $toolRoot = Join-Path $workspace 'REARRANGED_2D\tools'
}
$ffmpeg = Join-Path $toolRoot 'ffmpeg\ffmpeg.exe'
$ffprobe = Join-Path $toolRoot 'ffmpeg\ffprobe.exe'
$python = Join-Path $studioRoot '.venv-subtitles\Scripts\python.exe'
$transcriber = Join-Path $studioRoot 'transcribe_subtitles.py'
$statusFile = Join-Path $JobDir 'status.txt'
$logFile = Join-Path $JobDir 'processing.stderr.log'
$srt = Join-Path $JobDir 'subtitulos_ingles.srt'
$ass = Join-Path $JobDir 'subtitulos_vertical.ass'
$output = Join-Path $JobDir 'VIDEO_ANIME_VERTICAL_9x16_SUBTITULADO.mp4'

function Set-Status([string]$value) {
    [IO.File]::WriteAllText($statusFile, $value, [Text.UTF8Encoding]::new($false))
}

try {
    New-Item -ItemType Directory -Path $JobDir -Force | Out-Null
    if (-not (Test-Path -LiteralPath $InputVideo)) { throw 'No se encontró el video anime terminado.' }
    if (-not (Test-Path -LiteralPath $python)) { throw 'No se encontró el transcriptor local.' }

    if (-not ((Test-Path -LiteralPath $srt) -and (Test-Path -LiteralPath $ass))) {
        Set-Status 'TRANSCRIBING|0|Descargando el modelo la primera vez y escuchando el diálogo en inglés'
        $env:HF_HUB_DISABLE_SYMLINKS_WARNING = '1'
        $transcribeArgs = @($transcriber,'--input',$InputVideo,'--srt',$srt,'--ass',$ass,'--model','small.en')
        $process = Start-Process -FilePath $python -ArgumentList $transcribeArgs -Wait -PassThru -NoNewWindow -RedirectStandardError $logFile
        if ($process.ExitCode -ne 0) { throw 'Falló la generación automática de subtítulos.' }
    }
    if (-not (Test-Path -LiteralPath $ass)) { throw 'No se generó el archivo de subtítulos.' }

    Set-Status 'FORMATTING|75|Creando lienzo vertical 1080x1920 y quemando los subtítulos'
    $assPath = $ass.Replace('\','/').Replace(':','\:')
    $filter = "[0:v]split=2[bg][fg];[bg]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=luma_radius=35:luma_power=2,eq=brightness=-0.12:saturation=0.82[bgv];[fg]scale=1080:1080:force_original_aspect_ratio=decrease[fgv];[bgv][fgv]overlay=(W-w)/2:(H-h)/2[base];[base]ass='$assPath'[vout]"
    & $ffmpeg -hide_banner -loglevel warning -i $InputVideo -i $srt -filter_complex $filter -map '[vout]' -map 0:a:0? -map 1:0 -c:v libx264 -preset faster -crf 18 -pix_fmt yuv420p -c:a copy -c:s mov_text -metadata:s:s:0 language=eng -metadata:s:s:0 title='English captions' -movflags +faststart $output -y 2> (Join-Path $JobDir 'vertical_render.log')
    if ($LASTEXITCODE -ne 0) { throw 'Falló la creación del video vertical.' }

    & $ffprobe -v error -count_frames -show_entries stream=index,codec_type,codec_name,width,height,r_frame_rate,nb_read_frames:stream_tags=language,title -show_entries format=duration,size -of json $output | Set-Content -LiteralPath (Join-Path $JobDir 'verification.json') -Encoding UTF8
    Set-Status "DONE|100|$output"
} catch {
    Set-Status "ERROR|0|$($_.Exception.Message)"
    throw
}
