module vpdf_compose

pub fn (mut doc Document) add_pdf_pages_from_bytes(bytes []u8) !int {
	source := bytes.bytestr()
	objects := expand_pdf_object_streams(parse_pdf_objects(source))
	if objects.len == 0 {
		return error('pdf objects not found')
	}
	object_map := pdf_object_map(objects)
	excluded := pdf_import_excluded_objects(objects)
	mut imported := 0
	for object in ordered_pdf_page_objects(source, objects, object_map) {
		page_body := pdf_page_body_with_inherited_attrs(object.body, object_map)
		support_objects := pdf_page_support_objects(page_body, object_map, excluded)
		doc.pages << PdfPage{
			kind:          'raw_pdf'
			raw_page_id:   object.id
			raw_page_body: page_body
			raw_objects:   support_objects.clone()
		}
		imported++
	}
	if imported == 0 {
		return error('pdf pages not found')
	}
	return imported
}

fn ordered_pdf_page_objects(source string, objects []PdfObject, object_map map[int]PdfObject) []PdfObject {
	ids := pdf_page_tree_order(source, objects, object_map)
	if ids.len > 0 {
		mut ordered := []PdfObject{}
		for id in ids {
			object := object_map[id] or { continue }
			if is_pdf_page_object(object.body) {
				ordered << object
			}
		}
		if ordered.len > 0 {
			return ordered
		}
	}
	mut ordered := []PdfObject{}
	for object in objects {
		if is_pdf_page_object(object.body) {
			ordered << object
		}
	}
	return ordered
}

fn pdf_page_tree_order(source string, objects []PdfObject, object_map map[int]PdfObject) []int {
	catalog := pdf_catalog_object(source, objects, object_map) or { return []int{} }
	root_pages_id := pdf_ref_value(catalog.body, '/Pages') or { return []int{} }
	mut seen := map[int]bool{}
	return pdf_collect_page_tree_ids(root_pages_id, object_map, mut seen)
}

fn pdf_catalog_object(source string, objects []PdfObject, object_map map[int]PdfObject) ?PdfObject {
	if root_id := pdf_latest_trailer_root_id(source) {
		if object := object_map[root_id] {
			if is_pdf_catalog_object(object.body) {
				return object
			}
		}
	}
	mut i := objects.len
	for i > 0 {
		i--
		object := objects[i]
		if is_pdf_catalog_object(object.body) {
			return object
		}
	}
	return none
}

fn pdf_latest_trailer_root_id(source string) ?int {
	mut root_id := 0
	mut offset := 0
	for offset < source.len {
		rel := source[offset..].index('trailer') or { break }
		trailer_at := offset + rel + 'trailer'.len
		dict_rel := source[trailer_at..].index('<<') or {
			offset = trailer_at
			continue
		}
		dict_start := trailer_at + dict_rel
		dict_end := pdf_balanced_dict_end(source, dict_start)
		if dict_end <= dict_start || dict_end > source.len {
			offset = trailer_at
			continue
		}
		if id := pdf_ref_value(source[dict_start..dict_end], '/Root') {
			root_id = id
		}
		offset = dict_end
	}
	if root_id <= 0 {
		return none
	}
	return root_id
}

fn pdf_collect_page_tree_ids(id int, object_map map[int]PdfObject, mut seen map[int]bool) []int {
	if id in seen {
		return []int{}
	}
	object := object_map[id] or { return []int{} }
	seen[id] = true
	if is_pdf_page_object(object.body) {
		return [id]
	}
	if !is_pdf_pages_object(object.body) {
		return []int{}
	}
	mut ids := []int{}
	for kid_id in pdf_kids_refs(object.body) {
		ids << pdf_collect_page_tree_ids(kid_id, object_map, mut seen)
	}
	return ids
}

fn pdf_object_map(objects []PdfObject) map[int]PdfObject {
	mut out := map[int]PdfObject{}
	for object in objects {
		out[object.id] = object
	}
	return out
}

fn pdf_import_excluded_objects(objects []PdfObject) map[int]bool {
	mut excluded := map[int]bool{}
	for object in objects {
		if is_pdf_catalog_object(object.body) || is_pdf_pages_object(object.body)
			|| is_pdf_page_object(object.body) {
			excluded[object.id] = true
		}
	}
	return excluded
}

fn pdf_page_support_objects(page_body string, object_map map[int]PdfObject, excluded map[int]bool) []PdfObject {
	mut out := []PdfObject{}
	mut seen := map[int]bool{}
	collect_pdf_support_refs(pdf_ref_ids(page_body), object_map, excluded, mut seen, mut out)
	return out
}

fn pdf_page_body_with_inherited_attrs(body string, object_map map[int]PdfObject) string {
	inherited := pdf_inherited_page_attrs(body, object_map)
	if inherited.len == 0 {
		return body
	}
	mut additions := []string{}
	for key in pdf_inherited_page_keys() {
		if _ := pdf_key_index(body, key) {
			continue
		}
		if value := inherited[key] {
			additions << '${key} ${value}'
		}
	}
	if additions.len == 0 {
		return body
	}
	clean := body.trim_space()
	if clean.starts_with('<<') {
		return '<< ${additions.join(' ')} ${clean[2..].trim_space()}'
	}
	return '${additions.join(' ')} ${body}'
}

fn pdf_inherited_page_attrs(body string, object_map map[int]PdfObject) map[string]string {
	mut inherited := map[string]string{}
	mut current_body := body
	mut seen := map[int]bool{}
	for {
		parent_id := pdf_ref_value(current_body, '/Parent') or { break }
		if parent_id in seen {
			break
		}
		parent := object_map[parent_id] or { break }
		seen[parent_id] = true
		for key in pdf_inherited_page_keys() {
			if key in inherited {
				continue
			}
			if value := pdf_value_for_key(parent.body, key) {
				inherited[key] = value
			}
		}
		current_body = parent.body
	}
	return inherited
}

fn pdf_inherited_page_keys() []string {
	return ['/Resources', '/MediaBox', '/CropBox', '/Rotate']
}

fn is_pdf_catalog_object(body string) bool {
	return pdf_name_value(body, '/Type', '/Catalog')
}

fn is_pdf_pages_object(body string) bool {
	return pdf_name_value(body, '/Type', '/Pages')
}

fn is_pdf_page_object(body string) bool {
	return pdf_name_value(body, '/Type', '/Page')
}

fn pdf_ref_value(body string, key string) ?int {
	start := pdf_key_index(body, key) or { return none }
	after_key := start + key.len
	value_start := skip_pdf_space(body, after_key)
	return pdf_reference_at(body, value_start)?.id
}

fn pdf_kids_refs(body string) []int {
	start := pdf_key_index(body, '/Kids') or { return []int{} }
	array_start := body[start..].index('[') or { return []int{} }
	absolute_start := start + array_start + 1
	array_end_rel := body[absolute_start..].index(']') or { return []int{} }
	array_body := body[absolute_start..absolute_start + array_end_rel]
	return pdf_ref_ids(array_body)
}

fn pdf_value_for_key(body string, key string) ?string {
	start := pdf_key_index(body, key) or { return none }
	value_start := skip_pdf_space(body, start + key.len)
	value_end := pdf_value_end(body, value_start)
	if value_end <= value_start {
		return none
	}
	return body[value_start..value_end].trim_space()
}

fn pdf_value_end(body string, start int) int {
	if start >= body.len {
		return start
	}
	if pdf_ref := pdf_reference_at(body, start) {
		return pdf_ref.end
	}
	if start + 1 < body.len && body[start] == `<` && body[start + 1] == `<` {
		return pdf_balanced_dict_end(body, start)
	}
	if body[start] == `[` {
		return pdf_balanced_array_end(body, start)
	}
	mut i := start
	for i < body.len && !is_pdf_delimiter(body[i]) {
		i++
	}
	return i
}

fn pdf_balanced_dict_end(body string, start int) int {
	mut depth := 0
	mut i := start
	for i + 1 < body.len {
		if body[i] == `<` && body[i + 1] == `<` {
			depth++
			i += 2
			continue
		}
		if body[i] == `>` && body[i + 1] == `>` {
			depth--
			i += 2
			if depth <= 0 {
				return i
			}
			continue
		}
		i++
	}
	return body.len
}

fn pdf_balanced_array_end(body string, start int) int {
	mut depth := 0
	mut i := start
	for i < body.len {
		if body[i] == `[` {
			depth++
		} else if body[i] == `]` {
			depth--
			if depth <= 0 {
				return i + 1
			}
		}
		i++
	}
	return body.len
}

fn pdf_key_index(body string, key string) ?int {
	mut offset := 0
	for offset < body.len {
		rel := body[offset..].index(key) or { return none }
		start := offset + rel
		after_key := start + key.len
		if start > 0 && is_pdf_name_char(body[start - 1]) {
			offset = after_key
			continue
		}
		if after_key < body.len && is_pdf_name_char(body[after_key]) {
			offset = after_key
			continue
		}
		return start
	}
	return none
}

fn imported_pdf_page_body(body string, remap map[int]int) string {
	clean := remove_pdf_parent_ref(remap_pdf_refs(body, remap)).trim_space()
	if clean.starts_with('<<') {
		return '<< /Parent 2 0 R ${clean[2..].trim_space()}'
	}
	return clean
}

fn remove_pdf_parent_ref(body string) string {
	start := pdf_key_index(body, '/Parent') or { return body }
	value_start := skip_pdf_space(body, start + '/Parent'.len)
	parent_ref := pdf_reference_at(body, value_start) or { return body }
	end := parent_ref.end
	return (body[..start] + body[end..]).replace('  ', ' ')
}

fn remap_pdf_object_body(body string, remap map[int]int) string {
	stream_at := pdf_stream_marker_index(body) or { return remap_pdf_refs(body, remap) }
	return remap_pdf_refs(body[..stream_at], remap) + body[stream_at..]
}

fn remap_pdf_refs(body string, remap map[int]int) string {
	mut out := []u8{cap: body.len}
	mut i := 0
	for i < body.len {
		ch := body[i]
		if pdf_ref := pdf_reference_at(body, i) {
			id := pdf_ref.id
			if new_id := remap[id] {
				out << '${new_id} 0 R'.bytes()
				i = pdf_ref.end
				continue
			}
		}
		out << ch
		i++
	}
	return out.bytestr()
}

struct PdfRef {
	id  int
	end int
}

fn collect_pdf_support_refs(refs []int, object_map map[int]PdfObject, excluded map[int]bool, mut seen map[int]bool, mut out []PdfObject) {
	for id in refs {
		if id in excluded || id in seen {
			continue
		}
		object := object_map[id] or { continue }
		seen[id] = true
		out << object
		collect_pdf_support_refs(pdf_ref_ids(object.body), object_map, excluded, mut seen, mut out)
	}
}

fn pdf_ref_ids(body string) []int {
	scan := pdf_reference_scan_body(body)
	mut out := []int{}
	mut i := 0
	for i < scan.len {
		if pdf_ref := pdf_reference_at(scan, i) {
			if pdf_ref.id !in out {
				out << pdf_ref.id
			}
			i = pdf_ref.end
			continue
		}
		i++
	}
	return out
}

fn pdf_reference_scan_body(body string) string {
	stream_at := pdf_stream_marker_index(body) or { return body }
	return body[..stream_at]
}

fn pdf_reference_at(body string, start int) ?PdfRef {
	if start >= body.len || !is_pdf_digit(body[start]) {
		return none
	}
	mut i := start
	for i < body.len && is_pdf_digit(body[i]) {
		i++
	}
	id := body[start..i].int()
	i = skip_pdf_space(body, i)
	if i >= body.len || !is_pdf_digit(body[i]) {
		return none
	}
	gen_start := i
	for i < body.len && is_pdf_digit(body[i]) {
		i++
	}
	if i <= gen_start {
		return none
	}
	i = skip_pdf_space(body, i)
	if i >= body.len || body[i] != `R` {
		return none
	}
	return PdfRef{
		id:  id
		end: i + 1
	}
}

fn pdf_name_value(body string, key string, value string) bool {
	mut offset := 0
	for offset < body.len {
		rel := body[offset..].index(key) or { return false }
		start := offset + rel
		after_key := start + key.len
		if after_key < body.len && is_pdf_name_char(body[after_key]) {
			offset = after_key
			continue
		}
		value_start := skip_pdf_space(body, after_key)
		value_end := value_start + value.len
		if value_end <= body.len && body[value_start..value_end] == value
			&& (value_end == body.len || !is_pdf_name_char(body[value_end])) {
			return true
		}
		offset = after_key
	}
	return false
}

fn pdf_stream_marker_index(body string) ?int {
	for marker in pdf_stream_markers() {
		if index := body.index(marker) {
			return index
		}
	}
	return none
}

fn pdf_stream_markers() []string {
	return ['\r\nstream\r\n', '\r\nstream\n', '\nstream\r\n', '\nstream\n', '\rstream\r',
		'\rstream\n', '\nstream\r']
}

fn skip_pdf_space(body string, start int) int {
	mut i := start
	for i < body.len && body[i] in [` `, `\t`, `\r`, `\n`, 0x0c, 0x00] {
		i++
	}
	return i
}

fn is_pdf_name_char(ch u8) bool {
	return (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
		|| (ch >= `0` && ch <= `9`) || ch in [`_`, `-`]
}

fn is_pdf_delimiter(ch u8) bool {
	return ch in [` `, `\t`, `\r`, `\n`, 0x0c, 0x00, `/`, `[`, `]`, `<`, `>`, `(`, `)`]
}

fn is_pdf_digit(ch u8) bool {
	return ch >= `0` && ch <= `9`
}

fn is_pdf_uint_text(value string) bool {
	if value == '' {
		return false
	}
	for ch in value.bytes() {
		if !is_pdf_digit(ch) {
			return false
		}
	}
	return true
}
