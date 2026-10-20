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

local lookup = {'Rogue-Assassination','Evoker-Devastation','Evoker-Preservation','DeathKnight-Unholy','Shaman-Restoration','Priest-Discipline','DeathKnight-Blood','Monk-Windwalker','Monk-Mistweaver','Warrior-Arms','Priest-Shadow','Druid-Guardian','Druid-Restoration','DeathKnight-Frost','Priest-Holy','Paladin-Retribution','Warlock-Demonology','Shaman-Elemental','Druid-Balance','Unknown-Unknown','Paladin-Protection','DemonHunter-Devourer','Warrior-Fury','DemonHunter-Havoc','Hunter-BeastMastery','Mage-Arcane','DemonHunter-Vengeance','Warlock-Destruction','Warrior-Protection','Paladin-Holy','Druid-Feral','Shaman-Enhancement','Hunter-Marksmanship','Evoker-Augmentation','Warlock-Affliction',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aastrid:BAAANQADCggIGgAAAA==.',
Ad='Adorabúll:BAAANQAECgEIAQAAAA==.',
Ae='Aevriia:BAAANQADCgIIAgAAAA==.',
Ak='Akåshå:BAAANQADCggICAAAAA==.Akélla:BAAANQAECggICAAAAA==.',
Al='Aldric:BAAANQAECgQIBQAAAA==.Alien:BAABNQAFFH8FAAIBAAMKKRNlDwDzAAABAAMKKRNlDwDzAAAAAA==.Althenzdormu:BAABNQAECn8XAAMCAAcKCQVPCQDVAAACAAcKCQVPCQDVAAADAAIKAQH0TwAuAAAAAA==.Altruist:BAAANQAECgUIEAABNQAECggIJQAEAPESAA==.',
Am='Amaethon:BAAANQAECgUIEQAAAA==.',
An='Ancaera:BAAANQAECgEIAQAAAA==.Andalikus:BAABNQAECn8kAAIFAAgKGyPFFgAbAwAFAAgKGyPFFgAbAwAAAA==.Andorra:BAAANQADCgYICwAAAA==.Andybocelli:BAAANQADCgYIBgAAAA==.Anrien:BAABNQAECn8eAAIGAAgKbSJNAACRAgAGAAgKbSJNAACRAgAAAA==.',
Ar='Ari:BAAANQADCgcIBwAAAA==.Around:BAAANQAECgQICAAAAA==.',
As='Asharal:BAAANQAECgEIAQAAAA==.',
At='Atriste:BAABNQAECn8lAAMEAAgK8RJrDwBiAQAEAAgK8RJrDwBiAQAHAAUKSgf1jwDFAAAAAA==.',
Au='Aunyx:BAABNQAECn8kAAIBAAgK+w1fCQCIAQABAAgK+w1fCQCIAQAAAA==.',
Az='Azenoth:BAAANQADCggIGgAAAA==.',
Ba='Babajaga:BAAANQADCgIJAgAAAA==.Baloth:BAAANQADCgYIDAABNQAECggIJAAIALYPAA==.',
Be='Beej:BAABNQAECn8tAAIJAAkKtBgiDwCPAgAJAAkKtBgiDwCPAgAAAA==.',
Bi='Biggooch:BAABNQAECn8bAAIKAAgKexbOgQAWAgAKAAgKexbOgQAWAgAAAA==.Bigocritties:BAAANQAECgEIAQAAAA==.Bison:BAAANQADCgcIBwAAAA==.',
Bl='Blackrose:BAAANQADCggIGwABNQAECgoKJAAKANoXAA==.Blightbeard:BAAANQAECggIEgAAAA==.Blîss:BAAANQAECgUIEwAAAA==.',
Bo='Bowjobs:BAAANQADCgYIBgABNQAECgYIFAAHAF0WAA==.',
Br='Brayliel:BAAANQADCgQIBQAAAA==.Brut:BAAANQAECgUICwABNQAECgkJLAALAEYhAA==.',
Bu='Bullsi:BAAANQAECgEIAQABNQAECgkJQAAMAMQbAA==.Bumpy:BAAANQADCggICAAAAA==.Bustus:BAABNQAECn8kAAINAAgKowtiEgAyAQANAAgKowtiEgAyAQAAAA==.',
Ca='Calinia:BAAANQABCgMIBQAAAA==.Carole:BAABNQAECn9BAAQOAAoKZx1LCADTAQAEAAgKlyBVKACYAgAOAAgKaBdLCADTAQAHAAYKChRNagBKAQAAAA==.Caroll:BAABNQAECn8sAAQLAAkKRiHoDAAcAwALAAgKmyPoDAAcAwAPAAQK/xViuADvAAAGAAMKQgvMGgCTAAAAAA==.Carsomavra:BAAANQADCgYIDgAAAA==.Cathercy:BAABNQAECn8ZAAIQAAYKAA946ABKAQAQAAYKAA946ABKAQAAAA==.',
Ch='Chenzhen:BAAANQAECgcIDgAAAA==.Chrollo:BAAANQAECgcIEQAAAA==.Chunt:BAAANQADCgYIDQAAAA==.',
Cl='Cloggy:BAAANQADCgYIBgABNQAFFAYIDQARAC8aAA==.',
Co='Connery:BAAANQADCggIDgAAAA==.Corannis:BAABNQAECn8iAAISAAcKSRVbHwA+AQASAAcKSRVbHwA+AQAAAA==.Corax:BAAANQAECgEIAQAAAA==.',
Cr='Cranberries:BAAANQAECgMIBAABNQAECgoKMQAFABQLAA==.Cravedog:BAABNQAECn83AAMMAAgKLiOEBgAnAwAMAAgKLiOEBgAnAwATAAMKZAsnkwCLAAAAAA==.Creepi:BAABNQAECn8ZAAMGAAYKaRrICQC1AQAGAAUKQx7ICQC1AQALAAYKyRHZNgBtAQAAAA==.Crockett:BAAANQADCgMIAwABNQAECgIIAwAUAAAAAA==.Cromgabhar:BAAANQADCggICAABNQAECgYIFAAHAF0WAA==.',
Cu='Cupcáke:BAABNQAECn8VAAIQAAkK5ROMmADyAQAQAAkK5ROMmADyAQAAAA==.Curthodnes:BAAANQADCgIJAgAAAA==.',
Da='Dalmas:BAAANQADCgUICAAAAA==.Damaso:BAAANQAECgYIEgAAAA==.Damik:BAAANQAECgEIAQAAAA==.Darku:BAABNQAECn8iAAILAAgK8R7GAgAFAgALAAgK8R7GAgAFAgAAAA==.Darlàrk:BAAANQAECgYICwAAAA==.Dawnmane:BAABNQAFFH8GAAIVAAMKARyoAwCsAAAVAAMKARyoAwCsAAAAAA==.',
De='Deathsquaad:BAAANQAECgIIAgAAAA==.Delderach:BAABNQAECn8ZAAIVAAYKXxemJgCpAQAVAAYKXxemJgCpAQAAAA==.Dellila:BAAANQABCgcIBwAAAA==.Denin:BAABNQAECn8aAAIBAAgKTBDHNAAIAgABAAgKTBDHNAAIAgAAAA==.Derphardigan:BAAANQADCgYIBgABNQAECgYIFAAHAF0WAA==.',
Di='Diego:BAAANQADCgMIBAAAAA==.Dirkette:BAABNQAECn8gAAIGAAgKvwj2DABnAQAGAAgKvwj2DABnAQAAAA==.Dirksavoid:BAAANQAECgEIAQABNQAECggIIAAGAL8IAA==.',
Dk='Dkxsmurfx:BAAANQADCgYICAAAAA==.',
Do='Dokai:BAABNQAECn8kAAIIAAgKtg/2CwBXAQAIAAgKtg/2CwBXAQAAAA==.Doof:BAAANQAECgEIAQAAAA==.',
Dr='Dracmiz:BAAANQAECgcIBwABNQAECgkJNgAVAGUeAA==.Drathan:BAAANQADCgMJAwAAAA==.',
Dt='Dthnght:BAAANQADCgQIBwAAAA==.',
Du='Duskweaver:BAAANQADCgIIAgAAAA==.',
Ea='Earthboy:BAAANQADCgIIAgABNQAECgkJLAALAEYhAA==.',
Ed='Edamina:BAAANQABCgYIDQAAAA==.',
El='Elaenei:BAAANQADCgcIFgAAAA==.Eliance:BAABNQAECn8XAAIBAAYK6QPbbwDxAAABAAYK6QPbbwDxAAAAAA==.Elienn:BAAANQADCgcIGAAAAA==.Elinore:BAAANQADCgQIBAAAAA==.Elmer:BAAANQAECgEIAQAAAA==.',
Er='Errius:BAABNQAECn8hAAIHAAcKQwpAbABDAQAHAAcKQwpAbABDAQAAAA==.',
Es='Esh:BAAANQADCgQIBAABNQAECggIEwAUAAAAAA==.',
Eu='Eunja:BAEANQADCggIKwAAAQ==.',
Ey='Eyowynne:BAAANQADCgIIAgAAAA==.',
Fa='Facetious:BAAANQADCgIIAgAAAA==.Fatherbetter:BAAANQADCgYIBAABNQAFFAIIBQAWAAQUAA==.',
Fi='Filharmonic:BAAANQAECgEIAQAAAA==.Fizzbin:BAAANQADCgQIBwAAAA==.',
Fo='Foid:BAACNQAFFH8JAAMXAAMKnBuqAQARAQAXAAMKnBuqAQARAQAKAAEKWA1BPwBBAAA1AAQKfxoAAxcACQq+I6ADABgDABcACQq+I6ADABgDAAoAAQobAsdtARQAAAE1AAUUAwoJABcAnBsA.',
Fu='Furiah:BAAANQADCgYICwAAAA==.Fusaa:BAABNQAECn80AAIRAAoKhRTOLQA/AQARAAoKhRTOLQA/AQAAAA==.',
Ga='Gahzoo:BAAANQADCgYIFAAAAA==.Gallindo:BAAANQADCgIIAgABNQAECggIDwAUAAAAAA==.Gangry:BAAANQADCgYIDAAAAA==.Garretjax:BAAANQADCggIGgAAAA==.Garuda:BAABNQAECn8ZAAIWAAgKOBkfGQCSAgAWAAgKOBkfGQCSAgAAAA==.',
Ge='Gelst:BAAANQAECgEIAQAAAA==.Gelstoo:BAAANQADCgYICwAAAA==.Gerbs:BAAANQADCgYIDAAAAA==.Gerbzarrion:BAAANQAECgQIEQAAAA==.Getherdone:BAAANQADCgYIEgAAAA==.',
Gi='Gilgador:BAABNQAECn8ZAAIYAAkK+g2QPgDGAQAYAAkK+g2QPgDGAQABNQAECgoKHgAFAJIaAA==.',
Gr='Grape:BAAANQADCgYIBgABNQAECgkJLAALAEYhAA==.Grassfed:BAAANQAECgYIEgAAAA==.Grimbeloc:BAAANQADCgUICgAAAA==.',
Gu='Guilehart:BAAANQAECgEIAQAAAA==.',
Ha='Hawknnib:BAAANQAECgQIDAABNQAECgUICAAUAAAAAA==.Hawknnin:BAAANQAECgUICAAAAA==.',
He='Hexican:BAAANQADCgYIBgABNQAECgYIFAAHAF0WAA==.',
Ho='Hothala:BAAANQAECgcICQAAAA==.',
Hu='Hunterpulled:BAABNQAECn9EAAIZAAoKYxcVNwBNAQAZAAoKYxcVNwBNAQAAAA==.',
Ic='Icnothing:BAAANQADCgcIEAAAAA==.',
In='Infectedarms:BAABNQAECn8dAAIKAAcKIQWoaQDGAAAKAAcKIQWoaQDGAAAAAA==.Invisabull:BAAANQADCgYIBgABNQAECgYIFAAHAF0WAA==.',
Ip='Ipwnallnoobs:BAABNQAECn8jAAIOAAkKogkuTACIAQAOAAkKogkuTACIAQAAAA==.',
Ir='Irisila:BAAANQAECgEIAQABNQAECggIDwAUAAAAAA==.',
Ja='Jaskilz:BAAANQADCgUIBwAAAA==.Jaypharyn:BAAANQAECgcIEgAAAA==.Jazel:BAAANQADCgQICAAAAA==.',
Je='Jeeb:BAAANQABCgIIAgABNQAECgkJLQAJALQYAA==.Jellyapes:BAABNQAECn8VAAIaAAYKSwqUdgDQAAAaAAYKSwqUdgDQAAAAAA==.',
Jo='Johalea:BAAANQADCgcIEgAAAA==.',
Ju='Juliå:BAAANQADCgYIDQAAAA==.',
['Jå']='Jåsper:BAABNQAECn8XAAIQAAcKrhjBQgBAAQAQAAcKrhjBQgBAAQAAAA==.',
Ka='Kahea:BAEANQAECgEIAQABNQAECgYIDwAUAAAAAA==.Kaileena:BAABNQAECn8mAAIbAAoKXBZnCQBSAgAbAAoKXBZnCQBSAgAAAA==.Kasia:BAABNQAECn8XAAMFAAcKfx45YQDqAQAFAAYKHx05YQDqAQASAAEKEBlNewBNAAAAAA==.Kassani:BAAANQADCgEJAQAAAA==.Kasuga:BAAANQADCgQIBAABNQAECgkJIAAcAJcjAA==.',
Ke='Kenneth:BAAANQADCgQIBAAAAA==.',
Ki='Kieler:BAAANQAECgUICwAAAA==.Kierrings:BAAANQAECgYIDQAAAA==.Kikala:BAAANQADCgMIAwAAAA==.Kirarah:BAABNQAECn8fAAIZAAgK5x+JMQDYAgAZAAgK5x+JMQDYAgAAAA==.Kiylo:BAAANQADCgEIAQAAAA==.Kizune:BAAANQAECgEIAQAAAA==.',
Kl='Klauss:BAABNQAECn8jAAIJAAgKEAyEDQD9AAAJAAgKEAyEDQD9AAAAAA==.Klax:BAAANQADCggIGwAAAA==.',
Ko='Kordjin:BAAANQADCgIIAgAAAA==.',
Kr='Krornik:BAAANQADCgYIDgABNQAECgQIBgAUAAAAAA==.',
Ku='Kuyaros:BAAANQADCgUIBQAAAA==.',
['Kí']='Kíhanna:BAABNQAECn8jAAIZAAgKOSE0LwDfAgAZAAgKOSE0LwDfAgAAAA==.',
Le='Legenddairy:BAABNQAECn9AAAIMAAkKxBs0BwCOAQAMAAkKxBs0BwCOAQAAAA==.',
Li='Liemach:BAAANQADCgIIAgAAAA==.',
Lj='Ljósálfr:BAABNQAECn8iAAIdAAkKlyFABgAEAwAdAAkKlyFABgAEAwAAAA==.',
Lo='Lochramae:BAABNQAECn8YAAQEAAgKvhUJTQDgAQAEAAgKchQJTQDgAQAHAAUKJg9SewALAQAOAAUKBAe7cgDVAAAAAA==.Loupe:BAAANQADCgMIAwAAAA==.',
Lu='Lunaluvegood:BAAANQADCgUIBQAAAA==.Lunargaze:BAACNQAFFH8FAAMWAAIKBBQeBgCTAAAWAAIKBBQeBgCTAAAYAAEKlAH8IAAtAAA1AAQKfzoAAxYACgryItECAK4DABYACgryItECAK4DABgABAoHHXBVADgBAAAA.',
['Lâ']='Lâriel:BAABNQAECn8ZAAIaAAcKjgM5QAEiAQAaAAcKjgM5QAEiAQAAAA==.',
Ma='Madaya:BAABNQAECn8iAAIZAAkK/BTiawA7AgAZAAkK/BTiawA7AgAAAA==.Madmartigan:BAABNQAECn8UAAIHAAYKXRaQVQCeAQAHAAYKXRaQVQCeAQAAAA==.Mahangi:BAAANQADCggIDgAAAA==.Mamimisan:BAABNQAECn8bAAIFAAgKxxb9WgD/AQAFAAgKxxb9WgD/AQAAAA==.Matix:BAAANQABCggIHwAAAA==.',
Me='Mechadockie:BAAANQAECggIDwAAAA==.',
Mi='Miklo:BAAANQADCgUICgAAAA==.Mirah:BAAANQAECgUICQAAAA==.Mistazee:BAAANQAECgUICgAAAA==.Mizan:BAAANQAECggIDwABNQAECgkJNgAVAGUeAA==.Mizeroni:BAABNQAECn82AAMVAAkKZR7JCAARAwAVAAkKZR7JCAARAwAeAAEKjATrJgEuAAAAAA==.Mizkat:BAAANQADCgcIAQABNQAECgkJNgAVAGUeAA==.Mizky:BAAANQADCggICgAAAA==.',
Mo='Mormra:BAAANQAECgIIAgAAAA==.',
Mt='Mtruckski:BAAANQABCgIIAgABNQAECgQICQAUAAAAAA==.',
My='Myoo:BAAANQADCgUIBgAAAA==.',
['Më']='Mërcy:BAAANQADCgcIFAAAAA==.',
Na='Naklus:BAAANQADCgUICQAAAA==.',
Ne='Neilia:BAABNQAECn8eAAMFAAoKkhovHQD4AgAFAAoKkhovHQD4AgASAAIKfgM8JAFJAAAAAA==.Nerdroot:BAAANQADCgMIAwABNQAECgcIIQAbAJ0FAA==.Nerdvana:BAAANQADCgcIDQABNQAECgcIIQAbAJ0FAA==.Neropoison:BAAANQADCgIIAwAAAA==.Nessamos:BAAANQADCgIIAgAAAA==.',
Ni='Nikalkhano:BAAANQADCgYICQAAAA==.',
Nl='Nlani:BAAANQAECgQIDAAAAA==.',
Nu='Nuvi:BAAANQADCgUICAAAAA==.',
Oc='Octarius:BAAANQAECgIIAwABNQAECgQIBgAUAAAAAA==.',
On='Onomirigaru:BAABNQAECn8pAAIWAAgKehjDIgA0AgAWAAgKehjDIgA0AgAAAA==.',
Op='Oproer:BAAANQADCggICAAAAA==.',
Ox='Oxygentank:BAABNQAECn8UAAMfAAkKtBXTCwDhAAAfAAcKeRnTCwDhAAATAAQKSgzPkACTAAAAAA==.',
Pa='Parne:BAAANQADCgYIDwAAAA==.',
Pi='Piccolo:BAAANQAECggIAQAAAA==.Pips:BAAANQADCgYIBgAAAA==.',
Pl='Platura:BAABNQAECn8hAAIeAAgKghfWXwD5AQAeAAgKghfWXwD5AQAAAA==.',
Pv='Pvp:BAAANQADCgMIAwAAAA==.',
Ra='Raezune:BAAANQAECgEIAwAAAA==.Rajia:BAABNQAECn8lAAIcAAgKTwesAwAFAQAcAAgKTwesAwAFAQAAAA==.Ranron:BAAANQAECgQIBQAAAA==.Rassaphore:BAAANQADCggIDwAAAA==.Raínbow:BAAANQADCgcJCgABNQAECgYIFQAVAPwSAA==.',
Re='Reapin:BAABNQAECn8YAAIOAAcKSxPpIgAXAQAOAAcKSxPpIgAXAQAAAA==.Rezeldâ:BAAANQAECgEIAQAAAA==.',
Rh='Rhaegalsh:BAABNQAECn8aAAISAAgKNw0fdwC8AQASAAgKNw0fdwC8AQAAAA==.',
Ri='Rionach:BAABNQAECn8kAAIMAAgKWwxlDwAVAQAMAAgKWwxlDwAVAQAAAA==.Rivon:BAAANQADCggIGgAAAA==.',
Ro='Rob:BAAANQAECgEIAQAAAA==.',
Ru='Runeneya:BAAANQAECggIBwAAAA==.',
Sc='Schtzngigllz:BAAANQADCgQIBwABNQAECgIIAgAUAAAAAA==.Scoop:BAABNQAECn8kAAMLAAoKLB7IKADiAQALAAcKoRrIKADiAQAPAAkKcBusFQDDAQAAAA==.',
Se='Seanan:BAABNQAECn8yAAIgAAoKGyKXAwBjAwAgAAoKGyKXAwBjAwAAAA==.Seera:BAAANQADCgIIAgAAAA==.Seran:BAABNQAECn8tAAIeAAoKVwaefACjAQAeAAoKVwaefACjAQAAAA==.Servantes:BAAANQADCgMIBAAAAA==.',
Sh='Shammwow:BAAANQAECgcIDAAAAA==.Shamoo:BAAANQAECgYIBwAAAA==.Shaudis:BAABNQAECn8lAAIRAAkKrBh3VgBTAgARAAkKrBh3VgBTAgAAAA==.Shiftyshape:BAAANQAECgEJAQAAAA==.Shigurexx:BAABNQAECn8aAAIhAAgKdw1cMwCzAQAhAAgKdw1cMwCzAQAAAA==.Shoe:BAABNQAECn8yAAICAAoKYxQ5DgB8AgACAAoKYxQ5DgB8AgAAAA==.Shootup:BAAANQADCgcIEAAAAA==.',
Si='Siph:BAAANQAECgMIAwAAAA==.',
Sk='Skiliz:BAAANQADCgYIDAAAAA==.',
Sl='Slapurdaddy:BAAANQADCgUJCQAAAA==.',
So='Somassen:BAABNQAECn8iAAIZAAcKqgvRqgCvAQAZAAcKqgvRqgCvAQAAAA==.Sonashee:BAAANQAECgcIDgAAAA==.Sorender:BAAANQADCgYIFgAAAA==.',
St='Steelbutt:BAAANQADCggIJwAAAA==.',
Su='Supersoakêr:BAAANQAECgQIBAABNQAECgcIDgAUAAAAAA==.Surii:BAAANQADCgYICwAAAA==.',
Ta='Talene:BAAANQADCgUIBgAAAA==.Tamarins:BAAANQAECgcIEgAAAA==.Tappy:BAABNQAECn8yAAIPAAoK7BK2RgBTAgAPAAoK7BK2RgBTAgAAAA==.',
Te='Terkarakk:BAABNQAECn8bAAIMAAgKGSSPBgAmAwAMAAgKGSSPBgAmAwABNQAFFAMIBgAVAAEcAA==.',
Th='Thirryn:BAABNQAECn8aAAIiAAgKZQefEQAbAQAiAAgKZQefEQAbAQAAAA==.Thorybos:BAABNQAECn8aAAIaAAoK6BkwXgDDAgAaAAoK6BkwXgDDAgAAAA==.',
Ti='Tippy:BAAANQAECgQICQAAAA==.',
To='Toom:BAABNQAECn8ZAAIZAAYKEgfXzgBjAQAZAAYKEgfXzgBjAQAAAA==.',
Tr='Traylinna:BAAANQADCgEIAQAAAA==.Trophyhubby:BAABNQAECn8hAAMPAAcKvw61hACJAQAPAAcKvw61hACJAQALAAQKMgTVWQChAAAAAA==.',
Tu='Tuknark:BAAANQADCgcIGAAAAA==.',
Ty='Tyeren:BAABNQAECn8UAAMEAAcKNhFoagBpAQAEAAcKew5oagBpAQAHAAQKLBYDhgDlAAAAAA==.Tyeriel:BAACNQAFFH8QAAMOAAQKaA16EQDIAAAOAAMKnQx6EQDIAAAEAAMKMwppFADDAAA1AAQKfy0AAw4ACgofGoQnAFsCAA4ACgrEGYQnAFsCAAQABQqgGc1zAEgBAAAA.Typpy:BAAANQAECgQIBwAAAA==.',
Tz='Tzuriel:BAEBNQAECn8uAAMVAAoKIx+LAQBzAgAVAAgKliSLAQBzAgAQAAcKkQ5d0QB5AQAAAA==.',
Va='Valat:BAAANQADCgYIBgAAAA==.Valkyriewing:BAABNQAECn8ZAAIeAAYKpQ3bogA/AQAeAAYKpQ3bogA/AQAAAA==.Valvet:BAAANQADCggILwAAAA==.',
Ve='Velaste:BAAANQADCgQIBAAAAA==.',
Vi='Vikril:BAABNQAECn8iAAQOAAgKGxd3GABLAQAHAAcK0RgPQwDwAQAOAAcKewt3GABLAQAEAAYKPg09fAArAQAAAA==.Vincenzo:BAAANQAECgMIAwAAAA==.',
Vo='Volkanoth:BAAANQAECgUIBwAAAA==.',
Vu='Vue:BAAANQADCgYIBgABNQADCggIGwAUAAAAAA==.',
Vy='Vylus:BAABNQAECn8ZAAIYAAcKxAlbTgBiAQAYAAcKxAlbTgBiAQAAAA==.',
['Vá']='Vásh:BAABNQAECn8lAAMKAAgKVA2KMABMAQAKAAgK4QuKMABMAQAXAAYKHwwvFgA5AQAAAA==.',
We='Webjibaro:BAAANQADCgUICgAAAA==.Weeblewobble:BAAANQADCgcIGAAAAA==.Weili:BAABNQAECn8UAAITAAcK7BFTEwBAAQATAAcK7BFTEwBAAQAAAA==.',
Wh='Whiney:BAAANQAECgIIAwABNQAECgYICgAUAAAAAA==.',
Wi='Wikidfiend:BAAANQADCgQIBQAAAA==.William:BAABNQAECn8YAAIZAAgKzRnSTwB/AgAZAAgKzRnSTwB/AgAAAA==.Willious:BAAANQABCgIIAgAAAA==.Windee:BAAANQADCgYICgAAAA==.Wishi:BAAANQADCgQIBAAAAA==.',
Wr='Wrast:BAAANQAECgYIEwAAAA==.Wravyn:BAABNQAECn8gAAIZAAcKxgVWxwBzAQAZAAcKxgVWxwBzAQAAAA==.',
Xa='Xalted:BAAANQADCgUICQAAAA==.Xandria:BAAANQADCgUIBQAAAA==.Xaylios:BAAANQAECggIEQAAAA==.',
Xy='Xyara:BAABNQAECn8xAAQjAAoKIhphBAARAQARAAgKnBI4eAD6AQAcAAUKZhh/IwBWAQAjAAYKqhhhBAARAQAAAA==.',
Yo='Yoghurt:BAABNQAECn8dAAMXAAgK4hr7CABOAgAXAAgK4hr7CABOAgAKAAEKAACBXwEnAAAAAA==.',
Yu='Yunlan:BAAANQAECgQIBgAAAA==.',
Za='Zalidus:BAAANQAECggIEgAAAA==.Zanthor:BAAANQAECgUIDgABNQAECgoKMgAIADgSAA==.',
Ze='Zehnia:BAAANQABCgcIDQAAAA==.Zephira:BAAANQADCgUIBgAAAA==.Zerhistran:BAAANQAECgcICQAAAA==.',
Zi='Zibzab:BAABNQAECn8ZAAITAAYK4wjybQATAQATAAYK4wjybQATAQAAAA==.',
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
