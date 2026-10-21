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

local lookup = {'Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Fury','Druid-Guardian','Paladin-Retribution','Paladin-Holy','Warrior-Arms','Warrior-Protection','Priest-Holy','DemonHunter-Devourer','Druid-Balance','Unknown-Unknown','DeathKnight-Blood','DeathKnight-Unholy','Hunter-Survival','Mage-Fire','Shaman-Enhancement','Warlock-Affliction','Warlock-Demonology','Mage-Arcane','Mage-Frost','Monk-Windwalker','Monk-Mistweaver','Paladin-Protection','Warlock-Destruction','Evoker-Preservation','Rogue-Assassination','Monk-Brewmaster','Priest-Shadow','DemonHunter-Vengeance','Druid-Feral','Druid-Restoration','DeathKnight-Frost','Evoker-Devastation','Rogue-Subtlety',}
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abigt:BAAANQADCgIIAQAAAA==.',
Ac='Acidsnow:BAAANQAECgQIBQAAAA==.',
Ad='Adalaidê:BAAANQAECgMIBQAAAA==.',
Ae='Aerynne:BAAANQADCggIIwAAAA==.',
Ai='Airie:BAABNQAECn8gAAMBAAgKzwjtNwAGAQABAAgKzwjtNwAGAQACAAIKOwThGwFYAAAAAA==.',
Ak='Akuso:BAAANQADCgIIAgAAAA==.',
Al='Alcohaulorc:BAAANQAECgQIBwAAAA==.Alert:BAAANQAECgEIAQAAAA==.Aloris:BAAANQAECgQICAAAAA==.Aloy:BAABNQAFFH8QAAMDAAQKwRcPEABaAQADAAQKwRcPEABaAQAEAAEKAABwKAAzAAAAAA==.Aluhx:BAAANQAECgMICQABNQAFFAUICgAFAFsTAA==.',
Am='Amednato:BAABNQAECn8XAAIGAAkK4QaYLAA0AQAGAAkK4QaYLAA0AQAAAA==.',
An='Anaeli:BAABNQAECn9DAAIBAAkKKSCIGwABAwABAAkKKSCIGwABAwAAAA==.Anastarian:BAAANQAECgEIAQAAAA==.Ancalagonn:BAAANQAECgcIDwAAAA==.Angita:BAAANQAECgQIBwAAAA==.Anklin:BAAANQADCgIIAgAAAA==.Annaris:BAACNQAFFH8ZAAIDAAcKOBwCAwA8AgADAAcKOBwCAwA8AgA1AAQKfy0AAwMACgqjJEMHAKIDAAMACQrqJUMHAKIDAAQACQrJGS0yALwBAAAA.Antipæn:BAECNQAFFH8JAAMHAAMKFSJpEwAfAQAHAAMKFSJpEwAfAQAIAAEKdCO9JQBlAAA1AAQKfz4AAwcACgowJaIEANQDAAcACgowJaIEANQDAAgACQrNITkLAG4DAAAA.',
Ap='Apologia:BAABNQAECn8oAAIHAAkKtx9wCABbAgAHAAkKtx9wCABbAgAAAA==.',
Aq='Aquaphobic:BAAANQAECgMICQABNQAFFAYIEgABAK0KAA==.',
Ar='Arcanoth:BAAANQADCgIIAgAAAA==.Ardicelia:BAAANQABCgUIBgAAAA==.Ares:BAABNQAECn8fAAIJAAkK2SP7HQBAAwAJAAkK2SP7HQBAAwAAAA==.Armorgorden:BAABNQAECn8tAAIKAAgKySIsBgAHAwAKAAgKySIsBgAHAwAAAA==.Aroviaa:BAABNQAECn8xAAILAAoK7Bg1QABqAgALAAoK7Bg1QABqAgAAAA==.Arpmek:BAABNQAECn8sAAIMAAoKjRFFDgBDAQAMAAoKjRFFDgBDAQAAAA==.Artemîs:BAAANQADCgIIAgAAAA==.',
As='Asharienne:BAABNQAECn8iAAIDAAgKXQ8QgAANAgADAAgKXQ8QgAANAgAAAA==.Ashlynne:BAAANQAECgYJCwAAAA==.',
Au='Audiobully:BAAANQAECgQIBAABNQAECgkJJwANADoUAA==.Auralynn:BAAANQAECgQJBAABNQAECgYJCwAOAAAAAA==.Auriella:BAABNQAECn8jAAMIAAoKVhCaMwAVAQAIAAoKVhCaMwAVAQAHAAIKsghm/wAxAAAAAA==.Aurtt:BAABNQAECn8uAAMPAAoKmxNJRQDlAQAPAAgKFRZJRQDlAQAQAAMKEAlaMwCPAAAAAA==.',
['Aö']='Aöb:BAAANQADCgQIBgAAAA==.',
Ba='Bahahaknight:BAABNQAECn8pAAIPAAgK4RQOEgBRAQAPAAgK4RQOEgBRAQAAAA==.Bahree:BAAANQADCgIIAgAAAA==.Bakhar:BAABNQAECn8cAAIRAAcK8h1eAgCAAQARAAcK8h1eAgCAAQAAAA==.Balora:BAAANQADCgcIEgAAAA==.Barnette:BAABNQAECn84AAISAAoK0hM6AAAaAgASAAoK0hM6AAAaAgAAAA==.Basyleus:BAAANQADCgEIAQAAAA==.',
Be='Beau:BAAANQAECgEIAQABNQAECgcIEgAOAAAAAA==.Belthos:BAABNQAECn8ZAAIHAAgKSBgceQA6AgAHAAgKSBgceQA6AgAAAA==.Benihime:BAAANQAECgEIAQAAAA==.Berristan:BAABNQAECn82AAMIAAoKRw73MgAYAQAIAAoKRw73MgAYAQAHAAEKegQ1/AA0AAAAAA==.Bestwingman:BAAANQADCgEIAQAAAA==.',
Bi='Bigdawgsteve:BAAANQADCgIIAgAAAA==.Bigmarv:BAAANQAECgUIDAAAAA==.Bittytigs:BAACNQAFFH8JAAIBAAMKwhfdFwDiAAABAAMKwhfdFwDiAAA1AAQKf0IAAwEACgr3Hp8UACgDAAEACgr3Hp8UACgDAAIAAQoAAGBOAScAAAAA.',
Bl='Blestemat:BAAANQADCgYIBwAAAA==.Bluewitchpa:BAAANQADCggIJwAAAA==.Blumangood:BAABNQAECn8oAAQCAAgKwxcbGQBbAQACAAgKwxcbGQBbAQABAAIKLQKKFQE/AAATAAEKAADnNwAwAAAAAA==.',
Bo='Bollux:BAAANQAECgEIAgAAAA==.Bosc:BAABNQAECn8aAAIPAAkK9xSyCwCMAQAPAAkK9xSyCwCMAQAAAA==.Boudiicca:BAAANQADCggIIwAAAA==.Boxmasterr:BAABNQAECn8xAAMUAAoKwRO+BQBeAgAUAAgKqBi+BQBeAgAVAAYKoAoULABEAQAAAA==.',
Br='Braagh:BAAANQABCggICwAAAA==.Brasmir:BAABNQAECn8nAAIRAAoKsBuSAABKAgARAAoKsBuSAABKAgAAAA==.Briae:BAAANQADCgMIAwABNQAECgkJQwABACkgAA==.Brianzero:BAAANQABCgQJBgAAAA==.Brino:BAAANQABCgQIBAAAAA==.Brinotriage:BAAANQABCgIIAgAAAA==.',
Bu='Bubblemoth:BAAANQADCgMIBAABNQAECgYIDwAOAAAAAA==.Buik:BAAANQAECgIIAgAAAA==.Bulge:BAABNQAECn8dAAMWAAoKNQsw0QDkAQAWAAoK0wow0QDkAQAXAAEK2Rb9PwBEAAABNQAFFAQIDgAQAGILAA==.Bulgogi:BAACNQAFFH8OAAIQAAQKYgunAwDRAAAQAAQKYgunAwDRAAA1AAQKfzEAAhAACgpuHU4hAMMCABAACgpuHU4hAMMCAAAA.',
['Bö']='Börk:BAAANQAECgQIBwAAAA==.',
Ca='Capy:BAAANQAECgIIAgABNQAFFAQIBgAXAOQUAA==.Cardran:BAAANQADCgIIAgABNQAECgkJFwADANsRAA==.Cayda:BAAANQADCgYJCQAAAA==.Caylara:BAAANQAECgMIBwAAAA==.Cayssaber:BAAANQAECgIIAgAAAA==.',
Ce='Ceicilia:BAAANQADCgQIBAAAAA==.Celrythis:BAAANQAECgMIBQAAAA==.Cenokry:BAAANQADCgQIBAAAAA==.',
Ch='Chai:BAABNQAECn8XAAMYAAgKmAyEGgDVAAAYAAgKmAyEGgDVAAAZAAEK1QGNVQAeAAAAAA==.Chaintrain:BAAANQAECgMIAwABNQAECgcIDgAOAAAAAA==.Chellyy:BAAANQAECgMIAwABNQAECgUIDQAOAAAAAA==.Chibisend:BAAANQADCgMIAwAAAA==.Chámeleon:BAAANQADCgEIAQAAAA==.',
Ci='Cider:BAAANQAECgIIAgAAAA==.',
Cl='Claes:BAAANQADCgMIAwABNQAECgkJGgAPAPcUAA==.',
Co='Coralbubbles:BAABNQAECn8lAAIHAAoKHRIQIQCfAQAHAAoKHRIQIQCfAQAAAA==.Coralorchid:BAABNQAECn8iAAIaAAYKtx4wBwCLAQAaAAYKtx4wBwCLAQAAAA==.Coralrages:BAAANQAECgMIBgAAAA==.',
Cr='Cromenockle:BAABNQAECn8UAAQUAAkKmBO+EwAPAQAVAAgKahIYhADcAQAUAAQKdw++EwAPAQAbAAIKuw4vWAB3AAABNQAFFAIIAwAOAAAAAA==.Crtitman:BAAANQAECgUICQAAAA==.',
Cu='Cupcâke:BAAANQAECgQIBAAAAA==.Curissan:BAAANQAECgYIEwAAAA==.',
Da='Dalgon:BAABNQAFFH8IAAIcAAQK6wRDEADvAAAcAAQK6wRDEADvAAABNQAFFAYIDQAIAK4UAA==.Dalir:BAAANQAECgUIDQAAAA==.Dalspin:BAAANQADCgYIDAABNQAFFAYIDQAIAK4UAA==.Dalthepal:BAACNQAFFH8NAAIIAAYKrhTvBwDnAQAIAAYKrhTvBwDnAQA1AAQKfzQAAggACgrVHjoXAB8DAAgACgrVHjoXAB8DAAAA.Damné:BAABNQAECn8xAAIQAAoKwxdaBAD+AQAQAAoKwxdaBAD+AQAAAA==.Darze:BAAANQADCggIAwABNQAECgUICAAOAAAAAA==.Davidline:BAABNQAECn8iAAIHAAoKXhsICgA+AgAHAAoKXhsICgA+AgAAAA==.',
De='Deadish:BAABNQAECn8xAAMPAAoKRBycAwAzAgAPAAkKcB+cAwAzAgAQAAEKDQaHXgASAAAAAA==.Deathsaberss:BAABNQAECn89AAMJAAoK4RfZQwC+AgAJAAoK4RfZQwC+AgAKAAQK5Au+KgDjAAAAAA==.Deathvex:BAACNQAFFH8PAAIPAAUKqRNcCQC7AAAPAAUKqRNcCQC7AAA1AAQKfxUAAg8ACAqhFhIUAEMBAA8ACAqhFhIUAEMBAAAA.Decoz:BAAANQAECgUICgAAAA==.Deight:BAAANQADCgIIAgAAAA==.Dejamoo:BAAANQADCgYIEwAAAA==.Dendahn:BAAANQAECgcIDQAAAA==.Destinee:BAAANQAECgQICwAAAA==.',
Di='Dianntha:BAAANQADCgcIFAAAAA==.Diladrin:BAABNQAECn9EAAIGAAoKhhj9AgAPAgAGAAoKhhj9AgAPAgAAAA==.Dinomight:BAAANQADCgQIBAAAAA==.',
Do='Doileag:BAAANQAECgUICgAAAA==.Doomgrave:BAAANQADCgEIAQAAAA==.Dora:BAAANQADCgYIBgABNQAECgUIFgAdAAAFAA==.Dottmatrix:BAAANQAECgIIBwAAAA==.Doubledowns:BAAANQAECgEIAQAAAA==.',
Dr='Dreadwing:BAAANQADCggIIwAAAA==.Druromu:BAAANQAECgMIBwAAAA==.',
Du='Dufs:BAACNQAFFH8RAAIBAAUK/iM7CQC9AQABAAUK/iM7CQC9AQA1AAQKfygAAgEACgqhH2wcAPwCAAEACgqhH2wcAPwCAAAA.Dunkan:BAAANQAECgMIAwAAAA==.Dustbunny:BAABNQAECn8wAAILAAkK4hTWIwByAQALAAkK4hTWIwByAQAAAA==.',
Dw='Dwagon:BAAANQAECgYIDwAAAA==.',
Dy='Dylsonlolqt:BAAANQAECggICwAAAA==.',
['Dã']='Dãrling:BAAANQABCgEIAQAAAA==.',
['Dû']='Dûn:BAABNQAECn8vAAMYAAoKmiDLDQAAAwAYAAoKUiDLDQAAAwAeAAgKNh4pCgB1AgAAAA==.Dûna:BAABNQAECn8hAAIfAAoKTBlGFADCAgAfAAoKTBlGFADCAgABNQAECgoKLwAYAJogAA==.',
El='Elaatia:BAABNQAECn8xAAIHAAoKjCMoCwAuAgAHAAoKjCMoCwAuAgAAAA==.Elidria:BAAANQABCgIIAgABNQADCgYIBgAOAAAAAA==.Ellysprocket:BAAANQADCgYICQAAAA==.Elrric:BAAANQAECgcICgAAAA==.Elyak:BAAANQADCgIIAgAAAA==.',
En='Envoy:BAAANQAECgMIAwAAAA==.',
Er='Erakron:BAABNQAECn8pAAMBAAkKIRnUpwAiAQABAAUKTxLUpwAiAQACAAkKbxE3JwAfAQAAAA==.Erine:BAAANQAECgIIAgAAAA==.Erouvi:BAAANQADCgIIAgABNQAECgoKMQALAOwYAA==.Eroviaa:BAAANQAECgUIBwABNQAECgoKMQALAOwYAA==.Erovvia:BAAANQADCgUIBQABNQAECgoKMQALAOwYAA==.',
Es='Esmeralda:BAAANQABCggIEAAAAA==.',
Ev='Evorik:BAAANQAECgQIBAABNQAFFAIIBQAJAH4TAA==.',
Ez='Ezothen:BAAANQAECgYIDgAAAA==.',
Fa='Facelessman:BAAANQABCggIJAAAAA==.Faedoria:BAAANQAECgQICAAAAA==.Faeryln:BAABNQAECn8yAAILAAoKYggaHgCOAQALAAoKYggaHgCOAQAAAA==.Fatalcheese:BAAANQABCgQIBAAAAA==.Faustus:BAAANQAECgcIEgAAAA==.Favion:BAAANQADCgEIAQAAAA==.',
Fe='Felyyia:BAAANQAECgcIEgABNQAFFAcIGQADADgcAA==.Feyox:BAAANQADCggICAAAAA==.',
Fi='Fiddlestix:BAAANQAECgQIBAAAAA==.Firebrande:BAAANQAECgQIBwAAAA==.Fisticuffs:BAAANQADCggIJQAAAA==.Fizcrankshot:BAABNQAECn8xAAIDAAoK3RKFCAA9AgADAAoK3RKFCAA9AgAAAA==.',
Fl='Flamewhisker:BAAANQAECgQIBwAAAQ==.Flamez:BAAANQADCgcIBwAAAA==.Flandre:BAAANQAECgUIBAAAAA==.',
Fr='Fraublucher:BAABNQAECn8mAAILAAcK3QgAOwAYAQALAAcK3QgAOwAYAQAAAA==.Frewyn:BAAANQAECgUIDQAAAA==.Frostimoth:BAAANQAECgYIDwAAAA==.Frozty:BAAANQAECgQIBgAAAA==.',
Ga='Galandel:BAAANQADCggIIgAAAA==.Galial:BAACNQAFFH8IAAIgAAIKJRLaAQB9AAAgAAIKJRLaAQB9AAA1AAQKfzEAAiAACgpYGQwHAKACACAACgpYGQwHAKACAAAA.Gantar:BAAANQAECgUIBQABNQAECgoKKQAPAA0jAA==.Garradin:BAAANQADCgEIAQAAAA==.Garrunter:BAAANQAECgEIAgAAAA==.Gaznol:BAAANQADCgQIBAABNQAECgkJFwAGAOEGAA==.',
Ge='Gelasera:BAAANQAECgQIBgAAAA==.Gemitra:BAAANQADCgcIBwABNQAECgYIIgAaALceAA==.Geneth:BAAANQAECgUIBQAAAA==.George:BAACNQAFFH8FAAIJAAIKfhPSLgCPAAAJAAIKfhPSLgCPAAA1AAQKfyUAAgkACAr6HrVYAIECAAkACAr6HrVYAIECAAAA.',
Gh='Ghalta:BAAANQADCgIIAgABNQAECgoKKgAMANQZAA==.Ghrol:BAAANQABCgYIBgABNQAECgoKMwABAOsaAA==.',
Gl='Glaivethras:BAABNQAECn8vAAIgAAoKFx+EAAC1AgAgAAoKFx+EAAC1AgAAAA==.Glenfin:BAAANQADCgQIBgAAAA==.',
Gr='Greg:BAAANQADCgUIDgABNQADCggIGgAOAAAAAA==.Gremlynn:BAAANQADCggICAAAAA==.Grimclaw:BAACNQAFFH8JAAMhAAUKawfdAgC3AAANAAQKawfdFgD7AAAhAAIKAADdAgC3AAA1AAQKfyQAAyEACgofJQkGAFcBAA0ACAqVIsseANQCACEABgrTJQkGAFcBAAAA.Groot:BAABNQAECn8UAAMiAAQKLBfwQgATAQAiAAQKLBfwQgATAQANAAMK8wy4PABrAAABNQAECgkJHQAaAFYQAA==.',
Gu='Guthrek:BAAANQAECgcIBwAAAA==.',
Ha='Hamfist:BAAANQADCgIIAgABNQAECggJDAAOAAAAAA==.Hannebal:BAABNQAECn8hAAIIAAoKIxNGBQCFAgAIAAoKIxNGBQCFAgAAAA==.',
He='Healsonyou:BAAANQAECgUIBQABNQAECgoKIgAJAMEUAA==.Healyclam:BAAANQADCgMIAwAAAA==.Heydaw:BAAANQADCggICAABNQAECgkJGAAjAJUbAA==.Heynow:BAAANQAECgUICAAAAA==.',
Hi='Higherp:BAAANQADCggICAABNQAECgcIHAAhACgRAA==.Highmountain:BAAANQADCggIDQAAAA==.Hilimed:BAABNQAECn80AAIVAAoKvQmGFQCgAQAVAAoKvQmGFQCgAQAAAA==.',
Ho='Hobs:BAAANQADCgUIBQAAAA==.Holyßloodelf:BAAANQAECgcIDgABNQAECgoKIgAJAMEUAA==.Hoosier:BAAANQAECgQICQAAAA==.Hoplite:BAAANQAECgcIEQAAAA==.',
Hu='Huasca:BAAANQAECgEIAQAAAA==.Huthuel:BAAANQABCggIFAAAAA==.',
Hy='Hydra:BAAANQADCgYIBgABNQAECgoKIgAWANsOAA==.Hyve:BAAANQADCgcIJQABNQAECgkJMgAaADAZAA==.',
['Hà']='Hàney:BAEANQAECgQIBAAAAA==.',
['Hé']='Hélio:BAAANQADCgUIBQAAAA==.',
Ia='Ia:BAABNQAECn8rAAIjAAoKsh7UCwA4AwAjAAoKsh7UCwA4AwAAAA==.',
Ib='Ibesneakin:BAAANQADCggIDgABNQAECggJDAAOAAAAAA==.',
Id='Idontsuck:BAAANQADCggICwAAAA==.',
Il='Ileynha:BAAANQAECgQIBgAAAA==.Ilieau:BAAANQAECgQIBQABNQAECgoKHgARAMsgAA==.Illida:BAAANQADCgYIBgAAAA==.',
Im='Imamalelol:BAAANQAECgUICwAAAA==.',
In='Inarrah:BAAANQADCgEIAQAAAA==.Intol:BAAANQAFFAUIDQAAAQ==.Intrepidhero:BAAANQADCgEIAQAAAA==.',
Ir='Irkenfox:BAECNQAFFH8RAAIKAAUKXhVyAQDHAAAKAAUKXhVyAQDHAAA1AAQKfykAAgoACgq9IqQCAIYDAAoACgq9IqQCAIYDAAAA.',
It='Ithran:BAAANQADCgUIBQAAAA==.',
Iw='Iwilltank:BAAANQADCgYICwAAAA==.',
Ix='Ixitt:BAABNQAECn8qAAISAAoKqBg9AgA6AgASAAoKqBg9AgA6AgAAAA==.',
Ja='Jama:BAAANQADCgYIBgAAAA==.Janderick:BAAANQAECgYIDgAAAA==.Jaromer:BAAANQADCgcICgAAAA==.',
Je='Jellacee:BAAANQADCgcIFwAAAA==.',
Ji='Jimboberjim:BAACNQAFFH8RAAIbAAUKQR64AAB9AQAbAAUKQR64AAB9AQA1AAQKfy0AAhsACgpUI2wBAHsDABsACgpUI2wBAHsDAAAA.Jimbobwhey:BAAANQAECgcIDgABNQAECggIHgAKAD8TAA==.Jiminie:BAABNQAECn8eAAIKAAgKPxMdFgDHAQAKAAgKPxMdFgDHAQAAAA==.',
Jo='Jolio:BAAANQAECgcIDgAAAA==.Joltraxi:BAAANQADCggICAABNQAECgcIDgAOAAAAAA==.Joshie:BAABNQAECn8pAAIPAAoKDSPoCQBmAwAPAAoKDSPoCQBmAwAAAA==.Joshy:BAAANQADCgcIBwABNQAECgoKKQAPAA0jAA==.',
Ju='Jujubeans:BAAANQAECgEIAQAAAA==.Juniornite:BAABNQAECn8xAAIWAAkK1yAuDAAOAgAWAAkK1yAuDAAOAgAAAA==.Justthetouch:BAAANQAECgQIBAAAAA==.',
Jy='Jygglypuff:BAAANQAECgMIBAAAAA==.',
Ka='Kadaan:BAAANQAECgUIBQAAAA==.Kagemaro:BAABNQAECn8qAAMMAAoK1BlBFQC7AgAMAAoK1BlBFQC7AgAgAAUKdRS7GQAZAQAAAA==.Kahgar:BAAANQAECgYIFgABNQAECgoKSwAIAFIWAQ==.Kalimathath:BAAANQAECgEIAQAAAA==.Kalzod:BAABNQAECn9CAAIVAAoK+yScAABJAwAVAAoK+yScAABJAwAAAA==.Kataki:BAABNQAECn8dAAIDAAkK8hVsXQBdAgADAAkK8hVsXQBdAgABNQAECgoKKgAMANQZAA==.Katia:BAAANQAECgIIBQAAAA==.Kativeria:BAAANQAECgMIBQAAAA==.Katjayna:BAAANQADCgUICgAAAA==.Kaysabr:BAAANQAECgUIBQAAAA==.Kayssaber:BAABNQAECn8aAAMiAAgKiBP4BwC+AQAiAAgKiBP4BwC+AQANAAMK5BDvjwCXAAAAAA==.',
Ke='Kebab:BAAANQAECgQJBAAAAA==.Kelsifer:BAAANQAECgQICwABNQAECgcIEgAOAAAAAA==.Kempra:BAAANQADCgcIBwAAAA==.Kemprei:BAAANQADCgUIBQAAAA==.Kendralust:BAAANQAECgcICAAAAA==.Kerfufle:BAAANQABCgIJAgAAAA==.',
Kh='Khaos:BAAANQABCgEIAQAAAA==.',
Ki='Killmora:BAAANQADCggIJwAAAA==.Kippars:BAAANQAECgEIAQAAAA==.',
Kl='Klaax:BAAANQADCgYIBgABNQAECgkJMgAaADAZAA==.',
Ko='Kodazoff:BAAANQAECgcIEAAAAA==.Kora:BAAANQABCgEIAgAAAA==.Korevash:BAABNQAECn80AAMBAAoKZCP9AwCrAwABAAoKZCP9AwCrAwATAAYKAhJaHACeAQAAAA==.',
Kr='Krezz:BAAANQAECgEIAQAAAA==.Krissylu:BAAANQAECgUIDQAAAA==.Krothix:BAABNQAECn8vAAICAAkKMgfrHwA8AQACAAkKMgfrHwA8AQAAAA==.Krudd:BAAANQAECgcIDQAAAA==.Krychilly:BAAANQADCgYIEQAAAA==.Kryrande:BAAANQADCgQICwAAAA==.Kryshym:BAAANQAECgUIEgAAAA==.Krythrall:BAAANQADCgUIBQABNQAECgUIEgAOAAAAAA==.Kryvelen:BAAANQAECgUICQAAAA==.Krëëp:BAAANQAECggICAAAAA==.',
Ks='Kspectactle:BAAANQAECgMIBAAAAA==.',
Ku='Kuilei:BAAANQADCgYJCwABNQAECgIIBgAOAAAAAA==.Kurorø:BAAANQAECgMIBwAAAA==.',
Ky='Kyrayna:BAAANQADCgUIDAAAAA==.',
La='Ladara:BAABNQAECn8oAAIUAAkKixQxBgBPAgAUAAkKixQxBgBPAgAAAA==.Laima:BAAANQADCgUICQAAAA==.Landil:BAAANQADCgYIBgAAAA==.Lavitz:BAAANQAECgEIAQAAAA==.',
Le='Leheo:BAAANQAECgEIAQAAAA==.Lehua:BAAANQADCggICgAAAA==.Leilanii:BAAANQADCgcIEQAAAA==.Lemook:BAABNQAECn8ZAAIiAAcK3BM+EABHAQAiAAcK3BM+EABHAQAAAA==.Leonìdas:BAAANQADCgcIEQAAAA==.Leð:BAAANQAECggICAAAAA==.',
Li='Licker:BAAANQAECgUICQABNQAFFAIIAwAOAAAAAA==.Life:BAAANQADCgIIAgAAAA==.Lightbulb:BAAANQADCgYIDQAAAA==.Lightsorrow:BAAANQAECgIIAwAAAA==.Lightstormer:BAAANQADCgcIHwAAAA==.Lilamae:BAAANQAECgQIDAAAAA==.Lilarielle:BAABNQAECn8tAAIhAAYKgAbnEgCLAAAhAAYKgAbnEgCLAAAAAA==.Lildookie:BAAANQAECgcIDgAAAA==.Lilface:BAAANQAECggICgAAAA==.Lilhands:BAAANQAECgMIAwAAAA==.Liliel:BAAANQADCgMIAwABNQAECgkJFwADANsRAA==.Liliela:BAABNQAECn8XAAIDAAkK2xGuaABCAgADAAkK2xGuaABCAgAAAA==.Lilyannah:BAAANQADCgEIAQAAAA==.Liodragon:BAAANQADCgUIBQABNQAECgcICgAOAAAAAA==.Liolock:BAAANQAECggIBwAAAA==.Lite:BAAANQAECgQIBAAAAA==.Liø:BAAANQAECgcICgAAAA==.',
Ll='Lluniez:BAABNQAECn8VAAIYAAkK8w3+LgCgAQAYAAkK8w3+LgCgAQAAAA==.',
Lm='Lmccoy:BAAANQABCgQIBAAAAA==.',
Lo='Lockroknroll:BAAANQAECggJDAAAAA==.Losoli:BAABNQAECn8xAAIIAAkKRh3KDwDaAQAIAAkKRh3KDwDaAQAAAA==.Lotor:BAAANQADCgYIBgAAAA==.Lowchin:BAAANQAECgQIBQAAAA==.',
Lu='Lupine:BAAANQADCgYIBgABNQAECgUIBQAOAAAAAA==.Lutherion:BAABNQAECn8qAAIKAAoKgx0CAgAGAgAKAAoKgx0CAgAGAgAAAA==.',
Ly='Lycemmas:BAABNQAECn8iAAIBAAoKzRisHQB0AQABAAoKzRisHQB0AQAAAA==.',
['Lï']='Lïo:BAAANQADCgYIBwABNQAECgcICgAOAAAAAA==.',
Ma='Macoun:BAABNQAECn8aAAIDAAkKsyFdBQB6AgADAAkKsyFdBQB6AgAAAA==.Magicshowers:BAABNQAECn8xAAIWAAoKkyKGCQAyAgAWAAoKkyKGCQAyAgAAAA==.Manseed:BAAANQABCgQJBAAAAA==.Maple:BAAANQAECgUIBQAAAA==.Martei:BAACNQAFFH8PAAIhAAUKcRTCAQBJAQAhAAUKcRTCAQBJAQA1AAQKfygAAiEACgpPHDsHAO8CACEACgpPHDsHAO8CAAAA.Maríneth:BAAANQAECgMIBwAAAA==.Mascara:BAAANQAECgYICwAAAA==.Maxe:BAAANQADCgIIAgAAAA==.',
Me='Memebait:BAAANQAECgUIBQAAAA==.Mementomori:BAAANQADCgMIAwAAAA==.Meowbae:BAAANQAECgUIBQABNQAECgQIBgAOAAAAAA==.Merce:BAAANQADCgcIBwABNQAECgkJFwADANsRAA==.Mercesdes:BAAANQADCgEIAQAAAA==.',
Mi='Midway:BAAANQAECgQIBgAAAA==.Minizee:BAAANQAECgEIAQAAAA==.Mirokushan:BAAANQADCggIIwABNQAECgMIAwAOAAAAAA==.Missfire:BAAANQAECgIIAwAAAA==.Misticlady:BAAANQAECgQIBgAAAA==.Mistrariel:BAAANQADCggICwABNQAECgkJFAAbAPsWAA==.Mizukì:BAAANQABCgQIBgAAAA==.',
Mo='Moluubar:BAABNQAECn8dAAMJAAoKGBOWNQA+AQAJAAoKGBOWNQA+AQAKAAEKAABlKQAAAAAAAA==.Moradin:BAAANQADCgMIAwAAAA==.Mordemour:BAAANQAECgUICAAAAA==.',
Mu='Mufler:BAAANQABCgQIBQAAAA==.Mungo:BAAANQAECgYICQAAAA==.Mushù:BAAANQAECgUICgABNQAECgoKIgAVAGEXAA==.',
My='Myfire:BAAANQADCgYIBgAAAA==.Myrell:BAAANQAECggICAAAAA==.Myrrh:BAAANQAECgYIDwAAAA==.',
Na='Nalik:BAAANQAECgUIDQAAAA==.Nanou:BAAANQAECgUIBwAAAA==.Nardiaun:BAAANQADCgYIBgAAAA==.Naturebait:BAAANQADCgQIBAABNQAECggIKAACAMMXAA==.',
Ni='Nicety:BAAANQAECgMIAwAAAA==.Nimravidae:BAABNQAECn8pAAIIAAgK5BiDGwCBAQAIAAgK5BiDGwCBAQAAAA==.Ninelives:BAAANQAECgUIDQAAAA==.Nitecrawler:BAAANQADCgQIBAAAAA==.Niteeye:BAAANQABCgIIAgABNQAECgkJMQAWANcgAA==.Niteryu:BAAANQAECgEIAwABNQAECgkJMQAWANcgAA==.',
No='Nolokkotal:BAABNQAECn8iAAIJAAoKwRSHPAAsAQAJAAoKwRSHPAAsAQAAAA==.Nospitfisty:BAAANQADCgQIBAAAAA==.Noxolon:BAABNQAECn8UAAMFAAgKxQyIFABXAQAFAAgKxQyIFABXAQAJAAEKAADYWwErAAAAAA==.',
Nr='Nreaf:BAACNQAFFH8HAAIHAAQK7QjxFQD/AAAHAAQK7QjxFQD/AAA1AAQKfyQAAgcACgqHE7uHABgCAAcACgqHE7uHABgCAAAA.',
Oi='Oili:BAACNQAFFH8MAAIXAAUKZg8oAQDaAAAXAAUKZg8oAQDaAAA1AAQKfy0AAxcACgoDGdcHAG0CABcACgoDGdcHAG0CABYABAoADs9zAdcAAAAA.',
Ol='Olarrick:BAAANQAECgQIBQABNQAFFAIIBQAJAH4TAA==.',
Oo='Oops:BAACNQAFFH8NAAIPAAQKjRtFEgAzAQAPAAQKjRtFEgAzAQA1AAQKfy8AAg8ACgqSIHERACEDAA8ACgqSIHERACEDAAAA.',
Or='Orcchopped:BAAANQADCgQIBAAAAA==.Ornstein:BAAANQAECgQICwAAAA==.',
Ot='Ottuk:BAACNQAFFH8FAAIQAAIKFgmAGgCGAAAQAAIKFgmAGgCGAAA1AAQKfysAAhAACQrNIJMfAM4CABAACQrNIJMfAM4CAAAA.',
Pa='Padpaw:BAAANQAECgUJCAAAAA==.Pakraxes:BAABNQAECn8sAAIkAAgKrxCbFQDyAQAkAAgKrxCbFQDyAQAAAA==.Paksenarrion:BAABNQAECn8pAAIaAAgKrg4wDQAwAQAaAAgKrg4wDQAwAQAAAA==.Palehoof:BAAANQADCggIGgAAAA==.Pallywaya:BAAANQAECggICQAAAA==.Pandemonîum:BAAANQAECgQIBAABNQAFFAEIAQAOAAAAAA==.Pandemônium:BAAANQADCgMIAwABNQAFFAEIAQAOAAAAAA==.Pandemönium:BAABNQAECn8gAAMHAAgKeh0fVgCTAgAHAAgKUh0fVgCTAgAaAAIKzRxTUwCXAAABNQAFFAEIAQAOAAAAAA==.Pandemöniüm:BAAANQAFFAEIAQAAAA==.Patchington:BAAANQAECgIIBwAAAA==.Pañdemönium:BAAANQAECgUICgABNQAFFAEIAQAOAAAAAA==.',
Pe='Pepperrjakk:BAAANQADCgEIAQAAAA==.Perck:BAAANQADCgYIBgAAAA==.Perrylee:BAAANQAECgQICwAAAA==.',
Ph='Philia:BAABNQAECn8XAAMJAAgKmRWwnADVAQAJAAgKFhKwnADVAQAKAAMK9Rp5KwDdAAABNQAFFAQIEAADAMEXAA==.',
Pi='Pixelme:BAABNQAFFH8GAAIEAAIKcASBHwB4AAAEAAIKcASBHwB4AAAAAA==.',
Pl='Pleggster:BAAANQAECgcIDAAAAA==.',
Po='Pochula:BAAANQAECgUICwAAAA==.',
Pr='Primo:BAABNQAECn9LAAIIAAoKUhYoRABVAgAIAAoKUhYoRABVAgAAAA==.Protricity:BAABNQAECn8YAAMfAAoKUBaiJAALAgAfAAgKmBSiJAALAgALAAcKvBRQYQCuAAAAAA==.',
Ps='Psalms:BAAANQAECgQIAwABNQAECgQIBwAOAAAAAA==.Psychoprowla:BAABNQAECn8wAAIfAAkKWQ8NCQBkAQAfAAkKWQ8NCQBkAQAAAA==.Psychozdrood:BAAANQAECgEIAQAAAA==.',
['Pä']='Pändemönium:BAAANQAECgYICQABNQAFFAEIAQAOAAAAAA==.',
['Pæ']='Pæn:BAEANQAFFAIIAgABNQAFFAMICQAHABUiAA==.',
Qu='Quantar:BAAANQADCgYIBgABNQAECgcICQAOAAAAAA==.Quickstab:BAAANQAECgQICAAAAA==.',
Ra='Ragana:BAAANQAECggIDwAAAA==.Rainger:BAAANQADCgMIAwAAAA==.Rallypaly:BAAANQADCgIIAgAAAA==.Ramthor:BAAANQAECgUIBgAAAA==.Rancooll:BAAANQADCggIIgAAAA==.Rasniir:BAABNQAECn8oAAIiAAgK1RWnIAAkAgAiAAgK1RWnIAAkAgAAAA==.Rasputea:BAAANQABCgEIAQAAAA==.Ravenar:BAAANQAECgQIBAAAAA==.Ravenlash:BAAANQABCgcICwAAAA==.',
Re='Regna:BAACNQAFFH8OAAMJAAUK9yBOBgAYAQAJAAQK9yBOBgAYAQAFAAMKSR1tAgDBAAA1AAQKfy0AAwkACgpnJSsbAEsDAAkACQr+IysbAEsDAAUABQrfI1wQAKEBAAAA.Relkon:BAAANQADCgMIAwAAAA==.Remaked:BAACNQAFFH8hAAIeAAYKdxqkAQAAAgAeAAYKdxqkAQAAAgA1AAQKfzwAAh4ACgrgICIEADsDAB4ACgrgICIEADsDAAAA.Requinix:BAABNQAECn8yAAIDAAkKsBUHDwD4AQADAAkKsBUHDwD4AQAAAA==.Retro:BAAANQADCggIDgAAAA==.Reynmaker:BAAANQADCgQIBAAAAA==.',
Rh='Rhowyn:BAAANQADCgQICAAAAA==.',
Ri='Riptidez:BAAANQADCgYIBgAAAA==.Ririko:BAABNQAECn8pAAILAAgKWQrOJwBfAQALAAgKWQrOJwBfAQAAAA==.Ritzo:BAABNQAECn8pAAIFAAgKDBgQAwCiAQAFAAgKDBgQAwCiAQAAAA==.',
Ro='Robval:BAAANQABCgIIAgAAAA==.Rocksanne:BAAANQAECgQIBAAAAA==.Rooguee:BAAANQAECgIIAwAAAA==.',
Ru='Rukkis:BAABNQAECn8qAAMlAAoKzBoCCgCVAQAdAAgKDxcMKgBEAgAlAAkKhhoCCgCVAQAAAA==.Rukâ:BAAANQADCggIIAAAAA==.Rumi:BAABNQAECn9CAAIgAAoKkBvQAAB8AgAgAAoKkBvQAAB8AgAAAA==.',
Ry='Ryeekan:BAAANQAECggIDAAAAA==.Ryuma:BAAANQAECgYIDwAAAA==.Ryumar:BAAANQAECgMIAwAAAA==.',
Sa='Sabrosura:BAABNQAECn8dAAIaAAkKVhDlJwCfAQAaAAkKVhDlJwCfAQAAAA==.Saiyan:BAAANQADCgIIAgAAAA==.Salsinor:BAAANQADCgYICwAAAA==.Sanosagara:BAAANQAECggIBgAAAA==.Sathari:BAABNQAECn8pAAIMAAgKSRHnDQBGAQAMAAgKSRHnDQBGAQAAAA==.',
Sc='Schaden:BAAANQAECgQIBwAAAA==.Scripter:BAAANQADCgUIBgAAAA==.',
Se='Seijo:BAAANQAECgEJAQAAAA==.Sekk:BAABNQAECn8yAAMaAAkKMBltCgBTAQAHAAkKMBkIZwBmAgAaAAYKURVtCgBTAQAAAA==.Selecta:BAAANQAECgEIAQAAAA==.Selexi:BAAANQADCggICAAAAA==.Selithira:BAAANQAECgYIEgAAAA==.Sephylon:BAAANQADCgEIAQAAAA==.Sera:BAAANQADCgYICgAAAA==.',
Sh='Shabagnarang:BAAANQAECgQIDAABNQAECgkJKAAPAD4eAA==.Shadeofdark:BAAANQAECgcIEQAAAA==.Shalasyr:BAAANQAECgEIAgAAAA==.Shaletaz:BAAANQABCgQIBgAAAA==.Shamwowee:BAAANQADCggIJwAAAA==.Shamzee:BAACNQAFFH8GAAIBAAMKixJNCgDaAAABAAMKixJNCgDaAAA1AAQKfzAAAgEACgqlHacjANgCAAEACgqlHacjANgCAAAA.Shandalf:BAAANQAECgMIAwAAAA==.Sheyy:BAAANQAECgEIAQAAAA==.Shiftybonez:BAAANQADCgQIBQAAAA==.Shintok:BAAANQAECgUICwAAAA==.Shuddarun:BAACNQAFFH8UAAIDAAcKCB6rAQB0AgADAAcKCB6rAQB0AgA1AAQKfy8AAgMACgrIJF8NAHQDAAMACgrIJF8NAHQDAAAA.',
Si='Silverbakk:BAAANQABCgEIAQAAAA==.Simn:BAAANQAECgYICwAAAA==.Sindraesong:BAAANQAECgUJCQAAAA==.',
Sk='Skithiryx:BAAANQAECgQIBAABNQAECgoKKgAMANQZAA==.',
Sl='Slayvylora:BAAANQAECgQIBAABNQAFFAUIDwAPAKkTAA==.',
Sm='Smarte:BAAANQAFFAIIAwAAAA==.Smolderpally:BAAANQADCgYIBgAAAA==.',
Sn='Sneakymoth:BAAANQADCgUIBQABNQAECgYIDwAOAAAAAA==.Snookums:BAABNQAECn8XAAIMAAcK4RaTBwCVAQAMAAcK4RaTBwCVAQAAAA==.',
So='Soarin:BAAANQADCgQIBAAAAA==.',
Sp='Spicymaker:BAABNQAECn8gAAIJAAoKeBuYHwCFAQAJAAoKeBuYHwCFAQAAAA==.',
St='Starya:BAAANQAECgQICAAAAA==.Steelheart:BAAANQABCgQIBAAAAA==.Stolensøul:BAAANQABCggICwAAAA==.Stop:BAAANQAECgMIAwAAAA==.Strifewood:BAAANQAECgcIBgAAAA==.Stumper:BAABNQAECn8nAAINAAkKOhTDMwBIAgANAAkKOhTDMwBIAgAAAA==.',
Su='Suluna:BAAANQABCgQIBAABNQAECgkJQwABACkgAA==.Sux:BAAANQADCgMIAwAAAA==.',
Sy='Sybrina:BAABNQAECn8pAAIDAAgKIxKbbgA1AgADAAgKIxKbbgA1AgAAAA==.Sylvia:BAABNQAECn8iAAIWAAoK2w73XwD9AAAWAAoK2w73XwD9AAAAAA==.Syngeance:BAABNQAECn8WAAIDAAYKPwVVYgDmAAADAAYKPwVVYgDmAAAAAA==.Synèsterwolf:BAAANQAECggICwAAAA==.',
['Sí']='Síf:BAAANQAECgEIAQAAAA==.',
Ta='Tadeusz:BAAANQAECgUIBwAAAA==.Taelah:BAAANQAECggIAQAAAA==.Tamamò:BAAANQADCgYICAAAAA==.Tanglefoot:BAABNQAECn8gAAIJAAgKFhKHgAAaAgAJAAgKFhKHgAAaAgAAAA==.Tanleros:BAABNQAECn8aAAIIAAgKQhVyVwATAgAIAAgKQhVyVwATAgAAAA==.Taquítos:BAAANQADCgYICAAAAA==.Tasigur:BAAANQAECgQIBAABNQAECgoKKgAMANQZAA==.',
Te='Telana:BAAANQADCggIJwAAAA==.Tentación:BAAANQADCggICAABNQAECgkJHQAaAFYQAA==.Tequitos:BAAANQAECgcIEAAAAA==.',
Th='Theduk:BAABNQAECn8mAAMdAAoKEg6NGwDvAAAlAAgKYQ4zHwDXAQAdAAkK4QqNGwDvAAAAAA==.Theduke:BAAANQAECgQIBAAAAA==.Theliria:BAAANQADCgYIBgAAAA==.Thorias:BAABNQAECn8ZAAIWAAgKKxtkjgBiAgAWAAgKKxtkjgBiAgAAAA==.',
To='Toira:BAAANQADCgUIBQAAAA==.Tomoko:BAAANQADCgYICQAAAA==.Torment:BAABNQAECn8sAAIPAAkKQRgyNgAzAgAPAAkKQRgyNgAzAgAAAA==.',
Tr='Tristén:BAAANQAECggIEgAAAA==.Truvie:BAAANQADCgMIAwAAAA==.',
Tu='Tumbled:BAABNQAECn8VAAIWAAcKYhGF5QC+AQAWAAcKYhGF5QC+AQAAAA==.Tumbles:BAAANQADCgQIBQAAAA==.Tumni:BAAANQAECgYIDQAAAA==.',
Tw='Twinkletoes:BAAANQADCgYIBgAAAA==.',
['Tá']='Tángall:BAAANQABCgEIAQAAAA==.',
Ui='Ui:BAAANQADCgMIAwAAAA==.',
Ul='Ulnuk:BAABNQAECn8zAAIBAAoK6xpcIwBYAQABAAoK6xpcIwBYAQAAAA==.Ulster:BAAANQADCgEIAQAAAA==.',
Un='Ungodly:BAABNQAECn8mAAIjAAoK3BDJNwD3AQAjAAoK3BDJNwD3AQAAAA==.Unholyshan:BAAANQAECgIIAgABNQAECgMIAwAOAAAAAA==.Unidus:BAAANQAECgEIAQAAAA==.',
Uu='Uutr:BAAANQABCgEIAQAAAA==.',
Uv='Uvvolx:BAAANQADCgQICAAAAA==.',
Va='Vadka:BAAANQAECgQICAAAAA==.Vaeldrin:BAAANQAECgQIBQAAAA==.Vaha:BAAANQAECgIIBgAAAA==.Valkree:BAAANQAECgUIDgAAAA==.Valroc:BAAANQADCgYIBgAAAA==.Valsavis:BAABNQAECn8xAAIgAAoKUR6+AQDiAQAgAAoKUR6+AQDiAQAAAA==.Valtier:BAAANQADCgMIAwAAAA==.',
Ve='Vellagosa:BAAANQAECgQIBwAAAA==.Vernice:BAAANQADCgYICwABNQAECgUICAAOAAAAAA==.Verulan:BAAANQAECgUIDQAAAA==.Vexidari:BAAANQAECgUICQABNQAFFAUIDwAPAKkTAA==.Vexomous:BAABNQAECn8eAAMRAAgKgBqrBQBbAgARAAgKgBqrBQBbAgAEAAQKDgdTWwC3AAABNQAFFAUIDwAPAKkTAA==.',
Vi='Viiolet:BAAANQAECgYIBgAAAA==.',
Vo='Voidmayne:BAABNQAECn8oAAIHAAoKHRRKJQCQAQAHAAoKHRRKJQCQAQAAAA==.Vongogh:BAAANQADCgYICQAAAA==.Vonhelsing:BAAANQAECgQIBAAAAA==.',
Vy='Vynnara:BAAANQADCgEIAQAAAA==.Vyolent:BAAANQADCgYICwAAAA==.',
Wa='Wapello:BAAANQABCgcIDAAAAA==.Warnox:BAAANQAECgIIAgAAAA==.',
We='Weiand:BAABNQAECn8kAAMIAAcKFgx5jwBvAQAIAAcKFgx5jwBvAQAHAAcKxxKETAArAQAAAA==.Wevark:BAABNQAECn8WAAIJAAgKoQpqtQCXAQAJAAgKoQpqtQCXAQAAAA==.',
Wh='Whatami:BAABNQAECn8iAAMVAAoKYRedRgB/AgAVAAoKYRedRgB/AgAbAAIK4QyfXgBoAAAAAA==.Whiteknight:BAAANQADCgQIBgABNQAECgoKIgAVAGEXAA==.Wholemilk:BAAANQAECgUIDQAAAA==.',
Wi='Wilhellena:BAABNQAECn8oAAILAAoKhw2wOAAfAQALAAoKhw2wOAAfAQAAAA==.Wilhellfu:BAAANQADCgMIAwAAAA==.Winariel:BAABNQAECn8UAAIbAAkK+xZLBQDGAgAbAAkK+xZLBQDGAgAAAA==.Witewalker:BAAANQADCgcICgAAAA==.',
Wr='Writhesoul:BAAANQABCgIIAgABNQAECgoKGwACAGMVAA==.Wroughtsoul:BAAANQAECgYIDgAAAA==.Wrysoul:BAABNQAECn8bAAICAAoKYxXOEgCBAQACAAoKYxXOEgCBAQAAAA==.',
Wy='Wynston:BAAANQADCgEIAQAAAA==.Wyrmheart:BAAANQADCgIIAwAAAA==.',
Xa='Xaldred:BAABNQAECn8eAAIVAAoK7Qx5hQDYAQAVAAoK7Qx5hQDYAQABNQAECgoKMQAQAMMXAA==.Xandir:BAABNQAECn8YAAIaAAcKRhKxLwBhAQAaAAcKRhKxLwBhAQAAAA==.Xarhunt:BAAANQAECgMIAwAAAA==.',
Xe='Xenzia:BAAANQADCgcICwAAAA==.Xeracil:BAAANQADCgQICgAAAA==.',
Xo='Xoric:BAABNQAECn8xAAIiAAoKlxjdAQDjAgAiAAoKlxjdAQDjAgAAAA==.',
Xy='Xyal:BAABNQAECn8dAAILAAgKHhexbwDOAQALAAgKHhexbwDOAQAAAA==.Xyp:BAAANQADCgYIBgABNQAECgUIDQAOAAAAAA==.',
Ya='Yamaya:BAAANQADCgMIBQAAAA==.',
Yi='Yiago:BAAANQAECgIIBgAAAA==.',
Yo='Youknow:BAAANQADCgcICwAAAA==.',
Za='Zaelia:BAAANQADCgEIAQAAAA==.Zary:BAAANQAECgIIAgAAAA==.Zaxhdk:BAEANQADCgMIAwABNQAECgcIFgAIAOoSAA==.Zaxhpal:BAEBNQAECn8WAAIIAAcK6hIndgC1AQAIAAcK6hIndgC1AQAAAA==.',
Ze='Zenedy:BAAANQAECgQIBAABNQAECgUICAAOAAAAAA==.',
Zi='Zid:BAAANQAECgMIAwAAAA==.Ziny:BAAANQADCgUIBQAAAA==.Ziparoo:BAABNQAECn8mAAIXAAgKMAoMBwApAQAXAAgKMAoMBwApAQAAAA==.',
Zo='Zoenova:BAAANQAECggIAgAAAA==.',
Zr='Zraven:BAAANQADCgEIAQAAAA==.',
['În']='Îniquitous:BAAANQAECgUIDgAAAA==.',
['Ðê']='Ðêmønicßløøð:BAABNQAECn8dAAMjAAoKkRHFKgDzAAAjAAgKVRPFKgDzAAAQAAMKggrGsACQAAABNQAECgoKIgAJAMEUAA==.',
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
