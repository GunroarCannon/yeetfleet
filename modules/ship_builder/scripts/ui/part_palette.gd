## The parts catalogue: search, filter, and the source of every drag.
##
## Two ways in, on purpose. Dragging a card onto a socket is the direct, obvious
## route. Tapping a socket first and then tapping a card is the route that works
## with a keyboard, with one thumb, and when the socket is buried inside a capital
## hull where hitting it with a drag would be miserable. The second flow is why the
## palette can filter itself to a socket: once a socket is chosen, a 72-part
## catalogue collapses to the handful of parts that actually fit.
class_name PartPalette
extends VBoxContainer

const CATEGORY_TABS: Array[String] = [
	"", "chassis", "cockpit", "engine", "weapon", "cargo", "wing", "armor", "greeble"
]

var _root: BuilderRoot
var _category := ""
var _search := ""
var _size_filter := ""
## The socket the palette is currently filtered to, or {} for the whole catalogue.
var _socket_entry: Dictionary = {}
var _show_incompatible := false

var _category_options: OptionButton
var _search_field: LineEdit
var _size_options: OptionButton
var _context_bar: PanelContainer
var _context_label: Label
var _list: VBoxContainer
var _count_label: Label
var _incompatible_toggle: CheckButton


func _ready() -> void:
	_root = owner as BuilderRoot
	_build_ui()
	_root.design_rebuilt.connect(_on_design_rebuilt)


func _build_ui() -> void:
	var header := Label.new()
	header.text = "PARTS"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", BuilderTheme.text_dim())
	add_child(header)

	_search_field = LineEdit.new()
	_search_field.placeholder_text = "Search parts…"
	_search_field.clear_button_enabled = true
	_search_field.custom_minimum_size.y = BuilderTheme.TOUCH_MIN - 8
	_search_field.text_changed.connect(func(t: String) -> void:
		_search = t
		_refresh()
	)
	add_child(_search_field)

	# One filter row, two dropdowns. This was nine category chips and a labelled
	# size row: three lines of controls, permanently on screen, for a choice most
	# players make once. Collapsed to a pair of pickers it costs one line on a
	# phone and still fits the whole taxonomy.
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", BuilderTheme.GAP)
	add_child(filter_row)

	_category_options = OptionButton.new()
	_category_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category_options.custom_minimum_size.y = BuilderTheme.TOUCH_MIN - 10
	_category_options.tooltip_text = "Narrow the catalogue to one kind of part"
	for i in CATEGORY_TABS.size():
		var category: String = CATEGORY_TABS[i]
		var label: String = "All parts" if category == "" else ShipPart.CATEGORY_LABELS.get(category, category.capitalize())
		_category_options.add_item(label, i)
	_category_options.item_selected.connect(func(index: int) -> void:
		_category = CATEGORY_TABS[index]
		_refresh()
	)
	filter_row.add_child(_category_options)

	_size_options = OptionButton.new()
	_size_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_size_options.custom_minimum_size.y = BuilderTheme.TOUCH_MIN - 10
	_size_options.add_item("Any size", 0)
	for i in ShipPart.SIZE_CLASSES.size():
		_size_options.add_item(ShipPart.SIZE_CLASSES[i].capitalize(), i + 1)
	_size_options.tooltip_text = "Sockets only take parts of matching size classes"
	_size_options.item_selected.connect(func(index: int) -> void:
		_size_filter = "" if index == 0 else ShipPart.SIZE_CLASSES[index - 1]
		_refresh()
	)
	filter_row.add_child(_size_options)

	# The socket-context bar. Hidden until a socket is chosen, at which point it is
	# the most important thing in the panel.
	_context_bar = PanelContainer.new()
	_context_bar.visible = false
	_context_bar.add_theme_stylebox_override(
		"panel", BuilderTheme.flat(BuilderTheme.accent().darkened(0.72), BuilderTheme.accent(), 4)
	)
	add_child(_context_bar)
	var context_box := VBoxContainer.new()
	context_box.add_theme_constant_override("separation", 2)
	_context_bar.add_child(context_box)
	_context_label = Label.new()
	_context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_context_label.add_theme_font_size_override("font_size", 11)
	context_box.add_child(_context_label)
	var context_buttons := HBoxContainer.new()
	context_box.add_child(context_buttons)
	var clear_button := Button.new()
	clear_button.text = "Show all parts"
	clear_button.add_theme_font_size_override("font_size", 11)
	clear_button.pressed.connect(clear_socket_filter)
	context_buttons.add_child(clear_button)
	_incompatible_toggle = CheckButton.new()
	_incompatible_toggle.text = "Incompatible"
	_incompatible_toggle.add_theme_font_size_override("font_size", 11)
	_incompatible_toggle.tooltip_text = "List parts that do not fit, with the reason why"
	_incompatible_toggle.toggled.connect(func(on: bool) -> void:
		_show_incompatible = on
		_refresh()
	)
	context_buttons.add_child(_incompatible_toggle)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_list)

	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 10)
	_count_label.add_theme_color_override("font_color", BuilderTheme.text_dim())
	add_child(_count_label)


func _on_design_rebuilt(_view: ShipView) -> void:
	# The focused socket may have just been filled, in which case the filter is
	# stale and would list parts for a socket that no longer exists.
	if not _socket_entry.is_empty():
		var path := String(_socket_entry.get("path", ""))
		if _root.view.resolution.find_open_socket(path).is_empty():
			_socket_entry = {}
	_refresh()


## Narrow the palette to what fits one socket. Called when a socket is tapped or
## cycled to with the keyboard.
func filter_to_socket(entry: Dictionary) -> void:
	_socket_entry = entry
	var socket := entry["socket"] as PartSocket
	var label := socket.display_name if socket.display_name != "" else socket.id
	var mirrored: bool = bool(entry.get("shadow", false)) or socket.is_mirror()
	var lines := "Fitting %s — takes %s, size %s" % [
		label, ", ".join(socket.accepts), ", ".join(socket.size_classes)
	]
	if mirrored:
		lines += "\nMirrored: fitting here fills both sides."
	if socket.required:
		lines += "\nThis mount is required."
	_context_label.text = lines
	_context_bar.visible = true
	_category = ""
	_category_options.select(0)
	_refresh()


func clear_socket_filter() -> void:
	_socket_entry = {}
	_context_bar.visible = false
	if _root.view != null:
		_root.view.emphasise_socket("")
	_refresh()


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	var parts := _collect()
	var shown := 0
	for item in parts:
		var card := PartCard.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list.add_child(card)
		card.setup(item["part"] as ShipPart, String(item["rejection"]))
		card.chosen.connect(_on_card_chosen)
		card.considered.connect(_on_card_considered)
		card.unconsidered.connect(_root.clear_preview)
		shown += 1
	if shown == 0:
		var empty := Label.new()
		empty.text = "Nothing matches. Clear the search or the size filter."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", BuilderTheme.text_dim())
		_list.add_child(empty)
	_count_label.text = "%d of %d parts" % [shown, _root.library.count()]


## Build the display list, in the order the player should read it: compatible
## parts, then — only if asked for — the ones that do not fit, each carrying the
## socket's own explanation of why.
func _collect() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var candidates := _root.library.filter_parts(_category, _size_filter, _search)
	if _socket_entry.is_empty():
		for part in candidates:
			out.append({"part": part, "rejection": ""})
		return out
	var socket := _socket_entry["socket"] as PartSocket
	var rejected: Array[Dictionary] = []
	for part in candidates:
		if socket.accepts_part(part):
			out.append({"part": part, "rejection": ""})
		elif _show_incompatible:
			rejected.append({"part": part, "rejection": socket.rejection_reason(part)})
	out.append_array(rejected)
	return out


func _on_card_considered(part_id: String) -> void:
	var socket_path := String(_socket_entry.get("path", ""))
	_root.preview_fit(socket_path, part_id)


## Activating a card fits the part without any dragging. Where it goes, in order of
## preference: the socket the palette is filtered to; the socket of the currently
## selected part (a swap); or the first empty socket that takes it.
func _on_card_chosen(part_id: String) -> void:
	var part := _root.library.get_part(part_id)
	if part == null:
		return
	if part.category == "chassis":
		_root.swap_chassis(part_id)
		return
	if not _socket_entry.is_empty():
		var path := String(_socket_entry["path"])
		if _root.place_part(path, part_id):
			clear_socket_filter()
		return
	var selected_placement := _root.selected_placement()
	if selected_placement != null and selected_placement.socket != null \
			and selected_placement.socket.accepts_part(part):
		_root.replace_part(_root.selected, part_id)
		return
	var open := _root.view.resolution.sockets_accepting(part)
	if open.is_empty():
		_root.notice.emit(
			"No free %s mount takes a %s" % [part.category, part.size_class], "error"
		)
		return
	_root.place_part(String(open[0]["path"]), part_id)


## Jump the keyboard focus into the list, so Tab from the search field lands
## somewhere useful.
func focus_first_card() -> void:
	for child in _list.get_children():
		if child is PartCard:
			(child as PartCard).grab_focus()
			return


func focus_search() -> void:
	_search_field.grab_focus()
	_search_field.select_all()
