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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Unknown-Unknown','Rogue-Assassination','Rogue-Outlaw','Priest-Holy','Shaman-Restoration','Druid-Guardian','Mage-Arcane','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Retribution','Warrior-Arms','Evoker-Preservation','Monk-Windwalker','Priest-Shadow','Druid-Feral','Monk-Brewmaster','Mage-Frost','Evoker-Devastation','Warlock-Affliction','Warrior-Fury','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Shaman-Elemental','Paladin-Protection','Priest-Discipline','Shaman-Enhancement','Rogue-Subtlety','Paladin-Holy','Druid-Balance','Warrior-Protection','Evoker-Augmentation','DemonHunter-Vengeance',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Aceieus:BAAANQABCgUIBQAAAA==.Achelis:BAABNQAECn8lAAMBAAgKFSSSAQBNAwABAAgKFSSSAQBNAwACAAEKlhK3fwBBAAAAAA==.',
Ad='Adorian:BAAANQAECgIIAgAAAA==.Adros:BAAANQADCggJEAAAAA==.Adrrel:BAAANQADCgYIBgABNQAFFAUICgADAJcTAA==.Adrrelle:BAACNQAFFH8KAAMDAAUKlxOsEQBAAQADAAQK+BasEQBAAQACAAIKegYnHwB1AAA1AAQKfyUAAwIACQpTH9UnAAgCAAIACArNGtUnAAgCAAMABAq0HZXeAD4BAAAA.',
Ae='Aelfwine:BAAANQAECgUICgAAAA==.',
Ai='Ailaith:BAABNQAECn8eAAMDAAgKfyIpJQAAAwADAAgKfyIpJQAAAwACAAIKAADpeABYAAAAAA==.',
Ak='Akariliselle:BAABNQAECn8xAAMEAAgKICI8CQBlAgAEAAcKsRs8CQBlAgAFAAYKRCFDXAA/AgAAAA==.',
Al='Al:BAAANQADCgYIBgAAAA==.Alakn:BAAANQAECgEIAQABNQAECgUIBQAGAAAAAA==.Alan:BAAANQAECgUIBQAAAA==.Albatross:BAAANQADCgYICgAAAA==.Alcun:BAAANQADCgYIBwABNQAECgUIBQAGAAAAAA==.Alein:BAAANQADCgEIAQABNQAECgUIBQAGAAAAAA==.Alluriel:BAAANQAECgYICgABNQAECgUICgAGAAAAAA==.Alydrostage:BAAANQAECgUIEQAAAA==.Alystriaz:BAAANQAECgQIDAAAAA==.Alzheimerz:BAABNQAECn8oAAMHAAgK/CHQDAAcAwAHAAgK/CHQDAAcAwAIAAIKZBe5FgB4AAAAAA==.',
Am='Amaelalin:BAABNQAECn8eAAIJAAgKUwmwfwCUAQAJAAgKUwmwfwCUAQAAAA==.Amatoria:BAAANQAECgUIDAAAAA==.',
An='Anaralyth:BAAANQADCgUICQABNQAFFAEIAQAGAAAAAA==.Andaya:BAABNQAECn8fAAIKAAkKexuFKgC3AgAKAAkKexuFKgC3AgAAAA==.Andemeli:BAAANQAECgUIDAAAAA==.Andrewrynn:BAAANQADCgEIAQAAAA==.Annarah:BAAANQAECgIIAwAAAA==.',
Ar='Arandis:BAAANQAECgYIEgAAAA==.Arcianna:BAABNQAECn8eAAILAAkKjh3qBgAaAwALAAkKjh3qBgAaAwAAAA==.Arctica:BAAANQAECgUIDgAAAA==.Arjurn:BAABNQAECn8lAAIMAAgK7xz2bwCeAgAMAAgK7xz2bwCeAgAAAA==.Arlyndra:BAAANQADCgQIBAAAAA==.Armpitbutter:BAABNQAECn8nAAINAAgKMyWeBABaAwANAAgKMyWeBABaAwAAAA==.Artymiss:BAAANQAECgUICgAAAA==.',
As='Asherah:BAAANQAECgEIAQAAAA==.Astraleth:BAAANQAFFAEIAQAAAA==.',
Au='Autry:BAAANQADCgEIAQAAAA==.',
Av='Avocat:BAABNQAECn8aAAIDAAcKPBzGYABSAgADAAcKPBzGYABSAgAAAA==.',
Ay='Ayorana:BAAANQADCggIEAAAAA==.',
Az='Azshura:BAAANQAECgEIAQAAAA==.Azzinôth:BAABNQAECn8xAAMOAAkKKBFhMQAaAgAOAAkK3hBhMQAaAgAPAAcKpg40OAB9AQAAAA==.',
Ba='Baldr:BAABNQAECn8bAAIQAAgKxgk7wgCSAQAQAAgKxgk7wgCSAQAAAA==.Balgar:BAAANQAECgYIDAAAAA==.Bammz:BAABNQAECn8qAAIRAAgKniIIPADUAgARAAgKniIIPADUAgABNQAFFAEIAQAGAAAAAA==.Bastia:BAAANQADCgYIEwAAAA==.Baumstrum:BAAANQADCgcIDAAAAA==.',
Be='Beltbuckle:BAAANQADCgMIBAABNQADCgUICQAGAAAAAA==.Belvkara:BAAANQADCgEIAQAAAA==.Benbeckman:BAAANQAECgcIEQAAAA==.',
Bi='Bigtbag:BAAANQADCgUIBwAAAA==.',
Bl='Bloodrayvn:BAABNQAECn8VAAIDAAgKbxf7VABwAgADAAgKbxf7VABwAgAAAA==.Bloodytusks:BAAANQADCggIFgAAAA==.',
Bo='Boomchick:BAAANQADCggICAABNQAECgIIBAAGAAAAAA==.Borrkbuster:BAAANQAECgQICwAAAA==.',
Br='Brenri:BAAANQAECgMIBAAAAA==.Brewtality:BAAANQAECgQIBAABNQAFFAIIBQASAIsOAA==.Brudanature:BAAANQADCgUIBQABNQAECgQICAAGAAAAAA==.Brughe:BAAANQAECgcIDwAAAA==.Brywynn:BAAANQADCggIFAABNQAECgUIDAAGAAAAAA==.',
Bu='Bubbleoseven:BAAANQAECgYIEQABNQAFFAIIBQASAIsOAA==.Burnbabyburn:BAAANQAECggIEAAAAA==.Burntbum:BAAANQADCggICAABNQAECgYIEQAGAAAAAA==.Buttacutta:BAAANQADCggIJgAAAA==.',
Ca='Cahoots:BAABNQAECn8mAAITAAkK4R7eDQD9AgATAAkK4R7eDQD9AgAAAA==.Caneste:BAACNQAFFH8JAAIUAAQKCxEjCwA4AQAUAAQKCxEjCwA4AQA1AAQKfycAAhQACQodIv0IAEsDABQACQodIv0IAEsDAAAA.Capela:BAAANQAECgEIAQAAAA==.Catty:BAABNQAECn8hAAIVAAcKEBaBEQDmAQAVAAcKEBaBEQDmAQAAAA==.Cayleynne:BAABNQAECn8ZAAIWAAkKFB/1BAAYAwAWAAkKFB/1BAAYAwAAAA==.',
Ce='Celestyl:BAAANQAECgIIBgAAAA==.',
Ch='Chadman:BAAANQADCgYIBgAAAA==.Chamadel:BAAANQADCgMIAwAAAA==.Chara:BAAANQAECgEIAQAAAA==.Cheapbeerz:BAABNQAECn8bAAMXAAgKUAbyGQAjAQAXAAcKPgbyGQAjAQAMAAcKeAKcRAEXAQAAAA==.Cheesemon:BAAANQADCgUIBQAAAA==.Chiforged:BAAANQAECgQICAAAAA==.Chromstrasza:BAABNQAECn8kAAIYAAkKVQ+WEwATAgAYAAkKVQ+WEwATAgAAAA==.',
Ci='Cindersmoke:BAAANQADCgMIAwAAAA==.Cinnia:BAABNQAECn8eAAMFAAcKbhGAjADCAQAFAAcKbhGAjADCAQAZAAEKAACoMQAwAAAAAA==.',
Co='Comitus:BAABNQAECn8dAAIRAAgKfgU5zQBUAQARAAgKfgU5zQBUAQAAAA==.Conj:BAAANQAECgQIBAAAAA==.Conjarr:BAABNQAECn8jAAIJAAgK3xu/OgB7AgAJAAgK3xu/OgB7AgAAAA==.Cooters:BAAANQADCgQIBAABNQAECggIHAAaAMkbAA==.Cotournix:BAAANQADCgcIBwAAAA==.Cougardk:BAAANQAECgEIAQAAAA==.Cougarsixsix:BAAANQAECgIIBgAAAA==.',
Cr='Crabcarbs:BAAANQADCgUICQAAAA==.Crazydrake:BAAANQADCgEIAQAAAA==.Creideam:BAAANQADCgcJBwAAAA==.Crimos:BAABNQAECn8nAAIbAAgKhg9YVwCwAQAbAAgKhg9YVwCwAQAAAA==.Crypticcurse:BAAANQADCgcIJgAAAA==.',
Cy='Cynnai:BAABNQAECn8YAAIRAAcKTxpPkwDnAQARAAcKTxpPkwDnAQAAAA==.',
Da='Daeghrefn:BAAANQADCgYIBgABNQAECgUIBwAGAAAAAA==.Daerthor:BAAANQADCgYJCQABNQAECgUICQAGAAAAAA==.Dalora:BAAANQADCggIDAAAAA==.Damaclies:BAABNQAECn8eAAMFAAgKxg30tgBbAQAFAAYKBA30tgBbAQAEAAMKiQuaSAClAAAAAA==.Danashal:BAABNQAECn8eAAISAAcKDAKrNwDTAAASAAcKDAKrNwDTAAAAAA==.Dangerranger:BAAANQAECgIIAwAAAA==.Dansen:BAAANQADCgUIBQAAAA==.Darkspanner:BAAANQADCgQIBAAAAA==.Darksyn:BAAANQAECgUIBQAAAA==.Darrth:BAABNQAECn8ZAAMcAAcK2BRjNwD0AQAcAAcK2BRjNwD0AQAdAAEK2AN30QAqAAAAAA==.Darthbane:BAAANQAECgUIDQAAAA==.Darthjareth:BAAANQADCgYICQAAAA==.Darude:BAAANQADCgUIBQABNQADCgUICQAGAAAAAA==.Dattiffany:BAAANQAECgIIAwAAAA==.',
De='Deathsyn:BAAANQADCgQIBAABNQAECgUIBQAGAAAAAA==.Dekkan:BAAANQAECgQICAAAAA==.Delphyne:BAABNQAECn8aAAMJAAcKMBq7TgA0AgAJAAcKMBq7TgA0AgAUAAUKSgOVXQCIAAAAAA==.Demontator:BAAANQADCggICAABNQAECgYIEQAGAAAAAA==.Denasel:BAAANQADCgcIBwAAAA==.Denwarenji:BAABNQAECn8aAAIeAAgKYxYCXQAIAgAeAAgKYxYCXQAIAgAAAA==.Desmádre:BAABNQAECn8aAAMbAAcKPxySQAAYAgAbAAcKNhuSQAAYAgAdAAYKBxutTQC8AQAAAA==.',
Di='Dia:BAAANQADCgQIBAAAAA==.Diabetto:BAAANQABCgYICQAAAA==.Diend:BAABNQAECn8gAAMKAAgKLSIGGQAMAwAKAAgKLSIGGQAMAwAeAAEKAAAeOwEuAAAAAA==.Dillathis:BAAANQADCgMJAwAAAA==.Dissonanita:BAAANQADCgUICQAAAA==.',
Dj='Djthelock:BAAANQAECgYICQAAAA==.',
Do='Doctachris:BAAANQABCgUICQAAAA==.Domodios:BAAANQADCgYIBgABNQAECgUICwAGAAAAAA==.',
Dr='Dravenpryde:BAABNQAECn8aAAIKAAgKgQrffgCLAQAKAAgKgQrffgCLAQABNQAECgkJJAALADkdAA==.Drbrad:BAAANQAECgQIBAAAAA==.Dreadfists:BAABNQAECn8YAAIcAAgKiRIIOADwAQAcAAgKiRIIOADwAQAAAA==.Druen:BAABNQAECn8eAAIVAAkKaBo2BwDrAgAVAAkKaBo2BwDrAgAAAA==.Drunkenpo:BAABNQAECn8gAAIWAAgKgyC1BQD+AgAWAAgKgyC1BQD+AgAAAA==.Drunkxdemon:BAAANQAECgQIBwAAAA==.Drunkxhunter:BAAANQADCgMIBQAAAA==.Drunkxmonk:BAABNQAECn8WAAITAAkKVxvOFwCHAgATAAkKVxvOFwCHAgAAAA==.Drykin:BAAANQADCgYIBgAAAA==.Drïzl:BAEBNQAECn8ZAAMeAAgKmBhORABhAgAeAAgKmBhORABhAgAKAAEKQwa1GwEwAAABNQAFFAIIBQAHAIMeAA==.',
Du='Duckchow:BAAANQADCgIIAgAAAA==.',
Dw='Dwarfoo:BAAANQAECgMIBwAAAA==.Dweñde:BAABNQAECn8fAAIFAAcK4g8RlwCnAQAFAAcK4g8RlwCnAQAAAA==.',
Eb='Ebonfang:BAAANQABCgEIAQAAAA==.',
Ec='Ecthelion:BAAANQAECgQIBQAAAA==.',
Ed='Eddrick:BAABNQAECn8VAAMQAAgKLBcTrwC7AQAQAAcKShUTrwC7AQAfAAIKNxhfUwCSAAAAAA==.Edrid:BAAANQAECgYIEAABNQAFFAUIDgASACocAA==.',
Ei='Eirwen:BAAANQABCgIIAgAAAA==.',
El='Elîsha:BAAANQADCgUIBwAAAA==.',
En='Engo:BAABNQAECn8qAAIgAAgKyyNjAQA/AwAgAAgKyyNjAQA/AwAAAA==.',
Er='Eradrá:BAAANQAECgIIBAAAAA==.Eragon:BAAANQAECgYIDQAAAA==.',
Et='Ethaan:BAAANQABCgQIBAAAAA==.',
Eu='Eureka:BAAANQAECggIDwAAAA==.',
Ev='Evandra:BAAANQAECgYIDQAAAA==.Evanorah:BAAANQAECgUICgAAAA==.',
Fa='Faedeyeda:BAAANQAECgQIBAAAAA==.',
Fe='Ferheim:BAAANQADCgQJBAAAAA==.Ferhold:BAAANQADCgIIAgAAAA==.',
Fi='Fiddyone:BAAANQADCgUIBQABNQAECggIHAAhAKAZAA==.Figment:BAAANQADCgMIAwAAAA==.Firered:BAAANQADCgIIBAABNQAECgMIBgAGAAAAAA==.Fizzfuzzbttm:BAAANQAECgEJAQAAAA==.',
Fo='Fodurzin:BAAANQAECgEJAQABNQAECgYIDQAGAAAAAA==.',
Fr='Frojio:BAAANQAECggIEgAAAA==.Frosten:BAAANQADCggIMwAAAA==.',
Fu='Furenio:BAAANQADCgYIBgAAAA==.',
Ga='Gabaghoul:BAAANQAECgIIAwAAAA==.Gaff:BAABNQAECn8XAAIRAAYKlBewrACoAQARAAYKlBewrACoAQAAAA==.Gatekeeper:BAAANQADCgUIBQAAAA==.',
Ge='Georgiana:BAAANQABCgIIAgAAAA==.',
Gr='Grauth:BAAANQADCgUICgAAAA==.Grido:BAAANQADCgYICAAAAA==.',
Gu='Gulishdaniel:BAAANQADCgcIDQABNQAFFAQICQAUAAsRAA==.',
Ha='Hadin:BAABNQAECn8bAAIMAAgKWh0KYAC/AgAMAAgKWh0KYAC/AgAAAA==.Halalnt:BAAANQAECgUIBwAAAA==.Hamplanet:BAAANQAECgQIBAABNQAECgkJGQAXAGkaAA==.Hamster:BAAANQADCgYIBgABNQAFFAIIAgAGAAAAAA==.Hanu:BAAANQABCggIDAAAAA==.Haozhao:BAABNQAECn8gAAILAAgKGhelEwAjAgALAAgKGhelEwAjAgAAAA==.Harsaiah:BAAANQADCgYICAABNQAECgUIDAAGAAAAAA==.Hazenpryde:BAABNQAECn8kAAILAAkKOR0FCQDkAgALAAkKOR0FCQDkAgAAAA==.',
He='Healicious:BAAANQADCgcIDgAAAA==.Hearsay:BAAANQADCggIGQABNQAECgUIDgAGAAAAAA==.Hecatamu:BAAANQADCgUIBQAAAA==.Hephaistian:BAABNQAECn8kAAIDAAkKFBRtUgB2AgADAAkKFBRtUgB2AgAAAA==.',
Ho='Holytoe:BAAANQADCgYIBgAAAA==.Howlears:BAAANQADCgIIAgAAAA==.',
Hu='Hulud:BAABNQAECn8XAAIFAAgKkhdYaQAdAgAFAAgKkhdYaQAdAgAAAA==.',
Hy='Hysgar:BAAANQAECgUICgABNQAECgUIDAAGAAAAAA==.',
Ic='Icetiger:BAAANQADCgEIAQAAAA==.',
Ie='Iechu:BAAANQAECgEJAQAAAA==.',
Il='Illidaz:BAAANQADCgUIBgAAAA==.',
Im='Immortál:BAABNQAECn8bAAMUAAgKpx5aLQC3AQAUAAYKZhxaLQC3AQAJAAUKghaNmABGAQAAAA==.',
In='Indraz:BAAANQADCgQIBAAAAA==.Infinìte:BAABNQAECn8lAAIRAAgKVhumWgB5AgARAAgKVhumWgB5AgAAAA==.Inic:BAAANQABCgQJBQAAAA==.Inix:BAAANQABCgIIAgAAAA==.',
Is='Isildur:BAAANQADCgEIAQAAAA==.',
Iv='Ivysnow:BAAANQAECgIIAgAAAA==.',
Ja='Jackfruit:BAAANQAECgYIDwAAAA==.Jaod:BAAANQADCgYIFgAAAA==.',
Jd='Jdghoul:BAAANQADCgYIBgAAAA==.',
Ji='Jindrac:BAAANQADCggIEQAAAA==.Jitsuru:BAAANQADCggICgAAAA==.',
Ju='Juanfiles:BAAANQABCgQIAwAAAA==.',
['Jà']='Jàcaranda:BAAANQADCgMIAwAAAA==.',
Ka='Kahnrah:BAAANQADCggILAAAAA==.Kalarae:BAAANQAECgUICQAAAA==.Kaljeer:BAABNQAECn8YAAIiAAcK5hXWGwDzAQAiAAcK5hXWGwDzAQAAAA==.Kalki:BAAANQADCgEIAQAAAA==.Kaltharion:BAAANQAECgEIAQAAAA==.Kaluren:BAACNQAFFH8OAAIjAAUKyyCACADWAQAjAAUKyyCACADWAQA1AAQKfyoAAyMACQqtJiQBAOEDACMACQqtJiQBAOEDABAABQosIDvfAFYBAAAA.Kalurion:BAAANQADCgIIAgAAAA==.Kanade:BAABNQAECn8XAAMFAAgK5Ay2mACjAQAFAAgKfQq2mACjAQAEAAIKrw/2WAB0AAAAAA==.Kanishi:BAAANQABCggIDAAAAA==.Kantong:BAABNQAECn8gAAIWAAgKCCTHAwBLAwAWAAgKCCTHAwBLAwAAAA==.Kapp:BAAANQAECgUICQAAAA==.Karabar:BAABNQAECn8lAAIfAAgK8B6RDgCwAgAfAAgK8B6RDgCwAgAAAA==.Karnnaged:BAAANQAECgMIBgABNQAECgQIBQAGAAAAAA==.Karnnagex:BAAANQAECgQIBQAAAA==.Karnnagexx:BAAANQADCgQJBAABNQAECgQIBQAGAAAAAA==.Karnnagexxl:BAAANQAECgMIAwABNQAECgQIBQAGAAAAAA==.Kasarra:BAAANQAECgQIBgAAAA==.Kayiku:BAAANQADCggIFAAAAA==.Kazagol:BAABNQAECn8lAAIPAAgKQRoTHAByAgAPAAgKQRoTHAByAgAAAA==.',
Kh='Khamaracy:BAAANQAECgMIBwAAAA==.',
Ki='Kimahrí:BAAANQADCgcIBwAAAA==.',
Ko='Kojote:BAAANQADCgMIBgAAAA==.Kovalenko:BAABNQAECn8VAAIQAAgKdhY1ggAfAgAQAAgKdhY1ggAfAgAAAA==.',
Kr='Kryptus:BAABNQAECn8cAAIMAAcKexvIpQA1AgAMAAcKexvIpQA1AgAAAA==.',
Ku='Kurick:BAAANQAECgUIDAAAAA==.Kurshak:BAABNQAECn8iAAIkAAgK0hbVNAA/AgAkAAgK0hbVNAA/AgAAAA==.',
Ky='Kyngizzard:BAAANQAECgMIBgABNQAECgUIBwAGAAAAAA==.',
La='Latte:BAAANQAECgUIDAAAAA==.',
Le='Lenity:BAABNQAECn8bAAIiAAYKggxzLABaAQAiAAYKggxzLABaAQAAAA==.',
Lo='Loan:BAAANQADCggIFgABNQAFFAIIAgAGAAAAAA==.Lockstar:BAAANQADCgYIBgAAAA==.Lokinah:BAAANQAECgUIDAAAAA==.',
Lu='Lucoryphus:BAAANQAECgUIBwAAAA==.Lukeduke:BAACNQAFFH8OAAIlAAUKnxwhAgCJAQAlAAUKnxwhAgCJAQA1AAQKfycAAiUACQrKI/sDAFADACUACQrKI/sDAFADAAAA.Luketheduke:BAAANQAECgMIAwABNQAFFAUIDgAlAJ8cAA==.Lunaries:BAAANQAECgEIAQAAAA==.Lunä:BAAANQAFFAEIAQAAAA==.',
Ly='Lydia:BAABNQAECn8jAAMMAAgKWhnewAABAgAMAAcK5RbewAABAgAXAAIKexs2KwCdAAAAAA==.Lyleath:BAAANQADCgYICgABNQAECgUICgAGAAAAAA==.',
['Lú']='Lúthien:BAAANQAECgEIAQAAAA==.',
Ma='Malcontent:BAAANQAECgMIAwABNQAECgUICwAGAAAAAA==.Malfeasance:BAAANQADCgUIBQABNQAECgUICwAGAAAAAA==.Malifel:BAAANQAECgUICwAAAA==.Mallord:BAAANQAECgQIBAABNQAECgUICwAGAAAAAA==.Malstrom:BAAANQAECgIIBAABNQAECgUICwAGAAAAAA==.Mandarin:BAAANQAECgcIDwAAAA==.Mararose:BAAANQABCgIIBAAAAA==.Marashades:BAAANQAECgYIDAAAAA==.Marsali:BAAANQADCgcICgAAAA==.',
Me='Melabrin:BAAANQAECgYIEgAAAA==.Mercia:BAABNQAECn8bAAIfAAgKEB57DwCjAgAfAAgKEB57DwCjAgAAAA==.Mercý:BAAANQADCggIGAAAAA==.Merekoma:BAABNQAECn8VAAIPAAcKexjqKQDvAQAPAAcKexjqKQDvAQAAAA==.',
Mi='Mieena:BAAANQABCgQIBAAAAA==.Milhouse:BAAANQAECgEIAwAAAA==.Mingonashoba:BAAANQAECgEIAwAAAA==.Miragosa:BAAANQADCgQIBAAAAA==.Misschris:BAAANQAECgYIDQAAAA==.Mistaricky:BAAANQAECgYIDQAAAA==.',
Mo='Moadeed:BAAANQAECgUICgAAAA==.Morassabe:BAAANQADCgcIBwAAAA==.Morphmious:BAABNQAECn8pAAIVAAgK6xjlCgCDAgAVAAgK6xjlCgCDAgAAAA==.Mortesque:BAAANQAECgQICgAAAA==.',
Mu='Muffinz:BAAANQADCgcIEAAAAA==.Muttblitzed:BAAANQAECgUICQAAAA==.',
My='Myroku:BAAANQABCgMIAwABNQAECgUICwAGAAAAAA==.Myrrh:BAABNQAECn8mAAISAAkKgwaVJACaAQASAAkKgwaVJACaAQAAAA==.Mysklef:BAAANQADCgMJAwABNQAECgUIDAAGAAAAAA==.Mythrandyl:BAAANQADCgYIBgAAAA==.',
['Mí']='Místermage:BAAANQAECgQJCAAAAA==.',
['Mô']='Môses:BAAANQADCgMIBQAAAA==.',
Na='Naidia:BAAANQAECgQIBAABNQAECgUICgAGAAAAAA==.Nausican:BAAANQADCgUIBgAAAA==.',
Ne='Necrogue:BAAANQADCgIIAgABNQAECggIFgAKAEUgAA==.Necrosector:BAABNQAECn8dAAIQAAgKkBksYgBwAgAQAAgKkBksYgBwAgAAAA==.Nelandra:BAAANQAECgIIBAAAAA==.Neongrasp:BAAANQAECgcIDgAAAA==.Nerazlyn:BAAANQADCgMIAwAAAA==.',
Ni='Nickflare:BAAANQAECgIIAgAAAA==.Ninelives:BAAANQADCgYIBgAAAA==.Ninjadk:BAEANQAECgIIAgABNQAFFAIIBQAHAIMeAA==.',
No='Nomahuata:BAABNQAECn8rAAIeAAgKjw7RZgDoAQAeAAgKjw7RZgDoAQAAAA==.',
Nu='Nufrus:BAAANQAECgYIDAAAAA==.Nurgle:BAAANQADCgUICQAAAA==.',
Ny='Nyeli:BAAANQAECgUIDAAAAA==.Nyxi:BAAANQAECgUICgAAAA==.',
['Né']='Néo:BAAANQAECgIIAgAAAA==.',
Om='Ommeta:BAAANQAFFAMIAwAAAA==.',
On='Onefiftyone:BAABNQAECn8cAAQhAAgKoBkqDwB1AgAhAAgKoBkqDwB1AgAKAAQK5hmppwAfAQAeAAEKAACmOAEvAAAAAA==.',
Pa='Palochka:BAAANQAECgQICgAAAA==.Palpetine:BAAANQADCgYIFAAAAA==.Paltator:BAAANQAECgYIEQAAAA==.Pandazuken:BAABNQAECn8jAAIeAAgK0RqCRQBdAgAeAAgK0RqCRQBdAgAAAA==.Paradots:BAACNQAFFH8FAAISAAIKiw69FACEAAASAAIKiw69FACEAAA1AAQKfywAAhIACQpJG6MOAL0CABIACQpJG6MOAL0CAAAA.Paranitis:BAAANQADCggJCAAAAA==.Paraparaboom:BAABNQAECn8cAAIaAAgKyRvJBQC8AgAaAAgKyRvJBQC8AgAAAA==.',
Ph='Phatboi:BAAANQADCgQIBAAAAA==.Pheroth:BAAANQADCgYIDAABNQAECgUIBQAGAAAAAA==.',
Pi='Pixpax:BAAANQAECgYICwAAAA==.Pixyofdeath:BAAANQAECggIAQAAAA==.Pixystix:BAAANQAECgIIBgABNQAECggIAQAGAAAAAA==.',
Po='Pomortem:BAAANQAECgQICAAAAA==.Potsomancy:BAACNQAFFH8MAAIMAAYK1Rp3DgD/AQAMAAYK1Rp3DgD/AQA1AAQKfx8AAgwACQokJCJIAPICAAwACQokJCJIAPICAAAA.',
Pr='Profian:BAAANQADCgcIBwAAAA==.',
Ps='Psyberx:BAAANQAECggICQAAAA==.',
Ra='Radioshack:BAAANQADCgUIBQABNQAECgQIBAAGAAAAAA==.Raivel:BAAANQAECgMIBwABNQAECgUIDAAGAAAAAA==.Rambogg:BAAANQADCgMIAwABNQAFFAUIDgAMABsNAA==.Raneyth:BAAANQAECgUICgAAAA==.Ranoku:BAAANQADCggIDQAAAA==.Ravagèr:BAAANQADCggICgABNQAECgkJMQAOACgRAA==.Ravusternath:BAAANQADCgcIDQAAAA==.',
Re='Redwinetoast:BAAANQAECgQIBgAAAA==.Reignblade:BAAANQABCgIIAwAAAA==.Reno:BAABNQAECn8eAAQYAAcKPhrYGAC5AQAYAAYKNxfYGAC5AQASAAMKOg/0PgCjAAAmAAEKAACHJAAxAAABNQAFFAIIAgAGAAAAAA==.Reposess:BAAANQABCggIEgAAAA==.Reshyk:BAAANQAECgQIBAAAAA==.',
Rh='Rhobes:BAAANQADCggIHAAAAA==.Rhondta:BAAANQADCgEIAQAAAA==.',
Ri='Rickkrolled:BAAANQAECgEIAQAAAA==.Riordaa:BAAANQAECgYIDQAAAA==.Ripandtear:BAAANQADCgEIAQAAAA==.',
Ro='Roboskritch:BAAANQADCgUJBwABNQADCgUICQAGAAAAAA==.Roniston:BAAANQADCgQIBAAAAA==.Rowene:BAAANQADCgYIFgAAAA==.',
Ru='Rumor:BAAANQAECgUIDgAAAA==.Rurry:BAACNQAFFH8OAAISAAUKKhydCACsAQASAAUKKhydCACsAQA1AAQKfyYAAxIACQqQI8IDAHgDABIACQqQI8IDAHgDABgAAQohJWs0AGYAAAAA.',
Ry='Ryuuki:BAABNQAECn8lAAMbAAgKgCJaFAAUAwAbAAgKgCJaFAAUAwAdAAIKMgq8uABTAAAAAA==.',
['Rï']='Rïzzler:BAECNQAFFH8FAAIHAAIKgx5EEwCsAAAHAAIKgx5EEwCsAAA1AAQKfykAAwcACQqZIoAGAGcDAAcACQqZIoAGAGcDACIABgoHEmQpAHUBAAAA.',
Sa='Safetysham:BAAANQADCgcICwAAAA==.Saffia:BAAANQABCgUIBAAAAA==.Saleos:BAAANQADCgYJBgAAAA==.Sall:BAAANQADCgQIBAABNQADCgUICQAGAAAAAA==.Salmoo:BAAANQAECgYIDQAAAA==.Saltytator:BAAANQAECgMIBQABNQAECgYIEQAGAAAAAA==.Santhon:BAAANQADCgQIBAAAAA==.Sathariel:BAAANQADCgUIBQAAAA==.Savonah:BAAANQADCggIKAAAAA==.',
Sc='Scaledaddy:BAABNQAECn8bAAMmAAgKjwsmDACUAQAmAAgKjwsmDACUAQAYAAMKdQhtMQCDAAAAAA==.Scallion:BAAANQADCggICwABNQAECggIJQABABUkAA==.Scaryl:BAAANQAECgUIDgAAAA==.Schneè:BAABNQAECn8uAAIlAAkKpRKsEwDoAQAlAAkKpRKsEwDoAQAAAA==.Scoom:BAACNQAFFH8OAAIMAAUK5hwAGgClAQAMAAUK5hwAGgClAQA1AAQKfy8AAgwACQoFJSoZAHADAAwACQoFJSoZAHADAAAA.Scourgespawn:BAACNQAFFH8LAAMcAAUKlhlTBwB+AQAcAAUKlhlTBwB+AQAbAAEKAACCIwA9AAA1AAQKfyoAAxwACQoeJFkQAAoDABwACQoeJFkQAAoDABsABAogEXOXAM4AAAAA.',
Se='Seikyo:BAABNQAECn8lAAIdAAgK9QynVwCRAQAdAAgK9QynVwCRAQAAAA==.Seilah:BAAANQADCgUIBwABNQAECgUIBwAGAAAAAA==.Selenë:BAAANQAECgUIBgAAAA==.Serok:BAAANQAECgcIEAAAAA==.',
Sh='Shadowbox:BAAANQADCgMIAwAAAA==.Shadyaf:BAAANQAECgcICgAAAA==.Shailora:BAAANQADCgQIBAABNQADCgQIBAAGAAAAAA==.Shalis:BAAANQAECgYIBgAAAA==.Sharivee:BAAANQAECgUICwAAAA==.Shazamir:BAAANQAECgUIEQAAAA==.Shibui:BAABNQAECn8gAAIOAAgKyg83OgDeAQAOAAgKyg83OgDeAQAAAA==.Shifthead:BAABNQAECn8qAAMVAAkKThh2DQBBAgAVAAgKABl2DQBBAgAkAAkKahAKOQAjAgABNQAFFAMIAwAGAAAAAA==.Shockazilla:BAABNQAECn8dAAIjAAgKMCF+HAAAAwAjAAgKMCF+HAAAAwAAAA==.Shortspanky:BAAANQAECgQICAAAAA==.',
Si='Silaveen:BAAANQABCgIIAgAAAA==.Silverhorn:BAAANQAECgUIEQAAAA==.',
Sk='Skoduh:BAAANQAECgQICAAAAA==.',
Sl='Slack:BAAANQAECgUICwABNQAFFAIIAgAGAAAAAA==.Sluggo:BAACNQAFFH8MAAIQAAUK3xEhDACDAQAQAAUK3xEhDACDAQA1AAQKfyYAAhAACQrUIKNRAJ0CABAACQrUIKNRAJ0CAAAA.',
Sm='Smokeü:BAAANQADCggIDQAAAA==.',
So='Solinaara:BAAANQAECgEIAQAAAA==.Soraka:BAAANQAECgEIAQAAAA==.',
Sp='Spiralist:BAAANQAECgQIBQAAAA==.',
St='Stonedalways:BAAANQAECgUICgAAAA==.Stonytoni:BAAANQAECgEIAQAAAA==.',
Su='Sudokumyself:BAAANQADCgEIAQAAAA==.Sunfuri:BAAANQAECgcIEQAAAA==.Sus:BAACNQAFFH8NAAIOAAUKXBSXCgB1AQAOAAUKXBSXCgB1AQA1AAQKfyYAAw4ACQrKIoIZAMsCAA4ACQrKIoIZAMsCACcABAp1C9chALAAAAAA.Susanoo:BAAANQAECgYIBgAAAA==.',
Ta='Taalia:BAAANQAECgMIBwAAAA==.Talonas:BAAANQAECgIIAgAAAA==.Tarathor:BAAANQAECgMIBwAAAA==.Tatortott:BAAANQAECgQIBAABNQAECgYIEQAGAAAAAA==.',
Te='Teknofarious:BAAANQAECgYIEgAAAA==.',
Th='Thesafe:BAAANQAECgYIDQAAAA==.Thessara:BAAANQAECgMIAwAAAA==.Thevin:BAAANQAFFAIIAgAAAA==.Thialaa:BAAANQAECgIIAwABNQAECggIHgADAH8iAA==.Thialia:BAABNQAECn8ZAAIJAAYKFQ+smgBAAQAJAAYKFQ+smgBAAQABNQAECggIHgADAH8iAA==.Thialiaa:BAAANQADCgYIBgABNQAECggIHgADAH8iAA==.Thialiadin:BAAANQAECgUICQABNQAECggIHgADAH8iAA==.Thickems:BAAANQAECgYIDwAAAA==.Thoralon:BAAANQAECgIIAgAAAA==.Thorgrumn:BAAANQADCgIIAgAAAA==.',
Ti='Tinkabella:BAABNQAECn8lAAIgAAgKAx2SAwCuAgAgAAgKAx2SAwCuAgAAAA==.Tizl:BAEANQAECgIIAgABNQAFFAIIBQAHAIMeAA==.',
To='Torrey:BAAANQADCgIIAgAAAA==.',
Tr='Trek:BAAANQAECgUICwAAAA==.Trema:BAABNQAECn8pAAMfAAgKgBvLFABaAgAfAAcKRh7LFABaAgAQAAgKgQtxtQCtAQAAAA==.Trialei:BAAANQABCgIIAgAAAA==.Trick:BAAANQADCgIIAgABNQAECgkJMQAVAGslAA==.Trix:BAAANQADCggIFgAAAA==.',
Ts='Tserendelgor:BAAANQAECgUICwABNQAECggIKAAHAPwhAA==.',
Tu='Tulsi:BAAANQAECgYICwAAAA==.',
Ty='Tyronos:BAAANQAECgYIDQAAAA==.',
Va='Vaeltharion:BAAANQAECgUICQAAAA==.Varedrae:BAAANQADCggIEAAAAA==.Vas:BAAANQADCgYIFAAAAA==.',
Ve='Verdandi:BAAANQAECgUICgAAAA==.Vevicenth:BAAANQAECgYIDgAAAA==.',
Vo='Voranth:BAABNQAECn8WAAMKAAgKRSB/IADlAgAKAAgKRSB/IADlAgAeAAQKIBKPwwAHAQAAAA==.',
Wa='Warenio:BAABNQAECn8fAAIlAAgKRhcjEAAjAgAlAAgKRhcjEAAjAgAAAA==.Warick:BAAANQADCgMIAwAAAA==.Warpsbulge:BAABNQAECn8ZAAMXAAkKaRpbCwAIAgAXAAkKfRZbCwAIAgAMAAYKrR1AzQDpAQAAAA==.Wayawoman:BAAANQABCgIIAgABNQAECgYIDQAGAAAAAA==.',
Wh='Whakan:BAAANQADCggIIgABNQAECgUIBwAGAAAAAA==.',
Wi='Williamgoat:BAAANQADCgUIBQABNQAECggIKAAHAPwhAA==.',
Wo='Wolfos:BAAANQAECgIICQAAAA==.',
Wt='Wtfox:BAEBNQAECn8dAAIUAAgKzRAmKQDcAQAUAAgKzRAmKQDcAQAAAA==.',
Wu='Wulfgange:BAAANQAECgEIAQAAAA==.',
Wy='Wysteri:BAAANQAECgYIDgAAAA==.',
Xa='Xalatos:BAAANQAECgcIDwAAAA==.Xalfein:BAAANQADCggIFAAAAA==.',
Xi='Xinu:BAAANQADCgIIAgABNQAECggIIAADANcaAA==.',
Xo='Xolani:BAAANQAECgQIAwAAAA==.',
Ya='Yanakana:BAAANQAECgQICAAAAA==.',
Za='Zakeko:BAAANQAECgMIBwAAAA==.Zanderpryde:BAAANQAECgYIDAABNQAECgkJJAALADkdAA==.',
Ze='Zennite:BAAANQAECggICAAAAA==.Zenus:BAAANQAECgIJAgAAAA==.Zesty:BAAANQADCgIJAgAAAA==.Zeusinator:BAAANQAECgcIEQAAAA==.',
Zf='Zfatpanda:BAAANQADCggICAAAAA==.',
Zi='Zinu:BAABNQAECn8gAAIDAAgK1xr5TwB9AgADAAgK1xr5TwB9AgAAAA==.',
Zo='Zota:BAAANQAECgYICgAAAA==.',
Zu='Zukarius:BAAANQADCgUIBQABNQAECgUIDAAGAAAAAA==.Zulfionn:BAAANQAECgYIDgAAAA==.Zurok:BAAANQADCgcIBwABNQAFFAIIAgAGAAAAAA==.',
['Áy']='Áyrá:BAAANQAECgYIDQAAAA==.',
['Øu']='Øuroboros:BAAANQAECgMIBgAAAA==.',
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
