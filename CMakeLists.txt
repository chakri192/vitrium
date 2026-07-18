cmake_minimum_required(VERSION 3.16)
project(Vitrum LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTOUIC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Widgets)

set(SOURCES
    src/main.cpp
    src/MainWindow.cpp
    src/Editor.cpp
    src/Highlighter.cpp
    src/AutoHideBar.cpp
    src/FindBar.cpp
    src/FileWorker.cpp
)
set(HEADERS
    src/MainWindow.h
    src/Editor.h
    src/Highlighter.h
    src/AutoHideBar.h
    src/FindBar.h
    src/FileWorker.h
)

if(APPLE)
    list(APPEND SOURCES src/MacVibrancy.mm)
    list(APPEND HEADERS src/MacVibrancy.h)
endif()

add_executable(Vitrum MACOSX_BUNDLE ${SOURCES} ${HEADERS})
target_link_libraries(Vitrum PRIVATE Qt6::Widgets)

if(APPLE)
    target_link_libraries(Vitrum PRIVATE "-framework Cocoa")
    set_source_files_properties(src/MacVibrancy.mm PROPERTIES COMPILE_FLAGS "-x objective-c++ -fobjc-arc")
    set_target_properties(Vitrum PROPERTIES
        MACOSX_BUNDLE_BUNDLE_NAME "Vitrum"
        MACOSX_BUNDLE_GUI_IDENTIFIER "dev.chakradharv.vitrum"
    )
else()
    target_compile_definitions(Vitrum PRIVATE VITRUM_NO_MAC_VIBRANCY)
endif()
