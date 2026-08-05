param([Parameter(Mandatory=$true)][string]$JobDir)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Progreso — Anime gratuito" Width="680" Height="330"
        WindowStartupLocation="CenterScreen" Background="#151821"
        Foreground="#F4F6FA" FontFamily="Segoe UI" Topmost="True">
  <Grid Margin="24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Name="Heading" Text="PROCESANDO VIDEO" FontSize="24" FontWeight="Bold" Foreground="#62D9FF"/>
    <TextBlock Grid.Row="1" Name="StageText" Text="Iniciando..." FontSize="15" Margin="0,12,0,12" TextWrapping="Wrap"/>
    <StackPanel Grid.Row="2">
      <ProgressBar Name="Progress" Minimum="0" Maximum="100" Value="0" Height="28" Foreground="#23C483" Background="#303746"/>
      <TextBlock Name="PercentText" Text="0 %" FontSize="18" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,7,0,14"/>
    </StackPanel>
    <Border Grid.Row="3" Background="#0B0E13" CornerRadius="5" Padding="10">
      <TextBlock Name="DetailText" Foreground="#B9FBC0" TextWrapping="Wrap"/>
    </Border>
    <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
      <Button Name="OpenButton" Content="Abrir carpeta" Width="135" Height="36" Background="#334155" Foreground="White" Margin="0,0,10,0"/>
      <Button Name="OpenVideoButton" Content="Abrir video" Width="135" Height="36" Background="#7C3AED" Foreground="White" IsEnabled="False"/>
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
    $window.Title = 'Progreso — Video vertical con subtítulos'
    $Heading.Text = 'VIDEO VERTICAL 9:16 + SUBTÍTULOS'
} else {
    $window.Title = 'Progreso — Anime gratuito'
    $Heading.Text = 'REDIBUJANDO VIDEO COMPLETO'
}

$OpenButton.Add_Click({ if (Test-Path -LiteralPath $JobDir) { Start-Process explorer.exe $JobDir } })
$OpenVideoButton.Add_Click({ if ($script:finalVideo -and (Test-Path -LiteralPath $script:finalVideo)) { Start-Process -FilePath $script:finalVideo } })

$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({
    $statusFile = Join-Path $JobDir 'status.txt'
    $logFile = Join-Path $JobDir 'processing.stderr.log'
    if (-not (Test-Path -LiteralPath $statusFile)) {
        $StageText.Text = 'Esperando que comience el trabajo...'
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
        TRANSCRIBING='Generando subtítulos automáticos'
        FORMATTING='Adaptando el video a pantalla vertical 9:16'
        CONFORMING='Restaurando resolución y audio'
        DONE='Terminado'
        ERROR='Error'
    }
    $label = if ($labels.ContainsKey($stage)) { $labels[$stage] } else { $stage }
    $Progress.Value = $percent
    $PercentText.Text = "$percent %"
    $StageText.Text = $label
    $DetailText.Text = "$frames`n$message`n`nSalida: $JobDir"

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
