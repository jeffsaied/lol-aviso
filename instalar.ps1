# Instala o LoL Aviso neste PC: copia os arquivos, cria o topico do celular, o atalho e a entrada de iniciar com o Windows.
param(
    [string]$Destino = (Join-Path $env:LOCALAPPDATA 'LoL-Aviso'),
    [switch]$SoCopiar   # so copia e cria o topico (usado para testar o instalador)
)
$origem = Split-Path -Parent $MyInvocation.MyCommand.Path

# Fecha uma versao que ja esteja aberta, para poder sobrescrever.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like "*$Destino\lol-*" -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

New-Item -ItemType Directory -Force $Destino | Out-Null
foreach ($f in 'lol-aviso.ps1', 'lol-hud.ps1', 'LoL Aviso.vbs', 'icone.png') {
    Copy-Item (Join-Path $origem "arquivos\$f") $Destino -Force
}

# Topico proprio de cada pessoa; se ja existe (reinstalacao), mantem.
$arqTopico = Join-Path $Destino 'topico.txt'
if (-not (Test-Path $arqTopico)) {
    $letras = 'abcdefghijkmnpqrstuvwxyz23456789'.ToCharArray()
    $sorteio = -join (1..12 | ForEach-Object { $letras | Get-Random })
    [IO.File]::WriteAllText($arqTopico, "lol-$sorteio")
}
$topico = [IO.File]::ReadAllText($arqTopico).Trim()

if (-not $SoCopiar) {
    $vbs = Join-Path $Destino 'LoL Aviso.vbs'
    $wscript = "$env:WINDIR\System32\wscript.exe"

    $atalho = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'LoL Aviso.lnk'))
    $atalho.TargetPath = $wscript
    $atalho.Arguments = "`"$vbs`""
    $atalho.WorkingDirectory = $Destino
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        $exe = Join-Path $d.Name 'Riot Games\League of Legends\LeagueClient.exe'
        if ($d.DriveType -eq 'Fixed' -and (Test-Path $exe)) { $atalho.IconLocation = "$exe,0"; break }
    }
    $atalho.Save()

    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'LoL Aviso' -Value "`"$wscript`" `"$vbs`""
    Start-Process $wscript -ArgumentList "`"$vbs`""
    try { Set-Clipboard $topico } catch {}
}

Write-Host ''
Write-Host 'LoL Aviso instalado.' -ForegroundColor Green
Write-Host ''
Write-Host 'No celular: instale o app "ntfy", toque em + e assine este topico:'
Write-Host ''
Write-Host "    $topico" -ForegroundColor Yellow
Write-Host ''
Write-Host '(ja foi copiado; e tambem fica guardado em topico.txt na pasta do programa)'
Write-Host ''
