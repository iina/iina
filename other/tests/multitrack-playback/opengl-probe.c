// Exercise libmpv's real OpenGL path, optionally with the display ICC profile.
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl3.h>
#include <mpv/client.h>
#include <mpv/render_gl.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define FN(name) __typeof__(name) *p_##name = dlsym(lib, #name)
static void *gl_library;

static void *get_proc(void *context, const char *name)
{
    return dlsym(gl_library, name);
}

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr, "Usage: opengl-probe libmpv video [graph] [ICC profile]\n");
        return 1;
    }
    setbuf(stdout, NULL);
    CGLPixelFormatAttribute attributes[] = {
        kCGLPFAOpenGLProfile,
        (CGLPixelFormatAttribute)kCGLOGLPVersion_3_2_Core,
        kCGLPFAAccelerated, 0
    };
    CGLPixelFormatObj format;
    GLint count;
    CGLContextObj context;
    if (CGLChoosePixelFormat(attributes, &format, &count) ||
        CGLCreateContext(format, NULL, &context) || CGLSetCurrentContext(context))
        return 2;
    gl_library = dlopen("/System/Library/Frameworks/OpenGL.framework/OpenGL", RTLD_NOW);
    void *lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!lib) {
        puts(dlerror());
        return 3;
    }
    FN(mpv_create);
    FN(mpv_set_option_string);
    FN(mpv_initialize);
    FN(mpv_command);
    FN(mpv_wait_event);
    FN(mpv_render_context_create);
    FN(mpv_render_context_update);
    FN(mpv_render_context_render);
    FN(mpv_render_context_report_swap);
    FN(mpv_render_context_free);
    FN(mpv_terminate_destroy);

    mpv_handle *player = p_mpv_create();
    const char *keys[] = {"config", "terminal", "msg-level", "vo", "ao",
                          "pause", "hwdec", "start", "keep-open", "osd-level"};
    const char *values[] = {"no", "yes", "all=warn", "libmpv", "null",
                            "yes", "no", "12", "yes", "0"};
    for (int i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
        if (p_mpv_set_option_string(player, keys[i], values[i]) < 0)
            return 4;
    }
    if (argc > 3 && !strcmp(argv[3], "graph")) {
        if (p_mpv_set_option_string(player, "lavfi-complex",
            "[aid1][aid2][aid3][aid4]amix@iina_audio_mix=inputs=4:normalize=0:"
            "weights='1 0 0 0',alimiter=level=false:latency=true[ao]") < 0)
            return 4;
    }
    if (argc > 4 && p_mpv_set_option_string(player, "icc-profile", argv[4]) < 0)
        return 4;
    if (p_mpv_initialize(player) < 0)
        return 5;

    mpv_opengl_init_params init = {get_proc, NULL};
    int advanced = 1;
    mpv_render_param parameters[] = {
        {MPV_RENDER_PARAM_API_TYPE, "opengl"},
        {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &init},
        {MPV_RENDER_PARAM_ADVANCED_CONTROL, &advanced}, {0}
    };
    mpv_render_context *render = NULL;
    int result = p_mpv_render_context_create(&render, player, parameters);
    printf("create %d\n", result);
    if (result < 0)
        return 6;

    GLuint texture, framebuffer;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 128, 72, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glGenFramebuffers(1, &framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
        return 7;
    const char *load[] = {"loadfile", argv[2], NULL};
    if (p_mpv_command(player, load) < 0)
        return 7;

    mpv_opengl_fbo target = {(int)framebuffer, 128, 72, GL_RGBA8};
    int block = 0;
    mpv_render_param draw[] = {
        {MPV_RENDER_PARAM_OPENGL_FBO, &target},
        {MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &block}, {0}
    };
    unsigned char pixels[128 * 72 * 4];
    int frames = 0, maximum = 0, visible = 0;
    time_t deadline = time(NULL) + 12;
    while (time(NULL) < deadline) {
        p_mpv_wait_event(player, .01);
        if (!(p_mpv_render_context_update(render) & MPV_RENDER_UPDATE_FRAME))
            continue;
        result = p_mpv_render_context_render(render, draw);
        p_mpv_render_context_report_swap(render);
        frames++;
        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
        glFinish();
        glReadPixels(0, 0, 128, 72, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
        visible = 0;
        for (int i = 0; i < sizeof(pixels); i += 4) {
            int pixel = pixels[i];
            if (pixels[i + 1] > pixel) pixel = pixels[i + 1];
            if (pixels[i + 2] > pixel) pixel = pixels[i + 2];
            if (pixel > maximum) maximum = pixel;
            visible += pixel > 30;
        }
        GLenum error = glGetError();
        printf("frame %d render %d maxRGB %d visiblePixels %d glError %x\n",
               frames, result, maximum, visible, error);
        if (result < 0 || error != GL_NO_ERROR)
            break;
        if (maximum > 30 && visible > 100)
            break;
    }
    p_mpv_render_context_free(render);
    p_mpv_terminate_destroy(player);
    glDeleteFramebuffers(1, &framebuffer);
    glDeleteTextures(1, &texture);
    CGLSetCurrentContext(NULL);
    CGLDestroyContext(context);
    CGLDestroyPixelFormat(format);
    return result >= 0 && maximum > 30 && visible > 100 ? 0 : 8;
}
