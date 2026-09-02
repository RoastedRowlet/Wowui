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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aaliyshaa:BAAANQADCgUIBgAAAA==.Aanorim:BAAANQADCgMIBgAAAA==.Aaramis:BAAANQAECgIIAgAAAA==.',
Ab='Abyssal:BAAANQAECgQIBgAAAA==.',
Ae='Aelanthir:BAAANQADCgYIBgAAAA==.',
Al='Alariah:BAAANQADCgMIAwAAAQ==.Aldoraline:BAAANQADCgMIAwAAAA==.Alfredstare:BAAANQADCgcIBwAAAA==.Alliancewar:BAAANQADCgEIAQAAAA==.Alordros:BAAANQADCgIIAgAAAA==.Alystair:BAAANQADCgYIBgABNQADCgYICgABAAAAAA==.',
Am='Amadayus:BAAANQAECgIIAgAAAA==.Ambellina:BAAANQADCgYICwAAAA==.',
Ar='Aranyssa:BAAANQAECgEIAQAAAA==.Arclock:BAAANQADCgUIBQAAAA==.Arconnai:BAAANQAECggIDQAAAA==.',
As='Asham:BAAANQADCgYICgAAAA==.Asiago:BAAANQADCgYIBgABNQADCggIDgABAAAAAA==.Asondra:BAAANQADCgMIAwAAAA==.Aspect:BAAANQADCgYICgAAAA==.',
Av='Avvalethra:BAAANQAECgEIAQAAAA==.',
Az='Azdoroth:BAAANQADCgMIAwAAAA==.Azenet:BAAANQAECgQICAABNQAECggIDwABAAAAAA==.',
Ba='Bainefreeze:BAAANQADCggIDgAAAA==.Barackoshama:BAAANQAECgMIBAAAAA==.Barkimadog:BAAANQAECgMIAwAAAA==.Battle:BAAANQADCgIIAgAAAA==.Baw:BAAANQAECgIIAgAAAA==.',
Be='Bearlinwall:BAAANQADCgUICQAAAA==.Bearmaster:BAAANQADCgQIBAAAAA==.',
Bi='Biggiebertha:BAAANQAECgEIAQAAAA==.Bighooves:BAAANQADCgIIAgAAAA==.Bigskymage:BAAANQADCgUIBQAAAA==.Billybones:BAAANQADCgYIBgAAAA==.',
Bl='Blackholes:BAAANQADCgYIBwAAAA==.Bladeblade:BAAANQADCgcIDAABNQAECgIIAgABAAAAAA==.Blindinglite:BAAANQAECgMIBAAAAA==.Bloodhaze:BAAANQAECgUIBwAAAA==.',
Bo='Bodizzle:BAAANQADCgYIBgAAAA==.Bombil:BAAANQADCgYICgAAAA==.Bootychaser:BAAANQADCgUIBQAAAA==.Borestus:BAAANQADCgQIBAAAAA==.',
Br='Brieter:BAAANQADCgYICgABNQADCggIDgABAAAAAA==.Broncolock:BAAANQADCggICAAAAA==.Brotheldog:BAAANQADCgUIBQAAAA==.Brutusx:BAAANQADCgYIBgAAAA==.',
Bu='Bulaktheliar:BAAANQADCgIIAgAAAA==.',
Bx='Bxxberry:BAAANQADCgUIBwAAAA==.',
Ca='Caboodles:BAAANQADCgYICwAAAA==.',
Ce='Cexiback:BAAANQAECgUICAAAAA==.',
Ch='Cheesus:BAAANQADCggIDgAAAA==.Chicharon:BAAANQADCgcIDgAAAA==.Chingazossal:BAAANQADCgYICwAAAA==.Churva:BAAANQAECgQIBAAAAA==.',
Co='Coko:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Cosecantes:BAAANQAECgIIAgAAAA==.Cowdozer:BAAANQADCgMIAwAAAA==.',
Cr='Crackjones:BAAANQADCgYIBwAAAA==.Crismtg:BAAANQAECgEIAQAAAA==.Croaker:BAAANQADCgIIAgAAAA==.Crusäderaura:BAAANQAECgMIAwAAAA==.Cryptìc:BAAANQAECgQICAAAAA==.',
Da='Dabbia:BAAANQAECgUICQAAAA==.Dabhill:BAAANQADCgIIAgAAAA==.Daedleus:BAAANQADCggIEAAAAA==.Damented:BAAANQADCgQIBwABNQAECgUIBQABAAAAAA==.Darkfugg:BAAANQADCgQIBQAAAA==.Darood:BAAANQADCggIDgAAAA==.Dawnchild:BAAANQADCgUICAAAAA==.',
De='Deadvocate:BAAANQAECgQIBAAAAA==.Deathballz:BAAANQAECgEIAQAAAA==.Declake:BAAANQADCgMIAwAAAA==.Detreset:BAAANQAECgEIAQAAAA==.Devocate:BAAANQADCgEIAQAAAA==.',
Di='Dinkles:BAAANQADCgUICQAAAA==.Dinkys:BAAANQADCgcIEgAAAA==.Dirtytaint:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Disorder:BAAANQADCgQIBwAAAA==.',
Do='Doflamingo:BAAANQABCgEIAQAAAA==.Donkypunch:BAAANQADCgEIAQAAAA==.Donut:BAAANQADCgUICAABNQABCgIIAgABAAAAAA==.',
Dr='Drakarys:BAAANQADCgIIAgAAAA==.Drexybear:BAAANQADCggIDgAAAA==.Drezbi:BAAANQADCgUIBQAAAA==.',
Du='Dunbarth:BAAANQAECgQIBAAAAA==.Durzu:BAAANQAECgEIAQAAAA==.Duty:BAAANQAECgIIAgAAAA==.',
['Dà']='Dàrkfate:BAAANQADCgYICwAAAA==.',
Ea='Earthdozzer:BAAANQADCgMIAwAAAA==.',
Ec='Echohavo:BAAANQADCgUICQAAAA==.',
Ef='Eff:BAAANQAECgQIBAAAAA==.',
El='Electrcfrost:BAAANQAECgIIAgAAAA==.Elorene:BAAANQAECgIIAgAAAA==.Elunara:BAAANQAECgQICAABNQAECgEIAQABAAAAAA==.Elyysian:BAAANQAECgcICgAAAA==.',
Em='Emptor:BAAANQADCgIIAgAAAA==.',
Er='Ereleb:BAAANQADCgUIBQAAAA==.',
Es='Esil:BAAANQADCgUIBQAAAA==.Espresso:BAAANQADCgcIBwAAAA==.Essekk:BAAANQAECgcICwAAAA==.',
Ev='Evasivem:BAAANQADCgQIBAAAAA==.',
Ew='Ewoo:BAAANQADCgYIBgABNQADCgcIDQABAAAAAA==.',
Ex='Executtioner:BAAANQADCgMIAwAAAA==.',
Fa='Fadam:BAAANQADCggICAAAAA==.Famjam:BAAANQADCgUIBQAAAA==.Fatpo:BAAANQAECgQIBAAAAA==.Fazy:BAAANQADCgYIBgAAAA==.',
Fe='Feldrakka:BAAANQADCgMIBAAAAA==.Felgore:BAAANQADCgQIBAAAAA==.',
Fi='Finality:BAAANQAECgQIBAAAAA==.',
Fl='Flexo:BAAANQADCgUIBQAAAA==.',
Fo='Fortknight:BAAANQADCgUIBQABNQAECgcICwABAAAAAA==.Fourpriest:BAAANQADCgYIBwAAAA==.Foô:BAAANQAECgQIBQAAAA==.',
Fr='Freehands:BAAANQADCgIIAgAAAA==.Frizza:BAAANQADCgMIBAAAAA==.Frostpaw:BAAANQABCgIIAgAAAA==.',
Fu='Fudead:BAAANQADCgUIBwAAAA==.Fugarra:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.',
Fy='Fyaza:BAAANQADCggICAABNQAECgcICgABAAAAAA==.',
Ga='Gargamels:BAAANQADCgUIBQAAAA==.Garou:BAAANQADCgcIDQAAAA==.',
Ge='Geekyshaman:BAAANQADCgMIAwAAAA==.Gerttie:BAAANQAECgIIAgAAAA==.',
Gg='Ggoottss:BAAANQADCgYIBwAAAA==.',
Gi='Gingdrac:BAAANQAFFAIIAgAAAA==.',
Go='Gobsquadp:BAAANQADCgYIBgABNQADCgcIDQABAAAAAA==.',
Gr='Grassmoker:BAAANQADCgYIBgAAAA==.Grek:BAAANQAECgQIBAAAAA==.Grievex:BAAANQADCggIDwAAAA==.Grimbladez:BAAANQADCgYICgAAAA==.Grololo:BAAANQADCgYIFAAAAA==.Grozloo:BAAANQADCgIIAgAAAA==.Grumpel:BAAANQADCgMIBAAAAA==.',
Ha='Hanyu:BAAANQADCggICAAAAA==.',
He='Healthiss:BAAANQAECgMIBAAAAA==.Hemostasis:BAAANQAECgYICgAAAA==.Herjä:BAAANQAECgQIBAAAAA==.',
Ho='Homeslice:BAAANQADCgMIAwAAAA==.',
Hu='Huntweak:BAAANQADCgEIAQAAAA==.Huun:BAAANQAECgEIAQAAAA==.',
Hy='Hyasynthia:BAAANQADCgIIAgAAAA==.',
Ia='Iamgabrielsj:BAAANQAECgEIAQAAAA==.',
Ir='Irrenadro:BAAANQAECgMIAwAAAA==.',
Iy='Iyahna:BAAANQADCgUIBQAAAA==.',
Ja='Jabaru:BAAANQADCgQIBAAAAA==.',
Ji='Jimboslice:BAAANQADCgQIBAAAAA==.Jimmoh:BAAANQADCgMIAwABNQAECgQIBAABAAAAAA==.',
Jo='Joes:BAAANQADCggICAAAAA==.Jormingon:BAAANQADCgYIBgAAAA==.',
Ju='Juicygossip:BAAANQADCgEIAQAAAA==.',
Ka='Kalabar:BAAANQADCgEIAQAAAA==.Kanada:BAAANQAFFAIIAgAAAA==.',
Ke='Keetra:BAAANQAECgUIBgAAAA==.Keiriline:BAAANQADCgYICwAAAA==.',
Ki='Killbreed:BAAANQAECgEIAQAAAA==.Kinkster:BAAANQADCgUIBQAAAA==.',
Kn='Knight:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Knuggz:BAAANQADCggIDgAAAA==.',
Kr='Kratoswrath:BAAANQADCgYIBgAAAA==.',
Ky='Kyledh:BAAANQADCggICAABNQAECgcIBwABAAAAAA==.Kylepriest:BAAANQAECgcIBwAAAA==.',
La='Lambrusca:BAAANQADCgcIBwAAAA==.Landistis:BAAANQADCgUIBQAAAA==.Larzoh:BAAANQAECgIIAgAAAA==.Lateesha:BAAANQAECgQIBAAAAA==.Lavac:BAAANQADCgEIAQAAAA==.',
Li='Lightguard:BAAANQAECgEIAQAAAA==.Lilplottwist:BAAANQADCgcIDQAAAA==.Lilwiz:BAAANQADCgUIAgAAAA==.Linnxvx:BAAANQADCgYIBgAAAA==.Lishp:BAAANQADCgYIBgAAAA==.Literacola:BAAANQADCggIDQAAAA==.',
Lu='Lugeya:BAAANQADCgcIBwAAAA==.Lustnbeiber:BAAANQAECgEIAQAAAA==.',
Ly='Lyncha:BAAANQADCgIIAgABNQADCgcIDQABAAAAAA==.Lynchà:BAAANQADCgcIDQAAAA==.',
Ma='Maakun:BAAANQADCgQIBAAAAA==.Maddevil:BAAANQADCgQIBwAAAA==.Mahzad:BAAANQAECgcICQAAAA==.Malfrun:BAAANQADCggIEAAAAA==.Marox:BAAANQADCggIDgAAAA==.Marrøwgar:BAAANQADCgUICQAAAA==.Mathrim:BAAANQAECgQICAAAAA==.Matooka:BAAANQADCgcIDAAAAA==.Maynji:BAAANQADCggICAAAAA==.',
Mi='Minithril:BAAANQADCgUICAAAAA==.Misspetite:BAAANQADCgMIAwAAAA==.',
Mo='Mojosmiles:BAAANQADCgQIBAAAAA==.Molodeath:BAAANQADCgcICAAAAA==.Mommÿ:BAAANQAECgIIAgAAAA==.Monkgroom:BAAANQAECgIIAgAAAA==.Montra:BAAANQAECgQIBAAAAA==.Morgaine:BAAANQADCgIIAQAAAA==.Motorinkashi:BAAANQAECgEIAQAAAA==.',
Mu='Muat:BAAANQADCgEIAQAAAA==.Muddbane:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Muddgore:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.',
My='Myzarei:BAAANQAECgEIAQAAAA==.',
['Mø']='Møkxi:BAAANQADCggICAAAAA==.',
['Mû']='Mûdd:BAAANQAECgQIBgAAAA==.',
Ne='Nestaah:BAAANQADCgIIAgAAAA==.Nethender:BAAANQADCgIIAgAAAA==.',
Ni='Nirath:BAAANQAECgIIAgAAAA==.Nito:BAAANQAECgQIBAAAAA==.',
No='Nohkano:BAAANQAECgQIBQAAAA==.Norriz:BAAANQADCggIDAAAAA==.',
Nu='Numbuh:BAAANQADCggICgAAAA==.',
Oa='Oakrogue:BAAANQADCgYICQAAAA==.',
Od='Odysseusxap:BAAANQADCgIIAgAAAA==.',
On='Oneshothel:BAAANQADCgEIAQAAAA==.',
Pa='Paladeez:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.Pallymans:BAAANQADCgMIAwAAAA==.Pangpang:BAAANQADCgYICwAAAA==.Parsi:BAAANQAECgIIAgAAAA==.Pattysmyth:BAAANQADCgYIBwABNQAECgUIBQABAAAAAA==.Paulinemaroi:BAAANQADCggICAAAAA==.',
Pe='Peleaihonua:BAAANQABCgIIAgABNQADCgUICAABAAAAAA==.',
Ph='Philip:BAAANQADCgYICwAAAA==.',
Pl='Playstayshon:BAAANQADCgMIAgAAAA==.',
Po='Pottyy:BAAANQABCgIIAgAAAA==.',
Pr='Pritee:BAAANQADCgcIEgAAAA==.',
Pu='Putu:BAAANQADCgUIBgAAAA==.',
Py='Pyrina:BAAANQADCggIDgABNQAECgIIAgABAAAAAA==.',
Ra='Rabite:BAAANQADCgcIDQAAAA==.Ramshunter:BAAANQAECgMIBAAAAA==.Rathasas:BAAANQAECgIIAwAAAA==.Ratnob:BAAANQAECgEIAQAAAA==.',
Re='Reddemon:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Remye:BAAANQADCgMIAwAAAA==.Rennshi:BAAANQAECgYIBgAAAA==.',
Rh='Rhavetta:BAAANQADCgUIBQAAAA==.',
Ri='Riani:BAAANQAECgEIAQAAAA==.',
Ro='Rolanthas:BAAANQAECgEIAQAAAA==.Rosario:BAAANQAECgUICAAAAA==.',
Ry='Rythmatic:BAAANQAECgMIAwAAAA==.',
Sa='Sagà:BAAANQABCgEIAQAAAA==.Sainttaint:BAAANQADCgMIAwABNQADCgEIAQABAAAAAA==.Sakieri:BAAANQADCggIDwAAAA==.Saluke:BAAANQADCgUIBQAAAA==.Samwisegam:BAAANQADCgQIBAAAAA==.Sangan:BAAANQAECgMIAwAAAA==.Santaclaus:BAAANQADCgYICwAAAA==.',
Se='Seanoevil:BAAANQAECgIIAgAAAA==.Serazal:BAAANQAECggIDwAAAA==.Sergregorsly:BAAANQADCgIIAgAAAA==.Serintalis:BAAANQADCgEIAQAAAA==.',
Sh='Shakaphase:BAAANQADCgYICwAAAA==.Shamshamz:BAAANQADCgUIBQAAAA==.',
Si='Sinaga:BAAANQAECgEIAQAAAA==.Sintha:BAAANQADCgYIEQAAAA==.',
Sl='Slimedink:BAAANQADCgYICAAAAA==.',
Sm='Smolworm:BAAANQADCgUICQAAAA==.',
So='Soulezz:BAAANQAECgEIAQAAAA==.Sourmash:BAAANQADCgYIBwAAAA==.',
St='Steppedon:BAAANQADCgUIBQAAAA==.Stingerai:BAAANQAECgQIBQAAAA==.Stingerjb:BAAANQADCgUICQABNQAECgQIBQABAAAAAA==.',
Su='Sukunaa:BAAANQADCgMIAwAAAA==.Superdeej:BAAANQABCgQIBAABNQAECgIIAgABAAAAAA==.',
Sy='Syl:BAAANQADCgQIBAAAAA==.',
Ta='Tarashock:BAAANQADCgUIBgAAAA==.',
Te='Teecat:BAAANQADCgQIBwAAAA==.Teehuntee:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Teemonk:BAAANQAECgEIAQAAAA==.Teepal:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Telamanus:BAAANQABCgIIAgAAAA==.Tempist:BAAANQADCgYICgAAAA==.Teribullduce:BAAANQAECgUIBgAAAA==.Terscheckii:BAAANQADCgYIBwAAAA==.',
Th='Thingol:BAAANQABCgQIBgAAAA==.Thormor:BAAANQAECgQICAABNQAFFAIIAgABAAAAAA==.Thugger:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Thuggerjr:BAAANQAECgEIAQAAAA==.Thundersurge:BAAANQADCggIDgAAAA==.Thænes:BAAANQADCggIEQAAAA==.',
Ti='Tipsout:BAAANQAECgIIAgAAAA==.',
To='Totemm:BAAANQAECgEIAQAAAA==.Tottemdrop:BAAANQAECgUIBQAAAA==.',
Tr='Trailertrash:BAAANQADCgIIAgAAAA==.',
Ty='Tyllinar:BAAANQADCgYIBgAAAA==.Tyrgor:BAAANQABCgQIBQAAAA==.Tyrsside:BAAANQADCgMIBAAAAA==.',
Ub='Ubeenbained:BAAANQADCgEIAQAAAA==.',
Un='Unfocused:BAAANQAECgQIBAAAAA==.',
Ur='Urgmathron:BAAANQADCgUICgAAAA==.',
Va='Vakhara:BAAANQADCgUICAAAAA==.Valorisa:BAAANQAECgMIAwABNQAECgcICgABAAAAAA==.Vaush:BAAANQADCgUIBwAAAA==.',
Vo='Voidyvoid:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Vonrx:BAAANQADCgYIBwAAAA==.',
Vy='Vyndrian:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
We='Welfairline:BAAANQADCgUIBQAAAA==.',
Wi='Winrodan:BAAANQAECgQIBQAAAA==.',
['Wô']='Wôrm:BAAANQADCgUICQAAAA==.',
Xa='Xalarys:BAAANQADCgYIBgAAAA==.Xandra:BAAANQADCgMIAwAAAA==.',
Xs='Xsslopgob:BAAANQADCgEIAQAAAA==.',
Xu='Xufoxpikmin:BAAANQADCgEIAQAAAA==.',
Ya='Yappars:BAAANQADCgEIAQAAAA==.Yassera:BAAANQAECgQIBAAAAA==.',
Ye='Yekteniya:BAAANQADCgQIBAAAAA==.',
Yu='Yurio:BAAANQADCgcICwAAAA==.Yutch:BAAANQAECgQIBQAAAA==.',
Za='Zacalkan:BAAANQADCgIIBAAAAA==.Zarik:BAAANQADCgYICwAAAA==.',
Ze='Zedward:BAEANQADCgMIBQAAAA==.Zenfist:BAAANQADCgUIBAAAAA==.',
Zo='Zolidus:BAAANQADCgQIBAAAAA==.Zosiris:BAAANQADCgQIBAAAAA==.',
Zu='Zulugangrene:BAAANQADCggIDgAAAA==.',
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
