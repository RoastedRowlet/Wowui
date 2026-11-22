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

local lookup = {'Paladin-Retribution','Shaman-Enhancement','Druid-Restoration','DemonHunter-Havoc','Warrior-Fury','DemonHunter-Vengeance','DemonHunter-Devourer','Hunter-BeastMastery','Druid-Feral','Unknown-Unknown','Paladin-Holy','Paladin-Protection','Priest-Holy','Shaman-Restoration','Warlock-Affliction','Mage-Arcane','DeathKnight-Blood','DeathKnight-Frost','Shaman-Elemental','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','DeathKnight-Unholy','Druid-Balance','Warlock-Destruction','Warlock-Demonology','Warrior-Protection','Hunter-Marksmanship','Priest-Shadow','Evoker-Devastation','Mage-Frost','Mage-Fire','Warrior-Arms','Evoker-Preservation','Monk-Mistweaver','Rogue-Outlaw','Priest-Discipline','Monk-Windwalker',}
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Aberaht:BAABNQAECn88AAIBAAoKHCMuGAACAwABAAoKHCMuGAACAwAAAA==.Absolution:BAABNQAECn8WAAICAAgKUQm+IQBCAQACAAgKUQm+IQBCAQAAAA==.',
Ac='Ackianae:BAAANQAECgYIEAAAAA==.',
Ad='Adenwey:BAABNQAECn8nAAIDAAoKcB8fBgCEAwADAAoKcB8fBgCEAwABNQAECgoKUgAEADskAA==.Adewey:BAAANQAECgUICgAAAA==.Adorabull:BAAANQADCgIIAgAAAA==.',
Ae='Aenastian:BAAANQADCgUIDwABNQAECgoKUgAEADskAA==.Aerynsun:BAAANQABCggIDgABNQAECgkJMQAFAMEVAA==.',
Ak='Akhalla:BAAANQAECgQIBAABNQAECgkJHAAGAF0QAA==.Akre:BAAANQAECgEIAQABNQAECggIHgAHAMwNAQ==.Akumä:BAAANQADCgcIEQAAAA==.',
Al='Alarmclock:BAAANQABCgcIDQABNQAECgkJMQAFAMEVAA==.Aleannia:BAAANQAECgMIAQAAAA==.Alekz:BAAANQADCgYIBgAAAA==.Alestria:BAABNQAECn8rAAIBAAoK8RphdgBAAgABAAoK8RphdgBAAgAAAA==.Algodón:BAAANQADCgEIAgABNQAFFAMIBQAIAKodAA==.Alibrexia:BAABNQAECn81AAIFAAoKMgx7DgCYAQAFAAoKMgx7DgCYAQAAAA==.Allus:BAAANQABCgUICQAAAA==.Alphaomega:BAABNQAECn8YAAIJAAkKjQdhIQD3AAAJAAkKjQdhIQD3AAAAAA==.',
An='Anarcy:BAAANQAECgIIAgAAAA==.Anastaysha:BAAANQAECgQIBAABNQAECggIEAAKAAAAAA==.Anathema:BAAANQAECgUIBwAAAA==.Ankan:BAABNQAECn8vAAILAAoKHyGfGgDkAgALAAoKHyGfGgDkAgABNQAECgoKUgAEADskAA==.Annalese:BAAANQADCgcIBwABNQAECggIEAAKAAAAAA==.',
Ap='Ape:BAAANQAECgQIBAAAAA==.Apoc:BAAANQADCgUIBQAAAA==.',
Ar='Arcticplague:BAAANQADCgEIAQAAAA==.Ardatha:BAAANQADCgIIAgAAAA==.Ariêz:BAAANQADCgQIBAAAAA==.Arlor:BAAANQADCgYIDAAAAA==.',
As='Ashkada:BAAANQADCgQIBAAAAA==.Astrocakes:BAAANQADCgYICgABNQAFFAEIAgAKAAAAAA==.',
At='Athenä:BAACNQAFFH8aAAIMAAcKuRkCAwBoAQAMAAcKuRkCAwBoAQA1AAQKfzIAAgwACgoGH4ELAOECAAwACgoGH4ELAOECAAAA.Atsuma:BAAANQADCggICwAAAA==.Atthel:BAAANQAECgYIDQAAAA==.Attunement:BAAANQAECgQIBwABNQAECggIEQAKAAAAAA==.',
Ay='Aylah:BAAANQABCgIIAgABNQAECgYICgAKAAAAAA==.Aylli:BAAANQADCgcIBwABNQAECgkJKwANAD8gAA==.',
Az='Azei:BAAANQADCgMIAwAAAA==.',
['Aí']='Aísling:BAABNQAECn8XAAILAAgKKRgRTQDfAQALAAgKKRgRTQDfAQAAAA==.',
Ba='Baconmecrazy:BAAANQADCgMIAwAAAA==.Baela:BAAANQAECgMIAwABNQAFFAcIHAAOAPcdAA==.Baelthemar:BAAANQADCgUIBQAAAA==.Bajafresh:BAAANQADCgMIAwAAAA==.Bambita:BAAANQAECggIDgAAAA==.Battleshaman:BAAANQABCgMIAgAAAA==.',
Be='Benjinana:BAABNQAECn8UAAINAAUK2xNYqgAXAQANAAUK2xNYqgAXAQAAAA==.',
Bi='Bittybombom:BAAANQAECgYIEgAAAA==.',
Bk='Bkunstopabl:BAAANQADCgIIAgAAAA==.',
Bl='Blackened:BAABNQAECn8mAAIPAAkKWhmcBQAkAgAPAAkKWhmcBQAkAgAAAA==.Bloodbraid:BAAANQADCgMIAwAAAA==.',
Bo='Bohde:BAAANQAFFAEIAQAAAA==.Boricua:BAAANQAECgIIAgAAAA==.Bountty:BAAANQADCgYIBgAAAA==.',
Br='Brightbane:BAAANQAECgEIAQAAAA==.',
Bu='Buddie:BAAANQADCggICAAAAA==.Buffaloseven:BAABNQAECn8cAAILAAgK6gxGeABMAQALAAgK6gxGeABMAQABNQAFFAYIDwAQAFIVAA==.Bulleitrye:BAAANQADCgYIBgAAAA==.Burninate:BAAANQABCggIEQABNQAECgkJMQAFAMEVAA==.',
By='Byorn:BAABNQAECn8YAAMRAAkKcBMwZgBaAQARAAcKew4wZgBaAQASAAcKgBNZXAAmAQABNQAFFAUIDAAIALYSAA==.',
Ca='Cairdamane:BAABNQAECn8vAAMTAAoKohDzcgDIAQATAAoKohDzcgDIAQAOAAMKPAaF5QBQAAAAAA==.Calidrina:BAABNQAECn86AAIHAAoKQxNLGQDmAQAHAAoKQxNLGQDmAQAAAA==.Caness:BAAANQADCgEIAQAAAA==.',
Ce='Celldrassil:BAABNQAECn8gAAIDAAkKfQp8NgBDAQADAAkKfQp8NgBDAQAAAA==.Cellerunn:BAAANQADCgYIBgAAAA==.Cereel:BAABNQAECn8ZAAMUAAkK6hxKMgAVAgAUAAcKdBtKMgAVAgAVAAUK8RkyWwCcAQABNQAFFAEIAgAKAAAAAA==.',
Ch='Charayi:BAAANQADCggICAABNQAECggIEAAKAAAAAA==.Chardaney:BAAANQAECggIEAAAAA==.Cheery:BAAANQAECgYIBgABNQAECgkJMQAFAMEVAA==.Chickennuggi:BAABNQAECn8aAAIWAAcKwyDBEQAdAgAWAAcKwyDBEQAdAgABNQAECgkJJQARAIgjAA==.',
Ci='Cii:BAABNQAECn8yAAMMAAoKTxICJwA4AQAMAAcKwxUCJwA4AQABAAgKIgcA7wAFAQAAAA==.Ciine:BAAANQADCgYICAABNQAECgoKMgAMAE8SAA==.Ciinelock:BAAANQADCgIIAgABNQAECgoKMgAMAE8SAA==.',
Cl='Clampz:BAEANQAECgUIBwABNQAFFAcIFAAVAD0eAA==.',
Co='Colabrn:BAAANQADCggIHwAAAA==.Colandros:BAAANQADCgEIAQAAAA==.Colara:BAABNQAECn8sAAIHAAoKogxLIQCVAQAHAAoKogxLIQCVAQAAAA==.Colbear:BAAANQABCgUICQAAAA==.Coldspace:BAABNQAECn9ZAAIBAAoKbCHdGQBdAwABAAoKbCHdGQBdAwAAAA==.Corlock:BAAANQABCgUIBQAAAA==.',
Cr='Crassberry:BAACNQAFFH8MAAIXAAcKMxUCDABNAQAXAAcKMxUCDABNAQA1AAQKfykAAhcACgoSJUkkALACABcACgoSJUkkALACAAAA.Creepindeath:BAAANQAECgEIAgAAAA==.',
Cu='Cucaracha:BAABNQAECn8bAAMJAAgK9RBPGABUAQAJAAgK9RBPGABUAQAYAAEKAAD+ywAVAAAAAA==.',
Cy='Cyndal:BAAANQADCgcIHQABNQAECgYICgAKAAAAAA==.Cyndle:BAAANQADCggIJQABNQAECgYICgAKAAAAAA==.',
Da='Dagrathon:BAAANQADCgcIBwAAAA==.Dankbuds:BAABNQAECn8UAAIWAAoK1xQ1FwDUAQAWAAoK1xQ1FwDUAQAAAA==.Dankothy:BAAANQAECgQICAABNQAECgoKFAAWANcUAA==.Dankshot:BAAANQAECgYICgABNQAECgoKFAAWANcUAA==.Dantes:BAAANQAECgEJAQAAAA==.Darkryu:BAAANQADCgYIEAAAAA==.Darkspace:BAABNQAECn8hAAQZAAoK7hW9BQCVAQAaAAoKbguNYAC0AQAZAAcKkBe9BQCVAQAPAAQKUxBBFQD2AAABNQAECgoKWQABAGwhAA==.Darthsix:BAAANQADCgEIAQAAAA==.Dazex:BAAANQAECgYIDwAAAA==.',
De='Deadbolt:BAABNQAECn8VAAMZAAcKkAcaHACGAAAaAAYKTQSBzAC4AAAZAAUKTwsaHACGAAAAAA==.Deathforever:BAAANQAECgQIBAAAAA==.Deaus:BAAANQADCggIFQAAAA==.Delrus:BAABNQAECn86AAQDAAoKdh4FDAAKAwADAAoKdh4FDAAKAwAWAAgKIxD4LQAhAQAYAAUKQhLIWAC9AAAAAA==.Demon:BAABNQAECn9EAAMEAAoKlCACDQBBAwAEAAoKlCACDQBBAwAGAAQK0Rq5HwCNAAABNQAFFAgIIQAVAGgRAA==.Demoniec:BAAANQAECgQIBQAAAA==.Demowneege:BAAANQADCggICAABNQAFFAcIGAAFAJYeAA==.Denzvic:BAAANQAECgYICwAAAA==.Destro:BAAANQADCggICAAAAA==.Devil:BAAANQABCgQIBAAAAA==.',
Di='Diddyjr:BAABNQAECn8mAAIQAAoK0Ru7fACFAgAQAAoK0Ru7fACFAgABNQAFFAEIAQAKAAAAAA==.Disowneege:BAAANQAECggIDgABNQAFFAcIGAAFAJYeAA==.Diyos:BAAANQADCggICAAAAA==.',
Do='Doodu:BAAANQAFFAEIAQAAAA==.',
Dr='Dragnas:BAABNQAECn9EAAQCAAoKaBLNDwAYAgACAAoKaBLNDwAYAgAOAAQKuxJrvADyAAATAAEKHg5NLgE6AAAAAA==.Dragonisa:BAAANQAECgMIAwAAAA==.Draiocht:BAAANQADCgQIBwABNQAECgkJKwANAD8gAA==.Drakass:BAAANQAECgMIAwAAAA==.Dramakiller:BAAANQAECgUIEQAAAA==.Drcornbread:BAABNQAECn8UAAMJAAUK8w7dIAAOAQAJAAUKhQ7dIAAOAQAWAAQKCAy5QwCmAAAAAA==.Drcornellia:BAAANQADCgYIBwABNQAECgUIFAAJAPMOAA==.Drdreggs:BAABNQAECn8kAAMaAAoK2hEzhADbAQAaAAkKixEzhADbAQAZAAEKBhTVcQA9AAAAAA==.Drop:BAAANQADCgQIBAABNQAECgoKQAABAF0fAA==.Druduwolf:BAAANQAECgcIEAAAAA==.',
Du='Durden:BAAANQADCgIIAgABNQAECgYIEAAKAAAAAA==.Dustyhunter:BAAANQAECgEIAQAAAA==.Duthalemar:BAAANQAECgYIBgABNQAECgoKUgAEADskAA==.',
Ea='Eatbuttforpi:BAAANQADCgUIBwABNQAFFAEIAgAKAAAAAA==.',
El='Elastar:BAABNQAECn8+AAIbAAoK9xlcCQBCAgAbAAoK9xlcCQBCAgAAAA==.Ellimist:BAEANQAECgcIDAAAAA==.Elsan:BAAANQADCgQIBAAAAA==.Elycee:BAABNQAECn8kAAMIAAoKoSNUEwD/AgAIAAoKoSNUEwD/AgAcAAoK9RBPGQC8AQAAAA==.',
Em='Emura:BAAANQAECgMIBAAAAA==.',
En='Enveliria:BAAANQAECgYIDwABNQAECgoKUgAEADskAA==.',
Er='Eraser:BAABNQAECn9CAAMNAAoKCBQ/ZADzAQANAAoKCBQ/ZADzAQAdAAgK0g5LJQBZAQAAAA==.Erazar:BAABNQAECn8kAAIeAAkKLwjkDwBBAQAeAAkKLwjkDwBBAQAAAA==.Erickk:BAABNQAECn89AAIQAAoKYxugTgDkAgAQAAoKYxugTgDkAgAAAA==.Eristela:BAAANQAECgUIDAAAAA==.',
Es='Escanorlion:BAAANQAECgUIBwAAAA==.Essense:BAABNQAECn88AAINAAoKSyW+BADoAwANAAoKSyW+BADoAwAAAA==.',
Ev='Evokedcat:BAAANQAECgcIDgAAAA==.',
Ex='Exodari:BAABNQAECn89AAICAAoKzA9aEwDhAQACAAoKzA9aEwDhAQAAAA==.Extro:BAAANQAECggIDAAAAA==.',
Fa='Fabbioh:BAAANQADCgEIAQAAAA==.Fadeddh:BAAANQAECgUIBwABNQAFFAEIAgAKAAAAAA==.Faeliendra:BAAANQADCggICAAAAA==.Fangloria:BAAANQABCggIEwABNQAECgkJMQAFAMEVAA==.Fatalgrip:BAAANQADCgUIBgAAAA==.',
Fe='Fel:BAABNQAECn9eAAMEAAoKsiS8BgCLAwAEAAoKrCO8BgCLAwAHAAoKHCTbBwDcAgAAAA==.Fellius:BAAANQADCgQIBAAAAA==.Fellkarras:BAAANQAECgUICAABNQAECgkJJQARAIgjAA==.Felprincess:BAAANQABCgYICgAAAA==.',
Fi='Fibitz:BAAANQAECgcIDQABNQAECgoKMwAIAJohAA==.Fiddich:BAAANQAECgcIDAAAAA==.Findstewie:BAAANQABCgYICgABNQABCggIFgAKAAAAAA==.Fiofio:BAABNQAECn86AAIQAAoKVRzPPQBUAgAQAAoKVRzPPQBUAgAAAA==.Fizban:BAABNQAECn8jAAMfAAkK/QvxDwCoAQAfAAkK/QvxDwCoAQAQAAQK+AEimwGQAAAAAA==.',
Fl='Flik:BAAANQAECgUICAABNQAECgoKaAANAGUdAA==.',
Fo='Foringojr:BAAANQAECgIIAgAAAA==.',
Fr='Fragglelock:BAAANQABCggIFQABNQAECgkJMQAFAMEVAA==.Frigidheart:BAAANQAECgUIDAABNQAECgoKJgABAJ0MAA==.Frostetute:BAABNQAECn8fAAIQAAoK/gxQbwDTAQAQAAoK/gxQbwDTAQAAAA==.',
Fu='Furrybawlz:BAAANQADCggICAABNQAECgQIBAAKAAAAAA==.',
['Fà']='Fàllén:BAAANQAECgEIAwABNQAFFAUIDAAIALYSAA==.',
Ga='Gadogear:BAABNQAECn8jAAIfAAkK0xZqDQDCAQAfAAkK0xZqDQDCAQAAAA==.Galabren:BAAANQAECgYJDQAAAA==.Garlik:BAAANQADCgUIDQAAAA==.',
Ge='Gertra:BAABNQAECn8dAAMBAAkKMRfwTQBBAgABAAkKMRfwTQBBAgAMAAEK4QahbgAlAAAAAA==.',
Gf='Gfr:BAABNQAECn8cAAMZAAkK+hkxBADdAQAZAAkK+hkxBADdAQAaAAEKAAANMwEAAAAAAA==.',
Gi='Giddoo:BAAANQAECgYICwAAAA==.Gilnean:BAAANQABCgUIBgAAAA==.',
Gn='Gnomeanator:BAAANQABCgIIAgAAAA==.Gnowanceyi:BAAANQAECgIIAwABNQAECgoKPQAQAGMbAA==.',
Go='Goatcheeze:BAAANQAECggIDgAAAA==.Gohlemsaurus:BAAANQADCggIJAAAAA==.',
Gu='Gulen:BAAANQADCggIGwAAAA==.Gullee:BAAANQABCggIEwAAAA==.',
['Gí']='Gíga:BAAANQAECgMIAwAAAA==.',
Ha='Halsten:BAABNQAECn8rAAQfAAkKNQe9FQA9AQAfAAkKNQe9FQA9AQAQAAUKswFwmgGRAAAgAAEKAACYDwAhAAAAAA==.Hamish:BAAANQAECgEIAQAAAA==.',
He='Hellenkeller:BAEANQAFFAEIAQABNQAFFAcIFAAVAD0eAA==.Heloisa:BAAANQADCgYIBgAAAA==.',
Hi='Hitt:BAAANQAECgYICgAAAA==.',
Ho='Hogwortsfun:BAAANQADCggICAAAAA==.Holysudz:BAAANQADCgIIAgAAAA==.Hoofingit:BAAANQAECgYIEAAAAA==.',
Hr='Hroc:BAABNQAECn8XAAIUAAkKhgkZRQCyAQAUAAkKhgkZRQCyAQAAAA==.',
Hu='Hunterboi:BAAANQAECgEIAQAAAA==.',
Ic='Icedlatte:BAAANQADCgUIDQAAAA==.Icywolfy:BAAANQAECgIIAgAAAA==.',
Ig='Igreetyou:BAAANQAECgQICQAAAA==.',
Il='Illune:BAABNQAECn80AAIQAAoK9hafRgA5AgAQAAoK9hafRgA5AgAAAA==.',
Im='Imleapingit:BAABNQAECn8zAAIhAAkKHR/UGQDjAgAhAAkKHR/UGQDjAgAAAA==.Imrelentless:BAAANQABCgYICwAAAA==.',
In='Inaurian:BAAANQADCggICAAAAA==.Intoodeep:BAABNQAECn9SAAIUAAoKNR7TBQC1AgAUAAoKNR7TBQC1AgAAAA==.Intoodemons:BAAANQAECgIIBAABNQAECgoKUgAUADUeAA==.Intoodragons:BAAANQAECggIBwAAAA==.',
Ir='Ir:BAABNQAECn9qAAIQAAoKRR4fPQAMAwAQAAoKRR4fPQAMAwAAAA==.Ironfoot:BAAANQAECgQIBAAAAA==.Irrlvntgobbo:BAAANQAECgYICwAAAA==.',
Is='Isasham:BAAANQAECgIIAgAAAA==.Isawarriorr:BAABNQAECn8eAAMhAAkKshkqXgByAgAhAAkKmRcqXgByAgAbAAIK0Rv1NACOAAAAAA==.Ishdo:BAABNQAECn8pAAIRAAkKggvkRwAdAQARAAkKggvkRwAdAQAAAA==.Ishdu:BAAANQADCgYIBgABNQAECgkJKQARAIILAA==.Ishlok:BAAANQADCgUIBQABNQAECgkJKQARAIILAA==.Ishmael:BAAANQAECgQIBQABNQAFFAUIDAAIALYSAA==.Ishwar:BAAANQADCggIGAABNQAECgkJKQARAIILAA==.',
Iv='Ivanhöe:BAAANQAECgUICQAAAA==.',
Ja='Jakytreehorn:BAABNQAECn8UAAITAAgKZBDVZwDpAQATAAgKZBDVZwDpAQAAAA==.Jaydm:BAABNQAECn8VAAIhAAkKsxCyhQB6AQAhAAkKsxCyhQB6AQABNQAFFAYIDwAQAFIVAA==.',
Je='Jenevelle:BAAANQAECgMJAwAAAA==.Jerisil:BAAANQADCgUICAAAAA==.Jessiel:BAAANQAECgUIBAAAAA==.Jet:BAABNQAECn9AAAIBAAoKXR8VMQCeAgABAAoKXR8VMQCeAgAAAA==.',
Ji='Jibbajabba:BAAANQAECggICQAAAA==.',
Ju='Judgiah:BAAANQAECgIIAgAAAA==.Julthaenia:BAABNQAECn80AAIPAAkKaRjVAwCwAgAPAAkKaRjVAwCwAgABNQAECgoKUgAEADskAA==.Junjia:BAAANQADCgUIBQAAAA==.',
Ka='Kagebushin:BAAANQABCgIIAgAAAA==.Kagome:BAAANQADCgcIDQABNQAECggIEAAKAAAAAA==.Kallekgos:BAAANQADCgEIAQAAAA==.Kalofelement:BAAANQADCgEIAQAAAA==.Kalysy:BAAANQAECgUIBwABNQAECgoKUgAEADskAA==.Karash:BAAANQAECgYIEAAAAA==.Kargush:BAAANQADCgQIBAABNQADCggIFgAKAAAAAA==.Karmaisab:BAAANQAECggIAQAAAA==.Karnrae:BAABNQAECn85AAIBAAoKBheoVwAoAgABAAoKBheoVwAoAgAAAA==.Karynos:BAABNQAECn85AAIaAAoK5RAYWgDGAQAaAAoK5RAYWgDGAQAAAA==.Katwolf:BAABNQAECn8eAAIIAAkKxQwndADXAQAIAAkKxQwndADXAQAAAA==.Katyah:BAABNQAECn8XAAIOAAgKCAfIlgBOAQAOAAgKCAfIlgBOAQAAAA==.Kavourkaa:BAAANQABCggIHQAAAA==.',
Ke='Keynivas:BAAANQAECgIIAgAAAA==.',
Ki='Killiua:BAAANQAECgcICwAAAA==.',
Ko='Kobayashi:BAAANQAECgUIBQABNQAECgkJMQAFAMEVAA==.Konspiracy:BAABNQAECn8kAAMZAAkKsRZxBQCiAQAZAAkKsRZxBQCiAQAaAAIK4QW4GgEzAAAAAA==.',
Kr='Kraguva:BAAANQAECgQIBAAAAA==.Krataar:BAAANQAECgEIAQABNQAECgYIDQAKAAAAAA==.Kroot:BAABNQAECn8zAAIIAAoKmiFiGQDeAgAIAAoKmiFiGQDeAgAAAA==.Krous:BAACNQAFFH8UAAIhAAcKOxvmCgACAgAhAAcKOxvmCgACAgA1AAQKfy4AAiEACgrEHxBPAJwCACEACgrEHxBPAJwCAAAA.Kryph:BAAANQAECgcIEQAAAA==.',
['Kä']='Kämpfer:BAAANQAECgcICwABNQAECgoKMgAiALsUAA==.',
La='Lafiel:BAABNQAECn81AAINAAoKohHMTwD6AQANAAoKohHMTwD6AQAAAA==.Landiedoo:BAAANQAECggIAQAAAA==.Latrank:BAAANQAECgYIBwAAAA==.Laurandre:BAABNQAECn81AAMDAAkKsQi5NgBCAQADAAkKsQi5NgBCAQAYAAIK3ANmlgAgAAAAAA==.Lazeras:BAAANQAECgUICAABNQAECgoKKwAJAAcbAA==.',
Le='Letsgetwet:BAAANQAECgQIBgAAAA==.',
Li='Liefic:BAABNQAECn8/AAIIAAoKmyMLCQBDAwAIAAoKmyMLCQBDAwAAAA==.Lilibeth:BAAANQADCggICgAAAA==.Lilienne:BAAANQABCgYIBwAAAA==.Lilstooge:BAAANQABCgYIBwABNQABCggIFgAKAAAAAA==.Limon:BAAANQAECgcICQAAAA==.',
Ll='Llylith:BAAANQABCgMIBAAAAA==.',
Lo='Locke:BAAANQAECgcICAABNQAECgoKQAABAF0fAA==.',
Lu='Luckykilla:BAABNQAECn81AAIUAAoKwxhRDAAIAgAUAAoKwxhRDAAIAgAAAA==.Lucÿ:BAACNQAFFH8PAAIOAAUK0xeLDgB1AQAOAAUK0xeLDgB1AQA1AAQKfy0AAw4ACgqzHuQjANcCAA4ACgqzHuQjANcCABMABgp7EmyYAGgBAAAA.Lune:BAAANQADCgUICwAAAA==.Lurith:BAACNQAFFH8FAAIXAAIKRAwRDQCJAAAXAAIKRAwRDQCJAAA1AAQKf10AAxEACgoBGxEWAFkCABEACgo8GREWAFkCABcABwrQGZs2AEIBAAAA.Luxtyrannica:BAABNQAECn8XAAIBAAgK0Q09zQA8AQABAAgK0Q09zQA8AQAAAA==.',
Ly='Lydrain:BAAANQAECgQIBQAAAA==.Lylia:BAAANQADCggIGAAAAA==.',
Ma='Malcolm:BAAANQABCgYIDQABNQAECgkJMQAFAMEVAA==.Marahh:BAAANQABCgIIAgAAAA==.Matt:BAAANQAECgQIBAABNQAFFAgIIQAVAGgRAA==.Mattbolt:BAABNQAECn8ZAAICAAkKNiEDDwB6AgACAAkKNiEDDwB6AgAAAA==.Maximoose:BAACNQAFFH8MAAIIAAUKthKDEQBIAQAIAAUKthKDEQBIAQA1AAQKfysAAggACgq6GXhHAJYCAAgACgq6GXhHAJYCAAAA.Mayu:BAAANQADCggIGgAAAA==.Mayumey:BAAANQADCgUIBQAAAA==.Mazigos:BAAANQAECgUIBQAAAA==.',
Me='Medjrab:BAACNQAFFH8GAAIXAAIKtxfECwCbAAAXAAIKtxfECwCbAAA1AAQKf0cAAhcACgpkI3wJAHIDABcACgpkI3wJAHIDAAAA.Mefi:BAAANQADCgcIFgAAAA==.Melyria:BAABNQAECn8eAAIHAAgKzA1EMwCoAQAHAAgKzA1EMwCoAQAAAA==.Meristem:BAABNQAECn8wAAIYAAoKYAxcLgCSAQAYAAoKYAxcLgCSAQAAAA==.Merko:BAAANQADCggICQABNQAECgoKMwAIAJohAA==.',
Mi='Mignius:BAAANQADCgYIBgAAAA==.Mihonk:BAAANQAECgUICgAAAA==.Millesfavdom:BAABNQAECn8eAAIEAAkK/BNzIAAHAgAEAAkK/BNzIAAHAgABNQAFFAgIFAAWAHAQAA==.Misafarm:BAAANQADCgIIAgAAAA==.Mistified:BAAANQABCgIIBAAAAA==.',
Mo='Moedorai:BAAANQAECggIEQAAAA==.Mogast:BAAANQADCgcIBwAAAA==.Mogma:BAAANQAECgUICQAAAA==.Mogsarren:BAAANQABCgIIAgABNQAECgoKUQARAL8lAA==.Momentomori:BAAANQADCgUICwAAAA==.Mondgrille:BAAANQAECgQIBAAAAA==.Monora:BAAANQADCggIEQAAAA==.Moonbounds:BAACNQAFFH8VAAIOAAgKHhsGBgAIAgAOAAgKHhsGBgAIAgA1AAQKf1oAAg4ACgrSI5kFAJoDAA4ACgrSI5kFAJoDAAAA.Moondoggey:BAAANQADCgUIBQAAAA==.Moonshift:BAAANQABCggIFwAAAA==.Morgana:BAAANQADCgYICAAAAA==.Mousechief:BAABNQAECn8qAAITAAcKcAPSpgC5AAATAAcKcAPSpgC5AAAAAA==.Moxxzi:BAABNQAECn8rAAIXAAgK2BFWKgCSAQAXAAgK2BFWKgCSAQAAAA==.',
Mu='Muhfookinbak:BAABNQAECn8wAAQTAAoKLSLbEgDUAgATAAoKLSLbEgDUAgACAAEKixMhNQBBAAAOAAIKNwz2FwE7AAAAAA==.',
Na='Naksu:BAAANQADCgYJFgABNQAECgoKNAANAKAgAA==.Naksù:BAAANQADCgUIBQABNQAECgoKNAANAKAgAA==.Naksü:BAABNQAECn80AAINAAoKoCBXFQAsAwANAAoKoCBXFQAsAwAAAA==.',
Ne='Neifeb:BAABNQAECn8qAAIIAAkKcxHxggAGAgAIAAkKcxHxggAGAgAAAA==.Nerfherder:BAAANQABCgcIDwABNQAECgkJMQAFAMEVAA==.',
Ni='Niallivdam:BAAANQAECgQIDwAAAA==.Nights:BAABNQAECn8VAAIbAAkKcyD4AwD0AgAbAAkKcyD4AwD0AgABNQAFFAgIIQAVAGgRAA==.Ninh:BAABNQAECn9qAAIjAAoKZg8pFADCAQAjAAoKZg8pFADCAQAAAA==.Nintendopsp:BAAANQAECgIIAgAAAA==.Ninthgate:BAABNQAECn8gAAIaAAkKogWZ4QAGAQAaAAkKogWZ4QAGAQAAAA==.',
No='Noble:BAABNQAECn9BAAMHAAoK0hZXFAAgAgAHAAoK0hZXFAAgAgAEAAEKuQblhwAvAAAAAA==.Nogood:BAABNQAECn8ZAAIhAAoKRRYzaQBVAgAhAAoKRRYzaQBVAgAAAA==.Notsodemon:BAAANQAECgQICAABNQAECgcIFQAQAJsLAA==.Notsomage:BAABNQAECn8VAAIQAAcKmwsDAwGJAQAQAAcKmwsDAwGJAQAAAA==.',
Ny='Nyorai:BAAANQABCgQIAwAAAA==.Nyxwing:BAAANQAECgYIBQAAAA==.',
['Nå']='Nåld:BAAANQAECgEIAQAAAA==.',
['Në']='Nëao:BAAANQADCgYIBgAAAA==.',
Ob='Obvinotagirl:BAABNQAECn9AAAMDAAoKxiJKAwDQAwADAAoKxiJKAwDQAwAYAAEKAAC3xwAaAAAAAA==.',
Od='Oddone:BAAANQAECgUICwAAAA==.Oddpocalypse:BAAANQADCgQIBAAAAA==.Odelina:BAAANQADCggIDgAAAA==.Odinheâthen:BAAANQADCgYJDAAAAA==.',
Ol='Olydwarf:BAAANQAECgEIAQAAAA==.',
On='Onebadmutha:BAABNQAECn8eAAIaAAgKrQpXeAB0AQAaAAgKrQpXeAB0AQAAAA==.Ontop:BAABNQAECn9gAAIIAAoK6x4kKAD3AgAIAAoK6x4kKAD3AgAAAA==.',
Or='Orb:BAAANQAECgEIAQAAAA==.Ortinks:BAABNQAECn8pAAMfAAkKuRQuDQDgAQAfAAkKuRQuDQDgAQAQAAMK1wV1swFaAAAAAA==.',
Ou='Ouz:BAAANQAECgUIBQABNQAECgoKKwAJAAcbAA==.',
Ow='Owneege:BAACNQAFFH8YAAMFAAcKlh5AAACzAQAFAAcKCRtAAACzAQAhAAUKYRo7EgCeAQA1AAQKfzkAAyEACgooJHInAKICACEACgr1InInAKICAAUACQq0IpsKAB4CAAAA.',
Pa='Paapaa:BAABNQAECn8UAAIVAAoK6BWSLQBHAgAVAAoK6BWSLQBHAgAAAA==.Pallideaus:BAABNQAECn8oAAILAAkKHB6TLwCoAgALAAkKHB6TLwCoAgAAAA==.Pallinar:BAABNQAECn8VAAIBAAgKcAk36ABLAQABAAgKcAk36ABLAQAAAA==.Pandamak:BAAANQADCggICAAAAA==.Paradoxx:BAAANQADCgIIBAAAAA==.Pasquale:BAAANQAECgUIBwAAAA==.Pauzhaan:BAAANQAECgUICQABNQAECgkJMQAFAMEVAA==.',
Pe='Pebbles:BAABNQAECn9FAAIBAAoKJhYNcADvAQABAAoKJhYNcADvAQAAAA==.Pedorus:BAAANQABCgYIBwABNQAFFAUIDwAOANMXAA==.Penjerman:BAAANQAFFAEIAgAAAA==.',
Pi='Picklericky:BAAANQADCggIEgAAAA==.Pilgrimm:BAECNQAFFH8UAAIVAAcKPR7uAQA4AgAVAAcKPR7uAQA4AgA1AAQKfzIABBUACgq0JZ4DAGUDABUACgq0JZ4DAGUDACQAAQq5G4YZAEwAABQAAQpBC42gADoAAAAA.Pinxyl:BAAANQABCgcIBwAAAA==.Pistola:BAAANQAECgQIBAAAAA==.Pix:BAAANQABCgQIBwAAAA==.',
Pl='Plaguerott:BAABNQAECn8YAAISAAcKsgVSYgAbAQASAAcKsgVSYgAbAQAAAA==.Plaguewind:BAAANQAECggIEAAAAA==.',
Po='Polydh:BAABNQAECn8yAAIGAAoKYSQJAQC1AwAGAAoKYSQJAQC1AwAAAA==.Poobah:BAABNQAECn8jAAMTAAkKJgiMlQDeAAATAAgK2wiMlQDeAAAOAAIKrgLl7gBAAAAAAA==.Popsicles:BAABNQAECn8lAAMlAAkKixYqBgAyAgAlAAkKixYqBgAyAgAdAAEKAADjigAfAAAAAA==.Potrat:BAAANQAECgMJAwAAAA==.Pouffant:BAAANQAECgcICwAAAA==.',
Pr='Praddagy:BAAANQADCgUIBQAAAA==.Prayoncè:BAAANQADCggIDwAAAA==.Pronoz:BAAANQAECggIDwAAAA==.',
Pu='Puffr:BAAANQADCgQIBAAAAA==.Purpyl:BAABNQAECn8cAAIGAAkKXRDRDwBJAQAGAAkKXRDRDwBJAQAAAA==.',
Pw='Pwnageddon:BAAANQAECgMIAwAAAA==.Pwnjitsu:BAABNQAECn88AAImAAoKBx5DDACbAgAmAAoKBx5DDACbAgAAAA==.',
Py='Pyrothermia:BAACNQAFFH8PAAIQAAYKUhWIDgADAgAQAAYKUhWIDgADAgA1AAQKfzYAAxAACgquIvIXAOcCABAACgquIvIXAOcCAB8AAwr+BIsyAHEAAAAA.',
Ra='Rakugan:BAAANQABCgMIAwAAAA==.Ravthorn:BAAANQAECgIIAgAAAA==.Rawhoof:BAABNQAECn9qAAIhAAoK8CL7FwDsAgAhAAoK8CL7FwDsAgAAAA==.Razak:BAABNQAECn9GAAICAAoKMCNvBQDiAgACAAoKMCNvBQDiAgAAAA==.',
Rd='Rdnckromeo:BAAANQAECgQIBAAAAA==.',
Re='Redlock:BAABNQAECn8xAAIZAAoKgw0jBgCFAQAZAAoKgw0jBgCFAQAAAA==.Redrum:BAABNQAECn8lAAIRAAkKiCMZCwBbAwARAAkKiCMZCwBbAwAAAA==.Reineken:BAAANQADCggIFQAAAA==.Renarin:BAABNQAECn9oAAINAAoKZR19IADtAgANAAoKZR19IADtAgAAAA==.Renisa:BAABNQAECn8pAAQHAAoKvxQuGgDcAQAHAAoKvxQuGgDcAQAEAAEKMwb6nAAlAAAGAAEKAADeOgAAAAAAAA==.Renobagem:BAAANQADCgUIBgAAAA==.Retman:BAAANQADCggIDgAAAA==.Reu:BAAANQAECgcICgAAAA==.Revlyk:BAABNQAECn87AAMCAAoKqR1YCQCMAgACAAoKqR1YCQCMAgAOAAgKXRmvzwB3AAABNQAECgoKUgAEADskAA==.',
Rh='Rhoanna:BAAANQAECgQIBAAAAA==.Rhoupert:BAABNQAECn8WAAIBAAgK6xVhmQDwAQABAAgK6xVhmQDwAQAAAA==.',
Ri='Rimastus:BAAANQAECgEIAQAAAA==.',
Ro='Roccot:BAABNQAECn8/AAIRAAoKrSG6CQDyAgARAAoKrSG6CQDyAgAAAA==.Rotfather:BAAANQADCgcICAAAAA==.Rotjaw:BAAANQADCggIDAAAAA==.Roughedge:BAAANQADCgIIAgAAAA==.',
Rv='Rvn:BAAANQAECgUICQAAAA==.',
Ry='Ryppyr:BAAANQADCggICAAAAA==.',
['Rè']='Rèjuva:BAAANQADCgEIAQAAAA==.',
Sa='Saintess:BAAANQABCgYIDAAAAA==.Sallanu:BAAANQAECgEIAQAAAA==.Sardencreian:BAAANQAFFAEIAQAAAA==.Sauron:BAAANQAECgYICQAAAA==.',
Sc='Scalycat:BAAANQAECgcIDwAAAA==.Scum:BAAANQADCgcIDQABNQAECgQIBAAKAAAAAA==.',
Se='Senate:BAABNQAECn8/AAMTAAoKwBMnPADkAQATAAoKwBMnPADkAQAOAAEKqgFVMQEfAAAAAA==.Servenslay:BAAANQADCggIDgAAAA==.',
Sh='Shaamazing:BAAANQABCgIIAgAAAA==.Shablaam:BAAANQAECgIIAwAAAA==.Shadowbear:BAABNQAECn8pAAIdAAkK/xXXGADcAQAdAAkK/xXXGADcAQAAAA==.Sherrilyn:BAAANQAECgEIAQAAAA==.Shifdiah:BAAANQAECgUICgAAAA==.Shocktherapi:BAAANQAECgcIDAAAAA==.Shrimpback:BAAANQAECgIIAQAAAA==.',
Si='Singularity:BAAANQAECgQJBQAAAA==.',
Sk='Skelli:BAECNQAFFH8bAAINAAcKlRKXCgDfAQANAAcKlRKXCgDfAQA1AAQKfyYAAg0ACgo/HI47AHsCAA0ACgo/HI47AHsCAAE1AAQKBwgMAAoAAAAA.Skittlesdan:BAABNQAECn8mAAQaAAoKYhLSfgDpAQAaAAoKYhLSfgDpAQAPAAEKAAB/MgAvAAAZAAEKxQQWgwAoAAAAAA==.',
Sl='Slagathorr:BAAANQABCgIIAgAAAA==.Slaykween:BAABNQAECn8jAAIMAAgK8gTgOgDBAAAMAAgK8gTgOgDBAAAAAA==.Slaynesh:BAAANQADCgcIBwAAAA==.',
Sm='Smallz:BAAANQAECgUIBQABNQAECgkJIwAfAP0LAA==.',
Sn='Sneakin:BAAANQADCgIIAgAAAA==.Snooptrogg:BAABNQAECn8xAAQFAAkKwRURDwC8AQAFAAYK6xgRDwC8AQAhAAgKAw++ugCKAQAbAAUK8A/wLQCVAAAAAA==.',
So='Soldiah:BAAANQAECggICAAAAA==.Something:BAAANQABCggIEwABNQAECgkJMQAFAMEVAA==.Soryu:BAAANQAECgIIAgAAAA==.',
Sp='Spacelaser:BAAANQADCgMIAwAAAA==.Specialtwo:BAAANQADCgEIAQAAAA==.',
Sq='Sqwurl:BAAANQADCgUIBQAAAA==.',
St='Steakhaus:BAAANQAECgIIAgAAAA==.Stonedragon:BAECNQAFFH8PAAIIAAUKMxfjEwDuAAAIAAUKMxfjEwDuAAA1AAQKf1YAAggACgqNJaoFALQDAAgACgqNJaoFALQDAAAA.Stormfang:BAAANQADCgcIFAABNQAECggIFwALACkYAA==.Stormfist:BAAANQADCgQIBgAAAA==.Stormhaven:BAAANQADCgQJBAABNQAECggIFwALACkYAA==.Stormrender:BAAANQAECgUICgAAAA==.Stormriders:BAABNQAECn8/AAITAAoK1xHKQgDJAQATAAoK1xHKQgDJAQAAAA==.Stouty:BAAANQADCgQIAQAAAA==.Stubz:BAAANQABCgYICAAAAA==.',
Su='Sugi:BAAANQAECgcIDQABNQAFFAYICQAHAAMSAA==.Sukonamí:BAABNQAECn8iAAIhAAoKFBSzVAAAAgAhAAoKFBSzVAAAAgAAAA==.Suzhou:BAABNQAECn8bAAIZAAkK3wbIDADzAAAZAAkK3wbIDADzAAAAAA==.Suzoomies:BAAANQADCggIDwAAAA==.',
Sw='Swisscheese:BAABNQAECn8eAAMaAAkKqBomXABDAgAaAAkKqBomXABDAgAZAAEKLwpLewAyAAAAAA==.Swoopyboop:BAAANQADCgQIBAAAAA==.',
Sy='Sybaek:BAAANQAECggIDQAAAA==.Sycò:BAABNQAECn8sAAMIAAkKGyOaEgBVAwAIAAkKGyOaEgBVAwAcAAEKkQF3ngAgAAAAAA==.Syraxa:BAAANQAECgMIBAABNQAECgoKTAADAKMbAA==.',
['Sú']='Súbzerø:BAAANQAECgEIAQABNQAFFAQICwAIAJcTAA==.',
Ta='Taedish:BAAANQAECgEIAQAAAA==.Tahzdingle:BAAANQADCgYICwAAAA==.Talorien:BAAANQADCgIIAgABNQAECgoKNAAQAPYWAA==.Tayy:BAAANQADCgYICwAAAA==.',
Te='Teknobutts:BAAANQADCgUIBQAAAA==.Telan:BAAANQADCgUIBQAAAA==.Tempertotems:BAAANQADCggIDQAAAA==.Tenastin:BAAANQADCgQIBAAAAA==.Terragosa:BAABNQAECn8tAAMQAAoKBhW0WgAFAgAQAAoKqRO0WgAFAgAfAAIKFwwBNwBgAAAAAA==.Tetchybono:BAABNQAECn8UAAQZAAcK7AxrNQDtAAAZAAQKTQxrNQDtAAAPAAQKfgzSGQC4AAAaAAMKeAay+ABkAAAAAA==.Tettra:BAAANQADCggIEgABNQAECgYICgAKAAAAAA==.',
Th='Thaeleon:BAAANQAECgMIAwABNQAFFAUIDAAIALYSAA==.Thahawtz:BAAANQADCgYIDAAAAA==.Thirinis:BAABNQAECn8hAAILAAkKuAlddgBSAQALAAkKuAlddgBSAQAAAA==.Thope:BAAANQADCgYIFgAAAA==.Thrivia:BAAANQAECggIDgAAAA==.Thundergirl:BAAANQAECggIDwAAAA==.',
Ti='Ticklemychin:BAAANQADCgcIDQAAAA==.Tictacc:BAAANQADCgEIAQAAAA==.',
Tl='Tlàchtga:BAAANQAECgUICgAAAA==.',
To='Tortorin:BAAANQAECggICAAAAA==.Toughasnails:BAAANQAECgEIAQAAAA==.',
Tr='Traesdyne:BAAANQADCgQIBQAAAA==.Trailwalkur:BAAANQADCgYIDAABNQAECgoKKwAJAAcbAA==.Trainar:BAAANQAECgUIDQABNQAECgcIGgAEADEaAA==.Triggs:BAAANQAECggIBwAAAA==.Trollbear:BAAANQADCgcIBwAAAA==.Trooze:BAABNQAECn8aAAILAAcKHyG5LAByAgALAAcKHyG5LAByAgAAAA==.Truckz:BAABNQAECn8lAAITAAoKFRceLAAsAgATAAoKFRceLAAsAgAAAA==.Truckzage:BAAANQAECgQIBAABNQAECgoKJQATABUXAA==.Truckzbrr:BAAANQAECgEIAQABNQAECgoKJQATABUXAA==.Trõnlight:BAAANQAECgEIAQAAAA==.',
Ts='Tsunah:BAAANQADCgYIBgAAAA==.',
Tu='Tuba:BAAANQAECgEIAQAAAA==.Turim:BAAANQAECgEIAQAAAA==.',
Ty='Tyrawick:BAAANQAECgYIBgAAAA==.Tyrlidd:BAABNQAECn8tAAIIAAkK1wlNkgCRAQAIAAkK1wlNkgCRAQAAAA==.',
Un='Unavoidable:BAAANQADCgMIAwAAAA==.Unlikelytale:BAABNQAECn8yAAMOAAoKcxzFKQC8AgAOAAoKcxzFKQC8AgATAAEKRxbRJgFEAAAAAA==.',
Ur='Urbanmeyer:BAAANQAECgMIBQAAAA==.Uricash:BAABNQAECn9RAAIQAAoKjh/AGwDTAgAQAAoKjh/AGwDTAgAAAA==.Urrax:BAAANQADCgEIAQABNQADCgIIAgAKAAAAAA==.Urzual:BAABNQAECn8uAAMCAAkK6R2BDACoAgACAAkK6R2BDACoAgAOAAYKbhSCigBvAQAAAA==.',
Ut='Utini:BAAANQAECgEIAQABNQAECgEIAQAKAAAAAA==.',
Va='Vandreynna:BAABNQAECn9SAAIEAAoKOyRbBgCQAwAEAAoKOyRbBgCQAwAAAA==.',
Ve='Vehlrine:BAAANQADCgIIAgAAAA==.Velsiana:BAAANQAECgMIAwAAAA==.Velveetah:BAAANQADCgYIBwABNQAECgUIFAANANsTAA==.Venasia:BAAANQAECgMIAwABNQAECgoKUgAEADskAA==.Verbren:BAAANQAECgcICAABNQAECgoKMgAiALsUAA==.Verbrennen:BAABNQAECn8yAAIiAAoKuxQeGgAhAgAiAAoKuxQeGgAhAgAAAA==.Verita:BAAANQAECgQIBgAAAA==.Verlynne:BAAANQADCgcIBwAAAA==.Vetinari:BAAANQABCggIGwABNQAECgkJMQAFAMEVAA==.',
Vi='Viviann:BAABNQAECn85AAMiAAoKUgsxFAC1AQAiAAoKUgsxFAC1AQAeAAYKPAlEIwArAQAAAA==.',
Vo='Von:BAAANQADCgEIAQAAAA==.',
Wa='Walee:BAAANQADCgIIAgAAAA==.Walfred:BAAANQAECgQIBwABNQAFFAIIBQAXAEQMAA==.Warraxe:BAAANQADCgYIBwAAAA==.Waukeen:BAAANQABCgIIAgAAAA==.Wayloren:BAABNQAECn8qAAIBAAkKQAkx0gB3AQABAAkKQAkx0gB3AQAAAA==.Wayverly:BAAANQADCgEIAQABNQAECggIEAAKAAAAAA==.',
We='Wetboycaird:BAAANQADCgMIAwAAAA==.',
Wh='Whatsthemage:BAAANQADCgcIBwAAAA==.',
Wi='Wickathy:BAABNQAECn8xAAMGAAoKfCNwAQCTAwAGAAoKfCNwAQCTAwAEAAEKJgJukgAXAAAAAA==.Wickcreu:BAAANQAECgQIBAAAAA==.',
Wo='Woodson:BAAANQADCggICAABNQAECgkJHAAGAF0QAA==.Worstdps:BAACNQAFFH8NAAIEAAUKLwatDAD9AAAEAAUKLwatDAD9AAA1AAQKf0oAAgQACgp0HKsRAJwCAAQACgp0HKsRAJwCAAAA.',
Wu='Wuldorr:BAACNQAFFH8JAAIBAAQKAAfYFQAAAQABAAQKAAfYFQAAAQA1AAQKfzIAAgEACgr8F9NDAF4CAAEACgr8F9NDAF4CAAAA.',
Wy='Wynnifred:BAABNQAECn8dAAMiAAYKZRTrGgBJAQAiAAYKZRTrGgBJAQAeAAQKFgS8HwBiAAAAAA==.',
Xa='Xaltheris:BAAANQAECgYIBgAAAA==.',
Xe='Xenothor:BAAANQAECgEIAQAAAA==.Xethreal:BAABNQAECn8xAAIOAAoKchi+RABOAgAOAAoKchi+RABOAgAAAA==.',
Xy='Xype:BAAANQAECggICAAAAA==.',
Xz='Xzara:BAAANQAECgYICgAAAA==.',
Ya='Yaanu:BAAANQADCgMIAwAAAA==.',
Yu='Yura:BAAANQADCggICAAAAA==.',
Yv='Yvvee:BAAANQAECgMIAwAAAA==.',
Za='Zapbranigan:BAAANQADCggIDQAAAA==.Zasko:BAAANQAECggIDwAAAA==.',
Zi='Zifao:BAABNQAECn8vAAIQAAoKZCMTKQA/AwAQAAoKZCMTKQA/AwAAAA==.',
Zo='Zonora:BAABNQAECn8uAAILAAoKzxGiTgDZAQALAAoKzxGiTgDZAQAAAA==.',
['Äz']='Äzrael:BAABNQAECn8rAAINAAkKPyBaEwA9AwANAAkKPyBaEwA9AwAAAA==.',
['Çr']='Çréwüsæðèr:BAABNQAECn8eAAIbAAkKlh1zDgDSAQAbAAkKlh1zDgDSAQAAAA==.',
['Ðì']='Ðìaßlo:BAACNQAFFH8LAAIIAAQKlxPuEQBDAQAIAAQKlxPuEQBDAQA1AAQKf0gAAggACgrtIRoWAPACAAgACgrtIRoWAPACAAAA.',
['Òd']='Òdinn:BAAANQADCgcIBwAAAA==.',
['Ød']='Ødin:BAAANQADCggIFAABNQAECggIFwALACkYAA==.',
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
