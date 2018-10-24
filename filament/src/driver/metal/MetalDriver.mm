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

#include "driver/metal/MetalDriver.h"
#include "driver/CommandStream.h"

#include <AppKit/AppKit.h>
#include <Metal/Metal.h>
#include <QuartzCore/QuartzCore.h>

#include <utils/Log.h>
#include <utils/Panic.h>

#include <unordered_map>

#include <fstream>

namespace filament {

struct MetalDriverImpl {
    id<MTLDevice> mDevice;
    id<MTLCommandQueue> mCommandQueue;

    // Single use, re-created each frame.
    id<MTLCommandBuffer> mCurrentCommandBuffer;
    id<MTLRenderCommandEncoder> mCurrentCommandEncoder = nullptr;

    id<CAMetalDrawable> mCurrentDrawable = nullptr;

    id<MTLRenderPipelineState> mPipelineState;

    std::unordered_map<size_t, Driver::UniformBufferHandle> mBoundUniforms;
};

// A hack, for now. Put all vertex data into buffer 10 so that it does not conflict with uniform
// buffers.
constexpr uint8_t VERTEX_BUFFER_BINDING = 10;

// todo: move into Headers file

struct MetalSwapChain : public HwSwapChain {
    CAMetalLayer* layer = nullptr;
};

struct MetalVertexBuffer : public HwVertexBuffer {
    MetalVertexBuffer(id<MTLDevice> device, uint8_t bufferCount, uint8_t attributeCount,
            uint32_t vertexCount, Driver::AttributeArray const& attributes)
            : HwVertexBuffer(bufferCount, attributeCount, vertexCount, attributes) {
        // todo: handle more than 1 buffer

        // Calculate buffer size.
        uint8_t bufferIndex = 0;
        uint32_t size = 0;
        for (auto const& item : attributes) {
            if (item.buffer == bufferIndex) {
                uint32_t end = item.offset + vertexCount * item.stride;
                size = std::max(size, end);
            }
        }

        buffer = [device newBufferWithLength:size
                                     options:MTLResourceStorageModeShared];
        bufferSize = size;
    }

    id<MTLBuffer> buffer;
    uint32_t bufferSize;
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
    MetalUniformBuffer(id<MTLDevice> device, size_t size) : HwUniformBuffer(size) {
        buffer = [device newBufferWithLength:size
                                      options:MTLResourceStorageModeShared];
    }

    id<MTLBuffer> buffer;
};

struct MetalRenderPrimitive : public HwRenderPrimitive {
    MetalVertexBuffer* vertexBuffer = nullptr;
    MetalIndexBuffer* indexBuffer = nullptr;
};

//

Driver* MetalDriver::create(driver::MetalPlatform* const platform) {
    assert(platform);
    return new MetalDriver(platform);
}

MetalDriver::MetalDriver(driver::MetalPlatform* platform) noexcept
        : DriverBase(new ConcreteDispatcher<MetalDriver>(this)),
        mPlatform(*platform),
        pImpl(new MetalDriverImpl) {

    pImpl->mDevice = MTLCreateSystemDefaultDevice();
    pImpl->mCommandQueue = [pImpl->mDevice newCommandQueue];

    id<MTLLibrary> vertexLibrary;
    id<MTLLibrary> fragmentLibrary;
    {
        NSError* error = nullptr;
        NSString* content = [NSString stringWithContentsOfFile:@"/Users/bendoherty/code/filament-gh/shaderoutput/bakedColor.vert.metal"];
        vertexLibrary = [pImpl->mDevice newLibraryWithSource:content
                                                     options:nil
                                                       error:&error];
        if (error) {
            utils::slog.w << [error.userInfo[@"NSLocalizedDescription"] cStringUsingEncoding:NSUTF8StringEncoding] << utils::io::endl;
        }
        assert(error == nullptr);
    }
    {
        NSError *error = nullptr;
        NSString* content = [NSString stringWithContentsOfFile:@"/Users/bendoherty/code/filament-gh/shaderoutput/bakedColor.frag.metal"];
        fragmentLibrary = [pImpl->mDevice newLibraryWithSource:content
                                                       options:nil
                                                         error:&error];
        if (error) {
            utils::slog.w << [error.userInfo[@"NSLocalizedDescription"] cStringUsingEncoding:NSUTF8StringEncoding] << utils::io::endl;
        }
        assert(error == nullptr);
    }

    MTLRenderPipelineDescriptor* pipeline = [[MTLRenderPipelineDescriptor alloc] init];
    pipeline.label = @"Simple pipeline";

    // Vertex program
    pipeline.vertexFunction = [vertexLibrary newFunctionWithName:@"main0"];
    MTLVertexDescriptor* vertex = [MTLVertexDescriptor vertexDescriptor];
    vertex.attributes[0].format = MTLVertexFormatFloat2;
    vertex.attributes[0].bufferIndex = VERTEX_BUFFER_BINDING;
    vertex.attributes[0].offset = 0;

    vertex.attributes[2].format = MTLVertexFormatUChar4Normalized;
    vertex.attributes[2].bufferIndex = VERTEX_BUFFER_BINDING;
    vertex.attributes[2].offset = sizeof(float) * 2;

    vertex.layouts[VERTEX_BUFFER_BINDING].stride = sizeof(float) * 2 + sizeof(int32_t);
    vertex.layouts[VERTEX_BUFFER_BINDING].stepFunction = MTLVertexStepFunctionPerVertex;

    pipeline.vertexDescriptor = vertex;

    pipeline.fragmentFunction = [fragmentLibrary newFunctionWithName:@"main0"];
    pipeline.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    NSError* error = nullptr;
    pImpl->mPipelineState = [pImpl->mDevice newRenderPipelineStateWithDescriptor:pipeline
                                                                           error:&error];
    assert(error == nullptr);
}

MetalDriver::~MetalDriver() noexcept {
    delete pImpl;
}

void MetalDriver::debugCommand(const char *methodName) {
    utils::slog.d << methodName << utils::io::endl;
}

void MetalDriver::beginFrame(int64_t monotonic_clock_ns, uint32_t frameId) {
    pImpl->mCurrentCommandBuffer = [pImpl->mCommandQueue commandBuffer];
}

void MetalDriver::setPresentationTime(int64_t monotonic_clock_ns) {

}

void MetalDriver::endFrame(uint32_t frameId) {

}

void MetalDriver::flush(int dummy) {

}

void MetalDriver::createVertexBuffer(Driver::VertexBufferHandle vbh, uint8_t bufferCount,
        uint8_t attributeCount, uint32_t vertexCount, Driver::AttributeArray attributes,
        Driver::BufferUsage usage) {
    // todo: make use of usage
    construct_handle<MetalVertexBuffer>(mHandleMap, vbh, pImpl->mDevice, bufferCount,
            attributeCount, vertexCount, attributes);
}

void MetalDriver::createIndexBuffer(Driver::IndexBufferHandle ibh, Driver::ElementType elementType,
        uint32_t indexCount, Driver::BufferUsage usage) {
    auto elementSize = (uint8_t) getElementTypeSize(elementType);
    construct_handle<MetalIndexBuffer>(mHandleMap, ibh, pImpl->mDevice, elementSize, indexCount);
}

void MetalDriver::createTexture(Driver::TextureHandle, Driver::SamplerType target, uint8_t levels,
        Driver::TextureFormat format, uint8_t samples, uint32_t width, uint32_t height,
        uint32_t depth, Driver::TextureUsage usage) {

}

void MetalDriver::createSamplerBuffer(Driver::SamplerBufferHandle, size_t size) {

}

void MetalDriver::createUniformBuffer(Driver::UniformBufferHandle ubh, size_t size,
        Driver::BufferUsage usage) {
    construct_handle<MetalUniformBuffer>(mHandleMap, ubh, pImpl->mDevice, size);
}

void MetalDriver::createRenderPrimitive(Driver::RenderPrimitiveHandle rph, int dummy) {
    construct_handle<MetalRenderPrimitive>(mHandleMap, rph);
}

void MetalDriver::createProgram(Driver::ProgramHandle, Program&& program) {
    const auto& shadersSource = program.getShadersSource();

    using Shader = Program::Shader;

    for (size_t i = 0; i < Program::NUM_SHADER_TYPES; i++) {
        const char* shaderType;
        Shader type = (Shader)i;
        switch (type) {
            case Shader::VERTEX:
                shaderType = "vertex";
                break;
            case Shader::FRAGMENT:
                shaderType = "fragment";
                break;
        }

        if (shadersSource[i].length()) {
            char outputName[1000];
            sprintf(outputName, "/Users/bendoherty/code/filament-gh/shaderoutput/%s_%s.txt",
                    program.getName().c_str(), shaderType);

            std::ofstream file;
            file.open(outputName, std::ios_base::binary);
            assert(file.is_open());

            file.write(shadersSource[i].c_str(), shadersSource[i].size());
            file.close();
        }
    }
}

void MetalDriver::createDefaultRenderTarget(Driver::RenderTargetHandle, int dummy) {

}

void MetalDriver::createRenderTarget(Driver::RenderTargetHandle,
        Driver::TargetBufferFlags targetBufferFlags, uint32_t width, uint32_t height,
        uint8_t samples, Driver::TextureFormat format, Driver::TargetBufferInfo color,
        Driver::TargetBufferInfo depth, Driver::TargetBufferInfo stencil) {

}

void MetalDriver::createFence(Driver::FenceHandle, int dummy) {

}

void MetalDriver::createSwapChain(Driver::SwapChainHandle sch, void* nativeWindow, uint64_t flags) {
    auto* swapChain = construct_handle<MetalSwapChain>(mHandleMap, sch);

    // Obtain the CAMetalLayer-backed view.
    // todo: move this into Platform.
    NSView* nsview = (NSView*) nativeWindow;
    nsview = [nsview viewWithTag:255];
    swapChain->layer = (CAMetalLayer*) nsview.layer;
}

void MetalDriver::createStreamFromTextureId(Driver::StreamHandle, intptr_t externalTextureId,
        uint32_t width, uint32_t height) {

}

Driver::VertexBufferHandle MetalDriver::createVertexBufferSynchronous() noexcept {
    return alloc_handle<MetalVertexBuffer, HwVertexBuffer>();
}

Driver::IndexBufferHandle MetalDriver::createIndexBufferSynchronous() noexcept {
    return alloc_handle<MetalIndexBuffer, HwIndexBuffer>();
}

Driver::TextureHandle MetalDriver::createTextureSynchronous() noexcept {
    return {};
}

Driver::SamplerBufferHandle MetalDriver::createSamplerBufferSynchronous() noexcept {
    return {};
}

Driver::UniformBufferHandle MetalDriver::createUniformBufferSynchronous() noexcept {
    return alloc_handle<MetalUniformBuffer, HwUniformBuffer>();
}

Driver::RenderPrimitiveHandle MetalDriver::createRenderPrimitiveSynchronous() noexcept {
    return alloc_handle<MetalRenderPrimitive, HwRenderPrimitive>();
}

Driver::ProgramHandle MetalDriver::createProgramSynchronous() noexcept {
    return Driver::ProgramHandle((Driver::ProgramHandle::HandleId)0xDEAD0000);
}

Driver::RenderTargetHandle MetalDriver::createDefaultRenderTargetSynchronous() noexcept {
    return {};
}

Driver::RenderTargetHandle MetalDriver::createRenderTargetSynchronous() noexcept {
    return {};
}

Driver::FenceHandle MetalDriver::createFenceSynchronous() noexcept {
    return {};
}

Driver::SwapChainHandle MetalDriver::createSwapChainSynchronous() noexcept {
    return alloc_handle<MetalSwapChain, HwSwapChain>();
}

Driver::StreamHandle MetalDriver::createStreamFromTextureIdSynchronous() noexcept {
    return {};
}

void MetalDriver::destroyVertexBuffer(Driver::VertexBufferHandle vbh) {

}

void MetalDriver::destroyIndexBuffer(Driver::IndexBufferHandle ibh) {

}

void MetalDriver::destroyRenderPrimitive(Driver::RenderPrimitiveHandle rph) {

}

void MetalDriver::destroyProgram(Driver::ProgramHandle ph) {

}

void MetalDriver::destroySamplerBuffer(Driver::SamplerBufferHandle sbh) {

}

void MetalDriver::destroyUniformBuffer(Driver::UniformBufferHandle ubh) {

}

void MetalDriver::destroyTexture(Driver::TextureHandle th) {

}

void MetalDriver::destroyRenderTarget(Driver::RenderTargetHandle rth) {

}

void MetalDriver::destroySwapChain(Driver::SwapChainHandle sch) {

}

void MetalDriver::destroyStream(Driver::StreamHandle sh) {

}

void MetalDriver::terminate() {

}

Driver::StreamHandle MetalDriver::createStream(void* stream) {
    return {};
}

void MetalDriver::setStreamDimensions(Driver::StreamHandle stream, uint32_t width,
        uint32_t height) {

}

int64_t MetalDriver::getStreamTimestamp(Driver::StreamHandle stream) {
    return 0;
}

void MetalDriver::updateStreams(driver::DriverApi* driver) {

}

void MetalDriver::destroyFence(Driver::FenceHandle fh) {

}

Driver::FenceStatus MetalDriver::wait(Driver::FenceHandle fh, uint64_t timeout) {
    return FenceStatus::ERROR;
}

bool MetalDriver::isTextureFormatSupported(Driver::TextureFormat format) {
    return true;
}

bool MetalDriver::isRenderTargetFormatSupported(Driver::TextureFormat format) {
    return true;
}

bool MetalDriver::isFrameTimeSupported() {
    return false;
}

void MetalDriver::loadVertexBuffer(Driver::VertexBufferHandle vbh, size_t index,
        Driver::BufferDescriptor&& data, uint32_t byteOffset, uint32_t byteSize) {
    auto* vb = handle_cast<MetalVertexBuffer>(mHandleMap, vbh);
    memcpy(vb->buffer.contents, data.buffer, data.size);
}

void MetalDriver::loadIndexBuffer(Driver::IndexBufferHandle ibh, Driver::BufferDescriptor&& data,
        uint32_t byteOffset, uint32_t byteSize) {
    auto* ib = handle_cast<MetalIndexBuffer>(mHandleMap, ibh);
    memcpy(ib->buffer.contents, data.buffer, data.size);
}

void MetalDriver::load2DImage(Driver::TextureHandle th, uint32_t level, uint32_t xoffset,
        uint32_t yoffset, uint32_t width, uint32_t height, Driver::PixelBufferDescriptor&& data) {

}

void MetalDriver::loadCubeImage(Driver::TextureHandle th, uint32_t level,
        Driver::PixelBufferDescriptor&& data, Driver::FaceOffsets faceOffsets) {

}

void MetalDriver::setExternalImage(Driver::TextureHandle th, void* image) {

}

void MetalDriver::setExternalStream(Driver::TextureHandle th, Driver::StreamHandle sh) {

}

void MetalDriver::generateMipmaps(Driver::TextureHandle th) {

}

void MetalDriver::updateUniformBuffer(Driver::UniformBufferHandle ubh,
        Driver::BufferDescriptor&& data) {
    auto buffer = handle_cast<MetalUniformBuffer>(mHandleMap, ubh);
    memcpy(buffer->buffer.contents, data.buffer, data.size);
}

void MetalDriver::updateSamplerBuffer(Driver::SamplerBufferHandle ubh,
        SamplerBuffer&& samplerBuffer) {

}

void MetalDriver::beginRenderPass(Driver::RenderTargetHandle rth,
        const Driver::RenderPassParams& params) {
    ASSERT_PRECONDITION(pImpl->mCurrentDrawable != nullptr, "mCurrentDrawable is null.");
    MTLRenderPassDescriptor* descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    descriptor.colorAttachments[0].texture = pImpl->mCurrentDrawable.texture;
    descriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    descriptor.colorAttachments[0].clearColor = MTLClearColorMake(
            params.clearColor.r, params.clearColor.g, params.clearColor.b, params.clearColor.a
    );

    pImpl->mCurrentCommandEncoder =
            [pImpl->mCurrentCommandBuffer renderCommandEncoderWithDescriptor:descriptor];
}

void MetalDriver::endRenderPass(int dummy) {
    [pImpl->mCurrentCommandEncoder endEncoding];

    // Command encoders are one time use. Set it to nullptr so we don't accidentally use it again..
    pImpl->mCurrentCommandEncoder = nullptr;
}

void MetalDriver::discardSubRenderTargetBuffers(Driver::RenderTargetHandle rth,
        Driver::TargetBufferFlags targetBufferFlags, uint32_t left, uint32_t bottom, uint32_t width,
        uint32_t height) {

}

void MetalDriver::resizeRenderTarget(Driver::RenderTargetHandle rth, uint32_t width,
        uint32_t height) {

}

void MetalDriver::setRenderPrimitiveBuffer(Driver::RenderPrimitiveHandle rph,
        Driver::VertexBufferHandle vbh, Driver::IndexBufferHandle ibh, uint32_t enabledAttributes) {
    auto primitive = handle_cast<MetalRenderPrimitive>(mHandleMap, rph);
    primitive->vertexBuffer = handle_cast<MetalVertexBuffer>(mHandleMap, vbh);
    primitive->indexBuffer = handle_cast<MetalIndexBuffer>(mHandleMap, ibh);
}

void MetalDriver::setRenderPrimitiveRange(Driver::RenderPrimitiveHandle rph,
        Driver::PrimitiveType pt, uint32_t offset, uint32_t minIndex, uint32_t maxIndex,
        uint32_t count) {
    auto primitive = handle_cast<MetalRenderPrimitive>(mHandleMap, rph);
    // primitive->setPrimitiveType(pt);
    primitive->offset = offset * primitive->indexBuffer->elementSize;
    primitive->count = count;
    primitive->minIndex = minIndex;
    primitive->maxIndex = maxIndex > minIndex ? maxIndex : primitive->maxVertexCount - 1;
}

void MetalDriver::setViewportScissor(int32_t left, int32_t bottom, uint32_t width,
        uint32_t height) {

}

void MetalDriver::makeCurrent(Driver::SwapChainHandle schDraw, Driver::SwapChainHandle schRead) {
    ASSERT_PRECONDITION_NON_FATAL(schDraw == schRead,
                                  "Metal driver does not support distinct draw/read swap chains.");
    auto* swapChain = handle_cast<MetalSwapChain>(mHandleMap, schDraw);
    pImpl->mCurrentDrawable = [swapChain->layer nextDrawable];
}

void MetalDriver::commit(Driver::SwapChainHandle sch) {
    [pImpl->mCurrentCommandBuffer presentDrawable:pImpl->mCurrentDrawable];
    [pImpl->mCurrentCommandBuffer commit];
}

void MetalDriver::viewport(ssize_t left, ssize_t bottom, size_t width, size_t height) {

}

void MetalDriver::bindUniformBuffer(size_t index, Driver::UniformBufferHandle ubh) {
    utils::slog.d << "bindUniformBuffer(" << utils::io::endl
                  << "    index  = " << index << utils::io::endl
                  << ");" << utils::io::endl;
    pImpl->mBoundUniforms[index] = ubh;
}

void MetalDriver::bindUniformBufferRange(size_t index, Driver::UniformBufferHandle ubh,
        size_t offset, size_t size) {
    utils::slog.d << "bindUniformBufferRange(" << utils::io::endl
                  << "    index  = " << index << utils::io::endl
                  << "    offset = " << offset << utils::io::endl
                  << "    size   = " << size << utils::io::endl
                  << ");" << utils::io::endl;
    pImpl->mBoundUniforms[index] = ubh;
}

void MetalDriver::bindSamplers(size_t index, Driver::SamplerBufferHandle sbh) {

}

void MetalDriver::insertEventMarker(const char* string, size_t len) {

}

void MetalDriver::pushGroupMarker(const char* string, size_t len) {

}

void MetalDriver::popGroupMarker(int dummy) {

}

void MetalDriver::readPixels(Driver::RenderTargetHandle src, uint32_t x, uint32_t y, uint32_t width,
        uint32_t height, Driver::PixelBufferDescriptor&& data) {

}

void MetalDriver::readStreamPixels(Driver::StreamHandle sh, uint32_t x, uint32_t y, uint32_t width,
        uint32_t height, Driver::PixelBufferDescriptor&& data) {

}

void MetalDriver::blit(Driver::TargetBufferFlags buffers, Driver::RenderTargetHandle dst,
        int32_t dstLeft, int32_t dstBottom, uint32_t dstWidth, uint32_t dstHeight,
        Driver::RenderTargetHandle src, int32_t srcLeft, int32_t srcBottom, uint32_t srcWidth,
        uint32_t srcHeight) {

}

void MetalDriver::draw(Driver::ProgramHandle ph, Driver::RasterState rs,
        Driver::RenderPrimitiveHandle rph) {
    ASSERT_PRECONDITION(pImpl->mCurrentCommandEncoder != nullptr,
            "Attempted to draw without a valid command encoder.");
    auto primitive = handle_cast<MetalRenderPrimitive>(mHandleMap, rph);
    [pImpl->mCurrentCommandEncoder setRenderPipelineState:pImpl->mPipelineState];

    // Bind all the uniform buffers.
    for (const auto& entry : pImpl->mBoundUniforms) {
        const auto bufferIndex = entry.first;
        const auto ubh = entry.second;
        auto* buffer = handle_const_cast<MetalUniformBuffer>(mHandleMap, ubh);

        // We have no way of knowing which uniform buffers will be used by which shader stage so for
        // now, bind the uniform buffer to both the vertex and fragment stages.
        [pImpl->mCurrentCommandEncoder setVertexBuffer:buffer->buffer
                                                offset:0
                                               atIndex:bufferIndex];

        [pImpl->mCurrentCommandEncoder setFragmentBuffer:buffer->buffer
                                                  offset:0
                                                 atIndex:bufferIndex];
    }

    // Bind the vertex buffer.
    [pImpl->mCurrentCommandEncoder setVertexBuffer:primitive->vertexBuffer->buffer
                                            offset:0
                                           atIndex:VERTEX_BUFFER_BINDING];

    [pImpl->mCurrentCommandEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                              indexCount:3
                                               indexType:MTLIndexTypeUInt16
                                             indexBuffer:primitive->indexBuffer->buffer
                                       indexBufferOffset:0];
}

// explicit instantiation of the Dispatcher
template class ConcreteDispatcher<MetalDriver>;

} // namespace filament
