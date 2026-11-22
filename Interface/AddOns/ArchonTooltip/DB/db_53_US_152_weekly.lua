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
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aaylasecura:BAABNQAECn9OAAMBAAoKkSK9CABxAwABAAoKjiK9CABxAwACAAcKzhliCgC5AQAAAA==.',
Ab='Abelladanger:BAAANQADCgQJBAAAAA==.Abracadavar:BAAANQADCgEIAQABNQAFFAoKPwADAIYiAA==.Abscynth:BAAANQAECgUIBQABNQAFFAQICAAEAPgFAA==.Absinth:BAACNQAFFH8IAAIEAAQK+AWEHgCAAAAEAAQK+AWEHgCAAAA1AAQKfyEAAwQACgp0DARiAGoBAAQACgp0DARiAGoBAAUAAgqWAmC9ACgAAAAA.',
Ai='Aidaric:BAAANQADCgUIBQAAAA==.Airfriend:BAABNQAECn9SAAMGAAoKcCAdCgB7AwAGAAoKcCAdCgB7AwAHAAUKZRoBnABgAQAAAA==.',
Al='Alder:BAABNQAECn8ZAAIIAAoKaAyqCwCkAQAIAAoKaAyqCwCkAQAAAA==.Alet:BAAANQADCgEIAQABNQAECgoKUgAGAHAgAA==.Alphard:BAABNQAECn9PAAIJAAoKXCJxCwAbAwAJAAoKXCJxCwAbAwAAAA==.',
An='Anelowyn:BAABNQAECn9JAAMKAAoKphTGFAASAgAKAAoKphTGFAASAgALAAoKrgrMXADMAQAAAA==.Angrychicken:BAAANQAECgYIBgAAAA==.',
Ap='Apocal:BAACNQAFFH8KAAICAAcKyBcjAQCxAQACAAcKyBcjAQCxAQA1AAQKfzkAAgIACgoRJfIAAFUDAAIACgoRJfIAAFUDAAAA.',
Ar='Arete:BAAANQAECggIEwAAAA==.Aridam:BAAANQAECgQIBAABNQAECgcIFwAKANUQAA==.Arii:BAAANQAECgcICQAAAA==.Arthritis:BAAANQADCgUIBQAAAA==.',
As='Asmodyus:BAABNQAECn8zAAMMAAoKQQ8tYQD0AQAMAAoKQQ8tYQD0AQANAAQKAAazLACXAAAAAA==.Asmozaps:BAABNQAECn8/AAIHAAoK+xFXPQDfAQAHAAoK+xFXPQDfAQAAAA==.',
At='Ataraxya:BAAANQAECgQIBAAAAA==.',
Az='Aziel:BAABNQAECn8vAAMOAAoKJhMHagDDAQAOAAoKJhMHagDDAQAPAAEKcw3eMAA8AAAAAA==.Azmodeaus:BAAANQADCgcIBwAAAA==.',
Ba='Baraden:BAABNQAECn8eAAIHAAcKFRF9ewCwAQAHAAcKFRF9ewCwAQAAAA==.',
Be='Beefblood:BAAANQAECgMIBAAAAA==.',
Bh='Bhxdeeznutz:BAAANQAECgQIBAAAAA==.Bhxrafiq:BAAANQADCgYIBgAAAA==.',
Bi='Bigtimmehss:BAAANQAECgMIBQAAAA==.Bih:BAAANQADCgMIAwAAAA==.Bikerm:BAAANQAECgEIAQABNQAFFAgIHAACAP8eAA==.Billiards:BAAANQADCggICAABNQAECgoKTAAMAKoeAA==.Birgetta:BAAANQADCggICAABNQAECggIGwABAC0FAA==.',
Bl='Blitzkrieged:BAAANQAECggICAAAAA==.Blorne:BAAANQAECgQICAAAAA==.',
Bo='Bobodaklown:BAABNQAECn9FAAMQAAkKUSCjPADgAgAQAAkKUSCjPADgAgARAAgKQRFyHwBzAQAAAA==.Boneshade:BAAANQAECgMIAwAAAA==.Boombawks:BAAANQADCgUICQAAAA==.Boomnbrew:BAACNQAFFH8HAAISAAQK9wJ3BwCDAAASAAQK9wJ3BwCDAAA1AAQKfzEAAhIACgpGDv4RAMYBABIACgpGDv4RAMYBAAAA.Bownir:BAABNQAECn84AAITAAoKYhecPQBcAgATAAoKYhecPQBcAgAAAA==.',
Br='Braelsong:BAAANQAECgEIAQAAAA==.Brewman:BAACNQAFFH8HAAIUAAMKJBAmCwDEAAAUAAMKJBAmCwDEAAA1AAQKfy0AAxQACgrYF2sfADQCABQACgrYF2sfADQCABUAAwooELg4AKgAAAAA.',
Bu='Bubonic:BAABNQAECn8XAAIWAAcKrwqjTwDGAAAWAAcKrwqjTwDGAAAAAA==.Buenasalud:BAABNQAECn8mAAILAAoKTBpFJgC4AgALAAoKTBpFJgC4AgAAAA==.',
Ca='Catopriest:BAABNQAECn8aAAIXAAoK4BlBAgC5AgAXAAoK4BlBAgC5AgABNQAFFAcICwAIAGYOAA==.Caylea:BAACNQAFFH8UAAIOAAgKNRPREwCOAQAOAAgKNRPREwCOAQA1AAQKfzsAAg4ACgofIpMnABsDAA4ACgofIpMnABsDAAAA.',
Ch='Chalis:BAABNQAECn8hAAMYAAgKPiHuFwCtAQAYAAQKfiTuFwCtAQADAAcKhx46hgBSAQAAAA==.Chimonkey:BAAANQABCgIIAgAAAA==.',
Cl='Clamsquirter:BAACNQAFFH8HAAMGAAQKXxAZHgCvAAAGAAMKWwsZHgCvAAAZAAIKoAwCCABRAAA1AAQKfywABAYACgr5GjM8AG8CAAYACgr5GjM8AG8CABkABArZCXEwAGoAAAcAAQoeEV4HAS0AAAAA.Clanis:BAABNQAECn8lAAMJAAkKohSfNQAlAgAJAAkKuROfNQAlAgAaAAUKnRQjXQBCAQABNQAFFAgIEAAbAGsXAA==.',
Co='Coldhwip:BAABNQAECn87AAMNAAoK5hjNDwCrAQAMAAkK1RPxvwAEAgANAAoK4RbNDwCrAQAAAA==.',
Cr='Crtaker:BAAANQAECgcICgAAAA==.Crushfoot:BAAANQADCgUIBQAAAA==.Crysis:BAABNQAECn8+AAIcAAoKUR/2CADAAgAcAAoKUR/2CADAAgAAAA==.',
Cu='Cuahtemoc:BAAANQADCgYIDQAAAA==.',
Da='Dabss:BAAANQAECgEIAQAAAA==.Daelin:BAABNQAECn9IAAMQAAoK0ySTCQBRAwAQAAoK0ySTCQBRAwARAAgKqxWkIADfAQAAAA==.Dagda:BAAANQAECgUIBAAAAA==.Danye:BAAANQAECgMIBgAAAA==.Darknasti:BAAANQAECgEIAQAAAA==.Darkscout:BAAANQADCgUJDwAAAA==.Dasyra:BAAANQAECgQIBAABNQAECgoKOQAGAEYjAA==.',
De='Decease:BAAANQAECgQIBAABNQAFFAYICQADAH8ZAA==.Delium:BAACNQAFFH8TAAMMAAYKUBPbEgDhAQAMAAYKUBPbEgDhAQANAAEK1xaIFQBHAAA1AAQKfzAAAgwACgofIg4pAD8DAAwACgofIg4pAD8DAAAA.Demonmommy:BAABNQAECn8aAAIDAAYKGgaZ8wDjAAADAAYKGgaZ8wDjAAAAAA==.Deäthrose:BAACNQAFFH8HAAIHAAQK/QKbGACqAAAHAAQK/QKbGACqAAA1AAQKfzwABAcACgptFCRaABQCAAcACgppFCRaABQCABkABgqsD3cYAIwBAAYACAoICZeOAGQBAAAA.',
Di='Die:BAAANQAECgYICgAAAA==.Diegoo:BAAANQADCgUIBQAAAA==.Disc:BAAANQAECgYIBwAAAA==.',
Do='Doadin:BAABNQAECn9FAAIdAAkK7Bs3HgDLAgAdAAkK7Bs3HgDLAgAAAA==.Dolphus:BAABNQAECn8fAAIPAAkKCxm+CABWAgAPAAkKCxm+CABWAgAAAA==.Dolust:BAAANQAECgQIBgABNQAECgkJRQAdAOwbAA==.Doominatrix:BAACNQAFFH8GAAIDAAMKgQfqKgCGAAADAAMKgQfqKgCGAAA1AAQKfzUAAgMACgofE0xpACACAAMACgofE0xpACACAAAA.Dotem:BAAANQAECgQIBgAAAA==.',
Dr='Draggum:BAAANQADCggIFQABNQAECgkJLgAQABggAA==.Dragune:BAAANQAECgQIBgABNQAECggIIQAYAD4hAA==.Dreadlocky:BAABNQAECn88AAMYAAoKFBgnAwAhAgAYAAoKFBgnAwAhAgADAAYK/QkDBgHAAAAAAA==.Dreadmagey:BAAANQADCggICQABNQADCgYIDAAeAAAAAA==.Dreadpally:BAAANQAECgcIBwABNQADCgYIDAAeAAAAAA==.Dreadraven:BAAANQADCgYIDAAAAA==.Dreven:BAAANQADCggIEAABNQAECgcIFwAKANUQAA==.Drip:BAAANQAECgIIAgAAAA==.Druidhams:BAACNQAFFH8IAAIfAAQKJBj8CQAlAQAfAAQKJBj8CQAlAQA1AAQKfy4AAh8ACgpIINANAPMCAB8ACgpIINANAPMCAAAA.',
Du='Dunktars:BAACNQAFFH8GAAIOAAMK0BDUKQCHAAAOAAMK0BDUKQCHAAA1AAQKfy0AAg4ACgoMIOJDAL4CAA4ACgoMIOJDAL4CAAAA.Durpy:BAAANQADCgIIAwAAAA==.',
Eg='Egri:BAAANQAECgQIBgAAAA==.',
Ei='Eightball:BAAANQAECgYICwABNQAECgoKTAAMAKoeAA==.',
El='Electro:BAAANQADCgYIBgABNQAECgQIBgAeAAAAAA==.Elisha:BAABNQAECn9oAAIQAAoK8RCPogDcAQAQAAoK8RCPogDcAQAAAA==.Eltara:BAAANQADCgEIAQAAAA==.',
Er='Erebostro:BAABNQAECn9IAAITAAoKlh3zIQC3AgATAAoKlh3zIQC3AgAAAA==.',
Fa='Facheritor:BAAANQADCgUIBAAAAA==.Fastlane:BAAANQAECgQIEAAAAA==.Fathercow:BAAANQAFFAIIAgAAAA==.Fathoms:BAAANQAECgUIDQAAAA==.Fauxphoe:BAAANQADCgMIAwAAAA==.Fauxtotem:BAACNQAFFH8JAAIZAAMKxhD2AwDfAAAZAAMKxhD2AwDfAAA1AAQKfz0AAxkACgopIoYFADIDABkACgopIoYFADIDAAcAAgr8FPrAAIgAAAAA.',
Fe='Fender:BAAANQAECgQIBQAAAA==.Ferdinand:BAAANQAECgMIAwABNQAECgoKIgAEAK0JAA==.Ferren:BAAANQABCgQIBAAAAA==.',
Fi='Fingies:BAABNQAECn9eAAQDAAoKVSSwJQB6AgADAAgKTSWwJQB6AgAgAAIKXx/0GAC7AAAYAAIKeyJQGACdAAAAAA==.',
Fl='Flexyheals:BAAANQABCgQIBQAAAA==.Flush:BAAANQAECggICAAAAA==.',
Fr='Freakbeast:BAAANQAECgEIAQABNQAECgoKJwAhAFYjAA==.',
Fu='Furina:BAAANQAECgIIAgAAAA==.',
['Fë']='Fënn:BAAANQAECgQIBQAAAA==.',
['Fí']='Fíona:BAAANQABCgEIAQABNQAECgoKFAAQAA0aAA==.',
Ga='Galaxsea:BAABNQAECn9HAAIUAAoKjx71DQB9AgAUAAoKjx71DQB9AgAAAA==.Gale:BAAANQADCgYIBwABNQAECgoKPgAUAIsbAA==.Gamefreak:BAAANQAECgQIBAAAAA==.',
Ge='Gerthquake:BAABNQAECn8vAAMGAAoKfxbzIQCwAgAGAAoKfxbzIQCwAgAHAAEKzgWjBAEwAAAAAA==.',
Gh='Ghostfreak:BAABNQAECn8tAAIaAAkKQReCDwDQAQAaAAkKQReCDwDQAQAAAA==.',
Gi='Giren:BAAANQAECggIBwABNQAFFAgIHgAQAN8ZAA==.',
Gn='Gnomium:BAAANQADCggICAABNQAFFAQIEgANAGEVAA==.',
Go='Gobø:BAAANQAECgUIBQAAAA==.Gooby:BAABNQAECn8gAAIOAAoK7xOPVgD6AQAOAAoK7xOPVgD6AQAAAA==.',
Gr='Grindlemorph:BAAANQADCgYICAAAAA==.',
Ha='Hacks:BAABNQAECn81AAMGAAoKow9lUwDFAQAGAAoKow9lUwDFAQAHAAUKtwWT0gDuAAAAAA==.Haranjer:BAABNQAECn8eAAIUAAgKJBuyGgBpAgAUAAgKJBuyGgBpAgAAAA==.',
He='Hefferhumper:BAABNQAECn8sAAQiAAoK6BCTOgBGAQAjAAgKPxIMKgBHAQAiAAgKxQiTOgBGAQAkAAEKAAAVYQAAAAAAAA==.',
Ho='Homlock:BAAANQADCgYICwABNQAFFAcIHQAMAMQgAA==.Homslam:BAABNQAECn8UAAMOAAkKZB3YigABAgAOAAgK6hrYigABAgAcAAQKKRwnJwAHAQABNQAFFAcIHQAMAMQgAA==.Homsorc:BAACNQAFFH8dAAMMAAcKxCAdCQA2AgAMAAYKQyAdCQA2AgANAAIKSyC/DQBYAAA1AAQKfzgAAgwACgpvJosEANUDAAwACgpvJosEANUDAAAA.Homstab:BAACNQAFFH8NAAIJAAUKfx98DgAhAQAJAAUKfx98DgAhAQA1AAQKfy8AAwkACgqqIqwIADQDAAkACgqqIqwIADQDABoAAgr5JPd2ANYAAAE1AAUUBwgdAAwAxCAA.Homtard:BAAANQAFFAQIBAABNQAFFAcIHQAMAMQgAA==.Homtotem:BAAANQADCggICAABNQAFFAcIHQAMAMQgAA==.Homwiz:BAAANQAECgQIBgAAAA==.Hope:BAABNQAECn8tAAIdAAoK9RQRRgBOAgAdAAoK9RQRRgBOAgAAAA==.',
Ic='Iced:BAAANQADCgIIAgABNQAECgkJIQAKALQYAA==.Icons:BAAANQAECggICAAAAA==.Icyshaft:BAAANQADCgMIAwABNQAFFAgIEAAbAGsXAA==.',
Il='Illiandray:BAABNQAECn9LAAIYAAoKXR6yAQCZAgAYAAoKXR6yAQCZAgAAAA==.',
In='Insomniac:BAABNQAECn9RAAMlAAoKcSQjAwA/AwAlAAoKcSQjAwA/AwABAAEKAAAYngAAAAAAAA==.',
Is='Isklar:BAAANQADCgcIBwAAAA==.',
Ja='Jaegernaut:BAAANQADCgYIEgAAAA==.Jagernaut:BAAANQAECgYICwAAAA==.Jake:BAABNQAECn8bAAIMAAkKcg38nABrAQAMAAkKcg38nABrAQAAAA==.Jangaballs:BAAANQAECgYIDQAAAA==.Jawndie:BAABNQAECn8rAAMVAAoK5xi+EwBAAgAVAAoK5xi+EwBAAgASAAEKAABbNQAiAAAAAA==.',
Ji='Jinzo:BAAANQAECgMIAgABNQAECgoKFAAQAA0aAA==.',
Jo='Joker:BAAANQAECgIIAgAAAA==.',
Jy='Jynn:BAABNQAECn8UAAImAAUKZQxODADpAAAmAAUKZQxODADpAAABNQAECgoKLQAXAAshAA==.',
Ka='Kaalg:BAAANQADCgYIBgAAAA==.Kaalgormi:BAAANQABCgcICQAAAA==.Kammo:BAABNQAECn8zAAIFAAkKaiOzBQCFAwAFAAkKaiOzBQCFAwAAAA==.Kassa:BAAANQADCggIEQAAAA==.',
Ke='Keeah:BAABNQAECn8vAAIFAAoKUQrtPwCcAQAFAAoKUQrtPwCcAQAAAA==.Kestra:BAABNQAECn83AAIVAAoKgwdPIgByAQAVAAoKgwdPIgByAQAAAA==.',
Ki='Kittysprigg:BAABNQAECn8mAAMkAAoKrRO/EAC7AQAkAAoKrRO/EAC7AQAiAAQKgwh6igCrAAAAAA==.',
Kl='Klingnor:BAAANQADCgcJBwAAAA==.',
Kr='Kravensteak:BAACNQAFFH8QAAIbAAgKaxcCCgCjAQAbAAgKaxcCCgCjAQA1AAQKf0EAAhsACQr4Io4EAAwDABsACQr4Io4EAAwDAAAA.',
Ku='Kurty:BAAANQADCgUIBQAAAA==.',
Kw='Kwickin:BAABNQAECn8XAAMGAAcKQRF+fwCNAQAGAAYKKxN+fwCNAQAHAAUKqA10uACYAAABNQAECgkJLgAQABggAA==.',
Ky='Kyreen:BAABNQAECn86AAITAAoKIxTUSAA/AgATAAoKIxTUSAA/AgAAAA==.',
['Kä']='Kärl:BAAANQADCgYIBwABNQAECgoKRwAUAI8eAA==.',
Le='Leonelda:BAAANQADCgUIBQAAAA==.Leylines:BAACNQAFFH8KAAMNAAMKMwmKCQCJAAANAAIK1gyKCQCJAAAMAAIKaQXIPQB9AAA1AAQKfz0AAw0ACgrLGWIVAEEBAAwACgpkFy6SAFsCAA0ABAorGmIVAEEBAAAA.',
Lu='Luciferr:BAAANQAECgEIAQAAAA==.Lukafox:BAABNQAECn8ZAAMGAAkKgx+jRQBLAgAGAAkKgx+jRQBLAgAHAAEKAAA9VgEiAAAAAA==.Lunastarvale:BAABNQAECn86AAITAAoKOhUzTgAyAgATAAoKOhUzTgAyAgAAAA==.Lunereclipse:BAAANQAECgQJBAAAAA==.',
Ma='Macha:BAABNQAECn85AAMGAAoKRiNpBQCcAwAGAAoKRiNpBQCcAwAHAAYKkweGwAARAQAAAA==.Madith:BAAANQAECgQICgAAAA==.Maintarget:BAABNQAECn8hAAIKAAkKtBgLGwBxAgAKAAkKtBgLGwBxAgAAAA==.Malefisico:BAABNQAECn81AAIYAAoKOBjMAgA3AgAYAAoKOBjMAgA3AgAAAA==.Mardríft:BAABNQAECn8yAAIiAAoKHB4GGwDwAgAiAAoKHB4GGwDwAgAAAA==.Marero:BAAANQADCgYICgAAAA==.Martyr:BAABNQAECn8yAAIIAAoKFg5dFAAJAgAIAAoKFg5dFAAJAgAAAA==.Mazga:BAABNQAECn8/AAIGAAoK+hdkIgCuAgAGAAoK+hdkIgCuAgAAAA==.',
Mc='Mcflury:BAAANQADCgYICwAAAA==.',
Me='Melee:BAAANQADCgYIDAAAAA==.Meteos:BAAANQABCgMIBAAAAA==.Mezoti:BAAANQADCggICgAAAA==.',
Mi='Mick:BAAANQAECgYICQAAAA==.Miraclehwip:BAAANQADCggICQAAAA==.',
Mo='Moaxzy:BAAANQAECgEIAQAAAA==.Moji:BAABNQAECn84AAIVAAoKfxhpEAB5AgAVAAoKfxhpEAB5AgAAAA==.Molliebear:BAAANQAECggICAABNQAFFAUICQAKAP8KAA==.Monstermayi:BAABNQAECn81AAMPAAkKtBYbCgAsAgAPAAkKtBYbCgAsAgAOAAIKvxATMwFuAAAAAA==.Mooknight:BAABNQAECn9LAAIEAAoKkg7RLQCbAQAEAAoKkg7RLQCbAQAAAA==.Moreina:BAAANQADCgUIBQABNQAFFAMICQALADsRAA==.Morgoth:BAABNQAECn8rAAQDAAoKsBsNQACSAgADAAgKehwNQACSAgAgAAUKZhjIFwDPAAAYAAEKAAC3dAA5AAAAAA==.Morteesha:BAAANQAECgIIAQABNQAECgoKKwAVAOcYAA==.',
Mu='Muggy:BAABNQAECn8yAAIaAAoK1xAKFACSAQAaAAoK1xAKFACSAQAAAA==.',
My='Myrothar:BAAANQAECgYIBgAAAA==.Mytastical:BAAANQAECgMIBwAAAA==.',
['Må']='Måzikeen:BAAANQAECgQIBAABNQAECgoKOQAGAEYjAA==.',
['Mæ']='Mæve:BAAANQAECgYIBgABNQAECgoKOQAGAEYjAA==.',
Na='Najwah:BAABNQAECn8dAAMLAAoKjxs+FwAbAwALAAoKjxs+FwAbAwAKAAQKRxE0SwDqAAAAAA==.Namalis:BAACNQAFFH8JAAQDAAYKfxm3FwDqAAADAAQK+Rm3FwDqAAAYAAEKEhg9EABOAAAgAAEKAABuGwAAAAA1AAQKfzIABAMACgpbI08eAAsDAAMACAp6I08eAAsDABgAAwrJFpk+AMgAACAAAQorJS8jAGIAAAAA.Nanielito:BAABNQAECn8bAAIMAAkKaxfagwB3AgAMAAkKaxfagwB3AgAAAA==.',
Ne='Necrotik:BAAANQADCgIIAgAAAA==.Neffer:BAAANQAECgQIBwAAAA==.Nerra:BAAANQADCggIDgAAAA==.',
Ni='Nineball:BAAANQADCgIIAgABNQAECgoKTAAMAKoeAA==.Ninjutsu:BAAANQAECgIIAQABNQAFFAYICQADAH8ZAA==.',
No='Nobunaka:BAAANQADCgYIBgAAAA==.Nonae:BAABNQAECn8lAAITAAoKdhfHSAA/AgATAAoKdhfHSAA/AgAAAA==.Norivari:BAAANQADCgYICwAAAA==.Nosali:BAABNQAECn83AAIgAAoKdxt0AwDBAgAgAAoKdxt0AwDBAgABNQAFFAMICQALADsRAA==.Nosliw:BAAANQAECggICAAAAA==.Noxilis:BAABNQAECn8jAAIEAAoKMAx7NgBsAQAEAAoKMAx7NgBsAQAAAA==.',
Nu='Nuggetz:BAAANQADCggICQAAAA==.',
['Nï']='Nïghtman:BAAANQAECgcIDQABNQAECgoKHQAkABoZAA==.',
Om='Omegá:BAABNQAECn8qAAMRAAkKuRLFJQCxAQARAAkK1BDFJQCxAQAQAAMKQhcoPwGQAAABNQAFFAQICAAEAPgFAA==.',
Oo='Oopsalldruid:BAAANQAECgEIAQABNQAECgkJLgAQABggAA==.',
Op='Optìmusprìme:BAABNQAECn9PAAMcAAoKNB0WBgClAgAcAAoKNB0WBgClAgAPAAEKAAAdQwAAAAAAAA==.',
Or='Ordovic:BAAANQADCgUIBQAAAA==.',
Pa='Paladinchin:BAAANQAECggICwABNQAFFAkJGwAJAHUdAA==.Pandemic:BAABNQAECn9VAAITAAoKPBuSKACdAgATAAoKPBuSKACdAgAAAA==.Papa:BAABNQAECn9EAAQDAAoKPBosUADkAQADAAkKwBcsUADkAQAgAAUKrxGNEQAzAQAYAAUKCxV2LQAWAQAAAA==.Pawfu:BAABNQAECn8yAAQUAAkKphnIHABSAgAUAAkKphnIHABSAgAVAAgKrwpoKwATAQASAAIKmAn6KgBoAAAAAA==.',
Pe='Penywize:BAABNQAECn8vAAMdAAoKgwsKaQB7AQAdAAkKXQkKaQB7AQAQAAgKmwTMDwEEAQAAAA==.',
Pi='Pilo:BAAANQADCgUICAAAAA==.',
Pl='Planeteer:BAAANQAECgUICAAAAA==.',
Po='Pockets:BAABNQAECn9MAAMMAAoKqh6JOABkAgAMAAoKqh6JOABkAgAnAAIK8A4mCQB1AAAAAA==.',
Pr='Prenus:BAAANQAECgUJBwAAAA==.',
Ps='Psychic:BAABNQAECn8tAAIXAAoKCyEDAQBgAwAXAAoKCyEDAQBgAwAAAA==.',
Pu='Purge:BAAANQAECgMIBAAAAA==.',
Qr='Qrazi:BAABNQAECn8aAAIHAAgKwBDoZADyAQAHAAgKwBDoZADyAQAAAA==.',
Qu='Quenthil:BAABNQAECn8XAAIJAAkK4QVnfwAqAQAJAAkK4QVnfwAqAQAAAA==.Quick:BAAANQAECgUIDgABNQAECgkJLgAQABggAA==.',
Ra='Ratha:BAACNQAFFH8KAAIRAAMKgRt0BQDzAAARAAMKgRt0BQDzAAA1AAQKf0MAAxEACgqtI4gEAG8DABEACgqtI4gEAG8DABAAAQoCB1ibATMAAAAA.Ravincible:BAAANQAECgMIAwAAAA==.Razeal:BAABNQAECn8bAAIQAAoKZxCFfwDOAQAQAAoKZxCFfwDOAQAAAA==.Razkul:BAABNQAECn8VAAImAAkKQB9HAwB9AgAmAAkKQB9HAwB9AgAAAA==.',
Ri='Ribbz:BAAANQADCgYICwAAAA==.',
Ro='Roguechin:BAACNQAFFH8bAAMJAAkKdR11BADlAQAJAAYKKB11BADlAQAaAAUK3B24CQBpAQA1AAQKf0kAAxoACgonJuYDAPoCABoACQrWJeYDAPoCAAkACgrDJZcPAPoCAAAA.Rokkgar:BAABNQAECn8fAAIHAAgKOhjTQQBuAgAHAAgKOhjTQQBuAgAAAA==.Rottontoe:BAAANQADCgEIAQAAAA==.',
Ru='Runa:BAABNQAECn8UAAMTAAkK3xTcVgBuAgATAAkK3xTcVgBuAgAbAAEKPQlmjgAxAAAAAA==.',
Sa='Sageara:BAAANQAECgQIBAAAAA==.Samirath:BAABNQAECn8aAAILAAgKJBfiVQAhAgALAAgKJBfiVQAhAgAAAA==.',
Sc='Scared:BAACNQAFFH8KAAILAAUK0QlKFABlAQALAAUK0QlKFABlAQA1AAQKfz0AAgsACQoAInkMAF8DAAsACQoAInkMAF8DAAAA.',
Se='Secarious:BAAANQAECgIIAgAAAA==.Sehnsucht:BAABNQAECn8eAAQkAAcKvxm5EAD9AQAkAAYKuR25EAD9AQAfAAcKQBUWLQCzAQAjAAIKHQvqVQBOAAAAAA==.',
Sh='Shakti:BAAANQAECgUIBQAAAA==.Shieldcow:BAAANQAECgIIBAABNQAFFAIIAgAeAAAAAA==.Shinpal:BAAANQAECgYICgAAAA==.Shmadu:BAABNQAECn87AAITAAoKMSYxAQD2AwATAAoKMSYxAQD2AwAAAA==.Shockakhan:BAAANQADCgcIBwAAAA==.Shockk:BAAANQAECgQICAAAAA==.Shockurbooty:BAAANQAECgQIBAAAAA==.',
So='Soola:BAAANQADCggICAABNQAFFAMICgARAIEbAA==.Soulmonkey:BAAANQABCgQIBgAAAA==.',
Sp='Spoof:BAAANQADCgYICwAAAA==.',
St='Stabbymoose:BAAANQAECggIBwAAAA==.Stonedpriest:BAAANQAECggIEwAAAA==.Stymie:BAAANQAECgIIAgABNQAFFAQIEgANAGEVAA==.',
Su='Surrëal:BAABNQAECn8bAAIBAAgKLQVVXQAMAQABAAgKLQVVXQAMAQAAAA==.',
Sw='Sweetmask:BAAANQAECgYIDQAAAA==.',
Sy='Sybela:BAAANQAECgEIAgABNQAECgoKQgALABohAA==.',
Ta='Tahitian:BAAANQADCgIIAgAAAA==.Tahlreth:BAABNQAECn9SAAINAAoKRCDlAgDhAgANAAoKRCDlAgDhAgAAAA==.Tanidge:BAAANQADCgQIBAABNQAECgoKSAAHAEUgAA==.Tanidgemage:BAAANQADCgQIBAABNQAECgoKSAAHAEUgAA==.Tanidgetotem:BAABNQAECn9IAAMHAAoKRSCGFgBBAwAHAAoKRSCGFgBBAwAGAAIKLwZP4QBXAAAAAA==.',
Te='Teias:BAACNQAFFH8JAAILAAMKOxG7IwDGAAALAAMKOxG7IwDGAAA1AAQKf0wAAwsACgpnHgI5AIQCAAsACgpnHgI5AIQCAAoABArOF9RAACkBAAAA.Tersus:BAAANQADCgEIAQAAAA==.',
Th='Theleena:BAAANQABCgIIAgAAAA==.',
Ti='Tirael:BAAANQAECgUIBgABNQAFFAMICQALADsRAA==.',
To='Toasteroven:BAAANQAFFAIIAgABNQAFFAIIAgAeAAAAAA==.Torvald:BAAANQAECggICAABNQAECggICAAeAAAAAA==.',
Tr='Tricko:BAABNQAECn9GAAITAAoKnyMcEAASAwATAAoKnyMcEAASAwAAAA==.Trickshots:BAAANQADCgMIAwABNQAECgoKTAAMAKoeAA==.Trogar:BAAANQADCgQIBwAAAA==.Trollbi:BAAANQADCgQIAgAAAA==.Trollfacion:BAAANQADCgYIBgAAAA==.Trollskingx:BAABNQAECn88AAIMAAoK+BfnUgAZAgAMAAoK+BfnUgAZAgAAAA==.Trollzy:BAABNQAECn9SAAMZAAoKDyHABAD1AgAZAAoKDyHABAD1AgAGAAMKpwIGDgFMAAAAAA==.Trunkmonkey:BAABNQAECn8pAAIDAAoKthb1TQBqAgADAAoKthb1TQBqAgAAAA==.Trunky:BAAANQAECgYIBgAAAA==.',
Ts='Tsaagan:BAACNQAFFH8IAAIDAAQK8BZ9FwDsAAADAAQK8BZ9FwDsAAA1AAQKfz8AAgMACgqYIockAPICAAMACgqYIockAPICAAAA.',
Um='Umbrosa:BAAANQADCgcIBwABNQAECgoKPgAcAFEfAA==.',
Ur='Urthalos:BAAANQAECggIDAAAAA==.',
Va='Valica:BAAANQADCgUIBQAAAA==.Valiithria:BAAANQAECgQIBQAAAA==.Valkyruid:BAACNQAFFH8LAAIfAAQKxQ9lCwADAQAfAAQKxQ9lCwADAQA1AAQKfx8AAx8ACgqiHXoRAMcCAB8ACgqiHXoRAMcCACIAAQoAABO/ACIAAAAA.Varaxis:BAAANQABCgQIBgAAAA==.',
Ve='Veledreyssa:BAAANQAECgEIAgAAAA==.Veluthil:BAAANQAECgQICAABNQAECgoKOQAGAEYjAA==.',
Vu='Vulgan:BAAANQAECgUIBwAAAA==.',
Wa='Warriorchin:BAAANQAFFAIIAgABNQAFFAkJGwAJAHUdAA==.Waywatcher:BAAANQAECgQICgAAAA==.',
Wh='Whiilow:BAABNQAECn8iAAMGAAoKSBXNOwBwAgAGAAoKSBXNOwBwAgAHAAEKGAQlSwEoAAAAAA==.',
Wu='Wulgyn:BAAANQAECggICQAAAA==.Wullgan:BAABNQAECn8cAAILAAoKyBVRWQAWAgALAAoKyBVRWQAWAgAAAA==.',
Xe='Xencure:BAABNQAFFH8GAAIoAAQKKx1nDQAVAQAoAAQKKx1nDQAVAQAAAA==.Xerk:BAABNQAECn8dAAQkAAoKGhkGCwAoAgAkAAoKGhkGCwAoAgAjAAEKHBIkbQA3AAAfAAEKwA0zeAAvAAAAAA==.',
Xy='Xyrna:BAABNQAECn88AAImAAoKdxzTAgD7AgAmAAoKdxzTAgD7AgABNQAFFAMICgARAIEbAA==.',
Ya='Yareli:BAABNQAECn8vAAICAAoK7AWKGAApAQACAAoK7AWKGAApAQAAAA==.',
Yo='Youngdoug:BAAANQAECgQIBwAAAA==.',
Yu='Yunara:BAAANQADCgUIBQAAAA==.',
Za='Zartman:BAABNQAECn8mAAMFAAoKiBbXSwBoAQAWAAYKVhiEZQB6AQAFAAkK3BHXSwBoAQAAAA==.',
Ze='Zekröm:BAAANQAECgcICAABNQAFFAMICgANADMJAA==.Zeleck:BAABNQAECn8XAAMKAAcK1RBmLADDAQAKAAcK1RBmLADDAQALAAQK3gXl0QCwAAAAAA==.Zeno:BAACNQAFFH8eAAIQAAgK3xkWAQDBAgAQAAgK3xkWAQDBAgA1AAQKfzwAAhAACgo9JhUUABQDABAACgo9JhUUABQDAAAA.Zetetic:BAAANQADCggICAAAAA==.',
Zg='Zgystrdst:BAABNQAECn8fAAIaAAgKfBLbMQAYAgAaAAgKfBLbMQAYAgABNQAECggIHwAHADoYAA==.',
Zi='Zinbar:BAAANQAECgcIDgAAAA==.',
Zo='Zoroark:BAAANQADCggIEAABNQAFFAMICgANADMJAA==.',
Zu='Zuggzugg:BAAANQADCgYIBgAAAA==.Zune:BAABNQAECn8+AAMUAAoKixu+DQCBAgAUAAoKIxu+DQCBAgASAAcKiRSKEgD8AAAAAA==.',
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
