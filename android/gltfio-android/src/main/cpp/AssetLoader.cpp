/*
 * Copyright (C) 2019 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <jni.h>

#include <gltfio/AssetLoader.h>

using namespace filament;
using namespace gltfio;

#if 0

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderInit(JNIEnv*, jclass) {
    AssetLoader::init();
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderShutdown(JNIEnv*, jclass) {
    AssetLoader::shutdown();
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nCreateAssetLoader(JNIEnv*, jclass) {
    return (jlong) new AssetLoader();
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nDestroyAssetLoader(JNIEnv*, jclass,
        jlong nativeBuilder) {
    auto builder = (AssetLoader*) nativeBuilder;
    delete builder;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nBuilderBuild(JNIEnv*, jclass,
        jlong nativeBuilder) {
    auto builder = (AssetLoader*) nativeBuilder;
    return (jlong) new Package(builder->build());
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nGetPackageBytes(JNIEnv* env, jclass,
        jlong nativePackage) {
    auto package = (Package*) nativePackage;
    auto size = jsize(package->getSize());
    jbyteArray ret = env->NewByteArray(size);
    auto data = (jbyte*) package->getData();
    env->SetByteArrayRegion(ret, 0, size, data);
    return ret;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nGetPackageIsValid(JNIEnv*, jclass,
        jlong nativePackage) {
    auto* package = (Package*) nativePackage;
    return jboolean(package->isValid());
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nDestroyPackage(JNIEnv*, jclass,
        jlong nativePackage) {
    Package* package = (Package*) nativePackage;
    delete package;
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderName(JNIEnv* env,
        jclass, jlong nativeBuilder, jstring name_) {
    auto builder = (AssetLoader*) nativeBuilder;
    const char* name = env->GetStringUTFChars(name_, nullptr);
    builder->name(name);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderShading(JNIEnv*,
        jclass, jlong nativeBuilder, jint shading) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->shading((AssetLoader::Shading) shading);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderInterpolation(JNIEnv*,
        jclass, jlong nativeBuilder, jint interpolation) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->interpolation((AssetLoader::Interpolation) interpolation);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderUniformParameter(
        JNIEnv* env, jclass, jlong nativeBuilder, jint uniformType, jstring name_) {
    auto builder = (AssetLoader*) nativeBuilder;
    const char* name = env->GetStringUTFChars(name_, nullptr);
    builder->parameter((AssetLoader::UniformType) uniformType, name);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderUniformParameterArray(
        JNIEnv* env, jclass, jlong nativeBuilder, jint uniformType, jint size, jstring name_) {
    auto builder = (AssetLoader*) nativeBuilder;
    const char* name = env->GetStringUTFChars(name_, nullptr);
    builder->parameter((AssetLoader::UniformType) uniformType, (size_t) size, name);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderSamplerParameter(
        JNIEnv* env, jclass, jlong nativeBuilder, jint samplerType, jint format,
        jint precision, jstring name_) {
    auto builder = (AssetLoader*) nativeBuilder;
    const char* name = env->GetStringUTFChars(name_, nullptr);
    builder->parameter((AssetLoader::SamplerType) samplerType,
            (AssetLoader::SamplerFormat) format, (AssetLoader::SamplerPrecision) precision,
            name);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderVariable(
        JNIEnv* env, jclass, jlong nativeBuilder, jint variable, jstring name_) {
    const char* name = env->GetStringUTFChars(name_, nullptr);
    auto builder = (AssetLoader*) nativeBuilder;
    builder->variable((AssetLoader::Variable) variable, name);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderRequire(JNIEnv*,
        jclass, jlong nativeBuilder, jint attribute) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->require((VertexAttribute) attribute);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderMaterial(JNIEnv* env,
        jclass, jlong nativeBuilder, jstring code_) {
    auto builder = (AssetLoader*) nativeBuilder;
    const char* code = env->GetStringUTFChars(code_, nullptr);
    builder->material(code);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderMaterialVertex(JNIEnv* env,
        jclass, jlong nativeBuilder, jstring code_) {
    auto builder = (AssetLoader*) nativeBuilder;
    const char* code = env->GetStringUTFChars(code_, nullptr);
    builder->materialVertex(code);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderBlending(JNIEnv*,
        jclass, jlong nativeBuilder, jint mode) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->blending((AssetLoader::BlendingMode) mode);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderPostLightingBlending(
        JNIEnv*, jclass, jlong nativeBuilder, jint mode) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->postLightingBlending((AssetLoader::BlendingMode) mode);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderVertexDomain(JNIEnv*,
        jclass, jlong nativeBuilder, jint vertexDomain) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->vertexDomain((AssetLoader::VertexDomain) vertexDomain);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderCulling(JNIEnv*,
        jclass, jlong nativeBuilder, jint mode) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->culling((AssetLoader::CullingMode) mode);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderColorWrite(JNIEnv*,
        jclass, jlong nativeBuilder, jboolean enable) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->colorWrite(enable);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderDepthWrite(JNIEnv*,
        jclass, jlong nativeBuilder, jboolean depthWrite) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->depthWrite(depthWrite);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderDepthCulling(JNIEnv*,
        jclass, jlong nativeBuilder, jboolean depthCulling) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->depthCulling(depthCulling);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderDoubleSided(JNIEnv*,
        jclass, jlong nativeBuilder, jboolean doubleSided) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->doubleSided(doubleSided);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderMaskThreshold(JNIEnv*,
        jclass, jlong nativeBuilder, jfloat maskThreshold) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->maskThreshold(maskThreshold);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderShadowMultiplier(
        JNIEnv*, jclass, jlong nativeBuilder, jboolean shadowMultiplier) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->shadowMultiplier(shadowMultiplier);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderSpecularAntiAliasing(
        JNIEnv*, jclass, jlong nativeBuilder, jboolean specularAntiAliasing) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->specularAntiAliasing(specularAntiAliasing);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderSpecularAntiAliasingVariance(
        JNIEnv*, jclass, jlong nativeBuilder, jfloat variance) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->specularAntiAliasingVariance(variance);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderSpecularAntiAliasingThreshold(
        JNIEnv*, jclass, jlong nativeBuilder, jfloat threshold) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->specularAntiAliasingThreshold(threshold);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderClearCoatIorChange(
        JNIEnv*, jclass, jlong nativeBuilder, jboolean clearCoatIorChange) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->clearCoatIorChange(clearCoatIorChange);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderFlipUV(JNIEnv*,
        jclass, jlong nativeBuilder, jboolean flipUV) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->flipUV(flipUV);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderMultiBounceAmbientOcclusion(
        JNIEnv*, jclass, jlong nativeBuilder, jboolean multiBounceAO) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->multiBounceAmbientOcclusion(multiBounceAO);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderSpecularAmbientOcclusion(
        JNIEnv*, jclass, jlong nativeBuilder, jboolean specularAO) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->specularAmbientOcclusion(specularAO);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderTransparencyMode(
        JNIEnv* env, jclass, jlong nativeBuilder, jint mode) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->transparencyMode((AssetLoader::TransparencyMode) mode);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderPlatform(JNIEnv*,
        jclass, jlong nativeBuilder, jint platform) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->platform((AssetLoader::Platform) platform);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderTargetApi(JNIEnv*,
        jclass, jlong nativeBuilder, jint targetApi) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->targetApi((AssetLoader::TargetApi) targetApi);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderOptimization(JNIEnv*,
        jclass, jlong nativeBuilder, jint optimization) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->optimization((AssetLoader::Optimization) optimization);
}

extern "C" JNIEXPORT void JNICALL
Java_com_google_android_filament_gltfio_AssetLoader_nAssetLoaderVariantFilter(JNIEnv*,
        jclass, jlong nativeBuilder, jbyte variantFilter) {
    auto builder = (AssetLoader*) nativeBuilder;
    builder->variantFilter((uint8_t) variantFilter);
}

#endif