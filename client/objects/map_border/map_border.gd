extends Node2D
## The walls around the playable map, drawn like Agar.io's border.
## MAP_HALF_SIZE must match MapHalfSize on the server (internal/server/objects/spawn.go):
## the server stops players at the wall, and the client draws it in the same place.

const MAP_HALF_SIZE := 3000.0
const WALL_WIDTH := 14.0
const WALL_COLOR := Color(1.0, 0.42, 0.25, 0.9)
const OUTSIDE_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const OUTSIDE_EXTENT := 20000.0 # far enough to cover the view when fully zoomed out

## Keeps a circle of the given radius fully inside the map (same rule as the server).
static func clamp_to_map(point: Vector2, radius: float) -> Vector2:
	var limit: float = max(MAP_HALF_SIZE - radius, 0.0)
	return Vector2(clampf(point.x, -limit, limit), clampf(point.y, -limit, limit))

func _draw() -> void:
	var h := MAP_HALF_SIZE
	var e := OUTSIDE_EXTENT
	# Darken everything outside the map so the edge is obvious from far away.
	draw_rect(Rect2(-e, -e, 2 * e, e - h), OUTSIDE_COLOR)       # above
	draw_rect(Rect2(-e, h, 2 * e, e - h), OUTSIDE_COLOR)        # below
	draw_rect(Rect2(-e, -h, e - h, 2 * h), OUTSIDE_COLOR)       # left
	draw_rect(Rect2(h, -h, e - h, 2 * h), OUTSIDE_COLOR)        # right
	# The wall itself.
	draw_rect(Rect2(-h, -h, 2 * h, 2 * h), WALL_COLOR, false, WALL_WIDTH)
