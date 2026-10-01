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

local lookup = {'DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','Paladin-Holy','Monk-Brewmaster','Rogue-Assassination','Unknown-Unknown','DemonHunter-Havoc','DeathKnight-Unholy','Shaman-Enhancement','Evoker-Preservation','DeathKnight-Frost','Priest-Holy','Paladin-Retribution','Druid-Feral','Druid-Restoration','Warrior-Arms','Warrior-Fury','DemonHunter-Devourer','Rogue-Subtlety','Warrior-Protection','Monk-Windwalker','Monk-Mistweaver','Warlock-Affliction','Evoker-Devastation','Mage-Arcane','Paladin-Protection','Shaman-Elemental','Priest-Shadow','Hunter-Survival','Shaman-Restoration','DemonHunter-Vengeance',}
local provider = {region='US',realm='Ghostlands',name='US',type='weekly',zone=53,date='2026-09-29',data={Ad='Adobo:BAAANQADCgIIAgAAAA==.Adofian:BAAANQADCgUIBgAAAA==.',
Af='Aft:BAACNQAFFIEHAAIBAAMKwRNWEADgAAABAAMKwRNWEADgAAA1AAQKgSIAAgEACQpgJN8EAJIDAAEACQpgJN8EAJIDAAAA.',
Ai='Aislin:BAAANQAECgMIAwAAAQ==.',
Ak='Akumu:BAABNQAECoEYAAMCAAgKSxjuPwBTAgACAAgK8xfuPwBTAgADAAIKehg2TACEAAAAAA==.',
Al='Alarkin:BAACNQAFFIEKAAMEAAUKBg8xCQBjAQAEAAUKaAoxCQBjAQAFAAMKug3zDgDuAAA1AAQKgTAAAwQACQoZI9wHADoDAAQACQo2INwHADoDAAUABwq6IS4/AGUCAAAA.Alasmira:BAAANQADCggIEAAAAA==.Alcarde:BAABNQAECoEdAAIGAAgKcBV7BwAqAgAGAAgKcBV7BwAqAgAAAA==.Aldoan:BAAANQADCggIHAAAAA==.Aleza:BAAANQADCgEIAQAAAA==.Alialeman:BAAANQADCgQIBAAAAA==.Alistiri:BAAANQAECgUICwAAAA==.Alix:BAAANQAECgEJAQAAAA==.Allforge:BAAANQAECgIJBgAAAA==.Almina:BAAANQAECgYICwAAAA==.Alpal:BAACNQAFFIEKAAIHAAUKXQ9hCACLAQAHAAUKXQ9hCACLAQA1AAQKgTEAAgcACQp9HxsMAEcDAAcACQp9HxsMAEcDAAAA.',
Am='Ambs:BAAANQAECgUICwAAAA==.',
An='Analyse:BAAANQABCgIIAgAAAA==.Andalya:BAAANQAECgUIDAAAAA==.Andaria:BAAANQADCggJBQAAAA==.Angharrad:BAAANQADCgIIAgAAAA==.',
Ao='Aonani:BAAANQADCgcIFAAAAA==.',
Ap='Aprix:BAAANQAECgYJDAAAAA==.',
Ar='Aralyn:BAAANQADCgcIDQAAAA==.Arejay:BAAANQAECgQIBgAAAA==.Argeth:BAAANQAECgEIAQAAAA==.Arshika:BAAANQAECgUIEgAAAA==.Artek:BAAANQADCgMIAwAAAA==.Arthan:BAAANQADCgYIBwAAAA==.Arthonix:BAAANQAECgUJCQAAAA==.Arthurleywin:BAAANQAECgUIDwAAAA==.Arvis:BAAANQADCggIHwAAAA==.',
As='Asamia:BAACNQAFFIEQAAIIAAYKsxkEAQDvAQAIAAYKsxkEAQDvAQA1AAQKgSAAAggACQoRIs8DABwDAAgACQoRIs8DABwDAAAA.Ashaki:BAAANQAECgYIEQAAAA==.Astå:BAAANQADCggICAAAAA==.',
At='Athyná:BAAANQADCgIIAgAAAA==.',
Au='Auralius:BAAANQADCgQICAAAAA==.Auroramoon:BAAANQAECgUIBwAAAA==.',
Av='Avana:BAAANQADCgIIAgAAAA==.Avis:BAAANQAECgQIBAAAAA==.',
Aw='Awake:BAAANQAECgcJEwAAAA==.',
Ax='Axionar:BAAANQAECgcICwAAAA==.',
Az='Azshauria:BAAANQABCgYIDQAAAA==.Azurend:BAAANQAECgYIDQAAAA==.Azázél:BAAANQAECgUICQAAAA==.',
Ba='Badtimeboy:BAAANQAECgEIAQAAAA==.Baffle:BAAANQADCggIGQABNQAECgkJGgAJAKYcAA==.Bahula:BAAANQAECgYIEQAAAA==.Bainehuln:BAAANQAECgcICwAAAA==.Bastianos:BAAANQAECgYIEAAAAA==.Batsom:BAAANQABCgEIAQAAAA==.Battlecheeks:BAAANQADCgQIBAABNQAECgEIAQAKAAAAAA==.',
Be='Bellapearl:BAAANQAECgQIBQAAAA==.Bellmont:BAAANQAECgYIBwAAAA==.Belron:BAAANQAECgMIBgABNQAECggIIQALAIoMAA==.Bernes:BAABNQAECoEcAAMMAAkKORsSJABkAgAMAAkK9xYSJABkAgABAAYKNBz8OgDXAQAAAA==.',
Bi='Bigteef:BAAANQADCgUICQAAAA==.Birdhouse:BAAANQAECgQIDAAAAA==.',
Bl='Blackthornn:BAACNQAFFIEKAAIJAAUKCxnPAgDCAQAJAAUKCxnPAgDCAQA1AAQKgTEAAgkACQr5IToEAG0DAAkACQr5IToEAG0DAAAA.Blastin:BAAANQADCggICgAAAA==.Blastofel:BAAANQADCgUIBQAAAA==.Bloodcircus:BAAANQAECgYIBgAAAA==.Bloodorphan:BAAANQADCgIIAgABNQAECgkJJAANAFgfAA==.Bloodreign:BAAANQADCgYIBgAAAA==.Bloodworm:BAAANQADCgcIBwABNQAFFAUICgAFAJAhAA==.Blottros:BAAANQAECgUICQAAAA==.Blottzilla:BAACNQAFFIEKAAIOAAUKjwj9BwByAQAOAAUKjwj9BwByAQA1AAQKgTIAAg4ACQpAHXUGACYDAA4ACQpAHXUGACYDAAAA.Bluestreak:BAAANQADCggIEQAAAA==.',
Bo='Bobbyray:BAAANQADCggIDAAAAA==.Bobertbigg:BAABNQAECoEhAAIHAAgKJRx+KACRAgAHAAgKJRx+KACRAgAAAA==.Boratt:BAAANQADCgQIBAAAAA==.Bowbuttkick:BAACNQAFFIEKAAMFAAUKkCEwAwDiAQAFAAUKkCEwAwDiAQAEAAEKeQEeHgA2AAA1AAQKgRsAAwUACQpnJEYOAEsDAAUACQpnJEYOAEsDAAQAAgoHFLtYAHIAAAAA.Bowjangles:BAEANQAECgQJBAABNQAECggICgAKAAAAAA==.Boxiebrown:BAABNQAECoEhAAIFAAkKpBR3QgBaAgAFAAkKpBR3QgBaAgAAAA==.',
Br='Bralae:BAAANQAECgYIDAAAAA==.Breaya:BAAANQADCgYIDAAAAA==.Brewskiez:BAAANQADCgkJDQAAAA==.Bricktop:BAAANQADCgIIAgAAAA==.Brokuo:BAACNQAFFIENAAMPAAUKRB6eAwCCAQAPAAQK6CGeAwCCAQAMAAMKaws8CwDKAAA1AAQKgSMAAwwACQobJRUUAOMCAAwACQrGIxUUAOMCAA8ACAqeIEQQANMCAAAA.Broon:BAAANQADCgYIDQAAAA==.Brucellosis:BAABNQAECoEYAAMMAAgKFBvbLwAVAgAMAAcK1xzbLwAVAgAPAAEKvQ4ofgA/AAAAAA==.Brâgak:BAAANQADCgcIBwAAAA==.',
Bu='Bubbawoodkin:BAAANQAECgQIBgAAAA==.Buffpres:BAAANQAECgQIBAABNQAECgQICgAKAAAAAA==.Butchkween:BAAANQADCggIEAABNQAECgQIBwAKAAAAAA==.Buzzlez:BAACNQAFFIEKAAIQAAUK6w13CgCaAQAQAAUK6w13CgCaAQA1AAQKgTEAAhAACQrWIFUFAIQDABAACQrWIFUFAIQDAAAA.',
Ca='Camspally:BAAANQAECgMJAwAAAA==.Candyquartz:BAAANQADCgMIAwAAAA==.Carkleaschah:BAAANQADCgYICwABNQAECgQIBAAKAAAAAA==.Cat:BAAANQABCgIIAgAAAA==.',
Ch='Chaddrique:BAAANQABCgQIBgAAAA==.Chadgolas:BAAANQADCgIIAgAAAA==.Chadimir:BAAANQAECgQIBwAAAA==.Chahae:BAACNQAFFIEIAAMMAAMKASRlCAASAQAMAAMKASRlCAASAQAPAAEKQQcKFgA+AAA1AAQKgTIAAwwACQrLJi4CAMYDAAwACQrLJi4CAMYDAA8AAQrWJd5wAGgAAAAA.Channintotem:BAEANQAECgEIAQABNQAECgYIFwARAJ8eAA==.Cheerwine:BAABNQAECoEaAAMSAAgKPAruDwCZAQASAAgKPAruDwCZAQATAAYKZguRLwA3AQAAAA==.Cheezits:BAAANQAECgcIBwAAAA==.',
Cl='Clapdo:BAECNQAFFIEMAAMUAAQKCx2JDQBvAQAUAAQKCx2JDQBvAQAVAAEKwQswAwBWAAA1AAQKgSIAAxQACQq8JPYQAGUDABQACQq8JPYQAGUDABUAAQo1G48kAEMAAAAA.Clinician:BAAANQAECgcIDgAAAA==.',
Co='Commandor:BAAANQADCgEIAQAAAA==.Congolense:BAAANQAECgYICwAAAA==.Corbzz:BAAANQADCgMIAwAAAA==.Cougrogue:BAAANQAECgQICAAAAA==.Cowacusrex:BAAANQAECgEIAQAAAA==.',
Cp='Cptrisky:BAAANQABCgIIAgAAAA==.',
Cr='Crazzenburns:BAAANQAECgcIEwAAAA==.Creamer:BAAANQAECgcIEQAAAA==.Crunchin:BAABNQAECoEuAAMRAAkKQRdDYwAYAgARAAgKUxZDYwAYAgAHAAkK8AXJWwC6AQAAAA==.',
Cu='Cutedwarfxd:BAACNQAFFIENAAIBAAUKqCL8AwD9AQABAAUKqCL8AwD9AQA1AAQKgSMAAgEACQrhJeMCALUDAAEACQrhJeMCALUDAAAA.',
Da='Dakkadakka:BAAANQAECgMIAgAAAA==.Damane:BAAANQADCgUJBQABNQAECgQIBAAKAAAAAA==.Danìel:BAACNQAFFIEKAAILAAUKTBOmBQCZAQALAAUKTBOmBQCZAQA1AAQKgTAAAwsACQpJIs0HAFkDAAsACQpJIs0HAFkDABYACAq9FR4jAPQBAAAA.Darkarts:BAAANQADCgIIAgAAAA==.Darkmoore:BAAANQADCgUIBQAAAA==.Dartwo:BAAANQAECgUIBgAAAA==.',
De='Deadalicious:BAAANQAECgEIAQABNQAECggIIQALAIoMAA==.Deathspoons:BAACNQAFFIERAAIBAAYKaxw9AwAYAgABAAYKaxw9AwAYAgA1AAQKgSgAAwEACQoyIgIJAFUDAAEACQoyIgIJAFUDAAwAAQpKIUKZAGIAAAAA.Delecto:BAAANQAECgUICgAAAA==.Delmônico:BAAANQADCgYICgAAAA==.Delushoni:BAAANQADCgUIBQAAAA==.Dendalaus:BAACNQAFFIEKAAMXAAUKWiFBBQCVAQAXAAQKMSBBBQCVAQAJAAEK/SWHDwBpAAA1AAQKgS4AAxcACQocJocJAMUCABcABwoEJIcJAMUCAAkABArJJRstAL8BAAAA.Derkamental:BAAANQAECgIIAgAAAA==.Dextersmash:BAAANQADCgUIBQAAAA==.',
Di='Digallo:BAAANQADCggIGQAAAA==.Dimsumbun:BAAANQAECgUICgAAAA==.Dingledorf:BAAANQAECgYIEAAAAA==.Dinklebahmp:BAAANQAECgEIAQABNQAFFAUICgAYAPodAA==.Dinoxeye:BAAANQAECgQICQAAAA==.Discosdead:BAAANQADCgUIBQABNQAECgEIAQAKAAAAAA==.',
Do='Donut:BAAANQADCgMIAwAAAA==.',
Dr='Draacarys:BAAANQADCgQIBAAAAA==.Dragonpandas:BAAANQADCggJCAABNQAECgkJLQAMALAiAA==.Dramonk:BAACNQAFFIEIAAIZAAUKjQvQBQBOAQAZAAUKjQvQBQBOAQA1AAQKgSIAAhkACQpKIkcJABQDABkACQpKIkcJABQDAAAA.Dro:BAAANQABCgIIAgAAAA==.Drogbar:BAAANQABCgIIAgAAAA==.Druinlock:BAAANQADCgUIBQAAAA==.Druiske:BAAANQADCgIIAgABNQAECgQIBwAKAAAAAA==.',
Du='Dustydrewid:BAAANQADCgEIAQAAAA==.',
Dy='Dyre:BAAANQAECggICAAAAA==.',
Ei='Eir:BAABNQAECoEaAAIHAAgKMAn9YgCgAQAHAAgKMAn9YgCgAQAAAA==.',
El='Ellsnarl:BAAANQADCgYIBgAAAA==.Eltariel:BAAANQADCgQIBAABNQAECgQIBAAKAAAAAA==.',
Em='Emeraldjin:BAABNQAECoEcAAIaAAcKUyU6BwD0AgAaAAcKUyU6BwD0AgAAAA==.',
En='Ensera:BAAANQAECgQIBwAAAA==.',
Er='Eraesong:BAAANQADCgMIAwAAAA==.Erielyn:BAAANQAECgYIDwAAAA==.Ernet:BAAANQAECgUIEwAAAA==.',
Ex='Extraho:BAABNQAECoEaAAIQAAgKiCHoFAD7AgAQAAgKiCHoFAD7AgAAAA==.',
Fa='Fabled:BAACNQAFFIENAAQDAAUK3Rt2BgC5AAACAAMKIxnyEgD2AAADAAIKEh52BgC5AAAbAAEK8R8RBQBhAAA1AAQKgSMAAwMACQqOI78DAOcCAAMACAr6IL8DAOcCAAIABArLIyx/AIkBAAAA.Faeyice:BAAANQAECgYIEAAAAA==.',
Fe='Fearmachine:BAAANQADCggJFAABNQAECgcICwAKAAAAAA==.Feyden:BAAANQAECgQICAAAAA==.',
Ff='Ffxivcatgirl:BAAANQADCgQIBAABNQAFFAUIDQABAKgiAA==.',
Fi='Fielton:BAAANQADCgEIAQABNQAECgkJGAARABYiAA==.Fiiryazell:BAAANQAECgEIAQAAAA==.Fijaswarerth:BAAANQAECgUJCQAAAA==.Fijaswitcher:BAAANQAECgcIDgAAAA==.Fimbulvargr:BAAANQAECgYIEAAAAA==.Finiith:BAAANQAECgUJBgABNQAFFAUICgAEAAYPAA==.Finîth:BAAANQAECgUIBQABNQAFFAUICgAEAAYPAA==.Firedragön:BAAANQAECgEIAQAAAA==.',
Fl='Flogdanoggin:BAAANQADCgcIBwAAAA==.Flogurnoggin:BAAANQADCggIBQAAAA==.Fluffly:BAAANQADCggICAAAAA==.Fluffyokami:BAAANQAECgYIEwAAAA==.Flyingrodent:BAABNQAECoEbAAIcAAYKph4zEQAEAgAcAAYKph4zEQAEAgAAAA==.',
Fo='Foneer:BAAANQAECgYIEwAAAA==.Forestsky:BAAANQAECgYIDAAAAA==.',
Fr='Freezepop:BAABNQAECoEdAAIdAAgKdyBWQgDeAgAdAAgKdyBWQgDeAgAAAA==.Frenchieboi:BAAANQAECgUIBQABNQAECgcIEQAKAAAAAA==.Frenchielock:BAAANQAECgcIEQAAAA==.Frenchthyr:BAAANQAECgUIDQABNQAECgcIEQAKAAAAAA==.Frostbeast:BAAANQADCgEIAQAAAA==.',
Ga='Gaden:BAAANQAECgQIBgAAAA==.Galdiian:BAAANQAECgIIAgAAAA==.Gatebtch:BAAANQAECgUIBQAAAA==.Gawdspet:BAACNQAFFIEGAAMDAAMK0w2vDgB5AAACAAIKkBEsHwChAAADAAIKWwOvDgB5AAA1AAQKgSgAAwIACQqpHi5EAEUCAAIABwoNHi5EAEUCAAMABAoZFzMoACEBAAAA.',
Gh='Ghosi:BAABNQAECoEaAAMeAAkKGRVkEABKAgAeAAkKGRVkEABKAgARAAEKegn0SgE0AAAAAA==.',
Gl='Glaivier:BAAANQAECgMIBgAAAA==.Glitchhunt:BAAANQAECgUIBQAAAA==.',
Go='Goodtimeboy:BAAANQADCgYIBwAAAA==.Goregrind:BAABNQAECoEeAAIMAAkKByPcCABWAwAMAAkKByPcCABWAwAAAA==.Gorgeous:BAAANQADCgIIAgAAAA==.Gorius:BAAANQADCggIHQAAAA==.',
Gr='Grampman:BAAANQAECgYIBgAAAA==.Gremory:BAAANQAECgYIDQAAAA==.Grimholt:BAAANQADCgQIBgAAAA==.',
Gu='Guldank:BAAANQAECgUICgAAAA==.Guretta:BAAANQAECgYIEAAAAA==.',
Gw='Gwynhwyvar:BAAANQAECgQICAAAAA==.',
Ha='Haeneros:BAAANQAECgcIDgAAAA==.Handmemytank:BAAANQAECgIJAwABNQAECgkJHwAFAC8kAA==.Harumi:BAAANQAECgUIDwAAAA==.',
He='Healeta:BAAANQAECgMIAwAAAA==.Hearo:BAAANQAECgEIAQAAAA==.Heavyhead:BAAANQAECgIJAgAAAA==.Hedgehog:BAABNQAECoEgAAIaAAgKSQoTGwB1AQAaAAgKSQoTGwB1AQAAAA==.Heightning:BAAANQAECgQIBgAAAA==.Heisenberf:BAACNQAFFIEJAAIdAAUKRQdTFQBvAQAdAAUKRQdTFQBvAQA1AAQKgTAAAh0ACQp3H+wpACQDAB0ACQp3H+wpACQDAAAA.Hextrathicc:BAABNQAECoEmAAICAAgK8xkLMwCCAgACAAgK8xkLMwCCAgAAAA==.',
Ho='Hofnarr:BAAANQAECggIDgAAAA==.Holybuttkick:BAABNQAECoEZAAQeAAgKWh4QEwAiAgAeAAYKPCAQEwAiAgAHAAcKOQ8baQCMAQARAAEK4xYPNQFKAAABNQAFFAUICgAFAJAhAA==.Hoozurdaddy:BAABNQAECoEaAAIfAAgKcRNjQwAbAgAfAAgKcRNjQwAbAgAAAA==.',
Ia='Iamdownhere:BAAANQABCgYICgAAAA==.',
Ic='Icê:BAAANQAECgcIEgAAAA==.',
Ig='Igamm:BAAANQADCgYIDAAAAA==.Ignatius:BAAANQAECgMIBQAAAA==.Igniting:BAABNQAECoEjAAIdAAgKCRpXYwCJAgAdAAgKCRpXYwCJAgABNQAECgMIBgAKAAAAAA==.',
Ik='Ikillyoutoo:BAAANQAECgUICwAAAA==.Ikki:BAAANQAECggJCgAAAA==.',
Il='Illuzions:BAAANQADCgUIBQAAAA==.',
Im='Impenetrable:BAAANQADCgcIBwAAAA==.Impression:BAACNQAFFIENAAIHAAUK5iIhAwAUAgAHAAUK5iIhAwAUAgA1AAQKgR4AAgcACQqTJlwAAPMDAAcACQqTJlwAAPMDAAAA.Imprison:BAAANQAECgIIAwABNQAFFAUIDQAHAOYiAA==.',
In='Incarnated:BAAANQAECgcIDgAAAA==.Incursion:BAABNQAECoEZAAMHAAgK5REKSAAEAgAHAAgK5REKSAAEAgARAAYKKAlsvwAqAQAAAA==.Insayn:BAAANQADCgIIAgABNQAECgcIEgAKAAAAAA==.Inviçtus:BAAANQAECgQIBAAAAA==.',
Ir='Ironwolf:BAABNQAECoEgAAIYAAgK8glXFgBlAQAYAAgK8glXFgBlAQAAAA==.',
Ja='Jademoot:BAAANQAECgYIDAAAAA==.Jadis:BAAANQADCgUIBQAAAA==.Jaeaoria:BAAANQABCgIIAQAAAA==.Jaxblack:BAAANQADCggIEAAAAA==.Jaxurbate:BAAANQAECgIJAgAAAA==.Jaylaah:BAAANQAECgMIAwAAAA==.Jayvlyn:BAAANQAECgIIAwABNQAECgUIBgAKAAAAAA==.',
Jj='Jjman:BAAANQAECgYIBwABNQAECgkJGAARABYiAA==.Jjuicyfruit:BAAANQADCgYJEgAAAA==.',
Jo='Joftokal:BAAANQAECgcIEgAAAA==.Jokesonme:BAAANQAECgEIAQAAAA==.Jonebonejovi:BAAANQADCgIIAgAAAA==.Jorabna:BAAANQADCgYICgAAAA==.Joyboy:BAAANQAECgcJEwAAAA==.',
Ka='Kakiso:BAAANQAECgUIEgAAAA==.Kalanash:BAAANQADCgUIBQAAAA==.Kalim:BAAANQADCgIIAgAAAA==.Kaloneras:BAAANQADCgYICAAAAA==.Kattle:BAABNQAECoEsAAINAAkKaCNGAgB7AwANAAkKaCNGAgB7AwAAAA==.',
Ke='Kellistus:BAAANQADCgUICQAAAA==.Keyrasky:BAAANQAECgIIAgAAAA==.',
Kh='Khailyn:BAAANQADCgIJAgAAAA==.',
Ki='Kikuu:BAAANQAECgcIEwAAAA==.Kin:BAAANQADCggICwAAAA==.Kincaid:BAAANQABCgIIAgAAAA==.Kiradanna:BAABNQAECoEkAAIWAAkKshvJDwDQAgAWAAkKshvJDwDQAgAAAA==.Kiroa:BAAANQAECgUICQAAAA==.Kitå:BAEANQAECggICgAAAA==.Kiyoshiru:BAAANQADCgUIBQAAAA==.',
Kn='Knoks:BAAANQAECgYIDwAAAA==.Knotty:BAAANQAECgEIAQAAAA==.',
Ko='Koff:BAACNQAFFIEIAAIaAAQKMiY/AgC7AQAaAAQKMiY/AgC7AQA1AAQKgRoAAhoACQpPJWwBAKQDABoACQpPJWwBAKQDAAAA.Koino:BAAANQADCggIEAAAAA==.Koreshei:BAAANQAECgMIAwAAAA==.',
Kr='Krixxus:BAAANQAECgQJBwAAAA==.',
Ku='Kuni:BAAANQAECgYIEAAAAQ==.Kurius:BAAANQAECgIIAgAAAA==.Kuzan:BAAANQAECgUICAAAAA==.',
Ky='Kylian:BAAANQAECgQIBAABNQAECgkJJAAWALIbAA==.',
La='Lamynx:BAAANQAECgUIEAAAAA==.Lazydragon:BAAANQAECgcIEAAAAA==.',
Le='Lelouch:BAAANQAECgMIAwAAAA==.Leone:BAAANQAECgQIBAABNQAECggIGAACAEsYAA==.',
Li='Liberation:BAABNQAECoEXAAIWAAcK/RS5JADlAQAWAAcK/RS5JADlAQAAAA==.Lilgirlblue:BAAANQAECgcIEgAAAA==.Lilreggie:BAAANQADCggIFAAAAA==.Lilvoids:BAABNQAECoEqAAMDAAkKdwrgHQBvAQADAAcKUAngHQBvAQACAAYKnQjImgA+AQAAAA==.Lineste:BAAANQAECgYIDQAAAA==.Lion:BAAANQAECgYJDgAAAA==.',
Ll='Llyolis:BAAANQAECgIIAgABNQAECgQJBwAKAAAAAA==.',
Lo='Loldie:BAAANQAECgUICAAAAA==.Lonepanda:BAACNQAFFIEKAAIYAAUK+h3vAACyAQAYAAUK+h3vAACyAQA1AAQKgTEAAhgACQoqJfQAALoDABgACQoqJfQAALoDAAAA.Lorwynx:BAABNQAECoEoAAIdAAkKnCCdHwBHAwAdAAkKnCCdHwBHAwAAAA==.',
Lu='Luciliv:BAAANQADCgYIBgABNQAECgcIEgAKAAAAAA==.Lunado:BAAANQADCgUIBwAAAA==.Lupinaea:BAAANQAECgMIAwAAAA==.',
Lv='Lvcifur:BAAANQABCgQIBAAAAA==.',
Ma='Maalk:BAAANQADCgQIBAAAAA==.Mabellah:BAAANQADCggIMgAAAA==.Maemikyu:BAABNQAECoEzAAIQAAgKSyGvGwDSAgAQAAgKSyGvGwDSAgAAAA==.Magebuttkick:BAAANQADCgQIBAABNQAFFAUICgAFAJAhAA==.Magusultimis:BAAANQAECgYIDAAAAA==.Mahöshöjo:BAAANQADCggIEgAAAA==.Maintank:BAAANQAECgUIDgAAAA==.Makepoop:BAABNQAECoEgAAIgAAgKaiLmCwD/AgAgAAgKaiLmCwD/AgAAAA==.Maloa:BAAANQADCgYIBgAAAA==.Manbomanbo:BAAANQAECgQIBAABNQAECggIBAAKAAAAAA==.Marianita:BAABNQAECoEXAAMLAAkKcR4YEADsAgALAAkKcR4YEADsAgAWAAEKfhWxVgA4AAAAAA==.Maureen:BAAANQADCgUIBQAAAA==.',
Me='Mediarahan:BAAANQAECgEIAQAAAA==.Melfist:BAAANQAECgQIBwAAAA==.Melphis:BAAANQADCgIIAgAAAA==.Melysse:BAAANQAECgYIDgAAAA==.Mendocino:BAAANQADCgcIEAAAAA==.Mereo:BAAANQAECgUICAAAAA==.',
Mi='Mikiko:BAABNQAECoEbAAIfAAcKIg/HYwChAQAfAAcKIg/HYwChAQAAAA==.Mikto:BAAANQADCgEJAQAAAA==.Millcreek:BAAANQAECgYIDQAAAA==.Milliananeko:BAAANQADCgUICQABNQAECgUICQAKAAAAAA==.Miracat:BAAANQAECgQIBgAAAA==.Missindragon:BAAANQAECgcIEgAAAA==.',
Mo='Moomoohead:BAAANQADCgMIBAABNQAECgEIAQAKAAAAAA==.Morberto:BAAANQABCggICgAAAA==.Morianne:BAAANQADCgQIBAAAAA==.Mormel:BAAANQAECgYIEAAAAA==.Morticus:BAAANQAECgQICAAAAA==.',
Ms='Msthea:BAAANQAECgUIBwAAAA==.',
['Mä']='Mälina:BAAANQADCggIEgAAAA==.',
Na='Narial:BAAANQADCgIIAQAAAA==.Narrthas:BAAANQAECgUIBQAAAA==.Narru:BAACNQAFFIEHAAIFAAUKsRJyBQCgAQAFAAUKsRJyBQCgAQA1AAQKgScABAUACQqvJM8FAJoDAAUACQqvJM8FAJoDAAQABQrqCss+APQAACEABArhCqQLAMEAAAAA.',
Ne='Nebyula:BAAANQAECgQJBAAAAA==.',
Ni='Nizuno:BAAANQADCgYIBgAAAA==.',
No='Norieka:BAAANQAECgUIBwAAAA==.Norvasc:BAAANQADCgEIAQAAAA==.Noskillidan:BAAANQAECgEIAQABNQAFFAUICQAdAEUHAA==.Notknoks:BAAANQADCggICAAAAA==.',
Nu='Numinous:BAAANQAECgIIAgABNQAECggIHQAUAOQXAA==.',
Ny='Nykoleus:BAAANQAECgYICQAAAA==.Nylokar:BAAANQADCgQIBAAAAA==.',
Oa='Oatbarrel:BAAANQADCgIIAgAAAA==.Oatbreaker:BAAANQADCgYICgAAAA==.',
Og='Oggoat:BAAANQAECgMIAgAAAA==.',
Oz='Ozyy:BAAANQADCgYIBgAAAA==.',
Pa='Painindaazz:BAAANQADCgYIEgAAAA==.Pallygranny:BAEBNQAECoEXAAIRAAYKnx40cADxAQARAAYKnx40cADxAQAAAA==.Pawptart:BAAANQABCgQIBAAAAA==.',
Ph='Phyntom:BAAANQAECgEIAQAAAA==.',
Pi='Pibbs:BAACNQAFFIEFAAIdAAMKEROyIQD8AAAdAAMKEROyIQD8AAA1AAQKgSIAAh0ACQovIZMxAAwDAB0ACQovIZMxAAwDAAAA.',
Pl='Plaguepanda:BAABNQAECoEtAAQMAAkKsCLkDAAqAwAMAAkKfSLkDAAqAwAPAAkK3Rs9DwDfAgABAAEKFRp8qQA4AAAAAA==.Platinumcas:BAAANQADCgcIEwAAAA==.Pluribus:BAAANQADCgcIDgAAAA==.',
Po='Poohonroids:BAAANQAECgUICwAAAA==.Poppatroll:BAAANQADCggIEgAAAA==.',
Pr='Priestpvp:BAAANQADCggICQAAAA==.Priva:BAAANQADCgcIBwAAAA==.Protagoras:BAAANQAECgEIAgAAAA==.',
['Pä']='Pänz:BAAANQAECgYIDAAAAA==.',
Ra='Rafig:BAACNQAFFIEKAAIdAAUKsCAgCgDoAQAdAAUKsCAgCgDoAQA1AAQKgTEAAh0ACQqaJosAAAAEAB0ACQqaJosAAAAEAAAA.Ragefyre:BAAANQAECgIJAgAAAA==.Ralii:BAAANQADCgUIBQAAAA==.Ralobii:BAAANQAECgcJDQABNQADCgUIBQAKAAAAAA==.Ramellis:BAAANQADCgMIAwAAAA==.Ramses:BAACNQAFFIEFAAIfAAMKSgQuEwDNAAAfAAMKSgQuEwDNAAA1AAQKgSgAAx8ACQpaFBVFABQCAB8ACApnFBVFABQCACIACQqLD1hOANkBAAAA.Ratbasterd:BAAANQADCgQIBAAAAA==.Rats:BAAANQAECgIIAgAAAA==.Rayve:BAAANQABCgIIAgAAAA==.Rayy:BAABNQAECoEWAAILAAkK5R6CCQBAAwALAAkK5R6CCQBAAwAAAA==.',
Re='Reeji:BAAANQAECgMIAwAAAA==.Reinerbraun:BAAANQADCgcICAAAAA==.Renade:BAABNQAECoEUAAIJAAYK6RNsMQChAQAJAAYK6RNsMQChAQAAAA==.Rexx:BAAANQADCgMIAwAAAA==.Reywhite:BAAANQAECgEIAQABNQAECgQICAAKAAAAAA==.',
Rh='Rhazzah:BAAANQADCgcIBwAAAA==.',
Ri='Rigidsxz:BAAANQADCgUIBQAAAA==.Riskymonk:BAAANQADCgIIAgAAAA==.Riskyshammy:BAABNQAECoEtAAMiAAgKlhzsKwBzAgAiAAgKlhzsKwBzAgAfAAEKYghRCQErAAAAAA==.Riteaid:BAAANQAECgMICAAAAA==.',
Ro='Robe:BAAANQAECgIJAwABNQAECgUICQAKAAAAAA==.Rolexor:BAAANQADCgEIAQAAAA==.Ronok:BAAANQAECgcIDAAAAA==.Rorthach:BAAANQAECgEIAQAAAA==.Roru:BAABNQAECoErAAMCAAgKphVRSwAsAgACAAgKphVRSwAsAgADAAQK6wKuSgCJAAAAAA==.Roseire:BAAANQAECgQICAAAAA==.Rosethebrute:BAABNQAECoEmAAIUAAgKaB2VPQCZAgAUAAgKaB2VPQCZAgAAAA==.Rosetheholy:BAAANQAECgcIEgABNQAECggIJgAUAGgdAA==.Rougeloving:BAABNQAECoEYAAIXAAkKSBmCDACSAgAXAAkKSBmCDACSAgAAAA==.',
Ru='Ruler:BAAANQAECgYIDAAAAA==.Ruli:BAABNQAECoEmAAIFAAkK8RtLIgDVAgAFAAkK8RtLIgDVAgAAAA==.Rusticdiino:BAAANQADCgEIAQABNQAECggIHgAfAAIeAA==.',
Ry='Ryshin:BAABNQAECoEqAAMJAAkK/BYAGQBiAgAJAAkK/BYAGQBiAgAXAAUK7wejLQAbAQAAAA==.',
['Rø']='Rørs:BAAANQADCgcIBwAAAA==.',
Sa='Sabeck:BAABNQAECoEYAAIRAAkKFiLPFQBLAwARAAkKFiLPFQBLAwAAAA==.Safi:BAAANQADCggICAAAAA==.Saltine:BAEANQAECgEIAQABNQAECggICgAKAAAAAA==.Sanctano:BAAANQAECgUICwAAAA==.Saneras:BAAANQADCgYJCQAAAA==.Sapdo:BAEANQAECgYIBgABNQAFFAQIDAAUAAsdAA==.Sarshia:BAAANQADCgYJCAAAAA==.Sayn:BAAANQAECgcIEgAAAA==.',
Sc='Schultzies:BAAANQAECgcIEAAAAA==.',
Sd='Sdog:BAAANQAECgIIAQAAAA==.',
Se='Seanboyymage:BAABNQAECoEqAAIdAAkKYhsIRQDYAgAdAAkKYhsIRQDYAgAAAA==.Seina:BAAANQAECgYIEAAAAA==.Sensei:BAAANQAECgEIAQAAAA==.Sephirofl:BAAANQAECgQICQAAAA==.Seulrene:BAABNQAECoEXAAIMAAYK2BtsQAC1AQAMAAYK2BtsQAC1AQAAAA==.',
Sh='Shamlaw:BAAANQAECgYIEQAAAA==.Shammydavis:BAAANQAECgIIAgAAAA==.Shampayn:BAAANQAECgUIBwAAAA==.Shankiee:BAAANQABCgIIAgAAAA==.Shanti:BAAANQAECgYIDwAAAA==.Shhuffle:BAABNQAECoEaAAMJAAkKphxqEQCwAgAJAAgKJB5qEQCwAgAXAAQK1BJYLQAeAQAAAA==.Shieldmommy:BAAANQAECgUIBQABNQAFFAUICQAdAEUHAA==.Shiv:BAAANQAECgUIBgAAAA==.Shockuse:BAAANQAECgQIBAAAAA==.Shorukin:BAAANQADCgMJAwAAAA==.Shupasins:BAABNQAECoEoAAQiAAgKDR5aIQCsAgAiAAgKDR5aIQCsAgAfAAgK5xafQwAaAgANAAIKKw0pJACQAAAAAA==.Shyamablue:BAAANQAECgYIDAAAAA==.',
Si='Silvercas:BAAANQAECgUIEAAAAA==.Simpleyfire:BAABNQAECoEeAAMfAAgKAh4bJwCrAgAfAAgKAh4bJwCrAgAiAAcKyRHjXwCYAQAAAA==.',
Sk='Skullet:BAAANQAECgYIEQAAAA==.Skurmpls:BAAANQADCgcIBwABNQAECgQICQAKAAAAAA==.',
Sl='Slimshadyy:BAAANQADCgQIBQAAAA==.Slurpee:BAAANQAECgYIEwAAAA==.',
Sm='Smooth:BAABNQAECoEhAAMdAAgKiRtvYQCOAgAdAAgK9xpvYQCOAgAGAAQKNhJ2GQDhAAAAAA==.',
Sn='Snaphance:BAAANQAECgYIDAAAAA==.Sneekypete:BAAANQADCgYIBgAAAA==.Sniffer:BAAANQAECgYICgAAAA==.Sniparcat:BAAANQADCgIIAgAAAA==.Snipercat:BAABNQAECoEXAAIUAAgKhw3meADcAQAUAAgKhw3meADcAQAAAA==.Snuffles:BAAANQAECgYIDwAAAA==.Snøkie:BAAANQADCgcIDQAAAA==.',
So='Solange:BAAANQADCgYIBgAAAA==.Sorscha:BAAANQADCggIDwAAAA==.',
Sp='Spammy:BAABNQAECoEZAAMHAAkKwhRnMQBlAgAHAAkKwhRnMQBlAgARAAEKlAhlRAE4AAAAAA==.Sparlyy:BAACNQAFFIEKAAMgAAUKWR0FBQCZAQAgAAQKlCMFBQCZAQAQAAEKsh5rIQBeAAA1AAQKgS8AAyAACQqhJmgAAPEDACAACQqhJmgAAPEDABAAAQpdC37IADIAAAAA.Spectrality:BAAANQAECgEIAQABNQAECgUICQAKAAAAAA==.',
Ss='Sswordy:BAACNQAFFIEKAAIFAAUKAhHPBQCYAQAFAAUKAhHPBQCYAQA1AAQKgT4AAgUACQolI7MEAKcDAAUACQolI7MEAKcDAAAA.Sswordyvani:BAAANQADCgYIDAABNQAFFAUICgAFAAIRAA==.',
St='Stimulus:BAAANQAECgYIEQAAAA==.Stinkynuuts:BAAANQADCggIHAAAAA==.Stompy:BAAANQAECgEIAQAAAA==.Stormcloak:BAAANQADCggIDgAAAA==.Stormfang:BAAANQAECgMJBAAAAA==.',
Su='Sumbadvoodoo:BAAANQADCgEIAQAAAA==.Sunkist:BAAANQAECgUIDQAAAA==.Sunwing:BAAANQADCgUJBQAAAA==.Sureina:BAAANQADCgQIAwAAAA==.Surlym:BAABNQAECoEcAAIaAAgKxSQvBABCAwAaAAgKxSQvBABCAwAAAA==.',
Sw='Switchglaive:BAABNQAECoEhAAMLAAgKigzuMQC7AQALAAgKAAzuMQC7AQAjAAcKvAgmEgAlAQAAAA==.',
Sy='Sylphie:BAAANQAECgIIAgAAAA==.Symphemon:BAABNQAECoEpAAMWAAkKBA9bIAAPAgAWAAkKkw5bIAAPAgALAAgKfQrJNwCNAQAAAA==.Symphoid:BAAANQAECgQICAAAAA==.Syseloris:BAABNQAECoEVAAMjAAcK4hqKCAARAgAjAAcK4hqKCAARAgALAAUKCRERQQBGAQAAAA==.Sythion:BAABNQAECoEgAAMcAAkKgBSUDABnAgAcAAkKgBSUDABnAgAOAAcKlBDRHgCgAQAAAA==.',
['Sâ']='Sâlisbury:BAAANQADCgYIDAAAAA==.',
['Së']='Sëphy:BAAANQAECgEIAQAAAA==.',
Ta='Taediris:BAAANQADCgUICAAAAA==.Taliiha:BAAANQAECgUIBgAAAA==.Tanao:BAAANQAECgIIAgAAAA==.',
Te='Teenieween:BAAANQADCgIIAgAAAA==.Tengenuzui:BAAANQADCgEIAQAAAA==.Tenshi:BAAANQAECggIEAAAAA==.Terravesh:BAAANQADCgIIAgAAAA==.',
Th='Thenavigator:BAAANQAECgQIBQAAAA==.Thopegor:BAAANQAECgIJAgAAAA==.Thundergunt:BAAANQAECgEIAQABNQAECggIIQAHACUcAA==.',
Ti='Tianjin:BAAANQAECgEIAQAAAA==.Tickslap:BAAANQADCgcIBwAAAA==.Timid:BAAANQADCgIIAgAAAA==.Tintaglia:BAAANQAECgYIDQAAAA==.Tiqtaqto:BAAANQADCgIIAgAAAA==.Tivali:BAAANQADCgIIAgAAAA==.',
To='Toaster:BAAANQAECgUICgAAAA==.Tober:BAAANQADCgcIFQAAAA==.Toni:BAAANQADCgcIDwAAAA==.Toodles:BAAANQADCgUIBQAAAA==.',
Tr='Trust:BAAANQAECgcIEgAAAA==.',
Tu='Tunawhale:BAAANQAECgEJAQAAAA==.',
Tw='Twickenham:BAAANQADCgMIAwAAAA==.',
Ty='Tyloriavis:BAAANQAECgMIBQAAAA==.',
Ul='Ulfberht:BAAANQADCggICwAAAA==.Ulfin:BAAANQADCgUIBQABNQAECgYIDAAKAAAAAA==.Ultramind:BAAANQADCgUIBQAAAA==.',
Um='Umbras:BAAANQADCgIIAgAAAA==.',
Un='Unaware:BAAANQADCgcJBgAAAA==.Uncletouchie:BAAANQADCgIIAgAAAA==.Unáware:BAAANQADCgUIBQAAAA==.',
Va='Vaeliir:BAAANQADCgUICQAAAA==.Valára:BAAANQABCgYIBAAAAA==.',
Ve='Vesani:BAAANQADCgQIBAAAAA==.',
Vi='Vinfuriating:BAAANQAECgEIAQAAAA==.Vinsamo:BAAANQADCgcIBwAAAA==.Violentjudge:BAAANQAECgcIEgAAAA==.Violla:BAAANQAECgIIBQAAAA==.Virgocelest:BAAANQAECgUICQAAAA==.Viridion:BAAANQAECgQICgAAAA==.Vivax:BAAANQAECgUICAAAAA==.',
Vo='Vorlos:BAAANQAECgcIDAABNQAECgkJHAAMADkbAA==.',
Vr='Vreeg:BAAANQAECgYIDQAAAA==.',
Wh='Whiteflag:BAABNQAECoEvAAIRAAkKdCaoBADHAwARAAkKdCaoBADHAwAAAA==.Whoopington:BAAANQAECgYIBQAAAA==.Whyamialive:BAACNQAFFIEJAAIBAAUKfyOKAwANAgABAAUKfyOKAwANAgA1AAQKgTAAAgEACQrKJmgAAPkDAAEACQrKJmgAAPkDAAAA.',
Wi='Wickedwolfin:BAAANQABCgMIAwAAAA==.Willowes:BAEANQADCggICAABNQAFFAMIBwAQAJENAA==.Willowest:BAEANQAECgQIBAABNQAFFAMIBwAQAJENAA==.Willowing:BAEANQAFFAIIAgABNQAFFAMIBwAQAJENAA==.Willowish:BAECNQAFFIEHAAIQAAMKkQ3AEwD3AAAQAAMKkQ3AEwD3AAA1AAQKgS0AAxAACQrhItIEAIsDABAACQrhItIEAIsDACAAAQoGCA1iADIAAAAA.Winterz:BAABNQAECoEZAAIdAAgKyBl6aAB8AgAdAAgKyBl6aAB8AgAAAA==.Wiskii:BAAANQAECgYIDQAAAA==.',
Wo='Worio:BAAANQADCgYIDwAAAA==.',
Wy='Wytenha:BAAANQAECgUJBgABNQAFFAUICgAZAMMMAA==.Wytnarthom:BAAANQAECgYIBgABNQAFFAUICgAZAMMMAA==.Wytohne:BAACNQAFFIEKAAMZAAUKwww2BQBxAQAZAAUKwww2BQBxAQAIAAEKfQIjCAA+AAA1AAQKgTAAAxkACQr4HN0MANkCABkACQr4HN0MANkCAAgAAQq+FC8nADsAAAAA.',
Xa='Xaree:BAAANQAECgYIDQAAAA==.Xariá:BAAANQADCgUIDgABNQAECgQIBwAKAAAAAA==.',
Xc='Xcat:BAABNQAECoEeAAIRAAkKnxNcaAAIAgARAAkKnxNcaAAIAgAAAA==.',
Xy='Xydros:BAAANQABCggJDwAAAA==.Xymer:BAAANQAECgEIAQAAAA==.',
Yi='Yim:BAAANQAECggIEgAAAA==.Yismypetdead:BAAANQAECgQIBAABNQAECgQJBwAKAAAAAA==.',
Yo='Yorshka:BAABNQAECoEjAAIQAAkKORRmLgBuAgAQAAkKORRmLgBuAgAAAA==.',
Yw='Ywach:BAAANQAECgQIBgAAAA==.',
['Yú']='Yúno:BAABNQAECoEZAAIfAAgKThukJwCpAgAfAAgKThukJwCpAgAAAA==.',
Za='Zaffhavoc:BAAANQADCgYIBgABNQADCggIDAAKAAAAAA==.Zaffylizen:BAAANQADCgYIBgABNQADCggIDAAKAAAAAA==.Zako:BAAANQADCgMIAwABNQAECgQICQAKAAAAAA==.Zalliea:BAAANQAECgQIBQAAAA==.',
Ze='Zeff:BAAANQAECgEIAQAAAA==.',
Zn='Znåp:BAAANQADCgQIBAAAAA==.',
Zo='Zompt:BAAANQAECgEIAgAAAA==.Zorndk:BAAANQAECgYICwAAAA==.',
Zy='Zymar:BAAANQADCgMIAwABNQAECgEIAQAKAAAAAA==.',
['Ðë']='Ðëxx:BAAANQADCgQIBAAAAA==.',
['Õn']='Õni:BAAANQAECgYIBgAAAA==.',
['Ön']='Öni:BAACNQAFFIEHAAIYAAMK2iH8AQAjAQAYAAMK2iH8AQAjAQA1AAQKgSwAAhgACQoOJH4BAJkDABgACQoOJH4BAJkDAAAA.',
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
