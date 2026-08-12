/*
 * This file is part of mpv.
 *
 * mpv is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * mpv is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with mpv.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <stdbool.h>
#include <string.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <native_buffer/native_buffer.h>
#include <native_window/external_window.h>
#include <native_vsync/native_vsync.h>

#include "video/out/ohos_common.h"
#include "egl_helpers.h"
#include "common/common.h"
#include "context.h"

struct priv {
    struct GL gl;
    EGLDisplay egl_display;
    EGLContext egl_context;
    EGLSurface egl_surface;
    EGLConfig  egl_config;
    OHNativeWindow *native_window;
    struct pl_color_space target_csp;
    int native_gamut;
    // NativeVSync: 仅用于读取刷新率周期，不使用回调机制
    OH_NativeVSync *native_vsync;
    int64_t         vsync_period;  // vsync 周期 (ns)
};

static int ohos_refine_egl_config(void *user_data, EGLConfig *configs,
                                  int num_configs)
{
    struct ra_ctx *ctx = user_data;
    struct priv *p = ctx->priv;
    int rgba8 = -1;

    /* Prefer a 10-bit swapchain for HDR and retain an RGBA8 fallback for
     * devices whose compositor exposes no RGB10_A2 window format. */
    for (int n = 0; n < num_configs; n++) {
        EGLint r = 0, g = 0, b = 0, a = 0;
        eglGetConfigAttrib(p->egl_display, configs[n], EGL_RED_SIZE, &r);
        eglGetConfigAttrib(p->egl_display, configs[n], EGL_GREEN_SIZE, &g);
        eglGetConfigAttrib(p->egl_display, configs[n], EGL_BLUE_SIZE, &b);
        eglGetConfigAttrib(p->egl_display, configs[n], EGL_ALPHA_SIZE, &a);
        if (r == 10 && g == 10 && b == 10 && a == 2) {
            MP_INFO(ctx, "Using 10-bit RGB10_A2 EGL output for HDR.\n");
            return n;
        }
        if (rgba8 < 0 && r == 8 && g == 8 && b == 8 && a >= 8)
            rgba8 = n;
    }

    MP_WARN(ctx, "No 10-bit EGL window config; using SDR RGBA8 output.\n");
    return rgba8 >= 0 ? rgba8 : 0;
}

static pl_color_space_t ohos_preferred_csp(struct ra_ctx *ctx)
{
    struct priv *p = ctx->priv;
    return p->target_csp;
}

static bool ohos_set_color(struct ra_ctx *ctx, struct mp_image_params *params)
{
    struct priv *p = ctx->priv;
    struct pl_color_space target = pl_color_space_srgb;
    int gamut = NATIVEBUFFER_COLOR_GAMUT_SRGB;
    const char *name = "sRGB";

    if (params && params->color.transfer == PL_COLOR_TRC_PQ) {
        target = pl_color_space_hdr10;
        gamut = NATIVEBUFFER_COLOR_GAMUT_BT2100_PQ;
        name = "BT.2100 PQ";
    } else if (params && params->color.transfer == PL_COLOR_TRC_HLG) {
        target = pl_color_space_bt2020_hlg;
        gamut = NATIVEBUFFER_COLOR_GAMUT_BT2100_HLG;
        name = "BT.2100 HLG";
    }

    if (gamut != p->native_gamut) {
        int32_t ret = OH_NativeWindow_NativeWindowHandleOpt(
            p->native_window, SET_COLOR_GAMUT, (int32_t)gamut);
        if (ret != 0) {
            MP_WARN(ctx, "NativeWindow rejected %s gamut (%d); tone mapping to sRGB.\n",
                    name, (int)ret);
            target = pl_color_space_srgb;
            gamut = NATIVEBUFFER_COLOR_GAMUT_SRGB;
            OH_NativeWindow_NativeWindowHandleOpt(
                p->native_window, SET_COLOR_GAMUT, (int32_t)gamut);
        } else {
            MP_INFO(ctx, "NativeWindow output color space: %s.\n", name);
        }
        p->native_gamut = gamut;
    }

    p->target_csp = target;
    if (params)
        params->color = target;
    return true;
}

static void ohos_swap_buffers(struct ra_ctx *ctx)
{
    struct priv *p = ctx->priv;
    eglSwapBuffers(p->egl_display, p->egl_surface);
    // 不使用 OH_NativeVSync_RequestFrame：该 API 是单次回调模式，
    // 快速 seek 期间高频调用会导致内部死锁。
    // vsync 时间戳由 ohos_get_vsync 中直接读取 wall clock 提供，
    // mpv 内部会做样本平均，精度足够。
}

static void ohos_get_vsync(struct ra_ctx *ctx, struct vo_vsync_info *info)
{
    struct priv *p = ctx->priv;

    // 刷新率查询：仅在 vsync_period 未知时查询一次
    if (p->native_vsync && p->vsync_period <= 0) {
        long long period = 0;
        if (OH_NativeVSync_GetPeriod(p->native_vsync, &period) == 0 && period > 0)
            p->vsync_period = (int64_t)period;
    }

    // 使用 wall clock 作为 last_queue_display_time；
    // vo.c 中若该值 <= 0 会自动补 mp_time_ns()，行为一致。
    // 这与旧版（native_vsync 未链接、p->native_vsync == NULL）完全相同。
}

static void ohos_uninit(struct ra_ctx *ctx)
{
    struct priv *p = ctx->priv;
    ra_gl_ctx_uninit(ctx);

    if (p->native_vsync) {
        OH_NativeVSync_Destroy(p->native_vsync);
        p->native_vsync = NULL;
    }

    if (p->egl_surface) {
        eglMakeCurrent(p->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                       EGL_NO_CONTEXT);
        eglDestroySurface(p->egl_display, p->egl_surface);
    }
    if (p->egl_context)
        eglDestroyContext(p->egl_display, p->egl_context);

    vo_ohos_uninit(ctx->vo);
}

static bool ohos_init(struct ra_ctx *ctx)
{
    struct priv *p = ctx->priv = talloc_zero(ctx, struct priv);

    if (!vo_ohos_init(ctx->vo))
        goto fail;

    p->egl_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (!eglInitialize(p->egl_display, NULL, NULL)) {
        MP_FATAL(ctx, "EGL failed to initialize.\n");
        goto fail;
    }

    struct mpegl_cb egl_cb = {
        .refine_config = ohos_refine_egl_config,
        .user_data = ctx,
    };
    if (!mpegl_create_context_cb(ctx, p->egl_display, egl_cb,
                                 &p->egl_context, &p->egl_config))
        goto fail;

    p->native_window = vo_ohos_native_window(ctx->vo);
    p->target_csp = pl_color_space_srgb;
    p->native_gamut = -1;
    EGLint format = 0;
    if (!eglGetConfigAttrib(p->egl_display, p->egl_config,
                            EGL_NATIVE_VISUAL_ID, &format)) {
        MP_FATAL(ctx, "Could not query EGL native visual: 0x%x\n", eglGetError());
        goto fail;
    }
    int32_t format_result = OH_NativeWindow_NativeWindowHandleOpt(
        p->native_window, SET_FORMAT, (int32_t)format);
    if (format_result != 0) {
        MP_FATAL(ctx, "Could not set NativeWindow format %d: %d\n",
                 (int)format, (int)format_result);
        goto fail;
    }

    /* The initial frame is SDR. Reconfiguration switches this to PQ/HLG when
     * the decoded frame metadata identifies HDR content. */
    ohos_set_color(ctx, NULL);

    p->egl_surface = eglCreateWindowSurface(p->egl_display, p->egl_config,
                            (EGLNativeWindowType)p->native_window, NULL);

    if (p->egl_surface == EGL_NO_SURFACE) {
        MP_FATAL(ctx, "Could not create EGL surface: 0x%x\n", eglGetError());
        goto fail;
    }

    if (!eglMakeCurrent(p->egl_display, p->egl_surface, p->egl_surface,
                        p->egl_context)) {
        MP_FATAL(ctx, "Failed to set context!\n");
        goto fail;
    }

    mpegl_load_functions(&p->gl, ctx->log);

    // 创建 NativeVSync 实例：仅用于查询刷新率周期（GetPeriod），
    // 不使用 RequestFrame 回调，避免快速 seek 时并发触发死锁
    const char *vsync_name = "mpv-ohos";
    p->native_vsync = OH_NativeVSync_Create(vsync_name, strlen(vsync_name));
    if (!p->native_vsync)
        MP_WARN(ctx, "Failed to create OH_NativeVSync, FPS detection will be estimated\n");

    struct ra_ctx_params params = {
        .swap_buffers = ohos_swap_buffers,
        .get_vsync    = ohos_get_vsync,
        .preferred_csp = ohos_preferred_csp,
        .set_color     = ohos_set_color,
    };

    if (!ra_gl_ctx_init(ctx, &p->gl, params))
        goto fail;

    return true;
fail:
    ohos_uninit(ctx);
    return false;
}

static bool ohos_reconfig(struct ra_ctx *ctx)
{
    int w, h;
    if (!vo_ohos_surface_size(ctx->vo, &w, &h))
        return false;

    ctx->vo->dwidth = w;
    ctx->vo->dheight = h;
    ra_gl_ctx_resize(ctx->swapchain, w, h, 0);
    return true;
}

static void ohos_resize_if_needed(struct ra_ctx *ctx, int *events)
{
    int w, h;
    if (!vo_ohos_surface_size(ctx->vo, &w, &h))
        return;

    if (w == ctx->vo->dwidth && h == ctx->vo->dheight)
        return;

    MP_VERBOSE(ctx, "NativeWindow resized: %dx%d -> %dx%d\n",
               ctx->vo->dwidth, ctx->vo->dheight, w, h);
    ctx->vo->dwidth = w;
    ctx->vo->dheight = h;
    ra_gl_ctx_resize(ctx->swapchain, w, h, 0);
    *events |= VO_EVENT_RESIZE;
}

static int ohos_control(struct ra_ctx *ctx, int *events, int request, void *arg)
{
    struct priv *p = ctx->priv;

    // ArkUI keeps the same Surface ID while resizing/rotating an XComponent.
    // Poll NativeWindow geometry on mpv's regular control calls so the GL
    // swapchain and viewport never remain at the creation-time dimensions.
    ohos_resize_if_needed(ctx, events);

    switch (request) {
    case VOCTRL_GET_DISPLAY_FPS: {
        if (p->vsync_period > 0) {
            *(double *)arg = 1e9 / (double)p->vsync_period;
            return VO_TRUE;
        }
        return VO_NOTIMPL;
    }
    }
    return VO_NOTIMPL;
}

const struct ra_ctx_fns ra_ctx_ohos = {
    .type           = "opengl",
    .name           = "ohos",
    .description    = "HarmonyOS/EGL",
    .reconfig       = ohos_reconfig,
    .control        = ohos_control,
    .init           = ohos_init,
    .uninit         = ohos_uninit,
};
