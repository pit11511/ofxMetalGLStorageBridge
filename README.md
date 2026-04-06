# ofxMetalGLStorageBridge

`ofxMetalGLStorageBridge` は、macOS 上で

`Metal compute -> IOSurface ベースの共有ストレージテクスチャ -> OpenGL 読み出し`

を行うための openFrameworks addon です。



- 1 texel = 1 particle
- `RGBA = position.xyz + life`
- 別テクスチャに `velocity.xyz + flag`
- Metal が毎フレーム更新
- OpenGL 側は `texelFetch` で後段パスから読む

通常経路では CPU copy を前提にせず、IOSurface を使って Metal と OpenGL が同じ underlying storage を共有します。

## 想定プラットフォーム

- macOS 専用
- Apple Silicon 優先
- openFrameworks + OpenGL 環境
- Metal は compute 専用

## なぜ IOSurface を使うのか

Metal texture と OpenGL texture を別々に持つと、毎フレーム CPU 経由の upload / download や GPU 間コピー管理が必要になります。IOSurface を使うと、同じ共有メモリを

- Metal 側では `newTextureWithDescriptor:iosurface:plane:`
- OpenGL 側では `CGLTexImageIOSurface2D`

で参照できます。

この addon では、この共有面を「描画用画像」ではなく「GPU データコンテナ」として扱います。

## アーキテクチャ

- `ofxSharedStorageTexture`
  - IOSurface の確保
  - Metal texture view の作成
  - OpenGL texture view の作成
  - upload / download / clear / fill
  - channel semantic の注釈
- `ofxMetalStorageCompute`
  - Metal device / queue / library / kernel
  - shared storage texture の bind
  - parameter buffer の設定
  - dispatch / wait
- `ofxSharedStoragePingPong`
  - `front()` / `back()` / `swap()`
- `ofxMetalGLStorageBridge`
  - よくある setup をまとめる高レベルラッパ

## ストレージ指向であり draw 指向ではない

この addon の API は `draw()` を中心にしません。

中心になる操作は以下です。

- allocate
- bind input / output storage
- dispatch
- upload / download
- validate
- swap

OpenGL 側へ渡すのは「可視化用テクスチャ」ではなく「GPU データリソースの texture handle」です。

## 重要な OpenGL 制約

Apple の `CGLTexImageIOSurface2D` は、公式ヘッダ上は `GL_TEXTURE_RECTANGLE` を前提にした API です。  
そのため本 addon では OpenGL 側ターゲットを `GL_TEXTURE_RECTANGLE` に固定しています。

つまり OpenGL 側の読み出しは、通常の `sampler2D` ではなく次を推奨します。

- `sampler2DRect + texelFetch`

この方針は draw の見た目より、整数 texel 座標での厳密なデータ読み出しを優先しています。

## 座標系 / Y flip について

この addon ではストレージ座標を明示的に次で定義します。

- Metal kernel の `thread_position_in_grid` をそのまま texel 座標とみなす
- `(0, 0)` は CPU readback の先頭 row
- CPU upload / download は top-to-bottom の row-major packed data として扱う

注意点:

- OpenGL の「画面座標」は下原点の文脈が混ざることがあります
- しかし本 addon の intended path は screen UV ではなく integer texel access です
- したがって OpenGL 側でも `texelFetch` の texel index を明示し、画像サンプリング風の `texture()` には依存しないでください

`example-basic` では `RGBA32Float` を主例として、追加で `RG32Float` と `RGBA16Float` に対しても Metal 側から

- `R = x`
- `G = y`
- `B = 1000 + x + 100*y`
- `A = 1`

を書き込み、CPU readback と GLSL の両方で layout を確認できます。

## チャンネル順序について

この addon は BGRA のような表示寄り format を既定にしません。
数値ストレージ用途を優先し、基本は以下を使います。

- `R32Float`
- `RG32Float`
- `RGBA16Float`
- `RGBA32Float`
- `RGBA8Uint`

既定サンプルは `RGBA32Float` です。

### 現状の format 対応

| StorageFormat | 状態 | 備考 |
|---|---|---|
| `R32Float` | 対応 | 1ch float |
| `RG32Float` | 対応 | 2ch float |
| `RGBA16Float` | 対応 | 4ch half float |
| `RGBA32Float` | 対応 | 4ch float |
| `RGBA8Uint` | 対応 | 4ch uint8 |
| `RGBA32Uint` | 未対応 | IOSurface 側 pixel format 対応を要確認 |

`RGBA32Uint` は API enum には入っていますが、現時点では allocate を失敗させます。
理由は「Metal / OpenGL / IOSurface で 128-bit RGBA uint storage を明確に対応付ける pixel format」を安全に固定できていないためです。

## OpenGL 側は `texelFetch` 推奨

シミュレーションデータでは補間を避けるべきです。

推奨:

```glsl
#version 150
uniform sampler2DRect uStorageTex;
ivec2 coord = ivec2(12, 7);
vec4 raw = texelFetch(uStorageTex, coord);
```

非推奨:

```glsl
vec4 raw = texture(uStorageTex, uv);
```

`texture()` は補間や座標正規化の文脈と混ざりやすく、データストレージ用途では誤読の原因になります。

## CPU upload / download について

`upload()` と `download()` は packed row data を受け取り、内部では IOSurface の `bytesPerRow` alignment を吸収します。

- 呼び出し側は `width * height * bytesPerPixel` の連続メモリを渡す
- addon 側が row ごとに aligned row bytes へコピーする

そのため debug / 初期化用途では扱いやすいですが、通常フレーム更新は GPU だけで完結させる想定です。

## デバッグ / validation

以下を実装しています。

- Metal 側 debug pattern kernel
- CPU download
- `readTexelDebug(x, y)`
- `ofxMetalGLStorageValidateDebugPattern(...)`

これにより次を確認しやすくしています。

- Metal が期待通りに書けているか
- CPU readback が一致するか
- Y flip の疑い
- channel order mismatch の疑い

さらに OpenGL 側の end-to-end 検証用として

- `ofxMetalGLStorageValidateDebugPatternViaGLTexelFetch(...)`

を用意しています。これは一時 FBO に対して

- `sampler2DRect + texelFetch`

で shared texture を 1:1 読み出し

- `glReadPixels`

で float readback
- known debug pattern と数値比較

を行います。

## 使い方の最小例

```cpp
ofxSharedStorageTexture storage;
storage.allocate(256, 256, StorageFormat::RGBA32Float);
storage.setSemantic("pos.x", "pos.y", "pos.z", "life");

ofxMetalStorageCompute compute;
compute.setup();
compute.loadLibrary(ofToDataPath("metal/ofxMetalGLStorageKernels.metallib", true));
compute.loadKernel("writeDebugPattern");
compute.bindOutputStorage(storage, 0);
compute.dispatchForTextureSize();
compute.waitUntilCompleted();

GLuint glTex = storage.getGLTextureID();
GLenum glTarget = storage.getGLTextureTarget(); // GL_TEXTURE_RECTANGLE
```

## ping-pong

反復シミュレーション用に `ofxSharedStoragePingPong` を入れています。

```cpp
ofxSharedStoragePingPong pingPong;
pingPong.allocate(1024, 1024, StorageFormat::RGBA32Float);

compute.bindInputStorage(pingPong.front(), 0);
compute.bindOutputStorage(pingPong.back(), 1);
compute.dispatchForTextureSize();
compute.waitUntilCompleted();
pingPong.swap();
```

## example-basic

`example-basic` は次を行います。

1. `RGBA32Float` の shared storage を確保
2. Metal の `writeDebugPattern` kernel を dispatch
3. `waitUntilCompleted()`
4. CPU `download()` で複数 texel をログ出力
5. 同じ texture を OpenGL の `sampler2DRect + texelFetch` でプレビュー
6. OpenGL 側でも `texelFetch -> FBO -> glReadPixels` の数値検証
7. `RG32Float` と `RGBA16Float` でも同じ CPU/GL validation

### 実行前に metallib を作る

production path としては compiled `.metallib` を使うのが安全です。

```bash
cd addons/ofxMetalGLStorageBridge
./scripts/build_metallib.sh
```

`example-pingpong` 用の particle simulation kernel を build する場合:

```bash
cd addons/ofxMetalGLStorageBridge
./scripts/build_metallib.sh \
  example-pingpong/bin/data/metal/ofxMetalGLStorageParticles.metal \
  example-pingpong/bin/data/metal/ofxMetalGLStorageParticles.metallib
```

`xcrun metal` が

`cannot execute tool 'metal' due to missing Metal Toolchain`

で失敗する場合は、先に以下を実行してください。

```bash
xcodebuild -downloadComponent MetalToolchain
```

生成先:

- `example-basic/bin/data/metal/ofxMetalGLStorageKernels.metallib`

### source fallback

example と `ofxMetalStorageCompute::loadLibrary()` は、`.metallib` が見つからない場合に `.metal` source の runtime compile も試せます。  
ただしこれは debug / convenience 用です。production では `.metallib` を推奨します。

### project generator

`addons/ofxMetalGLStorageBridge/example-basic` を project generator で開き、addon として `ofxMetalGLStorageBridge` を含めてください。

## example-pingpong

`example-pingpong` は実更新ロジック付きの ping-pong simulation 例です。

- `positionLife` ping-pong
  - `R=pos.x`
  - `G=pos.y`
  - `B=pos.z`
  - `A=life`
- `velocityFlag` ping-pong
  - `R=vel.x`
  - `G=vel.y`
  - `B=vel.z`
  - `A=flag`

Metal 側では

- `initParticleState`
- `updateParticleState`

の 2 kernel を使います。

OpenGL 側では vertex shader が

- `sampler2DRect uPositionLifeTex`
- `sampler2DRect uVelocityFlagTex`

から `texelFetch` し、`gl_VertexID` を particle index として point rendering します。

これは

- simulation state は shared storage texture に置く
- draw pass は state texture を `texelFetch` で読む

という intended path の実例です。

### project generator

`addons/ofxMetalGLStorageBridge/example-pingpong` を project generator で開き、addon として `ofxMetalGLStorageBridge` を含めてください。

## `setParams()` の例

kernel に parameter struct を渡す場合は `setParams()` を使います。

```cpp
struct ParticleSimParams {
    float deltaTime;
    float time;
    float bounds;
    float damping;
};

ParticleSimParams params;
params.deltaTime = ofGetLastFrameTime();
params.time = ofGetElapsedTimef();
params.bounds = 0.92f;
params.damping = 0.995f;

compute.setParams(params);
compute.dispatchForTextureSize();
compute.waitUntilCompleted();
```

注意:

- struct は trivially copyable である必要があります
- Metal 側 struct と field order / alignment を一致させてください

## 制限事項

- macOS only
- OpenGL side は `GL_TEXTURE_RECTANGLE`
- OpenGL は deprecated API
- `RGBA32Uint` は未対応
- `imageLoad` 系の利用は macOS OpenGL driver 差を受けやすいため、この addon では `sampler2DRect + texelFetch` を既定例にしている
- GL / Metal の完全な fence 同期 abstraction までは入れていない

## 今後の候補

- `RGBA32Uint` の安全な IOSurface mapping を追加
- kernel reflection を使った bind validation
- 複数 parameter buffer / raw MTLBuffer bind
- GL image unit path の追加検証
- fence / event ベース同期の整理

## TODO と明示している不確定点

1. `RGBA32Uint`
   明確な IOSurface pixel format 対応が未確定なので、現実装では unsupported にしています。
2. `GL_TEXTURE_2D` 対応
   一部環境では動く例がありますが、Apple の `CGLTexImageIOSurface2D` ヘッダ記述に合わせて本 addon は `GL_TEXTURE_RECTANGLE` を既定にしています。
3. OpenGL `imageLoad`
   macOS driver 差異を踏まえ、README と example では `texelFetch` を優先しています。
