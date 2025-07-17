//
//  GridManager.swift
//  tes
//
//  Created by Muhamad Azis on 16/07/25.
//

import Foundation
import RealityKit
import _RealityKit_SwiftUI

class GridManager {
    static func createInfiniteGridFloor(content: any RealityViewContentProtocol, coordinator: CanvasCoordinator) {
        let tileSize: Float = 50.0
        let numTiles = 21
        let offset = Float(numTiles / 2) * tileSize
        
        let gridAnchor = AnchorEntity()
        coordinator.gridAnchor = gridAnchor
        
        for x in 0..<numTiles {
            for z in 0..<numTiles {
                let gridTile = GridManager.createGridTile(size: tileSize)
                gridTile.position = SIMD3<Float>(
                    Float(x) * tileSize - offset,
                    0,
                    Float(z) * tileSize - offset
                )
                gridAnchor.addChild(gridTile)
            }
        }
        
        content.add(gridAnchor)
    }
    
    static func updateGridPosition(coordinator: CanvasCoordinator, cameraPosition: SIMD3<Float>) {
        guard let gridAnchor = coordinator.gridAnchor else { return }
        
        let tileSize: Float = 50.0
        
        let offsetX = round(cameraPosition.x / tileSize) * tileSize
        let offsetZ = round(cameraPosition.z / tileSize) * tileSize
        
        gridAnchor.position = SIMD3<Float>(offsetX, 0, offsetZ)
    }
    
    // Fungsi untuk update grid secara real-time berdasarkan pergerakan pengguna
    static func updateInfiniteGrid(coordinator: CanvasCoordinator, userPosition: SIMD3<Float>) {
        guard let gridAnchor = coordinator.gridAnchor else { return }
        
        let tileSize: Float = 50.0
        let numTiles = 21
        let halfTiles = Float(numTiles / 2)
        
        // Hitung grid center berdasarkan posisi pengguna
        let gridCenterX = round(userPosition.x / tileSize) * tileSize
        let gridCenterZ = round(userPosition.z / tileSize) * tileSize
        
        // Update posisi semua tile untuk mengikuti pengguna
        var tileIndex = 0
        for x in 0..<numTiles {
            for z in 0..<numTiles {
                if tileIndex < gridAnchor.children.count {
                    let tile = gridAnchor.children[tileIndex]
                    
                    let newPosX = gridCenterX + (Float(x) - halfTiles) * tileSize
                    let newPosZ = gridCenterZ + (Float(z) - halfTiles) * tileSize
                    
                    tile.position = SIMD3<Float>(newPosX, 0, newPosZ)
                    tileIndex += 1
                }
            }
        }
    }
    
    private static func createGridTile(size: Float) -> ModelEntity {
        let gridTexture = TextureGenerator.createGrayGridTexture()
        
        guard let textureResource = try? TextureResource(
            image: gridTexture,
            withName: "grayGridTexture",
            options: TextureResource.CreateOptions(semantic: .color)
        ) else {
            fatalError("Failed to create texture resource")
        }
        
        var gridMaterial = UnlitMaterial()
        gridMaterial.color = .init(texture: .init(textureResource))
        gridMaterial.blending = .transparent(opacity: 0.8)
        gridMaterial.faceCulling = .none
        
        let mesh = MeshResource.generatePlane(width: size, depth: size)
        let floor = ModelEntity(mesh: mesh, materials: [gridMaterial])
        floor.name = "GridFloor"
        
        return floor
    }
    
    // Fungsi helper untuk menghitung jarak dan optimasi performa
    static func shouldUpdateGrid(lastUpdatePosition: SIMD3<Float>, currentPosition: SIMD3<Float>, threshold: Float = 25.0) -> Bool {
        let distance = distance(lastUpdatePosition, currentPosition)
        return distance > threshold
    }
}
