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

local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Warlock-Demonology','DeathKnight-Blood','DeathKnight-Frost','Shaman-Restoration','Shaman-Elemental','Evoker-Devastation','Rogue-Subtlety','Priest-Shadow','Priest-Holy','Mage-Arcane','Mage-Frost','Warrior-Arms','Warrior-Fury','Paladin-Retribution','Paladin-Protection','Monk-Brewmaster','Hunter-BeastMastery','Monk-Windwalker','Monk-Mistweaver','DeathKnight-Unholy','Priest-Discipline','Warlock-Destruction','Shaman-Enhancement','Rogue-Assassination','Hunter-Marksmanship','Warrior-Protection','Paladin-Holy','Unknown-Unknown','Druid-Restoration','Warlock-Affliction','Rogue-Outlaw','Druid-Balance','Druid-Guardian','Druid-Feral','DemonHunter-Devourer','Hunter-Survival','Mage-Fire','Evoker-Preservation',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aaylasecura:BAABNQAECn9OAAMBAAoKkSK9CABxAwABAAoKjiK9CABxAwACAAcKzhlFCQC8AQAAAA==.',
Ab='Abelladanger:BAAANQAECgEIAQAAAA==.Abracadavar:BAAANQADCgEIAQABNQAFFAoKNgADAB0iAA==.Absinth:BAACNQAFFH8IAAIEAAQK+AUbGwCFAAAEAAQK+AUbGwCFAAA1AAQKfyEAAwQACgp0DARiAGoBAAQACgp0DARiAGoBAAUAAgqWAvqzACgAAAAA.',
Ai='Aidaric:BAAANQADCgUIBQAAAA==.Airfriend:BAABNQAECn9SAAMGAAoKcCCNCACCAwAGAAoKcCCNCACCAwAHAAUKZRoBnABgAQAAAA==.',
Al='Alder:BAABNQAECn8ZAAIIAAoKaAzfCgClAQAIAAoKaAzfCgClAQAAAA==.Alet:BAAANQADCgEIAQABNQAECgoKUgAGAHAgAA==.Alphard:BAABNQAECn9FAAIJAAoKESIbDAAPAwAJAAoKESIbDAAPAwAAAA==.',
An='Anelowyn:BAABNQAECn8/AAMKAAoKphRQFAADAgAKAAoKphRQFAADAgALAAkKvApQfQBJAQAAAA==.Angrychicken:BAAANQAECgYICQAAAA==.',
Ap='Apocal:BAACNQAFFH8KAAICAAcKyBcjAQCxAQACAAcKyBcjAQCxAQA1AAQKfzkAAgIACgoRJdwAAFUDAAIACgoRJdwAAFUDAAAA.',
Ar='Arete:BAAANQAECgcIEQAAAA==.Aridam:BAAANQAECgQIBAABNQAECgcIFwAKANUQAA==.Arii:BAAANQAECgUIBQAAAA==.Arthritis:BAAANQADCgUIBQAAAA==.',
As='Asmodyus:BAABNQAECn8wAAMMAAoKmg27YQDjAQAMAAoKmg27YQDjAQANAAQKAAazLACXAAAAAA==.Asmozaps:BAABNQAECn8+AAIHAAoKjxEaOQDbAQAHAAoKjxEaOQDbAQAAAA==.',
At='Ataraxya:BAAANQAECgQIBQAAAA==.',
Az='Aziel:BAABNQAECn8pAAMOAAoKcQ2KoADLAQAOAAoKcQ2KoADLAQAPAAEKcw3eMAA8AAAAAA==.Azmodeaus:BAAANQAECgEIAQAAAA==.',
Ba='Baraden:BAABNQAECn8eAAIHAAcKFRF9ewCwAQAHAAcKFRF9ewCwAQAAAA==.',
Be='Beefblood:BAAANQAECgMIBAAAAA==.',
Bh='Bhxdeath:BAAANQAECgEIAQAAAA==.Bhxdeeznutz:BAAANQAECgQIBAAAAA==.Bhxrafiq:BAAANQADCgYIBgAAAA==.',
Bi='Bigtimmehss:BAAANQAECgMIBQAAAA==.Bih:BAAANQADCgMIAwAAAA==.Bikerm:BAAANQAECgEIAgABNQAFFAgIHAACAP8eAA==.Billiards:BAAANQADCggICAABNQAECgoKRgAMAJcdAA==.Birgetta:BAAANQADCggICAABNQAECggIGwABAC0FAA==.',
Bl='Blitzkrieged:BAAANQAECggICAAAAA==.Blorne:BAAANQAECgQICQAAAA==.',
Bo='Bobodaklown:BAABNQAECn9FAAMQAAkKUSCjPADgAgAQAAkKUSCjPADgAgARAAgKQRGRHAB2AQAAAA==.Boneshade:BAAANQAECgMIAwAAAA==.Boombawks:BAAANQAECgEIAQAAAA==.Boomnbrew:BAACNQAFFH8HAAISAAQK9wKXBgCLAAASAAQK9wKXBgCLAAA1AAQKfysAAhIACgpGDv4RAMYBABIACgpGDv4RAMYBAAAA.Bownir:BAABNQAECn8vAAITAAoKDRYRPQBMAgATAAoKDRYRPQBMAgAAAA==.',
Br='Braelsong:BAAANQAECgEIAQAAAA==.Brewman:BAACNQAFFH8HAAIUAAMKJBDtCQDIAAAUAAMKJBDtCQDIAAA1AAQKfy0AAxQACgrYF2sfADQCABQACgrYF2sfADQCABUAAwooELg4AKgAAAAA.',
Bu='Bubonic:BAABNQAECn8XAAIWAAcKrwr+SwDHAAAWAAcKrwr+SwDHAAAAAA==.Buenasalud:BAABNQAECn8mAAILAAoKTBpJIQDDAgALAAoKTBpJIQDDAgAAAA==.',
Ca='Catopriest:BAABNQAECn8aAAIXAAoK4BkGAgDAAgAXAAoK4BkGAgDAAgABNQAFFAYICgAIAJwJAA==.Caylea:BAACNQAFFH8SAAIOAAcKBhTREwCOAQAOAAcKBhTREwCOAQA1AAQKfzsAAg4ACgofIpMnABsDAA4ACgofIpMnABsDAAAA.',
Ch='Chalis:BAABNQAECn8hAAMYAAgKPiHuFwCtAQAYAAQKfiTuFwCtAQADAAcKhx7TewBWAQAAAA==.Chimonkey:BAAANQAECgEIAwAAAA==.',
Cl='Clamsquirter:BAACNQAFFH8HAAMGAAQKXxBUGwCvAAAGAAMKWwtUGwCvAAAZAAIKoAwCCABRAAA1AAQKfyYABAYACgr5GjM8AG8CAAYACgr5GjM8AG8CABkAAwq1CXEwAGoAAAcAAQoeEaP7AC0AAAAA.Clanis:BAABNQAECn8lAAMJAAkKohR7MAAnAgAJAAkKuRN7MAAnAgAaAAUKnRQtPACVAAABNQAFFAgIEAAbAGsXAA==.',
Co='Coldhwip:BAABNQAECn87AAMNAAoK5hjNDwCrAQAMAAkK1RPxvwAEAgANAAoK4RbNDwCrAQAAAA==.',
Cr='Crtaker:BAAANQAECgcICgAAAA==.Crushfoot:BAAANQADCgUIBQAAAA==.Crysis:BAABNQAECn8+AAIcAAoKUR/2CADAAgAcAAoKUR/2CADAAgAAAA==.',
Cu='Cuahtemoc:BAAANQADCgYIDQAAAA==.',
Da='Dabss:BAAANQAECgEIAQAAAA==.Daelin:BAABNQAECn8+AAMQAAoK6SOpDwAnAwAQAAoK6SOpDwAnAwARAAgKqxWkIADfAQAAAA==.Dagda:BAAANQAECgUIBwAAAA==.Danye:BAAANQAECgMICQAAAA==.Darknasti:BAAANQAECgEIAQAAAA==.Darkscout:BAAANQADCgUJDwAAAA==.Dasyra:BAAANQAECgQIBAABNQAECgoKOQAGAEYjAA==.',
De='Decease:BAAANQAECgQIBAABNQAFFAYICQADAH8ZAA==.Delium:BAACNQAFFH8TAAMMAAYKUBPbEgDhAQAMAAYKUBPbEgDhAQANAAEK1xaXEwBHAAA1AAQKfzAAAgwACgofIg4pAD8DAAwACgofIg4pAD8DAAAA.Demonmommy:BAABNQAECn8XAAIDAAYKkQSZ8wDjAAADAAYKkQSZ8wDjAAAAAA==.Deäthrose:BAACNQAFFH8HAAIHAAQK/QJ+FgCqAAAHAAQK/QJ+FgCqAAA1AAQKfzYAAwcACgppFCRaABQCAAcACgppFCRaABQCAAYACAoICZeOAGQBAAAA.',
Di='Die:BAAANQAECgYICgAAAA==.Diegoo:BAAANQADCgUIBQAAAA==.Disc:BAAANQAECgYICQAAAA==.',
Do='Doadin:BAABNQAECn9FAAIdAAkK7BurGgDTAgAdAAkK7BurGgDTAgAAAA==.Dolphus:BAABNQAECn8fAAIPAAkKCxmYCAAIAgAPAAkKCxmYCAAIAgAAAA==.Dolust:BAAANQAECgQIBgABNQAECgkJRQAdAOwbAA==.Doominatrix:BAACNQAFFH8GAAIDAAMKgQfUJgCJAAADAAMKgQfUJgCJAAA1AAQKfzUAAgMACgofE0xpACACAAMACgofE0xpACACAAAA.Dotem:BAAANQAECgQIBwAAAA==.',
Dr='Draggum:BAAANQAECgEIAQABNQAECgkJLgAQABggAA==.Dragune:BAAANQAECgQIBgABNQAECggIIQAYAD4hAA==.Dreadlocky:BAABNQAECn87AAMYAAoKFBjUAgAgAgAYAAoKFBjUAgAgAgADAAUKFgsDBgHAAAAAAA==.Dreadmagey:BAAANQADCggICQABNQADCgYIDAAeAAAAAA==.Dreadraven:BAAANQADCgYIDAAAAA==.Dreven:BAAANQADCggIEAABNQAECgcIFwAKANUQAA==.Drip:BAAANQAECgIIAgAAAA==.Druidhams:BAACNQAFFH8IAAIfAAQKJBjWCAAnAQAfAAQKJBjWCAAnAQA1AAQKfygAAh8ACgr0H9ANAPMCAB8ACgr0H9ANAPMCAAAA.',
Du='Dunktars:BAACNQAFFH8GAAIOAAMK0BDNJQCHAAAOAAMK0BDNJQCHAAA1AAQKfy0AAg4ACgoMIOJDAL4CAA4ACgoMIOJDAL4CAAAA.Durpy:BAAANQADCgIIAwAAAA==.',
Eg='Egri:BAAANQAECgQIBgAAAA==.',
Ei='Eightball:BAAANQAECgYIDAABNQAECgoKRgAMAJcdAA==.',
El='Electro:BAAANQADCgYIBgABNQAECgQIBgAeAAAAAA==.Elisha:BAABNQAECn9mAAIQAAoKsxCPogDcAQAQAAoKsxCPogDcAQAAAA==.Eltara:BAAANQADCgEIAQAAAA==.',
Er='Erebostro:BAABNQAECn8+AAITAAoK4xs7IgCpAgATAAoK4xs7IgCpAgAAAA==.',
Fa='Facheritor:BAAANQADCgUIBAAAAA==.Fastlane:BAAANQAECgQIEAAAAA==.Fathercow:BAAANQAFFAIIAgAAAA==.Fathoms:BAAANQAECgUICwAAAA==.Fauxphoe:BAAANQADCgMIAwAAAA==.Fauxtotem:BAACNQAFFH8IAAIZAAMKxhCIAwDjAAAZAAMKxhCIAwDjAAA1AAQKfzkAAxkACgqiIYYFADIDABkACgqiIYYFADIDAAcAAgr8FCy2AIkAAAAA.',
Fe='Fender:BAAANQAECgEIAQAAAA==.Ferdinand:BAAANQAECgMIAwABNQAECgoKHAAEANAIAA==.Ferren:BAAANQABCgQIBAAAAA==.',
Fi='Fingies:BAABNQAECn9cAAQDAAoKVSTEIQB+AgADAAgKTSXEIQB+AgAYAAIKeyKEFgCeAAAgAAEK6SCQIABhAAAAAA==.Fistin:BAAANQAECgEIAQAAAA==.',
Fl='Flexyheals:BAAANQABCgQIBQAAAA==.Flush:BAAANQAECggICAAAAA==.',
Fr='Freakbeast:BAAANQAECgEIAQABNQAECgoKJwAhAFYjAA==.',
Fu='Furina:BAAANQAECgIIAgAAAA==.',
['Fë']='Fënn:BAAANQAECgQIBQAAAA==.',
['Fí']='Fíona:BAAANQABCgEIAQABNQAECgoKFAAQAA0aAA==.',
Ga='Galaxsea:BAABNQAECn8+AAIUAAoKSR2CDgBhAgAUAAoKSR2CDgBhAgAAAA==.Gale:BAAANQADCgYIBwABNQAECgoKNQAUAMIYAA==.Gamefreak:BAAANQAECgQIBQAAAA==.',
Ge='Gerthquake:BAABNQAECn8lAAMGAAoKJBBoSwDOAQAGAAoKJBBoSwDOAQAHAAEKzgUV+QAwAAAAAA==.',
Gh='Ghostfreak:BAABNQAECn8tAAIaAAkKQRduDgDUAQAaAAkKQRduDgDUAQAAAA==.',
Gi='Giren:BAAANQAECggIBwABNQAFFAgIHgAQAN8ZAA==.',
Gn='Gnomium:BAAANQADCggICAABNQAFFAQIEAANAGEVAA==.',
Go='Gobø:BAAANQAECgQIBAAAAA==.Gooby:BAABNQAECn8gAAIOAAoK7xOoTwD9AQAOAAoK7xOoTwD9AQAAAA==.',
Gr='Grindlemorph:BAAANQADCgYICAAAAA==.',
Ha='Hacks:BAABNQAECn8zAAMGAAoKow9KTADKAQAGAAoKow9KTADKAQAHAAUKtwWT0gDuAAAAAA==.Haranjer:BAABNQAECn8eAAIUAAgKJBuyGgBpAgAUAAgKJBuyGgBpAgAAAA==.',
He='Hefferhumper:BAABNQAECn8sAAQiAAoK6BCENgBHAQAjAAgKPxIMKgBHAQAiAAgKxQiENgBHAQAkAAEKAAAfWgAAAAAAAA==.',
Ho='Homlock:BAAANQADCgYICwABNQAFFAcIHQAMAMQgAA==.Homslam:BAABNQAECn8UAAMOAAkKZB3YigABAgAOAAgK6hrYigABAgAcAAQKKRwnJwAHAQABNQAFFAcIHQAMAMQgAA==.Homsorc:BAACNQAFFH8dAAMMAAcKxCAdCQA2AgAMAAYKQyAdCQA2AgANAAIKSyBJDABYAAA1AAQKfzgAAgwACgpvJosEANUDAAwACgpvJosEANUDAAAA.Homstab:BAACNQAFFH8JAAIJAAQKiBtBDQDKAAAJAAQKiBtBDQDKAAA1AAQKfy4AAwkACgqqIv8HADUDAAkACgqqIv8HADUDABoAAgr5JPd2ANYAAAE1AAUUBwgdAAwAxCAA.Homtard:BAAANQAFFAMIAwABNQAFFAcIHQAMAMQgAA==.Homtotem:BAAANQADCggICAABNQAFFAcIHQAMAMQgAA==.Homwiz:BAAANQAECgQIBwAAAA==.Hope:BAABNQAECn8tAAIdAAoK9RQRRgBOAgAdAAoK9RQRRgBOAgAAAA==.',
Ic='Iced:BAAANQADCgIIAgABNQAECgkJIQAKALQYAA==.Icons:BAAANQAECggICAAAAA==.Icyshaft:BAAANQADCgMIAwABNQAFFAgIEAAbAGsXAA==.',
Il='Illiandray:BAABNQAECn9HAAIYAAoKMB6MAQCXAgAYAAoKMB6MAQCXAgAAAA==.',
In='Insomniac:BAABNQAECn9HAAIlAAoKTCQKBQAMAwAlAAoKTCQKBQAMAwAAAA==.',
Is='Isklar:BAAANQADCgcIBwAAAA==.',
Ja='Jaegernaut:BAAANQADCgYIEgAAAA==.Jagernaut:BAAANQAECgYIDwAAAA==.Jake:BAABNQAECn8bAAIMAAkKcg2FkwBrAQAMAAkKcg2FkwBrAQAAAA==.Jangaballs:BAAANQAECgYIDwAAAA==.Jawndie:BAABNQAECn8rAAMVAAoK5xi+EwBAAgAVAAoK5xi+EwBAAgASAAEKAABbNQAiAAAAAA==.',
Ji='Jinzo:BAAANQAECgIIAgABNQAECgoKFAAQAA0aAA==.',
Jo='Joker:BAAANQAECgIIAgAAAA==.',
Jy='Jynn:BAABNQAECn8UAAImAAUKZQxwCwDpAAAmAAUKZQxwCwDpAAABNQAECgoKLQAXAAshAA==.',
Ka='Kaalg:BAAANQAECgEIAQAAAA==.Kaalgormi:BAAANQAECgEIAQAAAA==.Kammo:BAABNQAECn8zAAIFAAkKaiOzBQCFAwAFAAkKaiOzBQCFAwAAAA==.Kassa:BAAANQADCggIEQAAAA==.',
Ke='Keeah:BAABNQAECn8oAAIFAAoKtQcEQwB3AQAFAAoKtQcEQwB3AQAAAA==.Kestra:BAABNQAECn83AAIVAAoKgwdPIgByAQAVAAoKgwdPIgByAQAAAA==.',
Ki='Kittysprigg:BAABNQAECn8mAAMkAAoKrROwDgC9AQAkAAoKrROwDgC9AQAiAAQKgwh6igCrAAAAAA==.',
Kl='Klingnor:BAAANQADCgcJBwAAAA==.',
Kr='Kravensteak:BAACNQAFFH8QAAIbAAgKaxcCCgCjAQAbAAgKaxcCCgCjAQA1AAQKf0EAAhsACQr4IgoEABIDABsACQr4IgoEABIDAAAA.',
Ku='Kurty:BAAANQAECgEIAQAAAA==.',
Kw='Kwickin:BAABNQAECn8XAAMGAAcKQRF+fwCNAQAGAAYKKxN+fwCNAQAHAAUKqA0drgCYAAABNQAECgkJLgAQABggAA==.',
Ky='Kyreen:BAABNQAECn8yAAITAAoKmBL+TwAYAgATAAoKmBL+TwAYAgAAAA==.',
['Kä']='Kärl:BAAANQADCgYIBwABNQAECgoKPgAUAEkdAA==.',
Le='Leonelda:BAAANQADCgUIBQAAAA==.Leylines:BAACNQAFFH8JAAMMAAMKxQVsOACCAAAMAAIKaQVsOACCAAANAAEKfAYBFgA6AAA1AAQKfzkAAwwACgo8GC6SAFsCAAwACgpkFy6SAFsCAA0AAwrFDmAnAJAAAAAA.',
Lu='Luciferr:BAAANQAECgEIAQAAAA==.Lukafox:BAABNQAECn8ZAAMGAAkKgx+jRQBLAgAGAAkKgx+jRQBLAgAHAAEKAAA9VgEiAAAAAA==.Lunastarvale:BAABNQAECn82AAITAAoKgBQMTAAjAgATAAoKgBQMTAAjAgAAAA==.Lunereclipse:BAAANQAECgQJBAAAAA==.',
Ma='Macha:BAABNQAECn85AAMGAAoKRiNpBQCcAwAGAAoKRiNpBQCcAwAHAAYKkweGwAARAQAAAA==.Madith:BAAANQAECgQIDAAAAA==.Maintarget:BAABNQAECn8hAAIKAAkKtBgLGwBxAgAKAAkKtBgLGwBxAgAAAA==.Malefisico:BAABNQAECn8rAAIYAAoKdhcaAwAEAgAYAAoKdhcaAwAEAgAAAA==.Mardríft:BAABNQAECn8yAAIiAAoKHB4GGwDwAgAiAAoKHB4GGwDwAgAAAA==.Martyr:BAABNQAECn8yAAIIAAoKFg5dFAAJAgAIAAoKFg5dFAAJAgAAAA==.Mazga:BAABNQAECn87AAIGAAoKfRWLJgB/AgAGAAoKfRWLJgB/AgAAAA==.',
Mc='Mcflury:BAAANQADCgYICwAAAA==.',
Me='Melee:BAAANQADCgYIDAAAAA==.Meteos:BAAANQAECgEIAQAAAA==.Mezoti:BAAANQADCggICgAAAA==.',
Mi='Mick:BAAANQAECgYICwAAAA==.Miraclehwip:BAAANQADCggICQAAAA==.',
Mo='Moaxzy:BAAANQAECgEIAQAAAA==.Moji:BAABNQAECn84AAIVAAoKfxhpEAB5AgAVAAoKfxhpEAB5AgAAAA==.Monstermayi:BAABNQAECn8vAAMPAAkKlxUbCgAsAgAPAAkKlxUbCgAsAgAOAAIKvxATMwFuAAAAAA==.Mooknight:BAABNQAECn9BAAIEAAoK+g1zKwCaAQAEAAoK+g1zKwCaAQAAAA==.Moreina:BAAANQADCgUIBQABNQAFFAMICAALADsRAA==.Morgoth:BAABNQAECn8rAAQDAAoKsBsNQACSAgADAAgKehwNQACSAgAgAAUKZhjIFwDPAAAYAAEKAAC3dAA5AAAAAA==.Morteesha:BAAANQAECgIIAgABNQAECgoKKwAVAOcYAA==.',
Mu='Muggy:BAABNQAECn8yAAIaAAoK1xDKEgCVAQAaAAoK1xDKEgCVAQAAAA==.',
My='Myrothar:BAAANQAECgUIBwAAAA==.Mytastical:BAAANQAECgMIBwAAAA==.',
['Må']='Måzikeen:BAAANQAECgQICAABNQAECgoKOQAGAEYjAA==.',
['Mæ']='Mæve:BAAANQAECgYIBgABNQAECgoKOQAGAEYjAA==.',
Na='Najwah:BAABNQAECn8dAAMLAAoKjxs+FwAbAwALAAoKjxs+FwAbAwAKAAQKRxE0SwDqAAAAAA==.Namalis:BAACNQAFFH8JAAQDAAYKfxn4EwDyAAADAAQK+Rn4EwDyAAAYAAEKEhjTDgBPAAAgAAEKAADJFgAAAAA1AAQKfzIABAMACgpbI08eAAsDAAMACAp6I08eAAsDABgAAwrJFpk+AMgAACAAAQorJT0gAGMAAAAA.Nanielito:BAABNQAECn8bAAIMAAkKaxfagwB3AgAMAAkKaxfagwB3AgAAAA==.',
Ne='Necrotik:BAAANQADCgIIAgAAAA==.Neffer:BAAANQAECgQICAAAAA==.Nerra:BAAANQAECgEIAQAAAA==.',
Ni='Nineball:BAAANQADCgIIAgABNQAECgoKRgAMAJcdAA==.Ninjutsu:BAAANQAECgIIAgABNQAFFAYICQADAH8ZAA==.',
No='Nobunaka:BAAANQADCgYIBgAAAA==.Nonae:BAABNQAECn8iAAITAAoKVxdTQwA6AgATAAoKVxdTQwA6AgAAAA==.Norivari:BAAANQADCgYICwAAAA==.Nosali:BAABNQAECn83AAIgAAoKdxt0AwDBAgAgAAoKdxt0AwDBAgABNQAFFAMICAALADsRAA==.Nosliw:BAAANQAECggICAAAAA==.Noxilis:BAABNQAECn8jAAIEAAoKMAwhMgB0AQAEAAoKMAwhMgB0AQAAAA==.',
Nu='Nuggetz:BAAANQADCggICQAAAA==.',
['Nï']='Nïghtman:BAAANQAECgcIDgABNQAECgoKHQAkABoZAA==.',
Om='Omegá:BAABNQAECn8pAAMRAAkKNxHFJQCxAQARAAkKUg/FJQCxAQAQAAMKQhcgLwGRAAABNQAFFAQICAAEAPgFAA==.',
Oo='Oopsalldruid:BAAANQAECgEIAQABNQAECgkJLgAQABggAA==.',
Op='Optìmusprìme:BAABNQAECn9FAAMcAAoKEhoDCABRAgAcAAoKEhoDCABRAgAPAAEKAACtPQAAAAAAAA==.',
Or='Ordovic:BAAANQADCgUIBQAAAA==.',
Pa='Paladinchin:BAAANQAECggICwABNQAFFAgIGQAJAD4fAA==.Pandemic:BAABNQAECn9NAAITAAoKERrgKgCHAgATAAoKERrgKgCHAgAAAA==.Papa:BAABNQAECn9EAAQDAAoKPBpISADqAQADAAkKwBdISADqAQAgAAUKrxGNEQAzAQAYAAUKCxV2LQAWAQAAAA==.Pawfu:BAABNQAECn8yAAQUAAkKphnIHABSAgAUAAkKphnIHABSAgAVAAgKrwpoKwATAQASAAIKmAn6KgBoAAAAAA==.',
Pe='Penywize:BAABNQAECn8vAAMdAAoKgwuzXwCHAQAdAAkKXQmzXwCHAQAQAAgKmwTMDwEEAQAAAA==.',
Pi='Pilo:BAAANQADCgUICAAAAA==.',
Pl='Planeteer:BAAANQAECgUICAAAAA==.',
Po='Pockets:BAABNQAECn9GAAMMAAoKlx0EbwCgAgAMAAoKlx0EbwCgAgAnAAIK8A4yCAB1AAAAAA==.',
Pr='Prenus:BAAANQAECgUJCQAAAA==.',
Ps='Psychic:BAABNQAECn8tAAIXAAoKCyEDAQBgAwAXAAoKCyEDAQBgAwAAAA==.',
Pu='Purge:BAAANQAECgMIBQAAAA==.',
Qr='Qrazi:BAABNQAECn8aAAIHAAgKwBDoZADyAQAHAAgKwBDoZADyAQAAAA==.',
Qu='Quenthil:BAABNQAECn8XAAIJAAkK4QW7dAAqAQAJAAkK4QW7dAAqAQAAAA==.Quick:BAAANQAECgUIEAABNQAECgkJLgAQABggAA==.',
Ra='Ratha:BAACNQAFFH8JAAIRAAMKgRvDBAD2AAARAAMKgRvDBAD2AAA1AAQKf0EAAxEACgouI4gEAG8DABEACgouI4gEAG8DABAAAQoCB16JATQAAAAA.Ravincible:BAAANQAECgMIBQAAAA==.Razeal:BAABNQAECn8bAAIQAAoKZxDOcwDTAQAQAAoKZxDOcwDTAQAAAA==.Razkul:BAABNQAECn8VAAImAAkKQB/oAgCBAgAmAAkKQB/oAgCBAgAAAA==.',
Re='Remura:BAAANQAECgEIAQAAAA==.',
Ri='Ribbz:BAAANQAECgEIAQAAAA==.',
Ro='Roguechin:BAACNQAFFH8ZAAMJAAgKPh91BADlAQAJAAYKKB11BADlAQAaAAQKayO4CQBpAQA1AAQKf0kAAxoACgonJpIDAP4CABoACQrWJZIDAP4CAAkACgrDJZ4OAPoCAAAA.Rokkgar:BAABNQAECn8fAAIHAAgKOhjTQQBuAgAHAAgKOhjTQQBuAgAAAA==.Rottontoe:BAAANQADCgEIAQAAAA==.',
Ru='Runa:BAABNQAECn8UAAMTAAkK3xTcVgBuAgATAAkK3xTcVgBuAgAbAAEKPQlmjgAxAAAAAA==.',
Sa='Sageara:BAAANQAECgQIBAAAAA==.Samirath:BAABNQAECn8aAAILAAgKJBfiVQAhAgALAAgKJBfiVQAhAgAAAA==.',
Sc='Scared:BAACNQAFFH8KAAILAAUK0QlKFABlAQALAAUK0QlKFABlAQA1AAQKfz0AAgsACQoAInkMAF8DAAsACQoAInkMAF8DAAAA.',
Se='Secarious:BAAANQAECgIIAwAAAA==.Sehnsucht:BAABNQAECn8eAAQkAAcKvxm5EAD9AQAkAAYKuR25EAD9AQAfAAcKQBUWLQCzAQAjAAIKHQvqVQBOAAAAAA==.',
Sh='Shakti:BAAANQAECgUIBQAAAA==.Shieldcow:BAAANQAECgIIBAABNQAFFAIIAgAeAAAAAA==.Shinpal:BAAANQAECgYICgAAAA==.Shmadu:BAABNQAECn87AAITAAoKMSYxAQD2AwATAAoKMSYxAQD2AwAAAA==.Shockakhan:BAAANQADCgcIBwAAAA==.Shockk:BAAANQAECgQICwAAAA==.Shockurbooty:BAAANQAECgQIBAAAAA==.',
So='Soola:BAAANQADCggICAABNQAFFAMICQARAIEbAA==.Soulmonkey:BAAANQABCgQIBgAAAA==.',
Sp='Spoof:BAAANQADCgYICwAAAA==.',
St='Stabbymoose:BAAANQAECggIBwAAAA==.Stonedpriest:BAABNQAECn8XAAILAAkKShlUQwAVAgALAAkKShlUQwAVAgAAAA==.Stymie:BAAANQAECgIIAgABNQAFFAQIEAANAGEVAA==.',
Su='Surrëal:BAABNQAECn8bAAIBAAgKLQVVXQAMAQABAAgKLQVVXQAMAQAAAA==.Surtain:BAAANQAECgEIBAAAAA==.',
Sw='Sweetmask:BAAANQAECgYIDwAAAA==.',
Sy='Sybela:BAAANQAECgEIAgABNQAECgoKQgALABohAA==.',
Ta='Tahitian:BAAANQADCgIIAgAAAA==.Tahlreth:BAABNQAECn9IAAINAAoKAiBeAwDBAgANAAoKAiBeAwDBAgAAAA==.Tanidge:BAAANQADCgQIBAABNQAECgoKSAAHAEUgAA==.Tanidgemage:BAAANQADCgQIBAABNQAECgoKSAAHAEUgAA==.Tanidgetotem:BAABNQAECn9IAAMHAAoKRSCGFgBBAwAHAAoKRSCGFgBBAwAGAAIKLwak2ABXAAAAAA==.',
Te='Teias:BAACNQAFFH8IAAILAAMKOxFsHwDPAAALAAMKOxFsHwDPAAA1AAQKf0gAAwsACgqGHQI5AIQCAAsACgqGHQI5AIQCAAoABArOF9RAACkBAAAA.Tersus:BAAANQADCgEIAQAAAA==.',
Th='Theleena:BAAANQABCgIIAgAAAA==.',
Ti='Tirael:BAAANQAECgUIBgABNQAFFAMICAALADsRAA==.',
To='Toasteroven:BAAANQAFFAIIAgABNQAFFAIIAgAeAAAAAA==.Torvald:BAAANQAECggICAABNQAECggICAAeAAAAAA==.',
Tr='Tricko:BAABNQAECn9CAAITAAoKEiMdEAAJAwATAAoKEiMdEAAJAwAAAA==.Trickshots:BAAANQADCgMIAwABNQAECgoKRgAMAJcdAA==.Trogar:BAAANQADCgQIBwAAAA==.Trollbi:BAAANQAECgEIAQAAAA==.Trollfacion:BAAANQADCgYIBgAAAA==.Trollskingx:BAABNQAECn82AAIMAAoK+BeeUQANAgAMAAoK+BeeUQANAgAAAA==.Trollzy:BAABNQAECn9IAAMZAAoKjR/CBQDPAgAZAAoKjR/CBQDPAgAGAAMKpwIGDgFMAAAAAA==.Trunkmonkey:BAABNQAECn8pAAIDAAoKthZ2QQAAAgADAAoKthZ2QQAAAgAAAA==.Trunky:BAAANQAECgYIBgAAAA==.',
Ts='Tsaagan:BAACNQAFFH8IAAIDAAQK8BYxFADwAAADAAQK8BYxFADwAAA1AAQKfzkAAgMACgp5IYckAPICAAMACgp5IYckAPICAAAA.',
Um='Umbrosa:BAAANQADCgcIBwABNQAECgoKPgAcAFEfAA==.',
Ur='Urthalos:BAAANQAECgcICQAAAA==.',
Va='Valica:BAAANQADCgUIBQAAAA==.Valiithria:BAAANQAECgQIBQAAAA==.Valkyruid:BAACNQAFFH8KAAIfAAMKgw4gDQC4AAAfAAMKgw4gDQC4AAA1AAQKfx8AAx8ACgqiHXoRAMcCAB8ACgqiHXoRAMcCACIAAQoAABO/ACIAAAAA.Varaxis:BAAANQABCgQIBgAAAA==.',
Ve='Veledreyssa:BAAANQAECgEIBAAAAA==.Veluthil:BAAANQAECgQICAABNQAECgoKOQAGAEYjAA==.',
Vu='Vulgan:BAAANQAECgYIBwAAAA==.',
Wa='Warriorchin:BAAANQAFFAIIAgABNQAFFAgIGQAJAD4fAA==.Waywatcher:BAAANQAECgQICgAAAA==.',
Wh='Whiilow:BAABNQAECn8iAAMGAAoKSBXNOwBwAgAGAAoKSBXNOwBwAgAHAAEKGAQlSwEoAAAAAA==.',
Wu='Wulgyn:BAAANQAECggICQAAAA==.Wullgan:BAABNQAECn8cAAILAAoKyBVRWQAWAgALAAoKyBVRWQAWAgAAAA==.',
Xe='Xencure:BAABNQAFFH8GAAIoAAQKKx3qCwAXAQAoAAQKKx3qCwAXAQAAAA==.Xerk:BAABNQAECn8dAAQkAAoKGhmnCQAtAgAkAAoKGhmnCQAtAgAjAAEKHBItZwA3AAAfAAEKwA3xcQAvAAAAAA==.',
Xy='Xyrna:BAABNQAECn86AAImAAoK8hvTAgD7AgAmAAoK8hvTAgD7AgABNQAFFAMICQARAIEbAA==.',
Ya='Yareli:BAABNQAECn8vAAICAAoK7AWKGAApAQACAAoK7AWKGAApAQAAAA==.',
Yo='Youngdoug:BAAANQAECgQIBwAAAA==.',
Yu='Yunara:BAAANQADCgUIBQAAAA==.',
Za='Zartman:BAABNQAECn8mAAMFAAoKiBakRQBrAQAWAAYKVhiEZQB6AQAFAAkK3BGkRQBrAQAAAA==.',
Ze='Zekröm:BAAANQAECggICAABNQAFFAMICQAMAMUFAA==.Zeleck:BAABNQAECn8XAAMKAAcK1RBmLADDAQAKAAcK1RBmLADDAQALAAQK3gXl0QCwAAAAAA==.Zeno:BAACNQAFFH8eAAIQAAgK3xkWAQDBAgAQAAgK3xkWAQDBAgA1AAQKfzwAAhAACgo9JogRABwDABAACgo9JogRABwDAAAA.Zetetic:BAAANQADCggICAAAAA==.',
Zg='Zgystrdst:BAABNQAECn8fAAIaAAgKfBLbMQAYAgAaAAgKfBLbMQAYAgABNQAECggIHwAHADoYAA==.',
Zi='Zinbar:BAAANQAECggIEQAAAA==.',
Zo='Zoroark:BAAANQAECgEIAQABNQAFFAMICQAMAMUFAA==.',
Zu='Zuggzugg:BAAANQADCgYIBgAAAA==.Zune:BAABNQAECn81AAMUAAoKwhiZFQD8AQAUAAkKmBiZFQD8AQASAAcKiRQ3EQD8AAAAAA==.',
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
