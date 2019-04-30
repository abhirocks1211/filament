cmake_minimum_required(VERSION 3.1)
project(filament-tests)

# ==================================================================================================
# Unit tests
# ==================================================================================================

if(NOT IOS AND NOT WEBGL)
    # The following tests rely on private APIs that are stripped
    # away in Release builds
    if (TNT_DEV)
        add_executable(test_${TARGET} filament_test_exposure.cpp filament_framegraph_test.cpp filament_test.cpp)
        target_link_libraries(test_${TARGET} PRIVATE filament gtest)
        target_compile_options(test_${TARGET} PRIVATE ${COMPILER_FLAGS})

        add_executable(test_depth depth_test.cpp)
        target_link_libraries(test_depth PRIVATE utils)
    endif()
endif()

add_library(inlinetest SHARED inlinetest.cpp inlinetest.h inlinetest_main.cpp)

target_link_libraries(inlinetest PUBLIC utils math)

set(OPTIMIZATION_FLAGS
        -ffast-math
        -ffp-contract=fast
        # TODO: aggressive vectorization is currently broken on Android
        #        -fslp-vectorize-aggressive
        -fvisibility=hidden
        -fvisibility-inlines-hidden
        -fstrict-vtable-pointers
        )

target_compile_options(inlinetest PRIVATE
        $<$<CONFIG:Release>:${OPTIMIZATION_FLAGS}>
        $<$<AND:$<PLATFORM_ID:Darwin>,$<CONFIG:Release>>:${DARWIN_OPTIMIZATION_FLAGS}>
        $<$<PLATFORM_ID:Linux>:${LINUX_COMPILER_FLAGS}>
        )