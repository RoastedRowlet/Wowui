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

local lookup = {'Warrior-Arms','DeathKnight-Frost','Unknown-Unknown','DeathKnight-Blood','Shaman-Restoration','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Priest-Holy','Paladin-Holy','Shaman-Elemental','Monk-Windwalker','Mage-Arcane','Mage-Frost','Paladin-Protection','Paladin-Retribution','Warrior-Fury','Druid-Feral','Druid-Restoration','Priest-Shadow','Rogue-Assassination','DemonHunter-Havoc','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abeblinkin:BAAANQAECgYIEAAAAA==.Aborlight:BAAANQAECgMIAwAAAA==.',
Ad='Adit:BAAANQADCggIDAAAAA==.',
Af='Afrit:BAAANQAECgMIBQAAAA==.',
Ai='Aiwass:BAAANQAECgYIDgAAAA==.',
Al='Alpharius:BAAANQAECgQICQAAAA==.',
Am='Amacoozy:BAABNQAECoEaAAIBAAkKPxMGUwBPAgABAAkKPxMGUwBPAgAAAA==.Amathricus:BAAANQAECgUIEAAAAA==.',
Ar='Arms:BAACNQAFFIEJAAICAAUKAAxWBABoAQACAAUKAAxWBABoAQA1AAQKgRcAAgIACQp1IH8WAJECAAIACQp1IH8WAJECAAAA.Artima:BAAANQADCgMIAwAAAA==.',
As='Ashh:BAAANQADCgcIDQAAAA==.Ashuk:BAAANQADCgEIAQAAAA==.',
At='Athena:BAAANQAECgUICwAAAA==.',
Au='Augtism:BAEANQADCgIIAgABNQAECgQIBQADAAAAAA==.Auralei:BAAANQADCgUIBQAAAA==.',
Az='Azelia:BAAANQAECgIJAgABNQAECgcICAADAAAAAA==.Azzy:BAAANQAECgcICAAAAA==.',
Be='Bellestri:BAAANQAECgEIAQAAAA==.',
Bi='Bigb:BAAANQAECgUIDwAAAA==.Bigface:BAAANQAECgYIBgAAAA==.Bigrod:BAABNQAECoEXAAIEAAkKPQ+COgDaAQAEAAkKPQ+COgDaAQAAAA==.Binks:BAAANQADCggIFAAAAA==.',
Bl='Black:BAAANQAECgYICwAAAA==.Blasfoomous:BAABNQAECoElAAIEAAkK9xzKFgDHAgAEAAkK9xzKFgDHAgAAAA==.Blu:BAACNQAFFIEHAAIFAAMK6BvpDQD+AAAFAAMK6BvpDQD+AAA1AAQKgRgAAgUACQroH3cWAO0CAAUACQroH3cWAO0CAAAA.',
Bu='Bubblewrap:BAAANQADCggICAABNQAECgkJKwAGAK4bAA==.',
['Bá']='Básicc:BAAANQADCgUIBQAAAA==.',
Ca='Canadianguy:BAAANQADCgYIBgABNQAECgYIEAADAAAAAA==.Cappen:BAAANQADCgIIAgAAAA==.',
Ce='Cedrik:BAAANQAECgMIAwAAAA==.Ceres:BAAANQADCgMIAwAAAA==.',
Cl='Classcarry:BAAANQAECgUICwABNQAECgkJIAACAJofAA==.Claybigsby:BAABNQAECoEjAAMHAAkKXRurSQAyAgAHAAcKIhqrSQAyAgAIAAQKFxUTKgAVAQAAAA==.Clif:BAAANQAECgEIAQAAAA==.',
Co='Constantina:BAABNQAECoEjAAIJAAkKiRGASQD4AQAJAAkKiRGASQD4AQAAAA==.Corven:BAAANQAECgQIBAAAAA==.',
Cr='Crunchycars:BAAANQADCggICgAAAA==.',
Cy='Cyleste:BAAANQAECgYIDwAAAA==.',
De='Derpy:BAAANQAECgUIBQAAAA==.',
Di='Divinelady:BAAANQADCggICAAAAA==.',
Dj='Djheals:BAAANQADCgEIAQABNQAECgQIBgADAAAAAA==.Djmuphasa:BAAANQADCgQIBwABNQAECgQIBgADAAAAAA==.Djthrasher:BAAANQAECgQIBgAAAA==.',
Dr='Drachese:BAAANQAECgUIBwABNQAECggIFgAKAHgWAA==.Druchese:BAAANQAECgYICwABNQAECggIFgAKAHgWAA==.',
Ea='Eagleeye:BAAANQAECgYICwAAAA==.',
Em='Emsley:BAABNQAECoExAAILAAkK2g0sQwAcAgALAAkK2g0sQwAcAgAAAA==.',
Er='Eralina:BAAANQADCgUIBQAAAA==.Erebos:BAAANQADCgEIAQAAAA==.Erised:BAAANQADCgYJCgAAAA==.',
Ev='Ev:BAABNQAECoEWAAMGAAgK4xyeCgAqAgAGAAUKYSaeCgAqAgAMAAcKqg4lKgBjAQAAAA==.',
Ex='Exo:BAABNQAECoEbAAMNAAkKvRwqXQCYAgANAAkK4xoqXQCYAgAOAAIK0CEjIwCSAAAAAA==.',
Fa='Falorin:BAAANQADCgYIDAAAAA==.',
Fl='Floudwing:BAAANQABCgYIDAAAAA==.',
Fn='Fnwarriors:BAAANQADCgEIAQAAAA==.',
Fo='Focalors:BAAANQAECgQIBAABNQAECgkJIAANAH8hAA==.Foobear:BAAANQAECgYIBgABNQAECgkJJQAEAPccAA==.',
Fr='Franchescold:BAAANQAECgYICgAAAA==.',
Fu='Furlock:BAAANQAECgYICwAAAA==.',
Ga='Gabriel:BAABNQAECoE9AAIPAAkKgxPBFAALAgAPAAkKgxPBFAALAgAAAA==.Gantaris:BAAANQAECgIIAgAAAA==.Gaymer:BAAANQAECgQIBQABNQAECgUICwADAAAAAA==.',
Gi='Gir:BAAANQAECgQJBgAAAA==.',
Go='Gochese:BAABNQAECoEWAAMKAAgKeBY6NwBLAgAKAAgKeBY6NwBLAgAQAAEK8wSsZAEmAAAAAA==.Gothel:BAAANQADCgcIDgAAAA==.',
Gr='Grace:BAAANQAECgcICwAAAA==.Greenseer:BAAANQAECgYICwAAAA==.',
Gt='Gtoffmydruid:BAAANQADCgEIAQABNQADCgUIBQADAAAAAA==.Gtoffmyface:BAAANQADCgUIBQAAAA==.',
Gw='Gwaralmighty:BAABNQAECoEfAAIRAAgKBxuSBQBzAgARAAgKBxuSBQBzAgAAAA==.',
Gy='Gypo:BAAANQADCggIDwAAAA==.',
Ha='Haagen:BAAANQAECgYIEQAAAA==.Hamsup:BAABNQAECoEdAAIBAAgK3xRHZAAYAgABAAgK3xRHZAAYAgAAAA==.Hatch:BAAANQADCgcICAABNQAECggIFgAGAOMcAA==.',
['Hô']='Hôldem:BAEANQAECgUIDgAAAA==.',
Ic='Icylady:BAAANQADCgYIDAAAAA==.',
If='Ifrita:BAAANQAECgYIEgAAAA==.Ifrite:BAAANQADCgQJBAAAAA==.',
Ik='Ikur:BAAANQAECgUIBQABNQAECggIIAAKAA0dAA==.',
Im='Imbasoul:BAAANQADCgMIAwAAAA==.Imyerchese:BAAANQADCgYIBgABNQAECggIFgAKAHgWAA==.',
Jo='Jontalo:BAAANQADCgcICgAAAA==.Jormi:BAAANQAECgYIEQAAAA==.',
Ju='Justthetipp:BAAANQABCgQIBgABNQAECgMIBgADAAAAAA==.',
Ka='Kalthael:BAAANQABCgYICQAAAA==.Karthus:BAAANQADCgEIAQAAAA==.Kasaurus:BAAANQADCgMIAQAAAA==.Kasura:BAABNQAECoEeAAMSAAgK8xx2BgCrAgASAAgK8xx2BgCrAgATAAMK1BW6PgDFAAAAAA==.',
Kh='Kharahealer:BAAANQAECgMIAwAAAA==.',
Ki='Kindred:BAAANQADCgYICQAAAA==.Kirihax:BAABNQAECoEYAAIUAAgKDB7/FAB4AgAUAAgKDB7/FAB4AgAAAA==.',
Ko='Kochese:BAAANQADCgUIBQABNQAECggIFgAKAHgWAA==.',
Ku='Kutar:BAAANQADCgYIDAAAAA==.',
Li='Limedro:BAAANQADCgcIFAAAAA==.Limpdaddy:BAAANQAECgIIAgAAAA==.',
Lo='Lockme:BAAANQAECgcICAABNQAFFAUIDwANAJkcAA==.Lotei:BAAANQADCgMIAwAAAA==.',
Ma='Magorrak:BAAANQADCggIGAAAAA==.Mal:BAABNQAFFIEHAAIVAAQKWCB9AwChAQAVAAQKWCB9AwChAQABNQAFFAYIDwAVABkZAA==.Mary:BAACNQAFFIEKAAIVAAQKjh0vBAB+AQAVAAQKjh0vBAB+AQA1AAQKgR8AAhUACQqOI3wEAGgDABUACQqOI3wEAGgDAAAA.',
Mc='Mcshammer:BAAANQAECgQICAAAAA==.',
Me='Mero:BAAANQAECgQICAAAAA==.Metal:BAAANQAECgQIDgAAAA==.',
Mi='Miorine:BAABNQAECoEgAAINAAkKfyFGKQAmAwANAAkKfyFGKQAmAwAAAA==.Mistbehavin:BAABNQAECoErAAIGAAkKrhvDBQC/AgAGAAkKrhvDBQC/AgAAAA==.',
Mo='Moginndar:BAABNQAECoEhAAMPAAcKJxF2KABAAQAPAAcK8g92KABAAQAQAAUKSRB43gDqAAAAAA==.Moochese:BAAANQAECgQICQABNQAECggIFgAKAHgWAA==.',
Mu='Muggsy:BAAANQAECgEJAQAAAA==.Munidar:BAAANQAECgYICwAAAA==.',
My='Mytz:BAAANQADCgQIBQAAAA==.',
['Mï']='Mïnna:BAAANQAECggIEQAAAA==.',
Ne='Nemisai:BAAANQADCgQICwAAAA==.',
On='Onebuttonwin:BAAANQADCgMIAwAAAA==.',
Op='Optimizer:BAAANQAECgQIBQAAAA==.',
Or='Orionbtch:BAAANQADCgYIDgAAAA==.',
Ov='Overheat:BAAANQAECgYJCwAAAA==.',
Po='Poppy:BAAANQAECgIIBgAAAA==.',
Pr='Problem:BAAANQADCgIIAgAAAA==.',
Pu='Pugne:BAAANQAECgcIDwAAAA==.',
Ra='Ratidari:BAAANQAECgUIEAAAAA==.Ratshifter:BAAANQAECgEIAQABNQAECgUIEAADAAAAAA==.Ravenstorm:BAAANQADCgEIAQAAAA==.',
Re='Remmîngton:BAAANQAECgUJCwAAAA==.Retbulls:BAABNQAECoEXAAIQAAgKWCCgLgDRAgAQAAgKWCCgLgDRAgAAAA==.',
Rh='Rhynehardt:BAAANQADCgYIBgAAAA==.',
Ri='Riptidedro:BAAANQAFFAEIAQAAAA==.',
Ru='Runslikedeer:BAAANQAECgMIBAAAAA==.Runé:BAAANQAECgEIAQABNQAECgQIBQADAAAAAA==.',
Sa='Satorugojo:BAAANQABCgIIAgAAAA==.',
Se='Sean:BAABNQAECoElAAMNAAkKKxyEWwCcAgANAAkKKxyEWwCcAgAOAAEKyRYeNQA+AAAAAA==.Serah:BAABNQAECoEgAAMWAAkK6g4ILgDaAQAWAAgKKRAILgDaAQAXAAgKgQeRLQCUAQAAAA==.Sevia:BAAANQADCggIEQAAAA==.',
Sh='Shimakaze:BAAANQAECggIBwABNQAECgkJIAANAH8hAA==.Shizaam:BAABNQAECoEgAAILAAkK3CDgEwAvAwALAAkK3CDgEwAvAwAAAA==.Shlommy:BAAANQAECgUIDwAAAA==.',
Si='Silvermage:BAACNQAFFIEPAAINAAUKmRwRDQDEAQANAAUKmRwRDQDEAQA1AAQKgSAAAg0ACQoRJcEYAGADAA0ACQoRJcEYAGADAAAA.Sinfxl:BAAANQAECgQIBQAAAA==.Sinheph:BAAANQADCgcIBwAAAA==.Sippinsizurp:BAABNQAECoEhAAINAAkKWR81KwAgAwANAAkKWR81KwAgAwAAAA==.',
Sk='Skullmages:BAAANQAECgcICgAAAA==.',
Sl='Slayur:BAAANQAECgYIBwAAAA==.Slinkeril:BAAANQADCggIHwAAAA==.Sloppydro:BAABNQAECoEkAAMKAAgKUhFNSgD7AQAKAAgKUhFNSgD7AQAQAAIKdwVELQFXAAAAAA==.',
Sm='Smuckerz:BAAANQAECgEIAgAAAA==.',
So='Socksimus:BAAANQADCgcIEQAAAA==.Sockssham:BAAANQADCggICAAAAA==.',
St='Stabberz:BAABNQAECoExAAIVAAkKlBlGEgClAgAVAAkKlBlGEgClAgAAAA==.Stannane:BAAANQADCgUICQABNQADCggIHwADAAAAAA==.Stellaloona:BAAANQADCgYIEAAAAA==.Sticks:BAAANQADCgYJBgAAAA==.Stinkyhooves:BAEANQADCgQIBgABNQAECgQIBQADAAAAAA==.Stromboli:BAAANQADCgUJBQAAAA==.',
Su='Sushiroll:BAAANQAECgcIDAABNQAECgkJIAACAJofAA==.',
Sw='Sweetsourrex:BAAANQADCgYIBgABNQAECgkJKAAYAPsbAA==.',
Ta='Tamaqua:BAAANQAECgIIBgAAAA==.',
Te='Telissa:BAAANQAECgEIAQAAAA==.Temoin:BAAANQADCgMIAQAAAA==.',
Th='Thalor:BAAANQAECgQIBAAAAA==.Thrass:BAAANQAECgYICgAAAA==.',
To='Toobrunner:BAAANQAECgQIBAAAAA==.',
Tr='Trueknight:BAAANQADCgEIAQAAAA==.',
Un='Unholeytoast:BAAANQAECgYICwABNQAECgkJIAALANwgAA==.',
Va='Vampress:BAAANQAECgMIAwAAAA==.Variam:BAAANQAECgYICgAAAA==.',
Ve='Velannis:BAABNQAECoEbAAQZAAgK5xxvBgA8AgAZAAcKYRxvBgA8AgAVAAUKahZxPABYAQAYAAIK3xToOgCVAAAAAA==.',
Vo='Voidangel:BAAANQADCgYICgAAAA==.Voodooki:BAAANQADCggIIwAAAA==.',
Vu='Vuo:BAAANQAECgQIBQAAAA==.',
Wi='Winze:BAAANQADCggIDgAAAA==.Withdraw:BAAANQADCgUIBQAAAA==.',
Wo='Wochese:BAAANQADCgYICwABNQAECggIFgAKAHgWAA==.',
Wr='Wrath:BAAANQADCggIDAABNQAECgUICwADAAAAAA==.',
Wu='Wuchese:BAAANQABCgMIAwABNQAECggIFgAKAHgWAA==.',
Xf='Xfreshh:BAAANQAECgQIBAAAAA==.',
Ya='Yamaa:BAAANQAECgUIBgABNQAECgkJIwANAPwgAA==.Yamadono:BAAANQAECgQIBAABNQAECgkJIwANAPwgAA==.Yamá:BAAANQADCgcIBwABNQAECgkJIwANAPwgAA==.Yamå:BAABNQAECoEjAAINAAkK/CBMKQAmAwANAAkK/CBMKQAmAwAAAA==.',
Yi='Yingzhi:BAAANQADCgIIAgAAAA==.',
Za='Zapchese:BAAANQAECgUIBQABNQAECggIFgAKAHgWAA==.',
Zo='Zortok:BAAANQAECgYICgAAAA==.',
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
