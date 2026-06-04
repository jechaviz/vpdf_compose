module vpdf_compose

pub const a4_width_points = 595
pub const a4_height_points = 842

pub struct TextLine {
pub:
	text string
	size int = 12
	bold bool
}

pub struct TextPageOptions {
pub:
	margin_points int = 28
}

pub struct ImagePageOptions {
pub:
	margin_points int  = 28
	fit_to_page   bool = true
}

pub struct ImageInfo {
pub:
	width  int
	height int
}

struct PdfPage {
	kind          string
	lines         []TextLine
	image         PdfImage
	margin_points int
	fit_to_page   bool
}

struct PdfImage {
	width  int
	height int
	rgb    []u8
}

pub struct Document {
mut:
	pages []PdfPage
}

struct PdfObject {
	id   int
	body string
}
