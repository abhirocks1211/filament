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

#ifndef TNT_FILAMENT_DRIVER_METALHANDLES_H
#define TNT_FILAMENT_DRIVER_METALHANDLES_H

#include "driver/metal/MetalDriver.h"

#include <Metal/Metal.h>
#include <QuartzCore/QuartzCore.h> // for CAMetalLayer

#include "MetalBinder.h" // for MetalBinder::VertexDescription
#include "MetalEnums.h"

#include <utils/Panic.h>

#include <vector>

namespace filament {
namespace driver {

struct MetalSwapChain : public HwSwapChain {
    CAMetalLayer* layer = nullptr;
};

struct MetalVertexBuffer : public HwVertexBuffer {
    MetalVertexBuffer(id<MTLDevice> device, uint8_t bufferCount, uint8_t attributeCount,
                      uint32_t vertexCount, Driver::AttributeArray const& attributes)
            : HwVertexBuffer(bufferCount, attributeCount, vertexCount, attributes) {

        buffers.reserve(bufferCount);

        for (uint8_t bufferIndex = 0; bufferIndex < bufferCount; ++bufferIndex) {
            // Calculate buffer size.
            uint32_t size = 0;
            for (auto const& item : attributes) {
                if (item.buffer == bufferIndex) {
                    uint32_t end = item.offset + vertexCount * item.stride;
                    size = std::max(size, end);
                }
            }

            id<MTLBuffer> buffer = [device newBufferWithLength:size
            options:MTLResourceStorageModeShared];
            buffers.push_back(buffer);
        }
    }

    std::vector<id<MTLBuffer>> buffers;
};

struct MetalIndexBuffer : public HwIndexBuffer {
    MetalIndexBuffer(id<MTLDevice> device, uint8_t elementSize, uint32_t indexCount)
            : HwIndexBuffer(elementSize, indexCount) {
        buffer = [device newBufferWithLength:(elementSize * indexCount)
        options:MTLResourceStorageModeShared];
    }

    id<MTLBuffer> buffer;
};

struct MetalUniformBuffer : public HwUniformBuffer {
    MetalUniformBuffer(id<MTLDevice> device, size_t size) : HwUniformBuffer() {
        buffer = [device newBufferWithLength:size
        options:MTLResourceStorageModeShared];
    }

    size_t offset = 0;
    id<MTLBuffer> buffer;
};

struct MetalRenderPrimitive : public HwRenderPrimitive {
    MetalVertexBuffer* vertexBuffer = nullptr;
    MetalIndexBuffer* indexBuffer = nullptr;

    // This struct is used to create the pipeline description to describe vertex assembly.
    MetalBinder::VertexDescription vertexDescription = {};

    std::vector<id<MTLBuffer>> buffers;
    std::vector<NSUInteger> offsets;

    void setBuffers(MetalVertexBuffer* vertexBuffer, MetalIndexBuffer* indexBuffer,
                    uint32_t enabledAttributes) {
        this->vertexBuffer = vertexBuffer;
        this->indexBuffer = indexBuffer;

        const size_t attributeCount = vertexBuffer->attributes.size();

        buffers.clear();
        buffers.reserve(attributeCount);
        offsets.clear();
        offsets.reserve(attributeCount);

        // Each attribute gets its own vertex buffer.

        uint32_t bufferIndex = 0;
        for (uint32_t attributeIndex = 0; attributeIndex < attributeCount; attributeIndex++) {
            if (!(enabledAttributes & (1U << attributeIndex))) {
                continue;
            }
            const auto& attribute = vertexBuffer->attributes[attributeIndex];

            buffers.push_back(vertexBuffer->buffers[attribute.buffer]);
            offsets.push_back(attribute.offset);

            vertexDescription.attributes[attributeIndex] = {
                    .format = getMetalFormat(attribute.type,
                                             attribute.flags & Driver::Attribute::FLAG_NORMALIZED),
                    .buffer = bufferIndex,
                    .offset = 0
            };
            vertexDescription.layouts[bufferIndex] = {
                    .stride = attribute.stride
            };

            bufferIndex++;
        };
    }
};

struct MetalProgram : public HwProgram {
    explicit MetalProgram(id<MTLDevice> device, const Program& program) noexcept
            : HwProgram(program.getName()) {
        using MetalFunctionPtr = id<MTLFunction>*;

        MetalFunctionPtr shaderFunctions[2] = { &vertexFunction, &fragmentFunction };

        const auto& sources = program.getShadersSource();
        for (size_t i = 0; i < Program::NUM_SHADER_TYPES; i++) {
            const auto& source = sources[i];
            // It's okay for some shaders to be empty, they shouldn't be used in any draw calls.
            if (source.empty()) {
                continue;
            }
            NSString* objcSource = [NSString stringWithCString:source.c_str()
            encoding:NSUTF8StringEncoding];
            NSError* error = nil;
            id<MTLLibrary> library = [device newLibraryWithSource:objcSource
            options:nil
            error:&error];
            if (error) {
                auto description =
                [error.localizedDescription cStringUsingEncoding:NSUTF8StringEncoding];
                utils::slog.w << description << utils::io::endl;
            }
            ASSERT_POSTCONDITION(library != nil, "Unable to compile Metal shading library.");

            *shaderFunctions[i] = [library newFunctionWithName:@"main0"];
        }

        samplerBindings = *program.getSamplerBindings();
    }

    id<MTLFunction> vertexFunction;
    id<MTLFunction> fragmentFunction;
    SamplerBindingMap samplerBindings;
};

struct MetalTexture : public HwTexture {

    MetalTexture(id<MTLDevice> device, driver::SamplerType target, uint8_t levels,
            TextureFormat format, uint8_t samples, uint32_t width, uint32_t height, uint32_t depth,
            TextureUsage usage)
    noexcept;

    void load2DImage(uint32_t level, uint32_t xoffset, uint32_t yoffset, uint32_t width,
            uint32_t height, Driver::PixelBufferDescriptor& data) noexcept;
    void loadCubeImage(const PixelBufferDescriptor& data, const FaceOffsets& faceOffsets,
            int miplevel);

    id<MTLTexture> texture;
    uint8_t bytesPerPixel;

};

struct MetalSamplerBuffer : public HwSamplerBuffer {

    MetalSamplerBuffer(size_t size) : HwSamplerBuffer(size) {}

};

} // namespace driver
} // namespace filament

#endif //TNT_FILAMENT_DRIVER_METALHANDLES_H
