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

local lookup = {'Paladin-Retribution','Shaman-Enhancement','Druid-Restoration','DemonHunter-Havoc','Warrior-Fury','Unknown-Unknown','DemonHunter-Devourer','Hunter-BeastMastery','Paladin-Holy','Paladin-Protection','Priest-Holy','Shaman-Restoration','Warlock-Affliction','Mage-Arcane','DeathKnight-Frost','DeathKnight-Blood','Shaman-Elemental','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','DeathKnight-Unholy','Warlock-Destruction','Warlock-Demonology','Druid-Balance','DemonHunter-Vengeance','Druid-Feral','Warrior-Protection','Hunter-Marksmanship','Priest-Shadow','Evoker-Devastation','Mage-Frost','Mage-Fire','Warrior-Arms','Evoker-Preservation','Monk-Mistweaver','Rogue-Outlaw','Priest-Discipline','Monk-Windwalker',}
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Aberaht:BAABNQAECn88AAIBAAoKHCO3DwAXAwABAAoKHCO3DwAXAwAAAA==.Absolution:BAABNQAECn8WAAICAAgKUQm+IQBCAQACAAgKUQm+IQBCAQAAAA==.',
Ac='Ackianae:BAAANQAECgYIEAAAAA==.',
Ad='Adenwey:BAABNQAECn8aAAIDAAoKAxmFCwDVAgADAAoKAxmFCwDVAgABNQAECgoKQwAEAGYjAA==.Adewey:BAAANQAECgUICgAAAA==.Adorabull:BAAANQADCgIIAgAAAA==.',
Ae='Aenastian:BAAANQADCgUIEgABNQAECgoKQwAEAGYjAA==.Aerynsun:BAAANQABCggIDgABNQAECgkJMAAFAMEVAA==.',
Ak='Akhalla:BAAANQAECgQIBAABNQAECgcIEQAGAAAAAA==.Akre:BAAANQAECgEIAQABNQAECggIHgAHAMwNAQ==.Akumä:BAAANQADCgcIEQAAAA==.',
Al='Alarmclock:BAAANQABCgcIDQABNQAECgkJMAAFAMEVAA==.Aleannia:BAAANQAECgEIAQAAAA==.Alekz:BAAANQADCgYIBgAAAA==.Alestria:BAABNQAECn8oAAIBAAoKZxlhdgBAAgABAAoKZxlhdgBAAgAAAA==.Algodón:BAAANQADCgEIAgABNQAFFAMIBQAIAKodAA==.Alibrexia:BAABNQAECn8jAAIFAAoKtgkNDwBJAQAFAAoKtgkNDwBJAQAAAA==.Allus:BAAANQADCgEIAwAAAA==.Alphaomega:BAAANQAECgcIDQAAAA==.',
An='Anarcy:BAAANQAECgIIAgAAAA==.Anastaysha:BAAANQAECgQIBAABNQAECgYICgAGAAAAAA==.Anathema:BAAANQAECgUIBwAAAA==.Ankan:BAABNQAECn8nAAIJAAoKFh4hLgCuAgAJAAoKFh4hLgCuAgABNQAECgoKQwAEAGYjAA==.Annalese:BAAANQADCgcICQABNQAECgYICgAGAAAAAA==.',
Ap='Ape:BAAANQAECgQIBAAAAA==.Apoc:BAAANQADCgUIBQAAAA==.',
Ar='Arcticplague:BAAANQADCgEIAQAAAA==.Ardatha:BAAANQADCgIIAwAAAA==.Ariêz:BAAANQADCgQIBAAAAA==.Arlor:BAAANQADCgYIDQAAAA==.',
As='Ashkada:BAAANQADCgQIBAAAAA==.Astrocakes:BAAANQADCgYICgABNQAFFAEIAQAGAAAAAA==.',
At='Athenä:BAACNQAFFH8aAAIKAAcKuRkCAgBwAQAKAAcKuRkCAgBwAQA1AAQKfy8AAgoACgr9HoELAOECAAoACgr9HoELAOECAAAA.Atsuma:BAAANQADCggIDAAAAA==.Atthel:BAAANQAECgYIDQAAAA==.Attunement:BAAANQAECgQIBQABNQAECggIEQAGAAAAAA==.',
Ay='Aylah:BAAANQADCgEIAQABNQAECgYICgAGAAAAAA==.Aylli:BAAANQADCgcIBwABNQAECggIIAALAGIaAA==.',
Az='Azei:BAAANQADCgMIAwAAAA==.',
['Aí']='Aísling:BAAANQAECgYIEgAAAA==.',
Ba='Baconmecrazy:BAAANQADCgMIAwAAAA==.Baela:BAAANQAECgMIAwABNQAFFAcIHAAMAPcdAA==.Baelthemar:BAAANQADCgUIBgAAAA==.Bajafresh:BAAANQADCgMIBAAAAA==.Bambita:BAAANQAECggIDAAAAA==.Battleshaman:BAAANQADCgEIAgAAAA==.',
Be='Bela:BAAANQADCgEIAQAAAA==.Benjinana:BAABNQAECn8UAAILAAUK2xNYqgAXAQALAAUK2xNYqgAXAQAAAA==.',
Bi='Bittybombom:BAAANQAECgUICAAAAA==.',
Bk='Bkunstopabl:BAAANQADCgIIAgAAAA==.',
Bl='Blackened:BAABNQAECn8eAAINAAgKbhkEBwA0AgANAAgKbhkEBwA0AgAAAA==.Bloodbraid:BAAANQADCgMIBAAAAA==.',
Bo='Bohde:BAAANQAFFAEIAQAAAA==.Boricua:BAAANQAECgIIAgAAAA==.Bountty:BAAANQADCgYIBwAAAA==.',
Br='Brightbane:BAAANQAECgEIAQAAAA==.Bronislav:BAAANQADCgEIAQABNQADCgEIAQAGAAAAAA==.',
Bu='Buddie:BAAANQADCggICAAAAA==.Buffaloseven:BAAANQAECgQIDQABNQAFFAYIDwAOAFIVAA==.Bulleitrye:BAAANQADCgYIBgAAAA==.Burninate:BAAANQABCggIEQABNQAECgkJMAAFAMEVAA==.',
By='Byorn:BAABNQAECn8YAAMPAAkKcBNxSwAqAQAQAAcKew4wZgBaAQAPAAcKgBNxSwAqAQABNQAFFAQICgAIAPwSAA==.',
Ca='Cairdamane:BAABNQAECn8tAAMRAAoKohDMUgBVAQARAAoKohDMUgBVAQAMAAMKPAY9zwBQAAAAAA==.Calidrina:BAABNQAECn86AAIHAAoKQxPCEwD2AQAHAAoKQxPCEwD2AQAAAA==.Caness:BAAANQADCgEIAQAAAA==.Cartianer:BAAANQADCgEIAQAAAA==.',
Ce='Celldrassil:BAABNQAECn8YAAIDAAgKhgp7MwASAQADAAgKhgp7MwASAQAAAA==.Cellerunn:BAAANQADCgYIBgAAAA==.Cereel:BAABNQAECn8YAAMSAAkK6hxKMgAVAgASAAcKdBtKMgAVAgATAAUK8RlMRgCbAQABNQAFFAEIAQAGAAAAAA==.',
Ch='Charayi:BAAANQADCggICAABNQAECgYICgAGAAAAAA==.Chardaney:BAAANQAECgYICgAAAA==.Cheery:BAAANQABCgcIFQABNQAECgkJMAAFAMEVAA==.Chickennuggi:BAABNQAECn8YAAIUAAcKwyCpDQAkAgAUAAcKwyCpDQAkAgABNQAECgkJJQAQAIgjAA==.',
Ci='Cii:BAABNQAECn8wAAMKAAkKtRMSHwBBAQAKAAcKwxUSHwBBAQABAAYKsQZt+gC3AAAAAA==.Ciine:BAAANQADCgYICQABNQAECgkJMAAKALUTAA==.Ciinelock:BAAANQADCgIIAgABNQAECgkJMAAKALUTAA==.Cindreth:BAAANQADCgEIAQAAAA==.Ciruzita:BAAANQADCgUIBQAAAA==.',
Cl='Clampz:BAEANQAECgUIBwABNQAFFAcIFAATAD0eAA==.',
Co='Colabrn:BAAANQADCggIFwAAAA==.Colandros:BAAANQADCgEIAQAAAA==.Colara:BAABNQAECn8jAAIHAAkKngykIgBQAQAHAAkKngykIgBQAQAAAA==.Colbear:BAAANQADCgEIAQAAAA==.Coldspace:BAABNQAECn9PAAIBAAoKdSDdGQBdAwABAAoKdSDdGQBdAwAAAA==.Corlock:BAAANQADCgEIAQAAAA==.',
Cr='Crassberry:BAACNQAFFH8MAAIVAAcKMxUCDABNAQAVAAcKMxUCDABNAQA1AAQKfyYAAhUACgqgJEkkALACABUACgqgJEkkALACAAAA.Creepindeath:BAAANQAECgEIAgAAAA==.',
Cu='Cucaracha:BAAANQAECgYICgAAAA==.',
Cy='Cyndal:BAAANQADCggIHwABNQAECgYICgAGAAAAAA==.Cyndle:BAAANQADCggIJAABNQAECgYICgAGAAAAAA==.',
Da='Dankbuds:BAAANQAECggIDwAAAA==.Dankothy:BAAANQAECgQICAABNQAECggIDwAGAAAAAA==.Dantes:BAAANQAECgEJAQAAAA==.Darkryu:BAAANQADCgYIEAAAAA==.Darkspace:BAABNQAECn8XAAQWAAoKcRVRBACbAQAWAAcKkBdRBACbAQANAAQKFhBBFQD2AAAXAAYKigkLpgDUAAABNQAECgoKTwABAHUgAA==.Darthsix:BAAANQADCgEIAQAAAA==.Dawnßreaker:BAAANQADCgEIAQAAAA==.Dazex:BAAANQAECgUIDgAAAA==.',
De='Deadbolt:BAAANQAECgYIDwAAAA==.Deathforever:BAAANQAECgQIBAAAAA==.Deaus:BAAANQADCggIFgAAAA==.Delrus:BAABNQAECn8xAAQDAAoKOh4dCQAHAwADAAoKOh4dCQAHAwAYAAUKMBB8UQCsAAAUAAQKCBD9PgCTAAAAAA==.Demon:BAABNQAECn9DAAMEAAoKlCACDQBBAwAEAAoKlCACDQBBAwAZAAMK0RqFGgCRAAABNQAFFAgIIQATAGgRAA==.Demoniec:BAAANQAECgQIBQAAAA==.Demowneege:BAAANQADCggICAABNQAFFAcIGAAFAJYeAA==.Denzvic:BAAANQAECgYICwAAAA==.Destro:BAAANQADCggICAAAAA==.Devil:BAAANQADCgEIAQAAAA==.',
Di='Diddyjr:BAABNQAECn8mAAIOAAoK0Ru7fACFAgAOAAoK0Ru7fACFAgAAAA==.Disowneege:BAAANQAECgcIDAABNQAFFAcIGAAFAJYeAA==.Diyos:BAAANQADCggICAAAAA==.',
Do='Doodu:BAAANQAFFAEIAQAAAA==.',
Dr='Dragnas:BAABNQAECn88AAQCAAoKAhH4EQBKAgACAAoKAhH4EQBKAgAMAAQKuxJrvADyAAARAAEKHg5NLgE6AAAAAA==.Dragonisa:BAAANQAECgMIAwAAAA==.Draiocht:BAAANQADCgQIBwABNQAECggIIAALAGIaAA==.Dramakiller:BAAANQAECgYIEAAAAA==.Drcornbread:BAABNQAECn8UAAMaAAUK8w7dIAAOAQAaAAUKhQ7dIAAOAQAUAAQKCAy5QwCmAAAAAA==.Drcornellia:BAAANQADCgYIBwABNQAECgUIFAAaAPMOAA==.Drdreggs:BAABNQAECn8kAAMXAAoK2hEzhADbAQAXAAkKixEzhADbAQAWAAEKBhTVcQA9AAAAAA==.Drop:BAAANQADCgQIBQABNQAECgoKQAABAF0fAA==.Druduwolf:BAAANQAECgcIEAAAAA==.',
Du='Durden:BAAANQADCgIIAwABNQAECgYIEAAGAAAAAA==.Dustyhunter:BAAANQAECgEIAQAAAA==.Duthalemar:BAAANQADCggICgABNQAECgoKQwAEAGYjAA==.',
Ea='Eatbuttforpi:BAAANQADCgUIBwABNQAFFAEIAQAGAAAAAA==.',
El='Elastar:BAABNQAECn88AAIbAAoKhxkyBwBEAgAbAAoKhxkyBwBEAgAAAA==.Elgrunto:BAAANQADCgEIAQAAAA==.Ellimist:BAEANQAECgcIDAAAAA==.Elsan:BAAANQADCgQIBQAAAA==.Elycee:BAABNQAECn8jAAMIAAoKoSNNDAATAwAIAAoKoSNNDAATAwAcAAoK9RDZFAC7AQAAAA==.',
Em='Emura:BAAANQAECgMIBAAAAA==.',
En='Enveliria:BAAANQAECgUIDgABNQAECgoKQwAEAGYjAA==.',
Er='Eraser:BAABNQAECn8/AAMLAAoKeRM/ZADzAQALAAoKeRM/ZADzAQAdAAgK0g6BHgBbAQAAAA==.Erazar:BAABNQAECn8dAAIeAAgK+QccEAAHAQAeAAgK+QccEAAHAQAAAA==.Erickk:BAABNQAECn85AAIOAAoKrRqgTgDkAgAOAAoKrRqgTgDkAgAAAA==.Eristela:BAAANQAECgEIAgAAAA==.',
Es='Escanorlion:BAAANQAECgUIBwAAAA==.Essense:BAABNQAECn88AAILAAoKSyW8AgD9AwALAAoKSyW8AgD9AwAAAA==.',
Ev='Evokedcat:BAAANQAECgcIDgAAAA==.',
Ex='Exodari:BAABNQAECn89AAICAAoKzA9vDwDkAQACAAoKzA9vDwDkAQAAAA==.Extro:BAAANQAECgQIBAAAAA==.',
Fa='Fabbioh:BAAANQADCgEIAQAAAA==.Fadeddh:BAAANQAECgUIBwABNQAFFAEIAQAGAAAAAA==.Faeliendra:BAAANQADCggICAAAAA==.Fangloria:BAAANQABCggIEwABNQAECgkJMAAFAMEVAA==.Fatalgrip:BAAANQADCgUIBgAAAA==.',
Fe='Fel:BAABNQAECn9UAAMEAAoKFCS8BgCLAwAEAAoKrCO8BgCLAwAHAAoKOyLKBwDDAgAAAA==.Fellius:BAAANQADCgQIBAAAAA==.Fellkarras:BAAANQAECgUICAABNQAECgkJJQAQAIgjAA==.Felprincess:BAAANQADCgEIAQAAAA==.',
Fi='Fibitz:BAAANQAECgcIDQABNQAECgoKLQAIAJohAA==.Fiddich:BAAANQAECgQIBQAAAA==.Findstewie:BAAANQADCgEIAwABNQADCgEIAwAGAAAAAA==.Fiofio:BAABNQAECn86AAIOAAoKVRyEMQBcAgAOAAoKVRyEMQBcAgAAAA==.Fizban:BAABNQAECn8bAAMfAAgKtQzxDwCoAQAfAAgKtQzxDwCoAQAOAAQK+AEimwGQAAAAAA==.',
Fl='Flik:BAAANQAECgUICAABNQAECgoKVAALAGUdAA==.',
Fo='Foringojr:BAAANQAECgIIAgAAAA==.',
Fr='Fragglelock:BAAANQABCggIFQABNQAECgkJMAAFAMEVAA==.Frigidheart:BAAANQAECgUIDAABNQAECgcIDwAGAAAAAA==.Frostetute:BAABNQAECn8bAAIOAAgKugyjiABnAQAOAAgKugyjiABnAQAAAA==.',
Fu='Furrybawlz:BAAANQADCggICAABNQAECgQIBAAGAAAAAA==.',
['Fà']='Fàllén:BAAANQAECgEIAwABNQAFFAQICgAIAPwSAA==.',
Ga='Gadogear:BAABNQAECn8fAAIfAAgKNhebDACGAQAfAAgKNhebDACGAQAAAA==.Galabren:BAAANQAECgYJDQAAAA==.Garlik:BAAANQADCgUIDQAAAA==.',
Ge='Gertra:BAAANQAECgcIDwAAAA==.',
Gf='Gfr:BAABNQAECn8ZAAMWAAcKQhu3BQBdAQAWAAcKQhu3BQBdAQAXAAEKAABlGgEAAAAAAA==.',
Gi='Giddoo:BAAANQAECgYICwAAAA==.Gilnean:BAAANQADCgEIAQAAAA==.',
Gn='Gnowanceyi:BAAANQAECgIIAwABNQAECgoKOQAOAK0aAA==.',
Go='Goatcheeze:BAAANQAECgcIDQAAAA==.Gohlemsaurus:BAAANQADCggIJgAAAA==.',
Gr='Gratfldeadly:BAAANQADCgEIAQABNQADCggIHAAGAAAAAA==.',
Gu='Gulen:BAAANQADCggIGwAAAA==.Gullee:BAAANQADCgEIAQAAAA==.',
Gw='Gwennevier:BAAANQADCgEIBQAAAA==.',
['Gí']='Gíga:BAAANQAECgMIAwAAAA==.',
Ha='Halsten:BAABNQAECn8fAAQfAAgKsANlGwDJAAAfAAgKsANlGwDJAAAOAAUKswFwmgGRAAAgAAEKAACYDwAhAAAAAA==.Hamish:BAAANQAECgEIAQAAAA==.',
He='Hellenkeller:BAEANQAFFAEIAQABNQAFFAcIFAATAD0eAA==.Heloisa:BAAANQADCgYIBgAAAA==.Helrazor:BAAANQADCgUIBQABNQAECgoKJgAaAOQYAA==.',
Hi='Hitt:BAAANQAECgYICgAAAA==.',
Ho='Hogwortsfun:BAAANQADCggICAAAAA==.Holysudz:BAAANQADCgIIAgAAAA==.Hoofingit:BAAANQAECgUIBQAAAA==.',
Hr='Hroc:BAABNQAECn8VAAISAAkKHAkZRQCyAQASAAkKHAkZRQCyAQAAAA==.',
Hu='Hunterboi:BAAANQAECgEIAQAAAA==.',
Ic='Icedlatte:BAAANQADCgUIDwAAAA==.Icywolfy:BAAANQAECgIIAgAAAA==.',
Ig='Igreetyou:BAAANQAECgQICQAAAA==.',
Il='Illune:BAABNQAECn8sAAIOAAoKNhTBSQALAgAOAAoKNhTBSQALAgAAAA==.',
Im='Imleapingit:BAABNQAECn8fAAIhAAgKJBgkVQDKAQAhAAgKJBgkVQDKAQAAAA==.Imrelentless:BAAANQADCgEIAQAAAA==.',
In='Inaurian:BAAANQADCggICAAAAA==.Intoodeep:BAABNQAECn9GAAISAAoKuhntBwBHAgASAAoKuhntBwBHAgAAAA==.',
Ir='Ir:BAABNQAECn9WAAIOAAoKzhwfPQAMAwAOAAoKzhwfPQAMAwAAAA==.Ironfoot:BAAANQAECgQIBAAAAA==.Irrlvntgobbo:BAAANQAECgYICwAAAA==.',
Is='Isasham:BAAANQAECgIIAgAAAA==.Isawarriorr:BAABNQAECn8eAAMhAAkKshkqXgByAgAhAAkKmRcqXgByAgAbAAIK0Rv1NACOAAAAAA==.Ishdo:BAABNQAECn8fAAIQAAgKPAwwYQBtAQAQAAgKPAwwYQBtAQAAAA==.Ishdu:BAAANQADCgYIBgABNQAECggIHwAQADwMAA==.Ishlok:BAAANQADCgUIBQABNQAECggIHwAQADwMAA==.Ishmael:BAAANQAECgQIBQABNQAFFAQICgAIAPwSAA==.Ishwar:BAAANQADCggIGAABNQAECggIHwAQADwMAA==.',
Iv='Ivanhöe:BAAANQAECgEIAQAAAA==.',
Ja='Jakytreehorn:BAABNQAECn8UAAIRAAgKZBDVZwDpAQARAAgKZBDVZwDpAQAAAA==.Jaydm:BAAANQAECgYICQABNQAFFAYIDwAOAFIVAA==.',
Je='Jenevelle:BAAANQAECgMJAwAAAA==.Jerisil:BAAANQADCgUICAAAAA==.Jessiel:BAAANQAECgUIBAAAAA==.Jet:BAABNQAECn9AAAIBAAoKXR+7IgCzAgABAAoKXR+7IgCzAgAAAA==.',
Ju='Judgiah:BAAANQAECgIIAgAAAA==.Julthaenia:BAABNQAECn8uAAINAAkKZxjVAwCwAgANAAkKZxjVAwCwAgABNQAECgoKQwAEAGYjAA==.Junjia:BAAANQADCgUIBQAAAA==.',
Ka='Kagebushin:BAAANQADCgEIAQAAAA==.Kagome:BAAANQADCggIDQABNQAECgYICgAGAAAAAA==.Kalofelement:BAAANQADCgEIAgAAAA==.Kaluth:BAAANQADCgEIAQABNQAECgcIDwAGAAAAAA==.Kalysy:BAAANQAECgEIAQABNQAECgoKQwAEAGYjAA==.Karash:BAAANQAECgYIEAAAAA==.Kargush:BAAANQADCgQIBAABNQADCggIFwAGAAAAAA==.Karmaisab:BAAANQAECggIAQAAAA==.Karnrae:BAABNQAECn8nAAIBAAoKhhbQTQAMAgABAAoKhhbQTQAMAgAAAA==.Karynos:BAABNQAECn8wAAIXAAoKVRCHgADlAQAXAAoKVRCHgADlAQAAAA==.Katwolf:BAABNQAECn8ZAAIIAAgKywyPhABnAQAIAAgKywyPhABnAQAAAA==.Katyah:BAABNQAECn8XAAIMAAgKCAfIlgBOAQAMAAgKCAfIlgBOAQAAAA==.Kavourkaa:BAAANQADCgEIAQAAAA==.',
Ke='Keynivas:BAAANQAECgIIAgAAAA==.',
Ki='Killiua:BAAANQAECgcICwAAAA==.Killspriest:BAAANQADCgEIAQAAAA==.',
Ko='Kobayashi:BAAANQAECgUIBQABNQAECgkJMAAFAMEVAA==.Konspiracy:BAABNQAECn8cAAMWAAkKuRJADwAHAgAWAAkKuRJADwAHAgAXAAEKAAAfTAErAAAAAA==.',
Kr='Kraguva:BAAANQAECgYIBAAAAA==.Krataar:BAAANQAECgEIAQABNQAECgYIDQAGAAAAAA==.Kroot:BAABNQAECn8tAAIIAAoKmiEWEQDwAgAIAAoKmiEWEQDwAgAAAA==.Krous:BAACNQAFFH8UAAIhAAcKOxtnBwCVAQAhAAcKOxtnBwCVAQA1AAQKfysAAiEACgrEHxBPAJwCACEACgrEHxBPAJwCAAAA.Kryph:BAAANQAECgcIEAAAAA==.',
['Kä']='Kämpfer:BAAANQAECgcICwABNQAECgoKLwAiAJIUAA==.',
La='Lafiel:BAABNQAECn81AAILAAoKohEkPgAJAgALAAoKohEkPgAJAgAAAA==.Landiedoo:BAAANQAECggIAQAAAA==.Latrank:BAAANQAECgYIBwAAAA==.Laurandre:BAABNQAECn8rAAMDAAkKDgfkMAAjAQADAAkKDgfkMAAjAQAYAAIK3AOShgAgAAAAAA==.Lazeras:BAAANQAECgUICAABNQAECgoKJgAaAOQYAA==.',
Le='Letsgetwet:BAAANQAECgQIBgAAAA==.',
Li='Liefic:BAABNQAECn8xAAIIAAoKFSCUEwDfAgAIAAoKFSCUEwDfAgAAAA==.Lilibeth:BAAANQADCggICgAAAA==.Lilienne:BAAANQABCgYIBwAAAA==.Lilstooge:BAAANQADCgEIAwABNQADCgEIAwAGAAAAAA==.Limon:BAAANQAECgcICQAAAA==.',
Ll='Llylith:BAAANQABCgMIBAAAAA==.',
Lo='Locke:BAAANQAECgcICAABNQAECgoKQAABAF0fAA==.',
Lu='Luckykilla:BAABNQAECn80AAISAAoKYBhbCgAIAgASAAoKYBhbCgAIAgAAAA==.Lucÿ:BAACNQAFFH8KAAIMAAQKUxgNEAAWAQAMAAQKUxgNEAAWAQA1AAQKfy0AAwwACgqzHuQjANcCAAwACgqzHuQjANcCABEABgp7EmyYAGgBAAAA.Luffsong:BAAANQADCgEIAQAAAA==.Lune:BAAANQADCgUICwAAAA==.Lurith:BAABNQAECn9FAAMVAAkKvRYoMgAvAQAVAAcK9RcoMgAvAQAQAAgKHA87RAAEAQAAAA==.Luxtyrannica:BAAANQAECgcIDwAAAA==.',
Ly='Lydrain:BAAANQAECgQIBQAAAA==.Lylia:BAAANQADCggIGAAAAA==.',
Ma='Malcolm:BAAANQABCgYIDAABNQAECgkJMAAFAMEVAA==.Marahh:BAAANQADCgEIAQAAAA==.Matt:BAAANQAECgQIBAABNQAFFAgIIQATAGgRAA==.Mattbolt:BAABNQAECn8ZAAICAAkKNiEDDwB6AgACAAkKNiEDDwB6AgAAAA==.Maximoose:BAACNQAFFH8KAAIIAAQK/BKDEQBIAQAIAAQK/BKDEQBIAQA1AAQKfx0AAggACgo/GXhHAJYCAAgACgo/GXhHAJYCAAAA.Mayu:BAAANQADCggIHAAAAA==.Mayumey:BAAANQADCgUIBgAAAA==.Mazigos:BAAANQAECgYIBQAAAA==.',
Me='Medjrab:BAABNQAECn9DAAIVAAoK1iJ8CQByAwAVAAoK1iJ8CQByAwAAAA==.Mefi:BAAANQADCgcIFgAAAA==.Melyria:BAABNQAECn8eAAIHAAgKzA1EMwCoAQAHAAgKzA1EMwCoAQAAAA==.Meristem:BAABNQAECn8kAAIYAAgKSAzxNwAfAQAYAAgKSAzxNwAfAQAAAA==.Merko:BAAANQADCggICgABNQAECgoKLQAIAJohAA==.',
Mi='Mignius:BAAANQADCgYIBgAAAA==.Mihonk:BAAANQAECgUIBQAAAA==.Millesfavdom:BAABNQAECn8UAAIEAAkKzg5TIgC8AQAEAAkKzg5TIgC8AQABNQAFFAcIEwAUAN0PAA==.Misafarm:BAAANQADCgIIAgAAAA==.Mistified:BAAANQADCgEIAQAAAA==.',
Mo='Moedorai:BAAANQAECggIEQAAAA==.Mogma:BAAANQAECgUICQAAAA==.Mogsarren:BAAANQABCgIIAgABNQAECgoKUQAQAL8lAA==.Momentomori:BAAANQADCgUIDAAAAA==.Mondgrille:BAAANQAECgQIBAAAAA==.Monora:BAAANQADCggICQAAAA==.Moonbounds:BAACNQAFFH8TAAIMAAcKSxoGBgAIAgAMAAcKSxoGBgAIAgA1AAQKf1EAAgwACgrSI5kFAJoDAAwACgrSI5kFAJoDAAAA.Moondoggey:BAAANQADCgUIBgAAAA==.Moonshift:BAAANQADCgEIAQAAAA==.Morgana:BAAANQADCgYICAAAAA==.Morzanna:BAAANQADCgEIAQAAAA==.Mousechief:BAABNQAECn8fAAIRAAcKFAN9kQCwAAARAAcKFAN9kQCwAAAAAA==.Moxxzi:BAABNQAECn8pAAIVAAcK9hFFKgBgAQAVAAcK9hFFKgBgAQAAAA==.',
Mu='Muhfookinbak:BAABNQAECn8nAAQRAAoKEyIRIgABAwARAAoKEyIRIgABAwACAAEKixM8LgBBAAAMAAEKUxD2FwE7AAAAAA==.Musk:BAAANQADCgEIAQAAAA==.',
Na='Naksu:BAAANQADCgYJFwABNQAECgkJKQALADshAA==.Naksù:BAAANQADCgUIBgABNQAECgkJKQALADshAA==.Naksü:BAABNQAECn8pAAILAAkKOyERHwCzAgALAAkKOyERHwCzAgAAAA==.Naturescurse:BAAANQADCgEIAQAAAA==.',
Ne='Neifeb:BAABNQAECn8pAAIIAAkKUxHxggAGAgAIAAkKUxHxggAGAgAAAA==.Nerfherder:BAAANQADCgEIAQABNQAECgkJMAAFAMEVAA==.',
Ni='Niallivdam:BAAANQAECgQIDwAAAA==.Nights:BAAANQAECgIIAwABNQAFFAgIIQATAGgRAA==.Ninh:BAABNQAECn9WAAIjAAoKPw6AEQCxAQAjAAoKPw6AEQCxAQAAAA==.Nintendopsp:BAAANQAECgIIAgAAAA==.Ninthgate:BAABNQAECn8aAAIXAAYKcAWZ4QAGAQAXAAYKcAWZ4QAGAQAAAA==.',
No='Noble:BAABNQAECn8yAAMHAAoKmBTcEQAQAgAHAAoKmBTcEQAQAgAEAAEKuQa/dwAvAAAAAA==.Nogood:BAABNQAECn8ZAAIhAAoKRRYzaQBVAgAhAAoKRRYzaQBVAgAAAA==.Notsodemon:BAAANQAECgQICAABNQAECgcIFQAOAJsLAA==.Notsomage:BAABNQAECn8VAAIOAAcKmwsDAwGJAQAOAAcKmwsDAwGJAQAAAA==.',
Ny='Nyorai:BAAANQADCgEIAgAAAA==.Nyxwing:BAAANQAECgYIBQAAAA==.',
['Nå']='Nåld:BAAANQAECgEIAQAAAA==.',
['Në']='Nëao:BAAANQADCgYIBwAAAA==.',
Ob='Obvinotagirl:BAABNQAECn8yAAMDAAkKRyG6BgBDAwADAAkKRyG6BgBDAwAYAAEKAAC3xwAaAAAAAA==.',
Od='Oddone:BAAANQAECgEIAgAAAA==.Oddpocalypse:BAAANQADCgQIBAAAAA==.Odelina:BAAANQADCggIDgAAAA==.Odinheâthen:BAAANQADCgYJDAAAAA==.',
Ok='Okrawindfury:BAAANQABCggIGAABNQAECgkJMAAFAMEVAA==.',
Ol='Olydwarf:BAAANQAECgEIAQAAAA==.',
On='Onebadmutha:BAABNQAECn8VAAIXAAcKgwlljgAIAQAXAAcKgwlljgAIAQAAAA==.Ontop:BAABNQAECn9WAAIIAAoK6x4kKAD3AgAIAAoK6x4kKAD3AgAAAA==.',
Or='Orb:BAAANQAECgEIAQAAAA==.Ortinks:BAABNQAECn8oAAMfAAgKqxUuDQDgAQAfAAgKqxUuDQDgAQAOAAMK1wV1swFaAAAAAA==.',
Ow='Owneege:BAACNQAFFH8YAAMFAAcKlh4fAADCAQAFAAcKCRsfAADCAQAhAAUKYRo7EgCeAQA1AAQKfzgAAyEACgooJLgmAIQCACEACgrpH7gmAIQCAAUACQq0IoEIANkBAAAA.',
Pa='Paapaa:BAABNQAECn8UAAITAAoK6BXBIwBHAgATAAoK6BXBIwBHAgAAAA==.Pallideaus:BAABNQAECn8dAAIJAAcKayGTLwCoAgAJAAcKayGTLwCoAgAAAA==.Pallinar:BAAANQAECggIEQAAAA==.Pandamak:BAAANQADCggICAAAAA==.Paradoxx:BAAANQADCgIIBAAAAA==.Pasquale:BAAANQAECgUIBwAAAA==.Pauzhaan:BAAANQAECgUICQABNQAECgkJMAAFAMEVAA==.',
Pe='Pebbles:BAABNQAECn9FAAIBAAoKJhY/WADuAQABAAoKJhY/WADuAQAAAA==.Pedorus:BAAANQADCgEIAgABNQAFFAQICgAMAFMYAA==.Penjerman:BAAANQAFFAEIAQAAAA==.',
Pi='Picklericky:BAAANQADCggIEgAAAA==.Pilgrimm:BAECNQAFFH8UAAITAAcKPR7uAQA4AgATAAcKPR7uAQA4AgA1AAQKfy8ABBMACgoTJZ4DAGUDABMACgoTJZ4DAGUDACQAAQq5G4YZAEwAABIAAQpBC42gADoAAAAA.Pinxyl:BAAANQADCgEIAQAAAA==.Pistola:BAAANQAECgQIBAAAAA==.Pix:BAAANQABCgQIBwAAAA==.Pixyl:BAAANQADCggIHAAAAA==.',
Pl='Plaguerott:BAABNQAECn8YAAIPAAcKsgVSYgAbAQAPAAcKsgVSYgAbAQAAAA==.Plaguewind:BAAANQAECgEIAgAAAA==.',
Po='Polydh:BAABNQAECn8yAAIZAAoKYSQJAQC1AwAZAAoKYSQJAQC1AwAAAA==.Poobah:BAABNQAECn8iAAMRAAgKkQfrwgAMAQARAAcKTQjrwgAMAQAMAAIKrgI41ABHAAAAAA==.Popsicles:BAABNQAECn8lAAMlAAkKixYqBgAyAgAlAAkKixYqBgAyAgAdAAEKAADjigAfAAAAAA==.Potrat:BAAANQAECgMJAwAAAA==.Pouffant:BAAANQAECgUICgAAAA==.',
Pr='Praddagy:BAAANQADCgUIBwAAAA==.Prayoncè:BAAANQADCggIDwAAAA==.Pronoz:BAAANQAECggIDwAAAA==.',
Pu='Puffr:BAAANQADCgQIBAAAAA==.Purpyl:BAAANQAECgcIEQAAAA==.',
Pw='Pwnageddon:BAAANQAECgMIAwAAAA==.Pwnjitsu:BAABNQAECn87AAImAAoKBx7NCQCjAgAmAAoKBx7NCQCjAgAAAA==.',
Py='Pyrothermia:BAACNQAFFH8PAAIOAAYKUhWIDgADAgAOAAYKUhWIDgADAgA1AAQKfzMAAw4ACgquIhoRAPYCAA4ACgquIhoRAPYCAB8AAwr+BIsyAHEAAAAA.',
Ra='Rakugan:BAAANQADCgEIAQAAAA==.Rawhoof:BAABNQAECn9WAAIhAAoK7SJyGADSAgAhAAoK7SJyGADSAgAAAA==.Razak:BAABNQAECn8/AAICAAoKOh8UBgAlAwACAAoKOh8UBgAlAwAAAA==.',
Rd='Rdnckromeo:BAAANQAECgQIBAAAAA==.',
Re='Redlock:BAABNQAECn8lAAIWAAgKlAtXCAAbAQAWAAgKlAtXCAAbAQAAAA==.Redrum:BAABNQAECn8lAAIQAAkKiCMZCwBbAwAQAAkKiCMZCwBbAwAAAA==.Reineken:BAAANQADCggICwAAAA==.Renarin:BAABNQAECn9UAAILAAoKZR19IADtAgALAAoKZR19IADtAgAAAA==.Renisa:BAABNQAECn8gAAMHAAgKvxX6JgANAgAHAAgKvxX6JgANAgAEAAEKMwb6nAAlAAAAAA==.Renobagem:BAAANQADCgUIBgAAAA==.Retman:BAAANQADCggIEAAAAA==.Reu:BAAANQAECgcICgAAAA==.Revlyk:BAABNQAECn8pAAMCAAoKKhdBDwB1AgACAAoKKhdBDwB1AgAMAAEKDxR02QA9AAABNQAECgoKQwAEAGYjAA==.',
Rh='Rhoanna:BAAANQAECgQIBAAAAA==.Rhoupert:BAABNQAECn8WAAIBAAgK6xVhmQDwAQABAAgK6xVhmQDwAQAAAA==.',
Ro='Roccot:BAABNQAECn8/AAIQAAoKrSGWBwD/AgAQAAoKrSGWBwD/AgAAAA==.Rotfather:BAAANQADCgcICAAAAA==.Rotjaw:BAAANQADCggIDQAAAA==.Roughedge:BAAANQADCgIIAgAAAA==.',
Rv='Rvn:BAAANQAECgUICQAAAA==.',
Ry='Ryppyr:BAAANQADCggICAAAAA==.',
['Rè']='Rèjuva:BAAANQADCgEIAQAAAA==.',
Sa='Saintess:BAAANQADCgEIAQAAAA==.Sallanu:BAAANQAECgEIAQAAAA==.Saramushan:BAAANQADCgEIAQAAAA==.Sardencreian:BAAANQAECggICAABNQAECgoKJgAOANEbAA==.Sauron:BAAANQAECgUICAAAAA==.',
Sc='Scalycat:BAAANQAECgcIDwAAAA==.Scum:BAAANQADCgcIDQABNQAECgQIBAAGAAAAAA==.',
Se='Senate:BAABNQAECn8/AAMRAAoKwBPvLgDoAQARAAoKwBPvLgDoAQAMAAEKqgFVMQEfAAAAAA==.Servenslay:BAAANQADCggIDgAAAA==.',
Sh='Shaamazing:BAAANQADCgEIAQAAAA==.Shablaam:BAAANQAECgIIAwAAAA==.Shadowbear:BAABNQAECn8jAAIdAAkKihUPFQDSAQAdAAkKihUPFQDSAQAAAA==.Sherrilyn:BAAANQAECgEIAQAAAA==.Shifdiah:BAAANQAECgUICgAAAA==.Shocktherapi:BAAANQAECgcIDAAAAA==.Shrimpback:BAAANQAECgIIAQAAAA==.',
Si='Singularity:BAAANQAECgQJBQAAAA==.',
Sk='Skelli:BAECNQAFFH8bAAILAAcKlRIjCADvAQALAAcKlRIjCADvAQA1AAQKfyMAAgsACgo/HI47AHsCAAsACgo/HI47AHsCAAE1AAQKBwgMAAYAAAAA.Skittlesdan:BAABNQAECn8mAAQXAAoKYhLSfgDpAQAXAAoKYhLSfgDpAQANAAEKAAB/MgAvAAAWAAEKxQQWgwAoAAAAAA==.',
Sl='Slaykween:BAABNQAECn8dAAIKAAgKxAQmOwCTAAAKAAgKxAQmOwCTAAAAAA==.',
Sm='Smallz:BAAANQAECgUIBQABNQAECggIGwAfALUMAA==.',
Sn='Sneakin:BAAANQADCgIIAgAAAA==.Snooptrogg:BAABNQAECn8wAAQFAAkKwRURDwC8AQAFAAYK6xgRDwC8AQAhAAgKAw++ugCKAQAbAAUK8A/KJQCaAAAAAA==.',
So='Something:BAAANQABCggIEwABNQAECgkJMAAFAMEVAA==.Soryu:BAAANQAECgIIAgAAAA==.',
Sp='Spacelaser:BAAANQADCgMIAwAAAA==.Specialtwo:BAAANQADCgEIAQAAAA==.',
Sq='Sqwurl:BAAANQADCgUIBQAAAA==.',
St='Steakhaus:BAAANQAECgIIAgAAAA==.Stonedragon:BAECNQAFFH8PAAIIAAUKMxdxDgD3AAAIAAUKMxdxDgD3AAA1AAQKf1YAAggACgqNJaoFALQDAAgACgqNJaoFALQDAAAA.Stormfang:BAAANQADCgcIFAABNQAECgYIEgAGAAAAAA==.Stormfist:BAAANQADCgQIBgAAAA==.Stormhaven:BAAANQADCgQJBAABNQAECgYIEgAGAAAAAA==.Stormrender:BAAANQAECgUICgAAAA==.Stormriders:BAABNQAECn8yAAIRAAkKJQ/pTgBiAQARAAkKJQ/pTgBiAQAAAA==.Stouty:BAAANQADCgQIAQAAAA==.Streea:BAAANQADCggIIQABNQAECgYICgAGAAAAAA==.Stubz:BAAANQADCgEIAQAAAA==.',
Su='Sugi:BAAANQAECgcICgABNQAFFAQIBwAHALkQAA==.Sukonamí:BAABNQAECn8iAAIhAAoKFBREQwAIAgAhAAoKFBREQwAIAgAAAA==.Suzhou:BAABNQAECn8aAAIWAAgKrQbcCwDdAAAWAAgKrQbcCwDdAAAAAA==.Suzoomies:BAAANQADCggIEAAAAA==.',
Sw='Swisscheese:BAABNQAECn8eAAMXAAkKqBomXABDAgAXAAkKqBomXABDAgAWAAEKLwpLewAyAAAAAA==.Swoopyboop:BAAANQADCgQIBAAAAA==.',
Sy='Sybaek:BAAANQAECggIDQAAAA==.Sycò:BAABNQAECn8sAAMIAAkKGyOaEgBVAwAIAAkKGyOaEgBVAwAcAAEKkQF3ngAgAAAAAA==.Syraxa:BAAANQAECgMIBAABNQAECgoKQwADAKMbAA==.',
['Sú']='Súbzerø:BAAANQAECgEIAQABNQAFFAQICwAIAJcTAA==.',
Ta='Taedish:BAAANQAECgEIAQAAAA==.Tahzdingle:BAAANQADCgYICwAAAA==.Talorien:BAAANQADCgIIAgABNQAECgoKLAAOADYUAA==.Tannith:BAAANQADCgIIAgABNQADCgEIAwAGAAAAAA==.Tayy:BAAANQADCgYICwAAAA==.',
Te='Teknobutts:BAAANQADCgUIBQAAAA==.Telan:BAAANQADCgUIBQAAAA==.Tempertotems:BAAANQADCggIDQAAAA==.Tenastin:BAAANQADCgQIBQAAAA==.Terragosa:BAABNQAECn8iAAMOAAgK0xWogAB5AQAOAAgKARSogAB5AQAfAAIKFwwBNwBgAAAAAA==.Tetchybono:BAAANQAECgYIEgAAAA==.Tettra:BAAANQADCggIEgABNQAECgYICgAGAAAAAA==.',
Th='Thaeleon:BAAANQAECgMIAwABNQAFFAQICgAIAPwSAA==.Thahawtz:BAAANQADCgYIDQAAAA==.Thirinis:BAAANQAECggIEwAAAA==.Thope:BAAANQADCgYIFgAAAA==.Thrivia:BAAANQAECggICQAAAA==.Thundergirl:BAAANQAECggICgAAAA==.',
Ti='Ticklemychin:BAAANQADCgcIDAAAAA==.',
Tl='Tlàchtga:BAAANQAECgUIBgAAAA==.',
To='Toughasnails:BAAANQAECgEIAQAAAA==.',
Tr='Traesdyne:BAAANQADCgQIBQAAAA==.Trailwalkur:BAAANQADCgYIDAABNQAECgoKJgAaAOQYAA==.Trainar:BAAANQAECgUIDQABNQAECgcIGgAEADEaAA==.Triggs:BAAANQAECggIBwAAAA==.Troggdor:BAAANQADCgEIAQABNQAECgkJMAAFAMEVAA==.Trollbear:BAAANQADCgcICAAAAA==.Trooze:BAAANQAECgYIEQAAAA==.Truckz:BAABNQAECn8cAAIRAAoKkxM7LAD2AQARAAoKkxM7LAD2AQAAAA==.Truckzbrr:BAAANQAECgEIAQABNQAECgoKHAARAJMTAA==.Trõnlight:BAAANQAECgEIAQAAAA==.',
Ts='Tsunah:BAAANQADCgYIBgAAAA==.',
Tu='Tuba:BAAANQAECgEIAQAAAA==.Turim:BAAANQAECgEIAQAAAA==.',
Ty='Tyrawick:BAAANQAECgYIBgAAAA==.Tyrlidd:BAABNQAECn8lAAIIAAgKJgg/mwA3AQAIAAgKJgg/mwA3AQAAAA==.',
Un='Unavoidable:BAAANQADCgMIAwAAAA==.Unlikelytale:BAABNQAECn8yAAMMAAoKcxzFKQC8AgAMAAoKcxzFKQC8AgARAAEKRxbRJgFEAAAAAA==.Unredeemed:BAAANQADCgEIAQAAAA==.',
Ur='Urbanmeyer:BAAANQAECgMIBQAAAA==.Uricash:BAABNQAECn9JAAIOAAoKJB4yJwCGAgAOAAoKJB4yJwCGAgAAAA==.Urrax:BAAANQADCgEIAgABNQADCgIIAgAGAAAAAA==.Urzual:BAABNQAECn8uAAMCAAkK6R2BDACoAgACAAkK6R2BDACoAgAMAAYKbhSCigBvAQAAAA==.',
Ut='Utini:BAAANQAECgEIAQAAAA==.',
Va='Vandreynna:BAABNQAECn9DAAIEAAoKZiNbBgCQAwAEAAoKZiNbBgCQAwAAAA==.',
Ve='Vehlrine:BAAANQADCgIIAgAAAA==.Velsiana:BAAANQAECgMIAwAAAA==.Velveetah:BAAANQADCgYIBwABNQAECgUIFAALANsTAA==.Venasia:BAAANQADCgYIBgABNQAECgoKQwAEAGYjAA==.Verbren:BAAANQAECgcICAABNQAECgoKLwAiAJIUAA==.Verbrennen:BAABNQAECn8vAAIiAAoKkhQeGgAhAgAiAAoKkhQeGgAhAgAAAA==.Verita:BAAANQAECgQIBgAAAA==.Verlynne:BAAANQADCgcIBwAAAA==.Vetinari:BAAANQABCggIGwABNQAECgkJMAAFAMEVAA==.',
Vi='Viviann:BAABNQAECn85AAMiAAoKUgtQEAC9AQAiAAoKUgtQEAC9AQAeAAYKPAlEIwArAQAAAA==.',
Vo='Von:BAAANQADCgEIAQAAAA==.',
Wa='Walee:BAAANQADCgIIAgAAAA==.Walfred:BAAANQAECgQIBwABNQAECgkJRQAVAL0WAA==.Waraho:BAAANQADCgEIAQABNQAECgoKKgARAN0RAA==.Warraxe:BAAANQADCgYICAAAAA==.Waukeen:BAAANQABCgIIAgAAAA==.Wayloren:BAABNQAECn8pAAIBAAkKQAkx0gB3AQABAAkKQAkx0gB3AQAAAA==.',
We='Wetboycaird:BAAANQADCgMIAwAAAA==.',
Wi='Wickathy:BAABNQAECn8xAAMZAAoKfCNwAQCTAwAZAAoKfCNwAQCTAwAEAAEKJgKBgQAXAAAAAA==.Wickcreu:BAAANQAECgQIBAAAAA==.',
Wo='Woodson:BAAANQADCggICAABNQAECgcIEQAGAAAAAA==.Wooping:BAAANQADCgEIAQAAAA==.Worstdps:BAACNQAFFH8MAAIEAAQK3QS6DQC4AAAEAAQK3QS6DQC4AAA1AAQKf0IAAgQACgpBG+QQAHkCAAQACgpBG+QQAHkCAAAA.',
Wu='Wuldorr:BAACNQAFFH8JAAIBAAQKAAfYFQAAAQABAAQKAAfYFQAAAQA1AAQKfyoAAgEACgo1EpZlAMkBAAEACgo1EpZlAMkBAAAA.',
Wy='Wynnifred:BAABNQAECn8bAAMiAAUK8RQyGgAZAQAiAAUK8RQyGgAZAQAeAAQKFgTUGwBkAAAAAA==.',
Xa='Xaltheris:BAAANQAECgYIBgAAAA==.',
Xe='Xenothor:BAAANQAECgEIAQAAAA==.Xethreal:BAABNQAECn8lAAIMAAgK+hu+RABOAgAMAAgK+hu+RABOAgAAAA==.',
Xy='Xype:BAAANQAECggICAAAAA==.',
Xz='Xzara:BAAANQAECgYICgAAAA==.',
Ya='Yaanu:BAAANQADCgMIAwAAAA==.',
Yu='Yura:BAAANQADCggICAAAAA==.',
Yv='Yvvee:BAAANQAECgMIAwAAAA==.',
Za='Zapbranigan:BAAANQADCggIDQAAAA==.Zasko:BAAANQAECggIDAAAAA==.',
Ze='Zeda:BAAANQADCgEIAQABNQAECgYICgAGAAAAAA==.',
Zi='Zifao:BAABNQAECn8vAAIOAAoKZCMTKQA/AwAOAAoKZCMTKQA/AwAAAA==.',
Zo='Zonora:BAABNQAECn8qAAIJAAoKZBGPRADOAQAJAAoKZBGPRADOAQAAAA==.',
['Äz']='Äzrael:BAABNQAECn8gAAILAAgKYhpHSABNAgALAAgKYhpHSABNAgAAAA==.',
['Çr']='Çréwüsæðèr:BAABNQAECn8dAAIbAAgKpR7dDgA+AgAbAAgKpR7dDgA+AgAAAA==.',
['Ðì']='Ðìaßlo:BAACNQAFFH8LAAIIAAQKlxPuEQBDAQAIAAQKlxPuEQBDAQA1AAQKfz8AAggACgqaIf8TANwCAAgACgqaIf8TANwCAAAA.',
['Òd']='Òdinn:BAAANQADCgcIBwAAAA==.',
['Ød']='Ødin:BAAANQADCggIFgABNQAECgYIEgAGAAAAAA==.',
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
