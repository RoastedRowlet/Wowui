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

local lookup = {'Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Evoker-Devastation','Evoker-Preservation','DeathKnight-Unholy','Shaman-Restoration','Paladin-Protection','Priest-Discipline','DeathKnight-Blood','Monk-Windwalker','Monk-Mistweaver','Warrior-Arms','Paladin-Retribution','Priest-Shadow','Druid-Guardian','Druid-Restoration','DeathKnight-Frost','Priest-Holy','Warlock-Demonology','Shaman-Elemental','Druid-Balance','DemonHunter-Devourer','Warrior-Fury','Mage-Arcane','DemonHunter-Havoc','Hunter-BeastMastery','Paladin-Holy','DemonHunter-Vengeance','Warlock-Destruction','Warrior-Protection','Druid-Feral','Shaman-Enhancement','Hunter-Marksmanship','Evoker-Augmentation','Warlock-Affliction',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aastrid:BAAANQADCggIGgAAAA==.',
Ad='Adorabúll:BAAANQAECgEIAgAAAA==.',
Ae='Aevriia:BAAANQADCgIIAgAAAA==.',
Ah='Ahrus:BAAANQADCgUIBQABNQAECgIIAwABAAAAAA==.',
Ak='Akåshå:BAAANQADCggIDwAAAA==.Akélla:BAAANQAECggICAAAAA==.',
Al='Aldric:BAAANQAECgQIBQAAAA==.Alien:BAACNQAFFH8FAAICAAMKKRNlDwDzAAACAAMKKRNlDwDzAAA1AAQKfxoAAwMACQriGNofAB8CAAMACQoLFdofAB8CAAIABgr2GNQgAP4AAAAA.Althenzdormu:BAABNQAECn8dAAMEAAcKEQWXEADIAAAEAAcKEQWXEADIAAAFAAIKAQH0TwAuAAAAAA==.Altruist:BAAANQAECgUIEAABNQAECgkJLQAGAG8SAA==.',
Am='Amaethon:BAAANQAECgUIEQAAAA==.',
An='Ancaera:BAAANQAECgEIAQAAAA==.Andalikus:BAABNQAECn8qAAIHAAgKfyPFFgAbAwAHAAgKfyPFFgAbAwAAAA==.Andorra:BAAANQADCgYICwAAAA==.Andybocelli:BAEANQADCgcIDQABNQAECgoKNgAIAIkhAA==.Anrien:BAABNQAECn8mAAIJAAkKWiEZAQDCAgAJAAkKWiEZAQDCAgAAAA==.',
Ar='Ari:BAAANQADCgcIBwAAAA==.Around:BAAANQAECgQICAAAAA==.',
As='Asharal:BAAANQAECgEIAQAAAA==.',
At='Atriste:BAABNQAECn8tAAMGAAkKbxJXHACRAQAGAAkKbxJXHACRAQAKAAUKSgf1jwDFAAAAAA==.',
Au='Aunyx:BAABNQAECn8sAAICAAkK2A6PDAC2AQACAAkK2A6PDAC2AQAAAA==.',
Az='Azenoth:BAAANQADCggIGgAAAA==.',
Ba='Babajaga:BAAANQADCgIJAgAAAA==.Baloth:BAAANQADCgYIDAABNQAECgkJKwALAF8QAA==.',
Be='Beej:BAABNQAECn80AAIMAAoKFBgiDwCPAgAMAAoKFBgiDwCPAgAAAA==.',
Bi='Biggooch:BAABNQAECn8gAAINAAgKphbOgQAWAgANAAgKphbOgQAWAgAAAA==.Bigocritties:BAAANQAECgEIAQAAAA==.Bison:BAAANQADCgcIBwAAAA==.',
Bl='Blackrose:BAAANQADCggIGwABNQAECgoKKgANADAZAA==.Blightbeard:BAABNQAECn8VAAIGAAkKtgkONADzAAAGAAkKtgkONADzAAAAAA==.Blîss:BAABNQAECn8XAAIOAAUKJAPOBQF3AAAOAAUKJAPOBQF3AAAAAA==.',
Bo='Bowjobs:BAAANQADCgYIBgABNQAECgYIGQAKAF0WAA==.',
Br='Brayliel:BAAANQADCgQIBQAAAA==.Brut:BAAANQAECgcIEgABNQAECgoKMAAPAEsgAA==.',
Bu='Bullsi:BAAANQAECgEIAQABNQAECgoKSAAQAI4cAA==.Bumpy:BAAANQADCggICAAAAA==.Bustus:BAABNQAECn8sAAIRAAkKFAyTHwBiAQARAAkKFAyTHwBiAQAAAA==.',
Ca='Calinia:BAAANQABCgUIBwAAAA==.Camma:BAAANQABCgYIBgAAAA==.Carole:BAABNQAECn9JAAQSAAoKih3SFAAwAgAGAAgKlyBVKACYAgASAAoKlxbSFAAwAgAKAAYKChRNagBKAQAAAA==.Caroll:BAABNQAECn8wAAQPAAoKSyDoDAAcAwAPAAgKmyPoDAAcAwATAAYKmBFiuADvAAAJAAMKQgvMGgCTAAAAAA==.Carsomavra:BAAANQADCgYIEgAAAA==.Cathercy:BAABNQAECn8eAAIOAAYKAA946ABKAQAOAAYKAA946ABKAQAAAA==.',
Ch='Chenzhen:BAAANQAECgcIDgAAAA==.Chilly:BAAANQAECgMIAgABNQAFFAUIBwAMAMsHAA==.Chrollo:BAAANQAECgcIEQAAAA==.Chunt:BAAANQADCgYIDQAAAA==.',
Cl='Cloggy:BAAANQADCgYIBgABNQAFFAYIDQAUAC8aAA==.',
Co='Connery:BAAANQADCggIDgAAAA==.Corannis:BAABNQAECn8qAAIVAAkKmxW+LACrAQAVAAkKmxW+LACrAQAAAA==.Corax:BAAANQAECgEIAQAAAA==.',
Cr='Cranberries:BAAANQAECgMIBAABNQAECgoKNQAHAOIMAA==.Cravedog:BAABNQAECn83AAMQAAgKLiOEBgAnAwAQAAgKLiOEBgAnAwAWAAMKZAsnkwCLAAAAAA==.Creepi:BAABNQAECn8eAAMJAAYKXx/qAgDUAQAJAAYKXx/qAgDUAQAPAAYKyRHZNgBtAQAAAA==.Crockett:BAAANQADCgUIBwABNQAECgEIAwABAAAAAA==.Cromgabhar:BAAANQADCggICAABNQAECgYIGQAKAF0WAA==.',
Cu='Cupcáke:BAABNQAECn8eAAIOAAoK+Re5TwDHAQAOAAoK+Re5TwDHAQAAAA==.Curthodnes:BAAANQADCgIJAgAAAA==.',
Da='Dalmas:BAAANQADCgUIDQAAAA==.Dalsho:BAAANQAECgUIBQAAAA==.Damaso:BAABNQAECn8UAAIPAAcKugyNIgDzAAAPAAcKugyNIgDzAAAAAA==.Damik:BAAANQAECgEIAQAAAA==.Darku:BAABNQAECn8qAAIPAAkKix/PCwAqAgAPAAkKix/PCwAqAgAAAA==.Darlàrk:BAAANQAECgcIEwAAAA==.Dawnmane:BAACNQAFFH8HAAIIAAQKwx0HAwAAAQAIAAQKwx0HAwAAAQA1AAQKfxwAAggACgqcI+IBAD8DAAgACgqcI+IBAD8DAAAA.',
De='Deadlie:BAAANQAECgEIAQAAAA==.Deathsquaad:BAAANQAFFAEIAQAAAA==.Delderach:BAABNQAECn8eAAIIAAYKXxemJgCpAQAIAAYKXxemJgCpAQAAAA==.Dellila:BAAANQABCgcIBwAAAA==.Denin:BAABNQAECn8iAAICAAgK6BPsDgCUAQACAAgK6BPsDgCUAQAAAA==.Derphardigan:BAAANQADCgYIBgABNQAECgYIGQAKAF0WAA==.',
Di='Diego:BAAANQADCgMIBAAAAA==.Dirkette:BAABNQAECn8kAAIJAAgKvwj2DABnAQAJAAgKvwj2DABnAQAAAA==.Dirksavoid:BAAANQAECgEIBAABNQAECggIJAAJAL8IAA==.',
Dk='Dkxsmurfx:BAAANQAECgEIAQAAAA==.',
Do='Dokai:BAABNQAECn8rAAILAAkKXxDiFQCPAQALAAkKXxDiFQCPAQAAAA==.Doof:BAAANQAECgEIAQAAAA==.',
Dr='Dracmiz:BAAANQAECgcICgABNQAECgoKOgAIAGAfAA==.Drathan:BAAANQADCgMJAwAAAA==.',
Dt='Dthnght:BAAANQADCgQIBwAAAA==.',
Du='Duskweaver:BAAANQADCgIIAgAAAA==.',
Ea='Earthboy:BAAANQADCgIIAgABNQAECgoKMAAPAEsgAA==.',
Ed='Edamina:BAAANQABCgYIDwAAAA==.',
El='Elaenei:BAAANQADCgcIFgAAAA==.Eliance:BAABNQAECn8cAAICAAYKcAQiMwCiAAACAAYKcAQiMwCiAAAAAA==.Elienn:BAAANQADCgcIGAAAAA==.Elinore:BAAANQADCgQIBAAAAA==.Elmer:BAAANQAECgEIAQAAAA==.',
Er='Errius:BAABNQAECn8nAAIKAAcKZAtAbABDAQAKAAcKZAtAbABDAQAAAA==.',
Es='Esh:BAAANQADCgQIBAABNQAECgoKFgARAAAaAA==.',
Eu='Eunja:BAEANQADCggIMwAAAQ==.',
Ey='Eyowynne:BAAANQADCgIIAgAAAA==.',
Fa='Facetious:BAAANQADCgIIAgAAAA==.Fatherbetter:BAAANQAECgIIAgABNQAFFAMIBwAXAJgUAA==.',
Fi='Filharmonic:BAAANQAECgEIAQAAAA==.Fizzbin:BAAANQADCgQIBwAAAA==.',
Fo='Foid:BAACNQAFFH8JAAMYAAMKnBuqAQARAQAYAAMKnBuqAQARAQANAAEKWA1BPwBBAAA1AAQKfxoAAxgACQq+I6ADABgDABgACQq+I6ADABgDAA0AAQobAsdtARQAAAE1AAUUAwoJABgAnBsA.',
Fu='Furiah:BAAANQADCgYICwAAAA==.Fusaa:BAABNQAECn87AAIUAAoKixQcZwAlAgAUAAoKixQcZwAlAgAAAA==.',
Ga='Gahzoo:BAAANQADCgYIFQAAAA==.Gallindo:BAAANQADCgIIAgABNQAECgcIEgABAAAAAA==.Gangry:BAAANQADCgYIDAAAAA==.Garretjax:BAAANQADCgcIGgAAAA==.Garuda:BAABNQAECn8hAAIXAAgKlBofGQCSAgAXAAgKlBofGQCSAgAAAA==.',
Ge='Gelst:BAAANQAECgEIAgAAAA==.Gelstoo:BAAANQADCgYICwAAAA==.Gerbs:BAAANQADCgYIDAAAAA==.Gerbzarrion:BAABNQAECn8WAAIZAAYKwgPtzwCvAAAZAAYKwgPtzwCvAAAAAA==.Getherdone:BAAANQADCgYIEgAAAA==.',
Gi='Gilgador:BAABNQAECn8dAAIaAAkK+g2QPgDGAQAaAAkK+g2QPgDGAQABNQAECgoKJgAHADgbAA==.',
Gr='Grape:BAAANQADCgYIBgABNQAECgoKMAAPAEsgAA==.Grassfed:BAABNQAECn8XAAIWAAYKOQh4QgC7AAAWAAYKOQh4QgC7AAAAAA==.Grimbeloc:BAAANQADCgUICwAAAA==.',
Gu='Guilehart:BAAANQAECgEIAQAAAA==.',
Ha='Hawknnib:BAAANQAECgQIDAABNQAECgUIDQABAAAAAA==.Hawknnin:BAAANQAECgUIDQAAAA==.',
He='Hexican:BAAANQADCgYIBgABNQAECgYIGQAKAF0WAA==.',
Ho='Hothala:BAAANQAECgYIDgAAAA==.',
Hu='Hunterpulled:BAABNQAECn9HAAIbAAoKYxdJWgBlAgAbAAoKYxdJWgBlAgAAAA==.',
Ic='Icnothing:BAAANQADCgcIEAAAAA==.',
In='Infectedarms:BAABNQAECn8jAAINAAcKLQaEmgDXAAANAAcKLQaEmgDXAAAAAA==.Invisabull:BAAANQADCgYIBgABNQAECgYIGQAKAF0WAA==.',
Ip='Ipwnallnoobs:BAABNQAECn8kAAISAAkKygkuTACIAQASAAkKygkuTACIAQAAAA==.',
Ir='Irisila:BAAANQAECgUIBQABNQAECgcIEgABAAAAAA==.',
Ja='Jaskilz:BAAANQADCgUIBwAAAA==.Jaypharyn:BAABNQAECn8YAAIRAAcK3RdAGACwAQARAAcK3RdAGACwAQAAAA==.Jazel:BAAANQADCgQICAAAAA==.',
Je='Jeeb:BAAANQABCgQIAgABNQAECgoKNAAMABQYAA==.Jellyapes:BAABNQAECn8ZAAIZAAYKSwrhxADBAAAZAAYKSwrhxADBAAAAAA==.',
Jo='Johalea:BAAANQADCgcIEgAAAA==.',
Ju='Juliå:BAAANQADCgYIDQAAAA==.',
['Jå']='Jåsper:BAABNQAECn8dAAIOAAcK0Rh4rwDAAQAOAAcK0Rh4rwDAAQAAAA==.',
Ka='Kabbek:BAAANQADCgMIAwAAAA==.Kahea:BAEANQAECgEIAQABNQAECggIFgAcADgSAA==.Kaileena:BAABNQAECn8mAAIdAAoKXBZnCQBSAgAdAAoKXBZnCQBSAgAAAA==.Kasia:BAABNQAECn8dAAMHAAcKsB45YQDqAQAHAAYKWB05YQDqAQAVAAMKuRU+cgC9AAAAAA==.Kassani:BAAANQADCgEJAQAAAA==.Kasuga:BAAANQADCgQIBAABNQAECgkJIAAeAJcjAA==.',
Ke='Kenneth:BAAANQADCgQIBAAAAA==.',
Ki='Kieler:BAAANQAECgUIDwAAAA==.Kierrings:BAAANQAECgYIDQAAAA==.Kikala:BAAANQADCgMIAwAAAA==.Kirarah:BAABNQAECn8lAAIbAAgK1iSJMQDYAgAbAAgK1iSJMQDYAgAAAA==.Kiylo:BAAANQADCgEIAQAAAA==.Kizune:BAAANQAECgIIAwAAAA==.',
Kl='Klauss:BAABNQAECn8rAAIMAAoK4g6KDADKAQAMAAoK4g6KDADKAQAAAA==.Klax:BAAANQADCggIIgAAAA==.',
Ko='Kordjin:BAAANQADCgIIAgAAAA==.',
Kr='Krornik:BAAANQADCgYIDgABNQAECgUICQABAAAAAA==.',
Ku='Kuyaros:BAAANQADCgUIBQAAAA==.',
['Kí']='Kíhanna:BAABNQAECn8rAAIbAAoKSh00LwDfAgAbAAoKSh00LwDfAgAAAA==.',
Le='Legenddairy:BAABNQAECn9IAAIQAAoKjhzGCwD7AQAQAAoKjhzGCwD7AQAAAA==.',
Li='Liemach:BAAANQADCgIIAgAAAA==.',
Lj='Ljósálfr:BAABNQAECn8lAAIfAAoKZSJABgAEAwAfAAoKZSJABgAEAwAAAA==.',
Lo='Lochramae:BAABNQAECn8fAAQGAAgKChYJTQDgAQAGAAgKchQJTQDgAQASAAYKNAwZQgAPAQAKAAUKJg9SewALAQAAAA==.Loupe:BAAANQADCgMIAwAAAA==.',
Lu='Lunaluvegood:BAAANQADCgUIBQAAAA==.Lunargaze:BAACNQAFFH8HAAMXAAMKmBTsBQDcAAAXAAMKmBTsBQDcAAAaAAEKlAH8IAAtAAA1AAQKfz4AAxcACgrUI9ECAK4DABcACgrUI9ECAK4DABoABAoHHXBVADgBAAAA.',
['Lâ']='Lâriel:BAABNQAECn8hAAIZAAgKdATyvgDLAAAZAAgKdATyvgDLAAAAAA==.',
Ma='Madaya:BAABNQAECn8lAAIbAAoKCBXiawA7AgAbAAoKCBXiawA7AgAAAA==.Madmartigan:BAABNQAECn8ZAAIKAAYKXRaQVQCeAQAKAAYKXRaQVQCeAQAAAA==.Mahangi:BAAANQADCggIDgAAAA==.Mamimisan:BAABNQAECn8eAAIHAAgKGxf9WgD/AQAHAAgKGxf9WgD/AQAAAA==.Matix:BAAANQABCggIHwAAAA==.',
Me='Meatpinata:BAAANQAECgUIBQAAAA==.Mechadockie:BAAANQAECgcIEgAAAA==.',
Mi='Miabel:BAAANQADCgcIBwAAAA==.Miklo:BAAANQADCgUICgAAAA==.Mirah:BAAANQAECgUICQAAAA==.Mistazee:BAAANQAECgcIDgAAAA==.Mizan:BAABNQAECn8WAAMQAAoKlRcjDQCVAgAQAAoKlRcjDQCVAgAgAAEKaxGvLwA1AAABNQAECgoKOgAIAGAfAA==.Mizeroni:BAABNQAECn86AAMIAAoKYB/JCAARAwAIAAoKYB/JCAARAwAcAAEKjATrJgEuAAAAAA==.Mizkat:BAAANQADCgcIBwABNQAECgoKOgAIAGAfAA==.Mizky:BAAANQADCggICgAAAA==.',
Mo='Mormra:BAAANQAECgIIAwAAAA==.',
Mt='Mtruckski:BAAANQABCgIIAgABNQAECgQICQABAAAAAA==.',
My='Myoo:BAAANQADCgUIBgAAAA==.',
['Më']='Mërcy:BAAANQADCgcIFAAAAA==.',
Na='Nakamuro:BAAANQADCgcIBwAAAA==.Naklus:BAAANQADCgUICQAAAA==.',
Ne='Neilia:BAABNQAECn8mAAMHAAoKOBsvHQD4AgAHAAoKOBsvHQD4AgAVAAIKfgM8JAFJAAAAAA==.Nerdroot:BAAANQADCgMIAwABNQAECgcIIQAdAJ0FAA==.Nerdvana:BAAANQADCgcIDQABNQAECgcIIQAdAJ0FAA==.Neropoison:BAAANQADCgIIAwAAAA==.Nessamos:BAAANQADCgIIAgAAAA==.',
Ni='Nikalkhano:BAAANQADCgYICQAAAA==.',
Nl='Nlani:BAAANQAECgQIDAAAAA==.',
Nu='Nuvi:BAAANQADCgUICAAAAA==.',
Oc='Octarius:BAAANQAECggIDAAAAA==.',
On='Onomirigaru:BAABNQAECn8pAAIXAAgKehjDIgA0AgAXAAgKehjDIgA0AgAAAA==.',
Op='Oproer:BAAANQADCggICAAAAA==.',
Ox='Oxygentank:BAABNQAECn8eAAMgAAoK5hQSFwCIAQAgAAcKeRkSFwCIAQAWAAYKRAxdPADUAAAAAA==.',
Pa='Parne:BAAANQADCgYIEQAAAA==.',
Pe='Pesades:BAABNQAECn8gAAMQAAoKsBxjCAD2AgAQAAoKsBxjCAD2AgARAAEKhAI8YQAhAAABNQAECgoKIAAQALAcAA==.',
Pi='Piccolo:BAAANQAECggIAgAAAA==.Pips:BAAANQADCgYIBgABNQAECgcIKAAGAIUNAA==.Pizzadatheal:BAAANQAECggICAABNQAECggIDAABAAAAAA==.',
Pl='Platura:BAABNQAECn8nAAIcAAgKghdbPQCjAQAcAAgKghdbPQCjAQAAAA==.',
Pv='Pvp:BAAANQADCgMIAwAAAA==.',
Qu='Quetzalcoatl:BAAANQAECggICQAAAA==.',
Ra='Raezune:BAAANQAECgEIAwAAAA==.Rajia:BAABNQAECn8tAAIeAAkKWwpZBQA8AQAeAAkKWwpZBQA8AQAAAA==.Ranron:BAAANQAECgQIBgAAAA==.Rassaphore:BAAANQADCggIDwAAAA==.Raínbow:BAAANQADCgcJCgABNQAECgcIFgAIABERAA==.',
Re='Reapin:BAABNQAECn8eAAISAAcKSxPxPgAcAQASAAcKSxPxPgAcAQAAAA==.Rezeldâ:BAAANQAECgEIAQAAAA==.',
Rh='Rhaegalsh:BAABNQAECn8aAAIVAAgKNw0fdwC8AQAVAAgKNw0fdwC8AQAAAA==.',
Ri='Rionach:BAABNQAECn8sAAIQAAkKAQy+HAAkAQAQAAkKAQy+HAAkAQAAAA==.Rivon:BAAANQADCggIGgAAAA==.',
Ro='Rob:BAAANQAECgEIAQAAAA==.',
Ru='Runeneya:BAAANQAECggIBwAAAA==.',
Sa='Salanozi:BAAANQADCgMIAwAAAA==.',
Sc='Schtzngigllz:BAAANQADCgQIBwABNQAECgIIAwABAAAAAA==.Scoop:BAABNQAECn8qAAMTAAoK4hsrQgCqAQATAAkK7RsrQgCqAQAPAAcKqh17FACEAQAAAA==.',
Se='Seanan:BAEBNQAECn85AAIhAAoKwiWXAwBjAwAhAAoKwiWXAwBjAwAAAA==.Seera:BAAANQADCgIIAgAAAA==.Seran:BAABNQAECn81AAIcAAoKnAYQVABJAQAcAAoKnAYQVABJAQAAAA==.Servantes:BAAANQADCgMIBAAAAA==.',
Sh='Shammwow:BAAANQAECgcIDAAAAA==.Shamoo:BAAANQAECgYIBwAAAA==.Shaudis:BAABNQAECn8oAAIUAAoKLRd3VgBTAgAUAAoKLRd3VgBTAgAAAA==.Shiftyshape:BAAANQAECgEJAQAAAA==.Shigurexx:BAABNQAECn8dAAIiAAkKpgxcMwCzAQAiAAkKpgxcMwCzAQAAAA==.Shoe:BAABNQAECn8+AAIEAAoKqBWgBQD0AQAEAAoKqBWgBQD0AQAAAA==.Shootup:BAAANQADCgcIEAAAAA==.',
Si='Siph:BAAANQAECgMIAwAAAA==.',
Sk='Skiliz:BAAANQADCgYIDAAAAA==.',
Sl='Slapurdaddy:BAAANQADCgUJCQAAAA==.',
So='Somassen:BAABNQAECn8oAAIbAAcKHAzRqgCvAQAbAAcKHAzRqgCvAQAAAA==.Sonashee:BAAANQAECgcIDgAAAA==.Sorender:BAAANQADCgYIFgAAAA==.',
St='Steelbutt:BAAANQADCggIKwAAAA==.',
Su='Supersoakêr:BAAANQAECgQIBAABNQAECgcIDgABAAAAAA==.Surii:BAAANQADCgYICwAAAA==.',
Ta='Talene:BAAANQADCgUIBgAAAA==.Tamarins:BAABNQAECn8YAAIfAAcKABETFwDeAAAfAAcKABETFwDeAAAAAA==.Tappy:BAABNQAECn83AAITAAoK3RO2RgBTAgATAAoK3RO2RgBTAgAAAA==.',
Te='Terkarakk:BAABNQAECn8bAAIQAAgKGSSPBgAmAwAQAAgKGSSPBgAmAwABNQAFFAQIBwAIAMMdAA==.',
Th='Thirryn:BAABNQAECn8gAAIjAAgKZQefEQAbAQAjAAgKZQefEQAbAQAAAA==.Thorybos:BAABNQAECn8bAAIZAAoKchowXgDDAgAZAAoKchowXgDDAgAAAA==.',
Ti='Tippy:BAAANQAECgQICQAAAA==.',
To='Toom:BAABNQAECn8eAAIbAAYKFAfXzgBjAQAbAAYKFAfXzgBjAQAAAA==.',
Tr='Traylinna:BAAANQADCgEIAQAAAA==.Trophyhubby:BAABNQAECn8iAAMTAAcKvw61hACJAQATAAcKvw61hACJAQAPAAQKMgTVWQChAAAAAA==.',
Tu='Tuknark:BAAANQADCgcIGAAAAA==.',
Ty='Tyeren:BAABNQAECn8UAAMGAAcKNhFoagBpAQAGAAcKew5oagBpAQAKAAQKLBYDhgDlAAAAAA==.Tyeriel:BAACNQAFFH8RAAMSAAUKXwyOCQDZAAASAAQKxwuOCQDZAAAGAAMKMwppFADDAAA1AAQKfzQABBIACgorHYoaAPoBABIACgpgHIoaAPoBAAYABQqgGc1zAEgBAAoAAQrUEA1/ADcAAAAA.Typpy:BAAANQAECggIDwAAAA==.',
Tz='Tzuriel:BAEBNQAECn82AAMIAAoKiSFsBQCtAgAIAAkKsiNsBQCtAgAOAAcKkQ5d0QB5AQAAAA==.',
Va='Valat:BAAANQADCgYIBgAAAA==.Valei:BAAANQADCgQIBAAAAA==.Valkyriewing:BAABNQAECn8eAAIcAAYK7g3bogA/AQAcAAYK7g3bogA/AQAAAA==.Valvet:BAAANQADCggIMgAAAA==.',
Ve='Velaste:BAAANQADCgQIBAAAAA==.',
Vi='Vikril:BAABNQAECn8pAAQKAAkKSBYoJQBtAQASAAgKBAxzLgBvAQAKAAgKohcoJQBtAQAGAAYKPg09fAArAQAAAA==.Vincenzo:BAAANQAECgMIAwAAAA==.',
Vo='Volkanoth:BAAANQAECgUIBwAAAA==.',
Vu='Vue:BAAANQADCgYIBgABNQADCggIIgABAAAAAA==.',
Vy='Vylus:BAABNQAECn8hAAIaAAgKQgkfOADzAAAaAAgKQgkfOADzAAAAAA==.',
['Vá']='Vásh:BAABNQAECn8tAAMNAAkKvAwRWwBxAQANAAkKtQsRWwBxAQAYAAYKHwwvFgA5AQAAAA==.',
We='Webjibaro:BAAANQADCgUICgAAAA==.Weeblewobble:BAAANQADCgcIGAAAAA==.Weili:BAABNQAECn8aAAIWAAcK7BE+LgAfAQAWAAcK7BE+LgAfAQAAAA==.',
Wh='Whiney:BAAANQAECgMIAwABNQAECgYICgABAAAAAA==.',
Wi='Wikidfiend:BAAANQADCgQIBQAAAA==.William:BAABNQAECn8gAAIbAAgKixrSTwB/AgAbAAgKixrSTwB/AgAAAA==.Willious:BAAANQABCgIIAgAAAA==.Windee:BAAANQADCgYICgAAAA==.Wishi:BAAANQADCgQIBAAAAA==.',
Wr='Wrast:BAABNQAECn8UAAMbAAcKzQwauQCRAQAbAAcKzQwauQCRAQAiAAUKKwKYYgCfAAAAAA==.Wravyn:BAABNQAECn8gAAIbAAcKxgVWxwBzAQAbAAcKxgVWxwBzAQAAAA==.',
Xa='Xalted:BAAANQADCgUICQAAAA==.Xandria:BAAANQADCgUIBQAAAA==.Xaylios:BAAANQAECgcIEgAAAA==.',
Xy='Xyara:BAABNQAECn82AAQeAAoKXht/IwBWAQAUAAgK5RU4eAD6AQAeAAYKWxd/IwBWAQAkAAYKjhkqCgD3AAAAAA==.',
Yo='Yoghurt:BAABNQAECn8eAAMYAAkKYRr7CABOAgAYAAkKYRr7CABOAgANAAEKAACBXwEnAAAAAA==.',
Yu='Yunlan:BAAANQAECgUICQAAAA==.',
Za='Zalidus:BAABNQAECn8UAAIhAAkKHwtmFgAlAQAhAAkKHwtmFgAlAQAAAA==.Zanthor:BAAANQAECgUIDgABNQAFFAIIBQALALURAA==.',
Ze='Zehnia:BAAANQABCgcIDQAAAA==.Zephira:BAAANQADCgUIBgAAAA==.Zerhistran:BAABNQAECn8UAAMSAAkK9BCfIwCxAQASAAkK9BCfIwCxAQAGAAIK2QaGZgBAAAAAAA==.',
Zi='Zibzab:BAABNQAECn8cAAIWAAYKHwnybQATAQAWAAYKHwnybQATAQAAAA==.',
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
