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

local lookup = {'Warrior-Arms','DeathKnight-Blood','Unknown-Unknown','Paladin-Retribution','Shaman-Restoration','Warlock-Destruction','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Druid-Guardian','Warrior-Protection','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Druid-Restoration','DeathKnight-Frost','Hunter-Survival','DemonHunter-Havoc','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','Rogue-Assassination','Paladin-Holy','DeathKnight-Unholy',}
local provider = {region='US',realm='Haomarush',name='US',type='weekly',zone=53,date='2026-10-13',data={Ai='Aitharlis:BAAANQADCgEIAQAAAA==.',
Al='Alexya:BAAANQADCgYIBgAAAA==.Alphahawk:BAABNQAECn8wAAIBAAkKYxLgcwA2AgABAAkKYxLgcwA2AgAAAA==.',
Ap='Applepie:BAAANQAECgIIBAABNQAECggIGwACAKIfAA==.',
Ar='Aralia:BAAANQAECgUIBQABNQABCgIIAgADAAAAAA==.Aramis:BAAANQAECgQIBAABNQABCgIIAgADAAAAAA==.Arathram:BAAANQAECgcIEgABNQABCgIIAgADAAAAAA==.',
As='Askaria:BAAANQAECgMIAwABNQAFFAQIBAADAAAAAA==.Asmoday:BAAANQADCgYIDAABNQAECgUICgADAAAAAA==.Asunawa:BAAANQAECgMIBAAAAA==.',
Au='Aundarr:BAAANQAECgIJAwABNQAECgUICgADAAAAAA==.',
Ba='Balvos:BAAANQAFFAEIAQAAAA==.Bat:BAAANQAECgcIDQAAAA==.',
Be='Beradok:BAAANQAECgQIBAAAAA==.',
Bl='Bladerazor:BAAANQADCgEIAQAAAA==.',
Bo='Boomster:BAAANQAFFAgIBAAAAA==.',
Br='Bri:BAAANQAECgYIEQAAAA==.',
Ca='Calixta:BAABNQAECn8gAAIEAAkKDyJpIgA4AwAEAAkKDyJpIgA4AwAAAA==.Camel:BAAANQADCgQIAgAAAA==.',
Ce='Ceolen:BAAANQAECgQIBAAAAA==.',
Ch='Cherrypie:BAAANQAECgQIBAABNQAECggIGwACAKIfAA==.Chiffonpie:BAAANQADCgYIBgAAAA==.',
Co='Coquette:BAABNQAECn8bAAIBAAcK2w44sgCaAQABAAcK2w44sgCaAQAAAA==.',
Cp='Cptbarnacles:BAAANQAECgcICwAAAA==.',
Cr='Crab:BAAANQADCgMJAwABNQAECgkJLwAFAN8dAA==.Cranberrypie:BAAANQAECggIDAABNQAECggIGwACAKIfAA==.Criscomaster:BAABNQAECn8hAAIGAAcKdxGrFADIAQAGAAcKdxGrFADIAQAAAA==.',
Cy='Cylla:BAABNQAECn8zAAIHAAkKkiEKAgBaAwAHAAkKkiEKAgBaAwAAAA==.',
Da='Dazãr:BAAANQADCgUIBgAAAA==.',
De='Dethbycrisco:BAAANQADCgIIAwAAAA==.',
Di='Dilfdormu:BAACNQAFFH8KAAIIAAQKHQWZDwD6AAAIAAQKHQWZDwD6AAA1AAQKfzIABAgACQqVFW8TAHUCAAgACQqVFW8TAHUCAAkAAQoAAFBBACYAAAoAAQpaBucnACAAAAAA.',
Do='Donkey:BAAANQAECgEIAQAAAA==.Doson:BAABNQAECn8rAAILAAgK1RtQDwBoAgALAAgK1RtQDwBoAgAAAA==.',
Dr='Dratak:BAACNQAFFH8hAAIMAAYKZSJ2AABiAgAMAAYKZSJ2AABiAgA1AAQKf0cAAgwACQroJhEAABQEAAwACQroJhEAABQEAAAA.Dratalt:BAABNQAFFH8OAAIMAAQKMR40AgCEAQAMAAQKMR40AgCEAQABNQAFFAYIIQAMAGUiAA==.Dreadfang:BAAANQADCgQIBAAAAA==.',
Ei='Eisdrameir:BAAANQADCgYICQAAAA==.',
El='Elitzai:BAAANQAECgUICgAAAA==.Elspethstorm:BAAANQAECgUIDgAAAA==.',
Em='Emeralda:BAAANQAECgQICwAAAA==.',
Ev='Evalueate:BAAANQAECgUJBQAAAA==.',
Fe='Feets:BAAANQAECgUIBgABNQAECgkJHAANABoiAA==.',
Fr='Frocknor:BAAANQAECgMIBgAAAA==.',
Fu='Fuki:BAAANQADCggIIQAAAA==.',
Ga='Galumian:BAACNQAFFH8nAAIOAAcKqSTZAADqAgAOAAcKqSTZAADqAgA1AAQKfzMAAg4ACQrlJPUEAKEDAA4ACQrlJPUEAKEDAAAA.',
Ge='Gergo:BAAANQADCgUICgAAAA==.Geron:BAAANQADCgYIBgABNQAECgkJIAAEAA8iAA==.',
Gr='Grasswonder:BAAANQADCgYIBgAAAA==.',
Gu='Guy:BAACNQAFFH8fAAIIAAcKVxTOBAAdAgAIAAcKVxTOBAAdAgA1AAQKfyUAAggACQoHHycPALQCAAgACQoHHycPALQCAAE1AAEKAwgDAAMAAAAA.',
Ha='Hailren:BAAANQAECgIIAgAAAA==.Haradali:BAAANQAECgYIDwAAAA==.',
Ho='Hondoe:BAAANQAECgUICwAAAA==.Hordehound:BAAANQADCgQIBAAAAA==.',
Ja='Jasminetea:BAABNQAECn8oAAMOAAkKChhZPAB1AgAOAAkKChhZPAB1AgAPAAEKAABbcgA+AAAAAA==.',
Ju='Judgment:BAAANQAECgQIBAAAAA==.',
Ka='Kairne:BAAANQAECgQIBAAAAA==.',
Ki='Kittybutt:BAAANQAECgYICAABNQAECgkJHAANABoiAA==.',
Kr='Krizara:BAAANQAECgEIAQABNQAECgMIBgADAAAAAA==.Kroth:BAABNQAECn8zAAIQAAkKWAz9KgDCAQAQAAkKWAz9KgDCAQAAAA==.',
Ku='Kubfury:BAAANQAECgIIAgAAAA==.',
Le='Lediah:BAAANQAECgEIAgAAAA==.',
Li='Liilith:BAAANQADCgQIBAAAAA==.Lillia:BAABNQAECn8ZAAMCAAkK0RZhSQDQAQACAAcK+hhhSQDQAQARAAUKCBNsawDoAAAAAA==.Lily:BAAANQAECgcIEQAAAA==.Limparrow:BAAANQADCgUIDwAAAA==.',
Ln='Lnav:BAAANQADCgUIBgAAAA==.',
Lu='Lunaci:BAABNQAECn8bAAIJAAcKlB1eEQA8AgAJAAcKlB1eEQA8AgAAAA==.',
Ma='Madyn:BAAANQADCgYIFQAAAA==.Magnusson:BAABNQAECn8dAAIMAAcKSBmzEQAIAgAMAAcKSBmzEQAIAgAAAA==.Masutado:BAABNQAECn8eAAIHAAcK2BoFCgAoAgAHAAcK2BoFCgAoAgAAAA==.Maven:BAAANQAECgcICQAAAA==.Mayernnaise:BAAANQAECgEIAQAAAA==.',
Me='Mellitha:BAAANQAECgQJBgAAAA==.',
Mi='Misfortune:BAAANQAECgIIAgABNQAECgkJIAAEAA8iAA==.Mitsy:BAAANQADCgUIBQABNQAECgcIEQADAAAAAA==.',
Mo='Montipython:BAAANQAECgUIBwAAAA==.Moons:BAABNQAECn88AAMNAAkKfSQ+HAAlAwANAAkKfSQ+HAAlAwASAAYKMhrxCAC0AQABNQAFFAQIBAADAAAAAA==.',
Mu='Munco:BAABNQAECn8xAAITAAkKYCDeCwBKAwATAAkKYCDeCwBKAwAAAA==.Muncola:BAAANQAECgEIAQABNQAECgkJMQATAGAgAA==.Muncolito:BAAANQADCgEIAQABNQAECgkJMQATAGAgAA==.',
No='Notker:BAABNQAECn8dAAIOAAcKyxEceACuAQAOAAcKyxEceACuAQAAAA==.',
Os='Osrs:BAAANQAECgUIBgAAAA==.',
Pa='Pandorra:BAAANQADCgYICwAAAA==.Papaj:BAAANQABCggIEAAAAA==.Pasteurmoon:BAAANQAECgQIDwAAAA==.',
Pe='Peepingpanda:BAAANQADCgYIDQAAAA==.Penne:BAAANQADCgYIDwAAAA==.',
Pi='Pizzapie:BAABNQAECn8bAAMCAAgKoh/PGwDOAgACAAgKoh/PGwDOAgARAAEKAADhrQAvAAAAAA==.',
Ra='Raffine:BAAANQADCgUICAAAAA==.Rango:BAAANQADCgQIBAAAAA==.',
Re='Rennik:BAABNQAECn8yAAQUAAkKgiUyDwBVAwAUAAgKaCUyDwBVAwAGAAQKyiRTGgCYAQAVAAEKAAD0JgBOAAAAAA==.Revenant:BAAANQADCgYIBgAAAA==.',
['Rú']='Rúnil:BAAANQADCggIDwAAAA==.',
Sa='Saeris:BAAANQADCgUIBQAAAA==.Sanise:BAAANQADCggIGAAAAA==.',
Sc='Scorewin:BAEBNQAECn8sAAIWAAkKViLzAgBAAwAWAAkKViLzAgBAAwAAAA==.',
Se='Seral:BAAANQADCgcIBwAAAA==.',
Sh='Shankdela:BAAANQAECggIEwAAAA==.',
Si='Simi:BAAANQABCggICQAAAA==.Sinappi:BAABNQAECn8dAAILAAcKnRq1FAAVAgALAAcKnRq1FAAVAgAAAA==.Siñ:BAABNQAECn8fAAIXAAcKKgiTUQBxAQAXAAcKKgiTUQBxAQAAAA==.',
Sk='Skeetshootah:BAAANQAECgQIBwAAAA==.Skunkstomper:BAAANQADCgIIAgAAAA==.Skunkstömper:BAAANQABCgUIBQAAAA==.Skùnkstomper:BAAANQADCggICQAAAA==.Skúnkstomper:BAAANQABCgUIBQABNQADCgIIAgADAAAAAA==.',
Sl='Slowbadon:BAABNQAECn8ZAAMYAAcKeQ7XiAB+AQAYAAcKeQ7XiAB+AQAEAAQKpQxuLgHOAAAAAA==.',
St='Stakkzy:BAAANQAECgQIBwAAAA==.Streetdruid:BAAANQADCgYIBgABNQADCggIDgADAAAAAA==.Streetlight:BAAANQAECgYIEQABNQADCggIDgADAAAAAA==.Streetlizard:BAAANQADCgYIBgABNQADCggIDgADAAAAAA==.Streetpriest:BAAANQADCggIDgAAAA==.Streets:BAAANQADCgYIBgABNQADCggIDgADAAAAAA==.',
Ta='Tank:BAABNQAECn8wAAIMAAkKziKrAgCDAwAMAAkKziKrAgCDAwAAAA==.',
Te='Teafayd:BAAANQADCgYIEwAAAA==.',
Th='Thunderdot:BAABNQAECn8lAAIPAAkKyiHYDAAbAwAPAAkKyiHYDAAbAwAAAA==.',
Ti='Tigolock:BAAANQAECgMIAwABNQAECggIHAAIAIUFAA==.Tilvayne:BAACNQAFFH8JAAMRAAQKAgybEQC6AAARAAMKZgabEQC6AAAZAAQKWQo+IABJAAA1AAQKfzMAAxEACQqHHT4jAHICABEACQq3HD4jAHICABkABwpAHEE1AFACAAAA.',
To='Tomayter:BAABNQAECn8bAAIOAAcKEhkzaQDfAQAOAAcKEhkzaQDfAQAAAA==.',
Tr='Trinitee:BAAANQADCgUIBwAAAA==.Trist:BAABNQAECn8lAAMEAAkK9RiMYgBuAgAEAAkK9RiMYgBuAgAYAAMKSxK24wC1AAAAAA==.',
Tu='Turbogoat:BAABNQAECn8ZAAIZAAcKXx3iPAAqAgAZAAcKXx3iPAAqAgAAAA==.',
Tw='Twowolves:BAABNQAECn8lAAQGAAkK1x09LgARAQAUAAYKjRyTggDbAQAGAAMKkB89LgARAQAVAAMKVRPOGwCgAAAAAA==.',
Va='Valthir:BAAANQADCgYIBgAAAA==.',
Xe='Xevic:BAAANQAECgEIAQABNQAECgUICgADAAAAAA==.',
Za='Zalar:BAAANQAECgEIAgABNQAECgkJMgAUAIIlAA==.',
Ze='Zerene:BAABNQAECn8cAAIGAAcKCRFiFQDBAQAGAAcKCRFiFQDBAQAAAA==.',
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
