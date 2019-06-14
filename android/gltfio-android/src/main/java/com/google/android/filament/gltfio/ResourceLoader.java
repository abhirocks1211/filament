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

public class ResourceLoader {
    private long mNativeObject;

    private static Method sEngineGetNativeObject;

    public ResourceLoader(@NonNull Engine engine) {
        try {
            long nativeEngine = (long) sEngineGetNativeObject.invoke(engine);
            mNativeObject = nCreateResourceLoader(nativeEngine);
        } catch (Exception e) {
            // Ignored
        }
    }

    public void destroy() {
        nDestroyResourceLoader(mNativeObject);
        mNativeObject = 0;
    }

    public void addResourceData(@NonNull String url, @NonNull Buffer buffer) {
        nAddResourceData(mNativeObject, url, buffer, buffer.remaining());
    }

    public void loadResources(@NonNull FilamentAsset asset) {
        nLoadResources(mNativeObject, asset.getNativeObject());
    }

    private static native long nCreateResourceLoader(long nativeEngine);
    private static native void nDestroyResourceLoader(long nativeLoader);
    private static native long nAddResourceData(long nativeLoader, String url, Buffer buffer,
            int remaining);
    private static native void nLoadResources(long nativeLoader, long nativeAsset);
}