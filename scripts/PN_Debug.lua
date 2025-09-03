-- FS25_PrecisionNutrition / scripts / PN_Debug.lua
-- Console helpers for on-demand inspection (FS25-style addConsoleCommand).

PN_Debug = PN_Debug or {}

-- =========================================================
-- Small utilities (safe string, simple helpers)
-- =========================================================
local function _safe(n)
    if n == nil then return "?" end
    n = tostring(n)
    if n == "" then return "?" end
    return n
end

-- =========================================================
-- Diagnostics & self-heal
-- =========================================================
-- Prints which PN modules/methods are actually loaded and ready
function PN_Debug:cmdDiag()
    local ok = function(x) return x and "yes" or "no" end
    local has = function(t, k) return (t and t[k]) and "yes" or "no" end

    Logging.info("---- PN Diag ----")
    Logging.info("PN_Settings loaded: " .. ok(PN_Settings))
    Logging.info("PN_Logger  loaded: " .. ok(PN_Logger) .. (PN_Logger and (" level="..(PN_Logger.levelName or "?")) or ""))

    Logging.info("PN_HusbandryScan loaded: " .. ok(PN_HusbandryScan))
    if PN_HusbandryScan and PN_HusbandryScan.entries then
        Logging.info(("  entries: %d"):format(#PN_HusbandryScan.entries))
    end

    Logging.info("PN_FeedMatrix loaded: " .. ok(PN_FeedMatrix))
    Logging.info("PN_Core      loaded: " .. ok(PN_Core) ..
                 "  computeNutritionAndADG: " .. has(PN_Core, "computeNutritionAndADG"))

    Logging.info("PN_Events    loaded: " .. ok(PN_Events) ..
                 "  heartbeat: " .. has(PN_Events, "heartbeat") ..
                 "  simDays: " .. has(PN_Events, "simDays"))

    Logging.info("---- End PN Diag ----")
end

function PN_Debug:cmdFixEvents()
    if not PN_Events then PN_Events = {} end
    PN_Events.__index = PN_Events
    -- Reattach methods if missing (pull from globals the installer stashed)
    PN_Events.heartbeat = PN_Events.heartbeat or _G.__pn_events_heartbeat_impl
    PN_Events.simDays   = PN_Events.simDays   or _G.__pn_events_simdays_impl
    if PN_Events.heartbeat and PN_Events.simDays then
        Logging.info("[PN] Events restored (heartbeat/simDays).")
    else
        Logging.info("[PN] Could not restore Events (impls missing).")
    end
end

-- =========================================================
-- Listing / exporting husbandries
-- =========================================================
function PN_Debug:cmdDumpHusbandries()
    if PN_HusbandryScan == nil or PN_HusbandryScan.getAll == nil then
        Logging.info("[PN] pnDumpHusbandries: scanner not available")
        return
    end
    local list = PN_HusbandryScan.getAll()
    Logging.info("[PN] ---- PN Husbandries ---- count=%d", #list)
    for i, e in ipairs(list) do
        local name   = _safe(e.name)
        local farmId = _safe(e.farmId)
        local kind   = _safe(e.type)
        local hasCS  = (e.clusterSystem ~= nil) and "yes" or "no"
        Logging.info("[PN] %03d | farm=%s | type=%s | cluster=%s | %s", i, farmId, kind, hasCS, name)
    end
    Logging.info("[PN] ------------------------")
end

function PN_Debug:cmdDumpHusbandriesCSV()
    if PN_HusbandryScan == nil or PN_HusbandryScan.getAll == nil then
        Logging.info("[PN] pnDumpHusbandriesCSV: scanner not available")
        return
    end
    local list = PN_HusbandryScan.getAll()
    local dir  = g_currentModSettingsDirectory or ""
    local file = dir .. "/PN_Husbandries.csv"
    local fh = io.open(file, "w")
    if fh == nil then
        Logging.info("[PN] Could not open %s for writing", file)
        return
    end
    fh:write("index,farmId,type,cluster,name\n")
    for i, e in ipairs(list) do
        local name   = '"' .. tostring(_safe(e.name)):gsub('"', '""') .. '"'
        local farmId = _safe(e.farmId)
        local kind   = _safe(e.type)
        local hasCS  = (e.clusterSystem ~= nil) and "yes" or "no"
        fh:write(string.format("%d,%s,%s,%s,%s\n", i, farmId, kind, hasCS, name))
    end
    fh:close()
    Logging.info("[PN] Wrote %d entries to %s", #list, file)
end

-- =========================================================
-- Inspectors (husbandry, clusters, trough, food spec)
-- =========================================================
function PN_Debug:cmdInspectHusbandry(idxStr)
    local idx = tonumber(idxStr or "")
    if idx == nil then
        Logging.info("[PN] Usage: pnInspect <index>  (see pnDumpHusbandries)")
        return
    end
    local list = (PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll()) or {}
    local e = list[idx]
    if not e then
        Logging.info("[PN] pnInspect: no entry at index %s", tostring(idx))
        return
    end
    Logging.info("[PN] Inspect #%d: name=%s farm=%s type=%s cluster=%s",
        idx, tostring(e.name), tostring(e.farmId), tostring(e.type), tostring(e.clusterSystem ~= nil))

    local function dumpTable(label, t, max)
        Logging.info("[PN]  %s = %s", label, tostring(t))
        local n = 0
        for k, v in pairs(t or {}) do
            Logging.info("[PN]   - %s : %s", tostring(k), tostring(v))
            n = n + 1; if n >= (max or 20) then break end
        end
    end

    dumpTable("placeable", e.placeable, 25)
    if e.placeable and e.placeable.spec_husbandryAnimals then
        dumpTable("spec_husbandryAnimals", e.placeable.spec_husbandryAnimals, 50)
    end
    if e.clusterSystem then
        dumpTable("clusterSystem", e.clusterSystem, 50)
        if e.clusterSystem.getClusters then
            local ok, clusters = pcall(e.clusterSystem.getClusters, e.clusterSystem)
            Logging.info("[PN]  getClusters() ok=%s, result=%s", tostring(ok), tostring(clusters))
        end
        if e.clusterSystem.getNumOfAnimals then
            local ok, n = pcall(e.clusterSystem.getNumOfAnimals, e.clusterSystem)
            Logging.info("[PN]  getNumOfAnimals() ok=%s, n=%s", tostring(ok), tostring(n))
        end
    end
end

function PN_Debug:cmdInspectClusters(idxStr)
    local idx = tonumber(idxStr or "")
    if idx == nil then
        Logging.info("[PN] Usage: pnInspectClusters <index>  (see pnDumpHusbandries)")
        return
    end
    local list = (PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll()) or {}
    local e = list[idx]
    if not e or not e.clusterSystem then
        Logging.info("[PN] pnInspectClusters: no entry/cluster at index %s", tostring(idx))
        return
    end

    local ok, clusters = pcall(e.clusterSystem.getClusters, e.clusterSystem)
    if not ok or type(clusters) ~= "table" then
        Logging.info("[PN] pnInspectClusters: getClusters() failed or not a table")
        return
    end

    local count = 0
    for k, c in pairs(clusters) do
        count = count + 1
        Logging.info("[PN]  Cluster key=%s  value=%s", tostring(k), tostring(c))
        local n = 0
        for ck, cv in pairs(c or {}) do
            Logging.info("[PN]    - %s : %s", tostring(ck), tostring(cv))
            n = n + 1; if n >= 20 then break end
        end
    end
    Logging.info("[PN]  total clusters=%d", count)
end

-- ---- fillType name helper (v2, intentionally later to override v1)
local function _ftName(idx)
    if g_fillTypeManager and g_fillTypeManager.getFillTypeNameByIndex then
        local n = g_fillTypeManager:getFillTypeNameByIndex(idx)
        if n and n ~= "" then return n end
    end
    return tostring(idx)
end

local function _hasFillUnit(p)
    return p and p.spec_fillUnit and p.spec_fillUnit.fillUnits and #p.spec_fillUnit.fillUnits > 0
end

-- v2: also show husbandryFood if present (some maps separate specs)
function PN_Debug:cmdInspectTrough(idxStr)
    local idx = tonumber(idxStr or "")
    if not idx then
        Logging.info("[PN] Usage: pnInspectTrough <index> (see pnDumpHusbandries)")
        return
    end
    local list = (PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll()) or {}
    local e = list[idx]
    if not e or not e.placeable then
        Logging.info("[PN] pnInspectTrough: no entry/placeable at %s", tostring(idx))
        return
    end
    local p = e.placeable

    if _hasFillUnit(p) then
        local fus = p.spec_fillUnit.fillUnits
        Logging.info("[PN] Placeable '%s' has %d fillUnits:", tostring(e.name), #fus)
        for u, fu in ipairs(fus) do
            local lvl  = tonumber(fu.fillLevel or 0) or 0
            local lft  = fu.lastFillType or fu.fillType
            Logging.info("[PN]  unit %d: level=%.3f, fillType=%s", u, lvl, _ftName(lft))
            if fu.supportedFillTypes then
                local names = {}
                for ftIndex, allowed in pairs(fu.supportedFillTypes) do
                    if allowed then table.insert(names, _ftName(ftIndex)) end
                end
                table.sort(names)
                if #names > 0 then
                    Logging.info("[PN]   supported: %s", table.concat(names, ", "))
                end
            end
            if fu.fillLevels then
                local count = 0
                for ftIndex, v in pairs(fu.fillLevels) do
                    if count < 16 then
                        Logging.info("[PN]   level[%s]=%.3f", _ftName(ftIndex), tonumber(v or 0) or 0)
                    end
                    count = count + 1
                end
                if count > 16 then Logging.info("[PN]   ... (%d total entries)", count) end
            end
        end
        return
    end

    -- No fillUnit on this placeable. Some maps carry a husbandryFood spec with fillTypes listed:
    if p.spec_husbandryFood and p.spec_husbandryFood.fillTypes then
        local names = {}
        for ftIndex, allowed in pairs(p.spec_husbandryFood.fillTypes) do
            if allowed then table.insert(names, _ftName(ftIndex)) end
        end
        table.sort(names)
        Logging.info("[PN] '%s' has spec_husbandryFood; accepted: %s", tostring(e.name), table.concat(names, ", "))
    else
        Logging.info("[PN] '%s' has no fillUnit and no spec_husbandryFood", tostring(e.name))
    end
    Logging.info("[PN] Tip: try pnFindFeeder %d to locate a nearby feeder placeable.", idx)
end

function PN_Debug:cmdInspectFoodSpec(idxStr)
  local idx = tonumber(idxStr or "")
  if not idx then
    Logging.info("[PN] Usage: pnInspectFoodSpec <index>")
    return
  end
  local list = PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll() or {}
  local e = list[idx]
  local p = e and e.placeable
  if not (p and p.spec_husbandryFood) then
    Logging.info("[PN] pnInspectFoodSpec: no spec_husbandryFood on entry %s", tostring(idx))
    return
  end
  local lv = p.spec_husbandryFood.fillLevels
  if type(lv) ~= "table" then
    Logging.info("[PN] pnInspectFoodSpec: no fillLevels table")
    return
  end
  local n = 0
  for ftIndex, v in pairs(lv) do
    Logging.info("[PN] food level[%s] = %.3f", _ftName(ftIndex), tonumber(v or 0) or 0)
    n = n + 1
  end
  if n == 0 then Logging.info("[PN] pnInspectFoodSpec: empty") end
end

-- =========================================================
-- Finder
-- =========================================================
function PN_Debug:cmdFindFeeder(idxStr, radiusStr)
    local idx = tonumber(idxStr or "")
    local radius = tonumber(radiusStr or "35") or 35  -- meters
    if not idx then
        Logging.info("[PN] Usage: pnFindFeeder <index> [radiusMeters]")
        return
    end
    local list = (PN_HusbandryScan and PN_HusbandryScan.getAll and PN_HusbandryScan.getAll()) or {}
    local e = list[idx]
    if not e or not e.placeable or not e.placeable.rootNode then
        Logging.info("[PN] pnFindFeeder: no entry/rootNode at %s", tostring(idx))
        return
    end
    local ex, ey, ez = getWorldTranslation(e.placeable.rootNode)
    local myFarm = e.farmId

    local candidates = {}
    -- Walk all known placeables (via PlaceableSystem or our scanner cache if exposed)
    local ps = g_placeableSystem or g_placeableManager or {}
    local function try(pl)
        if pl and pl ~= e.placeable and _hasFillUnit(pl) then
            -- same farm (when available)
            local pfarm = (pl.owningPlaceable and pl.owningPlaceable.farmId) or pl.farmId or pl.ownerFarmId
            if (myFarm == nil) or (pfarm == nil) or (pfarm == myFarm) then
                local rx = pl.rootNode or pl.nodeId or pl.node
                if rx then
                    local x, y, z = getWorldTranslation(rx)
                    local dx, dz = (x - ex), (z - ez)
                    local dist2 = dx*dx + dz*dz
                    table.insert(candidates, { pl=pl, dist2=dist2 })
                end
            end
        end
    end

    -- collect from PlaceableSystem / Manager
    if ps.placeables then
      for _, pl in ipairs(ps.placeables) do try(pl) end
    end
    if type(ps.getPlaceables) == "function" then
      local ok, arr = pcall(ps.getPlaceables, ps)
      if ok and type(arr) == "table" then
        for _, pl in ipairs(arr) do try(pl) end
      end
    end

    table.sort(candidates, function(a,b) return a.dist2 < b.dist2 end)

    local shown = 0
    for _, c in ipairs(candidates) do
        local dist = math.sqrt(c.dist2)
        if dist <= radius then
            shown = shown + 1
            local pl = c.pl
            Logging.info("[PN] Feeder candidate @ %.1fm: %s", dist, tostring(pl.typeName or pl.customEnvironment or pl))
            local fus = pl.spec_fillUnit.fillUnits
            for u, fu in ipairs(fus) do
                local lvl  = tonumber(fu.fillLevel or 0) or 0
                local lft  = fu.lastFillType or fu.fillType
                Logging.info("[PN]   unit %d: level=%.3f, currentFT=%s", u, lvl, _ftName(lft))
                if fu.supportedFillTypes then
                    local names = {}
                    for ftIndex, allowed in pairs(fu.supportedFillTypes) do
                        if allowed then table.insert(names, _ftName(ftIndex)) end
                    end
                    table.sort(names)
                    if #names > 0 then
                        Logging.info("[PN]    supported: %s", table.concat(names, ", "))
                    end
                end
            end
        end
        if shown >= 5 then break end -- avoid spam
    end

    if shown == 0 then
        Logging.info("[PN] No feeder placeable with fillUnits found within %.0fm of '%s'", radius, tostring(e.name))
    end
end

-- =========================================================
-- Mix override (set/clear/show)
-- =========================================================
function PN_Debug:cmdSetMix(idxStr, specStr)
    local idx = tonumber(idxStr)
    local list = (PN_HusbandryScan and PN_HusbandryScan.entries) or (PN_Core and PN_Core.entries)
    if not idx or not list or not list[idx] then
        Logging.info('[PN] Usage: pnSetMix <index> "TYPE=frac,TYPE=frac,..."')
        return
    end
    local mix, err = _parseMixSpec(specStr)
    if not mix then
        Logging.info("[PN] pnSetMix error: "..tostring(err))
        return
    end
    local e = list[idx]
    e.__pn_mixOverride = mix
    _printMix(string.format("[PN] Mix override set on %s: ", _entryLabel(e, idx)), mix)
end

function PN_Debug:cmdClearMix(idxStr)
    local idx = tonumber(idxStr)
    local list = (PN_HusbandryScan and PN_HusbandryScan.entries) or (PN_Core and PN_Core.entries)
    if not idx or not list or not list[idx] then
        Logging.info("[PN] Usage: pnClearMix <index>")
        return
    end
    local e = list[idx]
    e.__pn_mixOverride = nil
    Logging.info(string.format("[PN] Mix override cleared on %s", _entryLabel(e, idx)))
end

function PN_Debug:cmdShowMix(idxStr)
    local idx = tonumber(idxStr)
    local list = (PN_HusbandryScan and PN_HusbandryScan.entries) or (PN_Core and PN_Core.entries)
    if not idx or not list or not list[idx] then
        Logging.info("[PN] Usage: pnShowMix <index>")
        return
    end
    local e = list[idx]
    if e.__pn_mixOverride then
        _printMix(string.format("[PN] %s override: ", _entryLabel(e, idx)), e.__pn_mixOverride)
        return
    end
    -- Estimate from trough levels if possible
    local plc = e.placeable or e.feeder or e
    if plc and _isFeeder(plc) and plc.spec_husbandryFood and plc.spec_husbandryFood.fillLevels then
        local lvl = plc.spec_husbandryFood.fillLevels
        local total = 0
        for _,v in pairs(lvl) do total = total + (v or 0) end
        if total > 0 then
            local est = {}
            for id,v in pairs(lvl) do
                if (v or 0) > 0 then est[id] = (v or 0) / total end
            end
            _printMix(string.format("[PN] %s trough-estimated: ", _entryLabel(e, idx)), est)
            return
        end
    end
    Logging.info(string.format("[PN] %s has no override and trough composition not visible.", _entryLabel(e, idx)))
end

-- =========================================================
-- One-shot / simulation / feed manipulation / credit
-- =========================================================
function PN_Debug:cmdBeat(idxStr)
	local function _adgSupplyEnabled()
	  if PN_Settings and PN_Settings.adg and PN_Settings.adg.useSupplyFactor ~= nil then
		return (PN_Settings.adg.useSupplyFactor == true)
	  end
	  return true
	end

    if PN_HusbandryScan == nil or PN_HusbandryScan.getAll == nil or PN_Core == nil or PN_Core.updateHusbandry == nil then
        Logging.info("[PN] pnBeat: PN not ready")
        return
    end
    local idx = tonumber(idxStr or "")
    if idx == nil then
        Logging.info("[PN] Usage: pnBeat <index> (see pnDumpHusbandries)")
        return
    end
    local list = PN_HusbandryScan.getAll()
    local e = list[idx]
    if not e or not e.clusterSystem then
        Logging.info("[PN] pnBeat: no entry/cluster at index %s", tostring(idx))
        return
    end

    -- Refresh PN snapshot so nut/totals are current
    pcall(PN_Core.updateHusbandry, PN_Core, e, e.clusterSystem, 33, { forceBeat = true })

    -- Species inference
    local function inferSpecies(entry)
        local function norm(s)
            s = tostring(s or ""):upper()
            if s == "CATTLE" then return "COW" end
            if s == "HEN" then return "CHICKEN" end
            return s
        end
        if entry and entry.type and entry.type ~= "ANIMAL" then return norm(entry.type) end
        local cs = entry and entry.clusterSystem
        if cs and cs.getClusters then
            local ok, clusters = pcall(cs.getClusters, cs)
            if ok and type(clusters) == "table" then
                for _, c in pairs(clusters) do
                    local st = tostring(c and c.subType or ""):upper()
                    if st:find("COW",1,true) or st:find("BULL",1,true) then return "COW" end
                    if st:find("SHEEP",1,true) then return "SHEEP" end
                    if st:find("PIG",1,true) then return "PIG" end
                    if st:find("GOAT",1,true) then return "GOAT" end
                    if st:find("CHICK",1,true) or st:find("HEN",1,true) then return "CHICKEN" end
                end
            end
        end
        return "ANIMAL"
    end

    local species = inferSpecies(e)
    local name    = tostring(e.name or "?")

    -- Split counts from live clusters
    local counts = { femaleOpen=0, femalePreg=0, male=0 }
    local wsum   = { femaleOpen=0, femalePreg=0, male=0 }
    local okC, clusters = pcall(e.clusterSystem.getClusters, e.clusterSystem)
    if okC and type(clusters) == "table" then
        for _, c in pairs(clusters) do
            if type(c) == "table" and not c.isDead then
                local gsex = tostring(c.gender or ""):lower()
                local w    = tonumber(c.weight or 0) or 0
                if gsex == "female" then
                    if c.isPregnant then
                        counts.femalePreg = counts.femalePreg + 1
                        wsum.femalePreg   = wsum.femalePreg + w
                    else
                        counts.femaleOpen = counts.femaleOpen + 1
                        wsum.femaleOpen   = wsum.femaleOpen + w
                    end
                elseif gsex == "male" then
                    counts.male = counts.male + 1
                    wsum.male   = wsum.male + w
                end
            end
        end
    end
    local avgW = {
        femaleOpen = (counts.femaleOpen>0) and (wsum.femaleOpen / counts.femaleOpen) or 0,
        femalePreg = (counts.femalePreg>0) and (wsum.femalePreg / counts.femalePreg) or 0,
        male       = (counts.male>0)       and (wsum.male       / counts.male)       or 0,
    }

    -- Barn-level Nut ratio (0..1)
    local barnNut = 0
    if e.__pn_last and e.__pn_last.nutRatio ~= nil then
        barnNut = tonumber(e.__pn_last.nutRatio) or 0
    elseif PN_Core and PN_Core.getTotals then
        local okT, totals = pcall(PN_Core.getTotals, e)
        if okT and type(totals) == "table" then
            barnNut = tonumber(totals.nut or 0) or 0
        end
    end
    if barnNut < 0 then barnNut = 0 elseif barnNut > 1 then barnNut = 1 end

    -- Live available DM in trough (kg) — robust to either e.placeable.* or e.* specs
    local function fillTypeNameByIndex(idx)
        if g_fillTypeManager and g_fillTypeManager.getFillTypeNameByIndex then
            local n = g_fillTypeManager:getFillTypeNameByIndex(idx)
            if n and n ~= "" then return n end
        end
        return "FT:"..tostring(idx)
    end
    local function barnAvailableDmKg(entry)
        local p = (entry and entry.placeable) or entry
        if not p then return 0 end
        local total = 0
        -- Preferred: spec_fillUnit.fillUnits[*].fillLevels[ft] = liters
        if p.spec_fillUnit and p.spec_fillUnit.fillUnits then
            for _, fu in ipairs(p.spec_fillUnit.fillUnits) do
                local levels = fu and fu.fillLevels
                if type(levels) == "table" then
                    for ftIndex, L in pairs(levels) do
                        local liters = tonumber(L or 0) or 0
                        if liters > 0 then
                            local mpl = 1.0
                            if g_fillTypeManager and g_fillTypeManager.fillTypes and g_fillTypeManager.fillTypes[ftIndex] then
                                mpl = tonumber(g_fillTypeManager.fillTypes[ftIndex].massPerLiter or 1.0) or 1.0
                            end
                            local nameU = tostring(fillTypeNameByIndex(ftIndex)):upper()
                            local dmFrac = nil
                            if PN_Core and PN_Core.feedAliases and PN_Core.feedAliases[nameU] and PN_Core.feedAliases[nameU].dmFrac then
                                dmFrac = tonumber(PN_Core.feedAliases[nameU].dmFrac)
                            elseif PN_Core and PN_Core.tokenForFillTypeIndex then
                                local okTok, tok = pcall(PN_Core.tokenForFillTypeIndex, PN_Core, ftIndex)
                                if okTok and tok and PN_Core.feedTable and PN_Core.feedTable[tok] and PN_Core.feedTable[tok].dmFrac then
                                    dmFrac = tonumber(PN_Core.feedTable[tok].dmFrac)
                                end
                            end
                            dmFrac = dmFrac or 0
                            total = total + (liters * mpl * dmFrac)
                        end
                    end
                end
            end
        end
        -- Fallback: spec_husbandryFood aggregate levels (fallback)
        if total == 0 and p.spec_husbandryFood and p.spec_husbandryFood.fillLevels then
            for ftIndex, L in pairs(p.spec_husbandryFood.fillLevels) do
                local liters = tonumber(L or 0) or 0
                if liters > 0 then
                    local mpl = 1.0
                    if g_fillTypeManager and g_fillTypeManager.fillTypes and g_fillTypeManager.fillTypes[ftIndex] then
                        mpl = tonumber(g_fillTypeManager.fillTypes[ftIndex].massPerLiter or 1.0) or 1.0
                    end
                    local nameU = tostring(fillTypeNameByIndex(ftIndex)):upper()
                    local dmFrac = nil
                    if PN_Core and PN_Core.feedAliases and PN_Core.feedAliases[nameU] and PN_Core.feedAliases[nameU].dmFrac then
                        dmFrac = tonumber(PN_Core.feedAliases[nameU].dmFrac)
                    elseif PN_Core and PN_Core.tokenForFillTypeIndex then
                        local okTok, tok = pcall(PN_Core.tokenForFillTypeIndex, PN_Core, ftIndex)
                        if okTok and tok and PN_Core.feedTable and PN_Core.feedTable[tok] and PN_Core.feedTable[tok].dmFrac then
                            dmFrac = tonumber(PN_Core.feedTable[tok].dmFrac)
                        end
                    end
                    dmFrac = dmFrac or 0
                    total = total + (liters * mpl * dmFrac)
                end
            end
        end
        return total
    end

    -- Demand (kg/hd/d) for each stage
    local function dmDemandKgHd(species, stage)
        if PN_Core and PN_Core.nutritionForStage then
            local okN, row = pcall(PN_Core.nutritionForStage, PN_Core, species, stage)
            if okN and type(row)=="table" then
                local v = tonumber(row.dmDemandKgHd or row.intakeKgHd or 0)
                if v and v > 0 then return v end
            end
        end
        return 0
    end

    -- Supply factor from available DM vs required DM (0..1)
    local function supplyFactorBarn(entry, species, counts)
        local avail = barnAvailableDmKg(entry)
        local req = 0
        req = req + dmDemandKgHd(species, "LACT") * (counts.femaleOpen or 0)
        req = req + dmDemandKgHd(species, "GEST") * (counts.femalePreg or 0)
        req = req + dmDemandKgHd(species, "BULL") * (counts.male       or 0)
        if req <= 0 then return 1.0 end
        local f = avail / req
        if f < 0 then f = 0 elseif f > 1 then f = 1 end
        return f
    end

    -- Stage label for ADG model
    local function stageFor(key)
        local sex  = (key == "male") and "male" or "female"
        local isPr = (key == "femalePreg")
        if PN_Core and PN_Core.stageLabel then
            local okS, lbl = pcall(PN_Core.stageLabel, PN_Core, species, sex, isPr)
            if okS and type(lbl) == "string" and lbl ~= "" then return lbl end
        end
        if species == "COW" then
            if sex == "male" then return "BULL" end
            return isPr and "GEST" or "LACT"
        end
        if sex == "male" then return "MALE" end
        return isPr and "PREG" or "FEMALE"
    end

    -- Maturity reserve (same as PN_Core.updateHusbandry)
    local function maturityReserve(species, avgW)
        local mk
        if PN_Core and PN_Core.meta then
            local m = PN_Core.meta[(tostring(species or "COW")):upper()]
            mk = m and tonumber(m.matureKg)
        end
        if mk and mk > 0 and (avgW or 0) > 0 then
            local frac = math.max(0, math.min(1, (avgW or 0)/mk))
            return math.max(0.10, 1.0 - (frac ^ 1.6))
        end
        return 1.0
    end

    local supplyF = 1.0
    if _adgSupplyEnabled() then
      supplyF = supplyFactorBarn(e, species, counts)
    end

    local function adgFor(stage, w)
        local a = 0.10 * barnNut
        if PN_Core and PN_Core.adgFor then
            local okG, g = pcall(PN_Core.adgFor, PN_Core, species, stage, w or 0, barnNut)
            if okG and type(g) == "number" then a = g end
        end
        a = a * maturityReserve(species, w) * (supplyF or 1.0)
        local allowNeg = (PN_Settings and PN_Settings.adg and PN_Settings.adg.allowNegative == true)
        if allowNeg then
          local deficit = 1 - (supplyF or 1.0)
          if deficit > 0 then
            local penalty = ((PN_Settings.adg.starvationPenaltyKg or 0.05) * deficit)
            a = a - penalty
          end
        else
          if a < 0 then a = 0 end
        end
        return a
    end

    local rows = {
        { key="female-open", n=counts.femaleOpen, avgW=avgW.femaleOpen, stage=stageFor("femaleOpen"), preg=0 },
        { key="female-preg", n=counts.femalePreg, avgW=avgW.femalePreg, stage=stageFor("femalePreg"), preg=counts.femalePreg },
        { key="male",        n=counts.male,       avgW=avgW.male,       stage=stageFor("male"),       preg=0 },
    }

    for _, r in ipairs(rows) do
        if (r.n or 0) > 0 then
            local g = adgFor(r.stage, r.avgW)
            if r.key ~= "male" then
                Logging.info("[PN] %s [%s/%s] | stage=%s | head=%d preg=%d | avgW=%.2fkg | Nut=%d%% | ADG=%.3f kg/d",
                    name, species, r.key, r.stage, r.n, (r.preg or 0), r.avgW, math.floor(barnNut*100 + 0.5), g)
            else
                Logging.info("[PN] %s [%s/%s] | stage=%s | head=%d | avgW=%.2fkg | Nut=%d%% | ADG=%.3f kg/d",
                    name, species, r.key, r.stage, r.n, r.avgW, math.floor(barnNut*100 + 0.5), g)
            end
        end
    end
end

function PN_Debug:cmdSim(idxStr, spanStr)
    if PN_HusbandryScan == nil or PN_HusbandryScan.getAll == nil or PN_Core == nil or PN_Core.updateHusbandry == nil then
        Logging.info("[PN] pnSim: PN not ready")
        return
    end
    local idx = tonumber(idxStr or "")
    if idx == nil then
        Logging.info("[PN] Usage: pnSim <index> <hours|e.g. 6 or 0.5d for days>  (see pnDumpHusbandries)")
        return
    end
    local list = PN_HusbandryScan.getAll()
    local e = list[idx]
    if not e or not e.clusterSystem then
        Logging.info("[PN] pnSim: no entry/cluster at index %s", tostring(idx))
        return
    end

    local hours = tonumber(spanStr or "")
    if not hours then
        -- allow suffix 'd' for days
        local s = tostring(spanStr or ""):lower()
        local num = tonumber(s:match("^([%d%.]+)d$") or "")
        if num then hours = num * 24 end
    end
    if not hours or hours <= 0 then
        Logging.info("[PN] pnSim: please provide a positive number of hours (e.g. 6) or days (e.g. 0.5d)")
        return
    end

    local dtMs = math.floor(hours * 60 * 60 * 1000)  -- ms in the simulated window
    pcall(PN_Core.updateHusbandry, PN_Core, e, e.clusterSystem, dtMs, { forceBeat = true })

    -- Show the result immediately
    local name    = tostring(e.name or "?")
    local last    = e.__pn_last or {}
    local nutPct  = math.floor((last.nutRatio or 1) * 100 + 0.5)
    local adg     = last.effADG or 0
    local t       = e.__pn_totals or {}
    Logging.info("[PN] SIM '%s' %s | dT=%sh | Nut=%d%% | ADG=%.2f kg/d | head=%d avgW=%.2f kg",
    name, (last.species or "?"), tostring(hours), nutPct, adg, (t.animals or 0), (t.avgWeight or 0))

end

function PN_Debug:cmdClearFeed(idxStr, pctStr)
  if PN_HusbandryScan == nil or PN_HusbandryScan.getAll == nil then
    Logging.info("[PN] pnClearFeed: PN not ready"); return
  end
  local idx = tonumber(idxStr or "")
  if idx == nil then
    Logging.info("[PN] Usage: pnClearFeed <index> [percent 0..100]  (see pnDumpHusbandries)"); return
  end
  local pct = tonumber(pctStr or "100") or 100
  if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
  local list = PN_HusbandryScan.getAll()
  local e = list and list[idx]
  if not e then Logging.info("[PN] pnClearFeed: no entry at index %s", tostring(idx)); return end

  local p = (e.placeable or e)
  local removedL = 0

  local function _massPerL(ftIndex)
    if g_fillTypeManager and g_fillTypeManager.fillTypes and g_fillTypeManager.fillTypes[ftIndex] then
      return tonumber(g_fillTypeManager.fillTypes[ftIndex].massPerLiter or 1.0) or 1.0
    end
    return 1.0
  end

  -- Try API first (preferred), otherwise fall back to raw table edits
  local canAPI = (p.addFillUnitFillLevel ~= nil)

  -- 1) spec_fillUnit per-unit levels
  if p.spec_fillUnit and p.spec_fillUnit.fillUnits then
    for unitIndex, fu in ipairs(p.spec_fillUnit.fillUnits) do
      local levels = fu and fu.fillLevels
      if type(levels) == "table" then
        for ftIndex, liters in pairs(levels) do
          local L = tonumber(liters or 0) or 0
          if L > 0 then
            local take = L * (pct/100)
            if canAPI then
              p:addFillUnitFillLevel(nil, unitIndex, -take, ftIndex, ToolType.UNDEFINED)
            else
              levels[ftIndex] = L - take
            end
            removedL = removedL + take
          end
        end
      end
    end
  end

  -- 2) spec_husbandryFood aggregate levels (fallback)
  if p.spec_husbandryFood and p.spec_husbandryFood.fillLevels then
    for ftIndex, liters in pairs(p.spec_husbandryFood.fillLevels) do
      local L = tonumber(liters or 0) or 0
      if L > 0 then
        local take = L * (pct/100)
        p.spec_husbandryFood.fillLevels[ftIndex] = L - take
        removedL = removedL + take
      end
    end
  end

  -- Refresh PN snapshot so overlay updates right away
  if PN_Core and PN_Core.updateHusbandry and e and e.clusterSystem then
    pcall(PN_Core.updateHusbandry, PN_Core, e, e.clusterSystem, 33, { source="pnClearFeed" })
  end

  Logging.info("[PN] Cleared %.0f%% feed in '%s' (%.0f L total; ~%.0f kg)", pct, tostring(e.name or "?"),
    removedL, removedL * _massPerL(1))
end

-- pnCredit <index> <FILLTYPE_NAME> <kg>
function PN_Debug:cmdCredit(idxStr, ftName, kgStr)
  local idx = tonumber(idxStr or "")
  local kg  = tonumber(kgStr or "")
  if not idx or not ftName or not kg or kg <= 0 then
    Logging.info("[PN] Usage: pnCredit <index> <FILLTYPE_NAME> <kg>")
    return
  end
  local list = PN_HusbandryScan.getAll()
  local e = list[idx]
  if not e or not e.clusterSystem then
    Logging.info("[PN] pnCredit: no entry/cluster at %s", tostring(idx))
    return
  end
  if not g_fillTypeManager or not g_fillTypeManager.getFillTypeIndexByName then
    Logging.info("[PN] pnCredit: fillTypeManager not available")
    return
  end
  local ftIndex = g_fillTypeManager:getFillTypeIndexByName(ftName)
  if not ftIndex then
    Logging.info("[PN] pnCredit: unknown fill type '%s'", tostring(ftName))
    return
  end
  -- one-shot heartbeat with injected intake
  local ctx = { injectIntake = { [ftIndex] = kg } }
  pcall(PN_Core.updateHusbandry, PN_Core, e, e.clusterSystem, 33, ctx)
  if PN_Core.formatBeatLine then
    Logging.info("[PN] %s", PN_Core.formatBeatLine(e))
  end
end

-- =========================================================
-- UI / toggles / settings
-- =========================================================
-- Set heartbeat period or disable it: pnHeartbeat <ms|off>
function PN_Debug:cmdHeartbeat(periodStr)
    if periodStr == nil or periodStr == "" then
        Logging.info("[PN] pnHeartbeat usage: pnHeartbeat <milliseconds|off>. Current=%s",
            tostring(PN_HEARTBEAT_MS))
        return
    end
    if tostring(periodStr):lower() == "off" then
        PN_HEARTBEAT_MS = math.huge  -- effectively disables periodic logging
        Logging.info("[PN] Heartbeat disabled (pnBeat still works).")
        return
    end
    local ms = tonumber(periodStr)
    if not ms or ms < 100 then
        Logging.info("[PN] pnHeartbeat: please provide milliseconds >= 100 or 'off'")
        return
    end
    PN_HEARTBEAT_MS = ms
    Logging.info("[PN] Heartbeat set to every %d ms.", ms)
end

function PN_Debug:cmdOverlayMine(state)
    if PN_UI == nil then
        Logging.info("[PN] pnOverlayMine: PN_UI not available")
        return
    end
    local s = tostring(state or ""):lower()
    if s == "on" or s == "true" or s == "1" then
        PN_UI.onlyMyFarm = true
    elseif s == "off" or s == "false" or s == "0" or s == "all" then
        PN_UI.onlyMyFarm = false
    else
        -- toggle if no/unknown arg
        PN_UI.onlyMyFarm = not (PN_UI.onlyMyFarm == true)
    end
    local mode = (PN_UI.onlyMyFarm and "My Farm Only" or "All Farms")
    Logging.info("[PN] Overlay ownership filter now: %s", mode)
end

-- Toggle overlay from console
function PN_Debug:cmdOverlay()
    if PN_UI and PN_UI.toggle then PN_UI.toggle() end
end

function PN_Debug:cmdPNReload()
    if not PN_Settings or not PN_Settings.load or not PN_Core or not PN_Core.init then
        Logging.info("[PN] pnPNReload: PN not ready"); return
    end
    local cfg = PN_Settings.load()
    PN_Core.init(cfg)
    Logging.info("[PN] Reloaded PN settings (including external XML packs).")
end

function PN_Debug:cmdIntakeDebug(state)
    local s = tostring(state or ""):lower()
    if s == "on" or s == "true" or s == "1" then
        _G.PN_INTAKE_DEBUG = true
    elseif s == "off" or s == "false" or s == "0" then
        _G.PN_INTAKE_DEBUG = false
    else
        _G.PN_INTAKE_DEBUG = not (_G.PN_INTAKE_DEBUG == true)
    end
    Logging.info("[PN] Intake debug is %s", (_G.PN_INTAKE_DEBUG and "ON" or "OFF"))
end

-- Set PN_Logger level from console (TRACE|DEBUG|INFO|WARN|ERROR)
function PN_Debug:cmdSetLogLevel(level)
    if PN_Logger and PN_Logger.setLevel then
        PN_Logger:setLevel(level)
    else
        Logging.info("[PN] Logger not available; level not changed.")
    end
end

-- =========================================================
-- Extra debug conveniences
-- =========================================================
function PN_Debug:cmdListMods()
    local mm = g_modManager
    if not mm or not mm.mods then
        Logging.info("[PN] No mod manager or mods list.")
        return
    end
    Logging.info("[PN] Active mods:")
    for _,m in ipairs(mm.mods) do
        local dir = m.modDir or "?"
        local title = m.title or m.name or "?"
        Logging.info(string.format("  - %s  (%s)", dir, title))
    end
end

function PN_Debug:cmdDumpFillTypes()
    local fm = g_fillTypeManager
    if not fm then Logging.info("[PN] No fillTypeManager"); return end
    local names = {
        "GRASS","HAY","SILAGE","STRAW","MAIZE","CORN","WHEAT","BARLEY","OAT",
        "SORGHUM","SOYBEAN","PEA","PEAS","CHICKPEA","CHICKPEAS","CANOLA","FLAX",
        "RYE","TRITICALE","ALFALFA","ALFALFA_HAY","ALFALFA_SILAGE"
    }
    Logging.info("[PN] FillType presence:")
    for _,n in ipairs(names) do
        local idx = fm:getFillTypeByName(n)
        if idx then
            local title = fm.getFillTypeTitleByIndex and (fm:getFillTypeTitleByIndex(idx) or "")
            Logging.info(string.format("  %s -> id %d %s", n, idx, title ~= "" and ("(title="..title..")") or ""))
        else
            Logging.info(string.format("  %s -> MISSING", n))
        end
    end
end

-- Aliases to clarify meaning
-- (cmdBeat = one-shot tick; cmdHeartbeat = set heartbeat period)
PN_Debug.cmdHeartbeatTick = PN_Debug.cmdBeat
PN_Debug.cmdHeartbeatSet  = PN_Debug.cmdHeartbeat

-- =====================
-- Console registration
-- =====================
if addConsoleCommand ~= nil then
    -- Lists / CSV exports
    addConsoleCommand("pnDumpHusbandries",    "List PN-scanned husbandries",                  "cmdDumpHusbandries",    PN_Debug)
    addConsoleCommand("pnDumpHusbandriesCSV", "Export PN-scanned husbandries to CSV",         "cmdDumpHusbandriesCSV", PN_Debug)

    -- Inspectors
    addConsoleCommand("pnInspect",            "Inspect PN entry (alias of pnInspectHusbandry)","cmdInspectHusbandry",  PN_Debug)
    addConsoleCommand("pnInspectHusbandry",   "Inspect PN entry (by index)",                   "cmdInspectHusbandry",  PN_Debug)
    addConsoleCommand("pnInspectClusters",    "Inspect clusters for a PN entry",               "cmdInspectClusters",   PN_Debug)
    addConsoleCommand("pnInspectTrough",      "Inspect trough fillUnits/levels",               "cmdInspectTrough",     PN_Debug)
    addConsoleCommand("pnInspectFoodSpec",    "Dump spec_husbandryFood levels",                "cmdInspectFoodSpec",   PN_Debug)

    -- Feeder finder
    addConsoleCommand("pnFindFeeder",         "Find a nearby feeder (fillUnit) for the entry", "cmdFindFeeder",        PN_Debug)

    -- One-shot nutrition tick / simulation
    addConsoleCommand("pnBeat",               "Trigger one PN heartbeat for an entry",         "cmdHeartbeatTick",     PN_Debug)
    addConsoleCommand("pnSim",                "Simulate PN for an entry over hours/days",      "cmdSim",               PN_Debug)

    -- Feed + nutrition controls
    addConsoleCommand("pnClearFeed",          "Clear/Reduce trough feed % for an entry",       "cmdClearFeed",         PN_Debug)
    addConsoleCommand("pnNut",                "Set/view barn nutrition ratio (0..1)",          "cmdNut",               PN_Debug)
    addConsoleCommand("pnCredit",             "Credit intake to a barn (kg)",                  "cmdCredit",            PN_Debug)
    addConsoleCommand("pnAutoConsume",        "Toggle PN auto consumption (on/off)",           "cmdAutoConsume",       PN_Debug)
    addConsoleCommand("pnIntakeDebug",        "Toggle PN intake debug (on/off)",               "cmdIntakeDebug",       PN_Debug)

    -- UI / reload / heartbeat period / logging
    addConsoleCommand("pnOverlay",            "Toggle PN overlay",                              "cmdOverlay",           PN_Debug)
    addConsoleCommand("pnOverlayMine",        "Filter overlay to my farm only (on/off|all)",    "cmdOverlayMine",       PN_Debug)
    addConsoleCommand("pnPNReload",           "Reload PN settings/XML packs",                   "cmdPNReload",          PN_Debug)
    addConsoleCommand("pnHeartbeat",          "Set heartbeat period ms (or 'off')",             "cmdHeartbeatSet",      PN_Debug)
    addConsoleCommand("pnSetLogLevel",        "Set PN log level (TRACE|DEBUG|INFO|WARN|ERROR)", "cmdSetLogLevel",       PN_Debug)

    -- Diagnostics & fixers
    addConsoleCommand("pnDiag",               "Print PN module readiness",                      "cmdDiag",              PN_Debug)
    addConsoleCommand("pnFixEvents",          "Restore PN_Events methods if clobbered",         "cmdFixEvents",         PN_Debug)

    Logging.info("[PN] Console commands registered (debug).")
else
    Logging.info("[PN] Console: addConsoleCommand not available at load")
end

