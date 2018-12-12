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

#include <filamat/MaterialBuilder.h>
#include <filamat/PostprocessMaterialBuilder.h>

#include <fstream>

using namespace filament;
using namespace filamat;

int main(int argc, char* argv[]) {
    MaterialBuilder builder;

    {
        builder
                .name("SimpleColor")

                        // goal is to deprecate .set
                .set(Property::BASE_COLOR)

                .shading(Shading::LIT)
                .material(R"SHADER(
                void material(inout MaterialInputs material) {
                    prepareMaterial(material);
                    material.baseColor = float4(0.8, 0.8, 0.8, 1.0);
                    material.metallic = 1.0;
                    material.roughness = 0.5;
                }
            )SHADER")
                .platform(MaterialBuilder::Platform::DESKTOP)
                .targetApi(MaterialBuilder::TargetApi::ALL);

        Package pkg = builder.build();
    }
    {
        builder
                .name("SimpleColor")

                        // goal is to deprecate .set
                .set(Property::BASE_COLOR)

                .shading(Shading::LIT)
                .material(R"SHADER(
                void material(inout MaterialInputs material) {
                    prepareMaterial(material);
                    material.baseColor = float4(0.8, 0.8, 0.8, 1.0);
                    material.metallic = 1.0;
                    material.roughness = 0.5;
                }
            )SHADER")
                .platform(MaterialBuilder::Platform::DESKTOP)
                .targetApi(MaterialBuilder::TargetApi::ALL);

        Package pkg = builder.build();
    }

    /*
    std::ofstream output;
    output.open("output.bmat", std::ios::binary);
    output.write((char*)pkg.getData(), pkg.getSize());
    output.close();
     */

    return 0;
}
