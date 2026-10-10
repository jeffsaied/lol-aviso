# HUD do LoL Aviso: um botao liga/desliga o vigia (lol-aviso.ps1) e mostra o que ele esta fazendo.
# Abrir pelo atalho "LoL Aviso" ou pelo LoL Aviso.vbs (sem janela preta).
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$Pasta  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Vigia  = Join-Path $Pasta 'lol-aviso.ps1'
$ArqLog = Join-Path $Pasta 'lol-aviso.log'
$Icone  = Join-Path $Pasta 'icone.png'

# So um HUD por vez.
$novo = $false
$mutex = New-Object Threading.Mutex($true, 'LolAvisoHud', [ref]$novo)
if (-not $novo) { return }

$Fases = @{
    'Fechado'         = 'LoL fechado'
    'None'            = 'No menu'
    'Lobby'           = 'No lobby'
    'Matchmaking'     = 'Na fila'
    'ReadyCheck'      = 'Partida encontrada'
    'ChampSelect'     = 'Seleção de campeões'
    'GameStart'       = 'Abrindo o jogo'
    'InProgress'      = 'Em partida'
    'Reconnect'       = 'Reconectar'
    'WaitingForStats' = 'Fim de jogo'
    'PreEndOfGame'    = 'Fim de jogo'
    'EndOfGame'       = 'Fim de jogo'
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="LoL Aviso" Width="392" SizeToContent="Height" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ResizeMode="NoResize" WindowStartupLocation="Manual">
  <Border CornerRadius="14" Background="#0A1428" BorderBrush="#C8AA6E" BorderThickness="1.5" Margin="8">
    <Border.Effect><DropShadowEffect BlurRadius="12" ShadowDepth="0" Opacity="0.7"/></Border.Effect>
    <StackPanel>
    <Grid Height="100">
      <Grid Margin="14,12,30,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Border Width="76" Height="76" CornerRadius="10" BorderBrush="#C8AA6E" BorderThickness="1.5">
          <Border.Background><ImageBrush x:Name="Img" Stretch="UniformToFill"/></Border.Background>
        </Border>
        <StackPanel Grid.Column="1" Margin="14,0,10,0" VerticalAlignment="Center">
          <TextBlock Text="LOL AVISO" Foreground="#C8AA6E" FontSize="11" FontWeight="Bold"/>
          <TextBlock x:Name="Status" Text="..." Foreground="#F0E6D2" FontSize="17" FontWeight="SemiBold" Margin="0,3,0,3" TextTrimming="CharacterEllipsis"/>
          <TextBlock x:Name="Detalhe" Text="" Foreground="#A09B8C" FontSize="11" TextTrimming="CharacterEllipsis"/>
        </StackPanel>
        <Button x:Name="Botao" Grid.Column="2" Width="70" Height="70" Cursor="Hand" Foreground="White"
                FontSize="18" FontWeight="Bold" Content="ON" Background="#1FA84A" ToolTip="Clique para ligar ou desligar">
          <Button.Template>
            <ControlTemplate TargetType="Button">
              <Grid>
                <Ellipse Fill="{TemplateBinding Background}" Stroke="#F0E6D2" StrokeThickness="2"/>
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Grid>
              <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True"><Setter Property="Opacity" Value="0.85"/></Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
          </Button.Template>
        </Button>
      </Grid>
      <TextBlock x:Name="Fechar" Text="✕" Foreground="#A09B8C" FontSize="13" Cursor="Hand" ToolTip="Fechar (desliga o vigia)"
                 HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,7,11,0"/>
      <TextBlock x:Name="Ajuda" Text="?" Foreground="#C8AA6E" FontSize="14" FontWeight="Bold" Cursor="Hand" ToolTip="Mostrar ou esconder o que ele faz"
                 HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,12,8"/>
    </Grid>
    <Border x:Name="Info" BorderBrush="#26334D" BorderThickness="0,1,0,0" Margin="14,0,14,12" Padding="0,10,0,0">
      <StackPanel>
        <TextBlock Text="O QUE ELE FAZ" Foreground="#C8AA6E" FontSize="10" FontWeight="Bold" Margin="0,0,0,5"/>
        <TextBlock Text="✔  Aceita a partida sozinho quando a fila encontra" Foreground="#F0E6D2" FontSize="12" Margin="0,2"/>
        <TextBlock Text="✔  No ARAM, escolhe a carta se você não escolher a tempo" Foreground="#F0E6D2" FontSize="12" Margin="0,2"/>
        <TextBlock Text="      (pega um campeão que você joga bastante)" Foreground="#A09B8C" FontSize="11"/>
        <TextBlock Text="✔  Tira a tela de carregamento da frente" Foreground="#F0E6D2" FontSize="12" Margin="0,2"/>
        <TextBlock Text="      (2º monitor, ou minimiza; volta quando o jogo abre)" Foreground="#A09B8C" FontSize="11"/>
        <TextBlock Text="✔  Avisa no celular quando o jogo abre no mapa" Foreground="#F0E6D2" FontSize="12" Margin="0,2"/>
        <TextBlock x:Name="Topico" Text="" Foreground="#A09B8C" FontSize="11" Margin="0,8,0,0" Cursor="Hand"
                   TextTrimming="CharacterEllipsis" ToolTip="Clique para ver como ligar o celular"/>
      </StackPanel>
    </Border>
    </StackPanel>
  </Border>
</Window>
'@

$win     = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$status  = $win.FindName('Status')
$detalhe = $win.FindName('Detalhe')
$botao   = $win.FindName('Botao')
$fechar  = $win.FindName('Fechar')
$verde   = [Windows.Media.BrushConverter]::new().ConvertFromString('#1FA84A')
$vermelho = [Windows.Media.BrushConverter]::new().ConvertFromString('#D13639')

if (Test-Path $Icone) {
    $bmp = New-Object Windows.Media.Imaging.BitmapImage
    $bmp.BeginInit(); $bmp.CacheOption = 'OnLoad'; $bmp.UriSource = [Uri]$Icone; $bmp.EndInit()
    $win.FindName('Img').ImageSource = $bmp
}

$area = [Windows.SystemParameters]::WorkArea
$win.Left = $area.Right - $win.Width - 8
$win.Top  = $area.Top + 8

function Achar-Vigias {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -like '*lol-aviso.ps1*' } | ForEach-Object { [int]$_.ProcessId }
}
function Ligar {
    $p = Start-Process powershell -WindowStyle Hidden -PassThru `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$Vigia`""
    $script:pidVigia = $p.Id
}
function Desligar {
    foreach ($id in @(Achar-Vigias)) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    $script:pidVigia = 0
}
function Esta-Ligado {
    $script:pidVigia -gt 0 -and (Get-Process -Id $script:pidVigia -ErrorAction SilentlyContinue)
}

function Atualizar {
    if (-not (Esta-Ligado)) {
        $script:pidVigia = 0
        $botao.Background = $vermelho; $botao.Content = 'OFF'
        $status.Text = 'Desligado'
        $detalhe.Text = 'Clique no botão para ligar'
        return
    }
    $botao.Background = $verde; $botao.Content = 'ON'
    $fase = ''; $ultimo = ''
    try {
        foreach ($l in @(Get-Content $ArqLog -Tail 40 -Encoding UTF8 -ErrorAction Stop)) {
            if ($l.Length -lt 20) { continue }
            $txt = $l.Substring(20)
            if ($txt -like 'fase: *') { $fase = $txt.Substring(6) }
            elseif ($txt -notlike 'vigiando*') { $ultimo = $l.Substring(11, 5) + '  ' + $txt }
        }
    } catch {}
    if ($Fases.ContainsKey($fase)) { $status.Text = $Fases[$fase] } elseif ($fase) { $status.Text = $fase } else { $status.Text = 'Ligado' }
    if ($ultimo) { $detalhe.Text = $ultimo } else { $detalhe.Text = 'Vigiando a fila' }
}

# Ao abrir: aproveita um vigia que ja esteja rodando; senao liga.
$pidVigia = 0
$ja = @(Achar-Vigias)
if ($ja.Count -gt 0) { $pidVigia = $ja[0] } else { Ligar }

$botao.Add_Click({ if (Esta-Ligado) { Desligar } else { Ligar }; Atualizar })
$fechar.Add_MouseLeftButtonDown({ $_.Handled = $true; $win.Close() })

# Painel "o que ele faz": o ? mostra/esconde; a linha do topico copia o nome para colar no app ntfy.
$info = $win.FindName('Info')
$linhaTopico = $win.FindName('Topico')

# Cada instalacao tem o seu topico do ntfy; o vigia le o mesmo arquivo.
$ArqTopico = Join-Path $Pasta 'topico.txt'
$ArqCelularOk = Join-Path $Pasta 'celular-ok.txt'   # existe depois que a pessoa diz que ja configurou
if (-not (Test-Path $ArqTopico)) {
    $letras = 'abcdefghijkmnpqrstuvwxyz23456789'.ToCharArray()
    $sorteio = -join (1..12 | ForEach-Object { $letras | Get-Random })
    [IO.File]::WriteAllText($ArqTopico, "lol-$sorteio")
}
$topico = [IO.File]::ReadAllText($ArqTopico).Trim()
$linhaTopico.Text = "Celular: tópico $topico  ·  como configurar"

[xml]$xamlCelular = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="LoL Aviso - celular" Width="440" SizeToContent="Height" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ResizeMode="NoResize" WindowStartupLocation="CenterScreen" ShowInTaskbar="False">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#F0E6D2"/>
      <Setter Property="Background" Value="#1E2A3F"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Padding" Value="14,7"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" BorderBrush="#C8AA6E" BorderThickness="1" CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter Property="Opacity" Value="0.85"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border CornerRadius="14" Background="#0A1428" BorderBrush="#C8AA6E" BorderThickness="1.5" Margin="8" Padding="22,18">
    <Border.Effect><DropShadowEffect BlurRadius="12" ShadowDepth="0" Opacity="0.7"/></Border.Effect>
    <StackPanel>
      <TextBlock Text="AVISO NO CELULAR" Foreground="#C8AA6E" FontSize="11" FontWeight="Bold"/>
      <TextBlock Text="Ligue o seu celular ao LoL Aviso" Foreground="#F0E6D2" FontSize="18" FontWeight="SemiBold" Margin="0,4,0,6"/>
      <TextBlock Text="Para receber o aviso quando o jogo abrir, faça isto uma vez:" Foreground="#A09B8C" FontSize="12" TextWrapping="Wrap" Margin="0,0,0,12"/>
      <TextBlock Text="1.  Baixe o app ntfy no celular (Android ou iPhone)." Foreground="#F0E6D2" FontSize="13" TextWrapping="Wrap"/>
      <TextBlock Text="2.  No app, toque em + e assine o seu tópico:" Foreground="#F0E6D2" FontSize="13" TextWrapping="Wrap" Margin="0,10,0,6"/>
      <Grid Margin="20,0,0,0">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Border Background="#061020" BorderBrush="#26334D" BorderThickness="1" CornerRadius="6" Padding="10,6">
          <TextBox x:Name="CaixaTopico" IsReadOnly="True" Background="Transparent" BorderThickness="0" Foreground="#F5D76E"
                   FontFamily="Consolas" FontSize="16" VerticalAlignment="Center"/>
        </Border>
        <Button x:Name="Copiar" Grid.Column="1" Content="Copiar" Margin="8,0,0,0"/>
      </Grid>
      <TextBlock Text="3.  Clique em Enviar teste e veja se chega no celular." Foreground="#F0E6D2" FontSize="13" TextWrapping="Wrap" Margin="0,12,0,0"/>
      <TextBlock Text="O tópico é só seu: quem souber o nome recebe os seus avisos." Foreground="#A09B8C" FontSize="11" TextWrapping="Wrap" Margin="0,12,0,0"/>
      <TextBlock x:Name="Resultado" Text="" Foreground="#F5D76E" FontSize="12" TextWrapping="Wrap" Margin="0,8,0,0" MinHeight="16"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
        <Button x:Name="Testar" Content="Enviar teste"/>
        <Button x:Name="Depois" Content="Depois" Margin="8,0,0,0"/>
        <Button x:Name="Pronto" Content="Já configurei" Margin="8,0,0,0" Background="#1FA84A" FontWeight="Bold"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@

# Caixa que ensina a ligar o celular. Abre sozinha ate a pessoa clicar em "Ja configurei".
$dlg = $null
function Abrir-AjudaCelular {
    if ($script:dlg) { $script:dlg.Activate(); return }
    $script:dlg = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xamlCelular))
    $script:dlgResultado = $script:dlg.FindName('Resultado')
    $script:dlg.FindName('CaixaTopico').Text = $topico
    $script:dlg.FindName('Copiar').Add_Click({
        [Windows.Clipboard]::SetText($topico)
        $script:dlgResultado.Text = 'Tópico copiado.'
    })
    $script:dlg.FindName('Testar').Add_Click({
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $corpo = [Text.Encoding]::UTF8.GetBytes('Chegou! Seu celular está ligado ao LoL Aviso.')
            Invoke-RestMethod -Uri "https://ntfy.sh/$topico" -Method Post -Body $corpo -TimeoutSec 8 `
                -Headers @{ Title = 'LoL Aviso - teste'; Tags = 'video_game' } | Out-Null
            $script:dlgResultado.Text = 'Teste enviado. Se não chegou, confira se o tópico no app está igual.'
        } catch {
            $script:dlgResultado.Text = 'Não consegui enviar o teste. Confira a internet e tente de novo.'
        }
    })
    $script:dlg.FindName('Depois').Add_Click({ $script:dlg.Close() })
    $script:dlg.FindName('Pronto').Add_Click({
        try { [IO.File]::WriteAllText($ArqCelularOk, (Get-Date -Format 'yyyy-MM-dd')) } catch {}
        $script:dlg.Close()
    })
    $script:dlg.Add_MouseLeftButtonDown({ try { $script:dlg.DragMove() } catch {} })
    $script:dlg.Add_Closed({ $script:dlg = $null })
    $script:dlg.Show()
}

$win.FindName('Ajuda').Add_MouseLeftButtonDown({
    $_.Handled = $true
    if ($info.Visibility -eq 'Visible') { $info.Visibility = 'Collapsed' } else { $info.Visibility = 'Visible' }
})
$linhaTopico.Add_MouseLeftButtonDown({ $_.Handled = $true; Abrir-AjudaCelular })
$win.Add_ContentRendered({ if (-not (Test-Path $ArqCelularOk)) { Abrir-AjudaCelular } })
$win.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch {} })
$win.Add_Closed({ Desligar })

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({ Atualizar })
$timer.Start()
Atualizar

[void]$win.ShowDialog()
$timer.Stop()
$mutex.ReleaseMutex()
