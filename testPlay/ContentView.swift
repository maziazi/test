//
//  ContentView.swift
//  tes
//
//  Created by Muhamad Azis on 16/07/25.
//

import SwiftUI
import RealityKit
import PlayTest

enum GameEntityType: UInt8, Codable {
    case player
    case bot
    case powerup
    case powerdown
    case finish
}

struct GameTagComponent: Component, Codable {
    var type: GameEntityType
}

struct ContentView: View {
    @State var playerEntity: Entity?
    @State var botEntities: [Entity] = []
    @State var collisionSubscriptions: [EventSubscription] = []
    @State private var cameraMode: CameraMode = .followCamera
    @State private var cameraUpdateTimer: Timer?

    @StateObject private var cameraFollowManager = CameraFollowManager()
    @StateObject private var horizontalGestureHandler = HorizontalGestureHandler()
    @StateObject private var gameController = GameController()

    private let moveInterval: TimeInterval = 0.016
    private let trackLeftBoundary: Float = -0.5
    private let trackRightBoundary: Float = 1.8

    enum CameraMode: String, CaseIterable {
        case followCamera = "Follow"
        case dolly = "Dolly"
        case orbit = "Orbit"
    }

    var body: some View {
        ZStack {
            VStack {
                PowerEffectIndicator(gameController: gameController)
                
                RealityView { content in
                    if let scene = try? await Entity(named: "Scene", in: playTestBundle) {
                        
                        cameraFollowManager.setupCamera(content: content)
                        content.add(scene)
                        
                        if let slide = scene.findEntity(named: "Slide") {
                            await applyStaticMeshCollision(to: slide)
                        } else {
                             print("❌ Entitas 'slide' tidak ditemukan")
                        }
                        
                        // Collect all entities
                        var foundBots: [Entity] = []
                        var finishEntity: Entity?
                        
                        walkThroughEntities(entity: scene) { entity in
                            if entity.name.contains("player") {
                                print("🎯 Found player: \(entity.name)")
                                entity.components.set(GameTagComponent(type: .player))
                                playerEntity = entity
                                
                                // Setup camera follow untuk player
                                cameraFollowManager.setTarget(entity)
                                
                                // Setup horizontal gesture hanya untuk player
                                horizontalGestureHandler.setPlayer(entity)
                                horizontalGestureHandler.setBoundaries(
                                    left: trackLeftBoundary,
                                    right: trackRightBoundary
                                )
                                horizontalGestureHandler.setGameController(gameController)
                                
                            } else if entity.name.contains("bot") {
                                print("🤖 Found bot: \(entity.name)")
                                entity.components.set(GameTagComponent(type: .bot))
                                foundBots.append(entity)
                                
                            } else if entity.name.contains("powerup") {
                                print("⚡ Found powerup: \(entity.name)")
                                entity.components.set(GameTagComponent(type: .powerup))
                                
                            } else if entity.name.contains("powerdown") {
                                print("🐌 Found powerdown: \(entity.name)")
                                entity.components.set(GameTagComponent(type: .powerdown))
                                
                            } else if entity.name.lowercased().contains("choco") && entity.name.lowercased().contains("fountain") {
                                print("🏁 Found finish line: \(entity.name)")
                                entity.components.set(GameTagComponent(type: .finish))
                                finishEntity = entity
                            }
                        }
                        
                        // Store bot entities
                        botEntities = foundBots
                        
                        // Setup game controller dengan semua entities, boundaries, dan finish
                        gameController.setEntities(player: playerEntity, bots: botEntities)
                        gameController.setBoundaries(left: trackLeftBoundary, right: trackRightBoundary)
                        
                        if let finish = finishEntity {
                            gameController.setFinishEntity(finish)
                        }
                        
                        // Setup game callbacks
                        setupGameCallbacks()
                        
                        print("✅ Setup complete - Player: \(playerEntity?.name ?? "none"), Bots: \(botEntities.count)")
                        print("📏 Boundaries set: [\(trackLeftBoundary), \(trackRightBoundary)]")
                        print("🏁 Finish entity: \(finishEntity?.name ?? "none")")
                        
                        if cameraMode == .followCamera {
                            cameraFollowManager.startFollowing()
                            startCameraUpdateTimer()
                        }
                        
                        // Setup collision detection untuk semua moving entities (player + bots)
                        setupCollisionDetection(content: content)
                    }
                }
                .realityViewCameraControls(getCameraControl())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    // Gesture hanya untuk player dan hanya aktif saat game playing
                    gameController.canControlPlayer ?
                    horizontalGestureHandler.horizontalGesture : nil
                )

                // Game UI Controls
                VStack(spacing: 12) {
                    PlayButtonView(gameController: gameController)
                    GameControlsView(gameController: gameController)
                }
            }
            
            CountdownView(gameController: gameController)
            LeaderboardView(gameController: gameController)
        }
        .onDisappear {
            cleanup()
        }
    }
    
    private func setupCollisionDetection(content: RealityViewContentProtocol) {
        // Setup collision untuk player
        if let player = playerEntity {
            let playerCollision = content.subscribe(to: CollisionEvents.Began.self, on: player) { event in
                print("🎯 Player collision detected")
                handleCollision(event)
            }
            collisionSubscriptions.append(playerCollision)
        }
        
        // Setup collision untuk setiap bot
        for (index, bot) in botEntities.enumerated() {
            let botCollision = content.subscribe(to: CollisionEvents.Began.self, on: bot) { event in
                print("🤖 Bot \(index + 1) collision detected")
                handleCollision(event)
            }
            collisionSubscriptions.append(botCollision)
        }
        
        print("🔔 Collision detection setup for \(collisionSubscriptions.count) entities")
    }
    
    private func setupGameCallbacks() {
        gameController.onGameStart = {
            print("🚀 Race started - all entities moving")
        }
        
        gameController.onGameEnd = {
            print("🏁 Race ended - all entities stopped")
        }
        
        gameController.onCountdownFinish = {
            print("⏰ Countdown finished - race begin!")
        }
        
        gameController.onReset = {
            print("🔄 Race reset - all entities returned to start")
            // Reset horizontal gesture to center
            self.horizontalGestureHandler.moveToCenter()
            
            // Re-enable all powerups/powerdowns
            self.resetPowerItems()
        }
        
        gameController.onPowerEffectApplied = { effectType in
            print("💫 Power effect applied: \(effectType)")
        }
        
        gameController.onPowerEffectEnded = {
            print("🔄 Power effect ended - back to normal")
        }
        
        gameController.onEntityFinished = { finishInfo in
            print("🏆 \(finishInfo.displayName) finished in position \(finishInfo.position)!")
        }
        
        gameController.onAllEntitiesFinished = { finishedEntities in
            print("🎉 All entities finished! Final results:")
            for entity in finishedEntities {
                print("   \(entity.position). \(entity.displayName)")
            }
        }
    }
    
    private func resetPowerItems() {
        // Re-enable all powerup and powerdown entities
        if let scene = playerEntity?.parent {
            walkThroughEntities(entity: scene) { entity in
                if let tagComponent = entity.components[GameTagComponent.self] {
                    if tagComponent.type == .powerup || tagComponent.type == .powerdown {
                        entity.isEnabled = true
                    }
                }
            }
        }
        print("🔄 Power items reset and re-enabled")
    }

    func startCameraUpdateTimer() {
        stopCameraUpdateTimer()
        cameraUpdateTimer = Timer.scheduledTimer(withTimeInterval: moveInterval, repeats: true) { _ in
            if cameraMode == .followCamera {
                cameraFollowManager.updateCameraPosition()
            }
        }
    }
    
    func stopCameraUpdateTimer() {
        cameraUpdateTimer?.invalidate()
        cameraUpdateTimer = nil
    }

    func walkThroughEntities(entity: Entity, action: (Entity) -> Void) {
        action(entity)
        for child in entity.children {
            walkThroughEntities(entity: child, action: action)
        }
    }

    func handleCollision(_ event: CollisionEvents.Began) {
        // Collision hanya diproses saat game berjalan
        guard gameController.gameState == .playing else { return }
        
        let entityA = event.entityA
        let entityB = event.entityB

        let typeA = entityA.components[GameTagComponent.self]?.type
        let typeB = entityB.components[GameTagComponent.self]?.type

        guard let tA = typeA, let tB = typeB else {
            print("❌ Entity tanpa GameTagComponent")
            return
        }

        // Check collision combinations
        if (tA == .player || tA == .bot) && (tB == .powerup || tB == .powerdown || tB == .finish) {
            applyCollisionEffect(to: entityA, collidedWith: tB, otherEntity: entityB)
        } else if (tB == .player || tB == .bot) && (tA == .powerup || tA == .powerdown || tA == .finish) {
            applyCollisionEffect(to: entityB, collidedWith: tA, otherEntity: entityA)
        }
    }

    func applyCollisionEffect(to entity: Entity, collidedWith type: GameEntityType, otherEntity: Entity) {
        let entityType = entity.components[GameTagComponent.self]?.type
        let entityName = getEntityDisplayName(entity, entityType: entityType)
        
        switch type {
        case .powerup:
            // Apply speed boost to any entity (player or bot)
            gameController.applyPowerEffectToEntity(entity, effectType: .speedBoost, duration: 5.0)
            
            // Hide the powerup
            otherEntity.isEnabled = false
            
            print("⚡ \(entityName) collected powerup - speed boost applied!")
            
        case .powerdown:
            // Apply speed reduction to any entity (player or bot)
            gameController.applyPowerEffectToEntity(entity, effectType: .speedReduction, duration: 3.0)
            
            // Hide the powerdown
            otherEntity.isEnabled = false
            
            print("🐌 \(entityName) hit powerdown - speed reduced!")
            
        case .finish:
            // Handle finish line collision
            print("🏁 \(entityName) reached the finish line!")
            gameController.checkFinish(for: entity)
            
        case .bot, .player:
            // Handle entity-to-entity collision (optional: bounce effect, etc.)
            print("💥 \(entityName) collision with another entity")
            
        default:
            return
        }
    }
    
    private func getEntityDisplayName(_ entity: Entity, entityType: GameEntityType?) -> String {
        if entity === playerEntity {
            return "Player"
        } else if let botIndex = botEntities.firstIndex(where: { $0 === entity }) {
            return "Bot \(botIndex + 1)"
        } else {
            return entity.name
        }
    }
    
    func handleCameraModeChange(_ newMode: CameraMode) {
        switch newMode {
        case .followCamera:
            cameraFollowManager.startFollowing()
            startCameraUpdateTimer()
        default:
            cameraFollowManager.stopFollowing()
            stopCameraUpdateTimer()
        }
    }

    private func getCameraControl() -> CameraControls {
        switch cameraMode {
        case .followCamera:
            return .none
        case .dolly:
            return .dolly
        case .orbit:
            return .orbit
        }
    }
    
    private func cleanup() {
        stopCameraUpdateTimer()
        horizontalGestureHandler.cleanup()
        gameController.cleanup()
        
        // Cancel all collision subscriptions
        for subscription in collisionSubscriptions {
            subscription.cancel()
        }
        collisionSubscriptions.removeAll()
        
        print("🧹 ContentView cleanup completed")
    }
    
    @MainActor
    func applyStaticMeshCollision(to entity: Entity) async {
        for child in entity.children {
            if let model = child as? ModelEntity,
               let modelComponent = model.components[ModelComponent.self] {

                let mesh = modelComponent.mesh

                do {
                    let collision = try await CollisionComponent(shapes: [.generateStaticMesh(from: mesh)])
                    model.components[CollisionComponent.self] = collision
                    print("✅ Static mesh collision applied to: \(model.name)")
                } catch {
                    print("⚠️ Failed to generate static mesh for \(model.name): \(error)")
                    do {
                        let shape = try await ShapeResource.generateConvex(from: mesh)
                        model.components.set(CollisionComponent(shapes: [shape]))
                        print("📦 Convex collision fallback applied to: \(model.name)")
                    } catch {
                        let bounds = model.visualBounds(relativeTo: nil)
                        let size = bounds.max - bounds.min
                        let boxShape = ShapeResource.generateBox(size: size)
                        model.components.set(CollisionComponent(shapes: [boxShape]))
                        print("📦 Box collision fallback applied to: \(model.name)")
                    }
                }

                let trackMaterial = PhysicsMaterialResource.generate(
                    friction: 0.8,
                    restitution: 0.0
                )

                model.components.set(PhysicsBodyComponent(
                    massProperties: .default,
                    material: trackMaterial,
                    mode: .static
                ))
            }
            await applyStaticMeshCollision(to: child)
        }
    }
}
