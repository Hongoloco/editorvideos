param(
    [Parameter(Mandatory=$true)][ValidateSet('Prepare','GenerateAllKeyframes','Reintegrate')][string]$Action,
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][double]$StartSeconds,
    [Parameter(Mandatory=$true)][double]$EndSeconds,
    [Parameter(Mandatory=$true)][string]$JobDir,
    [string]$EditedVideo = ''
)

$ErrorActionPreference = 'Stop'
$studioRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$workspace = Split-Path -Parent $studioRoot
$ffmpeg = Join-Path $workspace 'REARRANGED_2D\tools\ffmpeg\ffmpeg.exe'
$ffprobe = Join-Path $workspace 'REARRANGED_2D\tools\ffmpeg\ffprobe.exe'
$statusFile = Join-Path $JobDir 'status.txt'
$segment = Join-Path $JobDir 'TRAMO_PARA_EBSYNTH_720p.mp4'
$keysDir = Join-Path $JobDir 'FOTOGRAMAS_CLAVE'
$python = Join-Path $workspace 'REARRANGED_2D\tools\animeganv3\.venv-dml\Scripts\python.exe'
$allKeyframesScript = Join-Path $studioRoot 'generate_all_keyframes.py'

function Set-Status([string]$value) {
    [IO.File]::WriteAllText($statusFile, $value, [Text.UTF8Encoding]::new($false))
}

function Encode-Part([string]$InputPath, [string]$OutputPath, [string]$VideoFilter, [string[]]$TimeArguments) {
    $arguments = @('-hide_banner','-loglevel','warning') + $TimeArguments + @(
        '-i',$InputPath,'-map','0:v:0','-an','-vf',$VideoFilter,
        '-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p',$OutputPath,'-y'
    )
    & $ffmpeg @arguments 2> (Join-Path $JobDir (([IO.Path]::GetFileNameWithoutExtension($OutputPath)) + '.log'))
    if ($LASTEXITCODE -ne 0) { throw "Falló la creación de $([IO.Path]::GetFileName($OutputPath))." }
}

try {
    New-Item -ItemType Directory -Path $JobDir,$keysDir -Force | Out-Null
    if (-not (Test-Path -LiteralPath $Source)) { throw 'No se encontró el video original.' }
    $duration = $EndSeconds - $StartSeconds
    if ($StartSeconds -lt 0 -or $duration -le 0.05) { throw 'El intervalo de tiempo no es válido.' }
    $startArgument = $StartSeconds.ToString('0.######',[Globalization.CultureInfo]::InvariantCulture)
    $endArgument = $EndSeconds.ToString('0.######',[Globalization.CultureInfo]::InvariantCulture)
    $durationArgument = $duration.ToString('0.######',[Globalization.CultureInfo]::InvariantCulture)

    $sourceInfo = & $ffprobe -v error -show_streams -show_format -of json $Source | ConvertFrom-Json
    $videoStream = $sourceInfo.streams | Where-Object codec_type -eq 'video' | Select-Object -First 1
    $sourceDuration = [double]$sourceInfo.format.duration
    if ($EndSeconds -gt $sourceDuration + 0.02) { throw 'El final del tramo supera la duración del video.' }

    if ($Action -eq 'GenerateAllKeyframes') {
        $jobMetadata = [pscustomobject]@{
            source = $Source
            start_seconds = $StartSeconds
            end_seconds = $EndSeconds
            created_at = (Get-Date).ToString('o')
            mode = 'all_keyframes'
        } | ConvertTo-Json
        [IO.File]::WriteAllText((Join-Path $JobDir 'job.json'),$jobMetadata,[Text.UTF8Encoding]::new($false))
        Set-Status 'PREPARING|5|Preparando el intervalo completo a 720p para analizarlo'
        $filter720 = 'scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:black,setsar=1'
        & $ffmpeg -hide_banner -loglevel warning -ss $startArgument -i $Source -t $durationArgument -map 0:v:0 -an -vf $filter720 -c:v libx264 -preset fast -crf 17 -pix_fmt yuv420p -movflags +faststart $segment -y 2> (Join-Path $JobDir 'prepare_all_keyframes.log')
        if ($LASTEXITCODE -ne 0) { throw 'Falló la preparación del video para generar keyframes.' }
        $outputKeys = Join-Path $JobDir 'KEYFRAMES_TODO_EL_VIDEO'
        Set-Status 'ALL_KEYFRAMES|10|Detectando escenas y creando keyframes cartoon'
        $keyArgs = @($allKeyframesScript,'--input',$segment,'--output-dir',$outputKeys,'--status-file',$statusFile,'--interval','2.0','--scene-threshold','0.43','--min-gap','0.60')
        $keyProcess = Start-Process -FilePath $python -ArgumentList $keyArgs -Wait -PassThru -NoNewWindow -RedirectStandardError (Join-Path $JobDir 'all_keyframes.log')
        if ($keyProcess.ExitCode -ne 0) { throw 'Falló la generación automática de keyframes.' }
        if (-not (Test-Path -LiteralPath (Join-Path $outputKeys 'keyframes_manifest.csv'))) { throw 'No se creó el manifiesto de keyframes.' }
        Set-Status "DONE|100|$outputKeys"
        exit 0
    }

    if ($Action -eq 'Prepare') {
        $jobMetadata = [pscustomobject]@{
            source = $Source
            start_seconds = $StartSeconds
            end_seconds = $EndSeconds
            created_at = (Get-Date).ToString('o')
        } | ConvertTo-Json
        [IO.File]::WriteAllText((Join-Path $JobDir 'job.json'),$jobMetadata,[Text.UTF8Encoding]::new($false))
        Set-Status 'PREPARING|10|Extrayendo el tramo seleccionado a 720p para EbSynth Free'
        $filter720 = 'scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:black,setsar=1'
        & $ffmpeg -hide_banner -loglevel warning -ss $startArgument -i $Source -t $durationArgument -map 0:v:0 -map 0:a:0? -vf $filter720 -c:v libx264 -preset fast -crf 17 -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart $segment -y 2> (Join-Path $JobDir 'prepare_segment.log')
        if ($LASTEXITCODE -ne 0) { throw 'Falló la extracción del tramo para EbSynth.' }

        Set-Status 'KEYFRAMES|65|Extrayendo fotogramas de referencia del tramo'
        $lastPosition = [Math]::Max([double]0.0,[double]($duration - 0.05))
        [double[]]$positions = @(0.0, ($duration * 0.25), ($duration * 0.5), ($duration * 0.75), $lastPosition)
        for ($index = 0; $index -lt $positions.Count; $index++) {
            $framePath = Join-Path $keysDir ('keyframe_{0:D2}_{1:F3}s.png' -f ($index + 1),$positions[$index])
            $positionArgument = $positions[$index].ToString('0.######',[Globalization.CultureInfo]::InvariantCulture)
            & $ffmpeg -hide_banner -loglevel error -ss $positionArgument -i $segment -frames:v 1 $framePath -y
            if ($LASTEXITCODE -ne 0) { throw 'Falló la extracción de fotogramas clave.' }
        }

        $instructions = @"
TRAMO EBSYNTH
==============
Inicio en el video original: $StartSeconds segundos
Final en el video original: $EndSeconds segundos
Duración: $duration segundos

1. Abrí https://ebsynth.com/app en Chrome.
2. Cargá TRAMO_PARA_EBSYNTH_720p.mp4.
3. Elegí uno o más cuadros de FOTOGRAMAS_CLAVE y editá/pintá esos cuadros.
4. Renderizá y descargá el resultado MP4.
5. En Anime Video Studio, usá "Importar resultado" para reinsertarlo.

El tramo exportado por EbSynth debe conservar la misma duración.
"@
        [IO.File]::WriteAllText((Join-Path $JobDir 'INSTRUCCIONES_EBSYNTH.txt'),$instructions,[Text.UTF8Encoding]::new($false))
        Set-Status "DONE|100|$segment"
        exit 0
    }

    if (-not (Test-Path -LiteralPath $EditedVideo)) { throw 'Seleccioná el MP4 descargado desde EbSynth.' }
    Set-Status 'CONFORMING|10|Ajustando el resultado de EbSynth al tramo original'
    $width = [int]$videoStream.width
    $height = [int]$videoStream.height
    $fps = [string]$videoStream.avg_frame_rate
    $fitFilter = "fps=$fps,scale=${width}:${height}:force_original_aspect_ratio=decrease,pad=${width}:${height}:(ow-iw)/2:(oh-ih)/2:black,tpad=stop_mode=clone:stop_duration=$durationArgument,trim=duration=$durationArgument,setpts=PTS-STARTPTS,setsar=1"
    $editedConformed = Join-Path $JobDir '02_ebsynth_conformado.mp4'
    Encode-Part -InputPath $EditedVideo -OutputPath $editedConformed -VideoFilter $fitFilter -TimeArguments @()

    $parts = [System.Collections.Generic.List[string]]::new()
    $baseFilter = "fps=$fps,scale=${width}:${height}:force_original_aspect_ratio=decrease,pad=${width}:${height}:(ow-iw)/2:(oh-ih)/2:black,setsar=1"
    if ($StartSeconds -gt 0.02) {
        Set-Status 'REINTEGRATING|30|Preparando la parte anterior al tramo'
        $before = Join-Path $JobDir '01_antes.mp4'
        Encode-Part -InputPath $Source -OutputPath $before -VideoFilter $baseFilter -TimeArguments @('-t',$startArgument)
        $parts.Add($before)
    }
    $parts.Add($editedConformed)
    if ($EndSeconds -lt $sourceDuration - 0.02) {
        Set-Status 'REINTEGRATING|60|Preparando la parte posterior al tramo'
        $after = Join-Path $JobDir '03_despues.mp4'
        Encode-Part -InputPath $Source -OutputPath $after -VideoFilter $baseFilter -TimeArguments @('-ss',$endArgument)
        $parts.Add($after)
    }

    $concatList = Join-Path $JobDir 'concat.txt'
    $listLines = $parts | ForEach-Object { "file '$($_.Replace('\','/').Replace("'","''"))'" }
    [IO.File]::WriteAllLines($concatList,$listLines,[Text.UTF8Encoding]::new($false))
    $silentFull = Join-Path $JobDir '04_video_completo_sin_audio.mp4'
    & $ffmpeg -hide_banner -loglevel warning -f concat -safe 0 -i $concatList -c copy $silentFull -y 2> (Join-Path $JobDir 'concat.log')
    if ($LASTEXITCODE -ne 0) { throw 'Falló la unión del tramo editado.' }

    Set-Status 'FINISHING|90|Restaurando el audio original'
    $final = Join-Path $JobDir 'VIDEO_CON_TRAMO_EBSYNTH.mp4'
    & $ffmpeg -hide_banner -loglevel warning -i $silentFull -i $Source -map 0:v:0 -map 1:a:0? -c:v copy -c:a copy -shortest -movflags +faststart $final -y 2> (Join-Path $JobDir 'audio.log')
    if ($LASTEXITCODE -ne 0) { throw 'Falló la restauración del audio.' }
    & $ffprobe -v error -show_streams -show_format -of json $final | Set-Content -LiteralPath (Join-Path $JobDir 'verification.json') -Encoding UTF8
    Set-Status "DONE|100|$final"
} catch {
    Set-Status "ERROR|0|$($_.Exception.Message)"
    throw
}
