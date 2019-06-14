//
//  KCLOpenGLImageView.m
//  H264Decoder
//
//  Created by Chentao on 2017/12/11.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import "KCLOpenGLImageView.h"
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import "KCLAssetsUtil.h"

enum { UNIFORM_Y, UNIFORM_UV, UNIFORM_COLOR_CONVERSION_MATRIX, NUM_UNIFORMS };
GLint uniforms[NUM_UNIFORMS];

enum { ATTRIB_VERTEX, ATTRIB_TEXCOORD, NUM_ATTRIBUTES };

// BT.709, which is the standard for HDTV.
static const GLfloat kColorConversion709[] = {
    1.164, 1.164, 1.164, 0.0, -0.213, 2.112, 1.793, -0.533, 0.0,
};

// BT.601 full range (ref: http://www.equasys.de/colorconversion.html)
static const GLfloat kColorConversion601FullRange[] = {
    1.0, 1.0, 1.0, 0.0, -0.343, 1.765, 1.4, -0.711, 0.0,
};

static const GLfloat quadVertexData[] = { -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, 1.0, 1.0 };

static const GLfloat quadTextureData[] = { // 正常坐标
    0, 1, 1, 1, 0, 0, 1, 0
};

@implementation KCLOpenGLImageView {
    EAGLContext *_context;

    GLuint _frameBufferHandle;
    GLuint _colorBufferHandle;

    CVOpenGLESTextureRef _lumaTexture;
    CVOpenGLESTextureRef _chromaTexture;
    CVOpenGLESTextureCacheRef _videoTextureCache;

    GLuint _program;

    GLint _backingWidth;
    GLint _backingHeight;

    const GLfloat *_preferredConversion;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentScaleFactor = [[UIScreen mainScreen] scale];

        [self setupLayer];
        [self setupContext];
        [self setupShaders];
        [self setupGL];

        _preferredConversion = kColorConversion709;
    }
    return self;
}

+ (Class)layerClass {
    return [CAEAGLLayer class];
}

#pragma mark -

- (void)setupLayer {
    CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
    eaglLayer.opaque = YES;
    eaglLayer.drawableProperties = @{ kEAGLDrawablePropertyRetainedBacking: [NSNumber numberWithBool:NO], kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8 };
}

- (void)setupContext {
    _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!_context) {
        NSLog(@"Failed to initialize OpenGLES 2.0 context");
        return;
    }

    // 设置为当前上下文
    if (![EAGLContext setCurrentContext:_context]) {
        NSLog(@"Failed to set current OpenGL context");
        return;
    }
}

- (void)setupBuffers {
    glDisable(GL_DEPTH_TEST);

    glDeleteFramebuffers(1, &_frameBufferHandle);
    _frameBufferHandle = 0;
    glDeleteRenderbuffers(1, &_colorBufferHandle);
    _colorBufferHandle = 0;

    glGenFramebuffers(1, &_frameBufferHandle);
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);

    glGenRenderbuffers(1, &_colorBufferHandle);
    glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);

    [_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);

    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorBufferHandle);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
    }
}

- (void)cleanUpTextures {
    if (_lumaTexture) {
        CFRelease(_lumaTexture);
        _lumaTexture = NULL;
    }

    if (_chromaTexture) {
        CFRelease(_chromaTexture);
        _chromaTexture = NULL;
    }

    CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
}

- (void)setupGL {
    glUseProgram(_program);

    glUniform1i(uniforms[UNIFORM_Y], 0);
    glUniform1i(uniforms[UNIFORM_UV], 1);

    // Create CVOpenGLESTextureCacheRef for optimal CVPixelBufferRef to GLES texture conversion.
    if (!_videoTextureCache) {
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _context, NULL, &_videoTextureCache);
        if (err != noErr) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
            return;
        }
    }
}

- (BOOL)setupShaders {
    GLuint vertShader, fragShader;
    NSURL *vertShaderURL, *fragShaderURL;

    _program = glCreateProgram();

    // Create and compile the vertex shader.
    vertShaderURL = [KCLAssetsUtil urlForResource:@"Shader" withExtension:@"vsh"];
    if (![self compileShader:&vertShader type:GL_VERTEX_SHADER URL:vertShaderURL]) {
        NSLog(@"Failed to compile vertex shader");
        return NO;
    }

    // Create and compile fragment shader.

    fragShaderURL = [KCLAssetsUtil urlForResource:@"Shader" withExtension:@"fsh"];
    if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER URL:fragShaderURL]) {
        NSLog(@"Failed to compile fragment shader");
        return NO;
    }

    // Attach vertex shader to program.
    glAttachShader(_program, vertShader);

    // Attach fragment shader to program.
    glAttachShader(_program, fragShader);

    // Bind attribute locations. This needs to be done prior to linking.
    glBindAttribLocation(_program, ATTRIB_VERTEX, "position");
    glBindAttribLocation(_program, ATTRIB_TEXCOORD, "texCoord");

    // Link the program.
    if (![self linkProgram:_program]) {
        NSLog(@"Failed to link program: %d", _program);

        if (vertShader) {
            glDeleteShader(vertShader);
            vertShader = 0;
        }
        if (fragShader) {
            glDeleteShader(fragShader);
            fragShader = 0;
        }
        if (_program) {
            glDeleteProgram(_program);
            _program = 0;
        }

        return NO;
    }

    // Get uniform locations.
    uniforms[UNIFORM_Y] = glGetUniformLocation(_program, "SamplerY");
    uniforms[UNIFORM_UV] = glGetUniformLocation(_program, "SamplerUV");
    uniforms[UNIFORM_COLOR_CONVERSION_MATRIX] = glGetUniformLocation(_program, "colorConversionMatrix");

    // Release vertex and fragment shaders.
    if (vertShader) {
        glDetachShader(_program, vertShader);
        glDeleteShader(vertShader);
    }
    if (fragShader) {
        glDetachShader(_program, fragShader);
        glDeleteShader(fragShader);
    }

    //    glEnableVertexAttribArray(ATTRIB_VERTEX);
    //    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
    //
    //    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
    //    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);

    // 更新顶点数据
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, quadVertexData);
    glEnableVertexAttribArray(ATTRIB_VERTEX);

    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, quadTextureData);
    glEnableVertexAttribArray(ATTRIB_TEXCOORD);

    return YES;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type URL:(NSURL *)URL {
    NSError *error;
    NSString *sourceString = [[NSString alloc] initWithContentsOfURL:URL encoding:NSUTF8StringEncoding error:&error];
    if (sourceString == nil) {
        NSLog(@"Failed to load vertex shader: %@", [error localizedDescription]);
        return NO;
    }

    GLint status;
    const GLchar *source;
    source = (GLchar *)[sourceString UTF8String];

    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);

    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO;
    }

    return YES;
}

- (BOOL)linkProgram:(GLuint)prog {
    GLint status;
    glLinkProgram(prog);

    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    return YES;
}

- (void)renderImageBuffer:(CVImageBufferRef)imageBuffer {
    if (UIApplicationStateActive == UIApplication.sharedApplication.applicationState) {

        [self setupBuffers];

        CVReturn err;
        if (imageBuffer != NULL) {
            int frameWidth = (int)CVPixelBufferGetWidth(imageBuffer);
            int frameHeight = (int)CVPixelBufferGetHeight(imageBuffer);

            _imageSize = CGSizeMake(frameWidth, frameHeight);

            if (!_videoTextureCache) {
                NSLog(@"No video texture cache");
                return;
            }
            if ([EAGLContext currentContext] != _context) {
                [EAGLContext setCurrentContext:_context];
            }
            [self cleanUpTextures];

            CFTypeRef colorAttachments = CVBufferGetAttachment(imageBuffer, kCVImageBufferYCbCrMatrixKey, NULL);

            if (colorAttachments == kCVImageBufferYCbCrMatrix_ITU_R_601_4) {
                _preferredConversion = kColorConversion601FullRange;
            } else {
                _preferredConversion = kColorConversion709;
            }

            glActiveTexture(GL_TEXTURE0);
            err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _videoTextureCache, imageBuffer, NULL, GL_TEXTURE_2D, GL_LUMINANCE, frameWidth, frameHeight, GL_LUMINANCE,
                                                               GL_UNSIGNED_BYTE, 0, &_lumaTexture);
            if (err) {
                NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
            }

            glBindTexture(CVOpenGLESTextureGetTarget(_lumaTexture), CVOpenGLESTextureGetName(_lumaTexture));
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

            // UV-plane.
            glActiveTexture(GL_TEXTURE1);
            err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _videoTextureCache, imageBuffer, NULL, GL_TEXTURE_2D, GL_LUMINANCE_ALPHA, frameWidth / 2, frameHeight / 2,
                                                               GL_LUMINANCE_ALPHA, GL_UNSIGNED_BYTE, 1, &_chromaTexture);
            if (err) {
                NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
            }

            glBindTexture(CVOpenGLESTextureGetTarget(_chromaTexture), CVOpenGLESTextureGetName(_chromaTexture));
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

            glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
            glViewport(0, 0, _backingWidth, _backingHeight);
        }

        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);

        // Use shader program.
        glUseProgram(_program);
        glUniformMatrix3fv(uniforms[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, _preferredConversion);

        //    // 更新顶点数据
        //    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, quadVertexData);
        //    glEnableVertexAttribArray(ATTRIB_VERTEX);
        //    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, quadTextureData);
        //    glEnableVertexAttribArray(ATTRIB_TEXCOORD);

        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

        glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);

        if ([EAGLContext currentContext] == _context) {
            [_context presentRenderbuffer:GL_RENDERBUFFER];
        }
    }
}

- (void)dealloc {
    [self cleanUpTextures];

    if (_videoTextureCache) {
        CFRelease(_videoTextureCache);
    }
}


@end
