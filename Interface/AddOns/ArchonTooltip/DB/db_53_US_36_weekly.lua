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

local lookup = {'Warlock-Demonology','Warrior-Protection','Warlock-Destruction','Paladin-Retribution','Mage-Arcane','DeathKnight-Unholy','Paladin-Protection','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Subtlety','Hunter-Survival','Unknown-Unknown','DeathKnight-Blood','Evoker-Preservation','DeathKnight-Frost','Priest-Shadow','Priest-Holy','Shaman-Enhancement','Priest-Discipline','DemonHunter-Havoc','DemonHunter-Devourer','Monk-Windwalker','Mage-Frost','Paladin-Holy','Warrior-Fury','Warlock-Affliction','Rogue-Assassination','Warrior-Arms','Shaman-Restoration','Druid-Feral','Druid-Restoration','Druid-Balance','Druid-Guardian','Shaman-Elemental','Evoker-Devastation','Rogue-Outlaw','Monk-Mistweaver','DemonHunter-Vengeance','Evoker-Augmentation',}
local provider = {region='US',realm="Blade'sEdge",name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Acotas:BAAANQADCgQIAwAAAA==.',
Ae='Aephiona:BAAANQAECgQIBAAAAA==.',
Af='Affli:BAABNQAECn8dAAIBAAgKahsrTABvAgABAAgKahsrTABvAgAAAA==.',
Ai='Aiunar:BAABNQAECn8pAAICAAkKvg52EwBHAQACAAkKvg52EwBHAQAAAA==.Aiupriesty:BAAANQAECgYIDQABNQAECgkJKQACAL4OAA==.',
Ak='Aka:BAAANQADCgIIAgAAAA==.Akaza:BAAANQADCggIDAAAAA==.',
Al='Alastiria:BAABNQAECn8dAAIDAAYKXwXBFwCEAAADAAYKXwXBFwCEAAAAAA==.Aleinara:BAABNQAECn8iAAIEAAkKfAq/xACSAQAEAAkKfAq/xACSAQAAAA==.',
Am='Amazngrace:BAAANQADCgYIBgAAAA==.',
An='Andsey:BAAANQAECgQIDQABNQAECgkJHQAFAMYIAA==.Annore:BAABNQAECn8WAAIGAAcKzRq1SgDqAQAGAAcKzRq1SgDqAQAAAA==.',
Aq='Aquelius:BAABNQAECn8aAAMEAAYK3Q6S7QBBAQAEAAYK3Q6S7QBBAQAHAAMKMwfqTABRAAAAAA==.Aqular:BAABNQAECn8yAAMIAAoKpxGeTwDvAQAIAAoKpxGeTwDvAQAJAAYKFQYnSAAbAQAAAA==.',
Ar='Argyre:BAABNQAECn9CAAICAAoKhiUWAQDHAwACAAoKhiUWAQDHAwAAAA==.Artifice:BAACNQAFFH8MAAIKAAMKwB/DCgAmAQAKAAMKwB/DCgAmAQA1AAQKfyoAAgoACgqzJGQCAI4DAAoACgqzJGQCAI4DAAAA.',
As='Asynic:BAABNQAECn8YAAILAAcKaxhsCADOAQALAAcKaxhsCADOAQAAAA==.Asynicl:BAAANQAECgQIDAAAAA==.',
Av='Avadakedevra:BAAANQAECggIAgAAAA==.',
Aw='Awooing:BAAANQADCggIDgABNQAECgQICQAMAAAAAA==.',
Az='Azaziel:BAABNQAECn8pAAINAAoKwA1ETQDBAQANAAoKwA1ETQDBAQAAAA==.Azells:BAAANQADCgEIAQABNQAFFAUIEAAOAKgcAA==.Azumok:BAAANQADCgcIBwAAAA==.',
Ba='Bail:BAAANQAECgMICwAAAA==.Bariesh:BAAANQADCgQIBAAAAA==.',
Be='Bearface:BAAANQADCgUIBQAAAA==.Behindyou:BAAANQAECgYICQAAAA==.Belgaria:BAAANQADCggIKgAAAA==.Belloftrix:BAAANQAECgIIAgAAAA==.Berrybrew:BAAANQAECgQIBAAAAA==.Berryknight:BAABNQAECn8WAAMGAAgKNxDWWwCgAQAGAAcK2RHWWwCgAQAPAAcKWAc/UwALAQAAAA==.Bewlzeye:BAABNQAECn8XAAIIAAYKUhpRnQDMAQAIAAYKUhpRnQDMAQAAAA==.',
Bi='Bigjonmachne:BAABNQAECn8fAAMPAAgKjRcuPQDYAQAPAAcKHBYuPQDYAQAGAAcKfxaFXQCZAQAAAA==.Bigmooma:BAAANQAECgYIDAAAAA==.Binky:BAAANQADCgUIBQAAAA==.',
Bl='Blackdog:BAAANQAECgIIAwAAAA==.Blackguyy:BAABNQAECn8UAAMQAAYK8BidMgCOAQAQAAYK8BidMgCOAQARAAEKcAvC+wA0AAAAAA==.Blasphamey:BAAANQADCgQIBAAAAA==.Bloodletter:BAAANQABCgIIAgAAAA==.Bloodsail:BAAANQAECgYIBgAAAA==.',
Bo='Bollux:BAABNQAECn9JAAISAAkKARcxCwAzAgASAAkKARcxCwAzAgAAAA==.Bonetatter:BAAANQAECgEIAQAAAA==.Bongonnaink:BAABNQAECn88AAMQAAkK2xiQEwDpAQAQAAkK2xiQEwDpAQATAAEKjxlrJABIAAAAAA==.Bownyxia:BAAANQAECgYIBwABNQAFFAgIGAAGAD8ZAA==.Bowties:BAACNQAFFH8YAAQGAAgKPxkaBgC+AQAGAAcK7xwaBgC+AQAPAAUK/hJCBwCIAQANAAEKAAASMgAxAAA1AAQKf1IABAYACgp2JjoCAFgDAA8ACQrJJEgFAIwDAAYACgp2JjoCAFgDAA0AAgqiA4OzAGIAAAAA.',
Br='Brewfú:BAAANQADCgIIAgAAAA==.Brotie:BAACNQAFFH8NAAIUAAUKiQ+gCwBmAQAUAAUKiQ+gCwBmAQA1AAQKfywAAhQACgoJG2gVAD0CABQACgoJG2gVAD0CAAE1AAUUCAgYAAYAPxkA.',
Bt='Btmanan:BAAANQADCggICQABNQAECgoKRgAEAHsgAA==.Btmanight:BAABNQAECn8bAAIGAAoKAAyvKQBkAQAGAAoKAAyvKQBkAQABNQAECgoKRgAEAHsgAA==.',
Bu='Bullshiift:BAAANQADCgYIBgAAAA==.Burgershaq:BAAANQADCgYIBgAAAA==.Burntbiscuit:BAAANQADCgUIBQAAAA==.Buugada:BAAANQAECgMIBQAAAA==.',
Ca='Caedo:BAAANQADCgIIAgABNQADCgMIAwAMAAAAAA==.Caliclysm:BAAANQAECgQIBgAAAA==.Calischism:BAABNQAECn8ZAAQTAAcKehvrCwB+AQATAAUKHBnrCwB+AQAQAAYKuBblHgBXAQARAAYKTBLxnAA+AQAAAA==.Canadiangoos:BAAANQADCgUJBQAAAA==.Cantspell:BAAANQAECgIIAgAAAA==.Carobnica:BAAANQADCgQJBAABNQADCgYIBgAMAAAAAA==.Cavantes:BAAANQADCgIIAgAAAA==.',
Ce='Celaris:BAAANQAECgQICQAAAA==.Cell:BAAANQABCgIIAgAAAA==.Celleyna:BAAANQAECgEIAgABNQAECgEIAgAMAAAAAA==.',
Ch='Chataykay:BAAANQAECgIIAwAAAA==.Chathsong:BAAANQADCggICAAAAA==.Chichichikin:BAAANQADCgcIBwAAAA==.Chunkyclaps:BAAANQADCgEIAQAAAA==.',
Ci='Circë:BAAANQAECggIDwAAAA==.Citrus:BAABNQAECn81AAMLAAoKmhEnBAAYAgALAAoKmhEnBAAYAgAIAAEK6AnfUgE/AAAAAA==.',
Cn='Cn:BAABNQAECn87AAIEAAoKqiCqIwA2AwAEAAoKqiCqIwA2AwAAAA==.',
Co='Codeman:BAABNQAECn88AAINAAkKSyDDFQD/AgANAAkKSyDDFQD/AgAAAA==.Cogbo:BAAANQAECgIIBAAAAA==.Cordine:BAAANQADCgYIBgAAAA==.',
Cp='Cptinsaneo:BAACNQAFFH8hAAMPAAcKGRRtBAB9AQAGAAUK3xseCQCFAQAPAAYKrA1tBAB9AQA1AAQKfzkAAwYACgqTHoAjALUCAAYACgoyHoAjALUCAA8ACQqnFygaAEYCAAAA.',
Cr='Crimdh:BAABNQAECn8VAAMVAAkKDRWSEAAkAgAVAAkKDRWSEAAkAgAUAAQKCgeYdQCjAAABNQAFFAcIDgAWAC0PAA==.Crimdk:BAAANQAECggIEwABNQAFFAcIDgAWAC0PAA==.Crimwl:BAAANQAECggICAAAAA==.',
Cy='Cynth:BAAANQAECgcIDAAAAA==.',
Cz='Czin:BAAANQAECgIIAgAAAA==.',
Da='Dalén:BAAANQADCgUIBQAAAA==.',
De='Deathverses:BAACNQAFFH8RAAIJAAUKWSbHBAAhAgAJAAUKWSbHBAAhAgA1AAQKf0UAAgkACQrIJvABAMoDAAkACQrIJvABAMoDAAAA.Demaeris:BAAANQAECgIIAgAAAA==.Demonbiscuit:BAACNQAFFH8OAAIUAAcKHiA+AwBWAgAUAAcKHiA+AwBWAgA1AAQKfzYAAhQACgp2JpEAAIcDABQACgp2JpEAAIcDAAAA.Denarkis:BAAANQADCgQIBAAAAA==.Derekor:BAAANQAECgMIAwAAAA==.Derpydawg:BAAANQADCgYIBgABNQAFFAQIBgAXAAYEAA==.Destructus:BAAANQAECgEIAgAAAA==.Deviancy:BAABNQAECn89AAMYAAoK0x/oCwBIAwAYAAoK0x/oCwBIAwAEAAIKyg9YewFgAAAAAA==.Devocean:BAAANQADCgUIBQAAAA==.Dexxt:BAAANQAECgMIBgAAAA==.',
Di='Dikslapp:BAAANQAECgUIBQABNQAECgkJIgAZAEwRAA==.Dirlin:BAAANQAECgQIBAAAAA==.Ditto:BAAANQADCggINgAAAA==.',
Dl='Dlitinaro:BAABNQAECn8jAAINAAoK7CGVEgAYAwANAAoK7CGVEgAYAwAAAA==.',
Do='Donoph:BAABNQAECn8/AAMYAAoK9yTmAQDSAwAYAAoK9yTmAQDSAwAEAAUKWhNy9wC8AAAAAA==.Doomar:BAABNQAECn87AAQBAAoKnB9URADTAQABAAkKDR5URADTAQADAAMKox+LMgD7AAAaAAIKWB3TGgCtAAAAAA==.Dordire:BAAANQAECgEJAQAAAA==.Dotudown:BAAANQAECgQIBAAAAA==.Dotzilla:BAAANQADCgEIAQAAAA==.',
Dr='Dragindznuts:BAAANQADCgYICgAAAA==.Drayn:BAABNQAECn8fAAIBAAgKVB9xOQCnAgABAAgKVB9xOQCnAgAAAA==.Dreaveous:BAABNQAECn82AAMBAAoKJg2OWgCLAQABAAoKJg2OWgCLAQADAAUKFQPWQAC/AAAAAA==.Drugar:BAABNQAECn8fAAIFAAYKugQ28QCmAAAFAAYKugQ28QCmAAAAAA==.',
Du='Duint:BAAANQADCgcJDAAAAA==.',
['Dé']='Déathsong:BAAANQABCgQIAwAAAA==.',
Eb='Eborsisk:BAAANQADCgEIAQAAAA==.',
Ec='Eclipsion:BAABNQAECn8YAAIBAAkKewy4sgBqAQABAAkKewy4sgBqAQAAAA==.',
Ee='Eelane:BAAANQAECgQICQAAAA==.',
El='Elementali:BAAANQAECgYIDAAAAA==.Ell:BAAANQADCgYIFgAAAA==.Ellennia:BAAANQAECgEIAQAAAA==.Eltain:BAAANQADCgQIBAAAAA==.',
En='Endurall:BAAANQADCggIDAABNQAECgoKPwAbAE4aAA==.',
Er='Eradication:BAACNQAFFH8IAAIcAAcKlw+MEwCRAQAcAAcKlw+MEwCRAQA1AAQKfygAAhwACgrXI0UOAIkDABwACgrXI0UOAIkDAAAA.',
Et='Etheria:BAAANQAECggICQABNQAFFAcIFgAdAP4UAA==.',
Ev='Everfale:BAAANQAECgEIAgABNQAFFAcICAAcAJcPAA==.Evilexo:BAAANQADCgcIBwAAAA==.',
Ex='Exxotic:BAAANQABCgIIAgAAAA==.',
Fa='Faedia:BAAANQAECgYICQABNQAECgkJHQAFAMYIAA==.Fahlafflez:BAABNQAECn8eAAMZAAkKcAtcDwC2AQAZAAkKcAtcDwC2AQAcAAYKEAYm8gD7AAAAAA==.Fahros:BAAANQAECgYIDgAAAA==.Farkhaz:BAAANQADCggICAAAAA==.Faydron:BAAANQADCgMJAwABNQAECgoKOQAdAD8XAA==.',
Ff='Ffloyd:BAAANQAECgUICwAAAA==.',
Fi='Fingielock:BAABNQAECn8bAAIBAAkKDQvboQCSAQABAAkKDQvboQCSAQAAAA==.Firedeezball:BAAANQADCgcIBwAAAA==.Fishinfridge:BAABNQAECn8jAAIeAAoKaw8PEAALAgAeAAoKaw8PEAALAgAAAA==.',
Fl='Flloyd:BAABNQAECn9AAAIfAAoKbRdFDgCfAgAfAAoKbRdFDgCfAgAAAA==.Floÿd:BAAANQAECgYICwAAAA==.Fløyd:BAAANQAECgIIAwAAAA==.',
Fo='Folid:BAAANQAECgIIAgAAAA==.Fortwooh:BAAANQADCggIJQAAAA==.',
Fr='Francy:BAAANQAECgYICAAAAA==.Frostbeard:BAAANQAECgEIAQAAAA==.',
Fu='Fuzzyspells:BAAANQAECgQICQAAAA==.',
Ga='Gaftard:BAAANQAECgUIBQAAAA==.Gambling:BAAANQADCggICAAAAA==.Gatzul:BAAANQADCgMIBAABNQADCggICAAMAAAAAA==.',
Gh='Ghostbladez:BAAANQAECgQJCAAAAA==.',
Gi='Gib:BAAANQADCgMIAwAAAA==.Girthmaster:BAAANQADCgQIBAAAAA==.',
Gn='Gnomaste:BAAANQADCgcIGgAAAA==.',
Go='Goththighs:BAACNQAFFH8WAAMFAAcKkR+9CAA7AgAFAAYKcx69CAA7AgAXAAEKCCT7CABmAAA1AAQKfzcAAxcACgpfJjwAAIMDABcACgoQJjwAAIMDAAUACgoxJdgxACcDAAAA.',
Gr='Grawler:BAABNQAECn8UAAMgAAYKnBAURQDeAAAgAAYKKhAURQDeAAAhAAQKuQtqRQB3AAAAAA==.Grimdk:BAAANQAECgUIDQAAAA==.Grissa:BAABNQAECn8aAAIBAAkKaAZjvABUAQABAAkKaAZjvABUAQAAAA==.',
Gu='Gumgumfury:BAAANQAECgIIBQAAAA==.',
Ha='Haidies:BAAANQAECgQIBQABNQAECggIDwAMAAAAAA==.Halru:BAAANQAECgEIAQAAAA==.Halzlok:BAABNQAECn8rAAIiAAgK3hGkVwBEAQAiAAgK3hGkVwBEAQAAAA==.Harmful:BAAANQADCgcIBwABNQAECggIFQAbADsfAA==.',
He='Herøn:BAAANQADCgYICgAAAA==.Heyheypeople:BAAANQAECggIDAABNQAFFAIIBwAdAGIPAA==.',
Hi='Hilarie:BAAANQADCgYICwAAAA==.',
Hu='Hundigob:BAAANQAECgEIAwAAAA==.Hunterschmax:BAABNQAECn8rAAMIAAkKWhWGcAAwAgAIAAkKWhWGcAAwAgAJAAQKOAjUaQCGAAAAAA==.',
Ic='Icemachine:BAAANQABCgUIBwAAAA==.',
Ih='Ihot:BAABNQAECn8VAAIfAAcKtxt7FgAcAgAfAAcKtxt7FgAcAgAAAA==.',
Ik='Ikayhaimahn:BAABNQAECn8aAAIhAAkKWiKSAwB9AwAhAAkKWiKSAwB9AwAAAA==.',
In='Incideranus:BAAANQADCggIBAAAAA==.Indimonk:BAAANQAECgMIAwAAAA==.Indishaman:BAACNQAFFH8GAAIdAAQKVxvdCwBaAQAdAAQKVxvdCwBaAQA1AAQKfzAAAh0ACgodJQ4FAJ8DAB0ACgodJQ4FAJ8DAAAA.',
Ir='Iris:BAAANQADCgMIAwAAAA==.Iritara:BAAANQAECgcICAAAAA==.Ironbound:BAAANQADCgUIBQABNQAECgkJPAAdANQdAA==.',
Iv='Ivoric:BAAANQAECggICAAAAA==.',
Ja='Jabronygos:BAACNQAFFH8WAAIjAAYKGRe6AQASAQAjAAYKGRe6AQASAQA1AAQKfy4AAiMACgo7HssGABoDACMACgo7HssGABoDAAAA.Jarnroz:BAAANQADCgIIAgAAAA==.Jaythirian:BAAANQAECgcIDwAAAA==.',
Je='Jeatalena:BAABNQAECn8dAAIBAAcKgwz9iwAOAQABAAcKgwz9iwAOAQAAAA==.Jengà:BAAANQAECgcIDAABNQAECgoKSAAFAJAjAA==.Jerg:BAAANQAECggIDwAAAA==.',
Jh='Jhara:BAABNQAECn8dAAIFAAkKxggLiABpAQAFAAkKxggLiABpAQAAAA==.',
Jo='Joeheals:BAAANQADCgUIBwAAAA==.',
Ju='Junior:BAAANQAECgUIBgABNQAFFAUIEAAOAKgcAA==.',
Ka='Kablinkiaa:BAAANQAECgIIBAAAAA==.Kaendas:BAAANQAECgIIAgAAAA==.Kaideli:BAAANQAECgEIAgAAAA==.Kaizayu:BAAANQAECgIIBAAAAA==.Kalier:BAAANQAECgQIBQAAAA==.Kalish:BAAANQADCgQIBAAAAA==.Kalistria:BAAANQADCgIIAgAAAA==.Kalypso:BAABNQAECn8lAAIdAAgKaRjuOAAEAgAdAAgKaRjuOAAEAgAAAA==.Kamekazi:BAAANQADCggICQAAAA==.Katastrophic:BAAANQADCggIEwAAAA==.Katazul:BAAANQADCgQIBAABNQADCggIEwAMAAAAAA==.Katieylyn:BAABNQAECn8vAAQKAAoKrh4yDwDiAgAKAAoKmh4yDwDiAgAbAAUKDBDOYAAyAQAkAAIK8w4fFwB0AAABNQAFFAUIEAAOAKgcAA==.',
Ke='Keelanllan:BAAANQAECgEIAQAAAA==.Keilun:BAEANQADCgQIBAAAAA==.Kertzz:BAAANQAECgEIAQABNQAECgEIAQAMAAAAAA==.Kew:BAAANQAECgIIAgAAAA==.',
Ki='Kimjitswho:BAAANQADCgYICAAAAA==.Kirby:BAAANQAECggIBgABNQAECggIDwAMAAAAAA==.Kizira:BAAANQAECgQIBAABNQAECgkJHQAFAMYIAA==.Kiznx:BAAANQAECgIIAgABNQADCgYIBgAMAAAAAA==.',
Kn='Kneecromance:BAAANQAECgEJAQAAAA==.Knightxl:BAAANQADCgEIAQAAAA==.',
Ko='Koggmaw:BAAANQAECggICAABNQAECggIDwAMAAAAAA==.Kokuten:BAAANQADCgQIBAABNQAFFAcIFgAdAP4UAA==.Koral:BAAANQAECgMIBgAAAA==.',
Ku='Kungfuhealya:BAABNQAECn8gAAIlAAgKAAqiGwAWAQAlAAgKAAqiGwAWAQAAAA==.Kurog:BAAANQAECgIIBAAAAA==.',
La='Larrydale:BAAANQADCgYICwAAAA==.Lazerturkey:BAAANQADCgcIBwAAAA==.',
Le='Lea:BAAANQADCgcIBwABNQADCgYIBgAMAAAAAA==.Lefica:BAAANQABCgIJAgAAAA==.Legacyx:BAAANQADCgcIDAABNQAFFAcICAAcAJcPAA==.Leonardorich:BAAANQADCgcIEQAAAA==.Leondis:BAABNQAECn89AAIIAAoKHyB5DgBtAwAIAAoKHyB5DgBtAwAAAA==.Lexifu:BAACNQAFFH8MAAIfAAYKcAcNCQBWAQAfAAYKcAcNCQBWAQA1AAQKf1gAAx8ACgqPIt0DAJoDAB8ACgqPIt0DAJoDACAABQrcCyt2APIAAAAA.Lexipriest:BAAANQAECgYIDAAAAA==.Leylla:BAAANQADCgMIAwABNQAECgEIAQAMAAAAAA==.',
Li='Lightful:BAABNQAECn8+AAIEAAoKTR0ePgBAAgAEAAoKTR0ePgBAAgAAAA==.Lilbro:BAACNQAFFH8UAAIcAAcKAxUfBwBOAgAcAAcKAxUfBwBOAgA1AAQKfzIAAhwACgpzJd8NAIsDABwACgpzJd8NAIsDAAAA.Lit:BAAANQADCggIDQABNQAECggIFQAbADsfAA==.',
Lo='Lobais:BAAANQAECgUICAABNQAECggIDwAMAAAAAA==.Lokii:BAAANQABCgMIAwAAAA==.',
Lu='Lucifel:BAAANQAECgYIBgAAAA==.Lumiel:BAAANQABCgcICwAAAA==.Lumos:BAAANQADCggICAAAAA==.Lumosmaxiima:BAAANQADCggIFAAAAA==.',
Ma='Madamme:BAAANQAECgYJDQAAAA==.Madkingzack:BAABNQAECn8kAAIcAAkK7Rc0VADNAQAcAAkK7Rc0VADNAQAAAA==.Madpriest:BAAANQAECgEIAQAAAA==.Maevea:BAAANQAECgQIBgAAAA==.Maggerz:BAAANQAECgEIAgAAAA==.Malagig:BAAANQADCgIIAgAAAA==.Malaviolence:BAAANQABCgcIDAAAAA==.Malistavias:BAABNQAECn8kAAIBAAkKrhgqXABDAgABAAkKrhgqXABDAgAAAA==.Malliki:BAAANQAECgUIBQAAAA==.Marnangus:BAACNQAFFH8GAAMcAAMKEAi7GQC9AAAcAAMKEAi7GQC9AAAZAAEK5AYyBAA6AAA1AAQKfy8AAxwACQotGx1pAFUCABwACQoYGx1pAFUCABkAAwopENQhAGMAAAE1AAQKBAgEAAwAAAAA.Marnolkas:BAAANQADCggICgABNQAECgQICAAMAAAAAA==.Mathan:BAABNQAECn81AAIYAAoKYiaFBQCrAwAYAAoKYiaFBQCrAwAAAA==.Maudib:BAABNQAECn8zAAMhAAkKMBP/GADkAQAhAAgKqhH/GADkAQAeAAgKfw43FAC4AQAAAA==.Mawile:BAABNQAECn8sAAQgAAkKUg++LgBVAQAgAAkKyQy+LgBVAQAhAAUKMBOFLAA0AQAeAAQKbwlXKwC2AAAAAA==.',
Me='Meesha:BAAANQAECgQICQAAAA==.Meilynn:BAAANQAECgEIAQAAAA==.Melinarra:BAABNQAECn8gAAIYAAcKzA8QZwBPAQAYAAcKzA8QZwBPAQAAAA==.Messe:BAABNQAECn8/AAMbAAoKThpbCAA6AgAbAAoKThpbCAA6AgAkAAYKARXbDQBjAQAAAA==.Methious:BAAANQAECgMIBAAAAA==.',
Mi='Milicious:BAAANQABCgMJBQAAAA==.Mindcontrol:BAABNQAECn8WAAMRAAkKzxV1XAAMAgARAAkKzxV1XAAMAgAQAAQK6AV2awBVAAAAAA==.',
Mo='Molatile:BAABNQAECn8aAAIIAAcKuw1ToQDDAQAIAAcKuw1ToQDDAQAAAA==.Montu:BAAANQAECgcIBQAAAA==.Moogyver:BAAANQABCggIEQAAAA==.Moonrivr:BAAANQABCgEIAQABNQAECggKIwAPADoMAA==.Moonsguard:BAAANQAECgEIAQAAAA==.Moovit:BAAANQAECgQICQAAAA==.Mordekaíser:BAAANQAECgIIAgAAAA==.Moth:BAABNQAECn8WAAIFAAgKzBKVtwAUAgAFAAgKzBKVtwAUAgAAAA==.',
Mu='Murre:BAAANQAECgEIAQAAAA==.',
Na='Naasmiu:BAAANQADCgYIBgABNQAECgIIBQAMAAAAAA==.Nachodps:BAAANQADCgYIBgAAAA==.Nachokimbo:BAAANQADCggIEAAAAA==.Nasmiuu:BAAANQAECgIIBQAAAA==.',
Ne='Nekfury:BAABNQAECn82AAIiAAoKsx3jEwCpAgAiAAoKsx3jEwCpAgAAAA==.Nekmane:BAAANQAECgcIDgAAAA==.Nepeta:BAABNQAECn8nAAQeAAkKAx3mCAASAgAeAAgKhBvmCAASAgAhAAYKwR1yFgADAgAgAAQKZhW6fgDSAAAAAA==.Nevenel:BAAANQADCgMIAwAAAA==.',
Ni='Nilmar:BAAANQAECgIIAgAAAA==.Nivan:BAABNQAECn8dAAMHAAYKmgTRSABdAAAEAAYKlQRBQAG5AAAHAAQK2QLRSABdAAAAAA==.Nixdorf:BAAANQAECggICAAAAA==.Niço:BAAANQAECgcICQAAAA==.',
No='Nocturnall:BAAANQADCgQIBAAAAA==.Noicce:BAABNQAECn8eAAIeAAkKRxpNCQC0AgAeAAkKRxpNCQC0AgAAAA==.Noiceshm:BAAANQAECggIDwAAAA==.Noicewar:BAAANQAECgIIAgAAAA==.Notcrims:BAACNQAFFH8OAAIWAAcKLQ/pBQC3AQAWAAcKLQ/pBQC3AQA1AAQKfy0AAhYACgqFIvEEABADABYACgqFIvEEABADAAAA.Notcrym:BAAANQAECgEIAQABNQAFFAcIDgAWAC0PAA==.',
Nu='Numrea:BAAANQADCgIIAgAAAA==.Nutz:BAAANQAECggICAAAAA==.',
Oa='Oakmoss:BAABNQAECn8lAAIcAAoK9hjIPgAaAgAcAAoK9hjIPgAaAgAAAA==.',
Or='Oralian:BAAANQADCggICAAAAA==.Orcleave:BAABNQAECn8nAAMcAAoKRCFjGwDBAgAcAAkKMiFjGwDBAgAZAAgKexokCQBJAgAAAA==.Orestes:BAAANQAECgQIBAABNQAECgoKPwAYAPckAA==.Orstab:BAAANQAECgYICgABNQAECgoKJwAcAEQhAA==.Orwan:BAAANQAECgQIBgAAAA==.',
Pe='Pea:BAAANQAECgQIBAABNQADCgYIBgAMAAAAAA==.',
Ph='Phoenyx:BAAANQADCgUIDQAAAA==.',
Pi='Pisslowmage:BAAANQAECgcIDwABNQAECgoKJwAcAEQhAA==.',
Pr='Pristene:BAABNQAECn8bAAIQAAkKhRGaHABvAQAQAAkKhRGaHABvAQAAAA==.Priyatama:BAAANQAECgcIEgAAAA==.',
['Põ']='Põ:BAAANQAECgYIBgABNQAECgoKNQAYAGImAA==.',
Qu='Quorra:BAAANQADCgUJBgAAAA==.',
Ra='Ragecakes:BAAANQADCgYIBQAAAA==.Rakagar:BAAANQAECgUICQAAAA==.Raktot:BAAANQADCgEIAQAAAA==.Ranko:BAAANQAECgIIBQAAAA==.Razluz:BAAANQAECgEIAQAAAA==.',
Re='Reue:BAABNQAECn8lAAIlAAkKjQ82GgDcAQAlAAkKjQ82GgDcAQAAAA==.',
Rh='Rhaegos:BAAANQAECgQICAAAAA==.',
Ri='Riggzz:BAAANQAECgQIBAAAAA==.',
Ru='Ruuna:BAAANQABCgIIAgAAAA==.',
Ry='Ryumali:BAAANQADCgYIBgAAAA==.',
['Rí']='Rígg:BAAANQAECgEIAQAAAA==.',
Sa='Salla:BAAANQAECgQIBAAAAA==.Sapsipper:BAAANQABCgQIBgAAAA==.',
Sc='Schmaximus:BAAANQADCgcIDwABNQAECgkJKwAIAFoVAA==.Scrapyjack:BAABNQAECn8eAAIUAAoK+hm3KABaAgAUAAoK+hm3KABaAgABNQAECgoKIwANAOwhAA==.',
Se='Senna:BAAANQADCgMIAwAAAA==.Sensitive:BAAANQAECggIEAAAAA==.',
Sh='Shale:BAABNQAECn88AAIOAAoKag/7EACxAQAOAAoKag/7EACxAQAAAA==.Shammit:BAAANQADCgIIAgAAAA==.Shammytyme:BAAANQAECgYIEQAAAA==.Shampow:BAABNQAECn8VAAIiAAcKyQ/sfwClAQAiAAcKyQ/sfwClAQAAAA==.Shamyhagar:BAAANQADCgQIBAAAAA==.Shangtsung:BAACNQAFFH8NAAIfAAQKhRQJCgDkAAAfAAQKhRQJCgDkAAA1AAQKfzoAAx8ACgqgIscHAEcDAB8ACgqgIscHAEcDACAAAgqhEJqXAHoAAAAA.Sharaiya:BAABNQAECn8mAAMfAAgK2wPwQQAZAQAfAAgK2wPwQQAZAQAgAAIKdQLPeQA3AAAAAA==.Sharkmanfive:BAAANQAECgQICAAAAA==.Shaure:BAAANQADCgIIAgAAAA==.Shearwater:BAABNQAECn8cAAMdAAkKQR2DQgBXAgAdAAkKQR2DQgBXAgAiAAIK+gpRFQFjAAAAAA==.',
Si='Silmeriaa:BAAANQABCgIIAgAAAA==.Silversesu:BAAANQAECgEIAQABNQAECgoKIQAFADsVAA==.',
Sk='Skippybmm:BAAANQAECggIDwAAAA==.Skirtero:BAAANQADCgYIBgAAAA==.',
Sl='Slappydappy:BAAANQADCgYIBgABNQAFFAYIDAAYADsRAA==.Slava:BAAANQAECggIDwAAAA==.Sledgehammer:BAAANQAECgMIAwAAAA==.Sleepytoker:BAAANQADCgYICwAAAA==.',
So='Soferus:BAAANQAECgEIAQABNQAECgQICAAMAAAAAA==.Softbaked:BAAANQADCgUIBgAAAA==.Soltergeist:BAACNQAFFH8JAAINAAQKrRQREQC7AAANAAQKrRQREQC7AAA1AAQKfzIAAg0ACgoeGggxAEwCAA0ACgoeGggxAEwCAAAA.Soulweaver:BAAANQAECggICAABNQAECggIDwAMAAAAAA==.',
Sp='Spine:BAAANQAECggIDAABNQAECggIDwAMAAAAAA==.',
Ss='Ssyd:BAAANQADCggICAAAAA==.',
St='Staras:BAAANQADCgMIAwAAAA==.Starlsbarkly:BAAANQADCgUIBQAAAA==.Steaknshock:BAAANQAECgYIBwAAAA==.Stormhoofs:BAACNQAFFH8NAAISAAYK1BzlAQDbAQASAAYK1BzlAQDbAQA1AAQKf2EAAhIACgpPJmkAAOYDABIACgpPJmkAAOYDAAAA.',
Su='Subzone:BAABNQAECn8ZAAIUAAgKgx6FJgBpAgAUAAgKgx6FJgBpAgAAAA==.Sumnabiscuit:BAACNQAFFH8GAAMXAAQKBgT2AgD3AAAXAAQK7AL2AgD3AAAFAAIKPwNVUgB3AAA1AAQKfxoAAwUACQr6Fk+4ABMCAAUACQoZFE+4ABMCABcAAwqGE4UlAMMAAAAA.Sunmaster:BAABNQAECn8dAAMBAAoKixF2mgCkAQABAAoKCQ92mgCkAQADAAMKShPlQQC8AAAAAA==.Supercharged:BAAANQADCggICAAAAA==.',
['Sâ']='Sâsha:BAAANQAECggIAQAAAA==.',
['Sê']='Sêlene:BAAANQABCggICAAAAA==.',
Ta='Tackshi:BAAANQADCggIDAAAAA==.Tankinit:BAAANQAECgIICgAAAA==.Tarea:BAAANQADCgQIBwAAAA==.Tatterbone:BAAANQADCgYIEAABNQAECgEIAQAMAAAAAA==.',
Tb='Tbolt:BAAANQAECgcICgABNQAECgoKSAAFAJAjAA==.',
Te='Temufuzzy:BAAANQADCgEJAQAAAA==.Tenzink:BAABNQAECn8qAAIlAAoKQBu/CwDJAgAlAAoKQBu/CwDJAgAAAA==.',
Tf='Tflow:BAABNQAECn9IAAIFAAoKkCOlCQAoAwAFAAoKkCOlCQAoAwAAAA==.',
Th='Théworld:BAAANQABCgIIBAABNQAECgEIAQAMAAAAAA==.',
Ti='Tindranga:BAAANQAECgQIBAAAAA==.Titansgrippy:BAABNQAECn8iAAIZAAkKTBHNCgCgAQAZAAkKTBHNCgCgAQAAAA==.',
To='Toetem:BAAANQAECgEIAQAAAA==.Tolbert:BAAANQADCgMIAwABNQADCgYIBgAMAAAAAA==.Totemir:BAABNQAECn8YAAIiAAcKKh/wOgCKAgAiAAcKKh/wOgCKAgAAAA==.Towani:BAAANQADCggIDwAAAA==.',
Tr='Trammatize:BAABNQAECn8WAAIFAAcKYxKt7wCrAQAFAAcKYxKt7wCrAQAAAA==.Triptamean:BAAANQADCggIFwAAAA==.Trorn:BAAANQAECgEIAQABNQAECggIDwAMAAAAAA==.',
Ts='Tshot:BAAANQAECgQIBAABNQAECgoKSAAFAJAjAA==.',
Tw='Twobladebray:BAABNQAECn8iAAQVAAkKkBanJAAhAgAVAAgKCRenJAAhAgAmAAEK2BmHLgBGAAAUAAEKMw4ukQA4AAAAAA==.',
Un='Undeadnite:BAABNQAECn8YAAQGAAgKsgivMwAnAQAGAAgKsgivMwAnAQAPAAUKaQR3dwCQAAANAAMKgQWYmwApAAAAAA==.Unglaus:BAAANQAECgYIBgAAAA==.',
Uz='Uzington:BAACNQAFFH8JAAICAAMKaR+7AwARAQACAAMKaR+7AwARAQA1AAQKfy4AAwIACQoKIzUFACYDAAIACQoKIzUFACYDABwABQrRGtaGAEABAAAA.',
Va='Valeta:BAAANQAECgEIAwAAAA==.Vali:BAAANQAECgIIAgAAAA==.Valzlok:BAAANQAECgQICAAAAA==.Vanessa:BAABNQAECn83AAIkAAoKhhWzAQA0AgAkAAoKhhWzAQA0AgAAAA==.Vanillacream:BAAANQADCgMIAwAAAA==.Vayth:BAAANQADCggICAAAAA==.',
Ve='Veilthorn:BAAANQAECgEIAgAAAA==.Velinieron:BAABNQAECn8ZAAMIAAoK8hgSRQCdAgAIAAoK8hgSRQCdAgAJAAMKcwnSaACJAAAAAA==.Velinvieron:BAAANQAECgIIAwABNQAECgoKGQAIAPIYAA==.Velithiri:BAAANQAECgQIDgAAAA==.Vellash:BAAANQADCgEIAQAAAA==.',
Vi='Vilencia:BAAANQABCggIDQAAAA==.Vince:BAAANQADCgUIBgAAAA==.Vinny:BAAANQABCgIIAgAAAA==.',
Vo='Voidjoe:BAAANQAECgUIBAAAAA==.Vonulter:BAABNQAECn8gAAIIAAcK7wqYtgABAQAIAAcK7wqYtgABAQAAAA==.',
Vy='Vylon:BAABNQAECn8YAAIcAAoKphbycwA5AgAcAAoKphbycwA5AgAAAA==.Vynlandis:BAAANQAECgEIAQAAAA==.Vyrel:BAAANQADCgYICgAAAA==.',
['Vê']='Vêga:BAAANQAECgcIBwABNQAFFAQIBgAXAAYEAA==.',
['Vó']='Vóid:BAAANQAECgEIAQAAAA==.',
Wa='Warbezerker:BAAANQADCgcIBwAAAA==.Waycores:BAAANQAECgYIBQAAAA==.',
We='Weenbean:BAAANQAECgcICAABNQAECgoKIQAYAFYdAA==.',
Wh='Whakoopa:BAAANQAECgQIBAAAAA==.Whispertree:BAACNQAFFH8FAAIgAAMKWgfyIgB5AAAgAAMKWgfyIgB5AAA1AAQKf0YAAyAACgpZG3sUAEoCACAACgpZG3sUAEoCAB8AAQqYEEplADYAAAAA.',
Wi='Wilddonut:BAAANQADCgQJBAAAAA==.Wiseguys:BAABNQAECn8qAAQPAAoKiyI0CQACAwAGAAkKtB1qFQAPAwAPAAoKLSA0CQACAwANAAcK8hdVSgDOAQABNQAFFAQIBgAXAAYEAA==.Wixypoo:BAAANQAECgEIAQAAAA==.',
Wo='Woodnzhood:BAAANQAECgMIBAAAAA==.Worhammer:BAAANQADCgYIBgAAAA==.',
Wr='Wrylah:BAABNQAECn8dAAIjAAoK6BJ5FQD1AQAjAAoK6BJ5FQD1AQAAAA==.',
Wu='Wuxian:BAAANQADCgYIBgABNQAFFAcIFgAdAP4UAA==.',
Wy='Wyyn:BAAANQAECgcIDgAAAA==.',
Xa='Xanboi:BAABNQAECn88AAMIAAkKaSWREwDfAgAIAAkKaSWREwDfAgAJAAEKSh9/egBXAAAAAA==.Xaodia:BAAANQADCgMIAwAAAA==.',
Xe='Xegos:BAAANQADCgQIBAAAAA==.Xeonia:BAAANQADCgMIAwAAAA==.',
Yi='Yikkle:BAAANQABCgIIAwAAAA==.',
Yo='Yosi:BAAANQAECgEIAgAAAA==.Youri:BAAANQAECgIIBAAAAA==.',
Ys='Ysar:BAABNQAECn8kAAMnAAgKGAkSEAA8AQAnAAgKGAkSEAA8AQAjAAEKugTsQAApAAAAAA==.',
Yu='Yumzug:BAAANQADCgQIBAAAAA==.',
['Yô']='Yôshi:BAAANQAECggICAAAAA==.',
Ze='Zeebu:BAABNQAECn8aAAILAAcKrQcmCQAUAQALAAcKrQcmCQAUAQAAAA==.Zenful:BAAANQAECgUIDAABNQAECgoKPgAEAE0dAA==.Zephryyn:BAAANQAECgEIAQAAAA==.',
Zh='Zhilan:BAABNQAECn9CAAIfAAoKERERGQD6AQAfAAoKERERGQD6AQAAAA==.',
Zi='Zilliwax:BAAANQADCgYIBgAAAA==.',
Zo='Zoda:BAAANQADCgQIBgAAAA==.Zoko:BAAANQAECgEIAQAAAA==.',
Zu='Zurgadhunter:BAABNQAECn8fAAImAAgK2h2BBwCOAgAmAAgK2h2BBwCOAgAAAA==.Zuzuk:BAAANQADCgMIAwAAAA==.Zuzuki:BAAANQAECgIIAgAAAA==.',
['Zú']='Zúz:BAAANQAECgcIEQAAAA==.',
['Ða']='Ðalinor:BAAANQADCggICAAAAA==.',
['Ðe']='Ðemaea:BAAANQADCgUIAwAAAA==.',
['Ði']='Ðittø:BAAANQADCgIIAgABNQADCggINgAMAAAAAA==.',
['Øc']='Øctø:BAAANQAECgEIAQAAAA==.',
['Ør']='Øreø:BAABNQAECn83AAImAAoKYSEQAwA+AwAmAAoKYSEQAwA+AwAAAA==.',
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
