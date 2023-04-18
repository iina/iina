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

#ifndef MPV_CLIENT_API_STREAM_CB_H_
#define MPV_CLIENT_API_STREAM_CB_H_

#include "client.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Warning: this API is not stable yet.
 *
 * Overview
 * --------
 *
 * This API can be used to make mpv read from a stream with a custom
 * implementation. This interface is inspired by funopen on BSD and
 * fopencookie on linux. The stream is backed by user-defined callbacks
 * which can implement customized open, read, seek, size and close behaviors.
 *
 * Usage
 * -----
 *
 * Register your stream callbacks with the mpv_stream_cb_add_ro() function. You
 * have to provide a mpv_stream_cb_open_ro_fn callback to it (open_fn argument).
 *
 * Once registered, you can `loadfile myprotocol://myfile`. Your open_fn will be
 * invoked with the URI and you must fill out the provided mpv_stream_cb_info
 * struct. This includes your stream callbacks (like read_fn), and an opaque
 * cookie, which will be passed as the first argument to all the remaining
 * stream callbacks.
 *
 * Note that your custom callbacks must not invoke libmpv APIs as that would
 * cause a deadlock. (Unless you call a different mpv_handle than the one the
 * callback was registered for, and the mpv_handles refer to different mpv
 * instances.)
 *
 * Stream lifetime
 * ---------------
 *
 * A stream remains valid until its close callback has been called. It's up to
 * libmpv to call the close callback, and the libmpv user cannot close it
 * directly with the stream_cb API.
 *
 * For example, if you consider your custom stream to become suddenly invalid
 * (maybe because the underlying stream died), libmpv will continue using your
 * stream. All you can do is returning errors from each callback, until libmpv
 * gives up and closes it.
 *
 * Protocol registration and lifetime
 * ----------------------------------
 *
 * Protocols remain registered until the mpv instance is terminated. This means
 * in particular that it can outlive the mpv_handle that was used to register
 * it, but once mpv_terminate_destroy() is called, your registered callbacks
 * will not be called again.
 *
 * Protocol unregistration is finished after the mpv core has been destroyed
 * (e.g. after mpv_terminate_destroy() has returned).
 *
 * If you do not call mpv_terminate_destroy() yourself (e.g. plugin-style code),
 * you will have to deal with the registration or even streams outliving your
 * code. Here are some possible ways to do this:
 * - call mpv_terminate_destroy(), which destroys the core, and will make sure
 *   all streams are closed once this function returns
 * - you refcount all resources your stream "cookies" reference, so that it
 *   doesn't matter if streams live longer than expected
 * - create "cancellation" semantics: after your protocol has been unregistered,
 *   notify all your streams that are still opened, and make them drop all
 *   referenced resources - then return errors from the stream callbacks as
 *   long as the stream is still opened
 *
 */

/**
 * Read callback used to implement a custom stream. The semantics of the
 * callback match read(2) in blocking mode. Short reads are allowed (you can
 * return less bytes than requested, and libmpv will retry reading the rest
 * with another call). If no data can be immediately read, the callback must
 * block until there is new data. A return of 0 will be interpreted as final
 * EOF, although libmpv might retry the read, or seek to a different position.
 *
 * @param cookie opaque cookie identifying the stream,
 *               returned from mpv_stream_cb_open_fn
 * @param buf buffer to read data into
 * @param size of the buffer
 * @return number of bytes read into the buffer
 * @return 0 on EOF
 * @return -1 on error
 */
typedef int64_t (*mpv_stream_cb_read_fn)(void *cookie, char *buf, uint64_t nbytes);

/**
 * Seek callback used to implement a custom stream.
 *
 * Note that mpv will issue a seek to position 0 immediately after opening. This
 * is used to test whether the stream is seekable (since seekability might
 * depend on the URI contents, not just the protocol). Return
 * MPV_ERROR_UNSUPPORTED if seeking is not implemented for this stream. This
 * seek also serves to establish the fact that streams start at position 0.
 *
 * This callback can be NULL, in which it behaves as if always returning
 * MPV_ERROR_UNSUPPORTED.
 *
 * @param cookie opaque cookie identifying the stream,
 *               returned from mpv_stream_cb_open_fn
 * @param offset target absolut stream position
 * @return the resulting offset of the stream
 *         MPV_ERROR_UNSUPPORTED or MPV_ERROR_GENERIC if the seek failed
 */
typedef int64_t (*mpv_stream_cb_seek_fn)(void *cookie, int64_t offset);

/**
 * Size callback used to implement a custom stream.
 *
 * Return MPV_ERROR_UNSUPPORTED if no size is known.
 *
 * This callback can be NULL, in which it behaves as if always returning
 * MPV_ERROR_UNSUPPORTED.
 *
 * @param cookie opaque cookie identifying the stream,
 *               returned from mpv_stream_cb_open_fn
 * @return the total size in bytes of the stream
 */
typedef int64_t (*mpv_stream_cb_size_fn)(void *cookie);

/**
 * Close callback used to implement a custom stream.
 *
 * @param cookie opaque cookie identifying the stream,
 *               returned from mpv_stream_cb_open_fn
 */
typedef void (*mpv_stream_cb_close_fn)(void *cookie);

/**
 * Cancel callback used to implement a custom stream.
 *
 * This callback is used to interrupt any current or future read and seek
 * operations. It will be called from a separate thread than the demux
 * thread, and should not block.
 *
 * This callback can be NULL.
 *
 * Available since API 1.106.
 *
 * @param cookie opaque cookie identifying the stream,
 *               returned from mpv_stream_cb_open_fn
 */
typedef void (*mpv_stream_cb_cancel_fn)(void *cookie);

/**
 * See mpv_stream_cb_open_ro_fn callback.
 */
typedef struct mpv_stream_cb_info {
    /**
     * Opaque user-provided value, which will be passed to the other callbacks.
     * The close callback will be called to release the cookie. It is not
     * interpreted by mpv. It doesn't even need to be a valid pointer.
     *
     * The user sets this in the mpv_stream_cb_open_ro_fn callback.
     */
    void *cookie;

    /**
     * Callbacks set by the user in the mpv_stream_cb_open_ro_fn callback. Some
     * of them are optional, and can be left unset.
     *
     * The following callbacks are mandatory: read_fn, close_fn
     */
    mpv_stream_cb_read_fn read_fn;
    mpv_stream_cb_seek_fn seek_fn;
    mpv_stream_cb_size_fn size_fn;
    mpv_stream_cb_close_fn close_fn;
    mpv_stream_cb_cancel_fn cancel_fn; /* since API 1.106 */
} mpv_stream_cb_info;

/**
 * Open callback used to implement a custom read-only (ro) stream. The user
 * must set the callback fields in the passed info struct. The cookie field
 * also can be set to store state associated to the stream instance.
 *
 * Note that the info struct is valid only for the duration of this callback.
 * You can't change the callbacks or the pointer to the cookie at a later point.
 *
 * Each stream instance created by the open callback can have different
 * callbacks.
 *
 * The close_fn callback will terminate the stream instance. The pointers to
 * your callbacks and cookie will be discarded, and the callbacks will not be
 * called again.
 *
 * @param user_data opaque user data provided via mpv_stream_cb_add()
 * @param uri name of the stream to be opened (with protocol prefix)
 * @param info fields which the user should fill
 * @return 0 on success, MPV_ERROR_LOADING_FAILED if the URI cannot be opened.
 */
typedef int (*mpv_stream_cb_open_ro_fn)(void *user_data, char *uri,
                                        mpv_stream_cb_info *info);

/**
 * Add a custom stream protocol. This will register a protocol handler under
 * the given protocol prefix, and invoke the given callbacks if an URI with the
 * matching protocol prefix is opened.
 *
 * The "ro" is for read-only - only read-only streams can be registered with
 * this function.
 *
 * The callback remains registered until the mpv core is registered.
 *
 * If a custom stream with the same name is already registered, then the
 * MPV_ERROR_INVALID_PARAMETER error is returned.
 *
 * @param protocol protocol prefix, for example "foo" for "foo://" URIs
 * @param user_data opaque pointer passed into the mpv_stream_cb_open_fn
 *                  callback.
 * @return error code
 */
MPV_EXPORT int mpv_stream_cb_add_ro(mpv_handle *ctx, const char *protocol, void *user_data,
                                    mpv_stream_cb_open_ro_fn open_fn);

#ifdef __cplusplus
}
#endif

#endif
