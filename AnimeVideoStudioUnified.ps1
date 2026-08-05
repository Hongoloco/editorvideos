param(
    [ValidateSet('main','ebsynth','localai')][string]$StartTab = 'main',
    [string]$KeyframesRoot = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms

$studioRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolRoot = Join-Path $studioRoot 'tools'
if (-not (Test-Path -LiteralPath $toolRoot)) {
    $workspace = Split-Path -Parent $studioRoot
    $toolRoot = Join-Path $workspace 'REARRANGED_2D\tools'
}

$ffprobe    = Join-Path $toolRoot 'ffmpeg\ffprobe.exe'
$mainRunner = Join-Path $studioRoot 'run_job.ps1'
$ebWorker   = Join-Path $studioRoot 'ebsynth_job.ps1'
$aiInstaller = Join-Path $studioRoot 'install_local_ai.ps1'
$aiWorker   = Join-Path $studioRoot 'local_ai_job.ps1'
$mainMethods = Get-Content -LiteralPath (Join-Path $studioRoot 'methods.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$jobsRoot   = Join-Path $studioRoot 'ebsynth_jobs'
$aiModel    = Join-Path $studioRoot 'models\v1-5-pruned-emaonly.safetensors'
$routeFile  = Join-Path $studioRoot '.ui_route.json'
New-Item -ItemType Directory -Path $jobsRoot -Force | Out-Null

$script:mainMedia     = $null
$script:mainJobDir    = $null
$script:mainIsPreview = $false
$script:ebJobDir      = $null
$script:ebMediaDuration = 0.0
$script:ebAction      = ''
$script:aiStatusFile  = ''
$script:aiAction      = ''
$script:appMutex      = $null

$createdNew = $false
$script:appMutex = [Threading.Mutex]::new($true, 'AnimeVideoStudio_Unified_Window', [ref]$createdNew)
if (-not $createdNew) {
    if ($StartTab -ne 'main' -or $KeyframesRoot) {
        $route = [pscustomobject]@{ tab = $StartTab; keyframes_root = $KeyframesRoot } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($routeFile, $route, [Text.UTF8Encoding]::new($false))
    } else {
        [System.Windows.MessageBox]::Show('Anime Video Studio ya esta abierto.','Ya esta abierto') | Out-Null
    }
    exit 0
}

$xamlPath = Join-Path $studioRoot 'AnimeVideoStudioUnified.xaml'
[xml]$xaml = Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

foreach ($n in 'MainTabs','MainVideoPath','MainBrowseButton','MainAnalyzeButton','MainMediaInfo',
    'MainMethodBox','MainMethodInfo','MainJobStatus','MainProgress','MainProgressText',
    'MainGuideText','MainLogBox','MainOpenButton','MainToEbButton','MainPreviewButton','MainStartButton',
    'EbVideoPath','EbBrowseButton','EbAnalyzeButton','EbMediaInfo','EbStartTime','EbEndTime',
    'EbFullRangeButton','EbPrepareButton','EbAllKeysButton','EbWebButton','EbFolderButton',
    'EbLocalAIButton','EbStatusText','EbProgress','EbProgressText','EbGuideText','EbDetailText','EbImportButton',
    'AiFolderPath','AiBrowseButton','AiStyleBox','AiPromptBox','AiNegativeBox',
    'AiStrengthText','AiStrengthSlider','AiStepsBox','AiSeedBox',
    'AiInstallButton','AiPreviewButton','AiAllButton','AiOpenButton',
    'AiStatusText','AiProgress','AiProgressText','AiGuideText','AiDetailText') {
    Set-Variable -Name $n -Value $window.FindName($n)
}

$MainMethodBox.ItemsSource  = $mainMethods
$MainMethodBox.SelectedIndex = 0

# ─── Helpers ─────────────────────────────────────────────────────────────────

function Set-SelectedTab([string]$tabName) {
    switch ($tabName) {
        'ebsynth' { $MainTabs.SelectedIndex = 1 }
        'localai' { $MainTabs.SelectedIndex = 2 }
        default   { $MainTabs.SelectedIndex = 0 }
    }
}

function Format-MainStage([string]$s) {
    switch ($s) {
        'PREPARING'  { 'Preparando video' }
        'DRAWING'    { 'Aplicando estilo' }
        'ANIMATING'  { 'Generando fotogramas' }
        'NANOBANAN'  { 'Procesando con IA' }
        'CONFORMING' { 'Armando video final' }
        'DONE'       { 'Terminado' }
        'ERROR'      { 'Error' }
        default      { $s }
    }
}

function Format-EbStage([string]$s) {
    switch ($s) {
        'PREPARING'     { 'Preparando material' }
        'KEYFRAMES'     { 'Extrayendo cuadros clave' }
        'ALL_KEYFRAMES' { 'Creando keyframes de todo el video' }
        'CONFORMING'    { 'Ajustando resultado importado' }
        'REINTEGRATING' { 'Uniendo partes del video' }
        'FINISHING'     { 'Restaurando audio' }
        'DONE'          { 'Terminado' }
        'ERROR'         { 'Error' }
        default         { $s }
    }
}

function Format-AiStage([string]$s) {
    switch ($s) {
        'INSTALLING'    { 'Instalando componentes' }
        'LOADING_AI'    { 'Cargando modelo de IA' }
        'GENERATING_AI' { 'Generando imagenes' }
        'DONE'          { 'Terminado' }
        'ERROR'         { 'Error' }
        default         { $s }
    }
}

function ConvertTo-EbSeconds([string]$v) {
    try { return [TimeSpan]::Parse($v,[Globalization.CultureInfo]::InvariantCulture).TotalSeconds }
    catch { throw "Tiempo invalido: $v" }
}

function Update-MainMethodInfo {
    $m = $MainMethodBox.SelectedItem
    if (-not $m) { return }
    $state = if ($m.available) { 'Listo para usar' } else { 'No disponible en esta PC' }
    $MainMethodInfo.Text = "Estado: $state`nAspecto: $($m.quality)`nConsistencia: $($m.continuity)`nRequisitos: $($m.hardware)"
    $MainGuideText.Text  = if ($m.available) {
        "Siguiente paso: prueba 6 s con '$($m.name)'. Si te gusta, usa Crear final."
    } else { 'Este metodo no esta disponible. Elige otro de la lista.' }
    $ok = [bool]($m.available -and $script:mainMedia)
    $MainStartButton.IsEnabled   = $ok
    $MainPreviewButton.IsEnabled = $ok
}

function Set-AiBusy([bool]$busy) {
    $AiInstallButton.IsEnabled = -not $busy
    $AiPreviewButton.IsEnabled = -not $busy
    $AiAllButton.IsEnabled     = -not $busy
    $AiBrowseButton.IsEnabled  = -not $busy
}

# ─── MAIN tab logic ──────────────────────────────────────────────────────────

function Start-MainJob([int]$previewSeconds) {
    try {
        $m = $MainMethodBox.SelectedItem
        if (-not $m.available) { throw 'El metodo seleccionado no esta disponible.' }
        $safe = [IO.Path]::GetFileNameWithoutExtension($MainVideoPath.Text) -replace '[^A-Za-z0-9_-]','_'
        $kind = if ($previewSeconds -gt 0) { 'preview' } else { 'full' }
        $script:mainJobDir = Join-Path $studioRoot ("jobs\{0}_{1}_{2}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'),$kind,$safe)
        New-Item -ItemType Directory -Path $script:mainJobDir -Force | Out-Null
        $jobArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$mainRunner`" -Source `"$($MainVideoPath.Text)`" -MethodId `"$($m.id)`" -JobDir `"$script:mainJobDir`" -OutputWidth $($script:mainMedia.Width) -OutputHeight $($script:mainMedia.Height) -PreviewSeconds $previewSeconds"
        Start-Process -FilePath 'powershell.exe' -ArgumentList $jobArgs -WindowStyle Hidden | Out-Null
        $script:mainIsPreview = $previewSeconds -gt 0
        $MainJobStatus.Text   = if ($script:mainIsPreview) { "Vista previa con $($m.name)" } else { "Procesando con $($m.name)" }
        $MainGuideText.Text   = if ($script:mainIsPreview) { 'Espera. Cuando termine, revisa el resultado.' } else { 'Creando el video completo. Podes abrir la carpeta del trabajo.' }
        $MainLogBox.Text      = "Trabajo: $script:mainJobDir`nEl original no se modifica."
        $MainProgress.Value   = 0; $MainProgressText.Text = '0 %'
        $MainStartButton.IsEnabled   = $false
        $MainPreviewButton.IsEnabled = $false
        $MainOpenButton.IsEnabled    = $true
    } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'No se pudo iniciar') | Out-Null }
}

$MainBrowseButton.Add_Click({
    $d = [Microsoft.Win32.OpenFileDialog]::new()
    $d.Filter = 'Videos|*.mp4;*.mov;*.mkv;*.avi;*.webm;*.mxf|Todos los archivos|*.*'
    if ($d.ShowDialog()) { $MainVideoPath.Text = $d.FileName }
})

$MainAnalyzeButton.Add_Click({
    try {
        if (-not (Test-Path -LiteralPath $MainVideoPath.Text)) { throw 'Elige un archivo de video valido.' }
        $MainGuideText.Text = 'Leyendo informacion del video...'
        $json  = & $ffprobe -v error -show_streams -show_format -of json $MainVideoPath.Text | ConvertFrom-Json
        $video = $json.streams | Where-Object codec_type -eq 'video' | Select-Object -First 1
        $audio = $json.streams | Where-Object codec_type -eq 'audio' | Select-Object -First 1
        $dur   = [TimeSpan]::FromSeconds([double]$json.format.duration)
        $fps   = [string]$video.avg_frame_rate
        $frames = 0
        if ($video.nb_frames) { [void][int]::TryParse([string]$video.nb_frames,[ref]$frames) }
        if ($frames -le 0 -and $fps -match '^(\d+)/(\d+)$') {
            $frames = [int][Math]::Round([double]$Matches[1] / [double]$Matches[2] * [double]$json.format.duration)
        }
        $script:mainMedia = [pscustomobject]@{ Width=[int]$video.width; Height=[int]$video.height; Fps=$fps; Frames=$frames; Duration=$dur; Audio=$audio }
        $audioTxt  = if ($audio) { "$($audio.codec_name), $($audio.sample_rate) Hz, $($audio.channels) canales" } else { 'sin audio' }
        $frameTxt  = if ($frames -gt 0) { $frames } else { 'N/D' }
        $MainMediaInfo.Text = "Resolucion: $($video.width) x $($video.height) | FPS: $fps | Duracion: $($dur.ToString('hh\:mm\:ss\.fff'))`nFotogramas: $frameTxt | Color: $($video.color_space) | Audio: $audioTxt"
        $MainGuideText.Text = 'Perfecto. Ahora elige un metodo y prueba 6 segundos.'
        Update-MainMethodInfo
    } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'Error de analisis') | Out-Null }
})

$MainMethodBox.Add_SelectionChanged({ Update-MainMethodInfo })
$MainStartButton.Add_Click({   Start-MainJob 0 })
$MainPreviewButton.Add_Click({ Start-MainJob 6 })
$MainOpenButton.Add_Click({    if ($script:mainJobDir -and (Test-Path $script:mainJobDir)) { Start-Process explorer.exe $script:mainJobDir } })
$MainToEbButton.Add_Click({    Set-SelectedTab 'ebsynth' })

# ─── EBSYNTH tab logic ───────────────────────────────────────────────────────

function Start-EbWorker([string]$action,[string]$editedVideo='') {
    $s = ConvertTo-EbSeconds $EbStartTime.Text
    $e = ConvertTo-EbSeconds $EbEndTime.Text
    if ($e -le $s) { throw 'El final debe ser posterior al inicio.' }
    if ($script:ebMediaDuration -gt 0 -and $e -gt $script:ebMediaDuration + 0.02) { throw 'El final supera la duracion del video.' }
    if (-not $script:ebJobDir) {
        $safe = [IO.Path]::GetFileNameWithoutExtension($EbVideoPath.Text) -replace '[^A-Za-z0-9_-]','_'
        $script:ebJobDir = Join-Path $jobsRoot ("{0}_{1}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'),$safe)
        New-Item -ItemType Directory -Path $script:ebJobDir -Force | Out-Null
    }
    $sa = $s.ToString('R',[Globalization.CultureInfo]::InvariantCulture)
    $ea = $e.ToString('R',[Globalization.CultureInfo]::InvariantCulture)
    $cmdArgs = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action {1} -Source "{2}" -StartSeconds {3} -EndSeconds {4} -JobDir "{5}"' -f $ebWorker,$action,$EbVideoPath.Text,$sa,$ea,$script:ebJobDir
    if ($editedVideo) { $cmdArgs += ' -EditedVideo "{0}"' -f $editedVideo }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $cmdArgs -WindowStyle Hidden | Out-Null
    $script:ebAction = $action
    foreach ($b in @($EbPrepareButton,$EbAllKeysButton,$EbLocalAIButton,$EbImportButton)) { $b.IsEnabled = $false }
    $EbFolderButton.IsEnabled = $true
    $EbStatusText.Text = switch ($action) {
        'Prepare'              { 'Preparando tramo para EbSynth' }
        'GenerateAllKeyframes' { 'Generando keyframes de todo el intervalo' }
        default                { 'Reinsertando tramo editado' }
    }
}

$EbBrowseButton.Add_Click({
    $d = [Microsoft.Win32.OpenFileDialog]::new()
    $d.Filter = 'Videos|*.mp4;*.mov;*.mkv;*.avi;*.webm;*.mxf|Todos los archivos|*.*'
    if ($d.ShowDialog()) { $EbVideoPath.Text = $d.FileName; $script:ebJobDir = $null }
})

$EbAnalyzeButton.Add_Click({
    try {
        if (-not (Test-Path -LiteralPath $EbVideoPath.Text)) { throw 'Elige un archivo de video valido.' }
        $json  = & $ffprobe -v error -show_streams -show_format -of json $EbVideoPath.Text | ConvertFrom-Json
        $video = $json.streams | Where-Object codec_type -eq 'video' | Select-Object -First 1
        $script:ebMediaDuration = [double]$json.format.duration
        $dur   = [TimeSpan]::FromSeconds($script:ebMediaDuration)
        $EbMediaInfo.Text = "Resolucion: $($video.width) x $($video.height) | FPS: $($video.avg_frame_rate) | Duracion: $($dur.ToString('hh\:mm\:ss\.fff'))"
        $EbGuideText.Text = 'Ahora elige el tramo. Usa Usar todo el video si quieres procesar el video completo.'
        if ($script:ebMediaDuration -lt 10) { $EbEndTime.Text = $dur.ToString('hh\:mm\:ss\.fff') }
        foreach ($b in @($EbPrepareButton,$EbAllKeysButton,$EbFullRangeButton)) { $b.IsEnabled = $true }
    } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'Error') | Out-Null }
})

$EbPrepareButton.Add_Click({   try { Start-EbWorker 'Prepare' }              catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'Error') | Out-Null } })
$EbAllKeysButton.Add_Click({   try { Start-EbWorker 'GenerateAllKeyframes' } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'Error') | Out-Null } })
$EbFullRangeButton.Add_Click({ if ($script:ebMediaDuration -gt 0) { $EbStartTime.Text = '00:00:00.000'; $EbEndTime.Text = [TimeSpan]::FromSeconds($script:ebMediaDuration).ToString('hh\:mm\:ss\.fff') } })
$EbWebButton.Add_Click({    Start-Process 'https://ebsynth.com/app' })
$EbFolderButton.Add_Click({ if ($script:ebJobDir -and (Test-Path -LiteralPath $script:ebJobDir)) { Start-Process explorer.exe $script:ebJobDir } })
$EbLocalAIButton.Add_Click({
    $kf = Join-Path $script:ebJobDir 'KEYFRAMES_TODO_EL_VIDEO'
    if (-not (Test-Path -LiteralPath $kf)) { [System.Windows.MessageBox]::Show('Primero genera los keyframes de todo el video.','Faltan keyframes') | Out-Null; return }
    $AiFolderPath.Text = $kf
    Set-SelectedTab 'localai'
})
$EbImportButton.Add_Click({
    try {
        if (-not $script:ebJobDir) { throw 'Primero prepara un tramo para EbSynth.' }
        $d = [Microsoft.Win32.OpenFileDialog]::new()
        $d.Filter = 'MP4 de EbSynth|*.mp4|Videos|*.mp4;*.mov;*.mkv;*.webm'
        if ($d.ShowDialog()) { Start-EbWorker 'Reintegrate' $d.FileName }
    } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'Error') | Out-Null }
})

# ─── IA LOCAL tab logic ──────────────────────────────────────────────────────

$aiPresets = @(
    'hand-drawn 2D anime film frame, clean expressive ink lines, detailed cel shading, fluid character animation, vivid original colors, consistent face, preserve pose and composition',
    'high quality animated cartoon film frame, expressive clean outlines, rich cel shading, lively shapes, vivid original colors, consistent character design, preserve pose and composition',
    'detailed illustrated comic panel, confident hand-drawn linework, graphic shadows, vivid original colors, consistent character design, preserve pose and composition'
)
$AiPromptBox.Text   = $aiPresets[0]
$AiNegativeBox.Text = 'photorealistic, 3d render, text, watermark, logo, deformed face, extra fingers, extra limbs, blurry, low detail, color shift'
$AiFolderPath.Text  = $KeyframesRoot

function Start-AiGeneration([string]$action) {
    if (-not (Test-Path -LiteralPath $AiFolderPath.Text)) { throw 'Elige una carpeta KEYFRAMES_TODO_EL_VIDEO valida.' }
    if (-not (Test-Path -LiteralPath $aiModel) -or (Get-Item -LiteralPath $aiModel).Length -lt 4000000000L) { throw 'Primero pulsa Instalar IA local y espera al 100 %.' }
    $steps = 0; $seed = 0L
    if (-not [int]::TryParse($AiStepsBox.Text,[ref]$steps) -or $steps -lt 2 -or $steps -gt 8) { throw 'Los pasos deben estar entre 2 y 8.' }
    if (-not [long]::TryParse($AiSeedBox.Text,[ref]$seed)) { throw 'La semilla debe ser un numero entero.' }
    $script:aiStatusFile = Join-Path $AiFolderPath.Text 'ia_status.txt'
    $p64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($AiPromptBox.Text))
    $n64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($AiNegativeBox.Text))
    $str = $AiStrengthSlider.Value.ToString('0.00',[Globalization.CultureInfo]::InvariantCulture)
    $cmdArgs = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action {1} -KeyframesRoot "{2}" -PromptBase64 {3} -NegativePromptBase64 {4} -Strength {5} -Steps {6} -Seed {7} -StatusFile "{8}"' -f $aiWorker,$action,$AiFolderPath.Text,$p64,$n64,$str,$steps,$seed,$script:aiStatusFile
    Start-Process -FilePath 'powershell.exe' -ArgumentList $cmdArgs -WindowStyle Hidden | Out-Null
    $script:aiAction = $action
    Set-AiBusy $true
    $AiStatusText.Text = if ($action -eq 'Preview') { 'Generando una vista previa' } else { 'Generando todos los keyframes' }
    $AiGuideText.Text  = if ($action -eq 'Preview') { 'Se esta generando una sola imagen para revisar el estilo.' } else { 'Se estan generando todas las imagenes. Puede tardar bastante.' }
}

$AiBrowseButton.Add_Click({
    $d = [System.Windows.Forms.FolderBrowserDialog]::new()
    $d.Description = 'Elige la carpeta KEYFRAMES_TODO_EL_VIDEO'
    if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $AiFolderPath.Text = $d.SelectedPath }
})
$AiStyleBox.Add_SelectionChanged({ if ($AiStyleBox.SelectedIndex -ge 0) { $AiPromptBox.Text = $aiPresets[$AiStyleBox.SelectedIndex] } })
$AiStrengthSlider.Add_ValueChanged({ $AiStrengthText.Text = 'Fuerza del redibujo: {0:F2}' -f $AiStrengthSlider.Value })
$AiInstallButton.Add_Click({
    $script:aiStatusFile = Join-Path $studioRoot 'local_ai_install_status.txt'
    $cmdArgs = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -StatusFile "{1}"' -f $aiInstaller,$script:aiStatusFile
    Start-Process -FilePath 'powershell.exe' -ArgumentList $cmdArgs -WindowStyle Hidden | Out-Null
    $script:aiAction = 'Install'
    Set-AiBusy $true
    $AiGuideText.Text = 'Descargando e instalando los componentes de IA local...'
})
$AiPreviewButton.Add_Click({ try { Start-AiGeneration 'Preview' } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'Error') | Out-Null } })
$AiAllButton.Add_Click({     try { Start-AiGeneration 'All' }     catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'Error') | Out-Null } })
$AiOpenButton.Add_Click({    if (Test-Path -LiteralPath $AiFolderPath.Text) { Start-Process explorer.exe $AiFolderPath.Text } })

# ─── Timers ──────────────────────────────────────────────────────────────────

$mainTimer = [Windows.Threading.DispatcherTimer]::new()
$mainTimer.Interval = [TimeSpan]::FromSeconds(2)
$mainTimer.Add_Tick({
    if (-not $script:mainJobDir) { return }
    $sf  = Join-Path $script:mainJobDir 'status.txt'
    $log = Join-Path $script:mainJobDir 'processing.stderr.log'
    if (-not (Test-Path $sf)) { return }
    $parts   = (Get-Content $sf -Raw -Encoding UTF8).Split('|',3)
    $stage   = $parts[0]
    $percent = if ($parts.Count -gt 1) { [int]$parts[1] } else { 0 }
    $msg     = if ($parts.Count -gt 2) { $parts[2] } else { '' }
    if ($stage -eq 'ANIMATING' -and (Test-Path $log)) {
        $raw = Get-Content $log -Raw -ErrorAction SilentlyContinue
        $m   = [regex]::Matches($raw,'(\d+)%\|')
        if ($m.Count) { $percent = [int]$m[$m.Count-1].Groups[1].Value }
    }
    if ($stage -eq 'DRAWING' -and (Test-Path $log)) {
        $raw = Get-Content $log -Raw -ErrorAction SilentlyContinue
        $m   = [regex]::Matches($raw,'PROGRESS\|\d+\|\d+\|(\d+)')
        if ($m.Count) { $percent = [int]$m[$m.Count-1].Groups[1].Value }
    }
    $MainProgress.Value   = $percent
    $MainProgressText.Text = "$percent %"
    $lbl = Format-MainStage $stage
    $MainJobStatus.Text   = "$($lbl.ToUpperInvariant()) - $msg"
    $MainGuideText.Text   = switch ($stage) {
        'PREPARING'  { 'El sistema esta preparando el video para procesarlo.' }
        'DRAWING'    { 'Se esta aplicando el estilo a cada fotograma.' }
        'ANIMATING'  { 'Se estan generando los fotogramas del resultado.' }
        'NANOBANAN'  { 'La IA esta procesando el video fotograma por fotograma.' }
        'CONFORMING' { 'Se esta armando el archivo final con resolucion y audio.' }
        'DONE'       { 'Listo! Podes abrir la carpeta o lanzar otra prueba.' }
        'ERROR'      { 'Hubo un error. Revisa el detalle de abajo.' }
        default      { $msg }
    }
    $MainLogBox.Text = "Carpeta: $script:mainJobDir`nPaso: $lbl`nDetalle: $msg"
    if ($stage -eq 'DONE') {
        $MainStartButton.IsEnabled   = $true
        $MainPreviewButton.IsEnabled = $true
        $MainProgress.Value = 100; $MainProgressText.Text = '100 % - TERMINADO'
    }
    if ($stage -eq 'ERROR') {
        $MainStartButton.IsEnabled   = $true
        $MainPreviewButton.IsEnabled = $true
        $MainProgressText.Text = 'ERROR'
    }
})
$mainTimer.Start()

$ebTimer = [Windows.Threading.DispatcherTimer]::new()
$ebTimer.Interval = [TimeSpan]::FromSeconds(2)
$ebTimer.Add_Tick({
    if (-not $script:ebJobDir) { return }
    $sf = Join-Path $script:ebJobDir 'status.txt'
    if (-not (Test-Path -LiteralPath $sf)) { return }
    $parts   = (Get-Content -LiteralPath $sf -Raw -Encoding UTF8).Split('|',3)
    $stage   = $parts[0]
    $percent = if ($parts.Count -gt 1) { [int]$parts[1] } else { 0 }
    $msg     = if ($parts.Count -gt 2) { $parts[2] } else { '' }
    $EbProgress.Value    = $percent
    $EbProgressText.Text = "$percent %"
    $lbl = Format-EbStage $stage
    $EbStatusText.Text   = "$lbl - $msg"
    $EbDetailText.Text   = "Carpeta del trabajo: $script:ebJobDir"
    if ($stage -eq 'DONE') {
        foreach ($b in @($EbPrepareButton,$EbAllKeysButton,$EbImportButton)) { $b.IsEnabled = $true }
        $EbLocalAIButton.IsEnabled = Test-Path -LiteralPath (Join-Path $script:ebJobDir 'KEYFRAMES_TODO_EL_VIDEO')
    }
    if ($stage -eq 'ERROR') {
        foreach ($b in @($EbPrepareButton,$EbAllKeysButton)) { $b.IsEnabled = $true }
        $EbImportButton.IsEnabled  = [bool]$script:ebJobDir
        $EbLocalAIButton.IsEnabled = [bool]($script:ebJobDir -and (Test-Path -LiteralPath (Join-Path $script:ebJobDir 'KEYFRAMES_TODO_EL_VIDEO')))
    }
})
$ebTimer.Start()

$aiTimer = [Windows.Threading.DispatcherTimer]::new()
$aiTimer.Interval = [TimeSpan]::FromSeconds(2)
$aiTimer.Add_Tick({
    if (-not $script:aiStatusFile -or -not (Test-Path -LiteralPath $script:aiStatusFile)) { return }
    try {
        $parts   = (Get-Content -LiteralPath $script:aiStatusFile -Raw -Encoding UTF8).Split('|',3)
        $stage   = $parts[0]
        $percent = if ($parts.Count -gt 1) { [int]$parts[1] } else { 0 }
        $msg     = if ($parts.Count -gt 2) { $parts[2] } else { '' }
        $AiProgress.Value    = $percent
        $AiProgressText.Text = "$percent %"
        $AiStatusText.Text   = Format-AiStage $stage
        $AiGuideText.Text    = switch ($stage) {
            'INSTALLING'    { 'Instalando los componentes necesarios...' }
            'LOADING_AI'    { 'Cargando la IA en memoria antes de generar imagenes...' }
            'GENERATING_AI' { 'La IA esta redibujando las imagenes seleccionadas...' }
            'DONE'          { 'Listo! Revisa el resultado antes de seguir con EbSynth.' }
            'ERROR'         { 'Hubo un error. Mira el detalle de abajo.' }
            default         { $msg }
        }
        $AiDetailText.Text = $msg
        if ($stage -in @('DONE','ERROR')) { Set-AiBusy $false }
    } catch { }
})
$aiTimer.Start()

$routeTimer = [Windows.Threading.DispatcherTimer]::new()
$routeTimer.Interval = [TimeSpan]::FromSeconds(1)
$routeTimer.Add_Tick({
    if (-not (Test-Path -LiteralPath $routeFile)) { return }
    try {
        $r = Get-Content -LiteralPath $routeFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($r.keyframes_root) { $AiFolderPath.Text = [string]$r.keyframes_root }
        Set-SelectedTab ([string]$r.tab)
        Remove-Item -LiteralPath $routeFile -Force -ErrorAction SilentlyContinue
    } catch { }
})
$routeTimer.Start()

# ─── Init ────────────────────────────────────────────────────────────────────

if ((Test-Path -LiteralPath $aiModel) -and (Get-Item -LiteralPath $aiModel).Length -ge 4000000000L) {
    $AiDetailText.Text = 'El modelo local ya esta instalado. Prueba primero un keyframe.'
    $AiGuideText.Text  = 'La IA ya esta lista. Prueba una imagen y, si te gusta, genera todas.'
}
if ($KeyframesRoot) { $AiFolderPath.Text = $KeyframesRoot }
Set-SelectedTab $StartTab
Update-MainMethodInfo

try {
    $window.ShowDialog() | Out-Null
} finally {
    if ($script:appMutex) { $script:appMutex.ReleaseMutex(); $script:appMutex.Dispose() }
}
