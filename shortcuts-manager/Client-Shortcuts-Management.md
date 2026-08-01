# Client Shortcuts Manager

## Purpose

When working across multiple client environments that use on-premise Windows
authentication, every application (SSMS, Visual Studio, VS Code, Power BI
Desktop, etc.) must be launched with a client-specific `DOMAIN\user` account.
Managing dozens of hand-crafted shortcuts becomes a maintenance problem:

- Duplicating the domain/user string in every shortcut.
- Updating paths manually after an application update (e.g. SSMS 21 → 22).
- No single source of truth for which client uses which applications.
- Passwords must be re-entered every time (if using `runas.exe` without `/savecred`).

This solution replaces individual shortcut files with **two JSON config files**
and **two PowerShell scripts** that manage credentials and regenerate all
shortcuts on demand.

---

## Repository structure

```
shortcuts-manager/
├── shortcuts-config.json        ← application registry and customer config
├── credentials-config.json      ← credential store (fill in passwords, then run Store-Credentials.ps1)
├── Store-Credentials.ps1        ← stores credentials in Windows Credential Manager
├── Generate-Shortcuts.ps1       ← generates shortcuts and per-shortcut launcher scripts
└── Client-Shortcuts-Management.md  ← this document
```

---

## Configuration files

### Credentials — `credentials-config.json`

Stores the mapping between credential names and `DOMAIN\user` accounts. Fill
in the `password` fields (initially set to `"CHANGEME"`) and save, then run
`Store-Credentials.ps1` to securely store them in Windows Credential Manager.

| Field             | Description |
|-------------------|-------------|
| `credentialName`  | Unique identifier, e.g. `"shortcuts/customer-a"`. Used by customer entries in `shortcuts-config.json`. |
| `domain`          | Windows domain. |
| `user`            | Windows username. |
| `password`        | Plaintext password (temporary; delete or set to `"CHANGEME"` after running `Store-Credentials.ps1`). |

#### Example

```jsonc
{
  "credentials": [
    {
      "credentialName": "shortcuts/customer-a",
      "domain": "DOMAINA",
      "user": "userA",
      "password": "CHANGEME"
    },
    {
      "credentialName": "shortcuts/customer-b",
      "domain": "DOMAINB",
      "user": "userB",
      "password": "CHANGEME"
    }
  ]
}
```

### Shortcuts — `shortcuts-config.json`

### Top-level sections

| Section        | Purpose |
|----------------|---------|
| `username`     | Local username for path expansion (e.g. `{username}` in app paths). Optional; defaults to `$env:USERNAME`. |
| `applications` | Global registry of every application that may be used. Paths are defined once here. |
| `customers`    | One entry per client. References application keys and supplies a credential name + optional arguments. |

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
| `credentialName`| ✔        | Reference to a credential name in `credentials-config.json`. |
| `applications`  | ✔        | Array of application entries (see below). |

Each item in `applications`:

| Field       | Required | Description |
|-------------|----------|-------------|
| `app`       | ✔        | Key from the global `applications` section. |
| `label`     |          | Custom shortcut name. Defaults to `"<App label> – <Customer name>"`. |
| `extraArgs` |          | Array of strings — each is one extra argument passed to the application (e.g. a solution file path). Quoting is handled by the script. |

#### Full example

```jsonc
{
  "username": "a.turelli",
  "applications": {
    "ssms": {
      "label": "SQL Server Management Studio",
      "path": "C:\\Program Files\\Microsoft SQL Server Management Studio 22\\Release\\Common7\\IDE\\SSMS.exe"
    },
    "vscode": {
      "label": "Visual Studio Code",
      "path": "C:\\Program Files\\Microsoft VS Code\\Code.exe"
    },
    "visualstudio": {
      "label": "Visual Studio 2022",
      "path": "C:\\Program Files\\Microsoft Visual Studio\\2022\\Community\\Common7\\IDE\\devenv.exe"
    },
    "powerbi": {
      "label": "Power BI Desktop",
      "path": "C:\\Users\\{username}\\AppData\\Local\\Microsoft\\WindowsApps\\PBIDesktopStore.exe"
    }
  },
  "customers": [
    {
      "name": "CustomerA",
      "shortcutsDir": "C:\\Shortcuts\\CustomerA",
      "credentialName": "shortcuts/customer-a",
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
    },
    {
      "name": "CustomerB",
      "shortcutsDir": "C:\\Shortcuts\\CustomerB",
      "credentialName": "shortcuts/customer-b",
      "applications": [
        {
          "app": "ssms",
          "label": "SSMS – CustomerB",
          "extraArgs": [ "C:\\Projects\\CustomerB\\CustomerB.ssmssln" ]
        },
        {
          "app": "visualstudio",
          "label": "Visual Studio – CustomerB"
        }
      ]
    }
  ]
}
```

---

## Credential storage — `Store-Credentials.ps1`

### How it works

Before generating shortcuts, credentials must be stored in Windows Credential
Manager. This script reads `credentials-config.json` and stores each entry as
a Generic credential using the built-in `cmdkey.exe` tool.

Credentials are encrypted by Windows (DPAPI) and tied to your local user
account. Once stored, they can be retrieved by the per-shortcut launcher
scripts without re-entering the password.

### Workflow

1. **Open `credentials-config.json`** and fill in all `password` fields with
   the actual customer passwords.
2. **Run `Store-Credentials.ps1`** to securely store them in Windows Credential
   Manager:
   ```powershell
   .\Store-Credentials.ps1
   ```
3. **Blank the passwords** in `credentials-config.json` (set them back to
   `"CHANGEME"` or delete the file entirely). Passwords should never be stored
   in plaintext on disk.

Credentials persist in Windows Credential Manager until explicitly deleted
(e.g. via `cmdkey /delete:target`).

### Parameters

| Parameter     | Default                       | Description |
|---|---|---|
| `-ConfigFile` | `credentials-config.json` (same folder as script) | Path to the credentials JSON file. |

### Usage

```powershell
# Store credentials
.\Store-Credentials.ps1

# Use a config file in a different location
.\Store-Credentials.ps1 -ConfigFile "D:\configs\my-credentials.json"
```

---

## Shortcut generator — `Generate-Shortcuts.ps1`

### How it works

For every customer/application pair the script:

1. Looks up the application path from the global `applications` registry.
2. Creates a per-shortcut PowerShell launcher script in the `_launchers/`
   subfolder inside the customer's `shortcutsDir`. This launcher:
   - Retrieves the credential from Windows Credential Manager (by `credentialName`).
   - Calls `Start-Process -FilePath <app> -Credential <cred>` to launch the
     application as the target user.
   - Displays errors in a Windows message box if credential retrieval fails.
3. Creates a `.lnk` shortcut file that calls
   `powershell.exe -NonInteractive -WindowStyle Hidden -File <launcher>`,
   so the launcher runs invisibly and the application appears to launch
   directly.

The generated shortcut avoids the `runas.exe` password prompt entirely — once
credentials are stored in Credential Manager, the app launches silently.

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

### Setting up a new customer (first time)

1. **Update `credentials-config.json`:**
   - Add a new entry with a unique `credentialName`, domain, user, and
     password.
2. **Run `Store-Credentials.ps1`** to store the credential in Windows
   Credential Manager.
3. **Update `shortcuts-config.json`:**
   - Add an entry to the `customers` array with the `credentialName` you
     created, plus the subset of `applications` they need.
4. **Run `Generate-Shortcuts.ps1`** to create the shortcuts and launcher
   scripts.
5. **Blank the passwords in `credentials-config.json`** (for security).

### Changing a customer's password

1. Update the `password` field in `credentials-config.json`.
2. Run `Store-Credentials.ps1` — it will overwrite the old credential.
3. Blank the password in the config file again.

### Updating an application path (e.g. SSMS upgrade)

1. Open `shortcuts-config.json`.
2. Update the `path` value under the relevant key in `applications`.
3. Run `Generate-Shortcuts.ps1`.

   All shortcuts referencing that application will automatically use the new
   path on the next run.

### Adding a new application globally

1. Add a new key to the `applications` section with its `label` and `path`.
2. Reference that key in any customer's `applications` list.
3. Run `Generate-Shortcuts.ps1`.

---

## Security considerations

### Credentials

- Credentials are **never stored in config files or shortcuts**. They live
  exclusively in Windows Credential Manager, encrypted by DPAPI.
- Each shortcut launcher retrieves credentials using P/Invoke to
  `CredReadW` (Windows advapi32) — no external dependencies.
- If credentials are compromised (e.g. `credentials-config.json` is shared
  unencrypted), immediately re-run `Store-Credentials.ps1` with new
  passwords; the Credential Manager entries are updated in-place.

### Config files

- `shortcuts-config.json` contains application paths and customer names (safe
  to share).
- `credentials-config.json` contains domain/user pairs and temporarily
  plaintext passwords. **Treat this file as sensitive**. Keep it:
  - Out of version control (add to `.gitignore`).
  - On disk only while storing credentials; blank passwords immediately.
  - Behind appropriate file permissions (Windows NTFS ACLs).

### Launchers and shortcuts

- Generated `.ps1` launchers and `.lnk` shortcuts are not sensitive — they
  contain only application paths and credential names (no passwords).
- The `_launchers/` folder can be deleted and regenerated on demand.
- Shortcuts can be shared across team members — each retrieves the credential
  from their own Credential Manager.

---

## Frequently asked questions

**Q: Can I put the shortcuts directly on the desktop or taskbar?**  
A: Set `shortcutsDir` to a path like `"C:\\Users\\USERNAME\\Desktop"`. Taskbar
pinning cannot be scripted reliably on modern Windows; pin manually after the
shortcut is created.

**Q: Can one customer entry share credentials with another?**  
A: Yes — just use the same `credentialName` in multiple customer entries. The
shortcut directory (`shortcutsDir`) keeps them organised by client
independently of credentials.

**Q: What if an application executable doesn't exist on the current machine?**  
A: The script prints a warning but still creates the shortcut. This is useful
when the config is shared across team members who may not have every
application installed.

**Q: Can I pass multiple extra arguments?**  
A: Yes. `extraArgs` is an array; add as many strings as needed. Each element
is automatically quoted if it contains spaces.

```jsonc
"extraArgs": [
  "C:\\Projects\\CustomerA\\CustomerA.ssmssln",
  "-nosplash"
]
```

**Q: How do I delete or change a stored credential?**  
A: Use `cmdkey /delete:` to remove a credential by its target name:
```powershell
cmdkey /delete:shortcuts/customer-a
```
Then fill in the new password in `credentials-config.json` and re-run
`Store-Credentials.ps1`.

**Q: What happens if the credential is not found in Credential Manager?**  
A: When a shortcut is clicked, a Windows error dialog appears saying the
credential was not found and instructing to run `Store-Credentials.ps1` first.
This ensures users know to set up credentials before launching apps.

**Q: Can I use `{username}` in application paths?**  
A: Yes — the top-level `username` field (or `$env:USERNAME` by default) is
expanded in all app paths. This is useful for user-profile-dependent paths
like Power BI Desktop or VS Code in AppData.
