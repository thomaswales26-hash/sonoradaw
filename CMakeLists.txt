cmake_minimum_required(VERSION 3.24)
set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0")
project(Sonora LANGUAGES Swift)

set(CMAKE_Swift_LANGUAGE_VERSION 5)

add_executable(Sonora MACOSX_BUNDLE main.swift)
target_compile_options(Sonora PRIVATE
    "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
)
target_link_libraries(Sonora PRIVATE
    "-framework AppKit"
    "-framework AVFoundation"
    "-framework AudioToolbox"
    "-framework UniformTypeIdentifiers"
)

set_target_properties(Sonora PROPERTIES
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.sonora.workstation"
    MACOSX_BUNDLE_BUNDLE_VERSION "1"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
)

add_custom_command(TARGET Sonora POST_BUILD
    COMMAND /usr/bin/open -n "$<TARGET_BUNDLE_DIR:Sonora>"
    COMMENT "Launching Sonora"
)
