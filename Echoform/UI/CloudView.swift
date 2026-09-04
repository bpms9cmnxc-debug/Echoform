import SwiftUI
import SceneKit
import AppKit
import simd

/// SceneKit host that always fills its SwiftUI slot (zero-size SCNView was the blank 3D).
final class CloudSCNView: NSView {
    let scn = SCNView(frame: .zero)
    var pool: [SCNNode] = []
    var deviceNodes: [String: SCNNode] = [:]
    var stemNodes: [String: SCNNode] = [:]
    var labelNodes: [String: SCNNode] = [:]
    var ringNodes: [String: SCNNode] = [:]
    var trailNode = SCNNode()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        scn.autoresizingMask = [.width, .height]
        scn.backgroundColor = NSColor(calibratedRed: 0.02, green: 0.06, blue: 0.08, alpha: 1)
        scn.allowsCameraControl = true
        scn.antialiasingMode = .multisampling4X
        scn.autoenablesDefaultLighting = false
        let scene = SCNScene()
        scn.scene = scene
        addSubview(scn)
        buildWorld(scene.rootNode)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func layout() {
        super.layout()
        scn.frame = bounds
    }

    private func buildWorld(_ root: SCNNode) {
        let cam = SCNNode()
        cam.name = "cam"
        cam.camera = SCNCamera()
        cam.camera?.zNear = 0.05
        cam.camera?.zFar = 60
        cam.camera?.fieldOfView = 50
        cam.position = SCNVector3(5.4, 3.8, 5.8)
        cam.look(at: SCNVector3(0, 0.9, 0))
        root.addChildNode(cam)
        scn.pointOfView = cam

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 650
        ambient.light?.color = NSColor.white
        root.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 1100
        key.position = SCNVector3(2.4, 4.0, 2.0)
        root.addChildNode(key)

        let floor = SCNNode(geometry: SCNPlane(width: 5.2, height: 3.8))
        floor.eulerAngles.x = -.pi / 2
        floor.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.04, green: 0.11, blue: 0.13, alpha: 1)
        floor.geometry?.firstMaterial?.isDoubleSided = true
        root.addChildNode(floor)

        let edges = SCNNode(geometry: SCNBox(width: 5.2, height: 2.5, length: 3.8, chamferRadius: 0))
        edges.position = SCNVector3(0, 1.25, 0)
        edges.geometry?.firstMaterial?.fillMode = .lines
        edges.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.49, green: 0.90, blue: 0.83, alpha: 1)
        edges.geometry?.firstMaterial?.lightingModel = .constant
        root.addChildNode(edges)

        let origin = SCNNode(geometry: SCNSphere(radius: 0.05))
        origin.geometry?.firstMaterial?.diffuse.contents = NSColor.white
        origin.geometry?.firstMaterial?.emission.contents = NSColor.white
        origin.position = SCNVector3(0, 0.05, 0)
        root.addChildNode(origin)

        trailNode.name = "trails"
        root.addChildNode(trailNode)

        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor(calibratedRed: 0.49, green: 0.90, blue: 0.83, alpha: 0.75)
        mat.emission.contents = NSColor(calibratedRed: 0.49, green: 0.90, blue: 0.83, alpha: 0.4)
        mat.transparency = 0.65
        for _ in 0..<400 {
            let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
            box.firstMaterial = mat
            let n = SCNNode(geometry: box)
            n.isHidden = true
            root.addChildNode(n)
            pool.append(n)
        }
    }

    func render(voxels: [OccupancyVoxel], poses: [Pose], trails: [String: [SIMD3<Float>]]) {
        guard let root = scn.scene?.rootNode else { return }

        var i = 0
        for vox in voxels.suffix(pool.count) {
            let n = pool[i]
            n.isHidden = false
            let h = CGFloat(max(0.12, min(1.8, 0.12 + vox.weight * 0.28)))
            n.position = SCNVector3(vox.position.x, Float(h) * 0.5, vox.position.y)
            n.scale = SCNVector3(0.1, Float(h), 0.1)
            i += 1
        }
        while i < pool.count {
            pool[i].isHidden = true
            i += 1
        }

        for p in poses {
            let color: NSColor = p.label == "Mac"
                ? .white
                : (p.label == "iPhone"
                   ? NSColor(calibratedRed: 0.49, green: 0.90, blue: 0.83, alpha: 1)
                   : NSColor(calibratedRed: 0.86, green: 0.70, blue: 0.18, alpha: 1))
            let y = max(0.2, p.position.z)
            if deviceNodes[p.label] == nil {
                let ball = SCNNode(geometry: SCNSphere(radius: p.label == "Mac" ? 0.11 : 0.09))
                ball.geometry?.firstMaterial?.lightingModel = .constant
                root.addChildNode(ball)
                deviceNodes[p.label] = ball
                let stem = SCNNode(geometry: SCNCylinder(radius: 0.015, height: 1))
                stem.geometry?.firstMaterial?.lightingModel = .constant
                root.addChildNode(stem)
                stemNodes[p.label] = stem
                let text = SCNText(string: p.label, extrusionDepth: 0.2)
                text.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
                text.firstMaterial?.diffuse.contents = color
                text.firstMaterial?.lightingModel = .constant
                let tn = SCNNode(geometry: text)
                tn.scale = SCNVector3(0.012, 0.012, 0.012)
                root.addChildNode(tn)
                labelNodes[p.label] = tn
            }
            deviceNodes[p.label]?.geometry?.firstMaterial?.diffuse.contents = color
            deviceNodes[p.label]?.geometry?.firstMaterial?.emission.contents = color
            deviceNodes[p.label]?.position = SCNVector3(p.position.x, y, p.position.y)
            stemNodes[p.label]?.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.5)
            stemNodes[p.label]?.position = SCNVector3(p.position.x, y * 0.5, p.position.y)
            stemNodes[p.label]?.scale = SCNVector3(1, y, 1)
            labelNodes[p.label]?.position = SCNVector3(p.position.x + 0.12, y + 0.14, p.position.y)

            if p.label != "Mac" {
                let r = CGFloat(max(0.2, hypot(p.position.x, p.position.y)))
                if ringNodes[p.label] == nil {
                    let ring = SCNNode(geometry: SCNTorus(ringRadius: 1, pipeRadius: 0.012))
                    ring.geometry?.firstMaterial?.lightingModel = .constant
                    root.addChildNode(ring)
                    ringNodes[p.label] = ring
                }
                ringNodes[p.label]?.geometry = SCNTorus(ringRadius: r, pipeRadius: 0.012)
                ringNodes[p.label]?.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.45)
                ringNodes[p.label]?.geometry?.firstMaterial?.lightingModel = .constant
                ringNodes[p.label]?.position = SCNVector3(0, 0.03, 0)
            }
        }

        trailNode.childNodes.forEach { $0.removeFromParentNode() }
        for (id, pts) in trails where pts.count > 1 {
            let color: NSColor = id == "iPhone"
                ? NSColor(calibratedRed: 0.49, green: 0.90, blue: 0.83, alpha: 1)
                : NSColor(calibratedRed: 0.86, green: 0.70, blue: 0.18, alpha: 1)
            var verts = pts.map { SCNVector3($0.x, $0.z, $0.y) }
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
            geo.firstMaterial?.lightingModel = .constant
            trailNode.addChildNode(SCNNode(geometry: geo))
        }
    }
}

struct CloudView: NSViewRepresentable {
    var voxels: [OccupancyVoxel]
    var poses: [Pose]
    var trails: [String: [SIMD3<Float>]]

    func makeNSView(context: Context) -> CloudSCNView {
        CloudSCNView(frame: NSRect(x: 0, y: 0, width: 800, height: 560))
    }

    func updateNSView(_ nsView: CloudSCNView, context: Context) {
        nsView.render(voxels: voxels, poses: poses, trails: trails)
    }
}
