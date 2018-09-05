/* Copyright (C) 2018 the mpv developers
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

#ifndef MPV_CLIENT_API_RENDER_H_
#define MPV_CLIENT_API_RENDER_H_

#include "client.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Overview
 * --------
 *
 * This API can be used to make mpv render using supported graphic APIs (such
 * as OpenGL). It can be used to handle video display.
 *
 * The renderer needs to be created with mpv_render_context_create() before
 * you start playback (or otherwise cause a VO to be created). Then (with most
 * backends) mpv_render_context_render() can be used to explicitly render the
 * current video frame. Use mpv_render_context_set_update_callback() to get
 * notified when there is a new frame to draw.
 *
 * Preferably rendering should be done in a separate thread. If you call
 * normal libmpv API functions on the renderer thread, deadlocks can result
 * (these are made non-fatal with timeouts, but user experience will obviously
 * suffer). See "Threading" section below.
 *
 * You can output and embed video without this API by setting the mpv "wid"
 * option to a native window handle (see "Embedding the video window" section
 * in the client.h header). In general, using the render API is recommended,
 * because window embedding can cause various issues, especially with GUI
 * toolkits and certain platforms.
 *
 * Supported backends
 * ------------------
 *
 * OpenGL: via MPV_RENDER_API_TYPE_OPENGL, see render_gl.h header.
 *
 * Threading
 * ---------
 *
 * You are recommended to do rendering on a separate thread than normal libmpv
 * use.
 *
 * The mpv_render_* functions can be called from any thread, under the
 * following conditions:
 *  - only one of the mpv_render_* functions can be called at the same time
 *    (unless they belong to different mpv cores created by mpv_create())
 *  - never can be called from within the callbacks set with
 *    mpv_set_wakeup_callback() or mpv_render_context_set_update_callback()
 *  - if the OpenGL backend is used, for all functions the OpenGL context
 *    must be "current" in the calling thread, and it must be the same OpenGL
 *    context as the mpv_render_context was created with. Otherwise, undefined
 *    behavior will occur.
 *  - the thread does not call libmpv API functions other than the mpv_render_*
 *    functions, except APIs which are declared as safe (see below). Likewise,
 *    there must be no lock or wait dependency from the render thread to a
 *    thread using other libmpv functions. Basically, the situation that your
 *    render thread waits for a "not safe" libmpv API function to return must
 *    not happen. If you ignore this requirement, deadlocks can happen, which
 *    are made non-fatal with timeouts; then playback quality will be degraded,
 *    and the message
 *          mpv_render_context_render() not being called or stuck.
 *    is logged. If you set MPV_RENDER_PARAM_ADVANCED_CONTROL, you promise that
 *    this won't happen, and must absolutely guarantee it, or a real deadlock
 *    will freeze the mpv core thread forever.
 *
 * libmpv functions which are safe to call from a render thread are:
 *  - functions marked with "Safe to be called from mpv render API threads."
 *  - client.h functions which don't have an explicit or implicit mpv_handle
 *    parameter
 *  - mpv_render_* functions; but only for the same mpv_render_context pointer.
 *    If the pointer is different, mpv_render_context_free() is not safe. (The
 *    reason is that if MPV_RENDER_PARAM_ADVANCED_CONTROL is set, it may have
 *    to process still queued requests from the core, which it can do only for
 *    the current context, while requests for other contexts would deadlock.
 *    Also, it may have to wait and block for the core to terminate the video
 *    chain to make sure no resources are used after context destruction.)
 *  - if the mpv_handle parameter refers to a different mpv core than the one
 *    you're rendering for (very obscure, but allowed)
 *
 * Context and handle lifecycle
 * ----------------------------
 *
 * Video initialization will fail if the render context was not initialized yet
 * (with mpv_render_context_create()), or it will revert to a VO that creates
 * its own window.
 *
 * Currently, there can be only 1 mpv_render_context at a time per mpv core.
 *
 * Calling mpv_render_context_free() while a VO is using the render context is
 * active will disable video.
 *
 * You must free the context with mpv_render_context_free() before the mpv core
 * is destroyed. If this doesn't happen, undefined behavior will result.
 */

/**
 * Opaque context, returned by mpv_render_context_create().
 */
typedef struct mpv_render_context mpv_render_context;

/**
 * Parameters for mpv_render_param (which is used in a few places such as
 * mpv_render_context_create().
 *
 * Also see mpv_render_param for conventions and how to use it.
 */
typedef enum mpv_render_param_type {
    /**
     * Not a valid value, but also used to terminate a params array. Its value
     * is always guaranteed to be 0 (even if the ABI changes in the future).
     */
    MPV_RENDER_PARAM_INVALID = 0,
    /**
     * The render API to use. Valid for mpv_render_context_create().
     *
     * Type: char*
     *
     * Defined APIs:
     *
     *   MPV_RENDER_API_TYPE_OPENGL:
     *      OpenGL desktop 2.1 or later (preferably core profile compatible to
     *      OpenGL 3.2), or OpenGLES 2.0 or later.
     *      Providing MPV_RENDER_PARAM_OPENGL_INIT_PARAMS is required.
     *      It is expected that an OpenGL context is valid and "current" when
     *      calling mpv_render_* functions (unless specified otherwise). It
     *      must be the same context for the same mpv_render_context.
     */
    MPV_RENDER_PARAM_API_TYPE = 1,
    /**
     * Required parameters for initializing the OpenGL renderer. Valid for
     * mpv_render_context_create().
     * Type: mpv_opengl_init_params*
     */
    MPV_RENDER_PARAM_OPENGL_INIT_PARAMS = 2,
    /**
     * Describes a GL render target. Valid for mpv_render_context_render().
     * Type: mpv_opengl_fbo*
     */
    MPV_RENDER_PARAM_OPENGL_FBO = 3,
    /**
     * Control flipped rendering. Valid for mpv_render_context_render().
     * Type: int*
     * If the value is set to 0, render normally. Otherwise, render it flipped,
     * which is needed e.g. when rendering to an OpenGL default framebuffer
     * (which has a flipped coordinate system).
     */
    MPV_RENDER_PARAM_FLIP_Y = 4,
    /**
     * Control surface depth. Valid for mpv_render_context_render().
     * Type: int*
     * This implies the depth of the surface passed to the render function in
     * bits per channel. If omitted or set to 0, the renderer will assume 8.
     * Typically used to control dithering.
     */
    MPV_RENDER_PARAM_DEPTH = 5,
    /**
     * ICC profile blob. Valid for mpv_render_context_set_parameter().
     * Type: mpv_byte_array*
     * Set an ICC profile for use with the "icc-profile-auto" option. (If the
     * option is not enabled, the ICC data will not be used.)
     */
    MPV_RENDER_PARAM_ICC_PROFILE = 6,
    /**
     * Ambient light in lux. Valid for mpv_render_context_set_parameter().
     * Type: int*
     * This can be used for automatic gamma correction.
     */
    MPV_RENDER_PARAM_AMBIENT_LIGHT = 7,
    /**
     * X11 Display, sometimes used for hwdec. Valid for
     * mpv_render_context_create(). The Display must stay valid for the lifetime
     * of the mpv_render_context.
     * Type: Display*
     */
    MPV_RENDER_PARAM_X11_DISPLAY = 8,
    /**
     * Wayland display, sometimes used for hwdec. Valid for
     * mpv_render_context_create(). The wl_display must stay valid for the
     * lifetime of the mpv_render_context.
     * Type: struct wl_display*
     */
    MPV_RENDER_PARAM_WL_DISPLAY = 9,
    /**
     * Better control about rendering and enabling some advanced features. Valid
     * for mpv_render_context_create().
     *
     * This conflates multiple requirements the API user promises to abide if
     * this option is enabled:
     *
     *  - The API user's render thread, which is calling the mpv_render_*()
     *    functions, never waits for the core. Otherwise deadlocks can happen.
     *    See "Threading" section.
     *  - The callback set with mpv_render_context_set_update_callback() can now
     *    be called even if there is no new frame. The API user should call the
     *    mpv_render_context_update() function, and interpret the return value
     *    for whether a new frame should be rendered.
     *  - Correct functionality is impossible if the update callback is not set,
     *    or not set soon enough after mpv_render_context_create() (the core can
     *    block while waiting for you to call mpv_render_context_update(), and
     *    if the update callback is not correctly set, it will deadlock, or
     *    block for too long).
     *
     * In general, setting this option will enable the following features (and
     * possibly more):
     *
     *  - "Direct rendering", which means the player decodes directly to a
     *    texture, which saves a copy per video frame ("vd-lavc-dr" option
     *    needs to be enabled, and the rendering backend as well as the
     *    underlying GPU API/driver needs to have support for it).
     *  - Rendering screenshots with the GPU API if supported by the backend
     *    (instead of using a suboptimal software fallback via libswscale).
     *
     * Type: int*: 0 for disable (default), 1 for enable
     */
    MPV_RENDER_PARAM_ADVANCED_CONTROL = 10,
    /**
     * Return information about the next frame to render. Valid for
     * mpv_render_context_get_info().
     *
     * Type: mpv_render_frame_info*
     *
     * It strictly returns information about the _next_ frame. The implication
     * is that e.g. mpv_render_context_update()'s return value will have
     * MPV_RENDER_UPDATE_FRAME set, and the user is supposed to call
     * mpv_render_context_render(). If there is no next frame, then the
     * return value will have is_valid set to 0.
     */
    MPV_RENDER_PARAM_NEXT_FRAME_INFO = 11,
    /**
     * Enable or disable video timing. Valid for mpv_render_context_render().
     *
     * Type: int*: 0 for disable, 1 for enable (default)
     *
     * When video is timed to audio, the player attempts to render video a bit
     * ahead, and then do a blocking wait until the target display time is
     * reached. This blocks mpv_render_context_render() for up to the amount
     * specified with the "video-timing-offset" global option. You can set
     * this parameter to 0 to disable this kind of waiting. If you do, it's
     * recommended to use the target time value in mpv_render_frame_info to
     * wait yourself, or to set the "video-timing-offset" to 0 instead.
     *
     * Disabling this without doing anything in addition will result in A/V sync
     * being slightly off.
     */
    MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME = 12,
    /**
     * Use to skip rendering in mpv_render_context_render().
     *
     * Type: int*: 0 for rendering (default), 1 for skipping
     *
     * If this is set, you don't need to pass a target surface to the render
     * function (and if you do, it's completely ignored). This can still call
     * into the lower level APIs (i.e. if you use OpenGL, the OpenGL context
     * must be set).
     *
     * Be aware that the render API will consider this frame as having been
     * rendered. All other normal rules also apply, for example about whether
     * you have to call mpv_render_context_report_swap(). It also does timing
     * in the same way.
     */
    MPV_RENDER_PARAM_SKIP_RENDERING = 13,
    /**
     * DRM display, contains drm display handles.
     * Valid for mpv_render_context_create().
     * Type : struct mpv_opengl_drm_params*
     */
    MPV_RENDER_PARAM_DRM_DISPLAY = 14,
    /**
     * DRM osd size, contains osd dimensions.
     * Valid for mpv_render_context_create().
     * Type : struct mpv_opengl_drm_osd_size*
     */
    MPV_RENDER_PARAM_DRM_OSD_SIZE = 15,
} mpv_render_param_type;

/**
 * Used to pass arbitrary parameters to some mpv_render_* functions. The
 * meaning of the data parameter is determined by the type, and each
 * MPV_RENDER_PARAM_* documents what type the value must point to.
 *
 * Each value documents the required data type as the pointer you cast to
 * void* and set on mpv_render_param.data. For example, if MPV_RENDER_PARAM_FOO
 * documents the type as Something* , then the code should look like this:
 *
 *   Something foo = {...};
 *   mpv_render_param param;
 *   param.type = MPV_RENDER_PARAM_FOO;
 *   param.data = & foo;
 *
 * Normally, the data field points to exactly 1 object. If the type is char*,
 * it points to a 0-terminated string.
 *
 * In all cases (unless documented otherwise) the pointers need to remain
 * valid during the call only. Unless otherwise documented, the API functions
 * will not write to the params array or any data pointed to it.
 *
 * As a convention, parameter arrays are always terminated by type==0. There
 * is no specific order of the parameters required. The order of the 2 fields in
 * this struct is guaranteed (even after ABI changes).
 */
typedef struct mpv_render_param {
    enum mpv_render_param_type type;
    void *data;
} mpv_render_param;


/**
 * Predefined values for MPV_RENDER_PARAM_API_TYPE.
 */
#define MPV_RENDER_API_TYPE_OPENGL "opengl"

/**
 * Flags used in mpv_render_frame_info.flags. Each value represents a bit in it.
 */
typedef enum mpv_render_frame_info_flag {
    /**
     * Set if there is actually a next frame. If unset, there is no next frame
     * yet, and other flags and fields that require a frame to be queued will
     * be unset.
     *
     * This is set for _any_ kind of frame, even for redraw requests.
     *
     * Note that when this is unset, it simply means no new frame was
     * decoded/queued yet, not necessarily that the end of the video was
     * reached. A new frame can be queued after some time.
     *
     * If the return value of mpv_render_context_render() had the
     * MPV_RENDER_UPDATE_FRAME flag set, this flag will usually be set as well,
     * unless the frame is rendered, or discarded by other asynchronous events.
     */
    MPV_RENDER_FRAME_INFO_PRESENT         = 1 << 0,
    /**
     * If set, the frame is not an actual new video frame, but a redraw request.
     * For example if the video is paused, and an option that affects video
     * rendering was changed (or any other reason), an update request can be
     * issued and this flag will be set.
     *
     * Typically, redraw frames will not be subject to video timing.
     *
     * Implies MPV_RENDER_FRAME_INFO_PRESENT.
     */
    MPV_RENDER_FRAME_INFO_REDRAW          = 1 << 1,
    /**
     * If set, this is supposed to reproduce the previous frame perfectly. This
     * is usually used for certain "video-sync" options ("display-..." modes).
     * Typically the renderer will blit the video from a FBO. Unset otherwise.
     *
     * Implies MPV_RENDER_FRAME_INFO_PRESENT.
     */
    MPV_RENDER_FRAME_INFO_REPEAT          = 1 << 2,
    /**
     * If set, the player timing code expects that the user thread blocks on
     * vsync (by either delaying the render call, or by making a call to
     * mpv_render_context_report_swap() at vsync time).
     *
     * Implies MPV_RENDER_FRAME_INFO_PRESENT.
     */
    MPV_RENDER_FRAME_INFO_BLOCK_VSYNC     = 1 << 3,
} mpv_render_frame_info_flag;

/**
 * Information about the next video frame that will be rendered. Can be
 * retrieved with MPV_RENDER_PARAM_NEXT_FRAME_INFO.
 */
typedef struct mpv_render_frame_info {
    /**
     * A bitset of mpv_render_frame_info_flag values (i.e. multiple flags are
     * combined with bitwise or).
     */
    uint64_t flags;
    /**
     * Absolute time at which the frame is supposed to be displayed. This is in
     * the same unit and base as the time returned by mpv_get_time_us(). For
     * frames that are redrawn, or if vsync locked video timing is used (see
     * "video-sync" option), then this can be 0. The "video-timing-offset"
     * option determines how much "headroom" the render thread gets (but a high
     * enough frame rate can reduce it anyway). mpv_render_context_render() will
     * normally block until the time is elapsed, unless you pass it
     * MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME = 0.
     */
    int64_t target_time;
} mpv_render_frame_info;

/**
 * Initialize the renderer state. Depending on the backend used, this will
 * access the underlying GPU API and initialize its own objects.
 *
 * You must free the context with mpv_render_context_free(). Not doing so before
 * the mpv core is destroyed may result in memory leaks or crashes.
 *
 * Currently, only at most 1 context can exists per mpv core (it represents the
 * main video output).
 *
 * You should pass the following parameters:
 *  - MPV_RENDER_PARAM_API_TYPE to select the underlying backend/GPU API.
 *  - Backend-specific init parameter, like MPV_RENDER_PARAM_OPENGL_INIT_PARAMS.
 *  - Setting MPV_RENDER_PARAM_ADVANCED_CONTROL and following its rules is
 *    strongly recommended.
 *  - If you want to use hwdec, possibly hwdec interop resources.
 *
 * @param res set to the context (on success) or NULL (on failure). The value
 *            is never read and always overwritten.
 * @param mpv handle used to get the core (the mpv_render_context won't depend
 *            on this specific handle, only the core referenced by it)
 * @param params an array of parameters, terminated by type==0. It's left
 *               unspecified what happens with unknown parameters. At least
 *               MPV_RENDER_PARAM_API_TYPE is required, and most backends will
 *               require another backend-specific parameter.
 * @return error code, including but not limited to:
 *      MPV_ERROR_UNSUPPORTED: the OpenGL version is not supported
 *                             (or required extensions are missing)
 *      MPV_ERROR_NOT_IMPLEMENTED: an unknown API type was provided, or
 *                                 support for the requested API was not
 *                                 built in the used libmpv binary.
 *      MPV_ERROR_INVALID_PARAMETER: at least one of the provided parameters was
 *                                   not valid.
 */
int mpv_render_context_create(mpv_render_context **res, mpv_handle *mpv,
                              mpv_render_param *params);

/**
 * Attempt to change a single parameter. Not all backends and parameter types
 * support all kinds of changes.
 *
 * @param ctx a valid render context
 * @param param the parameter type and data that should be set
 * @return error code. If a parameter could actually be changed, this returns
 *         success, otherwise an error code depending on the parameter type
 *         and situation.
 */
int mpv_render_context_set_parameter(mpv_render_context *ctx,
                                     mpv_render_param param);

/**
 * Retrieve information from the render context. This is NOT a counterpart to
 * mpv_render_context_set_parameter(), because you generally can't read
 * parameters set with it, and this function is not meant for this purpose.
 * Instead, this is for communicating information from the renderer back to the
 * user. See mpv_render_param_type; entries which support this function
 * explicitly mention it, and for other entries you can assume it will fail.
 *
 * You pass param with param.type set and param.data pointing to a variable
 * of the required data type. The function will then overwrite that variable
 * with the returned value (at least on success).
 *
 * @param ctx a valid render context
 * @param param the parameter type and data that should be retrieved
 * @return error code. If a parameter could actually be retrieved, this returns
 *         success, otherwise an error code depending on the parameter type
 *         and situation. MPV_ERROR_NOT_IMPLEMENTED is used for unknown
 *         param.type, or if retrieving it is not supported.
 */
int mpv_render_context_get_info(mpv_render_context *ctx,
                                mpv_render_param param);

typedef void (*mpv_render_update_fn)(void *cb_ctx);

/**
 * Set the callback that notifies you when a new video frame is available, or
 * if the video display configuration somehow changed and requires a redraw.
 * Similar to mpv_set_wakeup_callback(), you must not call any mpv API from
 * the callback, and all the other listed restrictions apply (such as not
 * exiting the callback by throwing exceptions).
 *
 * This can be called from any thread, except from an update callback. In case
 * of the OpenGL backend, no OpenGL state or API is accessed.
 *
 * Calling this will raise an update callback immediately.
 *
 * @param callback callback(callback_ctx) is called if the frame should be
 *                 redrawn
 * @param callback_ctx opaque argument to the callback
 */
void mpv_render_context_set_update_callback(mpv_render_context *ctx,
                                            mpv_render_update_fn callback,
                                            void *callback_ctx);

/**
 * The API user is supposed to call this when the update callback was invoked
 * (like all mpv_render_* functions, this has to happen on the render thread,
 * and _not_ from the update callback itself).
 *
 * This is optional if MPV_RENDER_PARAM_ADVANCED_CONTROL was not set (default).
 * Otherwise, it's a hard requirement that this is called after each update
 * callback. If multiple update callback happened, and the function could not
 * be called sooner, it's OK to call it once after the last callback.
 *
 * If an update callback happens during or after this function, the function
 * must be called again at the soonest possible time.
 *
 * If MPV_RENDER_PARAM_ADVANCED_CONTROL was set, this will do additional work
 * such as allocating textures for the video decoder.
 *
 * @return a bitset of mpv_render_update_flag values (i.e. multiple flags are
 *         combined with bitwise or). Typically, this will tell the API user
 *         what should happen next. E.g. if the MPV_RENDER_UPDATE_FRAME flag is
 *         set, mpv_render_context_render() should be called. If flags unknown
 *         to the API user are set, or if the return value is 0, nothing needs
 *         to be done.
 */
uint64_t mpv_render_context_update(mpv_render_context *ctx);

/**
 * Flags returned by mpv_render_context_update(). Each value represents a bit
 * in the function's return value.
 */
typedef enum mpv_render_update_flag {
    /**
     * A new video frame must be rendered. mpv_render_context_render() must be
     * called.
     */
    MPV_RENDER_UPDATE_FRAME         = 1 << 0,
} mpv_render_context_flag;

/**
 * Render video.
 *
 * Typically renders the video to a target surface provided via mpv_render_param
 * (the details depend on the backend in use). Options like "panscan" are
 * applied to determine which part of the video should be visible and how the
 * video should be scaled. You can change these options at runtime by using the
 * mpv property API.
 *
 * The renderer will reconfigure itself every time the target surface
 * configuration (such as size) is changed.
 *
 * This function implicitly pulls a video frame from the internal queue and
 * renders it. If no new frame is available, the previous frame is redrawn.
 * The update callback set with mpv_render_context_set_update_callback()
 * notifies you when a new frame was added. The details potentially depend on
 * the backends and the provided parameters.
 *
 * Generally, libmpv will invoke your update callback some time before the video
 * frame should be shown, and then lets this function block until the supposed
 * display time. This will limit your rendering to video FPS. You can prevent
 * this by setting the "video-timing-offset" global option to 0. (This applies
 * only to "audio" video sync mode.)
 *
 * You should pass the following parameters:
 *  - Backend-specific target object, such as MPV_RENDER_PARAM_OPENGL_FBO.
 *  - Possibly transformations, such as MPV_RENDER_PARAM_FLIP_Y.
 *
 * @param ctx a valid render context
 * @param params an array of parameters, terminated by type==0. Which parameters
 *               are required depends on the backend. It's left unspecified what
 *               happens with unknown parameters.
 * @return error code
 */
int mpv_render_context_render(mpv_render_context *ctx, mpv_render_param *params);

/**
 * Tell the renderer that a frame was flipped at the given time. This is
 * optional, but can help the player to achieve better timing.
 *
 * Note that calling this at least once informs libmpv that you will use this
 * function. If you use it inconsistently, expect bad video playback.
 *
 * If this is called while no video is initialized, it is ignored.
 *
 * @param ctx a valid render context
 */
void mpv_render_context_report_swap(mpv_render_context *ctx);

/**
 * Destroy the mpv renderer state.
 *
 * If video is still active (e.g. a file playing), video will be disabled
 * forcefully.
 *
 * @param ctx a valid render context. After this function returns, this is not
 *            a valid pointer anymore. NULL is also allowed and does nothing.
 */
void mpv_render_context_free(mpv_render_context *ctx);

#ifdef __cplusplus
}
#endif

#endif
