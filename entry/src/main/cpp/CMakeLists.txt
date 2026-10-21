cmake_minimum_required(VERSION 3.10)
project(mpv_napi)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(NAPI_ROOT "${OHOS_NAPI}/sysroot/usr")
get_filename_component(VIDEO_PROJECT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../.." ABSOLUTE)
set(MPV_DIST_DIR "${VIDEO_PROJECT_ROOT}/native/mpv/dist")
set(MPV_LIB "${MPV_DIST_DIR}/lib/${OHOS_ARCH}/libmpv.so")
set(MPV_INCLUDE_DIR "${MPV_DIST_DIR}/include")

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -D_GNU_SOURCE -D__MUSL__")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -D_GNU_SOURCE -D__MUSL__")

if(OHOS_ARCH STREQUAL "x86_64")
    add_library(mpv_napi SHARED
        mpv_client_napi_stub.cpp
    )

    target_include_directories(mpv_napi PRIVATE
        ${NAPI_ROOT}/include
    )

    target_link_libraries(mpv_napi PRIVATE
        ace_napi.z
    )
else()
    if(NOT EXISTS "${MPV_LIB}")
        message(FATAL_ERROR "Root mpv runtime not found: ${MPV_LIB}")
    endif()

    add_library(mpv_runtime SHARED IMPORTED GLOBAL)
    set_target_properties(mpv_runtime PROPERTIES
        IMPORTED_LOCATION "${MPV_LIB}"
        IMPORTED_SONAME "libmpv.so"
    )

    add_library(mpv_napi SHARED
        mpv_client_wrapper.cpp
        mpv_event_handler.cpp
        ohos_surface_helper.cpp
        video_processing_helper.cpp
        m3u8_converter_native.cpp
        video_thumbnail_native.cpp
        mpv_client_napi.cpp
    )

    target_include_directories(mpv_napi PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${NAPI_ROOT}/include
        ${MPV_INCLUDE_DIR}
        ${MPV_INCLUDE_DIR}/mpv
    )

    target_link_libraries(mpv_napi PRIVATE
        mpv_runtime
        ace_napi.z
        hilog_ndk.z
        video_processing
        native_media_core
        native_window
        libc++_shared.so
    )
endif()

set_target_properties(mpv_napi PROPERTIES
    OUTPUT_NAME "mpv_napi"
    LINK_FLAGS "-Wl,--as-needed -Wl,--gc-sections -Wl,--disable-new-dtags"
    INSTALL_RPATH ""
    BUILD_RPATH_USE_ORIGIN FALSE
    SKIP_BUILD_RPATH TRUE
)

# Node headers are scoped to their own compilation unit: they declare a different
# Node-API ABI from HarmonyOS native_api.h. Existing mpv compilation is untouched.
set(CATNODE_ROOT "${VIDEO_PROJECT_ROOT}/native/node")
set(CATNODE_HEADERS "${CATNODE_ROOT}/vendor/node-v24.2.0/include/node")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CATNODE_ROOT}/dist/patched/runtime-info.cmake")
set(CATNODE_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libnode.so.137")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CATNODE_LIBRARY}")
if(OHOS_ARCH STREQUAL "arm64-v8a")
    if(NOT EXISTS "${CATNODE_LIBRARY}" OR NOT EXISTS "${CATNODE_HEADERS}/node.h")
        message(FATAL_ERROR "Prepare the patched Node runtime and matching headers first; see native/node/README.md")
    endif()
    add_library(catnode_runtime SHARED IMPORTED)
    set_target_properties(catnode_runtime PROPERTIES IMPORTED_LOCATION "${CATNODE_LIBRARY}")
    add_library(catnode_napi SHARED catnode_napi.cpp catnode_runtime.cpp)
    set_source_files_properties(catnode_runtime.cpp PROPERTIES
        COMPILE_FLAGS "-std=c++20"
        INCLUDE_DIRECTORIES "${CATNODE_HEADERS}")
    target_link_libraries(catnode_napi PRIVATE ace_napi.z catnode_runtime libc++_shared.so)
    if(EXISTS "${CATNODE_ROOT}/dist/patched/runtime-info.cmake")
        include("${CATNODE_ROOT}/dist/patched/runtime-info.cmake")
        file(SHA256 "${CATNODE_LIBRARY}" CATNODE_ACTUAL_HASH)
        if(CATNODE_IOURING_DISABLED AND CATNODE_ACTUAL_HASH STREQUAL CATNODE_RUNTIME_SHA256)
            target_compile_definitions(catnode_napi PRIVATE CATNODE_SANDBOX_READY=1)
        endif()
    endif()
endif()
