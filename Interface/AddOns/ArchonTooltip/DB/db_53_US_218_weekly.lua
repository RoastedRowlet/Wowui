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

local lookup = {'DeathKnight-Frost','DeathKnight-Blood','Shaman-Elemental','Priest-Holy','Paladin-Holy','Druid-Restoration','Druid-Balance','DemonHunter-Devourer','Mage-Fire','Mage-Arcane','Mage-Frost','Unknown-Unknown','Warrior-Protection','Paladin-Retribution','Priest-Shadow','Paladin-Protection','DemonHunter-Vengeance','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Shaman-Restoration','Warrior-Arms','Evoker-Preservation','Rogue-Assassination','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Rogue-Subtlety','Warrior-Fury','Evoker-Augmentation','Evoker-Devastation','Druid-Feral','Druid-Guardian','Priest-Discipline','DemonHunter-Havoc','Monk-Mistweaver',}
local provider = {region='US',realm='ThoriumBrotherhood',name='US',type='weekly',zone=53,date='2026-11-03',data={Ad='Adabisi:BAAANQADCgEIBwAAAA==.Addu:BAAANQAECgEIAQAAAA==.Adiforis:BAABNQAECn8sAAMBAAoK2BRpNgD/AQABAAoK2BRpNgD/AQACAAMKcQUwpgCHAAAAAA==.Adobo:BAACNQAFFH8FAAIDAAIK6wjzGwBwAAADAAIK6wjzGwBwAAA1AAQKfz4AAgMACgr+ErlHAFgCAAMACgr+ErlHAFgCAAAA.Adolhay:BAAANQADCgMIAwAAAA==.',
Ai='Aigle:BAAANQADCgEIAgAAAA==.',
Al='Aljeron:BAAANQADCgIJAgAAAA==.Allysson:BAABNQAECn8jAAIBAAcKWgsqXwApAQABAAcKWgsqXwApAQAAAA==.Alrekur:BAAANQAFFAEIAgAAAA==.Alyestra:BAAANQAECgMIAwAAAA==.',
An='Animyst:BAAANQAECgYIEQABNQAECgoKLwAEAP8fAA==.Anipaltu:BAABNQAECn8cAAIFAAkKKx0ZHwD0AgAFAAkKKx0ZHwD0AgABNQAECgoKLwAEAP8fAA==.Aniron:BAAANQAECgYIEAABNQAECgoKLwAEAP8fAA==.Anirot:BAABNQAECn8vAAIEAAoK/x+5FgAeAwAEAAoK/x+5FgAeAwAAAA==.Anithwip:BAAANQADCggICAABNQAECgoKLwAEAP8fAA==.Annabelz:BAAANQADCgEIAQAAAA==.Annalissa:BAAANQADCgYIBwAAAA==.',
Ar='Aranta:BAABNQAECn8YAAMGAAcKVgfQPQDWAAAGAAcKVgfQPQDWAAAHAAMKVQJknQBnAAAAAA==.Argon:BAAANQADCgMIAQAAAA==.Arieldhas:BAAANQADCggIGAAAAA==.Arissarel:BAAANQADCgEIAQAAAA==.',
As='Astren:BAAANQAECgUIDwAAAA==.Asynsia:BAABNQAECn8zAAIIAAoKviBEDQAQAwAIAAoKviBEDQAQAwAAAA==.',
Av='Avamani:BAAANQAECgEIAgAAAA==.',
['Aõ']='Aõnar:BAAANQADCgEIAQAAAA==.',
Ba='Bartholomew:BAAANQAECgMIBAABNQAECgoKRQAEAOUfAA==.',
Be='Beertje:BAAANQAECgEIAgAAAA==.Bellemore:BAAANQAECgMIAgAAAA==.',
Bh='Bhattle:BAAANQAECgQICQAAAA==.',
Bi='Bienfaiseur:BAABNQAECn8sAAIEAAcKXCbFFgD0AgAEAAcKXCbFFgD0AgAAAA==.Bigdamhero:BAAANQADCgIIBQAAAA==.Bisonnaire:BAAANQAECgEIAQABNQAECgoKRQAEAOUfAA==.',
Bl='Blackbird:BAAANQADCgQIBAAAAA==.Blackcode:BAABNQAECn8bAAQJAAoKTg23BwC4AAAKAAgKkwy4ugAHAQAJAAQKjQ+3BwC4AAALAAIKgQy2NQBkAAAAAA==.',
Bo='Boombawks:BAAANQAECgIIAgABNQAECgQIBAAMAAAAAA==.',
Br='Breadbringer:BAAANQADCggIFAAAAA==.Breezybb:BAAANQADCgQIBQAAAA==.Brewfist:BAAANQADCgEIAQAAAA==.',
Bu='Buckshotapie:BAAANQADCgIIAwAAAA==.Bulgrim:BAAANQADCgYIEAAAAA==.Bunrÿl:BAAANQAECgIIAgAAAA==.Busterheiman:BAAANQAECgEIAgAAAA==.Butterrz:BAAANQADCgMIAwABNQAECgkJHgANABgaAA==.',
Ca='Caseopiea:BAAANQADCgYIBgAAAA==.',
Ce='Cearylin:BAABNQAECn8YAAIEAAgKLAPRhgALAQAEAAgKLAPRhgALAQAAAA==.Cerealkillah:BAAANQADCgMIAwAAAA==.',
Ch='Chasy:BAAANQADCgIIAgABNQAECgkJIgAOAAkOAA==.Cheerwine:BAAANQADCggICAAAAA==.Cherypoptart:BAABNQAECn8tAAIPAAoK7B+zBwDNAgAPAAoK7B+zBwDNAgAAAA==.Chrismeister:BAAANQAECgQIBgAAAA==.',
Ci='Citrate:BAAANQADCggIDAAAAA==.',
Co='Contradict:BAAANQADCggIBgABNQAECgoKMAAOAHUVAA==.Coomaka:BAAANQADCgUIBQAAAA==.Coraggioso:BAAANQAECgMIDAAAAA==.Corbenik:BAABNQAECn8oAAIQAAcKBhPLKgCHAQAQAAcKBhPLKgCHAQAAAA==.',
Cr='Crethasmus:BAAANQAECgQIBAAAAA==.Crodock:BAAANQADCgEIAgAAAA==.',
Cy='Cypress:BAAANQADCgYIBgAAAA==.',
['Cä']='Cähira:BAAANQAECgEIAQAAAA==.',
Da='Dainaira:BAABNQAECn8fAAIPAAkK8AeeIwAsAQAPAAkK8AeeIwAsAQAAAA==.Daisia:BAAANQABCgIIAgAAAA==.Darowen:BAAANQAECggIDQAAAA==.Daul:BAABNQAECn8dAAIQAAoKZQzDJgAGAQAQAAoKZQzDJgAGAQAAAA==.',
De='Delti:BAAANQADCgUIBgABNQAECggILQARAJIaAA==.Demonsmind:BAABNQAECn8dAAQSAAoKLg3/HQB+AQASAAcK9Qr/HQB+AQATAAkKcwpwpwDRAAAUAAEKFQt5LQA7AAAAAA==.Derien:BAABNQAECn8zAAINAAoKxRjlCgDcAQANAAoKxRjlCgDcAQAAAA==.Devlyn:BAAANQADCgcIIwAAAA==.',
Do='Donkeyteeth:BAAANQAECgcIDwAAAA==.Donkeyteeths:BAAANQAECgYIEgAAAA==.Dorana:BAAANQAECggIAgAAAA==.',
Dr='Dromak:BAAANQAECgYIBwAAAA==.Drusila:BAAANQAECgYICwAAAA==.Drynn:BAAANQADCgYIBgAAAA==.Drywater:BAABNQAECn8pAAILAAcK1w2ZFQBTAQALAAcK1w2ZFQBTAQAAAA==.',
El='Elfblood:BAABNQAECn8xAAISAAcK3AcsDwDDAAASAAcK3AcsDwDDAAAAAA==.Elvion:BAAANQADCgQIBQAAAA==.',
Em='Emitsabah:BAAANQADCgUIBQAAAA==.Emongar:BAAANQADCgcICAAAAA==.',
Fa='Fabulosa:BAAANQAECgcIDgAAAA==.Faith:BAAANQAECgUIBgAAAA==.',
Fe='Felesta:BAAANQAECgEIAQAAAA==.Femidan:BAAANQAECgEIAQABNQAECgQIBAAMAAAAAA==.',
Fi='Finite:BAAANQAECgUIBAABNQAECgoKMAAOAHUVAA==.Firebug:BAABNQAECn8UAAINAAcKRAYdJAClAAANAAcKRAYdJAClAAAAAA==.',
Fl='Flyke:BAABNQAECn8jAAIKAAoKfAm1bACpAQAKAAoKfAm1bACpAQAAAA==.Flyscrossmap:BAAANQAECgUIBwAAAA==.',
Fn='Fndruid:BAAANQAECgEIAQAAAA==.Fnwarlock:BAAANQAECgQIBgAAAA==.',
Fu='Furnok:BAABNQAECn8sAAMVAAcKbBROTACuAQAVAAcKbBROTACuAQADAAcKKxEJhQCYAQAAAA==.',
Ga='Galethia:BAAANQADCgUIBgAAAA==.Garmjackyl:BAAANQADCgMIAQAAAA==.',
Gh='Ghandaloren:BAAANQADCgUIBQAAAA==.Ghia:BAAANQADCgUIBQABNQAECgEIAgAMAAAAAA==.Ghortash:BAAANQADCgEIAgAAAA==.Ghrim:BAAANQAECgYICQAAAA==.Ghutz:BAABNQAECn9MAAMWAAoKyxPOSAD1AQAWAAoKyxPOSAD1AQANAAUKlgmQIgCxAAAAAA==.',
Go='Gonja:BAAANQADCgUICAAAAA==.',
Gr='Grave:BAABNQAECn9CAAMCAAoKniItBwAGAwACAAoKniItBwAGAwABAAQKpRgtaAC/AAAAAA==.',
Gu='Gumbercules:BAABNQAECn8vAAIXAAcKkg15FwA9AQAXAAcKkg15FwA9AQAAAA==.',
Ha='Haastur:BAAANQADCgEIAQAAAA==.Harina:BAAANQADCgEIAQAAAA==.',
He='Hearthglen:BAABNQAECn8iAAIOAAkKCQ4BnABUAQAOAAkKCQ4BnABUAQAAAA==.',
Ho='Hollet:BAAANQAECgUIDwAAAA==.Holykill:BAABNQAECn8mAAIQAAgK/QrnKgDqAAAQAAgK/QrnKgDqAAAAAA==.',
Hu='Hunttard:BAAANQAECgUICAAAAA==.',
Hy='Hydrack:BAAANQADCgYIBAAAAA==.Hylen:BAABNQAECn8sAAMUAAoKwRIXCQD1AQAUAAcKpxcXCQD1AQATAAUKLAxCpgDTAAAAAA==.',
['Hë']='Hëllboy:BAAANQADCgEIAgAAAA==.',
Ib='Ibrandul:BAABNQAECn8iAAIOAAoKVhEXbwCyAQAOAAoKVhEXbwCyAQAAAA==.',
Ic='Iceepop:BAAANQAECgUIBQAAAA==.',
Ir='Iroha:BAAANQADCgMIBAAAAA==.Ironhuntress:BAAANQAECgUIBwAAAA==.',
It='Ithro:BAABNQAECn8kAAIYAAoK4xKQDADeAQAYAAoK4xKQDADeAQAAAA==.',
Iy='Iyachtu:BAAANQADCgEIAQAAAA==.',
Ja='Jarlo:BAABNQAECn8eAAIYAAcKWxH+HQAjAQAYAAcKWxH+HQAjAQAAAA==.Jaydeki:BAAANQADCgQIBAAAAA==.',
Je='Jeffarg:BAAANQAECgEIAQABNQAECgoKRgAZAFUcAA==.Jefficiently:BAABNQAECn9GAAQZAAoKVRy3FAC9AQAaAAkKqRy/QwCgAgAZAAkKqhS3FAC9AQAbAAQKjx2MDAANAQAAAA==.Jefriel:BAAANQAECgEIAgABNQAECgoKRgAZAFUcAA==.Jestus:BAAANQADCgQIBwAAAA==.',
Ji='Jinsoftpaw:BAAANQAECgQIBAAAAA==.',
Jo='Joolianm:BAACNQAFFH8aAAMLAAcKbxQ0BADTAAAKAAUKWBfrGwCdAQALAAMKERA0BADTAAA1AAQKfzQABAoACgrtIq4lAIwCAAoACgrtIq4lAIwCAAsAAwqMG8sUAAkBAAkAAwpVIK0FAKYAAAAA.Jormungandr:BAABNQAECn8rAAMWAAoK1xmjLQBjAgAWAAoK1xmjLQBjAgANAAEKAAClQAA9AAAAAA==.',
Ju='Juandolf:BAAANQAECgUIDAAAAA==.Juanhunglow:BAAANQADCgUIFgAAAA==.Jularity:BAAANQAECgEJAQAAAA==.',
Ka='Kadryan:BAAANQADCgcIEwAAAA==.Kaeldric:BAAANQAECgQIDAAAAA==.Kaijinryu:BAAANQADCgEIAQAAAA==.Kairilynn:BAAANQAECgEIAQAAAA==.Kalemshai:BAAANQAECgUIDAAAAA==.Kalinea:BAABNQAECn8lAAIaAAoKhRADaABEAgAaAAoKhRADaABEAgAAAA==.',
Ke='Kellice:BAAANQAECgEIAQAAAA==.Keruptadin:BAAANQAECgYICAAAAA==.',
Kh='Khedriss:BAABNQAECn8aAAIKAAgKyARbJwFKAQAKAAgKyARbJwFKAQAAAA==.',
Ko='Kokonotsu:BAAANQADCgEIAgAAAA==.Konerik:BAAANQADCgEIAQAAAA==.Kope:BAABNQAECn8zAAIXAAoK+x6YBAAZAwAXAAoK+x6YBAAZAwAAAA==.',
Kr='Krugor:BAAANQAECgQICQAAAA==.Kruptis:BAAANQADCgQIBAAAAA==.Kryptikz:BAAANQADCgEIAQABNQAECgkJHgANABgaAA==.Krystoferson:BAABNQAECn8WAAIcAAUK1gPvkwCQAAAcAAUK1gPvkwCQAAAAAA==.',
Ku='Kurdis:BAAANQADCgEIAQAAAA==.',
['Kà']='Kàw:BAAANQADCggIIwAAAA==.',
La='Labiy:BAAANQADCgYIDAAAAA==.Lalatína:BAAANQADCgYIBgAAAA==.',
Le='Leelu:BAAANQADCgQIBQABNQAECgEIAQAMAAAAAA==.Leianii:BAAANQAECgUICAAAAA==.',
Lh='Lhondar:BAAANQAECgUICAAAAA==.',
Li='Lifehammer:BAAANQADCggIDAABNQAECgoKQgAIAL4dAA==.Likkaru:BAAANQADCgMIBAAAAA==.Liljess:BAAANQADCgYJBgABNQAECgUIBAAMAAAAAA==.Lillat:BAAANQAECgQIBAAAAA==.Lin:BAAANQADCggICQAAAA==.Littlepop:BAAANQADCgcIDQAAAA==.',
Lu='Luciamar:BAAANQADCggICAABNQAFFAUIEgAXAFUUAA==.Lumi:BAAANQADCgYIEwAAAA==.Luuggork:BAAANQADCgIIAgAAAA==.Luxfire:BAAANQADCgQIBAAAAA==.',
Ly='Lyarith:BAAANQADCgUICAAAAA==.',
['Lì']='Lìesson:BAEBNQAECn8lAAIOAAoK9R0yLQCDAgAOAAoK9R0yLQCDAgAAAA==.',
Ma='Mackaroni:BAAANQADCgEIAQABNQAECgEIAgAMAAAAAA==.Magesca:BAABNQAECn8uAAILAAcK4xWlDADvAQALAAcK4xWlDADvAQAAAA==.Makkagg:BAABNQAECn8jAAIdAAkKZhkvDQDlAQAdAAkKZhkvDQDlAQABNQAFFAIIBQATAIMVAA==.Malersia:BAAANQADCgEIAQAAAA==.Markymark:BAAANQAECgIIBAAAAA==.',
Me='Megastorm:BAAANQADCgEIAgAAAA==.Merillion:BAAANQADCgEIAQAAAA==.',
Mg='Mghtymage:BAAANQADCggIFAAAAA==.',
Mi='Miereynna:BAAANQADCgUIBQAAAA==.Milagrosa:BAABNQAECn8hAAIeAAoKFw1GBwCZAQAeAAoKFw1GBwCZAQAAAA==.Millanya:BAAANQAECgEIAQAAAA==.Mirael:BAACNQAFFH8KAAIaAAMKLww9EgDeAAAaAAMKLww9EgDeAAA1AAQKf00AAhoACgrvH5EaALYCABoACgrvH5EaALYCAAAA.',
Mo='Mommanoo:BAAANQAECgYICgAAAA==.Mordenthal:BAAANQAECgEIAQABNQAECgUIBgAMAAAAAA==.',
Mu='Mumshun:BAAANQAECggICAAAAA==.Mumsnielf:BAAANQAECggICAAAAA==.',
My='Mykester:BAAANQADCgEIAQAAAA==.Mykesucks:BAAANQAECgEIAQAAAA==.Myrmia:BAAANQAECgIJAgAAAA==.',
Na='Nails:BAAANQADCgYIBwAAAA==.Nanumar:BAAANQAECgYIBgABNQAECggIJAAfAGAXAA==.Nargul:BAAANQAECgQIAwAAAA==.Natyri:BAABNQAECn8UAAIIAAkKLA4SHACRAQAIAAkKLA4SHACRAQAAAA==.Naxximarus:BAAANQAECgcIEAABNQAECgoKRQAEAOUfAA==.',
Ne='Nelapywind:BAAANQADCgEIAQAAAA==.',
Ni='Nightowl:BAAANQADCgEIAgAAAA==.Nirazen:BAAANQAECgUICAAAAA==.',
No='Nota:BAABNQAECn8dAAIOAAkKJgRoDAEKAQAOAAkKJgRoDAEKAQAAAA==.',
Og='Ogrusao:BAAANQAECgQICAAAAA==.',
Ol='Olaaru:BAAANQAECgUIBQAAAA==.',
Om='Omelette:BAAANQAECgIJAgAAAA==.',
Pa='Panasaurus:BAABNQAECn8uAAMIAAcK5RfXKwDjAQAIAAcK5RfXKwDjAQARAAcK/AesFgC7AAAAAA==.',
Pe='Pelli:BAAANQAECgQIDAAAAA==.Pendraig:BAAANQAECgEIAgABNQAECgUIEAAMAAAAAA==.',
Pi='Pink:BAAANQAECgQIBwAAAA==.',
Pl='Plaza:BAAANQAECggIAwAAAA==.',
Po='Popchop:BAAANQAECgUIBQABNQAECggIEgAMAAAAAA==.',
Pu='Purgatorium:BAAANQAECggICQAAAA==.',
Ra='Rainedancer:BAABNQAECn80AAIVAAoKAxpfKwBIAgAVAAoKAxpfKwBIAgAAAA==.Rat:BAAANQAECggIEQABNQAFFAYIFgAVAM4bAA==.Ratatosk:BAAANQAECgYIBwAAAA==.Rawriior:BAAANQADCgEIAgAAAA==.Raynez:BAAANQADCgYICAABNQAECgkJHgANABgaAA==.',
Rh='Rhalek:BAABNQAECn8hAAIGAAkKRiJ3BgBJAwAGAAkKRiJ3BgBJAwAAAA==.Rheunae:BAAANQAECgUIEAAAAA==.Rhykis:BAABNQAECn8eAAIWAAkKTB9NQQAQAgAWAAkKTB9NQQAQAgAAAA==.',
Ro='Rogztaudru:BAAANQADCgEIAQAAAA==.Rogzundlock:BAAANQADCgEIAQAAAA==.',
Ry='Ryleigh:BAAANQADCgYIBgAAAA==.',
Sa='Sabba:BAAANQAECgQICwAAAA==.Sableanne:BAAANQAECgcIEAAAAA==.Sacrament:BAAANQAECggIBgABNQAECgoKHQAQAGUMAA==.Sagearian:BAAANQAECgIIBAAAAA==.Samanda:BAABNQAECn8XAAIgAAcKVhCtEgBQAQAgAAcKVhCtEgBQAQAAAA==.Samshir:BAAANQAECgUIBwABNQAECggIGgAKAMgEAA==.Sapped:BAABNQAECn8VAAMYAAkKUg8UMgAWAgAYAAkKUg8UMgAWAgAcAAIKDBQySgBoAAABNQAECgEIAgAMAAAAAA==.Sarinna:BAAANQADCgMIBQAAAA==.',
Se='Seosinz:BAAANQAECggIAQAAAA==.',
Sh='Shabbyshammy:BAAANQAECggIDQAAAA==.Shariaan:BAAANQAECgEIAQAAAA==.Shaylinn:BAAANQADCgcIJAAAAA==.Shùkkle:BAABNQAECn8lAAIHAAkKLh1BGgD2AgAHAAkKLh1BGgD2AgAAAA==.',
Si='Siella:BAAANQAECgQIDAAAAA==.Sinric:BAAANQAECgMIAwAAAA==.Sitrom:BAAANQAECgIIAgAAAA==.',
Sk='Skorvis:BAACNQAFFH8QAAMVAAMKOxaAFgD1AAAVAAMKOxaAFgD1AAADAAMKlQs8GQCIAAA1AAQKfy8AAxUACgoGHtgeAO8CABUACgoGHtgeAO8CAAMABwrtE3eEAJkBAAE1AAUUBwgMAAUAxhAA.',
Sl='Sloshama:BAAANQAECgQIBQAAAA==.',
Sm='Smallfox:BAAANQADCgUIBQABNQAECgQIBAAMAAAAAA==.',
Sn='Snayderino:BAAANQADCgcIDQAAAA==.',
So='Solar:BAACNQAFFH8HAAIHAAMK9gv5GQDUAAAHAAMK9gv5GQDUAAA1AAQKfyoABAcACgofHnsqAIUCAAcACgoUHXsqAIUCACAAAwojDpIgALcAACEAAQqUGGhXAEcAAAAA.Somenai:BAAANQADCgYICgAAAA==.Sonofmums:BAAANQAECggIAgAAAA==.Sora:BAAANQADCgYIBgAAAA==.Soulbaine:BAAANQADCgYIBgAAAA==.',
Sp='Spheria:BAABNQAECn8kAAITAAcKdwdYnADoAAATAAcKdwdYnADoAAAAAA==.',
Su='Surelyhots:BAABNQAECn8YAAQiAAgKWwbvBgA0AQAiAAgKWwbvBgA0AQAPAAEKlAT1ewAxAAAEAAEKpgHp6QAkAAAAAA==.',
Ta='Tankdezoe:BAAANQAECgMIBgABNQAECgUIBAAMAAAAAA==.Tansonite:BAABNQAECn8rAAMQAAoK2w14GQByAQAQAAoK2w14GQByAQAOAAkKAAKDVAGZAAAAAA==.',
Te='Tequ:BAAANQADCgcIIAAAAA==.',
Th='Thanosoferos:BAAANQADCgEIAQAAAA==.Thiberius:BAAANQADCgQIBAAAAA==.Thrazul:BAAANQADCgYICQAAAA==.',
Ti='Timeshade:BAAANQAECgEIAQAAAA==.Tine:BAABNQAECn8zAAIKAAoKyhLgUAD2AQAKAAoKyhLgUAD2AQAAAA==.',
To='Toray:BAAANQAECgcICgAAAA==.',
Tr='Trinn:BAAANQADCgQIBAAAAA==.Triplesix:BAABNQAECn8gAAIjAAgKthLQMgBGAQAjAAgKthLQMgBGAQAAAA==.Trittia:BAAANQAECgEIAgAAAA==.Trixzia:BAAANQADCgUIBQABNQAECgIIAwAMAAAAAA==.Troky:BAAANQAECggIEgAAAA==.',
Ty='Tynk:BAAANQAECgEIAQAAAA==.',
Ug='Ugh:BAEBNQAFFH8XAAICAAcKyCBYAwDbAQACAAcKyCBYAwDbAQAAAA==.',
Ur='Urza:BAAANQADCgMIAwAAAA==.',
Va='Vaewind:BAAANQADCgUIBQAAAA==.Valethus:BAABNQAECn84AAMaAAoKQhdzTwDwAQAaAAoKQhdzTwDwAQAZAAEKAACMcwAAAAAAAA==.Valhuntar:BAABNQAECn8kAAIaAAgKLxGKdQCKAQAaAAgKLxGKdQCKAQAAAA==.Varhanu:BAAANQADCgEIAQAAAA==.',
Ve='Velleria:BAAANQAECgUICAAAAA==.Verlis:BAAANQADCggIGAAAAA==.Vesp:BAAANQADCggIDwAAAA==.Veylla:BAAANQAECgIIAwAAAA==.',
Wa='Walkz:BAABNQAECn8eAAINAAkKGBqXDAC3AQANAAkKGBqXDAC3AQAAAA==.Warkkagg:BAACNQAFFH8FAAITAAIKgxUSHACiAAATAAIKgxUSHACiAAA1AAQKfycAAhMACgrfG5YyABcCABMACgrfG5YyABcCAAAA.Waterworks:BAAANQAECgEIAwABNQAECgQIBAAMAAAAAA==.',
We='Weékly:BAAANQAECgQIBgAAAA==.',
Wi='Wickedlight:BAABNQAECn8tAAIPAAgKohngHwA8AgAPAAgKohngHwA8AgAAAA==.Wickedlock:BAAANQADCgQIBQAAAA==.Willscarlet:BAAANQAECgQIAwAAAA==.',
Xu='Xunn:BAAANQADCgIIAgAAAA==.',
Yl='Ylkhalas:BAAANQAECgQIBQAAAA==.',
Yo='Yolks:BAABNQAECn8YAAIVAAgKeREoZABXAQAVAAgKeREoZABXAQAAAA==.',
Za='Zaareth:BAAANQAECgUICgAAAA==.Zamual:BAAANQADCgMIBQAAAA==.Zaritym:BAABNQAECn8fAAIkAAkKZBrxDgDnAQAkAAkKZBrxDgDnAQAAAA==.',
Ze='Zelsada:BAAANQADCgcIBwAAAA==.',
Zi='Zibetha:BAABNQAECn89AAISAAoKUxyKAwAJAwASAAoKUxyKAwAJAwAAAA==.',
Zo='Zoeheals:BAAANQAECgUIBAAAAA==.',
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
