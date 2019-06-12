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

import com.google.android.filament.Entity;

public class FilamentAsset {
    private long mNativeObject;

    FilamentAsset(long nativeObject) {
        mNativeObject = nativeObject;
    }

    @Entity int getRoot() {
        return nGetRoot(mNativeObject);
    }

    @Entity int[] getEntities() {
        int[] result = new int[nGetEntityCount(mNativeObject)];
        nGetEntities(mNativeObject, result);
        return result;
    }

    long getNativeObject() {
        return mNativeObject;
    }

    public void clearNativeObject() {
        mNativeObject = 0;
    }

    private static native int nGetRoot(long nativeAsset);
    private static native int nGetEntityCount(long nativeAsset);
    private static native void nGetEntities(long nativeAsset, int[] result);
}
