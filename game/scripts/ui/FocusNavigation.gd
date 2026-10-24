extends RefCounted
## Focus newly opened panels without stealing an existing text/list selection.
static func focus_first(panel: Control) -> void:
	if not is_instance_valid(panel) or not panel.is_visible_in_tree():
		return
	var current := panel.get_viewport().gui_get_focus_owner()
	if current != null and panel.is_ancestor_of(current) and current.is_visible_in_tree():
		return
	var target := _first_enabled(panel)
	if target != null:
		target.grab_focus()

static func _first_enabled(node: Node) -> Control:
	if node is Control:
		var control := node as Control
		if not control.is_visible_in_tree():
			return null
		if control.focus_mode == Control.FOCUS_ALL and not (control is BaseButton and control.disabled):
			return control
	for child in node.get_children():
		var found := _first_enabled(child)
		if found != null:
			return found
	return null
