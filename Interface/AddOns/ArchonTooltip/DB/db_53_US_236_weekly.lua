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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Monk-Windwalker','Warrior-Arms','Warrior-Fury','Priest-Discipline','Paladin-Protection','Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Evoker-Preservation','Paladin-Retribution','Monk-Mistweaver','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Elemental','Mage-Frost','Mage-Arcane','Priest-Holy','Rogue-Outlaw','Druid-Balance','Druid-Guardian','Hunter-Survival','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Devourer','Druid-Feral','Warrior-Protection','Shaman-Enhancement','DemonHunter-Havoc',}
local provider = {region='US',realm='Warsong',name='US',type='weekly',zone=53,date='2026-10-06',data={Ag='Agp:BAACNQAFFIEHAAIBAAUKFxImCACfAQABAAUKFxImCACfAQA1AAQKgR8AAwEACQqFI6USAD8DAAEACQqFI6USAD8DAAIAAQqZDUN+ADEAAAAA.',
Ah='Aharan:BAAANQAECgUICgAAAA==.',
Al='Aleria:BAAANQADCgQIBQAAAA==.',
An='Andraxy:BAAANQAECgYICAABNQAFFAQIDwADACEYAA==.Anielor:BAAANQABCgQIBAAAAA==.',
Ar='Aratar:BAACNQAFFIEHAAMEAAQKbRQDGgD9AAAEAAMKYxgDGgD9AAAFAAEKjAhKBABRAAA1AAQKgR4AAgQACArpHEhSAHgCAAQACArpHEhSAHgCAAAA.Arcadia:BAAANQAECgQIBwAAAA==.Arcticheat:BAAANQAECgQIBAABNQAECgkJHQAGADkZAA==.Arizona:BAAANQAECgYIEwAAAA==.Arkantos:BAAANQAECgcIEQAAAA==.',
As='Asta:BAAANQADCgYIBgAAAA==.',
Au='Automobeer:BAAANQADCgMIAwAAAA==.',
Aw='Awake:BAAANQADCgIIBAAAAA==.',
Ba='Bakedsham:BAAANQADCgEIAQAAAA==.Bayareadady:BAAANQADCgYIDQAAAA==.',
Be='Belandra:BAAANQADCgYIAwABNQAECgYIGAAHAHMgAA==.',
Bi='Biggbird:BAAANQAECgUIEAAAAA==.',
Bj='Bjord:BAABNQAECoEhAAMBAAgKpCDBNACrAgABAAgKpCDBNACrAgACAAEK3gDKiwAbAAABNQADCggICAAIAAAAAA==.',
Bl='Blackplague:BAAANQABCgEIAQAAAA==.',
Bo='Bossdeath:BAAANQAECgUIBQABNQAECggIJwAJAMMlAA==.Bossdierr:BAAANQAECggIEAABNQAECggIJwAJAMMlAA==.Bossdisan:BAAANQAECggIEQABNQAECggIJwAJAMMlAA==.Bossdiyi:BAABNQAECoEkAAIEAAkKQSEXEAB4AwAEAAkKQSEXEAB4AwABNQAECggIJwAJAMMlAA==.Bosswudi:BAABNQAECoEnAAMJAAgKwyXyJgAmAgAJAAUKxCXyJgAmAgAKAAUK/iMnGQD/AQAAAA==.',
Br='Bruh:BAAANQAECgUIBgAAAA==.',
Bu='Buffmw:BAEANQADCgIIAgABNQAFFAkJJwALAIQeAA==.Buttshaman:BAAANQAECgUICwAAAA==.',
Ca='Cazadòr:BAAANQADCgYIBgAAAA==.',
Ch='Choco:BAAANQAECggICwAAAA==.Chromiepip:BAAANQADCgEIAQAAAA==.',
Co='Colt:BAABNQAECoEgAAIHAAgKSxz0DwB3AgAHAAgKSxz0DwB3AgAAAA==.Corrosiveman:BAAANQAECgYIDwAAAA==.Cowned:BAAANQADCgYIBgABNQAECgkJHAAMACAiAA==.',
Cr='Creamy:BAAANQAECgUJCwAAAA==.',
Da='Daer:BAAANQADCgQIBAAAAA==.Danielpana:BAACNQAFFIEPAAIDAAQKIRihBwA3AQADAAQKIRihBwA3AQA1AAQKgSYAAgMACQpMIxAJACsDAAMACQpMIxAJACsDAAAA.Darkfyre:BAABNQAECoEbAAINAAgK4hD+GQCzAQANAAgK4hD+GQCzAQAAAA==.Darkraider:BAAANQAFFAEIAQAAAA==.',
Di='Dinkledots:BAAANQADCgUIBQABNQAECgYIEgAIAAAAAA==.Dinks:BAAANQAECgYIEgAAAA==.Dishwasher:BAAANQAECgcIDQAAAA==.',
Do='Docc:BAAANQAECgYICAAAAA==.Doe:BAAANQADCgYIBgABNQAECgYIEwAIAAAAAA==.Doii:BAAANQADCgQIBAABNQAECgYIEwAIAAAAAA==.',
Dr='Dragonfyre:BAAANQADCggIHwAAAA==.Drood:BAAANQADCgUIBQAAAA==.',
Du='Duration:BAAANQAECgYICwAAAA==.',
Ek='Ektyr:BAAANQAECgQICAABNQADCggICAAIAAAAAA==.',
Em='Emiliam:BAAANQAECggIDQAAAA==.',
Er='Erdrick:BAAANQAECgIIAgAAAA==.Ero:BAAANQAECgUIBQAAAA==.',
Ev='Evërjzy:BAAANQADCggIDAAAAA==.',
Fa='Faded:BAAANQAECgMIAwAAAA==.Fatheralvin:BAAANQABCgUIDAAAAA==.',
Fe='Feronar:BAAANQAECgYIEwAAAA==.',
Fl='Flume:BAAANQAECgcIDAAAAA==.',
Fx='Fx:BAAANQAECgYIEwAAAA==.',
['Fú']='Fúsión:BAEANQAECgEIAQABNQAECgkJGAAJAMchAA==.',
Ga='Galedra:BAABNQAECoEYAAIHAAYKcyBqFgAiAgAHAAYKcyBqFgAiAgAAAA==.Gargomash:BAAANQAECgIIAgAAAA==.',
Gi='Gin:BAAANQADCggIGgABNQAECgkJLgABAEseAA==.',
Gj='Gjana:BAABNQAECoEqAAMOAAkKrRntMwCfAgAOAAkKrRntMwCfAgAPAAUKEwVPOgDNAAAAAA==.',
Go='Goomy:BAAANQAECgQIBQAAAA==.Gorlash:BAAANQADCgYIBgAAAA==.',
Gr='Gravemaw:BAAANQADCgcJBwAAAA==.Greenboi:BAAANQADCgcIEgAAAA==.Grimfeather:BAAANQAECgYIBgAAAA==.Grimgeth:BAABNQAECoEuAAMQAAkKbRkEKwBoAgAQAAkKbRkEKwBoAgARAAcKSRHKOQCrAQAAAA==.Grimwrath:BAAANQAECgcIEgABNQAECgkJLgAQAG0ZAA==.Grouch:BAABNQAECoEoAAISAAkKGhroKQC2AgASAAkKGhroKQC2AgABNQAECgkJKgAOAK0ZAA==.',
Gu='Guanine:BAAANQAECgYIEgAAAA==.Gudeath:BAAANQAECgYIDwAAAA==.Guishin:BAAANQADCggIEAAAAA==.Guyver:BAAANQADCgYIBgAAAA==.',
He='Heidriel:BAAANQADCgIIAgAAAA==.Heontwo:BAAANQAECgIIAgAAAA==.Heshan:BAABNQAECoEtAAMTAAkKoRuZBgBpAgATAAkKoRuZBgBpAgAUAAcKlA5I0gC8AQAAAA==.',
Ho='Hoodwink:BAAANQADCgYIBwAAAA==.',
Im='Imortathorin:BAAANQADCggJCQAAAA==.',
In='Insanities:BAABNQAECoEdAAMGAAkKORnICQCfAQAVAAgKTBIkUAAJAgAGAAUKyxzICQCfAQAAAA==.',
Ja='Jaidie:BAAANQAECgQICQAAAA==.Jarco:BAECNQAFFIELAAIWAAYKsxVnAAAQAgAWAAYKsxVnAAAQAgA1AAQKgSMAAxYACQr1I48BAGEDABYACQoKI48BAGEDAAoACQphHukIANwCAAAA.',
Je='Jebussaves:BAAANQADCggICQAAAA==.Jerlonge:BAAANQADCggIEAAAAA==.',
Jo='Joak:BAAANQADCgIIAgAAAA==.',
Ka='Kasaar:BAAANQADCgIIAgAAAA==.',
Ki='Kitsune:BAABNQAECoEgAAMXAAgKegbPUQBpAQAXAAgKdQbPUQBpAQAYAAQKmQWHOgCOAAAAAA==.',
Kr='Kryptix:BAABNQAECoEZAAIVAAgKeB5dJAC9AgAVAAgKeB5dJAC9AgAAAA==.',
Ku='Kubicki:BAAANQAECgcIDQAAAA==.Kubimage:BAAANQADCgYIBgAAAA==.Kurta:BAAANQADCgEIAQAAAA==.',
La='Lastlife:BAAANQADCgUIDgAAAA==.Lastshamurai:BAAANQADCgUIBQAAAA==.Layona:BAAANQAECgYIDQAAAA==.',
Li='Linelli:BAACNQAFFIELAAMZAAUKBCFJAAAMAgAZAAUKTh5JAAAMAgABAAEKGCPeJQBnAAA1AAQKgSAAAxkACArcJdgAAIcDABkACArcJdgAAIcDAAEABwobHLlhACgCAAAA.',
Lo='Lobixona:BAAANQADCggIFAAAAA==.Lowakacho:BAAANQADCgQIBAAAAA==.',
Lx='Lxrbread:BAABNQAECoEnAAQLAAkKtAZOIQClAQALAAkKtAZOIQClAQAaAAYKGxSdDABgAQAbAAMKOwdPLgCCAAAAAA==.',
['Lì']='Lìlith:BAAANQAECgQIBAABNQAFFAUIBgAcAFAUAA==.',
Ma='Maccazilla:BAAANQADCgYICgAAAA==.Magdalena:BAABNQAECoEYAAIDAAkKWyDFCQAgAwADAAkKWyDFCQAgAwAAAA==.Martini:BAAANQAECgQIBAAAAA==.',
Me='Meatkleaver:BAAANQAECgcIEQAAAA==.Mech:BAABNQAECoFjAAMYAAkK3iYjAAAVBAAYAAkK3iYjAAAVBAAdAAgKFh/8BQDqAgAAAA==.Merbs:BAAANQAECgQIBwAAAA==.',
Mo='Mochi:BAAANQAECggIEwAAAA==.Mommydeath:BAAANQADCgYIBgAAAA==.Morbius:BAAANQAECggICAAAAA==.Morholt:BAAANQADCgMIAwAAAA==.',
Ne='Necromortas:BAABNQAECoEaAAMOAAcK1BYhagD3AQAOAAcK1BYhagD3AQAPAAEKEgM8ewAqAAAAAA==.',
Ni='Nipnaxes:BAAANQADCgIIAgAAAA==.Nira:BAAANQADCgYICgAAAA==.',
No='Notlrahc:BAAANQAECgQIDAAAAA==.',
Ny='Nyki:BAAANQADCgYICAAAAA==.',
Pa='Padriac:BAAANQADCgQIBAAAAA==.Paolinelli:BAAANQAECgcICQABNQAFFAUICwAZAAQhAA==.Pattêrn:BAAANQADCggIDQAAAA==.Paìn:BAACNQAFFIEGAAIcAAUKUBT+BgCAAQAcAAUKUBT+BgCAAQA1AAQKgToAAhwACQoFJsIAAOoDABwACQoFJsIAAOoDAAAA.',
Pe='Pedri:BAACNQAFFIEKAAIQAAMK2ib4CABfAQAQAAMK2ib4CABfAQA1AAQKgSwAAxAACQr1JjoBAOsDABAACQr1JjoBAOsDABEAAQqUHaSQADgAAAAA.Pedrok:BAABNQAECoEjAAMEAAgKEgp0mQCzAQAEAAgKEgp0mQCzAQAeAAEK2wGBQwAZAAAAAA==.',
Ph='Phael:BAAANQAECgIIAgAAAA==.',
Pi='Pinkdot:BAAANQADCgYIBwAAAA==.',
Po='Popius:BAAANQAECgQICQAAAA==.Pothtwo:BAAANQADCgUIBQAAAA==.',
Pr='Prentiss:BAAANQADCgcIDAAAAA==.Promorph:BAAANQAECgEIAgAAAA==.',
Pu='Puups:BAAANQADCgYICAAAAA==.',
['Pì']='Pìngü:BAAANQAECgYIEgAAAA==.',
Ra='Raph:BAABNQAECoErAAIQAAkK+iAMEAAiAwAQAAkK+iAMEAAiAwAAAA==.',
Re='Rednoser:BAAANQAECgYIDgAAAA==.Redthepriest:BAAANQADCgMIAwAAAA==.Remmahcm:BAAANQAECggIDgAAAA==.Reverse:BAAANQADCgYIBgABNQAFFAUIBwABABcSAA==.Rexnor:BAAANQADCgQIBAAAAA==.',
Sa='Sagas:BAABNQAECoElAAIfAAkK1R4JBQA0AwAfAAkK1R4JBQA0AwAAAA==.Sambiquira:BAAANQAECgIIAgAAAA==.Sarial:BAABNQAECoEiAAMgAAkK7yMWBACoAwAgAAkK7yMWBACoAwAcAAkKzRmfFQCeAgAAAA==.Saryeras:BAAANQADCgQIBAABNQADCggICAAIAAAAAA==.',
Sc='Scrit:BAAANQAECgMIBgAAAA==.',
Si='Sil:BAAANQAECgcIDgAAAA==.',
Sk='Ska:BAAANQAECgIIBAAAAA==.',
So='Softbutt:BAAANQADCgIIAgAAAA==.Soulreaper:BAAANQADCgcJDgABNQAECgYIEwAIAAAAAA==.',
Sq='Squish:BAAANQADCgEJAQAAAA==.',
St='Staby:BAAANQADCgYIBgABNQAECgMIAwAIAAAAAA==.',
Sy='Syrensong:BAAANQABCgUIBgAAAA==.',
Ta='Tapechewer:BAAANQADCgUICgAAAA==.Tatax:BAAANQAECggIDAABNQAFFAQIDwADACEYAA==.',
Te='Tertlepaws:BAAANQADCgMIAwABNQAECgcIEgAIAAAAAA==.Teto:BAAANQADCgYIBwAAAA==.Tetsunen:BAAANQAECgQIDgAAAA==.',
Th='Thralson:BAAANQADCgQIBAAAAA==.',
To='Tog:BAAANQADCgIIAgAAAA==.Toggywoggy:BAAANQAECgcIEwAAAA==.Tortoisetoes:BAAANQAECgEIBAABNQAECgcIEgAIAAAAAA==.',
Tu='Turok:BAAANQAECgUIBwAAAA==.',
Ur='Urra:BAAANQAECggIBAAAAA==.',
Ve='Velo:BAAANQAECgEIAQAAAA==.Verminardy:BAAANQABCgMIBAAAAA==.',
Wa='Wanheda:BAABNQAECoEdAAIBAAkKVR4ZGwATAwABAAkKVR4ZGwATAwAAAA==.Wargyu:BAACNQAFFIENAAIEAAQKLxriEgBeAQAEAAQKLxriEgBeAQA1AAQKgUQAAgQACQqLI8MOAIADAAQACQqLI8MOAIADAAAA.Watertort:BAAANQAECggIEAAAAA==.',
We='Weezard:BAAANQADCgYIEAABNQAECgkJKgAOAK0ZAA==.',
Wo='Woobley:BAAANQADCgcICQAAAA==.',
Yn='Ynup:BAAANQADCgcIFQAAAA==.',
Za='Zardnax:BAAANQAECgEIAQAAAA==.',
Ze='Zel:BAAANQADCgIIAgAAAA==.Zenin:BAAANQAECgUICAABNQADCggICAAIAAAAAA==.Zenjamin:BAAANQAECgEIAQABNQADCggICAAIAAAAAA==.Zenu:BAAANQADCggICAAAAA==.',
Zu='Zuleika:BAAANQAECgYIEAAAAA==.',
['Øm']='Ømen:BAAANQAECgMIBAAAAA==.',
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
