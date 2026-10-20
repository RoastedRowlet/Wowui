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

local lookup = {'DemonHunter-Havoc','Warlock-Destruction','DeathKnight-Blood','DeathKnight-Frost','Shaman-Restoration','Shaman-Elemental','Rogue-Subtlety','Priest-Shadow','Priest-Holy','DemonHunter-Vengeance','Mage-Arcane','Mage-Frost','Warrior-Arms','Warrior-Fury','Paladin-Retribution','Paladin-Protection','Monk-Brewmaster','Hunter-BeastMastery','Monk-Windwalker','Monk-Mistweaver','Evoker-Devastation','Warlock-Demonology','Shaman-Enhancement','Hunter-Marksmanship','Warrior-Protection','Paladin-Holy','Unknown-Unknown','Druid-Restoration','Rogue-Outlaw','Rogue-Assassination','Druid-Balance','Druid-Guardian','DemonHunter-Devourer','Priest-Discipline','Druid-Feral','Warlock-Affliction','Hunter-Survival','DeathKnight-Unholy',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aaylasecura:BAABNQAECn86AAIBAAoKjyBZAgCYAgABAAoKjyBZAgCYAgAAAA==.',
Ab='Abelladanger:BAAANQADCgQJBAAAAA==.Abracadavar:BAAANQADCgEIAQABNQAFFAkJHQACAFsZAA==.Absinth:BAABNQAECn8aAAMDAAkKKQ0EYgBqAQADAAkKKQ0EYgBqAQAEAAIKlgIHbAAvAAAAAA==.',
Ai='Aidaric:BAAANQADCgUIBQAAAA==.Airfriend:BAABNQAECn8+AAMFAAoK5xLoGACSAQAFAAoK5xLoGACSAQAGAAUKZRoBnABgAQAAAA==.',
Al='Alder:BAAANQAECgUIDwAAAA==.Alphard:BAABNQAECn8rAAIHAAkK8BwHDAC1AgAHAAkK8BwHDAC1AgAAAA==.',
An='Anelowyn:BAABNQAECn8rAAMIAAkKBROZJgD4AQAIAAkKBROZJgD4AQAJAAcKtwbNmABLAQAAAA==.Angrychicken:BAAANQAECgYIBgAAAA==.',
Ap='Apocal:BAACNQAFFH8JAAIKAAYKeRgjAQCxAQAKAAYKeRgjAQCxAQA1AAQKfy8AAgoACQr5I+0BAHoDAAoACQr5I+0BAHoDAAAA.',
Ar='Arete:BAAANQAECgYIBgAAAA==.Arthritis:BAAANQADCgUIBQAAAA==.',
As='Asmodyus:BAABNQAECn8XAAMLAAkKOAn9WAALAQALAAkKOAn9WAALAQAMAAQKAAazLACXAAAAAA==.Asmozaps:BAABNQAECn8qAAIGAAoKmA4hCQDUAQAGAAoKmA4hCQDUAQAAAA==.',
At='Ataraxya:BAAANQAECgQIBAAAAA==.',
Az='Aziel:BAABNQAECn8dAAMNAAoK1gvRWADoAAANAAoKgwvRWADoAAAOAAEKcw3eMAA8AAAAAA==.Azmodeaus:BAAANQADCgcIBwAAAA==.',
Ba='Baraden:BAABNQAECn8cAAIGAAcKpBB9ewCwAQAGAAcKpBB9ewCwAQAAAA==.',
Be='Beefblood:BAAANQAECgMIBAAAAA==.',
Bh='Bhxdeeznutz:BAAANQABCgIIAgAAAA==.Bhxrafiq:BAAANQADCgYIBgAAAA==.',
Bi='Bigtimmehss:BAAANQAECgMIBQAAAA==.Bih:BAAANQADCgMIAwAAAA==.Bikerm:BAAANQAECgEIAQABNQAFFAcIGgAKAAcgAA==.Billiards:BAAANQADCggICAABNQAECgoKMgALAHQZAA==.Birgetta:BAAANQADCggICAABNQAECggIGwABAC0FAA==.',
Bl='Blitzkrieged:BAAANQAECggICAAAAA==.Blorne:BAAANQAECgQICAAAAA==.',
Bo='Bobodaklown:BAABNQAECn8zAAMPAAkK8h2jPADgAgAPAAgKJSCjPADgAgAQAAYK2RBoCQBjAQAAAA==.Boneshade:BAAANQAECgMIAwAAAA==.Boombawks:BAAANQADCgUICQAAAA==.Boomnbrew:BAABNQAECn8nAAIRAAoK3w3+EQDGAQARAAoK3w3+EQDGAQAAAA==.Bownir:BAABNQAECn8YAAISAAcKdA4iowDAAQASAAcKdA4iowDAAQAAAA==.',
Br='Braelsong:BAAANQAECgEIAQAAAA==.Brewman:BAABNQAECn8oAAMTAAoKKxRrHwA0AgATAAoKKxRrHwA0AgAUAAMKKBC4OACoAAAAAA==.',
Bu='Bubonic:BAAANQAECgUIDgAAAA==.Buenasalud:BAABNQAECn8ZAAIJAAkKfRcCZAD0AQAJAAkKfRcCZAD0AQAAAA==.',
Ca='Catopriest:BAAANQAECgcICwABNQAFFAMIBQAVAA8IAA==.Caylea:BAACNQAFFH8RAAINAAYKNBTREwCOAQANAAYKNBTREwCOAQA1AAQKfy0AAg0ACgpTIZMnABsDAA0ACgpTIZMnABsDAAAA.',
Ch='Chalis:BAABNQAECn8bAAMCAAgKpB7uFwCtAQACAAQKfiTuFwCtAQAWAAcKxxg3pwCFAQAAAA==.Chimonkey:BAAANQABCgIIAgAAAA==.',
Cl='Clamsquirter:BAABNQAECn8bAAMFAAkKzxszPABvAgAFAAkKzxszPABvAgAXAAIKtQlxMABqAAAAAA==.Clanis:BAAANQAECgYIDQABNQAFFAYIDgAYAKcYAA==.',
Co='Coldhwip:BAABNQAECn8xAAMMAAoKfBbNBQBEAQALAAkKdRPxvwAEAgAMAAkKmRXNBQBEAQAAAA==.',
Cr='Crtaker:BAAANQAECgcICAAAAA==.Crushfoot:BAAANQADCgUIBQAAAA==.Crysis:BAABNQAECn8xAAIZAAoKFxyVAwCqAQAZAAoKFxyVAwCqAQAAAA==.',
Cu='Cuahtemoc:BAAANQADCgYIDQAAAA==.',
Da='Dabss:BAAANQAECgEIAQAAAA==.Daelin:BAABNQAECn8rAAMPAAkKqB++VgCSAgAPAAkKqB++VgCSAgAQAAgKqxWkIADfAQAAAA==.Dagda:BAAANQAECgUIBAAAAA==.Danye:BAAANQAECgMIBgAAAA==.Darknasti:BAAANQAECgEIAQAAAA==.Darkscout:BAAANQADCgUJDwAAAA==.Dasyra:BAAANQABCgIIAgABNQAECgoKLwAFAEYjAA==.',
De='Decease:BAAANQAECgQIBAABNQAFFAIIBQACAA8cAA==.Delium:BAACNQAFFH8RAAILAAYKihHbEgDhAQALAAYKihHbEgDhAQA1AAQKfykAAgsACgpPIQ4pAD8DAAsACgpPIQ4pAD8DAAAA.Demonmommy:BAAANQAECgUIDAAAAA==.Deäthrose:BAABNQAECn8qAAMGAAkK3A8kWgAUAgAGAAkK3A8kWgAUAgAFAAgKCAmXjgBkAQAAAA==.',
Di='Die:BAAANQAECgYICgAAAA==.Diegoo:BAAANQADCgUIBQAAAA==.Disc:BAAANQAECgYIBgAAAA==.',
Do='Doadin:BAABNQAECn8zAAIaAAkK8xYhIQBjAQAaAAkK8xYhIQBjAQAAAA==.Dolphus:BAABNQAECn8WAAIOAAkKeBe+CABWAgAOAAkKeBe+CABWAgAAAA==.Dolust:BAAANQAECgQIAgABNQAECgkJMwAaAPMWAA==.Doominatrix:BAABNQAECn8sAAIWAAoK9xFMaQAgAgAWAAoK9xFMaQAgAgAAAA==.Dotem:BAAANQAECgQIBQAAAA==.',
Dr='Draggum:BAAANQADCggIFQABNQAECgkJLgAPABggAA==.Dragune:BAAANQAECgIIAgABNQAECggIGwACAKQeAA==.Dreadlocky:BAABNQAECn8mAAMCAAkKZBXJDQAcAgACAAgKiBfJDQAcAgAWAAQKAg0DBgHAAAAAAA==.Dreadmagey:BAAANQADCggICQABNQADCgYIDAAbAAAAAA==.Dreadraven:BAAANQADCgYIDAAAAA==.Dreven:BAAANQADCggIEAABNQAECgcIFwAIANUQAA==.Drip:BAAANQAECgIIAgAAAA==.Druidhams:BAABNQAECn8bAAIcAAoKdh3QDQDzAgAcAAoKdh3QDQDzAgAAAA==.',
Du='Dunktars:BAABNQAECn8nAAINAAoKzB/iQwC+AgANAAoKzB/iQwC+AgAAAA==.Durpy:BAAANQADCgIIAwAAAA==.',
Eg='Egri:BAAANQAECgQIBgAAAA==.',
Ei='Eightball:BAAANQAECgEIAQABNQAECgoKMgALAHQZAA==.',
El='Electro:BAAANQADCgYIBgABNQAECgQIBgAbAAAAAA==.Elisha:BAABNQAECn9bAAIPAAkK8Q+PogDcAQAPAAkK8Q+PogDcAQAAAA==.Eltara:BAAANQADCgEIAQAAAA==.',
Er='Erebostro:BAABNQAECn8rAAISAAkKNRqhPwCsAgASAAkKNRqhPwCsAgAAAA==.',
Fa='Facheritor:BAAANQADCgUIBAAAAA==.Fastlane:BAAANQAECgQIDAAAAA==.Fathercow:BAAANQAFFAIIAgAAAA==.Fathoms:BAAANQABCggIDgAAAA==.Fauxphoe:BAAANQADCgMIAwAAAA==.Fauxtotem:BAABNQAECn8vAAIXAAoK7R+GBQAyAwAXAAoK7R+GBQAyAwAAAA==.',
Fe='Fender:BAAANQAECgEIAQAAAA==.Ferdinand:BAAANQADCgcIBwABNQAECgcIEAAbAAAAAA==.Ferren:BAAANQABCgQIBAAAAA==.',
Fi='Fingies:BAABNQAECn8+AAMWAAkKrSPWEAC8AQAWAAcKJyTWEAC8AQACAAIKeyLGCQCBAAAAAA==.',
Fl='Flexyheals:BAAANQABCgQIBQAAAA==.Flush:BAAANQAECggICAAAAA==.',
Fr='Freakbeast:BAAANQAECgEIAQABNQAECgoKHAAdAK8gAA==.',
Fu='Furina:BAAANQAECgIIAgAAAA==.',
['Fë']='Fënn:BAAANQAECgQIBQAAAA==.',
Ga='Galaxsea:BAABNQAECn8mAAITAAkKdht5EQDUAgATAAkKdht5EQDUAgAAAA==.Gale:BAAANQADCgYIBwABNQAECggIHgATAEoVAA==.Gamefreak:BAAANQAECgQIBAAAAA==.',
Ge='Gerthquake:BAAANQAECggIEgAAAA==.',
Gh='Ghostfreak:BAABNQAECn8lAAIeAAkKYxZ5CgB7AQAeAAkKYxZ5CgB7AQAAAA==.',
Gi='Giren:BAAANQAECggIBwABNQAFFAcIHAAPAG8cAA==.',
Go='Gobø:BAAANQAECgQIBAAAAA==.Gooby:BAABNQAECn8WAAINAAcKXRZ2ogDGAQANAAcKXRZ2ogDGAQAAAA==.',
Gr='Grindlemorph:BAAANQADCgYICAAAAA==.',
Ha='Hacks:BAABNQAECn8fAAMFAAcKxxGAIQBiAQAFAAcKxxGAIQBiAQAGAAUKtwWT0gDuAAAAAA==.Haranjer:BAABNQAECn8eAAITAAgKJBuyGgBpAgATAAgKJBuyGgBpAgAAAA==.',
He='Hefferhumper:BAABNQAECn8eAAMfAAgK5Q71FQAtAQAgAAYKnRIMKgBHAQAfAAgKFAb1FQAtAQAAAA==.',
Ho='Homlock:BAAANQADCgYICwABNQAFFAcIHAALAMQgAA==.Homslam:BAAANQAECggIEwABNQAFFAcIHAALAMQgAA==.Homsorc:BAACNQAFFH8cAAMLAAcKxCAdCQA2AgALAAYKQyAdCQA2AgAMAAIKSyA5BABnAAA1AAQKfysAAgsACgo1JosEANUDAAsACgo1JosEANUDAAAA.Homstab:BAACNQAFFH8GAAIHAAIK8x1BDQDKAAAHAAIK8x1BDQDKAAA1AAQKfyIAAwcACQr1H9MTAEsCAAcACQr1H9MTAEsCAB4AAgr5JPd2ANYAAAE1AAUUBwgcAAsAxCAA.Homtard:BAAANQAECgQICAABNQAFFAcIHAALAMQgAA==.Homtotem:BAAANQADCggICAABNQAFFAcIHAALAMQgAA==.Homwiz:BAAANQAECgQIBgAAAA==.Hope:BAABNQAECn8kAAIaAAkK3BQRRgBOAgAaAAkK3BQRRgBOAgAAAA==.',
Ic='Iced:BAAANQADCgIIAgABNQAECgkJIAAIANIWAA==.Icons:BAAANQAECggICAAAAA==.Icyshaft:BAAANQADCgMIAwABNQAFFAYIDgAYAKcYAA==.',
Il='Illiandray:BAABNQAECn8sAAICAAgKeh7PAADSAQACAAgKeh7PAADSAQAAAA==.',
In='Insomniac:BAABNQAECn8qAAIhAAkKzSPnCABGAwAhAAkKzSPnCABGAwAAAA==.',
Is='Isklar:BAAANQADCgcIBwAAAA==.',
Ja='Jaegernaut:BAAANQADCgYIEgAAAA==.Jagernaut:BAAANQAECgUICwAAAA==.Jake:BAAANQAECgYIEAAAAA==.Jangaballs:BAAANQAECgYIDQAAAA==.Jawndie:BAABNQAECn8lAAMUAAgKRBq+EwBAAgAUAAgKRBq+EwBAAgARAAEKAABbNQAiAAAAAA==.',
Jo='Joker:BAAANQAECgIIAgAAAA==.',
Jy='Jynn:BAAANQAECgUIDAABNQAECgoKKQAiAB4gAA==.',
Ka='Kaalg:BAAANQADCgYIBgAAAA==.Kaalgormi:BAAANQABCgcICQAAAA==.Kammo:BAABNQAECn8zAAIEAAkKaiOzBQCFAwAEAAkKaiOzBQCFAwAAAA==.Kassa:BAAANQADCggIEQAAAA==.',
Ke='Keeah:BAABNQAECn8XAAIEAAgKBQevXQAxAQAEAAgKBQevXQAxAQAAAA==.Kestra:BAABNQAECn8xAAIUAAoKSgfEDwDeAAAUAAoKSgfEDwDeAAAAAA==.',
Ki='Kittysprigg:BAABNQAECn8cAAMjAAgKFhTzDwANAgAjAAgKFhTzDwANAgAfAAQKgwh6igCrAAAAAA==.',
Kl='Klingnor:BAAANQADCgcJBwAAAA==.',
Kr='Kravensteak:BAACNQAFFH8OAAIYAAYKpxgCCgCjAQAYAAYKpxgCCgCjAQA1AAQKfygAAhgACQoQHysYAJcCABgACQoQHysYAJcCAAAA.',
Ku='Kurty:BAAANQADCgUIBQAAAA==.',
Kw='Kwickin:BAAANQAECgYICAABNQAECgkJLgAPABggAA==.',
Ky='Kyreen:BAABNQAECn8ZAAISAAgK2xB0lADgAQASAAgK2xB0lADgAQAAAA==.',
['Kä']='Kärl:BAAANQADCgYIBwABNQAECgkJJgATAHYbAA==.',
Le='Leonelda:BAAANQADCgUIBQAAAA==.Leylines:BAABNQAECn8vAAILAAoKIhYukgBbAgALAAoKIhYukgBbAgAAAA==.',
Lu='Luciferr:BAAANQAECgEIAQAAAA==.Lukafox:BAAANQAECgcIDwAAAA==.Lunastarvale:BAABNQAECn8lAAISAAgKvxMfGQC1AQASAAgKvxMfGQC1AQAAAA==.Lunereclipse:BAAANQAECgQJBAAAAA==.',
Ma='Macha:BAABNQAECn8vAAMFAAoKRiNpBQCcAwAFAAoKRiNpBQCcAwAGAAYKkweGwAARAQAAAA==.Madith:BAAANQAECgQICgAAAA==.Maintarget:BAABNQAECn8gAAIIAAkK0hYLGwBxAgAIAAkK0hYLGwBxAgAAAA==.Malefisico:BAABNQAECn8aAAICAAgKExhFCgBTAgACAAgKExhFCgBTAgAAAA==.Mardríft:BAABNQAECn8oAAIfAAkK4hsGGwDwAgAfAAkK4hsGGwDwAgAAAA==.Marero:BAAANQADCgYICgAAAA==.Martyr:BAABNQAECn8oAAIVAAoK/w2CBgAYAQAVAAoK/w2CBgAYAQAAAA==.Mazga:BAABNQAECn8sAAIFAAgKwhEIOwD8AAAFAAgKwhEIOwD8AAAAAA==.',
Mc='Mcflury:BAAANQADCgYICwAAAA==.',
Me='Melee:BAAANQADCgYIDAAAAA==.Meteos:BAAANQABCgMIBAAAAA==.Mezoti:BAAANQADCggICgAAAA==.',
Mi='Mick:BAAANQAECgYICQAAAA==.Miraclehwip:BAAANQADCggICQAAAA==.',
Mo='Moaxzy:BAAANQAECgEIAQAAAA==.Moji:BAABNQAECn8yAAIUAAkKuBZpEAB5AgAUAAkKuBZpEAB5AgAAAA==.Monstermayi:BAABNQAECn8rAAMOAAkKKBUbCgAsAgAOAAkKKBUbCgAsAgANAAIKvxATMwFuAAAAAA==.Mooknight:BAABNQAECn8kAAIDAAkKkwmRXwBzAQADAAkKkwmRXwBzAQAAAA==.Moreina:BAAANQADCgUIBQABNQAECgoKOAAJADgaAA==.Morgoth:BAABNQAECn8mAAQWAAgKDhvFGQCKAQAWAAgKRRrFGQCKAQAkAAMK1RnIFwDPAAACAAEKAAC3dAA5AAAAAA==.Morteesha:BAAANQAECgEIAQABNQAECggIJQAUAEQaAA==.',
Mu='Muggy:BAABNQAECn8oAAIeAAgK4xDmNAAHAgAeAAgK4xDmNAAHAgAAAA==.',
My='Myrothar:BAAANQAECgUIBQAAAA==.Mytastical:BAAANQAECgMIBwAAAA==.',
['Må']='Måzikeen:BAAANQAECgQIBAABNQAECgoKLwAFAEYjAA==.',
['Mæ']='Mæve:BAAANQAECgYIBgABNQAECgoKLwAFAEYjAA==.',
Na='Najwah:BAABNQAECn8dAAMJAAoKjxs+FwAbAwAJAAoKjxs+FwAbAwAIAAQKRxE0SwDqAAAAAA==.Namalis:BAACNQAFFH8FAAMCAAIKDxzIBgBbAAACAAEKEhjIBgBbAAAWAAEKDCA+GgBSAAA1AAQKfyoABBYACgpAIk8eAAsDABYACAp5I08eAAsDAAIAAwrJFpk+AMgAACQAAQpXHAMOAFkAAAAA.Nanielito:BAABNQAECn8bAAILAAkKaxfagwB3AgALAAkKaxfagwB3AgAAAA==.',
Ne='Necrotik:BAAANQADCgIIAgAAAA==.Neffer:BAAANQAECgQIBwAAAA==.Nerra:BAAANQADCggIDgAAAA==.',
Ni='Nineball:BAAANQADCgIIAgABNQAECgoKMgALAHQZAA==.Ninjutsu:BAAANQAECgEIAQABNQAFFAIIBQACAA8cAA==.',
No='Nobunaka:BAAANQADCgYIBgAAAA==.Nonae:BAABNQAECn8XAAISAAgKTRiEbAA6AgASAAgKTRiEbAA6AgAAAA==.Norivari:BAAANQADCgYICwAAAA==.Nosali:BAABNQAECn8eAAIkAAgKoht0AwDBAgAkAAgKoht0AwDBAgABNQAECgoKOAAJADgaAA==.Nosliw:BAAANQAECggICAAAAA==.Noxilis:BAAANQAFFAEIAgAAAA==.',
Nu='Nuggetz:BAAANQADCggICQAAAA==.',
['Nï']='Nïghtman:BAAANQAECgcIDQABNQAECgcIDgAbAAAAAA==.',
Om='Omegá:BAABNQAECn8XAAMQAAgKPhHFJQCxAQAQAAgKcxDFJQCxAQAPAAEKWBNSkgFCAAABNQAECgkJGgADACkNAA==.',
Op='Optìmusprìme:BAABNQAECn8oAAMZAAkK7xbIEQAKAgAZAAkK7xbIEQAKAgAOAAEKAADuHAAAAAAAAA==.',
Or='Ordovic:BAAANQADCgUIBQAAAA==.',
Pa='Paladinchin:BAAANQAECggICAABNQAFFAcIFwAHAI0gAA==.Pandemic:BAABNQAECn8rAAISAAoKLRH6KwBtAQASAAoKLRH6KwBtAQAAAA==.Papa:BAABNQAECn8yAAQWAAoKqhVENwAkAQAkAAUKrxGNEQAzAQAWAAYKLhZENwAkAQACAAUKCxV2LQAWAQAAAA==.Pawfu:BAABNQAECn8pAAQTAAgKxhnIHABSAgATAAgKxhnIHABSAgAUAAYKmwxoKwATAQARAAIKmAn6KgBoAAAAAA==.',
Pe='Penywize:BAABNQAECn8cAAMPAAkK8wPMDwEEAQAPAAgKmwTMDwEEAQAaAAgKNgXZvAACAQAAAA==.',
Pi='Pilo:BAAANQADCgUICAAAAA==.',
Pl='Planeteer:BAAANQAECgEIBAAAAA==.',
Po='Pockets:BAABNQAECn8yAAILAAoKdBldIACQAQALAAoKdBldIACQAQAAAA==.',
Pr='Prenus:BAAANQAECgUJBwAAAA==.',
Ps='Psychic:BAABNQAECn8pAAIiAAoKHiADAQBgAwAiAAoKHiADAQBgAwAAAA==.',
Pu='Purge:BAAANQAECgMIBAAAAA==.',
Qr='Qrazi:BAABNQAECn8aAAIGAAgKwBDoZADyAQAGAAgKwBDoZADyAQAAAA==.',
Qu='Quenthil:BAAANQAECgUIBgAAAA==.Quick:BAAANQAECgUIDgABNQAECgkJLgAPABggAA==.',
Ra='Ratha:BAABNQAECn8vAAIQAAoKqSGIBABvAwAQAAoKqSGIBABvAwAAAA==.Ravincible:BAAANQAECgMIAwAAAA==.Razeal:BAAANQAECgUICwAAAA==.Razkul:BAAANQAECggIBgAAAA==.',
Ri='Ribbz:BAAANQADCgYICwAAAA==.',
Ro='Roguechin:BAACNQAFFH8XAAMHAAcKjSB1BADlAQAHAAUKpB51BADlAQAeAAQKayO4CQBpAQA1AAQKfysAAwcACgrPJQcHAA0DAAcACQrfJQcHAA0DAB4ABwqEIw0WAMsCAAAA.Rokkgar:BAABNQAECn8fAAIGAAgKOhjTQQBuAgAGAAgKOhjTQQBuAgAAAA==.Rottontoe:BAAANQADCgEIAQAAAA==.',
Ru='Runa:BAAANQAECggIEgAAAA==.',
Sa='Sageara:BAAANQAECgQIBAAAAA==.Samirath:BAABNQAECn8aAAIJAAgKJBfiVQAhAgAJAAgKJBfiVQAhAgAAAA==.',
Sc='Scared:BAACNQAFFH8KAAIJAAUK0QlKFABlAQAJAAUK0QlKFABlAQA1AAQKfz0AAgkACQoAInkMAF8DAAkACQoAInkMAF8DAAAA.',
Se='Secarious:BAAANQAECgIIAgAAAA==.Sehnsucht:BAABNQAECn8eAAQjAAcKvxm5EAD9AQAjAAYKuR25EAD9AQAcAAcKQBUWLQCzAQAgAAIKHQvqVQBOAAAAAA==.',
Sh='Shakti:BAAANQAECgUIBQAAAA==.Shieldcow:BAAANQAECgIIBAABNQAFFAIIAgAbAAAAAA==.Shinpal:BAAANQAECgYIBgAAAA==.Shmadu:BAABNQAECn8qAAISAAoKLSUxAQD2AwASAAoKLSUxAQD2AwAAAA==.Shockakhan:BAAANQADCgcIBwAAAA==.Shockk:BAAANQAECgQICAAAAA==.',
So='Soola:BAAANQADCggICAABNQAECgoKLwAQAKkhAA==.',
Sp='Spoof:BAAANQADCgYICwAAAA==.',
St='Stonedpriest:BAAANQAECgUICwAAAA==.',
Su='Surrëal:BAABNQAECn8bAAIBAAgKLQVVXQAMAQABAAgKLQVVXQAMAQAAAA==.',
Sw='Sweetmask:BAAANQAECgYIDQAAAA==.',
Sy='Sybela:BAAANQAECgEIAgABNQAECgoKMQAJAH4gAA==.',
Ta='Tahitian:BAAANQADCgIIAgAAAA==.Tahlreth:BAABNQAECn8rAAIMAAkKSh8xBQDFAgAMAAkKSh8xBQDFAgAAAA==.Tanidge:BAAANQADCgQIBAABNQAECgoKNgAGADwgAA==.Tanidgemage:BAAANQADCgQIBAABNQAECgoKNgAGADwgAA==.Tanidgetotem:BAABNQAECn82AAIGAAoKPCCWCgDBAQAGAAoKPCCWCgDBAQAAAA==.',
Te='Teias:BAABNQAECn84AAMJAAoKOBoCOQCEAgAJAAoKOBoCOQCEAgAIAAQKzhfUQAApAQAAAA==.Tersus:BAAANQADCgEIAQAAAA==.',
Th='Theleena:BAAANQABCgIIAgAAAA==.',
Ti='Tirael:BAAANQAECgUIBgABNQAECgoKOAAJADgaAA==.',
To='Torvald:BAAANQAECggICAABNQAECggICAAbAAAAAA==.',
Tr='Tricko:BAABNQAECn8wAAISAAkKFiKyBACKAgASAAkKFiKyBACKAgAAAA==.Trickshots:BAAANQADCgMIAwABNQAECgoKMgALAHQZAA==.Trogar:BAAANQADCgQIBwAAAA==.Trollbi:BAAANQADCgQIAgAAAA==.Trollfacion:BAAANQADCgYIBgAAAA==.Trollskingx:BAABNQAECn8lAAILAAkKCBh0pAA4AgALAAkKCBh0pAA4AgAAAA==.Trollzy:BAABNQAECn8rAAMXAAkKKx0eDgCKAgAXAAkKKx0eDgCKAgAFAAIKIAMGDgFMAAAAAA==.Trunkmonkey:BAABNQAECn8hAAIWAAoKfhP1TQBqAgAWAAoKfhP1TQBqAgAAAA==.Trunky:BAAANQAECgYIBgAAAA==.',
Ts='Tsaagan:BAABNQAECn8sAAIWAAoKIyGHJADyAgAWAAoKIyGHJADyAgAAAA==.',
Um='Umbrosa:BAAANQADCgcIBwABNQAECgoKMQAZABccAA==.',
Ur='Urthalos:BAAANQAECgcICQAAAA==.',
Va='Valica:BAAANQADCgUIBQAAAA==.Valiithria:BAAANQAECgQIBQAAAA==.Valkyruid:BAACNQAFFH8FAAIcAAIKVAt7CAB4AAAcAAIKVAt7CAB4AAA1AAQKfx0AAxwACgqeHXoRAMcCABwACgqeHXoRAMcCAB8AAQoAABO/ACIAAAAA.Varaxis:BAAANQABCgQIBgAAAA==.',
Ve='Veledreyssa:BAAANQAECgEIAgAAAA==.',
Vu='Vulgan:BAAANQADCgcICAAAAA==.',
Wa='Warriorchin:BAAANQAFFAMIAgABNQAFFAcIFwAHAI0gAA==.Waywatcher:BAAANQAECgQICAAAAA==.',
Wh='Whiilow:BAABNQAECn8dAAMFAAoKSBXNOwBwAgAFAAoKSBXNOwBwAgAGAAEKGAQlSwEoAAAAAA==.',
Wu='Wullgan:BAABNQAECn8cAAIJAAoKyBVRWQAWAgAJAAoKyBVRWQAWAgAAAA==.',
Xe='Xencure:BAAANQAFFAIIAwAAAA==.Xerk:BAAANQAECgcIDgAAAA==.',
Xy='Xyrna:BAABNQAECn8oAAIlAAkKKRzTAgD7AgAlAAkKKRzTAgD7AgABNQAECgoKLwAQAKkhAA==.',
Ya='Yareli:BAABNQAECn8lAAIKAAgKcQaKGAApAQAKAAgKcQaKGAApAQAAAA==.',
Yo='Youngdoug:BAAANQAECgEIAQAAAA==.',
Yu='Yunara:BAAANQADCgUIBQAAAA==.',
Za='Zartman:BAABNQAECn8cAAMmAAgKzhOEZQB6AQAmAAYKVhiEZQB6AQAEAAYK4wyhXAA2AQAAAA==.',
Ze='Zeleck:BAABNQAECn8XAAMIAAcK1RBmLADDAQAIAAcK1RBmLADDAQAJAAQK3gXl0QCwAAAAAA==.Zeno:BAACNQAFFH8cAAIPAAcKbxwWAQDBAgAPAAcKbxwWAQDBAgA1AAQKfy8AAg8ACgqZIWMVAG8DAA8ACgqZIWMVAG8DAAAA.Zetetic:BAAANQADCggICAAAAA==.',
Zg='Zgystrdst:BAABNQAECn8fAAIeAAgKfBLbMQAYAgAeAAgKfBLbMQAYAgABNQAECggIHwAGADoYAA==.',
Zi='Zinbar:BAAANQAECgYIDQAAAA==.',
Zo='Zoroark:BAAANQADCggIEAABNQAECgoKLwALACIWAA==.',
Zu='Zuggzugg:BAAANQADCgYIBgAAAA==.Zune:BAABNQAECn8eAAMTAAgKShX2LQCpAQATAAgK5BL2LQCpAQARAAYKaBMcFwBwAQAAAA==.',
['Çl']='Çloud:BAAANQAECgIIAwAAAA==.',
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
