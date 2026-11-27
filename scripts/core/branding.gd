class_name Branding
extends RefCounted
## The OdinFC logo (assets/branding/odin_logo.svg). The SVG is a black square with the logo cut out as
## transparent holes, so we rasterise it and invert the alpha to get the logo as a solid, tintable shape.

const SVG_PATH := "res://assets/branding/odin_logo.svg"
static var _cache := {}

## The logo as a texture filled with `color` (alpha respects color.a). `scale` rasterises the SVG larger.
static func logo(color := Color.WHITE, scale := 1.5) -> ImageTexture:
	var key := "%s@%s" % [color.to_html(true), scale]
	if _cache.has(key):
		return _cache[key]
	var img := Image.new()
	if img.load_svg_from_buffer(FileAccess.get_file_as_bytes(SVG_PATH), scale) != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var edge := x < 2 or y < 2 or x >= img.get_width() - 2 or y >= img.get_height() - 2  # SVG border column
			var a := 0.0 if edge else 1.0 - img.get_pixel(x, y).a
			img.set_pixel(x, y, Color(color.r, color.g, color.b, a * color.a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
