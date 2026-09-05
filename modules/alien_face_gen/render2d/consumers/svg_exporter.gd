class_name SvgExporter


static func to_svg(dl: DrawList, size: int) -> String:
	var bounds := dl.bounds()
	if bounds.size.x < 0.001 or bounds.size.y < 0.001:
		return "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d'></svg>" % [size, size]
	
	# Add 6% padding
	var pad_x := bounds.size.x * 0.06
	var pad_y := bounds.size.y * 0.06
	var vx := bounds.position.x - pad_x
	var vy := bounds.position.y - pad_y
	var vw := bounds.size.x + pad_x * 2
	var vh := bounds.size.y + pad_y * 2
	
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='%s %s %s %s'>\n" % [
		size, size, _f(vx), _f(vy), _f(vw), _f(vh)
	]
	
	for c in dl.cmds:
		var pts: PackedVector2Array = c["points"]
		var col: Color = c["color"]
		var col_str := "rgb(%d,%d,%d)" % [int(col.r * 255), int(col.g * 255), int(col.b * 255)]
		
		match c["type"]:
			&"poly":
				if pts.size() >= 3:
					var pt_strs: PackedStringArray = []
					for p in pts:
						pt_strs.append("%s,%s" % [_f(p.x), _f(p.y)])
					svg += "<polygon points='%s' fill='%s' opacity='%.2f'/>\n" % [
						" ".join(pt_strs), col_str, col.a
					]
			&"line":
				if pts.size() >= 2:
					var pt_strs: PackedStringArray = []
					for p in pts:
						pt_strs.append("%s,%s" % [_f(p.x), _f(p.y)])
					var w: float = c["width"]
					svg += "<polyline points='%s' fill='none' stroke='%s' stroke-width='%s' opacity='%.2f'/>\n" % [
						" ".join(pt_strs), col_str, _f(maxf(w, 0.001)), col.a
					]
	
	svg += "</svg>"
	return svg


static func save(dl: DrawList, path: String, size: int) -> Error:
	var svg := to_svg(dl, size)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(svg)
	f.close()
	return OK


static func grid(lists: Array[DrawList], cols: int, cell: int, path: String) -> Error:
	if lists.is_empty():
		return ERR_INVALID_PARAMETER
	
	var rows := ceili(float(lists.size()) / cols)
	var total_w := cols * cell
	var total_h := rows * cell
	
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d'>\n" % [total_w, total_h]
	
	for i in range(lists.size()):
		var col_idx := i % cols
		var row_idx := i / cols
		var ox := col_idx * cell
		var oy := row_idx * cell
		
		var dl := lists[i]
		var bounds := dl.bounds()
		if bounds.size.x < 0.001 or bounds.size.y < 0.001:
			continue
		
		# Scale to fit cell with padding
		var pad := cell * 0.06
		var avail_w := cell - pad * 2
		var avail_h := cell - pad * 2
		var scale := minf(avail_w / bounds.size.x, avail_h / bounds.size.y)
		var offset_x := ox + pad + (avail_w - bounds.size.x * scale) / 2
		var offset_y := oy + pad + (avail_h - bounds.size.y * scale) / 2
		
		svg += "<g transform='translate(%s,%s) scale(%s) translate(%s,%s)'>\n" % [
			_f(offset_x), _f(offset_y), _f(scale),
			_f(-bounds.position.x), _f(-bounds.position.y)
		]
		
		for c in dl.cmds:
			var pts: PackedVector2Array = c["points"]
			var col: Color = c["color"]
			var col_str := "rgb(%d,%d,%d)" % [int(col.r * 255), int(col.g * 255), int(col.b * 255)]
			
			match c["type"]:
				&"poly":
					if pts.size() >= 3:
						var pt_strs: PackedStringArray = []
						for p in pts:
							pt_strs.append("%s,%s" % [_f(p.x), _f(p.y)])
						svg += "<polygon points='%s' fill='%s' opacity='%.2f'/>\n" % [
							" ".join(pt_strs), col_str, col.a
						]
				&"line":
					if pts.size() >= 2:
						var pt_strs: PackedStringArray = []
						for p in pts:
							pt_strs.append("%s,%s" % [_f(p.x), _f(p.y)])
						var w: float = c["width"]
						svg += "<polyline points='%s' fill='none' stroke='%s' stroke-width='%s' opacity='%.2f'/>\n" % [
							" ".join(pt_strs), col_str, _f(maxf(w, 0.001)), col.a
						]
		
		svg += "</g>\n"
	
	svg += "</svg>"
	
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(svg)
	f.close()
	return OK


static func _f(v: float) -> String:
	return "%.4f" % v
