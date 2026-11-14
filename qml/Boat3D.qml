import QtQuick
import QtQuick3D
import QtQuick3D.Helpers
import Fernedda
import "BoatMesh.js" as Mesh

// The outside of the boat in 3D, turning slowly, in the theme's colours.
// Loaded by NotesPage only when first shown, and only animates while visible.
View3D {
    id: root
    readonly property var parts: Mesh.build()
    readonly property int turnMs: 75000

    environment: SceneEnvironment {
        backgroundMode: SceneEnvironment.Transparent
        antialiasingMode: SceneEnvironment.MSAA
        antialiasingQuality: SceneEnvironment.High
    }
    camera: camera

    // Fit the boat at any angle: its height, or its width when pointing across.
    readonly property real halfFov: fov / 2 * Math.PI / 180
    readonly property real fov: 22
    readonly property real distance: Math.max(9.2 / Math.tan(halfFov),
                                              6.9 / (Math.tan(halfFov) * Math.max(0.1, width / Math.max(1, height))))
    readonly property real tilt: 10
    PerspectiveCamera {
        id: camera
        fieldOfView: root.fov
        clipNear: 1
        clipFar: 500
        eulerRotation.x: -root.tilt
        position: Qt.vector3d(0, 6.4 + root.distance * Math.sin(root.tilt * Math.PI / 180),
                              root.distance * Math.cos(root.tilt * Math.PI / 180))
    }

    // Light stays put while the boat turns. Tinted in red mode, so that highlights
    // don't break night vision.
    readonly property color light: Theme.mode === "red" ? "#ff5a4a" : "#ffffff"
    readonly property real lightLevel: Theme.mode === "red" ? 0.5 : 1
    // Gelcoat and sailcloth stay pale on the day theme, where text is dark.
    readonly property color paint: Theme.dark ? Theme.text : Theme.border
    DirectionalLight {
        eulerRotation: Qt.vector3d(-38, -32, 0)
        color: root.light
        brightness: root.lightLevel
        ambientColor: Qt.rgba(root.light.r * 0.36 * root.lightLevel, root.light.g * 0.36 * root.lightLevel, root.light.b * 0.36 * root.lightLevel, 1)
    }
    DirectionalLight {
        eulerRotation: Qt.vector3d(-12, 140, 0)
        color: root.light
        brightness: 0.28 * root.lightLevel
    }

    component Part: Model {
        id: model
        required property string part
        required property color tint
        property real alpha: 1
        property real rough: 0.62
        geometry: ProceduralMesh {
            positions: root.parts[model.part].positions
            normals: root.parts[model.part].normals
            indexes: root.parts[model.part].indexes
        }
        materials: PrincipledMaterial {
            baseColor: model.tint
            roughness: model.rough
            metalness: 0
            cullMode: Material.NoCulling
            alphaMode: model.alpha < 1 ? PrincipledMaterial.Blend : PrincipledMaterial.Opaque
            opacity: model.alpha
        }
    }

    Part { part: "water"; tint: Theme.accent2; alpha: 0.13; rough: 0.3; x: -Mesh.centre }

    Node {
        id: turntable
        NumberAnimation on eulerRotation.y {
            from: 0
            to: 360
            duration: root.turnMs
            loops: Animation.Infinite
            running: root.visible
        }
        Node {
            x: -Mesh.centre
            Part { part: "topsides"; tint: root.paint; rough: 0.35 }
            Part { part: "bottom"; tint: Theme.depth; rough: 0.8 }
            Part { part: "stripe"; tint: Theme.accent; rough: 0.4 }
            Part { part: "deck"; tint: Theme.dark ? Theme.textDim : Theme.textFaint; rough: 0.85 }
            Part { part: "house"; tint: root.paint; rough: 0.45 }
            Part { part: "well"; tint: Theme.textFaint; rough: 0.85 }
            Part { part: "glass"; tint: Theme.dark ? Theme.surface : Theme.text; rough: 0.2 }
            Part { part: "spar"; tint: Theme.textDim; rough: 0.35 }
            Part { part: "wire"; tint: Theme.textDim; rough: 0.5 }
            Part { part: "sail"; tint: root.paint; alpha: 0.72; rough: 0.9 }
            Part { part: "seam"; tint: Theme.textDim; alpha: 0.5; rough: 0.9 }
        }
    }
}
