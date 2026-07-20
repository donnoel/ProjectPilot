---
layout: default
title: Project Pilot
---

<section class="hero" aria-labelledby="hero-title">
  <div class="hero__copy">
    <p class="eyebrow">Native macOS <span aria-hidden="true">·</span> Xcode scaffolding</p>
    <h1 id="hero-title">Known-good Xcode projects, on demand.</h1>
    <p class="hero__lede">Project Pilot turns a trusted template into a complete iOS, macOS, or tvOS project—with source, tests, CI, git, and optional GitHub setup in one predictable run.</p>
    <div class="hero__actions"><a class="button button--primary" href="{{ site.github_url }}">View on GitHub <span aria-hidden="true">↗</span></a><a class="button button--quiet" href="#scaffold-flow">See the scaffold pipeline</a></div>
    <ul class="signal-list" aria-label="Project foundation"><li>SwiftUI</li><li>MenuBarExtra</li><li>Xcode templates</li><li>GitHub CLI</li></ul>
  </div>
  <aside class="status-card" aria-labelledby="build-status-title">
    <div class="status-card__topline"><span class="status-pill"><span class="status-dot" aria-hidden="true"></span>{{ site.status_label }}</span><span class="status-card__meta">One clean start</span></div>
    <div class="house-mark" aria-hidden="true"><span></span><span></span><span></span><span></span></div>
    <p class="status-card__kicker">Current pipeline</p><h2 id="build-status-title">Choose the intent.<br>Generate the foundation.</h2>
    <dl class="status-list"><div><dt>iOS + macOS + tvOS</dt><dd>Supported</dd></div><div><dt>Local git bootstrap</dt><dd>Included</dd></div><div><dt>GitHub creation</dt><dd>Optional</dd></div></dl>
  </aside>
</section>

<section class="section" aria-labelledby="principles-title">
  <div class="section-heading"><p class="eyebrow">Consistency at creation time</p><h2 id="principles-title">The first commit should already feel intentional.</h2><p>Project Pilot replaces repeated setup decisions with a golden template, explicit platform choices, and a visible pipeline that can explain every success or failure.</p></div>
  <div class="principle-grid">
    <article class="principle-card"><span class="card-number">01</span><h3>Template-accurate</h3><p>Generate from a known-good pbxproj and starter structure instead of approximating build settings after the fact.</p></article>
    <article class="principle-card"><span class="card-number">02</span><h3>Platform-aware</h3><p>Choose iOS, macOS, tvOS, or a supported combination and carry that intent into project settings and CI destinations.</p></article>
    <article class="principle-card"><span class="card-number">03</span><h3>Recoverable</h3><p>See Folder, Xcodeproj, Git, GitHub, and Open progress separately, then retry a failed GitHub step without rebuilding everything.</p></article>
  </div>
</section>

<section class="section section--split" id="scaffold-flow" aria-labelledby="preset-title">
  <article class="resident-card">
    <div class="resident-card__header"><div class="resident-icon" aria-hidden="true"><span></span><span></span><span></span></div><div><p class="eyebrow">One project preset</p><h2 id="preset-title">Defaults worth reusing</h2></div></div>
    <p class="resident-card__summary">Built-in and custom presets remember platform, template profile, and GitHub visibility so a familiar kind of project starts with familiar decisions.</p>
    <div class="boundary-note"><strong>Basic when simple is enough</strong><span>Basic · Advanced · Codex balance</span></div>
    <ul class="capability-list"><li><span aria-hidden="true">✓</span> User-selected project location</li><li><span aria-hidden="true">✓</span> Starter SwiftUI source, tests, assets, and CI</li><li><span aria-hidden="true">✓</span> Public or private GitHub repository</li><li><span aria-hidden="true">✓</span> Open in Xcode, Codex, CLI, Finder, or Safari</li></ul>
  </article>
  <div class="run-flow" aria-labelledby="flow-title"><p class="eyebrow">The scaffold pipeline</p><h2 id="flow-title">From a name to a working repository.</h2>
    <ol><li><span>01</span><div><strong>Validate</strong><p>Check the project name and choices.</p></div></li><li><span>02</span><div><strong>Create folder</strong><p>Write the selected local structure.</p></div></li><li><span>03</span><div><strong>Generate Xcodeproj</strong><p>Apply the golden template safely.</p></div></li><li><span>04</span><div><strong>Initialize git</strong><p>Create main and the first commit.</p></div></li><li><span>05</span><div><strong>Create GitHub</strong><p>Optionally create and push the repository.</p></div></li><li><span>06</span><div><strong>Open the work</strong><p>Launch the tool you want next.</p></div></li></ol>
  </div>
</section>

<section class="section foundation" aria-labelledby="foundation-title"><div><p class="eyebrow">Local first, predictable always</p><h2 id="foundation-title">Automation should remove repetition, not understanding.</h2></div><p>Project Pilot runs as a compact Mac menu-bar app, writes projects to the folder you choose, keeps local-only scaffolds completely local, and surfaces captured command details when git or GitHub needs attention.</p></section>
