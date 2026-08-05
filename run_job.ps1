param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$MethodId,
    [Parameter(Mandatory=$true)][string]$JobDir,
    [Parameter(Mandatory=$true)][int]$OutputWidth,
    [Parameter(Mandatory=$true)][int]$OutputHeight,
    [int]$PreviewSeconds = 0
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
$python = Join-Path $toolRoot 'animeganv3\.venv-dml\Scripts\python.exe'
$animeScript = Join-Path $toolRoot 'animeganv3\video2anime.py'
$animeRoot = Join-Path $toolRoot 'animeganv3'
$freeScript = Join-Path $studioRoot 'free_anime_draw.py'
$nanoBananScript = Join-Path $studioRoot 'nanobanan_video_full.py'
$statusFile = Join-Path $JobDir 'status.txt'
$processingLog = Join-Path $JobDir 'processing.stderr.log'
$preparedInput = Join-Path $JobDir 'input_prepared_silent.mp4'
$processedVideo = Join-Path $JobDir 'processed_silent.mp4'
$animeOutDir = Join-Path $JobDir 'animegan_output'
$finalName = switch ($MethodId) {
    'free_cartoon_vibrant' {
        if ($PreviewSeconds -gt 0) { 'VISTA_PREVIA_CARTOON_VIBRANTE.mp4' } else { 'VIDEO_CARTOON_VIBRANTE_COMPLETO.mp4' }
    }
    'animeganv3_hayao' {
        if ($PreviewSeconds -gt 0) { 'VISTA_PREVIA_ANIMEGAN_HAYAO.mp4' } else { 'VIDEO_ANIMEGAN_HAYAO_COMPLETO.mp4' }
    }
    'animeganv3_shinkai' {
        if ($PreviewSeconds -gt 0) { 'VISTA_PREVIA_ANIMEGAN_SHINKAI.mp4' } else { 'VIDEO_ANIMEGAN_SHINKAI_COMPLETO.mp4' }
    }
    'nanobanan_pro_full' {
        if ($PreviewSeconds -gt 0) { 'VISTA_PREVIA_NANOBANAN_PRO.mp4' } else { 'VIDEO_NANOBANAN_PRO_COMPLETO.mp4' }
    }
    default {
        if ($PreviewSeconds -gt 0) { 'VISTA_PREVIA_ANIME_GRATIS.mp4' } else { 'VIDEO_ANIME_GRATIS_COMPLETO.mp4' }
    }
}
$final = Join-Path $JobDir $finalName

function Set-Status([string]$value) {
    [IO.File]::WriteAllText($statusFile, $value, [Text.UTF8Encoding]::new($false))
}

try {
    New-Item -ItemType Directory -Path $JobDir,$animeOutDir -Force | Out-Null
    $env:PATH = "$(Split-Path -Parent $ffmpeg);$env:PATH"

    $isFreeDraw = $MethodId -in @('free_anime_draw','free_cartoon_vibrant')
    $isNanoBanan = $MethodId -eq 'nanobanan_pro_full'
    $workingWidth = if ($isFreeDraw) { 960 } elseif ($isNanoBanan) { 768 } else { 640 }
    Set-Status 'PREPARING|0|Preparando el video sin modificar el original'
    $prepareArgs = @(
        '-hide_banner','-loglevel','warning','-i',$Source,
        '-map','0:v:0','-an','-vf',"scale=${workingWidth}:-2:flags=lanczos",
        '-c:v','libx264','-preset','fast','-crf','16'
    )
    if ($PreviewSeconds -gt 0) { $prepareArgs += @('-t',[string]$PreviewSeconds) }
    $prepareArgs += @($preparedInput,'-y')
    & $ffmpeg @prepareArgs 2> (Join-Path $JobDir 'prepare.log')
    if ($LASTEXITCODE -ne 0) { throw 'Falló la preparación del video.' }

    if ($isFreeDraw) {
        $drawStyle = if ($MethodId -eq 'free_cartoon_vibrant') { 'cartoon' } else { 'anime' }
        $drawMessage = if ($drawStyle -eq 'cartoon') { 'Aplicando paleta vibrante, tinta gruesa y sombreado cartoon' } else { 'Redibujando con tinta, color y sombreado cel' }
        Set-Status "DRAWING|0|$drawMessage"
        $drawArgs = @($freeScript,'--input',$preparedInput,'--output',$processedVideo,'--max-width','960','--levels','7','--strength','0.86','--style',$drawStyle)
        $drawProcess = Start-Process -FilePath $python -ArgumentList $drawArgs -Wait -PassThru -NoNewWindow -RedirectStandardError $processingLog
        if ($drawProcess.ExitCode -ne 0) { throw 'Falló el motor gratuito de dibujo.' }
    } elseif ($isNanoBanan) {
        Set-Status 'NANOBANAN|0|Preparando fotogramas para IA generativa'
        $nanoArgs = @(
            $nanoBananScript,
            '--input-video',$preparedInput,
            '--output-video',$processedVideo,
            '--status-file',$statusFile,
            '--work-dir',(Join-Path $JobDir 'nanobanan_frames'),
            '--ffmpeg',$ffmpeg,
            '--ffprobe',$ffprobe
        )
        $nanoProcess = Start-Process -FilePath $python -ArgumentList $nanoArgs -Wait -PassThru -NoNewWindow -RedirectStandardError $processingLog
        if ($nanoProcess.ExitCode -ne 0) { throw 'Falló Nano Banan Pro para video completo.' }
        if (-not (Test-Path -LiteralPath $processedVideo)) { throw 'Nano Banan Pro no produjo el video procesado.' }
    } else {
        $modelName = switch ($MethodId) {
            'animeganv3_hayao' { 'AnimeGANv3_Hayao_36.onnx' }
            'animeganv3_shinkai' { 'AnimeGANv3_Shinkai_37.onnx' }
            default { throw "El método $MethodId no está disponible localmente." }
        }
        $model = Join-Path $animeRoot $modelName
        Set-Status 'ANIMATING|0|Aplicando AnimeGAN fotograma por fotograma'
        $animeArgs = @($animeScript,'-i',$preparedInput,'-m',$model,'-o',$animeOutDir,'-d','dml')
        $animeProcess = Start-Process -FilePath $python -ArgumentList $animeArgs -Wait -PassThru -NoNewWindow -RedirectStandardError $processingLog
        if ($animeProcess.ExitCode -ne 0) { throw 'Falló AnimeGANv3.' }
        $base = [IO.Path]::GetFileNameWithoutExtension($preparedInput)
        $modelBase = [IO.Path]::GetFileNameWithoutExtension($model)
        $processedVideo = Join-Path $animeOutDir "${base}_${modelBase}.mp4"
        if (-not (Test-Path -LiteralPath $processedVideo)) { throw 'AnimeGANv3 no produjo el archivo esperado.' }
    }

    Set-Status 'CONFORMING|99|Restaurando resolución y audio originales'
    & $ffmpeg -hide_banner -loglevel warning -i $processedVideo -i $Source -map 0:v:0 -map 1:a:0? -vf "scale=${OutputWidth}:${OutputHeight}:flags=lanczos" -c:v libx264 -preset medium -crf 17 -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv -c:a aac -b:a 256k -shortest -movflags +faststart $final -y 2> (Join-Path $JobDir 'conform.log')
    if ($LASTEXITCODE -ne 0) { throw 'Falló el conformado final.' }
    & $ffprobe -v error -count_frames -show_entries stream=codec_type,width,height,r_frame_rate,nb_read_frames -show_entries format=duration,size -of json $final | Set-Content -LiteralPath (Join-Path $JobDir 'verification.json') -Encoding UTF8
    Set-Status "DONE|100|$final"
} catch {
    Set-Status "ERROR|0|$($_.Exception.Message)"
    throw
}
