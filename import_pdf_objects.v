module vpdf_compose

fn parse_pdf_objects(source string) []PdfObject {
	mut out := []PdfObject{}
	mut offset := 0
	for offset < source.len {
		rel := source[offset..].index(' obj') or { break }
		marker := offset + rel
		line_start := pdf_object_header_start(source, marker)
		header := source[line_start..marker].trim_space()
		parts := header.fields()
		if parts.len < 2 || !is_pdf_uint_text(parts[0]) || !is_pdf_uint_text(parts[1]) {
			offset = marker + 4
			continue
		}
		id := parts[0].int()
		body_start := marker + ' obj'.len
		body_end := pdf_object_body_end(source, body_start) or { break }
		body := source[body_start..body_end].trim(' \r\n')
		if id > 0 {
			out << PdfObject{
				id:   id
				body: body
			}
		}
		offset = body_end + 'endobj'.len
	}
	return out
}

fn pdf_object_body_end(source string, body_start int) ?int {
	mut scan := body_start
	for scan < source.len {
		end_rel := source[scan..].index('endobj') or { return none }
		end_at := scan + end_rel
		stream_marker := pdf_next_stream_marker_before(source, scan, end_at) or { return end_at }
		if stream_length := pdf_stream_length(source, source[body_start..stream_marker.start]) {
			if stream_end := pdf_stream_end_from_direct_length(source, stream_marker.end,
				stream_length)
			{
				scan = stream_end
				continue
			}
		}
		stream_end := source[stream_marker.end..].index('endstream') or { return end_at }
		scan = stream_marker.end + stream_end + 'endstream'.len
	}
	return none
}

fn pdf_stream_length(source string, object_header string) ?int {
	if length := pdf_direct_stream_length(object_header) {
		return length
	}
	return pdf_indirect_stream_length(source, object_header)
}

fn pdf_direct_stream_length(object_header string) ?int {
	start := pdf_key_index(object_header, '/Length') or { return none }
	value_start := skip_pdf_space(object_header, start + '/Length'.len)
	mut value_end := value_start
	for value_end < object_header.len && is_pdf_digit(object_header[value_end]) {
		value_end++
	}
	if value_end <= value_start {
		return none
	}
	after_value := skip_pdf_space(object_header, value_end)
	if after_value < object_header.len && is_pdf_digit(object_header[after_value]) {
		return none
	}
	return object_header[value_start..value_end].int()
}

fn pdf_indirect_stream_length(source string, object_header string) ?int {
	ref := pdf_length_ref(object_header) or { return none }
	body := pdf_plain_object_body(source, ref.id, ref.generation) or { return none }
	return pdf_plain_uint_body(body)
}

struct PdfLengthRef {
	id         int
	generation int
}

fn pdf_length_ref(object_header string) ?PdfLengthRef {
	start := pdf_key_index(object_header, '/Length') or { return none }
	mut i := skip_pdf_space(object_header, start + '/Length'.len)
	id_start := i
	for i < object_header.len && is_pdf_digit(object_header[i]) {
		i++
	}
	if i <= id_start {
		return none
	}
	id := object_header[id_start..i].int()
	i = skip_pdf_space(object_header, i)
	gen_start := i
	for i < object_header.len && is_pdf_digit(object_header[i]) {
		i++
	}
	if i <= gen_start {
		return none
	}
	generation := object_header[gen_start..i].int()
	i = skip_pdf_space(object_header, i)
	if i >= object_header.len || object_header[i] != `R` {
		return none
	}
	return PdfLengthRef{
		id:         id
		generation: generation
	}
}

fn pdf_plain_object_body(source string, id int, generation int) ?string {
	mut offset := 0
	for offset < source.len {
		rel := source[offset..].index(' obj') or { return none }
		marker := offset + rel
		line_start := pdf_object_header_start(source, marker)
		header := source[line_start..marker].trim_space()
		parts := header.fields()
		if parts.len >= 2 && is_pdf_uint_text(parts[0]) && is_pdf_uint_text(parts[1])
			&& parts[0].int() == id && parts[1].int() == generation {
			body_start := marker + ' obj'.len
			end_rel := source[body_start..].index('endobj') or { return none }
			return source[body_start..body_start + end_rel].trim_space()
		}
		offset = marker + 4
	}
	return none
}

fn pdf_plain_uint_body(body string) ?int {
	clean := body.trim_space()
	if clean == '' || !clean.bytes().all(it >= `0` && it <= `9`) {
		return none
	}
	return clean.int()
}

fn pdf_stream_end_from_direct_length(source string, stream_data_start int, length int) ?int {
	if length < 0 {
		return none
	}
	data_end := stream_data_start + length
	if data_end > source.len {
		return none
	}
	endstream_start := skip_pdf_space(source, data_end)
	endstream_end := endstream_start + 'endstream'.len
	if endstream_end > source.len || source[endstream_start..endstream_end] != 'endstream' {
		return none
	}
	return endstream_end
}

struct PdfMarker {
	start int
	end   int
}

fn pdf_next_stream_marker_before(source string, start int, before int) ?PdfMarker {
	mut found := PdfMarker{
		start: source.len
		end:   source.len
	}
	for marker in pdf_stream_markers() {
		rel := source[start..].index(marker) or { continue }
		marker_start := start + rel
		if marker_start >= before || marker_start >= found.start {
			continue
		}
		found = PdfMarker{
			start: marker_start
			end:   marker_start + marker.len
		}
	}
	if found.start == source.len {
		return none
	}
	return found
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
