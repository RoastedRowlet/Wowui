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
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aabbigale:BAAANQAECggIAQAAAA==.',
Ab='Abigt:BAAANQADCgIIAQAAAA==.',
Ac='Acidsnow:BAAANQAECgQIBQAAAA==.',
Ad='Adalaidê:BAAANQAECgMICwAAAA==.',
Ae='Aerynne:BAAANQAECgMIBQAAAA==.',
Ai='Airie:BAABNQAECn8vAAMBAAoKUgnJagBdAQABAAoKUgnJagBdAQACAAUKUgYgwgBzAAAAAA==.',
Ak='Akuso:BAAANQADCgIIAgAAAA==.',
Al='Alcohaulorc:BAAANQAECgQIBwAAAA==.Alert:BAAANQAECgEIAQAAAA==.Aloris:BAAANQAECgQICAAAAA==.Aloy:BAACNQAFFH8QAAMDAAQKwRcPEABaAQADAAQKwRcPEABaAQAEAAEKAABwKAAzAAA1AAQKfxUAAgMABQo8HzahAFUBAAMABQo8HzahAFUBAAAA.Aluhx:BAAANQAECgMICQABNQAFFAYICwAFAJQRAA==.',
Am='Amednato:BAABNQAECn8cAAMGAAoKeweYLAA0AQAGAAoKeweYLAA0AQAHAAIKgAYsdQBVAAAAAA==.',
An='Anaeli:BAABNQAECn9fAAIBAAoKxCCIGwABAwABAAoKxCCIGwABAwAAAA==.Anastarian:BAAANQAECgMIBgAAAA==.Ancalagonn:BAAANQAECgcIDwAAAA==.Angita:BAAANQAECgUIDAAAAA==.Anklin:BAAANQADCgIIAgAAAA==.Annaris:BAACNQAFFH8ZAAIDAAcKOBwCAwA8AgADAAcKOBwCAwA8AgA1AAQKfy8AAwMACgr3JUMHAKIDAAMACgr3JUMHAKIDAAQACQrJGS0yALwBAAAA.Antipæn:BAECNQAFFH8LAAMIAAMKFSJpEwAfAQAIAAMKFSJpEwAfAQAJAAEKdCO9JQBlAAA1AAQKf0sAAwgACgrBJqIEANQDAAgACgrBJqIEANQDAAkACgoiITkLAG4DAAAA.',
Ap='Apologia:BAABNQAECn8/AAMIAAoKeiJqHADnAgAIAAoKeiJqHADnAgAKAAIKVghJZAAsAAAAAA==.',
Aq='Aquaphobic:BAAANQAECgUIDAABNQAFFAcIFAABAGYJAA==.',
Ar='Arcanoth:BAAANQADCgIIAgAAAA==.Ardicelia:BAAANQABCgUIBgAAAA==.Ares:BAABNQAECn8oAAILAAoK5R/7HQBAAwALAAoK5R/7HQBAAwAAAA==.Armorgorden:BAABNQAECn9LAAIMAAoKWSKiAwDyAgAMAAoKWSKiAwDyAgAAAA==.Aroviaa:BAABNQAECn89AAINAAoK5Ro1QABqAgANAAoK5Ro1QABqAgAAAA==.Arpmek:BAABNQAECn86AAIOAAoKtRVwJQAaAgAOAAoKtRVwJQAaAgAAAA==.Artemîs:BAAANQADCgIIAgAAAA==.',
As='Asharienne:BAABNQAECn8vAAIDAAoKXhC8WgD8AQADAAoKXhC8WgD8AQAAAA==.Ashilianar:BAAANQAECgUIBQAAAA==.Ashlynne:BAAANQAECgYJCwAAAA==.',
Au='Aubergine:BAAANQADCgQIBAAAAA==.Audiobully:BAAANQAECgQIBAABNQAECgoKNAAHAEoXAA==.Auntmary:BAAANQABCgUICAAAAA==.Auralynn:BAAANQAECgQJBAABNQAECgYJCwAPAAAAAA==.Auriella:BAABNQAECn8lAAMJAAoK0hAuaQDcAQAJAAoK0hAuaQDcAQAIAAIKsgjekwEtAAAAAA==.Aurtt:BAABNQAECn86AAMQAAoKshRJRQDlAQAQAAkKPhVJRQDlAQARAAMKEAlhXQCGAAAAAA==.',
['Aö']='Aöb:BAAANQADCgQIBgAAAA==.',
Ba='Bahahaknight:BAABNQAECn86AAIQAAoKbxdGGwAWAgAQAAoKbxdGGwAWAgAAAA==.Bahree:BAAANQADCgIIAgAAAA==.Bakhar:BAABNQAECn8xAAISAAkKaB6rAwBNAgASAAkKaB6rAwBNAgAAAA==.Balora:BAAANQADCgcIGAAAAA==.Barnette:BAABNQAECn9WAAITAAoKpRiUAQA1AgATAAoKpRiUAQA1AgAAAA==.Basyleus:BAAANQADCgEIAQAAAA==.',
Be='Beau:BAAANQAECgQICgABNQAECgkJGQAJAMgfAA==.Belthos:BAABNQAECn8ZAAIIAAgKSBgceQA6AgAIAAgKSBgceQA6AgAAAA==.Benihime:BAAANQAECgEIAQAAAA==.Berristan:BAABNQAECn9BAAMJAAoKtQ95YgDxAQAJAAoKtQ95YgDxAQAIAAEKegTFkQEuAAAAAA==.Bestwingman:BAAANQADCgEIAQAAAA==.',
Bi='Bigdawgsteve:BAAANQADCgIIAgAAAA==.Bigmarv:BAAANQAECgUIDAAAAA==.Bittytigs:BAACNQAFFH8TAAIBAAUKYhM2EgAdAQABAAUKYhM2EgAdAQA1AAQKf1QAAwEACgrOIJ8UACgDAAEACgrOIJ8UACgDAAIAAQoAAGBOAScAAAAA.',
Bl='Blestemat:BAAANQAECgEIAQAAAA==.Blossom:BAAANQAFFAQIBAABNQAFFAQIDQAPAAAAAQ==.Blumangood:BAABNQAECn85AAQCAAoKcBd9LQARAgACAAoKcBd9LQARAgABAAIKLQKKFQE/AAAUAAEKAADnNwAwAAAAAA==.',
Bo='Bollux:BAAANQAECgEIAgAAAA==.Bosc:BAABNQAECn8yAAIQAAoKYhaRIADnAQAQAAoKYhaRIADnAQAAAA==.Boudiicca:BAAANQAECgMIBQAAAA==.Boxmasterr:BAABNQAECn89AAMVAAoK4BW+BQBeAgAVAAgKqBi+BQBeAgAWAAcKOhHydABnAQAAAA==.',
Br='Braagh:BAAANQABCggICwAAAA==.Brasmir:BAABNQAECn9BAAISAAoKfB2oAgAIAwASAAoKfB2oAgAIAwAAAA==.Briae:BAAANQADCgMIAwABNQAECgoKXwABAMQgAA==.Brianzero:BAAANQADCgYIBwAAAA==.Brino:BAAANQAECgQIBAAAAA==.Brinotriage:BAAANQAECgUIBQAAAA==.',
Bu='Bubblemoth:BAAANQADCgMIBAABNQAECggIFQAXAP4UAA==.Buik:BAAANQAECgIIAgAAAA==.Bulge:BAABNQAECn8mAAMYAAoKUw0w0QDkAQAYAAoK8Qww0QDkAQAXAAEK2Rb9PwBEAAABNQAFFAQIEQARAGILAA==.Bulgogi:BAACNQAFFH8RAAIRAAQKYgtKCADMAAARAAQKYgtKCADMAAA1AAQKf0EAAhEACgoiIGYLALMCABEACgoiIGYLALMCAAAA.Butherrface:BAAANQADCgUIBQAAAA==.',
['Bö']='Börk:BAAANQAECgUIDAAAAA==.',
Ca='Capy:BAAANQAECgIIAgABNQAFFAQIBgAXAOQUAA==.Cardran:BAAANQADCgIIAgABNQAECgoKGAADAOASAA==.Cayda:BAAANQADCgYICwAAAA==.Caylara:BAABNQAECn8YAAIZAAYK/Qt0jQDbAAAZAAYK/Qt0jQDbAAAAAA==.Cayssabber:BAAANQAECgcIBQAAAA==.Cayssaber:BAAANQAECgIIAgAAAA==.',
Ce='Ceicilia:BAAANQADCgQIBAAAAA==.Celrythis:BAAANQAECgUICwAAAA==.Cenokry:BAAANQADCgYICQAAAA==.',
Ch='Chai:BAABNQAECn8dAAMaAAkKXQyENgBhAQAaAAkKXQyENgBhAQAbAAIKNAONQQAgAAAAAA==.Chaintrain:BAAANQAECgMIAwABNQAECgkJIAAWAE4WAA==.Chellyy:BAAANQAECgYIDwABNQAECgcIIQAOAIIdAA==.Chibisend:BAAANQADCgMIAwAAAA==.Chámeleon:BAAANQADCgEIAQAAAA==.',
Ci='Cider:BAAANQAECgIIAgAAAA==.',
Cl='Claes:BAAANQADCgMIAwABNQAECgoKMgAQAGIWAA==.',
Co='Coralbubbles:BAABNQAECn87AAIIAAoKnRM5XwAEAgAIAAoKnRM5XwAEAgAAAA==.Coralorchid:BAABNQAECn8wAAIKAAgKihohFgC3AQAKAAgKihohFgC3AQAAAA==.Coralprays:BAAANQADCggIEgAAAA==.Coralrages:BAAANQAECgQIBgAAAA==.',
Cr='Cromenockle:BAABNQAECn8UAAQVAAkKmBO+EwAPAQAWAAgKahIYhADcAQAVAAQKdw++EwAPAQAcAAIKuw4vWAB3AAABNQAFFAUICgASALUTAA==.Crtitman:BAAANQAECgUIDgAAAA==.',
Cu='Cupcâke:BAAANQAECgQIBgAAAA==.Curissan:BAABNQAECn8fAAICAAcKERTRbQDWAQACAAcKERTRbQDWAQAAAA==.',
Da='Dalgon:BAABNQAFFH8IAAIdAAQK6wRDEADvAAAdAAQK6wRDEADvAAABNQAFFAcIEAAJAKIUAA==.Dalir:BAAANQAECgYIDgAAAA==.Dalspin:BAAANQADCgYIDAAAAA==.Dalthepal:BAACNQAFFH8QAAIJAAcKohTvBwDnAQAJAAcKohTvBwDnAQA1AAQKf0gAAgkACgrzHzoXAB8DAAkACgrzHzoXAB8DAAAA.Damné:BAABNQAECn9BAAIRAAoKnxwjDgCMAgARAAoKnxwjDgCMAgAAAA==.Darze:BAAANQADCggIAwABNQAECggICgAPAAAAAA==.Davidline:BAABNQAECn80AAIIAAoKgx4QLACkAgAIAAoKgx4QLACkAgAAAA==.',
De='Deadish:BAABNQAECn9DAAMQAAoKbyHcCAD3AgAQAAoKbyHcCAD3AgARAAEKDQY3lwASAAAAAA==.Deathsaberss:BAABNQAECn9QAAMLAAoKNRsQLgB5AgALAAoKNRsQLgB5AgAMAAQK5Au+KgDjAAAAAA==.Deathvex:BAACNQAFFH8XAAIQAAUKqRM3FAAYAQAQAAUKqRM3FAAYAQA1AAQKfyMAAhAACgp9GtQTAGUCABAACgp9GtQTAGUCAAAA.Decoz:BAAANQAECgUICgAAAA==.Deight:BAAANQAECgUIBQAAAA==.Dejamoo:BAAANQADCgYIGAAAAA==.Deknivez:BAAANQAECgQIBAAAAA==.Dendahn:BAAANQAECgcIDQAAAA==.Destinee:BAAANQAECgQICwAAAA==.',
Di='Dianntha:BAAANQAECgEIAQAAAA==.Diladrin:BAABNQAECn9iAAIGAAoKgxsxDABnAgAGAAoKgxsxDABnAgAAAA==.Dinomight:BAAANQADCgQIBAAAAA==.',
Do='Doileag:BAABNQAECn8dAAIIAAcKuAVUNQHKAAAIAAcKuAVUNQHKAAAAAA==.Doomgrave:BAAANQADCgEIAQAAAA==.Dora:BAAANQADCgYIBgABNQAECgYIGwAeAHoGAA==.Dottmatrix:BAABNQAECn8YAAIcAAYKiQfpFwCVAAAcAAYKiQfpFwCVAAAAAA==.Doubledowns:BAAANQAECgEIAQAAAA==.',
Dr='Dreadwing:BAAANQAECgQICQAAAA==.Druromu:BAABNQAECn8YAAMLAAYK2w2FugDtAAALAAYK2w2FugDtAAAMAAEKAACWTgAAAAAAAA==.',
Du='Dufs:BAACNQAFFH8VAAIBAAUKDyY7CQC9AQABAAUKDyY7CQC9AQA1AAQKfy0AAgEACgrNH2wcAPwCAAEACgrNH2wcAPwCAAAA.Dunkan:BAAANQAECgMIAwAAAA==.Dustbunny:BAABNQAECn9JAAQNAAoKQRqEKQCRAgANAAoKQRqEKQCRAgAfAAEKVge2XgA0AAAgAAEK/gYoGwAoAAAAAA==.',
Dw='Dwagon:BAABNQAECn8UAAMhAAgKYQlaIgA4AQAhAAYKQQtaIgA4AQAiAAMK1gd5IABWAAAAAA==.Dwagonfells:BAAANQAECgIIBAAAAA==.',
Dy='Dylsonlolqt:BAABNQAECn8eAAIQAAkKhwjtNwBWAQAQAAkKhwjtNwBWAQAAAA==.',
['Dã']='Dãrling:BAAANQABCgEIAQAAAA==.',
['Dû']='Dûn:BAABNQAECn9AAAMaAAoK8CDLDQAAAwAaAAoK5SDLDQAAAwAjAAgKNh4pCgB1AgAAAA==.Dûna:BAABNQAECn8xAAIfAAoKkx0mCgCuAgAfAAoKkx0mCgCuAgABNQAECgoKQAAaAPAgAA==.',
El='Elaatia:BAABNQAECn8+AAIIAAoKySNjKgAdAwAIAAoKySNjKgAdAwAAAA==.Elidria:BAAANQABCgIIAgAAAA==.Ellysprocket:BAAANQADCgUICQAAAA==.Elrric:BAAANQAECgcICgAAAA==.Elyak:BAAANQADCgIIAgAAAA==.',
En='Envoy:BAAANQAECgQIBwAAAA==.',
Er='Erakron:BAABNQAECn9CAAMCAAoKuxdaJABGAgACAAoKuxdaJABGAgABAAYKmBPUpwAiAQAAAA==.Erine:BAAANQAECgUIBAAAAA==.Erouvi:BAAANQADCgIIAgABNQAECgoKPQANAOUaAA==.Eroviaa:BAAANQAECgUIBwABNQAECgoKPQANAOUaAA==.Erovvia:BAAANQADCgUIBQABNQAECgoKPQANAOUaAA==.',
Es='Esmeralda:BAAANQABCggIEAAAAA==.',
Et='Etali:BAAANQADCgYIBQABNQAECgoKOQAOAHEbAA==.',
Ev='Evorik:BAAANQAECgYICQABNQAFFAIIBQALAH4TAA==.',
Ez='Ezothen:BAABNQAECn8cAAMhAAcKfAegFgC8AAAhAAcKfAegFgC8AAAiAAEKJAUoHQAsAAAAAA==.',
Fa='Facelessman:BAAANQABCggILAAAAA==.Faedoria:BAAANQAECgUIDwAAAA==.Faeryln:BAABNQAECn9KAAINAAoK4QkdbACAAQANAAoK4QkdbACAAQAAAA==.Faustus:BAABNQAECn8ZAAIJAAkKyB8jJgDRAgAJAAkKyB8jJgDRAgAAAA==.Favion:BAAANQADCgEIAQAAAA==.',
Fe='Felyyia:BAABNQAECn8nAAIOAAoK3yKGBAAXAwAOAAoK3yKGBAAXAwABNQAFFAcIGQADADgcAA==.',
Fi='Fiddlestix:BAAANQAECgQIBAAAAA==.Firebrande:BAAANQAECgUIDAAAAA==.Fisticuffs:BAAANQADCggIKwAAAA==.Fizcrankshot:BAABNQAECn9JAAIDAAoKPhnlNQBhAgADAAoKPhnlNQBhAgAAAA==.',
Fl='Flamewhisker:BAAANQAECgYIDAAAAQ==.Flamez:BAAANQADCgcIBwAAAA==.Flandre:BAAANQAECgUIBAAAAA==.',
Fr='Fraublucher:BAABNQAECn82AAINAAoKhglMYwCeAQANAAoKhglMYwCeAQAAAA==.Frewyn:BAAANQAECgYIDgAAAA==.Frostimoth:BAABNQAECn8VAAIXAAgK/hS9EQCKAQAXAAgK/hS9EQCKAQAAAA==.Frozty:BAAANQAECgQIBgAAAA==.',
Ga='Galandel:BAAANQADCggIKAAAAA==.Galial:BAACNQAFFH8MAAIkAAQK9hCsAgCpAAAkAAQK9hCsAgCpAAA1AAQKfzMAAiQACgpfGgwHAKACACQACgpfGgwHAKACAAAA.Gantar:BAAANQAECgUIBQABNQAFFAUIDQAQAD0dAA==.Garradin:BAAANQADCgEIAQAAAA==.Garrunter:BAAANQAECggIDwAAAA==.Gaznol:BAAANQADCgQIBAABNQAECgoKHAAGAHsHAA==.',
Ge='Gelasera:BAAANQAECgUICwAAAA==.Gemitra:BAAANQADCgcIBwABNQAECggIMAAKAIoaAA==.Geneth:BAAANQAECgUIBQAAAA==.George:BAACNQAFFH8FAAILAAIKfhPSLgCPAAALAAIKfhPSLgCPAAA1AAQKfzEAAgsACQpiHz5CACwCAAsACQpiHz5CACwCAAAA.',
Gh='Ghalta:BAAANQADCgIIAgABNQAECgoKOQAOAHEbAA==.Ghrol:BAAANQABCgYIBgABNQAECgoKRgABAH4fAA==.',
Gl='Glaivethras:BAABNQAECn9HAAIkAAoK3iM7AQA5AwAkAAoK3iM7AQA5AwAAAA==.Glenfin:BAAANQADCgQIBgAAAA==.',
Gr='Greg:BAAANQAECgEIAgAAAA==.Gremlynn:BAAANQADCggICAAAAA==.Grimclaw:BAACNQAFFH8QAAMlAAgKLhk0AADZAQAlAAcKoBo0AADZAQAHAAUKSAndFgD7AAA1AAQKfy8AAwcACgorJcseANQCAAcACAqVIsseANQCACUABgrnJR4QAKUBAAAA.Groot:BAABNQAECn8aAAMmAAcKqhdAPgD8AAAmAAcKqhdAPgD8AAAHAAMK8wyrjQCgAAABNQAECgkJIwAKAGERAA==.',
Gu='Guthrek:BAAANQAECgYICwAAAA==.',
Ha='Hamfist:BAAANQADCgIIAgABNQAECgoKFAAVABgSAA==.Hannebal:BAABNQAECn8rAAIJAAoKJxUqLwBUAgAJAAoKJxUqLwBUAgAAAA==.',
He='Healsonyou:BAAANQAFFAEIAgABNQAECgoKMAALAG8bAA==.Healyclam:BAAANQADCgMIAwAAAA==.Heydaw:BAAANQADCggICAABNQAECgkJGAAnAJUbAA==.Heynow:BAABNQAECn8eAAIUAAkKVAhWFwCEAQAUAAkKVAhWFwCEAQAAAA==.',
Hi='Higherp:BAAANQADCggICAABNQAECgcILgAlAKYRAA==.Highmountain:BAAANQADCggIDQAAAA==.Hilimed:BAABNQAECn9MAAIWAAoK3QzVVgC8AQAWAAoK3QzVVgC8AQAAAA==.',
Ho='Hobs:BAAANQADCgUIBQAAAA==.Holyßloodelf:BAAANQAECgcIDgABNQAECgoKMAALAG8bAA==.Hoosier:BAABNQAECn8eAAINAAkKShi6JgCiAgANAAkKShi6JgCiAgAAAA==.Hoplite:BAABNQAECn8eAAImAAoKshXaFgBKAgAmAAoKshXaFgBKAgAAAA==.',
Hu='Huasca:BAAANQAECgEIAQAAAA==.Huthuel:BAAANQABCggIFAAAAA==.',
Hy='Hydra:BAAANQADCgYIBgABNQAECgoKJwAYALcSAA==.Hyve:BAAANQAECgMIAwABNQAECgoKTAAIANkZAA==.',
['Hà']='Hàney:BAAANQAECgQIBAAAAA==.',
['Hé']='Hélio:BAAANQADCgUIBQAAAA==.',
Ia='Ia:BAABNQAECn8+AAInAAoKdSKICgACAwAnAAoKdSKICgACAwAAAA==.',
Ib='Ibesmashin:BAAANQADCgQIBAABNQAECgoKFAAVABgSAA==.Ibesneakin:BAAANQAECgQIBAABNQAECgoKFAAVABgSAA==.',
Id='Idontsuck:BAAANQADCggICwAAAA==.',
Il='Ileynha:BAABNQAECn8UAAIVAAkKIQnnCwBpAQAVAAkKIQnnCwBpAQAAAA==.Ilieau:BAAANQAECgQIBQABNQAECggIEQAPAAAAAA==.Illida:BAAANQADCgYIBgAAAA==.',
Im='Imamalelol:BAABNQAECn8XAAMLAAYKQAUO/gDgAAALAAYKQAUO/gDgAAAFAAMK5ATnNgArAAAAAA==.',
In='Inarrah:BAAANQADCgEIAQAAAA==.Intol:BAAANQAFFAQIDQAAAQ==.Intrepidhero:BAAANQADCgEIAQAAAA==.',
Ir='Irkenfox:BAECNQAFFH8ZAAIMAAUKfBYsAwDKAAAMAAUKfBYsAwDKAAA1AAQKfzEAAgwACgoJJKQCAIYDAAwACgoJJKQCAIYDAAAA.',
It='Ithran:BAAANQADCgUIBQAAAA==.',
Iw='Iwilltank:BAAANQADCgYICwAAAA==.',
Ix='Ixitt:BAABNQAECn8xAAITAAoKrxg9AgA6AgATAAoKrxg9AgA6AgAAAA==.',
Ja='Jama:BAAANQADCgYIBgAAAA==.Janderick:BAAANQAECgcIDwAAAA==.Jaromer:BAAANQADCgcIEAAAAA==.',
Je='Jellacee:BAAANQADCgcIFwAAAA==.',
Ji='Jimboberjim:BAACNQAFFH8YAAIcAAUKMiK4AAB9AQAcAAUKMiK4AAB9AQA1AAQKfzUAAhwACgrsI2wBAHsDABwACgrsI2wBAHsDAAAA.Jimbobwhey:BAABNQAECn8pAAIjAAoKghocBAB0AgAjAAoKghocBAB0AgAAAA==.Jiminie:BAABNQAECn8eAAIMAAgKPxMdFgDHAQAMAAgKPxMdFgDHAQABNQAECgoKKQAjAIIaAA==.',
Jo='Jolio:BAABNQAECn8gAAQWAAkKThaYqgB9AQAWAAgKLhSYqgB9AQAcAAEKuBq9aABQAAAVAAIKrBdyKABKAAAAAA==.Joltraxi:BAAANQADCggICAABNQAECgkJIAAWAE4WAA==.Joshie:BAACNQAFFH8NAAIQAAUKPR23DgD8AAAQAAUKPR23DgD8AAA1AAQKfzEAAhAACgoSJOgJAGYDABAACgoSJOgJAGYDAAAA.Joshy:BAAANQADCgcIBwABNQAFFAUIDQAQAD0dAA==.',
Ju='Jujubeans:BAAANQAECgEIAQAAAA==.Juniornite:BAABNQAECn9IAAIYAAoK2yI9FADxAgAYAAoK2yI9FADxAgAAAA==.Justthetouch:BAAANQAECggIEwAAAA==.',
Jy='Jygglypuff:BAAANQAECgMIBAAAAA==.',
Ka='Kadaan:BAAANQAECgYIBgAAAA==.Kagemaro:BAABNQAECn85AAMOAAoKcRtBFQC7AgAOAAoKcRtBFQC7AgAkAAUKdRS7GQAZAQAAAA==.Kahgar:BAAANQAECggILAABNQAECgoKWwAJANMZAQ==.Kalimathath:BAAANQAECgQIBgAAAA==.Kalzod:BAABNQAECn9WAAIWAAoK4SXyAQDcAwAWAAoK4SXyAQDcAwAAAA==.Kataki:BAABNQAECn8wAAIDAAkKlxw/KACRAgADAAkKlxw/KACRAgABNQAECgoKOQAOAHEbAA==.Katia:BAAANQAECgUIDwAAAA==.Kativeria:BAAANQAECgUICgAAAA==.Katjayna:BAAANQADCgUICgAAAA==.Kaysabr:BAAANQAECgUIBQAAAA==.Kayssaber:BAABNQAECn8iAAMmAAoKQhPfGwAMAgAmAAoKQhPfGwAMAgAHAAMK5BDvjwCXAAAAAA==.',
Ke='Kebab:BAAANQAECgQJBAAAAA==.Kelsifer:BAAANQAECgQICwABNQAECgkJGQAJAMgfAA==.Kempra:BAAANQADCgcIBwAAAA==.Kemprei:BAAANQADCgUIBQAAAA==.Kendralust:BAAANQAECgcICAAAAA==.Kerfufle:BAAANQABCgIJAgAAAA==.',
Kh='Khaos:BAAANQABCgEIAQAAAA==.',
Ki='Killmora:BAAANQADCggILQAAAA==.Kippars:BAAANQAECgIIAgAAAA==.Kiritsugo:BAAANQADCggICwAAAA==.',
Kl='Klaax:BAAANQAECgcICAABNQAECgoKTAAIANkZAA==.',
Ko='Kodazoff:BAABNQAECn8aAAMhAAkKagmGDQBgAQAhAAkKagmGDQBgAQAdAAEKTwOjUwAkAAAAAA==.Kora:BAAANQABCgEIAgAAAA==.Korevash:BAABNQAECn87AAMBAAoKZCP9AwCrAwABAAoKZCP9AwCrAwAUAAYKAhJaHACeAQAAAA==.',
Kr='Krezz:BAAANQAECgEIAQAAAA==.Krissylu:BAAANQAECgYIDgAAAA==.Krothix:BAABNQAECn9AAAICAAoKSwdyXABZAQACAAoKSwdyXABZAQAAAA==.Krudd:BAAANQAECgcIDQAAAA==.Krychilly:BAAANQADCgcIFwAAAA==.Kryrande:BAAANQADCgQICwAAAA==.Kryshym:BAABNQAECn8cAAIJAAYKtiDiTAA2AgAJAAYKtiDiTAA2AgAAAA==.Krythrall:BAAANQAECgEIAQABNQAECgYIHAAJALYgAA==.Krytree:BAAANQADCgYIBgAAAA==.Kryvelen:BAABNQAECn8gAAMNAAoKOhpZHgDXAgANAAoKyRlZHgDXAgAgAAcKExaNBADcAQAAAA==.Krëëp:BAAANQAECggICAAAAA==.',
Ks='Kspectactle:BAAANQAECgMIBAAAAA==.',
Ku='Kuilei:BAAANQADCgYJCwABNQAECgQICgAPAAAAAA==.Kurorø:BAABNQAECn8cAAIDAAcKjQsFtQAsAQADAAcKjQsFtQAsAQAAAA==.',
Ky='Kyrayna:BAAANQADCgYIEgAAAA==.',
['Kä']='Käisèr:BAAANQABCgEIAQAAAA==.',
La='Ladara:BAABNQAECn8oAAIVAAkKixQxBgBPAgAVAAkKixQxBgBPAgAAAA==.Laima:BAAANQADCgUICQAAAA==.Landil:BAAANQADCgYIDAAAAA==.Lavitz:BAAANQAECgEIAQAAAA==.',
Le='Leheo:BAAANQAECgQIBgAAAA==.Lehua:BAAANQADCggICgAAAA==.Leilanii:BAAANQADCgcIEQAAAA==.Lemook:BAABNQAECn8dAAImAAoKDRKJIwC7AQAmAAoKDRKJIwC7AQAAAA==.Leonìdas:BAAANQADCggIGQAAAA==.Leð:BAAANQAECggICAAAAA==.',
Li='Licker:BAAANQAECgUICQABNQAFFAUICgASALUTAA==.Life:BAAANQADCgcICgAAAA==.Lightbulb:BAAANQADCgYIDQAAAA==.Lightsorrow:BAAANQAECgcICgABNQAECgoKMgAiADsTAA==.Lightstormer:BAAANQADCgcIJQAAAA==.Lilamae:BAAANQAECgUIDQAAAA==.Lilarielle:BAABNQAECn9HAAIlAAoKhAa1HwDnAAAlAAoKhAa1HwDnAAAAAA==.Lildookie:BAABNQAECn8dAAICAAoKugiNUwB2AQACAAoKugiNUwB2AQAAAA==.Lilface:BAAANQAECggIDAAAAA==.Lilhands:BAAANQAECgQIAwAAAA==.Liliel:BAAANQADCgMIAwABNQAECgoKGAADAOASAA==.Liliela:BAABNQAECn8YAAIDAAoK4BKuaABCAgADAAoK4BKuaABCAgAAAA==.Lilyannah:BAAANQADCgEIAQAAAA==.Liodragon:BAAANQADCgUIBQABNQAECgcICgAPAAAAAA==.Liolock:BAAANQAECggIBwAAAA==.Lite:BAAANQAECgQIBAAAAA==.Liø:BAAANQAECgcICgAAAA==.',
Ll='Lluniez:BAABNQAECn8pAAIaAAoKeQ8lGQDQAQAaAAoKeQ8lGQDQAQAAAA==.',
Lm='Lmccoy:BAAANQABCgQIBAAAAA==.',
Lo='Lockroknroll:BAABNQAECn8UAAIVAAoKGBKFBgBEAgAVAAoKGBKFBgBEAgAAAA==.Loissa:BAAANQAECggIEAAAAA==.Losoli:BAABNQAECn9JAAIJAAoKUx9JGADlAgAJAAoKUx9JGADlAgAAAA==.Lowchin:BAAANQAECgQIBQAAAA==.',
Lu='Lupine:BAAANQADCgYIBgABNQAECgYICwAPAAAAAA==.Lutherion:BAABNQAECn8xAAIMAAoKBB4SBgAJAwAMAAoKBB4SBgAJAwAAAA==.',
Ly='Lycemmas:BAABNQAECn8mAAIBAAoK1Ri8RQBKAgABAAoK1Ri8RQBKAgAAAA==.',
['Lï']='Lïo:BAAANQADCgYIBwABNQAECgcICgAPAAAAAA==.',
Ma='Macoun:BAABNQAECn8yAAIDAAoKISO6EAAGAwADAAoKISO6EAAGAwAAAA==.Magicshowers:BAABNQAECn8+AAIYAAoKzyKsNwAZAwAYAAoKzyKsNwAZAwAAAA==.Majiique:BAAANQABCggIGAAAAA==.Manseed:BAAANQABCgQJBAAAAA==.Maple:BAAANQAECgYICwAAAA==.Martei:BAACNQAFFH8XAAIlAAUK2xfCAQBJAQAlAAUK2xfCAQBJAQA1AAQKfzAAAiUACgpWHTsHAO8CACUACgpWHTsHAO8CAAAA.Maríneth:BAAANQAECgUIEQAAAA==.Mascara:BAAANQAECgYICwAAAA==.Maxe:BAAANQADCgIIAgAAAA==.',
Me='Memebait:BAAANQAECgUIBQAAAA==.Mementomori:BAAANQAECgEIAQAAAA==.Meowbae:BAAANQAECgUIBQABNQAECgQIBgAPAAAAAA==.Merce:BAAANQADCgcIBwABNQAECgoKGAADAOASAA==.Mercesdes:BAAANQAECgEIAgAAAA==.',
Mi='Midway:BAAANQAECgQIBgAAAA==.Minizee:BAAANQAECgEIAQAAAA==.Mirokushan:BAAANQAECgMIBQAAAA==.Missfire:BAAANQAECgIIAwAAAA==.Misticlady:BAAANQAECgQIBgAAAA==.Mistrariel:BAAANQAECgYIBgABNQAECgoKJgAcAMYbAA==.Mizukì:BAAANQABCgQIBgAAAA==.',
Mo='Moluubar:BAABNQAECn8pAAMLAAoKphMHfgAgAgALAAoKphMHfgAgAgAMAAEKAAAITQAAAAAAAA==.Moradin:BAAANQADCgMIAwAAAA==.Mordemour:BAAANQAECggICgAAAA==.',
Mu='Mufler:BAAANQABCgQIBQAAAA==.Mungo:BAABNQAECn8XAAIYAAgKMQo3wgAQAQAYAAgKMQo3wgAQAQAAAA==.Mushù:BAAANQAECgUICgABNQAECgoKOwAWAEQbAA==.',
My='Myfire:BAAANQADCgYIBgAAAA==.Myrell:BAAANQAECggICAAAAA==.Myrrh:BAAANQAECgYIDwAAAA==.',
Na='Nalik:BAAANQAECgYIDgAAAA==.Nanou:BAAANQAECgUIBwAAAA==.Nardiaun:BAAANQADCgYIBgAAAA==.Naturebait:BAAANQADCgQIBAABNQAECgoKOQACAHAXAA==.',
Ne='Nerzheul:BAABNQAECn8aAAIQAAgK5AwFQgAoAQAQAAgK5AwFQgAoAQAAAA==.',
Ni='Nicety:BAAANQAECgMIAwAAAA==.Nimravidae:BAABNQAECn87AAIJAAoKVRdlMABOAgAJAAoKVRdlMABOAgAAAA==.Ninelives:BAABNQAECn8dAAIHAAoKogIcWACuAAAHAAoKogIcWACuAAAAAA==.Nitecrawler:BAAANQADCgQIBAAAAA==.Niteeye:BAAANQABCgIIAgABNQAECgoKSAAYANsiAA==.Niteryu:BAAANQAECgEIAwABNQAECgoKSAAYANsiAA==.',
No='Nolokkotal:BAABNQAECn8wAAILAAoKbxtkRAAkAgALAAoKbxtkRAAkAgAAAA==.Nospitfisty:BAAANQADCgQIBAAAAA==.Noxolon:BAABNQAECn8dAAMFAAgKshGIFABXAQAFAAgKshGIFABXAQALAAEKAADYWwErAAAAAA==.',
Nr='Nreaf:BAACNQAFFH8IAAIIAAUK7QjxFQD/AAAIAAUK7QjxFQD/AAA1AAQKfywAAggACgrKE7uHABgCAAgACgrKE7uHABgCAAAA.',
['Nø']='Nørd:BAAANQADCgYIBgAAAA==.',
Oi='Oili:BAACNQAFFH8RAAIXAAUKaxSGAgAMAQAXAAUKaxSGAgAMAQA1AAQKfzEAAxcACgruGdcHAG0CABcACgruGdcHAG0CABgABAoADs9zAdcAAAAA.',
Ol='Olarrick:BAAANQAECgQIBQABNQAFFAIIBQALAH4TAA==.',
Oo='Oops:BAACNQAFFH8SAAIQAAUKjRtFEgAzAQAQAAUKjRtFEgAzAQA1AAQKf0IAAxAACgrNIHERACEDABAACgrNIHERACEDABEAAQqwCr2GADAAAAAA.',
Or='Orcchopped:BAAANQADCgQIBAAAAA==.Ornstein:BAEBNQAECn8YAAIKAAcK1h2eFwClAQAKAAcK1h2eFwClAQAAAA==.',
Ot='Ottuk:BAACNQAFFH8GAAIRAAMKFgmAGgCGAAARAAMKFgmAGgCGAAA1AAQKfywAAhEACgrqHZMfAM4CABEACgrqHZMfAM4CAAAA.',
Pa='Padpaw:BAAANQAECgUJCAAAAA==.Pakraxes:BAABNQAECn8zAAIhAAoKBQ+bFQDyAQAhAAoKBQ+bFQDyAQAAAA==.Paksenarrion:BAABNQAECn88AAIKAAoKOBJmFwCoAQAKAAoKOBJmFwCoAQAAAA==.Palehoof:BAAANQADCggIGgABNQAECgEIAgAPAAAAAA==.Pallywaya:BAABNQAECn8mAAMIAAoKxRAgbQDjAQAIAAoKxRAgbQDjAQAJAAkKgwWUygBvAAAAAA==.Pandemonîum:BAAANQAECgQIBAABNQAECgoKLAAaABEXAA==.Pandemônium:BAAANQADCgMIAwABNQAECgoKLAAaABEXAA==.Pandemönium:BAABNQAECn8lAAQIAAgKeh0fVgCTAgAIAAgKUh0fVgCTAgAKAAIKzRxTUwCXAAAJAAMKcApavQCNAAABNQAECgoKLAAaABEXAA==.Pandemöniüm:BAABNQAECn8sAAMaAAoKEReQEABBAgAaAAoKEReQEABBAgAbAAQKVBDyKQChAAAAAA==.Parts:BAAANQABCggIDwAAAA==.Patchington:BAABNQAECn8YAAIKAAYK3wsUPgCfAAAKAAYK3wsUPgCfAAAAAA==.Pañdemönium:BAAANQAECgUICgABNQAECgoKLAAaABEXAA==.',
Pe='Pedwyn:BAAANQAECgcIBwAAAA==.Pepperrjakk:BAAANQADCgEIAQAAAA==.Perck:BAAANQADCgYIBgAAAA==.Perrylee:BAAANQAECgQICwAAAA==.',
Ph='Philia:BAABNQAECn8XAAMLAAgKmRWwnADVAQALAAgKFhKwnADVAQAMAAMK9Rp5KwDdAAABNQAFFAQIEAADAMEXAA==.Phurrball:BAAANQADCgYIBwAAAA==.',
Pi='Pixelme:BAABNQAFFH8GAAIEAAIKcASBHwB4AAAEAAIKcASBHwB4AAAAAA==.',
Pl='Pleggster:BAAANQAECgYIDAAAAA==.',
Po='Pochula:BAAANQAECgUICwAAAA==.',
Pr='Primo:BAABNQAECn9bAAIJAAoK0xkVIQCmAgAJAAoK0xkVIQCmAgAAAA==.Protricity:BAABNQAECn8YAAMfAAoKUBaiJAALAgAfAAgKmBSiJAALAgANAAcKvBSpowAqAQAAAA==.',
Ps='Psalms:BAAANQAECgYIAwABNQAECgYIBwAPAAAAAA==.Psychoprowla:BAABNQAECn9AAAIfAAoKkBIHFAAHAgAfAAoKkBIHFAAHAgAAAA==.Psychozdrood:BAAANQAECgEIAQAAAA==.Psychozpally:BAAANQAECgQIBAAAAA==.',
['Pä']='Pändemönium:BAABNQAECn8bAAUGAAoKeR8UEgABAgAGAAcKeB0UEgABAgAHAAUK0AkkcQAFAQAlAAUKSg+KJgDZAAAmAAMKPwceWQB+AAABNQAECgoKLAAaABEXAA==.',
['Pæ']='Pæn:BAEBNQAECn8iAAMRAAoKxh0bNgBPAgARAAoKvhwbNgBPAgAnAAcK2RJfPwCHAQABNQAFFAMICwAIABUiAA==.',
Qu='Quantar:BAAANQADCgYIBgABNQAECggIDgAPAAAAAA==.Quickstab:BAAANQAECgQICQAAAA==.',
Ra='Ragana:BAABNQAECn8YAAIBAAgKgghPkADxAAABAAgKgghPkADxAAAAAA==.Rainger:BAAANQADCgMIAwAAAA==.Rallypaly:BAAANQADCgMIAwAAAA==.Ramthor:BAAANQAECgYICQAAAA==.Rancooll:BAAANQADCggIIgAAAA==.Rasniir:BAABNQAECn8yAAImAAkKARanIAAkAgAmAAkKARanIAAkAgAAAA==.Rasputea:BAAANQABCgIIAgAAAA==.Ravenar:BAAANQAECgQIBAAAAA==.Ravenlash:BAAANQABCgcICwAAAA==.',
Re='Regna:BAACNQAFFH8RAAMLAAUK9yCDFQB8AQALAAQK9yCDFQB8AQAFAAMKviJtAgDBAAA1AAQKfzEAAwsACgpnJSsbAEsDAAsACQqYJSsbAEsDAAUABQrfI1wQAKEBAAAA.Relkon:BAAANQADCgMIAwAAAA==.Remaked:BAACNQAFFH8pAAIjAAcKDBmkAQAAAgAjAAcKDBmkAQAAAgA1AAQKf0cAAiMACgqlISIEADsDACMACgqlISIEADsDAAAA.Requinix:BAABNQAECn9LAAIDAAoKfBY4QQBAAgADAAoKfBY4QQBAAgAAAA==.Retro:BAAANQADCggIDgAAAA==.Reynmaker:BAAANQADCgQIBAAAAA==.',
Rh='Rhowyn:BAAANQADCgQICAAAAA==.',
Ri='Riptidez:BAAANQADCgYIBgAAAA==.Ririko:BAABNQAECn88AAINAAoK0gyHWgC9AQANAAoK0gyHWgC9AQAAAA==.Ritzo:BAABNQAECn84AAIFAAoKMxhMCAAPAgAFAAoKMxhMCAAPAgAAAA==.',
Ro='Robval:BAAANQABCgIIAgAAAA==.Rocksanne:BAAANQAECgQIBAAAAA==.Rooguee:BAAANQAECgIIAwAAAA==.',
Ru='Rukkis:BAABNQAECn8xAAMZAAoKzBpRDwCGAgAZAAkKhhpRDwCGAgAeAAgKDxcMKgBEAgAAAA==.Rumi:BAABNQAECn9ZAAIkAAoKqh7MAwAdAwAkAAoKqh7MAwAdAwAAAA==.',
Ry='Ryeekan:BAAANQAECggIDQAAAA==.Ryuma:BAAANQAECgYIDwAAAA==.Ryumar:BAAANQAECgMIAwAAAA==.',
Sa='Sabrosura:BAABNQAECn8jAAIKAAkKYRHlJwCfAQAKAAkKYRHlJwCfAQAAAA==.Saiyan:BAAANQADCgIIAgAAAA==.Salsinor:BAAANQADCgYICwAAAA==.Sanosagara:BAAANQAECggIBgAAAA==.Sathari:BAABNQAECn88AAIOAAoKOhAPHQCpAQAOAAoKOhAPHQCpAQAAAA==.',
Sc='Schaden:BAAANQAECgYIBwAAAA==.Scripter:BAAANQADCgUIBgAAAA==.',
Se='Seijo:BAAANQAECgEJAQAAAA==.Sekk:BAABNQAECn9MAAMIAAoK2RmiSQA9AgAIAAoK2RmiSQA9AgAKAAYKURVyKQARAQAAAA==.Selecta:BAAANQAECgEIAQAAAA==.Selexi:BAAANQAECgcIDgAAAA==.Selithira:BAABNQAECn8bAAINAAkKOxGIgQCTAQANAAkKOxGIgQCTAQAAAA==.Sephylon:BAAANQADCgEIAQAAAA==.Sera:BAAANQADCgYICgAAAA==.Seton:BAAANQADCgUIBQABNQAECgoKOQAOAHEbAA==.',
Sh='Shabagnarang:BAAANQAECgYIEQABNQAECggIJgAUAFMbAA==.Shadeofdark:BAABNQAECn8tAAIoAAoKRx3PDwChAgAoAAoKRx3PDwChAgAAAA==.Shalasyr:BAAANQAECgEIAgAAAA==.Shaletaz:BAAANQABCgQIBgAAAA==.Shamwowee:BAAANQADCggILQAAAA==.Shamzee:BAACNQAFFH8LAAIBAAMKZhaTGADMAAABAAMKZhaTGADMAAA1AAQKf0cAAgEACgqPH8YOADkDAAEACgqPH8YOADkDAAAA.Shandalf:BAAANQAECgMIAwABNQAECgMIBQAPAAAAAA==.Sheyy:BAAANQAECgEIAQAAAA==.Shiftybonez:BAAANQADCgQIBQAAAA==.Shintok:BAAANQAECgUIDgAAAA==.Shuddarun:BAACNQAFFH8VAAIDAAgKQhqrAQB0AgADAAgKQhqrAQB0AgA1AAQKfz0AAgMACgosJV8NAHQDAAMACgosJV8NAHQDAAAA.',
Si='Silverbakk:BAAANQABCgEIAQAAAA==.Simn:BAAANQAECgYICwAAAA==.Sindraesong:BAAANQAECgUJCQAAAA==.',
Sk='Skithiryx:BAAANQAECgQICAABNQAECgoKOQAOAHEbAA==.Skuldd:BAAANQAECgUIDQAAAA==.',
Sl='Slayvylora:BAAANQAECgQIBAABNQAFFAUIFwAQAKkTAA==.',
Sm='Smarte:BAABNQAFFH8KAAISAAUKtRPFAAD2AAASAAUKtRPFAAD2AAAAAA==.Smolderpally:BAAANQADCgYIBgAAAA==.',
Sn='Sneakymoth:BAAANQADCgUIBQABNQAECggIFQAXAP4UAA==.Snookums:BAABNQAECn8fAAIOAAoKLhZ6FgDzAQAOAAoKLhZ6FgDzAQAAAA==.',
So='Soarin:BAAANQADCgQIBAAAAA==.',
Sp='Spicymaker:BAABNQAECn8nAAILAAoKkxwHVQCLAgALAAoKkxwHVQCLAgAAAA==.',
St='Starya:BAAANQAECgUICQAAAA==.Steelheart:BAAANQABCgQIBAAAAA==.Stolensøul:BAAANQABCggIDAAAAA==.Stop:BAAANQAECgMIAwAAAA==.Strifewood:BAAANQAECgcIBwAAAA==.Stumper:BAABNQAECn80AAIHAAoKShdgJwCtAQAHAAoKShdgJwCtAQAAAA==.',
Su='Suluna:BAAANQABCgQIBAABNQAECgoKXwABAMQgAA==.Sux:BAAANQADCgMIAwAAAA==.',
Sy='Sybrina:BAABNQAECn9FAAIDAAoKGhanQQA+AgADAAoKGhanQQA+AgAAAA==.Sylvia:BAABNQAECn8nAAIYAAoKtxJNwwD+AQAYAAoKtxJNwwD+AQAAAA==.Syngeance:BAABNQAECn8jAAIDAAgK/QYRlgBsAQADAAgK/QYRlgBsAQAAAA==.Synèsterwolf:BAAANQAECggIDQAAAA==.',
['Sí']='Síf:BAAANQAECgEIAQAAAA==.',
Ta='Tadeusz:BAAANQAECgcICgAAAA==.Taelah:BAAANQAECggIAgAAAA==.Tamamò:BAAANQADCgYICAAAAA==.Tanglefoot:BAABNQAECn8gAAILAAgKFhKHgAAaAgALAAgKFhKHgAAaAgAAAA==.Tanleros:BAABNQAECn8iAAIJAAkKahVyVwATAgAJAAkKahVyVwATAgAAAA==.Taquítos:BAAANQADCgYICAAAAA==.Tasigur:BAAANQAECgYIDgABNQAECgoKOQAOAHEbAA==.',
Te='Telana:BAAANQADCggILQAAAA==.Tentación:BAAANQADCggICAABNQAECgkJIwAKAGERAA==.Tequitos:BAAANQAECgcIEQAAAA==.',
Th='Theduk:BAABNQAECn85AAMZAAoK8BXHRwDHAQAeAAkK4QrXQADIAQAZAAoKpRXHRwDHAQAAAA==.Theduke:BAAANQAECgQIBAAAAA==.Theliria:BAAANQADCgYIBgAAAA==.Thorias:BAABNQAECn8ZAAIYAAgKKxtkjgBiAgAYAAgKKxtkjgBiAgAAAA==.',
To='Toira:BAAANQADCgUIBQAAAA==.Tomoko:BAAANQADCgYICQAAAA==.Torment:BAABNQAECn9FAAIQAAoKyhq8FABaAgAQAAoKyhq8FABaAgAAAA==.',
Tr='Tristén:BAABNQAECn8sAAIDAAoK3BaKOQBWAgADAAoK3BaKOQBWAgAAAA==.Truvie:BAAANQADCgMIAwAAAA==.',
Tu='Tumbled:BAABNQAECn8WAAIYAAgKcxCF5QC+AQAYAAgKcxCF5QC+AQAAAA==.Tumbles:BAAANQADCgQIBQAAAA==.Tumni:BAABNQAECn8aAAICAAgKCAvDXgBSAQACAAgKCAvDXgBSAQAAAA==.',
Tw='Twinkletoes:BAAANQAECgMIAwAAAA==.',
['Tá']='Tángall:BAAANQABCgEIAQAAAA==.',
Ui='Ui:BAAANQADCgMIAwAAAA==.',
Ul='Ulnuk:BAABNQAECn9GAAIBAAoKfh+cCgBmAwABAAoKfh+cCgBmAwAAAA==.Ulster:BAAANQADCgEIAQAAAA==.',
Un='Ungodly:BAABNQAECn8uAAInAAoKjxHJNwD3AQAnAAoKjxHJNwD3AQAAAA==.Unholyshan:BAAANQAECgIIAgABNQAECgMIBQAPAAAAAA==.Unidus:BAAANQAECgEIAgAAAA==.',
Uu='Uutr:BAAANQABCgEIAQAAAA==.',
Uv='Uvvolx:BAAANQADCgQICAAAAA==.',
Va='Vadka:BAAANQAECgUIEgAAAA==.Vaeldrin:BAAANQAECgQIBQAAAA==.Vaha:BAAANQAECgQICgAAAA==.Valkree:BAAANQAECgUIDgAAAA==.Valroc:BAAANQADCgYIDAAAAA==.Valsavis:BAABNQAECn89AAIkAAoKQyBABgC6AgAkAAoKQyBABgC6AgAAAA==.Valtier:BAAANQADCgMIAwAAAA==.',
Ve='Veaolop:BAAANQABCggIEAAAAA==.Vellagosa:BAAANQAECgUIDAAAAA==.Vernice:BAAANQADCgYICwABNQAECggICgAPAAAAAA==.Verulan:BAAANQAECgYIDgAAAA==.Vexidari:BAAANQAECgYIDwABNQAFFAUIFwAQAKkTAA==.Vexomous:BAABNQAECn8eAAMSAAgKgBqrBQBbAgASAAgKgBqrBQBbAgAEAAQKDgdTWwC3AAABNQAFFAUIFwAQAKkTAA==.',
Vi='Viiolet:BAAANQAFFAIIAwAAAA==.',
Vo='Voidmayne:BAABNQAECn8uAAIIAAoKHRQQoADhAQAIAAoKHRQQoADhAQAAAA==.Vongogh:BAAANQADCgYICQAAAA==.Vonhelsing:BAAANQAECgQIBAAAAA==.Vorenius:BAAANQAECgIIAgAAAA==.',
Vy='Vynnara:BAAANQADCgEIAQAAAA==.Vyolent:BAAANQADCgYICwAAAA==.',
Wa='Wapello:BAAANQABCgcIEgAAAA==.Warnox:BAAANQAECgIIAgAAAA==.',
We='Weiand:BAABNQAECn83AAMIAAgK9RnBWAAUAgAIAAgK9RnBWAAUAgAJAAcKLQx5jwBvAQAAAA==.Wevark:BAABNQAECn8XAAILAAkKLgpqtQCXAQALAAkKLgpqtQCXAQAAAA==.',
Wh='Whatami:BAABNQAECn87AAQWAAoKRBtdIwB2AgAWAAoKRBtdIwB2AgAcAAIKvxHsHwBqAAAVAAEKAABDMgAAAAAAAA==.Whiteknight:BAAANQADCgcIDQABNQAECgoKOwAWAEQbAA==.Wholemilk:BAABNQAECn8hAAIOAAcKgh1TJQAbAgAOAAcKgh1TJQAbAgAAAA==.',
Wi='Wilhellena:BAABNQAECn81AAINAAoKQRIuYQClAQANAAoKQRIuYQClAQAAAA==.Wilhellfu:BAAANQADCgMIAwAAAA==.Winariel:BAABNQAECn8mAAIcAAoKxhuIAQCaAgAcAAoKxhuIAQCaAgAAAA==.Witewalker:BAAANQADCgcICgAAAA==.',
Wo='Wobum:BAAANQABCgUIBQAAAA==.',
Wr='Writhesoul:BAAANQABCgIIAgABNQAECgoKJgACAHcXAA==.Wroughtsoul:BAABNQAECn8jAAQbAAoK9gl4FgCBAQAbAAoK9gl4FgCBAQAaAAIKvQv9XgBkAAAjAAEKAADWLwA+AAAAAA==.Wrysoul:BAABNQAECn8mAAICAAoKdxeANACmAgACAAoKdxeANACmAgAAAA==.',
Wy='Wynston:BAAANQADCgEIAQAAAA==.Wyrmheart:BAAANQADCgIIAwAAAA==.',
Xa='Xaldred:BAABNQAECn8eAAIWAAoK7Qx5hQDYAQAWAAoK7Qx5hQDYAQABNQAECgoKQQARAJ8cAA==.Xandir:BAABNQAECn8iAAMKAAkKQxM7HwBfAQAKAAkKQxM7HwBfAQAIAAEKNgnvmAEpAAAAAA==.Xarhunt:BAAANQAECgMIBwAAAA==.',
Xe='Xenzia:BAAANQADCgcICwAAAA==.Xeracil:BAAANQADCgQIDQAAAA==.Xerras:BAAANQAECgEIAQAAAA==.',
Xo='Xoric:BAABNQAECn8xAAImAAoKlxjaEACgAgAmAAoKlxjaEACgAgAAAA==.',
Xy='Xyal:BAABNQAECn8nAAINAAkKwxaxbwDOAQANAAkKwxaxbwDOAQAAAA==.Xyp:BAAANQADCgYIBgABNQAECgYIDgAPAAAAAA==.',
Ya='Yamaya:BAAANQADCgYICwAAAA==.',
Yi='Yiago:BAAANQAECgUIDgAAAA==.',
Yo='Youknow:BAAANQADCgcICwAAAA==.',
Za='Zaelia:BAAANQADCgEIAQAAAA==.Zaxhdk:BAEANQADCgMIAwABNQAECggIGwAJAPwSAA==.Zaxhpal:BAEBNQAECn8bAAIJAAgK/BIndgC1AQAJAAgK/BIndgC1AQAAAA==.',
Ze='Zenedy:BAAANQAECgQIBAABNQAECggICgAPAAAAAA==.Zerrus:BAAANQAECgQIBAAAAA==.',
Zi='Zid:BAAANQAECgMIAwAAAA==.Ziny:BAAANQADCgUIBQAAAA==.Ziparoo:BAABNQAECn84AAIXAAoK0wuQDgCKAQAXAAoK0wuQDgCKAQAAAA==.',
Zo='Zoenova:BAAANQAECggIAgAAAA==.',
Zr='Zraven:BAAANQADCgEIAQAAAA==.',
['În']='Îniquitous:BAAANQAECgUIDgAAAA==.',
['Ðê']='Ðêmønicßløøð:BAABNQAECn8mAAMnAAoK5BQXKAAEAgAnAAoK5BQXKAAEAgARAAMKggrGsACQAAABNQAECgoKMAALAG8bAA==.',
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
