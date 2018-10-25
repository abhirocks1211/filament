/*
 * Copyright (C) 2018 The Android Open Source Project
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

#include "MetalBinder.h"

#include <tsl/robin_map.h>
#include <utils/Hash.h>
#include <utils/compiler.h>

namespace filament {
namespace driver {

// A hack, for now. Put all vertex data into buffer 10 so that it does not conflict with uniform
// buffers.
constexpr uint8_t VERTEX_BUFFER_BINDING = 10;

namespace Metal {

struct PipelineKey {
    id<MTLFunction> vertexFunction = nullptr;
    id<MTLFunction> fragmentFunction = nullptr;
};

struct PipelineValue {
    id<MTLRenderPipelineState> pipelineState;
};

using PipelineHashFn = utils::hash::MurmurHashFn<PipelineKey>;

struct PipelineEqual {
    bool operator()(const PipelineKey& left, const PipelineKey& right) const {
        return left.vertexFunction == right.vertexFunction &&
               left.fragmentFunction == right.fragmentFunction;
    }
};

} // namespace Metal

struct MetalBinderImpl {
    id<MTLDevice> mDevice = nullptr;

    id<MTLRenderPipelineState> mCurrentPipelineState = nullptr;

    // A cache of pipelines.
    tsl::robin_map<Metal::PipelineKey, Metal::PipelineValue,
            Metal::PipelineHashFn, Metal::PipelineEqual> mPipelines;

    // Current state of pipeline bindings.
    Metal::PipelineKey mPipelineKey;

    // If mPipelineDirty is true, then mCurrentPipelineState is invalid and need to either create a
    // new pipeline, or retrieve a valid one from the cache.
    bool mPipelineDirty = true;
};

MetalBinder::MetalBinder() : pImpl(std::make_unique<MetalBinderImpl>()) {
}

MetalBinder::~MetalBinder() = default;

void MetalBinder::setDevice(id<MTLDevice> device) {
    pImpl->mDevice = device;
}

void MetalBinder::setShaderFunctions(id<MTLFunction> vertexFunction,
        id<MTLFunction> fragmentFunction) noexcept {
    if (pImpl->mPipelineKey.vertexFunction != vertexFunction ||
            pImpl->mPipelineKey.fragmentFunction != fragmentFunction) {
        pImpl->mPipelineKey.vertexFunction = vertexFunction;
        pImpl->mPipelineKey.fragmentFunction = fragmentFunction;
        pImpl->mPipelineDirty = true;
    }
}

void MetalBinder::getOrCreatePipelineState(
        id<MTLRenderPipelineState> &pipelineState) noexcept {
    assert(pImpl->mDevice != nullptr);

    if (!pImpl->mPipelineDirty && pImpl->mCurrentPipelineState != nullptr) {
        pipelineState = pImpl->mCurrentPipelineState;
        return;
    }

    // The pipeline is dirty, so check if a valid one exists in the cache.
    auto iter = pImpl->mPipelines.find(pImpl->mPipelineKey);
    if (UTILS_LIKELY(iter != pImpl->mPipelines.end())) {
        auto foundPipelineState = iter.value().pipelineState;
        pImpl->mCurrentPipelineState = foundPipelineState;
        pipelineState = foundPipelineState;
        return;
    }

    // Create a new pipeline and store it in the cache.
    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];

    // Shader Functions
    descriptor.vertexFunction = pImpl->mPipelineKey.vertexFunction;
    descriptor.fragmentFunction = pImpl->mPipelineKey.fragmentFunction;

    // Vertex attributes
    MTLVertexDescriptor* vertex = [MTLVertexDescriptor vertexDescriptor];
    vertex.attributes[0].format = MTLVertexFormatFloat2;
    vertex.attributes[0].bufferIndex = VERTEX_BUFFER_BINDING;
    vertex.attributes[0].offset = 0;

    vertex.attributes[2].format = MTLVertexFormatUChar4Normalized;
    vertex.attributes[2].bufferIndex = VERTEX_BUFFER_BINDING;
    vertex.attributes[2].offset = sizeof(float) * 2;

    vertex.layouts[VERTEX_BUFFER_BINDING].stride = sizeof(float) * 2 + sizeof(int32_t);
    vertex.layouts[VERTEX_BUFFER_BINDING].stepFunction = MTLVertexStepFunctionPerVertex;

    descriptor.vertexDescriptor = vertex;

    // Attachments
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    NSError* error = nullptr;
    id<MTLRenderPipelineState> pipeline =
            [pImpl->mDevice newRenderPipelineStateWithDescriptor:descriptor
                                                           error:&error];
    assert(error == nullptr);

    pImpl->mPipelines.emplace(std::make_pair(
        pImpl->mPipelineKey,
        Metal::PipelineValue { pipeline }
    ));

    pipelineState = pipeline;
    pImpl->mCurrentPipelineState = pipeline;
    pImpl->mPipelineDirty = false;
}

} // namespace driver
} // namespace filament
