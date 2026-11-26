# 0001. Record architecture decisions as ADRs

*Proposed · 2026-11-23*

## Context
The project is moving from single-player to online multiplayer (8 players, Windows + Web cross-play, split-screen, tournaments online). That needs several hard-to-reverse choices: network model, transport, renderer, who owns race state. So far the reasons for choices have lived in commit messages and the design doc, where they are hard to find later.

## Options
1. **Keep reasons in commit messages and the design doc.** No extra files, but the reasons get scattered and are easy to lose.
2. **Short numbered decision records in `docs/decisions/`.** A little overhead per decision; each reason has one obvious home and a visible history.

## Decision
We will record every significant architecture or multiplayer decision as a numbered ADR in `docs/decisions/`, following `0000-template.md` and the rules in `docs/README.md`.

## Consequences
- The first decisions to record are the network model and transport (MF-1) and the renderer (MF-2).
- Agents may draft ADRs as `Proposed`; only the repo owner accepts them.
- Decisions are never edited after acceptance. They are superseded by a new ADR, so the history stays readable.
