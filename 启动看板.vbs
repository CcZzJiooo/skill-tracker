On Error Resume Next

Set WshShell = CreateObject("WScript.Shell")
Set Fso = CreateObject("Scripting.FileSystemObject")
scriptDir = Fso.GetParentFolderName(WScript.ScriptFullName)

' Keep a one-click desktop entry for future launches.
desktopShortcut = WshShell.SpecialFolders("Desktop") & "\Skill Tracker Dashboard.lnk"
Set Shortcut = WshShell.CreateShortcut(desktopShortcut)
Shortcut.TargetPath = WshShell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\wscript.exe"
Shortcut.Arguments = """" & WScript.ScriptFullName & """"
Shortcut.WorkingDirectory = scriptDir
Shortcut.Description = "Open Skill Tracker Dashboard"
Shortcut.Save

' Start the stable local dashboard entry (0 = hidden window)
WshShell.Run "powershell -NoProfile -ExecutionPolicy Bypass -File """ & scriptDir & "\start-dashboard.ps1""", 0, false
