extends SceneTree
## Renders the lettering on the glove's wrist tape to a white-on-black mask (assets/branding/glove_tape.res).
## Needs a display (not --headless): godot --path . -s tools/gen_glove_tape.gd
## [text, size, top of its line box]
const LINES := [["Fairtex", 124, 14], ["Fighter", 84, 134]]
const SIZE := Vector2i(512, 256)  ## one repeat: half the way round the wrist
const OUT := "res://assets/branding/glove_tape.res"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var view := SubViewport.new()
	view.size = SIZE
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var back := ColorRect.new()
	back.color = Color.BLACK
	back.size = SIZE
	view.add_child(back)
	var font := SystemFont.new()
	font.font_names = ["Red Hat Display", "Roboto Flex", "sans-serif"]
	font.font_italic = true
	font.font_weight = 800
	var slanted := FontVariation.new()
	slanted.base_font = font
	slanted.variation_transform = Transform2D(Vector2(1, 0.22), Vector2(0, 1), Vector2.ZERO)
	for line in LINES:
		var label := Label.new()
		label.text = line[0]
		label.add_theme_font_override("font", slanted)
		label.add_theme_font_size_override("font_size", line[1])
		label.add_theme_color_override("font_color", Color.WHITE)
		label.position = Vector2(0, line[2])
		label.size = Vector2(SIZE.x, 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		view.add_child(label)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := view.get_texture().get_image()
	img.convert(Image.FORMAT_L8)
	var used := img.get_used_rect()
	ResourceSaver.save(img, OUT, ResourceSaver.FLAG_COMPRESS)
	print("saved %s %s (text drawn: %s)" % [OUT, img.get_size(), used])
	quit()
