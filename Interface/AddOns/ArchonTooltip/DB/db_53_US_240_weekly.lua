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

local lookup = {'Rogue-Assassination','Druid-Balance','Paladin-Holy','Unknown-Unknown','Priest-Holy','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','DeathKnight-Blood','DeathKnight-Unholy','Monk-Mistweaver','Paladin-Retribution','Evoker-Augmentation','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Fury','Evoker-Preservation','Shaman-Restoration','Rogue-Subtlety','Druid-Restoration',}
local provider = {region='US',realm='Winterhoof',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aardin:BAABNQAECoEZAAIBAAcK4g4ZNwC8AQABAAcK4g4ZNwC8AQAAAA==.',
Ad='Adyrill:BAAANQADCgYICwAAAA==.',
Ai='Ailani:BAAANQADCgIIAgAAAA==.Airnantas:BAAANQADCgEIAQABNQAECgcIHAACALUWAA==.',
Al='Allure:BAAANQAECgUIDwAAAA==.',
Am='Amadin:BAABNQAECoEwAAIDAAkK0xyqHwDaAgADAAkK0xyqHwDaAgAAAA==.Amoralibash:BAAANQADCgYICwABNQAECgcIHAACALUWAA==.',
An='Anguskhan:BAAANQADCggIFQAAAA==.Anhafal:BAAANQADCgYIDwAAAA==.',
Ao='Aoife:BAABNQAECoEZAAIDAAcKlxvsRgAsAgADAAcKlxvsRgAsAgAAAA==.Aosin:BAAANQAECgMIAwABNQAECgQICQAEAAAAAA==.',
Ap='Apocalipze:BAAANQADCgUICwAAAA==.',
Ar='Aragosa:BAAANQABCgQIBQAAAA==.Archdruid:BAAANQAECggICAAAAA==.Arileous:BAAANQADCgcIJAAAAA==.Aroes:BAAANQADCgUIBgAAAA==.Artemiza:BAAANQABCgcJDgAAAA==.',
As='Ashariel:BAAANQADCgYICwAAAA==.Asylum:BAAANQAECgQIBgAAAA==.',
Ay='Ayeamanoob:BAAANQABCgIIAgABNQABCgYICgAEAAAAAA==.',
Ba='Bambiná:BAAANQADCgQIBQAAAA==.Bar:BAAANQAECgMIBAAAAA==.Batshaun:BAAANQADCgYIBgAAAA==.',
Be='Benadryl:BAAANQAECgUICwAAAA==.',
Bh='Bhalen:BAAANQADCggIDQAAAA==.',
Bl='Bloodpear:BAAANQAECgMIAwABNQAECgcIEgAEAAAAAA==.',
Br='Brakey:BAAANQAECgYICwAAAA==.Briar:BAAANQAECgYIEwAAAA==.Brungar:BAAANQAECggIBQAAAA==.',
Bu='Bubblybear:BAAANQAECgQIBQAAAA==.Bucksdk:BAAANQAECgcIDgAAAA==.Buckshotheal:BAAANQADCgMIAwABNQAECgcIDgAEAAAAAA==.Butterworm:BAAANQAECgEIAQAAAA==.',
Ca='Castiél:BAAANQADCgYIBgAAAA==.Caín:BAAANQADCgcICgAAAA==.',
Ch='Chuckroast:BAAANQAECgUICQAAAA==.',
Cy='Cynastus:BAAANQAECgQIBgAAAA==.Cyrandalord:BAABNQAECoEfAAQFAAkK0hrJKwCaAgAFAAkKsRrJKwCaAgAGAAIKxxhFGQCHAAAHAAEK2gOQfQAfAAAAAA==.Cyrandalorr:BAAANQAECgYICwABNQAECgkJHwAFANIaAA==.',
Da='Danteghost:BAAANQADCgYIBgAAAA==.',
De='Deathzdemize:BAACNQAFFIEWAAMIAAcK5h43AQAxAgAIAAYK3CA3AQAxAgAJAAEKIhP/KQA3AAA1AAQKgVoABAgACQr+JkEAAAYEAAgACQr+JkEAAAYEAAoAAgrfJqyDAOgAAAkAAQooHhusAFMAAAAA.Demonbane:BAAANQAECgYIEAAAAA==.Demíse:BAAANQADCgEIAQAAAA==.',
Di='Dinduscuffin:BAAANQADCgcIBwABNQAFFAcIFgAIAOYeAA==.Dirtpear:BAAANQAECgcIEgAAAA==.',
Do='Doci:BAAANQADCggJFQABNQAECgYIDgAEAAAAAA==.',
Dr='Drakythor:BAAANQAECgEIAQABNQAECgkJIgALAEYaAA==.Dreadnought:BAAANQADCgUIBQAAAA==.Druisy:BAAANQAECgMIAwAAAA==.',
Dy='Dyrillin:BAABNQAECoEZAAIMAAgK8BQvfgD9AQAMAAgK8BQvfgD9AQAAAA==.',
Em='Emiragosa:BAAANQAECgEIAgAAAA==.',
Er='Erazar:BAAANQADCgUIBQABNQAECgkJHwAFANIaAA==.',
Ev='Evoker:BAACNQAFFIEHAAINAAQKKwhqBQADAQANAAQKKwhqBQADAQA1AAQKgSUAAg0ACQoJHVsEAKcCAA0ACQoJHVsEAKcCAAAA.',
Ex='Exorcizim:BAAANQADCgIIAgAAAA==.',
Fa='Facethegon:BAABNQAECoEpAAMOAAgKKx9tLgDAAgAOAAgKKx9tLgDAAgAPAAcKARv3IgAVAgAAAA==.Facethezoom:BAAANQAECgQIBAABNQAECggIKQAOACsfAA==.Father:BAAANQAECgMIAwAAAA==.',
Fe='Feld:BAAANQADCgYIDQAAAA==.Felreaper:BAAANQADCgMIAwAAAA==.Feziwig:BAAANQADCgUICgAAAA==.',
Fi='Fizbar:BAAANQADCgQIBAABNQAECgUIEAAEAAAAAA==.Fiztweaver:BAAANQADCggIDgABNQAECgUIEAAEAAAAAA==.Fizzywater:BAAANQAECgUIEAAAAA==.',
Fo='Forloyn:BAAANQAECgIIAgAAAA==.',
Fr='Frozarath:BAAANQADCggICAAAAA==.Frozntempest:BAAANQADCgYIDgAAAA==.',
Ga='Galairn:BAAANQAECgQICAAAAA==.Garlatha:BAABNQAECoEXAAIQAAcK0xPRDADHAQAQAAcK0xPRDADHAQAAAA==.',
Ge='Gellicaan:BAAANQADCgUIDwAAAA==.Geves:BAAANQAECgEIAQAAAA==.',
Go='Gortry:BAAANQADCgEIAQAAAA==.',
Gr='Gryfter:BAAANQADCggIDAAAAA==.',
Ha='Harrinarr:BAAANQAECgUIBQAAAA==.',
He='Hedgehog:BAAANQADCgYIBQAAAA==.Helbrecht:BAAANQADCgUJBQAAAA==.Hellgar:BAAANQAECgMICQAAAA==.Hellraid:BAABNQAECoEcAAICAAcKtRYFPADqAQACAAcKtRYFPADqAQAAAA==.',
Ho='Holysquid:BAAANQADCggIDAAAAA==.Hordebreaker:BAAANQADCggICAAAAA==.',
Hu='Humblépié:BAAANQADCgMIAwAAAA==.',
Hy='Hydrosavior:BAAANQAECgUIDAAAAA==.',
Il='Illbegood:BAAANQADCgQIBAAAAA==.',
Im='Impearing:BAAANQADCgcIBwABNQAECgcIEgAEAAAAAA==.',
In='Initalog:BAAANQADCgUIBQAAAA==.',
It='Ithlaris:BAAANQADCgUIBQAAAA==.',
Iz='Izakura:BAAANQAECgUIBQAAAA==.Izumi:BAABNQAECoEeAAIRAAgKhxlbFABWAgARAAgKhxlbFABWAgAAAA==.',
Ja='Jasperr:BAABNQAECoEdAAIJAAcKGxn1NQATAgAJAAcKGxn1NQATAgAAAA==.',
Je='Jenai:BAAANQADCgMIBQAAAA==.',
Ji='Jigsaw:BAAANQADCgYIBgAAAA==.Jinmoso:BAAANQADCgcICwAAAA==.Jinsha:BAAANQAECgYIDAAAAA==.Jiéqu:BAAANQAECgUICgAAAA==.',
Jo='Jojodimojo:BAAANQADCgUIDAAAAA==.Joker:BAAANQADCgYICgAAAA==.Jomama:BAAANQAECgYICwAAAA==.',
['Jö']='Jörmungandr:BAAANQADCgUIEQAAAA==.',
Ka='Kaitnahar:BAAANQADCggICQABNQAECgcIHAACALUWAA==.Kalunom:BAAANQABCggIBQAAAA==.Katiperry:BAAANQAECgUICQAAAA==.',
Kk='Kk:BAAANQAECgUICQAAAA==.',
Ky='Kylowren:BAAANQADCgcIBgAAAA==.',
La='Laloyd:BAAANQABCgIIAgAAAA==.Lawbreaker:BAAANQAECgMIAwAAAA==.',
Le='Leora:BAAANQADCggIDAAAAA==.',
Li='Liana:BAAANQADCgMIAwAAAA==.',
Lo='Lobotamy:BAAANQADCgUIDQAAAA==.Lockycharms:BAAANQADCgUIEAAAAA==.Loremis:BAAANQADCgUIEQAAAA==.',
Lu='Lunary:BAAANQADCgUIBQABNQAECgkJHwAFANIaAA==.Lunatari:BAAANQADCggIFAAAAA==.',
Ma='Maal:BAAANQAECgEIAQAAAA==.Magetank:BAAANQAECgUIEQAAAA==.Marche:BAABNQAECoEoAAIHAAkKJCMsBgBlAwAHAAkKJCMsBgBlAwAAAA==.Mathendistus:BAAANQADCggICAABNQAECgcIHAACALUWAA==.',
Me='Meliôdas:BAAANQAECgQIBAAAAA==.Mendelson:BAAANQABCgIIAgABNQABCgYICgAEAAAAAA==.Mew:BAAANQAECgUIBgAAAA==.',
Mo='Mommy:BAAANQAECgUICwAAAA==.Moonspinner:BAAANQADCgIIAgAAAA==.Mooädib:BAAANQADCggIIgAAAA==.',
Mu='Musketeer:BAAANQADCgMIAwAAAA==.',
My='Mygore:BAAANQADCgEIAQAAAA==.Myrcy:BAAANQADCggIFQAAAA==.Mysteia:BAABNQAECoEiAAILAAkKRhqBDACaAgALAAkKRhqBDACaAgAAAA==.',
['Mà']='Màkina:BAAANQADCggIDQAAAA==.',
['Mø']='Mørdréd:BAAANQAECgEIAQAAAA==.',
Na='Naughtyhuman:BAAANQABCggIEQAAAA==.',
Ne='Necrobijuan:BAAANQADCgcIBwAAAA==.Neodragoon:BAAANQAECgEIAQABNQAECgkJHwANAEMQAA==.Neodragoonz:BAAANQADCgUIBQABNQAECgkJHwANAEMQAA==.',
Ni='Nihilist:BAABNQAECoEbAAIJAAcKUBlcNgARAgAJAAcKUBlcNgARAgAAAA==.Nihlliance:BAAANQAECgQICQAAAA==.Nitequilz:BAABNQAECoEeAAISAAcKthP5awCZAQASAAcKthP5awCZAQAAAA==.',
No='Noblessyou:BAAANQABCgUJCAABNQABCgYICgAEAAAAAA==.',
Ob='Obeejoowan:BAAANQADCggIDwAAAA==.Obeewand:BAAANQADCggIGAAAAA==.Obijuan:BAAANQADCggIOAAAAA==.',
Ou='Ouch:BAAANQAECgQICQAAAA==.',
Pa='Pandapunch:BAAANQAECgUIEgAAAA==.',
Pl='Plateguy:BAAANQAECgIIBAAAAA==.',
Po='Poxx:BAAANQAECggIEgABNQAFFAcIEgATAC4iAA==.',
Qu='Quigonjin:BAAANQAECgQIDQAAAA==.',
Ra='Raelynixii:BAAANQADCgcIEwAAAA==.Raksi:BAAANQADCgIIAgAAAA==.Ranker:BAAANQADCgUICgAAAA==.Rastion:BAAANQADCgUIEAAAAA==.',
Re='Redacted:BAAANQADCgUIEQAAAA==.Rend:BAAANQADCgQIBAAAAA==.',
Ri='Rills:BAAANQADCgQIBAAAAA==.',
Ro='Rokku:BAAANQADCgYJBgAAAA==.Rollepolle:BAAANQAECgIIAgABNQAFFAcIFgAIAOYeAA==.Roxoglam:BAAANQADCgYIBgAAAA==.',
Ru='Rueittrebeck:BAAANQABCgYICgABNQABCgYICgAEAAAAAA==.Rushs:BAAANQABCgYICgAAAA==.',
Ry='Ryleigh:BAAANQADCgQIBAAAAA==.Rynron:BAAANQADCgUICAAAAA==.',
Sa='Samraj:BAAANQAECgMIAwAAAA==.',
Se='Seithr:BAAANQADCgEIAQAAAA==.Selexa:BAAANQADCgIIAgAAAA==.Sempiternal:BAACNQAFFIEFAAIDAAMKjgmCFADfAAADAAMKjgmCFADfAAA1AAQKgS8AAgMACQqOFak2AG0CAAMACQqOFak2AG0CAAAA.Sentry:BAAANQADCgQIBAAAAA==.',
Sh='Shadowreaper:BAAANQABCgQIBAAAAA==.Shambali:BAAANQAECgEIAQABNQAECgYICwAEAAAAAA==.Shaunanigans:BAAANQAECgUIBQAAAA==.Shaunwick:BAAANQADCgMIAwABNQAECgUIBQAEAAAAAA==.Shego:BAAANQAECgUIBwAAAA==.Sheltered:BAAANQAECggIDwAAAA==.Shocktopus:BAACNQAFFIEHAAISAAQKhBdUDABeAQASAAQKhBdUDABeAQA1AAQKgR4AAhIACQpnGccfAM0CABIACQpnGccfAM0CAAAA.',
Si='Silver:BAAANQAECgEIAQAAAA==.Sinakra:BAAANQAECgYIEAAAAA==.',
Sl='Slapdaddy:BAAANQADCggIDgAAAA==.Slapdh:BAAANQADCggIDAABNQAFFAcIEgATAC4iAA==.Slaphapypapy:BAACNQAFFIESAAMTAAcKLiIEAQBtAgATAAYKCyIEAQBtAgABAAIKYSSVDQC/AAA1AAQKgSoAAxMACQptJssAANYDABMACQptJssAANYDAAEAAwqKJKhMAEMBAAAA.',
Sm='Smee:BAABNQAECoEfAAITAAcKgBKQHADcAQATAAcKgBKQHADcAQAAAA==.',
Sn='Snowyscat:BAAANQAECggIDgABNQAFFAcIFgAIAOYeAA==.',
Sp='Spirits:BAAANQAECgcIEAABNQAECggIHgARAIcZAA==.Spritz:BAAANQAECgQIDgAAAA==.',
St='Stampede:BAAANQADCggIEgAAAA==.Starshots:BAAANQADCgMIAwAAAA==.Stuey:BAAANQADCgUIEQAAAA==.',
Ta='Taburiel:BAAANQADCgYJCQAAAA==.Tanis:BAAANQAECgMIAwAAAA==.Tarstarkas:BAAANQABCgIIAgAAAA==.Taylea:BAAANQADCgYIBgAAAA==.',
Te='Temperånce:BAABNQAECoEgAAMUAAgKyg5RMQBcAQAUAAcKcAtRMQBcAQACAAcK4gUoYQAgAQAAAA==.',
Th='Thekingelvis:BAAANQABCgYICAABNQABCgYICgAEAAAAAA==.',
Ti='Tiled:BAAANQABCggJCgAAAA==.',
To='Toosalty:BAAANQADCgQIBAAAAA==.Toothgrinder:BAAANQAECgUIDQAAAA==.',
Ug='Uglycow:BAAANQADCgcICAAAAA==.',
Ur='Urbanfries:BAAANQADCgQIBAABNQAFFAYIEQAJAK0WAA==.',
Va='Varr:BAAANQADCgcIDAAAAA==.Vayeda:BAAANQAECgYICwAAAA==.',
Ve='Velini:BAAANQADCggICAAAAA==.Venderic:BAAANQADCgYIBgAAAA==.',
Vi='Vixia:BAAANQAECgEIAQAAAA==.Viz:BAAANQAECgQICwAAAA==.',
Vo='Voidpetal:BAAANQADCgIIAgAAAA==.Vozzert:BAAANQAECgIIAgAAAA==.',
Wh='Whítemane:BAAANQADCgYIBgAAAA==.',
Xa='Xantara:BAAANQABCgYIBgAAAA==.',
Yo='Yoursalad:BAAANQAECgYIDwAAAA==.',
Yu='Yuuka:BAAANQAFFAIIAgAAAA==.',
Ze='Zerin:BAAANQAECgUICwABNQAECggIDwAEAAAAAA==.Zeroh:BAAANQADCgUIDQAAAA==.',
Zi='Zithia:BAAANQADCgUIEQAAAA==.',
Zn='Zna:BAAANQABCggIDgAAAA==.',
Zu='Zuezes:BAAANQADCgUIDAAAAA==.',
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
