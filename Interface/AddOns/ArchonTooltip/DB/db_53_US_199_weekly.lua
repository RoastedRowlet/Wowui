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

local lookup = {'Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Fury','Druid-Guardian','Druid-Balance','Paladin-Retribution','Paladin-Holy','Warrior-Arms','Warrior-Protection','Priest-Holy','DemonHunter-Devourer','Unknown-Unknown','DeathKnight-Blood','DeathKnight-Unholy','Hunter-Survival','Mage-Fire','Shaman-Enhancement','Warlock-Affliction','Warlock-Demonology','Mage-Frost','Mage-Arcane','Monk-Windwalker','Monk-Mistweaver','Paladin-Protection','Warlock-Destruction','Evoker-Preservation','Rogue-Assassination','Priest-Discipline','Evoker-Devastation','Evoker-Augmentation','Monk-Brewmaster','Priest-Shadow','DemonHunter-Vengeance','Druid-Feral','Druid-Restoration','DeathKnight-Frost','Rogue-Subtlety','DemonHunter-Havoc',}
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aabbigale:BAAANQAECggIAQAAAA==.',
Ab='Abigt:BAAANQADCgIIAQAAAA==.',
Ac='Acidsnow:BAAANQAECgQIBQAAAA==.',
Ad='Adalaidê:BAAANQAECgMICAAAAA==.',
Ae='Aerynne:BAAANQADCggIJgAAAA==.',
Ai='Airie:BAABNQAECn8oAAMBAAkKXwipXQAlAQABAAkKXwipXQAlAQACAAUKUgZolQBzAAAAAA==.',
Ak='Akuso:BAAANQADCgIIAgAAAA==.',
Al='Alcohaulorc:BAAANQAECgQIBwAAAA==.Alert:BAAANQAECgEIAQAAAA==.Aloris:BAAANQAECgQICAAAAA==.Aloy:BAACNQAFFH8QAAMDAAQKwRcPEABaAQADAAQKwRcPEABaAQAEAAEKAABwKAAzAAA1AAQKfxUAAgMABQo8H45nAGwBAAMABQo8H45nAGwBAAAA.Aluhx:BAAANQAECgMICQABNQAFFAYICwAFAJQRAA==.',
Am='Amednato:BAABNQAECn8ZAAMGAAoKeweYLAA0AQAGAAoKeweYLAA0AQAHAAEKcwUlcAAwAAAAAA==.',
An='Anaeli:BAABNQAECn9TAAIBAAoKtCCIGwABAwABAAoKtCCIGwABAwAAAA==.Anastarian:BAAANQAECgEIAQAAAA==.Ancalagonn:BAAANQAECgcIDwAAAA==.Angita:BAAANQAECgUIDAAAAA==.Anklin:BAAANQADCgIIAgAAAA==.Annaris:BAACNQAFFH8ZAAIDAAcKOBwCAwA8AgADAAcKOBwCAwA8AgA1AAQKfy4AAwMACgr3JUMHAKIDAAMACgr3JUMHAKIDAAQACQrJGS0yALwBAAAA.Antipæn:BAECNQAFFH8KAAMIAAMKFSJpEwAfAQAIAAMKFSJpEwAfAQAJAAEKdCO9JQBlAAA1AAQKf0IAAwgACgpuJaIEANQDAAgACgpuJaIEANQDAAkACgoiITkLAG4DAAAA.',
Ap='Apologia:BAABNQAECn8yAAIIAAoKQiGzFADVAgAIAAoKQiGzFADVAgAAAA==.',
Aq='Aquaphobic:BAAANQAECgUIDAABNQAFFAcIFAABAGYJAA==.',
Ar='Arcanoth:BAAANQADCgIIAgAAAA==.Ardicelia:BAAANQABCgUIBgAAAA==.Ares:BAABNQAECn8oAAIKAAoK5R/7HQBAAwAKAAoK5R/7HQBAAwAAAA==.Armorgorden:BAABNQAECn83AAILAAoK+yAfAwC8AgALAAoK+yAfAwC8AgAAAA==.Aroviaa:BAABNQAECn83AAIMAAoKmBk1QABqAgAMAAoKmBk1QABqAgAAAA==.Arpmek:BAABNQAECn8zAAINAAoK3RNwJQAaAgANAAoK3RNwJQAaAgAAAA==.Artemîs:BAAANQADCgIIAgAAAA==.',
As='Asharienne:BAABNQAECn8sAAIDAAoKXhAQNwADAgADAAoKXhAQNwADAgAAAA==.Ashlynne:BAAANQAECgYJCwAAAA==.',
Au='Audiobully:BAAANQAECgQIBAABNQAECgoKLQAHAEwUAA==.Auntmary:BAAANQABCgUICAAAAA==.Auralynn:BAAANQAECgQJBAABNQAECgYJCwAOAAAAAA==.Auriella:BAABNQAECn8jAAMJAAoKVhAuaQDcAQAJAAoKVhAuaQDcAQAIAAIKsgjDSwEvAAAAAA==.Aurtt:BAABNQAECn80AAMPAAoKshRJRQDlAQAPAAkKPhVJRQDlAQAQAAMKEAniSwCIAAAAAA==.',
['Aö']='Aöb:BAAANQADCgQIBgAAAA==.',
Ba='Bahahaknight:BAABNQAECn8xAAIPAAkKxBPiHwCTAQAPAAkKxBPiHwCTAQAAAA==.Bahree:BAAANQADCgIIAgAAAA==.Bakhar:BAABNQAECn8iAAIRAAgKCxwPBQB8AgARAAgKCxwPBQB8AgAAAA==.Balora:BAAANQADCgcIGAAAAA==.Barnette:BAABNQAECn9CAAISAAoKGxbOAAAzAgASAAoKGxbOAAAzAgAAAA==.Basyleus:BAAANQADCgEIAQAAAA==.',
Be='Beau:BAAANQAECgMIBAABNQAECgkJGAAJAMgfAA==.Belthos:BAABNQAECn8ZAAIIAAgKSBgceQA6AgAIAAgKSBgceQA6AgAAAA==.Benihime:BAAANQAECgEIAQAAAA==.Berristan:BAABNQAECn8/AAMJAAoKlw/2OAC4AQAJAAoKlw/2OAC4AQAIAAEKegRrSgEwAAAAAA==.Bestwingman:BAAANQADCgEIAQAAAA==.',
Bi='Bigdawgsteve:BAAANQADCgIIAgAAAA==.Bigmarv:BAAANQAECgUIDAAAAA==.Bittytigs:BAACNQAFFH8MAAIBAAMKwhfdFwDiAAABAAMKwhfdFwDiAAA1AAQKf0sAAwEACgr3Hp8UACgDAAEACgr3Hp8UACgDAAIAAQoAAGBOAScAAAAA.',
Bl='Blestemat:BAAANQADCgYIBwAAAA==.Blossom:BAAANQAFFAQIBAABNQAFFAUIDQAOAAAAAQ==.Blumangood:BAABNQAECn8vAAQCAAgK1RfCMgCNAQACAAgK1RfCMgCNAQABAAIKLQKKFQE/AAATAAEKAADnNwAwAAAAAA==.',
Bo='Bollux:BAAANQAECgEIAgAAAA==.Bosc:BAABNQAECn8jAAIPAAkKMhbSIACMAQAPAAkKMhbSIACMAQAAAA==.Boudiicca:BAAANQADCggIJgAAAA==.Boxmasterr:BAABNQAECn83AAMUAAoK4BW+BQBeAgAUAAgKqBi+BQBeAgAVAAYKYg+kVABlAQAAAA==.',
Br='Braagh:BAAANQABCggICwAAAA==.Brasmir:BAABNQAECn8wAAIRAAoKkxyoAgAIAwARAAoKkxyoAgAIAwAAAA==.Briae:BAAANQADCgMIAwABNQAECgoKUwABALQgAA==.Brianzero:BAAANQABCgQJBgAAAA==.Brino:BAAANQABCgQIBAAAAA==.Brinotriage:BAAANQAECgYIBQAAAA==.',
Bu='Bubblemoth:BAAANQADCgMIBAABNQAECgcIFAAWANgVAA==.Buik:BAAANQAECgIIAgAAAA==.Bulge:BAABNQAECn8gAAMXAAoKNQsw0QDkAQAXAAoK0wow0QDkAQAWAAEK2Rb9PwBEAAABNQAFFAQIDgAQAGILAA==.Bulgogi:BAACNQAFFH8OAAIQAAQKYgsVBgDPAAAQAAQKYgsVBgDPAAA1AAQKfzoAAhAACgrgHuMHAK4CABAACgrgHuMHAK4CAAAA.Butherrface:BAAANQADCgUIBQAAAA==.',
['Bö']='Börk:BAAANQAECgUIDAAAAA==.',
Ca='Capy:BAAANQAECgIIAgABNQAFFAQIBgAWAOQUAA==.Cardran:BAAANQADCgIIAgABNQAECgkJFwADANsRAA==.Cayda:BAAANQADCgYICwAAAA==.Caylara:BAAANQAECgMICgAAAA==.Cayssabber:BAAANQAECgUIBQAAAA==.Cayssaber:BAAANQAECgIIAgAAAA==.',
Ce='Ceicilia:BAAANQADCgQIBAAAAA==.Celrythis:BAAANQAECgMIBgAAAA==.Cenokry:BAAANQADCgQIBAAAAA==.',
Ch='Chai:BAABNQAECn8YAAMYAAkKxwuENgBhAQAYAAkKxwuENgBhAQAZAAEK1QGNVQAeAAAAAA==.Chaintrain:BAAANQAECgMIAwABNQAECgkJGAAVAJ4SAA==.Chellyy:BAAANQAECgYICAABNQAECgYIFQANAPIeAA==.Chibisend:BAAANQADCgMIAwAAAA==.Chámeleon:BAAANQADCgEIAQAAAA==.',
Ci='Cider:BAAANQAECgIIAgAAAA==.',
Cl='Claes:BAAANQADCgMIAwABNQAECgkJIwAPADIWAA==.',
Co='Coralbubbles:BAABNQAECn8sAAIIAAoKHRIUUQDDAQAIAAoKHRIUUQDDAQAAAA==.Coralorchid:BAABNQAECn8pAAIaAAYKtx4bGwAWAgAaAAYKtx4bGwAWAgAAAA==.Coralprays:BAAANQADCgIIAgAAAA==.Coralrages:BAAANQAECgQIBgAAAA==.',
Cr='Cromenockle:BAABNQAECn8UAAQUAAkKmBO+EwAPAQAVAAgKahIYhADcAQAUAAQKdw++EwAPAQAbAAIKuw4vWAB3AAABNQAFFAIIAwAOAAAAAA==.Crtitman:BAAANQAECgUIDAAAAA==.',
Cu='Cupcâke:BAAANQAECgQIBAAAAA==.Curissan:BAABNQAECn8fAAICAAcKERTRbQDWAQACAAcKERTRbQDWAQAAAA==.',
Da='Dalgon:BAABNQAFFH8IAAIcAAQK6wRDEADvAAAcAAQK6wRDEADvAAABNQAFFAYIDgAJADoVAA==.Dalir:BAAANQAECgYIDgAAAA==.Dalspin:BAAANQADCgYIDAAAAA==.Dalthepal:BAACNQAFFH8OAAIJAAYKOhXvBwDnAQAJAAYKOhXvBwDnAQA1AAQKfz4AAgkACgqbHzoXAB8DAAkACgqbHzoXAB8DAAAA.Damné:BAABNQAECn83AAIQAAoKDhiSDwAmAgAQAAoKDhiSDwAmAgAAAA==.Darze:BAAANQADCggIAwABNQAECgUICAAOAAAAAA==.Davidline:BAABNQAECn8qAAIIAAoKuhxCJgBrAgAIAAoKuhxCJgBrAgAAAA==.',
De='Deadish:BAABNQAECn86AAMPAAoKiCD/BQD6AgAPAAoKiCD/BQD6AgAQAAEKDQYtfAASAAAAAA==.Deathsaberss:BAABNQAECn9DAAMKAAoK4RfZQwC+AgAKAAoK4RfZQwC+AgALAAQK5Au+KgDjAAAAAA==.Deathvex:BAACNQAFFH8TAAIPAAUKqRM3FAAYAQAPAAUKqRM3FAAYAQA1AAQKfxkAAg8ACApCGU4oAFgBAA8ACApCGU4oAFgBAAAA.Decoz:BAAANQAECgUICgAAAA==.Deight:BAAANQADCgIIAgAAAA==.Dejamoo:BAAANQADCgYIGAAAAA==.Dendahn:BAAANQAECgcIDQAAAA==.Destinee:BAAANQAECgQICwAAAA==.',
Di='Dianntha:BAAANQADCgcIFwAAAA==.Diladrin:BAABNQAECn9OAAIGAAoKAxqLDACfAgAGAAoKAxqLDACfAgAAAA==.Dinomight:BAAANQADCgQIBAAAAA==.',
Do='Doileag:BAAANQAECgQIDQAAAA==.Doomgrave:BAAANQADCgEIAQAAAA==.Dora:BAAANQADCgYIBgABNQAECgYIGAAdANQFAA==.Dottmatrix:BAAANQAECgMIDAAAAA==.Doubledowns:BAAANQAECgEIAQAAAA==.',
Dr='Dreadwing:BAAANQADCggIJgAAAA==.Druromu:BAAANQAECgMICgAAAA==.',
Du='Dufs:BAACNQAFFH8VAAIBAAUKDiZzBgCcAQABAAUKDiZzBgCcAQA1AAQKfywAAgEACgrNH2wcAPwCAAEACgrNH2wcAPwCAAAA.Dunkan:BAAANQAECgMIAwAAAA==.Dustbunny:BAABNQAECn84AAMMAAkKFRe1OQDQAQAMAAkKFRe1OQDQAQAeAAEK/gZ+EwAoAAAAAA==.',
Dw='Dwagon:BAABNQAECn8UAAMfAAgKYQlaIgA4AQAfAAYKQQtaIgA4AQAgAAMK1gd5IABWAAAAAA==.',
Dy='Dylsonlolqt:BAAANQAECggIEQAAAA==.',
['Dã']='Dãrling:BAAANQABCgEIAQAAAA==.',
['Dû']='Dûn:BAABNQAECn80AAMYAAoKmiDLDQAAAwAYAAoKUiDLDQAAAwAhAAgKNh4pCgB1AgAAAA==.Dûna:BAABNQAECn8nAAIiAAoKGBtGFADCAgAiAAoKGBtGFADCAgABNQAECgoKNAAYAJogAA==.',
El='Elaatia:BAABNQAECn83AAIIAAoKySNjKgAdAwAIAAoKySNjKgAdAwAAAA==.Elidria:BAAANQABCgIIAgABNQADCgYIBgAOAAAAAA==.Ellysprocket:BAAANQADCgUICQAAAA==.Elrric:BAAANQAECgYICgAAAA==.Elyak:BAAANQADCgIIAgAAAA==.',
En='Envoy:BAAANQAECgMIAwAAAA==.',
Er='Erakron:BAABNQAECn8xAAMCAAoKORLgLwCaAQACAAoKORLgLwCaAQABAAYKmBPUpwAiAQAAAA==.Erine:BAAANQAECgIIAgAAAA==.Erouvi:BAAANQADCgIIAgABNQAECgoKNwAMAJgZAA==.Eroviaa:BAAANQAECgUIBwABNQAECgoKNwAMAJgZAA==.Erovvia:BAAANQADCgUIBQABNQAECgoKNwAMAJgZAA==.',
Es='Esmeralda:BAAANQABCggIEAAAAA==.',
Ev='Evorik:BAAANQAECgUIBgABNQAFFAIIBQAKAH4TAA==.',
Ez='Ezothen:BAABNQAECn8XAAMfAAcKnAYFJgAIAQAfAAYK+gYFJgAIAQAgAAEKJAUtFgAuAAAAAA==.',
Fa='Facelessman:BAAANQABCggIJgAAAA==.Faedoria:BAAANQAECgUICQAAAA==.Faeryln:BAABNQAECn84AAIMAAoKuQjzSwCBAQAMAAoKuQjzSwCBAQAAAA==.Faustus:BAABNQAECn8YAAIJAAkKyB8jJgDRAgAJAAkKyB8jJgDRAgAAAA==.Favion:BAAANQADCgEIAQAAAA==.',
Fe='Felyyia:BAABNQAECn8hAAINAAoKQyJdAgAsAwANAAoKQyJdAgAsAwABNQAFFAcIGQADADgcAA==.',
Fi='Fiddlestix:BAAANQAECgQIBAAAAA==.Firebrande:BAAANQAECgUIDAAAAA==.Fisticuffs:BAAANQADCggIKwAAAA==.Fizcrankshot:BAABNQAECn83AAIDAAoKVhMOMQAcAgADAAoKVhMOMQAcAgAAAA==.',
Fl='Flamewhisker:BAAANQAECgUIDAAAAQ==.Flamez:BAAANQADCgcIBwAAAA==.Flandre:BAAANQAECgUIBAAAAA==.',
Fr='Fraublucher:BAABNQAECn8uAAIMAAkKDgrvTQB5AQAMAAkKDgrvTQB5AQAAAA==.Frewyn:BAAANQAECgYIDgAAAA==.Frostimoth:BAABNQAECn8UAAIWAAcK2BW9EQCKAQAWAAcK2BW9EQCKAQAAAA==.Frozty:BAAANQAECgQIBgAAAA==.',
Ga='Galandel:BAAANQADCggIKAAAAA==.Galial:BAACNQAFFH8LAAIjAAMK9hDBAQC2AAAjAAMK9hDBAQC2AAA1AAQKfzIAAiMACgpfGgwHAKACACMACgpfGgwHAKACAAAA.Gantar:BAAANQAECgUIBQABNQAFFAIIBgAPAL0cAA==.Garradin:BAAANQADCgEIAQAAAA==.Garrunter:BAAANQAECgEIAgAAAA==.Gaznol:BAAANQADCgQIBAABNQAECgoKGQAGAHsHAA==.',
Ge='Gelasera:BAAANQAECgUICwAAAA==.Gemitra:BAAANQADCgcIBwABNQAECgYIKQAaALceAA==.Geneth:BAAANQAECgUIBQAAAA==.George:BAACNQAFFH8FAAIKAAIKfhPSLgCPAAAKAAIKfhPSLgCPAAA1AAQKfysAAgoACQpiHz04APIBAAoACQpiHz04APIBAAAA.',
Gh='Ghalta:BAAANQADCgIIAgABNQAECgoKMAANAPAaAA==.Ghrol:BAAANQABCgYIBgABNQAECgoKOwABAEIcAA==.',
Gl='Glaivethras:BAABNQAECn81AAIjAAoK2x8UAwA9AwAjAAoK2x8UAwA9AwAAAA==.Glenfin:BAAANQADCgQIBgAAAA==.',
Gr='Greg:BAAANQAECgEIAQAAAA==.Gremlynn:BAAANQADCggICAAAAA==.Grimclaw:BAACNQAFFH8JAAMkAAUKawfdAgC3AAAHAAQKawfdFgD7AAAkAAIKAADdAgC3AAA1AAQKfywAAyQACgorJfQIALgBAAcACAqVIsseANQCACQABgrnJfQIALgBAAAA.Groot:BAABNQAECn8VAAMlAAUKjBfwQgATAQAlAAUKjBfwQgATAQAHAAMK8wyrjQCgAAABNQAECgkJIAAaAGERAA==.',
Gu='Guthrek:BAAANQAECgYIBwAAAA==.',
Ha='Hamfist:BAAANQADCgIIAgABNQAECggIEgAOAAAAAA==.Hannebal:BAABNQAECn8hAAIJAAoKIxMxHQBaAgAJAAoKIxMxHQBaAgAAAA==.',
He='Healsonyou:BAAANQAFFAEIAQABNQAECgoKKwAKAG8YAA==.Healyclam:BAAANQADCgMIAwAAAA==.Heydaw:BAAANQADCggICAABNQAECgkJGAAmAJUbAA==.Heynow:BAAANQAECgUICgAAAA==.',
Hi='Higherp:BAAANQADCggICAABNQAECgcIIgAkAJMRAA==.Highmountain:BAAANQADCggIDQAAAA==.Hilimed:BAABNQAECn86AAIVAAoKgwqdRQCVAQAVAAoKgwqdRQCVAQAAAA==.',
Ho='Hobs:BAAANQADCgUIBQAAAA==.Holyßloodelf:BAAANQAECgcIDgABNQAECgoKKwAKAG8YAA==.Hoosier:BAAANQAECgYIDwAAAA==.Hoplite:BAABNQAECn8bAAIlAAkKQhXtGACoAQAlAAkKQhXtGACoAQAAAA==.',
Hu='Huasca:BAAANQAECgEIAQAAAA==.Huthuel:BAAANQABCggIFAAAAA==.',
Hy='Hydra:BAAANQADCgYIBgABNQAECgoKJQAXALcSAA==.Hyve:BAAANQAECgMIAwABNQAECgkJOwAIAMcaAA==.',
['Hà']='Hàney:BAEANQAECgQIBAAAAA==.',
['Hé']='Hélio:BAAANQADCgUIBQAAAA==.',
Ia='Ia:BAABNQAECn8tAAImAAoKwh7UCwA4AwAmAAoKwh7UCwA4AwAAAA==.',
Ib='Ibesmashin:BAAANQADCgQIBAABNQAECggIEgAOAAAAAA==.Ibesneakin:BAAANQADCggIDgABNQAECggIEgAOAAAAAA==.',
Id='Idontsuck:BAAANQADCggICwAAAA==.',
Il='Ileynha:BAAANQAECgYICwAAAA==.Ilieau:BAAANQAECgQIBQABNQAECggIDAAOAAAAAA==.Illida:BAAANQADCgYIBgAAAA==.',
Im='Imamalelol:BAAANQAECgUIDAAAAA==.',
In='Inarrah:BAAANQADCgEIAQAAAA==.Intol:BAAANQAFFAUIDQAAAQ==.Intrepidhero:BAAANQADCgEIAQAAAA==.',
Ir='Irkenfox:BAECNQAFFH8VAAILAAUKthUXAgDNAAALAAUKthUXAgDNAAA1AAQKfy0AAgsACgoJJKQCAIYDAAsACgoJJKQCAIYDAAAA.',
It='Ithran:BAAANQADCgUIBQAAAA==.',
Iw='Iwilltank:BAAANQADCgYICwAAAA==.',
Ix='Ixitt:BAABNQAECn8wAAISAAoKrxg9AgA6AgASAAoKrxg9AgA6AgAAAA==.',
Ja='Jama:BAAANQADCgYIBgAAAA==.Janderick:BAAANQAECgYIDgAAAA==.Jaromer:BAAANQADCgcIEAAAAA==.',
Je='Jellacee:BAAANQADCgcIFwAAAA==.',
Ji='Jimboberjim:BAACNQAFFH8VAAIbAAUKVh+4AAB9AQAbAAUKVh+4AAB9AQA1AAQKfzEAAhsACgrsI2wBAHsDABsACgrsI2wBAHsDAAAA.Jimbobwhey:BAABNQAECn8YAAIhAAkKbg2nBwB2AQAhAAkKbg2nBwB2AQAAAA==.Jiminie:BAABNQAECn8eAAILAAgKPxMdFgDHAQALAAgKPxMdFgDHAQABNQAECgkJGAAhAG4NAA==.',
Jo='Jolio:BAABNQAECn8YAAQVAAkKnhKdeQAEAQAVAAgKRBGdeQAEAQAbAAEKuBq9aABQAAAUAAIKaAlyKABKAAAAAA==.Joltraxi:BAAANQADCggICAABNQAECgkJGAAVAJ4SAA==.Joshie:BAACNQAFFH8GAAIPAAIKvRy5DwCnAAAPAAIKvRy5DwCnAAA1AAQKfy0AAg8ACgr/I+gJAGYDAA8ACgr/I+gJAGYDAAAA.Joshy:BAAANQADCgcIBwABNQAFFAIIBgAPAL0cAA==.',
Ju='Jujubeans:BAAANQAECgEIAQAAAA==.Juniornite:BAABNQAECn85AAIXAAoK9CFDFgCxAgAXAAoK9CFDFgCxAgAAAA==.Justthetouch:BAAANQAECgQIBAAAAA==.',
Jy='Jygglypuff:BAAANQAECgMIBAAAAA==.',
Ka='Kadaan:BAAANQAECgUIBQAAAA==.Kagemaro:BAABNQAECn8wAAMNAAoK8BpBFQC7AgANAAoK8BpBFQC7AgAjAAUKdRS7GQAZAQAAAA==.Kahgar:BAAANQAECggIIAABNQAECgoKUwAJAI8YAQ==.Kalimathath:BAAANQAECgEIAgAAAA==.Kalzod:BAABNQAECn9MAAIVAAoKcSXyAQDcAwAVAAoKcSXyAQDcAwAAAA==.Kataki:BAABNQAECn8kAAIDAAkKNRiCRADSAQADAAkKNRiCRADSAQABNQAECgoKMAANAPAaAA==.Katia:BAAANQAECgMICAAAAA==.Kativeria:BAAANQAECgUICgAAAA==.Katjayna:BAAANQADCgUICgAAAA==.Kaysabr:BAAANQAECgUIBQAAAA==.Kayssaber:BAABNQAECn8bAAMlAAgKgxTWFwC1AQAlAAgKgxTWFwC1AQAHAAMK5BDvjwCXAAAAAA==.',
Ke='Kebab:BAAANQAECgQJBAAAAA==.Kelsifer:BAAANQAECgQICwABNQAECgkJGAAJAMgfAA==.Kempra:BAAANQADCgcIBwAAAA==.Kemprei:BAAANQADCgUIBQAAAA==.Kendralust:BAAANQAECgcICAAAAA==.Kerfufle:BAAANQABCgIJAgAAAA==.',
Kh='Khaos:BAAANQABCgEIAQAAAA==.',
Ki='Kippars:BAAANQAECgEIAQAAAA==.',
Kl='Klaax:BAAANQADCgYIDAABNQAECgkJOwAIAMcaAA==.',
Ko='Kodazoff:BAAANQAECgcIEAAAAA==.Kora:BAAANQABCgEIAgAAAA==.Korevash:BAABNQAECn87AAMBAAoKZCP9AwCrAwABAAoKZCP9AwCrAwATAAYKAhJaHACeAQAAAA==.',
Kr='Krezz:BAAANQAECgEIAQAAAA==.Krissylu:BAAANQAECgYIDgAAAA==.Krothix:BAABNQAECn83AAICAAkKMgfxTAAmAQACAAkKMgfxTAAmAQAAAA==.Krudd:BAAANQAECgcIDQAAAA==.Krychilly:BAAANQADCgcIEgAAAA==.Kryrande:BAAANQADCgQICwAAAA==.Kryshym:BAABNQAECn8cAAIJAAYKtiDiTAA2AgAJAAYKtiDiTAA2AgAAAA==.Krythrall:BAAANQADCgcIDAABNQAECgYIHAAJALYgAA==.Kryvelen:BAAANQAECgcIEAAAAA==.Krëëp:BAAANQAECggICAAAAA==.',
Ks='Kspectactle:BAAANQAECgMIBAAAAA==.',
Ku='Kuilei:BAAANQADCgYJCwABNQAECgIIBgAOAAAAAA==.Kurorø:BAAANQAECgMICgAAAA==.',
Ky='Kyrayna:BAAANQADCgYIEgAAAA==.',
['Kä']='Käisèr:BAAANQABCgEIAQAAAA==.',
La='Ladara:BAABNQAECn8oAAIUAAkKixQxBgBPAgAUAAkKixQxBgBPAgAAAA==.Laima:BAAANQADCgUICQAAAA==.Landil:BAAANQADCgYIDAAAAA==.Lavitz:BAAANQAECgEIAQAAAA==.',
Le='Leheo:BAAANQAECgEIAgAAAA==.Lehua:BAAANQADCggICgAAAA==.Leilanii:BAAANQADCgcIEQAAAA==.Lemook:BAABNQAECn8bAAIlAAkKjxKqGQCfAQAlAAkKjxKqGQCfAQAAAA==.Leonìdas:BAAANQADCggIGQAAAA==.Leð:BAAANQAECggICAAAAA==.',
Li='Licker:BAAANQAECgUICQABNQAFFAIIAwAOAAAAAA==.Life:BAAANQADCgQIBgAAAA==.Lightbulb:BAAANQADCgYIDQAAAA==.Lightsorrow:BAAANQAECgYICQABNQAECgoKKAAgAOkSAA==.Lightstormer:BAAANQADCgcIJQAAAA==.Lilamae:BAAANQAECgUIDQAAAA==.Lilarielle:BAABNQAECn80AAIkAAgK7QUyGQC6AAAkAAgK7QUyGQC6AAAAAA==.Lildookie:BAAANQAECgcIDgAAAA==.Lilface:BAAANQAECggIDAAAAA==.Lilhands:BAAANQAECgMIAwAAAA==.Liliel:BAAANQADCgMIAwABNQAECgkJFwADANsRAA==.Liliela:BAABNQAECn8XAAIDAAkK2xGuaABCAgADAAkK2xGuaABCAgAAAA==.Lilyannah:BAAANQADCgEIAQAAAA==.Liodragon:BAAANQADCgUIBQABNQAECgcICgAOAAAAAA==.Liolock:BAAANQAECggIBwAAAA==.Lite:BAAANQAECgQIBAAAAA==.Liø:BAAANQAECgcICgAAAA==.',
Ll='Lluniez:BAABNQAECn8ZAAIYAAkKZQ7+LgCgAQAYAAkKZQ7+LgCgAQAAAA==.',
Lm='Lmccoy:BAAANQABCgQIBAAAAA==.',
Lo='Lockroknroll:BAAANQAECggIEgAAAA==.Loissa:BAAANQAECggICAAAAA==.Losoli:BAABNQAECn85AAIJAAkKRh3EKwC4AgAJAAkKRh3EKwC4AgAAAA==.Lotor:BAAANQADCgYIBgAAAA==.Lowchin:BAAANQAECgQIBQAAAA==.',
Lu='Lupine:BAAANQADCgYIBgABNQAECgUIBQAOAAAAAA==.Lutherion:BAABNQAECn8xAAILAAoKBB5yAwCoAgALAAoKBB5yAwCoAgAAAA==.',
Ly='Lycemmas:BAABNQAECn8lAAIBAAoK1Ri8RQBKAgABAAoK1Ri8RQBKAgAAAA==.',
['Lï']='Lïo:BAAANQADCgYIBwABNQAECgcICgAOAAAAAA==.',
Ma='Macoun:BAABNQAECn8jAAIDAAkKDCL8JAADAwADAAkKDCL8JAADAwAAAA==.Magicshowers:BAABNQAECn83AAIXAAoKkyKsNwAZAwAXAAoKkyKsNwAZAwAAAA==.Manseed:BAAANQABCgQJBAAAAA==.Maple:BAAANQAECgUIBQAAAA==.Martei:BAACNQAFFH8TAAIkAAUKGBYaAQDrAAAkAAUKGBYaAQDrAAA1AAQKfywAAiQACgpWHTsHAO8CACQACgpWHTsHAO8CAAAA.Maríneth:BAAANQAECgMICgAAAA==.Mascara:BAAANQAECgYICwAAAA==.Maxe:BAAANQADCgIIAgAAAA==.',
Me='Memebait:BAAANQAECgUIBQAAAA==.Mementomori:BAAANQAECgEIAQAAAA==.Meowbae:BAAANQAECgUIBQABNQAECgQIBgAOAAAAAA==.Merce:BAAANQADCgcIBwABNQAECgkJFwADANsRAA==.Mercesdes:BAAANQADCgEIAQAAAA==.',
Mi='Midway:BAAANQAECgQIBgAAAA==.Minizee:BAAANQAECgEIAQAAAA==.Mirokushan:BAAANQADCggIJgABNQAECgMIAwAOAAAAAA==.Missfire:BAAANQAECgIIAwAAAA==.Misticlady:BAAANQAECgQIBgAAAA==.Mistrariel:BAAANQADCggICwABNQAECgoKGwAbAIQXAA==.Mizukì:BAAANQABCgQIBgAAAA==.',
Mo='Moluubar:BAABNQAECn8jAAMKAAoKphMHfgAgAgAKAAoKphMHfgAgAgALAAEKAABNOgAAAAAAAA==.Moradin:BAAANQADCgMIAwAAAA==.Mordemour:BAAANQAECgUICAAAAA==.',
Mu='Mufler:BAAANQABCgQIBQAAAA==.Mungo:BAAANQAECgcIDgAAAA==.Mushù:BAAANQAECgUICgABNQAECgoKLAAVAJsXAA==.',
My='Myfire:BAAANQADCgYIBgAAAA==.Myrell:BAAANQAECggICAAAAA==.Myrrh:BAAANQAECgYIDwAAAA==.',
Na='Nalik:BAAANQAECgYIDgAAAA==.Nanou:BAAANQAECgUIBwAAAA==.Nardiaun:BAAANQADCgYIBgAAAA==.Naturebait:BAAANQADCgQIBAABNQAECggILwACANUXAA==.',
Ni='Nicety:BAAANQAECgMIAwAAAA==.Nimravidae:BAABNQAECn8xAAIJAAkKtxeoJAAmAgAJAAkKtxeoJAAmAgAAAA==.Ninelives:BAAANQAECgUIDwAAAA==.Nitecrawler:BAAANQADCgQIBAAAAA==.Niteeye:BAAANQABCgIIAgABNQAECgoKOQAXAPQhAA==.Niteryu:BAAANQAECgEIAwABNQAECgoKOQAXAPQhAA==.',
No='Nolokkotal:BAABNQAECn8rAAIKAAoKbxgYNQD/AQAKAAoKbxgYNQD/AQAAAA==.Nospitfisty:BAAANQADCgQIBAAAAA==.Noxolon:BAABNQAECn8XAAMFAAgK4Q+IFABXAQAFAAgK4Q+IFABXAQAKAAEKAADYWwErAAAAAA==.',
Nr='Nreaf:BAACNQAFFH8IAAIIAAUK7QjxFQD/AAAIAAUK7QjxFQD/AAA1AAQKfygAAggACgrKE7uHABgCAAgACgrKE7uHABgCAAAA.',
Oi='Oili:BAACNQAFFH8QAAIWAAUKaxSsAQDqAAAWAAUKaxSsAQDqAAA1AAQKfzEAAxYACgruGdcHAG0CABYACgruGdcHAG0CABcABAoADs9zAdcAAAAA.',
Ol='Olarrick:BAAANQAECgQIBQABNQAFFAIIBQAKAH4TAA==.',
Oo='Oops:BAACNQAFFH8OAAIPAAUKjRtFEgAzAQAPAAUKjRtFEgAzAQA1AAQKf0AAAw8ACgrNIHERACEDAA8ACgrNIHERACEDABAAAQqwCrRuADMAAAAA.',
Or='Orcchopped:BAAANQADCgQIBAAAAA==.Ornstein:BAEANQAECgUIEAAAAA==.',
Ot='Ottuk:BAACNQAFFH8FAAIQAAIKFgmAGgCGAAAQAAIKFgmAGgCGAAA1AAQKfysAAhAACQrNIJMfAM4CABAACQrNIJMfAM4CAAAA.',
Pa='Padpaw:BAAANQAECgUJCAAAAA==.Pakraxes:BAABNQAECn8tAAIfAAkKnQ+bFQDyAQAfAAkKnQ+bFQDyAQAAAA==.Paksenarrion:BAABNQAECn8xAAIaAAkKtg8jFgBUAQAaAAkKtg8jFgBUAQAAAA==.Palehoof:BAAANQADCggIGgABNQAECgEIAQAOAAAAAA==.Pallywaya:BAABNQAECn8UAAMIAAoKwgs9XACjAQAIAAoKwgs9XACjAQAJAAkKgwV0oQB0AAAAAA==.Pandemonîum:BAAANQAECgQIBAABNQAECgoKGAAYAK0SAA==.Pandemônium:BAAANQADCgMIAwABNQAECgoKGAAYAK0SAA==.Pandemönium:BAABNQAECn8jAAQIAAgKeh0fVgCTAgAIAAgKUh0fVgCTAgAaAAIKzRxTUwCXAAAJAAIK8Ai7qgBjAAABNQAECgoKGAAYAK0SAA==.Pandemöniüm:BAABNQAECn8YAAMYAAoKrRI+FQCYAQAYAAkKBxE+FQCYAQAZAAEKfAzJMAAxAAAAAA==.Parts:BAAANQABCggIDwAAAA==.Patchington:BAAANQAECgMICgAAAA==.Pañdemönium:BAAANQAECgUICgABNQAECgoKGAAYAK0SAA==.',
Pe='Pedwyn:BAAANQAECgcIBwAAAA==.Pepperrjakk:BAAANQADCgEIAQAAAA==.Perck:BAAANQADCgYIBgAAAA==.Perrylee:BAAANQAECgQICwAAAA==.',
Ph='Philia:BAABNQAECn8XAAMKAAgKmRWwnADVAQAKAAgKFhKwnADVAQALAAMK9Rp5KwDdAAABNQAFFAQIEAADAMEXAA==.',
Pi='Pixelme:BAABNQAFFH8GAAIEAAIKcASBHwB4AAAEAAIKcASBHwB4AAAAAA==.',
Pl='Pleggster:BAAANQAECgYIDAAAAA==.',
Po='Pochula:BAAANQAECgUICwAAAA==.',
Pr='Primo:BAABNQAECn9TAAIJAAoKjxiiHABeAgAJAAoKjxiiHABeAgAAAA==.Protricity:BAABNQAECn8YAAMiAAoKUBaiJAALAgAiAAgKmBSiJAALAgAMAAcKvBSpowAqAQAAAA==.',
Ps='Psalms:BAAANQAECgQIAwABNQAECgQIBwAOAAAAAA==.Psychoprowla:BAABNQAECn83AAIiAAoKMRBrEwCUAQAiAAoKMRBrEwCUAQAAAA==.Psychozdrood:BAAANQAECgEIAQAAAA==.Psychozpally:BAAANQAECgQIBAAAAA==.',
['Pä']='Pändemönium:BAAANQAECgYIDQABNQAECgoKGAAYAK0SAA==.',
['Pæ']='Pæn:BAEBNQAECn8ZAAMQAAkKFRkbNgBPAgAQAAkKFRkbNgBPAgAmAAQK9BLHhQA8AAABNQAFFAMICgAIABUiAA==.',
Qu='Quantar:BAAANQADCgYIBgABNQAECggIDgAOAAAAAA==.Quickstab:BAAANQAECgQICAAAAA==.',
Ra='Ragana:BAAANQAECggIEQAAAA==.Rainger:BAAANQADCgMIAwAAAA==.Rallypaly:BAAANQADCgIIAgAAAA==.Ramthor:BAAANQAECgYICAAAAA==.Rancooll:BAAANQADCggIIgAAAA==.Rasniir:BAABNQAECn8vAAIlAAgK6RanIAAkAgAlAAgK6RanIAAkAgAAAA==.Rasputea:BAAANQABCgIIAgAAAA==.Ravenar:BAAANQAECgQIBAAAAA==.Ravenlash:BAAANQABCgcICwAAAA==.',
Re='Regna:BAACNQAFFH8RAAMKAAUK9yDvCwAHAQAKAAQK9yDvCwAHAQAFAAMKviJtAgDBAAA1AAQKfzEAAwoACgpnJSsbAEsDAAoACQqYJSsbAEsDAAUABQrfI1wQAKEBAAAA.Relkon:BAAANQADCgMIAwAAAA==.Remaked:BAACNQAFFH8oAAIhAAcKDBnbAACOAQAhAAcKDBnbAACOAQA1AAQKf0EAAiEACgpqISIEADsDACEACgpqISIEADsDAAAA.Requinix:BAABNQAECn86AAIDAAkKMxZYPQDsAQADAAkKMxZYPQDsAQAAAA==.Retro:BAAANQADCggIDgAAAA==.Reynmaker:BAAANQADCgQIBAAAAA==.',
Rh='Rhowyn:BAAANQADCgQICAAAAA==.',
Ri='Riptidez:BAAANQADCgYIBgAAAA==.Ririko:BAABNQAECn8xAAIMAAkKpQwESQCNAQAMAAkKpQwESQCNAQAAAA==.Ritzo:BAABNQAECn8uAAIFAAkKFhfXBgDGAQAFAAkKFhfXBgDGAQAAAA==.',
Ro='Robval:BAAANQABCgIIAgAAAA==.Rocksanne:BAAANQAECgQIBAAAAA==.Rooguee:BAAANQAECgIIAwAAAA==.',
Ru='Rukkis:BAABNQAECn8xAAMnAAoKzBpRDwCGAgAnAAkKhhpRDwCGAgAdAAgKDxcMKgBEAgAAAA==.Rukâ:BAAANQADCggIIwAAAA==.Rumi:BAABNQAECn9KAAIjAAoKRh7MAwAdAwAjAAoKRh7MAwAdAwAAAA==.',
Ry='Ryeekan:BAAANQAECggIDAAAAA==.Ryuma:BAAANQAECgYIDwAAAA==.Ryumar:BAAANQAECgMIAwAAAA==.',
Sa='Sabrosura:BAABNQAECn8gAAIaAAkKYRHlJwCfAQAaAAkKYRHlJwCfAQAAAA==.Saiyan:BAAANQADCgIIAgAAAA==.Salsinor:BAAANQADCgYICwAAAA==.Sanosagara:BAAANQAECggIBgAAAA==.Sathari:BAABNQAECn8xAAINAAkKdBDwFwB6AQANAAkKdBDwFwB6AQAAAA==.',
Sc='Schaden:BAAANQAECgQIBwAAAA==.Scripter:BAAANQADCgUIBgAAAA==.',
Se='Seijo:BAAANQAECgEJAQAAAA==.Sekk:BAABNQAECn87AAMIAAkKxxpZRgDlAQAIAAkKxxpZRgDlAQAaAAYKURUGGwAkAQAAAA==.Selecta:BAAANQAECgEIAQAAAA==.Selexi:BAAANQAECgQIBAAAAA==.Selithira:BAAANQAECgcIEwAAAA==.Sephylon:BAAANQADCgEIAQAAAA==.Sera:BAAANQADCgYICgAAAA==.',
Sh='Shabagnarang:BAAANQAECgQIDAABNQAECggIJQATALcaAA==.Shadeofdark:BAABNQAECn8dAAIoAAoK6Be7EQAyAgAoAAoK6Be7EQAyAgAAAA==.Shalasyr:BAAANQAECgEIAgAAAA==.Shaletaz:BAAANQABCgQIBgAAAA==.Shamwowee:BAAANQADCggILQAAAA==.Shamzee:BAACNQAFFH8IAAIBAAMKixIGEQDOAAABAAMKixIGEQDOAAA1AAQKfzoAAgEACgqlHacjANgCAAEACgqlHacjANgCAAAA.Shandalf:BAAANQAECgMIAwAAAA==.Sheyy:BAAANQAECgEIAQAAAA==.Shiftybonez:BAAANQADCgQIBQAAAA==.Shintok:BAAANQAECgQICwAAAA==.Shuddarun:BAACNQAFFH8VAAIDAAgKQhqrAQB0AgADAAgKQhqrAQB0AgA1AAQKfzkAAgMACgosJcQJAAcDAAMACgosJcQJAAcDAAAA.',
Si='Silverbakk:BAAANQABCgEIAQAAAA==.Simn:BAAANQAECgYICwAAAA==.Sindraesong:BAAANQAECgUJCQAAAA==.',
Sk='Skithiryx:BAAANQAECgQIBAABNQAECgoKMAANAPAaAA==.Skuldd:BAAANQAECgQIBAAAAA==.',
Sl='Slayvylora:BAAANQAECgQIBAABNQAFFAUIEwAPAKkTAA==.',
Sm='Smarte:BAAANQAFFAIIAwAAAA==.Smolderpally:BAAANQADCgYIBgAAAA==.',
Sn='Sneakymoth:BAAANQADCgUIBQABNQAECgcIFAAWANgVAA==.Snookums:BAABNQAECn8ZAAINAAgK4RZUGQBpAQANAAgK4RZUGQBpAQAAAA==.',
So='Soarin:BAAANQADCgQIBAAAAA==.',
Sp='Spicymaker:BAABNQAECn8kAAIKAAoKIBwHVQCLAgAKAAoKIBwHVQCLAgAAAA==.',
St='Starya:BAAANQAECgUICQAAAA==.Steelheart:BAAANQABCgQIBAAAAA==.Stolensøul:BAAANQABCggICwAAAA==.Stop:BAAANQAECgMIAwAAAA==.Strifewood:BAAANQAECgcIBgAAAA==.Stumper:BAABNQAECn8tAAIHAAoKTBT8IAB+AQAHAAoKTBT8IAB+AQAAAA==.',
Su='Suluna:BAAANQABCgQIBAABNQAECgoKUwABALQgAA==.Sux:BAAANQADCgMIAwAAAA==.',
Sy='Sybrina:BAABNQAECn8yAAIDAAkKORIFSADGAQADAAkKORIFSADGAQAAAA==.Sylvia:BAABNQAECn8lAAIXAAoKtxJNwwD+AQAXAAoKtxJNwwD+AQAAAA==.Syngeance:BAABNQAECn8cAAIDAAYKPwVcpADlAAADAAYKPwVcpADlAAAAAA==.Synèsterwolf:BAAANQAECggIDAAAAA==.',
['Sí']='Síf:BAAANQAECgEIAQAAAA==.',
Ta='Tadeusz:BAAANQAECgYICQAAAA==.Taelah:BAAANQAECggIAgAAAA==.Tamamò:BAAANQADCgYICAAAAA==.Tanglefoot:BAABNQAECn8gAAIKAAgKFhKHgAAaAgAKAAgKFhKHgAAaAgAAAA==.Tanleros:BAABNQAECn8cAAIJAAkK+xRyVwATAgAJAAkK+xRyVwATAgAAAA==.Taquítos:BAAANQADCgYICAAAAA==.Tasigur:BAAANQAECgQIBAABNQAECgoKMAANAPAaAA==.',
Te='Telana:BAAANQADCggILQAAAA==.Tentación:BAAANQADCggICAABNQAECgkJIAAaAGERAA==.Tequitos:BAAANQAECgcIEAAAAA==.',
Th='Theduk:BAABNQAECn8qAAMdAAoKIhOvIwDqAAAnAAoKiBIzHwDXAQAdAAkK4QqvIwDqAAAAAA==.Theduke:BAAANQAECgQIBAAAAA==.Theliria:BAAANQADCgYIBgAAAA==.Thorias:BAABNQAECn8ZAAIXAAgKKxtkjgBiAgAXAAgKKxtkjgBiAgAAAA==.',
To='Toira:BAAANQADCgUIBQAAAA==.Tomoko:BAAANQADCgYICQAAAA==.Torment:BAABNQAECn80AAIPAAkKxBk/FgDvAQAPAAkKxBk/FgDvAQAAAA==.',
Tr='Tristén:BAABNQAECn8cAAIDAAkKFhcoPQDtAQADAAkKFhcoPQDtAQAAAA==.Truvie:BAAANQADCgMIAwAAAA==.',
Tu='Tumbled:BAABNQAECn8VAAIXAAcKYhGF5QC+AQAXAAcKYhGF5QC+AQAAAA==.Tumbles:BAAANQADCgQIBQAAAA==.Tumni:BAAANQAECgYIEwAAAA==.',
Tw='Twinkletoes:BAAANQADCgYIBgAAAA==.',
['Tá']='Tángall:BAAANQABCgEIAQAAAA==.',
Ui='Ui:BAAANQADCgMIAwAAAA==.',
Ul='Ulnuk:BAABNQAECn87AAIBAAoKQhw+DAACAwABAAoKQhw+DAACAwAAAA==.Ulster:BAAANQADCgEIAQAAAA==.',
Un='Ungodly:BAABNQAECn8nAAImAAoK3BDJNwD3AQAmAAoK3BDJNwD3AQAAAA==.Unholyshan:BAAANQAECgIIAgABNQAECgMIAwAOAAAAAA==.Unidus:BAAANQAECgEIAgAAAA==.',
Uu='Uutr:BAAANQABCgEIAQAAAA==.',
Uv='Uvvolx:BAAANQADCgQICAAAAA==.',
Va='Vadka:BAAANQAECgQICgAAAA==.Vaeldrin:BAAANQAECgQIBQAAAA==.Vaha:BAAANQAECgIIBgAAAA==.Valkree:BAAANQAECgUIDgAAAA==.Valroc:BAAANQADCgYIDAAAAA==.Valsavis:BAABNQAECn83AAIjAAoKEiBABgC6AgAjAAoKEiBABgC6AgAAAA==.Valtier:BAAANQADCgMIAwAAAA==.',
Ve='Vellagosa:BAAANQAECgUIDAAAAA==.Vernice:BAAANQADCgYICwABNQAECgUICAAOAAAAAA==.Verulan:BAAANQAECgYIDgAAAA==.Vexidari:BAAANQAECgUICQABNQAFFAUIEwAPAKkTAA==.Vexomous:BAABNQAECn8eAAMRAAgKgBqrBQBbAgARAAgKgBqrBQBbAgAEAAQKDgdTWwC3AAABNQAFFAUIEwAPAKkTAA==.',
Vi='Viiolet:BAAANQAFFAEIAQAAAA==.',
Vo='Voidmayne:BAABNQAECn8uAAIIAAoKHRTjbQB5AQAIAAoKHRTjbQB5AQAAAA==.Vongogh:BAAANQADCgYICQAAAA==.Vonhelsing:BAAANQAECgQIBAAAAA==.',
Vy='Vynnara:BAAANQADCgEIAQAAAA==.Vyolent:BAAANQADCgYICwAAAA==.',
Wa='Wapello:BAAANQABCgcIDAAAAA==.Warnox:BAAANQAECgIIAgAAAA==.',
We='Weiand:BAABNQAECn8qAAMJAAcKLQx5jwBvAQAJAAcKLQx5jwBvAQAIAAcK4BQxjQA3AQAAAA==.Wevark:BAABNQAECn8WAAIKAAgKoQpqtQCXAQAKAAgKoQpqtQCXAQAAAA==.',
Wh='Whatami:BAABNQAECn8sAAMVAAoKmxedRgB/AgAVAAoKmxedRgB/AgAbAAIK4QyfXgBoAAAAAA==.Whiteknight:BAAANQADCgYICwABNQAECgoKLAAVAJsXAA==.Wholemilk:BAABNQAECn8VAAINAAYK8h5TJQAbAgANAAYK8h5TJQAbAgAAAA==.',
Wi='Wilhellena:BAABNQAECn8uAAIMAAoKCA5yewCnAQAMAAoKCA5yewCnAQAAAA==.Wilhellfu:BAAANQADCgMIAwAAAA==.Winariel:BAABNQAECn8bAAIbAAoKhBdLBQDGAgAbAAoKhBdLBQDGAgAAAA==.Witewalker:BAAANQADCgcICgAAAA==.',
Wr='Writhesoul:BAAANQABCgIIAgABNQAECgoKIwACAEIXAA==.Wroughtsoul:BAABNQAECn8fAAQZAAoKRgjEDwCBAQAZAAoKRgjEDwCBAQAYAAIKvQv9XgBkAAAhAAEKAADWLwA+AAAAAA==.Wrysoul:BAABNQAECn8jAAICAAoKQheANACmAgACAAoKQheANACmAgAAAA==.',
Wy='Wynston:BAAANQADCgEIAQAAAA==.Wyrmheart:BAAANQADCgIIAwAAAA==.',
Xa='Xaldred:BAABNQAECn8eAAIVAAoK7Qx5hQDYAQAVAAoK7Qx5hQDYAQABNQAECgoKNwAQAA4YAA==.Xandir:BAABNQAECn8eAAIaAAkKfhJuFwBGAQAaAAkKfhJuFwBGAQAAAA==.Xarhunt:BAAANQAECgMIBwAAAA==.',
Xe='Xenzia:BAAANQADCgcICwAAAA==.Xeracil:BAAANQADCgQIDQAAAA==.',
Xo='Xoric:BAABNQAECn8xAAIlAAoKlxjtCAC9AgAlAAoKlxjtCAC9AgAAAA==.',
Xy='Xyal:BAABNQAECn8kAAIMAAkKwxYOTQB9AQAMAAkKwxYOTQB9AQAAAA==.Xyp:BAAANQADCgYIBgABNQAECgYIDgAOAAAAAA==.',
Ya='Yamaya:BAAANQADCgYICwAAAA==.',
Yi='Yiago:BAAANQAECgMICQAAAA==.',
Yo='Youknow:BAAANQADCgcICwAAAA==.',
Za='Zaelia:BAAANQADCgEIAQAAAA==.Zary:BAAANQAECgMIAgABNQAECggIAgAOAAAAAA==.Zaxhdk:BAEANQADCgMIAwABNQAECgcIFgAJAOoSAA==.Zaxhpal:BAEBNQAECn8WAAIJAAcK6hIndgC1AQAJAAcK6hIndgC1AQAAAA==.',
Ze='Zenedy:BAAANQAECgQIBAABNQAECgUICAAOAAAAAA==.Zerrus:BAAANQAECgQIBAAAAA==.',
Zi='Zid:BAAANQAECgMIAwAAAA==.Ziny:BAAANQADCgUIBQAAAA==.Ziparoo:BAABNQAECn8tAAIWAAgKBgsWFQBaAQAWAAgKBgsWFQBaAQAAAA==.',
Zo='Zoenova:BAAANQAECggIAgAAAA==.',
Zr='Zraven:BAAANQADCgEIAQAAAA==.',
['În']='Îniquitous:BAAANQAECgUIDgAAAA==.',
['Ðê']='Ðêmønicßløøð:BAABNQAECn8lAAMmAAoK5BRhFwAYAgAmAAoK5BRhFwAYAgAQAAMKggrGsACQAAABNQAECgoKKwAKAG8YAA==.',
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
