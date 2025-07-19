//
//  GameController.swift
//  testPlay
//
//  Created by Muhamad Azis on 18/07/25.
//

import SwiftUI
import RealityKit
import Combine

// MARK: - Game State Enum
enum GameState {
    case waiting    // Menunggu player click play
    case countdown  // Countdown 3-2-1
    case playing    // Game sedang berjalan
    case paused     // Game di-pause
    case finished   // Game selesai
}

// MARK: - Power Effect Types
enum PowerEffectType {
    case speedBoost
    case speedReduction
    case none
}

// MARK: - Entity Effect Info
struct EntityEffectInfo {
    var effectType: PowerEffectType = .none
    var timeRemaining: Double = 0.0
    var originalSpeed: Float = 190000.0
}

// MARK: - Finish Info
struct FinishInfo {
    let entityName: String
    let finishTime: Date
    let position: Int
    
    var isPlayer: Bool {
        return entityName.contains("player")
    }
    
    var displayName: String {
        if isPlayer {
            return "🎯 Player"
        } else {
            return "🤖 \(entityName.capitalized)"
        }
    }
}

// MARK: - Multi-Entity Game Controller
class GameController: ObservableObject {
    
    // MARK: - Published Properties
    @Published var gameState: GameState = .waiting
    @Published var countdownNumber: Int = 3
    @Published var isCountdownVisible = false
    @Published var showPlayButton = true
    @Published var canControlPlayer = false
    
    // MARK: - Movement Settings
    @Published var forwardSpeed: Float = 2.0
    @Published var botVariationSpeed: Float = 0.5
    
    // MARK: - Power Effect Properties (Global for UI)
    @Published var currentPowerEffect: PowerEffectType = .none
    @Published var powerEffectTimeRemaining: Double = 0.0
    
    // MARK: - Finish Detection
    @Published var finishedEntities: [FinishInfo] = []
    @Published var showLeaderboard = false
    var gameStartTime: Date?
    private var finishEntity: Entity?
    
    // MARK: - Individual Entity Effects
    private var entityEffects: [String: EntityEffectInfo] = [:]
    private var entityEffectTimers: [String: Timer] = [:]
    private var originalSpeed: Float = 2.0
    
    // MARK: - Entities Collection
    private weak var playerEntity: Entity?
    private var botEntities: [Entity] = []
    private var allMovingEntities: [Entity] = []
    
    // MARK: - Starting Positions Storage
    private var entityStartPositions: [String: SIMD3<Float>] = [:]
    private var entityStartOrientations: [String: simd_quatf] = [:]
    
    // MARK: - Timers
    private var countdownTimer: Timer?
    private var movementTimer: Timer?
    private var botAITimer: Timer?
    private var boundaryCheckTimer: Timer?
    
    // MARK: - Boundary Settings
    private var leftBoundary: Float = -0.5
    private var rightBoundary: Float = 1.8
    
    @Published var countdownDuration: Double = 1.0
    
    var onGameStart: (() -> Void)?
    var onGameEnd: (() -> Void)?
    var onCountdownFinish: (() -> Void)?
    var onReset: (() -> Void)?
    var onPowerEffectApplied: ((PowerEffectType) -> Void)?
    var onPowerEffectEnded: (() -> Void)?
    var onEntityFinished: ((FinishInfo) -> Void)?
    var onAllEntitiesFinished: (([FinishInfo]) -> Void)?
    
    init() {
        originalSpeed = forwardSpeed
    }
    
    // MARK: - Multi-Entity Setup
    func setEntities(player: Entity?, bots: [Entity]) {
        // Clear previous entities
        allMovingEntities.removeAll()
        botEntities.removeAll()
        entityStartPositions.removeAll()
        entityStartOrientations.removeAll()
        entityEffects.removeAll()
        
        // Setup player
        if let player = player {
            self.playerEntity = player
            allMovingEntities.append(player)
            storeStartingState(for: player, name: "player")
            setupEntityPhysics(player)
            entityEffects["player"] = EntityEffectInfo(originalSpeed: originalSpeed)
            print("🎯 Player setup: \(player.name) at \(player.position)")
        }
        
        // Setup bots
        for (index, bot) in bots.enumerated() {
            let botName = "bot_\(index)"
            botEntities.append(bot)
            allMovingEntities.append(bot)
            storeStartingState(for: bot, name: botName)
            setupEntityPhysics(bot)
            entityEffects[botName] = EntityEffectInfo(originalSpeed: originalSpeed)
            print("🤖 Bot \(index + 1) setup: \(bot.name) at \(bot.position)")
        }
        
        print("🎮 GameController setup complete - \(allMovingEntities.count) entities ready")
        
        // Initialize all entities to stopped state
        stopAllMovement()
    }
    
    func setFinishEntity(_ entity: Entity) {
        self.finishEntity = entity
        print("🏁 Finish entity set: \(entity.name)")
    }
    
    func setBoundaries(left: Float, right: Float) {
        leftBoundary = left
        rightBoundary = right
        print("📏 Game boundaries set: Left=\(leftBoundary), Right=\(rightBoundary)")
    }
    
    private func storeStartingState(for entity: Entity, name: String) {
        entityStartPositions[name] = entity.position
        entityStartOrientations[name] = entity.orientation
        print("💾 Stored start state for \(name): \(entity.position)")
    }
    
    private func setupEntityPhysics(_ entity: Entity) {
        // Ensure PhysicsBodyComponent exists and is dynamic
        if entity.components[PhysicsBodyComponent.self] == nil {
            entity.components.set(PhysicsBodyComponent(
                massProperties: .default,
                material: .default,
                mode: .dynamic
            ))
            print("📦 Added PhysicsBodyComponent to: \(entity.name)")
        } else {
            var physicsBody = entity.components[PhysicsBodyComponent.self]!
            physicsBody.mode = .dynamic
            entity.components.set(physicsBody)
        }
        
        // Ensure PhysicsMotionComponent exists
        if entity.components[PhysicsMotionComponent.self] == nil {
            entity.components.set(PhysicsMotionComponent())
            print("🏃 Added PhysicsMotionComponent to: \(entity.name)")
        }
        
        // Initialize with zero velocity
        var motion = entity.components[PhysicsMotionComponent.self]!
        motion.linearVelocity = SIMD3<Float>(0, 0, 0)
        motion.angularVelocity = SIMD3<Float>(0, 0, 0)
        entity.components.set(motion)
    }
    
    // MARK: - Game Control Methods
    func startGame() {
        guard gameState == .waiting else { return }
        
        print("🎯 Starting game with \(allMovingEntities.count) entities...")
        gameState = .countdown
        showPlayButton = false
        canControlPlayer = false
        showLeaderboard = false
        
        // Reset finish detection
        finishedEntities.removeAll()
        gameStartTime = Date()
        
        // Clear all power effects
        clearAllPowerEffects()
        
        // Ensure all movement is stopped during countdown
        stopAllMovement()
        
        startCountdown()
    }
    
    func pauseGame() {
        guard gameState == .playing else { return }
        
        gameState = .paused
        canControlPlayer = false
        
        // Stop all movement
        stopAllMovement()
        
        // Pause all power effect timers
        pauseAllPowerEffectTimers()
        
        print("⏸️ Game paused - all entities stopped")
    }
    
    func resumeGame() {
        guard gameState == .paused else { return }
        
        gameState = .playing
        canControlPlayer = true
        
        // Resume movement
        startAllMovement()
        
        // Resume all power effect timers
        resumeAllPowerEffectTimers()
        
        print("▶️ Game resumed - all entities moving")
    }
    
    func endGame() {
        gameState = .finished
        canControlPlayer = false
        showPlayButton = true
        
        // Stop all movement
        stopAllMovement()
        
        // Clear all power effects
        clearAllPowerEffects()
        
        // Show final leaderboard
        showLeaderboard = true
        
        onGameEnd?()
        
        print("🏁 Game ended - all entities stopped")
    }
    
    func resetGame() {
        print("🔄 Resetting game with \(allMovingEntities.count) entities...")
        
        gameState = .waiting
        countdownNumber = 3
        isCountdownVisible = false
        showPlayButton = true
        canControlPlayer = false
        showLeaderboard = false
        
        stopAllTimers()
        stopAllMovement()
        resetAllEntitiesPositions()
        clearAllPowerEffects()
        finishedEntities.removeAll()
        
        onReset?()
        
        print("🔄 Game reset complete - ready for new game")
    }
    
    // MARK: - Individual Entity Power Effect System
    func applyPowerEffectToEntity(_ entity: Entity, effectType: PowerEffectType, duration: Double = 3.0) {
        guard gameState == .playing else { return }
        
        let entityName = getEntityName(entity)
        
        // Clear any existing effect for this entity
        clearPowerEffectForEntity(entityName)
        
        var effectInfo = entityEffects[entityName] ?? EntityEffectInfo(originalSpeed: originalSpeed)
        effectInfo.effectType = effectType
        effectInfo.timeRemaining = duration
        
        entityEffects[entityName] = effectInfo
        
        // Update global UI if it's the player
        if entity === playerEntity {
            currentPowerEffect = effectType
            powerEffectTimeRemaining = duration
            onPowerEffectApplied?(effectType)
        }
        
        print("💫 \(entityName) got \(effectType) for \(duration)s")
        startPowerEffectTimerForEntity(entityName, duration: duration)
    }
    
    private func getEntityName(_ entity: Entity) -> String {
        if entity === playerEntity {
            return "player"
        } else if let botIndex = botEntities.firstIndex(where: { $0 === entity }) {
            return "bot_\(botIndex)"
        }
        return entity.name
    }
    
    private func startPowerEffectTimerForEntity(_ entityName: String, duration: Double) {
        entityEffectTimers[entityName]?.invalidate()
        entityEffectTimers[entityName] = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.updatePowerEffectTimerForEntity(entityName)
        }
    }
    
    private func updatePowerEffectTimerForEntity(_ entityName: String) {
        guard var effectInfo = entityEffects[entityName] else { return }
        
        effectInfo.timeRemaining -= 0.1
        entityEffects[entityName] = effectInfo
        
        // Update global UI if it's the player
        if entityName == "player" {
            powerEffectTimeRemaining = effectInfo.timeRemaining
        }
        
        if effectInfo.timeRemaining <= 0 {
            clearPowerEffectForEntity(entityName)
        }
    }
    
    private func clearPowerEffectForEntity(_ entityName: String) {
        entityEffectTimers[entityName]?.invalidate()
        entityEffectTimers[entityName] = nil
        
        if var effectInfo = entityEffects[entityName] {
            if effectInfo.effectType != .none {
                effectInfo.effectType = .none
                effectInfo.timeRemaining = 0.0
                entityEffects[entityName] = effectInfo
                
                // Update global UI if it's the player
                if entityName == "player" {
                    currentPowerEffect = .none
                    powerEffectTimeRemaining = 0.0
                    onPowerEffectEnded?()
                }
                
                print("🔄 \(entityName) power effect cleared")
            }
        }
    }
    
    private func pauseAllPowerEffectTimers() {
        for (entityName, _) in entityEffectTimers {
            entityEffectTimers[entityName]?.invalidate()
        }
    }
    
    private func resumeAllPowerEffectTimers() {
        for (entityName, effectInfo) in entityEffects {
            if effectInfo.effectType != .none && effectInfo.timeRemaining > 0 {
                startPowerEffectTimerForEntity(entityName, duration: effectInfo.timeRemaining)
            }
        }
    }
    
    private func clearAllPowerEffects() {
        for entityName in entityEffects.keys {
            clearPowerEffectForEntity(entityName)
        }
        currentPowerEffect = .none
        powerEffectTimeRemaining = 0.0
    }
    
    // MARK: - Finish Detection
    func checkFinish(for entity: Entity) {
        guard gameState == .playing,
              let finishEntity = finishEntity else { return }
        
        let distance = simd_distance(entity.position, finishEntity.position)
        
        if distance < 2.0 { // Threshold distance
            handleEntityFinished(entity)
        }
    }
    
    private func handleEntityFinished(_ entity: Entity) {
        let entityName = getEntityName(entity)
        
        // Check if already finished
        if finishedEntities.contains(where: { $0.entityName == entityName }) {
            return
        }
        
        let finishInfo = FinishInfo(
            entityName: entityName,
            finishTime: Date(),
            position: finishedEntities.count + 1
        )
        
        finishedEntities.append(finishInfo)
        onEntityFinished?(finishInfo)
        
        print("🏁 \(finishInfo.displayName) finished in position \(finishInfo.position)!")
        
        // Check if all entities finished
        if finishedEntities.count >= allMovingEntities.count {
            showLeaderboard = true
            onAllEntitiesFinished?(finishedEntities)
            
            // End game after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.endGame()
            }
        }
    }
    
    // MARK: - Countdown Logic
    private func startCountdown() {
        countdownNumber = 3
        isCountdownVisible = true
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: countdownDuration, repeats: true) { _ in
            self.updateCountdown()
        }
    }
    
    private func updateCountdown() {
        if countdownNumber > 1 {
            countdownNumber -= 1
        } else {
            finishCountdown()
        }
    }
    
    private func finishCountdown() {
        stopCountdownTimer()
        isCountdownVisible = false
        
        // Start actual game
        gameState = .playing
        canControlPlayer = true
        gameStartTime = Date()
        
        // Start movement for all entities
        startAllMovement()
        
        onCountdownFinish?()
        onGameStart?()
        
        print("🚀 Game started - all \(allMovingEntities.count) entities moving!")
    }
    
    private func startAllMovement() {
        startForwardMovementForAllEntities()
        startBotAI()
        startBoundaryCheck()
        print("🏃 All entities movement started")
    }
    
    private func stopAllMovement() {
        stopAllTimers()
        freezeAllEntities()
        print("🛑 All entities movement stopped")
    }
    
    private func startBoundaryCheck() {
        boundaryCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.checkPlayerBoundaries()
            self.checkAllEntitiesFinish()
        }
    }
    
    private func checkPlayerBoundaries() {
        guard gameState == .playing,
              let player = playerEntity else { return }
        
        let currentX = player.position.x
        
        if currentX < leftBoundary {
            player.position.x = leftBoundary
            if var motion = player.components[PhysicsMotionComponent.self] {
                motion.linearVelocity.x = max(0, motion.linearVelocity.x)
                player.components.set(motion)
            }
            print("🚧 Player pushed back from left boundary")
        } else if currentX > rightBoundary {
            player.position.x = rightBoundary
            if var motion = player.components[PhysicsMotionComponent.self] {
                motion.linearVelocity.x = min(0, motion.linearVelocity.x)
                player.components.set(motion)
            }
            print("🚧 Player pushed back from right boundary")
        }
    }
    
    private func checkAllEntitiesFinish() {
        guard gameState == .playing else { return }
        
        for entity in allMovingEntities {
            checkFinish(for: entity)
        }
    }
    
    private func startForwardMovementForAllEntities() {
        movementTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            guard self.gameState == .playing else { return }
            
            for entity in self.allMovingEntities {
                self.applyForwardMovement(to: entity)
            }
        }
    }
    
    private func applyForwardMovement(to entity: Entity) {
        guard var motion = entity.components[PhysicsMotionComponent.self] else { return }
        
        let entityName = getEntityName(entity)
        let effectInfo = entityEffects[entityName] ?? EntityEffectInfo(originalSpeed: originalSpeed)
        
        var entitySpeed = effectInfo.originalSpeed
        
        switch effectInfo.effectType {
        case .speedBoost:
            entitySpeed *= 2.0
        case .speedReduction:
            entitySpeed *= 0.3
        case .none:
            break
        }
        
        // Add bot variation
        if entity !== playerEntity {
            if let botIndex = botEntities.firstIndex(where: { $0 === entity }) {
                let variation = Float(botIndex) * botVariationSpeed * 0.2
                entitySpeed += variation - (botVariationSpeed * 0.5)
            }
        }
        
        motion.linearVelocity.z = -entitySpeed
        motion.linearVelocity.x *= 0.98
        motion.linearVelocity.y *= 0.95
        
        entity.components.set(motion)
    }
    
    private func startBotAI() {
        guard !botEntities.isEmpty else { return }
        
        botAITimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            guard self.gameState == .playing else { return }
            
            for (index, bot) in self.botEntities.enumerated() {
                self.updateBotAI(bot: bot, index: index)
            }
        }
    }
    
    private func updateBotAI(bot: Entity, index: Int) {
        guard var motion = bot.components[PhysicsMotionComponent.self] else { return }
        
        let currentX = bot.position.x
        var targetHorizontalSpeed: Float = 0
        
        let patterns: [Float] = [-1.0, 1.0, -0.5, 0.8]
        let patternIndex = index % patterns.count
        let baseDirection = patterns[patternIndex]
        
        let randomFactor = Float.random(in: 0.5...1.5)
        targetHorizontalSpeed = baseDirection * randomFactor * 0.8
        
        // Respect boundaries
        if currentX <= leftBoundary && targetHorizontalSpeed < 0 {
            targetHorizontalSpeed = abs(targetHorizontalSpeed)
        } else if currentX >= rightBoundary && targetHorizontalSpeed > 0 {
            targetHorizontalSpeed = -abs(targetHorizontalSpeed)
        }
        
        let currentHorizontalSpeed = motion.linearVelocity.x
        let speedDiff = targetHorizontalSpeed - currentHorizontalSpeed
        motion.linearVelocity.x += speedDiff * 0.1
        
        bot.components.set(motion)
    }
    
    private func freezeAllEntities() {
        for entity in allMovingEntities {
            freezeEntity(entity)
        }
    }
    
    private func freezeEntity(_ entity: Entity) {
        guard var motion = entity.components[PhysicsMotionComponent.self] else { return }
        
        motion.linearVelocity = SIMD3<Float>(0, 0, 0)
        motion.angularVelocity = SIMD3<Float>(0, 0, 0)
        entity.components.set(motion)
    }
    
    // MARK: - Player Horizontal Movement Integration
    func applyPlayerHorizontalMovement(_ horizontalVelocity: Float) {
        guard gameState == .playing,
              let player = playerEntity,
              var motion = player.components[PhysicsMotionComponent.self] else { return }
        
        motion.linearVelocity.x = horizontalVelocity
        
        // Get player's current speed (with power effect)
        let playerEffectInfo = entityEffects["player"] ?? EntityEffectInfo(originalSpeed: originalSpeed)
        var playerSpeed = playerEffectInfo.originalSpeed
        
        switch playerEffectInfo.effectType {
        case .speedBoost:
            playerSpeed *= 2.0
        case .speedReduction:
            playerSpeed *= 0.3
        case .none:
            break
        }
        
        motion.linearVelocity.z = -playerSpeed
        player.components.set(motion)
    }
    
    // MARK: - Reset All Entities Positions
    func resetAllEntitiesPositions() {
        if let player = playerEntity {
            resetEntityToStart(entity: player, name: "player")
        }
        
        for (index, bot) in botEntities.enumerated() {
            resetEntityToStart(entity: bot, name: "bot_\(index)")
        }
        
        print("🔄 All \(allMovingEntities.count) entities reset to start positions")
    }
    
    private func resetEntityToStart(entity: Entity, name: String) {
        guard let startPos = entityStartPositions[name],
              let startOrientation = entityStartOrientations[name] else {
            print("❌ No start position stored for \(name)")
            return
        }
        
        entity.position = startPos
        entity.orientation = startOrientation
        
        if var motion = entity.components[PhysicsMotionComponent.self] {
            motion.linearVelocity = SIMD3<Float>(0, 0, 0)
            motion.angularVelocity = SIMD3<Float>(0, 0, 0)
            entity.components.set(motion)
        }
        
        print("🔄 \(name) reset to: \(startPos)")
    }
    
    // MARK: - Manual Controls for Testing
    func forceResetToStart() {
        resetAllEntitiesPositions()
        print("🔧 Force reset all entities to start positions")
    }
    
    func toggleMovement() {
        if gameState == .playing {
            if isMovementActive() {
                stopAllMovement()
            } else {
                startAllMovement()
            }
        }
    }
    
    private func isMovementActive() -> Bool {
        return movementTimer != nil
    }
    
    // MARK: - Timer Management
    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
    
    private func stopMovementTimer() {
        movementTimer?.invalidate()
        movementTimer = nil
    }
    
    private func stopBotAITimer() {
        botAITimer?.invalidate()
        botAITimer = nil
    }
    
    private func stopBoundaryTimer() {
        boundaryCheckTimer?.invalidate()
        boundaryCheckTimer = nil
    }
    
    private func stopAllTimers() {
        stopCountdownTimer()
        stopMovementTimer()
        stopBotAITimer()
        stopBoundaryTimer()
        
        for (entityName, _) in entityEffectTimers {
            entityEffectTimers[entityName]?.invalidate()
        }
        entityEffectTimers.removeAll()
    }
    
    // MARK: - Cleanup
    func cleanup() {
        stopAllTimers()
        stopAllMovement()
        clearAllPowerEffects()
        allMovingEntities.removeAll()
        botEntities.removeAll()
        entityStartPositions.removeAll()
        entityStartOrientations.removeAll()
        entityEffects.removeAll()
        finishedEntities.removeAll()
        print("🧹 GameController cleanup completed")
    }
    
    // MARK: - Debug Info
    func getGameStatus() -> String {
        let movementActive = isMovementActive()
        let powerEffectText = currentPowerEffect == .none ? "None" : "\(currentPowerEffect) (\(String(format: "%.1f", powerEffectTimeRemaining))s)"
        
        return """
        State: \(gameState)
        Entities: \(allMovingEntities.count) total
        Player: \(playerEntity?.name ?? "none")
        Bots: \(botEntities.count)
        Finished: \(finishedEntities.count)
        Movement Active: \(movementActive)
        Power Effect: \(powerEffectText)
        Boundaries: [\(leftBoundary), \(rightBoundary)]
        Can Control Player: \(canControlPlayer)
        """
    }
    
    func getEntityPositions() -> String {
        var positions = "Entity Positions:\n"
        
        if let player = playerEntity {
            let inBounds = player.position.x >= leftBoundary && player.position.x <= rightBoundary
            let effectInfo = entityEffects["player"] ?? EntityEffectInfo()
            let effectText = effectInfo.effectType == .none ? "" : " (\(effectInfo.effectType))"
            positions += "Player: \(String(format: "%.1f", player.position.x)), \(String(format: "%.1f", player.position.z)) \(inBounds ? "✅" : "⚠️")\(effectText)\n"
        }
        
        for (index, bot) in botEntities.enumerated() {
            let inBounds = bot.position.x >= leftBoundary && bot.position.x <= rightBoundary
            let effectInfo = entityEffects["bot_\(index)"] ?? EntityEffectInfo()
            let effectText = effectInfo.effectType == .none ? "" : " (\(effectInfo.effectType))"
            positions += "Bot \(index + 1): \(String(format: "%.1f", bot.position.x)), \(String(format: "%.1f", bot.position.z)) \(inBounds ? "✅" : "⚠️")\(effectText)\n"
        }
        
        return positions
    }
}

// MARK: - UI Components
struct LeaderboardView: View {
    @ObservedObject var gameController: GameController
    
    var body: some View {
        if gameController.showLeaderboard && !gameController.finishedEntities.isEmpty {
            ZStack {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    Text("🏁 RACE RESULTS")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .shadow(radius: 5)
                    
                    VStack(spacing: 8) {
                        ForEach(Array(gameController.finishedEntities.enumerated()), id: \.element.entityName) { index, finishInfo in
                            HStack {
                                // Position medal
                                Text(getPositionEmoji(finishInfo.position))
                                    .font(.title)
                                
                                Text("\(finishInfo.position).")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(width: 30, alignment: .trailing)
                                
                                Text(finishInfo.displayName)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(finishInfo.isPlayer ? .yellow : .white)
                                
                                Spacer()
                                
                                Text(getFinishTimeText(finishInfo))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(finishInfo.isPlayer ? Color.yellow.opacity(0.2) : Color.white.opacity(0.1))
                            )
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.3))
                    )
                    
                    Button("🔄 Play Again") {
                        gameController.resetGame()
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                .padding()
            }
            .transition(.opacity.combined(with: .scale))
            .animation(.easeInOut(duration: 0.5), value: gameController.showLeaderboard)
        }
    }
    
    private func getPositionEmoji(_ position: Int) -> String {
        switch position {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return "🏃"
        }
    }
    
    private func getFinishTimeText(_ finishInfo: FinishInfo) -> String {
        guard let startTime = gameController.gameStartTime else { return "" }
        let duration = finishInfo.finishTime.timeIntervalSince(startTime)
        return String(format: "%.1fs", duration)
    }
}

// MARK: - Enhanced UI Components
struct PlayButtonView: View {
    @ObservedObject var gameController: GameController
    
    var body: some View {
        if gameController.showPlayButton {
            Button(action: {
                gameController.startGame()
            }) {
                HStack {
                    Image(systemName: "play.fill")
                        .font(.title2)
                    Text("START RACE")
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.green, Color.blue]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(25)
                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 3)
            }
            .scaleEffect(gameController.gameState == .waiting ? 1.0 : 0.8)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: gameController.gameState)
        }
    }
}

struct CountdownView: View {
    @ObservedObject var gameController: GameController
    
    var body: some View {
        if gameController.isCountdownVisible {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                VStack {
                    Text("\(gameController.countdownNumber)")
                        .font(.system(size: 120, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                        .scaleEffect(gameController.countdownNumber <= 3 ? 1.2 : 1.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.5), value: gameController.countdownNumber)
                    
                    Text("RACE STARTING!")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.top, 20)
                }
            }
            .transition(.opacity.combined(with: .scale))
            .animation(.easeInOut(duration: 0.3), value: gameController.isCountdownVisible)
        }
    }
}

struct PowerEffectIndicator: View {
    @ObservedObject var gameController: GameController
    
    var body: some View {
        if gameController.currentPowerEffect != .none {
            HStack(spacing: 8) {
                effectIcon
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(effectText)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(effectColor)
                    
                    Text("\(String(format: "%.1f", gameController.powerEffectTimeRemaining))s remaining")
                        .font(.caption)
                        .foregroundColor(effectColor.opacity(0.8))
                }
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(effectColor.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(effectColor, lineWidth: 2)
                    )
            )
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: gameController.currentPowerEffect)
        }
    }
    
    private var effectIcon: some View {
        Group {
            switch gameController.currentPowerEffect {
            case .speedBoost:
                Image(systemName: "bolt.fill")
                    .font(.title)
                    .foregroundColor(.yellow)
            case .speedReduction:
                Image(systemName: "tortoise.fill")
                    .font(.title)
                    .foregroundColor(.orange)
            case .none:
                EmptyView()
            }
        }
    }
    
    private var effectText: String {
        switch gameController.currentPowerEffect {
        case .speedBoost:
            return "SPEED BOOST!"
        case .speedReduction:
            return "SLOWED DOWN!"
        case .none:
            return ""
        }
    }
    
    private var effectColor: Color {
        switch gameController.currentPowerEffect {
        case .speedBoost:
            return .yellow
        case .speedReduction:
            return .orange
        case .none:
            return .clear
        }
    }
}

struct GameControlsView: View {
    @ObservedObject var gameController: GameController
    
    var body: some View {
        HStack(spacing: 16) {
            if gameController.gameState == .playing {
                Button("⏸️ Pause") {
                    gameController.pauseGame()
                }
                .buttonStyle(.bordered)
            } else if gameController.gameState == .paused {
                Button("▶️ Resume") {
                    gameController.resumeGame()
                }
                .buttonStyle(.borderedProminent)
            }
            
            if gameController.gameState != .waiting {
                Button("🔄 Reset Race") {
                    gameController.resetGame()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.orange)
            }
            
            if gameController.gameState == .playing || gameController.gameState == .paused {
                Button("🏁 End Race") {
                    gameController.endGame()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
