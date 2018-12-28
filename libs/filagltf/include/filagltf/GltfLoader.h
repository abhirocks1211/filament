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

#ifndef TNT_GLTFLOADER_H
#define TNT_GLTFLOADER_H

#include <math/mat4.h>

namespace filament {
    class Engine;
    class VertexBuffer;
    class IndexBuffer;
    class Material;
    class MaterialInstance;
    class Renderable;
    class VertexVuffer;
}

#include <filagltf/GltfAsset.h>
#include <functional>
#include <string>
#include <tiny_gltf.h>

class GltfLoader {
public:
    using mat4f = math::mat4f;
    using loadCallback = std::function<void(std::string)>;

    GltfLoader(filament::Engine& engine, filament::Material *defaultMaterial);
    ~GltfLoader();

    std::vector<utils::Entity> Load(const std::string &filename);

private:

    filament::Engine& mEngine;
    filament::Material* mDefaultColorMaterial = nullptr;

    utils::Entity getVertexBufferForPrimitive(const tinygltf::Model &model,
            const tinygltf::Primitive &primitive) const;
};


#endif //TNT_GLTFLOADER_H
