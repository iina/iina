 //
//  VideoView.swift
//  mpvx
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa
import OpenGL.GL
import OpenGL.GL3

func mpvGLUpdate(_ ctx: UnsafeMutablePointer<Void>?) -> Void {
  let videoView = unsafeBitCast(ctx, to: VideoView.self)
  videoView.mpvGLQueue.async {
    videoView.drawFrame()
  }
}

class VideoView: NSOpenGLView {
  
  let vertexShaderName = "vertexShader"
  let fragmentShaderName = "fragmentShader"
  
  /** The mpv opengl-cb context */
  var mpvGLContext: OpaquePointer! {
    didSet {
      // Initialize the mpv OpenGL state.
      mpv_opengl_cb_init_gl(mpvGLContext, nil, getGLProcAddress, nil)
      // Set the callback that notifies you when a new video frame is available, or requires a redraw.
      mpv_opengl_cb_set_update_callback(mpvGLContext, mpvGLUpdate, UnsafeMutablePointer<Void>(unsafeAddress(of: self)))
    }
  }
  
  /** The OpenGL context for drawing to fbo in mpvGLQueue */
  var renderContext: NSOpenGLContext!
  
  /**
   The queue for drawing to fbo.
   If draw in main thread, it will block UI such as resizing
   */
  lazy var mpvGLQueue: DispatchQueue = DispatchQueue(label: "mpvx.mpvgl", attributes: .serial)
  
  /** Video size for allocating fbo texture */
  var videoSize: NSSize? {
    didSet {
      prepareVideoFrameBuffer()
      setUpDisplayLink()
      startDisplayLink()
    }
  }
  
  /** Display link */
  var displayLink: CVDisplayLink?
  
  /** Objects for drawing to fbo */
  var program: GLuint = GLuint()
  var texture: GLuint = GLuint(0)
  var fbo: GLuint = GLuint(0)
  var vao: GLuint = GLuint()
  var vbo: GLuint = GLuint()
  var texUniform: GLint = GLint()
  var testi = GLint()
  let vertexData: [GLfloat] = [
    // X     Y      U    V
    -1.0, -1.0,   0.0, 0.0,
    -1.0,  1.0,   0.0, 1.0,
     1.0,  1.0,   1.0, 1.0,
     1.0,  1.0,   1.0, 1.0,
     1.0, -1.0,   1.0, 0.0,
    -1.0, -1.0,   0.0, 0.0,
  ]
  
  /** Whether mpv started drawing */
  var started: Bool = false
  
  // MARK: - Attributes
  
  override var mouseDownCanMoveWindow: Bool {
    return true
  }
  
  override var isOpaque: Bool {
    return true
  }
  
  // MARK: - Init
  
  override init(frame: CGRect) {
    // init context
    let attributes: [NSOpenGLPixelFormatAttribute] = [
      UInt32(NSOpenGLPFADoubleBuffer),
      UInt32(NSOpenGLPFAAccelerated),
      UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
      0
    ]
    let pixelFormat = NSOpenGLPixelFormat(attributes: attributes)!
    super.init(frame: frame, pixelFormat: pixelFormat)!
    guard openGLContext != nil else {
      Utility.fatal("Cannot initialize OpenGL Context")
      return
    }
    
    // set up another context for offscreen render thread
    renderContext = NSOpenGLContext(format: pixelFormat, share: openGLContext)!
    
    // init shader
    let vertexShader = initShader(vertexShaderName, type: GLenum(GL_VERTEX_SHADER))
    let fragShader = initShader(fragmentShaderName, type: GLenum(GL_FRAGMENT_SHADER))
    
    // create program
    program = glCreateProgram()
    glAttachShader(program, vertexShader)
    glAttachShader(program, fragShader)
    glLinkProgram(program)
    var flag = GLint()
    glGetProgramiv(program, GLenum(GL_LINK_STATUS), &flag)
    Utility.assert(flag != GL_FALSE, "Cannot link program")
    glDetachShader(program, vertexShader)
    glDetachShader(program, fragShader)
    
    // set up vbo and vao
    glGenVertexArrays(1, &vao)
    glBindVertexArray(vao)
    glGenBuffers(1, &vbo)
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vbo)
    glBufferData(GLenum(GL_ARRAY_BUFFER), sizeof(GLfloat.self) * vertexData.count, vertexData, GLenum(GL_STATIC_DRAW))
    let stride = GLsizei(4*sizeof(GLfloat.self))
    // connect x, y -> vert
    let vertPtr = glGetAttribLocation(program, "vert")
    Utility.assert(vertPtr != -1, "Cannot get location for vertex variable")
    glEnableVertexAttribArray(GLuint(vertPtr))
    glVertexAttribPointer(GLuint(vertPtr), 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), stride, nil)
    // connect u, v -> vertTexCoord
    let offset = 2*sizeof(GLfloat.self)
    let vertTexCoordPtr = glGetAttribLocation(program, "vertTexCoord")
    Utility.assert(vertTexCoordPtr != -1, "Cannot get location for texture coord variable")
    glEnableVertexAttribArray(GLuint(vertTexCoordPtr))
    glVertexAttribPointer(GLuint(vertTexCoordPtr), 2, GLenum(GL_FLOAT), GLboolean(GL_TRUE), stride, UnsafePointer<GLuint>(bitPattern: offset))
    glBindVertexArray(0)
    glBindFragDataLocation(program, 0, "color")
    // get texture uniform location
    texUniform = glGetUniformLocation(program, "tex")
    Utility.assert(texUniform != -1, "Cannot get location for texture uniform variable")
    
    // other settings
    autoresizingMask = [.viewWidthSizable, .viewHeightSizable]
    wantsBestResolutionOpenGLSurface = true
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    // uninit mpv gl
    mpv_opengl_cb_set_update_callback(mpvGLContext, nil, nil)
    mpv_opengl_cb_uninit_gl(mpvGLContext)
    // delete framebuffer
    glDeleteTextures(1, &texture)
    glDeleteFramebuffers(1, &fbo)
  }
  
  // MARK: - Preparation
  
  override func prepareOpenGL() {
    var swapInt = GLint(1)
    openGLContext!.setValues(&swapInt, for: NSOpenGLCPSwapInterval)
  }
  
  /** Set up the frame buffer needed for offline rendering. */
  private func prepareVideoFrameBuffer() {
    let size = self.videoSize!
    openGLContext!.makeCurrentContext()
    // if texture or fbo exists
//    if texture != 0 {
//      glDeleteTextures(1, &texture)
//    }
//    if fbo != 0 {
//      glDeleteFramebuffers(1, &fbo)
//    }
    // create frame buffer
    glGenFramebuffers(GLsizei(1), &fbo)
    Utility.assert(fbo > 0, "Cannot generate fbo")
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
    // create texture
    glGenTextures(1, &texture)
    Utility.assert(texture > 0, "Cannot generate texture")
    glBindTexture(GLenum(GL_TEXTURE_2D), texture)
    // bing texture
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
    glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA8, GLsizei(size.width), GLsizei(size.height), 0, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
    glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), texture, 0)
    // check whether frame buffer is completed
    let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
    Utility.assert(status == GLenum(GL_FRAMEBUFFER_COMPLETE), "Frame buffer check failed")
    // bind back to main framebuffer (may not necessary)
    glBindTexture(GLenum(GL_TEXTURE_2D), 0)
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
  }
  
  /**
   Set up display link.
   */
  func setUpDisplayLink() {
    // The callback function
    func displayLinkCallback(
      _ displayLink: CVDisplayLink, _ inNow: UnsafePointer<CVTimeStamp>,
      _ inOutputTime: UnsafePointer<CVTimeStamp>,
      _ flagsIn: CVOptionFlags,
      _ flagsOut: UnsafeMutablePointer<CVOptionFlags>,
      _ context: UnsafeMutablePointer<Void>?) -> CVReturn {
      let videoView = unsafeBitCast(context, to: VideoView.self)
      videoView.drawVideo()
      return kCVReturnSuccess
    }
    //
    CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
    if let link = displayLink {
      checkCVReturn(CVDisplayLinkSetOutputCallback(link, displayLinkCallback, UnsafeMutablePointer<Void>(unsafeAddress(of: self))))
    } else {
      Utility.fatal("Failed to create display link")
    }
    if let context = self.openGLContext?.cglContextObj, format = self.pixelFormat?.cglPixelFormatObj {
      checkCVReturn(CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(displayLink!, context, format))
    } else {
      Utility.fatal("Failed to set display with nil opengl context")
    }
  }
  
  func startDisplayLink() {
    CVDisplayLinkStart(displayLink!)
  }
  
  // MARK: - Drawing
  
  /** Draw offscreen to the framebuffer. */
  func drawFrame() {
    if !started {
      started = true
    }
    renderContext.lock()
    renderContext.makeCurrentContext()
    if let context = self.mpvGLContext {
      mpv_opengl_cb_draw(context, Int32(fbo), Int32(videoSize!.width), -(Int32)(videoSize!.height))
      ignoreGLError()
    } else {
      glClearColor(0, 0, 0, 1)
      glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
    }
    renderContext.update()
    renderContext.flushBuffer()
    // report flip to mpv
    if let context = self.mpvGLContext {
      mpv_opengl_cb_report_flip(context, 0)
    }
    renderContext.unlock()
  }
  
  /** Draw the video to view from framebuffer. */
  func drawVideo() {
    openGLContext?.lock()
    openGLContext?.makeCurrentContext()
    
    // should clear color especially before started receiving frames
    glClearColor(0, 0, 0, 1)
    glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
    
    if started {
      glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
      glUseProgram(program)
      
      glActiveTexture(GLenum(GL_TEXTURE0))
      glBindTexture(GLenum(GL_TEXTURE_2D), texture)
      glUniform1i(texUniform, 0)
      
      glBindVertexArray(vao)
      glDrawArrays(GLenum(GL_TRIANGLES), 0, 6)
      glBindVertexArray(0)
      
      glBindTexture (GLenum(GL_TEXTURE_2D), 0)
      glUseProgram(0)
    }
    openGLContext?.flushBuffer()
    openGLContext?.unlock()
  }
  
  /** This function is mainly called when bound changes, e.g. resize window */
  override func draw(_ dirtyRect: NSRect) {
//    drawVideo()
  }
  
  // MARK: - Utils
  
  /** Load a shader. */
  private func initShader(_ name: String, type: GLenum) -> GLuint {
    // load shader
    let shaderPath = Bundle.main.pathForResource(name, ofType: "glsl")!
    var shaderContent: NSString? = nil
    do {
      shaderContent = try NSString(contentsOfFile: shaderPath, encoding: String.Encoding.utf8.rawValue)
    } catch let error as NSError{
      Utility.fatal("Cannot load \(name): \(error)")
    }
    var shaderString = shaderContent!.utf8String
    var shaderStringLength = GLint(shaderContent!.length)
    
    // create & compile shader
    let shader = glCreateShader(type)
    glShaderSource(shader, 1, &shaderString, &shaderStringLength)
    glCompileShader(shader)
    
    // check error
    var flag = GLint()
    glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &flag)
    Utility.assert(flag != GL_FALSE, "Cannot compile shader \(name)") {
      var len = GLsizei()
      let str = UnsafeMutablePointer<Int8>.init(allocatingCapacity: 2000)
      glGetShaderInfoLog(shader, GLsizei(2000), &len, str)
      Utility.log(String(cString: str))
    }
    
    return shader
  }
  
  /** Check the CVReturn value. */
  private func checkCVReturn(_ value: CVReturn) {
    Utility.assert(value == kCVReturnSuccess, "CVReturn not success: \(value)")
  }
  
  /** Check OpenGL error (for debug only). */
  func gle() {
    let e = glGetError()
    Swift.print(arc4random())
    switch e {
    case GLenum(GL_NO_ERROR):
      break
    case GLenum(GL_OUT_OF_MEMORY):
      Swift.print("GL_OUT_OF_MEMORY")
      break
    case GLenum(GL_INVALID_ENUM):
      Swift.print("GL_INVALID_ENUM")
      break
    case GLenum(GL_INVALID_VALUE):
      Swift.print("GL_INVALID_VALUE")
      break
    case GLenum(GL_INVALID_OPERATION):
      Swift.print("GL_INVALID_OPERATION")
      break
    case GLenum(GL_INVALID_FRAMEBUFFER_OPERATION):
      Swift.print("GL_INVALID_FRAMEBUFFER_OPERATION")
      break
    case GLenum(GL_STACK_UNDERFLOW):
      Swift.print("GL_STACK_UNDERFLOW")
      break
    case GLenum(GL_STACK_OVERFLOW):
      Swift.print("GL_STACK_OVERFLOW")
      break
    default:
      break
    }
  }
  
  func ignoreGLError() {
    glGetError()
  }

}
