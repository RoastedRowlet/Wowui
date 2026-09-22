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

local lookup = {'Unknown-Unknown','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Evoker-Devastation','Shaman-Elemental','DemonHunter-Devourer','Shaman-Restoration','Hunter-BeastMastery','Priest-Shadow','Paladin-Retribution','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Havoc','Priest-Holy','Mage-Arcane','Evoker-Preservation','Evoker-Augmentation','Paladin-Holy','Shaman-Enhancement','Priest-Discipline','Druid-Restoration','Druid-Guardian','DeathKnight-Frost','Monk-Brewmaster','Hunter-Marksmanship','Warrior-Protection','Druid-Balance',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aaliyshaa:BAAANQAECgEJAQAAAA==.Aanorim:BAAANQADCgMIBgAAAA==.Aaramis:BAAANQAECgYIDQAAAA==.',
Ab='Abyssal:BAAANQAECgQICAAAAA==.',
Ae='Aelanthir:BAAANQAECgQJBwAAAA==.',
Ai='Aidoffhealer:BAAANQADCgQIBQAAAA==.',
Al='Alariah:BAAANQADCgMIAwAAAQ==.Aldoraline:BAAANQADCgUICAAAAA==.Alfredstare:BAAANQADCgcIBwAAAA==.Alliancewar:BAAANQADCgEIAQAAAA==.Alordros:BAAANQADCgYJDQAAAA==.Alystair:BAAANQADCgYIBgABNQAECgIJAgABAAAAAA==.',
Am='Amadayus:BAAANQAECgcIDwAAAA==.Ambellina:BAAANQADCggIFAAAAA==.',
An='Anaria:BAAANQADCgUIBQAAAA==.Anduinz:BAAANQAECgIIAgAAAA==.',
Ar='Aranyssa:BAABNQAECoEpAAQCAAgK3hlwCQBhAQADAAYKjxg/VADRAQACAAUKQBVwCQBhAQAEAAEKyRmqWQBMAAAAAA==.Arclock:BAAANQAECgQICAAAAA==.Arconnai:BAABNQAECoEnAAIFAAkKRB8OHAARAwAFAAkKRB8OHAARAwAAAA==.Arnøld:BAAANQAECgEIAQAAAA==.',
As='Asham:BAAANQADCgYICgAAAA==.Asiago:BAAANQAECgQJBgABNQAECgYJDwABAAAAAA==.Asondra:BAAANQADCgMIAwAAAA==.Aspect:BAAANQAECgIJAgAAAA==.',
Av='Avvalethra:BAAANQAECgUJDQAAAA==.',
Az='Azdoroth:BAAANQADCgMIAwAAAA==.Azenet:BAAANQAECgQJCAABNQAFFAYIDAAGAOwXAA==.',
Ba='Babyball:BAAANQAECgIIAgAAAA==.Backshöts:BAAANQAECgUIDAAAAA==.Bainefreeze:BAAANQAECgIJAgAAAA==.Barackoshama:BAABNQAECoEVAAIHAAcKEBT1QQDuAQAHAAcKEBT1QQDuAQAAAA==.Barkimadog:BAAANQAECgMIAwAAAA==.Battle:BAAANQADCgIIAgAAAA==.Baw:BAAANQAECgYJDAAAAA==.',
Be='Bearlinwall:BAAANQADCgYJGwAAAA==.Bearmaster:BAAANQAECgIJAgAAAA==.Belacc:BAAANQADCgcJCwAAAA==.Belfiyajr:BAAANQAECgcICgAAAA==.',
Bi='Biggiebertha:BAAANQAECgYJDwAAAA==.Bighooves:BAAANQADCgIIAgAAAA==.Bigskymage:BAAANQAFFAEJAQAAAA==.Billybones:BAAANQAECgMJBQAAAA==.',
Bl='Blackholes:BAAANQAECgQIBQAAAA==.Blackwÿn:BAAANQADCggIEAABNQAECgUICQABAAAAAA==.Bladeblade:BAAANQAECgQIBAABNQAECgkJHQAFAFEZAA==.Bladedozzer:BAAANQAECgEJAgAAAA==.Blindinglite:BAAANQAECgYIEQAAAA==.Bloodhaze:BAAANQAECggIEAAAAA==.Blueorange:BAAANQAECggICAAAAA==.',
Bo='Bodizzle:BAAANQADCggJHAAAAA==.Bombil:BAAANQADCgYIDgAAAA==.Boombalatty:BAAANQAECgMJAwAAAA==.Bootychaser:BAAANQADCgUIBQAAAA==.Borestus:BAAANQADCgUJBwAAAA==.',
Br='Brchm:BAAANQADCggJEAAAAA==.Brickly:BAAANQAECgcJEAABNQAECgcIEQABAAAAAA==.Brieter:BAAANQADCgYICgABNQAECgYJDwABAAAAAA==.Broncolock:BAAANQADCggICAAAAA==.Brotheldog:BAAANQADCgUIBQAAAA==.Brutusx:BAAANQADCggJFQAAAA==.',
Bu='Bulaktheliar:BAAANQADCgcJEwAAAA==.',
Bx='Bxxberry:BAAANQADCggJGwAAAA==.',
['Bú']='Búkki:BAAANQADCgYJEAAAAA==.',
['Bü']='Bükkï:BAAANQADCgYICQAAAA==.',
Ca='Caboodles:BAAANQAECgUJBQAAAA==.Camishami:BAAANQAECgIIAgAAAA==.Candyhandz:BAAANQADCgMIAwABNQAECgEJAQABAAAAAA==.Cassander:BAAANQADCgYIBgAAAA==.',
Ce='Ceraph:BAAANQADCgQIBAAAAA==.Cexiback:BAABNQAECoEcAAIIAAkKBxboEwCEAgAIAAkKBxboEwCEAgAAAA==.',
Ch='Cheebsz:BAAANQADCgQJBQAAAA==.Cheesus:BAAANQAECgYJDwAAAA==.Chicharon:BAAANQAECgQJCQAAAA==.Chillfrost:BAAANQADCgEIAQAAAA==.Chingazossal:BAAANQAECgQJCAAAAA==.Chunggus:BAAANQABCgMJAwAAAA==.Churva:BAABNQAECoEUAAMHAAcKJAiAgQAUAQAHAAYKOwSAgQAUAQAJAAYKZAYBhgDyAAAAAA==.',
Co='Coko:BAAANQADCgYIBgABNQAECgcJGAAKALwXAA==.Coochie:BAAANQADCgcIFgAAAA==.Cosecantes:BAAANQAECgQICgAAAA==.Cowdozer:BAAANQADCgMIAwAAAA==.Cowtools:BAAANQADCgQIBAAAAA==.',
Cr='Crackjones:BAAANQAECgEIAQAAAA==.Crisgmt:BAAANQAECgQJBQAAAA==.Crism:BAAANQAECgQIBQAAAA==.Crismtg:BAAANQAECgQJCgAAAA==.Critsandgigg:BAAANQADCgIIAgAAAA==.Croaker:BAAANQADCggJCQAAAA==.Crusäderaura:BAAANQAECgQIBwAAAA==.Cryptìc:BAABNQAECoEcAAILAAkKeSAwBwBAAwALAAkKeSAwBwBAAwABNQAECgcICgABAAAAAA==.Cryptîc:BAAANQAECgcICgAAAA==.',
Da='Dabbia:BAABNQAECoEYAAQCAAkKwxxaBQD3AQACAAYK6B5aBQD3AQADAAQKGhqZhgAxAQAEAAQKMxfSJwATAQAAAA==.Dabhill:BAAANQADCgIIAgAAAA==.Daedleus:BAAANQAECgcICQAAAA==.Damented:BAAANQADCggIEQABNQAECgkJHwAJABIZAA==.Dandaris:BAAANQAECgEIAQAAAA==.Darkfugg:BAAANQADCgUICgAAAA==.Darood:BAAANQADCggIFwAAAA==.Dawnchild:BAAANQAECgIIAgAAAA==.Dazdraperma:BAAANQADCgQIBAAAAA==.',
De='Deadvocate:BAAANQAECgQICgAAAA==.Deathballz:BAAANQAECgYJEAAAAA==.Declake:BAAANQADCgMIAwAAAA==.Delthrus:BAAANQAECgQJBwABNQAECgYIDAABAAAAAA==.Demonarc:BAAANQAECgcIDgAAAA==.Detreset:BAAANQAECggIDQAAAA==.Devocate:BAAANQADCgEIAQAAAA==.Devomorph:BAAANQADCgcIBwAAAA==.',
Di='Dinguskhaan:BAAANQAECgUICAAAAA==.Dinkles:BAAANQADCgcIEAAAAA==.Dinkys:BAAANQAECgEIAQABNQAECgIJAgABAAAAAA==.Dirtytaint:BAAANQAECgQJBgABNQAECgYJEwABAAAAAA==.Disorder:BAAANQADCgcJFAAAAA==.',
Do='Doflamingo:BAAANQABCgEIAQAAAA==.Doldion:BAAANQADCgUICQAAAA==.Donkypunch:BAAANQADCgEIAQAAAA==.Donut:BAAANQAECgIIAgABNQABCgIIAgABAAAAAA==.Dotnrun:BAAANQADCgEJAQAAAA==.',
Dr='Drakarys:BAAANQADCgIIAgAAAA==.Drexybear:BAAANQAECgQJBwAAAA==.Drezbi:BAAANQAECgEIAQAAAA==.Drunkenmaste:BAAANQADCgYIBgAAAA==.',
Du='Dunbarth:BAABNQAECoEVAAIMAAcK3wcwiwBgAQAMAAcK3wcwiwBgAQAAAA==.Durzu:BAAANQAECgQICgAAAA==.Duty:BAAANQAECgIIAgAAAA==.',
['Dà']='Dàrkfate:BAAANQAECgQIBAAAAA==.',
Ea='Earthdozzer:BAAANQADCgMIAwAAAA==.',
Ec='Echohavo:BAAANQAECgMIBgAAAA==.',
Ef='Eff:BAABNQAECoEYAAMNAAgKiwt7KQCLAQANAAcKxQh7KQCLAQAOAAYKJAkCJgBFAQAAAA==.',
Eg='Eggy:BAAANQAECggIBgAAAA==.Egholom:BAABNQAECoEVAAIPAAYK7AMVQwDnAAAPAAYK7AMVQwDnAAAAAA==.',
El='Electrcfrost:BAAANQAECgcJEgAAAA==.Elkanàh:BAAANQAECgUIBwABNQAECgkJNgAQAOciAA==.Elorene:BAAANQAECgcIEwAAAA==.Elunara:BAAANQAECgYIDgABNQAECggIKQACAN4ZAA==.Elyysian:BAABNQAECoEbAAMLAAkKFxynCQARAwALAAkKFxynCQARAwAQAAMKlgNhlgCDAAAAAA==.',
Em='Emokitten:BAAANQAECgEIAQAAAA==.Emptor:BAAANQAECgIIAwAAAA==.',
Er='Ereleb:BAAANQADCgUIBQAAAA==.',
Es='Escanör:BAAANQADCgIIAgABNQAECgIJAgABAAAAAA==.Esil:BAAANQADCgUIBQAAAA==.Espresso:BAAANQADCgcIBwAAAA==.Essekk:BAABNQAECoEeAAIRAAkKmCCGIAA1AwARAAkKmCCGIAA1AwAAAA==.',
Ev='Evasivem:BAAANQADCgQIBAAAAA==.',
Ew='Ewoo:BAAANQAECgQJBAABNQAECgYIDAABAAAAAA==.',
Ex='Executtioner:BAAANQADCggJDQAAAA==.Explicit:BAAANQADCgYIBgAAAA==.',
Fa='Fadam:BAAANQAECgYJBgAAAA==.Faei:BAAANQADCgUICAAAAA==.Famjam:BAAANQAECgIIAgAAAA==.Fatpo:BAAANQAECgcIEQAAAA==.Fazy:BAAANQADCgYIEAAAAA==.',
Fe='Feldrakka:BAAANQADCgMIBAAAAA==.Felgore:BAAANQADCgQIBAAAAA==.',
Fi='Finality:BAABNQAECoEdAAIRAAkK5hrLPgDPAgARAAkK5hrLPgDPAgAAAA==.',
Fl='Flexo:BAAANQADCgUIBQAAAA==.Flirtatious:BAAANQAFFAEIAQAAAA==.',
Fo='Forsakenvoid:BAAANQADCgQIBAAAAA==.Fortknight:BAAANQADCgUIBQABNQAECgkJIQARAKEdAA==.Fourpriest:BAAANQADCggJFQAAAA==.Foô:BAAANQAECgYJEgAAAA==.',
Fr='Freehands:BAAANQADCgIIAgAAAA==.Frizza:BAAANQAECgEJAQAAAA==.Frostpaw:BAAANQABCgIIAgAAAA==.',
Fu='Fudead:BAAANQAECgMIAwAAAA==.Fugarra:BAAANQAECgQIBAAAAA==.Furyrosa:BAAANQADCgcIBwAAAA==.Fuzi:BAAANQADCgMIAwABNQADCggICAABAAAAAA==.',
Fy='Fyah:BAAANQAECgUJDQABNQAFFAQJBQAKALUNAA==.Fyaza:BAAANQADCggICAABNQAFFAQJBQAKALUNAA==.',
Ga='Gaga:BAAANQADCgIIAgAAAA==.Gargamels:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Garou:BAAANQAECgQIBQAAAA==.',
Ge='Geekyshaman:BAAANQADCggICwAAAA==.Genesis:BAAANQAECgcIAwAAAA==.Gerttie:BAAANQAECgYIDgAAAA==.',
Gg='Ggoottss:BAAANQADCgYIDQAAAA==.',
Gi='Gingdrac:BAACNQAFFIENAAISAAYKUg8WAwDqAQASAAYKUg8WAwDqAQA1AAQKgRsAAhIACQqeHscJAMwCABIACQqeHscJAMwCAAAA.',
Go='Gobsquadp:BAAANQAECgQIBQABNQAECgYIDAABAAAAAA==.',
Gr='Grassmoker:BAAANQADCggIGgAAAA==.Grek:BAAANQAECgcIDQABNQAECggIFwATAJMdAA==.Grievex:BAAANQAECgYIDwAAAA==.Grimbladez:BAAANQADCgYICgAAAA==.Grololo:BAAANQADCgcIGwAAAA==.Grozloo:BAAANQADCgIIAgAAAA==.Grumpel:BAAANQADCgYICgAAAA==.',
Ha='Habeebe:BAAANQAECgQJCAAAAA==.Hammerrhoid:BAAANQADCgEIAQAAAA==.Hanyu:BAAANQADCggICAAAAA==.Harryoneeye:BAAANQAECgEJAQAAAA==.',
Hb='Hbots:BAAANQADCggJCAAAAA==.',
He='Healthiss:BAAANQAECgYIEgAAAA==.Heelz:BAAANQADCgMJBAAAAA==.Hemostasis:BAABNQAECoEcAAMMAAkKBR54JADTAgAMAAkKBR54JADTAgAUAAEKxgG82AAvAAAAAA==.Herjä:BAAANQAECgQIDAAAAA==.Hexem:BAAANQADCgYIBgABNQADCgcIBwABAAAAAA==.Hexoon:BAAANQADCggJDgAAAA==.',
Ho='Homeslice:BAAANQAECgQJCAAAAA==.',
Hu='Huntweak:BAAANQADCggICQAAAA==.Huun:BAAANQAECgcIEgAAAA==.',
Hy='Hyasynthia:BAAANQADCgIIAgAAAA==.Hycindraeda:BAAANQADCgcJBwAAAA==.',
Ia='Iamgabrielsj:BAAANQAECgUIEgAAAA==.',
Id='Idontdps:BAAANQADCgYIBwAAAA==.',
Im='Imphetamine:BAAANQADCgEIAQAAAA==.',
Ir='Irrenadro:BAABNQAECoEdAAIMAAgKcgxKcwCjAQAMAAgKcgxKcwCjAQAAAA==.',
Is='Islandhunter:BAAANQABCgQJBAAAAA==.',
Iy='Iyahna:BAAANQAECgIIAwAAAA==.',
Ja='Jabaru:BAAANQADCgQIBAAAAA==.Jaypee:BAAANQAECgUIBwAAAA==.',
Je='Jeage:BAAANQAECgMIAwABNQAECgkJGAAHALshAA==.',
Ji='Jimboslice:BAAANQADCgQIBAAAAA==.Jimmoh:BAAANQAECgQIBQABNQAECggJFAAVANkfAA==.',
Jo='Joes:BAAANQAECgUJCQAAAA==.Jonesy:BAAANQAECgEIAQAAAA==.Jormingon:BAAANQADCgYIBwAAAA==.',
Ju='Juicygossip:BAAANQADCgYIBwAAAA==.',
Ka='Kalabar:BAAANQADCgEIAQAAAA==.Kanada:BAAANQAFFAIIAgABNQAFFAYIDwAMADUWAA==.Kanikitddon:BAAANQADCgIJAgAAAA==.Katanya:BAAANQAECgIJAgABNQAECggIKQACAN4ZAA==.',
Ke='Keetra:BAAANQAFFAIJAgAAAA==.Keiriline:BAAANQAECgMJAwAAAA==.',
Ki='Killbreed:BAAANQAECgEIAQAAAA==.Kinkster:BAAANQADCgUIBQAAAA==.',
Kl='Klix:BAAANQADCgQJBAABNQAECgEJAQABAAAAAA==.',
Kn='Knight:BAAANQAECgcJDAAAAA==.Knuggz:BAAANQAECgIIAgAAAA==.',
Kr='Kratoswrath:BAAANQAECgEIAQAAAA==.',
Ky='Kyledh:BAAANQADCggICAABNQAECgkJIwAQAGomAA==.Kylepriest:BAABNQAECoEjAAMQAAkKaiZ1AADoAwAQAAkKaiZ1AADoAwAWAAIKKSP0DwDDAAAAAA==.',
La='Lambeáu:BAAANQAECgEIAQAAAA==.Lambrusca:BAAANQADCgcIBwAAAA==.Lamda:BAAANQAECgIJAQAAAA==.Landistis:BAAANQADCgYICwAAAA==.Lanstoll:BAAANQAECggJDgAAAA==.Larcisong:BAAANQAECgUICQAAAA==.Larzoe:BAAANQADCgUIBQABNQAECgcIEgABAAAAAA==.Larzoh:BAAANQAECgcIEgAAAA==.Lateesha:BAAANQAECgUICgAAAA==.Lavac:BAAANQAECgEIAQAAAA==.',
Le='Lemonheads:BAAANQAECgUIBgAAAA==.Lethargy:BAAANQADCgUICQAAAA==.Levapally:BAAANQADCgQIBQAAAA==.',
Li='Lidorila:BAAANQADCgMJCAAAAA==.Lightguard:BAAANQAECgYIDQAAAA==.Lilplottwist:BAAANQAECgUJCAAAAA==.Lilwiz:BAAANQADCgcIDwAAAA==.Linalala:BAABNQAECoEeAAIXAAgKCSUvAwBsAwAXAAgKCSUvAwBsAwAAAA==.Linnxvx:BAAANQADCgYIBgAAAA==.Lishp:BAAANQADCgYJBgAAAA==.Literacola:BAAANQAECgQIBAAAAA==.',
Lo='Lorino:BAAANQABCggJDgAAAA==.',
Lu='Lubaduba:BAAANQADCggIDQAAAA==.Lugeya:BAAANQADCgcICQAAAA==.Lumenadiel:BAAANQAECgEJAQAAAA==.Lustnbeiber:BAAANQAECgcIEgAAAA==.Lustpls:BAAANQABCgUIBQAAAA==.Luuciferr:BAAANQAECgEJAgAAAA==.',
Ly='Lyncha:BAAANQADCgIIAgABNQAECgUJCQABAAAAAA==.Lynchà:BAAANQAECgUJCQAAAA==.',
Ma='Maakun:BAAANQAECgcIEQAAAA==.Maddevil:BAAANQADCgUJDwAAAA==.Mahoragga:BAAANQAECgMIAwAAAA==.Mahzad:BAABNQAECoEeAAMJAAkKLRzPFADfAgAJAAkKLRzPFADfAgAHAAQKqBW9hgAHAQAAAA==.Malfrun:BAAANQAECgYIDAAAAA==.Marox:BAAANQAECggIEwAAAA==.Marrøwgar:BAAANQADCggIHgAAAA==.Mathrim:BAABNQAECoEgAAMDAAkKtiQSAgC4AwADAAkKtiQSAgC4AwAEAAIKjhXERACOAAAAAA==.Matooka:BAAANQAECgMIBAAAAA==.Maynji:BAAANQADCggICAAAAA==.',
Mc='Mcthugger:BAAANQADCgYICwABNQAECgYJEgABAAAAAA==.',
Mi='Minithril:BAAANQADCgUICAAAAA==.Misspetite:BAAANQADCgYJEgAAAA==.Mitskii:BAAANQADCgMIAwAAAA==.',
Mo='Mojosmiles:BAAANQADCgQIBAAAAA==.Mojosmilês:BAAANQAECgEIAQAAAA==.Mokxî:BAAANQAECgEIAQAAAA==.Molodeath:BAAANQAECgMJBQAAAA==.Mommÿ:BAABNQAECoEdAAMQAAkKHhYnIgCBAgAQAAkKHhYnIgCBAgAWAAYKSAzFCgA9AQAAAA==.Moneymage:BAAANQAECgQIBAAAAA==.Monkgroom:BAAANQAFFAEIAQAAAA==.Montra:BAABNQAECoEcAAIYAAgKuRLjDQC3AQAYAAgKuRLjDQC3AQAAAA==.Moogaag:BAAANQADCgEIAQABNQAECgcJGAAKALwXAA==.Moolificent:BAAANQAECgIJAgAAAA==.Morgaine:BAAANQADCgUIBgAAAA==.Motorinkashi:BAAANQAECgcJDwAAAA==.',
Mu='Muddbane:BAAANQADCgQIBAABNQAECgUJEwABAAAAAA==.Muddgore:BAAANQADCggIDgABNQAECgUJEwABAAAAAA==.Muddthir:BAAANQADCgQIBAABNQAECgUJEwABAAAAAA==.Murong:BAAANQAECgEIAQAAAA==.Mustardmage:BAAANQADCgcIBwABNQAECggIHwAKAFkgAA==.',
My='Myzarei:BAAANQAECgUICwAAAA==.',
['Mø']='Møkxi:BAAANQADCggICAAAAA==.',
['Mû']='Mûdd:BAAANQAECgUJEwAAAA==.',
Ne='Nebur:BAAANQADCgUICQAAAA==.Nestaah:BAAANQADCgYJCwAAAA==.Nethender:BAAANQADCgIIAgAAAA==.Newtlid:BAAANQAECgYIBwAAAA==.',
Ni='Nirath:BAAANQAECgcJEwAAAA==.Nito:BAABNQAECoEYAAIZAAgKYxAOIgDmAQAZAAgKYxAOIgDmAQAAAA==.',
No='Nohkano:BAABNQAECoEbAAIaAAgK1yWwAQB6AwAaAAgK1yWwAQB6AwAAAA==.Nokt:BAAANQAECgIJAgAAAA==.Norrbert:BAAANQADCgcIBwAAAA==.Norriz:BAAANQAECgYIDQAAAA==.',
Nu='Numbuh:BAAANQAECgQIBgAAAA==.Nusix:BAAANQADCggICAAAAA==.',
Oa='Oakrogue:BAAANQADCggJFwAAAA==.',
Od='Odysseusxap:BAAANQADCgIIAgAAAA==.',
Ol='Oldirtytank:BAAANQADCgMIAwAAAA==.',
On='Oneshothel:BAAANQADCgEIAQAAAA==.',
Ov='Overdoze:BAAANQADCgUICAAAAA==.',
Pa='Painwhisper:BAAANQABCgQJBAAAAA==.Paladeez:BAAANQAECgYICQABNQAECgkJHAAMAAUeAA==.Pallymans:BAAANQADCgMIAwAAAA==.Pangpang:BAAANQADCgcJDAAAAA==.Pantheons:BAAANQADCgYIBAAAAA==.Parsi:BAAANQAECgYJEQAAAA==.Pattysmyth:BAAANQADCggJEAABNQADCggIDgABAAAAAA==.Paulinemaroi:BAAANQAECgUICAAAAA==.Pawtism:BAAANQAECggJCAAAAA==.',
Pe='Peleaihonua:BAAANQADCgQJBQABNQAECgEJAQABAAAAAA==.Pennywhys:BAAANQADCgYIBgAAAA==.',
Ph='Philip:BAAANQAECgQJBAAAAA==.',
Pl='Playstayshon:BAAANQADCgMIAgAAAA==.',
Po='Pofat:BAAANQADCgYIBgABNQAECgcIEQABAAAAAA==.Polis:BAAANQADCgcIBwABNQAECgQJDAABAAAAAA==.Pottyy:BAAANQABCgIIAgAAAA==.Pougadina:BAAANQAECgIIAgABNQAECgcIEQABAAAAAA==.Powjr:BAAANQADCgYIBgAAAA==.',
Pr='Primal:BAAANQADCgcJBwAAAA==.Pritee:BAAANQADCggIGgAAAA==.',
Pu='Puriel:BAAANQABCgYICQAAAA==.Putu:BAAANQADCgUIBgAAAA==.',
Py='Pyrina:BAAANQAECgQIBQABNQAECgQIBwABAAAAAA==.',
['Pä']='Pändora:BAAANQADCggIDgAAAA==.',
Ra='Rabite:BAAANQAECgYIDAAAAA==.Raelinastus:BAAANQADCgYICAAAAA==.Ragehound:BAAANQADCgEIAQAAAA==.Rah:BAAANQADCgYJCQAAAA==.Ramshunter:BAAANQAECgMIBQAAAA==.Randyvivaldi:BAAANQAECgEIAwAAAA==.Rashanda:BAAANQADCgYIDQAAAA==.Rathasas:BAAANQAECgQICwAAAA==.Ratnob:BAAANQAECgYICQAAAA==.',
Re='Reddemon:BAABNQAECoEXAAMTAAgKkx1ZAwClAgATAAgKkx1ZAwClAgAGAAEKfwb6LgAzAAAAAA==.Relda:BAAANQAECgEJAQABNQAECggJFAAVANkfAA==.Remye:BAAANQAECgcJDwAAAA==.Rennshi:BAABNQAECoEdAAIPAAkK0SWvAQDOAwAPAAkK0SWvAQDOAwAAAA==.Rezzan:BAAANQAECgMIBgAAAA==.',
Rh='Rhavetta:BAAANQADCgUIBQAAAA==.',
Ri='Riani:BAAANQAECgEIAQAAAA==.Richie:BAAANQADCgcJBwAAAA==.',
Ro='Rolanthas:BAAANQAECgQIDAAAAA==.Roldaza:BAAANQADCgcIBwAAAA==.Rolexiós:BAAANQADCgIJAgAAAA==.Roranhamer:BAAANQADCgcICQAAAA==.Rosario:BAABNQAECoEfAAMKAAgKWSARHwDBAgAKAAgKWSARHwDBAgAbAAQKLAasQgChAAAAAA==.',
Ru='Rulep:BAAANQABCgIIAgAAAA==.',
Ry='Rykû:BAAANQAECgEIAgAAAA==.Rythmatic:BAAANQAECgYJEwAAAA==.',
Sa='Sacrifice:BAAANQADCgEIAQAAAA==.Sagà:BAAANQABCgEIAQAAAA==.Sainttaint:BAAANQADCggIEwABNQADCgEIAQABAAAAAA==.Sakieri:BAAANQAECgYIDwAAAA==.Salazar:BAAANQAECgEJAQAAAA==.Saluke:BAAANQADCgUIBQAAAA==.Samwisegam:BAAANQADCgQIBAAAAA==.Sandordel:BAAANQADCgQJBgAAAA==.Sangan:BAAANQAECgUIEQAAAA==.Santaclaus:BAAANQADCggIDQAAAA==.Sappie:BAAANQADCgIIAgABNQADCgYIBwABAAAAAA==.Sarafinmae:BAAANQABCgIIAgAAAA==.',
Se='Seanoevil:BAAANQAECgIIAgAAAA==.Selathviala:BAAANQADCgMIAgAAAA==.Serazal:BAACNQAFFIEMAAIGAAYK7BfdAAAMAgAGAAYK7BfdAAAMAgA1AAQKgR4AAgYACQrXIZkDAEcDAAYACQrXIZkDAEcDAAAA.Sergregorsly:BAAANQADCgIIAgAAAA==.Serintalis:BAAANQADCgEIAQAAAA==.',
Sh='Shadowblitzx:BAAANQADCggICwAAAA==.Shakaphase:BAAANQAECgEJAQAAAA==.Shamshamz:BAAANQAECgIIAgAAAA==.Sharpshotz:BAAANQADCgcIBwAAAA==.Shenanigan:BAAANQAECgUJBQAAAA==.Shionslime:BAAANQADCgQIBAAAAA==.',
Si='Sidequest:BAAANQADCgQJBAAAAA==.Sinaga:BAAANQAECgYJEAAAAA==.Sinsear:BAAANQADCgcIBwAAAA==.Sintha:BAAANQAECgQJDQAAAA==.',
Sl='Slimedink:BAAANQADCgYICAAAAA==.',
Sm='Smarfus:BAAANQADCgQIBAABNQAECggIFwATAJMdAA==.Smolworm:BAAANQADCgUIDQAAAA==.',
So='Soulezz:BAAANQAECgUJBwAAAA==.Sourmash:BAAANQADCgYIBwAAAA==.',
St='Starfrost:BAAANQADCgIJAwAAAA==.Stingerai:BAABNQAECoEYAAIKAAcKvBcUSwASAgAKAAcKvBcUSwASAgAAAA==.Stingerjb:BAAANQAECgIIAgABNQAECgcJGAAKALwXAA==.',
Su='Sukunaa:BAAANQADCgUJDAAAAA==.Sunbeamer:BAAANQABCgYIBgAAAA==.Superdeej:BAAANQAECgYIBwABNQAECggIDAABAAAAAA==.',
Sy='Syl:BAAANQAECgIIAgAAAA==.',
['Sá']='Sága:BAAANQADCgMJAwAAAA==.',
Ta='Tarashock:BAAANQADCgUIBgAAAA==.',
Te='Teecat:BAAANQADCgQIBwAAAA==.Teehuntee:BAAANQADCgEIAQABNQAECgcIDQABAAAAAA==.Teemonk:BAAANQAECgcIDQAAAA==.Teepal:BAAANQADCgUIBQABNQAECgcIDQABAAAAAA==.Telamanus:BAAANQABCgIIAgAAAA==.Tempist:BAAANQAECgEJAgAAAA==.Teribullduce:BAABNQAECoEZAAIKAAcKgSNoJgCdAgAKAAcKgSNoJgCdAgAAAA==.Terscheckii:BAAANQADCgYIDAAAAA==.',
Th='Thalissille:BAAANQAECgEIAQAAAA==.Thingol:BAAANQABCgYIEQAAAA==.Thormor:BAAANQAECgQICAABNQAFFAYIDQASAFIPAA==.Thugger:BAAANQADCgYICQABNQAECgYJEgABAAAAAA==.Thuggerjr:BAAANQAECgYJEgAAAA==.Thundersurge:BAAANQADCggIFgAAAA==.Thænes:BAAANQAECgUICQAAAA==.Thûr:BAAANQADCgYIBgABNQAECgkJHwAJABIZAA==.',
Ti='Tigg:BAAANQAECggJBgAAAA==.Tipsout:BAABNQAECoEdAAMFAAkKURkuMwCcAgAFAAkK6BYuMwCcAgAcAAYK3xLiEgBeAQAAAA==.',
To='Toddlyv:BAAANQADCggICAABNQAECgcIDQABAAAAAA==.Totemm:BAAANQAECgMIBAAAAA==.Totomlystond:BAAANQADCgMIAwAAAA==.Tottemdrop:BAABNQAECoEfAAIJAAkKEhlXHwCYAgAJAAkKEhlXHwCYAgAAAA==.',
Tr='Trailertrash:BAAANQADCgIIAgAAAA==.Traque:BAAANQAECgIJAgAAAA==.Trealin:BAAANQADCgEJAQAAAA==.',
Ty='Tyllinar:BAAANQADCgYIBgAAAA==.Tyrgor:BAAANQADCgYJDgAAAA==.Tyrsside:BAAANQAECgQJBAAAAA==.',
Ub='Ubeenbained:BAAANQADCgEJAQAAAA==.',
Un='Unfocused:BAABNQAECoEaAAIdAAkKgBRCHwB1AgAdAAkKgBRCHwB1AgAAAA==.',
Ur='Urgmathron:BAAANQAECgIJBAAAAA==.',
Va='Vakhara:BAAANQAECgEJAQAAAA==.Valorisa:BAAANQAECgMIAwABNQAECgkJGwALABccAA==.Vansthir:BAAANQAECggIBgAAAA==.Vargko:BAAANQADCggICAAAAA==.Vaush:BAAANQADCggJGwAAAA==.',
Ve='Veigär:BAAANQAECgEIAQAAAA==.Verasuchi:BAAANQADCgYIBgAAAA==.',
Vi='Vinsmoke:BAAANQADCggJCAAAAA==.',
Vo='Voidflare:BAAANQAECgIIAgAAAA==.Voidyvoid:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Volcanoez:BAAANQADCgYIBwAAAA==.Vonrx:BAAANQAECgEJAgAAAA==.',
Vy='Vyndrian:BAAANQADCgUIBQABNQAECgcJEAABAAAAAA==.',
Wa='Wariastos:BAAANQADCgQIBAAAAA==.',
We='Welfairline:BAAANQADCggJFQAAAA==.',
Wh='Whatasham:BAAANQAECgMIAwABNQAECgcIGQAKAIEjAA==.',
['Wô']='Wôrm:BAAANQADCgUIDQAAAA==.',
Xa='Xalarys:BAAANQADCgYIDAAAAA==.Xandra:BAAANQADCgMJBQAAAA==.',
Xs='Xsslopgob:BAAANQADCgEIAQAAAA==.',
Xu='Xufoxpikmin:BAAANQADCgEIAQAAAA==.',
Ya='Yappars:BAAANQAECgUJBQAAAA==.Yassera:BAAANQAECgQJDAAAAA==.',
Ye='Yekteniya:BAAANQAECgUICgAAAA==.',
Yu='Yurio:BAAANQAECgQIBgAAAA==.Yutch:BAAANQAECgQIBQAAAA==.',
Za='Zacalkan:BAAANQADCgUIDAAAAA==.Zarik:BAAANQAECgEJAQAAAA==.',
Ze='Zeddoc:BAEANQADCgYJEQAAAA==.Zedward:BAEANQADCgMIBQABNQADCgYJEQABAAAAAA==.Zenfist:BAAANQADCgQIBAAAAA==.Zenoath:BAAANQADCggICAAAAA==.',
Zo='Zolidus:BAAANQADCggIFAAAAA==.Zosiris:BAAANQADCgQJBAAAAA==.',
Zu='Zulugangrene:BAAANQAECgUJDgAAAA==.Zun:BAAANQAECgYJDwAAAA==.',
['Åt']='Åthenä:BAAANQADCgMIAwAAAA==.',
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
