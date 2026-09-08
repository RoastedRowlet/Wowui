local _, NS = ...

-- Load conditions: WHERE a rule is allowed to exist, as opposed to when it
-- lights up.
--
-- A rule's conditions answer "is this debuff on the mob". This answers a
-- question that has nothing to do with the mob at all: am I in a raid, am I
-- solo, is this a delve. Those change rarely -- a zone-in, a group change --
-- so they are not a per-plate test but a BUILD-TIME filter: a rule whose
-- context does not match is not built, costs no draw slot, and reappears on
-- the next zone-in that matches.
--
-- Two independent lists, not one:
--
--   zones   where you are   (world, dungeon, Mythic+, delve, raid, PvP)
--   groups  who you are with (solo, in a party, in a raid)
--
-- Within a list the entries are OR -- "dungeons or delves". Between the two
-- lists it is AND -- "dungeons, and only while in a party". Both empty means
-- everywhere, which is what every existing rule has and what a new one gets,
-- so nothing changes for a profile that never opens this.

local EMPTY = {}

-- Difficulty IDs. Named rather than inlined: 8 and 208 mean nothing at a
-- glance, and the raid set is four numbers that are easy to transpose.
local DIFFICULTY_MYTHIC_PLUS = 8
local DIFFICULTY_DELVE       = 208
local RAID_DIFFICULTY = {
  [17] = "raidLFR",
  [14] = "raidNormal",
  [15] = "raidHeroic",
  [16] = "raidMythic",
}

-- The zone list, in the order it is shown. `key` is what is stored.
NS.LOAD_ZONES = {
  { key = "world",       label = "Open world" },
  { key = "dungeon",     label = "Dungeon (normal/heroic)" },
  { key = "mythicplus",  label = "Mythic+" },
  { key = "delve",       label = "Delve" },
  { key = "scenario",    label = "Scenario" },
  { key = "raidLFR",     label = "Raid -- Looking For Raid" },
  { key = "raidNormal",  label = "Raid -- Normal" },
  { key = "raidHeroic",  label = "Raid -- Heroic" },
  { key = "raidMythic",  label = "Raid -- Mythic" },
  { key = "battleground", label = "Battleground" },
  { key = "arena",       label = "Arena" },
}

NS.LOAD_GROUPS = {
  { key = "solo",  label = "Solo" },
  { key = "party", label = "In a party" },
  { key = "raid",  label = "In a raid" },
}

local ZONE_LABEL, GROUP_LABEL = {}, {}
for _, zone in ipairs(NS.LOAD_ZONES) do ZONE_LABEL[zone.key] = zone.label end
for _, group in ipairs(NS.LOAD_GROUPS) do GROUP_LABEL[group.key] = group.label end

-- Cached, because this is asked once per rule per rebuild and the answer
-- changes on a zone-in. Cleared by NS.InvalidateLoadContext from the events in
-- Core.lua rather than expiring on a timer: a stale answer here silently
-- builds the wrong rules, and the events that can change it are known.
local cachedZone, cachedGroup

function NS.InvalidateLoadContext()
  cachedZone, cachedGroup = nil, nil
end

-- Did the answer actually change?
--
-- The events that can change it are not rare: GROUP_ROSTER_UPDATE fires on
-- every roster change and repeatedly around a zone-in, and most of those
-- firings leave both answers exactly as they were. Rebuilding on the EVENT
-- rather than on the change meant a raid produced a near-permanent rebuild
-- backlog -- in combat a rebuild cannot run, so it is deferred, and the next
-- opening tears down and re-registers every aura container on every plate.
-- The missing ladder's chains are the ones that notice: they carry secure
-- containers whose buttons repopulate on registration.
--
-- So this recomputes both answers and reports whether either moved. Cheap
-- enough to run on every firing, which is the point.
function NS.LoadContextChanged()
  local zone, group = cachedZone, cachedGroup
  cachedZone, cachedGroup = nil, nil
  local newZone, newGroup = NS.CurrentLoadZone(), NS.CurrentLoadGroup()
  -- First ask of the session: nothing to compare against, and nothing has
  -- been built off the old answer either.
  if zone == nil and group == nil then return false end
  return zone ~= newZone or group ~= newGroup
end

-- Where you are, as one of the LOAD_ZONES keys.
--
-- Unknown raid difficulties (timewalking, and whatever ships next) read as
-- Normal rather than as no raid at all: a rule set to raids should fire in a
-- raid the addon has not been taught about yet, and the alternative is a rule
-- that silently stops working after a patch.
function NS.CurrentLoadZone()
  if cachedZone then return cachedZone end
  local ok, _, instanceType, difficultyID = pcall(GetInstanceInfo)
  if not ok then return "world" end
  local zone
  if instanceType == "party" then
    zone = (difficultyID == DIFFICULTY_MYTHIC_PLUS) and "mythicplus" or "dungeon"
  elseif instanceType == "raid" then
    zone = RAID_DIFFICULTY[difficultyID] or "raidNormal"
  elseif instanceType == "scenario" then
    zone = (difficultyID == DIFFICULTY_DELVE) and "delve" or "scenario"
  elseif instanceType == "pvp" then
    zone = "battleground"
  elseif instanceType == "arena" then
    zone = "arena"
  else
    zone = "world"
  end
  cachedZone = zone
  return zone
end

function NS.CurrentLoadGroup()
  if cachedGroup then return cachedGroup end
  local group = "solo"
  if IsInRaid() then
    group = "raid"
  elseif IsInGroup() then
    group = "party"
  end
  cachedGroup = group
  return group
end

-- The stored shape, created on demand. Two sets of keys.
function NS.NormaliseLoad(load)
  if type(load) ~= "table" then load = {} end
  if type(load.zones) ~= "table" then load.zones = {} end
  if type(load.groups) ~= "table" then load.groups = {} end
  return load
end

function NS.LoadIsRestricted(load)
  if type(load) ~= "table" then return false end
  return next(load.zones or EMPTY) ~= nil or next(load.groups or EMPTY) ~= nil
end

-- Does this load condition allow the situation you are in right now?
--
-- An EMPTY list is not "nothing matches", it is "no opinion". That is the
-- difference between a rule nobody has restricted and a rule someone
-- restricted to a set that happens not to include here.
function NS.LoadAllows(load)
  if type(load) ~= "table" then return true end
  local zones = load.zones
  if zones and next(zones) and not zones[NS.CurrentLoadZone()] then return false end
  local groups = load.groups
  if groups and next(groups) and not groups[NS.CurrentLoadGroup()] then return false end
  return true
end

-- One line for the row and the editor: what this is restricted to, in words.
local function ListNames(set, ordered, labels)
  if not set or not next(set) then return nil end
  local names = {}
  for _, entry in ipairs(ordered) do
    if set[entry.key] then names[#names + 1] = labels[entry.key] end
  end
  return #names > 0 and table.concat(names, ", ") or nil
end

function NS.LoadZoneSummary(load)
  return ListNames((load or EMPTY).zones, NS.LOAD_ZONES, ZONE_LABEL) or "Anywhere"
end

function NS.LoadGroupSummary(load)
  return ListNames((load or EMPTY).groups, NS.LOAD_GROUPS, GROUP_LABEL) or "Any group"
end

function NS.LoadSummary(load)
  if not NS.LoadIsRestricted(load) then return "Always loaded" end
  local zones = ListNames((load or EMPTY).zones, NS.LOAD_ZONES, ZONE_LABEL)
  local groups = ListNames((load or EMPTY).groups, NS.LOAD_GROUPS, GROUP_LABEL)
  if zones and groups then return zones .. "  --  " .. groups end
  return zones or groups
end

-- Menu entries for the multi-select dropdowns.
local function Entries(ordered)
  local out = {}
  for _, entry in ipairs(ordered) do
    out[#out + 1] = { text = entry.label, value = entry.key }
  end
  return out
end

function NS.LoadZoneEntries() return Entries(NS.LOAD_ZONES) end
function NS.LoadGroupEntries() return Entries(NS.LOAD_GROUPS) end
