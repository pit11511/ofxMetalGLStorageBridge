#include "ofxMetalGLStorageBridge.h"

bool ofxSharedStoragePingPong::allocate(int width, int height, StorageFormat format) {
    release();
    frontIndex_ = 0;
    if (!storage_[0].allocate(width, height, format)) {
        return false;
    }
    if (!storage_[1].allocate(width, height, format)) {
        storage_[0].release();
        return false;
    }
    return true;
}

bool ofxSharedStoragePingPong::allocateLike(const ofxSharedStorageTexture& other) {
    return allocate(other.getWidth(), other.getHeight(), other.getFormat());
}

void ofxSharedStoragePingPong::release() {
    storage_[0].release();
    storage_[1].release();
    frontIndex_ = 0;
}

bool ofxSharedStoragePingPong::isAllocated() const {
    return storage_[0].isAllocated() && storage_[1].isAllocated();
}

ofxSharedStorageTexture& ofxSharedStoragePingPong::front() {
    return storage_[frontIndex_];
}

const ofxSharedStorageTexture& ofxSharedStoragePingPong::front() const {
    return storage_[frontIndex_];
}

ofxSharedStorageTexture& ofxSharedStoragePingPong::back() {
    return storage_[1 - frontIndex_];
}

const ofxSharedStorageTexture& ofxSharedStoragePingPong::back() const {
    return storage_[1 - frontIndex_];
}

void ofxSharedStoragePingPong::swap() {
    frontIndex_ = 1 - frontIndex_;
}

bool ofxSharedStoragePingPong::clearBoth() {
    return storage_[0].clear() && storage_[1].clear();
}

bool ofxMetalGLStorageBridge::setup(const std::string& libraryPath, const std::string& kernelName) {
    lastError_.clear();
    if (!compute_.setup()) {
        lastError_ = compute_.getLastError();
        return false;
    }
    if (!compute_.loadLibrary(libraryPath)) {
        lastError_ = compute_.getLastError();
        return false;
    }
    if (!compute_.loadKernel(kernelName)) {
        lastError_ = compute_.getLastError();
        return false;
    }
    return true;
}

bool ofxMetalGLStorageBridge::allocate(int width, int height, StorageFormat format) {
    usingPingPong_ = false;
    if (!storage_.allocate(width, height, format)) {
        lastError_ = storage_.getLastError();
        return false;
    }
    return true;
}

bool ofxMetalGLStorageBridge::allocatePingPong(int width, int height, StorageFormat format) {
    usingPingPong_ = true;
    if (!pingPong_.allocate(width, height, format)) {
        lastError_ = "Failed to allocate ping-pong textures";
        return false;
    }
    return true;
}

ofxSharedStorageTexture& ofxMetalGLStorageBridge::storage() {
    return storage_;
}

const ofxSharedStorageTexture& ofxMetalGLStorageBridge::storage() const {
    return storage_;
}

ofxSharedStoragePingPong& ofxMetalGLStorageBridge::pingPong() {
    return pingPong_;
}

const ofxSharedStoragePingPong& ofxMetalGLStorageBridge::pingPong() const {
    return pingPong_;
}

ofxMetalStorageCompute& ofxMetalGLStorageBridge::compute() {
    return compute_;
}

const ofxMetalStorageCompute& ofxMetalGLStorageBridge::compute() const {
    return compute_;
}

bool ofxMetalGLStorageBridge::bindSingleAsOutput(int outputIndex) {
    if (!storage_.isAllocated()) {
        lastError_ = "Single storage is not allocated";
        return false;
    }
    if (!compute_.bindOutputStorage(storage_, outputIndex)) {
        lastError_ = compute_.getLastError();
        return false;
    }
    return true;
}

bool ofxMetalGLStorageBridge::bindPingPong(int inputIndex, int outputIndex) {
    if (!pingPong_.isAllocated()) {
        lastError_ = "Ping-pong storage is not allocated";
        return false;
    }
    if (!compute_.bindInputStorage(pingPong_.front(), inputIndex)) {
        lastError_ = compute_.getLastError();
        return false;
    }
    if (!compute_.bindOutputStorage(pingPong_.back(), outputIndex)) {
        lastError_ = compute_.getLastError();
        return false;
    }
    return true;
}

bool ofxMetalGLStorageBridge::dispatchForTextureSize() {
    if (!compute_.dispatchForTextureSize()) {
        lastError_ = compute_.getLastError();
        return false;
    }
    return true;
}

void ofxMetalGLStorageBridge::swapPingPong() {
    pingPong_.swap();
}

std::string ofxMetalGLStorageBridge::getLastError() const {
    if (!lastError_.empty()) {
        return lastError_;
    }
    return compute_.getLastError();
}
