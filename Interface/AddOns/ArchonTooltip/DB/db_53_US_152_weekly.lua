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

local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Warlock-Demonology','DeathKnight-Blood','DeathKnight-Frost','Shaman-Restoration','Shaman-Elemental','Evoker-Devastation','Rogue-Subtlety','Priest-Shadow','Priest-Holy','Mage-Arcane','Mage-Frost','Warrior-Arms','Warrior-Fury','Paladin-Retribution','Paladin-Protection','Monk-Brewmaster','Hunter-BeastMastery','Monk-Windwalker','Monk-Mistweaver','DeathKnight-Unholy','Priest-Discipline','Warlock-Destruction','Shaman-Enhancement','Rogue-Assassination','Hunter-Marksmanship','Warrior-Protection','Paladin-Holy','Unknown-Unknown','Druid-Restoration','Warlock-Affliction','Rogue-Outlaw','Druid-Balance','Druid-Guardian','Druid-Feral','DemonHunter-Devourer','Mage-Fire','Hunter-Survival',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aaylasecura:BAABNQAECn9EAAMBAAoKjiK9CABxAwABAAoKjiK9CABxAwACAAcKRhc7CQCdAQAAAA==.',
Ab='Abelladanger:BAAANQADCgQJBAAAAA==.Abracadavar:BAAANQADCgEIAQABNQAFFAoKLgADANwgAA==.Absinth:BAACNQAFFH8GAAIEAAMKwgSnHQBUAAAEAAMKwgSnHQBUAAA1AAQKfyEAAwQACgp0DARiAGoBAAQACgp0DARiAGoBAAUAAgqWAj6mACgAAAAA.',
Ai='Aidaric:BAAANQADCgUIBQAAAA==.Airfriend:BAABNQAECn9IAAMGAAoKDhupEAAOAwAGAAoKDhupEAAOAwAHAAUKZRoBnABgAQAAAA==.',
Al='Alder:BAABNQAECn8ZAAIIAAoKaAykCQCoAQAIAAoKaAykCQCoAQAAAA==.Alet:BAAANQADCgEIAQABNQAECgoKSAAGAA4bAA==.Alphard:BAABNQAECn8+AAIJAAoKmiFzDAD7AgAJAAoKmiFzDAD7AgAAAA==.',
An='Anelowyn:BAABNQAECn81AAMKAAoKRhTmEgD0AQAKAAoKRhTmEgD0AQALAAcKtwbNmABLAQAAAA==.Angrychicken:BAAANQAECgYIBgAAAA==.',
Ap='Apocal:BAACNQAFFH8KAAICAAcKyBcjAQCxAQACAAcKyBcjAQCxAQA1AAQKfzkAAgIACgoRJa4AAFwDAAIACgoRJa4AAFwDAAAA.',
Ar='Arete:BAAANQAECgcIDwAAAA==.Aridam:BAAANQAECgQIBAABNQAECgcIFwAKANUQAA==.Arthritis:BAAANQADCgUIBQAAAA==.',
As='Asmodyus:BAABNQAECn8nAAMMAAoKrAyAcQCdAQAMAAoKrAyAcQCdAQANAAQKAAazLACXAAAAAA==.Asmozaps:BAABNQAECn84AAIHAAoKlxDYMwDPAQAHAAoKlxDYMwDPAQAAAA==.',
At='Ataraxya:BAAANQAECgQIBAAAAA==.',
Az='Aziel:BAABNQAECn8lAAMOAAoK7gyKoADLAQAOAAoK7gyKoADLAQAPAAEKcw3eMAA8AAAAAA==.Azmodeaus:BAAANQADCgcIBwAAAA==.',
Ba='Baraden:BAABNQAECn8eAAIHAAcKFRF9ewCwAQAHAAcKFRF9ewCwAQAAAA==.',
Be='Beefblood:BAAANQAECgMIBAAAAA==.',
Bh='Bhxdeeznutz:BAAANQAECgQIBAAAAA==.Bhxrafiq:BAAANQADCgYIBgAAAA==.',
Bi='Bigtimmehss:BAAANQAECgMIBQAAAA==.Bih:BAAANQADCgMIAwAAAA==.Bikerm:BAAANQAECgEIAQABNQAFFAgIHAACAP8eAA==.Billiards:BAAANQADCggICAABNQAECgoKQQAMADQdAA==.Birgetta:BAAANQADCggICAABNQAECggIGwABAC0FAA==.',
Bl='Blitzkrieged:BAAANQAECggICAAAAA==.Blorne:BAAANQAECgQICAAAAA==.',
Bo='Bobodaklown:BAABNQAECn9FAAMQAAkKUSCjPADgAgAQAAkKUSCjPADgAgARAAgKQRFWGAB+AQAAAA==.Boneshade:BAAANQAECgMIAwAAAA==.Boombawks:BAAANQADCgUICQAAAA==.Boomnbrew:BAACNQAFFH8FAAISAAMK9wKbBgBiAAASAAMK9wKbBgBiAAA1AAQKfysAAhIACgpGDv4RAMYBABIACgpGDv4RAMYBAAAA.Bownir:BAABNQAECn8pAAITAAoKLxXxNgA7AgATAAoKLxXxNgA7AgAAAA==.',
Br='Braelsong:BAAANQAECgEIAQAAAA==.Brewman:BAACNQAFFH8HAAIUAAMKJBCQCADKAAAUAAMKJBCQCADKAAA1AAQKfy0AAxQACgrYF2sfADQCABQACgrYF2sfADQCABUAAwooELg4AKgAAAAA.',
Bu='Bubonic:BAABNQAECn8XAAIWAAcKrwoARgDIAAAWAAcKrwoARgDIAAAAAA==.Buenasalud:BAABNQAECn8iAAILAAkK2htpIgCcAgALAAkK2htpIgCcAgAAAA==.',
Ca='Catopriest:BAABNQAECn8aAAIXAAoK4BmqAQDAAgAXAAoK4BmqAQDAAgABNQAFFAYICgAIAJwJAA==.Caylea:BAACNQAFFH8SAAIOAAcKBhTREwCOAQAOAAcKBhTREwCOAQA1AAQKfzoAAg4ACgofIpMnABsDAA4ACgofIpMnABsDAAAA.',
Ch='Chalis:BAABNQAECn8gAAMYAAgKPiHuFwCtAQAYAAQKfiTuFwCtAQADAAcKhx6LagBeAQAAAA==.',
Cl='Clamsquirter:BAACNQAFFH8FAAMGAAMKuBF1JQB3AAAGAAIK3gp1JQB3AAAZAAIKoAwCCABRAAA1AAQKfyIABAYACgoLGjM8AG8CAAYACgoLGjM8AG8CABkAAwq1CXEwAGoAAAcAAQoeEQHqAC0AAAAA.Clanis:BAABNQAECn8iAAMJAAkKohRpLAAVAgAJAAkKQRNpLAAVAgAaAAUKnRSkOQCWAAABNQAFFAcIDwAbAKgXAA==.',
Co='Coldhwip:BAABNQAECn87AAMNAAoK5hjNDwCrAQAMAAkK1RPxvwAEAgANAAoK4RbNDwCrAQAAAA==.',
Cr='Crtaker:BAAANQAECgcICgAAAA==.Crushfoot:BAAANQADCgUIBQAAAA==.Crysis:BAABNQAECn87AAIcAAoKxx72CADAAgAcAAoKxx72CADAAgAAAA==.',
Cu='Cuahtemoc:BAAANQADCgYIDQAAAA==.',
Da='Dabss:BAAANQAECgEIAQAAAA==.Daelin:BAABNQAECn80AAMQAAoKTCK3FwDrAgAQAAoKTCK3FwDrAgARAAgKqxWkIADfAQAAAA==.Dagda:BAAANQAECgUIBAAAAA==.Danye:BAAANQAECgMIBgAAAA==.Darknasti:BAAANQAECgEIAQAAAA==.Darkscout:BAAANQADCgUJDwAAAA==.Dasyra:BAAANQAECgQIBAABNQAECgoKOQAGAEYjAA==.',
De='Decease:BAAANQAECgQIBAABNQAFFAQIBwADAKsYAA==.Delium:BAACNQAFFH8TAAMMAAYKUBPbEgDhAQAMAAYKUBPbEgDhAQANAAEK1xZbEQBHAAA1AAQKfzAAAgwACgofIg4pAD8DAAwACgofIg4pAD8DAAAA.Demonmommy:BAABNQAECn8WAAIDAAYKkQSZ8wDjAAADAAYKkQSZ8wDjAAAAAA==.Deäthrose:BAACNQAFFH8FAAIHAAMKDwK3GwByAAAHAAMKDwK3GwByAAA1AAQKfzIAAwcACgowECRaABQCAAcACgowECRaABQCAAYACAoICZeOAGQBAAAA.',
Di='Die:BAAANQAECgYICgAAAA==.Diegoo:BAAANQADCgUIBQAAAA==.Disc:BAAANQAECgYIBwAAAA==.',
Do='Doadin:BAABNQAECn9FAAIdAAkK7BvdFQDdAgAdAAkK7BvdFQDdAgAAAA==.Dolphus:BAABNQAECn8fAAIPAAkKCxkWBwANAgAPAAkKCxkWBwANAgAAAA==.Dolust:BAAANQAECgQIBgABNQAECgkJRQAdAOwbAA==.Doominatrix:BAACNQAFFH8GAAIDAAMKgQd3IQCOAAADAAMKgQd3IQCOAAA1AAQKfzUAAgMACgofE0xpACACAAMACgofE0xpACACAAAA.Dotem:BAAANQAECgQIBgAAAA==.',
Dr='Draggum:BAAANQADCggIFQABNQAECgkJLgAQABggAA==.Dragune:BAAANQAECgMIBQABNQAECggIIAAYAD4hAA==.Dreadlocky:BAABNQAECn83AAMYAAkKDhnlAgDxAQAYAAkKDhnlAgDxAQADAAQKAg0DBgHAAAAAAA==.Dreadmagey:BAAANQADCggICQABNQADCgYIDAAeAAAAAA==.Dreadraven:BAAANQADCgYIDAAAAA==.Dreven:BAAANQADCggIEAABNQAECgcIFwAKANUQAA==.Drip:BAAANQAECgIIAgAAAA==.Druidhams:BAACNQAFFH8GAAIfAAMKahDyDQCPAAAfAAMKahDyDQCPAAA1AAQKfyQAAh8ACgrRHtANAPMCAB8ACgrRHtANAPMCAAAA.',
Du='Dunktars:BAACNQAFFH8GAAIOAAMK0BAoIQCKAAAOAAMK0BAoIQCKAAA1AAQKfy0AAg4ACgoMIOJDAL4CAA4ACgoMIOJDAL4CAAAA.Durpy:BAAANQADCgIIAwAAAA==.',
Eg='Egri:BAAANQAECgQIBgAAAA==.',
Ei='Eightball:BAAANQAECgYICAABNQAECgoKQQAMADQdAA==.',
El='Electro:BAAANQADCgYIBgABNQAECgQIBgAeAAAAAA==.Elisha:BAABNQAECn9jAAIQAAoKsxCPogDcAQAQAAoKsxCPogDcAQAAAA==.Eltara:BAAANQADCgEIAQAAAA==.',
Er='Erebostro:BAABNQAECn80AAITAAoKNRihPwCsAgATAAoKNRihPwCsAgAAAA==.',
Fa='Facheritor:BAAANQADCgUIBAAAAA==.Fastlane:BAAANQAECgQIEAAAAA==.Fathercow:BAAANQAFFAIIAgAAAA==.Fathoms:BAAANQAECgUIBwAAAA==.Fauxphoe:BAAANQADCgMIAwAAAA==.Fauxtotem:BAACNQAFFH8GAAIZAAMKxhARAwDnAAAZAAMKxhARAwDnAAA1AAQKfzUAAhkACgqiIYYFADIDABkACgqiIYYFADIDAAAA.',
Fe='Fender:BAAANQAECgEIAQAAAA==.Ferdinand:BAAANQADCgcIBwABNQAECgoKFQAWAGcHAA==.Ferren:BAAANQABCgQIBAAAAA==.',
Fi='Fingies:BAABNQAECn9SAAQDAAoKbiMrHwBzAgADAAgKTSUrHwBzAgAYAAIKeyLWEwChAAAgAAEKrhlMIQBFAAAAAA==.',
Fl='Flexyheals:BAAANQABCgQIBQAAAA==.Flush:BAAANQAECggICAAAAA==.',
Fr='Freakbeast:BAAANQAECgEIAQABNQAECgoKJgAhAMciAA==.',
Fu='Furina:BAAANQAECgIIAgAAAA==.',
['Fë']='Fënn:BAAANQAECgQIBQAAAA==.',
['Fí']='Fíona:BAAANQABCgEIAQABNQAECggIDQAeAAAAAA==.',
Ga='Galaxsea:BAABNQAECn84AAIUAAoKSR3VDABmAgAUAAoKSR3VDABmAgAAAA==.Gale:BAAANQADCgYIBwABNQAECgoKLwAUAB0YAA==.Gamefreak:BAAANQAECgQIBAAAAA==.',
Ge='Gerthquake:BAABNQAECn8hAAMGAAoKCBD8QQDbAQAGAAoKCBD8QQDbAQAHAAEKzgWJ5wAwAAAAAA==.',
Gh='Ghostfreak:BAABNQAECn8tAAIaAAkKQRfxDADYAQAaAAkKQRfxDADYAQAAAA==.',
Gi='Giren:BAAANQAECggIBwABNQAFFAgIHgAQAN8ZAA==.',
Gn='Gnomium:BAAANQADCggICAABNQAFFAQIDQANAGEVAA==.',
Go='Gobø:BAAANQAECgQIBAAAAA==.Gooby:BAABNQAECn8gAAIOAAoK7xM8RQABAgAOAAoK7xM8RQABAgAAAA==.',
Gr='Grindlemorph:BAAANQADCgYICAAAAA==.',
Ha='Hacks:BAABNQAECn8rAAMGAAgKuBFlWACAAQAGAAgKuBFlWACAAQAHAAUKtwWT0gDuAAAAAA==.Haranjer:BAABNQAECn8eAAIUAAgKJBuyGgBpAgAUAAgKJBuyGgBpAgAAAA==.',
He='Hefferhumper:BAABNQAECn8qAAQiAAkKExDeMABIAQAiAAgKxQjeMABIAQAjAAYKGRMMKgBHAQAkAAEKAAB+TwAAAAAAAA==.',
Ho='Homlock:BAAANQADCgYICwABNQAFFAcIHQAMAMQgAA==.Homslam:BAABNQAECn8UAAMOAAkKZB3YigABAgAOAAgK6hrYigABAgAcAAQKKRwnJwAHAQABNQAFFAcIHQAMAMQgAA==.Homsorc:BAACNQAFFH8dAAMMAAcKxCAdCQA2AgAMAAYKQyAdCQA2AgANAAIKSyDvCQBhAAA1AAQKfzUAAgwACgptJosEANUDAAwACgptJosEANUDAAAA.Homstab:BAACNQAFFH8JAAIJAAQKiBtBDQDKAAAJAAQKiBtBDQDKAAA1AAQKfy0AAwkACgqqIiYHADIDAAkACgqqIiYHADIDABoAAgr5JPd2ANYAAAE1AAUUBwgdAAwAxCAA.Homtard:BAAANQAFFAMIAwABNQAFFAcIHQAMAMQgAA==.Homtotem:BAAANQADCggICAABNQAFFAcIHQAMAMQgAA==.Homwiz:BAAANQAECgQIBgAAAA==.Hope:BAABNQAECn8rAAIdAAoKrhQRRgBOAgAdAAoKrhQRRgBOAgAAAA==.',
Ic='Iced:BAAANQADCgIIAgABNQAECgkJIQAKALQYAA==.Icons:BAAANQAECggICAAAAA==.Icyshaft:BAAANQADCgMIAwABNQAFFAcIDwAbAKgXAA==.',
Il='Illiandray:BAABNQAECn89AAIYAAoKvx2UAQBxAgAYAAoKvx2UAQBxAgAAAA==.',
In='Insomniac:BAABNQAECn89AAIlAAoKIyTnCABGAwAlAAoKIyTnCABGAwAAAA==.',
Is='Isklar:BAAANQADCgcIBwAAAA==.',
Ja='Jaegernaut:BAAANQADCgYIEgAAAA==.Jagernaut:BAAANQAECgUICwAAAA==.Jake:BAABNQAECn8bAAIMAAkKcg1qhgBsAQAMAAkKcg1qhgBsAQAAAA==.Jangaballs:BAAANQAECgYIDQAAAA==.Jawndie:BAABNQAECn8rAAMVAAoK5xi+EwBAAgAVAAoK5xi+EwBAAgASAAEKAABbNQAiAAAAAA==.',
Ji='Jinzo:BAAANQAECgIIAgABNQAECggIDQAeAAAAAA==.',
Jo='Joker:BAAANQAECgIIAgAAAA==.',
Jy='Jynn:BAAANQAECgUIEgABNQAECgoKLQAXAAshAA==.',
Ka='Kaalg:BAAANQADCgYIBgAAAA==.Kaalgormi:BAAANQABCgcICQAAAA==.Kammo:BAABNQAECn8zAAIFAAkKaiOzBQCFAwAFAAkKaiOzBQCFAwAAAA==.Kassa:BAAANQADCggIEQAAAA==.',
Ke='Keeah:BAABNQAECn8eAAIFAAkKeQevXQAxAQAFAAkKeQevXQAxAQAAAA==.Kestra:BAABNQAECn83AAIVAAoKgwdPIgByAQAVAAoKgwdPIgByAQAAAA==.',
Ki='Kittysprigg:BAABNQAECn8mAAMkAAoKrRPvCwDDAQAkAAoKrRPvCwDDAQAiAAQKgwh6igCrAAAAAA==.',
Kl='Klingnor:BAAANQADCgcJBwAAAA==.',
Kr='Kravensteak:BAACNQAFFH8PAAIbAAcKqBcCCgCjAQAbAAcKqBcCCgCjAQA1AAQKfzwAAhsACQrZIk4FAOUCABsACQrZIk4FAOUCAAAA.',
Ku='Kurty:BAAANQADCgUIBQAAAA==.',
Kw='Kwickin:BAABNQAECn8XAAMGAAcKQRF+fwCNAQAGAAYKKxN+fwCNAQAHAAUKqA2+nQCYAAABNQAECgkJLgAQABggAA==.',
Ky='Kyreen:BAABNQAECn8mAAITAAkKUxEEbwCaAQATAAkKUxEEbwCaAQAAAA==.',
['Kä']='Kärl:BAAANQADCgYIBwABNQAECgoKOAAUAEkdAA==.',
Le='Leonelda:BAAANQADCgUIBQAAAA==.Leylines:BAACNQAFFH8HAAMMAAMKxQV4MgCFAAAMAAIKaQV4MgCFAAANAAEKfAZgEwA6AAA1AAQKfzUAAwwACgo8GC6SAFsCAAwACgpkFy6SAFsCAA0AAgpFFAMlAIIAAAAA.',
Lu='Luciferr:BAAANQAECgEIAQAAAA==.Lukafox:BAABNQAECn8ZAAMGAAkKgx+jRQBLAgAGAAkKgx+jRQBLAgAHAAEKAAA9VgEiAAAAAA==.Lunastarvale:BAABNQAECn8sAAITAAoKgBSoQgAVAgATAAoKgBSoQgAVAgAAAA==.Lunereclipse:BAAANQAECgQJBAAAAA==.',
Ma='Macha:BAABNQAECn85AAMGAAoKRiNpBQCcAwAGAAoKRiNpBQCcAwAHAAYKkweGwAARAQAAAA==.Madith:BAAANQAECgQICgAAAA==.Maintarget:BAABNQAECn8hAAIKAAkKtBgLGwBxAgAKAAkKtBgLGwBxAgAAAA==.Malefisico:BAABNQAECn8hAAIYAAkKYBdFCgBTAgAYAAkKYBdFCgBTAgAAAA==.Mardríft:BAABNQAECn8yAAIiAAoKHB4qEwBbAgAiAAoKHB4qEwBbAgAAAA==.Marero:BAAANQADCgYICgAAAA==.Martyr:BAABNQAECn8yAAIIAAoKFg5dFAAJAgAIAAoKFg5dFAAJAgAAAA==.Mazga:BAABNQAECn86AAIGAAoKdRWGHwCRAgAGAAoKdRWGHwCRAgAAAA==.',
Mc='Mcflury:BAAANQADCgYICwAAAA==.',
Me='Melee:BAAANQADCgYIDAAAAA==.Meteos:BAAANQABCgMIBAAAAA==.Mezoti:BAAANQADCggICgAAAA==.',
Mi='Mick:BAAANQAECgYICQAAAA==.Miraclehwip:BAAANQADCggICQAAAA==.',
Mo='Moaxzy:BAAANQAECgEIAQAAAA==.Moji:BAABNQAECn84AAIVAAoKfxhpEAB5AgAVAAoKfxhpEAB5AgAAAA==.Monstermayi:BAABNQAECn8rAAMPAAkKKBUbCgAsAgAPAAkKKBUbCgAsAgAOAAIKvxATMwFuAAAAAA==.Mooknight:BAABNQAECn83AAIEAAoKdQybKQCLAQAEAAoKdQybKQCLAQAAAA==.Moreina:BAAANQADCgUIBQABNQAFFAMIBgALALEPAA==.Morgoth:BAABNQAECn8qAAQDAAkKjhwNQACSAgADAAgKehwNQACSAgAgAAQKUhnIFwDPAAAYAAEKAAC3dAA5AAAAAA==.Morteesha:BAAANQAECgIIAQABNQAECgoKKwAVAOcYAA==.',
Mu='Muggy:BAABNQAECn8yAAIaAAoK1xAAEQCYAQAaAAoK1xAAEQCYAQAAAA==.',
My='Myrothar:BAAANQAECgUIBQAAAA==.Mytastical:BAAANQAECgMIBwAAAA==.',
['Må']='Måzikeen:BAAANQAECgQIBAABNQAECgoKOQAGAEYjAA==.',
['Mæ']='Mæve:BAAANQAECgYIBgABNQAECgoKOQAGAEYjAA==.',
Na='Najwah:BAABNQAECn8dAAMLAAoKjxs+FwAbAwALAAoKjxs+FwAbAwAKAAQKRxE0SwDqAAAAAA==.Namalis:BAACNQAFFH8HAAMDAAQKqxj9HgCYAAADAAMK+Bj9HgCYAAAYAAEKEhg9DQBQAAA1AAQKfzEABAMACgpbI08eAAsDAAMACAp6I08eAAsDABgAAwrJFpk+AMgAACAAAQorJXMbAGYAAAAA.Nanielito:BAABNQAECn8bAAIMAAkKaxfagwB3AgAMAAkKaxfagwB3AgAAAA==.',
Ne='Necrotik:BAAANQADCgIIAgAAAA==.Neffer:BAAANQAECgQIBwAAAA==.Nerra:BAAANQADCggIDgAAAA==.',
Ni='Nineball:BAAANQADCgIIAgABNQAECgoKQQAMADQdAA==.Ninjutsu:BAAANQAECgEIAQABNQAFFAQIBwADAKsYAA==.',
No='Nobunaka:BAAANQADCgYIBgAAAA==.Nonae:BAABNQAECn8hAAITAAoKVxfGOAA1AgATAAoKVxfGOAA1AgAAAA==.Norivari:BAAANQADCgYICwAAAA==.Nosali:BAABNQAECn8vAAIgAAkKZxt0AwDBAgAgAAkKZxt0AwDBAgABNQAFFAMIBgALALEPAA==.Nosliw:BAAANQAECggICAAAAA==.Noxilis:BAABNQAECn8hAAIEAAoK/QsuLQB1AQAEAAoK/QsuLQB1AQAAAA==.',
Nu='Nuggetz:BAAANQADCggICQAAAA==.',
['Nï']='Nïghtman:BAAANQAECgcIDQABNQAECgoKHQAkABoZAA==.',
Om='Omegá:BAABNQAECn8iAAMRAAkKAxBrHgBFAQARAAkKUg9rHgBFAQAQAAEKWBNSkgFCAAABNQAFFAMIBgAEAMIEAA==.',
Oo='Oopsalldruid:BAAANQAECgEIAQABNQAECgkJLgAQABggAA==.',
Op='Optìmusprìme:BAABNQAECn87AAMcAAoK+hdKCQAHAgAcAAoK+hdKCQAHAgAPAAEKAABjNgAAAAAAAA==.',
Or='Ordovic:BAAANQADCgUIBQAAAA==.',
Pa='Paladinchin:BAAANQAECggICwABNQAFFAgIGQAJAD4fAA==.Pandemic:BAABNQAECn9FAAITAAoKhhkCJgB8AgATAAoKhhkCJgB8AgAAAA==.Papa:BAABNQAECn9EAAQDAAoKPBoqPADxAQADAAkKwBcqPADxAQAgAAUKrxGNEQAzAQAYAAUKCxV2LQAWAQAAAA==.Pawfu:BAABNQAECn8yAAQUAAkKphnIHABSAgAUAAkKphnIHABSAgAVAAgKrwpoKwATAQASAAIKmAn6KgBoAAAAAA==.',
Pe='Penywize:BAABNQAECn8nAAMdAAoKTgrbWAB/AQAdAAkKBgjbWAB/AQAQAAgKmwTMDwEEAQAAAA==.',
Pi='Pilo:BAAANQADCgUICAAAAA==.',
Pl='Planeteer:BAAANQAECgUICAAAAA==.',
Po='Pockets:BAABNQAECn9BAAMMAAoKNB0EbwCgAgAMAAoKNB0EbwCgAgAmAAIK8A7eBgB1AAAAAA==.',
Pr='Prenus:BAAANQAECgUJBwAAAA==.',
Ps='Psychic:BAABNQAECn8tAAIXAAoKCyEDAQBgAwAXAAoKCyEDAQBgAwAAAA==.',
Pu='Purge:BAAANQAECgMIBAAAAA==.',
Qr='Qrazi:BAABNQAECn8aAAIHAAgKwBDoZADyAQAHAAgKwBDoZADyAQAAAA==.',
Qu='Quenthil:BAAANQAECggIDgAAAA==.Quick:BAAANQAECgUIDgABNQAECgkJLgAQABggAA==.',
Ra='Ratha:BAACNQAFFH8HAAIRAAMKTRXZBADWAAARAAMKTRXZBADWAAA1AAQKfz8AAhEACgouI4gEAG8DABEACgouI4gEAG8DAAAA.Ravincible:BAAANQAECgMIAwAAAA==.Razeal:BAABNQAECn8ZAAIQAAkKRRB7fQCSAQAQAAkKRRB7fQCSAQAAAA==.Razkul:BAABNQAECn8VAAInAAkKQB9mAgCMAgAnAAkKQB9mAgCMAgAAAA==.',
Ri='Ribbz:BAAANQADCgYICwAAAA==.',
Ro='Roguechin:BAACNQAFFH8ZAAMJAAgKPh91BADlAQAJAAYKKB11BADlAQAaAAQKayO4CQBpAQA1AAQKfzsAAxoACgonJvsCAAUDAAkACgrDJQcHAA0DABoACQrWJfsCAAUDAAAA.Rokkgar:BAABNQAECn8fAAIHAAgKOhjTQQBuAgAHAAgKOhjTQQBuAgAAAA==.Rottontoe:BAAANQADCgEIAQAAAA==.',
Ru='Runa:BAABNQAECn8UAAMTAAkK3xTcVgBuAgATAAkK3xTcVgBuAgAbAAEKPQlmjgAxAAAAAA==.',
Sa='Sageara:BAAANQAECgQIBAAAAA==.Samirath:BAABNQAECn8aAAILAAgKJBfiVQAhAgALAAgKJBfiVQAhAgAAAA==.',
Sc='Scared:BAACNQAFFH8KAAILAAUK0QlKFABlAQALAAUK0QlKFABlAQA1AAQKfz0AAgsACQoAInkMAF8DAAsACQoAInkMAF8DAAAA.',
Se='Secarious:BAAANQAECgIIAgAAAA==.Sehnsucht:BAABNQAECn8eAAQkAAcKvxm5EAD9AQAkAAYKuR25EAD9AQAfAAcKQBUWLQCzAQAjAAIKHQvqVQBOAAAAAA==.',
Sh='Shakti:BAAANQAECgUIBQAAAA==.Shieldcow:BAAANQAECgIIBAABNQAFFAIIAgAeAAAAAA==.Shinpal:BAAANQAECgYICgAAAA==.Shmadu:BAABNQAECn81AAITAAoKMSYxAQD2AwATAAoKMSYxAQD2AwAAAA==.Shockakhan:BAAANQADCgcIBwAAAA==.Shockk:BAAANQAECgQICAAAAA==.Shockurbooty:BAAANQAECgQIBAAAAA==.',
So='Soola:BAAANQADCggICAABNQAFFAMIBwARAE0VAA==.Soulmonkey:BAAANQABCgQIBgAAAA==.',
Sp='Spoof:BAAANQADCgYICwAAAA==.',
St='Stabbymoose:BAAANQAECggIBwAAAA==.Stonedpriest:BAAANQAECggIEgAAAA==.Stymie:BAAANQAECgIIAgABNQAFFAQIDQANAGEVAA==.',
Su='Surrëal:BAABNQAECn8bAAIBAAgKLQVVXQAMAQABAAgKLQVVXQAMAQAAAA==.',
Sw='Sweetmask:BAAANQAECgYIDQAAAA==.',
Sy='Sybela:BAAANQAECgEIAgABNQAECgoKQgALABohAA==.',
Ta='Tahitian:BAAANQADCgIIAgAAAA==.Tahlreth:BAABNQAECn8+AAINAAoKNh8xBQDFAgANAAoKNh8xBQDFAgAAAA==.Tanidge:BAAANQADCgQIBAABNQAECgoKSAAHAEUgAA==.Tanidgemage:BAAANQADCgQIBAABNQAECgoKSAAHAEUgAA==.Tanidgetotem:BAABNQAECn9IAAMHAAoKRSCGFgBBAwAHAAoKRSCGFgBBAwAGAAIKLwb7yABcAAAAAA==.',
Te='Teias:BAACNQAFFH8GAAILAAMKsQ+nGwDRAAALAAMKsQ+nGwDRAAA1AAQKf0QAAwsACgqGHR8uAFcCAAsACgqGHR8uAFcCAAoABArOF9RAACkBAAAA.Tersus:BAAANQADCgEIAQAAAA==.',
Th='Theleena:BAAANQABCgIIAgAAAA==.',
Ti='Tirael:BAAANQAECgUIBgABNQAFFAMIBgALALEPAA==.',
To='Torvald:BAAANQAECggICAABNQAECggICAAeAAAAAA==.',
Tr='Tricko:BAABNQAECn8+AAITAAoK+SJ3DgACAwATAAoK+SJ3DgACAwAAAA==.Trickshots:BAAANQADCgMIAwABNQAECgoKQQAMADQdAA==.Trogar:BAAANQADCgQIBwAAAA==.Trollbi:BAAANQADCgQIAgAAAA==.Trollfacion:BAAANQADCgYIBgAAAA==.Trollskingx:BAABNQAECn8xAAIMAAoK+BfbSQALAgAMAAoK+BfbSQALAgAAAA==.Trollzy:BAABNQAECn8+AAMZAAoKJR/TCQBRAgAZAAkKrx7TCQBRAgAGAAMKpwIGDgFMAAAAAA==.Trunkmonkey:BAABNQAECn8pAAIDAAoKthbQOAD9AQADAAoKthbQOAD9AQAAAA==.Trunky:BAAANQAECgYIBgAAAA==.',
Ts='Tsaagan:BAACNQAFFH8GAAIDAAMKZRNHHACiAAADAAMKZRNHHACiAAA1AAQKfzUAAgMACgp5IYckAPICAAMACgp5IYckAPICAAAA.',
Um='Umbrosa:BAAANQADCgcIBwABNQAECgoKOwAcAMceAA==.',
Ur='Urthalos:BAAANQAECgcICQAAAA==.',
Va='Valica:BAAANQADCgUIBQAAAA==.Valiithria:BAAANQAECgQIBQAAAA==.Valkyruid:BAACNQAFFH8KAAIfAAMKgw4OCwDIAAAfAAMKgw4OCwDIAAA1AAQKfx8AAx8ACgqiHXoRAMcCAB8ACgqiHXoRAMcCACIAAQoAABO/ACIAAAAA.Varaxis:BAAANQABCgQIBgAAAA==.',
Ve='Veledreyssa:BAAANQAECgEIAgAAAA==.Veluthil:BAAANQAECgQICAABNQAECgoKOQAGAEYjAA==.',
Vu='Vulgan:BAAANQAECgYIBwAAAA==.',
Wa='Warriorchin:BAAANQAFFAIIAgABNQAFFAgIGQAJAD4fAA==.Waywatcher:BAAANQAECgQICgAAAA==.',
Wh='Whiilow:BAABNQAECn8iAAMGAAoKSBXNOwBwAgAGAAoKSBXNOwBwAgAHAAEKGAQlSwEoAAAAAA==.',
Wu='Wulgyn:BAAANQAECgYIBgAAAA==.Wullgan:BAABNQAECn8cAAILAAoKyBVRWQAWAgALAAoKyBVRWQAWAgAAAA==.',
Xe='Xencure:BAAANQAFFAMIBAAAAA==.Xerk:BAABNQAECn8dAAQkAAoKGhmSBwA5AgAkAAoKGhmSBwA5AgAjAAEKHBIQXgA3AAAfAAEKwA16aAAvAAAAAA==.',
Xy='Xyrna:BAABNQAECn8wAAInAAoKWhvTAgD7AgAnAAoKWhvTAgD7AgABNQAFFAMIBwARAE0VAA==.',
Ya='Yareli:BAABNQAECn8vAAICAAoK7AX9EwDZAAACAAoK7AX9EwDZAAAAAA==.',
Yo='Youngdoug:BAAANQAECgQIBwAAAA==.',
Yu='Yunara:BAAANQADCgUIBQAAAA==.',
Za='Zartman:BAABNQAECn8gAAMFAAoKPRS8RABGAQAWAAYKVhiEZQB6AQAFAAkKkQ+8RABGAQAAAA==.',
Ze='Zekröm:BAAANQAECggICAABNQAFFAMIBwAMAMUFAA==.Zeleck:BAABNQAECn8XAAMKAAcK1RBmLADDAQAKAAcK1RBmLADDAQALAAQK3gXl0QCwAAAAAA==.Zeno:BAACNQAFFH8eAAIQAAgK3xkWAQDBAgAQAAgK3xkWAQDBAgA1AAQKfzsAAhAACgo9Jl0NACYDABAACgo9Jl0NACYDAAAA.Zetetic:BAAANQADCggICAAAAA==.',
Zg='Zgystrdst:BAABNQAECn8fAAIaAAgKfBLbMQAYAgAaAAgKfBLbMQAYAgABNQAECggIHwAHADoYAA==.',
Zi='Zinbar:BAAANQAECggIDgAAAA==.',
Zo='Zoroark:BAAANQADCggIEAABNQAFFAMIBwAMAMUFAA==.',
Zu='Zuggzugg:BAAANQADCgYIBgAAAA==.Zune:BAABNQAECn8vAAMUAAoKHRgPFADxAQAUAAkK2xcPFADxAQASAAcKiRRlDwD/AAAAAA==.',
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
