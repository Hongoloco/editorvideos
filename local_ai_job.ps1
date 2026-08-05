param(
    [Parameter(Mandatory=$true)][ValidateSet('Preview','All')][string]$Action,
    [Parameter(Mandatory=$true)][string]$KeyframesRoot,
    [Parameter(Mandatory=$true)][string]$PromptBase64,
    [Parameter(Mandatory=$true)][string]$NegativePromptBase64,
    [Parameter(Mandatory=$true)][double]$Strength,
    [Parameter(Mandatory=$true)][int]$Steps,
    [Parameter(Mandatory=$true)][long]$Seed,
    [Parameter(Mandatory=$true)][string]$StatusFile
)

$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class AnimeVideoPowerState {
    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint flags);
}
'@
[uint32]$ES_CONTINUOUS = 2147483648
[uint32]$ES_SYSTEM_REQUIRED = 1
[AnimeVideoPowerState]::SetThreadExecutionState([uint32]($ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED)) | Out-Null
$Prompt = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($PromptBase64))
$NegativePrompt = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($NegativePromptBase64))
$studioRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$workspace = Split-Path -Parent $studioRoot
$engineRoot = Join-Path $studioRoot 'tools\stable-diffusion.cpp'
$serverExe = Join-Path $engineRoot 'sd-server.exe'
$model = Join-Path $studioRoot 'models\v1-5-pruned-emaonly.safetensors'
$lcmLora = Join-Path $studioRoot 'models\lcm-lora-sdv1-5.safetensors'
$controlNet = Join-Path $studioRoot 'models\control_v11p_sd15_canny.pth'
$ffmpeg = Join-Path $workspace 'REARRANGED_2D\tools\ffmpeg\ffmpeg.exe'
$python = Join-Path $workspace 'REARRANGED_2D\tools\animeganv3\.venv-dml\Scripts\python.exe'
$previewSelector = Join-Path $studioRoot 'select_preview_keyframe.py'
$controlMaker = Join-Path $studioRoot 'make_canny_control.py'
$inputDir = if (Test-Path -LiteralPath (Join-Path $KeyframesRoot '02_CARTOON_VIBRANTE')) { Join-Path $KeyframesRoot '02_CARTOON_VIBRANTE' } else { Join-Path $KeyframesRoot '01_ORIGINALES' }
$outputDir = Join-Path $KeyframesRoot '03_IA_LOCAL'
$tempDir = Join-Path $KeyframesRoot '.ia_temp'
$serverLog = Join-Path $KeyframesRoot 'ia_server.log'
$serverErrorLog = Join-Path $KeyframesRoot 'ia_server_error.log'
$port = 17868
$baseUrl = "http://127.0.0.1:$port"
$serverProcess = $null

function Set-Status([string]$stage,[int]$percent,[string]$message) {
    $temporary = "$StatusFile.tmp"
    [IO.File]::WriteAllText($temporary,"$stage|$percent|$message",[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $StatusFile -Force
}

function Wait-ForServer {
    for ($attempt = 0; $attempt -lt 360; $attempt++) {
        if ($serverProcess.HasExited) { throw "El motor local se cerró durante la carga. Revisá $serverErrorLog" }
        try {
            Invoke-RestMethod -Uri "$baseUrl/sdcpp/v1/capabilities" -Method Get -TimeoutSec 3 | Out-Null
            return
        } catch {
            $percent = [Math]::Min(12,2 + [int]($attempt / 36))
            Set-Status 'LOADING_AI' $percent 'Cargando el modelo en memoria; puede demorar varios minutos'
            Start-Sleep -Seconds 2
        }
    }
    throw 'El motor local no terminó de cargar dentro del tiempo esperado.'
}

function Generate-One([IO.FileInfo]$image,[string]$destination,[int]$position,[int]$total) {
    $prepared = Join-Path $tempDir ("prepared_{0:D4}.png" -f $position)
    $controlImage = Join-Path $tempDir ("control_{0:D4}.png" -f $position)
    & $ffmpeg -hide_banner -loglevel error -i $image.FullName -vf 'scale=512:288:force_original_aspect_ratio=decrease,pad=512:288:(ow-iw)/2:(oh-ih)/2:black,setsar=1' -frames:v 1 $prepared -y
    if ($LASTEXITCODE -ne 0) { throw "No se pudo preparar $($image.Name)." }
    $originalImage = Join-Path (Join-Path $KeyframesRoot '01_ORIGINALES') $image.Name
    $controlSource = if (Test-Path -LiteralPath $originalImage) { $originalImage } else { $image.FullName }
    $controlMetricsText = (& $python $controlMaker --input $controlSource --output $controlImage --width 512 --height 288 | Select-Object -Last 1)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $controlImage)) { throw "No se pudo crear la guía de contornos para $($image.Name)." }
    $controlMetrics = $controlMetricsText | ConvertFrom-Json
    if ([double]$controlMetrics.edge_density -lt 0.002) {
        Copy-Item -LiteralPath $image.FullName -Destination $destination -Force
        return
    }
    $base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($prepared))
    $controlBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($controlImage))
    $payload = [ordered]@{
        prompt = $Prompt
        negative_prompt = $NegativePrompt
        init_image = $base64
        control_image = $controlBase64
        width = 512
        height = 288
        strength = $Strength
        seed = $Seed
        batch_count = 1
        control_strength = 0.90
        auto_resize_ref_image = $true
        sample_params = [ordered]@{
            scheduler = 'discrete'
            sample_method = 'lcm'
            sample_steps = $Steps
            guidance = [ordered]@{ txt_cfg = 1.0; distilled_guidance = 3.5 }
        }
        lora = @([ordered]@{ path = 'lcm-lora-sdv1-5.safetensors'; multiplier = 1.0; is_high_noise = $false })
        vae_tiling_params = [ordered]@{ enabled = $false }
        output_format = 'png'
        output_compression = 100
    } | ConvertTo-Json -Depth 5 -Compress
    $basePercent = 15 + [int](80 * (($position - 1) / [Math]::Max($total,1)))
    Set-Status 'GENERATING_AI' $basePercent ("Generando keyframe {0}/{1}: {2}" -f $position,$total,$image.Name)
    $submission = Invoke-RestMethod -Uri "$baseUrl/sdcpp/v1/img_gen" -Method Post -ContentType 'application/json' -Body $payload -TimeoutSec 120
    if (-not $submission.id) { throw "El motor no aceptó el trabajo para $($image.Name)." }
    do {
        Start-Sleep -Seconds 2
        $response = Invoke-RestMethod -Uri "$baseUrl/sdcpp/v1/jobs/$($submission.id)" -Method Get -TimeoutSec 30
    } while ($response.status -in @('queued','generating'))
    if ($response.status -ne 'completed') {
        $reason = if ($response.error.message) { $response.error.message } else { "estado $($response.status)" }
        throw "Falló la IA para $($image.Name): $reason"
    }
    if (-not $response.result.images -or $response.result.images.Count -lt 1) { throw "El motor no devolvió una imagen para $($image.Name)." }
    $smallOutput = Join-Path $tempDir ("generated_{0:D4}.png" -f $position)
    [IO.File]::WriteAllBytes($smallOutput,[Convert]::FromBase64String([string]$response.result.images[0].b64_json))
    & $ffmpeg -hide_banner -loglevel error -i $smallOutput -vf 'scale=1280:720:flags=lanczos,setsar=1' -frames:v 1 $destination -y
    if ($LASTEXITCODE -ne 0) { throw "No se pudo guardar $destination." }
}

try {
    if (-not (Test-Path -LiteralPath $serverExe)) { throw 'Falta el motor local. Pulsá INSTALAR IA LOCAL primero.' }
    if (-not (Test-Path -LiteralPath $model) -or (Get-Item -LiteralPath $model).Length -lt 4000000000L) { throw 'Falta el modelo SD 1.5. Pulsá INSTALAR IA LOCAL primero.' }
    if (-not (Test-Path -LiteralPath $lcmLora) -or (Get-Item -LiteralPath $lcmLora).Length -lt 100MB) { throw 'Falta el acelerador LCM. Volvé a pulsar INSTALAR IA LOCAL.' }
    if (-not (Test-Path -LiteralPath $controlNet) -or (Get-Item -LiteralPath $controlNet).Length -lt 1400000000L) { throw 'Falta ControlNet Canny. Volvé a pulsar INSTALAR IA LOCAL.' }
    if (-not (Test-Path -LiteralPath $controlMaker)) { throw 'Falta el generador de contornos Canny.' }
    if (-not (Test-Path -LiteralPath $inputDir)) { throw 'No se encontró la carpeta 01_ORIGINALES o 02_CARTOON_VIBRANTE.' }
    New-Item -ItemType Directory -Path $outputDir,$tempDir -Force | Out-Null
    $images = @(Get-ChildItem -LiteralPath $inputDir -File -Filter '*.png' | Sort-Object Name)
    if ($images.Count -eq 0) { throw 'La carpeta de keyframes no contiene imágenes PNG.' }
    if ($Action -eq 'Preview') {
        $originalsDir = Join-Path $KeyframesRoot '01_ORIGINALES'
        $selectionDir = if (Test-Path -LiteralPath $originalsDir) { $originalsDir } else { $inputDir }
        $selectedPath = if ((Test-Path -LiteralPath $python) -and (Test-Path -LiteralPath $previewSelector)) { (& $python $previewSelector --input-dir $selectionDir | Select-Object -Last 1).Trim() } else { '' }
        $selectedInput = if ($selectedPath) { Join-Path $inputDir ([IO.Path]::GetFileName($selectedPath)) } else { '' }
        $selected = if ($selectedInput -and (Test-Path -LiteralPath $selectedInput)) { Get-Item -LiteralPath $selectedInput } else { $images[[Math]::Floor($images.Count / 2)] }
        $images = @($selected)
    }

    $config = [pscustomobject]@{
        input_folder = $inputDir
        output_folder = $outputDir
        prompt = $Prompt
        negative_prompt = $NegativePrompt
        strength = $Strength
        steps = $Steps
        seed = $Seed
        action = $Action
        generated_at = (Get-Date).ToString('o')
    } | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path $KeyframesRoot 'generacion_ia.json'),$config,[Text.UTF8Encoding]::new($false))

    Set-Status 'LOADING_AI' 1 'Iniciando Stable Diffusion local en CPU'
    $arguments = '--model "{0}" --control-net "{1}" --lora-model-dir "{2}" --backend cpu --params-backend cpu --threads 4 --mmap --listen-ip 127.0.0.1 --listen-port {3}' -f $model,$controlNet,(Split-Path -Parent $lcmLora),$port
    $serverProcess = Start-Process -FilePath $serverExe -ArgumentList $arguments -WorkingDirectory $engineRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput $serverLog -RedirectStandardError $serverErrorLog
    Wait-ForServer

    $generated = 0
    $skipped = 0
    for ($index = 0; $index -lt $images.Count; $index++) {
        $image = $images[$index]
        $destination = if ($Action -eq 'Preview') { Join-Path $KeyframesRoot 'PREVIEW_IA_LOCAL.png' } else { Join-Path $outputDir $image.Name }
        if ($Action -eq 'All' -and (Test-Path -LiteralPath $destination) -and (Get-Item -LiteralPath $destination).Length -gt 10000) {
            $skipped++
            Set-Status 'GENERATING_AI' (15 + [int](80 * (($index + 1) / $images.Count))) ("Reanudando: keyframe {0}/{1} ya existía" -f ($index + 1),$images.Count)
            continue
        }
        Generate-One $image $destination ($index + 1) $images.Count
        $generated++
    }

    $summary = @"
KEYFRAMES GENERADOS CON IA LOCAL
================================
Entrada: $inputDir
Salida: $outputDir
Generados ahora: $generated
Omitidos por reanudación: $skipped
Total: $($images.Count)
Fuerza imagen-a-imagen: $Strength
Pasos: $Steps
Semilla fija: $Seed

Los nombres se conservan para mantener la correspondencia temporal con EbSynth.
"@
    [IO.File]::WriteAllText((Join-Path $KeyframesRoot 'RESUMEN_IA_LOCAL.txt'),$summary,[Text.UTF8Encoding]::new($false))
    $result = if ($Action -eq 'Preview') { Join-Path $KeyframesRoot 'PREVIEW_IA_LOCAL.png' } else { $outputDir }
    Set-Status 'DONE' 100 $result
} catch {
    Set-Status 'ERROR' 0 $_.Exception.Message
    throw
} finally {
    if ($serverProcess -and -not $serverProcess.HasExited) { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
    [AnimeVideoPowerState]::SetThreadExecutionState($ES_CONTINUOUS) | Out-Null
}
