//
//  HorizontalGestureHandler.swift
//  testPlay
//
//  Created by Muhamad Azis on 18/07/25.
//

import SwiftUI
import RealityKit

class HorizontalGestureHandler: ObservableObject {
    
    @Published var maxLeftDistance: Float = -0.5
    @Published var maxRightDistance: Float = 1.8
    @Published var sensitivity: Float = 0.02
    @Published var responsiveness: Float = 0.15
    @Published var returnSpeed: Float = 0.1
    
    // MARK: - Internal Properties
    private weak var playerEntity: Entity?
    private weak var gameController: GameController?
    private var targetHorizontalVelocity: Float = 0.0
    private var isDragging = false
    private var returnToZeroTimer: Timer?
    
    init() {}
    
    // MARK: - Setup
    func setPlayer(_ entity: Entity) {
        self.playerEntity = entity
        print("🎮 Horizontal gesture setup for player: \(entity.name)")
    }
    
    func setGameController(_ controller: GameController) {
        self.gameController = controller
        print("🔗 GameController linked to gesture handler")
    }
    
    func setBoundaries(left: Float, right: Float) {
        maxLeftDistance = left
        maxRightDistance = right
        print("📏 Player boundaries: Left=\(maxLeftDistance), Right=\(maxRightDistance)")
    }
    
    // MARK: - Physics-Based Gesture Handling with Boundaries
    func handleHorizontalDrag(_ translation: CGSize) {
        // Only process if we have game controller and player
        guard let gameController = gameController,
              gameController.canControlPlayer,
              let player = playerEntity else {
            return
        }
        
        isDragging = true
        stopReturnToZero()
        
        let deltaX = Float(translation.width) * sensitivity
        
        // Get current position
        let currentX = player.position.x
        
        // Check boundaries and apply resistance
        var targetVelocity = deltaX * 3.0
        
        // Apply boundary resistance
        if currentX <= maxLeftDistance && targetVelocity < 0 {
            // Player is at or beyond left boundary, resist leftward movement
            targetVelocity *= 0.1
            print("🚧 Left boundary resistance applied")
        } else if currentX >= maxRightDistance && targetVelocity > 0 {
            // Player is at or beyond right boundary, resist rightward movement
            targetVelocity *= 0.1
            print("🚧 Right boundary resistance applied")
        }
        
        // Clamp velocity
        targetHorizontalVelocity = max(-2.5, min(2.5, targetVelocity))
        
        // Apply through game controller
        gameController.applyPlayerHorizontalMovement(targetHorizontalVelocity)
        
        print("🎮 Player horizontal: pos=\(String(format: "%.2f", currentX)), velocity=\(String(format: "%.2f", targetHorizontalVelocity))")
    }
    
    func handleDragStart() {
        guard gameController?.canControlPlayer == true else { return }
        
        isDragging = true
        stopReturnToZero()
        print("👆 Player horizontal drag started")
    }
    
    func handleDragEnd() {
        isDragging = false
        startReturnToZero()
        print("🏁 Player horizontal drag ended - returning to center")
    }
    
    // MARK: - Boundary Enforcement
    private func enforceBoundaries() {
        guard let player = playerEntity,
              let gameController = gameController else { return }
        
        let currentX = player.position.x
        var correctionVelocity: Float = 0.0
        
        if currentX < maxLeftDistance {
            // Push player back to right
            correctionVelocity = (maxLeftDistance - currentX) * 2.0
            print("🚧 Pushing player back from left boundary")
        } else if currentX > maxRightDistance {
            // Push player back to left
            correctionVelocity = (maxRightDistance - currentX) * 2.0
            print("🚧 Pushing player back from right boundary")
        }
        
        if correctionVelocity != 0 {
            gameController.applyPlayerHorizontalMovement(correctionVelocity)
        }
    }
    
    // MARK: - Return to Zero Velocity with Boundary Check
    private func startReturnToZero() {
        returnToZeroTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            self.updateReturnToZero()
        }
    }
    
    private func stopReturnToZero() {
        returnToZeroTimer?.invalidate()
        returnToZeroTimer = nil
    }
    
    private func updateReturnToZero() {
        guard !isDragging,
              let gameController = gameController,
              gameController.canControlPlayer else {
            stopReturnToZero()
            return
        }
        
        // Check boundaries first
        enforceBoundaries()
        
        // Gradually reduce horizontal velocity to zero for player
        targetHorizontalVelocity *= (1.0 - returnSpeed)
        
        // Stop when velocity is very small
        if abs(targetHorizontalVelocity) < 0.01 {
            targetHorizontalVelocity = 0.0
            stopReturnToZero()
        }
        
        // Apply reduced velocity to player only
        gameController.applyPlayerHorizontalMovement(targetHorizontalVelocity)
    }
    
    // MARK: - Manual Position Control with Boundaries
    func moveToPosition(_ targetVelocity: Float) {
        guard let gameController = gameController,
              let player = playerEntity else { return }
        
        let currentX = player.position.x
        var adjustedVelocity = targetVelocity
        
        // Check boundaries
        if (currentX <= maxLeftDistance && adjustedVelocity < 0) ||
           (currentX >= maxRightDistance && adjustedVelocity > 0) {
            adjustedVelocity = 0.0
        }
        
        stopReturnToZero()
        targetHorizontalVelocity = max(-2.5, min(2.5, adjustedVelocity))
        gameController.applyPlayerHorizontalMovement(targetHorizontalVelocity)
        
        // After short delay, return to zero
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.startReturnToZero()
        }
        
        print("📍 Player manual move: velocity=\(targetHorizontalVelocity)")
    }
    
    func moveToCenter() {
        guard let gameController = gameController else { return }
        
        targetHorizontalVelocity = 0.0
        gameController.applyPlayerHorizontalMovement(0.0)
        stopReturnToZero()
        print("🎯 Player moved to center (zero velocity)")
    }
    
    // MARK: - Status Methods
    func getCurrentVelocity() -> Float {
        guard let player = playerEntity,
              let motion = player.components[PhysicsMotionComponent.self] else { return 0.0 }
        return motion.linearVelocity.x
    }
    
    func getCurrentPosition() -> Float {
        return playerEntity?.position.x ?? 0.0
    }
    
    func isAtBoundary() -> (left: Bool, right: Bool) {
        let currentX = getCurrentPosition()
        let tolerance: Float = 0.1
        
        return (
            left: currentX <= (maxLeftDistance + tolerance),
            right: currentX >= (maxRightDistance - tolerance)
        )
    }
    
    func isPlayerControlActive() -> Bool {
        return gameController?.canControlPlayer == true
    }
    
    // MARK: - Cleanup
    func cleanup() {
        stopReturnToZero()
        targetHorizontalVelocity = 0.0
        isDragging = false
        print("🧹 Player horizontal gesture cleanup completed")
    }
    
    // MARK: - Debug Info
    func getDebugInfo() -> String {
        let currentPos = getCurrentPosition()
        let currentVel = getCurrentVelocity()
        let boundaries = isAtBoundary()
        let controlActive = isPlayerControlActive()
        
        return """
        Player Control Active: \(controlActive)
        Position: \(String(format: "%.2f", currentPos))
        Velocity: \(String(format: "%.2f", currentVel))
        Target Vel: \(String(format: "%.2f", targetHorizontalVelocity))
        Boundaries: [\(maxLeftDistance), \(maxRightDistance)]
        At Left: \(boundaries.left), At Right: \(boundaries.right)
        Dragging: \(isDragging)
        """
    }
}

// MARK: - SwiftUI Gesture Extension
extension HorizontalGestureHandler {
    
    var horizontalGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let horizontalMovement = abs(value.translation.width)
                let verticalMovement = abs(value.translation.height)
                
                // Only process significant horizontal movement for player
                if horizontalMovement > verticalMovement {
                    if !self.isDragging {
                        self.handleDragStart()
                    }
                    self.handleHorizontalDrag(value.translation)
                }
            }
            .onEnded { _ in
                self.handleDragEnd()
            }
    }
    
    var preciseHorizontalGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let horizontalMovement = abs(value.translation.width)
                let verticalMovement = abs(value.translation.height)
                
                if horizontalMovement > verticalMovement * 1.2 {
                    if !self.isDragging {
                        self.handleDragStart()
                    }
                    self.handleHorizontalDrag(value.translation)
                }
            }
            .onEnded { _ in
                self.handleDragEnd()
            }
    }
}

// MARK: - Boundary Presets
extension HorizontalGestureHandler {
    
    func setNarrowTrack() {
        setBoundaries(left: -0.3, right: 0.3)
    }
    
    func setMediumTrack() {
        setBoundaries(left: -0.5, right: 1.8)
    }
    
    func setWideTrack() {
        setBoundaries(left: -1.0, right: 2.0)
    }
    
    func setCustomTrack(leftBound: Float, rightBound: Float) {
        setBoundaries(left: leftBound, right: rightBound)
    }
    
    // Test movement functions for player
    func testPlayerMovement() {
        guard let gameController = gameController else { return }
        
        print("🧪 Testing player movement...")
        
        // Test left movement
        gameController.applyPlayerHorizontalMovement(-1.0)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Test right movement
            gameController.applyPlayerHorizontalMovement(1.0)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Return to center
                gameController.applyPlayerHorizontalMovement(0.0)
                print("🧪 Player movement test complete")
            }
        }
    }
}
