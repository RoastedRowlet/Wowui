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

local lookup = {'Druid-Restoration','Monk-Mistweaver','Unknown-Unknown','DeathKnight-Blood','Paladin-Protection','Paladin-Retribution','Warrior-Arms','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Mage-Fire','DeathKnight-Frost','Priest-Holy','Priest-Shadow','DemonHunter-Havoc','Paladin-Holy','DeathKnight-Unholy','Druid-Feral','Mage-Arcane','Mage-Frost','Shaman-Elemental','Warrior-Fury','Warrior-Protection','Druid-Balance','Evoker-Preservation','Shaman-Restoration','Rogue-Assassination','Druid-Guardian','Warlock-Affliction','Rogue-Subtlety','Evoker-Augmentation','Monk-Windwalker','Shaman-Enhancement','DemonHunter-Devourer','Priest-Discipline','Hunter-Survival',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abracanoobra:BAABNQAECn8aAAIBAAoKTxb5IAAhAgABAAoKTxb5IAAhAgAAAA==.Abuki:BAACNQAFFH8MAAICAAQKahhxAgAYAQACAAQKahhxAgAYAQA1AAQKfycAAgIACgryHm8JAPQCAAIACgryHm8JAPQCAAAA.',
Ai='Aiforix:BAAANQADCgcJBwAAAA==.',
Ak='Akagane:BAAANQADCgYIDAAAAA==.Akalla:BAAANQAECgUICQAAAA==.',
Al='Alfuric:BAAANQAECgUICgAAAA==.Aliviana:BAAANQADCgYIBgABNQAECgQICwADAAAAAA==.Altrois:BAABNQAECn8vAAIEAAoK8yAPCgBlAwAEAAoK8yAPCgBlAwAAAA==.',
Am='Amatrake:BAACNQAFFH8WAAIFAAcKdxR5AwDKAQAFAAcKdxR5AwDKAQA1AAQKfy0AAgUACgreHdUNAL0CAAUACgreHdUNAL0CAAAA.Amatsano:BAEANQAECgUICgAAAA==.Amorsith:BAABNQAECn8lAAMFAAoK2xtBAQCaAgAFAAoK2xtBAQCaAgAGAAYKwQxS9AA0AQAAAA==.Amurine:BAAANQADCggIAgAAAA==.Amyst:BAABNQAECn8jAAIHAAgKbSFHSQCuAgAHAAgKbSFHSQCuAgAAAA==.',
An='Angrycrack:BAAANQAECgcIEQAAAA==.Angusill:BAAANQAECgEIAQAAAA==.Animuggus:BAEANQAECgQIBwAAAA==.Anjunabeets:BAACNQAFFH8ZAAMIAAgKrBNyBgDuAQAIAAcKwRNyBgDuAQAJAAEKRBNEMABeAAA1AAQKfx8AAwgACgrGI0MaAIMCAAgACQp3I0MaAIMCAAkAAgoTGnQuAZAAAAAA.Anthran:BAABNQAECn8hAAMKAAgKLRAnKgArAQAKAAUKaRAnKgArAQALAAUKSQr04QAFAQAAAA==.',
Ao='Ao:BAAANQAECgIIBAAAAA==.',
Ap='Apexlegend:BAAANQAECgQIBAAAAA==.',
Ar='Arakin:BAAANQABCggJCgAAAA==.Arcon:BAAANQAECgQICgABNQAECgoKHQAMAHAWAA==.Arcscythe:BAABNQAECn8eAAINAAgK0BQ4AgA8AgANAAgK0BQ4AgA8AgAAAA==.Arctron:BAAANQAECgMIAwABNQAECgoKHQAMAHAWAA==.Arthanos:BAAANQADCgcIAQABNQAECgYIBwADAAAAAA==.Artoo:BAAANQAECgIIAgAAAA==.',
As='Ashesonly:BAABNQAECn80AAIOAAoK8xgdBAAxAgAOAAoK8xgdBAAxAgAAAA==.Assaulter:BAAANQADCgIIAgABNQAECgoKLwAJAIIfAA==.',
Au='Auramis:BAABNQAECn8xAAMPAAoKoCBrGAAUAwAPAAoKoCBrGAAUAwAQAAIKsQdtIgB6AAAAAA==.',
Az='Azariel:BAACNQAFFH8GAAIRAAMKMxZ7BwCmAAARAAMKMxZ7BwCmAAA1AAQKfysAAhEACgoHG2wQAB0DABEACgoHG2wQAB0DAAAA.Azrayel:BAAANQADCgUIBQAAAA==.',
Ba='Babydilla:BAACNQAFFH8WAAIEAAcKEiM0AwBkAgAEAAcKEiM0AwBkAgA1AAQKfy0AAgQACgpAJBsLAFsDAAQACgpAJBsLAFsDAAAA.Balgith:BAABNQAECn8aAAMSAAcKHQ5dMAAhAQASAAcKHQ5dMAAhAQAGAAEKAABzzAEhAAAAAA==.Balrus:BAAANQADCgEJAQAAAA==.Bam:BAAANQADCggICAAAAA==.Bannagad:BAABNQAECn8cAAMGAAkKuQkyuQCrAQAGAAkKuQkyuQCrAQASAAUKhAl3vQABAQAAAA==.Barthoun:BAAANQAECggIDAAAAA==.Battleburger:BAAANQAECgEIAwAAAA==.Bauchelaine:BAAANQAECgEIAgAAAA==.Bawitaba:BAAANQAECgUJEAAAAA==.',
Be='Benchknight:BAACNQAFFH8OAAQOAAcKXQ55DQAGAQAOAAUKwQt5DQAGAQATAAEKzRgbHQBfAAAEAAEKAABcMwAuAAA1AAQKfzcABA4ACgpwH1sSAPoCAA4ACgo3H1sSAPoCABMACApYGf9IAPMBAAQAAgotG6inAIMAAAAA.Beoron:BAACNQAFFH8HAAIUAAUKhRoQAgAVAQAUAAUKhRoQAgAVAQA1AAQKfzcAAhQACgo9JVMBAMQDABQACgo9JVMBAMQDAAAA.Bettyßastion:BAABNQAECn8iAAIGAAkKVREIXAANAQAGAAkKVREIXAANAQAAAA==.',
Bi='Big:BAAANQAECgQIBwAAAA==.Bigflex:BAAANQAECgUICAAAAA==.Bio:BAAANQAECggICwAAAA==.Bioenergy:BAAANQAECgEIAwABNQAECggICwADAAAAAA==.Biolysis:BAAANQAECgQIBgABNQAECggICwADAAAAAA==.',
Bl='Blesus:BAAANQAECgQIBQAAAA==.Blowtortch:BAABNQAECn8gAAMVAAkKSQmN8wCkAQAVAAkKlgiN8wCkAQAWAAEKggalRwA1AAAAAA==.',
Bo='Bolverkr:BAAANQAECgEIAQAAAA==.',
Br='Brageus:BAABNQAECn8VAAIXAAcK1Q9hkgB2AQAXAAcK1Q9hkgB2AQAAAA==.Brainmatter:BAAANQADCgMIBAAAAA==.Braintumor:BAABNQAECn8ZAAITAAcKIgkGfgAkAQATAAcKIgkGfgAkAQAAAA==.Brontag:BAABNQAECn8qAAQYAAoK8B1gBwCDAgAYAAkKRiBgBwCDAgAHAAgKeBY6oADMAQAZAAEKAACPQQA5AAAAAA==.Bruus:BAAANQADCggIEAAAAA==.',
Bu='Bugles:BAAANQAECgEIAQAAAA==.Buns:BAAANQAECgEIAgAAAA==.Butternutter:BAAANQAECgEIAQABNQAECgYICAADAAAAAA==.',
['Bé']='Béllas:BAAANQADCgYIBgAAAA==.',
Ca='Caissa:BAAANQADCgYIBgAAAA==.Caliboy:BAAANQAECgEIAgABNQAECgIIBQADAAAAAA==.Calißoy:BAAANQAECgIIBQAAAA==.Caneki:BAABNQAECn8aAAMPAAkKGRjXUQAuAgAPAAkKGRjXUQAuAgAQAAEKAAA+lAATAAAAAA==.Canekii:BAABNQAECn8VAAMSAAcKoxdGZQDoAQASAAcKoxdGZQDoAQAGAAEKAAChrAExAAABNQAECgkJGgAPABkYAA==.Casini:BAAANQAECgcIBwAAAA==.Cathrîne:BAAANQADCggICAAAAA==.',
Ce='Celticankou:BAAANQAECgUIBQAAAA==.Cerberus:BAACNQAFFH8IAAIJAAMK/R1zCgC+AAAJAAMK/R1zCgC+AAA1AAQKfyYAAgkACgoUIzENAHUDAAkACgoUIzENAHUDAAAA.',
Ch='Chaboomy:BAECNQAFFH8VAAIaAAcKcRWUCgDMAQAaAAcKcRWUCgDMAQA1AAQKfy8AAhoACgqnIvENAFsDABoACgqnIvENAFsDAAAA.Chevron:BAAANQAECgEIAQAAAA==.Chidori:BAAANQADCgUIBQAAAA==.Chips:BAABNQAECn8rAAIHAAgKRhB0nADVAQAHAAgKRhB0nADVAQAAAA==.Chloeswift:BAAANQAECgEIAQAAAA==.',
Co='Cobblerjr:BAAANQAECgIIAgAAAA==.Coffeemaker:BAABNQAECn8nAAQVAAoKqhjvjgBhAgAVAAoKqhjvjgBhAgANAAYKzQ/gBABMAQAWAAEKjh0mSAA0AAAAAA==.Conyay:BAAANQAECggIDwAAAA==.Cowploww:BAAANQADCggIDAAAAA==.',
Cr='Croissant:BAABNQAECn8iAAILAAgKwx7aOACpAgALAAgKwx7aOACpAgAAAA==.Cräsh:BAAANQADCgMIAwAAAA==.',
Cy='Cycko:BAAANQADCgUIBQAAAA==.Cytheria:BAAANQADCgQIBAABNQAECgYIBwADAAAAAA==.',
Da='Dalidan:BAAANQAECgUIBgABNQAECgoKIgAbAPMhAA==.Dalórien:BAAANQADCgUICgABNQAECgEIAgADAAAAAA==.Damaerin:BAAANQAECgUIDgAAAA==.Darkis:BAABNQAECn8YAAMBAAoKLQpxOgBMAQABAAkK/AZxOgBMAQAaAAgKJgQQbgASAQAAAA==.Darkseph:BAAANQAECgQICAABNQAECgUIDAADAAAAAA==.Darthjarjar:BAAANQADCgMIAwAAAA==.Dayy:BAACNQAFFH8SAAMXAAcKBBpuCgDEAQAXAAUKhhtuCgDEAQAcAAMKfAn9DQCfAAA1AAQKfzMAAxcACgpjJd4GALIDABcACgpjJd4GALIDABwAAgoYDPD5AHcAAAAA.',
De='Deathsteak:BAAANQADCggIDQAAAA==.Deepman:BAABNQAECn8iAAIdAAoKDBQ3JABmAgAdAAoKDBQ3JABmAgABNQAECgoKLwAJAIIfAA==.Delessia:BAAANQAECgcIBwAAAA==.Demonesque:BAAANQAECgEIAQAAAA==.Desy:BAAANQAECgYIDQAAAA==.',
Di='Diggersby:BAACNQAFFH8MAAIeAAQK/CK6AAAvAQAeAAQK/CK6AAAvAQA1AAQKfyMAAh4ACgr6ILwHAAcDAB4ACgr6ILwHAAcDAAAA.Disastrous:BAACNQAFFH8IAAIJAAMKVgeoCQDMAAAJAAMKVgeoCQDMAAA1AAQKfycAAgkACgraEsBcAF8CAAkACgraEsBcAF8CAAAA.',
Do='Doomangel:BAAANQAECgQIAwAAAA==.Doson:BAAANQAECgQIBAAAAA==.',
Dr='Dracthyr:BAAANQAECgEIAQABNQAECggICwADAAAAAA==.Drago:BAAANQAECgEIAQABNQAECgQIBQADAAAAAA==.Dragonbison:BAAANQAECgUICQAAAA==.Druidtime:BAAANQADCggIFQAAAA==.Drunkenmasta:BAAANQADCgIIAgABNQAECgoKLwAJAIIfAA==.',
['Dø']='Døc:BAABNQAECn83AAMcAAoKZBq6EADSAQAcAAkKYxq6EADSAQAXAAYKHRcueAC5AQAAAA==.',
Eg='Eggland:BAAANQAECgUICgAAAA==.',
Ei='Eielmolate:BAACNQAFFH8UAAILAAcKEQ1zCQDSAQALAAcKEQ1zCQDSAQA1AAQKfy0AAwsACgqVHo8fAAYDAAsACgqVHo8fAAYDAAoAAgrqDl1hAGIAAAAA.',
El='Eldranus:BAAANQAECgUICQAAAA==.',
En='Enimed:BAABNQAECn8xAAIEAAoK7RbOBQDoAQAEAAoK7RbOBQDoAQAAAA==.',
Er='Erutan:BAAANQAECgEIAQAAAA==.',
Eu='Eugenn:BAAANQADCggIEwAAAA==.',
Ev='Evil:BAACNQAFFH8IAAMKAAMKnxYSDwCXAAAKAAIKIhASDwCXAAALAAIKPBeNFABtAAA1AAQKfyoABAoACgp+IDMbAJMBAAsABwp4HkpkAC0CAAoABQpBIDMbAJMBAB8AAwpnIa8SAB8BAAAA.',
Fa='Falarion:BAAANQAECgYIBwAAAA==.Fam:BAABNQAECn81AAIVAAkKgyKYJgBGAwAVAAkKgyKYJgBGAwAAAA==.Fatherseph:BAAANQAECgUIDAAAAA==.',
Fi='Finkymcbinky:BAAANQAECgcIEAAAAA==.Finroz:BAAANQADCgQIBAAAAA==.Fisterdobble:BAABNQAECn8xAAIWAAoKJhdWBgCeAgAWAAoKJhdWBgCeAgAAAA==.',
Fl='Fleurdelys:BAAANQADCggIPQAAAA==.Florella:BAAANQADCgUIBwAAAA==.',
Fo='Foidhater:BAAANQADCgEIAQAAAA==.Forgedd:BAAANQAECgUIBQAAAA==.Forgeddemon:BAABNQAECn8pAAIMAAoKswiRBABGAQAMAAoKswiRBABGAQAAAA==.',
Fr='Frostborne:BAABNQAECn8kAAITAAkKChsGBgDTAQATAAkKChsGBgDTAQAAAA==.Frostheart:BAAANQABCgYIDAAAAA==.Frostystomp:BAAANQAECgcIBwABNQAFFAUIBwAUAIUaAA==.Frozenpickle:BAAANQADCgYIBwABNQAECgQIDAADAAAAAA==.',
Fu='Funeral:BAAANQAECggIEgABNQAECgoKLwAJAIIfAA==.',
Ga='Gamjee:BAAANQAECgUICQAAAA==.',
Ge='Gerkindk:BAAANQADCggICAAAAA==.',
Gh='Ghostly:BAAANQAECgEIAQAAAA==.',
Gl='Glyndin:BAAANQADCgcIDgAAAA==.',
Go='Goodboy:BAAANQAECgMIAwABNQAFFAQIDAAeAPwiAA==.Goodolrúss:BAAANQADCgYJEAAAAA==.',
Gr='Grackalackin:BAAANQAECgMICAAAAA==.Grassfedgeez:BAAANQAECgIIAgAAAA==.Greenxgoblin:BAAANQADCgEJAQAAAA==.Grizmaus:BAAANQAECggIDgAAAA==.',
Gu='Guilliman:BAABNQAECn8hAAIHAAkKQRmAIgB6AQAHAAkKQRmAIgB6AQAAAA==.Gulaj:BAABNQAECn8nAAIJAAkKpBPGOgBDAQAJAAkKpBPGOgBDAQAAAA==.Guldaniel:BAAANQADCggIDQAAAA==.',
['Gë']='Gënesis:BAAANQAECgYIDgAAAA==.',
Ha='Haloro:BAAANQADCgEIAQAAAA==.Ham:BAAANQAECgcICwAAAA==.',
He='Healgimp:BAABNQAECn8rAAIPAAoKeRnbLgCtAgAPAAoKeRnbLgCtAgAAAA==.',
Hi='Hiruken:BAAANQADCgcIEAAAAA==.',
Ho='Hope:BAEBNQAECn8XAAMBAAoKcBKnHwAvAgABAAoKcBKnHwAvAgAeAAEK6QMpeQALAAABNQAFFAcIGQAPAKQTAA==.Hortzel:BAAANQAECgUICQAAAA==.Hotrollz:BAAANQADCgUIBQABNQAECgcIIwAQAOMOAA==.Howdoidie:BAAANQAECgEIAQAAAA==.Howdoitotem:BAABNQAECn8jAAMXAAoKiBl6MgCwAgAXAAoKiBl6MgCwAgAcAAMK3geW+QB3AAAAAA==.',
Hu='Hulkx:BAAANQAECgQICwAAAA==.Humaa:BAABNQAECn8lAAIGAAgKARkxfQAwAgAGAAgKARkxfQAwAgAAAA==.Huntus:BAABNQAECn8uAAIJAAkK/BqZOwC3AgAJAAkK/BqZOwC3AgAAAA==.',
Hy='Hyperiøn:BAAANQADCgIIAgAAAA==.',
Ib='Ibcrootbeer:BAAANQAECgEIAQAAAA==.',
Ic='Icenaria:BAAANQADCggICAAAAA==.Icewiz:BAAANQABCgUIBQABNQAECgUICwADAAAAAA==.Icy:BAABNQAECn8YAAIHAAkKYReFYwBkAgAHAAkKYReFYwBkAgAAAA==.',
Im='Impale:BAAANQADCgMIAwAAAA==.Imperio:BAAANQAECgMIBQAAAA==.Impostor:BAABNQAECn8wAAIQAAoKfxs0DQAYAwAQAAoKfxs0DQAYAwAAAA==.',
Iz='Izuu:BAAANQAECgYIEQAAAA==.',
['Iç']='Içyhot:BAAANQADCgEIAQAAAA==.',
Ja='Jabrick:BAAANQAECgQJBQAAAA==.Jattin:BAAANQADCgYIDAAAAA==.Jawnski:BAAANQADCgUICQAAAA==.',
Ji='Jibjabjibjab:BAABNQAECn8sAAMdAAoKxRzJFQAZAQAgAAgKkBsWGwD+AQAdAAUK3RrJFQAZAQAAAA==.',
Jo='Joey:BAAANQADCgcIBwAAAA==.Joharin:BAABNQAECn8ZAAILAAcKhQ2eVQDYAAALAAcKhQ2eVQDYAAAAAA==.',
Jt='Jtabb:BAAANQABCgYICQAAAA==.',
Ju='Juroda:BAAANQADCgYIBgABNQAECgUIDAADAAAAAA==.',
Ka='Kankiro:BAAANQADCggIGAAAAA==.Kanstentin:BAAANQADCggICAAAAA==.Karram:BAAANQADCgQIBAAAAA==.',
Kc='Kcup:BAAANQADCgYIBgAAAA==.',
Ke='Kelamess:BAAANQAECgYIEgAAAA==.Kelemvor:BAAANQAECggIEgAAAA==.Ken:BAAANQADCgYIBgAAAA==.',
Kf='Kfp:BAAANQABCgEIAQAAAA==.',
Kh='Khandak:BAABNQAECn8dAAIEAAoKCBibGQAgAQAEAAoKCBibGQAgAQAAAA==.',
Ki='Kimmy:BAAANQAECgYIDwAAAA==.',
Kl='Kleenex:BAABNQAECn8hAAIWAAoK/RRWCABeAgAWAAoK/RRWCABeAgAAAA==.',
Ko='Koldiss:BAAANQADCgQIBAAAAA==.',
Kr='Krueger:BAAANQAECggIDAAAAA==.',
Ku='Kurisutina:BAAANQAECgYIDwABNQAFFAMICAAcAC4MAA==.Kushiel:BAAANQAECgEIAQAAAA==.',
Le='Leadblaster:BAABNQAECn8vAAIJAAoKgh+/FgBAAwAJAAoKgh+/FgBAAwAAAA==.Leethalfu:BAABNQAECn8aAAIMAAkKoBeqCQCEAgAMAAkKoBeqCQCEAgAAAA==.Leethalrot:BAAANQAECgEIAQABNQAECgkJGgAMAKAXAA==.Legosi:BAABNQAECn8eAAILAAcKLg+KUQDhAAALAAcKLg+KUQDhAAAAAA==.Leighroy:BAAANQAECgEIAQAAAA==.Lemegegen:BAABNQAECn8uAAILAAoKOh25DADlAQALAAoKOh25DADlAQAAAA==.Leviosa:BAAANQAECgYIBwAAAA==.',
Lh='Lhux:BAABNQAECn80AAIJAAoKGhyVDwD0AQAJAAoKGhyVDwD0AQABNQAECgkJGgAhANcNAA==.Lhuxi:BAABNQAECn8aAAIhAAkK1w0lAQCwAQAhAAkK1w0lAQCwAQAAAA==.',
Li='Lilbokchoy:BAAANQABCgQIBAAAAA==.Linkin:BAAANQABCgMIAwAAAA==.',
Lo='Loneassassin:BAAANQADCgQIBAAAAA==.Lorani:BAACNQAFFH8GAAIaAAQKhSDlFwDsAAAaAAQKhSDlFwDsAAA1AAQKfyUAAhoACgrLIiQMAGoDABoACgrLIiQMAGoDAAAA.',
Lu='Lurth:BAAANQADCgIIAgABNQAECgIIAgADAAAAAA==.',
Ly='Lyxxie:BAABNQAECn8oAAMOAAoK+BmyJQBmAgAOAAoK+BmyJQBmAgATAAUKCQvPjQDuAAAAAA==.',
Ma='Maelle:BAAANQAECgQIBAAAAA==.Mageus:BAAANQAECgIIAwAAAA==.Manafart:BAAANQADCgYIBgABNQAECggIKwAHAEYQAA==.Manbearpïg:BAAANQAECgQICAAAAA==.Matsumushi:BAABNQAECn8uAAMMAAkKzxPKDgAGAgAMAAgKWBbKDgAGAgAiAAgKdwY5EwASAQAAAA==.',
Mc='Mcnastyy:BAAANQADCgYICgAAAA==.',
Me='Mefesto:BAABNQAECn8dAAIVAAkKvg+DtgAWAgAVAAkKvg+DtgAWAgABNQABCgQIBgADAAAAAA==.Mellore:BAAANQAECgIIAwABNQAFFAQIBgAaAIUgAA==.Metsutan:BAACNQAFFH8HAAIgAAUKkRIJBgDwAAAgAAUKkRIJBgDwAAA1AAQKfywAAiAACQpTH0wLAL8CACAACQpTH0wLAL8CAAAA.',
Mi='Minphoria:BAAANQAECgEIAgAAAA==.Misfitgrimmy:BAAANQAECgMIBAAAAA==.',
Mo='Mogged:BAAANQAECgEIAgAAAA==.Molathom:BAAANQAECgUICgAAAA==.Moonster:BAAANQAECgUIDAAAAA==.Moppit:BAAANQAECgEIAQAAAA==.',
['Mâ']='Mâtthêw:BAAANQAECgIIBQAAAA==.',
Na='Naes:BAAANQADCgYIDAAAAA==.Nazuresh:BAAANQADCggICAABNQAECgQIEgADAAAAAA==.',
Ne='Necrodamus:BAAANQAECgQIBAAAAA==.Nekcrotic:BAABNQAECn8VAAMLAAgKshNunACfAQALAAcKuRJunACfAQAKAAIKIxClWAB2AAAAAA==.Nekromant:BAABNQAECn8gAAMKAAcKRA27SACmAAALAAYK2gm6xwA6AQAKAAMKiA27SACmAAAAAA==.Nelle:BAAANQABCggIDgAAAA==.Nemriel:BAAANQAECgUIBQAAAA==.',
Ni='Nibbles:BAAANQAECgQJBgAAAA==.Nighthoe:BAAANQAECgQIBgAAAA==.Nintales:BAAANQADCgcICAAAAA==.',
No='Nohric:BAAANQAECgcIEQAAAA==.Noobieone:BAAANQADCggICAAAAA==.Norsem:BAAANQAECgYIEQAAAA==.',
Ny='Nymera:BAAANQADCggIGQABNQAECgYIBwADAAAAAA==.',
['Nä']='Nämeless:BAAANQAECgMIAwAAAA==.',
Oh='Ohlorn:BAACNQAFFH8HAAIjAAUKQQ2hAwA9AQAjAAUKQQ2hAwA9AQA1AAQKfywAAiMACgqBI20EAE0DACMACgqBI20EAE0DAAAA.',
Ok='Oktar:BAAANQADCgUIBQAAAA==.',
On='Onfleek:BAAANQAECgUICQAAAA==.',
Or='Orakrak:BAAANQADCgQIBAAAAA==.Oroku:BAAANQADCgQICAAAAA==.',
Ox='Oxtails:BAAANQADCgMIAwAAAA==.',
Oz='Ozzmodius:BAAANQAECgQIBwAAAA==.',
Pa='Pakapunch:BAAANQADCgIIAgABNQAECgQJBQADAAAAAA==.Palysuk:BAAANQADCggIFAAAAA==.Papier:BAAANQAECgYICAAAAA==.Parsephone:BAACNQAFFH8UAAMBAAUKYx/eBADWAQABAAUKYx/eBADWAQAaAAMKug8ODACWAAA1AAQKfy0ABAEACgo9JfIAANIDAAEACQpWJvIAANIDABoABAqPGZQuAKYAABQAAQoAAEhCADUAAAE1AAQKBwgNAAMAAAAA.Parstout:BAAANQAECgcIDQAAAA==.Pawsitivity:BAABNQAECn8oAAIXAAkKjSK0IAAIAwAXAAkKjSK0IAAIAwAAAA==.',
Pd='Pdbm:BAABNQAECn8cAAIGAAoK1BhGUACkAgAGAAoK1BhGUACkAgAAAA==.',
Pe='Petr:BAABNQAECn8vAAMPAAoKfxnlMACkAgAPAAoKfxnlMACkAgAQAAEKAADqjgAcAAAAAA==.Pettigrew:BAAANQAECgYIBgAAAA==.Peut:BAABNQAECn8mAAISAAoKhho6LwCpAgASAAoKhho6LwCpAgAAAA==.',
Ph='Physix:BAAANQAECgQIAwAAAA==.',
Pi='Pipsqueak:BAAANQADCgcJCwAAAA==.Pitchntents:BAAANQAECgcJCwAAAA==.',
Po='Popped:BAAANQAECgQIDAAAAA==.Porkins:BAABNQAECn8rAAMOAAoK8xzqBAAYAgAOAAoKTRzqBAAYAgATAAYKdxMMZgB5AQAAAA==.',
Pr='Priestus:BAAANQAECgEIAwAAAA==.',
Ps='Psyndra:BAEANQAFFAEIAQAAAA==.',
Py='Pyraxx:BAABNQAECn85AAIWAAoK/x/JAACwAwAWAAoK/x/JAACwAwAAAA==.',
Qt='Qtwithabooty:BAACNQAFFH8XAAIkAAcKkRoBBAALAgAkAAcKkRoBBAALAgA1AAQKfygAAiQACgo3IzEJAEMDACQACgo3IzEJAEMDAAAA.',
Qu='Quatermaine:BAAANQAECgUIEgAAAA==.',
Ra='Radovan:BAACNQAFFH8PAAMLAAUKFSDEFQBIAQALAAQKHCTEFQBIAQAKAAEKCBiBGgBQAAA1AAQKf0AAAwsACgqkJYABAAADAAsACQpzJYABAAADAAoABQpDIM4aAJYBAAAA.Rayael:BAAANQAECgQICwABNQAECgoKMQAWAF0XAA==.Rayjax:BAAANQAECgQIAwAAAA==.Raìdèn:BAAANQAECgQIEgAAAA==.',
Re='Replicate:BAAANQAECgIIAgAAAA==.',
Rh='Rhinne:BAABNQAECn8iAAMcAAkK6RL3lgBOAQAcAAgKJhH3lgBOAQAXAAYKBAiVxgAFAQAAAA==.',
Ri='Riddic:BAAANQADCgEIAQAAAA==.',
Ro='Roktar:BAAANQADCgcIDQABNQAECgYIBwADAAAAAA==.Rosaelyia:BAAANQADCgYIBwABNQAECgcIGQAJAGIdAA==.',
Ry='Ryanqt:BAAANQADCggIDQAAAA==.Ryanvoker:BAAANQADCgcIBwAAAA==.Ryanx:BAABNQAECn8cAAISAAgK4SDqJADXAgASAAgK4SDqJADXAgAAAA==.',
Sa='Samavati:BAABNQAECn8bAAICAAcKfQ71DwDbAAACAAcKfQ71DwDbAAAAAA==.Sarah:BAABNQAECn8wAAMPAAkKXiQBBACvAwAPAAkKXiQBBACvAwAlAAMKngv6GwCHAAAAAA==.Saross:BAAANQADCggICAAAAA==.Sasori:BAACNQAFFH8MAAIgAAUKaghtCABwAQAgAAUKaghtCABwAQA1AAQKfygAAiAACQotHAQNAKUCACAACQotHAQNAKUCAAAA.Sassyface:BAABNQAECn8xAAIKAAoKCA9RAQCNAQAKAAoKCA9RAQCNAQAAAA==.',
Se='Sellit:BAAANQAECgUIBwAAAA==.Seman:BAAANQADCgIIAgAAAA==.Semperfi:BAAANQAECgEIAQAAAA==.',
Sh='Shadowbourne:BAAANQAECggICQABNQAFFAMIBgARADMWAA==.Shadowdin:BAABNQAECn8qAAISAAoKkhpeCQAuAgASAAoKkhpeCQAuAgAAAA==.Shamzilla:BAABNQAECn8oAAIXAAgKABtRNACnAgAXAAgKABtRNACnAgAAAA==.Sherria:BAAANQAECgEIAQAAAA==.Shockblast:BAAANQAECgEIAQAAAA==.Shriike:BAAANQADCgYIBgAAAA==.Shuyinn:BAAANQAECggICAABNQAECggIIQAKAC0QAA==.',
Si='Sibbrena:BAABNQAECn8oAAIQAAoKYhujEwDKAgAQAAoKYhujEwDKAgAAAA==.Sillygoose:BAAANQADCgcIGQAAAA==.Simpin:BAABNQAECn8VAAMLAAcKMxLlywAyAQALAAYKFhDlywAyAQAKAAEKpxo7agBMAAAAAA==.Sinemon:BAAANQAECgUICQAAAA==.Sinz:BAAANQAECgEIAQAAAA==.',
Sk='Skn:BAABNQAECn8sAAMSAAoKTiLVCgByAwASAAoKTiLVCgByAwAGAAQKNR/z4QBYAQAAAA==.',
Sl='Slam:BAAANQAECgIIAgAAAA==.Slaughter:BAAANQAECgUIDwAAAA==.Slycedyce:BAAANQAECgMIAwABNQAFFAUIDwALABUgAA==.',
Sm='Smartlurth:BAAANQAECgIIAgAAAA==.',
Sn='Snowjob:BAABNQAECn8WAAIVAAcKjRYAygDxAQAVAAcKjRYAygDxAQAAAA==.',
So='Solatic:BAAANQAECgUIBQAAAA==.Sonal:BAAANQADCgYIBgABNQAECgcIHgAKAMsYAA==.Sourdiesal:BAAANQABCgIIAgAAAA==.',
Sp='Spewns:BAAANQADCgMIAwAAAA==.Sporki:BAAANQAECgUICQAAAA==.Spron:BAAANQADCgUIBQAAAA==.',
Sq='Squanchy:BAAANQADCgMIAwAAAA==.',
St='Stackz:BAAANQAECgEIAQAAAA==.Stead:BAAANQAECgUICAAAAA==.Stealthus:BAAANQADCggIDAAAAA==.Steamlock:BAABNQAECn8WAAQfAAkKQw3eDQB4AQAfAAcKrAreDQB4AQAKAAQKtxB4NwDjAAALAAQKEwiyCQG4AAAAAA==.Stellar:BAAANQAECgQICQABNQAECggIIAAgANoWAA==.Stelthme:BAABNQAECn8gAAMgAAgK2hYVHgD2AAAdAAcK9hPxPQDXAQAgAAUKxBcVHgD2AAAAAA==.Strongman:BAAANQAECgIIAwAAAA==.',
Sw='Sweetie:BAAANQAECgEIAQAAAA==.',
Ta='Takeshì:BAAANQADCgcIBwABNQAECgQIEgADAAAAAA==.Tanìs:BAAANQAECgcICgAAAA==.Tarle:BAABNQAECn8WAAIFAAcKWBcOIgDSAQAFAAcKWBcOIgDSAQAAAA==.Tazath:BAAANQAECgUICgABNQAFFAUIBwAUAIUaAA==.',
Te='Tendroni:BAAANQAECgEIAgAAAA==.Tenten:BAAANQADCgYIBgAAAA==.',
Th='Theory:BAABNQAECn8dAAIEAAoKJBTiNwApAgAEAAoKJBTiNwApAgAAAA==.Thraxsus:BAAANQABCgIIAgAAAA==.',
To='Tonhãotrovão:BAAANQAECgQIBAABNQAECgQICAADAAAAAA==.',
Tr='Trashii:BAABNQAECn8rAAMmAAoKGw5RBwAIAgAmAAoKGw5RBwAIAgAIAAMKHwLNcgBrAAAAAA==.Treevive:BAAANQAECgcICQABNQAFFAMIBgAPAG8XAA==.Trencough:BAAANQAECgYIBgAAAA==.Trenlight:BAAANQAECgQIBAAAAA==.Trentotem:BAACNQAFFH8GAAIXAAMK3gIRHwC8AAAXAAMK3gIRHwC8AAA1AAQKfyEAAhcACQrxHbY0AKUCABcACQrxHbY0AKUCAAAA.Trystan:BAABNQAECn8tAAIGAAoKBw/FFgDJAQAGAAoKBw/FFgDJAQAAAA==.',
Ts='Tsinga:BAAANQAECgQIBQAAAA==.Tsla:BAAANQADCgEIAQAAAA==.',
Tu='Turlo:BAAANQADCggJCwAAAA==.',
Tw='Twobrews:BAACNQAFFH8GAAIMAAMKSRazBgDqAAAMAAMKSRazBgDqAAA1AAQKfyoAAwwACgqcG1IFAA0DAAwACQohH1IFAA0DACIABAriCOgaANMAAAAA.Twohammered:BAAANQADCgcICwABNQAFFAMIBgAMAEkWAA==.',
['Tø']='Tøm:BAACNQAFFH8UAAIGAAcKvRp3BQADAgAGAAcKvRp3BQADAgA1AAQKfy0AAgYACgqKI20iADoDAAYACgqKI20iADoDAAAA.',
Ul='Ullirus:BAAANQADCggIEQAAAA==.Ultimatefury:BAAANQAECgQIBQAAAA==.',
Un='Unb:BAAANQAECgEIBgAAAA==.Unbiased:BAABNQAECn8qAAMTAAoKKhc4NQBUAgATAAgKGxg4NQBUAgAOAAkKAxemNQADAgAAAA==.Unholyblodd:BAAANQADCggIIAAAAA==.Unshookable:BAABNQAECn80AAICAAoKaCJGBQBNAwACAAoKaCJGBQBNAwAAAA==.',
Ur='Ursos:BAAANQAECgYIBwAAAA==.Urìko:BAAANQAECgQIBAAAAA==.',
Ut='Utrig:BAAANQADCgMIAwABNQAECgYIBwADAAAAAA==.',
Va='Vaelor:BAAANQADCgQIBAABNQAECgYIBwADAAAAAA==.Valsande:BAAANQADCgIIAgAAAA==.',
Ve='Vermax:BAAANQAECgUIBgAAAA==.',
Vi='Vika:BAAANQADCggIEQABNQAECgYIBwADAAAAAA==.Vita:BAAANQADCgMJAwAAAA==.',
Vo='Voidh:BAAANQAECgcIEwAAAA==.Voidlockus:BAAANQAECgYICAAAAA==.',
Vu='Vulcin:BAABNQAECn8hAAISAAoKOxtyJgDQAgASAAoKOxtyJgDQAgABNQAECgoKOQAWAP8fAA==.',
Wa='War:BAAANQADCgQIBAABNQAFFAMICAAKAJ8WAA==.Wariuus:BAAANQAECgQIBAAAAA==.Watercupp:BAAANQAECgUICwAAAA==.',
Wh='Whiskie:BAAANQADCgQIBAAAAA==.Whitelïght:BAAANQAECgUIBgAAAA==.Whsprngihntr:BAAANQADCggICAAAAA==.',
Wi='Wibblës:BAABNQAECn8gAAMcAAgKPh7jGQCLAQAcAAgKPh7jGQCLAQAXAAMKRhm+5gDKAAAAAA==.Windsor:BAAANQADCgEIAQAAAA==.',
Wr='Wrathtiger:BAAANQADCgIIAgAAAA==.',
Xi='Xial:BAAANQAECgEIAQAAAA==.Xingcai:BAAANQADCgQIBAAAAA==.',
Xy='Xyfin:BAAANQADCggIDwAAAA==.',
Yd='Ydehhteb:BAAANQADCgEIAQABNQAECgIIAgADAAAAAA==.',
Za='Zandramadas:BAABNQAECn8nAAMBAAoKgRlHGQByAgABAAoKgRlHGQByAgAaAAgKGA8DSgC/AQAAAA==.Zaraline:BAABNQAECn8ZAAIJAAcKYh2vOgBEAQAJAAcKYh2vOgBEAQAAAA==.',
Ze='Zeakz:BAAANQAECgEIAgAAAA==.',
Zi='Zinyak:BAAANQAECgUICQAAAA==.',
Zo='Zoomiez:BAAANQAECgMIBwAAAA==.',
Zp='Zpai:BAABNQAECn8dAAMMAAoKcBZDDwD8AQAMAAoKcBZDDwD8AQAiAAYKbAWxTADFAAAAAA==.',
Zy='Zyfae:BAAANQAECggIBAAAAA==.Zyyn:BAAANQAECgYICgAAAA==.',
['Äc']='Ächilles:BAAANQAECgEIAQAAAA==.',
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
