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

local lookup = {'Druid-Balance','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Paladin-Retribution','Shaman-Restoration','Priest-Holy','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Unholy','Druid-Restoration','Paladin-Protection','DeathKnight-Blood','Warrior-Arms','Rogue-Assassination','Hunter-Marksmanship','Paladin-Holy','DemonHunter-Havoc','Priest-Discipline','Monk-Windwalker','DemonHunter-Vengeance','Shaman-Elemental','Priest-Shadow','Hunter-Survival','Mage-Arcane','Warlock-Affliction','Mage-Frost','Warrior-Fury','Rogue-Outlaw','Druid-Feral','Rogue-Subtlety','Druid-Guardian','Shaman-Enhancement','Monk-Mistweaver','Mage-Fire','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Blackhand',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Absorbency:BAAANQAECgYIBgABNQAFFAMIBQABAGwDAA==.',
Ae='Aeris:BAAANQAECgUIEQAAAA==.Aethwyn:BAAANQAECgUICQAAAA==.',
Ag='Agandaur:BAAANQAECgQICAAAAA==.',
Ah='Ahnkala:BAAANQADCggIJAAAAA==.',
Ai='Aigirlfriend:BAABNQAECoEnAAICAAgKzBEAJAAHAgACAAgKzBEAJAAHAgAAAA==.Aimdablame:BAAANQAECgEIAQAAAA==.',
Al='Allupcreepy:BAAANQAECgYIEgAAAA==.',
Am='Amalyndi:BAAANQAECgcIDAAAAA==.Ambewlance:BAABNQAECoEZAAMDAAgKMhYhhACuAQADAAYK5RUhhACuAQAEAAMKHxXgOQDPAAAAAA==.Amethystra:BAAANQAECgYIDAAAAA==.Amlu:BAAANQAECgUIBwABNQAECggIIgAFAHQgAA==.',
An='Andaconda:BAAANQAECgUICAAAAA==.Annimosity:BAAANQAECgEIAQAAAA==.Ansem:BAAANQAECgEJAQAAAA==.Anthesis:BAAANQAECgUICAABNQAECgkJJQAGAKgXAA==.Anúbis:BAAANQADCgUIDQAAAA==.',
Ap='Apawllo:BAAANQAECgEJAQAAAA==.Apep:BAAANQAECgQIBgAAAA==.Apostle:BAABNQAECoEZAAIHAAkKlR3/HQDfAgAHAAkKlR3/HQDfAgAAAA==.',
Ar='Aramìs:BAAANQADCggIFwAAAA==.Arcaya:BAAANQADCggIGgAAAA==.Ariaka:BAAANQADCgEIAQAAAA==.Arleen:BAAANQAECgQICwAAAA==.Arlida:BAABNQAECoEZAAIGAAgK+xaxTQABAgAGAAgK+xaxTQABAgAAAA==.Artemys:BAABNQAECoEbAAIIAAcKUxk/aAAYAgAIAAcKUxk/aAAYAgAAAA==.Aryto:BAAANQADCgUIBQAAAA==.',
As='Ashlar:BAAANQADCgEIAQAAAA==.Asketill:BAAANQADCgYIDwAAAA==.Asmodee:BAAANQAECgUIDgAAAA==.',
Au='Aure:BAAANQADCgYIDAAAAA==.Auren:BAAANQADCgIIAgAAAA==.',
Az='Azkadellia:BAAANQABCgQJCAAAAA==.Azonya:BAAANQABCgQIBAAAAA==.',
Ba='Baaloo:BAAANQABCgQIBAABNQAECgEIAQAJAAAAAA==.Bainne:BAAANQADCgUJCAAAAA==.Baitken:BAAANQAECgQICwABNQAECgYIEgAJAAAAAA==.Barktea:BAAANQAECgYIDwAAAA==.Batharel:BAAANQAECgQICwAAAA==.Battcantdps:BAAANQAECggIBgAAAA==.Battleground:BAAANQADCgMIAwAAAA==.',
Be='Bearen:BAAANQAECgcIEgAAAA==.Beertrain:BAABNQAECoEgAAIKAAgKVhfvOgARAgAKAAgKVhfvOgARAgAAAA==.Beesechurger:BAAANQAECgcIEAAAAA==.Belladue:BAAANQADCgcIHwAAAA==.Bellezza:BAABNQAECoEtAAILAAkKmhKVGwAvAgALAAkKmhKVGwAvAgAAAA==.Belphoebe:BAEANQABCgIIAgABNQAECgYICQAJAAAAAA==.',
Bh='Bhikku:BAAANQAECgcIDwABNQAECggIIgAFAHQgAA==.Bhilly:BAAANQADCggIHwAAAA==.',
Bi='Bigdumbcatqt:BAABNQAECoEiAAIMAAkKeCYzAAAFBAAMAAkKeCYzAAAFBAAAAA==.Bigdumbkatqt:BAACNQAFFIETAAINAAYKNCHIAgBMAgANAAYKNCHIAgBMAgA1AAQKgRYAAg0ACAqiJNcPABwDAA0ACAqiJNcPABwDAAAA.Bignjuicy:BAABNQAECoEcAAIOAAkK7RfjTQCFAgAOAAkK7RfjTQCFAgAAAA==.Bimisi:BAABNQAECoESAAIPAAgKpxC2LAD/AQAPAAgKpxC2LAD/AQAAAA==.',
Bl='Blades:BAAANQADCgMIBgAAAA==.Bloodshhot:BAABNQAECoEoAAIIAAgK0BbVSwBjAgAIAAgK0BbVSwBjAgAAAA==.Bloodthorne:BAAANQADCgQIBAAAAA==.Blueragebar:BAAANQAECgUICwAAAA==.',
Bo='Bobadasmash:BAABNQAECoEhAAIOAAgKwBNDeAAMAgAOAAgKwBNDeAAMAgAAAA==.Bobitt:BAAANQAECgEJAQAAAA==.Boddyknocker:BAAANQAECgYIDAAAAA==.Boombox:BAAANQADCgYIBgAAAA==.Boomvoker:BAAANQAECgEIAQABNQAFFAIIAgAJAAAAAA==.Boonerichard:BAAANQAECgQIBQAAAA==.Boopdoctor:BAAANQADCgQIBAAAAA==.Bouchewager:BAAANQADCgYIBgAAAA==.',
Br='Braina:BAAANQAECgYIDAAAAA==.Branwin:BAAANQADCgcIEgAAAA==.Braver:BAACNQAFFIEQAAIQAAYKtA6LCQCDAQAQAAYKtA6LCQCDAQA1AAQKgSoAAxAACQoiH/IQAM0CABAACQoiH/IQAM0CAAgAAQq4C0A5ATkAAAAA.Braverwar:BAAANQAECgIIAwABNQAFFAYIEAAQALQOAA==.Brayedine:BAAANQADCgcIFwAAAA==.Break:BAACNQAFFIEVAAIFAAcKGCCwAAC+AgAFAAcKGCCwAAC+AgA1AAQKgSIAAgUACQqFJowMAJEDAAUACQqFJowMAJEDAAE1AAUUBwoVAAUAGCAA.Bromungandr:BAAANQADCgYIDgAAAA==.',
Bu='Buligerent:BAAANQADCggIGAAAAA==.',
By='Bynnyy:BAAANQAECgIIAgAAAA==.',
['Bù']='Bùbbles:BAAANQAECgQIBwAAAA==.',
Ca='Cadelsaya:BAABNQAECoEsAAIRAAkKcw6YTAAXAgARAAkKcw6YTAAXAgAAAA==.Camandah:BAABNQAECoEdAAIBAAgKdhLhOQD4AQABAAgKdhLhOQD4AQABNQADCgUICQAJAAAAAA==.Cammandzar:BAAANQAECgIIAgABNQADCgUICQAJAAAAAA==.Candy:BAAANQABCgQIAgAAAA==.Canman:BAAANQAECgEIAQAAAA==.Carlo:BAAANQAECgEIAwAAAA==.Carryout:BAAANQAECggICwAAAA==.Caskca:BAAANQADCgEIAQAAAA==.Cassei:BAAANQAECgUICAAAAA==.Cassiell:BAAANQAECgEIAQAAAA==.Castertroy:BAAANQAECgYICQAAAA==.',
Ce='Celenia:BAAANQAECgIIAgAAAA==.',
Ch='Chainari:BAAANQAECgIIAgAAAA==.Charmless:BAAANQADCgcIDAABNQAECgkJLQASAKEcAA==.Chee:BAAANQADCggIFwAAAA==.Cheeksdakota:BAAANQAECgEIAQAAAA==.Cheetopaly:BAABNQAECoEZAAMRAAcKrRYAUwABAgARAAcKrRYAUwABAgAFAAYKxQbg5wARAQAAAA==.Chuga:BAAANQAECgQIBgABNQAECgcIEgAJAAAAAA==.Chìgusa:BAABNQAECoEkAAMHAAgKPSJkEwAcAwAHAAgKPSJkEwAcAwATAAUKcxUGDgA6AQAAAA==.',
Ci='Circa:BAAANQADCgEIAQAAAA==.',
Cl='Clarimonde:BAAANQADCgEIAQAAAA==.Cleaveradius:BAAANQADCggJCAABNQAECggIIAAGAGwfAA==.Clumonk:BAABNQAECoEbAAIUAAgKShtzFgByAgAUAAgKShtzFgByAgAAAA==.',
Co='Convoke:BAAANQADCggIEAABNQAECgkJGQAHAJUdAA==.Coosar:BAAANQAECgMIBAAAAA==.Coosedaplug:BAAANQADCgQIBAABNQAECgcIEgAJAAAAAA==.Cooseyloosey:BAAANQAECgcIEgAAAA==.Coosinator:BAAANQAECgYJCwABNQAECgcIEgAJAAAAAA==.Cooterray:BAAANQAECgUICAAAAA==.Corellon:BAAANQAECgYIEQAAAA==.Corinth:BAAANQAECgYJEAAAAA==.',
Cr='Cratoz:BAABNQAECoEiAAIFAAgKLR/aPgCzAgAFAAgKLR/aPgCzAgAAAA==.Croswind:BAABNQAECoEqAAIIAAkKXBXNOQCaAgAIAAkKXBXNOQCaAgAAAA==.',
Cu='Curandero:BAAANQADCgUIBQABNQAECgEIAQAJAAAAAA==.',
Cy='Cyndrine:BAABNQAECoEsAAIVAAkKxCWAAADXAwAVAAkKxCWAAADXAwAAAA==.Cyrani:BAABNQAECoErAAMWAAkKsCQtBADDAwAWAAkKsCQtBADDAwAGAAYKrCRJMgByAgAAAA==.',
Da='Dadipps:BAABNQAECoEhAAIGAAgKXB/rLACKAgAGAAgKXB/rLACKAgAAAA==.Daggumit:BAAANQADCggIGQAAAA==.Dagnei:BAAANQADCggIFwAAAA==.Daltina:BAAANQAECgUIEgAAAA==.Damage:BAAANQAECggIAgAAAA==.Dannyboone:BAAANQADCggICAABNQAECggIIQANAHkaAA==.Dareael:BAABNQAECoEcAAIFAAgKihQwfwD6AQAFAAgKihQwfwD6AQAAAA==.Darklighete:BAAANQABCgEIAQAAAA==.Daurgoth:BAAANQAECgcIDwAAAA==.Dazoner:BAAANQADCggIFQAAAA==.',
De='Deadbydrand:BAAANQAECggICwAAAA==.Deathndspark:BAABNQAECoEgAAINAAgKOwvvVwBxAQANAAgKOwvvVwBxAQAAAA==.Deathpuma:BAABNQAECoEiAAINAAkKyB1QFAD0AgANAAkKyB1QFAD0AgAAAA==.Deathrowe:BAABNQAECoEeAAIKAAgKjB6HIgCcAgAKAAgKjB6HIgCcAgAAAA==.Dednevoker:BAAANQAECgEIAQABNQAECggIEAAJAAAAAA==.Deelyte:BAAANQAECgIIAgAAAA==.Demonvann:BAAANQADCggICAAAAA==.Demítrá:BAAANQADCgIIAgABNQAECgkJKwAWAPwbAA==.Denouncer:BAAANQAECgQICAABNQAECggIIAAGAGwfAA==.Derca:BAAANQAECgQIDQAAAA==.Dethork:BAAANQADCgcIDAAAAA==.',
Di='Dieds:BAAANQADCgYIBgABNQAECggIEAAJAAAAAA==.Dienne:BAEANQAECgEIAQAAAA==.Dietunicorn:BAAANQADCggIKgABNQAECgMIBgAJAAAAAA==.Dinarra:BAAANQADCgUIBgAAAA==.Diosdelaluna:BAAANQADCgMIAwAAAA==.Dirtybyrd:BAAANQAECgEIAQAAAA==.Disahzter:BAABNQAECoEbAAMEAAgKFQ/vMwDoAAADAAcKkAxilgB+AQAEAAQK4A/vMwDoAAAAAA==.',
Do='Docbledore:BAAANQAECgcIBwAAAA==.Docdrood:BAAANQADCgcIBwABNQAECgcIBwAJAAAAAA==.Docmonk:BAAANQAECgEIAQABNQAECgcIBwAJAAAAAA==.Docpriest:BAAANQAECgYIDwABNQAECgcIBwAJAAAAAA==.Donlazul:BAAANQADCgQJBAAAAA==.Dotlotto:BAAANQAECgEJAgAAAA==.',
Dr='Draconoth:BAAANQAECgYIEAAAAA==.Dragfin:BAAANQAECgEIAQAAAA==.Dragonir:BAAANQAECgcIEwABNQAECggIIgAFAHQgAA==.',
Du='Dungard:BAAANQAECgEIAQABNQAECgkJLAARAHMOAA==.Dunstird:BAAANQAECgIIAgABNQAFFAIIAgAJAAAAAA==.',
Dy='Dyami:BAAANQAECgUICwAAAA==.',
['Dè']='Dèadèyè:BAAANQADCggJDgAAAA==.',
Ea='Eatmorechkn:BAABNQAECoEkAAIFAAgKRxNidwAOAgAFAAgKRxNidwAOAgAAAA==.',
Ee='Eellonwy:BAAANQADCggIGgAAAA==.Eemerald:BAAANQAECgQIBgAAAA==.',
Eg='Egna:BAAANQAECgcIEwAAAA==.',
El='Electricblu:BAAANQAECgQICAAAAA==.Elizaa:BAABNQAECoEYAAMGAAcKPA7UfwBeAQAGAAcKPA7UfwBeAQAWAAIKpQH8BgFFAAAAAA==.',
Em='Emaya:BAAANQAECgEIAQAAAA==.Emmadar:BAAANQAECgMIAwABNQAECggIJAAEAOsRAA==.',
Eu='Euripidus:BAAANQADCgEIAQAAAA==.',
Ev='Evilclared:BAAANQADCgUICgABNQAFFAQICwAOAFoWAA==.Evildean:BAAANQADCgYICgAAAA==.',
Ex='Execute:BAAANQADCgUICQAAAA==.',
Fa='Fanya:BAAANQADCgYIBgABNQAECgkJKQAXAGAeAA==.Fathernatur:BAAANQADCgYICQAAAA==.Fatherpain:BAAANQABCgYIEQAAAA==.',
Fe='Fenrigaar:BAABNQAECoEsAAIBAAkKgx8BEAA1AwABAAkKgx8BEAA1AwAAAA==.',
Ff='Ffsa:BAABNQAECoEpAAQIAAkKgB05KgDPAgAIAAkKdhs5KgDPAgAQAAgKOBjQGgBkAgAYAAEKahX8EAA5AAAAAA==.',
Fi='Fillin:BAAANQAECgEIAQAAAA==.Filô:BAABNQAECoEZAAIXAAkK0BqYFQCQAgAXAAkK0BqYFQCQAgAAAA==.Findinnan:BAAANQADCgUIBgAAAA==.',
Fl='Flame:BAAANQADCgQIBAAAAA==.Flintmini:BAAANQADCgQJBAAAAA==.Flossylock:BAAANQAECgEIAgAAAA==.',
Fo='Forsakenly:BAAANQADCggIEAAAAA==.',
Fr='Frasti:BAAANQAECgEIAQAAAA==.Frodes:BAAANQABCgYJBwAAAA==.Frostmage:BAABNQAECoEmAAIZAAgKuhXJlwAzAgAZAAgKuhXJlwAzAgAAAA==.',
Fu='Fuegoblazeit:BAAANQABCgIIAgAAAA==.Furbucket:BAAANQAECgQICwAAAA==.Futonhunts:BAABNQAECoEtAAIIAAkKASIhCQCEAwAIAAkKASIhCQCEAwAAAA==.',
Fy='Fylerw:BAAANQAECgUIEwAAAA==.',
Ga='Gailyn:BAAANQADCgYICgAAAA==.Galebb:BAAANQADCgcIDAABNQAECgUICwAJAAAAAA==.Gardros:BAAANQABCgQIBAAAAA==.',
Gh='Ghostrideher:BAAANQAECgcIDQAAAA==.',
Gi='Gigadad:BAACNQAFFIEFAAIIAAMKHBlgEAAUAQAIAAMKHBlgEAAUAQA1AAQKgSYAAggACQpeJeYGAJsDAAgACQpeJeYGAJsDAAAA.Gigafather:BAAANQADCgQIBAAAAA==.',
Gl='Gladiuz:BAAANQADCgcIBwABNQAECggIIgAFAHQgAA==.',
Go='Gornthemonki:BAAANQADCgcICgAAAA==.Goyahokasinj:BAAANQADCgYIEQAAAA==.',
Gr='Griannee:BAABNQAECoElAAISAAkKvRSMJwA4AgASAAkKvRSMJwA4AgAAAA==.Grimtoetem:BAAANQABCgYJCQAAAA==.Grislix:BAABNQAECoEaAAQaAAgKxBJ8CgCjAQAaAAcKaw58CgCjAQADAAYKVA8QpgBYAQAEAAEKLxkMZQBNAAAAAA==.Grismistea:BAAANQAECgEIAQABNQAECggIGgAaAMQSAA==.Grismunch:BAAANQABCggICAAAAA==.Gryffin:BAABNQAECoEZAAMbAAgKoRGkDAC5AQAbAAgKoRGkDAC5AQAZAAEKPwVEqAE0AAAAAA==.',
Gu='Guidance:BAAANQADCgcIBwAAAA==.Gulan:BAAANQADCgMIAwAAAA==.Gummies:BAAANQABCgYIDgAAAA==.',
['Gâ']='Gânk:BAABNQAECoEjAAIOAAgKeQ1/jADWAQAOAAgKeQ1/jADWAQAAAA==.',
Ha='Hanrekt:BAAANQAECgUICwAAAA==.Happiness:BAAANQAECgQIDQABNQAECgkJIwAIABEgAA==.',
He='Heavensbliss:BAAANQAECgQIBAABNQAECggIJgAZALoVAA==.Heavychevy:BAABNQAECoEWAAIcAAgKYxLMDADHAQAcAAgKYxLMDADHAQAAAA==.Hellvenger:BAAANQADCgMIAwAAAA==.Heriel:BAAANQAECgYIDgABNQAECggIIgAFAHQgAA==.Hexquisite:BAAANQAECgUIBAABNQAECgkJGQAHAJUdAA==.',
Hi='Hildoehealz:BAAANQAFFAEIAQAAAA==.',
Ho='Holybit:BAAANQAECgIIAgAAAA==.Hotsjkpurge:BAAANQADCgQIBAAAAA==.',
Hu='Humphrees:BAABNQAECoEnAAIPAAgKwRA8LAADAgAPAAgKwRA8LAADAgAAAA==.',
Hy='Hydrospin:BAAANQADCgQIBAAAAA==.Hypocrisy:BAAANQADCgcIEwAAAA==.',
['Hà']='Hàtos:BAABNQAECoEZAAIZAAcKXRAu1wCyAQAZAAcKXRAu1wCyAQAAAA==.',
Id='Idot:BAAANQADCgUJDgABNQAECgYIGQASAPYGAA==.',
Ii='Iironrod:BAAANQADCgUIBQAAAA==.',
Il='Illidave:BAAANQADCgYIBwABNQAECgUIEAAJAAAAAA==.',
In='Incubus:BAAANQAECgUICAABNQAECggIIgAFAHQgAA==.Inebriatas:BAAANQAECgEIAQABNQAECgUIEgAJAAAAAA==.Inu:BAAANQABCgIJAgAAAA==.Invissibill:BAABNQAECoEZAAIdAAcKsQeNDQBSAQAdAAcKsQeNDQBSAQAAAA==.',
Ir='Ironbark:BAAANQADCgUIBQAAAA==.',
Is='Ishaa:BAAANQAECggIDgAAAA==.',
Iv='Ivanä:BAAANQAECgYIEQAAAA==.',
Iz='Izax:BAABNQAECoEnAAQDAAcK7w4jnwBpAQADAAYK1A4jnwBpAQAEAAEKjw++bgA7AAAaAAEKYwaFLgAtAAAAAA==.',
Ja='Jaddzia:BAAANQABCgQIBAAAAA==.Jadestone:BAAANQADCgYIDAAAAA==.Jaguarkick:BAAANQADCggIGAAAAA==.Jarcor:BAAANQABCgQIBAAAAA==.',
Je='Jeffray:BAAANQABCgQIBAAAAA==.Jessi:BAAANQAECgUICQAAAA==.',
Jo='Jonsneew:BAAANQADCgYICgAAAA==.',
Ju='Judgment:BAAANQADCgMIBwAAAA==.Junglefu:BAAANQADCgIIAgAAAA==.Jupitus:BAAANQAECgUIBQAAAA==.Justin:BAAANQAECgUIBwABNQAECgYIBgAJAAAAAA==.',
['Jû']='Jûstin:BAAANQAECgYICAABNQAFFAQICgABAK0SAA==.',
Ka='Kabroz:BAAANQAECgQIBgAAAA==.Kale:BAAANQABCgYIBwAAAA==.Karma:BAAANQAECgUIEQAAAA==.Katalania:BAAANQAECgUIEQAAAA==.',
Ke='Keeshama:BAAANQADCgIIAgAAAA==.Kegna:BAAANQADCggIGAAAAA==.Keiwhenua:BAABNQAECoEcAAMLAAgKMhFeIwDeAQALAAgKMhFeIwDeAQAeAAEK6ANSPwAcAAAAAA==.Kelinn:BAAANQAECgQIBAAAAA==.Kelzier:BAAANQAECgQIDAABNQAECggIIgAFAHQgAA==.Kenthel:BAABNQAECoEYAAIfAAcKchcaFwAWAgAfAAcKchcaFwAWAgAAAA==.Kenthels:BAAANQADCgUIBQABNQAECgcIGAAfAHIXAA==.Kezt:BAAANQAECgIIAgABNQAECgIIAgAJAAAAAA==.',
Ki='Kiplander:BAABNQAECoEjAAMBAAUKgBOyXgAtAQABAAUKSxOyXgAtAQAgAAEKmw4TUQArAAAAAA==.Kiplandr:BAAANQADCgEIAQAAAA==.Kitheryn:BAAANQAECgEIAQAAAA==.',
Kl='Klitt:BAAANQAECgMIBAAAAA==.',
Ko='Komosky:BAACNQAFFIEXAAIUAAYKGgbPBQCDAQAUAAYKGgbPBQCDAQA1AAQKgSkAAhQACQrmFrwaADwCABQACQrmFrwaADwCAAAA.Korry:BAAANQAECgQIBgAAAA==.Kortanis:BAAANQAECgUIDQAAAA==.',
Kr='Krakìn:BAAANQAECgQIBgAAAA==.',
Ku='Kush:BAABNQAECoEZAAQEAAgKjA2vFgCvAQAEAAgKRAqvFgCvAQADAAUKvwqMwgAYAQAaAAEKcBDSKQA6AAAAAA==.',
Ky='Kyana:BAAANQADCgYICgAAAA==.Kyrianna:BAAANQAECgEIAQAAAA==.Kyäk:BAAANQADCgQIBAAAAA==.',
['Kü']='Küngfury:BAAANQADCgUIBQAAAA==.',
La='Laerik:BAAANQABCgEIAQAAAA==.Landissa:BAABNQAECoEXAAIfAAgKUA3BGgDuAQAfAAgKUA3BGgDuAQAAAA==.Larcenciel:BAAANQAECgUICQAAAA==.Larryholmes:BAAANQABCgQIBAABNQADCggICAAJAAAAAA==.',
Le='Leen:BAAANQABCgYICQAAAA==.Letmehelpyou:BAABNQAECoEgAAIGAAgKbB+uKgCVAgAGAAgKbB+uKgCVAgAAAA==.',
Li='Licky:BAAANQAECgcIEQAAAA==.Lihan:BAAANQAECgYIEQAAAA==.Lilieth:BAAANQADCggIDAAAAA==.Lily:BAABNQAECoEpAAIKAAgKIiEPGQDcAgAKAAgKIiEPGQDcAgAAAA==.Lively:BAAANQAECgUIDwAAAA==.',
Lo='Lockedtoit:BAAANQAECgIIAgAAAA==.Loverocket:BAABNQAECoEbAAIMAAgKPR7gDgCJAgAMAAgKPR7gDgCJAgAAAA==.',
Lu='Luna:BAAANQAECgUIBQABNQAECgYICgAJAAAAAA==.Lunastorm:BAAANQADCgQJBAAAAA==.',
Ly='Lyshia:BAABNQAECoEsAAMZAAkKSB3PQgDwAgAZAAkKRh3PQgDwAgAbAAIKkB7OIgC1AAAAAA==.',
['Lí']='Líghthand:BAABNQAECoEUAAMMAAgKmhpBFgAkAgAMAAgKmhpBFgAkAgAFAAEK/wE2pgETAAAAAA==.',
['Lý']='Lýght:BAAANQADCgcIDQAAAA==.',
Ma='Magedown:BAABNQAECoEhAAMZAAgKwhPwnwAiAgAZAAgKwhPwnwAiAgAbAAEKkAUTSgAhAAAAAA==.Magician:BAAANQADCggICAAAAA==.Mamachula:BAAANQADCgYIDQAAAA==.Manapali:BAAANQAECgQIBAABNQAECgkJKAAhAJsfAA==.Manpumper:BAAANQAECgYICAAAAA==.Margor:BAAANQAECgQICwABNQAECgYIEgAJAAAAAA==.Mattdemon:BAABNQAECoEtAAMSAAkKoRxoEQD6AgASAAkKmBxoEQD6AgACAAcKyBIWLgCuAQAAAA==.',
Me='Meanzy:BAAANQADCgQIBAAAAA==.Meliany:BAAANQAECgMIBgAAAA==.Meliorate:BAACNQAFFIEFAAIBAAMKbAP5FwC6AAABAAMKbAP5FwC6AAA1AAQKgSEAAwEACQqKFIgzACMCAAEACQqKFIgzACMCAAsABgqdCQc4ACcBAAAA.Meowch:BAABNQAECoEiAAIeAAgKjyBiBQD+AgAeAAgKjyBiBQD+AgAAAA==.',
Mi='Mikachu:BAABNQAECoE9AAIhAAkKlCZ3AADkAwAhAAkKlCZ3AADkAwABNQAFFAUIDgAFAAYWAA==.Miksi:BAAANQADCgYIDgABNQAECgEIAQAJAAAAAA==.Miradele:BAAANQAECgYIEgAAAA==.Miraxx:BAAANQAECgEIAQAAAA==.Misscleö:BAAANQAECgcIEwAAAA==.Miyoshi:BAABNQAECoEiAAIfAAcKjAr9IgCdAQAfAAcKjAr9IgCdAQAAAA==.',
Mo='Mobius:BAAANQABCgIIBQAAAA==.Moonshíne:BAAANQADCgIIAgAAAA==.Moosakka:BAABNQAECoEhAAIiAAgKAxQ4FgDpAQAiAAgKAxQ4FgDpAQAAAA==.Moosesiah:BAAANQABCgYICgABNQAECggIIwAiAMwZAA==.Moovinthru:BAAANQADCggIIgAAAA==.Moraxes:BAAANQAECgUIBgAAAA==.Mordenkainen:BAAANQAECgUIDAAAAA==.Morgax:BAAANQAECgcIEwAAAA==.Morgona:BAAANQADCgUICQAAAA==.Morphidmage:BAAANQADCgUIBQAAAA==.Motoko:BAAANQADCgYIGAAAAA==.',
Mu='Muaadib:BAAANQAECgYIEQABNQAECgkJKgAIAFwVAA==.',
My='Mydin:BAABNQAECoEdAAIFAAgKmhMcgQD1AQAFAAgKmhMcgQD1AQAAAA==.Myssaphra:BAABNQAECoElAAMGAAkKqBfUNwBYAgAGAAkKqBfUNwBYAgAWAAEKRAeSKQEoAAAAAA==.',
['Mì']='Mìsawa:BAAANQAECggIEAAAAA==.',
Na='Nakai:BAABNQAECoEhAAIIAAgKZRs5OACfAgAIAAgKZRs5OACfAgAAAA==.Nasatra:BAAANQADCgcICwAAAA==.Nastijiggle:BAABNQAECoEZAAIXAAgKFhsFHABCAgAXAAgKFhsFHABCAgAAAA==.Nazrien:BAAANQABCgUJBQAAAA==.Nazrion:BAAANQABCgEIAQAAAA==.',
Nc='Nc:BAAANQAECgcIEAAAAA==.',
Ne='Nexxa:BAABNQAECoEcAAIIAAgKQwwheADwAQAIAAgKQwwheADwAQAAAA==.',
Ni='Nightshadow:BAAANQADCgQIBAAAAA==.Nightsongs:BAAANQABCgIIAgAAAA==.Niqkle:BAABNQAECoEmAAMGAAkKZRFgYwC0AQAGAAgK2Q9gYwC0AQAWAAgK2wuNaQCzAQAAAA==.Nitebane:BAABNQAECoEcAAIPAAgKrAomMwDVAQAPAAgKrAomMwDVAQAAAA==.',
No='Nohurtscooby:BAAANQAECgEIAQAAAA==.Notadh:BAAANQADCggIEAAAAA==.Notadruid:BAAANQADCgQIBAAAAA==.Notawrlock:BAAANQAECgEIAQABNQAFFAIIAgAJAAAAAA==.',
Ns='Nstagatr:BAAANQAECgUIEAAAAA==.',
Ny='Nyxandria:BAAANQABCgQIBAAAAA==.Nyxi:BAAANQABCgQIBAAAAA==.',
Oa='Oak:BAAANQAECgIIAgAAAA==.',
Oc='Occidius:BAAANQAECgMIAwAAAA==.',
Ol='Olari:BAAANQAECgEIAQAAAA==.Oldfox:BAAANQAECgEIAgAAAA==.Oldoriel:BAAANQADCgYICwAAAA==.Olehanna:BAABNQAECoEkAAIFAAgKfg4+kADQAQAFAAgKfg4+kADQAQAAAA==.Olestrid:BAAANQADCggIJgABNQAECggIJAAFAH4OAA==.',
On='Oni:BAAANQADCgYICAAAAA==.',
Op='Opioid:BAAANQAECgMIAwAAAA==.Opsec:BAAANQAECgIJAgABNQAECgcIGAACAO8RAA==.Opsèc:BAABNQAECoEYAAICAAcK7xEqLQC2AQACAAcK7xEqLQC2AQAAAA==.',
Or='Orsa:BAAANQADCggICAAAAA==.',
Pe='Peachshock:BAECNQAFFIEaAAMGAAcKuRuiAQCHAgAGAAcKuRuiAQCHAgAWAAMKmwzJFgDgAAA1AAQKgSAAAwYACQrQJfkGAHwDAAYACQrQJfkGAHwDABYABAroH6aPAEwBAAAA.Peachyknight:BAAANQAECgQIBAAAAA==.Peebee:BAAANQAECgMIAwABNQAECggIMwAOABghAA==.Perfectlock:BAABNQAECoEfAAIDAAgKuxk5QAB2AgADAAgKuxk5QAB2AgAAAA==.',
Pi='Pigog:BAAANQAECgUIDAAAAA==.',
Po='Pooskbuddy:BAAANQADCgcIBwAAAA==.Popcorners:BAAANQADCgcIBwABNQAECgkJIQAhAPMhAA==.Pordgio:BAAANQAECgcIDAAAAA==.Pozzi:BAAANQAECgcIBwAAAA==.',
Pr='Praypal:BAAANQADCgQIBAAAAA==.Primoss:BAAANQADCgYIBgABNQAECgcIGAACAO8RAA==.',
Ps='Psuedolus:BAAANQAECgUIDAAAAA==.Psålm:BAABNQAECoEfAAIXAAgKyRaDHgAlAgAXAAgKyRaDHgAlAgAAAA==.',
Pu='Pulshadow:BAACNQAFFIEJAAIXAAUKAxFmBwByAQAXAAUKAxFmBwByAQA1AAQKgSUAAhcACQpkJK0GAF0DABcACQpkJK0GAF0DAAAA.Pumah:BAAANQAECgEIAQAAAA==.',
Qt='Qtclaps:BAAANQADCggIHwAAAA==.',
Qu='Quartzecoatl:BAAANQADCgUICQAAAA==.',
Ra='Raamen:BAAANQAECgEIAQAAAA==.Raellia:BAABNQAECoEkAAQEAAgK6xE4PwC7AAADAAUKrxIPqwBMAQAEAAMKoxA4PwC7AAAaAAEKTgi8LAAyAAAAAA==.Raimmey:BAAANQAECgQIBAAAAA==.Rajia:BAAANQAECgIJAgABNQAECgcIGAAEAG8FAA==.Ralune:BAABNQAECoEYAAIBAAcKMAflWgA9AQABAAcKMAflWgA9AQAAAA==.Ranes:BAABNQAECoEnAAIPAAgKBh0FGQCMAgAPAAgKBh0FGQCMAgAAAA==.Razagual:BAAANQAECggIEgABNQAECggIBgAJAAAAAA==.',
Re='Redback:BAAANQABCgMIBgAAAA==.Redxelementz:BAABNQAECoEtAAIGAAkKdSaBAADgAwAGAAkKdSaBAADgAwAAAA==.Redxpastakan:BAAANQADCgUIBQABNQAECgkJLQAGAHUmAA==.Redxyara:BAAANQAECgYICwAAAA==.Renasen:BAABNQAECoEcAAIOAAgK5SBUKwD8AgAOAAgK5SBUKwD8AgAAAA==.Reno:BAABNQAECoEdAAMRAAgKWBqiUgACAgARAAcKvhiiUgACAgAFAAcKigyvtgB4AQAAAA==.Resiretha:BAAANQAECgcIDgAAAA==.Revelynn:BAABNQAECoElAAICAAgKXhtHFgCXAgACAAgKXhtHFgCXAgAAAA==.Rexkwondo:BAAANQAECgQJBAAAAA==.',
Rh='Rhyssyn:BAAANQADCgUIBQAAAA==.',
Ri='Rilerich:BAAANQAECgEIAQAAAA==.Rivliam:BAAANQAECgYIEQAAAA==.Rizzn:BAAANQADCggIGAABNQAECgcIGAAfAHIXAA==.',
Ro='Rook:BAAANQAECgIIAgAAAA==.Rooxxy:BAABNQAECoEZAAMZAAcKBhihpgAUAgAZAAcKBhihpgAUAgAbAAEK5QjORQArAAAAAA==.Rotawna:BAAANQADCgcIEgAAAA==.Roxxyyzz:BAAANQAECgQICAABNQAECgcIGQAZAAYYAA==.Roûge:BAAANQAECgIIAgABNQAECggIMwAOABghAA==.',
Ru='Rumikang:BAAANQADCgIIAgABNQAECggIJAAEAOsRAA==.',
Ry='Rybeorn:BAAANQAECgEIAgAAAA==.Rynoh:BAAANQAECgcIBwAAAA==.Rythrik:BAAANQAECggIEwAAAA==.',
Sa='Sainted:BAACNQAFFIEOAAIRAAYKQxZQBQD7AQARAAYKQxZQBQD7AQA1AAQKgScAAxEACQrjFJI5AGECABEACQrjFJI5AGECAAUABwrqFBKsAI8BAAAA.Sanoks:BAABNQAECoEkAAMMAAgKVB/+DACpAgAMAAgKVB/+DACpAgAFAAIKAQRRXgFHAAAAAA==.Sanokz:BAAANQADCgYIBgAAAA==.Santar:BAAANQADCgcIBwAAAA==.Sassafraz:BAAANQADCggICAABNQAECggIGwAMAD0eAA==.Savira:BAAANQAECgUIEQAAAA==.',
Sc='Scaleorva:BAAANQAECgYIEgAAAA==.',
Se='Sentharis:BAAANQADCgYIBgAAAA==.Seraphìm:BAABNQAECoEaAAIFAAcKWAvWuABzAQAFAAcKWAvWuABzAQAAAA==.Seïnaru:BAAANQAECgQIBwAAAA==.',
Sh='Shadenova:BAAANQADCgUJBgABNQAECgcIFwAjALYOAA==.Shadezilla:BAAANQADCgYIBgABNQAECgcIFwAjALYOAA==.Shadowpath:BAAANQABCgQIAgAAAA==.Shadowypete:BAAANQADCgUIBQAAAA==.Shadyballs:BAABNQAECoEXAAQjAAcKtg7UBgC1AAAZAAcKmQxV4AChAQAjAAMKJg/UBgC1AAAbAAIKXAxoLgBoAAAAAA==.Shakypete:BAAANQAECgQIBwABNQAECgUIIwABAIATAA==.Shamysosa:BAAANQAECgYIEgAAAA==.Shiionknow:BAAANQADCgQIBAAAAA==.Shinjí:BAABNQAECoEYAAIKAAgKHR9yHgC3AgAKAAgKHR9yHgC3AgABNQAFFAYIDwAKAA0dAA==.Shmob:BAAANQAECgEIAgAAAA==.Shnappz:BAABNQAECoEbAAMDAAcKDwgLqABTAQADAAcKDwgLqABTAQAEAAEKbQLyfwAhAAAAAA==.Shwillarou:BAABNQAECoEkAAIKAAgKfwtrVwCMAQAKAAgKfwtrVwCMAQAAAA==.Shádôws:BAAANQADCgYICwAAAA==.',
Si='Sinergee:BAAANQAECgYICAAAAA==.Sinnj:BAAANQADCgcIDQAAAA==.Sinona:BAAANQADCgQIBAAAAA==.',
Sk='Skinsey:BAAANQADCgYIDQAAAA==.Skinzey:BAAANQAECgQIBwAAAA==.Skinzy:BAAANQADCgUIBQAAAA==.Skycrush:BAAANQADCgUICQAAAA==.',
Sl='Slanie:BAABNQAECoEYAAIHAAcKzgVAlQAbAQAHAAcKzgVAlQAbAQAAAA==.Slingerz:BAABNQAECoEtAAMkAAkKuhUIDABKAgAkAAkKuhUIDABKAgAcAAEKqAMZMgAlAAAAAA==.Slingr:BAAANQADCgcIBwAAAA==.Slowmeaux:BAAANQADCgEIAQAAAA==.',
Sm='Smalldragon:BAAANQAECgMIAgAAAA==.Smoky:BAAANQAECgcIEwAAAA==.',
Sn='Sneakpastya:BAAANQADCgIIAgAAAA==.Sneakyg:BAAANQAECgYIEAABNQAECggIIgAFAHQgAA==.Snoochie:BAABNQAECoEbAAIWAAcK1A8WbwCjAQAWAAcK1A8WbwCjAQAAAA==.',
So='Sol:BAACNQAFFIENAAIdAAUK5BmvAADFAQAdAAUK5BmvAADFAQA1AAQKgTUAAh0ACQrII6YAAK0DAB0ACQrII6YAAK0DAAAA.Solkar:BAAANQADCgUIBQABNQAECggIIQANAHkaAA==.Sollis:BAAANQAECgQIDAAAAA==.Sonastii:BAAANQADCgYIBgABNQAECggIGQAXABYbAA==.Soulcoil:BAAANQAECgQICAABNQAECgUIBQAJAAAAAA==.Soulfury:BAAANQABCgUIBgABNQAECgUIBQAJAAAAAA==.Soulreaper:BAAANQAECgUIBQAAAA==.Soulshock:BAAANQAECgQIBQABNQAECgUIBQAJAAAAAA==.Soulstorm:BAAANQADCgYIBgABNQAECgUIBQAJAAAAAA==.',
Sp='Sparnak:BAABNQAECoEaAAIZAAcKuwF4UgHjAAAZAAcKuwF4UgHjAAAAAA==.Spawntier:BAAANQADCgUIBQABNQADCggICAAJAAAAAA==.Spazzchel:BAAANQADCggIIAAAAA==.Spiritbox:BAACNQAFFIEKAAIGAAYKdRpOBQD2AQAGAAYKdRpOBQD2AQA1AAQKgSEAAgYACQqxJMkJAF8DAAYACQqxJMkJAF8DAAE1AAQKCQkZAAcAlR0A.Spruce:BAAANQADCggIKAAAAA==.Sprucemoose:BAAANQADCgUICwABNQADCgcICwAJAAAAAA==.',
St='Stahlman:BAABNQAECoEeAAMGAAgKHRUTTQADAgAGAAgKHRUTTQADAgAWAAIK+AZf/ABaAAAAAA==.Stalpho:BAABNQAECoEjAAIcAAgK1Re7BwBNAgAcAAgK1Re7BwBNAgAAAA==.Starblessed:BAAANQADCgcIEgABNQAECgYIEAAJAAAAAA==.Starkind:BAAANQAECgYIEAAAAA==.Starliner:BAABNQAECoEhAAIhAAkK8yEDAgCRAwAhAAkK8yEDAgCRAwAAAA==.Stasis:BAAANQAECgUIBwABNQAECgkJGQAHAJUdAA==.Stormyknight:BAAANQADCgUICQAAAA==.Strahd:BAAANQADCgYIFAAAAA==.Styrke:BAAANQADCgYIBgAAAA==.Styrmir:BAAANQAECgQIBAAAAA==.',
Su='Subza:BAABNQAECoEtAAIZAAkKPxm9TgDUAgAZAAkKPxm9TgDUAgAAAA==.Suurik:BAAANQABCgIIAgAAAA==.',
Sw='Swagadin:BAAANQADCgcIBwABNQAECggICAAJAAAAAA==.Swagikal:BAAANQAECggICAAAAA==.Swagtistic:BAAANQADCggJFAAAAA==.',
Ta='Tahra:BAAANQADCgcICgAAAA==.Taliss:BAABNQAECoEjAAIHAAgKpxikOABjAgAHAAgKpxikOABjAgAAAA==.Tankmedaddy:BAABNQAECoEmAAMUAAkKdxIKHgAXAgAUAAkKdxIKHgAXAgAiAAQKSxdLKgDyAAAAAA==.Tappuccino:BAAANQAECgUICAAAAA==.Taras:BAABNQAECoEmAAMOAAkKgSRoNwDPAgAOAAgKsiNoNwDPAgAcAAYKnBoODgCrAQAAAA==.Taraxist:BAABNQAECoEaAAIEAAgKNBqBCABsAgAEAAgKNBqBCABsAgAAAA==.Tautology:BAABNQAECoEXAAIXAAgKyxTdHwAVAgAXAAgKyxTdHwAVAgAAAA==.Tazajin:BAAANQADCgYIBgAAAA==.',
Tc='Tchala:BAABNQAECoEiAAIFAAgKdCCJQACuAgAFAAgKdCCJQACuAgAAAA==.Tchallah:BAAANQAECgQIBAAAAA==.Tchaumb:BAAANQADCgEIAQAAAA==.',
Td='Tdog:BAAANQADCgcJBwAAAA==.',
Te='Teacup:BAAANQADCgYIBgABNQAECgcIEAAJAAAAAA==.Teks:BAABNQAECoEZAAMRAAgK0BZuSQAiAgARAAgK0BZuSQAiAgAMAAYKchY+KABvAQAAAA==.Teksara:BAAANQAECgQIAwABNQAECggIGQARANAWAA==.Teksynoth:BAAANQADCgQIBAABNQAECggIGQARANAWAA==.Telian:BAAANQADCgUIBQAAAA==.Terracustode:BAAANQABCgIJAgAAAA==.Teth:BAAANQAECgUICwAAAA==.Tevildo:BAAANQABCgIIAgAAAA==.',
Th='Thaine:BAABNQAECoEtAAIFAAkK5SM5CQCoAwAFAAkK5SM5CQCoAwAAAA==.Theundeadone:BAABNQAECoEpAAIXAAkKYB7ZCQAvAwAXAAkKYB7ZCQAvAwAAAA==.Thndrwzrd:BAAANQAECgMIBAAAAA==.Thorphan:BAABNQAECoEsAAQhAAkKhiHlAgBxAwAhAAkKhiHlAgBxAwAWAAUKBxZVoQAjAQAGAAUKcAsfuwDIAAAAAA==.',
Ti='Ticho:BAAANQAECgQIBgAAAA==.',
To='Torez:BAAANQAECgUICQABNQAECgkJLQASAKEcAA==.Torodisilis:BAAANQAECgUICwABNQAECggIIgAFAHQgAA==.Toxicavenger:BAAANQAECggICQAAAA==.',
Tr='Treygec:BAAANQAECgQIBgAAAA==.Tribolonotus:BAAANQADCggIIwAAAA==.Trickette:BAAANQADCgcICAABNQAECggICwAJAAAAAA==.Trilleong:BAAANQADCgIIAgAAAA==.Trina:BAAANQADCggICAAAAA==.Trisilla:BAAANQADCggIEAABNQAECgkJKQAlAHcNAA==.Troubleshot:BAAANQADCgYJBgAAAA==.Trujal:BAABNQAECoEkAAINAAgKbRrdJgBsAgANAAgKbRrdJgBsAgAAAA==.',
Tu='Turdmonk:BAABNQAECoE1AAIUAAkKUh6LCwAFAwAUAAkKUh6LCwAFAwAAAA==.',
Ty='Tylandon:BAAANQABCgQICgAAAA==.Tyndal:BAAANQADCgcIDwAAAA==.Typhon:BAABNQAECoEkAAMXAAgKKBsXIQAIAgAXAAcKSBoXIQAIAgAHAAUKHSFfYQDKAQAAAA==.',
Tz='Tzaim:BAAANQADCgcIBwAAAA==.',
Un='Unclebób:BAAANQADCgYIDAABNQAECgUICAAJAAAAAA==.Unshady:BAAANQADCgYIBgABNQAECgcIFwAjALYOAA==.',
Va='Vaeshta:BAABNQAECoEXAAIhAAcKcwIfHwAyAQAhAAcKcwIfHwAyAQAAAA==.Vaku:BAAANQADCgYIBgAAAA==.Valhallarama:BAABNQAECoEiAAIGAAkKQxlONQBkAgAGAAkKQxlONQBkAgAAAA==.Valika:BAAANQABCgYIBgAAAA==.Vampy:BAAANQAECgQIBAAAAA==.Vandragon:BAAANQADCggIGAAAAA==.Vannida:BAAANQADCgUICQAAAA==.Vardanis:BAAANQAECgQIBAABNQAECgcIIAATAEMaAA==.',
Ve='Vengencedawg:BAABNQAECoEbAAIFAAcKLQnhzgBDAQAFAAcKLQnhzgBDAQAAAA==.Vexxya:BAAANQADCgQIAwAAAA==.',
Vl='Vladus:BAABNQAECoEhAAINAAgKeRpBKwBRAgANAAgKeRpBKwBRAgAAAA==.',
Vo='Voltroñ:BAAANQADCgMIAwABNQAFFAMICgAZAOoRAA==.Voodoo:BAAANQAECgQIBAAAAA==.',
Vs='Vsegda:BAAANQAECgIIAgABNQAECgkJJQAGAKgXAA==.',
Vy='Vyllian:BAABNQAECoEdAAINAAgKkA9aSwCqAQANAAgKkA9aSwCqAQAAAA==.',
Wa='Wangwang:BAAANQADCggIJAAAAA==.Wardrag:BAAANQABCgQIBAAAAA==.Wareshesh:BAAANQADCgUIBQAAAA==.Warlakaflaka:BAAANQAECgQIDQABNQAECgcIFwAjALYOAA==.',
Wh='Whale:BAAANQAECgcIEQAAAA==.',
Wi='Wickðaddy:BAAANQABCgMIAwAAAA==.Windfury:BAABNQAECoEeAAIhAAgKhg+ZEgAcAgAhAAgKhg+ZEgAcAgAAAA==.Windfuryous:BAAANQADCgUICQAAAA==.Winston:BAAANQADCgcIGAAAAA==.',
Wo='Wolfsbane:BAAANQADCgYIBgAAAA==.Wonpiece:BAAANQAECgYIBgABNQAFFAMIBQABAGwDAA==.',
Wu='Wulfnir:BAAANQADCgcIBwAAAA==.',
Wy='Wylestrean:BAABNQAECoEgAAIIAAkKhh2lJADmAgAIAAkKhh2lJADmAgAAAA==.',
Xa='Xanokz:BAAANQADCgEIAQABNQAECggIJAAMAFQfAA==.Xarytha:BAAANQABCgMJAwABNQAECggIDAAJAAAAAA==.',
Xi='Xiaomao:BAEANQADCgcIBwABNQAECgEIAQAJAAAAAA==.',
Ye='Yeinn:BAABNQAECoEzAAMOAAgKGCHhPgC2AgAOAAgKBCDhPgC2AgAcAAQKfiKfDwCMAQAAAA==.',
Za='Zandalarthas:BAAANQAECgYIEgAAAA==.Zarbok:BAAANQADCgQIBAABNQAECgYIEgAJAAAAAA==.',
Zc='Zcredo:BAABNQAECoEqAAIOAAkKSx8cIwAdAwAOAAkKSx8cIwAdAwAAAA==.',
Ze='Zel:BAAANQAECgQIBgAAAA==.Zentradei:BAAANQADCgQIBAAAAA==.Zephariel:BAAANQADCgYIEQAAAA==.Zerus:BAAANQABCgMIBAAAAA==.',
Zi='Ziconik:BAAANQADCgYIBgAAAA==.Zieganfuss:BAAANQAECggIDAAAAA==.Zinrozlek:BAABNQAECoEWAAINAAcK8QSpcgAGAQANAAcK8QSpcgAGAQAAAA==.',
Zo='Zoho:BAABNQAECoEpAAIlAAkKdw2xEAC9AQAlAAkKdw2xEAC9AQAAAA==.Zorrander:BAAANQADCgQIBAABNQAECgQIBAAJAAAAAA==.',
Zy='Zynvar:BAAANQADCggICAAAAA==.',
['Ðj']='Ðjay:BAAANQABCgUIBQAAAA==.',
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
