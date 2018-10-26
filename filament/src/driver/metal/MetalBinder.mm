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

namespace Metal {

struct PipelineKey {
    MetalBinder::VertexDescription vertexDescription;
    id<MTLFunction> vertexFunction = nullptr;
    id<MTLFunction> fragmentFunction = nullptr;
};

struct PipelineValue {
    id<MTLRenderPipelineState> pipelineState;
};

using PipelineHashFn = utils::hash::MurmurHashFn<PipelineKey>;
using DepthStencilStateHash = utils::hash::MurmurHashFn<MetalBinder::DepthStencilState>;

struct PipelineEqual {
    bool operator()(const PipelineKey& left, const PipelineKey& right) const {
        return (
           left.vertexDescription == right.vertexDescription &&
           left.vertexFunction == right.vertexFunction &&
           left.fragmentFunction == right.fragmentFunction
        );
    }
};

} // namespace Metal

struct MetalBinderImpl {
    id<MTLDevice> mDevice = nullptr;

    id<MTLRenderPipelineState> mCurrentPipelineState = nullptr;

    // A cache of pipelines.
    tsl::robin_map<Metal::PipelineKey, Metal::PipelineValue,
            Metal::PipelineHashFn, Metal::PipelineEqual> mPipelines;

    // A cache of depth-stencil states.
    tsl::robin_map<MetalBinder::DepthStencilState, id<MTLDepthStencilState>,
            Metal::DepthStencilStateHash> mDepthStencilStates;

    // Current state of pipeline bindings.
    Metal::PipelineKey mPipelineKey = {};

    // Current depth-stencil state.
    MetalBinder::DepthStencilState mDepthStencilStateKey = {};
    bool mDepthStencilStateDirty = true;

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

void MetalBinder::setVertexDescription(const VertexDescription& vertexDescription) noexcept {
    if (pImpl->mPipelineKey.vertexDescription != vertexDescription) {
        pImpl->mPipelineKey.vertexDescription = vertexDescription;
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

    const auto& vertexDescription = pImpl->mPipelineKey.vertexDescription;

    for (uint32_t i = 0; i < MAX_VERTEX_ATTRIBUTES; i++) {
        if (vertexDescription.attributes[i].format > MTLVertexFormatInvalid) {
            const auto& attribute = vertexDescription.attributes[i];
            vertex.attributes[i].format = attribute.format;
            vertex.attributes[i].bufferIndex = attribute.buffer;
            vertex.attributes[i].offset = attribute.offset;
        }
    }

    for (uint32_t i = 0; i < MAX_BUFFERS; i++) {
        if (vertexDescription.layouts[i].stride > 0) {
            const auto& layout = vertexDescription.layouts[i];
            // todo
            vertex.layouts[10].stride = layout.stride;
            vertex.layouts[10].stepFunction = MTLVertexStepFunctionPerVertex;
        }
    }

    descriptor.vertexDescriptor = vertex;

    // Attachments
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

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

void MetalBinder::makeDepthStencilStateDirty() noexcept {
    pImpl->mDepthStencilStateDirty = true;
}

void MetalBinder::bindDepthStencilState(const DepthStencilState& depthStencilState) noexcept {
    if (pImpl->mDepthStencilStateKey != depthStencilState) {
        pImpl->mDepthStencilStateKey = depthStencilState;
        pImpl->mDepthStencilStateDirty = true;
    }
}

bool MetalBinder::getOrCreateDepthStencilState(id<MTLDepthStencilState>& depthStencilState)
        noexcept {
    if (!pImpl->mDepthStencilStateDirty) {
        // The state has not changed, no re-binding is necessary.
        return false;
    }

    // The depth-stencil state is dirty, so check if a valid one exists in the cache.
    auto iter = pImpl->mDepthStencilStates.find(pImpl->mDepthStencilStateKey);
    if (UTILS_LIKELY(iter != pImpl->mDepthStencilStates.end())) {
        auto foundDepthStencilState = iter.value();
        // pImpl->mCurrentPipelineState = foundPipelineState;
        depthStencilState = foundDepthStencilState;
        return true;
    }

    // If we reach this point, the state is dirty and we couldn't find one in the cache, so create
    // a new one.

    MTLDepthStencilDescriptor* depthStencilDescriptor = [MTLDepthStencilDescriptor new];
    depthStencilDescriptor.depthCompareFunction = pImpl->mDepthStencilStateKey.compareFunction;
    depthStencilDescriptor.depthWriteEnabled = pImpl->mDepthStencilStateKey.depthWriteEnabled;
    id<MTLDepthStencilState> newDepthStencilState =
            [pImpl->mDevice newDepthStencilStateWithDescriptor:depthStencilDescriptor];

    pImpl->mDepthStencilStates.emplace(std::make_pair(
        pImpl->mDepthStencilStateKey,
        newDepthStencilState
    ));

    depthStencilState = newDepthStencilState;
    pImpl->mDepthStencilStateDirty = false;

    return true;
}

} // namespace driver
} // namespace filament
