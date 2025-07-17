//
//  ContentView.swift
//  tes
//
//  Created by Muhamad Azis on 16/07/25.
//

import SwiftUI
import RealityKit

struct ContentView: View {
    @State private var placedObjects: [Entity] = []
    @State private var ballObjectEntity: ModelEntity?
    @State private var isLoaded = false
    @State private var loadingError: String?
    @State private var cameraMode: CameraMode = .orbit
    @State private var moveTimer: Timer?
    @State private var ballPosition: SIMD3<Float> = SIMD3<Float>(0, 0, -2)
    
    private let moveInterval: TimeInterval = 0.016
    private let forwardSpeed: Float = 0.02
    private let sideSpeed: Float = 0.05
    private let maxSideDistance: Float = 3.0
    
    enum CameraMode: String, CaseIterable {
        case dolly = "Dolly"
        case orbit = "Orbit"
        case pan = "Pan"
        case tilt = "Tilt"
        case none = "None"
    }
    
    var body: some View {
        VStack {
            RealityKitCanvasView(placedObjects: $placedObjects)
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    loadBallObject()
                }
                .realityViewCameraControls(getCameraControl())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if cameraMode == .none {
                                handleBallMovement(translation: value.translation)
                            }
                        }
                )
            
            VStack(spacing: 16) {
                HStack {
                    Text("Camera Mode:")
                        .font(.headline)
                    
                    Picker("Camera Mode", selection: $cameraMode) {
                        ForEach(CameraMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: cameraMode) { oldValue, newValue in
                        handleCameraModeChange(newValue)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding()
        }
    }
    
    func loadBallObject() {
        print("=== Loading Ball Object ===")
        Task {
            await loadBallAsync()
        }
    }
    
    func loadBallAsync() async {
        do {
            guard let ballURL = Bundle.main.url(forResource: "Kursi", withExtension: "usdz") else {
                print("Ball.usdz not found, creating fallback ball")
                return
            }
            
            print("✅ Found ball file at: \(ballURL.path)")
            let ballModel = try await ModelEntity(contentsOf: ballURL)
            
            await MainActor.run {
                ballModel.name = "ball_object_main"
                ballModel.generateCollisionShapes(recursive: true)
                
                ballPosition = SIMD3<Float>(0, 0.8, -2)
                ballModel.position = ballPosition
                ballModel.scale = SIMD3<Float>(1.5, 1.5, 1.5)
                
                applyBallMaterial(ballModel, color: .orange)
                
                ballObjectEntity = ballModel
                placedObjects.removeAll()
                placedObjects.append(ballModel)
                
                isLoaded = true
                loadingError = nil
                
                startIdleMovement()
                
                print("✅ Ball Object loaded successfully")
                print("   Position: \(ballModel.position)")
                print("   Scale: \(ballModel.scale)")
            }
        } catch {
            await MainActor.run {
                loadingError = "Failed to load ball object: \(error.localizedDescription)"
            }
            print("❌ Failed to load ball.usdz: \(error)")
        }
    }
    
    func applyBallMaterial(_ ball: Entity, color: UIColor) {
        guard let modelEntity = ball as? ModelEntity else { return }
        
        var material = SimpleMaterial()
        material.color = .init(tint: color.withAlphaComponent(0.9))
        material.metallic = 0.3
        material.roughness = 0.4
        
        if let model = modelEntity.model {
            let materialCount = max(1, model.mesh.expectedMaterialCount)
            modelEntity.model?.materials = Array(repeating: material, count: materialCount)
        }
    }
    
    func startIdleMovement() {
        moveTimer?.invalidate()
        moveTimer = Timer.scheduledTimer(withTimeInterval: moveInterval, repeats: true) { _ in
            moveBallForward()
        }
    }
    
    func stopIdleMovement() {
        moveTimer?.invalidate()
        moveTimer = nil
    }
    
    func moveBallForward() {
        if let mainBall = placedObjects.first(where: { $0.name.contains("ball_object") }) {
            mainBall.position.z -= forwardSpeed
            
            if mainBall.position.z < -10.0 {
                mainBall.position.z = 2.0
            }
            
            ballPosition = mainBall.position
            
            if let ballEntity = mainBall as? ModelEntity {
                ballObjectEntity = ballEntity
            }
        }
    }
    
    // MOVEMENT CONTROLS - Hanya aktif ketika camera mode = none
    func handleBallMovement(translation: CGSize) {
        guard cameraMode == .none else { return }
        
        let sensitivity: Float = 0.01
        let deltaX = Float(translation.width) * sensitivity
        
        moveBallSideways(deltaX)
    }
    
    func moveBallSideways(_ deltaX: Float) {
        if let mainBall = placedObjects.first(where: { $0.name.contains("ball_object") }) {
            let newX = mainBall.position.x + deltaX
            mainBall.position.x = max(-maxSideDistance, min(maxSideDistance, newX))
            
            ballPosition.x = mainBall.position.x
            
            if let ballEntity = mainBall as? ModelEntity {
                ballObjectEntity = ballEntity
            }
            
            print("Ball moved to X: \(mainBall.position.x)")
        }
    }
    
    func resetBallPosition() {
        if let mainBall = placedObjects.first(where: { $0.name.contains("ball_object") }) {
            ballPosition = SIMD3<Float>(0, 0.7, -2)
            mainBall.position = ballPosition
            
            if let ballEntity = mainBall as? ModelEntity {
                ballObjectEntity = ballEntity
            }
            
            print("Ball position reset to center")
        }
    }
    
    func handleCameraModeChange(_ newMode: CameraMode) {
        if newMode == .none {
            print("🎮 Ball movement enabled - Use drag gesture or buttons to move left/right")
        } else {
            print("📷 Camera mode active - Ball movement disabled")
        }
    }
    
    private func getCameraControl() -> CameraControls {
        switch cameraMode {
        case .dolly:
            return .dolly
        case .orbit:
            return .orbit
        case .pan:
            return .pan
        case .tilt:
            return .tilt
        case .none:
            return .none
        }
    }
}
