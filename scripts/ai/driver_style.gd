class_name DriverStyle
extends RefCounted
## Who the AI drivers are. Each name always drives the same way, so the player
## can learn them: some attack every gap, some block, some crack when you
## fill their mirrors. A style never changes grip, power or top speed, and
## how fast a driver laps still comes from the difficulty setting.
## All values 0..1:
## - aggression: how soon they go for a pass, how late they brake into it
## - defence: how readily they cover the inside when someone attacks
## - nerve: how well they cope with a car close behind (low = mistakes)
## - consistency: how rarely they make mistakes on their own

const STYLES := {
	"VEGA": {"label": "AGGRESSIVE", "aggression": 0.95, "defence": 0.6, "nerve": 0.7, "consistency": 0.7},
	"KATO": {"label": "ICE COLD", "aggression": 0.55, "defence": 0.4, "nerve": 1.0, "consistency": 0.95},
	"MOREAU": {"label": "BLOCKER", "aggression": 0.35, "defence": 1.0, "nerve": 0.75, "consistency": 0.8},
	"LIND": {"label": "GENTLEMAN", "aggression": 0.2, "defence": 0.1, "nerve": 0.8, "consistency": 0.9},
	"OKAFOR": {"label": "LATE BRAKER", "aggression": 0.85, "defence": 0.3, "nerve": 0.6, "consistency": 0.6},
	"RUIZ": {"label": "HOTHEAD", "aggression": 1.0, "defence": 0.8, "nerve": 0.1, "consistency": 0.5},
	"HALE": {"label": "VETERAN", "aggression": 0.5, "defence": 0.75, "nerve": 0.9, "consistency": 0.85},
	"NOVAK": {"label": "NERVOUS", "aggression": 0.4, "defence": 0.5, "nerve": 0.0, "consistency": 0.7},
	"SATO": {"label": "WILD", "aggression": 0.8, "defence": 0.45, "nerve": 0.5, "consistency": 0.3},
}
const DEFAULT := {"label": "", "aggression": 0.5, "defence": 0.5, "nerve": 0.7, "consistency": 0.8}


## The style for `driver_name` (aggression, defence, nerve, consistency 0..1 and a label); DEFAULT if it has none.
static func of(driver_name: String) -> Dictionary:
	return STYLES.get(driver_name, DEFAULT)


## Short name for the driver's character ("" if it has none: the players).
static func label(driver_name: String) -> String:
	return of(driver_name).label


## Gives `ai` the character of `driver_name` (see of()).
static func apply(ai: AIDriver, driver_name: String) -> void:
	var s := of(driver_name)
	ai.aggression = s.aggression
	ai.defence = s.defence
	ai.nerve = s.nerve
	ai.consistency = s.consistency
