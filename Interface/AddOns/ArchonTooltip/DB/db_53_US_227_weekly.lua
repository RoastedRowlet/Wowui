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

local lookup = {'DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Warrior-Protection','Unknown-Unknown','Hunter-BeastMastery','Shaman-Restoration','Shaman-Enhancement','Paladin-Holy','Warrior-Arms','Warrior-Fury','Shaman-Elemental','Priest-Shadow','DeathKnight-Unholy','DemonHunter-Havoc','DemonHunter-Devourer','Monk-Brewmaster','DemonHunter-Vengeance','Priest-Holy','Paladin-Retribution','Evoker-Devastation','Evoker-Preservation','Mage-Arcane','Mage-Frost','Priest-Discipline','Evoker-Augmentation','Druid-Guardian','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Absu:BAAANQADCgMIAwAAAA==.',
Ag='Agoneer:BAAANQAECgMIAwAAAA==.',
Am='Amairah:BAAANQAECgUIDAAAAA==.Amarantha:BAAANQAECgcIDwAAAA==.',
An='Angelinalizy:BAAANQADCgMJAwAAAA==.Animagon:BAAANQADCgYIBgAAAA==.Animaker:BAABNQAECoEcAAIBAAgK2BdWIAA6AgABAAgK2BdWIAA6AgAAAA==.Anngus:BAAANQADCgYICAAAAA==.',
As='Astreos:BAACNQAFFIEdAAQCAAcK6R3QAAAyAQADAAQKThaQCgBcAQACAAMKcCPQAAAyAQAEAAEKNiZiAwByAAA1AAQKgSMABAIACQrMJOoBAEADAAIACQppIuoBAEADAAMABQprHgVzAK0BAAQAAwprJdgNACsBAAAA.Astryd:BAAANQADCgIIAgAAAA==.',
Az='Azorahaidh:BAAANQAECgcIBwABNQAFFAUIBgADAKUXAQ==.',
Ba='Bagawgwah:BAAANQADCgQIBAAAAA==.Balzinya:BAAANQADCgQIBAAAAA==.Bandurie:BAAANQADCgYJCQAAAA==.Baultier:BAAANQADCggIDwAAAA==.',
Be='Beraxes:BAABNQAECoEaAAIFAAgKDh2VBwCWAgAFAAgKDh2VBwCWAgAAAA==.Bethäny:BAAANQADCgcICQAAAA==.',
Bl='Blasser:BAAANQADCgYIBgAAAA==.Bloodhøøfkâi:BAAANQADCgcIHwABNQAECgMIAwAGAAAAAA==.',
Bn='Bnoi:BAAANQAECgIIAgAAAA==.',
Bo='Bose:BAAANQADCgYICgAAAA==.',
Br='Breadpitt:BAAANQADCgMIBAAAAA==.Bronnd:BAAANQAECgQIBwAAAA==.',
Bu='Bullbeer:BAAANQADCgMIAwAAAA==.Bulsy:BAABNQAECoEgAAIHAAgKqiTTCwBdAwAHAAgKqiTTCwBdAwAAAA==.',
Ca='Calamidade:BAABNQAECoEcAAMIAAgKjw3cWgCrAQAIAAgKjw3cWgCrAQAJAAIK5gDwKQBAAAAAAA==.Capwnd:BAAANQADCggICgAAAA==.',
Ce='Celebrimbor:BAABNQAECoEtAAIKAAkKQhlqIQC4AgAKAAkKQhlqIQC4AgAAAA==.Cerryan:BAAANQAECgEIAwAAAA==.Cexar:BAAANQAECgQIBAAAAA==.',
Ch='Churo:BAAANQADCgUIBQAAAA==.',
Cl='Clother:BAACNQAFFIEQAAILAAcKtxnmAgBzAgALAAcKtxnmAgBzAgA1AAQKgTIAAwsACQrHJYEHAKgDAAsACQrHJYEHAKgDAAwAAQqNJTYfAGwAAAAA.Cloud:BAABNQAECoE0AAILAAkK3iJlCgCQAwALAAkK3iJlCgCQAwAAAA==.',
Co='Coltist:BAAANQAECgQIBAAAAA==.Cormbread:BAAANQADCggICAAAAA==.',
Cr='Cravenfrost:BAAANQADCgYIBgAAAA==.',
Cu='Curses:BAAANQAECgQIDQAAAA==.',
Da='Dantheman:BAAANQADCgcIDwAAAA==.Darkwand:BAAANQADCgUIBQAAAA==.David:BAAANQADCgYIBgABNQAECggIBwAGAAAAAA==.',
De='Deathkanight:BAAANQADCgYIBgAAAA==.Desubea:BAAANQADCgYIDAAAAA==.',
Dj='Djaztech:BAACNQAFFIEIAAMLAAQK6BbaDQBoAQALAAQKxhbaDQBoAQAMAAEKWiZiAgBxAAA1AAQKgSIAAwsACQoIJCANAH0DAAsACQoGJCANAH0DAAwABQrEI8IJAOgBAAAA.',
Do='Doc:BAAANQAECgQIBAAAAA==.',
Dr='Draha:BAAANQAECgQIBgAAAA==.Drshockêr:BAABNQAECoEpAAQIAAkK2iABCwBHAwAIAAkK2iABCwBHAwANAAIKYwdK4QBeAAAJAAEKZQaoKwA2AAAAAA==.Drugdhealer:BAAANQADCggIEAAAAA==.Druidbull:BAAANQADCggICgAAAA==.',
Du='Dumbledore:BAAANQAECggIBwAAAA==.Dunthat:BAAANQAECgQIBAAAAA==.Duthir:BAAANQADCgIIAgABNQAECgkJJgAOAI0gAA==.',
Ea='Earthgrinder:BAAANQADCgUIBQABNQAECgcIDwAGAAAAAA==.',
Eg='Egrok:BAAANQAECgUICQAAAA==.',
Em='Emaeel:BAAANQADCggICAAAAA==.Emporia:BAAANQAECgUICAAAAA==.',
En='Enhangi:BAAANQADCgIIAgAAAA==.',
Er='Erissel:BAAANQAECgUICQAAAA==.Erowyn:BAAANQADCgUIBgAAAA==.',
Es='Esso:BAABNQAECoEkAAMPAAkKFR7FHgCLAgAPAAgKSR/FHgCLAgABAAQKyxfzSQAQAQAAAA==.Estupink:BAAANQAECgcICwAAAA==.',
Fa='Faelure:BAAANQAECgIIBQAAAA==.',
Fi='Fiending:BAAANQADCggIDwAAAA==.Finnarius:BAAANQADCgYIBgAAAA==.',
Fo='Foros:BAAANQAECgYICwAAAA==.',
Fr='Fryiertuck:BAAANQAECgQIBAAAAA==.',
Ga='Gabil:BAAANQAECgQICwAAAA==.',
Ge='Gendorosan:BAAANQAECgQICwAAAA==.',
Gn='Gnork:BAAANQAECgEIAQAAAA==.',
Go='Goldwolf:BAAANQADCgcIBwAAAA==.',
Gr='Grayfoxx:BAAANQAECgQIDAAAAA==.Grìmmgor:BAACNQAFFIELAAIPAAQKZiKKBACBAQAPAAQKZiKKBACBAQA1AAQKgSwAAg8ACQq1JWQDAKoDAA8ACQq1JWQDAKoDAAAA.',
Ha='Halbrand:BAAANQAECgIIAgABNQAECgkJLQAKAEIZAA==.',
He='Hellstomper:BAAANQAECgQICAAAAA==.Heygrlhey:BAABNQAECoEgAAIHAAgKnCEjGAAKAwAHAAgKnCEjGAAKAwAAAA==.',
Hi='Hieronymous:BAAANQAECggICAABNQAECggJCgAGAAAAAA==.Hisokana:BAAANQADCgIIAgAAAA==.',
Hu='Hunna:BAAANQAECgQICQAAAA==.Hurtzdonit:BAAANQAECgYICgAAAA==.',
Il='Illusion:BAABNQAECoEkAAMQAAkKWx0HEADtAgAQAAkKWx0HEADtAgARAAgK4wx9JwDLAQABNQAECgkKJAAQAFsdAA==.Ilmerel:BAAANQAECggICgAAAA==.',
Im='Immatos:BAAANQADCgEIAQAAAA==.',
In='Inebriated:BAAANQAECgUICgAAAA==.',
Is='Iselune:BAAANQADCgYJBwAAAA==.',
Ja='Jambi:BAAANQAECgMIAwAAAA==.Jankash:BAAANQADCgEIAQAAAA==.',
Ju='Jukeboxhero:BAAANQADCgIIAgAAAA==.',
['Jê']='Jêanne:BAAANQAECgUIDQAAAA==.',
Ka='Kael:BAAANQAECgEIAQAAAA==.',
Kh='Khán:BAAANQADCgEIAQAAAA==.',
Ki='Killjaeden:BAAANQABCgIIAgAAAA==.',
Ko='Koralin:BAAANQADCgEIAQAAAA==.',
Kr='Kredrel:BAAANQAECgEIAgABNQAECgkJKQASAAcdAA==.',
Ks='Ksauce:BAAANQAECgQICgAAAA==.',
Ky='Kynan:BAAANQADCggIGwABNQAECggIHgATANEQAA==.Kyran:BAABNQAECoEeAAMTAAgK0RCICwC3AQATAAgK0RCICwC3AQAQAAEKxAkieAArAAAAAA==.',
La='Lahughey:BAAANQADCgYICwAAAA==.Lamurun:BAAANQADCggIBwAAAA==.Lathina:BAABNQAECoEZAAIJAAkKbR8xBAA6AwAJAAkKbR8xBAA6AwAAAA==.Lavendere:BAAANQAECgYICwABNQAECgkJJgAOAI0gAA==.',
Li='Linafox:BAAANQAECgYIDwAAAA==.Linta:BAAANQADCgIIAgABNQADCgcIDAAGAAAAAA==.',
Ll='Lluvia:BAAANQAECgYIEwAAAA==.',
Lo='Lokix:BAAANQAECgEIAwAAAA==.Lothsblood:BAAANQADCgUICAAAAA==.',
Ly='Lysistratta:BAAANQAECgQIDAAAAA==.',
Ma='Magimal:BAAANQAECgQJCAABNQADCggICAAGAAAAAA==.Maldrakesus:BAAANQAECgQIBAABNQADCggICAAGAAAAAA==.Marquista:BAAANQADCggIIwAAAA==.',
Mc='Mcsmitey:BAAANQADCggICAABNQAECgcIDwAGAAAAAA==.',
Me='Meatypoo:BAAANQAECgYICQAAAA==.Meladaris:BAAANQAECgIJAgAAAA==.Mey:BAABNQAECoEZAAIUAAgKExSSRQAJAgAUAAgKExSSRQAJAgAAAA==.',
Mi='Missperfect:BAAANQAECgEIAQAAAA==.Mitenalla:BAABNQAECoEfAAIVAAkKciKuFgBGAwAVAAkKciKuFgBGAwAAAA==.',
Mo='Moosefluid:BAAANQADCggIAQAAAA==.Morrdred:BAAANQAECggJCgAAAA==.Mossberger:BAAANQADCggIEAAAAA==.',
My='Myoue:BAAANQAECgMIBQAAAA==.Mysticraven:BAAANQADCgEIAQAAAA==.',
Na='Nagendra:BAABNQAECoEmAAIWAAkKfhp6CADKAgAWAAkKfhp6CADKAgAAAA==.',
Ne='Neoptolemos:BAAANQAECgEIAgAAAA==.',
Ni='Nicnevin:BAAANQAECgYIDwAAAA==.Nieko:BAAANQAECggIDgAAAA==.Nikolos:BAAANQADCgYIBgAAAA==.Nitrochrist:BAABNQAECoEcAAIDAAgKGA1UZADbAQADAAgKGA1UZADbAQAAAA==.Nixxy:BAAANQADCgQIBAABNQAFFAMIBQAXACkJAA==.',
No='Nokimi:BAAANQABCgIIAgAAAA==.Nordathair:BAAANQADCggIJgAAAA==.Nori:BAACNQAFFIEVAAMYAAYK4CX6AQCGAgAYAAYKnCL6AQCGAgAZAAIKgxNHBACjAAA1AAQKgSQAAxgACQqLJvIEAMcDABgACQqLJvIEAMcDABkAAQpGJXApAGcAAAAA.',
Nu='Nuala:BAAANQADCggIDgAAAA==.',
Ny='Nyxza:BAAANQAECgIJAgAAAA==.',
Or='Originals:BAAANQADCgUIBQAAAA==.',
Pa='Painfulpoo:BAAANQAECgQIBAAAAA==.Parsemae:BAABNQAECoEfAAIYAAkKjhbHbQBvAgAYAAkKjhbHbQBvAgAAAA==.Pastries:BAAANQADCggICQABNQAFFAcIHQACAOkdAA==.',
Pi='Pitlin:BAABNQAECoEZAAQaAAcK6SAhBgD6AQAUAAYKDR/wQQAYAgAaAAYKAB0hBgD6AQAOAAEKMQeMYwAvAAAAAA==.',
Pm='Pmsavenger:BAAANQABCgcICwABNQAECgMIAwAGAAAAAA==.',
Pr='Priestalisha:BAACNQAFFIEKAAIUAAQKaSQGCQCxAQAUAAQKaSQGCQCxAQA1AAQKgTUAAhQACQrZJaoBAMQDABQACQrZJaoBAMQDAAAA.',
Ps='Psiphon:BAAANQADCgQJBAAAAA==.',
Qh='Qhhee:BAAANQADCgQIBAAAAA==.',
Ra='Raelana:BAAANQAECgEIAwAAAA==.Ransome:BAAANQADCgEIAQAAAA==.Rawsteak:BAAANQAECgcICwAAAA==.',
Re='Redcrow:BAAANQAECgMJBQAAAA==.Reshocker:BAAANQADCgUJBQAAAA==.Restosexualz:BAAANQAECgIIAgAAAA==.',
Ri='Rixxy:BAACNQAFFIEFAAIXAAMKKQk+DADiAAAXAAMKKQk+DADiAAA1AAQKgT8ABBcACQqPHCMIAAQDABcACQqPHCMIAAQDABYACAryFBIPADECABsAAgooChsZAFMAAAAA.',
Ro='Roastbeefdr:BAABNQAECoEZAAMPAAgKVR6OMgAFAgAPAAcKhh+OMgAFAgABAAUKOhRwQgBAAQAAAA==.Root:BAAANQADCgQIBAAAAA==.',
Sa='Saisaith:BAABNQAECoEmAAIOAAkKjSARCAA7AwAOAAkKjSARCAA7AwAAAA==.Sand:BAAANQADCgIIAgAAAA==.Savadar:BAAANQAECgEIAwAAAA==.Saymourcox:BAAANQAECgMIAwAAAA==.',
Se='Setareh:BAAANQAECgQIBAAAAA==.',
Sh='Shakira:BAAANQADCgQIBAAAAA==.Shakuru:BAAANQAECgcIEwAAAA==.Shkar:BAABNQAECoEpAAIMAAkKUB0HAwDwAgAMAAkKUB0HAwDwAgAAAA==.Shokan:BAAANQADCgUICQAAAA==.',
Si='Silandrya:BAAANQAECgEIAQAAAA==.',
Sj='Sjaridin:BAEANQADCgcIBwABNQAFFAMIBQAcAHQAAA==.',
Sm='Smawbrawl:BAAANQADCgEIAQAAAA==.',
So='Sock:BAAANQAECgYJEAAAAA==.Soulintosh:BAAANQAECggIDgAAAA==.',
St='Stickylock:BAAANQADCgEIAQAAAA==.',
Su='Sule:BAEANQAECgYJEAAAAA==.',
Sy='Syriais:BAAANQADCgEIAQAAAA==.',
['Sä']='Sämuel:BAAANQADCgMJAwAAAA==.',
Ta='Taurengee:BAAANQADCgUJBQAAAA==.',
Th='Thhee:BAAANQAECgQICwAAAA==.Thromm:BAAANQAECgEIAQAAAA==.',
Tr='Trigger:BAAANQADCgIIAgAAAA==.',
Ts='Tsuro:BAAANQAECgEIAgAAAA==.',
Tw='Twotonsoffun:BAAANQADCgYIBgABNQAECgYIDwAGAAAAAA==.',
Tz='Tzunami:BAAANQAECgMIAwAAAA==.',
Ud='Udernonsense:BAAANQADCgMIAwAAAA==.',
Un='Uncletoucher:BAAANQAECgYIEQAAAA==.Unholylife:BAAANQAECgIIAgAAAA==.',
Ut='Utena:BAABNQAECoEbAAIRAAcK7SA3FQCMAgARAAcK7SA3FQCMAgAAAA==.',
Ve='Velocet:BAABNQAECoEpAAMdAAkK9xULFwB1AgAdAAkKKBULFwB1AgAeAAcKlg8GIACnAQAAAA==.Vetlance:BAAANQADCgMIAwAAAA==.',
Vo='Voidbloom:BAAANQADCgYIBgABNQAECgcIDwAGAAAAAA==.',
Vy='Vynagos:BAAANQADCgQJBwAAAA==.',
Wa='Waghdaddy:BAAANQAECgYJCgAAAA==.Wannatry:BAAANQADCgQIBAAAAA==.',
We='Weeknave:BAAANQADCgUIBQAAAA==.',
Wi='Windripper:BAAANQAECgcIDwAAAA==.',
Wo='Wobiwabi:BAAANQABCgIIAgAAAA==.Wokedeath:BAAANQAECgQIBAAAAA==.',
Wr='Wratheon:BAABNQAECoEpAAISAAkKBx0wBQDZAgASAAkKBx0wBQDZAgAAAA==.',
Wu='Wuji:BAAANQAECgEIAQAAAA==.',
Xa='Xablau:BAAANQADCgYIBgAAAA==.Xanthus:BAAANQADCgIIAgAAAA==.',
Xe='Xebec:BAAANQADCgQIBAAAAA==.',
['Xí']='Xí:BAAANQADCgQJBAAAAA==.',
Za='Zanuker:BAAANQADCgUIBQAAAA==.',
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
