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

local lookup = {'Unknown-Unknown','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Evoker-Devastation','DemonHunter-Devourer','Priest-Shadow','Shaman-Restoration','Priest-Holy','Mage-Arcane','Hunter-BeastMastery','Evoker-Preservation','Paladin-Retribution','Paladin-Holy','Priest-Discipline','DemonHunter-Havoc','Hunter-Marksmanship',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aaliyshaa:BAAANQADCggIEgAAAA==.Aanorim:BAAANQADCgMIBgAAAA==.Aaramis:BAAANQAECgQICQAAAA==.',
Ab='Abyssal:BAAANQAECgQIBgAAAA==.',
Ae='Aelanthir:BAAANQAECgMIAwAAAA==.',
Ai='Aidoffhealer:BAAANQADCgQIBQAAAA==.',
Al='Alariah:BAAANQADCgMIAwAAAQ==.Aldoraline:BAAANQADCgUICAAAAA==.Alfredstare:BAAANQADCgcIBwAAAA==.Alliancewar:BAAANQADCgEIAQAAAA==.Alordros:BAAANQADCgUIBwAAAA==.Alystair:BAAANQADCgYIBgABNQADCggIGQABAAAAAA==.',
Am='Amadayus:BAAANQAECgYICQAAAA==.Ambellina:BAAANQADCgcIDAAAAA==.',
An='Anduinz:BAAANQAECgIIAgAAAA==.',
Ar='Aranyssa:BAABNQAECoEZAAQCAAcJvRhZBwBWAQACAAUJGxVZBwBWAQADAAQJ9RbiaAAyAQAEAAEJ/RXgUwBHAAAAAA==.Arclock:BAAANQAECgQICAAAAA==.Arconnai:BAABNQAECoEfAAIFAAkJEB47FgAWAwAFAAkJEB47FgAWAwAAAA==.Arnøld:BAAANQAECgEIAQABNQAECgIIAQABAAAAAA==.',
As='Asham:BAAANQADCgYICgAAAA==.Asiago:BAAANQAECgQIBQABNQAECgQICQABAAAAAA==.Asondra:BAAANQADCgMIAwAAAA==.Aspect:BAAANQADCggIGQAAAA==.',
Av='Avvalethra:BAAANQAECgQICAAAAA==.',
Az='Azdoroth:BAAANQADCgMIAwAAAA==.Azenet:BAAANQAECgQICAABNQAECgkJGwAGACkgAA==.',
Ba='Backshöts:BAAANQAECgQIBwAAAA==.Bainefreeze:BAAANQADCggIDgAAAA==.Barackoshama:BAAANQAECgYIDgAAAA==.Barkimadog:BAAANQAECgMIAwAAAA==.Battle:BAAANQADCgIIAgAAAA==.Baw:BAAANQAECgYICgAAAA==.',
Be='Bearlinwall:BAAANQADCgYIFQAAAA==.Bearmaster:BAAANQADCgYICAAAAA==.Belacc:BAAANQADCgcICQAAAA==.Belfiyajr:BAAANQAECgMIAQAAAA==.',
Bi='Biggiebertha:BAAANQAECgUICQAAAA==.Bighooves:BAAANQADCgIIAgAAAA==.Bigskymage:BAAANQAFFAEIAQAAAA==.Billybones:BAAANQAECgIIAgAAAA==.',
Bl='Blackholes:BAAANQADCgYIBwAAAA==.Blackwÿn:BAAANQADCggICQABNQAECgUIBQABAAAAAA==.Bladeblade:BAAANQAECgMIAwABNQAECgYIEwABAAAAAA==.Bladedozzer:BAAANQAECgEIAQAAAA==.Blindinglite:BAAANQAECgYIDgAAAA==.Bloodhaze:BAAANQAECggIDgAAAA==.Blueorange:BAAANQADCggIBgABNQADCggIBwABAAAAAA==.',
Bo='Bodizzle:BAAANQADCggIFgAAAA==.Bombil:BAAANQADCgYIDgAAAA==.Boombalatty:BAAANQAECgMIAwAAAA==.Bootychaser:BAAANQADCgUIBQAAAA==.Borestus:BAAANQADCgQIBAAAAA==.',
Br='Brchm:BAAANQADCggICAAAAA==.Brickly:BAAANQAECgQIBAABNQAECgYIDgABAAAAAA==.Brieter:BAAANQADCgYICgABNQAECgQICQABAAAAAA==.Broncolock:BAAANQADCggICAAAAA==.Brotheldog:BAAANQADCgUIBQAAAA==.Brutusx:BAAANQADCggIDgAAAA==.',
Bu='Bulaktheliar:BAAANQADCgcIDAAAAA==.',
Bx='Bxxberry:BAAANQADCgYIEwAAAA==.',
['Bú']='Búkki:BAAANQADCgYICgAAAA==.',
['Bü']='Bükkï:BAAANQADCgMIBAAAAA==.',
Ca='Caboodles:BAAANQADCgYIEQAAAA==.Camishami:BAAANQADCgcIBwAAAA==.Cassander:BAAANQADCgYIBgAAAA==.',
Ce='Cexiback:BAABNQAECoEYAAIHAAkJqBVREACWAgAHAAkJqBVREACWAgAAAA==.',
Ch='Cheebsz:BAAANQADCgQIBAAAAA==.Cheesus:BAAANQAECgQICQAAAA==.Chicharon:BAAANQAECgQIBQAAAA==.Chillfrost:BAAANQADCgEIAQAAAA==.Chingazossal:BAAANQAECgMIBAAAAA==.Chunggus:BAAANQABCgMIAwAAAA==.Churva:BAAANQAECgUIDQAAAA==.',
Co='Coko:BAAANQADCgYIBgABNQAECgYIEQABAAAAAA==.Coochie:BAAANQADCgcIEAAAAA==.Cosecantes:BAAANQAECgQICQAAAA==.Cowdozer:BAAANQADCgMIAwAAAA==.Cowtools:BAAANQADCgQIBAAAAA==.',
Cr='Crackjones:BAAANQAECgEIAQAAAA==.Crism:BAAANQAECgQIBQAAAA==.Crismtg:BAAANQAECgQIBgAAAA==.Critsandgigg:BAAANQADCgIIAgAAAA==.Croaker:BAAANQADCggICQAAAA==.Crusäderaura:BAAANQAECgQIBwAAAA==.Cryptìc:BAABNQAECoEZAAIIAAkJeSAHBQBbAwAIAAkJeSAHBQBbAwABNQAECgIIAwABAAAAAA==.Cryptîc:BAAANQAECgIIAwAAAA==.',
Da='Dabbia:BAABNQAECoEXAAQCAAkJABt2AwAOAgACAAYJ6B52AwAOAgADAAQJJBa5bAAnAQAEAAQJMxc7IwAfAQAAAA==.Dabhill:BAAANQADCgIIAgAAAA==.Daedleus:BAAANQAECgcICQAAAA==.Damented:BAAANQADCggIEQABNQAECgkJFwAJAFcXAA==.Dandaris:BAAANQAECgEIAQAAAA==.Darkfugg:BAAANQADCgUICgAAAA==.Darood:BAAANQADCggIFQAAAA==.Dawnchild:BAAANQAECgIIAgAAAA==.Dazdraperma:BAAANQADCgQIBAAAAA==.',
De='Deadvocate:BAAANQAECgQICgAAAA==.Deathballz:BAAANQAECgUICgAAAA==.Declake:BAAANQADCgMIAwAAAA==.Delthrus:BAAANQAECgMIAwABNQAECgQIBgABAAAAAA==.Demonarc:BAAANQAECgYICAAAAA==.Detreset:BAAANQAECgUICgAAAA==.Devocate:BAAANQADCgEIAQAAAA==.Devomorph:BAAANQADCgcIBwAAAA==.',
Di='Dinguskhaan:BAAANQAECgQIBAAAAA==.Dinkles:BAAANQADCgcIEAAAAA==.Dinkys:BAAANQAECgEIAQAAAA==.Dirtytaint:BAAANQAECgIIAgABNQAECgYIDgABAAAAAA==.Disorder:BAAANQADCgYIEwAAAA==.',
Do='Doflamingo:BAAANQABCgEIAQAAAA==.Doldion:BAAANQADCgUICQAAAA==.Donkypunch:BAAANQADCgEIAQAAAA==.Donut:BAAANQAECgIIAgABNQABCgIIAgABAAAAAA==.',
Dr='Drakarys:BAAANQADCgIIAgAAAA==.Drexybear:BAAANQAECgMIAwAAAA==.Drezbi:BAAANQAECgEIAQAAAA==.Drunkenmaste:BAAANQADCgYIBgAAAA==.',
Du='Dunbarth:BAAANQAECgYIDgAAAA==.Durzu:BAAANQAECgQIBgAAAA==.Duty:BAAANQAECgIIAgAAAA==.',
['Dà']='Dàrkfate:BAAANQADCggIFgAAAA==.',
Ea='Earthdozzer:BAAANQADCgMIAwAAAA==.',
Ec='Echohavo:BAAANQAECgIIAwAAAA==.',
Ef='Eff:BAAANQAECgcIEQAAAA==.',
Eg='Egholom:BAAANQAECgQIBwAAAA==.',
El='Electrcfrost:BAAANQAECgYIDQAAAA==.Elkanàh:BAAANQAECgMIAwABNQAECgkJHQAKAK0hAA==.Elorene:BAAANQAECgYIDAAAAA==.Elunara:BAAANQAECgUICgABNQAECgcIGQACAL0YAA==.Elyysian:BAAANQAECggIEgAAAA==.',
Em='Emokitten:BAAANQAECgEIAQAAAA==.Emptor:BAAANQAECgIIAwAAAA==.',
Er='Ereleb:BAAANQADCgUIBQAAAA==.',
Es='Escanör:BAAANQADCgIIAgABNQADCggIGQABAAAAAA==.Esil:BAAANQADCgUIBQAAAA==.Espresso:BAAANQADCgcIBwAAAA==.Essekk:BAABNQAECoEcAAILAAkJYCC/EgBZAwALAAkJYCC/EgBZAwAAAA==.',
Ev='Evasivem:BAAANQADCgQIBAAAAA==.',
Ew='Ewoo:BAAANQADCgYIBwABNQAECgQIBgABAAAAAA==.',
Ex='Executtioner:BAAANQADCgYICQAAAA==.Explicit:BAAANQADCgYIBgAAAA==.',
Fa='Fadam:BAAANQAECgUIBQAAAA==.Faei:BAAANQADCgMIAwAAAA==.Famjam:BAAANQAECgIIAgAAAA==.Fatpo:BAAANQAECgYIDgAAAA==.Fazy:BAAANQADCgYIEAAAAA==.',
Fe='Feldrakka:BAAANQADCgMIBAAAAA==.Felgore:BAAANQADCgQIBAAAAA==.',
Fi='Finality:BAAANQAECggIEwAAAA==.',
Fl='Flexo:BAAANQADCgUIBQAAAA==.',
Fo='Forsakenvoid:BAAANQADCgQIBAAAAA==.Fortknight:BAAANQADCgUIBQABNQAECgkJGAALAKQUAA==.Fourpriest:BAAANQADCgYIDQAAAA==.Foô:BAAANQAECgYIDQAAAA==.',
Fr='Freehands:BAAANQADCgIIAgAAAA==.Frizza:BAAANQAECgEIAQAAAA==.Frostpaw:BAAANQABCgIIAgAAAA==.',
Fu='Fudead:BAAANQAECgMIAwAAAA==.Fugarra:BAAANQADCgQIBwABNQADCgUIBQABAAAAAA==.Furyrosa:BAAANQADCgcIBwAAAA==.Fuzi:BAAANQADCgMIAwABNQADCggICAABAAAAAA==.',
Fy='Fyah:BAAANQAECgQICAABNQAECgkJHgAMADoiAA==.Fyaza:BAAANQADCggICAABNQAECgkJHgAMADoiAA==.',
Ga='Gaga:BAAANQADCgIIAgAAAA==.Gargamels:BAAANQADCgUIBQAAAA==.Garou:BAAANQAECgQIBQAAAA==.',
Ge='Geekyshaman:BAAANQADCggICwAAAA==.Genesis:BAAANQAECgcIAwAAAA==.Gerttie:BAAANQAECgYIDgAAAA==.',
Gg='Ggoottss:BAAANQADCgYIDQAAAA==.',
Gi='Gingdrac:BAACNQAFFIEMAAINAAYJUg+9AQD0AQANAAYJUg+9AQD0AQA1AAQKgRsAAg0ACQmeHisHAN4CAA0ACQmeHisHAN4CAAAA.',
Go='Gobsquadp:BAAANQAECgQIBAABNQAECgQIBgABAAAAAA==.',
Gr='Grassmoker:BAAANQADCggIFAAAAA==.Greenorange:BAAANQADCggIBwAAAA==.Grek:BAAANQAECgcIDQABNQAECgcIDgABAAAAAA==.Grievex:BAAANQAECgYICgAAAA==.Grimbladez:BAAANQADCgYICgAAAA==.Grololo:BAAANQADCgcIGwAAAA==.Grozloo:BAAANQADCgIIAgAAAA==.Grumpel:BAAANQADCgYICgAAAA==.',
Ha='Habeebe:BAAANQAECgQIBAAAAA==.Hammerrhoid:BAAANQADCgEIAQAAAA==.Hanyu:BAAANQADCggICAAAAA==.',
He='Healthiss:BAAANQAECgYIDgAAAA==.Heelz:BAAANQADCgIIAgAAAA==.Hemostasis:BAABNQAECoEbAAMOAAkJOxwdGQDYAgAOAAkJOxwdGQDYAgAPAAEJxgHgtwAyAAAAAA==.Herjä:BAAANQAECgQIDAAAAA==.Hexoon:BAAANQADCggICAAAAA==.',
Ho='Homeslice:BAAANQAECgQIBgAAAA==.',
Hu='Huntweak:BAAANQADCggICQAAAA==.Huun:BAAANQAECgYICgAAAA==.',
Hy='Hyasynthia:BAAANQADCgIIAgAAAA==.Hycindraeda:BAAANQABCgUIBQAAAA==.',
Ia='Iamgabrielsj:BAAANQAECgUICwAAAA==.',
Id='Idontdps:BAAANQADCgYIBwAAAA==.',
Ir='Irrenadro:BAAANQAECgYIEwAAAA==.',
Is='Islandhunter:BAAANQABCgQIBAAAAA==.',
Iy='Iyahna:BAAANQAECgIIAgAAAA==.',
Ja='Jabaru:BAAANQADCgQIBAAAAA==.Jaypee:BAAANQAECgIIAgAAAA==.',
Ji='Jimboslice:BAAANQADCgQIBAAAAA==.Jimmoh:BAAANQAECgQIBQABNQAECgcIEQABAAAAAA==.',
Jo='Joes:BAAANQAECgQIBAAAAA==.Jormingon:BAAANQADCgYIBwAAAA==.',
Ju='Juicygossip:BAAANQADCgYIBwAAAA==.',
Ka='Kalabar:BAAANQADCgEIAQAAAA==.Kanada:BAAANQAFFAIIAgABNQAFFAUICQAOAP0PAA==.Katanya:BAAANQAECgIIAgABNQAECgcIGQACAL0YAA==.',
Ke='Keetra:BAAANQAECgcIDgAAAA==.Keiriline:BAAANQADCggIGwAAAA==.',
Ki='Killbreed:BAAANQAECgEIAQAAAA==.Kinkster:BAAANQADCgUIBQAAAA==.',
Kn='Knight:BAAANQAECgQIBQABNQAECgYIDQABAAAAAA==.Knuggz:BAAANQADCggIDgAAAA==.',
Kr='Kratoswrath:BAAANQAECgEIAQAAAA==.',
Ky='Kyledh:BAAANQADCggICAABNQAECgkJGgAKABclAA==.Kylepriest:BAABNQAECoEaAAMKAAkJFyWFAQCpAwAKAAkJFyWFAQCpAwAQAAIJKSMKDgDGAAAAAA==.',
La='Lambeáu:BAAANQAECgEIAQAAAA==.Lambrusca:BAAANQADCgcIBwAAAA==.Lamda:BAAANQAECgEIAQAAAA==.Landistis:BAAANQADCgYICwAAAA==.Lanstoll:BAAANQAECggIBgAAAA==.Larcisong:BAAANQAECgUICQAAAA==.Larzoe:BAAANQADCgUIBQABNQAECgUICwABAAAAAA==.Larzoh:BAAANQAECgUICwAAAA==.Lateesha:BAAANQAECgUICgAAAA==.Lavac:BAAANQAECgEIAQAAAA==.',
Le='Lemonheads:BAAANQADCggIFQAAAA==.Lethargy:BAAANQADCgUICQAAAA==.Levapally:BAAANQADCgEIAQAAAA==.',
Li='Lidorila:BAAANQADCgMIBQAAAA==.Lightguard:BAAANQAECgIIAgAAAA==.Lilithiel:BAAANQAECggIAQAAAA==.Lilplottwist:BAAANQAECgIIAwAAAA==.Lilwiz:BAAANQADCgcIDwAAAA==.Linnxvx:BAAANQADCgYIBgAAAA==.Lishp:BAAANQADCgYIBgAAAA==.Literacola:BAAANQADCggIDQAAAA==.',
Lu='Lubaduba:BAAANQADCgUIBQAAAA==.Lugeya:BAAANQADCgcICQAAAA==.Lustnbeiber:BAAANQAECgYICwAAAA==.Lustpls:BAAANQABCgUIBQAAAA==.Luuciferr:BAAANQAECgEIAQAAAA==.',
Ly='Lyncha:BAAANQADCgIIAgABNQAECgMIBAABAAAAAA==.Lynchà:BAAANQAECgMIBAAAAA==.',
Ma='Maakun:BAAANQAECgQICgAAAA==.Maddevil:BAAANQADCgQICwAAAA==.Mahoragga:BAAANQAECgMIAwAAAA==.Mahzad:BAAANQAECggIEgAAAA==.Malfrun:BAAANQAECgQIBgAAAA==.Marox:BAAANQAECggICQAAAA==.Marrøwgar:BAAANQADCgcIFwAAAA==.Mathrim:BAABNQAECoEaAAMDAAkJFyOCCAApAwADAAgJFiOCCAApAwAEAAIJjhVtPQCTAAAAAA==.Matooka:BAAANQAECgEIAQAAAA==.Maynji:BAAANQADCggICAAAAA==.',
Mc='Mcthugger:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.',
Mi='Minithril:BAAANQADCgUICAAAAA==.Misspetite:BAAANQADCgYIDgAAAA==.Mitskii:BAAANQADCgMIAwAAAA==.',
Mo='Mojosmiles:BAAANQADCgQIBAAAAA==.Mojosmilês:BAAANQAECgEIAQAAAA==.Mokxî:BAAANQAECgEIAQAAAA==.Molodeath:BAAANQAECgIIAgAAAA==.Mommÿ:BAAANQAECggIEgAAAA==.Moneymage:BAAANQADCgEIAQAAAA==.Monkgroom:BAAANQAFFAEIAQAAAA==.Montra:BAAANQAECgcIEQAAAA==.Moogaag:BAAANQADCgEIAQABNQAECgYIEQABAAAAAA==.Moolificent:BAAANQADCggICQABNQAECgEIAQABAAAAAA==.Morgaine:BAAANQADCgUIBgAAAA==.Motorinkashi:BAAANQAECgQICAAAAA==.',
Mu='Muat:BAAANQADCgYIBwAAAA==.Muddbane:BAAANQADCgQIBAABNQAECgUIDgABAAAAAA==.Muddgore:BAAANQADCggIDgABNQAECgUIDgABAAAAAA==.Muddthir:BAAANQADCgQIBAABNQAECgUIDgABAAAAAA==.Murong:BAAANQAECgEIAQAAAA==.',
My='Myzarei:BAAANQAECgUICwAAAA==.',
['Mø']='Møkxi:BAAANQADCggICAAAAA==.',
['Mû']='Mûdd:BAAANQAECgUIDgAAAA==.',
Ne='Nebur:BAAANQADCgUIBQAAAA==.Nestaah:BAAANQADCgYICAAAAA==.Nethender:BAAANQADCgIIAgAAAA==.',
Ni='Nirath:BAAANQAECgYIDAAAAA==.Nito:BAAANQAECgcIDgAAAA==.',
No='Nohkano:BAAANQAECgcIEAAAAA==.Nokt:BAAANQADCgcICQABNQAECgEIAQABAAAAAA==.Norrbert:BAAANQADCgcIBwAAAA==.Norriz:BAAANQAECgUICAAAAA==.',
Nu='Numbuh:BAAANQAECgQIBgAAAA==.',
Oa='Oakrogue:BAAANQADCgYIDwAAAA==.',
Od='Odysseusxap:BAAANQADCgIIAgAAAA==.',
Ol='Oldirtytank:BAAANQADCgMIAwAAAA==.',
On='Oneshothel:BAAANQADCgEIAQAAAA==.',
Ov='Overdoze:BAAANQADCgQIBAAAAA==.',
Pa='Paladeez:BAAANQAECgMIAwABNQAECgkJGwAOADscAA==.Pallymans:BAAANQADCgMIAwAAAA==.Pangpang:BAAANQADCgcIDAAAAA==.Pantheons:BAAANQADCgEIAQAAAA==.Parsi:BAAANQAECgUICwAAAA==.Pattysmyth:BAAANQADCgYIDwABNQADCggICAABAAAAAA==.Paulinemaroi:BAAANQAECgUICAAAAA==.Pawtism:BAAANQADCgIIAgAAAA==.',
Pe='Peleaihonua:BAAANQADCgQIBQABNQADCggIEAABAAAAAA==.Pennywhys:BAAANQADCgYIBgAAAA==.',
Ph='Philip:BAAANQADCggIEAAAAA==.',
Pl='Playstayshon:BAAANQADCgMIAgAAAA==.',
Po='Polis:BAAANQADCgcIBwABNQAECgQIDAABAAAAAA==.Pottyy:BAAANQABCgIIAgAAAA==.Pougadina:BAAANQAECgIIAgABNQAECgYIDgABAAAAAA==.Powjr:BAAANQADCgYIBgAAAA==.',
Pr='Pritee:BAAANQADCggIGgAAAA==.',
Pu='Puriel:BAAANQABCgYICQAAAA==.Putu:BAAANQADCgUIBgAAAA==.',
Py='Pyrina:BAAANQAECgEIAQABNQAECgQIBwABAAAAAA==.',
['Pä']='Pändora:BAAANQADCggIDgAAAA==.',
Ra='Rabite:BAAANQAECgQIBgAAAA==.Raelinastus:BAAANQADCgYICAAAAA==.Rah:BAAANQADCgYIBgAAAA==.Ramshunter:BAAANQAECgMIBQAAAA==.Randyvivaldi:BAAANQAECgEIAwAAAA==.Rashanda:BAAANQADCgYIBwAAAA==.Rathasas:BAAANQAECgQICAAAAA==.Ratnob:BAAANQAECgMIAwAAAA==.',
Re='Reddemon:BAAANQAECgcIDgAAAA==.Relda:BAAANQADCgYIBgABNQAECgcIEQABAAAAAA==.Remye:BAAANQAECgUICAAAAA==.Rennshi:BAABNQAECoEYAAIRAAgJyCVTBABtAwARAAgJyCVTBABtAwAAAA==.Rezzan:BAAANQADCgUIBgAAAA==.',
Rh='Rhavetta:BAAANQADCgUIBQAAAA==.',
Ri='Riani:BAAANQAECgEIAQAAAA==.',
Ro='Rolanthas:BAAANQAECgIIBwAAAA==.Roranhamer:BAAANQADCgIIAgAAAA==.Rosario:BAABNQAECoEXAAMMAAcJHRyMMwArAgAMAAcJHRyMMwArAgASAAQJLAakNgCoAAAAAA==.',
Ry='Rykû:BAAANQAECgEIAgAAAA==.Rythmatic:BAAANQAECgYIDgAAAA==.',
Sa='Sacrifice:BAAANQADCgEIAQAAAA==.Sagà:BAAANQABCgEIAQAAAA==.Sainttaint:BAAANQADCggIEwABNQADCgEIAQABAAAAAA==.Sakieri:BAAANQAECgYICgAAAA==.Salazar:BAAANQADCgcIDQAAAA==.Saluke:BAAANQADCgUIBQAAAA==.Samwisegam:BAAANQADCgQIBAAAAA==.Sandordel:BAAANQADCgIIAgAAAA==.Sangan:BAAANQAECgQICwAAAA==.Santaclaus:BAAANQADCggIDQAAAA==.Sappie:BAAANQADCgIIAgABNQADCgYIBwABAAAAAA==.',
Se='Seanoevil:BAAANQAECgIIAgAAAA==.Selathviala:BAAANQADCgMIAgAAAA==.Serazal:BAABNQAECoEbAAIGAAkJKSCuAwAvAwAGAAkJKSCuAwAvAwAAAA==.Sergregorsly:BAAANQADCgIIAgAAAA==.Serintalis:BAAANQADCgEIAQAAAA==.',
Sh='Shadowblitzx:BAAANQADCggICwAAAA==.Shakaphase:BAAANQADCggIGgAAAA==.Shamshamz:BAAANQAECgIIAgAAAA==.Sharpshotz:BAAANQADCgcIBwAAAA==.Shionslime:BAAANQADCgQIBAAAAA==.',
Si='Sinaga:BAAANQAECgYICgAAAA==.Sinsear:BAAANQADCgcIBwAAAA==.Sintha:BAAANQAECgQICQAAAA==.',
Sl='Slimedink:BAAANQADCgYICAAAAA==.',
Sm='Smarfus:BAAANQADCgQIBAABNQAECgcIDgABAAAAAA==.Smolworm:BAAANQADCgUIDQAAAA==.',
So='Soulezz:BAAANQAECgMIBQAAAA==.Sourmash:BAAANQADCgYIBwAAAA==.',
St='Stingerai:BAAANQAECgYIEQAAAA==.Stingerjb:BAAANQAECgIIAgABNQAECgYIEQABAAAAAA==.',
Su='Sukunaa:BAAANQADCgUICgAAAA==.Sunbeamer:BAAANQABCgYIBgAAAA==.Superdeej:BAAANQAECgYIBwABNQAECgcICgABAAAAAA==.',
Sy='Syl:BAAANQAECgIIAgAAAA==.',
['Sá']='Sága:BAAANQADCgMIAwAAAA==.',
Ta='Tarashock:BAAANQADCgUIBgAAAA==.',
Te='Teecat:BAAANQADCgQIBwAAAA==.Teehuntee:BAAANQADCgEIAQABNQAECgcICAABAAAAAA==.Teemonk:BAAANQAECgcICAAAAA==.Teepal:BAAANQADCgUIBQABNQAECgcICAABAAAAAA==.Telamanus:BAAANQABCgIIAgAAAA==.Tempist:BAAANQAECgEIAQAAAA==.Teribullduce:BAAANQAECgYIEgAAAA==.Terscheckii:BAAANQADCgYIDAAAAA==.',
Th='Thalissille:BAAANQAECgEIAQAAAA==.Thingol:BAAANQABCgYIEQAAAA==.Thormor:BAAANQAECgQICAABNQAFFAYIDAANAFIPAA==.Thugger:BAAANQADCgYICQABNQAECgYIDAABAAAAAA==.Thuggerjr:BAAANQAECgYIDAAAAA==.Thundersurge:BAAANQADCggIFgAAAA==.Thænes:BAAANQAECgUIBQAAAA==.',
Ti='Tigg:BAAANQAECggIBgAAAA==.Tipsout:BAAANQAECgYIEwAAAA==.',
To='Toddlyv:BAAANQADCggICAABNQAECgcICAABAAAAAA==.Totemm:BAAANQAECgIIAwAAAA==.Totomlystond:BAAANQADCgMIAwAAAA==.Tottemdrop:BAABNQAECoEXAAIJAAkJVxd+FwCaAgAJAAkJVxd+FwCaAgAAAA==.',
Tr='Trailertrash:BAAANQADCgIIAgAAAA==.Traque:BAAANQADCgQIBQAAAA==.',
Ty='Tyllinar:BAAANQADCgYIBgAAAA==.Tyrgor:BAAANQADCgUICAAAAA==.Tyrsside:BAAANQADCgYIDgAAAA==.',
Ub='Ubeenbained:BAAANQADCgEIAQAAAA==.',
Un='Unfocused:BAAANQAECgcIEAAAAA==.',
Ur='Urgmathron:BAAANQAECgIIAgAAAA==.',
Va='Vakhara:BAAANQADCggIEAAAAA==.Valorisa:BAAANQAECgMIAwABNQAECggIEgABAAAAAA==.Vansthir:BAAANQAECgYIBgAAAA==.Vargko:BAAANQADCggICAAAAA==.Vaush:BAAANQADCgYIEwAAAA==.',
Ve='Veigär:BAAANQAECgEIAQAAAA==.Verasuchi:BAAANQADCgYIBgAAAA==.',
Vo='Voidflare:BAAANQADCggICAAAAA==.Voidyvoid:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Volcanoez:BAAANQADCgYIBwAAAA==.Vonrx:BAAANQAECgEIAQAAAA==.',
Vy='Vyndrian:BAAANQADCgUIBQABNQAECgQICQABAAAAAA==.',
Wa='Wariastos:BAAANQADCgQIBAAAAA==.',
We='Welfairline:BAAANQADCgcIDgAAAA==.',
Wh='Whatasham:BAAANQAECgMIAwABNQAECgYIEgABAAAAAA==.',
Wi='Winrodan:BAAANQAECgYIDwAAAA==.',
['Wô']='Wôrm:BAAANQADCgUIDQAAAA==.',
Xa='Xalarys:BAAANQADCgYIDAAAAA==.Xandra:BAAANQADCgMIAwAAAA==.',
Xs='Xsslopgob:BAAANQADCgEIAQAAAA==.',
Xu='Xufoxpikmin:BAAANQADCgEIAQAAAA==.',
Ya='Yappars:BAAANQADCgEIAQAAAA==.Yassera:BAAANQAECgQIDAAAAA==.',
Ye='Yekteniya:BAAANQAECgQIBQAAAA==.',
Yu='Yurio:BAAANQAECgMIAwAAAA==.Yutch:BAAANQAECgQIBQAAAA==.',
Za='Zacalkan:BAAANQADCgQICAAAAA==.Zarik:BAAANQADCgcIGAAAAA==.',
Ze='Zeddoc:BAEANQADCgYICwAAAA==.Zedward:BAEANQADCgMIBQABNQADCgYICwABAAAAAA==.Zenfist:BAAANQADCgQIBAAAAA==.',
Zo='Zolidus:BAAANQADCggIDAAAAA==.Zosiris:BAAANQADCgQIBAAAAA==.',
Zu='Zulugangrene:BAAANQAECgUICQAAAA==.Zun:BAAANQAECgUICQAAAA==.',
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
