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

    MTLTextureUsage metalUsage;
    constexpr NSUInteger MetalTextureUsageReadWrite =
            MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    switch (usage) {
        case TextureUsage::DEFAULT:
            metalUsage = MetalTextureUsageReadWrite;
            break;

        case TextureUsage::COLOR_ATTACHMENT:
            metalUsage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
            break;

        case TextureUsage::DEPTH_ATTACHMENT:
            metalUsage = MTLTextureUsageRenderTarget;
            break;
    }
    descriptor.usage = metalUsage;

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
