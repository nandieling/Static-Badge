#include "include/StaticBadgeWebP.h"

#include "src/webp/decode.h"
#include "src/webp/encode.h"

#include <stdio.h>
#include <stdlib.h>

size_t SBWebPEncodeBGRA(const uint8_t *pixels, int width, int height, int bytesPerRow,
                        float quality, int lossless, uint8_t **output) {
    if (pixels == NULL || output == NULL || width <= 0 || height <= 0 || bytesPerRow <= 0) {
        return 0;
    }
    *output = NULL;

    if (lossless) {
        return WebPEncodeLosslessBGRA(pixels, width, height, bytesPerRow, output);
    }
    if (quality < 0.0f) quality = 0.0f;
    if (quality > 100.0f) quality = 100.0f;
    return WebPEncodeBGRA(pixels, width, height, bytesPerRow, quality, output);
}

int SBWebPDecodeRGBA(const uint8_t *data, size_t data_size, int *width, int *height,
                     uint8_t **output) {
    if (data == NULL || width == NULL || height == NULL || output == NULL) {
        return (int) VP8_STATUS_INVALID_PARAM;
    }
    *output = NULL;
    *width = 0;
    *height = 0;

    WebPDecoderConfig config;
    if (!WebPInitDecoderConfig(&config)) {
        return (int) VP8_STATUS_OUT_OF_MEMORY;
    }

    VP8StatusCode status = WebPGetFeatures(data, data_size, &config.input);
    if (status == VP8_STATUS_OK) {
        config.output.colorspace = MODE_RGBA;
        status = WebPDecode(data, data_size, &config);
    }
    if (status != VP8_STATUS_OK) {
        WebPFreeDecBuffer(&config.output);
        return (int) status;
    }

    *width = config.input.width;
    *height = config.input.height;
    *output = config.output.u.RGBA.rgba;
    if (*output == NULL) {
        return (int) VP8_STATUS_OUT_OF_MEMORY;
    }
    return 0;
}

void SBWebPFree(void *ptr) {
    free(ptr);
}

const char *SBWebPVersionString(void) {
    static char buffer[32];
    const int version = WebPGetEncoderVersion();
    snprintf(buffer, sizeof(buffer), "%d.%d.%d", version >> 16, (version >> 8) & 0xff,
             version & 0xff);
    return buffer;
}
