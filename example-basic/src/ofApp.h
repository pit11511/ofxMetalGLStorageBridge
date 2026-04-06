#pragma once

#include "ofMain.h"
#include "ofxMetalGLStorageBridge.h"
#include "ofxMetalGLStorageUtils.h"

class ofApp : public ofBaseApp {
public:
    void setup() override;
    void update() override;
    void draw() override;
    void keyPressed(int key) override;

private:
    bool setupExample();
    bool runDebugKernel();
    bool validateAdditionalFormats();
    bool runAuxFormatValidation(StorageFormat format,
                                const std::string& kernelName,
                                const std::string& label);
    void logGLValidationSamples();
    void buildPreviewMesh();
    void logReadbackSamples();
    std::string buildOverlayText() const;

    ofxSharedStorageTexture storage_;
    ofxMetalStorageCompute compute_;
    ofShader previewShader_;
    ofMesh previewMesh_;
    ofxMetalGLStorageValidationResult validation_;
    ofxMetalGLStorageValidationResult glValidation_;

    int storageWidth_ = 16;
    int storageHeight_ = 8;
    float previewScale_ = 32.0f;
    std::string libraryPathUsed_;
    std::string statusLine_;
    std::vector<std::string> auxValidationLines_;
};
