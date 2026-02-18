# 🧭 **ProjectPilot**
### *A liquid-glass menu bar launcher that generates “known-good” Xcode projects in one click.*

<p align="center">
  <img src="https://img.shields.io/badge/SwiftUI-MenuBarExtra-orange?logo=swift">
  <img src="https://img.shields.io/badge/Platform-macOS-blue">
  <img src="https://img.shields.io/badge/Project%20Gen-Template%20Xcodeproj-purple">
  <img src="https://img.shields.io/badge/GitHub-gh%20CLI-green?logo=github">
</p>

---

## ✨ What is ProjectPilot?

**ProjectPilot** is a macOS menu bar utility that creates new Xcode projects using a **golden template `.xcodeproj`** as the source of truth.

Instead of generating “close enough” settings, ProjectPilot produces a project that **matches your known-good Xcode configuration**, changing only the project name (and platform selection), so you get consistent build settings, structure, and behavior every time.

It can also:
- initialize a git repo,
- create a GitHub repo via `gh`,
- push the initial commit,
- and open the project in Xcode.

---

## 💎 Core Features

| Feature | Description |
|--------|-------------|
| 🧱 **Template-Accurate Xcode Projects** | Generates projects by transforming a golden `.xcodeproj` template so settings match exactly. |
| 🧩 **Platform Selection** | Create a project for **iOS**, **macOS**, **tvOS**, or any combination supported by the template. |
| 🪄 **One-Click Bootstrap** | Creates folders + starter SwiftUI app + tests + assets with a clean, consistent layout. |
| 🧼 **Clean Git Start** | Initializes git, writes a sensible `.gitignore`, and commits “Initial commit.” |
| ☁️ **GitHub Repo Creation** | Creates a repo using `gh` and pushes automatically. |
| 🔒 **Public/Private Toggle** | Choose whether the GitHub repo is created as public or private. |
| 🧊 **Liquid Glass UI** | Compact, premium-looking popover with macOS visual effect styling. |
| 🔁 **Runs at Login** | Registers as a Login Item so it starts automatically after you log in. |

---

## 🎛 Controls

- **Project Name**: Enter the folder/project name to create.
- **Platforms**: Tap the platform “pills” to select iOS/macOS/tvOS.
- **GitHub**
  - Toggle **Public repo** on/off.
- **Post-Create**
  - Optionally open in Xcode, reveal in Finder, and open Safari to the GitHub project.
- **Create**: Generates the project, bootstraps git, creates/pushes GitHub repo (if enabled), then opens in Xcode.
- **Quit**: Terminates ProjectPilot.

---

## 🧠 How it works

ProjectPilot follows a predictable pipeline:

1. **Create folder** for the new project
2. **Write starter source files** (SwiftUI entry, basic content, tests, assets)
3. **Generate `.xcodeproj`** by:
   - reading the golden template `project.pbxproj`
   - replacing template identifiers with your project name
   - updating supported platforms based on selection
4. **Initialize git**, write `.gitignore`, commit
5. **Create GitHub repo** with `gh repo create` (public/private)
6. **Set origin + push**
7. **Open in Xcode**

---

## 🧱 Architecture Overview

### **ProjectPilotViewModel (@MainActor)**
The orchestration brain:
- Validates inputs and selection rules
- Runs the creation pipeline in sequence
- Surfaces status and failure messages to the UI

### **Process Runner**
A small wrapper around `Process` used to run:
- `git`
- `gh`
- any other CLI operations required for the pipeline

### **Template Project Writer**
- Loads the golden pbxproj text
- Applies safe name substitutions + platform adjustments
- Writes the resulting `.xcodeproj` to disk

### **UI (SwiftUI MenuBarExtra)**
- Compact popover UI
- Liquid-glass material background with layered card highlights
- Premium button/pill styling

---

## 📁 Project Structure

```text
ProjectPilot/
├── ProjectPilotApp/
│   ├── App/
│   │   ├── ProjectPilotApp.swift
│   │   ├── ProjectPilotPopover.swift
│   │   └── ProjectPilotViewModel.swift
│   └── Resources/
│       └── Assets.xcassets/
├── ProjectPilotTests/
└── ProjectPilotUITests/
```

---

## 🚀 Getting Started

### Requirements
- macOS
- Xcode
- Git
- GitHub CLI (`gh`) if you want automatic repo creation

### Setup
1. Open `ProjectPilot.xcodeproj` in Xcode
2. Build & run the **ProjectPilot** scheme
3. (Optional) Authenticate GitHub CLI:
   - `gh auth login`
4. Click the menu bar icon
5. Enter a project name, choose platforms, choose GitHub visibility
6. Click **Create**

---

## 🧭 Notes & Conventions

- **Repo names** are sanitized for GitHub (spaces are converted into a safe format).
- If `gh` is missing or not authenticated, ProjectPilot will fail that step with a readable status message.
- The generated project is designed to mirror your template’s settings, so the template is the “contract.”

---

## 🗺️ Roadmap

- [ ] Optional toggle: “Create GitHub repo” (local-only mode)
- [ ] Reveal-in-Finder button after creation
- [ ] Inline log view for CLI output (git/gh) when something fails
- [ ] Multiple templates (e.g., iOS-only, macOS-only, tvOS-only) with a template picker
- [ ] Optional project location picker (instead of a fixed root folder)

---

## ❤️ Credits

Built with care by **Don Noel** and AI collaboration.

---

> *ProjectPilot is designed to make starting a new Xcode project feel instant, consistent, and calm.*
