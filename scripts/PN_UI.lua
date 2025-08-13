-- Simple on-screen debug overlay for Precision Nutrition
PN_UI = {
  enabled = false,
  barns = {},   -- [id] = {name=..., adg=..., intake=..., balance=..., forage=..., stage=..., n=...}
  _debounce = 0
}

-- Safe text draw helper
local function drawLine(x, y, s)
  if renderText ~= nil then
    renderText(x, y, 0.014, s)
  end
end

function PN_UI.toggle()
  PN_UI.enabled = not PN_UI.enabled
  Logging.info("[PN] Overlay %s", PN_UI.enabled and "ON" or "OFF")
end

-- Called by the husbandry patch whenever it computes nutrition for a barn
function PN_UI.pushBarnStat(owner, name, stats)
  local id = tostring(owner or "barn")
  PN_UI.barns[id] = {
    name    = name or ("Barn@"..id),
    adg     = stats.adg or 0,
    intake  = stats.intakePH or 0,
    balance = stats.balance or 0,
    forage  = stats.forageShare or 0,
    stage   = stats.stage or "?",
    n       = stats.n or 0
  }
end

-- Basic key handling: Alt+N to toggle (debounced)
local function checkToggleKey(dt)
  PN_UI._debounce = math.max(0, PN_UI._debounce - dt)
  if PN_UI._debounce > 0 then return end
  if Input ~= nil and Input.isKeyPressed ~= nil then
    local alt = Input.isKeyPressed(Input.KEY_lalt) or Input.isKeyPressed(Input.KEY_ralt)
    local n   = Input.isKeyPressed(Input.KEY_n)
    if alt and n then
      PN_UI._debounce = 300 -- ms
      PN_UI.toggle()
    end
  end
end

-- Hooked from Mission00.update
function PN_UI.onUpdate(dt)
  checkToggleKey(dt)
end

-- Hooked from Mission00.draw
function PN_UI.onDraw()
  if not PN_UI.enabled then return end
  local x, y = 0.02, 0.95
  drawLine(x, y, ("[PN] Precision Nutrition Overlay (Alt+N)")); y = y - 0.02
  for _, v in pairs(PN_UI.barns) do
    local line = string.format("%s | Cows=%d | Stage=%s | ADG=%.2f kg/d | Intake=%.1f /hd/d | Balance=%.2f | Forage=%.0f%%",
      v.name, v.n, v.stage, v.adg, v.intake, v.balance, v.forage*100)
    drawLine(x, y, line); y = y - 0.018
  end
end

return PN_UI
