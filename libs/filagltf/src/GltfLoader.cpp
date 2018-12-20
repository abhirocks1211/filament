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
#define TINYGLTF_IMPLEMENTATION
#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_WRITE_IMPLEMENTATION

#include <filament/Engine.h>
#include <filament/VertexBuffer.h>

#include <filagltf/GltfLoader.h>

#include <set>
#include <iostream>
#include <filament/IndexBuffer.h>
#include <filament/RenderableManager.h>

using namespace filament;
using namespace tinygltf;
using namespace math;

GltfLoader::GltfLoader(filament::Engine& engine) : mEngine(engine){}
GltfLoader::~GltfLoader(){}

VertexBuffer::AttributeType intToAttributeType(int componentType, int type) {
    switch (componentType) {
        case TINYGLTF_PARAMETER_TYPE_BYTE :
            switch (type) {
                case TINYGLTF_TYPE_VEC2 : return VertexBuffer::AttributeType::BYTE2;
                case TINYGLTF_TYPE_VEC3 : return VertexBuffer::AttributeType::BYTE3;
                case TINYGLTF_TYPE_VEC4 : return VertexBuffer::AttributeType::BYTE4;
                default: return VertexBuffer::AttributeType::BYTE;
            }
        case TINYGLTF_PARAMETER_TYPE_UNSIGNED_BYTE : return VertexBuffer::AttributeType::UBYTE;
            switch (type) {
                case TINYGLTF_TYPE_VEC2 : return VertexBuffer::AttributeType::UBYTE2;
                case TINYGLTF_TYPE_VEC3 : return VertexBuffer::AttributeType::UBYTE3;
                case TINYGLTF_TYPE_VEC4 : return VertexBuffer::AttributeType::UBYTE4;
                default: return VertexBuffer::AttributeType::UBYTE;
            }
        case TINYGLTF_PARAMETER_TYPE_SHORT : return VertexBuffer::AttributeType::SHORT;
            switch (type) {
                case TINYGLTF_TYPE_VEC2 : return VertexBuffer::AttributeType::SHORT2;
                case TINYGLTF_TYPE_VEC3 : return VertexBuffer::AttributeType::SHORT3;
                case TINYGLTF_TYPE_VEC4 : return VertexBuffer::AttributeType::SHORT4;
                default: return VertexBuffer::AttributeType::SHORT;
            }
        case TINYGLTF_PARAMETER_TYPE_UNSIGNED_SHORT : return VertexBuffer::AttributeType::USHORT;
            switch (type) {
                case TINYGLTF_TYPE_VEC2 : return VertexBuffer::AttributeType::USHORT2;
                case TINYGLTF_TYPE_VEC3 : return VertexBuffer::AttributeType::USHORT3;
                case TINYGLTF_TYPE_VEC4 : return VertexBuffer::AttributeType::USHORT4;
                default: return VertexBuffer::AttributeType::USHORT;
            }
        case TINYGLTF_PARAMETER_TYPE_INT : return VertexBuffer::AttributeType::INT;
        case TINYGLTF_PARAMETER_TYPE_UNSIGNED_INT : return VertexBuffer::AttributeType::UINT;
        case TINYGLTF_PARAMETER_TYPE_FLOAT :
            switch (type) {
                case TINYGLTF_TYPE_VEC2 : return VertexBuffer::AttributeType::FLOAT2;
                case TINYGLTF_TYPE_VEC3 : return VertexBuffer::AttributeType::FLOAT3;
                case TINYGLTF_TYPE_VEC4 : return VertexBuffer::AttributeType::FLOAT4;
                default: return VertexBuffer::AttributeType::FLOAT;
            }
        case TINYGLTF_PARAMETER_TYPE_FLOAT_VEC2 : return VertexBuffer::AttributeType::FLOAT2;
        case TINYGLTF_PARAMETER_TYPE_FLOAT_VEC3 : return VertexBuffer::AttributeType::FLOAT3;
        case TINYGLTF_PARAMETER_TYPE_FLOAT_VEC4 : return VertexBuffer::AttributeType::FLOAT4;
        default :
            std::cerr << "unsupported componentType with value " << componentType << std::endl;
            assert(false);
        //There is no double AttributeType
    }
}

VertexAttribute stringToAttribute(std::string string) {
    if (string == "POSITION") {
        return VertexAttribute::POSITION;
    } else if (string == "TANGENT") {
        return VertexAttribute::TANGENTS;
    } else if (string == "TEXCOORD_0") {
        return VertexAttribute::UV0;
    } else if (string == "TEXCOORD_1") {
        return VertexAttribute::UV1;
    } else if (string == "COLOR_0") {
        return VertexAttribute::COLOR;
    } else {
        std::cerr << "unsupported attribute type " << string << std::endl;
        assert(false);
    }
}

static std::vector<int> getRootNodeIndices(const Model& model) {
    std::set<int> notRootNodes;
    for (size_t i = 0; i < model.nodes.size(); i++) {
        for (int child : model.nodes[i].children) {
            notRootNodes.insert(child);
        }
    }

    std::vector<int> rootNodes = {};
    for (int i = 0; i < model.nodes.size(); i++) {
        if (notRootNodes.find(i) == notRootNodes.end()) {
            rootNodes.emplace_back(i);
        }
    }

    return rootNodes;
}

static void processNode(const Model& model, int rootIndex, std::vector<utils::Entity>& renderables,
        mat4f parentTransform) {
    Node node = model.nodes[rootIndex];

//    for (node.mesh.)
//        VertexBuffer::Builder vbb;
//    vbb.bufferCount(model.buffers.size())


//    for (int child : node.children) {
//        processNode(model, child, renderables, node.matrix)
//    }
}

static void processNodes(const Model& model, int rootIndex, std::vector<utils::Entity>& renderables) {
    processNode(model, rootIndex, renderables, mat4f());
}

std::vector<utils::Entity> GltfLoader::Load(const std::string& filename){
    Model model;
    TinyGLTF loader;
    std::string err;
    std::string warn;
    bool ret = loader.LoadASCIIFromFile(&model, &err, &warn, filename);

    if (!warn.empty()) {
        printf("Warn: %s\n", warn.c_str());
    }

    if (!err.empty()) {
        printf("Err: %s\n", err.c_str());
    }

    if (!ret) {
        printf("Failed to parse glTF\n");
    }


    // Turn meshes into renderables

    std::vector<utils::Entity> renderables = {};
    for (Mesh mesh : model.meshes) {
        for (Primitive primitive : mesh.primitives) {
            VertexBuffer *vb = getVertexBufferForPrimitive(model, primitive);
            RenderableManager::Builder builder(1);
            builder.boundingBox()
        }
    }


    //Find Root Nodes

    std::vector<int> rootNodes = getRootNodeIndices(model);
    for (int root : rootNodes) {
        std::cout << "root" << root << std::endl;
    }

    //Recursively process root nodes


    // Load Buffers
    for (size_t i = 0; i < model.buffers.size(); i++) {
        const tinygltf::Buffer &buffer = model.buffers[i];
        std::cout << buffer.uri << std::endl;
    }

    // Load Buffer Views
    //
    std::cout << model.defaultScene << std::endl;

    for (size_t i = 0; i < model.meshes.size(); i++) {
        std::cout << model.meshes[i].name << std::endl;

    }


    return renderables;
}



VertexBuffer* GltfLoader::getVertexBufferForPrimitive(const Model &model, const Primitive &primitive) const {
    VertexBuffer::Builder vbb = VertexBuffer::Builder();

    //TODO: instead of making empty buffers, map indices to numbers [0, number of bufferViews used by primitive)
    int vertexCount = 0;
    int bufferCount = 0;
    std::set<int> requiredBufferViews;

    for (auto const& attribute : primitive.attributes) {
        std::cout << attribute.first << std::endl;

        Accessor accessor = model.accessors[attribute.second];
        BufferView bufferView = model.bufferViews[accessor.bufferView];
        VertexAttribute attributeName;
        if (attribute.first == "POSITION") {
            attributeName = VertexAttribute::POSITION;
            vertexCount = accessor.count;
        } else if (attribute.first == "TANGENT") {
            attributeName = VertexAttribute::TANGENTS;
        } else if (attribute.first == "TEXCOORD_0") {
            attributeName = VertexAttribute::UV0;
        } else if (attribute.first == "TEXCOORD_1") {
            attributeName = VertexAttribute::UV1;
        } else if (attribute.first == "COLOR_0") {
            attributeName = VertexAttribute::COLOR;
        } else {
            continue;
        }

        bufferCount++;
        requiredBufferViews.insert(accessor.bufferView);
        vbb.attribute(attributeName,
                      accessor.bufferView,
                      intToAttributeType(accessor.componentType, accessor.type),
                      accessor.byteOffset,
                      bufferView.byteStride);

        std::cout << "buffer info : " << std::endl;
        std::cout << accessor.byteOffset << std::endl;
        std::cout << bufferView.byteOffset << std::endl;
        std::cout << bufferView.byteLength << std::endl;
        std::cout << model.buffers[bufferView.buffer].data.size() << std::endl;
    }

    Accessor indexAccessor = model.accessors[primitive.indices];
    BufferView indexBufferView = model.bufferViews[indexAccessor.bufferView];
    Buffer indexBuffer = model.buffers[indexBufferView.buffer];
    IndexBuffer *ibb = IndexBuffer::Builder()
            .indexCount(indexAccessor.count)
            .build(mEngine);
    void *indexData = malloc(indexBufferView.byteLength);
    memcpy(indexData, &indexBuffer.data.at(0) + indexBufferView.byteOffset, indexBufferView.byteLength);
    ibb->setBuffer(mEngine,
            IndexBuffer::BufferDescriptor(indexData, indexBufferView.byteLength, nullptr, nullptr));

    vbb.vertexCount(vertexCount);
    vbb.bufferCount(model.bufferViews.size());

    VertexBuffer* vb = vbb.build(mEngine);

    for (int bufferViewIndex : requiredBufferViews) {
        BufferView bufferView = model.bufferViews[bufferViewIndex];
        Buffer buffer = model.buffers[bufferView.buffer];

        void *data = malloc(bufferView.byteLength);
        memcpy(data, &buffer.data.at(0) + bufferView.byteOffset, bufferView.byteLength);

        vb->setBufferAt(mEngine, bufferViewIndex,
                        VertexBuffer::BufferDescriptor(data, bufferView.byteLength, nullptr, nullptr));


    }

    return vb;
}