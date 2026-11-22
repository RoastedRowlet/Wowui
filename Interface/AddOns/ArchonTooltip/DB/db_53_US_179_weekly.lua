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

local lookup = {'Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Priest-Shadow','Shaman-Enhancement','DeathKnight-Frost','Mage-Arcane','Hunter-BeastMastery','Warrior-Arms','DeathKnight-Blood','Warlock-Destruction','Mage-Frost','Warrior-Fury','DemonHunter-Vengeance','Paladin-Holy','Monk-Brewmaster','Warlock-Affliction','Evoker-Devastation','Hunter-Survival','Druid-Feral','Unknown-Unknown','Shaman-Elemental','DemonHunter-Havoc','Monk-Mistweaver','Warlock-Demonology','DeathKnight-Unholy','Druid-Restoration','Hunter-Marksmanship','Druid-Guardian','DemonHunter-Devourer','Druid-Balance','Priest-Holy','Evoker-Preservation','Monk-Windwalker','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection','Priest-Discipline',}
local provider = {region='US',realm='Rexxar',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abcdeath:BAAANQABCgcICAAAAA==.',
Ad='Adanac:BAAANQAECgUIDAABNQAECgoKLwABACMVAA==.Addalyne:BAAANQADCggIFwAAAA==.Adhenar:BAAANQAECgMIBQAAAA==.Adow:BAAANQAECgEIAQAAAA==.Adynne:BAAANQAECgMIAwABNQAECgkJFgACAL8eAA==.',
Ae='Aered:BAAANQAECgQIBQAAAA==.',
Ah='Ahira:BAABNQAECn86AAIDAAoKxBo1PgBnAgADAAoKxBo1PgBnAgAAAA==.',
Ai='Airro:BAAANQADCgYIEAAAAA==.Aishe:BAABNQAECn8bAAIEAAkK4A9VFwDwAQAEAAkK4A9VFwDwAQAAAA==.Aitruin:BAABNQAECn8VAAIFAAcKfxECHABaAQAFAAcKfxECHABaAQABNQAECgcIJAAGAK4VAA==.',
Ak='Akashã:BAABNQAECn81AAIHAAoK3CFcNAAhAwAHAAoK3CFcNAAhAwAAAA==.Akuria:BAABNQAECn9OAAIEAAoKKxj0EgAtAgAEAAoKKxj0EgAtAgAAAA==.',
Al='Alacía:BAAANQAFFAEIAQAAAA==.Alahna:BAABNQAECn8cAAIIAAgK+QWi/AALAQAIAAgK+QWi/AALAQAAAA==.Alsta:BAAANQAECgYIBgABNQAECgoKIwAJANAXAA==.',
Am='Amaarth:BAAANQAECgMIBAABNQAECgoKNAAKACojAA==.',
An='Andeyn:BAAANQAECgIIAQAAAA==.Anies:BAACNQAFFH8GAAIKAAIKWgPcJQBLAAAKAAIKWgPcJQBLAAA1AAQKfzwAAgoACgrHEOooALgBAAoACgrHEOooALgBAAAA.',
Aq='Aquarian:BAABNQAECn8ZAAIDAAkKnwvXfgA3AQADAAkKnwvXfgA3AQAAAA==.',
Ar='Arthaz:BAAANQAECgEIAQAAAA==.Artëmîs:BAAANQAECgYIDwAAAA==.',
As='Asherrylie:BAAANQADCgYIGAAAAA==.Asmodeuss:BAAANQADCggIEQAAAA==.Assasincross:BAAANQADCgEIAQAAAA==.',
Av='Avãrice:BAAANQADCgcIBwAAAA==.',
Az='Azuresky:BAAANQADCgIIBAAAAA==.',
Ba='Babbagnush:BAAANQAECgIIAgAAAA==.Babysneeze:BAAANQADCgYIBQAAAA==.Backkstabber:BAAANQAECgQIBgAAAA==.Badbev:BAAANQADCgUIDQABNQAECgYIFQALAEoEAA==.Balzinner:BAAANQAECgIIAgAAAA==.Barene:BAAANQAECggIBwAAAA==.Basdruid:BAAANQADCgEIAQAAAA==.Basspro:BAAANQADCgMIAwAAAA==.Batmuhn:BAAANQADCgEIAQAAAA==.',
Be='Belserion:BAABNQAECn9wAAMHAAoKQiRQFACCAwAHAAoKlCNQFACCAwAMAAMKnCH0GwARAQAAAA==.Beltryne:BAAANQAECgUICQABNQAECgoKcAAHAEIkAA==.Benny:BAAANQADCgEIAQAAAA==.Benrick:BAAANQAECgQIAwAAAA==.Berol:BAABNQAECn8jAAMJAAoK0Bf0UgAFAgAJAAoK0Bf0UgAFAgANAAMK5BBGIgCmAAAAAA==.Beroldin:BAABNQAECn8gAAIBAAoK9BjBTgA/AgABAAoK9BjBTgA/AgABNQAECgoKIwAJANAXAA==.Bevar:BAAANQAECgYIBgABNQAECgYIFQALAEoEAA==.Bevell:BAAANQAECgQIBAABNQAECgYIFQALAEoEAA==.',
Bi='Bigbottom:BAAANQAECgIIAgAAAA==.Biggiesdk:BAAANQADCggICAAAAA==.',
Bl='Blindmafaka:BAABNQAECn80AAIOAAoKLRUVDACSAQAOAAoKLRUVDACSAQAAAA==.Blkrend:BAABNQAECn8gAAIKAAoKliPFBAA4AwAKAAoKliPFBAA4AwAAAA==.Bloodhound:BAAANQAECgIIAgAAAA==.',
Bo='Bonney:BAAANQAECgQIBwAAAA==.Bonzai:BAAANQAECgUICAAAAA==.',
Br='Bradycam:BAABNQAECn9AAAIBAAoKux/7KQC6AgABAAoKux/7KQC6AgAAAA==.Brightlock:BAAANQADCgYIDAAAAA==.Brnyshamders:BAAANQAECgYICgAAAA==.',
Bu='Bulloo:BAAANQADCgIIAgAAAA==.Burntpeanut:BAAANQAECgMIAwAAAA==.Busterblader:BAAANQAECggIDQAAAA==.',
Ca='Cadovenia:BAAANQAECgYICgAAAA==.Cantpalyhard:BAABNQAECn8gAAMPAAgKxxycJgCUAgAPAAgKxxycJgCUAgABAAUKSwf9KAHcAAABNQAECgoKQQADAE8cAA==.Casella:BAABNQAECn89AAIQAAoK1iPFAQCiAwAQAAoK1iPFAQCiAwAAAA==.',
Ce='Celerrime:BAAANQABCgUIBgAAAA==.',
Ch='Chemistry:BAAANQAECgUICAABNQAECgoKVgABADEmAA==.Chilindrina:BAAANQABCgIIAgAAAA==.Chupacabbra:BAAANQAECgYIDQAAAA==.',
Ci='Ciaphas:BAAANQAECgIIAgABNQAECgoKPwARAMkgAA==.Cierdwyn:BAAANQADCggIDQAAAA==.Cinthara:BAAANQAECgEIAQAAAA==.',
Cl='Cleth:BAABNQAECn86AAIBAAoK8heMZAAIAgABAAoK8heMZAAIAgAAAA==.Clouzot:BAAANQADCgYIGAAAAA==.',
Co='Corax:BAABNQAECn9KAAISAAoKMhGeCQDdAQASAAoKMhGeCQDdAQAAAA==.',
Cr='Crane:BAAANQABCgIIAgAAAA==.Crankitty:BAAANQAECggICAAAAA==.Critshot:BAAANQADCgQIBAABNQAFFAQICQAJAKQYAA==.',
Cu='Cunumi:BAABNQAECn8UAAIBAAYKIwipHwHqAAABAAYKIwipHwHqAAAAAA==.Cutie:BAAANQADCgMIAwAAAA==.',
['Cö']='Cösmic:BAAANQAECgMIAwAAAA==.',
Da='Dalathriel:BAAANQADCgcIBwAAAA==.Damachi:BAABNQAECn9MAAMGAAoK0RvhFwCLAgAGAAoKthrhFwCLAgAKAAcKfxZELgCYAQAAAA==.Danji:BAABNQAECn8YAAIGAAkKKhJ4NADSAQAGAAkKKhJ4NADSAQAAAA==.Darkasuna:BAAANQADCgcIEQAAAA==.Darmorae:BAABNQAECn8XAAITAAkKngdiCQChAQATAAkKngdiCQChAQAAAA==.Dashii:BAAANQAECggIEQABNQAECgkJGQAUAF8NAA==.Datewoo:BAABNQAECn8lAAIBAAoKjBNTiQC5AQABAAoKjBNTiQC5AQAAAA==.Datsuo:BAAANQAECgYIDgABNQAECgcIJAAGAK4VAA==.',
De='Deathlock:BAAANQAECggIAQAAAA==.Deathris:BAAANQAECgQJBwAAAA==.Demonicbjorn:BAAANQADCggICAABNQAECggIDgAVAAAAAA==.Demonish:BAABNQAECn8tAAIJAAoKlB6gSAAmAgAJAAoKlB6gSAAmAgAAAA==.Demontotem:BAABNQAECn8bAAMWAAoK5wfTbwA5AQAWAAkK6AfTbwA5AQADAAUKXwqn3gCrAAAAAA==.Desadeness:BAAANQADCgYIDQABNQAECgYICgAVAAAAAA==.',
Di='Dillinquent:BAAANQAECgQIBAAAAA==.',
Dr='Dracdemonica:BAABNQAECn8gAAIXAAoK6ArVMQCLAQAXAAoK6ArVMQCLAQABNQAECgoKSAAIANEVAA==.Dracfu:BAABNQAECn8ZAAIYAAcKrginKAC/AAAYAAcKrginKAC/AAABNQAECgoKSAAIANEVAA==.Dracklock:BAAANQAECgEIAQABNQAECggICwAVAAAAAA==.Drackpally:BAAANQAECggICwAAAA==.Dracserion:BAAANQADCggIDgABNQAECgoKcAAHAEIkAA==.Dracsham:BAAANQADCggICAABNQAECgoKSAAIANEVAA==.Dracshot:BAABNQAECn9IAAIIAAoK0RUXWgBmAgAIAAoK0RUXWgBmAgAAAA==.Dracslock:BAABNQAECn8YAAIZAAgKYgX55QD9AAAZAAgKYgX55QD9AAABNQAECgoKSAAIANEVAA==.Draffel:BAABNQAECn8lAAMWAAkKGRdFRwBZAgAWAAkKGRdFRwBZAgADAAEKQg5EBgEoAAAAAA==.Dragussÿ:BAAANQADCgcIBwAAAA==.Dreamfire:BAAANQAECgYICQAAAA==.Drestla:BAABNQAECn8dAAIIAAoKKR/sHQDJAgAIAAoKKR/sHQDJAgAAAA==.Drowgon:BAAANQAECgQIAwAAAA==.Drraakk:BAAANQADCgUIBgABNQAECggICwAVAAAAAA==.Drâc:BAAANQAECgIIAgABNQAECgoKSAAIANEVAA==.Dräc:BAAANQAECgUIDAABNQAECgoKSAAIANEVAA==.',
Du='Dukstorm:BAAANQAECgQIBAAAAA==.Dundinn:BAAANQADCgMIAwABNQAECgkJIQAHACcLAA==.Dunzer:BAABNQAECn9FAAMCAAoKOhGpHACLAQACAAoKiRCpHACLAQABAAgKGw++8gA3AQAAAA==.Dunzerblaze:BAABNQAECn8ZAAIHAAcK9QQe1wD9AAAHAAcK9QQe1wD9AAAAAA==.',
Eb='Ebonywolf:BAAANQADCgYIBgAAAA==.',
Ed='Edithpoothe:BAABNQAECn8qAAIHAAoKBh9ZLwCDAgAHAAoKBh9ZLwCDAgAAAA==.',
El='Electricks:BAABNQAECn9YAAMFAAoKvCIrAwAfAwAFAAoKvCIrAwAfAwAWAAYKTBc4igCKAQAAAA==.Elicia:BAAANQADCgUIBQAAAA==.Elontuskk:BAAANQADCgMIAwAAAA==.',
Em='Emmii:BAAANQADCgUIEAAAAA==.',
En='Enazure:BAAANQADCgcICwAAAA==.',
Ep='Epiphaný:BAABNQAECn8iAAMMAAcKXhiZGwD8AAAHAAcKMBEi/QCTAQAMAAQKKBWZGwD8AAABNQAECgkJGQAUAF8NAA==.',
Er='Eradoria:BAAANQAECgUICAAAAA==.Erielea:BAAANQADCgQIBAAAAA==.Ermgoob:BAAANQAECgMJAwAAAA==.Erosinamun:BAAANQADCgQIBAAAAA==.',
Et='Etrigon:BAAANQADCgYICAAAAA==.',
Ev='Evadne:BAABNQAECn8+AAMDAAoKBxPJQgAIAgADAAoKBxPJQgAIAgAWAAYKggZfrwCoAAAAAA==.Evagrius:BAAANQABCgIIAgAAAA==.Evenwicht:BAAANQAECgIIAgABNQAECgcIJAAGAK4VAA==.Eveokan:BAAANQAECggIDwAAAA==.Evok:BAAANQADCgEIAQAAAA==.',
Ex='Extremespeed:BAAANQADCgcIEwABNQAECgkJMgAaALkYAA==.',
Fa='Faant:BAAANQADCgUIBgABNQAECggIGQADAB8dAA==.Failshift:BAAANQAECgMIAwAAAA==.Fangy:BAAANQABCgIIAwAAAA==.Fatpats:BAAANQABCgIIAgAAAA==.',
Fe='Fenn:BAAANQAECggICAAAAA==.',
Fi='Fistantillus:BAAANQAECgIIAgAAAA==.',
Fl='Flopper:BAAANQAECgcIEAAAAA==.Fluttershy:BAAANQADCgQIBAAAAA==.',
Fo='Foxyboo:BAABNQAECn9BAAMDAAoKTxx+HwDAAgADAAoKTxx+HwDAAgAWAAQK0gmk7QC7AAAAAA==.',
Fr='Freak:BAABNQAECn8WAAIbAAgKixeOHwACAgAbAAgKixeOHwACAgAAAA==.Freakpeachh:BAAANQAECgQJBQAAAA==.',
Ga='Galerodra:BAAANQAECgEIAQAAAA==.Garalline:BAAANQADCgYICAAAAA==.',
Gn='Gnomatic:BAAANQAECgQIBgAAAA==.',
Go='Gooberetta:BAABNQAECn84AAIIAAoKrB9oIQARAwAIAAoKrB9oIQARAwAAAA==.Gooberoni:BAAANQADCgUJBQAAAA==.Gope:BAABNQAECn8iAAMDAAkK2h/GFgAbAwADAAkK2h/GFgAbAwAWAAEK7ARWPgEvAAAAAA==.Gostewpid:BAAANQAECgEIAQAAAA==.',
Gr='Gromiir:BAABNQAECn82AAMIAAoKGSN4EAAQAwAIAAoKGSN4EAAQAwAcAAEKlQ39iAA1AAAAAA==.Gromyr:BAAANQADCgcIBwABNQAECgoKNgAIABkjAA==.',
Gy='Gytha:BAAANQADCgEIAQAAAA==.',
['Gä']='Gärrus:BAAANQAECgQIBgAAAA==.',
Ha='Hashmal:BAAANQADCgEIAQAAAA==.Haurrmoany:BAAANQADCgEIAQAAAA==.',
He='Healingman:BAAANQADCgYIFQAAAA==.Hellkat:BAAANQAECggIDAAAAA==.',
Hi='Higarosa:BAAANQAECgIIAQAAAA==.Highbull:BAAANQAECggIDQABNQAECgkJGQAUAF8NAA==.',
Ho='Holiblade:BAABNQAECn8nAAIBAAgKNwjh1gBuAQABAAgKNwjh1gBuAQAAAA==.Holyhannah:BAAANQADCgIIAQAAAA==.Holyschitte:BAAANQADCgIIBAAAAA==.Holytoki:BAAANQAECgUIEAAAAA==.Holywhiskers:BAAANQAECgYIEAABNQAECgoKaQABAI4aAA==.Hooligun:BAABNQAECn8hAAIWAAkKnwhFbwA7AQAWAAkKnwhFbwA7AQAAAA==.Hoppered:BAABNQAECn8UAAIQAAgKtB1+CgBtAgAQAAgKtB1+CgBtAgABNQAECgoKPwARAMkgAA==.',
Hy='Hypérian:BAAANQAECgUIDQAAAA==.',
Ia='Ianes:BAAANQADCgYIBwAAAA==.Iantha:BAABNQAECn8cAAIIAAoKYSJBFwDqAgAIAAoKYSJBFwDqAgAAAA==.',
Ic='Icesikle:BAAANQAECgQICAAAAA==.',
Ig='Igglybuff:BAAANQAECgUICgAAAA==.',
Ij='Ijustshotyou:BAABNQAECn87AAMIAAoKXRznNQByAgAIAAoKXRznNQByAgAcAAUKGhLaMADqAAAAAA==.',
Il='Illusiongun:BAAANQAECgUIBwABNQAECgoKPwAXAHQgAA==.',
In='Indigoaura:BAAANQADCggICAAAAA==.Insaniac:BAAANQAECgUIBQAAAA==.Intervention:BAAANQABCgIIBAAAAA==.Invidious:BAAANQAECgQIBgAAAA==.',
Ir='Ironlotss:BAAANQADCggICwAAAA==.',
Iz='Izumo:BAABNQAECn8YAAIOAAgKYh3cBQBXAgAOAAgKYh3cBQBXAgAAAA==.',
Ja='Jagerbomb:BAAANQADCgUJBQAAAA==.Jardal:BAAANQADCgYIDgAAAA==.Jatswamdi:BAABNQAECn9NAAICAAoK2yL1BgA3AwACAAoK2yL1BgA3AwAAAA==.',
Je='Jehbodia:BAAANQADCggIEQAAAA==.',
Jn='Jnymango:BAAANQAECgcIDwAAAA==.',
Jo='Johnnysham:BAAANQADCggJCgABNQAECgcIDwAVAAAAAA==.Jollakeratu:BAABNQAECn9KAAIdAAoKIBJFHAChAQAdAAoKIBJFHAChAQAAAA==.Josequervo:BAAANQADCgIIAgAAAA==.',
Ju='Jugram:BAAANQAECgEIAQAAAA==.Jusmissiner:BAAANQAECgYICwAAAA==.Juut:BAABNQAECn8jAAIKAAoKsxyaIQCoAgAKAAoKsxyaIQCoAgAAAA==.',
['Jø']='Jønty:BAAANQADCgYIGAAAAA==.',
Ka='Kaelyra:BAAANQADCgYIDgAAAA==.',
Ke='Keelhorn:BAABNQAECn81AAMDAAoK9wwxcgC1AQADAAoK9wwxcgC1AQAWAAcKqQm2pgC5AAAAAA==.Kemboy:BAAANQADCgEJAQAAAA==.Kenneth:BAAANQADCgQIBAABNQAFFAkJGgAFANAMAA==.Kerubiel:BAABNQAECn8YAAQCAAcK8hipMgBMAQACAAcK8hipMgBMAQABAAQKoAkdOAHGAAAPAAQKyQbhxQCNAAABNQAECgcIJAAGAK4VAA==.Kessarah:BAABNQAECn8kAAIeAAkKcg6uIgCJAQAeAAkKcg6uIgCJAQAAAA==.',
Kh='Khadraga:BAAANQAECgQICgAAAA==.',
Ki='Kilthas:BAAANQAECgEIAQAAAA==.Kinkyhawt:BAEBNQAECn8fAAIEAAoKbhvjEgDTAgAEAAoKbhvjEgDTAgAAAA==.Kirio:BAAANQADCggIFAAAAA==.Kitsunenohi:BAABNQAECn8yAAIXAAoKcQaQRwAQAQAXAAoKcQaQRwAQAQAAAA==.Kitsunezorro:BAAANQAECgIIBQAAAA==.',
Ko='Kodiakk:BAAANQAECgIIAgAAAA==.Kornbread:BAAANQADCgEIAwAAAA==.',
Kr='Kraelith:BAAANQAECgMIBAAAAA==.Krattos:BAAANQAECgcIDAAAAA==.Krimzin:BAAANQAECgMIBAABNQAFFAgIDwAIAPkXAA==.',
Ks='Ksandra:BAABNQAECn8bAAIHAAgK1Q0RoABkAQAHAAgK1Q0RoABkAQAAAA==.Ksares:BAABNQAECn9HAAQUAAoKuyH2BADQAgAUAAoKuyH2BADQAgAfAAMKxQhBmgBxAAAbAAEK1RDddwAwAAAAAA==.',
Kw='Kwazii:BAABNQAECn8YAAMgAAcKwAvKiAB8AQAgAAcKwAvKiAB8AQAEAAYKqgb0TQDcAAABNQAECgkJGQAUAF8NAA==.',
Ky='Kyantzmi:BAAANQADCgEIAQAAAA==.Kyogre:BAAANQAECgQICQAAAA==.',
['Kë']='Këvîn:BAABNQAECn8XAAMMAAcK8gySFgBJAQAMAAcK8gySFgBJAQAHAAQKGAjkfgHFAAAAAA==.',
La='Laeflockxo:BAAANQAECgQIBgAAAA==.Laefnia:BAABNQAECn84AAQfAAoKOxjXMwBIAgAfAAoKOxjXMwBIAgAbAAMKWhY8UQDEAAAdAAQK1wuqQgCrAAAAAA==.Laraydra:BAAANQAECgYIDAABNQAECgkJIQAHACcLAA==.Laresistance:BAAANQADCgQIBAAAAA==.Lastofgoobs:BAAANQAECgYIBQAAAA==.',
Le='Leard:BAAANQAECgYIDgABNQAECgoKLAANAPQhAA==.',
Li='Lichnephilim:BAAANQADCgUIBQAAAA==.Lildarleena:BAAANQADCgYICAAAAA==.Lilis:BAAANQAECgUICQAAAA==.Lilithe:BAAANQAECggIEgABNQAECgoKPwARAMkgAA==.Liten:BAAANQADCgYIFQAAAA==.Lithndice:BAAANQADCggIFQAAAA==.Littlebev:BAABNQAECn8VAAILAAYKSgSjPQDLAAALAAYKSgSjPQDLAAAAAA==.Liz:BAAANQADCgYIEgAAAA==.',
Lo='Longshankss:BAAANQAECgEIAQAAAA==.Loonetta:BAAANQADCgEIAQAAAA==.',
Lu='Lucifers:BAAANQADCgMIAwAAAA==.Lucìen:BAAANQAECggIDAAAAA==.',
Ly='Lynch:BAAANQADCgEIAQAAAA==.',
['Lé']='Léxí:BAAANQAECggIBwAAAA==.',
Ma='Maachen:BAAANQADCgcIDAAAAA==.Maalik:BAAANQADCgQIBAABNQAECgcIJAAGAK4VAA==.Macncheeze:BAAANQABCgQIBAAAAA==.Maduin:BAAANQADCgUIBQAAAA==.Maiangel:BAAANQAECgYICwAAAA==.Maiikeru:BAAANQADCgUIBgAAAA==.Malaurray:BAABNQAECn8bAAIZAAkKqwighQBUAQAZAAkKqwighQBUAQABNQADCgEIAQAVAAAAAA==.Malhavoq:BAAANQAECgYICAAAAA==.Malkôan:BAAANQADCgYICgAAAA==.Maluin:BAAANQADCgcIGwABNQAECgoKQQAXAEQUAA==.Manlock:BAAANQADCgQIBAAAAA==.Mawea:BAAANQADCgQIBAABNQAECgkJIQAHACcLAA==.',
Mc='Mcchong:BAAANQADCgUIBQAAAA==.Mcchonky:BAAANQADCgIIAgAAAA==.Mckennah:BAABNQAECn8WAAMCAAkKvx6WDwCkAgACAAkKvx6WDwCkAgAPAAEKJA1vIQEzAAAAAA==.',
Me='Melienna:BAAANQAECgYIBgAAAA==.Melinea:BAAANQAECgMIAwAAAA==.Mereidith:BAABNQAECn86AAIHAAoK3BO+cwDIAQAHAAoK3BO+cwDIAQAAAA==.Mesohungry:BAAANQAECgUICgAAAA==.Meuria:BAAANQAECgQIBAAAAA==.',
Mi='Mikedicurt:BAAANQADCgEIAQABNQAECgoKKgAHAAYfAA==.Milele:BAAANQAECgIIBAAAAA==.Mir:BAAANQADCggICAAAAA==.Missnoms:BAAANQADCgYIEgAAAA==.Mistue:BAAANQAECgIIAgABNQAECgoKSwAQAOEgAA==.',
Mo='Moobáca:BAABNQAECn8ZAAQUAAkKXw12GAB0AQAUAAgKew12GAB0AQAdAAMKahCpVQBrAAAfAAEKiQM1mAAcAAAAAA==.Moostradamas:BAABNQAECn8cAAMGAAkKpgWBawDwAAAGAAkKpgWBawDwAAAKAAIK4wpuwgBDAAAAAA==.Morcilla:BAABNQAECn84AAQKAAoKxwoMNQBzAQAKAAoKxwoMNQBzAQAGAAgKjgN0agD1AAAaAAEKKQNe/AAcAAAAAA==.',
My='Myssts:BAAANQADCgYIFgAAAA==.',
['Mí']='Mínervä:BAAANQAECggIBAAAAA==.',
['Mî']='Mîlkmytötem:BAAANQADCgQIBAAAAA==.',
Na='Nacole:BAAANQADCgYIBgAAAA==.Nalleth:BAAANQADCgYIBgAAAA==.Nanakii:BAAANQADCgQIBAABNQAECggIGQADAB8dAA==.Narisa:BAAANQADCgEIAQAAAA==.Naturegoob:BAABNQAECn84AAMbAAoKsyHHDgDnAgAbAAoKsyHHDgDnAgAfAAkK6RSXTwCgAQAAAA==.Naughtynurse:BAABNQAECn85AAIbAAoK0hHrHwD9AQAbAAoK0hHrHwD9AQAAAA==.',
Ne='Neuma:BAABNQAECn8dAAIBAAkKvAmXAQEdAQABAAkKvAmXAQEdAQAAAA==.',
Ni='Nicfurry:BAAANQADCgEIAQAAAA==.Nightflower:BAABNQAECn8tAAIMAAoK0wiSEgB+AQAMAAoK0wiSEgB+AQAAAA==.',
No='Nostromo:BAABNQAECn8wAAIhAAoKLBXxHAD9AQAhAAoKLBXxHAD9AQAAAA==.',
Nu='Nurdraage:BAAANQADCgcIDAABNQAECgoKSQAHALwcAA==.',
Ny='Nyxserion:BAAANQAECgYIBwABNQAECgoKcAAHAEIkAA==.',
Ob='Obiejuan:BAABNQAECn9TAAIBAAoKXiMNEgAfAwABAAoKXiMNEgAfAwAAAA==.',
Od='Odbc:BAABNQAECn8xAAIfAAoKLxpqJgCgAgAfAAoKLxpqJgCgAgAAAA==.Oddball:BAABNQAECn82AAIWAAoK9CA9IAALAwAWAAoK9CA9IAALAwAAAA==.',
Ol='Olly:BAAANQAECggIDQAAAA==.',
Op='Ophiron:BAAANQADCgcICAAAAA==.',
Or='Orangecrush:BAAANQADCggIDQAAAA==.Orthiaa:BAABNQAECn8eAAIIAAcK0guovQA2AQAIAAcK0guovQA2AQAAAA==.',
Os='Osalot:BAAANQADCggIEAAAAA==.',
Pa='Paintrain:BAAANQAECgUICAAAAA==.Paladinning:BAAANQADCgUIBQAAAA==.',
Pe='Peso:BAAANQAECggICAABNQAECgkJGQAUAF8NAA==.Pez:BAABNQAECn85AAMDAAoKLxuNJgDKAgADAAoKLxuNJgDKAgAWAAEKAADtHgEAAAAAAA==.',
Ph='Phaidon:BAAANQADCggICAAAAA==.',
Pi='Pixularformd:BAAANQADCgYICQAAAA==.',
Po='Police:BAABNQAECn8cAAIgAAkKRxofRwAbAgAgAAkKRxofRwAbAgAAAA==.Polyhedroll:BAABNQAECn8kAAMYAAkKsx97CwDNAgAYAAkKsx97CwDNAgAiAAMKEgovWQCDAAABNQAFFAIIBQAVAAAAAA==.Postmalorne:BAAANQADCgEIAQAAAA==.Powerzone:BAAANQADCgIIAgAAAA==.',
Pr='Primafox:BAAANQADCgEIAQAAAA==.',
Ps='Psychoman:BAABNQAECn8nAAIEAAkKLxQFGwDBAQAEAAkKLxQFGwDBAQAAAA==.',
Pu='Punchandkick:BAAANQAECgIIBQAAAA==.Punchdeath:BAAANQADCgUIBQAAAA==.Purplerainjr:BAABNQAECn8aAAIGAAgKKg2LSwBqAQAGAAgKKg2LSwBqAQAAAA==.',
['Pó']='Póplókndótit:BAAANQAECgMIBAAAAA==.',
Qu='Quivermethis:BAAANQADCgUIBQAAAA==.',
Qx='Qx:BAAANQADCgQIBgAAAA==.',
Ra='Raakoth:BAABNQAECn8kAAMGAAcKrhVxVQBAAQAKAAYKzxUeZABiAQAGAAcKxhJxVQBAAQAAAA==.Raathe:BAAANQADCgUIEgABNQADCgYIBgAVAAAAAA==.Radge:BAABNQAECn8iAAIJAAkKWiVjBgDAAwAJAAkKWiVjBgDAAwAAAA==.Rainjar:BAAANQAECggIDgAAAA==.Rainne:BAAANQADCgQIBAAAAA==.Ralanar:BAABNQAECn8YAAIeAAUKtQ0oSQANAQAeAAUKtQ0oSQANAQABNQAECgkJIQAHACcLAA==.Raljah:BAABNQAECn8/AAQRAAoKySBFAgDHAgARAAoKySBFAgDHAgAZAAcKnhnvbwAPAgALAAUK/BSuIABrAQAAAA==.Rampart:BAAANQABCgQIBAAAAA==.',
Re='React:BAABNQAECn80AAIKAAoKKiObDABNAwAKAAoKKiObDABNAwAAAA==.Renpriest:BAAANQADCgYIDQAAAA==.',
Ri='Richpplwater:BAABNQAECn8WAAIBAAUKzw89DQEJAQABAAUKzw89DQEJAQAAAA==.Risingfallen:BAAANQADCgEIAQAAAA==.',
Ro='Rockie:BAAANQAECgcICgAAAA==.Rokk:BAAANQADCgYIBgAAAA==.Rotation:BAAANQADCgIIAgABNQAECgYIJwAOANoVAA==.Royalchaos:BAAANQAECgIIAwABNQAECgoKYQAgACAgAA==.',
Ru='Rubyraeven:BAAANQADCggIDgAAAA==.',
Ry='Ryobi:BAABNQAECn9AAAIIAAoKNRlGXwBZAgAIAAoKNRlGXwBZAgAAAA==.Ryptyde:BAABNQAECn8ZAAMWAAkKmQ06XAByAQAWAAkKmQ06XAByAQADAAgKkAuZjwAIAQAAAA==.Rysand:BAAANQAECgMIBQAAAA==.',
Sa='Saccharinê:BAAANQABCgMIAwAAAA==.Saintangel:BAAANQABCgQIAgAAAA==.Salinan:BAABNQAECn9AAAMRAAoKSh/bAgDhAgARAAgK4iLbAgDhAgAZAAgKsBiNiADRAQAAAA==.Saric:BAAANQAECgQICQAAAA==.',
Se='Selinedion:BAABNQAECn8vAAIBAAoKIxWBpACFAQABAAoKIxWBpACFAQAAAA==.Seraphiim:BAAANQAECgMIAwABNQAECgkJIwAHAEggAA==.Serdav:BAAANQAECgMIAwAAAA==.',
Sh='Shak:BAAANQADCgYIDgAAAA==.Shalai:BAACNQAFFH8FAAIXAAUKLhF8EwCiAAAXAAUKLhF8EwCiAAA1AAQKfzIAAhcACgqGI9EHABcDABcACgqGI9EHABcDAAAA.Shastix:BAAANQADCgYIBgABNQAECgcIJAAGAK4VAA==.Shellingtun:BAAANQAECggIDQABNQAECgkJGQAUAF8NAA==.Shilóh:BAAANQADCgYIBwAAAA==.Shyandrial:BAAANQADCgYIJQAAAA==.Shyness:BAAANQAECgUIBAAAAA==.',
Sk='Skaadooshh:BAAANQAECggIEwAAAA==.Sksteve:BAAANQAECgQICQAAAA==.Skychades:BAABNQAECn8tAAIIAAkK7xY2agA/AgAIAAkK7xY2agA/AgAAAA==.',
Sn='Sneakygoob:BAAANQADCgMIAwAAAA==.Snorlax:BAAANQAECgUICgAAAA==.',
So='Soulsreaver:BAAANQADCgYIBgAAAA==.Soulsrequiem:BAAANQADCggIGAAAAA==.',
Sp='Splash:BAAANQADCgQIBAAAAA==.Spookycurse:BAAANQADCgEIAQAAAA==.Spookydeath:BAABNQAECn8gAAIMAAkKNxvPCQAyAgAMAAkKNxvPCQAyAgAAAA==.Spookypriest:BAAANQADCgIIAgAAAA==.',
Sr='Srsnacksalot:BAABNQAECn82AAIBAAoKrhZNVQAuAgABAAoKrhZNVQAuAgAAAA==.',
St='Stileto:BAABNQAECn8XAAMjAAgKjQfzjwD3AAAjAAgKjQfzjwD3AAAkAAIKjwMlpQAyAAABNQAECgkJGQAUAF8NAA==.Stoneydracco:BAABNQAECn8zAAMMAAoK3g23DADsAQAMAAgKzhC3DADsAQAHAAkKUgQD6ADeAAAAAA==.Stèvè:BAAANQAECgQIBQAAAA==.',
Su='Subz:BAAANQADCgEIAQABNQAFFAgIFgAWAJ4iAA==.Sumtinwng:BAABNQAECn8aAAIBAAgKRwpivQCiAQABAAgKRwpivQCiAQAAAA==.Sunchipz:BAAANQADCgcICwAAAA==.Sungjay:BAAANQAECgcIDAAAAA==.Supervicious:BAABNQAECn8bAAIlAAoKEw7qFwCvAQAlAAoKEw7qFwCvAQAAAA==.',
Sy='Sylenne:BAAANQAECgUICAABNQAECgoKOQADAC8bAA==.Sylur:BAABNQAECn8yAAQaAAkKuRhJOQA/AgAaAAkKQhdJOQA/AgAGAAgKsREmUgBoAQAKAAQKrw+3dgB+AAAAAA==.',
['Sæ']='Sælinsonia:BAAANQAECgMIBAAAAA==.',
Ta='Tahran:BAAANQAECggICwABNQAFFAYIHQAgAGQeAA==.Tahren:BAACNQAFFH8dAAQgAAYKZB4hDgDHAQAgAAYKZB4hDgDHAQAmAAIKLwFkAwBgAAAEAAEKAADYGAAAAAA1AAQKf1wABCAACgr3IpgRADwDACAACgr3IpgRADwDAAQACQoVHCMRAEcCACYAAwoZICURABYBAAAA.Tahshock:BAAANQADCgYICwABNQAFFAYIHQAgAGQeAA==.Talanji:BAAANQADCgEIAQAAAA==.Taler:BAAANQADCgIIAgAAAA==.Talerion:BAABNQAECn8tAAMSAAoKBBZzCgDEAQASAAoKBBZzCgDEAQAhAAEKGQ/rTQA3AAAAAA==.Tanzanitia:BAAANQADCgEIAQABNQADCggIDgAVAAAAAA==.',
Te='Telline:BAAANQADCgEIAQAAAA==.Tempô:BAAANQADCggICAAAAA==.',
Th='Thatonemonk:BAAANQADCgQJBAABNQAECgQIBgAVAAAAAA==.Thereaben:BAAANQADCgcIEQAAAA==.Theyhateme:BAAANQADCgEIAQAAAA==.Thistelbear:BAABNQAECn9AAAIiAAoKAgvFIACXAQAiAAoKAgvFIACXAQAAAA==.Thorinn:BAAANQAECgcIDQAAAA==.Thornbloom:BAAANQADCggICAAAAA==.Thrallsux:BAAANQABCgYJBwAAAA==.Thraun:BAAANQAECgIIBAAAAA==.Thunderdin:BAABNQAECn9AAAMCAAoKrRq+FwA7AgACAAoK9RW+FwA7AgABAAoK0BZ/hQAdAgAAAA==.',
Ti='Tidfl:BAAANQADCgMIAwAAAA==.Tirrian:BAAANQADCggICAAAAA==.Titszilla:BAAANQAECgUICAABNQAECgkJGQAUAF8NAA==.',
To='Toki:BAAANQAECgQIDAABNQAECgUIEAAVAAAAAA==.Tokidh:BAAANQADCgYIBgAAAA==.Tokihots:BAAANQADCgQICAABNQAECgUIEAAVAAAAAA==.',
Tu='Turnip:BAABNQAECn8WAAMcAAgKtwZELAAJAQAcAAgKtwZELAAJAQAIAAIKRAMPXwE1AAABNQAECgkJGQAUAF8NAA==.',
Tw='Twamsack:BAAANQABCgUIBwAAAA==.Tweak:BAAANQAECgYIDAABNQAECgkJGQAUAF8NAA==.Tweis:BAAANQADCgYIGAAAAA==.',
Um='Umbrarogue:BAABNQAECn8vAAMkAAoK0h/+EwDcAgAkAAoKwRv+EwDcAgAjAAQKxxxBcQBWAQAAAA==.',
Va='Vaara:BAAANQABCgEIAQAAAA==.Valaa:BAAANQAECgEIAQAAAA==.Vanddrena:BAABNQAECn8kAAIeAAoKSQddNwCJAQAeAAoKSQddNwCJAQAAAA==.',
Ve='Velien:BAABNQAECn8oAAIBAAkKehG/gwAgAgABAAkKehG/gwAgAgAAAA==.Verwind:BAAANQADCgIIAgAAAA==.',
Vi='Vicotr:BAAANQADCgQIBgAAAA==.Viddysouls:BAAANQAECgcIDwAAAA==.Viscerai:BAABNQAECn9BAAIgAAoKFyRUAwAFBAAgAAoKFyRUAwAFBAAAAA==.Vite:BAAANQAECgQJBgAAAA==.',
Vo='Vonmiller:BAAANQAECgQICAAAAA==.Vorzul:BAAANQAECgUIDQAAAA==.Vozluz:BAAANQAECgUIBQABNQAECgcIJAAGAK4VAA==.',
Vr='Vryndiel:BAAANQABCgUIBQAAAA==.',
Vy='Vynllàn:BAAANQADCgYICwAAAA==.',
Wa='Walas:BAAANQADCggIEwAAAA==.Walklight:BAAANQADCgcIEQAAAA==.',
Wh='Whyjudaswhy:BAAANQAECgIIAgAAAA==.',
['Xí']='Xína:BAAANQADCggICAAAAA==.',
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
