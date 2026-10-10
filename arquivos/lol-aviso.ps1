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

# Cada instalacao tem o seu topico do ntfy (topico.txt); e' o nome que se assina no app do celular.
$ArqTopico = Join-Path $Pasta 'topico.txt'
if (-not (Test-Path $ArqTopico)) {
    $letras = 'abcdefghijkmnpqrstuvwxyz23456789'.ToCharArray()
    $sorteio = -join (1..12 | ForEach-Object { $letras | Get-Random })
    [IO.File]::WriteAllText($ArqTopico, "lol-$sorteio")
}
$Topico = [IO.File]::ReadAllText($ArqTopico).Trim()

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

function Avisar($titulo, $texto, $prioridade = 'high') {
    try {
        $corpo = [Text.Encoding]::UTF8.GetBytes($texto)
        Invoke-RestMethod -Uri "$Servidor/$Topico" -Method Post -Body $corpo `
            -Headers @{ Title = $titulo; Priority = $prioridade; Tags = 'video_game' } | Out-Null
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

# Roda a cada segundo na selecao: se a vez e' sua e o relogio esta acabando, escolhe a carta.
function Cuidar-DaEscolha {
    $s = Lcu Get '/lol-champ-select/v1/session'
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
    }
    if ($resta -gt $SobraParaAgir) { return }

    if ($minha.championId -gt 0) {
        $escolhido = [int]$minha.championId   # voce ja tinha clicado numa carta; so confirma
        $motivo = 'a que voce marcou'
    } else {
        $cartas = @()
        try { $cartas = @(Ids (Lcu Get '/lol-lobby-team-builder/champ-select/v1/subset-champion-list')) } catch {}
        if (-not $cartas) { $cartas = @(Ids (Lcu Get '/lol-champ-select/v1/pickable-champion-ids')) }
        if (-not $cartas) { Log 'nenhuma carta para escolher'; return }
        $escolhido = $script:frequentes | Where-Object { $cartas -contains $_ } | Select-Object -First 1
        if ($escolhido) { $motivo = 'frequente' } else { $escolhido = $cartas | Get-Random; $motivo = 'qualquer uma' }
        Log "cartas: $($cartas -join ',')"
    }
    Lcu Patch "/lol-champ-select/v1/session/actions/$($minha.id)" @{ championId = $escolhido } | Out-Null
    Lcu Post "/lol-champ-select/v1/session/actions/$($minha.id)/complete" | Out-Null
    Log "escolhi o campeao $escolhido ($motivo)"
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

Log "vigiando o LoL. Topico ntfy: $Topico"
$cliente = $null
$faseAnterior = ''
$avisouMapa = $false
$modoDeCarta = $false
$viuEscolha = $false
$frequentes = @()
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
    if ($fase -eq 'ChampSelect' -and $modoDeCarta) {
        try { Cuidar-DaEscolha } catch { Log "falha na escolha: $($_.Exception.Message)" }
    }
    # Durante o carregamento a porta 2999 nao responde; o evento GameStart so aparece dentro do mapa.
    $espera = 1000
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
