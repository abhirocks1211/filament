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

namespace filament {

struct MetalDriverImpl {
    id<MTLDevice> mDevice;
    id<MTLCommandQueue> mCommandQueue;
    CAMetalLayer* mLayer;
};

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
}

MetalDriver::~MetalDriver() noexcept {
    delete pImpl;
}

void MetalDriver::debugCommand(const char *methodName) {
    utils::slog.d << methodName << utils::io::endl;
}

void MetalDriver::beginFrame(int64_t monotonic_clock_ns, uint32_t frameId) {

}

void MetalDriver::setPresentationTime(int64_t monotonic_clock_ns) {

}

void MetalDriver::endFrame(uint32_t frameId) {

}

void MetalDriver::flush(int dummy) {

}

void MetalDriver::createVertexBuffer(Driver::VertexBufferHandle, uint8_t bufferCount,
        uint8_t attributeCount, uint32_t vertexCount, Driver::AttributeArray attributes,
        Driver::BufferUsage usage) {

}

void MetalDriver::createIndexBuffer(Driver::IndexBufferHandle, Driver::ElementType elementType,
        uint32_t indexCount, Driver::BufferUsage usage) {

}

void MetalDriver::createTexture(Driver::TextureHandle, Driver::SamplerType target, uint8_t levels,
        Driver::TextureFormat format, uint8_t samples, uint32_t width, uint32_t height,
        uint32_t depth, Driver::TextureUsage usage) {

}

void MetalDriver::createSamplerBuffer(Driver::SamplerBufferHandle, size_t size) {

}

void MetalDriver::createUniformBuffer(Driver::UniformBufferHandle, size_t size,
        Driver::BufferUsage usage) {

}

void MetalDriver::createRenderPrimitive(Driver::RenderPrimitiveHandle, int dummy) {

}

void MetalDriver::createProgram(Driver::ProgramHandle, Program&& program) {

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

void MetalDriver::createSwapChain(Driver::SwapChainHandle, void* nativeWindow, uint64_t flags) {
    // Obtain the CAMetalLayer-backed view.
    NSView* nsview = (NSView*) nativeWindow;
    nsview = [nsview viewWithTag:255];
    CAMetalLayer* mlayer = (CAMetalLayer*) nsview.layer;

    // todo: HACK
    pImpl->mLayer = mlayer;
}

void MetalDriver::createStreamFromTextureId(Driver::StreamHandle, intptr_t externalTextureId,
        uint32_t width, uint32_t height) {

}

Driver::VertexBufferHandle MetalDriver::createVertexBufferSynchronous() noexcept {
    return {};
}

Driver::IndexBufferHandle MetalDriver::createIndexBufferSynchronous() noexcept {
    return {};
}

Driver::TextureHandle MetalDriver::createTextureSynchronous() noexcept {
    return {};
}

Driver::SamplerBufferHandle MetalDriver::createSamplerBufferSynchronous() noexcept {
    return {};
}

Driver::UniformBufferHandle MetalDriver::createUniformBufferSynchronous() noexcept {
    return {};
}

Driver::RenderPrimitiveHandle MetalDriver::createRenderPrimitiveSynchronous() noexcept {
    return {};
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
    return {};
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

}

void MetalDriver::loadIndexBuffer(Driver::IndexBufferHandle ibh, Driver::BufferDescriptor&& data,
        uint32_t byteOffset, uint32_t byteSize) {

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
        Driver::BufferDescriptor&& buffer) {

}

void MetalDriver::updateSamplerBuffer(Driver::SamplerBufferHandle ubh,
        SamplerBuffer&& samplerBuffer) {

}


void MetalDriver::beginRenderPass(Driver::RenderTargetHandle rth,
        const Driver::RenderPassParams& params) {
    id<CAMetalDrawable> drawable = [pImpl->mLayer nextDrawable];

    MTLRenderPassDescriptor* descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    descriptor.colorAttachments[0].texture = drawable.texture;
    descriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    descriptor.colorAttachments[0].clearColor = MTLClearColorMake(
            params.clearColor.r, params.clearColor.g, params.clearColor.b, params.clearColor.a
    );

    id<MTLCommandBuffer> buffer = [pImpl->mCommandQueue commandBuffer];

    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:descriptor];
    [encoder endEncoding];

    [buffer presentDrawable:drawable];
    [buffer commit];
}

void MetalDriver::endRenderPass(int dummy) {

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

}

void MetalDriver::setRenderPrimitiveRange(Driver::RenderPrimitiveHandle rph,
        Driver::PrimitiveType pt, uint32_t offset, uint32_t minIndex, uint32_t maxIndex,
        uint32_t count) {

}

void MetalDriver::setViewportScissor(int32_t left, int32_t bottom, uint32_t width,
        uint32_t height) {

}

void MetalDriver::makeCurrent(Driver::SwapChainHandle schDraw, Driver::SwapChainHandle schRead) {

}

void MetalDriver::commit(Driver::SwapChainHandle sch) {

}

void MetalDriver::viewport(ssize_t left, ssize_t bottom, size_t width, size_t height) {

}

void MetalDriver::bindUniformBuffer(size_t index, Driver::UniformBufferHandle ubh) {

}

void MetalDriver::bindUniformBufferRange(size_t index, Driver::UniformBufferHandle ubh,
        size_t offset, size_t size) {

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

}

// explicit instantiation of the Dispatcher
template class ConcreteDispatcher<MetalDriver>;

} // namespace filament
