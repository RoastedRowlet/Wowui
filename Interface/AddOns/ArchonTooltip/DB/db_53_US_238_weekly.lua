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

local lookup = {'Shaman-Enhancement','Shaman-Restoration','Unknown-Unknown','Monk-Brewmaster','Paladin-Retribution','DeathKnight-Frost','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Holy','Paladin-Holy','DemonHunter-Havoc','Warlock-Demonology','Evoker-Preservation','Druid-Balance','Shaman-Elemental','Mage-Arcane','Warrior-Arms','Priest-Discipline','Priest-Shadow','DemonHunter-Vengeance','Druid-Restoration','DemonHunter-Devourer','Evoker-Devastation','Mage-Frost','DeathKnight-Blood','Warrior-Protection','Rogue-Assassination','Warrior-Fury','Rogue-Subtlety','Warlock-Destruction','Mage-Fire','DeathKnight-Unholy','Warlock-Affliction','Evoker-Augmentation','Paladin-Protection','Monk-Windwalker','Monk-Mistweaver',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aayrawn:BAABNQAECn8hAAMBAAgKBxucDACiAgABAAgKBxucDACiAgACAAEKjwPyIAEpAAAAAA==.',
Ac='Aceofplagues:BAAANQADCgQIBAABNQAECgcIEgADAAAAAA==.Acesdruid:BAAANQAECgYICwABNQAECgcIEgADAAAAAA==.Aceshaman:BAAANQAECgcIEgAAAA==.',
Ai='Airone:BAAANQAECgQIBwAAAA==.',
Ak='Akadion:BAAANQADCggICAAAAA==.',
Al='Alextros:BAEANQABCgIIAwABNQAECgkJKAAEAMMhAA==.Alluriel:BAAANQADCgIIAgAAAA==.',
Am='Amaranthe:BAAANQAECgEIAQAAAA==.Amrax:BAABNQAECn8aAAIFAAgKtw3NswCxAQAFAAgKtw3NswCxAQAAAA==.',
An='Antijastran:BAABNQAECn8ZAAIGAAgKyQpCSgCLAQAGAAgKyQpCSgCLAQAAAA==.',
Aq='Aquabat:BAABNQAECn8nAAMHAAkKth7/DwDnAgAHAAkKnB7/DwDnAgAIAAEK/CATQQFUAAAAAA==.Aquda:BAAANQADCgUIAgAAAA==.',
Ar='Artemist:BAAANQADCgUICgAAAA==.Arthás:BAAANQADCgIIAgAAAA==.',
As='Ashbringer:BAABNQAECn8xAAIFAAkKXyaQBADUAwAFAAkKXyaQBADUAwAAAA==.',
At='Athalax:BAAANQADCgEIAQAAAA==.Attia:BAAANQAECgcICAAAAA==.',
Ba='Baladoria:BAABNQAECn8gAAIJAAkKmBCKYwDyAQAJAAkKmBCKYwDyAQAAAA==.Baldkrank:BAAANQAECggIEAAAAA==.Bama:BAAANQAECgEIAQAAAA==.Bananabowman:BAAANQAECggIEwAAAA==.Banditos:BAAANQAECgcIDQAAAA==.Bartab:BAABNQAECn8iAAICAAgK3B6qKgC2AgACAAgK3B6qKgC2AgABNQAECgYIDwADAAAAAA==.',
Be='Bearemy:BAAANQAECgEIAQABNQAECggIHwAKAC8RAA==.Beastling:BAAANQAECgQIBgAAAA==.Beau:BAACNQAFFH8GAAILAAMKKBRiEQDZAAALAAMKKBRiEQDZAAA1AAQKfzcAAgsACQrwIlEKAFwDAAsACQrwIlEKAFwDAAAA.Beauwi:BAAANQADCggIEQABNQAFFAMIBgALACgUAA==.Bettyßrisco:BAAANQAECgYIEwAAAA==.',
Bi='Bigchungusyo:BAAANQADCgYIBwAAAA==.Bigpapi:BAAANQAECgMIAwAAAA==.',
Bl='Blawkk:BAAANQADCggIEAAAAA==.Blessthem:BAAANQADCgcICgAAAA==.',
Bo='Bombur:BAABNQAECn8eAAIMAAcKfBC+mQChAQAMAAcKfBC+mQChAQAAAA==.Bonejovi:BAAANQADCgIIAgAAAA==.Bottles:BAAANQAECgcIBwABNQAECggIEQADAAAAAA==.',
Br='Bratva:BAAANQAECgMIAwAAAA==.Brokenbubble:BAAANQAECgUIBgABNQAFFAYIDgANAAUUAA==.Brozown:BAAANQADCgQIBAABNQAECgkJJwAHALYeAA==.Brëtski:BAAANQAECgUIBQAAAA==.',
Bu='Bubagony:BAAANQAECggICgABNQAFFAQIDgAOABgUAA==.Burakku:BAAANQADCgMIAwABNQAFFAIIBwAPAIYZAA==.Buzza:BAAANQAECgUICAAAAA==.Buzzkill:BAAANQAECgUIEgAAAA==.',
Ca='Calinash:BAABNQAECn8iAAIQAAgKXByMigBpAgAQAAgKXByMigBpAgAAAA==.Calzraxx:BAABNQAECn8aAAIRAAcK8hZMkQDsAQARAAcK8hZMkQDsAQAAAA==.Cartons:BAAANQADCgQIBAABNQAECggIEQADAAAAAA==.',
Cc='Ccaan:BAAANQAECgUICwAAAA==.',
Ce='Celinn:BAABNQAECn8dAAIJAAkKoBaQTgA1AgAJAAkKoBaQTgA1AgAAAA==.',
Ch='Charliek:BAABNQAECn8XAAIRAAgK1A5CpgC4AQARAAgK1A5CpgC4AQAAAA==.Chimalma:BAABNQAECn8YAAMCAAkKXhzlIQDeAgACAAkKXhzlIQDeAgAPAAUKdxpVswAnAQAAAA==.Chingoblingo:BAAANQADCggIEgAAAA==.Chorr:BAAANQAECgIIAgABNQAECgUICQADAAAAAA==.',
Ck='Ckaan:BAAANQADCggICAAAAA==.',
Co='Cobygo:BAAANQADCggIDwAAAA==.Coffins:BAAANQADCgYIBgABNQAECggIEQADAAAAAA==.',
Cr='Crates:BAAANQAECggIEQAAAA==.Cringely:BAABNQAECn8kAAQJAAkKOiLDCgBqAwAJAAkKOiLDCgBqAwASAAIK9BrXGQCaAAATAAEKAABNlQAJAAAAAA==.Croakam:BAAANQADCgIIAgABNQAFFAMIBgAUACghAA==.Crosswalkk:BAAANQAECgIIAwAAAA==.Cryface:BAAANQAECgEIAQABNQABCgQIBAADAAAAAA==.',
Cu='Curonconagua:BAAANQADCgcICAAAAA==.',
Cy='Cypherrellik:BAAANQAECgYICwAAAA==.',
['Cö']='Cöldcancer:BAAANQADCgQIAgAAAA==.',
Da='Daktok:BAAANQAECgMIBgAAAA==.Dargar:BAAANQADCgYIBgAAAA==.Darknyss:BAAANQADCgEJAQAAAA==.Darkozygo:BAAANQADCggIJgABNQAECgQIBAADAAAAAA==.',
De='Deathfortres:BAABNQAECn8cAAMOAAgKnANwegDdAAAOAAYKCwVwegDdAAAVAAYK0QQzTADYAAAAAA==.Deathstar:BAAANQADCgEIAQAAAA==.Deidara:BAABNQAECn8vAAMLAAkKySKSDgAtAwALAAkKySKSDgAtAwAWAAcKWBenJQAVAgAAAA==.Demolish:BAAANQADCggIDgAAAA==.Demongrass:BAACNQAFFH8FAAIWAAQKyxBnCgApAQAWAAQKyxBnCgApAQA1AAQKfxYAAhYACQpSGusWAKYCABYACQpSGusWAKYCAAAA.Devit:BAAANQAECgQICAAAAA==.',
Di='Dimka:BAAANQADCggIEgAAAA==.Dirtyfox:BAAANQADCgQIBAAAAA==.Disarray:BAABNQAECn8eAAIWAAgKvSBzDAAZAwAWAAgKvSBzDAAZAwAAAA==.',
Do='Dontar:BAAANQAECgUIBQAAAA==.Donvald:BAAANQAECgIIAwAAAA==.Doodaad:BAAANQADCgYICwAAAA==.Doublerack:BAAANQAECgUIDQABNQABCgQIBAADAAAAAA==.',
Dr='Dragondznuts:BAACNQAFFH8OAAINAAYKBRRiBwDPAQANAAYKBRRiBwDPAQA1AAQKfysAAw0ACQpAF2oXAEACAA0ACQpAF2oXAEACABcABQosGLUfAFcBAAAA.Druzizzle:BAAANQADCgQIBAAAAA==.Dríppy:BAAANQAECgMIAwAAAA==.',
Ei='Eilerra:BAABNQAECn8bAAMYAAYKnhxcEgB+AQAQAAUKnhIW/QCQAQAYAAUKnhxcEgB+AQAAAA==.',
Er='Erre:BAABNQAECn8pAAIMAAgKOyBdLgDKAgAMAAgKOyBdLgDKAgAAAA==.',
Ex='Exxitwound:BAAANQADCggIDQAAAA==.',
Fa='Fallenhunt:BAAANQADCgQIBAAAAA==.',
Fi='Finniessa:BAAANQADCgEIAQAAAA==.Firesson:BAAANQAECgUIDgAAAA==.',
Fo='Fourroadsgz:BAAANQAECgQIBAAAAA==.Foxoffire:BAAANQAECgIIBAAAAA==.Foxtracks:BAAANQADCgEIAQAAAA==.Fozzee:BAAANQAECgIIAgABNQAECgkJJAAJADoiAA==.',
Fr='Fritark:BAABNQAECn8qAAMGAAgKdRf4NAACAgAGAAgKnxX4NAACAgAZAAQKNBdzfAADAQAAAA==.Frostyburn:BAAANQAECgIIBAAAAA==.',
['Fë']='Fëanor:BAAANQAECggIBwAAAA==.',
Ge='Gena:BAAANQADCgYIEQAAAA==.Geörge:BAACNQAFFH8MAAITAAUKER49BwChAQATAAUKER49BwChAQA1AAQKfzMAAhMACQq5I+kEAIgDABMACQq5I+kEAIgDAAAA.',
Gh='Ghostbath:BAAANQABCgUIBQAAAA==.',
Go='Goated:BAABNQAECn8aAAMRAAcKVSIYYABqAgARAAcKfh8YYABqAgAaAAMKsyRBIgA0AQAAAA==.',
Gr='Gremfrost:BAAANQAFFAEIAQAAAA==.Grotelek:BAABNQAECn8qAAICAAgKwhVlXwDtAQACAAgKwhVlXwDtAQAAAA==.Grumpywaltz:BAABNQAECn8jAAIaAAgKQxL8FADTAQAaAAgKQxL8FADTAQAAAA==.',
Gu='Gunhild:BAAANQADCgQIBAAAAA==.Guthy:BAAANQAECgMIAwAAAA==.',
Ha='Haedrath:BAAANQAECgYIBwABNQAECgYIGwAYAJ4cAA==.Hahafunny:BAAANQADCggICQAAAA==.Halcotsu:BAABNQAECn8cAAIMAAgKQgvymQCgAQAMAAgKQgvymQCgAQAAAA==.Halleko:BAABNQAECn8VAAIFAAgKZR4OVwCOAgAFAAgKZR4OVwCOAgABNQAFFAYIEwAbAAcbAA==.Hammerfoot:BAAANQAECgQICgAAAA==.Harkknight:BAAANQAECgYIDgAAAA==.Haurtrue:BAABNQAECn8hAAIOAAgKnRvzKQCFAgAOAAgKnRvzKQCFAgAAAA==.Hawgbawl:BAABNQAECn8lAAIcAAcK1hcqDAD4AQAcAAcK1hcqDAD4AQAAAA==.Hawgdream:BAAANQAECgQIDwAAAA==.',
He='Heliah:BAAANQABCgIIAgAAAA==.Hellequin:BAACNQAFFH8TAAMbAAYKBxsHBAAHAgAbAAYKBxsHBAAHAgAdAAEKOQHrFgA0AAA1AAQKfzIAAxsACQrpJUUEAJADABsACQrpJUUEAJADAB0ABgpUHXohAL0BAAAA.Heyyitzrichh:BAABNQAECn8cAAMeAAgKGyEdJABPAQAMAAYKGCDjgADfAQAeAAQKLSIdJABPAQAAAA==.',
Ho='Hollinar:BAAANQAECggIEwAAAA==.Holycøw:BAAANQAECgQIBAAAAA==.Hondoe:BAAANQAECgMIAwAAAA==.',
Ih='Ihavecookies:BAAANQAECgEIAQAAAA==.',
Im='Imahealer:BAAANQAECgYICgAAAA==.',
In='Invaled:BAAANQAECgUICAAAAA==.',
Ir='Irateknight:BAAANQAECgEIAQAAAA==.Irely:BAAANQADCgUIBQAAAA==.',
Is='Isegrim:BAAANQAECgQIBwAAAA==.',
It='Itzrich:BAAANQAECgQIBwAAAA==.',
Ja='Jakelong:BAAANQAECgQICQABNQAECgkJJQAFAAwjAA==.Jasmirangel:BAABNQAECn8pAAIVAAkKpCQ0AgCsAwAVAAkKpCQ0AgCsAwAAAA==.',
Je='Jenesis:BAAANQAECgYIDQAAAA==.Jermajesty:BAABNQAECn8fAAIKAAgKLxFvYgDuAQAKAAgKLxFvYgDuAQAAAA==.Jezus:BAAANQABCgYJDwAAAA==.',
Jo='Joanoforc:BAAANQAECgEIAQABNQAECgQICQADAAAAAA==.Joci:BAAANQAECgYIBgAAAA==.Jovar:BAAANQADCgMIAwAAAA==.',
['Jö']='Jöker:BAAANQAECgMIAwAAAA==.',
Ka='Kalzifer:BAABNQAECn8XAAIfAAcKNQsDBACCAQAfAAcKNQsDBACCAQABNQAFFAIIBQAGAOoOAA==.Kankaladin:BAABNQAECn8lAAIFAAkKDCMyJwAnAwAFAAkKDCMyJwAnAwAAAA==.Kanky:BAAANQAECgUIBQABNQAECgkJJQAFAAwjAA==.Kano:BAABNQAECn8iAAMHAAkKOxOpNACkAQAHAAkKVwmpNACkAQAIAAYKjhWgsgCaAQAAAA==.Karper:BAAANQADCgYIBgAAAA==.Kavern:BAAANQADCgUIBQAAAA==.Kawada:BAABNQAECn8VAAIeAAcKRgsrHQCDAQAeAAcKRgsrHQCDAQAAAA==.Kayhaus:BAAANQADCgQIBAAAAA==.',
Ke='Ken:BAABNQAECn8cAAMgAAgKoCCPHwDMAgAgAAgKoCCPHwDMAgAGAAUKVxLaXQAnAQAAAA==.Kennedï:BAAANQADCgQIBAAAAA==.Kennëdi:BAABNQAECn8eAAICAAcK7BTibQC+AQACAAcK7BTibQC+AQAAAA==.',
Kh='Khory:BAAANQAECgUICQAAAA==.',
Ki='Kichirõ:BAABNQAECn8hAAIEAAgKaQnQFwBjAQAEAAgKaQnQFwBjAQAAAA==.Killrah:BAAANQADCgIIAgAAAA==.Kilrah:BAAANQADCgIIAgAAAA==.Kilriella:BAAANQADCgIIAgAAAA==.Kimuri:BAAANQADCgYIBgAAAA==.',
Km='Kmt:BAAANQADCggIDgABNQAECgUICgADAAAAAA==.',
Ko='Koffee:BAAANQAECgYICgABNQAECgkJJQAFAAwjAA==.Korgigor:BAAANQADCgEJAQAAAA==.',
Kt='Kt:BAAANQAECgUICgAAAA==.',
Ku='Kuailiang:BAAANQADCgYIBgABNQAECgkJMAAWAAUUAA==.',
La='Ladezar:BAAANQADCgYJBgAAAA==.Laissen:BAAANQADCgYIGAAAAA==.Lapsung:BAAANQAECggICgABNQAECgcICAADAAAAAA==.Lattemocha:BAAANQAECgYIEwAAAA==.',
Le='Leprechaun:BAAANQAECgYIEAABNQAECggIAwADAAAAAA==.Leprechauñ:BAAANQAECgQICgABNQAECggIAwADAAAAAA==.Leprecháun:BAAANQAECgIIAwABNQAECggIAwADAAAAAA==.Lepréchaun:BAAANQAECggIAwAAAA==.',
Li='Liche:BAAANQAECgEIAQABNQAECgkJLwALAMkiAA==.Lighthoove:BAAANQADCgcIBwAAAA==.Lightsir:BAAANQADCgMIBwAAAA==.Lilfuse:BAAANQAECgEIAQAAAA==.Lishalle:BAAANQADCgUIBQABNQAECgkJJAAQABEYAA==.',
Lo='Loutone:BAAANQADCgcIFgAAAA==.',
Lu='Ludlow:BAAANQAECgQIBgAAAA==.Lunatonne:BAABNQAECn8aAAIIAAgKqxelPwCpAgAIAAgKqxelPwCpAgAAAA==.Luneztoprime:BAAANQAECgQIEgAAAA==.Luvlybella:BAAANQAECgQIBAAAAA==.',
Ly='Lyiann:BAAANQADCgYICgAAAA==.Lyákadion:BAAANQADCggIEgAAAA==.',
Ma='Mafi:BAAANQAECgQICgAAAA==.Malady:BAAANQADCgQIBAAAAA==.Mallypally:BAAANQAECgMIAwABNQAECgUIDQADAAAAAA==.Matt:BAACNQAFFH8IAAIVAAQKIQyXCgAiAQAVAAQKIQyXCgAiAQA1AAQKfywAAhUACQo+HoEOAOcCABUACQo+HoEOAOcCAAAA.Matte:BAABNQAECn8iAAMCAAkKFBqINQCGAgACAAkKFBqINQCGAgAPAAEKAABmQwEqAAABNQAFFAQICAAVACEMAA==.Mazza:BAAANQAECgcIDwAAAA==.',
Me='Meddicus:BAAANQAECgcICgAAAA==.Megorice:BAAANQADCgcIBwAAAA==.Mewtwô:BAAANQAECgcIDAAAAA==.',
Mi='Miedillø:BAAANQAFFAEIAQABNQAFFAcIIwAIALocAA==.Mikeoxmall:BAABNQAECn8pAAMIAAkKRx3jLwDbAgAIAAgKBSLjLwDbAgAHAAUKyQwQTgDzAAAAAA==.',
Mo='Monstermime:BAABNQAECn8jAAQhAAgKLRUJCQD1AQAhAAcK/hIJCQD1AQAMAAUKWxQaxAA+AQAeAAQKmQ4GMQACAQAAAA==.Moonpièz:BAAANQADCggIDQAAAA==.Moosetrax:BAABNQAECn8mAAIZAAgK1w9IVQCcAQAZAAgK1w9IVQCcAQAAAA==.',
Mu='Muffy:BAAANQADCgQIBAAAAA==.Mushumime:BAAANQADCgYIDAABNQAECggIIwAhAC0VAA==.',
My='Myserie:BAABNQAECn8cAAITAAgKjA9mKgDRAQATAAgKjA9mKgDRAQAAAA==.Mystikah:BAAANQADCgIIAgAAAA==.',
Na='Napshade:BAAANQAECgEIAQABNQAECgYIBQADAAAAAA==.Natsuu:BAAANQAECgEIAQAAAA==.Nazara:BAACNQAFFH8MAAMXAAUKRhPDBACAAQAXAAUKRhPDBACAAQANAAMKgwF0EwCYAAA1AAQKfyoAAxcACQpLG2sKAMQCABcACQpLG2sKAMQCAA0AAgr1C9RHAF0AAAE1AAQKBQgJAAMAAAAA.',
Ne='Neuro:BAABNQAECn8wAAIQAAkKkxmefwB/AgAQAAkKkxmefwB/AgAAAA==.Neyvin:BAAANQADCgIIAgAAAA==.',
Ni='Nightfiress:BAAANQAECgEIAQAAAA==.Nikodemos:BAAANQAFFAUIEQAAAQ==.',
Nk='Nkáujhmóob:BAAANQAECgUIBQAAAA==.',
Oo='Oopsifer:BAAANQAECgQICAAAAA==.Oowu:BAAANQADCgcIDQAAAA==.',
Op='Optimum:BAAANQAECgIIAgAAAA==.',
Or='Oran:BAAANQADCggIDgAAAA==.',
Pe='Persimmon:BAAANQAECgYICgAAAA==.Peyton:BAAANQAECgIJAgAAAA==.',
Pi='Piecemaker:BAACNQAFFH8KAAIIAAUKDxnlDAB+AQAIAAUKDxnlDAB+AQA1AAQKf0MAAggACQraIfwXADgDAAgACQraIfwXADgDAAAA.',
Pl='Plaguepapi:BAAANQADCgIJAgAAAA==.',
Pr='Pravin:BAAANQADCgIIAgAAAA==.Proslicer:BAAANQADCggIGAAAAA==.',
Pu='Pufdaddy:BAAANQABCgMIAwAAAA==.Puppetslayer:BAAANQAECgYIDwAAAA==.',
Py='Pyrrah:BAABNQAECn8rAAMKAAgKCCB6HwDwAgAKAAgKCCB6HwDwAgAFAAcKhhaarADBAQAAAA==.Pyrri:BAAANQAECgIIAgABNQAECggIKwAKAAggAA==.',
['Pé']='Péytón:BAAANQADCgQIBgAAAA==.',
Qu='Quanchì:BAABNQAECn8wAAIWAAkKBRRxIABHAgAWAAkKBRRxIABHAgAAAA==.',
Ra='Rabuf:BAAANQAECgYIEwAAAA==.Raccoonadin:BAAANQAECgEIAQAAAA==.Radha:BAABNQAECn8WAAIRAAkKlBoUPADUAgARAAkKlBoUPADUAgABNQAFFAQIDgAOABgUAA==.Rageruññer:BAAANQADCgYIBgAAAA==.',
Re='Redfenris:BAAANQAECgQICQABNQAECgkJMAAWAAUUAA==.Redizle:BAAANQADCggICAABNQAFFAYIFAAKANMWAA==.Reginrune:BAAANQAECggIBQAAAA==.Resonance:BAAANQAECgMIBAAAAA==.',
Rh='Rhaenyr:BAAANQAECgEIAQAAAA==.',
Ri='Ridizle:BAACNQAFFH8UAAIKAAYK0xazBgD8AQAKAAYK0xazBgD8AQA1AAQKfy8AAgoACQq8IJoRAEADAAoACQq8IJoRAEADAAAA.',
Ro='Rohdoog:BAABNQAECn8VAAIiAAgKsBSmCQDhAQAiAAgKsBSmCQDhAQAAAA==.',
Ru='Runedyu:BAAANQAECgQIEwAAAA==.',
Ry='Ryanno:BAABNQAECn8eAAMIAAkKdiCAHgAcAwAIAAkKdiCAHgAcAwAHAAUKARA8PwBTAQAAAA==.Ryannoo:BAAANQAECggICAAAAA==.Ryunosuke:BAAANQAECggIDAABNQAECgkJLwALAMkiAA==.',
Sa='Sahomi:BAACNQAFFH8GAAIJAAMKcgUKIgDKAAAJAAMKcgUKIgDKAAA1AAQKfyMAAwkACQq0EO1QAC0CAAkACQq0EO1QAC0CABIABAqYAhgcAIIAAAAA.Sammage:BAAANQADCgEIAQAAAA==.Sanlein:BAAANQAECggIBQAAAA==.Sarcini:BAABNQAECn8fAAIjAAcKpSBGEgB7AgAjAAcKpSBGEgB7AgAAAA==.Sarcisse:BAAANQAECgcIDQAAAA==.Satrina:BAABNQAECn8jAAMgAAkKAh3lIQC9AgAgAAkKAh3lIQC9AgAGAAIKAACJkgBqAAAAAA==.Savvy:BAABNQAECn8jAAICAAgKSRmYSAA9AgACAAgKSRmYSAA9AgAAAA==.',
Se='Senaren:BAAANQAECggIAQAAAA==.Senlain:BAAANQAECggIAgAAAA==.Seraphiña:BAAANQAECgEIAQAAAA==.',
Sh='Shagore:BAAANQADCgYIDwABNQABCgQIBAADAAAAAA==.Shamander:BAAANQAECgMIAwABNQAECgMIAwADAAAAAA==.Shameonyou:BAAANQAECgMIBAAAAA==.',
Si='Sigard:BAAANQADCgMIAwAAAA==.Silentmage:BAAANQADCgIIAgAAAA==.Sinclaire:BAAANQADCgIIAgAAAA==.Sitruc:BAAANQAECgcIDgAAAA==.',
Sl='Slander:BAAANQAECgQJBAAAAA==.',
Sm='Smartbuff:BAAANQADCgUICQAAAA==.',
So='Somazugzug:BAACNQAFFH8GAAICAAMKcgVkGgDCAAACAAMKcgVkGgDCAAA1AAQKfx4AAgIACQrwEWBVAA8CAAIACQrwEWBVAA8CAAAA.Souchong:BAAANQABCgEIAQABNQAECgcICAADAAAAAA==.Soyboy:BAAANQABCgUIBwAAAA==.',
Sp='Spacedguy:BAAANQADCgYICQAAAA==.Spammoosubi:BAAANQADCgcIBwAAAA==.Spamnrice:BAABNQAECn8mAAIIAAgKmxfbWABmAgAIAAgKmxfbWABmAgAAAA==.',
St='Steroidrage:BAAANQAECgEIAQAAAA==.',
Su='Sugars:BAAANQAECgQIBgAAAA==.Susperia:BAAANQAECggIAQAAAA==.Suzy:BAAANQAECgIIAgAAAA==.',
Ta='Taintbubble:BAAANQAECggIDgAAAA==.Tarnished:BAAANQADCgIIAgAAAA==.Tarquitus:BAACNQAFFH8GAAIUAAMKKCFUAgAdAQAUAAMKKCFUAgAdAQA1AAQKfx8AAxQACQrwIgYDAD0DABQACQrwIgYDAD0DAAsAAQr5B7uUAC8AAAAA.',
Te='Teostra:BAAANQAECgIIAgABNQAECgUICQADAAAAAA==.',
Th='Thedarkduke:BAAANQAECgcIEgAAAA==.Thedarkkness:BAAANQADCgYIBgABNQAECgcIEgADAAAAAA==.Thekleener:BAAANQADCgQIBAAAAA==.Thoni:BAAANQADCggICAAAAA==.Thorin:BAAANQAECgYICQABNQAECgkJHAANAE0gAA==.Thud:BAAANQAECggICgAAAA==.',
Ti='Tidalwave:BAABNQAECn8eAAICAAgKDCDLIQDfAgACAAgKDCDLIQDfAgAAAA==.Timmeh:BAAANQAECgYICAAAAA==.Tindra:BAAANQAECgUICQAAAA==.Tissue:BAABNQAECn8oAAILAAgKkQ3iPQDGAQALAAgKkQ3iPQDGAQAAAA==.Titanius:BAAANQAECgYICgABNQAECgUICQADAAAAAA==.',
To='Tobibi:BAABNQAECn8cAAINAAkKTSARBQBaAwANAAkKTSARBQBaAwAAAA==.Tolip:BAAANQAECgcIEgAAAA==.Tolipally:BAAANQADCgYICwABNQAECgcIEgADAAAAAA==.Tolipicious:BAAANQADCgYIBgABNQAECgcIEgADAAAAAA==.Tollock:BAAANQADCggIFAABNQAECgcIEgADAAAAAA==.Topsykret:BAAANQADCgcICAAAAA==.Topsyy:BAAANQADCggIEAAAAA==.Torpse:BAAANQAECgcJDAABNQAFFAQICAAOAAUYAA==.Torrick:BAAANQADCgIIAgAAAA==.',
Tr='Trevórg:BAAANQAECgUJDgAAAA==.',
Ts='Tsarrubus:BAABNQAECn8pAAILAAgKGAmLRgCNAQALAAgKGAmLRgCNAQAAAA==.',
Tu='Tucknrolz:BAAANQADCgEIAQAAAA==.Tullianis:BAAANQABCggICgAAAA==.Tusck:BAAANQAECgMICAAAAA==.',
Ul='Ulg:BAABNQAECn8tAAMRAAkKbCLhIwAnAwARAAkKRCHhIwAnAwAcAAUKfSFtDgDGAQAAAA==.Ulghar:BAAANQADCgYIBgABNQAECgkJLQARAGwiAA==.',
Uw='Uwantmebad:BAAANQADCgIIAgAAAA==.',
Va='Valkyl:BAAANQADCgQIBAAAAA==.Valkyll:BAAANQADCgIIAgAAAA==.Vanquisher:BAAANQAECggIEAAAAA==.',
Ve='Velvet:BAAANQAECgIIBAAAAA==.Vengeanze:BAAANQAECgQIBQAAAA==.Vengefulcry:BAAANQADCgYICgAAAA==.Verrat:BAABNQAECn8qAAIUAAgKHRz4BwB7AgAUAAgKHRz4BwB7AgAAAA==.',
We='Weave:BAAANQADCgIIAgABNQAFFAQICAAVACEMAA==.Wellerman:BAAANQAECgcIDAAAAA==.',
Wi='Willpew:BAAANQAECgYIBgAAAA==.Wino:BAAANQAECgUICwAAAA==.Wiqui:BAAANQAECgYIEAAAAA==.',
Wo='Wolfonk:BAABNQAECn8jAAIkAAkKxQq9LwCVAQAkAAkKxQq9LwCVAQAAAA==.',
Wu='Wuhshake:BAABNQAECn8eAAICAAgKrSXFDABZAwACAAgKrSXFDABZAwAAAA==.',
['Wë']='Wërrcs:BAAANQAECggICwAAAA==.',
Xe='Xemo:BAABNQAECn8dAAIFAAcKEAwnzAB9AQAFAAcKEAwnzAB9AQAAAA==.Xenophics:BAACNQAFFH8IAAIFAAUKXws1EABCAQAFAAUKXws1EABCAQA1AAQKfykAAgUACQq/Iy4sABQDAAUACQq/Iy4sABQDAAAA.',
Za='Zaiha:BAAANQADCgYIBgAAAA==.Zal:BAAANQAECgUIEwAAAA==.Zall:BAACNQAFFH8QAAIkAAUKHBPgCABIAQAkAAUKHBPgCABIAQA1AAQKfx4AAyQACQotHb4VAKACACQACQotHb4VAKACACUAAgqLE6lCAGAAAAAA.Zamos:BAAANQAECgEIBAAAAA==.',
Ze='Zedraikis:BAAANQADCgIIAgAAAA==.Zenshin:BAAANQADCggIEQAAAA==.Zentaur:BAABNQAECn8jAAIEAAgKnwyAFACYAQAEAAgKnwyAFACYAQAAAA==.',
Zi='Zitfrlt:BAABNQAECn8hAAMcAAkKNhRBEwBpAQARAAkK7xEVeQAoAgAcAAYKmhJBEwBpAQABNQAFFAIIBQAGAOoOAA==.',
Zo='Zontar:BAAANQAECgQIBgAAAA==.Zorman:BAAANQADCgIIAwAAAA==.',
['Ål']='Ålucard:BAAANQAECgYIEwAAAA==.',
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
