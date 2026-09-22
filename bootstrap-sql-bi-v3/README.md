# Bootstrap dichiarativo v3

Provider: Winget, VisualStudio, VSCodeExtension, VSIX, PowerShell, Manual.

Esempi:
```powershell
.\Bootstrap-Workstation.ps1 -List
.\Bootstrap-Workstation.ps1 -Profile Full -Plan
.\Bootstrap-Workstation.ps1 -Profile Full
```

## VSIX locali
Metti BimlExpress in `packages\BimlExpress.vsix`. Il bootstrap non scarica automaticamente VSIX: origine e versione rimangono sotto il tuo controllo.

## Visual Studio
Il provider `VisualStudio` trasforma `Add` in parametri `--add` del bootstrapper Visual Studio inoltrati da winget. `IncludeRecommended` aggiunge `--includeRecommended`.

SSAS/SSIS/SSRS restano dichiarazioni `Manual` perché sono estensioni separate e la configurazione deve fissare la release compatibile desiderata.
