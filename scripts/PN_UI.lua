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

-- Built-in stages get localized labels; user-defined stage identifiers remain intact.
local stageKeys = {}
for _, stage in ipairs({
    "CALF", "HEIFER", "COW_DRY", "COW_GEST", "COW_LACT", "YEARLING", "STEER_FINISH", "BULL",
    "LAMB", "GROWER", "EWE_DRY", "EWE_GEST", "EWE_LACT", "WETHER_FINISH", "RAM", "RAM_ADULT",
    "KID", "DOE_DRY", "DOE_GEST", "DOE_LACT", "BUCK", "BUCK_ADULT",
    "PIGLET", "GILT", "SOW_DRY", "SOW_GEST", "SOW_LACT", "BARROW_FINISH", "BOAR", "BOAR_ADULT",
    "CHICK", "LAYER", "ROOSTER", "FOAL", "WEANLING", "MARE_DRY", "MARE_GEST", "MARE_LACT",
    "GELDING", "COLT", "STALLION", "DEFAULT"
}) do
    stageKeys[stage] = "pn_ui_stage_" .. stage:lower()
end

local function stageName(stage)
    local key = stageKeys[stage]
    return key ~= nil and g_i18n:getText(key) or stage
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
    self.stageOptions = {}
    self.selectedStage = nil
    self.stageFilterOpen = false
    self.selectedHusbandry = math.max(tonumber(PN_UI.selected) or 1, 1)
    return self
end

function PNNutritionDialog:onGuiSetupFinished()
    PNNutritionDialog:superClass().onGuiSetupFinished(self)
    self.animalList = self:getDescendantById("animalList")
    self.emptyText = self:getDescendantById("emptyText")
    self.husbandryText = self:getDescendantById("husbandryText")
    self.stageText = self:getDescendantById("stageText")
    self.stageFilterButton = self:getDescendantById("stageFilterButton")
    self.stageFilterList = self:getDescendantById("stageFilterList")
    self.stageFilterPanel = self:getDescendantById("stageFilterPanel")
    self.stageFilterBackground = self:getDescendantById("stageFilterBackground")
    self.stageFilterSlider = self:getDescendantById("stageFilterSlider")
    self.filterCountText = self:getDescendantById("filterCountText")
    self.animalSliderBox = self:getDescendantById("animalSliderBox")
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
    if self.stageFilterList ~= nil then
        self.stageFilterList:setDataSource(self)
        self.stageFilterRowHeight = self.stageFilterList.size[2] / 7
    end
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

function PNNutritionDialog:updateStageFilter(metric)
    local individuals = metric ~= nil and metric.individuals or {}
    local counts = {}
    for _, animal in ipairs(individuals) do
        local stage = tostring(animal.stage or "DEFAULT")
        counts[stage] = (counts[stage] or 0) + 1
    end
    local stages = {}
    for stage in pairs(counts) do table.insert(stages, stage) end
    table.sort(stages)
    if self.selectedStage ~= nil and counts[self.selectedStage] == nil then
        self.selectedStage = nil
    end

    self.stageOptions = {{ text=string.format("%s (%d)",
        g_i18n:getText("pn_ui_filter_all"), #individuals) }}
    local selectedIndex = 1
    for _, stage in ipairs(stages) do
        table.insert(self.stageOptions, {
            stage=stage, text=string.format("%s (%d)", stageName(stage), counts[stage])
        })
        if stage == self.selectedStage then selectedIndex = #self.stageOptions end
    end
    self.selectedStageIndex = selectedIndex
    self.animals = {}
    for _, animal in ipairs(individuals) do
        if self.selectedStage == nil or tostring(animal.stage or "DEFAULT") == self.selectedStage then
            table.insert(self.animals, animal)
        end
    end
    if self.stageFilterButton ~= nil then
        self.stageFilterButton:setText(self.stageOptions[selectedIndex].text)
        self.stageFilterButton:setDisabled(#individuals == 0)
    end
    if self.filterCountText ~= nil then
        local isPartial = metric ~= nil and (tonumber(metric.individualTotal) or #individuals) > #individuals
        self.filterCountText:setText(string.format(g_i18n:getText(
            isPartial and "pn_ui_filter_count_received" or "pn_ui_filter_count"),
            #self.animals, #individuals))
    end
end

function PNNutritionDialog:setStageFilterOpen(isOpen)
    self.stageFilterOpen = isOpen == true
    if self.stageFilterPanel ~= nil then self.stageFilterPanel:setVisible(self.stageFilterOpen) end
    if self.animalList ~= nil then self.animalList:setDisabled(self.stageFilterOpen) end
    if self.animalSliderBox ~= nil then self.animalSliderBox:setDisabled(self.stageFilterOpen) end
    if self.stageFilterOpen and self.stageFilterList ~= nil then
        local height = math.min(#self.stageOptions, 7) * self.stageFilterRowHeight
        self.stageFilterList:setSize(self.stageFilterList.size[1], height)
        self.stageFilterPanel:setSize(self.stageFilterPanel.size[1], height)
        if self.stageFilterBackground ~= nil then
            self.stageFilterBackground:setSize(self.stageFilterBackground.size[1], height)
        end
        if self.stageFilterSlider ~= nil then self.stageFilterSlider:setVisible(#self.stageOptions > 7) end
        self.stageFilterList:reloadData()
        self.stageFilterList:setSelectedItem(1, self.selectedStageIndex)
        if FocusManager ~= nil then FocusManager:setFocus(self.stageFilterList) end
    end
end

function PNNutritionDialog:onClickStageFilter()
    if self.stageFilterButton == nil or #self.stageOptions <= 1 then return end
    local wasOpen = self.stageFilterOpen
    self:setStageFilterOpen(not wasOpen)
    if wasOpen and FocusManager ~= nil then FocusManager:setFocus(self.stageFilterButton) end
end

function PNNutritionDialog:onClickStageOption(_list, _section, index)
    local option = self.stageOptions[index]
    if not self.stageFilterOpen or option == nil then return end
    self.selectedStage = option.stage
    self:setStageFilterOpen(false)
    self:updateView()
    if #self.animals > 0 and self.animalList ~= nil then self.animalList:scrollToStart() end
    if FocusManager ~= nil then FocusManager:setFocus(self.stageFilterButton) end
end

function PNNutritionDialog:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    if self.stageFilterOpen and isDown and button == Input.MOUSE_BUTTON_LEFT then
        local function inside(element)
            return element ~= nil and GuiUtils.checkOverlayOverlap(posX, posY,
                element.absPosition[1], element.absPosition[2], element.absSize[1], element.absSize[2])
        end
        if not inside(self.stageFilterPanel) and not inside(self.stageFilterButton) then
            self:setStageFilterOpen(false)
            if FocusManager ~= nil then FocusManager:setFocus(self.stageFilterButton) end
            return true
        end
    end
    return PNNutritionDialog:superClass().mouseEvent(self, posX, posY, isDown, isUp, button, eventUsed)
end

function PNNutritionDialog:updateView()
    local metric = self.metrics[self.selectedHusbandry]
    self:updateStageFilter(metric)
    local hasMetric = metric ~= nil
    local hasAnimals = #self.animals > 0

    if self.animalList ~= nil then
        self.animalList:setVisible(hasAnimals)
        if hasAnimals then self.animalList:reloadData() end
    end
    if self.animalSliderBox ~= nil then
        local needsScrolling = hasAnimals
        if self.animalList ~= nil and self.animalList.contentSize ~= nil then
            needsScrolling = hasAnimals and self.animalList.contentSize > self.animalList.absSize[2] + 0.00001
        end
        self.animalSliderBox:setVisible(needsScrolling)
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

    self.selectedStage = nil
    self:setStageFilterOpen(false)
    self:refreshMetrics()
    if #self.animals > 0 and self.animalList ~= nil and FocusManager ~= nil then
        FocusManager:setFocus(self.animalList)
    end
end

function PNNutritionDialog:update(dt)
    PNNutritionDialog:superClass().update(self, dt)
end

function PNNutritionDialog:onClose()
    self:setStageFilterOpen(false)
    PN_UI.visible = false
    PN_UI.dialogOpen = false
    PNNutritionDialog:superClass().onClose(self)
end

function PNNutritionDialog:onClickPrevious()
    if #self.metrics <= 1 then return end
    self.selectedHusbandry = ((self.selectedHusbandry - 2) % #self.metrics) + 1
    PN_UI.selected = self.selectedHusbandry
    PN_UI.page = 1
    self.selectedStage = nil
    self:setStageFilterOpen(false)
    self:updateView()
end

function PNNutritionDialog:onClickNext()
    if #self.metrics <= 1 then return end
    self.selectedHusbandry = (self.selectedHusbandry % #self.metrics) + 1
    PN_UI.selected = self.selectedHusbandry
    PN_UI.page = 1
    self.selectedStage = nil
    self:setStageFilterOpen(false)
    self:updateView()
end

function PNNutritionDialog:onClickBack()
    if self.stageFilterOpen then
        self:setStageFilterOpen(false)
        if FocusManager ~= nil then FocusManager:setFocus(self.stageFilterButton) end
        return
    end
    if self.close ~= nil then
        self:close()
    elseif g_gui ~= nil then
        g_gui:showGui(nil)
    end
end

function PNNutritionDialog:getNumberOfSections()
    return 1
end

function PNNutritionDialog:getNumberOfItemsInSection(list, _section)
    if list == self.stageFilterList then return #self.stageOptions end
    return #self.animals
end

function PNNutritionDialog:getTitleForSectionHeader(_list, _section)
    return ""
end

function PNNutritionDialog:populateCellForItemInSection(list, _section, index, cell)
    if list == self.stageFilterList then
        local option = self.stageOptions[index]
        local text = cell:getAttribute("optionText")
        if option ~= nil and text ~= nil then text:setText(option.text) end
        return
    end
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
