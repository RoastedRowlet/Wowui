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

local lookup = {'Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Fury','Evoker-Devastation','Evoker-Augmentation','Paladin-Retribution','Paladin-Holy','Unknown-Unknown','Warrior-Arms','Warrior-Protection','Priest-Holy','DemonHunter-Devourer','Druid-Balance','DeathKnight-Blood','Mage-Fire','Shaman-Enhancement','Warlock-Affliction','Hunter-Survival','DeathKnight-Unholy','Mage-Frost','Evoker-Preservation','Druid-Guardian','Monk-Brewmaster','Monk-Windwalker','Priest-Shadow','DemonHunter-Vengeance','Druid-Feral','DeathKnight-Frost','Warlock-Demonology','Mage-Arcane','Warlock-Destruction','Paladin-Protection','Druid-Restoration','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abigt:BAAANQADCgIIAQAAAA==.',
Ac='Acidsnow:BAAANQADCgIIAgAAAA==.',
Ad='Adalaidê:BAAANQAECgIIAgAAAA==.',
Ae='Aerynne:BAAANQADCgcIFgAAAA==.',
Ai='Airie:BAABNQAECoEZAAMBAAcK9w6AoAAIAQABAAYK9gqAoAAIAQACAAIKOwRl/QBYAAAAAA==.',
Ak='Akuso:BAAANQADCgIIAgAAAA==.',
Al='Alcohaulorc:BAAANQAECgQIBwAAAA==.Alert:BAAANQAECgEIAQAAAA==.Aloris:BAAANQAECgQICAAAAA==.Aloy:BAABNQAFFIEIAAMDAAMKBhWXEQAHAQADAAMKBhWXEQAHAQAEAAEK4wEZIwAzAAAAAA==.Aluhx:BAAANQAECgMIBgABNQAECggIJQAFABAhAA==.',
Am='Amednato:BAAANQAECgYIEAAAAA==.',
An='Anaeli:BAABNQAECoE1AAIBAAgKph1sKACgAgABAAgKph1sKACgAgAAAA==.Anastarian:BAAANQAECgEIAQAAAA==.Ancalagonn:BAABNQAECoETAAMGAAgKdQldGQCUAQAGAAgKdQldGQCUAQAHAAMKVgOlGwBhAAAAAA==.Angita:BAAANQAECgIIAwAAAA==.Anklin:BAAANQADCgIIAgAAAA==.Annaris:BAACNQAFFIERAAIDAAUKYiJwBADwAQADAAUKYiJwBADwAQA1AAQKgSkAAwMACQqgJb0EALQDAAMACQqgJb0EALQDAAQACAruGLQrAMoBAAAA.Antipæn:BAECNQAFFIEGAAMIAAIKjiD3FgC6AAAIAAIKjiD3FgC6AAAJAAEKdCPLHwBoAAA1AAQKgTQAAwgACQoBJoQGAL0DAAgACQoBJoQGAL0DAAkACQrNIakIAHcDAAAA.',
Ap='Apologia:BAABNQAECoEZAAIIAAgKISNjJAAaAwAIAAgKISNjJAAaAwAAAA==.',
Aq='Aquaphobic:BAAANQAECgMIBQABNQAFFAUICwABAB8NAA==.',
Ar='Arcanoth:BAAANQADCgIIAgAAAA==.Archaeolight:BAAANQADCgQIBAABNQAECgYICwAKAAAAAA==.Ares:BAABNQAECoEdAAILAAkKhCR2FQBaAwALAAkKhCR2FQBaAwAAAA==.Armorgorden:BAABNQAECoEjAAIMAAgK+yFmBQD+AgAMAAgK+yFmBQD+AgAAAA==.Aroviaa:BAABNQAECoEjAAINAAgKgBcJUQAGAgANAAgKgBcJUQAGAgAAAA==.Arpmek:BAABNQAECoEdAAIOAAgKEw+zJQD4AQAOAAgKEw+zJQD4AQAAAA==.Artemîs:BAAANQADCgIIAgAAAA==.',
As='Asharienne:BAABNQAECoEZAAIDAAgKpw4HbwAHAgADAAgKpw4HbwAHAgAAAA==.Ashlynne:BAAANQAECgYJCwAAAA==.',
Au='Audiobully:BAAANQAECgQIBAABNQAECggIHQAPAJ4VAA==.Auralynn:BAAANQAECgQJBAABNQAECgYJCwAKAAAAAA==.Auriella:BAAANQAECgcIDAAAAA==.Aurtt:BAABNQAECoEgAAIQAAgK/xLlQwDMAQAQAAgK/xLlQwDMAQAAAA==.',
['Aö']='Aöb:BAAANQADCgQIBgAAAA==.',
Ba='Bahahaknight:BAABNQAECoEbAAIQAAcKnhR3SQCyAQAQAAcKnhR3SQCyAQAAAA==.Bahree:BAAANQADCgIIAgAAAA==.Bakhar:BAAANQAECgYIDwAAAA==.Balora:BAAANQADCgcIEAAAAA==.Barnette:BAABNQAECoElAAIRAAkKNBKnAQBbAgARAAkKNBKnAQBbAgAAAA==.Basyleus:BAAANQADCgEIAQAAAA==.',
Be='Belthos:BAAANQAECgcIDQAAAA==.Benihime:BAAANQAECgEIAQAAAA==.Berristan:BAABNQAECoEnAAIJAAkKjw2JUgADAgAJAAkKjw2JUgADAgAAAA==.Bestwingman:BAAANQADCgEIAQAAAA==.',
Bi='Bigdawgsteve:BAAANQADCgIIAgAAAA==.Bigmarv:BAAANQAECgUIDAAAAA==.Bittytigs:BAACNQAFFIEHAAIBAAMKwhcYEwDrAAABAAMKwhcYEwDrAAA1AAQKgTQAAwEACQqCIGgQACsDAAEACQqCIGgQACsDAAIAAQo2Bu8rAScAAAAA.',
Bl='Blestemat:BAAANQADCgYIBwAAAA==.Bluewitchpa:BAAANQADCgYIHgAAAA==.Blumangood:BAABNQAECoEgAAQCAAgKLRZ2SAAoAgACAAgKLRZ2SAAoAgABAAIKLQJt/AA/AAASAAEKQgbHMAA1AAAAAA==.',
Bo='Bollux:BAAANQAECgEIAgAAAA==.Bosc:BAAANQAECgUJCwAAAA==.Boudiicca:BAAANQADCgcIFgAAAA==.Boxmasterr:BAABNQAECoEjAAITAAgKIxcrBQBRAgATAAgKIxcrBQBRAgAAAA==.',
Br='Braagh:BAAANQABCggICwAAAA==.Brasmir:BAABNQAECoEXAAIUAAgKPhyiAwCmAgAUAAgKPhyiAwCmAgAAAA==.Briae:BAAANQADCgMIAwABNQAECggINQABAKYdAA==.Brianzero:BAAANQABCgQJBgAAAA==.Brino:BAAANQABCgQIBAAAAA==.Brinotriage:BAAANQABCgIIAgAAAA==.',
Bu='Bubblemoth:BAAANQADCgMIBAABNQAECgUIDwAKAAAAAA==.Buik:BAAANQADCgYICQAAAA==.Bulge:BAAANQAECggIDgABNQAFFAMIBgAVAFcLAA==.Bulgogi:BAACNQAFFIEGAAIVAAMKVwscEADWAAAVAAMKVwscEADWAAA1AAQKgSkAAhUACQrzHgUbAM4CABUACQrzHgUbAM4CAAAA.',
['Bö']='Börk:BAAANQAECgIIAwAAAA==.',
Ca='Capy:BAAANQAECgIIAgABNQAFFAMIBQAWAOQUAA==.Cardran:BAAANQADCgIIAgABNQAECgYIEAAKAAAAAA==.Cayda:BAAANQADCgYJCQAAAA==.Caylara:BAAANQAECgIIAwAAAA==.Cayssaber:BAAANQADCggIDAAAAA==.',
Ce='Ceicilia:BAAANQADCgQIBAAAAA==.Celrythis:BAAANQAECgEIAQAAAA==.',
Ch='Chai:BAAANQAECgYICwAAAA==.Chaintrain:BAAANQAECgMIAwABNQAECgQIBwAKAAAAAA==.Chellyy:BAAANQAECgIIAgABNQAECgIIAwAKAAAAAA==.Chibisend:BAAANQADCgMIAwAAAA==.Chámeleon:BAAANQADCgEIAQAAAA==.',
Ci='Cider:BAAANQAECgIIAgAAAA==.Cinia:BAAANQAECgYICgABNQAFFAQICAAKAAAAAA==.',
Co='Coralbubbles:BAAANQAECggIEgAAAA==.Coralorchid:BAAANQAECgUIDwAAAA==.Coralrages:BAAANQAECgMIBgAAAA==.',
Cr='Cromenockle:BAAANQAFFAEIAQAAAA==.Crtitman:BAAANQADCgIIAgABNQAECgQIBwAKAAAAAA==.',
Cu='Cupcâke:BAAANQAECgQIBAAAAA==.Curissan:BAAANQAECgUIBwAAAA==.',
Da='Dalgon:BAABNQAFFIEIAAIXAAQK6wSFDQD9AAAXAAQK6wSFDQD9AAABNQAFFAUIBwAJAFMQAA==.Dalir:BAAANQAECgQIBQAAAA==.Dalspin:BAAANQADCgYIDAABNQAFFAUIBwAJAFMQAA==.Dalthepal:BAACNQAFFIEHAAIJAAUKUxDpCgCLAQAJAAUKUxDpCgCLAQA1AAQKgSoAAgkACQqaHJwVABcDAAkACQqaHJwVABcDAAAA.Damné:BAABNQAECoEgAAIVAAgKoRa/PAAHAgAVAAgKoRa/PAAHAgAAAA==.Davidline:BAAANQAECggIEgAAAA==.',
De='Deadish:BAABNQAECoEfAAMQAAkKYB2iFADyAgAQAAgKSyCiFADyAgAVAAEKDQa/7AARAAAAAA==.Deathsaberss:BAABNQAECoEsAAMLAAkKZRclUQB7AgALAAkKZRclUQB7AgAMAAMKlAsRLwCJAAAAAA==.Deathvex:BAAANQAFFAIIBAAAAA==.Decoz:BAAANQAECgUIBQAAAA==.Deight:BAAANQADCgIIAgAAAA==.Dejamoo:BAAANQADCgYIDgAAAA==.Dendahn:BAAANQAECgcIDQAAAA==.Destinee:BAAANQAECgQICwAAAA==.',
Di='Dianntha:BAAANQADCgUICAAAAA==.Diladrin:BAABNQAECoExAAIYAAkKMxmvCwByAgAYAAkKMxmvCwByAgAAAA==.Dinomight:BAAANQADCgQIBAAAAA==.',
Do='Doileag:BAAANQAECgMIBQAAAA==.Doomgrave:BAAANQADCgEIAQAAAA==.Dora:BAAANQADCgYIBgABNQAECgUIDAAKAAAAAA==.Dottmatrix:BAAANQAECgIIAwAAAA==.Doubledowns:BAAANQADCggIDwAAAA==.',
Dr='Dreadwing:BAAANQADCgcIFgAAAA==.Druromu:BAAANQAECgIIAwAAAA==.',
Du='Dufs:BAACNQAFFIEIAAIBAAMKKybeDABTAQABAAMKKybeDABTAQA1AAQKgSEAAgEACQrxINIVAAcDAAEACQrxINIVAAcDAAAA.Dunkan:BAAANQADCgYICwAAAA==.Dustbunny:BAABNQAECoEhAAINAAgKmRXySAAkAgANAAgKmRXySAAkAgAAAA==.',
Dw='Dwagon:BAAANQAECgYIDgAAAA==.',
Dy='Dylsonlolqt:BAAANQADCgUICAAAAA==.',
['Dã']='Dãrling:BAAANQABCgEIAQAAAA==.',
['Dû']='Dûn:BAABNQAECoEiAAMZAAkKhB6MCACDAgAZAAgK1B2MCACDAgAaAAUKLRiXLwBlAQAAAA==.Dûna:BAABNQAECoEcAAIbAAkKmhnWEQDCAgAbAAkKmhnWEQDCAgABNQAECgkJIgAZAIQeAA==.',
El='Elaatia:BAABNQAECoEjAAIIAAgK4yPAJQAUAwAIAAgK4yPAJQAUAwAAAA==.Elidria:BAAANQABCgIIAgABNQADCgYIBgAKAAAAAA==.Ellysprocket:BAAANQADCgUICQAAAA==.Elrric:BAAANQAECgYICgAAAA==.Elyak:BAAANQADCgIIAgAAAA==.',
En='Envoy:BAAANQADCgcIEwAAAA==.',
Er='Erakron:BAABNQAECoEbAAMCAAYKkhWAfAB+AQACAAYKkhWAfAB+AQABAAQKAxJnqwDsAAAAAA==.Erine:BAAANQAECgIIAgAAAA==.Erouvi:BAAANQADCgIIAgABNQAECggIIwANAIAXAA==.Eroviaa:BAAANQAECgMIAwABNQAECggIIwANAIAXAA==.',
Ez='Ezothen:BAAANQAECgQICQAAAA==.',
Fa='Facelessman:BAAANQABCggIGgAAAA==.Faedoria:BAAANQAECgEIAQAAAA==.Faeryln:BAABNQAECoEhAAINAAgKngkSdQCEAQANAAgKngkSdQCEAQAAAA==.Fatalcheese:BAAANQABCgQIBAAAAA==.Faustus:BAAANQAECgcIDgAAAA==.Favion:BAAANQADCgEIAQAAAA==.',
Fe='Felyyia:BAAANQAECgYICgABNQAFFAUIEQADAGIiAA==.Feyox:BAAANQADCggICAAAAA==.',
Fi='Fiddlestix:BAAANQAECgQIBAAAAA==.Firebrande:BAAANQAECgIIAwAAAA==.Fisticuffs:BAAANQADCgYIHAAAAA==.Fizcrankshot:BAABNQAECoEfAAIDAAgKaxTlYQAoAgADAAgKaxTlYQAoAgAAAA==.',
Fl='Flamewhisker:BAAANQAECgIIAwAAAQ==.Flamez:BAAANQADCgcIBwAAAA==.',
Fr='Fraublucher:BAABNQAECoEaAAINAAcKJQZeiQBAAQANAAcKJQZeiQBAAQAAAA==.Frewyn:BAAANQAECgQIBQAAAA==.Frostimoth:BAAANQAECgUIDwAAAA==.Frozty:BAAANQAECgQIBgAAAA==.',
Ga='Galandel:BAAANQADCgYIGQAAAA==.Galial:BAABNQAECoEpAAIcAAkKLRuSBQCqAgAcAAkKLRuSBQCqAgAAAA==.Gantar:BAAANQAECgEIAQABNQAECgkJIgAQAL8jAA==.Garradin:BAAANQADCgEIAQAAAA==.Garrunter:BAAANQADCggIJAAAAA==.Gaznol:BAAANQADCgQIBAABNQAECgYIEAAKAAAAAA==.',
Ge='Gelasera:BAAANQAECgIIAgAAAA==.Gemitra:BAAANQADCgcIBwABNQAECgUIDwAKAAAAAA==.Geneth:BAAANQAECgUIBQAAAA==.George:BAABNQAECoEgAAILAAcK6x2kagAxAgALAAcK6x2kagAxAgAAAA==.',
Gh='Ghalta:BAAANQADCgIIAgABNQAECggIGwAOANsYAA==.Ghrol:BAAANQABCgYIBgABNQAECggIJgABAIkaAA==.',
Gl='Glaivethras:BAABNQAECoEeAAIcAAgKoh6JBQCrAgAcAAgKoh6JBQCrAgAAAA==.Glenfin:BAAANQADCgQIBgAAAA==.',
Gr='Greg:BAAANQADCgQIBAABNQADCgUIDgAKAAAAAA==.Gremlynn:BAAANQADCggICAAAAA==.Grimclaw:BAABNQAECoEcAAMdAAkKICPXDQADAgAPAAcK4SD7JgB7AgAdAAUKASTXDQADAgAAAA==.Groot:BAAANQAECgQIDQABNQAECgYIEwAKAAAAAA==.',
Gu='Guthrek:BAAANQAECgYIBgAAAA==.',
Ha='Hamfist:BAAANQADCgIIAgABNQAECggJDAAKAAAAAA==.Hannebal:BAAANQAECgcIEAAAAA==.',
He='Healyclam:BAAANQADCgMIAwAAAA==.Heydaw:BAAANQADCggICAABNQAECggIFgAeAHAaAA==.Heynow:BAAANQADCggIGwAAAA==.',
Hi='Highmountain:BAAANQADCgYICwAAAA==.Hilimed:BAABNQAECoEjAAIfAAgK+AqCiQCgAQAfAAgK+AqCiQCgAQAAAA==.',
Ho='Hobs:BAAANQABCgMIAwAAAA==.Holyßloodelf:BAAANQAECgUIBgABNQAECgcIFAALACUVAA==.Hoosier:BAAANQADCgUIBQAAAA==.Hoplite:BAAANQAECgMIAwAAAA==.',
Hu='Huasca:BAAANQADCgUIBQAAAA==.Huthuel:BAAANQABCggIFAAAAA==.',
Hy='Hydra:BAAANQADCgYIBgABNQAECggIGgAgACIQAA==.Hyve:BAAANQADCgcIGQABNQAECggIIwAIAEwYAA==.',
['Hà']='Hàney:BAEANQAECgQIBAAAAA==.',
['Hé']='Hélio:BAAANQADCgUIBQAAAA==.',
Ia='Ia:BAABNQAECoEcAAIeAAkKSBw2GACjAgAeAAkKSBw2GACjAgAAAA==.',
Ib='Ibesneakin:BAAANQADCggIDgABNQAECggJDAAKAAAAAA==.',
Id='Idontsuck:BAAANQADCggICwAAAA==.',
Il='Ileynha:BAAANQABCgIIAgAAAA==.Ilieau:BAAANQAECgQIBQABNQAECgYIBwAKAAAAAA==.Illida:BAAANQADCgYIBgAAAA==.',
Im='Imamalelol:BAAANQAECgUIBwAAAA==.',
In='Inarrah:BAAANQADCgEIAQAAAA==.Intrepidhero:BAAANQADCgEIAQAAAA==.',
Ir='Irkenfox:BAECNQAFFIEIAAIMAAMKExHWAwDEAAAMAAMKExHWAwDEAAA1AAQKgSIAAgwACQrpItwCAGUDAAwACQrpItwCAGUDAAAA.',
It='Ithran:BAAANQADCgUIBQAAAA==.',
Iw='Iwilltank:BAAANQADCgYICwAAAA==.',
Ix='Ixitt:BAABNQAECoEfAAIRAAgKWBfYAQBDAgARAAgKWBfYAQBDAgAAAA==.',
Ja='Jama:BAAANQADCgYIBgAAAA==.Janderick:BAAANQAECgUIDQAAAA==.Jaromer:BAAANQADCgQIBAAAAA==.',
Je='Jellacee:BAAANQADCgcIEgAAAA==.',
Ji='Jimboberjim:BAACNQAFFIEIAAIhAAMK5heoAQAOAQAhAAMK5heoAQAOAQA1AAQKgSYAAiEACQrvIkYBAHkDACEACQrvIkYBAHkDAAAA.Jiminie:BAABNQAECoEeAAIMAAgK6RNSEgDTAQAMAAgK6RNSEgDTAQAAAA==.',
Jo='Jolio:BAAANQAECgQIBwAAAA==.Joltraxi:BAAANQABCgMIAwABNQAECgQIBwAKAAAAAA==.Joshie:BAABNQAECoEiAAIQAAkKvyNGBwB5AwAQAAkKvyNGBwB5AwAAAA==.Joshy:BAAANQADCgcIBwABNQAECgkJIgAQAL8jAA==.',
Ju='Jujubeans:BAAANQAECgEIAQAAAA==.Juniornite:BAABNQAECoEiAAIgAAgKgiDBRgDnAgAgAAgKgiDBRgDnAgAAAA==.Justthetouch:BAAANQADCggICAAAAA==.',
Jy='Jygglypuff:BAAANQAECgEIAQAAAA==.',
Ka='Kadaan:BAAANQAECgQIBAAAAA==.Kagemaro:BAABNQAECoEbAAMOAAgK2xjbHABQAgAOAAgKrRjbHABQAgAcAAUKGBSlFQAfAQAAAA==.Kahgar:BAAANQAECgUICwABNQAECgkJQgAJAMMVAQ==.Kalimathath:BAAANQADCgYIDwAAAA==.Kalzod:BAABNQAECoEvAAIfAAkK9SOKBAClAwAfAAkK9SOKBAClAwAAAA==.Kataki:BAAANQAECgUIEQABNQAECggIGwAOANsYAA==.Katia:BAAANQAECgIIAwAAAA==.Kativeria:BAAANQAECgIIAgAAAA==.Katjayna:BAAANQADCgUICgAAAA==.Kaysabr:BAAANQADCgQIBAAAAA==.Kayssaber:BAAANQAECgUICQAAAA==.',
Ke='Kebab:BAAANQAECgQJBAAAAA==.Kelsifer:BAAANQAECgQICwABNQAECgcIDgAKAAAAAA==.Kempra:BAAANQADCgcIBwAAAA==.Kemprei:BAAANQADCgUIBQAAAA==.Kendralust:BAAANQAECgcICAAAAA==.Kerfufle:BAAANQABCgIJAgAAAA==.',
Kh='Khaos:BAAANQABCgEIAQAAAA==.',
Ki='Killmora:BAAANQADCgYIHgAAAA==.Kippars:BAAANQADCggJFgAAAA==.',
Ko='Kodazoff:BAAANQAECgcICQAAAA==.Kora:BAAANQABCgEIAgAAAA==.Korevash:BAABNQAECoEnAAMBAAkKtySGAgCyAwABAAkKtySGAgCyAwASAAEKDBLALQBFAAAAAA==.',
Kr='Krezz:BAAANQAECgEIAQAAAA==.Krissylu:BAAANQAECgQIBQAAAA==.Krothix:BAABNQAECoEfAAICAAgKwQZ3fAB+AQACAAgKwQZ3fAB+AQAAAA==.Krudd:BAAANQAECgUIBQAAAA==.Krychilly:BAAANQADCgYICwAAAA==.Kryrande:BAAANQADCgQJCwAAAA==.Kryshym:BAAANQAECgQICQAAAA==.Krythrall:BAAANQADCgUIBQABNQAECgQICQAKAAAAAA==.Kryvelen:BAAANQADCgUICgAAAA==.Krëëp:BAAANQAECggICAAAAA==.',
Ks='Kspectactle:BAAANQADCgMIAwAAAA==.',
Ku='Kuilei:BAAANQADCgYJCwABNQAECgIIAwAKAAAAAA==.Kurorø:BAAANQAECgIIAwAAAA==.',
Ky='Kyrayna:BAAANQADCgUIDAAAAA==.',
La='Ladara:BAABNQAECoEjAAITAAgKKRcHBQBXAgATAAgKKRcHBQBXAgAAAA==.Laima:BAAANQADCgMIBAAAAA==.Lavitz:BAAANQAECgEIAQAAAA==.',
Le='Leheo:BAAANQADCgIIAgAAAA==.Lehua:BAAANQADCgIIAgAAAA==.Leilanii:BAAANQADCgYIEAAAAA==.Lemook:BAAANQAECgYICgAAAA==.Leonìdas:BAAANQADCgYICgAAAA==.Leð:BAAANQAECggICAAAAA==.',
Li='Licker:BAAANQAECgUICQABNQAFFAEIAQAKAAAAAA==.Lightbulb:BAAANQADCgYIDQAAAA==.Lightsorrow:BAAANQAECgIIAgABNQAECggIHAAHAKkUAA==.Lightstormer:BAAANQADCgYIHgAAAA==.Lilamae:BAAANQAECgQIBQAAAA==.Lilarielle:BAABNQAECoEgAAIdAAYKVwXJHwDlAAAdAAYKVwXJHwDlAAAAAA==.Lildookie:BAAANQAECgQIBAAAAA==.Lilface:BAAANQAECgIIAgAAAA==.Liliel:BAAANQADCgMIAwABNQAECgYIEAAKAAAAAA==.Liliela:BAAANQAECgYIEAAAAA==.Lilyannah:BAAANQADCgEIAQAAAA==.Liodragon:BAAANQADCgUIBQABNQAECgcICgAKAAAAAA==.Liolock:BAAANQAECggIBwAAAA==.Lite:BAAANQAECgQIBAAAAA==.Liø:BAAANQAECgcICgAAAA==.',
Ll='Lluniez:BAAANQAECgYIDQAAAA==.',
Lo='Lockroknroll:BAAANQAECggJDAAAAA==.Losoli:BAABNQAECoEiAAIJAAgKjx6mJQC7AgAJAAgKjx6mJQC7AgAAAA==.Lotor:BAAANQADCgYIBgAAAA==.Lowchin:BAAANQAECgEIAQAAAA==.',
Lu='Lutherion:BAABNQAECoEbAAIMAAgKhh19CAChAgAMAAgKhh19CAChAgAAAA==.',
Ly='Lycemmas:BAABNQAECoEaAAIBAAgKIhr+OABTAgABAAgKIhr+OABTAgAAAA==.',
['Lï']='Lïo:BAAANQADCgYIBwABNQAECgcICgAKAAAAAA==.',
Ma='Macoun:BAAANQAECgUJCwAAAA==.Magicshowers:BAABNQAECoEjAAIgAAgK7CJOMQAdAwAgAAgK7CJOMQAdAwAAAA==.Majiique:BAAANQABCggIGAAAAA==.Manseed:BAAANQABCgQJBAAAAA==.Maple:BAAANQAECgIIAgAAAA==.Martei:BAACNQAFFIEHAAIdAAMKjRLTAQD7AAAdAAMKjRLTAQD7AAA1AAQKgSEAAh0ACQrxHNAFAO8CAB0ACQrxHNAFAO8CAAAA.Maríneth:BAAANQAECgIIAwAAAA==.Mascara:BAAANQAECgYICwAAAA==.',
Mi='Midway:BAAANQAECgQIBgAAAA==.Minizee:BAAANQADCgYIEAAAAA==.Mirokushan:BAAANQADCgcIFgABNQADCggIDAAKAAAAAA==.Missfire:BAAANQAECgIIAwAAAA==.Misticlady:BAAANQAECgQIBgAAAA==.Mistrariel:BAAANQADCgMIAwABNQAECggIGgAQADoRAA==.Mizukì:BAAANQABCgQIBgAAAA==.',
Mo='Moluubar:BAAANQAECgcIEAAAAA==.Moradin:BAAANQADCgMJAwAAAA==.Mordemour:BAAANQAECgQIBwAAAA==.',
Mu='Mufler:BAAANQABCgQIBQAAAA==.Mungo:BAAANQAECgUIBQAAAA==.Mushù:BAAANQAECgUICgABNQAECggIFQAfAF0WAA==.',
My='Myfire:BAAANQADCgYIBgAAAA==.Myrrh:BAAANQAECgYIDwAAAA==.',
Na='Nalik:BAAANQAECgQIBQAAAA==.Nanou:BAAANQAECgIIAgAAAA==.Nardiaun:BAAANQADCgYIBgAAAA==.Naturebait:BAAANQADCgQIBAABNQAECggIIAACAC0WAA==.',
Ne='Nerzheul:BAAANQAECgQICgAAAA==.',
Ni='Nimravidae:BAABNQAECoEbAAIJAAcKZhhtVQD5AQAJAAcKZhhtVQD5AQAAAA==.Ninelives:BAAANQAECgQIDQAAAA==.Nitecrawler:BAAANQADCgQIBAAAAA==.Niteeye:BAAANQABCgIIAgABNQAECggIIgAgAIIgAA==.Niteryu:BAAANQAECgEIAwABNQAECggIIgAgAIIgAA==.',
No='Nolokkotal:BAABNQAECoEUAAILAAcKJRUhiQDfAQALAAcKJRUhiQDfAQAAAA==.Nospitfisty:BAAANQADCgQIBAAAAA==.Noxolon:BAAANQAECgUICwAAAA==.',
Nr='Nreaf:BAABNQAECoEgAAIIAAkKDhP6dgAPAgAIAAkKDhP6dgAPAgAAAA==.',
Oi='Oili:BAABNQAECoEmAAMWAAkK6xlJBgB3AgAWAAkK6xlJBgB3AgAgAAQK1guoVQHeAAAAAA==.',
Ol='Olarrick:BAAANQADCgYICwABNQAECgcIIAALAOsdAA==.',
Oo='Oops:BAACNQAFFIEFAAIQAAIK6B+8FwCzAAAQAAIK6B+8FwCzAAA1AAQKgSkAAhAACQrTIHMQABYDABAACQrTIHMQABYDAAAA.',
Or='Orcchopped:BAAANQADCgQIBAAAAA==.Ornstein:BAAANQAECgQIBAAAAA==.',
Ot='Ottuk:BAABNQAECoEoAAIVAAkKJyC+GQDYAgAVAAkKJyC+GQDYAgAAAA==.',
Pa='Padpaw:BAAANQAECgUJCAAAAA==.Pakraxes:BAABNQAECoEhAAIGAAgKnxDuFADeAQAGAAgKnxDuFADeAQAAAA==.Paksenarrion:BAABNQAECoEbAAIiAAcK2Q7kKwBSAQAiAAcK2Q7kKwBSAQAAAA==.Palehoof:BAAANQADCgUIDgAAAA==.Pandemônium:BAAANQADCgMIAwABNQAECggIGQAIAMcaAA==.Pandemönium:BAABNQAECoEZAAMIAAgKxxphYQBJAgAIAAgKJBlhYQBJAgAiAAIKzRzCSACfAAAAAA==.Parts:BAAANQABCggIDQAAAA==.Patchington:BAAANQAECgIIAwAAAA==.Pañdemönium:BAAANQAECgQJCgABNQAECggIGQAIAMcaAA==.',
Pe='Pepperrjakk:BAAANQADCgEIAQAAAA==.Perrylee:BAAANQAECgQIBwAAAA==.',
Ph='Philia:BAABNQAECoEXAAMLAAgKmRf3hQDoAQALAAgK2RL3hQDoAQAMAAMKwBwIJgDhAAABNQAFFAMICAADAAYVAA==.',
Pi='Pixelme:BAAANQAFFAEIAwAAAA==.',
Pl='Pleggster:BAAANQAECgYIDAAAAA==.',
Po='Pochula:BAAANQAECgUICwAAAA==.',
Pr='Primo:BAABNQAECoFCAAIJAAkKwxWBNwBqAgAJAAkKwxWBNwBqAgAAAA==.Protricity:BAAANQAECgcIEgAAAA==.',
Ps='Psalms:BAAANQAECgEIAgABNQAECgQIBwAKAAAAAA==.Psychoprowla:BAABNQAECoEjAAIbAAgKdw/mJQDXAQAbAAgKdw/mJQDXAQAAAA==.Psychozdrood:BAAANQAECgEIAQAAAA==.',
['Pä']='Pändemönium:BAAANQAECgQIBAABNQAECggIGQAIAMcaAA==.',
['Pæ']='Pæn:BAEANQAECgYIBwABNQAFFAIIBgAIAI4gAA==.',
Qu='Quantar:BAAANQADCgYIBgABNQAECgIIAwAKAAAAAA==.Quickstab:BAAANQAECgQICAAAAA==.',
Ra='Ragana:BAAANQAECgUICAAAAA==.Rainger:BAAANQADCgMIAwAAAA==.Rallypaly:BAAANQADCgIIAgAAAA==.Ramthor:BAAANQAECgMIAwAAAA==.Rancooll:BAAANQADCgYIGQAAAA==.Rasniir:BAABNQAECoEiAAIjAAgK1RUqGwA0AgAjAAgK1RUqGwA0AgAAAA==.Rasputea:BAAANQABCgEIAQAAAA==.Ravenar:BAAANQAECgQJBAAAAA==.',
Re='Regna:BAABNQAECoEmAAMLAAkK/CWRFQBaAwALAAkKICSRFQBaAwAFAAQKCiYdDgCqAQAAAA==.Relkon:BAAANQADCgMIAwAAAA==.Remaked:BAACNQAFFIEVAAIZAAYKhRhoAQDrAQAZAAYKhRhoAQDrAQA1AAQKgTUAAhkACQqpINgDADEDABkACQqpINgDADEDAAAA.Requinix:BAABNQAECoEjAAIDAAgKlxL0XQAyAgADAAgKlxL0XQAyAgAAAA==.Reynmaker:BAAANQADCgQIBAAAAA==.',
Rh='Rhowyn:BAAANQADCgQICAAAAA==.',
Ri='Riptidez:BAAANQADCgYIBgAAAA==.Ririko:BAABNQAECoEbAAINAAcKwAY8jgAwAQANAAcKwAY8jgAwAQAAAA==.Ritzo:BAABNQAECoEbAAIFAAcKsxjRCQAOAgAFAAcKsxjRCQAOAgAAAA==.',
Ro='Rocksanne:BAAANQADCggIDAAAAA==.Rooguee:BAAANQAECgIIAwAAAA==.',
Ru='Rukkis:BAABNQAECoEcAAMkAAgKixfzHwBXAgAkAAgKixfzHwBXAgAlAAMKDwknPQClAAAAAA==.Rukâ:BAAANQADCgcIEwAAAA==.Rumi:BAABNQAECoEvAAIcAAkKix5HAwAPAwAcAAkKix5HAwAPAwAAAA==.Rumm:BAAANQADCgYIBwAAAA==.',
Ry='Ryeekan:BAAANQAECgYICwAAAA==.Ryuma:BAAANQAECgYIDwAAAA==.Ryumar:BAAANQAECgMIAwAAAA==.',
Sa='Sabrosura:BAAANQAECgYIEwAAAA==.Saiyan:BAAANQADCgIIAgAAAA==.Salsinor:BAAANQADCgUIBQAAAA==.Sanosagara:BAAANQAECggIBgAAAA==.Sathari:BAABNQAECoEbAAIOAAcKKxLHKwDCAQAOAAcKKxLHKwDCAQAAAA==.',
Sc='Schaden:BAAANQAECgQIBwAAAA==.Scripter:BAAANQADCgUIBgAAAA==.',
Se='Seijo:BAAANQAECgEJAQAAAA==.Sekk:BAABNQAECoEjAAMIAAgKTBjZbgAkAgAIAAgK7BfZbgAkAgAiAAUKdxLeOgDtAAAAAA==.Selecta:BAAANQAECgEIAQAAAA==.Selexi:BAAANQADCggICAAAAA==.Selithira:BAAANQAECgUIEgAAAA==.Sera:BAAANQADCgYICgAAAA==.',
Sh='Shabagnarang:BAAANQAECgQIDAABNQAECgcIIgASAJMcAA==.Shadeofdark:BAAANQAECgUIBgAAAA==.Shalasyr:BAAANQAECgEIAgAAAA==.Shaletaz:BAAANQABCgQIBgAAAA==.Shamwowee:BAAANQADCgYIHgAAAA==.Shamzee:BAABNQAECoEpAAIBAAkK+hzvHgDSAgABAAkK+hzvHgDSAgAAAA==.Sheyy:BAAANQAECgEIAQAAAA==.Shiftybonez:BAAANQADCgQIBQAAAA==.Shintok:BAAANQAECgQICQAAAA==.Shuddarun:BAACNQAFFIESAAIDAAcKcBnQAAB/AgADAAcKcBnQAAB/AgA1AAQKgSgAAgMACQrbJBkJAIUDAAMACQrbJBkJAIUDAAAA.',
Si='Silverbakk:BAAANQABCgEIAQAAAA==.Simn:BAAANQAECgYICwAAAA==.Sindraesong:BAAANQAECgUJCQAAAA==.',
Sk='Skithiryx:BAAANQAECgQIBAABNQAECggIGwAOANsYAA==.Skuldd:BAAANQABCgQICQAAAA==.',
Sl='Slayvylora:BAAANQADCgcIBwABNQAFFAIIBAAKAAAAAA==.',
Sm='Smarte:BAAANQADCgYIBwABNQAFFAEIAQAKAAAAAA==.Smolderpally:BAAANQADCgYIBgAAAA==.',
Sn='Sneakymoth:BAAANQADCgUIBQABNQAECgUIDwAKAAAAAA==.Snookums:BAAANQAECgUICgAAAA==.',
So='Soarin:BAAANQADCgQIBAAAAA==.',
Sp='Spicymaker:BAABNQAECoEYAAILAAgKZR3/SACVAgALAAgKZR3/SACVAgAAAA==.',
St='Starya:BAAANQAECgQIBAAAAA==.Steelheart:BAAANQABCgQIBAAAAA==.Stop:BAAANQAECgMIAwAAAA==.Strifewood:BAAANQAECgYIBgAAAA==.Stumper:BAABNQAECoEdAAIPAAgKnhUPMAA7AgAPAAgKnhUPMAA7AgAAAA==.',
Su='Sux:BAAANQADCgMIAwAAAA==.',
Sy='Sybrina:BAABNQAECoEcAAIDAAgKIhOaXwAuAgADAAgKIhOaXwAuAgAAAA==.Sylvia:BAABNQAECoEaAAIgAAgKIhA0tAD4AQAgAAgKIhA0tAD4AQAAAA==.Syngeance:BAAANQAECgUICgAAAA==.Synèsterwolf:BAAANQAECggICwAAAA==.',
['Sí']='Síf:BAAANQAECgEIAQAAAA==.',
Ta='Tadeusz:BAAANQAECgUIBwAAAA==.Taelah:BAAANQADCgMIAwAAAA==.Tamamò:BAAANQADCgYICAAAAA==.Tanglefoot:BAAANQAECgcIDwAAAA==.Tanleros:BAAANQAECgYICwAAAA==.Taquítos:BAAANQADCgYICAAAAA==.Tasigur:BAAANQADCgEIAQABNQAECggIGwAOANsYAA==.',
Te='Telana:BAAANQADCgYIHgAAAA==.Tequitos:BAAANQAECgUIDwAAAA==.Tessla:BAAANQADCgYIDAAAAA==.',
Th='Theduk:BAABNQAECoEaAAMlAAkKcAyKGwDmAQAlAAgKrQyKGwDmAQAkAAgKLAoHNwC8AQAAAA==.Theduke:BAAANQADCgIIAwAAAA==.Theliria:BAAANQADCgYIBgAAAA==.Thorias:BAABNQAECoEZAAIgAAgKLRwCeAB4AgAgAAgKLRwCeAB4AgAAAA==.Thtime:BAABNQAECoEqAAIgAAkKxx8tKAA3AwAgAAkKxx8tKAA3AwAAAA==.',
To='Toira:BAAANQADCgUIBQAAAA==.Tomoko:BAAANQADCgYICQAAAA==.Torment:BAABNQAECoEjAAIQAAgKehj+LgA7AgAQAAgKehj+LgA7AgAAAA==.',
Tr='Tristén:BAAANQAECggIDQAAAA==.Truvie:BAAANQADCgMIAwAAAA==.',
Tu='Tumbled:BAAANQAECgYIEAAAAA==.Tumbles:BAAANQADCgQIBQAAAA==.Tumni:BAAANQAECgUICQAAAA==.',
Tw='Twinkletoes:BAAANQADCgYIBgAAAA==.',
['Tá']='Tángall:BAAANQABCgEIAQAAAA==.',
Ui='Ui:BAAANQADCgMIAwAAAA==.',
Ul='Ulnuk:BAABNQAECoEmAAIBAAgKiRpHNQBkAgABAAgKiRpHNQBkAgAAAA==.Ulster:BAAANQADCgEIAQAAAA==.',
Un='Ungodly:BAABNQAECoEaAAIeAAkKAQylOACyAQAeAAkKAQylOACyAQAAAA==.Unholyshan:BAAANQADCggIDAAAAA==.Unidus:BAAANQABCgUICAAAAA==.',
Uu='Uutr:BAAANQABCgEIAQAAAA==.',
Uv='Uvvolx:BAAANQADCgQICAAAAA==.',
Va='Vadka:BAAANQAECgIIAwAAAA==.Vaeldrin:BAAANQAECgQIBQAAAA==.Vaha:BAAANQAECgIIAwAAAA==.Valkree:BAAANQAECgQICQAAAA==.Valsavis:BAABNQAECoEjAAIcAAgKRB8FBQC8AgAcAAgKRB8FBQC8AgAAAA==.',
Ve='Veaolop:BAAANQABCggIEAAAAA==.Vellagosa:BAAANQAECgIIAwAAAA==.Vernice:BAAANQADCgYICwABNQAECgQIBwAKAAAAAA==.Verulan:BAAANQAECgQIBQAAAA==.Vexidari:BAAANQAECgUICQABNQAFFAIIBAAKAAAAAA==.Vexomous:BAABNQAECoEeAAMUAAgKLByPBABvAgAUAAgKLByPBABvAgAEAAQK7gjIUAC8AAABNQAFFAIIBAAKAAAAAA==.',
Vi='Viiolet:BAAANQAECgYIBgAAAA==.',
Vo='Voidmayne:BAABNQAECoEaAAIIAAgKlRAIkQDOAQAIAAgKlRAIkQDOAQAAAA==.Vongogh:BAAANQADCgYICQAAAA==.Vonhelsing:BAAANQADCgEIAQAAAA==.',
Vy='Vynnara:BAAANQADCgEIAQAAAA==.Vyolent:BAAANQADCgYICwAAAA==.',
Wa='Warnox:BAAANQAECgIIAgAAAA==.',
We='Weiand:BAABNQAECoEVAAMJAAcKYBC2jQBKAQAJAAYK6Ay2jQBKAQAIAAUKqwo89gD4AAAAAA==.Wevark:BAAANQAECgYIEAAAAA==.',
Wh='Whatami:BAABNQAECoEVAAMfAAgKXRaXaQD5AQAfAAcKNheXaQD5AQAhAAIKtQuLWQBqAAAAAA==.Wholemilk:BAAANQAECgIIAwAAAA==.',
Wi='Wilhellena:BAABNQAECoEaAAINAAcKHg8veQB2AQANAAcKHg8veQB2AQAAAA==.Wilhellfu:BAAANQADCgMIAwAAAA==.Winariel:BAAANQAECgUICAABNQAECggIGgAQADoRAA==.Witewalker:BAAANQADCgMIAwAAAA==.',
Wr='Writhesoul:BAAANQABCgIIAgABNQAECgcICgAKAAAAAA==.Wroughtsoul:BAAANQAECgYIBwAAAA==.Wrysoul:BAAANQAECgcICgAAAA==.',
Wy='Wynston:BAAANQADCgEIAQAAAA==.Wyrmheart:BAAANQADCgIIAwAAAA==.',
Xa='Xalatath:BAAANQADCgEIAQABNQAECggIGQAIAMcaAA==.Xaldred:BAAANQAECgUIEwABNQAECggIIAAVAKEWAA==.Xandir:BAABNQAECoEUAAIiAAcKWREyKABwAQAiAAcKWREyKABwAQAAAA==.Xarhunt:BAAANQAECgEIAQAAAA==.',
Xe='Xenzia:BAAANQADCgcICwAAAA==.Xeracil:BAAANQADCgQICgAAAA==.',
Xo='Xoric:BAABNQAECoEgAAIjAAgKRRM4IAD9AQAjAAgKRRM4IAD9AQAAAA==.',
Xy='Xyal:BAAANQAECggIEwAAAA==.Xyp:BAAANQADCgYIBgABNQAECgQIBQAKAAAAAA==.',
Ya='Yamaya:BAAANQADCgMIBQAAAA==.',
Yi='Yiago:BAAANQAECgIIAgAAAA==.',
Yo='Youknow:BAAANQADCgcICwAAAA==.',
Za='Zaelia:BAAANQADCgEIAQAAAA==.Zary:BAAANQAECgIIAgAAAA==.Zaxhdk:BAEANQADCgMIAwABNQAECgcIEwAKAAAAAA==.Zaxhpal:BAEANQAECgcIEwAAAA==.',
Zi='Zid:BAAANQAECgMIAwAAAA==.Ziny:BAAANQADCgUIBQAAAA==.Ziparoo:BAABNQAECoEYAAIWAAcK/AjkEwBEAQAWAAcK/AjkEwBEAQAAAA==.',
Zr='Zraven:BAAANQADCgEIAQAAAA==.',
['În']='Îniquitous:BAAANQAECgUIDgAAAA==.',
['Ðê']='Ðêmønicßløøð:BAAANQAECgcIEAABNQAECgcIFAALACUVAA==.',
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
