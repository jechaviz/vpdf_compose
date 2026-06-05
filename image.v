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

pub fn (mut doc Document) add_jpeg_page_from_bytes(bytes []u8, options ImagePageOptions) !ImageInfo {
	info := parse_jpeg_info(bytes)!
	image := PdfImage{
		width:       info.width
		height:      info.height
		encoded:     bytes.clone()
		filter:      '/DCTDecode'
		color_space: if info.components == 1 { '/DeviceGray' } else { '/DeviceRGB' }
	}
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
		width:       img.width
		height:      img.height
		rgb:         rgb
		color_space: '/DeviceRGB'
	}
}

fn image_page_stream(page PdfPage, _image_id int) string {
	rect := image_rect(page)
	return 'q\n${rect.width} 0 0 ${rect.height} ${rect.x} ${rect.y} cm\n/Im0 Do\nQ'
}

fn image_object(id int, image PdfImage) PdfObject {
	if image.filter != '' {
		stream := image.encoded.bytestr()
		return PdfObject{
			id:   id
			body: '<< /Type /XObject /Subtype /Image /Width ${image.width} /Height ${image.height} /ColorSpace ${image.color_space} /BitsPerComponent 8 /Filter ${image.filter} /Length ${stream.len} >>\nstream\n${stream}\nendstream'
		}
	}
	stream := ascii_hex(image.rgb)
	return PdfObject{
		id:   id
		body: '<< /Type /XObject /Subtype /Image /Width ${image.width} /Height ${image.height} /ColorSpace ${image.color_space} /BitsPerComponent 8 /Filter /ASCIIHexDecode /Length ${stream.len} >>\nstream\n${stream}\nendstream'
	}
}

struct JpegInfo {
	width      int
	height     int
	components int
}

fn parse_jpeg_info(bytes []u8) !JpegInfo {
	if bytes.len < 4 || bytes[0] != 0xff || bytes[1] != 0xd8 {
		return error('invalid jpeg')
	}
	mut i := 2
	for i + 3 < bytes.len {
		for i < bytes.len && bytes[i] == 0xff {
			i++
		}
		if i >= bytes.len {
			break
		}
		marker := bytes[i]
		i++
		if marker == 0xd8 || marker == 0xd9 {
			continue
		}
		if i + 2 > bytes.len {
			break
		}
		segment_len := int(bytes[i]) * 256 + int(bytes[i + 1])
		if segment_len < 2 || i + segment_len > bytes.len {
			return error('invalid jpeg segment')
		}
		if is_jpeg_sof_marker(marker) {
			if segment_len < 8 {
				return error('invalid jpeg frame')
			}
			height := int(bytes[i + 3]) * 256 + int(bytes[i + 4])
			width := int(bytes[i + 5]) * 256 + int(bytes[i + 6])
			components := int(bytes[i + 7])
			if width <= 0 || height <= 0 {
				return error('invalid jpeg dimensions')
			}
			return JpegInfo{
				width:      width
				height:     height
				components: components
			}
		}
		if marker == 0xda {
			break
		}
		i += segment_len
	}
	return error('jpeg dimensions not found')
}

fn is_jpeg_sof_marker(marker u8) bool {
	return marker in [u8(0xc0), 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce,
		0xcf]
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
