$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms

$studioRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolRoot = Join-Path $studioRoot 'tools'
if (-not (Test-Path -LiteralPath $toolRoot)) {
  $workspace = Split-Path -Parent $studioRoot
  $toolRoot = Join-Path $workspace 'REARRANGED_2D\tools'
}
$ffprobe = Join-Path $toolRoot 'ffmpeg\ffprobe.exe'
$worker = Join-Path $studioRoot 'ebsynth_job.ps1'
$jobsRoot = Join-Path $studioRoot 'ebsynth_jobs'
New-Item -ItemType Directory -Path $jobsRoot -Force | Out-Null
$script:jobDir = $null
$script:mediaDuration = 0.0
$script:openedResult = $false
$script:activeAction = ''

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="EbSynth — Editor de tramos" Width="1020" Height="760"
        WindowStartupLocation="CenterScreen" Background="#0E131B" Foreground="#E6ECF5" FontFamily="Bahnschrift">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Height" Value="40"/>
      <Setter Property="Foreground" Value="#F8FAFC"/>
      <Setter Property="Background" Value="#2D3D56"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="12,0"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Height" Value="38"/>
      <Setter Property="Padding" Value="10"/>
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
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" CornerRadius="14" Padding="20" Margin="0,0,0,14" Background="#111926" BorderBrush="#2E3C52" BorderThickness="1">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="250"/></Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock Text="EBSYNTH FLOW EDITOR" FontSize="31" FontWeight="Bold" Foreground="#67D8FF"/>
          <TextBlock Text="Editá un tramo, generá keyframes y reintegrá al master sin perder audio" Foreground="#B6C2D4" Margin="0,5,0,0"/>
        </StackPanel>
        <Border Grid.Column="1" Background="#0C1421" CornerRadius="10" Padding="11" BorderBrush="#2A3A50" BorderThickness="1">
          <TextBlock Text="Paso sugerido: PREPARAR TRAMO → editar en EbSynth → IMPORTAR RESULTADO" TextWrapping="Wrap" Foreground="#8DFFCE" FontSize="13"/>
        </Border>
      </Grid>
    </Border>

    <Border Grid.Row="1" Background="#151D29" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="12" Padding="14" Margin="0,0,0,12">
      <Grid>
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <Grid Grid.Row="0">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="130"/><ColumnDefinition Width="120"/></Grid.ColumnDefinitions>
          <TextBox Name="VideoPath"/>
          <Button Name="BrowseButton" Grid.Column="1" Content="Elegir" Margin="10,0,0,0"/>
          <Button Name="AnalyzeButton" Grid.Column="2" Content="Analizar" Margin="10,0,0,0" Background="#0A9CC5"/>
        </Grid>
        <Border Grid.Row="1" Margin="0,12,0,0" Background="#0F1520" BorderBrush="#273549" BorderThickness="1" CornerRadius="9" Padding="11">
          <TextBlock Name="MediaInfo" Text="Seleccioná el video que querés editar." TextWrapping="Wrap" Foreground="#D5E1EF"/>
        </Border>
      </Grid>
    </Border>

    <Grid Grid.Row="2" Margin="0,0,0,12">
      <Grid.ColumnDefinitions><ColumnDefinition Width="230"/><ColumnDefinition Width="230"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Border Grid.Column="0" Background="#151D29" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="11" Padding="12" Margin="0,0,10,0">
        <StackPanel>
          <TextBlock Text="Inicio" FontWeight="Bold" Foreground="#9DD8FF" Margin="0,0,0,6"/>
          <TextBox Name="StartTime" Text="00:00:00.000"/>
        </StackPanel>
      </Border>
      <Border Grid.Column="1" Background="#151D29" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="11" Padding="12" Margin="0,0,10,0">
        <StackPanel>
          <TextBlock Text="Final" FontWeight="Bold" Foreground="#9DD8FF" Margin="0,0,0,6"/>
          <TextBox Name="EndTime" Text="00:00:10.000"/>
        </StackPanel>
      </Border>
      <Border Grid.Column="2" Background="#201830" BorderBrush="#3C2D5A" BorderThickness="1" CornerRadius="11" Padding="12">
        <StackPanel>
          <TextBlock Text="EbSynth Free exporta hasta 720p. Al importar, se restaura resolución y audio del original." TextWrapping="Wrap" Foreground="#E9D5FF"/>
          <Button Name="FullRangeButton" Content="Usar video completo" Height="30" Margin="0,8,0,0" Background="#4D2A91" IsEnabled="False"/>
        </StackPanel>
      </Border>
    </Grid>

    <Grid Grid.Row="3" Margin="0,0,0,12">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="170"/><ColumnDefinition Width="145"/></Grid.ColumnDefinitions>
      <Button Name="PrepareButton" Grid.Column="0" Content="Preparar tramo" Background="#06A77D" IsEnabled="False"/>
      <Button Name="AllKeysButton" Grid.Column="1" Content="Keyframes de todo el video" Margin="10,0,0,0" Background="#C026D3" IsEnabled="False"/>
      <Button Name="WebButton" Grid.Column="2" Content="Abrir EbSynth" Margin="10,0,0,0" Background="#246BFF"/>
      <Button Name="FolderButton" Grid.Column="3" Content="Abrir carpeta" Margin="10,0,0,0" IsEnabled="False"/>
    </Grid>

    <Button Grid.Row="4" Name="LocalAIButton" Content="Generar keyframes con IA local" Height="42" Margin="0,0,0,12" Background="#EC4899" IsEnabled="False"/>

    <Border Grid.Row="5" Background="#0A1018" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="12" Padding="14">
      <StackPanel>
        <TextBlock Name="StatusText" Text="Sin trabajo activo" FontSize="16" FontWeight="Bold"/>
        <Grid Margin="0,10,0,0">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="90"/></Grid.ColumnDefinitions>
          <ProgressBar Name="Progress" Height="22" Minimum="0" Maximum="100" Value="0" Foreground="#20E39A" Background="#223245"/>
          <Border Grid.Column="1" Margin="10,0,0,0" CornerRadius="7" Background="#111C2A" BorderBrush="#29435E" BorderThickness="1">
            <TextBlock Name="ProgressText" Text="0 %" HorizontalAlignment="Center" VerticalAlignment="Center" FontWeight="Bold"/>
          </Border>
        </Grid>
        <TextBlock Name="DetailText" Text="Después de descargar el MP4 desde EbSynth, importalo aquí." Foreground="#B9FBC0" TextWrapping="Wrap" Margin="0,13,0,0"/>
      </StackPanel>
    </Border>

    <Button Grid.Row="6" Name="ImportButton" Content="Importar resultado y reinsertar en el video" Height="44" Margin="0,14,0,0" Background="#E9852A" IsEnabled="False"/>
  </Grid>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
foreach ($name in 'VideoPath','BrowseButton','AnalyzeButton','MediaInfo','StartTime','EndTime','FullRangeButton','PrepareButton','AllKeysButton','WebButton','FolderButton','LocalAIButton','StatusText','Progress','ProgressText','DetailText','ImportButton') {
    Set-Variable -Name $name -Value $window.FindName($name)
}

function Parse-TimeText([string]$value) {
    try { return [TimeSpan]::Parse($value,[Globalization.CultureInfo]::InvariantCulture).TotalSeconds }
    catch { throw "Tiempo inválido: $value. Usá HH:MM:SS.mmm" }
}

function Start-Worker([string]$action,[string]$editedVideo='') {
    $startSeconds = Parse-TimeText $StartTime.Text
    $endSeconds = Parse-TimeText $EndTime.Text
    if ($endSeconds -le $startSeconds) { throw 'El final debe ser posterior al inicio.' }
    if ($script:mediaDuration -gt 0 -and $endSeconds -gt $script:mediaDuration + 0.02) { throw 'El final supera la duración del video.' }
    if (-not $script:jobDir) {
        $safeName = [IO.Path]::GetFileNameWithoutExtension($VideoPath.Text) -replace '[^A-Za-z0-9_-]','_'
        $script:jobDir = Join-Path $jobsRoot ("{0}_{1}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'),$safeName)
        New-Item -ItemType Directory -Path $script:jobDir -Force | Out-Null
    }
    $startArgument = $startSeconds.ToString('R',[Globalization.CultureInfo]::InvariantCulture)
    $endArgument = $endSeconds.ToString('R',[Globalization.CultureInfo]::InvariantCulture)
    $args = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action {1} -Source "{2}" -StartSeconds {3} -EndSeconds {4} -JobDir "{5}"' -f $worker,$action,$VideoPath.Text,$startArgument,$endArgument,$script:jobDir
    if ($editedVideo) { $args += (' -EditedVideo "{0}"' -f $editedVideo) }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $args -WindowStyle Hidden | Out-Null
    $script:activeAction = $action
    $script:openedResult = $false
    $PrepareButton.IsEnabled = $false
    $AllKeysButton.IsEnabled = $false
    $LocalAIButton.IsEnabled = $false
    $ImportButton.IsEnabled = $false
    $FolderButton.IsEnabled = $true
    $StatusText.Text = if ($action -eq 'Prepare') { 'Preparando tramo para EbSynth' } elseif ($action -eq 'GenerateAllKeyframes') { 'Generando keyframes de todo el intervalo' } else { 'Reinsertando tramo editado' }
}

$BrowseButton.Add_Click({
    $dialog = [Microsoft.Win32.OpenFileDialog]::new()
    $dialog.Filter = 'Videos|*.mp4;*.mov;*.mkv;*.avi;*.webm;*.mxf|Todos los archivos|*.*'
    if ($dialog.ShowDialog()) { $VideoPath.Text = $dialog.FileName; $script:jobDir = $null }
})

$AnalyzeButton.Add_Click({
    try {
        if (-not (Test-Path -LiteralPath $VideoPath.Text)) { throw 'Elegí un archivo de video válido.' }
        $json = & $ffprobe -v error -show_streams -show_format -of json $VideoPath.Text | ConvertFrom-Json
        $video = $json.streams | Where-Object codec_type -eq 'video' | Select-Object -First 1
        $script:mediaDuration = [double]$json.format.duration
        $duration = [TimeSpan]::FromSeconds($script:mediaDuration)
        $MediaInfo.Text = "Resolución: $($video.width) × $($video.height) | FPS: $($video.avg_frame_rate) | Duración: $($duration.ToString('hh\:mm\:ss\.fff'))"
        if ($script:mediaDuration -lt 10) { $EndTime.Text = $duration.ToString('hh\:mm\:ss\.fff') }
        $PrepareButton.IsEnabled = $true
        $AllKeysButton.IsEnabled = $true
        $FullRangeButton.IsEnabled = $true
    } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'Error') | Out-Null }
})

$PrepareButton.Add_Click({ try { Start-Worker 'Prepare' } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'Error') | Out-Null } })
$AllKeysButton.Add_Click({ try { Start-Worker 'GenerateAllKeyframes' } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'Error') | Out-Null } })
$FullRangeButton.Add_Click({
    if ($script:mediaDuration -gt 0) {
        $StartTime.Text = '00:00:00.000'
        $EndTime.Text = [TimeSpan]::FromSeconds($script:mediaDuration).ToString('hh\:mm\:ss\.fff')
    }
})
$WebButton.Add_Click({ Start-Process 'https://ebsynth.com/app' })
$FolderButton.Add_Click({ if ($script:jobDir -and (Test-Path -LiteralPath $script:jobDir)) { Start-Process explorer.exe $script:jobDir } })
$LocalAIButton.Add_Click({
    try {
        $keyframesRoot = Join-Path $script:jobDir 'KEYFRAMES_TODO_EL_VIDEO'
        if (-not (Test-Path -LiteralPath $keyframesRoot)) { throw 'Primero generá los keyframes de todo el video.' }
        $generator = Join-Path $studioRoot 'LocalKeyframeAI.ps1'
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -KeyframesRoot "{1}"' -f $generator,$keyframesRoot
        Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments | Out-Null
    } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'Error') | Out-Null }
})
$ImportButton.Add_Click({
    try {
        if (-not $script:jobDir) { throw 'Primero prepará un tramo para EbSynth.' }
        $dialog = [Microsoft.Win32.OpenFileDialog]::new()
        $dialog.Filter = 'Resultado MP4 de EbSynth|*.mp4|Todos los videos|*.mp4;*.mov;*.mkv;*.webm'
        if ($dialog.ShowDialog()) { Start-Worker 'Reintegrate' $dialog.FileName }
    } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'Error') | Out-Null }
})

$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({
    if (-not $script:jobDir) { return }
    $statusFile = Join-Path $script:jobDir 'status.txt'
    if (-not (Test-Path -LiteralPath $statusFile)) { return }
    $parts = (Get-Content -LiteralPath $statusFile -Raw -Encoding UTF8).Split('|',3)
    $stage = $parts[0]
    $percent = if ($parts.Count -gt 1) { [int]$parts[1] } else { 0 }
    $message = if ($parts.Count -gt 2) { $parts[2] } else { '' }
    $Progress.Value = $percent
    $ProgressText.Text = "$percent %"
    $StatusText.Text = "$stage - $message"
    $DetailText.Text = "Trabajo: $script:jobDir"
    if ($stage -eq 'DONE') {
        $PrepareButton.IsEnabled = $true
        $AllKeysButton.IsEnabled = $true
        $ImportButton.IsEnabled = $true
        $LocalAIButton.IsEnabled = Test-Path -LiteralPath (Join-Path $script:jobDir 'KEYFRAMES_TODO_EL_VIDEO')
        if (-not $script:openedResult) {
            $script:openedResult = $true
            if ($script:activeAction -eq 'Prepare') {
                Start-Process explorer.exe $script:jobDir
                Start-Process 'https://ebsynth.com/app'
            } elseif (Test-Path -LiteralPath $message) {
                Start-Process -FilePath $message
            }
        }
    }
    if ($stage -eq 'ERROR') {
        $PrepareButton.IsEnabled = $true
        $AllKeysButton.IsEnabled = $true
        $ImportButton.IsEnabled = [bool]$script:jobDir
        $LocalAIButton.IsEnabled = [bool]($script:jobDir -and (Test-Path -LiteralPath (Join-Path $script:jobDir 'KEYFRAMES_TODO_EL_VIDEO')))
    }
})
$timer.Start()

$lastJob = Get-ChildItem -LiteralPath $jobsRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($lastJob -and (Test-Path -LiteralPath (Join-Path $lastJob.FullName 'job.json'))) {
    try {
        $meta = Get-Content -LiteralPath (Join-Path $lastJob.FullName 'job.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:jobDir = $lastJob.FullName
        $VideoPath.Text = $meta.source
        $StartTime.Text = [TimeSpan]::FromSeconds([double]$meta.start_seconds).ToString('hh\:mm\:ss\.fff')
        $EndTime.Text = [TimeSpan]::FromSeconds([double]$meta.end_seconds).ToString('hh\:mm\:ss\.fff')
        $FolderButton.IsEnabled = $true
        $ImportButton.IsEnabled = $true
        $LocalAIButton.IsEnabled = Test-Path -LiteralPath (Join-Path $script:jobDir 'KEYFRAMES_TODO_EL_VIDEO')
    } catch { }
}

$window.ShowDialog() | Out-Null
