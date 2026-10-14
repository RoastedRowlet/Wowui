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

local lookup = {'Rogue-Assassination','DeathKnight-Unholy','Shaman-Restoration','Priest-Discipline','DeathKnight-Blood','Monk-Windwalker','Monk-Mistweaver','Warrior-Arms','Unknown-Unknown','Priest-Shadow','Druid-Guardian','Druid-Restoration','Priest-Holy','Warlock-Demonology','Shaman-Elemental','Druid-Balance','Paladin-Protection','Warrior-Fury','DemonHunter-Devourer','Hunter-BeastMastery','DeathKnight-Frost','DemonHunter-Vengeance','Warlock-Destruction','Warrior-Protection','DemonHunter-Havoc','Mage-Arcane','Paladin-Holy','Shaman-Enhancement','Hunter-Marksmanship','Evoker-Devastation','Evoker-Augmentation','Paladin-Retribution','Warlock-Affliction',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aastrid:BAAANQADCgYIEgAAAA==.',
Ad='Adorabúll:BAAANQADCgEIAQAAAA==.',
Ae='Aevriia:BAAANQADCgIIAgAAAA==.',
Ak='Akélla:BAAANQAECggICAAAAA==.',
Al='Aldric:BAAANQAECgQIBAAAAA==.Alien:BAABNQAFFH8FAAIBAAMKKRMDDwDzAAABAAMKKRMDDwDzAAAAAA==.Althenzdormu:BAAANQAECgUIDwAAAA==.Altruist:BAAANQAECgQICQABNQAECgcIHgACAE4VAA==.',
Am='Amaethon:BAAANQAECgUIDQAAAA==.',
An='Ancaera:BAAANQADCggIDQAAAA==.Andalikus:BAABNQAECn8iAAIDAAgKGyNjFgAcAwADAAgKGyNjFgAcAwAAAA==.Andorra:BAAANQADCgYICwAAAA==.Andybocelli:BAAANQADCgYIBgAAAA==.Anrien:BAABNQAECn8XAAIEAAcKdyMpAwDJAgAEAAcKdyMpAwDJAgAAAA==.',
Ar='Ari:BAAANQADCgcIBwAAAA==.Around:BAAANQAECgQIBgAAAA==.',
As='Asharal:BAAANQADCgYIBgAAAA==.',
At='Atriste:BAABNQAECn8eAAMCAAcKThUzWACsAQACAAcKThUzWACsAQAFAAUKSgfMjgDFAAAAAA==.',
Au='Aunyx:BAABNQAECn8dAAIBAAcK6AsgSACeAQABAAcK6AsgSACeAQAAAA==.',
Az='Azenoth:BAAANQADCggIGgAAAA==.',
Ba='Babajaga:BAAANQADCgIJAgAAAA==.Baloth:BAAANQADCgYIDAABNQAECgcIHQAGAO0RAA==.',
Be='Beej:BAABNQAECn8mAAIHAAkKtBjoDgCPAgAHAAkKtBjoDgCPAgAAAA==.',
Bi='Biggooch:BAABNQAECn8YAAIIAAgKexYmgAAXAgAIAAgKexYmgAAXAgAAAA==.Bigocritties:BAAANQADCgYIBgAAAA==.Bison:BAAANQADCgcJBwAAAA==.',
Bl='Blackrose:BAAANQADCgYIEwABNQAECgkJHQAIAPEYAA==.Blightbeard:BAAANQAECgUIDgAAAA==.Blîss:BAAANQAECgUIDgAAAA==.',
Bo='Bowjobs:BAAANQADCgYIBgABNQAECgUIDgAJAAAAAA==.',
Br='Brayliel:BAAANQADCgQIBQAAAA==.Brut:BAAANQAECgQIBwABNQAECgkJKgAKAEYhAA==.',
Bu='Bullsi:BAAANQADCggIEAABNQAECggINwALAAUbAA==.Bumpy:BAAANQADCggICAAAAA==.Bustus:BAABNQAECn8dAAIMAAcKoQy8OABTAQAMAAcKoQy8OABTAQAAAA==.',
Ca='Calinia:BAAANQABCgMIBQAAAA==.Carole:BAABNQAECn83AAMCAAgKlyDmJwCZAgACAAgKlyDmJwCZAgAFAAYKChRiaQBLAQAAAA==.Caroll:BAABNQAECn8qAAQKAAkKRiG2DAAdAwAKAAgKmyO2DAAdAwANAAQK/xUrtgDvAAAEAAMKQguOGgCSAAAAAA==.Carsomavra:BAAANQADCgYIDgAAAA==.Cathercy:BAAANQAECgUIEgAAAA==.',
Ch='Chenzhen:BAAANQAECgQIBQAAAA==.Chrollo:BAAANQAECgUIDgAAAA==.Chunt:BAAANQADCgYIDQAAAA==.',
Cl='Cloggy:BAAANQADCgYIBgABNQAFFAUICgAOAKwcAA==.',
Co='Connery:BAAANQADCgYIBgAAAA==.Corannis:BAABNQAECn8cAAIPAAcKFBXXbwDNAQAPAAcKFBXXbwDNAQAAAA==.Corax:BAAANQADCgQIBgAAAA==.',
Cr='Cranberries:BAAANQAECgMIAwABNQAECgkJLQADAIkKAA==.Cravedog:BAABNQAECn83AAMLAAgKLiNrBgAnAwALAAgKLiNrBgAnAwAQAAMKZAuRkQCLAAAAAA==.Creepi:BAAANQAECgUIEgAAAA==.Crockett:BAAANQADCgMIAwABNQAECgEIAQAJAAAAAA==.Cromgabhar:BAAANQADCgYIBgABNQAECgUIDgAJAAAAAA==.',
Cu='Cupcáke:BAAANQAFFAEIAQAAAA==.Curthodnes:BAAANQADCgIJAgAAAA==.',
Da='Dalmas:BAAANQADCgUICAAAAA==.Damaso:BAAANQAECgQICQAAAA==.Damik:BAAANQAECgEIAQAAAA==.Darku:BAABNQAECn8bAAIKAAcKUyHBGACHAgAKAAcKUyHBGACHAgAAAA==.Darlàrk:BAAANQAECgYICQAAAA==.Dawnmane:BAAANQAFFAIIAwAAAA==.',
De='Delderach:BAAANQAECgUIEgAAAA==.Dellila:BAAANQABCgcIBwAAAA==.Denin:BAABNQAECn8aAAIBAAgKTBDFMwAIAgABAAgKTBDFMwAIAgAAAA==.Derphardigan:BAAANQADCgYIBgABNQAECgUIDgAJAAAAAA==.',
Di='Diego:BAAANQADCgMIBAAAAA==.Dirkette:BAABNQAECn8cAAIEAAgKvwjkDABnAQAEAAgKvwjkDABnAQAAAA==.Dirksavoid:BAAANQADCgYIBgABNQAECggIHAAEAL8IAA==.',
Dk='Dkxsmurfx:BAAANQADCgYICAAAAA==.',
Do='Dokai:BAABNQAECn8dAAIGAAcK7RHXLwCUAQAGAAcK7RHXLwCUAQAAAA==.',
Dr='Dracmiz:BAAANQAECgcIBwABNQAECgkJMAARAGUeAA==.Drathan:BAAANQADCgMJAwAAAA==.',
Dt='Dthnght:BAAANQADCgQIBwAAAA==.',
Du='Duskweaver:BAAANQADCgIIAgAAAA==.',
Ea='Earthboy:BAAANQADCgIIAgABNQAECgkJKgAKAEYhAA==.',
El='Elaenei:BAAANQADCgcIFgAAAA==.Eliance:BAAANQAECgUIEgAAAA==.Elienn:BAAANQADCgcIGAAAAA==.Elinore:BAAANQADCgQIBAAAAA==.Elmer:BAAANQAECgEIAQAAAA==.',
Er='Errius:BAABNQAECn8gAAIFAAcKQwppawBDAQAFAAcKQwppawBDAQAAAA==.Eryndor:BAAANQAECgEIAQAAAA==.',
Es='Esh:BAAANQADCgQIBAABNQAECggIDwAJAAAAAA==.',
Eu='Eunja:BAEANQADCggIIwAAAQ==.',
Fa='Facetious:BAAANQADCgIIAgAAAA==.',
Fi='Filharmonic:BAAANQADCgcIFwAAAA==.Fizzbin:BAAANQADCgQIBwAAAA==.',
Fo='Foid:BAACNQAFFH8JAAMSAAMKnBunAQAQAQASAAMKnBunAQAQAQAIAAEKWA1FPgBBAAA1AAQKfxoAAxIACQq+I5wDABgDABIACQq+I5wDABgDAAgAAQobAvFoARQAAAE1AAUUAwoJABIAnBsA.',
Fu='Furiah:BAAANQADCgYICwAAAA==.Fusaa:BAABNQAECn8uAAIOAAgKjRV5ZQAmAgAOAAgKjRV5ZQAmAgAAAA==.',
Ga='Gahzoo:BAAANQADCgYIFAAAAA==.Gallindo:BAAANQADCgIIAgABNQAECgQICgAJAAAAAA==.Gangry:BAAANQADCgYIDAAAAA==.Garretjax:BAAANQADCgYIGQAAAA==.Garuda:BAABNQAECn8ZAAITAAgKOBnHGACTAgATAAgKOBnHGACTAgAAAA==.',
Ge='Gelst:BAAANQAECgEIAQAAAA==.Gelstoo:BAAANQADCgYICwAAAA==.Gerbs:BAAANQADCgYIDAAAAA==.Gerbzarrion:BAAANQAECgQIDQAAAA==.Getherdone:BAAANQADCgUIEQAAAA==.',
Gi='Gilgador:BAAANQAECgcIEwABNQAECgkJGgADADMcAA==.',
Gr='Grape:BAAANQADCgYIBgABNQAECgkJKgAKAEYhAA==.Grassfed:BAAANQAECgUIDQAAAA==.Grimbeloc:BAAANQADCgUICgAAAA==.',
Gu='Guilehart:BAAANQABCgIIAQAAAA==.',
Ha='Hawknnib:BAAANQAECgQICQABNQAECgUIBQAJAAAAAA==.Hawknnin:BAAANQAECgUIBQAAAA==.',
Ho='Hothala:BAAANQAECgMIAwAAAA==.',
Hu='Hunterpulled:BAABNQAECn88AAIUAAkKuhTYWABmAgAUAAkKuhTYWABmAgAAAA==.',
Ic='Icnothing:BAAANQADCgcIEAAAAA==.',
In='Infectedarms:BAAANQAECgYIEwAAAA==.Invisabull:BAAANQADCgYIBgABNQAECgUIDgAJAAAAAA==.',
Ip='Ipwnallnoobs:BAABNQAECn8eAAIVAAgKAArUSgCIAQAVAAgKAArUSgCIAQAAAA==.',
Ir='Irisila:BAAANQAECgEIAQABNQAECgQICgAJAAAAAA==.',
Ja='Jaskilz:BAAANQADCgUIBwAAAA==.Jaypharyn:BAAANQAECgQICgAAAA==.Jazel:BAAANQADCgQICAAAAA==.',
Je='Jellyapes:BAAANQAECgQIDAAAAA==.',
Jo='Johalea:BAAANQADCgcIEgAAAA==.',
Ju='Juliå:BAAANQADCgYIDQAAAA==.',
['Jå']='Jåsper:BAAANQAECgUIDwAAAA==.',
Ka='Kahea:BAEANQADCgYIBgABNQAECgYIDQAJAAAAAA==.Kaileena:BAABNQAECn8iAAIWAAgKmhhPCQBRAgAWAAgKmhhPCQBRAgAAAA==.Kasia:BAAANQAECgUIDwAAAA==.Kassani:BAAANQADCgEJAQAAAA==.Kasuga:BAAANQADCgQIBAABNQAECgkJIAAXAJcjAA==.',
Ke='Kenneth:BAAANQADCgQIBAAAAA==.',
Ki='Kieler:BAAANQAECgUICgAAAA==.Kierrings:BAAANQAECgYIDQAAAA==.Kikala:BAAANQADCgMIAwAAAA==.Kirarah:BAABNQAECn8bAAIUAAcKIiWXMADZAgAUAAcKIiWXMADZAgAAAA==.Kiylo:BAAANQADCgEIAQAAAA==.Kizune:BAAANQADCgcIBwAAAA==.',
Kl='Klauss:BAABNQAECn8dAAIHAAgK9wozIgBvAQAHAAgK9wozIgBvAQAAAA==.Klax:BAAANQADCgcIGQAAAA==.',
Ko='Kordjin:BAAANQADCgIIAgAAAA==.',
Kr='Krornik:BAAANQADCgYIDgABNQAECgEIAQAJAAAAAA==.',
Ku='Kuyaros:BAAANQADCgUIBQAAAA==.',
['Kí']='Kíhanna:BAABNQAECn8dAAIUAAgKICH4LQDhAgAUAAgKICH4LQDhAgAAAA==.',
Le='Legenddairy:BAABNQAECn83AAILAAgKBRuvDQCFAgALAAgKBRuvDQCFAgAAAA==.',
Li='Liemach:BAAANQADCgIIAgAAAA==.',
Lj='Ljósálfr:BAABNQAECn8eAAIYAAgKnSIoBgAFAwAYAAgKnSIoBgAFAwAAAA==.',
Lo='Lochramae:BAABNQAECn8YAAQCAAgKvhVYTADgAQACAAgKchRYTADgAQAFAAUKJg8+egAMAQAVAAUKBAdkcADVAAAAAA==.Loupe:BAAANQADCgMIAwAAAA==.',
Lu='Lunaluvegood:BAAANQADCgUIBQAAAA==.Lunargaze:BAABNQAECn8zAAMTAAkKDiW/AgCvAwATAAkKDiW/AgCvAwAZAAQKBx1VVAA5AQAAAA==.',
['Lâ']='Lâriel:BAABNQAECn8ZAAIaAAcKjgM+PQEjAQAaAAcKjgM+PQEjAQAAAA==.',
Ma='Madaya:BAABNQAECn8eAAIUAAgKyhabagA7AgAUAAgKyhabagA7AgAAAA==.Madmartigan:BAAANQAECgUIDgAAAA==.Mahangi:BAAANQADCgYIBgAAAA==.Mamimisan:BAABNQAECn8YAAIDAAgKnhTyWQD/AQADAAgKnhTyWQD/AQAAAA==.Matix:BAAANQABCggIGQAAAA==.',
Me='Mechadockie:BAAANQAECgUICwAAAA==.',
Mi='Miklo:BAAANQADCgUICgAAAA==.Mirah:BAAANQAECgQIBAAAAA==.Mistazee:BAAANQAECgUIBwAAAA==.Mizan:BAAANQAECggIDQABNQAECgkJMAARAGUeAA==.Mizeroni:BAABNQAECn8wAAMRAAkKZR61CAARAwARAAkKZR61CAARAwAbAAEKjASQIwEuAAAAAA==.Mizkat:BAAANQADCgcIAQABNQAECgkJMAARAGUeAA==.Mizky:BAAANQADCggICgAAAA==.',
Mo='Mormra:BAAANQAECgEIAgAAAA==.',
Mt='Mtruckski:BAAANQABCgIIAgABNQAECgQIBwAJAAAAAA==.',
My='Myoo:BAAANQADCgUIBgAAAA==.',
['Më']='Mërcy:BAAANQADCgcIFAAAAA==.',
Na='Naklus:BAAANQADCgUICQAAAA==.',
Ne='Neilia:BAABNQAECn8aAAMDAAkKMxy4HAD5AgADAAkKMxy4HAD5AgAPAAIKfgP+HwFJAAAAAA==.Nerdroot:BAAANQADCgMIAwABNQAECgcIIAAWAJ0FAA==.Nerdvana:BAAANQADCgcIDQABNQAECgcIIAAWAJ0FAA==.Neropoison:BAAANQADCgIIAwAAAA==.Nessamos:BAAANQADCgIIAgAAAA==.',
Ni='Nikalkhano:BAAANQADCgYICQAAAA==.',
Nl='Nlani:BAAANQAECgQIDAAAAA==.',
Nu='Nuvi:BAAANQADCgUICAAAAA==.',
Oc='Octarius:BAAANQAECgIIAgABNQAECgQIBgAJAAAAAA==.',
On='Onomirigaru:BAABNQAECn8jAAITAAgKGRhoIgA1AgATAAgKGRhoIgA1AgAAAA==.',
Op='Oproer:BAAANQADCggICAAAAA==.',
Ox='Oxygentank:BAAANQAECgYIDQAAAA==.',
Pa='Parne:BAAANQADCgYICwAAAA==.',
Pi='Piccolo:BAAANQAECggIAQAAAA==.Pips:BAAANQADCgYIBgABNQAECgYIIQACAGIOAA==.',
Pl='Platura:BAABNQAECn8eAAIbAAcKDBnwXgD5AQAbAAcKDBnwXgD5AQAAAA==.',
Pv='Pvp:BAAANQADCgMIAwAAAA==.',
Ra='Raezune:BAAANQABCgYICwAAAA==.Rajia:BAABNQAECn8eAAIXAAcKmQRdKQAvAQAXAAcKmQRdKQAvAQAAAA==.Ranron:BAAANQAECgMIAwAAAA==.Rassaphore:BAAANQADCggIDwAAAA==.Raínbow:BAAANQADCgcJCgABNQAECgUIDQAJAAAAAA==.',
Re='Reapin:BAAANQAECgUIDwAAAA==.Rezeldâ:BAAANQAECgEIAQAAAA==.',
Rh='Rhaegalsh:BAABNQAECn8aAAIPAAgKNw3xeACzAQAPAAgKNw3xeACzAQAAAA==.',
Ri='Rionach:BAABNQAECn8dAAILAAcKYw1AKABPAQALAAcKYw1AKABPAQAAAA==.Rivon:BAAANQADCggIGgAAAA==.',
Ru='Runeneya:BAAANQAECggIBwAAAA==.',
Sc='Schtzngigllz:BAAANQADCgQIBwABNQAECgEIAgAJAAAAAA==.Scoop:BAABNQAECn8bAAMNAAcKbxxnYwDyAQANAAYKmBxnYwDyAQAKAAcK4RZiKADjAQAAAA==.',
Se='Seanan:BAABNQAECn8sAAIcAAgKMyWCAwBkAwAcAAgKMyWCAwBkAwAAAA==.Seera:BAAANQADCgIIAgAAAA==.Seran:BAABNQAECn8oAAIbAAkK4wYxewCkAQAbAAkK4wYxewCkAQAAAA==.Servantes:BAAANQADCgIIAwAAAA==.',
Sh='Shammwow:BAAANQAECgcICgAAAA==.Shamoo:BAAANQAECgYIBgAAAA==.Shaudis:BAABNQAECn8kAAIOAAgKnBnMVABUAgAOAAgKnBnMVABUAgAAAA==.Shiftyshape:BAAANQAECgEJAQAAAA==.Shigurexx:BAABNQAECn8aAAIdAAgKdw3gMgCzAQAdAAgKdw3gMgCzAQAAAA==.Shoe:BAABNQAECn8tAAIeAAkKyBUUDgB8AgAeAAkKyBUUDgB8AgAAAA==.Shootup:BAAANQADCgcIEAAAAA==.',
Sk='Skiliz:BAAANQADCgYIDAAAAA==.',
Sl='Slapurdaddy:BAAANQADCgUJCQAAAA==.',
So='Somassen:BAABNQAECn8gAAIUAAcKQQuGqACwAQAUAAcKQQuGqACwAQAAAA==.Sonashee:BAAANQAECgcIDQAAAA==.Sorender:BAAANQADCgYIFgAAAA==.',
St='Steelbutt:BAAANQADCggIIwAAAA==.',
Su='Supersoakêr:BAAANQAECgQIBAABNQAECgcIDQAJAAAAAA==.Surii:BAAANQADCgYICwAAAA==.',
Ta='Talene:BAAANQADCgUIBgAAAA==.Tamarins:BAAANQAECgUIDwAAAA==.Tappy:BAABNQAECn8sAAINAAkKEhSlRQBTAgANAAkKEhSlRQBTAgAAAA==.',
Te='Terkarakk:BAABNQAECn8bAAILAAgKGSR3BgAlAwALAAgKGSR3BgAlAwABNQAFFAIIAwAJAAAAAA==.',
Th='Thirryn:BAABNQAECn8YAAIfAAcKZAhsEQAbAQAfAAcKZAhsEQAbAQAAAA==.Thorybos:BAABNQAECn8ZAAIaAAkKghunXADGAgAaAAkKghunXADGAgAAAA==.',
Ti='Tippy:BAAANQAECgQIBwAAAA==.',
To='Toom:BAAANQAECgUIEgAAAA==.',
Tr='Traylinna:BAAANQADCgEIAQAAAA==.Trophyhubby:BAABNQAECn8gAAMNAAcKvw46gwCJAQANAAcKvw46gwCJAQAKAAQKMgTAWAChAAAAAA==.',
Tu='Tuknark:BAAANQADCgcIGAAAAA==.',
Ty='Tyeren:BAAANQAECgYIEgAAAA==.Tyeriel:BAACNQAFFH8MAAMVAAQKaA3wEADIAAAVAAMKnQzwEADIAAACAAMKMwoaFADDAAA1AAQKfyoAAxUACQpbHOAmAFsCABUACQrzG+AmAFsCAAIABQqgGdJyAEgBAAAA.Typpy:BAAANQAECgIIAgAAAA==.',
Tz='Tzuriel:BAEBNQAECn8nAAMRAAkK+B4dCwDmAgARAAcKcCUdCwDmAgAgAAcKkQ5GzgB5AQAAAA==.',
Va='Valat:BAAANQADCgYIBgAAAA==.Valkyriewing:BAAANQAECgUIEgAAAA==.Valvet:BAAANQADCggIJwAAAA==.',
Ve='Velaste:BAAANQADCgQIBAAAAA==.',
Vi='Vikril:BAABNQAECn8YAAQFAAgK+hVuQgDwAQAFAAcKrBduQgDwAQACAAYKPg0gewArAQAVAAEKpQnYqgAzAAAAAA==.Vincenzo:BAAANQADCgYIDQAAAA==.',
Vo='Volkanoth:BAAANQAECgUIBwAAAA==.',
Vy='Vylus:BAAANQAECgYIEwAAAA==.',
['Vá']='Vásh:BAABNQAECn8eAAMSAAcK6w33FQA5AQAIAAcKLwxJtQCSAQASAAYKHwz3FQA5AQAAAA==.',
We='Webjibaro:BAAANQADCgUICgAAAA==.Weeblewobble:BAAANQADCgcIGAAAAA==.Weili:BAAANQAECgUIDQAAAA==.',
Wh='Whiney:BAAANQAECgIIAgABNQAECgYICQAJAAAAAA==.',
Wi='Wikidfiend:BAAANQADCgQIBQAAAA==.William:BAABNQAECn8YAAIUAAgKzRmZTgCAAgAUAAgKzRmZTgCAAgAAAA==.Windee:BAAANQADCgYICgAAAA==.Wishi:BAAANQADCgQIBAAAAA==.',
Wr='Wrast:BAAANQAECgYIDwAAAA==.Wravyn:BAABNQAECn8gAAIUAAcKxgWkxAB0AQAUAAcKxgWkxAB0AQAAAA==.',
Xa='Xalted:BAAANQADCgUJCQAAAA==.Xandria:BAAANQADCgUIBQAAAA==.Xaylios:BAAANQAECgYICQAAAA==.',
Xy='Xyara:BAABNQAECn8rAAQXAAkKfhZMIwBWAQAOAAcKnBRddgD7AQAXAAUKZhhMIwBWAQAhAAMKLA8FGQC/AAAAAA==.',
Yo='Yoghurt:BAABNQAECn8dAAMSAAgK4hrlCABOAgASAAgK4hrlCABOAgAIAAEKAAADWwEnAAAAAA==.',
Yu='Yunlan:BAAANQAECgEIAQAAAA==.',
Za='Zalidus:BAAANQAECgUIDQAAAA==.Zanthor:BAAANQAECgUIDgABNQAECgkJKQAGAPwRAA==.',
Ze='Zehnia:BAAANQABCgcIDQAAAA==.Zephira:BAAANQADCgUIBgAAAA==.Zerhistran:BAAANQAECgQIBAAAAA==.',
Zi='Zibzab:BAAANQAECgUIEgAAAA==.',
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
