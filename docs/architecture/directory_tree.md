# RRS — Directory Tree

*Current · updated 2026-11-26*

```
RRS-Random-Racing-Series/
├── CLAUDE.md              Rules and architecture notes for AI coding agents working on the repo.
├── Makefile               Short commands to play, import, run the smoke tests and run the Python tools; `make help`.
├── project.godot          Godot 4.7 project config: Jolt physics at 120 Hz, the main menu as the start scene, and the Music autoload.
├── .mcp.json              MCP server config the author uses to drive Godot and Blender from Claude.
├── addons/                Empty; reserved for Godot plugins.
├── assets/
│   ├── audio/car/         Engine, EV whine, tyre and dirt-rumble sound loops (.wav).
│   ├── cars/              22 car models; each folder holds a .glb mesh, a .tres config and light/livery textures.
│   │   ├── _source/       The master cars.blend that all the car models come from.
│   │   └── psx_hatch/     A third-party low-poly hatchback with credits and its original .blend/.obj sources.
│   ├── track_kit/         Trackside props (barriers, fences and similar) as a .glb, plus the source .blend.
│   ├── tracks/            Empty; tracks are generated in code rather than stored as models.
│   ├── ui/                Logo, cover and splash images.
│   │   └── track_clips/   Short .ogv preview videos for each track on the track select screen.
│   └── vfx/shaders/       The PS1-style lit and decal shaders, cloud shaders and the preview-screen shader.
├── docs/                  Project docs by purpose: design/, architecture/, decisions/ (ADRs), research/, reviews/; index in docs/README.md.
├── scenes/
│   ├── modes/             Playable mode scenes: free roam, practice, circuit race and versus race.
│   ├── tracks/            The procedural circuit scene and a test track.
│   ├── ui/                The main menu and tournament shop scenes.
│   └── vehicle/           The generic car scene and the PSX hatch variant.
├── scripts/
│   ├── ai/                The AI driver that follows the racing line and avoids other cars.
│   ├── camera/            The chase camera.
│   ├── core/              Global game state: car roster, saved settings and the music player.
│   ├── fx/                Controls for the retro PS1/PS2 visual look.
│   ├── input/             The shared driver-input class, plus player input and input-action setup.
│   ├── modes/             Setup logic for the drive and versus modes.
│   ├── race/              Race rules: race director, lap timer, tournament, upgrades and car perks.
│   ├── series/            Empty; probably meant for the "Random Series" championship system.
│   ├── tracks/            Procedural circuit and terrain generation, trackside dressing, atmosphere and the track list.
│   ├── ui/                Every menu, panel and the in-race HUD, plus shared menu styling.
│   └── vehicle/           Car physics (tyres, wheels, drivetrain, assists) plus damage, audio, paint and looks.
├── soundtrack/            Godot import files only; the licensed MP3s are kept off the repo.
├── tests/                 About 40 scripts that run without a window: smoke tests, probes, checks and screenshot capture.
└── tools/                 Python scripts that build cars and the track kit in Blender, generate sounds, and export the docs to PDF.
```
