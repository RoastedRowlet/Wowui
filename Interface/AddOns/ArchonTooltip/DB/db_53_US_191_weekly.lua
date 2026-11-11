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

local lookup = {'Monk-Windwalker','DeathKnight-Frost','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Holy','Paladin-Retribution','Shaman-Restoration','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warrior-Protection','Hunter-Survival','Shaman-Elemental','Evoker-Preservation','Warrior-Fury','DemonHunter-Havoc','Unknown-Unknown','DemonHunter-Devourer','DeathKnight-Blood','Priest-Holy','Warrior-Arms','Druid-Restoration','Druid-Feral','Shaman-Enhancement','Priest-Discipline','Mage-Arcane','Warlock-Affliction','Druid-Guardian','DemonHunter-Vengeance','Priest-Shadow','Mage-Frost','Rogue-Assassination','Druid-Balance','DeathKnight-Unholy','Monk-Brewmaster','Rogue-Subtlety','Rogue-Outlaw','Monk-Mistweaver',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Acaciastrain:BAAANQAECgIIAgAAAA==.',
Ad='Adorie:BAAANQAECgYIBgAAAA==.',
Ae='Aelord:BAAANQADCgUIBQAAAA==.Aelusius:BAAANQAECgEIAQABNQAECgoKUwABAE4kAA==.Aerebos:BAABNQAECn8jAAICAAoKvxYeHwBBAgACAAoKvxYeHwBBAgABNQAECgoKUwABAE4kAA==.Aeriss:BAAANQABCgQIBAAAAA==.Aetheria:BAAANQADCgYJBgAAAA==.Aethos:BAABNQAECn9HAAMDAAoKNyL2AgAtAwADAAoKNyL2AgAtAwAEAAMKcBu7+wCgAAABNQAECgoKUwABAE4kAA==.Aeón:BAAANQADCgMIAwABNQAECgcIGwAFANYIAA==.',
Ag='Agua:BAAANQAECgQIBAAAAA==.',
Ak='Akashá:BAABNQAECn8WAAIGAAoKQg1gkQCUAQAGAAoKQg1gkQCUAQAAAA==.',
Al='Aladrius:BAEANQAECgQIBwAAAA==.Alexanderath:BAAANQAECgUICAAAAA==.Alkatractite:BAABNQAECn8gAAIGAAkKKxY3eQDHAQAGAAkKKxY3eQDHAQAAAA==.Allenwalker:BAAANQAECgYIDwAAAA==.Allison:BAAANQADCgUIBQABNQAECgoKPwAHAOgbAA==.',
Am='Amey:BAAANQAECggIEwAAAA==.',
An='Anelise:BAAANQADCgUIBQAAAA==.Antelon:BAAANQAECgMIAwABNQAECgkJJwAIAAoLAA==.',
Ao='Aoeslave:BAACNQAFFH8FAAMJAAMK3wQiKgBuAAAJAAIKZwUiKgBuAAAKAAEKzgN0FAA/AAA1AAQKfzMAAwkACgpVFolvAHYBAAkACQrIFYlvAHYBAAoAAwplElBHAKoAAAAA.',
Ar='Arrisia:BAABNQAECn8iAAIEAAcKyAb/xAANAQAEAAcKyAb/xAANAQAAAA==.Arthedain:BAABNQAECn81AAILAAoKwSJJAwBsAwALAAoKwSJJAwBsAwAAAA==.Arthedaine:BAACNQAFFH8HAAIMAAQKBxAQAQDVAAAMAAQKBxAQAQDVAAA1AAQKfysAAgwACgpZHg8CALcCAAwACgpZHg8CALcCAAE1AAQKCgo1AAsAwSIA.',
As='Assano:BAABNQAECn8kAAMKAAkK+BLmBAChAQAKAAkK+BLmBAChAQAJAAQKSgpOBAHDAAABNQAECgoKOgANAEkYAA==.',
Au='Autumni:BAAANQADCgcICQAAAA==.Auvry:BAABNQAECn8jAAIOAAkKrQ/XGQAlAgAOAAkKrQ/XGQAlAgAAAA==.',
Az='Azliain:BAAANQAECggIEwAAAA==.Azurine:BAAANQADCgYIBgAAAA==.',
Ba='Bahamutfang:BAABNQAECn8ZAAIGAAcKkgm91QAZAQAGAAcKkgm91QAZAQAAAA==.Bahozakurkho:BAAANQAECgMIAwABNQAECgcIEgAGADwOAA==.Bakala:BAABNQAECn8kAAMPAAcK0wb5GgD3AAAPAAYK5Ab5GgD3AAALAAcKyAXlIwDFAAAAAA==.Barath:BAABNQAECn8UAAIQAAcKugp9RgD8AAAQAAcKugp9RgD8AAAAAA==.',
Be='Beerwench:BAAANQAECgYIEgAAAA==.Belegaer:BAABNQAECn8mAAIFAAgKwQtbdABEAQAFAAgKwQtbdABEAQAAAA==.Belenos:BAAANQAECgEIBAABNQAECgIIBAARAAAAAA==.Benmaverick:BAABNQAECn8cAAISAAkKtQ6cLgDMAQASAAkKtQ6cLgDMAQAAAA==.Bervin:BAABNQAECn8aAAITAAcKEhk5OQBQAQATAAcKEhk5OQBQAQAAAA==.',
Bi='Bifftunkisjr:BAAANQADCgEJAQAAAA==.Bishop:BAABNQAECn8zAAIUAAoKnArJWgC8AQAUAAoKnArJWgC8AQAAAA==.',
Bl='Blackbird:BAAANQADCgQIBAAAAA==.Bladesman:BAABNQAECn8YAAMLAAoKzxHsDgCwAQALAAkKMxTsDgCwAQAVAAcKEgFxDwFJAAAAAA==.',
Bo='Bobe:BAABNQAECn9KAAILAAoK2CDTAwDtAgALAAoK2CDTAwDtAgAAAA==.Bobedruid:BAAANQAECgQIBAAAAA==.Bordok:BAABNQAECn8YAAICAAYKlQcSbgDPAAACAAYKlQcSbgDPAAAAAA==.Borkuz:BAAANQADCggJCAAAAA==.',
Br='Brawl:BAAANQADCgYIBgAAAA==.Broot:BAAANQAECgEIAQAAAA==.Brunco:BAABNQAECn8vAAMEAAoKJRn/TACHAgAEAAoKJRn/TACHAgADAAEK0QpxiQA1AAAAAA==.',
Ca='Captplanet:BAABNQAECn88AAMWAAoK2xl/FAClAgAWAAoK2xl/FAClAgAXAAgKmhvEFQCfAQAAAA==.',
Ce='Ceindra:BAACNQAFFH8JAAIYAAUKPAr3AgD4AAAYAAUKPAr3AgD4AAA1AAQKfy0AAhgACgonGs0KAMUCABgACgonGs0KAMUCAAAA.Celestria:BAABNQAECn8aAAMZAAYKvQsACQAOAQAZAAYKvQsACQAOAQAUAAEKHwFZDQEYAAAAAA==.Celiñ:BAAANQAECgYIDQAAAA==.Cerealkiller:BAAANQADCgYJBgAAAA==.',
Ch='Chipcho:BAAANQADCggICAAAAA==.Chockula:BAAANQADCgMIAwAAAA==.Chuladk:BAAANQAECgEIAQAAAA==.',
Co='Colbalt:BAAANQADCggIEAAAAA==.Constantinez:BAABNQAECn8XAAIKAAoKIQJ6QwC3AAAKAAoKIQJ6QwC3AAAAAA==.Cor:BAAANQAECgMIBAAAAA==.',
Cr='Crackerzz:BAAANQAECgYICwAAAA==.',
Cu='Cuddlymethod:BAAANQADCgYICQAAAA==.',
['Có']='Cól:BAABNQAECn87AAIaAAoKAhtoQgA4AgAaAAoKAhtoQgA4AgAAAA==.Cónky:BAAANQADCgcIBQAAAA==.',
Da='Daddymoo:BAAANQADCgUIDAAAAA==.Daesong:BAAANQADCgEIAQABNQAECgcIEgAGADwOAA==.Dahealzrhere:BAAANQADCgEIAQAAAA==.Dalel:BAACNQAFFH8bAAMSAAcKzxZBAwBsAQASAAcKzxZBAwBsAQAQAAEKdgB2GwAsAAA1AAQKf0MAAxIACgqVIOkNAAkDABIACgqVIOkNAAkDABAAAQoAADySADYAAAAA.David:BAABNQAECn8WAAIVAAgKlRr+YABrAgAVAAgKlRr+YABrAgAAAA==.',
De='Deadlyglow:BAABNQAECn8aAAMTAAgKpxpaPgAHAgATAAcK7BhaPgAHAgACAAYKDBdDWABKAQAAAA==.Demiurgos:BAABNQAECn8XAAMHAAoKEhb1WwD7AQAHAAoKEhb1WwD7AQANAAYKGAwSggD1AAAAAA==.Denji:BAAANQADCggIBgAAAA==.Denogarn:BAAANQADCggIEQAAAA==.Dermot:BAABNQAECn8jAAQbAAkKViCSCwCxAQAJAAgK7RxDfQDtAQAbAAYK7BuSCwCxAQAKAAIK9RzJSgCfAAAAAA==.',
Dh='Dhiying:BAAANQADCgcIBwAAAA==.',
Di='Dirtface:BAABNQAECn88AAIVAAoKwAiRggBsAQAVAAoKwAiRggBsAQAAAA==.Dixlongmd:BAAANQAECgEIAQAAAA==.Dixmen:BAABNQAECn8wAAIGAAkKdRaZcwBHAgAGAAkKdRaZcwBHAgAAAA==.',
Dl='Dlekri:BAAANQAECgEIAQAAAA==.',
Do='Dolemen:BAABNQAECn8oAAIGAAcKCAQjEQG6AAAGAAcKCAQjEQG6AAAAAA==.Domaon:BAABNQAECn86AAIQAAoKKCDvDQC5AgAQAAoKKCDvDQC5AgAAAA==.Domshammy:BAAANQADCggICAABNQAECgoKOgAQACggAA==.Doubt:BAAANQAECgUIDAAAAA==.Doughug:BAAANQAECgMIAwABNQAECgQIBAARAAAAAA==.Dozy:BAABNQAECn8+AAIGAAoK3yMKDwArAwAGAAoK3yMKDwArAwAAAA==.',
Dr='Dracania:BAAANQADCgEIAQAAAA==.Druidheelzz:BAAANQAECgUICAAAAA==.Druissh:BAAANQAECgYIDQABNQAECgoKOgANAEkYAA==.Drôôdude:BAAANQADCgQIBAAAAA==.',
Du='Dullgrim:BAAANQADCggICAAAAA==.Dunigan:BAABNQAECn81AAIGAAgKQA56vQBBAQAGAAgKQA56vQBBAQAAAA==.Dunigen:BAABNQAECn8cAAMCAAcKUg3JWQAXAQACAAcKUg3JWQAXAQATAAMKpAtRfwBiAAAAAA==.',
Eb='Ebeast:BAABNQAECn88AAIMAAoKTxEGBQB9AgAMAAoKTxEGBQB9AgAAAA==.',
Ef='Efel:BAAANQADCggICAAAAA==.',
Ev='Evianda:BAAANQADCggIEAAAAA==.',
Fa='Fabulist:BAAANQADCgQIBAAAAA==.Facade:BAABNQAECn8fAAITAAgKgwrGXwByAQATAAgKgwrGXwByAQAAAA==.Facepalm:BAABNQAECn8eAAMPAAgKPBf+CQAwAgAPAAgKPBf+CQAwAgAVAAQKfwjaGgGmAAAAAA==.Falyy:BAAANQADCgMIAwAAAA==.Farmergeorge:BAAANQAECgQJCAAAAA==.',
Fe='Fentak:BAAANQAECgEIAQAAAA==.',
Fi='Fierytotes:BAAANQADCggIFAABNQAECgoKGAALAM8RAA==.Finnek:BAAANQADCgMIAwAAAA==.',
Fo='Forbidenelf:BAACNQAFFH8NAAIGAAQKUxknEADyAAAGAAQKUxknEADyAAA1AAQKf0EAAgYACQrSIfoXAPsCAAYACQrSIfoXAPsCAAAA.Forging:BAAANQADCgQIBAAAAA==.Forgotmymeds:BAAANQAECgQICAAAAA==.Foxmccloud:BAABNQAECn8eAAMHAAYKjiJePQAKAgAHAAYKjiJePQAKAgANAAMKCwn4DgFuAAAAAA==.',
Fr='Fridge:BAAANQAFFAIIAwAAAA==.Frosted:BAAANQADCggIAgAAAA==.Frozenwagyu:BAAANQAECgEIAQAAAA==.Fruitloop:BAABNQAECn8qAAIaAAgKNhhOggCRAQAaAAgKNhhOggCRAQAAAA==.',
Fu='Fuzybrewing:BAAANQABCgQICAAAAA==.',
Ga='Garidrael:BAAANQABCgMIAwAAAA==.',
Ge='Gebran:BAABNQAECn85AAIGAAgKRgpj0AAhAQAGAAgKRgpj0AAhAQAAAA==.Gellywoo:BAABNQAECn82AAIVAAoK5hckPwA3AgAVAAoK5hckPwA3AgAAAA==.Gemmarolizzy:BAAANQAECgQIBgAAAA==.Geneviève:BAAANQADCgQIBAAAAA==.',
Go='Golaoth:BAABNQAECn8eAAIOAAcK+xRjEgC9AQAOAAcK+xRjEgC9AQAAAA==.Gooftroupe:BAABNQAECn8vAAIFAAkKeCGbIACpAgAFAAkKeCGbIACpAgAAAA==.',
Gr='Grandmaster:BAABNQAECn8WAAIaAAgK3AinvQAZAQAaAAgK3AinvQAZAQABNQAECgEIAQARAAAAAA==.Grawn:BAAANQADCgMIAwAAAA==.Greymoon:BAABNQAECn8jAAIcAAcKWhX1JgA4AQAcAAcKWhX1JgA4AQAAAA==.Grimaced:BAAANQAECgYIBgABNQAECgkJOAAGAKYjAA==.Grimtotems:BAAANQADCgMIAwAAAA==.Grumph:BAAANQAECgEIAQAAAA==.',
Ha='Haezi:BAABNQAECn8dAAQdAAkKXBY6DAB1AQAdAAcKlRc6DAB1AQAQAAcKcxCJQgASAQASAAEKAAAGcgArAAAAAA==.Haki:BAAANQABCgIIAgAAAA==.Hammerbully:BAAANQADCgEIAQAAAA==.Happyendings:BAAANQAECgUICwAAAA==.',
He='Helbafx:BAAANQADCggIQwAAAA==.',
Hi='Hino:BAABNQAECn8XAAMUAAgKNBLCawDbAQAUAAgKNBLCawDbAQAeAAEKDQdrXwAyAAAAAA==.',
Ho='Holywarriors:BAAANQAECgQIBQAAAA==.Homewrecker:BAABNQAECn8cAAILAAYKPxZaHgBhAQALAAYKPxZaHgBhAQAAAA==.Horuid:BAAANQADCgEIAQAAAA==.',
Hu='Huntzman:BAAANQADCgUIBQAAAA==.Huské:BAAANQAECgIIAgAAAA==.',
Ic='Icebully:BAAANQAECgIIAgAAAA==.Icemàn:BAAANQAECgQIBgAAAA==.',
Id='Idrazil:BAAANQAECgcIEAAAAA==.',
If='Ifearnobeer:BAAANQAECgMIBAAAAA==.',
In='Infectz:BAAANQAECggIAgAAAA==.Infoxicated:BAAANQADCgQIBAAAAA==.',
Is='Isabel:BAAANQAECgEIAgAAAA==.',
It='Itburnsalot:BAAANQADCgYIBgAAAA==.',
Ja='Jaiantobea:BAACNQAFFH8aAAIHAAcKzh/NAgCMAgAHAAcKzh/NAgCMAgA1AAQKf14AAwcACgpVJBEIAIkDAAcACgpVJBEIAIkDAA0AAQrjFM3hAEMAAAAA.Jakik:BAAANQADCgUICgAAAA==.Jakulista:BAAANQADCgEIAQAAAA==.Jarlaxl:BAAANQADCgQIBAAAAA==.Jawn:BAAANQAECggIDwAAAA==.',
Je='Jessuss:BAABNQAECn8WAAIGAAcKwgpG+AAtAQAGAAcKwgpG+AAtAQAAAA==.',
Jh='Jha:BAABNQAECn8YAAMdAAgKPR5eDAABAgAdAAcKPR5eDAABAgAQAAYKnhJKSwB1AQAAAA==.',
Ju='Jude:BAABNQAECn8pAAIGAAoKHhgNdQBEAgAGAAoKHhgNdQBEAgAAAA==.Junipermoon:BAAANQAECgIIBAAAAA==.',
Ka='Kabub:BAAANQAECgYIEQAAAA==.Kalahandra:BAABNQAECn8bAAIWAAgKkxHtKADYAQAWAAgKkxHtKADYAQAAAA==.Kalebeesd:BAAANQADCgUIBwAAAA==.Katablight:BAAANQAECggIEQABNQAFFAUIBgAJABQaAA==.Katotan:BAABNQAECn8wAAIWAAkK1xXJJAD+AQAWAAkK1xXJJAD+AQAAAA==.Kawk:BAAANQAECgMIAwAAAA==.',
Ke='Kealestra:BAABNQAECn8WAAIfAAUKGg6FHAALAQAfAAUKGg6FHAALAQAAAA==.Keyboärd:BAABNQAECn8YAAILAAgK1xkrDgC9AQALAAgK1xkrDgC9AQAAAA==.',
Ki='Kimochi:BAAANQAECgQIBAAAAA==.Kippo:BAAANQADCgcIBwABNQAECgcICAARAAAAAA==.Kittylover:BAAANQAECgIIAgAAAA==.',
Ko='Kombat:BAAANQADCgYJCgAAAA==.Korllan:BAAANQAECgEIAQAAAA==.Kossnen:BAABNQAECn8bAAQbAAcK7xXBFQDHAAAJAAQKUhYA0gAmAQAbAAQKmhTBFQDHAAAKAAIKERbaGwB6AAAAAA==.',
Kr='Krestisnack:BAABNQAECn8UAAIKAAUKjxZ1IgBdAQAKAAUKjxZ1IgBdAQAAAA==.',
Ku='Kuda:BAABNQAECn8oAAIfAAkKKhWJDgDCAQAfAAkKKhWJDgDCAQAAAA==.Kullkil:BAAANQADCggIEQAAAA==.',
Kw='Kwanu:BAAANQAECgUIDAAAAA==.',
['Kñ']='Kño:BAAANQADCgMIAwABNQAECgcIGwAFANYIAA==.',
['Kó']='Kóñä:BAABNQAECn8bAAMFAAcK1gi9jwD3AAAFAAcK1gi9jwD3AAAIAAEKAADSfwAdAAAAAA==.',
La='Larke:BAAANQAECgEIAQAAAA==.Lasa:BAAANQAECgMIAgAAAA==.Lasloo:BAABNQAECn84AAIGAAoKrhBvfgC7AQAGAAoKrhBvfgC7AQAAAA==.Laylani:BAABNQAECn9MAAIIAAoKtBLvGQCOAQAIAAoKtBLvGQCOAQAAAA==.',
Le='Lebronjames:BAAANQAECgUIDAAAAA==.Leynreite:BAAANQAECgUICgAAAA==.',
Li='Lisan:BAABNQAECn80AAIaAAkK1RSLagDMAQAaAAkK1RSLagDMAQAAAA==.Littledicey:BAABNQAECn89AAIgAAoK8wzTEQChAQAgAAoK8wzTEQChAQAAAA==.',
Lu='Luciä:BAABNQAECn8dAAITAAcKqQwRTQD6AAATAAcKqQwRTQD6AAAAAA==.Lucymoon:BAAANQAECgYIBgAAAA==.Luvflap:BAAANQADCgMIAwAAAA==.',
Lv='Lv:BAABNQAECn8bAAQcAAkKZhByKAAuAQAcAAkKcw1yKAAuAQAhAAMKORlOXwCVAAAXAAIKIxHqMgBuAAABNQAECgoKHwAiAKMfAA==.',
Ly='Lykaios:BAAANQAECgEIAQAAAA==.Lyñx:BAAANQADCgQIBgAAAA==.',
Ma='Machoman:BAAANQAECgQIBAAAAA==.Madness:BAABNQAECn8hAAIeAAoKKgxRMwCIAQAeAAoKKgxRMwCIAQAAAA==.Maerion:BAABNQAECn8aAAMDAAYKagM8UQBWAAAEAAUK1gLNEwHdAAADAAYKkAI8UQBWAAAAAA==.Magdeth:BAABNQAECn8jAAINAAoK8hBqOwDRAQANAAoK8hBqOwDRAQAAAA==.Mantra:BAAANQAECgUIBgAAAA==.Maphra:BAAANQAECgEIAQAAAA==.Marabelle:BAABNQAECn8XAAIhAAgKuAaxXwBRAQAhAAgKuAaxXwBRAQAAAA==.Marasteil:BAAANQADCgIIAgAAAA==.Mariomage:BAAANQADCgQICAAAAA==.Marixia:BAAANQAECgUICgAAAA==.Marrow:BAAANQADCgYIBgAAAA==.Masilitu:BAAANQADCgYIDwAAAA==.Massack:BAABNQAECn8sAAIjAAgKDRagCgB/AQAjAAgKDRagCgB/AQAAAA==.Mawgwa:BAAANQAECgMIAwAAAA==.',
Mc='Mcwrath:BAAANQADCgcIDQABNQAECgkJJwAIAAoLAA==.',
Me='Meeow:BAAANQADCgEIAQABNQAECgkJHQAdAFwWAA==.Mero:BAABNQAECn8oAAQJAAoKSB5hMADGAgAJAAkKmB1hMADGAgAKAAIKHRnnSwCcAAAbAAEKSQrMKgA4AAAAAA==.',
Mi='Midgetmàniàc:BAAANQADCggICAAAAA==.',
Mo='Moiraine:BAAANQAECgUIBQAAAA==.Monkeywrench:BAAANQADCgIIAwAAAA==.Moobear:BAAANQADCgUIBQAAAA==.Moonshiner:BAAANQAECgQIBAAAAA==.Mosimo:BAAANQAECgEIAQAAAA==.Moushuhan:BAABNQAECn8oAAMkAAkKrBT2GQAJAgAkAAkKVxT2GQAJAgAgAAIKqRLwiwCBAAAAAA==.',
My='Mystrall:BAAANQAECgQIBAAAAA==.',
Na='Naanaa:BAABNQAECn8cAAIaAAkKqhG/vwAFAgAaAAkKqhG/vwAFAgAAAA==.Nadorian:BAAANQABCgIIAgAAAA==.Narey:BAAANQADCgIIAgAAAA==.',
Ne='Neb:BAAANQAECgEIAQAAAA==.Netherrogue:BAACNQAFFH8MAAQlAAYKHRLRAQD7AAAlAAMKcRXRAQD7AAAkAAIKWxHqHwBdAAAgAAIKNgy8HABSAAA1AAQKfyYABCUACgrOJA0EANcCACUABwqtJA0EANcCACAABApRHqU6AJsAACQAAQrMJAW1AGsAAAAA.',
Nu='Nuke:BAAANQAECggIEAABNQAFFAIIAwARAAAAAA==.',
Ny='Nytemayer:BAABNQAECn8gAAMJAAkKNRwmWQBLAgAJAAgKuxwmWQBLAgAKAAMKtRPnQwC1AAABNQAFFAQICgASABUMAA==.Nytè:BAACNQAFFH8KAAISAAQKFQzSCADNAAASAAQKFQzSCADNAAA1AAQKfx4AAhIACAp2GNAsANsBABIACAp2GNAsANsBAAAA.',
Ob='Obmakare:BAABNQAECn8aAAMXAAYKrQoJIAAXAQAXAAYKrQoJIAAXAQAWAAEKThLEbgA1AAAAAA==.Obonhigh:BAAANQADCgEIAQAAAA==.Oboñ:BAABNQAECn8cAAIbAAcKeAfXEgDtAAAbAAcKeAfXEgDtAAAAAA==.Obsfuyung:BAAANQAECgUICgAAAA==.',
Oo='Oopsiez:BAAANQAECgUIBwAAAA==.',
Op='Opiiknight:BAAANQAECgQICAAAAA==.Opiipal:BAAANQADCgIIAgAAAA==.Opiishift:BAACNQAFFH8GAAIhAAMKSQYvFAC5AAAhAAMKSQYvFAC5AAA1AAQKfykAAiEACgrKF+YxAFQCACEACgrKF+YxAFQCAAAA.Opiishots:BAABNQAECn8eAAIEAAoKZhpqKQCMAgAEAAoKZhpqKQCMAgAAAA==.',
Or='Orcc:BAAANQADCggIHQAAAA==.',
Pa='Paley:BAAANQAECgQICAAAAA==.',
Pd='Pdgrimm:BAAANQADCgQIBAAAAA==.',
Pe='Peavey:BAAANQABCgEIAQAAAA==.Peligrosa:BAAANQAECggIDwABNQAECgEIAQARAAAAAA==.Performance:BAABNQAECn8/AAQdAAoKryLXAQAQAwAdAAoKryLXAQAQAwASAAMKPRJgQwB/AAAQAAEKBBWGdgBEAAAAAA==.Peterturbo:BAAANQAECgQICAABNQABCgIIAgARAAAAAA==.',
Pi='Pinkky:BAAANQADCgcIBwAAAA==.',
Po='Pocketfox:BAAANQAECgMIBQAAAA==.Poisonoak:BAAANQABCgIIAgAAAA==.Poîsonivy:BAABNQAECn8eAAIKAAcKvwu2CgAFAQAKAAcKvwu2CgAFAQAAAA==.',
Ps='Psyrine:BAAANQAECgUIBgAAAA==.',
Py='Pyrö:BAABNQAECn8bAAIaAAkKxQFDEwGEAAAaAAkKxQFDEwGEAAAAAA==.',
['Pü']='Püff:BAAANQAECgIIAgAAAA==.',
Qu='Qu:BAABNQAECn9AAAIVAAoKox9JJgCcAgAVAAoKox9JJgCcAgAAAA==.',
Ra='Raega:BAAANQAECgEIAQAAAA==.Rakdoc:BAAANQADCgQIBAAAAA==.Rattlesnake:BAAANQADCggIMQAAAA==.Raymonnd:BAAANQAECgQIBAAAAA==.',
Re='Reborn:BAAANQADCgUIBQABNQAECgkJHgAVAKcPAA==.Reefinbeefin:BAAANQAECgEIBAAAAA==.Reflektor:BAAANQABCgQIBAAAAA==.Renägäde:BAAANQAECggIEAAAAA==.Retiredfurry:BAABNQAECn83AAMmAAoK6yIlCAAPAwAmAAoK6yIlCAAPAwABAAgKzR3jFgDsAQAAAA==.',
Ri='Ricodadawg:BAABNQAECn9DAAIaAAoKRCNqIABYAwAaAAoKRCNqIABYAwAAAA==.',
Ro='Roosk:BAAANQADCgUIBQAAAA==.Roshak:BAAANQAECgEIAgAAAA==.Rotspawn:BAAANQAECggJCAAAAA==.',
Ru='Runningbearr:BAAANQADCggIEgAAAA==.Runningdemon:BAAANQADCgYICwABNQAECgoKJwANABENAA==.Runningshama:BAABNQAECn8nAAMNAAoKEQ3VVgBrAQANAAoKEQ3VVgBrAQAHAAEK+hLg9AAvAAAAAA==.Rurahk:BAAANQAECgYIDwAAAA==.',
['Rõ']='Rõbb:BAAANQAECgEIAQAAAA==.',
Sa='Sabaak:BAABNQAECn8gAAIGAAcKzxeXtwBMAQAGAAcKzxeXtwBMAQAAAA==.Sabel:BAAANQADCggIDgAAAA==.Saeriin:BAABNQAECn8UAAIJAAcKzQQ7wQC7AAAJAAcKzQQ7wQC7AAAAAA==.Saintsnyder:BAABNQAECn8nAAQIAAkKCguoPgACAQAIAAUKKRaoPgACAQAGAAgKCQUHHAHwAAAFAAEKGgHgPQEPAAAAAA==.Saithis:BAAANQAECgEIAwAAAA==.Sanorasong:BAABNQAECn8SAAMGAAcKPA7A2QASAQAGAAYK7A7A2QASAQAFAAMKng5R8gCbAAAAAA==.Saphaa:BAAANQAECgUICQAAAA==.Saphirra:BAAANQADCggIEQAAAA==.Sarylin:BAAANQAECggIDwAAAA==.Satansshadow:BAAANQADCgEIAQAAAA==.Sathona:BAAANQAECggIEgAAAA==.Sathpriest:BAABNQAECn8jAAQUAAoKNSIhDgBTAwAUAAkKTyMhDgBTAwAZAAIKyRzxGACoAAAeAAIKZQ66WAA+AAAAAA==.Sathrel:BAAANQADCgMIAwAAAA==.',
Sc='Schio:BAABNQAECn8hAAIKAAcK0hGYCQAaAQAKAAcK0hGYCQAaAQAAAA==.',
Se='Severussnape:BAABNQAECn8sAAMJAAgKuQcIuQBbAQAJAAgKrAcIuQBbAQAKAAQKlwNjTQCXAAAAAA==.',
Sh='Shamrorag:BAAANQADCgQICAAAAA==.Sharpeyez:BAAANQAECgQIBAAAAA==.She:BAABNQAECn8tAAIkAAoK2BcWEAB7AgAkAAoK2BcWEAB7AgAAAA==.Shehealz:BAAANQADCggICQAAAA==.Shekxxy:BAAANQAECgIIAwABNQAFFAQIBgABALkUAA==.Shortstack:BAAANQAECgYIDAAAAA==.',
Si='Simpmother:BAABNQAECn8YAAIJAAcK/Qi5oAABAQAJAAcK/Qi5oAABAQAAAA==.Sinensis:BAAANQAECgUIEAAAAA==.',
Sk='Skadoosh:BAAANQADCggIDQABNQAFFAcIGwASAM8WAA==.Skarletflame:BAAANQADCgMIAwAAAA==.Skarletrose:BAABNQAECn8cAAMiAAcKtQ+bOQAgAQAiAAcKtQ+bOQAgAQATAAEKqQNzqgAhAAAAAA==.Skinalittleb:BAAANQAECgQIBAAAAA==.',
Sl='Slather:BAAANQAECgMIBAAAAA==.Slaycie:BAABNQAECn8vAAIUAAkKJB6rHQDbAgAUAAkKJB6rHQDbAgAAAA==.',
Sn='Sneek:BAABNQAECn8XAAMfAAcK2Q6yFQAjAQAfAAcK2Q6yFQAjAQAaAAQKWwSOhgG4AAAAAA==.Snugglebus:BAAANQAECgIIAgAAAA==.',
So='Solaara:BAABNQAECn8dAAIGAAgK0hvlbADjAQAGAAgK0hvlbADjAQAAAA==.',
Sp='Spaghett:BAABNQAECn8hAAMjAAgKxhVDEQDUAQAjAAgKxhVDEQDUAQABAAYK6Qb8VQCUAAABNQAECgkJHQAdAFwWAA==.',
St='Stanger:BAABNQAECn8ZAAIHAAoKph7oKADAAgAHAAoKph7oKADAAgAAAA==.Starlight:BAABNQAECn8oAAIhAAoKBB/wDQC9AgAhAAoKBB/wDQC9AgABNQAECgoKTgAGADEmAA==.Stonefly:BAAANQAECgEIAgAAAA==.',
Su='Succulent:BAEANQAECgIIBgAAAA==.',
Sy='Syrden:BAABNQAECn8yAAIWAAoKMA6gKgDJAQAWAAoKMA6gKgDJAQAAAA==.Syren:BAAANQADCgEIAQAAAA==.',
Ta='Tael:BAABNQAECn81AAIPAAkKmR+aBgBCAgAPAAkKmR+aBgBCAgAAAA==.Tangylizard:BAABNQAECn8lAAMUAAoKSCJ9DABuAwAUAAoKKyJ9DABuAwAZAAUKoxSEDwAzAQAAAA==.Tawainai:BAABNQAECn8tAAIaAAgKFhK0ugAOAgAaAAgKFhK0ugAOAgAAAA==.',
Te='Tessla:BAABNQAECn86AAMNAAoKSRgELwAJAgANAAoKSRgELwAJAgAHAAIKtQGtFgE9AAAAAA==.Tetragram:BAABNQAECn9TAAIBAAoKTiQ/AwBCAwABAAoKTiQ/AwBCAwAAAA==.',
Th='Thelarï:BAABNQAECn8sAAIEAAgKCgnoqgCvAQAEAAgKCgnoqgCvAQAAAA==.Thors:BAABNQAECn84AAIGAAkKpiPHEwB3AwAGAAkKpiPHEwB3AwAAAA==.Thundertoes:BAABNQAECn8qAAMHAAgKsBc9UQC2AQAHAAgKsBc9UQC2AQANAAUKDw0KuAAiAQAAAA==.',
Ti='Tia:BAAANQADCgEIAQAAAA==.Timmy:BAAANQADCgIIAgAAAA==.Tiquandeisha:BAABNQAECn8kAAMiAAcKoBKbZAB+AQAiAAYK8RWbZAB+AQACAAMK1Qb2sgAqAAAAAA==.Titåx:BAAANQADCgYIBgAAAA==.',
To='Tonik:BAABNQAECn8bAAMNAAcKiBCXqABDAQANAAYKSQ6XqABDAQAHAAUKmwyV1AC+AAAAAA==.Torgoth:BAABNQAECn8eAAIYAAcKaQnLGwBCAQAYAAcKaQnLGwBCAQAAAA==.Toshido:BAABNQAECn8UAAIEAAcKPAmQvwAYAQAEAAcKPAmQvwAYAQAAAA==.Totemtroller:BAAANQAECgUIBwAAAA==.Toy:BAAANQAECgMIAwAAAA==.',
Tr='Trevize:BAAANQAECggIAgAAAA==.',
Tw='Twilightsoul:BAAANQAECggIAQAAAA==.',
Ub='Ubully:BAAANQADCgMIAwAAAA==.',
Ul='Ultane:BAAANQAECggIEgAAAA==.',
Un='Unholypally:BAAANQADCggIHwAAAA==.',
Va='Valashar:BAAANQADCgcIDQAAAA==.Valiantaine:BAABNQAECn9BAAQGAAoKUR3zPgDYAgAGAAoKUR3zPgDYAgAFAAcKOQQTrwAhAQAIAAMKghRCOQC2AAABNQAECgoKLgASAOYXAA==.Valiantaint:BAABNQAECn8uAAISAAoK5hdpFwDpAQASAAoK5hdpFwDpAQAAAA==.Valiantroar:BAAANQAECgYIBgABNQAECgoKLgASAOYXAA==.Vashon:BAAANQADCgQIBwAAAA==.',
Ve='Velherun:BAABNQAECn8kAAIGAAgKdxUYnADqAQAGAAgKdxUYnADqAQAAAA==.Vendel:BAABNQAECn80AAINAAoKfiQCBwCxAwANAAoKfiQCBwCxAwAAAA==.Vexxaa:BAABNQAECn8eAAIEAAcKBwyznQBcAQAEAAcKBwyznQBcAQAAAA==.',
Vi='Virajr:BAAANQAECgQICQAAAA==.Vissiction:BAABNQAECn8iAAISAAgKfxVEIwBuAQASAAgKfxVEIwBuAQAAAA==.Vistine:BAABNQAECn8hAAIIAAkKaQlYKAAaAQAIAAkKaQlYKAAaAQABNQAECgoKOgANAEkYAA==.Vitez:BAABNQAECn8YAAIJAAgKegiCtgBhAQAJAAgKegiCtgBhAQAAAA==.',
Wa='Waterslide:BAAANQADCgYIEQAAAA==.',
We='Weatherman:BAAANQADCgQIBAAAAA==.Wendy:BAABNQAECn8/AAIHAAoK6BsLTwAoAgAHAAoK6BsLTwAoAgAAAA==.',
Wh='Whack:BAAANQADCgIIAgAAAA==.Whemeo:BAAANQAECgEIAQAAAA==.Whitesox:BAAANQADCgQJBAAAAA==.',
Wi='Win:BAABNQAECn8cAAMWAAcKCwkgPQA6AQAWAAcKCwkgPQA6AQAhAAcKxAy7RAD+AAABNQAFFAIIAwARAAAAAA==.Winkster:BAABNQAECn8aAAIFAAoKJxkAIACtAgAFAAoKJxkAIACtAgAAAA==.',
Xa='Xanadu:BAABNQAECn88AAMZAAoKECEFAQBDAwAZAAoKECEFAQBDAwAUAAEKUxLD/AAyAAAAAA==.Xarinia:BAAANQAECgIIAwABNQAECgoKRAACABAOAA==.',
Xb='Xbear:BAABNQAECn8eAAIcAAcKaxUtJABLAQAcAAcKaxUtJABLAQABNQAFFAcIHQAkAK4SAA==.',
Xd='Xdynasty:BAACNQAFFH8dAAMkAAcKrhL0BgCjAQAkAAcKrhL0BgCjAQAgAAEKpBvKHABSAAA1AAQKf0IAAyQACgoBIvoHAPoCACQACgpHH/oHAPoCACAABAqmHqBXAFwBAAAA.',
Xe='Xendier:BAAANQADCgIIAgAAAA==.',
Xi='Xióngchäo:BAAANQADCgYIEgABNQAECgYIDwARAAAAAA==.',
Xo='Xo:BAAANQADCggICAABNQAFFAIIAwARAAAAAA==.',
Za='Zabazz:BAABNQAECn87AAMHAAoK7g9AOgAYAgAHAAoK7g9AOgAYAgANAAQKrQZJzwBgAAAAAA==.Zabenir:BAABNQAECn8ZAAIeAAcKJRQBHwB7AQAeAAcKJRQBHwB7AQAAAA==.Zalrote:BAAANQADCggICgABNQAECgoKRAACABAOAA==.Zaraina:BAABNQAECn8dAAMUAAcKkxRjZwCQAQAUAAcKkxRjZwCQAQAeAAEKXQfJXgAzAAABNQAFFAcIGwASAM8WAA==.',
Ze='Zerototem:BAABNQAECn8rAAMHAAgKyBeTTQAtAgAHAAgKyBeTTQAtAgANAAIKGAlsEQFpAAAAAA==.',
Zo='Zorusii:BAAANQADCgcIDQABNQAFFAcIGwASAM8WAA==.',
['Çu']='Çuddleybunny:BAAANQADCgUIBQAAAA==.',
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
