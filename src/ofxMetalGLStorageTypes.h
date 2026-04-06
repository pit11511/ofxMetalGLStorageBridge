#pragma once

#include "ofMain.h"

#include <TargetConditionals.h>
#include <string>
#include <vector>

#if !TARGET_OS_OSX
#error "ofxMetalGLStorageBridge is macOS-only."
#endif

enum class StorageFormat {
    R32Float,
    RG32Float,
    RGBA16Float,
    RGBA32Float,
    RGBA8Uint,
    RGBA32Uint,
};

struct ofxMetalGLStorageFormatInfo {
    StorageFormat format = StorageFormat::RGBA32Float;
    std::string name;
    int numChannels = 0;
    size_t bytesPerPixel = 0;
    bool supported = false;
    bool floatingPoint = false;
    bool integer = false;
};

struct ofxMetalGLStorageValidationSample {
    glm::ivec2 coord = glm::ivec2(0);
    glm::vec4 value = glm::vec4(0.0f);
    glm::vec4 expected = glm::vec4(0.0f);
    bool matches = false;
};

struct ofxMetalGLStorageValidationResult {
    bool ok = false;
    bool yFlipDetected = false;
    bool channelOrderMismatchSuspected = false;
    std::string message;
    std::vector<ofxMetalGLStorageValidationSample> samples;
};

std::string ofxMetalGLStorageFormatToString(StorageFormat format);
ofxMetalGLStorageFormatInfo ofxMetalGLStorageGetFormatInfo(StorageFormat format);
bool ofxMetalGLStorageIsFormatSupported(StorageFormat format);
int ofxMetalGLStorageGetNumChannels(StorageFormat format);
size_t ofxMetalGLStorageGetBytesPerPixel(StorageFormat format);
