# Short commands for running, testing and building RRS. `make help` lists them.
#
# Override the tools on the command line, e.g. on Windows:
#   make test GODOT=Godot_console.exe PY=python
# Godot tests always exit 0, so `test-%` reads their output instead: a run
# fails if it prints FAILED, [FAIL] or SCRIPT ERROR, or never prints
# "<name> PASSED" / "<name> done".

GODOT   ?= godot
PY      ?= python3
TIMEOUT ?= timeout 900
LYCHEE  ?= lychee
# Python for the signalling server: its own venv, made by `make server-venv`.
# On Windows: SERVER_PY=server/.venv/Scripts/python.exe
SERVER_PY ?= server/.venv/bin/python
# Extra arguments for a single test, e.g. make test-race_test ARGS="--laps=2 --track=rx"
ARGS    ?=

# Network tests live in tests/net/ and run with `make test-net`, not `make test`.
NET_TESTS := webrtc_available_test

SMOKE_TESTS := race_test lap_test drive_test car_stats_test damage_test \
               tournament_test tournament_cards_test menu_test

# Default arguments per test, taken from each test's header comment.
race_test_ARGS       := --laps=1 --scene=circuit_race --track=spa
tournament_test_ARGS := --players=1 --tracks=rx

# A test is looked up in tests/, then tests/net/. One with a .tscn runs as a
# scene; otherwise its .gd runs as a script.
test_dir    = $(if $(wildcard tests/net/$(1).*),tests/net,tests)
test_target = $(if $(wildcard $(call test_dir,$(1))/$(1).tscn),res://$(call test_dir,$(1))/$(1).tscn,-s res://$(call test_dir,$(1))/$(1).gd)

# Hides the "missing MP3" errors (the soundtrack is not in git) and their backtraces.
HIDE_MUSIC_ERRORS := awk '/ERROR:.*(mp3|soundtrack)/ {skip=1; next} skip && /^[[:space:]]/ {next} {skip=0; print}'

.DEFAULT_GOAL := help
.PHONY: help play editor import webrtc server-venv signalling test-signalling test test-net hitbox docs-check car-configs sounds pdf export-web export-windows export-linux serve-web

help: ## List the commands
	@grep -hE '^[a-zA-Z_%-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-16s %s\n", $$1, $$2}'

play: ## Run the game
	$(GODOT) --path .

editor: ## Open the project in the Godot editor
	$(GODOT) --editor --path .

import: ## Import assets (needed once after a fresh clone, before tests)
	$(GODOT) --headless --path . --import

webrtc: ## Download the desktop WebRTC add-on and import it (needed once, before net tests)
	$(PY) tools/fetch_webrtc.py
	$(GODOT) --headless --path . --import

server-venv: ## Create server/.venv with the signalling server's dependencies (uses uv if installed)
	@if command -v uv >/dev/null 2>&1; then \
		uv venv -q server/.venv && uv pip install -q --python $(SERVER_PY) -r server/signalling/requirements.txt; \
	else \
		$(PY) -m venv server/.venv && $(SERVER_PY) -m pip install -q -r server/signalling/requirements.txt; \
	fi

signalling: ## Run the signalling server locally on ws://127.0.0.1:9081
	$(SERVER_PY) server/signalling/signalling.py --host 127.0.0.1 --port 9081

test-signalling: ## Run the signalling server's unit tests
	$(SERVER_PY) -m unittest discover -s server/signalling -v

test: $(addprefix test-,$(SMOKE_TESTS)) ## Run all main smoke tests
	@echo "All smoke tests passed: $(SMOKE_TESTS)"

test-net: $(addprefix test-,$(NET_TESTS)) ## Run the network tests (run make webrtc once first)
	@echo "All network tests passed: $(NET_TESTS)"

test-%: ## Run one test, e.g. make test-damage_test [ARGS="..."]
	@echo "== $*"
	@log=$$(mktemp); \
	$(TIMEOUT) $(GODOT) --headless --fixed-fps 120 --path . $(call test_target,$*) -- $(or $(ARGS),$($*_ARGS)) >$$log 2>&1; \
	$(HIDE_MUSIC_ERRORS) $$log; \
	if grep -qE 'FAILED|\[FAIL\]|SCRIPT ERROR' $$log || ! grep -qE '^$* (PASSED|done)' $$log; then \
		echo "✗ $* failed"; rm -f $$log; exit 1; \
	fi; \
	rm -f $$log; echo "✓ $*"

hitbox: ## Check collision matches drawn geometry (opens a window)
	$(GODOT) --path . -s res://tests/hitbox_check.gd

docs-check: ## Check doc comments in scripts/, and links and quoted paths in the docs
	@status=0; \
	$(PY) tools/docs_check.py || status=1; \
	if command -v $(LYCHEE) >/dev/null 2>&1; then \
		$(LYCHEE) --offline --no-progress --include-fragments CLAUDE.md 'docs/**/*.md' || status=1; \
	else \
		echo "lychee not found: install it from https://github.com/lycheeverse/lychee/releases"; status=1; \
	fi; \
	exit $$status

export-windows: ## Export the Windows build to build/windows/
	mkdir -p build/windows
	$(GODOT) --headless --path . --export-release "Windows Desktop" build/windows/RRS.exe

export-linux: ## Export the Linux build to build/linux/
	mkdir -p build/linux
	$(GODOT) --headless --path . --export-release "Linux" build/linux/RRS.x86_64

export-web: ## Export the Web (no-threads) build to build/web/
	mkdir -p build/web
	$(GODOT) --headless --path . --export-release "Web" build/web/index.html

serve-web: ## Serve build/web/ at http://localhost:8060
	$(PY) -m http.server 8060 -d build/web

car-configs: ## Regenerate assets/cars/<id>/<id>.tres from tools/make_car_configs.py
	$(PY) tools/make_car_configs.py

sounds: ## Regenerate the car sound effects
	$(PY) tools/make_sounds.py

pdf: ## Rebuild the design doc PDF (needs Edge or Chrome)
	$(PY) tools/md_to_pdf.py docs/design/RRS_Design_Concept.md
