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

local lookup = {'DeathKnight-Frost','DeathKnight-Blood','Shaman-Elemental','Priest-Holy','DemonHunter-Devourer','Unknown-Unknown','Warrior-Protection','Paladin-Retribution','Mage-Frost','Mage-Arcane','Warrior-Arms','Warlock-Affliction','Warlock-Demonology','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Evoker-Preservation','Warrior-Fury','Shaman-Restoration','Druid-Restoration','Druid-Balance','Paladin-Holy','Warlock-Destruction',}
local provider = {region='US',realm='ThoriumBrotherhood',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Absolver:BAAANQADCgUIBQAAAA==.',
Ad='Adabisi:BAAANQADCgEIBAAAAA==.Addu:BAAANQADCgMIAwAAAA==.Adiforis:BAABNQAECoEZAAMBAAgKoRDgNQDEAQABAAgKoRDgNQDEAQACAAMKcQWXmACKAAAAAA==.Adobo:BAABNQAECoEvAAIDAAgKGhbpRQAyAgADAAgKGhbpRQAyAgAAAA==.',
Al='Aljeron:BAAANQADCgIJAgAAAA==.Allysson:BAAANQAECgUIDQAAAA==.Alrekur:BAAANQADCgEIAQAAAA==.Alyestra:BAAANQAECgMIAwAAAA==.',
An='Anipaltu:BAAANQAECggIEwABNQAECggIJQAEAO4eAA==.Aniron:BAAANQAECgUICQABNQAECggIJQAEAO4eAA==.Anirot:BAABNQAECoElAAIEAAgK7h4/JAC+AgAEAAgK7h4/JAC+AgAAAA==.Annalissa:BAAANQADCgYIBgAAAA==.',
Ar='Aranta:BAAANQAECgQICwAAAA==.Arieldhas:BAAANQADCggIFQAAAA==.',
As='Astren:BAAANQAECgUIDgAAAA==.Asynsia:BAABNQAECoEhAAIFAAgK+yGCDAALAwAFAAgK+yGCDAALAwAAAA==.',
Av='Avamani:BAAANQADCgcIGAAAAA==.',
['Aõ']='Aõnar:BAAANQADCgEIAQAAAA==.',
Ba='Bartholomew:BAAANQAECgMIBAABNQAECgkJNQAEAKQbAA==.',
Be='Beertje:BAAANQAECgEIAgAAAA==.Bellemore:BAAANQAECgIIAgAAAA==.',
Bi='Bienfaiseur:BAAANQAECgYIEwAAAA==.Bigdamhero:BAAANQADCgIIAgAAAA==.',
Bl='Blackbird:BAAANQADCgQIBAAAAA==.Blackcode:BAAANQAECgYICwAAAA==.',
Br='Breadbringer:BAAANQADCggICwAAAA==.',
Bu='Buckshotapie:BAAANQADCgIIAgAAAA==.Bulgrim:BAAANQADCgYIDQAAAA==.Bunrÿl:BAAANQAECgIIAgAAAA==.Busterheiman:BAAANQADCgUIBQAAAA==.Butterrz:BAAANQADCgMIAwABNQAECgUICgAGAAAAAA==.',
Ce='Cearylin:BAAANQADCggIEQAAAA==.Cerealkillah:BAAANQADCgMIAwAAAA==.',
Ch='Chasy:BAAANQADCgIIAgABNQAECgUICQAGAAAAAA==.Cheerwine:BAAANQADCggICAAAAA==.Cherypoptart:BAAANQAECgUIDgAAAA==.Chrismeister:BAAANQAECgEIAQAAAA==.',
Ci='Citrate:BAAANQADCggIDAAAAA==.',
Co='Coraggioso:BAAANQAECgIIAgAAAA==.Corbenik:BAAANQAECgYIEQAAAA==.',
Cr='Crodock:BAAANQABCgQIBgAAAA==.',
Cy='Cypress:BAAANQADCgYIBgAAAA==.',
['Cä']='Cähira:BAAANQADCgYIDwAAAA==.',
Da='Dainaira:BAAANQAECgUICgAAAA==.Daisia:BAAANQABCgIIAgAAAA==.Darowen:BAAANQAECggIDQAAAA==.Daul:BAAANQAECggIDwAAAA==.',
De='Delti:BAAANQADCgUIBQABNQAECgYIEQAGAAAAAA==.Demonsmind:BAAANQAECgYIEgAAAA==.Derien:BAABNQAECoEhAAIHAAgKzBrTCwBPAgAHAAgKzBrTCwBPAgAAAA==.Devlyn:BAAANQADCgYIFgAAAA==.',
Do='Donkeyteeth:BAAANQAECgYICgAAAA==.',
Dr='Dromak:BAAANQAECgUIAwAAAA==.Drynn:BAAANQADCgYIBgAAAA==.Drywater:BAAANQAECgUIEQAAAA==.',
El='Elfblood:BAAANQAECgYIEwAAAA==.Elvion:BAAANQADCgQIBAAAAA==.',
Em='Emitsabah:BAAANQADCgUIBQAAAA==.Emongar:BAAANQABCgYICgAAAA==.',
Fa='Fabulosa:BAAANQAECgcIDQAAAA==.Faith:BAAANQAECgIIAgAAAA==.',
Fi='Finite:BAAANQADCgYICAABNQAECgcIGAAIAEYSAA==.Firebug:BAAANQAECgUICQAAAA==.',
Fl='Flyke:BAAANQAECgUICgAAAA==.Flyscrossmap:BAAANQADCgIIAgAAAA==.',
Fn='Fnwarlock:BAAANQADCgYIFgAAAA==.',
Fr='Frieren:BAACNQAFFIEXAAMJAAcKrhPAAgDYAAAKAAUKHxWLFQCjAQAJAAMKEwzAAgDYAAA1AAQKgRwAAwoACQoZIo41ABEDAAoACQoZIo41ABEDAAkAAQp2HR0/ADYAAAAA.',
Fu='Furnok:BAAANQAECgYIEQAAAA==.',
Ga='Galethia:BAAANQADCgUIBgAAAA==.Garmjackyl:BAAANQADCgMIAQAAAA==.',
Gh='Ghandaloren:BAAANQADCgUIBQAAAA==.Ghia:BAAANQADCgUIBQABNQAECgEIAgAGAAAAAA==.Ghortash:BAAANQABCgYJCwAAAA==.Ghutz:BAABNQAECoEtAAILAAgKABMUeAAMAgALAAgKABMUeAAMAgAAAA==.',
Go='Gonja:BAAANQADCgQIBAAAAA==.',
Gu='Gumbercules:BAAANQAECgYIEwAAAA==.',
Ha='Harina:BAAANQABCgMIAgAAAA==.',
He='Hearthglen:BAAANQAECgUICQAAAA==.',
Ho='Hollet:BAAANQAECgEIAgAAAA==.Holykill:BAAANQAECgYIEwAAAA==.',
Hu='Hunttard:BAAANQADCggIHAAAAA==.',
Hy='Hydrack:BAAANQADCgYIBAAAAA==.Hylen:BAABNQAECoEbAAMMAAkKyxI9CADnAQAMAAcKNBY9CADnAQANAAMK1giAEQFgAAAAAA==.',
['Hë']='Hëllboy:BAAANQABCgMIAwAAAA==.',
Ib='Ibrandul:BAAANQAECgcIEwAAAA==.',
Ic='Iceepop:BAAANQABCgMIAwAAAA==.',
Ir='Iroha:BAAANQADCgMIAwAAAA==.Ironhuntress:BAAANQAECgMIAwAAAA==.',
It='Ithro:BAAANQAECgcIDQAAAA==.',
Iy='Iyachtu:BAAANQADCgEIAQAAAA==.',
Ja='Jarlo:BAAANQAECgUIEAAAAA==.',
Je='Jeffarg:BAAANQAECgEIAQABNQAECggIJwAOAO4ZAA==.Jefficiently:BAABNQAECoEnAAQOAAgK7hmsTgBbAgAOAAgK2BesTgBbAgAPAAYKVgwkOwBJAQAQAAQKzRgwCwATAQAAAA==.Jestus:BAAANQADCgQIAwAAAA==.',
Jo='Jormungandr:BAAANQAECgcIEQAAAA==.',
Ju='Juandolf:BAAANQADCggIFgAAAA==.Juanhunglow:BAAANQADCgUICgAAAA==.Jularity:BAAANQAECgEJAQAAAA==.',
Ka='Kadryan:BAAANQADCgcIDQAAAA==.Kaeldric:BAAANQAECgIIAgAAAA==.Kairilynn:BAAANQAECgEIAQAAAA==.Kalinea:BAABNQAECoEeAAIOAAkKAQ+/UwBNAgAOAAkKAQ+/UwBNAgAAAA==.',
Ke='Kellice:BAAANQAECgEIAQAAAA==.Keruptadin:BAAANQAECgEIAgAAAA==.',
Kh='Khedriss:BAAANQAECgYIEgAAAA==.',
Ko='Konerik:BAAANQABCgQJDgAAAA==.Kope:BAABNQAECoEhAAIRAAgKix0ADgC1AgARAAgKix0ADgC1AgAAAA==.',
Kr='Krugor:BAAANQAECgEIAgAAAA==.Kruptis:BAAANQADCgQIBAAAAA==.Kryptikz:BAAANQADCgEIAQABNQAECgUICgAGAAAAAA==.Krystoferson:BAAANQAECgUICAAAAA==.',
Ku='Kurdis:BAAANQABCgUIBwAAAA==.',
['Kà']='Kàw:BAAANQADCggJIAAAAA==.',
La='Labiy:BAAANQADCgYIBgAAAA==.Lalatína:BAAANQADCgYIBgAAAA==.',
Le='Leelu:BAAANQABCgMIAwABNQADCgYIDwAGAAAAAA==.Leianii:BAAANQADCggIHgAAAA==.',
Lh='Lhondar:BAAANQADCgYICgAAAA==.',
Li='Lifehammer:BAAANQADCggICAABNQAECggIIQAFAHgbAA==.Likkaru:BAAANQADCgMIBAAAAA==.Liljess:BAAANQADCgYJBgABNQAECgMIAwAGAAAAAA==.Lillat:BAAANQAECgMIBAAAAA==.Littlepop:BAAANQADCgcIDQAAAA==.',
Lu='Luciamar:BAAANQADCggICAABNQAFFAUIEgARAFUUAA==.Lumi:BAAANQADCgYIEgAAAA==.',
['Lì']='Lìesson:BAEANQAECgcIEQAAAA==.',
Ma='Mackaroni:BAAANQADCgEIAQABNQAECgEIAgAGAAAAAA==.Magesca:BAAANQAECgYIEgAAAA==.Makkagg:BAABNQAECoEXAAISAAYK4BeLDgChAQASAAYK4BeLDgChAQABNQAFFAEIAQAGAAAAAA==.',
Me='Megastorm:BAAANQABCgQIBAAAAA==.Merillion:BAAANQABCgIIAgAAAA==.',
Mg='Mghtymage:BAAANQADCggIEwAAAA==.',
Mi='Milagrosa:BAAANQAECgcIDQAAAA==.Millanya:BAAANQADCgcIBwAAAA==.Mirael:BAABNQAECoEtAAIOAAkK/xqWJgDeAgAOAAkK/xqWJgDeAgAAAA==.',
Mo='Mommanoo:BAAANQAECgEIAQAAAA==.Mordenthal:BAAANQAECgEIAQAAAA==.',
My='Mykester:BAAANQABCgIIAgAAAA==.Mykesucks:BAAANQABCgUIBwAAAA==.Myrmia:BAAANQAECgIJAgAAAA==.',
Na='Nails:BAAANQADCgYIBgAAAA==.Nargul:BAAANQADCgUIBQAAAA==.Naxximarus:BAAANQADCgYIBgABNQAECgkJNQAEAKQbAA==.',
Ni='Nightowl:BAAANQABCgIIAgAAAA==.',
No='Nota:BAAANQAECgUICgAAAA==.',
Og='Ogrusao:BAAANQAECgEIAQAAAA==.',
Ol='Olaaru:BAAANQAECgQIBAAAAA==.',
Om='Omelette:BAAANQAECgIJAgAAAA==.',
Pa='Panasaurus:BAAANQAECgYIEQAAAA==.',
Pe='Pelli:BAAANQAECgIIAgAAAA==.Pendraig:BAAANQADCggIGwAAAA==.',
Pi='Pink:BAAANQAECgQIBwAAAA==.',
Ra='Rainedancer:BAABNQAECoEjAAITAAgKkRcmUwDtAQATAAgKkRcmUwDtAQAAAA==.Rat:BAAANQAECgcIBwABNQAFFAUIDAATALQbAA==.Rawriior:BAAANQABCgQIBQAAAA==.Raynez:BAAANQADCgYICAABNQAECgUICgAGAAAAAA==.',
Rh='Rhalek:BAAANQAECgMIBAABNQAECgkJKgAUAAQdAA==.Rheunae:BAAANQAECgEIAQAAAA==.Rhykis:BAAANQAECgUICgAAAA==.',
Ro='Rogztaudru:BAAANQABCgEIAQAAAA==.',
Sa='Sabba:BAAANQAECgEIAQAAAA==.Sableanne:BAAANQAECgcIDgAAAA==.Sacrament:BAAANQAECggIAwABNQAECggIDwAGAAAAAA==.Sagearian:BAAANQAECgEIAQAAAA==.Sapped:BAAANQAFFAEIAQABNQAECgEIAgAGAAAAAA==.Sarinna:BAAANQADCgMIBQAAAA==.',
Se='Seosinz:BAAANQAECgEJAQAAAA==.',
Sh='Shabbyshammy:BAAANQAECgMIAwAAAA==.Shariaan:BAAANQADCggIHAAAAA==.Shaylinn:BAAANQADCgYIFwAAAA==.Shùkkle:BAABNQAECoEiAAIVAAkK5B5sFQAFAwAVAAkK5B5sFQAFAwAAAA==.',
Si='Siella:BAAANQAECgIIAgAAAA==.Sinric:BAAANQAECgMIAwAAAA==.Sitrom:BAAANQADCgIIAgAAAA==.',
Sk='Skorvis:BAACNQAFFIEHAAMTAAMKBhEwHgCJAAATAAIKKgwwHgCJAAADAAIKZQZJIgCHAAA1AAQKgSMAAxMACQpVH6QXAPwCABMACQpVH6QXAPwCAAMABgqaEsp+AHcBAAE1AAUUBQgIABYAYREA.',
Sl='Sloshama:BAAANQAECgQIBQAAAA==.',
Sm='Smallfox:BAAANQADCgUIBQAAAA==.',
Sn='Snayderino:BAAANQADCgcIDAAAAA==.',
So='Solar:BAACNQAFFIEHAAIVAAMK9gudFQDWAAAVAAMK9gudFQDWAAA1AAQKgR4AAhUACQo7HpwjAJQCABUACQo7HpwjAJQCAAAA.Somenai:BAAANQADCgYICgAAAA==.Sora:BAAANQADCgYIBgAAAA==.Soulbaine:BAAANQADCgYIBgAAAA==.',
Sp='Spheria:BAAANQAECgYICQAAAA==.',
Su='Surelyhots:BAAANQAECgUIBgAAAA==.',
Ta='Tankdezoe:BAAANQADCgYJCAABNQAECgMIAwAGAAAAAA==.Tansonite:BAAANQAECgcICAAAAA==.',
Te='Tequ:BAAANQADCgYIFAAAAA==.',
Ti='Timeshade:BAAANQAECgEIAQAAAA==.Tine:BAABNQAECoEhAAIKAAgK3BO0lgA2AgAKAAgK3BO0lgA2AgAAAA==.',
To='Toray:BAAANQAECgMIAwAAAA==.',
Tr='Triplesix:BAAANQAECgYIEQAAAA==.Trittia:BAAANQAECgEIAgAAAA==.Trixzia:BAAANQADCgUIBQABNQAECgIIAwAGAAAAAA==.Troky:BAAANQAECgYIBgAAAA==.',
Ty='Tynk:BAAANQADCgcIDwAAAA==.',
Ug='Ugh:BAEBNQAFFIEKAAICAAUKIB1XCACuAQACAAUKIB1XCACuAQAAAA==.',
Ur='Urza:BAAANQADCgMIAwAAAA==.',
Va='Valethus:BAABNQAECoEdAAIOAAgKgRa8UABVAgAOAAgKgRa8UABVAgAAAA==.Valhuntar:BAAANQAECgUIBgAAAA==.',
Ve='Verlis:BAAANQADCgYIDgAAAA==.Vesp:BAAANQADCggIDwAAAA==.Veylla:BAAANQAECgIIAwAAAA==.',
Wa='Walkz:BAAANQAECgUICgAAAA==.Warkkagg:BAAANQAFFAEIAQAAAA==.',
We='Weékly:BAAANQADCgUICQAAAA==.',
Wi='Wickedlight:BAAANQAECgYIDgAAAA==.Wickedlock:BAAANQADCgQIBAAAAA==.Willscarlet:BAAANQAECgMIAwAAAA==.',
Xu='Xunn:BAAANQADCgIIAgAAAA==.',
Yl='Ylkhalas:BAAANQADCgcIFQAAAA==.',
Yo='Yolks:BAAANQAECgUICAAAAA==.',
Za='Zamual:BAAANQADCgMIAwAAAA==.Zaritym:BAAANQAECgUICgAAAA==.',
Zi='Zibetha:BAABNQAECoEoAAIXAAkK0RgnBQC/AgAXAAkK0RgnBQC/AgAAAA==.',
Zo='Zoeheals:BAAANQAECgMIAwAAAA==.',
Zu='Zuggtmoy:BAAANQADCgIIBQAAAA==.',
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
