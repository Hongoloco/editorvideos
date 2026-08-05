param(
    [string]$StatusFile = ''
)

$ErrorActionPreference = 'Stop'
$studioRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolRoot = Join-Path $studioRoot 'tools\stable-diffusion.cpp'
$modelRoot = Join-Path $studioRoot 'models'
$engine = Join-Path $toolRoot 'sd-server.exe'
$model = Join-Path $modelRoot 'v1-5-pruned-emaonly.safetensors'
$modelBytes = 4265146304L
$modelUrl = 'https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors'
$modelSha256 = '6CE0161689B3853ACAA03779EC93EAFE75A02F4CED659BEE03F50797806FA2FA'
$lcmLora = Join-Path $modelRoot 'lcm-lora-sdv1-5.safetensors'
$lcmLoraBytes = 134621556L
$lcmLoraUrl = 'https://huggingface.co/latent-consistency/lcm-lora-sdv1-5/resolve/main/pytorch_lora_weights.safetensors'
$lcmLoraSha256 = '8F90D840E075FF588A58E22C6586E2AE9A6F7922996EE6649A7F01072333AFE4'
$controlNet = Join-Path $modelRoot 'control_v11p_sd15_canny.pth'
$controlNetBytes = 1445234681L
$controlNetUrl = 'https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11p_sd15_canny.pth'
$controlNetSha256 = 'F99CFE4C70910E38E3FECE9918A4979ED7D3DCF9B81CEE293E1755363AF5406A'

if (-not $StatusFile) { $StatusFile = Join-Path $studioRoot 'local_ai_install_status.txt' }

function Set-Status([string]$stage,[int]$percent,[string]$message) {
    $temporary = "$StatusFile.tmp"
    [IO.File]::WriteAllText($temporary,"$stage|$percent|$message",[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $StatusFile -Force
}

function Download-WithProgress([string]$url,[string]$destination,[long]$expectedBytes,[int]$startPercent,[int]$endPercent,[string]$label) {
    $partial = "$destination.part"
    $log = "$destination.download.log"
    if ($expectedBytes -gt 0 -and (Test-Path -LiteralPath $partial) -and (Get-Item -LiteralPath $partial).Length -ge $expectedBytes) {
        Move-Item -LiteralPath $partial -Destination $destination -Force
        return
    }
    $arguments = '-L --fail --retry 5 --retry-delay 3 -C - -o "{0}" "{1}"' -f $partial,$url
    $process = Start-Process -FilePath 'curl.exe' -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardError $log
    while (-not $process.HasExited) {
        $downloaded = if (Test-Path -LiteralPath $partial) { (Get-Item -LiteralPath $partial).Length } else { 0L }
        $fraction = if ($expectedBytes -gt 0) { [Math]::Min(1.0,$downloaded / $expectedBytes) } else { 0.0 }
        $percent = $startPercent + [int][Math]::Floor(($endPercent - $startPercent) * $fraction)
        Set-Status 'INSTALLING' $percent ("{0}: {1:N2} / {2:N2} GB" -f $label,($downloaded / 1GB),($expectedBytes / 1GB))
        Start-Sleep -Seconds 2
        $process.Refresh()
    }
    if ($process.ExitCode -ne 0) { throw "No se pudo descargar $label. Revisá $log" }
    if ($expectedBytes -gt 0 -and (Get-Item -LiteralPath $partial).Length -lt $expectedBytes) { throw "La descarga de $label quedó incompleta." }
    Move-Item -LiteralPath $partial -Destination $destination -Force
}

try {
    New-Item -ItemType Directory -Path $toolRoot,$modelRoot -Force | Out-Null
    if (-not (Test-Path -LiteralPath $engine)) {
        Set-Status 'INSTALLING' 2 'Buscando la versión actual del motor local'
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/leejet/stable-diffusion.cpp/releases/latest' -Headers @{ 'User-Agent'='AnimeVideoStudio' }
        $asset = $release.assets | Where-Object name -Like '*bin-win-cpu-x64.zip' | Select-Object -First 1
        if (-not $asset) { throw 'No se encontró el ejecutable CPU para Windows.' }
        $zip = Join-Path $toolRoot 'sd-win-cpu.zip'
        Download-WithProgress $asset.browser_download_url $zip ([long]$asset.size) 3 10 'Motor local'
        Set-Status 'INSTALLING' 11 'Descomprimiendo el motor local'
        Expand-Archive -LiteralPath $zip -DestinationPath $toolRoot -Force
        if (-not (Test-Path -LiteralPath $engine)) { throw 'El paquete no contenía sd-server.exe.' }
    }

    if (-not (Test-Path -LiteralPath $model) -or (Get-Item -LiteralPath $model).Length -lt $modelBytes) {
        Set-Status 'INSTALLING' 12 'Descargando Stable Diffusion 1.5 (se hace una sola vez)'
        Download-WithProgress $modelUrl $model $modelBytes 12 82 'Modelo SD 1.5'
    }
    if (-not (Test-Path -LiteralPath $lcmLora) -or (Get-Item -LiteralPath $lcmLora).Length -lt $lcmLoraBytes) {
        Set-Status 'INSTALLING' 83 'Descargando acelerador LCM (135 MB)'
        Download-WithProgress $lcmLoraUrl $lcmLora $lcmLoraBytes 83 87 'Acelerador LCM'
    }
    if (-not (Test-Path -LiteralPath $controlNet) -or (Get-Item -LiteralPath $controlNet).Length -lt $controlNetBytes) {
        Set-Status 'INSTALLING' 88 'Descargando guía de contornos ControlNet (1,45 GB)'
        Download-WithProgress $controlNetUrl $controlNet $controlNetBytes 88 98 'ControlNet Canny'
    }

    Set-Status 'VERIFYING' 99 'Verificando integridad SHA-256 de los modelos'
    if ((Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ne $modelSha256) { throw 'El modelo SD 1.5 no superó la verificación SHA-256.' }
    if ((Get-FileHash -LiteralPath $lcmLora -Algorithm SHA256).Hash -ne $lcmLoraSha256) { throw 'El acelerador LCM no superó la verificación SHA-256.' }
    if ((Get-FileHash -LiteralPath $controlNet -Algorithm SHA256).Hash -ne $controlNetSha256) { throw 'ControlNet Canny no superó la verificación SHA-256.' }

    $metadata = [pscustomobject]@{
        engine = 'stable-diffusion.cpp'
        engine_license = 'MIT'
        engine_url = 'https://github.com/leejet/stable-diffusion.cpp'
        model = 'Stable Diffusion v1.5 ema-only'
        model_license = 'CreativeML OpenRAIL-M'
        model_url = 'https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5'
        model_sha256 = $modelSha256
        accelerator = 'LCM-LoRA SD 1.5'
        accelerator_license = 'OpenRAIL++'
        accelerator_url = 'https://huggingface.co/latent-consistency/lcm-lora-sdv1-5'
        accelerator_sha256 = $lcmLoraSha256
        controlnet = 'ControlNet v1.1 Canny original'
        controlnet_license = 'CreativeML OpenRAIL-M'
        controlnet_url = 'https://huggingface.co/lllyasviel/ControlNet-v1-1'
        controlnet_sha256 = $controlNetSha256
        installed_at = (Get-Date).ToString('o')
    } | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path $modelRoot 'local_ai_install.json'),$metadata,[Text.UTF8Encoding]::new($false))
    Set-Status 'DONE' 100 'Motor y modelo local listos'
} catch {
    Set-Status 'ERROR' 0 $_.Exception.Message
    throw
}
