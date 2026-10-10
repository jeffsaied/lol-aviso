' Abre o HUD sem mostrar a janela preta do PowerShell.
pasta = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & pasta & "\lol-hud.ps1""", 0, False
