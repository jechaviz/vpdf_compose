module vpdf_compose

fn test_text_document_has_valid_xref() {
	mut doc := new_document()
	doc.add_text_page([
		TextLine{
			text: 'Hello PDF'
			size: 14
			bold: true
		},
	], TextPageOptions{})
	body := doc.render()
	assert body.starts_with('%PDF-1.4')
	assert body.contains('Hello PDF')
	assert body.contains('xref')
	startxref := body.all_after_last('startxref\n').all_before('\n').int()
	assert startxref > 0
	assert body[startxref..].starts_with('xref')
}
