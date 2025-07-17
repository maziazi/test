//
//  CanvasCoordinator.swift
//  tes
//
//  Created by Muhamad Azis on 16/07/25.
//

import RealityKit
import UIKit
import ARKit

class CanvasCoordinator: ObservableObject {
    var selectedEntity: ModelEntity?
    var selectionIndicator: Entity?
    var cameraEntity: PerspectiveCamera?
    var cameraAnchor: AnchorEntity?
    var gridAnchor: AnchorEntity?
    var canvasCenter = SIMD3<Float>(0, 0, 0)
    var staticObjects: [Entity] = []
    var dynamicObjects: [Entity] = []
    var addAttempts: Int = 0
        
    var allObjects: [Entity] {
        return staticObjects + dynamicObjects
    }
        
    init() {
            // Inisialisasi tanpa parameter
    }
}
