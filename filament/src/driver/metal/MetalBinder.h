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

static constexpr uint32_t MAX_UNIFORMS = BindingPoints::COUNT;

struct MetalBinderImpl;

class MetalBinder {

public:
    static constexpr uint32_t MAX_VERTEX_ATTRIBUTES = filament::ATTRIBUTE_INDEX_COUNT;

    // Metal indexes vertex buffers and uniform buffers in the same number namespace.
    static constexpr uint32_t MAX_BUFFERS = BindingPoints::COUNT + MAX_ATTRIBUTE_BUFFERS_COUNT;

    MetalBinder();
    ~MetalBinder();

    void setDevice(id<MTLDevice> device);

    // Pipeline State

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
        // todo: we don't need that many layouts, only Vertex buffers need layouts.
        Layout layouts[MAX_BUFFERS];

        bool operator==(const VertexDescription& rhs) const noexcept {
            bool result = true;
            for (uint32_t i = 0; i < MAX_VERTEX_ATTRIBUTES; i++) {
                result &= (
                   this->attributes[i].format == rhs.attributes[i].format &&
                   this->attributes[i].buffer == rhs.attributes[i].buffer &&
                   this->attributes[i].offset == rhs.attributes[i].offset
                );
            }
            for (uint32_t i = 0; i < MAX_BUFFERS; i++) {
                result &= this->layouts[i].stride == rhs.layouts[i].stride;
            }
            return result;
        }

        bool operator!=(const VertexDescription& rhs) const noexcept {
            return !operator==(rhs);
        }
    };

    void setShaderFunctions(id<MTLFunction> vertexFunction,
            id<MTLFunction> fragmentFunction) noexcept;
    void setVertexDescription(const VertexDescription& vertexDescription) noexcept;
    void getOrCreatePipelineState(id<MTLRenderPipelineState>& pipelineState) noexcept;

private:

    std::unique_ptr<MetalBinderImpl> pImpl;

};

template<typename StateType, typename MetalType>
class StateCache {

public:

    using StateCreationFn = std::function<MetalType(id<MTLDevice>, const StateType&)>;

    void setDevice(id<MTLDevice> device) { mDevice = device; }
    void setCreationFunction(StateCreationFn creationFn) { mCreationFn = creationFn; }

    MetalType getOrCreateState(const StateType& state) noexcept {
        // Check if a valid state already exists in the cache.
        auto iter = mStateCache.find(state);
        if (UTILS_LIKELY(iter != mStateCache.end())) {
            auto foundState = iter.value();
            return foundState;
        }

        // If we reach this point, we couldn't find one in the cache; create a new one.
        const auto& metalObject = mCreationFn(mDevice, state);

        mStateCache.emplace(std::make_pair(
            state,
            metalObject
        ));

        return metalObject;
    }

private:

    id<MTLDevice> mDevice = nil;

    StateCreationFn mCreationFn;

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

id<MTLDepthStencilState> createDepthStencilState(id<MTLDevice> device,
        const DepthStencilState& state);

using DepthStencilStateTracker = StateTracker<DepthStencilState>;

using DepthStencilStateCache = StateCache<DepthStencilState, id<MTLDepthStencilState>>;

// Uniform buffers

struct UniformBufferState {
    bool bound;
    Driver::UniformBufferHandle ubh;
    uint64_t offset;

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


} // namespace driver
} // namespace filament


#endif //TNT_METALBINDER_H
