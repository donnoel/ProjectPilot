# 🧭 **Project Pilot**
### *A liquid-glass menu bar launcher that generates “known-good” Xcode projects in one click.*

<p align="center">
  <img src="https://img.shields.io/badge/SwiftUI-MenuBarExtra-orange?logo=swift">
  <img src="https://img.shields.io/badge/Platform-macOS-blue">
  <img src="https://img.shields.io/badge/Project%20Gen-Template%20Xcodeproj-purple">
  <img src="https://img.shields.io/badge/GitHub-gh%20CLI-green?logo=github">
</p>

---

## ✨ What is Project Pilot?

**Project Pilot** is a macOS menu bar utility that creates new Xcode projects using a **golden template `.xcodeproj`** as the source of truth.

Instead of generating “close enough” settings, Project Pilot produces a project that **matches your known-good Xcode configuration**, changing only the project name (and platform selection), so you get consistent build settings, structure, and behavior every time.

It can also:
- initialize a git repo,
- create a GitHub repo via `gh`,
- push the initial commit to remote branch `main`,
- and open the project in Xcode.

---

## 💎 Core Features

| Feature | Description |
|--------|-------------|
| 🧱 **Template-Accurate Xcode Projects** | Generates projects by transforming a golden `.xcodeproj` template so settings match exactly. |
| 🧩 **Platform Selection** | Create a project for **iOS**, **macOS**, **tvOS**, or any combination supported by the template. |
| 🪄 **One-Click Bootstrap** | Creates folders + starter SwiftUI app + tests + assets with a clean, consistent layout. |
| ✅ **Starter CI Workflow** | Generates `.github/workflows/ci.yml` per project with project-specific scheme/path and destination-aware test execution. |
| 🧼 **Clean Git Start** | Initializes git, writes a sensible `.gitignore` (including `xcuserdata/`), and commits “Initial commit.” |
| ☁️ **GitHub Repo Creation** | Creates a repo using `gh` and pushes automatically. |
| 🔒 **Public/Private Toggle** | Choose whether the GitHub repo is created as public or private. |
| 📊 **Codex Quota Tab** | Shows live Codex 5-hour + weekly usage limits and credits from local Codex session data. |
| 🧊 **Liquid Glass UI** | Compact, premium-looking popover with macOS visual effect styling. |
| 🔁 **Runs at Login** | Registers as a Login Item so it starts automatically after you log in. |

---

## 🎛 Controls

- **Project Name**: Enter the folder/project name to create.
- **Platforms**: Tap the platform “pills” to select iOS/macOS/tvOS.
- **Mode Tabs**: Switch between **Basic**, **Advanced**, and **Codex** views.
- **GitHub**
  - Toggle **Public repo** on/off.
  - GitHub tab repository list shows each repo's created and updated timestamps.
- **Post-Create**
  - Optionally open in Xcode, open in Codex, open CLI in the project folder, reveal in Finder, and open Safari to the GitHub project.
- **Codex Tab**
  - Shows near-real-time quota status (5-hour usage, weekly usage, credits) from `~/.codex/sessions` rollout logs.
- **Create**: Generates the project, bootstraps git, creates/pushes GitHub repo (if enabled), then opens in Xcode.
- **Quit**: Terminates Project Pilot.

---

## 🧠 How it works

Project Pilot follows a predictable pipeline:

1. **Create folder** for the new project
2. **Write starter source files** (SwiftUI entry, basic content, tests, assets)
3. **Generate starter project metadata** (README, AGENTS files, and `.github/workflows/ci.yml`)
4. **Generate `.xcodeproj`** by:
   - reading the golden template `project.pbxproj`
   - replacing template identifiers with your project name
   - updating supported platforms based on selection
5. **Initialize git**, write `.gitignore` (including `xcuserdata/`), commit
6. **Create GitHub repo** with `gh repo create` (public/private)
7. **Push to remote branch `main`** and set GitHub default branch to `main`
8. **Open in Xcode**

---

## 🧱 Architecture Overview

### **Project PilotViewModel (@MainActor)**
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
Project Pilot/
├── Project PilotApp/
│   ├── App/
│   │   ├── Project PilotApp.swift
│   │   ├── Project PilotPopover.swift
│   │   └── Project PilotViewModel.swift
│   └── Resources/
│       └── Assets.xcassets/
├── Project PilotTests/
└── Project PilotUITests/
```

---

## 🚀 Getting Started

### Requirements
- macOS
- Xcode
- Git
- GitHub CLI (`gh`) if you want automatic repo creation

### Setup
1. Open `Project Pilot.xcodeproj` in Xcode
2. Build & run the **Project Pilot** scheme
3. (Optional) Authenticate GitHub CLI:
   - `gh auth login`
4. Click the menu bar icon
5. Enter a project name, choose platforms, choose GitHub visibility
6. Click **Create**

---

## 🧭 Notes & Conventions

- **Repo names** are sanitized for GitHub (spaces are converted into a safe format).
- If `gh` is missing or not authenticated, Project Pilot will fail that step with a readable status message.
- GitHub remotes are normalized to `https://github.com/...` and use `gh auth` credentials for git network operations.
- The generated project is designed to mirror your template’s settings, so the template is the “contract.”

---

## ❤️ Credits

Built with care by **Don Noel** and AI collaboration.

---

> *Project Pilot is designed to make starting a new Xcode project feel instant, consistent, and calm.*
