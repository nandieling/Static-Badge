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
 * 把内存顺序为 B,G,R,A 的位图编码成 WebP。
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

void SBWebPFree(void *ptr);

/* libwebp 版本，形如 "1.5.0"。 */
const char *SBWebPVersionString(void);

#ifdef __cplusplus
}
#endif

#endif /* STATICBADGE_WEBP_H */
