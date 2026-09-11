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

local lookup = {'Unknown-Unknown','Warrior-Arms','Evoker-Devastation','Evoker-Preservation','Paladin-Retribution','Warlock-Demonology','Warlock-Destruction',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aaliyshaa:BAAANQADCggIDQAAAA==.Aanorim:BAAANQADCgMIBgAAAA==.Aaramis:BAAANQAECgQIBQAAAA==.',
Ab='Abyssal:BAAANQAECgQIBgAAAA==.',
Ae='Aelanthir:BAAANQADCggICAAAAA==.',
Ai='Aidoffhealer:BAAANQADCgQIBAAAAA==.',
Al='Alariah:BAAANQADCgMIAwAAAQ==.Aldoraline:BAAANQADCgMIAwAAAA==.Alfredstare:BAAANQADCgcIBwAAAA==.Alliancewar:BAAANQADCgEIAQAAAA==.Alordros:BAAANQADCgQIBQAAAA==.Alystair:BAAANQADCgYIBgABNQADCgcIEQABAAAAAA==.',
Am='Amadayus:BAAANQAECgMIAwAAAA==.Ambellina:BAAANQADCgYICwAAAA==.',
Ar='Aranyssa:BAAANQAECgYICgAAAA==.Arclock:BAAANQAECgQIBAAAAA==.Arconnai:BAABNQAECoEXAAICAAkJRhksGADDAgACAAkJRhksGADDAgAAAA==.',
As='Asham:BAAANQADCgYICgAAAA==.Asiago:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Asondra:BAAANQADCgMIAwAAAA==.Aspect:BAAANQADCgcIEQAAAA==.',
Av='Avvalethra:BAAANQAECgMIBAAAAA==.',
Az='Azdoroth:BAAANQADCgMIAwAAAA==.Azenet:BAAANQAECgQICAABNQAECgkJFwADAD0fAA==.',
Ba='Backshöts:BAAANQAECgIIAgAAAA==.Bainefreeze:BAAANQADCggIDgAAAA==.Barackoshama:BAAANQAECgQICAAAAA==.Barkimadog:BAAANQAECgMIAwAAAA==.Battle:BAAANQADCgIIAgAAAA==.Baw:BAAANQAECgQIBAAAAA==.',
Be='Bearlinwall:BAAANQADCgYIDwAAAA==.Bearmaster:BAAANQADCgUIBgAAAA==.Belacc:BAAANQADCgYICAAAAA==.Belfiyajr:BAAANQAECgEIAQAAAA==.',
Bi='Biggiebertha:BAAANQAECgMIBAAAAA==.Bighooves:BAAANQADCgIIAgAAAA==.Bigskymage:BAAANQADCgUIBQAAAA==.Billybones:BAAANQAECgIIAgAAAA==.',
Bl='Blackholes:BAAANQADCgYIBwAAAA==.Blackwÿn:BAAANQADCgcIBwABNQAECgUIBQABAAAAAA==.Bladeblade:BAAANQAECgIIAgABNQAECgYIDAABAAAAAA==.Blindinglite:BAAANQAECgQICAAAAA==.Bloodhaze:BAAANQAECgcIDAAAAA==.Blueorange:BAAANQADCggIBgABNQADCggICAABAAAAAA==.',
Bo='Bodizzle:BAAANQADCggIDgAAAA==.Bombil:BAAANQADCgYIDgAAAA==.Boombalatty:BAAANQADCggICAAAAA==.Bootychaser:BAAANQADCgUIBQAAAA==.Borestus:BAAANQADCgQIBAAAAA==.',
Br='Brieter:BAAANQADCgYICgABNQAECgQIBQABAAAAAA==.Broncolock:BAAANQADCggICAAAAA==.Brotheldog:BAAANQADCgUIBQAAAA==.Brutusx:BAAANQADCgYIDAAAAA==.',
Bu='Bulaktheliar:BAAANQADCgYICwAAAA==.',
Bx='Bxxberry:BAAANQADCgYIDQAAAA==.',
['Bú']='Búkki:BAAANQADCgUIBgAAAA==.',
['Bü']='Bükkï:BAAANQADCgIIAwAAAA==.',
Ca='Caboodles:BAAANQADCgYIEQAAAA==.Camishami:BAAANQADCgcIBwAAAA==.',
Ce='Cexiback:BAAANQAECgcIDwAAAA==.',
Ch='Cheesus:BAAANQAECgQIBQAAAA==.Chicharon:BAAANQAECgEIAQAAAA==.Chingazossal:BAAANQAECgEIAQAAAA==.Churva:BAAANQAECgQICAAAAA==.',
Co='Coko:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.Coochie:BAAANQADCgcIBwAAAA==.Cosecantes:BAAANQAECgMIBQAAAA==.Cowdozer:BAAANQADCgMIAwAAAA==.',
Cr='Crackjones:BAAANQADCgcICAAAAA==.Crism:BAAANQAECgEIAQAAAA==.Crismtg:BAAANQAECgQIBQAAAA==.Critsandgigg:BAAANQADCgIIAgAAAA==.Croaker:BAAANQADCggICQAAAA==.Crusäderaura:BAAANQAECgQIBgAAAA==.Cryptìc:BAAANQAECgcIDwABNQAECgIIAgABAAAAAA==.Cryptîc:BAAANQAECgIIAgAAAA==.',
Da='Dabbia:BAAANQAECgcIEAAAAA==.Dabhill:BAAANQADCgIIAgAAAA==.Daedleus:BAAANQAECgQIBAAAAA==.Damented:BAAANQADCgYICwABNQAECggIDQABAAAAAA==.Darkfugg:BAAANQADCgUICgAAAA==.Darood:BAAANQADCggIFAAAAA==.Dawnchild:BAAANQADCgYIDgAAAA==.Dazdraperma:BAAANQADCgQIBAAAAA==.',
De='Deadvocate:BAAANQAECgQICAAAAA==.Deathballz:BAAANQAECgQIBQAAAA==.Declake:BAAANQADCgMIAwAAAA==.Demonarc:BAAANQAECgIIAgAAAA==.Detreset:BAAANQAECgQIBQAAAA==.Devocate:BAAANQADCgEIAQAAAA==.Devomorph:BAAANQADCgcIBwAAAA==.Devouring:BAAANQAECgEIAQAAAA==.',
Di='Dinkles:BAAANQADCgcIEAAAAA==.Dinkys:BAAANQAECgEIAQAAAA==.Dirtytaint:BAAANQADCgQIBAABNQAECgUICAABAAAAAA==.Disorder:BAAANQADCgUIDAAAAA==.',
Do='Doflamingo:BAAANQABCgEIAQAAAA==.Doldion:BAAANQADCgUIBgAAAA==.Donkypunch:BAAANQADCgEIAQAAAA==.Donut:BAAANQAECgIIAgABNQABCgIIAgABAAAAAA==.',
Dr='Drakarys:BAAANQADCgIIAgAAAA==.Drexybear:BAAANQAECgMIAwAAAA==.Drezbi:BAAANQAECgEIAQAAAA==.Drunkenmaste:BAAANQADCgYIBgAAAA==.',
Du='Dunbarth:BAAANQAECgQICAAAAA==.Durzu:BAAANQAECgQIBAAAAA==.Duty:BAAANQAECgIIAgAAAA==.',
['Dà']='Dàrkfate:BAAANQADCggIEwAAAA==.',
Ea='Earthdozzer:BAAANQADCgMIAwAAAA==.',
Ec='Echohavo:BAAANQADCgYICwAAAA==.',
Ef='Eff:BAAANQAECgYICgAAAA==.',
Eg='Egholom:BAAANQAECgMIBAAAAA==.',
El='Electrcfrost:BAAANQAECgUIBwAAAA==.Elorene:BAAANQAECgQIBgAAAA==.Elunara:BAAANQAECgQICAABNQAECgYICgABAAAAAA==.Elyysian:BAAANQAECggIEQAAAA==.',
Em='Emokitten:BAAANQAECgEIAQAAAA==.Emptor:BAAANQAECgEIAQAAAA==.',
Er='Ereleb:BAAANQADCgUIBQAAAA==.',
Es='Esil:BAAANQADCgUIBQAAAA==.Espresso:BAAANQADCgcIBwAAAA==.Essekk:BAAANQAECgcIEgAAAA==.',
Ev='Evasivem:BAAANQADCgQIBAAAAA==.',
Ew='Ewoo:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Ex='Executtioner:BAAANQADCgMIAwAAAA==.Explicit:BAAANQADCgYIBgAAAA==.',
Fa='Fadam:BAAANQAECgUIBQAAAA==.Famjam:BAAANQADCgUIBQAAAA==.Fatpo:BAAANQAECgUICQAAAA==.Fazy:BAAANQADCgYICwAAAA==.',
Fe='Feldrakka:BAAANQADCgMIBAAAAA==.Felgore:BAAANQADCgQIBAAAAA==.',
Fi='Finality:BAAANQAECgcICwAAAA==.',
Fl='Flexo:BAAANQADCgUIBQAAAA==.',
Fo='Forsakenvoid:BAAANQADCgQIBAAAAA==.Fortknight:BAAANQADCgUIBQABNQAECgcIDwABAAAAAA==.Fourpriest:BAAANQADCgYIDQAAAA==.Foô:BAAANQAECgQIBwAAAA==.',
Fr='Freehands:BAAANQADCgIIAgAAAA==.Frizza:BAAANQADCgMIBAAAAA==.Frostpaw:BAAANQABCgIIAgAAAA==.',
Fu='Fudead:BAAANQAECgMIAwAAAA==.Fugarra:BAAANQADCgQIBwABNQADCgUIBQABAAAAAA==.Furyrosa:BAAANQADCgcIBwAAAA==.Fuzi:BAAANQADCgMIAwABNQADCggICAABAAAAAA==.',
Fy='Fyah:BAAANQAECgQIBAABNQAECggIEgABAAAAAA==.Fyaza:BAAANQADCggICAABNQAECggIEgABAAAAAA==.',
Ga='Gaga:BAAANQADCgIIAgAAAA==.Gargamels:BAAANQADCgUIBQAAAA==.Garou:BAAANQAECgEIAQAAAA==.',
Ge='Geekyshaman:BAAANQADCggICwAAAA==.Gerttie:BAAANQAECgYICAAAAA==.',
Gg='Ggoottss:BAAANQADCgYIDQAAAA==.',
Gi='Gingdrac:BAACNQAFFIEIAAIEAAYJDQzwAAD7AQAEAAYJDQzwAAD7AQA1AAQKgRcAAgQACQmeHtMEAO4CAAQACQmeHtMEAO4CAAAA.',
Go='Gobsquadp:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Goldorange:BAAANQADCggICAAAAA==.',
Gr='Grassmoker:BAAANQADCgYIDAAAAA==.Greenorange:BAAANQADCggIBwABNQADCggICAABAAAAAA==.Grek:BAAANQAECgYICgAAAA==.Grievex:BAAANQAECgQIBAAAAA==.Grimbladez:BAAANQADCgYICgAAAA==.Grololo:BAAANQADCgcIGwAAAA==.Grozloo:BAAANQADCgIIAgAAAA==.Grumpel:BAAANQADCgMIBAAAAA==.',
Ha='Hanyu:BAAANQADCggICAAAAA==.',
He='Healthiss:BAAANQAECgUICQAAAA==.Hemostasis:BAAANQAECgcIEQAAAA==.Herjä:BAAANQAECgQICAAAAA==.',
Ho='Homeslice:BAAANQAECgIIAgAAAA==.',
Hu='Huntweak:BAAANQADCggICQAAAA==.Huun:BAAANQAECgQIBAAAAA==.',
Hy='Hyasynthia:BAAANQADCgIIAgAAAA==.Hycindraeda:BAAANQABCgUIBQAAAA==.',
Ia='Iamgabrielsj:BAAANQAECgUIBQAAAA==.',
Id='Idontdps:BAAANQADCgYIBgAAAA==.',
Ir='Irrenadro:BAAANQAECgUICwAAAA==.',
Is='Islandhunter:BAAANQABCgQIBAAAAA==.',
Iy='Iyahna:BAAANQADCgUIBQAAAA==.',
Ja='Jabaru:BAAANQADCgQIBAAAAA==.Jaypee:BAAANQADCgQIBAAAAA==.',
Ji='Jimboslice:BAAANQADCgQIBAAAAA==.Jimmoh:BAAANQAECgMIAwABNQAECgcICwABAAAAAA==.',
Jo='Joes:BAAANQADCggIEAAAAA==.Jormingon:BAAANQADCgYIBwAAAA==.',
Ju='Juicygossip:BAAANQADCgEIAQAAAA==.',
Ka='Kalabar:BAAANQADCgEIAQAAAA==.Kanada:BAAANQAFFAIIAgABNQAECgkJGAAFAL0iAA==.',
Ke='Keetra:BAAANQAECgcIDQAAAA==.Keiriline:BAAANQADCggIEwAAAA==.',
Ki='Killbreed:BAAANQAECgEIAQAAAA==.Kinkster:BAAANQADCgUIBQAAAA==.',
Kn='Knight:BAAANQAECgEIAQABNQAECgYIBwABAAAAAA==.Knuggz:BAAANQADCggIDgAAAA==.',
Kr='Kratoswrath:BAAANQAECgEIAQAAAA==.',
Ky='Kyledh:BAAANQADCggICAABNQAFFAEIAQABAAAAAA==.Kylepriest:BAAANQAFFAEIAQAAAA==.',
La='Lambrusca:BAAANQADCgcIBwAAAA==.Landistis:BAAANQADCgUIBQAAAA==.Larcisong:BAAANQAECgQIBAAAAA==.Larzoe:BAAANQADCgUIBQABNQAECgQIBgABAAAAAA==.Larzoh:BAAANQAECgQIBgAAAA==.Lateesha:BAAANQAECgUICgAAAA==.Lavac:BAAANQAECgEIAQAAAA==.',
Le='Lemonheads:BAAANQADCggIDgAAAA==.Lethargy:BAAANQADCgQIBAAAAA==.Levapally:BAAANQADCgEIAQAAAA==.',
Li='Lidorila:BAAANQADCgIIAgAAAA==.Lightguard:BAAANQAECgIIAgAAAA==.Lilithiel:BAAANQAECggIAQAAAA==.Lilplottwist:BAAANQAECgEIAQAAAA==.Lilwiz:BAAANQADCgcICQAAAA==.Linnxvx:BAAANQADCgYIBgAAAA==.Lishp:BAAANQADCgYIBgAAAA==.Literacola:BAAANQADCggIDQAAAA==.',
Lu='Lugeya:BAAANQADCgcIBwAAAA==.Lustnbeiber:BAAANQAECgQIBQAAAA==.',
Ly='Lyncha:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Lynchà:BAAANQAECgEIAQAAAA==.',
Ma='Maakun:BAAANQADCgQIBAAAAA==.Maddevil:BAAANQADCgQICwAAAA==.Mahoragga:BAAANQAECgMIAwAAAA==.Mahzad:BAAANQAECggIDQAAAA==.Malfrun:BAAANQAECgIIAgAAAA==.Marox:BAAANQAECgQIAwAAAA==.Marrøwgar:BAAANQADCgcIEAAAAA==.Mathrim:BAABNQAECoESAAMGAAgJmCCUCgDDAgAGAAcJPCCUCgDDAgAHAAIJjhWwNACaAAAAAA==.Matooka:BAAANQADCggIDgAAAA==.Maynji:BAAANQADCggICAAAAA==.',
Mc='Mcthugger:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.',
Mi='Minithril:BAAANQADCgUICAAAAA==.Misspetite:BAAANQADCgUICAAAAA==.Mitskii:BAAANQADCgMIAwAAAA==.',
Mo='Mojosmiles:BAAANQADCgQIBAAAAA==.Molodeath:BAAANQADCgcIDwAAAA==.Mommÿ:BAAANQAECgcICQAAAA==.Moneymage:BAAANQADCgEIAQAAAA==.Monkgroom:BAAANQAECgMIAwAAAA==.Montra:BAAANQAECgYICgAAAA==.Moogaag:BAAANQADCgEIAQABNQAECgYICwABAAAAAA==.Morgaine:BAAANQADCgUIBgAAAA==.Motorinkashi:BAAANQAECgQIBQAAAA==.',
Mu='Muat:BAAANQADCgEIAQAAAA==.Muddbane:BAAANQADCgQIBAABNQAECgQICQABAAAAAA==.Muddgore:BAAANQADCgYIBgABNQAECgQICQABAAAAAA==.',
My='Myzarei:BAAANQAECgUIBwAAAA==.',
['Mø']='Møkxi:BAAANQADCggICAAAAA==.',
['Mû']='Mûdd:BAAANQAECgQICQAAAA==.',
Ne='Nestaah:BAAANQADCgIIAgAAAA==.Nethender:BAAANQADCgIIAgAAAA==.',
Ni='Nirath:BAAANQAECgQIBgAAAA==.Nito:BAAANQAECgUIBwAAAA==.',
No='Nohkano:BAAANQAECgYICwAAAA==.Nokt:BAAANQADCgQIBAABNQADCgYICwABAAAAAA==.Norriz:BAAANQAECgMIAwAAAA==.',
Nu='Numbuh:BAAANQAECgQIBAAAAA==.',
Oa='Oakrogue:BAAANQADCgYICQAAAA==.',
Od='Odysseusxap:BAAANQADCgIIAgAAAA==.',
On='Oneshothel:BAAANQADCgEIAQAAAA==.',
Pa='Paladeez:BAAANQADCgUIBwABNQAECgcIEQABAAAAAA==.Pallymans:BAAANQADCgMIAwAAAA==.Pangpang:BAAANQADCgYICwAAAA==.Parsi:BAAANQAECgQIBgAAAA==.Pattysmyth:BAAANQADCgYIDAABNQAECgUICgABAAAAAA==.Paulinemaroi:BAAANQAECgMIAwAAAA==.Pawtism:BAAANQADCgIIAgAAAA==.',
Pe='Peleaihonua:BAAANQADCgQIBQABNQADCgUICAABAAAAAA==.Pennywhys:BAAANQADCgYIBgAAAA==.',
Ph='Philip:BAAANQADCggIEAAAAA==.',
Pl='Playstayshon:BAAANQADCgMIAgAAAA==.',
Po='Polis:BAAANQADCgcIBwABNQAECgQICAABAAAAAA==.Pottyy:BAAANQABCgIIAgAAAA==.Powjr:BAAANQADCgYIBgAAAA==.',
Pr='Pritee:BAAANQADCggIGgAAAA==.',
Pu='Puriel:BAAANQABCgYICQAAAA==.Putu:BAAANQADCgUIBgAAAA==.',
Py='Pyrina:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.',
['Pä']='Pändora:BAAANQADCggICAAAAA==.',
Ra='Rabite:BAAANQAECgIIAgAAAA==.Raelinastus:BAAANQADCgYICAAAAA==.Rah:BAAANQADCgYIBgAAAA==.Ramshunter:BAAANQAECgMIBQAAAA==.Randyvivaldi:BAAANQAECgEIAgAAAA==.Rashanda:BAAANQADCgIIAgAAAA==.Rathasas:BAAANQAECgIIBAAAAA==.Ratnob:BAAANQAECgEIAQAAAA==.',
Re='Reddemon:BAAANQAECgYIBwABNQAECgYICgABAAAAAA==.Relda:BAAANQADCgYIBgABNQAECgcICwABAAAAAA==.Remye:BAAANQAECgMIAwAAAA==.Rennshi:BAAANQAECgcIDQAAAA==.',
Rh='Rhavetta:BAAANQADCgUIBQAAAA==.',
Ri='Riani:BAAANQAECgEIAQAAAA==.',
Ro='Rolanthas:BAAANQAECgIIBQAAAA==.Rosario:BAAANQAECgUIDgAAAA==.',
Ry='Rythmatic:BAAANQAECgUICAAAAA==.',
Sa='Sacrifice:BAAANQADCgEIAQAAAA==.Sagà:BAAANQABCgEIAQAAAA==.Sainttaint:BAAANQADCgcIDAABNQADCgEIAQABAAAAAA==.Sakieri:BAAANQAECgQIBAAAAA==.Salazar:BAAANQADCgYIBgAAAA==.Saluke:BAAANQADCgUIBQAAAA==.Samwisegam:BAAANQADCgQIBAAAAA==.Sangan:BAAANQAECgQIBwAAAA==.Santaclaus:BAAANQADCggIDQAAAA==.Sappie:BAAANQADCgIIAgABNQADCgYIBwABAAAAAA==.',
Se='Seanoevil:BAAANQAECgIIAgAAAA==.Selathviala:BAAANQADCgMIAgAAAA==.Serazal:BAABNQAECoEXAAIDAAkJPR8IAwAzAwADAAkJPR8IAwAzAwAAAA==.Sergregorsly:BAAANQADCgIIAgAAAA==.Serintalis:BAAANQADCgEIAQAAAA==.',
Sh='Shadowblitzx:BAAANQADCggICwAAAA==.Shakaphase:BAAANQADCgcIEgAAAA==.Shamshamz:BAAANQAECgIIAgAAAA==.Shionslime:BAAANQADCgQIBAAAAA==.',
Si='Sinaga:BAAANQAECgQIBQAAAA==.Sinsear:BAAANQADCgcIBwAAAA==.Sintha:BAAANQAECgQIBAAAAA==.',
Sl='Slimedink:BAAANQADCgYICAAAAA==.',
Sm='Smolworm:BAAANQADCgUIDQAAAA==.',
So='Soulezz:BAAANQAECgEIAgAAAA==.Sourmash:BAAANQADCgYIBwAAAA==.',
St='Steppedon:BAAANQADCgYICwAAAA==.Stingerai:BAAANQAECgYICwAAAA==.Stingerjb:BAAANQAECgIIAgABNQAECgYICwABAAAAAA==.',
Su='Sukunaa:BAAANQADCgUICgAAAA==.Sunbeamer:BAAANQABCgUIBgAAAA==.Superdeej:BAAANQAECgYIBgAAAA==.',
Sy='Syl:BAAANQADCggIBwAAAA==.',
Ta='Tarashock:BAAANQADCgUIBgAAAA==.',
Te='Teecat:BAAANQADCgQIBwAAAA==.Teehuntee:BAAANQADCgEIAQABNQAECgIIAwABAAAAAA==.Teemonk:BAAANQAECgIIAwAAAA==.Teepal:BAAANQADCgUIBQABNQAECgIIAwABAAAAAA==.Telamanus:BAAANQABCgIIAgAAAA==.Tempist:BAAANQADCgcIEQAAAA==.Teribullduce:BAAANQAECgUIDgAAAA==.Terscheckii:BAAANQADCgYIDAAAAA==.',
Th='Thingol:BAAANQABCgYIDQAAAA==.Thormor:BAAANQAECgQICAABNQAFFAYICAAEAA0MAA==.Thugger:BAAANQADCgYICAABNQAECgUIBgABAAAAAA==.Thuggerjr:BAAANQAECgUIBgAAAA==.Thundersurge:BAAANQADCggIEgAAAA==.Thænes:BAAANQAECgUIBQAAAA==.',
Ti='Tipsout:BAAANQAECgYIDAAAAA==.',
To='Totemm:BAAANQAECgIIAwAAAA==.Totomlystond:BAAANQADCgMIAwAAAA==.Tottemdrop:BAAANQAECggIDQAAAA==.',
Tr='Trailertrash:BAAANQADCgIIAgAAAA==.',
Ty='Tyllinar:BAAANQADCgYIBgAAAA==.Tyrgor:BAAANQADCgMIAwAAAA==.Tyrsside:BAAANQADCgYICgAAAA==.',
Ub='Ubeenbained:BAAANQADCgEIAQAAAA==.',
Un='Unfocused:BAAANQAECgQICQAAAA==.',
Ur='Urgmathron:BAAANQADCgUICgAAAA==.',
Va='Vakhara:BAAANQADCgUICAAAAA==.Valorisa:BAAANQAECgMIAwABNQAECggIEQABAAAAAA==.Vansthir:BAAANQAECgYIBgAAAA==.Vargko:BAAANQADCggICAAAAA==.Vaush:BAAANQADCgYIDQAAAA==.',
Ve='Verasuchi:BAAANQADCgYIBgAAAA==.',
Vo='Voidyvoid:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Volcanoez:BAAANQADCgEIAQAAAA==.Vonrx:BAAANQADCgYIBwAAAA==.',
Vy='Vyndrian:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.',
Wa='Wariastos:BAAANQADCgQIBAAAAA==.',
We='Welfairline:BAAANQADCgYICQAAAA==.',
Wi='Winrodan:BAAANQAECgQICQAAAA==.',
['Wô']='Wôrm:BAAANQADCgUIDQAAAA==.',
Xa='Xalarys:BAAANQADCgYIBgAAAA==.Xandra:BAAANQADCgMIAwAAAA==.',
Xs='Xsslopgob:BAAANQADCgEIAQAAAA==.',
Xu='Xufoxpikmin:BAAANQADCgEIAQAAAA==.',
Ya='Yappars:BAAANQADCgEIAQAAAA==.Yassera:BAAANQAECgQICAAAAA==.',
Ye='Yekteniya:BAAANQAECgMIAwAAAA==.',
Yu='Yurio:BAAANQADCgcIEgAAAA==.Yutch:BAAANQAECgQIBQAAAA==.',
Za='Zacalkan:BAAANQADCgIIBAAAAA==.Zarik:BAAANQADCgYIEQAAAA==.',
Ze='Zeddoc:BAEANQADCgUIBQAAAA==.Zedward:BAEANQADCgMIBQABNQADCgUIBQABAAAAAA==.Zenfist:BAAANQADCgUIBAAAAA==.',
Zo='Zolidus:BAAANQADCgQIBAAAAA==.Zosiris:BAAANQADCgQIBAAAAA==.',
Zu='Zulugangrene:BAAANQAECgQIBAAAAA==.Zun:BAAANQAECgQIBAAAAA==.',
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
