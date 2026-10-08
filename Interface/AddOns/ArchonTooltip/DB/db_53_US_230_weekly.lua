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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Paladin-Protection','Shaman-Elemental','Paladin-Holy','Druid-Guardian','DemonHunter-Havoc','Druid-Feral','Shaman-Restoration','Unknown-Unknown','Paladin-Retribution','Shaman-Enhancement','Evoker-Preservation','Hunter-BeastMastery','Mage-Frost','Mage-Arcane','DeathKnight-Blood','Hunter-Marksmanship','Druid-Balance','Druid-Restoration','Warrior-Fury','DeathKnight-Frost','Hunter-Survival','DemonHunter-Vengeance','DemonHunter-Devourer','Warlock-Affliction','Warrior-Arms','Warrior-Protection',}
local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abaddon:BAAANQAECgUICQAAAA==.',
Ac='Ackris:BAABNQAECoE0AAMBAAkKKCQLBwCGAwABAAkKKCQLBwCGAwACAAEKmRCFcgA2AAAAAA==.',
Ag='Agolan:BAAANQADCgcIBwAAAA==.',
Al='Aldric:BAEANQAECgcIDAABNQAFFAUIDgADAG0kAA==.Alkaios:BAAANQAECgIIAgABNQAECgcIGAADAJcPAA==.Alucarddalv:BAAANQAECgQICQAAAA==.',
Am='Amaimon:BAAANQAECgUIBQABNQAFFAQICgAEACwSAA==.Amnoon:BAABNQAECoEaAAIFAAcK+xCtbQCnAQAFAAcK+xCtbQCnAQAAAA==.Amri:BAAANQAECgYIEAABNQAECggIIwAGAKocAA==.',
Ap='Apoly:BAAANQADCgUIBQAAAA==.',
Aq='Aquas:BAAANQADCgEIAQAAAA==.',
Ar='Ardrhys:BAAANQAECgIIAgAAAA==.Arknem:BAAANQABCgQIBQAAAA==.Artikin:BAAANQAFFAEIAQABNQAFFAMIBwAHADcHAA==.',
As='Assasinateu:BAAANQADCgIIAgAAAA==.Asûná:BAABNQAECoEZAAIIAAYKkhXOEgCbAQAIAAYKkhXOEgCbAQAAAA==.',
At='Atlas:BAAANQAECgYIEQAAAA==.',
Au='Auroxa:BAAANQAECgYIDwAAAA==.Automagic:BAAANQADCgYICwAAAA==.',
Av='Avondwella:BAAANQAECgYIEQAAAA==.',
Az='Azorah:BAAANQADCggIEQAAAA==.',
Ba='Bacevicius:BAAANQAECggIDAAAAA==.Baldyguy:BAAANQAECgQICgAAAA==.Balm:BAAANQAECgYIDAAAAA==.',
Be='Beastlybull:BAAANQAECgcIDAABNQAFFAcIGQAJAOkeAA==.',
Bi='Biblepimp:BAAANQAECgYIDgAAAA==.Bigfries:BAAANQADCgQIBgAAAA==.Bigsneak:BAAANQAECgIJAwAAAA==.',
Bl='Blackmarker:BAAANQAECgUIDAAAAA==.Blemish:BAAANQADCgEIAQABNQAECgYIDAAKAAAAAA==.Bloodpac:BAAANQADCgIIAQAAAA==.',
Bo='Boadica:BAAANQADCgIIAgAAAA==.Bobsuruncle:BAAANQAECgEIAQAAAA==.Bodyguardwyn:BAAANQAECgIIBQAAAA==.Bolvar:BAABNQAECoEYAAILAAcKTBnZfwD4AQALAAcKTBnZfwD4AQAAAA==.Bonedjovi:BAAANQAECgYIEgAAAA==.Boondiggles:BAAANQAECgQICQAAAA==.',
Br='Brathelore:BAAANQADCggICgAAAA==.Bremitox:BAAANQADCgcIEQABNQAECgcIGAADAJcPAA==.Brimscythe:BAAANQADCgIIAQAAAA==.Brud:BAAANQAECgUIDQAAAA==.',
By='Byakugan:BAACNQAFFIEKAAIEAAQKLBI7DwA8AQAEAAQKLBI7DwA8AQA1AAQKgSIAAwQACQq8G+w0AH4CAAQACAriHew0AH4CAAwAAQqRCgkuAEMAAAAA.',
['Bø']='Bønitalèè:BAAANQAECgUICAAAAA==.',
Ca='Cain:BAAANQADCgQIBAAAAA==.Calvisi:BAAANQAECgMIAwAAAA==.Calvisichaos:BAAANQAECgYIEQAAAA==.Canthen:BAAANQAECggJAgAAAA==.',
Cc='Cc:BAAANQAECgUIDwAAAA==.',
Ch='Chaoticbacon:BAAANQADCgYIBgABNQAECgEIAgAKAAAAAA==.',
Co='Cosmicspark:BAAANQAECgYIEQAAAA==.',
Cr='Cropala:BAAANQAECgUIDAAAAA==.',
Da='Darkwingduck:BAAANQADCgQJBAAAAA==.Darkøne:BAAANQABCgMIAwAAAA==.Davros:BAAANQADCgYIDAABNQAECgEIAQAKAAAAAA==.',
De='Dellandre:BAAANQAECgMIAwABNQAECgYIEwAKAAAAAA==.Delta:BAAANQAECgUICQAAAA==.Delti:BAAANQADCggICAABNQAECgYIEQAKAAAAAA==.Destrõ:BAAANQAECgIIAgAAAA==.',
Di='Diabolist:BAABNQAECoEVAAIBAAcK0ApJlQCBAQABAAcK0ApJlQCBAQAAAA==.Dielma:BAAANQAECgUICQABNQAECgkJGgABACYdAA==.',
Dk='Dkdozer:BAAANQADCgYJDAABNQAECgEIAQAKAAAAAA==.',
Do='Doktaga:BAAANQAECgQICQAAAA==.',
Dr='Drakonna:BAAANQADCgUIBQAAAA==.Drarken:BAABNQAECoEcAAINAAgK+Bp7EgBvAgANAAgK+Bp7EgBvAgAAAA==.Drtapo:BAAANQAECgIIAgAAAA==.',
El='Elderr:BAAANQAECgMIAwABNQAECgcIEQAKAAAAAA==.Eldhe:BAAANQADCgIIAgAAAA==.Elistrae:BAABNQAECoEeAAIOAAgKiyJZHAANAwAOAAgKiyJZHAANAwAAAA==.',
En='Enazen:BAAANQAECgYIDgAAAA==.',
Er='Ereshkigal:BAAANQADCgYJBgAAAA==.Ergo:BAACNQAFFIERAAMPAAUKhA13BgCXAAAQAAQK/wl8IwArAQAPAAIKFA93BgCXAAA1AAQKgSMAAhAACQoFH9VJAN8CABAACQoFH9VJAN8CAAAA.',
Ex='Exon:BAAANQAECgYICwAAAA==.',
Fa='Faded:BAAANQAECgEIAQABNQAECgUIEwAKAAAAAA==.Fadednight:BAAANQAECgUIEwAAAA==.',
Fe='Femcel:BAAANQAECgcIDgAAAA==.Femcelibate:BAAANQAECgIIAgAAAA==.',
Fi='Fivebones:BAAANQAECgMIAwABNQAECgkJMQAOAOsiAA==.',
Fl='Flashlol:BAAANQAECgcIDgAAAA==.',
Fr='Freecookies:BAAANQAECgUIBgAAAA==.Frostytotems:BAAANQADCgQIBwAAAA==.',
Fu='Furryiosa:BAAANQADCgYIBgAAAA==.',
Ga='Gabagool:BAAANQAECgMICgAAAA==.',
Ge='Gerbert:BAAANQABCgIIAgAAAA==.',
Gh='Ghostë:BAAANQAECgcIEgAAAA==.',
Gi='Gishmou:BAAANQAECgYIEQAAAA==.',
Go='Goodlight:BAAANQAECgEIAQAAAA==.',
Gu='Gutted:BAACNQAFFIERAAIRAAUKriXwAwAmAgARAAUKriXwAwAmAgA1AAQKgSUAAhEACQqMJqsBANcDABEACQqMJqsBANcDAAAA.',
Ha='Hanna:BAAANQAECgcICAABNQAFFAUIEQARAK4lAA==.',
He='Hellmaw:BAAANQAECgQIBwAAAA==.',
Ho='Hollowheart:BAAANQAECgUICwAAAA==.Holycourtney:BAAANQADCgQIBAAAAA==.Holyfur:BAAANQAECgUIEgAAAA==.',
Hy='Hylanna:BAAANQAECgEIAQAAAA==.',
Ic='Ici:BAAANQAECgUIDQAAAA==.',
If='Iffybacon:BAAANQAECgEIAQABNQAECgEIAgAKAAAAAA==.',
In='Intensifies:BAAANQAECgYIEQAAAA==.',
Is='Iskothar:BAAANQAECgYIDQAAAA==.',
Iv='Ivarboneless:BAAANQAECgYICgAAAA==.',
Ja='Jace:BAAANQADCgYIBgAAAA==.Jackz:BAAANQADCggIEgAAAA==.Jackzlock:BAAANQAECgUIBQAAAA==.Jak:BAABNQAECoEhAAMOAAkKwRfWSgBmAgAOAAgKYBrWSgBmAgASAAYKywqqPQA1AQAAAA==.Jambii:BAAANQAECgUIDgAAAA==.Jattsz:BAEANQADCggICAAAAA==.Jayreezy:BAAANQAECgYICAAAAA==.',
Je='Jerawokee:BAAANQAECgQIDQAAAA==.',
Ji='Jirachii:BAAANQADCgQIBAABNQAECggIHwATAFoTAA==.',
Jo='Jonah:BAABNQAECoEcAAICAAkKZxo0BADdAgACAAkKZxo0BADdAgAAAA==.Joshcalcjr:BAABNQAECoEZAAQTAAkKnhBlRAC0AQATAAgKag9lRAC0AQAGAAUKqQ0kKwD3AAAUAAIKowUbXwBRAAAAAA==.',
Ka='Kaessatha:BAEANQADCgIIAgABNQADCgYIMQAKAAAAAA==.Kalika:BAAANQADCgIIAgAAAA==.',
Ke='Ketesh:BAABNQAECoEjAAMGAAgKqhypDQBMAgAGAAcKPx2pDQBMAgAIAAEKnRhFMQBIAAAAAA==.',
Ko='Kodeack:BAAANQADCgIJAgAAAA==.Kortona:BAAANQAECgIIAwAAAA==.',
['Kø']='Købioshi:BAAANQADCggICwAAAA==.',
La='Landrey:BAAANQADCgUIDQAAAA==.Laoghaire:BAAANQADCggIGAAAAA==.Laszarei:BAAANQAECgYIDwAAAA==.',
Le='Leonz:BAACNQAFFIESAAIVAAUKdRiJAAC8AQAVAAUKdRiJAAC8AQA1AAQKgTYAAhUACQpjJlMAAOkDABUACQpjJlMAAOkDAAAA.Letharanos:BAEBNQAECoEaAAMWAAYKwBhSOQCuAQAWAAYKwBhSOQCuAQARAAQK/AnFkQCeAAAAAA==.',
Li='Liraffemynn:BAAANQAECgYICgAAAA==.',
Lo='Lohfall:BAAANQADCgUIBgABNQAECgYIEgAKAAAAAA==.Lonranir:BAAANQADCggIEQAAAA==.',
Lu='Luckylucy:BAAANQADCgUIBgAAAA==.Lunoria:BAABNQAECoEbAAIBAAgK/iPBEAA7AwABAAgK/iPBEAA7AwAAAA==.',
Ma='Madarauchiha:BAAANQAECggIEQAAAA==.Madeirà:BAAANQADCgQJBAAAAA==.Magus:BAAANQAECgEIAQAAAA==.Maldran:BAAANQAECgUIDQAAAA==.Manderpants:BAAANQADCgQIBAAAAA==.Marien:BAAANQAECgYIEwAAAA==.Maxus:BAAANQAECgQIBQAAAA==.',
Mb='Mbbin:BAABNQAECoEqAAMQAAkKhCSRCgCoAwAQAAkKhCSRCgCoAwAPAAIKaRRDMABhAAAAAA==.',
Me='Meems:BAAANQABCgQIBAAAAA==.Mehuman:BAAANQAECgYIEQAAAA==.Mehumanhuntr:BAAANQAECgIIAgAAAA==.Mehumanlock:BAABNQAECoEYAAICAAYKZRIlHACEAQACAAYKZRIlHACEAQAAAA==.Melgibson:BAAANQAECgYIEwAAAA==.Meworgendk:BAAANQADCgcJCQAAAA==.',
Mi='Miräj:BAAANQAECgMJBAAAAA==.Mistyblue:BAAANQAECgEIAQAAAA==.Miya:BAAANQADCgUIBQAAAA==.',
Mo='Mojomugambe:BAAANQAECgcIBwAAAA==.Moodacritz:BAAANQADCgYIBgAAAA==.Moonscale:BAAANQAECgEIAQAAAA==.Morel:BAAANQADCgQIBAAAAA==.Mortstan:BAABNQAECoEwAAIRAAkKdiRvBQCTAwARAAkKdiRvBQCTAwAAAA==.',
Mu='Mutegen:BAAANQADCgYIBgAAAA==.',
Na='Nailz:BAAANQAECgYIEQAAAA==.',
Ne='Neloangelo:BAAANQAECgQIBQAAAA==.',
Ni='Nightflame:BAAANQADCgYIBgAAAA==.Nightlion:BAAANQAECgYIEQAAAA==.',
No='Noahpal:BAAANQAECgUIBQABNQAECgUICgAKAAAAAA==.Noahshaman:BAACNQAFFIEQAAIEAAUKfhiMCQCkAQAEAAUKfhiMCQCkAQA1AAQKgTMAAwQACQpFIlILAIEDAAQACQpFIlILAIEDAAkABwoJIOEuAIECAAE1AAQKBQgKAAoAAAAA.Noahwarlock:BAAANQAECgUICgAAAA==.Nonsensical:BAAANQADCgQIBQABNQADCgYIEAAKAAAAAA==.Notbacon:BAAANQAECgEIAQABNQAECgEIAgAKAAAAAA==.Noxander:BAAANQADCgMJAwAAAA==.',
Nu='Nuanakk:BAAANQAECgYIAQAAAA==.',
Oa='Oaths:BAAANQAECgMIBQAAAA==.',
Oh='Ohmylanta:BAAANQAECgEIAQAAAA==.Ohmylänta:BAABNQAECoEkAAMOAAkKpxfrOwCSAgAOAAkKpxfrOwCSAgAXAAEKqQA2EwAUAAAAAA==.',
Or='Orandrok:BAAANQAECgEIAQAAAA==.Ormond:BAAANQAECgEIAQAAAA==.',
['Oâ']='Oâth:BAABNQAECoEZAAMYAAgK+AlsEgBUAQAYAAgK+AlsEgBUAQAZAAEK3QPQZgAlAAAAAA==.',
Pa='Paldozer:BAAANQAECgEIAQAAAA==.Pallyman:BAAANQADCgUIBQAAAA==.Pallywacker:BAAANQAECgUIEAAAAA==.Panzerkìn:BAAANQADCgUIBQAAAA==.',
Pe='Peythilly:BAAANQADCggJDAAAAA==.',
Pi='Pigishdog:BAABNQAECoEkAAIBAAkK7hXeRABnAgABAAkK7hXeRABnAgAAAA==.',
Po='Poob:BAAANQADCgcJEwAAAA==.',
Qu='Quinn:BAAANQAECgUIDAAAAA==.',
Ra='Raedon:BAAANQADCgQIBAAAAA==.Ragerunner:BAAANQADCgQIBAAAAA==.',
Re='Redthing:BAAANQADCgYICwAAAA==.Retributíon:BAAANQAECgEIAQABNQAECgkJMQAHAH4lAA==.',
Ri='Rixas:BAAANQAECgcJCgABNQAECgkJNAABACgkAA==.Rixis:BAAANQADCgQIBAAAAA==.',
Ro='Rockafella:BAAANQADCgYICgAAAA==.Roguehiro:BAAANQAECgMIBgAAAA==.Rooter:BAACNQAFFIESAAINAAYKzR3WAwAgAgANAAYKzR3WAwAgAgA1AAQKgSgAAg0ACQrHJMQCAIsDAA0ACQrHJMQCAIsDAAAA.Rozetta:BAAANQADCgQIBAAAAA==.',
Ru='Ruto:BAAANQADCgIIAgAAAA==.',
Sa='Samshara:BAAANQADCgIIAgABNQAECgUIEAAKAAAAAA==.',
Sc='Scrawni:BAABNQAECoEeAAIGAAgKvB0QCQCxAgAGAAgKvB0QCQCxAgABNQAFFAMIBwAHADcHAA==.',
Se='Selyane:BAAANQABCgYIDgAAAA==.Seongpal:BAECNQAFFIEOAAIDAAUKbSTNAQASAgADAAUKbSTNAQASAgA1AAQKgSQAAgMACQrGJaICAJQDAAMACQrGJaICAJQDAAAA.Seraphinà:BAAANQADCggIDQABNQAECgUICwAKAAAAAA==.Serbingium:BAAANQAECgEIAQABNQAECgkJGgABACYdAA==.',
Sh='Shadowfur:BAAANQADCgIIAgABNQAECgUIEgAKAAAAAA==.Shadowlight:BAAANQAECgIJAgABNQAECgIJAwAKAAAAAA==.Shamygravy:BAAANQAECgIIAgAAAA==.Sharreth:BAAANQAECgEIAQAAAA==.Shimera:BAAANQAECgUIEAAAAA==.Shootrmcgavn:BAABNQAECoEnAAMSAAkKiSVhBgBgAwASAAkKfCJhBgBgAwAOAAgKCyVmFQAvAwAAAA==.',
Si='Sittingmoose:BAAANQAECgYIBgAAAA==.',
Sk='Sklormp:BAABNQAECoEaAAQBAAkKJh08LAC7AgABAAkK9hw8LAC7AgACAAMKXRsmMgDyAAAaAAIKNgnpHgBnAAAAAA==.Skubasteve:BAAANQABCgIIAgAAAA==.',
Sl='Slootar:BAAANQADCggIDwABNQAECgUIDgAKAAAAAA==.Slugs:BAAANQAECgEIAQAAAA==.',
Sm='Smoruk:BAAANQADCgUIBQAAAA==.',
So='Somerled:BAAANQAECgUIEAAAAA==.',
Sq='Squatreign:BAABNQAECoEcAAIFAAcKyAbRjABNAQAFAAcKyAbRjABNAQAAAA==.',
Su='Sulyvahn:BAEANQAECgUICgABNQAFFAUIDgADAG0kAA==.Sunstrike:BAAANQADCgYIBgAAAA==.',
Sy='Sylvara:BAAANQADCgUICgAAAA==.',
Ta='Takka:BAAANQAECgcIDAAAAA==.Talkamar:BAAANQAECgcIDgAAAA==.Tarell:BAAANQABCgMIAwAAAA==.Taylorswift:BAABNQAECoEXAAMPAAgKIRdKDwCIAQAQAAcKQhJ+vQDlAQAPAAUKbR5KDwCIAQAAAA==.',
Te='Tehharlequin:BAAANQAECgEIAQAAAA==.',
Th='Thekourge:BAAANQAECgYIEwAAAA==.Thenard:BAAANQAECgUICgAAAA==.Therealcafna:BAAANQADCgUIBwAAAA==.Thisle:BAAANQADCgcIKAAAAA==.Thukunamage:BAABNQAECoEjAAIQAAkKMSObDwCQAwAQAAkKMSObDwCQAwAAAA==.',
Ti='Tigerlord:BAAANQADCggIFQAAAA==.Tili:BAAANQADCgUIEgAAAA==.',
To='Tomislav:BAAANQAECgUICQAAAA==.Touritos:BAAANQAECgUIDgAAAA==.',
Tr='Trimblestein:BAABNQAECoEeAAIbAAgKuiJFOgDFAgAbAAgKuiJFOgDFAgAAAA==.Trohas:BAAANQADCggICAAAAA==.',
Tu='Tuskerdu:BAABNQAECoEgAAITAAgKPAt6SgCRAQATAAgKPAt6SgCRAQAAAA==.',
Tw='Twohoofy:BAAANQADCgYIDQAAAA==.',
Ud='Uddermilk:BAAANQAECgIIAgAAAA==.',
Va='Valandrian:BAAANQADCgYICQAAAA==.Valeka:BAABNQAECoEZAAIJAAgKjRoqLwCAAgAJAAgKjRoqLwCAAgAAAA==.Valissar:BAAANQABCgcIBwAAAA==.Valr:BAABNQAECoEYAAIDAAcKlw8zKgBfAQADAAcKlw8zKgBfAQAAAA==.Vandreu:BAAANQAECgQIBgAAAA==.',
Vs='Vse:BAACNQAFFIEIAAIPAAMKbBY9BgCaAAAPAAMKbBY9BgCaAAA1AAQKgSUAAg8ACAq6IZUDAOYCAA8ACAq6IZUDAOYCAAAA.Vsesosorry:BAAANQAECgQIBAABNQAFFAMICAAPAGwWAA==.',
We='Weiyan:BAAANQADCgcIBwAAAA==.',
Wi='Winklebottom:BAAANQADCgcIDAAAAA==.',
Wo='Worgenkrantz:BAAANQAECgUICwAAAA==.Worthybacon:BAAANQAECgEIAgAAAA==.',
Wr='Wrathlor:BAAANQADCgQIBAAAAA==.Wrenlyn:BAACNQAFFIEHAAMHAAMKNwe5FACDAAAHAAIKsQi5FACDAAAZAAEKRAQnEQBQAAA1AAQKgSEABAcACQonFpIqACICAAcACQp6EZIqACICABkACAq6DWctALQBABgABgoYEmwTAEMBAAAA.',
Wu='Wukain:BAABNQAECoEXAAIEAAgK0AjDcgCYAQAEAAgK0AjDcgCYAQAAAA==.',
Xa='Xanatas:BAAANQADCgcIFAABNQAECgYIDQAKAAAAAA==.Xarapxeh:BAAANQADCgUICAAAAA==.',
Xo='Xolòtl:BAACNQAFFIEGAAIbAAMK+Qv7HgDTAAAbAAMK+Qv7HgDTAAA1AAQKgSYAAxsACQrpFlBZAGMCABsACQpaFlBZAGMCABwABwpvCyweADcBAAE1AAUUAwgHAAcANwcA.',
Xy='Xymos:BAECNQAFFIERAAMCAAUKrSIDBADQAAABAAQK7yHODAB5AQACAAIKniMDBADQAAA1AAQKgSQAAwIACQp8Jc4AAKADAAIACQpOJc4AAKADAAEABQo/HdeIAKIBAAAA.',
Ya='Yakul:BAAANQAECgUIDQAAAA==.',
Za='Zalyia:BAAANQADCgQIBAAAAA==.',
Zd='Zdk:BAAANQADCgEIAQAAAA==.',
Ze='Zeroveth:BAAANQAECgYICwAAAA==.Zexpert:BAAANQAECgIIAgABNQAECgYIDwAKAAAAAA==.',
Zu='Zugg:BAAANQADCggICAAAAA==.Zulcow:BAAANQAECgYICAAAAA==.',
['Âr']='Ârtemis:BAAANQAECgUICAAAAA==.',
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
