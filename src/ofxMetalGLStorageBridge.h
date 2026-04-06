#pragma once

#include "ofxMetalStorageCompute.h"

class ofxSharedStoragePingPong {
public:
    bool allocate(int width, int height, StorageFormat format);
    bool allocateLike(const ofxSharedStorageTexture& other);
    void release();
    bool isAllocated() const;

    ofxSharedStorageTexture& front();
    const ofxSharedStorageTexture& front() const;
    ofxSharedStorageTexture& back();
    const ofxSharedStorageTexture& back() const;

    void swap();
    bool clearBoth();

private:
    ofxSharedStorageTexture storage_[2];
    int frontIndex_ = 0;
};

class ofxMetalGLStorageBridge {
public:
    bool setup(const std::string& libraryPath, const std::string& kernelName);
    bool allocate(int width, int height, StorageFormat format = StorageFormat::RGBA32Float);
    bool allocatePingPong(int width, int height, StorageFormat format = StorageFormat::RGBA32Float);

    ofxSharedStorageTexture& storage();
    const ofxSharedStorageTexture& storage() const;
    ofxSharedStoragePingPong& pingPong();
    const ofxSharedStoragePingPong& pingPong() const;

    ofxMetalStorageCompute& compute();
    const ofxMetalStorageCompute& compute() const;

    bool bindSingleAsOutput(int outputIndex = 0);
    bool bindPingPong(int inputIndex = 0, int outputIndex = 1);
    bool dispatchForTextureSize();
    void swapPingPong();

    std::string getLastError() const;

private:
    ofxMetalStorageCompute compute_;
    ofxSharedStorageTexture storage_;
    ofxSharedStoragePingPong pingPong_;
    bool usingPingPong_ = false;
    std::string lastError_;
};
