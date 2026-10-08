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

local lookup = {'Paladin-Holy','Mage-Arcane','Unknown-Unknown','Hunter-BeastMastery','Rogue-Assassination','Hunter-Marksmanship','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','Warrior-Arms','Warrior-Protection','DeathKnight-Frost','Druid-Balance','Druid-Restoration','Druid-Guardian','Hunter-Survival','Paladin-Retribution','Shaman-Elemental','Shaman-Restoration','Paladin-Protection','Monk-Windwalker','Monk-Mistweaver','Mage-Frost','DeathKnight-Unholy','Warrior-Fury','DemonHunter-Havoc','DeathKnight-Blood','Evoker-Preservation','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Subtlety','Warlock-Destruction','Shaman-Enhancement','Druid-Feral','Priest-Shadow','Warlock-Demonology','Priest-Discipline','Warlock-Affliction','Monk-Brewmaster',}
local provider = {region='US',realm='Garrosh',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aadolin:BAABNQAECoEnAAIBAAkKzh0DFAAhAwABAAkKzh0DFAAhAwAAAA==.Aardvarkeggs:BAAANQAECgMIBAAAAA==.',
Ab='Abaddon:BAAANQAECggICAAAAA==.Abi:BAAANQAFFAIIAgAAAA==.',
Ac='Acamar:BAAANQADCggIFwAAAA==.',
Ad='Adeleska:BAABNQAECoEdAAICAAcKHAe9+wBvAQACAAcKHAe9+wBvAQAAAA==.Aderina:BAAANQADCgcIBwAAAA==.Adessa:BAAANQAECggICwAAAA==.',
Ae='Aellibash:BAAANQADCgIIAgABNQAECgUICgADAAAAAA==.Aenivath:BAAANQADCgUJCAAAAA==.Aenlanast:BAAANQADCggICAAAAA==.',
Af='Aftercare:BAAANQAECgIJAgAAAA==.',
Ag='Agerthel:BAAANQAECgQIBAAAAA==.Agnergam:BAAANQADCgcIBwAAAA==.Agorath:BAAANQADCgYJBgAAAA==.',
Ah='Ahsnap:BAAANQAECgQIBAAAAA==.',
Ai='Airchiefsosa:BAAANQAECggIDQAAAA==.Airygrim:BAAANQADCgEJAQAAAA==.Aisatsana:BAAANQADCgQIBgAAAA==.',
Al='Alexstrasz:BAAANQAECgcICwAAAA==.Alopex:BAABNQAECoEcAAIEAAcKLA6diADJAQAEAAcKLA6diADJAQAAAA==.',
Am='Amaellara:BAABNQAECoEhAAICAAgKihf0jgBGAgACAAgKihf0jgBGAgAAAA==.Amajiki:BAAANQADCgYJAwAAAA==.',
An='Andrayah:BAAANQAECgEIAQAAAA==.Annakem:BAAANQADCgEIAQAAAA==.Annorah:BAAANQADCgEIAQAAAA==.Anthathein:BAAANQAECgMIBAAAAA==.',
Ao='Aoda:BAAANQAECgMJBAAAAA==.Aotrom:BAAANQAECgUIBQAAAA==.',
Ar='Aracus:BAAANQADCgQIBQAAAA==.Arcanefire:BAAANQADCgYIBgABNQAFFAMIAwADAAAAAA==.Archblade:BAAANQAECgQIDgAAAA==.Aristaana:BAAANQAECgEIAQABNQAFFAUICQAFADUWAA==.Armagnac:BAABNQAECoEuAAMEAAkKSx5pGAAgAwAEAAkKSx5pGAAgAwAGAAEK5gRLhgAoAAAAAA==.Arthias:BAAANQADCgEIAQAAAA==.',
As='Asroldal:BAAANQADCgYIBgAAAA==.Astralkitten:BAAANQAECgEIAQAAAA==.',
At='Atem:BAAANQABCgIIAgAAAA==.Atom:BAAANQAECgYIBgAAAA==.',
Au='Aufare:BAAANQAECgYIEwAAAA==.',
Av='Avacyn:BAAANQAECgMIAwAAAA==.Avarya:BAABNQAECoEnAAIHAAgKrCb3BQCJAwAHAAgKrCb3BQCJAwAAAA==.Averagerat:BAAANQAECgYIDwABNQAFFAcIIAAIAPMkAA==.Averagesham:BAAANQAECggIDwABNQAFFAcIIAAIAPMkAA==.Averagevoker:BAACNQAFFIEgAAMIAAcK8yTFAABuAgAIAAYK7yTFAABuAgAJAAIK2BmIBgC7AAA1AAQKgSoAAwgACQoqJj8BALQDAAgACQoqJj8BALQDAAkAAQouH8gcAFIAAAAA.Averwine:BAAANQADCgcIDQAAAA==.',
Ba='Babychow:BAAANQADCgEIAQAAAA==.Babynimyk:BAAANQAECgUICwAAAA==.Backyard:BAAANQADCgYIGAAAAA==.Bael:BAAANQAECgMIAwAAAA==.Bahamasoul:BAAANQAECgQIBAAAAA==.Balooi:BAAANQABCgYICQAAAA==.Baraxius:BAAANQADCgIIAgAAAA==.Bashtaz:BAEBNQAECoEfAAMKAAkKmyFrJgAQAwAKAAkKCCFrJgAQAwALAAYKOR7bDwD+AQABNQAFFAUICgAMANMcAA==.Basixx:BAAANQAECgMIAwAAAA==.Bayleaf:BAAANQAFFAIIAgABNQAFFAcIIAAIAPMkAA==.',
Bb='Bbeloree:BAAANQAECgQIBgAAAA==.',
Bd='Bdiotlcth:BAAANQADCgUJBQAAAA==.',
Be='Bearbryce:BAAANQADCggICAAAAA==.Bearykyns:BAABNQAECoEeAAQNAAgK3hVdNgAQAgANAAgKuhRdNgAQAgAOAAQKEBC0QwDZAAAPAAEKSBWsSgA9AAAAAA==.Beastwarden:BAABNQAECoEjAAMQAAgKtxJ+BQA6AgAQAAgKtxJ+BQA6AgAEAAEKMAHcSwEiAAAAAA==.Beatrixkiddo:BAAANQADCgYIBgAAAA==.Bejay:BAAANQADCgYIBgABNQAECgcICwADAAAAAA==.Belladar:BAAANQADCgMIAwAAAA==.Belokk:BAAANQADCggIEAAAAA==.Belwarr:BAAANQAECgUIDwAAAA==.Bemused:BAAANQAECgEIAQAAAA==.Benpai:BAAANQAECgEIAQAAAA==.Besticle:BAABNQAECoE2AAIKAAkKWCJHEQBxAwAKAAkKWCJHEQBxAwAAAA==.',
Bi='Bigcheddarz:BAAANQADCgMIAwAAAA==.Bigchungass:BAAANQAECgYIBgABNQAFFAQIBwARAGEWAA==.Bigttgothgf:BAAANQAECgUIBAAAAA==.Bilberry:BAAANQABCgQICAAAAA==.Binkie:BAAANQADCgcIGQABNQAECggIGgANANsHAA==.',
Bj='Bjaculator:BAAANQAECgcICwAAAA==.',
Bl='Blackcoat:BAAANQADCgIIAgAAAA==.Blackgranite:BAAANQAECgQIBAABNQAECgUICAADAAAAAA==.Blacklotus:BAAANQAECgIIAgAAAA==.Blayze:BAAANQADCgYIBgAAAA==.Blep:BAABNQAECoEaAAIHAAcK5w+MeAB4AQAHAAcK5w+MeAB4AQAAAA==.Bloodoath:BAAANQADCgEIAQABNQAECggILAASAOIVAA==.Blueheal:BAAANQAECgEIAQAAAA==.Bluemilk:BAAANQAECgEIAQAAAA==.Blueshiver:BAAANQAECgQIBwAAAA==.',
Bo='Bombadore:BAAANQADCgYIBgAAAA==.Bonesaw:BAAANQADCgIIAgABNQAECgUIDgADAAAAAA==.Booktök:BAAANQAECgUIBwABNQAECgcIEgADAAAAAA==.Bowlinder:BAABNQAECoEdAAMSAAkKECJyDgBpAwASAAkKECJyDgBpAwATAAgKORaiWADZAQAAAA==.Bowlinderr:BAAANQAECgEIAQAAAA==.Boyvine:BAAANQAECgYICQAAAA==.',
Br='Brahmana:BAAANQABCgYICwAAAA==.Braldar:BAAANQAECgMIBAAAAA==.Branas:BAAANQADCggIEAAAAA==.Braxiss:BAABNQAECoEkAAIEAAcKkxwwWwA5AgAEAAcKkxwwWwA5AgAAAA==.Break:BAAANQAFFAIIAgABNQAFFAcKFQARABggAA==.Breellspace:BAAANQADCgEIAQAAAA==.Brilin:BAABNQAECoEpAAMKAAkKQyLPDwB5AwAKAAkKQyLPDwB5AwALAAYKwx3gEgDJAQAAAA==.Brithio:BAAANQADCgQJAQAAAA==.Broguë:BAAANQAECgQICAAAAA==.Brokton:BAAANQADCgQIBAAAAA==.Brucarus:BAAANQADCggJCQABNQAECgMJBAADAAAAAA==.Bruce:BAAANQADCgYIDAAAAA==.Brueld:BAAANQAECgUICAABNQAECggILAASAOIVAA==.',
Bu='Bulldozzers:BAAANQADCgUIBQAAAA==.Bullshzitt:BAAANQAECggIAQAAAA==.Bumper:BAAANQADCgcJDAAAAA==.Busin:BAAANQAECgQICwAAAA==.',
['Bå']='Båshful:BAAANQAECgcIBwAAAA==.',
['Bë']='Bënzin:BAAANQADCgcIDQAAAA==.',
['Bî']='Bîllydakîd:BAAANQADCgYIBgAAAA==.',
Ca='Calabag:BAEANQAECgYICwABNQAECggIIgAPAP8gAA==.Calabloom:BAEBNQAECoEiAAIPAAgK/yB3BwDcAgAPAAgK/yB3BwDcAgAAAA==.Caland:BAAANQADCgIIAgAAAA==.Calibern:BAAANQAECgQIBAAAAA==.Calmm:BAAANQAECgYICgABNQAFFAQIBwARAGEWAA==.Canthndice:BAAANQAECgEIAwAAAA==.Capncrunchh:BAAANQAECgMIAwAAAA==.Caressaa:BAAANQADCgMJAwAAAA==.Cavalina:BAABNQAECoEwAAMUAAgKxBqWHgDHAQARAAgKLRUtcQAeAgAUAAYKhxuWHgDHAQAAAA==.Cavick:BAABNQAECoEYAAICAAcKPRGPzwDCAQACAAcKPRGPzwDCAQAAAA==.Cawnor:BAAANQAECgYIEwAAAA==.Caótica:BAAANQADCggIDgAAAA==.',
Ce='Celyanar:BAAANQADCgMJAgABNQAECgUIDAADAAAAAA==.Ceradwyn:BAAANQAECgEIAQAAAA==.',
Ch='Charön:BAACNQAFFIEKAAICAAMKNBPaKgDyAAACAAMKNBPaKgDyAAA1AAQKgTAAAgIACQpnIY0sACsDAAIACQpnIY0sACsDAAAA.Cheezewizard:BAAANQAECgYICAAAAA==.Chentrocka:BAABNQAECoFAAAICAAkKsSRoCgCpAwACAAkKsSRoCgCpAwAAAA==.Chillberto:BAAANQAECgYICQAAAA==.Chiselin:BAAANQAECgUJCQAAAA==.Chktmilk:BAAANQADCgYIBgAAAA==.Chopsui:BAAANQAECgQIBwAAAA==.',
Cl='Clankss:BAAANQADCggIGQAAAA==.Clerikyns:BAAANQADCgcIBwABNQAECggIHgANAN4VAA==.Clicks:BAAANQADCgMIAwAAAA==.Clics:BAAANQADCggICAAAAA==.',
Co='Coalgrim:BAAANQAECgUIDwAAAA==.Cosmíc:BAAANQAECgYIDgAAAA==.',
Cp='Cptbyakuya:BAACNQAFFIEFAAIRAAIKfh+3FgC8AAARAAIKfh+3FgC8AAA1AAQKgTMAAhEACQr2I1oSAG4DABEACQr2I1oSAG4DAAAA.',
Cr='Craterbip:BAAANQAECgYJCwAAAA==.Crimsonk:BAAANQADCgcIDQAAAA==.',
Cu='Curoconcum:BAAANQADCgYIBwAAAA==.',
Cy='Cyrub:BAAANQAECgEIAQAAAA==.',
Da='Dabrinto:BAAANQADCgYIBgAAAA==.Daedrian:BAABNQAECoEYAAIKAAkKNBlWRACkAgAKAAkKNBlWRACkAgAAAA==.Dailoom:BAAANQAECgUIBQAAAA==.Dallena:BAAANQAECgQIBwABNQAECgUIBAADAAAAAA==.Dankweaver:BAABNQAECoEiAAMVAAgKxBUHHQAiAgAVAAgKxBUHHQAiAgAWAAYKvBJaIgBIAQAAAA==.Daratri:BAAANQAECgUIBwABNQAECggIMAAUAMQaAA==.Darktales:BAAANQADCgYIBgAAAA==.Darthxander:BAAANQAECgIIAgAAAA==.Daruma:BAAANQADCggICAAAAA==.Daywrecker:BAAANQAECgQICQAAAA==.Dayyman:BAABNQAECoEkAAIUAAkK5B/KBgAiAwAUAAkK5B/KBgAiAwAAAA==.Dazuk:BAAANQADCgYIBgAAAA==.',
De='Deathlysham:BAAANQAECgIIBAAAAA==.Deathshroom:BAAANQADCggIGAABNQAECgUIBwADAAAAAA==.Deathsun:BAABNQAECoEjAAMEAAkK/SJqCwBxAwAEAAkK/SJqCwBxAwAGAAYKRQ21PAA9AQAAAA==.Deddonkey:BAAANQAECgIIAgABNQAECgUJBQADAAAAAA==.Deform:BAAANQAECgUIBQAAAA==.Deförmjr:BAAANQADCgUIBQABNQAECggIJgAXADUPAA==.Deianaera:BAAANQADCgQIBAAAAA==.Delldestus:BAAANQAECgQIBQAAAA==.Delmonicó:BAAANQAECgEIAgAAAA==.Demonics:BAAANQADCgYIBgAAAA==.Demonstix:BAAANQAECgcIEQAAAA==.Demontoki:BAAANQAECgMIAwAAAA==.Demv:BAAANQADCgIIAgAAAA==.Depressa:BAAANQADCgQIBAABNQAECgkJFgAPABkcAA==.Dernius:BAAANQADCggIEQAAAA==.Derran:BAAANQADCgcJBwAAAA==.Despairykyns:BAAANQAECgUIBgABNQAECggIHgANAN4VAA==.Dethbringa:BAABNQAECoEXAAMMAAgKFg9tRQBkAQAMAAcKDw1tRQBkAQAYAAQKRw8GhwDdAAAAAA==.Dewfall:BAABNQAECoEiAAIZAAkKKB2oAwDyAgAZAAkKKB2oAwDyAgAAAA==.Deylithdreyn:BAAANQAECgQIBwAAAA==.',
Dh='Dhuoth:BAABNQAECoEoAAIaAAkK3iIECABqAwAaAAkK3iIECABqAwAAAA==.',
Di='Diagoraz:BAAANQADCgUIBwAAAA==.Dialtone:BAAANQADCgQIBwABNQADCgQIBwADAAAAAA==.Dialtonee:BAAANQADCgQIBwAAAA==.Digitalbäth:BAAANQADCgUIBQAAAA==.Digoshadow:BAAANQAECgQIBwAAAA==.Dillonharper:BAAANQADCggICAAAAA==.Disgruntld:BAAANQAECgEIAgAAAA==.Disturbd:BAAANQAECgEIAQABNQAECgcIGgAHAOcPAA==.Ditdoo:BAAANQAECgEJAQAAAA==.',
Dk='Dkmetcàlf:BAAANQADCggICAAAAA==.',
Do='Donkeymonk:BAAANQAECgUJBQAAAA==.Dorkyspork:BAAANQAECgEIAQAAAA==.',
Dr='Dragonis:BAAANQADCggICAAAAA==.Dravenstone:BAAANQADCgYIBwAAAA==.Dreamerzz:BAAANQADCgYIBwAAAA==.Drovac:BAAANQAECgUICAAAAA==.Drugar:BAAANQADCgUIBQAAAA==.Druidxd:BAAANQADCgcICwAAAA==.Drumittz:BAAANQADCgEIAQAAAA==.Drworm:BAABNQAECoFAAAIMAAkKOiEtBwBeAwAMAAkKOiEtBwBeAwABNQAECgkJLAAKAJYgAA==.Drääko:BAAANQADCgYICAAAAA==.Drêdd:BAAANQABCgIJAgAAAA==.',
Ds='Dsonic:BAAANQADCgUICAAAAA==.',
Du='Dubbies:BAAANQAECgUICgAAAA==.Durtluz:BAAANQADCgcICAAAAA==.Dustandblood:BAAANQADCgMIAgABNQADCgYIBgADAAAAAA==.',
Dy='Dyrim:BAAANQAECgEIAQAAAA==.Dysthymia:BAAANQADCgUIBQABNQAECgkJMAATALIeAA==.',
['Dæ']='Dæmonkawlr:BAAANQADCgQIBAAAAA==.',
['Dê']='Dêformjr:BAABNQAECoEmAAMXAAgKNQ8FFABDAQACAAcKFApB8gCAAQAXAAYKMg8FFABDAQAAAA==.Dêvarim:BAAANQABCgQIBAAAAA==.',
['Dë']='Dëformjr:BAAANQADCgYIBgAAAA==.Dëfòrmjr:BAAANQADCgYICwABNQAECggIJgAXADUPAA==.Dëförmjr:BAAANQAECgUICwABNQAECggIJgAXADUPAA==.',
['Dú']='Dúbletap:BAAANQADCgYIBgAAAA==.',
Ea='Eajae:BAAANQADCgYICgAAAA==.',
Ed='Edennia:BAAANQAECgIIAgAAAA==.',
Eh='Ehvie:BAAANQADCggIDQABNQAECggIIgANAE0WAA==.',
Ei='Eidric:BAAANQADCgUIBAAAAA==.',
El='Elbrujo:BAAANQADCgcIDQAAAA==.Elenii:BAABNQAECoEoAAIHAAgKdh17LgCOAgAHAAgKdh17LgCOAgAAAA==.Eleynra:BAAANQADCgIIAgAAAA==.Elionor:BAAANQADCgEIAQAAAA==.Elstinko:BAAANQADCgYICgAAAA==.Elybear:BAAANQADCgUIBQAAAA==.Elychan:BAAANQADCgYIBgAAAA==.Elygance:BAAANQAECggICAAAAA==.Elÿ:BAABNQAECoEWAAIBAAkKABMcQwA7AgABAAkKABMcQwA7AgAAAA==.',
Em='Emptyside:BAAANQADCggJFwAAAA==.',
En='Enchorxxi:BAABNQAECoEWAAMbAAgK+hxFKgBXAgAbAAcKCx5FKgBXAgAYAAIKeBDVqwB0AAAAAA==.Enetrenazara:BAAANQAECgYIEgAAAA==.Eniar:BAAANQADCgUIBQABNQAECgMIAwADAAAAAA==.Eniaro:BAAANQAECgMIAwAAAA==.Enlonger:BAABNQAECoEjAAIcAAkKYg43GgAEAgAcAAkKYg43GgAEAgAAAA==.',
Ep='Epicgooner:BAAANQAECgUIDwAAAA==.',
Er='Erahm:BAAANQAECgMIAwAAAA==.Erahmm:BAAANQAECgUIDwAAAA==.Ergaraskreia:BAAANQADCgIIAgAAAA==.Erielia:BAAANQADCgIIAgABNQADCgYICAADAAAAAA==.Eruneenani:BAAANQADCgYIDAAAAA==.',
Es='Esmirelda:BAAANQAECgYIEAAAAA==.Essn:BAACNQAFFIELAAIdAAQK4CRuBgCWAQAdAAQK4CRuBgCWAQA1AAQKgTUAAh0ACQqSJo8AAPUDAB0ACQqSJo8AAPUDAAAA.',
Eu='Eulune:BAEANQAECgMIBAABNQAECgkJHgAWAB4UAA==.',
Ev='Evelynna:BAAANQADCggIFAAAAA==.Evilicecream:BAAANQADCgQIBAABNQAECgQIBQADAAAAAA==.',
Ex='Exsull:BAAANQAECgYIDwAAAA==.',
Fa='Faible:BAAANQADCgMIAwAAAA==.Faithwarrior:BAAANQAECgUICgAAAA==.Falk:BAAANQAECgEIAQAAAA==.Falron:BAABNQAECoGAAQIUAAgKnyWXDACwAgAUAAgKnyWXDACwAgAAAA==.Farday:BAAANQADCgUIBQAAAA==.Fathlia:BAABNQAECoEYAAITAAkKyhhZNABoAgATAAkKyhhZNABoAgAAAA==.Fazrien:BAAANQADCgIIAgAAAA==.',
Fe='Fezzjin:BAABNQAECoEYAAIBAAcKbhrqQwA4AgABAAcKbhrqQwA4AgAAAA==.',
Fi='Filbrust:BAAANQADCgIIAgAAAA==.Fishtanked:BAAANQADCgQIBgAAAA==.Fitzofrage:BAAANQADCgYIBwAAAA==.',
Fk='Fkem:BAAANQAECgQIAwABNQAECgkJMQAaAO8cAA==.',
Fl='Flashlights:BAAANQAECgEIAQABNQAECgYIEgADAAAAAA==.Fleshbiter:BAAANQAECgIIAgAAAA==.Flokindruid:BAAANQADCgIIAgABNQAECgYIEwADAAAAAA==.Flowingdeath:BAAANQADCgYICQABNQAECgYIEwADAAAAAA==.Flowingrage:BAAANQADCgYIBgABNQAECgYIEwADAAAAAA==.',
Fm='Fmjserval:BAAANQAECgQIBQAAAA==.',
Fo='Fomtoolery:BAAANQABCgUIBQAAAA==.Foot:BAABNQAECoEiAAIKAAkKLCDFMgDgAgAKAAkKLCDFMgDgAgAAAA==.Forcedk:BAAANQAECgQICQAAAA==.Forcefaith:BAABNQAECoEYAAIRAAkKCSRwFABjAwARAAkKCSRwFABjAwAAAA==.Forcemage:BAAANQAECgQIBAAAAA==.',
Fr='Freduardo:BAAANQADCgUIBgAAAA==.Freva:BAAANQAECggIEgAAAA==.Friarfox:BAAANQADCgYIBgABNQAECggIGgANANsHAA==.Fronkness:BAAANQAECgYIBgAAAA==.Frostfiree:BAAANQAECgEJAgABNQAECggILAASAOIVAA==.Fruitpuddle:BAAANQABCgEIAQABNQAECgkJIgAeABsaAA==.Frøsty:BAAANQADCgEIAQAAAA==.',
Fu='Furcana:BAAANQADCgIIAgAAAA==.Furlock:BAAANQAECgIIAwAAAA==.Furryhugger:BAABNQAECoEXAAISAAkKXyPdCACVAwASAAkKXyPdCACVAwAAAA==.Furrykisser:BAAANQADCgUIBQABNQAECgkJFwASAF8jAA==.Furstab:BAAANQADCgcIDAAAAA==.',
['Fì']='Fìzzypop:BAAANQADCgEIAQAAAA==.',
Ga='Galepalm:BAAANQAECgUIBwAAAA==.Gambriniss:BAAANQAECgQICAAAAA==.Gamea:BAABNQAECoEgAAIfAAcKFQsLIwCdAQAfAAcKFQsLIwCdAQAAAA==.Garloch:BAAANQADCgcIBwAAAA==.Gatoreggs:BAAANQAECgEIAQAAAA==.',
Ge='Geladra:BAAANQADCgcIBwABNQAECgkJMwAQAIobAA==.Gemmothy:BAAANQADCgcIEQAAAA==.',
Gi='Gibbychona:BAABNQAECoEfAAQbAAkKchxsLQBEAgAbAAkKuBlsLQBEAgAYAAIKDiAclgCyAAAMAAEKAxeGjQA/AAAAAA==.Giggaho:BAAANQADCgIIAgAAAA==.Ginblade:BAAANQADCgEIAQAAAA==.',
Gl='Glowshroom:BAAANQAECgIIAwABNQAECgUIBwADAAAAAA==.',
Go='Goldlust:BAAANQAECgEJAQAAAA==.Golotak:BAAANQADCgcIBwAAAA==.Gonnagetproc:BAAANQADCggICAAAAA==.Googale:BAAANQADCgUIBwAAAA==.Gordoc:BAAANQAECgUICwAAAA==.Gothboy:BAAANQADCggICAAAAA==.',
Gr='Graff:BAABNQAECoEYAAIbAAcKORlBPQDsAQAbAAcKORlBPQDsAQAAAA==.Grailed:BAAANQADCgEIAQAAAA==.Gratiana:BAAANQAECgUIDAAAAA==.Gravem:BAAANQADCgUIBQAAAA==.Gravie:BAAANQADCgIIAgAAAA==.Graystaf:BAAANQAECgQICAAAAA==.Greggorie:BAAANQAECgIIAwAAAA==.Grerizspace:BAAANQADCgYIBgAAAA==.Greyowl:BAAANQADCggIGwAAAA==.Greysun:BAAANQADCgUIBQAAAA==.Griffidan:BAAANQADCgIIAgAAAA==.Grifflez:BAAANQAECgYIEwAAAA==.Grumpli:BAABNQAECoEXAAICAAkK6gwJzQDHAQACAAkK6gwJzQDHAQAAAA==.',
Gu='Guljinn:BAAANQADCgQIBAAAAA==.Guytheshower:BAAANQAECgYIEwAAAA==.Guytoo:BAAANQADCgUJBQAAAA==.',
Gw='Gweilo:BAAANQAECgUIBQAAAA==.',
['Gê']='Gêralt:BAAANQADCgMIAwAAAA==.',
Ha='Habek:BAAANQADCgQIBQAAAA==.Hamadaver:BAAANQABCgUICAAAAA==.Handofblood:BAABNQAECoEVAAIRAAcKdgikygBNAQARAAcKdgikygBNAQAAAA==.Handymandy:BAAANQAFFAIIAgABNQAFFAQIBwARAGEWAA==.Harderrock:BAAANQADCgEIAQABNQAFFAMIAwADAAAAAA==.Hardrockgirl:BAAANQAECgcIDAABNQAFFAMIAwADAAAAAA==.Harmonechi:BAABNQAECoEoAAIgAAgK5BWoCQBUAgAgAAgK5BWoCQBUAgAAAA==.Haveasip:BAAANQAECgIIAgAAAA==.',
He='Healdealer:BAAANQAECgEIAQAAAA==.Healmonbello:BAABNQAECoEfAAMNAAkKGw3RPADlAQANAAkKGw3RPADlAQAOAAUK2gK7TQClAAAAAA==.Healystix:BAAANQAECgMIBAABNQAECgcIEQADAAAAAA==.Hellzcrusade:BAAANQAECgcIEQAAAA==.Henchi:BAAANQADCgIJAgABNQADCgUIFwADAAAAAA==.',
Hi='Higherheal:BAAANQADCgQIBAAAAA==.',
Ho='Hodesh:BAAANQADCgMJAwAAAA==.Holypuuss:BAACNQAFFIEHAAMRAAQKYRaYFwCzAAARAAIKAh+YFwCzAAAUAAIKwA1pCQCJAAA1AAQKgS0ABBEACQonJiMKAKEDABEACQonJiMKAKEDAAEAAwqPDS7QALQAABQAAgqeIfJGAKkAAAAA.Honeybumms:BAAANQAECgQJCQAAAA==.Hoplitedruid:BAAANQAECgUICgABNQAECgYIBwADAAAAAA==.Hoplitescout:BAAANQAECgYIBwAAAA==.Houndoom:BAAANQADCgYICgAAAA==.',
Ht='Htiál:BAAANQADCgIIAgAAAA==.Htiâl:BAAANQADCgIIAgABNQADCgIIAgADAAAAAA==.',
Hu='Huntko:BAAANQADCggIEAAAAA==.',
Hy='Hydrokyrios:BAAANQADCgYIBgAAAA==.Hyperthymia:BAABNQAECoEwAAITAAkKsh5QFQAKAwATAAkKsh5QFQAKAwAAAA==.Hyrakka:BAAANQAECgEIAQABNQADCgUIFwADAAAAAA==.',
Ic='Iceeveins:BAAANQADCggICAAAAA==.Icystyx:BAAANQAECgUICAAAAA==.',
Il='Ilyamurometz:BAABNQAECoEXAAILAAkKlRwxCACqAgALAAkKlRwxCACqAgAAAA==.',
Im='Immorta:BAABNQAECoElAAMKAAkKbBROWQBjAgAKAAkKVhROWQBjAgAZAAYKWQ8hEwBHAQAAAA==.',
In='Indigokiya:BAABNQAECoEaAAINAAcK7A6jSgCQAQANAAcK7A6jSgCQAQAAAA==.Influencer:BAAANQADCggICgAAAA==.Ingesteel:BAAANQADCgEIAQAAAA==.Inodoro:BAABNQAECoEjAAIhAAkKpx3EBAA7AwAhAAkKpx3EBAA7AwAAAA==.',
Io='Iordgodplaya:BAAANQAECggIEgAAAA==.',
Ir='Irabmal:BAABNQAECoEtAAIOAAkK5yCNBABsAwAOAAkK5yCNBABsAwAAAA==.Iriclaw:BAACNQAFFIEMAAIEAAUKsCBkBADyAQAEAAUKsCBkBADyAQA1AAQKgS8AAgQACQrOJtUAAPkDAAQACQrOJtUAAPkDAAAA.Ironpanda:BAAANQADCgEIAQAAAA==.',
Is='Isaama:BAAANQADCgQIBAAAAA==.Isothymia:BAABNQAECoEjAAIBAAkKVBbrLwCLAgABAAkKVBbrLwCLAgABNQAECgkJMAATALIeAA==.',
It='Itsmepip:BAAANQAECgUIEgAAAA==.',
Ja='Jackiechanda:BAAANQAECgMIAwAAAA==.Jacoby:BAAANQAECgUIBQABNQAFFAIIBAAhAGYiAA==.Jadefires:BAAANQAECgMIAwABNQAECgQIBAADAAAAAA==.Jadelite:BAAANQADCggIHgABNQAECgQIBAADAAAAAA==.Jaderanger:BAAANQAECgQIBAAAAA==.Janddasham:BAAANQAECgYIDQAAAA==.Janddavoker:BAACNQAFFIEHAAIcAAMKUg7JDgDXAAAcAAMKUg7JDgDXAAA1AAQKgS0AAhwACQqNIa8FAEQDABwACQqNIa8FAEQDAAAA.Jarnbrez:BAAANQADCgMIAwAAAA==.Jawnwick:BAAANQADCgMIAwAAAA==.Jaxo:BAAANQAECgYIDwABNQAECggIGQAYACsjAA==.',
Jd='Jdag:BAAANQADCggICAAAAA==.',
Je='Jezrien:BAAANQADCgcIDAAAAA==.',
Jh='Jherri:BAAANQAECgYIDAAAAA==.',
Ji='Jimbeamer:BAAANQAECgEIAQAAAA==.',
Jk='Jkm:BAAANQAECgUIDgAAAA==.',
Jo='Joanexotic:BAABNQAECoEWAAIMAAYKuwp5TgAwAQAMAAYKuwp5TgAwAQAAAA==.Joetothemama:BAAANQADCgYIBgAAAA==.Johnork:BAAANQAECgEIAQAAAA==.Jojolion:BAAANQAECgUIDgAAAA==.',
Jr='Jrocmfka:BAAANQAECgYIEQAAAA==.',
Jt='Jtama:BAAANQADCgUIBwAAAA==.',
Ju='Junefyre:BAAANQADCgEIAQABNQAECgUIDgADAAAAAA==.Juntor:BAAANQADCgcIBwAAAA==.',
Ka='Kaeliin:BAAANQADCggIFAAAAA==.Kage:BAAANQAECgEIAQAAAA==.Kaiderten:BAAANQAECgEIAQAAAA==.Kailo:BAAANQAECgEIAQAAAA==.Kal:BAAANQAECgEIAQAAAA==.Kalorondir:BAAANQADCgQICAAAAA==.Kamila:BAAANQADCggIDAAAAA==.Kaorí:BAAANQAECgcIDgAAAA==.Karatekyns:BAAANQADCgIIAgABNQAECggIHgANAN4VAA==.Kaselian:BAAANQAECgYICgAAAA==.Kashimo:BAAANQAECgQIBAABNQADCgUIBQADAAAAAA==.Katherwind:BAAANQABCgcIDAAAAA==.Kattara:BAABNQAECoElAAMiAAkKTxgNCgBpAgAiAAkKtBQNCgBpAgAPAAYKoRkXGACrAQAAAA==.Kattarwal:BAAANQAECgEIAwAAAA==.Kayalanii:BAAANQADCggICAAAAA==.Kayoti:BAAANQADCgEJAQABNQAECgYICQADAAAAAA==.Kazuhla:BAAANQAECgQIDgAAAA==.',
Ke='Keiryn:BAAANQAECgIIAwAAAA==.Kennily:BAAANQADCgQIBQAAAA==.Kentyrakka:BAAANQAECgUIDgAAAA==.Keyndian:BAAANQAECgYIBgAAAA==.',
Kh='Khaoptik:BAACNQAFFIEXAAICAAYKghKODQDqAQACAAYKghKODQDqAQA1AAQKgSAAAgIACQrTG8FuAIsCAAIACQrTG8FuAIsCAAAA.Khaotikdraco:BAAANQAECgQICAABNQAFFAYIFwACAIISAA==.Khaotikmeta:BAAANQAECgYICgAAAA==.',
Ki='Kiffypoo:BAAANQAECgUIDwAAAA==.Kil:BAABNQAECoEnAAMWAAgKLRuUDgBzAgAWAAgKLRuUDgBzAgAVAAYKmgetOwD+AAAAAA==.Kiljaiden:BAAANQABCgIIAgAAAA==.Kiltree:BAAANQAECgcICwABNQAECggIJwAWAC0bAA==.Kisho:BAAANQADCgMIAwAAAA==.Kiyoshie:BAABNQAECoErAAIEAAkKZhQ5RAB5AgAEAAkKZhQ5RAB5AgAAAA==.',
Kl='Klanky:BAAANQADCggICAABNQAFFAUIEAAjAGgeAA==.',
Kn='Kn:BAAANQAECgIIAgAAAA==.Kneehighjake:BAAANQADCgYJBgAAAA==.',
Ko='Kobëbeef:BAAANQADCggIDwAAAA==.Kodiakpax:BAAANQADCgUIDQAAAA==.Kontroll:BAEANQADCggIJwABNQAECggIEAADAAAAAA==.Kookee:BAABNQAECoEkAAIkAAgKzBpcXAAgAgAkAAgKzBpcXAAgAgAAAA==.Korice:BAAANQAECgYIDAAAAA==.',
Kr='Krieghelm:BAAANQAECgIIAgAAAA==.Krypticgrip:BAABNQAECoEiAAIbAAkKCiGHCwBIAwAbAAkKCiGHCwBIAwABNQAFFAYIFwACAIISAA==.',
Ku='Kumaa:BAABNQAECoEXAAIEAAcKnBWdbAANAgAEAAcKnBWdbAANAgAAAA==.Kunclebun:BAAANQADCgUIBgAAAA==.',
Ky='Kyle:BAAANQAECgQICAAAAA==.Kylidon:BAAANQADCgYIBgAAAA==.Kynlauriana:BAAANQAECgQIBAAAAA==.',
['Kö']='Köttbullar:BAAANQADCgMIAwAAAA==.',
La='Lalaind:BAAANQADCgYICAAAAA==.Landapipen:BAAANQAECggICAAAAA==.Larissa:BAABNQAECoEaAAINAAgK2wcPTgB+AQANAAgK2wcPTgB+AQAAAA==.Lathillea:BAAANQAECgUIDwAAAA==.Launchpad:BAAANQADCgQIBAAAAA==.Lazzirus:BAABNQAECoEjAAISAAgKLh52KQC4AgASAAgKLh52KQC4AgAAAA==.',
Le='Leedict:BAAANQAECgUJDAAAAA==.Leerøy:BAAANQAECgYIEAAAAA==.Leilani:BAAANQADCgYIGAAAAA==.Leinalei:BAAANQADCggICAABNQAECggIGwACAFEiAA==.Lessii:BAEBNQAECoEhAAIYAAkKcBwUKwBoAgAYAAkKcBwUKwBoAgAAAA==.Leyalis:BAAANQADCgYIBgAAAA==.',
Li='Lidande:BAAANQADCgYIBgAAAA==.Lidarcis:BAABNQAECoEjAAIbAAkKFSD6DwAaAwAbAAkKFSD6DwAaAwAAAA==.Liedora:BAAANQADCgYJDAAAAA==.Lightpraiser:BAAANQAECgYIEwAAAA==.Limjahey:BAAANQADCggIHwAAAA==.Limpshrimp:BAAANQADCgQIBAABNQAFFAMIAwADAAAAAA==.Linra:BAABNQAECoEaAAQHAAgKjg7faACvAQAHAAgKjg7faACvAQAlAAEKKA+SIwA6AAAjAAEK4wr5dQAmAAAAAA==.Littlefatt:BAABNQAECoEcAAINAAgKlxHrPgDXAQANAAgKlxHrPgDXAQAAAA==.',
Ll='Llich:BAAANQAECgMIBQAAAA==.',
Lo='Longdukdhong:BAAANQADCgYIBwAAAA==.Lostdogg:BAAANQADCgMIAwABNQAECgYIEwADAAAAAA==.',
Lu='Luassei:BAAANQADCggIEgAAAA==.Lucishifts:BAABNQAECoEdAAMNAAkKhSIfCgBvAwANAAkKhSIfCgBvAwAPAAEKDSMyQQBgAAAAAA==.Lucîan:BAAANQAECgMIBQAAAA==.Lumaris:BAAANQADCgcIBwAAAA==.Lunamorr:BAAANQADCgYIBgAAAA==.Luphoe:BAAANQAECggIBwAAAA==.Luä:BAAANQAECgUIBQAAAA==.',
Ly='Lyserra:BAAANQAECgUICQAAAA==.Lyudmila:BAAANQAECgIIAgAAAA==.',
Ma='Mabell:BAAANQADCgEIAQAAAA==.Mackori:BAAANQADCggJCwAAAA==.Maddawggamin:BAAANQADCgQIBAAAAA==.Maekar:BAAANQAECgIJAgAAAA==.Mafi:BAAANQADCgMIAwAAAA==.Magenos:BAAANQAECgQJBAAAAA==.Magic:BAAANQAECgEIAQAAAA==.Magicpants:BAAANQAECgQICAAAAA==.Magobiga:BAAANQADCgYICAAAAA==.Mahrx:BAACNQAFFIEOAAIVAAYK5yIfAgBKAgAVAAYK5yIfAgBKAgA1AAQKgSMAAhUACQp1JUsGAFkDABUACQp1JUsGAFkDAAAA.Malaricia:BAAANQADCgMIAQAAAA==.Mangangazo:BAAANQADCggICAABNQAECgEIAwADAAAAAA==.Mawaru:BAAANQAECgQIBQAAAA==.Maxanadu:BAAANQADCgcIHwAAAA==.Maxmiup:BAAANQADCgYIBgAAAA==.Mayalla:BAAANQAECgIIAgAAAA==.',
Me='Meatpipe:BAAANQAECgEIAQAAAA==.Medarela:BAAANQAECgUIDgAAAA==.Meeke:BAACNQAFFIEQAAIjAAUKaB6oBADKAQAjAAUKaB6oBADKAQA1AAQKgSgAAiMACQq0Iy0GAGUDACMACQq0Iy0GAGUDAAAA.Meekrob:BAAANQAECgEIAQAAAA==.Mell:BAABNQAECoEnAAIRAAkKUhxHSgCPAgARAAkKUhxHSgCPAgABNQAFFAIIBAADAAAAAA==.Melmin:BAAANQAECgQIDwAAAA==.Meroman:BAAANQAECgEIAQAAAA==.Metamora:BAAANQAECgQIBgABNQAECgYIDAADAAAAAA==.Meuria:BAAANQAECgUIDwAAAA==.',
Mi='Midgetlord:BAABNQAECoEuAAIRAAkK1SInHwAwAwARAAkK1SInHwAwAwAAAA==.Midjiggle:BAAANQADCgIIAgAAAA==.Miklos:BAAANQADCggIFwAAAA==.Military:BAAANQADCgEIAQAAAA==.Minxm:BAAANQADCggIDwAAAA==.Minxmaxed:BAAANQADCggIEAAAAA==.Misstearly:BAAANQAECgYIBwAAAA==.Mividita:BAAANQADCggICAAAAA==.',
Mo='Modicon:BAAANQADCgEIAQAAAA==.Moltonmonk:BAAANQADCgcIDQAAAA==.Moneebagz:BAAANQADCggIGwAAAA==.Montblanc:BAAANQADCggJCAAAAA==.Moonchylde:BAAANQADCggIDQABNQAECggIGgANANsHAA==.Moonem:BAABNQAECoEiAAINAAgK9iDUGQDfAgANAAgK9iDUGQDfAgAAAA==.Moosteerious:BAEANQAECggIEAAAAA==.Mossacre:BAABNQAECoEwAAMKAAgKOiE+MQDmAgAKAAgKOiE+MQDmAgAZAAIKkhDiIQB8AAAAAA==.Mossburg:BAAANQADCgMIAwAAAA==.Mossherder:BAAANQABCgEIAQAAAA==.',
Mu='Musubbi:BAAANQADCgMIAwAAAA==.',
['Mé']='Méta:BAAANQAECgYIDAAAAA==.',
Na='Naanda:BAAANQABCgcICwAAAA==.Nachopapa:BAAANQAECgIIAgAAAA==.Nalorspace:BAAANQADCgYIEQAAAA==.Naniwa:BAABNQAECoEeAAITAAkKHiHJEQAiAwATAAkKHiHJEQAiAwAAAA==.Narwail:BAAANQAECgYIDgAAAA==.Narwhall:BAAANQADCggIFgABNQAECgYIDgADAAAAAA==.Nasathen:BAAANQAECgEIAQABNQAECgUICgADAAAAAA==.Natanus:BAAANQADCgUICwAAAA==.Natsuko:BAAANQADCgMIAwAAAA==.Nazaric:BAAANQAECgcIDwAAAA==.Nazaricksm:BAAANQADCgMIAwABNQAECgcIDwADAAAAAA==.Nazgeul:BAAANQADCgYICwAAAA==.',
Nb='Nbi:BAAANQABCgQJBQABNQAECgUICgADAAAAAA==.',
Ne='Necrodik:BAAANQADCgQIBAAAAA==.Neladris:BAAANQADCgIIAgAAAA==.Nelagorn:BAAANQAECgYIBgAAAA==.Nemesís:BAAANQABCgYIBwAAAA==.Neohorn:BAAANQAECgEIAwAAAA==.Neomyk:BAAANQADCggJDgAAAA==.Neoptolemus:BAAANQAECgEIAQAAAA==.Neoqled:BAAANQAECgQICwAAAA==.Neorhon:BAAANQADCgUIBQAAAA==.Nerclopse:BAABNQAECoEsAAISAAgK4hXdRAA3AgASAAgK4hXdRAA3AgAAAA==.Nerco:BAAANQADCgYIBgABNQAECggILAASAOIVAA==.Neverender:BAAANQAECgUIDgAAAA==.Nexian:BAAANQABCgQIBgAAAA==.',
Ni='Niarwodahs:BAAANQAECgQICQAAAA==.Niaryci:BAAANQAECgYIDAAAAA==.Nightfangz:BAAANQADCgYIDAAAAA==.Nils:BAAANQADCgYIBwAAAA==.Nims:BAAANQADCgUICwABNQAECgQICgADAAAAAA==.',
Nm='Nmoney:BAAANQAECgMIAwAAAA==.',
No='Noritotem:BAABNQAECoEYAAIhAAgKJyL6BgADAwAhAAgKJyL6BgADAwAAAA==.Note:BAAANQADCgUICQAAAA==.Notec:BAAANQADCggIAQAAAA==.Notics:BAAANQAECgIIAgAAAA==.Novacainê:BAAANQAECgQIBgAAAA==.',
Nu='Nuff:BAAANQADCgYIDQAAAA==.Nuikai:BAAANQAECgUJDgAAAA==.Nukum:BAAANQADCgYICwAAAA==.',
Ob='Obsidiansun:BAAANQAECgUIBwAAAA==.',
Oc='Octame:BAAANQAECgQICgAAAA==.',
Ol='Olethvia:BAAANQADCgQIBwABNQAECgUIDAADAAAAAA==.',
On='Onirai:BAAANQADCgUIBQAAAA==.Onlylight:BAAANQADCggICAAAAA==.',
Oo='Oopsy:BAAANQADCgQIBAAAAA==.Ooran:BAAANQADCggICAAAAA==.Oororoe:BAAANQADCgcICgAAAA==.',
Op='Opalescence:BAAANQADCgcIGgAAAA==.Opie:BAAANQABCgIJAgAAAA==.Optional:BAABNQAECoEiAAIQAAkK1SWwAACbAwAQAAkK1SWwAACbAwAAAA==.',
Or='Orgargo:BAAANQAECgUIDwAAAA==.',
Os='Osley:BAAANQADCgMIBgAAAA==.',
Ou='Oule:BAEBNQAECoEeAAIWAAkKHhTaEgAiAgAWAAkKHhTaEgAiAgAAAA==.',
Ox='Oxydjinn:BAAANQADCgUIBQAAAA==.',
Pa='Pallorx:BAAANQADCgYIBgAAAA==.Pallyzombi:BAAANQAECgMIAwABNQAECggIIQACAIoXAA==.Paluoth:BAAANQADCgEIAQAAAA==.Pandasennin:BAAANQAECgEIAQAAAA==.Papachains:BAAANQADCgYIDAABNQAECggJAQADAAAAAA==.Papahammer:BAAANQAECggIBgABNQAECggJAQADAAAAAA==.Papamuffin:BAAANQAECggICAABNQAECggJAQADAAAAAA==.Papashootin:BAAANQAECggJAQAAAA==.Paperplate:BAABNQAECoExAAMOAAkKeiHtBABlAwAOAAkKeiHtBABlAwANAAYKtxNXUABxAQAAAA==.Paradox:BAABNQAECoEpAAIiAAkK0iG7AgBtAwAiAAkK0iG7AgBtAwAAAA==.Pattyhealsu:BAACNQAFFIEOAAITAAUKYRi3BwC5AQATAAUKYRi3BwC5AQA1AAQKgSkAAhMACQraIQYPADYDABMACQraIQYPADYDAAAA.Pawlyn:BAAANQADCgEIAQAAAA==.',
Pe='Peachizz:BAAANQAECgEIAQAAAA==.Pelikohjo:BAAANQAECgQICAABNQAECggINwAQAP8YAA==.Pelivarondo:BAABNQAECoE3AAMQAAgK/xhsBgAIAgAQAAcKDRtsBgAIAgAEAAMKMg4iBgGzAAAAAA==.Pelizandeth:BAAANQADCggIHAABNQAECggINwAQAP8YAA==.Pepegas:BAAANQADCggJHQAAAA==.Pestillia:BAABNQAECoEaAAImAAcKNRkeBgAwAgAmAAcKNRkeBgAwAgAAAA==.',
Ph='Phoffynax:BAAANQAECgMIBQAAAA==.Phundip:BAAANQADCgMIBgABNQAECgQICgADAAAAAA==.',
Pi='Pistolbeat:BAAANQADCgUIBQAAAA==.',
Pk='Pkthunder:BAAANQADCgUIBQAAAA==.',
Pl='Playful:BAAANQADCggIDgAAAA==.Plopopotamus:BAABNQAECoEfAAQQAAgK7iDvAwCUAgAQAAcKih/vAwCUAgAGAAYKGBcuNQB4AQAEAAEKriZdJQFVAAAAAA==.',
Po='Poedanrin:BAAANQAECgEIAQAAAA==.Polikarp:BAAANQABCgQIBwAAAA==.Pookìe:BAAANQAECgUICwAAAA==.Poorsol:BAAANQAECgQICgAAAA==.',
Ps='Psychoclaw:BAAANQAECgUIBwAAAA==.Psyko:BAAANQADCgMIAwABNQADCggICAADAAAAAA==.',
Qu='Quickbrown:BAAANQAECgQIBwAAAA==.',
Ra='Raced:BAAANQADCgQIBAAAAA==.Raebspace:BAAANQAECgYIBgAAAA==.Ragenel:BAAANQAECgIIAwAAAA==.Rahxe:BAAANQAECgUIBwAAAA==.Raikz:BAAANQAECgcIDgAAAA==.Raiyne:BAAANQADCggIDwAAAA==.Randolphus:BAAANQAECgUIBwABNQAECgUICwADAAAAAA==.Rateddz:BAAANQAECgEIAQAAAA==.Ratraxa:BAAANQADCgYIBgAAAA==.Rats:BAABNQAECoE6AAIdAAkKJCMvBACNAwAdAAkKJCMvBACNAwAAAA==.Ratshield:BAABNQAECoEgAAILAAgK3iB0BQD8AgALAAgK3iB0BQD8AgABNQAECgkJOgAdACQjAA==.Ratwynne:BAAANQADCggICAAAAA==.',
Re='Regifted:BAAANQADCgYIBgAAAA==.Rendis:BAAANQADCgIIAgAAAA==.Reno:BAABNQAECoEeAAIEAAcKbROxeQDtAQAEAAcKbROxeQDtAQAAAA==.Renthyr:BAAANQADCggIDQAAAA==.Reportcard:BAAANQAECgEIAQABNQAFFAMIAwADAAAAAA==.Reurog:BAAANQAECgYIEAAAAA==.Revanjmt:BAAANQADCgYIBAAAAA==.',
Rh='Rhakudu:BAAANQADCgYIBgABNQAECgcIFwATAB8fAA==.',
Ri='Rian:BAACNQAFFIELAAIGAAUK3xm1CACSAQAGAAUK3xm1CACSAQA1AAQKgSIAAgYACQrrI/cFAGgDAAYACQrrI/cFAGgDAAE1AAUUBwgPAAIAyRoA.Rigbee:BAAANQADCgUICgAAAA==.Ritalia:BAAANQAECgcIDgAAAA==.',
Rm='Rmnieech:BAAANQAECgYIEAAAAA==.',
Ro='Roadiee:BAAANQAECgMIAwAAAA==.Roadiex:BAAANQADCgIIAwAAAA==.Roadkyll:BAAANQAECgQIBgAAAA==.Ronynn:BAAANQADCgEIAQAAAA==.Rosamoon:BAAANQAECgIIAgAAAA==.Rosilyn:BAAANQAECgUICgAAAA==.',
Ru='Rugbee:BAAANQADCgQIBAAAAA==.Rurrick:BAAANQAECgEIAQAAAA==.',
Ry='Ryzee:BAABNQAECoEWAAITAAcKfRR2YwC0AQATAAcKfRR2YwC0AQAAAA==.',
['Rå']='Råinè:BAAANQADCgcIBwABNQAECgMIAwADAAAAAA==.',
Sa='Sahmash:BAAANQADCgIIAgAAAA==.Salara:BAABNQAECoEYAAICAAYK/RKr5wCUAQACAAYK/RKr5wCUAQAAAA==.Salasong:BAAANQADCgcIEwAAAA==.Saldri:BAAANQADCgMIAwAAAA==.Saltytoast:BAAANQAECgEIAQAAAA==.Sambda:BAAANQADCgYIBwABNQAECgIIAgADAAAAAA==.Samberia:BAAANQADCgIIAgAAAA==.Sambilton:BAAANQADCgcIDAAAAA==.Sambraicho:BAAANQADCggIDAABNQAECgIIAgADAAAAAA==.Samburai:BAAANQAECgEIAQABNQAECgIIAgADAAAAAA==.Samuella:BAAANQAECgcIEAAAAA==.Sandrinea:BAAANQAECgYIEwAAAA==.Sarinya:BAAANQADCggIFgAAAA==.Sauceym:BAAANQABCggICwAAAA==.Saytens:BAAANQAECggJEAAAAA==.',
Sc='Scargiver:BAAANQADCgEJAQAAAA==.Scarllett:BAAANQAECgIIBwABNQAECgkJFwASAF8jAA==.Scarykyns:BAAANQADCgYIBgABNQAECggIHgANAN4VAA==.Schatzi:BAAANQADCggICAAAAA==.Scrubmage:BAAANQAECgQIBQAAAA==.',
Se='Secondwall:BAAANQAECgQIBAAAAA==.Sedale:BAAANQAECgUIDAAAAA==.Seesdeline:BAAANQADCggIBwABNQAECgQIBAADAAAAAA==.Seilene:BAAANQAECgIIAgABNQAECgIIBQADAAAAAA==.Selisi:BAAANQAECgQICAABNQAECgUICgADAAAAAA==.Senddra:BAAANQABCgYICAAAAA==.Senilea:BAAANQADCgEIAQAAAA==.Seo:BAAANQAECgcIDQAAAA==.Seraf:BAACNQAFFIEFAAIYAAMKjgxCEADTAAAYAAMKjgxCEADTAAA1AAQKgTIAAxsACQoOJqEBANgDABsACQrtJaEBANgDABgACQrPIZ0VAPUCAAAA.Serafain:BAAANQAECggIEwABNQAFFAMIBQAYAI4MAA==.Sevonixz:BAAANQAECgEIAQAAAA==.',
Sh='Shadowerise:BAAANQAECgMIBAAAAA==.Shaforgold:BAACNQAFFIEIAAISAAQKQw3QDwAyAQASAAQKQw3QDwAyAQA1AAQKgSMAAhIACQqyIAcTAEUDABIACQqyIAcTAEUDAAAA.Shalaz:BAAANQADCggJCAAAAA==.Shalazard:BAAANQAECgQIBwAAAA==.Shamananana:BAAANQADCgYIBgAAAA==.Sharrina:BAAANQABCgEIAQAAAA==.Shawtyschit:BAAANQAFFAMIAwAAAA==.Shibal:BAABNQAECoEjAAMBAAcKehanTgAQAgABAAcKehanTgAQAgARAAQKHQ2J/gDpAAAAAA==.Shinerbock:BAAANQADCgUIBQAAAA==.Shinystepdad:BAAANQADCgUIBQAAAA==.Shotorock:BAAANQAECgMIAgAAAA==.Shreckfive:BAAANQAECgQIBwAAAA==.Shrekismydad:BAAANQADCgQIBAAAAA==.Shroompie:BAAANQADCgcIDQABNQAECgUIBwADAAAAAA==.Shroomshock:BAAANQAECgUIBwAAAA==.Shushumen:BAABNQAECoEYAAIYAAcK7xXqSwC+AQAYAAcK7xXqSwC+AQAAAA==.Shänk:BAAANQADCgcIEQAAAA==.',
Si='Sicknezz:BAAANQADCgYJCwABNQAECggIEAADAAAAAA==.Sidewinder:BAAANQAECgQIBQABNQAECgkJIgAQANUlAA==.Siinyster:BAAANQADCgMIAwAAAA==.Sikmode:BAAANQAECgQICgAAAA==.Sildrusil:BAAANQADCgEIAQAAAA==.Silverstarz:BAAANQABCggIFQABNQAFFAMICAANADwZAA==.Sindari:BAAANQAECgcIEgAAAA==.Sinturio:BAAANQAECgYICwAAAA==.Sipsy:BAAANQAECgUIDgAAAA==.',
Sk='Skarg:BAAANQAECgMICgAAAA==.Skyeashe:BAAANQAECgIIAgAAAA==.',
Sl='Sleezytease:BAAANQADCgcIBwAAAA==.Slimdusty:BAAANQADCgQICAAAAA==.Slingblades:BAAANQAECggIEAAAAA==.Slobbrknckr:BAAANQADCgcIBwABNQAFFAQIBwARAGEWAA==.Slowmo:BAAANQAECggIEgAAAA==.',
Sm='Smittles:BAAANQAECgYICQAAAA==.',
Sn='Sneakystix:BAAANQADCgYIBgABNQAECgcIEQADAAAAAA==.Snowtigerr:BAAANQABCgIJAgAAAA==.',
So='Solarflare:BAAANQAECgcIBwAAAA==.Sootclaw:BAAANQADCgYICQAAAA==.Sophus:BAAANQAECgUICQAAAA==.Soren:BAAANQAECgQIBAAAAA==.Sorenko:BAAANQAECgQICQABNQAECgQIBAADAAAAAA==.',
Sp='Spagooter:BAABNQAECoEjAAMkAAkKDSC4JQDVAgAkAAgKICG4JQDVAgAgAAEKdRdYaQBCAAAAAA==.Sparklepants:BAABNQAECoEjAAICAAkKUSE3KwAvAwACAAkKUSE3KwAvAwAAAA==.Spencerz:BAAANQADCgEIAQAAAA==.Speyesee:BAAANQAECgUIDQAAAA==.Splashydank:BAAANQAECgEIAQAAAA==.Spookyish:BAAANQAECgUJCgAAAA==.',
Sq='Squidstens:BAAANQABCgMIAwAAAA==.',
St='Stabbydank:BAAANQAECgIIAgAAAA==.Stackss:BAAANQAECgEIAQAAAA==.Starset:BAAANQADCggICAAAAA==.Staypuff:BAAANQABCgMIAwAAAA==.Stnkychz:BAAANQADCggIDwAAAA==.Stonedninja:BAAANQADCgIIAQAAAA==.Stonemason:BAAANQAECgUICwAAAA==.Stoneskin:BAAANQADCgUJCQAAAA==.Strawberymik:BAAANQADCgEIAQAAAA==.',
Su='Submisive:BAAANQAECgQIBQAAAA==.Supe:BAAANQAECgUIDQAAAA==.Superstar:BAAANQADCggICAAAAA==.',
Sw='Swagruid:BAAANQAECgYIEwAAAA==.Swampslinger:BAAANQAECgYIEQAAAA==.Swordlady:BAAANQAECgUIEQABNQAECggIKAAHAHYdAA==.',
Sy='Syncxx:BAAANQADCgIIAgAAAA==.Syntari:BAAANQAECgQIBgAAAA==.Syntyr:BAAANQADCgMIAwAAAA==.Synyra:BAAANQADCgcIBwAAAA==.Synìk:BAAANQADCgUICgAAAA==.',
['Sö']='Söma:BAAANQAECgYICQAAAA==.',
Ta='Taktixxloxx:BAAANQABCgMIAwAAAA==.Talenalat:BAAANQAECggICAAAAA==.Tankerbelle:BAAANQADCgEIAQAAAA==.Tannarisse:BAAANQADCgQIBQAAAA==.Taymatt:BAAANQAECgUIDgAAAA==.Tazstinko:BAABNQAECoEsAAIKAAkKliDfGQBEAwAKAAkKliDfGQBEAwAAAA==.',
Te='Teaveen:BAAANQAECgMIAwAAAA==.Tectonic:BAAANQAECgYIDAABNQAFFAUICQAFADUWAA==.Tejasgeek:BAAANQAECgUIDQAAAA==.Tenleron:BAAANQABCgIIAgAAAA==.Tenntoes:BAAANQADCgYIBgAAAA==.Tewiyakichkn:BAAANQAECggIEAAAAA==.',
Th='Thegoob:BAAANQABCgMIAwAAAA==.Theiceflare:BAAANQADCggIHwAAAA==.Themuffinman:BAAANQAECgQIBwAAAA==.Theworrirawr:BAACNQAFFIEHAAIPAAQKhiFjAQCYAQAPAAQKhiFjAQCYAQA1AAQKgScAAw8ACQooJqwAAOsDAA8ACQooJqwAAOsDACIABQokHvIQAL8BAAAA.Thur:BAABNQAECoEbAAIRAAgKMRfEcgAaAgARAAgKMRfEcgAaAgAAAA==.Thänatos:BAAANQAECgIIAgAAAA==.',
Ti='Tiesci:BAABNQAECoEbAAICAAgKUSLTSgDdAgACAAgKUSLTSgDdAgAAAA==.Tinyclash:BAAANQADCgQIBAAAAA==.Tinypap:BAAANQADCggIFwAAAA==.Tippe:BAAANQAECgUIBQAAAA==.',
Tl='Tlálocx:BAAANQAECgUIDAAAAA==.',
To='Toastedblade:BAAANQAECgQJBwAAAA==.Toldyousoul:BAAANQAECgEIAgAAAA==.Tomatomage:BAAANQAECgUIBQAAAA==.Tonarui:BAAANQAECgIIAQABNQAECgYICwADAAAAAA==.Tonytots:BAAANQAECgQIBQAAAA==.Tottemakk:BAAANQADCgEIAQAAAA==.Toughshots:BAAANQADCgEIAQAAAA==.Toxenima:BAAANQAECgUIEQAAAA==.Toxiciti:BAAANQAECgYIDQAAAA==.',
Tr='Tramlaw:BAAANQADCgIIAgAAAA==.Trashedara:BAAANQADCgUIBQAAAA==.Treebirth:BAABNQAECoExAAMOAAkKwiPiCAAfAwAOAAkKwiPiCAAfAwANAAEKcQ1ungA4AAAAAA==.Treyu:BAAANQADCgYIBgAAAA==.Triegh:BAAANQAECgMIAwAAAA==.Trolljones:BAAANQADCgcICgAAAA==.Troyano:BAAANQADCgQIBAAAAA==.Trunder:BAABNQAECoEYAAIPAAcKxBYkFQDPAQAPAAcKxBYkFQDPAQAAAA==.Trush:BAAANQAECgMIAwAAAA==.',
Ts='Tsaindorcus:BAABNQAECoEdAAIbAAYKPAkCdQD9AAAbAAYKPAkCdQD9AAAAAA==.Tsunamyz:BAAANQAECgEIAQAAAA==.',
Tu='Tuskgwel:BAAANQADCgIIAQAAAA==.',
Ty='Tyfoon:BAAANQABCgIIAgAAAA==.',
Ud='Uders:BAAANQAECgYIEAAAAA==.',
Uh='Uhlvar:BAAANQAECgcICwAAAA==.Uhm:BAABNQAECoEaAAIKAAkKlyNDFQBbAwAKAAkKlyNDFQBbAwAAAA==.',
Ui='Uil:BAEANQAECgIIAgABNQAECgkJHgAWAB4UAA==.',
Ul='Ultramad:BAAANQAECgcJDQAAAA==.Ultramellow:BAAANQAECgEIAQABNQAECgcJDQADAAAAAA==.',
Un='Unclesquid:BAAANQADCggIEwAAAA==.Unholydubzzy:BAAANQADCgEIAQAAAA==.',
Up='Upngo:BAABNQAECoE0AAIKAAkKeiQYBwC1AwAKAAkKeiQYBwC1AwAAAA==.',
Ur='Urotherdaddy:BAAANQADCgEIAQABNQAECgEIAQADAAAAAA==.',
Us='Uskthyr:BAAANQAECgEIAgAAAA==.',
Uw='Uwuovo:BAAANQADCgcICAAAAA==.',
Va='Vanakin:BAAANQAECgQIBAABNQAFFAcIFwAaAIEcAA==.Vandredor:BAACNQAFFIEXAAIaAAcKgRztAQBsAgAaAAcKgRztAQBsAgA1AAQKgSMAAxoACQrmIeAVAM4CABoACQq4IeAVAM4CAB4ABgpaHGcNALgBAAAA.Varntrah:BAAANQADCgYICgAAAA==.Vastatio:BAAANQADCgEIAQAAAA==.Vasträ:BAAANQAECgEIAQAAAA==.',
Ve='Velicelia:BAABNQAECoEiAAMMAAgKQQsZRgBgAQAMAAcKXgsZRgBgAQAYAAEKdQoj0AAvAAAAAA==.Vesroth:BAAANQAECgYIEwAAAA==.',
Vi='Viborge:BAAANQADCggIEAAAAA==.View:BAABNQAECoElAAIQAAkKyiO/AACRAwAQAAkKyiO/AACRAwAAAA==.Vince:BAAANQAECgIIAgAAAA==.Vissra:BAAANQAECgQIBAABNQAECggIMAAUAMQaAA==.',
Vo='Vojak:BAAANQAECgUIBQAAAA==.',
Vu='Vulpermon:BAAANQADCgMIBAAAAA==.Vuly:BAAANQADCgEIAQAAAA==.',
['Vä']='Vääko:BAAANQAECgQICAAAAA==.',
['Ví']='Vínce:BAAANQADCgIIAgAAAA==.',
Wa='Waluigi:BAAANQADCggJCAABNQAECgYICwADAAAAAA==.Warbaby:BAAANQADCggIDwAAAA==.Warlarren:BAAANQADCggICQAAAA==.',
We='Weatherr:BAABNQAFFIEIAAMkAAQKWhPmEQA+AQAkAAQKWhPmEQA+AQAgAAEKcQmNHQBJAAAAAA==.Weki:BAAANQADCggIDAAAAA==.Wetshrimp:BAAANQAFFAMIAwAAAA==.',
Wh='Whippoorwill:BAABNQAECoEiAAMNAAgKTRboNgAMAgANAAgKDBToNgAMAgAiAAIKsBLuKACJAAAAAA==.Whiskyslayer:BAAANQAECggIEAAAAA==.Whosmofunky:BAAANQAECgQIBAAAAA==.',
Wi='Wickeda:BAAANQAECgQIBwAAAA==.Williamp:BAAANQADCgYICgAAAA==.',
Wn='Wntlmd:BAAANQAECgMIBQAAAA==.',
Wo='Wolfnacht:BAAANQAECgUIDQAAAA==.',
Wu='Wukangmei:BAAANQADCgMIAwAAAA==.',
['Wà']='Wàrødør:BAAANQAECgQIBQAAAA==.',
Xe='Xene:BAABNQAECoEYAAISAAUKnSC7aQCzAQASAAUKnSC7aQCzAQAAAA==.',
Xh='Xhade:BAAANQADCgIIAgABNQAECgQIBAADAAAAAA==.',
Xr='Xriss:BAAANQADCggIFwAAAA==.Xrs:BAAANQADCgUICAABNQAECgQICgADAAAAAA==.',
Ya='Yanedin:BAABNQAECoEoAAInAAkKjwZMFQBuAQAnAAkKjwZMFQBuAQAAAA==.Yathrr:BAAANQADCgYICwAAAA==.',
Yi='Yil:BAAANQABCgYIDAAAAA==.Yippeezippee:BAAANQABCgYICgAAAA==.',
Yo='Yorforger:BAAANQAECgQIBAABNQAECgkJHQARAFcYAA==.Youngbj:BAAANQAECgcICAABNQAECgcICwADAAAAAA==.Younger:BAAANQAECgEIAgAAAA==.Youngerxx:BAAANQADCgYIBgAAAA==.Youngerxz:BAAANQAECgMIAgAAAA==.',
Ys='Yserene:BAAANQADCggIFAAAAA==.',
Yu='Yukonícus:BAAANQAECgYIDAABNQAECgkJOgAaAF0jAA==.Yukonïcus:BAABNQAECoE6AAMaAAkKXSMTBQCXAwAaAAkKViMTBQCXAwAeAAUKaBsGDwCUAQAAAA==.Yumm:BAAANQADCgcIBwAAAA==.Yuridemo:BAAANQAECgcIDAAAAA==.',
['Yè']='Yènnefer:BAAANQADCggIGAAAAA==.',
Za='Zahir:BAAANQAFFAEIAQABNQAFFAcIDwACAMkaAA==.Zaldrena:BAAANQADCgYIBgAAAA==.Zanotgaming:BAAANQADCgcIBwAAAA==.Zaraydorine:BAAANQADCgUIBQAAAA==.',
Zb='Zbrickashaw:BAAANQAECgYIEgAAAA==.',
Ze='Zelrin:BAACNQAFFIENAAICAAUKYxs/FACsAQACAAUKYxs/FACsAQA1AAQKgSIAAgIACQpKGcFzAIACAAIACQpKGcFzAIACAAAA.Zenthalion:BAAANQAECgEIAgAAAA==.',
Zi='Ziggyzags:BAAANQADCgcIBwAAAA==.Zippee:BAAANQADCgQIBAAAAA==.',
Zo='Zobi:BAAANQADCgMIAwAAAA==.Zoomhunt:BAACNQAFFIEOAAMGAAUK1x2yBwCoAQAGAAUK1x2yBwCoAQAEAAEKeBRQLgBOAAA1AAQKgRYAAwYACArYHfsWAIsCAAYACAqtHPsWAIsCAAQAAQqWIxAhAWEAAAAA.Zoommage:BAABNQAECoEbAAICAAkKKSCIQQDzAgACAAkKKSCIQQDzAgABNQAFFAUIDgAGANcdAA==.',
Zu='Zuluugargorg:BAAANQAECgUICgAAAA==.',
Zy='Zyrun:BAAANQADCgQIBAAAAA==.',
['Ãd']='Ãdaria:BAAANQADCgIIAgAAAA==.',
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
