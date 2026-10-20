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

local lookup = {'Warlock-Demonology','Warrior-Protection','Warlock-Destruction','Paladin-Retribution','Unknown-Unknown','DeathKnight-Unholy','Hunter-Marksmanship','Hunter-BeastMastery','Rogue-Subtlety','Hunter-Survival','DeathKnight-Blood','Evoker-Preservation','DeathKnight-Frost','Priest-Shadow','Priest-Holy','Shaman-Enhancement','Priest-Discipline','DemonHunter-Havoc','Monk-Windwalker','Mage-Frost','Paladin-Holy','Warrior-Fury','Warlock-Affliction','Mage-Arcane','Rogue-Assassination','Warrior-Arms','Shaman-Restoration','Druid-Feral','Druid-Restoration','Shaman-Elemental','Druid-Guardian','Evoker-Devastation','Rogue-Outlaw','Monk-Mistweaver','Druid-Balance','DemonHunter-Devourer','DemonHunter-Vengeance','Evoker-Augmentation',}
local provider = {region='US',realm="Blade'sEdge",name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Acotas:BAAANQADCgQJAwAAAA==.',
Ae='Aephiona:BAAANQAECgQIBAAAAA==.',
Af='Affli:BAABNQAECn8dAAIBAAgKahsrTABvAgABAAgKahsrTABvAgAAAA==.',
Ai='Aiunar:BAABNQAECn8hAAICAAkKfA6BFgDBAQACAAkKfA6BFgDBAQAAAA==.Aiupriesty:BAAANQAECgYIDQABNQAECgkJIQACAHwOAA==.',
Ak='Aka:BAAANQADCgIIAgAAAA==.Akaza:BAAANQADCggIDAAAAA==.',
Al='Alastiria:BAABNQAECn8UAAIDAAUKvgXMCgB0AAADAAUKvgXMCgB0AAAAAA==.Aleinara:BAABNQAECn8WAAIEAAgKLgq/xACSAQAEAAgKLgq/xACSAQAAAA==.Alphakiy:BAAANQADCgEIAQAAAA==.',
Am='Amazngrace:BAAANQADCgYIBgAAAA==.',
An='Andsey:BAAANQAECgUIBgABNQAECgYIEAAFAAAAAA==.Annore:BAABNQAECn8WAAIGAAcKzRq1SgDqAQAGAAcKzRq1SgDqAQAAAA==.',
Aq='Aquelius:BAAANQAECgUIDwAAAA==.Aqular:BAABNQAECn8iAAMHAAYKyRcnSAAbAQAIAAYKyRenqAC0AQAHAAYKFQYnSAAbAQAAAA==.',
Ar='Argyre:BAABNQAECn81AAICAAoKYCUWAQDHAwACAAoKYCUWAQDHAwAAAA==.Artifice:BAACNQAFFH8LAAIJAAMKwB/DCgAmAQAJAAMKwB/DCgAmAQA1AAQKfx0AAgkACgpKIGQCAI4DAAkACgpKIGQCAI4DAAAA.',
As='Asynic:BAABNQAECn8VAAIKAAYKShdsCADOAQAKAAYKShdsCADOAQAAAA==.Asynicl:BAAANQAECgQICAAAAA==.',
Av='Avadakedevra:BAAANQAECggIAgAAAA==.',
Aw='Awooing:BAAANQADCggIDgABNQAECgQICQAFAAAAAA==.',
Az='Azaziel:BAABNQAECn8nAAILAAkK5A5ETQDBAQALAAkK5A5ETQDBAQAAAA==.Azells:BAAANQADCgEIAQABNQAFFAUIEAAMAKgcAA==.Azumok:BAAANQADCgcIBwAAAA==.',
Ba='Bail:BAAANQAECgIICAAAAA==.Bariesh:BAAANQADCgQIBAAAAA==.',
Be='Bearface:BAAANQADCgUIBgAAAA==.Beezz:BAAANQADCgEIAQAAAA==.Behindyou:BAAANQAECgQIBAAAAA==.Belgaria:BAAANQADCggIHQAAAA==.Belloftrix:BAAANQAECgIIAgAAAA==.Berryknight:BAAANQAECgYIDwAAAA==.Bewlzeye:BAAANQAECgUIEQAAAA==.',
Bi='Bigjonmachne:BAABNQAECn8fAAMNAAgKjRcuPQDYAQANAAcKHBYuPQDYAQAGAAcKfxaFXQCZAQAAAA==.Bigmooma:BAAANQAECgUICgAAAA==.Binky:BAAANQADCgUIBQAAAA==.',
Bl='Blackdog:BAAANQAECgIIAwAAAA==.Blackguyy:BAABNQAECn8UAAMOAAYK8BidMgCOAQAOAAYK8BidMgCOAQAPAAEKcAvC+wA0AAAAAA==.Bloodletter:BAAANQADCgEIAgAAAA==.Bloodsail:BAAANQAECgYIBgAAAA==.',
Bo='Bollux:BAABNQAECn82AAIQAAkKjRXbAQBDAgAQAAkKjRXbAQBDAgAAAA==.Bonetatter:BAAANQAECgEIAQAAAA==.Bongonnaink:BAABNQAECn8uAAMOAAgKWho4BQCqAQAOAAgKWho4BQCqAQARAAEKjxlrJABIAAAAAA==.Bownyxia:BAAANQAECgYIBwABNQAFFAcIFgAGACMbAA==.Bowties:BAACNQAFFH8WAAQGAAcKIxsaBgC+AQAGAAYKOiAaBgC+AQANAAUK/hJCBwCIAQALAAEKAAASMgAxAAA1AAQKfz8ABAYACgrzJCcEALIDAAYACgreIycEALIDAA0ACQrJJEgFAIwDAAsAAgqiA4OzAGIAAAAA.',
Br='Brewfú:BAAANQADCgIIAgAAAA==.Briirix:BAAANQADCgEIAgAAAA==.Brotie:BAACNQAFFH8NAAISAAUKiQ+gCwBmAQASAAUKiQ+gCwBmAQA1AAQKfyIAAhIACQptHS8lAHMCABIACQptHS8lAHMCAAE1AAUUBwgWAAYAIxsA.',
Bt='Btmanight:BAABNQAECn8XAAIGAAkKkguDIgDeAAAGAAkKkguDIgDeAAAAAA==.',
Bu='Buffalowings:BAAANQADCgEIAgAAAA==.Bullshiift:BAAANQADCgYIBwAAAA==.Burgershaq:BAAANQADCgYIBgAAAA==.Burntbiscuit:BAAANQADCgUIBQAAAA==.Buugada:BAAANQAECgMIBQAAAA==.',
Ca='Caedo:BAAANQADCgIIAgABNQADCgMIAwAFAAAAAA==.Caliclysm:BAAANQAECgQIBgAAAA==.Calischism:BAAANQAECgUIEgAAAA==.Canadiangoos:BAAANQADCgUJBQAAAA==.Cantspell:BAAANQAECgIIAgAAAA==.Carobnica:BAAANQADCgQJBQABNQADCgYIBgAFAAAAAA==.Cavantes:BAAANQADCgIIAgAAAA==.',
Ce='Celaris:BAAANQAECgQIBwAAAA==.Cell:BAAANQADCgEIAgAAAA==.Celleyna:BAAANQADCgEIAgABNQADCgEIAgAFAAAAAA==.',
Ch='Chataykay:BAAANQAECgIIAwAAAA==.Chathsong:BAAANQADCggICAAAAA==.Chichichikin:BAAANQADCgcIBwAAAA==.Chunkyclaps:BAAANQADCgEIAQAAAA==.',
Ci='Citrus:BAABNQAECn8pAAMKAAkKEBF2BgAxAgAKAAkKEBF2BgAxAgAIAAEK6AnfUgE/AAAAAA==.',
Cn='Cn:BAABNQAECn8yAAIEAAoKbyCqIwA2AwAEAAoKbyCqIwA2AwAAAA==.',
Co='Codeman:BAABNQAECn8uAAILAAgK9CHDBQDpAQALAAgK9CHDBQDpAQAAAA==.Cordine:BAAANQADCgYIBgAAAA==.',
Cp='Cptinsaneo:BAACNQAFFH8XAAMGAAYKWxYeCQCFAQAGAAUK3xseCQCFAQANAAQKcAgxBgDUAAA1AAQKfywAAwYACgoyHoAjALUCAAYACgoyHoAjALUCAA0ABAo9FrIwANkAAAAA.',
Cr='Crimdh:BAAANQAECgQJBAABNQAFFAcIDgATAC0PAA==.Crimdk:BAAANQAECgcIEwABNQAFFAcIDgATAC0PAA==.',
Cz='Czin:BAAANQAECgIIAgAAAA==.',
Da='Dalén:BAAANQADCgUIBQAAAA==.',
De='Deathverses:BAACNQAFFH8RAAIHAAUKWSbHBAAhAgAHAAUKWSbHBAAhAgA1AAQKf0UAAgcACQrIJvABAMoDAAcACQrIJvABAMoDAAAA.Demonbiscuit:BAACNQAFFH8OAAISAAcKHiA+AwBWAgASAAcKHiA+AwBWAgA1AAQKfywAAhIACgpuIpsBAOIDABIACgpuIpsBAOIDAAAA.Denarkis:BAAANQADCgQIBAAAAA==.Derekor:BAAANQAECgMIAwAAAA==.Derpydawg:BAAANQADCgYIBgABNQAFFAQIBgAUAAYEAA==.Destructus:BAAANQAECgEIAgAAAA==.Deviancy:BAABNQAECn8uAAMVAAoKDh7LAQAyAwAVAAoKDh7LAQAyAwAEAAIKyg9YewFgAAAAAA==.Devocean:BAAANQADCgUIBQAAAA==.Dexxt:BAAANQAECgMIBgAAAA==.',
Di='Dikslapp:BAAANQAECgUIBQABNQAECgcIFAAWAK0NAA==.Dirlin:BAAANQADCggIHgAAAA==.Ditto:BAAANQADCggIOgAAAA==.',
Dl='Dlitinaro:BAABNQAECn8jAAILAAoK7CGVEgAYAwALAAoK7CGVEgAYAwAAAA==.',
Do='Donoph:BAABNQAECn8uAAMVAAkKRyXmAQDSAwAVAAkKRyXmAQDSAwAEAAEKAABGhgFRAAAAAA==.Doomar:BAABNQAECn8vAAQBAAoKOhzFXgA7AgABAAgK2xrFXgA7AgAXAAIKWB3TGgCtAAADAAMKox/LBwCiAAAAAA==.Dordire:BAAANQAECgEJAQAAAA==.Dotzilla:BAAANQADCgEIAQAAAA==.',
Dr='Dragindznuts:BAAANQADCgYICgAAAA==.Drayn:BAABNQAECn8fAAIBAAgKVB9xOQCnAgABAAgKVB9xOQCnAgAAAA==.Dreaveous:BAABNQAECn8pAAMBAAkK1wxShgDWAQABAAkK1wxShgDWAQADAAUKFQPWQAC/AAAAAA==.Drugar:BAABNQAECn8VAAIYAAYKiwMeZgHrAAAYAAYKiwMeZgHrAAAAAA==.',
Du='Duint:BAAANQADCgcJDQAAAA==.',
['Dé']='Déathsong:BAAANQADCgEIAQAAAA==.',
Eb='Eborsisk:BAAANQADCgEIBAAAAA==.',
Ec='Eclipsion:BAABNQAECn8WAAIBAAcK1A64sgBqAQABAAcK1A64sgBqAQAAAA==.',
Ee='Eelane:BAAANQAECgQICQAAAA==.',
El='Elementali:BAAANQAECgQIBAAAAA==.Ell:BAAANQADCgYIFwAAAA==.Ellennia:BAAANQAECgEIAQAAAA==.Eltain:BAAANQADCgQIBQAAAA==.',
En='Endurall:BAAANQADCggIDAABNQAECgkJLAAZAA8ZAA==.',
Er='Eradication:BAACNQAFFH8HAAIaAAYKZhKMEwCRAQAaAAYKZhKMEwCRAQA1AAQKfyMAAhoACgqGIEUOAIkDABoACgqGIEUOAIkDAAAA.',
Et='Etheria:BAAANQAECggICQABNQAFFAYIFQAbAHMXAA==.',
Ev='Everfale:BAAANQAECgEIAgABNQAFFAYIBwAaAGYSAA==.Evilexo:BAAANQADCgcIBwAAAA==.',
Ex='Exxotic:BAAANQADCgEIAQAAAA==.',
Fa='Faedia:BAAANQAECgQIBAABNQAECgYIEAAFAAAAAA==.Fahlafflez:BAABNQAECn8eAAMWAAkKcAtcDwC2AQAWAAkKcAtcDwC2AQAaAAYKEAYm8gD7AAAAAA==.Fahros:BAAANQAECgYIDgAAAA==.Farkhaz:BAAANQADCggICAAAAA==.Faydron:BAAANQADCgMJAwABNQAECgkJJwAbAHsZAA==.',
Ff='Ffloyd:BAAANQAECgEIAgAAAA==.',
Fi='Fingielock:BAABNQAECn8YAAIBAAkKDQvboQCSAQABAAkKDQvboQCSAQAAAA==.Firedeezball:BAAANQADCgcIBwAAAA==.Fishinfridge:BAABNQAECn8WAAIcAAkKKA8PEAALAgAcAAkKKA8PEAALAgAAAA==.',
Fl='Flloyd:BAABNQAECn8wAAIdAAoK/xIQCAC8AQAdAAoK/xIQCAC8AQAAAA==.Floÿd:BAAANQAECgQIBQAAAA==.Fløyd:BAAANQADCgYIBgAAAA==.',
Fo='Folid:BAAANQAECgEIAQAAAA==.Fortwooh:BAAANQADCggIIAAAAA==.',
Fr='Francy:BAAANQAECgYICAAAAA==.',
Fu='Fuzzyspells:BAAANQAECgQIBwAAAA==.',
Ga='Gaftard:BAAANQAECgUIBQAAAA==.Gambling:BAAANQADCggICAAAAA==.Gatzul:BAAANQADCgMIBQAAAA==.',
Gh='Ghostbladez:BAAANQAECgQJCAAAAA==.',
Gi='Gib:BAAANQADCgMIAwAAAA==.Girthmaster:BAAANQADCgQIBAAAAA==.',
Gn='Gnomaste:BAAANQADCgcIGgAAAA==.',
Go='Goththighs:BAACNQAFFH8WAAMYAAcKkR+9CAA7AgAYAAYKcx69CAA7AgAUAAEKCCTKAwBwAAA1AAQKfyMAAhgACgrJJNgxACcDABgACgrJJNgxACcDAAAA.',
Gr='Grawler:BAAANQAECgYICgAAAA==.Grimdk:BAAANQAECgIICAAAAA==.Grissa:BAABNQAECn8XAAIBAAkKMgZjvABUAQABAAkKMgZjvABUAQAAAA==.',
Gu='Gumgumfury:BAAANQAECgEIAQAAAA==.',
Ha='Halru:BAAANQADCgYICwAAAA==.Halzlok:BAABNQAECn8eAAIeAAYKmBRDiACQAQAeAAYKmBRDiACQAQAAAA==.Harmful:BAAANQADCgcIBwABNQAECggIFQAZADsfAA==.',
He='Herøn:BAAANQADCgYICgAAAA==.Heyheypeople:BAAANQAECgEIAQABNQAECgoKNgAbALsYAA==.',
Hi='Hilarie:BAAANQADCgYICwAAAA==.',
Hu='Hundigob:BAAANQAECgEIAQAAAA==.Hunterschmax:BAABNQAECn8hAAMIAAgKdBaGcAAwAgAIAAgKdBaGcAAwAgAHAAMK8QjUaQCGAAAAAA==.',
Ic='Icemachine:BAAANQADCgEIAQAAAA==.',
Ih='Ihot:BAAANQAECgcIDQAAAA==.',
Ik='Ikayhaimahn:BAABNQAECn8aAAIfAAkKWiKSAwB9AwAfAAkKWiKSAwB9AwAAAA==.',
In='Incideranus:BAAANQADCggIBAAAAA==.Indimonk:BAAANQADCgYIDAAAAA==.Indishaman:BAABNQAECn8qAAIbAAkK6CQOBQCfAwAbAAkK6CQOBQCfAwAAAA==.',
Ir='Iris:BAAANQADCgMIAwAAAA==.Iritara:BAAANQAECgQIBQAAAA==.Ironbound:BAAANQADCgUIBgABNQAECggILQAbAK4aAA==.',
Iv='Ivoric:BAAANQAECggICAAAAA==.',
Ja='Jabronygos:BAACNQAFFH8WAAIgAAYKGReaAAAhAQAgAAYKGReaAAAhAQA1AAQKfy4AAiAACgo7HssGABoDACAACgo7HssGABoDAAAA.Jambi:BAAANQADCgEIAQAAAA==.Jarnroz:BAAANQADCgIIAgAAAA==.Jaythirian:BAAANQAECgcIDAAAAA==.',
Je='Jeatalena:BAAANQAECgQIEgAAAA==.Jengà:BAAANQAECgQIBAABNQAECgoKNAAYAOcgAA==.Jerg:BAAANQAECgQICAABNQAECggIAQAFAAAAAA==.',
Jh='Jhara:BAAANQAECgYIEAAAAA==.',
Jo='Joeevoke:BAAANQADCgEIAQAAAA==.Joeheals:BAAANQADCgUIBwAAAA==.',
Ju='Junior:BAAANQAECgEIAQABNQAFFAUIEAAMAKgcAA==.',
Ka='Kablinkiaa:BAAANQAECgIIAwAAAA==.Kaendas:BAAANQAECgIIAgAAAA==.Kaideli:BAAANQADCgEIAgAAAA==.Kaizayu:BAAANQAECgIIBAAAAA==.Kalier:BAAANQAECgQIBQAAAA==.Kalish:BAAANQADCgQIBAAAAA==.Kalistria:BAAANQADCgIIAgAAAA==.Kalypso:BAABNQAECn8YAAIbAAYKQRixNgAKAQAbAAYKQRixNgAKAQAAAA==.Kamekazi:BAAANQADCggICgAAAA==.Katastrophic:BAAANQADCggIEwAAAA==.Katazul:BAAANQADCgQIBAABNQADCggIEwAFAAAAAA==.Kathriais:BAAANQADCgEIAQAAAA==.Katieylyn:BAABNQAECn8bAAQJAAkK3BozAgBwAgAJAAkKxhozAgBwAgAZAAUKDBDOYAAyAQAhAAIK8w4fFwB0AAABNQAFFAUIEAAMAKgcAA==.',
Ke='Keelanllan:BAAANQAECgEIAQAAAA==.Keilun:BAEANQADCgQIBAAAAA==.Kertzz:BAAANQAECgEIAQABNQAECgEIAQAFAAAAAA==.Kew:BAAANQAECgIIAgAAAA==.',
Ki='Kimjitswho:BAAANQADCgQIBAAAAA==.Kirby:BAAANQAECgQIBAABNQAECggIAQAFAAAAAA==.Kizira:BAAANQAECgQIBAABNQAECgYIEAAFAAAAAA==.Kiznx:BAAANQADCgIIBAABNQADCgYIBgAFAAAAAA==.',
Kn='Kneecromance:BAAANQAECgEJAQAAAA==.Knightxl:BAAANQADCgEIAQAAAA==.',
Ko='Kokuten:BAAANQADCgQIBAABNQAFFAYIFQAbAHMXAA==.Koral:BAAANQAECgMIBgAAAA==.',
Ku='Kungfuhealya:BAABNQAECn8ZAAIiAAcKAAgdKgAfAQAiAAcKAAgdKgAfAQAAAA==.Kurog:BAAANQAECgIIAgAAAA==.',
La='Larrydale:BAAANQADCgYICwAAAA==.Lazerturkey:BAAANQADCgcIBwAAAA==.',
Le='Lea:BAAANQADCgcIBwABNQADCgYIBgAFAAAAAA==.Lefica:BAAANQABCgIJAgAAAA==.Legacyx:BAAANQADCgcIDAABNQAFFAYIBwAaAGYSAA==.Leonardorich:BAAANQADCgcIEQAAAA==.Leondis:BAABNQAECn8xAAIIAAoKBCB5DgBtAwAIAAoKBCB5DgBtAwAAAA==.Lexifu:BAACNQAFFH8LAAIdAAUKOgcNCQBWAQAdAAUKOgcNCQBWAQA1AAQKf0QAAx0ACgp8IesAAGcDAB0ACgp8IesAAGcDACMABQrcCyt2APIAAAAA.Lexipriest:BAAANQAECgYIDAAAAA==.Leylla:BAAANQADCgMIAwABNQAECgEIAQAFAAAAAA==.',
Li='Lightful:BAABNQAECn83AAIEAAoKTR1HEwDhAQAEAAoKTR1HEwDhAQAAAA==.Lilbro:BAACNQAFFH8UAAIaAAcKAxUfBwBOAgAaAAcKAxUfBwBOAgA1AAQKfywAAhoACgrQId8NAIsDABoACgrQId8NAIsDAAAA.Lit:BAAANQADCggIDgABNQAECggIFQAZADsfAA==.',
Lo='Lobais:BAAANQAECgQIBAABNQAECggIDAAFAAAAAA==.Lokii:BAAANQADCgEIAQAAAA==.',
Lu='Lumiel:BAAANQADCgEIAQAAAA==.Lumos:BAAANQADCggICAAAAA==.Lumosmaxiima:BAAANQADCggIFQAAAA==.',
Ma='Madamme:BAAANQAECgYJDQAAAA==.Madkingzack:BAABNQAECn8eAAIaAAgK6hhVLABZAQAaAAgK6hhVLABZAQAAAA==.Madpriest:BAAANQADCgcIBwAAAA==.Maevea:BAAANQAECgMIAwAAAA==.Malagig:BAAANQADCgIIAgAAAA==.Malaviolence:BAAANQADCgEIAQAAAA==.Malistavias:BAABNQAECn8WAAIBAAgKTRYqXABDAgABAAgKTRYqXABDAgAAAA==.Malliki:BAAANQAECgUIBQAAAA==.Malnick:BAAANQADCgEIAgAAAA==.Marnangus:BAABNQAECn8nAAMaAAgK3xodaQBVAgAaAAgKOhodaQBVAgAWAAMKKRB5EAByAAABNQAECgQIBAAFAAAAAA==.Marnolkas:BAAANQADCggICwABNQAECgQIBwAFAAAAAA==.Mathan:BAABNQAECn8oAAIVAAoKLSaiCACDAwAVAAoKLSaiCACDAwAAAA==.Maudib:BAABNQAECn8tAAMfAAkKMBP/GADkAQAfAAgKuRD/GADkAQAcAAgKfw43FAC4AQAAAA==.Mavie:BAAANQADCgEIAQABNQAFFAYIBwAaAGYSAA==.Mawile:BAABNQAECn8gAAQfAAcKyxCFLAA0AQAfAAUKMBOFLAA0AQAjAAcKaQ1vJwDGAAAcAAQKbwlXKwC2AAAAAA==.',
Me='Meesha:BAAANQAECgQIBwAAAA==.Megaplex:BAAANQADCgEIAQAAAA==.Melinarra:BAAANQAECgUIEgAAAA==.Messe:BAABNQAECn8sAAMZAAkKDxn5JQBcAgAZAAkKDxn5JQBcAgAhAAYKARXbDQBjAQAAAA==.Methious:BAAANQAECgMIBAAAAA==.',
Mi='Milicious:BAAANQABCgMJBQAAAA==.Mindcontrol:BAAANQAECgcIEAABNQAECgoKHwAIAEYdAA==.',
Mn='Mnmhammer:BAAANQADCgEIAQAAAA==.',
Mo='Molatile:BAAANQAECgYIEQAAAA==.Montu:BAAANQAECgYIBAAAAA==.Moogyver:BAAANQADCgEIAQAAAA==.Moonrivr:BAAANQABCgEIAQABNQAECgcKHwANAC4MAA==.Moonsguard:BAAANQADCgcIFwAAAA==.Moovit:BAAANQAECgQIBwAAAA==.Mordekaíser:BAAANQAECgIIAgAAAA==.Moth:BAABNQAECn8WAAIYAAgKzBKVtwAUAgAYAAgKzBKVtwAUAgAAAA==.',
Mu='Murre:BAAANQADCgYIBgAAAA==.',
Na='Naasmiu:BAAANQADCgYIBgABNQAECgIIBQAFAAAAAA==.Nachodps:BAAANQADCgYIBgAAAA==.Nachokimbo:BAAANQADCggICQAAAA==.Nasmiuu:BAAANQAECgIIBQAAAA==.',
Ne='Nekfury:BAABNQAECn8lAAIeAAoKohMnBgALAgAeAAoKohMnBgALAgAAAA==.Nekmane:BAAANQAECgYIBgAAAA==.Nepeta:BAABNQAECn8jAAQcAAgKuBwgAgDfAQAfAAYKwR1yFgADAgAcAAYKOB8gAgDfAQAjAAQKBBW6fgDSAAAAAA==.Nevenel:BAAANQADCgMIAwAAAA==.',
Ni='Nivan:BAABNQAECn8UAAIEAAUKrARBQAG5AAAEAAUKrARBQAG5AAAAAA==.Nixdorf:BAAANQAECggICAAAAA==.Niço:BAAANQAECgcICQAAAA==.',
No='Nocturnall:BAAANQADCgQIBQAAAA==.Noicce:BAABNQAECn8eAAIcAAkKRxpNCQC0AgAcAAkKRxpNCQC0AgAAAA==.Noiceshm:BAAANQAECgUIBgAAAA==.Noicewar:BAAANQAECgIIAgAAAA==.Notcrims:BAACNQAFFH8OAAITAAcKLQ/pBQC3AQATAAcKLQ/pBQC3AQA1AAQKfxwAAhMACgrOHW8VAKgCABMACgrOHW8VAKgCAAAA.Notcrym:BAAANQAECgEIAQABNQAFFAcIDgATAC0PAA==.',
Nu='Numrea:BAAANQADCgIIAgAAAA==.Nutz:BAAANQAECggICAAAAA==.',
Oa='Oakmoss:BAABNQAECn8aAAIaAAkKJhkYYQBqAgAaAAkKJhkYYQBqAgAAAA==.',
Or='Oralian:BAAANQADCggICAAAAA==.Orcleave:BAABNQAECn8bAAMWAAoKnR4kCQBJAgAWAAgKexokCQBJAgAaAAkKER44JQBwAQAAAA==.Orestes:BAAANQAECgQIBAABNQAECgkJLgAVAEclAA==.Orwan:BAAANQAECgQIBgAAAA==.',
Pe='Pea:BAAANQAECgQIBAABNQADCgYIBgAFAAAAAA==.',
Ph='Phoenyx:BAAANQADCgUIDAAAAA==.',
Pi='Pisslowmage:BAAANQAECgUIBgABNQAECgoKGwAWAJ0eAA==.',
Pr='Pristene:BAAANQAECgYIEAAAAA==.Priyatama:BAAANQAECgYICgAAAA==.',
Qu='Quorra:BAAANQADCgUJBgAAAA==.',
Ra='Ragecakes:BAAANQADCgYIBQAAAA==.Rakagar:BAAANQAECgUICQAAAA==.Raktot:BAAANQADCgEIAQAAAA==.Ranko:BAAANQAECgIIAwAAAA==.Razluz:BAAANQADCgYIHQAAAA==.',
Re='Reue:BAABNQAECn8lAAIiAAkKjQ82GgDcAQAiAAkKjQ82GgDcAQAAAA==.',
Rh='Rhaegos:BAAANQAECgQIBwAAAA==.',
Ri='Riggzz:BAAANQAECgQIBAAAAA==.',
Ro='Robinavitch:BAAANQADCgEIAQAAAA==.',
Ru='Ruuna:BAAANQADCgEIAwAAAA==.',
['Rí']='Rígg:BAAANQAECgEIAQAAAA==.',
Sa='Salla:BAAANQAECgQIBAAAAA==.Sapsipper:BAAANQADCgEIAQAAAA==.',
Sc='Schmaximus:BAAANQADCgcIEAABNQAECggIIQAIAHQWAA==.Scrapyjack:BAABNQAECn8eAAISAAoK+hm3KABaAgASAAoK+hm3KABaAgABNQAECgoKIwALAOwhAA==.',
Se='Senna:BAAANQADCgMIAwAAAA==.Sensitive:BAAANQAECggICAAAAA==.',
Sh='Shale:BAABNQAECn8yAAIMAAoK7Q0kHQD6AQAMAAoK7Q0kHQD6AQAAAA==.Shammit:BAAANQADCgIIAgAAAA==.Shammytyme:BAAANQAECgYIEQAAAA==.Shampow:BAABNQAECn8UAAIeAAcKyQ/sfwClAQAeAAcKyQ/sfwClAQAAAA==.Shamyhagar:BAAANQADCgQIBAAAAA==.Shanahime:BAAANQADCgEIAQAAAA==.Shangtsung:BAACNQAFFH8IAAIdAAMKKRLtDADhAAAdAAMKKRLtDADhAAA1AAQKfzQAAx0ACgpEH8cHAEcDAB0ACgpEH8cHAEcDACMAAgqhEJqXAHoAAAAA.Sharaiya:BAABNQAECn8eAAIdAAgKyAOwIgC/AAAdAAgKyAOwIgC/AAAAAA==.Sharkmanfive:BAAANQAECgQICAAAAA==.Shaure:BAAANQADCgIIAwAAAA==.Shearwater:BAAANQAECggIEAAAAA==.',
Si='Silmeriaa:BAAANQABCgIIAgAAAA==.Silversesu:BAAANQAECgEIAQABNQAECggIHwAYAAcWAA==.',
Sk='Skippybmm:BAAANQAECgUIBAABNQAECggIDAAFAAAAAA==.Skirtero:BAAANQADCgYIBgAAAA==.',
Sl='Slappydappy:BAAANQADCgYIBgABNQAFFAYIDAAVADsRAA==.Slava:BAAANQAECggIDwAAAA==.Sledgehammer:BAAANQAECgEIAQAAAA==.Sleepytoker:BAAANQADCgYIDQAAAA==.',
Sn='Sneaky:BAAANQAECgQIBAABNQAECgoKNwAEAE0dAA==.',
So='Softbaked:BAAANQADCgUIBgAAAA==.Soltergeist:BAABNQAECn8qAAILAAoKixcIMQBMAgALAAoKixcIMQBMAgAAAA==.Soulweaver:BAAANQAECggIAQAAAA==.',
Sp='Spine:BAAANQAECggIDAAAAA==.',
Ss='Ssyd:BAAANQADCggICAAAAA==.',
St='Staras:BAAANQADCgMIBAAAAA==.Starlsbarkly:BAAANQADCgUIBQAAAA==.Steaknshock:BAAANQAECgYIBwAAAA==.Stormhoofs:BAACNQAFFH8MAAIQAAUKYhvlAQDbAQAQAAUKYhvlAQDbAQA1AAQKf00AAhAACgroJCQAAFgDABAACgroJCQAAFgDAAAA.',
Su='Subzone:BAABNQAECn8ZAAISAAgKgx6FJgBpAgASAAgKgx6FJgBpAgAAAA==.Sumnabiscuit:BAACNQAFFH8GAAMUAAQKBgT2AgD3AAAUAAQK7AL2AgD3AAAYAAIKPwNVUgB3AAA1AAQKfxoAAxgACQr6Fk+4ABMCABgACQoZFE+4ABMCABQAAwqGE4UlAMMAAAAA.Sunmaster:BAABNQAECn8ZAAMBAAcK0RR2mgCkAQABAAcKzRB2mgCkAQADAAMKShPlQQC8AAAAAA==.Supercharged:BAAANQADCggICQAAAA==.',
['Sê']='Sêlene:BAAANQABCggICAAAAA==.',
Ta='Tackshi:BAAANQADCggIDAAAAA==.Tankinit:BAAANQAECgMIBQAAAA==.Tarea:BAAANQADCgQIBwAAAA==.Tatterbone:BAAANQADCgYIEAABNQAECgEIAQAFAAAAAA==.',
Te='Temufuzzy:BAAANQADCgEJAQAAAA==.Tenzink:BAABNQAECn8iAAIiAAkKNBy/CwDJAgAiAAkKNBy/CwDJAgAAAA==.',
Tf='Tflow:BAABNQAECn80AAIYAAoK5yAmAgAAAwAYAAoK5yAmAgAAAwAAAA==.',
Th='Théworld:BAAANQADCgEIAQABNQADCgcIFwAFAAAAAA==.',
Ti='Tindranga:BAAANQADCggIIQAAAA==.Titansgrippy:BAABNQAECn8UAAIWAAcKrQ3BBgAwAQAWAAcKrQ3BBgAwAQAAAA==.',
To='Tolbert:BAAANQADCgMIAwABNQADCgYIBgAFAAAAAA==.Totemir:BAABNQAECn8YAAIeAAcKKh/wOgCKAgAeAAcKKh/wOgCKAgAAAA==.Towani:BAAANQADCgcIBwAAAA==.',
Tr='Trammatize:BAABNQAECn8WAAIYAAcKYxKt7wCrAQAYAAcKYxKt7wCrAQAAAA==.Triptamean:BAAANQADCggIGgAAAA==.Trorn:BAAANQAECgEIAQABNQAECggIDAAFAAAAAA==.',
Tw='Twobladebray:BAABNQAECn8iAAQkAAkKkBanJAAhAgAkAAgKCRenJAAhAgAlAAEK2BmHLgBGAAASAAEKMw4ukQA4AAAAAA==.',
Un='Undeadnite:BAAANQAECgUICAAAAA==.Unglaus:BAAANQAECgYIBgAAAA==.',
Uz='Uzington:BAACNQAFFH8JAAICAAMKaR+7AwARAQACAAMKaR+7AwARAQA1AAQKfycAAgIACQoKIzUFACYDAAIACQoKIzUFACYDAAAA.',
Va='Valeta:BAAANQAECgEIAQAAAA==.Valzlok:BAAANQAECgQICAAAAA==.Vanessa:BAABNQAECn8oAAIhAAoKMhGvBwA1AgAhAAoKMhGvBwA1AgAAAA==.Vanillacream:BAAANQADCgMIAwAAAA==.Vayth:BAAANQADCggICAAAAA==.',
Ve='Veilthorn:BAAANQAECgEIAQAAAA==.Velinieron:BAABNQAECn8ZAAMIAAoK8hgSRQCdAgAIAAoK8hgSRQCdAgAHAAMKcwnSaACJAAAAAA==.Velithiri:BAAANQAECgQIDgAAAA==.Vellash:BAAANQADCgEIAQAAAA==.Vendétta:BAAANQADCgEIAwAAAA==.',
Vi='Vilencia:BAAANQADCgEIAQAAAA==.Vince:BAAANQADCgUICAAAAA==.Vinny:BAAANQADCgEIAQAAAA==.',
Vo='Voidjoe:BAAANQAECgUIBAAAAA==.Vonulter:BAABNQAECn8XAAIIAAYKbQoV2ABQAQAIAAYKbQoV2ABQAQAAAA==.',
Vy='Vylon:BAABNQAECn8WAAIaAAgKQRnycwA5AgAaAAgKQRnycwA5AgAAAA==.Vynlandis:BAAANQAECgEIAQAAAA==.Vyrel:BAAANQADCgYICgAAAA==.',
['Vê']='Vêga:BAAANQAECgcIBwABNQAFFAQIBgAUAAYEAA==.',
Wa='Warbezerker:BAAANQADCgcIBwAAAA==.Waycores:BAAANQAECgYIBQAAAA==.',
We='Weenbean:BAAANQAECgYICAABNQAECggIDQAFAAAAAA==.',
Wh='Whakoopa:BAAANQAECgQIBAAAAA==.Whispertree:BAABNQAECn8zAAIjAAoKThq8BgDMAQAjAAoKThq8BgDMAQAAAA==.Whìspèr:BAAANQAECgIIAgAAAA==.',
Wi='Wilddonut:BAAANQADCgQJBAAAAA==.Wiseguys:BAABNQAECn8WAAQGAAoK8hxqFQAPAwAGAAkKIBxqFQAPAwALAAcK8hdVSgDOAQANAAQKHRBQIgAaAQABNQAFFAQIBgAUAAYEAA==.Wixypoo:BAAANQAECgEIAQAAAA==.',
Wo='Woodnzhood:BAAANQAECgMIBAAAAA==.Worhammer:BAAANQADCgYIBgAAAA==.',
Wr='Wrylah:BAABNQAECn8dAAIgAAoK6BJ5FQD1AQAgAAoK6BJ5FQD1AQAAAA==.',
Wu='Wuxian:BAAANQADCgYIBgABNQAFFAYIFQAbAHMXAA==.',
Wy='Wyyn:BAAANQAECgcIDgAAAA==.',
Xa='Xanboi:BAABNQAECn8uAAMIAAgK3CW4CAA6AgAIAAgK3CW4CAA6AgAHAAEKSh9/egBXAAAAAA==.Xaodia:BAAANQADCgMIAwAAAA==.',
Xe='Xegos:BAAANQADCgQIBAAAAA==.Xeonia:BAAANQADCgMIAwAAAA==.',
Yi='Yikkle:BAAANQADCgEIAQAAAA==.',
Yo='Youri:BAAANQAECgMIAgAAAA==.',
Ys='Ysar:BAABNQAECn8dAAMmAAgKEwkSEAA8AQAmAAgKEwkSEAA8AQAgAAEKugTsQAApAAAAAA==.',
Yu='Yumzug:BAAANQADCgQIBAAAAA==.',
['Yô']='Yôshi:BAAANQAECggICAAAAA==.',
Ze='Zeebu:BAAANQAECgUIDgAAAA==.Zenful:BAAANQAECgQIBgABNQAECgoKNwAEAE0dAA==.Zephryyn:BAAANQAECgEIAQAAAA==.',
Zh='Zhilan:BAABNQAECn8zAAIdAAgKeBJkDgBbAQAdAAgKeBJkDgBbAQAAAA==.',
Zi='Ziet:BAAANQADCgEIAQAAAA==.Zilliwax:BAAANQADCgYIBgAAAA==.',
Zo='Zoda:BAAANQADCgQIBgAAAA==.Zoko:BAAANQAECgEIAQAAAA==.',
Zu='Zurgadhunter:BAABNQAECn8fAAIlAAgK2h2BBwCOAgAlAAgK2h2BBwCOAgAAAA==.Zuzuk:BAAANQADCgMIAwAAAA==.Zuzuki:BAAANQAECgIIAgAAAA==.',
['Zú']='Zúz:BAAANQAECgYIDwAAAA==.',
['Ða']='Ðalinor:BAAANQADCggICAAAAA==.',
['Ðe']='Ðemaea:BAAANQADCgUIAwAAAA==.',
['Ði']='Ðittø:BAAANQADCgIIAgABNQADCggIOgAFAAAAAA==.',
['Øc']='Øctø:BAAANQAECgEIAQAAAA==.',
['Ør']='Øreø:BAABNQAECn8tAAIlAAoKPyAQAwA+AwAlAAoKPyAQAwA+AwAAAA==.',
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
