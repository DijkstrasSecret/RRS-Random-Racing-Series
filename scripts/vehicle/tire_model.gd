class_name TireModel
extends RefCounted
## Simplified Pacejka "Magic Formula" (design concept §6.2).
##
## The curve works on a normalised combined slip `rho`, where rho = 1 is the
## peak of grip. Longitudinal and lateral slip are each divided by their peak
## value and combined into one vector, so a spinning wheel also loses
## sideways grip (friction circle).
##
## The shape factor C is chosen so the curve settles at `falloff` × peak
## after the peak. A high falloff (≈0.9) gives long, controllable slides.


## Shape factor C for a given falloff (fraction of peak grip kept when sliding).
static func shape_from_falloff(falloff: float) -> float:
	falloff = clampf(falloff, 0.3, 0.98)
	return 2.0 - 2.0 * asin(falloff) / PI


## Normalised grip: 0 at rho = 0, exactly 1 at rho = 1, tends to the falloff.
static func curve(rho: float, c: float) -> float:
	var b := tan(PI / (2.0 * c))
	return sin(c * atan(b * rho))


## Derivative of curve() with respect to rho.
static func curve_slope(rho: float, c: float) -> float:
	var b := tan(PI / (2.0 * c))
	var x := b * rho
	return cos(c * atan(x)) * c * b / (1.0 + x * x)
