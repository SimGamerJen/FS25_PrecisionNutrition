-- PN_Config.lua — external config for FS25_PrecisionNutrition overlay
-- Persists UI settings to:  <User>/My Games/FarmingSimulator2025/modSettings/FS25_PrecisionNutrition/<name>.xml
-- Default file is "config.xml" and we maintain a simple index for listing: PN_Config_index.xml

PN_Config = {
    dir  = nil,
    _ver = 1,
}

-- Use a safe, engine-tolerant separator. GIANTS accepts "/" on Windows.
local SEP = "/"

local function _userPath()
    if getUserProfileAppPath ~= nil then
        return getUserProfileAppPath()
    end
    return "" -- fallback for tools/tests
end

local function _join(a, b)
    if a == nil or a == "" then return tostring(b or "") end
    if b == nil or b == "" then return tostring(a or "") end
    -- remove trailing/leading slashes to avoid doubles
    a = tostring(a):gsub("[/\\]+$", "")
    b = tostring(b):gsub("^[/\\]+", "")
    return a .. SEP .. b
end

local function _ensureDir(path)
    if createFolder ~= nil then
        -- GIANTS API; returns true or 0 on success depending on engine build
        local ok = createFolder(path)
        return (ok == true or ok == 0)
    end
    -- If unavailable (unit tests), just assume true
    return true
end

local function _fileExists(path)
    if fileExists ~= nil then
        return fileExists(path)
    end
    local f = io.open(path, "rb")
    if f ~= nil then f:close(); return true end
    return false
end

function PN_Config:init()
    if self.dir ~= nil then return end
    local base = _userPath()
    -- <user>/My Games/FarmingSimulator2025/modSettings/FS25_PrecisionNutrition
    self.dir = _join(_join(_join(base, "modSettings"), "FS25_PrecisionNutrition"), "")
    _ensureDir(_join(base, "modSettings"))
    _ensureDir(self.dir)
end

local function _mkPath(name)
    PN_Config:init()
    name = tostring(name or "config")
    -- sanitize to safe filename
    name = name:gsub("[^%w%._%-]", "_")
    if name == "" then name = "config" end
    if not name:lower():match("%.xml$") then name = name .. ".xml" end
    return _join(PN_Config.dir, name)
end

-- ---- Simple index for listing without directory APIs -----------------------

local function _indexPath()
    PN_Config:init()
    return _mkPath("PN_Config_index.xml")
end

local function _readIndex()
    local list = {}
    local set  = {}
    local p = _indexPath()
    if XMLFile ~= nil and XMLFile.load ~= nil and _fileExists(p) then
        local xml = XMLFile.load("pnCfgIndexLoad", p, "pnIndex")
        if xml ~= nil then
            local i = 0
            while true do
                local key = string.format("pnIndex.file(%d)", i)
                if not xml:hasProperty(key) then break end
                local n = xml:getString(key .. "#name")
                if n and n ~= "" and not set[n] then
                    table.insert(list, n)
                    set[n] = true
                end
                i = i + 1
            end
            xml:delete()
        end
    end
    return list, set
end

local function _writeIndex(list)
    local p = _indexPath()
    if XMLFile == nil or XMLFile.create == nil then return end
    local xml = XMLFile.create("pnCfgIndexSave", p, "pnIndex")
    if xml == nil then return end
    for i, n in ipairs(list or {}) do
        local key = string.format("pnIndex.file(%d)", i - 1)
        xml:setString(key .. "#name", n)
    end
    xml:save()
    xml:delete()
end

local function _indexAdd(name)
    local list, set = _readIndex()
    if not set[name] then
        table.insert(list, name)
        _writeIndex(list)
    end
end

-- ---- Public read/apply/save/load ------------------------------------------

-- Returns table with UI overlay + cfg fields
function PN_Config:read(name)
    local path = _mkPath(name)
    local t = { ui = {}, cfg = {} }
    if XMLFile == nil or XMLFile.load == nil or not _fileExists(path) then
        return t, path, false
    end
    local xml = XMLFile.load("pnCfgLoad", path, "pn")
    if xml == nil then
        return t, path, false
    end
    t._ver = xml:getInt("pn#ver", 1)

    -- UI
    t.ui.anchor   = xml:getString("pn.ui#anchor") or nil
    t.ui.alpha    = xml:getFloat ("pn.ui#alpha")  or nil
    t.ui.maxRows  = xml:getInt   ("pn.ui#maxRows") or nil
    t.ui.marginX  = xml:getFloat ("pn.ui#marginX") or nil
    t.ui.marginY  = xml:getFloat ("pn.ui#marginY") or nil
    t.ui.fontSize = xml:getFloat ("pn.ui#font")    or nil
    t.ui.rowH     = xml:getFloat ("pn.ui#rowH")    or nil
    t.ui.padX     = xml:getFloat ("pn.ui#padX")    or nil
    t.ui.padY     = xml:getFloat ("pn.ui#padY")    or nil
    -- Width controls are optional; nil means "auto"
    if xml:hasProperty("pn.ui#fixedW") then t.ui.fixedW = xml:getFloat("pn.ui#fixedW") end
    if xml:hasProperty("pn.ui#minW")   then t.ui.minW   = xml:getFloat("pn.ui#minW")   end
    if xml:hasProperty("pn.ui#maxW")   then t.ui.maxW   = xml:getFloat("pn.ui#maxW")   end
    if xml:hasProperty("pn.ui#enabled") then t.ui.enabled = xml:getBool("pn.ui#enabled") end
    t.ui.mode     = xml:getString("pn.ui#mode") or nil

    -- Behavioural cfg (optional)
    local hasRefresh = xml:hasProperty("pn.cfg#refreshMs")
    if hasRefresh then t.cfg.refreshThrottleMs = xml:getInt("pn.cfg#refreshMs") end
    if xml:hasProperty("pn.cfg#spacer")        then t.cfg.addSpacerBetweenBarns = xml:getBool("pn.cfg#spacer") end
    if xml:hasProperty("pn.cfg#preferLive")    then t.cfg.preferLiveRows        = xml:getBool("pn.cfg#preferLive") end
    if xml:hasProperty("pn.cfg#useSupplyFactor") then t.cfg.useSupplyFactor     = xml:getBool("pn.cfg#useSupplyFactor") end

    xml:delete()
    return t, path, true
end

-- Applies a config table (t.ui, t.cfg) to PN_UI
function PN_Config:applyToUI(t)
    if PN_UI == nil or t == nil then return end

    if t.ui.enabled ~= nil then PN_UI.enabled = (t.ui.enabled == true) end
    if t.ui.mode    ~= nil then PN_UI.mode    = t.ui.mode end

    PN_UI.ov = PN_UI.ov or {}
    local o = PN_UI.ov
    o.anchor   = (t.ui.anchor   ~= nil) and t.ui.anchor   or o.anchor
    o.alpha    = (t.ui.alpha    ~= nil) and t.ui.alpha    or o.alpha
    o.maxRows  = (t.ui.maxRows  ~= nil) and t.ui.maxRows  or o.maxRows
    o.marginX  = (t.ui.marginX  ~= nil) and t.ui.marginX  or o.marginX
    o.marginY  = (t.ui.marginY  ~= nil) and t.ui.marginY  or o.marginY
    o.fontSize = (t.ui.fontSize ~= nil) and t.ui.fontSize or o.fontSize
    o.rowH     = (t.ui.rowH     ~= nil) and t.ui.rowH     or o.rowH
    o.padX     = (t.ui.padX     ~= nil) and t.ui.padX     or o.padX
    o.padY     = (t.ui.padY     ~= nil) and t.ui.padY     or o.padY
    if t.ui.fixedW ~= nil then o.fixedW = t.ui.fixedW end
    if t.ui.minW   ~= nil then o.minW   = t.ui.minW   end
    if t.ui.maxW   ~= nil then o.maxW   = t.ui.maxW   end

    PN_UI.cfg = PN_UI.cfg or {}
    local c = PN_UI.cfg
    if t.cfg.refreshThrottleMs     ~= nil then c.refreshThrottleMs     = t.cfg.refreshThrottleMs end
    if t.cfg.addSpacerBetweenBarns ~= nil then c.addSpacerBetweenBarns = t.cfg.addSpacerBetweenBarns end
    if t.cfg.preferLiveRows        ~= nil then c.preferLiveRows        = t.cfg.preferLiveRows end
    if t.cfg.useSupplyFactor       ~= nil then c.useSupplyFactor       = t.cfg.useSupplyFactor end
end

-- Saves PN_UI.ov (+ enabled/mode) and PN_UI.cfg essentials to <name>.xml
function PN_Config:saveUI(name)
    local path = _mkPath(name)
    if XMLFile == nil or XMLFile.create == nil then
        return false, "xml-api-missing", path
    end
    local xml = XMLFile.create("pnCfgSave", path, "pn")
    if xml == nil then
        return false, "create-failed", path
    end

    xml:setInt("pn#ver", self._ver)

    local o = PN_UI and PN_UI.ov or {}
    local c = PN_UI and PN_UI.cfg or {}

    xml:setString("pn.ui#anchor",    tostring(o.anchor or "tr"))
    xml:setFloat ("pn.ui#alpha",     tonumber(o.alpha or 0.40) or 0.40)
    xml:setInt   ("pn.ui#maxRows",   tonumber(o.maxRows or 14) or 14)
    xml:setFloat ("pn.ui#marginX",   tonumber(o.marginX or 0.500) or 0.500)
    xml:setFloat ("pn.ui#marginY",   tonumber(o.marginY or 0.030) or 0.030)
    xml:setFloat ("pn.ui#font",      tonumber(o.fontSize or 0.016) or 0.016)
    xml:setFloat ("pn.ui#rowH",      tonumber(o.rowH or 0.018) or 0.018)
    xml:setFloat ("pn.ui#padX",      tonumber(o.padX or 0.010) or 0.010)
    xml:setFloat ("pn.ui#padY",      tonumber(o.padY or 0.010) or 0.010)

    -- Only write width keys when explicitly set (lets "auto" remain auto)
    if o.fixedW ~= nil then xml:setFloat("pn.ui#fixedW", tonumber(o.fixedW) or o.fixedW) end
    if o.minW   ~= nil then xml:setFloat("pn.ui#minW",   tonumber(o.minW)   or o.minW)   end
    if o.maxW   ~= nil then xml:setFloat("pn.ui#maxW",   tonumber(o.maxW)   or o.maxW)   end

    xml:setBool  ("pn.ui#enabled",  PN_UI and (PN_UI.enabled == true) or false)
    xml:setString("pn.ui#mode",     tostring(PN_UI and PN_UI.mode or "list"))

    xml:setInt   ("pn.cfg#refreshMs", tonumber(c.refreshThrottleMs or 250) or 250)
    xml:setBool  ("pn.cfg#spacer",     c.addSpacerBetweenBarns == true)
    xml:setBool  ("pn.cfg#preferLive", c.preferLiveRows == true)
    xml:setBool  ("pn.cfg#useSupplyFactor", c.useSupplyFactor == true)

    xml:save()
    xml:delete()

    -- Maintain the index so pnOverlay list works without directory APIs
    local fname = path:match("([^/\\]+)$") or "config.xml"
    _indexAdd(fname)

    return true, nil, path
end

-- Loads from <name>.xml and applies to PN_UI
function PN_Config:loadUI(name)
    local t, path, ok = self:read(name)
    if not ok then return false, "not-found", path end
    self:applyToUI(t)
    if PN_UI ~= nil then PN_UI._nextRefreshAt = 0 end

    -- If it exists but isn't in index yet, add it for future listing
    local fname = path:match("([^/\\]+)$") or "config.xml"
    _indexAdd(fname)

    return true, nil, path
end

-- Lists available configs from our maintained index
function PN_Config:list()
    local list = _readIndex()
    return list
end
