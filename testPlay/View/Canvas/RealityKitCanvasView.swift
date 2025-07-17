//
//  RealityKitCanvasView.swift
//  tes
//
//  Created by Muhamad Azis on 16/07/25.
//

import SwiftUI
import RealityKit
struct RealityKitCanvasView: View {
    @Binding var placedObjects: [Entity]
    @StateObject private var coordinator = CanvasCoordinator()
    var body: some View {
        RealityView { content in
            setupScene(content: content, coordinator: coordinator)
            loadStaticRoom(content: content, coordinator: coordinator)
        } update: { content in
            updateDynamicObjects(content: content)
        }
    }
    private func setupScene(content: any RealityViewContentProtocol, coordinator: CanvasCoordinator) {
        GridManager.createInfiniteGridFloor(content: content, coordinator: coordinator)
    }
    // FUNGSI 1: Load Room (Static Object - Tidak Bergerak)
    private func loadStaticRoom(content: any RealityViewContentProtocol, coordinator: CanvasCoordinator) {
        Task {
            await loadRoomAsync(content: content, coordinator: coordinator)
        }
    }
    private func loadRoomAsync(content: any RealityViewContentProtocol, coordinator: CanvasCoordinator) async {
        do {
            guard let roomURL = Bundle.main.url(forResource: "sceneFefe", withExtension: "usdz") else {
                print("slide.usdz not found")
                return
            }
            let loadedRoom = try await ModelEntity(contentsOf: roomURL)
            await MainActor.run {
                loadedRoom.name = "Slide_Rumit_Tinggi"
                loadedRoom.generateCollisionShapes(recursive: true)
                loadedRoom.position = SIMD3<Float>(0, -4, 0)
                loadedRoom.scale = SIMD3<Float>(1.0, 1.0, 1.0)
                let roomAnchor = AnchorEntity()
                roomAnchor.addChild(loadedRoom)
                content.add(roomAnchor)
                coordinator.staticObjects.append(loadedRoom)
                print("✅ Static Room loaded successfully at center")
                print("   Position: \(loadedRoom.position)")
            }
        } catch {
            print("❌ Failed to load room.usdz: \(error)")
        }
    }
    private func updateDynamicObjects(content: any RealityViewContentProtocol) {
        for object in placedObjects {
            if object.name.contains("ball_object") {
                content.add(object)
                print("Updated dynamic object: \(object.name) at position: \(object.position)")
            }
        }
    }
}
