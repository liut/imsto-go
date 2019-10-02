package image

import (
	"image"
	"image/jpeg"
	"image/png"
	"io"

	"github.com/liut/jpegquality"
)

const (
	formatJPEG = "jpeg"
	formatPNG  = "png"
)

// Image ...
type Image struct {
	m image.Image
	*Attr
	Format string
}

// Open ...
func Open(rs io.ReadSeeker) (*Image, error) {
	m, format, err := image.Decode(rs)
	if err != nil {
		return nil, err
	}

	pt := m.Bounds().Max
	attr := NewAttr(uint(pt.X), uint(pt.Y), 0)
	attr.Ext = getExt(format)
	if format == formatJPEG {
		jr, err := jpegquality.New(rs)
		if err != nil {
			return nil, err
		}
		attr.Quality = Quality(jr.Quality())
	}
	return &Image{
		m:      m,
		Attr:   attr,
		Format: format,
	}, nil
}

// WriteOption ...
type WriteOption struct {
	Format   string
	StripAll bool
	Quality  Quality
}

// WriteTo ...
func (im *Image) WriteTo(w io.Writer, opt *WriteOption) error {
	if opt.Format == "" {
		opt.Format = im.Format
	}
	return WriteTo(w, im.m, opt)
}

// WriteTo ...
func WriteTo(w io.Writer, m image.Image, opt *WriteOption) error {
	switch opt.Format {
	case formatJPEG:
		return jpeg.Encode(w, m, &jpeg.Options{Quality: int(opt.Quality)})
	case formatPNG:
		return png.Encode(w, m)
	}
	return ErrorFormat
}
