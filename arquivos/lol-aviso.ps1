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
        return @{ Porta = $partes[2]; Auth = @{ Authorization = "Basic $b64" } }
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
        $faseAnterior = $fase
        $avisouMapa = $false
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
    if ($fase -eq 'InProgress' -and -not $avisouMapa) {
        try {
            $ev = Invoke-RestMethod -Uri 'https://127.0.0.1:2999/liveclientdata/eventdata' -TimeoutSec 2
            if ($ev.Events | Where-Object { $_.EventName -eq 'GameStart' }) {
                Avisar 'LoL - dentro do mapa' 'Carregamento terminou, o jogo abriu.' 'urgent'
                $avisouMapa = $true
            }
        } catch {}
    }
    Start-Sleep -Seconds 1
}
