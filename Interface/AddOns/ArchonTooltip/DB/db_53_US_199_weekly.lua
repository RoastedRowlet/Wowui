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

local lookup = {'Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Arms','Paladin-Retribution','Paladin-Holy','Warrior-Protection','Priest-Holy','DemonHunter-Devourer','Druid-Balance','Unknown-Unknown','DeathKnight-Blood','Hunter-Survival','Mage-Fire','Shaman-Enhancement','Warlock-Affliction','Mage-Arcane','Mage-Frost','DeathKnight-Unholy','Paladin-Protection','Evoker-Preservation','Druid-Guardian','Monk-Windwalker','Monk-Brewmaster','Priest-Shadow','DemonHunter-Vengeance','Druid-Feral','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Evoker-Devastation','Druid-Restoration','Warrior-Fury','Rogue-Subtlety','Rogue-Assassination',}
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abigt:BAAANQADCgIIAQAAAA==.',
Ac='Acidsnow:BAAANQADCgUIBwAAAA==.',
Ad='Adalaidê:BAAANQAECgIIAgAAAA==.',
Ae='Aerynne:BAAANQADCgcIHAAAAA==.',
Ai='Airie:BAABNQAECn8ZAAMBAAcK9w6vsgAFAQABAAYK9gqvsgAFAQACAAIKOwQAGAFYAAAAAA==.',
Ak='Akuso:BAAANQADCgIIAgAAAA==.',
Al='Alcohaulorc:BAAANQAECgQIBwAAAA==.Alert:BAAANQAECgEIAQAAAA==.Aloris:BAAANQAECgQICAAAAA==.Aloy:BAABNQAFFH8MAAMDAAQKwReTDwBaAQADAAQKwReTDwBaAQAEAAEKAADTJwAzAAAAAA==.Aluhx:BAAANQAECgMIBgABNQAFFAMIBQAFAPUPAA==.',
Am='Amednato:BAAANQAECgcIEQAAAA==.',
An='Anaeli:BAABNQAECn89AAIBAAgKmCEaGwABAwABAAgKmCEaGwABAwAAAA==.Anastarian:BAAANQAECgEIAQAAAA==.Ancalagonn:BAAANQAECgcIDwAAAA==.Angita:BAAANQAECgMIBgAAAA==.Anklin:BAAANQADCgIIAgAAAA==.Annaris:BAACNQAFFH8XAAIDAAYKKx7UAgA8AgADAAYKKx7UAgA8AgA1AAQKfywAAwMACQrqJSUHAKMDAAMACQrqJSUHAKMDAAQACAp4GbQxALwBAAAA.Antipæn:BAECNQAFFH8IAAMGAAMKFSLGEgAfAQAGAAMKFSLGEgAfAQAHAAEKdCMYJQBmAAA1AAQKfzkAAwYACQoVJo0EANQDAAYACQoVJo0EANQDAAcACQrNIQ8LAG4DAAAA.',
Ap='Apologia:BAABNQAECn8gAAIGAAgKlSKvLQAPAwAGAAgKlSKvLQAPAwAAAA==.',
Aq='Aquaphobic:BAAANQAECgMICAABNQAFFAYIEQABAK0KAA==.',
Ar='Arcanoth:BAAANQADCgIIAgAAAA==.Ardicelia:BAAANQABCgUIBgAAAA==.Ares:BAABNQAECn8fAAIFAAkK2SN/HQBAAwAFAAkK2SN/HQBAAwAAAA==.Armorgorden:BAABNQAECn8rAAIIAAgKySIXBgAHAwAIAAgKySIXBgAHAwAAAA==.Aroviaa:BAABNQAECn8rAAIJAAgKJRwvPwBqAgAJAAgKJRwvPwBqAgAAAA==.Arpmek:BAABNQAECn8mAAIKAAgKoxQKJQAaAgAKAAgKoxQKJQAaAgAAAA==.Artemîs:BAAANQADCgIIAgAAAA==.',
As='Asharienne:BAABNQAECn8gAAIDAAgKXQ8wfgANAgADAAgKXQ8wfgANAgAAAA==.Ashlynne:BAAANQAECgYJCwAAAA==.',
Au='Audiobully:BAAANQAECgQIBAABNQAECggIIwALABQVAA==.Auralynn:BAAANQAECgQJBAABNQAECgYJCwAMAAAAAA==.Auriella:BAABNQAECn8aAAMHAAkKRQwDaADcAQAHAAkKRQwDaADcAQAGAAEKAABOrAEuAAAAAA==.Aurtt:BAABNQAECn8oAAINAAgKFRaVRADmAQANAAgKFRaVRADmAQAAAA==.',
['Aö']='Aöb:BAAANQADCgQIBgAAAA==.',
Ba='Bahahaknight:BAABNQAECn8iAAINAAcK2hXATwCzAQANAAcK2hXATwCzAQAAAA==.Bahree:BAAANQADCgIIAgAAAA==.Bakhar:BAABNQAECn8WAAIOAAcK0B0BBQB8AgAOAAcK0B0BBQB8AgAAAA==.Balora:BAAANQADCgcIEQAAAA==.Barnette:BAABNQAECn8uAAIPAAkKQBTTAQBtAgAPAAkKQBTTAQBtAgAAAA==.Basyleus:BAAANQADCgEIAQAAAA==.',
Be='Bellonitra:BAAANQABCgMIBQAAAA==.Belthos:BAABNQAECn8ZAAIGAAgKSBjxdgA7AgAGAAgKSBjxdgA7AgAAAA==.Benihime:BAAANQAECgEIAQAAAA==.Berristan:BAABNQAECn8vAAIHAAkKqA1bYQDxAQAHAAkKqA1bYQDxAQAAAA==.Bestwingman:BAAANQADCgEIAQAAAA==.',
Bi='Bigdawgsteve:BAAANQADCgIIAgAAAA==.Bigmarv:BAAANQAECgUIDAAAAA==.Bittytigs:BAACNQAFFH8HAAIBAAMKwhdFFwDiAAABAAMKwhdFFwDiAAA1AAQKfz0AAwEACQqCIEsUACkDAAEACQqCIEsUACkDAAIAAQoAANdJAScAAAAA.',
Bl='Blestemat:BAAANQADCgYIBwAAAA==.Bluewitchpa:BAAANQADCgcIHwAAAA==.Blumangood:BAABNQAECn8iAAQCAAgKdxcNVwAbAgACAAgKdxcNVwAbAgABAAIKLQJsEgE/AAAQAAEKAABBNwAwAAAAAA==.',
Bo='Bollux:BAAANQAECgEIAgAAAA==.Bosc:BAAANQAECgcIDQAAAA==.Boudiicca:BAAANQADCgcIHAAAAA==.Boxmasterr:BAABNQAECn8rAAIRAAgKqBivBQBfAgARAAgKqBivBQBfAgAAAA==.',
Br='Braagh:BAAANQABCggICwAAAA==.Brasmir:BAABNQAECn8fAAIOAAkKhBufAgAIAwAOAAkKhBufAgAIAwAAAA==.Briae:BAAANQADCgMIAwABNQAECggIPQABAJghAA==.Brianzero:BAAANQABCgQJBgAAAA==.Brino:BAAANQABCgQIBAAAAA==.Brinotriage:BAAANQABCgIIAgAAAA==.',
Bu='Bubblemoth:BAAANQADCgMIBAABNQAECgUIDwAMAAAAAA==.Buik:BAAANQAECgIIAgAAAA==.Bulge:BAABNQAECn8aAAMSAAkKtgs7zgDnAQASAAkKAgo7zgDnAQATAAEK2RYlPwBFAAABNQAFFAQICgAUAFcLAA==.Bulgogi:BAACNQAFFH8KAAIUAAQKVwuEDwAOAQAUAAQKVwuEDwAOAQA1AAQKfywAAhQACQpBHvQgAMMCABQACQpBHvQgAMMCAAAA.',
['Bö']='Börk:BAAANQAECgMIBgAAAA==.',
Ca='Capy:BAAANQAECgIIAgABNQAFFAQIBgATAOQUAA==.Cardran:BAAANQADCgIIAgABNQAECgcIEQAMAAAAAA==.Cayda:BAAANQADCgYJCQAAAA==.Caylara:BAAANQAECgIIBQAAAA==.Cayssaber:BAAANQADCggIDAAAAA==.',
Ce='Ceicilia:BAAANQADCgQIBAAAAA==.Celrythis:BAAANQAECgIIAwAAAA==.Cenokry:BAAANQADCgQIBAAAAA==.',
Ch='Chai:BAAANQAECgYIDQAAAA==.Chaintrain:BAAANQAECgMIAwABNQAECgYICwAMAAAAAA==.Chellyy:BAAANQAECgIIAgABNQAECgUICAAMAAAAAA==.Chibisend:BAAANQADCgMIAwAAAA==.Chámeleon:BAAANQADCgEIAQAAAA==.',
Ci='Cider:BAAANQAECgIIAgAAAA==.',
Co='Coralbubbles:BAABNQAECn8dAAIGAAkKUxN0egAyAgAGAAkKUxN0egAyAgAAAA==.Coralorchid:BAABNQAECn8ZAAIVAAYKlB7MGgAWAgAVAAYKlB7MGgAWAgAAAA==.Coralrages:BAAANQAECgMIBgAAAA==.',
Cr='Cromenockle:BAAANQAFFAEIAQAAAA==.Crtitman:BAAANQAECgUIBQAAAA==.',
Cu='Cupcâke:BAAANQAECgQIBAAAAA==.Curissan:BAAANQAECgYIDQAAAA==.',
Da='Dalgon:BAABNQAFFH8IAAIWAAQK6wT3DwDvAAAWAAQK6wT3DwDvAAABNQAFFAYIDAAHABkTAA==.Dalir:BAAANQAECgUICgAAAA==.Dalspin:BAAANQADCgYIDAABNQAFFAYIDAAHABkTAA==.Dalthepal:BAACNQAFFH8MAAIHAAYKGROvBwDnAQAHAAYKGROvBwDnAQA1AAQKfzAAAgcACQoRHu0WAB8DAAcACQoRHu0WAB8DAAAA.Damné:BAABNQAECn8mAAIUAAkK2BbCMwBZAgAUAAkK2BbCMwBZAgAAAA==.Davidline:BAABNQAECn8YAAIGAAkKlhutOgDkAgAGAAkKlhutOgDkAgAAAA==.',
De='Deadish:BAABNQAECn8oAAMNAAkK6RzjEwALAwANAAgKuCDjEwALAwAUAAEKDQbwAQERAAAAAA==.Deathsaberss:BAABNQAECn83AAMFAAkK5RiwQgC/AgAFAAkK5RiwQgC/AgAIAAQK5As6KgDjAAAAAA==.Deathvex:BAABNQAFFH8KAAINAAQKuRDOEwAYAQANAAQKuRDOEwAYAQAAAA==.Decoz:BAAANQAECgUIBwAAAA==.Deight:BAAANQADCgIIAgAAAA==.Dejamoo:BAAANQADCgYIEwAAAA==.Dendahn:BAAANQAECgcIDQAAAA==.Destinee:BAAANQAECgQICwAAAA==.',
Di='Dianntha:BAAANQADCgYIDgAAAA==.Diladrin:BAABNQAECn86AAIXAAkKLRloDACdAgAXAAkKLRloDACdAgAAAA==.Dinomight:BAAANQADCgQIBAAAAA==.',
Do='Doileag:BAAANQAECgQICAAAAA==.Doomgrave:BAAANQADCgEIAQAAAA==.Dora:BAAANQADCgYIBgABNQAECgUIEQAMAAAAAA==.Dottmatrix:BAAANQAECgIIBQAAAA==.Doubledowns:BAAANQAECgEIAQAAAA==.',
Dr='Dreadwing:BAAANQADCgcIHAAAAA==.Druromu:BAAANQAECgIIBQAAAA==.',
Du='Dufs:BAACNQAFFH8MAAIBAAQKjSX7CAC9AQABAAQKjSX7CAC9AQA1AAQKfyQAAgEACQrxIPgbAP0CAAEACQrxIPgbAP0CAAAA.Dunkan:BAAANQADCgYICwAAAA==.Dustbunny:BAABNQAECn8oAAIJAAgKdxaOVAAiAgAJAAgKdxaOVAAiAgAAAA==.',
Dw='Dwagon:BAAANQAECgYIDwAAAA==.',
Dy='Dylsonlolqt:BAAANQAECgMIAwAAAA==.',
['Dã']='Dãrling:BAAANQABCgEIAQAAAA==.',
['Dû']='Dûn:BAABNQAECn8qAAMYAAkKkh+eDQAAAwAYAAkKPx+eDQAAAwAZAAgKNh4LCgB2AgAAAA==.Dûna:BAABNQAECn8fAAIaAAkK8RgJFADDAgAaAAkK8RgJFADDAgABNQAECgkJKgAYAJIfAA==.',
El='Elaatia:BAABNQAECn8rAAIGAAgKXCN1KQAeAwAGAAgKXCN1KQAeAwAAAA==.Elidria:BAAANQABCgIIAgABNQADCgYIBgAMAAAAAA==.Ellysprocket:BAAANQADCgUICQAAAA==.Elrric:BAAANQAECgcICgAAAA==.Elyak:BAAANQADCgIIAgAAAA==.',
En='Envoy:BAAANQADCgcIEwAAAA==.',
Er='Erakron:BAABNQAECn8jAAMCAAgKmBIJYgD3AQACAAgKmBIJYgD3AQABAAUKTxIKpgAiAQAAAA==.Erine:BAAANQAECgIIAgAAAA==.Erouvi:BAAANQADCgIIAgABNQAECggIKwAJACUcAA==.Eroviaa:BAAANQAECgMIAwABNQAECggIKwAJACUcAA==.Erovvia:BAAANQADCgUIBQABNQAECggIKwAJACUcAA==.',
Es='Esmeralda:BAAANQABCggIEAAAAA==.',
Ez='Ezothen:BAAANQAECgUIDgAAAA==.',
Fa='Facelessman:BAAANQABCggIHgAAAA==.Faedoria:BAAANQAECgMIBAAAAA==.Faeryln:BAABNQAECn8oAAIJAAkK8ggVdwCyAQAJAAkK8ggVdwCyAQAAAA==.Fatalcheese:BAAANQABCgQIBAAAAA==.Faustus:BAAANQAECgcIEAAAAA==.Favion:BAAANQADCgEIAQAAAA==.',
Fe='Felyyia:BAAANQAECgcIDQABNQAFFAYIFwADACseAA==.Feyox:BAAANQADCggICAAAAA==.',
Fi='Fiddlestix:BAAANQAECgQIBAAAAA==.Firebrande:BAAANQAECgMIBgAAAA==.Fisticuffs:BAAANQADCgcIHQAAAA==.Fizcrankshot:BAABNQAECn8nAAIDAAkK7BCeVwBpAgADAAkK7BCeVwBpAgAAAA==.',
Fl='Flamewhisker:BAAANQAECgMIBgAAAQ==.Flamez:BAAANQADCgcIBwAAAA==.',
Fr='Fraublucher:BAABNQAECn8gAAIJAAcKawgclQBRAQAJAAcKawgclQBRAQAAAA==.Frewyn:BAAANQAECgUICgAAAA==.Frostimoth:BAAANQAECgUIDwAAAA==.Frozty:BAAANQAECgQIBgAAAA==.',
Ga='Galandel:BAAANQADCgcIGgAAAA==.Galial:BAACNQAFFH8GAAIbAAIK8A55BQBqAAAbAAIK8A55BQBqAAA1AAQKfy0AAhsACQqJGfYGAKACABsACQqJGfYGAKACAAAA.Gantar:BAAANQAECgQIBQABNQAECgkJJgANADAjAA==.Garradin:BAAANQADCgEIAQAAAA==.Garrunter:BAAANQADCggIJAAAAA==.Gaznol:BAAANQADCgQIBAABNQAECgcIEQAMAAAAAA==.',
Ge='Gelasera:BAAANQAECgMIBQAAAA==.Gemitra:BAAANQADCgcIBwABNQAECgYIGQAVAJQeAA==.Geneth:BAAANQAECgUIBQAAAA==.George:BAABNQAECn8jAAIFAAgK+h6CVwCCAgAFAAgK+h6CVwCCAgAAAA==.',
Gh='Ghalta:BAAANQADCgIIAgABNQAECgkJIwAKAD4bAA==.Ghrol:BAAANQABCgYIBgABNQAECggILgABAIkaAA==.',
Gl='Glaivethras:BAABNQAECn8lAAIbAAkKvR4FAwA9AwAbAAkKvR4FAwA9AwAAAA==.Glenfin:BAAANQADCgQIBgAAAA==.',
Gr='Greg:BAAANQADCgUICQABNQADCggIFQAMAAAAAA==.Gremlynn:BAAANQADCggICAAAAA==.Grimclaw:BAABNQAECn8hAAMLAAkKgCR5HgDUAgALAAgKlSJ5HgDUAgAcAAUK6ySnDgAnAgAAAA==.Groot:BAAANQAECgQIEAABNQAECggIGQAVAOYRAA==.',
Gu='Guthrek:BAAANQAECgYIBgAAAA==.',
Ha='Hamfist:BAAANQADCgIIAgABNQAECggJDAAMAAAAAA==.Hannebal:BAAANQAECgcIEAAAAA==.',
He='Healyclam:BAAANQADCgMIAwAAAA==.Heydaw:BAAANQADCggICAABNQAECggIFwAdAKsaAA==.Heynow:BAAANQADCggIGwAAAA==.',
Hi='Highmountain:BAAANQADCgYICwAAAA==.Hilimed:BAABNQAECn8qAAIeAAkK8QkYfgDmAQAeAAkK8QkYfgDmAQAAAA==.',
Ho='Hobs:BAAANQADCgUIBQAAAA==.Holyßloodelf:BAAANQAECgcICwABNQAECggIHAAFAFAWAA==.Hoosier:BAAANQAECgQIBAAAAA==.Hoplite:BAAANQAECgYICwAAAA==.',
Hu='Huasca:BAAANQAECgEIAQAAAA==.Huthuel:BAAANQABCggIFAAAAA==.',
Hy='Hydra:BAAANQADCgYIBgABNQAECgkJHgASAPsPAA==.Hyve:BAAANQADCgcIIAABNQAECggIKgAGAGkbAA==.',
['Hà']='Hàney:BAEANQAECgQIBAAAAA==.',
['Hé']='Hélio:BAAANQADCgUIBQAAAA==.',
Ia='Ia:BAABNQAECn8lAAIdAAkKGyCXCwA5AwAdAAkKGyCXCwA5AwAAAA==.',
Ib='Ibesneakin:BAAANQADCggIDgABNQAECggJDAAMAAAAAA==.',
Id='Idontsuck:BAAANQADCggICwAAAA==.',
Il='Ileynha:BAAANQABCgIIAgAAAA==.Ilieau:BAAANQAECgQIBQABNQAECggIFwAOADYeAA==.Illida:BAAANQADCgYIBgAAAA==.',
Im='Imamalelol:BAAANQAECgUIBwAAAA==.',
In='Inarrah:BAAANQADCgEIAQAAAA==.Intrepidhero:BAAANQADCgEIAQAAAA==.',
Ir='Irkenfox:BAECNQAFFH8MAAIIAAQKXhWCAwAZAQAIAAQKXhWCAwAZAQA1AAQKfyUAAggACQovJJcCAIcDAAgACQovJJcCAIcDAAAA.',
It='Ithran:BAAANQADCgUIBQAAAA==.',
Iw='Iwilltank:BAAANQADCgYICwAAAA==.',
Ix='Ixitt:BAABNQAECn8nAAIPAAgKphc3AgA6AgAPAAgKphc3AgA6AgAAAA==.',
Ja='Jama:BAAANQADCgYIBgAAAA==.Janderick:BAAANQAECgYIDgAAAA==.Jaromer:BAAANQADCgcICgAAAA==.',
Je='Jellacee:BAAANQADCgcIFwAAAA==.',
Ji='Jimboberjim:BAACNQAFFH8MAAIfAAQKQR60AAB+AQAfAAQKQR60AAB+AQA1AAQKfykAAh8ACQqRImkBAHsDAB8ACQqRImkBAHsDAAAA.Jimbobwhey:BAAANQAECggIBwABNQAECggIHgAIAD8TAA==.Jiminie:BAABNQAECn8eAAIIAAgKPxPTFQDHAQAIAAgKPxPTFQDHAQAAAA==.',
Jo='Jolio:BAAANQAECgYICwAAAA==.Joltraxi:BAAANQADCggICAABNQAECgYICwAMAAAAAA==.Joshie:BAABNQAECn8mAAINAAkKMCPECQBnAwANAAkKMCPECQBnAwAAAA==.Joshy:BAAANQADCgcIBwABNQAECgkJJgANADAjAA==.',
Ju='Jujubeans:BAAANQAECgEIAQAAAA==.Juniornite:BAABNQAECn8pAAISAAgKyyESPwAHAwASAAgKyyESPwAHAwAAAA==.Justthetouch:BAAANQADCggICAAAAA==.',
Jy='Jygglypuff:BAAANQAECgEIAQAAAA==.',
Ka='Kadaan:BAAANQAECgUIBQAAAA==.Kagemaro:BAABNQAECn8jAAMKAAkKPhsHFQC7AgAKAAkKPhsHFQC7AgAbAAUKdRR3GQAYAQAAAA==.Kahgar:BAAANQAECgYIEQABNQAECgkJRwAHAMMVAQ==.Kalimathath:BAAANQAECgEIAQAAAA==.Kalzod:BAABNQAECn84AAIeAAkKOCXWAQDcAwAeAAkKOCXWAQDcAwAAAA==.Kataki:BAABNQAECn8ZAAIDAAgKoxciXABeAgADAAgKoxciXABeAgABNQAECgkJIwAKAD4bAA==.Katia:BAAANQAECgIIAwAAAA==.Kativeria:BAAANQAECgMIBQAAAA==.Katjayna:BAAANQADCgUICgAAAA==.Kaysabr:BAAANQADCgQIBAAAAA==.Kayssaber:BAAANQAECgYIDwAAAA==.',
Ke='Kebab:BAAANQAECgQJBAAAAA==.Kelsifer:BAAANQAECgQICwABNQAECgcIEAAMAAAAAA==.Kempra:BAAANQADCgcIBwAAAA==.Kemprei:BAAANQADCgUIBQAAAA==.Kendralust:BAAANQAECgcICAAAAA==.Kerfufle:BAAANQABCgIJAgAAAA==.',
Kh='Khaos:BAAANQABCgEIAQAAAA==.',
Ki='Kippars:BAAANQAECgEIAQAAAA==.',
Ko='Kodazoff:BAAANQAECgcIEAAAAA==.Kora:BAAANQABCgEIAgAAAA==.Korevash:BAABNQAECn8wAAMBAAkKtyTmAwCrAwABAAkKtyTmAwCrAwAQAAYKAhIJHACeAQAAAA==.',
Kr='Krezz:BAAANQAECgEIAQAAAA==.Krissylu:BAAANQAECgUICgAAAA==.Krothix:BAABNQAECn8nAAICAAgKwAcFiACMAQACAAgKwAcFiACMAQAAAA==.Krudd:BAAANQAECgYICwAAAA==.Krychilly:BAAANQADCgYIEQAAAA==.Kryrande:BAAANQADCgQJCwAAAA==.Kryshym:BAAANQAECgYIDgAAAA==.Krythrall:BAAANQADCgUIBQABNQAECgYIDgAMAAAAAA==.Kryvelen:BAAANQAECgUIBQAAAA==.Krëëp:BAAANQAECggICAAAAA==.',
Ks='Kspectactle:BAAANQADCgcICQAAAA==.',
Ku='Kuilei:BAAANQADCgYJCwABNQAECgIIBQAMAAAAAA==.Kurorø:BAAANQAECgIIBQAAAA==.',
Ky='Kyrayna:BAAANQADCgUIDAAAAA==.',
La='Ladara:BAABNQAECn8lAAIRAAgKPBYgBgBPAgARAAgKPBYgBgBPAgAAAA==.Laima:BAAANQADCgUICQAAAA==.Lavitz:BAAANQAECgEIAQAAAA==.',
Le='Leheo:BAAANQADCgIIAgAAAA==.Lehua:BAAANQADCgIIAgAAAA==.Leilanii:BAAANQADCgcIEQAAAA==.Lemook:BAAANQAECgYIEAAAAA==.Leonìdas:BAAANQADCgcIEQAAAA==.Leð:BAAANQAECggICAAAAA==.',
Li='Licker:BAAANQAECgUICQABNQAFFAEIAQAMAAAAAA==.Life:BAAANQADCgIIAgAAAA==.Lightbulb:BAAANQADCgYIDQAAAA==.Lightsorrow:BAAANQAECgIIAgABNQAECggIHwAgAOsTAA==.Lightstormer:BAAANQADCgcIHwAAAA==.Lilamae:BAAANQAECgQICQAAAA==.Lilarielle:BAABNQAECn8kAAIcAAYKsgVeJQDfAAAcAAYKsgVeJQDfAAAAAA==.Lildookie:BAAANQAECgQIBwAAAA==.Lilface:BAAANQAECgIIAgAAAA==.Liliel:BAAANQADCgMIAwABNQAECgcIEQAMAAAAAA==.Liliela:BAAANQAECgcIEQAAAA==.Lilyannah:BAAANQADCgEIAQAAAA==.Liodragon:BAAANQADCgUIBQABNQAECgcICgAMAAAAAA==.Liolock:BAAANQAECggIBwAAAA==.Lite:BAAANQAECgQIBAAAAA==.Liø:BAAANQAECgcICgAAAA==.',
Ll='Lluniez:BAAANQAECgcIEQAAAA==.',
Lo='Lockroknroll:BAAANQAECggJDAAAAA==.Losoli:BAABNQAECn8pAAIHAAgKxR47KwC4AgAHAAgKxR47KwC4AgAAAA==.Lotor:BAAANQADCgYIBgAAAA==.Lowchin:BAAANQAECgIIAgAAAA==.',
Lu='Lupine:BAAANQADCgYIBgABNQAECgQIBAAMAAAAAA==.Lutherion:BAABNQAECn8iAAIIAAkKFR74BQAKAwAIAAkKFR74BQAKAwAAAA==.',
Ly='Lycemmas:BAABNQAECn8cAAIBAAgKIhrnRABKAgABAAgKIhrnRABKAgAAAA==.',
['Lï']='Lïo:BAAANQADCgYIBwABNQAECgcICgAMAAAAAA==.',
Ma='Macoun:BAAANQAECgcIDQAAAA==.Magicshowers:BAABNQAECn8rAAISAAgK0iItNwAaAwASAAgK0iItNwAaAwAAAA==.Majiique:BAAANQABCggIGAAAAA==.Manseed:BAAANQABCgQJBAAAAA==.Maple:BAAANQAECgQIBAAAAA==.Martei:BAACNQAFFH8LAAIcAAQKcRSzAQBJAQAcAAQKcRSzAQBJAQA1AAQKfyQAAhwACQrNGxgHAO4CABwACQrNGxgHAO4CAAAA.Maríneth:BAAANQAECgIIBQAAAA==.Mascara:BAAANQAECgYICwAAAA==.',
Me='Memebait:BAAANQAECgUIBQAAAA==.Mementomori:BAAANQADCgMIAwAAAA==.Meowbae:BAAANQAECgUIBQABNQAECgQIBgAMAAAAAA==.Merce:BAAANQADCgcIBwABNQAECgcIEQAMAAAAAA==.',
Mi='Midway:BAAANQAECgQIBgAAAA==.Minizee:BAAANQADCgYIEAAAAA==.Missfire:BAAANQAECgIIAwAAAA==.Misticlady:BAAANQAECgQIBgAAAA==.Mistrariel:BAAANQADCggICwABNQAECggIEAAMAAAAAA==.Mizukì:BAAANQABCgQIBgAAAA==.',
Mo='Moluubar:BAABNQAECn8XAAIFAAkKmxBxfAAgAgAFAAkKmxBxfAAgAgAAAA==.Moradin:BAAANQADCgMIAwAAAA==.Mordemour:BAAANQAECgUICAAAAA==.',
Mu='Mufler:BAAANQABCgQIBQAAAA==.Mungo:BAAANQAECgYIBwAAAA==.Mushù:BAAANQAECgUICgABNQAECggIHQAeAB4ZAA==.',
My='Myfire:BAAANQADCgYIBgAAAA==.Myrell:BAAANQAECggICAAAAA==.Myrrh:BAAANQAECgYIDwAAAA==.',
Na='Nalik:BAAANQAECgUICgAAAA==.Nanou:BAAANQAECgIIAgAAAA==.Nardiaun:BAAANQADCgYIBgAAAA==.Naturebait:BAAANQADCgQIBAABNQAECggIIgACAHcXAA==.',
Ni='Nimravidae:BAABNQAECn8iAAIHAAcK+hrFUQAiAgAHAAcK+hrFUQAiAgAAAA==.Ninelives:BAAANQAECgQIDQAAAA==.Nitecrawler:BAAANQADCgQIBAAAAA==.Niteeye:BAAANQABCgIIAgABNQAECggIKQASAMshAA==.Niteryu:BAAANQAECgEIAwABNQAECggIKQASAMshAA==.',
No='Nolokkotal:BAABNQAECn8cAAIFAAgKUBYSewAjAgAFAAgKUBYSewAjAgAAAA==.Nospitfisty:BAAANQADCgQIBAAAAA==.Noxolon:BAAANQAECgUIDQAAAA==.',
Nr='Nreaf:BAACNQAFFH8HAAIGAAQK7QhWFQD/AAAGAAQK7QhWFQD/AAA1AAQKfyMAAgYACQo0E3qFABgCAAYACQo0E3qFABgCAAAA.',
Oi='Oili:BAACNQAFFH8HAAITAAQKHwpuAgAMAQATAAQKHwpuAgAMAQA1AAQKfykAAxMACQqRGb0HAG4CABMACQqRGb0HAG4CABIABAoADrFwAdcAAAAA.',
Ol='Olarrick:BAAANQAECgIIAgABNQAECggIIwAFAPoeAA==.',
Oo='Oops:BAACNQAFFH8JAAINAAQKjRvYEQAzAQANAAQKjRvYEQAzAQA1AAQKfy0AAg0ACQpeIS4RACIDAA0ACQpeIS4RACIDAAAA.',
Or='Orcchopped:BAAANQADCgQIBAAAAA==.Ornstein:BAAANQAECgQIBwAAAA==.',
Ot='Ottuk:BAACNQAFFH8FAAIUAAIKFgkqGgCGAAAUAAIKFgkqGgCGAAA1AAQKfysAAhQACQrNIE0fAM0CABQACQrNIE0fAM0CAAAA.',
Pa='Padpaw:BAAANQAECgUJCAAAAA==.Pakraxes:BAABNQAECn8pAAIhAAgKrxB0FQDyAQAhAAgKrxB0FQDyAQAAAA==.Paksenarrion:BAABNQAECn8iAAIVAAcKdw+9LQBrAQAVAAcKdw+9LQBrAQAAAA==.Palehoof:BAAANQADCggIFQAAAA==.Pallywaya:BAAANQAECggICAAAAA==.Pandemonîum:BAAANQAECgQIBAABNQAECggIIAAGAHodAA==.Pandemônium:BAAANQADCgMIAwABNQAECggIIAAGAHodAA==.Pandemönium:BAABNQAECn8gAAMGAAgKeh0xVACVAgAGAAgKUh0xVACVAgAVAAIKzRxYUgCXAAAAAA==.Pandemöniüm:BAAANQAECgYIBwABNQAECggIIAAGAHodAA==.Parts:BAAANQABCggIDQAAAA==.Patchington:BAAANQAECgIIBQAAAA==.Pañdemönium:BAAANQAECgQJCgABNQAECggIIAAGAHodAA==.',
Pe='Pepperrjakk:BAAANQADCgEIAQAAAA==.Perck:BAAANQADCgYIBgAAAA==.Perrylee:BAAANQAECgQICwAAAA==.',
Ph='Philia:BAABNQAECn8XAAMFAAgKmRXkmgDVAQAFAAgKFhLkmgDVAQAIAAMK9RrnKgDdAAABNQAFFAQIDAADAMEXAA==.',
Pi='Pixelme:BAAANQAFFAEIBAAAAA==.',
Pl='Pleggster:BAAANQAECgcIDAAAAA==.',
Po='Pochula:BAAANQAECgUICwAAAA==.',
Pr='Primo:BAABNQAECn9HAAIHAAkKwxVLQwBVAgAHAAkKwxVLQwBVAgAAAA==.Protricity:BAABNQAECn8WAAMaAAgKmBREJAALAgAaAAgKmBREJAALAgAJAAUKcBHdoQAqAQAAAA==.',
Ps='Psalms:BAAANQAECgEIAgABNQAECgQIBwAMAAAAAA==.Psychoprowla:BAABNQAECn8pAAIaAAkKIA5PJAALAgAaAAkKIA5PJAALAgAAAA==.Psychozdrood:BAAANQAECgEIAQAAAA==.',
['Pä']='Pändemönium:BAAANQAECgUICQABNQAECggIIAAGAHodAA==.',
['Pæ']='Pæn:BAEANQAECggIDwABNQAFFAMICAAGABUiAA==.',
Qu='Quantar:BAAANQADCgYIBgABNQAECgMIBgAMAAAAAA==.Quickstab:BAAANQAECgQICAAAAA==.',
Ra='Ragana:BAAANQAECgUIDQAAAA==.Rainger:BAAANQADCgMIAwAAAA==.Rallypaly:BAAANQADCgIIAgAAAA==.Ramthor:BAAANQAECgQIBQAAAA==.Rancooll:BAAANQADCgcIGgAAAA==.Rasniir:BAABNQAECn8oAAIiAAgK1RVKIAAkAgAiAAgK1RVKIAAkAgAAAA==.Rasputea:BAAANQABCgEIAQAAAA==.Ravenar:BAAANQAECgQIBAAAAA==.',
Re='Regna:BAACNQAFFH8JAAMFAAQKjCDbFAB9AQAFAAQKjCDbFAB9AQAjAAIKSR1jAgDBAAA1AAQKfykAAwUACQogJqsaAEwDAAUACQr5I6saAEwDACMABAqzJTsQAKEBAAAA.Relkon:BAAANQADCgMIAwAAAA==.Remaked:BAACNQAFFH8bAAIZAAYKdxqXAQABAgAZAAYKdxqXAQABAgA1AAQKfzgAAhkACQo0IRUEADwDABkACQo0IRUEADwDAAAA.Requinix:BAABNQAECn8qAAIDAAgKtxapYgBOAgADAAgKtxapYgBOAgAAAA==.Retro:BAAANQADCggICQAAAA==.Reynmaker:BAAANQADCgQIBAAAAA==.',
Rh='Rhowyn:BAAANQADCgQICAAAAA==.',
Ri='Riptidez:BAAANQADCgYIBgAAAA==.Ririko:BAABNQAECn8iAAIJAAcKFAh4mgBBAQAJAAcKFAh4mgBBAQAAAA==.Ritzo:BAABNQAECn8iAAIjAAcKzBgaCwAQAgAjAAcKzBgaCwAQAgAAAA==.',
Ro='Rocksanne:BAAANQADCggIEgAAAA==.Rooguee:BAAANQAECgIIAwAAAA==.',
Ru='Rukkis:BAABNQAECn8kAAMkAAkKpRooDwCGAgAkAAgKiRcoDwCGAgAlAAgKDxc2KQBEAgAAAA==.Rukâ:BAAANQADCgcIGQAAAA==.Rumi:BAABNQAECn84AAIbAAkK+x68AwAdAwAbAAkK+x68AwAdAwAAAA==.',
Ry='Ryeekan:BAAANQAECgcIDAAAAA==.Ryuma:BAAANQAECgYIDwAAAA==.Ryumar:BAAANQAECgMIAwAAAA==.',
Sa='Sabrosura:BAABNQAECn8ZAAIVAAgK5hFbJwCfAQAVAAgK5hFbJwCfAQAAAA==.Saiyan:BAAANQADCgIIAgAAAA==.Salsinor:BAAANQADCgUIBQAAAA==.Sanosagara:BAAANQAECggIBgAAAA==.Sathari:BAABNQAECn8iAAIKAAcKzxJrMgCqAQAKAAcKzxJrMgCqAQAAAA==.',
Sc='Schaden:BAAANQAECgQIBwAAAA==.Scripter:BAAANQADCgUIBgAAAA==.',
Se='Seijo:BAAANQAECgEJAQAAAA==.Sekk:BAABNQAECn8qAAMGAAgKaRsEZQBoAgAGAAgKaRsEZQBoAgAVAAUK1BOqQwDgAAAAAA==.Selecta:BAAANQAECgEIAQAAAA==.Selithira:BAAANQAECgUIEgAAAA==.Sephylon:BAAANQADCgEIAQAAAA==.Sera:BAAANQADCgYICgAAAA==.',
Sh='Shabagnarang:BAAANQAECgQIDAABNQAECgcIIgAQAPYbAA==.Shadeofdark:BAAANQAECgYICwAAAA==.Shalasyr:BAAANQAECgEIAgAAAA==.Shaletaz:BAAANQABCgQIBgAAAA==.Shamwowee:BAAANQADCgcIHwAAAA==.Shamzee:BAABNQAECn8sAAIBAAkKgx01IwDYAgABAAkKgx01IwDYAgAAAA==.Sheyy:BAAANQAECgEIAQAAAA==.Shiftybonez:BAAANQADCgQIBQAAAA==.Shintok:BAAANQAECgUICwAAAA==.Shuddarun:BAACNQAFFH8TAAIDAAcKCB6JAQB1AgADAAcKCB6JAQB1AgA1AAQKfyoAAgMACQq4JBINAHUDAAMACQq4JBINAHUDAAAA.',
Si='Silverbakk:BAAANQABCgEIAQAAAA==.Simn:BAAANQAECgYICwAAAA==.Sindraesong:BAAANQAECgUJCQAAAA==.',
Sk='Skithiryx:BAAANQAECgQIBAABNQAECgkJIwAKAD4bAA==.Skuldd:BAAANQABCgQIDQAAAA==.',
Sl='Slayvylora:BAAANQAECgQIBAABNQAFFAQICgANALkQAA==.',
Sm='Smarte:BAAANQAFFAEIAQABNQAFFAEIAQAMAAAAAA==.Smolderpally:BAAANQADCgYIBgAAAA==.',
Sn='Sneakymoth:BAAANQADCgUIBQABNQAECgUIDwAMAAAAAA==.Snookums:BAAANQAECgYIEAAAAA==.',
So='Soarin:BAAANQADCgQIBAAAAA==.',
Sp='Spicymaker:BAABNQAECn8bAAIFAAgKJByfUwCMAgAFAAgKJByfUwCMAgAAAA==.',
St='Starya:BAAANQAECgQICAAAAA==.Steelheart:BAAANQABCgQIBAAAAA==.Stop:BAAANQAECgMIAwAAAA==.Strifewood:BAAANQAECgYIBgAAAA==.Stumper:BAABNQAECn8jAAILAAgKFBU8MwBIAgALAAgKFBU8MwBIAgAAAA==.',
Su='Suluna:BAAANQABCgQIBAABNQAECggIPQABAJghAA==.Sux:BAAANQADCgMIAwAAAA==.',
Sy='Sybrina:BAABNQAECn8lAAIDAAgKIxLsbAA2AgADAAgKIxLsbAA2AgAAAA==.Sylvia:BAABNQAECn8eAAISAAkK+w+bwQD/AQASAAkK+w+bwQD/AQAAAA==.Syngeance:BAAANQAECgYIEAAAAA==.Synèsterwolf:BAAANQAECggICwAAAA==.',
['Sí']='Síf:BAAANQAECgEIAQAAAA==.',
Ta='Tadeusz:BAAANQAECgUIBwAAAA==.Taelah:BAAANQAECggIAQAAAA==.Tamamò:BAAANQADCgYICAAAAA==.Tanglefoot:BAABNQAECn8gAAIFAAgKFhIBfwAaAgAFAAgKFhIBfwAaAgAAAA==.Tanleros:BAAANQAECgcIEAAAAA==.Taquítos:BAAANQADCgYICAAAAA==.Tasigur:BAAANQAECgQIBAABNQAECgkJIwAKAD4bAA==.',
Te='Telana:BAAANQADCgcIHwAAAA==.Tequitos:BAAANQAECgYIEAAAAA==.Tessla:BAAANQADCgYIDAAAAA==.',
Th='Theduk:BAABNQAECn8iAAMkAAkK+Q7aHgDXAQAkAAgKYQ7aHgDXAQAlAAgKVAu3PwDIAQAAAA==.Theduke:BAAANQAECgQIBAAAAA==.Theliria:BAAANQADCgYIBgAAAA==.Thorias:BAABNQAECn8ZAAISAAgKKxu2jQBjAgASAAgKKxu2jQBjAgAAAA==.Thtime:BAABNQAECn8wAAISAAkKrCBlJABNAwASAAkKrCBlJABNAwAAAA==.',
To='Toira:BAAANQADCgUIBQAAAA==.Tomoko:BAAANQADCgYICQAAAA==.Torment:BAABNQAECn8qAAINAAgKBRqcNQAzAgANAAgKBRqcNQAzAgAAAA==.',
Tr='Tristén:BAAANQAECggIDQAAAA==.Truvie:BAAANQADCgMIAwAAAA==.',
Tu='Tumbled:BAAANQAECgYIEAAAAA==.Tumbles:BAAANQADCgQIBQAAAA==.Tumni:BAAANQAECgYICgAAAA==.',
Tw='Twinkletoes:BAAANQADCgYIBgAAAA==.',
['Tá']='Tángall:BAAANQABCgEIAQAAAA==.',
Ui='Ui:BAAANQADCgMIAwAAAA==.',
Ul='Ulnuk:BAABNQAECn8uAAIBAAgKiRr1QABaAgABAAgKiRr1QABaAgAAAA==.Ulster:BAAANQADCgEIAQAAAA==.',
Un='Ungodly:BAABNQAECn8hAAIdAAkK6w/FNgD3AQAdAAkK6w/FNgD3AQAAAA==.Unholyshan:BAAANQADCggIDAAAAA==.Unidus:BAAANQABCgUICAAAAA==.',
Uu='Uutr:BAAANQABCgEIAQAAAA==.',
Uv='Uvvolx:BAAANQADCgQICAAAAA==.',
Va='Vadka:BAAANQAECgMIBgAAAA==.Vaeldrin:BAAANQAECgQIBQAAAA==.Vaha:BAAANQAECgIIBQAAAA==.Valkree:BAAANQAECgUIDgAAAA==.Valsavis:BAABNQAECn8rAAIbAAgK+R8nBgC6AgAbAAgK+R8nBgC6AgAAAA==.',
Ve='Veaolop:BAAANQABCggIEAAAAA==.Vellagosa:BAAANQAECgMIBgAAAA==.Vernice:BAAANQADCgYICwABNQAECgUICAAMAAAAAA==.Verulan:BAAANQAECgUICgAAAA==.Vexidari:BAAANQAECgUICQABNQAFFAQICgANALkQAA==.Vexomous:BAABNQAECn8eAAMOAAgKgBqYBQBcAgAOAAgKgBqYBQBcAgAEAAQKDgdDWgC3AAABNQAFFAQICgANALkQAA==.',
Vi='Viiolet:BAAANQAECgYIBgAAAA==.',
Vo='Voidmayne:BAABNQAECn8iAAIGAAgKORKlnQDiAQAGAAgKORKlnQDiAQAAAA==.Vongogh:BAAANQADCgYICQAAAA==.Vonhelsing:BAAANQAECgQIBAAAAA==.',
Vy='Vynnara:BAAANQADCgEIAQAAAA==.Vyolent:BAAANQADCgYICwAAAA==.',
Wa='Wapello:BAAANQABCgcICgAAAA==.Warnox:BAAANQAECgIIAgAAAA==.',
We='Weiand:BAABNQAECn8dAAMHAAcK1wsajgBvAQAHAAcK1wsajgBvAQAGAAUKGhVp5QBKAQAAAA==.Wevark:BAAANQAECgcIEQAAAA==.',
Wh='Whatami:BAABNQAECn8dAAMeAAgKHhlKRQCAAgAeAAgKHhlKRQCAAgAfAAIKtQsaXgBoAAAAAA==.Wholemilk:BAAANQAECgUICAAAAA==.',
Wi='Wilhellena:BAABNQAECn8iAAIJAAgKNQ4aegCnAQAJAAgKNQ4aegCnAQAAAA==.Wilhellfu:BAAANQADCgMIAwAAAA==.Winariel:BAAANQAECggIEAAAAA==.Witewalker:BAAANQADCgcICgAAAA==.',
Wr='Writhesoul:BAAANQABCgIIAgABNQAECggIEAAMAAAAAA==.Wroughtsoul:BAAANQAECgYIDQAAAA==.Wrysoul:BAAANQAECggIEAAAAA==.',
Wy='Wynston:BAAANQADCgEIAQAAAA==.Wyrmheart:BAAANQADCgIIAwAAAA==.',
Xa='Xalatath:BAAANQADCgEIAQABNQAECggIIAAGAHodAA==.Xaldred:BAABNQAECn8cAAIeAAgKnA6fgwDYAQAeAAgKnA6fgwDYAQABNQAECgkJJgAUANgWAA==.Xandir:BAABNQAECn8WAAIVAAcKRhIiLwBhAQAVAAcKRhIiLwBhAQAAAA==.Xarhunt:BAAANQAECgEIAgAAAA==.',
Xe='Xenzia:BAAANQADCgcICwAAAA==.Xeracil:BAAANQADCgQICgAAAA==.',
Xo='Xoric:BAABNQAECn8nAAIiAAkKghXPGQBoAgAiAAkKghXPGQBoAgAAAA==.',
Xy='Xyal:BAABNQAECn8bAAIJAAcK3xZIbgDOAQAJAAcK3xZIbgDOAQAAAA==.Xyp:BAAANQADCgYIBgABNQAECgUICgAMAAAAAA==.',
Ya='Yamaya:BAAANQADCgMIBQAAAA==.',
Yi='Yiago:BAAANQAECgIIBAAAAA==.',
Yo='Youknow:BAAANQADCgcICwAAAA==.',
Za='Zaelia:BAAANQADCgEIAQAAAA==.Zary:BAAANQAECgIIAgAAAA==.Zaxhdk:BAEANQADCgMIAwABNQAECgcIFQAHAOoSAA==.Zaxhpal:BAEBNQAECn8VAAIHAAcK6hIUdQC1AQAHAAcK6hIUdQC1AQAAAA==.',
Ze='Zenedy:BAAANQAECgQIBAABNQAECgUICAAMAAAAAA==.',
Zi='Zid:BAAANQAECgMIAwAAAA==.Ziny:BAAANQADCgUIBQAAAA==.Ziparoo:BAABNQAECn8fAAITAAcKFQrkFABaAQATAAcKFQrkFABaAQAAAA==.',
Zo='Zoenova:BAAANQAECggIAgAAAA==.',
Zr='Zraven:BAAANQADCgEIAQAAAA==.',
['În']='Îniquitous:BAAANQAECgUIDgAAAA==.',
['Ðê']='Ðêmønicßløøð:BAABNQAECn8WAAMdAAgK8xFfTAB/AQAdAAYKyxRfTAB/AQAUAAMKggoTrwCQAAABNQAECggIHAAFAFAWAA==.',
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
