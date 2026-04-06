#include "ofxMetalStorageCompute.h"

#include "ofxMetalGLStoragePrivate.h"

#include <algorithm>
#include <cstring>
#include <sstream>

namespace {

void setBinding(std::vector<std::pair<int, ofxSharedStorageTexture*>>& bindings,
                ofxSharedStorageTexture& storage,
                int index) {
    auto existing = std::find_if(bindings.begin(),
                                 bindings.end(),
                                 [index](const auto& item) { return item.first == index; });
    if (existing != bindings.end()) {
        existing->second = &storage;
        return;
    }
    bindings.emplace_back(index, &storage);
}

bool sortBindingsAscending(const std::pair<int, ofxSharedStorageTexture*>& a,
                          const std::pair<int, ofxSharedStorageTexture*>& b) {
    return a.first < b.first;
}

} // namespace

ofxMetalStorageCompute::ofxMetalStorageCompute()
: impl_(std::make_unique<ofxMetalStorageComputeImpl>()) {
}

ofxMetalStorageCompute::~ofxMetalStorageCompute() = default;

ofxMetalStorageCompute::ofxMetalStorageCompute(ofxMetalStorageCompute&& other) noexcept = default;
ofxMetalStorageCompute& ofxMetalStorageCompute::operator=(ofxMetalStorageCompute&& other) noexcept = default;

bool ofxMetalStorageCompute::setup() {
    impl_->lastError.clear();
    impl_->device = ofxMetalGLStorageGetSharedDevice();
    if (impl_->device == nil) {
        impl_->lastError = "Metal device is not available";
        return false;
    }
    if (impl_->commandQueue == nil) {
        impl_->commandQueue = [impl_->device newCommandQueue];
    }
    if (impl_->commandQueue == nil) {
        impl_->lastError = "Failed to create Metal command queue";
        return false;
    }
    return true;
}

bool ofxMetalStorageCompute::loadLibrary(const std::string& metallibPath) {
    impl_->lastError.clear();
    if (!setup()) {
        return false;
    }

    if (metallibPath.empty()) {
        impl_->lastError = "loadLibrary requires a path";
        return false;
    }

    NSString* path = [NSString stringWithUTF8String:metallibPath.c_str()];
    NSError* error = nil;

    const std::string ext = ofToLower(ofFilePath::getFileExt(metallibPath));
    if (ext == "metal") {
        NSString* source = [NSString stringWithContentsOfFile:path
                                                     encoding:NSUTF8StringEncoding
                                                        error:&error];
        if (source == nil) {
            impl_->lastError = "Failed to read Metal source: " + ofxMetalGLStorageNSErrorToString(error);
            return false;
        }

        MTLCompileOptions* options = [[MTLCompileOptions alloc] init];
        options.languageVersion = MTLLanguageVersion3_1;
        impl_->library = [impl_->device newLibraryWithSource:source options:options error:&error];
        if (impl_->library == nil) {
            impl_->lastError =
                "Failed to compile Metal source: " + ofxMetalGLStorageNSErrorToString(error);
            return false;
        }
        return true;
    }

    if (@available(macOS 13.0, *)) {
        NSURL* url = [NSURL fileURLWithPath:path];
        impl_->library = [impl_->device newLibraryWithURL:url error:&error];
    } else {
        impl_->library = [impl_->device newLibraryWithFile:path error:&error];
    }
    if (impl_->library == nil) {
        impl_->lastError = "Failed to load Metal library: " + ofxMetalGLStorageNSErrorToString(error);
        return false;
    }

    return true;
}

bool ofxMetalStorageCompute::loadKernel(const std::string& kernelName) {
    impl_->lastError.clear();
    if (impl_->library == nil) {
        impl_->lastError = "Load a Metal library before loadKernel";
        return false;
    }

    NSString* name = [NSString stringWithUTF8String:kernelName.c_str()];
    impl_->kernel = [impl_->library newFunctionWithName:name];
    if (impl_->kernel == nil) {
        impl_->lastError = "Kernel not found in Metal library: " + kernelName;
        return false;
    }

    NSError* error = nil;
    impl_->pipeline = [impl_->device newComputePipelineStateWithFunction:impl_->kernel error:&error];
    if (impl_->pipeline == nil) {
        impl_->lastError =
            "Failed to create compute pipeline: " + ofxMetalGLStorageNSErrorToString(error);
        return false;
    }
    return true;
}

bool ofxMetalStorageCompute::bindInputStorage(ofxSharedStorageTexture& storage, int index) {
    if (!storage.isAllocated()) {
        impl_->lastError = "bindInputStorage requires allocated storage";
        return false;
    }
    setBinding(impl_->inputBindings, storage, index);
    return true;
}

bool ofxMetalStorageCompute::bindOutputStorage(ofxSharedStorageTexture& storage, int index) {
    if (!storage.isAllocated()) {
        impl_->lastError = "bindOutputStorage requires allocated storage";
        return false;
    }
    setBinding(impl_->outputBindings, storage, index);
    return true;
}

bool ofxMetalStorageCompute::setParamsBytes(const void* data, size_t bytes) {
    impl_->lastError.clear();
    if (data == nullptr || bytes == 0) {
        impl_->lastError = "setParams requires non-empty data";
        return false;
    }
    impl_->paramsBytes.assign(static_cast<const uint8_t*>(data),
                              static_cast<const uint8_t*>(data) + bytes);
    return true;
}

bool ofxMetalStorageCompute::dispatchForTextureSize() {
    if (impl_->outputBindings.empty()) {
        impl_->lastError = "dispatchForTextureSize requires at least one bound output texture";
        return false;
    }

    const ofxSharedStorageTexture* first = impl_->outputBindings.front().second;
    const int width = first->getWidth();
    const int height = first->getHeight();

    for (const auto& output : impl_->outputBindings) {
        if (output.second->getWidth() != width || output.second->getHeight() != height) {
            impl_->lastError = "All bound output textures must have the same dimensions";
            return false;
        }
    }

    return dispatchThreads(width, height, 1);
}

bool ofxMetalStorageCompute::dispatchThreads(int x, int y, int z) {
    impl_->lastError.clear();
    if (!setup()) {
        return false;
    }
    if (impl_->pipeline == nil) {
        impl_->lastError = "Load a kernel before dispatch";
        return false;
    }
    if (x <= 0 || y <= 0 || z <= 0) {
        impl_->lastError = "dispatchThreads requires positive grid dimensions";
        return false;
    }

    std::vector<std::pair<int, ofxSharedStorageTexture*>> allBindings = impl_->inputBindings;
    allBindings.insert(allBindings.end(), impl_->outputBindings.begin(), impl_->outputBindings.end());
    std::sort(allBindings.begin(), allBindings.end(), sortBindingsAscending);

    for (size_t i = 1; i < allBindings.size(); ++i) {
        if (allBindings[i - 1].first == allBindings[i].first &&
            allBindings[i - 1].second != allBindings[i].second) {
            impl_->lastError =
                "Texture binding index collision. Use distinct indices or reuse the same storage.";
            return false;
        }
    }

    id<MTLCommandBuffer> commandBuffer = [impl_->commandQueue commandBuffer];
    if (commandBuffer == nil) {
        impl_->lastError = "Failed to create Metal command buffer";
        return false;
    }

    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
    if (encoder == nil) {
        impl_->lastError = "Failed to create Metal compute encoder";
        return false;
    }

    [encoder setComputePipelineState:impl_->pipeline];

    if (!impl_->paramsBytes.empty()) {
        if (impl_->paramsBuffer == nil || [impl_->paramsBuffer length] < impl_->paramsBytes.size()) {
            impl_->paramsBuffer = [impl_->device newBufferWithLength:impl_->paramsBytes.size()
                                                             options:MTLResourceStorageModeShared];
        }
        if (impl_->paramsBuffer == nil) {
            [encoder endEncoding];
            impl_->lastError = "Failed to create Metal parameter buffer";
            return false;
        }
        std::memcpy([impl_->paramsBuffer contents], impl_->paramsBytes.data(), impl_->paramsBytes.size());
        [encoder setBuffer:impl_->paramsBuffer offset:0 atIndex:0];
    }

    for (const auto& binding : allBindings) {
        id<MTLTexture> metalTexture = (__bridge id<MTLTexture>)binding.second->getMetalTextureHandle();
        if (metalTexture == nil) {
            [encoder endEncoding];
            impl_->lastError = "A bound storage texture does not expose a valid Metal texture";
            return false;
        }
        [encoder setTexture:metalTexture atIndex:binding.first];
    }

    NSUInteger threadgroupWidth =
        std::max<NSUInteger>(1, std::min<NSUInteger>(16, [impl_->pipeline threadExecutionWidth]));
    NSUInteger maxThreads = [impl_->pipeline maxTotalThreadsPerThreadgroup];
    NSUInteger threadgroupHeight =
        std::max<NSUInteger>(1, std::min<NSUInteger>(16, maxThreads / threadgroupWidth));

    const MTLSize gridSize = MTLSizeMake(static_cast<NSUInteger>(x),
                                         static_cast<NSUInteger>(y),
                                         static_cast<NSUInteger>(z));
    const MTLSize threadgroupSize = MTLSizeMake(threadgroupWidth, threadgroupHeight, 1);

    [encoder dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];
    [encoder endEncoding];
    [commandBuffer commit];

    impl_->lastCommandBuffer = commandBuffer;
    return true;
}

bool ofxMetalStorageCompute::waitUntilCompleted() {
    if (impl_->lastCommandBuffer == nil) {
        impl_->lastError = "waitUntilCompleted called before dispatch";
        return false;
    }

    [impl_->lastCommandBuffer waitUntilCompleted];
    if ([impl_->lastCommandBuffer status] == MTLCommandBufferStatusCompleted) {
        return true;
    }

    std::ostringstream oss;
    oss << "Metal command buffer failed with status " << static_cast<int>([impl_->lastCommandBuffer status]);
    if ([impl_->lastCommandBuffer error] != nil) {
        oss << ": " << ofxMetalGLStorageNSErrorToString([impl_->lastCommandBuffer error]);
    }
    impl_->lastError = oss.str();
    return false;
}

std::string ofxMetalStorageCompute::getLastError() const {
    return impl_ ? impl_->lastError : "impl is null";
}
