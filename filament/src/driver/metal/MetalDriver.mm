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
#include "MetalEnums.h"
#include "MetalHandles.h"

#include <AppKit/AppKit.h>
#include <Metal/Metal.h>
#include <QuartzCore/QuartzCore.h>

#include <utils/Log.h>
#include <utils/Panic.h>
#include <utils/trap.h>

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

    SamplerStateCache mSamplerStateCache;

    id<MTLSamplerState> mBoundSamplers[NUM_SAMPLER_BINDINGS] = {};
    id<MTLTexture> mBoundTextures[NUM_SAMPLER_BINDINGS] = {};
    bool mSamplersDirty = true;
    bool mTexturesDirty = true;

    MetalSamplerBuffer* mSamplerBindings[NUM_SAMPLER_BINDINGS];

    // Surface-related properties.
    id<CAMetalDrawable> mCurrentDrawable = nullptr;
    id<MTLTexture> mDepthTexture = nullptr;
    MTLViewport mCurrentViewport = {};
    NSUInteger mSurfaceHeight = 0;
};

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
    pImpl->mSamplerStateCache.setDevice(pImpl->mDevice);
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

void MetalDriver::createTexture(Driver::TextureHandle th, Driver::SamplerType target, uint8_t levels,
        Driver::TextureFormat format, uint8_t samples, uint32_t width, uint32_t height,
        uint32_t depth, Driver::TextureUsage usage) {
    construct_handle<MetalTexture>(mHandleMap, th, pImpl->mDevice, target, levels, format, samples,
            width, height, depth, usage);
}

void MetalDriver::createSamplerBuffer(Driver::SamplerBufferHandle sbh, size_t size) {
    construct_handle<MetalSamplerBuffer>(mHandleMap, sbh, size);
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
    return alloc_handle<MetalTexture, HwTexture>();
}

Driver::SamplerBufferHandle MetalDriver::createSamplerBufferSynchronous() noexcept {
    return alloc_handle<MetalSamplerBuffer, HwSamplerBuffer>();
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

void MetalDriver::updateVertexBuffer(Driver::VertexBufferHandle vbh, size_t index,
        Driver::BufferDescriptor&& data, uint32_t byteOffset, uint32_t byteSize) {
    auto* vb = handle_cast<MetalVertexBuffer>(mHandleMap, vbh);
    memcpy(vb->buffers[index].contents, data.buffer, data.size);
}

void MetalDriver::updateIndexBuffer(Driver::IndexBufferHandle ibh, Driver::BufferDescriptor&& data,
        uint32_t byteOffset, uint32_t byteSize) {
    auto* ib = handle_cast<MetalIndexBuffer>(mHandleMap, ibh);
    memcpy(ib->buffer.contents, data.buffer, data.size);
}

void MetalDriver::update2DImage(Driver::TextureHandle th, uint32_t level, uint32_t xoffset,
        uint32_t yoffset, uint32_t width, uint32_t height, Driver::PixelBufferDescriptor&& data) {
    auto tex = handle_cast<MetalTexture>(mHandleMap, th);
    tex->load2DImage(level, xoffset, yoffset, width, height, data);
    scheduleDestroy(std::move(data));
}

void MetalDriver::updateCubeImage(Driver::TextureHandle th, uint32_t level,
        Driver::PixelBufferDescriptor&& data, Driver::FaceOffsets faceOffsets) {
    auto tex = handle_cast<MetalTexture>(mHandleMap, th);
    tex->loadCubeImage(data, faceOffsets, level);
    scheduleDestroy(std::move(data));
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

void MetalDriver::updateSamplerBuffer(Driver::SamplerBufferHandle sbh,
        SamplerBuffer&& samplerBuffer) {
    auto sb = handle_cast<MetalSamplerBuffer>(mHandleMap, sbh);
    // todo: enable a move here.
    *sb->sb = samplerBuffer;
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
    for (auto& i : pImpl->mUniformState) {
        i.invalidate();
    }
    pImpl->mDepthStencilState.invalidate();
    pImpl->mSamplersDirty = true;
    pImpl->mTexturesDirty = true;
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
    auto sb = handle_cast<MetalSamplerBuffer>(mHandleMap, sbh);
    pImpl->mSamplerBindings[index] = sb;
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

    uint8_t offset = NUM_UBUFFER_BINDINGS;

    for (uint8_t bufferIdx = 0; bufferIdx < NUM_SAMPLER_BINDINGS; bufferIdx++) {
        MetalSamplerBuffer* metalSb = pImpl->mSamplerBindings[bufferIdx];
        if (!metalSb) {
            continue;
        }
        SamplerBuffer* sb = metalSb->sb.get();
        for (uint8_t samplerIdx = 0; samplerIdx < sb->getSize(); samplerIdx++) {
            const SamplerBuffer::Sampler* sampler = sb->getBuffer() + samplerIdx;
            if (!sampler->t) {
                continue;
            }
            uint8_t binding, group;
            if (program->samplerBindings.getSamplerBinding(bufferIdx, samplerIdx, &binding,
                    &group)) {

                const auto metalTexture = handle_const_cast<MetalTexture>(mHandleMap, sampler->t);
                auto& textureSlot = pImpl->mBoundTextures[binding - offset];
                if (textureSlot != metalTexture->texture) {
                    textureSlot = metalTexture->texture;
                    pImpl->mTexturesDirty = true;
                }

                id<MTLSamplerState> samplerState =
                        pImpl->mSamplerStateCache.getOrCreateState(sampler->s);
                auto& samplerSlot = pImpl->mBoundSamplers[binding - offset];
                if (samplerSlot != samplerState) {
                    samplerSlot = samplerState;
                    pImpl->mSamplersDirty = true;
                }
            }
        }
    }

    // Similar to uniforms, we can't tell which stage will use the textures / samplers, so bind
    // to both the vertex and fragment stages.

    NSRange range {
        .length = NUM_SAMPLER_BINDINGS,
        .location = SAMPLER_BINDINGS_START
    };
    if (pImpl->mTexturesDirty) {
        [pImpl->mCurrentCommandEncoder setFragmentTextures:pImpl->mBoundTextures
                                                 withRange:range];
        [pImpl->mCurrentCommandEncoder setVertexTextures:pImpl->mBoundTextures
                                               withRange:range];
        pImpl->mTexturesDirty = false;
    }

    if (pImpl->mSamplersDirty) {
        [pImpl->mCurrentCommandEncoder setFragmentSamplerStates:pImpl->mBoundSamplers
                                                      withRange:range];
        [pImpl->mCurrentCommandEncoder setVertexSamplerStates:pImpl->mBoundSamplers
                                                    withRange:range];
        pImpl->mSamplersDirty = false;
    }

    // Bind the vertex buffers.
    NSRange bufferRange = NSMakeRange(VERTEX_BUFFER_START, primitive->buffers.size());
    [pImpl->mCurrentCommandEncoder setVertexBuffers:primitive->buffers.data()
                                            offsets:primitive->offsets.data()
                                          withRange:bufferRange];

    MetalIndexBuffer* indexBuffer = primitive->indexBuffer;

    [pImpl->mCurrentCommandEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                              indexCount:primitive->count
                                               indexType:getIndexType(indexBuffer->elementSize)
                                             indexBuffer:indexBuffer->buffer
                                       indexBufferOffset:0];
}

} // namespace driver

// explicit instantiation of the Dispatcher
template class ConcreteDispatcher<driver::MetalDriver>;

} // namespace filament
