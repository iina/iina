//
//  VirtualRenderContext.swift
//  iina-server
//
//  Created by Collider LI on 19/2/2019.
//  Copyright © 2019 lhc. All rights reserved.
//

import Foundation
import AppKit
import CoreGraphics
import OpenGL.GL
import OpenGL.GL3

class VirtualRenderContext {

  struct Size {
    var width: Int
    var height: Int
  }

  var openGLContext: NSOpenGLContext
  var texture: GLuint = GLuint()
  var fbo: GLuint = GLuint()

  var size: Size
  var mpvController: SimpleMPVController

  var queue =  DispatchQueue(label: "com.colliderli.iina.server-render")

  init(size: Size, mpvController: SimpleMPVController) {
    let attributes: [NSOpenGLPixelFormatAttribute] = [
      UInt32(NSOpenGLPFADoubleBuffer),
      UInt32(NSOpenGLPFAAccelerated),
      0
    ]
    let pixelFormat = NSOpenGLPixelFormat(attributes: attributes)!
    self.openGLContext = NSOpenGLContext(format: pixelFormat, share: nil)!
    self.size = size
    self.mpvController = mpvController
  }

  func prepareVideoFrameBuffer() {
    openGLContext.makeCurrentContext()
    openGLContext.lock()
    // if texture or fbo exists
    if texture != 0 {
      glDeleteTextures(1, &texture)
    }
    if fbo != 0 {
      glDeleteFramebuffers(1, &fbo)
    }
    // create frame buffer
    glGenFramebuffers(GLsizei(1), &fbo)
    assert(fbo > 0, "Cannot generate fbo")
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
    // create texture
    glGenTextures(1, &texture)
    assert(texture > 0, "Cannot generate texture")
    glBindTexture(GLenum(GL_TEXTURE_2D), texture)
    // bing texture
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
    glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA8, GLsizei(size.width), GLsizei(size.height), 0, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
    glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), texture, 0)
    // check whether frame buffer is completed
    let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
    assert(status == GLenum(GL_FRAMEBUFFER_COMPLETE), "Frame buffer check failed")
    // bind back to main framebuffer (may not necessary)
    glBindTexture(GLenum(GL_TEXTURE_2D), 0)
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    openGLContext.unlock()
  }

  func drawFrame() {
    guard controller.renderContextAvailable else { return }
    controller.cleanupLock.lock()

    openGLContext.lock()
    openGLContext.makeCurrentContext()

    var dims: [GLint] = [0, 0, 0, 0]
    glGetIntegerv(GLenum(GL_VIEWPORT), &dims);

    var flip: CInt = 0

    if let context = mpvController.mpvRenderContext {
      var data = mpv_opengl_fbo(fbo: Int32(fbo),
                                w: Int32(size.width),
                                h: Int32(size.height),
                                internal_format: 0)
      var params: [mpv_render_param] = [
        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: &data),
        mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: &flip),
        mpv_render_param()
      ]
      mpv_render_context_render(context, &params);
    } else {
      glClearColor(0, 0, 0, 1)
      glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
    }
    openGLContext.update()
    openGLContext.flushBuffer()

    mpvController.mpvReportSwap()

    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
    let pointer = UnsafeMutableRawPointer.allocate(byteCount: size.width * size.height * 4, alignment: 0)
    glReadPixels(0, 0, GLsizei(size.width), GLsizei(size.height), GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), pointer)
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)

    let f = pointer.bindMemory(to: UInt8.self, capacity: size.width * size.height)

    let cgContext = CGContext(data: pointer, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: size.width * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    if let image = cgContext?.makeImage() {
      let rep = NSBitmapImageRep(cgImage: image)
      let data = rep.representation(using: .jpeg, properties: [:])
      mpvController.socket?.dataBuffer = data
    }


    openGLContext.unlock()
    controller.cleanupLock.unlock()
  }

}
