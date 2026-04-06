#include "ofxMetalGLStorageUtils.h"

#include "ofxMetalGLStoragePrivate.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <sstream>

namespace {

constexpr ofxMetalGLStorageFormatMapping kFormatMappings[] = {
    {StorageFormat::R32Float,
     "R32Float",
     MTLPixelFormatR32Float,
     GL_TEXTURE_RECTANGLE,
     GL_R32F,
     GL_RED,
     GL_FLOAT,
     kCVPixelFormatType_OneComponent32Float,
     sizeof(float) * 1,
     1,
     true,
     true,
     false},
    {StorageFormat::RG32Float,
     "RG32Float",
     MTLPixelFormatRG32Float,
     GL_TEXTURE_RECTANGLE,
     GL_RG32F,
     GL_RG,
     GL_FLOAT,
     kCVPixelFormatType_TwoComponent32Float,
     sizeof(float) * 2,
     2,
     true,
     true,
     false},
    {StorageFormat::RGBA16Float,
     "RGBA16Float",
     MTLPixelFormatRGBA16Float,
     GL_TEXTURE_RECTANGLE,
     GL_RGBA16F,
     GL_RGBA,
     GL_HALF_FLOAT,
     kCVPixelFormatType_64RGBAHalf,
     sizeof(uint16_t) * 4,
     4,
     true,
     true,
     false},
    {StorageFormat::RGBA32Float,
     "RGBA32Float",
     MTLPixelFormatRGBA32Float,
     GL_TEXTURE_RECTANGLE,
     GL_RGBA32F,
     GL_RGBA,
     GL_FLOAT,
     kCVPixelFormatType_128RGBAFloat,
     sizeof(float) * 4,
     4,
     true,
     true,
     false},
    {StorageFormat::RGBA8Uint,
     "RGBA8Uint",
     MTLPixelFormatRGBA8Uint,
     GL_TEXTURE_RECTANGLE,
     GL_RGBA8UI,
     GL_RGBA_INTEGER,
     GL_UNSIGNED_BYTE,
     kCVPixelFormatType_32RGBA,
     sizeof(uint8_t) * 4,
     4,
     true,
     false,
     true},
    {StorageFormat::RGBA32Uint,
     "RGBA32Uint",
     MTLPixelFormatRGBA32Uint,
     GL_TEXTURE_RECTANGLE,
     GL_RGBA32UI,
     GL_RGBA_INTEGER,
     GL_UNSIGNED_INT,
     0,
     sizeof(uint32_t) * 4,
     4,
     false,
     false,
     true},
};

template<typename T>
T clampCast(float value) {
    if (std::isnan(value)) {
        return static_cast<T>(0);
    }
    const float minValue = static_cast<float>(std::numeric_limits<T>::min());
    const float maxValue = static_cast<float>(std::numeric_limits<T>::max());
    const float clamped = std::max(minValue, std::min(maxValue, value));
    return static_cast<T>(std::lround(clamped));
}

bool almostEqual(float a, float b, float epsilon = 0.001f) {
    return std::fabs(a - b) <= epsilon;
}

bool almostEqualVec4(const glm::vec4& a, const glm::vec4& b, float epsilon = 0.001f) {
    return almostEqual(a.r, b.r, epsilon) &&
           almostEqual(a.g, b.g, epsilon) &&
           almostEqual(a.b, b.b, epsilon) &&
           almostEqual(a.a, b.a, epsilon);
}

bool almostEqualForFormat(StorageFormat format,
                          const glm::vec4& actual,
                          const glm::vec4& expected,
                          float epsilon = 0.001f) {
    const int channels = ofxMetalGLStorageGetNumChannels(format);
    if (channels >= 1 && !almostEqual(actual.r, expected.r, epsilon)) {
        return false;
    }
    if (channels >= 2 && !almostEqual(actual.g, expected.g, epsilon)) {
        return false;
    }
    if (channels >= 3 && !almostEqual(actual.b, expected.b, epsilon)) {
        return false;
    }
    if (channels >= 4 && !almostEqual(actual.a, expected.a, epsilon)) {
        return false;
    }
    return true;
}

bool ensureGLValidationShader(ofShader& shader, std::string& error) {
    if (shader.isLoaded()) {
        return true;
    }

    const std::string vertexShader = R"(#version 150
in vec4 position;
void main() {
    gl_Position = position;
}
)";

    const std::string fragmentShader = R"(#version 150
uniform sampler2DRect uStorageTex;
out vec4 outputColor;
void main() {
    ivec2 coord = ivec2(floor(gl_FragCoord.xy));
    outputColor = texelFetch(uStorageTex, coord);
}
)";

    if (!shader.setupShaderFromSource(GL_VERTEX_SHADER, vertexShader)) {
        error = "failed to compile GL validation vertex shader";
        return false;
    }
    if (!shader.setupShaderFromSource(GL_FRAGMENT_SHADER, fragmentShader)) {
        error = "failed to compile GL validation fragment shader";
        return false;
    }
    shader.bindDefaults();
    if (!shader.linkProgram()) {
        error = "failed to link GL validation shader";
        return false;
    }
    return true;
}

ofMesh makeFullScreenTriangleStrip() {
    ofMesh mesh;
    mesh.setMode(OF_PRIMITIVE_TRIANGLE_STRIP);
    mesh.addVertex(glm::vec3(-1.0f, -1.0f, 0.0f));
    mesh.addVertex(glm::vec3(1.0f, -1.0f, 0.0f));
    mesh.addVertex(glm::vec3(-1.0f, 1.0f, 0.0f));
    mesh.addVertex(glm::vec3(1.0f, 1.0f, 0.0f));
    return mesh;
}

std::vector<glm::ivec2> makeDefaultSampleCoordsGL(int width, int height) {
    std::vector<glm::ivec2> coords;
    coords.push_back(glm::ivec2(0, 0));
    coords.push_back(glm::ivec2(std::max(0, width - 1), 0));
    coords.push_back(glm::ivec2(0, std::max(0, height - 1)));
    coords.push_back(glm::ivec2(std::max(0, width - 1), std::max(0, height - 1)));
    coords.push_back(glm::ivec2(width / 2, height / 2));
    return coords;
}

} // namespace

const ofxMetalGLStorageFormatMapping* ofxMetalGLStorageGetFormatMapping(StorageFormat format) {
    for (const auto& mapping : kFormatMappings) {
        if (mapping.format == format) {
            return &mapping;
        }
    }
    return nullptr;
}

id<MTLDevice> ofxMetalGLStorageGetSharedDevice() {
    static id<MTLDevice> sharedDevice = MTLCreateSystemDefaultDevice();
    return sharedDevice;
}

std::string ofxMetalGLStorageFormatToString(StorageFormat format) {
    const auto* mapping = ofxMetalGLStorageGetFormatMapping(format);
    return mapping ? mapping->name : "Unknown";
}

ofxMetalGLStorageFormatInfo ofxMetalGLStorageGetFormatInfo(StorageFormat format) {
    ofxMetalGLStorageFormatInfo info;
    info.format = format;
    const auto* mapping = ofxMetalGLStorageGetFormatMapping(format);
    if (!mapping) {
        info.name = "Unknown";
        return info;
    }
    info.name = mapping->name;
    info.numChannels = mapping->numChannels;
    info.bytesPerPixel = mapping->bytesPerPixel;
    info.supported = mapping->supported;
    info.floatingPoint = mapping->floatingPoint;
    info.integer = mapping->integer;
    return info;
}

bool ofxMetalGLStorageIsFormatSupported(StorageFormat format) {
    const auto* mapping = ofxMetalGLStorageGetFormatMapping(format);
    return mapping && mapping->supported;
}

int ofxMetalGLStorageGetNumChannels(StorageFormat format) {
    const auto* mapping = ofxMetalGLStorageGetFormatMapping(format);
    return mapping ? mapping->numChannels : 0;
}

size_t ofxMetalGLStorageGetBytesPerPixel(StorageFormat format) {
    const auto* mapping = ofxMetalGLStorageGetFormatMapping(format);
    return mapping ? mapping->bytesPerPixel : 0;
}

std::string ofxMetalGLStorageNSErrorToString(NSError* error) {
    if (error == nil) {
        return {};
    }
    return std::string([[error localizedDescription] UTF8String]);
}

std::string ofxMetalGLStorageGetCGLErrorString(CGLError error) {
    const char* errorString = CGLErrorString(error);
    return errorString ? std::string(errorString) : ("CGLError " + ofToString(static_cast<int>(error)));
}

size_t ofxMetalGLStorageAlignedBytesPerRow(size_t logicalRowBytes) {
    return IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, logicalRowBytes);
}

void ofxMetalGLStorageRebindTexture(GLenum target, GLuint textureId) {
    if (textureId == 0 || CGLGetCurrentContext() == nullptr) {
        return;
    }
    glBindTexture(target, textureId);
    glBindTexture(target, 0);
}

uint16_t ofxMetalGLStorageFloatToHalf(float value) {
    uint32_t bits = 0;
    std::memcpy(&bits, &value, sizeof(bits));

    const uint32_t sign = (bits >> 16) & 0x8000u;
    uint32_t mantissa = bits & 0x007fffffu;
    int32_t exponent = static_cast<int32_t>((bits >> 23) & 0xffu) - 127 + 15;

    if (exponent <= 0) {
        if (exponent < -10) {
            return static_cast<uint16_t>(sign);
        }
        mantissa = (mantissa | 0x00800000u) >> static_cast<uint32_t>(1 - exponent);
        return static_cast<uint16_t>(sign | ((mantissa + 0x00001000u) >> 13));
    }

    if (exponent >= 31) {
        return static_cast<uint16_t>(sign | 0x7c00u | (mantissa ? 0x0200u : 0u));
    }

    return static_cast<uint16_t>(sign | (static_cast<uint32_t>(exponent) << 10) |
                                 ((mantissa + 0x00001000u) >> 13));
}

float ofxMetalGLStorageHalfToFloat(uint16_t value) {
    const uint32_t sign = static_cast<uint32_t>(value & 0x8000u) << 16;
    uint32_t exponent = (value >> 10) & 0x1fu;
    uint32_t mantissa = value & 0x03ffu;
    uint32_t bits = 0;

    if (exponent == 0) {
        if (mantissa == 0) {
            bits = sign;
        } else {
            exponent = 127 - 15 + 1;
            while ((mantissa & 0x0400u) == 0) {
                mantissa <<= 1u;
                --exponent;
            }
            mantissa &= 0x03ffu;
            bits = sign | (exponent << 23) | (mantissa << 13);
        }
    } else if (exponent == 31) {
        bits = sign | 0x7f800000u | (mantissa << 13);
    } else {
        bits = sign | ((exponent - 15 + 127) << 23) | (mantissa << 13);
    }

    float result = 0.0f;
    std::memcpy(&result, &bits, sizeof(result));
    return result;
}

glm::vec4 ofxMetalGLStorageDecodeTexelToVec4(StorageFormat format, const void* texelBytes) {
    glm::vec4 decoded(0.0f);
    switch (format) {
    case StorageFormat::R32Float: {
        const auto* values = static_cast<const float*>(texelBytes);
        decoded.r = values[0];
        break;
    }
    case StorageFormat::RG32Float: {
        const auto* values = static_cast<const float*>(texelBytes);
        decoded.r = values[0];
        decoded.g = values[1];
        break;
    }
    case StorageFormat::RGBA16Float: {
        const auto* values = static_cast<const uint16_t*>(texelBytes);
        decoded.r = ofxMetalGLStorageHalfToFloat(values[0]);
        decoded.g = ofxMetalGLStorageHalfToFloat(values[1]);
        decoded.b = ofxMetalGLStorageHalfToFloat(values[2]);
        decoded.a = ofxMetalGLStorageHalfToFloat(values[3]);
        break;
    }
    case StorageFormat::RGBA32Float: {
        const auto* values = static_cast<const float*>(texelBytes);
        decoded = glm::vec4(values[0], values[1], values[2], values[3]);
        break;
    }
    case StorageFormat::RGBA8Uint: {
        const auto* values = static_cast<const uint8_t*>(texelBytes);
        decoded = glm::vec4(values[0], values[1], values[2], values[3]);
        break;
    }
    case StorageFormat::RGBA32Uint: {
        const auto* values = static_cast<const uint32_t*>(texelBytes);
        decoded = glm::vec4(static_cast<float>(values[0]),
                            static_cast<float>(values[1]),
                            static_cast<float>(values[2]),
                            static_cast<float>(values[3]));
        break;
    }
    }
    return decoded;
}

bool ofxMetalGLStorageEncodeVec4ToTexel(StorageFormat format,
                                        const glm::vec4& value,
                                        void* outTexelBytes) {
    switch (format) {
    case StorageFormat::R32Float: {
        auto* values = static_cast<float*>(outTexelBytes);
        values[0] = value.r;
        return true;
    }
    case StorageFormat::RG32Float: {
        auto* values = static_cast<float*>(outTexelBytes);
        values[0] = value.r;
        values[1] = value.g;
        return true;
    }
    case StorageFormat::RGBA16Float: {
        auto* values = static_cast<uint16_t*>(outTexelBytes);
        values[0] = ofxMetalGLStorageFloatToHalf(value.r);
        values[1] = ofxMetalGLStorageFloatToHalf(value.g);
        values[2] = ofxMetalGLStorageFloatToHalf(value.b);
        values[3] = ofxMetalGLStorageFloatToHalf(value.a);
        return true;
    }
    case StorageFormat::RGBA32Float: {
        auto* values = static_cast<float*>(outTexelBytes);
        values[0] = value.r;
        values[1] = value.g;
        values[2] = value.b;
        values[3] = value.a;
        return true;
    }
    case StorageFormat::RGBA8Uint: {
        auto* values = static_cast<uint8_t*>(outTexelBytes);
        values[0] = clampCast<uint8_t>(value.r);
        values[1] = clampCast<uint8_t>(value.g);
        values[2] = clampCast<uint8_t>(value.b);
        values[3] = clampCast<uint8_t>(value.a);
        return true;
    }
    case StorageFormat::RGBA32Uint: {
        auto* values = static_cast<uint32_t*>(outTexelBytes);
        values[0] = clampCast<uint32_t>(value.r);
        values[1] = clampCast<uint32_t>(value.g);
        values[2] = clampCast<uint32_t>(value.b);
        values[3] = clampCast<uint32_t>(value.a);
        return true;
    }
    }
    return false;
}

glm::vec4 ofxMetalGLStorageExpectedDebugPattern(int x, int y) {
    return glm::vec4(static_cast<float>(x),
                     static_cast<float>(y),
                     1000.0f + static_cast<float>(x) + 100.0f * static_cast<float>(y),
                     1.0f);
}

glm::vec4 ofxMetalGLStorageExpectedDebugPatternForFormat(StorageFormat format, int x, int y) {
    switch (format) {
    case StorageFormat::R32Float:
        return glm::vec4(static_cast<float>(x), 0.0f, 0.0f, 0.0f);
    case StorageFormat::RG32Float:
        return glm::vec4(static_cast<float>(x), static_cast<float>(y), 0.0f, 0.0f);
    case StorageFormat::RGBA16Float:
    case StorageFormat::RGBA32Float:
        return ofxMetalGLStorageExpectedDebugPattern(x, y);
    case StorageFormat::RGBA8Uint:
        return glm::vec4(static_cast<float>(x & 0xff),
                         static_cast<float>(y & 0xff),
                         static_cast<float>((1000 + x + 100 * y) & 0xff),
                         1.0f);
    case StorageFormat::RGBA32Uint:
        return glm::vec4(static_cast<float>(x),
                         static_cast<float>(y),
                         1000.0f + static_cast<float>(x) + 100.0f * static_cast<float>(y),
                         1.0f);
    }
    return glm::vec4(0.0f);
}

ofxMetalGLStorageValidationResult ofxMetalGLStorageValidateDebugPattern(
    const ofxSharedStorageTexture& storage,
    const std::vector<glm::ivec2>& sampleCoords) {
    ofxMetalGLStorageValidationResult result;

    if (!storage.isAllocated()) {
        result.message = "storage is not allocated";
        return result;
    }

    std::vector<glm::ivec2> coords = sampleCoords;
    if (coords.empty()) {
        coords.push_back(glm::ivec2(0, 0));
        coords.push_back(glm::ivec2(std::max(0, storage.getWidth() - 1), 0));
        coords.push_back(glm::ivec2(0, std::max(0, storage.getHeight() - 1)));
        coords.push_back(glm::ivec2(std::max(0, storage.getWidth() - 1),
                                    std::max(0, storage.getHeight() - 1)));
        coords.push_back(glm::ivec2(storage.getWidth() / 2, storage.getHeight() / 2));
    }

    result.ok = true;
    result.samples.reserve(coords.size());

    for (const auto& coord : coords) {
        ofxMetalGLStorageValidationSample sample;
        sample.coord = coord;
        sample.value = storage.readTexelDebug(coord.x, coord.y);
        sample.expected =
            ofxMetalGLStorageExpectedDebugPatternForFormat(storage.getFormat(), coord.x, coord.y);
        sample.matches = almostEqualForFormat(storage.getFormat(), sample.value, sample.expected);
        result.ok = result.ok && sample.matches;
        result.samples.push_back(sample);
    }

    if (!result.ok && storage.getHeight() > 1) {
        const glm::vec4 topLeft = storage.readTexelDebug(0, 0);
        const glm::vec4 expectedBottomLeft = ofxMetalGLStorageExpectedDebugPatternForFormat(
            storage.getFormat(), 0, storage.getHeight() - 1);
        result.yFlipDetected =
            almostEqualForFormat(storage.getFormat(), topLeft, expectedBottomLeft);

        const glm::vec4 channelProbe = storage.readTexelDebug(std::min(1, storage.getWidth() - 1),
                                                              std::min(1, storage.getHeight() - 1));
        const glm::vec4 expectedProbe = ofxMetalGLStorageExpectedDebugPatternForFormat(
            storage.getFormat(),
            std::min(1, storage.getWidth() - 1),
            std::min(1, storage.getHeight() - 1));
        result.channelOrderMismatchSuspected =
            almostEqual(channelProbe.r, expectedProbe.b) &&
            almostEqual(channelProbe.g, expectedProbe.g) &&
            almostEqual(channelProbe.b, expectedProbe.r);
    }

    std::ostringstream oss;
    if (result.ok) {
        oss << "debug pattern validation passed";
    } else {
        oss << "debug pattern validation failed";
        if (result.yFlipDetected) {
            oss << " | suspected Y flip";
        }
        if (result.channelOrderMismatchSuspected) {
            oss << " | suspected channel order mismatch";
        }
    }
    result.message = oss.str();
    return result;
}

ofxMetalGLStorageValidationResult ofxMetalGLStorageValidateDebugPatternViaGLTexelFetch(
    const ofxSharedStorageTexture& storage,
    const std::vector<glm::ivec2>& sampleCoords) {
    ofxMetalGLStorageValidationResult result;

    if (!storage.isAllocated()) {
        result.message = "storage is not allocated";
        return result;
    }
    if (CGLGetCurrentContext() == nullptr) {
        result.message = "no current OpenGL context";
        return result;
    }

    const auto formatInfo = ofxMetalGLStorageGetFormatInfo(storage.getFormat());
    if (!formatInfo.floatingPoint) {
        result.message =
            "GL texelFetch validation currently supports floating-point storage formats only";
        return result;
    }

    static ofShader shader;
    static ofMesh mesh = makeFullScreenTriangleStrip();
    std::string shaderError;
    if (!ensureGLValidationShader(shader, shaderError)) {
        result.message = shaderError;
        return result;
    }

    ofFbo fbo;
    ofFbo::Settings settings;
    settings.width = storage.getWidth();
    settings.height = storage.getHeight();
    settings.numColorbuffers = 1;
    settings.useDepth = false;
    settings.useStencil = false;
    settings.depthStencilAsTexture = false;
    settings.textureTarget = GL_TEXTURE_2D;
    settings.internalformat = GL_RGBA32F;
    settings.minFilter = GL_NEAREST;
    settings.maxFilter = GL_NEAREST;
    settings.wrapModeHorizontal = GL_CLAMP_TO_EDGE;
    settings.wrapModeVertical = GL_CLAMP_TO_EDGE;
    settings.numSamples = 0;
    fbo.allocate(settings);

    if (!fbo.isAllocated()) {
        result.message = "failed to allocate validation FBO";
        return result;
    }

    const GLboolean blendWasEnabled = glIsEnabled(GL_BLEND);
    if (blendWasEnabled) {
        glDisable(GL_BLEND);
    }

    GLint previousActiveTexture = GL_TEXTURE0;
    glGetIntegerv(GL_ACTIVE_TEXTURE, &previousActiveTexture);

    fbo.begin(OF_FBOMODE_PERSPECTIVE);
    ofClear(0, 0, 0, 0);
    shader.begin();
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(storage.getGLTextureTarget(), storage.getGLTextureID());
    shader.setUniform1i("uStorageTex", 0);
    mesh.draw();
    glBindTexture(storage.getGLTextureTarget(), 0);
    shader.end();
    fbo.end();

    glActiveTexture(previousActiveTexture);
    if (blendWasEnabled) {
        glEnable(GL_BLEND);
    }

    std::vector<float> pixels(static_cast<size_t>(storage.getWidth() * storage.getHeight() * 4), 0.0f);

    GLint previousReadFbo = 0;
    GLint previousPackAlignment = 4;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &previousReadFbo);
    glGetIntegerv(GL_PACK_ALIGNMENT, &previousPackAlignment);

    glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo.getId());
    glReadBuffer(GL_COLOR_ATTACHMENT0);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0,
                 0,
                 storage.getWidth(),
                 storage.getHeight(),
                 GL_RGBA,
                 GL_FLOAT,
                 pixels.data());
    glBindFramebuffer(GL_READ_FRAMEBUFFER, previousReadFbo);
    glPixelStorei(GL_PACK_ALIGNMENT, previousPackAlignment);

    std::vector<glm::ivec2> coords = sampleCoords;
    if (coords.empty()) {
        coords = makeDefaultSampleCoordsGL(storage.getWidth(), storage.getHeight());
    }

    bool directAllMatch = true;
    bool flippedAllMatch = true;
    struct PendingSample {
        glm::ivec2 coord;
        glm::vec4 actual;
        glm::vec4 expectedDirect;
        glm::vec4 expectedFlipped;
    };
    std::vector<PendingSample> pending;
    pending.reserve(coords.size());

    for (const auto& coord : coords) {
        const int x = coord.x;
        const int y = coord.y;
        if (x < 0 || y < 0 || x >= storage.getWidth() || y >= storage.getHeight()) {
            continue;
        }

        const size_t index = static_cast<size_t>(y * storage.getWidth() + x) * 4;
        const glm::vec4 actual(pixels[index + 0], pixels[index + 1], pixels[index + 2], pixels[index + 3]);
        const glm::vec4 expectedDirect =
            ofxMetalGLStorageExpectedDebugPatternForFormat(storage.getFormat(), x, y);
        const glm::vec4 expectedFlipped = ofxMetalGLStorageExpectedDebugPatternForFormat(
            storage.getFormat(), x, storage.getHeight() - 1 - y);

        directAllMatch =
            directAllMatch && almostEqualForFormat(storage.getFormat(), actual, expectedDirect);
        flippedAllMatch =
            flippedAllMatch && almostEqualForFormat(storage.getFormat(), actual, expectedFlipped);
        pending.push_back({coord, actual, expectedDirect, expectedFlipped});
    }

    result.ok = directAllMatch || flippedAllMatch;
    result.yFlipDetected = !directAllMatch && flippedAllMatch;
    result.samples.reserve(pending.size());

    for (const auto& item : pending) {
        ofxMetalGLStorageValidationSample sample;
        sample.coord = item.coord;
        sample.value = item.actual;
        sample.expected = result.yFlipDetected ? item.expectedFlipped : item.expectedDirect;
        sample.matches =
            almostEqualForFormat(storage.getFormat(), sample.value, sample.expected);
        result.samples.push_back(sample);
    }

    if (!result.ok && !pending.empty()) {
        const auto& probe = pending.front();
        result.channelOrderMismatchSuspected =
            almostEqual(probe.actual.r, probe.expectedDirect.b) &&
            almostEqual(probe.actual.g, probe.expectedDirect.g) &&
            almostEqual(probe.actual.b, probe.expectedDirect.r);
    }

    std::ostringstream oss;
    if (result.ok) {
        oss << "GL texelFetch validation passed";
        if (result.yFlipDetected) {
            oss << " | OpenGL sees vertically flipped rows relative to CPU/Metal debug convention";
        } else {
            oss << " | OpenGL coordinates match CPU/Metal debug convention";
        }
    } else {
        oss << "GL texelFetch validation failed";
        if (result.channelOrderMismatchSuspected) {
            oss << " | suspected channel order mismatch";
        }
    }
    result.message = oss.str();
    return result;
}

std::string ofxMetalGLStorageRecommendedRectSamplerGLSL() {
    return
        "#version 150\n"
        "uniform sampler2DRect uStorageTex;\n"
        "ivec2 coord = ivec2(12, 7);\n"
        "vec4 raw = texelFetch(uStorageTex, coord);\n";
}
