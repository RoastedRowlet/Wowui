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

local lookup = {'Monk-Windwalker','Hunter-Marksmanship','Hunter-BeastMastery','Unknown-Unknown','Shaman-Restoration','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warrior-Protection','Hunter-Survival','Shaman-Elemental','Evoker-Preservation','Paladin-Holy','Priest-Holy','Rogue-Assassination','Druid-Restoration','Druid-Feral','Shaman-Enhancement','Mage-Arcane','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Arms','Warlock-Affliction','Paladin-Retribution','Warrior-Fury','Druid-Balance','Monk-Brewmaster','DemonHunter-Vengeance','Priest-Shadow','Rogue-Subtlety','Rogue-Outlaw','Monk-Mistweaver','Priest-Discipline','DeathKnight-Frost',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Acaciastrain:BAAANQADCggIDwAAAA==.',
Ae='Aelord:BAAANQADCgUIBQAAAA==.Aerebos:BAAANQAECgQIBQABNQAECgkJMQABACIfAA==.Aeriss:BAAANQABCgQIBAAAAA==.Aetheria:BAAANQADCgYJBgAAAA==.Aethos:BAABNQAECn8aAAMCAAkKMhk2EwDGAgACAAkKMhk2EwDGAgADAAIKRhVrMwF4AAABNQAECgkJMQABACIfAA==.Aeón:BAAANQADCgMIAwABNQAECgQIDgAEAAAAAA==.',
Ag='Agua:BAAANQAECgQIBQAAAA==.',
Ak='Akashá:BAAANQADCgEIAQAAAA==.',
Al='Aladrius:BAEANQAECgQIBwAAAA==.Alexanderath:BAAANQAECgUICAAAAA==.Alkatractite:BAAANQAECgQIEAAAAA==.Allenwalker:BAAANQAECgUIDQAAAA==.Allison:BAAANQADCgUIBQABNQAECggIKwAFAJIXAA==.',
Am='Amey:BAAANQAECgIIBAAAAA==.',
An='Anelise:BAAANQADCgUIBQAAAA==.Antelon:BAAANQAECgMIAwABNQAECgkJIwAGAAoLAA==.',
Ao='Aoeslave:BAABNQAECn8jAAMHAAgKCxTmjwC6AQAHAAcK0BLmjwC6AQAIAAMKZRLpRgCqAAABNQAFFAIIAgAEAAAAAA==.',
Ap='Apk:BAAANQAECgEIAwAAAA==.',
Ar='Arrisia:BAAANQAECgUIDAAAAA==.Arthedain:BAABNQAECn8eAAIJAAkKYyE6AwBsAwAJAAkKYyE6AwBsAwAAAA==.Arthedaine:BAABNQAECn8UAAIKAAkKNhqXAgAKAwAKAAkKNhqXAgAKAwABNQAECgkJHgAJAGMhAA==.',
As='Assano:BAABNQAECn8VAAMIAAcKThCIJABMAQAIAAUKVhCIJABMAQAHAAQKSgotAQHDAAABNQAECggIJAALAL8YAA==.',
Au='Auvry:BAABNQAECn8jAAIMAAkKrQ+kGQAlAgAMAAkKrQ+kGQAlAgAAAA==.',
Az='Azliain:BAAANQAECggICAAAAA==.Azurine:BAAANQADCgYIBgAAAA==.',
Ba='Bahamutfang:BAAANQAECgUIEAAAAA==.Bahozakurkho:BAAANQAECgMIAwABNQAECgUIDAAEAAAAAA==.Bakala:BAAANQAECgUIDgAAAA==.Barath:BAAANQAECgUIDAAAAA==.',
Be='Belegaer:BAABNQAECn8bAAINAAcKXwTzqwAlAQANAAcKXwTzqwAlAQAAAA==.Belenos:BAAANQAECgEIAwABNQAECgEIAwAEAAAAAA==.Benmaverick:BAAANQAECgcIEwAAAA==.Bervin:BAAANQAECgQIDQAAAA==.',
Bi='Bifftunkisjr:BAAANQADCgEJAQAAAA==.Bishop:BAABNQAECn8XAAIOAAYKDQtBogApAQAOAAYKDQtBogApAQAAAA==.',
Bl='Bladesman:BAAANQADCggICAABNQAECgkJKwAPABUVAA==.',
Bo='Bobe:BAABNQAECn8tAAIJAAkKUxtOCADNAgAJAAkKUxtOCADNAgAAAA==.Bobedruid:BAAANQADCggIHgAAAA==.Bordok:BAAANQAECgQICwAAAA==.Borkuz:BAAANQADCggJCAAAAA==.',
Br='Brawl:BAAANQADCgYIBgAAAA==.Broot:BAAANQADCgUIBwAAAA==.Brunco:BAABNQAECn8kAAMDAAgKeBnaSwCIAgADAAgKeBnaSwCIAgACAAEK0QqghwA1AAAAAA==.',
Ca='Captplanet:BAABNQAECn8qAAMQAAkKBBk3FAClAgAQAAkKBBk3FAClAgARAAYKBBhdFQCiAQAAAA==.',
Ce='Ceindra:BAABNQAECn8kAAISAAkKfBmUCgDHAgASAAkKfBmUCgDHAgAAAA==.Celestria:BAAANQAECgQIDQAAAA==.Celiñ:BAAANQAECgEIAQAAAA==.Cerealkiller:BAAANQADCgYJBgAAAA==.',
Ch='Chipcho:BAAANQADCggICAAAAA==.Chockula:BAAANQADCgMIAwAAAA==.Chuladk:BAAANQAECgEIAQAAAA==.',
Co='Colbalt:BAAANQADCggIBwAAAA==.Constantinez:BAAANQAECggIEAAAAA==.Cor:BAAANQAECgEIAwAAAA==.',
Cr='Crackerzz:BAAANQAECgYIBgAAAA==.',
Cu='Cuddlymethod:BAAANQADCgYICQAAAA==.',
['Có']='Cól:BAABNQAECn8tAAITAAkKSBpycgCYAgATAAkKSBpycgCYAgAAAA==.Cónky:BAAANQADCgcIBQAAAA==.',
Da='Daddymoo:BAAANQADCgUIDAAAAA==.Dahealzrhere:BAAANQADCgEIAQAAAA==.Dalel:BAACNQAFFH8NAAIUAAUKBBrqBwCCAQAUAAUKBBrqBwCCAQA1AAQKfzUAAxQACQrBHrsNAAkDABQACQrBHrsNAAkDABUAAQoAABKQADYAAAAA.David:BAABNQAECn8WAAIWAAgKlRqFXwBsAgAWAAgKlRqFXwBsAgAAAA==.',
De='Deadlyglow:BAAANQAECgUIEgAAAA==.Demiurgos:BAAANQAECgYIDQAAAA==.Denji:BAAANQAECgEIAQAAAA==.Denogarn:BAAANQADCggIEQAAAA==.Dermot:BAABNQAECn8ZAAQXAAcKeiJ3CwCyAQAHAAYK6x0zewDuAQAXAAUKPBt3CwCyAQAIAAIK9RxXSgCfAAAAAA==.',
Dh='Dhiying:BAAANQAECgEIAgAAAA==.',
Di='Dirtface:BAABNQAECn8jAAIWAAgK5wbpvQB9AQAWAAgK5wbpvQB9AQAAAA==.Dixlongmd:BAAANQAECgEIAQAAAA==.Dixmen:BAABNQAECn8nAAIYAAkKdRadcQBIAgAYAAkKdRadcQBIAgAAAA==.',
Do='Dolemen:BAAANQAECgQIEwAAAA==.Domaon:BAABNQAECn8nAAIVAAgKXR4aIgCGAgAVAAgKXR4aIgCGAgAAAA==.Domshammy:BAAANQADCggICAABNQAECggIJwAVAF0eAA==.Doubt:BAAANQAECgUIDgAAAA==.Dozy:BAABNQAECn8oAAIYAAgKGiMNLQARAwAYAAgKGiMNLQARAwAAAA==.',
Dr='Druidheelzz:BAAANQAECgUICQAAAA==.Druissh:BAAANQAECgIIBgABNQAECggIJAALAL8YAA==.Drôôdude:BAAANQADCgQIBAAAAA==.',
Du='Dullgrim:BAAANQADCggICAAAAA==.Dunigan:BAABNQAECn8aAAIYAAYKFQxY6wA/AQAYAAYKFQxY6wA/AQAAAA==.Dunigen:BAAANQAECgIIBQAAAA==.',
Eb='Ebeast:BAABNQAECn8gAAIKAAkKSxL9BAB9AgAKAAkKSxL9BAB9AgAAAA==.',
Ef='Efel:BAAANQADCggICAAAAA==.',
Ev='Evianda:BAAANQADCggIEAAAAA==.',
Fa='Facade:BAAANQAECgcIEgAAAA==.Facepalm:BAABNQAECn8YAAMZAAgKPBfnCQAwAgAZAAgKPBfnCQAwAgAWAAQKfwhoFwGmAAAAAA==.Falyy:BAAANQAECgEIAQAAAA==.Farmergeorge:BAAANQAECgQJCQAAAA==.',
Fe='Fentak:BAAANQADCgcIEwAAAA==.',
Fi='Fierytotes:BAAANQAECgEIAQABNQAECgkJKwAPABUVAA==.Finnek:BAAANQADCgMIAwAAAA==.',
Fo='Forbidenelf:BAABNQAECn8mAAIYAAgKDB6fSwCuAgAYAAgKDB6fSwCuAgAAAA==.Forging:BAAANQADCgQIBAAAAA==.Forgotmymeds:BAAANQAECgMIBQAAAA==.Foxmccloud:BAAANQAECgUIDwAAAA==.',
Fr='Fridge:BAAANQADCgcIBwABNQAECgcIFgAaAGkIAA==.Frosted:BAAANQADCggIAgAAAA==.Fruitloop:BAABNQAECn8gAAITAAgK2xRHtgAVAgATAAgK2xRHtgAVAgAAAA==.',
Fu='Funkybooty:BAAANQAECgEIAgAAAA==.Fuzybrewing:BAAANQABCgQICAAAAA==.',
Ga='Garidrael:BAAANQABCgMIAwAAAA==.',
Ge='Gebran:BAABNQAECn8dAAIYAAcKvQm43QBZAQAYAAcKvQm43QBZAQAAAA==.Gellywoo:BAAANQAECgYIEgAAAA==.Gemmarolizzy:BAAANQAECgQICQAAAA==.',
Go='Golaoth:BAAANQAECgUIEAAAAA==.Gooftroupe:BAABNQAECn8YAAINAAcKwB85NQCNAgANAAcKwB85NQCNAgAAAA==.',
Gr='Grandmaster:BAAANQAECgYIDwABNQAECgEIAQAEAAAAAA==.Grawn:BAAANQADCgMIAwAAAA==.Greymoon:BAAANQAECgUIDQAAAA==.Grimaced:BAAANQAECgYIBgABNQAECgkJIwAYAKIhAA==.Grimtotems:BAAANQADCgMIAwAAAA==.',
Ha='Haezi:BAAANQAECgQICQABNQAECgcIGAAbAOAWAA==.Haki:BAAANQABCgIIAgAAAA==.Hammerbully:BAAANQADCgEIAQAAAA==.Happyendings:BAAANQAECgUIBwAAAA==.',
He='Helbafx:BAAANQADCggIOwAAAA==.',
Hi='Hino:BAABNQAECn8VAAIOAAgKVxBaagDbAQAOAAgKVxBaagDbAQAAAA==.',
Ho='Homewrecker:BAAANQAECgUIDgAAAA==.Horuid:BAAANQAECgEIAQAAAA==.',
Ic='Icebully:BAAANQAECgEIAQAAAA==.Icemàn:BAAANQAECgEIBQAAAA==.',
Id='Idrazil:BAAANQAECgcIEwAAAA==.',
If='Ifearnobeer:BAAANQAECgMIBQAAAA==.',
In='Infectz:BAAANQAECggJAgAAAA==.Infoxicated:BAAANQADCgQIBAAAAA==.',
It='Itburnsalot:BAAANQADCgYIBgAAAA==.',
Ja='Jaiantobea:BAACNQAFFH8MAAIFAAUK9hRuDACCAQAFAAUK9hRuDACCAQA1AAQKf0MAAgUACQrcIbAKAGoDAAUACQrcIbAKAGoDAAAA.Jakik:BAAANQADCgUIBQAAAA==.Jarlaxl:BAAANQADCgQIBAAAAA==.Jawn:BAAANQAECgUIDQAAAA==.',
Je='Jessuss:BAAANQAECgUIDQAAAA==.',
Jh='Jha:BAABNQAECn8WAAMcAAcKEh82DAABAgAcAAYKEh82DAABAgAVAAYKnhJjSgB1AQAAAA==.',
Ju='Jude:BAABNQAECn8aAAIYAAgKJBgBcwBEAgAYAAgKJBgBcwBEAgAAAA==.Junipermoon:BAAANQAECgEIAwAAAA==.',
Ka='Kabub:BAAANQAECgYIEQAAAA==.Kalahandra:BAABNQAECn8bAAIQAAgKkxF+KADYAQAQAAgKkxF+KADYAQAAAA==.Kalebeesd:BAAANQADCgUIBwAAAA==.Katablight:BAAANQAECggIEQAAAA==.Katotan:BAABNQAECn8mAAIQAAgKnxRyJAD9AQAQAAgKnxRyJAD9AQAAAA==.',
Ke='Kealestra:BAAANQAECgUIEAAAAA==.Keyboärd:BAAANQAECgQIDQAAAA==.',
Ki='Kimochi:BAAANQAECgQIBQAAAA==.Kippo:BAEANQADCgcIBwABNQAECgcICQAEAAAAAA==.Kittylover:BAAANQAECgEIAQAAAA==.',
Ko='Kombat:BAAANQADCgYJCgAAAA==.Korllan:BAAANQADCgUIDgAAAA==.Kossnen:BAAANQAECgQIDgAAAA==.',
Kr='Krestisnack:BAAANQAECgUIDwAAAA==.',
Ku='Kuda:BAAANQAECgUIEQAAAA==.Kullkil:BAAANQADCggIEQAAAA==.',
Kw='Kwanu:BAAANQAECgUICwAAAA==.',
['Kñ']='Kño:BAAANQADCgMIAwABNQAECgQIDgAEAAAAAA==.',
['Kó']='Kóñä:BAAANQAECgQIDgAAAA==.',
La='Larke:BAAANQADCgYIBgAAAA==.Lasa:BAAANQAECgEIBAAAAA==.Lasloo:BAABNQAECn8fAAIYAAgKsAurugCiAQAYAAgKsAurugCiAQAAAA==.Laylani:BAABNQAECn8vAAIGAAgKCxDAJwCcAQAGAAgKCxDAJwCcAQAAAA==.',
Le='Lebronjames:BAAANQAECgQICwAAAA==.Leynreite:BAAANQAECgMIBwAAAA==.',
Li='Lisan:BAABNQAECn8dAAITAAcKGBGB2gDPAQATAAcKGBGB2gDPAQAAAA==.Littledicey:BAABNQAECn8nAAIPAAgK5AkyPgDQAQAPAAgK5AkyPgDQAQAAAA==.',
Lo='Lonélyboy:BAAANQAECgEIAQAAAA==.',
Lu='Luciä:BAAANQAECgUIEAAAAA==.Lucymoon:BAAANQAECgYIBwAAAA==.Luvflap:BAAANQADCgMIAwAAAA==.',
Ly='Lyñx:BAAANQADCgQIBgAAAA==.',
Ma='Machoman:BAAANQAECgQIBAAAAA==.Madness:BAABNQAECn8bAAIdAAcKcA3SMgCIAQAdAAcKcA3SMgCIAQAAAA==.Maerion:BAABNQAECn8VAAMCAAUK1gJtagB+AAADAAUK1gJ/EAHdAAACAAUKZAFtagB+AAAAAA==.Magdeth:BAAANQAECgcICwAAAA==.Maphra:BAAANQABCgUIBwAAAA==.Marabelle:BAABNQAECn8UAAIaAAgKwgXMXgBRAQAaAAgKwgXMXgBRAQAAAA==.Marasteil:BAAANQADCgIIAgAAAA==.Mariomage:BAAANQADCgQICAAAAA==.Marixia:BAAANQAECgUIDAAAAA==.Masilitu:BAAANQADCgYIDwAAAA==.Massack:BAABNQAECn8iAAIbAAgK5xAsEgDAAQAbAAgK5xAsEgDAAQAAAA==.Mawgwa:BAAANQAECgMIBAAAAA==.',
Mc='Mcwrath:BAAANQADCgcIDQABNQAECgkJIwAGAAoLAA==.',
Me='Meeow:BAAANQADCgEIAQABNQAECgcIGAAbAOAWAA==.Mero:BAABNQAECn8jAAMHAAkKqR9lLwDGAgAHAAgKFx9lLwDGAgAIAAIKHRlxSwCcAAAAAA==.',
Mi='Midgetmàniàc:BAAANQADCggICAAAAA==.',
Mo='Monkeywrench:BAAANQADCgEIAQAAAA==.Moobear:BAAANQADCgUIBQAAAA==.Mosimo:BAAANQAECgEIAQAAAA==.Moushuhan:BAABNQAECn8gAAMeAAgKLhK0GQAJAgAeAAgK/xC0GQAJAgAPAAIKqRIXiQCBAAAAAA==.',
My='Mystrall:BAAANQAECgQIBAAAAA==.',
Na='Naanaa:BAAANQAFFAEIAQAAAA==.Nadorian:BAAANQABCgIIAgAAAA==.Narey:BAAANQADCgIIAgAAAA==.',
Ne='Neb:BAAANQAECgEIAgAAAA==.Netherrogue:BAACNQAFFH8JAAMfAAQKXhLLAQD7AAAfAAMKcRXLAQD7AAAPAAEKNgwHHABSAAA1AAQKfyEAAx8ACQr6IwEEANgCAB8ABwqtJAEEANgCAA8AAwpbIiNiACQBAAAA.',
No='Noesis:BAAANQADCgQJBAAAAA==.',
Nu='Nuke:BAAANQAECgQICAABNQAECgcIFgAaAGkIAA==.',
Ny='Nytehuntrix:BAAANQAFFAIIBAAAAA==.Nytemayer:BAABNQAECn8gAAMHAAkKNRyoVwBMAgAHAAgKuxyoVwBMAgAIAAMKtROKQwC1AAABNQAFFAIIBAAEAAAAAA==.',
Ob='Obmakare:BAAANQAECgUIDgAAAA==.Obonhigh:BAAANQADCgEIAQAAAA==.Oboñ:BAAANQAECgQICwAAAA==.Obsfuyung:BAAANQAECgUICgAAAA==.',
Oo='Oopsiez:BAAANQAECgQIBgAAAA==.',
Op='Opiiknight:BAAANQAECgQICAAAAA==.Opiishift:BAABNQAECn8fAAIaAAkKcRRaMQBUAgAaAAkKcRRaMQBUAgAAAA==.Opiishots:BAAANQAECgQIDAAAAA==.',
Or='Orcc:BAAANQADCggIFAAAAA==.',
Pa='Paley:BAAANQAECgQICAAAAA==.',
Pd='Pdgrimm:BAAANQAECgEIAQAAAA==.',
Pe='Peavey:BAAANQABCgEIAQAAAA==.Peligrosa:BAAANQAECgcIEAABNQAECgEIAQAEAAAAAA==.Performance:BAABNQAECn8uAAIcAAkKFyBVAwAwAwAcAAkKFyBVAwAwAwAAAA==.Peterturbo:BAAANQAECgQICgABNQABCgIIAgAEAAAAAA==.',
Pi='Pinkky:BAAANQADCgcIBwAAAA==.',
Po='Pocketfox:BAAANQAECgMIBgAAAA==.Poîsonivy:BAAANQAECgUIEAAAAA==.',
Ps='Psyrine:BAAANQADCgYIFQAAAA==.',
Py='Pyrö:BAAANQAECggIAwAAAA==.',
Qu='Qu:BAABNQAECn8uAAIWAAkK6xtLQADGAgAWAAkK6xtLQADGAgAAAA==.',
Ra='Rakdoc:BAAANQADCgQIBAAAAA==.Rattlesnake:BAAANQAECgEIAQAAAA==.Raymonnd:BAAANQADCgYICwAAAA==.',
Re='Reflektor:BAAANQAECgEIAQAAAA==.Renägäde:BAAANQAECgYIEAAAAA==.Reptilia:BAAANQAECgEIAQAAAA==.Retiredfurry:BAABNQAECn8lAAMgAAgKTiP9BwAPAwAgAAgKTiP9BwAPAwABAAIKCCPBVACUAAAAAA==.',
Ri='Ricodadawg:BAABNQAECn8yAAITAAkKnSH2HgBdAwATAAkKnSH2HgBdAwAAAA==.',
Ro='Roosk:BAAANQADCgUIBQAAAA==.Roshak:BAAANQADCgYIDQAAAA==.Rotspawn:BAAANQAECggJCAAAAA==.',
Ru='Runningbearr:BAAANQADCggIEgAAAA==.Runningdemon:BAAANQADCgYICwABNQAECggIGQALAN8LAA==.Runningshama:BAABNQAECn8ZAAILAAgK3wsyeQCyAQALAAgK3wsyeQCyAQAAAA==.Rurahk:BAAANQAECgYIEgAAAA==.',
['Rõ']='Rõbb:BAAANQAECgEIAQAAAA==.',
Sa='Sabaak:BAAANQAECgUIDgAAAA==.Sabel:BAAANQADCggIDgAAAA==.Saeriin:BAAANQAECgEIAQAAAA==.Saintsnyder:BAABNQAECn8jAAQGAAkKCgvUPQADAQAGAAUKKRbUPQADAQAYAAgKCQUrGAHwAAANAAEKGgEjOgEPAAAAAA==.Saithis:BAAANQAECgEIBQAAAA==.Sanorasong:BAAANQAECgUIDAAAAA==.Saphaa:BAAANQAECgEIAQAAAA==.Saphirra:BAAANQAECgEIAQAAAA==.Sarylin:BAAANQAECgQICQAAAA==.Satansshadow:BAAANQADCgEIAQAAAA==.Sathona:BAAANQAECgIIAgAAAA==.Sathpriest:BAABNQAECn8dAAQOAAkKeiPVDQBTAwAOAAgK4CTVDQBTAwAhAAIKyRyzGACoAAAdAAEKAABDgQAmAAAAAA==.Sathrel:BAAANQADCgMIAwAAAA==.',
Sc='Schio:BAAANQAECgUICwAAAA==.',
Se='Severussnape:BAABNQAECn8iAAMHAAgKKAbWtgBbAQAHAAgKGgbWtgBbAQAIAAQKlwP9TACXAAAAAA==.',
Sh='Shamrorag:BAAANQADCgQICAAAAA==.She:BAABNQAECn8kAAIeAAkKHhf5DwB7AgAeAAkKHhf5DwB7AgAAAA==.Shehealz:BAAANQADCggICQAAAA==.Shekxxy:BAAANQAECgIIAwAAAA==.Shortstack:BAAANQAECgYIDQAAAA==.',
Si='Simpmother:BAAANQAECgQIBQAAAA==.Sinensis:BAAANQAECgQIBQAAAA==.',
Sk='Skadoosh:BAAANQADCggIDQABNQAFFAUIDQAUAAQaAA==.Skarletflame:BAAANQADCgMIAwAAAA==.Skarletrose:BAAANQAECgUIDgAAAA==.Skinalittleb:BAAANQADCgMIAwAAAA==.',
Sl='Slaycie:BAAANQAECgUIDQAAAA==.',
Sn='Sneek:BAAANQAECgQICwAAAA==.Snugglebus:BAAANQAECgIIAgAAAA==.',
So='Solaara:BAAANQAECgUIDQAAAA==.',
Sp='Spaghett:BAABNQAECn8YAAMbAAcK4BYKEQDVAQAbAAcK4BYKEQDVAQABAAUKWAbKVACUAAAAAA==.',
St='Stanger:BAAANQAECggIDwAAAA==.Starlight:BAAANQAECgUIDQABNQAECgkJJwAYAGUkAA==.',
Sy='Syrden:BAABNQAECn8pAAIQAAkKcQw9KgDIAQAQAAkKcQw9KgDIAQAAAA==.Syren:BAAANQADCgEIAQAAAA==.',
Ta='Tael:BAABNQAECn8fAAIZAAcKBiDTBwBxAgAZAAcKBiDTBwBxAgAAAA==.Tangylizard:BAAANQAECgcIEwAAAA==.Tawainai:BAABNQAECn8kAAITAAgKFhISuQAQAgATAAgKFhISuQAQAgAAAA==.',
Te='Tessla:BAABNQAECn8kAAMLAAgKvxhUTQA+AgALAAgKvxhUTQA+AgAFAAIKtQGREwE9AAAAAA==.Tetragram:BAABNQAECn8xAAIBAAkKIh/hCABAAwABAAkKIh/hCABAAwAAAA==.',
Th='Thelarï:BAABNQAECn8iAAIDAAgKoAikqACwAQADAAgKoAikqACwAQAAAA==.Thors:BAABNQAECn8jAAIYAAkKoiFqEwB3AwAYAAkKoiFqEwB3AwAAAA==.Thundertoes:BAABNQAECn8iAAMFAAgKGhTnaADOAQAFAAgKGhTnaADOAQALAAUKDw3btQAiAQAAAA==.',
Ti='Timmy:BAAANQADCgIIAgAAAA==.Tiquandeisha:BAAANQAECgUIDgAAAA==.Titåx:BAAANQADCgYIBgAAAA==.',
To='Tonik:BAABNQAECn8UAAMLAAYKSQ6BpgBDAQALAAYKSQ6BpgBDAQAFAAQK/gw30gC+AAAAAA==.Torgoth:BAAANQAECgUIEAAAAA==.Toshido:BAAANQAECgQICQAAAA==.Totemtroll:BAAANQAECgEIAQAAAA==.Toy:BAAANQADCggICAAAAA==.',
Tr='Trevize:BAAANQADCgcIEwAAAA==.',
Tw='Twilightsoul:BAAANQAECggIAgAAAA==.',
Ub='Ubully:BAAANQADCgMIAwAAAA==.',
Ul='Ultane:BAAANQAECgQICwAAAA==.',
Un='Unholypally:BAAANQADCggIDwAAAA==.',
Va='Valashar:BAAANQADCgcIDQAAAA==.Valiantaine:BAABNQAECn8uAAMYAAkK0hy1PQDZAgAYAAkK0hy1PQDZAgANAAcKOQQsrQAiAQAAAA==.Valiantaint:BAABNQAECn8bAAIUAAgK8Rh2HgBZAgAUAAgK8Rh2HgBZAgABNQAECgkJLgAYANIcAA==.Valiantroar:BAAANQAECgYIBgABNQAECgkJLgAYANIcAA==.Vashon:BAAANQADCgQIBgAAAA==.',
Ve='Velherun:BAABNQAECn8gAAIYAAgKDxWemQDrAQAYAAgKDxWemQDrAQAAAA==.Vendel:BAABNQAECn8sAAILAAkK7yTJBgCxAwALAAkK7yTJBgCxAwAAAA==.Vexxaa:BAAANQAECgUIEAAAAA==.',
Vi='Virajr:BAAANQAECgMIBgAAAA==.Vissiction:BAABNQAECn8YAAIUAAcK6hR7MAC5AQAUAAcK6hR7MAC5AQAAAA==.Vistine:BAAANQAECgQIEAABNQAECggIJAALAL8YAA==.Vitez:BAABNQAECn8VAAIHAAcKwAg+tABhAQAHAAcKwAg+tABhAQAAAA==.',
Wa='Waterslide:BAAANQADCgMIAwAAAA==.',
We='Wendy:BAABNQAECn8rAAIFAAgKkhcKTgApAgAFAAgKkhcKTgApAgAAAA==.',
Wh='Whemeo:BAAANQAECgEIAQAAAA==.Whitesox:BAAANQADCgQJBAAAAA==.',
Wi='Win:BAABNQAECn8WAAMaAAcKaQhwYABJAQAaAAcKaQhwYABJAQAQAAcKCwlkPAA5AQAAAA==.Winkster:BAAANQAECgUICgAAAA==.',
Xa='Xanadu:BAABNQAECn8oAAMhAAgKqR4zAwDHAgAhAAgKqR4zAwDHAgAOAAEKUxIs+QAyAAAAAA==.Xarinia:BAAANQADCggIHQABNQAECggILQAiAAgNAA==.',
Xb='Xbear:BAAANQAECgUIEAABNQAFFAUIDQAeAIMVAA==.',
Xd='Xdynasty:BAACNQAFFH8NAAMeAAUKgxULCQBXAQAeAAQKcxILCQBXAQAPAAEKpBsVHABSAAA1AAQKfzUAAx4ACQorIekHAPsCAB4ACQp5G+kHAPsCAA8ABAqmHjxWAFsBAAAA.',
Xe='Xendier:BAAANQADCgIIAgAAAA==.',
Xi='Xióngchäo:BAAANQADCgYIEgABNQAECgUIDQAEAAAAAA==.',
Xo='Xo:BAAANQADCggICAABNQAECgcIFgAaAGkIAA==.',
Za='Zabazz:BAABNQAECn8XAAMFAAcKQg7KiwBoAQAFAAcKQg7KiwBoAQALAAEKAAALWgEaAAAAAA==.Zabenir:BAAANQAECgQICwAAAA==.Zalrote:BAAANQADCggICgABNQAECggILQAiAAgNAA==.Zaraina:BAAANQAECgQIDwABNQAFFAUIDQAUAAQaAA==.',
Ze='Zerototem:BAABNQAECn8pAAMFAAgKyBeuTAAuAgAFAAgKyBeuTAAuAgALAAIKGAmODQFpAAAAAA==.',
Zo='Zorusii:BAAANQADCgcIDQABNQAFFAUIDQAUAAQaAA==.',
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
