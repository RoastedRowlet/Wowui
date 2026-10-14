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

local lookup = {'Unknown-Unknown','Paladin-Protection','Shaman-Restoration','Mage-Arcane','Priest-Shadow','Paladin-Retribution','DeathKnight-Blood','Mage-Frost','DemonHunter-Vengeance','Monk-Brewmaster','Evoker-Devastation','Warrior-Arms','DeathKnight-Frost','Hunter-BeastMastery','Shaman-Elemental','Shaman-Enhancement','DeathKnight-Unholy','Hunter-Marksmanship','Warlock-Affliction','DemonHunter-Havoc','Druid-Guardian','DemonHunter-Devourer','Druid-Feral','Druid-Balance','Druid-Restoration','Warrior-Fury','Paladin-Holy','Evoker-Preservation','Monk-Mistweaver','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','Priest-Holy','Warrior-Protection','Priest-Discipline','Rogue-Assassination',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abcdeath:BAAANQAECgEIBAAAAA==.',
Ad='Adanac:BAAANQAECgUIEAABNQAECgcIDQABAAAAAA==.Addalyne:BAAANQADCgIIAgAAAA==.Adhenar:BAAANQAECgMIBQAAAA==.Adow:BAAANQAECgEIAQAAAA==.Adynne:BAAANQAECgMIAwABNQAECggIFAACAHUfAA==.',
Ae='Aered:BAAANQAECgMIAwAAAA==.',
Ah='Ahira:BAABNQAECn8pAAIDAAgKphpgPQBnAgADAAgKphpgPQBnAgAAAA==.',
Ai='Airro:BAAANQAECgEIAQAAAA==.Aishe:BAAANQAECgMIAwAAAA==.',
Ak='Akashã:BAABNQAECn8sAAIEAAkKUSGeMwAjAwAEAAkKUSGeMwAjAwAAAA==.Akuria:BAABNQAECn8rAAIFAAgK/hf/HQBNAgAFAAgK/hf/HQBNAgAAAA==.',
Al='Alacía:BAAANQAECgMIBwAAAA==.Alahna:BAAANQAECgcIEQAAAA==.Alfredomac:BAAANQAECgEIAQABNQAECgkJMAAGAAMiAA==.Allmightx:BAAANQAECgUIBgAAAA==.',
Am='Amaarth:BAAANQAECgMIAwABNQAECgkJKgAHAC4hAA==.',
An='Anies:BAABNQAECn8WAAIHAAkKHQztTAC/AQAHAAkKHQztTAC/AQAAAA==.Annihilatur:BAAANQAECgEIAgAAAA==.',
Aq='Aquarian:BAAANQAECgYIDAAAAA==.',
Ar='Arthaz:BAAANQAECgEIAgAAAA==.Artëmîs:BAAANQAECgUIDwAAAA==.',
As='Asherrylie:BAAANQADCgQIBgAAAA==.Asmodeuss:BAAANQAECgEIAQAAAA==.Assasincross:BAAANQADCgEIAQAAAA==.',
Au='Auki:BAAANQAECgEIAQAAAA==.',
Av='Avãrice:BAAANQADCgcIBwAAAA==.',
Ba='Babbagnush:BAAANQAECgIIAgAAAA==.Babysneeze:BAAANQADCgYIBQAAAA==.Backkstabber:BAAANQAECgQIBgAAAA==.Badbev:BAAANQADCgUIDQABNQAECgUICAABAAAAAA==.Barene:BAAANQAECggIBwAAAA==.Basspro:BAAANQADCgMIAwAAAA==.Batmuhn:BAAANQADCgEIAQAAAA==.',
Be='Beastiam:BAAANQAECgEIAgAAAA==.Belserion:BAABNQAECn8+AAMEAAkKtyPFEwCEAwAEAAkKOCPFEwCEAwAIAAMK9yCQGwARAQAAAA==.Beltryne:BAAANQAECgUIBQABNQAECgkJPgAEALcjAA==.Benny:BAAANQADCgEIAQAAAA==.Benrick:BAAANQAECgEIAQAAAA==.Berol:BAAANQAECgYIDgAAAA==.Beroldin:BAAANQAECgQIBwABNQAECgYIDgABAAAAAA==.Bevar:BAAANQAECgEIAQABNQAECgUICAABAAAAAA==.Bevell:BAAANQAECgIIAgABNQAECgUICAABAAAAAA==.Bevie:BAAANQAECgEIAgABNQAECgUICAABAAAAAA==.',
Bi='Biggiesdk:BAAANQADCggICAAAAA==.',
Bl='Blindmafaka:BAABNQAECn8hAAIJAAkK9hOsDAD2AQAJAAkK9hOsDAD2AQAAAA==.Blkrend:BAAANQAECgcICQABNQAECgkJOgAEANslAA==.',
Bo='Bonney:BAAANQAECgQICAAAAA==.Bonzai:BAAANQAECgUICgAAAA==.',
Br='Bradycam:BAABNQAECn8kAAIGAAkKHx6cOQDnAgAGAAkKHx6cOQDnAgAAAA==.Brightlock:BAAANQADCgYIDAAAAA==.',
Bu='Bulloo:BAAANQAECgEIAgAAAA==.Busterblader:BAAANQAECgMIAwAAAA==.',
Ca='Cantpalyhard:BAAANQAECgUIDgABNQAECggIJwADAAobAA==.Casella:BAABNQAECn8uAAIKAAkKOyO8AQCiAwAKAAkKOyO8AQCiAwAAAA==.',
Ce='Celerrime:BAAANQAECgEIAQAAAA==.',
Ch='Chemistry:BAAANQAECgEIAgABNQAECgkJJwAGAGUkAA==.Chilindrina:BAAANQABCgIIAgAAAA==.Chupacabbra:BAAANQAECgYIDwAAAA==.',
Ci='Cierdwyn:BAAANQADCgcIBwAAAA==.Cinnaßon:BAAANQAECgEIAgAAAA==.Cinthara:BAAANQAECgEIAgAAAA==.',
Cl='Cleth:BAABNQAECn8cAAIGAAgKUBlqdgA8AgAGAAgKUBlqdgA8AgAAAA==.Clouzot:BAAANQADCgQIBgAAAA==.',
Co='Corax:BAABNQAECn8mAAILAAgKcRCLFQDxAQALAAgKcRCLFQDxAQAAAA==.',
Cr='Crane:BAAANQABCgIIAgAAAA==.Crankitty:BAAANQAECggICAAAAA==.Critshot:BAAANQADCgQIBAABNQAFFAQICQAMAKQYAA==.Crèmeßrûlée:BAAANQAECgEIAQAAAA==.',
Cu='Cunumi:BAAANQAECgcIDAAAAA==.Cutie:BAAANQADCgMIAwAAAA==.',
['Cö']='Cösmic:BAAANQAECgMIAwAAAA==.',
Da='Dainichi:BAAANQAECgEIAgAAAA==.Damachi:BAABNQAECn8fAAINAAgKMBb7NAACAgANAAgKMBb7NAACAgAAAA==.Danji:BAAANQAECgcIDwAAAA==.Darkasuna:BAAANQADCgcIEQAAAA==.Darmorae:BAAANQAECgcIEAAAAA==.Dashii:BAAANQAECggICQABNQAECggIEwABAAAAAA==.Datewoo:BAAANQAECgYIDgAAAA==.Datsuo:BAAANQAECgUIBgABNQAECgUICwABAAAAAA==.',
De='Deathlock:BAAANQAECggIAgAAAA==.Deathris:BAAANQAECgQJCQAAAA==.Deef:BAAANQAECgEIAgAAAA==.Demonish:BAABNQAECn8iAAIMAAkK1hUFVwCDAgAMAAkK1hUFVwCDAgAAAA==.Demontotem:BAAANQAECgYIDgAAAA==.Desadeness:BAAANQADCgUICAABNQADCgYIDwABAAAAAA==.',
Di='Dillinquent:BAAANQAECgMIAwAAAA==.',
Dr='Dracdemonica:BAAANQAECgUIBwABNQAECgkJLgAOADQSAA==.Dracfu:BAAANQAECgYIDgABNQAECgkJLgAOADQSAA==.Dracklock:BAAANQAECgEIAQABNQAECggICgABAAAAAA==.Drackpally:BAAANQAECggICgAAAA==.Dracserion:BAAANQADCggIDgABNQAECgkJPgAEALcjAA==.Dracshot:BAABNQAECn8uAAIOAAkKNBKvWABnAgAOAAkKNBKvWABnAgAAAA==.Dracslock:BAAANQAECgYIEQABNQAECgkJLgAOADQSAA==.Draffel:BAABNQAECn8YAAIPAAgKeBg1RgBaAgAPAAgKeBg1RgBaAgAAAA==.Dreamfire:BAAANQAECgYIBwAAAA==.Drestla:BAAANQAECgUICQAAAA==.Drowgon:BAAANQAECgEIAQAAAA==.Drraakk:BAAANQADCgUIBgABNQAECggICgABAAAAAA==.Dräc:BAAANQAECgYICwABNQAECgkJLgAOADQSAA==.Dråffel:BAAANQAECgEIAQAAAA==.',
Du='Dukstorm:BAAANQAECgQIBAAAAA==.Dundinn:BAAANQADCgMIAwABNQAECggIFAAEAG0KAA==.Dunzer:BAABNQAECn8nAAMCAAgKvhPnMwBBAQACAAYKLBPnMwBBAQAGAAUKFRIR7wA3AQAAAA==.Dunzerblaze:BAAANQAECgUIDQAAAA==.',
Ed='Edithpoothe:BAABNQAECn8WAAIEAAkKhhh7cQCaAgAEAAkKhhh7cQCaAgAAAA==.',
El='Electricks:BAABNQAECn8pAAMQAAkKnx5wBABMAwAQAAkKnx5wBABMAwAPAAYKTBdfiACLAQAAAA==.Elicia:BAAANQADCgUIBQAAAA==.',
Em='Emmii:BAAANQAECgEIAQAAAA==.',
En='Enazure:BAAANQADCgcICwAAAA==.',
Ep='Epiphaný:BAABNQAECn8dAAIEAAYKDxUL+wCUAQAEAAYKDxUL+wCUAQABNQAECggIEwABAAAAAA==.',
Er='Eradoria:BAAANQAECgUICAAAAA==.Ermgoob:BAAANQAECgMJAwAAAA==.',
Et='Etrigon:BAAANQAECgEIAgAAAA==.',
Ev='Evadne:BAABNQAECn8fAAMDAAgKeg8FdQCoAQADAAgKeg8FdQCoAQAPAAYKswOd0QDsAAAAAA==.Evagrius:BAAANQAECgEIAQAAAA==.',
Ex='Extremespeed:BAAANQADCgcIEwABNQAECgkJHwARAO0UAA==.',
Fa='Faant:BAAANQADCgUIBQABNQAECgcIGAADAPUcAA==.Fangy:BAAANQABCgIIAwAAAA==.Fatpats:BAAANQAECgEIAgAAAA==.Fattychangis:BAAANQAECgEIAQAAAA==.',
Fi='Fistantillus:BAAANQAECgIICAAAAA==.',
Fl='Flashægis:BAAANQAECgEIAgAAAA==.Flopper:BAAANQAECgcIEwAAAA==.Fluttershy:BAAANQADCgQIBAAAAA==.',
Fo='Foxyboo:BAABNQAECn8nAAMDAAgKChtwOgBzAgADAAgKChtwOgBzAgAPAAQK7giA6gC7AAAAAA==.',
Fr='Freak:BAAANQAECgYICQAAAA==.Freakpeachh:BAAANQAECgQJBgAAAA==.',
Ga='Galerodra:BAAANQADCggICAAAAA==.Garalline:BAAANQADCgYICAAAAA==.',
Gn='Gnomatic:BAAANQAECgQIBgAAAA==.',
Go='Gooberetta:BAABNQAECn8oAAIOAAgKiSHOIAASAwAOAAgKiSHOIAASAwAAAA==.Gooberoni:BAAANQADCgUJBQAAAA==.Gope:BAABNQAECn8iAAMDAAkK2h9rFgAcAwADAAkK2h9rFgAcAwAPAAEK7ARKOQEvAAAAAA==.Gostewpid:BAAANQAECgEIAQAAAA==.',
Gr='Gromiir:BAABNQAECn8jAAMOAAkKNB/xHwAWAwAOAAgKJCLxHwAWAwASAAEKlQ0whwA1AAAAAA==.Gromyr:BAAANQADCgcIBwABNQAECgkJIwAOADQfAA==.',
['Gä']='Gärrus:BAAANQAECgQICAAAAA==.',
Ha='Haurrmoany:BAAANQADCgEIAQAAAA==.',
He='Healingman:BAAANQADCgMIAwAAAA==.Hellkat:BAAANQAECgIIAgAAAA==.',
Hi='Higarosa:BAAANQAECgEIBQAAAA==.Highbull:BAAANQAECggICwABNQAECggIEwABAAAAAA==.',
Ho='Holiblade:BAABNQAECn8dAAIGAAgKoAeO0wBuAQAGAAgKoAeO0wBuAQAAAA==.Holyhannah:BAAANQADCgIIAQAAAA==.Holywhiskers:BAAANQADCggIHwABNQAECggINQAGAHUZAA==.Hooligun:BAAANQAECgQICQAAAA==.Hoppered:BAAANQAECgYIDAABNQAECggIHAATAIodAA==.',
Hy='Hypérian:BAAANQAECgYICwAAAA==.',
Ia='Ianes:BAAANQADCgYIBwAAAA==.Iantha:BAAANQAECgIIAgAAAA==.',
Ic='Icesikle:BAAANQAECgQJCAAAAA==.',
Ig='Igglybuff:BAAANQAECgUICgAAAA==.',
Ij='Ijustshotyou:BAABNQAECn8lAAMOAAkK/Q6CewAUAgAOAAgKthCCewAUAgASAAMKhAeOZwCJAAAAAA==.',
Il='Illusiongun:BAAANQAECgUIBgABNQAECgkKMAAUAEwgAA==.',
In='Indistera:BAAANQAECgEIAgAAAA==.Insaniac:BAAANQADCggIFAAAAA==.Intervention:BAAANQABCgIIBAAAAA==.Invidious:BAAANQAECgMIBAAAAA==.',
Ir='Ironlotss:BAAANQADCggICwAAAA==.',
Iz='Izumo:BAAANQAECgQIBAAAAA==.',
Ja='Jagerbomb:BAAANQADCgUJBQAAAA==.Jardal:BAAANQADCgIJAgAAAA==.Jatswamdi:BAABNQAECn8tAAICAAkKyCDYBgA3AwACAAkKyCDYBgA3AwAAAA==.',
Jn='Jnymango:BAAANQAECgcIEAAAAA==.',
Jo='Johnnysham:BAAANQADCggJCgABNQAECgcIEAABAAAAAA==.Jollakeratu:BAABNQAECn8mAAIVAAgKjRJGGwDEAQAVAAgKjRJGGwDEAQAAAA==.Jonnyßlaze:BAAANQAECgEIAgAAAA==.Josequervo:BAAANQADCgIIAgAAAA==.',
Ju='Jugram:BAAANQAECgEIAQAAAA==.Jusmissiner:BAAANQAECgYIDQAAAA==.Juut:BAABNQAECn8WAAIHAAkKZxs2IQCoAgAHAAkKZxs2IQCoAgAAAA==.',
['Jø']='Jønty:BAAANQADCgQIBgAAAA==.',
Ka='Kaelyra:BAAANQADCgIJAgAAAA==.',
Ke='Keelhorn:BAABNQAECn8tAAMDAAkKHQvgcAC1AQADAAkKHQvgcAC1AQAPAAMKJg148QCsAAAAAA==.Kemboy:BAAANQADCgEJAQAAAA==.Kenneth:BAAANQADCgQIBAABNQAFFAcIGAAQALsPAA==.Kerubiel:BAAANQAECgQIDgABNQAECgUICwABAAAAAA==.Kessarah:BAABNQAECn8aAAIWAAcKkwwfNwCGAQAWAAcKkwwfNwCGAQAAAA==.',
Kh='Khadraga:BAAANQAECgMIAwAAAA==.',
Ki='Kilthas:BAAANQAECgEIAQAAAA==.Kinkyhawt:BAEBNQAECn8aAAIFAAkKChyxEgDTAgAFAAkKChyxEgDTAgAAAA==.Kirio:BAAANQADCgUIEAAAAA==.Kitsunenohi:BAABNQAECn8kAAIUAAgKeQbLTwBUAQAUAAgKeQbLTwBUAQAAAA==.Kitsunezorro:BAAANQAECgIIBwAAAA==.',
Ko='Kodiakk:BAAANQAECgIIAgAAAA==.Kornbread:BAAANQADCgEIAwAAAA==.',
Kr='Kraelith:BAAANQAECgMIBgAAAA==.Krattos:BAAANQAECgYIDAAAAA==.Krimzin:BAAANQAECgMIBAABNQAFFAUIDAAOAHMbAA==.',
Ks='Ksandra:BAAANQAECgQIEQAAAA==.Ksares:BAABNQAECn8uAAMXAAkKbB2DBQAfAwAXAAkKbB2DBQAfAwAYAAMKxQigmABxAAAAAA==.',
Kw='Kwazii:BAAANQAECggIEgABNQAECggIEwABAAAAAA==.',
Ky='Kyantzmi:BAAANQAECgEIAwAAAA==.Kyogre:BAAANQAECgQIBgAAAA==.',
['Kë']='Këvîn:BAAANQAECgUIDwAAAA==.',
La='Laeflockxo:BAAANQAECgQICAAAAA==.Laefnia:BAABNQAECn8oAAQYAAkKPhVbMwBIAgAYAAkKPhVbMwBIAgAZAAMKJxZwUADDAAAVAAQK1wtCQQCrAAAAAA==.Laraydra:BAAANQAECgYIDgABNQAECggIFAAEAG0KAA==.Laresistance:BAAANQADCgQIBAAAAA==.Lastofgoobs:BAAANQAECgUIBgAAAA==.',
Le='Leard:BAAANQAECgUIBgABNQAECgkJHgAaANwfAA==.Leelui:BAAANQAECgEIAgAAAA==.',
Li='Lichnephilim:BAAANQADCgUIBQAAAA==.Lildarleena:BAAANQADCgUICAAAAA==.Lilis:BAAANQAECgUICQAAAA==.Lilithe:BAAANQAECgUIBwABNQAECggIHAATAIodAA==.Liten:BAAANQADCgIIAwAAAA==.Littlebev:BAAANQAECgUICAAAAA==.Liz:BAAANQADCgQIBgAAAA==.',
Lo='Longshankss:BAAANQAECgEIAQAAAA==.Loonetta:BAAANQAECgEIAQAAAA==.',
Lu='Lucifers:BAAANQADCgMIAwAAAA==.',
['Lé']='Léxí:BAAANQAECggIBwAAAA==.',
Ma='Maachen:BAAANQADCgcIDAAAAA==.Macncheeze:BAAANQAECgEIAQAAAA==.Maduin:BAAANQADCgUIBQAAAA==.Maiangel:BAAANQAECgQIBQAAAA==.Maiikeru:BAAANQADCgUIBgAAAA==.Malaurray:BAAANQAECgcIDAABNQADCgEIAQABAAAAAA==.Malhavoq:BAAANQAECgEIAgAAAA==.Malkôan:BAAANQADCgQIBAAAAA==.Maluin:BAAANQADCgYIEwABNQAECgkJGwAUACgPAA==.Mawea:BAAANQADCgQIBAABNQAECggIFAAEAG0KAA==.',
Mc='Mcchong:BAAANQADCgUIBQAAAA==.Mckennah:BAABNQAECn8UAAMCAAgKdR9jDwCkAgACAAgKdR9jDwCkAgAbAAEKJA0OHgEzAAAAAA==.',
Me='Meliadoul:BAAANQAECgEIAgAAAA==.Melinea:BAAANQAECgMIAwAAAA==.Mereidith:BAABNQAECn8lAAIEAAcKcRiZsAAgAgAEAAcKcRiZsAAgAgAAAA==.Mesohungry:BAAANQAECgUIDAAAAA==.Meuria:BAAANQAECgEIAQAAAA==.',
Mi='Mikedicurt:BAAANQADCgEIAQABNQAECgkJFgAEAIYYAA==.Milele:BAAANQAECgEIAgAAAA==.Mir:BAAANQADCggICAAAAA==.Missnoms:BAAANQADCgYIEgAAAA==.Mistue:BAAANQAECgEIAQABNQAECggIKgAKAJkgAA==.',
Mo='Moobáca:BAAANQAECggIEwAAAA==.Moostradamas:BAABNQAECn8UAAMNAAcKBwVVaQDwAAANAAcKBwVVaQDwAAAHAAEKAACnwABDAAAAAA==.Morcilla:BAABNQAECn8WAAQNAAcKywNDaAD1AAANAAcKxQNDaAD1AAAHAAIKIgM5vwBGAAARAAEKKQOB+QAcAAAAAA==.',
My='Myssts:BAAANQADCgQIBAAAAA==.',
['Mî']='Mîlkmytötem:BAAANQADCgQIBAAAAA==.',
Na='Nacole:BAAANQADCgYIBgAAAA==.Nalleth:BAAANQADCgYIBgAAAA==.Nanakii:BAAANQADCgQIBAAAAA==.Narisa:BAAANQAECgEIAQAAAA==.Naturegoob:BAABNQAECn8nAAMZAAgKliGDDgDnAgAZAAgKliGDDgDnAgAYAAYKdhTITgCgAQAAAA==.Naughtynurse:BAABNQAECn8iAAIZAAkKtQbxMwB2AQAZAAkKtQbxMwB2AQAAAA==.',
Ne='Neuma:BAABNQAECn8UAAIGAAYKuwnq/QAdAQAGAAYKuwnq/QAdAQAAAA==.',
Ni='Nicfurry:BAAANQADCgEIAQAAAA==.Nightflower:BAABNQAECn8kAAIIAAgKpghgEgB+AQAIAAgKpghgEgB+AQAAAA==.',
No='Nostromo:BAABNQAECn8iAAIcAAgKJRTFHAD9AQAcAAgKJRTFHAD9AQAAAA==.',
Ny='Nyxserion:BAAANQAECgYIBwABNQAECgkJPgAEALcjAA==.',
Ob='Obiejuan:BAABNQAECn8xAAIGAAkKtx44IwA2AwAGAAkKtx44IwA2AwAAAA==.',
Od='Odbc:BAABNQAECn8oAAIYAAkK1BnqJQCgAgAYAAkK1BnqJQCgAgAAAA==.Oddball:BAABNQAECn8pAAIPAAkKux/LHwALAwAPAAkKux/LHwALAwAAAA==.',
Op='Ophiron:BAAANQAECgEIAgAAAA==.',
Or='Orthiaa:BAAANQAECgUIDAAAAA==.',
Os='Osalot:BAAANQADCggIEAAAAA==.',
Pa='Paintrain:BAAANQAECgUICgAAAA==.Paladinning:BAAANQAECgEIAQAAAA==.',
Pe='Peso:BAAANQAECggIBgABNQAECggIEwABAAAAAA==.Pez:BAABNQAECn8sAAIDAAkKmRwUJgDKAgADAAkKmRwUJgDKAgAAAA==.',
Ph='Phaidon:BAAANQADCggICAAAAA==.',
Pi='Pixularformd:BAAANQADCgYICQAAAA==.',
Po='Police:BAAANQAECgYICQABNQAECgkJJwADAEUfAA==.Polyhedroll:BAABNQAECn8kAAMdAAkKsx9XCwDMAgAdAAkKsx9XCwDMAgAeAAMKEgrqVwCDAAABNQAECgcICgABAAAAAA==.Postmalorne:BAAANQADCgEIAQAAAA==.Powerzone:BAAANQADCgEJAgAAAA==.',
Pr='Primafox:BAAANQADCgEIAQAAAA==.',
Ps='Psychoman:BAAANQAECgYIDgAAAA==.',
Pu='Punchandkick:BAAANQAECgIIBQAAAA==.Punchdeath:BAAANQADCgUIBQAAAA==.Purplerainjr:BAAANQAECgUIDAAAAA==.',
Qu='Quivermethis:BAAANQADCgUIBQAAAA==.',
Qx='Qx:BAAANQADCgIIAgAAAA==.',
Ra='Raakoth:BAAANQAECgUICwAAAA==.Raathe:BAAANQADCgQIBgAAAA==.Radge:BAABNQAECn8iAAIMAAkKWiU2BgDBAwAMAAkKWiU2BgDBAwAAAA==.Rainjar:BAAANQAECgIIBgABNQAECgkJLAAEAK0fAA==.Rainne:BAAANQADCgQIBAAAAA==.Ralanar:BAABNQAECn8WAAIWAAUKtQ0ySAANAQAWAAUKtQ0ySAANAQABNQAECggIFAAEAG0KAA==.Raljah:BAABNQAECn8cAAQTAAgKih0RBQB6AgATAAgKyxwRBQB6AgAfAAcKnhkDbgAQAgAgAAUK/BR+IABrAQAAAA==.Rampart:BAAANQAECgEIAQABNQAECgEIAgABAAAAAA==.',
Re='React:BAABNQAECn8qAAIHAAkKLiFuDABOAwAHAAkKLiFuDABOAwAAAA==.Renpriest:BAAANQADCgYIDQAAAA==.',
Ri='Richpplwater:BAAANQAECgUIDgAAAA==.',
Ro='Rockie:BAAANQAECgEIAQAAAA==.Rotation:BAAANQABCgIIAgABNQAECgYIGwAJANoVAA==.Royalchaos:BAAANQAECgEIAQABNQAECgkJMwAhAOYbAA==.',
Ru='Rubyraeven:BAAANQAECgEIBgAAAA==.',
Ry='Ryobi:BAABNQAECn8pAAIOAAgKWxWtXQBaAgAOAAgKWxWtXQBaAgAAAA==.Ryptyde:BAAANQAECgUIBQAAAA==.',
['Ræ']='Rævena:BAAANQAECgEIAQAAAA==.',
Sa='Saccharinê:BAAANQAECgEIAQAAAA==.Saintangel:BAAANQAECgEIAgAAAA==.Salinan:BAABNQAECn8qAAMTAAkKiB/RAgDhAgATAAgKxyLRAgDhAgAfAAcKZRVvhgDRAQAAAA==.Saric:BAAANQAECgQICgAAAA==.',
Se='Selinedion:BAAANQAECgcIDQAAAA==.Seraphiim:BAAANQAECgMIAwABNQAECggIFwAEAMgeAA==.Serdav:BAAANQAECgEIAQAAAA==.',
Sh='Shak:BAAANQADCgYICgAAAA==.Shalai:BAABNQAECn8cAAIUAAkKDiCxEQAOAwAUAAkKDiCxEQAOAwAAAA==.Shellingtun:BAAANQAECggIDAABNQAECggIEwABAAAAAA==.Shilóh:BAAANQADCgYIBwAAAA==.Shyandrial:BAAANQADCgYIJQAAAA==.Shyness:BAAANQAECgEIAQAAAA==.',
Sk='Sksteve:BAAANQAECgMIBAAAAA==.Skychades:BAABNQAECn8eAAIOAAcKcRh5aABBAgAOAAcKcRh5aABBAgAAAA==.',
Sn='Sneakygoob:BAAANQADCgMIAwAAAA==.Snorlax:BAAANQAECgUICgAAAA==.',
So='Soulsrequiem:BAAANQAECgEIAQAAAA==.',
Sp='Splash:BAAANQADCgQIBAAAAA==.Spookycurse:BAAANQADCgEIAQAAAA==.Spookydeath:BAABNQAECn8XAAIIAAgKthinCQAyAgAIAAgKthinCQAyAgAAAA==.Spookypriest:BAAANQADCgIIAgAAAA==.',
Sr='Srsnacksalot:BAABNQAECn8XAAIGAAYKuhbXyACEAQAGAAYKuhbXyACEAQAAAA==.',
St='Stileto:BAAANQAECgcIDwABNQAECggIEwABAAAAAA==.Stoneydracco:BAABNQAECn8kAAMIAAgKzhCUDADtAQAIAAgKzhCUDADtAQAEAAYKpQIKYQHuAAAAAA==.',
Su='Sumtinwng:BAAANQAECgcIEgAAAA==.Sunchipz:BAAANQAECgEIAgAAAA==.Sungjay:BAAANQADCgEIAQAAAA==.Supervicious:BAABNQAECn8WAAIiAAkKFw2cFwCvAQAiAAkKFw2cFwCvAQAAAA==.',
Sy='Sylenne:BAAANQAECgUIBwABNQAECgkJLAADAJkcAA==.Sylur:BAABNQAECn8fAAQRAAkK7RSxOAA/AgARAAkK7RSxOAA/AgANAAUKExiLUABoAQAHAAIKpw9FswBfAAAAAA==.',
Ta='Tahren:BAACNQAFFH8QAAMhAAUKVRkADwCcAQAhAAUKVRkADwCcAQAjAAIKLwFYAwBgAAA1AAQKfzQAAyEACQqkIzsRADwDACEACQqkIzsRADwDACMAAwoZIAgRABYBAAAA.Tahshock:BAAANQADCgYICwABNQAFFAUIEAAhAFUZAA==.Taler:BAAANQADCgIIAgAAAA==.Talerion:BAABNQAECn8bAAMLAAcK/BePEgAmAgALAAcK/BePEgAmAgAcAAEKGQ/wTAA3AAAAAA==.',
Te='Telline:BAAANQADCgEIAQAAAA==.Temporalize:BAAANQAECgEIAQAAAA==.Tempô:BAAANQAECgEIAQAAAA==.',
Th='Thatonemonk:BAAANQADCgQJBAABNQAECgMIBAABAAAAAA==.Thistelbear:BAABNQAECn8cAAIeAAgKdQh5NABsAQAeAAgKdQh5NABsAQAAAA==.Thorinn:BAAANQAECgYIBgAAAA==.Thornbloom:BAAANQADCggICAAAAA==.Thrallsux:BAAANQABCgYJBwAAAA==.Thraun:BAAANQAECgIIBwAAAA==.Thunderdin:BAABNQAECn8mAAMCAAgKwxlzFwA8AgACAAgKehhzFwA8AgAGAAgKZxMagwAdAgAAAA==.',
Ti='Tidfl:BAAANQADCgMJAwAAAA==.Tirrian:BAAANQADCggICAAAAA==.Titszilla:BAAANQAECgUIBAABNQAECggIEwABAAAAAA==.',
To='Toki:BAAANQAECgQIDAAAAA==.Tokidh:BAAANQADCgYIBgAAAA==.Tokihots:BAAANQADCgQICAABNQAECgQIDAABAAAAAA==.',
Tu='Turnip:BAAANQAECggIDgABNQAECggIEwABAAAAAA==.',
Tw='Twamsack:BAAANQAECgEIBAAAAA==.Tweak:BAAANQAECgYICwABNQAECggIEwABAAAAAA==.Tweis:BAAANQADCgQIBgAAAA==.',
Um='Umbrarogue:BAABNQAECn8dAAIkAAkKCRyoEwDbAgAkAAkKCRyoEwDbAgAAAA==.',
Uw='Uwumental:BAAANQAECgEIAQAAAA==.',
Va='Vaara:BAAANQABCgEIAQAAAA==.Valaa:BAAANQAECgEIAQAAAA==.Vanddrena:BAABNQAECn8XAAIWAAgKqge0NgCJAQAWAAgKqge0NgCJAQAAAA==.',
Ve='Velien:BAABNQAECn8oAAIGAAkKehFpgQAhAgAGAAkKehFpgQAhAgAAAA==.',
Vi='Vicotr:BAAANQADCgQIBgAAAA==.Viddysouls:BAAANQAECgUICgAAAA==.Viscerai:BAABNQAECn8hAAIhAAkK2xxiHgD1AgAhAAkK2xxiHgD1AgAAAA==.Vite:BAAANQAECgQJBgAAAA==.',
Vo='Vonmiller:BAAANQAECgQICAAAAA==.Vorzul:BAAANQAECgQIBAAAAA==.',
Vr='Vryndiel:BAAANQABCgUIBQAAAA==.',
Vy='Vynllàn:BAAANQADCgYICgAAAA==.',
Wa='Walas:BAAANQADCgEIAQAAAA==.',
We='Wereßearßirb:BAAANQAECgEIAQAAAA==.',
Yu='Yurie:BAAANQAECgQIBAAAAA==.',
Za='Zarrahli:BAAANQAECgEIAQAAAA==.',
Zi='Zipp:BAAANQAECgEIAwAAAA==.',
['Ñö']='Ñövä:BAAANQAECgEIAQAAAA==.',
['Õs']='Õso:BAAANQAECgEIAQAAAA==.',
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
