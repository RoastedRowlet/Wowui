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

local lookup = {'Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Mage-Arcane','Priest-Shadow','Hunter-BeastMastery','DeathKnight-Blood','Unknown-Unknown','Mage-Frost','Warrior-Arms','Warrior-Fury','DemonHunter-Vengeance','Paladin-Holy','Monk-Brewmaster','Evoker-Devastation','DeathKnight-Frost','Hunter-Survival','Druid-Feral','Shaman-Elemental','Warlock-Demonology','Shaman-Enhancement','DeathKnight-Unholy','Druid-Restoration','Hunter-Marksmanship','Warlock-Affliction','DemonHunter-Havoc','Druid-Guardian','DemonHunter-Devourer','Druid-Balance','Priest-Holy','Evoker-Preservation','Monk-Mistweaver','Monk-Windwalker','Warlock-Destruction','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection','Priest-Discipline',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abcdeath:BAAANQABCgcICAAAAA==.',
Ad='Adanac:BAAANQAECgUIDAABNQAECgoKHQABAKARAA==.Addalyne:BAAANQADCggIDwAAAA==.Adhenar:BAAANQAECgMIBQAAAA==.Adow:BAAANQAECgEIAQAAAA==.Adynne:BAAANQAECgMIAwABNQAECgkJFQACAL8eAA==.',
Ae='Aered:BAAANQAECgQIBQAAAA==.',
Ah='Ahira:BAABNQAECn80AAIDAAoKwBpfIABCAgADAAoKwBpfIABCAgAAAA==.',
Ai='Airro:BAAANQADCgYIEAAAAA==.Aishe:BAAANQAECgQICgAAAA==.',
Ak='Akashã:BAABNQAECn81AAIEAAoK3CFcNAAhAwAEAAoK3CFcNAAhAwAAAA==.Akuria:BAABNQAECn87AAIFAAgKAhpPHgBNAgAFAAgKAhpPHgBNAgAAAA==.',
Al='Alacía:BAAANQAFFAEIAQAAAA==.Alahna:BAABNQAECn8WAAIGAAcK+QU/xwCjAAAGAAcK+QU/xwCjAAAAAA==.',
Am='Amaarth:BAAANQAECgMIBAABNQAECgoKNAAHACojAA==.',
An='Andeyn:BAAANQAECgIIAQAAAA==.Anies:BAABNQAECn8iAAIHAAoKZwtLJABzAQAHAAoKZwtLJABzAQAAAA==.',
Aq='Aquarian:BAAANQAECgUIEgAAAA==.',
Ar='Arthaz:BAAANQAECgEIAQAAAA==.Artëmîs:BAAANQAECgYIDAAAAA==.',
As='Asherrylie:BAAANQADCgUICwAAAA==.Asmodeuss:BAAANQADCggIEQAAAA==.Assasincross:BAAANQADCgEIAQAAAA==.',
Av='Avãrice:BAAANQADCgcIBwAAAA==.',
Ba='Babbagnush:BAAANQAECgIIAgAAAA==.Babysneeze:BAAANQADCgYIBQAAAA==.Backkstabber:BAAANQAECgQIBgAAAA==.Badbev:BAAANQADCgUIDQABNQAECgUIDAAIAAAAAA==.Balzinner:BAAANQAECgIIAgAAAA==.Barene:BAAANQAECggIBwAAAA==.Basspro:BAAANQADCgMIAwAAAA==.Batmuhn:BAAANQADCgEIAQAAAA==.',
Be='Beastiam:BAAANQABCgIIAgAAAA==.Belserion:BAABNQAECn9UAAMEAAoKfiNQFACCAwAEAAoK0CJQFACCAwAJAAMKnCH0GwARAQAAAA==.Beltryne:BAAANQAECgUIBQABNQAECgoKVAAEAH4jAA==.Benny:BAAANQADCgEIAQAAAA==.Berol:BAABNQAECn8YAAMKAAcKmBbTXwBjAQAKAAcKmBbTXwBjAQALAAMK5BBGIgCmAAAAAA==.Beroldin:BAAANQAECgYIDwABNQAECgcIGAAKAJgWAA==.Bevar:BAAANQAECgUIBQABNQAECgUIDAAIAAAAAA==.Bevell:BAAANQAECgQIBAABNQAECgUIDAAIAAAAAA==.',
Bi='Biggiesdk:BAAANQADCggICAAAAA==.',
Bl='Blindmafaka:BAABNQAECn8sAAIMAAoK5BEaCQBbAQAMAAoK5BEaCQBbAQAAAA==.Blkrend:BAAANQAECgYICwABNQAECgoKTAAEAEUlAA==.',
Bo='Bonney:BAAANQAECgQIBwAAAA==.Bonzai:BAAANQAECgUICAAAAA==.',
Br='Bradycam:BAABNQAECn82AAIBAAoKuB4uJgBrAgABAAoKuB4uJgBrAgAAAA==.Brightlock:BAAANQADCgYIDAAAAA==.Brnyshamders:BAAANQAECgUIBQAAAA==.',
Bu='Busterblader:BAAANQAECgQIBwAAAA==.',
['Bó']='Bóbafett:BAAANQABCgQIBAAAAA==.',
Ca='Cantpalyhard:BAABNQAECn8bAAMNAAgKJhhNJgAcAgANAAgKJhhNJgAcAgABAAUKSwf9KAHcAAABNQAECgoKMwADACMZAA==.Casella:BAABNQAECn85AAIOAAoKWSPFAQCiAwAOAAoKWSPFAQCiAwAAAA==.',
Ce='Celerrime:BAAANQABCgUIBgAAAA==.',
Ch='Chemistry:BAAANQAECgUICAABNQAECgkJNgABANokAA==.Chilindrina:BAAANQABCgIIAgAAAA==.Chupacabbra:BAAANQAECgYIDAAAAA==.',
Ci='Cierdwyn:BAAANQADCggIDAAAAA==.Cinthara:BAAANQAECgEIAQAAAA==.',
Cl='Cleth:BAABNQAECn8sAAIBAAgKUBl+eAA7AgABAAgKUBl+eAA7AgAAAA==.Clouzot:BAAANQADCgUICwAAAA==.',
Co='Corax:BAABNQAECn82AAIPAAgKcRBeCgBIAQAPAAgKcRBeCgBIAQAAAA==.',
Cr='Crane:BAAANQABCgIIAgAAAA==.Crankitty:BAAANQAECggICAAAAA==.Critshot:BAAANQADCgQIBAABNQAFFAQICQAKAKQYAA==.',
Cu='Cunumi:BAABNQAECn8UAAIBAAYKIwipHwHqAAABAAYKIwipHwHqAAAAAA==.Cutie:BAAANQADCgMIAwAAAA==.',
['Cö']='Cösmic:BAAANQAECgMIAwAAAA==.',
Da='Dalathriel:BAAANQADCgcIBwAAAA==.Damachi:BAABNQAECn8tAAIQAAkKtxakHQDfAQAQAAkKtxakHQDfAQAAAA==.Danji:BAABNQAECn8YAAIQAAkKKhK6HADmAQAQAAkKKhK6HADmAQAAAA==.Darkasuna:BAAANQADCgcIEQAAAA==.Darmorae:BAABNQAECn8UAAIRAAgKqgZiCQChAQARAAgKqgZiCQChAQAAAA==.Dashii:BAAANQAECggIDQABNQAECgkJGQASAF8NAA==.Datewoo:BAABNQAECn8XAAIBAAcKLRRbtAC2AQABAAcKLRRbtAC2AQAAAA==.Datsuo:BAAANQAECgYIDgABNQAECgcIGQAQAGkUAA==.',
De='Deathlock:BAAANQAECggIAQAAAA==.Deathris:BAAANQAECgQJBwAAAA==.Deef:BAAANQADCgQIBAAAAA==.Demonicbjorn:BAAANQADCggICAABNQAECgUIBQAIAAAAAA==.Demonish:BAABNQAECn8tAAIKAAoKlB61JgBLAgAKAAoKlB61JgBLAgAAAA==.Demontotem:BAABNQAECn8XAAMTAAgKnQhSUgAWAQATAAgKnQhSUgAWAQADAAQKHwun3gCrAAAAAA==.Desadeness:BAAANQADCgYIDQABNQADCggIGAAIAAAAAA==.',
Di='Dillinquent:BAAANQAECgQIBAAAAA==.',
Dr='Dracdemonica:BAAANQAECgUICgABNQAECgoKPgAGALwUAA==.Dracfu:BAAANQAECgUIDwABNQAECgoKPgAGALwUAA==.Dracklock:BAAANQAECgEIAQABNQAECggICwAIAAAAAA==.Drackpally:BAAANQAECggICwAAAA==.Dracserion:BAAANQADCggIDgABNQAECgoKVAAEAH4jAA==.Dracsham:BAAANQADCggICAABNQAECgoKPgAGALwUAA==.Dracshot:BAABNQAECn8+AAIGAAoKvBTdNQAIAgAGAAoKvBTdNQAIAgAAAA==.Dracslock:BAABNQAECn8YAAIUAAgKYgXQmQC8AAAUAAgKYgXQmQC8AAABNQAECgoKPgAGALwUAA==.Draffel:BAABNQAECn8lAAMTAAkKGRfBKwCwAQATAAkKGRfBKwCwAQADAAEKQg7W0wApAAAAAA==.Dragussÿ:BAAANQADCgcIBwAAAA==.Dreamfire:BAAANQAECgYICQAAAA==.Drestla:BAAANQAECgUIDQAAAA==.Drraakk:BAAANQADCgUIBgABNQAECggICwAIAAAAAA==.Dräc:BAAANQAECgYICAABNQAECgoKPgAGALwUAA==.',
Du='Dukstorm:BAAANQAECgQIBAAAAA==.Dundinn:BAAANQADCgMIAwABNQAECggIGgAEAJoKAA==.Dunzer:BAABNQAECn8yAAMCAAoKXBC6IAD2AAABAAYKVxC+8gA3AQACAAgK1hC6IAD2AAAAAA==.Dunzerblaze:BAABNQAECn8ZAAIEAAcK9QTwnwAGAQAEAAcK9QTwnwAGAQAAAA==.',
Ed='Edithpoothe:BAABNQAECn8mAAIEAAoKmRwlHQCJAgAEAAoKmRwlHQCJAgAAAA==.',
El='Electricks:BAABNQAECn8/AAMVAAoKwiCRBABKAwAVAAoKwiCRBABKAwATAAYKTBc4igCKAQAAAA==.Elicia:BAAANQADCgUIBQAAAA==.',
Em='Emmii:BAAANQADCgUIEAAAAA==.',
En='Enazure:BAAANQADCgcICwAAAA==.',
Ep='Epiphaný:BAABNQAECn8hAAMJAAcKnhPkFgC8AAAEAAcKMBEi/QCTAQAJAAMKuhPkFgC8AAABNQAECgkJGQASAF8NAA==.',
Er='Eradoria:BAAANQAECgUICAAAAA==.Ermgoob:BAAANQAECgMJAwAAAA==.Erosinamun:BAAANQADCgQIBAAAAA==.',
Et='Etrigon:BAAANQADCgYICAAAAA==.',
Ev='Evadne:BAABNQAECn8sAAMDAAoKShGhOgCvAQADAAoKShGhOgCvAQATAAYKnAU21ADsAAAAAA==.Evagrius:BAAANQABCgIIAgAAAA==.Eveokan:BAAANQAECgcIBwAAAA==.',
Ex='Extremespeed:BAAANQADCgcIEwABNQAECgkJKgAWACwXAA==.',
Fa='Faant:BAAANQADCgUIBQABNQAECggIGQADAB8dAA==.Failshift:BAAANQAECgMIAwAAAA==.Fangy:BAAANQABCgIIAwAAAA==.Fatpats:BAAANQABCgIIAgAAAA==.',
Fi='Fistantillus:BAAANQAECgIIAgAAAA==.',
Fl='Flopper:BAAANQAECgcIEAAAAA==.Fluttershy:BAAANQADCgQIBAAAAA==.',
Fo='Foxyboo:BAABNQAECn8zAAMDAAoKIxk8JAApAgADAAoKIxk8JAApAgATAAQK7gik7QC7AAAAAA==.',
Fr='Freak:BAABNQAECn8WAAIXAAgKixfJEAAaAgAXAAgKixfJEAAaAgAAAA==.Freakpeachh:BAAANQAECgQJBQAAAA==.',
Ga='Galerodra:BAAANQADCggICAAAAA==.Garalline:BAAANQADCgYICAAAAA==.',
Gh='Ghostofpete:BAAANQABCgIIAgAAAA==.',
Gn='Gnomatic:BAAANQAECgQIBgAAAA==.',
Go='Gooberetta:BAABNQAECn8zAAIGAAoKrB9oIQARAwAGAAoKrB9oIQARAwAAAA==.Gooberoni:BAAANQADCgUJBQAAAA==.Gope:BAABNQAECn8iAAMDAAkK2h/GFgAbAwADAAkK2h/GFgAbAwATAAEK7ARWPgEvAAAAAA==.Gostewpid:BAAANQAECgEIAQAAAA==.',
Gr='Gromiir:BAABNQAECn8lAAMGAAoKdR+xIAAVAwAGAAkKAyKxIAAVAwAYAAEKlQ39iAA1AAAAAA==.Gromyr:BAAANQADCgcIBwABNQAECgoKJQAGAHUfAA==.',
['Gä']='Gärrus:BAAANQAECgQIBgAAAA==.',
Ha='Haurrmoany:BAAANQADCgEIAQAAAA==.',
He='Healingman:BAAANQADCgYIDwAAAA==.Hellkat:BAAANQAECgQIBAAAAA==.',
Hi='Higarosa:BAAANQAECgEIAQAAAA==.Highbull:BAAANQAECggIDAABNQAECgkJGQASAF8NAA==.',
Ho='Holiblade:BAABNQAECn8kAAIBAAgKNwjh1gBuAQABAAgKNwjh1gBuAQAAAA==.Holyhannah:BAAANQADCgIIAQAAAA==.Holytoki:BAAANQAECgUIBQAAAA==.Holywhiskers:BAAANQAECgQICgABNQAECgoKTwABADsYAA==.Hooligun:BAAANQAECgUICAAAAA==.Hoppered:BAAANQAECgYICwABNQAECgoKKwAZAEwgAA==.',
Hy='Hypérian:BAAANQAECgUICgAAAA==.',
Ia='Ianes:BAAANQADCgYIBwAAAA==.Iantha:BAAANQAECggIEwAAAA==.',
Ic='Icesikle:BAAANQAECgQICAAAAA==.',
Ig='Igglybuff:BAAANQAECgUICgAAAA==.',
Ij='Ijustshotyou:BAABNQAECn8xAAMGAAoKdRZffQATAgAGAAoKuRVffQATAgAYAAUKhw9IIwDjAAAAAA==.',
Il='Illusiongun:BAAANQAECgUIBwABNQAECgoKPwAaAH0gAA==.',
In='Insaniac:BAAANQADCggIFAAAAA==.Intervention:BAAANQABCgIIBAAAAA==.Invidious:BAAANQAECgQIBgAAAA==.',
Ir='Ironlotss:BAAANQADCggICwAAAA==.',
Iz='Izumo:BAAANQAECgQICAAAAA==.',
Ja='Jagerbomb:BAAANQADCgUJBQAAAA==.Jardal:BAAANQADCgIJAgAAAA==.Jatswamdi:BAABNQAECn9BAAICAAoKWiJEBADdAgACAAoKWiJEBADdAgAAAA==.',
Jn='Jnymango:BAAANQAECgcIDwAAAA==.',
Jo='Johnnysham:BAAANQADCggJCgABNQAECgcIDwAIAAAAAA==.Jollakeratu:BAABNQAECn82AAIbAAgKExPNGwDFAQAbAAgKExPNGwDFAQAAAA==.Josequervo:BAAANQADCgIIAgAAAA==.',
Ju='Jugram:BAAANQAECgEIAQAAAA==.Jusmissiner:BAAANQAECgYICwAAAA==.Juut:BAABNQAECn8bAAIHAAoKzBuaIQCoAgAHAAoKzBuaIQCoAgAAAA==.',
['Jø']='Jønty:BAAANQADCgUICwAAAA==.',
Ka='Kaelyra:BAAANQADCgIJAgAAAA==.',
Ke='Keelhorn:BAABNQAECn81AAMDAAoK9wwxcgC1AQADAAoK9wwxcgC1AQATAAcKqQm5cADAAAAAAA==.Kemboy:BAAANQADCgEJAQAAAA==.Kenneth:BAAANQADCgQIBAABNQAFFAcIGAAVALsPAA==.Kerubiel:BAABNQAECn8XAAQCAAcK8hipMgBMAQACAAcK8hipMgBMAQABAAQKoAkdOAHGAAANAAQKyQZJkACgAAABNQAECgcIGQAQAGkUAA==.Kessarah:BAABNQAECn8bAAIcAAgK7wzJNwCGAQAcAAgK7wzJNwCGAQAAAA==.',
Kh='Khadraga:BAAANQAECgQICgAAAA==.',
Ki='Kilthas:BAAANQAECgEIAQAAAA==.Kinkyhawt:BAEBNQAECn8fAAIFAAoKbhvjEgDTAgAFAAoKbhvjEgDTAgAAAA==.Kirio:BAAANQADCgcIEgAAAA==.Kitsunenohi:BAABNQAECn8sAAIaAAgKeQa6UABUAQAaAAgKeQa6UABUAQAAAA==.Kitsunezorro:BAAANQAECgIIBQAAAA==.',
Ko='Kodiakk:BAAANQAECgIIAgAAAA==.Kornbread:BAAANQADCgEIAwAAAA==.',
Kr='Kraelith:BAAANQAECgMIBAAAAA==.Krattos:BAAANQAECgUICwAAAA==.Krimzin:BAAANQAECgMIBAABNQAFFAcIDgAGABUYAA==.',
Ks='Ksandra:BAABNQAECn8XAAIEAAcKZQ0qkQAhAQAEAAcKZQ0qkQAhAQAAAA==.Ksares:BAABNQAECn8+AAMSAAoKbiE1AgDuAgASAAoKbiE1AgDuAgAdAAMKxQhBmgBxAAAAAA==.',
Kw='Kwazii:BAABNQAECn8YAAMeAAcKwAvKiAB8AQAeAAcKwAvKiAB8AQAFAAYKqgb0TQDcAAABNQAECgkJGQASAF8NAA==.',
Ky='Kyantzmi:BAAANQADCgEIAQAAAA==.Kyogre:BAAANQAECgQICQAAAA==.',
['Kë']='Këvîn:BAABNQAECn8XAAMJAAcK8gySFgBJAQAJAAcK8gySFgBJAQAEAAQKGAjkfgHFAAAAAA==.',
La='Laeflockxo:BAAANQAECgQIBgAAAA==.Laefnia:BAABNQAECn8xAAQdAAoKFRjNGgC4AQAdAAoKFRjNGgC4AQAXAAMKJxY8UQDEAAAbAAQK1wuqQgCrAAAAAA==.Laraydra:BAAANQAECgYIDAABNQAECggIGgAEAJoKAA==.Laresistance:BAAANQADCgQIBAAAAA==.Lastofgoobs:BAAANQAECgYIBQAAAA==.',
Le='Leard:BAAANQAECgUICgABNQAECgoKJQALALQeAA==.',
Li='Lichnephilim:BAAANQADCgUIBQAAAA==.Lildarleena:BAAANQADCgYICAAAAA==.Lilis:BAAANQAECgUICQAAAA==.Lilithe:BAAANQAECgUIBwABNQAECgoKKwAZAEwgAA==.Liten:BAAANQADCgUICAAAAA==.Lithndice:BAAANQADCgYIBgAAAA==.Littlebev:BAAANQAECgUIDAAAAA==.Liz:BAAANQADCgUICwAAAA==.',
Lo='Longshankss:BAAANQAECgEIAQAAAA==.',
Lu='Lucifers:BAAANQADCgMIAwAAAA==.Lucìen:BAAANQAECggICAAAAA==.',
['Lé']='Léxí:BAAANQAECggIBwAAAA==.',
Ma='Maachen:BAAANQADCgcIDAAAAA==.Maalik:BAAANQADCgQIBAABNQAECgcIGQAQAGkUAA==.Macncheeze:BAAANQABCgQIBAAAAA==.Maduin:BAAANQADCgUIBQAAAA==.Maiangel:BAAANQAECgYICgAAAA==.Maiikeru:BAAANQADCgUIBgAAAA==.Malaurray:BAABNQAECn8bAAIUAAkKqwh+VQBiAQAUAAkKqwh+VQBiAQABNQADCgEIAQAIAAAAAA==.Malkôan:BAAANQADCgYICgAAAA==.Maluin:BAAANQADCgcIGgABNQAECgkJJgAaAIcQAA==.Mawea:BAAANQADCgQIBAABNQAECggIGgAEAJoKAA==.',
Mc='Mcchong:BAAANQADCgUIBQAAAA==.Mckennah:BAABNQAECn8VAAMCAAkKvx6WDwCkAgACAAkKvx6WDwCkAgANAAEKJA1vIQEzAAAAAA==.',
Me='Melinea:BAAANQAECgMIAwAAAA==.Mereidith:BAABNQAECn8vAAIEAAgKzxV7sgAeAgAEAAgKzxV7sgAeAgAAAA==.Mesohungry:BAAANQAECgUICgAAAA==.Meuria:BAAANQABCgYICAAAAA==.',
Mi='Mikedicurt:BAAANQADCgEIAQABNQAECgoKJgAEAJkcAA==.Milele:BAAANQAECgIIBAAAAA==.Mir:BAAANQADCggICAAAAA==.Missnoms:BAAANQADCgYIEgAAAA==.Mistue:BAAANQAECgEIAQABNQAECgoKOQAOAE4dAA==.',
Mo='Moobáca:BAABNQAECn8ZAAQSAAkKXw12GAB0AQASAAgKew12GAB0AQAbAAMKahDSOQB1AAAdAAEKiQMEeAAcAAAAAA==.Moostradamas:BAABNQAECn8XAAMQAAgKUQWBawDwAAAQAAgKUQWBawDwAAAHAAIK4wpuwgBDAAAAAA==.Morcilla:BAABNQAECn8kAAQHAAkKgAWvPQDrAAAQAAgKjgN0agD1AAAHAAgK7gWvPQDrAAAWAAEKKQNe/AAcAAAAAA==.',
My='Myssts:BAAANQADCgUICQAAAA==.',
['Mí']='Mínervä:BAAANQAECggIBAAAAA==.',
['Mî']='Mîlkmytötem:BAAANQADCgQIBAAAAA==.',
Na='Nacole:BAAANQADCgYIBgAAAA==.Nalleth:BAAANQADCgYIBgAAAA==.Nanakii:BAAANQADCgQIBAABNQAECggIGQADAB8dAA==.Narisa:BAAANQABCgMIAwAAAA==.Naturegoob:BAABNQAECn8yAAMXAAoKsyHHDgDnAgAXAAoKsyHHDgDnAgAdAAcKdhSXTwCgAQAAAA==.Naughtynurse:BAABNQAECn8xAAIXAAoKBQdMJgAqAQAXAAoKBQdMJgAqAQAAAA==.',
Ne='Neuma:BAABNQAECn8VAAIBAAYKuwmXAQEdAQABAAYKuwmXAQEdAQAAAA==.',
Ni='Nicfurry:BAAANQADCgEIAQAAAA==.Nightflower:BAABNQAECn8rAAIJAAoK0wiSEgB+AQAJAAoK0wiSEgB+AQAAAA==.',
No='Nostromo:BAABNQAECn8sAAIfAAoKLBVSDgCQAQAfAAoKLBVSDgCQAQAAAA==.',
Ny='Nyxserion:BAAANQAECgYIBwABNQAECgoKVAAEAH4jAA==.',
Ob='Obiejuan:BAABNQAECn9CAAIBAAoKqCLqDgD/AgABAAoKqCLqDgD/AgAAAA==.',
Od='Odbc:BAABNQAECn8xAAIdAAoKLxpqJgCgAgAdAAoKLxpqJgCgAgAAAA==.Oddball:BAABNQAECn8yAAITAAoKyB49IAALAwATAAoKyB49IAALAwAAAA==.',
Op='Ophiron:BAAANQADCgcICAAAAA==.',
Or='Orangecrush:BAAANQADCggICAAAAA==.Orthiaa:BAABNQAECn8WAAIGAAUK3gquoADtAAAGAAUK3gquoADtAAAAAA==.',
Os='Osalot:BAAANQADCggIEAAAAA==.',
Pa='Paintrain:BAAANQAECgUICAAAAA==.Paladinning:BAAANQADCgUIBQAAAA==.',
Pe='Peso:BAAANQAECggIBwABNQAECgkJGQASAF8NAA==.Pez:BAABNQAECn85AAMDAAoKLxuNJgDKAgADAAoKLxuNJgDKAgATAAEKAACH3QAAAAAAAA==.',
Ph='Phaidon:BAAANQADCggICAAAAA==.',
Pi='Pixularformd:BAAANQADCgYICQAAAA==.',
Po='Police:BAABNQAECn8VAAIeAAkKoRdsOgDMAQAeAAkKoRdsOgDMAQAAAA==.Polyhedroll:BAABNQAECn8kAAMgAAkKsx97CwDNAgAgAAkKsx97CwDNAgAhAAMKEgovWQCDAAABNQAFFAIIAwAIAAAAAA==.Postmalorne:BAAANQADCgEIAQAAAA==.Powerzone:BAAANQADCgIIAgAAAA==.',
Pr='Primafox:BAAANQADCgEIAQAAAA==.',
Ps='Psychoman:BAABNQAECn8fAAIFAAkKwRMXEQC6AQAFAAkKwRMXEQC6AQAAAA==.',
Pu='Punchandkick:BAAANQAECgIIBQAAAA==.Punchdeath:BAAANQADCgUIBQAAAA==.Purplerainjr:BAABNQAECn8ZAAIQAAgKCguANQBHAQAQAAgKCguANQBHAQAAAA==.',
['Pó']='Póplókndótit:BAAANQAECgMIBAAAAA==.',
Qu='Quivermethis:BAAANQADCgUIBQAAAA==.',
Qx='Qx:BAAANQADCgMIAwAAAA==.',
Ra='Raakoth:BAABNQAECn8ZAAMQAAcKaRTEPAAmAQAHAAYKzxUeZABiAQAQAAcKsg7EPAAmAQAAAA==.Raathe:BAAANQADCgUICwAAAA==.Radge:BAABNQAECn8iAAIKAAkKWiVjBgDAAwAKAAkKWiVjBgDAAwAAAA==.Rainjar:BAAANQAECggIDgAAAA==.Rainne:BAAANQADCgQIBAAAAA==.Ralanar:BAABNQAECn8YAAIcAAUKtQ0oSQANAQAcAAUKtQ0oSQANAQABNQAECggIGgAEAJoKAA==.Raljah:BAABNQAECn8rAAQZAAoKTCDFAADiAgAZAAoKTCDFAADiAgAUAAcKnhnvbwAPAgAiAAUK/BSuIABrAQAAAA==.Rampart:BAAANQABCgQIBAAAAA==.',
Re='React:BAABNQAECn80AAIHAAoKKiObDABNAwAHAAoKKiObDABNAwAAAA==.Renpriest:BAAANQADCgYIDQAAAA==.',
Ri='Richpplwater:BAABNQAECn8WAAIBAAUKzw89DQEJAQABAAUKzw89DQEJAQAAAA==.',
Ro='Rockie:BAAANQAECgEIAwAAAA==.Rotation:BAAANQABCgIIAgABNQAECgYIHgAMANoVAA==.Royalchaos:BAAANQAECgIIAwABNQAECgoKQgAeAAscAA==.',
Ru='Rubyraeven:BAAANQADCggIDgAAAA==.',
Ry='Ryobi:BAABNQAECn81AAIGAAoKUhhGXwBZAgAGAAoKUhhGXwBZAgAAAA==.Ryptyde:BAAANQAECggIDQAAAA==.',
Sa='Saccharinê:BAAANQABCgMIAwAAAA==.Saintangel:BAAANQABCgQIAgAAAA==.Salinan:BAABNQAECn83AAMZAAoKwR3bAgDhAgAZAAgK4iLbAgDhAgAUAAgKvhSNiADRAQAAAA==.Saric:BAAANQAECgQICQAAAA==.',
Se='Selinedion:BAABNQAECn8dAAIBAAoKoBEWgwBLAQABAAoKoBEWgwBLAQAAAA==.Seraphiim:BAAANQAECgMIAwABNQAECgkJIwAEAEggAA==.Serdav:BAAANQAECgEIAQAAAA==.',
Sh='Shak:BAAANQADCgYIDQAAAA==.Shalai:BAACNQAFFH8FAAIaAAUKLhF8CwCsAAAaAAUKLhF8CwCsAAA1AAQKfykAAhoACgouIrUFAAEDABoACgouIrUFAAEDAAAA.Shastix:BAAANQADCgYIBgABNQAECgcIGQAQAGkUAA==.Shellingtun:BAAANQAECggIDQABNQAECgkJGQASAF8NAA==.Shilóh:BAAANQADCgYIBwAAAA==.Shyandrial:BAAANQADCgYIJQAAAA==.Shyness:BAAANQADCggICAAAAA==.',
Sk='Sksteve:BAAANQAECgQICQAAAA==.Skychades:BAABNQAECn8lAAIGAAcKcRg2agA/AgAGAAcKcRg2agA/AgAAAA==.',
Sn='Sneakygoob:BAAANQADCgMIAwAAAA==.Snorlax:BAAANQAECgUICgAAAA==.',
So='Soulsrequiem:BAAANQADCggIFwAAAA==.',
Sp='Splash:BAAANQADCgQIBAAAAA==.Spookycurse:BAAANQADCgEIAQAAAA==.Spookydeath:BAABNQAECn8ZAAIJAAkK5RfPCQAyAgAJAAkK5RfPCQAyAgAAAA==.Spookypriest:BAAANQADCgIIAgAAAA==.',
Sr='Srsnacksalot:BAABNQAECn8jAAIBAAcKghWZjQA2AQABAAcKghWZjQA2AQAAAA==.',
St='Stileto:BAABNQAECn8UAAMjAAgKpAWTdgCPAAAjAAgK4wSTdgCPAAAkAAIKjwMlpQAyAAABNQAECgkJGQASAF8NAA==.Stoneydracco:BAABNQAECn8rAAMJAAoKyA23DADsAQAJAAgKzhC3DADsAQAEAAkKrQMcxwC9AAAAAA==.Stèvè:BAAANQADCgIIAgAAAA==.',
Su='Subz:BAAANQABCgIIAgABNQAFFAcIFAATAOsiAA==.Sumtinwng:BAABNQAECn8WAAIBAAgKRwpivQCiAQABAAgKRwpivQCiAQAAAA==.Sunchipz:BAAANQADCgcICwAAAA==.Sungjay:BAAANQAECgcIDAAAAA==.Supervicious:BAABNQAECn8bAAIlAAoKEw7qFwCvAQAlAAoKEw7qFwCvAQAAAA==.',
Sy='Sylenne:BAAANQAECgUICAABNQAECgoKOQADAC8bAA==.Sylur:BAABNQAECn8qAAQWAAkKLBdJOQA/AgAWAAkKFxdJOQA/AgAQAAcKwhImUgBoAQAHAAQKrw+lWQCJAAAAAA==.',
['Sæ']='Sælinsonia:BAAANQAECgMIBAAAAA==.',
Ta='Tahren:BAACNQAFFH8YAAMeAAUKFh10DwCcAQAeAAUKFh10DwCcAQAmAAIKLwFkAwBgAAA1AAQKf0kABB4ACgrAIpgRADwDAB4ACgrAIpgRADwDAAUABwqhGk4bADMBACYAAwoZICURABYBAAAA.Tahshock:BAAANQADCgYICwABNQAFFAUIGAAeABYdAA==.Talanji:BAAANQADCgEIAQAAAA==.Taler:BAAANQADCgIIAgAAAA==.Talerion:BAABNQAECn8nAAMPAAoKBBZfBgDOAQAPAAoKBBZfBgDOAQAfAAEKGQ/rTQA3AAAAAA==.',
Te='Telline:BAAANQADCgEIAQAAAA==.Tempô:BAAANQADCggICAAAAA==.',
Th='Thatonemonk:BAAANQADCgQJBAABNQAECgQIBgAIAAAAAA==.Thereaben:BAAANQADCgcIEQAAAA==.Thistelbear:BAABNQAECn8sAAIhAAgKCwu1HQA7AQAhAAgKCwu1HQA7AQAAAA==.Thorinn:BAAANQAECgcIDQAAAA==.Thornbloom:BAAANQADCggICAAAAA==.Thrallsux:BAAANQABCgYJBwAAAA==.Thraun:BAAANQAECgIIBAAAAA==.Thunderdin:BAABNQAECn80AAMCAAoK/Rm+FwA7AgACAAgKehi+FwA7AgABAAoKNxV/hQAdAgAAAA==.',
Ti='Tidfl:BAAANQADCgMJAwAAAA==.Tirrian:BAAANQADCggICAAAAA==.Titszilla:BAAANQAECgUICAABNQAECgkJGQASAF8NAA==.',
To='Toki:BAAANQAECgQIDAAAAA==.Tokidh:BAAANQADCgYIBgAAAA==.Tokihots:BAAANQADCgQICAABNQAECgQIDAAIAAAAAA==.',
Tu='Turnip:BAAANQAECggIDwABNQAECgkJGQASAF8NAA==.',
Tw='Twamsack:BAAANQABCgUIBwAAAA==.Tweak:BAAANQAECgYIDAABNQAECgkJGQASAF8NAA==.Tweis:BAAANQADCgUICwAAAA==.',
Um='Umbrarogue:BAABNQAECn8nAAMkAAoKux/+EwDcAgAkAAoKwRv+EwDcAgAjAAMKYR04WAD7AAAAAA==.',
Va='Vaara:BAAANQABCgEIAQAAAA==.Valaa:BAAANQAECgEIAQAAAA==.Vanddrena:BAABNQAECn8eAAIcAAkKJAddNwCJAQAcAAkKJAddNwCJAQAAAA==.',
Ve='Velien:BAABNQAECn8oAAIBAAkKehG/gwAgAgABAAkKehG/gwAgAgAAAA==.Verwind:BAAANQADCgIIAgAAAA==.',
Vi='Vicotr:BAAANQADCgQIBgAAAA==.Viddysouls:BAAANQAECgUICgAAAA==.Viscerai:BAABNQAECn8tAAIeAAkKASKPDwD2AgAeAAkKASKPDwD2AgAAAA==.Vite:BAAANQAECgQJBgAAAA==.',
Vo='Vonmiller:BAAANQAECgQICAAAAA==.Vorzul:BAAANQAECgUICgAAAA==.Vozluz:BAAANQADCgEIAQABNQAECgcIGQAQAGkUAA==.',
Vr='Vryndiel:BAAANQABCgUIBQAAAA==.',
Vy='Vynllàn:BAAANQADCgYICgAAAA==.',
Wa='Walas:BAAANQADCggICQAAAA==.Walklight:BAAANQADCgUIBQAAAA==.',
Wh='Whyjudaswhy:BAAANQAECgIIAgAAAA==.',
Yu='Yurie:BAAANQAECgQIBAAAAA==.',
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
