param(
    [string]$KeyframesRoot = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms
$studioRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installer = Join-Path $studioRoot 'install_local_ai.ps1'
$worker = Join-Path $studioRoot 'local_ai_job.ps1'
$model = Join-Path $studioRoot 'models\v1-5-pruned-emaonly.safetensors'
$script:statusFile = ''
$script:activeAction = ''
$script:appMutex = $null

$createdNew = $false
$script:appMutex = [Threading.Mutex]::new($true, 'AnimeVideoStudio_LocalAI_Window', [ref]$createdNew)
if (-not $createdNew) {
  [System.Windows.MessageBox]::Show('El generador de IA local ya esta abierto. Usa la ventana existente.','Ya esta abierto') | Out-Null
  exit 0
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Generador IA de keyframes" Width="1040" Height="860"
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
    <Style TargetType="ComboBox">
      <Setter Property="Height" Value="38"/>
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
          <Setter Property="Background" Value="#D946EF"/>
          <Setter Property="Foreground" Value="#FFFFFF"/>
        </Trigger>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="#F472B6"/>
          <Setter Property="Foreground" Value="#1A1020"/>
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
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" CornerRadius="14" Padding="20" Margin="0,0,0,14" Background="#111926" BorderBrush="#2E3C52" BorderThickness="1">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="270"/></Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock Text="IA LOCAL PARA KEYFRAMES" FontSize="32" FontWeight="Bold" Foreground="#FF7AC5"/>
          <TextBlock Text="Redibuja los keyframes con mas detalle antes de usarlos en EbSynth." Foreground="#B6C2D4" Margin="0,5,0,0"/>
        </StackPanel>
        <Border Grid.Column="1" Background="#0C1421" CornerRadius="10" Padding="11" BorderBrush="#2A3A50" BorderThickness="1">
          <TextBlock Text="Pasos: instala la IA, prueba una imagen y despues genera todas." TextWrapping="Wrap" Foreground="#8DFFCE" FontSize="13"/>
        </Border>
      </Grid>
    </Border>

    <Border Grid.Row="1" Background="#122033" BorderBrush="#2A4869" BorderThickness="1" CornerRadius="12" Padding="14" Margin="0,0,0,12">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Border Grid.Column="0" Margin="0,0,10,0" Background="#0F1C2D" BorderBrush="#2563EB" BorderThickness="1.5" CornerRadius="10" Padding="10">
          <StackPanel>
            <TextBlock Text="PASO 1" Foreground="#6DCFF6" FontWeight="Bold"/>
            <TextBlock Text="Elige la carpeta de keyframes." TextWrapping="Wrap" Margin="0,4,0,0"/>
          </StackPanel>
        </Border>
        <Border Grid.Column="1" Margin="0,0,10,0" Background="#24170F" BorderBrush="#F59E0B" BorderThickness="1.5" CornerRadius="10" Padding="10">
          <StackPanel>
            <TextBlock Text="PASO 2" Foreground="#FCD34D" FontWeight="Bold"/>
            <TextBlock Text="Prueba una sola imagen primero." TextWrapping="Wrap" Margin="0,4,0,0"/>
          </StackPanel>
        </Border>
        <Border Grid.Column="2" Background="#0F2018" BorderBrush="#10B981" BorderThickness="1.5" CornerRadius="10" Padding="10">
          <StackPanel>
            <TextBlock Text="PASO 3" Foreground="#86EFAC" FontWeight="Bold"/>
            <TextBlock Text="Si te gusta, genera todas las imagenes." TextWrapping="Wrap" Margin="0,4,0,0"/>
          </StackPanel>
        </Border>
      </Grid>
    </Border>

    <Border Grid.Row="2" Background="#151D29" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="12" Padding="14" Margin="0,0,0,12">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="150"/></Grid.ColumnDefinitions>
        <TextBox Name="FolderPath"/>
        <Button Name="BrowseButton" Grid.Column="1" Content="Buscar carpeta" Margin="10,0,0,0"/>
      </Grid>
    </Border>

    <Grid Grid.Row="3" Margin="0,0,0,12">
      <Grid.ColumnDefinitions><ColumnDefinition Width="270"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Border Grid.Column="0" Background="#151D29" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="11" Padding="12" Margin="0,0,10,0">
        <StackPanel>
          <TextBlock Text="1. ESTILO" FontWeight="Bold" Foreground="#7DD3FC" Margin="0,0,0,6"/>
          <ComboBox Name="StyleBox" SelectedIndex="0">
            <ComboBoxItem Content="Anime dibujado a mano"/>
            <ComboBoxItem Content="Cartoon cinematográfico"/>
            <ComboBoxItem Content="Cómic ilustrado"/>
          </ComboBox>
        </StackPanel>
      </Border>
      <Border Grid.Column="1" Background="#151D29" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="11" Padding="12">
        <StackPanel>
          <TextBlock Text="2. DESCRIPCION DEL ESTILO" FontWeight="Bold" Foreground="#FCD34D" Margin="0,0,0,6"/>
          <TextBlock Text="Conviene escribirla en ingles." Foreground="#A5B4C7" Margin="0,0,0,6"/>
          <TextBox Name="PromptBox" Height="62" TextWrapping="Wrap" AcceptsReturn="True"/>
        </StackPanel>
      </Border>
    </Grid>

    <Border Grid.Row="4" Background="#151D29" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="11" Padding="12" Margin="0,0,0,12">
      <StackPanel>
        <TextBlock Text="3. QUE EVITAR" FontWeight="Bold" Foreground="#F9A8D4" Margin="0,0,0,6"/>
        <TextBox Name="NegativeBox"/>
      </StackPanel>
    </Border>

    <Grid Grid.Row="5" Margin="0,0,0,12">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="185"/><ColumnDefinition Width="185"/></Grid.ColumnDefinitions>
      <Border Grid.Column="0" Background="#151D29" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="11" Padding="12" Margin="0,0,10,0">
        <StackPanel>
          <TextBlock Name="StrengthText" Text="Fuerza del redibujo: 0.45" FontWeight="Bold" Foreground="#86EFAC"/>
          <Slider Name="StrengthSlider" Minimum="0.15" Maximum="0.70" Value="0.45" TickFrequency="0.01" IsSnapToTickEnabled="True" Margin="0,8,0,0"/>
        </StackPanel>
      </Border>
      <Border Grid.Column="1" Background="#151D29" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="11" Padding="12" Margin="0,0,10,0">
        <StackPanel>
          <TextBlock Text="Cantidad de pasos (2 a 8)" FontWeight="Bold" Foreground="#9DD8FF" Margin="0,0,0,6"/>
          <TextBox Name="StepsBox" Text="4" Height="34"/>
        </StackPanel>
      </Border>
      <Border Grid.Column="2" Background="#151D29" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="11" Padding="12">
        <StackPanel>
          <TextBlock Text="Semilla fija" FontWeight="Bold" Foreground="#9DD8FF" Margin="0,0,0,6"/>
          <TextBox Name="SeedBox" Text="424242" Height="34"/>
        </StackPanel>
      </Border>
    </Grid>

    <Grid Grid.Row="6" Margin="0,0,0,12">
      <Grid.ColumnDefinitions><ColumnDefinition Width="210"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="150"/></Grid.ColumnDefinitions>
      <Button Name="InstallButton" Content="Instalar IA local" Background="#2563EB"/>
      <Button Name="PreviewButton" Grid.Column="1" Content="Probar 1 keyframe" Margin="10,0,0,0" Background="#8B5CF6"/>
      <Button Name="AllButton" Grid.Column="2" Content="Generar todos" Margin="10,0,0,0" Background="#D946EF"/>
      <Button Name="OpenButton" Grid.Column="3" Content="Ver carpeta" Margin="10,0,0,0"/>
    </Grid>

    <Border Grid.Row="7" Background="#0A1018" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="12" Padding="14">
      <StackPanel>
        <TextBlock Name="StatusText" Text="LISTO PARA CONFIGURAR" FontSize="16" FontWeight="Bold"/>
        <Grid Margin="0,10,0,0">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="90"/></Grid.ColumnDefinitions>
          <ProgressBar Name="Progress" Height="22" Minimum="0" Maximum="100" Value="0" Foreground="#20E39A" Background="#223245"/>
          <Border Grid.Column="1" Margin="10,0,0,0" CornerRadius="7" Background="#111C2A" BorderBrush="#29435E" BorderThickness="1">
            <TextBlock Name="ProgressText" Text="0 %" HorizontalAlignment="Center" VerticalAlignment="Center" FontWeight="Bold"/>
          </Border>
        </Grid>
        <Border Background="#101A27" BorderBrush="#24384E" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,12,0,0">
          <TextBlock Name="GuideText" Text="Elige la carpeta de keyframes. Despues prueba una imagen antes de generar todas." Foreground="#D6E5F7" TextWrapping="Wrap"/>
        </Border>
        <TextBlock Name="DetailText" Margin="0,12,0,0" Foreground="#B9FBC0" TextWrapping="Wrap" Text="Primero instala los modelos. La descarga total es de unos 5,9 GB y se realiza una sola vez."/>
      </StackPanel>
    </Border>

    <TextBlock Grid.Row="8" Margin="0,14,0,0" Foreground="#FDE68A" TextWrapping="Wrap"
               Text="En esta PC cada cuadro puede demorar varios minutos. Generar todos reanuda automáticamente y no repite imágenes ya terminadas."/>
  </Grid>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
foreach ($name in 'FolderPath','BrowseButton','StyleBox','PromptBox','NegativeBox','StrengthText','StrengthSlider','StepsBox','SeedBox','InstallButton','PreviewButton','AllButton','OpenButton','StatusText','Progress','ProgressText','GuideText','DetailText') {
    Set-Variable -Name $name -Value $window.FindName($name)
}

function Format-StageText([string]$stage) {
  switch ($stage) {
    'INSTALLING' { return 'Instalando componentes' }
    'LOADING_AI' { return 'Cargando modelo de IA' }
    'GENERATING_AI' { return 'Generando imágenes' }
    'DONE' { return 'Terminado' }
    'ERROR' { return 'Error' }
    default { return $stage }
  }
}

$presets = @(
    'hand-drawn 2D anime film frame, clean expressive ink lines, detailed cel shading, fluid character animation, vivid original colors, consistent face, preserve pose and composition',
    'high quality animated cartoon film frame, expressive clean outlines, rich cel shading, lively shapes, vivid original colors, consistent character design, preserve pose and composition',
    'detailed illustrated comic panel, confident hand-drawn linework, graphic shadows, vivid original colors, consistent character design, preserve pose and composition'
)
$PromptBox.Text = $presets[0]
$NegativeBox.Text = 'photorealistic, 3d render, text, watermark, logo, deformed face, extra fingers, extra limbs, blurry, low detail, color shift'
$FolderPath.Text = $KeyframesRoot

function Set-Busy([bool]$busy) {
    $InstallButton.IsEnabled = -not $busy
    $PreviewButton.IsEnabled = -not $busy
    $AllButton.IsEnabled = -not $busy
    $BrowseButton.IsEnabled = -not $busy
}

function Start-Generation([string]$action) {
  if (-not (Test-Path -LiteralPath $FolderPath.Text)) { throw 'Elige una carpeta KEYFRAMES_TODO_EL_VIDEO valida.' }
  if (-not (Test-Path -LiteralPath $model) -or (Get-Item -LiteralPath $model).Length -lt 4000000000L) { throw 'Primero pulsa INSTALAR IA LOCAL y espera a que llegue al 100 %.' }
    $steps = 0
    $seed = 0L
    if (-not [int]::TryParse($StepsBox.Text,[ref]$steps) -or $steps -lt 2 -or $steps -gt 8) { throw 'Con el acelerador LCM, los pasos deben estar entre 2 y 8.' }
    if (-not [long]::TryParse($SeedBox.Text,[ref]$seed)) { throw 'La semilla debe ser un numero entero.' }
    $script:statusFile = Join-Path $FolderPath.Text 'ia_status.txt'
    $prompt64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($PromptBox.Text))
    $negative64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($NegativeBox.Text))
    $strengthArgument = $StrengthSlider.Value.ToString('0.00',[Globalization.CultureInfo]::InvariantCulture)
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action {1} -KeyframesRoot "{2}" -PromptBase64 {3} -NegativePromptBase64 {4} -Strength {5} -Steps {6} -Seed {7} -StatusFile "{8}"' -f $worker,$action,$FolderPath.Text,$prompt64,$negative64,$strengthArgument,$steps,$seed,$script:statusFile
    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden | Out-Null
    $script:activeAction = $action
    Set-Busy $true
    $StatusText.Text = if ($action -eq 'Preview') { 'Generando una vista previa' } else { 'Generando todos los keyframes' }
    $GuideText.Text = if ($action -eq 'Preview') { 'Se esta generando una sola imagen para que revises el estilo.' } else { 'Se estan generando todas las imagenes. Esto puede tardar bastante.' }
}

$BrowseButton.Add_Click({
    $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description = 'Elige la carpeta KEYFRAMES_TODO_EL_VIDEO'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $FolderPath.Text = $dialog.SelectedPath }
})
$StyleBox.Add_SelectionChanged({ if ($StyleBox.SelectedIndex -ge 0) { $PromptBox.Text = $presets[$StyleBox.SelectedIndex] } })
$StrengthSlider.Add_ValueChanged({ $StrengthText.Text = ('Fuerza del redibujo: {0:F2}' -f $StrengthSlider.Value) })
$InstallButton.Add_Click({
    $script:statusFile = Join-Path $studioRoot 'local_ai_install_status.txt'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -StatusFile "{1}"' -f $installer,$script:statusFile
    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden | Out-Null
    $script:activeAction = 'Install'
    Set-Busy $true
    $GuideText.Text = 'Se estan descargando e instalando los componentes de IA local.'
})
$PreviewButton.Add_Click({ try { Start-Generation 'Preview' } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'Error') | Out-Null } })
$AllButton.Add_Click({ try { Start-Generation 'All' } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'Error') | Out-Null } })
$OpenButton.Add_Click({ if (Test-Path -LiteralPath $FolderPath.Text) { Start-Process explorer.exe $FolderPath.Text } })

$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({
    if (-not $script:statusFile -or -not (Test-Path -LiteralPath $script:statusFile)) { return }
    try {
        $parts = (Get-Content -LiteralPath $script:statusFile -Raw -Encoding UTF8).Split('|',3)
        $stage = $parts[0]
        $percent = if ($parts.Count -gt 1) { [int]$parts[1] } else { 0 }
        $message = if ($parts.Count -gt 2) { $parts[2] } else { '' }
        $Progress.Value = $percent
        $ProgressText.Text = "$percent %"
        $StatusText.Text = Format-StageText $stage
        $GuideText.Text = switch ($stage) {
          'INSTALLING' { 'Se estan instalando los componentes necesarios.' }
          'LOADING_AI' { 'La IA se esta cargando en memoria antes de generar imagenes.' }
          'GENERATING_AI' { 'La IA esta redibujando las imagenes seleccionadas.' }
          'DONE' { 'Listo. Revisa el resultado antes de seguir con EbSynth.' }
          'ERROR' { 'Hubo un error. Mira el detalle de abajo para ver que fallo.' }
          default { $message }
        }
        $DetailText.Text = $message
        if ($stage -eq 'DONE') {
            Set-Busy $false
        } elseif ($stage -eq 'ERROR') { Set-Busy $false }
    } catch { }
})
$timer.Start()

$installStatus = Join-Path $studioRoot 'local_ai_install_status.txt'
if (Test-Path -LiteralPath $installStatus) {
    $installParts = (Get-Content -LiteralPath $installStatus -Raw -Encoding UTF8).Split('|',3)
    if ($installParts[0] -eq 'INSTALLING') {
        $script:statusFile = $installStatus
        $script:activeAction = 'Install'
        Set-Busy $true
    }
}
$generationStatus = if ($FolderPath.Text) { Join-Path $FolderPath.Text 'ia_status.txt' } else { '' }
if ($generationStatus -and (Test-Path -LiteralPath $generationStatus)) {
    $generationParts = (Get-Content -LiteralPath $generationStatus -Raw -Encoding UTF8).Split('|',3)
    if ($generationParts[0] -in @('LOADING_AI','GENERATING_AI')) {
        $script:statusFile = $generationStatus
        $script:activeAction = 'All'
        Set-Busy $true
    }
}
if ((Test-Path -LiteralPath $model) -and (Get-Item -LiteralPath $model).Length -ge 4000000000L) {
    $DetailText.Text = 'El modelo local ya esta instalado. Prueba primero un keyframe.'
  $GuideText.Text = 'La IA ya esta lista. Prueba una imagen y, si te gusta, genera todas.'
}
try {
  $window.ShowDialog() | Out-Null
} finally {
  if ($script:appMutex) {
    $script:appMutex.ReleaseMutex()
    $script:appMutex.Dispose()
  }
}
