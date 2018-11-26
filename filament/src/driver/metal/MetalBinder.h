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

#ifndef TNT_METALBINDER_H
#define TNT_METALBINDER_H

#include <Metal/Metal.h>

#include "driver/Driver.h"

#include <filament/EngineEnums.h>

#include <memory>
#include <tsl/robin_map.h>
#include <utils/Hash.h>

namespace filament {
namespace driver {

inline bool operator==(const driver::SamplerParams& lhs, const driver::SamplerParams& rhs) {
    return lhs.u == rhs.u;
}

namespace metal {

static constexpr uint32_t VERTEX_BUFFER_START = BindingPoints::COUNT;
static constexpr uint32_t MAX_VERTEX_ATTRIBUTES = filament::ATTRIBUTE_INDEX_COUNT;
static constexpr uint32_t NUM_UBUFFER_BINDINGS = filament::BindingPoints::COUNT;
static constexpr uint32_t SAMPLER_BINDINGS_START = NUM_UBUFFER_BINDINGS;
static constexpr uint32_t NUM_SAMPLER_BINDINGS = filament::MAX_SAMPLER_COUNT;

struct MetalBinderImpl;

// Forward declarations necessary here, definitions at end of file.
inline bool operator==(const MTLViewport& lhs, const MTLViewport& rhs);
inline bool operator!=(const MTLViewport& lhs, const MTLViewport& rhs);

struct VertexDescription {
    struct Attribute {
        MTLVertexFormat format;
        uint32_t buffer;
        uint32_t offset;
    };
    struct Layout {
        uint32_t stride;
    };
    Attribute attributes[MAX_VERTEX_ATTRIBUTES];
    Layout layouts[MAX_VERTEX_ATTRIBUTES];

    bool operator==(const VertexDescription& rhs) const noexcept {
        bool result = true;
        for (uint32_t i = 0; i < MAX_VERTEX_ATTRIBUTES; i++) {
            result &= (
                    this->attributes[i].format == rhs.attributes[i].format &&
                    this->attributes[i].buffer == rhs.attributes[i].buffer &&
                    this->attributes[i].offset == rhs.attributes[i].offset
            );
        }
        for (uint32_t i = 0; i < MAX_VERTEX_ATTRIBUTES; i++) {
            result &= this->layouts[i].stride == rhs.layouts[i].stride;
        }
        return result;
    }

    bool operator!=(const VertexDescription& rhs) const noexcept {
        return !operator==(rhs);
    }
};

struct BlendState {
    bool blendingEnabled;
    MTLBlendOperation alphaBlendOperation;
    MTLBlendOperation rgbBlendOperation;
    MTLBlendFactor destinationAlphaBlendFactor;
    MTLBlendFactor destinationRGBBlendFactor;
    MTLBlendFactor sourceAlphaBlendFactor;
    MTLBlendFactor sourceRGBBlendFactor;

    bool operator==(const BlendState& rhs) const noexcept {
        return (
                this->blendingEnabled == rhs.blendingEnabled &&
                this->alphaBlendOperation == rhs.alphaBlendOperation &&
                this->rgbBlendOperation == rhs.rgbBlendOperation &&
                this->destinationAlphaBlendFactor == rhs.destinationAlphaBlendFactor &&
                this->destinationRGBBlendFactor == rhs.destinationRGBBlendFactor &&
                this->sourceAlphaBlendFactor == rhs.sourceAlphaBlendFactor &&
                this->sourceRGBBlendFactor == rhs.sourceRGBBlendFactor
        );
    }

    bool operator!=(const BlendState& rhs) const noexcept {
        return !operator==(rhs);
    }
};

template<typename StateType,
         typename MetalType,
         typename StateCreator>
class StateCache {

public:

    void setDevice(id<MTLDevice> device) { mDevice = device; }

    MetalType getOrCreateState(const StateType& state) noexcept {
        // Check if a valid state already exists in the cache.
        auto iter = mStateCache.find(state);
        if (UTILS_LIKELY(iter != mStateCache.end())) {
            auto foundState = iter.value();
            return foundState;
        }

        // If we reach this point, we couldn't find one in the cache; create a new one.
        const auto& metalObject = creator(mDevice, state);

        mStateCache.emplace(std::make_pair(
            state,
            metalObject
        ));

        return metalObject;
    }

private:

    StateCreator creator;
    id<MTLDevice> mDevice = nil;

    using HashFn = utils::hash::MurmurHashFn<StateType>;
    tsl::robin_map<StateType, MetalType, HashFn> mStateCache;

};

template<typename StateType>
class StateTracker {

public:

    void invalidate() noexcept { mStateDirty = true; }

    void updateState(const StateType& newState) noexcept {
        if (mCurrentState != newState) {
            mCurrentState = newState;
            mStateDirty = true;
        }
    }

    // Returns true if the state has changed since the last call to stateChanged.
    bool stateChanged() noexcept {
        bool ret = mStateDirty;
        mStateDirty = false;
        return ret;
    }

    const StateType& getState() const {
        return mCurrentState;
    }

private:

    bool mStateDirty = true;
    StateType mCurrentState = {};

};

// Pipeline state

struct PipelineState {
    id<MTLFunction> vertexFunction;
    id<MTLFunction> fragmentFunction;
    VertexDescription vertexDescription;
    MTLPixelFormat colorAttachmentPixelFormat;
    MTLPixelFormat depthAttachmentPixelFormat;
    BlendState blendState;

    bool operator==(const PipelineState& rhs) const noexcept {
        return (
                this->vertexFunction == rhs.vertexFunction &&
                this->fragmentFunction == rhs.fragmentFunction &&
                this->vertexDescription == rhs.vertexDescription &&
                this->colorAttachmentPixelFormat == rhs.colorAttachmentPixelFormat &&
                this->depthAttachmentPixelFormat == rhs.depthAttachmentPixelFormat &&
                this->blendState == rhs.blendState
        );
    }

    bool operator!=(const PipelineState& rhs) const noexcept {
        return !operator==(rhs);
    }
};

struct PipelineStateCreator {
    id<MTLRenderPipelineState> operator()(id<MTLDevice> device, const PipelineState& state)
            noexcept;
};

using PipelineStateTracker = StateTracker<PipelineState>;

using PipelineStateCache = StateCache<PipelineState, id<MTLRenderPipelineState>,
        PipelineStateCreator>;

// Depth-stencil State

struct DepthStencilState {
    MTLCompareFunction compareFunction;
    bool depthWriteEnabled;

    bool operator==(const DepthStencilState& rhs) const noexcept {
        return this->compareFunction == rhs.compareFunction &&
               this->depthWriteEnabled == rhs.depthWriteEnabled;
    }

    bool operator!=(const DepthStencilState& rhs) const noexcept {
        return !operator==(rhs);
    }
};

struct DepthStateCreator {
    id<MTLDepthStencilState> operator()(id<MTLDevice> device, const DepthStencilState& state)
            noexcept;
};

using DepthStencilStateTracker = StateTracker<DepthStencilState>;

using DepthStencilStateCache = StateCache<DepthStencilState, id<MTLDepthStencilState>,
        DepthStateCreator>;

// Uniform buffers

struct UniformBufferState {
    bool bound = false;
    Driver::UniformBufferHandle ubh;
    uint64_t offset = 0;

    bool operator==(const UniformBufferState& rhs) const noexcept {
        return this->bound == rhs.bound &&
               this->ubh.getId() == rhs.ubh.getId() &&
               this->offset == rhs.offset;
    }

    bool operator!=(const UniformBufferState& rhs) const noexcept {
        return !operator==(rhs);
    }
};

using UniformBufferStateTracker = StateTracker<UniformBufferState>;

// Sampler states

struct SamplerStateCreator {
    id<MTLSamplerState> operator()(id<MTLDevice> device, const driver::SamplerParams& state)
            noexcept;
};

using SamplerStateCache = StateCache<driver::SamplerParams, id<MTLSamplerState>,
        SamplerStateCreator>;

// Raster-related states

using CullModeStateTracker = StateTracker<MTLCullMode>;
using WindingStateTracker = StateTracker<MTLWinding>;
using ViewportStateTracker = StateTracker<MTLViewport>;

inline bool operator==(const MTLViewport& lhs, const MTLViewport& rhs) {
    return (
            lhs.width == rhs.width &&
            lhs.height == rhs.height &&
            lhs.originX == rhs.originX &&
            lhs.originY == rhs.originY &&
            lhs.zfar == rhs.zfar &&
            lhs.znear == rhs.znear
    );
}

inline bool operator!=(const MTLViewport& lhs, const MTLViewport& rhs) {
    return !operator==(lhs, rhs);
}

} // namespace metal
} // namespace driver
} // namespace filament


#endif //TNT_METALBINDER_H
