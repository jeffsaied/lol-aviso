# Instala o LoL Aviso neste PC: copia os arquivos, cria o atalho e a entrada de iniciar com o Windows.
param(
    [string]$Destino = (Join-Path $env:LOCALAPPDATA 'LoL-Aviso'),
    [switch]$SoCopiar   # so copia os arquivos (usado para testar o instalador)
)
$origem = Split-Path -Parent $MyInvocation.MyCommand.Path

# Fecha uma versao que ja esteja aberta, para poder sobrescrever.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like "*$Destino\lol-*" -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

New-Item -ItemType Directory -Force $Destino | Out-Null
foreach ($f in 'lol-aviso.ps1', 'lol-hud.ps1', 'LoL Aviso.vbs', 'icone.png', 'icone.ico') {
    Copy-Item (Join-Path $origem "arquivos\$f") $Destino -Force
}

if (-not $SoCopiar) {
    $vbs = Join-Path $Destino 'LoL Aviso.vbs'
    $wscript = "$env:WINDIR\System32\wscript.exe"

    $atalho = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'LoL Aviso.lnk'))
    $atalho.TargetPath = $wscript
    $atalho.Arguments = "`"$vbs`""
    $atalho.WorkingDirectory = $Destino
    $atalho.IconLocation = "$(Join-Path $Destino 'icone.ico'),0"
    $atalho.Save()

    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'LoL Aviso' -Value "`"$wscript`" `"$vbs`""
    Start-Process $wscript -ArgumentList "`"$vbs`""
}

Write-Host ''
Write-Host 'LoL Aviso instalado.' -ForegroundColor Green
Write-Host ''
Write-Host 'O painel vai abrir com uma caixa para ligar o seu celular:'
Write-Host 'instale o app "ntfy", invente um nome de topico so seu e siga os passos da caixa.'
Write-Host ''
