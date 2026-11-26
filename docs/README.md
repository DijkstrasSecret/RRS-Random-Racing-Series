# RRS documentation

This is the index for everything in `docs/` and the rulebook for writing it. It applies to people and AI agents alike. A short version is in `CLAUDE.md`; this file has the detail.

## Index

| Folder | What goes here | Files |
|--------|----------------|-------|
| `design/` | **What the game is:** pillars, modes, cars, tracks, rules, tuning targets. Written for players and designers. | [RRS_Design_Concept.md](design/RRS_Design_Concept.md) (+ PDF), [tournament_upgrades.md](design/tournament_upgrades.md), RRS_car_lineup.pdf |
| `architecture/` | **How the code works:** systems, data flow, ownership, networking model. Written for developers. | [directory_tree.md](architecture/directory_tree.md) |
| `decisions/` | **Why it works that way:** numbered decision records (ADRs). Never deleted. | [0000-template.md](decisions/0000-template.md), [0001-record-architecture-decisions.md](decisions/0001-record-architecture-decisions.md), [0002-online-multiplayer-network-model.md](decisions/0002-online-multiplayer-network-model.md) |
| `research/` | **What we found out:** investigations, real-world data, engine experiments, comparisons. They can be out of date. | [damage_research.md](research/damage_research.md) |
| `reviews/` | **Audits of the code at a point in time,** with numbered findings that get ticked off. | [multiplayer_must_fix.md](reviews/multiplayer_must_fix.md), [multiplayer_nice_to_have.md](reviews/multiplayer_nice_to_have.md) |
| `plans/` | **How a piece of work will be built:** step-by-step implementation plans for one issue, written before the code. `Snapshot`. | [2026-11-26-webrtc-prototype.md](plans/2026-11-26-webrtc-prototype.md) |

**Which folder?** A doc that says "the game should…" goes in `design/`. One that says "the code does…" goes in `architecture/`. "We chose X over Y because…" is a decision record. "We measured / compared…" goes in `research/`. "Here is what's wrong with the code right now" goes in `reviews/`. "Here is how we'll build issue #N, step by step" goes in `plans/`.

## When docs must change

A change isn't done until the docs match it, **in the same PR**.

| You changed… | Update… |
|--------------|---------|
| Gameplay, rules, handling feel, car or track content | The matching section of `design/RRS_Design_Concept.md` (and rebuild the PDF), or the topic doc such as `tournament_upgrades.md`. |
| How a system works, who owns state, data flow, scene structure | The relevant `architecture/` doc, or create one if none covers the system. |
| A choice between real alternatives: a new system, a library or engine feature, a reversal of an earlier choice, **any netcode or multiplayer choice** | A new ADR in `decisions/`. |
| Something that fixes a review finding | Mark it in the review doc: `✅ Fixed in #<PR>` after the finding's heading, plus one line saying how. |
| Folders, top-level layout, new asset types | `architecture/directory_tree.md`. |
| Commands, conventions, or anything an agent needs every session | `CLAUDE.md`. |

If a change makes a doc wrong and you can't fix it in this PR, add a `> ⚠️ Out of date: <what> (since #<PR>)` line at the top of that doc. Never leave a doc silently wrong.

## File rules

- **Names:**
  - `lower_snake_case.md`.
  - ADRs are `NNNN-kebab-case-title.md`, numbered in order.
  - Existing files with other names (`RRS_Design_Concept.md`, `RRS_car_lineup.pdf`) keep their names, because tools and links point at them.
- **Format:** Markdown only. PDFs are generated, never edited by hand:
  - The design doc PDF comes from `python tools/md_to_pdf.py docs/design/RRS_Design_Concept.md`.
  - The car lineup PDF comes from `tools/make_lineup_pdf.py`.
  - Commit each regenerated PDF together with its source.
- **Header:** every doc starts with an `# H1` title, then one italic line giving its status and date.
  - The status is one of `Draft`, `Current`, `Superseded by <link>` or `Snapshot`. Reviews and research are `Snapshot`, since they describe a moment in time.
  - The date is the last meaningful update, ISO format: `*Current · updated 2026-11-23*`.
- **New docs** go in the right folder and get a row in the index above, in the same PR.
- **Moving or renaming a doc:** use `git mv`, then `grep -rn "<old path>"` across the repo and update every reference: code comments, tools, other docs, `CLAUDE.md`.
- **Links:** use relative Markdown links between docs, and point to code as `path/to/file.gd:LINE` (good enough for a snapshot; it can drift). In living docs, name the function or class instead, e.g. ``Circuit.progress_at()``.
- **Images:** put them in `docs/<folder>/img/`, as `png` for screenshots and `svg` for diagrams, each under 1 MB. Generate screenshots with the `tests/screenshot_*.gd` scripts so they can be redone.

## Writing style

- **Plain English.** Short sentences. One idea per paragraph. No filler ("it is worth noting that…").
- **British spelling** ("tyre", "colour", "behaviour"). Code identifiers stay exactly as they are in the code (`TireModel`, `paint_color`).
- **Numbers carry units:** `120 Hz`, `0.85 g`, `3.2 m`, `450 N·m`, `lap fraction 0–1`. Use SI units, as the code does.
- **Lead with the point.** Each section opens with the conclusion; details follow.
- **Be concrete.** "Two peers with different damage settings desync on the first crash" beats "this may cause issues".
- **Mark uncertainty** with *(uncertain)* or *(not yet measured)* rather than presenting guesses as fact.
- **Tables** suit lists of comparable things; **bullets** for steps or short items; **prose** for reasoning.
- **No dead content:** no `TODO: write this` stubs and no empty sections. Leave a section out until there's something to say.
- Cite the design doc as `§N` (e.g. `§6.3`) in code and in other docs.

## Decision records (ADRs)

- Copy `decisions/0000-template.md` and take the next number.
- **Status flow:** `Proposed` → `Accepted` → (later) `Superseded by NNNN` or `Deprecated`.
- Never edit an accepted ADR's decision. To change it, write a new ADR and set the old one to `Superseded by NNNN`.
- Keep each one to about a page. If it needs more, the detail belongs in `architecture/` or `research/`, linked from the ADR.
- The person who owns the repo accepts ADRs. An agent may write one as `Proposed`, but must not set it to `Accepted` itself.

## Reviews

- **Finding IDs are stable and never reused.** Each review gets a prefix (`MF-` for multiplayer must-fix, `NH-` for multiplayer nice-to-have); a new review picks its own prefix.
- **Each finding has:** ID, title, severity, evidence (`file:line`), why it matters (a concrete scenario), the fix, effort (S/M/L), and who found it.
- **Fixed findings stay in the doc,** marked `✅ Fixed in #<PR>`, so the history is kept. A finding that turns out wrong is marked `❌ Not an issue: <reason>`.
- Each finding gets its own GitHub issue (review ID in the title). Commits and PRs reference the issue number (see the Git workflow in `CLAUDE.md`) and mention the review ID in the body.

## Code documentation (GDScript)

Docs in `docs/` explain systems. Comments in code explain the code itself. Both are required.

- **`##` doc comments are required on:**
  - Every `class_name` script: a header block under `extends` saying what the class is, what owns it, and which `§N` it implements.
  - Every `signal`: when it fires and what its arguments mean.
  - Every `@export`: meaning, units and range, e.g. `## Spring rate per wheel, N/m. 20 000–80 000.`.
  - Every public `func` (no leading `_`): what it does, what it returns, and side effects such as scene changes, saving or teleporting.
  - Public `var`s that other scripts read: units and range.
- **`make docs-check` enforces these rules** for scripts, signals, `@export`s and public `func`s; run it before opening a PR. It can't tell which public `var`s other scripts read, so those are on you. It also fails on broken links between docs (lychee, offline) and on repo paths in backticks that don't exist, e.g. after a move (docs in `plans/` are exempt, since they name files still to be written).
- **Optional on private `_helpers`:** add a `#` comment only when the *why* isn't obvious from the code.
- **Comments describe the code as it is now.** History belongs in git ("used to be X" doesn't go in a comment). Delete a comment that no longer matches.
- **Ranges and enums are spelled out:** `## -1 (left) … +1 (right)`, `## 0 Arcade, 1 Sport, 2 Sim`.
- **Tests:** each test file's header comment gives the exact command line, its options, and what it checks. New tests follow the existing `<name> PASSED` / `FAILED` and `[ok]` / `[FAIL]` output format.
- **Python tools:** each one has a module docstring with usage and what it writes.
