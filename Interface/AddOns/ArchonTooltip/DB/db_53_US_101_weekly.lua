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

local lookup = {'Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Evoker-Devastation','Evoker-Preservation','DeathKnight-Unholy','Druid-Guardian','Shaman-Restoration','Paladin-Protection','Priest-Discipline','DeathKnight-Blood','Monk-Windwalker','Monk-Mistweaver','Warrior-Arms','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Shadow','Druid-Restoration','DeathKnight-Frost','Priest-Holy','Warlock-Demonology','Shaman-Elemental','Druid-Balance','Warrior-Fury','Hunter-Survival','Mage-Arcane','DemonHunter-Havoc','Shaman-Enhancement','Hunter-BeastMastery','Paladin-Holy','Warlock-Destruction','Warrior-Protection','Druid-Feral','Hunter-Marksmanship','Evoker-Augmentation','Warlock-Affliction',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aastrid:BAAANQADCggIGgAAAA==.',
Ad='Adorabúll:BAAANQAECgEIAgAAAA==.',
Ae='Aevriia:BAAANQADCgIIAgAAAA==.',
Ah='Ahrus:BAAANQADCgUIBQABNQAECgIIBQABAAAAAA==.',
Ak='Akåshå:BAAANQAECgIIAwAAAA==.Akélla:BAAANQAECggICAAAAA==.',
Al='Aldric:BAAANQAECgQIBAAAAA==.Alien:BAACNQAFFH8FAAICAAMKKRNlDwDzAAACAAMKKRNlDwDzAAA1AAQKfyIAAwIACQpCHbgKAAECAAMACQoLFcYpACMCAAIABwqaHLgKAAECAAAA.Althenzdormu:BAABNQAECn8dAAMEAAcKEQVhFADAAAAEAAcKEQVhFADAAAAFAAIKAQH0TwAuAAAAAA==.Altruist:BAAANQAECgUIDgABNQAECgkJMAAGALUTAA==.',
Am='Amaethon:BAABNQAECn8WAAIHAAcKdgcaOQDiAAAHAAcKdgcaOQDiAAAAAA==.',
An='Ancaera:BAAANQADCggIDQAAAA==.Andalikus:BAABNQAECn8rAAIIAAkKiCPFFgAbAwAIAAkKiCPFFgAbAwAAAA==.Andorra:BAAANQADCgYICwAAAA==.Andybocelli:BAEANQAECggICAABNQAECgoKOQAJAMUiAA==.Anrien:BAABNQAECn8pAAIKAAkK0yGZAQDGAgAKAAkK0yGZAQDGAgAAAA==.',
Ar='Ari:BAAANQADCgcIBwAAAA==.Around:BAAANQAECgQIBgAAAA==.',
As='Asharal:BAAANQADCgYIBgAAAA==.',
At='Atriste:BAABNQAECn8wAAMGAAkKtRPQIQCfAQAGAAkKtRPQIQCfAQALAAUKSgf1jwDFAAAAAA==.',
Au='Aunyx:BAABNQAECn8vAAICAAkKIRD1DwCmAQACAAkKIRD1DwCmAQAAAA==.',
Az='Azenoth:BAAANQADCggIGgAAAA==.',
Ba='Babajaga:BAAANQADCgIJAgAAAA==.Baloth:BAAANQADCgYIDAABNQAECgkJLgAMALwRAA==.',
Be='Beej:BAABNQAECn86AAINAAoKFBgiDwCPAgANAAoKFBgiDwCPAgAAAA==.',
Bi='Biggooch:BAABNQAECn8gAAIOAAgKphbOgQAWAgAOAAgKphbOgQAWAgAAAA==.Bigocritties:BAAANQADCggIFQAAAA==.Bison:BAAANQADCgcIBwAAAA==.',
Bl='Blackrose:BAAANQADCggIGwABNQAECgoKLAAOADAZAA==.Blightbeard:BAABNQAECn8XAAIGAAkKMgoGPQDzAAAGAAkKMgoGPQDzAAAAAA==.Blîss:BAABNQAECn8YAAIPAAYK4gKdHAGJAAAPAAYK4gKdHAGJAAAAAA==.',
Bo='Bowjobs:BAAANQADCgYIBgABNQAECgcIIAALAJgUAA==.',
Br='Brayliel:BAAANQADCgQIBQAAAA==.Brut:BAABNQAECn8YAAMQAAcKThUiEAAQAQAQAAcKkxEiEAAQAQARAAUKQRYuNADFAAABNQAECgoKMgASAP0gAA==.',
Bu='Bullsi:BAAANQADCggIEAABNQAECgoKTgAHAI4cAA==.Bumpy:BAAANQADCggICAAAAA==.Bustus:BAABNQAECn8vAAITAAkKFAxYKgBRAQATAAkKFAxYKgBRAQAAAA==.',
Ca='Calinia:BAAANQABCgYICQAAAA==.Camma:BAAANQADCgUIBAAAAA==.Carole:BAABNQAECn9PAAQGAAoKZx5VKACYAgAGAAgKlyBVKACYAgAUAAoKdBezHQApAgALAAcKWxJNagBKAQAAAA==.Caroll:BAABNQAECn8yAAQSAAoK/SDoDAAcAwASAAkKESLoDAAcAwAVAAYK7RFiuADvAAAKAAMKQgvMGgCTAAAAAA==.Carsomavra:BAAANQADCgYIFwAAAA==.Cathercy:BAABNQAECn8lAAIPAAcKiA146ABKAQAPAAcKiA146ABKAQAAAA==.',
Ch='Chenzhen:BAAANQAECgcIEgAAAA==.Cherub:BAAANQAECggIAQAAAA==.Chilly:BAAANQAECgMIAgABNQAFFAUICwANAF8KAA==.Chrollo:BAAANQAECgYIDwAAAA==.Chunt:BAAANQADCgYIDQAAAA==.',
Cl='Cloggy:BAAANQADCgYIBgABNQAFFAcIDgAWAEYXAA==.',
Co='Connery:BAAANQADCggIDgAAAA==.Corannis:BAABNQAECn8sAAIXAAkKvRXYOwCqAQAXAAkKvRXYOwCqAQAAAA==.Corax:BAAANQADCgQIBgAAAA==.',
Cr='Cranberries:BAAANQAECgMIAwABNQAECgoKOQAIAOIMAA==.Cravedog:BAABNQAECn83AAMHAAgKLiOEBgAnAwAHAAgKLiOEBgAnAwAYAAMKZAsnkwCLAAAAAA==.Creepi:BAABNQAECn8lAAMKAAcKJhwMBADRAQAKAAYKXx8MBADRAQASAAcKThJ0IwAtAQAAAA==.Crockett:BAAANQADCgUIBwABNQAECgIIAwABAAAAAA==.Cromgabhar:BAAANQADCggICAABNQAECgcIIAALAJgUAA==.',
Cu='Cuauhtzin:BAAANQAECggIAQAAAA==.Cupcáke:BAABNQAECn8hAAIPAAoKdBhXYwDPAQAPAAoKdBhXYwDPAQAAAA==.Curthodnes:BAAANQADCgIJAgAAAA==.',
Da='Dalmas:BAAANQADCgUIDQAAAA==.Dalsho:BAAANQAECgYIDAAAAA==.Damaso:BAABNQAECn8cAAISAAoKLw3vFgC1AQASAAoKLw3vFgC1AQAAAA==.Damik:BAAANQAECgEIAQAAAA==.Darku:BAABNQAECn8tAAISAAkK3x+ODwAsAgASAAkK3x+ODwAsAgAAAA==.Darlàrk:BAAANQAECgcIEgAAAA==.Dawnmane:BAACNQAFFH8IAAIJAAUKwx0YBAD2AAAJAAUKwx0YBAD2AAA1AAQKfyUAAgkACgoiJHICAEUDAAkACgoiJHICAEUDAAAA.',
De='Deadlie:BAAANQAECgEIAQAAAA==.Deathsquaad:BAAANQAFFAEIAQAAAA==.Delderach:BAABNQAECn8lAAIJAAcKBBamJgCpAQAJAAcKBBamJgCpAQAAAA==.Dellila:BAAANQABCgcIBwAAAA==.Denin:BAABNQAECn8mAAICAAkKBRMqDwCyAQACAAkKBRMqDwCyAQAAAA==.Derphardigan:BAAANQADCgYIBgABNQAECgcIIAALAJgUAA==.',
Di='Diego:BAAANQADCgMIBAAAAA==.Dirkette:BAABNQAECn8oAAIKAAkKsgn2DABnAQAKAAkKsgn2DABnAQAAAA==.Dirksavoid:BAAANQAECgEIBAABNQAECgkJKAAKALIJAA==.',
Dk='Dkxsmurfx:BAAANQAECgEIAQAAAA==.',
Do='Dokai:BAABNQAECn8uAAIMAAkKvBFDGwCVAQAMAAkKvBFDGwCVAQAAAA==.',
Dr='Dracmiz:BAAANQAECgcICgABNQAECgoKPgAJAH8fAA==.Drathan:BAAANQADCgMJAwAAAA==.',
Dt='Dthnght:BAAANQADCgQIBwAAAA==.',
Du='Duskweaver:BAAANQADCgIIAgAAAA==.',
Ea='Earthboy:BAAANQADCgIIAgABNQAECgoKMgASAP0gAA==.',
Ed='Edamina:BAAANQABCgYIDwAAAA==.',
El='Elaenei:BAAANQADCgcIFgAAAA==.Eliance:BAABNQAECn8jAAICAAcKjQQ/MQC4AAACAAcKjQQ/MQC4AAAAAA==.Elienn:BAAANQADCgcIGAAAAA==.Elinore:BAAANQADCgQIBAAAAA==.Elmer:BAAANQAECgEIAQAAAA==.',
En='Enpain:BAAANQAECgIIAgAAAA==.',
Er='Errius:BAABNQAECn8nAAILAAcKZAtAbABDAQALAAcKZAtAbABDAQAAAA==.',
Es='Esh:BAAANQADCgQIBAABNQAECgoKHQATAHocAA==.',
Eu='Eunja:BAEANQAECgIIAwAAAQ==.',
Ey='Eyowynne:BAAANQADCgIIAgAAAA==.',
Fa='Facetious:BAAANQADCgIIAgAAAA==.Fatherbetter:BAAANQAECgUIAwABNQAFFAQICwARAL0YAA==.',
Fi='Filharmonic:BAAANQADCgcIFwAAAA==.Fizzbin:BAAANQADCgQIBwAAAA==.',
Fo='Foid:BAACNQAFFH8JAAMZAAMKnBuqAQARAQAZAAMKnBuqAQARAQAOAAEKWA1BPwBBAAA1AAQKfxoAAxkACQq+I6ADABgDABkACQq+I6ADABgDAA4AAQobAsdtARQAAAE1AAUUAwoJABkAnBsA.',
Fu='Furiah:BAAANQADCgYICwAAAA==.Fusaa:BAABNQAECn9BAAIWAAoKixQcZwAlAgAWAAoKixQcZwAlAgAAAA==.',
Ga='Gahzoo:BAAANQADCgYIGAAAAA==.Gallindo:BAAANQADCgIIAgABNQAECgkJFgAaAMoSAA==.Gangry:BAAANQAECgQIBAAAAA==.Garretjax:BAAANQADCggIHAAAAA==.Garuda:BAABNQAECn8lAAIRAAkKzxcfGQCSAgARAAkKzxcfGQCSAgAAAA==.',
Ge='Gelst:BAAANQAECgQIBgAAAA==.Gelstoo:BAAANQADCgYICwAAAA==.Gerbs:BAAANQADCgYIDAAAAA==.Gerbzarrion:BAABNQAECn8dAAIbAAcK7wPazwDfAAAbAAcK7wPazwDfAAAAAA==.Getherdone:BAAANQADCgYIEgAAAA==.',
Gi='Gilgador:BAABNQAECn8nAAIcAAkK9w4OLwBeAQAcAAkK9w4OLwBeAQABNQAECgoKLQAIAF0bAA==.',
Gr='Grape:BAAANQADCgYIBgABNQAECgoKMgASAP0gAA==.Grassfed:BAABNQAECn8eAAIYAAcKcgk7QQDwAAAYAAcKcgk7QQDwAAAAAA==.Grimbeloc:BAAANQAECgMIAwAAAA==.',
Gu='Guilehart:BAAANQABCgIIAQAAAA==.',
Ha='Hawknnib:BAAANQAECgQICQABNQAECgYIEwABAAAAAA==.Hawknnin:BAAANQAECgYIEwAAAA==.',
He='Hechicera:BAAANQAECggIAwAAAA==.Hexican:BAAANQADCgYIBgABNQAECgcIIAALAJgUAA==.',
Ho='Hothala:BAABNQAECn8VAAMdAAkK5w8DGQBBAQAdAAYK1Q4DGQBBAQAXAAQKlhJotABuAAAAAA==.',
Hu='Hunterpulled:BAABNQAECn9hAAIeAAoKyRq7IQCQAgAeAAoKyRq7IQCQAgAAAA==.Huroona:BAAANQADCgUIBQAAAA==.',
Ic='Icnothing:BAAANQADCgcIEAAAAA==.',
In='Infectedarms:BAABNQAECn8qAAIOAAgKdwa5nwAHAQAOAAgKdwa5nwAHAQAAAA==.Invisabull:BAAANQADCgYIBgABNQAECgcIIAALAJgUAA==.',
Ip='Ipwnallnoobs:BAABNQAECn8qAAIUAAoKXQouTACIAQAUAAoKXQouTACIAQAAAA==.',
Ir='Irisila:BAAANQAECgUIBQABNQAECgkJFgAaAMoSAA==.',
Iz='Iztaccihualt:BAAANQAECggIAgAAAA==.',
Ja='Jaskilz:BAAANQADCgUIBwAAAA==.Jaypharyn:BAABNQAECn8YAAITAAcK3RfNIACkAQATAAcK3RfNIACkAQAAAA==.Jazel:BAAANQADCgQICAAAAA==.',
Je='Jeeb:BAAANQABCgIIAgABNQAECgoKOgANABQYAA==.Jellyapes:BAABNQAECn8dAAIbAAYKTwtp1wDRAAAbAAYKTwtp1wDRAAAAAA==.',
Jo='Johalea:BAAANQADCgcIEgAAAA==.',
Ju='Juliå:BAAANQADCgYIDQAAAA==.',
['Jå']='Jåsper:BAABNQAECn8dAAIPAAcK0Rh4rwDAAQAPAAcK0Rh4rwDAAQAAAA==.',
Ka='Kabbek:BAAANQADCgMIAwAAAA==.Kahea:BAEANQADCgYIBgABNQAECggIFgAfADgSAA==.Kaileena:BAABNQAECn8mAAIQAAoKXBZnCQBSAgAQAAoKXBZnCQBSAgAAAA==.Kasia:BAABNQAECn8dAAMIAAcKsB45YQDqAQAIAAYKWB05YQDqAQAXAAMKuRWjiwC8AAAAAA==.Kassani:BAAANQADCgEJAQAAAA==.Kasuga:BAAANQADCgQIBAABNQAECgkJIAAgAJcjAA==.',
Ke='Kenneth:BAAANQADCgQIBAAAAA==.',
Ki='Kieler:BAABNQAECn8WAAIYAAgKOQRdeADpAAAYAAgKOQRdeADpAAAAAA==.Kierrings:BAAANQAECgcIDgAAAA==.Kikala:BAAANQADCgMIAwAAAA==.Kirarah:BAABNQAECn8oAAIeAAkKcySJMQDYAgAeAAkKcySJMQDYAgAAAA==.Kiylo:BAAANQADCgEIAQAAAA==.Kizune:BAAANQAECgIIAgAAAA==.',
Kl='Klauss:BAABNQAECn8xAAINAAoKFQ8aEQC5AQANAAoKFQ8aEQC5AQAAAA==.Klax:BAAANQADCggIIgAAAA==.',
Ko='Kordjin:BAAANQADCgIIAgAAAA==.',
Kr='Krornik:BAAANQADCgYIDgABNQAECgYICAABAAAAAA==.',
Ku='Kuyaros:BAAANQADCgUIBQAAAA==.',
['Kí']='Kíhanna:BAABNQAECn8yAAIeAAoK8h40LwDfAgAeAAoK8h40LwDfAgAAAA==.',
La='Lanen:BAAANQADCgUIBQAAAA==.',
Le='Legenddairy:BAABNQAECn9OAAIHAAoKjhzrDQCGAgAHAAoKjhzrDQCGAgAAAA==.',
Li='Liemach:BAAANQADCgIIAgAAAA==.',
Lj='Ljósálfr:BAABNQAECn8vAAIhAAoK+yJgAgAUAwAhAAoK+yJgAgAUAwAAAA==.',
Lo='Lochramae:BAABNQAECn8jAAQGAAkKWxYJTQDgAQAGAAgKchQJTQDgAQAUAAYKNAyLVAAHAQALAAgK7RG4RgD5AAAAAA==.Loupe:BAAANQADCgMIAwAAAA==.',
Lu='Lunaluvegood:BAAANQADCgUIBQAAAA==.Lunargaze:BAACNQAFFH8LAAMRAAQKvRhZBgDqAAARAAQKvRhZBgDqAAAcAAEKlAH8IAAtAAA1AAQKf0IAAxEACgrrJNECAK4DABEACgrrJNECAK4DABwABAoHHXBVADgBAAAA.',
['Lâ']='Lâriel:BAABNQAECn8hAAIbAAgKdATH3gDEAAAbAAgKdATH3gDEAAAAAA==.',
Ma='Madaya:BAABNQAECn8vAAIeAAoKuxjrLABgAgAeAAoKuxjrLABgAgAAAA==.Madmartigan:BAABNQAECn8gAAILAAcKmBSQVQCeAQALAAcKmBSQVQCeAQAAAA==.Mahangi:BAAANQADCggIDgAAAA==.Mamimisan:BAABNQAECn8gAAIIAAgKhxf9WgD/AQAIAAgKhxf9WgD/AQAAAA==.Matix:BAAANQABCggIHwAAAA==.',
Me='Meatpinata:BAAANQAECgUIBQAAAA==.Mechadockie:BAAANQAECgcIEwAAAA==.',
Mi='Miabel:BAAANQADCgcIBwAAAA==.Micttlan:BAAANQAECggICAAAAA==.Miklo:BAAANQADCgUICgAAAA==.Mirah:BAAANQAECgYICgAAAA==.Mistazee:BAAANQAECgcIDAAAAA==.Mizan:BAABNQAECn8aAAMHAAoKlRcjDQCVAgAHAAoKlRcjDQCVAgAiAAQKBhQXKgB4AAABNQAECgoKPgAJAH8fAA==.Mizeroni:BAABNQAECn8+AAMJAAoKfx/JCAARAwAJAAoKfx/JCAARAwAfAAEKjATrJgEuAAAAAA==.Mizkat:BAAANQADCgcIBwABNQAECgoKPgAJAH8fAA==.Mizky:BAAANQADCggICgAAAA==.',
Mo='Mormra:BAAANQAECgIIBQAAAA==.',
Mt='Mtruckski:BAAANQABCgIIAgABNQAECgQIBwABAAAAAA==.',
My='Myoo:BAAANQADCgUIBgAAAA==.',
['Më']='Mërcy:BAAANQADCgcIFAAAAA==.',
Na='Nakamuro:BAAANQADCgcIBwAAAA==.Naklus:BAAANQADCgUICQAAAA==.',
Ne='Neilia:BAABNQAECn8tAAMIAAoKXRsFFADsAgAIAAoKXRsFFADsAgAXAAIKfgM8JAFJAAAAAA==.Nerdroot:BAAANQADCgMIAwABNQAECgcIIQAQAJ0FAA==.Nerdvana:BAAANQADCgcIDQABNQAECgcIIQAQAJ0FAA==.Neropoison:BAAANQADCgIIAwAAAA==.Nessamos:BAAANQADCgIIAgAAAA==.',
Ni='Nikalkhano:BAAANQADCgYICQAAAA==.',
Nl='Nlani:BAAANQAECgQIDAAAAA==.',
Nu='Nuvi:BAAANQADCgUICAAAAA==.',
Oc='Octarius:BAAANQAECggICwAAAA==.',
On='Onomirigaru:BAABNQAECn8uAAIRAAgKehjDIgA0AgARAAgKehjDIgA0AgAAAA==.',
Op='Oproer:BAAANQADCggICAAAAA==.',
Ox='Oxygentank:BAABNQAECn8kAAMiAAoK/hUSFwCIAQAiAAcKrhkSFwCIAQAYAAYKMQ6pRADgAAAAAA==.',
Pa='Padremayu:BAAANQAECgEIAQAAAA==.Parne:BAAANQADCgYIEQAAAA==.',
Pe='Pesades:BAABNQAECn8jAAMHAAoKlR1jCAD2AgAHAAoKlR1jCAD2AgATAAEKhAJZcwAdAAABNQAECgoKIwAHAJUdAA==.',
Pi='Piccolo:BAAANQAECggIAwAAAA==.Pips:BAAANQADCgYIBgABNQAECgcIKAAGAIUNAA==.Pizzadatheal:BAAANQAECggICAABNQAECggICwABAAAAAA==.',
Pl='Platura:BAABNQAECn8tAAIfAAgKRBkUPwDmAQAfAAgKRBkUPwDmAQAAAA==.',
Pv='Pvp:BAAANQADCgMIAwAAAA==.',
Qu='Quetzalcoatl:BAAANQAECggICQAAAA==.',
Ra='Raezune:BAAANQABCgYICwAAAA==.Rajia:BAABNQAECn8wAAIgAAkKKQubBgBCAQAgAAkKKQubBgBCAQAAAA==.Ranron:BAAANQAECgQIBAAAAA==.Rassaphore:BAAANQADCggIDwAAAA==.Raínbow:BAAANQADCgcJCgABNQAECgcIGwAJABERAA==.',
Re='Reapin:BAABNQAECn8eAAIUAAcKSxPtUgBkAQAUAAcKSxPtUgBkAQAAAA==.Rezeldâ:BAAANQAECgQIBQAAAA==.',
Rh='Rhaegalsh:BAABNQAECn8aAAIXAAgKNw0fdwC8AQAXAAgKNw0fdwC8AQAAAA==.',
Ri='Rilorren:BAAANQADCgUIBQABNQAECgoKMgASAP0gAA==.Rionach:BAABNQAECn8vAAIHAAkKQw11IwAvAQAHAAkKQw11IwAvAQAAAA==.Rivon:BAAANQADCggIGgAAAA==.',
Ru='Runeneya:BAAANQAECggIBwAAAA==.',
Sa='Salanozi:BAAANQADCgMIAwAAAA==.',
Sc='Schtzngigllz:BAAANQADCgQIBwABNQAECgIIBQABAAAAAA==.Scoop:BAABNQAECn8tAAMVAAoKlBxwSADdAQAVAAkKtBxwSADdAQASAAcKqh22GwB6AQAAAA==.',
Se='Seanan:BAEBNQAECn8/AAIdAAoKwiWXAwBjAwAdAAoKwiWXAwBjAwAAAA==.Seera:BAAANQADCgIIAgAAAA==.Seran:BAABNQAECn8+AAIfAAoK6gaefACjAQAfAAoK6gaefACjAQAAAA==.Servantes:BAAANQADCgMIBAAAAA==.',
Sh='Shamminout:BAAANQADCgMIAwAAAA==.Shammwow:BAAANQAECgcIEwAAAA==.Shamoo:BAAANQAECgYIBgAAAA==.Shannon:BAAANQADCgIIAgAAAA==.Shaudis:BAABNQAECn8oAAIWAAoKLRd3VgBTAgAWAAoKLRd3VgBTAgAAAA==.Shefali:BAAANQAECgQIBAAAAA==.Shiftyshape:BAAANQAECgEJAQAAAA==.Shigurexx:BAABNQAECn8mAAIjAAoKIg5jFQC0AQAjAAoKIg5jFQC0AQAAAA==.Shoe:BAABNQAECn9IAAIEAAoKshcFBgAkAgAEAAoKshcFBgAkAgAAAA==.Shootup:BAAANQADCgcIEAAAAA==.',
Si='Siph:BAAANQAECgMIBAAAAA==.',
Sk='Skiliz:BAAANQADCgYIDAAAAA==.',
Sl='Slapurdaddy:BAAANQADCgUJCQAAAA==.',
So='Somassen:BAABNQAECn8oAAIeAAcKHAzRqgCvAQAeAAcKHAzRqgCvAQAAAA==.Sonashee:BAAANQAECgcIDQAAAA==.Sorender:BAAANQADCgYIFgAAAA==.',
St='Steelbutt:BAAANQADCggIMgAAAA==.',
Su='Supersoakêr:BAAANQAECgQIBAABNQAECgcIDQABAAAAAA==.Surii:BAAANQADCgYICwAAAA==.',
Ta='Talene:BAAANQADCgUIBgAAAA==.Tamarins:BAABNQAECn8YAAIhAAcKABG6HQDYAAAhAAcKABG6HQDYAAAAAA==.Tappy:BAABNQAECn85AAIVAAoK3RO2RgBTAgAVAAoK3RO2RgBTAgAAAA==.',
Te='Terkarakk:BAABNQAECn8bAAIHAAgKGSSPBgAmAwAHAAgKGSSPBgAmAwABNQAFFAUICAAJAMMdAA==.',
Th='Thirryn:BAABNQAECn8hAAIkAAkKwgafEQAbAQAkAAkKwgafEQAbAQAAAA==.Thorybos:BAABNQAECn8fAAIbAAoK1RwwXgDDAgAbAAoK1RwwXgDDAgAAAA==.',
Ti='Tippy:BAAANQAECgQIBwAAAA==.',
To='Toom:BAABNQAECn8lAAIeAAcK+QZ6rgAQAQAeAAcK+QZ6rgAQAQAAAA==.',
Tr='Traylinna:BAAANQADCgEIAQAAAA==.Trophyhubby:BAABNQAECn8iAAMVAAcKvw61hACJAQAVAAcKvw61hACJAQASAAQKMgTVWQChAAAAAA==.',
Tu='Tuknark:BAAANQADCgcIGAAAAA==.',
Ty='Tyeren:BAABNQAECn8UAAMGAAcKNhFoagBpAQAGAAcKew5oagBpAQALAAQKLBYDhgDlAAAAAA==.Tyeriel:BAACNQAFFH8SAAMUAAYKaAxuBwAiAQAUAAUK7gtuBwAiAQAGAAMKMwppFADDAAA1AAQKfzUABBQACgorHYQnAFsCABQACgpgHIQnAFsCAAYABQqgGc1zAEgBAAsAAQrUEDKQADcAAAAA.Typpy:BAABNQAECn8XAAMkAAoKBAieCgAkAQAkAAkKOQeeCgAkAQAFAAEK6AJrOAAiAAAAAA==.',
Tz='Tzuriel:BAEBNQAECn85AAMJAAoKxSIDBwC7AgAJAAkKGiUDBwC7AgAPAAcKkQ5d0QB5AQAAAA==.',
Va='Valat:BAAANQADCgYIBgAAAA==.Valei:BAAANQADCgQIBAAAAA==.Valkyriewing:BAABNQAECn8lAAIfAAcKHBNrVACPAQAfAAcKHBNrVACPAQAAAA==.Valvet:BAAANQADCggINQAAAA==.',
Ve='Velaste:BAAANQADCgQIBAAAAA==.',
Vi='Vikril:BAABNQAECn8tAAQLAAkK5hieIgC5AQALAAkKPxieIgC5AQAUAAgKBAyrPgBjAQAGAAYKPg09fAArAQAAAA==.Vincenzo:BAAANQAECgQIBAAAAA==.',
Vo='Volkanoth:BAAANQAECgUIBwAAAA==.',
Vu='Vue:BAAANQADCgYIBgABNQADCggIIgABAAAAAA==.',
Vy='Vylus:BAABNQAECn8pAAIcAAkKaAgNPQAKAQAcAAkKaAgNPQAKAQAAAA==.',
['Vá']='Vásh:BAABNQAECn8wAAMZAAkK7QwvFgA5AQAOAAkK5gsOcQB1AQAZAAYKHwwvFgA5AQAAAA==.',
We='Webjibaro:BAAANQADCgUICgAAAA==.Weeblewobble:BAAANQADCgcIGAAAAA==.Weili:BAABNQAECn8aAAIYAAcK7BGKOgASAQAYAAcK7BGKOgASAQAAAA==.',
Wh='Whiney:BAAANQAECgMIAgABNQAECgYICQABAAAAAA==.',
Wi='Wikidfiend:BAAANQADCgQIBQAAAA==.William:BAABNQAECn8kAAIeAAkKQRtXRQANAgAeAAkKQRtXRQANAgAAAA==.Willious:BAAANQABCgIIAgAAAA==.Windee:BAAANQADCgYICgAAAA==.Wishi:BAAANQADCgQIBAAAAA==.',
Wr='Wrast:BAABNQAECn8VAAMeAAgKrwwauQCRAQAeAAgKrwwauQCRAQAjAAUKKwKYYgCfAAAAAA==.Wravyn:BAABNQAECn8gAAIeAAcKxgVWxwBzAQAeAAcKxgVWxwBzAQAAAA==.',
Xa='Xalted:BAAANQADCgUICQAAAA==.Xandria:BAAANQADCgUIBQAAAA==.Xaylios:BAAANQAECggIEwAAAA==.',
Xy='Xyara:BAABNQAECn89AAQlAAoKix7wBgC6AQAWAAgK5RU4eAD6AQAlAAgKEh7wBgC6AQAgAAYKWxd/IwBWAQAAAA==.',
Yo='Yoghurt:BAABNQAECn8nAAMZAAoKpBlnBQBLAgAZAAoKpBlnBQBLAgAOAAEKAACBXwEnAAAAAA==.',
Yu='Yunlan:BAAANQAECgYICAAAAA==.',
Za='Zalidus:BAABNQAECn8WAAIdAAkK9QtjGgAtAQAdAAkK9QtjGgAtAQAAAA==.Zanthor:BAAANQAECgUIDgABNQAFFAMICAAMAJsNAA==.',
Ze='Zehnia:BAAANQABCgcIDgAAAA==.Zephira:BAAANQADCgUIBgAAAA==.Zerhistran:BAABNQAECn8eAAMGAAoKqBXJIQCfAQAUAAkK9BCYMQClAQAGAAgKqhTJIQCfAQAAAA==.',
Zi='Zibzab:BAABNQAECn8jAAIYAAcKDQjiRwDRAAAYAAcKDQjiRwDRAAAAAA==.',
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
