#pragma once

#include "ofMain.h"
#include "ofxMetalGLStorageTypes.h"

#include <memory>
#include <string>

struct ofxSharedStorageTextureImpl;

class ofxSharedStorageTexture {
public:
    ofxSharedStorageTexture();
    ~ofxSharedStorageTexture();

    ofxSharedStorageTexture(ofxSharedStorageTexture&& other) noexcept;
    ofxSharedStorageTexture& operator=(ofxSharedStorageTexture&& other) noexcept;

    ofxSharedStorageTexture(const ofxSharedStorageTexture&) = delete;
    ofxSharedStorageTexture& operator=(const ofxSharedStorageTexture&) = delete;

    bool allocate(int width, int height, StorageFormat format);
    bool allocateLike(const ofxSharedStorageTexture& other);
    void release();
    bool isAllocated() const;

    int getWidth() const;
    int getHeight() const;
    StorageFormat getFormat() const;
    int getNumChannels() const;
    size_t getBytesPerPixel() const;
    size_t getBytesPerRow() const;
    size_t getElementCount() const;

    GLuint getGLTextureID() const;
    GLenum getGLTextureTarget() const;

    bool clear();
    bool fill(float r, float g, float b, float a);

    // Upload/download expect tightly packed rows in the storage's native texel layout.
    bool upload(const void* data, size_t bytes);
    bool download(void* outData, size_t bytes) const;

    glm::vec4 readTexelDebug(int x, int y) const;

    void setSemantic(const std::string& r,
                     const std::string& g,
                     const std::string& b,
                     const std::string& a);
    std::string describe() const;
    std::string getLastError() const;

private:
    friend class ofxMetalStorageCompute;

    void* getMetalTextureHandle() const;

    std::unique_ptr<ofxSharedStorageTextureImpl> impl_;
};
