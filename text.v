module vpdf_compose

pub fn (mut doc Document) add_text_page(lines []TextLine, options TextPageOptions) {
	doc.pages << PdfPage{
		kind:          'text'
		lines:         lines.clone()
		margin_points: normalized_margin(options.margin_points)
	}
}

fn text_page_stream(page PdfPage) string {
	margin := normalized_margin(page.margin_points)
	x := margin
	mut y := a4_height_points - margin
	mut out := ''
	for line in page.lines {
		size := normalized_font_size(line.size)
		font := if line.bold { 'F2' } else { 'F1' }
		out += 'BT /${font} ${size} Tf ${x} ${y} Td (${pdf_escape(line.text)}) Tj ET\n'
		y -= line_height(size)
	}
	return out
}

fn normalized_margin(value int) int {
	if value <= 0 {
		return 28
	}
	if value > 220 {
		return 220
	}
	return value
}

fn normalized_font_size(value int) int {
	if value <= 0 {
		return 12
	}
	if value > 72 {
		return 72
	}
	return value
}

fn line_height(size int) int {
	if size >= 16 {
		return 20
	}
	if size >= 14 {
		return 18
	}
	return 15
}

fn pdf_text_safe(value string) string {
	mut out := []u8{}
	for ch in value.bytes() {
		if ch == `\n` || ch == `\r` || ch == `\t` {
			out << ` `
		} else if ch >= 32 && ch <= 126 {
			out << ch
		} else {
			out << `?`
		}
	}
	return out.bytestr().trim_space()
}

fn pdf_escape(value string) string {
	clean := pdf_text_safe(value)
	mut out := ''
	for ch in clean.bytes() {
		if ch == `\\` || ch == `(` || ch == `)` {
			out += '\\'
		}
		out += ch.ascii_str()
	}
	return out
}
