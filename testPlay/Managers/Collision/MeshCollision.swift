////
////  MeshCollision.swift
////  testPlay
////
////  Created by Muhamad Azis on 17/07/25.
////
//
//@MainActor
//// Fungsi untuk menerapkan static mesh collision
//func applyStaticMeshCollision(to entity: Entity) async {
//    for child in entity.children {
//        if let model = child as? ModelEntity,
//           let modelComponent = model.components[ModelComponent.self] {
//            
//            let mesh = modelComponent.mesh
//            
//            // Menambahkan task untuk async call
//            do {
//                let collision = try await CollisionComponent(shapes: [.generateStaticMesh(from: mesh)])
//                model.components[CollisionComponent.self] = collision
//                print("✅ Static mesh collision diterapkan pada: \(model.name)")
//            } catch {
//                print("⚠️ Gagal generate static mesh untuk \(model.name): \(error)")
//                
//                // Fallback ke convex hull
//                do {
//                    let shape = try await ShapeResource.generateConvex(from: mesh)
//                    model.components.set(CollisionComponent(shapes: [shape]))
//                    print("📦 Convex collision fallback diterapkan pada: \(model.name)")
//                } catch {
//                    print("⚠️ Gagal generate convex untuk \(model.name): \(error)")
//                    
//                    // Fallback terakhir ke bounding box
//                    let bounds = model.visualBounds(relativeTo: nil)
//                    let size = bounds.max - bounds.min
//                    let boxShape = ShapeResource.generateBox(size: size)
//                    model.components.set(CollisionComponent(shapes: [boxShape]))
//                    print("📦 Box collision fallback diterapkan pada: \(model.name)")
//                }
//            }
//
//            let trackMaterial = PhysicsMaterialResource.generate(
//                friction: 800.0,      // lintasan tidak licin
//                restitution: 0.0
//            )
//
//            model.components.set(PhysicsBodyComponent(
//                massProperties: .default,
//                material: trackMaterial,
//                mode: .static
//            ))
//        }
//        // Recursively apply collision to children
//        await applyStaticMeshCollision(to: child)
//    }
//}
