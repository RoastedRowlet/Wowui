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

local lookup = {'Warlock-Demonology','Warrior-Protection','Warlock-Destruction','Paladin-Retribution','Mage-Arcane','DeathKnight-Unholy','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Subtlety','Hunter-Survival','Unknown-Unknown','DeathKnight-Blood','DeathKnight-Frost','Priest-Shadow','Priest-Holy','Shaman-Enhancement','Priest-Discipline','DemonHunter-Havoc','Monk-Windwalker','Mage-Frost','Paladin-Holy','Warrior-Fury','Warlock-Affliction','Rogue-Assassination','Warrior-Arms','Shaman-Restoration','Druid-Feral','Druid-Restoration','Shaman-Elemental','Druid-Guardian','Evoker-Devastation','Rogue-Outlaw','Monk-Mistweaver','Druid-Balance','Paladin-Protection','Evoker-Preservation','DemonHunter-Devourer','DemonHunter-Vengeance','Evoker-Augmentation',}
local provider = {region='US',realm="Blade'sEdge",name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Acotas:BAAANQADCgQIAwAAAA==.',
Ae='Aephiona:BAAANQAECgQIBAAAAA==.',
Af='Affli:BAABNQAECn8dAAIBAAgKahsrTABvAgABAAgKahsrTABvAgAAAA==.',
Ai='Aiunar:BAABNQAECn8pAAICAAkKvg47DgBTAQACAAkKvg47DgBTAQAAAA==.Aiupriesty:BAAANQAECgYIDQABNQAECgkJKQACAL4OAA==.',
Ak='Aka:BAAANQADCgIIAgAAAA==.Akaza:BAAANQADCggIDAAAAA==.',
Al='Alastiria:BAABNQAECn8aAAIDAAYKXwV2EgCHAAADAAYKXwV2EgCHAAAAAA==.Aleinara:BAABNQAECn8cAAIEAAkKqQm/xACSAQAEAAkKqQm/xACSAQAAAA==.',
Am='Amazngrace:BAAANQADCgYIBgAAAA==.',
An='Andsey:BAAANQAECgQICQABNQAECgcIFAAFAMwJAA==.Annore:BAABNQAECn8WAAIGAAcKzRq1SgDqAQAGAAcKzRq1SgDqAQAAAA==.',
Aq='Aquelius:BAABNQAECn8XAAIEAAYK3Q6S7QBBAQAEAAYK3Q6S7QBBAQAAAA==.Aqular:BAABNQAECn8sAAMHAAoKpxEeOAAAAgAHAAoKpxEeOAAAAgAIAAYKFQYnSAAbAQAAAA==.',
Ar='Argyre:BAABNQAECn9BAAICAAoKhiUWAQDHAwACAAoKhiUWAQDHAwAAAA==.Artifice:BAACNQAFFH8MAAIJAAMKwB/DCgAmAQAJAAMKwB/DCgAmAQA1AAQKfyMAAgkACgqzJGQCAI4DAAkACgqzJGQCAI4DAAAA.',
As='Asynic:BAABNQAECn8WAAIKAAcKaxhsCADOAQAKAAcKaxhsCADOAQAAAA==.Asynicl:BAAANQAECgQICwAAAA==.',
Av='Avadakedevra:BAAANQAECggIAQAAAA==.',
Aw='Awooing:BAAANQADCggIDgABNQAECgQICQALAAAAAA==.',
Az='Azaziel:BAABNQAECn8pAAIMAAoKwA1ETQDBAQAMAAoKwA1ETQDBAQAAAA==.Azells:BAAANQADCgEIAQABNQAECgoKJQAJACIeAA==.Azumok:BAAANQADCgcIBwAAAA==.',
Ba='Bail:BAAANQAECgMICwAAAA==.Bariesh:BAAANQADCgQIBAAAAA==.',
Be='Bearface:BAAANQADCgUIBQAAAA==.Behindyou:BAAANQAECgUIBQAAAA==.Belgaria:BAAANQADCggIIwAAAA==.Belloftrix:BAAANQAECgIIAgAAAA==.Berryknight:BAABNQAECn8WAAMGAAgKNxDWWwCgAQAGAAcK2RHWWwCgAQANAAcKWAcuQQAUAQAAAA==.Bewlzeye:BAAANQAECgUIEQAAAA==.',
Bi='Bigjonmachne:BAABNQAECn8fAAMNAAgKjRcuPQDYAQANAAcKHBYuPQDYAQAGAAcKfxaFXQCZAQAAAA==.Bigmooma:BAAANQAECgYIDAAAAA==.Binky:BAAANQADCgUIBQAAAA==.',
Bl='Blackdog:BAAANQAECgIIAwAAAA==.Blackguyy:BAABNQAECn8UAAMOAAYK8BidMgCOAQAOAAYK8BidMgCOAQAPAAEKcAvC+wA0AAAAAA==.Blasphamey:BAAANQADCgQIBAAAAA==.Bloodletter:BAAANQABCgIIAgAAAA==.Bloodsail:BAAANQAECgYIBgAAAA==.',
Bo='Bollux:BAABNQAECn8+AAIQAAkKxBWDCAAvAgAQAAkKxBWDCAAvAgAAAA==.Bonetatter:BAAANQAECgEIAQAAAA==.Bongonnaink:BAABNQAECn82AAMOAAgK6xo0HABjAgAOAAgK6xo0HABjAgARAAEKjxlrJABIAAAAAA==.Bownyxia:BAAANQAECgYIBwABNQAFFAgIGAAGAD8ZAA==.Bowties:BAACNQAFFH8YAAQGAAgKPxkaBgC+AQAGAAcK7xwaBgC+AQANAAUK/hJCBwCIAQAMAAEKAAASMgAxAAA1AAQKf0kABAYACgpzJicEALIDAAYACgpeJScEALIDAA0ACQrJJEgFAIwDAAwAAgqiA4OzAGIAAAAA.',
Br='Brewfú:BAAANQADCgIIAgAAAA==.Brotie:BAACNQAFFH8NAAISAAUKiQ+gCwBmAQASAAUKiQ+gCwBmAQA1AAQKfywAAhIACgoJG7IOAGACABIACgoJG7IOAGACAAE1AAUUCAgYAAYAPxkA.',
Bt='Btmanight:BAABNQAECn8ZAAIGAAkKqQvHJgBDAQAGAAkKqQvHJgBDAQAAAA==.',
Bu='Bullshiift:BAAANQADCgYIBgAAAA==.Burgershaq:BAAANQADCgYIBgAAAA==.Burntbiscuit:BAAANQADCgUIBQAAAA==.Buugada:BAAANQAECgMIBAAAAA==.',
Ca='Caedo:BAAANQADCgIIAgABNQADCgMIAwALAAAAAA==.Caliclysm:BAAANQAECgQIBgAAAA==.Calischism:BAABNQAECn8VAAQRAAcKDhvrCwB+AQARAAUKHBnrCwB+AQAPAAYKTBLxnAA+AQAOAAUK1xOMIgDzAAAAAA==.Canadiangoos:BAAANQADCgUJBQAAAA==.Cantspell:BAAANQAECgIIAgAAAA==.Carobnica:BAAANQADCgQJBAABNQADCgYIBgALAAAAAA==.Cavantes:BAAANQADCgIIAgAAAA==.',
Ce='Celaris:BAAANQAECgQIBwAAAA==.Cell:BAAANQABCgIIAgAAAA==.',
Ch='Chataykay:BAAANQAECgIIAgAAAA==.Chathsong:BAAANQADCggICAAAAA==.Chichichikin:BAAANQADCgcIBwAAAA==.Chunkyclaps:BAAANQADCgEIAQAAAA==.',
Ci='Circë:BAAANQAECgQIBQAAAA==.Citrus:BAABNQAECn8tAAMKAAoKkBF2BgAxAgAKAAoKkBF2BgAxAgAHAAEK6AnfUgE/AAAAAA==.',
Cn='Cn:BAABNQAECn81AAIEAAoKbyCqIwA2AwAEAAoKbyCqIwA2AwAAAA==.',
Co='Codeman:BAABNQAECn82AAIMAAgKCyLDFQD/AgAMAAgKCyLDFQD/AgAAAA==.Cordine:BAAANQADCgYIBgAAAA==.',
Cp='Cptinsaneo:BAACNQAFFH8cAAMNAAYKchYmBQAqAQAGAAUK3xseCQCFAQANAAUKfQsmBQAqAQA1AAQKfzUAAwYACgoyHoAjALUCAAYACgoyHoAjALUCAA0ACQqIFK0XABUCAAAA.',
Cr='Crimdh:BAAANQAECgcICwABNQAFFAcIDgATAC0PAA==.Crimdk:BAAANQAECgcIEgABNQAFFAcIDgATAC0PAA==.Crimwl:BAAANQAECggICAAAAA==.',
Cy='Cynth:BAAANQAECgUIBQAAAA==.',
Cz='Czin:BAAANQAECgIIAgAAAA==.',
Da='Dalén:BAAANQADCgUIBQAAAA==.',
De='Deathverses:BAACNQAFFH8RAAIIAAUKWSbHBAAhAgAIAAUKWSbHBAAhAgA1AAQKf0UAAggACQrIJvABAMoDAAgACQrIJvABAMoDAAAA.Demonbiscuit:BAACNQAFFH8OAAISAAcKHiA+AwBWAgASAAcKHiA+AwBWAgA1AAQKfzYAAhIACgp2Ji8AAJgDABIACgp2Ji8AAJgDAAAA.Denarkis:BAAANQADCgQIBAAAAA==.Derekor:BAAANQAECgMIAwAAAA==.Derpydawg:BAAANQADCgYIBgABNQAFFAQIBgAUAAYEAA==.Destructus:BAAANQAECgEIAgAAAA==.Deviancy:BAABNQAECn83AAMVAAoKCR8RCQA4AwAVAAoKCR8RCQA4AwAEAAIKyg9YewFgAAAAAA==.Devocean:BAAANQADCgUIBQAAAA==.Dexxt:BAAANQAECgMIBgAAAA==.',
Di='Dikslapp:BAAANQAECgUIBQABNQAECggIHAAWADsRAA==.Dirlin:BAAANQADCggIIwAAAA==.Ditto:BAAANQADCggINgAAAA==.',
Dl='Dlitinaro:BAABNQAECn8jAAIMAAoK7CGVEgAYAwAMAAoK7CGVEgAYAwAAAA==.',
Do='Donoph:BAABNQAECn84AAMVAAoKSSTmAQDSAwAVAAoKSSTmAQDSAwAEAAEKAABGhgFRAAAAAA==.Doomar:BAABNQAECn81AAQBAAoKnB/FXgA7AgABAAgKXh/FXgA7AgADAAMKox+LMgD7AAAXAAIKWB3TGgCtAAAAAA==.Dordire:BAAANQAECgEJAQAAAA==.Dotudown:BAAANQAECgQIBAAAAA==.Dotzilla:BAAANQADCgEIAQAAAA==.',
Dr='Dragindznuts:BAAANQADCgYICgAAAA==.Drayn:BAABNQAECn8fAAIBAAgKVB9xOQCnAgABAAgKVB9xOQCnAgAAAA==.Dreaveous:BAABNQAECn8tAAMBAAoK+wtShgDWAQABAAoK+wtShgDWAQADAAUKFQPWQAC/AAAAAA==.Drugar:BAABNQAECn8bAAIFAAYKugSu1ACoAAAFAAYKugSu1ACoAAAAAA==.',
Du='Duint:BAAANQADCgcJDAAAAA==.',
['Dé']='Déathsong:BAAANQABCgQIAwAAAA==.',
Eb='Eborsisk:BAAANQADCgEIAQAAAA==.',
Ec='Eclipsion:BAABNQAECn8WAAIBAAcK1A64sgBqAQABAAcK1A64sgBqAQAAAA==.',
Ee='Eelane:BAAANQAECgQICQAAAA==.',
El='Elementali:BAAANQAECgUICQAAAA==.Ell:BAAANQADCgYIFgAAAA==.Ellennia:BAAANQAECgEIAQAAAA==.Eltain:BAAANQADCgQIBAAAAA==.',
En='Endurall:BAAANQADCggIDAABNQAECgoKNgAYALIYAA==.',
Er='Eradication:BAACNQAFFH8IAAIZAAcKlw+MEwCRAQAZAAcKlw+MEwCRAQA1AAQKfycAAhkACgrXI0UOAIkDABkACgrXI0UOAIkDAAAA.',
Et='Etheria:BAAANQAECggICQABNQAFFAYIFQAaAHMXAA==.',
Ev='Everfale:BAAANQAECgEIAgABNQAFFAcICAAZAJcPAA==.Evilexo:BAAANQADCgcIBwAAAA==.',
Ex='Exxotic:BAAANQABCgIIAgAAAA==.',
Fa='Faedia:BAAANQAECgQIAwABNQAECgcIFAAFAMwJAA==.Fahlafflez:BAABNQAECn8eAAMWAAkKcAtcDwC2AQAWAAkKcAtcDwC2AQAZAAYKEAYm8gD7AAAAAA==.Fahros:BAAANQAECgYIDgAAAA==.Farkhaz:BAAANQADCggICAAAAA==.Faydron:BAAANQADCgMJAwABNQAECgkJLwAaAPgVAA==.',
Ff='Ffloyd:BAAANQAECgQIBwAAAA==.',
Fi='Fingielock:BAABNQAECn8bAAIBAAkKDQvboQCSAQABAAkKDQvboQCSAQAAAA==.Firedeezball:BAAANQADCgcIBwAAAA==.Fishinfridge:BAABNQAECn8aAAIbAAoKgA4PEAALAgAbAAoKgA4PEAALAgAAAA==.',
Fl='Flloyd:BAABNQAECn84AAIcAAoKCReNCwB/AgAcAAoKCReNCwB/AgAAAA==.Floÿd:BAAANQAECgYICwAAAA==.Fløyd:BAAANQADCgYIBgAAAA==.',
Fo='Folid:BAAANQAECgEIAQAAAA==.Fortwooh:BAAANQADCggIJQAAAA==.',
Fr='Francy:BAAANQAECgYICAAAAA==.',
Fu='Fuzzyspells:BAAANQAECgQICQAAAA==.',
Ga='Gaftard:BAAANQAECgUIBQAAAA==.Gambling:BAAANQADCggICAAAAA==.Gatzul:BAAANQADCgMIBAABNQADCggICAALAAAAAA==.',
Gh='Ghostbladez:BAAANQAECgQJCAAAAA==.',
Gi='Gib:BAAANQADCgMIAwAAAA==.Girthmaster:BAAANQADCgQIBAAAAA==.',
Gn='Gnomaste:BAAANQADCgcIGgAAAA==.',
Go='Goththighs:BAACNQAFFH8WAAMFAAcKkR+9CAA7AgAFAAYKcx69CAA7AgAUAAEKCCSZBgBpAAA1AAQKfy0AAwUACgoIJtgxACcDAAUACgoxJdgxACcDABQABQp7JXwHALQBAAAA.',
Gr='Grawler:BAAANQAECgQICgAAAA==.Grimdk:BAAANQAECgMICwAAAA==.Grissa:BAABNQAECn8YAAIBAAkKMgZjvABUAQABAAkKMgZjvABUAQAAAA==.',
Gu='Gumgumfury:BAAANQAECgEIAQAAAA==.',
Ha='Haidies:BAAANQAECgQIBAABNQAECggICAALAAAAAA==.Halru:BAAANQADCgYICwAAAA==.Halzlok:BAABNQAECn8lAAIdAAcKghP2VgAIAQAdAAcKghP2VgAIAQAAAA==.Harmful:BAAANQADCgcIBwABNQAECggIFQAYADsfAA==.',
He='Herøn:BAAANQADCgYICgAAAA==.Heyheypeople:BAAANQAECgcICAABNQAFFAIIBgAaAGIPAA==.',
Hi='Hilarie:BAAANQADCgYICwAAAA==.',
Hu='Hundigob:BAAANQABCgUIBgAAAA==.Hunterschmax:BAABNQAECn8oAAMHAAgKdBaGcAAwAgAHAAgKdBaGcAAwAgAIAAMK8QjUaQCGAAAAAA==.',
Ic='Icemachine:BAAANQABCgUIBwAAAA==.',
Ih='Ihot:BAAANQAECgcIEgAAAA==.',
Ik='Ikayhaimahn:BAABNQAECn8aAAIeAAkKWiKSAwB9AwAeAAkKWiKSAwB9AwAAAA==.',
In='Incideranus:BAAANQADCggIBAAAAA==.Indimonk:BAAANQAECgEIAQAAAA==.Indishaman:BAACNQAFFH8FAAIaAAMK7h2ADAAaAQAaAAMK7h2ADAAaAQA1AAQKfy4AAhoACgqNJA4FAJ8DABoACgqNJA4FAJ8DAAAA.',
Ir='Iris:BAAANQADCgMIAwAAAA==.Iritara:BAAANQAECgQIBAAAAA==.Ironbound:BAAANQADCgUIBQABNQAECgkJNAAaAIUdAA==.',
Iv='Ivoric:BAAANQAECggICAAAAA==.',
Ja='Jabronygos:BAACNQAFFH8WAAIfAAYKGRc3AQAYAQAfAAYKGRc3AQAYAQA1AAQKfy4AAh8ACgo7HssGABoDAB8ACgo7HssGABoDAAAA.Jarnroz:BAAANQADCgIIAgAAAA==.Jaythirian:BAAANQAECgcIDQAAAA==.',
Je='Jeatalena:BAABNQAECn8XAAIBAAUKUhAZ3wALAQABAAUKUhAZ3wALAQAAAA==.Jengà:BAAANQAECgQIBAABNQAECgoKPwAFALQiAA==.Jerg:BAAANQAECgQICgABNQAECggICAALAAAAAA==.',
Jh='Jhara:BAABNQAECn8UAAIFAAcKzAlvKAFIAQAFAAcKzAlvKAFIAQAAAA==.',
Jo='Joeheals:BAAANQADCgUIBwAAAA==.',
Ju='Junior:BAAANQAECgUIBgABNQAECgoKJQAJACIeAA==.',
Ka='Kablinkiaa:BAAANQAECgIIAgAAAA==.Kaendas:BAAANQAECgIIAgAAAA==.Kaizayu:BAAANQAECgIIBAAAAA==.Kalier:BAAANQAECgQIBQAAAA==.Kalish:BAAANQADCgQIBAAAAA==.Kalistria:BAAANQADCgIIAgAAAA==.Kalypso:BAABNQAECn8fAAIaAAcK8RnCMADfAQAaAAcK8RnCMADfAQAAAA==.Kamekazi:BAAANQADCggICQAAAA==.Katastrophic:BAAANQADCggIEwAAAA==.Katazul:BAAANQADCgQIBAABNQADCggIEwALAAAAAA==.Katieylyn:BAABNQAECn8lAAQJAAoKIh4rDADVAgAJAAoKDh4rDADVAgAYAAUKDBDOYAAyAQAgAAIK8w4fFwB0AAAAAA==.',
Ke='Keelanllan:BAAANQAECgEIAQAAAA==.Keilun:BAEANQADCgQIBAAAAA==.Kertzz:BAAANQAECgEIAQABNQAECgEIAQALAAAAAA==.Kew:BAAANQAECgIIAgAAAA==.',
Ki='Kimjitswho:BAAANQADCgQIBAAAAA==.Kirby:BAAANQAECggIBAABNQAECggICAALAAAAAA==.Kizira:BAAANQAECgQIAwABNQAECgcIFAAFAMwJAA==.Kiznx:BAAANQADCgIIAgABNQADCgYIBgALAAAAAA==.',
Kn='Kneecromance:BAAANQAECgEJAQAAAA==.Knightxl:BAAANQADCgEIAQAAAA==.',
Ko='Koggmaw:BAAANQADCgUIBQABNQAECggICAALAAAAAA==.Kokuten:BAAANQADCgQIBAABNQAFFAYIFQAaAHMXAA==.Koral:BAAANQAECgMIBgAAAA==.',
Ku='Kungfuhealya:BAABNQAECn8ZAAIhAAcKAAgdKgAfAQAhAAcKAAgdKgAfAQAAAA==.Kurog:BAAANQABCgEIAQAAAA==.',
La='Larrydale:BAAANQADCgYICwAAAA==.Lazerturkey:BAAANQADCgcIBwAAAA==.',
Le='Lea:BAAANQADCgcIBwABNQADCgYIBgALAAAAAA==.Lefica:BAAANQABCgIJAgAAAA==.Legacyx:BAAANQADCgcIDAABNQAFFAcICAAZAJcPAA==.Leonardorich:BAAANQADCgcIEQAAAA==.Leondis:BAABNQAECn86AAIHAAoKBCB5DgBtAwAHAAoKBCB5DgBtAwAAAA==.Lexifu:BAACNQAFFH8MAAIcAAYKcAcNCQBWAQAcAAYKcAcNCQBWAQA1AAQKf04AAxwACgp8IQADAIUDABwACgp8IQADAIUDACIABQrcCyt2APIAAAAA.Lexipriest:BAAANQAECgYIDAAAAA==.Leylla:BAAANQADCgMIAwABNQAECgEIAQALAAAAAA==.',
Li='Lightful:BAABNQAECn89AAIEAAoKTR07KQBcAgAEAAoKTR07KQBcAgAAAA==.Lilbro:BAACNQAFFH8UAAIZAAcKAxUfBwBOAgAZAAcKAxUfBwBOAgA1AAQKfy4AAhkACgrQId8NAIsDABkACgrQId8NAIsDAAAA.Lit:BAAANQADCggIDQABNQAECggIFQAYADsfAA==.',
Lo='Lobais:BAAANQAECgQIAwABNQAECggIDAALAAAAAA==.Lokii:BAAANQABCgMIAwAAAA==.',
Lu='Lucifel:BAAANQAECgYIBgAAAA==.Lumiel:BAAANQABCgcICwAAAA==.Lumos:BAAANQADCggICAAAAA==.Lumosmaxiima:BAAANQADCggIFAAAAA==.',
Ma='Madamme:BAAANQAECgYJDQAAAA==.Madkingzack:BAABNQAECn8eAAIZAAgK6hjZdAA2AgAZAAgK6hjZdAA2AgAAAA==.Madpriest:BAAANQADCgcIBwAAAA==.Maevea:BAAANQAECgQIBgAAAA==.Malagig:BAAANQADCgIIAgAAAA==.Malaviolence:BAAANQABCgcIDAAAAA==.Malistavias:BAABNQAECn8cAAIBAAkKlRUqXABDAgABAAkKlRUqXABDAgAAAA==.Malliki:BAAANQAECgUIBQAAAA==.Marnangus:BAABNQAECn8vAAMZAAkKLRsdaQBVAgAZAAkKGBsdaQBVAgAWAAMKKRCtGgBnAAABNQAECgQIBAALAAAAAA==.Marnolkas:BAAANQADCggICgABNQAECgQICAALAAAAAA==.Mathan:BAABNQAECn8xAAIVAAoKTSY5AwC2AwAVAAoKTSY5AwC2AwAAAA==.Maudib:BAABNQAECn8vAAMeAAkKMBP/GADkAQAeAAgKqhH/GADkAQAbAAgKfw43FAC4AQAAAA==.Mawile:BAABNQAECn8lAAQeAAgKjhCFLAA0AQAeAAUKMBOFLAA0AQAiAAgKpQ0DMwAEAQAbAAQKbwlXKwC2AAAAAA==.',
Me='Meesha:BAAANQAECgQICQAAAA==.Melinarra:BAABNQAECn8aAAIVAAYKJBFmaQAGAQAVAAYKJBFmaQAGAQAAAA==.Messe:BAABNQAECn82AAMYAAoKshgHBwAwAgAYAAoKshgHBwAwAgAgAAYKARXbDQBjAQAAAA==.Methious:BAAANQAECgMIBAAAAA==.',
Mi='Milicious:BAAANQABCgMJBQAAAA==.Mindcontrol:BAAANQAECgcIEQABNQAECgoKJQAHAL0dAA==.',
Mo='Molatile:BAAANQAECgYIEQAAAA==.Montu:BAAANQAECgcIBQAAAA==.Moogyver:BAAANQABCggIEQAAAA==.Moonrivr:BAAANQABCgEIAQABNQAECggKIQANANQLAA==.Moonsguard:BAAANQADCggIHwAAAA==.Moovit:BAAANQAECgQIBwAAAA==.Mordekaíser:BAAANQAECgIIAgAAAA==.Moth:BAABNQAECn8WAAIFAAgKzBKVtwAUAgAFAAgKzBKVtwAUAgAAAA==.',
Mu='Murre:BAAANQADCgYIBgAAAA==.',
Na='Naasmiu:BAAANQADCgYIBgABNQAECgIIBQALAAAAAA==.Nachodps:BAAANQADCgYIBgAAAA==.Nachokimbo:BAAANQADCggIEAAAAA==.Nasmiuu:BAAANQAECgIIBQAAAA==.',
Ne='Nekfury:BAABNQAECn8vAAIdAAoK1xdHHQARAgAdAAoK1xdHHQARAgAAAA==.Nekmane:BAAANQAECgUIBwAAAA==.Nepeta:BAABNQAECn8nAAQbAAkKAx2GBQAxAgAbAAgKhBuGBQAxAgAeAAYKwR1yFgADAgAiAAQKZhW6fgDSAAAAAA==.Nevenel:BAAANQADCgMIAwAAAA==.',
Ni='Nivan:BAABNQAECn8aAAMjAAYKmgTxPABeAAAEAAYKlQRBQAG5AAAjAAQK2QLxPABeAAAAAA==.Nixdorf:BAAANQAECggICAAAAA==.Niço:BAAANQAECgcICQAAAA==.',
No='Nocturnall:BAAANQADCgQIBAAAAA==.Noicce:BAABNQAECn8eAAIbAAkKRxpNCQC0AgAbAAkKRxpNCQC0AgAAAA==.Noiceshm:BAAANQAECgYIBwAAAA==.Noicewar:BAAANQAECgIIAgAAAA==.Notcrims:BAACNQAFFH8OAAITAAcKLQ/pBQC3AQATAAcKLQ/pBQC3AQA1AAQKfyUAAhMACgq5IT4GAMQCABMACgq5IT4GAMQCAAAA.Notcrym:BAAANQAECgEIAQABNQAFFAcIDgATAC0PAA==.',
Nu='Numrea:BAAANQADCgIIAgAAAA==.Nutz:BAAANQAECggICAAAAA==.',
Oa='Oakmoss:BAABNQAECn8lAAIZAAoK9hj/LAAoAgAZAAoK9hj/LAAoAgAAAA==.',
Or='Oralian:BAAANQADCggICAAAAA==.Orcleave:BAABNQAECn8jAAMZAAoK/SAfEgDUAgAZAAkK7CAfEgDUAgAWAAgKexokCQBJAgAAAA==.Orestes:BAAANQAECgQIBAABNQAECgoKOAAVAEkkAA==.Orwan:BAAANQAECgQIBgAAAA==.',
Pe='Pea:BAAANQAECgQIBAABNQADCgYIBgALAAAAAA==.',
Ph='Phoenyx:BAAANQADCgUIDQAAAA==.',
Pi='Pisslowmage:BAAANQAECggIDQABNQAECgoKIwAZAP0gAA==.',
Pr='Pristene:BAABNQAECn8ZAAIOAAgKqhG6GwAvAQAOAAgKqhG6GwAvAQAAAA==.Priyatama:BAAANQAECgcIEQAAAA==.',
Qu='Quorra:BAAANQADCgUJBgAAAA==.',
Ra='Ragecakes:BAAANQADCgYIBQAAAA==.Rakagar:BAAANQAECgUICQAAAA==.Raktot:BAAANQADCgEIAQAAAA==.Ranko:BAAANQAECgIIBAAAAA==.Razluz:BAAANQADCggIHwAAAA==.',
Re='Reue:BAABNQAECn8lAAIhAAkKjQ82GgDcAQAhAAkKjQ82GgDcAQAAAA==.',
Rh='Rhaegos:BAAANQAECgQICAAAAA==.',
Ri='Riggzz:BAAANQAECgQIBAAAAA==.',
Ru='Ruuna:BAAANQABCgIIAgAAAA==.',
Ry='Ryumali:BAAANQADCgYIBgAAAA==.',
['Rí']='Rígg:BAAANQAECgEIAQAAAA==.',
Sa='Salla:BAAANQAECgQIBAAAAA==.Sapsipper:BAAANQABCgQIBgAAAA==.',
Sc='Schmaximus:BAAANQADCgcIDwABNQAECggIKAAHAHQWAA==.Scrapyjack:BAABNQAECn8eAAISAAoK+hm3KABaAgASAAoK+hm3KABaAgABNQAECgoKIwAMAOwhAA==.',
Se='Senna:BAAANQADCgMIAwAAAA==.Sensitive:BAAANQAECggIEAAAAA==.',
Sh='Shale:BAABNQAECn81AAIkAAoKAQ4kHQD6AQAkAAoKAQ4kHQD6AQAAAA==.Shammit:BAAANQADCgIIAgAAAA==.Shammytyme:BAAANQAECgYIEQAAAA==.Shampow:BAABNQAECn8VAAIdAAcKyQ/sfwClAQAdAAcKyQ/sfwClAQAAAA==.Shamyhagar:BAAANQADCgQIBAAAAA==.Shangtsung:BAACNQAFFH8LAAIcAAQK8REJCADgAAAcAAQK8REJCADgAAA1AAQKfzcAAxwACgqgIscHAEcDABwACgqgIscHAEcDACIAAgqhEJqXAHoAAAAA.Sharaiya:BAABNQAECn8mAAMcAAgK2wM7LwDsAAAcAAgK2wM7LwDsAAAiAAIKdQJLaAA8AAAAAA==.Sharkmanfive:BAAANQAECgQICAAAAA==.Shaure:BAAANQADCgIIAgAAAA==.Shearwater:BAAANQAECggIEgAAAA==.',
Si='Silmeriaa:BAAANQABCgIIAgAAAA==.Silversesu:BAAANQAECgEIAQABNQAECgoKIQAFADsVAA==.',
Sk='Skippybmm:BAAANQAECgQIBwABNQAECggIDAALAAAAAA==.Skirtero:BAAANQADCgYIBgAAAA==.',
Sl='Slappydappy:BAAANQADCgYIBgABNQAFFAYIDAAVADsRAA==.Slava:BAAANQAECggIDwAAAA==.Sledgehammer:BAAANQAECgEIAQAAAA==.Sleepytoker:BAAANQADCgYICwAAAA==.',
So='Soferus:BAAANQAECgEIAQABNQAECgQICAALAAAAAA==.Softbaked:BAAANQADCgUIBgAAAA==.Soltergeist:BAACNQAFFH8FAAIMAAMKXhJXDQDBAAAMAAMKXhJXDQDBAAA1AAQKfy4AAgwACgpFGQgxAEwCAAwACgpFGQgxAEwCAAAA.Soulweaver:BAAANQAECggICAAAAA==.',
Sp='Spine:BAAANQAECggIDAAAAA==.',
Ss='Ssyd:BAAANQADCggICAAAAA==.',
St='Staras:BAAANQADCgMIAwAAAA==.Starlsbarkly:BAAANQADCgUIBQAAAA==.Steaknshock:BAAANQAECgYIBwAAAA==.Stormhoofs:BAACNQAFFH8NAAIQAAYK1BzlAQDbAQAQAAYK1BzlAQDbAQA1AAQKf1cAAhAACgpPJmkAAOYDABAACgpPJmkAAOYDAAAA.',
Su='Subzone:BAABNQAECn8ZAAISAAgKgx6FJgBpAgASAAgKgx6FJgBpAgAAAA==.Sumnabiscuit:BAACNQAFFH8GAAMUAAQKBgT2AgD3AAAUAAQK7AL2AgD3AAAFAAIKPwNVUgB3AAA1AAQKfxoAAwUACQr6Fk+4ABMCAAUACQoZFE+4ABMCABQAAwqGE4UlAMMAAAAA.Sunmaster:BAABNQAECn8bAAMBAAgKBxN2mgCkAQABAAgKrw92mgCkAQADAAMKShPlQQC8AAAAAA==.Supercharged:BAAANQADCggICAAAAA==.',
['Sê']='Sêlene:BAAANQABCggICAAAAA==.',
Ta='Tackshi:BAAANQADCggIDAAAAA==.Tankinit:BAAANQAECgIIBQAAAA==.Tarea:BAAANQADCgQIBwAAAA==.Tatterbone:BAAANQADCgYIEAABNQAECgEIAQALAAAAAA==.',
Tb='Tbolt:BAAANQAECgUIBwABNQAECgoKPwAFALQiAA==.',
Te='Temufuzzy:BAAANQADCgEJAQAAAA==.Tenzink:BAABNQAECn8qAAIhAAoKQBu/CwDJAgAhAAoKQBu/CwDJAgAAAA==.',
Tf='Tflow:BAABNQAECn8/AAIFAAoKtCJCCwD+AgAFAAoKtCJCCwD+AgAAAA==.',
Th='Théworld:BAAANQABCgIIBAABNQADCggIHwALAAAAAA==.',
Ti='Tindranga:BAAANQAECgQIBAAAAA==.Titansgrippy:BAABNQAECn8cAAIWAAgKOxEkCgBmAQAWAAgKOxEkCgBmAQAAAA==.',
To='Tolbert:BAAANQADCgMIAwABNQADCgYIBgALAAAAAA==.Totemir:BAABNQAECn8YAAIdAAcKKh/wOgCKAgAdAAcKKh/wOgCKAgAAAA==.Towani:BAAANQADCggIDwAAAA==.',
Tr='Trammatize:BAABNQAECn8WAAIFAAcKYxKt7wCrAQAFAAcKYxKt7wCrAQAAAA==.Triptamean:BAAANQADCggIFwAAAA==.',
Tw='Twobladebray:BAABNQAECn8iAAQlAAkKkBanJAAhAgAlAAgKCRenJAAhAgAmAAEK2BmHLgBGAAASAAEKMw4ukQA4AAAAAA==.',
Un='Undeadnite:BAAANQAECgcIDwAAAA==.Unglaus:BAAANQAECgYIBgAAAA==.',
Uz='Uzington:BAACNQAFFH8JAAICAAMKaR+7AwARAQACAAMKaR+7AwARAQA1AAQKfykAAwIACQoKIzUFACYDAAIACQoKIzUFACYDABkAAgr1FPS8AJIAAAAA.',
Va='Valeta:BAAANQADCggILAAAAA==.Vali:BAAANQAECgIIAgAAAA==.Valzlok:BAAANQAECgQICAAAAA==.Vanessa:BAABNQAECn8uAAIgAAoK0xGvBwA1AgAgAAoK0xGvBwA1AgAAAA==.Vanillacream:BAAANQADCgMIAwAAAA==.Vayth:BAAANQADCggICAAAAA==.',
Ve='Veilthorn:BAAANQAECgEIAgAAAA==.Velinieron:BAABNQAECn8ZAAMHAAoK8hgSRQCdAgAHAAoK8hgSRQCdAgAIAAMKcwnSaACJAAAAAA==.Velinvieron:BAAANQAECgIIAgABNQAECgoKGQAHAPIYAA==.Velithiri:BAAANQAECgQIDgAAAA==.Vellash:BAAANQADCgEIAQAAAA==.',
Vi='Vilencia:BAAANQABCggIDQAAAA==.Vince:BAAANQADCgUIBgAAAA==.Vinny:BAAANQABCgIIAgAAAA==.',
Vo='Voidjoe:BAAANQAECgUIBAAAAA==.Vonulter:BAABNQAECn8ZAAIHAAYK4wsV2ABQAQAHAAYK4wsV2ABQAQAAAA==.',
Vy='Vylon:BAABNQAECn8WAAIZAAgKQRnycwA5AgAZAAgKQRnycwA5AgAAAA==.Vynlandis:BAAANQAECgEIAQAAAA==.Vyrel:BAAANQADCgYICgAAAA==.',
['Vê']='Vêga:BAAANQAECgcIBwABNQAFFAQIBgAUAAYEAA==.',
Wa='Warbezerker:BAAANQADCgcIBwAAAA==.Waycores:BAAANQAECgYIBQAAAA==.',
We='Weenbean:BAAANQAECgYICAABNQAECgoKFwAEADAWAA==.',
Wh='Whakoopa:BAAANQAECgQIBAAAAA==.Whispertree:BAABNQAECn88AAIiAAoK7BqBEAA/AgAiAAoK7BqBEAA/AgAAAA==.Whìspèr:BAAANQAECgIIAgAAAA==.',
Wi='Wilddonut:BAAANQADCgQJBAAAAA==.Wiseguys:BAABNQAECn8gAAQGAAoK4B9qFQAPAwAGAAkKtB1qFQAPAwAMAAcK8hdVSgDOAQANAAcK4hfxIQC9AQABNQAFFAQIBgAUAAYEAA==.Wixypoo:BAAANQAECgEIAQAAAA==.',
Wo='Woodnzhood:BAAANQAECgMIAwAAAA==.Worhammer:BAAANQADCgYIBgAAAA==.',
Wr='Wrylah:BAABNQAECn8dAAIfAAoK6BJ5FQD1AQAfAAoK6BJ5FQD1AQAAAA==.',
Wu='Wuxian:BAAANQADCgYIBgABNQAFFAYIFQAaAHMXAA==.',
Wy='Wyyn:BAAANQAECgcIDgAAAA==.',
Xa='Xanboi:BAABNQAECn82AAMHAAgKZiYkGQCPAgAHAAgKZiYkGQCPAgAIAAEKSh9/egBXAAAAAA==.Xaodia:BAAANQADCgMIAwAAAA==.',
Xe='Xegos:BAAANQADCgQIBAAAAA==.Xeonia:BAAANQADCgMIAwAAAA==.',
Yi='Yikkle:BAAANQABCgIIAwAAAA==.',
Yo='Yosi:BAAANQAECgEIAQAAAA==.Youri:BAAANQAECgIIBAAAAA==.',
Ys='Ysar:BAABNQAECn8kAAMnAAgKGAkSEAA8AQAnAAgKGAkSEAA8AQAfAAEKugTsQAApAAAAAA==.',
Yu='Yumzug:BAAANQADCgQIBAAAAA==.',
['Yô']='Yôshi:BAAANQAECggICAAAAA==.',
Ze='Zeebu:BAABNQAECn8aAAIKAAcKrQc0BwAaAQAKAAcKrQc0BwAaAQAAAA==.Zenful:BAAANQAECgUICwABNQAECgoKPQAEAE0dAA==.Zephryyn:BAAANQAECgEIAQAAAA==.',
Zh='Zhilan:BAABNQAECn84AAIcAAkKGRJOGwCNAQAcAAkKGRJOGwCNAQAAAA==.',
Zi='Zilliwax:BAAANQADCgYIBgAAAA==.',
Zo='Zoda:BAAANQADCgQIBgAAAA==.Zoko:BAAANQAECgEIAQAAAA==.',
Zu='Zurgadhunter:BAABNQAECn8fAAImAAgK2h2BBwCOAgAmAAgK2h2BBwCOAgAAAA==.Zuzuk:BAAANQADCgMIAwAAAA==.Zuzuki:BAAANQAECgIIAgAAAA==.',
['Zú']='Zúz:BAAANQAECgYIDwAAAA==.',
['Ða']='Ðalinor:BAAANQADCggICAAAAA==.',
['Ðe']='Ðemaea:BAAANQADCgUIAwAAAA==.',
['Ði']='Ðittø:BAAANQADCgIIAgABNQADCggINgALAAAAAA==.',
['Øc']='Øctø:BAAANQAECgEIAQAAAA==.',
['Ør']='Øreø:BAABNQAECn8xAAImAAoK0SAQAwA+AwAmAAoK0SAQAwA+AwAAAA==.',
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
