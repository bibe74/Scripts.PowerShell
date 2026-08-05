# Client Shortcuts Manager

## Purpose

When working across multiple client environments that use on-premise Windows
authentication, every application (SSMS, Visual Studio, VS Code, Power BI
Desktop, etc.) must be launched via `runas.exe` with a client-specific
`DOMAIN\user` account. Managing dozens of hand-crafted shortcuts becomes a
maintenance problem:

- Duplicating the domain/user string in every shortcut.
- Updating paths manually after an application update (e.g. SSMS 21 → 22).
- No single source of truth for which client uses which applications.

This solution replaces individual shortcut files with **one JSON config file**
and **one PowerShell script** that regenerates all shortcuts on demand.

---

## Repository structure

```
shortcuts-manager/
├── shortcuts-config.json   ← single source of truth
├── Generate-Shortcuts.ps1  ← shortcut generator
└── Client-Shortcuts-Management.md  ← this document
```

---

## Configuration file — `shortcuts-config.json`

### Top-level sections

| Section        | Purpose |
|----------------|---------|
| `applications` | Global registry of every application that may be used. Paths are defined once here. |
| `customers`    | One entry per client. References application keys and supplies credentials + optional arguments. |

### `applications` section

Each key is a short identifier (e.g. `"ssms"`, `"vscode"`) used by customer
entries. Update the `"path"` here once when an application is installed to a
new location, and every downstream shortcut will reflect it on the next run.

```jsonc
"applications": {
  "ssms": {
    "label": "SQL Server Management Studio",   // used as default shortcut name
    "path":  "C:\\Program Files (x86)\\Microsoft SQL Server Management Studio 22\\Common7\\IDE\\Ssms.exe"
  },
  "vscode": {
    "label": "Visual Studio Code",
    "path":  "C:\\Users\\USERNAME\\AppData\\Local\\Programs\\Microsoft VS Code\\Code.exe"
  }
  // add more as needed
}
```

### `customers` section

Each entry in the array represents one client.

| Field           | Required | Description |
|-----------------|----------|-------------|
| `name`          | ✔        | Display name, used in log output. |
| `shortcutsDir`  | ✔        | Directory where the `.lnk` files will be created (created if absent). |
| `domain`        | *        | Windows domain. Used with `user` to build `DOMAIN\\user` when `runasUser` is not specified. |
| `user`          | *        | Windows username. Used with `domain` to build `DOMAIN\\user` when `runasUser` is not specified. |
| `runasUser`     |          | Optional explicit value for `runas /user:` (for example `DOMAIN\\user` or `user@domain.tld`). Use this when a specific tenant needs a custom identity format. |
| `applications`  | ✔        | Array of application entries (see below). |

`domain` + `user` are required unless `runasUser` is provided.

Each item in `applications`:

| Field       | Required | Description |
|-------------|----------|-------------|
| `app`       | ✔        | Key from the global `applications` section. |
| `label`     |          | Custom shortcut name. Defaults to `"<App label> – <Customer name>"`. |
| `extraArgs` |          | Array of strings — each is one extra argument passed to the application (e.g. a solution file path). Empty values are ignored; non-empty values are always quoted by the script. |

#### Full example

```jsonc
{
  "applications": {
    "ssms": {
      "label": "SQL Server Management Studio",
      "path": "C:\\Program Files (x86)\\Microsoft SQL Server Management Studio 22\\Common7\\IDE\\Ssms.exe"
    },
    "vscode": {
      "label": "Visual Studio Code",
      "path": "C:\\Users\\USERNAME\\AppData\\Local\\Programs\\Microsoft VS Code\\Code.exe"
    },
    "visualstudio": {
      "label": "Visual Studio 2022",
      "path": "C:\\Program Files\\Microsoft Visual Studio\\2022\\Professional\\Common7\\IDE\\devenv.exe"
    },
    "powerbi": {
      "label": "Power BI Desktop",
      "path": "C:\\Program Files\\Microsoft Power BI Desktop\\bin\\PBIDesktop.exe"
    }
  },
  "customers": [
    {
      "name": "CustomerA",
      "shortcutsDir": "C:\\Shortcuts\\CustomerA",
      "domain": "DOMAINA",
      "user": "userA",
      "applications": [
        {
          "app": "ssms",
          "label": "SSMS – CustomerA",
          "extraArgs": [ "C:\\Projects\\CustomerA\\CustomerA.ssmssln" ]
        },
        {
          "app": "vscode",
          "label": "VS Code – CustomerA"
        }
      ]
    }
  ]
}
```

---

## Generator script — `Generate-Shortcuts.ps1`

### How it works

For every customer/application pair the script:

1. Looks up the application path from the global `applications` registry.
2. Computes the `runas.exe` argument string, handling path quoting
   automatically.
3. Creates a `.lnk` file via the `WScript.Shell` COM object, setting the icon
   to the target executable so the shortcut looks like the native app.

When `runasUser` is not set, the generated shortcut is equivalent to writing,
in the shortcut's *Target* field:

```
C:\Windows\System32\runas.exe /netonly /user:DOMAINA\userA "C:\...\Ssms.exe \"C:\Projects\CustomerA\CustomerA.ssmssln\""
```

The script uses `/netonly` and passes one double-quoted command block to
`runas.exe`. The executable path is first, and each extra argument is emitted
as `\"...\"` inside that command block.

If `runasUser` is set on a customer, that exact value is used for `/user:`.

### Parameters

| Parameter     | Default                         | Description |
|---------------|---------------------------------|-------------|
| `-ConfigFile` | `shortcuts-config.json` (same folder as script) | Path to the JSON config. |
| `-DryRun`     | *(switch, off)*                 | Print what would happen without writing any files. |

### Usage

```powershell
# Preview what will be created
.\Generate-Shortcuts.ps1 -DryRun

# Generate all shortcuts
.\Generate-Shortcuts.ps1

# Use a config file in a different location
.\Generate-Shortcuts.ps1 -ConfigFile "D:\configs\my-shortcuts.json"
```

> **Execution policy**: if your machine restricts unsigned scripts, run once
> from an elevated PowerShell prompt with
> `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` before calling
> the script, or sign the script with a code-signing certificate.

---

## Typical workflows

### Adding a new client

1. Open `shortcuts-config.json`.
2. Add an entry to the `customers` array with the client's `domain`, `user`,
   `shortcutsDir`, and the subset of `applications` they need.
3. Run `.\Generate-Shortcuts.ps1`.

### Updating an application path (e.g. SSMS upgrade)

1. Open `shortcuts-config.json`.
2. Update the `path` value under the relevant key in `applications`.
3. Run `.\Generate-Shortcuts.ps1`.

All client shortcuts that reference that application are regenerated with the
new path automatically.

### Adding a new application globally

1. Add a new key to the `applications` section with its `label` and `path`.
2. Reference that key in any customer's `applications` list.
3. Run `.\Generate-Shortcuts.ps1`.

---

## Security considerations

- Credentials are **never stored** in the config file or the script. The
  shortcuts launch `runas.exe`, which prompts for the password interactively
  (Windows secure dialog) every time the shortcut is used — exactly the same
  behaviour as hand-crafted `runas` shortcuts.
- Keep `shortcuts-config.json` under version control or in a location with
  appropriate access controls, since it contains usernames and domain names.
- If you use `/savecred` with `runas`, the saved credential lives in Windows
  Credential Manager and is not controlled by this tooling.

---

## Frequently asked questions

**Q: Can I put the shortcuts directly on the desktop or taskbar?**  
A: Set `shortcutsDir` to `%USERPROFILE%\Desktop` (expand the variable first in
the JSON: `"C:\\Users\\USERNAME\\Desktop"`). Taskbar pinning cannot be scripted
reliably on modern Windows; pin manually after the shortcut is created.

**Q: Can one customer entry share credentials with another?**  
A: Yes — just use the same `domain`/`user` values. The shortcut directory
(`shortcutsDir`) keeps them organised by client independently of credentials.
If needed, both customers can also reuse the same explicit `runasUser` value.

**Q: What if an application executable doesn't exist on the current machine?**  
A: The script prints a warning but still creates the shortcut. This is useful
when the config is shared across team members who may not have every
application installed.

**Q: Can I pass multiple extra arguments?**  
A: Yes. `extraArgs` is an array; add as many strings as needed. Non-empty
elements are always quoted, and empty/whitespace entries are ignored.

```jsonc
"extraArgs": [
  "C:\\Projects\\CustomerA\\CustomerA.ssmssln",
  "-nosplash"
]
```
