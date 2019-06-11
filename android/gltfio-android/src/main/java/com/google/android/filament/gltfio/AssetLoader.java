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

package com.google.android.filament.gltfio;

import android.support.annotation.NonNull;
import android.support.annotation.Nullable;

import com.google.android.filament.Engine;

import java.lang.reflect.Method;
import java.nio.Buffer;

public class AssetLoader {
    private long mNativeObject;

    private static Method sEngineGetNativeObject;

    static {
        System.loadLibrary("gltfio-jni");
        try {
            sEngineGetNativeObject = Engine.class.getDeclaredMethod("getNativeObject");
            sEngineGetNativeObject.setAccessible(true);
        } catch (NoSuchMethodException e) {
            // Cannot happen
        }
    }

    AssetLoader(@NonNull Engine engine, @NonNull MaterialGenerator generator) {
        try {
            long nativeEngine = (Long) sEngineGetNativeObject.invoke(engine);
            mNativeObject = nCreateAssetLoader(nativeEngine, generator.getNativeObject());
        } catch (Exception e) {
            // Ignored
        }
    }

    public void destroy() {
        nDestroyAssetLoader(mNativeObject);
        mNativeObject = 0;
    }

    @Nullable
    public FilamentAsset createAssetFromJson(@NonNull Buffer buffer) {
        long nativeAsset = nCreateAssetFromJson(mNativeObject, buffer, buffer.remaining());
        return new FilamentAsset(nativeAsset);
    }

    @Nullable
    public FilamentAsset createAssetFromBinary(@NonNull Buffer buffer) {
        long nativeAsset = nCreateAssetFromBinary(mNativeObject, buffer, buffer.remaining());
        return new FilamentAsset(nativeAsset);
    }

    public void enableDiagnostics(boolean enable) {
        nEnableDiagnostics(mNativeObject, enable);
    }

    public void destroyAsset(@Nullable FilamentAsset asset) {
        nDestroyAsset(mNativeObject, asset.getNativeObject());
        asset.clearNativeObject();
    }

    private static native long nCreateAssetLoader(long nativeEngine, long nativeGenerator);
    private static native void nDestroyAssetLoader(long nativeLoader);
    private static native long nCreateAssetFromJson(long nativeLoader, Buffer buffer, int remaining);
    private static native long nCreateAssetFromBinary(long nativeLoader, Buffer buffer, int remaining);
    private static native long nEnableDiagnostics(long nativeLoader, boolean enable);
    private static native long nDestroyAsset(long nativeLoader, long nativeAsset);
}
