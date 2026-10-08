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

local lookup = {'DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Frost','Paladin-Holy','Monk-Brewmaster','Unknown-Unknown','Shaman-Elemental','Priest-Shadow','Priest-Discipline','Rogue-Subtlety','Shaman-Restoration','DemonHunter-Havoc','DeathKnight-Unholy','Rogue-Assassination','Shaman-Enhancement','Evoker-Preservation','DeathKnight-Frost','Evoker-Augmentation','Priest-Holy','Paladin-Retribution','Druid-Feral','Druid-Restoration','Warrior-Arms','Warrior-Fury','Monk-Windwalker','Monk-Mistweaver','DemonHunter-Devourer','Warrior-Protection','Mage-Arcane','Warlock-Affliction','Evoker-Devastation','Paladin-Protection','DemonHunter-Vengeance','Hunter-Survival','Mage-Fire',}
local provider = {region='US',realm='Ghostlands',name='US',type='weekly',zone=53,date='2026-10-06',data={Ad='Adobo:BAAANQADCgYIDQAAAA==.Adofian:BAAANQADCgYICwAAAA==.',
Af='Aft:BAACNQAFFIEMAAIBAAUKzBr1CAChAQABAAUKzBr1CAChAQA1AAQKgSYAAgEACQpnJPAFAIwDAAEACQpnJPAFAIwDAAAA.',
Ai='Aislin:BAAANQAECgMIAwAAAQ==.',
Ak='Akumu:BAABNQAECoEfAAMCAAgKMh0KMACtAgACAAgKMh0KMACtAgADAAIKehgeUACDAAAAAA==.',
Al='Alarkin:BAACNQAFFIEQAAMEAAYKIhHtBADkAQAEAAYKBBDtBADkAQAFAAUKaAojDABSAQA1AAQKgTUAAwQACQpgJegWACcDAAQACArYJOgWACcDAAUACQo2IHkKAB4DAAAA.Alasmira:BAAANQADCggIEAAAAA==.Alcarde:BAABNQAECoEgAAIGAAkKoRa2BgBlAgAGAAkKoRa2BgBlAgAAAA==.Aldoan:BAAANQAECgIIAgAAAA==.Aleza:BAAANQADCgEIAQAAAA==.Alialeman:BAAANQAECgEIAQAAAA==.Alistiri:BAAANQAECgUICwAAAA==.Alix:BAAANQAECgEIAQAAAA==.Allforge:BAAANQAECgYIDAAAAA==.Almina:BAAANQAECgcIDQAAAA==.Alpal:BAACNQAFFIEQAAIHAAYKSg90BgDcAQAHAAYKSg90BgDcAQA1AAQKgTYAAgcACQoEIEYNAFADAAcACQoEIEYNAFADAAAA.',
Am='Ambs:BAAANQAECgYIEQAAAA==.',
An='Analyse:BAAANQABCgIIAgAAAA==.Andalya:BAAANQAECgYIDgAAAA==.Andaria:BAAANQAECgQIBAAAAA==.Angharrad:BAAANQADCgIIAgAAAA==.',
Ao='Aonani:BAAANQADCgcIFAAAAA==.',
Ap='Aprix:BAAANQAECgYJDAAAAA==.',
Ar='Araara:BAAANQADCgUIBQAAAA==.Aralyn:BAAANQADCgcIDQAAAA==.Arejay:BAAANQAECgQIBgAAAA==.Argeth:BAAANQAECgEIAQAAAA==.Arshika:BAAANQAECgUIEgAAAA==.Artek:BAAANQADCgMIAwAAAA==.Arthan:BAAANQADCgYIBwAAAA==.Arthonix:BAAANQAECgUJCQAAAA==.Arthurleywin:BAAANQAECgUIDwAAAA==.Arvis:BAAANQAECgEIAQAAAA==.',
As='Asamia:BAACNQAFFIEWAAIIAAYK/R3hAAAiAgAIAAYK/R3hAAAiAgA1AAQKgSIAAggACQqVI6cDADoDAAgACQqVI6cDADoDAAAA.Ashaki:BAAANQAECgYIEQAAAA==.Asmodéus:BAAANQADCgUIBQABNQAECgYICgAJAAAAAA==.Astå:BAAANQADCggICAABNQAECggIHwAKAHodAA==.',
At='Athyná:BAAANQADCgIIAgAAAA==.',
Au='Auralius:BAAANQADCgQICAAAAA==.Auroramoon:BAAANQAECgYIDAAAAA==.',
Av='Avana:BAAANQADCgIIAgAAAA==.Avis:BAAANQAECgQIBAAAAA==.',
Aw='Awake:BAABNQAECoEZAAMLAAgKWhCLJwDHAQALAAgKWhCLJwDHAQAMAAEKkAK1KwAlAAAAAA==.',
Ax='Axionar:BAAANQAECggIDgAAAA==.',
Az='Azshauria:BAAANQABCggIEQAAAA==.Azurend:BAAANQAECgYIEwAAAA==.Azázél:BAAANQAECgYICgAAAA==.',
Ba='Badtimeboy:BAAANQAECgEIAQAAAA==.Baffle:BAAANQADCggIGQABNQAECgkJIwANAFkhAA==.Bahula:BAABNQAECoEaAAIOAAgKJQvPcgCEAQAOAAgKJQvPcgCEAQAAAA==.Bainehuln:BAAANQAECgcIEQAAAA==.Bastianos:BAAANQAECgcIEgAAAA==.Batsom:BAAANQABCgEIAQAAAA==.Battlecheeks:BAAANQADCgQIBAABNQAECgQIBAAJAAAAAA==.',
Be='Beastafied:BAAANQABCgEIAQAAAA==.Bellapearl:BAAANQAECgQICgAAAA==.Bellmont:BAAANQAECgYIBwAAAA==.Belron:BAAANQAECgMIBgABNQAECgkJKgAPAGgOAA==.Bernes:BAABNQAECoEfAAMQAAkKxBudMwA5AgAQAAkK9xadMwA5AgABAAcKKBxWMwAhAgAAAA==.',
Bi='Biffle:BAAANQAECggIBAABNQAECgkJIwANAFkhAA==.Bigteef:BAAANQADCgUICQAAAA==.Bioz:BAAANQAECgUIBQAAAA==.Birdhouse:BAAANQAECgYIEgAAAA==.',
Bl='Blackthornn:BAACNQAFFIEQAAIRAAYK/RlkAgAfAgARAAYK/RlkAgAfAgA1AAQKgTYAAhEACQo2Ii0FAGsDABEACQo2Ii0FAGsDAAAA.Blastin:BAAANQADCggICgAAAA==.Blastofel:BAAANQADCgUIBQAAAA==.Bloodcircus:BAAANQAECgYIBgAAAA==.Bloodorphan:BAAANQADCgIIAgABNQAECgkJLAASAIYhAA==.Bloodreign:BAAANQADCgYIBgAAAA==.Bloodworm:BAAANQAECgQIBAABNQAFFAYIDgAEAA8hAA==.Blottros:BAAANQAECgUIDgAAAA==.Blottzilla:BAACNQAFFIEQAAITAAYKNQ38BgC3AQATAAYKNQ38BgC3AQA1AAQKgTcAAhMACQorHh4HACgDABMACQorHh4HACgDAAAA.Bluestreak:BAAANQADCggIEQAAAA==.',
Bo='Bobbyray:BAAANQADCggIDAAAAA==.Bobertbigg:BAABNQAECoEoAAIHAAgKAh4yKQCrAgAHAAgKAh4yKQCrAgAAAA==.Booda:BAAANQADCggICQAAAA==.Boratt:BAAANQADCggIDQAAAA==.Bowbuttkick:BAACNQAFFIEOAAMEAAYKDyH1AQA7AgAEAAYKDyH1AQA7AgAFAAMKrRFFEgDiAAA1AAQKgRwAAwQACQpnJGMWACoDAAQACQpnJGMWACoDAAUAAgoHFKdlAG4AAAAA.Bowjangles:BAEANQAECgQJBAABNQAECggIDwAJAAAAAA==.Boxiebrown:BAABNQAECoEjAAIEAAkKpBSQUgBQAgAEAAkKpBSQUgBQAgAAAA==.',
Br='Bralae:BAAANQAECgYIEgAAAA==.Breaya:BAAANQADCgYIDAAAAA==.Brewskiez:BAAANQADCggIDwAAAA==.Bricktop:BAAANQADCgIIAgAAAA==.Brokuo:BAACNQAFFIERAAMQAAYK0BxlBADJAQAQAAUKMxtlBADJAQAUAAQK6CFqBQBuAQA1AAQKgSQAAxAACQorJZUaANICABAACQouJJUaANICABQACAqeIBAWALcCAAAA.Broon:BAAANQADCgYIDQAAAA==.Brucellosis:BAABNQAECoEiAAMQAAgKfB/XIACmAgAQAAcK4CHXIACmAgAUAAEKvQ56kAA5AAAAAA==.Brâgak:BAAANQADCgcIDQAAAA==.',
Bu='Bubbawoodkin:BAAANQAECgQIBgAAAA==.Buffpres:BAAANQAECgQIBAABNQAECgUIDAAJAAAAAA==.Butchkween:BAAANQADCggIEAABNQAECggIHwAVAB4QAA==.Buzzlez:BAACNQAFFIEQAAIWAAYK5A/4CADWAQAWAAYK5A/4CADWAQA1AAQKgTYAAhYACQpnIdgGAH8DABYACQpnIdgGAH8DAAAA.',
Ca='Camspally:BAAANQAECgMJAwAAAA==.Candyquartz:BAAANQADCgMIAwAAAA==.Carkleaschah:BAAANQADCgYICwABNQAECgQIBAAJAAAAAA==.Cat:BAAANQABCgIIAgAAAA==.',
Ch='Chaddrique:BAAANQABCgQIBgAAAA==.Chadgolas:BAAANQADCgIIAgAAAA==.Chadimir:BAAANQAECgQIBwAAAA==.Chahae:BAACNQAFFIENAAMQAAUKTCUoAgASAgAQAAUKTCUoAgASAgAUAAEKQQftGQA8AAA1AAQKgTUAAxAACQrLJhAEAKgDABAACQrLJhAEAKgDABQAAQrWJZmAAGQAAAAA.Channintotem:BAEANQAECgEIAQABNQAECgcIHwAXACYfAA==.Cheerwine:BAABNQAECoEaAAMYAAgKPAozEwCTAQAYAAgKPAozEwCTAQAZAAYKZgvxNgAwAQAAAA==.Cheezits:BAAANQAECgcIBwAAAA==.Chinnook:BAAANQADCgYIBgAAAA==.',
Cl='Clapdo:BAECNQAFFIENAAMaAAQKCx3UEQBuAQAaAAQKCx3UEQBuAQAbAAEKwQsiBABUAAA1AAQKgSMAAxoACQq8JNEXAE8DABoACQq8JNEXAE8DABsAAQo1G+UpAEMAAAAA.Clinician:BAABNQAECoEYAAMWAAkK3xULLQCUAgAWAAkK3xULLQCUAgALAAYK8gzINgBHAQAAAA==.',
Co='Commandor:BAAANQADCgEIAQAAAA==.Congolense:BAAANQAECgYICwAAAA==.Corbzz:BAAANQADCgMIAwAAAA==.Cougrogue:BAAANQAECgQIDQAAAA==.Cowacusrex:BAAANQAECgEIAQAAAA==.',
Cp='Cptrisky:BAAANQABCgIIAgAAAA==.',
Cr='Crazzenburns:BAABNQAECoEaAAQcAAcK+Bi+IQDvAQAcAAcK+Bi+IQDvAQAdAAMKeQ2cNQCXAAAIAAEK+g+LLQAtAAAAAA==.Creamer:BAABNQAECoEYAAMOAAgKRxGzZQCsAQAOAAgKRxGzZQCsAQAKAAEK1QgaFgEzAAAAAA==.Crunchin:BAABNQAECoEuAAMXAAkKQRecfAABAgAXAAgKUxacfAABAgAHAAkK8AVAagCyAQAAAA==.',
Cu='Cutedwarfxd:BAACNQAFFIERAAIBAAYKfyJGAgBhAgABAAYKfyJGAgBhAgA1AAQKgSUAAgEACQrhJeUDAKwDAAEACQrhJeUDAKwDAAAA.',
Da='Dakkadakka:BAAANQAECgMIAgAAAA==.Damane:BAAANQADCgUIBQABNQAECgUICwAJAAAAAA==.Danìel:BAACNQAFFIEQAAIPAAYKPRMNBQDgAQAPAAYKPRMNBQDgAQA1AAQKgTUAAw8ACQroIp0HAHADAA8ACQroIp0HAHADAB4ACAq9FUAnAOoBAAAA.Darkarts:BAAANQADCgIIAgAAAA==.Darkmoore:BAAANQADCgUIBQAAAA==.Dartwo:BAAANQAECgYICwAAAA==.',
De='Deadalicious:BAAANQAECgEIAgABNQAECgkJKgAPAGgOAA==.Deathspoons:BAACNQAFFIEYAAIBAAcKYxl2AgBZAgABAAcKYxl2AgBZAgA1AAQKgSsAAwEACQoyIugLAEQDAAEACQoyIugLAEQDABAAAQpKIYe4AFgAAAAA.Delecto:BAAANQAECgUIDgAAAA==.Delmônico:BAAANQADCgYIDQAAAA==.Delushoni:BAAANQADCgUIBQAAAA==.Dendalaus:BAACNQAFFIEPAAMNAAUKdSGeBgCMAQANAAQKVCCeBgCMAQARAAEK/SXQFABkAAA1AAQKgTIAAw0ACQo7JiUKAMYCAA0ABwolJCUKAMYCABEABArTJQ43ALwBAAAA.Derkamental:BAAANQAECgIIAgAAAA==.Devora:BAEANQADCggICAABNQAECgcIHwAXACYfAA==.Dextersmash:BAAANQADCggIDAAAAA==.',
Di='Digallo:BAAANQADCggIGQAAAA==.Dimsumbun:BAAANQAECgYIEAAAAA==.Dingledorf:BAAANQAECgYIEgAAAA==.Dinklebahmp:BAAANQAECgUIBgABNQAFFAYIEAAfAI0dAA==.Dinoxeye:BAAANQAECgYIDwAAAA==.Discosdead:BAAANQADCgUIBQABNQAECgEIAQAJAAAAAA==.',
Do='Donut:BAAANQADCgMIAwAAAA==.',
Dr='Draacarys:BAAANQADCgQIBAAAAA==.Dragonpandas:BAAANQADCggJCAABNQAECgkJMgAUAMIjAA==.Dramonk:BAACNQAFFIEKAAIcAAUKjQt5BwA8AQAcAAUKjQt5BwA8AQA1AAQKgSQAAhwACQpKIn0LAAYDABwACQpKIn0LAAYDAAAA.Dro:BAAANQABCgIIAgAAAA==.Drogbar:BAAANQABCgIIAgAAAA==.Druinlock:BAAANQADCgUIBQAAAA==.Druiske:BAAANQAECgMIAwABNQAECgQIBwAJAAAAAA==.',
Du='Dustydrewid:BAAANQADCgEIAQAAAA==.',
Dy='Dyre:BAAANQAECggICAAAAA==.',
Ei='Eir:BAABNQAECoEgAAIHAAgKdw5eXgDaAQAHAAgKdw5eXgDaAQAAAA==.',
El='Ellsnarl:BAAANQADCgYIBgAAAA==.Eltariel:BAAANQADCgYIBwABNQAECgQIBAAJAAAAAA==.',
Em='Emeraldjin:BAABNQAECoEkAAIdAAgKfCXJAwBeAwAdAAgKfCXJAwBeAwAAAA==.',
En='Ensera:BAAANQAECgUIDAAAAA==.',
Er='Eraesong:BAAANQADCgMIAwAAAA==.Erielyn:BAAANQAECgcIEAAAAA==.Ernet:BAABNQAECoEdAAIgAAcKbhNYxwDSAQAgAAcKbhNYxwDSAQAAAA==.',
Eu='Eugenekrabs:BAAANQADCgYIBgAAAA==.',
Ex='Extraho:BAABNQAECoEfAAIWAAgKPCMbEwAeAwAWAAgKPCMbEwAeAwAAAA==.',
Fa='Fabled:BAACNQAFFIERAAQDAAYKahvjBQC+AAACAAQKJhgeDwBcAQADAAIK9SDjBQC+AAAhAAEK8R/MBgBeAAA1AAQKgSUAAwMACQqOI0EEANwCAAMACAr6IEEEANwCAAIABArLI1eXAHsBAAAA.Faeyice:BAAANQAECgcIEgAAAA==.',
Fe='Fearmachine:BAAANQADCggJFAABNQAECggIDgAJAAAAAA==.Feyden:BAAANQAECgQICAAAAA==.',
Ff='Ffxivcatgirl:BAAANQADCgQIBAABNQAFFAYIEQABAH8iAA==.',
Fi='Fielton:BAAANQAECgEIAQABNQAECgkJGgAXABYiAA==.Fiiryazell:BAAANQAECgEIAQAAAA==.Fijaswarerth:BAAANQAFFAMIAwAAAA==.Fijaswitcher:BAAANQAECgcIDgAAAA==.Fimbulvargr:BAAANQAECgcIEgAAAA==.Finiith:BAAANQAECgUJBgABNQAFFAYIEAAEACIRAA==.Finîth:BAAANQAECgUICgABNQAFFAYIEAAEACIRAA==.Firebrands:BAAANQAECgIIAgAAAA==.Firedragön:BAAANQAECgEIAQAAAA==.Firelordz:BAAANQADCgQIBAAAAA==.',
Fl='Flogdanoggin:BAAANQADCgcIBwAAAA==.Flogurnoggin:BAAANQADCggIBQAAAA==.Fluffly:BAAANQADCggICAAAAA==.Fluffyokami:BAABNQAECoEbAAIYAAgKPBk9CgBjAgAYAAgKPBk9CgBjAgAAAA==.Flyingrodent:BAABNQAECoEcAAMiAAYKph56EwD3AQAiAAYKph56EwD3AQATAAEKXwzwSAAwAAAAAA==.',
Fo='Foneer:BAABNQAECoEeAAIcAAgKhAtNMgBNAQAcAAgKhAtNMgBNAQAAAA==.Forestsky:BAAANQAECgcIDgAAAA==.',
Fr='Freezepop:BAABNQAECoEkAAIgAAgK6CA9QgDyAgAgAAgK6CA9QgDyAgAAAA==.Frenchieboi:BAAANQAECgUICAABNQAECgcIEQAJAAAAAA==.Frenchielock:BAAANQAECgcIEQAAAA==.Frenchthyr:BAAANQAECgUIDQABNQAECgcIEQAJAAAAAA==.Frostbeast:BAAANQADCgEIAQAAAA==.',
Ga='Gaden:BAAANQAECgQIBgAAAA==.Galdiian:BAAANQAECgUIBgAAAA==.Gatebtch:BAAANQAECgYICgAAAA==.Gawdspet:BAACNQAFFIEHAAMDAAMK0w3pEABxAAACAAIKkBGuJwCcAAADAAIKWwPpEABxAAA1AAQKgSoAAwIACQqpHh1XADACAAIABwoNHh1XADACAAMABAoZF+4qABoBAAAA.',
Gh='Ghosi:BAABNQAECoEfAAMjAAkKUhbREQBdAgAjAAkKUhbREQBdAgAXAAEKeglaeAEyAAAAAA==.',
Gl='Glaivier:BAAANQAECgMIBgAAAA==.Glitchhunt:BAAANQAECgUIBQAAAA==.',
Go='Goodtimeboy:BAAANQADCgYIBwAAAA==.Goregrind:BAACNQAFFIELAAMQAAYKlBe9BQCmAQAQAAUKRRu9BQCmAQABAAEKHAXNNAAdAAA1AAQKgSMAAhAACQr/I7YJAF4DABAACQr/I7YJAF4DAAAA.Gorgeous:BAAANQADCgIIAgAAAA==.Gorius:BAAANQADCggIIgAAAA==.',
Gr='Grampman:BAAANQAECgYIBgAAAA==.Gremory:BAAANQAECgYIEwAAAA==.Grimholt:BAAANQADCgQICAAAAA==.',
Gu='Guldank:BAAANQAECgUIDwAAAA==.Guretta:BAAANQAECgYIEgAAAA==.',
Gw='Gwynhwyvar:BAAANQAECgQICAAAAA==.',
Ha='Haeneros:BAABNQAECoEVAAIkAAcKShLnDgCXAQAkAAcKShLnDgCXAQAAAA==.Handmemytank:BAAANQAECgIJAwABNQAECgkJJAAEAIYkAA==.Harumi:BAAANQAECgUIDwAAAA==.',
He='Healeta:BAAANQAECgMIBAAAAA==.Hearo:BAAANQAECgEIAQAAAA==.Heavyhead:BAAANQAECgIIAgAAAA==.Heavypudding:BAAANQAECgQICQAAAA==.Hedgehog:BAABNQAECoEoAAIdAAkKfgxfGQC7AQAdAAkKfgxfGQC7AQAAAA==.Heightning:BAAANQAECgQIBgAAAA==.Heisenberf:BAACNQAFFIEPAAIgAAYK9wxEDwDYAQAgAAYK9wxEDwDYAQA1AAQKgTYAAyAACQovIGctACgDACAACQoRIGctACgDAAYAAQrsHFgzAFYAAAAA.Hextrathicc:BAABNQAECoEvAAICAAkK/BnDKgDBAgACAAkK/BnDKgDBAgAAAA==.',
Ho='Hofnarr:BAAANQAECggIEgAAAA==.Holybuttkick:BAABNQAECoEcAAQjAAgKWh5DGAAMAgAjAAYKPCBDGAAMAgAHAAgKiRL3UAAIAgAXAAEK4xYNYAFFAAABNQAFFAYIDgAEAA8hAA==.Hoozurdaddy:BAABNQAECoEfAAIKAAkKHxSKPgBRAgAKAAkKHxSKPgBRAgAAAA==.',
Ia='Iamdownhere:BAAANQABCgYICgAAAA==.',
Ig='Igamm:BAAANQADCgYIDAAAAA==.Ignatius:BAAANQAECgMIBQAAAA==.Igniting:BAABNQAECoEjAAIgAAgKCRp6eQB0AgAgAAgKCRp6eQB0AgABNQAECgMIBgAJAAAAAA==.',
Ik='Ikillyoutoo:BAAANQAECgUICwAAAA==.Ikki:BAAANQAECggJCgAAAA==.',
Il='Illuzions:BAAANQADCggIDwAAAA==.',
Im='Impenetrable:BAAANQAECgIIAgAAAA==.Impression:BAACNQAFFIERAAIHAAYKRiPdAQB/AgAHAAYKRiPdAQB/AgA1AAQKgSAAAgcACQqTJo8AAO0DAAcACQqTJo8AAO0DAAAA.Imprison:BAAANQAECgIIAwABNQAFFAYIEQAHAEYjAA==.',
In='Incarnated:BAAANQAECgcIDwAAAA==.Incursion:BAABNQAECoEhAAMHAAgKGBSfTQAUAgAHAAgKGBSfTQAUAgAXAAYKKAnR3gAjAQAAAA==.Insayn:BAAANQADCgIIAgABNQAECgkJGwAXAAMkAA==.Inviçtus:BAAANQAECgQIBAAAAA==.',
Ir='Ironwolf:BAABNQAECoEoAAIfAAkKQgxWFAC0AQAfAAkKQgxWFAC0AQAAAA==.',
Ja='Jademoot:BAAANQAECgcIEgAAAA==.Jadis:BAAANQADCgUIBQAAAA==.Jaeaoria:BAAANQABCgIIAQAAAA==.Jaxblack:BAAANQADCggIEAAAAA==.Jaxurbate:BAAANQAECgIJAgAAAA==.Jaylaah:BAAANQAECgMIAwAAAA==.Jayvlyn:BAAANQAECgUICAAAAA==.',
Je='Jessex:BAAANQABCgIIAgAAAA==.',
Ji='Jiinn:BAAANQAECgMIAwAAAA==.',
Jj='Jjman:BAAANQAECgYIBwABNQAECgkJGgAXABYiAA==.Jjuicyfruit:BAAANQADCgYIEgAAAA==.',
Jo='Jodirty:BAAANQADCgYIBgAAAA==.Joftokal:BAABNQAECoEeAAIKAAgKShIHUwD/AQAKAAgKShIHUwD/AQAAAA==.Jokesonme:BAAANQAECgIIAwAAAA==.Jonebonejovi:BAAANQADCgIIAgAAAA==.Jorabna:BAAANQADCgYICgAAAA==.Joyboy:BAABNQAECoEYAAIHAAkKMR+VEgAqAwAHAAkKMR+VEgAqAwAAAA==.',
Ju='Junpana:BAAANQAECgYIBAAAAA==.',
Ka='Kakiso:BAAANQAECgYIEwAAAA==.Kalanash:BAAANQADCgUIBQAAAA==.Kalim:BAAANQADCgIIAgAAAA==.Kaloneras:BAAANQADCgYICAAAAA==.Kattle:BAABNQAECoExAAISAAkKcSMBAwBtAwASAAkKcSMBAwBtAwAAAA==.',
Ke='Kellistus:BAAANQADCgUICQAAAA==.Keyrasky:BAAANQAECgIIAgAAAA==.',
Kh='Khailyn:BAAANQADCgIJAgAAAA==.',
Ki='Kikuu:BAABNQAECoEdAAIjAAgK4h8tCwDHAgAjAAgK4h8tCwDHAgAAAA==.Kin:BAAANQADCggICwAAAA==.Kiradanna:BAABNQAECoEtAAIeAAkKvR3yDAAGAwAeAAkKvR3yDAAGAwAAAA==.Kiroa:BAAANQAECgUIDgAAAA==.Kiyoshiru:BAAANQADCgUIBQAAAA==.',
Kn='Knoks:BAABNQAECoEYAAMDAAgKlhn4NQDeAAACAAYK4RepjACYAQADAAMKnxj4NQDeAAAAAA==.Knotty:BAAANQAECgEIAQABNQAECgQIBAAJAAAAAA==.',
Ko='Koff:BAACNQAFFIEMAAIdAAQKuybKAgDMAQAdAAQKuybKAgDMAQA1AAQKgR0AAh0ACQpYJeMBAJgDAB0ACQpYJeMBAJgDAAAA.Koino:BAAANQAECgUIBQAAAA==.Koreshei:BAAANQAECgUICAAAAA==.Koressita:BAAANQADCgYIBgAAAA==.',
Kr='Krixxus:BAAANQAECgQJBwABNQAECgUIBgAJAAAAAA==.',
Ku='Kuni:BAAANQAECgYIEgAAAQ==.Kurius:BAAANQAECgIIAwAAAA==.Kuzan:BAAANQAECgcIDQAAAA==.',
Ky='Kylian:BAAANQAECgQIBAABNQAECgkJLQAeAL0dAA==.',
La='Lamynx:BAAANQAECgUIEQAAAA==.Lazydragon:BAABNQAECoEbAAQXAAgKzwpmuQBxAQAXAAcKaQtmuQBxAQAHAAIKUgc37ABvAAAjAAIKLArsWgBIAAAAAA==.',
Le='Lelouch:BAAANQAECgYICQAAAA==.Leone:BAAANQAECgQIBAABNQAECggIHwACADIdAA==.',
Li='Liberation:BAABNQAECoEXAAIeAAcK/RQyKQDZAQAeAAcK/RQyKQDZAQAAAA==.Lilgirlblue:BAABNQAECoEYAAIEAAgKwQ0gcAAEAgAEAAgKwQ0gcAAEAgAAAA==.Lilreggie:BAAANQADCggIFAAAAA==.Lilvoids:BAABNQAECoErAAMDAAkKbgsrIABlAQACAAcKEwmvmQB1AQADAAcKUAkrIABlAQAAAA==.Lineste:BAAANQAECgYIEAAAAA==.Lion:BAAANQAECgYJDgAAAA==.',
Ll='Llyolis:BAAANQAECgUIBgAAAA==.',
Lo='Lockdeeznutz:BAAANQADCgQIBAAAAA==.Loldie:BAAANQAECgUIDQAAAA==.Lonepanda:BAACNQAFFIEQAAIfAAYKjR2rAAAKAgAfAAYKjR2rAAAKAgA1AAQKgTYAAh8ACQpoJQABAMQDAB8ACQpoJQABAMQDAAAA.Lorwynx:BAABNQAECoEtAAIgAAkKnCDuKAA1AwAgAAkKnCDuKAA1AwAAAA==.',
Lu='Luciliv:BAAANQADCgYIBgABNQAECgkJGwAXAAMkAA==.Lunado:BAAANQADCgUIBwAAAA==.Lupinaea:BAAANQAECgMIAwAAAA==.',
Lv='Lvcifur:BAAANQABCgQIBAAAAA==.',
Ma='Maalk:BAAANQADCgYICgAAAA==.Mabellah:BAAANQAECgUIBQAAAA==.Maemikyu:BAABNQAECoFDAAIWAAgKnSP/DwAxAwAWAAgKnSP/DwAxAwAAAA==.Magebuttkick:BAAANQADCggIDAABNQAFFAYIDgAEAA8hAA==.Magusultimis:BAAANQAECgcIEgAAAA==.Mahöshöjo:BAAANQAECgIIAgAAAA==.Maintank:BAAANQAECgUIDgAAAA==.Makepoop:BAABNQAECoEnAAILAAgKiSKwDgDuAgALAAgKiSKwDgDuAgAAAA==.Maloa:BAAANQADCgYIBgAAAA==.Manbomanbo:BAAANQAECgQIBAABNQAECggIBAAJAAAAAA==.Marianita:BAABNQAECoEZAAMPAAkKcR5CFgDKAgAPAAkKcR5CFgDKAgAeAAEKfhUOXgA4AAAAAA==.Maureen:BAAANQADCgUIBQAAAA==.',
Me='Mediarahan:BAAANQAECgIIAwAAAA==.Melfist:BAAANQAECgUIDAAAAA==.Melphis:BAAANQADCgMIAwAAAA==.Melysse:BAAANQAECgcIEAAAAA==.Mendocino:BAAANQADCgcIEAAAAA==.Mereo:BAAANQAECgYIDgABNQAECggIHwAKAHodAA==.',
Mi='Mikiko:BAABNQAECoEjAAIKAAgKyRBGVwDwAQAKAAgKyRBGVwDwAQAAAA==.Mikto:BAAANQADCgEJAQAAAA==.Millcreek:BAAANQAECgYIEwAAAA==.Milliananeko:BAAANQADCgUICQABNQAECgYICwAJAAAAAA==.Miracat:BAAANQAECgQIBgAAAA==.Missindragon:BAABNQAECoEeAAIOAAgKqCCXGQDwAgAOAAgKqCCXGQDwAgAAAA==.',
Mo='Moomoohead:BAAANQAECgQIBAAAAA==.Morberto:BAAANQABCggICgAAAA==.Morianne:BAAANQADCgQIBAAAAA==.Mormel:BAAANQAECgYIEgAAAA==.Morticus:BAAANQAECgYIDgAAAA==.',
Ms='Msthea:BAAANQAECgYIDAAAAA==.',
['Mä']='Mälina:BAAANQAECgIIAgAAAA==.',
Na='Narial:BAAANQADCgIIAQAAAA==.Narrthas:BAAANQAECgUIBgAAAA==.Narru:BAACNQAFFIENAAIEAAYK1hGYBADtAQAEAAYK1hGYBADtAQA1AAQKgSwABAQACQpiJfcDAL8DAAQACQpiJfcDAL8DAAUABQrqCq1HAOwAACUABArhCi8NALQAAAAA.',
Ne='Nebyula:BAAANQAECgUICwAAAA==.',
Ni='Nizuno:BAAANQADCgYIBgAAAA==.',
No='Norieka:BAAANQAECgUIDAAAAA==.Norvasc:BAAANQADCgEIAQAAAA==.Noskillidan:BAAANQAECgQIBAABNQAFFAYIDwAgAPcMAA==.Notknoks:BAAANQADCggICAAAAA==.',
Nu='Numinous:BAAANQAECgIIAwABNQAECgkJJgAaADgYAA==.',
Ny='Nykoleus:BAAANQAECgYICQAAAA==.Nylokar:BAAANQADCgQIBAAAAA==.',
Oa='Oatbarrel:BAAANQADCgYICAAAAA==.Oatbreaker:BAAANQADCgYICgAAAA==.',
Og='Oggoat:BAAANQAECgIIAgAAAA==.',
Oz='Ozyy:BAAANQAECgEIAQAAAA==.',
Pa='Painindaazz:BAAANQADCgYIEgAAAA==.Pallygranny:BAEBNQAECoEfAAIXAAcKJh+2WwBaAgAXAAcKJh+2WwBaAgAAAA==.Pawptart:BAAANQABCgQIBAAAAA==.',
Ph='Phyntom:BAAANQAECgMIAwAAAA==.',
Pi='Pibbs:BAACNQAFFIEGAAIgAAQKExHNIAA/AQAgAAQKExHNIAA/AQA1AAQKgSQAAiAACQozIaA/APgCACAACQozIaA/APgCAAAA.',
Pl='Plaguepanda:BAABNQAECoEyAAQUAAkKwiO0DQAMAwAUAAkKSR+0DQAMAwAQAAkKfSJ4FAD/AgABAAEKFRqxuQA2AAAAAA==.Platinumcas:BAAANQADCgcIEwAAAA==.Pluribus:BAAANQADCgcIDgAAAA==.',
Po='Poohonroids:BAAANQAECgYIDAAAAA==.Poppatroll:BAAANQADCggIEgAAAA==.',
Pr='Priestpvp:BAAANQAECgEIAQAAAA==.Priva:BAAANQADCgcIBwAAAA==.Protagoras:BAAANQAECgEIAgAAAA==.',
['Pä']='Pänz:BAAANQAECgcIEgAAAA==.',
Ra='Rafig:BAACNQAFFIEQAAIgAAYK3yIJAwB+AgAgAAYK3yIJAwB+AgA1AAQKgTYAAiAACQqbJgMBAPoDACAACQqbJgMBAPoDAAAA.Ragefyre:BAAANQAECgIJAgAAAA==.Ralii:BAAANQADCgUIBQAAAA==.Ralobii:BAAANQAECgcJDQABNQADCgUIBQAJAAAAAA==.Ramellis:BAAANQADCgMIAwAAAA==.Ramses:BAACNQAFFIEFAAIKAAMKSgRnGADKAAAKAAMKSgRnGADKAAA1AAQKgSgAAwoACQpaFBdTAP8BAAoACApnFBdTAP8BAA4ACQqLD1pdAMgBAAAA.Ratbasterd:BAAANQADCgQIBAAAAA==.Rats:BAAANQAECgIIAgAAAA==.Rayve:BAAANQABCgIIAgAAAA==.Rayy:BAABNQAECoEYAAIPAAkKVx8LDQAqAwAPAAkKVx8LDQAqAwAAAA==.Razgar:BAAANQAECgIIAgAAAA==.',
Re='Reeji:BAAANQAECgMIAwAAAA==.Reinerbraun:BAAANQADCgcICAAAAA==.Renade:BAABNQAECoEeAAIRAAgKHRSOKwAHAgARAAgKHRSOKwAHAgAAAA==.Rexx:BAAANQADCgMIAwAAAA==.Reywhite:BAAANQAECgEIAgABNQAECgQICAAJAAAAAA==.',
Ri='Rigidsxz:BAAANQADCgUIBQAAAA==.Riskymonk:BAAANQADCgIIAgAAAA==.Riskyshammy:BAABNQAECoE3AAMOAAgKox3HKQCZAgAOAAgKox3HKQCZAgAKAAEKYgiLJgEqAAAAAA==.Riteaid:BAAANQAECgQICwAAAA==.Ritual:BAAANQAECgQIBAABNQAECgkJGwAXAAMkAA==.',
Ro='Robe:BAAANQAECgIJAwABNQAECgYICwAJAAAAAA==.Rolexor:BAAANQADCgEIAQAAAA==.Ronok:BAAANQAECgcIEgAAAA==.Rorthach:BAAANQAECgEIAQAAAA==.Roru:BAABNQAECoE3AAMCAAkKGxQyTQBNAgACAAkKGxQyTQBNAgADAAQK6wLJTgCHAAAAAA==.Roseire:BAAANQAECgQICAAAAA==.Rosethebrute:BAABNQAECoEmAAIaAAgKaB1FTwCBAgAaAAgKaB1FTwCBAgAAAA==.Rosetheholy:BAAANQAECgcIEgABNQAECggIJgAaAGgdAA==.Rougeloving:BAABNQAECoEYAAINAAkKSBliDgCBAgANAAkKSBliDgCBAgAAAA==.',
Ru='Ruler:BAAANQAECgcIEAAAAA==.Ruli:BAABNQAECoEzAAIEAAkKCyARGgAYAwAEAAkKCyARGgAYAwAAAA==.Rusticdiino:BAAANQADCgEIAQABNQAECggIIgAKAD8gAA==.',
Ry='Ryshin:BAABNQAECoEtAAMRAAkKMxecIABTAgARAAkKMxecIABTAgANAAUK7wfiMAAWAQAAAA==.',
['Rø']='Rørs:BAAANQADCgcIBwAAAA==.',
Sa='Sabeck:BAABNQAECoEaAAIXAAkKFiLgHwAsAwAXAAkKFiLgHwAsAwAAAA==.Safi:BAAANQADCggICAAAAA==.Saltine:BAEANQAECgEIAQABNQAECggIDwAJAAAAAA==.Sanctano:BAAANQAECgYIDQAAAA==.Saneras:BAAANQAECgQIBAAAAA==.Sapdo:BAEANQAFFAIIAgABNQAFFAQIDQAaAAsdAA==.Sarshia:BAAANQADCgYJCAAAAA==.Sayn:BAABNQAECoEbAAIXAAkKAyTLDQCJAwAXAAkKAyTLDQCJAwAAAA==.',
Sc='Schultzies:BAABNQAECoEfAAIMAAgKyB6cAgDYAgAMAAgKyB6cAgDYAgAAAA==.Scorchdk:BAAANQADCgUIBgAAAA==.',
Sd='Sdog:BAAANQAECgIIAgAAAA==.',
Se='Seanboyymage:BAABNQAECoEyAAIgAAkKGh5mLwAjAwAgAAkKGh5mLwAjAwAAAA==.Seina:BAAANQAECgcIEgAAAA==.Sensei:BAAANQAECgEIAQAAAA==.Sephirofl:BAAANQAECgQICQAAAA==.Seulrene:BAABNQAECoEeAAIQAAcKpSHTJACNAgAQAAcKpSHTJACNAgAAAA==.',
Sh='Shamlaw:BAABNQAECoEdAAIOAAgKQhc7RwAaAgAOAAgKQhc7RwAaAgAAAA==.Shammydavis:BAAANQAECgIIAgAAAA==.Shampayn:BAAANQAECgUICwAAAA==.Shankiee:BAAANQABCgIIAgAAAA==.Shanti:BAAANQAECgcIEQAAAA==.Shhuffle:BAABNQAECoEjAAMNAAkKWSEBBABSAwANAAkK/h8BBABSAwARAAgKJB4hGACTAgAAAA==.Shieldmommy:BAAANQAECgUIBQABNQAFFAYIDwAgAPcMAA==.Shiv:BAAANQAECgUIBgAAAA==.Shockuse:BAAANQAECgcICgAAAA==.Shodoch:BAAANQADCgUIBQAAAA==.Shorukin:BAAANQADCgYIBwAAAA==.Shupasins:BAABNQAECoEvAAQOAAgKDR5IKAChAgAOAAgKDR5IKAChAgAKAAgKyherUAAIAgASAAIKKw2GKACMAAAAAA==.Shyamablue:BAAANQAECgYIEQAAAA==.',
Si='Silvercas:BAABNQAECoEYAAINAAcKaxH8HQDNAQANAAcKaxH8HQDNAQAAAA==.Simpleyfire:BAABNQAECoEiAAMKAAgKPyAHIQDpAgAKAAgKPyAHIQDpAgAOAAcKyRExcACMAQAAAA==.',
Sk='Skullet:BAABNQAECoEWAAIaAAcKZhDDlwC4AQAaAAcKZhDDlwC4AQAAAA==.Skurmpls:BAAANQADCgcIBwABNQAECgQIDQAJAAAAAA==.',
Sl='Slamjam:BAAANQAECgQIBAABNQAFFAYIEAALAIAeAA==.Slimshadyy:BAAANQADCgQIBQAAAA==.Slurpee:BAABNQAECoEcAAIgAAcK/Q9d2gCsAQAgAAcK/Q9d2gCsAQAAAA==.',
Sm='Smooth:BAABNQAECoEqAAMgAAkKMhuCUwDJAgAgAAkKsBqCUwDJAgAGAAQKNhJtHwDLAAAAAA==.',
Sn='Snaphance:BAAANQAECgcIDgAAAA==.Sneekypete:BAAANQADCgYIBgAAAA==.Sniffer:BAAANQAECgYICgAAAA==.Sniparcat:BAAANQADCgYICAAAAA==.Snipercat:BAABNQAECoEaAAIaAAkKvw2adwANAgAaAAkKvw2adwANAgAAAA==.Snuffles:BAABNQAECoEaAAIXAAcKCx8hVgBqAgAXAAcKCx8hVgBqAgAAAA==.Snøkie:BAAANQADCgcIDQAAAA==.',
So='Solange:BAAANQADCgYIBgAAAA==.Sorscha:BAAANQADCggIDwAAAA==.Soupforsale:BAAANQABCgQIBQAAAA==.',
Sp='Spammy:BAABNQAECoEZAAMHAAkKwhQ6OwBaAgAHAAkKwhQ6OwBaAgAXAAEKlAhBcwE1AAAAAA==.Sparlyy:BAACNQAFFIEQAAMLAAYKgB7JBQCjAQALAAQKpCTJBQCjAQAWAAIK+xjAHADFAAA1AAQKgTQAAwsACQqhJoMAAPADAAsACQqhJoMAAPADABYAAgqnFHDHAIoAAAAA.Spectrality:BAAANQAECgEIAQABNQAECgYICwAJAAAAAA==.',
Ss='Sswordy:BAACNQAFFIEQAAIEAAYKNxLqAwD9AQAEAAYKNxLqAwD9AQA1AAQKgUoAAgQACQrnIzAEALwDAAQACQrnIzAEALwDAAAA.Sswordyvani:BAAANQADCgYIDAABNQAFFAYIEAAEADcSAA==.',
St='Stephhunt:BAAANQABCgIIAgAAAA==.Stimulus:BAABNQAECoEaAAMWAAgKmAtSbACiAQAWAAgKmAtSbACiAQAMAAUKnQLTFgCmAAAAAA==.Stinkynuuts:BAAANQADCggIHwAAAA==.Stompy:BAAANQAECgEIAQAAAA==.Stormcloak:BAAANQADCggIDgAAAA==.Stormfang:BAAANQAECgYIBAAAAA==.',
Su='Sumbadvoodoo:BAAANQAECgIIAgAAAA==.Sunkist:BAAANQAECgYIDgAAAA==.Sunwing:BAAANQADCgUJBQAAAA==.Sureina:BAAANQAECgQIBAAAAA==.Surlym:BAABNQAECoElAAIdAAkKrCLjAgB4AwAdAAkKrCLjAgB4AwAAAA==.',
Sw='Swash:BAAANQADCgcIBwAAAA==.Switchglaive:BAABNQAECoEqAAMPAAkKaA4gLgAGAgAPAAkKYQ4gLgAGAgAkAAcKvAgiFgAZAQAAAA==.',
Sy='Sylphie:BAAANQAECgIIAgAAAA==.Symphemon:BAABNQAECoEpAAMeAAkKBA9pJAAEAgAeAAkKkw5pJAAEAgAPAAgKfQo8QQB/AQAAAA==.Symphoid:BAAANQAECgYICgAAAA==.Syseloris:BAABNQAECoEcAAMkAAcKgR0wCABIAgAkAAcKgR0wCABIAgAPAAUKCRHhSwA3AQAAAA==.Sythion:BAACNQAFFIEFAAIiAAMKGQw4CADaAAAiAAMKGQw4CADaAAA1AAQKgSMAAyIACQodFmANAHICACIACQodFmANAHICABMABwqUEE4iAJcBAAAA.',
['Sâ']='Sâlisbury:BAAANQADCgYIDAAAAA==.',
['Së']='Sëphy:BAAANQAECgEIAQAAAA==.',
Ta='Taediris:BAAANQADCgYIDgAAAA==.Taliiha:BAAANQAECgUIBgAAAA==.Tanao:BAAANQAECgUIBgAAAA==.',
Te='Teenieween:BAAANQADCgIIAgAAAA==.Tengenuzui:BAAANQADCgEIAQAAAA==.Tenshi:BAAANQAECgMIAwAAAA==.Terravesh:BAAANQADCgIIAgAAAA==.',
Th='Thewarfox:BAAANQABCgIIAgAAAA==.Thopegor:BAAANQAECgIJAgAAAA==.Thundergunt:BAAANQAECgcIBwABNQAECggIKAAHAAIeAA==.',
Ti='Tianjin:BAAANQAECgEIAQAAAA==.Tickslap:BAAANQADCggIDQAAAA==.Timid:BAAANQADCgIIAgAAAA==.Tintaglia:BAAANQAECgYIEwAAAA==.Tiqtaqto:BAAANQADCgIIAgAAAA==.Tivali:BAAANQADCgIIAgAAAA==.',
To='Toaster:BAAANQAECgUIDAAAAA==.Tober:BAAANQADCgcIFQAAAA==.Toni:BAAANQADCgcIDwAAAA==.Toodles:BAAANQADCgUIBQAAAA==.',
Tr='Trust:BAABNQAECoEeAAIEAAgKIBXiVQBHAgAEAAgKIBXiVQBHAgAAAA==.',
Tu='Tunawhale:BAAANQAECgIIAwAAAA==.',
Tw='Twickenham:BAAANQADCgMIAwAAAA==.',
Ty='Tyloriavis:BAAANQAECgMIBQAAAA==.',
Ul='Ulfberht:BAAANQADCggIDwAAAA==.Ulfin:BAAANQADCgUIBQABNQAECgYIEgAJAAAAAA==.Ultramind:BAAANQADCgUIBQAAAA==.',
Um='Umbras:BAAANQADCgIIAgAAAA==.',
Un='Unaware:BAAANQADCgcJBgAAAA==.Uncletouchie:BAAANQADCgIIAgAAAA==.Unáware:BAAANQADCgUIBQAAAA==.',
Va='Vaeliir:BAAANQADCgUICQAAAA==.Valára:BAAANQABCgYIBAAAAA==.',
Ve='Vesani:BAAANQADCgQIBAAAAA==.',
Vi='Vinfuriating:BAAANQAECgEIAQAAAA==.Vinsamo:BAAANQADCgcIBwAAAA==.Violentjudge:BAABNQAECoEbAAIXAAgK0xqoXgBRAgAXAAgK0xqoXgBRAgAAAA==.Violla:BAAANQAECgYICwAAAA==.Virgocelest:BAAANQAECgYICwAAAA==.Viridion:BAAANQAECgUIDAAAAA==.Vivax:BAAANQAECgUICAAAAA==.',
Vo='Vonmack:BAAANQADCggICAAAAA==.Vorlos:BAAANQAECgcIDAABNQAECgkJHwAQAMQbAA==.',
Vr='Vreeg:BAAANQAECgYIEwAAAA==.',
Wh='Whiteflag:BAABNQAECoE0AAIXAAkKkiZOBADSAwAXAAkKkiZOBADSAwAAAA==.Whoopington:BAAANQAECgYIBwAAAA==.Whyamialive:BAACNQAFFIEPAAIBAAYKxSR1AQCKAgABAAYKxSR1AQCKAgA1AAQKgTUAAgEACQrNJnoAAPkDAAEACQrNJnoAAPkDAAAA.',
Wi='Wickedwolfin:BAAANQADCgYIBgAAAA==.Wiffles:BAAANQAECgUIBQABNQAFFAYICwAQAJQXAA==.Willowes:BAEANQADCggICAABNQAFFAUIDAAWAMgPAA==.Willowest:BAEANQAECgQIBgABNQAFFAUIDAAWAMgPAA==.Willowing:BAECNQAFFIEDAAICAAIK7A+EKACZAAACAAIK7A+EKACZAAA1AAQKgRUABAIACAoRGp1ZACgCAAIABwqgGZ1ZACgCAAMAAgq0GbxKAJQAACEAAQouAvEvACcAAAE1AAUUBQgMABYAyA8A.Willowish:BAECNQAFFIEMAAIWAAUKyA95DQCRAQAWAAUKyA95DQCRAQA1AAQKgTIAAxYACQrhIq4GAIEDABYACQrhIq4GAIEDAAsAAQoGCH9vADAAAAAA.Willowly:BAEANQAECgIIAgABNQAFFAUIDAAWAMgPAA==.Winterz:BAABNQAECoEbAAIgAAkK/hj2UwDIAgAgAAkK/hj2UwDIAgAAAA==.Wiskii:BAAANQAECgYIEwAAAA==.',
Wo='Woopecushion:BAAANQADCgIIAgAAAA==.Worio:BAAANQADCgYIDwAAAA==.',
Wy='Wytenha:BAAANQAECgUICwABNQAFFAYIEAAcAHIOAA==.Wytnarthom:BAAANQAECgcIBwABNQAFFAYIEAAcAHIOAA==.Wytohne:BAACNQAFFIEQAAMcAAYKcg54BAC/AQAcAAYKcg54BAC/AQAIAAEKfQKkCQA9AAA1AAQKgTUAAxwACQo1HmoLAAcDABwACQo1HmoLAAcDAAgAAQq+FMkrADoAAAAA.',
Xa='Xaree:BAAANQAECgYIEwAAAA==.Xariá:BAAANQADCgYIFAABNQAECgUIDAAJAAAAAA==.',
Xc='Xcat:BAABNQAECoEfAAIXAAkK4xRlfAABAgAXAAkK4xRlfAABAgAAAA==.',
Xy='Xydros:BAAANQABCggJDwAAAA==.Xymer:BAAANQAECgIIAwAAAA==.',
Yi='Yim:BAABNQAECoEaAAIXAAkKsB5FPQC5AgAXAAkKsB5FPQC5AgAAAA==.Yismypetdead:BAAANQAECgQIBAABNQAECgUIBgAJAAAAAA==.',
Yo='Yorshka:BAABNQAECoEsAAIWAAkKORQ3OgBdAgAWAAkKORQ3OgBdAgAAAA==.',
Yw='Ywach:BAAANQAECgcIDAABNQAECggIHwAKAHodAA==.',
['Yú']='Yúno:BAABNQAECoEfAAIKAAgKeh3mJgDHAgAKAAgKeh3mJgDHAgAAAA==.',
Za='Zaffhavoc:BAAANQADCgYIBgABNQADCggIDAAJAAAAAA==.Zaffylizen:BAAANQADCgYIBgABNQADCggIDAAJAAAAAA==.Zako:BAAANQADCgMIAwABNQAECgQICQAJAAAAAA==.Zalliea:BAAANQAECgUICgAAAA==.',
Ze='Zeff:BAAANQAECgIIAwAAAA==.',
Zn='Znåp:BAAANQADCgQIBAAAAA==.',
Zo='Zompt:BAAANQAECgIIBAAAAA==.Zorndk:BAAANQAECgYICwAAAA==.',
Zy='Zymar:BAAANQADCgMIAwABNQAECgIIAwAJAAAAAA==.',
['Ðë']='Ðëxx:BAAANQADCgQIBAAAAA==.',
['Õn']='Õni:BAAANQAFFAMIAwAAAA==.',
['Ön']='Öni:BAACNQAFFIEHAAIfAAMK2iHCAgAWAQAfAAMK2iHCAgAWAQA1AAQKgS0AAh8ACQoOJDMCAIQDAB8ACQoOJDMCAIQDAAAA.',
['Øm']='Ømêgá:BAABNQAECoEWAAMgAAgK+ALhCAFXAQAgAAgK+ALhCAFXAQAmAAEKdAH6DQAYAAAAAA==.',
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
