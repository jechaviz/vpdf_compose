module vpdf_compose

pub fn new_document() Document {
	return Document{}
}

pub fn (doc Document) page_count() int {
	return doc.pages.len
}

pub fn (doc Document) render() string {
	pages := if doc.pages.len == 0 {
		[
			PdfPage{
				kind:          'text'
				lines:         [
					TextLine{
						text: 'Empty PDF document'
						size: 14
						bold: true
					},
				]
				margin_points: 28
			},
		]
	} else {
		doc.pages
	}
	mut objects := [
		PdfObject{
			id:   1
			body: '<< /Type /Catalog /Pages 2 0 R >>'
		},
		PdfObject{
			id:   2
			body: ''
		},
		PdfObject{
			id:   3
			body: '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'
		},
		PdfObject{
			id:   4
			body: '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>'
		},
	]
	mut kids := []string{}
	mut next_id := 5
	for page in pages {
		if page.kind == 'raw_pdf' {
			page_id := next_id
			next_id++
			kids << '${page_id} 0 R'
			mut remap := map[int]int{}
			remap[page.raw_page_id] = page_id
			for object in page.raw_objects {
				remap[object.id] = next_id
				next_id++
			}
			objects << PdfObject{
				id:   page_id
				body: imported_pdf_page_body(page.raw_page_body, remap)
			}
			for object in page.raw_objects {
				objects << PdfObject{
					id:   remap[object.id]
					body: remap_pdf_object_body(object.body, remap)
				}
			}
			continue
		}
		page_id := next_id
		content_id := next_id + 1
		next_id += 2
		kids << '${page_id} 0 R'
		match page.kind {
			'image' {
				image_id := next_id
				next_id++
				stream := image_page_stream(page, image_id)
				objects << PdfObject{
					id:   page_id
					body: page_object(content_id, image_id)
				}
				objects << stream_object(content_id, stream)
				objects << image_object(image_id, page.image)
			}
			else {
				stream := text_page_stream(page)
				objects << PdfObject{
					id:   page_id
					body: text_page_object(content_id)
				}
				objects << stream_object(content_id, stream)
			}
		}
	}
	objects[1] = PdfObject{
		id:   2
		body: '<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${kids.len} >>'
	}
	return objects_to_pdf(objects)
}

fn text_page_object(content_id int) string {
	return '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${a4_width_points} ${a4_height_points}] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents ${content_id} 0 R >>'
}

fn page_object(content_id int, image_id int) string {
	return '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${a4_width_points} ${a4_height_points}] /Resources << /XObject << /Im0 ${image_id} 0 R >> /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents ${content_id} 0 R >>'
}

fn stream_object(id int, stream string) PdfObject {
	return PdfObject{
		id:   id
		body: '<< /Length ${stream.len} >>\nstream\n${stream}\nendstream'
	}
}

fn objects_to_pdf(objects []PdfObject) string {
	max_id := max_object_id(objects)
	mut body := []u8{cap: estimated_pdf_size(objects)}
	body << '%PDF-1.4\n'.bytes()
	mut offsets := []int{len: max_id + 1}
	for object in objects {
		offsets[object.id] = body.len
		body << '${object.id} 0 obj\n'.bytes()
		body << object.body.bytes()
		body << '\nendobj\n'.bytes()
	}
	startxref := body.len
	body << 'xref\n0 ${max_id + 1}\n'.bytes()
	body << '0000000000 65535 f \n'.bytes()
	for id in 1 .. max_id + 1 {
		body << '${zero_pad(offsets[id], 10)} 00000 n \n'.bytes()
	}
	body << 'trailer\n<< /Size ${max_id + 1} /Root 1 0 R >>\n'.bytes()
	body << 'startxref\n${startxref}\n%%EOF\n'.bytes()
	return body.bytestr()
}

fn estimated_pdf_size(objects []PdfObject) int {
	mut size := 1024
	for object in objects {
		size += object.body.len + 48
	}
	return size
}

fn max_object_id(objects []PdfObject) int {
	mut max_id := 0
	for object in objects {
		if object.id > max_id {
			max_id = object.id
		}
	}
	return max_id
}

fn zero_pad(value int, width int) string {
	mut out := value.str()
	for out.len < width {
		out = '0${out}'
	}
	return out
}
