meta:
	ADDON_NAME = ofxMetalGLStorageBridge
	ADDON_DESCRIPTION = macOS-only shared GPU data storage for Metal compute to OpenGL read access through IOSurface
	ADDON_AUTHOR = OpenAI Codex
	ADDON_TAGS = "metal" "opengl" "iosurface" "compute" "data-texture" "macos"
	ADDON_URL = https://github.com/openframeworks/openFrameworks

common:
	ADDON_INCLUDES = src
	ADDON_CPPFLAGS += -DGL_SILENCE_DEPRECATION

osx:
	ADDON_FRAMEWORKS += Foundation
	ADDON_FRAMEWORKS += Metal
	ADDON_FRAMEWORKS += IOSurface
	ADDON_FRAMEWORKS += CoreVideo
	ADDON_FRAMEWORKS += OpenGL
