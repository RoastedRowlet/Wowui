local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Unknown-Unknown','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Havoc','Shaman-Enhancement','Paladin-Holy','Warrior-Protection','Paladin-Retribution','Warrior-Arms','Priest-Shadow','Priest-Discipline','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Monk-Windwalker','Monk-Mistweaver','Warlock-Affliction','Druid-Restoration','Shaman-Elemental','Shaman-Restoration',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abrocklock:BAAANQADCgYICQAAAA==.',
Ad='Adorabull:BAAANQAECgYJDQAAAA==.',
Ae='Aedreline:BAAANQADCgMIAwABNQAECgQICwABAAAAAA==.Aevelee:BAAANQADCggJFQAAAA==.',
Al='Aleeta:BAAANQAECgQIBAAAAA==.',
Am='Amaria:BAAANQAECgQIBQABNQAECgUJCQABAAAAAA==.',
An='Anaki:BAAANQADCgUIBQAAAA==.Anduîiîn:BAAANQADCggICgAAAA==.Antarias:BAAANQAECgMJBgAAAA==.Anubiz:BAAANQADCgEIAQAAAA==.',
Ar='Araydin:BAAANQADCgEIAQAAAA==.Arckenon:BAAANQAECgcJEgAAAA==.Ardarl:BAAANQADCggICAAAAA==.Arranix:BAAANQADCgMIAwAAAA==.Arrica:BAAANQABCgEIAQAAAA==.Artemisv:BAAANQADCgIIAgAAAA==.',
As='Ashog:BAAANQADCgcICgAAAA==.',
At='Atillis:BAAANQADCgYJCwAAAA==.',
Au='Austenpally:BAAANQAECgQIBQAAAA==.',
Av='Aveycado:BAAANQAECgUJCgAAAA==.',
Ax='Axeflack:BAAANQAECgQIBwABNQAECgUIBQABAAAAAA==.Axegor:BAAANQAECgMIBAAAAA==.',
Az='Azaral:BAAANQADCgUJBQABNQAECgQIBAABAAAAAA==.Azmarija:BAAANQADCgEIAgAAAA==.',
Ba='Bacuda:BAAANQADCggJDAAAAA==.',
Bi='Biancadelrio:BAAANQAECgIIAwAAAA==.Bigguberment:BAAANQAECgEJAQAAAA==.',
Bl='Bladekrim:BAAANQADCgcICwAAAA==.Blindashunae:BAAANQADCgEIAQAAAA==.Blitzo:BAAANQADCgMIAwAAAA==.',
Bo='Boomhammer:BAAANQADCgYIBgAAAA==.Boredgored:BAAANQADCgcIBwABNQAECggJFQACACcSAA==.Botia:BAAANQAECgIJAwAAAA==.Bourdeaux:BAAANQADCgcIFQAAAA==.',
Br='Braedia:BAAANQABCgEIAQAAAA==.Brainnmatter:BAAANQADCgEIAQAAAA==.Brashmoore:BAAANQADCgMIAwAAAA==.Brizik:BAAANQABCgUIBQAAAA==.Bruised:BAAANQAECgIIAgAAAA==.Brunae:BAAANQAECgIIAwAAAA==.Brunnera:BAAANQADCgcIDAAAAA==.Bruuenor:BAAANQABCgMIAgAAAA==.Bruul:BAAANQAECgQICQAAAA==.',
Ca='Caenji:BAAANQADCggIDwAAAA==.Captbenson:BAAANQADCgYIAQAAAA==.Carcharoth:BAAANQADCgMIAwAAAA==.Carmelina:BAAANQADCgQIBQAAAA==.Castanthrax:BAAANQADCgQIBAAAAA==.',
Ch='Chadgar:BAABNQAECoEVAAICAAgKJxIBewAkAgACAAgKJxIBewAkAgAAAA==.Chaoshammer:BAAANQADCggICAAAAA==.Chey:BAABNQAECoEYAAMDAAgKYR6xGgDFAQADAAUKSB+xGgDFAQAEAAMK3xwAPAABAQAAAA==.Chipsahoy:BAAANQADCgEIAQAAAA==.Chormage:BAAANQABCgQIBQAAAA==.Chíef:BAAANQAECgMIAwABNQAECgkJGgAFAPQYAA==.',
Cl='Close:BAAANQADCgUIBQABNQAECggIBwABAAAAAA==.',
Co='Conorix:BAAANQADCgcIEwAAAA==.Corvo:BAAANQADCggICAABNQAECgIIAwABAAAAAA==.',
Cr='Crataxxis:BAAANQAECgUJBwAAAA==.',
Cu='Cudara:BAAANQADCgIIAgABNQADCggJDAABAAAAAA==.',
Cy='Cydon:BAAANQAECgQJDQAAAA==.Cythraul:BAAANQAECgIIAwAAAA==.',
Da='Daerith:BAAANQADCgYICgAAAA==.Daerrith:BAAANQADCgYJBgAAAA==.Dagni:BAAANQAECgEIAQAAAA==.Dantey:BAAANQADCgUIBQABNQADCgUIBQABAAAAAA==.Darrwin:BAAANQAECgIIAwAAAA==.',
De='Derrith:BAAANQADCgUIBgAAAA==.',
Df='Dfabness:BAAANQAECgUJDAAAAA==.',
Di='Diizmyster:BAAANQADCggICAAAAA==.',
Do='Doomfury:BAAANQADCgEIAgAAAA==.',
Dr='Dracthayr:BAAANQAECgcIEQAAAA==.Dragonhammer:BAAANQAECgYJBgAAAA==.Drimclaw:BAAANQAECgIIAwAAAA==.Drubo:BAAANQAECgEIAQAAAA==.Drx:BAAANQAECgQJCgAAAA==.',
Du='Dukkelemon:BAAANQAECgQIBwAAAA==.',
El='Elanore:BAAANQAECgYJDgABNQAECgEJAQABAAAAAA==.Elicithy:BAAANQABCgUIBQABNQAECggIFwAGAJQWAA==.Elison:BAAANQAECgQIBAAAAA==.Ellaini:BAAANQAECgEIAQAAAA==.Elliana:BAAANQAECgEJAQAAAA==.Ellie:BAAANQAECgEIAQABNQAECgcIHgAHANMiAA==.Elloise:BAAANQADCgQJBQABNQAECgEJAQABAAAAAA==.Elsae:BAAANQAECgYIEAAAAA==.Elseb:BAAANQADCgEIAQAAAA==.',
Ev='Evasion:BAAANQAFFAIIAgAAAA==.Everios:BAABNQAECoEaAAIIAAgKOR5MBQCxAgAIAAgKOR5MBQCxAgAAAA==.Evic:BAAANQADCgYICAAAAA==.Evielyn:BAAANQADCgUJBQABNQAECgEJAQABAAAAAA==.',
Ex='Exodous:BAAANQABCgYJBAAAAA==.',
Fa='Faeleader:BAAANQAECgEIAQAAAA==.Faevelina:BAAANQAECgEIAQABNQAECgIIBQABAAAAAA==.Faytadori:BAAANQAECgYJEAAAAA==.',
Fe='Felgrrl:BAAANQADCgcIFwAAAA==.Feyreh:BAAANQAECgEJAgAAAA==.',
Fi='Fidget:BAAANQAECgMIBQAAAA==.',
Fl='Fletch:BAAANQAECgUICAAAAA==.',
Fo='Forever:BAAANQAECggIBwAAAA==.',
Fr='Frique:BAAANQADCgUIFAAAAA==.Frozenyogert:BAAANQADCgYJCgAAAA==.',
Ga='Galbur:BAAANQAECgcJEwAAAA==.Galdrin:BAAANQAECgIIBQAAAA==.Gaspode:BAAANQADCgYICwAAAA==.Gassann:BAABNQAECoEZAAIJAAgKpRayWAD3AQAJAAgKpRayWAD3AQAAAA==.',
Ge='Geers:BAAANQAECgQIBAAAAA==.Getarage:BAABNQAECoEVAAIKAAgKBhgASABIAgAKAAgKBhgASABIAgAAAA==.Getasoar:BAAANQADCgQIBgABNQAECggJFQAKAAYYAA==.',
Gh='Ghil:BAAANQAECgUIBwAAAA==.',
Gi='Gilia:BAAANQAECgEJAgAAAA==.',
Gl='Glynix:BAAANQAECgIIAwAAAA==.',
Gn='Gnosher:BAAANQADCgYJDAAAAA==.',
Go='Goku:BAAANQAECgUJDgAAAA==.Goloron:BAAANQADCgIJAgAAAA==.Gorzok:BAAANQABCgEIAQAAAA==.',
Gr='Graymayn:BAAANQAECgQIBQAAAA==.Grekk:BAAANQAECgMIAwAAAA==.Grelldar:BAAANQADCgEIAQAAAA==.Grimflaps:BAAANQAECgIIBAAAAA==.',
Gu='Gunderthirth:BAABNQAECoEdAAIIAAkKzSTxAACvAwAIAAkKzSTxAACvAwAAAA==.Guulfang:BAAANQADCgMIAwAAAA==.',
Gw='Gwaeniiha:BAAANQAECgMJBAAAAA==.',
Ha='Haliran:BAAANQADCgUIDQAAAA==.Handsoap:BAAANQAECgIIAwAAAA==.Harakhty:BAAANQADCgQIBAAAAA==.Hardhitter:BAABNQAECoEaAAMIAAcKghFFDwCfAQAIAAcKghFFDwCfAQAKAAYKHwuJlQBCAQAAAA==.',
He='Hellumph:BAAANQAECgQIBgAAAA==.Hevensrath:BAAANQAECgQJBQAAAA==.Hexhorn:BAAANQADCggJDgAAAA==.Hextermorgan:BAAANQABCggICAABNQAECgcIEAABAAAAAA==.',
Ho='Hokuden:BAAANQAECgcJEQAAAA==.Holphie:BAAANQAECgEIAQAAAA==.Holyholyholy:BAAANQADCggICAAAAA==.',
Hu='Huddington:BAAANQAECgYIBwAAAA==.',
Hy='Hyperion:BAAANQADCgYIDwAAAA==.',
Ig='Igknight:BAAANQADCggIEgABNQAECgkJGAAHAK4LAA==.',
Im='Impthrower:BAAANQADCgYIBgABNQADCgYJDwABAAAAAA==.',
In='Indecent:BAAANQAECgYICAAAAA==.Inibble:BAAANQABCgUICAAAAA==.',
Iq='Iqfbeef:BAAANQADCgYICgAAAA==.',
Is='Ishy:BAAANQAECgYJDgAAAA==.',
Iw='Iwannalive:BAAANQADCgIIAgAAAA==.',
Iz='Izziey:BAAANQADCgEIAQAAAA==.',
Ja='Jack:BAABNQAECoEaAAQLAAgKUBW3FQBHAgALAAgKUBW3FQBHAgAMAAMKURWGDwDMAAANAAEKbgWJswAmAAAAAA==.Jackieplays:BAABNQAECoEcAAMMAAgKmR4GAgDIAgAMAAgK4x0GAgDIAgANAAcK/xgeRgDJAQAAAA==.Jaded:BAAANQAECgYJCgAAAA==.',
Jo='Jollah:BAAANQAECgQIBAAAAA==.',
Ju='Jurassic:BAAANQADCgYIBgAAAA==.Jutic:BAAANQAECgcIEQAAAA==.',
Ka='Kageken:BAAANQADCgQIBAABNQADCgYJEQABAAAAAA==.Kardas:BAAANQAECgUJCQAAAA==.',
Kb='Kbilly:BAAANQAECgUJDQAAAA==.',
Ke='Kentarou:BAAANQABCgUIBQAAAA==.Keylerin:BAABNQAECoEfAAIDAAkKhxlsBwDiAgADAAkKhxlsBwDiAgAAAA==.',
Ki='Kitsunami:BAAANQABCgUIBgAAAA==.Kitto:BAAANQADCgYJBgAAAA==.Kittvulpy:BAAANQADCgYICgAAAA==.',
Kn='Knottes:BAAANQABCggIEAAAAA==.',
Kr='Krampus:BAAANQAECgYICAAAAA==.Kranok:BAAANQAECgIIAwAAAA==.Krennthis:BAAANQADCgYJCwAAAA==.Krimbruiser:BAAANQADCgYIBwABNQADCgcICwABAAAAAA==.Krimhuntress:BAAANQADCgYIBgAAAA==.',
Ku='Kunac:BAAANQADCgYIEAAAAA==.',
Ky='Kyran:BAAANQADCgUIBwAAAA==.Kytrina:BAAANQADCgIIAgAAAA==.',
La='Lactoes:BAAANQADCgYIBgAAAA==.Lamoran:BAAANQADCgIJAgAAAA==.',
Le='Lemón:BAAANQAECgEIAQAAAA==.',
Lh='Lhani:BAAANQAECgIIAwAAAA==.',
Li='Lilguysci:BAAANQAECgIJAgAAAA==.',
Ll='Llothien:BAAANQAECgIIAgAAAA==.Llyrael:BAAANQAECgQICQAAAA==.',
Lu='Lugosi:BAAANQADCggIDgAAAA==.',
Ly='Lyfe:BAAANQABCgQIBAAAAA==.',
Ma='Machlain:BAAANQADCgQIBAABNQAECgUJCQABAAAAAA==.Maddeleine:BAAANQADCgEIAQAAAA==.Magara:BAAANQADCggIEAAAAA==.Magicdemon:BAAANQAECgYICAAAAA==.Makall:BAAANQABCgQIBAAAAA==.Malaah:BAAANQAECgQICQAAAA==.Mansuno:BAAANQAECgQJEgAAAA==.Mapachote:BAAANQAECgEJAQAAAA==.Marodin:BAAANQADCgcIHAAAAA==.Maynor:BAAANQABCgYJBgAAAA==.Mazboda:BAAANQAECgQJDQAAAA==.',
Me='Meatbaal:BAAANQAECgUIDQAAAA==.Melinaria:BAAANQAECgUJCQAAAA==.Merkabai:BAAANQADCgIIAgAAAA==.',
Mi='Mileta:BAAANQAECgQICQAAAA==.Minuette:BAAANQAECgMIAwAAAA==.',
Mo='Montblanc:BAAANQADCgUJBQAAAA==.',
Na='Nazgul:BAAANQADCgcICAAAAA==.',
Ne='Necroreign:BAAANQAECgYJEQAAAA==.Need:BAAANQAECgIIAgAAAA==.Neherenia:BAAANQAECgIIAwAAAA==.Nervous:BAAANQAECggIAQABNQAECggIBwABAAAAAA==.Nessee:BAAANQAECgQIBQAAAA==.',
Ni='Niall:BAAANQAECgEIAgAAAA==.Nightfire:BAAANQABCgcIBwAAAA==.Nihowdy:BAAANQAECgcJEQAAAA==.',
No='Norrin:BAAANQABCggIDAAAAA==.',
Oc='Octalexane:BAAANQADCgYIBgABNQAECgIIAwABAAAAAA==.',
On='Onimusha:BAAANQAECgEIAQAAAA==.',
Or='Orci:BAAANQAECgQIBQAAAA==.Ortalbem:BAAANQAECgcJEQAAAA==.',
Ou='Oulli:BAAANQABCggIEAAAAA==.',
Ov='Ovi:BAAANQAECgIJBAAAAA==.',
Pe='Peddles:BAAANQAECgIJAwAAAA==.',
Ph='Pherix:BAAANQADCgUIBQAAAA==.Philipfry:BAAANQAECgcIEwAAAA==.',
Pl='Plaguetusk:BAAANQADCgQIBAAAAA==.',
Po='Poomacha:BAAANQAECgIJAgAAAA==.Potatopants:BAAANQADCgQIBQAAAA==.',
Pr='Prinlina:BAAANQADCggIDQAAAA==.',
Py='Pyree:BAAANQAECgYIBwAAAA==.',
Ra='Radimus:BAAANQAECgEIAQAAAA==.Raenne:BAAANQADCgMIAwAAAA==.Raistlain:BAAANQAECgUICQAAAA==.Ralli:BAAANQAECgYIDQAAAA==.Rallsodins:BAAANQAECgUICAAAAA==.Ranleroesh:BAAANQAECggICAAAAA==.Ranulf:BAAANQADCgUIDQAAAA==.Ratava:BAAANQADCggJFwAAAA==.Ratrot:BAAANQADCggICQAAAA==.Raztar:BAAANQADCgUIBQAAAA==.',
Re='Reddemon:BAAANQAECgYJDwAAAA==.Rekarra:BAAANQADCgcIBwAAAA==.Reldarus:BAEANQAECgYIBwAAAA==.Rena:BAABNQAECoEXAAQOAAgKlgc/GQBWAQAOAAcKnAY/GQBWAQAPAAQKxQNwEgCCAAAQAAEKgAEOPgAkAAAAAA==.Revilation:BAAANQAECgYJCwAAAA==.Rezjyk:BAAANQADCgYIBgABNQAECgIIAwABAAAAAA==.Rezzyk:BAAANQAECgIIAwAAAA==.',
Rh='Rhyxali:BAAANQAECgIIBAAAAA==.',
Ri='Riibirth:BAAANQADCgYIBgAAAA==.Riis:BAAANQADCgEIAQAAAA==.',
Ry='Rygelon:BAAANQAECgQICQAAAA==.',
Sa='Sacredscales:BAAANQADCgMJAwAAAA==.Samvimes:BAAANQAECgIJAwAAAA==.Sangreene:BAAANQAECgcJDgAAAA==.Sargis:BAAANQAECgcJDwAAAA==.',
Sc='Schrödinger:BAAANQADCgcIBwABNQAECgIIAwABAAAAAA==.Scott:BAAANQAECgQIBAAAAA==.',
Se='Serissa:BAAANQADCgEJAQAAAA==.Serjankins:BAAANQADCgQIBAAAAA==.Setsuna:BAAANQABCgYIDAABNQAECggJGAALAJIeAA==.',
Sh='Shadowbrooks:BAAANQADCgIIAgAAAA==.Shadowgiver:BAAANQADCgcICwAAAA==.Shagol:BAAANQAECgQIBgAAAA==.Shamemoon:BAAANQAECgEJAQAAAA==.Shamunroe:BAAANQAECgYICAAAAA==.Shatterhoof:BAAANQAECgEJAQAAAA==.Shelle:BAAANQADCgQIBQAAAA==.Shingra:BAAANQAFFAEIAgAAAA==.Shylindra:BAAANQADCgYJCwAAAA==.',
Si='Sigourney:BAAANQAECgMJBAAAAA==.Silversho:BAAANQADCgYJCwAAAA==.Silvren:BAAANQADCgIIAgAAAA==.',
Sk='Skill:BAAANQAECgUJBQAAAA==.',
Sl='Slighttrash:BAAANQAECgMIBQAAAA==.',
Sm='Smallcrow:BAABNQAECoEXAAMRAAkK4BraCwDEAgARAAgKMB3aCwDEAgASAAQK0Q3AIgDkAAAAAA==.',
So='Somdot:BAAANQAECggIEgAAAA==.Somedeekay:BAAANQAECgQICAAAAA==.',
Sp='Spirit:BAAANQAECgcICwABNQAFFAIIAgABAAAAAA==.',
St='Starga:BAAANQADCgQIBAAAAA==.Starge:BAAANQADCgUIBQAAAA==.Starre:BAAANQADCgQIBAAAAA==.Steffey:BAAANQAECgEJAQAAAA==.Stepbro:BAAANQADCgYJBgAAAA==.Stoikk:BAAANQAECgQIBQAAAA==.Straven:BAAANQAECgQJBAAAAA==.Sturgeson:BAABNQAECoEeAAIIAAgKYx+UBADSAgAIAAgKYx+UBADSAgAAAA==.',
Su='Suffocation:BAEANQAECgYIBgABNQAFFAYIEQATAOwgAA==.Sulwen:BAAANQAECgQJCQAAAA==.Sundance:BAAANQADCgUIBQAAAA==.Sunray:BAAANQADCgcICAAAAA==.',
Sw='Swiftfeet:BAAANQAECgUICQAAAA==.',
['Sé']='Sésho:BAAANQADCgQIBgAAAA==.',
['Sö']='Söranin:BAAANQADCggIDgAAAA==.',
['Sø']='Sømdøt:BAAANQAECggIDAABNQAECggIEgABAAAAAA==.',
Ta='Taeili:BAAANQAECgUJBQAAAA==.Taeror:BAAANQADCgQIBAAAAA==.Tanequil:BAABNQAECoEbAAIUAAgKYwn6HwCPAQAUAAgKYwn6HwCPAQAAAA==.',
Te='Techromancer:BAAANQADCgEJAQABNQADCgUIBQABAAAAAA==.',
Th='Thanatias:BAAANQADCgIIAgAAAA==.Thantasia:BAAANQADCggJEgAAAA==.Theakunda:BAAANQAECgUJBQAAAA==.Theodis:BAAANQADCgUIDwAAAA==.',
Ti='Tifà:BAAANQAECgIIAgAAAA==.Tillago:BAAANQADCggICgAAAA==.Timothy:BAAANQAECgQIBQAAAA==.Timothyjohn:BAAANQADCgcJFgAAAA==.Tinkphooey:BAAANQAECgMIBAAAAA==.Tirianna:BAAANQADCgEJAQABNQAECgEJAQABAAAAAA==.Tituba:BAAANQAECgcJDwAAAA==.',
To='Tonepavone:BAAANQADCgYIBgAAAA==.Tormmok:BAAANQADCgQIBAAAAA==.',
Tr='Traazz:BAAANQADCgYICgAAAA==.Trior:BAAANQAECgIJAgAAAA==.',
Ts='Tsuruga:BAAANQAECgYICAAAAA==.',
Tu='Turkwise:BAAANQAECgQJDAAAAA==.',
Ur='Urobolos:BAAANQAECgMIAwAAAA==.',
Uv='Uvari:BAAANQAECgQICAAAAA==.',
Va='Vacalaca:BAAANQAECgEIAQABNQAECgEJAQABAAAAAA==.Valany:BAAANQADCgIIAgAAAA==.Valkira:BAABNQAECoEbAAMGAAgKjhdRCgBwAgAGAAgKiBZRCgBwAgAVAAYK3xecUACvAQAAAA==.Valton:BAABNQAECoEcAAIRAAgKEiPnBwASAwARAAgKEiPnBwASAwAAAA==.Vanillanice:BAAANQADCgMJBAAAAA==.Varrfife:BAAANQABCgIJAgAAAA==.Vaxaldan:BAAANQAECgYICAAAAA==.',
Ve='Venj:BAAANQAECgIIAgAAAA==.Ventosa:BAABNQAECoEbAAIWAAgKwhv6JwBkAgAWAAgKwhv6JwBkAgAAAA==.Vex:BAAANQAECgEJAQAAAA==.',
Vi='Vilox:BAAANQADCgIIAgAAAA==.Viltex:BAAANQADCgYICwAAAA==.Vilxten:BAAANQADCgUIBQAAAA==.',
Vo='Voidleader:BAAANQAECgMIAwAAAA==.Vostok:BAAANQAECgUJDAAAAA==.',
Wa='Warramag:BAAANQAECgQJBAAAAA==.Warranni:BAAANQAECgUICQAAAA==.',
We='Weekend:BAAANQAECgQICQAAAA==.',
Wh='Whatafox:BAAANQAECgQICAAAAA==.Whittail:BAAANQABCggIDgAAAA==.',
Wi='Wikket:BAAANQAECgYIBwAAAA==.',
Wy='Wyelie:BAAANQAECgQICQAAAA==.',
Xa='Xade:BAAANQAECgYJDwAAAA==.Xandendon:BAAANQAECgYIDAAAAA==.',
Xe='Xerond:BAAANQADCgUJBQAAAA==.Xevin:BAAANQAECgUIDQAAAA==.',
Ya='Yaákov:BAAANQAECgcJCwAAAA==.',
Yi='Yinosai:BAAANQADCgYICQAAAA==.',
Yo='Yougot:BAAANQADCgUICAAAAA==.',
Za='Zademedic:BAAANQAECgEIAQAAAA==.Zanarkin:BAAANQAECgEJAQAAAA==.Zaranji:BAAANQADCgYIBgAAAA==.Zarisedra:BAABNQAECoEgAAMHAAkKNRq7GQDDAgAHAAkKNRq7GQDDAgAJAAEK9QAzQgEUAAAAAA==.Zarissena:BAAANQAECgEJAQABNQAECgQIBAABAAAAAA==.Zarmina:BAAANQADCgEIAQAAAA==.Zarris:BAAANQABCgYIBAAAAA==.',
Ze='Zerdah:BAAANQADCgcIEwAAAA==.Zerogasm:BAAANQADCgQIBgAAAA==.Zerolicious:BAAANQAECgMJAwAAAA==.Zeroprophecy:BAAANQAECgEIAQAAAA==.Zevvo:BAAANQAECgYICAAAAA==.',
Zo='Zoeybear:BAAANQAECgIJAgAAAA==.Zoraji:BAAANQAECgcJEQAAAA==.',
['Ëd']='Ëdën:BAAANQAECgIJAgAAAA==.',
['Ða']='Ðarkmoon:BAAANQABCgYICAAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
