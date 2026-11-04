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

local lookup = {'Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Fury','Druid-Guardian','Druid-Balance','Paladin-Retribution','Paladin-Holy','Warrior-Arms','Warrior-Protection','Priest-Holy','DemonHunter-Devourer','Unknown-Unknown','DeathKnight-Blood','DeathKnight-Unholy','Hunter-Survival','Mage-Fire','Shaman-Enhancement','Warlock-Affliction','Warlock-Demonology','Mage-Frost','Mage-Arcane','Monk-Windwalker','Monk-Mistweaver','Paladin-Protection','Warlock-Destruction','Evoker-Preservation','Rogue-Assassination','Priest-Shadow','Priest-Discipline','Evoker-Devastation','Evoker-Augmentation','Monk-Brewmaster','DemonHunter-Vengeance','Druid-Feral','Druid-Restoration','DeathKnight-Frost','Rogue-Subtlety','DemonHunter-Havoc',}
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aabbigale:BAAANQAECggIAQAAAA==.',
Ab='Abigt:BAAANQADCgIIAQAAAA==.',
Ac='Acidsnow:BAAANQAECgQIBQAAAA==.',
Ad='Adalaidê:BAAANQAECgMIDAAAAA==.',
Ae='Aerynne:BAAANQAECgQIBQAAAA==.',
Ai='Airie:BAABNQAECn8pAAMBAAkKJgk6cgApAQABAAkKJgk6cgApAQACAAUKUgZ0sQBzAAAAAA==.',
Ak='Akuso:BAAANQADCgIIAgAAAA==.',
Al='Alcohaulorc:BAAANQAECgQIBwAAAA==.Alert:BAAANQAECgEIAQAAAA==.Allfry:BAAANQADCgEIAQAAAA==.Aloris:BAAANQAECgQICAAAAA==.Aloy:BAACNQAFFH8QAAMDAAQKwRcPEABaAQADAAQKwRcPEABaAQAEAAEKAABwKAAzAAA1AAQKfxUAAgMABQo8H3qKAFkBAAMABQo8H3qKAFkBAAAA.Aluhx:BAAANQAECgMICQABNQAFFAYICwAFAJQRAA==.',
Am='Amednato:BAABNQAECn8bAAMGAAoKeweYLAA0AQAGAAoKeweYLAA0AQAHAAEKcwW3gAAsAAAAAA==.',
An='Anaeli:BAABNQAECn9fAAIBAAoKxCCIGwABAwABAAoKxCCIGwABAwAAAA==.Anastarian:BAAANQAECgQIBgAAAA==.Ancalagonn:BAAANQAECgcIDwAAAA==.Angita:BAAANQAECgUIDAAAAA==.Anklin:BAAANQADCgIIAgAAAA==.Annaris:BAACNQAFFH8ZAAIDAAcKOBwCAwA8AgADAAcKOBwCAwA8AgA1AAQKfy8AAwMACgr3JUMHAKIDAAMACgr3JUMHAKIDAAQACQrJGS0yALwBAAAA.Antipæn:BAECNQAFFH8LAAMIAAMKFSJpEwAfAQAIAAMKFSJpEwAfAQAJAAEKdCO9JQBlAAA1AAQKf0kAAwgACgrBJqIEANQDAAgACgrBJqIEANQDAAkACgoiITkLAG4DAAAA.',
Ap='Apologia:BAABNQAECn85AAIIAAoKRSKPGgDcAgAIAAoKRSKPGgDcAgAAAA==.',
Aq='Aquaphobic:BAAANQAECgYIDgABNQAFFAcIFAABAGYJAA==.',
Ar='Arcanoth:BAAANQADCgIIAgAAAA==.Ardicelia:BAAANQADCgEIAQAAAA==.Ares:BAABNQAECn8oAAIKAAoK5R/7HQBAAwAKAAoK5R/7HQBAAwAAAA==.Armorgorden:BAABNQAECn9BAAILAAoKWSKxAwDbAgALAAoKWSKxAwDbAgAAAA==.Aroviaa:BAABNQAECn89AAIMAAoK5Ro1QABqAgAMAAoK5Ro1QABqAgAAAA==.Arpmek:BAABNQAECn86AAINAAoKtRVwJQAaAgANAAoKtRVwJQAaAgAAAA==.Artemîs:BAAANQADCgIIAgAAAA==.',
As='Asharienne:BAABNQAECn8sAAIDAAoKXhDoUADrAQADAAoKXhDoUADrAQAAAA==.Ashilianar:BAAANQAECgEIAQAAAA==.Ashlynne:BAAANQAECgYJCwAAAA==.',
Au='Aubergine:BAAANQADCgQIBAAAAA==.Audiobully:BAAANQAECgQIBAABNQAECgoKMQAHAEoXAA==.Auntmary:BAAANQAECgEIAQAAAA==.Auralynn:BAAANQAECgQJBAABNQAECgYJCwAOAAAAAA==.Auriella:BAABNQAECn8kAAMJAAoKVhAuaQDcAQAJAAoKVhAuaQDcAQAIAAIKsggtdwEtAAAAAA==.Aurtt:BAABNQAECn86AAMPAAoKshRJRQDlAQAPAAkKPhVJRQDlAQAQAAMKEAnNVgCHAAAAAA==.',
Av='Avvatar:BAAANQADCgEIAQAAAA==.',
['Aö']='Aöb:BAAANQADCgQIBgAAAA==.',
Ba='Bahahaknight:BAABNQAECn82AAIPAAkKfBbiIQC/AQAPAAkKfBbiIQC/AQAAAA==.Bahree:BAAANQADCgIIAgAAAA==.Bakhar:BAABNQAECn8pAAIRAAkKhR3VAwArAgARAAkKhR3VAwArAgAAAA==.Balora:BAAANQADCgcIGAAAAA==.Barnette:BAABNQAECn9MAAISAAoKnhhMAQA7AgASAAoKnhhMAQA7AgAAAA==.Basyleus:BAAANQADCgEIAgAAAA==.',
Be='Beau:BAAANQAECgQICAABNQAECgkJGQAJAMgfAA==.Belthos:BAABNQAECn8ZAAIIAAgKSBgceQA6AgAIAAgKSBgceQA6AgAAAA==.Benihime:BAAANQAECgEIAQAAAA==.Berristan:BAABNQAECn8/AAMJAAoKlw95YgDxAQAJAAoKlw95YgDxAQAIAAEKegR7cgEwAAAAAA==.Bestwingman:BAAANQADCgEIAQAAAA==.',
Bi='Bigdawgsteve:BAAANQADCgIIAgAAAA==.Bigmarv:BAAANQAECgUIDAAAAA==.Bittytigs:BAACNQAFFH8QAAIBAAUKYhPZDwAZAQABAAUKYhPZDwAZAQA1AAQKf1IAAwEACgr+Hp8UACgDAAEACgr+Hp8UACgDAAIAAQoAAGBOAScAAAAA.',
Bl='Blestemat:BAAANQAECgEIAQAAAA==.Blossom:BAAANQAFFAQIBAABNQAFFAQIEAAOAAAAAQ==.Blumangood:BAABNQAECn8wAAQCAAgK1Rc0WAAbAgACAAgK1Rc0WAAbAgABAAIKLQKKFQE/AAATAAEKAADnNwAwAAAAAA==.',
Bo='Bollux:BAAANQAECgEIAgAAAA==.Bosc:BAABNQAECn8pAAIPAAoKBxayHwDRAQAPAAoKBxayHwDRAQAAAA==.Boudiicca:BAAANQAECgQIBQAAAA==.Boxmasterr:BAABNQAECn89AAMUAAoK4BW+BQBeAgAUAAgKqBi+BQBeAgAVAAcKOhHbaQBfAQAAAA==.',
Br='Braagh:BAAANQADCgEIAgAAAA==.Brasmir:BAABNQAECn84AAIRAAoKdx2oAgAIAwARAAoKdx2oAgAIAwAAAA==.Briae:BAAANQADCgMIAwABNQAECgoKXwABAMQgAA==.Brianzero:BAAANQADCgEIAQAAAA==.Brino:BAAANQAECgQIBQAAAA==.Brinotriage:BAAANQAECgYIBQAAAA==.',
Bu='Bubblemoth:BAAANQADCgMIBAABNQAECgcIFAAWANgVAA==.Buik:BAAANQAECgIIAwAAAA==.Bulge:BAABNQAECn8kAAMXAAoKUw0w0QDkAQAXAAoK8Qww0QDkAQAWAAEK2Rb9PwBEAAABNQAFFAQIDgAQAGILAA==.Bulgogi:BAACNQAFFH8OAAIQAAQKYgvSBwDBAAAQAAQKYgvSBwDBAAA1AAQKf0AAAhAACgoiIHkJAL8CABAACgoiIHkJAL8CAAAA.Butherrface:BAAANQADCgUIBQAAAA==.',
['Bö']='Börk:BAAANQAECgUIDAAAAA==.',
Ca='Capy:BAAANQAECgIIAgABNQAFFAQIBgAWAOQUAA==.Cardran:BAAANQADCgIIAwABNQAECgkJFwADANsRAA==.Cayda:BAAANQADCgYICwAAAA==.Caylara:BAAANQAECgMIDwAAAA==.Cayssabber:BAAANQAECgcIBwAAAA==.Cayssaber:BAAANQAECgIIAgAAAA==.',
Ce='Ceicilia:BAAANQADCgQIBAAAAA==.Celrythis:BAAANQAECgMICAAAAA==.Cenokry:BAAANQADCgYICgAAAA==.',
Ch='Chai:BAABNQAECn8aAAMYAAkKxwuENgBhAQAYAAkKxwuENgBhAQAZAAIKNAP8PAAgAAAAAA==.Chaintrain:BAAANQAECgMIAwABNQAECgkJHgAVAJsVAA==.Chellyy:BAAANQAECgcICQABNQAECgcIGwANAAMdAA==.Chibisend:BAAANQAECgEIAQAAAA==.Chámeleon:BAAANQADCgEIAgAAAA==.',
Ci='Cider:BAAANQAECgIIAgAAAA==.',
Cl='Claes:BAAANQADCgMIAwABNQAECgoKKQAPAAcWAA==.',
Co='Coralbubbles:BAABNQAECn8zAAIIAAoKqhJJawC7AQAIAAoKqhJJawC7AQAAAA==.Coralorchid:BAABNQAECn8pAAIaAAYKtx4bGwAWAgAaAAYKtx4bGwAWAgAAAA==.Coralprays:BAAANQADCggICgAAAA==.Coralrages:BAAANQAECgQIBgAAAA==.',
Cr='Cromenockle:BAABNQAECn8UAAQUAAkKmBO+EwAPAQAVAAgKahIYhADcAQAUAAQKdw++EwAPAQAbAAIKuw4vWAB3AAABNQAFFAQIBQARANwIAA==.Crtitman:BAAANQAECgUIDgAAAA==.Crystalline:BAAANQADCgEIAQAAAA==.',
Cu='Cupcâke:BAAANQAECgQIBgAAAA==.Curissan:BAABNQAECn8fAAICAAcKERTRbQDWAQACAAcKERTRbQDWAQAAAA==.',
Cy='Cyber:BAAANQAECggIAQAAAA==.',
Da='Dalgon:BAABNQAFFH8IAAIcAAQK6wRDEADvAAAcAAQK6wRDEADvAAABNQAFFAcIEAAJAKIUAA==.Dalir:BAAANQAECgYIDgAAAA==.Dalspin:BAAANQADCgYIDAAAAA==.Dalthepal:BAACNQAFFH8QAAIJAAcKohTvBwDnAQAJAAcKohTvBwDnAQA1AAQKf0cAAgkACgrzHzoXAB8DAAkACgrzHzoXAB8DAAAA.Damné:BAABNQAECn9BAAIQAAoKnxzOCwCXAgAQAAoKnxzOCwCXAgAAAA==.Darze:BAAANQADCggIAwABNQAECgcICwAOAAAAAA==.Davidline:BAABNQAECn8qAAIIAAoKuhzjOwDjAgAIAAoKuhzjOwDjAgAAAA==.',
De='Deadish:BAABNQAECn9DAAMPAAoKbyGkBwD+AgAPAAoKbyGkBwD+AgAQAAEKDQZrjQASAAAAAA==.Deathsaberss:BAABNQAECn9QAAMKAAoKNRtrJgCGAgAKAAoKNRtrJgCGAgALAAQK5Au+KgDjAAAAAA==.Deathvex:BAACNQAFFH8XAAIPAAUKqRM3FAAYAQAPAAUKqRM3FAAYAQA1AAQKfx0AAg8ACAqPGYwyAFYBAA8ACAqPGYwyAFYBAAAA.Decoz:BAAANQAECgUICgAAAA==.Degarius:BAAANQADCgEIAgAAAA==.Deight:BAAANQAECgEIAQAAAA==.Dejamoo:BAAANQADCgYIGQAAAA==.Dendahn:BAAANQAECgcIDQAAAA==.Destinee:BAAANQAECgQICwAAAA==.',
Di='Dianntha:BAAANQADCgcIHgAAAA==.Diladrin:BAABNQAECn9YAAIGAAoKKhvKCwBKAgAGAAoKKhvKCwBKAgAAAA==.Dinomight:BAAANQADCgQIBAAAAA==.',
Do='Doileag:BAABNQAECn8XAAIIAAUKkAZUNQHKAAAIAAUKkAZUNQHKAAAAAA==.Doomgrave:BAAANQADCgEIAQAAAA==.Dora:BAAANQADCgYIBgABNQAECgYIGQAdAGQGAA==.Dottmatrix:BAAANQAECgMIEAAAAA==.Doubledowns:BAAANQAECgEIAQAAAA==.',
Dr='Dreadwing:BAAANQAECgQIBQAAAA==.Dreamfyre:BAAANQADCgEIAgAAAA==.Druromu:BAAANQAECgMIDwAAAA==.',
Du='Dufs:BAACNQAFFH8VAAIBAAUKDyY7CQC9AQABAAUKDyY7CQC9AQA1AAQKfy0AAgEACgrNH2wcAPwCAAEACgrNH2wcAPwCAAAA.Dunkan:BAAANQAECgMIAwAAAA==.Dustbunny:BAABNQAECn9AAAQMAAkKFRe2VQAiAgAMAAkKFRe2VQAiAgAeAAEKVgdnVgA0AAAfAAEK/gY2GAAoAAAAAA==.',
Dw='Dwagon:BAABNQAECn8UAAMgAAgKYQlaIgA4AQAgAAYKQQtaIgA4AQAhAAMK1gd5IABWAAAAAA==.',
Dy='Dylsonlolqt:BAABNQAECn8YAAIPAAkKeQZYNwA9AQAPAAkKeQZYNwA9AQAAAA==.',
['Dã']='Dãrling:BAAANQADCgEIBAAAAA==.',
['Dû']='Dûn:BAABNQAECn87AAMYAAoKmiDLDQAAAwAYAAoKUiDLDQAAAwAiAAgKNh4pCgB1AgAAAA==.Dûna:BAABNQAECn8xAAIeAAoKkx3eCACyAgAeAAoKkx3eCACyAgABNQAECgoKOwAYAJogAA==.',
El='Elaatia:BAABNQAECn89AAIIAAoKySNjKgAdAwAIAAoKySNjKgAdAwAAAA==.Elidria:BAAANQADCgEIAQABNQAECgEIAQAOAAAAAA==.Ellysprocket:BAAANQAECgEIAQAAAA==.Elrric:BAAANQAECgcICgAAAA==.Elyak:BAAANQADCgIIAgAAAA==.',
En='Envoy:BAAANQAECgQIBwAAAA==.',
Er='Erakron:BAABNQAECn86AAMCAAoKsBM/LQDwAQACAAoKsBM/LQDwAQABAAYKmBPUpwAiAQAAAA==.Erine:BAAANQAECgUIBgAAAA==.Erouvi:BAAANQADCgIIAgABNQAECgoKPQAMAOUaAA==.Eroviaa:BAAANQAECgUIBwABNQAECgoKPQAMAOUaAA==.Erovvia:BAAANQADCgUIBQABNQAECgoKPQAMAOUaAA==.',
Es='Esmeralda:BAAANQADCgEIAQAAAA==.',
Et='Etali:BAAANQADCgYIBQABNQAECgoKNgANAHEbAA==.',
Ev='Evorik:BAAANQAECgYICwABNQAFFAIIBQAKAH4TAA==.',
Ez='Ezothen:BAABNQAECn8XAAMgAAcKnAYFJgAIAQAgAAYK+gYFJgAIAQAhAAEKJAXLGgAsAAAAAA==.',
Fa='Facelessman:BAAANQADCgEIAQAAAA==.Faedoria:BAAANQAECgUICwAAAA==.Faeryln:BAABNQAECn9CAAIMAAoKuQiaYgB8AQAMAAoKuQiaYgB8AQAAAA==.Faustus:BAABNQAECn8ZAAIJAAkKyB8jJgDRAgAJAAkKyB8jJgDRAgAAAA==.Favion:BAAANQADCgEIAQAAAA==.',
Fe='Feature:BAAANQADCgEIAQAAAA==.Felyyia:BAABNQAECn8mAAINAAoK3yKTAwAlAwANAAoK3yKTAwAlAwABNQAFFAcIGQADADgcAA==.',
Fi='Fiddlestix:BAAANQAECgQIBAAAAA==.Firebrande:BAAANQAECgUIDAAAAA==.Fisticuffs:BAAANQADCggIKwAAAA==.Fizcrankshot:BAABNQAECn9BAAIDAAoKPhmJKgBqAgADAAoKPhmJKgBqAgAAAA==.',
Fl='Flamewhisker:BAAANQAECgYIDQAAAQ==.Flamez:BAAANQADCgcIBwAAAA==.Flandre:BAAANQAECgUIBQAAAA==.',
Fr='Fraublucher:BAABNQAECn80AAIMAAkKDgraZQBxAQAMAAkKDgraZQBxAQAAAA==.Frewyn:BAAANQAECgYIDgAAAA==.Frostimoth:BAABNQAECn8UAAIWAAcK2BW9EQCKAQAWAAcK2BW9EQCKAQAAAA==.Frozty:BAAANQAECgQIBgAAAA==.',
Ga='Galandel:BAAANQADCggIKAAAAA==.Galial:BAACNQAFFH8MAAIjAAQK9hBSAgCrAAAjAAQK9hBSAgCrAAA1AAQKfzMAAiMACgpfGgwHAKACACMACgpfGgwHAKACAAAA.Gantar:BAAANQAECgUIBQABNQAFFAQICAAPALwZAA==.Garradin:BAAANQADCgEIAQAAAA==.Garrunter:BAAANQAECgQIBwAAAA==.Gaznol:BAAANQADCgQIBAABNQAECgoKGwAGAHsHAA==.',
Ge='Gelasera:BAAANQAECgUICwAAAA==.Gemitra:BAAANQADCgcIBwABNQAECgYIKQAaALceAA==.Geneth:BAAANQAECgUIBQAAAA==.George:BAACNQAFFH8FAAIKAAIKfhPSLgCPAAAKAAIKfhPSLgCPAAA1AAQKfzAAAgoACQpiH6g4ADMCAAoACQpiH6g4ADMCAAAA.',
Gh='Ghalta:BAAANQADCgIIAgABNQAECgoKNgANAHEbAA==.Ghrol:BAAANQADCgEIAQABNQAECgoKRQABAH4fAA==.',
Gl='Glaivethras:BAABNQAECn8/AAIjAAoK3iMFAQBAAwAjAAoK3iMFAQBAAwAAAA==.Glenfin:BAAANQADCgQIBgAAAA==.',
Gr='Greg:BAAANQAECgEIAQAAAA==.Gremlynn:BAAANQADCggICQAAAA==.Grimclaw:BAACNQAFFH8LAAMkAAYKSAndAgC3AAAHAAUKSAndFgD7AAAkAAIKAADdAgC3AAA1AAQKfy4AAwcACgorJcseANQCAAcACAqVIsseANQCACQABgrnJU4NAKgBAAAA.Groot:BAABNQAECn8WAAMlAAUKIhjwQgATAQAlAAUKIhjwQgATAQAHAAMK8wyrjQCgAAABNQAECgkJIwAaAGERAA==.',
Gu='Guthrek:BAAANQAECgYIDAAAAA==.',
Ha='Hamfist:BAAANQADCgIIAgABNQAECggIEgAOAAAAAA==.Hanhealz:BAEANQADCgEIAQABNQAECgQIBAAOAAAAAA==.Hannebal:BAABNQAECn8rAAIJAAoKJxVeJwBhAgAJAAoKJxVeJwBhAgAAAA==.',
He='Healsonyou:BAAANQAFFAEIAQAAAA==.Healyclam:BAAANQADCgMIAwAAAA==.Heydaw:BAAANQADCggICAABNQAECgkJGAAmAJUbAA==.Heynow:BAAANQAECgUIEQAAAA==.',
Hi='Higherp:BAAANQADCggICAABNQAECgcIKAAkAJMRAA==.Highmountain:BAAANQADCggIDwAAAA==.Hilimed:BAABNQAECn9EAAIVAAoKFgxtUgCkAQAVAAoKFgxtUgCkAQAAAA==.',
Ho='Hobs:BAAANQADCgUIBgAAAA==.Holyßloodelf:BAAANQAECgcIEQABNQAFFAEIAQAOAAAAAA==.Hoosier:BAABNQAECn8VAAIMAAgKtxKoOgAZAgAMAAgKtxKoOgAZAgAAAA==.Hoplite:BAABNQAECn8eAAIlAAoKshVdEwBKAgAlAAoKshVdEwBKAgAAAA==.',
Hu='Huasca:BAAANQAECgEIAQAAAA==.Huthuel:BAAANQADCgEIAQAAAA==.',
Hy='Hydra:BAAANQADCgYIBgABNQAECgoKJgAXALcSAA==.Hyve:BAAANQAECgMIBAABNQAECgkJQwAIAMcaAA==.',
['Hà']='Hàney:BAEANQAECgQIBAAAAA==.',
['Hé']='Hélio:BAAANQADCgUIBgAAAA==.',
Ia='Ia:BAABNQAECn81AAImAAoKUSHUCwA4AwAmAAoKUSHUCwA4AwAAAA==.',
Ib='Ibesmashin:BAAANQADCgQIBAABNQAECggIEgAOAAAAAA==.Ibesneakin:BAAANQAECgQIBAABNQAECggIEgAOAAAAAA==.',
Id='Idontsuck:BAAANQADCggICwAAAA==.',
Il='Ileynha:BAABNQAECn8UAAIUAAkKIQmECQBtAQAUAAkKIQmECQBtAQAAAA==.Ilieau:BAAANQAECgQIBQABNQAECggIEgAOAAAAAA==.Illida:BAAANQADCgYIBgAAAA==.',
Im='Imamalelol:BAAANQAFFAEIAQAAAA==.',
In='Inarrah:BAAANQADCgEIAQAAAA==.Intol:BAAANQAFFAQIEAAAAQ==.Intrepidhero:BAAANQADCgEIAQAAAA==.',
Ir='Irkenfox:BAECNQAFFH8ZAAILAAUKfBaNAgDSAAALAAUKfBaNAgDSAAA1AAQKfzEAAgsACgoJJKQCAIYDAAsACgoJJKQCAIYDAAAA.',
It='Ithran:BAAANQADCgUIBgAAAA==.',
Iw='Iwilltank:BAAANQADCgYICwAAAA==.',
Ix='Ixitt:BAABNQAECn8wAAISAAoKrxg9AgA6AgASAAoKrxg9AgA6AgAAAA==.',
Ja='Jama:BAAANQADCgYIBgAAAA==.Janderick:BAAANQAECgYIDgAAAA==.Jaromer:BAAANQADCgcIEAAAAA==.',
Je='Jellacee:BAAANQADCgcIFwAAAA==.Jenita:BAAANQADCgEIAQAAAA==.',
Ji='Jimboberjim:BAACNQAFFH8YAAIbAAUKMiK4AAB9AQAbAAUKMiK4AAB9AQA1AAQKfzUAAhsACgrsI2wBAHsDABsACgrsI2wBAHsDAAAA.Jimbobwhey:BAABNQAECn8gAAIiAAkKVxUOBwDJAQAiAAkKVxUOBwDJAQAAAA==.Jiminie:BAABNQAECn8eAAILAAgKPxMdFgDHAQALAAgKPxMdFgDHAQABNQAECgkJIAAiAFcVAA==.',
Jo='Jolio:BAABNQAECn8eAAQVAAkKmxWYqgB9AQAVAAgKXROYqgB9AQAbAAEKuBq9aABQAAAUAAIKrBeWIABIAAAAAA==.Joltraxi:BAAANQADCggICQABNQAECgkJHgAVAJsVAA==.Joshie:BAACNQAFFH8IAAIPAAQKvBn0DQDiAAAPAAQKvBn0DQDiAAA1AAQKfzAAAg8ACgr/I+gJAGYDAA8ACgr/I+gJAGYDAAAA.Joshy:BAAANQADCgcIBwABNQAFFAQICAAPALwZAA==.',
Ju='Jujubeans:BAAANQAECgEIAQAAAA==.Juniornite:BAABNQAECn9DAAIXAAoKRyJRFADkAgAXAAoKRyJRFADkAgAAAA==.Justthetouch:BAAANQAECggIDgAAAA==.',
Jy='Jygglypuff:BAAANQAECgMIBAAAAA==.',
Ka='Kadaan:BAAANQAECgYIBgAAAA==.Kagemaro:BAABNQAECn82AAMNAAoKcRtBFQC7AgANAAoKcRtBFQC7AgAjAAUKdRS7GQAZAQAAAA==.Kahgar:BAAANQAECggILQABNQAFFAMIBgAJAGUKAQ==.Kalimathath:BAAANQAECgQIBgAAAA==.Kalzod:BAABNQAECn9WAAIVAAoK4SXyAQDcAwAVAAoK4SXyAQDcAwAAAA==.Kataki:BAABNQAECn8qAAIDAAkKKBq6PgAiAgADAAkKKBq6PgAiAgABNQAECgoKNgANAHEbAA==.Katia:BAAANQAECgQIDAAAAA==.Kativeria:BAAANQAECgUICgAAAA==.Katjayna:BAAANQADCgUICgAAAA==.Kaysabr:BAAANQAECgUIBgAAAA==.Kayssaber:BAABNQAECn8bAAMlAAgKgxTaIACjAQAlAAgKgxTaIACjAQAHAAMK5BDvjwCXAAAAAA==.',
Ke='Kebab:BAAANQAECgQJBAAAAA==.Kelsifer:BAAANQAECgQICwABNQAECgkJGQAJAMgfAA==.Kempra:BAAANQADCgcIBwAAAA==.Kemprei:BAAANQADCgUIBQAAAA==.Kendralust:BAAANQAECgcICAAAAA==.Kerfufle:BAAANQADCgEIAQAAAA==.',
Kh='Khaos:BAAANQADCgEIAQAAAA==.',
Ki='Kippars:BAAANQAECgEIAQAAAA==.Kiritsugo:BAAANQADCggICAAAAA==.',
Kl='Klaax:BAAANQAECgEIAQABNQAECgkJQwAIAMcaAA==.',
Kn='Knitel:BAAANQAECgEIAgAAAA==.',
Ko='Kodazoff:BAABNQAECn8ZAAMgAAgKwwm9DQA6AQAgAAgKwwm9DQA6AQAcAAEKTwOjUwAkAAAAAA==.Kora:BAAANQADCgEIAQAAAA==.Korevash:BAABNQAECn87AAMBAAoKZCP9AwCrAwABAAoKZCP9AwCrAwATAAYKAhJaHACeAQAAAA==.',
Kr='Krezz:BAAANQAECgEIAQAAAA==.Krissylu:BAAANQAECgYIDgAAAA==.Krothix:BAABNQAECn8/AAICAAkKOQdIXAA2AQACAAkKOQdIXAA2AQAAAA==.Krudd:BAAANQAECgcIDQAAAA==.Krychilly:BAAANQADCgcIFAAAAA==.Kryrande:BAAANQADCgQIDwAAAA==.Kryshym:BAABNQAECn8cAAIJAAYKtiDiTAA2AgAJAAYKtiDiTAA2AgAAAA==.Krythrall:BAAANQAECgEIAQABNQAECgYIHAAJALYgAA==.Kryvelen:BAABNQAECn8aAAMMAAkKfRv5IACmAgAMAAkKfRv5IACmAgAfAAQKTxCCCQDdAAAAAA==.Krëëp:BAAANQAECggICAAAAA==.',
Ks='Kspectactle:BAAANQAECgMIBgAAAA==.',
Ku='Kuilei:BAAANQADCgYJCwABNQAECgIIBgAOAAAAAA==.Kurorø:BAAANQAECgYIEwAAAA==.',
Ky='Kyrayna:BAAANQADCgYIEgAAAA==.',
['Kä']='Käisèr:BAAANQABCgEIAQAAAA==.',
La='Ladara:BAABNQAECn8oAAIUAAkKixQxBgBPAgAUAAkKixQxBgBPAgAAAA==.Laima:BAAANQADCgUICQAAAA==.Landil:BAAANQADCgYIDAAAAA==.Lavitz:BAAANQAECgEIAQAAAA==.',
Le='Leheo:BAAANQAECgQIBgAAAA==.Lehua:BAAANQADCggICgAAAA==.Leilanii:BAAANQADCgcIEQAAAA==.Lemook:BAABNQAECn8bAAIlAAkKjxICJACHAQAlAAkKjxICJACHAQAAAA==.Leonìdas:BAAANQADCggIGQAAAA==.Leð:BAAANQAECggICAAAAA==.',
Li='Licker:BAAANQAECgUICQABNQAFFAQIBQARANwIAA==.Life:BAAANQAECgEIAQAAAA==.Lightbulb:BAAANQADCgYIDQAAAA==.Lightlocke:BAAANQADCgEIBAAAAA==.Lightsorrow:BAAANQAECggIDgAAAA==.Lightstormer:BAAANQADCgcIJQAAAA==.Lilamae:BAAANQAECgUIDQAAAA==.Lilarielle:BAABNQAECn89AAIkAAgKXwYdIAC6AAAkAAgKXwYdIAC6AAAAAA==.Lildookie:BAABNQAECn8XAAICAAoKRwc6UABeAQACAAoKRwc6UABeAQAAAA==.Lilface:BAAANQAECggIDgAAAA==.Lilhands:BAAANQAECgQIBQAAAA==.Liliel:BAAANQADCgMIAwABNQAECgkJFwADANsRAA==.Liliela:BAABNQAECn8XAAIDAAkK2xGuaABCAgADAAkK2xGuaABCAgAAAA==.Lilyannah:BAAANQADCgEIAQAAAA==.Liodragon:BAAANQADCgUIBQABNQAECgcICgAOAAAAAA==.Liolock:BAAANQAECggIBwAAAA==.Lite:BAAANQAECgQIBAAAAA==.Liø:BAAANQAECgcICgAAAA==.',
Ll='Lluniez:BAABNQAECn8hAAIYAAkKBRCjGQCnAQAYAAkKBRCjGQCnAQAAAA==.',
Lm='Lmccoy:BAAANQABCgQIBAAAAA==.',
Lo='Lockroknroll:BAAANQAECggIEgAAAA==.Loissa:BAAANQAECggIEAAAAA==.Losoli:BAABNQAECn9BAAIJAAkKRh3EKwC4AgAJAAkKRh3EKwC4AgAAAA==.Lotor:BAAANQAECgEIAQAAAA==.Lowchin:BAAANQAECgQIBQAAAA==.',
Lu='Lupine:BAAANQADCgYIBgABNQAECgYICwAOAAAAAA==.Lutherion:BAABNQAECn8xAAILAAoKBB5fBQCOAgALAAoKBB5fBQCOAgAAAA==.',
Ly='Lycemmas:BAABNQAECn8mAAIBAAoK1Ri8RQBKAgABAAoK1Ri8RQBKAgAAAA==.',
['Lï']='Lïo:BAAANQADCgYIBwABNQAECgcICgAOAAAAAA==.',
Ma='Macoun:BAABNQAECn8pAAIDAAoKoiLNFwDFAgADAAoKoiLNFwDFAgAAAA==.Magicshowers:BAABNQAECn89AAIXAAoKzyKsNwAZAwAXAAoKzyKsNwAZAwAAAA==.Majiique:BAAANQAECgEIBAAAAA==.Manseed:BAAANQADCgEIAgAAAA==.Maple:BAAANQAECgYICwAAAA==.Martei:BAACNQAFFH8XAAIkAAUK2xdpAQDXAAAkAAUK2xdpAQDXAAA1AAQKfzAAAiQACgpWHTsHAO8CACQACgpWHTsHAO8CAAAA.Maríneth:BAAANQAECgQIDwAAAA==.Mascara:BAAANQAECgYICwAAAA==.Maxe:BAAANQADCgIIAgAAAA==.',
Me='Memebait:BAAANQAECgUIBQAAAA==.Mementomori:BAAANQAECgEIAQAAAA==.Meowbae:BAAANQAECgUIBQABNQAECgQIBgAOAAAAAA==.Merce:BAAANQADCgcIBwABNQAECgkJFwADANsRAA==.Mercesdes:BAAANQADCgEIAQAAAA==.',
Mi='Midway:BAAANQAECgQIBgAAAA==.Minizee:BAAANQAECgEIAQAAAA==.Mirokushan:BAAANQAECgQIBQAAAA==.Missfire:BAAANQAECgIIAwAAAA==.Misticlady:BAAANQAECgQIBgAAAA==.Mistrariel:BAAANQAECgYIBwABNQAECgoKJAAbAMYbAA==.Mizukì:BAAANQADCgEIAQAAAA==.',
Mo='Moluubar:BAABNQAECn8pAAMKAAoKphNuZgCTAQAKAAoKphNuZgCTAQALAAEKAADURQAAAAAAAA==.Moradin:BAAANQADCgMIAwAAAA==.Mordemour:BAAANQAECgcICwAAAA==.Morienn:BAAANQAECgEIAQABNQAECgoKXwABAMQgAA==.',
Mu='Mufler:BAAANQABCgQIBQAAAA==.Mungo:BAAANQAECgcIEwAAAA==.Mushù:BAAANQAECgUICgABNQAECgoKNgAVAA0aAA==.',
My='Myfire:BAAANQADCgYIBgAAAA==.Myrell:BAAANQAECggICAAAAA==.Myrrh:BAAANQAECgYIDwAAAA==.Mythic:BAAANQADCgEIAQAAAA==.',
Na='Nalik:BAAANQAECgYIDgAAAA==.Nanou:BAAANQAECgUIBwAAAA==.Nardiaun:BAAANQADCgYIBgAAAA==.Naturebait:BAAANQADCgQIBAABNQAECggIMAACANUXAA==.',
Ne='Nerzheul:BAAANQAFFAEIAQAAAA==.',
Ni='Nicety:BAAANQAECgMIBAAAAA==.Nimravidae:BAABNQAECn81AAIJAAkKSRg2NAAZAgAJAAkKSRg2NAAZAgAAAA==.Ninelives:BAABNQAECn8bAAIHAAkKZALNVgCaAAAHAAkKZALNVgCaAAAAAA==.Nitecrawler:BAAANQADCgQIBAAAAA==.Niteeye:BAAANQADCgEIAQABNQAECgoKQwAXAEciAA==.Niteryu:BAAANQAECgEIAwABNQAECgoKQwAXAEciAA==.',
No='Nolokkotal:BAABNQAECn8vAAIKAAoK8BrPPQAeAgAKAAoK8BrPPQAeAgABNQAFFAEIAQAOAAAAAA==.Nospitfisty:BAAANQADCgQIBAAAAA==.Noxolon:BAABNQAECn8bAAMFAAgKshGIFABXAQAFAAgKshGIFABXAQAKAAEKAADYWwErAAAAAA==.',
Nr='Nreaf:BAACNQAFFH8IAAIIAAUK7QjxFQD/AAAIAAUK7QjxFQD/AAA1AAQKfywAAggACgrKE7uHABgCAAgACgrKE7uHABgCAAAA.',
['Nø']='Nørd:BAAANQADCgYIBgAAAA==.',
Oi='Oili:BAACNQAFFH8RAAIWAAUKaxSGAgAMAQAWAAUKaxSGAgAMAQA1AAQKfzEAAxYACgruGdcHAG0CABYACgruGdcHAG0CABcABAoADs9zAdcAAAAA.',
Ol='Olarrick:BAAANQAECgQIBQABNQAFFAIIBQAKAH4TAA==.',
Oo='Oops:BAACNQAFFH8SAAIPAAUKjRtFEgAzAQAPAAUKjRtFEgAzAQA1AAQKf0IAAw8ACgrNIHERACEDAA8ACgrNIHERACEDABAAAQqwCr5+ADAAAAAA.',
Or='Orcchopped:BAAANQADCgQIBAAAAA==.Ornstein:BAEANQAECgYIEQAAAA==.',
Ot='Ottuk:BAACNQAFFH8GAAIQAAMKFgmAGgCGAAAQAAMKFgmAGgCGAAA1AAQKfywAAhAACgrqHZMfAM4CABAACgrqHZMfAM4CAAAA.',
Pa='Padpaw:BAAANQAECgUJCAAAAA==.Pakraxes:BAABNQAECn8zAAIgAAoKBQ+bFQDyAQAgAAoKBQ+bFQDyAQAAAA==.Paksenarrion:BAABNQAECn82AAIaAAkKuBFYGQBzAQAaAAkKuBFYGQBzAQAAAA==.Palehoof:BAAANQADCggIGwABNQAECgEIAQAOAAAAAA==.Pallywaya:BAABNQAECn8eAAMIAAoKlw+cZgDHAQAIAAoKlw+cZgDHAQAJAAkKgwUZvABxAAAAAA==.Pandemonîum:BAAANQAECgQIBAABNQAECgoKIQAYAOAUAA==.Pandemônium:BAAANQADCgMIAwABNQAECgoKIQAYAOAUAA==.Pandemönium:BAABNQAECn8jAAQIAAgKeh0fVgCTAgAIAAgKUh0fVgCTAgAaAAIKzRxTUwCXAAAJAAIK8Ai0xwBbAAABNQAECgoKIQAYAOAUAA==.Pandemöniüm:BAABNQAECn8hAAMYAAoK4BTbFgDJAQAYAAkKihPbFgDJAQAZAAMKpg12JwCbAAAAAA==.Parts:BAAANQAECgEIAgAAAA==.Patchington:BAAANQAECgMIDwAAAA==.Pañdemönium:BAAANQAECgUICgABNQAECgoKIQAYAOAUAA==.',
Pe='Pedwyn:BAAANQAECggICAAAAA==.Pepperrjakk:BAAANQADCgEIAgAAAA==.Perck:BAAANQADCgYIBgAAAA==.Perrylee:BAAANQAECgUIDAAAAA==.',
Ph='Philia:BAABNQAECn8XAAMKAAgKmRWwnADVAQAKAAgKFhKwnADVAQALAAMK9Rp5KwDdAAABNQAFFAQIEAADAMEXAA==.Phurrball:BAAANQADCgYIBwAAAA==.',
Pi='Pixelme:BAABNQAFFH8GAAIEAAIKcASBHwB4AAAEAAIKcASBHwB4AAAAAA==.',
Pl='Pleggster:BAAANQAECgYIDAAAAA==.',
Po='Pochula:BAAANQAECgUICwAAAA==.',
Pr='Primo:BAACNQAFFH8GAAIJAAMKZQqgGgDJAAAJAAMKZQqgGgDJAAA1AAQKf1sAAgkACgrTGaYbAK4CAAkACgrTGaYbAK4CAAAA.Protricity:BAABNQAECn8YAAMeAAoKUBaiJAALAgAeAAgKmBSiJAALAgAMAAcKvBSpowAqAQAAAA==.',
Ps='Psalms:BAAANQAECgYIBQABNQAECgYIBwAOAAAAAA==.Psychoprowla:BAABNQAECn8/AAIeAAoKlxFhEgD8AQAeAAoKlxFhEgD8AQAAAA==.Psychozdrood:BAAANQAECgEIAQAAAA==.Psychozpally:BAAANQAECgQIBQAAAA==.',
['Pä']='Pändemönium:BAABNQAECn8aAAUGAAoK8BtTDwAGAgAGAAcKeB1TDwAGAgAHAAUK0AkkcQAFAQAkAAUKSg+KJgDZAAAlAAMKPwdcUQB6AAABNQAECgoKIQAYAOAUAA==.',
['Pæ']='Pæn:BAEBNQAECn8gAAMQAAoK/RwbNgBPAgAQAAoK9BsbNgBPAgAmAAcK2RLHNgCJAQABNQAFFAMICwAIABUiAA==.',
Qu='Quantar:BAAANQADCgYIBgABNQAECggIDgAOAAAAAA==.Quickstab:BAAANQAECgQICAAAAA==.',
Ra='Ragana:BAABNQAECn8YAAIBAAgKggjHgAD/AAABAAgKggjHgAD/AAAAAA==.Rainger:BAAANQADCgMIAwAAAA==.Rallypaly:BAAANQADCgMIAwAAAA==.Ramthor:BAAANQAECgYICwAAAA==.Rancooll:BAAANQADCggIIgAAAA==.Rasniir:BAABNQAECn8yAAIlAAkKARanIAAkAgAlAAkKARanIAAkAgAAAA==.Rasputea:BAAANQADCgEIAQAAAA==.Ravenar:BAAANQAECgQIBAAAAA==.Ravenlash:BAAANQAECgIIAwAAAA==.',
Re='Regna:BAACNQAFFH8RAAMKAAUK9yBkEAD+AAAKAAQK9yBkEAD+AAAFAAMKviJtAgDBAAA1AAQKfzEAAwoACgpnJSsbAEsDAAoACQqYJSsbAEsDAAUABQrfI1wQAKEBAAAA.Relkon:BAAANQADCgMIAwAAAA==.Remaked:BAACNQAFFH8pAAIiAAcKDBmkAQAAAgAiAAcKDBmkAQAAAgA1AAQKf0YAAiIACgqlISIEADsDACIACgqlISIEADsDAAAA.Requinix:BAABNQAECn9CAAIDAAkKVBZWUQDqAQADAAkKVBZWUQDqAQAAAA==.Retro:BAAANQADCggIDgAAAA==.Reynmaker:BAAANQADCgQIBAAAAA==.',
Rh='Rhowyn:BAAANQADCgQICAAAAA==.',
Ri='Riptidez:BAAANQADCgYIBgAAAA==.Ririko:BAABNQAECn82AAIMAAkK1A24WwCVAQAMAAkK1A24WwCVAQAAAA==.Ritzo:BAABNQAECn8yAAIFAAkKnBetCQC6AQAFAAkKnBetCQC6AQAAAA==.',
Ro='Robval:BAAANQAECgEIAQAAAA==.Rocksanne:BAAANQAECgQIBAAAAA==.Rooguee:BAAANQAECgIIAwAAAA==.',
Ru='Rukkis:BAABNQAECn8xAAMnAAoKzBpRDwCGAgAnAAkKhhpRDwCGAgAdAAgKDxcMKgBEAgAAAA==.Rukâ:BAAANQAECgEIAgAAAA==.Rumi:BAABNQAECn9SAAIjAAoKRh7MAwAdAwAjAAoKRh7MAwAdAwAAAA==.',
Ry='Ryeekan:BAAANQAECggIDQAAAA==.Ryuma:BAAANQAECgYIDwAAAA==.Ryumar:BAAANQAECgMIAwAAAA==.',
Sa='Sabrosura:BAABNQAECn8jAAIaAAkKYRHlJwCfAQAaAAkKYRHlJwCfAQAAAA==.Saiyan:BAAANQADCgIIAgAAAA==.Salsinor:BAAANQADCgYIDAAAAA==.Sanearia:BAAANQADCgEIAQAAAA==.Sanosagara:BAAANQAECggIBgAAAA==.Sathari:BAABNQAECn82AAINAAkKhBFiHQCFAQANAAkKhBFiHQCFAQAAAA==.',
Sc='Schaden:BAAANQAECgYIBwAAAA==.Scripter:BAAANQADCgUIBwAAAA==.',
Se='Seijo:BAAANQAECgEJAQAAAA==.Sekk:BAABNQAECn9DAAMIAAkKxxoIZwBmAgAIAAkKxxoIZwBmAgAaAAYKURVGJAAZAQAAAA==.Selecta:BAAANQAECgEIAQAAAA==.Selexi:BAAANQAECgYICgAAAA==.Selithira:BAABNQAECn8ZAAIMAAgKxBGIgQCTAQAMAAgKxBGIgQCTAQAAAA==.Sephylon:BAAANQADCgEIAQAAAA==.Sera:BAAANQADCgYICgAAAA==.Seton:BAAANQADCgUIBQABNQAECgoKNgANAHEbAA==.',
Sh='Shabagnarang:BAAANQAECgYIEAABNQAECggIJgATAFMbAA==.Shadeofdark:BAABNQAECn8nAAIoAAoKyxtxEAB+AgAoAAoKyxtxEAB+AgAAAA==.Shalasyr:BAAANQAECgEIAgAAAA==.Shaletaz:BAAANQADCgEIAQAAAA==.Shamwowee:BAAANQADCggILQAAAA==.Shamzee:BAACNQAFFH8LAAIBAAMKZhYsFQDMAAABAAMKZhYsFQDMAAA1AAQKf0MAAgEACgqPH5YLAEoDAAEACgqPH5YLAEoDAAAA.Shandalf:BAAANQAECgMIBAABNQAECgQIBQAOAAAAAA==.Sheyy:BAAANQAECgEIAQAAAA==.Shiftybonez:BAAANQADCgQIBQAAAA==.Shintok:BAAANQAECgUIEAAAAA==.Shuddarun:BAACNQAFFH8VAAIDAAgKQhqrAQB0AgADAAgKQhqrAQB0AgA1AAQKfzwAAgMACgosJV8NAHQDAAMACgosJV8NAHQDAAAA.',
Si='Silverbakk:BAAANQADCgEIAQAAAA==.Simn:BAAANQAECgYICwAAAA==.Sindraesong:BAAANQAECgUJCQAAAA==.',
Sk='Skithiryx:BAAANQAECgQICAABNQAECgoKNgANAHEbAA==.Skuldd:BAAANQAECgYICwAAAA==.',
Sl='Slayvylora:BAAANQAECgQIBQABNQAFFAUIFwAPAKkTAA==.',
Sm='Smarte:BAABNQAFFH8FAAIRAAQK3Aj+AADLAAARAAQK3Aj+AADLAAAAAA==.Smolderdk:BAAANQADCgEIAQAAAA==.Smolderpally:BAAANQADCgYIBwAAAA==.Smoldersham:BAAANQADCgEIAQAAAA==.',
Sn='Sneakymoth:BAAANQADCgUIBQABNQAECgcIFAAWANgVAA==.Snookums:BAABNQAECn8ZAAINAAgK4RYhIQBfAQANAAgK4RYhIQBfAQAAAA==.',
So='Soarin:BAAANQADCgQIBAAAAA==.',
Sp='Spicymaker:BAABNQAECn8mAAIKAAoKkxwHVQCLAgAKAAoKkxwHVQCLAgAAAA==.',
St='Starya:BAAANQAECgUICQAAAA==.Steelheart:BAAANQADCgEIAQAAAA==.Stolensøul:BAAANQABCggIDAAAAA==.Stop:BAAANQAECgMIAwAAAA==.Strifewood:BAAANQAECgcIBwAAAA==.Stumper:BAABNQAECn8xAAIHAAoKShdtJACiAQAHAAoKShdtJACiAQAAAA==.',
Su='Suluna:BAAANQAECgIIAwABNQAECgoKXwABAMQgAA==.Sux:BAAANQADCgMIAwAAAA==.',
Sy='Sybrina:BAABNQAECn88AAIDAAoKTRQMPwAhAgADAAoKTRQMPwAhAgAAAA==.Sylvia:BAABNQAECn8mAAIXAAoKtxJNwwD+AQAXAAoKtxJNwwD+AQAAAA==.Syngeance:BAABNQAECn8cAAIDAAYKPwWRxgDgAAADAAYKPwWRxgDgAAAAAA==.Synèsterwolf:BAAANQAECggIDQAAAA==.',
['Sí']='Síf:BAAANQAECgEIAQAAAA==.',
Ta='Tadeusz:BAAANQAECgYICQAAAA==.Taelah:BAAANQAECggIAwAAAA==.Tamamò:BAAANQADCgYICAAAAA==.Tanglefoot:BAABNQAECn8gAAIKAAgKFhKHgAAaAgAKAAgKFhKHgAAaAgAAAA==.Tanleros:BAABNQAECn8cAAIJAAkK+xRyVwATAgAJAAkK+xRyVwATAgAAAA==.Taquítos:BAAANQADCgYICQAAAA==.Tasigur:BAAANQAECgUICgABNQAECgoKNgANAHEbAA==.',
Te='Telana:BAAANQADCggILQAAAA==.Tentación:BAAANQADCggICAABNQAECgkJIwAaAGERAA==.Tequitos:BAAANQAECgcIEQAAAA==.Tessla:BAAANQAECgIIBQAAAA==.',
Th='Theduk:BAABNQAECn8xAAMnAAoKPhMzHwDXAQAnAAoKpBIzHwDXAQAdAAkK4QrXQADIAQAAAA==.Theduke:BAAANQAECgQIBQAAAA==.Theexwife:BAAANQAECgEIAQAAAA==.Theliria:BAAANQADCgYIBgAAAA==.Thorias:BAABNQAECn8ZAAIXAAgKKxtkjgBiAgAXAAgKKxtkjgBiAgAAAA==.Thunderblast:BAAANQADCggIAQAAAA==.',
To='Toira:BAAANQADCgUIBQAAAA==.Tomoko:BAAANQADCgYICgAAAA==.Torment:BAABNQAECn88AAIPAAkKHBo+HADxAQAPAAkKHBo+HADxAQAAAA==.',
Tr='Tristén:BAABNQAECn8lAAIDAAoK8hStRQAMAgADAAoK8hStRQAMAgAAAA==.Truvie:BAAANQADCgMIAwAAAA==.',
Tu='Tumbled:BAABNQAECn8VAAIXAAcKYhGF5QC+AQAXAAcKYhGF5QC+AQAAAA==.Tumbles:BAAANQADCgQIBQAAAA==.Tumni:BAAANQAECgYIEwAAAA==.',
Tw='Twinkletoes:BAAANQAECgMIAwAAAA==.',
['Tá']='Tángall:BAAANQADCgEIAQAAAA==.',
Ui='Ui:BAAANQADCgMIAwAAAA==.',
Ul='Ulnuk:BAABNQAECn9FAAIBAAoKfh9UCAB1AwABAAoKfh9UCAB1AwAAAA==.Ulster:BAAANQADCgEIAQAAAA==.',
Un='Ungodly:BAABNQAECn8tAAImAAoKjxHJNwD3AQAmAAoKjxHJNwD3AQAAAA==.Unholyshan:BAAANQAECgIIAgABNQAECgQIBQAOAAAAAA==.Unidus:BAAANQAECgEIAwAAAA==.',
Uu='Uutr:BAAANQADCgEIAQAAAA==.',
Uv='Uvvolx:BAAANQADCgQICAAAAA==.',
Va='Vackra:BAAANQADCgEIAgAAAA==.Vadka:BAAANQAECgUIEAAAAA==.Vaeldrin:BAAANQAECgQIBQAAAA==.Vaha:BAAANQAECgIIBgAAAA==.Valkree:BAAANQAECgUIDgAAAA==.Vallae:BAAANQADCgEIAQABNQAECgoKXwABAMQgAA==.Valroc:BAAANQADCgYIDAAAAA==.Valsavis:BAABNQAECn89AAIjAAoKQyBABgC6AgAjAAoKQyBABgC6AgAAAA==.Valtier:BAAANQADCgMIAwAAAA==.',
Ve='Veaolop:BAAANQADCgEIAQAAAA==.Vellagosa:BAAANQAECgUIDAAAAA==.Vernice:BAAANQADCgYICwABNQAECgcICwAOAAAAAA==.Verulan:BAAANQAECgYIDgAAAA==.Vexidari:BAAANQAECgYIDwABNQAFFAUIFwAPAKkTAA==.Vexomous:BAABNQAECn8eAAMRAAgKgBqrBQBbAgARAAgKgBqrBQBbAgAEAAQKDgdTWwC3AAABNQAFFAUIFwAPAKkTAA==.',
Vi='Viiolet:BAAANQAFFAEIAQAAAA==.',
Vo='Voidmayne:BAABNQAECn8uAAIIAAoKHRQQoADhAQAIAAoKHRQQoADhAQAAAA==.Vongogh:BAAANQADCgYICQAAAA==.Vonhelsing:BAAANQAECgQIBAAAAA==.Vorenius:BAAANQAECgIIAgAAAA==.',
Vy='Vynnara:BAAANQADCgEIAQAAAA==.Vyolent:BAAANQADCgYICwAAAA==.',
Wa='Wapello:BAAANQABCgcIEAAAAA==.Warnox:BAAANQAECgIIAgAAAA==.',
We='Weiand:BAABNQAECn8wAAMIAAgKkhhyUwD8AQAIAAgKkhhyUwD8AQAJAAcKLQx5jwBvAQAAAA==.Wevark:BAABNQAECn8WAAIKAAgKoQpqtQCXAQAKAAgKoQpqtQCXAQAAAA==.',
Wh='Whatami:BAABNQAECn82AAQVAAoKDRreLAAvAgAVAAoKDRreLAAvAgAbAAIKvxHtHABrAAAUAAEKAABLLAAAAAAAAA==.Whiteknight:BAAANQAECgEIAgABNQAECgoKNgAVAA0aAA==.Wholemilk:BAABNQAECn8bAAINAAcKAx1TJQAbAgANAAcKAx1TJQAbAgAAAA==.',
Wi='Wilhellena:BAABNQAECn80AAIMAAoKQRJ9VACvAQAMAAoKQRJ9VACvAQAAAA==.Wilhellfu:BAAANQADCgMIAwAAAA==.Willowhisp:BAAANQADCgEIAQAAAA==.Winariel:BAABNQAECn8kAAIbAAoKxhs4AQCiAgAbAAoKxhs4AQCiAgAAAA==.Witewalker:BAAANQADCgcICgAAAA==.',
Wo='Wobum:BAAANQAECgEIAQAAAA==.',
Wr='Wrakesoul:BAAANQAECgEIAQABNQAECgoKIwACAEIXAA==.Wraspsoul:BAAANQAECgEIAQABNQAECgoKIwACAEIXAA==.Writhesoul:BAAANQABCgIIAgABNQAECgoKIwACAEIXAA==.Wroughtsoul:BAABNQAECn8jAAQZAAoK9gl7EwCMAQAZAAoK9gl7EwCMAQAYAAIKvQv9XgBkAAAiAAEKAADWLwA+AAAAAA==.Wrysoul:BAABNQAECn8jAAICAAoKQheANACmAgACAAoKQheANACmAgAAAA==.',
Wy='Wynston:BAAANQADCgEIAQAAAA==.Wyrmheart:BAAANQADCgIIAwAAAA==.',
Xa='Xaldred:BAABNQAECn8eAAIVAAoK7Qx5hQDYAQAVAAoK7Qx5hQDYAQABNQAECgoKQQAQAJ8cAA==.Xandir:BAABNQAECn8hAAIaAAkKQxOkGgBmAQAaAAkKQxOkGgBmAQAAAA==.Xarhunt:BAAANQAECgMICgAAAA==.',
Xe='Xenzia:BAAANQADCgcIDAAAAA==.Xeracil:BAAANQADCgQIDQAAAA==.',
Xo='Xoric:BAABNQAECn8xAAIlAAoKlxg7DgCgAgAlAAoKlxg7DgCgAgAAAA==.',
Xy='Xyal:BAABNQAECn8kAAIMAAkKwxaxbwDOAQAMAAkKwxaxbwDOAQAAAA==.Xyp:BAAANQADCgYIBgABNQAECgYIDgAOAAAAAA==.',
Ya='Yamaya:BAAANQADCgYICwAAAA==.',
Yi='Yiago:BAAANQAECgMIDQAAAA==.',
Yo='Youknow:BAAANQADCgcICwAAAA==.',
Za='Zaelia:BAAANQADCgEIAQAAAA==.Zary:BAAANQAECgIIBAABNQAECggIAgAOAAAAAA==.Zaxhdk:BAEANQADCgMIAwABNQAECggIGQAJAPwSAA==.Zaxhpal:BAEBNQAECn8ZAAIJAAgK/BIndgC1AQAJAAgK/BIndgC1AQAAAA==.',
Ze='Zenedy:BAAANQAECgQIBAABNQAECgcICwAOAAAAAA==.Zerrus:BAAANQAECgQIBQAAAA==.',
Zh='Zhada:BAAANQADCgEIAQAAAA==.',
Zi='Zid:BAAANQAECgMIAwAAAA==.Ziny:BAAANQADCgUIBQAAAA==.Ziparoo:BAABNQAECn8yAAIWAAkKZgtlDgBiAQAWAAkKZgtlDgBiAQAAAA==.',
Zo='Zoenova:BAAANQAECggIAwAAAA==.',
Zr='Zraven:BAAANQADCgEIAQAAAA==.',
['În']='Îniquitous:BAAANQAECgUIDgAAAA==.',
['Ðê']='Ðêmønicßløøð:BAABNQAECn8mAAMmAAoK5BQ2IgAGAgAmAAoK5BQ2IgAGAgAQAAMKggrGsACQAAABNQAFFAEIAQAOAAAAAA==.',
['Üb']='Übernasus:BAAANQADCgQIBgAAAA==.',
['ßy']='ßyrøßløøð:BAAANQAECgIIAgAAAA==.',
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
