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
