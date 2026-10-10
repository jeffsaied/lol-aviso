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
  <Grid>
  <Ellipse x:Name="Bolinha" Width="35" Height="35" Fill="#1FA84A" Stroke="#F0E6D2" StrokeThickness="1.5" Visibility="Collapsed"
           HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,40,55,6"/>
  <Border x:Name="Painel" CornerRadius="14" Background="#0A1428" BorderBrush="#C8AA6E" BorderThickness="1.5" Margin="8">
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
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="LOL AVISO" Foreground="#C8AA6E" FontSize="11" FontWeight="Bold" VerticalAlignment="Center"/>
            <Border x:Name="Teste" Margin="8,0,0,0" Padding="6,1" CornerRadius="4" Background="#1E2A3F" BorderBrush="#C8AA6E" BorderThickness="1"
                    Cursor="Hand" ToolTip="Manda um aviso de teste pro celular">
              <TextBlock x:Name="TesteTxt" Text="TESTE" Foreground="#F0E6D2" FontSize="9" FontWeight="Bold"/>
            </Border>
          </StackPanel>
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
        <TextBlock Text="✔  No ARAM, manda as cartas pro celular com botão de escolher" Foreground="#F0E6D2" FontSize="12" Margin="0,2"/>
        <TextBlock Text="✔  Se ninguém escolher a tempo, escolhe sozinho" Foreground="#F0E6D2" FontSize="12" Margin="0,2"/>
        <TextBlock Text="      (pega um campeão que você joga bastante)" Foreground="#A09B8C" FontSize="11"/>
        <TextBlock Text="✔  Tira a tela de carregamento da frente" Foreground="#F0E6D2" FontSize="12" Margin="0,2"/>
        <TextBlock Text="      (2º monitor, ou minimiza; volta quando o jogo abre)" Foreground="#A09B8C" FontSize="11"/>
        <TextBlock Text="✔  Avisa no celular quando o jogo abre no mapa" Foreground="#F0E6D2" FontSize="12" Margin="0,2"/>
        <TextBlock x:Name="Topico" Text="" Foreground="#A09B8C" FontSize="11" Margin="0,8,0,0" Cursor="Hand"
                   TextTrimming="CharacterEllipsis" ToolTip="Clique para configurar o aviso no celular"/>
      </StackPanel>
    </Border>
    </StackPanel>
  </Border>
  </Grid>
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
    if ($script:testeAte -and (Get-Date) -gt $script:testeAte) { $testeTxt.Text = 'TESTE'; $script:testeAte = $null }
    if (-not (Esta-Ligado)) {
        $script:pidVigia = 0
        $botao.Background = $vermelho; $botao.Content = 'OFF'; $bolinha.Fill = $vermelho
        $status.Text = 'Desligado'
        $detalhe.Text = 'Clique no botão para ligar'
        return
    }
    $botao.Background = $verde; $botao.Content = 'ON'; $bolinha.Fill = $verde
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

# Parado por 3 s, o painel vira so a bolinha (metade do botao, 25% de opacidade); mexer o mouse em cima abre de novo.
$painel = $win.FindName('Painel')
$bolinha = $win.FindName('Bolinha')
$compacto = $false
$ultimoMexer = Get-Date
$ultimaPos = ''
function Compactar($sim) {
    if ($sim) { $painel.Visibility = 'Collapsed'; $bolinha.Visibility = 'Visible'; $win.Opacity = 0.25 }
    else { $bolinha.Visibility = 'Collapsed'; $painel.Visibility = 'Visible'; $win.Opacity = 1 }
    $script:compacto = $sim
}
# Compara a posicao na tela: trocar o painel pela bolinha dispara MouseMove sozinho, sem o mouse ter andado.
$win.Add_MouseMove({
    $p = $win.PointToScreen($_.GetPosition($win))
    $pos = "$([int]$p.X),$([int]$p.Y)"
    if ($pos -ne $script:ultimaPos) {
        $script:ultimaPos = $pos
        $script:ultimoMexer = Get-Date
        if ($script:compacto) { Compactar $false }
    }
})
$timerParado = New-Object Windows.Threading.DispatcherTimer
$timerParado.Interval = [TimeSpan]::FromMilliseconds(250)
$timerParado.Add_Tick({
    if (-not $script:compacto -and ((Get-Date) - $script:ultimoMexer).TotalSeconds -ge 3) { Compactar $true }
})
$timerParado.Start()

$botao.Add_Click({ $script:ultimoMexer = Get-Date; if (Esta-Ligado) { Desligar } else { Ligar }; Atualizar })
$fechar.Add_MouseLeftButtonDown({ $_.Handled = $true; $win.Close() })

# Painel "o que ele faz": o ? mostra/esconde; a linha do topico copia o nome para colar no app ntfy.
$info = $win.FindName('Info')
$linhaTopico = $win.FindName('Topico')

# O topico do ntfy e' a pessoa que inventa, na caixa abaixo; o vigia le o mesmo arquivo.
$ArqTopico = Join-Path $Pasta 'topico.txt'
$Exemplo = 'lol-jeffi-exemplo'
$topico = ''
if (Test-Path $ArqTopico) { $topico = [IO.File]::ReadAllText($ArqTopico).Trim() }
function Mostrar-LinhaTopico {
    if ($script:topico) { $linhaTopico.Text = "Celular: tópico $($script:topico)  ·  alterar" }
    else { $linhaTopico.Text = 'Celular: falta configurar  ·  clique aqui' }
}
Mostrar-LinhaTopico

# Manda o aviso de teste para o topico salvo; devolve $true se o ntfy aceitou.
function Enviar-Teste {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $corpo = [Text.Encoding]::UTF8.GetBytes('Chegou! Seu celular está ligado ao LoL Aviso.')
        Invoke-RestMethod -Uri "https://ntfy.sh/$($script:topico)" -Method Post -Body $corpo -TimeoutSec 8 `
            -Headers @{ Title = 'LoL Aviso - teste'; Tags = 'video_game' } | Out-Null
        return $true
    } catch { return $false }
}

# Botao TESTE do painel: sem topico, abre a caixa de configurar; com topico, envia e mostra o resultado no proprio botao.
$testeTxt = $win.FindName('TesteTxt')
$testeAte = $null
$win.FindName('Teste').Add_MouseLeftButtonDown({
    $_.Handled = $true
    $script:ultimoMexer = Get-Date
    if (-not $script:topico) { Abrir-AjudaCelular; return }
    if (Enviar-Teste) { $testeTxt.Text = 'ENVIADO' } else { $testeTxt.Text = 'FALHOU' }
    $script:testeAte = (Get-Date).AddSeconds(3)
})

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
      <TextBlock Text="2.  Invente um nome de tópico só seu e escreva aqui:" Foreground="#F0E6D2" FontSize="13" TextWrapping="Wrap" Margin="0,10,0,6"/>
      <Border Margin="20,0,0,0" Background="#061020" BorderBrush="#C8AA6E" BorderThickness="1" CornerRadius="6" Padding="10,6">
        <Grid>
          <TextBlock x:Name="Exemplo" Text="lol-jeffi-exemplo" Foreground="#5B6577" FontFamily="Consolas" FontSize="16"
                     VerticalAlignment="Center" IsHitTestVisible="False" Margin="2,0,0,0"/>
          <TextBox x:Name="CaixaTopico" Background="Transparent" BorderThickness="0" Foreground="#F5D76E" CaretBrush="#F5D76E"
                   FontFamily="Consolas" FontSize="16" VerticalAlignment="Center" MaxLength="64"/>
        </Grid>
      </Border>
      <TextBlock Text="3.  No app, toque em + e assine esse mesmo nome." Foreground="#F0E6D2" FontSize="13" TextWrapping="Wrap" Margin="0,12,0,0"/>
      <TextBlock Text="4.  Clique em Enviar teste e veja se chega no celular." Foreground="#F0E6D2" FontSize="13" TextWrapping="Wrap" Margin="0,10,0,0"/>
      <TextBlock Text="Escolha um nome difícil de adivinhar: quem souber o nome recebe os seus avisos." Foreground="#A09B8C" FontSize="11" TextWrapping="Wrap" Margin="0,12,0,0"/>
      <TextBlock x:Name="Resultado" Text="" Foreground="#F5D76E" FontSize="12" TextWrapping="Wrap" Margin="0,8,0,0" MinHeight="16"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
        <Button x:Name="Testar" Content="Enviar teste"/>
        <Button x:Name="Depois" Content="Depois" Margin="8,0,0,0"/>
        <Button x:Name="Pronto" Content="Salvar" Margin="8,0,0,0" Background="#1FA84A" FontWeight="Bold"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@

# Grava o topico digitado na caixa; devolve $false (com o motivo na tela) se o nome nao serve.
function Salvar-Topico {
    $novo = $script:dlgCaixa.Text.Trim()
    if ($novo -eq $Exemplo) { $script:dlgResultado.Text = 'Esse é só o exemplo. Invente um nome seu.'; return $false }
    if ($novo -notmatch '^[A-Za-z0-9_-]{6,64}$') {
        $script:dlgResultado.Text = 'Use de 6 a 64 letras, números, - ou _ (sem espaço e sem acento).'
        return $false
    }
    [IO.File]::WriteAllText($ArqTopico, $novo)
    $script:topico = $novo
    Mostrar-LinhaTopico
    return $true
}

# Caixa que ensina a ligar o celular. Abre sozinha enquanto nao houver topico salvo.
$dlg = $null
function Abrir-AjudaCelular {
    if ($script:dlg) { $script:dlg.Activate(); return }
    $script:dlg = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xamlCelular))
    $script:dlgResultado = $script:dlg.FindName('Resultado')
    $script:dlgCaixa = $script:dlg.FindName('CaixaTopico')
    $script:dlgExemplo = $script:dlg.FindName('Exemplo')
    $script:dlgCaixa.Add_TextChanged({
        if ($script:dlgCaixa.Text) { $script:dlgExemplo.Visibility = 'Collapsed' } else { $script:dlgExemplo.Visibility = 'Visible' }
    })
    $script:dlgCaixa.Text = $script:topico
    $script:dlg.FindName('Testar').Add_Click({
        if (-not (Salvar-Topico)) { return }
        if (Enviar-Teste) { $script:dlgResultado.Text = 'Teste enviado. Se não chegou, confira se o nome no app está igual.' }
        else { $script:dlgResultado.Text = 'Não consegui enviar o teste. Confira a internet e tente de novo.' }
    })
    $script:dlg.FindName('Depois').Add_Click({ $script:dlg.Close() })
    $script:dlg.FindName('Pronto').Add_Click({ if (Salvar-Topico) { $script:dlg.Close() } })
    $script:dlg.Add_MouseLeftButtonDown({ try { $script:dlg.DragMove() } catch {} })
    $script:dlg.Add_Closed({ $script:dlg = $null })
    $script:dlg.Show()
}

$win.FindName('Ajuda').Add_MouseLeftButtonDown({
    $_.Handled = $true
    if ($info.Visibility -eq 'Visible') { $info.Visibility = 'Collapsed' } else { $info.Visibility = 'Visible' }
})
$linhaTopico.Add_MouseLeftButtonDown({ $_.Handled = $true; Abrir-AjudaCelular })
$win.Add_ContentRendered({ if (-not $script:topico) { Abrir-AjudaCelular } })
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
