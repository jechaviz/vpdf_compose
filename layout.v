module vpdf_compose

pub fn add_text_pages(mut doc Document, pages []TextPage, options TextPageOptions) {
	for page in pages {
		doc.add_text_page(page.lines, options)
	}
}

pub fn text_pages_from_lines(lines []TextLine, options TextLayoutOptions) []TextPage {
	mut pages := []TextPage{}
	mut current := []TextLine{}
	max_lines := text_max_lines(options.margin_points)
	for line in lines {
		for wrapped in wrap_text_line(line, text_max_chars(line.size)) {
			current << wrapped
			if current.len >= max_lines {
				pages << TextPage{
					lines: current.clone()
				}
				current = []TextLine{}
			}
		}
	}
	if current.len > 0 {
		pages << TextPage{
			lines: current.clone()
		}
	}
	return pages
}

pub fn wrap_text_line(line TextLine, max_chars int) []TextLine {
	clean := safe_text(line.text)
	if clean == '' {
		return [line]
	}
	mut out := []TextLine{}
	mut current := ''
	limit := if max_chars <= 0 { text_max_chars(line.size) } else { max_chars }
	for word in clean.split(' ') {
		if word == '' {
			continue
		}
		if current == '' {
			current = word
		} else if current.len + 1 + word.len <= limit {
			current += ' ${word}'
		} else {
			out << TextLine{
				text: current
				size: line.size
				bold: line.bold
			}
			current = word
		}
		for current.len > limit {
			out << TextLine{
				text: current[..limit]
				size: line.size
				bold: line.bold
			}
			current = current[limit..]
		}
	}
	if current != '' {
		out << TextLine{
			text: current
			size: line.size
			bold: line.bold
		}
	}
	if out.len == 0 {
		out << TextLine{
			text: ''
			size: line.size
			bold: line.bold
		}
	}
	return out
}

pub fn text_max_lines(margin_points int) int {
	margin := normalized_margin(margin_points)
	lines := (a4_height_points - margin * 2) / 16
	if lines < 8 {
		return 8
	}
	return lines
}

pub fn text_max_chars(size int) int {
	if size >= 16 {
		return 54
	}
	if size >= 14 {
		return 64
	}
	return 88
}

pub fn text_margin_points_from_mm(margin_mm int) int {
	mut margin := margin_mm
	if margin <= 0 {
		margin = 10
	}
	points := margin * 72 / 25
	if points < 20 {
		return 20
	}
	if points > 220 {
		return 220
	}
	return points
}

pub fn safe_text(value string) string {
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
