//
//  VR2DRenderer.swift
//  iina
//
//  The OpenGL side of the VR2D reprojection pass.
//
//  Normally `ViewLayer` hands mpv the layer's own framebuffer and mpv draws
//  straight into it. With reprojection on, mpv is pointed at an offscreen
//  texture instead and a single full-screen triangle draws the flattened view
//  from that texture into the layer's framebuffer.
//
//  Two details drive the design:
//
//  - mpv renders *fitted* into whatever framebuffer it is given, because
//    `keepaspect` is on. Handing it a window-sized framebuffer would produce a
//    letterboxed, already-downscaled image, and reprojecting that would sample
//    black bars and throw away most of the source resolution. So the offscreen
//    texture is the video's own display size, where mpv's scale is 1:1 and
//    there are no bars.
//  - mpv expects the OpenGL state to be at its defaults on entry and leaves it
//    that way on exit, apart from the viewport, scissor, blend function and
//    clear colour (see `render_gl.h`). Anything this pass binds therefore has
//    to be unbound before the next frame, or the corruption shows up inside
//    mpv's renderer where it looks like a decoder bug.
//

import Cocoa
import OpenGL.GL
import OpenGL.GL3

final class VR2DRenderer {

  /// Everything the pass needs for one frame.
  struct Params {
    var source: VR2DSource
    var view: VR2DView
    var eye: VR2DEye
  }

  private var program: GLuint = 0
  private var vao: GLuint = 0
  private var srcTex: GLuint = 0
  private var srcFBO: GLuint = 0
  private var srcWidth: GLsizei = 0
  private var srcHeight: GLsizei = 0
  private var srcIsFloat = false
  private var uniformLocations: [String: GLint] = [:]

  /// Set after a failure so we log once and fall back rather than retrying
  /// sixty times a second.
  private(set) var isBroken = false

  /// `false` until mpv has rendered into the offscreen buffer at its current
  /// size. A freshly allocated texture holds nothing, so the pass cannot reuse
  /// it and mpv has to run once first.
  private(set) var sourceHasContent = false

  func markSourceRendered() {
    sourceHasContent = true
  }

  private lazy var subsystem = Logger.makeSubsystem("vr2d", ["view.3d"])

  // MARK: - Offscreen target

  /// Make sure there is an offscreen colour buffer of this size, and return the
  /// framebuffer mpv should render into.
  ///
  /// - Important: Must be called with the layer's OpenGL context current.
  func acquireSourceFramebuffer(width: Int, height: Int, float: Bool) -> GLuint? {
    guard !isBroken, width > 0, height > 0 else { return nil }

    let w = GLsizei(width), h = GLsizei(height)
    if srcFBO != 0 && srcWidth == w && srcHeight == h && srcIsFloat == float {
      return srcFBO
    }
    // About to be reallocated, so whatever it held is gone.
    sourceHasContent = false

    if srcTex == 0 {
      glGenTextures(1, &srcTex)
      glBindTexture(GLenum(GL_TEXTURE_2D), srcTex)
      glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
      glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
      // Wrapping for a 360° source is done in the shader, where it can happen
      // before the eye transform packs two eyes into one texture.
      glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
      glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
    } else {
      glBindTexture(GLenum(GL_TEXTURE_2D), srcTex)
    }

    glTexImage2D(GLenum(GL_TEXTURE_2D), 0,
                 float ? GL_RGBA16F : GL_RGBA8, w, h, 0,
                 GLenum(GL_RGBA), GLenum(float ? GL_HALF_FLOAT : GL_UNSIGNED_BYTE), nil)
    glBindTexture(GLenum(GL_TEXTURE_2D), 0)

    if srcFBO == 0 {
      glGenFramebuffers(1, &srcFBO)
    }
    var previousFBO: GLint = 0
    glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &previousFBO)
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), srcFBO)
    glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                           GLenum(GL_TEXTURE_2D), srcTex, 0)
    let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), GLuint(previousFBO))

    guard status == GLenum(GL_FRAMEBUFFER_COMPLETE) else {
      Logger.log("VR2D: offscreen framebuffer incomplete (status \(status)) at \(width)x\(height)",
                 level: .error, subsystem: subsystem)
      isBroken = true
      return nil
    }

    srcWidth = w
    srcHeight = h
    srcIsFloat = float
    Logger.log("VR2D: offscreen target \(width)x\(height) \(float ? "RGBA16F" : "RGBA8")",
               level: .verbose, subsystem: subsystem)
    return srcFBO
  }

  // MARK: - The pass

  /// Draw the reprojected view into `target`.
  ///
  /// - Important: Must be called with the layer's OpenGL context current, after
  ///   mpv has rendered into the framebuffer returned by
  ///   `acquireSourceFramebuffer`.
  func draw(target: GLint, width: GLsizei, height: GLsizei, params: Params) {
    guard !isBroken, srcTex != 0, ensureProgram() else { return }

    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), GLuint(target))
    glViewport(0, 0, width, height)

    glUseProgram(program)
    glActiveTexture(GLenum(GL_TEXTURE0))
    glBindTexture(GLenum(GL_TEXTURE_2D), srcTex)
    glUniform1i(location("uSrc"), 0)

    setUniforms(params, width: width, height: height)

    glBindVertexArray(vao)
    glDrawArrays(GLenum(GL_TRIANGLES), 0, 3)

    // Back to the defaults mpv expects to find.
    glBindVertexArray(0)
    glBindTexture(GLenum(GL_TEXTURE_2D), 0)
    glUseProgram(0)
  }

  private func setUniforms(_ params: Params, width: GLsizei, height: GLsizei) {
    let source = params.source
    let fov = VR2DGeometry.fovComponents(params.view.fov, Double(width), Double(height))
    let toRadians = Double.pi / 180
    glUniform2f(location("uTanHalfFov"),
                GLfloat(tan(fov.h / 2 * toRadians)),
                GLfloat(tan(fov.v / 2 * toRadians)))

    var rotation = VR2DGeometry.rotationMatrix(yaw: params.view.yaw, pitch: params.view.pitch)
    glUniformMatrix3fv(location("uRot"), 1, GLboolean(GL_FALSE), &rotation)

    glUniform1i(location("uProjection"), GLint(source.projection.rawValue))
    glUniform2f(location("uInFovHalf"),
                GLfloat(source.inHFov / 2 * toRadians),
                GLfloat(source.inVFov / 2 * toRadians))

    let eye = VR2DGeometry.eyeTransform(layout: source.layout, swapEyes: source.swapEyes, eye: params.eye)
    glUniform4f(location("uEye"),
                GLfloat(eye.scale.0), GLfloat(eye.scale.1),
                GLfloat(eye.offset.0), GLfloat(eye.offset.1))
  }

  // MARK: - Program

  private func ensureProgram() -> Bool {
    guard program == 0 else { return true }

    guard let vertex = compile(VR2DShader.vertex, type: GLenum(GL_VERTEX_SHADER)),
          let fragment = compile(VR2DShader.fragment, type: GLenum(GL_FRAGMENT_SHADER)) else {
      isBroken = true
      return false
    }
    defer {
      glDeleteShader(vertex)
      glDeleteShader(fragment)
    }

    let handle = glCreateProgram()
    glAttachShader(handle, vertex)
    glAttachShader(handle, fragment)
    glBindFragDataLocation(handle, 0, "fragColor")
    glLinkProgram(handle)

    var status: GLint = 0
    glGetProgramiv(handle, GLenum(GL_LINK_STATUS), &status)
    guard status == GL_TRUE else {
      Logger.log("VR2D: shader link failed: \(programLog(handle))", level: .error, subsystem: subsystem)
      glDeleteProgram(handle)
      isBroken = true
      return false
    }

    program = handle
    glGenVertexArrays(1, &vao)

    let version = glGetString(GLenum(GL_SHADING_LANGUAGE_VERSION)).map { String(cString: $0) } ?? "unknown"
    Logger.log("VR2D: shader ready, GLSL \(version)", subsystem: subsystem)
    return true
  }

  private func compile(_ source: String, type: GLenum) -> GLuint? {
    let shader = glCreateShader(type)
    var cString = (source as NSString).utf8String
    glShaderSource(shader, 1, &cString, nil)
    glCompileShader(shader)

    var status: GLint = 0
    glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &status)
    guard status == GL_TRUE else {
      let kind = type == GLenum(GL_VERTEX_SHADER) ? "vertex" : "fragment"
      Logger.log("VR2D: \(kind) shader failed to compile: \(shaderLog(shader))",
                 level: .error, subsystem: subsystem)
      glDeleteShader(shader)
      return nil
    }
    return shader
  }

  private func shaderLog(_ shader: GLuint) -> String {
    var length: GLint = 0
    glGetShaderiv(shader, GLenum(GL_INFO_LOG_LENGTH), &length)
    guard length > 0 else { return "no log" }
    var buffer = [GLchar](repeating: 0, count: Int(length))
    glGetShaderInfoLog(shader, length, nil, &buffer)
    return String(cString: buffer)
  }

  private func programLog(_ handle: GLuint) -> String {
    var length: GLint = 0
    glGetProgramiv(handle, GLenum(GL_INFO_LOG_LENGTH), &length)
    guard length > 0 else { return "no log" }
    var buffer = [GLchar](repeating: 0, count: Int(length))
    glGetProgramInfoLog(handle, length, nil, &buffer)
    return String(cString: buffer)
  }

  private func location(_ name: String) -> GLint {
    if let cached = uniformLocations[name] { return cached }
    let location = glGetUniformLocation(program, name)
    uniformLocations[name] = location
    return location
  }

  // MARK: - Teardown

  /// - Important: Must be called with the layer's OpenGL context current.
  func dispose() {
    if srcFBO != 0 { glDeleteFramebuffers(1, &srcFBO); srcFBO = 0 }
    if srcTex != 0 { glDeleteTextures(1, &srcTex); srcTex = 0 }
    if vao != 0 { glDeleteVertexArrays(1, &vao); vao = 0 }
    if program != 0 { glDeleteProgram(program); program = 0 }
    uniformLocations.removeAll()
    srcWidth = 0
    srcHeight = 0
    sourceHasContent = false
  }
}
