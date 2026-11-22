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

local lookup = {'DeathKnight-Frost','Monk-Windwalker','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Holy','Paladin-Retribution','Shaman-Restoration','Warlock-Demonology','Paladin-Protection','Warlock-Destruction','Warrior-Protection','Hunter-Survival','Shaman-Elemental','Evoker-Preservation','Warrior-Fury','DemonHunter-Havoc','Unknown-Unknown','DemonHunter-Devourer','DeathKnight-Blood','Priest-Holy','Warrior-Arms','Druid-Restoration','Druid-Feral','Shaman-Enhancement','Priest-Discipline','Mage-Arcane','Warlock-Affliction','Druid-Guardian','DemonHunter-Vengeance','Monk-Brewmaster','Priest-Shadow','Mage-Frost','Rogue-Assassination','Druid-Balance','Rogue-Subtlety','Rogue-Outlaw','Monk-Mistweaver','DeathKnight-Unholy',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Acaciastrain:BAAANQAECgIIAgAAAA==.',
Ad='Adorie:BAAANQAECgYIBgAAAA==.',
Ae='Aelord:BAAANQADCgUIBQAAAA==.Aerebos:BAABNQAECn8pAAIBAAoKLheYIABJAgABAAoKLheYIABJAgABNQAECgoKWAACALMkAA==.Aeriss:BAAANQABCgQIBAAAAA==.Aetheria:BAAANQADCgYJBgAAAA==.Aethos:BAABNQAECn9QAAMDAAoKryICAwAzAwADAAoKryICAwAzAwAEAAMKcBt3CQGfAAABNQAECgoKWAACALMkAA==.Aeón:BAAANQADCgMIAwABNQAECggIHAAFAFAIAA==.',
Ag='Agua:BAAANQAECgQIBAAAAA==.',
Ak='Akashá:BAABNQAECn8WAAIGAAoKQg1VngCQAQAGAAoKQg1VngCQAQAAAA==.',
Al='Aladrius:BAEANQAECgQIBwAAAA==.Alandarus:BAAANQADCgEIAQAAAA==.Alexanderath:BAAANQAECgUIAwAAAA==.Alkatractite:BAABNQAECn8hAAIGAAkKKxYShADEAQAGAAkKKxYShADEAQAAAA==.Allenwalker:BAAANQAECgYIDQAAAA==.Allison:BAAANQADCgUIBQABNQAECgoKPwAHAOgbAA==.',
Am='Amey:BAABNQAECn8UAAIIAAkK5wZhigBIAQAIAAkK5wZhigBIAQAAAA==.',
An='Anelise:BAAANQADCgUIBQAAAA==.Antelon:BAAANQAECgMIAwABNQAECgkJJwAJAAoLAA==.',
Ao='Aoeslave:BAACNQAFFH8FAAMIAAMK3wRkLgBqAAAIAAIKZwVkLgBqAAAKAAEKzgPgFQA+AAA1AAQKfzMAAwgACgpVFgF5AHMBAAgACQrIFQF5AHMBAAoAAwplElBHAKoAAAAA.',
Ar='Arrisia:BAABNQAECn8pAAIEAAcKkgo2wwArAQAEAAcKkgo2wwArAQAAAA==.Arthedain:BAABNQAECn81AAILAAoKwSJJAwBsAwALAAoKwSJJAwBsAwAAAA==.Arthedaine:BAACNQAFFH8HAAIMAAQKBxAoAQDTAAAMAAQKBxAoAQDTAAA1AAQKfysAAgwACgpZHlsCALICAAwACgpZHlsCALICAAE1AAQKCgo1AAsAwSIA.',
As='Assano:BAABNQAECn8kAAMKAAkK+BJ9BQCgAQAKAAkK+BJ9BQCgAQAIAAQKSgpOBAHDAAABNQAECgoKQAANACIZAA==.',
Au='Autumni:BAAANQADCgcIDAAAAA==.Auvry:BAABNQAECn8jAAIOAAkKrQ/XGQAlAgAOAAkKrQ/XGQAlAgAAAA==.',
Az='Azliain:BAAANQAECggIEAAAAA==.Azurine:BAAANQADCgYIBgAAAA==.',
Ba='Bahamutfang:BAABNQAECn8ZAAIGAAcKkgk75QAVAQAGAAcKkgk75QAVAQAAAA==.Bahozakurkho:BAAANQAECgMIAwABNQAECgkJFAAGAGYNAA==.Bakala:BAABNQAECn8rAAMPAAcK9wb5GgD3AAAPAAYK5Ab5GgD3AAALAAcK7AWwJgDFAAAAAA==.Barath:BAABNQAECn8UAAIQAAcKugqlSwD6AAAQAAcKugqlSwD6AAAAAA==.',
Be='Beerwench:BAAANQAECgYIDwAAAA==.Belegaer:BAABNQAECn8pAAIFAAkKigu9bQBsAQAFAAkKigu9bQBsAQAAAA==.Belenos:BAAANQAECgEIAQABNQAECgIIAQARAAAAAA==.Benmaverick:BAABNQAECn8cAAISAAkKtQ6cLgDMAQASAAkKtQ6cLgDMAQAAAA==.Bervin:BAABNQAECn8bAAITAAgKtxjJLwCPAQATAAgKtxjJLwCPAQAAAA==.',
Bi='Bifftunkisjr:BAAANQADCgEJAQAAAA==.Bishop:BAABNQAECn8zAAIUAAoKnAoNYQC9AQAUAAoKnAoNYQC9AQAAAA==.',
Bl='Blackbird:BAAANQADCgQIBAAAAA==.Bladesman:BAABNQAECn8YAAMLAAoKzxF9EACuAQALAAkKMxR9EACuAQAVAAcKEgFnGgFJAAAAAA==.',
Bo='Bobe:BAABNQAECn9UAAMLAAoK2CAzBADsAgALAAoK2CAzBADsAgAVAAUKCww2xwDmAAAAAA==.Bobedruid:BAAANQAECgQIBAAAAA==.Bordok:BAABNQAECn8aAAIBAAgKiQfKagDxAAABAAgKiQfKagDxAAAAAA==.Borkuz:BAAANQADCggJCAAAAA==.',
Br='Brawl:BAAANQADCgYIBgAAAA==.Brunco:BAABNQAECn8wAAMEAAoKUBn/TACHAgAEAAoKUBn/TACHAgADAAEK0QpxiQA1AAAAAA==.',
Ca='Captplanet:BAABNQAECn88AAMWAAoK2xl/FAClAgAWAAoK2xl/FAClAgAXAAgKmhvEFQCfAQAAAA==.',
Ce='Ceindra:BAACNQAFFH8JAAIYAAUKPApjAwDzAAAYAAUKPApjAwDzAAA1AAQKfy0AAhgACgonGs0KAMUCABgACgonGs0KAMUCAAAA.Celestria:BAABNQAECn8bAAMZAAYKwAsWCgACAQAZAAYKwAsWCgACAQAUAAEKHwFZDQEYAAAAAA==.Celiñ:BAAANQAECgYIDAAAAA==.Cerealkiller:BAAANQADCgYIBgAAAA==.',
Ch='Chipcho:BAAANQADCggICAAAAA==.Chockula:BAAANQADCgMIAwAAAA==.Chuladk:BAAANQAECgEIAQAAAA==.',
Co='Coachney:BAAANQADCgEIAQAAAA==.Colbalt:BAAANQAECgQIBgAAAA==.Constantinez:BAABNQAECn8XAAIKAAoKIQJ6QwC3AAAKAAoKIQJ6QwC3AAAAAA==.Cor:BAAANQAECgMIBAAAAA==.',
Cr='Crackerzz:BAAANQAECgYICgAAAA==.',
Cu='Cuddlymethod:BAAANQADCgYICQAAAA==.',
['Có']='Cól:BAABNQAECn87AAIaAAoKAht6RwA3AgAaAAoKAht6RwA3AgAAAA==.Cónky:BAAANQADCgcIBQAAAA==.',
Da='Daddymoo:BAAANQADCgUIDAAAAA==.Daesong:BAAANQADCgEIAQABNQAECgkJFAAGAGYNAA==.Dahealzrhere:BAAANQADCgEIAQAAAA==.Dalel:BAACNQAFFH8bAAMSAAcKzxbuAwBbAQASAAcKzxbuAwBbAQAQAAEKdgCDHQAsAAA1AAQKf0cAAxIACgqVIOkNAAkDABIACgqVIOkNAAkDABAAAQoAADySADYAAAAA.Dameond:BAAANQADCgQICAAAAA==.David:BAABNQAECn8WAAIVAAgKlRr+YABrAgAVAAgKlRr+YABrAgABNQAECgoKMwAEAMwdAA==.',
De='Deadlyglow:BAABNQAECn8aAAMTAAgKpxpaPgAHAgATAAcK7BhaPgAHAgABAAYKDBdDWABKAQAAAA==.Demiurgos:BAABNQAECn8XAAMHAAoKEhb1WwD7AQAHAAoKEhb1WwD7AQANAAYKGAwqjAD0AAAAAA==.Denji:BAAANQADCggIBgAAAA==.Denogarn:BAAANQADCggIEQAAAA==.Dermot:BAABNQAECn8jAAQbAAkKViCSCwCxAQAIAAgK7RxDfQDtAQAbAAYK7BuSCwCxAQAKAAIK9RzJSgCfAAAAAA==.',
Dh='Dhiying:BAAANQADCgcIBwAAAA==.',
Di='Dirtface:BAABNQAECn9BAAIVAAoKwAg6igBvAQAVAAoKwAg6igBvAQAAAA==.Dixlongmd:BAAANQAECgEIAQAAAA==.Dixmen:BAABNQAECn8wAAIGAAkKdRaZcwBHAgAGAAkKdRaZcwBHAgAAAA==.',
Do='Dolemen:BAABNQAECn8vAAIGAAgKvwQEAAHpAAAGAAgKvwQEAAHpAAAAAA==.Domaon:BAABNQAECn86AAIQAAoKKCB6DwC1AgAQAAoKKCB6DwC1AgAAAA==.Domshammy:BAAANQADCggICAABNQAECgoKOgAQACggAA==.Doubt:BAAANQAECgUIDAAAAA==.Doughug:BAAANQAECgMIAwABNQAECgQIBAARAAAAAA==.Dozy:BAACNQAFFH8FAAIGAAMKqxnnEQD1AAAGAAMKqxnnEQD1AAA1AAQKf0IAAgYACgrfIyURACQDAAYACgrfIyURACQDAAAA.',
Dr='Dracania:BAAANQADCgEIAQAAAA==.Druidheelzz:BAAANQAECgUICAAAAA==.Druissh:BAAANQAECgYICwABNQAECgoKQAANACIZAA==.Drôôdude:BAAANQADCgQIBAAAAA==.',
Du='Dullgrim:BAAANQADCggICAAAAA==.Dunigan:BAABNQAECn87AAIGAAkKkg5mpgCCAQAGAAkKkg5mpgCCAQAAAA==.Dunigen:BAABNQAECn8iAAMBAAcKUg3hYAAVAQABAAcKUg3hYAAVAQATAAYKLww8YQDAAAAAAA==.',
Eb='Ebeast:BAABNQAECn9AAAIMAAoK5hEGBQB9AgAMAAoK5hEGBQB9AgAAAA==.',
Ef='Efel:BAAANQADCggICAAAAA==.',
Ev='Evianda:BAAANQADCggIEAAAAA==.',
Fa='Fabulist:BAAANQADCgQIBAAAAA==.Facade:BAABNQAECn8fAAITAAgKgwrGXwByAQATAAgKgwrGXwByAQAAAA==.Facepalm:BAABNQAECn8eAAMPAAgKPBf+CQAwAgAPAAgKPBf+CQAwAgAVAAQKfwjaGgGmAAAAAA==.Falyy:BAAANQADCgMIAwAAAA==.Farmergeorge:BAAANQAECgQJCAAAAA==.',
Fe='Fentak:BAAANQAECgEIAQAAAA==.',
Fi='Fierytotes:BAAANQADCggIFQABNQAECgoKGAALAM8RAA==.Finnek:BAAANQADCgMIAwAAAA==.',
Fo='Forbidenelf:BAACNQAFFH8NAAIGAAQKUxnOEgDuAAAGAAQKUxnOEgDuAAA1AAQKf0EAAgYACQrSIdcbAPECAAYACQrSIdcbAPECAAAA.Forging:BAAANQADCgQIBAAAAA==.Forgotmymeds:BAAANQAECgQICAAAAA==.Foxmccloud:BAABNQAECn8eAAMHAAYKjiKQQwAFAgAHAAYKjiKQQwAFAgANAAMKCwn4DgFuAAAAAA==.',
Fr='Fridge:BAACNQAFFH8GAAMDAAMKrgHSGACPAAADAAMKiwHSGACPAAAEAAEKzAE1OQAxAAA1AAQKfxYAAwQACQq0D0pfAAkCAAQACQq0D0pfAAkCAAMABAqeDKIxAOUAAAAA.Frosted:BAAANQADCggIAgAAAA==.Fruitloop:BAABNQAECn8tAAIaAAkKxhYebQDYAQAaAAkKxhYebQDYAQAAAA==.',
Fu='Funkybooty:BAAANQABCgIIAgAAAA==.Fuzybrewing:BAAANQABCgQICAAAAA==.',
Ge='Gebran:BAABNQAECn8/AAIGAAkKVQpfxQBKAQAGAAkKVQpfxQBKAQAAAA==.Gellywoo:BAABNQAECn9AAAIVAAoKPxlFNQBqAgAVAAoKPxlFNQBqAgAAAA==.Gemmarolizzy:BAAANQAECgQIBgAAAA==.Geneviève:BAAANQADCgQIBAAAAA==.',
Go='Golaoth:BAABNQAECn8gAAIOAAkKWxPVDgAhAgAOAAkKWxPVDgAhAgAAAA==.Gooftroupe:BAABNQAECn8xAAIFAAoKsB/OGwDbAgAFAAoKsB/OGwDbAgAAAA==.',
Gr='Grandmaster:BAABNQAECn8WAAIaAAgK3AiCxwAZAQAaAAgK3AiCxwAZAQABNQAECgEIAQARAAAAAA==.Grawn:BAAANQADCgMIAwAAAA==.Greymoon:BAABNQAECn8qAAIcAAcKmRXsKgA0AQAcAAcKmRXsKgA0AQAAAA==.Grimaced:BAAANQAECgYIBgABNQAECgkJOAAGAKYjAA==.Grimtotems:BAAANQADCgMIAwAAAA==.',
Ha='Haezi:BAABNQAECn8fAAQdAAoKEhhMCQDZAQAdAAgKXBlMCQDZAQAQAAcKcxC3RwAPAQASAAEKAAAGcgArAAABNQAECgoKJAAeAIAUAA==.Haki:BAAANQABCgIIAgAAAA==.Hammerbully:BAAANQADCgEIAQAAAA==.Happyendings:BAAANQAECgUICQAAAA==.',
He='Helbafx:BAAANQADCggIQwAAAA==.',
Hi='Hino:BAABNQAECn8XAAMUAAgKNBLCawDbAQAUAAgKNBLCawDbAQAfAAEKDQdXZQAyAAAAAA==.',
Ho='Holywarriors:BAAANQAECgQIBQAAAA==.Homewrecker:BAABNQAECn8cAAILAAYKPxZaHgBhAQALAAYKPxZaHgBhAQAAAA==.Horuid:BAAANQADCgEIAQAAAA==.',
Hu='Huntzman:BAAANQADCgUIBgAAAA==.Huské:BAAANQAECgIIAgAAAA==.',
Ic='Icebully:BAAANQAECgIIAgAAAA==.Icemàn:BAAANQAECgQIBQAAAA==.',
Id='Idrazil:BAAANQAECgcIEAAAAA==.',
If='Ifearnobeer:BAAANQAECgMIBAAAAA==.',
In='Infectz:BAAANQAECggIAgAAAA==.Infoxicated:BAAANQADCgQIBAAAAA==.',
Is='Isabel:BAAANQAECgEIAgAAAA==.',
It='Itburnsalot:BAAANQADCgYIBgAAAA==.',
Ja='Jaiantobea:BAACNQAFFH8aAAIHAAcKzh/7AwCIAgAHAAcKzh/7AwCIAgA1AAQKf2EAAwcACgr5JOMDAOUDAAcACgr5JOMDAOUDAA0AAQrjFOrsAEMAAAAA.Jakik:BAAANQADCgUICgAAAA==.Jakulista:BAAANQADCgEIAQAAAA==.Jarlaxl:BAAANQADCgQIBAAAAA==.Jawn:BAAANQAECggIDgAAAA==.',
Je='Jessuss:BAABNQAECn8WAAIGAAcKwgpG+AAtAQAGAAcKwgpG+AAtAQAAAA==.',
Jh='Jha:BAABNQAECn8YAAMdAAgKPR5eDAABAgAdAAcKPR5eDAABAgAQAAYKnhJKSwB1AQAAAA==.',
Ju='Jude:BAABNQAECn8uAAIGAAoK3BgNdQBEAgAGAAoK3BgNdQBEAgAAAA==.Junipermoon:BAAANQAECgIIAQAAAA==.',
Ka='Kabub:BAAANQAECgYIEQAAAA==.Kalahandra:BAABNQAECn8bAAIWAAgKkxHtKADYAQAWAAgKkxHtKADYAQAAAA==.Kalebeesd:BAAANQADCgUIBwAAAA==.Katablight:BAAANQAECggIEQABNQAFFAUIBgAIABQaAA==.Katotan:BAABNQAECn8wAAIWAAkK1xXJJAD+AQAWAAkK1xXJJAD+AQAAAA==.Kawk:BAAANQAECgMIAwAAAA==.',
Ke='Kealestra:BAABNQAECn8WAAIgAAUKGg6FHAALAQAgAAUKGg6FHAALAQAAAA==.Keyboärd:BAABNQAECn8YAAILAAgK1xniDwC5AQALAAgK1xniDwC5AQAAAA==.',
Ki='Kimochi:BAAANQAECgQIBAAAAA==.Kippo:BAAANQADCgcIBwABNQAECgcICAARAAAAAA==.Kittylover:BAAANQAECgIIAgAAAA==.',
Ko='Kombat:BAAANQADCgYJCgAAAA==.Korllan:BAAANQAECgEIAQAAAA==.Kossnen:BAABNQAECn8cAAQbAAgKERR7EwD/AAAIAAQKUhYA0gAmAQAbAAUKIxJ7EwD/AAAKAAIKERYOHgB4AAAAAA==.',
Kr='Krestisnack:BAABNQAECn8UAAIKAAUKjxZ1IgBdAQAKAAUKjxZ1IgBdAQAAAA==.',
Ku='Kuda:BAABNQAECn8qAAIgAAoKqhT6CgDyAQAgAAoKqhT6CgDyAQAAAA==.Kullkil:BAAANQADCggIEQAAAA==.',
Kw='Kwanu:BAAANQAECgUIDAAAAA==.',
['Kñ']='Kño:BAAANQADCgMIAwABNQAECggIHAAFAFAIAA==.',
['Kó']='Kóñä:BAABNQAECn8cAAMFAAgKUAi6iwAVAQAFAAgKUAi6iwAVAQAJAAEKAADSfwAdAAAAAA==.',
La='Larke:BAAANQAECgEIAQAAAA==.Lasa:BAAANQAECgMIAgAAAA==.Lasloo:BAABNQAECn8+AAIGAAoKOBN5aQD9AQAGAAoKOBN5aQD9AQAAAA==.Laylani:BAABNQAECn9MAAIJAAoKtBKIHACMAQAJAAoKtBKIHACMAQAAAA==.',
Le='Lebronjames:BAAANQAECgUICgAAAA==.Leynreite:BAAANQAECgUICQAAAA==.',
Li='Lisan:BAABNQAECn87AAIaAAoKCBR/VgAPAgAaAAoKCBR/VgAPAgAAAA==.Littledicey:BAABNQAECn9CAAIhAAoKlA2rEgCjAQAhAAoKlA2rEgCjAQAAAA==.',
Lu='Luciä:BAABNQAECn8dAAITAAcKqQxHUgD0AAATAAcKqQxHUgD0AAAAAA==.Lucymoon:BAAANQAECgYIBgAAAA==.Luvflap:BAAANQADCgMIAwAAAA==.',
Ly='Lykaios:BAAANQABCgQIBAAAAA==.Lyñx:BAAANQADCgQIBgAAAA==.',
Ma='Machoman:BAAANQAECgQIBAAAAA==.Madness:BAABNQAECn8hAAIfAAoKKgxRMwCIAQAfAAoKKgxRMwCIAQAAAA==.Maerion:BAABNQAECn8eAAMDAAYKMwV7OwCyAAAEAAUK1gLNEwHdAAADAAYKMwV7OwCyAAAAAA==.Magdeth:BAABNQAECn8sAAINAAoKXRFlPwDXAQANAAoKXRFlPwDXAQAAAA==.Mantra:BAAANQAECgUIBQAAAA==.Maphra:BAAANQABCgUIBwAAAA==.Marabelle:BAABNQAECn8XAAIiAAgKuAaxXwBRAQAiAAgKuAaxXwBRAQAAAA==.Marasteil:BAAANQADCgIIAgAAAA==.Mariomage:BAAANQADCgQICAAAAA==.Marixia:BAAANQAECgUICgAAAA==.Marrow:BAAANQADCgYIBgAAAA==.Masilitu:BAAANQADCgYIDwAAAA==.Massack:BAABNQAECn8vAAIeAAkKAhdrCADRAQAeAAkKAhdrCADRAQAAAA==.Mawgwa:BAAANQAECgMIAwAAAA==.',
Mc='Mcwrath:BAAANQADCgcIDQABNQAECgkJJwAJAAoLAA==.',
Me='Meeow:BAAANQADCgEIAQABNQAECgoKJAAeAIAUAA==.Mero:BAABNQAECn8oAAQIAAoKSB5hMADGAgAIAAkKmB1hMADGAgAKAAIKHRnnSwCcAAAbAAEKSQqULgA2AAAAAA==.',
Mi='Midgetmàniàc:BAAANQADCggICAAAAA==.',
Mo='Moiraine:BAAANQAECgUICQAAAA==.Monkeywrench:BAAANQADCgIIAwAAAA==.Moobear:BAAANQADCgUIBQAAAA==.Moonshiner:BAAANQAECgQIBAAAAA==.Mosimo:BAAANQABCgIIAgAAAA==.Moushuhan:BAABNQAECn8oAAMjAAkKrBT2GQAJAgAjAAkKVxT2GQAJAgAhAAIKqRLwiwCBAAAAAA==.',
My='Mystrall:BAAANQAECgQIBAAAAA==.',
Na='Naanaa:BAABNQAECn8cAAIaAAkKqhG/vwAFAgAaAAkKqhG/vwAFAgAAAA==.Nadorian:BAAANQABCgIIAgAAAA==.Narey:BAAANQADCgIIAgAAAA==.',
Ne='Neb:BAAANQAECgEIAQAAAA==.Netherrogue:BAACNQAFFH8MAAQkAAYKHRLRAQD7AAAkAAMKcRXRAQD7AAAjAAIKWxHnIgBdAAAhAAIKNgy8HABSAAA1AAQKfyYABCQACgrOJA0EANcCACQABwqtJA0EANcCACEABApRHiI8AJsAACMAAQrMJKbAAGsAAAAA.',
Nu='Nuke:BAAANQAECggIDAABNQAFFAMIBgADAK4BAA==.',
Ny='Nytemayer:BAABNQAECn8gAAMIAAkKNRwmWQBLAgAIAAgKuxwmWQBLAgAKAAMKtRPnQwC1AAABNQAFFAQICgASABUMAA==.Nytè:BAACNQAFFH8KAAISAAQKFQy1CQDHAAASAAQKFQy1CQDHAAA1AAQKfx4AAhIACAp2GNAsANsBABIACAp2GNAsANsBAAAA.',
Ob='Obmakare:BAABNQAECn8hAAMXAAcKJwkJIAAXAQAXAAYKrQoJIAAXAQAWAAUKEQYFWACYAAAAAA==.Obonhigh:BAAANQADCgEIAQAAAA==.Oboñ:BAABNQAECn8cAAIbAAcKeAe/FADrAAAbAAcKeAe/FADrAAAAAA==.Obsfuyung:BAAANQAECgUICgAAAA==.',
Oo='Oopsiez:BAAANQAECgUIBwAAAA==.',
Op='Opiiknight:BAAANQAECgQIBwAAAA==.Opiipal:BAAANQADCgIIAgAAAA==.Opiishift:BAACNQAFFH8GAAIiAAMKSQa4FgC3AAAiAAMKSQa4FgC3AAA1AAQKfykAAiIACgrKF+YxAFQCACIACgrKF+YxAFQCAAAA.Opiishots:BAABNQAECn8eAAIEAAoKZhpaLwCGAgAEAAoKZhpaLwCGAgAAAA==.',
Or='Orcc:BAAANQADCggIHQAAAA==.',
Pa='Paley:BAAANQAECgQICAAAAA==.',
Pd='Pdgrimm:BAAANQADCgQIBAAAAA==.',
Pe='Peavey:BAAANQADCgEIAQAAAA==.Peligrosa:BAAANQAECggIDgABNQAECgEIAQARAAAAAA==.Performance:BAABNQAECn8/AAQdAAoKryIOAgAOAwAdAAoKryIOAgAOAwASAAMKPRJ+RgB/AAAQAAEKBBURfQBDAAAAAA==.Peterturbo:BAAANQAECgQICAABNQABCgIIAgARAAAAAA==.',
Pi='Pinkky:BAAANQADCgcIBwAAAA==.',
Po='Pocketfox:BAAANQAECgMIBQAAAA==.Poisonoak:BAAANQABCgIIAgAAAA==.Poîsonivy:BAABNQAECn8gAAIKAAkKbgv2CQAnAQAKAAkKbgv2CQAnAQAAAA==.',
Ps='Psyrine:BAAANQAECgUIBQAAAA==.',
Py='Pyrö:BAABNQAECn8jAAIaAAkKowOM8QDMAAAaAAkKowOM8QDMAAAAAA==.',
['Pü']='Püff:BAAANQAECgIIAgAAAA==.',
Qu='Qu:BAABNQAECn9AAAIVAAoKox/UKgCUAgAVAAoKox/UKgCUAgAAAA==.',
Ra='Raega:BAAANQAECgEIAQAAAA==.Rakdoc:BAAANQADCgQIBAAAAA==.Rattlesnake:BAAANQADCggIMgAAAA==.Raymonnd:BAAANQAECgQIBAAAAA==.',
Re='Reborn:BAAANQADCgUIBQABNQAECgoKJgAVAMoPAA==.Reflektor:BAAANQABCgQIBAAAAA==.Renägäde:BAAANQAECgcIEAAAAA==.Retiredfurry:BAABNQAECn86AAMlAAoK6yIlCAAPAwAlAAoK6yIlCAAPAwACAAgKcx4sFwAAAgAAAA==.',
Ri='Ricodadawg:BAABNQAECn9DAAIaAAoKRCNqIABYAwAaAAoKRCNqIABYAwAAAA==.',
Ro='Roosk:BAAANQADCgUIBQAAAA==.Roshak:BAAANQADCgYIDQAAAA==.Rotspawn:BAAANQAECggJCAAAAA==.',
Ru='Runningbearr:BAAANQADCggIEgAAAA==.Runningdemon:BAAANQADCgYICwABNQAECgoKJwANABENAA==.Runningshama:BAABNQAECn8nAAMNAAoKEQ2iXgBrAQANAAoKEQ2iXgBrAQAHAAEK+hL3/gAuAAAAAA==.Rurahk:BAAANQAECgYIDwAAAA==.',
['Rõ']='Rõbb:BAAANQAECgEIAQAAAA==.',
Sa='Sabaak:BAABNQAECn8pAAIGAAkKDxcefgDRAQAGAAkKDxcefgDRAQAAAA==.Sabel:BAAANQADCggIDgAAAA==.Saeriin:BAABNQAECn8XAAIIAAkK2QV4nQAdAQAIAAkK2QV4nQAdAQAAAA==.Saintsnyder:BAABNQAECn8nAAQJAAkKCguoPgACAQAJAAUKKRaoPgACAQAGAAgKCQUHHAHwAAAFAAEKGgHgPQEPAAAAAA==.Saithis:BAAANQAECgEIAwAAAA==.Sanorasong:BAABNQAECn8UAAQGAAkKZg3N6QANAQAGAAYK7A7N6QANAQAFAAMKng5R8gCbAAAJAAIKYQhTawAqAAAAAA==.Saphaa:BAAANQAECgUICQAAAA==.Saphirra:BAAANQADCggIEQAAAA==.Sarylin:BAAANQAECggIDgAAAA==.Satansshadow:BAAANQADCgEIAQAAAA==.Sathona:BAAANQAECggIEQAAAA==.Sathpriest:BAABNQAECn8jAAQUAAoKNSIhDgBTAwAUAAkKTyMhDgBTAwAZAAIKyRzxGACoAAAfAAIKZQ5VXgA+AAAAAA==.Sathrel:BAAANQADCgMIAwAAAA==.',
Sc='Schio:BAABNQAECn8pAAIKAAgK1BIoBwBkAQAKAAgK1BIoBwBkAQAAAA==.Schmunkybbw:BAABNQAECn8cAAQcAAkKZhD9KwAtAQAcAAkKcw39KwAtAQAiAAMKZRzBXgCnAAAXAAIKIxHjNwBtAAABNQAECgoKHwAmAKMfAA==.',
Se='Severussnape:BAABNQAECn8vAAMIAAkKDQhVjwA9AQAIAAkKAQhVjwA9AQAKAAQKlwNjTQCXAAAAAA==.',
Sh='Shamrorag:BAAANQADCgQICAAAAA==.Sharpeyez:BAAANQAECgQIBAAAAA==.She:BAABNQAECn8tAAIjAAoK2BcWEAB7AgAjAAoK2BcWEAB7AgAAAA==.Shehealz:BAAANQADCggICQAAAA==.Shekxxy:BAAANQAECgIIAwABNQAFFAQIBwACALkUAA==.Shinron:BAAANQADCgQIBAAAAA==.Shortstack:BAAANQAECgYIDAAAAA==.',
Si='Simpmother:BAABNQAECn8fAAIIAAcKAgnHqQABAQAIAAcKAgnHqQABAQAAAA==.Sinensis:BAAANQAECgYIDwAAAA==.',
Sk='Skadoosh:BAAANQADCggIDQABNQAFFAcIGwASAM8WAA==.Skarletflame:BAAANQADCgMIAwAAAA==.Skarletrose:BAABNQAECn8eAAMmAAkKEA/9PAAfAQAmAAcKtQ/9PAAfAQATAAMKbgd3kwBHAAAAAA==.Skinalittleb:BAAANQAECgQIBAAAAA==.',
Sl='Slather:BAAANQAECgMIAwAAAA==.Slaycie:BAABNQAECn85AAIUAAkKVB4OHgDsAgAUAAkKVB4OHgDsAgAAAA==.',
Sn='Sneek:BAABNQAECn8YAAMgAAgK0w7WEgBgAQAgAAgK0w7WEgBgAQAaAAQKWwSOhgG4AAAAAA==.Snugglebus:BAAANQAECgIIAgAAAA==.',
So='Solaara:BAABNQAECn8dAAIGAAgK0huseADdAQAGAAgK0huseADdAQAAAA==.Sorne:BAAANQABCgQIBAABNQAECgoKXAAHAFklAA==.',
Sp='Spaghett:BAABNQAECn8kAAMeAAoKgBRDEQDUAQAeAAgKxhVDEQDUAQACAAgKqAruPwCyAAAAAA==.',
St='Stanger:BAABNQAECn8ZAAIHAAoKph7oKADAAgAHAAoKph7oKADAAgAAAA==.Starlight:BAABNQAECn8rAAIiAAoKBB+2DQDMAgAiAAoKBB+2DQDMAgABNQAECgoKVgAGADEmAA==.Stonefly:BAAANQAECgEIAQAAAA==.',
Su='Succulent:BAEANQAECgIIBgAAAA==.',
Sy='Syrden:BAABNQAECn8yAAIWAAoKMA6gKgDJAQAWAAoKMA6gKgDJAQAAAA==.Syren:BAAANQADCgEIAQAAAA==.',
Ta='Tael:BAABNQAECn82AAIPAAkKmR+HBwA7AgAPAAkKmR+HBwA7AgAAAA==.Tangylizard:BAACNQAFFH8GAAIUAAMKDB5pGgAhAQAUAAMKDB5pGgAhAQA1AAQKfykAAxQACgpIIswOAGUDABQACgorIswOAGUDABkABQqjFIQPADMBAAAA.Tawainai:BAABNQAECn8tAAIaAAgKFhK0ugAOAgAaAAgKFhK0ugAOAgAAAA==.',
Te='Tessla:BAABNQAECn9AAAMNAAoKIhnOMAAVAgANAAoKIhnOMAAVAgAHAAIKtQGtFgE9AAAAAA==.Tetragram:BAABNQAECn9YAAICAAoKsyRoAgBaAwACAAoKsyRoAgBaAwAAAA==.',
Th='Thelarï:BAABNQAECn8vAAIEAAkKGgnoqgCvAQAEAAkKGgnoqgCvAQAAAA==.Thors:BAABNQAECn84AAIGAAkKpiPHEwB3AwAGAAkKpiPHEwB3AwAAAA==.Thundertoes:BAABNQAECn8qAAMHAAgKsBe7WQCuAQAHAAgKsBe7WQCuAQANAAUKDw0KuAAiAQAAAA==.',
Ti='Tia:BAAANQADCgEIAQAAAA==.Timmy:BAAANQADCgIIAgAAAA==.Tiquandeisha:BAABNQAECn8rAAMmAAcKoBKbZAB+AQAmAAYK8RWbZAB+AQABAAMK1QYmvQAoAAAAAA==.Titåx:BAAANQADCgYIBgAAAA==.',
To='Tobias:BAAANQADCgEIAQAAAA==.Tonik:BAABNQAECn8bAAMNAAcKiBCXqABDAQANAAYKSQ6XqABDAQAHAAUKmwyV1AC+AAAAAA==.Torgoth:BAABNQAECn8gAAIYAAkKIQpAGQCBAQAYAAkKIQpAGQCBAQAAAA==.Toshido:BAABNQAECn8UAAIEAAcKPAmBzQAXAQAEAAcKPAmBzQAXAQAAAA==.Totemtroller:BAAANQAECgUIBAAAAA==.Toy:BAAANQAECgMIAwAAAA==.',
Tr='Trevize:BAAANQAECggIAgAAAA==.',
Tw='Twilightsoul:BAAANQAECggIAQAAAA==.',
Ub='Ubully:BAAANQADCgMIAwAAAA==.',
Ul='Ultane:BAAANQAECggIEAAAAA==.',
Un='Unholypally:BAAANQADCggIHwAAAA==.',
Va='Valashar:BAAANQADCgcIDQAAAA==.Valiantaine:BAABNQAECn9BAAQGAAoKUR3zPgDYAgAGAAoKUR3zPgDYAgAFAAcKOQQTrwAhAQAJAAMKghSRPQC1AAABNQAFFAMIBQASAGIMAA==.Valiantaint:BAACNQAFFH8FAAISAAMKYgwsCQDPAAASAAMKYgwsCQDPAAA1AAQKfzIAAhIACgrmF84YAOsBABIACgrmF84YAOsBAAAA.Valiantroar:BAAANQAECgYIBgABNQAFFAMIBQASAGIMAA==.Vashon:BAAANQADCgQIBwAAAA==.',
Ve='Velherun:BAABNQAECn8nAAIGAAkKxRMYnADqAQAGAAkKxRMYnADqAQAAAA==.Vendel:BAABNQAECn80AAINAAoKfiQCBwCxAwANAAoKfiQCBwCxAwAAAA==.Vexxaa:BAABNQAECn8gAAIEAAkKcgs5lwCGAQAEAAkKcgs5lwCGAQAAAA==.',
Vi='Virajr:BAAANQAECgQICQAAAA==.Vissiction:BAABNQAECn8lAAISAAkKThUiHwCqAQASAAkKThUiHwCqAQAAAA==.Vistine:BAABNQAECn8nAAIJAAoKMAm1JQBCAQAJAAoKMAm1JQBCAQABNQAECgoKQAANACIZAA==.Vitez:BAABNQAECn8aAAIIAAkKxAeCtgBhAQAIAAkKxAeCtgBhAQAAAA==.',
Wa='Waterslide:BAAANQADCgYIEgAAAA==.',
We='Weatherman:BAAANQADCgQIBAAAAA==.Wendy:BAABNQAECn8/AAIHAAoK6BsLTwAoAgAHAAoK6BsLTwAoAgAAAA==.',
Wh='Whack:BAAANQADCgIIAgAAAA==.Whemeo:BAAANQAECgEIAQAAAA==.Whitesox:BAAANQADCgQIBAAAAA==.',
Wi='Win:BAABNQAECn8cAAMWAAcKCwkgPQA6AQAWAAcKCwkgPQA6AQAiAAcKxAwxSQD9AAABNQAFFAMIBgADAK4BAA==.Winkster:BAABNQAECn8cAAIFAAoKqxkqIgCwAgAFAAoKqxkqIgCwAgAAAA==.',
Xa='Xanadu:BAABNQAECn9CAAMZAAoKXCJkAADXAwAZAAoKXCJkAADXAwAUAAEKUxLD/AAyAAAAAA==.Xarinia:BAAANQAECgIIAgABNQAECgoKRgABAHgOAA==.',
Xb='Xbear:BAABNQAECn8eAAIcAAcKaxVNKABFAQAcAAcKaxVNKABFAQABNQAFFAcIHQAjAK4SAA==.',
Xd='Xdynasty:BAACNQAFFH8dAAMjAAcKrhJWCACjAQAjAAcKrhJWCACjAQAhAAEKpBvKHABSAAA1AAQKf0UAAyMACgpRIvoHAPoCACMACgqWH/oHAPoCACEABAqmHqBXAFwBAAAA.',
Xe='Xendier:BAAANQADCgIIAgAAAA==.',
Xi='Xióngchäo:BAAANQADCgYIEgABNQAECgYIDQARAAAAAA==.',
Xo='Xo:BAAANQADCggICAABNQAFFAMIBgADAK4BAA==.',
Za='Zabazz:BAABNQAECn88AAMHAAoK7g8yQAATAgAHAAoK7g8yQAATAgANAAQKrQY12gBgAAAAAA==.Zabenir:BAABNQAECn8ZAAIfAAcKJRSIIQB7AQAfAAcKJRSIIQB7AQAAAA==.Zalrote:BAAANQADCggICgABNQAECgoKRgABAHgOAA==.Zaraina:BAABNQAECn8dAAMUAAcKkxQIcQCJAQAUAAcKkxQIcQCJAQAfAAEKXQezZAAzAAABNQAFFAcIGwASAM8WAA==.',
Ze='Zerototem:BAABNQAECn8rAAMHAAgKyBeTTQAtAgAHAAgKyBeTTQAtAgANAAIKGAlsEQFpAAAAAA==.',
Zi='Zinic:BAAANQADCgIIAgAAAA==.',
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
