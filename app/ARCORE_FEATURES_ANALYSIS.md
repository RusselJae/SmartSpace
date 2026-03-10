# ARCore Scene Viewer Features Analysis

## What's Possible with model-viewer + ARCore Scene Viewer

### ✅ **1. Accurate 3D Model Preparation**

**Model to Life Size:**
- ✅ **YES** - Scene Viewer automatically uses the model's native scale
- ✅ Models should be exported in real-world units (meters)
- ✅ `arScale: ArScale.auto` handles automatic scaling
- ✅ Your pre-scaled models will work correctly

**Optimal Texture Resolution:**
- ✅ **YES** - You control this in your 3D model files
- ✅ Use 2K textures maximum for performance
- ✅ Add visual noise/imperfections in textures (handled in your 3D modeling software)
- ✅ PBR materials work automatically if included in GLB/GLTF files

### ✅ **2. Robust Environmental Interaction**

**Plane Detection and Anchoring:**
- ✅ **YES (Automatic)** - Scene Viewer handles this automatically
- ✅ `arPlacement: ArPlacement.floor` enables floor plane detection
- ✅ Scene Viewer automatically creates anchors when user places the model
- ✅ Objects stay anchored to detected planes
- ⚠️ **LIMITATION**: No programmatic control over plane detection or anchor creation
- ⚠️ **LIMITATION**: Can't detect vertical planes (walls) - only horizontal (floor)

**Depth API:**
- ❌ **NO** - Not available through Scene Viewer
- ❌ Scene Viewer doesn't expose depth occlusion features
- ❌ Virtual objects won't occlude/be occluded by real-world objects
- ⚠️ Requires native ARCore SDK for depth-based occlusion

**Placement Boundaries:**
- ⚠️ **PARTIAL** - Limited control
- ✅ Scene Viewer handles placement distance automatically
- ❌ Can't set maximum placement distance programmatically
- ❌ Can't restrict placement to specific areas

### ⚠️ **3. Enhance Visual Realism and Depth Perception**

**Lighting Estimation:**
- ⚠️ **PARTIAL** - Automatic but limited
- ✅ Scene Viewer automatically estimates lighting from environment
- ✅ Models receive ambient lighting from real environment
- ❌ Can't programmatically control lighting intensity or direction
- ❌ No access to lighting estimation data

**Realistic Shadows:**
- ⚠️ **PARTIAL** - Depends on model
- ✅ Shadows can be baked into the 3D model textures
- ✅ Shadow planes can be included in the GLB/GLTF model
- ❌ Scene Viewer doesn't generate dynamic shadows automatically
- ❌ No real-time shadow casting onto detected planes

**Physically Based Rendering (PBR):**
- ✅ **YES** - Fully supported
- ✅ GLB/GLTF format supports PBR materials
- ✅ Metallic-roughness workflow works automatically
- ✅ Reflections and ambient occlusion work if included in model
- ✅ Scene Viewer renders PBR materials correctly

**User Guidance and Feedback:**
- ✅ **YES** - Can be implemented in Flutter UI
- ✅ Add instructional overlays before AR launch
- ✅ Show hints/guidance text in Flutter widgets
- ✅ Provide visual feedback through dimension panels (already implemented)
- ❌ Can't add overlays inside Scene Viewer itself

---

## Summary: What Works vs. What Doesn't

### ✅ **Works Automatically:**
1. ✅ Life-size model scaling (if models are correctly scaled)
2. ✅ Floor plane detection and anchoring
3. ✅ Automatic lighting estimation
4. ✅ PBR material rendering
5. ✅ Texture quality (depends on your model)

### ⚠️ **Partially Works:**
1. ⚠️ Shadows (must be baked into model, no dynamic shadows)
2. ⚠️ User guidance (can add in Flutter UI, not in Scene Viewer)
3. ⚠️ Placement boundaries (automatic, no programmatic control)

### ❌ **Not Available:**
1. ❌ Depth API / Occlusion
2. ❌ Vertical plane detection (walls)
3. ❌ Programmatic control over anchors
4. ❌ Dynamic shadow casting
5. ❌ Custom placement restrictions
6. ❌ Access to lighting estimation data

---

## Recommendations

### For Best Results with Scene Viewer:

1. **3D Model Preparation:**
   - Export models in real-world scale (meters)
   - Use PBR materials (metallic-roughness workflow)
   - Bake shadows into textures or include shadow planes in model
   - Keep textures at 2K maximum
   - Add visual imperfections to textures

2. **Flutter UI Enhancements:**
   - Add pre-AR instructions/guidance screens
   - Show dimension feedback (already implemented ✅)
   - Provide placement tips before launching AR
   - Add visual indicators for optimal placement distance

3. **Limitations to Accept:**
   - No depth occlusion (furniture won't hide behind real objects)
   - No wall placement (only floor)
   - No programmatic anchor control
   - Shadows must be baked into models

---

## Alternative: Native ARCore SDK

If you need features like:
- Depth API / Occlusion
- Vertical plane detection
- Programmatic anchor control
- Dynamic shadows
- Custom placement boundaries

You would need to use the **native ARCore SDK** (Kotlin/Java) instead of model-viewer, which would require:
- Platform channel implementation
- Native Android code
- More complex setup
- Full control over ARCore features






