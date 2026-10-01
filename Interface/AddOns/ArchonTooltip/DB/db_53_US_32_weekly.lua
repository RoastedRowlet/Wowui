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

local lookup = {'Druid-Balance','DemonHunter-Devourer','Paladin-Retribution','Shaman-Restoration','Priest-Holy','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Unholy','Druid-Restoration','Paladin-Protection','DeathKnight-Blood','Warrior-Arms','Hunter-Marksmanship','Druid-Guardian','Paladin-Holy','DemonHunter-Havoc','Priest-Discipline','DemonHunter-Vengeance','Shaman-Elemental','Warlock-Destruction','Priest-Shadow','Hunter-Survival','Mage-Arcane','Warlock-Affliction','Warlock-Demonology','Mage-Frost','Rogue-Assassination','Monk-Windwalker','Shaman-Enhancement','Druid-Feral','Rogue-Subtlety','Monk-Mistweaver','Warrior-Protection','Warrior-Fury','Rogue-Outlaw','Monk-Brewmaster',}
local provider = {region='US',realm='Blackhand',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Absorbency:BAAANQAECgYIBgABNQAECgkJIQABAIoUAA==.',
Ae='Aeris:BAAANQAECgUIDQAAAA==.Aethwyn:BAAANQAECgUJBQAAAA==.',
Ag='Agandaur:BAAANQAECgQIBAAAAA==.',
Ah='Ahnkala:BAAANQADCgcIHAAAAA==.',
Ai='Aigirlfriend:BAABNQAECoEfAAICAAgKgA6UIwDvAQACAAgKgA6UIwDvAQAAAA==.',
Al='Allupcreepy:BAAANQAECgUIDAAAAA==.',
Am='Amalyndi:BAAANQAECgYIBgAAAA==.Ambewlance:BAAANQAECgYIDQAAAA==.Amethystra:BAAANQAECgYIBgAAAA==.Amlu:BAAANQAECgQIBQABNQAECggIGwADABsdAA==.',
An='Andaconda:BAAANQAECgQIBQAAAA==.Annimosity:BAAANQADCgcIDgAAAA==.Ansem:BAAANQAECgEJAQAAAA==.Anthesis:BAAANQAECgUIBQABNQAECgkJIgAEAIMWAA==.Anúbis:BAAANQADCgUIDQAAAA==.',
Ap='Apawllo:BAAANQAECgEJAQAAAA==.Apep:BAAANQAECgIIAgAAAA==.Apostle:BAABNQAECoEXAAIFAAkKeB2JGgDZAgAFAAkKeB2JGgDZAgAAAA==.',
Ar='Aramìs:BAAANQADCgcIDwAAAA==.Arcaya:BAAANQADCgcIGAAAAA==.Ariaka:BAAANQADCgEIAQAAAA==.Arleen:BAAANQAECgQIBwAAAA==.Arlida:BAABNQAECoEYAAIEAAcKdxm8TQDcAQAEAAcKdxm8TQDcAQAAAA==.Artemys:BAABNQAECoEXAAIGAAcKNRgZWQAWAgAGAAcKNRgZWQAWAgAAAA==.Aryto:BAAANQADCgUIBQAAAA==.',
As='Asketill:BAAANQADCgYIDwAAAA==.Asmodee:BAAANQAECgUICwAAAA==.',
Au='Aure:BAAANQADCgYIDAAAAA==.Auren:BAAANQADCgIIAgAAAA==.',
Az='Azkadellia:BAAANQABCgQJCAAAAA==.Azonya:BAAANQABCgQIBAAAAA==.',
Ba='Baaloo:BAAANQABCgQIBAABNQADCggIGgAHAAAAAA==.Bainne:BAAANQADCgUJCAAAAA==.Baitken:BAAANQAECgQIBwABNQAECgUIDAAHAAAAAA==.Barktea:BAAANQAECgUICQAAAA==.Batharel:BAAANQAECgQIBwAAAA==.Battleground:BAAANQADCgMIAwAAAA==.',
Be='Bearen:BAAANQAECgYJDgAAAA==.Beertrain:BAABNQAECoEYAAIIAAgKTBZEMgAGAgAIAAgKTBZEMgAGAgAAAA==.Beesechurger:BAAANQAECgYICQAAAA==.Belladue:BAAANQADCgYIGwAAAA==.Bellezza:BAABNQAECoEkAAIJAAkKnRFlFwA4AgAJAAkKnRFlFwA4AgAAAA==.',
Bh='Bhikku:BAAANQAECgQICAABNQAECggIGwADABsdAA==.Bhilly:BAAANQADCggIGwAAAA==.',
Bi='Bigdumbcatqt:BAABNQAECoEZAAIKAAcKGiZ1BgASAwAKAAcKGiZ1BgASAwAAAA==.Bigdumbkatqt:BAABNQAFFIEOAAILAAUKbBuJBwCWAQALAAUKbBuJBwCWAQAAAA==.Bignjuicy:BAAANQAECggIEwAAAA==.Bimisi:BAAANQAECgcIEwAAAA==.',
Bl='Blades:BAAANQADCgMIBgAAAA==.Bloodshhot:BAABNQAECoEjAAIGAAgKgxM3TAA8AgAGAAgKgxM3TAA8AgAAAA==.Blueragebar:BAAANQAECgUJCwAAAA==.',
Bo='Bobadasmash:BAABNQAECoEZAAIMAAgKGRNYagAGAgAMAAgKGRNYagAGAgAAAA==.Bobitt:BAAANQAECgEJAQAAAA==.Boddyknocker:BAAANQAECgYIBwAAAA==.Boombox:BAAANQADCgYIBgAAAA==.Boonerichard:BAAANQAECgEIAQAAAA==.Bouchewager:BAAANQADCgYIBgAAAA==.',
Br='Braina:BAAANQAECgYIDAAAAA==.Branwin:BAAANQADCgYIDgAAAA==.Braver:BAACNQAFFIEMAAINAAUKChF+CABzAQANAAUKChF+CABzAQA1AAQKgScAAw0ACQovHqkQALwCAA0ACQovHqkQALwCAAYAAQq4C5QZATkAAAAA.Braverwar:BAAANQAECgIIAwABNQAFFAUIDAANAAoRAA==.Brayedine:BAAANQADCgcIFwAAAA==.Break:BAACNQAFFIETAAIDAAcKxh9HAADSAgADAAcKxh9HAADSAgA1AAQKgSIAAgMACQqFJogHAKsDAAMACQqFJogHAKsDAAE1AAUUBwoTAAMAxh8A.Bromungandr:BAAANQADCgYIDgAAAA==.',
Bu='Buligerent:BAAANQADCggIGAABNQAECggIHwAOAAkVAA==.',
By='Bynnyy:BAAANQAECgIIAgAAAA==.',
['Bù']='Bùbbles:BAAANQAECgIIAwAAAA==.',
Ca='Cadelsaya:BAABNQAECoEjAAIPAAkKGQ7mQAAgAgAPAAkKGQ7mQAAgAgAAAA==.Camandah:BAAANQAECgYIEAABNQADCgUICQAHAAAAAA==.Cammandzar:BAAANQAECgIIAgABNQADCgUICQAHAAAAAA==.Candy:BAAANQABCgQIAgAAAA==.Canman:BAAANQADCggIGgAAAA==.Carlo:BAAANQAECgEIAwAAAA==.Carryout:BAAANQAECggICwAAAA==.Cassei:BAAANQAECgQIBgAAAA==.Castertroy:BAAANQAECgYICQAAAA==.',
Ce='Celenia:BAAANQAECgIIAgAAAA==.',
Ch='Chainari:BAAANQAECgIIAgAAAA==.Charmless:BAAANQADCgUIBQABNQAECgkJJAAQAG0YAA==.Chee:BAAANQADCggJFgAAAA==.Cheetopaly:BAAANQAECgYIDwAAAA==.Chuga:BAAANQAECgIIAgABNQAECgcIEgAHAAAAAA==.Chìgusa:BAABNQAECoEcAAMFAAgK+x4GHwC+AgAFAAgK+x4GHwC+AgARAAUKcxU1DABDAQAAAA==.',
Ci='Circa:BAAANQADCgEIAQAAAA==.',
Cl='Clarimonde:BAAANQADCgEIAQAAAA==.Cleaveradius:BAAANQADCggJCAABNQAECggIHgAEAGwfAA==.Clumonk:BAAANQAECggIEAAAAA==.',
Co='Convoke:BAAANQADCggIEAABNQAECgkJFwAFAHgdAA==.Coosar:BAAANQAECgMIBAAAAA==.Coosedaplug:BAAANQADCgQIBAABNQAECgcIEgAHAAAAAA==.Cooseyloosey:BAAANQAECgcIEgAAAA==.Coosinator:BAAANQAECgYJCwABNQAECgcIEgAHAAAAAA==.Cooterray:BAAANQAECgUICAAAAA==.Corellon:BAAANQAECgYICwAAAA==.Corinth:BAAANQAECgYJEAAAAA==.',
Cr='Cratoz:BAABNQAECoEaAAIDAAgKLR/7LgDPAgADAAgKLR/7LgDPAgAAAA==.Croswind:BAABNQAECoEhAAIGAAgKpRVYPgBoAgAGAAgKpRVYPgBoAgAAAA==.',
Cy='Cyndrine:BAABNQAECoEpAAISAAkKtCVWAADiAwASAAkKtCVWAADiAwAAAA==.Cyrani:BAABNQAECoEkAAMTAAkKBCQvBgCoAwATAAkKBCQvBgCoAwAEAAYKrCQSKwB4AgAAAA==.',
Da='Dadipps:BAABNQAECoEbAAIEAAgKXB9ZJACbAgAEAAgKXB9ZJACbAgAAAA==.Daggumit:BAAANQADCgYIEQAAAA==.Dagnei:BAAANQADCgcIEwAAAA==.Daltina:BAAANQAECgUIDQAAAA==.Damage:BAAANQAECggIAgAAAA==.Dannyboone:BAAANQADCggICAABNQAECggIGgALADcZAA==.Dareael:BAAANQAECgYIEQAAAA==.Daurgoth:BAAANQAECgYJDgAAAA==.Dazoner:BAAANQADCggIDgAAAA==.',
De='Deadbydrand:BAAANQAECgcICgAAAA==.Deathndspark:BAABNQAECoEZAAILAAcKkArPWgBAAQALAAcKkArPWgBAAQAAAA==.Deathpuma:BAABNQAECoEeAAILAAkKwxwEFADgAgALAAkKwxwEFADgAgAAAA==.Deathrowe:BAAANQAECgYIEgAAAA==.Dednevoker:BAAANQAECgEIAQABNQAECgcIDQAHAAAAAA==.Deelyte:BAAANQAECgIIAgAAAA==.Demonvann:BAAANQADCggICAAAAA==.Demítrá:BAAANQADCgIIAgABNQAECggIIwAEAKYYAA==.Denouncer:BAAANQAECgQIBAABNQAECggIHgAEAGwfAA==.Derca:BAAANQAECgQICQAAAA==.Dethork:BAAANQADCgcIDAAAAA==.',
Di='Dieds:BAAANQADCgYIBgABNQAECgcIDQAHAAAAAA==.Dienne:BAEANQAECgEIAQAAAA==.Dietunicorn:BAAANQADCggIJQAAAA==.Dinarra:BAAANQADCgUIBgAAAA==.Diosdelaluna:BAAANQABCggIFwAAAA==.Dirtybyrd:BAAANQADCgMIAwAAAA==.Disahzter:BAAANQAECgYIEgAAAA==.',
Do='Docbledore:BAAANQADCgIIAgABNQAECgYIDwAHAAAAAA==.Docdrood:BAAANQADCgcIBwABNQAECgYIDwAHAAAAAA==.Docmonk:BAAANQAECgEIAQABNQAECgYIDwAHAAAAAA==.Docpriest:BAAANQAECgYIDwAAAA==.Donlazul:BAAANQADCgQJBAAAAA==.Dotlotto:BAAANQAECgEJAgAAAA==.',
Dr='Draconoth:BAAANQAECgUICgAAAA==.Dragfin:BAAANQAECgEIAQAAAA==.Dragonir:BAAANQAECgYIDQABNQAECggIGwADABsdAA==.',
Du='Dungard:BAAANQAECgEIAQABNQAECgkJIwAPABkOAA==.Dunstird:BAAANQADCgQIBgABNQAFFAIIAgAHAAAAAA==.',
Dy='Dyami:BAAANQAECgUJBwAAAA==.',
['Dè']='Dèadèyè:BAAANQADCggJDgAAAA==.',
Ea='Eatmorechkn:BAABNQAECoEcAAIDAAgKmg7HegDUAQADAAgKmg7HegDUAQAAAA==.',
Ee='Eellonwy:BAAANQADCgcIEgAAAA==.Eemerald:BAAANQAECgIIAgAAAA==.',
Eg='Egna:BAAANQAECgYIDAAAAA==.',
El='Electricblu:BAAANQAECgMJBAAAAA==.Elizaa:BAABNQAECoEYAAMEAAcKPA69bgBoAQAEAAcKPA69bgBoAQATAAIKpQGm6gBKAAAAAA==.',
Em='Emmadar:BAAANQADCggIFgABNQAECggIHwAUAAcPAA==.',
Eu='Euripidus:BAAANQADCgEIAQAAAA==.',
Ev='Evilclared:BAAANQADCgUICgABNQAFFAMIBwAMAOEUAA==.Evildean:BAAANQADCgYICgAAAA==.',
Ex='Execute:BAAANQADCgUICQAAAA==.',
Fa='Fanya:BAAANQADCgYIBgABNQAECgkJIwAVAMocAA==.Fathernatur:BAAANQADCgYICQAAAA==.Fatherpain:BAAANQABCgYIEQAAAA==.',
Fe='Fenrigaar:BAABNQAECoEiAAIBAAkKHRxwFgDpAgABAAkKHRxwFgDpAgAAAA==.',
Ff='Ffsa:BAABNQAECoEgAAQGAAkKOxvSIQDYAgAGAAkKOxvSIQDYAgANAAUKWQ+wOAAmAQAWAAEKahWxDgBDAAAAAA==.',
Fi='Fillin:BAAANQADCggIFwAAAA==.Filô:BAABNQAECoEYAAIVAAkK0BpAEQCsAgAVAAkK0BpAEQCsAgAAAA==.',
Fl='Flame:BAAANQADCgQIBAAAAA==.Flintmini:BAAANQADCgQJBAAAAA==.Flossylock:BAAANQAECgEJAQAAAA==.',
Fo='Forsakenly:BAAANQADCggICAAAAA==.',
Fr='Frasti:BAAANQADCggIGAAAAA==.Frodes:BAAANQABCgYJBwAAAA==.Frostmage:BAABNQAECoEfAAIXAAgKGhVQiwApAgAXAAgKGhVQiwApAgAAAA==.',
Fu='Fuegoblazeit:BAAANQABCgIIAgAAAA==.Furbucket:BAAANQAECgQICwAAAA==.Futonhunts:BAABNQAECoEkAAIGAAkKCCHZCwBdAwAGAAkKCCHZCwBdAwAAAA==.',
Fy='Fylerw:BAAANQAECgUIDgAAAA==.',
Ga='Gailyn:BAAANQADCgYICgAAAA==.Galebb:BAAANQADCgUIBQABNQAECgMIBgAHAAAAAA==.Gardros:BAAANQABCgQIBAAAAA==.',
Gh='Ghostrideher:BAAANQAECgcIDQAAAA==.',
Gi='Gigadad:BAABNQAECoEiAAIGAAkKXiWtBACnAwAGAAkKXiWtBACnAwAAAA==.Gigafather:BAAANQADCgQIBAAAAA==.',
Gl='Gladiuz:BAAANQADCgcIBwABNQAECggIGwADABsdAA==.',
Go='Gornthemonki:BAAANQADCgcICgAAAA==.Goyahokasinj:BAAANQADCgQJCwAAAA==.',
Gr='Griannee:BAABNQAECoEcAAIQAAgKVhZgJQAiAgAQAAgKVhZgJQAiAgAAAA==.Grimtoetem:BAAANQABCgYJCQAAAA==.Grislix:BAABNQAECoEaAAQYAAgKxBKYCACyAQAYAAcKaw6YCACyAQAZAAYKVA+jjgBdAQAUAAEKLxneXwBNAAAAAA==.Grismistea:BAAANQAECgEIAQABNQAECggIGgAYAMQSAA==.Grismunch:BAAANQABCggICAAAAA==.Gryffin:BAABNQAECoEYAAMaAAcKyhJgDACjAQAaAAcKyhJgDACjAQAXAAEKPwVeiAE2AAAAAA==.',
Gu='Guidance:BAAANQADCgcIBwAAAA==.Gummies:BAAANQABCgYIDgAAAA==.',
['Gâ']='Gânk:BAABNQAECoEbAAIMAAgKvgpziACtAQAMAAgKvgpziACtAQAAAA==.',
Ha='Hanrekt:BAAANQAECgUIBwAAAA==.Happiness:BAAANQAECgQICQABNQAECgkJHQAGAM0dAA==.',
He='Heavensbliss:BAAANQAECgQIBAABNQAECggIHwAXABoVAA==.Heavychevy:BAAANQAECggIDgAAAA==.Hellvenger:BAAANQADCgMIAwAAAA==.Heriel:BAAANQAECgUIDAABNQAECggIGwADABsdAA==.Hexquisite:BAAANQADCgYJBQABNQAECgkJFwAFAHgdAA==.',
Hi='Hildoehealz:BAAANQAECgIIBAAAAA==.',
Ho='Holybit:BAAANQADCggIDwAAAA==.Hotsjkpurge:BAAANQADCgQIBAAAAA==.',
Hu='Humphrees:BAABNQAECoEfAAIbAAgKiQ8pJQD8AQAbAAgKiQ8pJQD8AQAAAA==.',
Hy='Hydrospin:BAAANQADCgQIBAAAAA==.Hypocrisy:BAAANQADCgYIDwAAAA==.',
['Hà']='Hàtos:BAABNQAECoEZAAIXAAcKXRAfvwC2AQAXAAcKXRAfvwC2AQAAAA==.',
Id='Idot:BAAANQADCgUJDgABNQAECgUIDwAHAAAAAA==.',
Il='Illidave:BAAANQADCgYIBwABNQAECgUICwAHAAAAAA==.',
In='Incubus:BAAANQAECgUIBQABNQAECggIGwADABsdAA==.Inebriatas:BAAANQAECgEIAQABNQAECgQIDQAHAAAAAA==.Inu:BAAANQABCgIJAgAAAA==.Invissibill:BAAANQAECgYIEAAAAA==.',
Is='Ishaa:BAAANQAECgcICgAAAA==.',
Iv='Ivanä:BAAANQAECgYICwAAAA==.',
Iz='Izax:BAABNQAECoEhAAQZAAcKvAzbkABXAQAZAAYKQwzbkABXAQAUAAEKjw+PaQA7AAAYAAEKYwb4KAAxAAAAAA==.',
Ja='Jaddzia:BAAANQABCgQIBAAAAA==.Jadestone:BAAANQADCgYIDAAAAA==.Jaguarkick:BAAANQADCggICAAAAA==.Jarcor:BAAANQABCgQIBAAAAA==.',
Je='Jeffray:BAAANQABCgQIBAAAAA==.Jessi:BAAANQAECgUICQAAAA==.',
Jo='Jonsneew:BAAANQADCgYICgAAAA==.',
Ju='Judgment:BAAANQADCgMIBQAAAA==.Junglefu:BAAANQADCgIIAgAAAA==.Jupitus:BAAANQAECgUIBQAAAA==.Justin:BAAANQAECgUIBwABNQAECgYIBgAHAAAAAA==.',
['Jû']='Jûstin:BAAANQAECgYICAABNQAFFAMIBgABAJoTAA==.',
Ka='Kabroz:BAAANQADCgcIBwAAAA==.Kale:BAAANQABCgIIBQAAAA==.Karma:BAAANQAECgUIDQAAAA==.Katalania:BAAANQAECgUIDQAAAA==.',
Ke='Keeshama:BAAANQADCgIIAgAAAA==.Kegna:BAAANQADCggICAAAAA==.Keiwhenua:BAAANQAECgYIEQAAAA==.Kelinn:BAAANQADCggIFAAAAA==.Kelzier:BAAANQAECgQICAABNQAECggIGwADABsdAA==.Kenthel:BAAANQAECgcIEwAAAA==.Kenthels:BAAANQADCgUIBQABNQAECgcIEwAHAAAAAA==.Kezt:BAAANQADCgUIBQABNQADCggIDwAHAAAAAA==.',
Ki='Kiplander:BAABNQAECoEbAAIBAAUKNBJmVwAmAQABAAUKNBJmVwAmAQAAAA==.Kiplandr:BAAANQADCgEIAQAAAA==.Kitheryn:BAAANQAECgEIAQAAAA==.',
Kl='Klitt:BAAANQAECgMIBAAAAA==.',
Ko='Komosky:BAACNQAFFIERAAIcAAUKIgbsBQBHAQAcAAUKIgbsBQBHAQA1AAQKgSYAAhwACQrmFrMVAFUCABwACQrmFrMVAFUCAAAA.Korry:BAAANQAECgIIAgAAAA==.Kortanis:BAAANQAECgUICwAAAA==.',
Kr='Krakìn:BAAANQAECgIIAgAAAA==.',
Ku='Kush:BAABNQAECoEYAAQUAAcK8A1VHAB8AQAUAAcKLwpVHAB8AQAZAAUKvwpPpwAgAQAYAAEKcBCkJQA6AAAAAA==.',
Ky='Kyana:BAAANQADCgYICgAAAA==.',
['Kü']='Küngfury:BAAANQADCgUIBQAAAA==.',
La='Laerik:BAAANQABCgEIAQAAAA==.Landissa:BAAANQAECgYIEwAAAA==.Larcenciel:BAAANQAECgQJCQAAAA==.Larryholmes:BAAANQABCgQIBAABNQADCggICAAHAAAAAA==.',
Le='Leen:BAAANQABCgYICQAAAA==.Letmehelpyou:BAABNQAECoEeAAIEAAgKbB8ZJACdAgAEAAgKbB8ZJACdAgAAAA==.',
Li='Licky:BAAANQAECgcIEQAAAA==.Lihan:BAAANQAECgUICwAAAA==.Lilieth:BAAANQADCggICgAAAA==.Lily:BAABNQAECoEcAAIIAAgK1B+6GAC7AgAIAAgK1B+6GAC7AgAAAA==.Lively:BAAANQAECgUIDAAAAA==.',
Lo='Lockedtoit:BAAANQAECgIIAgAAAA==.Loverocket:BAABNQAECoEaAAIKAAgKPR5HCwClAgAKAAgKPR5HCwClAgAAAA==.',
Lu='Luna:BAAANQAECgUIBQAAAA==.Lunastorm:BAAANQADCgQJBAAAAA==.',
Ly='Lyshia:BAABNQAECoEkAAIXAAkKbhvsSgDHAgAXAAkKbhvsSgDHAgAAAA==.',
['Lí']='Líghthand:BAAANQAECggIEgAAAA==.',
['Lý']='Lýght:BAAANQADCgcIDQAAAA==.',
Ma='Magedown:BAABNQAECoEaAAMXAAgKEhIfjwAgAgAXAAgKEhIfjwAgAgAaAAEKkAVVQQAjAAAAAA==.Magician:BAAANQADCggICAAAAA==.Mamachula:BAAANQADCgQJBAAAAA==.Manapali:BAAANQADCgYIBgABNQAECgkJIAAdAMceAA==.Manpumper:BAAANQAECgMIAwAAAA==.Margor:BAAANQAECgQIBwABNQAECgUICwAHAAAAAA==.Mattdemon:BAABNQAECoEkAAMQAAkKbRjJFgCjAgAQAAkK4xfJFgCjAgACAAcKyBKDKQC4AQAAAA==.',
Me='Meanzy:BAAANQADCgQIBAAAAA==.Meliany:BAAANQAECgMIBAAAAA==.Meliorate:BAABNQAECoEhAAMBAAkKihRGLAA2AgABAAkKihRGLAA2AgAJAAYKnQlJMAAwAQAAAA==.Meowch:BAABNQAECoEaAAIeAAgKux6dBQDNAgAeAAgKux6dBQDNAgAAAA==.',
Mi='Mikachu:BAABNQAECoEpAAIdAAkKhCZ7AADeAwAdAAkKhCZ7AADeAwABNQAFFAUICgADAJMOAA==.Miksi:BAAANQADCgYICQABNQADCggIGgAHAAAAAA==.Miradele:BAAANQAECgUIDAAAAA==.Miraxx:BAAANQADCggIGgAAAA==.Misscleö:BAAANQAECgYIEgAAAA==.Miyoshi:BAABNQAECoEbAAIfAAcKsghgIgCPAQAfAAcKsghgIgCPAQAAAA==.',
Mo='Mobius:BAAANQABCgIIBQAAAA==.Moonshíne:BAAANQADCgIIAgAAAA==.Moosakka:BAABNQAECoEZAAIgAAcKExJrGQCRAQAgAAcKExJrGQCRAQAAAA==.Moosesiah:BAAANQABCgYICgABNQAECggIGwAgAO8UAA==.Moovinthru:BAAANQADCgcIGgAAAA==.Moraxes:BAAANQAECgUIBgAAAA==.Mordenkainen:BAAANQAECgUIDAAAAA==.Morgax:BAAANQAECgcIDQAAAA==.Morgona:BAAANQADCgUICQAAAA==.Morphidmage:BAAANQADCgUIBQAAAA==.Motoko:BAAANQADCgYIEgAAAA==.',
Mu='Muaadib:BAAANQAECgYICwABNQAECggIIQAGAKUVAA==.',
My='Mydin:BAABNQAECoEaAAIDAAgKLxPTawD+AQADAAgKLxPTawD+AQAAAA==.Myssaphra:BAABNQAECoEiAAMEAAkKgxYEMABfAgAEAAkKgxYEMABfAgATAAEKRAceDAEqAAAAAA==.',
['Mì']='Mìsawa:BAAANQAECgUICAAAAA==.',
Na='Nakai:BAABNQAECoEXAAIGAAgKnBVRQgBaAgAGAAgKnBVRQgBaAgAAAA==.Nasatra:BAAANQADCgQICAABNQADCgUICgAHAAAAAA==.Nastijiggle:BAABNQAECoEYAAIVAAcKnBtMHQAMAgAVAAcKnBtMHQAMAgAAAA==.Nazrien:BAAANQABCgUJBQAAAA==.Nazrion:BAAANQABCgEIAQAAAA==.',
Nc='Nc:BAAANQAECgYJDwAAAA==.',
Ne='Nexxa:BAAANQAECgYIEQAAAA==.',
Ni='Nightshadow:BAAANQADCgQIBAAAAA==.Niqkle:BAABNQAECoEdAAMEAAkKRxK8YACVAQAEAAcKRhC8YACVAQATAAgKDwjraACRAQAAAA==.Nitebane:BAAANQAECgcIEgAAAA==.',
No='Nohurtscooby:BAAANQADCgcIGAAAAA==.Notadh:BAAANQADCggIEAAAAA==.Notadruid:BAAANQADCgQIBAAAAA==.Notawrlock:BAAANQAECgEIAQABNQAFFAIIAgAHAAAAAA==.',
Ns='Nstagatr:BAAANQAECgUICwAAAA==.',
Ny='Nyxandria:BAAANQABCgQIBAAAAA==.Nyxi:BAAANQABCgQIBAAAAA==.',
Oa='Oak:BAAANQAECgIIAgAAAA==.',
Oc='Occidius:BAAANQAECgMIAwAAAA==.',
Ol='Olari:BAAANQAECgEIAQAAAA==.Oldfox:BAAANQAECgEIAgAAAA==.Oldoriel:BAAANQADCgYIBgAAAA==.Olehanna:BAABNQAECoEcAAIDAAgKwg3iewDRAQADAAgKwg3iewDRAQAAAA==.Olestrid:BAAANQADCggIFgABNQAECggIHAADAMINAA==.',
On='Oni:BAAANQADCgYICAAAAA==.',
Op='Opioid:BAAANQAECgMIAwAAAA==.Opsec:BAAANQAECgIJAgABNQAECgcIGAACAO8RAA==.Opsèc:BAABNQAECoEYAAICAAcK7xGEKADBAQACAAcK7xGEKADBAQAAAA==.',
Or='Orsa:BAAANQADCggICAAAAA==.',
Pe='Peachshock:BAECNQAFFIEUAAMEAAYKoRq2AgApAgAEAAYKoRq2AgApAgATAAEKzQxPIQBLAAA1AAQKgR4AAwQACQrQJc4EAIsDAAQACQrQJc4EAIsDABMABAroH9F8AFYBAAAA.Peachyknight:BAAANQAECgQIBAAAAA==.Peebee:BAAANQAECgMIAwAAAA==.Perfectlock:BAAANQAECgcIEgAAAA==.',
Pi='Pigog:BAAANQAECgUIBwAAAA==.',
Po='Pordgio:BAAANQAECgYIBgAAAA==.Pozzi:BAAANQAECgcIBwAAAA==.',
Pr='Praypal:BAAANQADCgQIBAAAAA==.Primoss:BAAANQADCgYIBgABNQAECgcIGAACAO8RAA==.',
Ps='Psuedolus:BAAANQAECgUIDAAAAA==.Psålm:BAABNQAECoEXAAIVAAcK/BXVIADkAQAVAAcK/BXVIADkAQAAAA==.',
Pu='Pulshadow:BAACNQAFFIEGAAIVAAMKoRFzCQD4AAAVAAMKoRFzCQD4AAA1AAQKgSMAAhUACQpUJHYFAGgDABUACQpUJHYFAGgDAAAA.Pumah:BAAANQADCggIGgAAAA==.',
Qt='Qtclaps:BAAANQADCggIDwAAAA==.',
Qu='Quartzecoatl:BAAANQADCgUICQAAAA==.',
Ra='Raamen:BAAANQADCggIGgAAAA==.Raellia:BAABNQAECoEfAAQUAAgKBw9tPwCwAAAZAAUKjBDkmgA+AQAUAAMKfgxtPwCwAAAYAAEKTgjeJgA3AAAAAA==.Raimmey:BAAANQADCgYICgAAAA==.Rajia:BAAANQAECgIJAgABNQAECgYIEAAHAAAAAA==.Ralune:BAAANQAECgYIEAAAAA==.Ranes:BAABNQAECoEfAAIbAAgKOhwiFQCIAgAbAAgKOhwiFQCIAgAAAA==.Razagual:BAAANQAECggIEgABNQAECggIBgAHAAAAAA==.',
Re='Redback:BAAANQABCgMIBgAAAA==.Redxelementz:BAABNQAECoEnAAIEAAkK5iWsAADaAwAEAAkK5iWsAADaAwAAAA==.Redxpastakan:BAAANQADCgUIBQABNQAECgkJJwAEAOYlAA==.Redxyara:BAAANQAECgYIBgAAAA==.Renasen:BAAANQAECgYIEQAAAA==.Reno:BAAANQAECgYIEgAAAA==.Resiretha:BAAANQAECgUIBwAAAA==.Revelynn:BAABNQAECoEdAAICAAgKORq9FQCGAgACAAgKORq9FQCGAgAAAA==.Rexkwondo:BAAANQAECgQJBAAAAA==.',
Ri='Rivliam:BAAANQAECgYICwAAAA==.Rizzn:BAAANQADCgcIEAABNQAECgcIEwAHAAAAAA==.',
Ro='Rook:BAAANQAECgIIAgAAAA==.Rooxxy:BAABNQAECoEVAAMXAAYKuBdRsgDSAQAXAAYKuBdRsgDSAQAaAAEK5QjWPQAtAAAAAA==.Rotawna:BAAANQADCgYICwAAAA==.Roxxyyzz:BAAANQAECgQIBwABNQAECgYIFQAXALgXAA==.Roûge:BAAANQAECgIIAgAAAA==.',
Ru='Rumikang:BAAANQADCgIJAgABNQAECggIHwAUAAcPAA==.',
Ry='Rybeorn:BAAANQAECgEIAQAAAA==.Rynoh:BAAANQAECgEJAQAAAA==.Rythrik:BAAANQAECggIEQAAAA==.',
Sa='Sainted:BAACNQAFFIEIAAIPAAUKJRPJBwCVAQAPAAUKJRPJBwCVAQA1AAQKgSMAAw8ACQrjFJEvAG0CAA8ACQrjFJEvAG0CAAMABwrqFGSPAJwBAAAA.Sanoks:BAABNQAECoEcAAMKAAgKHB+WCgCyAgAKAAgKHB+WCgCyAgADAAIKAQRbNQFJAAAAAA==.Sanokz:BAAANQADCgYIBgAAAA==.Sassafraz:BAAANQADCggJCAABNQAECggIGgAKAD0eAA==.Savira:BAAANQAECgUIDAAAAA==.',
Sc='Scaleorva:BAAANQAECgUIDAAAAA==.',
Se='Seraphìm:BAAANQAECgYIDwAAAA==.Seïnaru:BAAANQAECgQIBwAAAA==.',
Sh='Shadenova:BAAANQADCgUJBgABNQAECgUIDwAHAAAAAA==.Shadowpath:BAAANQABCgQIAgAAAA==.Shadyballs:BAAANQAECgUIDwAAAA==.Shakypete:BAAANQAECgQIBwABNQAECgUIGwABADQSAA==.Shamysosa:BAAANQAECgUICwAAAA==.Shiionknow:BAAANQADCgQIBAAAAA==.Shinjí:BAAANQAECgUIDQABNQAFFAUICgAIAI0eAA==.Shmob:BAAANQAECgEIAgAAAA==.Shnappz:BAAANQAECgUIEAAAAA==.Shwillarou:BAABNQAECoEcAAIIAAgK2QiwTQB2AQAIAAgK2QiwTQB2AQAAAA==.Shádôws:BAAANQADCgYICwAAAA==.',
Si='Sinergee:BAAANQAECgMIAwAAAA==.Sinnj:BAAANQADCgcIDQAAAA==.Sinona:BAAANQADCgQIBAAAAA==.',
Sk='Skinsey:BAAANQADCgYIDQAAAA==.Skinzey:BAAANQADCgcIDAAAAA==.Skinzy:BAAANQABCgYIBwAAAA==.Skycrush:BAAANQADCgUICQAAAA==.',
Sl='Slanie:BAAANQAECgUIDwAAAA==.Slingerz:BAABNQAECoEkAAMhAAkK6BK4DAAUAgAhAAkK6BK4DAAUAgAiAAEKqAMfLAAlAAAAAA==.Slowmeaux:BAAANQADCgEIAQAAAA==.',
Sm='Smoky:BAAANQAECgcIEAAAAA==.',
Sn='Sneakpastya:BAAANQADCgIIAgAAAA==.Sneakyg:BAAANQAECgUICgABNQAECggIGwADABsdAA==.Snoochie:BAAANQAECgYIEQAAAA==.',
So='Sol:BAACNQAFFIEJAAIjAAQK2x2/AAB+AQAjAAQK2x2/AAB+AQA1AAQKgSwAAiMACQoxI+0AAI4DACMACQoxI+0AAI4DAAAA.Solkar:BAAANQADCgUIBQABNQAECggIGgALADcZAA==.Sollis:BAAANQAECgQICAAAAA==.Solohoes:BAAANQAECgUIBwAAAA==.Sonastii:BAAANQADCgYIBgABNQAECgcIGAAVAJwbAA==.Soulcoil:BAAANQAECgQIBwAAAA==.Soulfury:BAAANQABCgUIBgABNQAECgQIBwAHAAAAAA==.Soulreaper:BAAANQADCgQIBAABNQAECgQIBwAHAAAAAA==.Soulshock:BAAANQAECgQJBAABNQAECgQIBwAHAAAAAA==.Soulstorm:BAAANQADCgYIBgABNQAECgQIBwAHAAAAAA==.',
Sp='Spawntier:BAAANQADCgUIBQABNQADCggICAAHAAAAAA==.Spazzchel:BAAANQADCggIIAAAAA==.Spiritbox:BAACNQAFFIEKAAIEAAYKdRqWAwADAgAEAAYKdRqWAwADAgA1AAQKgR8AAgQACQqxJCsHAG8DAAQACQqxJCsHAG8DAAE1AAQKCQkXAAUAeB0A.Spruce:BAAANQADCggIGAAAAA==.Sprucemoose:BAAANQADCgUICgAAAA==.',
St='Stahlman:BAABNQAECoEWAAMEAAgKERJPTgDaAQAEAAgKERJPTgDaAQATAAIK+Aa54gBbAAAAAA==.Stalpho:BAABNQAECoEbAAIiAAgKvhaSBgBKAgAiAAgKvhaSBgBKAgAAAA==.Starblessed:BAAANQADCgYIEQABNQAECgYICgAHAAAAAA==.Starkind:BAAANQAECgYICgAAAA==.Starliner:BAABNQAECoEYAAIdAAkKyCHYAQCLAwAdAAkKyCHYAQCLAwAAAA==.Stasis:BAAANQAECgMIAwABNQAECgkJFwAFAHgdAA==.Stormyknight:BAAANQADCgUIBQAAAA==.Strahd:BAAANQADCgUIEwAAAA==.Styrke:BAAANQADCgYIBgAAAA==.Styrmir:BAAANQAECgQIBAAAAA==.',
Su='Subza:BAABNQAECoEkAAIXAAkKMBUyYwCJAgAXAAkKMBUyYwCJAgAAAA==.Suurik:BAAANQABCgIIAgAAAA==.',
Sw='Swagtistic:BAAANQADCggJFAAAAA==.',
Ta='Tahra:BAAANQADCgcICQAAAA==.Taliss:BAABNQAECoEbAAIFAAgK7hckLgBwAgAFAAgK7hckLgBwAgAAAA==.Tankmedaddy:BAABNQAECoEjAAMcAAkKlhBwGgAXAgAcAAkKlhBwGgAXAgAgAAQKSxe1JQD2AAAAAA==.Tappuccino:BAAANQAECgMIAwAAAA==.Taras:BAABNQAECoEjAAMMAAkKnyN0MgDFAgAMAAgKsyJ0MgDFAgAiAAYKnBqqCwC2AQAAAA==.Taraxist:BAABNQAECoEYAAIUAAcKwxi/DQALAgAUAAcKwxi/DQALAgAAAA==.Tautology:BAAANQAECgcIDQAAAA==.Tazajin:BAAANQADCgYIBgAAAA==.',
Tc='Tchala:BAABNQAECoEbAAIDAAgKGx0XUQBRAgADAAgKGx0XUQBRAgAAAA==.Tchallah:BAAANQAECgMIAgAAAA==.Tchaumb:BAAANQADCgEIAQAAAA==.',
Td='Tdog:BAAANQADCgcJBwAAAA==.',
Te='Teacup:BAAANQADCgYIBgABNQAECgYJDwAHAAAAAA==.Teks:BAABNQAECoEYAAMPAAcK3Ba/UADjAQAPAAcK3Ba/UADjAQAKAAYKchZaIACFAQAAAA==.Telian:BAAANQADCgUIBQAAAA==.Terracustode:BAAANQABCgIJAgAAAA==.Teth:BAAANQAECgUIBgAAAA==.Tevildo:BAAANQABCgIIAgAAAA==.',
Th='Thaine:BAABNQAECoEkAAIDAAkKlCO6CgCRAwADAAkKlCO6CgCRAwAAAA==.Theundeadone:BAABNQAECoEjAAIVAAkKyhzfCgAOAwAVAAkKyhzfCgAOAwAAAA==.Thndrwzrd:BAAANQAECgIIAgAAAA==.Thorphan:BAABNQAECoEkAAQdAAkKWB+vAwBIAwAdAAkKWB+vAwBIAwATAAUKBxbNjAAsAQAEAAUKcAsoqADJAAAAAA==.',
Ti='Ticho:BAAANQAECgQIBgAAAA==.',
To='Torez:BAAANQAECgUICQABNQAECgkJJAAQAG0YAA==.Torodisilis:BAAANQAECgUIBwABNQAECggIGwADABsdAA==.Toxicavenger:BAAANQAECggJCAAAAA==.',
Tr='Treygec:BAAANQAECgQIBgAAAA==.Tribolonotus:BAAANQADCgcIGwAAAA==.Trickette:BAAANQADCgUJBQABNQAECggICQAHAAAAAA==.Trilleong:BAAANQADCgIIAgAAAA==.Trina:BAAANQADCggJCAAAAA==.Trisilla:BAAANQADCggIEAABNQAECggIJgAkAGENAA==.Troubleshot:BAAANQADCgYJBgAAAA==.Trujal:BAABNQAECoEcAAILAAgK/hbNLAAnAgALAAgK/hbNLAAnAgAAAA==.',
Tu='Turdmonk:BAABNQAECoEpAAIcAAgKTx1nEACjAgAcAAgKTx1nEACjAgAAAA==.',
Ty='Tylandon:BAAANQABCgQICAAAAA==.Tyndal:BAAANQADCgcICwAAAA==.Typhon:BAABNQAECoEcAAMVAAgKFBvlHAARAgAVAAcKMRrlHAARAgAFAAUK5h6pWwCtAQAAAA==.',
Un='Unclebób:BAAANQADCgYIDAABNQAECgUICAAHAAAAAA==.Unshady:BAAANQADCgYIBgABNQAECgUIDwAHAAAAAA==.',
Va='Vaeshta:BAAANQAECgYIEAAAAA==.Vaku:BAAANQADCgYIBgAAAA==.Valhallarama:BAABNQAECoEeAAIEAAkKPhlFKgB8AgAEAAkKPhlFKgB8AgAAAA==.Valika:BAAANQABCgYIBgAAAA==.Vampy:BAAANQAECgQIBAAAAA==.Vandragon:BAAANQADCggICAAAAA==.Vannida:BAAANQADCgUICQAAAA==.',
Ve='Vengencedawg:BAABNQAECoEbAAIDAAcKLQnksABKAQADAAcKLQnksABKAQAAAA==.Vexxya:BAAANQADCgQIAwAAAA==.',
Vl='Vladus:BAABNQAECoEaAAILAAgKNxmjJwBKAgALAAgKNxmjJwBKAgAAAA==.',
Vo='Voltroñ:BAAANQADCgMIAwABNQAECgkJJgAXAB4eAA==.Voodoo:BAAANQAECgQIBAAAAA==.',
Vs='Vsegda:BAAANQABCgYIBgABNQAECgkJIgAEAIMWAA==.',
Vy='Vyllian:BAAANQAECgYIEgAAAA==.',
Wa='Wangwang:BAAANQADCgcIHAAAAA==.Wardrag:BAAANQABCgQIBAAAAA==.Wareshesh:BAAANQADCgUIBQAAAA==.Warlakaflaka:BAAANQAECgQICQABNQAECgUIDwAHAAAAAA==.',
Wh='Whale:BAAANQAECgcIEQAAAA==.',
Wi='Windfury:BAABNQAECoEcAAIdAAgKbA+bDwAsAgAdAAgKbA+bDwAsAgAAAA==.Windfuryous:BAAANQADCgUICQAAAA==.Winston:BAAANQADCgcIGAAAAA==.',
Wo='Wolfsbane:BAAANQADCgYIBgAAAA==.Wonpiece:BAAANQADCgQIBgABNQAECgkJIQABAIoUAA==.',
Wu='Wulfnir:BAAANQADCgcIBwAAAA==.',
Wy='Wylestrean:BAABNQAECoEdAAIGAAkKMR1hGgD9AgAGAAkKMR1hGgD9AgAAAA==.',
Xa='Xanokz:BAAANQADCgEIAQABNQAECggIHAAKABwfAA==.Xarytha:BAAANQABCgMJAwABNQAECggIDAAHAAAAAA==.',
Xi='Xiaomao:BAEANQADCgcIBwABNQAECgEIAQAHAAAAAA==.',
Ye='Yeinn:BAABNQAECoElAAMMAAgKxh9KPgCXAgAMAAgKJx9KPgCXAgAiAAQK8xoIEABRAQAAAA==.',
Za='Zandalarthas:BAAANQAECgUIDAAAAA==.',
Zc='Zcredo:BAABNQAECoEiAAIMAAkKLx/sGwApAwAMAAkKLx/sGwApAwAAAA==.',
Ze='Zel:BAAANQAECgIIAgAAAA==.Zentradei:BAAANQADCgQIBAAAAA==.Zephariel:BAAANQADCgQJCwAAAA==.Zerus:BAAANQABCgMIBAAAAA==.',
Zi='Ziconik:BAAANQADCgYIBgAAAA==.Zieganfuss:BAAANQAECggIDAAAAA==.Zinrozlek:BAAANQAECgYIDgAAAA==.',
Zo='Zoho:BAABNQAECoEmAAIkAAgKYQ0bEQCRAQAkAAgKYQ0bEQCRAQAAAA==.Zorrander:BAAANQADCgQIBAABNQADCgYICgAHAAAAAA==.',
Zy='Zynvar:BAAANQADCggICAAAAA==.',
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
