#pragma once

#include "ofxSharedStorageTexture.h"

#include <string>
#include <vector>

glm::vec4 ofxMetalGLStorageExpectedDebugPattern(int x, int y);
glm::vec4 ofxMetalGLStorageExpectedDebugPatternForFormat(StorageFormat format, int x, int y);

ofxMetalGLStorageValidationResult ofxMetalGLStorageValidateDebugPattern(
    const ofxSharedStorageTexture& storage,
    const std::vector<glm::ivec2>& sampleCoords = {});

// Validates the OpenGL read path by sampling the shared texture with sampler2DRect + texelFetch
// into a temporary FBO and comparing the GPU readback against the known Metal debug pattern.
// The sampled coordinates are expressed in OpenGL/FBO bottom-left origin space.
ofxMetalGLStorageValidationResult ofxMetalGLStorageValidateDebugPatternViaGLTexelFetch(
    const ofxSharedStorageTexture& storage,
    const std::vector<glm::ivec2>& sampleCoords = {});

std::string ofxMetalGLStorageRecommendedRectSamplerGLSL();
