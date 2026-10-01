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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Monk-Windwalker','Warrior-Arms','Warrior-Fury','Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Paladin-Protection','Paladin-Retribution','Warlock-Demonology','Warlock-Destruction','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','Mage-Frost','Mage-Arcane','Rogue-Outlaw','Druid-Balance','Druid-Guardian','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Devourer','Warrior-Protection','Shaman-Enhancement','DemonHunter-Havoc',}
local provider = {region='US',realm='Warsong',name='US',type='weekly',zone=53,date='2026-09-29',data={Ag='Agp:BAACNQAFFIEHAAIBAAUKFxItBQCnAQABAAUKFxItBQCnAQA1AAQKgR8AAwEACQqFIzkMAFoDAAEACQqFIzkMAFoDAAIAAQqZDfdvADEAAAAA.',
Ah='Aharan:BAAANQAECgMIBQAAAA==.',
An='Andraxy:BAAANQAECgYICAABNQAFFAQIDwADACEYAA==.Anielor:BAAANQABCgQIBAAAAA==.',
Ar='Aratar:BAACNQAFFIEHAAMEAAQKbRQ8FAACAQAEAAMKYxg8FAACAQAFAAEKjAhRAwBTAAA1AAQKgRwAAgQACArpHJ9AAI8CAAQACArpHJ9AAI8CAAAA.Arcadia:BAAANQAECgIIAwAAAA==.Arcticheat:BAAANQAECgQIBAABNQAECgcIEgAGAAAAAA==.Arizona:BAAANQAECgQIDgAAAA==.Arkantos:BAAANQAECgcIEQAAAA==.',
As='Asta:BAAANQADCgYIBgAAAA==.',
Au='Automobeer:BAAANQADCgMIAwAAAA==.',
Aw='Awake:BAAANQADCgIIBAAAAA==.',
Ba='Bayareadady:BAAANQADCgYIDAAAAA==.',
Be='Belandra:BAAANQADCgYIAwABNQAECgUIDwAGAAAAAA==.',
Bi='Biggbird:BAAANQAECgUIDAAAAA==.',
Bj='Bjord:BAABNQAECoEeAAMBAAgKcSCWKgCxAgABAAgKcSCWKgCxAgACAAEK3gDFegAbAAABNQADCggICAAGAAAAAA==.',
Bl='Blackplague:BAAANQABCgEIAQAAAA==.',
Bo='Bossdeath:BAAANQAECgUIBQABNQAECgkJHwAEAKgdAA==.Bossdierr:BAAANQAECgcJDAABNQAECgkJHwAEAKgdAA==.Bossdisan:BAAANQAECgcICwABNQAECgkJHwAEAKgdAA==.Bossdiyi:BAABNQAECoEfAAIEAAkKqB3AHAAlAwAEAAkKqB3AHAAlAwAAAA==.Bosswudi:BAABNQAECoEhAAMHAAgKlyXjIAAeAgAHAAUK+CTjIAAeAgAIAAUK/iN5FgAKAgABNQAECgkJHwAEAKgdAA==.',
Bu='Buttshaman:BAAANQAECgUIBgAAAA==.',
Ch='Choco:BAAANQAECgYIBAAAAA==.Chromiepip:BAAANQADCgEIAQAAAA==.',
Co='Colt:BAABNQAECoEgAAIJAAgKVRxtDQB8AgAJAAgKVRxtDQB8AgAAAA==.Corrosiveman:BAAANQAECgYICwAAAA==.Cowned:BAAANQADCgYIBgABNQAECgkJGgAKACohAA==.',
Cr='Creamy:BAAANQAECgUJCwAAAA==.',
Da='Daer:BAAANQADCgQIBAAAAA==.Danielpana:BAACNQAFFIEPAAIDAAQKIRjPBQBOAQADAAQKIRjPBQBOAQA1AAQKgSYAAgMACQpMI10GAEoDAAMACQpMI10GAEoDAAAA.Darkfyre:BAAANQAECgYIEgAAAA==.Darkraider:BAAANQAECgQIBAAAAA==.',
Di='Dinkledots:BAAANQADCgUIBQABNQAECgYIDQAGAAAAAA==.Dinks:BAAANQAECgYIDQAAAA==.Dishwasher:BAAANQAECgYIDAAAAA==.',
Do='Docc:BAAANQAECgYICAAAAA==.Doe:BAAANQADCgYIBgABNQAECgUIDQAGAAAAAA==.Doii:BAAANQADCgQIBAABNQAECgUIDQAGAAAAAA==.',
Dr='Dragonfyre:BAAANQADCggIHwAAAA==.Drood:BAAANQADCgUIBQAAAA==.',
Du='Duration:BAAANQAECgYIBwAAAA==.',
Ek='Ektyr:BAAANQAECgMIBAABNQADCggICAAGAAAAAA==.',
Em='Emiliam:BAAANQAECgUIBQAAAA==.',
Er='Erdrick:BAAANQADCgQIBAAAAA==.Ero:BAAANQADCggIEgAAAA==.',
Ev='Evërjzy:BAAANQADCggIDAAAAA==.',
Fa='Faded:BAAANQAECgMIAwAAAA==.Fatheralvin:BAAANQABCgUIDAAAAA==.',
Fe='Feronar:BAAANQAECgYIDgAAAA==.',
Fl='Flume:BAAANQAECgcIDAAAAA==.',
Fx='Fx:BAAANQAECgUIDQAAAA==.',
['Fú']='Fúsión:BAEANQAECgEIAQABNQAECgkJFwAHAEYhAA==.',
Ga='Galedra:BAAANQAECgUIDwAAAA==.Gargomash:BAAANQAECgIIAgAAAA==.',
Gi='Gin:BAAANQADCggIGgABNQAECgkJJQABADwaAA==.',
Gj='Gjana:BAABNQAECoEfAAMLAAkKsxOdPwBUAgALAAkKsxOdPwBUAgAMAAUKEwWlNgDSAAABNQAECgkJHwANAHgXAA==.',
Go='Goomy:BAAANQAECgIIAgAAAA==.Gorlash:BAAANQADCgYIBgAAAA==.',
Gr='Gravemaw:BAAANQADCgcJBwAAAA==.Greenboi:BAAANQADCgcIEgAAAA==.Grimgeth:BAABNQAECoElAAMOAAkKAhiIKwAwAgAOAAgKIRmIKwAwAgAPAAYKaw44PQBjAQAAAA==.Grimwrath:BAAANQAECgYIEQABNQAECgkJJQAOAAIYAA==.Grouch:BAABNQAECoEfAAINAAkKeBeNJwCpAgANAAkKeBeNJwCpAgAAAA==.',
Gu='Guanine:BAAANQAECgUIDQAAAA==.Gudeath:BAAANQAECgYIDwAAAA==.Guishin:BAAANQADCggICAAAAA==.',
He='Heontwo:BAAANQAECgIIAgAAAA==.Heshan:BAABNQAECoEmAAMQAAkKbxrSAwDAAgAQAAkKbxrSAwDAAgARAAcKaQwWwgCwAQAAAA==.',
Ho='Hoodwink:BAAANQADCgYIBwAAAA==.',
Im='Imortathorin:BAAANQADCggJCQAAAA==.',
In='Insanities:BAAANQAECgcIEgAAAA==.',
Ja='Jaidie:BAAANQAECgQICAAAAA==.Jarco:BAECNQAFFIELAAISAAYKsxU9AAAaAgASAAYKsxU9AAAaAgA1AAQKgSMAAxIACQr1Iz4BAHADABIACQoKIz4BAHADAAgACQphHnMHAPACAAAA.',
Je='Jebussaves:BAAANQADCggICQAAAA==.Jerlonge:BAAANQADCggICAAAAA==.',
Jo='Joak:BAAANQADCgIIAgAAAA==.',
Ka='Kaidou:BAABNQAFFIEGAAILAAUKpRd1BgCmAQALAAUKpRd1BgCmAQAAAA==.Kasaar:BAAANQADCgIIAgAAAA==.',
Ki='Kitsune:BAABNQAECoEaAAMTAAgK9gXNTABeAQATAAgKYQXNTABeAQAUAAQKmQUtLwCRAAAAAA==.',
Kr='Kryptix:BAAANQAECgcIEAAAAA==.',
Ku='Kubicki:BAAANQAECgcIDQAAAA==.Kubimage:BAAANQADCgYIBgAAAA==.Kurta:BAAANQADCgEIAQAAAA==.',
La='Lastlife:BAAANQADCgUIDgAAAA==.Lastshamurai:BAAANQADCgUIBQAAAA==.Layona:BAAANQAECgYIDQAAAA==.',
Li='Linelli:BAACNQAFFIEGAAMVAAQK8BuhAAAXAQAVAAMKjRmhAAAXAQABAAEKGCMsHgBpAAA1AAQKgRgAAxUABwpFJFcCAOgCABUABwpFJFcCAOgCAAEABwobHJhUACMCAAAA.',
Lo='Lobixona:BAAANQADCggJDwAAAA==.Lowakacho:BAAANQADCgQIBAAAAA==.',
Lx='Lxrbread:BAABNQAECoEjAAQWAAkKtAbgHQCsAQAWAAkKtAbgHQCsAQAXAAYKzxOzCgBmAQAYAAMKOwdwKgCEAAAAAA==.',
['Lì']='Lìlith:BAAANQAECgQIBAABNQAFFAUIBwAZAMYTAA==.',
Ma='Maccazilla:BAAANQADCgYICgAAAA==.Magdalena:BAAANQAECgYIDgABNQAECgcIDwAGAAAAAA==.',
Me='Meatkleaver:BAAANQAECgcIEQAAAA==.Mech:BAAANQAFFAIIAwABNQAFFAIIAwAGAAAAAQ==.Merbs:BAAANQAECgQIBwAAAA==.',
Mo='Mochi:BAAANQAECgQICgAAAA==.Mommydeath:BAAANQADCgYIBgAAAA==.Morbius:BAAANQAECggICAAAAA==.Morholt:BAAANQADCgMIAwAAAA==.',
Ne='Necromortas:BAAANQAECgYIEgAAAA==.',
Ni='Nira:BAAANQADCgYICgAAAA==.',
No='Notlrahc:BAAANQAECgQIDAAAAA==.',
Ny='Nyki:BAAANQADCgYICAAAAA==.',
Pa='Padriac:BAAANQADCgQIBAAAAA==.Paolinelli:BAAANQAECgcICQABNQAFFAQIBgAVAPAbAA==.Pattêrn:BAAANQADCggIDQAAAA==.Paìn:BAABNQAECoE2AAIZAAkKqiWjAADsAwAZAAkKqiWjAADsAwABNQAFFAUIBwAZAMYTAA==.',
Pe='Pedri:BAACNQAFFIEHAAIOAAMKsyVFBwAwAQAOAAMKsyVFBwAwAQA1AAQKgSYAAw4ACQr1JoAAAP0DAA4ACQr1JoAAAP0DAA8AAQqUHZWAADkAAAAA.Pedrok:BAABNQAECoEcAAMEAAgKQAkqjACiAQAEAAgKQAkqjACiAQAaAAEK2wGZOgAeAAAAAA==.',
Pi='Pinkdot:BAAANQADCgYIBwAAAA==.',
Po='Popius:BAAANQAECgQICQAAAA==.Pothtwo:BAAANQADCgUIBQAAAA==.',
Pr='Prentiss:BAAANQADCgYIBgAAAA==.Promorph:BAAANQAECgEIAQAAAA==.',
Pu='Puups:BAAANQADCgYICAAAAA==.',
['Pì']='Pìngü:BAAANQAECgYIEgAAAA==.',
Ra='Raph:BAABNQAECoElAAIOAAkKAh95FwDGAgAOAAkKAh95FwDGAgAAAA==.',
Re='Rednoser:BAAANQAECgYICwAAAA==.Redthepriest:BAAANQADCgMIAwAAAA==.Remmahcm:BAAANQAECggIDgAAAA==.Reverse:BAAANQADCgYIBgABNQAFFAUIBwABABcSAA==.',
Sa='Sagas:BAABNQAECoEeAAIbAAgKvxvsCQChAgAbAAgKvxvsCQChAgAAAA==.Sambiquira:BAAANQAECgIIAgAAAA==.Sarial:BAABNQAECoEaAAMcAAkKRyPJBgBrAwAcAAkK+B/JBgBrAwAZAAkKzRkSEgC0AgAAAA==.Saryeras:BAAANQADCgQIBAABNQADCggICAAGAAAAAA==.',
Sc='Scrit:BAAANQAECgIIBAAAAA==.',
Si='Sil:BAAANQAECgcIDgAAAA==.',
Sk='Ska:BAAANQAECgIIAgAAAA==.',
So='Softbutt:BAAANQADCgIIAgAAAA==.Soulreaper:BAAANQADCgcJDgABNQAECgUIDQAGAAAAAA==.',
Sq='Squish:BAAANQADCgEJAQAAAA==.',
St='Staby:BAAANQADCgYIBgABNQAECgMIAwAGAAAAAA==.',
Sy='Syrensong:BAAANQABCgUIBQAAAA==.',
Ta='Tapechewer:BAAANQADCgUICgAAAA==.Tatax:BAAANQAECggIDAABNQAFFAQIDwADACEYAA==.',
Te='Teto:BAAANQADCgYIBwAAAA==.Tetsunen:BAAANQAECgQICgAAAA==.',
Th='Thralson:BAAANQADCgQIBAAAAA==.',
To='Tog:BAAANQADCgIIAgAAAA==.Toggywoggy:BAAANQAECgcIEwAAAA==.Tortoisetoes:BAAANQAECgEIBAABNQAECgcIEgAGAAAAAA==.',
Tu='Turok:BAAANQAECgQIBgAAAA==.',
Ur='Urra:BAAANQAECggIBAAAAA==.',
Ve='Velo:BAAANQAECgEIAQAAAA==.Verminardy:BAAANQABCgMIBAAAAA==.',
Wa='Wanheda:BAABNQAECoEXAAIBAAgK7xuuLwCdAgABAAgK7xuuLwCdAgAAAA==.Wargyu:BAACNQAFFIEHAAIEAAMKGBbmFAD4AAAEAAMKGBbmFAD4AAA1AAQKgTkAAgQACQpMIcYZADQDAAQACQpMIcYZADQDAAAA.Watertort:BAAANQAECggICgAAAA==.',
We='Weezard:BAAANQADCgYIEAABNQAECgkJHwANAHgXAA==.',
Wo='Woobley:BAAANQADCgcICQAAAA==.',
Yn='Ynup:BAAANQADCgcIFQAAAA==.',
Za='Zardnax:BAAANQADCgUICAAAAA==.',
Ze='Zel:BAAANQADCgIIAgAAAA==.Zenin:BAAANQAECgMIAwABNQADCggICAAGAAAAAA==.Zenjamin:BAAANQAECgEIAQABNQADCggICAAGAAAAAA==.Zenu:BAAANQADCggICAAAAA==.',
Zu='Zuleika:BAAANQAECgUIDwAAAA==.',
['Øm']='Ømen:BAAANQAECgEIAgAAAA==.',
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
