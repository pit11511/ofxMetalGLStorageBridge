#include "ofApp.h"

namespace {

std::string vec4ToString(const glm::vec4& value) {
    return "(" + ofToString(value.x, 3) + ", " +
           ofToString(value.y, 3) + ", " +
           ofToString(value.z, 3) + ", " +
           ofToString(value.w, 3) + ")";
}

} // namespace

void ofApp::setup() {
    ofSetWindowTitle("ofxMetalGLStorageBridge example-basic");
    ofSetFrameRate(60);
    ofBackground(12);
    ofSetColor(255);

    buildPreviewMesh();
    previewShader_.load("shadersGL3/debugDataView");

    if (!setupExample()) {
        ofLogError("example-basic") << statusLine_;
    }
}

void ofApp::update() {
}

void ofApp::draw() {
    ofBackgroundGradient(ofColor(18, 20, 24), ofColor(8, 9, 12), OF_GRADIENT_CIRCULAR);

    if (previewShader_.isLoaded() && storage_.isAllocated()) {
        ofPushMatrix();
        ofTranslate(40.0f, 120.0f);

        previewShader_.begin();
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(storage_.getGLTextureTarget(), storage_.getGLTextureID());
        previewShader_.setUniform1i("uStorageTex", 0);
        previewShader_.setUniform2f("uStorageSize",
                                    static_cast<float>(storage_.getWidth()),
                                    static_cast<float>(storage_.getHeight()));
        previewMesh_.draw();
        glBindTexture(storage_.getGLTextureTarget(), 0);
        previewShader_.end();

        ofNoFill();
        ofSetColor(255, 255, 255, 120);
        ofDrawRectangle(0.0f,
                        0.0f,
                        storageWidth_ * previewScale_,
                        storageHeight_ * previewScale_);
        ofFill();
        ofPopMatrix();
    }

    ofSetColor(255);
    ofDrawBitmapStringHighlight(buildOverlayText(), 40, 36, ofColor(0, 0, 0, 180), ofColor::white);
}

void ofApp::keyPressed(int key) {
    if (key == 'r') {
        if (runDebugKernel()) {
            logReadbackSamples();
            validateAdditionalFormats();
        }
    }
}

bool ofApp::setupExample() {
    storage_.setSemantic("x", "y", "1000 + x + 100*y", "valid");
    if (!storage_.allocate(storageWidth_, storageHeight_, StorageFormat::RGBA32Float)) {
        statusLine_ = "storage allocate failed: " + storage_.getLastError();
        return false;
    }

    if (!compute_.setup()) {
        statusLine_ = "compute setup failed: " + compute_.getLastError();
        return false;
    }

    const std::string metallibPath = ofToDataPath("metal/ofxMetalGLStorageKernels.metallib", true);
    const std::string metalSourcePath = ofToDataPath("metal/ofxMetalGLStorageKernels.metal", true);
    libraryPathUsed_ = ofFile::doesFileExist(metallibPath) ? metallibPath : metalSourcePath;

    if (!compute_.loadLibrary(libraryPathUsed_)) {
        statusLine_ = "loadLibrary failed: " + compute_.getLastError();
        return false;
    }
    if (!compute_.loadKernel("writeDebugPattern")) {
        statusLine_ = "loadKernel failed: " + compute_.getLastError();
        return false;
    }
    if (!compute_.bindOutputStorage(storage_, 0)) {
        statusLine_ = "bindOutputStorage failed: " + compute_.getLastError();
        return false;
    }

    if (!runDebugKernel()) {
        return false;
    }

    logReadbackSamples();
    validateAdditionalFormats();
    return true;
}

bool ofApp::runDebugKernel() {
    if (!compute_.dispatchForTextureSize()) {
        statusLine_ = "dispatchForTextureSize failed: " + compute_.getLastError();
        return false;
    }
    if (!compute_.waitUntilCompleted()) {
        statusLine_ = "waitUntilCompleted failed: " + compute_.getLastError();
        return false;
    }

    validation_ = ofxMetalGLStorageValidateDebugPattern(storage_);
    glValidation_ = ofxMetalGLStorageValidateDebugPatternViaGLTexelFetch(storage_);
    statusLine_ = "CPU: " + validation_.message + " | GL: " + glValidation_.message;
    ofLogNotice("example-basic") << validation_.message;
    ofLogNotice("example-basic") << glValidation_.message;
    return true;
}

void ofApp::buildPreviewMesh() {
    previewMesh_.clear();
    previewMesh_.setMode(OF_PRIMITIVE_TRIANGLE_STRIP);

    const float drawWidth = static_cast<float>(storageWidth_) * previewScale_;
    const float drawHeight = static_cast<float>(storageHeight_) * previewScale_;

    previewMesh_.addVertex(glm::vec3(0.0f, 0.0f, 0.0f));
    previewMesh_.addTexCoord(glm::vec2(0.0f, 0.0f));

    previewMesh_.addVertex(glm::vec3(drawWidth, 0.0f, 0.0f));
    previewMesh_.addTexCoord(glm::vec2(static_cast<float>(storageWidth_), 0.0f));

    previewMesh_.addVertex(glm::vec3(0.0f, drawHeight, 0.0f));
    previewMesh_.addTexCoord(glm::vec2(0.0f, static_cast<float>(storageHeight_)));

    previewMesh_.addVertex(glm::vec3(drawWidth, drawHeight, 0.0f));
    previewMesh_.addTexCoord(
        glm::vec2(static_cast<float>(storageWidth_), static_cast<float>(storageHeight_)));
}

void ofApp::logReadbackSamples() {
    std::vector<float> readback(static_cast<size_t>(storageWidth_ * storageHeight_ * 4), 0.0f);
    if (!storage_.download(readback.data(), readback.size() * sizeof(float))) {
        ofLogError("example-basic") << "download failed: " << storage_.getLastError();
        return;
    }

    const auto logSample = [&](int x, int y) {
        const size_t index = static_cast<size_t>(y * storageWidth_ + x) * 4;
        const glm::vec4 downloaded(readback[index + 0],
                                   readback[index + 1],
                                   readback[index + 2],
                                   readback[index + 3]);
        const glm::vec4 debugRead = storage_.readTexelDebug(x, y);
        ofLogNotice("example-basic")
            << "texel(" << x << ", " << y << ") download=" << vec4ToString(downloaded)
            << " readTexelDebug=" << vec4ToString(debugRead)
            << " expected=" << vec4ToString(ofxMetalGLStorageExpectedDebugPattern(x, y));
    };

    logSample(0, 0);
    logSample(std::min(1, storageWidth_ - 1), 0);
    logSample(0, std::min(1, storageHeight_ - 1));
    logSample(storageWidth_ - 1, storageHeight_ - 1);

    logGLValidationSamples();
}

void ofApp::logGLValidationSamples() {
    for (const auto& sample : glValidation_.samples) {
        ofLogNotice("example-basic")
            << "glTexelFetch(" << sample.coord.x << ", " << sample.coord.y
            << ", bottom-left origin) value=" << vec4ToString(sample.value)
            << " expected=" << vec4ToString(sample.expected)
            << " match=" << (sample.matches ? "true" : "false");
    }
}

bool ofApp::validateAdditionalFormats() {
    auxValidationLines_.clear();

    bool ok = true;
    ok = runAuxFormatValidation(StorageFormat::RG32Float, "writeDebugPatternRG32Float", "RG32Float") && ok;
    ok = runAuxFormatValidation(StorageFormat::RGBA16Float, "writeDebugPatternRGBA16Float", "RGBA16Float") && ok;
    return ok;
}

bool ofApp::runAuxFormatValidation(StorageFormat format,
                                   const std::string& kernelName,
                                   const std::string& label) {
    ofxSharedStorageTexture tempStorage;
    tempStorage.setSemantic("x", "y", format == StorageFormat::RG32Float ? "-" : "debug.b", format == StorageFormat::RG32Float ? "-" : "debug.a");

    if (!tempStorage.allocate(storageWidth_, storageHeight_, format)) {
        const std::string line = label + ": allocate failed: " + tempStorage.getLastError();
        auxValidationLines_.push_back(line);
        ofLogError("example-basic") << line;
        return false;
    }

    ofxMetalStorageCompute tempCompute;
    if (!tempCompute.setup()) {
        const std::string line = label + ": compute setup failed: " + tempCompute.getLastError();
        auxValidationLines_.push_back(line);
        ofLogError("example-basic") << line;
        return false;
    }
    if (!tempCompute.loadLibrary(libraryPathUsed_)) {
        const std::string line = label + ": loadLibrary failed: " + tempCompute.getLastError();
        auxValidationLines_.push_back(line);
        ofLogError("example-basic") << line;
        return false;
    }
    if (!tempCompute.loadKernel(kernelName)) {
        const std::string line = label + ": loadKernel failed: " + tempCompute.getLastError();
        auxValidationLines_.push_back(line);
        ofLogError("example-basic") << line;
        return false;
    }
    if (!tempCompute.bindOutputStorage(tempStorage, 0)) {
        const std::string line = label + ": bindOutputStorage failed: " + tempCompute.getLastError();
        auxValidationLines_.push_back(line);
        ofLogError("example-basic") << line;
        return false;
    }
    if (!tempCompute.dispatchForTextureSize() || !tempCompute.waitUntilCompleted()) {
        const std::string line = label + ": dispatch failed: " + tempCompute.getLastError();
        auxValidationLines_.push_back(line);
        ofLogError("example-basic") << line;
        return false;
    }

    const auto cpuValidation = ofxMetalGLStorageValidateDebugPattern(tempStorage);
    const auto glValidation = ofxMetalGLStorageValidateDebugPatternViaGLTexelFetch(tempStorage);

    const std::string line =
        label + ": CPU=" + cpuValidation.message + " | GL=" + glValidation.message;
    auxValidationLines_.push_back(line);
    ofLogNotice("example-basic") << line;

    for (const auto& sample : cpuValidation.samples) {
        ofLogNotice("example-basic")
            << label << " cpu(" << sample.coord.x << ", " << sample.coord.y << ") value="
            << vec4ToString(sample.value)
            << " expected=" << vec4ToString(sample.expected)
            << " match=" << (sample.matches ? "true" : "false");
    }
    for (const auto& sample : glValidation.samples) {
        ofLogNotice("example-basic")
            << label << " glTexelFetch(" << sample.coord.x << ", " << sample.coord.y << ") value="
            << vec4ToString(sample.value)
            << " expected=" << vec4ToString(sample.expected)
            << " match=" << (sample.matches ? "true" : "false");
    }

    return cpuValidation.ok && glValidation.ok;
}

std::string ofApp::buildOverlayText() const {
    std::string text;
    text += "ofxMetalGLStorageBridge / Example A\n";
    text += "Metal compute -> IOSurface-backed storage -> OpenGL sampler2DRect + texelFetch\n";
    text += "Storage: " + storage_.describe() + "\n";
    text += "Library: " + libraryPathUsed_ + "\n";
    text += "Validation: " + statusLine_ + "\n";
    text += "GLSL read path: sampler2DRect + texelFetch (see bin/data/shadersGL3/debugDataView.frag)\n";
    text += "Keys: r = rerun debug kernel\n";
    for (const auto& line : auxValidationLines_) {
        text += line + "\n";
    }
    text += "Sample GLSL:\n";
    text += ofxMetalGLStorageRecommendedRectSamplerGLSL();
    return text;
}
