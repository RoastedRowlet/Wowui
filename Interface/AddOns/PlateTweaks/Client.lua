local _, NS = ...

-- Which client this is. Loaded first, before anything that branches on it.
--
-- WoW Forever runs the retail 12.1 engine -- same frames, same AuraContainer,
-- same secret values -- with vanilla content on top, and reports a 1.60+
-- interface number (16001). Classic Era reports 115xx and retail 12xxxx, so
-- the ranges never meet.
--
-- What differs on Forever, and is handled where it bites:
--   * One specialization per class, with no role. Spec-keyed profile bindings
--     need nothing; the threat "auto" role reads stance and form instead
--     (Threat.lua).
--   * Spell ranks. Every rank of Corruption is its own spell ID and its own
--     aura ID, so a rule built on one rank must match all of them
--     (NS.ForeverRankIDs, Spells.lua).
--
-- Fail-open: if the interface number cannot be read, this is retail.

local iface = select(4, GetBuildInfo())
NS.INTERFACE = type(iface) == "number" and iface or nil
NS.IS_FOREVER = NS.INTERFACE ~= nil and NS.INTERFACE >= 16000 and NS.INTERFACE < 20000

-- RegisterEvent throws on an event the client does not define. Forever shares
-- the retail engine, so these should all exist there, but a missing one must
-- cost that one event rather than the whole load path.
function NS.SafeRegisterEvent(frame, event)
  local ok = pcall(frame.RegisterEvent, frame, event)
  return ok
end
