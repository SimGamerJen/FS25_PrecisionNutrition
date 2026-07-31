PN_UI = PN_UI or { visible=false, selected=1, page=1, dialog=nil, dialogOpen=false }

local PNNutritionDialog = {}
local PNNutritionDialog_mt = ScreenElement ~= nil and Class(PNNutritionDialog, ScreenElement) or nil

local function percent(value)
    return string.format("%d%%", math.floor(math.clamp(tonumber(value) or 0, 0, 1) * 100 + 0.5))
end

local function developmentPercent(weight, targetWeight)
    targetWeight = tonumber(targetWeight) or 0
    local ratio = targetWeight > 0 and (tonumber(weight) or 0) / targetWeight or 0
    return string.format("%d%%", math.floor(math.max(ratio, 0) * 100 + 0.5))
end

local function localFarmId()
    if g_currentMission ~= nil and g_currentMission.player ~= nil then
        return g_currentMission.player.farmId
    end
    return 0
end

local function metrics()
    return PN_Core.getMetrics(localFarmId())
end

local function statusSuffix(animal)
    local flags = {}
    if animal.pregnant then table.insert(flags, g_i18n:getText("pn_ui_status_pregnant")) end
    if animal.lactating then table.insert(flags, g_i18n:getText("pn_ui_status_lactating")) end
    if animal.castrated then table.insert(flags, g_i18n:getText("pn_ui_status_castrated")) end
    return #flags > 0 and " [" .. table.concat(flags, ", ") .. "]" or ""
end

local function setFactorColor(element, value)
    if element == nil or element.setTextColor == nil then return end
    value = tonumber(value) or 0
    if value < 0.60 then
        element:setTextColor(0.95, 0.12, 0.08, 1)
    elseif value < 0.85 then
        element:setTextColor(1.00, 0.52, 0.00, 1)
    else
        element:setTextColor(0.52, 1.00, 0.00, 1)
    end
end

function PNNutritionDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or PNNutritionDialog_mt)
    self.returnScreenName = ""
    self.metrics = {}
    self.animals = {}
    self.selectedHusbandry = math.max(tonumber(PN_UI.selected) or 1, 1)
    return self
end

function PNNutritionDialog:onGuiSetupFinished()
    PNNutritionDialog:superClass().onGuiSetupFinished(self)
    self.animalList = self:getDescendantById("animalList")
    self.emptyText = self:getDescendantById("emptyText")
    self.husbandryText = self:getDescendantById("husbandryText")
    self.stageText = self:getDescendantById("stageText")
    self.prevButton = self:getDescendantById("prevButton")
    self.nextButton = self:getDescendantById("nextButton")
    self.summaryValues = {
        head = self:getDescendantById("headValue"),
        ration = self:getDescendantById("rationValue"),
        energy = self:getDescendantById("energyValue"),
        protein = self:getDescendantById("proteinValue"),
        rlrm = self:getDescendantById("rlrmValue"),
        effective = self:getDescendantById("effectiveValue"),
        dryMatter = self:getDescendantById("dryMatterValue")
    }
    if self.animalList ~= nil then self.animalList:setDataSource(self) end
end

function PNNutritionDialog:onCreate()
end

function PNNutritionDialog:refreshMetrics()
    self.metrics = metrics()
    self.selectedHusbandry = math.clamp(
        tonumber(PN_UI.selected) or self.selectedHusbandry,
        1,
        math.max(#self.metrics, 1)
    )
    PN_UI.selected = self.selectedHusbandry
    self:updateView()
end

function PNNutritionDialog:updateView()
    local metric = self.metrics[self.selectedHusbandry]
    self.animals = metric ~= nil and metric.individuals or {}
    local hasMetric = metric ~= nil
    local hasAnimals = #self.animals > 0

    if self.animalList ~= nil then
        self.animalList:setVisible(hasAnimals)
        if hasAnimals then self.animalList:reloadData() end
    end
    if self.emptyText ~= nil then
        self.emptyText:setVisible(not hasAnimals)
        self.emptyText:setText(g_i18n:getText(hasMetric and "pn_ui_no_individuals" or "pn_ui_waiting"))
    end
    if self.prevButton ~= nil then self.prevButton:setDisabled(#self.metrics <= 1) end
    if self.nextButton ~= nil then self.nextButton:setDisabled(#self.metrics <= 1) end

    if not hasMetric then
        if self.husbandryText ~= nil then
            self.husbandryText:setText(g_i18n:getText("pn_ui_waiting"))
        end
        if self.stageText ~= nil then self.stageText:setText("") end
        for _, element in pairs(self.summaryValues) do element:setText("-") end
        return
    end

    self.husbandryText:setText(string.format(
        g_i18n:getText("pn_ui_table_barn"),
        metric.name,
        metric.species,
        self.selectedHusbandry,
        #self.metrics
    ))
    local stages = metric.stages ~= "" and metric.stages or g_i18n:getText("pn_ui_pending")
    if metric.unknownKg > 0.01 then
        stages = stages .. "  |  " .. string.format(g_i18n:getText("pn_ui_unknown"), metric.unknownKg)
    end
    self.stageText:setText(string.format(g_i18n:getText("pn_ui_table_stages"), stages))

    self.summaryValues.head:setText(tostring(metric.head))
    self.summaryValues.ration:setText(percent(metric.quality))
    self.summaryValues.energy:setText(percent(metric.energy))
    self.summaryValues.protein:setText(percent(metric.protein))
    self.summaryValues.rlrm:setText(percent(metric.baseFood))
    self.summaryValues.effective:setText(percent(metric.effectiveFood))
    self.summaryValues.dryMatter:setText(string.format("%.0f kg", metric.dryMatterKg))
    setFactorColor(self.summaryValues.ration, metric.quality)
    setFactorColor(self.summaryValues.energy, metric.energy)
    setFactorColor(self.summaryValues.protein, metric.protein)
    setFactorColor(self.summaryValues.rlrm, metric.baseFood)
    setFactorColor(self.summaryValues.effective, metric.effectiveFood)
end

function PNNutritionDialog:onOpen()
    PNNutritionDialog:superClass().onOpen(self)
    PN_UI.visible = true
    PN_UI.dialogOpen = true

    self:refreshMetrics()
    if #self.animals > 0 and self.animalList ~= nil and FocusManager ~= nil then
        FocusManager:setFocus(self.animalList)
    end
end

function PNNutritionDialog:update(dt)
    PNNutritionDialog:superClass().update(self, dt)
end

function PNNutritionDialog:onClose()
    PN_UI.visible = false
    PN_UI.dialogOpen = false
    PNNutritionDialog:superClass().onClose(self)
end

function PNNutritionDialog:onClickPrevious()
    if #self.metrics <= 1 then return end
    self.selectedHusbandry = ((self.selectedHusbandry - 2) % #self.metrics) + 1
    PN_UI.selected = self.selectedHusbandry
    PN_UI.page = 1
    self:updateView()
end

function PNNutritionDialog:onClickNext()
    if #self.metrics <= 1 then return end
    self.selectedHusbandry = (self.selectedHusbandry % #self.metrics) + 1
    PN_UI.selected = self.selectedHusbandry
    PN_UI.page = 1
    self:updateView()
end

function PNNutritionDialog:onClickBack()
    if self.close ~= nil then
        self:close()
    elseif g_gui ~= nil then
        g_gui:showGui(nil)
    end
end

function PNNutritionDialog:getNumberOfSections()
    return 1
end

function PNNutritionDialog:getNumberOfItemsInSection(_list, _section)
    return #self.animals
end

function PNNutritionDialog:getTitleForSectionHeader(_list, _section)
    return ""
end

function PNNutritionDialog:populateCellForItemInSection(_list, _section, index, cell)
    local animal = self.animals[index]
    if animal == nil then return end

    local genderKey = tostring(animal.gender or ""):lower() == "male"
        and "pn_ui_gender_male_short" or "pn_ui_gender_female_short"
    local cells = {
        animalName = g_i18n:getText(genderKey) .. "  " .. tostring(animal.name or animal.id or "?"),
        age = string.format("%d", math.floor((animal.age or 0) + 0.5)),
        stage = tostring(animal.stage or "DEFAULT") .. statusSuffix(animal),
        weight = string.format("%.0f / %.0f kg", animal.weight or 0, animal.targetWeight or 0),
        development = developmentPercent(animal.weight, animal.targetWeight),
        health = percent((animal.health or 0) / 100),
        quality = percent(animal.quality),
        effective = percent(animal.effectiveFood)
    }
    for attribute, value in pairs(cells) do
        local element = cell:getAttribute(attribute)
        if element ~= nil then element:setText(value) end
    end
    setFactorColor(cell:getAttribute("health"), (animal.health or 0) / 100)
    setFactorColor(cell:getAttribute("quality"), animal.quality)
    setFactorColor(cell:getAttribute("effective"), animal.effectiveFood)
end

local function registerDialog()
    if PN_UI.dialog ~= nil then return true end
    if g_gui == nil or ScreenElement == nil or PNNutritionDialog_mt == nil then return false end

    local dialog = PNNutritionDialog.new()
    g_gui:loadGui(
        Utils.getFilename("gui/PNNutritionDialog.xml", PN_MOD_DIRECTORY),
        "PNNutritionMenu",
        dialog
    )
    PN_UI.dialog = dialog
    return true
end

function PN_UI.toggle()
    if PN_UI.dialogOpen and PN_UI.dialog ~= nil then
        PN_UI.dialog:onClickBack()
        return
    end
    if not registerDialog() then return end

    if g_server ~= nil then
        PN_Husbandry.scan()
        PN_Core.refreshAllMetrics(false)
    end
    g_gui:showGui("PNNutritionMenu")
end

function PN_UI.previous()
    if PN_UI.dialogOpen and PN_UI.dialog ~= nil then
        PN_UI.dialog:onClickPrevious()
    end
end

function PN_UI.next()
    if PN_UI.dialogOpen and PN_UI.dialog ~= nil then
        PN_UI.dialog:onClickNext()
    end
end

function PN_UI.registerPlayerActions()
    if g_inputBinding == nil then return end
    -- Match FS25/RLRM's native lifecycle: register the dialog while player
    -- actions are being installed, not from inside the Alt+N input callback.
    if not registerDialog() then return end
    local success, id = g_inputBinding:registerActionEvent(
        InputAction.PN_TOGGLE_OVERLAY,
        PN_UI,
        PN_UI.toggle,
        false,
        true,
        false,
        true,
        nil,
        true
    )
    if success and id ~= nil then g_inputBinding:setActionEventTextVisibility(id, false) end
end

if PlayerInputComponent ~= nil and PlayerInputComponent.registerGlobalPlayerActionEvents ~= nil then
    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
        PlayerInputComponent.registerGlobalPlayerActionEvents,
        PN_UI.registerPlayerActions
    )
end

-- PN_Load retains its original draw callback. Native GUI elements draw through
-- g_gui, so there is no direct-render overlay here.
function PN_UI.draw() end

return PN_UI
