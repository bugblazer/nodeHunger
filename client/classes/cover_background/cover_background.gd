extends Sprite2D
## Scales a full-screen menu background so it always covers the window, whatever
## its shape, without stretching the art. Wider or taller windows crop the top of
## the picture, so the logo and mascot along the bottom stay in view.

func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()

func _fit() -> void:
	var art := region_rect.size if region_enabled else texture.get_size()
	var view := get_viewport_rect().size
	var s: float = max(view.x / art.x, view.y / art.y)
	centered = false
	scale = Vector2(s, s)
	position = Vector2((view.x - art.x * s) / 2.0, view.y - art.y * s)
