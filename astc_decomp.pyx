from PIL import Image, ImageFile
import io
from libc.stdint cimport uint8_t
from libcpp cimport bool

cdef extern from "astc_dec/astc_decomp.h" namespace "basisu::astc":
    # Unpacks a single ASTC block to pDst
    # If isSRGB is true, the spec requires the decoder to scale the LDR 8-bit endpoints to 16-bit before interpolation slightly differently,
    # which will lead to different outputs. So be sure to set it correctly (ideally it should match whatever the encoder did).
    cdef bool decompress(uint8_t* pDst, const uint8_t* data, bool isSRGB, int blockWidth, int blockHeight);

# define decoder
class ASTCDecoder(ImageFile.PyDecoder):
    dstChannelBytes = 1
    dstChannels = 4

    def decode(self, buffer):
        if isinstance(buffer, (io.BufferedReader, io.BytesIO)):
            data = buffer.read()
        else:
            data = buffer

        self.set_as_raw(
            decompress_astc(
                data,
                self.state.xsize,
                self.state.ysize,
                self.args[0],
                self.args[1],
                self.args[2] if len(self.args) > 2 else False
            )
        )
        return -1, 0


def decompress_astc(astc_data : bytes, width : int, height : int, block_width : int, block_height : int,
                    is_srgb : bool = False) -> bytes:
    """
    Decompresses ASTC LDR image data to a RGBA32 buffer.
    Supports formats defined in the KHR_texture_compression_astc_ldr spec and
    returns UNORM8 values.  sRGB is not supported, and should be implemented
    by the caller.
    :param astc_data: - Compressed ASTC image buffer, must be at least |astc_data_size|
        bytes long.
    :param width: - Image width, in pixels.
    :param height: - Image height, in pixels.
    :param block_width: - Block width, in pixels.
    :param block_height: - BLock height, in pixels.
    :param is_srgb: - True/False (default)
    :returns: - Returns a buffer where the decompressed image will be
        stored, must be at least |out_buffer_size| bytes long if decompression succeeded,
        or b'' if it failed or if the astc_data_size was too small for the given width, height,
        and footprint, or if out_buffer_size is too small.
    """
    img_data = bytearray(width * height * 4)

    cdef size_t k_size_in_bytes = 16
    cdef size_t k_bytes_per_pixel_unorm8 = 4

    cdef size_t block_index
    cdef size_t block_x
    cdef size_t block_y
    cdef size_t blocks_wide = (width + block_width - 1) / block_width
    cdef size_t row_length = block_width * k_bytes_per_pixel_unorm8

    for i in range(0, len(astc_data), k_size_in_bytes):
        block_index = i / k_size_in_bytes
        block_x = block_index % blocks_wide
        block_y = block_index / blocks_wide

        src = astc_data[i:i + 16]
        block = bytes(block_width * block_height * 4)
        decompress(<uint8_t*> block, <uint8_t*> src, <bool> is_srgb, <int> block_width, <int> block_height)

        for y in range(block_height):
            py = block_height * block_y + y

            px = block_width * block_x
            dst_pixel_pos = (py * width + px) * k_bytes_per_pixel_unorm8
            src_pixel_pos = (y * block_width) * k_bytes_per_pixel_unorm8
            img_data[dst_pixel_pos: dst_pixel_pos + row_length] = block[src_pixel_pos: src_pixel_pos + row_length]
            """
            LDR only - no pixel decoding required
            for x in range(block_width):
                px = block_width * block_x + x

                # Skip out of bounds
                if px >= width or py >= height:
                    continue

                dst_pixel_pos = (py * width + px) * k_bytes_per_pixel_unorm8
                src_pixel_pos = (y * block_width + x) * k_bytes_per_pixel_unorm8
                for j in range(k_bytes_per_pixel_unorm8):
                    img_data[dst_pixel_pos + j] = block[src_pixel_pos + j]
            """
    return bytes(img_data)

# register decoder
if 'astc' not in Image.DECODERS:
    Image.register_decoder('astc', ASTCDecoder)
