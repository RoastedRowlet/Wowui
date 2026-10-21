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

local lookup = {'Shaman-Enhancement','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','Paladin-Retribution','DeathKnight-Frost','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Holy','Mage-Arcane','Druid-Balance','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Demonology','Unknown-Unknown','Evoker-Preservation','Warrior-Arms','Priest-Discipline','Priest-Shadow','DemonHunter-Vengeance','Druid-Restoration','Evoker-Devastation','Mage-Frost','DeathKnight-Blood','Warrior-Protection','Rogue-Assassination','Warrior-Fury','Warlock-Destruction','Rogue-Subtlety','Mage-Fire','DeathKnight-Unholy','Druid-Guardian','Warlock-Affliction','Evoker-Augmentation','Paladin-Protection','Druid-Feral','Monk-Windwalker','Monk-Mistweaver',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aayrawn:BAABNQAECn8nAAMBAAkKdxvaDACgAgABAAgKox7aDACgAgACAAIKPAZDlwA3AAAAAA==.',
Ac='Aceofplagues:BAAANQADCgQIBAABNQAECgkJFQADADkcAA==.Acesdruid:BAAANQAECgYICwABNQAECgkJFQADADkcAA==.Aceshaman:BAABNQAECn8VAAMDAAkKORxITQBBAgADAAgKNRxITQBBAgABAAgKgBY2FwD1AQAAAA==.',
Ai='Airone:BAAANQAECgQIBwAAAA==.',
Ak='Akadion:BAAANQADCggICAAAAA==.',
Al='Alextros:BAEANQABCgIIAwABNQAECgoKKwAEAEMgAA==.Alluriel:BAAANQADCgIIAgAAAA==.',
Am='Amaranthe:BAAANQAECgEIAQAAAA==.Amrax:BAABNQAECn8gAAIFAAgK8w69UwAdAQAFAAgK8w69UwAdAQAAAA==.',
An='Antijastran:BAABNQAECn8gAAIGAAgKyQrkJAAOAQAGAAgKyQrkJAAOAQAAAA==.',
Aq='Aquabat:BAABNQAECn8nAAMHAAkKth47EADnAgAHAAkKnB47EADnAgAIAAEK/CBARQFUAAAAAA==.Aquda:BAAANQADCgUIAgAAAA==.',
Ar='Artemist:BAAANQADCgUICgAAAA==.Arthás:BAAANQADCgMIAwAAAA==.',
As='Ashbringer:BAABNQAECn85AAIFAAoKCCa+BADTAwAFAAoKCCa+BADTAwAAAA==.',
At='Athalax:BAAANQADCgEIAQAAAA==.Attia:BAAANQAECgcIDQAAAA==.',
Ba='Baladoria:BAABNQAECn8jAAIJAAoKDhC4ZADyAQAJAAoKDhC4ZADyAQAAAA==.Baldkrank:BAABNQAECn8UAAIKAAkKEQu+ZQDxAAAKAAkKEQu+ZQDxAAAAAA==.Bama:BAAANQAECggICQAAAA==.Bananabowman:BAABNQAECn8XAAIIAAoKJh5OHgAeAwAIAAoKJh5OHgAeAwAAAA==.Banditos:BAAANQAECgcIDQAAAA==.Bartab:BAABNQAECn8mAAICAAkKtR1GKwC2AgACAAkKtR1GKwC2AgABNQAECgcIGQALAPEOAA==.',
Be='Bearemy:BAAANQAECgEIAQABNQAECggIIwAMAHoZAA==.Beastling:BAAANQAECgUICgAAAA==.Beau:BAACNQAFFH8IAAINAAMKKBRbCACUAAANAAMKKBRbCACUAAA1AAQKfzsAAg0ACgpaIYUKAFwDAA0ACgpaIYUKAFwDAAAA.Beauwi:BAAANQADCggIEQABNQAFFAMICAANACgUAA==.Bestia:BAAANQAECgEIAQABNQAFFAIIBQAOAJAQAA==.Bettyßrisco:BAABNQAECn8fAAIIAAoKWRYVEADvAQAIAAoKWRYVEADvAQAAAA==.',
Bi='Bigchungusyo:BAAANQADCgYIBwAAAA==.Bigpapi:BAAANQAECgMIAwAAAA==.',
Bl='Blawkk:BAAANQADCggIEAAAAA==.Blessthem:BAAANQADCgcICgAAAA==.',
Bo='Bombur:BAABNQAECn8kAAIPAAcKyhAqRwD8AAAPAAcKyhAqRwD8AAAAAA==.Bonejovi:BAAANQADCgIIAgAAAA==.Bottles:BAAANQAECgcIBwABNQAECggIEQAQAAAAAA==.',
Br='Bratva:BAAANQAECgMIAwAAAA==.Brokenbubble:BAAANQAECgUIBgABNQAFFAYIFAARAAobAA==.Brozown:BAAANQADCgQIBAABNQAECgkJJwAHALYeAA==.Brëtski:BAAANQAECgcICwAAAA==.',
Bu='Bubagony:BAAANQAECggIEgABNQAFFAUIEgALABgUAA==.Burakku:BAAANQADCgMIBQABNQAFFAMICgADAFsVAA==.Buzza:BAAANQAECgUIDAAAAA==.Buzzkill:BAABNQAECn8XAAIPAAcKyxgqIABvAQAPAAcKyxgqIABvAQAAAA==.',
Ca='Calinash:BAABNQAECn8pAAIKAAoKgBnpKgBvAQAKAAoKgBnpKgBvAQAAAA==.Calzraxx:BAABNQAECn8aAAISAAcK8hZGkwDsAQASAAcK8hZGkwDsAQAAAA==.Cartons:BAAANQADCgQIBAABNQAECggIEQAQAAAAAA==.',
Cc='Ccaan:BAAANQAECggIEwAAAA==.',
Ce='Celinn:BAABNQAECn8jAAIJAAoKohVyJABuAQAJAAoKohVyJABuAQAAAA==.',
Ch='Charliek:BAABNQAECn8XAAISAAgK1A4aqAC5AQASAAgK1A4aqAC5AQAAAA==.Cheebah:BAAANQADCggICAAAAA==.Chimalma:BAABNQAECn8YAAMCAAkKXhxaIgDeAgACAAkKXhxaIgDeAgADAAUKdxq5tQAnAQAAAA==.Chingoblingo:BAAANQADCggIFgAAAA==.Chorr:BAAANQAECgIIAgABNQAECgYICQAQAAAAAA==.',
Ck='Ckaan:BAAANQADCggICAAAAA==.',
Co='Cobygo:BAAANQADCggIDwAAAA==.Coffins:BAAANQADCgYIBgABNQAECggIEQAQAAAAAA==.',
Cr='Crates:BAAANQAECggIEQAAAA==.Cringely:BAABNQAECn8kAAQJAAkKOiILCwBqAwAJAAkKOiILCwBqAwATAAIK9BoVGgCaAAAUAAEKAABWlwAJAAAAAA==.Croakam:BAAANQADCgIIAgABNQAFFAMIBgAVACghAA==.Crosswalkk:BAAANQAECgIIAwAAAA==.Cryface:BAAANQAECgEIAQABNQABCgQIBAAQAAAAAA==.',
Cu='Curonconagua:BAAANQADCgcICAAAAA==.',
Cy='Cypherrellik:BAAANQAECgYICwAAAA==.',
['Cö']='Cöldcancer:BAAANQADCgQIAwAAAA==.',
Da='Daktok:BAAANQAECgMIBgAAAA==.Dargar:BAAANQADCgYIBgAAAA==.Darknyss:BAAANQADCgEJAQAAAA==.Darkozygo:BAAANQADCggIKAABNQAECgQIBAAQAAAAAA==.',
De='Deathfortres:BAABNQAECn8jAAMWAAkK/A5mCwCDAQAWAAgK1g9mCwCDAQALAAYKCwWpewDdAAAAAA==.Deathstar:BAAANQADCgEIAQAAAA==.Deidara:BAACNQAFFH8FAAMOAAIKkBB8BgCLAAAOAAIKXgt8BgCLAAANAAEKPRgPHQBEAAA1AAQKfzQAAw0ACgqKH+MOAC0DAA0ACQrJIuMOAC0DAA4ACArsFCAmABUCAAAA.Demolish:BAAANQADCggIDgAAAA==.Demongrass:BAACNQAFFH8IAAIOAAQKaRT7AwDeAAAOAAQKaRT7AwDeAAA1AAQKfxkAAg4ACQpSGh8XAKYCAA4ACQpSGh8XAKYCAAAA.Devit:BAAANQAECgQICAAAAA==.',
Di='Dimka:BAAANQADCggIEgAAAA==.Dirtyfox:BAAANQADCgQIBAAAAA==.Disarray:BAABNQAECn8hAAIOAAkKOx6oDAAYAwAOAAkKOx6oDAAYAwAAAA==.',
Do='Dontar:BAAANQAECgUIBgAAAA==.Donvald:BAAANQAECgIIAwAAAA==.Doodaad:BAAANQADCgYICwAAAA==.Doublerack:BAAANQAECgYIDwABNQABCgQIBAAQAAAAAA==.',
Dr='Dragondznuts:BAACNQAFFH8UAAIRAAYKChsbAgDwAQARAAYKChsbAgDwAQA1AAQKfy8AAxcACgoNG/gfAFcBABcABQosGPgfAFcBABEACgrCGesIADMBAAAA.Druzizzle:BAAANQADCgQIBAAAAA==.Dríppy:BAAANQAECgQIBwAAAA==.',
Ed='Edrian:BAAANQABCgEIAQAAAA==.',
Ei='Eilerra:BAABNQAECn8dAAMYAAcKJBmQEgB+AQAKAAYKxRAr/wCPAQAYAAUKnhyQEgB+AQAAAA==.',
Er='Erre:BAABNQAECn8tAAIPAAoK+x2ALwDJAgAPAAoK+x2ALwDJAgAAAA==.',
Ex='Exxitwound:BAAANQADCggIEAAAAA==.',
Fa='Fallenhunt:BAAANQADCgQIBAAAAA==.',
Fi='Finniessa:BAAANQADCgMIBAAAAA==.Firesson:BAAANQAECgUIEQAAAA==.',
Fo='Fourroadsgz:BAAANQAECgQIBAAAAA==.Foxoffire:BAAANQAECgQIBwAAAA==.Foxtracks:BAAANQADCgEIAQAAAA==.Fozzee:BAAANQAECgUIBQABNQAECgkJJAAJADoiAA==.',
Fr='Fritark:BAABNQAECn8qAAMGAAgKdRf7NQABAgAGAAgKnxX7NQABAgAZAAQKNBegfQADAQAAAA==.Fritzyp:BAAANQAECgMIAwABNQAECggIKgAGAHUXAA==.Frostyburn:BAAANQAECgIIBAAAAA==.',
['Fë']='Fëanor:BAAANQAECggIBwAAAA==.',
Ge='Gena:BAAANQADCggIGQAAAA==.Geörge:BAACNQAFFH8MAAIUAAUKER5sBwCgAQAUAAUKER5sBwCgAQA1AAQKfzgAAhQACgpKIwEFAIgDABQACgpKIwEFAIgDAAAA.',
Gh='Ghostbath:BAAANQABCgUIBQAAAA==.',
Go='Goated:BAABNQAECn8iAAMaAAkKACSuAQAoAgASAAgKbiCDYQBpAgAaAAcKgiWuAQAoAgAAAA==.',
Gr='Gremfrost:BAABNQAECn8dAAIYAAkK9RK+DQDTAQAYAAkK9RK+DQDTAQAAAA==.Grotelek:BAABNQAECn8uAAICAAoKHhV3YADtAQACAAoKHhV3YADtAQAAAA==.Grumpywaltz:BAABNQAECn8nAAIaAAgKzxNHFQDTAQAaAAgKzxNHFQDTAQAAAA==.',
Gu='Gunhild:BAAANQADCgQIBAAAAA==.Guthy:BAAANQAECgMIAwAAAA==.',
Ha='Haedrath:BAAANQAECgcICwABNQAECgcIHQAYACQZAA==.Hahafunny:BAAANQADCggICQAAAA==.Halcotsu:BAABNQAECn8mAAIPAAoKMwprFQCgAQAPAAoKMwprFQCgAQAAAA==.Halleko:BAABNQAECn8aAAIFAAoKhByxWACNAgAFAAoKhByxWACNAgABNQAFFAYIEwAbAAcbAA==.Hammerfoot:BAAANQAECgYIDQAAAA==.Hark:BAAANQADCgcIBwAAAA==.Harkknight:BAAANQAECgYIEwAAAA==.Haurtrue:BAABNQAECn8iAAILAAgKnRt2KgCFAgALAAgKnRt2KgCFAgAAAA==.Hawgbawl:BAABNQAECn8vAAIcAAoK2BdJAwCXAQAcAAoK2BdJAwCXAQAAAA==.Hawgdream:BAABNQAECn8UAAIdAAUKbQrgMAAEAQAdAAUKbQrgMAAEAQAAAA==.',
He='Heliah:BAAANQABCgIIAgAAAA==.Hellequin:BAACNQAFFH8TAAMbAAYKBxs1BAAHAgAbAAYKBxs1BAAHAgAeAAEKOQE6FwA0AAA1AAQKfzkAAxsACgppIWkEAJADABsACgppIWkEAJADAB4ABgpUHeAhAL0BAAAA.Heyyitzrichh:BAABNQAECn8eAAMdAAkKzCBWJABPAQAPAAcK3h+/ggDfAQAdAAQKLSJWJABPAQAAAA==.',
Ho='Hollinar:BAABNQAECn8WAAIKAAkKRwpUzwDnAQAKAAkKRwpUzwDnAQAAAA==.Holycøw:BAAANQAECgQIBAAAAA==.Hondoe:BAAANQAECgMIAwAAAA==.',
Ih='Ihavecookies:BAAANQAECgEIAQAAAA==.',
Im='Imahealer:BAAANQAECgYICwAAAA==.',
In='Invaled:BAAANQAECgUICAAAAA==.',
Ir='Irateknight:BAAANQAECgEIAQAAAA==.Irely:BAAANQADCgUIBQAAAA==.',
Is='Isegrim:BAAANQAECgQIBwAAAA==.',
It='Itzrich:BAAANQAECgQIBwAAAA==.',
Ja='Jakelong:BAAANQAECgQICQABNQAFFAIIBgAFAFseAA==.Jasmirangel:BAABNQAECn8pAAIWAAkKpCRAAgCrAwAWAAkKpCRAAgCrAwAAAA==.',
Je='Jenesis:BAAANQAECgYIDQAAAA==.Jermajesty:BAABNQAECn8jAAIMAAgKehn9HAB5AQAMAAgKehn9HAB5AQAAAA==.Jezus:BAAANQABCgYJDwAAAA==.',
Jo='Joanoforc:BAAANQAECgEIAQABNQAECgYIDgAQAAAAAA==.Joci:BAAANQAECgYIBgAAAA==.Jovar:BAAANQADCgMIAwAAAA==.',
['Jö']='Jöker:BAAANQAECgMIAwAAAA==.',
Ka='Kalzifer:BAABNQAECn8bAAIfAAgKwQsLBACCAQAfAAgKwQsLBACCAQABNQAFFAIIBQAGAOoOAA==.Kankaladin:BAACNQAFFH8GAAIFAAIKWx4vDgCWAAAFAAIKWx4vDgCWAAA1AAQKfykAAgUACgpeIicoACUDAAUACgpeIicoACUDAAAA.Kanky:BAAANQAECgUIBQABNQAFFAIIBgAFAFseAA==.Kano:BAABNQAECn8nAAMIAAoKEhjTKwBtAQAHAAkKVwk2NQCkAQAIAAkK7xfTKwBtAQAAAA==.Karper:BAAANQADCgYIBgAAAA==.Kavern:BAAANQADCgUIBQAAAA==.Kawada:BAABNQAECn8XAAIdAAgKTAtOHQCDAQAdAAgKTAtOHQCDAQAAAA==.Kayhaus:BAAANQADCgQIBAAAAA==.',
Ke='Ken:BAABNQAECn8gAAMgAAgKhSHfHwDMAgAgAAgKhSHfHwDMAgAGAAUKVxLLXwAmAQAAAA==.Kennedï:BAAANQADCgQIBAAAAA==.Kennëdi:BAABNQAECn8mAAICAAgKAxmyCgAYAgACAAgKAxmyCgAYAgAAAA==.',
Kh='Khory:BAAANQAECgYICQAAAA==.',
Ki='Kichirõ:BAABNQAECn8jAAIEAAgKaQkbGABiAQAEAAgKaQkbGABiAQAAAA==.Killrah:BAAANQADCgIIAgAAAA==.Kilrah:BAAANQADCgMIAwAAAA==.Kilriella:BAAANQADCgMIBAAAAA==.Kimuri:BAAANQAECgEIAQAAAA==.',
Km='Kmt:BAAANQADCggIDgABNQAECgUICwAQAAAAAA==.',
Ko='Koffee:BAAANQAECgcIDAABNQAFFAIIBgAFAFseAA==.Korgigor:BAAANQADCgEJAQAAAA==.',
Kt='Kt:BAAANQAECgUICwAAAA==.',
Ku='Kuailiang:BAAANQADCgYIBgABNQAECgoKNAAOAE0SAA==.',
La='Ladezar:BAAANQADCgYJBgAAAA==.Laissen:BAAANQADCgYIGAAAAA==.Lapsung:BAAANQAECggICgABNQAECgcIDQAQAAAAAA==.Lattemocha:BAABNQAECn8dAAMWAAcKPAzqOQBPAQAWAAcKPAzqOQBPAQALAAYKlwmEcAAIAQAAAA==.',
Le='Leprechaun:BAABNQAECn8UAAMhAAYKngvTJwBrAAALAAYKngvccQADAQAhAAQKeQbTJwBrAAABNQAECggICQAQAAAAAA==.Leprechauñ:BAAANQAECgQICgABNQAECggICQAQAAAAAA==.Leprecháun:BAAANQAECgIIAwABNQAECggICQAQAAAAAA==.Lepréchaun:BAAANQAECggICQAAAA==.',
Li='Liche:BAAANQAECgEIAQABNQAFFAIIBQAOAJAQAA==.Lighthoove:BAAANQADCgcIBwAAAA==.Lightsir:BAAANQADCgMIBwAAAA==.Lilfuse:BAAANQAECgEIAQAAAA==.Lishalle:BAAANQADCgUIBQABNQAECgoKKwAKAD4ZAA==.',
Lo='Loutone:BAAANQADCgcIFgAAAA==.',
Lu='Ludlow:BAAANQAECgQIBgAAAA==.Lunatonne:BAABNQAECn8fAAIIAAkKBBjyQACoAgAIAAkKBBjyQACoAgAAAA==.Luneztoprime:BAABNQAECn8VAAIgAAUKaCN2UADSAQAgAAUKaCN2UADSAQAAAA==.Luvlybella:BAAANQAECgQICAAAAA==.',
Ly='Lyiann:BAAANQADCgYICgAAAA==.Lyákadion:BAAANQADCggIEgAAAA==.',
Ma='Mafi:BAAANQAECgcIEQAAAA==.Malady:BAAANQADCgYICgAAAA==.Mallypally:BAAANQAECgMIAwABNQAECgUIDQAQAAAAAA==.Matt:BAACNQAFFH8MAAIWAAUKxRKZAwBAAQAWAAUKxRKZAwBAAQA1AAQKfy0AAhYACgorHLoOAOgCABYACgorHLoOAOgCAAAA.Matte:BAACNQAFFH8GAAICAAMKVBYBGwDCAAACAAMKVBYBGwDCAAA1AAQKfyUAAwIACgomGTU2AIYCAAIACgomGTU2AIYCAAMAAQoAAPVHASoAAAE1AAUUBQgMABYAxRIA.Mazza:BAAANQAECgcIDwAAAA==.',
Me='Meddicus:BAAANQAECgcICgAAAA==.Megorice:BAAANQADCgcIBwAAAA==.Mewtwô:BAAANQAECggIDwAAAA==.',
Mi='Miedillø:BAAANQAFFAEIAQABNQAFFAcIKQAIADcfAA==.Mikeoxmall:BAACNQAFFH8GAAIIAAIKTx7aCgC4AAAIAAIKTx7aCgC4AAA1AAQKfy0AAwgACgoGHs8wANoCAAgACQoyIs8wANoCAAcABQrJDOlOAPMAAAAA.',
Mo='Monstermime:BAABNQAECn8nAAQiAAgKWRcbCQD1AQAiAAgK0hUbCQD1AQAPAAUKWxRkxgA+AQAdAAQKmQ4+MQACAQAAAA==.Moonpièz:BAAANQADCggIDQAAAA==.Moosetrax:BAABNQAECn8pAAIZAAoKRw0AVgCcAQAZAAoKRw0AVgCcAQAAAA==.',
Mu='Muffy:BAAANQADCgQIBAAAAA==.Mushumime:BAAANQADCgYIDAABNQAECggIJwAiAFkXAA==.',
My='Myserie:BAABNQAECn8fAAIUAAkKKQ7JKgDRAQAUAAkKKQ7JKgDRAQAAAA==.Mystikah:BAAANQADCgMIAwAAAA==.',
Na='Napshade:BAAANQAECgEIAQABNQAECgYIBQAQAAAAAA==.Natsuu:BAAANQAECgUIBQAAAA==.Nazara:BAACNQAFFH8QAAMXAAUKPBiyAQC7AAAXAAUKPBiyAQC7AAARAAMKgwG9EwCYAAA1AAQKfysAAxcACgrtG4cKAMMCABcACgrtG4cKAMMCABEAAgr1C6xIAF0AAAE1AAQKBggJABAAAAAA.',
Ne='Neuro:BAABNQAECn8zAAIKAAoKYhmugAB9AgAKAAoKYhmugAB9AgAAAA==.Neyvin:BAAANQADCgIIBAAAAA==.',
Ni='Nightfiress:BAAANQAECgEIAQAAAA==.Nikodemos:BAAANQAFFAcIEgAAAQ==.',
Nk='Nkáujhmóob:BAAANQAECgUIBQAAAA==.',
Oo='Oopsifer:BAAANQAECgQICAAAAA==.Oowu:BAAANQADCgcIDQAAAA==.',
Op='Optimum:BAAANQAECgIIAgAAAA==.',
Or='Oran:BAAANQADCggIDgAAAA==.',
Pe='Persimmon:BAAANQAECgYICgAAAA==.Peyton:BAAANQAECgIJAgAAAA==.',
Pi='Piecemaker:BAACNQAFFH8MAAIIAAUKExxQDQB+AQAIAAUKExxQDQB+AQA1AAQKf1MAAggACgoKIdkCAMYCAAgACgoKIdkCAMYCAAAA.',
Pl='Plaguepapi:BAAANQADCgIJAgAAAA==.',
Pr='Pravin:BAAANQADCgIIBAAAAA==.Proslicer:BAAANQADCggIHAAAAA==.',
Pu='Pufdaddy:BAAANQABCgMIAwAAAA==.Puppetslayer:BAAANQAECgYIDwAAAA==.',
Py='Pyrrah:BAABNQAECn8rAAMMAAgKCCDkHwDwAgAMAAgKCCDkHwDwAgAFAAcKhhZlrwDAAQAAAA==.Pyrri:BAAANQAECgQIBQABNQAECggIKwAMAAggAA==.',
['Pé']='Péytón:BAAANQADCgQIBgAAAA==.',
Qu='Quanchì:BAABNQAECn80AAIOAAoKTRK/IABHAgAOAAoKTRK/IABHAgAAAA==.',
Ra='Rabuf:BAABNQAECn8dAAIMAAcKPxwOHAB+AQAMAAcKPxwOHAB+AQAAAA==.Raccoonadin:BAAANQAECgEIAQAAAA==.Radha:BAABNQAECn8XAAISAAoKsBgGPQDUAgASAAoKsBgGPQDUAgABNQAFFAUIEgALABgUAA==.Rageruññer:BAAANQADCgYIBgAAAA==.',
Re='Redfenris:BAAANQAECgYIDQABNQAECgoKNAAOAE0SAA==.Redizle:BAAANQADCggICAABNQAFFAcIFQAMAJ8WAA==.Reginrune:BAAANQAECggIBQAAAA==.Resonance:BAAANQAECgMIBAAAAA==.',
Rh='Rhaenyr:BAAANQAECgIIBQAAAA==.',
Ri='Ridizle:BAACNQAFFH8VAAIMAAcKnxbsBgD7AQAMAAcKnxbsBgD7AQA1AAQKfzMAAgwACgqQH9kRAEADAAwACgqQH9kRAEADAAAA.',
Ro='Rohdoog:BAABNQAECn8VAAIjAAgKsBSzCQDhAQAjAAgKsBSzCQDhAQAAAA==.',
Ru='Runedyu:BAABNQAECn8eAAIgAAcKdxEdEgBMAQAgAAcKdxEdEgBMAQAAAA==.',
Ry='Ryanno:BAABNQAECn8iAAMIAAoKeSAwHwAbAwAIAAoKeSAwHwAbAwAHAAYKYQ0PQABTAQAAAA==.Ryannoo:BAAANQAECggICAAAAA==.Ryunosuke:BAAANQAECggIDAABNQAFFAIIBQAOAJAQAA==.',
Sa='Sahomi:BAACNQAFFH8IAAIJAAMKLQrOIgDKAAAJAAMKLQrOIgDKAAA1AAQKfyYAAwkACgoCESlSAC0CAAkACgoCESlSAC0CABMABAqYAmAcAIIAAAAA.Sammage:BAAANQADCgEIAQAAAA==.Sanlein:BAAANQAECggIBwAAAA==.Sarcini:BAABNQAECn8gAAIkAAgKIR+HEgB6AgAkAAgKIR+HEgB6AgAAAA==.Sarcisse:BAAANQAECgcIDQAAAA==.Satrina:BAABNQAECn8nAAMgAAoKIBxCIgC+AgAgAAoKIBxCIgC+AgAGAAIKAACklQBqAAAAAA==.Savvy:BAABNQAECn8nAAICAAgKTBqDSQA8AgACAAgKTBqDSQA8AgAAAA==.',
Se='Senaren:BAAANQAECggIAQAAAA==.Senlain:BAAANQAECggIAgAAAA==.Seraphiña:BAAANQAECgEIAQAAAA==.',
Sh='Shagore:BAAANQADCgYIDwABNQABCgQIBAAQAAAAAA==.Shamander:BAAANQAECgMIAwABNQAECgMIAwAQAAAAAA==.Shameonyou:BAAANQAECgMIBAAAAA==.',
Si='Sigard:BAAANQADCgMIAwAAAA==.Silentmage:BAAANQADCgIIAgAAAA==.Sinclaire:BAAANQADCgIIAgAAAA==.Sitruc:BAAANQAECgcIDgAAAA==.',
Sl='Slander:BAAANQAECgQIBAAAAA==.',
Sm='Smartbuff:BAAANQADCgUICQAAAA==.',
So='Somazugzug:BAACNQAFFH8IAAICAAMK7Qb/GgDCAAACAAMK7Qb/GgDCAAA1AAQKfyIAAgIACgoSEmRWAA8CAAIACgoSEmRWAA8CAAAA.Souchong:BAAANQABCgEIAQABNQAECgcIDQAQAAAAAA==.Soyboy:BAAANQABCgUIBwAAAA==.',
Sp='Spacedguy:BAAANQADCgYICQAAAA==.Spammoosubi:BAAANQADCgcIBwAAAA==.Spamnrice:BAABNQAECn8qAAIIAAoKcxQLWgBmAgAIAAoKcxQLWgBmAgAAAA==.',
St='Steroidrage:BAAANQAECgEIAQAAAA==.Stormtwist:BAAANQADCgYIBgAAAA==.',
Su='Sugars:BAAANQAECgQIBgAAAA==.Susperia:BAAANQAECggICQAAAA==.Suzy:BAAANQAECgIIAgAAAA==.',
Ta='Taintbubble:BAAANQAECggIEQAAAA==.Tarnished:BAAANQADCgIIAgAAAA==.Tarquitus:BAACNQAFFH8GAAIVAAMKKCFmAgAdAQAVAAMKKCFmAgAdAQA1AAQKfx8AAxUACQrwIhYDAD0DABUACQrwIhYDAD0DAA0AAQr5B++WAC8AAAAA.',
Te='Teostra:BAAANQAECgIIAgABNQAECgYICQAQAAAAAA==.',
Th='Thedarkduke:BAABNQAECn8bAAIVAAgKvBJwBwAAAQAVAAgKvBJwBwAAAQAAAA==.Thedarkkness:BAAANQADCgYIBgABNQAECggIGwAVALwSAA==.Thekleener:BAAANQADCgQIBAAAAA==.Thoni:BAAANQADCggICAAAAA==.Thorin:BAAANQAECggIDAABNQAECgoKIgARAPMhAA==.Thud:BAAANQAECggICgAAAA==.',
Ti='Tidalwave:BAABNQAECn8gAAICAAgKDCBKIgDeAgACAAgKDCBKIgDeAgAAAA==.Timmeh:BAAANQAECgYICAAAAA==.Tindra:BAAANQAECgUICQAAAA==.Tissue:BAABNQAECn8wAAINAAoKTgywIgDrAAANAAoKTgywIgDrAAAAAA==.Titanius:BAAANQAECgYIDgABNQAECgYICQAQAAAAAA==.',
To='Tobibi:BAABNQAECn8iAAIRAAoK8yGZAQBtAgARAAoK8yGZAQBtAgAAAA==.Tolip:BAABNQAECn8XAAQlAAkK5A5QGwBNAQAlAAYKDhBQGwBNAQAWAAMKsQYKawBZAAALAAEK7ALxwwAeAAAAAA==.Tolipally:BAAANQADCgYICwABNQAECgkJFwAlAOQOAA==.Tolipicious:BAAANQADCgYIBgABNQAECgkJFwAlAOQOAA==.Tollock:BAAANQADCggIFAABNQAECgkJFwAlAOQOAA==.Topsykret:BAAANQADCgcICQAAAA==.Topsyy:BAAANQADCggIEAAAAA==.Torpse:BAAANQAECgcJDAABNQAFFAQICAALAAUYAA==.Torrick:BAAANQADCgQIBAAAAA==.',
Tr='Trevórg:BAAANQAECgUJDgAAAA==.',
Ts='Tsarrubus:BAABNQAECn8tAAINAAoKnAh5RwCNAQANAAoKnAh5RwCNAQAAAA==.',
Tu='Tucknrolz:BAAANQADCgEIAQAAAA==.Tullianis:BAAANQABCggICgAAAA==.Tusck:BAAANQAECgMICAAAAA==.',
Ul='Ulg:BAABNQAECn8xAAMSAAoK7B+LJAAmAwASAAkK4SGLJAAmAwAcAAYK0RyKDgDGAQAAAA==.Ulghar:BAAANQADCgYIBgABNQAECgoKMQASAOwfAA==.',
Uw='Uwantmebad:BAAANQADCgIIAgAAAA==.',
Va='Valkyl:BAAANQADCgQIBwAAAA==.Valkyll:BAAANQADCgQIBAAAAA==.Vanquisher:BAAANQAECggIEAAAAA==.',
Ve='Velvet:BAAANQAECgIIBAAAAA==.Vengeanze:BAAANQAECgQIBQAAAA==.Vengefulcry:BAAANQADCgYICgAAAA==.Verrat:BAABNQAECn8uAAIVAAoKwBkQCAB7AgAVAAoKwBkQCAB7AgAAAA==.',
We='Weave:BAAANQAECgMIBAABNQAFFAUIDAAWAMUSAA==.Wellerman:BAAANQAECgcIDAAAAA==.',
Wh='Whohaveaggro:BAAANQAECgEIAQAAAA==.',
Wi='Willpew:BAAANQAECgYIBgAAAA==.Wino:BAAANQAECgYIDAAAAA==.Wiqui:BAABNQAECn8ZAAIIAAgKDBXJSAAiAQAIAAgKDBXJSAAiAQAAAA==.',
Wo='Wolfonk:BAABNQAECn8oAAImAAoKEQpKMACVAQAmAAoKEQpKMACVAQAAAA==.',
Wu='Wuhshake:BAABNQAECn8kAAICAAgK5CVNBgBuAgACAAgK5CVNBgBuAgAAAA==.',
['Wë']='Wërrcs:BAAANQAECggIDAAAAA==.',
Xe='Xemo:BAABNQAECn8lAAIFAAkK/w1vKQCDAQAFAAkK/w1vKQCDAQAAAA==.Xenophics:BAACNQAFFH8JAAIFAAYKQwq2EABCAQAFAAYKQwq2EABCAQA1AAQKfzAAAgUACgolIzgMACECAAUACgolIzgMACECAAAA.',
Za='Zaiha:BAAANQADCgYIBgAAAA==.Zal:BAAANQAECgUIEwAAAA==.Zall:BAACNQAFFH8UAAImAAUKXRafAwDqAAAmAAUKXRafAwDqAAA1AAQKfyIAAyYACgqVGgwWAKACACYACgqVGgwWAKACACcAAgqLE6dDAGAAAAAA.Zamos:BAAANQAECgMIBQAAAA==.',
Ze='Zedraikis:BAAANQADCgMIBAAAAA==.Zenshin:BAAANQADCggIEQAAAA==.Zentaur:BAABNQAECn8nAAIEAAgKnwy4FACYAQAEAAgKnwy4FACYAQAAAA==.',
Zi='Zitfrlt:BAABNQAECn8lAAMcAAoKwhJuEwBpAQASAAoKwxCPegAoAgAcAAYKmhJuEwBpAQABNQAFFAIIBQAGAOoOAA==.',
Zo='Zontar:BAAANQAECgQIBgAAAA==.Zorman:BAAANQADCgIIAwAAAA==.',
Zy='Zylaz:BAAANQADCggICAAAAA==.',
['Ål']='Ålucard:BAABNQAECn8dAAIJAAcKjx4aQQBnAgAJAAcKjx4aQQBnAgAAAA==.',
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
