module vpdf_compose

pub fn (mut doc Document) add_pdf_pages_from_bytes(bytes []u8) !int {
	source := bytes.bytestr()
	objects := parse_pdf_objects(source)
	if objects.len == 0 {
		return error('pdf objects not found')
	}
	support_objects := pdf_support_objects(objects)
	mut imported := 0
	for object in objects {
		if !is_pdf_page_object(object.body) {
			continue
		}
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

fn parse_pdf_objects(source string) []PdfObject {
	mut out := []PdfObject{}
	mut offset := 0
	for offset < source.len {
		rel := source[offset..].index(' obj') or { break }
		marker := offset + rel
		line_start := source[..marker].last_index('\n') or { -1 } + 1
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

fn pdf_support_objects(objects []PdfObject) []PdfObject {
	mut out := []PdfObject{}
	for object in objects {
		if is_pdf_catalog_object(object.body) || is_pdf_pages_object(object.body)
			|| is_pdf_page_object(object.body) {
			continue
		}
		out << object
	}
	return out
}

fn is_pdf_catalog_object(body string) bool {
	return body.contains('/Type /Catalog')
}

fn is_pdf_pages_object(body string) bool {
	return body.contains('/Type /Pages')
}

fn is_pdf_page_object(body string) bool {
	return body.contains('/Type /Page') && !body.contains('/Type /Pages')
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
	stream_at := body.index('\nstream\n') or { return remap_pdf_refs(body, remap) }
	return remap_pdf_refs(body[..stream_at], remap) + body[stream_at..]
}

fn remap_pdf_refs(body string, remap map[int]int) string {
	mut out := []u8{cap: body.len}
	mut i := 0
	for i < body.len {
		ch := body[i]
		if !is_pdf_digit(ch) {
			out << ch
			i++
			continue
		}
		start := i
		for i < body.len && is_pdf_digit(body[i]) {
			i++
		}
		id := body[start..i].int()
		if i + 4 <= body.len && body[i..i + 4] == ' 0 R' {
			if new_id := remap[id] {
				out << '${new_id} 0 R'.bytes()
				i += 4
				continue
			}
		}
		out << body[start..i].bytes()
	}
	return out.bytestr()
}

fn is_pdf_digit(ch u8) bool {
	return ch >= `0` && ch <= `9`
}
