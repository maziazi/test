

import SwiftUI
import RealityKit

class CameraFollowManager: ObservableObject {
    private var cameraEntity: Entity?
    private var targetEntity: Entity?
    private var isFollowActive = false
    
    @Published var followDistance: Float = 5.0
    @Published var followHeight: Float = 3.5
    @Published var followSmoothness: Float = 0.2
    @Published var lookAtTarget = true
    @Published var followSideMovement = true
    @Published var followForwardMovement = true
    
    private let minDistance: Float = 2.0
    private let maxDistance: Float = 15.0
    private let minHeight: Float = 0.5
    private let maxHeight: Float = 10.0
    
    init() {}
    
    func setupCamera(content: any RealityViewContentProtocol) {
        let camera = Entity()
        camera.name = "follow_camera"
        
        camera.components.set(PerspectiveCameraComponent(
            near: 0.1,
            far: 100.0,
            fieldOfViewInDegrees: 60
        ))
        
        camera.position = SIMD3<Float>(0, followHeight, followDistance)
        
        let cameraAnchor = AnchorEntity()
        cameraAnchor.addChild(camera)
        content.add(cameraAnchor)
        
        self.cameraEntity = camera
        
        print("✅ Follow Camera created at position: \(camera.position)")
    }
    
    func setTarget(_ entity: Entity) {
        self.targetEntity = entity
        print("🎯 Camera target set to: \(entity.name)")
    }
    
    func startFollowing() {
        isFollowActive = true
        print("▶️ Camera follow started")
    }
    
    func stopFollowing() {
        isFollowActive = false
        print("⏹️ Camera follow stopped")
    }
    
    func updateCameraPosition() {
        guard isFollowActive,
              let camera = cameraEntity,
              let target = targetEntity else { return }
        
        // Calculate target position for camera
        let targetPosition = target.position
        var desiredCameraPosition = targetPosition
        
        // Apply follow distance and height
        if followForwardMovement {
            desiredCameraPosition.z += followDistance
        } else {
            desiredCameraPosition.z = camera.position.z
        }
        
        if followSideMovement {
            desiredCameraPosition.x = targetPosition.x
        } else {
            desiredCameraPosition.x = camera.position.x
        }
        
        desiredCameraPosition.y = targetPosition.y + followHeight
        
        let currentPosition = camera.position
        let newPosition = simd_mix(currentPosition, desiredCameraPosition, SIMD3<Float>(repeating: followSmoothness))
        
        let constrainedPosition = applyConstraints(newPosition, targetPosition: targetPosition)
        camera.position = constrainedPosition
        
        if lookAtTarget {
            camera.look(at: targetPosition, from: constrainedPosition, relativeTo: nil)
        }
    }
    
    private func applyConstraints(_ position: SIMD3<Float>, targetPosition: SIMD3<Float>) -> SIMD3<Float> {
        var constrainedPos = position
        
        let distance = simd_distance(SIMD2<Float>(position.x, position.z),
                                   SIMD2<Float>(targetPosition.x, targetPosition.z))
        
        if distance < minDistance {
            let direction = normalize(SIMD2<Float>(position.x - targetPosition.x, position.z - targetPosition.z))
            let newPos2D = SIMD2<Float>(targetPosition.x, targetPosition.z) + direction * minDistance
            constrainedPos.x = newPos2D.x
            constrainedPos.z = newPos2D.y
        } else if distance > maxDistance {
            let direction = normalize(SIMD2<Float>(position.x - targetPosition.x, position.z - targetPosition.z))
            let newPos2D = SIMD2<Float>(targetPosition.x, targetPosition.z) + direction * maxDistance
            constrainedPos.x = newPos2D.x
            constrainedPos.z = newPos2D.y
        }
        
        constrainedPos.y = max(minHeight, min(maxHeight, constrainedPos.y))
        
        return constrainedPos
    }
    
    func setCloseFollow() {
        followDistance = 3.0
        followHeight = 1.5
        followSmoothness = 0.15
    }
    
    func setMediumFollow() {
        followDistance = 5.0
        followHeight = 2.5
        followSmoothness = 0.1
    }
    
    func setFarFollow() {
        followDistance = 8.0
        followHeight = 4.0
        followSmoothness = 0.08
    }
    
    func setCinematicFollow() {
        followDistance = 6.0
        followHeight = 3.0
        followSmoothness = 0.05
    }
}

