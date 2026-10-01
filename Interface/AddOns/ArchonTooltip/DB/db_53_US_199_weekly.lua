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

local lookup = {'Warrior-Fury','Shaman-Restoration','Evoker-Devastation','Evoker-Augmentation','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Paladin-Holy','Unknown-Unknown','Warrior-Arms','Warrior-Protection','Priest-Holy','DemonHunter-Devourer','Mage-Fire','Shaman-Elemental','Warlock-Affliction','DeathKnight-Unholy','Mage-Frost','Druid-Guardian','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Vengeance','DeathKnight-Blood','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','Mage-Arcane','Shaman-Enhancement','Druid-Feral','Priest-Shadow','Druid-Restoration','Paladin-Protection','Hunter-Survival',}
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aabbigale:BAAANQADCgIIAgAAAA==.',
Ab='Abigt:BAAANQADCgIJAQAAAA==.',
Ad='Adalaidê:BAAANQAECgIIAgAAAA==.',
Ae='Aerynne:BAAANQADCgYIEAAAAA==.',
Ai='Airie:BAAANQAECgYIDwAAAA==.',
Ak='Akuso:BAAANQADCgIIAgAAAA==.',
Al='Alcohaulorc:BAAANQAECgQIBwAAAA==.Alert:BAAANQAECgEIAQAAAA==.Aloris:BAAANQAECgQICAAAAA==.Aloy:BAAANQAFFAIIBAAAAA==.Aluhx:BAAANQADCgYIDgABNQAECggIHwABAGogAA==.',
Am='Amednato:BAAANQAECgUIDwAAAA==.',
An='Anaeli:BAABNQAECoElAAICAAgK/RtuKACFAgACAAgK/RtuKACFAgAAAA==.Anastarian:BAAANQAECgEJAQAAAA==.Ancalagonn:BAABNQAECoERAAMDAAcKNgo7GgBoAQADAAcKNgo7GgBoAQAEAAMKVgPyFwBjAAAAAA==.Angita:BAAANQAECgEIAQAAAA==.Annaris:BAACNQAFFIENAAIFAAUKGCDxAgDrAQAFAAUKGCDxAgDrAQA1AAQKgSYAAwUACQolJSAEALEDAAUACQolJSAEALEDAAYACAruGKElANYBAAAA.Antipæn:BAECNQAFFIEFAAMHAAIKjiDgEADCAAAHAAIKjiDgEADCAAAIAAEK5ggRIABEAAA1AAQKgTEAAwcACQoBJhEEAM0DAAcACQoBJhEEAM0DAAgACQrNIasGAH4DAAAA.',
Ap='Apologia:BAAANQAECgcIDgAAAA==.',
Aq='Aquaphobic:BAAANQAECgMIAwABNQAFFAUICQACAB8NAA==.',
Ar='Arcanoth:BAAANQADCgIIAgAAAA==.Archaeolight:BAAANQADCgQIBAABNQAECgYIBgAJAAAAAA==.Ares:BAABNQAECoEbAAIKAAkKhCRWDwBvAwAKAAkKhCRWDwBvAwAAAA==.Armorgorden:BAABNQAECoEbAAILAAgKJyC4BQDUAgALAAgKJyC4BQDUAgAAAA==.Aroviaa:BAABNQAECoEbAAIMAAgKxxVRRwABAgAMAAgKxxVRRwABAgAAAA==.Arpmek:BAABNQAECoEXAAINAAgKcAwwJADqAQANAAgKcAwwJADqAQAAAA==.Artemîs:BAAANQADCgIIAgAAAA==.',
As='Asharienne:BAAANQAECgYIDwAAAA==.Ashlynne:BAAANQAECgYJCwAAAA==.',
Au='Audiobully:BAAANQADCgUIBgABNQAECgcIEwAJAAAAAA==.Auralynn:BAAANQAECgQJBAABNQAECgYJCwAJAAAAAA==.Auriella:BAAANQAECgQIBAAAAA==.Aurtt:BAAANQAECgcIEwAAAA==.',
['Aö']='Aöb:BAAANQADCgQIBgAAAA==.',
Ba='Bahahaknight:BAAANQAECgYIEAAAAA==.Bahree:BAAANQADCgIIAgAAAA==.Bakhar:BAAANQAECgUICQAAAA==.Balora:BAAANQADCgcJCwAAAA==.Barnette:BAABNQAECoEcAAIOAAgKYw4eAgADAgAOAAgKYw4eAgADAgAAAA==.Basyleus:BAAANQADCgEIAQAAAA==.',
Be='Belthos:BAAANQAECgcIDQAAAA==.Benihime:BAAANQAECgEIAQAAAA==.Berristan:BAABNQAECoEhAAIIAAkKtwx6RwAGAgAIAAkKtwx6RwAGAgAAAA==.',
Bi='Bigdawgsteve:BAAANQADCgIIAgAAAA==.Bigmarv:BAAANQAECgUIDAAAAA==.Bittytigs:BAABNQAECoEtAAMCAAkKbBzdHwC1AgACAAkKbBzdHwC1AgAPAAEKNgZ3DgEoAAAAAA==.',
Bl='Blestemat:BAAANQADCgYIBwAAAA==.Bluewitchpa:BAAANQADCgYIGAAAAA==.Blumangood:BAABNQAECoEYAAMPAAgKKxXwQwAZAgAPAAgKKxXwQwAZAgACAAIKLQLj5QA/AAAAAA==.',
Bo='Bollux:BAAANQAECgEIAgAAAA==.Bosc:BAAANQAECgUJCwAAAA==.Boudiicca:BAAANQADCgYIEAAAAA==.Boxmasterr:BAABNQAECoEbAAIQAAgKZRWyBABHAgAQAAgKZRWyBABHAgAAAA==.',
Br='Braagh:BAAANQABCggICwAAAA==.Brasmir:BAAANQAECgcIEQAAAA==.Briae:BAAANQADCgMIAwABNQAECggIJQACAP0bAA==.Brianzero:BAAANQABCgQJBgAAAA==.Brinotriage:BAAANQABCgIIAgAAAA==.',
Bu='Bubblemoth:BAAANQADCgMIBAABNQAECgUIDwAJAAAAAA==.Buik:BAAANQADCgYICQAAAA==.Bulge:BAAANQAECgYICwABNQAECgkJJgARAMwbAA==.Bulgogi:BAABNQAECoEmAAIRAAkKzBtzGAC+AgARAAkKzBtzGAC+AgAAAA==.',
['Bö']='Börk:BAAANQAECgEIAQAAAA==.',
Ca='Capy:BAAANQAECgIIAgABNQAECgkJLwASAMAfAA==.Cardran:BAAANQADCgIIAgABNQAECgUIDwAJAAAAAA==.Cayda:BAAANQADCgYJCQAAAA==.Caylara:BAAANQAECgEIAQAAAA==.Cayssaber:BAAANQADCggIDAAAAA==.',
Ce='Ceicilia:BAAANQADCgQIBAAAAA==.Celrythis:BAAANQAECgEIAQAAAA==.',
Ch='Chai:BAAANQAECgYICwAAAA==.Chaintrain:BAAANQAECgMIAwABNQAECgMJBgAJAAAAAA==.Chellyy:BAAANQADCggIIAABNQAECgEIAQAJAAAAAA==.',
Ci='Cider:BAAANQADCgYIBgAAAA==.Cinia:BAAANQAECgYIBgABNQAFFAIIBAAJAAAAAA==.',
Co='Coralbubbles:BAAANQAECgUICgAAAA==.Coralorchid:BAAANQAECgIIAwAAAA==.Coralrages:BAAANQAECgMIBgAAAA==.',
Cr='Cromenockle:BAAANQAECgcIEAAAAA==.',
Cu='Cupcâke:BAAANQADCgYIEwAAAA==.Curissan:BAAANQAECgEIAgAAAA==.',
Da='Dalgon:BAAANQAFFAMIBAABNQAECgkJJQAIAJocAA==.Dalir:BAAANQAECgEIAQAAAA==.Dalspin:BAAANQADCgYIDAABNQAECgkJJQAIAJocAA==.Dalthepal:BAABNQAECoElAAIIAAkKmhxdEQAeAwAIAAkKmhxdEQAeAwAAAA==.Damné:BAABNQAECoEZAAIRAAgKNxTnNAD2AQARAAgKNxTnNAD2AQAAAA==.Davidline:BAAANQAECgcIDQAAAA==.',
De='Deadish:BAAANQAECgYIEgAAAA==.Deathsaberss:BAABNQAECoEmAAMKAAkKPRY1SwBqAgAKAAkKPRY1SwBqAgALAAMKlAvJKACKAAAAAA==.Deathvex:BAAANQAFFAIIAgAAAA==.Decoz:BAAANQAECgMIAwAAAA==.Deight:BAAANQADCgIIAgAAAA==.Dejamoo:BAAANQADCgYIDgAAAA==.Dendahn:BAAANQAECgcIDQAAAA==.Destinee:BAAANQAECgQICwAAAA==.',
Di='Dianntha:BAAANQADCgUIBQAAAA==.Diladrin:BAABNQAECoEoAAITAAkKsBj3CAB8AgATAAkKsBj3CAB8AgAAAA==.Dinomight:BAAANQADCgQIBAAAAA==.',
Do='Doileag:BAAANQAECgIIAwAAAA==.Doomgrave:BAAANQADCgEIAQAAAA==.Dottmatrix:BAAANQAECgEIAQAAAA==.Doubledowns:BAAANQADCggIDwAAAA==.',
Dr='Dreadwing:BAAANQADCgYIEAAAAA==.Druromu:BAAANQAECgEIAQAAAA==.',
Du='Dufs:BAABNQAECoEeAAICAAkK4iAvEQATAwACAAkK4iAvEQATAwAAAA==.Dunkan:BAAANQADCgYICwAAAA==.Dustbunny:BAABNQAECoEZAAIMAAgK7hEsTQDpAQAMAAgK7hEsTQDpAQAAAA==.',
Dw='Dwagon:BAAANQAECgYIDQAAAA==.',
Dy='Dylsonlolqt:BAAANQADCgUICAAAAA==.',
['Dã']='Dãrling:BAAANQABCgEIAQAAAA==.',
['Dû']='Dûn:BAABNQAECoEgAAMUAAkKOB7iBgCUAgAUAAgK1B3iBgCUAgAVAAQKYxYlMwANAQAAAA==.Dûna:BAAANQAECggIEwABNQAECgkJIAAUADgeAA==.',
El='Elaatia:BAABNQAECoEbAAIHAAgKByMFIwAGAwAHAAgKByMFIwAGAwAAAA==.Elidria:BAAANQABCgIIAgABNQADCgYIBgAJAAAAAA==.Ellysprocket:BAAANQADCgUJCQAAAA==.Elrric:BAAANQAECgYICgAAAA==.Elyak:BAAANQADCgIIAgAAAA==.',
En='Envoy:BAAANQADCgcIEwAAAA==.',
Er='Erakron:BAAANQAECgUIDgAAAA==.Erine:BAAANQAECgIIAgAAAA==.Erouvi:BAAANQADCgIIAgABNQAECggIGwAMAMcVAA==.Eroviaa:BAAANQAECgMIAwABNQAECggIGwAMAMcVAA==.',
Ez='Ezothen:BAAANQAECgQIBQAAAA==.',
Fa='Facelessman:BAAANQABCggIGQAAAA==.Faedoria:BAAANQADCggIGQAAAA==.Faeryln:BAABNQAECoEdAAIMAAgKlwmDYwCPAQAMAAgKlwmDYwCPAQAAAA==.Fatalcheese:BAAANQABCgQIBAAAAA==.Faustus:BAAANQAECgcICQAAAA==.Favion:BAAANQADCgEIAQAAAA==.',
Fe='Felyyia:BAAANQAECgUIBQABNQAFFAUIDQAFABggAA==.Feyox:BAAANQADCggICAAAAA==.',
Fi='Fiddlestix:BAAANQAECgQIBAAAAA==.Firebrande:BAAANQAECgEIAQAAAA==.Fisticuffs:BAAANQADCgYIFgAAAA==.Fizcrankshot:BAABNQAECoEdAAIFAAgKoxNWUwAnAgAFAAgKoxNWUwAnAgAAAA==.',
Fl='Flamewhisker:BAAANQAECgEIAQAAAQ==.',
Fr='Fraublucher:BAAANQAECgYIEQAAAA==.Frewyn:BAAANQAECgEIAQAAAA==.Frostimoth:BAAANQAECgUIDwAAAA==.Frozty:BAAANQAECgEIAgAAAA==.',
Ga='Galandel:BAAANQADCgYIGAAAAA==.Galial:BAABNQAECoEmAAIWAAkKGhqeBACrAgAWAAkKGhqeBACrAgAAAA==.Gantar:BAAANQAECgEIAQABNQAECggIIAAXADQjAA==.Garradin:BAAANQADCgEIAQAAAA==.Garrunter:BAAANQADCggIHgAAAA==.Gaznol:BAAANQADCgQIBAABNQAECgUIDwAJAAAAAA==.',
Ge='Gelasera:BAAANQADCggIHAAAAA==.Gemitra:BAAANQADCgcIBwABNQAECgIIAwAJAAAAAA==.Geneth:BAAANQAECgUIBQAAAA==.George:BAABNQAECoEbAAIKAAcKKB1nXgArAgAKAAcKKB1nXgArAgAAAA==.',
Gh='Ghalta:BAAANQADCgIIAgABNQAECgcIEwAJAAAAAA==.Ghrol:BAAANQABCgYIBgABNQAECggIHgACAMIZAA==.',
Gl='Glaivethras:BAABNQAECoEdAAIWAAgKoh4kBAC9AgAWAAgKoh4kBAC9AgAAAA==.Glenfin:BAAANQADCgQIBgAAAA==.',
Gr='Greg:BAAANQADCgEIAQAAAA==.Gremlynn:BAAANQADCggICAAAAA==.Grimclaw:BAAANQAFFAQIBAAAAA==.Groot:BAAANQAECgQIBwABNQAECgUIDQAJAAAAAA==.',
Gu='Guthrek:BAAANQAECgMIAgAAAA==.',
Ha='Hamfist:BAAANQADCgIIAgABNQAECggJDAAJAAAAAA==.Hannebal:BAAANQAECgcIEAAAAA==.',
He='Healyclam:BAAANQADCgMIAwAAAA==.Heydaw:BAAANQADCggICAABNQAECggIFQAYAHAaAA==.Heynow:BAAANQADCggIGwAAAA==.',
Hi='Highmountain:BAAANQADCgYICwAAAA==.Hilimed:BAABNQAECoEdAAIZAAgKjAoAewCWAQAZAAgKjAoAewCWAQAAAA==.',
Ho='Hobs:BAAANQABCgMIAwAAAA==.Hoosier:BAAANQADCgUIBQAAAA==.Hoplite:BAAANQADCgIIAgAAAA==.',
Hu='Huasca:BAAANQADCgUIBQAAAA==.Huthuel:BAAANQABCggIFAAAAA==.',
Hy='Hydra:BAAANQADCgYIBgABNQAECgcIEAAJAAAAAA==.Hyve:BAAANQADCgcIEgABNQAECggIGwAHAP4XAA==.',
['Hà']='Hàney:BAEANQAECgQIBAAAAA==.',
['Hé']='Hélio:BAAANQADCgUIBQAAAA==.',
Ia='Ia:BAABNQAECoEYAAIYAAkKCRurGAB9AgAYAAkKCRurGAB9AgAAAA==.',
Ib='Ibesneakin:BAAANQADCgYIBgABNQAECggJDAAJAAAAAA==.',
Id='Idontsuck:BAAANQADCggICwAAAA==.',
Il='Ilieau:BAAANQAECgEIAQABNQAECgUIDgAJAAAAAA==.Illida:BAAANQADCgYIBgAAAA==.',
Im='Imamalelol:BAAANQAECgIIAgAAAA==.',
In='Inarrah:BAAANQADCgEIAQAAAA==.Intrepidhero:BAAANQADCgEIAQAAAA==.',
Ir='Irkenfox:BAEBNQAECoEfAAILAAkK+CGpAgBTAwALAAkK+CGpAgBTAwAAAA==.',
It='Ithran:BAAANQADCgUIBQAAAA==.',
Iw='Iwilltank:BAAANQADCgYICwAAAA==.',
Ix='Ixitt:BAABNQAECoEbAAIOAAgKxBWBAQBQAgAOAAgKxBWBAQBQAgAAAA==.',
Ja='Jama:BAAANQADCgYIBgAAAA==.Janderick:BAAANQAECgUIDQAAAA==.',
Je='Jellacee:BAAANQADCgYIDwAAAA==.',
Ji='Jimboberjim:BAABNQAECoEjAAIaAAkK0CIbAQB+AwAaAAkK0CIbAQB+AwAAAA==.Jiminie:BAAANQAECgcIEwAAAA==.',
Jo='Jolio:BAAANQAECgMJBgAAAA==.Joltraxi:BAAANQABCgMIAwABNQAECgMJBgAJAAAAAA==.Joshie:BAABNQAECoEgAAIXAAgKNCOqDgAVAwAXAAgKNCOqDgAVAwAAAA==.Joshy:BAAANQADCgcIBwABNQAECggIIAAXADQjAA==.',
Ju='Jujubeans:BAAANQAECgEIAQAAAA==.Juniornite:BAABNQAECoEaAAIbAAgKax2hUAC4AgAbAAgKax2hUAC4AgAAAA==.Justthetouch:BAAANQADCggICAAAAA==.',
Jy='Jygglypuff:BAAANQAECgEIAQAAAA==.',
Ka='Kadaan:BAAANQAECgQIBAAAAA==.Kagemaro:BAAANQAECgcIEwAAAA==.Kahgar:BAAANQAECgQIBgABNQAECgkJNwAIABMVAQ==.Kalimathath:BAAANQADCgYIDwAAAA==.Kalzod:BAABNQAECoEpAAIZAAkKESE7BwBzAwAZAAkKESE7BwBzAwAAAA==.Kataki:BAAANQAECgUIDAABNQAECgcIEwAJAAAAAA==.Katia:BAAANQAECgEIAQAAAA==.Kativeria:BAAANQADCggIHAAAAA==.Katjayna:BAAANQADCgUICgAAAA==.Kaysabr:BAAANQADCgQIBAAAAA==.Kayssaber:BAAANQAECgEIAQAAAA==.',
Ke='Kebab:BAAANQAECgQJBAAAAA==.Kelsifer:BAAANQAECgQICwABNQAECgcICQAJAAAAAA==.Kempra:BAAANQADCgcIBwAAAA==.Kemprei:BAAANQADCgUJBQAAAA==.Kendralust:BAAANQAECgcICAAAAA==.Kerfufle:BAAANQABCgIJAgAAAA==.',
Kh='Khaos:BAAANQABCgEIAQAAAA==.',
Ki='Killmora:BAAANQADCgYIGAAAAA==.Kippars:BAAANQADCggJFgAAAA==.',
Ko='Kodazoff:BAAANQAECgEIAgAAAA==.Kora:BAAANQABCgEIAgAAAA==.Korevash:BAABNQAECoEeAAMCAAkKXSIyBwBvAwACAAkKXSIyBwBvAwAcAAEKDBL/KABGAAAAAA==.',
Kr='Krezz:BAAANQAECgEIAQAAAA==.Krissylu:BAAANQAECgEIAQAAAA==.Krothix:BAAANQAECgYIEwAAAA==.Krudd:BAAANQAECgUIBQAAAA==.Krychilly:BAAANQADCgYIBgAAAA==.Kryrande:BAAANQADCgQJCwAAAA==.Kryshym:BAAANQAECgMIBQAAAA==.Krythrall:BAAANQADCgUIBQABNQAECgMIBQAJAAAAAA==.Kryvelen:BAAANQADCgUIBQAAAA==.Krëëp:BAAANQAECggICAAAAA==.',
Ks='Kspectactle:BAAANQADCgMIAwAAAA==.',
Ku='Kuilei:BAAANQADCgYJCwABNQAECgEIAQAJAAAAAA==.Kurorø:BAAANQAECgEIAQAAAA==.',
Ky='Kyrayna:BAAANQADCgUIBwAAAA==.',
La='Ladara:BAABNQAECoEcAAIQAAgKMBZuBABTAgAQAAgKMBZuBABTAgAAAA==.Laima:BAAANQADCgMIBAAAAA==.Lavitz:BAAANQAECgEIAQAAAA==.',
Le='Leheo:BAAANQADCgIIAgAAAA==.Lehua:BAAANQADCgIIAgAAAA==.Leilanii:BAAANQADCgYIDwAAAA==.Lemook:BAAANQAECgMIBAAAAA==.Leonìdas:BAAANQADCgYICgAAAA==.Leð:BAAANQAECggICAAAAA==.',
Li='Licker:BAAANQAECgUICQABNQAECgcIEAAJAAAAAA==.Lightbulb:BAAANQADCgYIDQAAAA==.Lightsorrow:BAAANQAECgIIAgABNQAECgcIGAAEADEWAA==.Lightstormer:BAAANQADCgYIGAAAAA==.Lilamae:BAAANQAECgEIAQAAAA==.Lilarielle:BAABNQAECoEaAAIdAAYKuwR4GwDeAAAdAAYKuwR4GwDeAAAAAA==.Lildookie:BAAANQADCggICwAAAA==.Liliel:BAAANQADCgMIAwABNQAECgUIDwAJAAAAAA==.Liliela:BAAANQAECgUIDwAAAA==.Lilyannah:BAAANQADCgEIAQAAAA==.Liodragon:BAAANQADCgUIBQABNQAECgcICgAJAAAAAA==.Liolock:BAAANQAECggIBwAAAA==.Lite:BAAANQAECgQIBAAAAA==.Liø:BAAANQAECgcICgAAAA==.',
Ll='Lluniez:BAAANQAECgUIDAAAAA==.',
Lo='Lockroknroll:BAAANQAECggJDAAAAA==.Losoli:BAABNQAECoEbAAIIAAgKTB5SIAC+AgAIAAgKTB5SIAC+AgAAAA==.Lotor:BAAANQADCgYIBgAAAA==.Lowchin:BAAANQAECgEIAQAAAA==.',
Lu='Lutherion:BAAANQAECgYIEgAAAA==.',
Ly='Lycemmas:BAAANQAECgYIEAAAAA==.',
['Lï']='Lïo:BAAANQADCgYIBwABNQAECgcICgAJAAAAAA==.',
Ma='Macoun:BAAANQAECgUJCwAAAA==.Magicshowers:BAABNQAECoEbAAIbAAgKLCKoMwAHAwAbAAgKLCKoMwAHAwAAAA==.Manseed:BAAANQABCgQJBAAAAA==.Maple:BAAANQAECgEIAQAAAA==.Martei:BAABNQAECoEeAAIdAAkKwByfBAD0AgAdAAkKwByfBAD0AgAAAA==.Maríneth:BAAANQAECgEIAQAAAA==.Mascara:BAAANQAECgYICwAAAA==.',
Mi='Midway:BAAANQAECgQIBgAAAA==.Mirokushan:BAAANQADCgYIEAABNQADCggIDAAJAAAAAA==.Missfire:BAAANQAECgEIAQAAAA==.Misticlady:BAAANQAECgQIBgAAAA==.Mistrariel:BAAANQADCgMIAwABNQAECggIFQAXAPsPAA==.Mizukì:BAAANQABCgQJBgAAAA==.',
Mo='Moluubar:BAAANQAECgcIDgAAAA==.Moradin:BAAANQADCgMJAwAAAA==.Mordemour:BAAANQAECgQIBQAAAA==.',
Mu='Mufler:BAAANQABCgQIBQAAAA==.Mushù:BAAANQAECgUICQABNQAECgcIDgAJAAAAAA==.',
My='Myfire:BAAANQADCgYIBgAAAA==.Myrrh:BAAANQAECgYIDwAAAA==.',
Na='Nalik:BAAANQAECgEIAQAAAA==.Nanou:BAAANQAECgIIAgAAAA==.Nardiaun:BAAANQADCgYIBgAAAA==.Naturebait:BAAANQADCgQIBAABNQAECggIGAAPACsVAA==.',
Ne='Nerzheul:BAAANQAECgQICgAAAA==.',
Ni='Nimravidae:BAAANQAECgYIEAAAAA==.Ninelives:BAAANQAECgQICQAAAA==.Nitecrawler:BAAANQADCgQIBAAAAA==.Niteeye:BAAANQABCgIIAgABNQAECggIGgAbAGsdAA==.Niteryu:BAAANQAECgEIAwABNQAECggIGgAbAGsdAA==.',
No='Nolokkotal:BAAANQAECgcIDQAAAA==.Nospitfisty:BAAANQADCgQIBAAAAA==.Noxolon:BAAANQAECgMIBgAAAA==.',
Nr='Nreaf:BAABNQAECoEdAAIHAAkKiRKUYQAdAgAHAAkKiRKUYQAdAgAAAA==.',
Oi='Oili:BAABNQAECoEjAAMSAAkKUBnzBACMAgASAAkKUBnzBACMAgAbAAQK1gujNgHjAAAAAA==.',
Ol='Olarrick:BAAANQADCgYICwABNQAECgcIGwAKACgdAA==.',
Oo='Oops:BAABNQAECoEmAAIXAAkKfCAVDgAbAwAXAAkKfCAVDgAbAwAAAA==.',
Or='Orcchopped:BAAANQADCgQIBAAAAA==.Ornstein:BAAANQADCggJAwAAAA==.',
Ot='Ottuk:BAABNQAECoElAAIRAAkKkx/eEgDtAgARAAkKkx/eEgDtAgAAAA==.',
Pa='Padpaw:BAAANQAECgUJCAAAAA==.Pakraxes:BAABNQAECoEZAAIDAAcKXBC3FgCcAQADAAcKXBC3FgCcAQAAAA==.Paksenarrion:BAAANQAECgYIEAAAAA==.Palehoof:BAAANQADCgUIDgAAAA==.Pandemônium:BAAANQADCgMIAwABNQAECgcIEQAJAAAAAA==.Pandemönium:BAAANQAECgcIEQAAAA==.Parts:BAAANQABCggIDQAAAA==.Patchington:BAAANQAECgEIAQAAAA==.Pañdemönium:BAAANQAECgQJCgABNQAECgcIEQAJAAAAAA==.',
Pe='Pepperrjakk:BAAANQADCgEIAQAAAA==.Perrylee:BAAANQAECgQIBwAAAA==.',
Ph='Philia:BAABNQAECoEXAAMKAAgKmRcrdQDnAQAKAAgK2RIrdQDnAQALAAMKwBw+IADnAAABNQAFFAIIBAAJAAAAAA==.',
Pi='Pixelme:BAAANQAFFAEIAwAAAA==.',
Pl='Pleggster:BAAANQAECgYIDAAAAA==.',
Po='Pochula:BAAANQAECgUICwAAAA==.',
Pr='Primo:BAABNQAECoE3AAIIAAkKExXvMQBiAgAIAAkKExXvMQBiAgAAAA==.Protricity:BAAANQAECgcICwAAAA==.',
Ps='Psalms:BAAANQAECgEIAQABNQAECgQIBwAJAAAAAA==.Psychoprowla:BAABNQAECoEbAAIeAAgKZQ0+IwDJAQAeAAgKZQ0+IwDJAQAAAA==.Psychozdrood:BAAANQAECgEIAQAAAA==.',
['Pæ']='Pæn:BAEANQAECgYIBwABNQAFFAIIBQAHAI4gAA==.',
Qu='Quantar:BAAANQADCgYIBgABNQAECgEIAQAJAAAAAA==.Quickstab:BAAANQAECgQICAAAAA==.',
Ra='Ragana:BAAANQAECgMIAwAAAA==.Rainger:BAAANQADCgMIAwAAAA==.Rallypaly:BAAANQADCgIIAgAAAA==.Ramthor:BAAANQAECgIIAgAAAA==.Rancooll:BAAANQADCgYIEwAAAA==.Rasniir:BAABNQAECoEcAAIfAAgKbxM4GwAKAgAfAAgKbxM4GwAKAgAAAA==.Rasputea:BAAANQABCgEIAQAAAA==.Ravenar:BAAANQAECgQJBAAAAA==.',
Re='Regna:BAABNQAECoEjAAMKAAkK+CXlEABlAwAKAAkKGyTlEABlAwABAAQKCibSCwCyAQAAAA==.Relkon:BAAANQADCgMIAwAAAA==.Remaked:BAACNQAFFIEPAAIUAAUKDhjVAQCVAQAUAAUKDhjVAQCVAQA1AAQKgTIAAhQACQpRIEYDADUDABQACQpRIEYDADUDAAAA.Requinix:BAABNQAECoEbAAIFAAgKPBDsVQAfAgAFAAgKPBDsVQAfAgAAAA==.Reynmaker:BAAANQADCgQIBAAAAA==.',
Rh='Rhowyn:BAAANQADCgQICAAAAA==.',
Ri='Riptidez:BAAANQADCgYIBgAAAA==.Ririko:BAAANQAECgYIEAAAAA==.Ritzo:BAAANQAECgYIEAAAAA==.',
Ro='Rocksanne:BAAANQADCggICQAAAA==.Rooguee:BAAANQAECgIIAwAAAA==.',
Ru='Rukkis:BAAANQAECgYIEgAAAA==.Rukâ:BAAANQADCgYIDQAAAA==.Rumi:BAABNQAECoEmAAIWAAkK6xsDBADDAgAWAAkK6xsDBADDAgAAAA==.Rumm:BAAANQADCgEIAQAAAA==.',
Ry='Ryeekan:BAAANQAECgUJCgAAAA==.Ryuma:BAAANQAECgYIDwAAAA==.Ryumar:BAAANQAECgMIAwAAAA==.',
Sa='Sabrosura:BAAANQAECgUIDQAAAA==.Saiyan:BAAANQADCgIIAgAAAA==.Salsinor:BAAANQADCgUIBQAAAA==.Sanosagara:BAAANQAECggIBgAAAA==.Sathari:BAAANQAECgYIEAAAAA==.',
Sc='Schaden:BAAANQAECgQIBwAAAA==.Scripter:BAAANQADCgUIBgAAAA==.',
Se='Seijo:BAAANQAECgEJAQAAAA==.Sekk:BAABNQAECoEbAAMHAAgK/hdgXgAnAgAHAAgKnhdgXgAnAgAgAAUKdxIcMgD4AAAAAA==.Selecta:BAAANQAECgEIAQAAAA==.Selexi:BAAANQADCggICAAAAA==.Selithira:BAAANQAECgUIDQAAAA==.Sera:BAAANQADCgYICgAAAA==.',
Sh='Shabagnarang:BAAANQAECgQIDAABNQAECgcIGwAcAIIbAA==.Shadeofdark:BAAANQADCggICAAAAA==.Shalasyr:BAAANQAECgEIAgAAAA==.Shaletaz:BAAANQABCgQIBgAAAA==.Shamwowee:BAAANQADCgYIGAAAAA==.Shamzee:BAABNQAECoEmAAICAAkK+hyBFwDnAgACAAkK+hyBFwDnAgAAAA==.Sheyy:BAAANQAECgEIAQAAAA==.Shiftybonez:BAAANQADCgQIBQAAAA==.Shintok:BAAANQAECgQICAAAAA==.Shuddarun:BAACNQAFFIEOAAIFAAYK1RmaAQAkAgAFAAYK1RmaAQAkAgA1AAQKgSYAAgUACQrbJLMFAJsDAAUACQrbJLMFAJsDAAAA.',
Si='Silverbakk:BAAANQABCgEIAQAAAA==.Simn:BAAANQAECgUJCgAAAA==.Sindraesong:BAAANQAECgUJCQAAAA==.',
Sk='Skithiryx:BAAANQAECgQIBAABNQAECgcIEwAJAAAAAA==.Skuldd:BAAANQABCgQICQAAAA==.',
Sl='Slayvylora:BAAANQADCgcJBwABNQAFFAIIAgAJAAAAAA==.',
Sm='Smarte:BAAANQADCgEIAQABNQAECgcIEAAJAAAAAA==.Smolderpally:BAAANQADCgYIBgAAAA==.',
Sn='Sneakymoth:BAAANQADCgUIBQABNQAECgUIDwAJAAAAAA==.Snookums:BAAANQAECgIIAgAAAA==.',
So='Soarin:BAAANQADCgQIBAAAAA==.',
Sp='Spicymaker:BAAANQAECggIEAAAAA==.',
St='Steelheart:BAAANQABCgQIBAAAAA==.Stop:BAAANQAECgMIAwAAAA==.Strifewood:BAAANQAECgUJBQAAAA==.Stumper:BAAANQAECgcIEwAAAA==.',
Su='Sux:BAAANQADCgMIAwAAAA==.',
Sy='Sybrina:BAAANQAECgUIEAAAAA==.Sylvia:BAAANQAECgcIEAAAAA==.Syngeance:BAAANQAECgIIAgAAAA==.Synèsterwolf:BAAANQAECggICwAAAA==.',
['Sí']='Síf:BAAANQAECgEIAQAAAA==.',
Ta='Tadeusz:BAAANQAECgUIBwAAAA==.Tamamò:BAAANQADCgYJCAAAAA==.Tanglefoot:BAAANQADCggIFAAAAA==.Tanleros:BAAANQAECgUICQAAAA==.Taquítos:BAAANQADCgIIAgAAAA==.',
Te='Telana:BAAANQADCgYIGAAAAA==.Tequitos:BAAANQAECgUIDwAAAA==.Tessla:BAAANQADCgYIDAAAAA==.',
Th='Theduk:BAAANQAECgcIDwAAAA==.Theduke:BAAANQADCgIIAwAAAA==.Theliria:BAAANQADCgYIBgAAAA==.Thorias:BAABNQAECoEZAAIbAAgKLRwaZQCEAgAbAAgKLRwaZQCEAgAAAA==.Thtime:BAABNQAECoEhAAIbAAkKLB0WLAAdAwAbAAkKLB0WLAAdAwAAAA==.',
To='Tomoko:BAAANQADCgYICQAAAA==.Torment:BAABNQAECoEbAAIXAAgKBBaOMAAPAgAXAAgKBBaOMAAPAgAAAA==.',
Tr='Tristén:BAAANQAECgUIDQAAAA==.Truvie:BAAANQADCgMIAwAAAA==.',
Tu='Tumbled:BAAANQAECgUIDwAAAA==.Tumbles:BAAANQADCgQIBQAAAA==.Tumni:BAAANQAECgIIAgAAAA==.',
['Tá']='Tángall:BAAANQABCgEIAQAAAA==.',
Ui='Ui:BAAANQADCgMIAwAAAA==.',
Ul='Ulnuk:BAABNQAECoEeAAICAAgKwhlDLgBoAgACAAgKwhlDLgBoAgAAAA==.Ulster:BAAANQADCgEIAQAAAA==.',
Un='Ungodly:BAABNQAECoEWAAIYAAkKzQmgNgCPAQAYAAkKzQmgNgCPAQAAAA==.Unholyshan:BAAANQADCggIDAAAAA==.Unidus:BAAANQABCgUICAAAAA==.',
Uu='Uutr:BAAANQABCgEIAQAAAA==.',
Uv='Uvvolx:BAAANQADCgQICAAAAA==.',
Va='Vadka:BAAANQAECgEIAQAAAA==.Vaeldrin:BAAANQAECgQIBQAAAA==.Vaha:BAAANQAECgEIAQAAAA==.Valkree:BAAANQAECgQIBQAAAA==.Valsavis:BAABNQAECoEbAAIWAAgKRB/XAwDLAgAWAAgKRB/XAwDLAgAAAA==.',
Ve='Veaolop:BAAANQABCggIEAAAAA==.Vellagosa:BAAANQAECgEIAQAAAA==.Vernice:BAAANQADCgYICwABNQAECgQIBQAJAAAAAA==.Verulan:BAAANQAECgEIAQAAAA==.Vexidari:BAAANQAECgQIBAABNQAFFAIIAgAJAAAAAA==.Vexomous:BAABNQAECoEeAAMhAAgKLByuAwCDAgAhAAgKLByuAwCDAgAGAAQK7ggFRwC/AAABNQAFFAIIAgAJAAAAAA==.',
Vi='Viiolet:BAAANQAECgYIBgAAAA==.',
Vo='Voidmayne:BAAANQAECgUIDgAAAA==.Vongogh:BAAANQADCgYICQAAAA==.Vonhelsing:BAAANQADCgEIAQAAAA==.',
Vy='Vynnara:BAAANQADCgEIAQAAAA==.Vyolent:BAAANQADCgYICwAAAA==.',
Wa='Warnox:BAAANQADCgcIBwAAAA==.',
We='Weiand:BAAANQAECgcIEAAAAA==.Wevark:BAAANQAECgUIDwAAAA==.',
Wh='Whatami:BAAANQAECgcIDgAAAA==.Wholemilk:BAAANQAECgEIAQAAAA==.',
Wi='Wilhellena:BAABNQAECoEaAAIMAAcKHg/3ZgCCAQAMAAcKHg/3ZgCCAQAAAA==.Wilhellfu:BAAANQADCgMIAwAAAA==.Winariel:BAAANQAECgIIAgABNQAECggIFQAXAPsPAA==.Witewalker:BAAANQADCgMIAwAAAA==.',
Wr='Writhesoul:BAAANQABCgIIAgABNQAECgYICQAJAAAAAA==.Wroughtsoul:BAAANQAECgYIBgAAAA==.Wrysoul:BAAANQAECgYICQAAAA==.',
Wy='Wynston:BAAANQADCgEIAQAAAA==.Wyrmheart:BAAANQADCgIIAwAAAA==.',
Xa='Xalatath:BAAANQADCgEIAQABNQAECgcIEQAJAAAAAA==.Xaldred:BAAANQAECgUIDgABNQAECggIGQARADcUAA==.Xandir:BAAANQAECgcIDwAAAA==.Xarhunt:BAAANQADCgcICgAAAA==.',
Xe='Xenzia:BAAANQADCgcICwAAAA==.Xeracil:BAAANQADCgQICgAAAA==.',
Xo='Xoric:BAABNQAECoEaAAIfAAgKvhBZHwDYAQAfAAgKvhBZHwDYAQAAAA==.',
Xy='Xyal:BAAANQAECgYIEQAAAA==.Xyp:BAAANQADCgYIBgABNQAECgEIAQAJAAAAAA==.',
Ya='Yamaya:BAAANQADCgMIBQAAAA==.',
Yi='Yiago:BAAANQAECgEIAQAAAA==.',
Yo='Youknow:BAAANQADCgcICwAAAA==.',
Za='Zaelia:BAAANQADCgEIAQAAAA==.Zary:BAAANQAECgIIAgAAAA==.Zaxhdk:BAEANQADCgMIAwABNQAECgcIEwAJAAAAAA==.Zaxhpal:BAEANQAECgcIEwAAAA==.',
Zi='Zid:BAAANQAECgMIAwAAAA==.Ziny:BAAANQADCgUIBQAAAA==.Ziparoo:BAAANQAECgYIDgAAAA==.',
Zr='Zraven:BAAANQADCgEIAQAAAA==.',
['În']='Îniquitous:BAAANQAECgUIDgAAAA==.',
['Ðê']='Ðêmønicßløøð:BAAANQAECgcICwABNQAECgcIDQAJAAAAAA==.',
['Üb']='Übernasus:BAAANQADCgQIBgAAAA==.',
['ßy']='ßyrøßløøð:BAAANQABCgIIAgAAAA==.',
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
