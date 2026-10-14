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

local lookup = {'Evoker-Preservation','Paladin-Retribution','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Protection','Paladin-Holy','Druid-Restoration','Druid-Balance','Evoker-Augmentation','Evoker-Devastation','Unknown-Unknown','Warrior-Arms','Warrior-Protection','DeathKnight-Blood','Mage-Frost','Rogue-Subtlety','Rogue-Outlaw','Druid-Feral','Shaman-Elemental','Mage-Arcane','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','Hunter-BeastMastery','Shaman-Restoration','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Marksmanship','Monk-Brewmaster','Rogue-Assassination','Druid-Guardian','Hunter-Survival','Warrior-Fury',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abnee:BAAANQADCgYICQAAAA==.',
Ad='Adowyrm:BAACNQAFFH8RAAIBAAYKhRXUBgDhAQABAAYKhRXUBgDhAQA1AAQKfyYAAgEACQqWIFIIAB8DAAEACQqWIFIIAB8DAAAA.Adrielle:BAAANQAECgUIBQAAAA==.',
Ai='Airali:BAABNQAECn8oAAICAAkKEBExigANAgACAAkKEBExigANAgAAAA==.Airedale:BAAANQAECgUIEQAAAA==.',
Ak='Akairo:BAACNQAFFH8WAAIDAAYKux8IBgAzAgADAAYKux8IBgAzAgA1AAQKfzUABAMACQolJegGAIwDAAMACQolJegGAIwDAAQABAqKGJpFAAcBAAUAAQo1AWwyABoAAAAA.',
Al='Alexanderlx:BAABNQAECn8bAAMGAAcKiRvZFQBOAgAGAAYKUiLZFQBOAgACAAIKZABFiAFGAAAAAA==.Aleybobwa:BAABNQAECn8jAAMHAAkKqRwXHAACAwAHAAkKqRwXHAACAwACAAUKWhPa/QAdAQAAAA==.Algren:BAAANQADCgYIBgAAAA==.Alindrya:BAAANQABCgYIDQAAAA==.Althalas:BAAANQADCgQIBAAAAA==.',
Am='Amateur:BAAANQAECggIAgAAAA==.',
An='Andramedae:BAABNQAECn8jAAMIAAgKGSBiDgDpAgAIAAgKGSBiDgDpAgAJAAEKpwQLtQAqAAAAAA==.Andrio:BAAANQADCgcICgAAAA==.Angyavocado:BAABNQAECn8yAAMKAAkKAR+8AgAlAwAKAAkKGx68AgAlAwALAAMKLRORKwDFAAAAAA==.Antithanatos:BAAANQAECgIIAgABNQAECgMIBQAMAAAAAA==.',
Ao='Aolus:BAABNQAECn8vAAIJAAkKahwQGQD9AgAJAAkKahwQGQD9AgAAAA==.',
Ap='Apoliis:BAAANQAECgUICgAAAA==.Apollyon:BAAANQAECgEIAQAAAA==.',
Ar='Arathors:BAAANQAECgQIBAAAAA==.Arcaina:BAAANQADCgcIAgAAAA==.Archis:BAABNQAECn8lAAMNAAkKJhY6YwBhAgANAAkKJhY6YwBhAgAOAAYKIghUJgAKAQAAAA==.Arcidaes:BAEBNQAECn8aAAIPAAcKbwpFbABAAQAPAAcKbwpFbABAAQAAAA==.Arez:BAAANQADCgEJAQABNQAECggIGAAQAOEIAA==.',
As='Astryd:BAAANQAECgIIAwAAAA==.Asurna:BAAANQAECgYICQAAAA==.',
At='Athlon:BAAANQAECgEIAQAAAA==.',
Au='Aurellia:BAAANQADCgYIBgAAAA==.',
Aw='Awake:BAAANQADCgcIBwAAAA==.Awooga:BAACNQAFFH8GAAMRAAMKYQ2IDADhAAARAAMKnwuIDADhAAASAAIK6wu9AgCQAAA1AAQKfyEAAxIACQp/I/UBAE8DABIACQpHIvUBAE8DABEABQqKHzQeAN0BAAAA.',
Az='Azaekho:BAAANQADCgUIBQAAAA==.Azaelleonoc:BAAANQABCgQIBAAAAA==.Azalet:BAAANQADCgQIAwAAAA==.',
Ba='Babysharrk:BAAANQADCgUJBQABNQAECgkJJgATAModAA==.Baeyorn:BAAANQADCgEIAQAAAA==.Bajablaster:BAAANQAECgYIEAAAAA==.Baliw:BAABNQAECn8lAAIJAAkK/Q2AOwAUAgAJAAkK/Q2AOwAUAgAAAA==.Balto:BAAANQADCgQIBAAAAA==.Bandoliers:BAAANQAECgUICgAAAA==.Banugg:BAAANQADCgMIAwAAAA==.Bavmorda:BAAANQADCgUIBQAAAA==.',
Bb='Bbl:BAECNQAFFH8IAAIUAAUKRAwQDwB5AQAUAAUKRAwQDwB5AQA1AAQKfygAAhQACQqIHG4hAAIDABQACQqIHG4hAAIDAAAA.',
Bc='Bchung:BAABNQAECn8tAAMQAAkKBR4vBQDEAgAQAAkKBR4vBQDEAgAVAAgKMxaysQAeAgAAAA==.',
Be='Bela:BAAANQADCggIEAAAAA==.Belathil:BAAANQAECgcIBwAAAA==.Belathor:BAAANQADCgYIBgABNQAECgYICQAMAAAAAA==.Bertus:BAACNQAFFH8TAAMWAAYK5yRxAQBbAgAWAAYK5yRxAQBbAgAXAAQK8yEUCgBuAQA1AAQKfyMAAxcACQrlJXAUABQDABcACQpGJXAUABQDABYABwowJCcgAIcCAAAA.',
Bh='Bhain:BAABNQAECn8fAAIUAAkKYRydKwDNAgAUAAkKYRydKwDNAgAAAA==.',
Bi='Bieorne:BAAANQAECgYIEAAAAA==.',
Bl='Blikefire:BAAANQADCgEIAQAAAA==.Bloodwrath:BAAANQADCgQICQAAAA==.',
Bo='Bog:BAAANQADCgIIAgAAAA==.Boondocks:BAABNQAECn8lAAQYAAgKFRXGfwDiAQAYAAcKFRXGfwDiAQAZAAMKoRHVFgDZAAAaAAEKlAX6gAAqAAAAAA==.Bottomx:BAABNQAECn8cAAILAAgKEgmyFwDMAQALAAgKEgmyFwDMAQAAAA==.',
Br='Braca:BAABNQAECn8bAAMbAAcKrhnZFgAMAgAbAAcKrhnZFgAMAgAcAAEKAAAcaAA4AAAAAA==.Bread:BAAANQADCggIEgAAAA==.Brielle:BAABNQAECn8hAAIdAAkKdQ8xdAAlAgAdAAkKdQ8xdAAlAgAAAA==.Brimmnin:BAAANQADCgQIBAAAAA==.Brokenbranch:BAAANQAECgQIBwAAAA==.Brudene:BAAANQAECggIEwABNQAECggIKQAVAFkSAA==.Bruustag:BAAANQADCgEIAQAAAA==.Brynjarr:BAAANQADCgUIBQAAAA==.',
Bu='Bubblespop:BAAANQADCgcIBwAAAA==.Bubbletruble:BAAANQAECgIIAwAAAA==.Buddylock:BAAANQADCgEIAQAAAA==.Buffalowings:BAAANQAECgQIBAABNQADCgcIBwAMAAAAAA==.Bullymaguire:BAAANQAECgQIBAABNQAFFAYIDwAUAL0eAA==.',
Ca='Carpe:BAAANQAECgUIBQAAAA==.Catknipp:BAAANQADCgYIBgAAAA==.',
Ce='Ceromaar:BAABNQAECn8vAAINAAkK3hSybwBBAgANAAkK3hSybwBBAgAAAA==.',
Ch='Chaindeez:BAAANQAECgEJAQAAAA==.Charge:BAACNQAFFH8XAAINAAYKwyPqBgBNAgANAAYKwyPqBgBNAgA1AAQKfy8AAg0ACQqzJs8GALwDAA0ACQqzJs8GALwDAAAA.Checkurback:BAAANQAECgcIDwAAAA==.Chewtum:BAAANQAECgMIAwAAAA==.Chimo:BAABNQAECn8ZAAIeAAcKaAuLmABFAQAeAAcKaAuLmABFAQAAAA==.',
Ci='Cillah:BAAANQABCgEIAQABNQAECgkJJQAVANIbAA==.',
Co='Cobellex:BAAANQABCgUIBQAAAA==.Cops:BAABNQAECn8jAAIHAAgKYR6fKADEAgAHAAgKYR6fKADEAgAAAA==.',
Cr='Crimewave:BAAANQAECgcIBgAAAA==.Cruubakk:BAAANQADCgIIAgAAAA==.',
Cy='Cy:BAAANQAECgQICQAAAA==.',
Da='Danaconda:BAAANQABCgQIBgABNQAECgYIDAAMAAAAAA==.Darkenergy:BAABNQAECn8lAAIfAAgKwCAsGQDOAgAfAAgKwCAsGQDOAgAAAA==.Darà:BAAANQADCgcIBwABNQAECgYIEgAMAAAAAA==.Dashyll:BAAANQAECgUICgAAAA==.Dazzled:BAAANQADCgcIBwAAAA==.',
De='Deadlegslul:BAABNQAECn8ZAAIdAAcKZxzHawA5AgAdAAcKZxzHawA5AgAAAA==.Deathhelix:BAAANQADCgEJAQAAAA==.Deathmono:BAAANQAECgIIAwAAAA==.Deathshark:BAAANQADCgQIBAABNQAECgkJJgATAModAA==.Demacus:BAAANQAECggICgAAAA==.Demeter:BAABNQAECn8cAAIGAAcKgBH3KgCBAQAGAAcKgBH3KgCBAQAAAA==.Denalli:BAAANQAECgYIBwAAAA==.Devouress:BAAANQAECgEIAgAAAA==.',
Dh='Dhracian:BAAANQADCgYIBgAAAA==.',
Di='Dillkiller:BAAANQADCgcIFwAAAA==.Dimeniare:BAAANQADCggIHAAAAA==.Dirgen:BAAANQAECgYIDwAAAA==.Dirtymagic:BAAANQAECgUIBQAAAA==.',
Do='Docktorwhom:BAAANQADCgQIBAAAAA==.Dogmaww:BAAANQAECgMIBAAAAA==.Dookiee:BAAANQADCggIDgAAAA==.Dorkma:BAAANQABCgMIAwAAAA==.Doublenickel:BAAANQAECgYIEwAAAA==.',
Dr='Dragönlöl:BAAANQADCgUIBQAAAA==.Drakkaris:BAAANQAECgQIBgABNQAECgEIAgAMAAAAAA==.Drat:BAAANQAECgcIEwAAAA==.Drimbarn:BAAANQADCggICAAAAA==.Drustan:BAAANQADCgIIAgABNQAECggIEwAMAAAAAA==.',
Du='Duridon:BAAANQAECgIIAgAAAA==.',
Dy='Dyorna:BAAANQADCgcIDAAAAA==.',
Eb='Ebojager:BAABNQAECn8cAAIgAAcKfhkBJgASAgAgAAcKfhkBJgASAgAAAA==.',
Ed='Eddardstark:BAAANQADCgQIBAAAAA==.',
Ei='Eibon:BAACNQAFFH8JAAIXAAYKkhAqBADtAQAXAAYKkhAqBADtAQA1AAQKfxkAAhcACQoDIfktAHcCABcACQoDIfktAHcCAAAA.',
El='Eldric:BAABNQAECn8pAAIVAAgKWRJbswAbAgAVAAgKWRJbswAbAgAAAA==.Elvispriesty:BAAANQAECgQIBAAAAA==.Elvymir:BAAANQABCggIDQAAAA==.Elwarrioro:BAAANQAECgEIAQABNQAECgkJKwACABMgAA==.',
En='Enabran:BAAANQAECgEIAQAAAA==.',
Er='Ere:BAABNQAECn8YAAMQAAgK4QjEQABBAAAVAAgK4QhVqAFoAAAQAAEKAADEQABBAAAAAA==.Erus:BAAANQADCgEIAQAAAA==.',
Es='Eskath:BAAANQAECgQIDwABNQAECggIHwAVAGQWAA==.Essential:BAABNQAECn8iAAICAAkKcBPGewAvAgACAAkKcBPGewAvAgAAAA==.',
Ev='Evavaria:BAABNQAECn8aAAIHAAcKxhnSUgAfAgAHAAcKxhnSUgAfAgABNQABCggIEwAMAAAAAA==.Evdoggy:BAAANQAECgYIDgAAAA==.Eveleonoc:BAAANQABCgMIAwAAAA==.',
Ex='Exterminate:BAAANQAECgMIBgAAAA==.',
Fe='Fellina:BAAANQAECgQIBgAAAA==.Felparsnip:BAEANQAECgIIAgABNQAECgkJJwADAOAUAA==.Felpickles:BAAANQADCgUIBQABNQADCgcIBwAMAAAAAA==.Ferrara:BAACNQAFFH8RAAMhAAYKKSKpAwBHAgAhAAYKKSKpAwBHAgAdAAEKAABaLQBlAAA1AAQKfyYAAiEACQpFI5UPAOwCACEACQpFI5UPAOwCAAAA.',
Fi='Filthi:BAAANQAFFAEIAQAAAA==.Fiz:BAAANQADCgYIBgABNQAECgcICAAMAAAAAA==.Fizzbang:BAAANQADCgYICAABNQADCgcIBwAMAAAAAA==.',
Fl='Flandri:BAACNQAFFH8PAAIDAAUK3w9QEQCBAQADAAUK3w9QEQCBAQA1AAQKfyIAAgMACQrwI/IQAD4DAAMACQrwI/IQAD4DAAAA.',
Fo='Forehead:BAAANQADCgYJBwAAAA==.Foskins:BAAANQAECgQIBAABNQAECgcIGQAeAGgLAA==.',
Fr='Fraliende:BAAANQADCgYIBgABNQABCggIEwAMAAAAAA==.Frostednip:BAABNQAECn8wAAMWAAkKEx1jFADmAgAWAAkKEx1jFADmAgAXAAIKYQVIzQBOAAAAAA==.',
Fu='Fuzz:BAAANQADCgUIBQAAAA==.',
Ga='Gabaghoul:BAAANQADCgMIAwAAAA==.Gabiru:BAABNQAECn8qAAIBAAkKnRxSCQAMAwABAAkKnRxSCQAMAwAAAA==.Gadreeste:BAAANQAECgQIBAAAAA==.Galnarn:BAACNQAFFH8SAAIiAAYK6yGKAQAFAgAiAAYK6yGKAQAFAgA1AAQKfycAAiIACQqiJW0CAIIDACIACQqiJW0CAIIDAAAA.Gambagood:BAAANQAECgIIBgAAAA==.Gank:BAECNQAFFH8TAAIiAAUK5xr7AgCeAQAiAAUK5xr7AgCeAQA1AAQKfysAAyIACQopIfcGANICACIACQo/HfcGANICABwACQppH90YAHsCAAAA.Garjingo:BAAANQADCgEIAQABNQAECgYIEAAMAAAAAA==.Garlicbae:BAAANQAECgMIAwAAAA==.Garrgh:BAAANQADCgcIBwAAAA==.Garwulf:BAAANQAECgUIBwAAAA==.',
Ge='Gefaustet:BAABNQAECn8lAAIOAAgKAxXPFQDHAQAOAAgKAxXPFQDHAQAAAA==.Gewch:BAAANQADCgEIAQAAAA==.',
Gl='Glyd:BAAANQAECgEIAQABNQAECggICgAMAAAAAA==.',
Go='Goldenred:BAAANQAECgQICQAAAA==.',
Gr='Graybrew:BAAANQAECgMIAwAAAA==.Grayes:BAAANQAECgQIDAABNQAECgMIAwAMAAAAAA==.Grayze:BAAANQADCgUIBQABNQAECgMIAwAMAAAAAA==.Grelin:BAAANQAECgUIDgAAAA==.Grizzlydeath:BAAANQAECgEIAQAAAA==.Grog:BAAANQAECggICQAAAA==.',
Gu='Gumption:BAAANQADCgMIAwAAAA==.',
Ha='Hail:BAAANQAECgIIAgABNQAFFAMIBwAjAGkXAA==.Hamshamwhich:BAAANQADCgQIBAABNQADCgcIBwAMAAAAAA==.Harmôny:BAAANQADCgYICQAAAA==.Hatredno:BAAANQADCgQIBAAAAA==.Hatredyes:BAABNQAECn8nAAIkAAkKAxOlFgD6AQAkAAkKAxOlFgD6AQAAAA==.',
He='Helare:BAABNQAECn8gAAIJAAgKqRH3PwD4AQAJAAgKqRH3PwD4AQAAAA==.Helowyn:BAAANQADCggIDAAAAA==.Hexenbane:BAAANQAECgUIDQAAAA==.',
Ho='Holyghosst:BAAANQADCgEIAQAAAA==.',
Hy='Hyasin:BAAANQAECgYICAAAAA==.Hype:BAAANQADCgUIBQAAAA==.',
Ic='Ice:BAAANQAECgEIAgABNQAECgMIAgAMAAAAAA==.',
Id='Idlewild:BAEANQADCgYIBgABNQAECgQICQAMAAAAAA==.',
Ig='Ignazio:BAAANQADCgEIAQAAAA==.',
Ih='Ihorns:BAAANQADCgIIAgAAAA==.',
Ik='Ikedizzy:BAAANQAECgMIAgAAAA==.Ikor:BAAANQAECgUIDAAAAA==.Ikrys:BAAANQAECgYICwAAAA==.',
Il='Ilandrea:BAAANQABCgYIDgAAAA==.Illiae:BAABNQAECn8jAAIUAAgKpCIcFgBCAwAUAAgKpCIcFgBCAwAAAA==.',
Im='Impactr:BAAANQADCgYIBgAAAA==.',
In='Insecure:BAAANQAECgQIBgAAAA==.',
Io='Ionic:BAAANQAECgcIDgAAAA==.',
Is='Issidora:BAAANQAECgUIDQAAAA==.',
Iv='Ivvy:BAAANQADCgMIBAAAAA==.',
Ix='Ix:BAAANQADCgQJBAAAAA==.',
Ja='Jagtat:BAAANQADCgQIBAAAAA==.Jakeakuma:BAABNQAECn8dAAIYAAkKZQpLiwDGAQAYAAkKZQpLiwDGAQAAAA==.Janeleonoc:BAAANQABCgEIAQAAAA==.Janja:BAAANQABCgIIAgABNQAECgkJJQAVANIbAA==.Jascob:BAAANQAECgMIAwAAAA==.Jaynne:BAAANQAECgEIAQAAAA==.',
Ji='Jimmywhisky:BAAANQADCgIIAgAAAA==.',
Jo='Johnivxx:BAAANQADCggICgAAAA==.',
Ju='Judokeg:BAABNQAECn8eAAIcAAgK3hfKJAD6AQAcAAgK3hfKJAD6AQAAAA==.',
['Jà']='Jàckblack:BAAANQADCgMIBQAAAA==.',
Ka='Kaandi:BAAANQADCgYIBgAAAA==.Kaashaa:BAABNQAECn8vAAIdAAkKfSLnEABeAwAdAAkKfSLnEABeAwAAAA==.Kaelsgf:BAABNQAECn8pAAIDAAkKnByxHwDvAgADAAkKnByxHwDvAgAAAA==.Kahllan:BAAANQAECgYIEgAAAA==.Kahnigitt:BAAANQADCgMIBQAAAA==.Kalsifire:BAAANQADCgYIBgAAAA==.Kataltoholic:BAAANQAECgQIDgAAAA==.Kayhas:BAAANQADCgIIAwAAAA==.Kayser:BAAANQAECgMIBAAAAA==.Kazarel:BAAANQADCggIDAAAAA==.',
Ke='Keheo:BAAANQADCgMIAwAAAA==.Kelinïsha:BAAANQAECgUICAAAAA==.Kenf:BAAANQAECgEIAwAAAA==.Kensshaman:BAAANQAECgEIAgAAAA==.Kevinbacon:BAAANQAECgEIAQAAAA==.',
Kh='Khelina:BAAANQAECgYICgAAAA==.Khelldyr:BAAANQADCggIGgABNQAECgYICgAMAAAAAA==.',
Ki='Kiiras:BAAANQAECgMIBAAAAA==.Kimbodh:BAACNQAFFH8RAAIgAAUKliIOBQDjAQAgAAUKliIOBQDjAQA1AAQKfykAAiAACQoDJGcFAHsDACAACQoDJGcFAHsDAAAA.Kimoora:BAAANQADCgcIDAAAAA==.Kimshady:BAAANQADCgcICAABNQADCgcIDAAMAAAAAA==.Kirathein:BAAANQAECgIIAgAAAA==.',
Kl='Klefthoof:BAABNQAECn8kAAMUAAYKJQiPsgApAQAUAAYKJQiPsgApAQAeAAUKKQuKvgDoAAABNQAECggICgAMAAAAAA==.',
Ko='Kodey:BAAANQAECgQICQABNQAECggIIgAaAKYPAA==.',
Kr='Krelon:BAAANQADCggIDwAAAA==.Krimboz:BAAANQAECgUIBwAAAA==.Krystallight:BAABNQAECn8iAAIlAAgKzSEEAwDuAgAlAAgKzSEEAwDuAgAAAA==.',
La='Lanwulf:BAAANQADCggIEAAAAA==.Lazreki:BAAANQABCgcIBwAAAA==.',
Le='Lechuzón:BAAANQADCgQIBAAAAA==.Legaloas:BAABNQAECn8wAAIdAAkKbxxzLQDjAgAdAAkKbxxzLQDjAgAAAA==.Leinhart:BAAANQAECgUIBQAAAA==.Lenah:BAAANQADCgMIAwABNQAECgMIAwAMAAAAAA==.Leondero:BAABNQAECn8iAAIdAAkKCRteLwDdAgAdAAkKCRteLwDdAgAAAA==.Leroyjenkins:BAAANQADCggIFAAAAA==.Leuthil:BAAANQAECgUIBwABNQAECgEIAgAMAAAAAA==.',
Li='Lintilla:BAAANQADCgcICAAAAA==.',
Ll='Llevanya:BAABNQAECn8lAAICAAgKTA7hrADAAQACAAgKTA7hrADAAQAAAA==.',
Lo='Lofi:BAABNQAECn8bAAIeAAgKXAkZjgBiAQAeAAgKXAkZjgBiAQAAAA==.Lokkhar:BAAANQAECgEIAQAAAA==.Loredalso:BAAANQAECgUIDwAAAA==.',
Lu='Lubricated:BAAANQAECgYICQAAAA==.Lucíewilde:BAAANQADCgQIBAAAAA==.Luxon:BAAANQAECgUICgAAAA==.',
['Lè']='Lèdrollan:BAABNQAECn8qAAMdAAkK6yFMEQBcAwAdAAkK6yFMEQBcAwAhAAEKAAC0mAAlAAAAAA==.',
Ma='Magicdreams:BAAANQAECgYIEwAAAA==.Mahll:BAAANQAECgIIAgABNQAECggIEgAMAAAAAA==.Malmorte:BAAANQADCgYIBgAAAA==.Malorane:BAAANQAECgEIAQAAAA==.Malorix:BAABNQAECn8rAAIUAAkKsBg6OQCOAgAUAAkKsBg6OQCOAgAAAA==.Maléficaa:BAAANQADCgQIBAAAAA==.Materia:BAAANQAECgYICQAAAA==.Materialism:BAAANQADCgQIBAAAAA==.Maz:BAAANQAECgUIBgAAAA==.',
Mc='Mcflury:BAAANQADCggIDgAAAA==.',
Me='Meatbeef:BAAANQAECgYIDAAAAA==.Meerchi:BAAANQAECgYICAAAAA==.Meknin:BAABNQAECn8fAAIVAAgKzgRrDQFzAQAVAAgKzgRrDQFzAQAAAA==.Meldia:BAAANQAECgYIBwAAAA==.Merlinsdog:BAAANQADCgMIAwAAAA==.Mesmal:BAAANQAECgEIAQABNQAECggIBAAMAAAAAA==.Mesthos:BAAANQAECgEIAQABNQAECggIEwAMAAAAAA==.',
Mi='Mickieta:BAABNQAECn8lAAICAAgK3xx2VQCSAgACAAgK3xx2VQCSAgAAAA==.Mikalau:BAABNQAECn8lAAIdAAgK5BipVgBsAgAdAAgK5BipVgBsAgAAAA==.Mikaluu:BAAANQADCggIFQAAAA==.Milktide:BAAANQADCgUIBwABNQAECgkJGQAYAFceAA==.Minishields:BAAANQAECgMIBAAAAA==.Missteek:BAAANQAECgIIAwABNQAECgYIEAAMAAAAAA==.Mistrunner:BAAANQADCgYIBgAAAA==.Mistspell:BAABNQAECn8vAAMDAAkK7BnbMACiAgADAAkK7BnbMACiAgAEAAgKrRfvIAAtAgAAAA==.',
Mo='Mochacho:BAAANQADCgYIBgABNQAECgcIGQAeAGgLAA==.Mognel:BAAANQAECgYICAAAAA==.Moomootus:BAABNQAECn8pAAICAAkKXyKqNwDuAgACAAkKXyKqNwDuAgAAAA==.Mordenkainen:BAAANQABCgYICgAAAA==.Motoraxe:BAABNQAECn8dAAINAAkKLBJbiQAAAgANAAkKLBJbiQAAAgAAAA==.',
My='Mystynight:BAAANQADCgUIBgAAAA==.',
Na='Naajin:BAAANQADCgcIDAAAAA==.Nabyano:BAAANQAECgEIAQAAAA==.Nauty:BAAANQABCgYICQAAAA==.',
Ne='Newt:BAAANQADCggIEQAAAA==.',
Ni='Nicegauges:BAEBNQAECn8nAAMDAAkK4BQ/PwBqAgADAAkK4BQ/PwBqAgAEAAgKgg1sKgDRAQAAAA==.Nightcrest:BAAANQAECgUICAAAAA==.Nightrocks:BAAANQAECgYICQAAAA==.Nilfgard:BAAANQAECgUIDAAAAA==.Nivix:BAAANQADCgQICAAAAA==.Niyyx:BAAANQAECgQIBgAAAA==.',
No='Nordrydsh:BAAANQADCgcIBwABNQAECgYICgAMAAAAAA==.Noslock:BAAANQABCgYIBgAAAA==.Nosprey:BAAANQABCgEIAQAAAA==.Nosred:BAAANQADCggICAAAAA==.',
Nu='Nuhpie:BAACNQAFFH8QAAINAAYKeRpXCwD2AQANAAYKeRpXCwD2AQA1AAQKfyQAAg0ACQqPI7M4AN8CAA0ACQqPI7M4AN8CAAAA.',
Ny='Nybish:BAAANQADCgYIBwAAAA==.',
Oc='Occultfish:BAAANQAECgIIAgAAAA==.',
Ol='Olimdar:BAACNQAFFH8MAAIeAAYK+xmhBQANAgAeAAYK+xmhBQANAgA1AAQKfyEAAh4ACQpBIqYMAFkDAB4ACQpBIqYMAFkDAAAA.',
Oo='Oopositive:BAAANQADCgIIAgAAAA==.',
Or='Oraion:BAABNQAECn8fAAMVAAgKZBZtwwD7AQAVAAcKVBdtwwD7AQAQAAEKthE9QABCAAAAAA==.',
Ot='Otimion:BAAANQADCgMIAwAAAA==.',
Ov='Ovarb:BAAANQAECgYICQAAAA==.',
Pa='Pallydan:BAAANQAECgcIDwABNQAECggIHwAVAGQWAA==.Pan:BAAANQAECgEIAQAAAA==.Pathofpain:BAAANQADCgEIAQAAAA==.',
Pe='Peachie:BAAANQAECgQICAAAAA==.Persicles:BAAANQAECgYIBwAAAA==.',
Pi='Pissedwolf:BAAANQADCgEIAQAAAA==.',
Po='Polong:BAAANQADCgUIBQAAAA==.Pompouspear:BAAANQADCgcIBwAAAA==.Poutine:BAAANQAECgIIAQAAAA==.',
Pr='Prisman:BAAANQAECgUIBQAAAA==.Proserpìne:BAAANQAECgYIEAAAAA==.',
Pu='Pummel:BAAANQADCgQIBAAAAA==.Putt:BAAANQADCgYICwAAAA==.',
Qo='Qoolkumquat:BAAANQADCgcIBwAAAA==.',
Qu='Quoril:BAABNQAECn8mAAIVAAkKjxgffgCCAgAVAAkKjxgffgCCAgAAAA==.',
Ra='Radiyra:BAAANQABCgIIAgAAAA==.Ragnahr:BAAANQAECggIBAAAAA==.Rainstormin:BAAANQAECgYICQAAAA==.Raitan:BAAANQAECgYIEAABNQAECgcIBwAMAAAAAA==.Raivoker:BAAANQAECgcIBwAAAA==.Rakarra:BAAANQADCgIIAgAAAA==.Rantah:BAAANQADCgQIBAAAAA==.Rawrstance:BAABNQAECn8YAAIPAAgKhAe3xQA5AAAPAAgKhAe3xQA5AAABNQADCgcIBwAMAAAAAA==.Razgrize:BAAANQAECgMIAwAAAA==.',
Re='Reilin:BAAANQAECgUIBgAAAA==.Remsham:BAAANQAECgUIDQAAAA==.Renwyck:BAAANQAECggIEwAAAA==.Reovar:BAAANQABCgQIBAAAAA==.Reovarr:BAAANQADCgIIAgAAAA==.Revengemoon:BAABNQAECn8uAAICAAkKDiDnLAARAwACAAkKDiDnLAARAwAAAA==.',
Ro='Robane:BAAANQAECgMIAwAAAA==.Rouen:BAAANQAECgUIDQAAAA==.',
Ru='Rubidea:BAAANQAECgMIBAAAAA==.Ruckus:BAEANQAECgQICQAAAA==.Rudder:BAAANQAECgcIDQAAAA==.Rude:BAAANQAECgIIBAAAAA==.Ruder:BAAANQADCgEIAQABNQAECgkJJwAkAAMTAA==.Rutabaga:BAAANQADCgIIAgAAAA==.',
Ry='Rythas:BAAANQADCgUIBQAAAA==.',
Sa='Safetwo:BAAANQADCgUICAABNQAECggIJQADADwZAA==.Sahranna:BAAANQABCgIIAgAAAA==.Saintanic:BAAANQADCgcIBwAAAA==.Sandkat:BAABNQAECn8fAAMmAAkKiRiXBQDCAgAmAAkKiRiXBQDCAgANAAEKhRlQPgFOAAAAAA==.Santalight:BAAANQAECgEIAwABNQAFFAQICAAcABsaAA==.Santamoe:BAACNQAFFH8IAAIcAAQKGxp3CABXAQAcAAQKGxp3CABXAQA1AAQKfy4AAhwACAqIIgEOAPsCABwACAqIIgEOAPsCAAAA.Saraelin:BAAANQAECgMIAwAAAA==.Saray:BAABNQAECn8gAAIdAAkKkiH6FwA4AwAdAAkKkiH6FwA4AwAAAA==.Sarwyn:BAAANQADCgYIBgAAAA==.Saurelli:BAAANQADCgYICAABNQAFFAUIDQAjANoUAA==.',
Se='Sedak:BAAANQADCggIIQAAAA==.Seitana:BAAANQABCgQIBAAAAA==.Sevrus:BAAANQADCgYIBgAAAA==.',
Sh='Shadownlight:BAAANQADCgYIBgAAAA==.Shadysadie:BAAANQAECggICAAAAA==.Shamushamu:BAAANQADCgMIAwAAAA==.Shaqheal:BAAANQADCggIDwAAAA==.Shelaan:BAAANQAECgUIBgAAAA==.Shiftey:BAAANQAECgYIEgAAAA==.Shiftymage:BAAANQAECgQIBwABNQAECgYIEgAMAAAAAA==.Shirtles:BAAANQADCgcIDQAAAA==.Shockandmoo:BAAANQADCgUIBQABNQAECgQIBgAMAAAAAA==.Shèp:BAAANQAECgEIAQABNQAECgQICAAMAAAAAA==.',
Si='Sidecake:BAAANQADCgQIBAAAAA==.Singars:BAABNQAECn8eAAQZAAgKGhCXCgDJAQAZAAcKlRCXCgDJAQAYAAUKywo71wAWAQAaAAEKzgXbgAAqAAAAAA==.Sixseven:BAAANQADCgcJBwAAAA==.Siypra:BAABNQAECn8hAAIPAAgKMiDpHADHAgAPAAgKMiDpHADHAgAAAA==.',
Sk='Skelmir:BAAANQADCgYJCgAAAA==.',
Sn='Snokplaster:BAAANQADCgYIBwAAAA==.Snorri:BAABNQAECn8oAAMXAAkKCiVgCgBoAwAXAAkK6iRgCgBoAwAWAAgK9yBXEQAAAwAAAA==.Snowbvnny:BAAANQAECgEIBAAAAA==.',
So='Soleyn:BAAANQADCgYIBgAAAA==.Solie:BAAANQAECgUIBQAAAA==.Soto:BAAANQAECgEIAQAAAA==.Sotosan:BAAANQADCgMIAwAAAA==.',
Sp='Spacechicken:BAAANQADCgEIAQABNQAECgEIAgAMAAAAAA==.Sprintd:BAAANQADCgUIBQAAAA==.Sprodage:BAABNQAECn8ZAAIHAAgK6BfpSQA+AgAHAAgK6BfpSQA+AgAAAA==.',
St='Stanil:BAAANQAECgUIEAAAAA==.Steampunkz:BAAANQAECgEIAQAAAA==.Stellare:BAAANQAECgYIBgAAAA==.Strangetame:BAAANQADCgMIBAAAAA==.Striest:BAAANQAECgUIBwAAAA==.Styló:BAAANQAECgEIAgAAAA==.',
Su='Suelly:BAABNQAECn8lAAMVAAkK0huGYAC+AgAVAAkKGRqGYAC+AgAQAAQK9xqJHAAIAQAAAA==.Suguru:BAAANQAECggIEAAAAA==.Sularma:BAAANQAECgUIBgAAAA==.Sunsorrow:BAAANQADCggIDAABNQADCgcIBwAMAAAAAA==.Suraschi:BAABNQAECn8kAAIiAAgKBRb+DgD/AQAiAAgKBRb+DgD/AQAAAA==.',
Sw='Swisscake:BAAANQAECgEIAQAAAA==.Swtmystic:BAAANQAECggIAgAAAA==.',
Sy='Sygneus:BAAANQAECgIIAgAAAA==.Sylain:BAAANQADCggICQABNQAECgUIBwAMAAAAAA==.Synwav:BAABNQAECn8aAAIeAAkKOBgZMACfAgAeAAkKOBgZMACfAgAAAA==.',
Ta='Taiani:BAAANQABCgMIAwAAAA==.Taldrin:BAAANQADCgMIAwAAAA==.Tallinor:BAAANQAECgMIBAAAAA==.Tannatax:BAABNQAECn8aAAIeAAcK3ROteACeAQAeAAcK3ROteACeAQAAAA==.Tashah:BAAANQADCgYICwAAAA==.',
Te='Teamspidey:BAAANQADCgMIAwABNQAECgQIBAAMAAAAAA==.Tekvet:BAAANQAECggIBAAAAA==.Terminator:BAAANQADCgcIDQAAAA==.',
Th='Thewhitness:BAAANQAECgYICQAAAA==.Thewretch:BAAANQAECgYIEgAAAA==.Thumpthump:BAAANQAECgcIDwAAAA==.Thunderkiss:BAEANQADCggIFwABNQAECgQICQAMAAAAAA==.',
Ti='Tindoranis:BAAANQADCgIIAgAAAA==.',
To='Toastnbutta:BAAANQADCgYIBgAAAA==.Toothguy:BAAANQADCgMIAwAAAA==.Toscus:BAAANQADCgMIAwAAAA==.Totemii:BAAANQADCgYIBgAAAA==.',
Tr='Tradewarrior:BAABNQAECn8cAAINAAgKyxy8TQCdAgANAAgKyxy8TQCdAgAAAA==.Trayth:BAAANQAECggIBwAAAA==.Trevor:BAAANQADCgMIAwAAAA==.Trueheart:BAAANQAECgYIDAAAAA==.',
Ts='Tshark:BAABNQAECn8mAAMTAAkKyh1lBgAEAwATAAkKUR1lBgAEAwAkAAMK/x4XMAAVAQAAAA==.Tsura:BAABNQAECn8WAAIHAAgKGxK6ZQDkAQAHAAgKGxK6ZQDkAQAAAA==.',
Tu='Tutatotao:BAAANQABCgQIBgABNQADCgQIBQAMAAAAAA==.',
Ty='Tyduss:BAAANQADCgEJAQAAAA==.',
Un='Unclepeepers:BAABNQAECn8qAAMbAAkKxCBYBgAxAwAbAAkKxCBYBgAxAwAcAAkKWh3vFACqAgAAAA==.Underpowered:BAAANQADCgcIEAAAAA==.Unearthed:BAAANQADCgQIBAAAAA==.',
Ur='Urlän:BAAANQADCgYIBgAAAA==.',
Us='Usirina:BAAANQADCgUIBQABNQAECgkJJwAkAAMTAA==.',
Va='Vaeryn:BAAANQAECgYICAABNQAECgkJPAADALAaAA==.Valhen:BAABNQAECn88AAQDAAkKsBoCJQDVAgADAAkKKRoCJQDVAgAFAAcKgRZnCADeAQAEAAMKGwhzYAB6AAAAAA==.Valryn:BAAANQADCggICAABNQAECgkJPAADALAaAA==.Valtar:BAABNQAECn8nAAIeAAkKXCPDBwCCAwAeAAkKXCPDBwCCAwAAAA==.',
Ve='Velryn:BAAANQADCgYIDAABNQAECgkJPAADALAaAA==.',
Vi='Vicsen:BAAANQADCgUIBQAAAA==.Vikaya:BAAANQAECgQIBAAAAA==.Vilevixon:BAABNQAECn8lAAMEAAgKLh3bFQCtAgAEAAgKLh3bFQCtAgAFAAEKvAhgLQApAAAAAA==.',
Wa='Wagu:BAAANQABCgQIBAAAAA==.Walla:BAAANQADCgIIAgABNQAECgQIBAAMAAAAAA==.Wanlok:BAAANQAECgUIDwAAAA==.Warbuddy:BAAANQAECgEIAQAAAA==.Warmis:BAAANQADCgYICgAAAA==.Warriorlobo:BAABNQAECn8ZAAMNAAgKCRJejgD0AQANAAgKCRJejgD0AQAmAAEKdArdNAAvAAABNQAECgkJJQAVANIbAA==.Watts:BAABNQAECn8jAAIdAAgKuh3GLQDiAgAdAAgKuh3GLQDiAgABNQAECgkJJgAVAI8YAA==.',
We='Weez:BAAANQADCgUIBQAAAA==.',
Wi='Wildfang:BAABNQAECn8fAAMdAAgKZQ4ofwALAgAdAAgKZQ4ofwALAgAhAAEKAACAnwAUAAAAAA==.Wildside:BAAANQAECggIDgAAAA==.',
Xa='Xandronys:BAABNQAECn8fAAQZAAgKSxT+BgAzAgAZAAgKSxT+BgAzAgAYAAUKfRI51QAaAQAaAAEKvgkseQA0AAAAAA==.',
Xe='Xebec:BAAANQAECgcIDgAAAA==.',
Xy='Xyra:BAAANQAECgIIAgAAAA==.',
Ya='Yalik:BAAANQADCgMIAwABNQAECgQIBAAMAAAAAA==.Yalla:BAAANQAECgMIAwAAAA==.',
Ye='Yeet:BAAANQAECgcICAAAAA==.',
Yz='Yzugzugo:BAAANQAECggIDQAAAA==.',
Za='Zalckar:BAAANQAECgcIDwAAAA==.Zanos:BAAANQADCgcICgAAAA==.Zappyending:BAAANQAECgUIBQAAAA==.',
Ze='Zeeva:BAAANQAECgcIDwAAAA==.Zendead:BAAANQAECgcIDQAAAA==.',
Zi='Zigar:BAAANQAECgQIBAAAAA==.Zionspartan:BAAANQAECgcIDQAAAA==.',
Zu='Zugzugpriest:BAAANQAECgYICwAAAA==.Zurokhan:BAABNQAECn8xAAIHAAkKkxxvIwDcAgAHAAkKkxxvIwDcAgAAAA==.',
['Zø']='Zønda:BAABNQAECn8mAAMmAAcKySO6DwCrAQANAAUKZiNYpQC7AQAmAAQKmyS6DwCrAQAAAA==.',
['Ñå']='Ñårçîssîstîç:BAAANQAECggICAAAAA==.',
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
