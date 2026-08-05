param([Parameter(Mandatory=$true)][string]$JobDir)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Progreso del trabajo" Width="760" Height="390"
        WindowStartupLocation="CenterScreen" Background="#0E131B"
        Foreground="#E6ECF5" FontFamily="Bahnschrift" Topmost="True">
  <Grid Margin="24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" Grid.RowSpan="2" Background="#111926" BorderBrush="#2E3C52" BorderThickness="1" CornerRadius="12" Padding="16" Margin="0,0,0,12">
      <StackPanel>
        <TextBlock Grid.Row="0" Name="Heading" Text="PROCESANDO VIDEO" FontSize="28" FontWeight="Bold" Foreground="#62D9FF"/>
        <TextBlock Grid.Row="1" Name="StageText" Text="Preparando el proceso..." FontSize="15" Margin="0,10,0,0" TextWrapping="Wrap" Foreground="#D8E3F1"/>
      </StackPanel>
    </Border>
    <StackPanel Grid.Row="2">
      <ProgressBar Name="Progress" Minimum="0" Maximum="100" Value="0" Height="24" Foreground="#20E39A" Background="#223245"/>
      <TextBlock Name="PercentText" Text="0 %" FontSize="18" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,8,0,14" Foreground="#F7FBFF"/>
    </StackPanel>
    <Border Grid.Row="3" Background="#0A1018" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="10" Padding="12">
      <TextBlock Name="DetailText" Foreground="#B9FBC0" TextWrapping="Wrap"/>
    </Border>
    <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
      <Button Name="OpenButton" Content="Ver carpeta" Width="140" Height="38" Background="#334155" Foreground="White" Margin="0,0,10,0"/>
      <Button Name="OpenVideoButton" Content="Abrir resultado" Width="150" Height="38" Background="#246BFF" Foreground="White" IsEnabled="False"/>
    </StackPanel>
  </Grid>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$Heading = $window.FindName('Heading')
$StageText = $window.FindName('StageText')
$Progress = $window.FindName('Progress')
$PercentText = $window.FindName('PercentText')
$DetailText = $window.FindName('DetailText')
$OpenButton = $window.FindName('OpenButton')
$OpenVideoButton = $window.FindName('OpenVideoButton')
$script:finalVideo = $null

if ($JobDir -like '*VERTICAL*') {
  $window.Title = 'Progreso - Video vertical con subtitulos'
  $Heading.Text = 'CREANDO VIDEO VERTICAL CON SUBTÍTULOS'
} else {
  $window.Title = 'Progreso - Conversion de video'
  $Heading.Text = 'CREANDO TU VIDEO ESTILIZADO'
}

$OpenButton.Add_Click({ if (Test-Path -LiteralPath $JobDir) { Start-Process explorer.exe $JobDir } })
$OpenVideoButton.Add_Click({ if ($script:finalVideo -and (Test-Path -LiteralPath $script:finalVideo)) { Start-Process -FilePath $script:finalVideo } })

$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({
    $statusFile = Join-Path $JobDir 'status.txt'
    $logFile = Join-Path $JobDir 'processing.stderr.log'
    if (-not (Test-Path -LiteralPath $statusFile)) {
        $StageText.Text = 'Esperando que empiece el trabajo...'
        return
    }

    $parts = (Get-Content -LiteralPath $statusFile -Raw -Encoding UTF8).Split('|',3)
    $stage = $parts[0]
    $percent = if ($parts.Count -gt 1) { [int]$parts[1] } else { 0 }
    $message = if ($parts.Count -gt 2) { $parts[2] } else { '' }
    $frames = ''

    if ($stage -eq 'DRAWING' -and (Test-Path -LiteralPath $logFile)) {
        $raw = Get-Content -LiteralPath $logFile -Raw -ErrorAction SilentlyContinue
        $matches = [regex]::Matches($raw,'PROGRESS\|(\d+)\|(\d+)\|(\d+)')
        if ($matches.Count) {
            $last = $matches[$matches.Count - 1]
            $percent = [int]$last.Groups[3].Value
            $frames = "Fotogramas: $($last.Groups[1].Value) / $($last.Groups[2].Value)"
        }
    }
    if ($stage -eq 'TRANSCRIBING' -and (Test-Path -LiteralPath $logFile)) {
        $raw = Get-Content -LiteralPath $logFile -Raw -ErrorAction SilentlyContinue
        $matches = [regex]::Matches($raw,'TRANSCRIBE\|([0-9.]+)\|([0-9.]+)\|(\d+)')
        if ($matches.Count) {
            $last = $matches[$matches.Count - 1]
            $percent = [int]$last.Groups[3].Value
            $frames = "Audio analizado: $($last.Groups[1].Value) / $($last.Groups[2].Value) segundos"
        }
    }

    $labels = @{
        PREPARING='Preparando el video'
        DRAWING='Dibujando fotograma por fotograma'
        TRANSCRIBING='Generando subtitulos automaticos'
        FORMATTING='Adaptando el video a pantalla vertical 9:16'
        CONFORMING='Restaurando resolucion y audio'
        DONE='Terminado'
        ERROR='Error'
    }
    $label = if ($labels.ContainsKey($stage)) { $labels[$stage] } else { $stage }
    $Progress.Value = $percent
    $PercentText.Text = "$percent %"
    $StageText.Text = $label
    $help = switch ($stage) {
      'PREPARING' { 'El sistema esta preparando el material antes de empezar.' }
      'DRAWING' { 'Se esta procesando cuadro por cuadro. Este paso suele ser el mas largo.' }
      'TRANSCRIBING' { 'Se esta escuchando el audio para crear subtitulos.' }
      'FORMATTING' { 'Se esta adaptando el video al formato vertical.' }
      'CONFORMING' { 'Se esta armando el archivo final con audio y resolucion correctos.' }
      'DONE' { 'Listo. Ya podes abrir el resultado.' }
      'ERROR' { 'Hubo un error. Revisa el mensaje para saber que revisar.' }
      default { '' }
    }
    $DetailText.Text = "$help`n$frames`n$message`n`nCarpeta del trabajo: $JobDir"

    if ($stage -eq 'DONE') {
        $script:finalVideo = $message
        $OpenVideoButton.IsEnabled = $true
        $window.Topmost = $false
        $timer.Stop()
    }
    if ($stage -eq 'ERROR') {
        $window.Topmost = $false
        $timer.Stop()
    }
})

$timer.Start()
$window.ShowDialog() | Out-Null
