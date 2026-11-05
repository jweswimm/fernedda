cmake_minimum_required(VERSION 3.21)
project(fernedda VERSION 0.2 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick QuickControls2 Network WebSockets)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(fernedda src/main.cpp)

set_source_files_properties(qml/Theme.qml qml/Units.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(fernedda
  URI Fernedda
  VERSION 1.0
  SOURCES
    src/SignalKStore.cpp src/SignalKStore.h
    src/SignalKValue.cpp src/SignalKValue.h
    src/SignalKClient.cpp src/SignalKClient.h
    src/Simulator.cpp src/Simulator.h
    src/HistoryPlot.cpp src/HistoryPlot.h
    src/BoatFolder.cpp src/BoatFolder.h
    src/Msgpack.cpp src/Msgpack.h
    src/NvimLink.cpp src/NvimLink.h
    src/NvimView.cpp src/NvimView.h
    src/KeyRouter.cpp src/KeyRouter.h
  QML_FILES
    qml/Main.qml
    qml/Theme.qml
    qml/Units.qml
    qml/NavRail.qml
    qml/TopBar.qml
    qml/Icon.qml
    qml/Card.qml
    qml/BigNumber.qml
    qml/AnimatedNumber.qml
    qml/RadialGauge.qml
    qml/WindRose.qml
    qml/TankGauge.qml
    qml/BatteryMeter.qml
    qml/DetailOverlay.qml
    qml/DashboardPage.qml
    qml/DataPage.qml
    qml/NotesPage.qml
    qml/SettingsPage.qml
    qml/Page.qml
    qml/Chip.qml
    qml/BoatView.qml
    qml/BoatS235C.js
)

target_include_directories(fernedda PRIVATE src)
# The boat folder and the Neovim module live in the source tree.
target_compile_definitions(fernedda PRIVATE FERNEDDA_SOURCE_DIR="${CMAKE_SOURCE_DIR}")
target_link_libraries(fernedda PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::Network Qt6::WebSockets)

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
