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

local lookup = {'DeathKnight-Frost','Unknown-Unknown','DeathKnight-Blood','Monk-Brewmaster','DeathKnight-Unholy','Warlock-Demonology','Warlock-Destruction','Priest-Holy','Shaman-Elemental','Monk-Windwalker','Mage-Arcane','Mage-Frost','Paladin-Protection','Paladin-Holy','Priest-Shadow','Rogue-Assassination','Paladin-Retribution','DemonHunter-Havoc','DemonHunter-Devourer','Rogue-Subtlety',}
local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abeblinkin:BAAANQAECgQICgAAAA==.Aborlight:BAAANQADCgYIBgAAAA==.',
Ad='Adit:BAAANQADCggICgAAAA==.',
Af='Afrit:BAAANQAECgMJAwAAAA==.',
Ai='Aiwass:BAAANQAECgUICAAAAA==.',
Al='Alpharius:BAAANQAECgQJBAAAAA==.',
Am='Amacoozy:BAAANQAECgcIDgAAAA==.Amathricus:BAAANQAECgUJCwAAAA==.',
Ar='Arms:BAABNQAECoEWAAIBAAkKdSA5DgDIAgABAAkKdSA5DgDIAgAAAA==.Artima:BAAANQADCgMIAwAAAA==.',
As='Ashh:BAAANQADCgcIDQAAAA==.Ashuk:BAAANQADCgEIAQAAAA==.',
At='Athena:BAAANQAECgUIBgAAAA==.',
Au='Auralei:BAAANQADCgUIBQABNQAECgQJBAACAAAAAA==.',
Az='Azelia:BAAANQAECgIJAgABNQAECgcICAACAAAAAA==.Azzy:BAAANQAECgcICAAAAA==.',
Be='Bellestri:BAAANQAECgEJAQAAAA==.',
Bi='Bigb:BAAANQAECgUIDwAAAA==.Bigface:BAAANQADCgQIBAAAAA==.Bigrod:BAAANQAECgcIEgAAAA==.Binks:BAAANQADCggJFAAAAA==.',
Bl='Black:BAAANQAECgUIBQAAAA==.Blasfoomous:BAABNQAECoEiAAIDAAkK9xwVEQDfAgADAAkK9xwVEQDfAgAAAA==.Blu:BAAANQAFFAIJBAAAAA==.',
Bu='Bubblewrap:BAAANQADCggICAABNQAECgkJIgAEAFcbAA==.',
Ca='Cappen:BAAANQADCgIIAgAAAA==.',
Ce='Cedrik:BAAANQAECgMIAwAAAA==.Ceres:BAAANQADCgMIAwAAAA==.',
Cl='Classcarry:BAAANQAECgQIBgABNQAECggIGgAFAPUeAA==.Claybigsby:BAABNQAECoEdAAMGAAkKXRtkOAA8AgAGAAcKIhpkOAA8AgAHAAQKFxVjJwAWAQAAAA==.Clif:BAAANQAECgEIAQAAAA==.',
Co='Constantina:BAABNQAECoEaAAIIAAkK5Q0kOwD/AQAIAAkK5Q0kOwD/AQAAAA==.Corven:BAAANQAECgQIBAAAAA==.',
Cr='Crunchycars:BAAANQADCgcIBwAAAA==.',
Cy='Cyleste:BAAANQAECgYIDAAAAA==.',
De='Derpy:BAAANQADCgcIIAAAAA==.',
Di='Divinelady:BAAANQADCggICAAAAA==.',
Dj='Djthrasher:BAAANQAECgIIAgAAAA==.',
Dr='Drachese:BAAANQAECgUIBwABNQAECgcIDwACAAAAAA==.Druchese:BAAANQAECgQJBQABNQAECgcIDwACAAAAAA==.',
Ea='Eagleeye:BAAANQAECgUIBQAAAA==.',
Em='Emsley:BAABNQAECoElAAIJAAgKVA1SQgDsAQAJAAgKVA1SQgDsAQAAAA==.',
Er='Eralina:BAAANQADCgUIBQAAAA==.Erebos:BAAANQADCgEIAQAAAA==.Erised:BAAANQADCgYJCgAAAA==.',
Ev='Ev:BAABNQAECoEWAAMEAAgK4xy2CAAyAgAEAAUKYSa2CAAyAgAKAAcKqg7jIQB7AQAAAA==.',
Ex='Exo:BAABNQAECoEYAAMLAAgK3x3UZwBZAgALAAgKyRvUZwBZAgAMAAIK0CHbHACXAAAAAA==.',
Fa='Falorin:BAAANQADCgYICQAAAA==.',
Fl='Floudwing:BAAANQABCgYIDAAAAA==.',
Fo='Foobear:BAAANQADCggIFgABNQAECgkJIgADAPccAA==.',
Fr='Franchescold:BAAANQAECgUICQAAAA==.',
Fu='Furlock:BAAANQAECgUIBQAAAA==.',
Ga='Gabriel:BAABNQAECoE0AAINAAkKQgzkFgCzAQANAAkKQgzkFgCzAQAAAA==.Gantaris:BAAANQADCggJIAAAAA==.',
Gi='Gir:BAAANQAECgQJBgAAAA==.',
Go='Gochese:BAAANQAECgcIDwAAAA==.Gothel:BAAANQADCgcIDgAAAA==.',
Gr='Grace:BAAANQAECgYIBwAAAA==.Greenseer:BAAANQAECgUIBQAAAA==.',
Gt='Gtoffmydruid:BAAANQADCgEIAQABNQADCgUIBQACAAAAAA==.Gtoffmyface:BAAANQADCgUIBQAAAA==.',
Gw='Gwaralmighty:BAAANQAECgYIEgAAAA==.',
Gy='Gypo:BAAANQADCgUICgAAAA==.',
Ha='Haagen:BAAANQAECgUJCwAAAA==.Hamsup:BAAANQAECgYIEgAAAA==.Hatch:BAAANQADCgcICAABNQAECggIFgAEAOMcAA==.',
['Hô']='Hôldem:BAEANQAECgUJCQAAAA==.',
Ic='Icylady:BAAANQADCgYIDAAAAA==.',
If='Ifrita:BAAANQAECgUJDAAAAA==.Ifrite:BAAANQADCgQJBAAAAA==.',
Ik='Ikur:BAAANQAECgUIBQABNQAECggIGQAOAPsbAA==.',
Im='Imbasoul:BAAANQADCgMIAwAAAA==.Imyerchese:BAAANQADCgYIBgABNQAECgcIDwACAAAAAA==.',
Jo='Jontalo:BAAANQADCgQIBgAAAA==.Jormi:BAAANQAECgUJCwAAAA==.',
Ju='Justthetipp:BAAANQABCgQIBgABNQAECgEIAgACAAAAAA==.',
Ka='Kalthael:BAAANQABCgYICQAAAA==.Karthus:BAAANQADCgEIAQAAAA==.Kasaurus:BAAANQADCgMIAQAAAA==.Kasura:BAAANQAECgYIEgAAAA==.',
Kh='Kharahealer:BAAANQAECgMIAwAAAA==.',
Ki='Kindred:BAAANQADCgYICQAAAA==.Kirihax:BAABNQAECoEYAAIPAAgKDB5TDwCqAgAPAAgKDB5TDwCqAgAAAA==.',
Ko='Kochese:BAAANQADCgUIBQABNQAECgcIDwACAAAAAA==.',
Ku='Kutar:BAAANQADCgYJCgAAAA==.',
Li='Limedro:BAAANQADCgcIFAAAAA==.Limpdaddy:BAAANQAECgIJAgAAAA==.',
Lo='Lockme:BAAANQAECgUIBQABNQAFFAUICgALACgYAA==.Lotei:BAAANQADCgMIAwAAAA==.',
Ma='Magorrak:BAAANQADCggJDAAAAA==.Mal:BAAANQAFFAIIAgABNQAFFAUICQAQACsXAA==.Mary:BAACNQAFFIEGAAIQAAQKBBtjAgCFAQAQAAQKBBtjAgCFAQA1AAQKgRsAAhAACQqAIn4EAFEDABAACQqAIn4EAFEDAAAA.',
Mc='Mcshammer:BAAANQAECgQJBAAAAA==.',
Me='Mero:BAAANQAECgQIBAAAAA==.Metal:BAAANQAECgQICgAAAA==.',
Mi='Miorine:BAABNQAECoEbAAILAAkKCSCXHwA5AwALAAkKCSCXHwA5AwAAAA==.Mistbehavin:BAABNQAECoEiAAIEAAkKVxs1BQCyAgAEAAkKVxs1BQCyAgAAAA==.',
Mo='Moginndar:BAABNQAECoEcAAMNAAcK8g+hHgBgAQANAAcK8g+hHgBgAQARAAQKCAv30ADAAAAAAA==.Moochese:BAAANQAECgQIBQABNQAECgcIDwACAAAAAA==.',
Mu='Muggsy:BAAANQAECgEJAQAAAA==.Munidar:BAAANQAECgUIBQAAAA==.',
My='Mytz:BAAANQADCgQJBQAAAA==.',
['Mï']='Mïnna:BAAANQAECggICgAAAA==.',
Ne='Nemisai:BAAANQADCgQJCwAAAA==.',
On='Onebuttonwin:BAAANQADCgMIAwAAAA==.',
Op='Optimizer:BAAANQAECgEIAQAAAA==.',
Or='Orionbtch:BAAANQADCgYIDQAAAA==.',
Ov='Overheat:BAAANQAECgYJCwAAAA==.',
Po='Poppy:BAAANQAECgIIBgAAAA==.',
Pr='Problem:BAAANQADCgIIAgAAAA==.',
Pu='Pugne:BAAANQAECgcJCAAAAA==.',
Ra='Ratidari:BAAANQAECgUJCwAAAA==.Ravenstorm:BAAANQADCgEIAQAAAA==.',
Re='Remmîngton:BAAANQAECgUJCwAAAA==.Retbulls:BAAANQAECgYJDQAAAA==.',
Rh='Rhynehardt:BAAANQADCgYIBgAAAA==.',
Ri='Riptidedro:BAAANQAECgUJCAAAAA==.',
Ru='Runslikedeer:BAAANQAECgEIAQAAAA==.Runé:BAAANQAECgEIAQAAAA==.',
Sa='Satorugojo:BAAANQABCgIIAgAAAA==.',
Se='Sean:BAABNQAECoEiAAMLAAkKCRxpSACyAgALAAkKCRxpSACyAgAMAAEKyRYdLQA+AAAAAA==.Serah:BAABNQAECoEdAAMSAAkK3g4YIwD9AQASAAgKGxAYIwD9AQATAAgKgQfvJwCrAQAAAA==.Sevia:BAAANQADCgUJCQAAAA==.',
Sh='Shimakaze:BAAANQAECgQIBAABNQAECgkJGwALAAkgAA==.Shizaam:BAABNQAECoEdAAIJAAkK1yCpDgBAAwAJAAkK1yCpDgBAAwAAAA==.Shlommy:BAAANQAECgQJCgAAAA==.',
Si='Silvermage:BAACNQAFFIEKAAILAAUKKBiDCQDCAQALAAUKKBiDCQDCAQA1AAQKgR4AAgsACQoMJfUQAHgDAAsACQoMJfUQAHgDAAAA.Sinfxl:BAAANQAECgEJAQABNQAECgEIAQACAAAAAA==.Sinheph:BAAANQADCgcIBwAAAA==.Sippinsizurp:BAABNQAECoEgAAILAAkKWR9jHQBBAwALAAkKWR9jHQBBAwAAAA==.',
Sk='Skullmages:BAAANQAECgUIBQAAAA==.',
Sl='Slayur:BAAANQAECgYIBwAAAA==.Slinkeril:BAAANQADCgcJFwAAAA==.Sloppydro:BAABNQAECoEcAAMOAAgKUhHuPAADAgAOAAgKUhHuPAADAgARAAIKdwVCAAFaAAAAAA==.',
Sm='Smuckerz:BAAANQAECgEIAgAAAA==.',
So='Socksimus:BAAANQADCgcICwAAAA==.Sockssham:BAAANQADCggICAAAAA==.',
St='Stabberz:BAABNQAECoElAAIQAAgK/RiwEwBgAgAQAAgK/RiwEwBgAgAAAA==.Stannane:BAAANQADCgUJBQABNQADCgcJFwACAAAAAA==.Stellaloona:BAAANQADCgYIDwAAAA==.Sticks:BAAANQADCgYJBgAAAA==.Stinkyhooves:BAEANQADCgQIBgAAAA==.Stromboli:BAAANQADCgUJBQAAAA==.',
Su='Sushiroll:BAAANQAECgQJBgABNQAECggIGgAFAPUeAA==.',
Sw='Sweetsourrex:BAAANQADCgYIBgABNQAECgkJIgAUACcaAA==.',
Ta='Tamaqua:BAAANQAECgIJBAAAAA==.',
Te='Telissa:BAAANQADCgcIBwAAAA==.',
Th='Thalor:BAAANQADCggICAAAAA==.Thrass:BAAANQAECgUICQAAAA==.',
To='Toobrunner:BAAANQADCgMIAwAAAA==.',
Tr='Trueknight:BAAANQADCgEIAQAAAA==.',
Un='Unholeytoast:BAAANQAECgUIBQABNQAECgkJHQAJANcgAA==.',
Va='Vampress:BAAANQAECgMJAwAAAA==.Variam:BAAANQAECgQJBAAAAA==.',
Ve='Velannis:BAAANQAECgcJEgAAAA==.',
Vo='Voidangel:BAAANQADCgYIBgAAAA==.Voodooki:BAAANQADCgcIHAAAAA==.',
Vu='Vuo:BAAANQAECgEJAQAAAA==.',
Wi='Winze:BAAANQADCggICQAAAA==.Withdraw:BAAANQADCgUIBQAAAA==.',
Wo='Wochese:BAAANQADCgYIBgABNQAECgcIDwACAAAAAA==.',
Wr='Wrath:BAAANQADCggIDAABNQAECgUIBgACAAAAAA==.',
Wu='Wuchese:BAAANQABCgMIAwABNQAECgcIDwACAAAAAA==.',
Xf='Xfreshh:BAAANQAECgMIAwAAAA==.',
Ya='Yamaa:BAAANQAECgUIBgABNQAECggIGwALAOwgAA==.Yamadono:BAAANQAECgQIBAABNQAECggIGwALAOwgAA==.Yamá:BAAANQADCgcIBwABNQAECggIGwALAOwgAA==.Yamå:BAABNQAECoEbAAILAAgK7CDgOwDYAgALAAgK7CDgOwDYAgAAAA==.',
Yi='Yingzhi:BAAANQADCgIIAgAAAA==.',
Za='Zapchese:BAAANQAECgUIBQABNQAECgcIDwACAAAAAA==.',
Zo='Zortok:BAAANQAECgUICQAAAA==.',
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
