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

local lookup = {'Rogue-Subtlety','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Mage-Frost','Unknown-Unknown','Evoker-Augmentation','DeathKnight-Blood','Hunter-BeastMastery','Rogue-Outlaw','Priest-Holy','Monk-Mistweaver','Paladin-Protection','Shaman-Enhancement','Mage-Arcane','Rogue-Assassination','DemonHunter-Vengeance','DemonHunter-Devourer','Druid-Guardian',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Acanthel:BAAANQADCgMJAgAAAA==.',
Ad='Adhira:BAAANQADCgYJDgAAAA==.',
Ae='Aegennai:BAAANQAECgUICAAAAA==.Aegondk:BAEANQAFFAMJBAAAAA==.Aelias:BAAANQADCgcIFQAAAA==.Aevaela:BAABNQAECoEVAAIBAAgKFBbHDgBZAgABAAgKFBbHDgBZAgAAAA==.',
Ag='Agilaz:BAAANQAECgUJCwAAAA==.',
Ak='Akey:BAAANQAECgEJAQAAAQ==.Akhae:BAABNQAECoEVAAMCAAcKWgqfaQBNAQACAAcKWgqfaQBNAQADAAEKtwGe7gAoAAAAAA==.',
Al='Albinism:BAAANQAECgEIAQAAAA==.Alcadeias:BAAANQADCgcIEwAAAA==.Alethiah:BAAANQAECgEIAQAAAA==.Allastor:BAAANQADCgQIBgAAAA==.',
An='Anaeda:BAAANQAECgUJCAAAAA==.Anastrianna:BAAANQADCgYJBgAAAA==.Andrömëdä:BAAANQAECgIIAQAAAA==.Angryjim:BAAANQADCgUJBQAAAA==.Anubisre:BAAANQADCggJDQAAAA==.Anzulay:BAAANQADCgMIAwAAAA==.',
Aq='Aquindra:BAAANQADCgYIDgAAAA==.',
Ar='Aralleda:BAAANQABCgIIAgAAAA==.Arccane:BAAANQAECgQJBgAAAA==.Arthar:BAABNQAECoEbAAIEAAcKzxvhTAA2AgAEAAcKzxvhTAA2AgAAAA==.',
As='Ashvyth:BAAANQAECgQJCAAAAA==.',
Aw='Awwyeah:BAAANQADCgIIAgABNQAECgkJHgAFANIcAA==.',
Az='Azuredeath:BAAANQABCgQIBAAAAA==.Azurehope:BAAANQABCgUIBQAAAA==.',
Ba='Baconpancake:BAAANQAECgIJAQAAAA==.Baldpunch:BAAANQADCggJHQAAAA==.Balinor:BAAANQAECgIJAQAAAA==.Ballz:BAAANQADCgYIBgAAAA==.Balom:BAAANQAECgIIAgAAAA==.Balomdruid:BAAANQADCgUIBQABNQAECgIIAgAGAAAAAA==.Barnabus:BAAANQAECgIIBgAAAA==.',
Be='Beachbecrazy:BAAANQAECgQIBAAAAA==.Beaj:BAAANQAECgIJAQAAAA==.Beastlypläyä:BAAANQADCgIJAgAAAA==.Belládonna:BAAANQADCggICAAAAA==.Bessarion:BAAANQADCgUIAgAAAA==.',
Bi='Bigandbeefy:BAAANQAECgQJBgAAAA==.Bilac:BAAANQADCgEIAQABNQAECggJGAAHAHUMAA==.',
Bl='Blusoleil:BAAANQAECgIJAQAAAA==.',
Bo='Bonerblast:BAAANQADCggICgAAAA==.Boston:BAAANQAECgYJDQAAAA==.',
Br='Branches:BAAANQAECgUICgAAAA==.Brewtholomew:BAAANQAECgYIEAAAAA==.Briggsey:BAAANQAECgMIBAAAAA==.Briznot:BAAANQAECgIIAwAAAA==.Bruh:BAAANQAECgQIBAAAAA==.Bryce:BAAANQAECgEIAQAAAA==.Brèanna:BAAANQADCgMIBQAAAA==.',
Bu='Bubbadubya:BAAANQADCgYJFgAAAA==.Bunnyfu:BAAANQADCgcJFAABNQAECggJGAAHAHUMAA==.Burningwolf:BAAANQAECgUIDQAAAA==.',
['Bó']='Bórs:BAAANQAECgMJBQAAAA==.',
Ca='Caiden:BAAANQADCgcIDQAAAA==.Caitlyn:BAAANQADCgEIAQAAAA==.Caleesia:BAAANQADCgYJEQAAAA==.Carnìfex:BAAANQADCgcIFwAAAA==.Caskaerta:BAAANQADCgYIBgAAAA==.Catbrin:BAAANQAECgIIBAAAAA==.',
Ce='Cerà:BAAANQAECgQJBAAAAA==.',
Ch='Chapslop:BAAANQADCgcIDAAAAA==.Cheetah:BAAANQADCgMIBQAAAA==.',
Cl='Clizee:BAAANQAECgQJBAAAAA==.Clobberben:BAAANQADCgQIBAAAAA==.Cloudbreaker:BAAANQADCggIDwAAAA==.',
Co='Cobramage:BAAANQAECgQICAAAAA==.Constellate:BAAANQAECgQJCAAAAA==.Cotterpins:BAAANQAECgIIAwAAAA==.',
Cr='Cruicible:BAAANQADCgcIDAAAAA==.',
Cy='Cybrkatz:BAAANQADCgIIAgAAAA==.',
Cz='Cztalone:BAAANQADCgQIBAAAAA==.',
['Cè']='Cèlane:BAAANQAECgcJEgAAAA==.',
Da='Damitsu:BAEANQADCgYIFQABNQAECgIIAgAGAAAAAA==.Damnitsu:BAEANQAECgIIAgAAAA==.Darckside:BAAANQADCgUIBQAAAA==.Dazen:BAAANQADCgMIBQAAAA==.',
De='Deadflexy:BAAANQAECgIIAwAAAA==.Deathberry:BAAANQAECgUJCwAAAA==.Deathdoodles:BAAANQAECgIIAgABNQAECggJEgAGAAAAAA==.Deathvoker:BAAANQADCgYICwAAAA==.Deekan:BAAANQAECgQIBQAAAA==.Dejavù:BAAANQAECgIIAgAAAA==.Demonblood:BAAANQAECgYIEAAAAA==.Demonicmac:BAAANQADCgMJAwABNQAECgQICAAGAAAAAA==.Deräth:BAAANQAECgUIBwAAAA==.Devlik:BAAANQADCgYIDQAAAA==.Dew:BAAANQADCgYIBgABNQADCgYICgAGAAAAAA==.',
Di='Dimensius:BAAANQAECgQIBQAAAA==.Dinkalopogis:BAAANQADCgUJCgAAAA==.Dionne:BAAANQAECgIIAwAAAA==.Ditsie:BAAANQAECgEJAQAAAA==.',
Dm='Dmega:BAAANQAECgQIBAAAAA==.',
Do='Dogfunk:BAAANQABCgcICgAAAA==.',
Dr='Dragea:BAAANQAECgIIAwAAAA==.Dragondude:BAAANQAECgQJBwAAAA==.Dragonsgrasp:BAAANQADCgUIBAAAAA==.Drakoswrath:BAACNQAFFIEFAAIIAAMKxhIsDADXAAAIAAMKxhIsDADXAAA1AAQKgR4AAggACQoaH/8PAOsCAAgACQoaH/8PAOsCAAAA.Drizzít:BAAANQAECgUIBQAAAA==.',
Du='Durango:BAAANQAECgEIAQAAAA==.',
Dy='Dyelin:BAAANQAECgQJCAAAAA==.',
Ek='Ekocteid:BAAANQABCgIIAgAAAA==.',
El='Elylle:BAAANQADCgMIBAABNQADCgYIBgAGAAAAAA==.Elyron:BAAANQAECgQJCAAAAA==.',
En='Endofall:BAAANQAECgEIAgAAAA==.',
Ep='Epiczimbabue:BAAANQADCgEIAQAAAA==.',
Es='Esrahaddon:BAAANQAECgcIEAAAAA==.Estella:BAAANQADCgYIDgAAAA==.',
Et='Et:BAAANQAECgEIAQAAAA==.Etheri:BAAANQADCgcJEQAAAA==.',
Ez='Ezhra:BAAANQABCgEIAQABNQADCgYJEQAGAAAAAA==.Ezind:BAAANQAECgEIAQAAAA==.',
Fa='Fakename:BAAANQAECgQIBAAAAA==.Fakesaint:BAAANQAECgcJEwAAAA==.Fangstorm:BAAANQAECgQJCAAAAA==.Farorê:BAAANQADCgYJDAAAAA==.Fazz:BAAANQADCggJDAAAAA==.',
Fe='Feldruid:BAAANQAECgQIBQAAAA==.Felup:BAAANQAECgcJEgAAAA==.',
Fo='Folstagg:BAAANQADCgcIDAAAAA==.Foreverem:BAAANQAECgEIAQAAAA==.',
Fr='Frostynewf:BAAANQADCgYIBgAAAA==.',
Fu='Fujitora:BAAANQAECgYJDQAAAA==.Fuzzwig:BAAANQADCgYJBgAAAA==.',
Gi='Gideòn:BAAANQADCgQJBAAAAA==.',
Gl='Glenys:BAAANQADCgEIAQAAAA==.',
Go='Gopao:BAAANQADCgUIAgABNQAECgIIAwAGAAAAAA==.',
Gr='Graxus:BAAANQADCggJEgAAAA==.Greth:BAAANQADCgYJFQAAAA==.Grimlin:BAAANQAECgEJAQAAAA==.',
Gu='Gudge:BAABNQAECoEYAAIHAAgKdQymBwCfAQAHAAgKdQymBwCfAQAAAA==.Gummypenguin:BAAANQAECggJEwABNQAECgkJLAAJALgkAA==.',
Ha='Hadhox:BAAANQADCgcJGAABNQAECgUIBQAGAAAAAA==.Hathdox:BAAANQAECgUIBQAAAA==.Hawkulees:BAAANQADCgYJEgAAAA==.Hazelnoot:BAAANQAECgcJEgAAAA==.',
He='Healzofdeath:BAAANQADCgcJEAAAAA==.Hegaphie:BAAANQAECgEJAQAAAA==.Hercluvscake:BAAANQADCgcJBwAAAA==.Hexcist:BAAANQAECgQJBAAAAA==.',
Hi='Hitsuryu:BAAANQAECgQJBwAAAA==.',
Ho='Hochma:BAAANQADCgEIAQAAAA==.Hokogo:BAAANQADCgEIAQAAAA==.Holdon:BAAANQAECgYJEAAAAA==.Hollyanne:BAAANQAECgMJBAAAAA==.Hoonicorn:BAAANQADCgEIAQABNQADCgIJAgAGAAAAAA==.Hornsharp:BAAANQADCgcIDgAAAA==.',
Hu='Hunalli:BAAANQADCgUIBwABNQAECggJGAAHAHUMAA==.Hunilla:BAAANQAECgMJAwABNQAECggJGAAHAHUMAA==.',
Ia='Iamu:BAAANQADCgQICgAAAA==.',
Ib='Ibris:BAAANQADCgMIBQAAAA==.',
Ic='Iconius:BAAANQADCgMIBQAAAA==.',
Ie='Ieatwetsocks:BAABNQAECoEVAAICAAgKNRagOAAPAgACAAgKNRagOAAPAgAAAA==.',
Ig='Ignivar:BAAANQADCgYJFAAAAA==.',
In='Indra:BAAANQAECgEJAQAAAA==.Innexshaman:BAAANQAECgUIBQAAAA==.Insaint:BAAANQAECgYICgAAAA==.',
Ir='Ironfield:BAAANQAECgYJCgABNQADCgUIBQAGAAAAAA==.Ironsanta:BAAANQADCgIJAgAAAA==.Irony:BAAANQAECgMIAgAAAA==.Irtank:BAAANQADCgEIAQAAAA==.',
Is='Isabellë:BAAANQAECgQJCQAAAA==.',
Je='Jessamine:BAAANQAECgcIEgAAAA==.Jetta:BAAANQAECgEIAQAAAA==.Jezzak:BAAANQAECgUJCwABNQAECgYIDwAGAAAAAA==.',
Jo='John:BAABNQAECoEqAAIKAAcKICPWAwCdAgAKAAcKICPWAwCdAgAAAA==.Jorien:BAAANQAECgUJDQAAAA==.',
Jp='Jp:BAAANQADCgQJBQABNQAECgQIBAAGAAAAAA==.Jpd:BAAANQAECgQIBAAAAA==.',
Ju='Justadwarf:BAAANQADCgcICQAAAA==.Justatsuj:BAAANQADCgQIAgAAAA==.Juston:BAAANQAECgUIBQAAAA==.',
Ka='Kaboonsky:BAAANQAECgUJCgAAAA==.Kaeamani:BAAANQADCgYIBwAAAA==.Kaenaya:BAAANQADCgIJAgAAAA==.Kamikori:BAAANQAECgQJBwAAAA==.Kardell:BAAANQADCgYIDAAAAA==.Kardels:BAAANQADCgQIBAABNQADCgYIDAAGAAAAAA==.Karnadaz:BAABNQAECoEhAAIEAAkKCholLwCuAgAEAAkKCholLwCuAgAAAA==.Karnkarn:BAAANQAECgQIBAAAAA==.Karnn:BAAANQADCggIDgAAAA==.Katalight:BAAANQADCgEIAQABNQAECgEIAQAGAAAAAA==.',
Ke='Keho:BAAANQAECgIIAwABNQAECgUIDwAGAAAAAA==.',
Ki='Kiascendance:BAABNQAECoEXAAICAAcKRCNHGwCzAgACAAcKRCNHGwCzAgAAAA==.',
Ko='Kolosho:BAAANQADCgcIEwAAAA==.Korxana:BAAANQAECgcICwAAAA==.Korxon:BAABNQAECoEWAAILAAgKPBQqMwAmAgALAAgKPBQqMwAmAgAAAA==.Kotus:BAAANQADCgcIDQAAAA==.',
Ks='Ksyusha:BAAANQAECgEJAQAAAA==.',
Ky='Kyfess:BAAANQAECgEIAQABNQAECgEIAQAGAAAAAA==.',
['Kä']='Kämi:BAAANQADCgUIBgABNQAECgEIAQAGAAAAAA==.',
La='Lanuadra:BAABNQAECoEWAAIBAAgKVhM6EABFAgABAAgKVhM6EABFAgAAAA==.Lawry:BAAANQAECgYIBwAAAA==.',
Le='Leasidhe:BAAANQADCgcJDgABNQADCgQIBAAGAAAAAA==.Lethalbimbo:BAAANQADCgMJBQAAAA==.',
Lg='Lghtninstorm:BAAANQADCgIJAgAAAA==.',
Li='Likhan:BAAANQABCgQIBAABNQADCgcIBwAGAAAAAA==.Lillié:BAAANQABCgIIAQAAAA==.Lilysham:BAACNQAFFIEJAAICAAUKphm8AwC/AQACAAUKphm8AwC/AQA1AAQKgSIAAwIACQpwIXgTAOoCAAIACQpwIXgTAOoCAAMACArCEDo+AP8BAAAA.Lindar:BAAANQABCgMIBAAAAA==.Linddrel:BAAANQAECgEIAgAAAA==.',
Lo='Lomea:BAAANQADCgYIBgAAAA==.Lonarius:BAAANQABCgQIBQAAAA==.',
Lu='Lunasblood:BAAANQABCgIIAgAAAA==.',
['Lá']='Ládylumps:BAAANQADCgcIBwABNQAECgQIBAAGAAAAAA==.',
['Lø']='Løllîe:BAAANQAECgEJAQAAAA==.',
Ma='Macarius:BAAANQAECgIIAwAAAA==.Macdee:BAAANQADCgMIAwABNQAECgQICAAGAAAAAA==.Magatai:BAAANQADCgUIBQAAAA==.Mageless:BAAANQADCgIIAgAAAA==.Magicjim:BAAANQADCgIJAgAAAA==.Magpie:BAAANQADCgYIDAAAAA==.Maimed:BAAANQAECgIIAgAAAA==.Malotan:BAAANQABCgEIAQABNQABCggICAAGAAAAAA==.Manaster:BAAANQAECgIIAQAAAA==.Manpriest:BAAANQADCgEIAQAAAA==.Maravanna:BAAANQADCgEIAQAAAA==.Martlok:BAAANQAECgEJAQAAAA==.Mathas:BAAANQAECgEIAgAAAA==.Maynis:BAAANQABCgQIBgAAAA==.Maysaveyou:BAAANQADCgYJBwAAAA==.',
Mc='Mcbrynhammer:BAAANQADCgUJDwAAAA==.',
Me='Meanwhile:BAAANQADCgUIAgAAAA==.Meowmixx:BAAANQABCgUIBQAAAA==.Merkii:BAAANQADCgYIBgABNQAECgYICQAGAAAAAA==.',
Mi='Micflinigan:BAAANQAECgUJCQAAAA==.Midnightmare:BAAANQABCgMJAQAAAA==.Milkymoomoo:BAAANQADCgQIBAAAAA==.Minarii:BAAANQAECgIIAgAAAA==.Ming:BAAANQADCgQIBAABNQAECggIHAAMAI0dAA==.Minilove:BAAANQADCgIIAwAAAA==.Misha:BAAANQABCgIJAgAAAA==.Mishelö:BAAANQAECgEJAQAAAA==.Misla:BAAANQAECgEIAQAAAA==.',
Mo='Mochimochi:BAAANQADCgQIBAAAAA==.Mommieuppies:BAAANQADCgcJCAAAAA==.Momomochi:BAAANQAECgIJAgAAAA==.Moonshae:BAAANQAECgUIEAAAAA==.Mortalbion:BAAANQAECgIIAgAAAA==.',
My='Mystiquè:BAAANQADCgYJFgAAAA==.',
Na='Naithin:BAAANQAECgEIAQAAAA==.Nalarah:BAAANQADCgQIBAAAAA==.Naviriel:BAAANQADCgYIAwABNQAECgIIAwAGAAAAAA==.',
Ne='Nerrf:BAAANQADCgUIBQAAAA==.',
Ni='Nightray:BAAANQAECgQJCAABNQAECgcIGwAEAM8bAA==.',
No='Noknik:BAAANQABCggICAAAAA==.Nonsocial:BAACNQAFFIEJAAINAAcK0w/eAAAVAgANAAcK0w/eAAAVAgA1AAQKgRgAAg0ACQodJC4BAMEDAA0ACQodJC4BAMEDAAAA.Norgaladwen:BAAANQADCggICgAAAA==.Noriisa:BAAANQAECgYIDwAAAA==.Notamathguy:BAAANQADCggIDgAAAA==.Noudders:BAAANQAECgUICQAAAA==.',
Ny='Nyvak:BAAANQADCgcIDgAAAA==.',
Od='Odinhand:BAAANQAECgcJEgAAAA==.',
Oh='Ohgreatdink:BAAANQADCgYJCwAAAA==.',
Ol='Oliissa:BAAANQADCgYJFgAAAA==.',
Oz='Ozwäld:BAAANQAECgQIBAABNQAECgkJGwAOALkeAA==.Ozwäldo:BAABNQAECoEbAAIOAAkKuR6rBAAVAwAOAAkKuR6rBAAVAwAAAA==.',
Pa='Pandapí:BAAANQADCgYIBgAAAA==.Panduh:BAABNQAECoEWAAMPAAgKxBhAcABCAgAPAAgKxBhAcABCAgAFAAIKVRJJHwB/AAAAAA==.Pandóra:BAAANQADCgcIDgAAAA==.Pariousa:BAABNQAECoEgAAIQAAkKECP3AwBeAwAQAAkKECP3AwBeAwAAAA==.',
Pe='Peppermintxo:BAAANQADCgYJDwABNQADCgIJAgAGAAAAAA==.',
Ph='Phaite:BAAANQAECggJAQAAAA==.',
Pi='Pinkeepink:BAAANQADCgYJFgAAAA==.',
Po='Popacooldown:BAAANQADCgUJCwAAAA==.',
Pr='Pres:BAAANQAECgIIAwAAAA==.Prild:BAAANQABCgQIBgAAAA==.',
Pu='Pumpernickle:BAAANQAECgQIBAAAAA==.',
Ra='Rahzon:BAAANQAECgIIAgAAAA==.Ralganor:BAAANQAECgcJEgAAAA==.Ralzin:BAAANQADCgUIDQAAAA==.Ramanash:BAAANQADCgQICAAAAA==.Randron:BAAANQADCggICAAAAA==.Raynlight:BAAANQAECgMJAwAAAA==.',
Re='Ren:BAAANQADCgUIBwAAAA==.Retacus:BAAANQADCgYICwAAAA==.',
Ri='Rina:BAAANQAFFAEIAQAAAA==.Ringadingg:BAAANQAECgQICAAAAA==.',
Ro='Rosequartz:BAAANQADCggIDQAAAA==.',
Ry='Rydia:BAAANQAECgIJBQAAAA==.',
Sa='Saladin:BAAANQADCgUIBgAAAA==.Sankatlantis:BAAANQADCgYICgAAAA==.Sarka:BAAANQADCgcIBwAAAA==.Sasquatch:BAAANQAECgIIAwAAAA==.Saunkae:BAAANQAECgMIBAAAAA==.',
Sc='Scony:BAAANQAECgQJCAAAAA==.Scribs:BAAANQADCggJGAAAAA==.Scyphen:BAAANQADCgYICQAAAA==.',
Se='Seegon:BAAANQABCgYIBQAAAA==.Seismic:BAAANQADCggJCAAAAA==.Sephirain:BAAANQADCgMIAwAAAA==.Sevelement:BAAANQAECgQICwABNQAECggIFgARAPQXAA==.Severànce:BAABNQAECoEWAAMRAAgK9BcxBwD9AQARAAcKExcxBwD9AQASAAQKyxFUOgADAQAAAA==.Sevivify:BAAANQADCgIIAwABNQAECggIFgARAPQXAA==.',
Sh='Shablammy:BAAANQAECgQJBwAAAA==.Shadowginni:BAAANQAECgIIAgAAAA==.Shadownome:BAAANQADCgMIBQAAAA==.Shammygand:BAAANQADCgUJBQABNQAECgUJCwAGAAAAAA==.Shanker:BAAANQADCgMIAwAAAA==.Shefu:BAAANQAECgMIBQAAAA==.Shfifty:BAAANQAECggJEgAAAA==.Shizamthebam:BAAANQAECgQIBAAAAA==.Shutupbird:BAAANQAECgUJCwAAAA==.',
Si='Silris:BAAANQADCgMIAwAAAA==.',
Sk='Skydragon:BAAANQADCgYJFwAAAA==.',
Sl='Slay:BAAANQAECgEJAQABNQAECgUJDQAGAAAAAA==.Slayful:BAAANQABCgQJBAAAAA==.Sleepydwarf:BAAANQADCggJCAAAAA==.Slonk:BAAANQAECgQJBAAAAA==.',
So='Sofia:BAAANQAECgIIAwAAAA==.',
Sp='Sparrtacus:BAAANQABCgUIBwAAAA==.Spiritly:BAAANQAECgMIBAAAAA==.Sploof:BAAANQAECgEJAQAAAA==.Sprynt:BAAANQAECgMIAwAAAA==.',
St='Staples:BAAANQADCgcIBwABNQAECgIIAwAGAAAAAA==.Starlighter:BAAANQADCgYIBgAAAA==.Starmist:BAAANQADCgYJFgAAAA==.Stubly:BAAANQADCgQJBAAAAA==.',
Su='Sunfyrie:BAAANQAECgQIBAAAAA==.',
Sw='Sweèt:BAAANQAECgIIAQAAAA==.',
Ta='Tagrit:BAAANQADCgUIBQAAAA==.Taldieth:BAAANQAECgIJAQAAAA==.Taurdk:BAAANQAECgUJBwAAAA==.Taylorshift:BAAANQAECgYJCgAAAA==.',
Te='Teaar:BAAANQADCgUIBQABNQAECgUJDQAGAAAAAA==.Teetau:BAAANQAECgQJCAAAAA==.',
Th='Thadregosa:BAAANQAECgQIBQAAAA==.Thalsan:BAAANQABCgIIAgAAAA==.Thander:BAAANQADCgYIDwAAAA==.Therlisa:BAAANQADCggICAAAAA==.Thordar:BAAANQABCggICwAAAA==.',
Ti='Tibbotanical:BAAANQADCgUIBQAAAA==.Tiberius:BAAANQABCgIIAQAAAA==.Tiffy:BAAANQADCggIFwAAAA==.Tirna:BAAANQAECgEJAgAAAA==.Tirnotham:BAAANQAECgEJAQAAAA==.',
Tm='Tmtglizzy:BAAANQAECggJDQAAAA==.',
To='Tokalu:BAAANQAECgIIAwAAAA==.Tonjudsonson:BAABNQAECoEhAAITAAkKJCNBAQCVAwATAAkKJCNBAQCVAwAAAA==.Torath:BAAANQADCgYJCwABNQADCgYIDwAGAAAAAA==.',
Tu='Turdimer:BAAANQADCgYJGAAAAA==.',
Tw='Twiki:BAAANQAECgEJAgAAAA==.Twobricks:BAAANQAECgcJEgAAAA==.',
Ty='Tyrielas:BAAANQADCgYIBwAAAA==.Tyrssana:BAAANQAECgEJAQABNQAECgcJEwAGAAAAAA==.',
['Tö']='Töketsu:BAAANQADCgYIBgAAAA==.',
Uh='Uhmerica:BAAANQAECgcJEgAAAA==.',
Ur='Urdeadtoo:BAAANQAECgQJBAAAAA==.Urlacher:BAAANQADCgUIBgAAAA==.Urthkwayk:BAAANQADCgYIBgAAAA==.',
Va='Vaedryn:BAAANQADCgUIBQAAAA==.Vaterunser:BAAANQAECgEJAQAAAA==.Vazoom:BAAANQAECgIIAwAAAA==.',
Ve='Velskud:BAAANQADCgYJFQAAAA==.Vertexx:BAAANQADCgYJBgAAAA==.',
Vi='Vierth:BAAANQADCgIIAgABNQADCgYIBgAGAAAAAA==.Vinhar:BAAANQADCgUICAAAAA==.Visea:BAAANQADCgIIAgABNQADCgYIBgAGAAAAAA==.',
Vo='Voidsavage:BAAANQADCgYIFAAAAA==.Voidwing:BAAANQAECgQIBAAAAA==.Volic:BAAANQAECgQJCAAAAQ==.Vollken:BAAANQADCgYICAAAAA==.Voznje:BAAANQAECgEIBAAAAA==.',
We='Wesleypipes:BAAANQAECgYJDAAAAA==.',
Wh='Whisteria:BAAANQADCgYIBgAAAA==.',
Wi='Wizalf:BAAANQADCggIEgAAAA==.',
Wm='Wmrx:BAAANQADCgYIBgAAAA==.',
Wo='Wodalpala:BAAANQAECgcICQAAAA==.Wolfmato:BAAANQAECgYICwAAAA==.',
Wy='Wynne:BAAANQADCggJEgAAAA==.',
Xa='Xalabro:BAAANQAECgQJBwAAAA==.',
Xe='Xerxeis:BAAANQABCgYICAABNQADCgcIEwAGAAAAAA==.',
Xo='Xousa:BAAANQADCgQIBgABNQAECgkJIAAQABAjAA==.',
Yh='Yhorn:BAAANQADCgcIBwABNQAFFAUJCQACAKYZAA==.',
Ys='Yssuplef:BAAANQAECgEJAQAAAA==.',
Yu='Yuefei:BAAANQADCgQJBAAAAA==.',
Za='Zaiyra:BAAANQADCgcIDwAAAA==.Zakoor:BAAANQADCgYIFAAAAA==.Zareena:BAAANQADCgYJFgAAAA==.Zarnia:BAAANQADCgMIAwAAAA==.Zarrock:BAAANQADCgIJAgAAAA==.Zavatan:BAAANQADCgQIBwAAAA==.',
Ze='Zebbyzebzeb:BAAANQADCgYJGQAAAA==.Zekia:BAAANQAECgYIDgAAAA==.Zepirra:BAAANQABCgcIDgAAAA==.Zerm:BAAANQAECgQICwAAAA==.Zerodeath:BAAANQADCgYJBgAAAA==.',
Zi='Zinnkura:BAAANQAECgEJAQAAAA==.',
Zo='Zorsa:BAAANQADCgYIFgAAAA==.',
Zu='Zuljawn:BAAANQAECgQJCAAAAA==.',
Zy='Zyphos:BAAANQADCgIIAgAAAA==.',
['Ñô']='Ñôg:BAAANQADCggICQAAAA==.',
['Ød']='Ødis:BAAANQADCggIFwAAAA==.',
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
