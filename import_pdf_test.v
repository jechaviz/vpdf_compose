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
