"""Writes the picture fixtures in pictures/ and the embedded picture in Drawing.lst.

Run from this folder with Pillow installed: python make-pictures.py
Each file is small and its pixels are known, so a test can name them.
"""
import base64
import struct
import zlib

from PIL import Image

out = 'pictures/'

# 2x2 RGBA: red opaque, green half transparent, blue clear, white opaque.
rgba = Image.new('RGBA', (2, 2))
rgba.putdata([(255, 0, 0, 255), (0, 255, 0, 128), (0, 0, 255, 0), (255, 255, 255, 255)])
rgba.save(out + 'rgba.png')

# 3x1 palette at one bit a pixel would hold only two colours; four bits: black, red, white,
# with black transparent.
pal = Image.new('P', (3, 1))
pal.putpalette([0, 0, 0, 255, 0, 0, 255, 255, 255])
pal.putdata([0, 1, 2])
pal.save(out + 'palette.png', bits=4, transparency=0)

# 2x1 sixteen-bit grey: 0x1234 and 0xFF00.
grey = Image.new('I;16', (2, 1))
grey.putdata([0x1234, 0xFF00])
grey.save(out + 'grey16.png')


def chunk(tag, data):
    return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)


def interlaced(path, w, h, pixel):
    """An Adam7-interlaced 8-bit RGB PNG, which Pillow cannot write."""
    passes = [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]
    raw = b''
    for x0, y0, dx, dy in passes:
        xs = list(range(x0, w, dx))
        for y in range(y0, h, dy):
            if xs:
                raw += b'\0' + b''.join(bytes(pixel(x, y)) for x in xs)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 1))
    png += chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
    open(path, 'wb').write(png)


interlaced(out + 'interlaced.png', 9, 9, lambda x, y: (x * 20, y * 20, 7))

# 3x2 bitmaps: top row red, green, blue; bottom row white, black, grey.
colours = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 255), (0, 0, 0), (128, 128, 128)]
bmp = Image.new('RGB', (3, 2))
bmp.putdata(colours)
bmp.save(out + 'rgb24.bmp')
bmp.convert('P', palette=Image.ADAPTIVE, colors=8).save(out + 'pal8.bmp')


def topdown(path):
    """A 24-bit bitmap stored top row first, as a negative height says."""
    rows = b''
    for y in range(2):
        row = b''.join(bytes((b, g, r)) for r, g, b in colours[y * 3:y * 3 + 3])
        rows += row + b'\0' * ((4 - len(row) % 4) % 4)
    header = struct.pack('<IiiHHIIiiII', 40, 3, -2, 1, 24, 0, len(rows), 2835, 2835, 0, 0)
    open(path, 'wb').write(b'BM' + struct.pack('<IHHI', 14 + len(header) + len(rows), 0, 0, 54) + header + rows)


topdown(out + 'topdown.bmp')

# TIFF: the same six colours by LZW at 150 dpi, grey by PackBits, as a palette, and rgba.png
# with its transparency, which List & Label lays over black.
bmp.save(out + 'rgb-lzw.tif', compression='tiff_lzw', dpi=(150, 150))
bmp.convert('L').save(out + 'grey-packbits.tif', compression='packbits')
bmp.convert('P', palette=Image.ADAPTIVE, colors=8).save(out + 'palette.tif')
rgba.save(out + 'rgba.tif')


def motorola(path):
    """The six colours big-endian, deflated, each sample stored as the difference from the one before."""
    raw = b''
    for y in range(2):
        row = [v for c in colours[y * 3:y * 3 + 3] for v in c]
        raw += bytes([row[i] if i < 3 else (row[i] - row[i - 3]) & 0xFF for i in range(len(row))])
    data = zlib.compress(raw)
    entries = [(256, 3, 1, 3), (257, 3, 1, 2), (258, 3, 3, 0), (259, 3, 1, 8), (262, 3, 1, 2), (273, 4, 1, 0),
               (277, 3, 1, 3), (278, 3, 1, 2), (279, 4, 1, len(data)), (317, 3, 1, 2)]
    ifd_at = 8
    after = ifd_at + 2 + len(entries) * 12 + 4
    bits_at, data_at = after, after + 6
    ifd = struct.pack('>H', len(entries))
    for tag, kind, count, value in entries:
        if tag == 258:
            value = bits_at
        if tag == 273:
            value = data_at
        packed = struct.pack('>HI', value, 0)[:4] if kind == 3 and count == 1 else struct.pack('>I', value)
        ifd += struct.pack('>HHI', tag, kind, count) + packed
    ifd += struct.pack('>I', 0)
    open(path, 'wb').write(b'MM\0*' + struct.pack('>I', ifd_at) + ifd + struct.pack('>HHH', 8, 8, 8) + data)


motorola(out + 'motorola.tif')

# GIF: the six colours, the same interlaced, and with its first colour said to be transparent.
gif = bmp.convert('P', palette=Image.ADAPTIVE, colors=8)
gif.save(out + 'rgb.gif')
gif.save(out + 'interlaced.gif', interlace=True)
gif.save(out + 'transparent.gif', transparency=0)

# 40 x 10 at 72 dpi, which JFIF states exactly where PNG and BMP count per metre: its own size is 40 x 10 points.
Image.new('RGB', (40, 10), (0, 0, 255)).save(out + 'wide.jpg', quality=95, dpi=(72, 72))

Image.new('RGB', (4, 3), (10, 200, 30)).save(out + 'rgb.jpg', quality=95)
Image.new('RGB', (4, 3), (10, 200, 30)).save(out + 'rgb-300.jpg', quality=95, dpi=(300, 300))
Image.new('CMYK', (5, 2), (0, 255, 255, 0)).save(out + 'cmyk.jpg', quality=95)

# The embedded picture of Drawing.lst: rgba.png as List & Label carries a file.
data = open(out + 'rgba.png', 'rb').read()
packed = struct.pack('<I', len(data)) + b'ChK_Packed\0' + zlib.compress(data)
print('Contents=@2@' + base64.b64encode(packed).decode())
