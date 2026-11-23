# Tournament mode: upgrade system

Code: `scripts/race/tournament.gd` (flow, economy), `scripts/race/upgrades.gd` (cards),
`scripts/race/car_perks.gd` (race-time effects), `scripts/ui/tournament_shop.gd` (shop screen).
Tests: `tests/tournament_cards_test.gd`, `tests/tournament_test.gd`.

## Format
- 6 one-lap races on random tracks, with a shop after each of the first five.
- Every race pays points by position: 10 / 8 / 6 / 5 / 4 / 3 / 2 / 1. A DNF scores 0.
- Only races 4–6 count for the tournament score. Races 1–3 only earn shop points.
- Ties on score go to the better finish in race 6.
- The grid is set by points earned, so the leader starts at the back.

## Controls
| | Xbox | Keyboard (P1) | Keyboard (P2) |
|---|---|---|---|
| Power item (X) | X | Left Shift | Right Shift |
| Tactical item (Y) | Y | R | Right Ctrl |

Recovery is switched off in tournaments.

## DNF (no recovery)
A car is out of the race after any of these:
- 5 s upside down
- 8 s stuck (under 1 m/s)
- 8 s with a wheel missing

The rule applies to AI cars too: they never reset out of a roll-over or a lost wheel.
The race ends once every human player has finished or is out.

## Carry-over and services
- Tyre wear and body / engine damage carry over from race to race. Punctures and bent suspension are fixed between races.
- Fresh Tyres cost 3 points.
- Repairs cost 1 point per 10% of damage.
- A reroll costs 2 points. The winner of the last race gets one free reroll.

## Shop
- Each shop shows 4 cards: 2 stat cards and 2 unlock cards.
- Rarity odds blend from the first shop to the last:

| Shop | Common | Rare | Epic | Legendary |
|---|---|---|---|---|
| First | 70% | 25% | 5% | 0% |
| Last | 30% | 35% | 25% | 10% |

- Rarity multiplies both the price and the effect: Common ×1, Rare ×1.5, Epic ×2, Legendary ×3.

## Stat cards
| Stat | Base value | Base price | Stacking |
|---|---|---|---|
| Power | +3% engine power | 6 | additive |
| Top Speed | +2% | 5 | additive |
| Grip | +3% | 6 | additive |
| Braking | +4% | 4 | additive |
| Weight | −2% mass | 5 | multiplicative |
| Tire Preservation | −15% wear | 4 | multiplicative |
| Durability | −3% damage | 4 | multiplicative |

Wording: every "+% power" in the game (Power cards, nitro, KERS, Push-to-Pass, Engine Map,
Overbored Engine, Perfect Shift) works the same way: it scales the engine's torque at every rpm,
which is the same as scaling its power. They multiply together.

How Top Speed works: drag is divided by (1+s)³ and the final drive by (1+s).

## Unlocks
### General rules
- Buying an unlock you already own levels it up, up to III.
- You can hold at most 4 skill passives.
- A new X or Y item replaces the one in that slot.

### Skill passives
- **Perfect Shift (10):** an upshift at 94%+ of the redline gives +12% power for 1 s. Each level widens the window by 2.5% and adds 3% power.
- **Heel-Toe (9):** a downshift while braking steadies the rear (+6% rear grip for 0.8 s) and adds 34% to a meter. A full meter gives +8% grip for 2 s when you get back on the throttle.
- **Drift Harvest (9):** a handbrake slide of 0.4 s or more charges the X item by 0.35 s of boost per second.
- **Late Braker (9):** starting to brake less than 1.6 s before a corner gives +8% grip for 1.8 s after you release the brake.
- **Clean Sector (10):** 8 s without touching a wall slowly recharges the X item.

### Power actives (X)
- **Nitro: Burst (10):** one 2.5 s boost of +55% power.
- **Nitro: Charges (10):** three 1 s boosts of +45% power.
- **Nitro: Regen (9):** a 1.5 s bottle of +35% power that refills itself.
- **KERS (11):** braking stores energy (up to 2 s); hold X for +40% power.
- **Push-to-Pass (8):** three uses per race of 3 s at +25% power.

### Tactical actives (Y)
- **Engine Map (9):** switches between the POWER map (+6% power) and the STABILITY map (−4% power, traction control, steadier rear).
- **DRS (11):** usable within 1 s of the car ahead; −22% drag while held. It closes when you brake.

### Risk / curse
- **Overbored Engine (8):** +12% power. More than 2 s at the redline damages the engine; Durability reduces this.
- **Stripped Interior (8):** −12% weight, but each wall hit costs 12% of your speed.
- **Bet on Yourself (6):** stake 6 points. A podium in the next race pays 12; points only, never score.

### Economy
- **Interest (8):** +10% of unspent points each shop, up to +10.
- **Rival Bounty (6):** pick a rival in the shop. Beating them in a race pays +6.

## AI
- AI racers buy stat cards and X / Y items, plus fresh tyres and repairs when needed.
- They fire X and hold Y (DRS) on straights. Their engine map stays on POWER.
- They don't take skill passives, risk cards or economy cards.
