cmake_minimum_required(VERSION 3.1)
project(filagltf)

set(TARGET filagltf)
set(PUBLIC_HDR_DIR include)

# ==================================================================================================
# Sources and headers
# ==================================================================================================
set(PUBLIC_HDRS
        include/filagltf/GltfLoader.h
        include/filagltf/GltfAsset.h
)

set(SRCS
        src/GltfLoader.cpp
        src/GltfAsset.cpp
)

# ==================================================================================================
# Include and target definitions
# ==================================================================================================
include_directories(${PUBLIC_HDR_DIR})

add_library(${TARGET} STATIC ${PUBLIC_HDRS} ${SRCS})

target_include_directories(${TARGET} PUBLIC ${PUBLIC_HDR_DIR})

target_link_libraries(${TARGET} PUBLIC tinygltf filament)
