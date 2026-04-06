#pragma once

#include "ofxSharedStorageTexture.h"

#include <memory>
#include <string>
#include <type_traits>

struct ofxMetalStorageComputeImpl;

class ofxMetalStorageCompute {
public:
    ofxMetalStorageCompute();
    ~ofxMetalStorageCompute();

    ofxMetalStorageCompute(ofxMetalStorageCompute&& other) noexcept;
    ofxMetalStorageCompute& operator=(ofxMetalStorageCompute&& other) noexcept;

    ofxMetalStorageCompute(const ofxMetalStorageCompute&) = delete;
    ofxMetalStorageCompute& operator=(const ofxMetalStorageCompute&) = delete;

    bool setup();
    bool loadLibrary(const std::string& metallibPath);
    bool loadKernel(const std::string& kernelName);

    bool bindInputStorage(ofxSharedStorageTexture& storage, int index);
    bool bindOutputStorage(ofxSharedStorageTexture& storage, int index);

    template<typename T>
    bool setParams(const T& params) {
        static_assert(std::is_trivially_copyable<T>::value,
                      "setParams requires a trivially copyable parameter block.");
        return setParamsBytes(&params, sizeof(T));
    }

    bool dispatchForTextureSize();
    bool dispatchThreads(int x, int y, int z = 1);
    bool waitUntilCompleted();

    std::string getLastError() const;

private:
    bool setParamsBytes(const void* data, size_t bytes);

    std::unique_ptr<ofxMetalStorageComputeImpl> impl_;
};
