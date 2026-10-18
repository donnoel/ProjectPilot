---
layout: default
title: Project Pilot
---

<section class="hero" aria-labelledby="hero-title">
  <div class="hero__copy">
    <p class="eyebrow">Native macOS <span aria-hidden="true">·</span> Your menu-bar companion</p>
    <h1 id="hero-title">Your development day, in the menu bar.</h1>
    <p class="hero__lede">Track a Tick, check Codex usage and GitHub CI, keep development backups current, and see focused system health warnings—all from one compact Mac companion.</p>
    <div class="hero__actions"><a class="button button--primary" href="{{ site.github_url }}">View on GitHub <span aria-hidden="true">↗</span></a><a class="button button--quiet" href="#scaffold-flow">Explore the five tabs</a></div>
    <ul class="signal-list" aria-label="Project features"><li>Ticks</li><li>Codex usage</li><li>GitHub CI</li><li>Backups + health</li></ul>
  </div>
  <aside class="status-card" aria-labelledby="build-status-title">
    <div class="status-card__topline"><span class="status-pill"><span class="status-dot" aria-hidden="true"></span>{{ site.status_label }}</span><span class="status-card__meta">Five focused tabs</span></div>
    <div class="house-mark" aria-hidden="true"><span></span><span></span><span></span><span></span></div>
    <p class="status-card__kicker">Mac companion</p><h2 id="build-status-title">Time, code, and health.<br>One calm place.</h2>
    <dl class="status-list"><div><dt>Ticks</dt><dd>Start · Pause · Resume · Stop</dd></div><div><dt>GitHub</dt><dd>Local Git + CI</dd></div><div><dt>System health</dt><dd>Actionable warnings</dd></div></dl>
  </aside>
</section>

<section class="section" aria-labelledby="principles-title">
  <div class="section-heading"><p class="eyebrow">Keep everyday work visible</p><h2 id="principles-title">A quick check, then back to the work.</h2><p>Project Pilot brings time capture, development status, backups, and system health into a small menu-bar app. Your selected tab is remembered, with Ticks as the initial starting point.</p></div>
  <div class="principle-grid">
    <article class="principle-card"><span class="card-number">01</span><h3>Capture time</h3><p>Choose an existing Space and Start, Pause, Resume, or Stop a Tick. Manage Spaces, manual time, voice memos, and Auto Ticks in the mobile Ticks app.</p></article>
    <article class="principle-card"><span class="card-number">02</span><h3>See development status</h3><p>Check Codex usage limits and credits from local session data. Browse GitHub repositories with local Git sync and current-default-branch CI shown separately.</p></article>
    <article class="principle-card"><span class="card-number">03</span><h3>Keep recovery visible</h3><p>Check the development-folder mirror in iCloud Drive and back up when needed. A completed local copy is reported separately from Apple's cloud upload.</p></article>
  </div>
</section>

<section class="section section--split" id="scaffold-flow" aria-labelledby="preset-title">
  <article class="resident-card">
    <div class="resident-card__header"><div class="resident-icon" aria-hidden="true"><span></span><span></span><span></span></div><div><p class="eyebrow">Everyday controls</p><h2 id="preset-title">Five focused tabs</h2></div></div>
    <p class="resident-card__summary">Ticks, Codex, GitHub, Backup, and System Health each keep a clear job. Check what needs attention without turning a quick glance into another dashboard to manage.</p>
    <div class="boundary-note"><strong>The right detail, when you need it</strong><span>Ticks · Codex · GitHub · Backup · System Health</span></div>
    <ul class="capability-list"><li><span aria-hidden="true">✓</span> Ticks timer controls with shared CloudKit data</li><li><span aria-hidden="true">✓</span> Codex usage limits and credits</li><li><span aria-hidden="true">✓</span> Separate local Git sync and GitHub CI status</li><li><span aria-hidden="true">✓</span> Development backups and focused system warnings</li></ul>
  </article>
  <div class="run-flow" aria-labelledby="flow-title"><p class="eyebrow">A lighter daily routine</p><h2 id="flow-title">Keep the essentials close.</h2>
    <ol><li><span>01</span><div><strong>Choose a Space</strong><p>Select an existing Space in Ticks.</p></div></li><li><span>02</span><div><strong>Record your time</strong><p>Start, pause, resume, and stop from the Mac.</p></div></li><li><span>03</span><div><strong>Check Codex</strong><p>Review usage limits and credits.</p></div></li><li><span>04</span><div><strong>Review GitHub</strong><p>See local sync and default-branch CI.</p></div></li><li><span>05</span><div><strong>Check your backup</strong><p>Review or update the development mirror.</p></div></li><li><span>06</span><div><strong>See what needs attention</strong><p>Check disk, developer-storage, Docker, backup, and tool warnings.</p></div></li></ol>
  </div>
</section>

<section class="section foundation" aria-labelledby="foundation-title"><div><p class="eyebrow">Local first, clear about sync</p><h2 id="foundation-title">Useful status, without the guesswork.</h2></div><p>Project Pilot keeps an atomic local Ticks cache and retries pending iCloud changes. GitHub status distinguishes local repository sync from CI. Backup status confirms the local iCloud Drive copy, while System Health shows actionable warnings or a calm All clear state.</p></section>
