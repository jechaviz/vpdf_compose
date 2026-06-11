module vpdf_compose

import compress.deflate

fn expand_pdf_object_streams(objects []PdfObject) []PdfObject {
	mut expanded := objects.clone()
	mut existing := map[int]bool{}
	for object in objects {
		existing[object.id] = true
	}
	for object in objects {
		for embedded in pdf_object_stream_objects(object) {
			if embedded.id in existing {
				continue
			}
			existing[embedded.id] = true
			expanded << embedded
		}
	}
	return expanded
}

fn pdf_object_stream_objects(object PdfObject) []PdfObject {
	if !pdf_object_stream_dictionary(object.body).contains('/ObjStm') {
		return []PdfObject{}
	}
	first := pdf_object_stream_int_value(object.body, '/First')
	count := pdf_object_stream_int_value(object.body, '/N')
	if first < 0 || count <= 0 {
		return []PdfObject{}
	}
	raw := pdf_object_stream_body_bytes(object.body) or { return []PdfObject{} }
	decoded := pdf_object_stream_decoded_bytes(object.body, raw) or { return []PdfObject{} }
	if first < 0 || first >= decoded.len {
		return []PdfObject{}
	}
	header := decoded[..first].bytestr()
	object_data := decoded[first..].bytestr()
	pairs := pdf_object_stream_pairs(header, count)
	mut out := []PdfObject{}
	for i, pair in pairs {
		start := pair.offset
		end := if i + 1 < pairs.len { pairs[i + 1].offset } else { object_data.len }
		if start < 0 || start >= object_data.len || end <= start || end > object_data.len {
			continue
		}
		out << PdfObject{
			id:   pair.id
			body: object_data[start..end].trim_space()
		}
	}
	return out
}

fn pdf_object_stream_decoded_bytes(body string, raw []u8) ?[]u8 {
	if pdf_object_stream_has_flate(body) {
		return deflate.decompress(raw) or { return none }
	}
	return raw
}

struct PdfObjectStreamPair {
	id     int
	offset int
}

fn pdf_object_stream_pairs(header string, count int) []PdfObjectStreamPair {
	tokens := header.fields()
	mut pairs := []PdfObjectStreamPair{}
	mut i := 0
	for i + 1 < tokens.len && pairs.len < count {
		id := tokens[i].int()
		offset := tokens[i + 1].int()
		if id > 0 && offset >= 0 {
			pairs << PdfObjectStreamPair{
				id:     id
				offset: offset
			}
		}
		i += 2
	}
	return pairs
}

fn pdf_object_stream_dictionary(body string) string {
	stream_start := pdf_object_stream_body_start(body) or { return body }
	return body[..stream_start]
}

fn pdf_object_stream_has_flate(body string) bool {
	dictionary := pdf_object_stream_dictionary(body)
	return dictionary.contains('/FlateDecode') || dictionary.contains('/Fl')
}

fn pdf_object_stream_body_bytes(body string) ?[]u8 {
	start := pdf_object_stream_body_start(body)?
	length := pdf_object_stream_int_value(body, '/Length')
	if length >= 0 && start + length <= body.len {
		return body[start..start + length].bytes()
	}
	end_rel := body[start..].index('endstream') or { return none }
	mut end := start + end_rel
	for end > start && body[end - 1] in [`\n`, `\r`] {
		end--
	}
	return body[start..end].bytes()
}

fn pdf_object_stream_body_start(body string) ?int {
	for marker in pdf_stream_markers() {
		if index := body.index(marker) {
			return index + marker.len
		}
	}
	return none
}

fn pdf_object_stream_int_value(body string, key string) int {
	start := pdf_key_index(body, key) or { return -1 }
	mut i := skip_pdf_space(body, start + key.len)
	mut value := 0
	mut has_digits := false
	for i < body.len && is_pdf_digit(body[i]) {
		has_digits = true
		value = value * 10 + int(body[i] - `0`)
		i++
	}
	return if has_digits { value } else { -1 }
}
