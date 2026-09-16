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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','Druid-Restoration','Hunter-BeastMastery','DemonHunter-Havoc','Paladin-Retribution','Monk-Windwalker','Shaman-Elemental','Shaman-Restoration','Warrior-Arms','DeathKnight-Frost','Rogue-Subtlety','Rogue-Assassination','Mage-Arcane','Mage-Frost','Priest-Shadow','Monk-Mistweaver',}
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aanaleaa:BAAANQADCggIGwAAAA==.',
Ad='Ad:BAAANQAECgcIDQABNQAECggIEgABAAAAAA==.Adellon:BAAANQAECgcIEwAAAA==.Adhar:BAAANQADCgQIBAAAAA==.Adrielle:BAAANQAECgIIAgAAAA==.',
Ak='Akakage:BAAANQAECgQIBwAAAA==.Akutoku:BAAANQADCggICwAAAA==.',
An='Anaki:BAAANQADCggIDAAAAA==.Annakkin:BAAANQAECgQICwAAAA==.',
Ar='Ar:BAAANQAECgcICgABNQAECggIEgABAAAAAA==.Archon:BAAANQAECgYIDwAAAA==.Arienca:BAAANQAECgYIDQAAAA==.',
At='At:BAAANQAECgEIAQABNQAECggIEgABAAAAAA==.',
Ba='Barbato:BAAANQADCgcICQAAAA==.',
Be='Beavesfault:BAAANQADCgYIBgAAAA==.Beldent:BAAANQADCgYICQAAAA==.Bepis:BAAANQAECgcIEQAAAA==.',
Bi='Bigleif:BAAANQADCgIIAgAAAA==.Bitsakura:BAAANQADCgUICwAAAA==.',
Bl='Blazerunner:BAAANQAECgUICwAAAA==.Blitzkreig:BAAANQADCggIFQAAAA==.Blured:BAAANQAECgcIEAAAAA==.',
Bo='Booty:BAAANQAECgcIEQAAAA==.Bort:BAAANQAECgYIDwAAAA==.',
Br='Brevyn:BAAANQABCgUIBQAAAA==.',
Bu='Bulla:BAAANQADCgcIDQAAAA==.Bung:BAAANQAECgcIEQAAAA==.Buum:BAAANQADCggIGwAAAA==.',
['Bä']='Bämba:BAAANQADCgcIDQABNQAECgMIBAABAAAAAA==.',
Ca='Cali:BAABNQAECoEgAAICAAkJXR9IBwAyAwACAAkJXR9IBwAyAwAAAA==.Calipari:BAAANQADCgQIBAABNQAECgkJIAACAF0fAA==.Catamara:BAAANQADCgcICQAAAA==.',
Ce='Cephus:BAABNQAECoEXAAIDAAgJqRDwEwDgAQADAAgJqRDwEwDgAQAAAA==.Cerafina:BAAANQADCgUICgAAAA==.',
Ch='Chayse:BAABNQAECoEaAAIEAAkJZh+tCgAuAwAEAAkJZh+tCgAuAwAAAA==.Chumléé:BAAANQADCgEIAQAAAA==.Chérry:BAABNQAECoEfAAMCAAkJHR5xCgD1AgACAAkJrRtxCgD1AgAFAAIJXho0PgCfAAAAAA==.',
Cl='Climpwimp:BAAANQADCgUIBQAAAA==.',
Co='Conneer:BAAANQADCgUIBQAAAA==.Consham:BAAANQAECgcIDwAAAA==.',
Cy='Cynestra:BAAANQADCggIFAAAAA==.Cyni:BAAANQAECgEIAQABNQAECgcIEAABAAAAAA==.',
Da='Dadudadu:BAABNQAECoEeAAIGAAkJcxSjLgBRAgAGAAkJcxSjLgBRAgAAAA==.Daftmonk:BAABNQAECoEpAAIHAAkJuCSsAQCrAwAHAAkJuCSsAQCrAwAAAA==.Darj:BAAANQAECgUIBgAAAA==.Darmonevil:BAAANQADCggICgAAAA==.Dasarus:BAAANQADCgQIBwAAAA==.Dauntless:BAAANQADCggIFQAAAA==.',
De='Deth:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Dethblades:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Dethblow:BAAANQAECgQIBAAAAA==.Dethcurse:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Deuterium:BAAANQADCgYIBgAAAA==.',
Di='Disturbbed:BAAANQABCgIIAgAAAA==.Diwa:BAABNQAECoEXAAMIAAgJGQVJYgAnAQAIAAcJKwNJYgAnAQAJAAYJbAHzegDVAAAAAA==.',
Dk='Dklot:BAAANQAECgYIEgAAAA==.',
Do='Doomkin:BAAANQADCgMIAwAAAA==.',
Dr='Draken:BAAANQAECgQIBAAAAA==.Drama:BAAANQAECgEIAQAAAA==.Draviin:BAAANQAECgYIDQAAAA==.Dreadgrave:BAAANQAECgQIBQAAAA==.Drequan:BAAANQADCgEIAQAAAA==.Driade:BAAANQADCgIIAgABNQAECgcIEAABAAAAAA==.',
Du='Dunkyn:BAAANQAECgQICQAAAA==.',
El='Elendryl:BAAANQADCgUIBQAAAA==.',
En='Enkeke:BAAANQAECgYIDgAAAA==.',
Ep='Epitaph:BAAANQADCggIDAAAAA==.',
Er='Erena:BAAANQADCgUIBQABNQABCgIIAgABAAAAAA==.Eresanna:BAAANQAECgYIDwAAAA==.Erf:BAAANQAECgcIEQAAAA==.',
Ex='Extremefear:BAAANQAECgMIBAAAAA==.',
Fe='Fearious:BAAANQAFFAIIAgAAAA==.Feroond:BAAANQAECgQIBwAAAA==.Feyrah:BAAANQADCgUIBQAAAA==.',
Fr='Frogteeth:BAAANQAECgIIAgAAAA==.Frozath:BAAANQADCgcICQAAAA==.',
Fu='Furibeav:BAAANQADCgQIBQABNQADCgYIBgABAAAAAA==.Fussypants:BAAANQAECgQICAAAAA==.',
Ga='Gallindral:BAAANQAECgYIEAAAAA==.',
Ge='Genericnpc:BAAANQADCgYIDwAAAA==.Geobrando:BAAANQAECgUICwAAAA==.',
Gg='Ggbrews:BAAANQAECgQIBAAAAA==.',
Gn='Gnosh:BAAANQADCggIGwAAAA==.',
Go='Goofypally:BAAANQAECgEIAgABNQAECggICAABAAAAAA==.',
Gr='Grippindeez:BAAANQADCgIIAgAAAA==.',
Gu='Guidosarduci:BAAANQAECgUICQAAAA==.Guiseppe:BAAANQAECgQICwAAAA==.Gungfu:BAAANQADCgYIBgAAAA==.',
Ha='Harle:BAAANQADCggIGwAAAA==.Hatari:BAAANQADCgEIAQAAAA==.',
He='Heavyg:BAABNQAECoEvAAIKAAkJYBLgMgBwAgAKAAkJYBLgMgBwAgAAAA==.',
Ho='Holyshortguy:BAAANQAECggIDAAAAA==.',
Hu='Hustlermag:BAAANQAECgYIDgAAAA==.',
Ic='Icelmo:BAAANQAECgcIDwAAAA==.',
Im='Impact:BAAANQADCgIIAgABNQAECgkJGAAIAFoeAA==.',
Ja='Jaskow:BAAANQAECgcIDgAAAA==.Jaymick:BAAANQADCggIGQAAAA==.',
Ju='Jusdatip:BAAANQAECgUIBgAAAA==.',
Ka='Kameshoga:BAAANQAECgEIAQAAAA==.Karten:BAAANQADCgcIDQAAAA==.',
Ke='Keir:BAAANQADCgQIBAAAAA==.',
Ki='Killjoyss:BAAANQADCgYIBgAAAA==.',
Kr='Krag:BAAANQADCgcICQABNQAECgYIDgABAAAAAA==.Krasis:BAAANQAECggICgAAAA==.Krazermonk:BAAANQAECgcIEwAAAA==.Kristysavage:BAAANQAECgYIDQAAAA==.',
Ku='Kumpell:BAAANQABCgEIAQAAAA==.',
La='Lanc:BAAANQADCggIFwAAAA==.',
Le='Leafsrock:BAAANQADCgEIAQAAAA==.Lealta:BAAANQAECgQIBQABNQAECgkJHAADANQlAA==.',
Li='Lichdawg:BAABNQAECoEZAAILAAkJvSKkBgAKAwALAAkJvSKkBgAKAwAAAA==.Lilthorn:BAAANQADCggICQAAAA==.',
Lo='Lover:BAAANQAECgEIAQAAAA==.',
Lt='Ltroflcopter:BAAANQAECgEIAQABNQAECggIDAABAAAAAA==.',
Lu='Lubu:BAAANQAECgUIBQAAAA==.Lumen:BAAANQADCgYIDQAAAA==.Lumiette:BAAANQAECgEIAQAAAA==.',
Lv='Lvispriestly:BAAANQAECgEIAQABNQABCgIIAgABAAAAAA==.',
Ly='Lynai:BAAANQAECgQIBAAAAA==.',
['Lá']='Lándwhale:BAABNQAECoEZAAMMAAkJ1iNBAQCpAwAMAAkJtyNBAQCpAwANAAEJ/yW3PwBuAAAAAA==.',
['Læ']='Lægolas:BAAANQADCgIIAgAAAA==.',
['Lö']='Löver:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.',
Ma='Macktimus:BAAANQAECgQIBAAAAA==.Magictonyp:BAAANQADCgUICQAAAA==.Makili:BAABNQAECoE0AAMOAAkJKSB0FQBIAwAOAAkJKSB0FQBIAwAPAAEJeAyTKgAxAAAAAA==.Malonion:BAAANQADCgYIBgAAAA==.',
Mc='Mcfire:BAAANQAECgUIBgAAAA==.',
Me='Melotte:BAAANQADCggIEgAAAA==.Mepha:BAAANQADCgYIBgAAAA==.Merlîn:BAAANQADCgUICwAAAA==.',
Mi='Mickallv:BAAANQADCgcIBwAAAA==.',
My='Mylodon:BAAANQABCgIIAwAAAA==.Mysternia:BAAANQADCggIGwAAAA==.',
Ni='Niade:BAAANQAECgcIEAAAAA==.',
No='Notorckrag:BAAANQAECgYIDgAAAA==.',
Ny='Nythor:BAAANQADCgMIAwAAAA==.Nythoz:BAAANQADCggICAABNQAECgkJHQAQADkkAA==.',
['Nê']='Nêz:BAAANQADCgYIDAAAAA==.',
Oa='Oathbringer:BAAANQADCgYICQAAAA==.',
Ob='Obtutas:BAAANQABCgYICgAAAA==.',
Od='Odimeer:BAAANQADCggIGgAAAA==.',
Of='Offbrandcleo:BAAANQABCgYIBwAAAA==.',
Ol='Oldrecipe:BAAANQAECgcIEwAAAA==.Oliange:BAAANQAECgMIBAAAAA==.',
Oo='Oopsrofl:BAAANQAECgEIAgAAAA==.',
Or='Originalgank:BAAANQAECgUIEgAAAA==.',
Ot='Otoha:BAAANQADCgYIBgAAAA==.',
Pe='Peachcobbler:BAAANQAECgYIBgAAAA==.',
Pi='Pinkchadp:BAAANQADCgcIBwAAAA==.Pinkk:BAAANQAECgIIAgAAAA==.',
Pl='Plaguerism:BAAANQAECgcICwABNQAFFAIIAgABAAAAAA==.',
Po='Poo:BAABNQAECoEeAAINAAkJJR44BQAWAwANAAkJJR44BQAWAwAAAA==.Pooq:BAAANQAECgEIAQAAAA==.Popcorn:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.',
Pr='Promkang:BAAANQADCgUICQAAAA==.',
['Pâ']='Pâiñ:BAAANQADCgcICwAAAA==.',
Qm='Qmpell:BAAANQADCgYIBgAAAA==.',
Ra='Ragel:BAAANQAECgIIAgAAAA==.Rahor:BAAANQAECgIIAgAAAA==.Rainesage:BAAANQAECgMIBAAAAA==.Ralphel:BAAANQADCgYIEgAAAA==.Razzberry:BAAANQADCgQIBAAAAA==.',
Rh='Rhubarb:BAAANQAECgYICgAAAA==.',
Ro='Rohiem:BAAANQADCgMIAwAAAA==.',
Ry='Rylosh:BAABNQAECoEhAAIDAAkJARAtDwAxAgADAAkJARAtDwAxAgAAAA==.',
Sa='Sabot:BAAANQADCggIGwAAAA==.Sashafierce:BAAANQAECgEIAQAAAA==.',
Sc='Scottpaladin:BAAANQAECgQIBgAAAA==.',
Se='Seath:BAAANQADCgYIEAABNQAECgYIDQABAAAAAA==.',
Sh='Shamerica:BAABNQAECoEeAAIIAAkJ2yG1CABhAwAIAAkJ2yG1CABhAwAAAA==.Shielderon:BAAANQADCgYIBgAAAA==.Shmooythefox:BAAANQADCgYICgAAAA==.Shòckwave:BAAANQAECgEIAgAAAA==.',
Sk='Skilleaz:BAAANQAECgcIEwAAAA==.',
Sl='Slagothor:BAAANQAECgcIDgAAAA==.',
So='Soultax:BAAANQADCggIEQAAAA==.',
Sp='Spekaleks:BAAANQAECgIIAgAAAA==.Spinfat:BAABNQAECoEbAAIHAAkJaiFaAwBsAwAHAAkJaiFaAwBsAwAAAA==.Spiritbox:BAAANQADCgEIAQAAAA==.',
St='Stapler:BAAANQAECgYIEQAAAA==.Starbux:BAAANQADCgUIDQABNQAECgQIBwABAAAAAA==.',
Su='Sugarr:BAAANQADCgYIBgAAAA==.',
Sy='Syb:BAAANQADCgYIDAAAAA==.',
Ta='Taeyang:BAAANQAECgcIEAAAAA==.Tamerlein:BAAANQADCgUIBQAAAA==.Tankadin:BAAANQADCgcIBwABNQAECgMIBAABAAAAAA==.Tanookii:BAAANQAECgEIAgAAAA==.',
Te='Terraform:BAAANQADCgEIAQAAAA==.',
Th='Theinsider:BAAANQAECgQICAABNQAECgYIDQABAAAAAA==.Theoutsider:BAAANQAECgYIDQAAAA==.',
Ti='Timhair:BAAANQADCgUIBQAAAA==.Tindril:BAAANQADCgYIBgAAAA==.',
To='Toekneess:BAAANQAFFAEIAQAAAA==.Toekneezz:BAAANQAECgUICgABNQAFFAEIAQABAAAAAA==.Totemofbear:BAAANQAECgEIAQAAAA==.',
Tr='Trandis:BAAANQAECgcIDgAAAA==.Tranza:BAAANQAECgMIBAAAAA==.Trash:BAAANQAECgEIAQAAAA==.',
Tx='Tx:BAABNQAECoEYAAIIAAkJWh6aDwAMAwAIAAkJWh6aDwAMAwAAAA==.',
Ty='Tyrannius:BAAANQADCgUIBQAAAA==.',
Ut='Uthros:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.Utterchaos:BAAANQAECgQIBAAAAA==.',
Va='Vaporeon:BAAANQADCggIEAAAAA==.',
Ve='Vekris:BAAANQABCgIIAgAAAA==.',
We='Wematanye:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Wetheals:BAAANQAECgEIAQAAAA==.',
Wi='Wimpykid:BAAANQADCgIIAgAAAA==.Winter:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Wo='Worgnfreeman:BAAANQAECggIBAAAAA==.',
Wt='Wtfmonk:BAABNQAECoEXAAIRAAcJ8xQ4EAC8AQARAAcJ8xQ4EAC8AQABNQAECggIDAABAAAAAA==.',
Xa='Xazia:BAAANQADCgEIAQAAAA==.',
Xe='Xethani:BAAANQADCggIGwAAAA==.',
Xo='Xorcopressor:BAAANQADCgIIAgAAAA==.',
Xs='Xsaber:BAAANQADCgYIDwAAAA==.',
Ya='Yazmo:BAABNQAECoEdAAIQAAkJOSSEAQC7AwAQAAkJOSSEAQC7AwAAAA==.',
Yu='Yuuky:BAAANQAECgYIEQAAAA==.',
Za='Zarivia:BAAANQADCgQIBAAAAA==.',
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
