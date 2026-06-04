module vpdf_compose

import stbi

pub fn (mut doc Document) add_image_page_from_path(path string, options ImagePageOptions) !ImageInfo {
	image := load_pdf_image(path)!
	doc.pages << PdfPage{
		kind:          'image'
		image:         image
		margin_points: normalized_margin(options.margin_points)
		fit_to_page:   options.fit_to_page
	}
	return ImageInfo{
		width:  image.width
		height: image.height
	}
}

fn load_pdf_image(path string) !PdfImage {
	mut img := stbi.load(path, desired_channels: 3)!
	defer {
		img.free()
	}
	size := img.width * img.height * img.nr_channels
	rgb := unsafe { img.data.vbytes(size).clone() }
	return PdfImage{
		width:  img.width
		height: img.height
		rgb:    rgb
	}
}

fn image_page_stream(page PdfPage, _image_id int) string {
	rect := image_rect(page)
	return 'q\n${rect.width} 0 0 ${rect.height} ${rect.x} ${rect.y} cm\n/Im0 Do\nQ'
}

fn image_object(id int, image PdfImage) PdfObject {
	stream := ascii_hex(image.rgb)
	return PdfObject{
		id:   id
		body: '<< /Type /XObject /Subtype /Image /Width ${image.width} /Height ${image.height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode /Length ${stream.len} >>\nstream\n${stream}\nendstream'
	}
}

struct ImageRect {
	x      int
	y      int
	width  int
	height int
}

fn image_rect(page PdfPage) ImageRect {
	margin := normalized_margin(page.margin_points)
	area_width := a4_width_points - margin * 2
	area_height := a4_height_points - margin * 2
	mut scale := 1.0
	if page.fit_to_page {
		scale_w := f64(area_width) / f64(page.image.width)
		scale_h := f64(area_height) / f64(page.image.height)
		scale = if scale_w < scale_h { scale_w } else { scale_h }
		if scale > 1.0 {
			scale = 1.0
		}
	}
	width := int(f64(page.image.width) * scale)
	height := int(f64(page.image.height) * scale)
	return ImageRect{
		x:      (a4_width_points - width) / 2
		y:      (a4_height_points - height) / 2
		width:  if width <= 0 { 1 } else { width }
		height: if height <= 0 { 1 } else { height }
	}
}

fn ascii_hex(bytes []u8) string {
	hex := '0123456789ABCDEF'
	mut out := []u8{cap: bytes.len * 2 + 1}
	for b in bytes {
		out << hex[int(b >> 4)]
		out << hex[int(b & 15)]
	}
	out << `>`
	return out.bytestr()
}
