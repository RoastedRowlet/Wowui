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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Paladin-Protection','Unknown-Unknown','Shaman-Elemental','Warrior-Arms','Shaman-Restoration','Shaman-Enhancement','Mage-Arcane','DeathKnight-Blood','Hunter-BeastMastery','Warrior-Fury','Evoker-Preservation','Hunter-Marksmanship','Warrior-Protection',}
local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abaddon:BAAANQAECgEIAQAAAA==.',
Ac='Ackris:BAABNQAECoEdAAMBAAkJSSGoAwBzAwABAAkJSSGoAwBzAwACAAEJmRB6WgA7AAAAAA==.',
Ag='Agolan:BAAANQADCgcIBwAAAA==.',
Al='Aldric:BAEANQADCgMIAwABNQAECgkJHgADAPwkAA==.Alkaios:BAAANQADCgMIAwABNQAECgMIBgAEAAAAAA==.Alucarddalv:BAAANQADCggIDAAAAA==.',
Am='Amaimon:BAAANQAECgEIAQABNQAECgkJGwAFAE8aAA==.Amnoon:BAAANQAECgMIBQAAAA==.Amri:BAAANQAECgQIBQABNQAECgUIDQAEAAAAAA==.',
Ap='Apoly:BAAANQADCgUIBQAAAA==.',
Aq='Aquas:BAAANQADCgEIAQAAAA==.',
Ar='Arknem:BAAANQABCgQIBQAAAA==.Artikin:BAAANQADCgcICQABNQAECggIHAAGACYWAA==.',
As='Asûná:BAAANQAECgQIBQAAAA==.',
At='Atlas:BAAANQAECgUICwAAAA==.',
Au='Auroxa:BAAANQAECgIIAwAAAA==.Automagic:BAAANQADCgYICAAAAA==.',
Av='Avondwella:BAAANQAECgQIBwAAAA==.',
Az='Azorah:BAAANQADCgcIBwAAAA==.',
Ba='Bacevicius:BAAANQAECggIAgAAAA==.Baldyguy:BAAANQADCgYIEQAAAA==.Balm:BAAANQAECgQIBgAAAA==.',
Be='Beastlybull:BAAANQAECgcICwABNQAFFAUICwAHAD4cAA==.',
Bi='Biblepimp:BAAANQAECgEIAQAAAA==.Bigfries:BAAANQADCgQIBgAAAA==.Bigsneak:BAAANQAECgEIAgAAAA==.',
Bl='Blackmarker:BAAANQAECgMIAwAAAA==.Blemish:BAAANQADCgEIAQABNQAECgQIBgAEAAAAAA==.Bloodpac:BAAANQADCgIIAQAAAA==.',
Bo='Boadica:BAAANQADCgIIAgAAAA==.Bobsuruncle:BAAANQAECgEIAQAAAA==.Bodyguardwyn:BAAANQAECgIIBQAAAA==.Bolvar:BAAANQAECgIIAwAAAA==.Bonedjovi:BAAANQAECgMIBAAAAA==.Boondiggles:BAAANQADCgYIBgAAAA==.',
Br='Brathelore:BAAANQADCggICgAAAA==.Bremitox:BAAANQADCgcICAABNQAECgMIBgAEAAAAAA==.Brimscythe:BAAANQADCgIIAQAAAA==.Brud:BAAANQAECgUICQAAAA==.',
By='Byakugan:BAABNQAECoEbAAMFAAkJTxoyGwCaAgAFAAgJRxwyGwCaAgAIAAEJkQqFHgBJAAAAAA==.',
['Bø']='Bønitalèè:BAAANQAECgEIAwAAAA==.',
Ca='Calvisi:BAAANQADCgcIBgAAAA==.Calvisichaos:BAAANQAECgMIBAAAAA==.Canthen:BAAANQAECgYIAgAAAA==.',
Ch='Chaoticbacon:BAAANQADCgYIBgABNQAECgEIAgAEAAAAAA==.',
Co='Cosmicspark:BAAANQAECgIIAwAAAA==.',
Cr='Cropala:BAAANQAECgMIBQAAAA==.',
Da='Darkwingduck:BAAANQADCgQIBAAAAA==.Darkøne:BAAANQABCgMIAwAAAA==.Davros:BAAANQADCgYIDAAAAA==.',
De='Dellandre:BAAANQADCgcIBgABNQAECgMIBAAEAAAAAA==.Delta:BAAANQAECgEIAQAAAA==.Delti:BAAANQADCggICAABNQAECgIIAwAEAAAAAA==.',
Di='Diabolist:BAAANQAECgUIBwAAAA==.',
Dk='Dkdozer:BAAANQADCgYIDAAAAA==.',
Do='Doktaga:BAAANQAECgIIBAAAAA==.',
Dr='Drakonna:BAAANQADCgUIBQAAAA==.Drarken:BAAANQAECgYIDwAAAA==.Drtapo:BAAANQABCgEIAQAAAA==.',
El='Elderr:BAAANQADCgcICwABNQAECgMIBAAEAAAAAA==.Eldhe:BAAANQADCgIIAgAAAA==.Elistrae:BAAANQAECgUICQAAAA==.',
En='Enazen:BAAANQAECgUIBwAAAA==.',
Er='Ereshkigal:BAAANQADCgUIBQAAAA==.Ergo:BAABNQAECoEaAAIJAAkJ3h2hIQAOAwAJAAkJ3h2hIQAOAwAAAA==.',
Ex='Exon:BAAANQAECgIIAwAAAA==.',
Fa='Faded:BAAANQADCggIDAABNQAECgQICAAEAAAAAA==.Fadednight:BAAANQAECgQICAAAAA==.',
Fe='Femcelibate:BAAANQAECgIIAgAAAA==.Femdom:BAAANQAECgUIBQABNQAECgkJHgAKAG4mAA==.',
Fi='Fivebones:BAAANQADCgcIBgABNQAECgcIGAALAMwjAA==.',
Fr='Freecookies:BAAANQADCggICAAAAA==.Frostytotems:BAAANQADCgQIBwAAAA==.',
Ga='Gabagool:BAAANQAECgMIBQAAAA==.',
Ge='Gerbert:BAAANQABCgIIAgAAAA==.',
Gh='Ghostë:BAAANQAECgMIAwAAAA==.',
Gi='Gishmou:BAAANQAECgIIAwAAAA==.',
Gu='Gutted:BAABNQAECoEeAAIKAAkJbiaaAADwAwAKAAkJbiaaAADwAwAAAA==.',
Ha='Hanna:BAAANQADCggICgABNQAECgkJHgAKAG4mAA==.',
He='Hellmaw:BAAANQAECgQIBAAAAA==.',
Ho='Hollowheart:BAAANQAECgEIAQAAAA==.Holycourtney:BAAANQADCgQIBAAAAA==.Holyfur:BAAANQAECgMIBAAAAA==.',
Hy='Hylanna:BAAANQADCgYIDAAAAA==.',
Ic='Ici:BAAANQAECgQIBQAAAA==.',
If='Iffybacon:BAAANQAECgEIAQABNQAECgEIAgAEAAAAAA==.',
In='Intensifies:BAAANQAECgIIAwAAAA==.',
Is='Iskothar:BAAANQADCggIGAAAAA==.',
Iv='Ivarboneless:BAAANQAECgEIAgAAAA==.',
Ja='Jace:BAAANQADCgYIBgAAAA==.Jackz:BAAANQADCggIEgAAAA==.Jambii:BAAANQAECgIIAgAAAA==.Jattsz:BAEANQADCggICAAAAA==.Jayreezy:BAAANQAECgIIAgAAAA==.',
Jo='Jonah:BAAANQAECgcIDQAAAA==.Joshcalcjr:BAAANQAECgUIBwAAAA==.',
Ka='Kaessatha:BAEANQADCgIIAgABNQADCgYIDwAEAAAAAA==.Kalika:BAAANQADCgIIAgAAAA==.',
Ke='Ketesh:BAAANQAECgUIDQAAAA==.',
Ko='Kortona:BAAANQAECgEIAQAAAA==.',
La='Landrey:BAAANQADCgMIAwAAAA==.Laoghaire:BAAANQADCgYICwAAAA==.Laszarei:BAAANQAECgEIAQAAAA==.',
Le='Leonz:BAABNQAECoEoAAIMAAkJ1iUXAAD1AwAMAAkJ1iUXAAD1AwAAAA==.Letharanos:BAEANQAECgQIBQAAAA==.',
Li='Liraffemynn:BAAANQAECgYICgAAAA==.',
Lo='Lohfall:BAAANQADCgUIBgABNQAECgIIAwAEAAAAAA==.Lonranir:BAAANQADCggICQAAAA==.',
Lu='Luckylucy:BAAANQADCgUIBgAAAA==.Lunoria:BAAANQAECgYIBgAAAA==.',
Ma='Madarauchiha:BAAANQAECgYICQAAAA==.Madeirà:BAAANQADCgQIBAAAAA==.Maldran:BAAANQAECgMIBAAAAA==.Mallgrab:BAAANQADCgcIBwAAAA==.Manderpants:BAAANQADCgQIBAAAAA==.Marien:BAAANQAECgUIBwAAAA==.Maxus:BAAANQAECgQIBQAAAA==.',
Mb='Mbbin:BAAANQAECgYIEQAAAA==.',
Me='Meems:BAAANQABCgQIBAAAAA==.Mehuman:BAAANQAECgIIAwAAAA==.Mehumanhuntr:BAAANQADCgMIAwAAAA==.Mehumanlock:BAAANQAECgQICAAAAA==.Melgibson:BAAANQAECgUIBwAAAA==.Meworgendk:BAAANQADCgcIBwAAAA==.',
Mi='Miräj:BAAANQAECgMIBAAAAA==.Mistyblue:BAAANQAECgEIAQAAAA==.',
Mo='Mojomugambe:BAAANQADCgUIBwAAAA==.Moodacritz:BAAANQADCgYIBgAAAA==.Moonscale:BAAANQADCgYIDAAAAA==.Morel:BAAANQADCgQIBAAAAA==.Mortstan:BAABNQAECoEWAAIKAAcJUiSXDQDjAgAKAAcJUiSXDQDjAgAAAA==.',
Mu='Mutegen:BAAANQADCgYIBgAAAA==.',
Na='Nailz:BAAANQAECgIIAwAAAA==.',
Ni='Nightflame:BAAANQADCgYIBgAAAA==.Nightlion:BAAANQAECgIIAwAAAA==.',
No='Noahpal:BAAANQAECgUIBQABNQAECgUIBwAEAAAAAA==.Noahshaman:BAABNQAECoEZAAIFAAkJER9IDQAnAwAFAAkJER9IDQAnAwABNQAECgUIBwAEAAAAAA==.Noahwarlock:BAAANQAECgUIBwAAAA==.Nonsensical:BAAANQADCgEIAQABNQADCgUICQAEAAAAAA==.Notbacon:BAAANQAECgEIAQABNQAECgEIAgAEAAAAAA==.',
Oa='Oaths:BAAANQAECgEIAQAAAA==.',
Oh='Ohmylanta:BAAANQADCgMIBQAAAA==.Ohmylänta:BAAANQAECgUICwAAAA==.',
Or='Orandrok:BAAANQAECgEIAQAAAA==.',
['Oâ']='Oâth:BAAANQAECgUICAAAAA==.',
Pa='Pallyman:BAAANQADCgUIBQAAAA==.Pallywacker:BAAANQAECgIIAwAAAA==.Panzerkìn:BAAANQADCgUIBQAAAA==.',
Pe='Peythilly:BAAANQADCggIDAAAAA==.',
Pi='Pigishdog:BAAANQAECgUIDQAAAA==.',
Po='Poob:BAAANQADCgcIDQAAAA==.',
Ra='Ragerunner:BAAANQADCgQIBAAAAA==.',
Re='Redthing:BAAANQADCgYICwAAAA==.',
Ri='Rixas:BAAANQAECgYICAABNQAECgkJHQABAEkhAA==.Rixis:BAAANQADCgQIBAAAAA==.',
Ro='Rockafella:BAAANQADCgYICgAAAA==.Roguehiro:BAAANQAECgMIBQAAAA==.Rooter:BAABNQAECoEfAAINAAkJIyRbAQCWAwANAAkJIyRbAQCWAwAAAA==.Rozetta:BAAANQADCgQIBAAAAA==.',
Sc='Scrawni:BAAANQAECgUIBgABNQAECggIHAAGACYWAA==.',
Se='Selyane:BAAANQABCgYICwAAAA==.Seongpal:BAEBNQAECoEeAAIDAAkJ/CTNAADHAwADAAkJ/CTNAADHAwAAAA==.Seraphinà:BAAANQADCggICAABNQAECgMIAwAEAAAAAA==.Serbingium:BAAANQADCggIDAABNQAECgcIDQAEAAAAAA==.',
Sh='Shadowlight:BAAANQAECgEIAQABNQAECgEIAgAEAAAAAA==.Sharpshotjak:BAAANQAECggIDgAAAA==.Sharreth:BAAANQADCgUIBQAAAA==.Shimera:BAAANQAECgMIBAAAAA==.Shootrmcgavn:BAABNQAECoEXAAMLAAgJWSXYBQBxAwALAAgJCiXYBQBxAwAOAAgJ6x8pDgCmAgAAAA==.',
Sk='Sklormp:BAAANQAECgcIDQAAAA==.',
Sl='Slootar:BAAANQADCggIDwABNQAECgIIAgAEAAAAAA==.Slugs:BAAANQAECgEIAQAAAA==.',
Sm='Smoruk:BAAANQADCgUIBQAAAA==.',
So='Somerled:BAAANQAECgEIAgAAAA==.',
Sq='Squatreign:BAAANQAECgQICgAAAA==.',
Su='Sulyvahn:BAEANQAECgUIBwABNQAECgkJHgADAPwkAA==.Sunstrike:BAAANQADCgYIBgAAAA==.',
Sy='Sylvara:BAAANQADCgUICgAAAA==.',
Ta='Takka:BAAANQAECgcIDAAAAA==.Talkamar:BAAANQAECgMIBgAAAA==.Taylorswift:BAAANQAECgMIBQAAAA==.',
Th='Thekourge:BAAANQAECgMIBAAAAA==.Thenard:BAAANQADCgUICAAAAA==.Therealcafna:BAAANQADCgIIAgAAAA==.Thisle:BAAANQADCgcIEwAAAA==.Thukunamage:BAABNQAECoEPAAIJAAcJhhokYAAnAgAJAAcJhhokYAAnAgAAAA==.',
Ti='Tigerlord:BAAANQADCggIDgAAAA==.Tili:BAAANQADCgQIBAAAAA==.',
To='Tomislav:BAAANQAECgMIAwAAAA==.Touritos:BAAANQAECgIIAwAAAA==.',
Tr='Trimblestein:BAAANQAECgcIDQAAAA==.',
Tu='Tuskerdu:BAAANQAECgUICgAAAA==.',
Tw='Twohoofy:BAAANQADCgYICAAAAA==.',
Ud='Uddermilk:BAAANQADCgYIBgAAAA==.',
Va='Valandrian:BAAANQADCgYICQAAAA==.Valeka:BAAANQAECgUICwAAAA==.Valissar:BAAANQABCgcIBwAAAA==.Valr:BAAANQAECgMIBgAAAA==.Vandreu:BAAANQAECgIIAgAAAA==.',
Vs='Vse:BAAANQAECgYIEAAAAA==.',
Wo='Worgenkrantz:BAAANQAECgMIAwAAAA==.Worthybacon:BAAANQAECgEIAgAAAA==.',
Wr='Wrenlyn:BAAANQAECgcIDgABNQAECggIHAAGACYWAA==.',
Wu='Wukain:BAAANQAECgYICAAAAA==.',
Wy='Wyldbloom:BAAANQAECgMIAwAAAA==.',
Xa='Xarapxeh:BAAANQADCgUICAAAAA==.',
Xo='Xolòtl:BAABNQAECoEcAAMGAAgJJhZbQQAvAgAGAAgJhBVbQQAvAgAPAAcJbwvKDgBnAQAAAA==.',
Xy='Xymos:BAEBNQAECoEeAAMCAAkJTiVaAADMAwACAAkJTiVaAADMAwABAAQJnBODagAtAQAAAA==.',
Ya='Yakul:BAAANQAECgMIAwAAAA==.',
Za='Zalyia:BAAANQADCgQIBAAAAA==.',
Zd='Zdk:BAAANQADCgEIAQAAAA==.',
Ze='Zeroveth:BAAANQAECgUICgAAAA==.',
Zu='Zulcow:BAAANQAECgUIBQAAAA==.',
['Âr']='Ârtemis:BAAANQAECgIIAwAAAA==.',
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
