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

local lookup = {'Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Fury','Druid-Guardian','Druid-Balance','Paladin-Retribution','Paladin-Holy','Paladin-Protection','Warrior-Arms','Warrior-Protection','Priest-Holy','DemonHunter-Devourer','Unknown-Unknown','DeathKnight-Blood','DeathKnight-Unholy','Hunter-Survival','Mage-Fire','Shaman-Enhancement','Warlock-Affliction','Warlock-Demonology','Mage-Frost','Mage-Arcane','Rogue-Subtlety','Monk-Windwalker','Monk-Mistweaver','Warlock-Destruction','Evoker-Preservation','Rogue-Assassination','Priest-Shadow','Priest-Discipline','Evoker-Devastation','Evoker-Augmentation','Monk-Brewmaster','DemonHunter-Vengeance','Druid-Feral','Druid-Restoration','DeathKnight-Frost','DemonHunter-Havoc',}
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aabbigale:BAAANQAECggIAQAAAA==.',
Ab='Abigt:BAAANQADCgIIAQAAAA==.',
Ac='Acidsnow:BAAANQAECgQIBQAAAA==.',
Ad='Adalaidê:BAAANQAECgMICwAAAA==.',
Ae='Aerynne:BAAANQAECgQICAAAAA==.',
Ai='Airie:BAABNQAECn8zAAMBAAoKUgkocwBZAQABAAoKUgkocwBZAQACAAcK0geZlADgAAAAAA==.',
Ak='Akuso:BAAANQADCgQIBgAAAA==.',
Al='Alcohaulorc:BAAANQAECgQIBwAAAA==.Alert:BAAANQAECgEIAQAAAA==.Aloris:BAAANQAECgQICAAAAA==.Aloy:BAACNQAFFH8QAAMDAAQKwRcPEABaAQADAAQKwRcPEABaAQAEAAEKAABwKAAzAAA1AAQKfxUAAgMABQo8H7ivAFIBAAMABQo8H7ivAFIBAAAA.Aluhx:BAAANQAECgMICQABNQAFFAYICwAFAJQRAA==.',
Am='Amednato:BAABNQAECn8cAAMGAAoKeweYLAA0AQAGAAoKeweYLAA0AQAHAAIKgAasegBVAAAAAA==.',
An='Anaeli:BAABNQAECn9fAAIBAAoKxCCIGwABAwABAAoKxCCIGwABAwAAAA==.Anastarian:BAAANQAECgQICQAAAA==.Ancalagonn:BAAANQAECgcIDwAAAA==.Angita:BAAANQAECgUIDAAAAA==.Anklin:BAAANQADCgIIAgAAAA==.Annaris:BAACNQAFFH8ZAAIDAAcKOBwCAwA8AgADAAcKOBwCAwA8AgA1AAQKfy8AAwMACgr3JUMHAKIDAAMACgr3JUMHAKIDAAQACQrJGS0yALwBAAAA.Antipæn:BAECNQAFFH8LAAMIAAMKFSJpEwAfAQAIAAMKFSJpEwAfAQAJAAEKdCO9JQBlAAA1AAQKf08AAwgACgrBJr8DAHgDAAgACgrBJr8DAHgDAAkACgoiITkLAG4DAAAA.',
Ap='Apologia:BAABNQAECn9DAAMIAAoKeiJhIQDbAgAIAAoKeiJhIQDbAgAKAAIKVgi4aQAsAAAAAA==.',
Aq='Aquaphobic:BAAANQAECgUIDAABNQAFFAgIFgABABMJAA==.',
Ar='Arcanoth:BAAANQADCgIIAgAAAA==.Ardicelia:BAAANQABCgUIBgAAAA==.Ares:BAABNQAECn8oAAILAAoK5R/7HQBAAwALAAoK5R/7HQBAAwAAAA==.Armorgorden:BAABNQAECn9VAAIMAAoKuSIcAwATAwAMAAoKuSIcAwATAwAAAA==.Aroviaa:BAABNQAECn89AAINAAoK5Ro1QABqAgANAAoK5Ro1QABqAgAAAA==.Arpmek:BAABNQAECn86AAIOAAoKtRVwJQAaAgAOAAoKtRVwJQAaAgAAAA==.Artemîs:BAAANQADCgIIAgAAAA==.',
As='Asharienne:BAABNQAECn8vAAIDAAoKXhCIZQD6AQADAAoKXhCIZQD6AQAAAA==.Ashilianar:BAAANQAECgUIDAAAAA==.Ashlynne:BAAANQAECgYJCwAAAA==.',
Au='Aubergine:BAAANQADCgQIBAAAAA==.Audiobully:BAAANQAECgQIBgABNQAECgoKOAAHAF4XAA==.Auntmary:BAAANQABCgUICAAAAA==.Auralynn:BAAANQAECgQJBAABNQAECgYJCwAPAAAAAA==.Auriella:BAABNQAECn8lAAMJAAoK0hAuaQDcAQAJAAoK0hAuaQDcAQAIAAIKsgi6pgEsAAAAAA==.Aurtt:BAABNQAECn86AAMQAAoKshRJRQDlAQAQAAkKPhVJRQDlAQARAAMKEAluYQCGAAAAAA==.',
['Aö']='Aöb:BAAANQADCgQIBgAAAA==.',
Ba='Bahahaknight:BAABNQAECn8+AAIQAAoKIBiAGwAiAgAQAAoKIBiAGwAiAgAAAA==.Bahree:BAAANQADCgIIAgAAAA==.Bakhar:BAABNQAECn82AAISAAkKaB4qBABLAgASAAkKaB4qBABLAgAAAA==.Balora:BAAANQADCgcIGAAAAA==.Barnette:BAABNQAECn9WAAITAAoKpRjAAQAyAgATAAoKpRjAAQAyAgAAAA==.Basyleus:BAAANQADCgEIAQAAAA==.',
Be='Beau:BAAANQAECgUIDQABNQAECgkJGQAJAMgfAA==.Belthos:BAABNQAECn8ZAAIIAAgKSBgceQA6AgAIAAgKSBgceQA6AgAAAA==.Benihime:BAAANQAECgEIAQAAAA==.Berristan:BAABNQAECn9BAAMJAAoKtQ95YgDxAQAJAAoKtQ95YgDxAQAIAAEKegTjowEtAAAAAA==.Bestwingman:BAAANQADCgEIAQAAAA==.',
Bi='Bigdawgsteve:BAAANQADCgIIAgAAAA==.Bigmarv:BAAANQAECgUIDAAAAA==.Bittytigs:BAACNQAFFH8WAAIBAAUKRRXNEwAmAQABAAUKRRXNEwAmAQA1AAQKf1cAAwEACgrGIZ8UACgDAAEACgrGIZ8UACgDAAIAAQoAAGBOAScAAAAA.',
Bl='Blestemat:BAAANQAECgEIAQAAAA==.Blossom:BAAANQAFFAQIBAABNQAFFAQIDQAPAAAAAQ==.Blumangood:BAABNQAECn9CAAQCAAoKPhlbIwBeAgACAAoKPhlbIwBeAgABAAIKLQKKFQE/AAAUAAEKAADnNwAwAAAAAA==.',
Bo='Bollux:BAAANQAECgEIAgAAAA==.Bosc:BAABNQAECn87AAIQAAoKzhZeIAD5AQAQAAoKzhZeIAD5AQAAAA==.Boudiicca:BAAANQAECgQICAAAAA==.Boxmasterr:BAABNQAECn89AAMVAAoK4BW+BQBeAgAVAAgKqBi+BQBeAgAWAAcKOhGNfgBkAQAAAA==.',
Br='Braagh:BAAANQABCggICwAAAA==.Brasmir:BAABNQAECn9LAAISAAoK3B4YAgDEAgASAAoK3B4YAgDEAgAAAA==.Briae:BAAANQADCgMIAwABNQAECgoKXwABAMQgAA==.Brianzero:BAAANQADCgYIBwAAAA==.Brino:BAAANQAECgQIBAAAAA==.Brinotriage:BAAANQAECgUIBQAAAA==.',
Bu='Bubblemoth:BAAANQADCgMIBAABNQAECggIFQAXAP4UAA==.Buik:BAAANQAECgIIAgAAAA==.Bulge:BAABNQAECn8mAAMYAAoKUw0w0QDkAQAYAAoK8Qww0QDkAQAXAAEK2Rb9PwBEAAABNQAFFAQIFQARAFIVAA==.Bulgogi:BAACNQAFFH8VAAIRAAQKUhUUBwDqAAARAAQKUhUUBwDqAAA1AAQKf0EAAhEACgoiILMMAK4CABEACgoiILMMAK4CAAAA.Butherrface:BAAANQADCgUIBQAAAA==.',
['Bö']='Börk:BAAANQAECgUIDAAAAA==.',
Ca='Capy:BAAANQAECgIIAgABNQAFFAQIBgAXAOQUAA==.Cardran:BAAANQADCgIIAgABNQAECgoKGAADAOASAA==.Cayda:BAAANQADCgYICwAAAA==.Caylara:BAABNQAECn8eAAIZAAYK/QuLmADcAAAZAAYK/QuLmADcAAAAAA==.Cayssabber:BAAANQAECgcIBQAAAA==.Cayssaber:BAAANQAECgIIAgAAAA==.',
Ce='Ceicilia:BAAANQADCgQIBAAAAA==.Celrythis:BAAANQAECgUIEAAAAA==.Cenokry:BAAANQAECgIIAgAAAA==.',
Ch='Chai:BAABNQAECn8hAAMaAAoKBgxCLwAgAQAaAAoKBgxCLwAgAQAbAAIKNAPCRAAeAAAAAA==.Chaintrain:BAAANQAECgMIAwABNQAECgkJIAAWAE4WAA==.Chellyy:BAAANQAECgYIDwABNQAECgcIJwAOAGYeAA==.Chibisend:BAAANQADCgMIAwAAAA==.Chocymilk:BAAANQAECgYIBgAAAA==.Chámeleon:BAAANQADCgEIAQAAAA==.',
Ci='Cider:BAAANQAECgIIAgAAAA==.',
Cl='Claes:BAAANQADCgMIAwABNQAECgoKOwAQAM4WAA==.',
Co='Coralbubbles:BAABNQAECn9BAAIIAAoKIBY1WQAkAgAIAAoKIBY1WQAkAgAAAA==.Coralorchid:BAABNQAECn8yAAIKAAgKRxsWGAC4AQAKAAgKRxsWGAC4AQAAAA==.Coralprays:BAAANQAECgYIBgAAAA==.Coralrages:BAAANQAECgQIBgAAAA==.',
Cr='Cromenockle:BAABNQAECn8UAAQVAAkKmBO+EwAPAQAWAAgKahIYhADcAQAVAAQKdw++EwAPAQAcAAIKuw4vWAB3AAABNQAFFAUICgASALUTAA==.Crtitman:BAAANQAECgUIDgAAAA==.',
Cu='Cupcâke:BAAANQAECgQIBgAAAA==.Curissan:BAABNQAECn8gAAICAAgKqBLRbQDWAQACAAgKqBLRbQDWAQAAAA==.',
Da='Dalgon:BAABNQAFFH8IAAIdAAQK6wRDEADvAAAdAAQK6wRDEADvAAABNQAFFAcIEAAJAKIUAA==.Dalir:BAAANQAECgYIDgAAAA==.Dalspin:BAAANQADCgYIDAAAAA==.Dalthepal:BAACNQAFFH8QAAIJAAcKohTvBwDnAQAJAAcKohTvBwDnAQA1AAQKf0gAAgkACgrzHzoXAB8DAAkACgrzHzoXAB8DAAAA.Damné:BAABNQAECn9HAAIRAAoKnxw+DwCLAgARAAoKnxw+DwCLAgAAAA==.Darze:BAAANQADCggIAwABNQAECgcICgAPAAAAAA==.Davidline:BAABNQAECn80AAIIAAoKgx4/MgCZAgAIAAoKgx4/MgCZAgAAAA==.',
De='Deadish:BAABNQAECn9DAAMQAAoKbyHKCQDxAgAQAAoKbyHKCQDxAgARAAEKDQa8nQASAAAAAA==.Deathras:BAAANQAECgYIBgAAAA==.Deathsaberss:BAABNQAECn9QAAMLAAoKNRvwMgBzAgALAAoKNRvwMgBzAgAMAAQK5Au+KgDjAAAAAA==.Deathvex:BAACNQAFFH8XAAIQAAUKqRM3FAAYAQAQAAUKqRM3FAAYAQA1AAQKfyoAAhAACgpZHCQRAJECABAACgpZHCQRAJECAAAA.Decoz:BAAANQAECgUICgAAAA==.Deight:BAAANQAECgcIDAAAAA==.Deknivez:BAAANQAECgQICAAAAA==.Dendahn:BAAANQAECgcIDQAAAA==.Destinee:BAAANQAECgQICwAAAA==.',
Di='Dianntha:BAAANQAECgEIAQAAAA==.Diladrin:BAABNQAECn9iAAIGAAoKgxtaDQBhAgAGAAoKgxtaDQBhAgAAAA==.Dinomight:BAAANQADCgQIBAAAAA==.',
Do='Doileag:BAABNQAECn8iAAIIAAcKEAeRKQGsAAAIAAcKEAeRKQGsAAAAAA==.Doomgrave:BAAANQADCgEIAQAAAA==.Dora:BAAANQADCgYIBgABNQAECggIHgAeAFwHAA==.Dottmatrix:BAABNQAECn8eAAIcAAYKwwcdGQCYAAAcAAYKwwcdGQCYAAAAAA==.Doubledowns:BAAANQAECgEIAQAAAA==.',
Dr='Dreadwing:BAAANQAECgQIDAAAAA==.Druromu:BAABNQAECn8cAAMLAAYKYQ5mwQDzAAALAAYKYQ5mwQDzAAAMAAEKAACLUwAAAAAAAA==.',
Du='Dufs:BAACNQAFFH8VAAIBAAUKDyY7CQC9AQABAAUKDyY7CQC9AQA1AAQKfy0AAgEACgrNH2wcAPwCAAEACgrNH2wcAPwCAAAA.Dunkan:BAAANQAECgMIAwAAAA==.Dustbunny:BAABNQAECn9SAAQNAAoKCB2vIADbAgANAAoKCB2vIADbAgAfAAEKVgeeZAA0AAAgAAEK/gZDHQAnAAAAAA==.',
Dw='Dwagon:BAABNQAECn8UAAMhAAgKYQlaIgA4AQAhAAYKQQtaIgA4AQAiAAMK1gd5IABWAAAAAA==.Dwagonfells:BAAANQAECgIIBAAAAA==.',
Dy='Dylsonlolqt:BAABNQAECn8iAAIQAAkKXgnOOQBbAQAQAAkKXgnOOQBbAQAAAA==.',
['Dã']='Dãrling:BAAANQABCgEIAQAAAA==.',
['Dû']='Dûn:BAABNQAECn9AAAMaAAoK8CDLDQAAAwAaAAoK5SDLDQAAAwAjAAgKNh4pCgB1AgAAAA==.Dûna:BAABNQAECn8xAAIfAAoKkx31CgCuAgAfAAoKkx31CgCuAgABNQAECgoKQAAaAPAgAA==.',
El='Elaatia:BAABNQAECn8+AAIIAAoKySNjKgAdAwAIAAoKySNjKgAdAwAAAA==.Elidria:BAAANQABCgIIAgAAAA==.Ellysprocket:BAAANQADCgUICQAAAA==.Elrric:BAAANQAECgcICgAAAA==.Elyak:BAAANQADCgIIAgAAAA==.',
En='Envoy:BAAANQAECgQIBwAAAA==.',
Er='Erakron:BAABNQAECn9GAAMCAAoKuxf7JwBDAgACAAoKuxf7JwBDAgABAAYKmBPUpwAiAQAAAA==.Erine:BAAANQAECgUIBAAAAA==.Erouvi:BAAANQADCgIIAgABNQAECgoKPQANAOUaAA==.Eroviaa:BAAANQAECgUIBwABNQAECgoKPQANAOUaAA==.Erovvia:BAAANQADCgUIBQABNQAECgoKPQANAOUaAA==.',
Es='Esmeralda:BAAANQABCggIEAAAAA==.',
Et='Etali:BAAANQADCgYIBQABNQAECgoKOQAOAHEbAA==.',
Ev='Evorik:BAAANQAECggIEQABNQAFFAIIBQALAH4TAA==.',
Ez='Ezothen:BAABNQAECn8cAAMhAAcKfAfmFwC7AAAhAAcKfAfmFwC7AAAiAAEKJAW+HgAsAAAAAA==.',
Fa='Facelessman:BAAANQABCggILAAAAA==.Faedoria:BAABNQAECn8XAAIIAAgKzAeK7QAHAQAIAAgKzAeK7QAHAQAAAA==.Faeryln:BAABNQAECn9QAAINAAoKXguUYwC1AQANAAoKXguUYwC1AQAAAA==.Faustus:BAABNQAECn8ZAAIJAAkKyB8jJgDRAgAJAAkKyB8jJgDRAgAAAA==.Favion:BAAANQADCgEIAQAAAA==.',
Fe='Felyyia:BAABNQAECn8nAAIOAAoK3yInBQAPAwAOAAoK3yInBQAPAwABNQAFFAcIGQADADgcAA==.',
Fi='Fiddlestix:BAAANQAECgQIBAAAAA==.Firebrande:BAAANQAECgUIDAAAAA==.Fisticuffs:BAAANQADCggIKwAAAA==.Fizcrankshot:BAABNQAECn9PAAIDAAoKvBlMNQB0AgADAAoKvBlMNQB0AgAAAA==.',
Fl='Flamewhisker:BAAANQAECgUIEQAAAQ==.Flamez:BAAANQADCgcIBwAAAA==.Flandre:BAAANQAECgUIBAAAAA==.',
Fr='Fraublucher:BAABNQAECn84AAINAAoKhgnybQCTAQANAAoKhgnybQCTAQAAAA==.Frewyn:BAAANQAECgYIDgAAAA==.Frostimoth:BAABNQAECn8VAAIXAAgK/hS9EQCKAQAXAAgK/hS9EQCKAQAAAA==.Frozty:BAAANQAECgQIBgAAAA==.',
Ga='Galandel:BAAANQADCggIKAAAAA==.Galial:BAACNQAFFH8MAAIkAAQK9hAFAwCoAAAkAAQK9hAFAwCoAAA1AAQKfzMAAiQACgpfGgwHAKACACQACgpfGgwHAKACAAAA.Gantar:BAAANQAECgUIBQABNQAFFAUIDQAQAD0dAA==.Garradin:BAAANQADCgEIAQAAAA==.Garrunter:BAABNQAECn8YAAIDAAoKiQkgoABzAQADAAoKiQkgoABzAQAAAA==.Gaznol:BAAANQADCgQIBAABNQAECgoKHAAGAHsHAA==.',
Ge='Gelasera:BAAANQAECgUICwAAAA==.Gemitra:BAAANQADCgcIBwABNQAECggIMgAKAEcbAA==.Geneth:BAAANQAECgUIBQAAAA==.George:BAACNQAFFH8FAAILAAIKfhPSLgCPAAALAAIKfhPSLgCPAAA1AAQKfzUAAgsACQpiH2hBAD4CAAsACQpiH2hBAD4CAAAA.',
Gh='Ghalta:BAAANQADCgIIAgABNQAECgoKOQAOAHEbAA==.Ghrol:BAAANQABCgYIBgABNQAECgoKUAABAH4fAA==.',
Gl='Glaivethras:BAABNQAECn9IAAIkAAoK3iNgAQA4AwAkAAoK3iNgAQA4AwAAAA==.Glenfin:BAAANQADCgQIBgAAAA==.',
Gr='Greg:BAAANQAECgEIAgAAAA==.Gremlynn:BAAANQADCggICAAAAA==.Grimclaw:BAACNQAFFH8TAAMlAAkKdhkoAAAzAgAlAAgKtxooAAAzAgAHAAUKSAndFgD7AAA1AAQKfy8AAwcACgorJcseANQCAAcACAqVIsseANQCACUABgrnJdAOACYCAAAA.Groot:BAABNQAECn8aAAMmAAcKqhchQwD6AAAmAAcKqhchQwD6AAAHAAMK8wyrjQCgAAABNQAECgkJIwAKAGERAA==.',
Gu='Guthrek:BAAANQAECgYIDAAAAA==.',
Ha='Hamfist:BAAANQADCgIIAgABNQAECgoKFAAVABgSAA==.Hannebal:BAABNQAECn8rAAIJAAoKJxWRNABLAgAJAAoKJxWRNABLAgAAAA==.',
He='Healsonyou:BAAANQAFFAEIAgAAAA==.Healyclam:BAAANQADCgMIAwAAAA==.Heydaw:BAAANQADCggICAABNQAECgkJGAAnAJUbAA==.Heynow:BAABNQAECn8oAAIUAAoKRgjeFgCnAQAUAAoKRgjeFgCnAQAAAA==.',
Hi='Higherp:BAAANQADCggICAABNQAECgcILgAlAKYRAA==.Highmountain:BAAANQADCggIDQAAAA==.Hilimed:BAABNQAECn9SAAIWAAoKsw5zVQDUAQAWAAoKsw5zVQDUAQAAAA==.',
Ho='Hobs:BAAANQADCgUIBQAAAA==.Holyßloodelf:BAAANQAECggIDgABNQAFFAEIAgAPAAAAAA==.Hoosier:BAABNQAECn8mAAINAAkK4BlkJQC9AgANAAkK4BlkJQC9AgAAAA==.Hoplite:BAABNQAECn8eAAImAAoKshVjGQBGAgAmAAoKshVjGQBGAgAAAA==.',
Hu='Huasca:BAAANQAECgEIAQAAAA==.Huthuel:BAAANQABCggIFAAAAA==.',
Hy='Hydra:BAAANQADCgYIBgABNQAECgoKJwAYALcSAA==.Hyve:BAAANQAECgMIAwABNQAECgoKVQAIANkZAA==.',
['Hà']='Hàney:BAEANQAECgQIBAAAAA==.',
['Hé']='Hélio:BAAANQADCgUIBQAAAA==.',
Ia='Ia:BAABNQAECn9HAAInAAoKSyO4BQBEAwAnAAoKSyO4BQBEAwAAAA==.',
Ib='Ibesmashin:BAAANQADCgQIBAABNQAECgoKFAAVABgSAA==.Ibesneakin:BAAANQAECgQIBAABNQAECgoKFAAVABgSAA==.',
Id='Idontsuck:BAAANQADCggICwAAAA==.',
Il='Ileynha:BAABNQAECn8bAAIVAAoKBQuXCQC2AQAVAAoKBQuXCQC2AQAAAA==.Ilieau:BAAANQAECgQIBQABNQAECggIEQAPAAAAAA==.Illida:BAAANQADCgYIBgAAAA==.',
Im='Imamalelol:BAABNQAECn8YAAMLAAYKQAUO/gDgAAALAAYKQAUO/gDgAAAFAAMK5ATnNgArAAAAAA==.',
In='Inarrah:BAAANQADCgEIAQAAAA==.Intol:BAAANQAFFAQIDQAAAQ==.Intrepidhero:BAAANQADCgEIAQAAAA==.',
Ir='Irkenfox:BAECNQAFFH8ZAAIMAAUKfBabAwAYAQAMAAUKfBabAwAYAQA1AAQKfzEAAgwACgoJJKQCAIYDAAwACgoJJKQCAIYDAAAA.',
It='Ithran:BAAANQADCgUIBQAAAA==.Itsatrap:BAAANQAECgQIBAAAAA==.',
Iw='Iwilltank:BAAANQADCgYICwAAAA==.',
Ix='Ixitt:BAABNQAECn87AAITAAoKrxinAQA9AgATAAoKrxinAQA9AgAAAA==.',
Ja='Jama:BAAANQADCgYIBgAAAA==.Janderick:BAAANQAECgcIDwAAAA==.Jaromer:BAAANQADCgcIEAAAAA==.',
Je='Jellacee:BAAANQADCgcIFwAAAA==.Jesterjoe:BAAANQADCgMIAwAAAA==.',
Ji='Jimboberjim:BAACNQAFFH8YAAIcAAUKMiK4AAB9AQAcAAUKMiK4AAB9AQA1AAQKfzUAAhwACgrsI2wBAHsDABwACgrsI2wBAHsDAAAA.Jimbobwhey:BAABNQAECn8yAAIjAAoKvx0tAwDAAgAjAAoKvx0tAwDAAgAAAA==.Jiminie:BAABNQAECn8eAAIMAAgKPxMdFgDHAQAMAAgKPxMdFgDHAQABNQAECgoKMgAjAL8dAA==.',
Jo='Jolio:BAABNQAECn8gAAQWAAkKThaYqgB9AQAWAAgKLhSYqgB9AQAcAAEKuBq9aABQAAAVAAIKrBdyKABKAAAAAA==.Joltraxi:BAAANQADCggICAABNQAECgkJIAAWAE4WAA==.Joshie:BAACNQAFFH8NAAIQAAUKPR1LEQDzAAAQAAUKPR1LEQDzAAA1AAQKfzEAAhAACgoSJOgJAGYDABAACgoSJOgJAGYDAAAA.Joshy:BAAANQADCgcIBwABNQAFFAUIDQAQAD0dAA==.',
Ju='Jujubeans:BAAANQAECgcICQAAAA==.Juniornite:BAABNQAECn9RAAIYAAoKZyNHEAAOAwAYAAoKZyNHEAAOAwAAAA==.Justthetouch:BAABNQAECn8YAAIaAAoKABIJGAD1AQAaAAoKABIJGAD1AQAAAA==.',
Jy='Jygglypuff:BAAANQAECgMIBAAAAA==.',
Ka='Kadaan:BAAANQAECgYIBgAAAA==.Kagemaro:BAABNQAECn85AAMOAAoKcRtBFQC7AgAOAAoKcRtBFQC7AgAkAAUKdRS7GQAZAQAAAA==.Kahgar:BAAANQAECggILAABNQAECgoKWwAJANMZAQ==.Kalimathath:BAAANQAECgQIBgAAAA==.Kalzod:BAABNQAECn9WAAIWAAoK4SXyAQDcAwAWAAoK4SXyAQDcAwAAAA==.Kataki:BAABNQAECn82AAIDAAkKlxyALACQAgADAAkKlxyALACQAgABNQAECgoKOQAOAHEbAA==.Katia:BAABNQAECn8ZAAIaAAYKMBJkNwDoAAAaAAYKMBJkNwDoAAAAAA==.Kativeria:BAAANQAECgUICgAAAA==.Katjayna:BAAANQADCgUICgAAAA==.Kaysabr:BAAANQAECgUIBQAAAA==.Kayssaber:BAABNQAECn8kAAMmAAoKtBSwHAAgAgAmAAoKtBSwHAAgAgAHAAMK5BDvjwCXAAAAAA==.',
Ke='Kebab:BAAANQAECgQJBAAAAA==.Kelsifer:BAAANQAECgQICwABNQAECgkJGQAJAMgfAA==.Kempra:BAAANQADCgcIBwAAAA==.Kemprei:BAAANQADCgUIBQAAAA==.Kendralust:BAAANQAECgcICAAAAA==.Kerfufle:BAAANQABCgIJAgAAAA==.',
Kh='Khaos:BAAANQABCgEIAQAAAA==.',
Ki='Killmora:BAAANQADCggILQAAAA==.Kippars:BAAANQAECgIIAgAAAA==.Kiritsugo:BAAANQADCggIDgAAAA==.',
Kl='Klaax:BAABNQAECn8WAAIUAAgKhQiRGACKAQAUAAgKhQiRGACKAQABNQAECgoKVQAIANkZAA==.',
Ko='Kodazoff:BAABNQAECn8bAAMhAAkKHwr1DQBqAQAhAAkKHwr1DQBqAQAdAAEKTwOjUwAkAAAAAA==.Kora:BAAANQABCgEIAgAAAA==.Korevash:BAABNQAECn87AAMBAAoKZCP9AwCrAwABAAoKZCP9AwCrAwAUAAYKAhJaHACeAQAAAA==.',
Kr='Krezz:BAAANQAECgEIAQAAAA==.Krissylu:BAAANQAECgYIDgAAAA==.Krothix:BAABNQAECn9BAAICAAoKhAeMYgBfAQACAAoKhAeMYgBfAQAAAA==.Krudd:BAAANQAECgcIDQAAAA==.Krychilly:BAAANQADCggIHwAAAA==.Kryrande:BAAANQADCgQICwAAAA==.Kryshym:BAABNQAECn8cAAIJAAYKtiDiTAA2AgAJAAYKtiDiTAA2AgAAAA==.Krythrall:BAAANQAECgEIAQABNQAECgYIHAAJALYgAA==.Krytree:BAAANQADCggICQAAAA==.Kryvelen:BAABNQAECn8kAAMNAAoKOhrxIgDMAgANAAoKyRnxIgDMAgAgAAcKExYKBQDRAQAAAA==.Krëëp:BAAANQAECggICAAAAA==.',
Ks='Kspectactle:BAAANQAECgMIBAAAAA==.',
Ku='Kuilei:BAAANQADCgYJCwABNQAECgQIDAAPAAAAAA==.Kurorø:BAABNQAECn8iAAIDAAcKjQvKwQAuAQADAAcKjQvKwQAuAQAAAA==.',
Ky='Kyrayna:BAAANQADCgYIEgAAAA==.',
['Kä']='Käisèr:BAAANQABCgEIAQAAAA==.',
La='Ladara:BAABNQAECn8oAAIVAAkKixQxBgBPAgAVAAkKixQxBgBPAgAAAA==.Laima:BAAANQADCgUICQAAAA==.Landil:BAAANQADCgYIDAAAAA==.Lavitz:BAAANQAECgEIAQAAAA==.',
Le='Leheo:BAAANQAECgQIBgAAAA==.Lehua:BAAANQADCggICgAAAA==.Leilanii:BAAANQADCgcIEQAAAA==.Lemook:BAABNQAECn8iAAImAAoKIRL3IADyAQAmAAoKIRL3IADyAQAAAA==.Leonìdas:BAAANQADCggIGQAAAA==.Leð:BAAANQAECggICAAAAA==.',
Li='Licker:BAAANQAECgUICQABNQAFFAUICgASALUTAA==.Life:BAAANQADCgcICgAAAA==.Lightbulb:BAAANQADCgYIDQAAAA==.Lightsorrow:BAAANQAECgcIDgABNQAECgoKMgAiADsTAA==.Lightstormer:BAAANQADCgcIJQAAAA==.Lilamae:BAAANQAECgUIDQAAAA==.Lilarielle:BAABNQAECn9QAAIlAAoKAAcYIQD5AAAlAAoKAAcYIQD5AAAAAA==.Lildookie:BAABNQAECn8hAAICAAoKkQl6VgCEAQACAAoKkQl6VgCEAQAAAA==.Lilface:BAAANQAECggIDAAAAA==.Lilhands:BAAANQAECgQIAwAAAA==.Liliel:BAAANQADCgMIAwABNQAECgoKGAADAOASAA==.Liliela:BAABNQAECn8YAAIDAAoK4BKuaABCAgADAAoK4BKuaABCAgAAAA==.Lilyannah:BAAANQADCgEIAQAAAA==.Liodragon:BAAANQADCgUIBQABNQAECgcICgAPAAAAAA==.Liolock:BAAANQAECggIBwAAAA==.Lite:BAAANQAECgQIBAAAAA==.Liø:BAAANQAECgcICgAAAA==.',
Ll='Lluniez:BAABNQAECn8yAAIaAAoK0RG+GADsAQAaAAoK0RG+GADsAQAAAA==.',
Lm='Lmccoy:BAAANQABCgQIBAAAAA==.',
Lo='Lockroknroll:BAABNQAECn8UAAIVAAoKGBKFBgBEAgAVAAoKGBKFBgBEAgAAAA==.Loissa:BAAANQAECggIEAAAAA==.Losoli:BAABNQAECn9SAAIJAAoK6SBuDgBPAwAJAAoK6SBuDgBPAwAAAA==.Lowchin:BAAANQAECgQIBQAAAA==.',
Lu='Lupine:BAAANQADCgYIBgABNQAECggIEgAPAAAAAA==.Lutherion:BAABNQAECn8xAAIMAAoKBB4SBgAJAwAMAAoKBB4SBgAJAwAAAA==.',
Ly='Lycemmas:BAABNQAECn8mAAIBAAoK1Ri8RQBKAgABAAoK1Ri8RQBKAgAAAA==.',
['Lï']='Lïo:BAAANQADCgYIBwABNQAECgcICgAPAAAAAA==.',
Ma='Macoun:BAABNQAECn87AAIDAAoKPCPEDgAaAwADAAoKPCPEDgAaAwAAAA==.Magicshowers:BAABNQAECn8+AAIYAAoKzyKsNwAZAwAYAAoKzyKsNwAZAwAAAA==.Majiique:BAAANQABCggIGAAAAA==.Manseed:BAAANQABCgQJBAAAAA==.Maple:BAAANQAECggIEgAAAA==.Martei:BAACNQAFFH8XAAIlAAUK2xfCAQBJAQAlAAUK2xfCAQBJAQA1AAQKfzAAAiUACgpWHTsHAO8CACUACgpWHTsHAO8CAAAA.Maríneth:BAABNQAECn8eAAImAAYK7wrDRADxAAAmAAYK7wrDRADxAAAAAA==.Mascara:BAAANQAECgYICwAAAA==.Maxe:BAAANQADCgIIAgAAAA==.',
Me='Memebait:BAAANQAECgUIBQAAAA==.Mementomori:BAAANQAECgEIAQAAAA==.Meowbae:BAAANQAECgUICQABNQAECgQIBgAPAAAAAA==.Merce:BAAANQADCgcIBwABNQAECgoKGAADAOASAA==.Mercesdes:BAAANQAECgEIAgAAAA==.',
Mi='Midway:BAAANQAECgQIBgAAAA==.Minizee:BAAANQAECgEIAQAAAA==.Mirokushan:BAAANQAECgUICAAAAA==.Missfire:BAAANQAECgIIAwAAAA==.Misticlady:BAAANQAECgQIBgAAAA==.Mistrariel:BAAANQAECgYIBgABNQAECgoKLAAcAGQcAA==.Mizukì:BAAANQABCgQIBgAAAA==.',
Mo='Moluubar:BAABNQAECn8pAAMLAAoKphMHfgAgAgALAAoKphMHfgAgAgAMAAEKAADeUQAAAAAAAA==.Moradin:BAAANQADCgMIAwAAAA==.Mordemour:BAAANQAECgcICgAAAA==.',
Mu='Mufler:BAAANQABCgQIBQAAAA==.Mungo:BAABNQAECn8ZAAIYAAkKRAm9swA9AQAYAAkKRAm9swA9AQAAAA==.Mushù:BAAANQAECgUICgABNQAECgoKRQAWAMgbAA==.',
My='Myfire:BAAANQADCgYIBgAAAA==.Myrell:BAAANQAECggICAAAAA==.Myrrh:BAAANQAECgYIDwAAAA==.',
Na='Nalik:BAAANQAECgYIDgAAAA==.Nanou:BAAANQAECgUIBwAAAA==.Nardiaun:BAAANQADCgYIBgAAAA==.Naturebait:BAAANQADCgQIBAABNQAECgoKQgACAD4ZAA==.',
Ne='Nerzheul:BAABNQAECn8hAAIQAAoKqQ5hLACjAQAQAAoKqQ5hLACjAQAAAA==.',
Ni='Nicety:BAAANQAECgMIAwAAAA==.Nimravidae:BAABNQAECn8/AAIJAAoKIxqeLgBoAgAJAAoKIxqeLgBoAgAAAA==.Ninelives:BAABNQAECn8gAAIHAAoKzwJTWgC3AAAHAAoKzwJTWgC3AAAAAA==.Nitecrawler:BAAANQADCgQIBAAAAA==.Niteeye:BAAANQABCgIIAgABNQAECgoKUQAYAGcjAA==.Niteryu:BAAANQAECgEIAwABNQAECgoKUQAYAGcjAA==.',
No='Nolokkotal:BAABNQAECn8wAAILAAoKbxu8SgAfAgALAAoKbxu8SgAfAgABNQAFFAEIAgAPAAAAAA==.Nospitfisty:BAAANQADCgQIBAAAAA==.Noxolon:BAABNQAECn8fAAMFAAkKMBLTFAArAQAFAAkKMBLTFAArAQALAAEKAADYWwErAAAAAA==.',
Nr='Nreaf:BAACNQAFFH8IAAIIAAUK7QjxFQD/AAAIAAUK7QjxFQD/AAA1AAQKfywAAggACgrKE7uHABgCAAgACgrKE7uHABgCAAAA.',
['Nø']='Nørd:BAAANQADCgYIBgAAAA==.',
Oi='Oili:BAACNQAFFH8RAAIXAAUKaxSGAgAMAQAXAAUKaxSGAgAMAQA1AAQKfzEAAxcACgruGdcHAG0CABcACgruGdcHAG0CABgABAoADs9zAdcAAAAA.',
Ol='Olarrick:BAAANQAECgQIBQABNQAFFAIIBQALAH4TAA==.',
Oo='Ookkarlib:BAAANQADCgUIBQAAAA==.Oops:BAACNQAFFH8SAAIQAAUKjRtFEgAzAQAQAAUKjRtFEgAzAQA1AAQKf0IAAxAACgrNIHERACEDABAACgrNIHERACEDABEAAQqwCnCMADAAAAAA.',
Or='Orcchopped:BAAANQADCgQIBAAAAA==.Ornstein:BAEBNQAECn8eAAIKAAcKUB9FFwDAAQAKAAcKUB9FFwDAAQAAAA==.',
Ot='Ottuk:BAACNQAFFH8GAAIRAAMKFgmAGgCGAAARAAMKFgmAGgCGAAA1AAQKfywAAhEACgrqHZMfAM4CABEACgrqHZMfAM4CAAAA.',
Pa='Padpaw:BAAANQAECgUJCAAAAA==.Pakraxes:BAABNQAECn8zAAIhAAoKBQ+bFQDyAQAhAAoKBQ+bFQDyAQAAAA==.Paksenarrion:BAABNQAECn9AAAIKAAoKkBL8GACuAQAKAAoKkBL8GACuAQAAAA==.Palehoof:BAAANQADCggIGgABNQAECgEIAgAPAAAAAA==.Pallywaya:BAABNQAECn8mAAMIAAoKxRBUeADdAQAIAAoKxRBUeADdAQAJAAkKgwUw1ABtAAAAAA==.Pandemonîum:BAAANQAECgUIBgABNQAFFAQIBQAaAEELAA==.Pandemônium:BAAANQAECgYIBwABNQAFFAQIBQAaAEELAA==.Pandemönium:BAABNQAECn8lAAQIAAgKeh0fVgCTAgAIAAgKUh0fVgCTAgAKAAIKzRxTUwCXAAAJAAMKcArVxgCLAAABNQAFFAQIBQAaAEELAA==.Pandemöniüm:BAACNQAFFH8FAAMaAAQKQQusDACtAAAaAAQK+QesDACtAAAjAAEKxgyVCQA6AAA1AAQKfy4AAxoACgr8F+oQAE8CABoACgr8F+oQAE8CABsABApREEolANwAAAAA.Parca:BAAANQADCgQIBAAAAA==.Parts:BAAANQABCggIDwAAAA==.Patchington:BAABNQAECn8eAAIKAAYK4wsoQgCfAAAKAAYK4wsoQgCfAAAAAA==.Pañdemönium:BAAANQAECgQIDgABNQAFFAQIBQAaAEELAA==.',
Pe='Pedwyn:BAAANQAECgcIBwAAAA==.Pepperrjakk:BAAANQADCgEIAQAAAA==.Perck:BAAANQADCgYIBgAAAA==.Perrylee:BAAANQAECgQICwAAAA==.',
Ph='Philia:BAABNQAECn8XAAMLAAgKmRWwnADVAQALAAgKFhKwnADVAQAMAAMK9Rp5KwDdAAABNQAFFAQIEAADAMEXAA==.Phurrball:BAAANQADCgYIBwAAAA==.',
Pi='Pixelme:BAABNQAFFH8GAAIEAAIKcASBHwB4AAAEAAIKcASBHwB4AAAAAA==.',
Pl='Pleggster:BAAANQAECgYIDAAAAA==.',
Po='Pochula:BAAANQAECgUICwAAAA==.Poplo:BAAANQADCggICAAAAA==.',
Pr='Primo:BAABNQAECn9bAAIJAAoK0xkKJQCeAgAJAAoK0xkKJQCeAgAAAA==.Protricity:BAABNQAECn8YAAMfAAoKUBaiJAALAgAfAAgKmBSiJAALAgANAAcKvBSpowAqAQAAAA==.',
Ps='Psalms:BAAANQAECgYIAwABNQAECgcIBwAPAAAAAA==.Psychoprowla:BAABNQAECn9AAAIfAAoKkBKjFQAHAgAfAAoKkBKjFQAHAgAAAA==.Psychozdrood:BAAANQAECgEIAQAAAA==.Psychozpally:BAAANQAECgQIBAAAAA==.',
['Pä']='Pändemönium:BAABNQAECn8bAAUGAAoKeR/hEwD+AQAGAAcKeB3hEwD+AQAHAAUK0AkkcQAFAQAlAAUKSg+KJgDZAAAmAAMKPwekXgB9AAABNQAFFAQIBQAaAEELAA==.',
['Pæ']='Pæn:BAEBNQAECn8mAAMRAAoKBR+3EgBgAgARAAoK/R23EgBgAgAnAAcK2RJsRQCEAQABNQAFFAMICwAIABUiAA==.',
Qu='Quantar:BAAANQADCgYIBgABNQAECggIDgAPAAAAAA==.Quickstab:BAAANQAECgQIDAAAAA==.',
Ra='Ragana:BAABNQAECn8YAAIBAAgKggjjmQDtAAABAAgKggjjmQDtAAAAAA==.Rainger:BAAANQADCgMIAwAAAA==.Rainn:BAAANQADCgQIAgAAAA==.Rallypaly:BAAANQADCgMIAwAAAA==.Ramthor:BAAANQAECgUICwAAAA==.Rancooll:BAAANQADCggIIgAAAA==.Rasniir:BAABNQAECn8yAAImAAkKARanIAAkAgAmAAkKARanIAAkAgAAAA==.Rasputea:BAAANQABCgIIAgAAAA==.Ravenar:BAAANQAECgQIBAAAAA==.Ravenlash:BAAANQABCgcICwAAAA==.',
Re='Regna:BAACNQAFFH8RAAMLAAUK9yCDFQB8AQALAAQK9yCDFQB8AQAFAAMKviJtAgDBAAA1AAQKfzEAAwsACgpnJSsbAEsDAAsACQqYJSsbAEsDAAUABQrfI1wQAKEBAAAA.Relkon:BAAANQADCgMIAwAAAA==.Remaked:BAACNQAFFH8rAAIjAAgKbRqkAQAAAgAjAAgKbRqkAQAAAgA1AAQKf0kAAiMACgqlISIEADsDACMACgqlISIEADsDAAAA.Requinix:BAABNQAECn9UAAIDAAoKMheAQABUAgADAAoKMheAQABUAgAAAA==.Retro:BAAANQADCggIDgAAAA==.Reynmaker:BAAANQADCgQIBAAAAA==.',
Rh='Rhowyn:BAAANQADCgQICAAAAA==.',
Ri='Riptidez:BAAANQADCgYIBgAAAA==.Ririko:BAABNQAECn9AAAINAAoKvw4yWwDSAQANAAoKvw4yWwDSAQAAAA==.Ritzo:BAABNQAECn84AAIFAAoKMxh2CQAIAgAFAAoKMxh2CQAIAgAAAA==.',
Ro='Robval:BAAANQABCgIIAgAAAA==.Rocksanne:BAAANQAECgQIBAAAAA==.Rooguee:BAAANQAECgIIAwAAAA==.',
Ru='Rukkis:BAABNQAECn8xAAMZAAoKzBpRDwCGAgAZAAkKhhpRDwCGAgAeAAgKDxcMKgBEAgAAAA==.Rumi:BAABNQAECn9ZAAIkAAoKqh7MAwAdAwAkAAoKqh7MAwAdAwAAAA==.',
Ry='Ryeekan:BAAANQAECggIDQAAAA==.Ryuma:BAAANQAECgYIDwAAAA==.Ryumar:BAAANQAECgMIAwAAAA==.',
Sa='Sabrosura:BAABNQAECn8jAAIKAAkKYRHlJwCfAQAKAAkKYRHlJwCfAQAAAA==.Saiyan:BAAANQADCgIIAgAAAA==.Salsinor:BAAANQADCgYICwAAAA==.Sanosagara:BAAANQAECggIBgAAAA==.Sathari:BAABNQAECn9AAAIOAAoKKBHyHQC1AQAOAAoKKBHyHQC1AQAAAA==.',
Sc='Schaden:BAAANQAECgcIBwAAAA==.Scripter:BAAANQADCgUIBgAAAA==.',
Se='Seijo:BAAANQAECgEJAQAAAA==.Sekk:BAABNQAECn9VAAMIAAoK2RmJUQA4AgAIAAoK2RmJUQA4AgAKAAYKURU7LQAOAQAAAA==.Selecta:BAAANQAECgEIAQAAAA==.Selexi:BAABNQAECn8bAAICAAoKaRZ1KgA1AgACAAoKaRZ1KgA1AgAAAA==.Selithira:BAABNQAECn8bAAINAAkKOxGIgQCTAQANAAkKOxGIgQCTAQAAAA==.Sephylon:BAAANQADCgEIAQAAAA==.Sera:BAAANQADCgYICgAAAA==.Seton:BAAANQADCgUIBQABNQAECgoKOQAOAHEbAA==.',
Sh='Shabagnarang:BAAANQAECgYIEQABNQAECggIJgAUAFMbAA==.Shadeofdark:BAABNQAECn8vAAIoAAoKph1mEACqAgAoAAoKph1mEACqAgAAAA==.Shalasyr:BAAANQAECgEIAgAAAA==.Shaletaz:BAAANQABCgQIBgAAAA==.Shamwowee:BAAANQADCggILQAAAA==.Shamzee:BAACNQAFFH8LAAIBAAMKZhZWGwDLAAABAAMKZhZWGwDLAAA1AAQKf0cAAgEACgqPH6IQADYDAAEACgqPH6IQADYDAAAA.Shandalf:BAAANQAECgMIAwABNQAECgUICAAPAAAAAA==.Sheyy:BAAANQAECgYIBwAAAA==.Shiftybonez:BAAANQADCgQIBQAAAA==.Shintok:BAAANQAECgUIDgAAAA==.Shuddarun:BAACNQAFFH8WAAIDAAkKUBirAQB0AgADAAkKUBirAQB0AgA1AAQKfz0AAgMACgosJV8NAHQDAAMACgosJV8NAHQDAAAA.',
Si='Silverbakk:BAAANQABCgEIAQAAAA==.Simn:BAAANQAECgYICwAAAA==.Sindraesong:BAAANQAECgUJCQAAAA==.',
Sk='Skithiryx:BAAANQAECgQICAABNQAECgoKOQAOAHEbAA==.Skuldd:BAAANQAECgYIEQAAAA==.',
Sl='Slayvylora:BAAANQAECgQIBAABNQAFFAUIFwAQAKkTAA==.',
Sm='Smarte:BAACNQAFFH8KAAISAAUKtRPaAADzAAASAAUKtRPaAADzAAA1AAQKfxcAAhIACgp9FYgHAPkBABIACgp9FYgHAPkBAAAA.Smolderpally:BAAANQADCgYIBgAAAA==.',
Sn='Sneaks:BAAANQADCgUIBQAAAA==.Sneakymoth:BAAANQADCgUIBQABNQAECggIFQAXAP4UAA==.Snookums:BAABNQAECn8fAAIOAAoKLhZ6GADvAQAOAAoKLhZ6GADvAQAAAA==.',
So='Soarin:BAAANQADCgQIBAAAAA==.',
Sp='Spicymaker:BAABNQAECn8nAAILAAoKkxwHVQCLAgALAAoKkxwHVQCLAgAAAA==.',
St='Starya:BAAANQAECgUICQAAAA==.Steelheart:BAAANQABCgQIBAAAAA==.Stolensøul:BAAANQABCggIDAAAAA==.Stop:BAAANQAECgMIAwAAAA==.Strifewood:BAAANQAECgcIBwAAAA==.Stumper:BAABNQAECn84AAIHAAoKXhc5KgCuAQAHAAoKXhc5KgCuAQAAAA==.',
Su='Suluna:BAAANQABCgQIBAABNQAECgoKXwABAMQgAA==.Sux:BAAANQADCgMIAwAAAA==.',
Sy='Sybrina:BAABNQAECn9HAAIDAAoKXBeJRABKAgADAAoKXBeJRABKAgAAAA==.Sylvia:BAABNQAECn8nAAIYAAoKtxJNwwD+AQAYAAoKtxJNwwD+AQAAAA==.Syngeance:BAABNQAECn8lAAIDAAgK/QYrpABrAQADAAgK/QYrpABrAQAAAA==.Synèsterwolf:BAAANQAECggIDQAAAA==.',
['Sí']='Síf:BAAANQAECgEIAQAAAA==.',
Ta='Tadeusz:BAAANQAECgcICgAAAA==.Taelah:BAAANQAECggIAgAAAA==.Tamamò:BAAANQADCgYICAAAAA==.Tanglefoot:BAABNQAECn8gAAILAAgKFhKHgAAaAgALAAgKFhKHgAAaAgAAAA==.Tanleros:BAABNQAECn8lAAMJAAoK3hNBSQDuAQAJAAoK3hNBSQDuAQAIAAIKTwnCkgE4AAAAAA==.Taquítos:BAAANQADCgYICAAAAA==.Tasigur:BAABNQAECn8YAAIUAAgKnQ/bGACGAQAUAAgKnQ/bGACGAQABNQAECgoKOQAOAHEbAA==.',
Te='Telana:BAAANQADCggILQAAAA==.Tentación:BAAANQADCggICAABNQAECgkJIwAKAGERAA==.Tequitos:BAAANQAECgcIEQAAAA==.',
Th='Theduk:BAABNQAECn88AAMZAAoKUhfuRQDnAQAZAAoKBxfuRQDnAQAeAAkK4QrXQADIAQAAAA==.Theduke:BAAANQAECgQIBAAAAA==.Theliria:BAAANQADCgYIBgAAAA==.Thorias:BAABNQAECn8ZAAIYAAgKKxtkjgBiAgAYAAgKKxtkjgBiAgAAAA==.',
To='Toira:BAAANQADCgUIBQAAAA==.Tomoko:BAAANQADCgYICQAAAA==.Torment:BAABNQAECn9OAAIQAAoKjx4zDADQAgAQAAoKjx4zDADQAgAAAA==.',
Tr='Tristén:BAABNQAECn80AAIDAAoKEh2nIQC5AgADAAoKEh2nIQC5AgAAAA==.Truvie:BAAANQADCgMIAwAAAA==.',
Tu='Tumbled:BAABNQAECn8WAAIYAAgKcxCF5QC+AQAYAAgKcxCF5QC+AQAAAA==.Tumbles:BAAANQADCgQIBQAAAA==.Tumni:BAABNQAECn8aAAICAAgKCAvwZgBSAQACAAgKCAvwZgBSAQAAAA==.',
Tw='Twinkletoes:BAAANQAECgMIAwAAAA==.',
['Tá']='Tángall:BAAANQABCgEIAQAAAA==.',
Ui='Ui:BAAANQADCgMIAwAAAA==.',
Ul='Ulnuk:BAABNQAECn9QAAIBAAoKfh9DCwBuAwABAAoKfh9DCwBuAwAAAA==.Ulster:BAAANQADCgEIAQAAAA==.',
Un='Ungodly:BAABNQAECn8uAAInAAoKjxHJNwD3AQAnAAoKjxHJNwD3AQAAAA==.Unholyshan:BAAANQAECgIIAgABNQAECgUICAAPAAAAAA==.Unidus:BAAANQAECgEIAgAAAA==.',
Uu='Uutr:BAAANQABCgEIAQAAAA==.',
Uv='Uvvolx:BAAANQADCgQICAAAAA==.',
Va='Vadka:BAABNQAECn8fAAIJAAgKQxs9JwCQAgAJAAgKQxs9JwCQAgAAAA==.Vaeldrin:BAAANQAECgQIBQAAAA==.Vaha:BAAANQAECgQIDAAAAA==.Valkree:BAAANQAECgUIDgAAAA==.Valroc:BAAANQADCgYIDAAAAA==.Valsavis:BAABNQAECn89AAIkAAoKQyBABgC6AgAkAAoKQyBABgC6AgAAAA==.Valtier:BAAANQADCgMIAwAAAA==.',
Ve='Veaolop:BAAANQABCggIEAAAAA==.Vellagosa:BAAANQAECgUIDAAAAA==.Vernice:BAAANQADCgYICwABNQAECgcICgAPAAAAAA==.Verulan:BAAANQAECgYIDgAAAA==.Vexidari:BAAANQAECgYIDwABNQAFFAUIFwAQAKkTAA==.Vexomous:BAABNQAECn8eAAMSAAgKgBqrBQBbAgASAAgKgBqrBQBbAgAEAAQKDgdTWwC3AAABNQAFFAUIFwAQAKkTAA==.',
Vi='Viiolet:BAACNQAFFH8GAAIDAAMK2hffEQD6AAADAAMK2hffEQD6AAA1AAQKfxYAAwMACgrnGDSAALkBAAMABgpoHTSAALkBAAQABgrODmBEADUBAAAA.',
Vo='Voidmayne:BAABNQAECn8uAAIIAAoKHRQQoADhAQAIAAoKHRQQoADhAQAAAA==.Vongogh:BAAANQADCgYICQAAAA==.Vonhelsing:BAAANQAECgQIBAAAAA==.Vorenius:BAAANQAECggICgAAAA==.',
Vy='Vynnara:BAAANQADCgEIAQAAAA==.Vyolent:BAAANQADCgYICwAAAA==.',
Wa='Wapello:BAAANQABCgcIEwAAAA==.Warnox:BAAANQAECgIIAgAAAA==.',
We='Weiand:BAABNQAECn8+AAMIAAkK6xoSPgBwAgAIAAkK6xoSPgBwAgAJAAcKLQx5jwBvAQAAAA==.Wevark:BAABNQAECn8XAAILAAkKLgpqtQCXAQALAAkKLgpqtQCXAQAAAA==.',
Wh='Whatami:BAABNQAECn9FAAQWAAoKyBtaJgB3AgAWAAoKyBtaJgB3AgAVAAMKrxKgHQCKAAAcAAIKBxLBIABuAAAAAA==.Wholemilk:BAABNQAECn8nAAIOAAcKZh6+HQC3AQAOAAcKZh6+HQC3AQAAAA==.',
Wi='Wilhellena:BAABNQAECn8/AAINAAoKrBWbMACBAgANAAoKrBWbMACBAgAAAA==.Wilhellfu:BAAANQADCgMIAwAAAA==.Winariel:BAABNQAECn8sAAIcAAoKZBybAQCfAgAcAAoKZBybAQCfAgAAAA==.Witewalker:BAAANQADCgcICgAAAA==.',
Wo='Wobum:BAAANQABCgUIBQAAAA==.',
Wr='Writhesoul:BAAANQABCgIIAgABNQAECgoKLAACAHcXAA==.Wroughtsoul:BAABNQAECn8kAAQbAAoK9gmaGAB3AQAbAAoK9gmaGAB3AQAaAAIKvQv9XgBkAAAjAAEKAADWLwA+AAAAAA==.Wrysoul:BAABNQAECn8sAAICAAoKdxeANACmAgACAAoKdxeANACmAgAAAA==.',
Wy='Wynston:BAAANQADCgEIAQAAAA==.Wyrmheart:BAAANQADCgIIAwAAAA==.',
Xa='Xaldred:BAABNQAECn8fAAIWAAoK7Qx5hQDYAQAWAAoK7Qx5hQDYAQABNQAECgoKRwARAJ8cAA==.Xandir:BAABNQAECn8mAAMKAAkKhhOJIQBiAQAKAAkKhhOJIQBiAQAIAAEKNgluqgEpAAAAAA==.Xarhunt:BAAANQAECgQICwAAAA==.',
Xe='Xenzia:BAAANQADCgcICwAAAA==.Xeracil:BAAANQADCgQIDQAAAA==.Xerras:BAAANQAECgIIAwAAAA==.',
Xo='Xoric:BAABNQAECn83AAImAAoKwBkTEQC2AgAmAAoKwBkTEQC2AgAAAA==.',
Xy='Xyal:BAABNQAECn8pAAINAAkKNhexbwDOAQANAAkKNhexbwDOAQAAAA==.Xyp:BAAANQADCgYIBgABNQAECgYIDgAPAAAAAA==.',
Ya='Yamaya:BAAANQADCgYICwAAAA==.',
Yi='Yiago:BAAANQAECgUIEAAAAA==.',
Yo='Youknow:BAAANQADCgcICwAAAA==.',
Za='Zaelia:BAAANQADCgEIAQAAAA==.Zaxhdk:BAEANQADCgMIAwABNQAECgkJHwAJADUSAA==.Zaxhpal:BAEBNQAECn8fAAIJAAkKNRIndgC1AQAJAAkKNRIndgC1AQAAAA==.',
Ze='Zenedy:BAAANQAECgQIBAABNQAECgcICgAPAAAAAA==.Zerrus:BAAANQAECgQIBAAAAA==.',
Zi='Zid:BAAANQAECgMIAwAAAA==.Ziny:BAAANQADCgUIBQAAAA==.Ziparoo:BAABNQAECn88AAIXAAoKpAz7DgCiAQAXAAoKpAz7DgCiAQAAAA==.',
Zo='Zoenova:BAAANQAECggIAgAAAA==.',
Zr='Zraven:BAAANQADCgEIAQAAAA==.',
['În']='Îniquitous:BAAANQAECgUIDgAAAA==.',
['Ðê']='Ðêmønicßløøð:BAABNQAECn8mAAMnAAoK5BS7LAD9AQAnAAoK5BS7LAD9AQARAAMKggrGsACQAAABNQAFFAEIAgAPAAAAAA==.',
['Üb']='Übernasus:BAAANQADCgQIBgAAAA==.',
['ßy']='ßyrøßløøð:BAAANQAECgEIAQAAAA==.',
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
