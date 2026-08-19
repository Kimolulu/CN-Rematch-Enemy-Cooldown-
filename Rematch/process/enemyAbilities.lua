local _, rematch = ...

-- Rematch Enemy Ability Bar
-- WoW 12.1 compatibility module.
-- Shows the active enemy pet's abilities and manually tracks enemy PvE cooldowns.
-- Includes an in-game configuration window. Open it with: /reab

rematch.enemyAbilityBar = rematch.enemyAbilityBar or {}
local module = rematch.enemyAbilityBar

local ENEMY = Enum.BattlePetOwner.Enemy
local abilityButtons = {}
local casts = {}
local currentRound = 0
local bar
local configFrame
local eventFrame = CreateFrame("Frame")

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

local function getSettings()
    return {
        iconSize = rematch.settings.EnemyAbilityIconSize or 42,
        spacing = rematch.settings.EnemyAbilitySpacing or 6,

        cooldownFontObject = rematch.settings.EnemyAbilityCooldownFont or "GameFontNormalSmall",
        cooldownFontSize = rematch.settings.EnemyAbilityCooldownFontSize or 12,
        cooldownX = rematch.settings.EnemyAbilityCooldownX or 0,
        cooldownY = rematch.settings.EnemyAbilityCooldownY or 0,

        remainingFontObject = "GameFontNormalLarge",
        remainingFontSize = rematch.settings.EnemyAbilityRemainingFontSize or 16,

        barX = 0,
        barY = 28,
    }
end

local fontChoices = {
    {name="Friz Quadrata", object="GameFontNormalSmall"},
    {name="Friz Quadrata Large", object="GameFontNormalLarge"},
    {name="Number Font", object="NumberFontNormal"},
    {name="Number Font Large", object="NumberFontNormalLarge"},
}

local function getFontChoiceName(object)
    for _, info in ipairs(fontChoices) do
        if info.object == object then
            return info.name
        end
    end
    return object or "Default"
end

local function applyFont(fontString, fontObjectName, size)
    local fontObject = _G[fontObjectName] or GameFontNormalSmall
    fontString:SetFontObject(fontObject)

    local font = fontString:GetFont()
    if font then
        fontString:SetFont(font, size, "OUTLINE")
    end

    fontString:SetTextColor(1, 1, 1, 1)
    fontString:SetShadowColor(0, 0, 0, 1)
    fontString:SetShadowOffset(0, 0)
end

-- ---------------------------------------------------------------------------
-- Battle/cooldown state
-- ---------------------------------------------------------------------------

local function ensurePetTable(index)
    if not casts[index] then
        casts[index] = {}
    end
    return casts[index]
end

local function resetBattle()
    wipe(casts)
    currentRound = 0
end

local function getRemainingCooldown(enemyIndex, slot, abilityID, baseCooldown)
    local petCasts = casts[enemyIndex]
    local cast = petCasts and petCasts[slot]

    if not cast or cast.id ~= abilityID then
        return 0
    end

    local remaining = (baseCooldown or 0) + cast.turn - currentRound
    return max(0, remaining)
end


-- ---------------------------------------------------------------------------
-- Minimal FUI visual layer
-- ---------------------------------------------------------------------------

local function styleZZZButton(button)
    if button.__minimalFUIStyled then return end
    button.__minimalFUIStyled = true

    -- Keep the icon completely clean: no custom border, no corner accents,
    -- no mask overlay and no blue decorative line.
    button.CooldownText:ClearAllPoints()
    local db = getSettings()
    button.CooldownText:SetPoint("CENTER", db.cooldownX, db.cooldownY)
    button.CooldownText:SetJustifyH("CENTER")
    button.CooldownText:SetJustifyV("MIDDLE")
end

local function setFUIState(button, remaining, baseCooldown)
    styleZZZButton(button)

    if remaining and remaining > 0 then
        -- Cooldown: icon becomes gray and the countdown remains centered.
        button.Icon:SetDesaturated(true)
        button.CooldownText:SetText(tostring(math.ceil(remaining)))
        button.CooldownText:Show()
    else
        -- Ready: clean icon, no READY label and no decorative border.
        button.Icon:SetDesaturated(false)
        button.CooldownText:SetText("")
        button.CooldownText:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Ability buttons / bar
-- ---------------------------------------------------------------------------

local function createAbilityButton(parent, index)
    local db = getSettings()

    local button = CreateFrame("Button", nil, parent)
    button:SetSize(db.iconSize, db.iconSize)
    button.abilitySlot = index

    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetAllPoints()
    button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Rounded-square mask. Keep exactly one mask on the icon.
    button.IconMask = button:CreateMaskTexture()
    button.IconMask:SetAllPoints(button.Icon)
    button.IconMask:SetTexture(
        "Interface\\AddOns\\Rematch\\textures\\enemyAbilityMask",
        "CLAMPTOBLACKADDITIVE",
        "CLAMPTOBLACKADDITIVE"
    )
    button.Icon:AddMaskTexture(button.IconMask)

    button.CooldownText = button:CreateFontString(nil, "OVERLAY")
    local initialSettings = getSettings()
    button.CooldownText:SetPoint("CENTER", initialSettings.cooldownX, initialSettings.cooldownY)
    applyFont(button.CooldownText, db.remainingFontObject, db.remainingFontSize)

    button.MaxCooldownText = button:CreateFontString(nil, "OVERLAY")
    button.MaxCooldownText:SetPoint("TOPRIGHT", 0, 0)
    applyFont(button.MaxCooldownText, db.cooldownFontObject, db.cooldownFontSize)

    -- Blizzard-native pet battle attribute relationship indicators.
    -- Strong and Weak are mutually exclusive and appear only when the
    -- ability's pet type has a non-neutral modifier against the active pet.
    button.StrongIcon = button:CreateTexture(nil, "OVERLAY", nil, 7)
    button.StrongIcon:SetSize(16, 16)
    button.StrongIcon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    button.WeakIcon = button:CreateTexture(nil, "OVERLAY", nil, 7)
    button.WeakIcon:SetSize(16, 16)
    button.WeakIcon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    -- Use the same concrete Blizzard textures Rematch's own ability tooltip uses.
    -- Do not rely on atlas names here: those atlas names are not present on all clients.
    button.StrongIcon:SetTexture("Interface\\PetBattles\\BattleBar-AbilityBadge-Strong")
    button.WeakIcon:SetTexture("Interface\\PetBattles\\BattleBar-AbilityBadge-Weak")
    button.StrongIcon:Hide()
    button.WeakIcon:Hide()

    styleZZZButton(button)

    button:SetScript("OnEnter", function(self)
        if not self.abilityID then
            return
        end

        local enemyIndex = C_PetBattles.GetActivePet(ENEMY)
        if enemyIndex and enemyIndex > 0
            and PetBattleAbilityTooltip_SetAbility
            and PetBattleAbilityTooltip_Show
            and PetBattlePrimaryAbilityTooltip then

            PetBattleAbilityTooltip_SetAbility(ENEMY, enemyIndex, self.abilitySlot)
            PetBattleAbilityTooltip_Show("TOPLEFT", self, "TOPRIGHT", 8, 0)
            return
        end

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.abilityName or ("Ability "..self.abilityID), 1, 1, 1)

        if self.description and self.description ~= "" then
            GameTooltip:AddLine(self.description, nil, nil, nil, true)
        end

        if self.baseCooldown and self.baseCooldown > 0 then
            GameTooltip:AddLine("Cooldown: "..self.baseCooldown.." rounds", 1, 0.82, 0)
        end

        if self.remaining and self.remaining > 0 then
            GameTooltip:AddLine("Remaining: "..self.remaining.." rounds", 1, 0.25, 0.25)
        end

        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        if PetBattlePrimaryAbilityTooltip then
            PetBattlePrimaryAbilityTooltip:Hide()
        end
        GameTooltip:Hide()
    end)

    return button
end

local function applyLayout()
    if not bar then
        return
    end

    local db = getSettings()

    for i = 1, 3 do
        local button = abilityButtons[i]
        button:SetSize(db.iconSize, db.iconSize)

        button:ClearAllPoints()
        if i == 1 then
            button:SetPoint("LEFT", bar, "LEFT", 0, 0)
        else
            button:SetPoint("LEFT", abilityButtons[i-1], "RIGHT", db.spacing, 0)
        end

        button.MaxCooldownText:ClearAllPoints()
        button.MaxCooldownText:SetPoint("TOPRIGHT", 0, 0)

        applyFont(button.MaxCooldownText, db.cooldownFontObject, db.cooldownFontSize)
        applyFont(button.CooldownText, db.remainingFontObject, db.remainingFontSize)
        styleZZZButton(button)
        button.CooldownText:ClearAllPoints()
        button.CooldownText:SetPoint("CENTER", db.cooldownX, db.cooldownY)
        button.CooldownText:SetTextColor(0.88, 0.97, 1, 1)
    end

    local width = db.iconSize * 3 + db.spacing * 2
    bar:SetSize(width, db.iconSize)

    bar:ClearAllPoints()
    if PetBattleFrame and PetBattleFrame.BottomFrame then
        bar:SetPoint("BOTTOM", PetBattleFrame.BottomFrame, "TOP", db.barX, db.barY)
    else
        bar:SetPoint("CENTER", UIParent, "CENTER", db.barX, -160 + db.barY)
    end
end

local updateBar

local function ensureBar()
    if bar then
        return
    end

    bar = CreateFrame("Frame", "RematchEnemyAbilityBar", UIParent)
    bar:SetFrameStrata("HIGH")
    bar:SetClampedToScreen(true)

    -- Pet-selection visibility can change without a convenient addon event.
    -- Poll very lightly so the ability bar disappears/reappears immediately.
    bar.selectionPoll = 0
    bar.wasPetSelectShown = false
    bar:SetScript("OnUpdate", function(self, elapsed)
        self.selectionPoll = self.selectionPoll + elapsed
        if self.selectionPoll < 0.05 then
            return
        end
        self.selectionPoll = 0

        if not C_PetBattles.IsInBattle() then
            return
        end

        local shown = C_PetBattles.ShouldShowPetSelect
            and C_PetBattles.ShouldShowPetSelect()
            or false

        if shown ~= self.wasPetSelectShown then
            self.wasPetSelectShown = shown
            if shown then
                self:Hide()
            else
                updateBar()
            end
        end
    end)

    for i = 1, 3 do
        abilityButtons[i] = createAbilityButton(bar, i)
    end

    applyLayout()
    bar:Hide()
end

updateBar = function()
    ensureBar()

    if not C_PetBattles.IsInBattle() then
        bar:Hide()
        return
    end

    -- Hide the enemy ability bar while Blizzard's pet-selection UI is open.
    -- This prevents overlap with the choose-a-pet menu during swaps/deaths.
    if C_PetBattles.ShouldShowPetSelect and C_PetBattles.ShouldShowPetSelect() then
        bar:Hide()
        return
    end

    local enemyIndex = C_PetBattles.GetActivePet(ENEMY)
    if not enemyIndex or enemyIndex == 0 then
        bar:Hide()
        return
    end

    local hasAbility = false

    for slot = 1, 3 do
        local button = abilityButtons[slot]
        local abilityID, name, icon, baseCooldown, description, numTurns, abilityPetType =
            C_PetBattles.GetAbilityInfo(ENEMY, enemyIndex, slot)

        if abilityID then
            hasAbility = true

            local remaining = getRemainingCooldown(enemyIndex, slot, abilityID, baseCooldown)

            button.abilityID = abilityID
            button.abilityName = name
            button.description = description
            button.baseCooldown = baseCooldown or 0
            button.remaining = remaining

            -- Attribute relationship: use Blizzard's combat modifier directly.
            -- >1 = Strong, <1 = Weak, ==1 = neutral/no icon.
            local playerIndex = C_PetBattles.GetActivePet(Enum.BattlePetOwner.Ally)
            local playerPetType = playerIndex and playerIndex > 0
                and C_PetBattles.GetPetType(Enum.BattlePetOwner.Ally, playerIndex)
                or nil
            local attackModifier = abilityPetType and playerPetType
                and C_PetBattles.GetAttackModifier(abilityPetType, playerPetType)
                or 1

            button.abilityPetType = abilityPetType
            button.attackModifier = attackModifier or 1
            if button.StrongIcon then
                button.StrongIcon:SetShown((attackModifier or 1) > 1)
            end
            if button.WeakIcon then
                button.WeakIcon:SetShown((attackModifier or 1) < 1)
            end

            setFUIState(button, remaining, baseCooldown or 0)

            button.Icon:SetTexture(icon)
            button.Icon:SetDesaturated(remaining > 0)

            if remaining > 0 then
                button.CooldownText:SetText(remaining)
                button.CooldownText:Show()
            else
                button.CooldownText:SetText("")
                button.CooldownText:Hide()
            end

            button.MaxCooldownText:SetText("")
            button.MaxCooldownText:Hide()

            button:Show()
        else
            button.abilityID = nil
            if button.StrongIcon then
                button.StrongIcon:Hide()
            end
            if button.WeakIcon then
                button.WeakIcon:Hide()
            end
            button:Hide()
        end
    end

    bar:SetShown(hasAbility)
end

-- ---------------------------------------------------------------------------
-- Combat log tracking
-- ---------------------------------------------------------------------------

local function processCombatLog(message)
    if not message or issecretvalue(message) then
        return
    end

    if PET_BATTLE_COMBAT_LOG_NEW_ROUND then
        local pattern = PET_BATTLE_COMBAT_LOG_NEW_ROUND:gsub("%%d", "(%%d+)")
        local round = message:match(pattern)
        if round then
            currentRound = tonumber(round) or currentRound
            updateBar()
            return
        end
    end

    local abilityID = tonumber(message:match("|HbattlePetAbil:(%d+)"))
    if not abilityID then
        return
    end

    local enemyIndex = C_PetBattles.GetActivePet(ENEMY)
    if not enemyIndex or enemyIndex == 0 then
        return
    end

    -- Do not classify by "attack/heal" text. Defensive, buff, armor and utility
    -- abilities are valid enemy casts too. Instead, match the logged ability ID
    -- against the currently active enemy pet's actual ability slots.
    for slot = 1, 3 do
        local id = C_PetBattles.GetAbilityInfo(ENEMY, enemyIndex, slot)
        if id == abilityID then
            local petCasts = ensurePetTable(enemyIndex)
            petCasts[slot] = {
                id = abilityID,
                turn = currentRound,
            }
            updateBar()
            return
        end
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

eventFrame:RegisterEvent("PET_BATTLE_OPENING_START")
eventFrame:RegisterEvent("PET_BATTLE_PET_CHANGED")
eventFrame:RegisterEvent("PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE")
eventFrame:RegisterEvent("PET_BATTLE_CLOSE")
eventFrame:RegisterEvent("CHAT_MSG_PET_BATTLE_COMBAT_LOG")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PET_BATTLE_OPENING_START" then
        resetBattle()
        C_Timer.After(0, function()
            applyLayout()
            updateBar()
        end)

    elseif event == "PET_BATTLE_CLOSE" then
        resetBattle()
        if bar then
            bar:Hide()
        end

    elseif event == "CHAT_MSG_PET_BATTLE_COMBAT_LOG" then
        processCombatLog(...)

    elseif event == "PET_BATTLE_PET_CHANGED" or event == "PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE" then
        updateBar()
    end
end)

function module:ApplySettings()
    applyLayout()
    updateBar()
end

module.Update = updateBar
module.Reset = resetBattle
module.ApplyLayout = applyLayout
