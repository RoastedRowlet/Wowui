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

local lookup = {'Warlock-Destruction','Warlock-Demonology','DeathKnight-Frost','Warlock-Affliction','Warrior-Protection','Unknown-Unknown','Hunter-BeastMastery','Shaman-Restoration','Shaman-Enhancement','Paladin-Holy','Warrior-Arms','Warrior-Fury','Shaman-Elemental','Priest-Shadow','DeathKnight-Unholy','DemonHunter-Havoc','DemonHunter-Devourer','Monk-Brewmaster','DemonHunter-Vengeance','Mage-Arcane','Priest-Holy','Paladin-Retribution','Evoker-Devastation','Evoker-Preservation','Mage-Frost','Priest-Discipline','Evoker-Augmentation','Druid-Guardian','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Absu:BAAANQADCgMIAwAAAA==.',
Ag='Agoneer:BAAANQAECgMIAwAAAA==.',
Am='Amairah:BAAANQAECgYIEQAAAA==.Amarantha:BAABNQAECoEaAAMBAAgKlAbeMgDuAAABAAYKdwfeMgDuAAACAAQK/gOs+wCdAAAAAA==.',
An='Anaesthetize:BAAANQABCgYIDAAAAA==.Angelinalizy:BAAANQADCgMJAwAAAA==.Animagon:BAAANQADCgYIBgAAAA==.Animaker:BAABNQAECoEjAAIDAAgKhBkKIwBKAgADAAgKhBkKIwBKAgAAAA==.Anngus:BAAANQAECgMIAwAAAA==.',
As='Astreos:BAACNQAFFIEeAAQBAAcK6R0pAQAmAQACAAQKThYNEABQAQABAAMKcCMpAQAmAQAEAAEKNibFBABxAAA1AAQKgSUABAEACQrMJFMCADIDAAEACQppIlMCADIDAAQABQpeI20IAOEBAAIABQprHneIAKMBAAAA.Astryd:BAAANQADCgIIAgAAAA==.',
At='Atticus:BAAANQAECgUIBQAAAA==.',
Au='Aurhon:BAAANQADCgQIBAAAAA==.',
Az='Azorahaidh:BAAANQAFFAIIAgAAAQ==.',
Ba='Bagawgwah:BAAANQADCgQIBAAAAA==.Balzinya:BAAANQADCgQIBAAAAA==.Bandurie:BAAANQADCgYICQAAAA==.Baultier:BAAANQADCggIFwAAAA==.',
Be='Beraxes:BAABNQAECoEhAAIFAAgK9R+RBgDaAgAFAAgK9R+RBgDaAgAAAA==.Bethäny:BAAANQADCgcICQAAAA==.',
Bl='Blackshiva:BAAANQADCgUIBQAAAA==.Blasser:BAAANQADCgYIBgAAAA==.Bloodhøøfkâi:BAAANQADCgcIHwABNQAECgYICQAGAAAAAA==.Bluemaple:BAAANQADCgcIBwAAAA==.',
Bn='Bnoi:BAAANQAECgIIAgAAAA==.',
Bo='Bose:BAAANQADCgYICgAAAA==.',
Br='Breadpitt:BAAANQADCgcICAAAAA==.Bronnd:BAAANQAECgQIBwAAAA==.',
Bu='Bullbeer:BAAANQADCgMIAwAAAA==.Bulsy:BAABNQAECoEnAAIHAAgK7CRHDwBVAwAHAAgK7CRHDwBVAwAAAA==.',
Ca='Calamidade:BAABNQAECoEjAAMIAAgKpw3XZwCmAQAIAAgKpw3XZwCmAQAJAAIK5gC1LgA/AAAAAA==.Capwnd:BAAANQADCggICwAAAA==.',
Ce='Celebrimbor:BAABNQAECoExAAIKAAkKZhqqIQDPAgAKAAkKZhqqIQDPAgAAAA==.Cerryan:BAAANQAECgEIBAAAAA==.Cexar:BAAANQAECgQIBAAAAA==.',
Ch='Churo:BAAANQADCgUIBQAAAA==.',
Cl='Clother:BAACNQAFFIERAAILAAcKtxl/BABlAgALAAcKtxl/BABlAgA1AAQKgTQAAwsACQrHJQwMAJEDAAsACQrHJQwMAJEDAAwAAQqNJRkkAGkAAAAA.Cloud:BAABNQAECoE8AAILAAkKPSOMDACOAwALAAkKPSOMDACOAwAAAA==.',
Co='Coltist:BAAANQAECgQIBAAAAA==.Cormbread:BAAANQADCggICAAAAA==.',
Cr='Cravenfrost:BAAANQADCgYICwAAAA==.',
Cu='Curses:BAAANQAECgYIEwAAAA==.',
Da='Dantheman:BAAANQADCgcIDwAAAA==.Darkwand:BAAANQADCgUIBQAAAA==.David:BAAANQADCgYIBgABNQAECggICQAGAAAAAA==.',
De='Deathkanight:BAAANQADCgYIBgAAAA==.Desubea:BAAANQADCgYIDAAAAA==.',
Dj='Djaztech:BAACNQAFFIEMAAMMAAUKmhbbAQDGAAALAAQKaRgYEgBqAQAMAAIKmBrbAQDGAAA1AAQKgSMAAwsACQoIJOESAGgDAAsACQoGJOESAGgDAAwABQrEI+oLAN0BAAAA.',
Do='Doc:BAAANQAECgQIBgAAAA==.',
Dr='Draha:BAAANQAECgQICgABNQAECgUICAAGAAAAAA==.Drshockêr:BAABNQAECoExAAQIAAkKKiE1DgA7AwAIAAkKKiE1DgA7AwANAAIKYwfI/ABZAAAJAAEKZQaCMAA2AAAAAA==.Drugdhealer:BAAANQADCggIEAAAAA==.Druidbull:BAAANQADCggICgAAAA==.',
Du='Dumbledore:BAAANQAECggIBwAAAA==.Dunthat:BAAANQAECgQIBAAAAA==.Duthir:BAAANQADCgIIAgABNQAECgkJKwAOAI0gAA==.',
Ea='Earthgrinder:BAAANQADCgUIBQABNQAECggIGgAJAD0YAA==.',
Eg='Egrok:BAAANQAECgYIDAAAAA==.',
Em='Emaeel:BAAANQADCggICAAAAA==.Emporia:BAAANQAECgUICAAAAA==.',
En='Enhangi:BAAANQADCgIIAgAAAA==.',
Er='Erissel:BAAANQAECgUIDgAAAA==.Erowyn:BAAANQADCgUIBgAAAA==.',
Es='Esso:BAABNQAECoEnAAMPAAkKsR9LGADiAgAPAAkKsR9LGADiAgADAAQKyxf0VQAGAQAAAA==.Estupink:BAAANQAECggIDgAAAA==.',
Fa='Faelure:BAAANQAECgIIBQAAAA==.',
Fi='Fiending:BAAANQADCggIDwAAAA==.Finnarius:BAAANQADCgYIBgAAAA==.',
Fo='Foros:BAAANQAECgcIDAAAAA==.',
Fr='Fryiertuck:BAAANQAECgYICgAAAA==.',
Ga='Gabil:BAAANQAECgYIEQAAAA==.',
Ge='Gendorosan:BAAANQAECgYIEQAAAA==.',
Gn='Gnork:BAAANQAECgEIAQAAAA==.',
Go='Goldwolf:BAAANQADCgcIBwAAAA==.',
Gr='Grayfoxx:BAAANQAECgYIEgAAAA==.Grìmmgor:BAACNQAFFIEQAAIPAAYKOByCAgAEAgAPAAYKOByCAgAEAgA1AAQKgS8AAg8ACQrXJZQFAJEDAA8ACQrXJZQFAJEDAAAA.',
Ha='Halbrand:BAAANQAECgIIAgABNQAECgkJMQAKAGYaAA==.',
He='Hellstomper:BAAANQAECgQIDAAAAA==.Heygrlhey:BAABNQAECoElAAIHAAkKhSA+EQBIAwAHAAkKhSA+EQBIAwAAAA==.',
Hi='Hieronymous:BAAANQAECggIEAAAAA==.Hisokana:BAAANQADCgIIAgAAAA==.',
Hu='Hunna:BAAANQAECgUIDgAAAA==.Hurtzdonit:BAAANQAECgYICwAAAA==.',
Il='Illusion:BAABNQAECoEpAAMQAAkK7h2ZEgDtAgAQAAkK7h2ZEgDtAgARAAgK4wzPKwDCAQABNQAECgkKKQAQAO4dAA==.Ilmerel:BAAANQAECggIDQAAAA==.',
Im='Imawhitedot:BAAANQAECgIIAgAAAA==.Immatos:BAAANQAECgcICwAAAA==.',
In='Inebriated:BAAANQAECgYIEAAAAA==.',
Is='Iselune:BAAANQADCgYJBwAAAA==.',
Ja='Jambi:BAAANQAECgMIAwAAAA==.Jankash:BAAANQADCgEIAQAAAA==.',
Je='Jeremiahjnsn:BAAANQADCgQIBAAAAA==.',
Ju='Jukeboxhero:BAAANQADCgIIAgAAAA==.',
['Jê']='Jêanne:BAAANQAECgYIEAAAAA==.',
Ka='Kael:BAAANQAECgEIAgAAAA==.',
Kh='Khán:BAAANQADCgYIBwAAAA==.',
Ki='Killjaeden:BAAANQABCgIIAgAAAA==.',
Ko='Koralin:BAAANQADCgEIAQAAAA==.',
Kr='Kredrel:BAAANQAECgEIAgABNQAECgkJMAASACUeAA==.',
Ks='Ksauce:BAAANQAECgQIDgAAAA==.',
Ky='Kynan:BAAANQADCggIGwABNQAECggIJQATAP4RAA==.Kyran:BAABNQAECoElAAMTAAgK/hF/DQC2AQATAAgK/hF/DQC2AQAQAAMKwgwZaACkAAAAAA==.',
La='Lahughey:BAAANQADCgYICwAAAA==.Lamurun:BAAANQADCggIBwAAAA==.Lathina:BAABNQAECoEgAAMJAAkKPiCMBQAmAwAJAAkKPiCMBQAmAwANAAEKuhdxBQFIAAAAAA==.Lavendere:BAAANQAECgYIDQABNQAECgkJKwAOAI0gAA==.',
Li='Linafox:BAAANQAECgcIEAAAAA==.Linta:BAAANQADCgIIAgABNQADCgcIDAAGAAAAAA==.',
Ll='Lluvia:BAABNQAECoEXAAIUAAgKxAgK2QCvAQAUAAgKxAgK2QCvAQAAAA==.',
Lo='Lokix:BAAANQAECgEIBAAAAA==.Lothsblood:BAAANQADCgUICAAAAA==.',
Ly='Lysistratta:BAAANQAECgYIEgAAAA==.',
Ma='Magimal:BAAANQAECgQJCAABNQADCggICAAGAAAAAA==.Maldrakesus:BAAANQAECgYICgABNQADCggICAAGAAAAAA==.Mariebenoit:BAAANQADCgQIBAAAAA==.Marquista:BAAANQADCggIKgAAAA==.',
Mc='Mcsmitey:BAAANQADCggICAABNQAECggIGgAJAD0YAA==.',
Me='Meatypoo:BAAANQAECgYIDQAAAA==.Meladaris:BAAANQAECgIIAwAAAA==.Meloncrusher:BAAANQADCgUIBQAAAA==.Mey:BAABNQAECoEeAAIVAAgKlhQgVAD6AQAVAAgKlhQgVAD6AQAAAA==.',
Mi='Missperfect:BAAANQAECgEIAQAAAA==.Mitenalla:BAABNQAECoEiAAIWAAkKeiKzIAApAwAWAAkKeiKzIAApAwAAAA==.',
Mo='Moosefluid:BAAANQAECgIIAgAAAA==.Morrdred:BAAANQAECggICgABNQAECggIEAAGAAAAAA==.Mossberger:BAAANQADCggIEAAAAA==.',
My='Myoue:BAAANQAECgMIBQAAAA==.Mysticraven:BAAANQADCgYIBwAAAA==.',
Na='Nagendra:BAABNQAECoEqAAIXAAkKtRrmCQC5AgAXAAkKtRrmCQC5AgAAAA==.',
Ne='Neoptolemos:BAAANQAECgEIAgAAAA==.',
Ni='Nicnevin:BAAANQAECgcIEAAAAA==.Nieko:BAAANQAECggIDgAAAA==.Nikolos:BAAANQADCgYIBgAAAA==.Nitrochrist:BAABNQAECoEjAAICAAgKiw6ibwDoAQACAAgKiw6ibwDoAQAAAA==.Nixxy:BAAANQADCgQIBAABNQAFFAQICQAYAIILAA==.',
No='Nokimi:BAAANQABCgIIAgAAAA==.Nordathair:BAAANQAECgEIAQAAAA==.Nori:BAACNQAFFIEcAAMUAAcKLSZ9AgCPAgAUAAYK7iJ9AgCPAgAZAAMKOSUFAQBMAQA1AAQKgSYAAxQACQqdJlQHAL0DABQACQqdJlQHAL0DABkAAQpGJYQvAGQAAAAA.',
Nu='Nuala:BAAANQADCggIDgAAAA==.',
Ny='Nyxza:BAAANQAECgUIBwAAAA==.',
Or='Originals:BAAANQADCgUIBQAAAA==.',
Pa='Painfulpoo:BAAANQAECgQIBAAAAA==.Parsemae:BAABNQAECoEfAAIUAAkKjhY/gwBfAgAUAAkKjhY/gwBfAgAAAA==.Pastries:BAAANQADCggICQABNQAFFAcIHgABAOkdAA==.',
Pi='Pitlin:BAABNQAECoEaAAQaAAgK/R4dBwD0AQAVAAcKHh09PQBQAgAaAAYKAB0dBwD0AQAOAAEKMQdBcQAsAAAAAA==.',
Pm='Pmsavenger:BAAANQABCgcICwABNQAECgMIAwAGAAAAAA==.',
Pr='Priestalisha:BAACNQAFFIEOAAIVAAUKZCRaBQAiAgAVAAUKZCRaBQAiAgA1AAQKgT8AAhUACQqgJigAAAgEABUACQqgJigAAAgEAAAA.',
Ps='Psiphon:BAAANQADCgQJBAAAAA==.',
Qh='Qhhee:BAAANQADCgQIBAAAAA==.',
Ra='Raelana:BAAANQAECgEIBAAAAA==.Ransome:BAAANQADCgEIAQAAAA==.Rawsteak:BAAANQAECgcIEAAAAA==.',
Re='Redcrow:BAAANQAECgMJBQAAAA==.Reshocker:BAAANQADCgUIBQAAAA==.Restosexualz:BAAANQAECgIIAwAAAA==.',
Ri='Rixxiee:BAAANQAECgcIBgABNQAFFAQICQAYAIILAA==.Rixxy:BAACNQAFFIEJAAIYAAQKgguSDAAcAQAYAAQKgguSDAAcAQA1AAQKgUgABBgACQqzHUYIABEDABgACQqzHUYIABEDABcACAryFEIRACICABsAAgooCsUcAFIAAAAA.',
Ro='Roastbeefdr:BAABNQAECoEbAAMPAAgKVR7pRgDWAQAPAAcKhh/pRgDWAQADAAUKOhTvTgAtAQAAAA==.Root:BAAANQADCgQIBAAAAA==.',
Sa='Saisaith:BAABNQAECoErAAIOAAkKjSDJCgAiAwAOAAkKjSDJCgAiAwAAAA==.Sand:BAAANQADCgIIAgAAAA==.Sanguinbella:BAAANQAECgEIAQAAAA==.Saturday:BAAANQAECgEIAQAAAA==.Savadar:BAAANQAECgEIBAAAAA==.Saymourcox:BAAANQAECgMIAwAAAA==.',
Se='Setareh:BAAANQAECgQICAAAAA==.',
Sh='Shakira:BAAANQADCgQIBAAAAA==.Shakuru:BAABNQAECoEeAAIZAAgKVhXeCQABAgAZAAgKVhXeCQABAgAAAA==.Shkar:BAABNQAECoEyAAIMAAkKUB0UBADgAgAMAAkKUB0UBADgAgAAAA==.Shokan:BAAANQADCgUICQAAAA==.',
Si='Silandrya:BAAANQAECgEIAQAAAA==.',
Sj='Sjaridin:BAEANQADCgcIBwABNQAFFAQICQAcAAQBAA==.',
Sm='Smawbrawl:BAAANQADCgUIBQAAAA==.',
So='Sock:BAAANQAECgYIEAAAAA==.Soulintosh:BAAANQAECggIEgAAAA==.',
St='Stickylock:BAAANQADCgcICAAAAA==.',
Su='Sule:BAEBNQAECoEVAAIUAAgKKA5yxQDWAQAUAAgKKA5yxQDWAQAAAA==.',
Sy='Syriais:BAAANQADCgEIAQAAAA==.',
['Sä']='Sämuel:BAAANQADCgMJAwAAAA==.',
Ta='Tatyniana:BAAANQADCgUIBQABNQAECggIAQAGAAAAAA==.Taurengee:BAAANQADCgUJBQAAAA==.',
Th='Thhee:BAAANQAECgYIEQAAAA==.Thromm:BAAANQAECgEIAQAAAA==.',
Tr='Trigger:BAAANQADCgIIAgAAAA==.',
Ts='Tsuro:BAAANQAECgEIAwAAAA==.',
Tw='Twotonsoffun:BAAANQADCgYIBgABNQAECgYIDwAGAAAAAA==.',
Tz='Tzunami:BAAANQAECgMIBgAAAA==.',
Ud='Udernonsense:BAAANQADCgMIAwAAAA==.',
Un='Uncletoucher:BAAANQAECgYIEQAAAA==.Unholylife:BAAANQAECgIIAgAAAA==.',
Ut='Utena:BAABNQAECoEjAAIRAAgKzyAZDgD2AgARAAgKzyAZDgD2AgAAAA==.',
Ve='Velocet:BAABNQAECoEsAAMdAAkK9xW7HgBgAgAdAAkKKBW7HgBgAgAeAAcKlg+/IgCfAQAAAA==.Vetlance:BAAANQADCgMIAwAAAA==.',
Vi='Vimpira:BAAANQADCgUIBQAAAA==.',
Vo='Voidbloom:BAAANQADCgYIBgABNQAECggIGgAJAD0YAA==.',
Vy='Vynagos:BAAANQADCgQIBwAAAA==.',
Wa='Waghdaddy:BAAANQAECgYJCgAAAA==.Wannatry:BAAANQADCgQIBAAAAA==.',
We='Weeknave:BAAANQADCgUIBQAAAA==.',
Wi='Windripper:BAABNQAECoEaAAIJAAgKPRjODQB1AgAJAAgKPRjODQB1AgAAAA==.',
Wo='Wobiwabi:BAAANQABCgIIAgAAAA==.Wokedeath:BAAANQAECgQIBAAAAA==.',
Wr='Wratheon:BAABNQAECoEwAAISAAkKJR4pBQD7AgASAAkKJR4pBQD7AgAAAA==.',
Wu='Wuji:BAAANQAECgEIAgAAAA==.',
Xa='Xablau:BAAANQADCgYIBgAAAA==.Xanthus:BAAANQADCgIIAgAAAA==.',
Xe='Xebec:BAAANQADCgQIBAAAAA==.',
['Xí']='Xí:BAAANQADCgQJBAAAAA==.',
Za='Zanuker:BAAANQADCgUIBQAAAA==.',
Zo='Zoie:BAAANQADCgQIBAAAAA==.',
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
