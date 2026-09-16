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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Mage-Arcane','Mage-Frost','Mage-Fire','Druid-Restoration','Paladin-Protection','Hunter-Marksmanship','Hunter-BeastMastery','DemonHunter-Devourer','DemonHunter-Havoc','Evoker-Devastation','Evoker-Preservation','Druid-Balance','Paladin-Holy','Warrior-Arms',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abeyancë:BAAANQAECgcIEAAAAA==.Abilities:BAAANQABCgYIDAAAAA==.',
Ae='Aeshanth:BAAANQADCgUIBgAAAA==.',
Ai='Airwrecka:BAAANQAECgcIEAAAAA==.',
Al='Altlas:BAAANQADCggIEAAAAA==.',
Am='Amaterasu:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
An='Anise:BAAANQADCgEIAQAAAA==.',
Ar='Arahgon:BAEANQAECgcIDAABNQADCggIGQABAAAAAA==.',
As='Asukà:BAAANQAECgMIBAAAAA==.',
Au='Auchenile:BAAANQAECgQIBgAAAA==.Austin:BAAANQAECgEIAQAAAA==.',
Av='Avanoura:BAAANQABCgQIBAABNQADCgcIDgABAAAAAA==.',
['Aé']='Aéd:BAAANQADCgQIBAABNQADCgYICgABAAAAAA==.',
Ba='Barkthas:BAAANQAECgIIAwAAAA==.',
Be='Bellarg:BAAANQAECgEIAgAAAA==.Belobog:BAAANQAECgUIBgAAAA==.Belyn:BAAANQADCggIGAAAAA==.',
Bi='Bifesor:BAAANQADCgMIAwAAAA==.Bizmania:BAAANQADCgQIBAAAAA==.',
Bl='Blackhøof:BAAANQADCgUIBwAAAA==.',
Br='Bratlax:BAAANQADCgIIAgABNQAECgkJHgACALUlAA==.Bro:BAAANQAECgMIBAAAAA==.Brolich:BAAANQAECgcIEgABNQAECgMIBAABAAAAAA==.Broo:BAAANQADCggICAABNQAECgMIBAABAAAAAA==.Brooak:BAAANQADCgIIAgABNQAECgMIBAABAAAAAA==.Brozeit:BAAANQADCggICAABNQAECgMIBAABAAAAAA==.',
Bu='Bubblegump:BAAANQAECgUIBQAAAA==.',
Ca='Calculusx:BAAANQAECgQICAAAAA==.Camión:BAAANQADCgYIBgAAAA==.',
Ce='Cellice:BAACNQAFFIEMAAMDAAYJjRUNAwAIAgADAAYJchINAwAIAgAEAAEJfR+vAgBcAAA1AAQKgR4ABAMACQlaI3kVAEgDAAMACQnqInkVAEgDAAUAAwm0EIgDAOsAAAQAAQksJYQdAF4AAAAA.',
Ch='Chuckborris:BAAANQADCgEIAQABNQAFFAEIAQABAAAAAA==.',
Cl='Clare:BAAANQAECgYICQAAAA==.',
Da='Daddydimes:BAAANQAECgUICQAAAA==.',
De='Deathfu:BAAANQABCgYIBgAAAA==.Deathless:BAAANQAECgQICQAAAA==.Demiize:BAAANQAECgQIBAAAAA==.Demize:BAAANQAECgcIEwAAAA==.Deshield:BAAANQAECgcIDwAAAA==.Deus:BAAANQAECgQIBgAAAA==.Dewry:BAAANQAECgYIDAAAAA==.',
Dh='Dhudamuthi:BAAANQAECgUIDAAAAA==.',
Di='Dizzo:BAAANQAECggIBwAAAA==.',
Do='Doink:BAAANQAECgQIBQABNQAECgkJGgAGAMseAA==.Donnajuan:BAAANQAECgYIBgAAAA==.Dornath:BAAANQADCggICAAAAA==.',
Dr='Draaxelro:BAAANQADCgUIDAAAAA==.Dragontiddys:BAAANQADCgIIAgAAAA==.',
El='Elimere:BAAANQAECgcIEgAAAA==.Elvarg:BAAANQAECgUICgAAAA==.Elywen:BAAANQAECgcIEQAAAA==.',
En='Enry:BAAANQADCggIEAAAAA==.',
Eq='Eqlipse:BAAANQADCgYIBgAAAA==.',
Es='Esira:BAAANQADCgIIAgAAAA==.',
Fi='Fiammetta:BAEANQADCgcIBwABNQAECgkJFwAHAM4hAA==.Finke:BAAANQAECgQIBAAAAA==.Fistzz:BAAANQADCgIIAgAAAA==.',
Fl='Flickerbeat:BAAANQADCggIDgAAAA==.',
Fr='Free:BAAANQAECgIIAwAAAA==.',
Fu='Futurama:BAAANQADCgQIBAAAAA==.',
Ga='Gabi:BAAANQABCgIIAgAAAA==.',
Gd='Gdizz:BAAANQAECggIDAAAAA==.',
Gh='Ghostshadows:BAAANQAECgQIBwAAAA==.',
Gi='Gigazapper:BAAANQAECgEIAgABNQAFFAEIAQABAAAAAA==.Gizzlit:BAAANQAECgEIAQAAAA==.',
Go='Gobiasinds:BAAANQAECgIIAgAAAA==.Gofetch:BAAANQAECgQIBwAAAA==.',
Gr='Grissum:BAAANQAECgUICQAAAA==.',
Gs='Gson:BAAANQADCggICAAAAA==.',
Gu='Guppy:BAAANQADCgYIBgAAAA==.',
Ha='Hac:BAAANQAECgUIBwAAAA==.Hallack:BAAANQAECgEIAQAAAA==.',
He='Healingkiss:BAAANQADCgUIBwAAAA==.',
Hi='Hikingboots:BAAANQAECgMIBQAAAA==.',
Ho='Hollypallz:BAAANQAECgIIAgAAAA==.Holymages:BAAANQAECgMIBAAAAA==.',
Ik='Iknowaguy:BAAANQAECgQICAAAAA==.',
Il='Illani:BAAANQAECgEIAgAAAA==.Ilyanna:BAAANQAECgcIEQAAAA==.',
Im='Im:BAABNQAECoEdAAMIAAkJ9SLQAwBtAwAIAAkJgCLQAwBtAwAJAAEJ9CUdswBvAAAAAA==.Imscary:BAAANQADCggIDQAAAA==.',
Iz='Izzo:BAAANQADCggICAAAAA==.',
Ja='Jausi:BAAANQAECgEIAQAAAA==.',
Jh='Jhops:BAAANQAECgUICQAAAA==.',
Ji='Jilliadk:BAAANQAECgEIAQAAAA==.Jirachi:BAAANQADCggIDAAAAA==.',
Ke='Keju:BAAANQADCggIGQAAAA==.Kerrigan:BAABNQAECoEcAAMKAAkJwRkEEgB7AgAKAAgJxhsEEgB7AgALAAEJoQl0SwBBAAAAAA==.',
Ko='Kookler:BAAANQADCgUIBQABNQAECgYIEAABAAAAAA==.',
Ku='Kuji:BAAANQAECgQICAAAAA==.',
Ky='Kyirr:BAAANQAECgYIDwAAAA==.',
La='Layke:BAAANQADCgcIEgAAAA==.Lazerbeampew:BAAANQAECgYIDgAAAA==.',
Ll='Llynryn:BAAANQADCgcIDgAAAA==.',
Lo='Locktuah:BAAANQADCgYICgAAAA==.Loklak:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Ma='Magicae:BAAANQAFFAEIAQABNQAFFAUICAAKAOsaAA==.Magicmanzz:BAAANQADCggIGgAAAA==.Magnifuso:BAAANQADCggIGgAAAA==.Maguapa:BAAANQAECgQIBAAAAA==.Margarita:BAAANQADCgQIBAAAAA==.Masstech:BAAANQAECgcICQAAAA==.Mastab:BAAANQAECgYIDgAAAA==.',
Mc='Mchammerdin:BAAANQAECgMIAwAAAA==.',
Me='Meat:BAAANQAECgQICAAAAA==.',
Mi='Mikio:BAAANQAECgIIAwAAAA==.Milinka:BAAANQAECgcIEgAAAA==.Mirror:BAAANQAECgYIBwAAAA==.',
Mo='Moiryn:BAAANQADCgIIAgAAAA==.',
My='Myshaman:BAAANQAECgMIAwAAAA==.',
Na='Navillus:BAABNQAECoErAAMMAAkJKyY0AAD2AwAMAAkJKyY0AAD2AwANAAUJqB1yIgDmAAAAAA==.',
No='Noxi:BAAANQAECgEIAwAAAA==.',
Oa='Oakensoul:BAAANQAECgEIAQABNQAECgYIDAABAAAAAA==.',
Og='Ogron:BAAANQADCgYIBgABNQAECgcIDwABAAAAAA==.',
Op='Ophindis:BAAANQAECgYIDAAAAA==.',
Pa='Pagoda:BAAANQAECgcIEAAAAA==.Panerai:BAAANQADCgYIBgAAAA==.',
Pe='Pewpop:BAAANQAECgQIEQAAAA==.',
Pi='Pintsize:BAAANQABCgcICQAAAA==.',
Pj='Pjt:BAAANQADCgEIAQAAAA==.',
Pu='Putemuptoo:BAAANQAECgEIAQAAAA==.',
Qp='Qpti:BAAANQAECgcIEwAAAA==.',
Ra='Razorclaw:BAAANQADCgEIAQABNQAECgQICgABAAAAAA==.Razz:BAAANQABCgcIBgAAAA==.',
Re='Rejectlol:BAAANQAECgYIDwAAAA==.Rennx:BAABNQAFFIEMAAIOAAYJixsqAQA7AgAOAAYJixsqAQA7AgAAAA==.Reznik:BAAANQAECgUICQAAAA==.',
Ri='Rika:BAAANQADCgQIBAAAAA==.Ringmasta:BAAANQADCgcIFgAAAA==.Riot:BAAANQAECgcIEAAAAA==.',
Ro='Rosé:BAAANQAFFAEIAQAAAA==.Rowen:BAAANQAECgIIAwAAAA==.',
['Rè']='Rènza:BAAANQAECggIAQAAAA==.',
Sa='Saintlorric:BAAANQABCgQIBAAAAA==.Sanguineous:BAAANQAECgIIBAABNQAECgQIBAABAAAAAA==.Saphia:BAEBNQAECoEXAAIHAAkJziFTAwA4AwAHAAkJziFTAwA4AwAAAA==.Saphyr:BAEANQAECgQIBQABNQAECgkJFwAHAM4hAA==.',
Sc='Scarydude:BAAANQAECgUICQAAAA==.',
Se='Sevrin:BAAANQAECgcIDwAAAA==.',
Sh='Shamoon:BAAANQAECgQIBQAAAA==.Shamwow:BAAANQAECgQICAABNQAECgUIBgABAAAAAA==.Sheesh:BAABNQAECoEaAAMGAAkJyx4OBQAOAwAGAAkJyx4OBQAOAwAOAAIJZhTRXgB7AAAAAA==.Shinru:BAABNQAECoEbAAIPAAgJVB7jEQDTAgAPAAgJVB7jEQDTAgAAAA==.Shrikedk:BAAANQADCgIIAgABNQAECgYICQABAAAAAA==.',
Si='Sickdayze:BAAANQAECgQIBwAAAA==.Sickhymns:BAAANQADCgcIDQABNQAECgQIBwABAAAAAA==.Sickntired:BAAANQADCgMIAwABNQAECgQIBwABAAAAAA==.Sicktides:BAAANQADCgYICAABNQAECgQIBwABAAAAAA==.',
Sk='Skinnymini:BAAANQADCgEIAQAAAA==.',
Sl='Slyxxar:BAAANQAECgUIEAAAAA==.',
Sn='Snoopyy:BAAANQADCgcIBwAAAA==.',
So='Soar:BAAANQAECgQICgAAAA==.Soph:BAAANQAECgQICwABNQAECgkJHgACALUlAA==.Sophie:BAABNQAECoEeAAICAAkJtSXUAgDMAwACAAkJtSXUAgDMAwAAAA==.Sophisticate:BAAANQAECgYICAABNQAECgkJHgACALUlAA==.Sophiz:BAAANQAECgQIBQABNQAECgkJHgACALUlAA==.Sophlax:BAAANQAECgQIDAABNQAECgkJHgACALUlAA==.Sophs:BAAANQAECgMIBwABNQAECgkJHgACALUlAA==.Sox:BAAANQAECgcIEAAAAA==.',
Sp='Spicynoodle:BAAANQAECgcIEgAAAA==.Spookyougi:BAAANQAECgQICwAAAA==.',
Sq='Squattinchop:BAAANQAECgMIBAAAAA==.',
St='Stabamon:BAAANQADCggICAAAAA==.Stiffcrit:BAAANQAECgQIBQAAAA==.',
Su='Sua:BAABNQAFFIEKAAIQAAUJARJABAC6AQAQAAUJARJABAC6AQAAAA==.Suksuksuk:BAAANQABCgQICAAAAA==.Supergogeta:BAAANQAECgUICQAAAA==.',
Sy='Sylvie:BAAANQAECgYIDAAAAA==.Synistër:BAAANQADCgYIDgAAAA==.',
['Sï']='Sïnsu:BAAANQAECgUICQAAAA==.',
Ta='Takoda:BAAANQAECgQIBQAAAA==.Talauyia:BAAANQADCggIDQAAAA==.Tankyou:BAAANQADCgYIBgAAAA==.',
Te='Temporë:BAAANQADCgIIAgAAAA==.',
Th='Thndrsquirel:BAAANQAECgEIAQABNQAECgQICAABAAAAAA==.Thrayne:BAAANQABCgMIAwAAAA==.',
Ti='Tiriandrel:BAAANQADCggICAABNQAECgYIDAABAAAAAA==.',
To='Toofaded:BAAANQADCgUIBQAAAA==.Torio:BAAANQAECgQIBgAAAA==.',
Tw='Twofow:BAAANQADCggIDwAAAA==.',
Ty='Tyranis:BAEANQADCggIGQAAAA==.Tyê:BAAANQAECgUICgAAAA==.',
['Té']='Témalabécane:BAAANQAECgUICgAAAA==.',
['Të']='Tërry:BAAANQADCgEIAQAAAA==.',
Va='Vael:BAAANQADCgYIBgAAAA==.Valexisea:BAAANQAECgUIBwAAAA==.Valériana:BAAANQADCgIIAgAAAA==.Vanítas:BAAANQADCgcIBgAAAA==.',
Vo='Voltage:BAAANQAECgQIDQABNQAECgQIEQABAAAAAA==.',
Vu='Vulgnash:BAAANQAECgcIEgAAAA==.Vult:BAAANQAECgYIDgAAAA==.',
We='Welgo:BAAANQAECgQIBgAAAA==.',
Wi='Wickeddemon:BAAANQADCgcIEAAAAA==.',
Xc='Xcesive:BAAANQADCggICAAAAA==.Xcessiv:BAAANQADCgQIBAAAAA==.Xcéssiv:BAAANQAECgYIDgAAAA==.',
Xe='Xerra:BAAANQAECgYICwAAAA==.',
['Xû']='Xûrû:BAAANQADCgQIBAAAAA==.',
Yr='Yrel:BAAANQADCgYICAABNQADCgYICgABAAAAAA==.',
Ze='Zelgie:BAAANQAECgUICgAAAA==.',
Zi='Zienna:BAAANQADCgcICQAAAA==.',
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
