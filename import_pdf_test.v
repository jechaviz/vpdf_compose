module vpdf_compose

import compress.deflate

fn test_imports_pages_from_rendered_pdf() {
	mut source := new_document()
	source.add_text_page([
		TextLine{
			text: 'imported page needle'
		},
	], TextPageOptions{})
	mut merged := new_document()
	imported := merged.add_pdf_pages_from_bytes(source.render().bytes())!
	assert imported == 1
	merged.add_text_page([
		TextLine{
			text: 'native page after import'
		},
	], TextPageOptions{})
	body := merged.render()
	assert body.contains('/Count 2')
	assert body.contains('imported page needle')
	assert body.contains('native page after import')
	startxref := body.all_after_last('startxref\n').all_before('\n').int()
	assert startxref > 0
	assert body[startxref..].starts_with('xref')
}

fn test_imports_referenced_objects_without_copying_unrelated_pdf_objects() {
	source := '%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources 7 0 R /Contents 5 0 R >>\nendobj\n4 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources 7 0 R /Contents 6 0 R >>\nendobj\n5 0 obj\n<< /Length 30 >>\nstream\nBT (real pdf page one) Tj ET\nendstream\nendobj\n6 0 obj\n<< /Length 30 >>\r\nstream\r\nBT (real pdf page two) Tj ET\r\nendstream\r\nendobj\n7 0 obj\n<< /Font << /F1 8 0 R >> >>\nendobj\n8 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n9 0 obj\n<< /Length 17 >>\nstream\nunrelated needle\nendstream\nendobj\nxref\n0 10\n0000000000 65535 f \ntrailer\n<< /Root 1 0 R /Size 10 >>\nstartxref\n0\n%%EOF\n'
	mut doc := new_document()
	imported := doc.add_pdf_pages_from_bytes(source.bytes())!
	assert imported == 2
	body := doc.render()
	assert body.contains('/Count 2')
	assert body.contains('real pdf page one')
	assert body.contains('real pdf page two')
	assert body.contains('/BaseFont /Helvetica')
	assert !body.contains('unrelated needle')
	startxref := body.all_after_last('startxref\n').all_before('\n').int()
	assert startxref > 0
	assert body[startxref..].starts_with('xref')
}

fn test_imports_pages_in_page_tree_kids_order() {
	source := '%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [4 0 R 3 0 R] /Count 2 >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << >> /Contents 5 0 R >>\nendobj\n4 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << >> /Contents 6 0 R >>\nendobj\n5 0 obj\n<< /Length 30 >>\nstream\nBT (logical page two) Tj ET\nendstream\nendobj\n6 0 obj\n<< /Length 30 >>\nstream\nBT (logical page one) Tj ET\nendstream\nendobj\ntrailer\n<< /Root 1 0 R /Size 7 >>\nstartxref\n0\n%%EOF\n'
	mut doc := new_document()
	imported := doc.add_pdf_pages_from_bytes(source.bytes())!
	body := doc.render()
	assert imported == 2
	page_one := body.index('logical page one') or { -1 }
	page_two := body.index('logical page two') or { -1 }
	assert page_one >= 0
	assert page_two >= 0
	assert page_one < page_two
}

fn test_imports_pages_when_objects_start_after_carriage_return() {
	source := '%PDF-1.4\r274 0 obj\r<< /Type /Page /Parent 271 0 R /Resources << /Font << /TT2 277 0 R >> >> /Contents 279 0 R /MediaBox [ 0 0 612 792 ] >>\rendobj\r277 0 obj\r<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\rendobj\r279 0 obj\r<< /Length 26 >>\rstream\rBT (udhr page needle) Tj ET\rendstream\rendobj\r'
	mut doc := new_document()
	imported := doc.add_pdf_pages_from_bytes(source.bytes())!
	assert imported == 1
	body := doc.render()
	assert body.contains('udhr page needle')
	assert body.contains('/Count 1')
}

fn test_imports_nonzero_generation_content_reference() {
	source := '%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> /Contents 5 2 R >>\nendobj\n5 2 obj\n<< /Length 34 >>\nstream\nBT (nonzero generation page) Tj ET\nendstream\nendobj\ntrailer\n<< /Root 1 0 R /Size 6 >>\nstartxref\n0\n%%EOF\n'
	mut doc := new_document()
	imported := doc.add_pdf_pages_from_bytes(source.bytes())!
	body := doc.render()
	assert imported == 1
	assert body.contains('nonzero generation page')
	assert !body.contains('/Contents 5 2 R')
}

fn test_imports_page_tree_inherited_page_attributes() {
	source := '%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 /Resources 7 0 R /MediaBox [0 0 300 400] /CropBox [10 20 290 380] /Rotate 90 >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 5 0 R >>\nendobj\n5 0 obj\n<< /Length 30 >>\nstream\nBT (inherited attr needle) Tj ET\nendstream\nendobj\n7 0 obj\n<< /Font << /F1 8 0 R >> >>\nendobj\n8 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\ntrailer\n<< /Root 1 0 R /Size 9 >>\nstartxref\n0\n%%EOF\n'
	mut doc := new_document()
	imported := doc.add_pdf_pages_from_bytes(source.bytes())!
	body := doc.render()
	assert imported == 1
	assert body.contains('inherited attr needle')
	assert body.contains('/MediaBox [0 0 300 400]')
	assert body.contains('/CropBox [10 20 290 380]')
	assert body.contains('/Rotate 90')
	assert body.contains('/BaseFont /Helvetica')
}

fn test_imported_page_attributes_override_page_tree_inheritance() {
	source := '%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 /Resources 7 0 R /MediaBox [0 0 300 400] /CropBox [10 20 290 380] /Rotate 90 >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /Resources 9 0 R /MediaBox [0 0 500 600] /Rotate 180 /Contents 5 0 R >>\nendobj\n5 0 obj\n<< /Length 30 >>\nstream\nBT (override attr needle) Tj ET\nendstream\nendobj\n7 0 obj\n<< /Font << /Old 8 0 R >> >>\nendobj\n8 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>\nendobj\n9 0 obj\n<< /Font << /F1 10 0 R >> >>\nendobj\n10 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\ntrailer\n<< /Root 1 0 R /Size 11 >>\nstartxref\n0\n%%EOF\n'
	mut doc := new_document()
	imported := doc.add_pdf_pages_from_bytes(source.bytes())!
	body := doc.render()
	assert imported == 1
	assert body.contains('override attr needle')
	assert body.contains('/MediaBox [0 0 500 600]')
	assert body.contains('/CropBox [10 20 290 380]')
	assert body.contains('/Rotate 180')
	assert body.contains('/BaseFont /Helvetica')
	assert !body.contains('/BaseFont /Courier')
}

fn test_imports_page_object_from_flate_object_stream() {
	page := '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources 8 0 R /Contents 6 0 R >>'
	resources := '<< /Font << /F1 9 0 R >> >>'
	header := '5 0 8 ${page.len} '
	object_stream := header + page + resources
	compressed := deflate.compress_zlib(object_stream.bytes())!
	mut source :=
		'%PDF-1.5\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [5 0 R] /Count 1 >>\nendobj\n6 0 obj\n<< /Length 29 >>\nstream\nBT (object stream page) Tj ET\nendstream\nendobj\n7 0 obj\n<< /Type /ObjStm /N 2 /First ${header.len} /Length ${compressed.len} /Filter /FlateDecode >>\nstream\n'.bytes()
	append_import_pdf_test_bytes(mut source, compressed)
	append_import_pdf_test_bytes(mut source,
		'\nendstream\nendobj\n9 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\ntrailer\n<< /Root 1 0 R /Size 10 >>\nstartxref\n0\n%%EOF\n'.bytes())
	mut doc := new_document()
	imported := doc.add_pdf_pages_from_bytes(source)!
	body := doc.render()
	assert imported == 1
	assert body.contains('object stream page')
	assert body.contains('/BaseFont /Helvetica')
}

fn append_import_pdf_test_bytes(mut dst []u8, src []u8) {
	for ch in src {
		dst << ch
	}
}
