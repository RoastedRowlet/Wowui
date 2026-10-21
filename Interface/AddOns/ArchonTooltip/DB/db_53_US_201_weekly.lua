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

local lookup = {'Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Survival','Unknown-Unknown','Paladin-Holy','Shaman-Elemental','DemonHunter-Devourer','Druid-Balance','Druid-Guardian','Priest-Shadow','Evoker-Preservation','Priest-Holy','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Druid-Feral','Rogue-Outlaw','Shaman-Enhancement','Mage-Frost','Mage-Arcane','Monk-Windwalker','Hunter-Marksmanship','Evoker-Devastation','DemonHunter-Havoc','DeathKnight-Frost','Evoker-Augmentation','DemonHunter-Vengeance','DeathKnight-Unholy','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Warlock-Affliction','Rogue-Assassination','Warrior-Arms','Warrior-Protection','Rogue-Subtlety',}
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Aceroth:BAABNQAECn8oAAMBAAkKchfwFwDDAQABAAkKchfwFwDDAQACAAEKnwbefgAeAAAAAA==.',
Ae='Aelin:BAABNQAECn8zAAIDAAoKdRYkBAAdAgADAAoKdRYkBAAdAgAAAA==.Aerillidan:BAAANQAECgEIAQAAAA==.',
Ak='Akinna:BAAANQABCggICAAAAA==.',
Al='Alariane:BAAANQADCggICgAAAA==.Alaysia:BAAANQADCgYIBgAAAA==.Alestair:BAABNQAECn8UAAIEAAkKiwUgsQCiAQAEAAkKiwUgsQCiAQAAAA==.Alythra:BAAANQADCgcIBwAAAA==.',
Am='Amorsith:BAABNQAECn8cAAIFAAcKgA6kCADCAQAFAAcKgA6kCADCAQABNQAECgoKJQACANsbAA==.Ampluslues:BAAANQADCgMIAgABNQADCggICAAGAAAAAA==.',
An='Anath:BAAANQADCgIIAgAAAA==.Androdne:BAAANQAECgUIBAAAAA==.Angelyna:BAAANQAECggICAAAAA==.Angrä:BAAANQAECgQJBAAAAA==.',
Ar='Arakfalas:BAAANQADCggIDgAAAA==.Argentnox:BAAANQAECgUIBQABNQAECgkJIgAEAHwLAA==.Argoz:BAABNQAECn8mAAIHAAoKWw6UGQCNAQAHAAoKWw6UGQCNAQAAAA==.Arrethyn:BAAANQAECggIEgAAAA==.',
As='Asbell:BAAANQAECgcIDgAAAA==.Aspectz:BAAANQABCgMIAwAAAA==.',
At='Atsidi:BAABNQAECn8gAAIIAAgKsRhvCwC4AQAIAAgKsRhvCwC4AQAAAA==.',
Ax='Axecutioner:BAAANQAECgUIBwAAAA==.',
Az='Azaelara:BAABNQAECn8lAAMCAAkKIQiIGADIAAACAAgKCQWIGADIAAABAAEKsxrI2wBPAAAAAA==.Azaëlle:BAAANQADCgYIDAAAAA==.Azmerea:BAAANQADCggIEAAAAA==.Azshaura:BAAANQADCgIIAgAAAA==.',
Ba='Badmojojojo:BAABNQAECn8iAAIEAAkKfAsimQDVAQAEAAkKfAsimQDVAQAAAA==.Bankhand:BAABNQAECn8nAAIJAAgKIxYxJwALAgAJAAgKIxYxJwALAgAAAA==.Bartab:BAABNQAECn8ZAAMKAAcK8Q7iIADnAAAKAAcK3g3iIADnAAALAAQKoA/HOQDdAAAAAA==.',
Be='Beazle:BAAANQAECgQIBAAAAA==.Beefytotems:BAAANQAECgYICAABNQAECggICQAGAAAAAA==.Benjamin:BAABNQAECn8ZAAIMAAkKoByVGQCBAgAMAAkKoByVGQCBAgAAAA==.',
Bi='Bibistraz:BAABNQAECn8eAAINAAkKJRMtHQD5AQANAAkKJRMtHQD5AQAAAA==.',
Bl='Blenny:BAAANQAECgUICAAAAA==.Blitzkrîeg:BAABNQAECn8nAAIHAAgKVRrWIgBZAQAHAAgKVRrWIgBZAQAAAA==.',
Bo='Boeboe:BAABNQAECn8lAAIOAAgK0xd6RQBXAgAOAAgK0xd6RQBXAgAAAA==.Boomloomly:BAABNQAECn8oAAMKAAoKbCKwDQBdAwAKAAoKbCKwDQBdAwAPAAIKzAmQaQBfAAAAAA==.Borgymorgy:BAAANQADCgEIAQAAAA==.',
Br='Brightblade:BAAANQAECgYIBQAAAA==.Brofessor:BAAANQADCgQIAQAAAA==.Bruzande:BAAANQAECgYJEAAAAA==.Brynjolf:BAAANQADCgYIBgAAAA==.',
Bu='Bumbaweatuna:BAAANQADCgEIAQAAAA==.Burncycle:BAAANQADCgYIBgAAAA==.Buttjeans:BAABNQAECn8sAAMQAAoKvR1LJgDrAgAQAAkK1B1LJgDrAgARAAIKYBLgUwCDAAAAAA==.',
Ca='Catastrophez:BAAANQADCgcIBwAAAA==.',
Ce='Celine:BAABNQAECn8fAAIHAAYK/QidRgDXAAAHAAYK/QidRgDXAAAAAA==.Ceo:BAAANQAECgEIAQAAAA==.',
Ch='Chev:BAAANQADCgUIBQAAAA==.Chickynuggy:BAAANQAECgcIEgAAAA==.Chillypickle:BAAANQAECgMIBAAAAA==.Christopher:BAABNQAECn8YAAIDAAkK2SC6FAAGAwADAAkK2SC6FAAGAwAAAA==.Chronicbuds:BAAANQAECgYIDQAAAA==.',
Cl='Cloudcaller:BAAANQAECgQIBAABNQAECggIJwASAGEHAA==.Clyde:BAAANQADCgYIBgAAAA==.',
Co='Cobrakai:BAABNQAECn8bAAITAAcKwBFMAwD7AAATAAcKwBFMAwD7AAAAAA==.Cochuata:BAABNQAECn8nAAMPAAoKiRYlBwDUAQAPAAoKiRYlBwDUAQAKAAEKvQuNrQA7AAAAAA==.',
Cr='Crabbypatty:BAAANQADCgcICwABNQABCgQIBAAGAAAAAA==.Cripstaet:BAAANQADCggIDgAAAA==.Crow:BAAANQAECgEIAQAAAA==.Crusadinvee:BAAANQADCggIEAAAAA==.',
Cu='Curse:BAAANQAECgQICAABNQAECgYIEAAGAAAAAA==.',
Da='Dairydefendr:BAABNQAECn8hAAIBAAoK8RwxEwDiAQABAAoK8RwxEwDiAQAAAA==.Damage:BAAANQADCggIDAAAAA==.Damyn:BAABNQAECn8yAAIUAAkKHSDPAQBIAgAUAAkKHSDPAQBIAgAAAA==.Darogue:BAAANQAECgQIBwAAAA==.Darthsparrow:BAAANQAECgMIAwAAAA==.',
De='Deadbro:BAAANQADCgEIAQAAAA==.Deathaxe:BAAANQADCgUIBQABNQAECggIJAAVAKccAA==.Deathsgrace:BAABNQAECn8kAAMVAAgKpxy7AgCrAQAWAAgK7hRkzADtAQAVAAgKDRy7AgCrAQAAAA==.Delia:BAAANQABCggIDgAAAA==.Demark:BAAANQAECgQIBAAAAA==.Demonicneon:BAABNQAECn8VAAIJAAcKlQZLQQBDAQAJAAcKlQZLQQBDAQAAAA==.Devana:BAABNQAECn8iAAIEAAgKDRppaQBBAgAEAAgKDRppaQBBAgABNQAECgoKJAAHAPEWAA==.',
Di='Diabolicque:BAAANQAECgEIAQAAAA==.Diddycated:BAEANQAECgUICQABNQAFFAMICAAXAIkIAA==.Dingus:BAABNQAECn8nAAQYAAgKdBp2IgA6AgAYAAcK+Bl2IgA6AgAFAAUKGxYgCgB+AQAEAAEK+RjfRwFPAAAAAA==.',
Dk='Dk:BAAANQADCgYIDQABNQAECgYIEAAGAAAAAA==.',
Do='Doode:BAABNQAECn8hAAMNAAkKGAlgIgC4AQANAAkKGAlgIgC4AQAZAAEKAAC+QgAjAAAAAA==.Doody:BAAANQADCgYIEAABNQAECgkJIQANABgJAA==.',
Dr='Dragonslayer:BAAANQADCgcIBwAAAA==.Dreastotems:BAAANQAECgEIAgAAAA==.Drennifer:BAAANQAECgQICgAAAA==.',
Eb='Ebtyrone:BAAANQAECggIBwAAAA==.',
Em='Emmerson:BAAANQADCgQIBQAAAA==.Emphasis:BAAANQAECgEIAQABNQAECgoKJwAaADUZAA==.',
Es='Escanór:BAAANQADCgUIBwAAAA==.',
Fa='Fajitajones:BAAANQADCgUICgAAAA==.',
Fl='Flanuora:BAAANQABCgYICQAAAA==.',
Fo='Fooksdh:BAAANQADCggICgAAAA==.Fooksdk:BAABNQAECn8xAAMbAAgK9hi4FABiAQAbAAgK9hi4FABiAQADAAUKdgZZlAC3AAAAAA==.Fooksdruid:BAAANQAECgQIDAAAAA==.Forestpimp:BAAANQAECgYIDgAAAA==.',
Fu='Fullometal:BAABNQAECn8gAAISAAkKsRhzCQCuAgASAAkKsRhzCQCuAgAAAA==.Furojin:BAAANQAECgUICQABNQAECgkJIgAEAHwLAA==.',
Ga='Galroot:BAABNQAECn8rAAIPAAkK9SVFBACBAwAPAAkK9SVFBACBAwAAAA==.Galstad:BAAANQABCgEIAQAAAA==.Garrett:BAAANQADCgEIAQAAAA==.',
Ge='Geff:BAAANQADCgQIBAAAAA==.',
Gh='Ghôst:BAAANQAECgUIBgABNQAFFAIIBAAGAAAAAA==.',
Gi='Girthhquake:BAAANQAECgQIBwAAAA==.Gisokaashi:BAAANQADCgcIFgAAAA==.',
Gn='Gnomepwner:BAAANQADCgcIBwAAAA==.',
Go='Gothick:BAAANQAECgUIEAAAAA==.',
Gr='Grimréaper:BAAANQADCgIIAgAAAA==.',
Gu='Guts:BAAANQAECgEIAQAAAA==.',
Ha='Habib:BAAANQABCggIDAAAAA==.Haraneon:BAAANQADCgEIAQAAAA==.Harryhoudini:BAAANQAECgEJAQAAAA==.',
He='Healforfun:BAABNQAECn85AAIPAAoKSBl4AgCqAgAPAAoKSBl4AgCqAgAAAA==.Heilung:BAABNQAECn8sAAQcAAoKrhM1CAAYAgAcAAkKlxI1CAAYAgANAAEK6AQ0TgA1AAAZAAEKJwGfRAAaAAAAAA==.',
Hi='Hippokleides:BAAANQADCgYICgAAAA==.Hirradee:BAABNQAECn8wAAIJAAoKTxZPHwBUAgAJAAoKTxZPHwBUAgAAAA==.',
Ho='Holyzeal:BAAANQAECgQIBAAAAA==.Honatuto:BAAANQAECgQICAAAAA==.',
Hu='Hubelez:BAABNQAECn8bAAIEAAkKUg7ecgArAgAEAAkKUg7ecgArAgAAAA==.',
Hy='Hyacine:BAAANQADCggIGAAAAA==.',
Ic='Icecweam:BAAANQADCggIDgAAAA==.Icehott:BAAANQAECgIIAgAAAA==.Icthelight:BAAANQAECgMIAwAAAA==.',
Ig='Ightbet:BAAANQAECgEIAgAAAA==.',
Ii='Iista:BAAANQAECgIIAgAAAA==.',
Ir='Irontuskss:BAAANQAECgQIBgAAAA==.',
Iz='Iznthyr:BAAANQABCgIIAgAAAA==.',
Ja='Jayar:BAABNQAECn8nAAMaAAoKNRlBDACPAQAaAAoKNRlBDACPAQAdAAEKAAAUNwAhAAAAAA==.',
Jd='Jdawgg:BAAANQAECgEIAQAAAA==.',
Jo='Jorley:BAAANQADCggIDwAAAA==.',
Jr='Jrwriter:BAAANQAECgYIEAAAAA==.',
Jy='Jym:BAAANQAECgcIDgAAAA==.',
Ka='Kaijin:BAABNQAECn8dAAIXAAgKTxbjJwDhAQAXAAgKTxbjJwDhAQAAAA==.Kalasting:BAAANQAECgMIBgABNQAECgkJKwAOANYfAA==.Kalyr:BAABNQAECn8XAAIKAAgKHhPXEABTAQAKAAgKHhPXEABTAQAAAA==.Kandrianna:BAABNQAECn8nAAIMAAgKyAVHPABIAQAMAAgKyAVHPABIAQAAAA==.',
Ke='Keraasi:BAABNQAECn8oAAMHAAkK7RSBPgBqAgAHAAkK7RSBPgBqAgABAAEKYwdbrAExAAAAAA==.Kevinv:BAAANQADCgEIAQAAAA==.',
Kh='Khristine:BAAANQADCgQIBAABNQAECgoKJwAaADUZAA==.',
Ki='Kikai:BAAANQADCgUICQAAAA==.Kilrav:BAABNQAECn8cAAIeAAgK4xgfSAD3AQAeAAgK4xgfSAD3AQAAAA==.Kimberlee:BAAANQAECggIDgAAAA==.Kiryanna:BAAANQAECgQIBQAAAA==.Kitiara:BAAANQAECgQIBAAAAA==.',
Kl='Klayah:BAABNQAECn8ZAAMDAAcKERtUUgCrAQADAAYKMBtUUgCrAQAbAAYKgBaLRwCgAQAAAA==.',
Ko='Koogz:BAAANQAECgcIDwAAAA==.Kordelia:BAABNQAECn8kAAMHAAoK8Rb5GgCFAQAHAAoK8Rb5GgCFAQABAAMKZQM4dwFlAAAAAA==.Korgmafx:BAAANQADCgUIEAAAAA==.',
Kr='Kratosol:BAAANQAECgEJAQAAAA==.',
Ku='Kudre:BAAANQABCgIIAgAAAA==.',
Ky='Kynigos:BAAANQADCggIEAABNQAECggIJAAVAKccAA==.',
La='Larke:BAAANQAECgQIBwAAAA==.',
Le='Leilany:BAAANQAECgcIDgAAAA==.Lethäl:BAAANQADCgIIAgAAAA==.',
Li='Littledirk:BAAANQADCgcIAgAAAA==.',
Ll='Llillies:BAAANQAECgQIBwAAAA==.',
Lo='Loramor:BAAANQADCggICAAAAA==.',
Lu='Lucioush:BAAANQADCggICAAAAA==.Lugnuts:BAAANQAECgQIBQAAAA==.',
Ma='Magebuff:BAACNQAFFH8IAAIWAAMKPg8KGQCcAAAWAAMKPg8KGQCcAAA1AAQKfzgAAhYACgoWHpkWALcBABYACgoWHpkWALcBAAAA.Malroy:BAAANQADCgYIBgAAAA==.',
Mc='Mcheals:BAAANQADCgcIDgAAAA==.',
Mi='Miidniter:BAAANQAECgQICgAAAA==.',
Mo='Monsunami:BAAANQAECgQICAAAAA==.Moogar:BAABNQAECn8tAAMfAAoKaCHUBgCMAwAfAAoKaCHUBgCMAwAIAAEKuwPQNwEyAAAAAA==.Moolinda:BAAANQAECgMIAwAAAA==.Moonlock:BAAANQADCggICAAAAA==.Morte:BAAANQADCgIIAgAAAA==.Moònflower:BAAANQAECgIIAgAAAA==.',
Mu='Mushroom:BAAANQADCgEIAQABNQADCgEIAQAGAAAAAA==.',
['Mø']='Møøse:BAABNQAECn8iAAIfAAgKGhxsPQBqAgAfAAgKGhxsPQBqAgAAAA==.',
Na='Namegoeshere:BAAANQAECgMIAwABNQAECgkJIgAEAHwLAA==.Nanwu:BAABNQAECn8kAAIIAAgKdxWxIQA1AQAIAAgKdxWxIQA1AQAAAA==.Narcyon:BAABNQAECn8rAAMOAAkK1h/IBQCfAgAOAAkK1h/IBQCfAgAMAAYKARQDOABlAQAAAA==.',
Ne='Neonfel:BAAANQADCggICAAAAA==.',
Nh='Nhox:BAAANQAECgQIDQAAAA==.Nhöxx:BAAANQADCgUIBwAAAA==.',
No='Noobîtîs:BAAANQAECgMIAwAAAA==.Notmaxxie:BAAANQAECgYICgAAAA==.',
Ny='Nystiae:BAAANQADCggICgAAAA==.',
Ob='Obscur:BAAANQAECgEIAQABNQAECgoKHAAQAPYZAA==.Obz:BAABNQAECn8cAAMQAAoK9hmfMgAxAQAQAAkKQhufMgAxAQARAAIKJhDEWgBwAAAAAA==.',
Od='Oddlylight:BAAANQAECgQICQAAAA==.',
Og='Ogzugz:BAAANQABCgUIBQAAAA==.',
Ol='Ollie:BAAANQADCgIIAgAAAA==.',
Ox='Oxytocin:BAAANQADCgIIAgAAAA==.',
Pa='Pandicated:BAECNQAFFH8IAAIXAAMKiQiVBgCOAAAXAAMKiQiVBgCOAAA1AAQKfzQABBcACgo6FaMZAHYCABcACgoZEqMZAHYCACAABwrXFjwSAMEBACEAAQpbAHVYABMAAAAA.',
Pe='Pelondar:BAAANQADCggIEwAAAA==.',
Ph='Phalanx:BAAANQADCgYIFAAAAA==.',
Pi='Pickleburger:BAAANQADCgUICAAAAA==.',
Pl='Plaguedoctor:BAAANQADCgQJBAAAAA==.',
Po='Pookalicious:BAAANQADCgQIBAAAAA==.Pookiebear:BAAANQAECgEIAQAAAA==.Possessed:BAAANQADCgYICgAAAA==.',
Pr='Prìdè:BAAANQAECgcIEwAAAA==.Prïdë:BAAANQAECgIIAgAAAA==.',
Pu='Punjana:BAAANQABCgMIAwAAAA==.',
Ra='Raike:BAAANQADCgMIAwAAAA==.Razmae:BAAANQAECgMIAwAAAA==.',
Re='Rennala:BAAANQAECgEIAQAAAA==.',
Ri='Riceball:BAAANQADCgMIAwAAAA==.Riptide:BAABNQAECn8cAAIWAAoKAA8MwgAAAgAWAAoKAA8MwgAAAgAAAA==.Risto:BAABNQAECn8mAAMiAAkKNSGgAwArAQAQAAcKHB64IABsAQAiAAQKRiKgAwArAQAAAA==.',
Ro='Rockon:BAABNQAECn8cAAIIAAkK/AlTbADbAQAIAAkK/AlTbADbAQABNQADCgcIDgAGAAAAAA==.Roden:BAAANQABCgMIAwAAAA==.Ronzertnin:BAABNQAECn8eAAIRAAgKCBRsAQCGAQARAAgKCBRsAQCGAQAAAA==.Roxen:BAAANQADCggIFQAAAA==.',
Ru='Runananako:BAAANQAECgUICwAAAA==.',
Ry='Ryo:BAAANQADCggIEAAAAA==.',
['Ré']='Réaper:BAAANQADCgcIDwAAAA==.Rénji:BAABNQAECn8cAAIXAAgKhA7wEwAMAQAXAAgKhA7wEwAMAQAAAA==.',
Sa='Salana:BAAANQAECgMIBwAAAA==.San:BAABNQAECn8hAAMjAAoK3R2DBgCzAQAjAAkK3R2DBgCzAQATAAIK9BIkFwB0AAABNQAFFAIIBgAOAHgOAA==.Sandroin:BAAANQAECgEIAQAAAA==.Sarah:BAAANQADCggIDAABNQAECgkJMAAOAF4kAA==.',
Sc='Scarf:BAABNQAECn8oAAMkAAgK+QwOJgBtAQAkAAgK+QwOJgBtAQAlAAEKWANySwAdAAAAAA==.',
Sh='Shiggy:BAAANQADCggICAAAAA==.Shinerbock:BAABNQAECn8YAAIEAAgKCQljnADOAQAEAAgKCQljnADOAQAAAA==.Shipoopi:BAABNQAECn8UAAMUAAcK7RGQHgB4AQAUAAYKXhCQHgB4AQAIAAMK+xas6QDDAAAAAA==.Shock:BAABNQAECn8lAAIIAAgKpCM6BwD0AQAIAAgKpCM6BwD0AQAAAA==.Shortnshady:BAABNQAECn8oAAImAAgK7xAoCwCIAQAmAAgK7xAoCwCIAQAAAA==.',
Si='Sithen:BAAANQAECgMIAwAAAA==.',
Sk='Skankadin:BAAANQADCgYICQABNQAECgIIBQAGAAAAAA==.Skankerella:BAAANQAECgIIBQAAAA==.Skiatrochia:BAAANQADCggICAABNQAECgoKMAAJAE8WAA==.Skipuscales:BAABNQAECn8lAAIZAAoKDR5HBQA/AwAZAAoKDR5HBQA/AwAAAA==.',
Sm='Smoaky:BAABNQAECn8nAAISAAgKYQeYGgBWAQASAAgKYQeYGgBWAQAAAA==.',
So='Soul:BAABNQAECn89AAMKAAoKCRxIAgCIAgAKAAoKCRxIAgCIAgALAAQKzQhiRACjAAAAAA==.Soulscorcher:BAAANQADCggIFAAAAA==.Soulsurvivor:BAAANQAECgcIDAABNQAECgcIGQANANgNAA==.Sovietpanda:BAAANQADCgUICAAAAA==.',
Sp='Spanky:BAAANQAECgQIBgAAAA==.Spankyohs:BAAANQADCgcJDAAAAA==.Spindles:BAAANQAECgEIAQAAAA==.Spineless:BAAANQAECgIIAgAAAA==.Spiritgun:BAAANQAECgEIAQABNQAECgYIEAAGAAAAAA==.',
St='Stimpack:BAABNQAECn8ZAAINAAcK2A1TKwBRAQANAAcK2A1TKwBRAQAAAA==.',
Su='Sutures:BAAANQADCgYIDgAAAA==.',
['Sö']='Sönja:BAAANQAECgIIBAAAAA==.',
Ta='Tacotuesday:BAAANQABCgcIBwAAAA==.Tará:BAAANQAECgUJCQAAAA==.',
Te='Techpriest:BAAANQAECgUIBgAAAA==.Tehblink:BAABNQAECn8mAAIVAAgK5h0VBwCFAgAVAAgK5h0VBwCFAgAAAA==.Tenative:BAAANQAECgUICAABNQAECgoKLAAQAL0dAA==.Tenoch:BAAANQAECgUIDQAAAA==.Terah:BAAANQADCgIIAgAAAA==.',
To='Tobibobi:BAAANQADCgUIBQAAAA==.Toomez:BAAANQADCggICgAAAA==.Touchmydemon:BAAANQAECgYICgAAAA==.',
Tr='Trea:BAABNQAECn8hAAIEAAgKrxQ+QQAzAQAEAAgKrxQ+QQAzAQAAAA==.',
Tu='Tupkiss:BAABNQAECn8pAAIMAAgKXR9KEQDnAgAMAAgKXR9KEQDnAgAAAA==.',
Ty='Tygrand:BAAANQAECgcICwABNQAECggIJwASAGEHAA==.',
Va='Vazer:BAAANQABCgMIAwAAAA==.',
Vl='Vlannpire:BAEANQADCgcIBwABNQAECgYIDgAGAAAAAA==.',
Vo='Voidtouched:BAAANQADCggICAAAAA==.',
Wa='Waffledead:BAABNQAECn8kAAQiAAkKmhl3CQDrAQAiAAYKLBt3CQDrAQAQAAYK5xMknwCYAQARAAQKXBveJgA/AQAAAA==.Wafflelight:BAAANQADCgcIBwAAAA==.Walshy:BAAANQAECggICQAAAA==.Warpfiend:BAABNQAECn8dAAMUAAgK/R0LAwD2AQAUAAgKvB0LAwD2AQAIAAUKbx0qfwCnAQAAAA==.Warpinferno:BAAANQADCggIDgAAAA==.',
We='Wek:BAAANQADCgUIBQAAAA==.Wetnugget:BAAANQAECgYIBwAAAA==.',
Wi='Winnie:BAAANQADCgEIAQAAAA==.',
Wo='Wolfnhowz:BAAANQAECgIIAgAAAA==.',
Wy='Wyhm:BAAANQADCgIIAgAAAA==.',
Yu='Yuriko:BAAANQADCgYIDAAAAA==.',
Za='Zandragon:BAAANQADCgQIBAAAAA==.',
Ze='Zebubblez:BAAANQAECgIIAwAAAA==.',
Zg='Zgux:BAAANQAECgUICAAAAA==.',
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
