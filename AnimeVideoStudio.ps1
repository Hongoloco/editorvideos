$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms

$studioRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$workspace = Split-Path -Parent $studioRoot
$ffprobe = Join-Path $workspace 'REARRANGED_2D\tools\ffmpeg\ffprobe.exe'
$runner = Join-Path $studioRoot 'run_job.ps1'
$methods = Get-Content -LiteralPath (Join-Path $studioRoot 'methods.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$script:media = $null
$script:jobDir = $null
$script:isPreview = $false
$script:openedResult = $false

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Anime Video Studio" Width="1140" Height="790" WindowStartupLocation="CenterScreen"
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
      <Setter Property="Background" Value="#101722"/>
      <Setter Property="Foreground" Value="#F8FAFC"/>
      <Setter Property="BorderBrush" Value="#2E3D53"/>
      <Setter Property="BorderThickness" Value="1"/>
    </Style>
  </Window.Resources>
  <Grid Margin="24">
    <Grid.RowDefinitions>
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
          <TextBlock Text="Pipeline local y IA para video a anime, fotograma por fotograma" FontSize="14" Foreground="#B6C2D4" Margin="0,5,0,0"/>
        </StackPanel>
        <Border Grid.Column="1" Background="#0C1421" CornerRadius="10" Padding="12" BorderBrush="#2A3A50" BorderThickness="1">
          <TextBlock Text="Tip: empezá con VISTA PREVIA 6 S antes de procesar completo." TextWrapping="Wrap" Foreground="#8DFFCE" FontSize="13"/>
        </Border>
      </Grid>
    </Border>

    <Border Grid.Row="1" Background="{StaticResource CardBrush}" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="12" Padding="14" Margin="0,0,0,14">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid Grid.Row="0">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="140"/><ColumnDefinition Width="130"/></Grid.ColumnDefinitions>
          <TextBox Name="VideoPath" Grid.Column="0" FontSize="14"/>
          <Button Name="BrowseButton" Grid.Column="1" Content="Elegir" Margin="10,0,0,0"/>
          <Button Name="AnalyzeButton" Grid.Column="2" Content="Analizar" Margin="10,0,0,0" Background="#0A9CC5"/>
        </Grid>
        <Border Grid.Row="1" Background="#0E1520" BorderBrush="#273549" BorderThickness="1" CornerRadius="9" Padding="12" Margin="0,12,0,0">
          <TextBlock Name="MediaInfo" Text="Seleccioná un video para analizarlo." TextWrapping="Wrap" FontSize="13" Foreground="#D6E0EE"/>
        </Border>
      </Grid>
    </Border>

    <Grid Grid.Row="2" Margin="0,0,0,14">
      <Grid.ColumnDefinitions><ColumnDefinition Width="390"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Border Grid.Column="0" Background="{StaticResource CardBrush}" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="12" Padding="14">
        <StackPanel>
          <TextBlock Text="Método" FontSize="16" FontWeight="Bold" Margin="0,0,0,8" Foreground="#9DD8FF"/>
          <ComboBox Name="MethodBox" DisplayMemberPath="name"/>
        </StackPanel>
      </Border>
      <Border Grid.Column="2" Background="{StaticResource CardBrush}" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="12" Padding="14">
        <TextBlock Name="MethodInfo" TextWrapping="Wrap" Foreground="#D9E4F3" FontSize="13"/>
      </Border>
    </Grid>

    <Border Grid.Row="3" Background="#0A1018" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="12" Padding="14">
      <Grid>
        <Grid.RowDefinitions>
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
        <TextBox Name="LogBox" Grid.Row="2" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Background="#070B11" Foreground="#B9FFD6" BorderBrush="#1B2B3D" BorderThickness="1" Padding="10"/>
      </Grid>
    </Border>

    <Grid Grid.Row="4" Margin="0,14,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="185"/>
        <ColumnDefinition Width="190"/>
        <ColumnDefinition Width="170"/>
        <ColumnDefinition Width="180"/>
      </Grid.ColumnDefinitions>
      <TextBlock Grid.Column="0" VerticalAlignment="Center" Foreground="#9CB1C8" Text="Salida: se guarda en jobs y no modifica el original."/>
      <Button Name="OpenButton" Grid.Column="1" Content="Abrir salida" Margin="10,0,0,0" IsEnabled="False"/>
      <Button Name="EbSynthButton" Grid.Column="2" Content="EbSynth + IA" Margin="10,0,0,0" Background="#E9852A"/>
      <Button Name="PreviewButton" Grid.Column="3" Content="Vista 6 s" Margin="10,0,0,0" Background="#246BFF" IsEnabled="False"/>
      <Button Name="StartButton" Grid.Column="4" Content="Procesar video" Margin="10,0,0,0" Background="#04A777" IsEnabled="False"/>
    </Grid>
  </Grid>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
foreach ($name in 'VideoPath','BrowseButton','AnalyzeButton','MediaInfo','MethodBox','MethodInfo','JobStatus','Progress','ProgressText','LogBox','OpenButton','EbSynthButton','PreviewButton','StartButton') {
    Set-Variable -Name $name -Value $window.FindName($name)
}
$MethodBox.ItemsSource = $methods
$MethodBox.SelectedIndex = 0

function Update-MethodInfo {
    $method = $MethodBox.SelectedItem
    if (-not $method) { return }
    $state = if ($method.available) { 'DISPONIBLE' } else { 'NO DISPONIBLE EN ESTE EQUIPO' }
    $MethodInfo.Text = "$state`nCalidad: $($method.quality)`nContinuidad: $($method.continuity)`nHardware: $($method.hardware)"
    $enabled = [bool]($method.available -and $script:media)
    $StartButton.IsEnabled = $enabled
    $PreviewButton.IsEnabled = $enabled
}

function Start-StudioJob([int]$previewSeconds) {
    try {
        $method = $MethodBox.SelectedItem
        if (-not $method.available) { throw 'El método seleccionado no está disponible en este equipo.' }
        $safeName = [IO.Path]::GetFileNameWithoutExtension($VideoPath.Text) -replace '[^A-Za-z0-9_-]','_'
        $kind = if ($previewSeconds -gt 0) { 'preview' } else { 'full' }
        $script:jobDir = Join-Path $studioRoot ("jobs\{0}_{1}_{2}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'),$kind,$safeName)
        New-Item -ItemType Directory -Path $script:jobDir -Force | Out-Null
        # Las comillas explícitas permiten usar videos ubicados en carpetas con espacios.
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$runner`" -Source `"$($VideoPath.Text)`" -MethodId `"$($method.id)`" -JobDir `"$script:jobDir`" -OutputWidth $($script:media.Width) -OutputHeight $($script:media.Height) -PreviewSeconds $previewSeconds"
        Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden | Out-Null
        $script:isPreview = $previewSeconds -gt 0
        $script:openedResult = $false
        $JobStatus.Text = if ($script:isPreview) { "Creando vista previa con $($method.name)" } else { "Procesando con $($method.name)" }
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
        if (-not (Test-Path -LiteralPath $VideoPath.Text)) { throw 'Elegí un archivo de video válido.' }
        $json = & $ffprobe -v error -count_frames -show_streams -show_format -of json $VideoPath.Text | ConvertFrom-Json
        $video = $json.streams | Where-Object codec_type -eq 'video' | Select-Object -First 1
        $audio = $json.streams | Where-Object codec_type -eq 'audio' | Select-Object -First 1
        $duration = [TimeSpan]::FromSeconds([double]$json.format.duration)
        $script:media = [pscustomobject]@{
            Width=[int]$video.width; Height=[int]$video.height; Fps=$video.avg_frame_rate
            Frames=$video.nb_read_frames; Duration=$duration; Audio=$audio
        }
        $audioText = if ($audio) { "$($audio.codec_name), $($audio.sample_rate) Hz, $($audio.channels) canales" } else { 'sin audio' }
        $MediaInfo.Text = "Resolución: $($video.width) × $($video.height)   |   FPS: $($video.avg_frame_rate)   |   Duración: $($duration.ToString('hh\:mm\:ss\.fff'))`nFotogramas: $($video.nb_read_frames)   |   Color: $($video.color_space)   |   Audio: $audioText"
        Update-MethodInfo
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message,'Error de análisis') | Out-Null
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
    $JobStatus.Text = "$stage - $message"
    $LogBox.Text = "Trabajo: $script:jobDir`nEstado: $stage`n$message"

    if ($stage -eq 'DONE') {
        $StartButton.IsEnabled = $true
        $PreviewButton.IsEnabled = $true
        $Progress.Value = 100
        $ProgressText.Text = '100 % - TERMINADO'
        if ($script:isPreview -and -not $script:openedResult -and (Test-Path -LiteralPath $message)) {
            $script:openedResult = $true
            Start-Process -FilePath $message | Out-Null
        }
    }
    if ($stage -eq 'ERROR') {
        $StartButton.IsEnabled = $true
        $PreviewButton.IsEnabled = $true
        $ProgressText.Text = 'ERROR'
    }
})
$timer.Start()
Update-MethodInfo
$window.ShowDialog() | Out-Null
