#pragma once

#include "ofMain.h"
#include "ofxMetalGLStorageBridge.h"

struct ParticleSimParams {
    float deltaTime = 0.016f;
    float time = 0.0f;
    float bounds = 0.92f;
    float damping = 0.995f;
};

class ofApp : public ofBaseApp {
public:
    void setup() override;
    void update() override;
    void draw() override;
    void keyPressed(int key) override;

private:
    bool setupSimulation();
    bool initializeParticles();
    bool stepSimulation();
    void buildParticleMesh();
    std::string buildOverlayText() const;

    ofxSharedStoragePingPong positionLife_;
    ofxSharedStoragePingPong velocityFlag_;
    ofxMetalStorageCompute initCompute_;
    ofxMetalStorageCompute updateCompute_;

    ofShader particleShader_;
    ofMesh particleMesh_;

    int storageWidth_ = 128;
    int storageHeight_ = 128;
    int particleCount_ = 0;
    float pointScale_ = 4.0f;
    bool paused_ = false;
    bool singleStep_ = false;

    std::string libraryPathUsed_;
    std::string statusLine_;
};
