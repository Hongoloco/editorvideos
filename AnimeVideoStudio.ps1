$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms

$studioRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolRoot = Join-Path $studioRoot 'tools'
if (-not (Test-Path -LiteralPath $toolRoot)) {
  $workspace = Split-Path -Parent $studioRoot
  $toolRoot = Join-Path $workspace 'REARRANGED_2D\tools'
}
$ffprobe = Join-Path $toolRoot 'ffmpeg\ffprobe.exe'
$runner = Join-Path $studioRoot 'run_job.ps1'
$methods = Get-Content -LiteralPath (Join-Path $studioRoot 'methods.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$script:media = $null
$script:jobDir = $null
$script:isPreview = $false
$script:appMutex = $null

$createdNew = $false
$script:appMutex = [Threading.Mutex]::new($true, 'AnimeVideoStudio_Main_Window', [ref]$createdNew)
if (-not $createdNew) {
  [System.Windows.MessageBox]::Show('Anime Video Studio ya esta abierto. Usa la ventana existente.','Ya esta abierto') | Out-Null
  exit 0
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
  xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Anime Video Studio" Width="1140" Height="860" WindowStartupLocation="CenterScreen"
        Background="#0E131B" Foreground="#E6ECF5" FontFamily="Bahnschrift">
  <Window.Resources>
    <LinearGradientBrush x:Key="CardBrush" StartPoint="0,0" EndPoint="1,1">
      <GradientStop Color="#1B2432" Offset="0"/>
      <GradientStop Color="#151C28" Offset="1"/>
    </LinearGradientBrush>
    <Style TargetType="Button">
      <Setter Property="Height" Value="40"/>
      <Setter Property="Foreground" Value="#F8FAFC"/>
      <Setter Property="Background" Value="#2D3D56"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="12,0"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Height" Value="38"/>
      <Setter Property="Padding" Value="10"/>
      <Setter Property="Background" Value="#101722"/>
      <Setter Property="Foreground" Value="#F8FAFC"/>
      <Setter Property="BorderBrush" Value="#2E3D53"/>
      <Setter Property="BorderThickness" Value="1"/>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Height" Value="40"/>
      <Setter Property="Background" Value="#F3F4F6"/>
      <Setter Property="Foreground" Value="#111827"/>
      <Setter Property="BorderBrush" Value="#94A3B8"/>
      <Setter Property="BorderThickness" Value="1"/>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Background" Value="#F3F4F6"/>
      <Setter Property="Foreground" Value="#111827"/>
      <Setter Property="Padding" Value="8,6"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Style.Triggers>
        <Trigger Property="IsHighlighted" Value="True">
          <Setter Property="Background" Value="#1D4ED8"/>
          <Setter Property="Foreground" Value="#FFFFFF"/>
        </Trigger>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="#0EA5E9"/>
          <Setter Property="Foreground" Value="#08111C"/>
        </Trigger>
      </Style.Triggers>
    </Style>
  </Window.Resources>
  <Grid Margin="24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" CornerRadius="14" Padding="20" Margin="0,0,0,14" Background="#111926" BorderBrush="#2E3C52" BorderThickness="1">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="260"/>
        </Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock Text="ANIME VIDEO STUDIO" FontSize="34" FontWeight="Bold" Foreground="#65E5FF"/>
          <TextBlock Text="Converti tu video a un estilo anime o cartoon, paso a paso" FontSize="14" Foreground="#B6C2D4" Margin="0,5,0,0"/>
        </StackPanel>
        <Border Grid.Column="1" Background="#0C1421" CornerRadius="10" Padding="12" BorderBrush="#2A3A50" BorderThickness="1">
          <TextBlock Text="Consejo: proba primero 6 segundos para ver si el estilo te gusta." TextWrapping="Wrap" Foreground="#8DFFCE" FontSize="13"/>
        </Border>
      </Grid>
    </Border>

    <Border Grid.Row="1" Background="#122033" BorderBrush="#2A4869" BorderThickness="1" CornerRadius="12" Padding="14" Margin="0,0,0,14">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Border Grid.Column="0" Margin="0,0,10,0" Background="#0F1C2D" BorderBrush="#2563EB" BorderThickness="1" CornerRadius="10" Padding="10">
          <StackPanel>
            <TextBlock Text="PASO 1" Foreground="#6DCFF6" FontWeight="Bold"/>
            <TextBlock Text="Elegi tu video y revisa su informacion." TextWrapping="Wrap" Margin="0,4,0,0"/>
          </StackPanel>
        </Border>
        <Border Grid.Column="1" Margin="0,0,10,0" Background="#24170F" BorderBrush="#F59E0B" BorderThickness="1" CornerRadius="10" Padding="10">
          <StackPanel>
            <TextBlock Text="PASO 2" Foreground="#FCD34D" FontWeight="Bold"/>
            <TextBlock Text="Elegi el estilo que mas te guste." TextWrapping="Wrap" Margin="0,4,0,0"/>
          </StackPanel>
        </Border>
        <Border Grid.Column="2" Background="#0F2018" BorderBrush="#10B981" BorderThickness="1" CornerRadius="10" Padding="10">
          <StackPanel>
            <TextBlock Text="PASO 3" Foreground="#86EFAC" FontWeight="Bold"/>
            <TextBlock Text="Proba 6 segundos y, si te gusta, crea el video final." TextWrapping="Wrap" Margin="0,4,0,0"/>
          </StackPanel>
        </Border>
      </Grid>
    </Border>

    <Border Grid.Row="2" Background="{StaticResource CardBrush}" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="12" Padding="14" Margin="0,0,0,14">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid Grid.Row="0">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="140"/><ColumnDefinition Width="130"/></Grid.ColumnDefinitions>
          <TextBox Name="VideoPath" Grid.Column="0" FontSize="14"/>
          <Button Name="BrowseButton" Grid.Column="1" Content="Buscar video" Margin="10,0,0,0"/>
          <Button Name="AnalyzeButton" Grid.Column="2" Content="Leer datos" Margin="10,0,0,0" Background="#0A9CC5"/>
        </Grid>
        <Border Grid.Row="1" Background="#0E1520" BorderBrush="#273549" BorderThickness="1" CornerRadius="9" Padding="12" Margin="0,12,0,0">
          <TextBlock Name="MediaInfo" Text="Selecciona un video para analizarlo." TextWrapping="Wrap" FontSize="13" Foreground="#D6E0EE"/>
        </Border>
      </Grid>
    </Border>

    <Grid Grid.Row="3" Margin="0,0,0,14">
      <Grid.ColumnDefinitions><ColumnDefinition Width="390"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Border Grid.Column="0" Background="{StaticResource CardBrush}" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="12" Padding="14">
        <StackPanel>
          <TextBlock Text="Metodo" FontSize="16" FontWeight="Bold" Margin="0,0,0,8" Foreground="#9DD8FF"/>
          <ComboBox Name="MethodBox" DisplayMemberPath="name"/>
        </StackPanel>
      </Border>
      <Border Grid.Column="2" Background="{StaticResource CardBrush}" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="12" Padding="14">
        <TextBlock Name="MethodInfo" TextWrapping="Wrap" Foreground="#D9E4F3" FontSize="13"/>
      </Border>
    </Grid>

    <Border Grid.Row="4" Background="#0A1018" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="12" Padding="14">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <TextBlock Name="JobStatus" Text="Sin trabajo activo" FontSize="17" FontWeight="Bold" Margin="0,0,0,10" Foreground="#F5FBFF"/>
        <Grid Grid.Row="1" Margin="0,0,0,12">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="95"/></Grid.ColumnDefinitions>
          <ProgressBar Name="Progress" Height="22" Minimum="0" Maximum="100" Value="0" Foreground="#20E39A" Background="#223245"/>
          <Border Grid.Column="1" Margin="10,0,0,0" CornerRadius="7" Background="#111C2A" BorderBrush="#29435E" BorderThickness="1">
            <TextBlock Name="ProgressText" Text="0 %" HorizontalAlignment="Center" VerticalAlignment="Center" FontWeight="Bold"/>
          </Border>
        </Grid>
        <Border Grid.Row="2" Background="#101A27" BorderBrush="#24384E" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,12">
          <TextBlock Name="GuideText" Text="Todavia no empezo el proceso. Elegi un video, revisa sus datos y despues proba 6 segundos." TextWrapping="Wrap" Foreground="#D6E5F7"/>
        </Border>
        <TextBox Name="LogBox" Grid.Row="3" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Background="#070B11" Foreground="#B9FFD6" BorderBrush="#1B2B3D" BorderThickness="1" Padding="10"/>
      </Grid>
    </Border>

    <Grid Grid.Row="5" Margin="0,14,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="185"/>
        <ColumnDefinition Width="190"/>
        <ColumnDefinition Width="170"/>
        <ColumnDefinition Width="180"/>
      </Grid.ColumnDefinitions>
      <TextBlock Grid.Column="0" VerticalAlignment="Center" Foreground="#9CB1C8" Text="El archivo original no se modifica. La salida se guarda en la carpeta del trabajo."/>
      <Button Name="OpenButton" Grid.Column="1" Content="Ver carpeta" Margin="10,0,0,0" IsEnabled="False"/>
      <Button Name="EbSynthButton" Grid.Column="2" Content="Abrir editor EbSynth" Margin="10,0,0,0" Background="#E9852A"/>
      <Button Name="PreviewButton" Grid.Column="3" Content="Probar 6 s" Margin="10,0,0,0" Background="#246BFF" IsEnabled="False"/>
      <Button Name="StartButton" Grid.Column="4" Content="Crear video final" Margin="10,0,0,0" Background="#04A777" IsEnabled="False"/>
    </Grid>
  </Grid>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
foreach ($name in 'VideoPath','BrowseButton','AnalyzeButton','MediaInfo','MethodBox','MethodInfo','JobStatus','Progress','ProgressText','GuideText','LogBox','OpenButton','EbSynthButton','PreviewButton','StartButton') {
    Set-Variable -Name $name -Value $window.FindName($name)
}
$MethodBox.ItemsSource = $methods
$MethodBox.SelectedIndex = 0

function Format-StageText([string]$stage) {
  switch ($stage) {
    'PREPARING' { return 'Preparando video' }
    'DRAWING' { return 'Aplicando estilo' }
    'ANIMATING' { return 'Generando fotogramas' }
    'NANOBANAN' { return 'Procesando con IA' }
    'CONFORMING' { return 'Armando video final' }
    'DONE' { return 'Terminado' }
    'ERROR' { return 'Error' }
    default { return $stage }
  }
}

function Update-MethodInfo {
    $method = $MethodBox.SelectedItem
    if (-not $method) { return }
  $state = if ($method.available) { 'Listo para usar' } else { 'No disponible en esta PC' }
  $MethodInfo.Text = "Estado: $state`nAspecto: $($method.quality)`nConsistencia entre cuadros: $($method.continuity)`nRequisitos: $($method.hardware)"
  $GuideText.Text = if ($method.available) {
    "Siguiente paso: proba 6 segundos con '$($method.name)'. Si te gusta, usa Crear video final."
  } else {
    "Este metodo no esta disponible en esta PC. Elegi otro metodo de la lista."
  }
    $enabled = [bool]($method.available -and $script:media)
    $StartButton.IsEnabled = $enabled
    $PreviewButton.IsEnabled = $enabled
}

function Start-StudioJob([int]$previewSeconds) {
    try {
        $method = $MethodBox.SelectedItem
        if (-not $method.available) { throw 'El metodo seleccionado no esta disponible en este equipo.' }
        $safeName = [IO.Path]::GetFileNameWithoutExtension($VideoPath.Text) -replace '[^A-Za-z0-9_-]','_'
        $kind = if ($previewSeconds -gt 0) { 'preview' } else { 'full' }
        $script:jobDir = Join-Path $studioRoot ("jobs\{0}_{1}_{2}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'),$kind,$safeName)
        New-Item -ItemType Directory -Path $script:jobDir -Force | Out-Null
        # Las comillas explícitas permiten usar videos ubicados en carpetas con espacios.
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$runner`" -Source `"$($VideoPath.Text)`" -MethodId `"$($method.id)`" -JobDir `"$script:jobDir`" -OutputWidth $($script:media.Width) -OutputHeight $($script:media.Height) -PreviewSeconds $previewSeconds"
        Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden | Out-Null
        $script:isPreview = $previewSeconds -gt 0
        $JobStatus.Text = if ($script:isPreview) { "Creando vista previa con $($method.name)" } else { "Procesando con $($method.name)" }
        $GuideText.Text = if ($script:isPreview) { 'Espera unos segundos. Cuando termine, revisa el resultado y decidi si queres crear el video final.' } else { 'El sistema esta creando el video completo. Podes abrir la carpeta del trabajo cuando quieras.' }
        $LogBox.Text = "Trabajo: $script:jobDir`nEl video original no se modifica."
        $Progress.Value = 0
        $ProgressText.Text = '0 %'
        $StartButton.IsEnabled = $false
        $PreviewButton.IsEnabled = $false
        $OpenButton.IsEnabled = $true
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message,'No se pudo iniciar') | Out-Null
    }
}

$BrowseButton.Add_Click({
    $dialog = [Microsoft.Win32.OpenFileDialog]::new()
    $dialog.Filter = 'Videos|*.mp4;*.mov;*.mkv;*.avi;*.webm;*.mxf|Todos los archivos|*.*'
    if ($dialog.ShowDialog()) { $VideoPath.Text = $dialog.FileName }
})

$AnalyzeButton.Add_Click({
    try {
        if (-not (Test-Path -LiteralPath $VideoPath.Text)) { throw 'Elegi un archivo de video valido.' }
        $GuideText.Text = 'Leyendo la informacion del video. Esto deberia tardar solo unos segundos.'
    $json = & $ffprobe -v error -show_streams -show_format -of json $VideoPath.Text | ConvertFrom-Json
        $video = $json.streams | Where-Object codec_type -eq 'video' | Select-Object -First 1
        $audio = $json.streams | Where-Object codec_type -eq 'audio' | Select-Object -First 1
        $duration = [TimeSpan]::FromSeconds([double]$json.format.duration)
    $fpsText = [string]$video.avg_frame_rate
    $frames = 0
    if ($video.nb_frames) {
      [void][int]::TryParse([string]$video.nb_frames,[ref]$frames)
    }
    if ($frames -le 0 -and $fpsText -match '^(\d+)/(\d+)$') {
      $fpsValue = [double]$matches[1] / [double]$matches[2]
      $frames = [int][Math]::Round($fpsValue * [double]$json.format.duration)
    }
        $script:media = [pscustomobject]@{
      Width=[int]$video.width; Height=[int]$video.height; Fps=$fpsText
      Frames=$frames; Duration=$duration; Audio=$audio
        }
        $audioText = if ($audio) { "$($audio.codec_name), $($audio.sample_rate) Hz, $($audio.channels) canales" } else { 'sin audio' }
    $frameText = if ($frames -gt 0) { $frames } else { 'no disponible' }
        $MediaInfo.Text = "Resolucion: $($video.width) × $($video.height)   |   FPS: $fpsText   |   Duracion: $($duration.ToString('hh\:mm\:ss\.fff'))`nFotogramas: $frameText   |   Color: $($video.color_space)   |   Audio: $audioText"
        $GuideText.Text = 'Perfecto. Ahora elegi un metodo abajo y hace una prueba de 6 segundos.'
        Update-MethodInfo
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message,'Error de analisis') | Out-Null
    }
})

$MethodBox.Add_SelectionChanged({ Update-MethodInfo })
$StartButton.Add_Click({ Start-StudioJob 0 })
$PreviewButton.Add_Click({ Start-StudioJob 6 })
$EbSynthButton.Add_Click({
    $bridge = Join-Path $studioRoot 'EbSynthBridge.ps1'
    Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$bridge`"" -WindowStyle Hidden | Out-Null
})
$OpenButton.Add_Click({ if ($script:jobDir -and (Test-Path $script:jobDir)) { Start-Process explorer.exe $script:jobDir } })

$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({
    if (-not $script:jobDir) { return }
    $statusFile = Join-Path $script:jobDir 'status.txt'
    $processingLog = Join-Path $script:jobDir 'processing.stderr.log'
    if (-not (Test-Path $statusFile)) { return }
    $parts = (Get-Content $statusFile -Raw -Encoding UTF8).Split('|',3)
    $stage = $parts[0]
    $percent = if ($parts.Count -gt 1) { [int]$parts[1] } else { 0 }
    $message = if ($parts.Count -gt 2) { $parts[2] } else { '' }

    if ($stage -eq 'ANIMATING' -and (Test-Path $processingLog)) {
        $raw = Get-Content $processingLog -Raw -ErrorAction SilentlyContinue
        $matches = [regex]::Matches($raw,'(\d+)%\|')
        if ($matches.Count) { $percent = [int]$matches[$matches.Count-1].Groups[1].Value }
    }
    if ($stage -eq 'DRAWING' -and (Test-Path $processingLog)) {
        $raw = Get-Content $processingLog -Raw -ErrorAction SilentlyContinue
        $matches = [regex]::Matches($raw,'PROGRESS\|\d+\|\d+\|(\d+)')
        if ($matches.Count) { $percent = [int]$matches[$matches.Count-1].Groups[1].Value }
    }

    $Progress.Value = $percent
    $ProgressText.Text = "$percent %"
    $stageLabel = Format-StageText $stage
    $JobStatus.Text = "$stageLabel - $message"
    $GuideText.Text = switch ($stage) {
      'PREPARING' { 'El sistema esta preparando el video para procesarlo.' }
      'DRAWING' { 'Se esta aplicando el estilo a cada fotograma.' }
      'ANIMATING' { 'Se estan generando los fotogramas del resultado.' }
      'NANOBANAN' { 'La IA esta procesando el video fotograma por fotograma.' }
      'CONFORMING' { 'Se esta armando el archivo final con resolucion y audio.' }
      'DONE' { 'Listo. Podes abrir la carpeta o lanzar otra prueba.' }
      'ERROR' { 'Hubo un error. Revisa el detalle de abajo para ver que fallo.' }
      default { $message }
    }
    $LogBox.Text = "Carpeta del trabajo: $script:jobDir`nPaso actual: $stageLabel`nDetalle: $message"

    if ($stage -eq 'DONE') {
        $StartButton.IsEnabled = $true
        $PreviewButton.IsEnabled = $true
        $Progress.Value = 100
        $ProgressText.Text = '100 % - TERMINADO'
    }
    if ($stage -eq 'ERROR') {
        $StartButton.IsEnabled = $true
        $PreviewButton.IsEnabled = $true
        $ProgressText.Text = 'ERROR'
    }
})
$timer.Start()
Update-MethodInfo
try {
  $window.ShowDialog() | Out-Null
} finally {
  if ($script:appMutex) {
    $script:appMutex.ReleaseMutex()
    $script:appMutex.Dispose()
  }
}
