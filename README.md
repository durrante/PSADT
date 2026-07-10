# 📦 PSADT Package Library

A personal collection of Windows application deployment packages built on [PSAppDeployToolkit (PSADT)](https://psappdeploytoolkit.com), designed for deployment via **Microsoft Intune** as Win32 apps.

> **As-is, no warranty.** These packages are provided without any guarantee of fitness for purpose. Test thoroughly in your own environment before deploying to production.

---

## Structure

```
.
├── v3/    # Deprecated - PSADT v3 packages (no longer maintained)
└── v4/    # Active - PSADT v4 packages
    └── OLD/   # Archived v4 packages, superseded or no longer used
```

---

## V4 Packages

All packages in `v4/` are built on **PSAppDeployToolkit 4.1.x** and target deployment via **Microsoft Intune** as Win32 apps.

### Package structure

Every V4 package follows a consistent structure designed to work seamlessly with Win32Forge (see [Uploading to Intune](#-uploading-to-intune)):

| File | Purpose |
|---|---|
| `Invoke-AppDeployToolkit.ps1` | The main PSADT deployment script (install, uninstall, repair logic) |
| `detection.ps1` | Intune detection script - determines whether the app is already installed |
| `metadata.txt` | App description, information URL, privacy URL, and Intune category |
| `Logo.png` | App icon displayed in the Company Portal |
| `requirement_*.ps1` | Optional - requirement scripts (e.g. checks that Office is installed before proceeding) |
| `Files\` | Installer payload or supporting files |
| `PSAppDeployToolkit\` | PSADT runtime module (obtained from the [PSADT releases page](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/releases)) |

When you point **Win32Forge** at a package folder, it automatically picks up `detection.ps1`, `Logo.png`, and `metadata.txt` and pre-fills the Intune upload form - including the app description, URLs, and category. See [Win32Forge](https://github.com/durrante/Win32Forge) for full details.

### Deployment methods

The folder name suffix indicates how the installer is sourced:

#### 🌿 `_Evergreen_`

Packages with `_Evergreen_` in the name use the **[Evergreen PowerShell module](https://github.com/EUCPilots/evergreen-module)** to resolve and download the latest version of an application at install time - no static installer to maintain or update.

Big thanks to **Aaron Parker** for creating and maintaining Evergreen. It takes the pain out of keeping application versions current.

#### 📦 `_WinGet_`

Packages with `_WinGet_` in the name use the **[PSAppDeployToolkit.WinGet extension](https://github.com/mjr4077au/PSAppDeployToolkit.WinGet)** by **mjr4077au** to install, update, and remove applications via the Windows Package Manager from within a PSADT deployment context. The extension handles WinGet availability and repair, making it reliable under the SYSTEM account during Intune deployments.

#### `_URLFallback_`

Packages with `_URLFallback_` attempt to download the latest installer from a known vendor URL at runtime. If that download fails for any reason (network issue, URL change, etc.), the script falls back to a locally cached copy bundled in the `Files\` folder, which may be an older version. This gives you the best of both worlds - always try for the latest, but never leave a device without an installer to use.

#### No suffix (Manual)

Packages with no method suffix bundle the installer directly in the `Files\` folder. These are version-pinned and rebuilt when a new release is needed.

---

## V3 Packages (Deprecated) ⚠️

Packages in `v3/` were built on **PSAppDeployToolkit v3**, which is no longer under active development by the PSADT project and is no longer maintained here. They are kept for reference only. Use the V4 equivalents where available.

---

## 🚀 Uploading to Intune

These packages are designed to work with **[Win32Forge](https://github.com/durrante/Win32Forge)** - a free, open-source PowerShell 7 GUI tool for packaging, uploading, and documenting Win32 apps in Microsoft Intune.

Win32Forge has deep PSADT v4 support and automatically reads each package's `detection.ps1`, `Logo.png`, and `metadata.txt` to pre-fill the upload form. It also extracts app metadata (name, version, publisher) directly from `Invoke-AppDeployToolkit.ps1`. The bulk upload manager lets you import an entire folder of packages in one click and upload them as a queue.

See the [Win32Forge README](https://github.com/durrante/Win32Forge) for full details on setup and usage.
