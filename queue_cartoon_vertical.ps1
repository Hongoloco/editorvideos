param(
    [Parameter(Mandatory=$true)][string]$CartoonJobDir,
    [Parameter(Mandatory=$true)][string]$VerticalJobDir
)

$ErrorActionPreference = 'Stop'
$studioRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$cartoonStatus = Join-Path $CartoonJobDir 'status.txt'
$cartoonVideo = Join-Path $CartoonJobDir 'VIDEO_CARTOON_VIBRANTE_COMPLETO.mp4'
$verticalScript = Join-Path $studioRoot 'make_vertical_subtitled.ps1'
$monitorScript = Join-Path $studioRoot 'monitor_job.ps1'
$awakeScript = Join-Path $studioRoot 'keep_awake.ps1'

while ($true) {
    if (Test-Path -LiteralPath $cartoonStatus) {
        $status = Get-Content -LiteralPath $cartoonStatus -Raw -Encoding UTF8
        if ($status.StartsWith('DONE|')) { break }
        if ($status.StartsWith('ERROR|')) {
            New-Item -ItemType Directory -Path $VerticalJobDir -Force | Out-Null
            [IO.File]::WriteAllText(
                (Join-Path $VerticalJobDir 'status.txt'),
                'ERROR|0|La versión cartoon no terminó; no se inició la entrega vertical.',
                [Text.UTF8Encoding]::new($false)
            )
            exit 1
        }
    }
    Start-Sleep -Seconds 10
}

if (-not (Test-Path -LiteralPath $cartoonVideo)) {
    throw 'No se encontró el video cartoon terminado.'
}

New-Item -ItemType Directory -Path $VerticalJobDir -Force | Out-Null
$previousSubs = 'D:\Video\AnimeVideoStudio\jobs\20260804_VERTICAL_SUBTITULADO'
$previousSrt = Join-Path $previousSubs 'subtitulos_ingles.srt'
$previousAss = Join-Path $previousSubs 'subtitulos_vertical.ass'
if ((Test-Path -LiteralPath $previousSrt) -and (Test-Path -LiteralPath $previousAss)) {
    Copy-Item -LiteralPath $previousSrt -Destination (Join-Path $VerticalJobDir 'subtitulos_ingles.srt') -Force
    Copy-Item -LiteralPath $previousAss -Destination (Join-Path $VerticalJobDir 'subtitulos_vertical.ass') -Force
}

$monitorArgs = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$monitorScript`" -JobDir `"$VerticalJobDir`""
Start-Process -FilePath 'powershell.exe' -ArgumentList $monitorArgs -WindowStyle Hidden | Out-Null
$awakeArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$awakeScript`" -JobDir `"$VerticalJobDir`""
Start-Process -FilePath 'powershell.exe' -ArgumentList $awakeArgs -WindowStyle Hidden | Out-Null

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verticalScript -InputVideo $cartoonVideo -JobDir $VerticalJobDir
exit $LASTEXITCODE
