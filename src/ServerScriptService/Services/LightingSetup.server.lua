--!strict
-- Script
-- Location in Studio: ServerScriptService > Services > LightingSetup
--
-- Applies the game's lighting profile and post-processing effects once on server start.
-- Changes to game.Lighting from a server Script replicate to all clients automatically,
-- so no client-side counterpart is needed.
--
-- Style: gritty overcast urban — deep blacks, cold desaturated palette, heavy atmospheric
-- haze, warm artificial-light bloom.  Reference: Criminality (old build).
--
-- Tuning guide:
--   Ambient / OutdoorAmbient   → how dark the un-lit areas are (lower = deeper blacks)
--   ExposureCompensation       → overall scene exposure (negative = darker)
--   ColorCorrection.Saturation → desaturation level (0 = full colour, -1 = greyscale)
--   ColorCorrection.Contrast   → shadow/highlight separation (higher = punchier)
--   Atmosphere.Density         → how quickly the sky/fog overtakes distant geometry
--   Bloom.Threshold            → minimum luminance for bloom (high = only lamps bloom)

local Lighting = game:GetService("Lighting")

-- ── Core Lighting properties ──────────────────────────────────────────────────────────────
-- Future technology: physically-based shadows, screen-space ambient occlusion,
-- accurate point-light falloff.  Must be set before child effects are created.
Lighting.Technology           = Enum.Technology.Future
Lighting.GlobalShadows        = true
Lighting.ShadowSoftness       = 0.12          -- crisp shadow edges (lower = harder)

-- Exposure & colour
Lighting.Brightness           = 0.28          -- sun brightness; low sun = overcast feel
Lighting.ExposureCompensation = -0.40         -- pulls everything darker

-- Ambient: what colour unlit surfaces receive.  Deep cold blue-black.
Lighting.Ambient              = Color3.fromRGB(14, 17, 25)
Lighting.OutdoorAmbient       = Color3.fromRGB(20, 23, 34)

-- Colour shifts on the indirect lighting (bottom = ground bounce, top = sky light).
Lighting.ColorShift_Bottom    = Color3.fromRGB(8, 10, 18)
Lighting.ColorShift_Top       = Color3.fromRGB(16, 19, 30)

-- Clock position: ~15:30 gives a low sun angle; Atmosphere density kills most direct light.
Lighting.TimeOfDay            = "15:30:00"
Lighting.GeographicLatitude   = 41.88          -- roughly Chicago

-- Environment scales: how much the sky/environment contributes to surface lighting.
-- EnvironmentDiffuseScale: cold grey sky bleeds onto diffuse surfaces (dark, overcast feel).
-- EnvironmentSpecularScale: metal and smooth surfaces catch the environment colour —
--   gives wet-pavement and gun-metal the reflective quality visible in the reference shots.
Lighting.EnvironmentDiffuseScale  = 0.4
Lighting.EnvironmentSpecularScale = 0.6

-- Legacy fog: disabled in favour of the Atmosphere effect below.
Lighting.FogEnd               = 100000

-- ── Helper: create a child effect, set properties, parent to Lighting ─────────────────────
local function makeEffect(className: string, props: { [string]: any }): Instance
    local e = Instance.new(className)
    for k, v in props do
        (e :: any)[k] = v
    end
    e.Parent = Lighting
    return e
end

-- Remove any effects that existed before this script ran (idempotent in Studio).
for _, child in Lighting:GetChildren() do
    if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
        child:Destroy()
    end
end

-- ── Atmosphere ────────────────────────────────────────────────────────────────────────────
-- Dense overcast haze softens the horizon, kills sky glow, limits sightlines.
-- High Haze makes the sky a flat cold grey; zero Glare removes sun disk entirely.
makeEffect("Atmosphere", {
    Density = 0.68,                            -- 0–1; higher = fog sets in closer
    Offset  = 0.07,                            -- slight vertical offset for horizon scattering
    Color   = Color3.fromRGB(94, 104, 126),    -- cold grey-blue haze colour
    Decay   = Color3.fromRGB(55, 65, 85),      -- colour the atmosphere fades to at zenith
    Glare   = 0,                               -- no sun glare — fully overcast
    Haze    = 2.8,                             -- high haze = flat grey sky
})

-- ── ColorCorrectionEffect ────────────────────────────────────────────────────────────────
-- Desaturation + contrast lift + cold tint = the core of the Criminality palette.
-- TintColor shifts whites toward pale blue-grey (not pure white).
makeEffect("ColorCorrectionEffect", {
    Enabled    = true,
    Brightness = -0.06,                        -- slight darkening on top of ExposureCompensation
    Contrast   = 0.45,                         -- punchy blacks / bright highlights
    Saturation = -0.50,                        -- half-desaturated; colours still readable
    TintColor  = Color3.fromRGB(195, 210, 255),-- cold blue-white tint
})

-- ── BloomEffect ───────────────────────────────────────────────────────────────────────────
-- High Threshold ensures only artificial lights (street lamps, neon, muzzle flash) bloom.
-- Ambient surfaces stay sharp; halos appear only on genuine light sources.
makeEffect("BloomEffect", {
    Enabled   = true,
    Intensity = 0.45,
    Size      = 24,
    Threshold = 0.93,                          -- ~94% brightness before any glow appears
})

-- ── SunRaysEffect ─────────────────────────────────────────────────────────────────────────
-- Disabled — an overcast sky has no visible sun rays.
makeEffect("SunRaysEffect", {
    Enabled   = false,
    Intensity = 0,
    Spread    = 0.5,
})

-- ── DepthOfFieldEffect ────────────────────────────────────────────────────────────────────
-- Near-field is always sharp so the viewmodel and close enemies are crisp.
-- Subtle far-blur thickens atmospheric depth without obscuring targets.
makeEffect("DepthOfFieldEffect", {
    Enabled        = true,
    NearIntensity  = 0,
    FarIntensity   = 0.28,
    FocusDistance  = 52,
    InFocusRadius  = 40,
})
