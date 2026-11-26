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
# Extra arguments for a single test, e.g. make test-race_test ARGS="--laps=2 --track=rx"
ARGS    ?=

SMOKE_TESTS := race_test lap_test drive_test car_stats_test damage_test \
               tournament_test tournament_cards_test menu_test

# Default arguments per test, taken from each test's header comment.
race_test_ARGS       := --laps=1 --scene=circuit_race --track=spa
tournament_test_ARGS := --players=1 --tracks=rx

# A test with a .tscn runs as a scene; otherwise its .gd runs as a script.
test_target = $(if $(wildcard tests/$(1).tscn),res://tests/$(1).tscn,-s res://tests/$(1).gd)

# Hides the "missing MP3" errors (the soundtrack is not in git) and their backtraces.
HIDE_MUSIC_ERRORS := awk '/ERROR:.*(mp3|soundtrack)/ {skip=1; next} skip && /^[[:space:]]/ {next} {skip=0; print}'

.DEFAULT_GOAL := help
.PHONY: help play editor import test hitbox car-configs sounds pdf

help: ## List the commands
	@grep -hE '^[a-zA-Z_%-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-16s %s\n", $$1, $$2}'

play: ## Run the game
	$(GODOT) --path .

editor: ## Open the project in the Godot editor
	$(GODOT) --editor --path .

import: ## Import assets (needed once after a fresh clone, before tests)
	$(GODOT) --headless --path . --import

test: $(addprefix test-,$(SMOKE_TESTS)) ## Run all main smoke tests
	@echo "All smoke tests passed: $(SMOKE_TESTS)"

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

car-configs: ## Regenerate assets/cars/<id>/<id>.tres from tools/make_car_configs.py
	$(PY) tools/make_car_configs.py

sounds: ## Regenerate the car sound effects
	$(PY) tools/make_sounds.py

pdf: ## Rebuild the design doc PDF (needs Edge or Chrome)
	$(PY) tools/md_to_pdf.py docs/design/RRS_Design_Concept.md
