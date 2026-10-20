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

local lookup = {'Monk-Windwalker','Hunter-Marksmanship','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Shaman-Restoration','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warrior-Protection','Hunter-Survival','Shaman-Elemental','Evoker-Preservation','Paladin-Holy','DemonHunter-Devourer','Priest-Holy','Druid-Restoration','Druid-Feral','Shaman-Enhancement','Mage-Arcane','DemonHunter-Havoc','Warrior-Arms','Warlock-Affliction','DeathKnight-Blood','Warrior-Fury','Monk-Brewmaster','Priest-Shadow','DemonHunter-Vengeance','Mage-Frost','Rogue-Assassination','Druid-Balance','Rogue-Subtlety','Rogue-Outlaw','Monk-Mistweaver','Priest-Discipline','DeathKnight-Frost','Druid-Guardian',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Acaciastrain:BAAANQADCggIDwAAAA==.',
Ae='Aelord:BAAANQADCgUIBQAAAA==.Aerebos:BAAANQAECgUIDQABNQAECgoKOwABAEceAA==.Aeriss:BAAANQABCgQIBAAAAA==.Aetheria:BAAANQADCgYJBgAAAA==.Aethos:BAABNQAECn8gAAMCAAoKvRl4EwDFAgACAAoK/Bh4EwDFAgADAAMK0hj4rQBYAAABNQAECgoKOwABAEceAA==.Aeón:BAAANQADCgMIAwABNQAECgQIDgAEAAAAAA==.',
Ag='Agua:BAAANQAECgQIBQAAAA==.',
Ak='Akashá:BAAANQADCgEIAQAAAA==.',
Al='Aladrius:BAEANQAECgQIBwAAAA==.Alexanderath:BAAANQAECgYICAAAAA==.Alkatractite:BAABNQAECn8XAAIFAAgKPRXtNQBfAQAFAAgKPRXtNQBfAQAAAA==.Allenwalker:BAAANQAECgYIDgAAAA==.Allison:BAAANQADCgUIBQABNQAECgkJLwAGAMoXAA==.',
Am='Amey:BAAANQAECgMIBQAAAA==.',
An='Anelise:BAAANQADCgUIBQAAAA==.Antelon:BAAANQAECgMIAwABNQAECgkJJwAHAAoLAA==.',
Ao='Aoeslave:BAABNQAECn8sAAMIAAoK8xIoHQB7AQAIAAkK6hEoHQB7AQAJAAMKZRJQRwCqAAABNQAFFAIIAgAEAAAAAA==.',
Ap='Apk:BAAANQAECgEIAwAAAA==.',
Ar='Arrisia:BAAANQAECgYIEAAAAA==.Arthedain:BAABNQAECn8nAAIKAAoKpyDBAAC9AgAKAAoKpyDBAAC9AgAAAA==.Arthedaine:BAACNQAFFH8GAAILAAQKBxA0AQAMAQALAAQKBxA0AQAMAQA1AAQKfxoAAgsACgrDGZ4CAAkDAAsACgrDGZ4CAAkDAAE1AAQKCgonAAoApyAA.',
As='Assano:BAABNQAECn8bAAMJAAgKfw8bBgDEAAAJAAYKWw8bBgDEAAAIAAQKSgpOBAHDAAABNQAECgkJJwAMACAYAA==.',
Au='Auvry:BAABNQAECn8jAAINAAkKrQ/XGQAlAgANAAkKrQ/XGQAlAgAAAA==.',
Az='Azliain:BAAANQAECggICAAAAA==.Azurine:BAAANQADCgYIBgAAAA==.',
Ba='Bahamutfang:BAABNQAECn8VAAIFAAUKpgklgQDKAAAFAAUKpgklgQDKAAAAAA==.Bahozakurkho:BAAANQAECgMIAwABNQAECgUIDAAEAAAAAA==.Bakala:BAAANQAECgYIEgAAAA==.Barath:BAAANQAECgUIDAAAAA==.',
Be='Belegaer:BAABNQAECn8dAAIOAAgKDQSkrQAlAQAOAAgKDQSkrQAlAQAAAA==.Belenos:BAAANQAECgEIAwABNQAECgEIAwAEAAAAAA==.Benmaverick:BAABNQAECn8WAAIPAAkKgA6cLgDMAQAPAAkKgA6cLgDMAQAAAA==.Bervin:BAAANQAECgQIDQAAAA==.',
Bi='Bifftunkisjr:BAAANQADCgEJAQAAAA==.Bishop:BAABNQAECn8dAAIQAAcKuApTPgAOAQAQAAcKuApTPgAOAQAAAA==.',
Bl='Bladesman:BAAANQAECggICAAAAA==.',
Bo='Bobe:BAABNQAECn81AAIKAAoKMhsLAwC+AQAKAAoKMhsLAwC+AQAAAA==.Bobedruid:BAAANQAECgQIBAAAAA==.Bordok:BAAANQAECgUIEAAAAA==.Borkuz:BAAANQADCggJCAAAAA==.',
Br='Brawl:BAAANQADCgYIBgAAAA==.Brunco:BAABNQAECn8lAAMDAAgKeBn/TACHAgADAAgKeBn/TACHAgACAAEK0QpxiQA1AAAAAA==.',
Ca='Captplanet:BAABNQAECn8uAAMRAAoKwhd/FAClAgARAAoKwhd/FAClAgASAAYKBBjEFQCfAQAAAA==.',
Ce='Ceindra:BAABNQAECn8nAAITAAoKdhfNCgDFAgATAAoKdhfNCgDFAgAAAA==.Celestria:BAAANQAECgQIDQAAAA==.Celiñ:BAAANQAECgEIAQAAAA==.Cerealkiller:BAAANQADCgYJBgAAAA==.',
Ch='Chipcho:BAAANQADCggICAAAAA==.Chockula:BAAANQADCgMIAwAAAA==.Chuladk:BAAANQAECgEIAQAAAA==.',
Co='Colbalt:BAAANQADCggIBwAAAA==.Constantinez:BAAANQAECggIEAAAAA==.Cor:BAAANQAECgMIBQAAAA==.',
Cr='Crackerzz:BAAANQAECgYIBgAAAA==.',
Cu='Cuddlymethod:BAAANQADCgYICQAAAA==.',
['Có']='Cól:BAABNQAECn8xAAIUAAoKqhh+dACVAgAUAAoKqhh+dACVAgAAAA==.Cónky:BAAANQADCgcIBQAAAA==.',
Da='Daddymoo:BAAANQADCgUIDAAAAA==.Dahealzrhere:BAAANQADCgEIAQAAAA==.Dalel:BAACNQAFFH8RAAMPAAUKBBoTCACAAQAPAAUKBBoTCACAAQAVAAEKdgDvDQAyAAA1AAQKfzkAAw8ACgqjHekNAAkDAA8ACgqjHekNAAkDABUAAQoAADySADYAAAAA.David:BAABNQAECn8WAAIWAAgKlRr+YABrAgAWAAgKlRr+YABrAgAAAA==.',
De='Deadlyglow:BAAANQAECgUIEgAAAA==.Demiurgos:BAAANQAECggIEAAAAA==.Denji:BAAANQAECgEIAQAAAA==.Denogarn:BAAANQADCggIEQAAAA==.Dermot:BAABNQAECn8dAAQXAAgKXCCSCwCxAQAIAAcKSxxDfQDtAQAXAAUKPBuSCwCxAQAJAAIK9RzJSgCfAAAAAA==.',
Dh='Dhiying:BAAANQAECgEIAgAAAA==.',
Di='Dirtface:BAABNQAECn8nAAIWAAkK0wYOwAB9AQAWAAkK0wYOwAB9AQAAAA==.Dixlongmd:BAAANQAECgEIAQAAAA==.Dixmen:BAABNQAECn8tAAIFAAkKdRaZcwBHAgAFAAkKdRaZcwBHAgAAAA==.',
Do='Dolemen:BAABNQAECn8XAAIFAAUKFAOgPAG/AAAFAAUKFAOgPAG/AAAAAA==.Domaon:BAABNQAECn8tAAIVAAgKZh7DDwBtAQAVAAgKZh7DDwBtAQAAAA==.Domshammy:BAAANQADCggICAABNQAECggILQAVAGYeAA==.Doubt:BAAANQAECgUIDgAAAA==.Doughug:BAAANQAECgMIAwABNQAECgQIBAAEAAAAAA==.Dozy:BAABNQAECn8qAAIFAAkKhCIKLgAQAwAFAAkKhCIKLgAQAwAAAA==.',
Dr='Druidheelzz:BAAANQAECgYICgAAAA==.Druissh:BAAANQAECgUICgABNQAECgkJJwAMACAYAA==.Drôôdude:BAAANQADCgQIBAAAAA==.',
Du='Dullgrim:BAAANQADCggICAAAAA==.Dunigan:BAABNQAECn8hAAIFAAcKjg4I0AB7AQAFAAcKjg4I0AB7AQAAAA==.Dunigen:BAAANQAECgQICAAAAA==.',
Eb='Ebeast:BAABNQAECn8kAAILAAoKRxEGBQB9AgALAAoKRxEGBQB9AgAAAA==.',
Ef='Efel:BAAANQADCggICAAAAA==.',
Ev='Evianda:BAAANQADCggIEAAAAA==.',
Fa='Fabulist:BAAANQADCgQIBAAAAA==.Facade:BAABNQAECn8YAAIYAAgKfwqFJADlAAAYAAgKfwqFJADlAAAAAA==.Facepalm:BAABNQAECn8YAAMZAAgKPBf+CQAwAgAZAAgKPBf+CQAwAgAWAAQKfwjaGgGmAAAAAA==.Falyy:BAAANQAECgEIAQAAAA==.Farmergeorge:BAAANQAECgQJCQAAAA==.',
Fe='Fentak:BAAANQADCgcIEwAAAA==.',
Fi='Fierytotes:BAAANQAECgEIAQABNQAECggICAAEAAAAAA==.Finnek:BAAANQADCgMIAwAAAA==.',
Fo='Forbidenelf:BAABNQAECn8rAAIFAAkKpRwkTQCtAgAFAAkKpRwkTQCtAgAAAA==.Forging:BAAANQADCgQIBAAAAA==.Forgotmymeds:BAAANQAECgMIBQAAAA==.Foxmccloud:BAAANQAECgYIEwAAAA==.',
Fr='Fridge:BAAANQADCggIDQABNQAECggICAAEAAAAAA==.Frosted:BAAANQADCggIAgAAAA==.Fruitloop:BAABNQAECn8iAAIUAAgKwBbEtwAUAgAUAAgKwBbEtwAUAgAAAA==.',
Fu='Funkybooty:BAAANQAECgEIAgAAAA==.Fuzybrewing:BAAANQABCgQICAAAAA==.',
Ga='Garidrael:BAAANQABCgMIAwAAAA==.',
Ge='Gebran:BAABNQAECn8kAAIFAAcKTgohZgD5AAAFAAcKTgohZgD5AAAAAA==.Gellywoo:BAABNQAECn8aAAIWAAkK9Q/kGACjAQAWAAkK9Q/kGACjAQAAAA==.Gemmarolizzy:BAAANQAECgQICQAAAA==.',
Go='Golaoth:BAABNQAECn8VAAINAAUKwhZ3CwAMAQANAAUKwhZ3CwAMAQAAAA==.Gooftroupe:BAABNQAECn8fAAIOAAgK9R6jBgBgAgAOAAgK9R6jBgBgAgAAAA==.',
Gr='Grandmaster:BAABNQAECn8WAAIUAAgK3Ai9PgA/AQAUAAgK3Ai9PgA/AQABNQAECgEIAQAEAAAAAA==.Grawn:BAAANQADCgMIAwAAAA==.Greymoon:BAAANQAECgYIEQAAAA==.Grimaced:BAAANQAECgYIBgABNQAECgkJIwAFAKIhAA==.Grimtotems:BAAANQADCgMIAwAAAA==.',
Ha='Haezi:BAAANQAECgcIDwABNQAECggIGgAaALUVAA==.Haki:BAAANQABCgIIAgAAAA==.Hammerbully:BAAANQADCgEIAQAAAA==.Happyendings:BAAANQAECgUICQAAAA==.',
He='Helbafx:BAAANQADCggIQwAAAA==.',
Hi='Hino:BAABNQAECn8XAAMQAAgKNBLCawDbAQAQAAgKNBLCawDbAQAbAAEKDAf+MQA5AAAAAA==.',
Ho='Homewrecker:BAAANQAECgUIEgAAAA==.Horuid:BAAANQAECgEIAQAAAA==.',
Hu='Huské:BAAANQAECgIIAgAAAA==.',
Ic='Icebully:BAAANQAECgEIAQAAAA==.Icemàn:BAAANQAECgEIBQAAAA==.',
Id='Idrazil:BAAANQAECgcIEwAAAA==.',
If='Ifearnobeer:BAAANQAECgQIBQAAAA==.',
In='Infectz:BAAANQAECggJAgAAAA==.Infoxicated:BAAANQADCgQIBAAAAA==.',
Is='Isabel:BAAANQADCgQIBAAAAA==.',
It='Itburnsalot:BAAANQADCgYIBgAAAA==.',
Ja='Jaiantobea:BAACNQAFFH8PAAIGAAUKbxjADACCAQAGAAUKbxjADACCAQA1AAQKf0wAAgYACgriI80CAP8CAAYACgriI80CAP8CAAAA.Jakik:BAAANQADCgUIBQAAAA==.Jarlaxl:BAAANQADCgQIBAAAAA==.Jawn:BAAANQAECggIDwAAAA==.',
Je='Jessuss:BAAANQAECgUIEQAAAA==.',
Jh='Jha:BAABNQAECn8YAAMcAAgKPR5eDAABAgAcAAcKPR5eDAABAgAVAAYKnhJKSwB1AQAAAA==.',
Ju='Jude:BAABNQAECn8cAAIFAAgKJBgNdQBEAgAFAAgKJBgNdQBEAgAAAA==.Junipermoon:BAAANQAECgEIAwAAAA==.',
Ka='Kabub:BAAANQAECgYIEQAAAA==.Kalahandra:BAABNQAECn8bAAIRAAgKkxHtKADYAQARAAgKkxHtKADYAQAAAA==.Kalebeesd:BAAANQADCgUIBwAAAA==.Katablight:BAAANQAECggIEQAAAA==.Katotan:BAABNQAECn8oAAIRAAgKnxTJJAD+AQARAAgKnxTJJAD+AQAAAA==.Kawk:BAAANQAECgMIAwAAAA==.',
Ke='Kealestra:BAAANQAECgUIEAAAAA==.Keyboärd:BAAANQAECgQIDQAAAA==.',
Ki='Kimochi:BAAANQAECgQIBQAAAA==.Kippo:BAEANQADCgcIBwABNQAECgcICQAEAAAAAA==.Kittylover:BAAANQAECgEIAQAAAA==.',
Ko='Kombat:BAAANQADCgYJCgAAAA==.Korllan:BAAANQADCgUIEgAAAA==.Kossnen:BAAANQAECgUIDgAAAA==.',
Kr='Krestisnack:BAABNQAECn8UAAIJAAUKjxbbBADdAAAJAAUKjxbbBADdAAAAAA==.',
Ku='Kuda:BAABNQAECn8XAAIdAAYKzBiJDgDCAQAdAAYKzBiJDgDCAQAAAA==.Kullkil:BAAANQADCggIEQAAAA==.',
Kw='Kwanu:BAAANQAECgUIDAAAAA==.',
['Kñ']='Kño:BAAANQADCgMIAwABNQAECgQIDgAEAAAAAA==.',
['Kó']='Kóñä:BAAANQAECgQIDgAAAA==.',
La='Larke:BAAANQADCgYIBgAAAA==.Lasa:BAAANQAECgMIBQAAAA==.Lasloo:BAABNQAECn8lAAIFAAkKZwufXwAGAQAFAAkKZwufXwAGAQAAAA==.Laylani:BAABNQAECn82AAIHAAoK9g6JDAA5AQAHAAoK9g6JDAA5AQAAAA==.',
Le='Lebronjames:BAAANQAECgYIDAAAAA==.Leynreite:BAAANQAECgMICAAAAA==.',
Li='Lisan:BAABNQAECn8kAAIUAAgKaBKvHQCZAQAUAAgKaBKvHQCZAQAAAA==.Littledicey:BAABNQAECn8pAAIeAAkKPglGPwDQAQAeAAkKPglGPwDQAQAAAA==.',
Lo='Lonélyboy:BAAANQAECgEIAQAAAA==.',
Lu='Luciä:BAABNQAECn8VAAIYAAUKTA6wOACVAAAYAAUKTA6wOACVAAAAAA==.Lucymoon:BAAANQAECgYIBwAAAA==.Luvflap:BAAANQADCgMIAwAAAA==.',
Lv='Lv:BAAANQAECggIEwABNQAFFAEIAQAEAAAAAA==.',
Ly='Lyñx:BAAANQADCgQIBgAAAA==.',
Ma='Machoman:BAAANQAECgQIBAAAAA==.Madness:BAABNQAECn8bAAIbAAcKcA1RMwCIAQAbAAcKcA1RMwCIAQAAAA==.Maerion:BAABNQAECn8WAAMCAAUK1gLVawB+AAADAAUK1gLNEwHdAAACAAUKZAHVawB+AAAAAA==.Magdeth:BAAANQAECgcIEAAAAA==.Mantra:BAAANQAECgUIBQAAAA==.Maphra:BAAANQABCgUIBwAAAA==.Marabelle:BAABNQAECn8UAAIfAAgKwgWxXwBRAQAfAAgKwgWxXwBRAQAAAA==.Marasteil:BAAANQADCgIIAgAAAA==.Mariomage:BAAANQADCgQICAAAAA==.Marixia:BAAANQAECgUIDAAAAA==.Marrow:BAAANQADCgYIBgAAAA==.Masilitu:BAAANQADCgYIDwAAAA==.Massack:BAABNQAECn8kAAIaAAgK5xBhEgC/AQAaAAgK5xBhEgC/AQAAAA==.Mawgwa:BAAANQAECgMIBAAAAA==.',
Mc='Mcwrath:BAAANQADCgcIDQABNQAECgkJJwAHAAoLAA==.',
Me='Meeow:BAAANQADCgEIAQABNQAECggIGgAaALUVAA==.Mero:BAABNQAECn8kAAMIAAoKMh5hMADGAgAIAAkKfx1hMADGAgAJAAIKHRnnSwCcAAAAAA==.',
Mi='Midgetmàniàc:BAAANQADCggICAAAAA==.',
Mo='Monkeywrench:BAAANQADCgEIAQAAAA==.Moobear:BAAANQADCgUIBQAAAA==.Moonshiner:BAAANQAECgQIBAAAAA==.Mosimo:BAAANQAECgEIAQAAAA==.Moushuhan:BAABNQAECn8iAAMgAAkKAxL2GQAJAgAgAAkK/xD2GQAJAgAeAAIKqRLwiwCBAAAAAA==.',
My='Mystrall:BAAANQAECgQIBAAAAA==.',
Na='Naanaa:BAABNQAECn8aAAIUAAkKfxDqHwCSAQAUAAkKfxDqHwCSAQAAAA==.Nadorian:BAAANQABCgIIAgAAAA==.Narey:BAAANQADCgIIAgAAAA==.',
Ne='Neb:BAAANQAECgEIAgAAAA==.Netherrogue:BAACNQAFFH8KAAMhAAUKXhLRAQD7AAAhAAMKcRXRAQD7AAAeAAIKNgy8HABSAAA1AAQKfyQAAyEACgrBIQ0EANcCACEABwqtJA0EANcCAB4ABApRHoEpAKgAAAAA.',
No='Noesis:BAAANQADCgQJBAAAAA==.',
Nu='Nuke:BAAANQAECggICAAAAA==.',
Ny='Nytehuntrix:BAABNQAFFH8GAAIPAAIKaAxiBgCNAAAPAAIKaAxiBgCNAAAAAA==.Nytemayer:BAABNQAECn8gAAMIAAkKNRwmWQBLAgAIAAgKuxwmWQBLAgAJAAMKtRPnQwC1AAABNQAFFAIIBgAPAGgMAA==.',
Ob='Obmakare:BAAANQAECgYIEgAAAA==.Obonhigh:BAAANQADCgEIAQAAAA==.Oboñ:BAAANQAECgQICwAAAA==.Obsfuyung:BAAANQAECgUICgAAAA==.',
Oo='Oopsiez:BAAANQAECgQIBgAAAA==.',
Op='Opiiknight:BAAANQAECgQICAAAAA==.Opiishift:BAABNQAECn8hAAIfAAoKKBPmMQBUAgAfAAoKKBPmMQBUAgAAAA==.Opiishots:BAAANQAECgUIEAAAAA==.',
Or='Orcc:BAAANQADCggIGQAAAA==.',
Pa='Paley:BAAANQAECgQICAAAAA==.',
Pd='Pdgrimm:BAAANQAECgEIAQAAAA==.',
Pe='Peavey:BAAANQABCgEIAQAAAA==.Peligrosa:BAAANQAECggIEAABNQAECgEIAQAEAAAAAA==.Performance:BAABNQAECn8vAAIcAAoKWx9kAwAwAwAcAAoKWx9kAwAwAwAAAA==.Peterturbo:BAAANQAECgQICgABNQABCgIIAgAEAAAAAA==.',
Pi='Pinkky:BAAANQADCgcIBwAAAA==.',
Po='Pocketfox:BAAANQAECgMIBwAAAA==.Poîsonivy:BAABNQAECn8VAAIJAAUKBganCQCDAAAJAAUKBganCQCDAAAAAA==.',
Ps='Psyrine:BAAANQADCgYIFQAAAA==.',
Py='Pyrö:BAAANQAECggICwAAAA==.',
Qu='Qu:BAABNQAECn8yAAIWAAoK8BhQQQDGAgAWAAoK8BhQQQDGAgAAAA==.',
Ra='Rakdoc:BAAANQADCgQIBAAAAA==.Rattlesnake:BAAANQAECgEIAQAAAA==.Raymonnd:BAAANQADCgcICwAAAA==.',
Re='Reflektor:BAAANQAECgEIAQAAAA==.Renägäde:BAAANQAECggIEgAAAA==.Reptilia:BAAANQAECgEIAQAAAA==.Retiredfurry:BAABNQAECn8rAAMiAAoK2SAlCAAPAwAiAAoK2SAlCAAPAwABAAIKCCPzVQCUAAAAAA==.',
Ri='Ricodadawg:BAABNQAECn82AAIUAAoKhx1qIABYAwAUAAoKhx1qIABYAwAAAA==.',
Ro='Roosk:BAAANQADCgUIBQAAAA==.Roshak:BAAANQADCgcIDQAAAA==.Rotspawn:BAAANQAECggJCAAAAA==.',
Ru='Runningbearr:BAAANQADCggIEgAAAA==.Runningdemon:BAAANQADCgYICwABNQAECggIHAAMAN8LAA==.Runningshama:BAABNQAECn8cAAMMAAgK3wvnegCyAQAMAAgK3wvnegCyAQAGAAEK+hLolgA3AAAAAA==.Rurahk:BAAANQAECgYIEgAAAA==.',
['Rõ']='Rõbb:BAAANQAECgEIAQAAAA==.',
Sa='Sabaak:BAAANQAECgUIEgAAAA==.Sabel:BAAANQADCggIDgAAAA==.Saeriin:BAAANQAECgQIBQAAAA==.Saintsnyder:BAABNQAECn8nAAQHAAkKCguoPgACAQAHAAUKKRaoPgACAQAFAAgKCQUHHAHwAAAOAAEKGgHgPQEPAAAAAA==.Saithis:BAAANQAECgEIBQAAAA==.Sanorasong:BAAANQAECgUIDAAAAA==.Saphaa:BAAANQAECgUIBQAAAA==.Saphirra:BAAANQAECgEIAQAAAA==.Sarylin:BAAANQAECgQICQAAAA==.Satansshadow:BAAANQADCgEIAQAAAA==.Sathona:BAAANQAECgIIAgAAAA==.Sathpriest:BAABNQAECn8fAAQQAAoK7SEhDgBTAwAQAAkK/yIhDgBTAwAjAAIKyRzxGACoAAAbAAEKAAD3ggAmAAAAAA==.Sathrel:BAAANQADCgMIAwAAAA==.',
Sc='Schio:BAAANQAECgYIDwAAAA==.',
Se='Severussnape:BAABNQAECn8kAAMIAAgKZQYIuQBbAQAIAAgKVwYIuQBbAQAJAAQKlwNjTQCXAAAAAA==.',
Sh='Shamrorag:BAAANQADCgQICAAAAA==.Sharpeyez:BAAANQAECgQIBAAAAA==.She:BAABNQAECn8lAAIgAAkKnBcWEAB7AgAgAAkKnBcWEAB7AgAAAA==.Shehealz:BAAANQADCggICQAAAA==.Shekxxy:BAAANQAECgIIAwABNQAECgoKLgABAPAaAA==.Shortstack:BAAANQAECgYIDQAAAA==.',
Si='Simpmother:BAAANQAECgUICQAAAA==.Sinensis:BAAANQAECgQICQAAAA==.',
Sk='Skadoosh:BAAANQADCggIDQABNQAFFAUIEQAPAAQaAA==.Skarletflame:BAAANQADCgMIAwAAAA==.Skarletrose:BAAANQAECgUIEwAAAA==.Skinalittleb:BAAANQAECgQIBAAAAA==.',
Sl='Slaycie:BAAANQAECgYIEQAAAA==.',
Sn='Sneek:BAAANQAECgQICwAAAA==.Snugglebus:BAAANQAECgIIAgAAAA==.',
So='Solaara:BAAANQAECgYIDwAAAA==.',
Sp='Spaghett:BAABNQAECn8aAAMaAAgKtRVDEQDUAQAaAAgKtRVDEQDUAQABAAYKWAb8VQCUAAAAAA==.',
St='Stanger:BAAANQAECggIEQAAAA==.Starlight:BAAANQAECgYIEQABNQAECgkJLQAFAGUkAA==.',
Sy='Syrden:BAABNQAECn8pAAIRAAkKcQygKgDJAQARAAkKcQygKgDJAQAAAA==.Syren:BAAANQADCgEIAQAAAA==.',
Ta='Tael:BAABNQAECn8mAAIZAAgKTB0eAgDLAQAZAAgKTB0eAgDLAQAAAA==.Tangylizard:BAAANQAECgcIEwAAAA==.Tawainai:BAABNQAECn8rAAIUAAgKFhJoJQCAAQAUAAgKFhJoJQCAAQAAAA==.',
Te='Tessla:BAABNQAECn8nAAMMAAkKIBhaTgA+AgAMAAkKIBhaTgA+AgAGAAIKtQGtFgE9AAAAAA==.Tetragram:BAABNQAECn87AAIBAAoKRx4UAwAUAgABAAoKRx4UAwAUAgAAAA==.',
Th='Thelarï:BAABNQAECn8kAAIDAAgKoAjoqgCvAQADAAgKoAjoqgCvAQAAAA==.Thors:BAABNQAECn8jAAIFAAkKoiHHEwB3AwAFAAkKoiHHEwB3AwAAAA==.Thundertoes:BAABNQAECn8iAAMGAAgKGhQKagDOAQAGAAgKGhQKagDOAQAMAAUKDw0KuAAiAQAAAA==.',
Ti='Timmy:BAAANQADCgIIAgAAAA==.Tiquandeisha:BAAANQAECgYIEgAAAA==.Titåx:BAAANQADCgYIBgAAAA==.',
To='Tonik:BAABNQAECn8ZAAMMAAYKSQ7qNQDpAAAMAAYKSQ7qNQDpAAAGAAQK/gyV1AC+AAAAAA==.Torgoth:BAABNQAECn8VAAITAAUKjAr0EADyAAATAAUKjAr0EADyAAAAAA==.Toshido:BAAANQAECgQIDAAAAA==.Totemtroll:BAAANQAECgEIAQAAAA==.Toy:BAAANQAECgEIAQAAAA==.',
Tr='Trevize:BAAANQADCgcIEwAAAA==.',
Tw='Twilightsoul:BAAANQAECggIAgAAAA==.',
Ub='Ubully:BAAANQADCgMIAwAAAA==.',
Ul='Ultane:BAAANQAECgQICwAAAA==.',
Un='Unholypally:BAAANQADCggIFwAAAA==.',
Va='Valashar:BAAANQADCgcIDQAAAA==.Valiantaine:BAABNQAECn8yAAMFAAoKphvzPgDYAgAFAAoKphvzPgDYAgAOAAcKOQQTrwAhAQAAAA==.Valiantaint:BAABNQAECn8cAAIPAAgK8RjUHgBZAgAPAAgK8RjUHgBZAgABNQAECgoKMgAFAKYbAA==.Valiantroar:BAAANQAECgYIBgABNQAECgoKMgAFAKYbAA==.Vashon:BAAANQADCgQIBgAAAA==.',
Ve='Velherun:BAABNQAECn8iAAIFAAgKDxUYnADqAQAFAAgKDxUYnADqAQAAAA==.Vendel:BAABNQAECn8sAAIMAAkK7yQCBwCxAwAMAAkK7yQCBwCxAwAAAA==.Vexxaa:BAABNQAECn8VAAIDAAUKFA01bQDRAAADAAUKFA01bQDRAAAAAA==.',
Vi='Virajr:BAAANQAECgQICgAAAA==.Vissiction:BAABNQAECn8aAAIPAAgKZxQQMQC5AQAPAAgKZxQQMQC5AQAAAA==.Vistine:BAABNQAECn8WAAIHAAYKsgjNHQCjAAAHAAYKsgjNHQCjAAABNQAECgkJJwAMACAYAA==.Vitez:BAABNQAECn8VAAIIAAcKwAiCtgBhAQAIAAcKwAiCtgBhAQAAAA==.',
Wa='Waterslide:BAAANQADCgYICQAAAA==.',
We='Wendy:BAABNQAECn8vAAIGAAkKyhcLTwAoAgAGAAkKyhcLTwAoAgAAAA==.',
Wh='Whemeo:BAAANQAECgEIAQAAAA==.Whitesox:BAAANQADCgQJBAAAAA==.',
Wi='Win:BAABNQAECn8WAAMfAAcKaQhZYQBJAQAfAAcKaQhZYQBJAQARAAcKCwkgPQA6AQABNQAECggICAAEAAAAAA==.Winkster:BAAANQAECgYICwAAAA==.',
Xa='Xanadu:BAABNQAECn8qAAMjAAoK9hs7AwDHAgAjAAoK9hs7AwDHAgAQAAEKUxLD/AAyAAAAAA==.Xarinia:BAAANQADCggIIwABNQAECgoKMwAkAN4LAA==.',
Xb='Xbear:BAABNQAECn8VAAIlAAUK5haGFgDPAAAlAAUK5haGFgDPAAABNQAFFAUIEgAgAIMVAA==.',
Xd='Xdynasty:BAACNQAFFH8SAAMgAAUKgxVBCQBXAQAgAAQKcxJBCQBXAQAeAAEKpBuUCABRAAA1AAQKfzkAAyAACgptIPoHAPoCACAACgovHfoHAPoCAB4ABAqmHqBXAFwBAAAA.',
Xe='Xendier:BAAANQADCgIIAgAAAA==.',
Xi='Xióngchäo:BAAANQADCgYIEgABNQAECgYIDgAEAAAAAA==.',
Xo='Xo:BAAANQADCggICAABNQAECggICAAEAAAAAA==.',
Za='Zabazz:BAABNQAECn8eAAMGAAgKlQ+kHAB6AQAGAAgKlQ+kHAB6AQAMAAEKAADjXgEaAAAAAA==.Zabenir:BAAANQAECgUIEAAAAA==.Zalrote:BAAANQADCggICgABNQAECgoKMwAkAN4LAA==.Zaraina:BAABNQAECn8UAAIQAAUKiBMuRgD1AAAQAAUKiBMuRgD1AAABNQAFFAUIEQAPAAQaAA==.',
Ze='Zerototem:BAABNQAECn8rAAMGAAgKyBeTTQAtAgAGAAgKyBeTTQAtAgAMAAIKGAlsEQFpAAAAAA==.',
Zo='Zorusii:BAAANQADCgcIDQABNQAFFAUIEQAPAAQaAA==.',
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
