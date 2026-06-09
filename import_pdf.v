module vpdf_compose

pub fn (mut doc Document) add_pdf_pages_from_bytes(bytes []u8) !int {
	source := bytes.bytestr()
	objects := parse_pdf_objects(source)
	if objects.len == 0 {
		return error('pdf objects not found')
	}
	object_map := pdf_object_map(objects)
	excluded := pdf_import_excluded_objects(objects)
	mut imported := 0
	for object in ordered_pdf_page_objects(objects, object_map) {
		support_objects := pdf_page_support_objects(object.body, object_map, excluded)
		doc.pages << PdfPage{
			kind:          'raw_pdf'
			raw_page_id:   object.id
			raw_page_body: object.body
			raw_objects:   support_objects.clone()
		}
		imported++
	}
	if imported == 0 {
		return error('pdf pages not found')
	}
	return imported
}

fn ordered_pdf_page_objects(objects []PdfObject, object_map map[int]PdfObject) []PdfObject {
	ids := pdf_page_tree_order(objects, object_map)
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

fn pdf_page_tree_order(objects []PdfObject, object_map map[int]PdfObject) []int {
	catalog := pdf_catalog_object(objects) or { return []int{} }
	root_pages_id := pdf_ref_value(catalog.body, '/Pages') or { return []int{} }
	mut seen := map[int]bool{}
	return pdf_collect_page_tree_ids(root_pages_id, object_map, mut seen)
}

fn pdf_catalog_object(objects []PdfObject) ?PdfObject {
	for object in objects {
		if is_pdf_catalog_object(object.body) {
			return object
		}
	}
	return none
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

fn parse_pdf_objects(source string) []PdfObject {
	mut out := []PdfObject{}
	mut offset := 0
	for offset < source.len {
		rel := source[offset..].index(' obj') or { break }
		marker := offset + rel
		line_start := pdf_object_header_start(source, marker)
		header := source[line_start..marker].trim_space()
		parts := header.split(' ')
		if parts.len < 2 || parts[1] != '0' {
			offset = marker + 4
			continue
		}
		id := parts[0].int()
		body_start := marker + ' obj'.len
		end_rel := source[body_start..].index('endobj') or { break }
		body := source[body_start..body_start + end_rel].trim(' \r\n')
		if id > 0 {
			out << PdfObject{
				id:   id
				body: body
			}
		}
		offset = body_start + end_rel + 'endobj'.len
	}
	return out
}

fn pdf_object_header_start(source string, marker int) int {
	mut i := marker - 1
	for i >= 0 {
		if source[i] == `\n` || source[i] == `\r` {
			return i + 1
		}
		i--
	}
	return 0
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
	start := body.index('/Parent ') or { return body }
	after_start := start + '/Parent '.len
	after := body[after_start..]
	end_rel := after.index(' R') or { return body }
	end := after_start + end_rel + 2
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
	if body[gen_start..i].int() != 0 {
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
	for marker in ['\nstream\n', '\r\nstream\r\n', '\nstream\r\n', '\r\nstream\n'] {
		if index := body.index(marker) {
			return index
		}
	}
	return none
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

fn is_pdf_digit(ch u8) bool {
	return ch >= `0` && ch <= `9`
}
