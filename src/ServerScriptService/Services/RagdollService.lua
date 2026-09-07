--!strict
-- ModuleScript
-- Location in Studio: ServerScriptService > Services > RagdollService
--
-- Converts a player character from a rigidly-animated rig into a physics ragdoll
-- when called by DamageService on player death.
--
-- What this service does:
--   - Replaces every Motor6D in the character with a BallSocketConstraint so body
--     parts become physics-jointed instead of animation-driven
--   - Sets PlatformStand = true so the Humanoid stops counteracting physics
--   - Sets Humanoid.Health = 0 to trigger Humanoid.Died (TeamService still gets this)
--   - Fires MatchEvents.PlayerDied for services that want a named death signal
--   - Fires RagdollApplied to all clients so the dying player's client can show the
--     death experience (DeathScreen fade, blur, audio muffle)
--
-- What this service does NOT do:
--   - Destroy the character  →  CorpseService (future) owns character cleanup
--   - Track team or alive state  →  TeamService handles that via Humanoid.Died
--   - Apply damage or validate hits  →  DamageService and GunService own that

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- Dependencies
-- ============================================================

local Modules  = ReplicatedStorage:WaitForChild("Modules")
local Logger   = require(Modules:WaitForChild("Logger"))

local MatchEvents = require(script.Parent:WaitForChild("MatchEvents"))

local Remotes        = ReplicatedStorage:WaitForChild("Remotes")
local RagdollApplied = Remotes:WaitForChild("RagdollApplied") :: RemoteEvent

-- ============================================================
-- Private helpers
-- ============================================================

-- Converts one Motor6D into a BallSocketConstraint so the joint becomes
-- physics-driven instead of animation-driven. The Motor6D is disabled but kept
-- in the hierarchy so CorpseService can restore the rig if needed later.
local function convertJoint(motor: Motor6D)
    local part0 = motor.Part0
    local part1 = motor.Part1
    if part0 == nil or part1 == nil then
        Logger.warn("[RagdollService] Motor6D has nil Part0 or Part1 — skipping:", motor:GetFullName())
        return
    end

    local att0 = Instance.new("Attachment")
    att0.Name   = "RagdollAtt0_" .. motor.Name
    att0.CFrame = motor.C0
    att0.Parent = part0

    local att1 = Instance.new("Attachment")
    att1.Name   = "RagdollAtt1_" .. motor.Name
    att1.CFrame = motor.C1
    att1.Parent = part1

    local bsc          = Instance.new("BallSocketConstraint")
    bsc.Name           = "RagdollBSC_" .. motor.Name
    bsc.Attachment0    = att0
    bsc.Attachment1    = att1
    bsc.LimitsEnabled  = true   -- prevent full 360° spin; keeps the ragdoll visually plausible
    bsc.UpperAngle     = 45     -- maximum swing angle (degrees) from the rest orientation
    bsc.Parent         = part0

    motor.Enabled = false
end

-- ============================================================
-- Public API
-- ============================================================

local RagdollService = {}

-- Called by DamageService when a player's health drops to 0.
-- `character` is the Model in Workspace. `victim` is the Player. `attacker` is
-- the killing Player, or nil for environment/hazard deaths.
function RagdollService:Apply(character: Model, victim: Player, attacker: Player?)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid == nil then
        Logger.warn("[RagdollService] No Humanoid in character for", victim.Name, "— cannot ragdoll")
        return
    end

    -- ── Convert all Motor6Ds to physics joints ──────────────────────────────────
    local motorCount = 0
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("Motor6D") then
            convertJoint(descendant :: Motor6D)
            motorCount += 1
        end
    end

    if motorCount == 0 then
        Logger.warn("[RagdollService] No Motor6Ds found in character for", victim.Name,
            "— ragdoll will not work; character rig may be non-standard")
    else
        Logger.debug("[RagdollService] Converted", motorCount, "Motor6Ds for", victim.Name)
    end

    -- ── Kill the Humanoid ────────────────────────────────────────────────────────
    -- PlatformStand = true stops the Humanoid from fighting the new physics joints.
    -- Setting Health = 0 fires Humanoid.Died which TeamService listens to for
    -- alive-count tracking and round-end detection. Both steps together produce
    -- a clean physics ragdoll with no animation interference.
    humanoid.PlatformStand = true
    humanoid.Health        = 0   -- fires Humanoid.Died → TeamService.handlePlayerDied

    -- ── Notify listeners ─────────────────────────────────────────────────────────
    local killerName = if attacker ~= nil then attacker.DisplayName else ""

    -- MatchEvents.PlayerDied: server-side signal for future consumers (RewardService,
    -- CorpseService) that want a named death event without relying on Humanoid.Died.
    MatchEvents.PlayerDied:Fire(victim, killerName)

    -- RagdollApplied: tells every client a player just died.
    -- DeathScreen on the dying player's client checks UserId and triggers the
    -- full death experience (fade, blur, audio muffle).
    RagdollApplied:FireAllClients(victim.UserId, killerName)

    Logger.debug("[RagdollService] Ragdoll applied to", victim.Name, "| killer:", killerName)
end

return RagdollService
