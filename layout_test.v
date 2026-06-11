module vpdf_compose

fn test_layout_wraps_and_sanitizes_text_lines() {
	wrapped := wrap_text_line(TextLine{
		text: 'alpha beta gamma delta'
		size: 14
		bold: true
	}, 10)
	assert wrapped.len == 3
	assert wrapped[0].text == 'alpha beta'
	assert wrapped[1].text == 'gamma'
	assert wrapped[2].text == 'delta'
	assert wrapped[0].size == 14
	assert wrapped[0].bold

	long := wrap_text_line(TextLine{
		text: 'abcdefghijkl'
	}, 5)
	assert long.map(it.text) == ['abcde', 'fghij', 'kl']
	assert safe_text(' A\tB\nC' + [u8(0xff)].bytestr()) == 'A B C?'
}

fn test_layout_paginates_with_margin_bounds() {
	mut lines := []TextLine{}
	for i in 0 .. 60 {
		lines << TextLine{
			text: 'line ${i}'
		}
	}
	margin := text_margin_points_from_mm(10)
	pages := text_pages_from_lines(lines, TextLayoutOptions{
		margin_points: margin
	})
	assert margin == 28
	assert pages.len == 2
	assert pages[0].lines.len == text_max_lines(margin)
	assert pages[1].lines.len == 11
	assert text_margin_points_from_mm(1) == 20
	assert text_margin_points_from_mm(200) == 220
	assert text_max_chars(16) == 54
	assert text_max_chars(14) == 64
	assert text_max_chars(12) == 88
}

fn test_add_text_pages_appends_pages_to_document() {
	mut doc := new_document()
	pages := [
		TextPage{
			lines: [
				TextLine{
					text: 'page one'
				},
			]
		},
		TextPage{
			lines: [
				TextLine{
					text: 'page two'
				},
			]
		},
	]
	add_text_pages(mut doc, pages, TextPageOptions{
		margin_points: 28
	})
	assert doc.page_count() == 2
	body := doc.render()
	assert body.contains('page one')
	assert body.contains('page two')
}
