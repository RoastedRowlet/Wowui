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

local lookup = {'Warlock-Demonology','Warrior-Protection','Warlock-Destruction','Paladin-Retribution','Mage-Arcane','DeathKnight-Unholy','Paladin-Protection','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Subtlety','Hunter-Survival','Unknown-Unknown','DeathKnight-Blood','Evoker-Preservation','DeathKnight-Frost','Priest-Shadow','Priest-Holy','Shaman-Enhancement','Priest-Discipline','DemonHunter-Havoc','Warlock-Affliction','DemonHunter-Devourer','Monk-Windwalker','Mage-Frost','Paladin-Holy','Warrior-Fury','Rogue-Assassination','Warrior-Arms','Shaman-Restoration','Druid-Feral','Druid-Restoration','Druid-Balance','Druid-Guardian','Shaman-Elemental','Evoker-Devastation','Rogue-Outlaw','Monk-Mistweaver','DemonHunter-Vengeance','Evoker-Augmentation',}
local provider = {region='US',realm="Blade'sEdge",name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Acotas:BAAANQADCgQIAwAAAA==.',
Ae='Aephiona:BAAANQAECgQIBAAAAA==.',
Af='Affli:BAABNQAECn8dAAIBAAgKahsrTABvAgABAAgKahsrTABvAgAAAA==.',
Ai='Aiunar:BAABNQAECn8rAAICAAkKIw8dFgBIAQACAAkKIw8dFgBIAQAAAA==.Aiupriesty:BAAANQAECgYIDgABNQAECgkJKwACACMPAA==.',
Ak='Aka:BAAANQADCgIIAgAAAA==.Akaza:BAAANQADCggIDAAAAA==.',
Al='Alastiria:BAABNQAECn8iAAIDAAYKEQakGQCJAAADAAYKEQakGQCJAAAAAA==.Aleinara:BAABNQAECn8oAAIEAAoKdQu/xACSAQAEAAoKdQu/xACSAQAAAA==.',
Am='Amazngrace:BAAANQADCgYIBgAAAA==.',
An='Andicryst:BAAANQADCgEIAQAAAA==.Andsey:BAAANQAECgQIDQABNQAECgkJHgAFANsIAA==.Annore:BAABNQAECn8WAAIGAAcKzRq1SgDqAQAGAAcKzRq1SgDqAQAAAA==.',
Aq='Aquelius:BAABNQAECn8aAAMEAAYK3Q6S7QBBAQAEAAYK3Q6S7QBBAQAHAAMKMwe0UwBQAAAAAA==.Aqular:BAABNQAECn84AAMIAAoKsxHqVwADAgAIAAoKsxHqVwADAgAJAAYKFQYnSAAbAQAAAA==.',
Ar='Argyre:BAABNQAECn9CAAICAAoKhiUWAQDHAwACAAoKhiUWAQDHAwAAAA==.Artifice:BAACNQAFFH8MAAIKAAMKwB/DCgAmAQAKAAMKwB/DCgAmAQA1AAQKfyoAAgoACgqzJGQCAI4DAAoACgqzJGQCAI4DAAAA.',
As='Asynic:BAABNQAECn8bAAMLAAcKaxhsCADOAQALAAcKaxhsCADOAQAIAAMKQQ5mCwGCAAAAAA==.Asynicl:BAAANQAECgQICwAAAA==.',
Av='Avadakedevra:BAAANQAECggIAQAAAA==.',
Aw='Awooing:BAAANQADCggIDgABNQAECgQICQAMAAAAAA==.',
Az='Azaziel:BAABNQAECn8pAAINAAoKwA1ETQDBAQANAAoKwA1ETQDBAQAAAA==.Azells:BAAANQADCgEIAQABNQAFFAYIFQAOALYaAA==.Azumok:BAAANQADCgcIBwAAAA==.',
Ba='Bail:BAAANQAECgUICwAAAA==.Bariesh:BAAANQADCgQIBAAAAA==.',
Be='Bearface:BAAANQADCgUIBQAAAA==.Behindyou:BAAANQAECgYIBwAAAA==.Belgaria:BAAANQADCggIKgAAAA==.Belloftrix:BAAANQAECgIIAgAAAA==.Berrybrew:BAAANQAECgUICQAAAA==.Berryknight:BAABNQAECn8XAAMGAAkKkg7WWwCgAQAGAAcK2RHWWwCgAQAPAAgK+AYIUgA1AQAAAA==.Bewlzeye:BAABNQAECn8bAAIIAAYKUhpRnQDMAQAIAAYKUhpRnQDMAQAAAA==.',
Bi='Bigjonmachne:BAABNQAECn8fAAMPAAgKjRcuPQDYAQAPAAcKHBYuPQDYAQAGAAcKfxaFXQCZAQAAAA==.Bigmooma:BAAANQAECgYIDAAAAA==.Binky:BAAANQADCgUIBQAAAA==.',
Bl='Blackdog:BAAANQAECgIIAwAAAA==.Blackguyy:BAABNQAECn8UAAMQAAYK8BidMgCOAQAQAAYK8BidMgCOAQARAAEKcAvC+wA0AAAAAA==.Blasphamey:BAAANQADCgQIBAAAAA==.Bloodletter:BAAANQABCgIIAgAAAA==.Bloodsail:BAAANQAECgYIBgAAAA==.',
Bo='Bollux:BAABNQAECn9OAAISAAkKdBghDABEAgASAAkKdBghDABEAgAAAA==.Bonetatter:BAAANQAECgEIAQAAAA==.Bongonnaink:BAABNQAECn9AAAMQAAoKthcuEgAhAgAQAAoKthcuEgAhAgATAAEKjxlrJABIAAAAAA==.Bownyxia:BAAANQAECgYIBwABNQAFFAgIGAAGAD8ZAA==.Bowties:BAACNQAFFH8YAAQGAAgKPxkaBgC+AQAGAAcK7xwaBgC+AQAPAAUK/hJCBwCIAQANAAEKAAASMgAxAAA1AAQKf1IABAYACgp2JicEALIDAAYACgp2JicEALIDAA8ACQrJJEgFAIwDAA0AAgqiA4OzAGIAAAAA.',
Br='Brewfú:BAAANQADCgIIAgAAAA==.Brotie:BAACNQAFFH8NAAIUAAUKiQ+gCwBmAQAUAAUKiQ+gCwBmAQA1AAQKfywAAhQACgoJGz0ZADcCABQACgoJGz0ZADcCAAE1AAUUCAgYAAYAPxkA.',
Bt='Btmanan:BAAANQAECggIDQABNQAECgoKTwAEANsgAA==.Btmanight:BAABNQAECn8bAAIGAAoKAAzGLgBgAQAGAAoKAAzGLgBgAQABNQAECgoKTwAEANsgAA==.',
Bu='Bullshiift:BAAANQADCgYIBgAAAA==.Burgershaq:BAAANQADCgYIBgAAAA==.Burntbiscuit:BAAANQADCgUIBQAAAA==.Buugada:BAAANQAECgQIBQAAAA==.',
Ca='Caedo:BAAANQADCgIIAgABNQADCgMIAwAMAAAAAA==.Caliclysm:BAAANQAECgQIBgAAAA==.Calischism:BAABNQAECn8aAAQTAAcKBR3rCwB+AQATAAUKVxzrCwB+AQAQAAYKuBbhIgBWAQARAAYKTBLxnAA+AQAAAA==.Canadiangoos:BAAANQADCgUJBQAAAA==.Cantspell:BAAANQAECgIIAgAAAA==.Carobnica:BAAANQADCgQJBAABNQADCgYIBgAMAAAAAA==.Cavantes:BAAANQADCgIIAgAAAA==.',
Ce='Celaris:BAAANQAECgQICwAAAA==.Cell:BAAANQABCgIIAgAAAA==.Celleyna:BAAANQABCggICQAAAA==.',
Ch='Chataykay:BAAANQAECgIIAgAAAA==.Chathsong:BAAANQADCggICAAAAA==.Chichichikin:BAAANQADCgcIBwAAAA==.Chunkyclaps:BAAANQADCgEIAQAAAA==.',
Ci='Circë:BAABNQAECn8VAAIVAAkKhwk4CwB5AQAVAAkKhwk4CwB5AQAAAA==.Citrus:BAABNQAECn84AAMLAAoK7BKSBAAeAgALAAoK7BKSBAAeAgAIAAEK6AnfUgE/AAAAAA==.',
Cn='Cn:BAABNQAECn87AAIEAAoKqiCqIwA2AwAEAAoKqiCqIwA2AwAAAA==.',
Co='Codeman:BAABNQAECn9AAAINAAoKoCFuCwDTAgANAAoKoCFuCwDTAgAAAA==.Cogbo:BAAANQAECgIIAQAAAA==.Cordine:BAAANQADCgYIBgAAAA==.',
Cp='Cptinsaneo:BAACNQAFFH8hAAMPAAcKFRTzBQB2AQAGAAUK3xseCQCFAQAPAAYKqA3zBQB2AQA1AAQKfzoAAwYACgqTHoAjALUCAAYACgoyHoAjALUCAA8ACQpYGO4oAP8BAAAA.',
Cr='Crimdh:BAABNQAECn8VAAMWAAkKDRVeEwAaAgAWAAkKDRVeEwAaAgAUAAQKCgeYdQCjAAABNQAFFAcIDgAXAC0PAA==.Crimdk:BAAANQAECggIEgABNQAFFAcIDgAXAC0PAA==.Crimwl:BAAANQAECggICAAAAA==.',
Cy='Cynth:BAAANQAECgcIDgAAAA==.',
Cz='Czin:BAAANQAECgIIAgAAAA==.',
Da='Dalén:BAAANQADCgUIBQAAAA==.',
De='Deathverses:BAACNQAFFH8RAAIJAAUKWSbHBAAhAgAJAAUKWSbHBAAhAgA1AAQKf0UAAgkACQrIJvABAMoDAAkACQrIJvABAMoDAAAA.Demaeris:BAAANQAECgIIAgAAAA==.Demonbiscuit:BAACNQAFFH8QAAIUAAgKayA+AwBWAgAUAAgKayA+AwBWAgA1AAQKfzcAAhQACgqTJpIAAIwDABQACgqTJpIAAIwDAAAA.Denarkis:BAAANQADCgQIBAAAAA==.Derekor:BAAANQAECgMIAwAAAA==.Derpydawg:BAAANQADCgYIBgABNQAFFAQIBgAYAAYEAA==.Destructus:BAAANQAECgEIAgAAAA==.Deviancy:BAABNQAECn9DAAMZAAoKFiAHDgBGAwAZAAoKFiAHDgBGAwAEAAIKyg9YewFgAAAAAA==.Devocean:BAAANQADCgUIBQAAAA==.Dexxt:BAAANQAECgMIBgAAAA==.',
Di='Dikslapp:BAAANQAECgUIBQABNQAECgkJIgAaAEwRAA==.Dirlin:BAAANQAECgMIBAAAAA==.Ditto:BAAANQADCggINgAAAA==.',
Dl='Dlitinaro:BAABNQAECn8jAAINAAoK7CGVEgAYAwANAAoK7CGVEgAYAwAAAA==.',
Do='Donoph:BAABNQAECn9DAAMZAAoKVCXmAQDSAwAZAAoKVCXmAQDSAwAEAAUKWhPTEgG4AAAAAA==.Doomar:BAABNQAECn8/AAQBAAoKvB/fRAD0AQABAAkKWR7fRAD0AQADAAMKox+LMgD7AAAVAAIKWB3TGgCtAAAAAA==.Dordire:BAAANQAECgEJAQAAAA==.Dotudown:BAAANQAECgQIBAAAAA==.Dotzilla:BAAANQADCgEIAQAAAA==.',
Dr='Dragindznuts:BAAANQADCgYICgAAAA==.Drayn:BAABNQAECn8fAAIBAAgKVB9xOQCnAgABAAgKVB9xOQCnAgAAAA==.Dreaveous:BAABNQAECn82AAMBAAoKJg0tZgCQAQABAAoKJg0tZgCQAQADAAUKFQPWQAC/AAAAAA==.Drugar:BAABNQAECn8fAAIFAAYKugTlAgGgAAAFAAYKugTlAgGgAAAAAA==.',
Du='Duint:BAAANQADCgcJDAAAAA==.',
['Dé']='Déathsong:BAAANQABCgQIAwAAAA==.',
Eb='Eborsisk:BAAANQADCgEIAQAAAA==.',
Ec='Eclipsion:BAABNQAECn8YAAIBAAkKewy4sgBqAQABAAkKewy4sgBqAQAAAA==.',
Ed='Edgeclaw:BAAANQADCggICAAAAA==.',
Ee='Eelane:BAAANQAECgQICQAAAA==.',
El='Elementali:BAAANQAECgYICwAAAA==.Ell:BAAANQADCgYIFgAAAA==.Ellennia:BAAANQAECgEIAQAAAA==.Eltain:BAAANQADCgQIBAAAAA==.',
En='Endurall:BAAANQADCggIDAABNQAECgoKRAAbANIbAA==.',
Er='Eradication:BAACNQAFFH8IAAIcAAcKlw+MEwCRAQAcAAcKlw+MEwCRAQA1AAQKfykAAhwACgqtJEUOAIkDABwACgqtJEUOAIkDAAAA.',
Et='Etheria:BAAANQAECggICQABNQAFFAcIFgAdAP4UAA==.',
Ev='Everfale:BAAANQAECgEIAwABNQAFFAcICAAcAJcPAA==.Evilexo:BAAANQADCgcIBwAAAA==.',
Ex='Exxotic:BAAANQABCgIIAgAAAA==.',
Fa='Faedia:BAAANQAECgYICAABNQAECgkJHgAFANsIAA==.Fahlafflez:BAABNQAECn8eAAMaAAkKcAtcDwC2AQAaAAkKcAtcDwC2AQAcAAYKEAYm8gD7AAAAAA==.Fahros:BAAANQAECgYIDgAAAA==.Farkhaz:BAAANQADCggICAAAAA==.Faydron:BAAANQADCgMJAwABNQAECgoKQAAdAKgXAA==.',
Ff='Ffloyd:BAAANQAECgYIDwAAAA==.',
Fi='Fingielock:BAABNQAECn8bAAIBAAkKDQvboQCSAQABAAkKDQvboQCSAQAAAA==.Firedeezball:BAAANQADCggIDwAAAA==.Fishinfridge:BAABNQAECn8jAAIeAAoKaw8PEAALAgAeAAoKaw8PEAALAgAAAA==.',
Fl='Flloyd:BAABNQAECn9GAAIfAAoKbRfbEACgAgAfAAoKbRfbEACgAgAAAA==.Floÿd:BAAANQAECggIDgAAAA==.Fløyd:BAAANQAECgIIAwAAAA==.',
Fo='Folid:BAAANQAECgIIAQAAAA==.Fortwooh:BAAANQADCggIJQAAAA==.',
Fr='Francy:BAAANQAECgYICAAAAA==.',
Fu='Fuzzyspells:BAAANQAECgQICwAAAA==.',
Ga='Gaft:BAAANQAECgYIBgAAAA==.Gaftard:BAAANQAECgYIBQAAAA==.Gafty:BAAANQADCggICAAAAA==.Gambling:BAAANQADCggICAAAAA==.Gatzul:BAAANQADCgMIBAABNQADCggICAAMAAAAAA==.',
Gh='Ghostbladez:BAAANQAECgQJCAAAAA==.',
Gi='Gib:BAAANQADCgMIAwAAAA==.Girthmaster:BAAANQADCgQIBAAAAA==.',
Gn='Gnomaste:BAAANQADCgcIGgAAAA==.',
Go='Goththighs:BAACNQAFFH8WAAMFAAcKkR+9CAA7AgAFAAYKcx69CAA7AgAYAAEKCCS/CgBjAAA1AAQKf0AAAxgACgpfJlsAAH0DABgACgoQJlsAAH0DAAUACgoxJdgxACcDAAAA.',
Gr='Grawler:BAABNQAECn8cAAMgAAoKOhAKIgDYAQAgAAoKOhAKIgDYAQAhAAQKuQssTQB3AAAAAA==.Grimdk:BAAANQAECgUIDQAAAA==.Grissa:BAABNQAECn8cAAIBAAkKvAZjvABUAQABAAkKvAZjvABUAQAAAA==.',
Gu='Gumgumfury:BAAANQAECgQIBAAAAA==.',
Ha='Haidies:BAAANQAECgQIBAABNQAECgoKGgAfAGYaAA==.Halru:BAAANQAECgEIAQAAAA==.Halzlok:BAABNQAECn8xAAIiAAgK3hHbYQBJAQAiAAgK3hHbYQBJAQAAAA==.Harmful:BAAANQADCgcIBwABNQAECggIFQAbADsfAA==.',
He='Herøn:BAAANQADCgYICgAAAA==.Heyheypeople:BAAANQAECggIEgABNQAFFAIIBwAdAGIPAA==.',
Hi='Hilarie:BAAANQADCgYICwAAAA==.',
Hu='Hundigob:BAAANQABCgUIBgAAAA==.Hunterschmax:BAABNQAECn8rAAMIAAkKWhWGcAAwAgAIAAkKWhWGcAAwAgAJAAQKOAjUaQCGAAAAAA==.',
Ic='Icemachine:BAAANQABCgUIBwAAAA==.',
Ih='Ihot:BAABNQAECn8XAAIfAAkKXRvADwCzAgAfAAkKXRvADwCzAgAAAA==.',
Ik='Ikayhaimahn:BAABNQAECn8aAAIhAAkKWiKSAwB9AwAhAAkKWiKSAwB9AwAAAA==.',
In='Incideranus:BAAANQADCggIBAAAAA==.Indimonk:BAAANQAECgQIAwAAAA==.Indishaman:BAACNQAFFH8GAAIdAAQKVxtEDgBYAQAdAAQKVxtEDgBYAQA1AAQKfzAAAh0ACgodJQ4FAJ8DAB0ACgodJQ4FAJ8DAAAA.',
Ir='Iris:BAAANQADCgMIAwAAAA==.Iritara:BAAANQAECgcIBQAAAA==.Ironbound:BAAANQADCgUIBQABNQAECgkJQQAdAKAeAA==.',
Iv='Ivoric:BAAANQAECggICAAAAA==.',
Ja='Jabronygos:BAACNQAFFH8WAAIjAAYKGRcTAgANAQAjAAYKGRcTAgANAQA1AAQKfy4AAiMACgo7HssGABoDACMACgo7HssGABoDAAAA.Jarnroz:BAAANQADCgIIAgAAAA==.Jaythirian:BAAANQAECgcIDQAAAA==.',
Je='Jeatalena:BAABNQAECn8jAAIBAAcKAQ9YjQAsAQABAAcKAQ9YjQAsAQAAAA==.Jengà:BAABNQAECn8dAAIiAAoK0xtsGACaAgAiAAoK0xtsGACaAgABNQAECgoKTgAFAJAjAA==.Jerg:BAABNQAECn8aAAMfAAoKZhr1EACfAgAfAAkKLBn1EACfAgAgAAIKQRAffwA8AAAAAA==.',
Jh='Jhara:BAABNQAECn8eAAIFAAkK2wiFlQBnAQAFAAkK2wiFlQBnAQAAAA==.',
Jo='Joeheals:BAAANQADCgUIBwAAAA==.',
Ju='Junior:BAAANQAECgUIBgABNQAFFAYIFQAOALYaAA==.',
Ka='Kablinkiaa:BAAANQAECgIIAgAAAA==.Kaendas:BAAANQAECgIIAgAAAA==.Kaizayu:BAAANQAECgIIBAAAAA==.Kalier:BAAANQAECgQIBQAAAA==.Kalish:BAAANQADCgQIBAAAAA==.Kalistria:BAAANQADCgIIAgAAAA==.Kalypso:BAABNQAECn8lAAIdAAgKaRiAQQD3AQAdAAgKaRiAQQD3AQAAAA==.Kamekazi:BAAANQADCggICQAAAA==.Katastrophic:BAAANQADCggIEwAAAA==.Katazul:BAAANQADCgQIBAABNQADCggIEwAMAAAAAA==.Katieylyn:BAABNQAECn8zAAQKAAoKrh4lEQDlAgAKAAoKmh4lEQDlAgAbAAUKDBDOYAAyAQAkAAIK8w4fFwB0AAABNQAFFAYIFQAOALYaAA==.',
Ke='Keelanllan:BAAANQAECgEIAQAAAA==.Keilun:BAEANQADCgQIBAAAAA==.Kertzz:BAAANQAECgEIAQABNQAECgEIAQAMAAAAAA==.Kew:BAAANQAECgIIAgAAAA==.',
Ki='Kimjitswho:BAAANQADCgYICAAAAA==.Kirby:BAAANQAECggIDQABNQAECgoKGgAfAGYaAA==.Kizira:BAAANQAECgQIAwABNQAECgkJHgAFANsIAA==.Kiznx:BAAANQADCgIIAgABNQADCgYIBgAMAAAAAA==.',
Kn='Kneecromance:BAAANQAECgEJAQAAAA==.Knightxl:BAAANQADCgEIAQAAAA==.',
Ko='Koggmaw:BAAANQAECggICAABNQAECgoKGgAfAGYaAA==.Kokuten:BAAANQADCgQIBAABNQAFFAcIFgAdAP4UAA==.Koral:BAAANQAECgMIBgAAAA==.',
Ku='Kungfuhealya:BAABNQAECn8hAAIlAAgKWArfHgAQAQAlAAgKWArfHgAQAQAAAA==.Kurog:BAAANQABCgEIAQAAAA==.',
La='Larrydale:BAAANQADCgYICwAAAA==.',
Le='Lea:BAAANQADCgcIBwABNQADCgYIBgAMAAAAAA==.Lefica:BAAANQABCgIJAgAAAA==.Legacyx:BAAANQADCgcIDAABNQAFFAcICAAcAJcPAA==.Leonardorich:BAAANQADCgcIEQAAAA==.Leondis:BAABNQAECn89AAIIAAoKHyB5DgBtAwAIAAoKHyB5DgBtAwAAAA==.Lexifu:BAACNQAFFH8MAAIfAAYKcAcNCQBWAQAfAAYKcAcNCQBWAQA1AAQKf2EAAx8ACgrvItEDALEDAB8ACgrvItEDALEDACAABQrcCyt2APIAAAAA.Lexipriest:BAAANQAECgYIDAAAAA==.Leylla:BAAANQADCgMIAwABNQAECgEIAQAMAAAAAA==.',
Li='Lightful:BAABNQAECn8+AAIEAAoKTR1/RgBHAgAEAAoKTR1/RgBHAgAAAA==.Lilbro:BAACNQAFFH8UAAIcAAcKAxUfBwBOAgAcAAcKAxUfBwBOAgA1AAQKfzIAAhwACgpzJd8NAIsDABwACgpzJd8NAIsDAAAA.Lit:BAAANQADCggIDQABNQAECggIFQAbADsfAA==.',
Lo='Lobais:BAAANQAECgUIBwABNQAECggIDgAMAAAAAA==.Lokii:BAAANQABCgMIAwAAAA==.',
Lu='Lucifel:BAAANQAECgYIBgAAAA==.Lumiel:BAAANQABCgcICwAAAA==.Lumos:BAAANQADCggICAAAAA==.Lumosmaxiima:BAAANQADCggIFAAAAA==.',
Ma='Madamme:BAAANQAECgYJDQAAAA==.Madkingzack:BAABNQAECn8oAAIcAAoKEh0cLQB+AgAcAAoKEh0cLQB+AgAAAA==.Maevea:BAAANQAECgQIBgAAAA==.Maggerz:BAAANQADCgMIAwAAAA==.Malagig:BAAANQADCgIIAgAAAA==.Malaviolence:BAAANQABCgcIDAAAAA==.Malistavias:BAABNQAECn8qAAIBAAoKVhjMQAACAgABAAoKVhjMQAACAgAAAA==.Malliki:BAAANQAECgUIBQAAAA==.Marnangus:BAACNQAFFH8GAAMcAAMKEAj5HQC5AAAcAAMKEAj5HQC5AAAaAAEK5AasBAA6AAA1AAQKfy8AAxwACQotGx1pAFUCABwACQoYGx1pAFUCABoAAwopEPgmAGAAAAE1AAQKBAgEAAwAAAAA.Marnolkas:BAAANQADCggICgABNQAECgQICAAMAAAAAA==.Mathan:BAABNQAECn81AAIZAAoKYiYdBwChAwAZAAoKYiYdBwChAwAAAA==.Maudib:BAABNQAECn8zAAMhAAkKMBP/GADkAQAhAAgKqhH/GADkAQAeAAgKfw43FAC4AQAAAA==.Mawile:BAABNQAECn8xAAQgAAkKjg8uMwBbAQAgAAkKBQ0uMwBbAQAhAAUKMBOFLAA0AQAeAAQKbwlXKwC2AAAAAA==.',
Me='Meesha:BAAANQAECgQICwAAAA==.Melinarra:BAABNQAECn8mAAIZAAcKCRAAcgBLAQAZAAcKCRAAcgBLAQAAAA==.Meridia:BAAANQADCgQIBAAAAA==.Messe:BAABNQAECn9EAAMbAAoK0hsoCABcAgAbAAoK0hsoCABcAgAkAAYKARXbDQBjAQAAAA==.Methious:BAAANQAECgMIBAAAAA==.',
Mi='Milicious:BAAANQABCgMJBQAAAA==.Mindcontrol:BAAANQAECgcIEQABNQAECgoKJQAIAL0dAA==.',
Mo='Molatile:BAABNQAECn8iAAIIAAcKuw1ToQDDAQAIAAcKuw1ToQDDAQAAAA==.Montu:BAAANQAECgcIBQAAAA==.Moogyver:BAAANQABCggIEQAAAA==.Moonrivr:BAAANQABCgEIAQABNQAECgkKJQAPAFEMAA==.Moonsguard:BAAANQAECgEIAQAAAA==.Moovit:BAAANQAECgQICgAAAA==.Mordekaíser:BAAANQAECgIIAgAAAA==.Moth:BAABNQAECn8WAAIFAAgKzBKVtwAUAgAFAAgKzBKVtwAUAgAAAA==.',
Mu='Murre:BAAANQADCgYIBgAAAA==.',
Na='Naasmiu:BAAANQADCgYIBgABNQAECgIIBQAMAAAAAA==.Nachodps:BAAANQADCgYIBgAAAA==.Nachokimbo:BAAANQADCggIEAAAAA==.Nasmiuu:BAAANQAECgIIBQAAAA==.',
Ne='Nekfury:BAABNQAECn87AAIiAAoKwB0WFwClAgAiAAoKwB0WFwClAgAAAA==.Nekmane:BAAANQAECgUIEAAAAA==.Nepeta:BAABNQAECn8oAAQeAAkKNh3RCgAQAgAeAAgKvhvRCgAQAgAhAAYKwR1yFgADAgAgAAQKZhW6fgDSAAAAAA==.Nephîlîm:BAAANQADCgQIBAAAAA==.Nevenel:BAAANQADCgMIAwAAAA==.',
Ni='Nilmar:BAAANQAECgIIAQAAAA==.Nivan:BAABNQAECn8iAAMHAAYKmgStTwBbAAAEAAYKlQRBQAG5AAAHAAQK2QKtTwBbAAAAAA==.Nixdorf:BAAANQAECggICAAAAA==.Niço:BAAANQAECgcICQAAAA==.',
No='Nocturnall:BAAANQADCgQIBAAAAA==.Noicce:BAABNQAECn8eAAIeAAkKRxpNCQC0AgAeAAkKRxpNCQC0AgAAAA==.Noiceshm:BAAANQAECggIDwAAAA==.Noicewar:BAAANQAECgIIAgAAAA==.Notcrims:BAACNQAFFH8OAAIXAAcKLQ/pBQC3AQAXAAcKLQ/pBQC3AQA1AAQKfy0AAhcACgqFIvEFAAkDABcACgqFIvEFAAkDAAAA.Notcrym:BAAANQAECgEIAQABNQAFFAcIDgAXAC0PAA==.',
Nu='Numrea:BAAANQADCgIIAgAAAA==.Nutz:BAAANQAECggICAAAAA==.',
Oa='Oakmoss:BAABNQAECn8lAAIcAAoK9hiGSAAWAgAcAAoK9hiGSAAWAgAAAA==.',
Or='Oralian:BAAANQADCggICAAAAA==.Orcleave:BAABNQAECn8oAAMcAAoKRCEyIQC0AgAcAAkKMiEyIQC0AgAaAAgKexokCQBJAgAAAA==.Orestes:BAAANQAECgQIBAABNQAECgoKQwAZAFQlAA==.Orstab:BAAANQAECgYICwABNQAECgoKKAAcAEQhAA==.Orwan:BAAANQAECgQIBgAAAA==.',
Pe='Pea:BAAANQAECgQIBAABNQADCgYIBgAMAAAAAA==.',
Ph='Phoenyx:BAAANQADCgUIEAAAAA==.',
Pi='Pisslowmage:BAAANQAECgcIDQABNQAECgoKKAAcAEQhAA==.',
Pr='Pristene:BAABNQAECn8cAAIQAAkKhRE1IABvAQAQAAkKhRE1IABvAQAAAA==.Priyatama:BAAANQAECgcIEQAAAA==.',
['Põ']='Põ:BAAANQAECgYIBgABNQAECgoKNQAZAGImAA==.',
Qu='Quorra:BAAANQADCgUJBgAAAA==.',
Ra='Ragecakes:BAAANQADCgYIBQAAAA==.Rakagar:BAAANQAECgUICQAAAA==.Raktot:BAAANQAECgIIAgAAAA==.Ranko:BAAANQAECgMIBQAAAA==.Razluz:BAAANQADCggIIgAAAA==.',
Re='Reue:BAABNQAECn8lAAIlAAkKjQ82GgDcAQAlAAkKjQ82GgDcAQAAAA==.',
Rh='Rhaegos:BAAANQAECgQICAAAAA==.',
Ri='Riggzz:BAAANQAECgQIBAAAAA==.',
Ru='Ruuna:BAAANQABCgIIAgAAAA==.',
Ry='Ryumali:BAAANQADCgYIBgAAAA==.',
['Rí']='Rígg:BAAANQAECgEIAQAAAA==.',
Sa='Salla:BAAANQAECgQIBAAAAA==.Sapsipper:BAAANQABCgQIBgAAAA==.',
Sc='Schmaximus:BAAANQADCgcIDwABNQAECgkJKwAIAFoVAA==.Scrapyjack:BAABNQAECn8eAAIUAAoK+hm3KABaAgAUAAoK+hm3KABaAgABNQAECgoKIwANAOwhAA==.',
Se='Senna:BAAANQADCgMIAwAAAA==.Sensitive:BAAANQAECggIEAAAAA==.',
Sh='Shale:BAABNQAECn88AAIOAAoKag9HEwCsAQAOAAoKag9HEwCsAQAAAA==.Shammit:BAAANQADCgIIAgAAAA==.Shammytyme:BAAANQAECgYIEQAAAA==.Shampow:BAABNQAECn8WAAIiAAcKyQ/sfwClAQAiAAcKyQ/sfwClAQAAAA==.Shamyhagar:BAAANQADCgQIBAAAAA==.Shangtsung:BAACNQAFFH8PAAIfAAQKqhiwCgD3AAAfAAQKqhiwCgD3AAA1AAQKfzsAAx8ACgqgIscHAEcDAB8ACgqgIscHAEcDACAAAgqhEJqXAHoAAAAA.Sharaiya:BAABNQAECn8qAAMfAAoKUwQYNQAyAQAfAAoKUwQYNQAyAQAgAAIKdQIjggA3AAAAAA==.Sharkmanfive:BAAANQAECgQICAAAAA==.Shaure:BAAANQADCgIIAgAAAA==.Shearwater:BAABNQAECn8cAAMdAAkKQR2DQgBXAgAdAAkKQR2DQgBXAgAiAAIK+gpRFQFjAAAAAA==.',
Si='Silene:BAAANQAECgEIAQAAAA==.Silmeriaa:BAAANQABCgIIAgAAAA==.Silversesu:BAAANQAECgEIAQABNQAECgoKIQAFADsVAA==.Singularia:BAAANQAECgYICAAAAA==.',
Sk='Skippybmm:BAAANQAECggIDgAAAA==.Skirtero:BAAANQADCgYIBgAAAA==.',
Sl='Slappydappy:BAAANQADCgYIBgABNQAFFAYIDAAZADsRAA==.Slava:BAAANQAECggIDwAAAA==.Sledgehammer:BAAANQAECgIIAwAAAA==.Sleepytoker:BAAANQADCgYICwAAAA==.',
So='Soferus:BAAANQAECgEIAQABNQAECgQICAAMAAAAAA==.Softbaked:BAAANQADCgUIBgAAAA==.Soltergeist:BAACNQAFFH8JAAINAAQKrRSzFAC1AAANAAQKrRSzFAC1AAA1AAQKfzYAAg0ACgqrGggxAEwCAA0ACgqrGggxAEwCAAAA.Soulweaver:BAAANQAECggICAABNQAECgoKGgAfAGYaAA==.',
Sp='Spine:BAAANQAECggIDAABNQAECggIDgAMAAAAAA==.',
Ss='Ssyd:BAAANQADCggICAAAAA==.',
St='Staras:BAAANQADCgMIAwAAAA==.Starlsbarkly:BAAANQADCgUIBQAAAA==.Steaknshock:BAAANQAECgYIBwAAAA==.Stormhoofs:BAACNQAFFH8NAAISAAYK1BzlAQDbAQASAAYK1BzlAQDbAQA1AAQKf2oAAhIACgpPJmkAAOYDABIACgpPJmkAAOYDAAAA.',
Su='Subzone:BAABNQAECn8ZAAIUAAgKgx6FJgBpAgAUAAgKgx6FJgBpAgAAAA==.Sumnabiscuit:BAACNQAFFH8GAAMYAAQKBgT2AgD3AAAYAAQK7AL2AgD3AAAFAAIKPwNVUgB3AAA1AAQKfxoAAwUACQr6Fk+4ABMCAAUACQoZFE+4ABMCABgAAwqGE4UlAMMAAAAA.Sunmaster:BAABNQAECn8dAAMBAAoKixF2mgCkAQABAAoKCQ92mgCkAQADAAMKShPlQQC8AAAAAA==.Supercharged:BAAANQADCggICAAAAA==.',
['Sê']='Sêlene:BAAANQABCggICAAAAA==.',
Ta='Tackshi:BAAANQADCggIDAAAAA==.Tankinit:BAAANQAECgQICAAAAA==.Tarea:BAAANQADCgQIBwAAAA==.Tatterbone:BAAANQADCgYIEAABNQAECgEIAQAMAAAAAA==.',
Tb='Tbolt:BAAANQAECgcIDAABNQAECgoKTgAFAJAjAA==.',
Te='Temufuzzy:BAAANQADCgEJAQAAAA==.Tenzink:BAABNQAECn8qAAIlAAoKQBu/CwDJAgAlAAoKQBu/CwDJAgAAAA==.',
Tf='Tflow:BAABNQAECn9OAAIFAAoKkCOBCwAmAwAFAAoKkCOBCwAmAwAAAA==.',
Th='Théworld:BAAANQABCgIIBAABNQAECgEIAQAMAAAAAA==.',
Ti='Tindranga:BAAANQAECgUIBAAAAA==.Titansgrippy:BAABNQAECn8iAAIaAAkKTBETDQCaAQAaAAkKTBETDQCaAQAAAA==.',
To='Tolbert:BAAANQADCgMIAwABNQADCgYIBgAMAAAAAA==.Totemir:BAABNQAECn8YAAIiAAcKKh/wOgCKAgAiAAcKKh/wOgCKAgAAAA==.Towani:BAAANQADCggIDwAAAA==.',
Tr='Trammatize:BAABNQAECn8WAAIFAAcKYxKt7wCrAQAFAAcKYxKt7wCrAQAAAA==.Triptamean:BAAANQADCggIFwAAAA==.Trorn:BAAANQADCggICAABNQAECggIDgAMAAAAAA==.',
Ts='Tshot:BAAANQAECgYICgABNQAECgoKTgAFAJAjAA==.',
Tu='Tuonetar:BAAANQABCggIFAAAAA==.',
Tw='Twobladebray:BAABNQAECn8iAAQWAAkKkBanJAAhAgAWAAgKCRenJAAhAgAmAAEK2BmHLgBGAAAUAAEKMw4ukQA4AAAAAA==.',
Un='Undeadnite:BAABNQAECn8eAAQGAAkK0ggCOAApAQAGAAgKIwkCOAApAQAPAAcKjQV3YQD7AAANAAMKgQVlpQApAAAAAA==.Unglaus:BAAANQAECgYIBgAAAA==.',
Uz='Uzington:BAACNQAFFH8JAAICAAMKaR+7AwARAQACAAMKaR+7AwARAQA1AAQKfy4AAwIACQoKIzUFACYDAAIACQoKIzUFACYDABwABQrRGpmXADsBAAAA.',
Va='Vali:BAAANQAECgIIAgAAAA==.Valzlok:BAAANQAECgQICAAAAA==.Vanessa:BAABNQAECn9AAAIkAAoKIhpdAQCDAgAkAAoKIhpdAQCDAgAAAA==.Vanillacream:BAAANQADCgMIAwAAAA==.Vayth:BAAANQADCggICAAAAA==.',
Ve='Veilthorn:BAAANQAECgEIAgAAAA==.Velinieron:BAABNQAECn8ZAAMIAAoK8hgSRQCdAgAIAAoK8hgSRQCdAgAJAAMKcwnSaACJAAAAAA==.Velinvieron:BAAANQAECgIIAgABNQAECgoKGQAIAPIYAA==.Velithiri:BAAANQAECgQIDgAAAA==.Vellash:BAAANQADCgEIAQAAAA==.',
Vi='Vilencia:BAAANQABCggIDQAAAA==.Vince:BAAANQADCgUIBgAAAA==.Vinny:BAAANQABCgIIAgAAAA==.',
Vo='Voidjoe:BAAANQAECgUIBAAAAA==.Vonulter:BAABNQAECn8nAAIIAAgKggoLmQBmAQAIAAgKggoLmQBmAQAAAA==.',
Vy='Vylon:BAABNQAECn8YAAIcAAoKphbycwA5AgAcAAoKphbycwA5AgAAAA==.Vynlandis:BAAANQAECgEIAQAAAA==.Vyrel:BAAANQADCgYICgAAAA==.',
['Vê']='Vêga:BAAANQAECgcIBwABNQAFFAQIBgAYAAYEAA==.',
Wa='Wakanda:BAAANQADCggICAABNQAECgoKGgAfAGYaAA==.Warbezerker:BAAANQADCgcIBwAAAA==.Waycores:BAAANQAECgYIBQAAAA==.',
We='Weenbean:BAAANQAECgYICAABNQAECgoKIgAZAFYdAA==.',
Wh='Whakoopa:BAAANQAECgQIBAAAAA==.Whispertree:BAACNQAFFH8FAAIgAAMKWgfyIgB5AAAgAAMKWgfyIgB5AAA1AAQKf0wAAyAACgpZGxAdAOECACAACgpZGxAdAOECAB8AAQqYEPlsADsAAAAA.',
Wi='Wilddonut:BAAANQADCgQJBAAAAA==.Wiseguys:BAABNQAECn8yAAQPAAoKAyOgCQANAwAGAAkKJh9qFQAPAwAPAAoK1SCgCQANAwANAAcK8hdVSgDOAQABNQAFFAQIBgAYAAYEAA==.Wixypoo:BAAANQAECgEIAQAAAA==.',
Wo='Woodnzhood:BAAANQAECgMIAwAAAA==.Worhammer:BAAANQADCgYIBgAAAA==.',
Wr='Wrylah:BAABNQAECn8dAAIjAAoK6BJ5FQD1AQAjAAoK6BJ5FQD1AQAAAA==.',
Wu='Wuxian:BAAANQADCgYIBgABNQAFFAcIFgAdAP4UAA==.',
Wy='Wyyn:BAAANQAECgcIDwAAAA==.',
Xa='Xanboi:BAABNQAECn9AAAMIAAoK6yXEBQBaAwAIAAoK6yXEBQBaAwAJAAIKWxoFVwBFAAAAAA==.Xaodia:BAAANQADCgMIAwAAAA==.Xardon:BAAANQADCgcIBwAAAA==.',
Xe='Xegos:BAAANQADCgQIBAAAAA==.Xeonia:BAAANQADCgMIAwAAAA==.',
Yi='Yikkle:BAAANQABCgIIAwAAAA==.',
Yo='Yosi:BAAANQAECgEIAQAAAA==.Youri:BAAANQAECgIIBAAAAA==.',
Ys='Ysar:BAABNQAECn8kAAMnAAgKGAkSEAA8AQAnAAgKGAkSEAA8AQAjAAEKugTsQAApAAAAAA==.',
Yu='Yumzug:BAAANQADCgQIBAAAAA==.',
['Yô']='Yôshi:BAAANQAECggICAAAAA==.',
Ze='Zeebu:BAABNQAECn8cAAILAAgK2Qf2CABFAQALAAgK2Qf2CABFAQAAAA==.Zenful:BAAANQAECgUICwABNQAECgoKPgAEAE0dAA==.Zephryyn:BAAANQAECgEIAQAAAA==.',
Zh='Zhilan:BAABNQAECn9JAAIfAAoKdhN3GAA1AgAfAAoKdhN3GAA1AgAAAA==.',
Zi='Zilliwax:BAAANQADCgYIBgAAAA==.',
Zo='Zoda:BAAANQADCgQIBgAAAA==.Zoko:BAAANQAECgEIAQAAAA==.',
Zu='Zurgadhunter:BAABNQAECn8fAAImAAgK2h2BBwCOAgAmAAgK2h2BBwCOAgAAAA==.Zuzuk:BAAANQADCgMIAwAAAA==.Zuzuki:BAAANQAECgIIAgAAAA==.',
['Zú']='Zúz:BAAANQAECgcIEQAAAA==.',
['Ða']='Ðalinor:BAAANQADCggICAAAAA==.',
['Ðe']='Ðemaea:BAAANQADCgUIAwAAAA==.',
['Ði']='Ðittø:BAAANQADCgIIAgABNQADCggINgAMAAAAAA==.',
['Øc']='Øctø:BAAANQAECgEIAQAAAA==.',
['Ør']='Øreø:BAABNQAECn87AAImAAoKYSEQAwA+AwAmAAoKYSEQAwA+AwAAAA==.',
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
