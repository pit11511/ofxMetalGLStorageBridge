#pragma once

#import <CoreVideo/CVPixelBuffer.h>
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#import <Metal/Metal.h>
#import <OpenGL/CGLCurrent.h>
#import <OpenGL/CGLIOSurface.h>
#import <OpenGL/OpenGL.h>

#include "ofxMetalGLStorageTypes.h"

#include <memory>
#include <string>
#include <vector>

class ofxSharedStorageTexture;

struct ofxMetalGLStorageFormatMapping {
    StorageFormat format = StorageFormat::RGBA32Float;
    const char* name = "Unknown";
    MTLPixelFormat metalPixelFormat = MTLPixelFormatInvalid;
    GLenum glTarget = GL_TEXTURE_RECTANGLE;
    GLenum glInternalFormat = 0;
    GLenum glFormat = 0;
    GLenum glType = 0;
    OSType cvPixelFormat = 0;
    size_t bytesPerPixel = 0;
    int numChannels = 0;
    bool supported = false;
    bool floatingPoint = false;
    bool integer = false;
};

struct ofxSharedStorageTextureImpl {
    int width = 0;
    int height = 0;
    StorageFormat format = StorageFormat::RGBA32Float;
    GLuint glTextureId = 0;
    GLenum glTarget = GL_TEXTURE_RECTANGLE;
    size_t bytesPerPixel = 0;
    size_t logicalRowBytes = 0;
    size_t allocatedRowBytes = 0;
    int numChannels = 0;
    IOSurfaceRef surface = nullptr;
    id<MTLTexture> metalTexture = nil;
    std::string semanticR = "R";
    std::string semanticG = "G";
    std::string semanticB = "B";
    std::string semanticA = "A";
    std::string lastError;
};

struct ofxMetalStorageComputeImpl {
    id<MTLDevice> device = nil;
    id<MTLCommandQueue> commandQueue = nil;
    id<MTLLibrary> library = nil;
    id<MTLFunction> kernel = nil;
    id<MTLComputePipelineState> pipeline = nil;
    id<MTLCommandBuffer> lastCommandBuffer = nil;
    id<MTLBuffer> paramsBuffer = nil;
    std::vector<std::pair<int, ofxSharedStorageTexture*>> inputBindings;
    std::vector<std::pair<int, ofxSharedStorageTexture*>> outputBindings;
    std::vector<uint8_t> paramsBytes;
    std::string lastError;
};

const ofxMetalGLStorageFormatMapping* ofxMetalGLStorageGetFormatMapping(StorageFormat format);
id<MTLDevice> ofxMetalGLStorageGetSharedDevice();

std::string ofxMetalGLStorageNSErrorToString(NSError* error);
std::string ofxMetalGLStorageGetCGLErrorString(CGLError error);

size_t ofxMetalGLStorageAlignedBytesPerRow(size_t logicalRowBytes);
void ofxMetalGLStorageRebindTexture(GLenum target, GLuint textureId);

uint16_t ofxMetalGLStorageFloatToHalf(float value);
float ofxMetalGLStorageHalfToFloat(uint16_t value);

glm::vec4 ofxMetalGLStorageDecodeTexelToVec4(StorageFormat format, const void* texelBytes);
bool ofxMetalGLStorageEncodeVec4ToTexel(StorageFormat format,
                                        const glm::vec4& value,
                                        void* outTexelBytes);
