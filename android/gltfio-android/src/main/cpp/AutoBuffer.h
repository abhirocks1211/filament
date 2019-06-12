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

#ifndef GLTFIO_AUTOBUFFER_H
#define GLTFIO_AUTOBUFFER_H

#include <jni.h>

struct AutoBufferUtils {
    AutoBufferUtils(JNIEnv* env) {
        jniClass = env->FindClass("com/google/android/filament/NioUtils");
        jniClass = (jclass) env->NewGlobalRef(jniClass);
        getBasePointer = env->GetStaticMethodID(jniClass, "getBasePointer",
                "(Ljava/nio/Buffer;JI)J");
    }
    jclass jniClass;
    jmethodID getBasePointer;
};

struct AutoBuffer {
    AutoBuffer(JNIEnv* env, jobject javaBuffer, jint remaining) :
            env(env), buffer(env->NewGlobalRef(javaBuffer)), size(remaining) {
        static AutoBufferUtils utils(env);
        jlong address = (jlong) env->GetDirectBufferAddress(buffer);
        data = reinterpret_cast<uint8_t *>(env->CallStaticLongMethod(utils.jniClass,
                    utils.getBasePointer, buffer, address, 0));

    }
    ~AutoBuffer() {
        env->DeleteGlobalRef(buffer);
    }

    // utility function for BufferDescriptor callbacks
    static void destroy(void* data, size_t size, void *userData) {
        AutoBuffer* buffer = (AutoBuffer*) userData;
        delete buffer;
    }

    JNIEnv* env;
    jobject buffer;
    size_t size;
    uint8_t const* data;
};


#endif // GLTFIO_AUTOBUFFER_H
