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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Paladin-Protection','Shaman-Elemental','DeathKnight-Blood','Paladin-Holy','Evoker-Preservation','Evoker-Augmentation','Druid-Guardian','Warrior-Arms','Druid-Feral','Warlock-Affliction','Shaman-Restoration','Unknown-Unknown','Paladin-Retribution','Shaman-Enhancement','DemonHunter-Devourer','Hunter-BeastMastery','Mage-Arcane','Mage-Frost','Mage-Fire','Monk-Mistweaver','Priest-Holy','Priest-Discipline','Hunter-Marksmanship','Druid-Balance','Druid-Restoration','Hunter-Survival','Warrior-Fury','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Protection',}
local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abaddon:BAAANQAECgUIDQAAAA==.',
Ac='Ackris:BAABNQAECn81AAMBAAkKQiSNBwCPAwABAAkKQiSNBwCPAwACAAEKmRA4dwA2AAAAAA==.',
Ag='Agolan:BAAANQAECgQICAAAAA==.',
Al='Aldric:BAEANQAECgcIDAABNQAFFAYIFAADAAsjAA==.Alkaios:BAAANQAECgIIAgABNQAECgcIHwADAH8RAA==.Alucarddalv:BAAANQAECgQICQAAAA==.',
Am='Amaimon:BAAANQAECgUIBQABNQAFFAUIDwAEAMsRAA==.Amalthaea:BAAANQADCgcIBwABNQAECgcIHQAFAH4OAA==.Amnoon:BAABNQAECn8iAAIGAAgKFhJJZADoAQAGAAgKFhJJZADoAQAAAA==.Amri:BAABNQAECn8XAAMHAAcKgBVxHwDbAQAHAAcKgBVxHwDbAQAIAAMKmQ6eGwCIAAABNQAECggIKwAJAMEcAA==.',
An='Andarnáurram:BAAANQADCggICAAAAA==.',
Ap='Apoly:BAAANQADCgUIBQAAAA==.',
Aq='Aquas:BAAANQADCgEIAQAAAA==.',
Ar='Ardrhys:BAAANQAECgIIAgAAAA==.Arknem:BAAANQABCgQIBQAAAA==.Artikin:BAAANQAFFAEIAQABNQAFFAQIBwAKAPkLAA==.',
As='Assasinateu:BAAANQADCgIIAgAAAA==.Asûná:BAABNQAECn8aAAILAAcKYxaFEgDTAQALAAcKYxaFEgDTAQAAAA==.',
At='Atlas:BAABNQAECn8ZAAMCAAcK5B0FIwBYAQABAAUKpxhtowCJAQACAAQKTR8FIwBYAQAAAA==.',
Au='Auroxa:BAABNQAECn8aAAMMAAcKNBjKCQDgAQAMAAYKJhrKCQDgAQABAAMKMBKiCAG0AAAAAA==.Automagic:BAAANQADCgYICwAAAA==.',
Av='Avondwella:BAABNQAECn8ZAAIKAAgKMxRpfwAZAgAKAAgKMxRpfwAZAgAAAA==.',
Az='Azorah:BAAANQADCggIEQAAAA==.',
Ba='Bacevicius:BAAANQAECggIDAAAAA==.Baldyguy:BAAANQAECgQICgAAAA==.Balm:BAAANQAECgYIDAAAAA==.',
Be='Beastlybull:BAAANQAECgcIDAABNQAFFAcIGgANAOkeAA==.',
Bi='Biblepimp:BAAANQAECggIEAAAAA==.Bigfries:BAAANQADCgQIBgAAAA==.Bigsneak:BAAANQAECgIJAwAAAA==.',
Bl='Blackmarker:BAAANQAECgUIDAAAAA==.Blemish:BAAANQADCgEIAQABNQAECgYIDAAOAAAAAA==.Bloodpac:BAAANQADCgEIAQAAAA==.',
Bo='Boadica:BAAANQADCgIIAgAAAA==.Bobsuruncle:BAAANQAECgEIAQAAAA==.Bodyguardwyn:BAAANQAECgIIBQAAAA==.Bolvar:BAABNQAECn8gAAIPAAgK9RZVcwBEAgAPAAgK9RZVcwBEAgAAAA==.Bonedjovi:BAABNQAECn8dAAIFAAcKfg7UZQBYAQAFAAcKfg7UZQBYAQAAAA==.Boondiggles:BAAANQAECgUICwAAAA==.',
Br='Brathelore:BAAANQADCggICgAAAA==.Bremitox:BAAANQAECgMIAwABNQAECgcIHwADAH8RAA==.Brimscythe:BAAANQADCgIIAQAAAA==.Brud:BAAANQAECgUIDwAAAA==.',
By='Byakugan:BAACNQAFFH8PAAIEAAUKyxGEDQCSAQAEAAUKyxGEDQCSAQA1AAQKfyIAAwQACQokHFhAAHECAAQACAoSH1hAAHECABAAAQqRCtwzAD8AAAAA.',
['Bø']='Bønitalèè:BAAANQAECgUICAAAAA==.',
Ca='Cain:BAAANQADCgQIBAAAAA==.Calvisi:BAAANQAECgMIAwAAAA==.Calvisichaos:BAAANQAECgYIEQAAAA==.Canthen:BAAANQAECggIAgAAAA==.',
Cc='Cc:BAAANQAFFAEIAQAAAA==.',
Ch='Chaoticbacon:BAAANQADCgYIBgABNQAECgEIAgAOAAAAAA==.',
Co='Cosmicsage:BAAANQADCgYIBgAAAA==.Cosmicspark:BAABNQAECn8cAAIPAAcKywwAzQB7AQAPAAcKywwAzQB7AQAAAA==.',
Cr='Crentist:BAAANQAFFAIIAgAAAA==.Cropala:BAAANQAECgUIDAAAAA==.',
Da='Darkwingduck:BAAANQADCgQJBAAAAA==.Darkøne:BAAANQABCgMIAwAAAA==.Davros:BAAANQADCgYIDAABNQAECgEIAQAOAAAAAA==.',
De='Dellandre:BAAANQAECgQIBwABNQAECgcIHgADAEMRAA==.Delta:BAAANQAECgcIDwAAAA==.Delti:BAAANQADCggICAABNQAECgcIHQARANcbAA==.Destrõ:BAAANQAECgIIAgAAAA==.',
Di='Diabolist:BAABNQAECn8bAAIBAAkKeAuYhQDTAQABAAkKeAuYhQDTAQAAAA==.Dielma:BAAANQAECgUICQABNQAFFAMIBgACAL8VAA==.',
Dk='Dkdozer:BAAANQADCgYJDAABNQAECgEIAQAOAAAAAA==.',
Do='Doktaga:BAAANQAECgQIDgAAAA==.',
Dr='Draetanìa:BAAANQADCgYIBgAAAA==.Drakonna:BAAANQADCgUIBQAAAA==.Drarken:BAABNQAECn8gAAIHAAgKORs8FABqAgAHAAgKORs8FABqAgAAAA==.Drtapo:BAAANQAECgIIAwAAAA==.Drustdar:BAAANQADCgEIAQAAAA==.',
El='Elderr:BAAANQAECgcICgAAAA==.Eldhe:BAAANQADCgIIAgAAAA==.Elistrae:BAABNQAECn8eAAISAAgKECMSKQDyAgASAAgKECMSKQDyAgAAAA==.',
En='Enazen:BAAANQAECgcIDwAAAA==.',
Er='Ereshkigal:BAAANQADCgYJBgAAAA==.Ergo:BAACNQAFFH8XAAMTAAYKOg9fIAB+AQATAAUKUwxfIAB+AQAUAAIKsBEiCACXAAA1AAQKfyMAAhMACQoXHhpdAMUCABMACQoXHhpdAMUCAAAA.',
Ev='Evelake:BAAANQAECgIIAgAAAA==.',
Ex='Exon:BAAANQAECgYICwAAAA==.',
Fa='Faded:BAAANQAECgEIAQABNQAECgUIEwAOAAAAAA==.Fadednight:BAAANQAECgUIEwAAAA==.',
Fe='Femcel:BAAANQAECgcIEQAAAA==.Femcelibate:BAAANQAECgQIBgAAAA==.',
Fi='Fivebones:BAAANQAECgMIAwABNQAECgkJOQASAAcjAA==.',
Fl='Flacidheals:BAAANQABCgEIAQAAAA==.Flashlol:BAABNQAECn8WAAMGAAcKaw0UgQCTAQAGAAcKaw0UgQCTAQAPAAcKVQdA7gA5AQAAAA==.',
Fr='Freecookies:BAAANQAECgUIBgAAAA==.Frostytotems:BAAANQADCgQIBwAAAA==.',
Fu='Furryiosa:BAAANQADCgYIBgAAAA==.',
Ga='Gabagool:BAABNQAECn8WAAQUAAYKqw+9GAAvAQAUAAUKiA+9GAAvAQATAAYKdAxYNgEuAQAVAAEKkxBRDQA3AAAAAA==.',
Ge='Gerbert:BAAANQABCgIIAgAAAA==.',
Gh='Ghostë:BAABNQAECn8ZAAIWAAkKbwpwHgCfAQAWAAkKbwpwHgCfAQAAAA==.',
Gi='Gishmou:BAABNQAECn8cAAINAAcKJR0nRgBGAgANAAcKJR0nRgBGAgAAAA==.',
Go='Goodlight:BAAANQAECgEIAQAAAA==.',
Gu='Gutted:BAACNQAFFH8XAAIFAAYKYyagAQCfAgAFAAYKYyagAQCfAgA1AAQKfycAAgUACQqZJmACAM0DAAUACQqZJmACAM0DAAAA.',
Ha='Hanna:BAAANQAECgcICQABNQAFFAYIFwAFAGMmAA==.',
He='Hellmaw:BAAANQAECgQIBwAAAA==.',
Ho='Hollowheart:BAAANQAECgUICwAAAA==.Holycourtney:BAAANQADCgQIBAAAAA==.Holyfur:BAABNQAECn8bAAMXAAYKvhFskgBZAQAXAAYKwBBskgBZAQAYAAEKixFPKAAzAAAAAA==.',
Hy='Hylanna:BAAANQAECgEIAQAAAA==.',
Ic='Ici:BAABNQAECn8UAAMPAAcKuAYX9wApAQAPAAcKuAYX9wApAQAGAAEKHwLYMgEhAAAAAA==.',
Id='Idobutidont:BAAANQADCgIIAgAAAA==.',
If='Iffybacon:BAAANQAECgEIAQABNQAECgEIAgAOAAAAAA==.',
In='Intensifies:BAABNQAECn8bAAIEAAcKVhJ8cwDCAQAEAAcKVhJ8cwDCAQAAAA==.',
Is='Iskothar:BAAANQAECgYIEgAAAA==.',
Iv='Ivarboneless:BAAANQAECgYIDgAAAA==.',
Ja='Jace:BAAANQADCgYIBgAAAA==.Jackz:BAAANQADCggIEgAAAA==.Jackzlock:BAAANQAECgUICQAAAA==.Jak:BAACNQAFFH8IAAMSAAMKSxF4GQDrAAASAAMKSxF4GQDrAAAZAAIK0AKGHwBxAAA1AAQKfyQAAxIACQqoHEwtAOQCABIACQqoHEwtAOQCABkABgrRCkVFACoBAAAA.Jambii:BAAANQAECgUIEwAAAA==.Jattsz:BAEANQADCggICAAAAA==.Jayreezy:BAAANQAECgYICAAAAA==.',
Je='Jerawokee:BAAANQAECgUIEgAAAA==.',
Ji='Jirachii:BAAANQAECgQIBAABNQAECggIJwAaAF4XAA==.',
Jo='Jonah:BAABNQAECn8fAAICAAkK8RpsBADkAgACAAkK8RpsBADkAgAAAA==.Joshcalcjr:BAABNQAECn8cAAQaAAkKNRK6SADCAQAaAAgKPBG6SADCAQAJAAYK+Q2YLQAnAQAbAAIKowWFbABMAAAAAA==.',
Ka='Kaelthàs:BAAANQADCgcIBwAAAA==.Kaessatha:BAEANQADCgIIAgABNQADCgYIMQAOAAAAAA==.Kalika:BAAANQADCgIIAgAAAA==.',
Ke='Ketesh:BAABNQAECn8rAAMJAAgKwRz9EQA9AgAJAAcKwRz9EQA9AgALAAEKAADFOgBIAAAAAA==.Kezanplague:BAABNQAECn8jAAMcAAgKWh4xBACqAgAcAAgKAhsxBACqAgASAAcKmhzZYwBLAgAAAA==.',
Ko='Kodeack:BAAANQADCgIJAgAAAA==.Kortona:BAAANQAECgIIAwAAAA==.',
Kr='Krej:BAAANQAECgQIBAABNQAFFAQIBwAKAPkLAA==.',
['Kø']='Købioshi:BAAANQADCggICwAAAA==.',
La='Landrey:BAAANQADCgYIEwAAAA==.Laoghaire:BAAANQADCggIGAAAAA==.Laszarei:BAABNQAECn8WAAIEAAcKqwRItAAlAQAEAAcKqwRItAAlAQAAAA==.',
Le='Leonz:BAACNQAFFH8YAAIdAAYKuh1CAAA5AgAdAAYKuh1CAAA5AgA1AAQKfzkAAh0ACQp8Jn4AANgDAB0ACQp8Jn4AANgDAAAA.Lethadestro:BAEANQADCgYIBwABNQAECgYIGgAeAC4ZAA==.Letharanos:BAEBNQAECn8aAAMeAAYKLhmISACUAQAeAAYKLhmISACUAQAFAAQK1wgNngCaAAAAAA==.',
Li='Liraffemynn:BAAANQAECgYICgAAAA==.',
Lo='Lohfall:BAAANQADCgUIBgABNQAECgcIHgAfAHIZAA==.Lonranir:BAAANQADCggIEQAAAA==.',
Lu='Luckylucy:BAAANQADCgUIBgAAAA==.Lunoria:BAABNQAECn8iAAIBAAkKGCTaBgCWAwABAAkKGCTaBgCWAwAAAA==.',
Ma='Madarauchiha:BAABNQAECn8aAAMeAAkKJBwzEgD5AgAeAAkKExwzEgD5AgAfAAUK5xbndgA6AQAAAA==.Madeirà:BAAANQADCgQJBAAAAA==.Magus:BAAANQAECgEIAQAAAA==.Maldran:BAAANQAECgUIDQAAAA==.Manderpants:BAAANQADCgQIBAAAAA==.Marien:BAABNQAECn8WAAIFAAgKGRYtPgAGAgAFAAgKGRYtPgAGAgAAAA==.Maxus:BAAANQAECgQIBQAAAA==.',
Mb='Mbbin:BAABNQAECn8tAAMTAAkKDCWJDwCVAwATAAkKDCWJDwCVAwAUAAIKaRQjNgBhAAAAAA==.',
Me='Meems:BAAANQABCgQIBAAAAA==.Mehuman:BAABNQAECn8cAAIPAAcKdxiyowDUAQAPAAcKdxiyowDUAQAAAA==.Mehumanhuntr:BAAANQAECgIIAgAAAA==.Mehumanlock:BAABNQAECn8fAAICAAcKCBKeEgDeAQACAAcKCBKeEgDeAQAAAA==.Melgibson:BAABNQAECn8VAAIDAAgK9BqtFgBFAgADAAgK9BqtFgBFAgAAAA==.Meworgendk:BAAANQADCgcICQAAAA==.',
Mi='Miräj:BAAANQAECgMJBAAAAA==.Mistyblue:BAAANQAECgEIAQAAAA==.Miya:BAAANQADCgUIBQAAAA==.',
Mo='Mojomugambe:BAAANQAECgcIDwAAAA==.Moodacritz:BAAANQADCgYIBgAAAA==.Moonscale:BAAANQAECgEIAQAAAA==.Morel:BAAANQADCgQIBAAAAA==.Mortstan:BAABNQAECn80AAIFAAkKqSQoBwCGAwAFAAkKqSQoBwCGAwAAAA==.',
Mu='Mutegen:BAAANQADCgYIBgAAAA==.',
Na='Nailz:BAABNQAECn8dAAMRAAcK1xsWJwAIAgARAAcKZBoWJwAIAgAgAAMKwRw5HgDZAAAAAA==.',
Ne='Neloangelo:BAAANQAECgQIBwAAAA==.',
Ni='Nightflame:BAAANQADCgYIBgAAAA==.Nightlion:BAABNQAECn8aAAIJAAcKVxuJEwAlAgAJAAcKVxuJEwAlAgAAAA==.',
No='Noahpal:BAAANQAECgUIBQABNQAECgUICgAOAAAAAA==.Noahshaman:BAACNQAFFH8VAAIEAAYK/Rm0BgAKAgAEAAYK/Rm0BgAKAgA1AAQKfzYAAwQACQoFI54OAHMDAAQACQoFI54OAHMDAA0ACAojIAcjANkCAAE1AAQKBQgKAA4AAAAA.Noahwarlock:BAAANQAECgUICgAAAA==.Nonsensical:BAAANQADCgQIBQABNQADCgYIEAAOAAAAAA==.Notbacon:BAAANQAECgEIAQABNQAECgEIAgAOAAAAAA==.Noxander:BAAANQADCgMJAwAAAA==.',
Nu='Nuanakk:BAAANQAECgYIAQAAAA==.',
Oa='Oaths:BAAANQAECgQICQAAAA==.',
Oh='Ohmylanta:BAAANQAECgEIAQAAAA==.Ohmylänta:BAABNQAECn8rAAMSAAkKnhhtRACcAgASAAkKnhhtRACcAgAcAAEKqQBdFQAUAAAAAA==.',
Or='Orandrok:BAAANQAECgEIAQAAAA==.Ormond:BAAANQAECgUIBgAAAA==.',
['Oâ']='Oâth:BAABNQAECn8ZAAMgAAgKAgoEFgBIAQAgAAgKAgoEFgBIAQARAAEK3QMGdAAiAAAAAA==.',
Pa='Paldozer:BAAANQAECgEIAQAAAA==.Pallyman:BAAANQADCgUIBQAAAA==.Pallywacker:BAABNQAECn8bAAIDAAYKPBEUKwCAAQADAAYKPBEUKwCAAQAAAA==.Panzerkìn:BAAANQADCgUIBQAAAA==.',
Pe='Peythilly:BAAANQADCggJDAAAAA==.',
Pi='Pigishdog:BAABNQAECn8sAAIBAAkKTxe+VgBOAgABAAkKTxe+VgBOAgAAAA==.',
Po='Poob:BAAANQADCgcJEwAAAA==.',
Qu='Quinn:BAAANQAECgUIEAAAAA==.',
Ra='Raedon:BAAANQADCgQIBAAAAA==.Ragerunner:BAAANQADCgQIBAAAAA==.',
Re='Redthing:BAAANQADCgYICwAAAA==.Retributíon:BAAANQAECgMIAwABNQAECgkJOQAhAIQlAA==.',
Ri='Rixas:BAAANQAECggIEQABNQAECgkJNQABAEIkAA==.Rixis:BAAANQADCgQIBAAAAA==.',
Ro='Rockafella:BAAANQADCgYICgAAAA==.Roguehiro:BAAANQAECgMIBgAAAA==.Rooter:BAACNQAFFH8TAAIHAAcKxBvXAgBuAgAHAAcKxBvXAgBuAgA1AAQKfyoAAgcACQrHJG8DAIADAAcACQrHJG8DAIADAAAA.Rozetta:BAAANQADCgQIBAAAAA==.',
Ru='Ruto:BAAANQADCgIIAgAAAA==.',
Sa='Samshara:BAAANQADCgIIAgABNQAECgYIGQASAIkbAA==.Saptapper:BAAANQADCgcIBwAAAA==.',
Sc='Scrawni:BAABNQAECn8hAAIJAAgKcR1mCwCxAgAJAAgKcR1mCwCxAgABNQAFFAQIBwAKAPkLAA==.',
Se='Selyane:BAAANQABCgYIDgAAAA==.Seongpal:BAECNQAFFH8UAAIDAAYKCyMAAQCHAgADAAYKCyMAAQCHAgA1AAQKfyYAAgMACQr/JWkDAIoDAAMACQr/JWkDAIoDAAAA.Seraphinà:BAAANQADCggIDQABNQAECgUICwAOAAAAAA==.Serbingium:BAAANQAECgEIAQABNQAFFAMIBgACAL8VAA==.',
Sh='Shadowfur:BAAANQADCgIIAgABNQAECgYIGwAXAL4RAA==.Shadowlight:BAAANQAECgIJAgABNQAECgIJAwAOAAAAAA==.Shamygravy:BAAANQAECgIIAgAAAA==.Sharreth:BAAANQAECgEIAQAAAA==.Shimera:BAABNQAECn8bAAISAAcK2wjArQCkAQASAAcK2wjArQCkAQAAAA==.Shodam:BAAANQAECgIIAgAAAA==.Shootrmcgavn:BAACNQAFFH8HAAMZAAMKwxe2FADtAAAZAAMKwxe2FADtAAASAAEKAAByMwBRAAA1AAQKfy8AAxkACQpHJV4FAHkDABkACQq9I14FAHkDABIACAquJIYeABwDAAAA.',
Si='Sittingmoose:BAAANQAECgYICgAAAA==.',
Sk='Sklormp:BAACNQAFFH8GAAMCAAMKvxUBDQCgAAABAAIKcRY4LQCiAAACAAIKrBEBDQCgAAA1AAQKfx0ABAEACQpGHXAvAMYCAAEACQoJHXAvAMYCAAIAAwpdG+00AO4AAAwAAgrrDcogAHAAAAAA.Skubasteve:BAAANQADCggICAAAAA==.',
Sl='Slootar:BAAANQADCggIDwABNQAECgUIEwAOAAAAAA==.Slugs:BAAANQAECgEIAQAAAA==.',
Sm='Smoruk:BAAANQADCgUIBQAAAA==.',
So='Somerled:BAABNQAECn8ZAAMSAAYKiRsWjADuAQASAAYKiRsWjADuAQAcAAEKPgsHEwA2AAAAAA==.',
Sq='Squatreign:BAABNQAECn8fAAIGAAcKyAZVnwBDAQAGAAcKyAZVnwBDAQAAAA==.',
Sr='Srgtpeppers:BAAANQADCgUIBQAAAA==.',
Su='Sulyvahn:BAEANQAECgUICgABNQAFFAYIFAADAAsjAA==.Sunstrike:BAAANQADCgYIBgAAAA==.',
Sy='Sylvara:BAAANQADCgYIEAAAAA==.',
Ta='Takka:BAAANQAECgcIDAAAAA==.Talkamar:BAAANQAECgcIDwAAAA==.Tarell:BAAANQABCgMIAwAAAA==.Taylorswift:BAABNQAECn8dAAMUAAgKsRZpDQDXAQAUAAYKrBxpDQDXAQATAAcKRxC01gDWAQAAAA==.',
Te='Tehharlequin:BAAANQAECgEIAQAAAA==.',
Th='Thekourge:BAABNQAECn8eAAIDAAcKQxGxLQBsAQADAAcKQxGxLQBsAQAAAA==.Thenard:BAAANQAECgUIDwAAAA==.Therealcafna:BAAANQADCgUIBwAAAA==.Thisle:BAAANQADCgcIKAAAAA==.Thukunamage:BAABNQAECn8tAAITAAkKAyM+EACSAwATAAkKAyM+EACSAwAAAA==.',
Ti='Tigerlord:BAAANQADCggIFQAAAA==.Tili:BAAANQADCgYIGAAAAA==.',
To='Tomislav:BAAANQAECgUICQAAAA==.Touritos:BAAANQAECgYIEwAAAA==.',
Tr='Trimblestein:BAABNQAECn8eAAIKAAgKEiMwSgCoAgAKAAgKEiMwSgCoAgAAAA==.Trohas:BAAANQADCggICAAAAA==.',
Tu='Tuskerdu:BAABNQAECn8iAAIaAAgKDAuMUQCSAQAaAAgKDAuMUQCSAQAAAA==.',
Tw='Twohoofy:BAAANQADCgYIDQAAAA==.',
Ud='Uddermilk:BAAANQAECgQIBgAAAA==.',
Va='Valandrian:BAAANQADCgYICQAAAA==.Valeka:BAABNQAECn8dAAINAAkKThu5JgDHAgANAAkKThu5JgDHAgAAAA==.Valissar:BAAANQABCgcIBwAAAA==.Valr:BAABNQAECn8fAAIDAAcKfxEELQBxAQADAAcKfxEELQBxAQAAAA==.Vandreu:BAAANQAECgQIBgAAAA==.',
Vs='Vse:BAACNQAFFH8IAAIUAAMKjxYSAwDvAAAUAAMKjxYSAwDvAAA1AAQKfyoAAhQACQpqIXcBAHwDABQACQpqIXcBAHwDAAAA.Vsesosorry:BAAANQAECgUICQABNQAFFAMICAAUAI8WAA==.',
We='Weierstrass:BAAANQAECgEIAQABNQAFFAYIFwAFAGMmAA==.Weiyan:BAAANQADCgcIBwAAAA==.',
Wi='Winklebottom:BAAANQADCgcIDAAAAA==.',
Wo='Worgenkrantz:BAAANQAECgUICwAAAA==.Worthybacon:BAAANQAECgEIAgAAAA==.',
Wr='Wrathlor:BAAANQADCgQIBAAAAA==.Wrenlyn:BAACNQAFFH8HAAMhAAMKNwefGAB2AAAhAAIKsQifGAB2AAARAAEKRATeFABHAAA1AAQKfykABCAACQqxFqcQAKMBACEACQoHEpoyABECACAABgrDFqcQAKMBABEACAr8EF00AJsBAAE1AAUUBAgHAAoA+QsA.',
Wu='Wukain:BAABNQAECn8eAAIEAAgKrQxMdQC9AQAEAAgKrQxMdQC9AQAAAA==.',
Xa='Xalatoth:BAAANQADCgYIBgAAAA==.Xanatas:BAAANQADCggIHAABNQAECgYIEgAOAAAAAA==.Xarapxeh:BAAANQADCgUICAAAAA==.',
Xo='Xolòtl:BAACNQAFFH8HAAIKAAQK+QvsHQAXAQAKAAQK+QvsHQAXAQA1AAQKfysAAwoACQoaGTNOAJwCAAoACQpKGDNOAJwCACIABwo4C9MbAHkBAAAA.',
Xy='Xymos:BAECNQAFFH8SAAMCAAYK2B8EBQDKAAABAAUK6h0hCgDKAQACAAIKniMEBQDKAAA1AAQKfyUAAwIACQpJJQoBAJgDAAIACQoOJQoBAJgDAAEABgpuHJ54APUBAAAA.',
Ya='Yakul:BAAANQAECgUIDQAAAA==.',
Za='Zalyia:BAAANQADCgQIBAAAAA==.',
Zd='Zdk:BAAANQADCgEIAQAAAA==.',
Ze='Zeroveth:BAAANQAECgYIEQABNQAECgcIEgAOAAAAAA==.Zexpert:BAAANQAECgIIAgABNQAECgcIGgAMADQYAA==.',
Zu='Zugg:BAAANQADCggIDAAAAA==.Zulcow:BAAANQAECggIDAAAAA==.',
['Âr']='Ârtemis:BAAANQAECgYIDgAAAA==.',
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
