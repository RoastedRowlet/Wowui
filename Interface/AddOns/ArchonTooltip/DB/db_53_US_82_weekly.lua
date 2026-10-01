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

local lookup = {'DeathKnight-Frost','Rogue-Subtlety','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Mage-Frost','Unknown-Unknown','Evoker-Augmentation','DeathKnight-Blood','DeathKnight-Unholy','Priest-Holy','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-BeastMastery','Paladin-Retribution','Rogue-Assassination','Rogue-Outlaw','Monk-Mistweaver','Monk-Windwalker','Paladin-Protection','Druid-Balance','Shaman-Enhancement','DemonHunter-Vengeance','DemonHunter-Devourer','Druid-Guardian','Druid-Restoration','Evoker-Devastation',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Acanthel:BAAANQADCgMJAgAAAA==.',
Ad='Adhira:BAAANQADCgYJDgAAAA==.',
Ae='Aegennai:BAAANQAECgUIDQAAAA==.Aegondk:BAEBNQAFFIEGAAIBAAMK0xnHBgAYAQABAAMK0xnHBgAYAQAAAA==.Aelias:BAAANQADCggIHQAAAA==.Aevaela:BAABNQAECoEcAAICAAgKdRg/DgB0AgACAAgKdRg/DgB0AgAAAA==.',
Ag='Agilaz:BAAANQAECgYIEQAAAA==.',
Ak='Akey:BAAANQAECgIIAwAAAQ==.Akhae:BAABNQAECoEcAAMDAAgK6Q5mWgCtAQADAAgK6Q5mWgCtAQAEAAEKtwExEAEnAAAAAA==.',
Al='Albinism:BAAANQAECgEIAQAAAA==.Alcadeias:BAAANQADCggIGwAAAA==.Alethiah:BAAANQAECgEIAQAAAA==.Allastor:BAAANQADCgQIBgAAAA==.',
Am='Amuria:BAAANQAECgEIAQAAAA==.',
An='Anaeda:BAAANQAECgYIDgAAAA==.Anastrianna:BAAANQADCgYJBgAAAA==.Andrömëdä:BAAANQAECgIIAQAAAA==.Angryjim:BAAANQADCgUJBQAAAA==.Anubisre:BAAANQADCggIDwAAAA==.Anzulay:BAAANQADCgMIAwAAAA==.',
Aq='Aquindra:BAAANQADCgYIDgAAAA==.',
Ar='Aralleda:BAAANQABCgIIAgAAAA==.Arccane:BAAANQAECgUICwAAAA==.Arthar:BAABNQAECoEkAAIFAAgKeBsiRACCAgAFAAgKeBsiRACCAgAAAA==.',
As='Ashvyth:BAAANQAECgUIDQAAAA==.',
Aw='Awwyeah:BAAANQADCgIIAgABNQAECgkJHgAGANIcAA==.',
Az='Azuredeath:BAAANQABCgQIBAAAAA==.Azurehope:BAAANQABCgUIBQAAAA==.',
Ba='Baconpancake:BAAANQAECgIIAQAAAA==.Baldpunch:BAAANQADCggIJQAAAA==.Balinor:BAAANQAECgIIAQAAAA==.Ballz:BAAANQADCgYIBgAAAA==.Balom:BAAANQAECgQIBAAAAA==.Balomdruid:BAAANQADCgUIBQABNQAECgQIBAAHAAAAAA==.Barnabus:BAAANQAECgIIBgAAAA==.',
Be='Beachbecrazy:BAAANQAECgUICQAAAA==.Beaj:BAAANQAECgIIAQAAAA==.Beastlypläyä:BAAANQADCgIJAgAAAA==.Bessarion:BAAANQADCgcICQAAAA==.',
Bi='Bigandbeefy:BAAANQAECgQICgAAAA==.Bilac:BAAANQADCgEIAQABNQAECggIHgAIAJ8SAA==.',
Bl='Blusoleil:BAAANQAECgIIAQAAAA==.',
Bo='Bonerblast:BAAANQADCggICgAAAA==.Boston:BAABNQAECoEXAAQBAAgKzBaVIQAuAgABAAgKzBaVIQAuAgAJAAMKKBC3ggCmAAAKAAEKORalrQA1AAAAAA==.',
Br='Branches:BAAANQAECgUIDwAAAA==.Brewtholomew:BAAANQAECgYIEAAAAA==.Briggsey:BAAANQAECgUICQAAAA==.Briznot:BAAANQAECgUIBgAAAA==.Bruh:BAAANQAECgQIBAAAAA==.Brunna:BAAANQADCgQIBAAAAA==.Bryce:BAAANQAECgEIAQAAAA==.Brèanna:BAAANQADCgMIBwAAAA==.',
Bu='Bubbadubya:BAAANQADCgYIHAAAAA==.Bunnyfu:BAAANQADCgcIGAABNQAECggIHgAIAJ8SAA==.Burningwolf:BAAANQAECgUIEQAAAA==.',
['Bó']='Bórs:BAAANQAECgQICAAAAA==.',
Ca='Caiden:BAAANQAECgIIAgAAAA==.Caitlyn:BAAANQADCgEIAQAAAA==.Caleesia:BAAANQADCgYIFwAAAA==.Carnìfex:BAAANQADCgcIIQAAAA==.Caskaerta:BAAANQADCgYIBgAAAA==.Catbrin:BAAANQAECgUIBwAAAA==.',
Ce='Cerà:BAAANQAECgQICAAAAA==.',
Ch='Chapslop:BAAANQADCgcIDAAAAA==.Cheetah:BAAANQADCgMIBwAAAA==.',
Cl='Clizee:BAAANQAECgQIBAAAAA==.Clobberben:BAAANQADCgQIBAAAAA==.Cloudbreaker:BAAANQAECgQIBAAAAA==.',
Co='Cobramage:BAAANQAECgQICAAAAA==.Constellate:BAAANQAECgUICgAAAA==.Cotterpins:BAAANQAECgUIBgAAAA==.',
Cr='Cruicible:BAAANQADCgcIDAAAAA==.',
Cy='Cybrkatz:BAAANQADCgIIAgAAAA==.',
Cz='Cztalone:BAAANQADCgQIBAAAAA==.',
['Cè']='Cèlane:BAABNQAECoEeAAIEAAgKMRdJNwBTAgAEAAgKMRdJNwBTAgAAAA==.',
Da='Damitsu:BAEANQADCgYIFQABNQAECgMIBQAHAAAAAA==.Damnitsu:BAEANQAECgMIBQAAAA==.Darckside:BAAANQADCgUIBQAAAA==.Dazen:BAAANQADCgMIBwAAAA==.',
De='Deadflexy:BAAANQAECgUIBgAAAA==.Deathberry:BAAANQAECgYIEQAAAA==.Deathdoodles:BAAANQAECgUIBwABNQAECgkJGwALADYWAA==.Deathvoker:BAAANQADCgYICwAAAA==.Deekan:BAAANQAECgQIBQAAAA==.Dejavù:BAAANQAECgIIAgAAAA==.Demonblood:BAAANQAECgYIEAAAAA==.Demonicmac:BAAANQADCgMJAwABNQAECgQICAAHAAAAAA==.Deräth:BAAANQAECgYIDAAAAA==.Devlik:BAAANQADCgYIDQAAAA==.Dew:BAAANQADCgYIBgABNQADCgYICgAHAAAAAA==.Dezlover:BAAANQADCgIIAgAAAA==.',
Di='Dimensius:BAAANQAECgQIBQAAAA==.Dinkalopogis:BAAANQADCgYIEAAAAA==.Dionne:BAAANQAECgUIBgAAAA==.Dippindots:BAAANQADCgYIBgABNQAECgkJGwAMAFAaAA==.Ditsie:BAAANQAECgEJAQAAAA==.',
Dm='Dmega:BAAANQAECgQICAAAAA==.',
Do='Dogfunk:BAAANQABCgcICgAAAA==.',
Dr='Dragea:BAAANQAECgIIAwAAAA==.Dragondude:BAAANQAECgQJBwAAAA==.Dragonsgrasp:BAAANQADCgUIBAAAAA==.Drakoswrath:BAACNQAFFIEIAAIJAAMKUBaoDwDuAAAJAAMKUBaoDwDuAAA1AAQKgSEAAgkACQoaHx0VANcCAAkACQoaHx0VANcCAAAA.Drizzít:BAAANQAECgUIBQAAAA==.',
Du='Durango:BAAANQAECgEIAQAAAA==.',
Dy='Dyelin:BAAANQAECgUIDQAAAA==.',
Ek='Ekocteid:BAAANQABCgIIAgAAAA==.',
El='Elylle:BAAANQADCgMIBgABNQADCgYIBgAHAAAAAA==.Elyron:BAAANQAECgUIDQAAAA==.',
En='Endofall:BAAANQAECgEIAgAAAA==.',
Ep='Epiczimbabue:BAAANQADCgEIAQAAAA==.',
Es='Esrahaddon:BAABNQAECoEaAAMGAAgKzB22BgBGAgAGAAcKbh62BgBGAgAMAAcKoxi6kAAcAgAAAA==.Estella:BAAANQADCgYIDgAAAA==.',
Et='Et:BAAANQAECgEIAQAAAA==.Etheri:BAAANQADCgcJEQAAAA==.',
Ez='Ezhra:BAAANQABCgEIAQABNQADCgYIFwAHAAAAAA==.Ezind:BAAANQAECgIIAQAAAA==.',
Fa='Fakename:BAAANQAECgUICQAAAA==.Fakesaint:BAABNQAECoEeAAIDAAgK6SGkEwABAwADAAgK6SGkEwABAwAAAA==.Fangstorm:BAAANQAECgUIDQAAAA==.Farorê:BAAANQADCgYJDAAAAA==.Fazz:BAAANQAECgEIAQAAAA==.',
Fe='Feldruid:BAAANQAECgQIBwAAAA==.Felup:BAABNQAECoEeAAQNAAcKgB+qNQB4AgANAAcKLx+qNQB4AgAOAAIK+xGUTACDAAAPAAEK5Bt5IQBGAAAAAA==.',
Fo='Folstagg:BAAANQADCgcIDAAAAA==.Foreverem:BAAANQAECgcICgAAAA==.',
Fr='Frostynewf:BAAANQADCgYIBgAAAA==.',
Fu='Fujitora:BAAANQAECgYIEwAAAA==.Fuzzwig:BAAANQADCgYJBgAAAA==.',
Gi='Gideòn:BAAANQADCgQJBAAAAA==.',
Gl='Glenys:BAAANQADCgEIAQAAAA==.',
Go='Gopao:BAAANQADCgUIAgABNQAECgQIBQAHAAAAAA==.',
Gr='Graxus:BAAANQADCggJEgAAAA==.Greth:BAAANQADCgYIGwAAAA==.Grimlin:BAAANQAECgEJAQAAAA==.',
Gu='Gudge:BAABNQAECoEeAAIIAAgKnxKWBwDVAQAIAAgKnxKWBwDVAQAAAA==.Gummypenguin:BAAANQAECggIEwABNQAFFAQICAAQALkbAA==.',
Ha='Hadhox:BAAANQAECgEIAQABNQAECgYICwAHAAAAAA==.Hathdox:BAAANQAECgYICwAAAA==.Hawkulees:BAAANQADCgYIGAAAAA==.Hazelnoot:BAABNQAECoEfAAIRAAgKEh8LNAC6AgARAAgKEh8LNAC6AgAAAA==.',
He='Healzofdeath:BAAANQADCgcJEAAAAA==.Hegaphie:BAAANQAECgEJAQAAAA==.Hercluvscake:BAAANQADCgcICwAAAA==.Hexcist:BAAANQAECgUICQAAAA==.',
Hi='Hitsuryu:BAAANQAECgUIDAAAAA==.',
Ho='Hochma:BAAANQADCgEIAQAAAA==.Hokogo:BAAANQADCgEIAQAAAA==.Holdon:BAABNQAECoEZAAMSAAgKnAtELgC3AQASAAcKzgxELgC3AQATAAYKLAREDwD+AAAAAA==.Holehbones:BAAANQADCgYIBgAAAA==.Hollyanne:BAAANQAECgMJBAAAAA==.Hoonicorn:BAAANQADCgEIAQABNQADCgIJAgAHAAAAAA==.Hornsharp:BAAANQADCgcIDgAAAA==.',
Hu='Hunalli:BAAANQADCgUIBwABNQAECggIHgAIAJ8SAA==.Hunilla:BAAANQAECgUIBwABNQAECggIHgAIAJ8SAA==.',
Ia='Iamu:BAAANQADCgYIDwAAAA==.',
Ib='Ibris:BAAANQADCgMIBwAAAA==.',
Ic='Iconius:BAAANQADCgMIBwAAAA==.',
Ie='Ieatwetsocks:BAABNQAECoEZAAMDAAkKaBRMPgAdAgADAAkKaBRMPgAdAgAEAAIKWwRr5wBRAAAAAA==.',
Ig='Ignivar:BAAANQADCgYJFAAAAA==.',
In='Indra:BAAANQAECgIIAgAAAA==.Innexshaman:BAAANQAECgYICwAAAA==.Insaint:BAAANQAECgYIDwAAAA==.',
Ir='Ironfield:BAAANQAECgcIDgABNQADCgUIBQAHAAAAAA==.Ironsanta:BAAANQADCgIJAgAAAA==.Irony:BAAANQAECgMIAgAAAA==.Irtank:BAAANQADCgEIAQAAAA==.',
Is='Isabellë:BAAANQAECgQIDQAAAA==.',
Je='Jessamine:BAABNQAECoEgAAIMAAgKfxDdnAABAgAMAAgKfxDdnAABAgAAAA==.Jetta:BAAANQAECgEIAQAAAA==.Jezzak:BAAANQAECgYIEQABNQAECggIGQAQAAEUAA==.',
Jo='John:BAABNQAECoEyAAITAAgKUiTJAQBBAwATAAgKUiTJAQBBAwAAAA==.Jorien:BAABNQAECoEXAAIQAAgKmBtFMQCXAgAQAAgKmBtFMQCXAgAAAA==.',
Jp='Jp:BAAANQAECgMIBAABNQAECgQIBAAHAAAAAA==.Jpd:BAAANQAECgQIBAAAAA==.',
Ju='Justadwarf:BAAANQADCgcICQAAAA==.Justatsuj:BAAANQADCgYICAAAAA==.Juston:BAAANQAECgUIBQAAAA==.',
Ka='Kaboonsky:BAAANQAECgYIDAAAAA==.Kaeamani:BAAANQADCgYIBwAAAA==.Kaenaya:BAAANQADCgIJAgAAAA==.Kamikori:BAAANQAECgUIDAAAAA==.Kardell:BAAANQADCgYIDAAAAA==.Kardels:BAAANQADCgQIBAABNQADCgYIDAAHAAAAAA==.Karnadaz:BAABNQAECoEhAAIFAAkKChoXQACQAgAFAAkKChoXQACQAgAAAA==.Karnkarn:BAAANQAECgYICgAAAA==.Karnn:BAAANQADCggIDgAAAA==.Katalight:BAAANQADCgEIAQABNQAECgEIAQAHAAAAAA==.',
Ke='Keho:BAAANQAECgcICgAAAA==.',
Ki='Kiascendance:BAABNQAECoEXAAIDAAcKRCPqIgCjAgADAAcKRCPqIgCjAgAAAA==.',
Ko='Kolosho:BAAANQADCgcIEwAAAA==.Korxana:BAAANQAECgcIEQAAAA==.Korxon:BAABNQAECoEeAAILAAkKtxSVKwB8AgALAAkKtxSVKwB8AgAAAA==.Kotus:BAAANQADCgcIDQAAAA==.',
Ks='Ksyusha:BAAANQAECgEJAQAAAA==.',
Ky='Kyfess:BAAANQAECgIIAQAAAA==.',
['Kä']='Kämi:BAAANQADCgYICgABNQAECgEIAQAHAAAAAA==.',
La='Lanuadra:BAABNQAECoEdAAICAAgKYBRVEQBJAgACAAgKYBRVEQBJAgAAAA==.Lawry:BAAANQAECgYICwAAAA==.',
Le='Leasidhe:BAAANQADCgcJDgABNQADCgQIBAAHAAAAAA==.Lethalbimbo:BAAANQADCgQICAAAAA==.',
Lg='Lghtninstorm:BAAANQADCgIJAgAAAA==.',
Li='Liesel:BAAANQADCggICAAAAA==.Likhan:BAAANQABCgQIBAABNQADCgcIBwAHAAAAAA==.Lillié:BAAANQABCgIIAQAAAA==.Lilysham:BAACNQAFFIEOAAIDAAUKmRuhBQDBAQADAAUKmRuhBQDBAQA1AAQKgSUAAwMACQpwIWkbAM4CAAMACQpwIWkbAM4CAAQACArzERNLAPsBAAAA.Lindar:BAAANQABCgMIBAAAAA==.Linddrel:BAAANQAECgMIBAAAAA==.',
Lo='Lomea:BAAANQADCgYIBgAAAA==.Lonarius:BAAANQABCgQIBwAAAA==.',
Lu='Lunasblood:BAAANQABCgIIAgAAAA==.',
['Lá']='Ládylumps:BAAANQADCgcIBwABNQAECgUICQAHAAAAAA==.',
['Lø']='Løllîe:BAAANQAECgIIAwAAAA==.',
Ma='Macarius:BAAANQAECgUIBgAAAA==.Macdee:BAAANQADCgMIAwABNQAECgQICAAHAAAAAA==.Magatai:BAAANQAECgEIAQAAAA==.Mageless:BAAANQADCgIIAgAAAA==.Magicjim:BAAANQADCgIJAgAAAA==.Magpie:BAAANQADCgYIDAAAAA==.Maimed:BAAANQAECgIIAgAAAA==.Malotan:BAAANQABCgEIAQABNQABCggICAAHAAAAAA==.Manaster:BAAANQAECgIIAQAAAA==.Manpriest:BAAANQADCgEIAQAAAA==.Maravanna:BAAANQADCgEIAQAAAA==.Martlok:BAAANQAECgEIAQAAAA==.Mathas:BAAANQAECgEIAgAAAA==.Maynis:BAAANQABCgQIBgAAAA==.Maysaveyou:BAAANQADCgYIDQAAAA==.',
Mc='Mcbrynhammer:BAAANQADCgUIEwAAAA==.',
Me='Meanwhile:BAAANQADCgUIAgAAAA==.Meowmixx:BAAANQABCgUIBQAAAA==.Merkii:BAAANQADCgYIBgABNQAECgYIDwAHAAAAAA==.',
Mi='Micflinigan:BAAANQAECgUIDgAAAA==.Midnightmare:BAAANQABCgMJAQAAAA==.Milkymoomoo:BAAANQADCgQICAAAAA==.Minarii:BAAANQAECgIIAgAAAA==.Ming:BAAANQADCgQIBAABNQAECggIJAAUADAfAA==.Minilove:BAAANQADCgIIAwAAAA==.Misha:BAAANQABCgIJAgAAAA==.Mishelö:BAAANQAECgEJAQAAAA==.Misla:BAAANQAECgEIAQAAAA==.Missfiré:BAAANQADCggICAAAAA==.',
Mo='Mochimochi:BAAANQADCgQIBAAAAA==.Mommieuppies:BAAANQADCgcJCAAAAA==.Momomochi:BAAANQAECgQIBAAAAA==.Moonshae:BAABNQAECoEcAAMUAAcKXRKsGACbAQAUAAcKXRKsGACbAQAVAAUK5RFsMQAcAQAAAA==.Moothrnature:BAAANQABCgQIBAAAAA==.Mortalbion:BAAANQAECgIIAgAAAA==.',
My='Mystiquè:BAAANQADCgYIHAAAAA==.',
Na='Nahmbra:BAAANQAECgIIAgAAAA==.Naithin:BAAANQAECgEIAQAAAA==.Nalarah:BAAANQADCgQIBAAAAA==.Naviriel:BAAANQADCgYIAwABNQAECgUIBgAHAAAAAA==.',
Ne='Nerrf:BAAANQADCgYIBgAAAA==.',
Ni='Nightray:BAAANQAECgQJCAABNQAECggIJAAFAHgbAA==.',
No='Noknik:BAAANQABCggICAAAAA==.Nonsocial:BAACNQAFFIEJAAIWAAcK0w+0AQDfAQAWAAcK0w+0AQDfAQA1AAQKgRgAAhYACQodJB8CAJoDABYACQodJB8CAJoDAAAA.Norgaladwen:BAAANQADCggICgAAAA==.Noriisa:BAABNQAECoEZAAIQAAgKARS3RABTAgAQAAgKARS3RABTAgAAAA==.Notamathguy:BAAANQADCggIDgAAAA==.Noudders:BAAANQAECgYIDwAAAA==.',
Ny='Nyvak:BAAANQADCgcIDgAAAA==.',
Od='Odinhand:BAABNQAECoEdAAIXAAcKughOSQByAQAXAAcKughOSQByAQAAAA==.',
Oh='Ohgreatdink:BAAANQADCgYJCwAAAA==.',
Ol='Oliissa:BAAANQADCgYIHAAAAA==.',
Oz='Ozwäld:BAAANQAECgUICQABNQAECgkJIQAYAMMfAA==.Ozwäldo:BAABNQAECoEhAAIYAAkKwx9QBQAYAwAYAAkKwx9QBQAYAwAAAA==.',
Pa='Pandapí:BAAANQADCgYIBgAAAA==.Panduh:BAABNQAECoEbAAMMAAkKUBrZYACPAgAMAAkKUBrZYACPAgAGAAIKVRIqJgB4AAAAAA==.Pandóra:BAAANQADCgcIDgAAAA==.Pariousa:BAABNQAECoEjAAISAAkKSCO6BQBOAwASAAkKSCO6BQBOAwAAAA==.',
Pe='Peppermintxo:BAAANQAECgQIBAABNQADCgIJAgAHAAAAAA==.',
Ph='Phaite:BAAANQAECggJAQAAAA==.',
Pi='Pinkeepink:BAAANQAECgEIAQAAAA==.',
Po='Popacooldown:BAAANQADCgUIDwAAAA==.',
Pr='Pres:BAAANQAECgIIAwAAAA==.Prild:BAAANQABCgQIBgAAAA==.',
Pu='Pumpernickle:BAAANQAECgQIBAAAAA==.',
Ra='Rahzon:BAAANQAECgYICAAAAA==.Ralganor:BAABNQAECoEgAAIJAAgKfR3eHACVAgAJAAgKfR3eHACVAgAAAA==.Ralzin:BAAANQADCgUIDQAAAA==.Ramanash:BAAANQADCgQICAAAAA==.Ravilan:BAAANQAECgIIAgAAAA==.Raynlight:BAAANQAECgMJAwAAAA==.',
Re='Ren:BAAANQADCgUIBwAAAA==.Retacus:BAAANQADCgYICwAAAA==.',
Ri='Rina:BAAANQAFFAEIAQAAAA==.Rineli:BAAANQADCgMIAwABNQAECgIIAgAHAAAAAA==.Ringadingg:BAAANQAECgYIDgAAAA==.',
Ro='Rosequartz:BAAANQAECgQIBAAAAA==.',
Ry='Rydia:BAAANQAECgIIBwAAAA==.',
Sa='Saladin:BAAANQADCgUIBgAAAA==.Sankatlantis:BAAANQADCgYICgAAAA==.Sarka:BAAANQADCgcIBwAAAA==.Sasquatch:BAAANQAECgUIBgAAAA==.Saunkae:BAAANQAECgQIBgAAAA==.',
Sc='Scony:BAAANQAECgUICgAAAA==.Scribs:BAAANQAECgUIBQAAAA==.Scyphen:BAAANQADCgYICQAAAA==.',
Se='Seegon:BAAANQABCgYIBQAAAA==.Seismic:BAAANQADCggJCAAAAA==.Sephirain:BAAANQADCgMIAwAAAA==.Sevelement:BAAANQAECgUIEgABNQAECgkJHgAZAOgVAA==.Severalforms:BAAANQAECgQIBAABNQAECgkJHgAZAOgVAA==.Severànce:BAABNQAECoEeAAMZAAkK6BUaCQD/AQAZAAgKcRUaCQD/AQAaAAQKyxGIQADwAAAAAA==.Sevivify:BAAANQADCgIIAwABNQAECgkJHgAZAOgVAA==.',
Sh='Shablammy:BAAANQAECgUIDAAAAA==.Shadowginni:BAAANQAECgIIAgAAAA==.Shadownome:BAAANQADCgMIBwAAAA==.Shammygand:BAAANQADCgUJBQABNQAECgYICQAHAAAAAA==.Shanker:BAAANQADCgMIAwAAAA==.Shefu:BAAANQAECgMIBQAAAA==.Shfifty:BAABNQAECoEbAAILAAkKNhaNJACgAgALAAkKNhaNJACgAgAAAA==.Shizamthebam:BAAANQAECgUICQAAAA==.Shutupbird:BAABNQAECoEaAAIbAAgKRBnPCgBOAgAbAAgKRBnPCgBOAgAAAA==.',
Si='Sihtric:BAAANQADCggICAAAAA==.Silris:BAAANQADCgYIDAAAAA==.',
Sk='Skydragon:BAAANQADCgYJFwAAAA==.',
Sl='Slay:BAAANQAECgEJAQABNQAECggIFwAJAEMaAA==.Slayful:BAAANQABCgQJBAAAAA==.Sleepydwarf:BAAANQADCggJCAAAAA==.Slonk:BAAANQAECgQJBAAAAA==.',
So='Sofia:BAAANQAECgQIBQAAAA==.',
Sp='Sparrtacus:BAAANQABCgUIBwAAAA==.Spiritly:BAAANQAECgMIBAAAAA==.Sploof:BAAANQAECgIIAwAAAA==.Sprynt:BAAANQAECgUICAAAAA==.',
St='Staples:BAAANQADCggIDgABNQAECgUIBgAHAAAAAA==.Starlighter:BAAANQADCgYIBgAAAA==.Starmist:BAAANQADCgYIGwAAAA==.Stubly:BAAANQADCgQJBAAAAA==.',
Su='Sunfyrie:BAAANQAECgQICAAAAA==.',
Sw='Sweèt:BAAANQAECgIIAQAAAA==.',
Ta='Tagrit:BAAANQADCgUIBQAAAA==.Taldieth:BAAANQAECgIIAQAAAA==.Taurdk:BAAANQAECgUJBwAAAA==.Taylorshift:BAAANQAECgcIEgAAAA==.',
Te='Teaar:BAAANQADCgUIBQABNQAECggIFwAJAEMaAA==.Teetau:BAAANQAECgUIDQAAAA==.',
Th='Thadregosa:BAAANQAECgUICgAAAA==.Thalsan:BAAANQABCgIIAgAAAA==.Thander:BAAANQADCgYIDwAAAA==.Therlisa:BAAANQADCggICAAAAA==.Thordar:BAAANQABCggICwAAAA==.',
Ti='Tibbotanical:BAAANQADCgUIBQAAAA==.Tiberius:BAAANQABCgIIAQAAAA==.Tiffy:BAAANQADCggIHgAAAA==.Tirna:BAAANQAECgEJAgAAAA==.Tirnotham:BAAANQAECgIIAwAAAA==.',
Tm='Tmtglizzy:BAAANQAECggIEgAAAA==.',
To='Tokalu:BAAANQAECgUIBgAAAA==.Tonjudsonson:BAACNQAFFIEFAAIbAAMKNBdcAgDuAAAbAAMKNBdcAgDuAAA1AAQKgSgAAhsACQoqI9QBAJIDABsACQoqI9QBAJIDAAAA.Torath:BAAANQADCgYJCwABNQADCgYIDwAHAAAAAA==.',
Tu='Turdimer:BAAANQADCgYJGAAAAA==.',
Tw='Twiki:BAAANQAECgUIBwAAAA==.Twobricks:BAABNQAECoEdAAIcAAcK/RRKIgC2AQAcAAcK/RRKIgC2AQAAAA==.',
Ty='Tyrielas:BAAANQADCgYIBwAAAA==.Tyrssana:BAAANQAECgIIAwABNQAECgkJHQAdAFoQAA==.',
['Tö']='Töketsu:BAAANQADCgYIBgAAAA==.',
Uh='Uhmerica:BAABNQAECoEdAAIWAAcKeB8hDwBeAgAWAAcKeB8hDwBeAgABNQABCgYIBgAHAAAAAA==.',
Ur='Urdeadtoo:BAAANQAECgQICAAAAA==.Urlacher:BAAANQADCgUIBgAAAA==.Urthkwayk:BAAANQADCgYIBgAAAA==.',
Va='Vaedryn:BAAANQADCgUIBQAAAA==.Vaterunser:BAAANQAECgIIAwAAAA==.Vazoom:BAAANQAECgIIAwAAAA==.',
Ve='Velskud:BAAANQADCgYJFQAAAA==.Vertexx:BAAANQADCgYJBgAAAA==.',
Vi='Vierth:BAAANQADCgIIAgABNQADCgYIBgAHAAAAAA==.Vinhar:BAAANQADCgUICAAAAA==.Vinsteam:BAAANQADCgQIBAAAAA==.Visea:BAAANQADCgIIAgABNQADCgYIBgAHAAAAAA==.',
Vo='Voidsavage:BAAANQADCgYIFAAAAA==.Voidwing:BAAANQAECgQIBAAAAA==.Volic:BAAANQAECgUIDQAAAQ==.Vollken:BAAANQADCgYICAAAAA==.Voznje:BAAANQAECgEIBAAAAA==.',
We='Wesleypipes:BAAANQAECgYIEgAAAA==.',
Wh='Whisteria:BAAANQADCgYIBgAAAA==.',
Wi='Wizalf:BAAANQAECgIIAgAAAA==.',
Wm='Wmrx:BAAANQADCgYIBgAAAA==.',
Wo='Wodalpala:BAAANQAECggIEQAAAA==.Wolfmato:BAAANQAECgYIDAAAAA==.',
Wy='Wynne:BAAANQADCggJEgAAAA==.',
Xa='Xalabro:BAAANQAECgUIDAAAAA==.',
Xe='Xerxeis:BAAANQABCgYICAABNQADCgcIEwAHAAAAAA==.',
Xo='Xousa:BAAANQADCgQIBgABNQAECgkJIwASAEgjAA==.',
Yh='Yhorn:BAAANQADCgcIBwABNQAFFAUIDgADAJkbAA==.',
Ys='Yssuplef:BAAANQAECgIIAwAAAA==.',
Yu='Yuefei:BAAANQADCgQJBAAAAA==.',
Za='Zaiyra:BAAANQADCgcIFQAAAA==.Zakoor:BAAANQADCgYIFAAAAA==.Zareena:BAAANQADCgYJFgAAAA==.Zarnia:BAAANQADCgMIAwAAAA==.Zarrock:BAAANQADCgIJAgAAAA==.Zavatan:BAAANQADCgQIBwAAAA==.',
Ze='Zebbyzebzeb:BAAANQADCgYJGQAAAA==.Zekia:BAAANQAECgYIEwAAAA==.Zepirra:BAAANQABCgcIDgAAAA==.Zerm:BAAANQAECgUIEAAAAA==.Zerodeath:BAAANQADCgYJBgAAAA==.',
Zi='Zinnkura:BAAANQAECgEJAQAAAA==.',
Zo='Zorsa:BAAANQAECgEIAQAAAA==.',
Zu='Zuljawn:BAAANQAECgUIDQAAAA==.',
Zy='Zyphos:BAAANQADCgIIAgAAAA==.',
['Ñô']='Ñôg:BAAANQADCggICQAAAA==.',
['Ød']='Ødis:BAAANQADCggIHgAAAA==.',
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
