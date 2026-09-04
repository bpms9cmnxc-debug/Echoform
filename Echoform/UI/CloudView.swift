import SwiftUI
import SceneKit
import AppKit
import simd

/// SceneKit room: Y-up, occupancy columns, tracked nodes, range rings, trails.
struct CloudView: NSViewRepresentable {
    var voxels: [OccupancyVoxel]
    var poses: [Pose]
    var trails: [String: [SIMD3<Float>]]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = NSColor(calibratedRed: 0.02, green: 0.06, blue: 0.08, alpha: 1)
        v.allowsCameraControl = true
        v.antialiasingMode = .multisampling4X
        v.autoenablesDefaultLighting = false

        let scene = SCNScene()
        v.scene = scene
        let root = scene.rootNode

        let cam = SCNNode()
        cam.name = "cam"
        cam.camera = SCNCamera()
        cam.camera?.zNear = 0.08
        cam.camera?.zFar = 40
        cam.camera?.fieldOfView = 46
        cam.position = SCNVector3(4.8, 3.5, 5.2)
        cam.look(at: SCNVector3(0, 0.9, 0))
        root.addChildNode(cam)
        v.pointOfView = cam

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 400
        ambient.light?.color = NSColor(calibratedRed: 0.5, green: 0.75, blue: 0.8, alpha: 1)
        root.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 800
        key.light?.color = NSColor(calibratedRed: 0.49, green: 0.90, blue: 0.83, alpha: 1)
        key.position = SCNVector3(2.2, 3.2, 1.6)
        root.addChildNode(key)

        let room = SCNNode(geometry: SCNBox(width: 5.2, height: 2.5, length: 3.8, chamferRadius: 0))
        room.name = "room"
        room.position = SCNVector3(0, 1.25, 0)
        room.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.05, green: 0.10, blue: 0.12, alpha: 0.18)
        room.geometry?.firstMaterial?.transparency = 0.12
        room.geometry?.firstMaterial?.isDoubleSided = true
        root.addChildNode(room)

        let floor = SCNNode(geometry: SCNFloor())
        floor.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.03, green: 0.09, blue: 0.10, alpha: 1)
        (floor.geometry as? SCNFloor)?.reflectivity = 0
        root.addChildNode(floor)

        let grid = SCNNode(geometry: SCNPlane(width: 5.2, height: 3.8))
        grid.eulerAngles.x = -.pi / 2
        grid.position.y = 0.01
        grid.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.12, green: 0.20, blue: 0.22, alpha: 1)
        grid.geometry?.firstMaterial?.isDoubleSided = true
        root.addChildNode(grid)

        context.coordinator.view = v
        context.coordinator.ensurePool(in: root)
        return v
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        guard let root = nsView.scene?.rootNode else { return }
        let coord = context.coordinator
        coord.ensurePool(in: root)

        var i = 0
        for vox in voxels.suffix(coord.pool.count) {
            let n = coord.pool[i]
            n.isHidden = false
            let h = CGFloat(0.12 + min(1.6, vox.weight * 0.28))
            n.position = SCNVector3(vox.position.x, Float(h) / 2, vox.position.y)
            n.scale = SCNVector3(0.09, Float(h), 0.09)
            i += 1
        }
        while i < coord.pool.count {
            coord.pool[i].isHidden = true
            i += 1
        }

        root.childNodes.filter { $0.name == "dev" || $0.name == "trail" || $0.name == "ring" }.forEach { $0.removeFromParentNode() }

        for p in poses {
            let height = p.position.z
            let color: NSColor = p.label == "Mac"
                ? NSColor(calibratedWhite: 0.92, alpha: 1)
                : (p.label == "iPhone"
                   ? NSColor(calibratedRed: 0.49, green: 0.90, blue: 0.83, alpha: 1)
                   : NSColor(calibratedRed: 0.79, green: 0.64, blue: 0.15, alpha: 1))
            let ball = SCNNode(geometry: SCNSphere(radius: p.label == "Mac" ? 0.09 : 0.07))
            ball.name = "dev"
            ball.geometry?.firstMaterial?.diffuse.contents = color
            ball.geometry?.firstMaterial?.emission.contents = color
            ball.position = SCNVector3(p.position.x, height, p.position.y)
            root.addChildNode(ball)

            let stem = SCNNode(geometry: SCNCylinder(radius: 0.012, height: CGFloat(max(0.1, height))))
            stem.name = "dev"
            stem.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.45)
            stem.position = SCNVector3(p.position.x, height / 2, p.position.y)
            root.addChildNode(stem)

            if p.label != "Mac" {
                let r = CGFloat(simd_length(SIMD2(p.position.x, p.position.y)))
                if r > 0.15 {
                    let ring = SCNNode(geometry: SCNTorus(ringRadius: r, pipeRadius: 0.012))
                    ring.name = "ring"
                    ring.position = SCNVector3(0, 0.03, 0)
                    ring.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.35)
                    root.addChildNode(ring)
                }
            }

            if let trail = trails[p.label], trail.count > 1 {
                var verts: [SCNVector3] = trail.map { SCNVector3($0.x, $0.z, $0.y) }
                let src = SCNGeometrySource(vertices: verts)
                var idx: [Int32] = []
                for k in 0..<(verts.count - 1) {
                    idx.append(Int32(k))
                    idx.append(Int32(k + 1))
                }
                let dat = idx.withUnsafeBufferPointer { Data(buffer: $0) }
                let elem = SCNGeometryElement(data: dat, primitiveType: .line, primitiveCount: verts.count - 1, bytesPerIndex: 4)
                let geo = SCNGeometry(sources: [src], elements: [elem])
                geo.firstMaterial?.diffuse.contents = color
                geo.firstMaterial?.emission.contents = color
                let tn = SCNNode(geometry: geo)
                tn.name = "trail"
                root.addChildNode(tn)
            }
        }
    }

    final class Coordinator {
        var view: SCNView?
        var pool: [SCNNode] = []
        func ensurePool(in root: SCNNode) {
            if pool.count >= 500 { return }
            let mat = SCNMaterial()
            mat.diffuse.contents = NSColor(calibratedRed: 0.49, green: 0.90, blue: 0.83, alpha: 0.7)
            mat.emission.contents = NSColor(calibratedRed: 0.49, green: 0.90, blue: 0.83, alpha: 0.35)
            mat.transparency = 0.7
            for _ in pool.count..<500 {
                let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
                box.firstMaterial = mat
                let n = SCNNode(geometry: box)
                n.name = "vox"
                n.isHidden = true
                root.addChildNode(n)
                pool.append(n)
            }
        }
    }
}
