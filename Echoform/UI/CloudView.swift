import SwiftUI
import SceneKit

struct CloudView: NSViewRepresentable {
    var voxels: [OccupancyVoxel]
    var poses: [Pose]

    func makeNSView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = SCNScene()
        v.backgroundColor = .black
        v.allowsCameraControl = true
        v.antialiasingMode = .multisampling4X
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.zFar = 40
        cam.position = SCNVector3(0, -4.2, 2.4)
        cam.look(at: SCNVector3(0, 0, 1))
        v.scene?.rootNode.addChildNode(cam)
        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .omni
        light.position = SCNVector3(2, -3, 6)
        v.scene?.rootNode.addChildNode(light)
        context.coordinator.view = v
        return v
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        guard let root = nsView.scene?.rootNode else { return }
        root.childNodes.filter { $0.name == "dyn" }.forEach { $0.removeFromParentNode() }
        for p in poses {
            let n = SCNNode(geometry: SCNSphere(radius: 0.06))
            n.name = "dyn"
            n.geometry?.firstMaterial?.diffuse.contents = NSColor.systemYellow
            n.position = SCNVector3(p.position.x, p.position.y, p.position.z)
            root.addChildNode(n)
        }
        for vox in voxels.suffix(1500) {
            let n = SCNNode(geometry: SCNBox(width: 0.05, height: 0.05, length: 0.05, chamferRadius: 0))
            n.name = "dyn"
            let w = CGFloat(min(1, vox.weight / 3))
            n.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.2, green: 0.7 + 0.2 * w, blue: 1.0, alpha: 0.35 + 0.5 * w)
            n.position = SCNVector3(vox.position.x, vox.position.y, vox.position.z)
            root.addChildNode(n)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var view: SCNView? }
}
