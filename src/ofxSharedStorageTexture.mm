#include "ofxSharedStorageTexture.h"

#include "ofxMetalGLStoragePrivate.h"

#include <cstring>
#include <sstream>
#include <vector>

namespace {

bool checkLockedSurface(IOSurfaceRef surface,
                        IOSurfaceLockOptions options,
                        void** baseAddress,
                        std::string& error) {
    if (surface == nullptr) {
        error = "IOSurface is null";
        return false;
    }

    kern_return_t lockResult = IOSurfaceLock(surface, options, nullptr);
    if (lockResult != KERN_SUCCESS) {
        error = "IOSurfaceLock failed: " + ofToString(lockResult);
        return false;
    }

    *baseAddress = IOSurfaceGetBaseAddress(surface);
    if (*baseAddress == nullptr) {
        IOSurfaceUnlock(surface, options, nullptr);
        error = "IOSurfaceGetBaseAddress returned null";
        return false;
    }

    return true;
}

void unlockSurface(IOSurfaceRef surface, IOSurfaceLockOptions options) {
    if (surface != nullptr) {
        IOSurfaceUnlock(surface, options, nullptr);
    }
}

} // namespace

ofxSharedStorageTexture::ofxSharedStorageTexture()
: impl_(std::make_unique<ofxSharedStorageTextureImpl>()) {
}

ofxSharedStorageTexture::~ofxSharedStorageTexture() {
    release();
}

ofxSharedStorageTexture::ofxSharedStorageTexture(ofxSharedStorageTexture&& other) noexcept = default;
ofxSharedStorageTexture& ofxSharedStorageTexture::operator=(ofxSharedStorageTexture&& other) noexcept = default;

bool ofxSharedStorageTexture::allocate(int width, int height, StorageFormat format) {
    release();
    impl_->lastError.clear();

    if (width <= 0 || height <= 0) {
        impl_->lastError = "allocate requires positive width and height";
        return false;
    }

    const auto* mapping = ofxMetalGLStorageGetFormatMapping(format);
    if (mapping == nullptr || !mapping->supported) {
        impl_->lastError =
            "Storage format is not supported for IOSurface interop: " +
            ofxMetalGLStorageFormatToString(format);
        return false;
    }

    if (CGLGetCurrentContext() == nullptr) {
        impl_->lastError = "No current OpenGL context. Allocate after the openFrameworks window exists.";
        return false;
    }

    id<MTLDevice> device = ofxMetalGLStorageGetSharedDevice();
    if (device == nil) {
        impl_->lastError = "Metal device is not available";
        return false;
    }

    impl_->width = width;
    impl_->height = height;
    impl_->format = format;
    impl_->glTarget = mapping->glTarget;
    impl_->bytesPerPixel = mapping->bytesPerPixel;
    impl_->logicalRowBytes = static_cast<size_t>(width) * impl_->bytesPerPixel;
    impl_->allocatedRowBytes = ofxMetalGLStorageAlignedBytesPerRow(impl_->logicalRowBytes);
    impl_->numChannels = mapping->numChannels;

    NSDictionary* properties = @{
        (NSString*)kIOSurfaceWidth : @(impl_->width),
        (NSString*)kIOSurfaceHeight : @(impl_->height),
        (NSString*)kIOSurfaceBytesPerElement : @(impl_->bytesPerPixel),
        (NSString*)kIOSurfaceBytesPerRow : @(impl_->allocatedRowBytes),
        (NSString*)kIOSurfaceAllocSize : @(impl_->allocatedRowBytes * static_cast<size_t>(impl_->height)),
        (NSString*)kIOSurfacePixelFormat : @(mapping->cvPixelFormat),
        (NSString*)kIOSurfacePixelSizeCastingAllowed : @NO,
        (NSString*)kIOSurfaceName : @"ofxMetalGLStorageBridge",
    };

    impl_->surface = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
    if (impl_->surface == nullptr) {
        impl_->lastError = "IOSurfaceCreate failed";
        release();
        return false;
    }

    MTLTextureDescriptor* descriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:mapping->metalPixelFormat
                                                          width:static_cast<NSUInteger>(impl_->width)
                                                         height:static_cast<NSUInteger>(impl_->height)
                                                      mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    descriptor.storageMode = MTLStorageModeShared;

    impl_->metalTexture = [device newTextureWithDescriptor:descriptor
                                                 iosurface:impl_->surface
                                                     plane:0];
    if (impl_->metalTexture == nil) {
        impl_->lastError = "Failed to create Metal texture from IOSurface";
        release();
        return false;
    }

    glGenTextures(1, &impl_->glTextureId);
    glBindTexture(impl_->glTarget, impl_->glTextureId);
    glTexParameteri(impl_->glTarget, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(impl_->glTarget, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(impl_->glTarget, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(impl_->glTarget, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    CGLError glError = CGLTexImageIOSurface2D(CGLGetCurrentContext(),
                                              impl_->glTarget,
                                              mapping->glInternalFormat,
                                              static_cast<GLsizei>(impl_->width),
                                              static_cast<GLsizei>(impl_->height),
                                              mapping->glFormat,
                                              mapping->glType,
                                              impl_->surface,
                                              0);
    glBindTexture(impl_->glTarget, 0);

    if (glError != kCGLNoError) {
        impl_->lastError = "CGLTexImageIOSurface2D failed: " +
                           ofxMetalGLStorageGetCGLErrorString(glError);
        release();
        return false;
    }

    return clear();
}

bool ofxSharedStorageTexture::allocateLike(const ofxSharedStorageTexture& other) {
    const bool allocated = allocate(other.getWidth(), other.getHeight(), other.getFormat());
    if (allocated) {
        impl_->semanticR = other.impl_->semanticR;
        impl_->semanticG = other.impl_->semanticG;
        impl_->semanticB = other.impl_->semanticB;
        impl_->semanticA = other.impl_->semanticA;
    }
    return allocated;
}

void ofxSharedStorageTexture::release() {
    if (!impl_) {
        return;
    }

    if (impl_->glTextureId != 0 && CGLGetCurrentContext() != nullptr) {
        glDeleteTextures(1, &impl_->glTextureId);
    }
    impl_->glTextureId = 0;

    impl_->metalTexture = nil;

    if (impl_->surface != nullptr) {
        CFRelease(impl_->surface);
        impl_->surface = nullptr;
    }

    impl_->width = 0;
    impl_->height = 0;
    impl_->bytesPerPixel = 0;
    impl_->logicalRowBytes = 0;
    impl_->allocatedRowBytes = 0;
    impl_->numChannels = 0;
}

bool ofxSharedStorageTexture::isAllocated() const {
    return impl_ && impl_->surface != nullptr && impl_->metalTexture != nil && impl_->glTextureId != 0;
}

int ofxSharedStorageTexture::getWidth() const {
    return impl_ ? impl_->width : 0;
}

int ofxSharedStorageTexture::getHeight() const {
    return impl_ ? impl_->height : 0;
}

StorageFormat ofxSharedStorageTexture::getFormat() const {
    return impl_ ? impl_->format : StorageFormat::RGBA32Float;
}

int ofxSharedStorageTexture::getNumChannels() const {
    return impl_ ? impl_->numChannels : 0;
}

size_t ofxSharedStorageTexture::getBytesPerPixel() const {
    return impl_ ? impl_->bytesPerPixel : 0;
}

size_t ofxSharedStorageTexture::getBytesPerRow() const {
    return impl_ ? impl_->allocatedRowBytes : 0;
}

size_t ofxSharedStorageTexture::getElementCount() const {
    return static_cast<size_t>(getWidth()) * static_cast<size_t>(getHeight());
}

GLuint ofxSharedStorageTexture::getGLTextureID() const {
    return impl_ ? impl_->glTextureId : 0;
}

GLenum ofxSharedStorageTexture::getGLTextureTarget() const {
    return impl_ ? impl_->glTarget : GL_TEXTURE_RECTANGLE;
}

bool ofxSharedStorageTexture::clear() {
    if (!isAllocated()) {
        impl_->lastError = "clear called on an unallocated texture";
        return false;
    }

    void* baseAddress = nullptr;
    if (!checkLockedSurface(impl_->surface, 0, &baseAddress, impl_->lastError)) {
        return false;
    }

    std::memset(baseAddress, 0, impl_->allocatedRowBytes * static_cast<size_t>(impl_->height));
    unlockSurface(impl_->surface, 0);
    ofxMetalGLStorageRebindTexture(impl_->glTarget, impl_->glTextureId);
    return true;
}

bool ofxSharedStorageTexture::fill(float r, float g, float b, float a) {
    if (!isAllocated()) {
        impl_->lastError = "fill called on an unallocated texture";
        return false;
    }

    std::vector<uint8_t> texel(impl_->bytesPerPixel, 0);
    if (!ofxMetalGLStorageEncodeVec4ToTexel(impl_->format, glm::vec4(r, g, b, a), texel.data())) {
        impl_->lastError = "fill failed to encode texel";
        return false;
    }

    void* baseAddress = nullptr;
    if (!checkLockedSurface(impl_->surface, 0, &baseAddress, impl_->lastError)) {
        return false;
    }

    auto* base = static_cast<uint8_t*>(baseAddress);
    for (int y = 0; y < impl_->height; ++y) {
        uint8_t* row = base + static_cast<size_t>(y) * impl_->allocatedRowBytes;
        for (int x = 0; x < impl_->width; ++x) {
            std::memcpy(row + static_cast<size_t>(x) * impl_->bytesPerPixel,
                        texel.data(),
                        impl_->bytesPerPixel);
        }
    }

    unlockSurface(impl_->surface, 0);
    ofxMetalGLStorageRebindTexture(impl_->glTarget, impl_->glTextureId);
    return true;
}

bool ofxSharedStorageTexture::upload(const void* data, size_t bytes) {
    if (!isAllocated()) {
        impl_->lastError = "upload called on an unallocated texture";
        return false;
    }
    if (data == nullptr) {
        impl_->lastError = "upload data pointer is null";
        return false;
    }

    const size_t expectedBytes = impl_->logicalRowBytes * static_cast<size_t>(impl_->height);
    if (bytes != expectedBytes) {
        impl_->lastError = "upload expected " + ofToString(expectedBytes) +
                           " bytes, got " + ofToString(bytes);
        return false;
    }

    void* baseAddress = nullptr;
    if (!checkLockedSurface(impl_->surface, 0, &baseAddress, impl_->lastError)) {
        return false;
    }

    auto* dst = static_cast<uint8_t*>(baseAddress);
    const auto* src = static_cast<const uint8_t*>(data);
    for (int y = 0; y < impl_->height; ++y) {
        std::memcpy(dst + static_cast<size_t>(y) * impl_->allocatedRowBytes,
                    src + static_cast<size_t>(y) * impl_->logicalRowBytes,
                    impl_->logicalRowBytes);
    }

    unlockSurface(impl_->surface, 0);
    ofxMetalGLStorageRebindTexture(impl_->glTarget, impl_->glTextureId);
    return true;
}

bool ofxSharedStorageTexture::download(void* outData, size_t bytes) const {
    if (!isAllocated()) {
        impl_->lastError = "download called on an unallocated texture";
        return false;
    }
    if (outData == nullptr) {
        impl_->lastError = "download outData pointer is null";
        return false;
    }

    const size_t expectedBytes = impl_->logicalRowBytes * static_cast<size_t>(impl_->height);
    if (bytes != expectedBytes) {
        impl_->lastError = "download expected " + ofToString(expectedBytes) +
                           " bytes, got " + ofToString(bytes);
        return false;
    }

    void* baseAddress = nullptr;
    if (!checkLockedSurface(impl_->surface,
                            kIOSurfaceLockReadOnly,
                            &baseAddress,
                            impl_->lastError)) {
        return false;
    }

    const auto* src = static_cast<const uint8_t*>(baseAddress);
    auto* dst = static_cast<uint8_t*>(outData);
    for (int y = 0; y < impl_->height; ++y) {
        std::memcpy(dst + static_cast<size_t>(y) * impl_->logicalRowBytes,
                    src + static_cast<size_t>(y) * impl_->allocatedRowBytes,
                    impl_->logicalRowBytes);
    }

    unlockSurface(impl_->surface, kIOSurfaceLockReadOnly);
    return true;
}

glm::vec4 ofxSharedStorageTexture::readTexelDebug(int x, int y) const {
    if (!isAllocated()) {
        impl_->lastError = "readTexelDebug called on an unallocated texture";
        return glm::vec4(0.0f);
    }
    if (x < 0 || y < 0 || x >= impl_->width || y >= impl_->height) {
        impl_->lastError = "readTexelDebug coordinate out of range";
        return glm::vec4(0.0f);
    }

    void* baseAddress = nullptr;
    if (!checkLockedSurface(impl_->surface,
                            kIOSurfaceLockReadOnly,
                            &baseAddress,
                            impl_->lastError)) {
        return glm::vec4(0.0f);
    }

    const auto* row = static_cast<const uint8_t*>(baseAddress) +
                      static_cast<size_t>(y) * impl_->allocatedRowBytes;
    const void* texel = row + static_cast<size_t>(x) * impl_->bytesPerPixel;
    glm::vec4 result = ofxMetalGLStorageDecodeTexelToVec4(impl_->format, texel);

    unlockSurface(impl_->surface, kIOSurfaceLockReadOnly);
    return result;
}

void ofxSharedStorageTexture::setSemantic(const std::string& r,
                                          const std::string& g,
                                          const std::string& b,
                                          const std::string& a) {
    impl_->semanticR = r;
    impl_->semanticG = g;
    impl_->semanticB = b;
    impl_->semanticA = a;
}

std::string ofxSharedStorageTexture::describe() const {
    std::ostringstream oss;
    oss << "ofxSharedStorageTexture{"
        << "size=" << impl_->width << "x" << impl_->height
        << ", format=" << ofxMetalGLStorageFormatToString(impl_->format)
        << ", channels=" << impl_->numChannels
        << ", bytesPerPixel=" << impl_->bytesPerPixel
        << ", rowBytes=" << impl_->allocatedRowBytes
        << ", glTarget=GL_TEXTURE_RECTANGLE"
        << ", semantics=[R=" << impl_->semanticR
        << ", G=" << impl_->semanticG
        << ", B=" << impl_->semanticB
        << ", A=" << impl_->semanticA << "]"
        << "}";
    return oss.str();
}

std::string ofxSharedStorageTexture::getLastError() const {
    return impl_ ? impl_->lastError : "impl is null";
}

void* ofxSharedStorageTexture::getMetalTextureHandle() const {
    return (__bridge void*)impl_->metalTexture;
}
