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

local lookup = {'Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Hunter-Survival','Unknown-Unknown','Hunter-BeastMastery','Paladin-Holy','Shaman-Elemental','DemonHunter-Devourer','Priest-Shadow','Evoker-Preservation','Priest-Holy','Druid-Balance','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Druid-Feral','Shaman-Enhancement','Mage-Frost','Mage-Arcane','Monk-Windwalker','Hunter-Marksmanship','Evoker-Devastation','DemonHunter-Havoc','DeathKnight-Frost','Evoker-Augmentation','DemonHunter-Vengeance','DeathKnight-Unholy','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Warlock-Affliction','Rogue-Assassination','Rogue-Outlaw','Warrior-Arms','Warrior-Protection','Rogue-Subtlety','Druid-Guardian',}
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Aceroth:BAABNQAECn8gAAMBAAkKRRbuYwBrAgABAAkKRRbuYwBrAgACAAEKnwZ3fQAeAAAAAA==.',
Ae='Aelin:BAABNQAECn8qAAIDAAgKVxpTNQA0AgADAAgKVxpTNQA0AgAAAA==.Aerillidan:BAAANQAECgEIAQAAAA==.',
Ak='Akinna:BAAANQABCggICAAAAA==.',
Al='Alariane:BAAANQADCgYIBgAAAA==.Alaysia:BAAANQADCgYIBgAAAA==.Alestair:BAAANQAECggIEgAAAA==.Alythra:BAAANQADCgcIBwAAAA==.',
Am='Amorsith:BAABNQAECn8YAAIEAAcKgA6YCADCAQAEAAcKgA6YCADCAQABNQAECgkJHAACALQZAA==.Ampluslues:BAAANQADCgMIAgABNQADCggICAAFAAAAAA==.',
An='Angelyna:BAAANQAECggICAAAAA==.Angrä:BAAANQAECgQJBAAAAA==.',
Ar='Arakfalas:BAAANQADCggIDgAAAA==.Argentnox:BAAANQAECgUIBQABNQAECggIHgAGAE0MAA==.Argoz:BAABNQAECn8fAAIHAAgK5AvKewCiAQAHAAgK5AvKewCiAQAAAA==.Arrethyn:BAAANQAECggIDwAAAA==.',
As='Asbell:BAAANQAECgcIDQAAAA==.Aspectz:BAAANQABCgMIAwAAAA==.',
At='Atsidi:BAABNQAECn8ZAAIIAAgKdhdTUQAwAgAIAAgKdhdTUQAwAgAAAA==.',
Ax='Axecutioner:BAAANQAECgUIBwAAAA==.',
Az='Azaelara:BAABNQAECn8dAAICAAgKCQX2OwAOAQACAAgKCQX2OwAOAQAAAA==.Azaëlle:BAAANQADCgYIDAAAAA==.Azmerea:BAAANQADCggICAAAAA==.Azshaura:BAAANQADCgIIAgAAAA==.',
Ba='Badmojojojo:BAABNQAECn8eAAIGAAgKTQz+lgDWAQAGAAgKTQz+lgDWAQAAAA==.Bankhand:BAABNQAECn8jAAIJAAgKJhTCJgAMAgAJAAgKJhTCJgAMAgAAAA==.Bartab:BAAANQAECgYIDwAAAA==.',
Be='Beazle:BAAANQADCgYICQAAAA==.Beefytotems:BAAANQAECgYICAABNQAECggICQAFAAAAAA==.Benjamin:BAABNQAECn8ZAAIKAAkKoBxiGQCBAgAKAAkKoBxiGQCBAgAAAA==.',
Bi='Bibistraz:BAABNQAECn8dAAILAAgKGhQRHQD5AQALAAgKGhQRHQD5AQAAAA==.',
Bl='Blenny:BAAANQAECgUICAAAAA==.Blitzkrîeg:BAABNQAECn8jAAIHAAgK+BTFVAAYAgAHAAgK+BTFVAAYAgAAAA==.',
Bo='Boeboe:BAABNQAECn8eAAIMAAgK7xZlRABXAgAMAAgK7xZlRABXAgAAAA==.Boomloomly:BAABNQAECn8kAAMNAAkK8iBwDQBeAwANAAkK8iBwDQBeAwAOAAIKzAnrZwBfAAAAAA==.Borgymorgy:BAAANQADCgEIAQAAAA==.',
Br='Brightblade:BAAANQADCgcIBwAAAA==.Brofessor:BAAANQADCgQIAQAAAA==.Bruzande:BAAANQAECgYJEAAAAA==.Brynjolf:BAAANQADCgYIBgAAAA==.',
Bu='Bumbaweatuna:BAAANQADCgEIAQAAAA==.Burncycle:BAAANQADCgYIBgAAAA==.Burntt:BAAANQABCgYIBgAAAA==.Buttjeans:BAABNQAECn8mAAMPAAkKJR9lJQDsAgAPAAgKfB9lJQDsAgAQAAIKYBJgUwCDAAAAAA==.',
Ca='Catastrophez:BAAANQADCgcIBwAAAA==.',
Ce='Celine:BAABNQAECn8aAAIHAAYKhwiYsAAaAQAHAAYKhwiYsAAaAQAAAA==.Ceo:BAAANQAECgEIAQAAAA==.',
Ch='Chev:BAAANQADCgUIBQAAAA==.Chickynuggy:BAAANQAECgUIEQAAAA==.Chillypickle:BAAANQAECgMIBAAAAA==.Christopher:BAABNQAECn8YAAIDAAkK2SBZFAAHAwADAAkK2SBZFAAHAwAAAA==.Chronicbuds:BAAANQAECgYIDQAAAA==.',
Cl='Cloudcaller:BAAANQADCgYIBgABNQAECggIJwARAGEHAA==.Clyde:BAAANQADCgYJBgAAAA==.',
Co='Cobrakai:BAAANQAECgYIEQAAAA==.Cochuata:BAABNQAECn8eAAMOAAkK8BXFGQBpAgAOAAkK8BXFGQBpAgANAAEKvQuhqwA7AAAAAA==.',
Cr='Crabbypatty:BAAANQADCgcICwABNQABCgQIBAAFAAAAAA==.Cripstaet:BAAANQADCgYIBgAAAA==.Crow:BAAANQAECgEIAQAAAA==.Crusadinvee:BAAANQADCggICAAAAA==.',
Cu='Curse:BAAANQAECgQICAABNQAECgYIEAAFAAAAAA==.',
Da='Dairydefendr:BAABNQAECn8aAAIBAAcKBR92ewAwAgABAAcKBR92ewAwAgAAAA==.Damage:BAAANQADCggIDAAAAA==.Damyn:BAABNQAECn8qAAISAAgK4B9OBwAJAwASAAgK4B9OBwAJAwAAAA==.Darogue:BAAANQAECgQIBAAAAA==.Darthsparrow:BAAANQAECgMIAwAAAA==.',
De='Deadbro:BAAANQADCgEIAQAAAA==.Deathaxe:BAAANQADCgUIBQABNQAECggIHQATAAscAA==.Deathsgrace:BAABNQAECn8dAAMTAAgKCxwkCgAlAgATAAcKiRskCgAlAgAUAAcKdxYeygDvAQAAAA==.Delia:BAAANQABCggIDgAAAA==.Demark:BAAANQAECgQIBAAAAA==.Demonicneon:BAAANQAECgYIEwAAAA==.Devana:BAABNQAECn8cAAIGAAcKDBstaABBAgAGAAcKDBstaABBAgABNQAECgcIHgAHAHIaAA==.',
Di='Diabolicque:BAAANQAECgEIAQAAAA==.Diddycated:BAEANQAECgUIBQABNQAFFAMIBgAVAGUIAA==.Dingus:BAABNQAECn8jAAQWAAgKfBn+IQA6AgAWAAcK0Bj+IQA6AgAEAAUKLBUKCgB/AQAGAAEK+RghQwFQAAAAAA==.',
Dk='Dk:BAAANQADCgYIDQABNQAECgYIEAAFAAAAAA==.',
Do='Doode:BAABNQAECn8hAAMLAAkKGAkTIgC5AQALAAkKGAkTIgC5AQAXAAEKAAAoQgAjAAAAAA==.Doody:BAAANQADCgYIEAABNQAECgkJIQALABgJAA==.',
Dr='Dragonslayer:BAAANQADCgcIBwAAAA==.Dreastotems:BAAANQAECgEIAgAAAA==.Drennifer:BAAANQAECgQICgAAAA==.',
Eb='Ebtyrone:BAAANQAECgUIBQAAAA==.',
Em='Emmerson:BAAANQADCgQIBQAAAA==.Emphasis:BAAANQAECgEIAQABNQAECgkJIQAYAKUYAA==.',
Es='Escanór:BAAANQADCgUIBwAAAA==.',
Fa='Fajitajones:BAAANQADCgUICgAAAA==.',
Fo='Fooksdh:BAAANQADCggICgAAAA==.Fooksdk:BAABNQAECn8rAAMZAAgK9hhcLgAqAgAZAAgK9hhcLgAqAgADAAUKdgYlkwC3AAAAAA==.Fooksdruid:BAAANQAECgQICAAAAA==.Forestpimp:BAAANQAECgQICQAAAA==.',
Fu='Fullometal:BAABNQAECn8eAAIRAAkKsRhWCQCvAgARAAkKsRhWCQCvAgAAAA==.Furojin:BAAANQAECgUICQABNQAECggIHgAGAE0MAA==.',
Ga='Galroot:BAABNQAECn8qAAIOAAgKRSYrBACBAwAOAAgKRSYrBACBAwAAAA==.Galstad:BAAANQABCgEIAQAAAA==.Garrett:BAAANQADCgEIAQAAAA==.',
Ge='Geff:BAAANQADCgQIBAAAAA==.',
Gh='Ghôst:BAAANQAECgMIBQABNQAFFAIIBAAFAAAAAA==.',
Gi='Girthhquake:BAAANQAECgQIBgAAAA==.Gisokaashi:BAAANQADCgcIEAAAAA==.',
Gn='Gnomepwner:BAAANQADCgcIBwAAAA==.',
Go='Gothick:BAAANQAECgUIDAAAAA==.',
Gr='Grimréaper:BAAANQADCgIIAgAAAA==.',
Gu='Guts:BAAANQAECgEIAQAAAA==.',
Ha='Habib:BAAANQABCggIDAAAAA==.Harryhoudini:BAAANQAECgEJAQAAAA==.',
He='Healforfun:BAABNQAECn8wAAIOAAkK2hnpFQCSAgAOAAkK2hnpFQCSAgAAAA==.Heilung:BAABNQAECn8oAAQaAAkKiRUiCAAYAgAaAAgKkxQiCAAYAgALAAEK6AQbTQA2AAAXAAEKJwH+QwAaAAAAAA==.',
Hi='Hippokleides:BAAANQADCgYICgAAAA==.Hirradee:BAABNQAECn8sAAIJAAkKHxcWHwBUAgAJAAkKHxcWHwBUAgAAAA==.',
Ho='Holyzeal:BAAANQADCgUIBQAAAA==.Honatuto:BAAANQAECgQICAAAAA==.',
Hu='Hubelez:BAABNQAECn8bAAIGAAkKUg5KcQAsAgAGAAkKUg5KcQAsAgAAAA==.',
Hy='Hyacine:BAAANQADCggIEAAAAA==.',
Ic='Icecweam:BAAANQADCggIDgAAAA==.Icthelight:BAAANQAECgMIAwAAAA==.',
Ig='Ightbet:BAAANQADCggIEAAAAA==.',
Ii='Iista:BAAANQAECgIIAgAAAA==.',
Ir='Irontuskss:BAAANQAECgIIAgAAAA==.',
Iz='Iznthyr:BAAANQABCgIIAgAAAA==.',
Ja='Jayar:BAABNQAECn8hAAMYAAkKpRiKIQCLAgAYAAkKpRiKIQCLAgAbAAEKAABONgAhAAAAAA==.',
Jd='Jdawgg:BAAANQAECgEIAQAAAA==.',
Jo='Jorley:BAAANQADCggIDwAAAA==.',
Jr='Jrwriter:BAAANQAECgYIEAAAAA==.',
Jy='Jym:BAAANQAECgYICwAAAA==.',
Ka='Kaijin:BAABNQAECn8dAAIVAAgKTxZoJwDhAQAVAAgKTxZoJwDhAQAAAA==.Kalasting:BAAANQAECgMIBgABNQAECggIIwAMAAYfAA==.Kalyr:BAAANQAECgYIEAAAAA==.Kandrianna:BAABNQAECn8jAAIKAAgKbgW+OwBIAQAKAAgKbgW+OwBIAQAAAA==.',
Ke='Keraasi:BAABNQAECn8oAAMHAAkK7RSqPQBrAgAHAAkK7RSqPQBrAgABAAEKYwcopgExAAAAAA==.Kevinv:BAAANQADCgEIAQAAAA==.',
Kh='Khristine:BAAANQADCgQIBAABNQAECgkJIQAYAKUYAA==.',
Ki='Kikai:BAAANQADCgUICQAAAA==.Kilrav:BAABNQAECn8aAAIcAAcK0hxKRwD3AQAcAAcK0hxKRwD3AQAAAA==.Kimberlee:BAAANQAECggIDgAAAA==.Kiryanna:BAAANQAECgQIBQAAAA==.Kitiara:BAAANQAECgQJBAAAAA==.',
Kl='Klayah:BAAANQAECgUIEgAAAA==.',
Ko='Koogz:BAAANQAECgUIDgAAAA==.Kordelia:BAABNQAECn8eAAMHAAcKchpKVQAXAgAHAAcKchpKVQAXAgABAAMKZQO1cQFlAAAAAA==.Korgmafx:BAAANQADCgUIEAAAAA==.',
Kr='Kratosol:BAAANQAECgEJAQAAAA==.',
Ku='Kudre:BAAANQABCgIIAgAAAA==.',
Ky='Kynigos:BAAANQADCggICAABNQAECggIHQATAAscAA==.',
La='Larke:BAAANQAECgQIBwAAAA==.',
Le='Leilany:BAAANQAECgUIDQAAAA==.Lethäl:BAAANQADCgIIAgAAAA==.',
Li='Littledirk:BAAANQADCgcIAgAAAA==.',
Ll='Llillies:BAAANQAECgEIAgAAAA==.',
Lu='Lucioush:BAAANQADCggICAAAAA==.Lugnuts:BAAANQAECgQIBQAAAA==.',
Ma='Magebuff:BAACNQAFFH8GAAIUAAMKcQ4dNQDrAAAUAAMKcQ4dNQDrAAA1AAQKfzIAAhQACQr/Hqs5ABQDABQACQr/Hqs5ABQDAAAA.Malroy:BAAANQADCgYIBgAAAA==.',
Mc='Mcheals:BAAANQADCgcIDgAAAA==.',
Mi='Miidniter:BAAANQAECgQICgAAAA==.',
Mo='Monsunami:BAAANQAECgQICAAAAA==.Moogar:BAABNQAECn8mAAMdAAkKMSOpBgCNAwAdAAkKMSOpBgCNAwAIAAEKuwN7MwEyAAAAAA==.Moolinda:BAAANQAECgMIAwAAAA==.Moonlock:BAAANQADCggICAAAAA==.Morte:BAAANQADCgIIAgAAAA==.Moònflower:BAAANQAECgIIAgAAAA==.',
['Mø']='Møøse:BAABNQAECn8eAAIdAAgKGhyqPABqAgAdAAgKGhyqPABqAgAAAA==.',
Na='Namegoeshere:BAAANQAECgMIAwABNQAECggIHgAGAE0MAA==.Nanwu:BAABNQAECn8eAAIIAAgK6RQpYgD3AQAIAAgK6RQpYgD3AQAAAA==.Narcyon:BAABNQAECn8jAAMMAAgKBh+RNgCLAgAMAAgKBh+RNgCLAgAKAAYKARSANwBlAQAAAA==.',
Ne='Neonfel:BAAANQADCggICAAAAA==.',
Nh='Nhox:BAAANQAECgQIDQAAAA==.Nhöxx:BAAANQADCgUIBwAAAA==.',
No='Noobîtîs:BAAANQAECgMIAwAAAA==.Notmaxxie:BAAANQAECgYIBwAAAA==.',
Ny='Nystiae:BAAANQADCggICgAAAA==.',
Ob='Obscur:BAAANQAECgEIAQABNQAECgkJGAAPAOAUAA==.Obz:BAABNQAECn8YAAMPAAkK4BSxcgAEAgAPAAgKihWxcgAEAgAQAAIKJhBNWgBwAAAAAA==.',
Od='Oddlylight:BAAANQAECgQICQAAAA==.',
Og='Ogzugz:BAAANQABCgUIBQAAAA==.',
Ol='Ollie:BAAANQADCgIIAgAAAA==.',
Ox='Oxytocin:BAAANQADCgIIAgAAAA==.',
Pa='Pandicated:BAECNQAFFH8GAAIVAAMKZQheDQC+AAAVAAMKZQheDQC+AAA1AAQKfzAABBUACQrwF00ZAHUCABUACQpdFE0ZAHUCAB4ABwrXFgMSAMIBAB8AAQpbACpXABMAAAAA.',
Pe='Pelondar:BAAANQADCggIDgAAAA==.',
Ph='Phalanx:BAAANQADCgYIFAAAAA==.',
Pi='Pickleburger:BAAANQADCgUICAAAAA==.',
Pl='Plaguedoctor:BAAANQADCgQJBAAAAA==.',
Po='Pookalicious:BAAANQADCgQIBAAAAA==.Pookiebear:BAAANQADCgIIAgAAAA==.Possessed:BAAANQADCgYICgAAAA==.',
Pr='Prìdè:BAAANQAECgcIEAAAAA==.Prïdë:BAAANQAECgIIAgAAAA==.',
Pu='Punjana:BAAANQABCgMIAwAAAA==.',
Ra='Raike:BAAANQADCgMIAwAAAA==.Razmae:BAAANQAECgMIAwAAAA==.',
Re='Rennala:BAAANQAECgEIAQAAAA==.',
Ri='Riceball:BAAANQADCgMIAwAAAA==.Riptide:BAABNQAECn8aAAIUAAgKfRBNwAACAgAUAAgKfRBNwAACAgAAAA==.Risto:BAABNQAECn8eAAMPAAgK2yCKYgAuAgAPAAYKtR2KYgAuAgAgAAMKmSRiEABEAQAAAA==.',
Ro='Rockon:BAABNQAECn8cAAIIAAkK/AnkagDcAQAIAAkK/AnkagDcAQABNQADCgcIDgAFAAAAAA==.Roden:BAAANQABCgMIAwAAAA==.Ronzertnin:BAABNQAECn8XAAIQAAgKMxB3DwADAgAQAAgKMxB3DwADAgAAAA==.Roxen:BAAANQADCggIFQAAAA==.',
Ru='Runananako:BAAANQAECgUICwAAAA==.',
Ry='Ryo:BAAANQADCggICAAAAA==.',
['Ré']='Réaper:BAAANQADCgcIDwAAAA==.Rénji:BAABNQAECn8WAAIVAAcKDRAeNABvAQAVAAcKDRAeNABvAQAAAA==.',
Sa='Salana:BAAANQAECgMIBwAAAA==.San:BAABNQAECn8bAAMhAAkKKSEvDwAFAwAhAAgKKSEvDwAFAwAiAAIK9BL3FgB0AAABNQAFFAIIBgAMAHgOAA==.Sandroin:BAAANQAECgEIAQAAAA==.Sarah:BAAANQADCggIDAABNQAECgkJLQAMAF4kAA==.',
Sc='Scarf:BAABNQAECn8hAAMjAAgKbAsNqAC0AQAjAAgKbAsNqAC0AQAkAAEKWANjSgAdAAAAAA==.',
Sh='Shiggy:BAAANQADCggICAAAAA==.Shinerbock:BAABNQAECn8YAAIGAAgKCQkmmgDPAQAGAAgKCQkmmgDPAQAAAA==.Shipoopi:BAABNQAECn8UAAMSAAcK7RE5HgB4AQASAAYKXhA5HgB4AQAIAAMK+xaC5gDEAAAAAA==.Shock:BAABNQAECn8eAAIIAAgKrSLhGgAmAwAIAAgKrSLhGgAmAwAAAA==.Shortnshady:BAABNQAECn8hAAIlAAgKPw/zGwDyAQAlAAgKPw/zGwDyAQAAAA==.',
Si='Sithen:BAAANQAECgMIAwAAAA==.',
Sk='Skankadin:BAAANQADCgYICQABNQAECgIIBAAFAAAAAA==.Skankerella:BAAANQAECgIIBAAAAA==.Skiatrochia:BAAANQADCggICAABNQAECgkJLAAJAB8XAA==.Skipuscales:BAABNQAECn8hAAIXAAkKdCArBQBAAwAXAAkKdCArBQBAAwAAAA==.',
Sm='Smoaky:BAABNQAECn8nAAIRAAgKYQcZGgBZAQARAAgKYQcZGgBZAQAAAA==.',
So='Soul:BAABNQAECn80AAMNAAkKYx49FAAkAwANAAkKYx49FAAkAwAmAAQKzQj3QgCjAAAAAA==.Soulscorcher:BAAANQADCggIFAAAAA==.Soulsurvivor:BAAANQAECgQIBQABNQAECgUIEgAFAAAAAA==.Sovietpanda:BAAANQADCgUICAAAAA==.',
Sp='Spanky:BAAANQAECgQIBgAAAA==.Spankyohs:BAAANQADCgcJDAAAAA==.Spindles:BAAANQAECgEIAQAAAA==.Spineless:BAAANQAECgIIAgAAAA==.Spiritgun:BAAANQAECgEIAQABNQAECgYIEAAFAAAAAA==.',
St='Stimpack:BAAANQAECgUIEgAAAA==.',
Su='Sutures:BAAANQADCgYIDgAAAA==.',
['Sö']='Sönja:BAAANQAECgIIBAAAAA==.',
Ta='Tacotuesday:BAAANQABCgcIBwAAAA==.Tará:BAAANQAECgUJCQAAAA==.',
Te='Techpriest:BAAANQAECgMIAgAAAA==.Tehblink:BAABNQAECn8iAAITAAcKsB74BgCGAgATAAcKsB74BgCGAgAAAA==.Tenative:BAAANQAECgIIAwABNQAECgkJJgAPACUfAA==.Tenoch:BAAANQAECgUIDQAAAA==.Terah:BAAANQADCgIIAgAAAA==.',
To='Tobibobi:BAAANQADCgUIBQAAAA==.Toomez:BAAANQADCggICgAAAA==.Touchmydemon:BAAANQAECgUICgAAAA==.',
Tr='Trea:BAABNQAECn8dAAIGAAcKAhOKlQDZAQAGAAcKAhOKlQDZAQAAAA==.',
Tu='Tupkiss:BAABNQAECn8pAAIKAAgKXR8SEQDnAgAKAAgKXR8SEQDnAgAAAA==.',
Ty='Tygrand:BAAANQAECgUIBgABNQAECggIJwARAGEHAA==.',
Va='Vazer:BAAANQABCgMIAwAAAA==.',
Vo='Voidtouched:BAAANQADCggICAAAAA==.',
Wa='Waffledead:BAABNQAECn8kAAQgAAkKmhlkCQDsAQAgAAYKLBtkCQDsAQAPAAYK5xPOnACZAQAQAAQKXBufJgBAAQAAAA==.Wafflelight:BAAANQADCgcIBwAAAA==.Walshy:BAAANQAECggICQAAAA==.Warpfiend:BAABNQAECn8WAAMSAAcKXRxHEgBCAgASAAcKDxxHEgBCAgAIAAUKbx1kfQCoAQAAAA==.Warpinferno:BAAANQADCggICAAAAA==.',
We='Wek:BAAANQADCgUIBQAAAA==.Wetnugget:BAAANQAECgEIAgAAAA==.',
Wi='Winnie:BAAANQADCgEIAQAAAA==.',
Wo='Wolfnhowz:BAAANQAECgIIAgAAAA==.',
Wy='Wyhm:BAAANQADCgIIAgAAAA==.',
Yu='Yuriko:BAAANQADCgYIDAAAAA==.',
Za='Zandragon:BAAANQADCgQIBAAAAA==.',
Ze='Zebubblez:BAAANQAECgIIAwAAAA==.',
Zg='Zgux:BAAANQAECgQIBwAAAA==.',
Zo='Zoêy:BAAANQADCggIHQAAAA==.',
Zu='Zuraki:BAAANQAECgQIBgAAAA==.',
Zz='Zzin:BAAANQABCgEIAQAAAA==.',
['Ço']='Çountèr:BAAANQAECgIIAgAAAA==.',
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
