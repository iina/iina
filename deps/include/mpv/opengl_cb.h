/* Copyright (C) 2017 the mpv developers
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

#ifndef MPV_CLIENT_API_OPENGL_CB_H_
#define MPV_CLIENT_API_OPENGL_CB_H_

#include "client.h"

#if !MPV_ENABLE_DEPRECATED
#error "This header and all API provided by it is deprecated. Use render.h instead."
#else

#ifdef __cplusplus
extern "C" {
#endif

/**
 *
 * Overview
 * --------
 *
 * Warning: this API is deprecated. A very similar API is provided by render.h
 * and render_gl.h. The deprecated API is emulated with the new API.
 *
 * This API can be used to make mpv render into a foreign OpenGL context. It
 * can be used to handle video display.
 *
 * The renderer needs to be explicitly initialized with mpv_opengl_cb_init_gl(),
 * and then video can be drawn with mpv_opengl_cb_draw(). The user thread can
 * be notified by new frames with mpv_opengl_cb_set_update_callback().
 *
 * You can output and embed video without this API by setting the mpv "wid"
 * option to a native window handle (see "Embedding the video window" section
 * in the client.h header). In general, using the opengl-cb API is recommended,
 * because window embedding can cause various issues, especially with GUI
 * toolkits and certain platforms.
 *
 * OpenGL interop
 * --------------
 *
 * This assumes the OpenGL context lives on a certain thread controlled by the
 * API user. The following functions require access to the OpenGL context:
 *      mpv_opengl_cb_init_gl
 *      mpv_opengl_cb_draw
 *      mpv_opengl_cb_uninit_gl
 *
 * The OpenGL context is indirectly accessed through the OpenGL function
 * pointers returned by the get_proc_address callback in mpv_opengl_cb_init_gl.
 * Generally, mpv will not load the system OpenGL library when using this API.
 *
 * Only "desktop" OpenGL version 2.1 and later and OpenGL ES version 2.0 and
 * later are supported. With OpenGL 2.1, the GL_ARB_texture_rg is required. The
 * renderer was written for the OpenGL 3.x core profile, with additional support
 * for OpenGL 2.1 and OpenGL ES 2.0.
 *
 * Note that some hardware decoding interop API (as set with the "hwdec" option)
 * may actually access some sort of host API, such as EGL.
 *
 * OpenGL state
 * ------------
 *
 * OpenGL has a large amount of implicit state. All the mpv functions mentioned
 * above expect that the OpenGL state is reasonably set to OpenGL standard
 * defaults. Likewise, mpv will attempt to leave the OpenGL context with
 * standard defaults. The following state is excluded from this:
 *
 *      - the glViewport state
 *      - the glScissor state (but GL_SCISSOR_TEST is in its default value)
 *      - glBlendFuncSeparate() state (but GL_BLEND is in its default value)
 *      - glClearColor() state
 *      - mpv may overwrite the callback set with glDebugMessageCallback()
 *      - mpv always disables GL_DITHER at init
 *
 * Messing with the state could be avoided by creating shared OpenGL contexts,
 * but this is avoided for the sake of compatibility and interoperability.
 *
 * On OpenGL 2.1, mpv will strictly call functions like glGenTextures() to
 * create OpenGL objects. You will have to do the same. This ensures that
 * objects created by mpv and the API users don't clash. Also, legacy state
 * must be either in its defaults, or not interfere with core state.
 *
 * Threading
 * ---------
 *
 * The mpv_opengl_cb_* functions can be called from any thread, under the
 * following conditions:
 *  - only one of the mpv_opengl_cb_* functions can be called at the same time
 *    (unless they belong to different mpv cores created by mpv_create())
 *  - for functions which need an OpenGL context (see above) the OpenGL context
 *    must be "current" in the current thread, and it must be the same context
 *    as used with mpv_opengl_cb_init_gl()
 *  - never can be called from within the callbacks set with
 *    mpv_set_wakeup_callback() or mpv_opengl_cb_set_update_callback()
 *
 * Context and handle lifecycle
 * ----------------------------
 *
 * Video initialization will fail if the OpenGL context was not initialized yet
 * (with mpv_opengl_cb_init_gl()). Likewise, mpv_opengl_cb_uninit_gl() will
 * disable video.
 *
 * When the mpv core is destroyed (e.g. via mpv_terminate_destroy()), the OpenGL
 * context must have been uninitialized. If this doesn't happen, undefined
 * behavior will result.
 *
 * Hardware decoding
 * -----------------
 *
 * Hardware decoding via opengl_cb is fully supported, but requires some
 * additional setup. (At least if direct hardware decoding modes are wanted,
 * instead of copying back surface data from GPU to CPU RAM.)
 *
 * While "normal" mpv loads the OpenGL hardware decoding interop on demand,
 * this can't be done with opengl_cb for internal technical reasons. Instead,
 * it loads them by default, even if hardware decoding is not going to be used.
 * In older mpv releases, this had to be done by setting the
 * "opengl-hwdec-interop" or "hwdec-preload" options before calling
 * mpv_opengl_cb_init_gl(). You can still use the newer "gpu-hwdec-interop"
 * option to prevent loading of interop, or to load only a specific interop.
 *
 * There may be certain requirements on the OpenGL implementation:
 * - Windows: ANGLE is required (although in theory GL/DX interop could be used)
 * - Intel/Linux: EGL is required, and also a glMPGetNativeDisplay() callback
 *                must be provided (see sections below)
 * - nVidia/Linux: Both GLX and EGL should work (GLX is required if vdpau is
 *                 used, e.g. due to old drivers.)
 * - OSX: CGL is required (CGLGetCurrentContext() returning non-NULL)
 * - iOS: EAGL is required (EAGLContext.currentContext returning non-nil)
 *
 * Once these things are setup, hardware decoding can be enabled/disabled at
 * any time by setting the "hwdec" property.
 *
 * Special windowing system interop considerations
 * ------------------------------------------------
 *
 * In some cases, libmpv needs to have access to the windowing system's handles.
 * This can be a pointer to a X11 "Display" for example. Usually this is needed
 * only for hardware decoding.
 *
 * You can communicate these handles to libmpv by adding a pseudo-OpenGL
 * extension "GL_MP_MPGetNativeDisplay" to the additional extension string when
 * calling mpv_opengl_cb_init_gl(). The get_proc_address callback should resolve
 * a function named "glMPGetNativeDisplay", which has the signature:
 *
 *    void* GLAPIENTRY glMPGetNativeDisplay(const char* name)
 *
 * See below what names are defined. Usually, libmpv will use the native handle
 * up until mpv_opengl_cb_uninit_gl() is called. If the name is not anything
 * you know/expected, return NULL from the function.
 */

// Legacy - not supported anymore.
struct mpv_opengl_cb_window_pos {
    int x;      // left coordinates of window (usually 0)
    int y;      // top coordinates of window (usually 0)
    int width;  // width of GL window
    int height; // height of GL window
};

// Legacy - not supported anymore.
struct mpv_opengl_cb_drm_params {
    // DRM fd (int). set this to -1 if invalid.
    int fd;

    // currently used crtc id
    int crtc_id;

    // currently used connector id
    int connector_id;

    // pointer to the drmModeAtomicReq that is being used for the renderloop.
    // This atomic request pointer should be usually created at every renderloop.
    struct _drmModeAtomicReq *atomic_request;
};

/**
 * nVidia/Linux via VDPAU requires GLX, which does not have this problem (the
 * GLX API can return the current X11 Display).
 *
 * Windowing system interop on MS win32
 * ------------------------------------
 *
 * You should use ANGLE, and make sure your application and libmpv are linked
 * to the same ANGLE DLLs. libmpv will pick the device context (needed for
 * hardware decoding) from the current ANGLE EGL context.
 */

/**
 * Opaque context, returned by mpv_get_sub_api(MPV_SUB_API_OPENGL_CB).
 *
 * A context is bound to the mpv_handle it was retrieved from. The context
 * will always be the same (for the same mpv_handle), and is valid until the
 * mpv_handle it belongs to is released.
 */
typedef struct mpv_opengl_cb_context mpv_opengl_cb_context;

typedef void (*mpv_opengl_cb_update_fn)(void *cb_ctx);
typedef void *(*mpv_opengl_cb_get_proc_address_fn)(void *fn_ctx, const char *name);

/**
 * Set the callback that notifies you when a new video frame is available, or
 * if the video display configuration somehow changed and requires a redraw.
 * Similar to mpv_set_wakeup_callback(), you must not call any mpv API from
 * the callback, and all the other listed restrictions apply (such as not
 * exiting the callback by throwing exceptions).
 *
 * @param callback callback(callback_ctx) is called if the frame should be
 *                 redrawn
 * @param callback_ctx opaque argument to the callback
 */
void mpv_opengl_cb_set_update_callback(mpv_opengl_cb_context *ctx,
                                       mpv_opengl_cb_update_fn callback,
                                       void *callback_ctx);

/**
 * Initialize the mpv OpenGL state. This retrieves OpenGL function pointers via
 * get_proc_address, and creates OpenGL objects needed by mpv internally. It
 * will also call APIs needed for rendering hardware decoded video in OpenGL,
 * according to the mpv "hwdec" option.
 *
 * You must free the associated state at some point by calling the
 * mpv_opengl_cb_uninit_gl() function. Not doing so may result in memory leaks
 * or worse.
 *
 * @param exts optional _additional_ extension string, can be NULL
 * @param get_proc_address callback used to retrieve function pointers to OpenGL
 *                         functions. This is used for both standard functions
 *                         and extension functions. (The extension string is
 *                         checked whether extensions are really available.)
 *                         The callback will be called from this function only
 *                         (it is not stored and never used later).
 *                         Usually, GL context APIs do this for you (e.g. with
 *                         glXGetProcAddressARB or wglGetProcAddress), but
 *                         some APIs do not always return pointers for all
 *                         standard functions (even if present); in this case
 *                         you have to compensate by looking up these functions
 *                         yourself.
 * @param get_proc_address_ctx arbitrary opaque user context passed to the
 *                             get_proc_address callback
 * @return error code (same as normal mpv_* API), including but not limited to:
 *      MPV_ERROR_UNSUPPORTED: the OpenGL version is not supported
 *                             (or required extensions are missing)
 *      MPV_ERROR_INVALID_PARAMETER: the OpenGL state was already initialized
 */
int mpv_opengl_cb_init_gl(mpv_opengl_cb_context *ctx, const char *exts,
                          mpv_opengl_cb_get_proc_address_fn get_proc_address,
                          void *get_proc_address_ctx);

/**
 * Render video. Requires that the OpenGL state is initialized.
 *
 * The video will use the full provided framebuffer. Options like "panscan" are
 * applied to determine which part of the video should be visible and how the
 * video should be scaled. You can change these options at runtime by using the
 * mpv property API.
 *
 * The renderer will reconfigure itself every time the output rectangle/size
 * is changed. (If you want to do animations, it might be better to do the
 * animation on a FBO instead.)
 *
 * This function implicitly pulls a video frame from the internal queue and
 * renders it. If no new frame is available, the previous frame is redrawn.
 * The update callback set with mpv_opengl_cb_set_update_callback() notifies
 * you when a new frame was added.
 *
 * @param fbo The framebuffer object to render on. Because the renderer might
 *            manage multiple FBOs internally for the purpose of video
 *            postprocessing, it will always bind and unbind FBOs itself. If
 *            you want mpv to render on the main framebuffer, pass 0.
 * @param w Width of the framebuffer. This is either the video size if the fbo
 *          parameter is 0, or the allocated size of the texture backing the
 *          fbo. The renderer will always use the full size of the fbo.
 * @param h Height of the framebuffer. Same as with the w parameter, except
 *          that this parameter can be negative. In this case, the video
 *          frame will be rendered flipped.
 * @return 0
 */
int mpv_opengl_cb_draw(mpv_opengl_cb_context *ctx, int fbo, int w, int h);

/**
 * Deprecated. Use mpv_opengl_cb_draw(). This function is equivalent to:
 *
 * int mpv_opengl_cb_render(mpv_opengl_cb_context *ctx, int fbo, int vp[4])
 *  { return mpv_opengl_cb_draw(ctx, fbo, vp[2], vp[3]); }
 *
 * vp[0] and vp[1] used to have a meaning, but are ignored in newer versions.
 *
 * This function will be removed in the future without version bump (this API
 * was never marked as stable).
 */
int mpv_opengl_cb_render(mpv_opengl_cb_context *ctx, int fbo, int vp[4]);

/**
 * Tell the renderer that a frame was flipped at the given time. This is
 * optional, but can help the player to achieve better timing.
 *
 * Note that calling this at least once informs libmpv that you will use this
 * function. If you use it inconsistently, expect bad video playback.
 *
 * If this is called while no video or no OpenGL is initialized, it is ignored.
 *
 * @param time The mpv time (using mpv_get_time_us()) at which the flip call
 *             returned. If 0 is passed, mpv_get_time_us() is used instead.
 *             Currently, this parameter is ignored.
 * @return error code
 */
int mpv_opengl_cb_report_flip(mpv_opengl_cb_context *ctx, int64_t time);

/**
 * Destroy the mpv OpenGL state.
 *
 * If video is still active (e.g. a file playing), video will be disabled
 * forcefully.
 *
 * Calling this multiple times is ok.
 *
 * @return error code
 */
int mpv_opengl_cb_uninit_gl(mpv_opengl_cb_context *ctx);

#ifdef __cplusplus
}
#endif

#endif /* else #if MPV_ENABLE_DEPRECATED */

#endif
