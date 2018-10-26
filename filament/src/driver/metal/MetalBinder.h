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

#include <filament/EngineEnums.h>

#include <memory>

namespace filament {
namespace driver {

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

} // namespace driver
} // namespace filament


#endif //TNT_METALBINDER_H
