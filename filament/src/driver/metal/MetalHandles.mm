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

#include "MetalHandles.h"

#include "MetalEnums.h"

#include <details/Texture.h> // for FTexture::getFormatSize

#include <utils/Panic.h>

namespace filament {
namespace driver {

static inline MTLTextureUsage getMetalTextureUsage(TextureUsage usage) {
    switch (usage) {
        case TextureUsage::DEFAULT:
            return MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;

        case TextureUsage::COLOR_ATTACHMENT:
            return MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;

        case TextureUsage::DEPTH_ATTACHMENT:
            return MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    }
}

static inline MTLStorageMode getMetalStorageMode(TextureFormat format) {
    switch (format) {
        // Depth textures must have a private storage mode.
        case TextureFormat::DEPTH16:
        case TextureFormat::DEPTH24:
        case TextureFormat::DEPTH32F:
        case TextureFormat::DEPTH24_STENCIL8:
        case TextureFormat::DEPTH32F_STENCIL8:
            return MTLStorageModePrivate;

        default:
            return MTLStorageModeManaged;

    }
}

MetalTexture::MetalTexture(id<MTLDevice> device, driver::SamplerType target, uint8_t levels,
        TextureFormat format, uint8_t samples, uint32_t width, uint32_t height, uint32_t depth,
        TextureUsage usage) noexcept
    : HwTexture(target, levels, samples, width, height, depth) {

    MTLPixelFormat pixelFormat = getMetalFormat(format);
    bytesPerPixel = static_cast<uint8_t>(details::FTexture::getFormatSize(format));

    ASSERT_POSTCONDITION(pixelFormat != MTLPixelFormatInvalid, "Pixel format not supported.");

    const BOOL mipmapped = levels > 1;

    MTLTextureDescriptor* descriptor;
    if (target == driver::SamplerType::SAMPLER_2D) {
        descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pixelFormat
                                                                        width:width
                                                                       height:height
                                                                    mipmapped:mipmapped];
        descriptor.mipmapLevelCount = levels;
    } else if (target == driver::SamplerType::SAMPLER_CUBEMAP) {
        ASSERT_POSTCONDITION(width == height, "Cubemap faces must be square.");
        descriptor = [MTLTextureDescriptor textureCubeDescriptorWithPixelFormat:pixelFormat
                                                                           size:width
                                                                      mipmapped:mipmapped];
        descriptor.mipmapLevelCount = levels;
    } else {
        ASSERT_POSTCONDITION(false, "Sampler type not supported.");
    }

    descriptor.usage = getMetalTextureUsage(usage);
    descriptor.storageMode = getMetalStorageMode(format);

    texture = [device newTextureWithDescriptor:descriptor];
}

void MetalTexture::load2DImage(uint32_t level, uint32_t xoffset, uint32_t yoffset, uint32_t width,
        uint32_t height, Driver::PixelBufferDescriptor& data) noexcept {
    MTLRegion region {
        .origin = {
            .x = xoffset,
            .y = yoffset,
            .z =  0
        },
        .size = {
            .height = height,
            .width = width,
            .depth = 1
        }
    };
    NSUInteger bytesPerRow = bytesPerPixel * width;
    [texture replaceRegion:region
               mipmapLevel:level
                     slice:0
                 withBytes:data.buffer
               bytesPerRow:bytesPerRow
             bytesPerImage:0];          // only needed for MTLTextureType3D
}

void MetalTexture::loadCubeImage(const PixelBufferDescriptor& data, const FaceOffsets& faceOffsets,
        int miplevel) {
    NSUInteger faceWidth = width >> miplevel;
    NSUInteger bytesPerRow = bytesPerPixel * faceWidth;
    MTLRegion region = MTLRegionMake2D(0, 0, faceWidth, faceWidth);
    for (NSUInteger slice = 0; slice < 6; slice++) {
        auto faceoffset = faceOffsets.offsets[slice];
        [texture replaceRegion:region
                   mipmapLevel:static_cast<NSUInteger>(miplevel)
                         slice:slice
                     withBytes:static_cast<uint8_t*>(data.buffer) + faceoffset
                   bytesPerRow:bytesPerRow
                 bytesPerImage:0];
    }
}

} // namespace driver
} // namespace filament
