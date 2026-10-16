#include "include/StaticBadgeWebP.h"

#include "src/webp/decode.h"
#include "src/webp/demux.h"
#include "src/webp/encode.h"
#include "src/webp/mux.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * libwebp 的 ARGB 输入是“非预乘”的：解码端直接把 alpha 乘回去还原颜色。
 * 而 CGBitmapContext 给出的位图是预乘的，直接把 RGB 当非预乘编码会让半透明
 * 边缘被乘两次 alpha（偏暗），所以统一在进编码器前反预乘一次。
 */
static void unpremultiply_bgra(const uint8_t *src, int src_stride, uint8_t *dst,
                               int dst_stride, int width, int height) {
    int y;
    for (y = 0; y < height; ++y) {
        const uint8_t *s = src + (size_t)y * src_stride;
        uint8_t *d = dst + (size_t)y * dst_stride;
        int x;
        for (x = 0; x < width; ++x, s += 4, d += 4) {
            const int a = s[3];
            d[3] = (uint8_t)a;
            if (a == 255) {
                d[0] = s[0];
                d[1] = s[1];
                d[2] = s[2];
            } else if (a == 0) {
                d[0] = d[1] = d[2] = 0;
            } else {
                int b = (s[0] * 255 + a / 2) / a;
                int g = (s[1] * 255 + a / 2) / a;
                int r = (s[2] * 255 + a / 2) / a;
                d[0] = (uint8_t)(b > 255 ? 255 : b);
                d[1] = (uint8_t)(g > 255 ? 255 : g);
                d[2] = (uint8_t)(r > 255 ? 255 : r);
            }
        }
    }
}

/* 分配一块紧凑（width * 4）的位图缓冲。 */
static uint8_t *alloc_bitmap(int width, int height, int *bytes_per_row) {
    const int stride = width * 4;
    uint8_t *buffer = (uint8_t *)malloc((size_t)stride * (size_t)height);
    if (buffer != NULL) {
        *bytes_per_row = stride;
    }
    return buffer;
}

size_t SBWebPEncodeBGRA(const uint8_t *pixels, int width, int height, int bytesPerRow,
                        float quality, int lossless, uint8_t **output) {
    if (pixels == NULL || output == NULL || width <= 0 || height <= 0 || bytesPerRow <= 0) {
        return 0;
    }
    *output = NULL;

    int stride = 0;
    uint8_t *scratch = alloc_bitmap(width, height, &stride);
    if (scratch == NULL) {
        return 0;
    }
    unpremultiply_bgra(pixels, bytesPerRow, scratch, stride, width, height);

    size_t written;
    if (lossless) {
        written = WebPEncodeLosslessBGRA(scratch, width, height, stride, output);
    } else {
        if (quality < 0.0f) quality = 0.0f;
        if (quality > 100.0f) quality = 100.0f;
        written = WebPEncodeBGRA(scratch, width, height, stride, quality, output);
    }
    free(scratch);
    return written;
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

/* ------------------------------------------------------------ 动态 WebP 编码 */

struct SBWebPAnimEncoder {
    WebPAnimEncoder *encoder;
    WebPConfig config;
    uint8_t *scratch;
    int scratch_stride;
    int width;
    int height;
    int next_timestamp_ms; /* 下一帧的时间戳，帧时长按追加顺序累加 */
    char error[160];
};

void *SBWebPAnimEncoderNew(int width, int height, int bytes_per_row, int loop_count,
                           uint32_t bgcolor, float quality, int lossless) {
    if (width <= 0 || height <= 0 || bytes_per_row <= 0 || bytes_per_row % 4 != 0) {
        return NULL;
    }

    WebPAnimEncoderOptions options;
    if (!WebPAnimEncoderOptionsInit(&options)) {
        return NULL;
    }
    options.anim_params.loop_count = loop_count < 0 ? 0 : loop_count;
    options.anim_params.bgcolor = bgcolor;

    struct SBWebPAnimEncoder *enc =
        (struct SBWebPAnimEncoder *)calloc(1, sizeof(struct SBWebPAnimEncoder));
    if (enc == NULL) {
        return NULL;
    }

    enc->scratch = alloc_bitmap(width, height, &enc->scratch_stride);
    if (enc->scratch == NULL) {
        free(enc);
        return NULL;
    }

    if (!WebPConfigInit(&enc->config)) {
        free(enc->scratch);
        free(enc);
        return NULL;
    }
    if (quality < 0.0f) quality = 0.0f;
    if (quality > 100.0f) quality = 100.0f;
    enc->config.quality = quality;
    enc->config.lossless = lossless ? 1 : 0;
    /* method 4 起步太慢：动图动辄上百帧，这里换成偏快的 2。 */
    enc->config.method = 2;

    enc->encoder = WebPAnimEncoderNew(width, height, &options);
    if (enc->encoder == NULL) {
        free(enc->scratch);
        free(enc);
        return NULL;
    }

    enc->width = width;
    enc->height = height;
    enc->next_timestamp_ms = 0;
    return enc;
}

int SBWebPAnimEncoderAddFrame(void *opaque, const uint8_t *pixels, int bytes_per_row,
                              int duration_ms) {
    struct SBWebPAnimEncoder *enc = (struct SBWebPAnimEncoder *)opaque;
    if (enc == NULL || enc->encoder == NULL || pixels == NULL || bytes_per_row <= 0 ||
        bytes_per_row % 4 != 0 || duration_ms <= 0) {
        return 0;
    }

    unpremultiply_bgra(pixels, bytes_per_row, enc->scratch, enc->scratch_stride, enc->width,
                       enc->height);

    WebPPicture picture;
    if (!WebPPictureInit(&picture)) {
        return 0;
    }
    picture.width = enc->width;
    picture.height = enc->height;
    picture.use_argb = 1;
    picture.argb = (uint32_t *)enc->scratch;
    picture.argb_stride = enc->scratch_stride / 4;

    const int timestamp_ms = enc->next_timestamp_ms;
    if (!WebPAnimEncoderAdd(enc->encoder, &picture, timestamp_ms, &enc->config)) {
        const char *reason = WebPAnimEncoderGetError(enc->encoder);
        snprintf(enc->error, sizeof(enc->error), "%s",
                 reason != NULL && reason[0] != '\0' ? reason : "追加帧失败");
        return 0;
    }

    enc->next_timestamp_ms = timestamp_ms + duration_ms;
    if (enc->next_timestamp_ms < 0) {
        enc->next_timestamp_ms = 0; /* 时长溢出，交给 libwebp 自己夹取 */
    }
    enc->error[0] = '\0';
    return 1;
}

size_t SBWebPAnimEncoderFinish(void *opaque, uint8_t **output) {
    struct SBWebPAnimEncoder *enc = (struct SBWebPAnimEncoder *)opaque;
    if (enc == NULL || enc->encoder == NULL || output == NULL) {
        return 0;
    }
    *output = NULL;

    /* 传 NULL 帧告知“没有更多帧”，同时决定最后一帧的时长。 */
    if (!WebPAnimEncoderAdd(enc->encoder, NULL, enc->next_timestamp_ms, NULL)) {
        snprintf(enc->error, sizeof(enc->error), "结束编码失败");
        return 0;
    }

    WebPData webp_data;
    webp_data.bytes = NULL;
    webp_data.size = 0;
    if (!WebPAnimEncoderAssemble(enc->encoder, &webp_data)) {
        const char *reason = WebPAnimEncoderGetError(enc->encoder);
        snprintf(enc->error, sizeof(enc->error), "%s",
                 reason != NULL && reason[0] != '\0' ? reason : "组装码流失败");
        return 0;
    }

    *output = (uint8_t *)webp_data.bytes;
    enc->error[0] = '\0';
    return webp_data.size;
}

const char *SBWebPAnimEncoderError(void *opaque) {
    struct SBWebPAnimEncoder *enc = (struct SBWebPAnimEncoder *)opaque;
    if (enc == NULL) {
        return "编码器未创建";
    }
    if (enc->error[0] != '\0') {
        return enc->error;
    }
    if (enc->encoder != NULL) {
        const char *reason = WebPAnimEncoderGetError(enc->encoder);
        if (reason != NULL && reason[0] != '\0') {
            return reason;
        }
    }
    return "";
}

void SBWebPAnimEncoderDelete(void *opaque) {
    struct SBWebPAnimEncoder *enc = (struct SBWebPAnimEncoder *)opaque;
    if (enc == NULL) {
        return;
    }
    if (enc->encoder != NULL) {
        WebPAnimEncoderDelete(enc->encoder);
    }
    free(enc->scratch);
    free(enc);
}

/* ------------------------------------------------------------ 动态 WebP 解码 */

void *SBWebPAnimDecoderNew(const uint8_t *data, size_t data_size) {
    if (data == NULL || data_size == 0) {
        return NULL;
    }

    WebPAnimDecoderOptions options;
    if (!WebPAnimDecoderOptionsInit(&options)) {
        return NULL;
    }
    options.color_mode = MODE_RGBA;

    WebPData webp_data;
    webp_data.bytes = data;
    webp_data.size = data_size;
    return WebPAnimDecoderNew(&webp_data, &options);
}

int SBWebPAnimDecoderGetInfo(void *decoder, SBWebPAnimationInfo *info) {
    if (decoder == NULL || info == NULL) {
        return 0;
    }
    WebPAnimInfo anim_info;
    if (!WebPAnimDecoderGetInfo((WebPAnimDecoder *)decoder, &anim_info)) {
        return 0;
    }
    info->width = (int)anim_info.canvas_width;
    info->height = (int)anim_info.canvas_height;
    info->frame_count = (int)anim_info.frame_count;
    info->loop_count = (int)anim_info.loop_count;
    info->bgcolor = anim_info.bgcolor;
    return 1;
}

int SBWebPAnimDecoderHasMoreFrames(void *decoder) {
    if (decoder == NULL) {
        return 0;
    }
    return WebPAnimDecoderHasMoreFrames((WebPAnimDecoder *)decoder);
}

int SBWebPAnimDecoderNext(void *decoder, const uint8_t **rgba, int *bytes_per_row,
                          int *timestamp_ms) {
    if (decoder == NULL || rgba == NULL || bytes_per_row == NULL || timestamp_ms == NULL) {
        return 0;
    }
    uint8_t *buffer = NULL;
    int timestamp = 0;
    if (!WebPAnimDecoderGetNext((WebPAnimDecoder *)decoder, &buffer, &timestamp)) {
        return 0;
    }
    *rgba = buffer;
    *timestamp_ms = timestamp;
    *bytes_per_row = 0; /* 画布是紧凑行，行距由调用方按宽 * 4 计算 */
    return 1;
}

void SBWebPAnimDecoderDelete(void *decoder) {
    if (decoder != NULL) {
        WebPAnimDecoderDelete((WebPAnimDecoder *)decoder);
    }
}
