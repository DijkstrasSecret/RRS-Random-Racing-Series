class_name CarPaint
extends RefCounted
## Repaints a car texture in any colour (design concept §13 "paint mask").
## The paint area is found by comparing the car's texture with a second
## colour variant of it: pixels that differ are paint. Paint pixels get the
## new colour but keep their original light and shade. Results are cached.

static var _cache: Dictionary = {}


## Texture `base` repainted in `color`; `reference` is the same texture in another colour, used to find the paint pixels.
static func make(base: Texture2D, reference: Texture2D, color: Color) -> Texture2D:
	var key := "%s|%s|%s" % [base.resource_path, reference.resource_path, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var a := _rgba(base.get_image())
	var b := _rgba(reference.get_image())
	if b.get_size() != a.get_size():
		b.resize(a.get_width(), a.get_height(), Image.INTERPOLATE_NEAREST)
	var w := a.get_width()
	var h := a.get_height()
	# Pass 1: find the paint pixels and their average brightness.
	var mask := PackedByteArray()
	mask.resize(w * h)
	var total_v := 0.0
	var count := 0
	for y in h:
		for x in w:
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			if absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b) > 0.12:
				mask[y * w + x] = 1
				total_v += pa.v
				count += 1
	var avg_v := total_v / maxi(count, 1)
	# Pass 2: recolour, keeping each pixel's brightness relative to the average.
	var out := a.duplicate() as Image
	for y in h:
		for x in w:
			if mask[y * w + x] == 1:
				var pa := a.get_pixel(x, y)
				var shade := pa.v / maxf(avg_v, 0.01)
				out.set_pixel(x, y, Color.from_hsv(color.h, color.s, clampf(color.v * shade, 0.0, 1.0), pa.a))
	out.generate_mipmaps()
	var tex := ImageTexture.create_from_image(out)
	_cache[key] = tex
	return tex


static func _rgba(img: Image) -> Image:
	var copy := img.duplicate() as Image
	if copy.is_compressed():
		copy.decompress()
	copy.clear_mipmaps()
	copy.convert(Image.FORMAT_RGBA8)
	return copy
