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

local lookup = {'Paladin-Retribution','Paladin-Protection','Shaman-Restoration','DeathKnight-Blood','Mage-Arcane','Priest-Shadow','Hunter-BeastMastery','Unknown-Unknown','Mage-Frost','Warrior-Arms','Warrior-Fury','DemonHunter-Vengeance','Paladin-Holy','Monk-Brewmaster','Evoker-Devastation','DeathKnight-Frost','Hunter-Survival','Druid-Feral','Shaman-Elemental','Monk-Mistweaver','Warlock-Demonology','Shaman-Enhancement','DeathKnight-Unholy','Druid-Restoration','Hunter-Marksmanship','Warlock-Affliction','DemonHunter-Havoc','Druid-Guardian','DemonHunter-Devourer','Druid-Balance','Priest-Holy','Evoker-Preservation','Monk-Windwalker','Warlock-Destruction','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection','Priest-Discipline',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abcdeath:BAAANQABCgcICAAAAA==.',
Ad='Adanac:BAAANQAECgUIDAABNQAECgoKJQABAFAUAA==.Addalyne:BAAANQADCggIDwAAAA==.Adhenar:BAAANQAECgMIBQAAAA==.Adow:BAAANQAECgEIAQAAAA==.Adynne:BAAANQAECgMIAwABNQAECgkJFgACAL8eAA==.',
Ae='Aered:BAAANQAECgQIBQAAAA==.',
Ah='Ahira:BAABNQAECn82AAIDAAoKxBrPKwBGAgADAAoKxBrPKwBGAgAAAA==.',
Ai='Airro:BAAANQADCgYIEAAAAA==.Aishe:BAAANQAECgcIEgAAAA==.Aitruin:BAAANQAECgYIBQABNQAECgcIHwAEAM8UAA==.',
Ak='Akashã:BAABNQAECn81AAIFAAoK3CFcNAAhAwAFAAoK3CFcNAAhAwAAAA==.Akuria:BAABNQAECn9CAAIGAAoKRheXEQAJAgAGAAoKRheXEQAJAgAAAA==.',
Al='Alacía:BAAANQAFFAEIAQAAAA==.Alahna:BAABNQAECn8bAAIHAAcK+QV52AC9AAAHAAcK+QV52AC9AAAAAA==.',
Am='Amaarth:BAAANQAECgMIBAABNQAECgoKNAAEACojAA==.',
An='Andeyn:BAAANQAECgIIAQAAAA==.Anies:BAABNQAECn8qAAIEAAoKVQ1GKQCNAQAEAAoKVQ1GKQCNAQAAAA==.',
Aq='Aquarian:BAAANQAECgYIEwAAAA==.',
Ar='Arthaz:BAAANQAECgEIAQAAAA==.Artëmîs:BAAANQAECgYIDAAAAA==.',
As='Asherrylie:BAAANQADCgUIEAAAAA==.Asmodeuss:BAAANQADCggIEQAAAA==.Assasincross:BAAANQADCgEIAQAAAA==.',
Av='Avãrice:BAAANQADCgcIBwAAAA==.',
Ba='Babbagnush:BAAANQAECgIIAgAAAA==.Babysneeze:BAAANQADCgYIBQAAAA==.Backkstabber:BAAANQAECgQIBgAAAA==.Badbev:BAAANQADCgUIDQABNQAECgYIBgAIAAAAAA==.Balzinner:BAAANQAECgIIAgAAAA==.Barene:BAAANQAECggIBwAAAA==.Basspro:BAAANQADCgMIAwAAAA==.Batmuhn:BAAANQADCgEIAQAAAA==.',
Be='Beastiam:BAAANQABCgIIAgAAAA==.Belserion:BAABNQAECn9dAAMFAAoK6yNQFACCAwAFAAoKPiNQFACCAwAJAAMKnCH0GwARAQAAAA==.Beltryne:BAAANQAECgUIBQABNQAECgoKXQAFAOsjAA==.Benny:BAAANQADCgEIAQAAAA==.Berol:BAABNQAECn8aAAMKAAcK0xd+dABtAQAKAAcK0xd+dABtAQALAAMK5BBGIgCmAAAAAA==.Beroldin:BAAANQAECgUIEwABNQAECgcIGgAKANMXAA==.Bevar:BAAANQAECgYIBgAAAA==.Bevell:BAAANQAECgQIBAABNQAECgYIBgAIAAAAAA==.',
Bi='Bigbottom:BAAANQADCgUIBQAAAA==.Biggiesdk:BAAANQADCggICAAAAA==.',
Bl='Blindmafaka:BAABNQAECn8wAAIMAAoKmRLVDAD3AQAMAAoKmRLVDAD3AQAAAA==.Blkrend:BAAANQAECggIEwAAAA==.Bloodhound:BAAANQAECgIIAgAAAA==.',
Bo='Bonney:BAAANQAECgQIBwAAAA==.Bonzai:BAAANQAECgUICAAAAA==.',
Br='Bradycam:BAABNQAECn84AAIBAAoKBB/jOgDmAgABAAoKBB/jOgDmAgAAAA==.Brightlock:BAAANQADCgYIDAAAAA==.Brnyshamders:BAAANQAECgYICgAAAA==.',
Bu='Bulloo:BAAANQADCgIIAgAAAA==.Busterblader:BAAANQAECgcIDAAAAA==.',
['Bó']='Bóbafett:BAAANQABCgQIBAAAAA==.',
Ca='Cantpalyhard:BAABNQAECn8gAAMNAAgKxxwjHQCiAgANAAgKxxwjHQCiAgABAAUKSwf9KAHcAAABNQAECgoKOwADAMMaAA==.Casella:BAABNQAECn89AAIOAAoK1iPFAQCiAwAOAAoK1iPFAQCiAwAAAA==.',
Ce='Celerrime:BAAANQABCgUIBgAAAA==.',
Ch='Chemistry:BAAANQAECgUICAABNQAECgoKRAABALQlAA==.Chilindrina:BAAANQABCgIIAgAAAA==.Chupacabbra:BAAANQAECgYIDQAAAA==.',
Ci='Cierdwyn:BAAANQADCggIDAAAAA==.Cinthara:BAAANQAECgEIAQAAAA==.',
Cl='Cleth:BAABNQAECn80AAIBAAoK3hbXWwDkAQABAAoK3hbXWwDkAQAAAA==.Clouzot:BAAANQADCgUIEAAAAA==.',
Co='Corax:BAABNQAECn8+AAIPAAoKRg9cCQCvAQAPAAoKRg9cCQCvAQAAAA==.',
Cr='Crane:BAAANQABCgIIAgAAAA==.Crankitty:BAAANQAECggICAAAAA==.Critshot:BAAANQADCgQIBAABNQAFFAQICQAKAKQYAA==.',
Cu='Cunumi:BAABNQAECn8UAAIBAAYKIwipHwHqAAABAAYKIwipHwHqAAAAAA==.Cutie:BAAANQADCgMIAwAAAA==.',
['Cö']='Cösmic:BAAANQAECgMIAwAAAA==.',
Da='Dalathriel:BAAANQADCgcIBwAAAA==.Damachi:BAABNQAECn82AAIQAAoKVRYQHgAmAgAQAAoKVRYQHgAmAgAAAA==.Danji:BAABNQAECn8YAAIQAAkKKhLZKADYAQAQAAkKKhLZKADYAQAAAA==.Darkasuna:BAAANQADCgcIEQAAAA==.Darmorae:BAABNQAECn8XAAIRAAkKngdiCQChAQARAAkKngdiCQChAQAAAA==.Dashii:BAAANQAECggIEQABNQAECgkJGQASAF8NAA==.Datewoo:BAABNQAECn8eAAIBAAgKPxNbtAC2AQABAAgKPxNbtAC2AQAAAA==.Datsuo:BAAANQAECgYIDgABNQAECgcIHwAEAM8UAA==.',
De='Deathlock:BAAANQAECggIAQAAAA==.Deathris:BAAANQAECgQJBwAAAA==.Deef:BAAANQADCgQIBAAAAA==.Demonicbjorn:BAAANQADCggICAABNQAECgUIBQAIAAAAAA==.Demonish:BAABNQAECn8tAAIKAAoKlB5ZOAA1AgAKAAoKlB5ZOAA1AgAAAA==.Demontotem:BAABNQAECn8XAAMTAAgKnQh2aAATAQATAAgKnQh2aAATAQADAAQKHwun3gCrAAAAAA==.Desadeness:BAAANQADCgYIDQABNQAECgYIBgAIAAAAAA==.',
Di='Dillinquent:BAAANQAECgQIBAAAAA==.',
Dr='Dracdemonica:BAAANQAECggIEQABNQAECgoKRAAHAPYUAA==.Dracfu:BAABNQAECn8ZAAIUAAcKrggtIgDMAAAUAAcKrggtIgDMAAABNQAECgoKRAAHAPYUAA==.Dracklock:BAAANQAECgEIAQABNQAECggICwAIAAAAAA==.Drackpally:BAAANQAECggICwAAAA==.Dracserion:BAAANQADCggIDgABNQAECgoKXQAFAOsjAA==.Dracsham:BAAANQADCggICAABNQAECgoKRAAHAPYUAA==.Dracshot:BAABNQAECn9EAAIHAAoK9hQWTgDzAQAHAAoK9hQWTgDzAQAAAA==.Dracslock:BAABNQAECn8YAAIVAAgKYgW6sgC6AAAVAAgKYgW6sgC6AAABNQAECgoKRAAHAPYUAA==.Draffel:BAABNQAECn8lAAMTAAkKGRdFRwBZAgATAAkKGRdFRwBZAgADAAEKQg6p7gAoAAAAAA==.Dragussÿ:BAAANQADCgcIBwAAAA==.Dreamfire:BAAANQAECgYICQAAAA==.Drestla:BAABNQAECn8ZAAIHAAoKRB7AFwDFAgAHAAoKRB7AFwDFAgAAAA==.Drraakk:BAAANQADCgUIBgABNQAECggICwAIAAAAAA==.Dräc:BAAANQAECgUIDAABNQAECgoKRAAHAPYUAA==.',
Du='Dukstorm:BAAANQAECgQIBAAAAA==.Dundinn:BAAANQADCgMIAwABNQAECggIGgAFAJoKAA==.Dunzer:BAABNQAECn8/AAMCAAoKORHUGQBuAQACAAkKzRHUGQBuAQABAAgKGw++8gA3AQAAAA==.Dunzerblaze:BAABNQAECn8ZAAIFAAcK9QSbvwD+AAAFAAcK9QSbvwD+AAAAAA==.',
Ed='Edithpoothe:BAABNQAECn8oAAIFAAoKBh+NIgCaAgAFAAoKBh+NIgCaAgAAAA==.',
El='Electricks:BAABNQAECn9GAAMWAAoKQiGRBABKAwAWAAoKQiGRBABKAwATAAYKTBc4igCKAQAAAA==.Elicia:BAAANQADCgUIBQAAAA==.',
Em='Emmii:BAAANQADCgUIEAAAAA==.',
En='Enazure:BAAANQADCgcICwAAAA==.',
Ep='Epiphaný:BAABNQAECn8hAAMJAAcKnhMSHgC1AAAFAAcKMBEi/QCTAQAJAAMKuhMSHgC1AAABNQAECgkJGQASAF8NAA==.',
Er='Eradoria:BAAANQAECgUICAAAAA==.Ermgoob:BAAANQAECgMJAwAAAA==.Erosinamun:BAAANQADCgQIBAAAAA==.',
Et='Etrigon:BAAANQADCgYICAAAAA==.',
Ev='Evadne:BAABNQAECn8xAAMDAAoK7BERRgDIAQADAAoK7BERRgDIAQATAAYKnAU21ADsAAAAAA==.Evagrius:BAAANQABCgIIAgAAAA==.Eveokan:BAAANQAECggIDAAAAA==.',
Ex='Extremespeed:BAAANQADCgcIEwABNQAECgkJMAAXAFgXAA==.',
Fa='Faant:BAAANQADCgUIBQABNQAECggIGQADAB8dAA==.Failshift:BAAANQAECgMIAwAAAA==.Fangy:BAAANQABCgIIAwAAAA==.Fatpats:BAAANQABCgIIAgAAAA==.',
Fi='Fistantillus:BAAANQAECgIIAgAAAA==.',
Fl='Flopper:BAAANQAECgcIEAAAAA==.Fluttershy:BAAANQADCgQIBAAAAA==.',
Fo='Foxyboo:BAABNQAECn87AAMDAAoKwxpuIQCEAgADAAoKwxpuIQCEAgATAAQK0gmk7QC7AAAAAA==.',
Fr='Freak:BAABNQAECn8WAAIYAAgKixdRGAAEAgAYAAgKixdRGAAEAgAAAA==.Freakpeachh:BAAANQAECgQJBQAAAA==.',
Ga='Galerodra:BAAANQAECgEIAQAAAA==.Garalline:BAAANQADCgYICAAAAA==.',
Gh='Ghostofpete:BAAANQABCgIIAgAAAA==.',
Gn='Gnomatic:BAAANQAECgQIBgAAAA==.',
Go='Gooberetta:BAABNQAECn83AAIHAAoKrB9oIQARAwAHAAoKrB9oIQARAwAAAA==.Gooberoni:BAAANQADCgUJBQAAAA==.Gope:BAABNQAECn8iAAMDAAkK2h/GFgAbAwADAAkK2h/GFgAbAwATAAEK7ARWPgEvAAAAAA==.Gostewpid:BAAANQAECgEIAQAAAA==.',
Gr='Gromiir:BAABNQAECn8sAAMHAAoKAiKxIAAVAwAHAAoKAiKxIAAVAwAZAAEKlQ39iAA1AAAAAA==.Gromyr:BAAANQADCgcIBwABNQAECgoKLAAHAAIiAA==.',
['Gä']='Gärrus:BAAANQAECgQIBgAAAA==.',
Ha='Haurrmoany:BAAANQADCgEIAQAAAA==.',
He='Healingman:BAAANQADCgYIFQAAAA==.Hellkat:BAAANQAECgQIBAAAAA==.',
Hi='Higarosa:BAAANQAECgEIAQAAAA==.Highbull:BAAANQAECggIDQABNQAECgkJGQASAF8NAA==.',
Ho='Holiblade:BAABNQAECn8nAAIBAAgKNwjh1gBuAQABAAgKNwjh1gBuAQAAAA==.Holyhannah:BAAANQADCgIIAQAAAA==.Holyschitte:BAAANQADCgIIAgAAAA==.Holytoki:BAAANQAECgUICgAAAA==.Holywhiskers:BAAANQAECgYIEAABNQAECgoKXAABAGIZAA==.Hooligun:BAAANQAECgYIDgAAAA==.Hoppered:BAAANQAECgYICwABNQAECgoKNAAaALkgAA==.',
Hy='Hypérian:BAAANQAECgYIDQAAAA==.',
Ia='Ianes:BAAANQADCgYIBwAAAA==.Iantha:BAABNQAECn8YAAIHAAoK6h9+GQC7AgAHAAoK6h9+GQC7AgAAAA==.',
Ic='Icesikle:BAAANQAECgQICAAAAA==.',
Ig='Igglybuff:BAAANQAECgUICgAAAA==.',
Ij='Ijustshotyou:BAABNQAECn86AAMHAAoKXRzIJACCAgAHAAoKXRzIJACCAgAZAAUKhw/cKgDdAAAAAA==.',
Il='Illusiongun:BAAANQAECgUIBwABNQAECgoKPwAbAHQgAA==.',
In='Insaniac:BAAANQADCggIFAAAAA==.Intervention:BAAANQABCgIIBAAAAA==.Invidious:BAAANQAECgQIBgAAAA==.',
Ir='Ironlotss:BAAANQADCggICwAAAA==.',
Iz='Izumo:BAAANQAECgcIDQAAAA==.',
Ja='Jagerbomb:BAAANQADCgUJBQAAAA==.Jardal:BAAANQADCgUIBwAAAA==.Jatswamdi:BAABNQAECn9FAAICAAoKdiL1BgA3AwACAAoKdiL1BgA3AwAAAA==.',
Je='Jehbodia:BAAANQADCggICAAAAA==.',
Jn='Jnymango:BAAANQAECgcIDwAAAA==.',
Jo='Johnnysham:BAAANQADCggJCgABNQAECgcIDwAIAAAAAA==.Jollakeratu:BAABNQAECn8+AAIcAAoKVxFXGgB6AQAcAAoKVxFXGgB6AQAAAA==.Josequervo:BAAANQADCgIIAgAAAA==.',
Ju='Jugram:BAAANQAECgEIAQAAAA==.Jusmissiner:BAAANQAECgYICwAAAA==.Juut:BAABNQAECn8jAAIEAAoKsxyaIQCoAgAEAAoKsxyaIQCoAgAAAA==.',
['Jø']='Jønty:BAAANQADCgUIEAAAAA==.',
Ka='Kaelyra:BAAANQADCgUIBwAAAA==.',
Ke='Keelhorn:BAABNQAECn81AAMDAAoK9wwxcgC1AQADAAoK9wwxcgC1AQATAAcKqQn+jAC5AAAAAA==.Kemboy:BAAANQADCgEJAQAAAA==.Kenneth:BAAANQADCgQIBAABNQAFFAgIGQAWAPMNAA==.Kerubiel:BAABNQAECn8XAAQCAAcK8hipMgBMAQACAAcK8hipMgBMAQABAAQKoAkdOAHGAAANAAQKyQaGqgCdAAABNQAECgcIHwAEAM8UAA==.Kessarah:BAABNQAECn8dAAIdAAgKQA3JNwCGAQAdAAgKQA3JNwCGAQAAAA==.',
Kh='Khadraga:BAAANQAECgQICgAAAA==.',
Ki='Kilthas:BAAANQAECgEIAQAAAA==.Kinkyhawt:BAEBNQAECn8fAAIGAAoKbhvjEgDTAgAGAAoKbhvjEgDTAgAAAA==.Kirio:BAAANQADCggIEwAAAA==.Kitsunenohi:BAABNQAECn8uAAIbAAkKFwa6UABUAQAbAAkKFwa6UABUAQAAAA==.Kitsunezorro:BAAANQAECgIIBQAAAA==.',
Ko='Kodiakk:BAAANQAECgIIAgAAAA==.Kornbread:BAAANQADCgEIAwAAAA==.',
Kr='Kraelith:BAAANQAECgMIBAAAAA==.Krattos:BAAANQAECgUICwAAAA==.Krimzin:BAAANQAECgMIBAABNQAFFAcIDgAHABUYAA==.',
Ks='Ksandra:BAABNQAECn8ZAAIFAAgK0g3MhABwAQAFAAgK0g3MhABwAQAAAA==.Ksares:BAABNQAECn9HAAQSAAoKuyFvAwDgAgASAAoKuyFvAwDgAgAeAAMKxQhBmgBxAAAYAAEK1RA0ZwAxAAAAAA==.',
Kw='Kwazii:BAABNQAECn8YAAMfAAcKwAvKiAB8AQAfAAcKwAvKiAB8AQAGAAYKqgb0TQDcAAABNQAECgkJGQASAF8NAA==.',
Ky='Kyantzmi:BAAANQADCgEIAQAAAA==.Kyogre:BAAANQAECgQICQAAAA==.',
['Kë']='Këvîn:BAABNQAECn8XAAMJAAcK8gySFgBJAQAJAAcK8gySFgBJAQAFAAQKGAjkfgHFAAAAAA==.',
La='Laeflockxo:BAAANQAECgQIBgAAAA==.Laefnia:BAABNQAECn84AAQeAAoKOxisIgCxAQAeAAoKOxisIgCxAQAYAAMKWhY8UQDEAAAcAAQK1wuqQgCrAAAAAA==.Laraydra:BAAANQAECgYIDAABNQAECggIGgAFAJoKAA==.Laresistance:BAAANQADCgQIBAAAAA==.Lastofgoobs:BAAANQAECgYIBQAAAA==.',
Le='Leard:BAAANQAECgYIDAABNQAECgoKKQALACsgAA==.',
Li='Lichnephilim:BAAANQADCgUIBQAAAA==.Lildarleena:BAAANQADCgYICAAAAA==.Lilis:BAAANQAECgUICQAAAA==.Lilithe:BAAANQAECgUIBwABNQAECgoKNAAaALkgAA==.Liten:BAAANQADCgUIDQAAAA==.Lithndice:BAAANQADCggIDgAAAA==.Littlebev:BAAANQAECgUIEAABNQAECgYIBgAIAAAAAA==.Liz:BAAANQADCgUICwAAAA==.',
Lo='Longshankss:BAAANQAECgEIAQAAAA==.',
Lu='Lucifers:BAAANQADCgMIAwAAAA==.Lucìen:BAAANQAECggIDAAAAA==.',
['Lé']='Léxí:BAAANQAECggIBwAAAA==.',
Ma='Maachen:BAAANQADCgcIDAAAAA==.Maalik:BAAANQADCgQIBAABNQAECgcIHwAEAM8UAA==.Macncheeze:BAAANQABCgQIBAAAAA==.Maduin:BAAANQADCgUIBQAAAA==.Maiangel:BAAANQAECgYICwAAAA==.Maiikeru:BAAANQADCgUIBgAAAA==.Malaurray:BAABNQAECn8bAAIVAAkKqwgtbwBRAQAVAAkKqwgtbwBRAQABNQADCgEIAQAIAAAAAA==.Malhavoq:BAAANQAECgYICAAAAA==.Malkôan:BAAANQADCgYICgAAAA==.Maluin:BAAANQADCgcIGgABNQAECgoKLgAbAJkRAA==.Manlock:BAAANQADCgQIBAAAAA==.Mawea:BAAANQADCgQIBAABNQAECggIGgAFAJoKAA==.',
Mc='Mcchong:BAAANQADCgUIBQAAAA==.Mckennah:BAABNQAECn8WAAMCAAkKvx6WDwCkAgACAAkKvx6WDwCkAgANAAEKJA1vIQEzAAAAAA==.',
Me='Melinea:BAAANQAECgMIAwAAAA==.Mereidith:BAABNQAECn85AAIFAAoK3BOoXQDTAQAFAAoK3BOoXQDTAQAAAA==.Mesohungry:BAAANQAECgUICgAAAA==.Meuria:BAAANQAECgQIBAAAAA==.',
Mi='Mikedicurt:BAAANQADCgEIAQABNQAECgoKKAAFAAYfAA==.Milele:BAAANQAECgIIBAAAAA==.Mir:BAAANQADCggICAAAAA==.Missnoms:BAAANQADCgYIEgAAAA==.Mistue:BAAANQAECgIIAgABNQAECgoKQQAOALIeAA==.',
Mo='Moobáca:BAABNQAECn8ZAAQSAAkKXw12GAB0AQASAAgKew12GAB0AQAcAAMKahAvRwBwAAAeAAEKiQMXiAAcAAAAAA==.Moostradamas:BAABNQAECn8XAAMQAAgKUQWBawDwAAAQAAgKUQWBawDwAAAEAAIK4wpuwgBDAAAAAA==.Morcilla:BAABNQAECn8sAAQEAAoKKAeWNQBGAQAEAAoKKAeWNQBGAQAQAAgKjgN0agD1AAAXAAEKKQNe/AAcAAAAAA==.',
My='Myssts:BAAANQADCgUIDgAAAA==.',
['Mí']='Mínervä:BAAANQAECggIBAAAAA==.',
['Mî']='Mîlkmytötem:BAAANQADCgQIBAAAAA==.',
Na='Nacole:BAAANQADCgYIBgAAAA==.Nalleth:BAAANQADCgYIBgAAAA==.Nanakii:BAAANQADCgQIBAABNQAECggIGQADAB8dAA==.Narisa:BAAANQABCgMIAwAAAA==.Naturegoob:BAABNQAECn81AAMYAAoKsyHHDgDnAgAYAAoKsyHHDgDnAgAeAAcKSRaXTwCgAQAAAA==.Naughtynurse:BAABNQAECn8xAAIYAAoKBQeJNAB2AQAYAAoKBQeJNAB2AQAAAA==.',
Ne='Neuma:BAABNQAECn8WAAIBAAYKuwmXAQEdAQABAAYKuwmXAQEdAQAAAA==.',
Ni='Nicfurry:BAAANQADCgEIAQAAAA==.Nightflower:BAABNQAECn8tAAIJAAoK0wiSEgB+AQAJAAoK0wiSEgB+AQAAAA==.',
No='Nostromo:BAABNQAECn8wAAIgAAoKLBXoEgCJAQAgAAoKLBXoEgCJAQAAAA==.',
Ny='Nyxserion:BAAANQAECgYIBwABNQAECgoKXQAFAOsjAA==.',
Ob='Obiejuan:BAABNQAECn9LAAIBAAoKsyJCEwADAwABAAoKsyJCEwADAwAAAA==.',
Od='Odbc:BAABNQAECn8xAAIeAAoKLxpqJgCgAgAeAAoKLxpqJgCgAgAAAA==.Oddball:BAABNQAECn81AAITAAoK9CA9IAALAwATAAoK9CA9IAALAwAAAA==.',
Op='Ophiron:BAAANQADCgcICAAAAA==.',
Or='Orangecrush:BAAANQADCggICAAAAA==.Orthiaa:BAABNQAECn8bAAIHAAUKsgvFuwD2AAAHAAUKsgvFuwD2AAAAAA==.',
Os='Osalot:BAAANQADCggIEAAAAA==.',
Pa='Paintrain:BAAANQAECgUICAAAAA==.Paladinning:BAAANQADCgUIBQAAAA==.',
Pe='Peso:BAAANQAECggICAABNQAECgkJGQASAF8NAA==.Pez:BAABNQAECn85AAMDAAoKLxuNJgDKAgADAAoKLxuNJgDKAgATAAEKAABz/wAAAAAAAA==.',
Ph='Phaidon:BAAANQADCggICAAAAA==.',
Pi='Pixularformd:BAAANQADCgYICQAAAA==.',
Po='Police:BAABNQAECn8bAAIfAAkKRxrENAA2AgAfAAkKRxrENAA2AgAAAA==.Polyhedroll:BAABNQAECn8kAAMUAAkKsx97CwDNAgAUAAkKsx97CwDNAgAhAAMKEgovWQCDAAABNQAFFAIIAwAIAAAAAA==.Postmalorne:BAAANQADCgEIAQAAAA==.Powerzone:BAAANQADCgIIAgAAAA==.',
Pr='Primafox:BAAANQADCgEIAQAAAA==.',
Ps='Psychoman:BAABNQAECn8fAAIGAAkKwRMzFwCyAQAGAAkKwRMzFwCyAQAAAA==.',
Pu='Punchandkick:BAAANQAECgIIBQAAAA==.Punchdeath:BAAANQADCgUIBQAAAA==.Purplerainjr:BAABNQAECn8aAAIQAAgKKg0bPABvAQAQAAgKKg0bPABvAQAAAA==.',
['Pó']='Póplókndótit:BAAANQAECgMIBAAAAA==.',
Qu='Quivermethis:BAAANQADCgUIBQAAAA==.',
Qx='Qx:BAAANQADCgQIBAAAAA==.',
Ra='Raakoth:BAABNQAECn8fAAMEAAcKzxQeZABiAQAEAAYKzxUeZABiAQAQAAcKFw9LTQAiAQAAAA==.Raathe:BAAANQADCgUIEAAAAA==.Radge:BAABNQAECn8iAAIKAAkKWiVjBgDAAwAKAAkKWiVjBgDAAwAAAA==.Rainjar:BAAANQAECggIDgAAAA==.Rainne:BAAANQADCgQIBAAAAA==.Ralanar:BAABNQAECn8YAAIdAAUKtQ0oSQANAQAdAAUKtQ0oSQANAQABNQAECggIGgAFAJoKAA==.Raljah:BAABNQAECn80AAQaAAoKuSDwAQCzAgAaAAoKuSDwAQCzAgAVAAcKnhnvbwAPAgAiAAUK/BSuIABrAQAAAA==.Rampart:BAAANQABCgQIBAAAAA==.',
Re='React:BAABNQAECn80AAIEAAoKKiObDABNAwAEAAoKKiObDABNAwAAAA==.Renpriest:BAAANQADCgYIDQAAAA==.',
Ri='Richpplwater:BAABNQAECn8WAAIBAAUKzw89DQEJAQABAAUKzw89DQEJAQAAAA==.',
Ro='Rockie:BAAANQAECgQIBwAAAA==.Rotation:BAAANQADCgIIAgABNQAECgYIIwAMANoVAA==.Royalchaos:BAAANQAECgIIAwABNQAECgoKUgAfANwfAA==.',
Ry='Ryobi:BAABNQAECn87AAIHAAoKqRhGXwBZAgAHAAoKqRhGXwBZAgAAAA==.Ryptyde:BAAANQAECggIEAAAAA==.Rysand:BAAANQAECgMIAwAAAA==.',
Sa='Saccharinê:BAAANQABCgMIAwAAAA==.Saintangel:BAAANQABCgQIAgAAAA==.Salinan:BAABNQAECn9AAAMaAAoKSh/bAgDhAgAaAAgK4iLbAgDhAgAVAAgKsBi9ZwBlAQAAAA==.Saric:BAAANQAECgQICQAAAA==.',
Se='Selinedion:BAABNQAECn8lAAIBAAoKUBRWjgBvAQABAAoKUBRWjgBvAQAAAA==.Seraphiim:BAAANQAECgMIAwABNQAECgkJIwAFAEggAA==.Serdav:BAAANQAECgEIAQAAAA==.',
Sh='Shak:BAAANQADCgYIDQAAAA==.Shalai:BAACNQAFFH8FAAIbAAUKLhGWDgCqAAAbAAUKLhGWDgCqAAA1AAQKfy0AAhsACgrcIokHAAIDABsACgrcIokHAAIDAAAA.Shastix:BAAANQADCgYIBgABNQAECgcIHwAEAM8UAA==.Shellingtun:BAAANQAECggIDQABNQAECgkJGQASAF8NAA==.Shilóh:BAAANQADCgYIBwAAAA==.Shyandrial:BAAANQADCgYIJQAAAA==.Shyness:BAAANQADCggICAAAAA==.',
Sk='Skaadooshh:BAAANQAECgUIBQAAAA==.Sksteve:BAAANQAECgQICQAAAA==.Skychades:BAABNQAECn8tAAIHAAkK7xZsVgDbAQAHAAkK7xZsVgDbAQAAAA==.',
Sn='Sneakygoob:BAAANQADCgMIAwAAAA==.Snorlax:BAAANQAECgUICgAAAA==.',
So='Soulsrequiem:BAAANQADCggIFwAAAA==.',
Sp='Splash:BAAANQADCgQIBAAAAA==.Spookycurse:BAAANQADCgEIAQAAAA==.Spookydeath:BAABNQAECn8ZAAIJAAkK5RfPCQAyAgAJAAkK5RfPCQAyAgAAAA==.Spookypriest:BAAANQADCgIIAgAAAA==.',
Sr='Srsnacksalot:BAABNQAECn8lAAIBAAgKBBUAiwB2AQABAAgKBBUAiwB2AQAAAA==.',
St='Stileto:BAABNQAECn8XAAMjAAgKjQcQcwD3AAAjAAgKjQcQcwD3AAAkAAIKjwMlpQAyAAABNQAECgkJGQASAF8NAA==.Stoneydracco:BAABNQAECn8zAAMJAAoK3g23DADsAQAJAAgKzhC3DADsAQAFAAkKUgTTzwDfAAAAAA==.Stèvè:BAAANQAECgEIAQAAAA==.',
Su='Subz:BAAANQABCgIIAgABNQAFFAcIFAATAOsiAA==.Sumtinwng:BAABNQAECn8aAAIBAAgKRwpivQCiAQABAAgKRwpivQCiAQAAAA==.Sunchipz:BAAANQADCgcICwAAAA==.Sungjay:BAAANQAECgcIDAAAAA==.Supervicious:BAABNQAECn8bAAIlAAoKEw7qFwCvAQAlAAoKEw7qFwCvAQAAAA==.',
Sy='Sylenne:BAAANQAECgUICAABNQAECgoKOQADAC8bAA==.Sylur:BAABNQAECn8wAAQXAAkKWBdJOQA/AgAXAAkKQhdJOQA/AgAQAAcKwhImUgBoAQAEAAQKrw9DaQCDAAAAAA==.',
['Sæ']='Sælinsonia:BAAANQAECgMIBAAAAA==.',
Ta='Tahran:BAAANQADCgEIAQABNQAFFAYIHQAfAGQeAA==.Tahren:BAACNQAFFH8dAAQfAAYKZB5VCQDUAQAfAAYKZB5VCQDUAQAmAAIKLwFkAwBgAAAGAAEKAADmFAAAAAA1AAQKf08ABB8ACgrAIpgRADwDAB8ACgrAIpgRADwDAAYACQrtGfUPACQCACYAAwoZICURABYBAAAA.Tahshock:BAAANQADCgYICwABNQAFFAYIHQAfAGQeAA==.Talanji:BAAANQADCgEIAQAAAA==.Taler:BAAANQADCgIIAgAAAA==.Talerion:BAABNQAECn8sAAMPAAoKBBaYCADIAQAPAAoKBBaYCADIAQAgAAEKGQ/rTQA3AAAAAA==.',
Te='Telline:BAAANQADCgEIAQAAAA==.Tempô:BAAANQADCggICAAAAA==.',
Th='Thatonemonk:BAAANQADCgQJBAABNQAECgQIBgAIAAAAAA==.Thereaben:BAAANQADCgcIEQAAAA==.Theyhateme:BAAANQABCggICQAAAA==.Thistelbear:BAABNQAECn80AAIhAAoKfQqSHACIAQAhAAoKfQqSHACIAQAAAA==.Thorinn:BAAANQAECgcIDQAAAA==.Thornbloom:BAAANQADCggICAAAAA==.Thrallsux:BAAANQABCgYJBwAAAA==.Thraun:BAAANQAECgIIBAAAAA==.Thunderdin:BAABNQAECn8/AAMCAAoKrRq+FwA7AgACAAoK9RW+FwA7AgABAAoK0BZ/hQAdAgAAAA==.',
Ti='Tidfl:BAAANQADCgMIAwAAAA==.Tirrian:BAAANQADCggICAAAAA==.Titszilla:BAAANQAECgUICAABNQAECgkJGQASAF8NAA==.',
To='Toki:BAAANQAECgQIDAABNQAECgUICgAIAAAAAA==.Tokidh:BAAANQADCgYIBgAAAA==.Tokihots:BAAANQADCgQICAABNQAECgUICgAIAAAAAA==.',
Tu='Turnip:BAABNQAECn8WAAMZAAgKtwZ/JAAMAQAZAAgKtwZ/JAAMAQAHAAIKRAMPXwE1AAABNQAECgkJGQASAF8NAA==.',
Tw='Twamsack:BAAANQABCgUIBwAAAA==.Tweak:BAAANQAECgYIDAABNQAECgkJGQASAF8NAA==.Tweis:BAAANQADCgUIEAAAAA==.',
Um='Umbrarogue:BAABNQAECn8rAAMkAAoKux/+EwDcAgAkAAoKwRv+EwDcAgAjAAQKmRyFXABGAQAAAA==.',
Va='Vaara:BAAANQABCgEIAQAAAA==.Valaa:BAAANQAECgEIAQAAAA==.Vanddrena:BAABNQAECn8eAAIdAAkKJAddNwCJAQAdAAkKJAddNwCJAQAAAA==.',
Ve='Velien:BAABNQAECn8oAAIBAAkKehG/gwAgAgABAAkKehG/gwAgAgAAAA==.Verwind:BAAANQADCgIIAgAAAA==.',
Vi='Vicotr:BAAANQADCgQIBgAAAA==.Viddysouls:BAAANQAECgYIDgAAAA==.Viscerai:BAABNQAECn8wAAIfAAkKyyLsCgBtAwAfAAkKyyLsCgBtAwAAAA==.Vite:BAAANQAECgQJBgAAAA==.',
Vo='Vonmiller:BAAANQAECgQICAAAAA==.Vorzul:BAAANQAECgUIDQAAAA==.Vozluz:BAAANQADCgEIAQABNQAECgcIHwAEAM8UAA==.',
Vr='Vryndiel:BAAANQABCgUIBQAAAA==.',
Vy='Vynllàn:BAAANQADCgYICgAAAA==.',
Wa='Walas:BAAANQADCggICwAAAA==.Walklight:BAAANQADCgcIEQAAAA==.',
Wh='Whyjudaswhy:BAAANQAECgIIAgAAAA==.',
Yu='Yurie:BAAANQAECgQIBAAAAA==.',
Za='Zapka:BAAANQABCgEIAQAAAA==.',
Zi='Zipp:BAAANQABCgEIAQAAAA==.',
['Õs']='Õso:BAAANQABCgMIAwAAAA==.',
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
