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

local lookup = {'DeathKnight-Frost','DeathKnight-Blood','Shaman-Elemental','Priest-Holy','Paladin-Holy','Druid-Restoration','Druid-Balance','DemonHunter-Devourer','Warrior-Protection','Paladin-Retribution','Priest-Shadow','Paladin-Protection','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Mage-Frost','Mage-Arcane','Shaman-Restoration','Unknown-Unknown','Warrior-Arms','Evoker-Preservation','Rogue-Assassination','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Warrior-Fury','Evoker-Devastation','Rogue-Subtlety','Druid-Feral','DemonHunter-Havoc','Monk-Mistweaver',}
local provider = {region='US',realm='ThoriumBrotherhood',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Absolver:BAAANQADCgYIFAAAAA==.',
Ad='Adabisi:BAAANQADCgEIBAAAAA==.Addu:BAAANQADCgMIAwAAAA==.Adiforis:BAABNQAECn8lAAMBAAoKmBThEgBvAQABAAoKmBThEgBvAQACAAMKcQUwpgCHAAAAAA==.Adobo:BAABNQAECn80AAIDAAkKEBW5RwBYAgADAAkKEBW5RwBYAgAAAA==.Adolhay:BAAANQADCgMIAwAAAA==.',
Al='Aljeron:BAAANQADCgIJAgAAAA==.Allysson:BAABNQAECn8cAAIBAAcKAAu6KQD4AAABAAcKAAu6KQD4AAAAAA==.Alrekur:BAAANQAECgQIBAAAAA==.Alyestra:BAAANQAECgMIAwAAAA==.',
An='Animyst:BAAANQAECgYIEAABNQAECgkJKgAEAHoeAA==.Anipaltu:BAABNQAECn8cAAIFAAkKKx0ZHwD0AgAFAAkKKx0ZHwD0AgABNQAECgkJKgAEAHoeAA==.Aniron:BAAANQAECgUICQABNQAECgkJKgAEAHoeAA==.Anirot:BAABNQAECn8qAAIEAAkKeh65FgAeAwAEAAkKeh65FgAeAwAAAA==.Anithwip:BAAANQADCggICAABNQAECgkJKgAEAHoeAA==.Annalissa:BAAANQADCgYIBgAAAA==.',
Ar='Aranta:BAABNQAECn8YAAMGAAcKVgfmGgDtAAAGAAcKVgfmGgDtAAAHAAMKVQJknQBnAAAAAA==.Arieldhas:BAAANQADCggIGAAAAA==.',
As='Astren:BAAANQAECgUIDgAAAA==.Asynsia:BAABNQAECn8pAAIIAAgKZyFEDQAQAwAIAAgKZyFEDQAQAwAAAA==.',
['Aõ']='Aõnar:BAAANQADCgEIAQAAAA==.',
Ba='Bartholomew:BAAANQAECgMIBAABNQAECgoKPAAEAOUdAA==.',
Be='Beertje:BAAANQAECgEIAgAAAA==.Bellemore:BAAANQAECgMIAgAAAA==.',
Bi='Bienfaiseur:BAABNQAECn8jAAIEAAcKOSYfBADkAgAEAAcKOSYfBADkAgAAAA==.Bigdamhero:BAAANQADCgIIAgAAAA==.Bisonnaire:BAAANQABCgYIBgABNQAECgoKPAAEAOUdAA==.',
Bl='Blackbird:BAAANQADCgQIBAAAAA==.Blackcode:BAAANQAECggIDQAAAA==.',
Br='Breadbringer:BAAANQADCggICwAAAA==.Breezybb:BAAANQADCgQIBAAAAA==.',
Bu='Buckshotapie:BAAANQADCgIIAgAAAA==.Bulgrim:BAAANQADCgYIDQAAAA==.Bunrÿl:BAAANQAECgIIAgAAAA==.Busterheiman:BAAANQADCgYIGAAAAA==.Butterrz:BAAANQADCgMIAwABNQAECgcIGgAJAEkbAA==.',
Ce='Cearylin:BAAANQAECgUICQAAAA==.Cerealkillah:BAAANQADCgMIAwAAAA==.',
Ch='Chasy:BAAANQADCgIIAgABNQAECgcIGQAKAEEOAA==.Cheerwine:BAAANQADCggICAAAAA==.Cherypoptart:BAABNQAECn8fAAILAAgKDR55BgCQAQALAAgKDR55BgCQAQAAAA==.Chrismeister:BAAANQAECgEIAgAAAA==.',
Ci='Citrate:BAAANQADCggIDAAAAA==.',
Co='Coomaka:BAAANQADCgUIBQAAAA==.Coraggioso:BAAANQAECgMIBgAAAA==.Corbenik:BAABNQAECn8iAAIMAAcKBhPgEgD1AAAMAAcKBhPgEgD1AAAAAA==.',
Cr='Crodock:BAAANQABCgQIBgAAAA==.',
Cy='Cypress:BAAANQADCgYIBgAAAA==.',
['Cä']='Cähira:BAAANQADCggIFwAAAA==.',
Da='Dainaira:BAABNQAECn8aAAILAAcKKwgcPgA7AQALAAcKKwgcPgA7AQAAAA==.Daisia:BAAANQABCgIIAgAAAA==.Darowen:BAAANQAECggIDQAAAA==.Daul:BAABNQAECn8VAAIMAAoKwAW+NgAyAQAMAAoKwAW+NgAyAQAAAA==.',
De='Delti:BAAANQADCgUIBQABNQAECgcIIwAIANcbAA==.Demonsmind:BAABNQAECn8WAAQNAAgKewz/HQB+AQANAAcK9Qr/HQB+AQAOAAYK7ggV3wALAQAPAAEKFQt5LQA7AAAAAA==.Derien:BAABNQAECn8pAAIJAAgKvBrHDQBUAgAJAAgKvBrHDQBUAgAAAA==.Devlyn:BAAANQADCgcIHQAAAA==.',
Do='Donkeyteeth:BAAANQAECgcIDwAAAA==.Donkeyteeths:BAAANQAECgcIBgAAAA==.',
Dr='Dromak:BAAANQAECgUIBwAAAA==.Drynn:BAAANQADCgYIBgAAAA==.Drywater:BAABNQAECn8gAAIQAAYK8A+ZFQBTAQAQAAYK8A+ZFQBTAQAAAA==.',
El='Elfblood:BAABNQAECn8jAAINAAcKigf2BQDGAAANAAcKigf2BQDGAAAAAA==.Elvion:BAAANQADCgQIBAAAAA==.',
Em='Emitsabah:BAAANQADCgUIBQAAAA==.Emongar:BAAANQADCgcIBwAAAA==.',
Fa='Fabulosa:BAAANQAECgcIDgAAAA==.Faith:BAAANQAECgUIBgAAAA==.',
Fi='Finite:BAAANQADCgYICAABNQAECggIJAAKAB8VAA==.Firebug:BAAANQAECgUIDAAAAA==.',
Fl='Flyke:BAABNQAECn8YAAIRAAcK2gffeQDLAAARAAcK2gffeQDLAAAAAA==.Flyscrossmap:BAAANQAECgEIAQAAAA==.',
Fn='Fndruid:BAAANQAECgEIAQAAAA==.Fnwarlock:BAAANQAECgEIAQAAAA==.',
Fr='Frieren:BAACNQAFFH8YAAMQAAcKbxQ0BADTAAARAAUKWBfrGwCdAQAQAAMKERA0BADTAAA1AAQKfyQAAxEACgogHgQ9AAwDABEACgogHgQ9AAwDABAAAQp2HUtJADIAAAAA.',
Fu='Furnok:BAABNQAECn8gAAMDAAcK+Q8JhQCYAQADAAcK+Q8JhQCYAQASAAcKbwkjZgCJAAAAAA==.',
Ga='Galethia:BAAANQADCgUIBgAAAA==.Garmjackyl:BAAANQADCgMIAQAAAA==.',
Gh='Ghandaloren:BAAANQADCgUIBQAAAA==.Ghia:BAAANQADCgUIBQABNQAECgEIAgATAAAAAA==.Ghortash:BAAANQABCgYICwAAAA==.Ghutz:BAABNQAECn8+AAIUAAkKYBO6EQDKAQAUAAkKYBO6EQDKAQAAAA==.',
Go='Gonja:BAAANQADCgUICAAAAA==.',
Gr='Grave:BAABNQAECn8wAAMCAAkKCSLFDgA5AwACAAkKCSLFDgA5AwABAAQKpRipLADqAAAAAA==.',
Gu='Gumbercules:BAABNQAECn8iAAIVAAcKbAnlDAD3AAAVAAcKbAnlDAD3AAAAAA==.',
Ha='Harina:BAAANQABCgMIAgAAAA==.',
He='Hearthglen:BAABNQAECn8ZAAIKAAcKQQ5rzACDAQAKAAcKQQ5rzACDAQAAAA==.',
Ho='Hollet:BAAANQAECgQICgAAAA==.Holykill:BAABNQAECn8kAAIMAAgKgwqFEQADAQAMAAgKgwqFEQADAQAAAA==.',
Hu='Hunttard:BAAANQADCggIHAAAAA==.',
Hy='Hydrack:BAAANQADCgYIBAAAAA==.Hylen:BAABNQAECn8iAAMPAAkK2xIXCQD1AQAPAAcKpxcXCQD1AQAOAAMKzQj3GgGRAAAAAA==.',
['Hë']='Hëllboy:BAAANQABCgMIAwAAAA==.',
Ib='Ibrandul:BAABNQAECn8eAAIKAAkK7xBeMwBmAQAKAAkK7xBeMwBmAQAAAA==.',
Ic='Iceepop:BAAANQAECgUIBQAAAA==.',
Ir='Iroha:BAAANQADCgMIAwAAAA==.Ironhuntress:BAAANQAECgQIBQAAAA==.',
It='Ithro:BAABNQAECn8XAAIWAAgKshLeMwAMAgAWAAgKshLeMwAMAgAAAA==.',
Iy='Iyachtu:BAAANQADCgEIAQAAAA==.',
Ja='Jarlo:BAABNQAECn8eAAIWAAcKWxETDwBMAQAWAAcKWxETDwBMAQAAAA==.Jaydeki:BAAANQADCgQIBAAAAA==.',
Je='Jeffarg:BAAANQAECgEIAQABNQAECgkJMwAXADQaAA==.Jefficiently:BAABNQAECn8zAAQXAAkKNBq/QwCgAgAXAAkKLhm/QwCgAgAYAAQKjx2MDAANAQAZAAYKlxbhEAABAQAAAA==.Jestus:BAAANQADCgQIAwAAAA==.',
Jo='Jormungandr:BAABNQAECn8eAAMUAAkKLhTFLABXAQAUAAkKLhTFLABXAQAJAAEKAAClQAA9AAAAAA==.',
Ju='Juandolf:BAAANQAECgMIBAAAAA==.Juanhunglow:BAAANQADCgUIFAAAAA==.Jularity:BAAANQAECgEJAQAAAA==.',
Ka='Kadryan:BAAANQADCgcIDQAAAA==.Kaeldric:BAAANQAECgMIBgAAAA==.Kairilynn:BAAANQAECgEIAQAAAA==.Kalinea:BAABNQAECn8kAAIXAAoKFg8DaABEAgAXAAoKFg8DaABEAgAAAA==.',
Ke='Kellice:BAAANQAECgEIAQAAAA==.Keruptadin:BAAANQAECgYICAAAAA==.',
Kh='Khedriss:BAABNQAECn8VAAIRAAgKtgRbJwFKAQARAAgKtgRbJwFKAQAAAA==.',
Ko='Konerik:BAAANQABCgQIDgAAAA==.Kope:BAABNQAECn8pAAIVAAgKmB94DADdAgAVAAgKmB94DADdAgAAAA==.',
Kr='Krugor:BAAANQAECgMIBgAAAA==.Kruptis:BAAANQADCgQIBAAAAA==.Kryptikz:BAAANQADCgEIAQABNQAECgcIGgAJAEkbAA==.Krystoferson:BAAANQAECgUIEQAAAA==.',
Ku='Kurdis:BAAANQABCgUIBwAAAA==.',
['Kà']='Kàw:BAAANQADCggJIAAAAA==.',
La='Labiy:BAAANQADCgYIDAAAAA==.Lalatína:BAAANQADCgYIBgAAAA==.',
Le='Leelu:BAAANQADCgQIBAABNQADCggIFwATAAAAAA==.Leianii:BAAANQADCggIHgAAAA==.',
Lh='Lhondar:BAAANQADCgYICgAAAA==.',
Li='Lifehammer:BAAANQADCggIDAABNQAECgoKLQAIAOsaAA==.Likkaru:BAAANQADCgMIBAAAAA==.Liljess:BAAANQADCgYJBgABNQAECgMIAwATAAAAAA==.Lillat:BAAANQAECgQIBAAAAA==.Littlepop:BAAANQADCgcIDQAAAA==.',
Lu='Luciamar:BAAANQADCggICAABNQAFFAUIEgAVAFUUAA==.Lumi:BAAANQADCgYIEgAAAA==.Luuggork:BAAANQADCgIIAgAAAA==.',
Ly='Lyarith:BAAANQADCgUIBwAAAA==.',
['Lì']='Lìesson:BAEBNQAECn8YAAIKAAgKARm3dQBCAgAKAAgKARm3dQBCAgAAAA==.',
Ma='Mackaroni:BAAANQADCgEIAQABNQAECgEIAgATAAAAAA==.Magesca:BAABNQAECn8hAAIQAAcKvBWlDADvAQAQAAcKvBWlDADvAQAAAA==.Makkagg:BAABNQAECn8cAAIaAAkKrBUvDQDlAQAaAAkKrBUvDQDlAQAAAA==.',
Me='Megastorm:BAAANQABCgUIBwAAAA==.Merillion:BAAANQABCgIIAgAAAA==.',
Mg='Mghtymage:BAAANQADCggIEwAAAA==.',
Mi='Milagrosa:BAAANQAECgcIEQAAAA==.Millanya:BAAANQADCgcIBwAAAA==.Mirael:BAABNQAECn9BAAIXAAoKfB5xBQB4AgAXAAoKfB5xBQB4AgAAAA==.',
Mo='Mommanoo:BAAANQAECgYICgAAAA==.Mordenthal:BAAANQAECgEIAQAAAA==.',
Mu='Mumshun:BAAANQAECggICAAAAA==.',
My='Mykester:BAAANQABCgIIAgAAAA==.Myrmia:BAAANQAECgIJAgAAAA==.',
Na='Nails:BAAANQADCgYIBgAAAA==.Nanumar:BAAANQAECgYIBgABNQAECggIHQAbAEYWAA==.Natyri:BAAANQAECgUIBwAAAA==.Naxximarus:BAAANQAECggIDgABNQAECgoKPAAEAOUdAA==.',
Ni='Nightowl:BAAANQABCgIIAgAAAA==.Nirazen:BAAANQAECgIIAgAAAA==.',
No='Nota:BAABNQAECn8ZAAIKAAcKtgNoDAEKAQAKAAcKtgNoDAEKAQAAAA==.',
Og='Ogrusao:BAAANQAECgIIAwAAAA==.',
Ol='Olaaru:BAAANQAECgUIBQAAAA==.',
Om='Omelette:BAAANQAECgIJAgAAAA==.',
Pa='Panasaurus:BAABNQAECn8gAAIIAAcK5RdLDgBCAQAIAAcK5RdLDgBCAQAAAA==.',
Pe='Pelli:BAAANQAECgMIBQAAAA==.Pendraig:BAAANQADCggIIgABNQAECgUIBgATAAAAAA==.',
Pi='Pink:BAAANQAECgQIBwAAAA==.',
Po='Popchop:BAAANQAECgEIAQABNQAECgUIBQATAAAAAA==.',
Pu='Purgatorium:BAAANQAECgUIAwAAAA==.',
Ra='Rainedancer:BAABNQAECn8oAAISAAoKuhaSWQAEAgASAAoKuhaSWQAEAgAAAA==.Rat:BAAANQAECggIEQABNQAFFAYIFgASAM4bAA==.Rawriior:BAAANQABCgQIBQAAAA==.Raynez:BAAANQADCgYICAABNQAECgcIGgAJAEkbAA==.',
Rh='Rhalek:BAAANQAECgUIDgABNQAECgoKOwAGAP4dAA==.Rheunae:BAAANQAECgUIBgAAAA==.Rhykis:BAABNQAECn8aAAIUAAcKKSAsMABNAQAUAAcKKSAsMABNAQAAAA==.',
Ro='Rogztaudru:BAAANQABCgEIAQAAAA==.',
Sa='Sabba:BAAANQAECgMIBQAAAA==.Sableanne:BAAANQAECgcIDgAAAA==.Sacrament:BAAANQAECggIBgABNQAECgoKFQAMAMAFAA==.Sagearian:BAAANQAECgEIAQAAAA==.Samanda:BAAANQAECgQICQAAAA==.Samshir:BAAANQAECgUIBQABNQAECggIFQARALYEAA==.Sapped:BAABNQAECn8VAAMWAAkKUg8UMgAWAgAWAAkKUg8UMgAWAgAcAAIKDBSKRgBLAAABNQAECgEIAgATAAAAAA==.Sarinna:BAAANQADCgMIBQAAAA==.',
Se='Seosinz:BAAANQAECgEIAQAAAA==.',
Sh='Shabbyshammy:BAAANQAECgUIBQAAAA==.Shariaan:BAAANQAECgEIAQAAAA==.Shaylinn:BAAANQADCgcIHgAAAA==.Shùkkle:BAABNQAECn8lAAIHAAkKLh1BGgD2AgAHAAkKLh1BGgD2AgAAAA==.',
Si='Siella:BAAANQAECgMIBgAAAA==.Sinric:BAAANQAECgMIAwAAAA==.Sitrom:BAAANQAECgIIAgAAAA==.',
Sk='Skorvis:BAACNQAFFH8NAAMSAAMKOxaAFgD1AAASAAMKOxaAFgD1AAADAAMKZQYJKQCFAAA1AAQKfygAAxIACgrqHdgeAO8CABIACgrqHdgeAO8CAAMABgp8EHeEAJkBAAE1AAUUBggLAAUAFxAA.',
Sl='Sloshama:BAAANQAECgQIBQAAAA==.',
Sm='Smallfox:BAAANQADCgUIBQABNQAECgEIAQATAAAAAA==.',
Sn='Snayderino:BAAANQADCgcIDAAAAA==.',
So='Solar:BAACNQAFFH8HAAIHAAMK9gv5GQDUAAAHAAMK9gv5GQDUAAA1AAQKfyQAAwcACgoUHXsqAIUCAAcACgoUHXsqAIUCAB0AAwojDmgNAMsAAAAA.Somenai:BAAANQADCgYICgAAAA==.Sora:BAAANQADCgYIBgAAAA==.Soulbaine:BAAANQADCgYIBgAAAA==.',
Sp='Spheria:BAABNQAECn8WAAIOAAcK9gXyXwDCAAAOAAcK9gXyXwDCAAAAAA==.',
Su='Surelyhots:BAAANQAECgcIEQAAAA==.',
Ta='Tankdezoe:BAAANQADCgYJCAABNQAECgMIAwATAAAAAA==.Tansonite:BAABNQAECn8ZAAMMAAoKDAknNgA2AQAMAAcK7QwnNgA2AQAKAAkKAAKDVAGZAAAAAA==.',
Te='Tequ:BAAANQADCgcIGwAAAA==.',
Ti='Timeshade:BAAANQAECgEIAQAAAA==.Tine:BAABNQAECn8pAAIRAAgKaxPGqQAuAgARAAgKaxPGqQAuAgAAAA==.',
To='Toray:BAAANQAECgMIAwAAAA==.',
Tr='Triplesix:BAABNQAECn8fAAIeAAgKthIgDwBzAQAeAAgKthIgDwBzAQAAAA==.Trittia:BAAANQAECgEIAgAAAA==.Trixzia:BAAANQADCgUIBQABNQAECgIIAwATAAAAAA==.Troky:BAAANQAECgYICwAAAA==.',
Ty='Tynk:BAAANQADCggIFwAAAA==.',
Ug='Ugh:BAEBNQAFFH8MAAICAAYKyhlxCwCeAQACAAYKyhlxCwCeAQAAAA==.',
Ur='Urza:BAAANQADCgMIAwAAAA==.',
Va='Vaewind:BAAANQADCgQIBAAAAA==.Valethus:BAABNQAECn8oAAMXAAgK/hfJWwBiAgAXAAgK/hfJWwBiAgAZAAEKAADfTAAAAAAAAA==.Valhuntar:BAAANQAECgYIEQAAAA==.',
Ve='Velleria:BAAANQAECgUIBQAAAA==.Verlis:BAAANQADCggIFgAAAA==.Vesp:BAAANQADCggIDwAAAA==.Veylla:BAAANQAECgIIAwAAAA==.',
Wa='Walkz:BAABNQAECn8aAAIJAAcKSRuwEAAdAgAJAAcKSRuwEAAdAgAAAA==.Warkkagg:BAABNQAECn8gAAIOAAoKHRi0BwAtAgAOAAoKHRi0BwAtAgABNQAECgkJHAAaAKwVAA==.Waterworks:BAAANQAECgEIAQAAAA==.',
We='Weékly:BAAANQAECgQIBgAAAA==.',
Wi='Wickedlight:BAABNQAECn8dAAILAAcKOhrdBwB3AQALAAcKOhrdBwB3AQAAAA==.Wickedlock:BAAANQADCgQIBAAAAA==.Willscarlet:BAAANQAECgQIAwAAAA==.',
Xu='Xunn:BAAANQADCgIIAgAAAA==.',
Yl='Ylkhalas:BAAANQAECgQIBAAAAA==.',
Yo='Yolks:BAAANQAECgcIEwAAAA==.',
Za='Zamual:BAAANQADCgMIAwAAAA==.Zaritym:BAABNQAECn8bAAIfAAcKfhugCQA9AQAfAAcKfhugCQA9AQAAAA==.',
Ze='Zelsada:BAAANQADCgcIBwAAAA==.',
Zi='Zibetha:BAABNQAECn8yAAINAAkKDxuKAwAJAwANAAkKDxuKAwAJAwAAAA==.',
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
