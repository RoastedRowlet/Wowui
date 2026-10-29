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

local lookup = {'Warlock-Affliction','Warlock-Destruction','Paladin-Protection','Shaman-Elemental','Druid-Balance','Hunter-BeastMastery','Shaman-Restoration','Unknown-Unknown','Paladin-Holy','Monk-Windwalker','Hunter-Marksmanship','Priest-Holy','Priest-Shadow','Paladin-Retribution','Hunter-Survival','Shaman-Enhancement','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Demonology','Priest-Discipline','Warrior-Protection','Druid-Restoration','DemonHunter-Havoc','Evoker-Devastation','DemonHunter-Vengeance','Warrior-Arms','Warrior-Fury','Druid-Guardian','Mage-Arcane','Mage-Frost','Monk-Mistweaver','DemonHunter-Devourer',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abdalhazred:BAACNQAFFH8QAAIBAAUKriCKAAAaAQABAAUKriCKAAAaAQA1AAQKfzcAAwEACgqaIhoBAGEDAAEACgqVIhoBAGEDAAIAAgqsGTdMAJsAAAAA.Abilus:BAABNQAECn8jAAIDAAYKYhkqHAAbAQADAAYKYhkqHAAbAQAAAA==.Abolis:BAABNQAECn8bAAIEAAYKCgkXdgC0AAAEAAYKCgkXdgC0AAAAAA==.',
Ad='Adarlan:BAAANQAECgIIAgAAAA==.Adolin:BAAANQAECgEIAgAAAA==.',
Ae='Aelianna:BAAANQAECgQIAwAAAA==.',
Ah='Ahqwanken:BAAANQADCgIIAgAAAA==.',
Ai='Aintnowei:BAAANQAECgQIBAAAAA==.',
Al='Allina:BAAANQADCgYIBgAAAA==.Alnara:BAAANQAECgUICwAAAA==.',
Am='Amoradis:BAAANQADCgYIDQAAAA==.',
An='Anarran:BAAANQAECgIIAgABNQAECgkJGAAFAIsMAA==.Animalfury:BAABNQAECn8pAAIFAAcK4QgeLwAaAQAFAAcK4QgeLwAaAQAAAA==.Anthestria:BAAANQAECgQIBwAAAA==.',
Aq='Aqurala:BAABNQAECn8vAAIGAAoK4CBkFgBBAwAGAAoK4CBkFgBBAwAAAA==.',
Ar='Arasham:BAAANQAECgQIBAABNQAECgoKIQAGACwWAA==.Aravenn:BAABNQAECn8hAAIGAAoKLBZqeAAeAgAGAAoKLBZqeAAeAgAAAA==.Arionaa:BAAANQABCgIIAgAAAA==.Arkangel:BAAANQADCgYIBgAAAA==.Artemesia:BAAANQAECgYICQABNQAFFAYIEQAHAMIdAA==.Artison:BAAANQADCgYIBgABNQAECgYIDgAIAAAAAA==.',
As='Ashiru:BAAANQADCgMIBQAAAA==.Assandra:BAAANQADCgUIBQAAAA==.',
At='Ateup:BAAANQADCgQJBQABNQAECgUICwAIAAAAAA==.Athenos:BAAANQAECgMIAQAAAA==.Atlás:BAAANQAECgUIBwAAAA==.',
Au='Aurum:BAABNQAECn8ZAAIJAAkKghH8RQB+AQAJAAkKghH8RQB+AQAAAA==.',
Av='Avatartele:BAABNQAECn85AAIEAAoKYxeSHAAXAgAEAAoKYxeSHAAXAgAAAA==.Avatartouka:BAABNQAECn9NAAMHAAoK3iRpBACXAwAHAAoK3iRpBACXAwAEAAcK7Bh8XAD4AAAAAA==.Avrala:BAAANQADCgIJAgAAAA==.Avraria:BAAANQAECggIDAAAAA==.Avylastral:BAAANQAECgIIAgAAAA==.',
Az='Azshaxa:BAACNQAFFH8VAAIKAAUKqhfEBQDlAAAKAAUKqhfEBQDlAAA1AAQKfy0AAgoACgr1G14ZAHkCAAoACgr1G14ZAHkCAAAA.',
['Aí']='Aísling:BAAANQAECgUICQAAAA==.',
Ba='Bagador:BAACNQAFFH8GAAILAAMKoQPtCwCnAAALAAMKoQPtCwCnAAA1AAQKfxkAAgsACgoGE1EnABACAAsACgoGE1EnABACAAAA.Barby:BAAANQAECgEIAQAAAA==.Barrs:BAAANQADCgMIAwAAAA==.',
Be='Bearbuthealz:BAAANQAECgIIAgAAAA==.Beautifulluv:BAABNQAECn8hAAMMAAoKzxNEUgBpAQAMAAoKzxNEUgBpAQANAAcKjgqYQAArAQAAAA==.Bekabeka:BAACNQAFFH8QAAIJAAUKXRVjBwCFAQAJAAUKXRVjBwCFAQA1AAQKfzkAAwkACgoyH4YZABIDAAkACgoyH4YZABIDAA4AAQqJDUo5ATwAAAAA.Bekabekabeka:BAAANQABCggJAQABNQAFFAUIEAAJAF0VAA==.Belfour:BAAANQADCgQIBAAAAA==.Bera:BAAANQAECggIAwAAAA==.Berashiv:BAAANQAECggIBgAAAA==.',
Bi='Billybobjr:BAABNQAECn8hAAIHAAoK1xwEKgAFAgAHAAoK1xwEKgAFAgAAAA==.',
Bl='Blackbart:BAAANQADCgQIBAAAAA==.Bloodar:BAAANQAECggICQAAAA==.',
Bo='Bonski:BAAANQAECgYICQAAAA==.Boomdoom:BAAANQADCgQIBAAAAA==.Boosterman:BAABNQAECn8fAAMOAAgKnB4dWwCHAgAOAAgKnB4dWwCHAgAJAAIKaQ2CxAA1AAAAAA==.',
Br='Brakkar:BAAANQAECgMIBQAAAA==.Braxxis:BAAANQAECggIEAABNQAFFAYIFwAPAHocAA==.Breadstick:BAAANQAECgQIDAAAAA==.Bress:BAAANQADCgYIBgABNQAECgkJHAADAH8hAA==.Brihunts:BAAANQAECgcIEAAAAA==.Britotems:BAAANQAECgEIAQAAAA==.Brutaal:BAAANQADCgQJBAAAAA==.Bruutaal:BAAANQAECgQIAwAAAA==.Bryndel:BAAANQADCgYIBgAAAA==.',
Bu='Bubsydogo:BAAANQADCggICAAAAA==.',
Ca='Cacellice:BAAANQADCggICAAAAA==.Canoodles:BAAANQAECgcICQAAAA==.',
Ce='Celaian:BAAANQAECgUICAABNQAECgQICAAIAAAAAA==.Celpanda:BAAANQAECgQICAAAAA==.',
Ch='Chadee:BAAANQADCggICAABNQAECggIFQAIAAAAAA==.Charybdia:BAAANQADCggJGwAAAA==.Cheesecake:BAABNQAECn8XAAIGAAgKIg85jQDwAQAGAAgKIg85jQDwAQAAAA==.Chidõri:BAABNQAECn8kAAQQAAoKgRfAEQBNAgAQAAkKhhXAEQBNAgAHAAUKXBamTgBbAQAEAAQKNBQa0wDuAAAAAA==.Chunni:BAABNQAECn8oAAMRAAoKnAgiCgAzAQARAAoK4wciCgAzAQAKAAcKxQUAQQAPAQAAAA==.',
Co='Codap:BAAANQADCgEIAQAAAA==.Coolbeard:BAAANQAECgMIAwAAAA==.Cortex:BAAANQAECgYICgAAAA==.',
Cr='Crayonman:BAABNQAECn8hAAIQAAoK/BnJBQCBAgAQAAoK/BnJBQCBAgAAAA==.Cronus:BAAANQAECgQICgABNQAECgcIDwAIAAAAAA==.Cruelkitty:BAAANQAECgQIBQAAAA==.',
Cy='Cyralai:BAAANQADCgEIAQAAAA==.',
Da='Dahlinar:BAAANQAECgQIDAAAAA==.Dalov:BAABNQAECn8fAAMJAAcKSR4RSQBDAgAJAAcKSR4RSQBDAgAOAAQK1R8H5QBRAQAAAA==.Damageworg:BAAANQAECgEIAQAAAA==.Dankley:BAAANQAECgUICgAAAA==.Danystorm:BAAANQADCgcIBwABNQAFFAYIEQAHAMIdAA==.Darkomenz:BAAANQADCgEIAQAAAA==.',
Dd='Ddream:BAAANQADCgEIAQABNQAECgMIAQAIAAAAAA==.',
De='Deaddude:BAABNQAECn8oAAISAAgKvxujLABlAgASAAgKvxujLABlAgABNQAECgoKGQAEABMXAA==.Deathboi:BAABNQAECn8hAAITAAkKYg5EHQCKAQATAAkKYg5EHQCKAQAAAA==.Deathburgur:BAAANQAECggICwAAAA==.Deathcuddles:BAABNQAECn8UAAIUAAcKSgK5hgCWAAAUAAcKSgK5hgCWAAAAAA==.Dedcow:BAABNQAECn8dAAISAAgKARJjHACvAQASAAgKARJjHACvAQAAAA==.',
Di='Diana:BAABNQAECn8tAAIGAAkKyArZTAC2AQAGAAkKyArZTAC2AQAAAA==.',
Do='Dontjudgemê:BAAANQADCgYJCgAAAA==.Dorcina:BAAANQADCgcICAAAAA==.Downpour:BAAANQADCgUIBQAAAA==.',
Dr='Dragam:BAAANQAECgQIBAABNQAECgkJIAAVAEUYAA==.Dragonwarrio:BAABNQAECn8rAAIKAAoKER0xCQB3AgAKAAoKER0xCQB3AgAAAA==.Draltina:BAABNQAECn8XAAICAAkK+wf3IABpAQACAAkK+wf3IABpAQAAAA==.Drazira:BAAANQAECgEIAQAAAA==.Dresstokill:BAAANQADCggJEQAAAA==.Drmonkborg:BAAANQAECgUICwABNQAECgoKIQAMAK4fAA==.Drovis:BAAANQADCgIIAgAAAA==.Druzzlek:BAAANQADCggIEQAAAA==.',
Du='Dubalnuar:BAAANQADCgUIEAAAAA==.Dubalpally:BAAANQADCgcIBwAAAA==.Dubaltrok:BAAANQADCgYIDgAAAA==.Dudde:BAABNQAECn8ZAAMEAAoKExenNwCYAgAEAAoKExenNwCYAgAQAAIKNAciJABvAAAAAA==.Dulapin:BAAANQADCgIIAgAAAA==.Duskfu:BAABNQAECn8lAAIKAAoKlxs8CwBGAgAKAAoKlxs8CwBGAgAAAA==.Dustylock:BAABNQAECn8gAAMVAAkKRRi1VABXAgAVAAkKRRi1VABXAgACAAEKzQeAfQAvAAAAAA==.',
Ea='Earthele:BAABNQAECn8bAAMEAAcKLwp4XgDyAAAEAAcKLwp4XgDyAAAHAAIK7AjRCwFQAAAAAA==.',
El='Elderblood:BAAANQADCgYIBgAAAA==.Elfcaster:BAAANQAECgEIAgAAAA==.Elfowl:BAAANQADCgYIBwABNQAECgkJKQAMALEMAA==.',
Em='Emanonsahi:BAAANQABCgQIBgAAAA==.Emmel:BAAANQADCgcIDQAAAA==.',
Eq='Equeslucis:BAAANQAECggIBAAAAA==.',
Er='Eromir:BAAANQAECgQIBwABNQAECgUICwAIAAAAAA==.Eryi:BAAANQAECgMIBgAAAA==.',
Ev='Eviserator:BAAANQADCgYIDAAAAA==.',
Fa='Fable:BAABNQAECn8fAAIJAAkKzhiwLAD2AQAJAAkKzhiwLAD2AQAAAA==.Faegen:BAAANQADCgMIAwAAAA==.Fallumn:BAAANQADCgEIAQAAAA==.Fangytooth:BAAANQADCgYIBgABNQAECgoKIQAQAPwZAA==.Faze:BAAANQAECgUICgAAAA==.',
Fb='Fbitortamilf:BAAANQAECgUICQAAAA==.',
Fe='Fenlian:BAAANQADCgIIAgAAAA==.Feydoria:BAAANQAECgQIBAAAAA==.',
Fi='Firstfira:BAAANQAECgMIAwAAAA==.',
Fr='Frontman:BAABNQAECn8cAAMJAAgKiBllVQAZAgAJAAgKiBllVQAZAgAOAAIKjQ0DYwGBAAAAAA==.',
Fu='Funkycolors:BAAANQAECgQIBAABNQAECgkJIAAVAEUYAA==.',
Ga='Gabomonk:BAAANQADCgEIAQABNQAECgIIAgAIAAAAAA==.Gavrael:BAAANQADCgQIBwAAAA==.',
Ge='Genma:BAAANQAECgQIBwAAAA==.Gewch:BAAANQAECgQIBAAAAA==.',
Gi='Gitgudder:BAAANQAECgQIBQAAAA==.',
Gl='Gloçk:BAAANQAECgcIDwABNQAECggIEAAIAAAAAA==.',
Go='Goofy:BAAANQAECggIDgAAAA==.',
Gr='Graeae:BAAANQAECgIIAgAAAA==.Grimaldi:BAABNQAECn8YAAIFAAkKiwx7IgBxAQAFAAkKiwx7IgBxAQAAAA==.Grimvaka:BAAANQADCgYIBwAAAA==.Gripforceone:BAAANQAECggIAQAAAA==.',
Gu='Gunduin:BAABNQAECn8uAAIGAAkKrxamcAAwAgAGAAkKrxamcAAwAgAAAA==.',
Gw='Gwinden:BAAANQADCgUIBQAAAA==.',
Gy='Gyda:BAABNQAECn9DAAMMAAoKCiACHgD5AgAMAAoKCiACHgD5AgAWAAIKCgyhIABdAAAAAA==.Gyuyuki:BAABNQAECn8zAAIEAAoKYg21LgCgAQAEAAoKYg21LgCgAQAAAA==.',
['Gó']='Gódofwàr:BAAANQAECgIIAgAAAA==.',
Ha='Haggish:BAAANQAECgQIBwAAAA==.Hakeo:BAEBNQAECn8jAAIXAAkKeyJxCQC1AgAXAAkKeyJxCQC1AgAAAA==.',
He='Heidie:BAAANQAECgUIBgAAAA==.Hermin:BAAANQADCggIDgAAAA==.',
Hi='Hikomosil:BAABNQAECn8WAAIBAAcKiA18CwCzAQABAAcKiA18CwCzAQAAAA==.',
Ho='Holdmybeerz:BAAANQADCgUIBQAAAA==.Homiekissér:BAAANQAECgcICQAAAA==.',
Hu='Hudsonhawk:BAAANQAECgEIAQAAAA==.',
['Hë']='Hëllen:BAAANQADCgIIAgAAAA==.',
['Hú']='Húñtrèss:BAAANQAECgEIAgAAAA==.',
Im='Imakittycat:BAABNQAECn8pAAIYAAkK5x2+FACiAgAYAAkK5x2+FACiAgAAAA==.Impared:BAAANQAECgYIBgABNQAECggIEAAIAAAAAA==.',
Is='Isummon:BAAANQADCgEIAQAAAA==.',
Iv='Ivey:BAAANQADCggIDAAAAA==.',
Ja='Jacburton:BAAANQADCgEIAQAAAA==.Jacenne:BAAANQAECgEIAgAAAA==.',
Je='Jenesis:BAABNQAECn85AAMOAAoKRiL7CgAdAwAOAAoKRiL7CgAdAwAJAAEKHgOZMwEkAAAAAA==.Jerkme:BAAANQAECggICAAAAA==.',
Jo='Josephyn:BAABNQAECn8kAAIJAAoKTRYJSQBDAgAJAAoKTRYJSQBDAgABNQAFFAYIEQAHAMIdAA==.Jotaro:BAAANQADCgUIBQAAAA==.',
Ju='Juggernåut:BAAANQADCgMIAwAAAA==.',
Ka='Kaale:BAAANQAECgIIAgABNQAECgQIDwAIAAAAAA==.Kahoa:BAAANQAECgQIBAAAAA==.Kakuta:BAABNQAECn83AAIJAAoKliFWDQBfAwAJAAoKliFWDQBfAwAAAA==.Kakutæ:BAAANQAECgYICQABNQAECgoKNwAJAJYhAA==.Kalru:BAAANQADCgYIAwAAAA==.Kargar:BAAANQAECgEJAgAAAA==.Karot:BAAANQAECgUICgAAAA==.Katharsis:BAABNQAECn8mAAIOAAoK/hfodQBBAgAOAAoK/hfodQBBAgAAAA==.',
Ke='Keba:BAAANQAECgIIAgABNQAFFAUIEAAJAF0VAA==.Keit:BAEANQADCgUIBQABNQAFFAUIDQAZAIIWAA==.Keévs:BAAANQADCgUIBQAAAA==.',
Kh='Khalidisi:BAABNQAECn8bAAIJAAgK3BzPKwC4AgAJAAgK3BzPKwC4AgAAAA==.Khalizar:BAAANQADCgUIBQAAAA==.Khanna:BAAANQADCgIIAgAAAA==.Khenja:BAAANQADCgUIBQAAAA==.',
Ki='Killinthyme:BAAANQADCgYIBgAAAA==.',
Kk='Kkiilleerr:BAAANQADCgcIBwAAAA==.',
Ko='Korath:BAAANQABCgIIAgAAAA==.Korbulo:BAAANQAECgUIBwAAAA==.Korlothel:BAAANQABCgIIAgABNQAECgoKIQAGACwWAA==.',
Kr='Kriptos:BAAANQADCgEIAQABNQAECgMIAQAIAAAAAA==.Kronar:BAAANQADCgYICQAAAA==.Krumpus:BAAANQAECgEIAQAAAA==.Kryma:BAAANQAECgMIAwAAAA==.',
Ku='Kungfuuy:BAAANQADCgQIBgAAAA==.',
Ky='Kylogos:BAAANQAECgEIAQAAAA==.Kynsong:BAABNQAECn8lAAMMAAoK4REEQwCmAQAMAAoK4REEQwCmAQAWAAEKJAHzNAAHAAAAAA==.Kysia:BAAANQAECgUICQABNQAFFAMICQAOAC0PAA==.',
['Kî']='Kîrah:BAACNQAFFH8FAAIMAAMK/RgRFgDTAAAMAAMK/RgRFgDTAAA1AAQKfx4AAgwACQpIIbEZAA4DAAwACQpIIbEZAA4DAAAA.',
La='Larcine:BAAANQADCggICAABNQAECgcIEQAIAAAAAA==.',
Le='Lerazal:BAABNQAECn8WAAIaAAoKIRUBCQBuAQAaAAoKIRUBCQBuAQAAAA==.Leshah:BAAANQADCggICwAAAA==.Lexanteus:BAAANQADCgUIBQABNQAECgoKFgAaACEVAA==.',
Li='Liir:BAAANQAECgUIBQAAAA==.Lilbilly:BAAANQAECgIIAQAAAA==.Lildh:BAABNQAECn8cAAIbAAkKCBBEDgDvAAAbAAkKCBBEDgDvAAAAAA==.Liyi:BAAANQAECgEIAQAAAA==.',
Lo='Lorastyrell:BAAANQABCgEIAQAAAA==.Loughalnan:BAAANQADCgQIBAABNQAECgoKLwAGAOAgAA==.Loìsbethe:BAAANQAECgQIBgAAAA==.',
Lu='Luciferra:BAABNQAECn87AAIMAAoK7h/MDwD0AgAMAAoK7h/MDwD0AgABNQAFFAYIEQAHAMIdAA==.Luu:BAAANQAECgMIBAABNQAECgoKHAAJAJUOAA==.',
Ly='Lytho:BAAANQAECgUIBgAAAA==.',
Ma='Madomi:BAAANQAECgEIAQABNQAECgkJLgAGAK8WAA==.Maetromundo:BAAANQADCgcIBwAAAA==.Magelock:BAAANQAECgIIAgABNQAECgQIBwAIAAAAAA==.Magickul:BAAANQAECgYIAQABNQAECgQIBwAIAAAAAA==.Malakii:BAAANQADCgEIAQAAAA==.Maletsy:BAAANQAECgYIEAABNQAECgkJLgAGAK8WAA==.Maliboo:BAABNQAECn8YAAMYAAkKmhQ7LQCyAQAYAAkKmhQ7LQCyAQAFAAMKKAjMmAB2AAAAAA==.Mandalor:BAAANQADCgEIAQAAAA==.Maxamus:BAABNQAECn8tAAMcAAoKDyDyIwApAwAcAAoKwB/yIwApAwAdAAEK2SHOGgBmAAAAAA==.',
Mc='Mceuan:BAAANQADCgIIAgAAAA==.',
Me='Medarisa:BAABNQAECn8VAAIVAAQK4w8TogCsAAAVAAQK4w8TogCsAAAAAA==.Mederia:BAAANQADCgEIAQAAAA==.Medívh:BAAANQAECgUIBwAAAA==.Meelly:BAAANQADCgQIBAAAAA==.Melisandr:BAAANQADCgUIBQAAAA==.Merkenier:BAABNQAECn8fAAMFAAcK+QqKXABfAQAFAAcK+QqKXABfAQAeAAEKAAAfaQAAAAAAAA==.Merkshamalot:BAAANQAECgMIAgABNQAECgcIHwAFAPkKAA==.Merkur:BAAANQADCggIJAABNQAECgcIHwAFAPkKAA==.Merkurry:BAAANQADCgQIBQABNQAECgcIHwAFAPkKAA==.',
Mi='Mieks:BAAANQAECgUIBQAAAA==.Missmayhem:BAAANQAECgQICAAAAA==.',
Mo='Modifiedmix:BAAANQAECgEIAQAAAA==.Monatazumaa:BAAANQADCggIDwAAAA==.Moonfalls:BAAANQAECgIIAgABNQAECgYIEwAIAAAAAA==.',
Mu='Mugato:BAAANQABCgEIAQAAAA==.Murdette:BAAANQAECgUIBQABNQAECgkJJgAcAJQjAA==.',
My='Mystych:BAABNQAECn8WAAMPAAkKKQ6hAwDiAQAPAAkKKQ6hAwDiAQAGAAEKAAC/JQEAAAAAAA==.',
['Må']='Mågi:BAAANQAECgQICAAAAA==.',
['Mé']='Méabh:BAAANQAECgIIAQABNQAECgUICQAIAAAAAA==.',
['Mö']='Möôôöõöóòòõô:BAABNQAECn81AAMJAAkKfhI/YAD3AQAJAAkKfhI/YAD3AQAOAAUKYA62HQHtAAAAAA==.',
Na='Nakednwasted:BAAANQADCgYIBgAAAA==.Nanakii:BAAANQAECgIJAwAAAA==.Nathrold:BAAANQAECgQIBgABNQAECggIEAAIAAAAAA==.',
Ne='Neptune:BAACNQAFFH8RAAIHAAYKwh0zAwAIAgAHAAYKwh0zAwAIAgA1AAQKfzcAAwcACgrwH0odAPgCAAcACgrwH0odAPgCAAQAAQptDDa+ADoAAAAA.Nerfpaladins:BAAANQAECgUIBgAAAA==.Nerfpriests:BAABNQAECn8ZAAINAAgKORSmIwAVAgANAAgKORSmIwAVAgAAAA==.Nerissl:BAAANQADCgIIAgAAAA==.',
Ni='Niemwa:BAAANQADCgQIBAAAAA==.Nightbird:BAAANQAECgcICQAAAA==.Nightwingqt:BAAANQAECgYICgAAAA==.Nimrock:BAAANQABCgIIAgAAAA==.Ninediewatt:BAAANQADCgcIDAAAAA==.',
['Nè']='Nèo:BAAANQADCgYIEAAAAA==.',
Ob='Obsaedia:BAAANQAECggIDgABNQAECggIFQAIAAAAAQ==.',
Od='Odysseus:BAABNQAECn8XAAMQAAoKZBW5DADJAQAQAAgKWRa5DADJAQAEAAQK0AoIfQClAAAAAA==.',
Ok='Oktobra:BAABNQAECn8UAAIOAAcKigIlTQGlAAAOAAcKigIlTQGlAAAAAA==.',
On='Onos:BAAANQADCggJCAAAAA==.',
Or='Orillin:BAABNQAECn81AAMUAAoKDiJUBQAVAwAUAAoKDiJUBQAVAwATAAIKdg+yygBXAAAAAA==.Orioan:BAABNQAECn8mAAIOAAkK+B8PRgDCAgAOAAkK+B8PRgDCAgAAAA==.',
Os='Osÿrus:BAAANQADCgQIBAAAAA==.',
Ou='Ouroboro:BAAANQAECgQIBAAAAA==.',
Pa='Paddy:BAAANQAECgUICgAAAA==.Palantyr:BAACNQAFFH8HAAIEAAQKBA2MHADcAAAEAAQKBA2MHADcAAA1AAQKf1YAAgQACgp3H9cNALMCAAQACgp3H9cNALMCAAAA.Pallytings:BAAANQADCgQIBAAAAA==.Panurita:BAABNQAECn8lAAIHAAoKqBmFJwDGAgAHAAoKqBmFJwDGAgAAAA==.',
Pe='Pellidillion:BAAANQADCgcICwAAAA==.Pepas:BAAANQAECggIDQAAAA==.',
Po='Polgára:BAAANQAECgIIAgAAAA==.',
Pu='Purity:BAAANQAECgMIAwAAAA==.',
Qe='Qevelana:BAAANQADCgMIBAAAAA==.',
Qu='Quetzalcoatl:BAAANQADCgUICQAAAA==.',
Ra='Raambox:BAABNQAECn8rAAIcAAkK/Q36TQCaAQAcAAkK/Q36TQCaAQAAAA==.Raddish:BAAANQAECgYIEwAAAA==.Raedl:BAAANQAECgYICwAAAA==.Ragriefy:BAAANQADCgUIBQAAAA==.Raiinn:BAAANQADCgEIAQAAAA==.Ramantu:BAAANQADCgIJAgAAAA==.Ramranch:BAAANQAECgQIBQABNQAECgoKIQAHANccAA==.Randay:BAAANQAECggIDQAAAA==.Rathix:BAAANQABCgIIAQAAAA==.Raylee:BAAANQAECgMIAwAAAA==.Razuki:BAAANQAECgYIDAAAAA==.',
Re='Reeker:BAAANQABCgQIAgAAAA==.Retton:BAAANQAECgQIBAABNQAECgQIDwAIAAAAAA==.Revenge:BAABNQAECn9AAAIOAAgKgyXVFgDGAgAOAAgKgyXVFgDGAgAAAA==.',
Rh='Rhovanion:BAAANQADCgUIBQABNQAECgkJIwASALoOAA==.Rhuac:BAAANQADCggICgAAAA==.',
Ri='Riddik:BAAANQADCggIDQAAAA==.Rifle:BAAANQAECgQICQABNQAECgoKMwAEAIMTAA==.Rika:BAAANQAECgQIBgAAAA==.',
Ro='Robolich:BAABNQAECn8eAAISAAoKCiEHDQB3AgASAAoKCiEHDQB3AgAAAA==.Rosefist:BAEANQAECgUIBQAAAA==.Rosemourne:BAEANQADCggICAABNQAECgUIBQAIAAAAAA==.Roshwyn:BAAANQAECgMICwAAAA==.Rottedmeat:BAAANQAECggICwAAAA==.',
Ru='Rubmytotems:BAABNQAECn8bAAMHAAcKxxUfUABWAQAHAAcKxxUfUABWAQAEAAEKAAABPwEuAAAAAA==.Ruckus:BAABNQAECn8tAAIOAAoKIRfjbgBSAgAOAAoKIRfjbgBSAgAAAA==.',
Rx='Rxmblock:BAAANQAECgEIAQAAAA==.Rxmboxx:BAAANQADCgIIAgAAAA==.',
Sa='Saelin:BAAANQAECgcICwABNQAECgQIDwAIAAAAAA==.Sareenastar:BAABNQAECn8hAAIMAAoK4ySVEwAwAwAMAAoK4ySVEwAwAwAAAA==.',
Sc='Scarless:BAAANQADCgcIBwAAAA==.',
Se='Seafood:BAAANQAECggIDwAAAA==.Sennara:BAAANQAECgcIDwAAAA==.Sephiróth:BAAANQAECgIIAQAAAA==.Serenitynow:BAAANQADCgYICAAAAA==.Sethworgen:BAAANQADCggICAAAAA==.',
Sh='Shadowlillee:BAAANQAECgIIAgAAAA==.Shadowmeteor:BAABNQAFFH8LAAINAAQK5hINCgClAAANAAQK5hINCgClAAAAAA==.Shakey:BAAANQAECgEIAQAAAA==.Shalen:BAAANQAECgcICQAAAA==.Shamrox:BAAANQAECgYICQAAAA==.Sharar:BAAANQAECgUJBwAAAA==.Sharker:BAAANQADCgMIAwAAAA==.Sharkerprest:BAAANQADCgYIBgAAAA==.Sharkerwarlo:BAAANQAECgEJAQAAAA==.Sharpenator:BAAANQAECgEIAQAAAA==.Sheraa:BAAANQAECgUIBwAAAA==.Shieldknight:BAAANQAECgYICAAAAA==.Shiftystrike:BAAANQAECgYIEAAAAA==.Shifushield:BAAANQADCggIEQAAAA==.Shirazormu:BAAANQAECgEIAQABNQAECgUIBQAIAAAAAA==.Shrike:BAAANQADCgYICgABNQAFFAcIFwANABESAA==.',
Si='Silentwindy:BAAANQAECgEIAQAAAA==.Silmarkthree:BAABNQAECn8dAAIfAAgKAQ6zxAD7AQAfAAgKAQ6zxAD7AQAAAA==.Sinbåd:BAAANQADCggICgAAAA==.',
Sk='Skol:BAABNQAECn8jAAISAAkKug62WwCDAQASAAkKug62WwCDAQAAAA==.',
Sl='Slipknoth:BAACNQAFFH8dAAMNAAcK0RcLBQDxAQANAAcK0RcLBQDxAQAMAAYKxxC1BgDOAQA1AAQKfzkABA0ACgrSH3UGALACAA0ACQooI3UGALACAAwABAriFMCKAL4AABYAAwrBD9YLAGwAAAAA.',
Sn='Snakeplizken:BAAANQADCggIAQAAAA==.',
So='Sorean:BAACNQAFFH8XAAIPAAYKehw1AABoAQAPAAYKehw1AABoAQA1AAQKfy0AAw8ACgo1IOgCAPMCAA8ACgo1IOgCAPMCAAsAAQpjDdGJADUAAAAA.Sorrel:BAAANQADCggIEAAAAA==.',
Sp='Specialmove:BAAANQAECgYICQAAAA==.',
St='Staghealz:BAAANQADCgYICAAAAA==.Staldorn:BAAANQADCgIIAgAAAA==.Starlet:BAAANQADCgIIAgAAAA==.Stifs:BAABNQAECn8dAAIDAAoK+xG6FABiAQADAAoK+xG6FABiAQAAAA==.Stinkinglily:BAAANQABCgQIBwAAAA==.Stonebeard:BAAANQADCggIIQAAAA==.Stormstream:BAAANQADCgMICQAAAA==.',
Su='Suelustra:BAAANQAECgcIEQAAAA==.',
Sy='Sykotyk:BAABNQAECn8lAAIHAAoKjBbJOgB0AgAHAAoKjBbJOgB0AgAAAA==.',
Ta='Tadagain:BAAANQAECgcIEgAAAA==.Talairn:BAAANQADCgYICQAAAA==.Talix:BAAANQAECgIIAgAAAA==.Tamaira:BAAANQAECgUICQAAAA==.Tankybears:BAAANQAECgQIDwAAAA==.Tanthirria:BAAANQADCgQIBAAAAA==.Tart:BAAANQAECgUICAAAAA==.',
Te='Telekinesis:BAABNQAECn8dAAQGAAgK2xUXeQAdAgAGAAgK2xUXeQAdAgALAAYKwAYYTAAEAQAPAAEKAADNEwAxAAAAAA==.Tenara:BAABNQAECn8hAAMHAAoK3x62PABtAgAHAAoK3x62PABtAgAEAAQKqw6O+wCbAAABNQAECgQIDwAIAAAAAA==.Teos:BAAANQADCgYIBgABNQAECgkJIwASALoOAA==.',
Th='Thalanor:BAAANQABCggIIQAAAA==.Thaliak:BAAANQADCgYIBwABNQAECgQIBwAIAAAAAA==.Tharad:BAAANQAECgQIAgABNQAECgcIDwAIAAAAAA==.Tharris:BAAANQADCgYIBgAAAA==.Tholin:BAAANQADCggIEwAAAA==.Thunderlily:BAABNQAECn8eAAMfAAkK+geVfgBFAQAfAAkKuweVfgBFAQAgAAEKvQZURwA1AAAAAA==.',
Ti='Tinychaos:BAAANQAECgIIAwAAAA==.Tirra:BAAANQADCggIDgAAAA==.',
Tr='Tracther:BAAANQADCgYIDwAAAA==.Trapps:BAAANQADCgYIDAAAAA==.Treedemon:BAAANQADCgYIBgAAAA==.Treelock:BAABNQAECn8WAAIVAAkKmhhOcAAOAgAVAAkKmhhOcAAOAgAAAA==.Trelapin:BAAANQADCggIDQAAAA==.',
Tw='Twinrova:BAAANQADCggICAAAAA==.',
Ty='Tybearon:BAAANQADCgYIBwAAAA==.Tyrelitha:BAAANQADCgQIBgAAAA==.',
Uh='Uhtrad:BAABNQAECn8XAAIDAAkKDg4PLQB1AQADAAkKDg4PLQB1AQAAAA==.Uhura:BAAANQADCgYIBgAAAA==.',
Ul='Ulfrir:BAAANQADCgYIBgAAAA==.Ullhr:BAAANQADCgYICwAAAA==.Ultradukes:BAAANQADCgEIAQAAAA==.Ultralord:BAAANQADCgQIBAAAAA==.',
Un='Unleashed:BAAANQAECgEIAQAAAA==.',
Ur='Ursaline:BAAANQAECgEIAQABNQAECgYICwAIAAAAAA==.',
Va='Valock:BAAANQAECgUICgAAAA==.Vanshifty:BAABNQAECn89AAIYAAoK2RxDEQDJAgAYAAoK2RxDEQDJAgAAAA==.',
Ve='Venli:BAAANQAECgMIBQAAAA==.',
Vo='Voidentine:BAAANQABCggIBgAAAA==.',
Vy='Vyx:BAAANQAECgIIAwAAAA==.',
Wa='Waffle:BAABNQAECn8cAAIGAAkKkhHpVgCYAQAGAAkKkhHpVgCYAQAAAA==.Wardaelos:BAAANQADCggIIAAAAA==.Wargue:BAABNQAECn8VAAMdAAgKGw/fDAAqAQAdAAYKLhHfDAAqAQAcAAYKQgjD7gAEAQAAAA==.Wasprepared:BAAANQADCgQIBAAAAA==.Watson:BAAANQAECgYICAABNQAECgcIDwAIAAAAAA==.',
We='Weeaboos:BAAANQADCgQICgAAAA==.Welindis:BAAANQADCgcJBwABNQAECgIIAwAIAAAAAA==.Wenus:BAAANQABCgQIAwAAAA==.',
Wh='Whofurmoover:BAAANQAECgQICQAAAA==.',
Wi='Winrodan:BAABNQAECn8cAAIDAAkKfyF0FQBVAgADAAkKfyF0FQBVAgABNQAECgkJHAADAH8hAA==.Wizzard:BAAANQAECggIFQAAAQ==.',
['Wó']='Wóof:BAAANQADCgMIAwAAAA==.',
Xa='Xaandu:BAAANQADCgQIBAAAAA==.Xaris:BAABNQAECn8cAAIhAAcKtRKnEgBOAQAhAAcKtRKnEgBOAQABNQAECgoKJQAMAOERAA==.',
Xi='Xiladin:BAAANQAECgMIBAAAAA==.',
Xt='Xtremes:BAAANQADCgcIBwAAAA==.',
['Xí']='Xíe:BAABNQAECn8aAAIXAAgKxREdFwC6AQAXAAgKxREdFwC6AQAAAA==.',
Yi='Yimm:BAAANQADCgEIAQAAAA==.',
Yo='Yourdadsadad:BAAANQAECgUIBQABNQAFFAcIEgAcAFsgAA==.',
['Yø']='Yø:BAAANQAECgQIBAAAAA==.',
Zb='Zbm:BAAANQAECgIJAgAAAA==.',
Ze='Zeldy:BAABNQAECn8sAAIGAAoKnxjDNgDGAgAGAAoKnxjDNgDGAgAAAA==.Zenthareal:BAABNQAECn8qAAMiAAkK0RXCLQDUAQAiAAkK0RXCLQDUAQAZAAEKYwjglAAyAAAAAA==.Zenzi:BAAANQADCgcIHAAAAA==.',
Zm='Zmaster:BAAANQAECgUIEAAAAA==.',
Zu='Zunarri:BAAANQADCgYICAABNQAECgcIEAAIAAAAAA==.',
Zw='Zwar:BAAANQADCgMJAwABNQAECgUIEAAIAAAAAA==.',
Zy='Zyri:BAAANQAECgEIAQAAAA==.',
['Ða']='Ðark:BAABNQAECn84AAIGAAoKFR9lHQAiAwAGAAoKFR9lHQAiAwAAAA==.',
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
