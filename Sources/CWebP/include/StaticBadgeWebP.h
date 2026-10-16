/*
 * StaticBadgeWebP.h —— 给 Swift 用的最小 libwebp 接口。
 * 只暴露编解码两个入口，避免把 libwebp 的几十个公开头文件带进 Swift 模块。
 */
#ifndef STATICBADGE_WEBP_H
#define STATICBADGE_WEBP_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * 把位图编码成 WebP。
 * 输入按 CGBitmapContext 的小端 premultipliedFirst 布局理解（内存顺序 B,G,R,A，
 * 颜色已预乘 alpha）；libwebp 要求非预乘 ARGB，内部会先反预乘。
 * lossless != 0 时走无损编码，否则按 quality（0~100）有损编码。
 * 成功返回写入 *output 的字节数（需用 SBWebPFree 释放），失败返回 0。
 */
size_t SBWebPEncodeBGRA(const uint8_t *pixels, int width, int height, int bytesPerRow,
                        float quality, int lossless, uint8_t **output);

/*
 * 解码 WebP，输出内存顺序为 R,G,B,A 的位图。
 * 成功返回 0 并填充 width/height/output（需用 SBWebPFree 释放），
 * 失败返回 libwebp 的 VP8StatusCode。
 */
int SBWebPDecodeRGBA(const uint8_t *data, size_t data_size, int *width, int *height,
                     uint8_t **output);

/* ---------------------------------------------------------------- 动态 WebP */

/*
 * 创建动态 WebP 编码器，画布尺寸固定（所有帧同尺寸）。
 * loop_count = 0 表示无限循环；bgcolor 按 WebP 规范排列（低位起 alpha、R、G、B）。
 * 帧缓冲按预乘 BGRA 理解，内部会反预乘后交给 libwebp。
 * 失败返回 NULL。
 */
void *SBWebPAnimEncoderNew(int width, int height, int bytes_per_row, int loop_count,
                           uint32_t bgcolor, float quality, int lossless);

/*
 * 追加一帧，duration_ms 是这一帧的显示时长（至少 1 毫秒）。
 * 成功返回 1；失败返回 0，具体原因见 SBWebPAnimEncoderError。
 */
int SBWebPAnimEncoderAddFrame(void *encoder, const uint8_t *pixels, int bytes_per_row,
                              int duration_ms);

/*
 * 收尾并组装成完整码流。必须在追加至少一帧之后调用。
 * 成功返回写入 *output 的字节数（需用 SBWebPFree 释放），失败返回 0。
 */
size_t SBWebPAnimEncoderFinish(void *encoder, uint8_t **output);

/* 最近一次失败的说明，成功时为空字符串。返回的内存归 encoder 所有。 */
const char *SBWebPAnimEncoderError(void *encoder);

void SBWebPAnimEncoderDelete(void *encoder);

/* -------------------------------------------------- 动态 WebP 解码（自检用） */

typedef struct {
    int width;
    int height;
    int frame_count;
    int loop_count;
    uint32_t bgcolor;
} SBWebPAnimationInfo;

/* 解码动态 WebP，输出内存顺序为 R,G,B,A 的画布。失败返回 NULL。 */
void *SBWebPAnimDecoderNew(const uint8_t *data, size_t data_size);

/* 成功返回 1 并填充 info。 */
int SBWebPAnimDecoderGetInfo(void *decoder, SBWebPAnimationInfo *info);

int SBWebPAnimDecoderHasMoreFrames(void *decoder);

/*
 * 取下一帧（已按 dispose/blend 合成好的整幅画布）。
 * 返回 1 表示取到，缓冲有效期到下一次调用；返回 0 表示帧已取完或出错。
 */
int SBWebPAnimDecoderNext(void *decoder, const uint8_t **rgba, int *bytes_per_row,
                          int *timestamp_ms);

void SBWebPAnimDecoderDelete(void *decoder);

void SBWebPFree(void *ptr);

/* libwebp 版本，形如 "1.5.0"。 */
const char *SBWebPVersionString(void);

#ifdef __cplusplus
}
#endif

#endif /* STATICBADGE_WEBP_H */
