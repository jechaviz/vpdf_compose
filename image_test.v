module vpdf_compose

import os
import stbi

fn test_image_page_embeds_xobject_and_draw_command() {
	root := os.join_path(os.temp_dir(), 'vpdf-compose-image-test-${os.getpid()}')
	path := os.join_path(root, 'image.png')
	defer {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all(root)!
	write_test_png(path, 4, 2)!
	mut doc := new_document()
	info := doc.add_image_page_from_path(path, ImagePageOptions{})!
	body := doc.render()
	assert info.width == 4
	assert info.height == 2
	assert body.starts_with('%PDF-1.4')
	assert body.contains('/Subtype /Image')
	assert body.contains('/Width 4')
	assert body.contains('/Height 2')
	assert body.contains('/Im0 Do')
	assert body.contains('/ASCIIHexDecode')
}

fn test_fit_to_page_changes_large_image_dimensions() {
	image := PdfImage{
		width:  1000
		height: 1000
		rgb:    []u8{len: 1000 * 1000 * 3}
	}
	fit := image_rect(PdfPage{
		kind:          'image'
		image:         image
		margin_points: 40
		fit_to_page:   true
	})
	original := image_rect(PdfPage{
		kind:          'image'
		image:         image
		margin_points: 40
		fit_to_page:   false
	})
	assert fit.width < original.width
	assert fit.height < original.height
}

fn write_test_png(path string, width int, height int) ! {
	mut pixels := []u8{len: width * height * 4}
	for y in 0 .. height {
		for x in 0 .. width {
			idx := (y * width + x) * 4
			pixels[idx] = u8(20 + x * 20)
			pixels[idx + 1] = u8(80 + y * 20)
			pixels[idx + 2] = 180
			pixels[idx + 3] = 255
		}
	}
	stbi.stbi_write_png(path, width, height, 4, pixels.data, width * 4)!
}
