-- ===================================================================
-- ArcUI_DurationText.lua
-- Thin wrapper over 12.0.7's C_DurationUtil.CreateDurationTextBinding.
--
-- A DurationTextBinding makes Blizzard drive a FontString's countdown text
-- entirely C-side — no Lua OnUpdate. We bind a (secret-safe) duration object
-- once and reapply it whenever it changes; Blizzard formats + updates the text
-- on its own interval. This replaces the per-bar 10fps "GetRemainingDuration()
-- -> SetText" OnUpdate handlers (category A of the bar OnUpdate audit).
--
-- Feature-probed: on a client without these APIs, IsSupported() is false and
-- callers keep their existing OnUpdate path. Verified against live 12.0.7.68235:
--   C_DurationUtil.CreateDurationTextBinding() -> binding
--   binding:SetFontString(fs) / :SetDuration(durObj) / :SetFormatter(numFmt)
--   binding:SetUpdateInterval(s) / :SetZeroDurationText / :SetExpiredText
--   binding:Enable() / :Disable()
--   C_StringUtil.CreateNumericRuleFormatter():AddBreakpoint{threshold,format}
-- ===================================================================

local ADDON, ns = ...
ns = ns or {}
ns.DurationText = ns.DurationText or {}
local DT = ns.DurationText

local supported = (C_DurationUtil and C_DurationUtil.CreateDurationTextBinding
                   and C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) and true or false

function DT.IsSupported()
  return supported
end

-- Shared numeric formatters keyed by decimal count. A single breakpoint at
-- threshold 0 with a "%.Nf" format reproduces ArcUI's existing plain-decimal
-- look exactly (e.g. "12.3"), so there is no visible change.
local formatters = {}
local function GetFormatter(decimals)
  decimals = decimals or 1
  local f = formatters[decimals]
  if not f then
    f = C_StringUtil.CreateNumericRuleFormatter()
    f:AddBreakpoint({ threshold = 0, format = "%." .. decimals .. "f" })
    formatters[decimals] = f
  end
  return f
end

-- Bind (or refresh) a FontString to a duration object so Blizzard drives its
-- countdown text. The binding is created once and cached on the FontString
-- (an ArcUI-created region, so writing a field on it is taint-safe); later
-- calls just reapply the duration / formatter. Returns true on success.
function DT.Bind(fs, durObj, decimals)
  if not supported or not fs or not durObj then return false end
  local b = fs._arcDurBinding
  if not b then
    b = C_DurationUtil.CreateDurationTextBinding()
    b:SetFontString(fs)
    b:SetZeroDurationText("")
    b:SetExpiredText("")
    b:SetUpdateInterval(0.1)   -- 10fps, matches the cadence of the old OnUpdate
    fs._arcDurBinding = b
    fs._arcDurDecimals = nil
  end
  if fs._arcDurDecimals ~= decimals then
    b:SetFormatter(GetFormatter(decimals))
    fs._arcDurDecimals = decimals
  end
  -- Re-applying the duration on the existing binding restarts the C-side
  -- countdown (proven: bars on the full UpdateBar path refresh correctly on aura
  -- reapply). Callers must RE-CALL Bind whenever the duration changes; the bug
  -- where the text stuck on the old value was a caller skipping this re-bind, not
  -- the binding itself.
  b:SetDuration(durObj)        -- secret durObj is a safe sink
  b:Enable()
  return true
end

-- Stop driving a FontString (aura/totem gone). Keeps the binding cached for
-- reuse and blanks the text.
function DT.Unbind(fs)
  if not fs then return end
  local b = fs and fs._arcDurBinding
  if b then b:Disable() end
  if fs.SetText then fs:SetText("") end
end
