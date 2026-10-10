# Vigia do LoL: aceita a partida sozinho, escolhe a carta do ARAM se voce nao escolher
# e avisa no celular (ntfy) quando o jogo abre no mapa.
# Uso:  powershell -ExecutionPolicy Bypass -File lol-aviso.ps1          (fica vigiando)
#       powershell -ExecutionPolicy Bypass -File lol-aviso.ps1 -Teste   (manda um aviso de teste e sai)
param([switch]$Teste)

$Servidor      = 'https://ntfy.sh'
$QtdFrequentes = 30      # os N campeoes com mais maestria contam como "jogo frequentemente"
$SobraParaAgir = 6000    # ms que faltam no relogio quando ele escolhe por voce
$ModosDeCarta  = @('ARAM', 'KIWI')   # KIWI = ARAM Caos
$Pasta         = Split-Path -Parent $MyInvocation.MyCommand.Path
$ArqLog        = Join-Path $Pasta 'lol-aviso.log'

# O topico do ntfy e' escolhido pela pessoa no painel e fica em topico.txt; sem ele, nao ha aviso no celular.
$ArqTopico = Join-Path $Pasta 'topico.txt'
function Ler-Topico {
    try { if (Test-Path $ArqTopico) { return [IO.File]::ReadAllText($ArqTopico).Trim() } } catch {}
    return ''
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# O cliente do LoL usa certificado proprio em 127.0.0.1; so ali o erro de certificado e' aceito.
Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class LcuCertPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) {
        return problem == 0 || sp.Address.Host == "127.0.0.1";
    }
}
"@
[Net.ServicePointManager]::CertificatePolicy = New-Object LcuCertPolicy

Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Janela {
    public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr depois, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern IntPtr GetShellWindow();
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    // O Windows so deixa trocar a janela da frente logo depois de uma tecla; um toque no ALT libera.
    public static void Frente(IntPtr h) {
        keybd_event(0x12, 0, 0, UIntPtr.Zero); keybd_event(0x12, 0, 2, UIntPtr.Zero);
        SetForegroundWindow(h);
    }
}
"@

function Log($texto) {
    $linha = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $texto"
    Write-Host $linha
    try { Add-Content -Path $ArqLog -Value $linha -Encoding UTF8 } catch {}
}

# $acoes: botoes do aviso (ate 3, limite do ntfy), no formato de acao do ntfy.
# $seq: avisos com o mesmo $seq trocam o anterior no celular em vez de empilhar.
function Avisar($titulo, $texto, $prioridade = 'high', $acoes = $null, $seq = '') {
    $Topico = Ler-Topico   # lido na hora: a pessoa pode trocar pelo painel com o vigia rodando
    if (-not $Topico) { Log "sem topico configurado; aviso nao enviado: $titulo"; return }
    try {
        $niveis = @{ urgent = 5; high = 4; default = 3; low = 2 }
        $msg = @{ topic = $Topico; title = $titulo; message = $texto; priority = $niveis[$prioridade]; tags = @('video_game') }
        if ($acoes) { $msg.actions = @($acoes) }
        if ($seq) { $msg.sequence_id = $seq }
        $corpo = [Text.Encoding]::UTF8.GetBytes(($msg | ConvertTo-Json -Depth 5 -Compress))
        Invoke-RestMethod -Uri $Servidor -Method Post -Body $corpo -ContentType 'application/json' -TimeoutSec 8 | Out-Null
        Log "aviso enviado: $titulo"
    } catch {
        Log "falha ao avisar: $($_.Exception.Message)"
    }
}

# Devolve porta e cabecalho de login do cliente, ou $null se o LoL estiver fechado.
function Ler-Cliente {
    $p = Get-Process LeagueClientUx -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) { return $null }
    $pastas = @()
    try { if ($p.Path) { $pastas += Split-Path $p.Path } } catch {}
    try { $pastas += (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Riot Game league_of_legends.live' -ErrorAction Stop).InstallLocation } catch {}
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        if ($d.DriveType -eq 'Fixed') { $pastas += Join-Path $d.Name 'Riot Games\League of Legends' }
    }
    foreach ($pasta in $pastas) {
        $arq = Join-Path $pasta 'lockfile'
        if (-not (Test-Path $arq)) { continue }
        try {
            $fs = [IO.File]::Open($arq, 'Open', 'Read', 'ReadWrite')
            $txt = (New-Object IO.StreamReader($fs)).ReadToEnd()
            $fs.Close()
        } catch { continue }
        $partes = $txt.Split(':')   # LeagueClient:pid:porta:senha:https
        if ($partes.Count -lt 5) { continue }
        $b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("riot:$($partes[3])"))
        return @{ Porta = $partes[2]; Auth = @{ Authorization = "Basic $b64" }; Pasta = $pasta }
    }
    return $null
}

function Lcu($metodo, $caminho, $corpo) {
    $p = @{ Uri = "https://127.0.0.1:$($cliente.Porta)$caminho"; Method = $metodo; Headers = $cliente.Auth; TimeoutSec = 3 }
    if ($null -ne $corpo) { $p.Body = ($corpo | ConvertTo-Json -Compress); $p.ContentType = 'application/json' }
    Invoke-RestMethod @p
}

# Lista de ids vinda do cliente; aceita tanto numeros soltos quanto objetos com championId/id.
function Ids($lista) {
    $r = @()
    foreach ($x in @($lista)) {
        if ($null -eq $x) { continue }
        if ($x -is [ValueType]) { $r += [int]$x }
        elseif ($x.championId) { $r += [int]$x.championId }
        elseif ($x.id) { $r += [int]$x.id }
    }
    return $r | Where-Object { $_ -gt 0 }
}

function Nome($id) {
    if ($script:nomes.ContainsKey([int]$id)) { return $script:nomes[[int]$id] }
    return "campeão $id"
}

# Marca o campeao na sua acao. Nas cartas do ARAM a escolha fica aberta ate o relogio acabar, entao da para trocar depois.
function Escolher($acao, $id, $motivo) {
    Lcu Patch "/lol-champ-select/v1/session/actions/$($acao.id)" @{ championId = [int]$id } | Out-Null
    try { Lcu Post "/lol-champ-select/v1/session/actions/$($acao.id)/complete" | Out-Null } catch {}
    $script:escolhaFeita = $true
    Log "escolhi $(Nome $id) ($motivo)"
}

# Manda as cartas para o celular com um botao para cada (o ntfy aceita ate 3 botoes).
# O botao publica o id do campeao no topico "<topico>-cmd", que o vigia consulta.
function Pedir-NoCelular($segundos) {
    $t = Ler-Topico
    if (-not $t -or -not $script:cartas) { return }
    $acoes = @($script:cartas | Select-Object -First 3 | ForEach-Object {
        @{ action = 'http'; label = (Nome $_); url = "$Servidor/$t-cmd"; method = 'POST'; body = "$_"; clear = $true }
    })
    if ($script:cartas.Count -le 6) { $lista = ($script:cartas | ForEach-Object { Nome $_ }) -join '  ·  ' }
    else { $lista = "$($script:cartas.Count) campeões disponíveis" }
    Avisar 'LoL - escolha o campeão' "$lista`nToque no nome para escolher (faltam $segundos s)." 'urgent' $acoes
}

# Devolve o id do campeao tocado no celular (so se estiver em $validos), ou 0. Cada toque vale uma vez so.
# Consulta o ntfy no maximo a cada 1,5 s (ele corta quem pergunta demais); entre uma e outra vale o ultimo toque lido,
# assim as cartas e o banco olham o mesmo toque sem um roubar a vez do outro.
function Ler-RespostaCelular($validos) {
    $t = Ler-Topico
    if (-not $t -or -not $validos) { return 0 }
    if (((Get-Date) - $script:ultimaConsulta).TotalMilliseconds -ge 1500) {
        $script:ultimaConsulta = Get-Date
        try {
            $r = Invoke-WebRequest -UseBasicParsing -Uri "$Servidor/$t-cmd/json?poll=1&since=20s" -TimeoutSec 3
            $txt = $r.Content
            if ($txt -is [byte[]]) { $txt = [Text.Encoding]::UTF8.GetString($txt) }
            foreach ($linha in ($txt -split "`n")) {
                if (-not $linha.Trim()) { continue }
                $m = $linha | ConvertFrom-Json
                if ($m.event -eq 'message' -and $m.message -match '^\d+$') { $script:toque = [int]$m.message; $script:toqueId = $m.id }
            }
        } catch {}
    }
    if ($script:toque -and $script:toqueId -ne $script:ultimaResposta -and $validos -contains $script:toque) {
        $script:ultimaResposta = $script:toqueId
        return $script:toque
    }
    return 0
}

# Roda varias vezes por segundo na selecao: mostra as cartas no celular, obedece o toque de la
# e, se ninguem escolher e o relogio estiver acabando, escolhe sozinho.
function Cuidar-DaEscolha($s) {
    $minha = $null
    foreach ($grupo in $s.actions) {
        foreach ($a in $grupo) {
            if ($a.actorCellId -eq $s.localPlayerCellId -and $a.type -eq 'pick' -and $a.isInProgress -and -not $a.completed) { $minha = $a }
        }
    }
    if (-not $minha) { return }

    $resta = $s.timer.adjustedTimeLeftInPhase - ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - $s.timer.internalNowInEpochMs)
    if (-not $script:viuEscolha) {
        $script:viuEscolha = $true
        Log "sua vez de escolher (acao $($minha.id)), restam $([int]$resta) ms"
        try { $s | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $Pasta 'ultima-selecao.json') -Encoding UTF8 } catch {}
        $cartas = @()
        try { $cartas = @(Ids (Lcu Get '/lol-lobby-team-builder/champ-select/v1/subset-champion-list')) } catch {}
        if (-not $cartas) { try { $cartas = @(Ids (Lcu Get '/lol-champ-select/v1/pickable-champion-ids')) } catch {} }
        # as que voce joga bastante vem primeiro (viram os botoes do celular e a escolha automatica)
        $script:cartas = @($script:frequentes | Where-Object { $cartas -contains $_ }) + @($cartas | Where-Object { $script:frequentes -notcontains $_ })
        Log "cartas: $(($script:cartas | ForEach-Object { Nome $_ }) -join ', ')"
        Pedir-NoCelular ([int]($resta / 1000))
    }

    $doCelular = Ler-RespostaCelular $script:cartas
    if ($doCelular) { Escolher $minha $doCelular 'pelo celular'; return }

    if ($script:escolhaFeita -or $minha.championId -gt 0 -or $resta -gt $SobraParaAgir) { return }
    if (-not $script:cartas) { Log 'nenhuma carta para escolher'; $script:escolhaFeita = $true; return }
    if ($script:frequentes -contains $script:cartas[0]) { Escolher $minha $script:cartas[0] 'automático: você joga bastante' }
    else { Escolher $minha ($script:cartas | Get-Random) 'automático: qualquer uma' }
}

# Banco do ARAM: as cartas que o time nao quis. Cada vez que o banco muda, o aviso do celular e' trocado
# pela lista nova, com botao para pegar (ate 3, as que voce joga bastante primeiro).
function Cuidar-DoBanco($s) {
    if (-not $s.benchEnabled) { return }
    $banco = @(Ids $s.benchChampions)
    $banco = @($script:frequentes | Where-Object { $banco -contains $_ }) + @($banco | Where-Object { $script:frequentes -notcontains $_ })
    $chave = $banco -join ','
    if ($chave -ne $script:bancoEnviado) {
        $script:bancoEnviado = $chave
        $t = Ler-Topico
        if ($t) {
            if ($banco) {
                Log "banco: $(($banco | ForEach-Object { Nome $_ }) -join ', ')"
                $acoes = @($banco | Select-Object -First 3 | ForEach-Object {
                    @{ action = 'http'; label = (Nome $_); url = "$Servidor/$t-cmd"; method = 'POST'; body = "$_" }
                })
                $lista = ($banco | ForEach-Object { Nome $_ }) -join '  ·  '
                Avisar 'LoL - sobrando no banco' "$lista`nToque no nome para pegar." 'high' $acoes "banco-$($s.gameId)"
            } else {
                Avisar 'LoL - sobrando no banco' 'Banco vazio agora.' 'low' $null "banco-$($s.gameId)"
            }
        }
    }
    $doCelular = Ler-RespostaCelular $banco
    if ($doCelular) {
        Lcu Post "/lol-champ-select/v1/session/bench/swap/$doCelular" | Out-Null
        Log "peguei $(Nome $doCelular) do banco (pelo celular)"
    }
}

# Tira a tela de carregamento da frente: vai para o segundo monitor, ou minimiza se nao der.
# Tela cheia exclusiva (WindowMode=0 no game.cfg) nao aceita ser movida; so "sem bordas" e "janela".
function Esconder-Carregamento {
    $jogo = Get-Process 'League of Legends' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if (-not $jogo) { return }
    $h = $jogo.MainWindowHandle
    $script:janelaJogo = $h
    $script:telaTratada = $true

    $modoJanela = 0
    try {
        $linha = Select-String -Path (Join-Path $cliente.Pasta 'Config\game.cfg') -Pattern '^WindowMode=(\d)' | Select-Object -First 1
        if ($linha) { $modoJanela = [int]$linha.Matches[0].Groups[1].Value }
    } catch {}
    $segunda = [Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary } | Select-Object -First 1

    if ($segunda -and $modoJanela -ne 0) {
        $r = New-Object Janela+RECT
        [void][Janela]::GetWindowRect($h, [ref]$r)
        $script:lugarOriginal = $r
        $b = $segunda.Bounds
        $larg = [Math]::Min($r.R - $r.L, $b.Width); $alt = [Math]::Min($r.B - $r.T, $b.Height)
        [void][Janela]::SetWindowPos($h, [IntPtr]::Zero, $b.X, $b.Y, $larg, $alt, 0x0014)   # sem mexer na ordem nem ativar
        $volta = $script:ultimaJanela
        if (-not $volta -or -not [Janela]::IsWindowVisible($volta)) { $volta = [Janela]::GetShellWindow() }
        [Janela]::Frente($volta)
        $script:modoTela = 'movida'
        Log "carregamento enviado para o segundo monitor ($($segunda.DeviceName))"
    } else {
        [void][Janela]::ShowWindow($h, 6)   # minimiza e devolve o foco para a janela de antes
        $script:modoTela = 'minimizada'
        if ($segunda) { Log 'carregamento minimizado (jogo em tela cheia exclusiva nao pode ser movido)' }
        else { Log 'carregamento minimizado (sem segundo monitor)' }
    }
}

# O jogo abriu no mapa: devolve a janela para o lugar e para a frente.
function Voltar-Jogo {
    if (-not $script:modoTela) { return }
    $h = $script:janelaJogo
    if ($script:modoTela -eq 'movida') {
        $r = $script:lugarOriginal
        [void][Janela]::SetWindowPos($h, [IntPtr]::Zero, $r.L, $r.T, $r.R - $r.L, $r.B - $r.T, 0x0014)
    } else {
        [void][Janela]::ShowWindow($h, 9)
    }
    [Janela]::Frente($h)
    Log 'jogo de volta na tela principal'
    $script:modoTela = ''
}

if ($Teste) {
    Avisar 'LoL - teste' 'Se isso chegou no celular, esta funcionando.'
    return
}

Log 'vigiando o LoL'
$cliente = $null
$faseAnterior = ''
$avisouMapa = $false
$modoDeCarta = $false
$viuEscolha = $false
$frequentes = @()
$cartas = @()
$nomes = @{}
$escolhaFeita = $false
$ultimaResposta = ''
$ultimaConsulta = [datetime]::MinValue
$toque = 0
$toqueId = ''
$bancoEnviado = ''
$primeiraVolta = $true
$telaTratada = $false
$modoTela = ''
$janelaJogo = [IntPtr]::Zero
$ultimaJanela = [IntPtr]::Zero
$lugarOriginal = $null
while ($true) {
    if (-not $cliente) {
        $cliente = Ler-Cliente
        if (-not $cliente) {
            if ($faseAnterior -ne 'Fechado') { Log 'fase: Fechado'; $faseAnterior = 'Fechado' }
            Start-Sleep -Seconds 5
            continue
        }
    }
    try {
        $fase = Lcu Get '/lol-gameflow/v1/gameflow-phase'
    } catch {
        $cliente = $null   # cliente fechou ou reiniciou; le o lockfile de novo
        Start-Sleep -Seconds 3
        continue
    }
    if ($fase -ne $faseAnterior) {
        Log "fase: $fase"
        # Vigia ligado no meio de uma partida: nao mexe na janela nem avisa de novo.
        $avisouMapa = ($primeiraVolta -and $fase -eq 'InProgress')
        $primeiraVolta = $false
        $faseAnterior = $fase
        $telaTratada = $false
        $modoTela = ''
        if ($fase -eq 'ReadyCheck') {
            try {
                Lcu Post '/lol-matchmaking/v1/ready-check/accept' | Out-Null
                Log 'partida aceita'
            } catch {
                Log "falha ao aceitar: $($_.Exception.Message)"
                $faseAnterior = ''   # tenta de novo na proxima volta
            }
        }
        if ($fase -eq 'ChampSelect') {
            $viuEscolha = $false
            $escolhaFeita = $false
            $bancoEnviado = ''
            $cartas = @()
            $nomes = @{}
            try { foreach ($c in (Lcu Get '/lol-game-data/assets/v1/champion-summary.json')) { $nomes[[int]$c.id] = $c.name } } catch {}
            $modoDeCarta = $false
            try {
                $modo = (Lcu Get '/lol-gameflow/v1/session').gameData.queue.gameMode
                $modoDeCarta = $ModosDeCarta -contains $modo
                $m = Lcu Get '/lol-champion-mastery/v1/local-player/champion-mastery'
                $frequentes = @($m | Sort-Object championPoints -Descending | Select-Object -First $QtdFrequentes | ForEach-Object { [int]$_.championId })
                Log "selecao no modo $modo; escolha automatica: $modoDeCarta"
            } catch { Log "falha ao preparar a selecao: $($_.Exception.Message)" }
        }
    }
    $espera = 1000
    if ($fase -eq 'ChampSelect' -and $modoDeCarta) {
        try {
            $sessao = Lcu Get '/lol-champ-select/v1/session'
            Cuidar-DaEscolha $sessao
            Cuidar-DoBanco $sessao
        } catch { Log "falha na escolha: $($_.Exception.Message)" }
        if ($viuEscolha) { $espera = 300 }   # responde rapido ao toque no celular
    }
    # Durante o carregamento a porta 2999 nao responde; o evento GameStart so aparece dentro do mapa.
    if ($fase -eq 'ChampSelect') {
        $naFrente = [Janela]::GetForegroundWindow()
        if ($naFrente -ne [IntPtr]::Zero) { $ultimaJanela = $naFrente }   # para onde devolver o foco no carregamento
    }
    if ($fase -eq 'InProgress' -and -not $avisouMapa) {
        $espera = 300   # a janela do jogo aparece de repente; olha mais vezes para tirar da frente logo
        $carregando = $false
        try {
            $ev = Invoke-RestMethod -Uri 'https://127.0.0.1:2999/liveclientdata/eventdata' -TimeoutSec 2
            if ($ev.Events | Where-Object { $_.EventName -eq 'GameStart' }) {
                try { Voltar-Jogo } catch { Log "falha ao voltar o jogo: $($_.Exception.Message)" }
                Avisar 'LoL - dentro do mapa' 'Carregamento terminou, o jogo abriu.' 'urgent'
                $avisouMapa = $true
            }
        } catch { $carregando = $true }
        if ($carregando -and -not $telaTratada) {
            try { Esconder-Carregamento } catch { Log "falha ao esconder o carregamento: $($_.Exception.Message)" }
        }
    }
    Start-Sleep -Milliseconds $espera
}
