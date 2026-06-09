module vpdf_compose

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

fn test_imports_pages_when_objects_start_after_carriage_return() {
	source := '%PDF-1.4\r274 0 obj\r<< /Type /Page /Parent 271 0 R /Resources << /Font << /TT2 277 0 R >> >> /Contents 279 0 R /MediaBox [ 0 0 612 792 ] >>\rendobj\r277 0 obj\r<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\rendobj\r279 0 obj\r<< /Length 26 >>\rstream\rBT (udhr page needle) Tj ET\rendstream\rendobj\r'
	mut doc := new_document()
	imported := doc.add_pdf_pages_from_bytes(source.bytes())!
	assert imported == 1
	body := doc.render()
	assert body.contains('udhr page needle')
	assert body.contains('/Count 1')
}
