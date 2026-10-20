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

local lookup = {'Unknown-Unknown','Paladin-Protection','Shaman-Restoration','Mage-Arcane','Priest-Shadow','Paladin-Retribution','DeathKnight-Blood','Mage-Frost','Warrior-Arms','Warrior-Fury','DemonHunter-Vengeance','Paladin-Holy','Monk-Brewmaster','Evoker-Devastation','DeathKnight-Frost','Druid-Feral','Shaman-Elemental','Hunter-BeastMastery','Warlock-Demonology','Shaman-Enhancement','DeathKnight-Unholy','Hunter-Marksmanship','Warlock-Affliction','DemonHunter-Havoc','Druid-Guardian','DemonHunter-Devourer','Druid-Balance','Priest-Holy','Druid-Restoration','Evoker-Preservation','Monk-Mistweaver','Monk-Windwalker','Warlock-Destruction','Warrior-Protection','Priest-Discipline','Rogue-Assassination',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abcdeath:BAAANQAECgEIBAAAAA==.',
Ad='Adanac:BAAANQAECgUIEAABNQAECggIEgABAAAAAA==.Addalyne:BAAANQADCggICgAAAA==.Adhenar:BAAANQAECgMIBQAAAA==.Adow:BAAANQAECgEIAQAAAA==.Adynne:BAAANQAECgMIAwABNQAECgkJFQACAL8eAA==.',
Ae='Aered:BAAANQAECgMIBAAAAA==.',
Ah='Ahira:BAABNQAECn8uAAIDAAkKhxvqEgC+AQADAAkKhxvqEgC+AQAAAA==.',
Ai='Airro:BAAANQAECgEIAQAAAA==.Aishe:BAAANQAECgQIBwAAAA==.',
Ak='Akashã:BAABNQAECn8xAAIEAAoKgCF7EwDKAQAEAAoKgCF7EwDKAQAAAA==.Akuria:BAABNQAECn8zAAIFAAgKAhqbAwDZAQAFAAgKAhqbAwDZAQAAAA==.',
Al='Alacía:BAAANQAFFAEIAQAAAA==.Alahna:BAAANQAECgcIEwAAAA==.Alfredomac:BAAANQAECgEIAQABNQAECgoKMwAGAKohAA==.Allmightx:BAAANQAECgUIBgAAAA==.',
Am='Amaarth:BAAANQAECgMIBAABNQAECgoKMAAHAD8gAA==.',
An='Andeyn:BAAANQAECgIIAQAAAA==.Anies:BAABNQAECn8ZAAIHAAoK5QqOTQC/AQAHAAoK5QqOTQC/AQAAAA==.Annihilatur:BAAANQAECgEIAgAAAA==.',
Aq='Aquarian:BAABNQAECn8WAAIDAAcKdwvrPwDrAAADAAcKdwvrPwDrAAAAAA==.',
Ar='Arthaz:BAAANQAECgEIAgAAAA==.Artëmîs:BAAANQAECgUIDwAAAA==.',
As='Asherrylie:BAAANQADCgUICwAAAA==.Asmodeuss:BAAANQAECgEIAQAAAA==.Assasincross:BAAANQADCgEIAQAAAA==.',
Au='Auki:BAAANQAECgEIAQAAAA==.',
Av='Avãrice:BAAANQADCgcIBwAAAA==.',
Ba='Babbagnush:BAAANQAECgIIAgAAAA==.Babysneeze:BAAANQADCgYIBQAAAA==.Backkstabber:BAAANQAECgQIBgAAAA==.Badbev:BAAANQADCgUIDQABNQAECgYICwABAAAAAA==.Balzinner:BAAANQAECgIIAgAAAA==.Barene:BAAANQAECggIBwAAAA==.Basspro:BAAANQADCgMIAwAAAA==.Batmuhn:BAAANQADCgEIAQAAAA==.',
Be='Beastiam:BAAANQAECgEIAgAAAA==.Belserion:BAABNQAECn9KAAMEAAoKfiNQFACCAwAEAAoK0CJQFACCAwAIAAMKnCH0GwARAQAAAA==.Beltryne:BAAANQAECgUIBQABNQAECgoKSgAEAH4jAA==.Benny:BAAANQADCgEIAQAAAA==.Benrick:BAAANQAECgEIAQAAAA==.Berol:BAABNQAECn8VAAMJAAcK3RR2HwCGAQAJAAcK3RR2HwCGAQAKAAMK5BBGIgCmAAAAAA==.Beroldin:BAAANQAECgUICwABNQAECgcIFQAJAN0UAA==.Bevar:BAAANQAECgMIAwABNQAECgYICwABAAAAAA==.Bevell:BAAANQAECgIIAgABNQAECgYICwABAAAAAA==.Bevie:BAAANQAECgEIAgABNQAECgYICwABAAAAAA==.',
Bi='Biggiesdk:BAAANQADCggICAAAAA==.',
Bl='Blindmafaka:BAABNQAECn8sAAILAAoK5BE6AwCCAQALAAoK5BE6AwCCAQAAAA==.Blkrend:BAAANQAECgcICwABNQAECgoKQgAEANshAA==.',
Bo='Bonney:BAAANQAECgQICAAAAA==.Bonzai:BAAANQAECgUICgAAAA==.',
Br='Bradycam:BAABNQAECn8tAAIGAAoK5h3mBACmAgAGAAoK5h3mBACmAgAAAA==.Brightlock:BAAANQADCgYIDAAAAA==.',
Bu='Bulloo:BAAANQAECgEIAgAAAA==.Busterblader:BAAANQAECgQIBwAAAA==.',
['Bó']='Bóbafett:BAAANQABCgQIBAAAAA==.',
Ca='Cantpalyhard:BAABNQAECn8YAAMMAAcKShj5DAD4AQAMAAcKShj5DAD4AQAGAAUKPAb9KAHcAAABNQAECgoKLQADACcYAA==.Casella:BAABNQAECn8yAAINAAoK3CHFAQCiAwANAAoK3CHFAQCiAwAAAA==.',
Ce='Celerrime:BAAANQAECgEIAQAAAA==.',
Ch='Chemistry:BAAANQAECgMIBAABNQAECgkJLQAGAGUkAA==.Chilindrina:BAAANQABCgIIAgAAAA==.Chupacabbra:BAAANQAECgcIDwAAAA==.',
Ci='Cierdwyn:BAAANQADCgcIBwAAAA==.Cinnaßon:BAAANQAECgEIAgAAAA==.Cinthara:BAAANQAECgEIAgAAAA==.',
Cl='Cleth:BAABNQAECn8kAAIGAAgKUBmPJgCMAQAGAAgKUBmPJgCMAQAAAA==.Clouzot:BAAANQADCgUICwAAAA==.',
Co='Corax:BAABNQAECn8uAAIOAAgKcRBVBABWAQAOAAgKcRBVBABWAQAAAA==.',
Cr='Crane:BAAANQABCgIIAgAAAA==.Crankitty:BAAANQAECggICAAAAA==.Critshot:BAAANQADCgQIBAABNQAFFAQICQAJAKQYAA==.Crèmeßrûlée:BAAANQAECgEIAQAAAA==.',
Cu='Cunumi:BAAANQAECgcIEAAAAA==.Cutie:BAAANQADCgMIAwAAAA==.',
['Cö']='Cösmic:BAAANQAECgMIAwAAAA==.',
Da='Dainichi:BAAANQAECgEIAgAAAA==.Dalathriel:BAAANQADCgcIBwAAAA==.Damachi:BAABNQAECn8mAAIPAAgKgBZdEACCAQAPAAgKgBZdEACCAQAAAA==.Danji:BAABNQAECn8XAAIPAAkKghFZCADSAQAPAAkKghFZCADSAQAAAA==.Darkasuna:BAAANQADCgcIEQAAAA==.Darmorae:BAAANQAECggIEgAAAA==.Dashii:BAAANQAECggIDQABNQAECggIFAAQAOwLAA==.Datewoo:BAAANQAECgcIEgAAAA==.Datsuo:BAAANQAECgYICgABNQAECgcIFAACAPIYAA==.',
De='Deathlock:BAAANQAECggIAgAAAA==.Deathris:BAAANQAECgQJCQAAAA==.Deef:BAAANQAECgEIAgAAAA==.Demonish:BAABNQAECn8pAAIJAAoKfhlDCAA4AgAJAAoKfhlDCAA4AgAAAA==.Demontotem:BAABNQAECn8VAAMRAAgKnQjKIAA4AQARAAgKnQjKIAA4AQADAAQKHwun3gCrAAAAAA==.Desadeness:BAAANQADCgUICAABNQADCgcIEgABAAAAAA==.',
Di='Dillinquent:BAAANQAECgMIAwAAAA==.',
Dr='Dracdemonica:BAAANQAECgYICwABNQAECgoKNAASALQRAA==.Dracfu:BAAANQAECgUIEgABNQAECgoKNAASALQRAA==.Dracklock:BAAANQAECgEIAQABNQAECggICwABAAAAAA==.Drackpally:BAAANQAECggICwAAAA==.Dracserion:BAAANQADCggIDgABNQAECgoKSgAEAH4jAA==.Dracsham:BAAANQADCggICAABNQAECgoKNAASALQRAA==.Dracshot:BAABNQAECn80AAISAAoKtBFJMABgAQASAAoKtBFJMABgAQAAAA==.Dracslock:BAABNQAECn8XAAITAAgKYgXWWwDKAAATAAgKYgXWWwDKAAABNQAECgoKNAASALQRAA==.Draffel:BAABNQAECn8dAAMRAAkKtBZFRwBZAgARAAkKtBZFRwBZAgADAAEKQg7FoQAsAAAAAA==.Dragussÿ:BAAANQADCgcIBwAAAA==.Dreamfire:BAAANQAECgYICgAAAA==.Drestla:BAAANQAECgUICgAAAA==.Drowgon:BAAANQAECgEIAQAAAA==.Drraakk:BAAANQADCgUIBgABNQAECggICwABAAAAAA==.Dräc:BAAANQAECgYICwABNQAECgoKNAASALQRAA==.Dråffel:BAAANQAECgEIAQAAAA==.',
Du='Dukstorm:BAAANQAECgQIBAAAAA==.Dundinn:BAAANQADCgMIAwABNQAECggIFgAEAIUKAA==.Dunzer:BAABNQAECn8tAAMCAAoKXBApGQDDAAAGAAYKVxC+8gA3AQACAAgKNxApGQDDAAAAAA==.Dunzerblaze:BAABNQAECn8XAAIEAAcK9QT1VAATAQAEAAcK9QT1VAATAQAAAA==.',
Ed='Edithpoothe:BAABNQAECn8XAAIEAAkKUhkecgCZAgAEAAkKUhkecgCZAgAAAA==.',
El='Electricks:BAABNQAECn80AAMUAAoK3R/kAQA+AgAUAAoK3R/kAQA+AgARAAYKTBc4igCKAQAAAA==.Elicia:BAAANQADCgUIBQAAAA==.',
Em='Emmii:BAAANQAECgEIAQAAAA==.',
En='Enazure:BAAANQADCgcICwAAAA==.',
Ep='Epiphaný:BAABNQAECn8dAAIEAAYKDxUi/QCTAQAEAAYKDxUi/QCTAQABNQAECggIFAAQAOwLAA==.',
Er='Eradoria:BAAANQAECgUICAAAAA==.Ermgoob:BAAANQAECgMJAwAAAA==.',
Et='Etrigon:BAAANQAECgEIAgAAAA==.',
Ev='Evadne:BAABNQAECn8kAAMDAAgKQxLuJgBHAQADAAgKQxLuJgBHAQARAAYKswM21ADsAAAAAA==.Evagrius:BAAANQAECgEIAQAAAA==.',
Ex='Extremespeed:BAAANQADCgcIEwABNQAECgkJJAAVAAMVAA==.',
Fa='Faant:BAAANQADCgUIBQABNQAECggIGQADAB8dAA==.Failshift:BAAANQAECgMIAwAAAA==.Fangy:BAAANQABCgIIAwAAAA==.Fatpats:BAAANQAECgEIAgAAAA==.Fattychangis:BAAANQAECgEIAQAAAA==.',
Fi='Fistantillus:BAAANQAECgIICAAAAA==.',
Fl='Flashægis:BAAANQAECgEIAgAAAA==.Flopper:BAAANQAECgcIEwAAAA==.Fluttershy:BAAANQADCgQIBAAAAA==.',
Fo='Foxyboo:BAABNQAECn8tAAMDAAoKJxgsOwByAgADAAoKJxgsOwByAgARAAQK7gik7QC7AAAAAA==.',
Fr='Freak:BAAANQAECgYICQAAAA==.Freakpeachh:BAAANQAECgQJBgAAAA==.',
Ga='Galerodra:BAAANQADCggICAAAAA==.Garalline:BAAANQADCgYICAAAAA==.',
Gn='Gnomatic:BAAANQAECgQIBgAAAA==.',
Go='Gooberetta:BAABNQAECn8tAAISAAkKFCBoIQARAwASAAkKFCBoIQARAwAAAA==.Gooberoni:BAAANQADCgUJBQAAAA==.Gope:BAABNQAECn8iAAMDAAkK2h/GFgAbAwADAAkK2h/GFgAbAwARAAEK7ARWPgEvAAAAAA==.Gostewpid:BAAANQAECgEIAQAAAA==.',
Gr='Gromiir:BAABNQAECn8kAAMSAAoK/R6xIAAVAwASAAkKeiGxIAAVAwAWAAEKlQ39iAA1AAAAAA==.Gromyr:BAAANQADCgcIBwABNQAECgoKJAASAP0eAA==.',
['Gä']='Gärrus:BAAANQAECgQICAAAAA==.',
Ha='Haurrmoany:BAAANQADCgEIAQAAAA==.',
He='Healingman:BAAANQADCgYICgAAAA==.Hellkat:BAAANQAECgMIAwAAAA==.',
Hi='Higarosa:BAAANQAECgIIBgAAAA==.Highbull:BAAANQAECggICwABNQAECggIFAAQAOwLAA==.',
Ho='Holiblade:BAABNQAECn8kAAIGAAgKNwjLYgAAAQAGAAgKNwjLYgAAAQAAAA==.Holyhannah:BAAANQADCgIIAQAAAA==.Holywhiskers:BAAANQAECgQIBAABNQAECgoKRwAGAF0WAA==.Hooligun:BAAANQAECgYICgAAAA==.Hoppered:BAAANQAECgYIDAABNQAECggIIwAXAD4fAA==.',
Hy='Hypérian:BAAANQAECgUIDAAAAA==.',
Ia='Ianes:BAAANQADCgYIBwAAAA==.Iantha:BAAANQAECggICwAAAA==.',
Ic='Icesikle:BAAANQAECgQJCAAAAA==.',
Ig='Igglybuff:BAAANQAECgUICgAAAA==.',
Ij='Ijustshotyou:BAABNQAECn8sAAMWAAoKkBDvGADBAAASAAkKiBBffQATAgAWAAUKWQ7vGADBAAAAAA==.',
Il='Illusiongun:BAAANQAECgUICAABNQAECgoKNAAYACUfAA==.',
In='Indistera:BAAANQAECgEIAgAAAA==.Insaniac:BAAANQADCggIFAAAAA==.Intervention:BAAANQABCgIIBAAAAA==.Invidious:BAAANQAECgMIBQAAAA==.',
Ir='Ironlotss:BAAANQADCggICwAAAA==.',
Iz='Izumo:BAAANQAECgQICAAAAA==.',
Ja='Jagerbomb:BAAANQADCgUJBQAAAA==.Jardal:BAAANQADCgIJAgAAAA==.Jatswamdi:BAABNQAECn85AAICAAoKWiKAAAAWAwACAAoKWiKAAAAWAwAAAA==.',
Jn='Jnymango:BAAANQAECgcIEAAAAA==.',
Jo='Johnnysham:BAAANQADCggJCgABNQAECgcIEAABAAAAAA==.Jollakeratu:BAABNQAECn8uAAIZAAgKnRLPDQAoAQAZAAgKnRLPDQAoAQAAAA==.Jonnyßlaze:BAAANQAECgEIAgAAAA==.Josequervo:BAAANQADCgIIAgAAAA==.',
Ju='Jugram:BAAANQAECgEIAQAAAA==.Jusmissiner:BAAANQAECgYIDQAAAA==.Juut:BAABNQAECn8YAAIHAAoKThqaIQCoAgAHAAoKThqaIQCoAgAAAA==.',
['Jø']='Jønty:BAAANQADCgUICwAAAA==.',
Ka='Kaelyra:BAAANQADCgIJAgAAAA==.',
Ke='Keelhorn:BAABNQAECn8xAAMDAAoK9ww6OwD7AAADAAoK9ww6OwD7AAARAAMKJg2f9ACsAAAAAA==.Kemboy:BAAANQADCgEJAQAAAA==.Kenneth:BAAANQADCgQIBAABNQAFFAcIGAAUALsPAA==.Kerubiel:BAABNQAECn8UAAQCAAcK8hipMgBMAQACAAcK8hipMgBMAQAGAAQKoAkdOAHGAAAMAAQKyQaZWACoAAAAAA==.Kessarah:BAABNQAECn8aAAIaAAcKkwzJNwCGAQAaAAcKkwzJNwCGAQAAAA==.',
Kh='Khadraga:BAAANQAECgUIBwAAAA==.',
Ki='Kilthas:BAAANQAECgEIAQAAAA==.Kinkyhawt:BAEBNQAECn8eAAIFAAkKShzjEgDTAgAFAAkKShzjEgDTAgAAAA==.Kirio:BAAANQADCgYIEQAAAA==.Kitsunenohi:BAABNQAECn8sAAIYAAgKeQYTJgDZAAAYAAgKeQYTJgDZAAAAAA==.Kitsunezorro:BAAANQAECgIIBwAAAA==.',
Ko='Kodiakk:BAAANQAECgIIAgAAAA==.Kornbread:BAAANQADCgEIAwAAAA==.',
Kr='Kraelith:BAAANQAECgMIBgAAAA==.Krattos:BAAANQAECgcIDQAAAA==.Krimzin:BAAANQAECgMIBAABNQAFFAYIDQASAN8VAA==.',
Ks='Ksandra:BAABNQAECn8WAAIEAAYKug0sYgD5AAAEAAYKug0sYgD5AAAAAA==.Ksares:BAABNQAECn82AAMQAAoKBSCiAAClAgAQAAoKBSCiAAClAgAbAAMKxQhBmgBxAAAAAA==.',
Kw='Kwazii:BAABNQAECn8UAAMcAAcKwAvKiAB8AQAcAAcKwAvKiAB8AQAFAAYKqgb0TQDcAAABNQAECggIFAAQAOwLAA==.',
Ky='Kyantzmi:BAAANQAECgEIAwAAAA==.Kyogre:BAAANQAECgUICwAAAA==.',
['Kë']='Këvîn:BAABNQAECn8UAAMIAAcK8gySFgBJAQAIAAcK8gySFgBJAQAEAAQKGAjkfgHFAAAAAA==.',
La='Laeflockxo:BAAANQAECgQICAAAAA==.Laefnia:BAABNQAECn8pAAQbAAoKNRPXMwBIAgAbAAoKNRPXMwBIAgAdAAMKJxY8UQDEAAAZAAQK1wuqQgCrAAAAAA==.Laraydra:BAAANQAECgYIDgABNQAECggIFgAEAIUKAA==.Laresistance:BAAANQADCgQIBAAAAA==.Lastofgoobs:BAAANQAECgUIBgAAAA==.',
Le='Leard:BAAANQAECgUICgABNQAECgoKIQAKAJwdAA==.Leelui:BAAANQAECgEIAgAAAA==.',
Li='Lichnephilim:BAAANQADCgUIBQAAAA==.Lildarleena:BAAANQADCgYICAAAAA==.Lilis:BAAANQAECgUICQAAAA==.Lilithe:BAAANQAECgUICQABNQAECggIIwAXAD4fAA==.Liten:BAAANQADCgUICAAAAA==.Littlebev:BAAANQAECgYICwAAAA==.Liz:BAAANQADCgUICwAAAA==.',
Lo='Longshankss:BAAANQAECgEIAQAAAA==.Loonetta:BAAANQAECgEIAQAAAA==.',
Lu='Lucifers:BAAANQADCgMIAwAAAA==.',
['Lé']='Léxí:BAAANQAECggIBwAAAA==.',
Ma='Maachen:BAAANQADCgcIDAAAAA==.Maalik:BAAANQADCgQIBAABNQAECgcIFAACAPIYAA==.Macncheeze:BAAANQAECgEIAQAAAA==.Maduin:BAAANQADCgUIBQAAAA==.Maiangel:BAAANQAECgYICgAAAA==.Maiikeru:BAAANQADCgUIBgAAAA==.Malaurray:BAAANQAECgcIEgABNQADCgEIAQABAAAAAA==.Malhavoq:BAAANQAECgIIAgAAAA==.Malkôan:BAAANQADCgYICgAAAA==.Maluin:BAAANQADCgcIGgABNQAECgkJIgAYACgPAA==.Mawea:BAAANQADCgQIBAABNQAECggIFgAEAIUKAA==.',
Mc='Mcchong:BAAANQADCgUIBQAAAA==.Mckennah:BAABNQAECn8VAAMCAAkKvx6WDwCkAgACAAkKvx6WDwCkAgAMAAEKJA1vIQEzAAAAAA==.',
Me='Meliadoul:BAAANQAECgEIAgAAAA==.Melinea:BAAANQAECgMIAwAAAA==.Mereidith:BAABNQAECn8nAAIEAAcKcRh7sgAeAgAEAAcKcRh7sgAeAgAAAA==.Mesohungry:BAAANQAECgUIDAAAAA==.Meuria:BAAANQAECgEIAQAAAA==.',
Mi='Mikedicurt:BAAANQADCgEIAQABNQAECgkJFwAEAFIZAA==.Milele:BAAANQAECgEIAwAAAA==.Mir:BAAANQADCggICAAAAA==.Missnoms:BAAANQADCgYIEgAAAA==.Mistue:BAAANQAECgEIAQABNQAECggIMQANAJkgAA==.',
Mo='Moobáca:BAABNQAECn8UAAMQAAgK7At2GAB0AQAQAAgK7At2GAB0AQAZAAIKwgk5UwBXAAAAAA==.Moostradamas:BAABNQAECn8VAAMPAAcKBwWBawDwAAAPAAcKBwWBawDwAAAHAAIK4wpuwgBDAAAAAA==.Morcilla:BAABNQAECn8dAAQHAAgKCAWeIwDpAAAPAAcKxQN0agD1AAAHAAgK9QSeIwDpAAAVAAEKKQNe/AAcAAAAAA==.',
My='Myssts:BAAANQADCgUICQAAAA==.',
['Mî']='Mîlkmytötem:BAAANQADCgQIBAAAAA==.',
Na='Nacole:BAAANQADCgYIBgAAAA==.Nalleth:BAAANQADCgYIBgAAAA==.Nanakii:BAAANQADCgQIBAABNQAECggIGQADAB8dAA==.Narisa:BAAANQAECgEIAQAAAA==.Naturegoob:BAABNQAECn8sAAMdAAkKgCDHDgDnAgAdAAkKgCDHDgDnAgAbAAcKdhSXTwCgAQAAAA==.Naughtynurse:BAABNQAECn8pAAIdAAoKawaIGgDwAAAdAAoKawaIGgDwAAAAAA==.',
Ne='Neuma:BAABNQAECn8UAAIGAAYKuwmXAQEdAQAGAAYKuwmXAQEdAQAAAA==.',
Ni='Nicfurry:BAAANQADCgEIAQAAAA==.Nightflower:BAABNQAECn8oAAIIAAoKCgiSEgB+AQAIAAoKCgiSEgB+AQAAAA==.',
No='Nostromo:BAABNQAECn8oAAIeAAoKihIEBgB1AQAeAAoKihIEBgB1AQAAAA==.',
Ny='Nyxserion:BAAANQAECgYIBwABNQAECgoKSgAEAH4jAA==.',
Ob='Obiejuan:BAABNQAECn85AAIGAAoKkyEKBQCjAgAGAAoKkyEKBQCjAgAAAA==.',
Od='Odbc:BAABNQAECn8tAAIbAAoKpxcFEABZAQAbAAoKpxcFEABZAQAAAA==.Oddball:BAABNQAECn8tAAIRAAoKEB49IAALAwARAAoKEB49IAALAwAAAA==.',
Op='Ophiron:BAAANQAECgEIAgAAAA==.',
Or='Orangecrush:BAAANQADCggICAAAAA==.Orthiaa:BAAANQAECgUIEQAAAA==.',
Os='Osalot:BAAANQADCggIEAAAAA==.',
Pa='Paintrain:BAAANQAECgUICgAAAA==.Paladinning:BAAANQAECgEIAQAAAA==.',
Pe='Peso:BAAANQAECggIBwABNQAECggIFAAQAOwLAA==.Pez:BAABNQAECn8zAAIDAAoKDBuNJgDKAgADAAoKDBuNJgDKAgAAAA==.',
Ph='Phaidon:BAAANQADCggICAAAAA==.',
Pi='Pixularformd:BAAANQADCgYICQAAAA==.',
Po='Police:BAAANQAECgYIEQABNQAECgoKKwADAMEfAA==.Polyhedroll:BAABNQAECn8kAAMfAAkKsx97CwDNAgAfAAkKsx97CwDNAgAgAAMKEgovWQCDAAABNQAFFAEIAQABAAAAAA==.Postmalorne:BAAANQADCgEIAQAAAA==.Powerzone:BAAANQADCgIIAgAAAA==.',
Pr='Primafox:BAAANQADCgEIAQAAAA==.',
Ps='Psychoman:BAABNQAECn8WAAIFAAgK/hNDBgCVAQAFAAgK/hNDBgCVAQAAAA==.',
Pu='Punchandkick:BAAANQAECgIIBQAAAA==.Punchdeath:BAAANQADCgUIBQAAAA==.Purplerainjr:BAAANQAECgcIEgAAAA==.',
['Pó']='Póplókndótit:BAAANQAECgMIAwAAAA==.',
Qu='Quivermethis:BAAANQADCgUIBQAAAA==.',
Qx='Qx:BAAANQADCgIIAgAAAA==.',
Ra='Raakoth:BAAANQAECgcIEQABNQAECgcIFAACAPIYAA==.Raathe:BAAANQADCgUICwAAAA==.Radge:BAABNQAECn8iAAIJAAkKWiVjBgDAAwAJAAkKWiVjBgDAAwAAAA==.Rainjar:BAAANQAECggIDgAAAA==.Rainne:BAAANQADCgQIBAAAAA==.Ralanar:BAABNQAECn8YAAIaAAUKtQ0oSQANAQAaAAUKtQ0oSQANAQABNQAECggIFgAEAIUKAA==.Raljah:BAABNQAECn8jAAQXAAgKPh+2AAAHAgATAAcKnhnvbwAPAgAXAAgKzR62AAAHAgAhAAUK/BSuIABrAQAAAA==.Rampart:BAAANQAECgEIAQABNQAECgEIAgABAAAAAA==.',
Re='React:BAABNQAECn8wAAIHAAoKPyCbDABNAwAHAAoKPyCbDABNAwAAAA==.Renpriest:BAAANQADCgYIDQAAAA==.',
Ri='Richpplwater:BAAANQAECgUIDgAAAA==.',
Ro='Rockie:BAAANQAECgEIAgAAAA==.Rotation:BAAANQABCgIIAgABNQAECgYIGwALANoVAA==.Royalchaos:BAAANQAECgIIAwABNQAECgoKPgAcAKQbAA==.',
Ru='Rubyraeven:BAAANQAECgEIBgAAAA==.',
Ry='Ryobi:BAABNQAECn8vAAISAAoKPRVqKQB1AQASAAoKPRVqKQB1AQAAAA==.Ryptyde:BAAANQAECgcIDAAAAA==.',
['Ræ']='Rævena:BAAANQAECgEIAQAAAA==.',
Sa='Saccharinê:BAAANQAECgEIAQAAAA==.Saintangel:BAAANQAECgEIAgAAAA==.Salinan:BAABNQAECn8uAAMXAAoKvhzbAgDhAgAXAAgK4iLbAgDhAgATAAgKQhONiADRAQAAAA==.Saric:BAAANQAECgQICgAAAA==.',
Se='Selinedion:BAAANQAECggIEgAAAA==.Seraphiim:BAAANQAECgMIAwABNQAECgkJHwAEAEggAA==.Serdav:BAAANQAECgEIAQAAAA==.',
Sh='Shak:BAAANQADCgYICgAAAA==.Shalai:BAABNQAECn8gAAIYAAoKWCDCCQCrAQAYAAoKWCDCCQCrAQAAAA==.Shastix:BAAANQADCgYIBgABNQAECgcIFAACAPIYAA==.Shellingtun:BAAANQAECggIDQABNQAECggIFAAQAOwLAA==.Shilóh:BAAANQADCgYIBwAAAA==.Shyandrial:BAAANQADCgYIJQAAAA==.Shyness:BAAANQAECgEIAQAAAA==.',
Sk='Sksteve:BAAANQAECgMIBQAAAA==.Skychades:BAABNQAECn8lAAISAAcKcRhVNwBMAQASAAcKcRhVNwBMAQAAAA==.',
Sn='Sneakygoob:BAAANQADCgMIAwAAAA==.Snorlax:BAAANQAECgUICgAAAA==.',
So='Soulsrequiem:BAAANQAECgEIAQAAAA==.',
Sp='Splash:BAAANQADCgQIBAAAAA==.Spookycurse:BAAANQADCgEIAQAAAA==.Spookydeath:BAABNQAECn8YAAIIAAkK5RfPCQAyAgAIAAkK5RfPCQAyAgAAAA==.Spookypriest:BAAANQADCgIIAgAAAA==.',
Sr='Srsnacksalot:BAABNQAECn8cAAIGAAcKkBTRYwD+AAAGAAcKkBTRYwD+AAAAAA==.',
St='Stileto:BAAANQAECgcIEAABNQAECggIFAAQAOwLAA==.Stoneydracco:BAABNQAECn8nAAMIAAkKNg+3DADsAQAIAAgKzhC3DADsAQAEAAgKfAOMlACeAAAAAA==.Stèvè:BAAANQADCgEIAQAAAA==.',
Su='Subz:BAAANQABCgIIAgABNQAFFAYIEwARAFIjAA==.Sumtinwng:BAAANQAECgcIEgAAAA==.Sunchipz:BAAANQAECgEIAgAAAA==.Sungjay:BAAANQAECgYIBgAAAA==.Supervicious:BAABNQAECn8YAAIiAAoKhgzqFwCvAQAiAAoKhgzqFwCvAQAAAA==.',
Sy='Sylenne:BAAANQAECgUICwABNQAECgoKMwADAAwbAA==.Sylur:BAABNQAECn8kAAQVAAkKAxVJOQA/AgAVAAkK7RRJOQA/AgAPAAcKwhImUgBoAQAHAAMK9A9rRgBrAAAAAA==.',
['Sæ']='Sælinsonia:BAAANQAECgMIAwAAAA==.',
Ta='Tahren:BAACNQAFFH8UAAMcAAUKvxomCABPAQAcAAUKvxomCABPAQAjAAIKLwFkAwBgAAA1AAQKfzwABBwACgrAIpgRADwDABwACgrAIpgRADwDACMAAwoZICURABYBAAUABAqmGh8bALAAAAAA.Tahshock:BAAANQADCgYICwABNQAFFAUIFAAcAL8aAA==.Talanji:BAAANQADCgEIAQAAAA==.Taler:BAAANQADCgIIAgAAAA==.Talerion:BAABNQAECn8cAAMOAAgKWBe7EgAlAgAOAAgKWBe7EgAlAgAeAAEKGQ/rTQA3AAAAAA==.',
Te='Telline:BAAANQADCgEIAQAAAA==.Temporalize:BAAANQAECgEIAQAAAA==.Tempô:BAAANQAECgEIAQAAAA==.',
Th='Thatonemonk:BAAANQADCgQJBAABNQAECgMIBQABAAAAAA==.Thereaben:BAAANQADCgcICwAAAA==.Thistelbear:BAABNQAECn8kAAIgAAgKdQhhFQD/AAAgAAgKdQhhFQD/AAAAAA==.Thorinn:BAAANQAECgYIBgAAAA==.Thornbloom:BAAANQADCggICAAAAA==.Thrallsux:BAAANQABCgYJBwAAAA==.Thraun:BAAANQAECgIIBwAAAA==.Thunderdin:BAABNQAECn8sAAMCAAkKZRa+FwA7AgACAAgKehi+FwA7AgAGAAkK8RB/hQAdAgAAAA==.',
Ti='Tidfl:BAAANQADCgMJAwAAAA==.Tirrian:BAAANQADCggICAAAAA==.Titszilla:BAAANQAECgUIBAABNQAECggIFAAQAOwLAA==.',
To='Toki:BAAANQAECgQIEAAAAA==.Tokidh:BAAANQADCgYIBgAAAA==.Tokihots:BAAANQADCgQICAABNQAECgQIEAABAAAAAA==.',
Tu='Turnip:BAAANQAECggIDgABNQAECggIFAAQAOwLAA==.',
Tw='Twamsack:BAAANQAECgEIBAAAAA==.Tweak:BAAANQAECgYIDAABNQAECggIFAAQAOwLAA==.Tweis:BAAANQADCgUICwAAAA==.',
Um='Umbrarogue:BAABNQAECn8jAAIkAAoKxxr+EwDcAgAkAAoKxxr+EwDcAgAAAA==.',
Uw='Uwumental:BAAANQAECgEIAQAAAA==.',
Va='Vaara:BAAANQABCgEIAQAAAA==.Valaa:BAAANQAECgEIAQAAAA==.Vanddrena:BAABNQAECn8YAAIaAAkKrgZdNwCJAQAaAAkKrgZdNwCJAQAAAA==.',
Ve='Velien:BAABNQAECn8oAAIGAAkKehG/gwAgAgAGAAkKehG/gwAgAgAAAA==.Verwind:BAAANQADCgIIAgAAAA==.',
Vi='Vicotr:BAAANQADCgQIBgAAAA==.Viddysouls:BAAANQAECgUICgAAAA==.Viscerai:BAABNQAECn8mAAIcAAkKeR5jEgDiAQAcAAkKeR5jEgDiAQAAAA==.Vite:BAAANQAECgQJBgAAAA==.',
Vo='Vonmiller:BAAANQAECgQICAAAAA==.Vorzul:BAAANQAECgQIBwAAAA==.Vozluz:BAAANQADCgEIAQABNQAECgcIFAACAPIYAA==.',
Vr='Vryndiel:BAAANQABCgUIBQAAAA==.',
Vy='Vynllàn:BAAANQADCgYICgAAAA==.',
Wa='Walas:BAAANQADCggICQAAAA==.',
We='Wereßearßirb:BAAANQAECgEIAQAAAA==.',
Wh='Whyjudaswhy:BAAANQAECgIIAgAAAA==.',
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
