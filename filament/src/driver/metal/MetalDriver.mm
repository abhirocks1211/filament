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

#include "MetalBinder.h"

#include <AppKit/AppKit.h>
#include <Metal/Metal.h>
#include <QuartzCore/QuartzCore.h>

#include <utils/Log.h>
#include <utils/Panic.h>
#include <utils/trap.h>

#include <unordered_map>
#include <vector>

namespace filament {
namespace driver {

struct MetalDriverImpl {
    id<MTLDevice> mDevice = nullptr;
    id<MTLCommandQueue> mCommandQueue = nullptr;

    // Single use, re-created each frame.
    id<MTLCommandBuffer> mCurrentCommandBuffer = nullptr;
    id<MTLRenderCommandEncoder> mCurrentCommandEncoder = nullptr;

    UniformBufferStateTracker mUniformState[VERTEX_BUFFER_START];

    MetalBinder mBinder;

    DepthStencilStateTracker mDepthStencilState;
    DepthStencilStateCache mDepthStencilStateCache;

    // Surface-related properties.
    id<CAMetalDrawable> mCurrentDrawable = nullptr;
    id<MTLTexture> mDepthTexture = nullptr;
    MTLViewport mCurrentViewport = {};
    NSUInteger mSurfaceHeight = 0;
};

// A hack, for now. Put all vertex data into buffer 10 so that it does not conflict with uniform
// buffers.
constexpr uint8_t VERTEX_BUFFER_BINDING = 10;

static MTLVertexFormat getMetalFormat(ElementType type, bool normalized) {
    if (normalized) {
        switch (type) {
            // Single Component Types
            case ElementType::BYTE: return MTLVertexFormatCharNormalized;
            case ElementType::UBYTE: return MTLVertexFormatUCharNormalized;
            case ElementType::SHORT: return MTLVertexFormatShortNormalized;
            case ElementType::USHORT: return MTLVertexFormatUShortNormalized;
            // Two Component Types
            case ElementType::BYTE2: return MTLVertexFormatChar2Normalized;
            case ElementType::UBYTE2: return MTLVertexFormatUChar2Normalized;
            case ElementType::SHORT2: return MTLVertexFormatShort2Normalized;
            case ElementType::USHORT2: return MTLVertexFormatUShort2Normalized;
            // Three Component Types
            case ElementType::BYTE3: return MTLVertexFormatChar3Normalized;
            case ElementType::UBYTE3: return MTLVertexFormatUChar3Normalized;
            case ElementType::SHORT3: return MTLVertexFormatShort3Normalized;
            case ElementType::USHORT3: return MTLVertexFormatUShort3Normalized;
            // Four Component Types
            case ElementType::BYTE4: return MTLVertexFormatChar4Normalized;
            case ElementType::UBYTE4: return MTLVertexFormatUChar4Normalized;
            case ElementType::SHORT4: return MTLVertexFormatShort4Normalized;
            case ElementType::USHORT4: return MTLVertexFormatUShort4Normalized;
            default:
                ASSERT_POSTCONDITION(false, "Normalized format does not exist.");
                return MTLVertexFormatInvalid;
        }
    }
    switch (type) {
        // Single Component Types
        case ElementType::BYTE: return MTLVertexFormatChar;
        case ElementType::UBYTE: return MTLVertexFormatUChar;
        case ElementType::SHORT: return MTLVertexFormatShort;
        case ElementType::USHORT: return MTLVertexFormatUShort;
        case ElementType::HALF: return MTLVertexFormatHalf;
        case ElementType::INT: return MTLVertexFormatInt;
        case ElementType::UINT: return MTLVertexFormatUInt;
        case ElementType::FLOAT: return MTLVertexFormatFloat;
        // Two Component Types
        case ElementType::BYTE2: return MTLVertexFormatChar2;
        case ElementType::UBYTE2: return MTLVertexFormatUChar2;
        case ElementType::SHORT2: return MTLVertexFormatShort2;
        case ElementType::USHORT2: return MTLVertexFormatUShort2;
        case ElementType::HALF2: return MTLVertexFormatHalf2;
        case ElementType::FLOAT2: return MTLVertexFormatFloat2;
        // Three Component Types
        case ElementType::BYTE3: return MTLVertexFormatChar3;
        case ElementType::UBYTE3: return MTLVertexFormatUChar3;
        case ElementType::SHORT3: return MTLVertexFormatShort3;
        case ElementType::USHORT3: return MTLVertexFormatUShort3;
        case ElementType::HALF3: return MTLVertexFormatHalf3;
        case ElementType::FLOAT3: return MTLVertexFormatFloat3;
        // Four Component Types
        case ElementType::BYTE4: return MTLVertexFormatChar4;
        case ElementType::UBYTE4: return MTLVertexFormatUChar4;
        case ElementType::SHORT4: return MTLVertexFormatShort4;
        case ElementType::USHORT4: return MTLVertexFormatUShort4;
        case ElementType::HALF4: return MTLVertexFormatHalf4;
        case ElementType::FLOAT4: return MTLVertexFormatFloat4;
    }
    return MTLVertexFormatInvalid;
}


static MTLCompareFunction getMetalCompareFunction(Driver::RasterState::DepthFunc func) {
    switch (func) {
        case Driver::RasterState::DepthFunc::LE: return MTLCompareFunctionLessEqual;
        case Driver::RasterState::DepthFunc::GE: return MTLCompareFunctionGreaterEqual;
        case Driver::RasterState::DepthFunc::L: return MTLCompareFunctionLess;
        case Driver::RasterState::DepthFunc::G: return MTLCompareFunctionGreater;
        case Driver::RasterState::DepthFunc::E: return MTLCompareFunctionEqual;
        case Driver::RasterState::DepthFunc::NE: return MTLCompareFunctionNotEqual;
        case Driver::RasterState::DepthFunc::A: return MTLCompareFunctionAlways;
        case Driver::RasterState::DepthFunc::N: return MTLCompareFunctionNever;
    }
}

// todo: move into Headers file

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
    MetalUniformBuffer(id<MTLDevice> device, size_t size) : HwUniformBuffer(size) {
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
    }

    id<MTLFunction> vertexFunction;
    id<MTLFunction> fragmentFunction;
};

//

Driver* MetalDriver::create(MetalPlatform* const platform) {
    assert(platform);
    return new MetalDriver(platform);
}

MetalDriver::MetalDriver(driver::MetalPlatform* platform) noexcept
        : DriverBase(new ConcreteDispatcher<MetalDriver>(this)),
        mPlatform(*platform),
        pImpl(new MetalDriverImpl) {

    pImpl->mDevice = MTLCreateSystemDefaultDevice();
    pImpl->mCommandQueue = [pImpl->mDevice newCommandQueue];
    pImpl->mBinder.setDevice(pImpl->mDevice);
    pImpl->mDepthStencilStateCache.setDevice(pImpl->mDevice);
    pImpl->mDepthStencilStateCache.setCreationFunction(createDepthStencilState);

    // Create a depth texture and depthStencilState.
}

MetalDriver::~MetalDriver() noexcept {
    [pImpl->mCommandQueue release];
    [pImpl->mDepthTexture release];
    delete pImpl;
}

void MetalDriver::debugCommand(const char *methodName) {
#if METAL_DEBUG_COMMANDS
    utils::slog.d << methodName << utils::io::endl;
#endif
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

void MetalDriver::createProgram(Driver::ProgramHandle rph, Program&& program) {
    construct_handle<MetalProgram>(mHandleMap, rph, pImpl->mDevice, program);
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
    auto *swapChain = construct_handle<MetalSwapChain>(mHandleMap, sch);

    // Obtain the CAMetalLayer-backed view.
    // todo: move this into Platform.
    NSView *nsview = (NSView *) nativeWindow;
    nsview = [nsview viewWithTag:255];
    swapChain->layer = (CAMetalLayer *) nsview.layer;

    // Create the depth buffer.
    // todo: This is a hack for now, and assumes createSwapChain is only called once.
    CGSize size = swapChain->layer.bounds.size;
    CGFloat scale = swapChain->layer.contentsScale;
    auto width = static_cast<NSUInteger>(size.width * scale);
    auto height = static_cast<NSUInteger>(size.height * scale);
    MTLTextureDescriptor* depthTextureDesc =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                               width:width
                                                              height:height
                                                           mipmapped:NO];
    depthTextureDesc.usage = MTLTextureUsageRenderTarget;
    depthTextureDesc.resourceOptions = MTLResourceStorageModePrivate;
    pImpl->mDepthTexture = [pImpl->mDevice newTextureWithDescriptor:depthTextureDesc];
    pImpl->mSurfaceHeight = height;
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
    return alloc_handle<MetalProgram, HwProgram>();
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
    memcpy(vb->buffers[index].contents, data.buffer, data.size);
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
    scheduleDestroy(std::move(data));
}

void MetalDriver::updateSamplerBuffer(Driver::SamplerBufferHandle ubh,
        SamplerBuffer&& samplerBuffer) {

}

void MetalDriver::beginRenderPass(Driver::RenderTargetHandle rth,
        const Driver::RenderPassParams& params) {
    ASSERT_PRECONDITION(pImpl->mCurrentDrawable != nullptr, "mCurrentDrawable is null.");

    // Metal clears the entire attachment without respect to viewport or scissor.
    // todo: might need to clear the scissor area manually via a draw call if we need that
    // functionality.

    MTLRenderPassDescriptor* descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    descriptor.colorAttachments[0].texture = pImpl->mCurrentDrawable.texture;
    descriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    descriptor.colorAttachments[0].clearColor = MTLClearColorMake(
            params.clearColor.r, params.clearColor.g, params.clearColor.b, params.clearColor.a
    );

    descriptor.depthAttachment.texture = pImpl->mDepthTexture;
    descriptor.depthAttachment.clearDepth = params.clearDepth;

    pImpl->mCurrentCommandEncoder =
            [pImpl->mCurrentCommandBuffer renderCommandEncoderWithDescriptor:descriptor];

    viewport(params.left, params.bottom, params.width, params.height);

    // Metal requires a new command encoder for each render pass, and they cannot be reused.
    // We must bind the depth-stencil state for each command encoder, so we dirty the state here
    // to force a rebinding at the first the draw call of this pass.
    for (auto &i : pImpl->mUniformState) {
        i.invalidate();
    }
    pImpl->mDepthStencilState.invalidate();
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
    auto vertexBuffer = handle_cast<MetalVertexBuffer>(mHandleMap, vbh);
    auto indexBuffer = handle_cast<MetalIndexBuffer>(mHandleMap, ibh);
    primitive->setBuffers(vertexBuffer, indexBuffer, enabledAttributes);
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

    if (pImpl->mCurrentDrawable == nil) {
        utils::slog.e << "Could not obtain drawable." << utils::io::endl;
        utils::debug_trap();
    }
}

void MetalDriver::commit(Driver::SwapChainHandle sch) {
    [pImpl->mCurrentCommandBuffer presentDrawable:pImpl->mCurrentDrawable];
    [pImpl->mCurrentCommandBuffer commit];
}

void MetalDriver::viewport(ssize_t left, ssize_t bottom, size_t width, size_t height) {
    ASSERT_PRECONDITION(pImpl->mCurrentCommandEncoder != nullptr, "mCurrentCommandEncoder is null");
    // Flip the viewport, because Metal's screen space is vertically flipped that of Filament's.
    pImpl->mCurrentViewport = MTLViewport {
        .originX = static_cast<double>(left),
        .originY = pImpl->mSurfaceHeight - static_cast<double>(bottom) - static_cast<double>(height),
        .height = static_cast<double>(height),
        .width = static_cast<double>(width),
        .znear = 0.0,
        .zfar = 1.0
    };
}

void MetalDriver::bindUniformBuffer(size_t index, Driver::UniformBufferHandle ubh) {
    pImpl->mUniformState[index].updateState(UniformBufferState {
        .bound = true,
        .ubh = ubh,
        .offset = 0
    });
}

void MetalDriver::bindUniformBufferRange(size_t index, Driver::UniformBufferHandle ubh,
        size_t offset, size_t size) {
    pImpl->mUniformState[index].updateState(UniformBufferState {
        .bound = true,
        .ubh = ubh,
        .offset = offset
    });
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
    auto program = handle_cast<MetalProgram>(mHandleMap, ph);

    pImpl->mBinder.setShaderFunctions(program->vertexFunction, program->fragmentFunction);
    pImpl->mBinder.setVertexDescription(primitive->vertexDescription);

    // Bind a valid pipeline state for this draw call.
    // todo: check if the pipeline state needs to be rebound
    id<MTLRenderPipelineState> pipeline = nullptr;
    pImpl->mBinder.getOrCreatePipelineState(pipeline);
    assert(pipeline != nullptr);
    [pImpl->mCurrentCommandEncoder setRenderPipelineState:pipeline];

    // Set the viewport state.
    [pImpl->mCurrentCommandEncoder setViewport:pImpl->mCurrentViewport];

    // Set the depth-stencil state, if a state change is needed.
    DepthStencilState depthState {
        .compareFunction = getMetalCompareFunction(rs.depthFunc),
        .depthWriteEnabled = rs.depthWrite,
    };
    pImpl->mDepthStencilState.updateState(depthState);
    if (pImpl->mDepthStencilState.stateChanged()) {
        id<MTLDepthStencilState> state =
                pImpl->mDepthStencilStateCache.getOrCreateState(depthState);
        assert(state != nil);
        [pImpl->mCurrentCommandEncoder setDepthStencilState:state];
    }

    // Bind any uniform buffers that have changed since the last draw call.
    for (uint32_t i = 0; i < VERTEX_BUFFER_START; i++) {
        auto& thisUniform = pImpl->mUniformState[i];
        if (thisUniform.stateChanged() ) {
            const auto& uniformState = thisUniform.getState();
            if (!uniformState.bound) {
                continue;
            }

            const auto* uniform = handle_const_cast<MetalUniformBuffer>(mHandleMap,
                    uniformState.ubh);

            // We have no way of knowing which uniform buffers will be used by which shader stage
            // so for now, bind the uniform buffer to both the vertex and fragment stages.

            [pImpl->mCurrentCommandEncoder setVertexBuffer:uniform->buffer
                                                    offset:uniformState.offset
                                                   atIndex:i];

            [pImpl->mCurrentCommandEncoder setFragmentBuffer:uniform->buffer
                                                      offset:uniformState.offset
                                                     atIndex:i];
        }
    }

    // Bind the vertex buffers.
    NSRange bufferRange = NSMakeRange(VERTEX_BUFFER_START, primitive->buffers.size());
    [pImpl->mCurrentCommandEncoder setVertexBuffers:primitive->buffers.data()
                                            offsets:primitive->offsets.data()
                                          withRange:bufferRange];

    [pImpl->mCurrentCommandEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                              indexCount:primitive->count
                                               indexType:MTLIndexTypeUInt16
                                             indexBuffer:primitive->indexBuffer->buffer
                                       indexBufferOffset:0];
}

} // namespace driver

// explicit instantiation of the Dispatcher
template class ConcreteDispatcher<driver::MetalDriver>;

} // namespace filament
