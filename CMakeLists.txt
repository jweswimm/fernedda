cmake_minimum_required(VERSION 3.21)
project(fernedda VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Qt6 6.5 REQUIRED COMPONENTS Widgets Concurrent)

add_executable(fernedda
  src/main.cpp
  src/MainWindow.cpp src/MainWindow.h
  src/PictureView.cpp src/PictureView.h
  src/Store.cpp src/Store.h
  src/Opener.cpp src/Opener.h
)
target_link_libraries(fernedda PRIVATE Qt6::Widgets Qt6::Concurrent)

# Install for the current user (~/.local) unless a prefix is given.
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "$ENV{HOME}/.local" CACHE PATH "Install prefix" FORCE)
endif()

include(GNUInstallDirs)
install(TARGETS fernedda RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES fernedda.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)

# Every successful build also installs, so the launcher always runs the latest version.
option(FERNEDDA_AUTO_INSTALL "Install after every build" ON)
if(FERNEDDA_AUTO_INSTALL)
  add_custom_command(TARGET fernedda POST_BUILD
    COMMAND ${CMAKE_COMMAND} --install ${CMAKE_BINARY_DIR}
    COMMENT "Installing fernedda to ${CMAKE_INSTALL_PREFIX}")
endif()
