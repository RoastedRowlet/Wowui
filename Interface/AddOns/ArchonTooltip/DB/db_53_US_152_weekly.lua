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

local lookup = {'DemonHunter-Havoc','Warlock-Demonology','DeathKnight-Blood','DeathKnight-Frost','Shaman-Restoration','Shaman-Elemental','Rogue-Subtlety','Priest-Shadow','Priest-Holy','DemonHunter-Vengeance','Mage-Arcane','Mage-Frost','Warrior-Arms','Warrior-Fury','Paladin-Retribution','Paladin-Protection','Monk-Brewmaster','Hunter-BeastMastery','Monk-Windwalker','Monk-Mistweaver','DeathKnight-Unholy','Warlock-Destruction','Shaman-Enhancement','Rogue-Assassination','Hunter-Marksmanship','Warrior-Protection','Paladin-Holy','Unknown-Unknown','Druid-Restoration','Warlock-Affliction','Rogue-Outlaw','Druid-Balance','Druid-Guardian','DemonHunter-Devourer','Priest-Discipline','Druid-Feral','Evoker-Devastation','Hunter-Survival',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aaylasecura:BAABNQAECn86AAIBAAoKjyC9CABxAwABAAoKjyC9CABxAwAAAA==.',
Ab='Abelladanger:BAAANQADCgQJBAAAAA==.Abracadavar:BAAANQADCgEIAQABNQAFFAkJJQACANAcAA==.Absinth:BAABNQAECn8fAAMDAAoKdAwEYgBqAQADAAoKdAwEYgBqAQAEAAIKlgKfuAAmAAAAAA==.',
Ai='Aidaric:BAAANQADCgUIBQAAAA==.Airfriend:BAABNQAECn8+AAMFAAoK5xLqSgA3AgAFAAoK5xLqSgA3AgAGAAUKZRoBnABgAQAAAA==.',
Al='Alder:BAAANQAECgUIDwAAAA==.Alphard:BAABNQAECn81AAIHAAoKTSEcDADWAgAHAAoKTSEcDADWAgAAAA==.',
An='Anelowyn:BAABNQAECn81AAMIAAoKRhTbDQD7AQAIAAoKRhTbDQD7AQAJAAcKtwbNmABLAQAAAA==.Angrychicken:BAAANQAECgYIBgAAAA==.',
Ap='Apocal:BAACNQAFFH8KAAIKAAcKyBcjAQCxAQAKAAcKyBcjAQCxAQA1AAQKfy8AAgoACQr5I+0BAHoDAAoACQr5I+0BAHoDAAAA.',
Ar='Arete:BAAANQAECgcICgAAAA==.Aridam:BAAANQAECgQIBAABNQAECgcIFwAIANUQAA==.Arthritis:BAAANQADCgUIBQAAAA==.',
As='Asmodyus:BAABNQAECn8eAAMLAAkKwAw6dABcAQALAAkKwAw6dABcAQAMAAQKAAazLACXAAAAAA==.Asmozaps:BAABNQAECn8tAAIGAAoKwQ/xKgCzAQAGAAoKwQ/xKgCzAQAAAA==.',
At='Ataraxya:BAAANQAECgQIBAAAAA==.',
Az='Aziel:BAABNQAECn8hAAMNAAoKMAyKoADLAQANAAoK3QuKoADLAQAOAAEKcw3eMAA8AAAAAA==.Azmodeaus:BAAANQADCgcIBwAAAA==.',
Ba='Baraden:BAABNQAECn8eAAIGAAcKFRF9ewCwAQAGAAcKFRF9ewCwAQAAAA==.',
Be='Beefblood:BAAANQAECgMIBAAAAA==.',
Bh='Bhxdeeznutz:BAAANQADCgUIBQAAAA==.Bhxrafiq:BAAANQADCgYIBgAAAA==.',
Bi='Bigtimmehss:BAAANQAECgMIBQAAAA==.Bih:BAAANQADCgMIAwAAAA==.Bikerm:BAAANQAECgEIAQABNQAFFAcIGgAKAAcgAA==.Billiards:BAAANQADCggICAABNQAECgoKOwALADQdAA==.Birgetta:BAAANQADCggICAABNQAECggIGwABAC0FAA==.',
Bl='Blitzkrieged:BAAANQAECggICAAAAA==.Blorne:BAAANQAECgQICAAAAA==.',
Bo='Bobodaklown:BAABNQAECn88AAMPAAkKmh6jPADgAgAPAAkKmh6jPADgAgAQAAYK2RDwFwBBAQAAAA==.Boneshade:BAAANQAECgMIAwAAAA==.Boombawks:BAAANQADCgUICQAAAA==.Boomnbrew:BAABNQAECn8nAAIRAAoK3w3+EQDGAQARAAoK3w3+EQDGAQAAAA==.Bownir:BAABNQAECn8gAAISAAoKnRMfPwDmAQASAAoKnRMfPwDmAQAAAA==.',
Br='Braelsong:BAAANQAECgEIAQAAAA==.Brewman:BAABNQAECn8sAAMTAAoKYBZrHwA0AgATAAoKYBZrHwA0AgAUAAMKKBC4OACoAAAAAA==.',
Bu='Bubonic:BAABNQAECn8XAAIVAAcKrwoXOwDOAAAVAAcKrwoXOwDOAAAAAA==.Buenasalud:BAABNQAECn8iAAIJAAkK2huxFQC3AgAJAAkK2huxFQC3AgAAAA==.',
Ca='Catopriest:BAAANQAECggIEwAAAA==.Caylea:BAACNQAFFH8SAAINAAcKBhTREwCOAQANAAcKBhTREwCOAQA1AAQKfzcAAg0ACgofIpMnABsDAA0ACgofIpMnABsDAAAA.',
Ch='Chalis:BAABNQAECn8dAAMWAAgKPiHuFwCtAQAWAAQKfiTuFwCtAQACAAcKhx7YcwASAQAAAA==.',
Cl='Clamsquirter:BAABNQAECn8iAAQFAAoKCxozPABvAgAFAAoKCxozPABvAgAXAAMKtQlxMABqAAAGAAEKHhGKywAtAAAAAA==.Clanis:BAABNQAECn8VAAMHAAcKRxfANQCUAQAHAAcKWRXANQCUAQAYAAUKnRRxNACcAAABNQAFFAcIDwAZAKgXAA==.',
Co='Coldhwip:BAABNQAECn83AAMMAAoKaRjNDwCrAQALAAkK1RPxvwAEAgAMAAoKABbNDwCrAQAAAA==.',
Cr='Crtaker:BAAANQAECgcICgAAAA==.Crushfoot:BAAANQADCgUIBQAAAA==.Crysis:BAABNQAECn83AAIaAAoKrx72CADAAgAaAAoKrx72CADAAgAAAA==.',
Cu='Cuahtemoc:BAAANQADCgYIDQAAAA==.',
Da='Dabss:BAAANQAECgEIAQAAAA==.Daelin:BAABNQAECn80AAMPAAoKTCKKDAARAwAPAAoKTCKKDAARAwAQAAgKqxWkIADfAQAAAA==.Dagda:BAAANQAECgUIBAAAAA==.Danye:BAAANQAECgMIBgAAAA==.Darknasti:BAAANQAECgEIAQAAAA==.Darkscout:BAAANQADCgUJDwAAAA==.Dasyra:BAAANQAECgQIBAABNQAECgoKNQAFAEYjAA==.',
De='Decease:BAAANQAECgQIBAABNQAFFAQIBwACAKsYAA==.Delium:BAACNQAFFH8TAAMLAAYKUBPbEgDhAQALAAYKUBPbEgDhAQAMAAEK1xaPDABOAAA1AAQKfzAAAgsACgofIg4pAD8DAAsACgofIg4pAD8DAAAA.Demonmommy:BAABNQAECn8VAAICAAYKkQSZ8wDjAAACAAYKkQSZ8wDjAAAAAA==.Deäthrose:BAABNQAECn8uAAMGAAoKuA8kWgAUAgAGAAoKuA8kWgAUAgAFAAgKCAmXjgBkAQAAAA==.',
Di='Die:BAAANQAECgYICgAAAA==.Diegoo:BAAANQADCgUIBQAAAA==.Disc:BAAANQAECgYIBwAAAA==.',
Do='Doadin:BAABNQAECn88AAIbAAkKhxgnFwCLAgAbAAkKhxgnFwCLAgAAAA==.Dolphus:BAABNQAECn8WAAIOAAkKeBe+CABWAgAOAAkKeBe+CABWAgAAAA==.Dolust:BAAANQAECgQIBgABNQAECgkJPAAbAIcYAA==.Doominatrix:BAABNQAECn8xAAICAAoKaxJMaQAgAgACAAoKaxJMaQAgAgAAAA==.Dotem:BAAANQAECgQIBQAAAA==.',
Dr='Draggum:BAAANQADCggIFQABNQAECgkJLgAPABggAA==.Dragune:BAAANQAECgMIAgABNQAECggIHQAWAD4hAA==.Dreadlocky:BAABNQAECn8vAAMWAAkKBBhvAgDNAQAWAAkKBBhvAgDNAQACAAQKAg0DBgHAAAAAAA==.Dreadmagey:BAAANQADCggICQABNQADCgYIDAAcAAAAAA==.Dreadraven:BAAANQADCgYIDAAAAA==.Dreven:BAAANQADCggIEAABNQAECgcIFwAIANUQAA==.Drip:BAAANQAECgIIAgAAAA==.Druidhams:BAABNQAECn8gAAIdAAoKQR7QDQDzAgAdAAoKQR7QDQDzAgAAAA==.',
Du='Dunktars:BAABNQAECn8sAAINAAoKDCDiQwC+AgANAAoKDCDiQwC+AgAAAA==.Durpy:BAAANQADCgIIAwAAAA==.',
Eg='Egri:BAAANQAECgQIBgAAAA==.',
Ei='Eightball:BAAANQAECgMIAgABNQAECgoKOwALADQdAA==.',
El='Electro:BAAANQADCgYIBgABNQAECgQIBgAcAAAAAA==.Elisha:BAABNQAECn9gAAIPAAkKdxCPogDcAQAPAAkKdxCPogDcAQAAAA==.Eltara:BAAANQADCgEIAQAAAA==.',
Er='Erebostro:BAABNQAECn8rAAISAAkKNRqhPwCsAgASAAkKNRqhPwCsAgAAAA==.',
Fa='Facheritor:BAAANQADCgUIBAAAAA==.Fastlane:BAAANQAECgQIEAAAAA==.Fathercow:BAAANQAFFAIIAgAAAA==.Fathoms:BAAANQABCggIDgAAAA==.Fauxphoe:BAAANQADCgMIAwAAAA==.Fauxtotem:BAABNQAECn8yAAIXAAoKoiGGBQAyAwAXAAoKoiGGBQAyAwAAAA==.',
Fe='Fender:BAAANQAECgEIAQAAAA==.Ferdinand:BAAANQADCgcIBwABNQAECgcIEAAcAAAAAA==.Ferren:BAAANQABCgQIBAAAAA==.',
Fi='Fingies:BAABNQAECn9IAAQCAAoKeCJ/HQBNAgACAAgKBSR/HQBNAgAWAAIKeyJLPgDJAAAeAAEKrhlhFwBMAAAAAA==.',
Fl='Flexyheals:BAAANQABCgQIBQAAAA==.Flush:BAAANQAECggICAAAAA==.',
Fr='Freakbeast:BAAANQAECgEIAQABNQAECgoKIAAfAIwiAA==.',
Fu='Furina:BAAANQAECgIIAgAAAA==.',
['Fë']='Fënn:BAAANQAECgQIBQAAAA==.',
['Fí']='Fíona:BAAANQABCgEIAgABNQAECggICwAcAAAAAA==.',
Ga='Galaxsea:BAABNQAECn8vAAITAAoKSR15EQDUAgATAAoKSR15EQDUAgAAAA==.Gale:BAAANQADCgYIBwABNQAECgkJJgATAKYWAA==.Gamefreak:BAAANQAECgQIBAAAAA==.',
Ge='Gerthquake:BAABNQAECn8YAAMFAAoK2gnMhQB8AQAFAAoK2gnMhQB8AQAGAAEKzgVDyQAwAAAAAA==.',
Gh='Ghostfreak:BAABNQAECn8tAAIYAAkKQRczCQD4AQAYAAkKQRczCQD4AQAAAA==.',
Gi='Giren:BAAANQAECggIBwABNQAFFAcIHAAPAG8cAA==.',
Gn='Gnomium:BAAANQADCggICAABNQAFFAQICgALAGEVAA==.',
Go='Gobø:BAAANQAECgQIBAAAAA==.Gooby:BAABNQAECn8XAAINAAcKABd2ogDGAQANAAcKABd2ogDGAQAAAA==.',
Gr='Grindlemorph:BAAANQADCgYICAAAAA==.',
Ha='Hacks:BAABNQAECn8mAAMFAAgKuBFSQgCNAQAFAAgKuBFSQgCNAQAGAAUKtwWT0gDuAAAAAA==.Haranjer:BAABNQAECn8eAAITAAgKJBuyGgBpAgATAAgKJBuyGgBpAgAAAA==.',
He='Hefferhumper:BAABNQAECn8lAAMgAAgKuw/3JQBVAQAgAAgKxQj3JQBVAQAhAAYKnRIMKgBHAQAAAA==.',
Ho='Homlock:BAAANQADCgYICwABNQAFFAcIHQALAMQgAA==.Homslam:BAABNQAECn8UAAMNAAkKZB3YigABAgANAAgK6hrYigABAgAaAAQKKRwnJwAHAQABNQAFFAcIHQALAMQgAA==.Homsorc:BAACNQAFFH8dAAMLAAcKxCAdCQA2AgALAAYKQyAdCQA2AgAMAAIKSyBsBwBhAAA1AAQKfzQAAgsACgptJosEANUDAAsACgptJosEANUDAAAA.Homstab:BAACNQAFFH8IAAIHAAQKiBtBDQDKAAAHAAQKiBtBDQDKAAA1AAQKfysAAwcACgqqIkMFAC8DAAcACgqqIkMFAC8DABgAAgr5JPd2ANYAAAE1AAUUBwgdAAsAxCAA.Homtard:BAAANQAECgUIDAABNQAFFAcIHQALAMQgAA==.Homtotem:BAAANQADCggICAABNQAFFAcIHQALAMQgAA==.Homwiz:BAAANQAECgQIBgAAAA==.Hope:BAABNQAECn8nAAIbAAoKrhQRRgBOAgAbAAoKrhQRRgBOAgAAAA==.',
Ic='Iced:BAAANQADCgIIAgABNQAECgkJIQAIALQYAA==.Icons:BAAANQAECggICAAAAA==.Icyshaft:BAAANQADCgMIAwABNQAFFAcIDwAZAKgXAA==.',
Il='Illiandray:BAABNQAECn8zAAIWAAoKvx0sAQBeAgAWAAoKvx0sAQBeAgAAAA==.',
In='Insomniac:BAABNQAECn80AAIiAAoKIySyAwACAwAiAAoKIySyAwACAwAAAA==.',
Is='Isklar:BAAANQADCgcIBwAAAA==.',
Ja='Jaegernaut:BAAANQADCgYIEgAAAA==.Jagernaut:BAAANQAECgUICwAAAA==.Jake:BAABNQAECn8bAAILAAkKcg3FZgB8AQALAAkKcg3FZgB8AQAAAA==.Jangaballs:BAAANQAECgYIDQAAAA==.Jawndie:BAABNQAECn8pAAMUAAoKBxi+EwBAAgAUAAoKBxi+EwBAAgARAAEKAABbNQAiAAAAAA==.',
Ji='Jinzo:BAAANQAECgIIAQABNQAECggICwAcAAAAAA==.',
Jo='Joker:BAAANQAECgIIAgAAAA==.',
Jy='Jynn:BAAANQAECgUIEAABNQAECgoKKwAjADUgAA==.',
Ka='Kaalg:BAAANQADCgYIBgAAAA==.Kaalgormi:BAAANQABCgcICQAAAA==.Kammo:BAABNQAECn8zAAIEAAkKaiOzBQCFAwAEAAkKaiOzBQCFAwAAAA==.Kassa:BAAANQADCggIEQAAAA==.',
Ke='Keeah:BAABNQAECn8cAAIEAAkKPwevXQAxAQAEAAkKPwevXQAxAQAAAA==.Kestra:BAABNQAECn83AAIUAAoKgwdPIgByAQAUAAoKgwdPIgByAQAAAA==.',
Ki='Kittysprigg:BAABNQAECn8kAAMkAAkKlhPVCQCkAQAkAAkKlhPVCQCkAQAgAAQKgwh6igCrAAAAAA==.',
Kl='Klingnor:BAAANQADCgcJBwAAAA==.',
Kr='Kravensteak:BAACNQAFFH8PAAIZAAcKqBcCCgCjAQAZAAcKqBcCCgCjAQA1AAQKfzMAAhkACQpPIoEFALQCABkACQpPIoEFALQCAAAA.',
Ku='Kurty:BAAANQADCgUIBQAAAA==.',
Kw='Kwickin:BAAANQAECgYIEQABNQAECgkJLgAPABggAA==.',
Ky='Kyreen:BAABNQAECn8kAAISAAkK0A83UgCmAQASAAkK0A83UgCmAQAAAA==.',
['Kä']='Kärl:BAAANQADCgYIBwABNQAECgoKLwATAEkdAA==.',
Le='Leonelda:BAAANQADCgUIBQAAAA==.Leylines:BAABNQAECn8zAAMLAAoKxBcukgBbAgALAAoKyRYukgBbAgAMAAEKHhNKKgA/AAAAAA==.',
Lu='Luciferr:BAAANQAECgEIAQAAAA==.Lukafox:BAAANQAECgcIEgAAAA==.Lunastarvale:BAABNQAECn8sAAISAAoKgBShKwAyAgASAAoKgBShKwAyAgAAAA==.Lunereclipse:BAAANQAECgQJBAAAAA==.',
Ma='Macha:BAABNQAECn81AAMFAAoKRiNpBQCcAwAFAAoKRiNpBQCcAwAGAAYKkweGwAARAQAAAA==.Madith:BAAANQAECgQICgAAAA==.Maintarget:BAABNQAECn8hAAIIAAkKtBgLGwBxAgAIAAkKtBgLGwBxAgAAAA==.Malefisico:BAABNQAECn8hAAIWAAkKYBdFCgBTAgAWAAkKYBdFCgBTAgAAAA==.Mardríft:BAABNQAECn8xAAIgAAoKHB6XDQBxAgAgAAoKHB6XDQBxAgAAAA==.Marero:BAAANQADCgYICgAAAA==.Martyr:BAABNQAECn8uAAIlAAoKAA5dFAAJAgAlAAoKAA5dFAAJAgAAAA==.Mazga:BAABNQAECn8wAAIFAAgK+RO4QgCLAQAFAAgK+RO4QgCLAQAAAA==.',
Mc='Mcflury:BAAANQADCgYICwAAAA==.',
Me='Melee:BAAANQADCgYIDAAAAA==.Meteos:BAAANQABCgMIBAAAAA==.Mezoti:BAAANQADCggICgAAAA==.',
Mi='Mick:BAAANQAECgYICQAAAA==.Miraclehwip:BAAANQADCggICQAAAA==.',
Mo='Moaxzy:BAAANQAECgEIAQAAAA==.Moji:BAABNQAECn84AAIUAAoKfxhpEAB5AgAUAAoKfxhpEAB5AgAAAA==.Monstermayi:BAABNQAECn8rAAMOAAkKKBUbCgAsAgAOAAkKKBUbCgAsAgANAAIKvxATMwFuAAAAAA==.Mooknight:BAABNQAECn8uAAIDAAoKQAuoIwB3AQADAAoKQAuoIwB3AQAAAA==.Moreina:BAAANQADCgUIBQABNQAECgoKPgAJABQcAA==.Morgoth:BAABNQAECn8oAAQCAAgKQx0NQACSAgACAAgKehwNQACSAgAeAAMK1RnIFwDPAAAWAAEKAAC3dAA5AAAAAA==.Morteesha:BAAANQAECgEIAQABNQAECgoKKQAUAAcYAA==.',
Mu='Muggy:BAABNQAECn8wAAIYAAkKCg8HFQBSAQAYAAkKCg8HFQBSAQAAAA==.',
My='Myrothar:BAAANQAECgUIBQAAAA==.Mytastical:BAAANQAECgMIBwAAAA==.',
['Må']='Måzikeen:BAAANQAECgQIBAABNQAECgoKNQAFAEYjAA==.',
['Mæ']='Mæve:BAAANQAECgYIBgABNQAECgoKNQAFAEYjAA==.',
Na='Najwah:BAABNQAECn8dAAMJAAoKjxs+FwAbAwAJAAoKjxs+FwAbAwAIAAQKRxE0SwDqAAAAAA==.Namalis:BAACNQAFFH8HAAMCAAQKqxgWGACaAAACAAMK+BgWGACaAAAWAAEKEhiDCgBUAAA1AAQKfy8ABAIACgpbI08eAAsDAAIACAp6I08eAAsDABYAAwrJFpk+AMgAAB4AAQorJVsSAG8AAAAA.Nanielito:BAABNQAECn8bAAILAAkKaxfagwB3AgALAAkKaxfagwB3AgAAAA==.',
Ne='Necrotik:BAAANQADCgIIAgAAAA==.Neffer:BAAANQAECgQIBwAAAA==.Nerra:BAAANQADCggIDgAAAA==.',
Ni='Nineball:BAAANQADCgIIAgABNQAECgoKOwALADQdAA==.Ninjutsu:BAAANQAECgEIAQABNQAFFAQIBwACAKsYAA==.',
No='Nobunaka:BAAANQADCgYIBgAAAA==.Nonae:BAABNQAECn8fAAISAAkKyRavOgD2AQASAAkKyRavOgD2AQAAAA==.Norivari:BAAANQADCgYICwAAAA==.Nosali:BAABNQAECn8mAAIeAAgK/ht0AwDBAgAeAAgK/ht0AwDBAgABNQAECgoKPgAJABQcAA==.Nosliw:BAAANQAECggICAAAAA==.Noxilis:BAABNQAECn8cAAIDAAoKCQuzIwB3AQADAAoKCQuzIwB3AQAAAA==.',
Nu='Nuggetz:BAAANQADCggICQAAAA==.',
['Nï']='Nïghtman:BAAANQAECgcIDQABNQAECgkJGAAkAAAYAA==.',
Om='Omegá:BAABNQAECn8eAAMQAAkKiA8mGQA2AQAQAAkK1g4mGQA2AQAPAAEKWBNSkgFCAAABNQAECgoKHwADAHQMAA==.',
Op='Optìmusprìme:BAABNQAECn8yAAMaAAoKfBfJBwDhAQAaAAoKfBfJBwDhAQAOAAEKAACqKwAAAAAAAA==.',
Or='Ordovic:BAAANQADCgUIBQAAAA==.',
Pa='Paladinchin:BAAANQAECggICAABNQAFFAgIGQAHAD4fAA==.Pandemic:BAABNQAECn82AAISAAoKdRiXMAAeAgASAAoKdRiXMAAeAgAAAA==.Papa:BAABNQAECn9EAAQCAAoKPBoAKgAKAgACAAkKwBcAKgAKAgAeAAUKrxGNEQAzAQAWAAUKCxV2LQAWAQAAAA==.Pawfu:BAABNQAECn8yAAQTAAkKphnIHABSAgATAAkKphnIHABSAgAUAAgKrwpoKwATAQARAAIKmAn6KgBoAAAAAA==.',
Pe='Penywize:BAABNQAECn8gAAMPAAoKLATMDwEEAQAPAAgKmwTMDwEEAQAbAAkKsAXZvAACAQAAAA==.',
Pi='Pilo:BAAANQADCgUICAAAAA==.',
Pl='Planeteer:BAAANQAECgUIBwAAAA==.',
Po='Pockets:BAABNQAECn87AAILAAoKNB3IQQDvAQALAAoKNB3IQQDvAQAAAA==.',
Pr='Prenus:BAAANQAECgUJBwAAAA==.',
Ps='Psychic:BAABNQAECn8rAAIjAAoKNSADAQBgAwAjAAoKNSADAQBgAwAAAA==.',
Pu='Purge:BAAANQAECgIIBAAAAA==.',
Qr='Qrazi:BAABNQAECn8aAAIGAAgKwBDoZADyAQAGAAgKwBDoZADyAQAAAA==.',
Qu='Quenthil:BAAANQAECgUIBwAAAA==.Quick:BAAANQAECgUIDgABNQAECgkJLgAPABggAA==.',
Ra='Ratha:BAABNQAECn87AAIQAAoK4yKIBABvAwAQAAoK4yKIBABvAwAAAA==.Ravincible:BAAANQAECgMIAwAAAA==.Razeal:BAABNQAECn8VAAIPAAkKRRAzXwCcAQAPAAkKRRAzXwCcAQAAAA==.Razkul:BAAANQAECggIDQAAAA==.',
Ri='Ribbz:BAAANQADCgYICwAAAA==.',
Ro='Roguechin:BAACNQAFFH8ZAAMHAAgKPh91BADlAQAHAAYKKB11BADlAQAYAAQKayO4CQBpAQA1AAQKfzMAAwcACgrqJQcHAA0DAAcACgrDJQcHAA0DABgABwqEIw0WAMsCAAAA.Rokkgar:BAABNQAECn8fAAIGAAgKOhjTQQBuAgAGAAgKOhjTQQBuAgAAAA==.Rottontoe:BAAANQADCgEIAQAAAA==.',
Ru='Runa:BAABNQAECn8UAAMSAAkK3xTcVgBuAgASAAkK3xTcVgBuAgAZAAEKPQlmjgAxAAAAAA==.',
Sa='Sageara:BAAANQAECgQIBAAAAA==.Samirath:BAABNQAECn8aAAIJAAgKJBfiVQAhAgAJAAgKJBfiVQAhAgAAAA==.',
Sc='Scared:BAACNQAFFH8KAAIJAAUK0QlKFABlAQAJAAUK0QlKFABlAQA1AAQKfz0AAgkACQoAInkMAF8DAAkACQoAInkMAF8DAAAA.',
Se='Secarious:BAAANQAECgIIAgAAAA==.Sehnsucht:BAABNQAECn8eAAQkAAcKvxm5EAD9AQAkAAYKuR25EAD9AQAdAAcKQBUWLQCzAQAhAAIKHQvqVQBOAAAAAA==.',
Sh='Shakti:BAAANQAECgUIBQAAAA==.Shieldcow:BAAANQAECgIIBAABNQAFFAIIAgAcAAAAAA==.Shinpal:BAAANQAECgYICQAAAA==.Shmadu:BAABNQAECn8rAAISAAoKvSUxAQD2AwASAAoKvSUxAQD2AwAAAA==.Shockakhan:BAAANQADCgcIBwAAAA==.Shockk:BAAANQAECgQICAAAAA==.',
So='Soola:BAAANQADCggICAABNQAECgoKOwAQAOMiAA==.',
Sp='Spoof:BAAANQADCgYICwAAAA==.',
St='Stabbymoose:BAAANQAECggIBgAAAA==.Stonedpriest:BAAANQAECgUICwAAAA==.Stymie:BAAANQAECgIIAgABNQAFFAQICgALAGEVAA==.',
Su='Surrëal:BAABNQAECn8bAAIBAAgKLQVVXQAMAQABAAgKLQVVXQAMAQAAAA==.',
Sw='Sweetmask:BAAANQAECgYIDQAAAA==.',
Sy='Sybela:BAAANQAECgEIAgAAAA==.',
Ta='Tahitian:BAAANQADCgIIAgAAAA==.Tahlreth:BAABNQAECn81AAIMAAoKBx8QAwBxAgAMAAoKBx8QAwBxAgAAAA==.Tanidge:BAAANQADCgQIBAABNQAECgoKPwAGADwgAA==.Tanidgemage:BAAANQADCgQIBAABNQAECgoKPwAGADwgAA==.Tanidgetotem:BAABNQAECn8/AAIGAAoKPCCGFgBBAwAGAAoKPCCGFgBBAwAAAA==.',
Te='Teias:BAABNQAECn8+AAMJAAoKFBwCOQCEAgAJAAoKFBwCOQCEAgAIAAQKzhfUQAApAQAAAA==.Tersus:BAAANQADCgEIAQAAAA==.',
Th='Theleena:BAAANQABCgIIAgAAAA==.',
Ti='Tirael:BAAANQAECgUIBgABNQAECgoKPgAJABQcAA==.',
To='Torvald:BAAANQAECggICAABNQAECggICAAcAAAAAA==.',
Tr='Tricko:BAABNQAECn80AAISAAkKFiK/JAAEAwASAAkKFiK/JAAEAwAAAA==.Trickshots:BAAANQADCgMIAwABNQAECgoKOwALADQdAA==.Trogar:BAAANQADCgQIBwAAAA==.Trollbi:BAAANQADCgQIAgAAAA==.Trollfacion:BAAANQADCgYIBgAAAA==.Trollskingx:BAABNQAECn8sAAILAAoK+Bc2NwAVAgALAAoK+Bc2NwAVAgAAAA==.Trollzy:BAABNQAECn81AAMXAAoKJR8QBwBZAgAXAAkKrx4QBwBZAgAFAAMKpwIGDgFMAAAAAA==.Trunkmonkey:BAABNQAECn8pAAICAAoKthYPJQAjAgACAAoKthYPJQAjAgAAAA==.Trunky:BAAANQAECgYIBgAAAA==.',
Ts='Tsaagan:BAABNQAECn8xAAICAAoKdiGHJADyAgACAAoKdiGHJADyAgAAAA==.',
Um='Umbrosa:BAAANQADCgcIBwABNQAECgoKNwAaAK8eAA==.',
Ur='Urthalos:BAAANQAECgcICQAAAA==.',
Va='Valica:BAAANQADCgUIBQAAAA==.Valiithria:BAAANQAECgQIBQAAAA==.Valkyruid:BAACNQAFFH8HAAIdAAIKPgycDAB0AAAdAAIKPgycDAB0AAA1AAQKfx8AAx0ACgqiHXoRAMcCAB0ACgqiHXoRAMcCACAAAQoAABO/ACIAAAAA.Varaxis:BAAANQABCgQIBgAAAA==.',
Ve='Veledreyssa:BAAANQAECgEIAgAAAA==.',
Vu='Vulgan:BAAANQAECgUIBQAAAA==.',
Wa='Warriorchin:BAAANQAFFAMIAwABNQAFFAgIGQAHAD4fAA==.Waywatcher:BAAANQAECgQICgAAAA==.',
Wh='Whiilow:BAABNQAECn8hAAMFAAoKSBXNOwBwAgAFAAoKSBXNOwBwAgAGAAEKGAQlSwEoAAAAAA==.',
Wu='Wulgyn:BAAANQABCgQIBAAAAA==.Wullgan:BAABNQAECn8cAAIJAAoKyBVRWQAWAgAJAAoKyBVRWQAWAgAAAA==.',
Xe='Xencure:BAAANQAFFAIIAwAAAA==.Xerk:BAABNQAECn8YAAIkAAkKABjtBgD4AQAkAAkKABjtBgD4AQAAAA==.',
Xy='Xyrna:BAABNQAECn8uAAImAAoK6xrTAgD7AgAmAAoK6xrTAgD7AgABNQAECgoKOwAQAOMiAA==.',
Ya='Yareli:BAABNQAECn8tAAIKAAkKygWKGAApAQAKAAkKygWKGAApAQAAAA==.',
Yo='Youngdoug:BAAANQAECgQIBwAAAA==.',
Yu='Yunara:BAAANQADCgUIBQAAAA==.',
Za='Zartman:BAABNQAECn8cAAMVAAgKzhOEZQB6AQAVAAYKVhiEZQB6AQAEAAYK4wyhXAA2AQAAAA==.',
Ze='Zekröm:BAAANQAECgUIBQABNQAECgoKMwALAMQXAA==.Zeleck:BAABNQAECn8XAAMIAAcK1RBmLADDAQAIAAcK1RBmLADDAQAJAAQK3gXl0QCwAAAAAA==.Zeno:BAACNQAFFH8cAAIPAAcKbxwWAQDBAgAPAAcKbxwWAQDBAgA1AAQKfzoAAg8ACgqrIWMVAG8DAA8ACgqrIWMVAG8DAAAA.Zetetic:BAAANQADCggICAAAAA==.',
Zg='Zgystrdst:BAABNQAECn8fAAIYAAgKfBLbMQAYAgAYAAgKfBLbMQAYAgABNQAECggIHwAGADoYAA==.',
Zi='Zinbar:BAAANQAECgYIDQAAAA==.',
Zo='Zoroark:BAAANQADCggIEAABNQAECgoKMwALAMQXAA==.',
Zu='Zuggzugg:BAAANQADCgYIBgAAAA==.Zune:BAABNQAECn8mAAMTAAkKphaJEQDMAQATAAkKeRaJEQDMAQARAAYKaBMcFwBwAQAAAA==.',
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
