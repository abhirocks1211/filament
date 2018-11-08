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
    MTLPixelFormat colorPixelFormat = MTLPixelFormatInvalid;
    MTLPixelFormat depthPixelFormat = MTLPixelFormatInvalid;
};

struct PipelineValue {
    id<MTLRenderPipelineState> pipelineState;
};

using PipelineHashFn = utils::hash::MurmurHashFn<PipelineKey>;

struct PipelineEqual {
    bool operator()(const PipelineKey& left, const PipelineKey& right) const {
        return (
           left.vertexDescription == right.vertexDescription &&
           left.vertexFunction == right.vertexFunction &&
           left.fragmentFunction == right.fragmentFunction &&
           left.colorPixelFormat == right.colorPixelFormat &&
           left.depthPixelFormat == right.depthPixelFormat
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

    // Current state of pipeline bindings.
    Metal::PipelineKey mPipelineKey = {};

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

void MetalBinder::setColorAttachmentPixelFormat(const MTLPixelFormat pixelFormat) noexcept {
    if (pImpl->mPipelineKey.colorPixelFormat != pixelFormat) {
        pImpl->mPipelineKey.colorPixelFormat = pixelFormat;
        pImpl->mPipelineDirty = true;
    }
}

void MetalBinder::setDepthAttachmentPixelFormat(const MTLPixelFormat pixelFormat) noexcept {
    if (pImpl->mPipelineKey.depthPixelFormat != pixelFormat) {
        pImpl->mPipelineKey.depthPixelFormat = pixelFormat;
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
    MTLRenderPipelineDescriptor* descriptor = [MTLRenderPipelineDescriptor new];

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
            vertex.attributes[i].bufferIndex = VERTEX_BUFFER_START + attribute.buffer;
            vertex.attributes[i].offset = attribute.offset;
        }
    }

    for (uint32_t i = 0; i < MAX_VERTEX_ATTRIBUTES; i++) {
        if (vertexDescription.layouts[i].stride > 0) {
            const auto& layout = vertexDescription.layouts[i];
            vertex.layouts[VERTEX_BUFFER_START + i].stride = layout.stride;
            vertex.layouts[VERTEX_BUFFER_START + i].stepFunction = MTLVertexStepFunctionPerVertex;
        }
    }

    descriptor.vertexDescriptor = vertex;

    // Attachments
    descriptor.colorAttachments[0].pixelFormat = pImpl->mPipelineKey.colorPixelFormat;
    descriptor.depthAttachmentPixelFormat = pImpl->mPipelineKey.depthPixelFormat;

    NSError* error = nullptr;
    id<MTLRenderPipelineState> pipeline =
            [pImpl->mDevice newRenderPipelineStateWithDescriptor:descriptor
                                                           error:&error];
    assert(error == nullptr);

    [descriptor release];

    pImpl->mPipelines.emplace(std::make_pair(
        pImpl->mPipelineKey,
        Metal::PipelineValue { pipeline }
    ));

    pipelineState = pipeline;
    pImpl->mCurrentPipelineState = pipeline;
    pImpl->mPipelineDirty = false;
}

id<MTLDepthStencilState> DepthStateCreator::operator()(id<MTLDevice> device,
        const DepthStencilState& state) noexcept {
    MTLDepthStencilDescriptor* depthStencilDescriptor = [MTLDepthStencilDescriptor new];
    depthStencilDescriptor.depthCompareFunction = state.compareFunction;
    depthStencilDescriptor.depthWriteEnabled = state.depthWriteEnabled;
    id<MTLDepthStencilState> depthStencilState =
            [device newDepthStencilStateWithDescriptor:depthStencilDescriptor];
    [depthStencilDescriptor release];
    return depthStencilState;
}

constexpr inline MTLSamplerMinMagFilter getFilter(SamplerMinFilter filter) {
    switch (filter) {
        case SamplerMinFilter::NEAREST:
        case SamplerMinFilter::NEAREST_MIPMAP_NEAREST:
        case SamplerMinFilter::LINEAR_MIPMAP_NEAREST:
            return MTLSamplerMinMagFilterNearest;
        case SamplerMinFilter::LINEAR:
        case SamplerMinFilter::NEAREST_MIPMAP_LINEAR:
        case SamplerMinFilter::LINEAR_MIPMAP_LINEAR:
            return MTLSamplerMinMagFilterLinear;
    }
}

constexpr inline MTLSamplerMinMagFilter getFilter(SamplerMagFilter filter) noexcept {
    switch (filter) {
        case SamplerMagFilter::NEAREST:
            return MTLSamplerMinMagFilterNearest;
        case SamplerMagFilter::LINEAR:
            return MTLSamplerMinMagFilterLinear;
    }
}

constexpr inline MTLSamplerMipFilter getMipFilter(SamplerMinFilter filter) noexcept {
    switch (filter) {
        case SamplerMinFilter::NEAREST:
        case SamplerMinFilter::LINEAR:
            return MTLSamplerMipFilterNotMipmapped;
        case SamplerMinFilter::NEAREST_MIPMAP_NEAREST:
        case SamplerMinFilter::LINEAR_MIPMAP_NEAREST:
            return MTLSamplerMipFilterNearest;
        case SamplerMinFilter::NEAREST_MIPMAP_LINEAR:
        case SamplerMinFilter::LINEAR_MIPMAP_LINEAR:
            return MTLSamplerMipFilterLinear;
    }
}

constexpr inline MTLSamplerAddressMode getAddressMode(SamplerWrapMode wrapMode) noexcept {
    switch (wrapMode) {
        case SamplerWrapMode::CLAMP_TO_EDGE:
            return MTLSamplerAddressModeClampToEdge;
        case SamplerWrapMode::REPEAT:
            return MTLSamplerAddressModeRepeat;
        case SamplerWrapMode::MIRRORED_REPEAT:
            return MTLSamplerAddressModeMirrorRepeat;
    }
}

constexpr inline MTLCompareFunction getCompareFunction(SamplerCompareFunc compareFunc) noexcept {
    switch (compareFunc) {
        case SamplerCompareFunc::LE:
            return MTLCompareFunctionLessEqual;
        case SamplerCompareFunc::GE:
            return MTLCompareFunctionGreaterEqual;
        case SamplerCompareFunc::L:
            return MTLCompareFunctionLess;
        case SamplerCompareFunc::G:
            return MTLCompareFunctionGreater;
        case SamplerCompareFunc::E:
            return MTLCompareFunctionEqual;
        case SamplerCompareFunc::NE:
            return MTLCompareFunctionNotEqual;
        case SamplerCompareFunc::A:
            return MTLCompareFunctionAlways;
        case SamplerCompareFunc::N:
            return MTLCompareFunctionNever;
    }
}

id<MTLSamplerState> SamplerStateCreator::operator()(id<MTLDevice> device,
        const driver::SamplerParams& state) noexcept {
    assert(state.depthStencil == false);
    MTLSamplerDescriptor* samplerDescriptor = [[MTLSamplerDescriptor new] autorelease];
    samplerDescriptor.minFilter = getFilter(state.filterMin);
    samplerDescriptor.magFilter = getFilter(state.filterMag);
    samplerDescriptor.mipFilter = getMipFilter(state.filterMin);
    samplerDescriptor.sAddressMode = getAddressMode(state.wrapS);
    samplerDescriptor.tAddressMode = getAddressMode(state.wrapT);
    samplerDescriptor.rAddressMode = getAddressMode(state.wrapR);
    samplerDescriptor.maxAnisotropy = 1u << state.anisotropyLog2;
    samplerDescriptor.compareFunction =
            state.compareMode == SamplerCompareMode::NONE ?
                MTLCompareFunctionNever : getCompareFunction(state.compareFunc);
    return [device newSamplerStateWithDescriptor:samplerDescriptor];
}

} // namespace driver
} // namespace filament
