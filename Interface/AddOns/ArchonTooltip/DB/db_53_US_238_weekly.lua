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

local lookup = {'Unknown-Unknown','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Retribution','Priest-Holy','DemonHunter-Havoc','Evoker-Preservation','DemonHunter-Vengeance','Evoker-Devastation','Priest-Shadow','Warlock-Demonology','Rogue-Assassination','Rogue-Subtlety','Warlock-Destruction','Druid-Restoration','DeathKnight-Frost','DemonHunter-Devourer','Shaman-Restoration','Shaman-Elemental','Mage-Arcane','Druid-Balance','Paladin-Holy','DeathKnight-Unholy','Warrior-Arms','Warrior-Fury','Monk-Windwalker','Monk-Mistweaver',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aayrawn:BAAANQAECgYICwAAAA==.',
Ac='Aceofplagues:BAAANQADCgQIBAAAAA==.Acesdruid:BAAANQAECgUIBQAAAA==.Aceshaman:BAAANQAECgYICgAAAA==.',
Ai='Airone:BAAANQADCgYICgAAAA==.',
Ak='Akadion:BAAANQADCggICAAAAA==.',
Al='Alextros:BAEANQABCgIIAwABNQAECgYJEAABAAAAAA==.',
Am='Amaranthe:BAAANQADCggIDAAAAA==.Amrax:BAAANQAECgYJCgAAAA==.',
An='Antijastran:BAAANQAECgUIBQAAAA==.',
Aq='Aquabat:BAABNQAECoEfAAMCAAkKkB0ACwD0AgACAAkKfRwACwD0AgADAAEK/CCv3wBeAAAAAA==.',
Ar='Artemist:BAAANQADCgUJBQAAAA==.',
As='Ashbringer:BAABNQAECoEdAAIEAAkKmSSmBAC/AwAEAAkKmSSmBAC/AwAAAA==.',
At='Athalax:BAAANQADCgEIAQAAAA==.Attia:BAAANQAECgUIBgAAAA==.',
Ba='Baladoria:BAABNQAECoEXAAIFAAgK8hD8RQDKAQAFAAgK8hD8RQDKAQAAAA==.Baldkrank:BAAANQAECgQIBAAAAA==.Bananabowman:BAAANQAECgQIBgAAAA==.Banditos:BAAANQAECgMIBQAAAA==.Bartab:BAAANQAECgYJCQABNQAECgMIAwABAAAAAA==.',
Be='Bearemy:BAAANQAECgEIAQABNQAECgYICQABAAAAAA==.Beastling:BAAANQAECgEIAQAAAA==.Beau:BAABNQAECoEnAAIGAAkK0iI/BwBOAwAGAAkK0iI/BwBOAwAAAA==.Beauwi:BAAANQADCggIEQABNQAECgkJJwAGANIiAA==.Bettyßrisco:BAAANQADCgYJBgABNQAECgYJBgABAAAAAA==.',
Bi='Bigchungusyo:BAAANQADCgYIBwAAAA==.Bigpapi:BAAANQAECgMIAwAAAA==.',
Bl='Blawkk:BAAANQADCggIEAAAAA==.',
Bo='Bombur:BAAANQAECgUJCAAAAA==.Bonejovi:BAAANQADCgIIAgAAAA==.',
Br='Brokenbubble:BAAANQAECgMIAwABNQAECgkJHwAHAH0VAA==.Brozown:BAAANQADCgQIBAABNQAECgkJHwACAJAdAA==.Brëtski:BAAANQADCggICAAAAA==.',
Bu='Buzzkill:BAAANQAECgQJBAAAAA==.',
Ca='Calinash:BAAANQAECgYIDQAAAA==.Calzraxx:BAAANQAECgUIDwAAAA==.Cartons:BAAANQADCgQIBAABNQAECggIBwABAAAAAA==.',
Cc='Ccaan:BAAANQAECgIIAgAAAA==.',
Ce='Celinn:BAAANQAECgYIEAAAAA==.',
Ch='Charliek:BAAANQAECgUICQAAAA==.Chimalma:BAAANQAECgYIDwAAAA==.Chorr:BAAANQABCgMIAwABNQAECgUIBQABAAAAAA==.',
Ck='Ckaan:BAAANQADCggICAAAAA==.',
Co='Cobygo:BAAANQADCggIDwAAAA==.Coffins:BAAANQADCgYIBgABNQAECggIBwABAAAAAA==.',
Cr='Crates:BAAANQAECggIBwAAAA==.Cringely:BAAANQAECgcIEQAAAA==.Croakam:BAAANQADCgIIAgABNQAECgkJHQAIAI0hAA==.Crosswalkk:BAAANQADCgUIBQAAAA==.Cryface:BAAANQADCgIIAgABNQABCgQIBAABAAAAAA==.',
Cu='Curonconagua:BAAANQADCgcICAAAAA==.',
Cy='Cypherrellik:BAAANQAECgUJBQAAAA==.',
Da='Daktok:BAAANQADCgQIAgAAAA==.Dargar:BAAANQADCgYIBgAAAA==.Darknyss:BAAANQADCgEJAQAAAA==.Darkozygo:BAAANQADCggIHgAAAA==.',
De='Deathfortres:BAAANQAECgQICAAAAA==.Deathstar:BAAANQADCgEIAQAAAA==.Deidara:BAABNQAECoEeAAIGAAkKSyLjBQBnAwAGAAkKSyLjBQBnAwAAAA==.Demolish:BAAANQADCggJDgAAAA==.Demongrass:BAAANQAFFAEIAQAAAA==.Devit:BAAANQAECgQICAAAAA==.',
Di='Dimka:BAAANQADCggIEgAAAA==.Dirtyfox:BAAANQADCgQIBAAAAA==.Disarray:BAAANQAECgQIBwAAAA==.',
Do='Donvald:BAAANQAECgIIAwAAAA==.Doodaad:BAAANQADCgYICwAAAA==.Doublerack:BAAANQAECgQICwABNQABCgQIBAABAAAAAA==.',
Dr='Dragondznuts:BAABNQAECoEfAAMHAAkKfRWlEABMAgAHAAkKfRWlEABMAgAJAAIKDQ1VJwB1AAAAAA==.Druzizzle:BAAANQADCgQIBAAAAA==.Dríppy:BAAANQADCgYJBgAAAA==.',
Ei='Eilerra:BAAANQAECgQIBwABNQAECgYIBwABAAAAAA==.',
Er='Erre:BAAANQAECgYIEAAAAA==.',
Fa='Fallenhunt:BAAANQADCgQIBAAAAA==.',
Fi='Firesson:BAAANQAECgIIAgAAAA==.',
Fo='Fourroadsgz:BAAANQAECgQIBAAAAA==.Foxoffire:BAAANQADCgYIDQAAAA==.Foxtracks:BAAANQADCgEIAQAAAA==.',
Fr='Fritark:BAAANQAECgYIEAAAAA==.',
Ge='Gena:BAAANQADCgYJEQAAAA==.Geörge:BAACNQAFFIEGAAIKAAQKxgm0BQAzAQAKAAQKxgm0BQAzAQA1AAQKgSUAAgoACQpiH6oGAEsDAAoACQpiH6oGAEsDAAAA.',
Gh='Ghostbath:BAAANQABCgUIBQAAAA==.',
Go='Goated:BAAANQAECgQJBgAAAA==.',
Gr='Gremfrost:BAAANQAECggJEAAAAA==.Grotelek:BAAANQAECgYIEAAAAA==.Grumpywaltz:BAAANQAECgYICwAAAA==.',
Gu='Gunhild:BAAANQADCgQIBAAAAA==.',
Ha='Haedrath:BAAANQAECgYIBwAAAA==.Hahafunny:BAAANQADCggICQAAAA==.Halcotsu:BAABNQAECoEYAAILAAgKIgpXXQCxAQALAAgKIgpXXQCxAQAAAA==.Halleko:BAAANQAECgcICQABNQAFFAUICQAMANAQAA==.Hammerfoot:BAAANQAECgIIAgAAAA==.Harkknight:BAAANQAECgUICQAAAA==.Haurtrue:BAAANQAECgMJCAAAAA==.Hawgbawl:BAAANQAECgUICwAAAA==.Hawgdream:BAAANQAECgQJCQAAAA==.',
He='Heliah:BAAANQABCgIIAgAAAA==.Hellequin:BAACNQAFFIEJAAMMAAUK0BDSAQC4AQAMAAUK0BDSAQC4AQANAAEKOQFrDwA6AAA1AAQKgSEAAwwACQq0IhAGAC8DAAwACQq0IBAGAC8DAA0ABgrZHxIYAOIBAAAA.Heyyitzrichh:BAABNQAECoEVAAMOAAgKrhn4IABFAQALAAYKERcOYgCiAQAOAAQKeB/4IABFAQAAAA==.',
Ho='Hollinar:BAAANQAECgcIDgAAAA==.Holycøw:BAAANQADCgQIBQAAAA==.Hondoe:BAAANQAECgMIAwAAAA==.',
Ih='Ihavecookies:BAAANQADCgcJEAAAAA==.',
Im='Imahealer:BAAANQADCgMIAwAAAA==.',
In='Invaled:BAAANQAECgUJCAAAAA==.',
Ir='Irateknight:BAAANQADCgcJDAAAAA==.',
Is='Isegrim:BAAANQADCgEJAQAAAA==.',
It='Itzrich:BAAANQAECgQIBwAAAA==.',
Ja='Jakelong:BAAANQAECgQICQABNQAECgkJHwAEAGwhAA==.Jasmirangel:BAABNQAECoEZAAIPAAgKtCIHBgAfAwAPAAgKtCIHBgAfAwAAAA==.',
Je='Jenesis:BAAANQAECgYIDAAAAA==.Jermajesty:BAAANQAECgYICQAAAA==.Jezus:BAAANQABCgYJDwAAAA==.',
Jo='Joanoforc:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Jovar:BAAANQADCgMIAwAAAA==.',
['Jö']='Jöker:BAAANQADCgYJCwABNQAECgEJAQABAAAAAA==.',
Ka='Kalzifer:BAAANQAECgQICAABNQAECgkJGwAQABsdAA==.Kankaladin:BAABNQAECoEfAAIEAAkKbCF3EgBDAwAEAAkKbCF3EgBDAwAAAA==.Kanky:BAAANQAECgUIBQABNQAECgkJHwAEAGwhAA==.Kano:BAABNQAECoEcAAMCAAgKtg4jJwCRAQACAAgKiQcjJwCRAQADAAYKBhGEdgCKAQAAAA==.Karper:BAAANQADCgYIBgAAAA==.Kawada:BAAANQAECgMJBQAAAA==.Kayhaus:BAAANQADCgQIBAAAAA==.',
Ke='Ken:BAAANQAECgYICwAAAA==.Kennëdi:BAAANQAECgUIBwAAAA==.',
Kh='Khory:BAAANQAECgUIBQAAAA==.',
Ki='Kichirõ:BAAANQAECgcJEgAAAA==.',
Km='Kmt:BAAANQADCggIDgABNQAECgUJBAABAAAAAA==.',
Ko='Koffee:BAAANQAECgYICAABNQAECgkJHwAEAGwhAA==.Korgigor:BAAANQADCgEJAQAAAA==.',
Kt='Kt:BAAANQAECgUJBAAAAA==.',
Ku='Kuailiang:BAAANQADCgYIBgABNQAECggJHQARAHUTAA==.',
La='Ladezar:BAAANQADCgYJBgAAAA==.Laissen:BAAANQADCgYJGAAAAA==.Lattemocha:BAAANQAECgUICQAAAA==.',
Le='Leprechaun:BAAANQAECgQJBAABNQAECgQJCgABAAAAAA==.Leprechauñ:BAAANQAECgQJCgAAAA==.Leprecháun:BAAANQAECgIJAwABNQAECgQJCgABAAAAAA==.',
Li='Liche:BAAANQAECgEIAQABNQAECgkJHgAGAEsiAA==.Lighthoove:BAAANQADCgcIBwAAAA==.Lightsir:BAAANQADCgMIBwAAAA==.Lishalle:BAAANQADCgUIBQAAAA==.',
Lo='Loutone:BAAANQADCgcJEQAAAA==.',
Lu='Ludlow:BAAANQAECgEJAQAAAA==.Lunatonne:BAAANQAECgUICQAAAA==.Luneztoprime:BAAANQAECgQICAAAAA==.Luvlybella:BAAANQADCggJCAAAAA==.',
Ly='Lyiann:BAAANQADCgYICgAAAA==.Lyákadion:BAAANQADCggIEgAAAA==.',
Ma='Mafi:BAAANQAECgQIBgAAAA==.Mallypally:BAAANQAECgIIAgABNQAECgUIDQABAAAAAA==.Matt:BAABNQAECoEmAAIPAAkKPh4sBgAcAwAPAAkKPh4sBgAcAwAAAA==.Matte:BAABNQAECoEYAAMSAAkKzxnLGADDAgASAAkKzxnLGADDAgATAAEK6Ajc5gAtAAABNQAECgkJJgAPAD4eAA==.Mazza:BAAANQAECgcICQAAAA==.',
Me='Megorice:BAAANQADCgcIBwAAAA==.Mewtwô:BAAANQAECgQIBQAAAA==.',
Mi='Miedillø:BAAANQADCgYIBgABNQAFFAYJEQADAL4RAA==.Mikeoxmall:BAABNQAECoEfAAMDAAkKghbZMABwAgADAAgKOBnZMABwAgACAAUKxwuXNAAIAQAAAA==.',
Mo='Monstermime:BAAANQAECgYICwAAAA==.Moosetrax:BAAANQAECgYIEAAAAA==.',
Mu='Muffy:BAAANQADCgQIBAAAAA==.Mushumime:BAAANQADCgYIDAABNQAECgYICwABAAAAAA==.',
My='Myserie:BAABNQAECoEVAAIKAAgKfw4YGwD9AQAKAAgKfw4YGwD9AQAAAA==.',
Na='Natsuu:BAAANQABCgMJAwAAAA==.Nazara:BAABNQAECoEjAAMJAAkKIxrBBwDLAgAJAAkKIxrBBwDLAgAHAAIK9QuVNABkAAABNQAECgUIBQABAAAAAA==.',
Ne='Neuro:BAABNQAECoEgAAIUAAcKFRn2gwANAgAUAAcKFRn2gwANAgAAAA==.',
Ni='Nikodemos:BAAANQAFFAQJCAAAAQ==.',
Nk='Nkáujhmóob:BAAANQADCgIIAgAAAA==.',
Oo='Oopsifer:BAAANQAECgQICAAAAA==.',
Op='Optimum:BAAANQADCgQICwAAAA==.',
Or='Oran:BAAANQADCggIDgAAAA==.',
Pe='Persimmon:BAAANQAECgYICgAAAA==.Peyton:BAAANQAECgIJAgAAAA==.',
Pi='Piecemaker:BAABNQAECoEkAAIDAAkKvxwxFwDvAgADAAkKvxwxFwDvAgAAAA==.',
Pl='Plaguepapi:BAAANQADCgIJAgAAAA==.',
Pu='Pufdaddy:BAAANQABCgMIAwAAAA==.Puppetslayer:BAAANQAECgQIBAAAAA==.',
Py='Pyrrah:BAAANQAECgYIEAAAAA==.',
['Pé']='Péytón:BAAANQADCgQIBgAAAA==.',
Qu='Quanchì:BAABNQAECoEdAAIRAAgKdROOGgAyAgARAAgKdROOGgAyAgAAAA==.',
Ra='Rabuf:BAAANQAECgUICQAAAA==.Radha:BAAANQAECgYICwABNQAECgkJIAAVACkeAA==.Rageruññer:BAAANQADCgYIBgAAAA==.',
Re='Redizle:BAAANQADCggICAABNQAFFAQJCQAWAIIWAA==.Reginrune:BAAANQAECggJBQAAAA==.Resonance:BAAANQAECgMIBAAAAA==.',
Rh='Rhaenyr:BAAANQADCggIFwAAAA==.',
Ri='Ridizle:BAACNQAFFIEJAAIWAAQKghbtBgBkAQAWAAQKghbtBgBkAQA1AAQKgSgAAhYACQp2ICIJAFADABYACQp2ICIJAFADAAAA.',
Ro='Rohdoog:BAAANQAECgUIDQAAAA==.',
Ru='Runedyu:BAAANQAECgQIDQAAAA==.',
Ry='Ryanno:BAAANQAECggICgAAAA==.Ryannoo:BAAANQADCgYIBwAAAA==.Ryunosuke:BAAANQAECggICwABNQAECgkJHgAGAEsiAA==.',
Sa='Sahomi:BAAANQAECggJEQAAAA==.Sammage:BAAANQADCgEIAQAAAA==.Sanlein:BAAANQAECggIAQAAAA==.Sarcini:BAAANQAECgUICwAAAA==.Sarcisse:BAAANQAECgcICgAAAA==.Satrina:BAABNQAECoEWAAMXAAgK2RjtIABdAgAXAAgK2RjtIABdAgAQAAIKtBFPWwByAAAAAA==.Savvy:BAAANQAECgYICwAAAA==.',
Se='Senaren:BAAANQADCgYIBwAAAA==.Senlain:BAAANQADCgQIBAAAAA==.Seraphiña:BAAANQAECgEIAQAAAA==.',
Sh='Shagore:BAAANQADCgYIDwABNQABCgQIBAABAAAAAA==.Shamander:BAAANQAECgEJAQAAAA==.Shameonyou:BAAANQAECgMIBAAAAA==.',
Si='Sigard:BAAANQADCgMIAwAAAA==.Silentmage:BAAANQADCgIIAgAAAA==.Sinclaire:BAAANQADCgIJAgAAAA==.Sitruc:BAAANQAECgMIBAAAAA==.',
Sl='Slander:BAAANQAECgQJBAAAAA==.',
Sm='Smartbuff:BAAANQADCgUICQAAAA==.',
So='Somazugzug:BAAANQAECggJEAAAAA==.Soyboy:BAAANQABCgUIBwAAAA==.',
Sp='Spacedguy:BAAANQADCgYICQAAAA==.Spammoosubi:BAAANQADCgcIBwAAAA==.Spamnrice:BAAANQAECgYJDgAAAA==.',
Su='Sugars:BAAANQAECgEIAQAAAA==.',
Ta='Tarnished:BAAANQADCgIIAgAAAA==.Tarquitus:BAABNQAECoEdAAMIAAkKjSEiAQBoAwAIAAkKjSEiAQBoAwAGAAEK+QfCYgAzAAAAAA==.',
Te='Teostra:BAAANQADCgIIAgABNQAECgUIBQABAAAAAA==.',
Th='Thedarkduke:BAAANQAECgYJCgAAAA==.Thedarkkness:BAAANQADCgYIBgAAAA==.Thorin:BAAANQAECgUIBwABNQAECgYJDQABAAAAAA==.Thud:BAAANQAECgcICAAAAA==.',
Ti='Tidalwave:BAAANQAECgcJEQAAAA==.Timmeh:BAAANQAECgQJBAAAAA==.Tindra:BAAANQAECgQICAAAAA==.Tissue:BAAANQAECggIDgAAAA==.Titanius:BAAANQADCgQIBgABNQAECgUIBQABAAAAAA==.',
To='Tobibi:BAAANQAECgYJDQAAAA==.Tolip:BAAANQAECgQICQAAAA==.Tolipally:BAAANQADCgYICwABNQAECgQICQABAAAAAA==.Tolipicious:BAAANQADCgYIBgABNQAECgQICQABAAAAAA==.Tollock:BAAANQADCgcIDQAAAA==.Torpse:BAAANQAECgcJDAABNQAECgkJIgAVAI8kAA==.',
Tr='Trevórg:BAAANQAECgUJDgAAAA==.',
Ts='Tsarrubus:BAAANQAECgYIEAAAAA==.',
Tu='Tusck:BAAANQADCgcIEAAAAA==.',
Ul='Ulg:BAABNQAECoEZAAMYAAgK/RsfOQCCAgAYAAgK6xsfOQCCAgAZAAEKsR2mHQBQAAAAAA==.Ulghar:BAAANQADCgYIBgABNQAECggJGQAYAP0bAA==.',
Va='Vanquisher:BAAANQAECgYJBgAAAA==.',
Ve='Velvet:BAAANQAECgIIBAAAAA==.Vengeanze:BAAANQAECgQIBQAAAA==.Vengefulcry:BAAANQADCgYICgAAAA==.Verrat:BAAANQAECgYIEAAAAA==.',
We='Wellerman:BAAANQAECgQIBQAAAA==.',
Wi='Wino:BAAANQAECgMIAwAAAA==.Wiqui:BAAANQAECgMIBAAAAA==.',
Wo='Wolfonk:BAABNQAECoEdAAIaAAgK0gYvIgB3AQAaAAgK0gYvIgB3AQAAAA==.',
Wu='Wuhshake:BAAANQAECgYJDQAAAA==.',
['Wë']='Wërrcs:BAAANQAECgEIAgAAAA==.',
Xe='Xemo:BAAANQAECgQICwAAAA==.Xenophics:BAABNQAECoEgAAIEAAkK6h/lFQArAwAEAAkK6h/lFQArAwAAAA==.',
Za='Zaiha:BAAANQADCgYIBgAAAA==.Zal:BAAANQAECgUICQAAAA==.Zall:BAABNQAECoEXAAMaAAkKqxouDQCsAgAaAAkKqxouDQCsAgAbAAIKixP7LgBpAAAAAA==.Zamos:BAAANQAECgEJAgAAAA==.',
Ze='Zenshin:BAAANQADCgYIDAAAAA==.Zentaur:BAAANQAECgYICwAAAA==.',
Zi='Zitfrlt:BAAANQAECgQIDAABNQAECgkJGwAQABsdAA==.',
Zo='Zontar:BAAANQAECgQIBgAAAA==.Zorman:BAAANQADCgIIAwAAAA==.',
['Ål']='Ålucard:BAAANQAECgUICQAAAA==.',
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
