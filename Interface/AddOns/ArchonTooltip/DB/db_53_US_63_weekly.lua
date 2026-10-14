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

local lookup = {'Warlock-Affliction','Warlock-Destruction','Druid-Balance','Hunter-BeastMastery','Shaman-Restoration','Unknown-Unknown','Shaman-Elemental','Monk-Windwalker','Paladin-Holy','Paladin-Retribution','Hunter-Survival','Paladin-Protection','Shaman-Enhancement','Monk-Brewmaster','Druid-Feral','DeathKnight-Blood','Warlock-Demonology','Priest-Holy','Priest-Discipline','Warrior-Protection','Druid-Restoration','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Arms','Warrior-Fury','Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','Mage-Arcane','Hunter-Marksmanship','DemonHunter-Devourer',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abdalhazred:BAACNQAFFH8LAAIBAAQKpCAUAQCBAQABAAQKpCAUAQCBAQA1AAQKfy8AAwEACQo9IhUBAGEDAAEACQo4IhUBAGEDAAIAAgqsGbtLAJsAAAAA.Abilus:BAAANQAECgMIDwAAAA==.Abolis:BAAANQAECgQIDQAAAA==.',
Ad='Adarlan:BAAANQAECgIIAgAAAA==.',
Ae='Aelianna:BAAANQAECgEIAQAAAA==.',
Ah='Ahqwanken:BAAANQADCgIIAgAAAA==.',
Ai='Aintnowei:BAAANQAECgQIBAAAAA==.',
Al='Allina:BAAANQADCgYIBgAAAA==.Alnara:BAAANQAECgUICwAAAA==.',
Am='Amoradis:BAAANQADCgYIDQAAAA==.',
An='Anarran:BAAANQADCgYIDAAAAA==.Animalfury:BAABNQAECn8bAAIDAAYKjwavbQAPAQADAAYKjwavbQAPAQAAAA==.Anthestria:BAAANQAECgQIBwAAAA==.',
Aq='Aqurala:BAABNQAECn8gAAIEAAkK0x7zFQBCAwAEAAkK0x7zFQBCAwAAAA==.',
Ar='Arasham:BAAANQADCgQIBAABNQAECggIGQAEANUWAA==.Aravenn:BAABNQAECn8ZAAIEAAgK1RaNdgAfAgAEAAgK1RaNdgAfAgAAAA==.Arionaa:BAAANQABCgIIAgAAAA==.Arkangel:BAAANQADCgYIBgAAAA==.Artemesia:BAAANQAECgMIAwABNQAFFAQICwAFALsgAA==.Artison:BAAANQADCgYIBgABNQAECgYIDgAGAAAAAA==.',
As='Ashiru:BAAANQADCgMIBQAAAA==.',
At='Ateup:BAAANQADCgQJBQABNQAECgUICwAGAAAAAA==.Athenos:BAAANQADCgYICAAAAA==.Atlás:BAAANQAECgUIBwAAAA==.',
Au='Aurum:BAAANQAFFAQIBAAAAA==.',
Av='Avatartele:BAABNQAECn8aAAIHAAkKphMPTQA/AgAHAAkKphMPTQA/AgAAAA==.Avatartouka:BAABNQAECn8vAAMFAAkKtSODBwCEAwAFAAkKtSODBwCEAwAHAAUKfRncuwAWAQAAAA==.Avrala:BAAANQADCgIJAgAAAA==.Avraria:BAAANQAECgcICgAAAA==.Avylastral:BAAANQAECgIIAgAAAA==.',
Az='Azshaxa:BAACNQAFFH8MAAIIAAQKkBXyCQAlAQAIAAQKkBXyCQAlAQA1AAQKfygAAggACQqOHBEZAHkCAAgACQqOHBEZAHkCAAAA.',
['Aí']='Aísling:BAAANQAECgQIBgAAAA==.',
Ba='Bagador:BAAANQAFFAIIAwAAAA==.Barby:BAAANQAECgEIAQAAAA==.Barrs:BAAANQADCgMIAwAAAA==.',
Be='Bearbuthealz:BAAANQAECgIIAgAAAA==.Beautifulluv:BAAANQAECgcIEwAAAA==.Bekabeka:BAACNQAFFH8LAAIJAAQKSw6TEgAxAQAJAAQKSw6TEgAxAQA1AAQKfy8AAwkACQoLHysZABIDAAkACQoLHysZABIDAAoAAQqJDUKYATgAAAAA.Bekabekabeka:BAAANQABCggJAQABNQAFFAQICwAJAEsOAA==.Belfour:BAAANQADCgQIBAAAAA==.Bera:BAAANQAECggIAwAAAA==.',
Bi='Billybobjr:BAABNQAECn8YAAIFAAgK1xgsTQAsAgAFAAgK1xgsTQAsAgAAAA==.',
Bl='Blackbart:BAAANQADCgQIBAAAAA==.Bloodar:BAAANQAECggIAQAAAA==.',
Bo='Bonski:BAAANQAECgEIAQAAAA==.Boosterman:BAABNQAECn8XAAMKAAcKcx9YWQCIAgAKAAcKcx9YWQCIAgAJAAEKiwtzGAE8AAAAAA==.',
Br='Brakkar:BAAANQAECgIIAgAAAA==.Braxxis:BAAANQAECgQICAABNQAFFAUIDgALAE4WAA==.Breadstick:BAAANQAECgQICAAAAA==.Bress:BAAANQADCgYIBgABNQAECgcIFQAMAO8hAA==.Brihunts:BAAANQAECgYICwAAAA==.Britotems:BAAANQAECgEIAQAAAA==.Brutaal:BAAANQADCgQJBAAAAA==.Bruutaal:BAAANQAECgEIAQAAAA==.Bryndel:BAAANQADCgYIBgAAAA==.',
Bu='Bubsydogo:BAAANQADCggICAAAAA==.',
Ca='Cacellice:BAAANQADCggICAAAAA==.Canoodles:BAAANQAECgYICQAAAA==.',
Ce='Celaian:BAAANQAECgQICAABNQAECgQICAAGAAAAAA==.Celpanda:BAAANQAECgQICAAAAA==.',
Ch='Chadee:BAAANQADCggICAABNQAECgcIDQAGAAAAAA==.Charybdia:BAAANQADCggJGwAAAA==.Cheesecake:BAABNQAECn8XAAIEAAgKIg9SiwDwAQAEAAgKIg9SiwDwAQAAAA==.Chidõri:BAABNQAECn8dAAMNAAkKMBNwEQBPAgANAAkKMBNwEQBPAgAHAAQKNBRa0ADuAAAAAA==.Chunni:BAABNQAECn8ZAAMOAAgKhwgSGgA/AQAOAAgKhgYSGgA/AQAIAAcKxQVBQAAPAQAAAA==.',
Co='Codap:BAAANQADCgEIAQAAAA==.Coolbeard:BAAANQAECgMIAwAAAA==.Cortex:BAAANQAECgQIBAABNQAECgkJHQAPADEcAA==.',
Cr='Crayonman:BAAANQAECgcIEQAAAA==.Cronus:BAAANQAECgQICAAAAA==.Cruelkitty:BAAANQAECgQIBQAAAA==.',
Cy='Cyralai:BAAANQADCgEIAQAAAA==.',
Da='Dahlinar:BAAANQAECgQIBwAAAA==.Dalov:BAABNQAECn8bAAMJAAYKrSFYSABDAgAJAAYKrSFYSABDAgAKAAQK1R/+4ABTAQAAAA==.Damageworg:BAAANQADCgQIBAAAAA==.Dankley:BAAANQAECgQIBgAAAA==.Danystorm:BAAANQADCgcIBwABNQAFFAQICwAFALsgAA==.',
Dd='Ddream:BAAANQADCgEIAQABNQADCgYICAAGAAAAAA==.',
De='Deaddude:BAABNQAECn8oAAIQAAgKvxsSLABlAgAQAAgKvxsSLABlAgAAAA==.Deathboi:BAAANQAECgUIEAAAAA==.Deathburgur:BAAANQAECggICAAAAA==.Deathcuddles:BAAANQAECgUIEAAAAA==.Dedcow:BAAANQAECgcIEgAAAA==.',
Di='Diana:BAABNQAECn8fAAIEAAgKwQimlQDZAQAEAAgKwQimlQDZAQAAAA==.',
Do='Dontjudgemê:BAAANQADCgYJCgAAAA==.Dorcina:BAAANQADCgcICAAAAA==.Downpour:BAAANQADCgUIBQAAAA==.',
Dr='Dracthyr:BAAANQADCgYIFwAAAA==.Dragam:BAAANQAECgQIBAABNQAECggIGgARADcXAA==.Dragonwarrio:BAABNQAECn8iAAIIAAkKdx/pEgDAAgAIAAkKdx/pEgDAAgAAAA==.Draltina:BAAANQAECgcIEQAAAA==.Drazira:BAAANQADCgcJDgAAAA==.Dresstokill:BAAANQADCggJEQAAAA==.Drmonkborg:BAAANQAECgUICwABNQAECgkJGQASAOEdAA==.Drovis:BAAANQADCgIIAgAAAA==.Druzzlek:BAAANQADCggIEQAAAA==.',
Du='Dubalnuar:BAAANQADCgUIDAAAAA==.Dubalpally:BAAANQADCgQIBAAAAA==.Dubaltrok:BAAANQADCgYIDQAAAA==.Dudde:BAAANQAECggIEwABNQAECggIKAAQAL8bAA==.Dulapin:BAAANQADCgIIAgAAAA==.Duskfu:BAABNQAECn8YAAIIAAkKiBweEwC+AgAIAAkKiBweEwC+AgAAAA==.Dustylock:BAABNQAECn8aAAMRAAgKNxceUwBYAgARAAgKNxceUwBYAgACAAEKzQfXfAAvAAAAAA==.',
Ea='Earthele:BAAANQAECgUIDQAAAA==.',
El='Elfcaster:BAAANQAECgEIAgAAAA==.Elfowl:BAAANQADCgYIBwABNQAECggIIQASANgLAA==.',
Em='Emanonsahi:BAAANQABCgQIBAAAAA==.Emmel:BAAANQADCgcIDQAAAA==.',
Eq='Equeslucis:BAAANQAECggIBAAAAA==.',
Er='Eromir:BAAANQAECgQIBwABNQAECgUICwAGAAAAAA==.Eryi:BAAANQAECgIIAgAAAA==.',
Ev='Eviserator:BAAANQADCgYIDAAAAA==.',
Fa='Fable:BAAANQAECggIEwAAAA==.Faegen:BAAANQADCgMJAwAAAA==.Fallumn:BAAANQADCgEIAQAAAA==.Fangytooth:BAAANQADCgYIBgABNQAECgcIEQAGAAAAAA==.Faze:BAAANQAECgUICgAAAA==.',
Fb='Fbitortamilf:BAAANQAECgUIBQAAAA==.',
Fe='Fenlian:BAAANQADCgIIAgAAAA==.Feydoria:BAAANQAECgQIBAAAAA==.',
Fi='Firstfira:BAAANQAECgIIAwAAAA==.',
Fr='Frontman:BAABNQAECn8ZAAMJAAcKHBlAVAAaAgAJAAcKHBlAVAAaAgAKAAIKjQ3DXQGBAAAAAA==.Frostscythe:BAAANQABCgQIAgAAAA==.',
Fu='Funkycolors:BAAANQAECgQIBAABNQAECggIGgARADcXAA==.',
Ga='Gabomonk:BAAANQADCgEIAQABNQAECgIIAgAGAAAAAA==.Gavrael:BAAANQADCgQIBwAAAA==.',
Ge='Genma:BAAANQAECgIIAwAAAA==.Gewch:BAAANQAECgQIBAAAAA==.',
Gi='Gitgudder:BAAANQAECgIIAwAAAA==.',
Gl='Gloçk:BAAANQAECgcIDwAAAA==.',
Go='Goofy:BAAANQAECggICwAAAA==.',
Gr='Graeae:BAAANQAECgIIAgAAAA==.Grimaldi:BAAANQAECgUICQAAAA==.Grimvaka:BAAANQADCgYIBwAAAA==.Gripforceone:BAAANQAECggIAQAAAA==.',
Gu='Gunduin:BAABNQAECn8nAAIEAAcKgRfabgAxAgAEAAcKgRfabgAxAgAAAA==.',
Gy='Gyda:BAABNQAECn81AAMSAAkKQh1yHQD6AgASAAkKQh1yHQD6AgATAAIKCgxKIABdAAAAAA==.Gyuyuki:BAABNQAECn8mAAIHAAkKQAskcADMAQAHAAkKQAskcADMAQAAAA==.',
['Gó']='Gódofwàr:BAAANQAECgIIAgAAAA==.',
Ha='Haggish:BAAANQAECgIIAgAAAA==.Hakeo:BAEBNQAECn8YAAIUAAcK1SJWCQC1AgAUAAcK1SJWCQC1AgAAAA==.Hanokan:BAAANQADCgIIAgAAAA==.',
He='Heidie:BAAANQAECgUIBgAAAA==.Hermin:BAAANQADCggIDgAAAA==.',
Hi='Hikomosil:BAABNQAECn8WAAIBAAcKiA1oCwCzAQABAAcKiA1oCwCzAQAAAA==.',
Ho='Holdmybeerz:BAAANQADCgUIBQAAAA==.Homiekissér:BAAANQAECgYICAAAAA==.',
['Hë']='Hëllen:BAAANQADCgIIAgAAAA==.',
['Hú']='Húñtrèss:BAAANQAECgEIAgAAAA==.',
Im='Imakittycat:BAABNQAECn8jAAIVAAgKvh17FACiAgAVAAgKvh17FACiAgAAAA==.Impared:BAAANQAECgYIBgABNQAECggIEAAGAAAAAA==.',
Is='Isummon:BAAANQADCgEIAQAAAA==.',
Iv='Ivey:BAAANQADCggICwAAAA==.',
Ja='Jacburton:BAAANQADCgEIAQAAAA==.Jacenne:BAAANQAECgEIAgAAAA==.',
Je='Jenesis:BAABNQAECn8hAAMKAAkKBh2kOADrAgAKAAkKBh2kOADrAgAJAAEKHgMqMAEkAAAAAA==.',
Jo='Josephyn:BAABNQAECn8bAAIJAAkKfBMYSABEAgAJAAkKfBMYSABEAgABNQAFFAQICwAFALsgAA==.Jotaro:BAAANQADCgUIBQAAAA==.',
Ju='Juggernåut:BAAANQADCgMIAwAAAA==.',
Ka='Kaale:BAAANQABCgUIBwABNQAECgUIDgAGAAAAAA==.Kahoa:BAAANQAECgQIBAAAAA==.Kakuta:BAABNQAECn8tAAIJAAkK0yAtDQBfAwAJAAkK0yAtDQBfAwAAAA==.Kakutæ:BAAANQAECgQIBwABNQAECgkJLQAJANMgAA==.Kalru:BAAANQADCgQIAQAAAA==.Kalypsso:BAAANQADCgMIAwAAAA==.Kargar:BAAANQAECgEJAgAAAA==.Karot:BAAANQAECgUICgAAAA==.Katharsis:BAABNQAECn8gAAIKAAkK2BYpdABBAgAKAAkK2BYpdABBAgAAAA==.',
Ke='Keit:BAEANQADCgUIBQABNQAFFAQICgAWAEoWAA==.Keévs:BAAANQADCgUIBQAAAA==.',
Kh='Khalidisi:BAABNQAECn8bAAIJAAgK3BwWKwC5AgAJAAgK3BwWKwC5AgAAAA==.Khalizar:BAAANQADCgUIBQAAAA==.Khanna:BAAANQADCgIIAgAAAA==.Khenja:BAAANQADCgUIBQAAAA==.',
Ki='Killinthyme:BAAANQADCgYIBgAAAA==.',
Kk='Kkiilleerr:BAAANQADCgcIBwAAAA==.',
Ko='Korath:BAAANQABCgIIAgAAAA==.Korbulo:BAAANQAECgUIBwAAAA==.Korlothel:BAAANQABCgIIAgABNQAECggIGQAEANUWAA==.',
Kr='Kriptos:BAAANQADCgEIAQABNQADCgYICAAGAAAAAA==.Kronar:BAAANQADCgYICQAAAA==.Kronu:BAAANQADCgYIBgAAAA==.Krumpus:BAAANQAECgEIAQAAAA==.Kryma:BAAANQAECgMIAwAAAA==.',
Ku='Kungfuuy:BAAANQADCgQIBgAAAA==.',
Ky='Kylogos:BAAANQAECgEIAQAAAA==.Kynsong:BAABNQAECn8eAAMSAAgK3Q7xcgC/AQASAAgK3Q7xcgC/AQATAAEKJAFONAAGAAAAAA==.Kysia:BAAANQAECgUICQABNQAFFAMIBgAKALIOAA==.',
['Ké']='Kéévály:BAAANQADCgYIBgAAAA==.',
['Kî']='Kîrah:BAABNQAECn8UAAISAAgK9SA9GQAOAwASAAgK9SA9GQAOAwAAAA==.',
Le='Lerazal:BAAANQAECgcIDwAAAA==.Leshah:BAAANQADCgUIBQAAAA==.Lexanteus:BAAANQADCgUIBQABNQAECgcIDwAGAAAAAA==.',
Li='Liir:BAAANQAECgUIBQAAAA==.Lilbilly:BAAANQAECgEIAQAAAA==.Lildh:BAABNQAECn8VAAIXAAYKzw5SFwA2AQAXAAYKzw5SFwA2AQAAAA==.',
Lo='Lorastyrell:BAAANQABCgEIAQAAAA==.Loughalnan:BAAANQADCgQIBAABNQAECgkJIAAEANMeAA==.Loìsbethe:BAAANQAECgQIBgAAAA==.',
Lu='Luciferra:BAABNQAECn8sAAISAAkKkBw8GQAOAwASAAkKkBw8GQAOAwABNQAFFAQICwAFALsgAA==.Luu:BAAANQAECgEIAgAAAA==.',
Ly='Lytho:BAAANQAECgUIBgAAAA==.',
Ma='Magelock:BAAANQAECgIIAgABNQAECgQIBwAGAAAAAA==.Magickul:BAAANQAECgYIAQABNQAECgQIBwAGAAAAAA==.Malakii:BAAANQADCgEIAQAAAA==.Maletsy:BAAANQAECgYIEAABNQAECgcIJwAEAIEXAA==.Maliboo:BAAANQAECgcIEAAAAA==.Mandalor:BAAANQADCgEIAQAAAA==.Maxamus:BAABNQAECn8mAAMYAAkKMB8yIwAqAwAYAAkKMB8yIwAqAwAZAAEKVh/+KQBdAAAAAA==.',
Mc='Mceuan:BAAANQADCgIIAgAAAA==.',
Me='Medarisa:BAAANQAECgQIDgAAAA==.Mederia:BAAANQADCgEIAQAAAA==.Medívh:BAAANQAECgQIBQAAAA==.Meelly:BAAANQADCgQIBAAAAA==.Melisandr:BAAANQADCgUIBQAAAA==.Merkenier:BAABNQAECn8ZAAIDAAcK9QqtWwBfAQADAAcK9QqtWwBfAQAAAA==.Merkshamalot:BAAANQAECgEIAQABNQAECgcIGQADAPUKAA==.Merkur:BAAANQADCggIJAABNQAECgcIGQADAPUKAA==.Merkurry:BAAANQADCgQIBQABNQAECgcIGQADAPUKAA==.',
Mo='Modifiedmix:BAAANQADCgUICwAAAA==.Monatazumaa:BAAANQADCggIDwAAAA==.',
Mu='Mugato:BAAANQABCgEIAQAAAA==.Murdette:BAAANQAECgUIBQABNQAECgkJJgAYAJQjAA==.',
My='Mystych:BAAANQAECgYIBwAAAA==.',
['Må']='Mågi:BAAANQAECgQICAAAAA==.',
['Mé']='Méabh:BAAANQADCgMIAwABNQAECgQIBgAGAAAAAA==.',
['Mö']='Möôôöõöóòòõô:BAABNQAECn8xAAMJAAgKWhNnXwD3AQAJAAgKWhNnXwD3AQAKAAUKYA6PGQHtAAAAAA==.',
Na='Nakednwasted:BAAANQADCgYIBgAAAA==.Nanakii:BAAANQAECgIJAwAAAA==.Nathrold:BAAANQAECgQIBgABNQAECgcIDwAGAAAAAA==.',
Ne='Neptune:BAACNQAFFH8LAAIFAAQKuyC6DAB8AQAFAAQKuyC6DAB8AQA1AAQKfy0AAgUACQqKINUcAPgCAAUACQqKINUcAPgCAAAA.Nerfpaladins:BAAANQAECgUIBgAAAA==.Nerfpriests:BAABNQAECn8ZAAIaAAgKORRMIwAVAgAaAAgKORRMIwAVAgAAAA==.Nerissl:BAAANQADCgIIAgAAAA==.',
Ni='Niemwa:BAAANQADCgQIBAAAAA==.Nightbird:BAAANQAECgEIAQAAAA==.Nightwingqt:BAAANQAECgYIBwAAAA==.Nimrock:BAAANQABCgIIAgAAAA==.Ninediewatt:BAAANQADCgQIBQAAAA==.',
['Nè']='Nèo:BAAANQADCgYIEAAAAA==.',
Ob='Obsaedia:BAAANQAECgEIAQABNQAECgcIDQAGAAAAAQ==.',
Od='Odysseus:BAAANQAECgcICgAAAA==.',
Ok='Oktobra:BAAANQAECgUIEAAAAA==.',
On='Onos:BAAANQADCggJCAAAAA==.',
Or='Orillin:BAABNQAECn8fAAMbAAcKWx3sKwA6AgAbAAcKWx3sKwA6AgAcAAIKdg+VyABXAAAAAA==.Orioan:BAABNQAECn8cAAIKAAgKhR+QRADDAgAKAAgKhR+QRADDAgAAAA==.',
Os='Osun:BAAANQADCggIEAAAAA==.Osÿrus:BAAANQADCgQIBAAAAA==.',
Pa='Paddy:BAAANQAECgQIBgAAAA==.Palantyr:BAACNQAFFH8GAAIHAAMK0g8DHADcAAAHAAMK0g8DHADcAAA1AAQKfz8AAgcACQpDGVItAMUCAAcACQpDGVItAMUCAAAA.Pallytings:BAAANQADCgQIBAAAAA==.Panurita:BAABNQAECn8bAAIFAAkK6xkIJwDGAgAFAAkK6xkIJwDGAgAAAA==.',
Pe='Pellidillion:BAAANQADCgcICwAAAA==.Pepas:BAAANQAECggICAAAAA==.',
Po='Polgára:BAAANQAECgIIAgAAAA==.',
Pr='Prepotente:BAAANQADCgUIBQAAAA==.',
Pu='Purity:BAAANQAECgMIAwAAAA==.',
Qe='Qevelana:BAAANQADCgMIBAAAAA==.',
Qu='Quetzalcoatl:BAAANQADCgUICQAAAA==.',
Ra='Raambox:BAABNQAECn8cAAIYAAcKfQxJuACKAQAYAAcKfQxJuACKAQAAAA==.Raddish:BAAANQAECgYIEAAAAA==.Raedl:BAAANQAECgYICwAAAA==.Ragriefy:BAAANQADCgUIBQAAAA==.Raiinn:BAAANQADCgEIAQAAAA==.Ramantu:BAAANQADCgIJAgAAAA==.Ramranch:BAAANQAECgQIBQABNQAECggIGAAFANcYAA==.Randay:BAAANQAECggIDQAAAA==.Rathix:BAAANQABCgIIAQAAAA==.Raylee:BAAANQAECgEIAQAAAA==.Razuki:BAAANQAECgQICQAAAA==.',
Re='Reeker:BAAANQABCgQIAgAAAA==.Retton:BAAANQADCgEIAQABNQAECgUIDgAGAAAAAA==.',
Rh='Rhovanion:BAAANQADCgUIBQABNQAECggIHwAQALgMAA==.Rhuac:BAAANQADCggICgAAAA==.',
Ri='Riddik:BAAANQADCggIDQAAAA==.Rifle:BAAANQADCggIEAABNQAECggIKAAHAJERAA==.Rika:BAAANQAECgIIAgAAAA==.',
Ro='Robolich:BAAANQAECggIEQAAAA==.Rosefist:BAEANQAECgUIBQAAAA==.Rosemourne:BAEANQADCggICAABNQAECgUIBQAGAAAAAA==.Roshwyn:BAAANQAECgIIBgAAAA==.Rottedmeat:BAAANQAECggICwAAAA==.',
Ru='Rubmytotems:BAAANQAECgUIEgAAAA==.Ruckus:BAABNQAECn8lAAIKAAkKHxfFbABUAgAKAAkKHxfFbABUAgAAAA==.',
Rx='Rxmblock:BAAANQAECgEIAQAAAA==.',
Sa='Saelin:BAAANQAECgQIBwABNQAECgUIDgAGAAAAAA==.Sareenastar:BAABNQAECn8ZAAISAAgKUCQ9EwAwAwASAAgKUCQ9EwAwAwAAAA==.',
Se='Seafood:BAAANQAECggIDQAAAA==.Sennara:BAAANQAECgQICAABNQAECgQICAAGAAAAAA==.Sephiróth:BAAANQAECgIIAQAAAA==.Serenitynow:BAAANQADCgYICAAAAA==.Sethworgen:BAAANQADCggICAAAAA==.',
Sh='Shadowlillee:BAAANQABCgIIAgAAAA==.Shadowmeteor:BAABNQAFFH8GAAIaAAMK5QN8EgCZAAAaAAMK5QN8EgCZAAAAAA==.Shakey:BAAANQAECgEIAQAAAA==.Shalen:BAAANQAECgYIBwAAAA==.Shamrox:BAAANQAECgQIBQAAAA==.Sharar:BAAANQAECgUJBwAAAA==.Sharker:BAAANQADCgMIAwAAAA==.Sharkerprest:BAAANQADCgYIBgAAAA==.Sharkerwarlo:BAAANQAECgEJAQAAAA==.Sharpenator:BAAANQAECgEIAQAAAA==.Sheraa:BAAANQAECgQIBgAAAA==.Shieldknight:BAAANQAECgQIBQAAAA==.Shiftystrike:BAAANQAECgQICQAAAA==.Shifushield:BAAANQADCggIEQAAAA==.Shirazormu:BAAANQAECgEIAQABNQAECgUIBQAGAAAAAA==.Shrike:BAAANQADCgIIBAABNQAFFAcIFwAaABESAA==.',
Si='Silentwindy:BAAANQADCgYJCQAAAA==.Silmarkthree:BAABNQAECn8dAAIdAAgKAQ4JwwD8AQAdAAgKAQ4JwwD8AQAAAA==.Sinbåd:BAAANQADCggICgAAAA==.',
Sk='Skol:BAABNQAECn8fAAIQAAgKuAwRWwCDAQAQAAgKuAwRWwCDAQAAAA==.',
Sl='Slipknoth:BAACNQAFFH8VAAMaAAcKrRTdBADyAQAaAAcKrRTdBADyAQASAAEKJwvyMwBGAAA1AAQKfyoABBoACQqIIuwKADIDABoACQqIIuwKADIDABIAAwoTCzjQAK4AABMAAQrQGWojAEsAAAAA.',
Sn='Snakeplizken:BAAANQADCggIAQAAAA==.',
So='Sorean:BAACNQAFFH8OAAILAAUKThacAAC3AQALAAUKThacAAC3AQA1AAQKfycAAwsACQqlH+UCAPQCAAsACQqlH+UCAPQCAB4AAQpjDf2HADUAAAAA.Sorrel:BAAANQADCggICQAAAA==.',
Sp='Specialmove:BAAANQAECgUIBQAAAA==.',
St='Staghealz:BAAANQADCgYICAAAAA==.Staldorn:BAAANQADCgIIAgAAAA==.Starlet:BAAANQADCgIIAgAAAA==.Stifs:BAAANQAECgYIEwAAAA==.Stinkinglily:BAAANQABCgQIBwAAAA==.Stonebeard:BAAANQADCggIIQAAAA==.Stormstream:BAAANQADCgMICQAAAA==.',
Su='Suelustra:BAAANQAECgYIDgAAAA==.',
Sy='Sykotyk:BAABNQAECn8hAAIFAAkK/xcHOgB0AgAFAAkK/xcHOgB0AgAAAA==.',
Ta='Tadagain:BAAANQAECgUIEAAAAA==.Talairn:BAAANQADCgYICQAAAA==.Talix:BAAANQAECgIIAgAAAA==.Tamaira:BAAANQAECgUICQAAAA==.Tankybears:BAAANQAECgUIDgAAAA==.Tart:BAAANQAECgQIBAAAAA==.',
Te='Telekinesis:BAABNQAECn8bAAQEAAgKOxImdwAeAgAEAAgKOxImdwAeAgAeAAYKwAY+SwAEAQALAAEKAACSEwAxAAAAAA==.Tenara:BAABNQAECn8cAAMFAAgK9RzuOwBtAgAFAAgK9RzuOwBtAgAHAAMKmA1f+ACbAAABNQAECgUIDgAGAAAAAA==.Teos:BAAANQADCgYIBgABNQAECggIHwAQALgMAA==.',
Th='Thalanor:BAAANQABCggIGQAAAA==.Thaliak:BAAANQADCgYIBwABNQAECgQIBwAGAAAAAA==.Tharris:BAAANQADCgYIBgAAAA==.Tholin:BAAANQADCggIEwAAAA==.Thunderlily:BAAANQAECgYIEgAAAA==.',
Ti='Tinychaos:BAAANQAECgEIAQAAAA==.Tirra:BAAANQADCggIDgAAAA==.',
Tr='Tracther:BAAANQADCgYIDwAAAA==.Trapps:BAAANQADCgYIDAAAAA==.Treedemon:BAAANQADCgYIBgAAAA==.Treelock:BAAANQAECgcIEAAAAA==.Trelapin:BAAANQADCggIDQAAAA==.',
Tw='Twinrova:BAAANQADCggICAAAAA==.',
Ty='Tybearon:BAAANQADCgYIBgAAAA==.Tyrelitha:BAAANQADCgQIBgAAAA==.',
Uh='Uhtrad:BAAANQAECgcIEQAAAA==.Uhura:BAAANQADCgYIBgAAAA==.',
Ul='Ulfrir:BAAANQADCgYIBgAAAA==.Ullhr:BAAANQADCgYICwAAAA==.Ultradukes:BAAANQADCgEIAQAAAA==.',
Ur='Ursaline:BAAANQAECgEIAQABNQAECgYIBgAGAAAAAA==.',
Va='Valock:BAAANQAECgQIBgAAAA==.Vanshifty:BAABNQAECn80AAIVAAgKMh/5EADJAgAVAAgKMh/5EADJAgAAAA==.',
Ve='Venli:BAAANQAECgIIAgAAAA==.',
Vo='Voidentine:BAAANQABCggIBgAAAA==.',
Vy='Vyx:BAAANQAECgIIAwAAAA==.',
Wa='Waffle:BAAANQAECgYIEAAAAA==.Wardaelos:BAAANQADCggIEgAAAA==.Wargue:BAAANQAECgUICQAAAA==.Wasprepared:BAAANQADCgQIBAAAAA==.Watson:BAAANQAECgQIBAABNQAECgQICAAGAAAAAA==.',
We='Weeaboos:BAAANQADCgQICgAAAA==.Welindis:BAAANQADCgcJBwABNQAECgIIAgAGAAAAAA==.Wenus:BAAANQABCgQIAwAAAA==.',
Wh='Whofurmoover:BAAANQAECgQICQAAAA==.',
Wi='Winrodan:BAABNQAECn8VAAIMAAcK7yEsFQBWAgAMAAcK7yEsFQBWAgABNQAECgcIFQAMAO8hAA==.Wizzard:BAAANQAECgcIDQAAAQ==.',
['Wó']='Wóof:BAAANQADCgMIAwAAAA==.',
Xa='Xaandu:BAAANQADCgQIBAAAAA==.Xaris:BAAANQAECgUIDwABNQAECggIHgASAN0OAA==.',
Xi='Xiladin:BAAANQAECgEIAgAAAA==.',
Xt='Xtremes:BAAANQADCgcIBwAAAA==.',
['Xí']='Xíe:BAAANQAECgcIEwAAAA==.',
Yi='Yimm:BAAANQADCgEIAQAAAA==.',
Yo='Yourdadsadad:BAAANQAECgUIBQABNQAFFAcIEgAYAFsgAA==.',
['Yø']='Yø:BAAANQAECgQIBAAAAA==.',
Za='Zalendria:BAAANQABCgQIBAAAAA==.',
Zb='Zbm:BAAANQAECgIJAgAAAA==.',
Ze='Zeldy:BAABNQAECn8dAAIEAAkKmxZ5NQDIAgAEAAkKmxZ5NQDIAgAAAA==.Zenthareal:BAABNQAECn8iAAMfAAcKLRZDLQDUAQAfAAcKLRZDLQDUAQAWAAEKYwiukgAyAAAAAA==.Zenzi:BAAANQADCgcIFgAAAA==.',
Zm='Zmaster:BAAANQAECgUIEAAAAA==.',
Zu='Zunarri:BAAANQADCgYJCAABNQAECgYICwAGAAAAAA==.',
Zw='Zwar:BAAANQADCgMJAwABNQAECgUIEAAGAAAAAA==.',
Zy='Zyri:BAAANQAECgEIAQAAAA==.',
['Ða']='Ðark:BAABNQAECn8oAAIEAAkKWx/zHAAjAwAEAAkKWx/zHAAjAwAAAA==.',
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
