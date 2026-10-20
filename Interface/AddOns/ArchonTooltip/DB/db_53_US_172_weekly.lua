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

local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','Warrior-Arms','Paladin-Protection','Paladin-Retribution','Warrior-Protection','Mage-Arcane','Shaman-Restoration','Unknown-Unknown','Druid-Balance','Druid-Restoration','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Guardian','Druid-Feral','Rogue-Subtlety','Evoker-Preservation','Priest-Shadow','DemonHunter-Havoc','Shaman-Elemental','Hunter-BeastMastery','Paladin-Holy','Warrior-Fury','Mage-Frost','DeathKnight-Blood','DemonHunter-Devourer','Priest-Holy','DemonHunter-Vengeance','Monk-Brewmaster','Monk-Windwalker','Rogue-Assassination','Evoker-Devastation','Hunter-Marksmanship','Shaman-Enhancement','Evoker-Augmentation','Rogue-Outlaw','Priest-Discipline','Monk-Mistweaver',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Acedk:BAABNQAECn8hAAMBAAkKoiEyGgDvAgABAAkKPCAyGgDvAgACAAUKdiAWRACyAQAAAA==.Aceslam:BAABNQAECn8YAAIDAAgKuiFKMwDzAgADAAgKuiFKMwDzAgABNQAECgkJIQABAKIhAA==.',
Ad='Adrador:BAABNQAECn8mAAMEAAkKBh2bAwDiAQAEAAgKZiCbAwDiAQAFAAUKVgsLIQHoAAAAAA==.Adrenaline:BAACNQAFFH8NAAIGAAUK6RswAgCJAQAGAAUK6RswAgCJAQA1AAQKfzcAAgYACgpAJHoCAI4DAAYACgpAJHoCAI4DAAAA.',
Ae='Aelik:BAABNQAECn8lAAIBAAYKmBnLaABuAQABAAYKmBnLaABuAQAAAA==.Aeolian:BAAANQADCgYIDgAAAA==.Aeru:BAAANQADCgQIBAAAAA==.',
Aj='Ajaila:BAAANQADCgQIBAAAAA==.',
Ak='Akueria:BAAANQADCgcIBwAAAA==.',
Al='Alayssa:BAABNQAECn8WAAIHAAkKSRcNCwAcAgAHAAkKSRcNCwAcAgAAAA==.Alda:BAAANQADCgYIFgAAAA==.Alemental:BAAANQAECggIDwAAAA==.Aleska:BAAANQAECgQIDwAAAA==.Allarius:BAAANQAECgQIBAAAAA==.Allevist:BAAANQADCgUICQAAAA==.Alo:BAABNQAECn8vAAIIAAoKGxXGPgBlAgAIAAoKGxXGPgBlAgABNQAECgEJAQAJAAAAAA==.',
Am='Amilee:BAAANQADCggIDwAAAA==.Amoondai:BAAANQADCgYICAAAAA==.Amoondrin:BAABNQAECn8eAAMKAAkKTAjhVwB2AQAKAAgK5wfhVwB2AQALAAEK3wPDewAnAAAAAA==.',
An='Analiya:BAAANQADCgQJBQAAAA==.Anatyr:BAAANQADCggIDgAAAA==.',
Ar='Aramathis:BAAANQAECgUIBQAAAA==.Araviin:BAAANQAECgUICAAAAA==.Arbor:BAAANQAECgQIBwAAAA==.Arcillias:BAAANQAECgQICwABNQAECgQICwAJAAAAAA==.Arilas:BAAANQAECgQICAABNQAECgQICwAJAAAAAA==.Arkanist:BAABNQAECn8cAAIHAAYK0wdhcgDYAAAHAAYK0wdhcgDYAAAAAA==.Arthia:BAAANQADCgYICQAAAA==.Arvidpally:BAAANQAECgQICwAAAA==.',
As='Ashesius:BAABNQAECn87AAQMAAoKUxmGBADhAgAMAAoKUxmGBADhAgANAAMKYQmcHgGHAAAOAAIKaxyHHgCHAAAAAA==.Ashmehameha:BAAANQAECgMIBAABNQAECgcIFgAOAPgMAA==.',
At='Atredes:BAAANQAECgYIDQAAAA==.',
Au='Auspex:BAABNQAECn8fAAIPAAgKJwihMQARAQAPAAgKJwihMQARAQAAAA==.',
Av='Avaryn:BAABNQAECn8aAAILAAkKiBbVHwAtAgALAAkKiBbVHwAtAgAAAA==.',
Ax='Aximlii:BAAANQADCgUICQAAAA==.',
Ba='Babs:BAAANQADCgcICwAAAA==.Badaracka:BAACNQAFFH8KAAIQAAUKlA4wAQCoAQAQAAUKlA4wAQCoAQA1AAQKfy0AAxAACgqUIbMDAGEDABAACgqUIbMDAGEDAA8ABQqrHKseAKoBAAAA.Badash:BAAANQAECgQIBAABNQAECgcIFgAOAPgMAA==.Bahamuth:BAABNQAECn80AAIFAAoKMxYKDAAjAgAFAAoKMxYKDAAjAgAAAA==.Bahamutsrage:BAAANQADCggIDgABNQAECgUICAAJAAAAAA==.Balder:BAAANQAECggIFQABNQAFFAQICgAJAAAAAQ==.Bandage:BAAANQAECgYIBgABNQAECggIHQARADkUAA==.Barbattos:BAACNQAFFH8NAAISAAUKCBbgBAAsAQASAAUKCBbgBAAsAQA1AAQKfzMAAhIACgpTIxUGAEgDABIACgpTIxUGAEgDAAAA.',
Bd='Bdyrk:BAAANQAECgcIDgABNQAFFAUICgAQAJQOAA==.',
Be='Bealzeboss:BAAANQADCgcICQAAAA==.Bexley:BAABNQAECn8pAAIEAAoK+BhrAgAjAgAEAAoK+BhrAgAjAgAAAA==.',
Bi='Biggerbunny:BAABNQAECn8ZAAITAAgK7BLqJQD/AQATAAgK7BLqJQD/AQAAAA==.Biglarry:BAAANQADCgMJBQAAAA==.Biianca:BAAANQADCgUICQAAAA==.',
Bl='Blacklok:BAAANQAECgIIBAABNQAECgoKMQAUALQlAA==.Blanne:BAAANQABCgIIAgAAAA==.Blargle:BAAANQAECgIIAwAAAA==.Blegh:BAACNQAFFH8HAAIFAAMKARnHFQABAQAFAAMKARnHFQABAQA1AAQKfyQAAgUACgoNILwvAAoDAAUACgoNILwvAAoDAAAA.Blessyaheart:BAAANQAECgUIDAABNQAECgcIFgAVAKAMAA==.Blincyto:BAAANQAECgEIAQAAAA==.Blinx:BAAANQAECgEIAgAAAA==.Bloodrake:BAABNQAECn8zAAIWAAoKGhjyKAB3AQAWAAoKGhjyKAB3AQAAAA==.Blueray:BAAANQADCgYIBgAAAA==.',
Bm='Bman:BAABNQAECn8XAAIDAAYKxhzKJAByAQADAAYKxhzKJAByAQAAAA==.',
Br='Braneour:BAABNQAECn8rAAMEAAgKvBNzJwCjAQAEAAgKvBNzJwCjAQAXAAYK1QcEswAYAQAAAA==.Bravisimo:BAAANQAECgIIAgAAAA==.Browel:BAABNQAECn8eAAINAAoKwxZkTgBpAgANAAoKwxZkTgBpAgAAAA==.',
Bu='Bubblfett:BAAANQAECgEIAQAAAA==.Bumm:BAAANQAECgMIAwAAAA==.',
Bz='Bzspy:BAABNQAECn8nAAMDAAoKpxcnYwBlAgADAAoKpxcnYwBlAgAYAAIK9ApMKwBZAAAAAA==.',
['Bë']='Bëar:BAAANQAECgEIAQAAAA==.',
Ca='Cabooselul:BAAANQAECgQIBAAAAA==.Calyptus:BAABNQAECn8iAAMMAAkKFgs5BADtAAAMAAkKFgs5BADtAAANAAEKTQ2krABDAAAAAA==.Capylaura:BAAANQAECgMIBgAAAA==.Caratine:BAAANQADCgcIDQAAAA==.Cassandrah:BAABNQAECn8vAAIHAAoK+ByEPAANAwAHAAoK+ByEPAANAwAAAA==.',
Ce='Celìa:BAAANQAECgYIDQAAAA==.',
Ch='Chillymage:BAAANQADCgcIBwAAAA==.Chpchop:BAAANQABCggIEQAAAA==.Christy:BAAANQADCgYIGwAAAA==.Chugg:BAABNQAECn8eAAIIAAcKdwaeQQDmAAAIAAcKdwaeQQDmAAAAAA==.',
Ci='Ciaphus:BAABNQAECn81AAQXAAoKwgmREQDIAQAXAAoKwgmREQDIAQAFAAgK6A+btwCvAQAEAAcKNgxENgA1AQAAAA==.Cinnamonster:BAAANQAECgQICgAAAA==.',
Cl='Clogs:BAAANQAECgUIBgAAAA==.',
Co='Coffeedemon:BAAANQAECgQIBgAAAA==.Coldslappins:BAAANQAECgMIAwABNQAECggIKwAEALwTAA==.Convalescent:BAAANQADCgYIBgAAAA==.Coragrr:BAAANQAECgIIAwAAAA==.',
Cr='Cracklepants:BAACNQAFFH8KAAIVAAUKaAlMEABoAQAVAAUKaAlMEABoAQA1AAQKfzkAAhUACgqTITQXAD0DABUACgqTITQXAD0DAAAA.Crashout:BAAANQAECgcICgAAAA==.',
Cu='Curtastrophe:BAABNQAECn8wAAIZAAoKOCEpAQCQAwAZAAoKOCEpAQCQAwAAAA==.Curticus:BAAANQADCgYIBgAAAA==.',
Da='Daelanos:BAABNQAECn8YAAIDAAgKIAtbrwCmAQADAAgKIAtbrwCmAQAAAA==.Dallas:BAAANQAECgYIBAAAAA==.Danorman:BAAANQADCgQIBAABNQAECgEIAgAJAAAAAA==.',
De='Deathisreal:BAAANQADCgEIAgABNQAECgMIAwAJAAAAAA==.Deathoof:BAABNQAECn8fAAQBAAgKKxQCHQABAQABAAgKKxQCHQABAQAaAAMK/hHKlwCuAAACAAEKGgWKtAArAAAAAA==.Demonblaze:BAAANQAECgIIBgAAAA==.Demonilla:BAABNQAECn8eAAIbAAoKhBOuHQBkAgAbAAoKhBOuHQBkAgAAAA==.Destro:BAABNQAECn8mAAINAAkKygsOfwDoAQANAAkKygsOfwDoAQAAAA==.',
Di='Dilaudyd:BAAANQADCgcICQAAAA==.Disbeleaf:BAAANQAECgYIEAAAAA==.Dishu:BAAANQABCgQIBAAAAA==.Dispel:BAAANQADCgYIBgAAAA==.Disputatious:BAAANQADCgQIBAAAAA==.',
Dn='Dntblink:BAAANQADCgUIBQAAAA==.',
Do='Dogaz:BAAANQADCgYIGwAAAA==.Dogsoldier:BAAANQADCgQIBAAAAA==.Donori:BAAANQADCgEIAQAAAA==.Doomphoenix:BAAANQADCggIDAAAAA==.',
Dr='Dragonias:BAAANQAECgQIDwAAAA==.Drakthorn:BAAANQADCggIFQAAAA==.Drinny:BAABNQAECn8nAAIcAAkKRAUROAAhAQAcAAkKRAUROAAhAQAAAA==.Dripington:BAABNQAECn8mAAMCAAoK7B2VFADoAgACAAoK7B2VFADoAgABAAEKAABp4AAzAAAAAA==.',
Ea='Earthangel:BAAANQAECgQIDQAAAA==.',
Ef='Efon:BAAANQADCgUIBQABNQAECgkJFgAHAEkXAA==.',
Ei='Eine:BAABNQAECn8uAAIWAAoK7BCzLgBkAQAWAAoK7BCzLgBkAQAAAA==.',
El='Eldergreen:BAAANQAECgYIEQAAAA==.Elfwine:BAAANQAECgQIDQAAAA==.Elindria:BAABNQAECn8xAAMUAAoKtCXCBACnAwAUAAoKbCXCBACnAwAdAAUKwSTeBABEAQAAAA==.Elminstir:BAABNQAECn8bAAIZAAgKoRf1CgAWAgAZAAgKoRf1CgAWAgAAAA==.Eluzhion:BAAANQADCgUICAAAAA==.Elysian:BAAANQAECgUICQAAAA==.',
Er='Erizhal:BAAANQABCgIIAgAAAA==.Eruptyon:BAAANQAECgEIAQABNQAECgkJJQAHACYgAA==.',
Es='Esabel:BAAANQAECgcIDgABNQAECgkJFgAHAEkXAA==.',
Ev='Eviae:BAAANQAECgQIDQAAAA==.Evillure:BAAANQAECgYICgAAAA==.',
Ex='Explanation:BAAANQADCgQIBAAAAA==.',
Fa='Falan:BAAANQAECgEIAQAAAA==.Farfins:BAAANQADCgYIBgAAAA==.',
Fe='Fedor:BAAANQAECggICAAAAA==.Feår:BAABNQAECn8VAAMNAAcKjwyP0gAkAQANAAUKyQuP0gAkAQAMAAIKGw4sWwBvAAAAAA==.',
Fi='Finley:BAAANQADCgQIBAAAAA==.Fixation:BAAANQABCgIIAgAAAA==.',
Fl='Flane:BAACNQAFFH8VAAIeAAYKERy+AQD2AQAeAAYKERy+AQD2AQA1AAQKfycAAx4ACgoUH+IFAPcCAB4ACgoUH+IFAPcCAB8AAQoAAEdkAE4AAAAA.Flexdruid:BAAANQAECgUIBQAAAA==.',
Fr='Fragil:BAABNQAECn8kAAMgAAoKeBw2FwDCAgAgAAoK7xs2FwDCAgARAAQKAxVSNQAPAQAAAA==.Frostmane:BAAANQAECgUIBQABNQAFFAUICgAVAGgJAA==.',
Ga='Galena:BAAANQAECgQIDwAAAA==.Galian:BAAANQADCggIEgAAAA==.Ganonn:BAAANQAECgQICQABNQAECgYIEAAJAAAAAA==.',
Ge='Geshtal:BAABNQAECn8UAAMUAAgKFwtoEwBPAQAUAAgKFwtoEwBPAQAdAAEKAAAcNAAsAAAAAA==.',
Gi='Girion:BAAANQAECgQIDQAAAA==.',
Gl='Glaiven:BAECNQAFFH8JAAIUAAUKlhKMCwBnAQAUAAUKlhKMCwBnAQA1AAQKfzEAAxQACgq/HpAOADEDABQACgq/HpAOADEDABsABwoxFzoxALcBAAAA.Glyr:BAAANQAECgEJAQAAAA==.',
Gn='Gnora:BAAANQADCggIDwAAAA==.',
Go='Gorgrin:BAAANQAECgQICQAAAA==.',
Gr='Groguu:BAAANQAECgQIBAABNQAECgkJIQABAKIhAA==.',
Ha='Harkanum:BAABNQAECn8sAAMhAAgKSAq+HACBAQAhAAgKSAq+HACBAQASAAgK6QQ1KwBSAQAAAA==.Harvester:BAAANQAECgQICgAAAA==.',
He='Healinturds:BAAANQADCgEIAQAAAA==.Helloagain:BAABNQAECn8WAAIHAAkK3RucfgCBAgAHAAkK3RucfgCBAgAAAA==.',
Hi='Hidethetotem:BAAANQAECgYIEgAAAA==.Hikari:BAACNQAFFH8JAAIFAAQKwQpRGwDOAAAFAAQKwQpRGwDOAAA1AAQKfyQAAgUACgqfHb5TAJoCAAUACgqfHb5TAJoCAAAA.Hiown:BAAANQABCgYICAAAAA==.',
Ho='Holyrebel:BAAANQAECgEIAQABNQAECgMIAwAJAAAAAA==.Holyspike:BAAANQAECgQIDwAAAA==.Homerr:BAAANQAECgQIDgAAAA==.Honiahaka:BAABNQAECn81AAIWAAoKzgzzEwDTAQAWAAoKzgzzEwDTAQAAAA==.Hotsdog:BAAANQADCgIIAgAAAA==.Hottcakes:BAABNQAECn81AAIHAAkKAiMlDwCWAwAHAAkKAiMlDwCWAwABNQAFFAgIFwANADMTAA==.',
Hu='Humanoidlite:BAAANQAFFAEIAgABNQAFFAMICAADAP0JAA==.Humanoidlock:BAAANQADCgYIDAABNQAFFAMICAADAP0JAA==.Humanoidwar:BAACNQAFFH8IAAMDAAMK/QlrDADNAAADAAMK/QlrDADNAAAGAAEKoAP3CgAtAAA1AAQKfyoAAwMACgoIHi40APACAAMACgoIHi40APACAAYABQr+D50pAO4AAAAA.',
['Hà']='Hàvòc:BAAANQADCgQIBAAAAA==.',
['Hö']='Hölyçow:BAAANQADCgUIBQAAAA==.',
Ic='Icedtea:BAAANQAECgQIBAAAAA==.',
In='Inoru:BAAANQAECgQIBwAAAA==.',
Ip='Ipseity:BAAANQABCgMIAwAAAA==.',
Ir='Irmaline:BAAANQAECgQIDwAAAA==.',
It='Ithurtshuh:BAAANQAECgIIBQABNQAECgMIAwAJAAAAAA==.',
Ja='Jabbawockie:BAABNQAECn8XAAIUAAgKFwhqYwDsAAAUAAgKFwhqYwDsAAAAAA==.Jackcat:BAAANQADCgQIAwAAAA==.Jackyl:BAAANQABCgYIBgAAAA==.',
Je='Jeffee:BAABNQAECn8hAAICAAgKgxnaEgBwAQACAAgKgxnaEgBwAQAAAA==.Jennifleur:BAAANQADCgcIBwAAAA==.Jequalsjosh:BAABNQAECn8YAAIgAAkKCBE8NQAFAgAgAAkKCBE8NQAFAgAAAA==.Jerk:BAACNQAFFH8WAAIbAAYKViK+BADxAQAbAAYKViK+BADxAQA1AAQKfzIAAhsACgpFJTgEAJIDABsACgpFJTgEAJIDAAAA.Jesper:BAABNQAECn87AAIIAAoKKx6fEgA0AwAIAAoKKx6fEgA0AwAAAA==.Jetz:BAAANQAECgQICQAAAA==.Jezelle:BAAANQADCggICAAAAA==.',
Ji='Jilara:BAAANQAECgUIEwAAAA==.Jimmyjim:BAAANQAECgQICwAAAA==.',
Jo='Joink:BAAANQADCgYICQAAAA==.',
Jp='Jpepps:BAABNQAECn8mAAMNAAgK2A0tigDNAQANAAgK2A0tigDNAQAMAAMKcAThXgBoAAAAAA==.',
Jr='Jrose:BAAANQADCggIGQAAAA==.',
Ka='Kagozo:BAEANQAECgEIAQABNQAECgIIAgAJAAAAAA==.Kahlanrahl:BAAANQADCgIIAgAAAA==.Kaiatra:BAAANQAECgQIDwAAAA==.Kalamor:BAAANQAECgUIBQAAAA==.Kaliguala:BAAANQADCgMIAwAAAA==.Kaloran:BAAANQAECgYIDQAAAA==.Katalaystar:BAAANQADCgYIDAABNQAECgoKMgALAIQgAA==.Katalegdh:BAAANQAECgQICQAAAA==.Kative:BAAANQADCgUICAAAAA==.Kaìju:BAABNQAECn8aAAIFAAcKeiDyewAzAgAFAAcKeiDyewAzAgAAAA==.',
Ke='Kellytgt:BAAANQAECgYIBgAAAA==.',
Kh='Khaelyn:BAAANQADCgQIBQAAAA==.Khai:BAABNQAECn8VAAIFAAgKUw1X4ABbAQAFAAgKUw1X4ABbAQAAAA==.',
Ki='Kiae:BAAANQADCgYJBwAAAA==.Kidneyspears:BAAANQADCgYICAAAAA==.Kilaura:BAAANQADCgUIBQAAAA==.Kilmandaros:BAAANQAECgUIBgAAAA==.Kimblee:BAAANQADCgQIBAAAAA==.',
Ko='Korbix:BAAANQABCgUIBAABNQAECgUICwAJAAAAAA==.',
Kr='Kronmon:BAAANQADCgQIBAAAAA==.',
Ku='Kudria:BAABNQAECn8bAAIWAAgK/hMbigD2AQAWAAgK/hMbigD2AQAAAA==.Kunei:BAAANQABCgYICQABNQAECgEIAgAJAAAAAA==.Kurdran:BAAANQABCgQIAgAAAA==.Kuroyukihime:BAABNQAECn8qAAIZAAkKoxrPAQDmAQAZAAkKoxrPAQDmAQAAAA==.',
Ky='Kylas:BAAANQADCgUICAAAAA==.Kynae:BAAANQAECgQIEQAAAA==.Kyross:BAAANQABCgIIAgAAAA==.',
['Ká']='Kárma:BAAANQADCgYICwABNQAECgcIFQANAI8MAA==.',
La='Lashela:BAABNQAECn8cAAIiAAYKmQdpHQCpAAAiAAYKmQdpHQCpAAAAAA==.Laughter:BAAANQAECgQICgAAAA==.Lavamylash:BAAANQAECgYIEAAAAA==.Laylla:BAAANQAECgQICgAAAA==.Lazulie:BAAANQAECgQICAAAAA==.',
Le='Lefnedrav:BAAANQADCgYICgABNQAECgkJGwAEABkTAA==.Lektrik:BAAANQAECgUICAAAAA==.Lenexa:BAAANQADCgUICAAAAA==.Lexapayne:BAAANQADCgEIAQABNQAECggIGAAWALoPAA==.Leyra:BAABNQAECn8fAAIiAAkKnxaPAwDgAQAiAAkKnxaPAwDgAQABNQAECgoKMQAUALQlAA==.',
Li='Lighthammer:BAAANQADCggIDgAAAA==.Lightmessiah:BAABNQAECn8hAAMFAAkKVRqsfgAsAgAFAAgKERmsfgAsAgAXAAcKhBL6GQCLAQAAAA==.Lightnig:BAAANQADCgUIBQAAAA==.Lilyvain:BAAANQAECgEIAQAAAA==.Lireal:BAABNQAECn8gAAMXAAoKKx7MIwDcAgAXAAkKNB3MIwDcAgAFAAEKKAwA/wAxAAAAAA==.Livnod:BAAANQADCggIDgAAAA==.',
Lo='Lonon:BAABNQAECn8XAAIVAAgKJA5tcwDHAQAVAAgKJA5tcwDHAQAAAA==.Loosescrew:BAAANQADCgQIBQAAAA==.Lorine:BAABNQAECn8uAAIEAAoK3RhyEACWAgAEAAoK3RhyEACWAgAAAA==.',
Lu='Lunara:BAAANQADCgYIDAAAAA==.',
Ly='Lynnethe:BAAANQAECgYIDgAAAA==.',
Ma='Malkiel:BAAANQAECgQIDgAAAA==.Mantang:BAAANQABCgIIAgAAAA==.Mastakillah:BAAANQADCgQICAABNQAECgUIEQAJAAAAAA==.Maxamus:BAAANQADCgQIBgAAAA==.',
Me='Meeseeks:BAAANQAECgcIDQAAAA==.Merckel:BAABNQAECn8xAAIbAAoKkBtREADvAgAbAAoKkBtREADvAgAAAA==.Messorom:BAAANQADCgEIAQAAAA==.',
Mi='Michello:BAAANQAECgQIDwAAAA==.Mightytot:BAAANQADCgcIDQAAAA==.Millia:BAABNQAECn8lAAMHAAkKJiDtFQC7AQAHAAcK8yDtFQC7AQAZAAIKJh6rKQCqAAAAAA==.Mint:BAABNQAECn8fAAIXAAkKGBW5QgBaAgAXAAkKGBW5QgBaAgAAAA==.Mintberrytea:BAAANQAECgQJBAABNQAECgkJHwAXABgVAA==.Misstress:BAABNQAECn8gAAMKAAkKXgmsUACaAQAKAAkKXgmsUACaAQAPAAEKAABzcAAdAAAAAA==.',
Mo='Moistweaver:BAAANQADCgYIBgAAAA==.Monoxide:BAAANQADCgUIBQABNQAECgcIFgAjAD4MAA==.Mooncloud:BAAANQADCggICQAAAA==.Moonhunt:BAAANQAECgQIBAAAAA==.Morkleb:BAAANQAECgUICwAAAA==.Morrag:BAABNQAECn8bAAINAAYKHgpKWQDPAAANAAYKHgpKWQDPAAAAAA==.Morrtisha:BAAANQAECgcIDAAAAA==.',
Mu='Munchkins:BAAANQABCgcIDQAAAA==.Munden:BAAANQADCgUIBQABNQAECgQIDgAJAAAAAA==.',
My='Myxie:BAABNQAECn8gAAIIAAcK5hXaJABRAQAIAAcK5hXaJABRAQAAAA==.',
['Mí']='Mísfìt:BAABNQAECn8wAAIIAAoKpB3BIwDXAgAIAAoKpB3BIwDXAgAAAA==.',
Na='Nakaito:BAAANQAECgYIEQABNQAECgkJJwAgAFAPAA==.Narcoleptic:BAABNQAECn8zAAQSAAoKWxSHEgCEAgASAAoKWxSHEgCEAgAhAAUKzQuYJgABAQAkAAQKLxFxCQBzAAAAAA==.Nashty:BAAANQADCgIIAgAAAA==.Naturaljuice:BAAANQAECggICwABNQAFFAgIFwANADMTAA==.Naturebreakr:BAABNQAECn8XAAIKAAkKExC+PQAKAgAKAAkKExC+PQAKAgAAAA==.',
Ne='Nex:BAABNQAECn8sAAIHAAoKDiGKBACaAgAHAAoKDiGKBACaAgAAAA==.',
Ni='Nightsawdy:BAABNQAECn8YAAIWAAYK7RT0owC+AQAWAAYK7RT0owC+AQAAAA==.Niightstorm:BAAANQAECgQIDAAAAA==.Nilvannas:BAAANQADCggICAAAAA==.Nitefire:BAAANQADCgYIGgAAAA==.Nitélifé:BAAANQAECgUIBgAAAA==.',
Of='Offspring:BAAANQABCgIIAgAAAA==.',
Om='Omora:BAABNQAECn8bAAQEAAkKGRONBADCAQAEAAkKGRONBADCAQAXAAYKWgm5rwAgAQAFAAIKmwwfcgFrAAAAAA==.',
Op='Opalinnas:BAABNQAECn8yAAILAAoKhCBUCABAAwALAAoKhCBUCABAAwAAAA==.Optimism:BAAANQADCgIIAgAAAA==.',
Pa='Paladrone:BAAANQABCggIDwABNQADCgcICgAJAAAAAA==.Palestrina:BAAANQADCgMIAwAAAA==.Pallyandtank:BAAANQAECgEIAQAAAA==.Panzer:BAABNQAECn8kAAIPAAcKhhQ3DwAYAQAPAAcKhhQ3DwAYAQAAAA==.Parts:BAABNQAECn8dAAQRAAgKORRgEgBDAQAgAAYKwg+MUAB8AQARAAUKCxlgEgBDAQAlAAMK0gpNFQCbAAAAAA==.Passionfruit:BAAANQAECgcIBwAAAA==.Paul:BAAANQAECgUICgAAAA==.',
Pe='Peachtea:BAAANQAECgYICwAAAA==.Pepecojon:BAAANQADCggIDwAAAA==.',
Pi='Piebaby:BAAANQADCgUIBgAAAA==.Pirodeath:BAAANQAECgYICAAAAA==.',
Pl='Plovdiv:BAAANQADCgcJCQAAAA==.',
Po='Poah:BAAANQAECgYIBgAAAA==.',
Pr='Pray:BAABNQAECn81AAMcAAoKTyQeAgBXAwAcAAoK6SEeAgBXAwAmAAgKMiR5AQA5AwAAAA==.Prodarkangel:BAAANQADCgcJCQAAAA==.',
Pu='Puckllane:BAAANQAECgEIAgAAAA==.Punkin:BAAANQADCggIEwAAAA==.',
Py='Pyre:BAABNQAECn8jAAMmAAkKjw2VCgCeAQAmAAgKWg2VCgCeAQAcAAQKdQoBTgDeAAABNQAECgEJAQAJAAAAAA==.',
['Pü']='Püff:BAAANQADCgEIAQABNQAECgQICwAJAAAAAA==.',
Qu='Quanah:BAABNQAECn8bAAIIAAcKriCSCAA5AgAIAAcKriCSCAA5AgAAAA==.Quivver:BAAANQADCgYIGAAAAA==.',
Ra='Rabmaxx:BAABNQAECn8bAAIUAAkKWQTuVwAqAQAUAAkKWQTuVwAqAQAAAA==.Raina:BAAANQADCgYIBgAAAA==.Rap:BAAANQAECgMIAwAAAA==.Ravenlight:BAACNQAFFH8FAAIFAAQKDwaRCgC/AAAFAAQKDwaRCgC/AAA1AAQKfyMAAgUACgqbFVJ1AEMCAAUACgqbFVJ1AEMCAAAA.Ravenwynnd:BAABNQAECn8uAAMDAAoKeB5SHQBCAwADAAoKeB5SHQBCAwAGAAYKFh23FQDMAQAAAA==.Raynman:BAABNQAECn8uAAIVAAoKzBJZBgAGAgAVAAoKzBJZBgAGAgAAAA==.',
Re='Restotuition:BAAANQABCgQICAABNQAFFAUIDQAcABkcAA==.Reylariel:BAAANQADCgMIAwAAAA==.',
Rh='Rhydian:BAAANQADCgQIBAAAAA==.Rhyzer:BAAANQAECgQIDQAAAA==.',
Ri='Riiver:BAAANQADCgYIBgAAAA==.',
Ro='Roderick:BAAANQADCggIEAAAAA==.Root:BAABNQAECn8gAAIPAAoKeyUsAAB/AwAPAAoKeyUsAAB/AwAAAA==.',
Ru='Rubmytotem:BAAANQAECgYICwAAAA==.',
Sa='Sabazia:BAABNQAECn8rAAIaAAgKHxPfSADUAQAaAAgKHxPfSADUAQAAAA==.Sabelinå:BAAANQAECgEIAgAAAA==.Sable:BAAANQADCgEIAQAAAA==.Sacred:BAAANQAECgcIDQAAAA==.Saerise:BAAANQADCggIDgAAAA==.Sairalindë:BAAANQAECgYIDQAAAA==.Salamandra:BAAANQADCggIGQABNQAECgkJGwAEABkTAA==.Saleath:BAAANQAECgIIAgAAAA==.Salios:BAAANQAECgEIAQAAAA==.Sanara:BAAANQABCgUIBwABNQAECgQIDQAJAAAAAA==.Sanctifier:BAAANQADCgUIBQAAAA==.',
Sc='Scrept:BAAANQAECggICgAAAA==.Scynix:BAEBNQAECn8cAAMSAAgKvQkhJwCAAQASAAgKvQkhJwCAAQAkAAcKRQzADQBwAQAAAA==.',
Se='Sedaline:BAAANQAECgEIAQAAAA==.Seizuregoat:BAAANQAECgMJAwAAAA==.Senus:BAAANQADCgEIAQAAAA==.Servoker:BAAANQAECgcICwAAAA==.',
Sh='Shabzyt:BAABNQAECn8VAAMBAAgKrRddUADSAQABAAcK6hldUADSAQACAAUKnQ1pOAC/AAAAAA==.Shaienne:BAAANQADCgcIDgAAAA==.Shammander:BAAANQAECgUICgAAAA==.Shamrockshak:BAAANQAECgIIBAAAAA==.Shamron:BAAANQADCgcICgAAAA==.Shenuton:BAAANQAECgYIEAAAAA==.Shieldbash:BAABNQAECn86AAIGAAoKwCH9AADNAwAGAAoKwCH9AADNAwAAAA==.Shockthêràpy:BAABNQAECn8lAAMIAAkKhSCvHgDwAgAIAAkKhSCvHgDwAgAVAAEKzw4lMgE3AAAAAA==.Shoes:BAAANQAECgYICgAAAA==.Shtdruid:BAAANQAECgEIAQAAAA==.',
Si='Sibearian:BAAANQAECgUIDgABNQAECggIHwABACsUAA==.Sibeson:BAABNQAECn8YAAMOAAcK4xKrBAAFAQANAAcKMgqurgB0AQAOAAQKJxurBAAFAQABNQAECggIHwABACsUAA==.Simi:BAABNQAECn8YAAIWAAgKug+cgQAJAgAWAAgKug+cgQAJAgAAAA==.',
Sm='Smithnwesson:BAAANQABCgcICgAAAA==.Smokesçreen:BAABNQAECn8nAAMdAAgKXBEMDwDGAQAdAAgKXBEMDwDGAQAUAAcKKQlqTwBcAQAAAA==.',
So='Soonerpride:BAABNQAECn8YAAIFAAgKCyPKWQCKAgAFAAgKCyPKWQCKAgAAAA==.Soothed:BAAANQADCggICAAAAA==.',
Sp='Spearminttea:BAAANQADCgIIAgAAAA==.Spellbreakr:BAACNQAFFH8HAAIHAAMK4AWZPgDAAAAHAAMK4AWZPgDAAAA1AAQKfx8AAgcACgp8HZtnAK8CAAcACgp8HZtnAK8CAAAA.Spirtbreaker:BAAANQAECgYIDgAAAA==.',
Sq='Squeak:BAAANQADCgUICQAAAA==.Squiby:BAABNQAECn8xAAMTAAoKxSLrBQB5AwATAAkKayLrBQB5AwAcAAIKexHBlgA5AAAAAA==.',
St='Stankowitz:BAAANQABCgQICAABNQADCgYIBgAJAAAAAA==.Starboi:BAAANQADCgUIBQAAAA==.Starce:BAAANQABCgMIAwAAAA==.Steveirwin:BAAANQADCgYICgAAAA==.Stheris:BAABNQAECn8cAAIgAAoKZw+eMAAfAgAgAAoKZw+eMAAfAgAAAA==.Stuefester:BAABNQAECn8UAAMaAAcKTyAFPAATAgAaAAcKIh0FPAATAgABAAcK9x1AWgCnAQAAAA==.',
Sv='Sveika:BAAANQAECgQIDwAAAA==.',
Sy='Sylaria:BAEANQADCggIEAAAAA==.Syreline:BAAANQAECgMIAwAAAA==.',
['Sï']='Sïn:BAABNQAECn8ZAAINAAcK+B7EYgAxAgANAAcK+B7EYgAxAgAAAA==.',
['Sý']='Sýlver:BAABNQAECn8aAAIKAAcKNwxcUQCXAQAKAAcKNwxcUQCXAQAAAA==.',
Ta='Tarathiel:BAAANQADCgIIAgAAAA==.Tarpalantir:BAAANQADCgcICAAAAA==.Taurne:BAABNQAECn8vAAMLAAkKShqzFgCNAgALAAkKShqzFgCNAgAKAAMKiQX6lwB5AAAAAA==.',
Tc='Tchnce:BAAANQADCgcICgAAAA==.',
Te='Teknoman:BAABNQAECn8tAAMDAAgKlBiIcABCAgADAAgKlBiIcABCAgAGAAEKBwWNSgAgAAAAAA==.Telephone:BAAANQAECgEIBQAAAA==.Tempered:BAABNQAECn8cAAIDAAgKXRFglADpAQADAAgKXRFglADpAQABNQAECggIHQARADkUAA==.Teresen:BAAANQADCgIIAgAAAA==.',
Th='Thaitea:BAAANQADCgIIBAAAAA==.Thalindra:BAAANQAECgQIDQAAAA==.Tharain:BAAANQAECgQIBQAAAA==.Thebigbeast:BAAANQAECgUIDgABNQAFFAgIFwANADMTAA==.Thecurt:BAABNQAECn81AAIeAAoKYiJzAADQAgAeAAoKYiJzAADQAgAAAA==.Thunderrbutt:BAABNQAECn8WAAIVAAcKoAw3kgB3AQAVAAcKoAw3kgB3AQAAAA==.Thyralizen:BAAANQADCgQIBQAAAA==.',
Ti='Tiael:BAAANQAECgIIAgAAAA==.Timaeus:BAAANQADCggIGgAAAA==.Tinylef:BAABNQAECn8mAAQfAAgKpxePJwDlAQAfAAcKpxePJwDlAQAnAAYKXhH7CABJAQAeAAEKAABALwBDAAABNQAECgkJGwAEABkTAA==.Tirouke:BAAANQAECgMIBAAAAA==.Titanlock:BAAANQADCgcIDQAAAA==.',
Tk='Tkdfath:BAAANQADCgYIBgAAAA==.',
To='Toralina:BAAANQAECgEIAQAAAA==.Torvia:BAAANQADCggIDwAAAA==.',
Tr='Trisinz:BAAANQAECgUICgAAAA==.',
Tu='Tuerto:BAABNQAECn8ZAAIWAAkKqA+ADQAGAgAWAAkKqA+ADQAGAgAAAA==.Tuiarmstrong:BAAANQAECgUIDwABNQAFFAUIDQAcABkcAA==.Tuipasteur:BAACNQAFFH8NAAIcAAUKGRxUBwBlAQAcAAUKGRxUBwBlAQA1AAQKfyoABBwACgrgHisjAOECABwACgrgHisjAOECACYAAgriCqkfAGQAABMAAgpiFXQuAEIAAAAA.Tuithexiv:BAAANQAECgcIDwABNQAFFAUIDQAcABkcAA==.Turbojohnson:BAAANQAECgEIAQAAAA==.Turk:BAABNQAECn86AAIbAAoKgRSODgBAAQAbAAoKgRSODgBAAQAAAA==.Turkish:BAABNQAECn8mAAICAAoKSA3vCQC9AQACAAoKSA3vCQC9AQAAAA==.',
Tw='Twinkytoes:BAAANQADCggIEwAAAA==.',
Ty='Tychaa:BAAANQADCgYIEgAAAA==.Tylat:BAAANQABCgMIAwAAAA==.Tyranax:BAABNQAECn8tAAIcAAgKZR2gDAAdAgAcAAgKZR2gDAAdAgAAAA==.Tyrith:BAAANQADCgQIBQAAAA==.',
Ui='Uintah:BAAANQAECgUIDAAAAA==.',
Ul='Ullyr:BAACNQAFFH8HAAIKAAQKkAfnCADKAAAKAAQKkAfnCADKAAA1AAQKfyUAAwoACgrNG/oBAJ8CAAoACgrNG/oBAJ8CABAAAQoAAJVOABkAAAE1AAUUBQgKABUAaAkA.',
Us='Userdel:BAABNQAECn8dAAIIAAYKXwiYYQCUAAAIAAYKXwiYYQCUAAAAAA==.',
Va='Vadose:BAAANQADCgYIBgABNQAECggIGAAWALoPAA==.Valytrois:BAAANQAECgEIAQAAAA==.Variant:BAAANQAECgMIAwAAAA==.Varinix:BAAANQADCgUICAAAAA==.Vauld:BAAANQADCgQJBQAAAA==.',
Ve='Veiksla:BAAANQADCgYIGgAAAA==.Vengerr:BAAANQADCgYIFQAAAA==.Verace:BAAANQAECggIAQAAAA==.Verradic:BAAANQAECgUICAAAAA==.',
Vi='Vilanelle:BAAANQABCgUIBwAAAA==.Vitur:BAABNQAECn84AAIbAAkKxCN1AwChAwAbAAkKxCN1AwChAwAAAA==.Vivi:BAAANQADCgYIBgAAAA==.',
Vo='Voidbunny:BAAANQAECgYJDwAAAA==.Volaine:BAAANQAECgQICwAAAA==.Volgar:BAAANQADCgUICQAAAA==.Volition:BAAANQADCgYIBgAAAA==.Volt:BAABNQAECn8gAAIjAAgKlBkpEABmAgAjAAgKlBkpEABmAgABNQAECgkJJgANAMoLAA==.',
Vr='Vrye:BAABNQAECn8cAAIbAAkKQwTnSwD6AAAbAAkKQwTnSwD6AAAAAA==.',
Vy='Vynaeda:BAABNQAECn8UAAIHAAcKEhSc6gC1AQAHAAcKEhSc6gC1AQAAAA==.',
['Vô']='Vôx:BAAANQAECgIIBQABNQAECgcIDAAJAAAAAA==.',
Wa='Wakko:BAAANQADCgcIEwAAAA==.Walkure:BAAANQADCgYIHAAAAA==.',
We='Weirdscience:BAAANQABCgQIBAAAAA==.Wetasstotem:BAABNQAECn8XAAIVAAoK5BzkKwDPAgAVAAoK5BzkKwDPAgABNQAFFAgIFwANADMTAA==.',
Wh='Whew:BAAANQADCggICQAAAA==.',
Wi='Widge:BAAANQAECgQIBAAAAA==.Wikker:BAAANQADCgQIBAAAAA==.',
Wo='Worldlight:BAAANQADCgIIAgAAAA==.',
Wr='Wreckbums:BAAANQAECgMIBAAAAA==.Wreckd:BAAANQAECgYICwABNQAECggIHQARADkUAA==.Wrongway:BAAANQADCgQIBQAAAA==.',
Xa='Xanthad:BAAANQADCgUICAAAAA==.',
Xb='Xb:BAAANQADCgYIFgAAAA==.',
Xi='Xitãozinho:BAAANQAECgMIAwAAAA==.',
Xy='Xyomi:BAAANQADCgIIAgAAAA==.',
Ya='Yaalia:BAAANQAECgQIDQAAAA==.Yaan:BAAANQAECggIDgAAAA==.Yalane:BAAANQAECgMIAwAAAA==.',
Za='Zain:BAAANQADCgYIBgABNQAECgoKOwAMAFMZAA==.Zalaan:BAAANQAECgYIEQABNQAECgkJFgAHAEkXAA==.Zandibar:BAAANQAECgQIDQAAAA==.Zaptoasted:BAAANQADCgYIBgAAAA==.Zariea:BAAANQAECgIIAgABNQAECgcIJQABAJgZAA==.Zavac:BAAANQADCgUIBwAAAA==.',
Ze='Zellezugtail:BAAANQADCgYIBgABNQAECgQIDgAJAAAAAA==.Zelritch:BAAANQADCggICAAAAA==.',
Zi='Zinfandell:BAAANQAECgUICwAAAA==.',
Zo='Zorrloc:BAAANQADCgQIBAAAAA==.',
Zu='Zuggie:BAAANQAECgQIDgAAAA==.Zugtail:BAAANQAECgEIAQABNQAECgQIDgAJAAAAAA==.Zurtrinik:BAAANQAECgUICwABNQAFFAYIFQAeABEcAA==.',
Zy='Zyntalla:BAAANQAECgQIDQAAAA==.',
Zz='Zzonked:BAAANQAECgEIAQAAAA==.',
['Zê']='Zêp:BAAANQADCgcIFwAAAA==.',
['Àr']='Àrròw:BAAANQADCgYICgAAAA==.',
['Ðo']='Ðoogle:BAAANQAECgQIDwABNQABCgUIBQAJAAAAAA==.',
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
