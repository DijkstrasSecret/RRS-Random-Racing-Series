extends SceneTree
func _init():
	GameSettings.use_defaults()
	GameSettings.time_of_day = 3
	var scene := (load("res://scenes/modes/circuit_practice.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 120:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://screenshots/dbg_a.png")
	scene.get_node("Circuit/Atmosphere/ScreenFX").visible = false
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://screenshots/dbg_b.png")
	quit()
