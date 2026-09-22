#requires -Version 5.1

[CmdletBinding()]
param(
	[string]$Config = "$PSScriptRoot\workstation.json",
	[string]$Profile = "Full",
	[string[]]$Group,
	[string[]]$Program,
	[switch]$List,
	[switch]$Plan,
	[switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

function Names($o) {
	@($o.PSObject.Properties.Name)
}

function Admin() {
	$p = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
	$p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function P($n) {
	$x = $script:C.Programs.PSObject.Properties[$n]
	if (!$x) {
		throw "Programma sconosciuto: $n"
	}

	$x.Value
}

function Run($text, [scriptblock]$a) {
	Write-Host "    $text" -ForegroundColor DarkGray
	if (!$Plan -and !$WhatIf) {
		&$a
	}
}

function Install($n) {
	if ($script:D[$n]) {
		return
	}

	if ($script:V[$n]) {
		throw "Dipendenza circolare: $n"
	}

	$script:V[$n] = $true
	$p = P $n

	foreach ($d in @($p.Requires)) {
		if ($d) {
			Install $d
		}
	}

	Write-Host "==> $n [$($p.Provider)]" -ForegroundColor Cyan

	try {
		switch ($p.Provider) {
			'Winget' {
				if (!(Get-Command winget -EA SilentlyContinue)) {
					throw 'winget non disponibile'
				}

				$a = @(
					'install',
					'--id',
					$p.Id,
					'--exact',
					'--source',
					'winget',
					'--accept-package-agreements',
					'--accept-source-agreements'
				)

				if ($p.Version) {
					$a += @('--version', $p.Version)
				}

				if ($p.Override) {
					$a += @('--override', $p.Override)
				}

				Run "winget $($a -join ' ')" {
					& winget @a
					if ($LASTEXITCODE) {
						throw "winget exit $LASTEXITCODE"
					}
				}
			}

			'VSCodeExtension' {
				if (!(Get-Command code -EA SilentlyContinue)) {
					throw 'code non disponibile'
				}

				Run "code --install-extension $($p.Id) --force" {
					& code --install-extension $p.Id --force
					if ($LASTEXITCODE) {
						throw "code exit $LASTEXITCODE"
					}
				}
			}

			'VisualStudio' {
				if (!(Admin)) {
					throw 'Visual Studio richiede PowerShell elevato'
				}

				if (!(Get-Command winget -EA SilentlyContinue)) {
					throw 'winget non disponibile'
				}

				$ov = @('--passive', '--norestart')
				foreach ($x in @($p.Add)) {
					if ($x) {
						$ov += @('--add', $x)
					}
				}

				if ($p.IncludeRecommended) {
					$ov += '--includeRecommended'
				}

				$over = $ov -join ' '
				Run "winget install --id $($p.Id) --exact --override `"$over`"" {
					& winget install --id $p.Id --exact --source winget --accept-package-agreements --accept-source-agreements --override $over
					if ($LASTEXITCODE) {
						throw "Visual Studio exit $LASTEXITCODE"
					}
				}
			}

			'VSIX' {
				if (!(Test-Path $p.Path)) {
					throw "VSIX non trovato: $($p.Path)"
				}

				$vsix = (Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\resources\app\ServiceHub\Services\Microsoft.VisualStudio.Setup.Service" -Filter VSIXInstaller.exe -Recurse -EA SilentlyContinue | Select -First 1).FullName
				if (!$vsix) {
					$vsix = (Get-ChildItem "${env:ProgramFiles}\Microsoft Visual Studio" -Filter VSIXInstaller.exe -Recurse -EA SilentlyContinue | Select -First 1).FullName
				}

				if (!$vsix) {
					throw 'VSIXInstaller.exe non trovato'
				}

				$a = @()
				if ($p.Admin) {
					$a += '/admin'
				}

				$a += $p.Path
				Run "$vsix $($a -join ' ')" {
					&$vsix @a
					if ($LASTEXITCODE) {
						throw "VSIX exit $LASTEXITCODE"
					}
				}
			}

			'PowerShell' {
				if ($p.Admin -and !(Admin)) {
					throw 'Richiesti privilegi amministrativi'
				}

				$cmd = $p.Command
				Run $cmd {
					Invoke-Expression $cmd
				}
			}

			'PSModule' {
				$scope = if ($p.Admin) { 'AllUsers' } else { 'CurrentUser' }
				if ($p.Admin -and !(Admin)) {
					throw 'Richiesti privilegi amministrativi'
				}

				Run "Install-Module -Name $($p.Id) -Scope $scope -Force -AllowClobber" {
					Install-Module -Name $p.Id -Scope $scope -Force -AllowClobber -ErrorAction Stop
				}
			}

			'Manual' {
				Write-Host "    MANUALE: $($p.Description)" -ForegroundColor Yellow
			}

			default {
				throw "Provider sconosciuto: $($p.Provider)"
			}
		}

		$script:D[$n] = $true
	}
	catch {
		if ($p.Optional) {
			Write-Warning "$n : $($_.Exception.Message)"
			$script:D[$n] = $true
		}
		else {
			throw
		}
	}
	finally {
		$script:V.Remove($n)
	}
}

if (!(Test-Path $Config)) {
	throw "Config non trovata: $Config"
}

$script:C = Get-Content $Config -Raw | ConvertFrom-Json
$gn = Names $C.Groups
$pn = Names $C.Profiles

if ($List) {
	Write-Host 'Programmi:' -ForegroundColor Yellow
	Names $C.Programs | ForEach-Object {
		Write-Host "  $_ [$((P $_).Provider)]"
	}

	Write-Host "`nGruppi:" -ForegroundColor Yellow
	$gn | ForEach-Object {
		Write-Host "  $_ -> $(@($C.Groups.$_) -join ', ')"
	}

	Write-Host "`nProfili:" -ForegroundColor Yellow
	$pn | ForEach-Object {
		Write-Host "  $_ -> $(@($C.Profiles.$_) -join ', ')"
	}

	exit
}

$t = @()
if ($Program) {
	$t += $Program
}

if ($Group) {
	foreach ($g in $Group) {
		if ($gn -notcontains $g) {
			throw "Gruppo sconosciuto: $g"
		}

		$t += @($C.Groups.$g)
	}
}

if (!$Program -and !$Group) {
	if ($pn -notcontains $Profile) {
		throw "Profilo sconosciuto: $Profile"
	}

	foreach ($g in @($C.Profiles.$Profile)) {
		$t += @($C.Groups.$g)
	}
}

$script:D = @{}
$script:V = @{}
foreach ($n in @($t | Select -Unique)) {
	Install $n
}

Write-Host 'Completato.' -ForegroundColor Green
