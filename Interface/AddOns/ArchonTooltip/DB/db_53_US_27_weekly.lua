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

local lookup = {'DeathKnight-Frost','DeathKnight-Blood','DeathKnight-Unholy','Mage-Arcane','Druid-Guardian','Warlock-Demonology','Hunter-Survival','Priest-Shadow','Paladin-Retribution','Shaman-Elemental','Druid-Feral','Druid-Balance','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Protection','Warrior-Arms','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','Mage-Frost','DemonHunter-Devourer','Warrior-Protection','Shaman-Restoration','Rogue-Subtlety','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Evoker-Devastation','Warrior-Fury','Rogue-Assassination','Rogue-Outlaw','Monk-Brewmaster','Monk-Windwalker','Priest-Holy','Evoker-Preservation','Evoker-Augmentation','Priest-Discipline','Druid-Restoration',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aaravos:BAAANQAECgYIBgAAAA==.Aatrøx:BAABNQAECn8VAAQBAAgKFwqIXQAKAQABAAcKtwmIXQAKAQACAAEKCRQAlwA5AAADAAEKRQP5kAAfAAAAAA==.',
Ac='Accretion:BAAANQADCgcIBwAAAA==.',
Ad='Addath:BAAANQAECgYIBAAAAA==.Adura:BAAANQADCggICwAAAA==.',
Ae='Aeirith:BAABNQAECn8yAAIEAAoKmxz9MABxAgAEAAoKmxz9MABxAgAAAA==.',
Ai='Ailsà:BAAANQADCgIIAgABNQAECgcIKAAFAI4SAA==.Airius:BAAANQAECgQIAwAAAA==.',
Al='Alannon:BAAANQADCgQIBAAAAA==.Alayana:BAAANQAECgEIAwAAAA==.Aldyah:BAAANQADCgMIAwAAAA==.',
Am='Amalthia:BAABNQAECn8XAAIGAAkK7ht0OQAcAgAGAAkK7ht0OQAcAgAAAA==.Amarasu:BAABNQAECn8iAAIHAAgKzhDpBwDlAQAHAAgKzhDpBwDlAQAAAA==.Amarlly:BAABNQAECn8fAAIBAAgKHRB4RwCgAQABAAgKHRB4RwCgAQAAAA==.',
An='Ancelina:BAABNQAECn8kAAIIAAoKcB57CADRAgAIAAoKcB57CADRAgAAAA==.Anderton:BAABNQAECn9QAAIJAAoKdhIdZAD4AQAJAAoKdhIdZAD4AQAAAA==.Anditracks:BAAANQAECgUIBQAAAA==.Andraenei:BAABNQAECn8iAAIKAAYKUA52pQBJAQAKAAYKUA52pQBJAQAAAA==.Andrela:BAAANQAECgIIAQAAAA==.Andromadda:BAAANQADCgcIBwAAAA==.Aneira:BAABNQAECn8oAAQFAAcKjhJAJwA2AQAFAAcKjhJAJwA2AQALAAQKKwZ7NQBlAAAMAAIK9AJ2fABBAAAAAA==.',
Ap='Applefritter:BAAANQADCggIDQABNQAECgoKKQAGAOkbAA==.',
Aq='Aquarius:BAAANQADCgcIBwAAAA==.',
Ar='Araest:BAAANQADCgUIBQAAAA==.Araga:BAABNQAECn9OAAICAAoKvSSABQApAwACAAoKvSSABQApAwAAAA==.Archérhiro:BAACNQAFFH8XAAMNAAcKgRruBwDNAQANAAcKgRruBwDNAQAOAAEKAAAfKAA1AAA1AAQKf04AAw0ACgoAJdEIAD4DAA0ACgoAJdEIAD4DAA4ABQpTEANFADEBAAAA.Arillann:BAABNQAECn84AAIPAAoKOiHaBwAjAwAPAAoKOiHaBwAjAwAAAA==.Arin:BAAANQAECgQIBgABNQAECgoKHgAQAOwXAA==.Arms:BAAANQAECgcICAABNQAECgoKLQAJAFAYAA==.Arrook:BAAANQAECgQIBAAAAA==.Artdemsamis:BAABNQAECn8aAAQRAAoKPBEWNgDpAAAGAAgKEhCymACpAQARAAQKqw4WNgDpAAASAAEKAAD2MQAAAAAAAA==.Arttimar:BAAANQAECggICAAAAA==.Arvena:BAAANQADCgQIBAAAAA==.',
As='Asclëpius:BAAANQADCgIIAgABNQADCgYJBgATAAAAAA==.Ashylock:BAABNQAECn8fAAIGAAoKlBTKUQBgAgAGAAoKlBTKUQBgAgABNQAFFAUIEwAEAFUbAA==.Ashymage:BAACNQAFFH8TAAIEAAUKVRs3GwAFAQAEAAUKVRs3GwAFAQA1AAQKf0EAAwQACgoDJcgWAHgDAAQACgoDJcgWAHgDABQAAQrTCu1GADYAAAAA.Askevar:BAABNQAECn8eAAIDAAcKowjHQwDrAAADAAcKowjHQwDrAAAAAA==.Asriél:BAABNQAECn8ZAAINAAkKtBn1YwBNAgANAAkKtBn1YwBNAgAAAA==.Assoul:BAAANQABCgIIBAAAAA==.Astrea:BAAANQABCggIDAAAAA==.Astridia:BAAANQAECgMIBAAAAA==.Asuya:BAAANQAECgEJAQAAAA==.',
At='Atlassian:BAAANQAECgIJAgAAAA==.Atreus:BAABNQAECn8eAAIJAAoKfwOfAAHTAAAJAAoKfwOfAAHTAAAAAA==.',
Az='Azaleah:BAABNQAECn88AAIJAAoKEBGJegA2AgAJAAoKEBGJegA2AgAAAA==.Azlan:BAAANQAECgEIAQAAAA==.Azraesha:BAABNQAECn8mAAIVAAoKIRFLHgCdAQAVAAoKIRFLHgCdAQAAAA==.Azureflamez:BAAANQADCgYJBgAAAA==.',
Ba='Backy:BAAANQAECgUIBQAAAA==.',
Be='Beareold:BAAANQAECgEIAgAAAA==.Beary:BAAANQAECgIIAwAAAA==.Beefcakes:BAAANQADCgYIBgAAAA==.Benimaru:BAAANQADCgQJBAAAAA==.',
Bi='Bigblunt:BAAANQAECgQIDQAAAA==.Bigmon:BAABNQAECn9ZAAMQAAoKuSFsIQAyAwAQAAoKuSFsIQAyAwAWAAEKgA/SRAAvAAAAAA==.Billie:BAAANQAECgIIAQAAAA==.',
Bj='Bjornulfr:BAAANQADCgIIAgAAAA==.',
Bl='Blackadder:BAAANQAECgcIEwAAAA==.Blackstaff:BAAANQADCggIEQABNQAECgcIJAAFAGocAA==.Blessthefall:BAAANQAECggIDQAAAA==.Bloodygrundl:BAABNQAECn82AAICAAoKYCJVEAAqAwACAAoKYCJVEAAqAwAAAA==.Bluestorm:BAABNQAECn8cAAIKAAkKSgJXpQCoAAAKAAkKSgJXpQCoAAAAAA==.',
Bo='Bonegrinda:BAABNQAECn8tAAIDAAkK/R6rMgBhAgADAAkK/R6rMgBhAgAAAA==.Borledish:BAAANQADCgQIBAABNQAFFAMIAwATAAAAAA==.',
Br='Branwynn:BAAANQAECgIIAQAAAA==.Bringg:BAAANQAECgQIBAAAAA==.',
Bu='Budgetcuts:BAAANQADCgYIBgAAAA==.Bulldoza:BAAANQADCgQIBAAAAA==.',
Ca='Caidinn:BAAANQADCgUIBQAAAA==.Calissancia:BAAANQAECgIIAgAAAA==.Calliaa:BAAANQADCgYIBgAAAA==.Callmemommy:BAAANQAECgMIBQAAAA==.Camrookie:BAAANQADCggIDgAAAA==.Catovia:BAAANQAECgMIAwAAAA==.',
Ce='Ceallachan:BAABNQAECn8kAAIQAAoKEAbrlABBAQAQAAoKEAbrlABBAQAAAA==.Ceri:BAAANQAECggIEQAAAA==.Ceska:BAAANQADCgIIAgAAAA==.',
Ch='Channingtotm:BAACNQAFFH8YAAIXAAcK1h8LBABFAgAXAAcK1h8LBABFAgA1AAQKfzQAAhcACgo0JfQIAHoDABcACgo0JfQIAHoDAAAA.Chaosshadow:BAABNQAECn8wAAIIAAkK+BTtFgDeAQAIAAkK+BTtFgDeAQAAAA==.Chaosti:BAABNQAECn8YAAIDAAoK9Qp2bABhAQADAAoK9Qp2bABhAQAAAA==.Cheekymonkey:BAABNQAECn8rAAIEAAoKbQnwlQBmAQAEAAoKbQnwlQBmAQAAAA==.Chrispbacon:BAAANQADCgQIBQAAAA==.Chueyé:BAAANQAECgUIBwABNQAECgoKQgAYAIAgAA==.Chune:BAAANQADCgEIAQABNQAECgcIJAAFAGocAA==.Churros:BAAANQAECgcIEAABNQAECgoKKQAGAOkbAA==.',
Co='Cobiepaladin:BAAANQAECgYIBgAAAA==.Coconuts:BAAANQAECgEIAQAAAA==.Conqueefador:BAAANQAECgIIAwAAAA==.Corafel:BAAANQAECgIIAgAAAA==.Cordialkylie:BAAANQAECgMIAwAAAA==.',
Cr='Cross:BAABNQAECn8mAAIZAAYKtR2ecwC9AQAZAAYKtR2ecwC9AQAAAA==.Crosslock:BAAANQADCgcICwAAAA==.',
Cu='Cuack:BAAANQAECgEIAQAAAA==.',
Cy='Cynnari:BAABNQAECn8lAAIGAAgKTQjFlwAVAQAGAAgKTQjFlwAVAQAAAA==.',
Da='Dagnabit:BAAANQAECgMIAwABNQAECgcIJAAFAGocAA==.Daisydeath:BAAANQADCgEIAQAAAA==.Dalaris:BAABNQAECn8vAAIaAAkKOxDgLACUAQAaAAkKOxDgLACUAQAAAA==.Darkpriestes:BAAANQADCgQIBAAAAA==.Darling:BAAANQADCgIIAgAAAA==.Darrosh:BAAANQAECgUIDwAAAA==.Dartian:BAAANQAECgMJAwABNQAECgcIIwANAIUMAA==.',
De='Deathmare:BAABNQAECn8nAAMaAAkKgg2kJwC5AQAaAAkKgg2kJwC5AQAbAAQKdAf6IQCzAAAAAA==.Deathty:BAABNQAECn8VAAMDAAoKXQs4NQA5AQADAAkKxAg4NQA5AQACAAMKAxDtaQCYAAABNQAECgoKLgAGAIwTAA==.Deeptroat:BAAANQADCgEIAQABNQAECggIIgAHAM4QAA==.Dementia:BAAANQADCgcIBwAAAA==.Derzer:BAAANQADCgUIBgAAAA==.Design:BAABNQAECn8wAAMGAAkKixPqdQAAAgAGAAkKixPqdQAAAgASAAEKAAAfMQAzAAAAAA==.',
Di='Dibick:BAAANQABCgQIBQAAAA==.Dictaiter:BAABNQAECn8VAAQBAAUKiA/UbwDfAAABAAQKQw/UbwDfAAADAAIKtQRBzABUAAACAAEK0g1PywAzAAAAAA==.Diltlish:BAAANQAECgUIDgAAAA==.Disconcern:BAAANQADCgIIAgAAAA==.Discontent:BAABNQAECn8nAAIQAAkKYBslfwAdAgAQAAkKYBslfwAdAgAAAA==.',
Dm='Dmginc:BAAANQAECgQIDQAAAA==.',
Do='Domidouse:BAAANQADCgYICAAAAA==.Domivyr:BAAANQAECgMIBQAAAA==.Doubledeuces:BAAANQAECgQIBQAAAA==.Doubtz:BAAANQAFFAMIAwAAAA==.',
Dr='Drackonia:BAABNQAECn8XAAIIAAYKKwOeRgB9AAAIAAYKKwOeRgB9AAAAAA==.Dracolyte:BAAANQADCgEIAQAAAA==.Dragonflai:BAABNQAECn8nAAIEAAoKixAznwBDAgAEAAoKixAznwBDAgAAAA==.Draik:BAAANQADCgUICQAAAA==.Drakkari:BAAANQAECgUICAAAAA==.Drakkei:BAABNQAECn85AAINAAoKORVrVgAHAgANAAoKORVrVgAHAgABNQAECgoKQwAFAL0UAA==.Drshortbus:BAAANQAECgUICQAAAA==.Drunkenfist:BAAANQAECgQIBQAAAA==.Drylo:BAEBNQAECn8rAAIcAAkKhiIoBgAqAwAcAAkKhiIoBgAqAwAAAA==.',
Du='Duwéndé:BAAANQADCgQIBAAAAA==.',
El='Elarol:BAAANQADCgYICQAAAA==.Eleonore:BAAANQAECgYIDQAAAA==.Elfie:BAAANQADCgYIBgAAAA==.Elray:BAAANQAECgUIBwAAAA==.',
Em='Emeralde:BAAANQABCgYJCgAAAA==.Emilia:BAAANQABCgQIBwAAAA==.Emptyhands:BAAANQAECggIDQAAAA==.Emptyheals:BAAANQADCggICwAAAA==.',
Er='Erf:BAAANQADCgYIDgAAAA==.Erfinden:BAAANQADCgIIBAAAAA==.',
Es='Espers:BAABNQAECn8sAAIMAAoKOw1qSwC3AQAMAAoKOw1qSwC3AQAAAA==.',
Et='Ethellin:BAABNQAECn8pAAIJAAgK7wTRBQEVAQAJAAgK7wTRBQEVAQAAAA==.',
Eu='Euph:BAAANQAECgYIDgAAAA==.',
Ev='Evilhearts:BAAANQAECgQIBAAAAA==.',
Ex='Excalodor:BAAANQAECgEIAQAAAA==.Extrabacon:BAAANQADCgUIDgAAAA==.',
Fe='Fedders:BAAANQAECgYIEgABNQAECgoKNwAJAEMmAA==.Feedmepizzas:BAAANQAECgEIBAAAAA==.Feildmedic:BAAANQAECgUIBwABNQAECgUIEAATAAAAAA==.Feleria:BAAANQAECgEIAQAAAA==.Felwinter:BAAANQADCgYIBgAAAA==.',
Fi='Finwé:BAAANQAECgIIAgAAAA==.Fizzysoda:BAAANQADCgcIBwAAAA==.',
Fl='Fluxarata:BAABNQAECn8bAAIVAAgKBgj9MwDlAAAVAAgKBgj9MwDlAAAAAA==.',
Fr='Fred:BAABNQAECn8cAAIdAAcKvQeiGQDTAAAdAAcKvQeiGQDTAAAAAA==.Friendly:BAABNQAECn86AAMeAAoK2SRbBQB+AwAeAAoKeyRbBQB+AwAYAAkKox8qDQAGAwAAAA==.Frightrice:BAAANQAECgQJCAAAAA==.Frioh:BAAANQADCgYIDwAAAA==.',
Fu='Fullpally:BAAANQADCgYIBgAAAA==.Fupacabra:BAAANQADCgcIBwAAAA==.Fuzzyhunter:BAAANQADCgcIEQAAAA==.',
['Fï']='Fïzzle:BAAANQAECgQIBQABNQAECgcIKAAFAI4SAA==.',
Ga='Gabel:BAAANQADCggJCAAAAA==.Gablyn:BAABNQAECn8nAAINAAoK1BnFPwCrAgANAAoK1BnFPwCrAgAAAA==.Gagageoff:BAAANQAECgEIAQAAAA==.Gardyson:BAABNQAECn8wAAMWAAoKUw0fIABOAQAQAAoKYwkcsQCiAQAWAAgKMQ4fIABOAQAAAA==.Garwarmegad:BAAANQAECgQIBQAAAA==.',
Gh='Ghrash:BAAANQADCgQIBAAAAA==.',
Gl='Gloney:BAAANQADCgMIAwAAAA==.',
Gn='Gnomew:BAAANQAECgUIAwAAAA==.',
Go='Gobsprocket:BAAANQADCggICAAAAA==.Gojira:BAAANQABCgUIBgAAAA==.Goldenshower:BAAANQADCgUIBQAAAA==.',
Gr='Gremilien:BAABNQAECn88AAIOAAoKfxNJEwD7AQAOAAoKfxNJEwD7AQAAAA==.Grenadeout:BAABNQAECn8eAAQYAAoKYBy8GgCfAgAYAAoKYBy8GgCfAgAeAAMKahY8cwDkAAAfAAEKAAB1GQBNAAAAAA==.Grimaldus:BAAANQAECgIIAQABNQAECgYICAATAAAAAA==.',
Ha='Harrod:BAAANQAECgIIAgAAAA==.Hauteliotie:BAAANQAECgMIBwAAAA==.Hawkwave:BAAANQADCgIIAgABNQADCgUIBQATAAAAAA==.',
He='Hefty:BAAANQAECgUIEAAAAA==.Hellbad:BAABNQAECn8WAAMgAAgKAhdbDQAlAgAgAAgKAhdbDQAlAgAhAAYK4ADnbQAuAAAAAA==.Hellsspawn:BAAANQADCgUIDAAAAA==.',
Ho='Hokàge:BAABNQAECn9CAAMYAAoKgCCGHACUAgAYAAoKpB+GHACUAgAeAAcKixwXLAA4AgAAAA==.Holyprom:BAAANQADCgUIBQAAAA==.Homealone:BAABNQAECn8dAAMXAAkKoAxMWgCVAQAXAAkKoAxMWgCVAQAKAAMKnQFSFAFkAAAAAA==.Hotblood:BAAANQAECgEIAQAAAA==.',
Hu='Huey:BAAANQAECgUIBgABNQAECgoKMAAIAGoVAA==.Huntinfuzzy:BAABNQAECn8bAAINAAgKjwnktACaAQANAAgKjwnktACaAQAAAA==.Huugg:BAAANQAECgYICQAAAA==.',
Hy='Hymncarrey:BAABNQAECn8kAAIiAAcK/COfLAC2AgAiAAcK/COfLAC2AgAAAA==.Hynkie:BAABNQAECn8kAAIiAAoKzBMdOQBDAgAiAAoKzBMdOQBDAgABNQAECgoKKgAjALgXAA==.',
Id='Idari:BAAANQABCgEIAQAAAA==.',
Ig='Igothots:BAAANQAECgYICgABNQAECggIEQATAAAAAA==.',
Il='Ilarcine:BAAANQAECgQIBAABNQAECgcIDQATAAAAAA==.',
In='Insanitty:BAAANQADCggJCAAAAA==.',
Ir='Irritable:BAABNQAECn8zAAQSAAkKpxwjBgABAgASAAkKpxwjBgABAgAGAAYKXA5dtgBiAQARAAEK4wZnfwAtAAAAAA==.',
Is='Isadragon:BAAANQADCgUICQABNQAECggIIgAHAM4QAA==.',
Ja='Jackyll:BAAANQAECggIBwAAAA==.Jatix:BAABNQAECn8aAAIJAAkKThjsbgBSAgAJAAkKThjsbgBSAgAAAA==.Jawzlyn:BAAANQADCgYIDAABNQAECgQIBQATAAAAAA==.',
Je='Jellytown:BAABNQAECn81AAIUAAoKTBqMBQC3AgAUAAoKTBqMBQC3AgAAAA==.Jelorinea:BAAANQADCgYIBgAAAA==.Jessiana:BAAANQAECgEJAQAAAA==.',
Jo='Johncarlo:BAAANQAECgIIBgAAAA==.',
Jp='Jpeppers:BAAANQAECgQICQAAAA==.',
Ju='Juicifer:BAAANQAECgIIAQAAAA==.Juicylucy:BAAANQAECgEIAQAAAA==.Jundra:BAAANQADCgYICAAAAA==.Jundraa:BAAANQADCgQIBAAAAA==.Jurih:BAAANQAECgMIAwAAAA==.Justine:BAAANQAECgMIAwAAAA==.',
['Jô']='Jôhnwick:BAABNQAECn8dAAIOAAkKZw4UKwDyAQAOAAkKZw4UKwDyAQAAAA==.',
Ka='Kaedas:BAAANQAECgUIBQABNQAECgoKQwAFAL0UAA==.Kaerynn:BAAANQADCgYIBgAAAA==.Kait:BAABNQAECn81AAINAAoKQhS7UgB4AgANAAoKQhS7UgB4AgAAAA==.Kaladil:BAAANQAECgMICgAAAA==.Kamaren:BAAANQAECgcICAAAAA==.Kashmir:BAAANQAECgMIAwAAAA==.Kawdor:BAAANQAECgQIBwAAAA==.Kazola:BAAANQABCgEIAQAAAA==.',
Ke='Kelaino:BAAANQABCgYIBgAAAA==.',
Kh='Khota:BAAANQAECggICwAAAA==.',
Ki='Killanick:BAAANQAECgQIBAAAAA==.',
Ko='Koldfront:BAAANQADCgYIDgAAAA==.Kollinator:BAAANQAECggICwAAAA==.',
Ku='Kurtina:BAABNQAECn85AAIQAAoKyBRoVwDlAQAQAAoKyBRoVwDlAQAAAA==.',
Ky='Kyyell:BAAANQAECgIIAgAAAA==.',
La='Lafty:BAABNQAECn8tAAINAAoKghx9KQCMAgANAAoKghx9KQCMAgABNQAECgoKLgAGAIwTAA==.Larac:BAAANQAECggIDQAAAA==.',
Le='Leddy:BAAANQADCgUICQAAAA==.Leif:BAABNQAECn80AAMcAAoKbhZqEABRAgAcAAoKbhZqEABRAgAkAAMKkAosFACKAAAAAA==.Lemmart:BAABNQAECn8gAAISAAkKPw0FDQBSAQASAAkKPw0FDQBSAQAAAA==.Lenik:BAAANQAECgYIEQAAAA==.',
Li='Licorice:BAABNQAECn8pAAMGAAoK6RtHKgBXAgAGAAoK6RtHKgBXAgARAAEKEwvQewAxAAAAAA==.Lieree:BAABNQAECn8nAAIEAAoKtAn63gDKAQAEAAoKtAn63gDKAQAAAA==.Lilyfaye:BAAANQADCgEIAQAAAA==.Limosfire:BAAANQAECgUICAAAAA==.',
Lo='Lockty:BAABNQAECn8uAAIGAAoKjBNnPgAKAgAGAAoKjBNnPgAKAgAAAA==.Logi:BAAANQADCgUIBgAAAA==.Longtotem:BAAANQAECgMJAwAAAA==.Lorian:BAAANQAECgcIBgAAAA==.',
Lp='Lpeppers:BAAANQADCgMIAwAAAA==.',
Lu='Lucha:BAEANQAECgIIAwAAAA==.Lucity:BAAANQAECgcIDwABNQAECgkJGgAJAE4YAA==.Luckyvodka:BAAANQADCgUICQAAAA==.Lunafae:BAAANQAECgEIAQAAAA==.Lunarmyst:BAAANQADCgUIBQABNQAECgEIAQATAAAAAA==.Lunà:BAAANQAECgQICQAAAA==.',
Ly='Lystral:BAAANQAECgcICwAAAA==.Lythalle:BAAANQADCgIIAgAAAA==.Lythwynn:BAAANQAECgUIDgAAAA==.',
['Lá']='Lásh:BAAANQAECgYICwABNQAECgcIKAAFAI4SAA==.',
Ma='Mace:BAABNQAECn8rAAIJAAoKlCHRHgBIAwAJAAoKlCHRHgBIAwAAAA==.Magdalena:BAAANQAECgQIBQAAAA==.Mageyboi:BAAANQAECgMIAgABNQAECgoKQgAYAIAgAA==.Magickul:BAAANQAECgQIBwAAAA==.Mahano:BAAANQAECgEIAQABNQAECgoKMAAWAFMNAA==.Malìficus:BAAANQADCgcIBwAAAA==.Manadâr:BAAANQAECggIDgAAAA==.Manawave:BAAANQAECggIBwAAAA==.Marinas:BAAANQADCgcIFgAAAA==.Maru:BAAANQADCgYIBgAAAA==.Massili:BAAANQADCgQICQAAAA==.Mazumaragg:BAAANQAECgQICAABNQAECgoKMAAWAFMNAA==.',
Me='Mediocre:BAAANQAECgMIAgAAAA==.Mello:BAAANQAECgIIBAAAAA==.',
Mi='Miande:BAAANQAECgYICgAAAA==.Microburst:BAABNQAECn80AAIKAAoKegeVZgA7AQAKAAoKegeVZgA7AQAAAA==.Milamagi:BAAANQADCggIDgAAAA==.Minilock:BAABNQAECn8nAAQGAAoKtQkzaQCHAQAGAAoKtQkzaQCHAQARAAMKwgHqYQBhAAASAAEKDAcpMgAwAAAAAA==.Missdeeds:BAAANQABCgQIBAAAAA==.Missleading:BAAANQABCgEIAQAAAA==.Miyagifu:BAAANQADCgMJBAABNQAECgUIEAATAAAAAA==.Mièlikki:BAABNQAECn8kAAIFAAcKahx3GwCRAQAFAAcKahx3GwCRAQAAAA==.',
Mo='Moash:BAAANQADCggICAAAAA==.Modelotime:BAAANQADCggICwAAAA==.Modsagoodtnk:BAAANQADCggICQABNQAECgEIAQATAAAAAA==.Mongermook:BAABNQAECn8bAAMFAAkK1Q2nKABRAQAFAAgKRg2nKABRAQALAAIKCA1dNgBiAAAAAA==.Monkyd:BAAANQAECggIAQAAAA==.Monnkysham:BAAANQAECgUICAAAAA==.Montclair:BAAANQAECgIIAgABNQAECgkJGwAZABcUAA==.Mooglefur:BAAANQADCgcICAAAAA==.Moranta:BAEANQADCgYIBgAAAA==.Moshood:BAAANQADCggICwAAAA==.',
My='Myaka:BAAANQAECgIIAwAAAA==.',
['Má']='Mánáburn:BAAANQADCgQIBAAAAA==.',
['Mõ']='Mõnk:BAAANQADCgYIBgAAAA==.',
Na='Naatixa:BAABNQAECn8pAAIXAAoKzhMeSwDPAQAXAAoKzhMeSwDPAQAAAA==.Nacronor:BAAANQADCggIIgAAAA==.Naiika:BAAANQABCgQIBQAAAA==.Nasoj:BAAANQAECggIDwAAAA==.Nauseous:BAAANQADCggICAAAAA==.',
Ne='Nedalla:BAAANQADCgYIBgAAAA==.Nerzultash:BAAANQADCgEIAQAAAA==.Nexedo:BAAANQAECgEIAQAAAA==.',
Ni='Nickatnite:BAAANQAECgQIBgAAAA==.Nickelodeon:BAAANQAECgQICQAAAA==.Nickita:BAAANQAECgQIBgAAAA==.Nicky:BAAANQAECgEIAQAAAA==.Nightgear:BAACNQAFFH8WAAINAAcKHRHfAwAhAgANAAcKHRHfAwAhAgA1AAQKf1oAAg0ACgrdIoEdAL4CAA0ACgrdIoEdAL4CAAAA.Nighti:BAAANQADCgQIBAAAAA==.Niteshadeth:BAAANQADCgMIAwAAAA==.Nixeava:BAAANQAECgQIDwAAAA==.',
No='Notadoctor:BAAANQAECgMIBAAAAA==.Notafurry:BAAANQADCgUICQAAAA==.',
Ny='Nysong:BAAANQADCgEIAQAAAA==.',
Oa='Oakenforge:BAABNQAECn9DAAMFAAoKvRRtFwD3AQAFAAkKmBZtFwD3AQAMAAkKmQjtOgAuAQAAAA==.',
Od='Ode:BAABNQAECn80AAIEAAoKaQw9awDLAQAEAAoKaQw9awDLAQAAAA==.Odex:BAABNQAECn8eAAIcAAkKnQqSDQBfAQAcAAkKnQqSDQBfAQAAAA==.',
On='Onlymages:BAABNQAECn8wAAIEAAcKww+urAA4AQAEAAcKww+urAA4AQAAAA==.Onos:BAAANQAECgQICwAAAA==.',
Or='Orinin:BAABNQAECn8wAAMIAAoKahW0EwALAgAIAAoKahW0EwALAgAlAAMKhgtAGwCOAAAAAA==.',
Ou='Outdeath:BAAANQAECgMIAwABNQAECgcIGwAQAGsJAA==.Outheal:BAAANQAECgQIBQABNQAECgcIGwAQAGsJAA==.Outkíll:BAABNQAECn8bAAIQAAcKawktsgAAAQAQAAcKawktsgAAAQAAAA==.',
Pa='Pally:BAABNQAECn8tAAIJAAoKUBjjVwAWAgAJAAoKUBjjVwAWAgAAAA==.Pandarweb:BAAANQAECgUIBgAAAA==.Papasmurfz:BAAANQAECgQIBAAAAA==.Pathogen:BAABNQAECn82AAIDAAoK7iPqCQBuAwADAAoK7iPqCQBuAwAAAA==.',
Pe='Peachebelle:BAAANQADCgQIBAAAAA==.Peaches:BAAANQADCgUIBQAAAA==.Persephoni:BAABNQAECn80AAIBAAkKaxOZMgDGAQABAAkKaxOZMgDGAQAAAA==.Perve:BAABNQAECn8VAAIiAAkKFgl/ZwCQAQAiAAkKFgl/ZwCQAQABNQAECgkJGQANALQZAA==.',
Pf='Pfchen:BAAANQADCgYIBwAAAA==.',
Pi='Pious:BAAANQAECgEIAQAAAA==.Pippy:BAAANQAECgIIAQAAAA==.',
Pl='Plaguestrip:BAAANQADCgIIAgAAAA==.Plinkerbell:BAAANQAECgEIAwAAAA==.',
Po='Poppit:BAAANQADCgYIBgAAAA==.',
Pr='Prom:BAAANQAECgEIAQAAAA==.Promethèus:BAABNQAECn8kAAIEAAoKxxkUSgDuAgAEAAoKxxkUSgDuAgAAAA==.',
Pu='Puffypuff:BAAANQADCggICAAAAA==.',
Qo='Qoheleth:BAAANQAECgYICwAAAA==.',
Qu='Quansamdi:BAAANQAECggIAgAAAA==.Queedle:BAABNQAECn8qAAIfAAoKTguSAwCUAQAfAAoKTguSAwCUAQAAAA==.',
Qw='Qwacker:BAAANQADCgUIDgAAAA==.',
Ra='Ragalstan:BAAANQABCggJDAAAAA==.Rainlette:BAAANQAECgQIBQAAAA==.Rainsvoker:BAACNQAFFH8SAAIcAAcK/RDqAgDXAQAcAAcK/RDqAgDXAQA1AAQKf3IAAxwACgqAITIDAHcDABwACgqAITIDAHcDACQAAQo4A3QeAB8AAAAA.Ramike:BAABNQAECn8qAAIWAAkKjBpiDQBcAgAWAAkKjBpiDQBcAgAAAA==.Randal:BAAANQABCgQIBAAAAA==.',
Re='Reaveldahar:BAAANQADCgUJCQAAAA==.Recovery:BAAANQAECgIIAwAAAA==.Reddan:BAAANQAECgQIDgAAAA==.Rei:BAAANQADCgUIBQAAAA==.Restodrood:BAAANQADCgUJAwABNQAECgoKQgAYAIAgAA==.Retman:BAAANQABCgIIAgAAAA==.Revy:BAAANQAECgQJBAAAAA==.',
Ri='Rinji:BAAANQADCggIDgAAAA==.Rinà:BAAANQAECgcICAAAAA==.Rit:BAAANQAECgYIDAAAAA==.Ritzon:BAABNQAECn81AAIQAAoKwxwpOQBNAgAQAAoKwxwpOQBNAgAAAA==.',
Ro='Robbert:BAAANQAECggICAAAAA==.Rosara:BAABNQAECn8bAAIZAAkKFxTROQAfAgAZAAkKFxTROQAfAgAAAA==.',
Rr='Rrook:BAAANQADCgQICAAAAA==.',
Ry='Ryanrainolds:BAAANQAECgcIDQABNQAECgcIJAAiAPwjAA==.Rykken:BAAANQAECgEIAQABNQAECgIIAgATAAAAAA==.',
['Rà']='Ràncore:BAAANQADCgEIAQAAAA==.',
Sa='Sakúra:BAAANQAECgUICQAAAA==.Santacloz:BAAANQADCgQIBAAAAA==.',
Sc='Scubasteve:BAAANQAECgEIAwAAAA==.',
Se='Segan:BAAANQADCgcIBwAAAA==.Sell:BAAANQADCgMIAwAAAA==.Sellex:BAAANQAECgQICAAAAA==.',
Sh='Shamalaya:BAAANQADCgUIBgAAAA==.Shamburgler:BAAANQAECgUIBwAAAA==.Shan:BAAANQAECgcIDwAAAA==.Sherrilu:BAAANQADCgIIAgAAAA==.Shiera:BAAANQADCggIDgAAAA==.Shmoove:BAEANQADCgYIBgABNQAECgIIAwATAAAAAA==.',
Si='Sinarria:BAAANQADCgUICAAAAA==.Sithra:BAAANQADCgQIBAAAAA==.',
Sk='Skitzop:BAAANQAECggIEAAAAA==.Skullace:BAABNQAECn8pAAIGAAkKhAaNhwA6AQAGAAkKhAaNhwA6AQAAAA==.Skylette:BAAANQADCggIDQAAAA==.',
Sl='Slash:BAAANQADCgEIAQAAAA==.Slilith:BAAANQABCgIIAgAAAA==.',
Sn='Snakeblitzen:BAAANQADCgQIBAAAAA==.Snakeosham:BAAANQAECgYICQAAAA==.Snakesix:BAAANQADCgYIBwAAAA==.Snarf:BAAANQADCgUIDgABNQAECgoKMAAWAFMNAA==.',
So='Soothingdusk:BAAANQAECgEIAQAAAA==.Sortiebatoru:BAAANQAECgEIAQAAAA==.Soulblight:BAAANQADCggIFwAAAA==.Souldune:BAAANQAECggIEAAAAA==.',
Sp='Sparkplugg:BAAANQADCgQICAAAAA==.Sparthos:BAABNQAECn8XAAMcAAYKugVNJgAEAQAcAAYKugVNJgAEAQAkAAEKAABOJwAmAAAAAA==.Spideyrogue:BAAANQAECgEIAQAAAA==.Springbuck:BAAANQABCgIIAgAAAA==.',
Sr='Srfreaky:BAAANQADCggIHAAAAA==.',
St='Stabatha:BAAANQAECgEIAQAAAA==.Stepbrogon:BAAANQADCgYICAAAAA==.Sterlìng:BAABNQAECn8sAAIBAAoKPwcwTgB9AQABAAoKPwcwTgB9AQAAAA==.Stocklock:BAAANQAECgMIBwAAAA==.Stormblessed:BAAANQADCgQIBAAAAA==.Stowned:BAAANQAECgQIBQAAAA==.Stumpyborg:BAAANQAECgEIAQABNQAECgUIEAATAAAAAA==.',
Su='Sune:BAAANQADCgUICQABNQAECgcIJAAFAGocAA==.Suzuya:BAAANQABCggICgAAAA==.',
Sy='Sympåthy:BAAANQAECgEIAQAAAA==.',
Ta='Takoyaki:BAAANQADCgMIAwAAAA==.Tapartos:BAAANQADCgIIAgABNQAECgoKMAAWAFMNAA==.Tatari:BAAANQADCgYJCgABNQAECggIDQATAAAAAA==.Tavenon:BAAANQAECgEIAQAAAA==.',
Te='Tel:BAAANQADCgQIAwAAAA==.Telandril:BAABNQAECn81AAImAAoKgBGAJgDuAQAmAAoKgBGAJgDuAQAAAA==.Tellanna:BAABNQAECn8gAAIEAAgKiAJ58QC7AAAEAAgKiAJ58QC7AAAAAA==.Tensuken:BAABNQAECn8VAAIJAAcK3RXhxgCOAQAJAAcK3RXhxgCOAQAAAA==.Teriyaki:BAAANQADCgMIAwAAAA==.Testarossaa:BAAANQAECgUIEAAAAA==.',
Th='Thadium:BAAANQADCgcIBwAAAA==.Thaet:BAAANQABCgUIBwAAAA==.That:BAAANQADCgYIBgAAAA==.Thauríel:BAAANQAECgUIBAAAAA==.Thebran:BAAANQADCggJEAAAAA==.Thejuiciest:BAAANQAECgYICwAAAA==.Theunclepaul:BAAANQAECgUICgAAAA==.',
Ti='Tiarl:BAABNQAECn9KAAMiAAoKjSCjFAAgAwAiAAoKjSCjFAAgAwAIAAMKtA3nSwBpAAAAAA==.Tinydots:BAAANQAECgYIEgAAAA==.Tinypaws:BAAANQADCgUIBwAAAA==.',
To='Tom:BAAANQADCgMIBAAAAA==.Tomoyá:BAAANQADCgYIBgAAAA==.Toniichopper:BAAANQAECgEIAQAAAA==.Tonn:BAAANQADCgUIDgAAAA==.Toosxyfohair:BAAANQAECgEIAQAAAA==.Torhal:BAAANQADCgIIAgAAAA==.',
Tr='Traw:BAAANQADCgUIBAAAAA==.Trimble:BAAANQABCggIBgAAAA==.',
Tt='Tt:BAAANQAFFAQIAwAAAA==.',
Tu='Tuv:BAAANQAECgQIBAAAAA==.',
Tw='Twentytwo:BAAANQADCgIIAgAAAA==.Twylo:BAEANQAECggICAABNQAECgkJKwAcAIYiAA==.',
Ty='Tyiedis:BAAANQADCgYJBwAAAA==.Tyrànda:BAAANQADCgUIDAAAAA==.',
Ul='Ulanhi:BAAANQAECgQIBgAAAA==.Uling:BAAANQADCgEIAQAAAA==.',
Un='Undeadjelly:BAABNQAECn8kAAMDAAkK7iA8HgDcAQADAAcKoSE8HgDcAQABAAQK6h2oYgAZAQAAAA==.Unfriendly:BAAANQAECgEIAQAAAA==.',
Va='Vaelora:BAABNQAECn8ZAAMCAAkKHhJpLQCOAQACAAkKHhJpLQCOAQABAAEKtAh/rgAxAAAAAA==.Vaelyria:BAAANQAECgIIAgAAAA==.Valakk:BAABNQAECn8fAAMQAAkKkwdNmgA1AQAQAAgKwQZNmgA1AQAdAAQKvQnEHwC/AAAAAA==.Valsitril:BAABNQAECn8YAAIUAAYKDxO2FwA9AQAUAAYKDxO2FwA9AQABNQAECgkJLwAaADsQAA==.Vanara:BAAANQABCggIDQAAAA==.Varelyna:BAAANQADCgYIBgABNQAECgkJLwAaADsQAA==.',
Ve='Velsetin:BAAANQAECgEIAQABNQAFFAMIAwATAAAAAA==.Venum:BAAANQAECgUIBQAAAA==.Veryspooky:BAAANQAECgQIBAABNQAECgUIDAATAAAAAA==.Vexian:BAAANQADCgcIGQABNQAECgoKQwAIAI0cAA==.',
Vi='Vicas:BAAANQAECgYICQAAAA==.Vipbull:BAAANQADCgYIBwAAAA==.Vixena:BAAANQADCgUIBgAAAA==.',
Vl='Vladdok:BAAANQADCgUIBQAAAA==.',
Vo='Voidzzmid:BAAANQADCgIIAgAAAA==.',
Wa='Warded:BAAANQAECgIIAQAAAA==.',
We='Webgar:BAAANQAECgMIAgAAAA==.Wesjenks:BAAANQAECgUICAAAAA==.',
Wh='Whisperlia:BAAANQAECgIIAgAAAA==.Whisperwindd:BAABNQAECn8aAAINAAYKGwTb8AC1AAANAAYKGwTb8AC1AAAAAA==.White:BAAANQADCgUIBgAAAA==.Whitetoothe:BAAANQAECgIIAwAAAA==.',
Wo='Workin:BAAANQADCgIIAgABNQAECggIDQATAAAAAA==.',
Xa='Xandina:BAAANQADCgQICQAAAA==.',
Xi='Xiuhtecuhtli:BAAANQADCgUIBgAAAA==.',
Xo='Xotiko:BAAANQAECgIIAgAAAA==.',
['Xâ']='Xâxâs:BAAANQAECgMIAwABNQAECgQICQATAAAAAA==.',
Ya='Yaerin:BAABNQAECn8iAAMiAAoKjR4+EgA3AwAiAAoKjR4+EgA3AwAlAAMK0Q79GgCQAAAAAA==.Yahman:BAAANQAECgQIBAABNQAECgoKKAAEACIkAA==.Yaoi:BAABNQAECn83AAMKAAoKyQ2bZwDpAQAKAAoKyQ2bZwDpAQAXAAgK0wjAlABUAQAAAA==.',
Ye='Yevanendra:BAAANQADCgYICgAAAA==.',
Yo='Yokof:BAAANQAECggIEAAAAA==.',
Yu='Yungblood:BAAANQAECgYIBwAAAA==.Yungfungi:BAAANQAECgMIAwAAAA==.Yuukon:BAABNQAECn8yAAIBAAoKFxF1PgDSAQABAAoKFxF1PgDSAQAAAA==.',
Za='Zackman:BAAANQADCggIHgAAAA==.Zad:BAAANQAECgUIBAABNQAFFAYIEQABADkgAA==.Zaddydruid:BAAANQAECgYIBgABNQAFFAYIEQABADkgAA==.Zadira:BAACNQAFFH8RAAIBAAYKOSBNBQCLAQABAAYKOSBNBQCLAQA1AAQKf0AAAwEACgpcIWIKAEcDAAEACgpcIWIKAEcDAAIABgodF4FeALwAAAAA.Zadirasham:BAABNQAECn8fAAIKAAkKwB4nLgANAgAKAAkKwB4nLgANAgABNQAFFAYIEQABADkgAA==.Zadorca:BAAANQAECgYIBwABNQAFFAYIEQABADkgAA==.',
Ze='Zeeze:BAAANQADCgcIBwAAAA==.',
Zu='Zuriel:BAABNQAECn8bAAIXAAcK8hSfVACpAQAXAAcK8hSfVACpAQAAAA==.',
Zy='Zyku:BAAANQADCgEIAQAAAA==.Zylphia:BAAANQAECgcIDAAAAA==.',
['Àm']='Àmagezing:BAAANQAECgIIAgABNQAECgoKNwAPAFokAA==.',
['Èx']='Èxcision:BAAANQADCgUIBQAAAA==.',
['Ða']='Ðark:BAAANQADCggIDgAAAA==.',
['Ös']='Östara:BAAANQAECggIDQAAAA==.',
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
