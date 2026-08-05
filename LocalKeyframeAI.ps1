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
$script:openedResult = $false
$script:activeAction = ''

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Generador IA de keyframes" Width="1040" Height="790"
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
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" CornerRadius="14" Padding="20" Margin="0,0,0,14" Background="#111926" BorderBrush="#2E3C52" BorderThickness="1">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="270"/></Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock Text="IA LOCAL PARA KEYFRAMES" FontSize="32" FontWeight="Bold" Foreground="#FF7AC5"/>
          <TextBlock Text="Transformación imagen a imagen con continuidad visual para EbSynth" Foreground="#B6C2D4" Margin="0,5,0,0"/>
        </StackPanel>
        <Border Grid.Column="1" Background="#0C1421" CornerRadius="10" Padding="11" BorderBrush="#2A3A50" BorderThickness="1">
          <TextBlock Text="Flujo recomendado: instalar IA, probar 1 keyframe y luego generar todos." TextWrapping="Wrap" Foreground="#8DFFCE" FontSize="13"/>
        </Border>
      </Grid>
    </Border>

    <Border Grid.Row="1" Background="#151D29" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="12" Padding="14" Margin="0,0,0,12">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="150"/></Grid.ColumnDefinitions>
        <TextBox Name="FolderPath"/>
        <Button Name="BrowseButton" Grid.Column="1" Content="Elegir carpeta" Margin="10,0,0,0"/>
      </Grid>
    </Border>

    <Grid Grid.Row="2" Margin="0,0,0,12">
      <Grid.ColumnDefinitions><ColumnDefinition Width="270"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Border Grid.Column="0" Background="#151D29" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="11" Padding="12" Margin="0,0,10,0">
        <StackPanel>
          <TextBlock Text="Estilo" FontWeight="Bold" Foreground="#9DD8FF" Margin="0,0,0,6"/>
          <ComboBox Name="StyleBox" SelectedIndex="0">
            <ComboBoxItem Content="Anime dibujado a mano"/>
            <ComboBoxItem Content="Cartoon cinematográfico"/>
            <ComboBoxItem Content="Cómic ilustrado"/>
          </ComboBox>
        </StackPanel>
      </Border>
      <Border Grid.Column="1" Background="#151D29" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="11" Padding="12">
        <StackPanel>
          <TextBlock Text="Prompt principal (mejor en inglés)" FontWeight="Bold" Foreground="#9DD8FF" Margin="0,0,0,6"/>
          <TextBox Name="PromptBox" Height="62" TextWrapping="Wrap" AcceptsReturn="True"/>
        </StackPanel>
      </Border>
    </Grid>

    <Border Grid.Row="3" Background="#151D29" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="11" Padding="12" Margin="0,0,0,12">
      <StackPanel>
        <TextBlock Text="Negative prompt" FontWeight="Bold" Foreground="#9DD8FF" Margin="0,0,0,6"/>
        <TextBox Name="NegativeBox"/>
      </StackPanel>
    </Border>

    <Grid Grid.Row="4" Margin="0,0,0,12">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="185"/><ColumnDefinition Width="185"/></Grid.ColumnDefinitions>
      <Border Grid.Column="0" Background="#151D29" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="11" Padding="12" Margin="0,0,10,0">
        <StackPanel>
          <TextBlock Name="StrengthText" Text="Fuerza del redibujo: 0.45" FontWeight="Bold" Foreground="#9DD8FF"/>
          <Slider Name="StrengthSlider" Minimum="0.15" Maximum="0.70" Value="0.45" TickFrequency="0.01" IsSnapToTickEnabled="True" Margin="0,8,0,0"/>
        </StackPanel>
      </Border>
      <Border Grid.Column="1" Background="#151D29" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="11" Padding="12" Margin="0,0,10,0">
        <StackPanel>
          <TextBlock Text="Pasos (2 a 8)" FontWeight="Bold" Foreground="#9DD8FF" Margin="0,0,0,6"/>
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

    <Grid Grid.Row="5" Margin="0,0,0,12">
      <Grid.ColumnDefinitions><ColumnDefinition Width="210"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="150"/></Grid.ColumnDefinitions>
      <Button Name="InstallButton" Content="Instalar IA local" Background="#246BFF"/>
      <Button Name="PreviewButton" Grid.Column="1" Content="Probar 1 keyframe" Margin="10,0,0,0" Background="#8B5CF6"/>
      <Button Name="AllButton" Grid.Column="2" Content="Generar todos" Margin="10,0,0,0" Background="#D946EF"/>
      <Button Name="OpenButton" Grid.Column="3" Content="Abrir carpeta" Margin="10,0,0,0"/>
    </Grid>

    <Border Grid.Row="6" Background="#0A1018" BorderBrush="#2A3A50" BorderThickness="1" CornerRadius="12" Padding="14">
      <StackPanel>
        <TextBlock Name="StatusText" Text="Listo para configurar" FontSize="16" FontWeight="Bold"/>
        <Grid Margin="0,10,0,0">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="90"/></Grid.ColumnDefinitions>
          <ProgressBar Name="Progress" Height="22" Minimum="0" Maximum="100" Value="0" Foreground="#20E39A" Background="#223245"/>
          <Border Grid.Column="1" Margin="10,0,0,0" CornerRadius="7" Background="#111C2A" BorderBrush="#29435E" BorderThickness="1">
            <TextBlock Name="ProgressText" Text="0 %" HorizontalAlignment="Center" VerticalAlignment="Center" FontWeight="Bold"/>
          </Border>
        </Grid>
        <TextBlock Name="DetailText" Margin="0,12,0,0" Foreground="#B9FBC0" TextWrapping="Wrap" Text="Primero instalá los modelos. La descarga total es de unos 5,9 GB y se realiza una sola vez."/>
      </StackPanel>
    </Border>

    <TextBlock Grid.Row="7" Margin="0,14,0,0" Foreground="#FDE68A" TextWrapping="Wrap"
               Text="En esta PC cada cuadro puede demorar varios minutos. GENERAR TODOS reanuda automáticamente y no repite imágenes ya terminadas."/>
  </Grid>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
foreach ($name in 'FolderPath','BrowseButton','StyleBox','PromptBox','NegativeBox','StrengthText','StrengthSlider','StepsBox','SeedBox','InstallButton','PreviewButton','AllButton','OpenButton','StatusText','Progress','ProgressText','DetailText') {
    Set-Variable -Name $name -Value $window.FindName($name)
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
    if (-not (Test-Path -LiteralPath $FolderPath.Text)) { throw 'Elegí una carpeta KEYFRAMES_TODO_EL_VIDEO válida.' }
    if (-not (Test-Path -LiteralPath $model) -or (Get-Item -LiteralPath $model).Length -lt 4000000000L) { throw 'Primero pulsá INSTALAR IA LOCAL y esperá a que llegue al 100 %.' }
    $steps = 0
    $seed = 0L
    if (-not [int]::TryParse($StepsBox.Text,[ref]$steps) -or $steps -lt 2 -or $steps -gt 8) { throw 'Con el acelerador LCM, los pasos deben estar entre 2 y 8.' }
    if (-not [long]::TryParse($SeedBox.Text,[ref]$seed)) { throw 'La semilla debe ser un número entero.' }
    $script:statusFile = Join-Path $FolderPath.Text 'ia_status.txt'
    $prompt64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($PromptBox.Text))
    $negative64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($NegativeBox.Text))
    $strengthArgument = $StrengthSlider.Value.ToString('0.00',[Globalization.CultureInfo]::InvariantCulture)
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action {1} -KeyframesRoot "{2}" -PromptBase64 {3} -NegativePromptBase64 {4} -Strength {5} -Steps {6} -Seed {7} -StatusFile "{8}"' -f $worker,$action,$FolderPath.Text,$prompt64,$negative64,$strengthArgument,$steps,$seed,$script:statusFile
    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden | Out-Null
    $script:activeAction = $action
    $script:openedResult = $false
    Set-Busy $true
    $StatusText.Text = if ($action -eq 'Preview') { 'Generando una vista previa' } else { 'Generando todos los keyframes' }
}

$BrowseButton.Add_Click({
    $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description = 'Elegí la carpeta KEYFRAMES_TODO_EL_VIDEO'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $FolderPath.Text = $dialog.SelectedPath }
})
$StyleBox.Add_SelectionChanged({ if ($StyleBox.SelectedIndex -ge 0) { $PromptBox.Text = $presets[$StyleBox.SelectedIndex] } })
$StrengthSlider.Add_ValueChanged({ $StrengthText.Text = ('Fuerza del redibujo: {0:F2}' -f $StrengthSlider.Value) })
$InstallButton.Add_Click({
    $script:statusFile = Join-Path $studioRoot 'local_ai_install_status.txt'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -StatusFile "{1}"' -f $installer,$script:statusFile
    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden | Out-Null
    $script:activeAction = 'Install'
    $script:openedResult = $false
    Set-Busy $true
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
        $StatusText.Text = $stage
        $DetailText.Text = $message
        if ($stage -eq 'DONE') {
            Set-Busy $false
            if (-not $script:openedResult) {
                $script:openedResult = $true
                if ($script:activeAction -eq 'Preview' -and (Test-Path -LiteralPath $message)) { Start-Process -FilePath $message }
                elseif ($script:activeAction -eq 'All' -and (Test-Path -LiteralPath $message)) { Start-Process explorer.exe $message }
            }
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
    $DetailText.Text = 'El modelo local ya está instalado. Probá primero un keyframe.'
}
$window.ShowDialog() | Out-Null
