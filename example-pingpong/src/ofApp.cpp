#include "ofApp.h"

void ofApp::setup() {
    ofSetWindowTitle("ofxMetalGLStorageBridge example-pingpong");
    ofSetFrameRate(60);
    ofEnableAlphaBlending();
    glEnable(GL_PROGRAM_POINT_SIZE);

    buildParticleMesh();
    particleShader_.load("shadersGL3/particles");

    if (!setupSimulation()) {
        ofLogError("example-pingpong") << statusLine_;
    }
}

void ofApp::update() {
    if (!paused_ || singleStep_) {
        stepSimulation();
        singleStep_ = false;
    }
}

void ofApp::draw() {
    ofBackgroundGradient(ofColor(5, 8, 12), ofColor(12, 18, 28), OF_GRADIENT_CIRCULAR);

    ofEnableBlendMode(OF_BLENDMODE_ADD);
    if (particleShader_.isLoaded() && particleCount_ > 0) {
        particleShader_.begin();
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(positionLife_.front().getGLTextureTarget(), positionLife_.front().getGLTextureID());
        particleShader_.setUniform1i("uPositionLifeTex", 0);

        glActiveTexture(GL_TEXTURE1);
        glBindTexture(velocityFlag_.front().getGLTextureTarget(), velocityFlag_.front().getGLTextureID());
        particleShader_.setUniform1i("uVelocityFlagTex", 1);

        particleShader_.setUniform2i("uStorageSize", storageWidth_, storageHeight_);
        particleShader_.setUniform1f("uPointScale", pointScale_);

        particleMesh_.draw();

        glActiveTexture(GL_TEXTURE1);
        glBindTexture(velocityFlag_.front().getGLTextureTarget(), 0);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(positionLife_.front().getGLTextureTarget(), 0);
        particleShader_.end();
    }
    ofDisableBlendMode();

    ofSetColor(255);
    ofDrawBitmapStringHighlight(buildOverlayText(), 24, 28, ofColor(0, 0, 0, 170), ofColor::white);
}

void ofApp::keyPressed(int key) {
    if (key == ' ') {
        paused_ = !paused_;
    } else if (key == 's') {
        singleStep_ = true;
        paused_ = true;
    } else if (key == 'r') {
        initializeParticles();
    }
}

bool ofApp::setupSimulation() {
    particleCount_ = storageWidth_ * storageHeight_;
    buildParticleMesh();

    positionLife_.front().setSemantic("pos.x", "pos.y", "pos.z", "life");
    positionLife_.back().setSemantic("pos.x", "pos.y", "pos.z", "life");
    velocityFlag_.front().setSemantic("vel.x", "vel.y", "vel.z", "flag");
    velocityFlag_.back().setSemantic("vel.x", "vel.y", "vel.z", "flag");

    if (!positionLife_.allocate(storageWidth_, storageHeight_, StorageFormat::RGBA32Float)) {
        statusLine_ = "positionLife allocate failed";
        return false;
    }
    if (!velocityFlag_.allocate(storageWidth_, storageHeight_, StorageFormat::RGBA32Float)) {
        statusLine_ = "velocityFlag allocate failed";
        return false;
    }

    const std::string metallibPath =
        ofToDataPath("metal/ofxMetalGLStorageParticles.metallib", true);
    const std::string metalSourcePath =
        ofToDataPath("metal/ofxMetalGLStorageParticles.metal", true);
    libraryPathUsed_ = ofFile::doesFileExist(metallibPath) ? metallibPath : metalSourcePath;

    if (!initCompute_.setup()) {
        statusLine_ = "init compute setup failed: " + initCompute_.getLastError();
        return false;
    }
    if (!initCompute_.loadLibrary(libraryPathUsed_)) {
        statusLine_ = "init loadLibrary failed: " + initCompute_.getLastError();
        return false;
    }
    if (!initCompute_.loadKernel("initParticleState")) {
        statusLine_ = "init loadKernel failed: " + initCompute_.getLastError();
        return false;
    }

    if (!updateCompute_.setup()) {
        statusLine_ = "update compute setup failed: " + updateCompute_.getLastError();
        return false;
    }
    if (!updateCompute_.loadLibrary(libraryPathUsed_)) {
        statusLine_ = "update loadLibrary failed: " + updateCompute_.getLastError();
        return false;
    }
    if (!updateCompute_.loadKernel("updateParticleState")) {
        statusLine_ = "update loadKernel failed: " + updateCompute_.getLastError();
        return false;
    }

    return initializeParticles();
}

bool ofApp::initializeParticles() {
    if (!initCompute_.bindOutputStorage(positionLife_.front(), 0)) {
        statusLine_ = "init bind position output failed: " + initCompute_.getLastError();
        return false;
    }
    if (!initCompute_.bindOutputStorage(velocityFlag_.front(), 1)) {
        statusLine_ = "init bind velocity output failed: " + initCompute_.getLastError();
        return false;
    }
    if (!initCompute_.dispatchForTextureSize() || !initCompute_.waitUntilCompleted()) {
        statusLine_ = "init dispatch failed: " + initCompute_.getLastError();
        return false;
    }

    positionLife_.back().clear();
    velocityFlag_.back().clear();

    statusLine_ = "initialized particle storage";
    ofLogNotice("example-pingpong") << statusLine_;
    return true;
}

bool ofApp::stepSimulation() {
    ParticleSimParams params;
    params.deltaTime = ofClamp(ofGetLastFrameTime(), 1.0f / 240.0f, 1.0f / 24.0f);
    params.time = ofGetElapsedTimef();
    params.bounds = 0.92f;
    params.damping = 0.995f;

    if (!updateCompute_.bindInputStorage(positionLife_.front(), 0)) {
        statusLine_ = "bind position input failed: " + updateCompute_.getLastError();
        return false;
    }
    if (!updateCompute_.bindInputStorage(velocityFlag_.front(), 1)) {
        statusLine_ = "bind velocity input failed: " + updateCompute_.getLastError();
        return false;
    }
    if (!updateCompute_.bindOutputStorage(positionLife_.back(), 2)) {
        statusLine_ = "bind position output failed: " + updateCompute_.getLastError();
        return false;
    }
    if (!updateCompute_.bindOutputStorage(velocityFlag_.back(), 3)) {
        statusLine_ = "bind velocity output failed: " + updateCompute_.getLastError();
        return false;
    }
    if (!updateCompute_.setParams(params)) {
        statusLine_ = "setParams failed: " + updateCompute_.getLastError();
        return false;
    }
    if (!updateCompute_.dispatchForTextureSize() || !updateCompute_.waitUntilCompleted()) {
        statusLine_ = "update dispatch failed: " + updateCompute_.getLastError();
        return false;
    }

    positionLife_.swap();
    velocityFlag_.swap();
    statusLine_ = "simulation running";
    return true;
}

void ofApp::buildParticleMesh() {
    particleCount_ = storageWidth_ * storageHeight_;
    particleMesh_.clear();
    particleMesh_.setMode(OF_PRIMITIVE_POINTS);
    for (int i = 0; i < particleCount_; ++i) {
        particleMesh_.addVertex(glm::vec3(0.0f, 0.0f, 0.0f));
    }
}

std::string ofApp::buildOverlayText() const {
    std::string text;
    text += "ofxMetalGLStorageBridge / Example B\n";
    text += "Ping-pong simulation using two shared storage pairs\n";
    text += "positionLife: R=pos.x G=pos.y B=pos.z A=life\n";
    text += "velocityFlag: R=vel.x G=vel.y B=vel.z A=flag\n";
    text += "Storage size: " + ofToString(storageWidth_) + " x " + ofToString(storageHeight_);
    text += " (" + ofToString(particleCount_) + " particles)\n";
    text += "Metal library: " + libraryPathUsed_ + "\n";
    text += "Status: " + statusLine_ + "\n";
    text += "OpenGL path: vertex shader texelFetch() from sampler2DRect\n";
    text += "Keys: space = pause/resume, s = single-step, r = reinitialize\n";
    return text;
}
