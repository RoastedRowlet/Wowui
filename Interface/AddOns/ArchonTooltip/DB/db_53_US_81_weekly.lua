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

local lookup = {'Rogue-Outlaw','Shaman-Restoration','Hunter-BeastMastery','Druid-Restoration','Druid-Balance','Unknown-Unknown','Druid-Feral','Priest-Holy','Priest-Shadow','Warrior-Arms','DeathKnight-Blood','Paladin-Protection','Rogue-Subtlety','Rogue-Assassination','Paladin-Retribution','Priest-Discipline','Paladin-Holy','DemonHunter-Havoc','Mage-Frost','Shaman-Elemental','DeathKnight-Unholy','Evoker-Preservation','Shaman-Enhancement','Druid-Guardian','DeathKnight-Frost','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Warrior-Protection','Warlock-Destruction','Evoker-Augmentation','Evoker-Devastation','Warrior-Fury','Warlock-Demonology','Hunter-Marksmanship','Mage-Arcane','Hunter-Survival','Warlock-Affliction','DemonHunter-Devourer',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aakai:BAABNQAECn8rAAIBAAgKoBlYBgBsAgABAAgKoBlYBgBsAgAAAA==.Aarmorr:BAABNQAECn8gAAICAAcKlgrGnAA6AQACAAcKlgrGnAA6AQAAAA==.',
Ac='Acinianis:BAAANQADCggIDwAAAA==.',
Ad='Adinna:BAAANQADCgYIBgAAAA==.Adiro:BAAANQADCgQIBAAAAA==.Adsdad:BAAANQAECgIIAgAAAA==.',
Ae='Aedelas:BAAANQADCggIFQAAAA==.',
Ai='Aimeeiove:BAAANQAECgMIAwAAAA==.Airoldeel:BAAANQADCgcICAAAAA==.',
Ak='Akarag:BAAANQADCgcICQAAAA==.',
Al='Alcarza:BAAANQADCgcIBwAAAA==.Alchon:BAABNQAECn8jAAIDAAgK0xreUQB4AgADAAgK0xreUQB4AgAAAA==.Alicalsastre:BAAANQAECgcJDwAAAA==.Alista:BAAANQABCgIIAgAAAA==.Allykat:BAABNQAECn8dAAMEAAcKQQ3pOwA9AQAEAAcKQQ3pOwA9AQAFAAUKzgRZgwC/AAAAAA==.Alunathsong:BAAANQAECgYIBwAAAA==.Alvagíngras:BAAANQAECgUIBQAAAA==.',
Am='Amaith:BAAANQAECgQJCgAAAA==.Amantillado:BAAANQAECgEIAwABNQAECgYIDwAGAAAAAA==.Amata:BAAANQAECgIIAwAAAA==.Amblance:BAAANQAECgIIAgAAAA==.Amelianne:BAAANQAECgEIAQAAAA==.Ammastary:BAAANQAECgIIAwAAAA==.Ammonfrey:BAAANQADCgQIBAAAAA==.',
An='Andrea:BAABNQAECn8YAAIHAAYK+hEhGQBnAQAHAAYK+hEhGQBnAQAAAA==.Angelec:BAAANQADCgYIDAAAAA==.Anthria:BAAANQADCgQIBAAAAA==.Anysra:BAAANQADCgYJBgAAAA==.',
Ap='Apöllo:BAABNQAECn8XAAMIAAYKpQ6+kwBVAQAIAAYKpQ6+kwBVAQAJAAQKBAdHVQCzAAAAAA==.',
Aq='Aqules:BAAANQADCggICwAAAA==.',
Ar='Arcapeligo:BAAANQADCggIFQAAAA==.Archonsfury:BAAANQADCgcIBwAAAA==.Ardagg:BAAANQABCgYICQAAAA==.Arilyn:BAAANQADCgQIBAAAAA==.Arin:BAABNQAECn8XAAIKAAkK3hafbgBDAgAKAAkK3hafbgBDAgAAAA==.',
As='Ashentris:BAAANQAECgQIBQAAAA==.Asnew:BAABNQAECn8fAAILAAkKJQw+VwCTAQALAAkKJQw+VwCTAQAAAA==.Asura:BAAANQAECgcIDgAAAA==.',
At='Athelstan:BAAANQAECgUIEwAAAA==.Atonement:BAAANQADCgEIAQABNQAECggIJAAMAG8eAA==.',
Au='Aumaril:BAAANQADCggICAAAAA==.Aumaryl:BAABNQAECn8YAAMNAAgKwRbyEwBIAgANAAgKwRbyEwBIAgAOAAEKWA1SmgA/AAAAAA==.Auralynn:BAAANQAECgUIDAAAAA==.Auroriana:BAAANQADCgQIBQAAAA==.',
Av='Averus:BAABNQAECn8hAAIFAAcK4gmTXwBNAQAFAAcK4gmTXwBNAQAAAA==.',
Az='Azariel:BAABNQAECn8iAAMPAAgKJhLulwDvAQAPAAgKJhLulwDvAQAMAAEKAAAddAAnAAAAAA==.Azatre:BAAANQADCgIIAgAAAA==.Azuriah:BAABNQAECn8gAAIMAAcK1R3aGgAWAgAMAAcK1R3aGgAWAgAAAA==.',
Ba='Baane:BAAANQAECgIIAwABNQAECgMICQAGAAAAAA==.Babnik:BAEANQAECgcIDgAAAA==.Balderdashe:BAAANQADCggICwAAAA==.',
Be='Bealzibub:BAAANQABCgIIAgAAAA==.Bedhead:BAABNQAECn8aAAMIAAcK5x17UwAlAgAIAAcKpxx7UwAlAgAQAAMKOxgIFQDXAAAAAA==.Belaim:BAAANQABCgIIAgAAAA==.Belovis:BAACNQAFFH8JAAIPAAUKrRhOCgCfAQAPAAUKrRhOCgCfAQA1AAQKfyYAAg8ACQp1IzIfAEUDAA8ACQp1IzIfAEUDAAAA.Betsea:BAAANQADCgcIBwABNQAECgcIJQARABkYAA==.',
Bi='Bidock:BAAANQAECgQJBAAAAA==.Bidoof:BAABNQAECn8ZAAISAAgKPguCQQCvAQASAAgKPguCQQCvAQAAAA==.Bigocritties:BAAANQABCgMIAgAAAA==.Bitemarks:BAAANQADCggJFQAAAA==.Bix:BAABNQAECn8bAAITAAcKmB6tCQAxAgATAAcKmB6tCQAxAgAAAA==.',
Bl='Blackcoat:BAAANQADCgUIBQAAAA==.Blokmor:BAAANQAECgQIDgAAAA==.',
Bo='Boggrog:BAAANQAECgMICQAAAA==.Bolz:BAAANQADCgYIBgAAAA==.Bonepicklucy:BAAANQADCgUICQAAAA==.Boneybob:BAAANQABCgQJCAAAAA==.Boras:BAAANQAECgUIBwAAAA==.Bordeaux:BAAANQAECgMIBQABNQAECgQICwAGAAAAAA==.Bosshog:BAABNQAECn8YAAIUAAcKhAoNlwBnAQAUAAcKhAoNlwBnAQAAAA==.',
Br='Brabanzio:BAAANQAECgUIEgABNQAECgkJKAACAKAZAA==.Breadfriend:BAAANQADCggICAAAAA==.Brightnshiny:BAAANQABCgIIAgAAAA==.Broseidon:BAAANQAECgIIAwAAAA==.Brotato:BAAANQABCgcICwABNQAECgUIBwAGAAAAAA==.Brotatochip:BAAANQAECgUIBwAAAA==.Broxxer:BAAANQADCgYIBgAAAA==.Brycke:BAAANQADCggIFwAAAA==.',
Bu='Buffsalot:BAAANQAECgcIDAAAAA==.Burningblunt:BAAANQAECgQIBQAAAA==.Buttons:BAAANQADCgcJBwAAAA==.',
Ca='Calav:BAAANQADCgcIDgABNQAECgcIEQAGAAAAAA==.Castle:BAAANQAECgMICQAAAA==.Catsinhats:BAAANQADCggICgABNQAECgkJMQAVAPwZAA==.Catzinhatz:BAAANQADCgUIBQABNQAECgkJMQAVAPwZAA==.',
Ce='Cecelya:BAABNQAECn8hAAIIAAgKPxpLPgBuAgAIAAgKPxpLPgBuAgAAAA==.',
Ch='Chablis:BAAANQAECgEIAQAAAA==.Cherlia:BAAANQADCgcIDgABNQAECggIIwASADEdAA==.Chivactdl:BAAANQADCgYJCgABNQAECgcIIwACAFcUAA==.Chosenn:BAAANQAECgUICgAAAA==.Chotek:BAAANQAECgQIBgAAAA==.Chunknoriss:BAAANQAECgQICAABNQAECgcIIwACAFcUAA==.',
Ci='Cilarnen:BAAANQAECgQICAAAAA==.',
Cl='Claudiuss:BAAANQAECgUIBQABNQAECgkJKAACAKAZAA==.Clure:BAABNQAECn8jAAIRAAgKECPVFAAsAwARAAgKECPVFAAsAwABNQAECggIKgAWAO8ZAA==.Clurelock:BAAANQADCgQIBAABNQAECggIKgAWAO8ZAA==.Clurethyr:BAABNQAECn8qAAIWAAgK7xmkFABlAgAWAAgK7xmkFABlAgAAAA==.',
Co='Conchobhar:BAAANQAECgUIBgAAAA==.Coppertan:BAAANQADCgcIFwAAAA==.Cornaddict:BAACNQAFFH8NAAMIAAUKdw33EgBvAQAIAAUKdw33EgBvAQAJAAEKAAABGABEAAA1AAQKfykAAwgACQo2FgtIAEsCAAgACApHGAtIAEsCAAkACAq2HTUhACoCAAAA.Corrosion:BAABNQAECn8dAAIXAAkKbB7XBgAUAwAXAAkKbB7XBgAUAwAAAA==.',
Cr='Crommash:BAAANQAECggICQAAAA==.Cromshade:BAAANQABCgYIBgAAAA==.Cromsteel:BAAANQADCgQIBAAAAA==.Cromsyth:BAAANQADCgYIBgAAAA==.Crono:BAAANQADCgYICQAAAA==.Crunchynuget:BAABNQAECn8UAAIPAAUKIxMQ7gA5AQAPAAUKIxMQ7gA5AQABNQAECgkJLgAPADggAA==.Crylessplz:BAAANQAECgQIBgABNQAECggIJAAMAG8eAA==.',
Ct='Cthuwu:BAAANQAECgUIBgABNQAFFAIIBQADAJsdAA==.',
Cv='Cvhamster:BAAANQADCgcIBwAAAA==.',
Cy='Cy:BAAANQADCggJCAAAAA==.Cybeast:BAABNQAECn8eAAMHAAgKnxqICwBxAgAHAAgKnxqICwBxAgAYAAMK1BaOQgClAAAAAA==.Cynortas:BAAANQADCgUIBQAAAA==.',
Da='Daciana:BAAANQAECgUIEgAAAA==.Dados:BAAANQAECgUIBQAAAA==.Daeghun:BAAANQADCgYIBgAAAA==.Dahleigh:BAAANQADCgYIBAAAAA==.Dakanar:BAAANQADCggIDAAAAA==.Darkessence:BAAANQADCgEIAQAAAA==.Darkfox:BAAANQADCgYIBgAAAA==.Darkhazel:BAAANQAECgUIBgAAAA==.Darkkromdor:BAABNQAECn8lAAIPAAgKWByXYAB0AgAPAAgKWByXYAB0AgAAAA==.Darloct:BAAANQADCgEIAgAAAA==.',
De='Deadelff:BAABNQAECn8kAAISAAgKFBk9JwBgAgASAAgKFBk9JwBgAgAAAA==.Deathcat:BAABNQAECn8xAAMVAAkK/BmrLQB5AgAVAAkK/BmrLQB5AgAZAAYKPguFXwAfAQAAAA==.Deathkiss:BAAANQAECgMJBAAAAA==.Deathrixx:BAAANQADCggICAAAAA==.Deathshadowx:BAAANQAECgIIAwAAAA==.Decayy:BAABNQAECn8cAAILAAkKUxdNLQBeAgALAAkKUxdNLQBeAgAAAA==.Dedbull:BAAANQADCggJIQAAAA==.Demodius:BAAANQADCggICAAAAA==.Demourdenite:BAAANQADCgYJFQAAAA==.Des:BAAANQABCgIIAgAAAA==.',
Di='Discharged:BAAANQADCgYICAABNQAECgYIDwAGAAAAAA==.',
Dk='Dkpheonix:BAABNQAECn8dAAIJAAcKoxWnKQDXAQAJAAcKoxWnKQDXAQAAAA==.',
Do='Dolemite:BAAANQAECgQIDwAAAA==.Donalbain:BAABNQAECn8oAAICAAkKoBnFLgCkAgACAAkKoBnFLgCkAgAAAA==.Donninban:BAAANQAECgUICwAAAA==.Doodoobutter:BAAANQAECgIIAgABNQAECgkJJgAaABgZAA==.',
Dr='Draganpriest:BAAANQAECgEIAQAAAA==.Dremar:BAAANQAECgQIBQAAAA==.Drizzeh:BAAANQABCggIEAAAAA==.',
Du='Duarcán:BAAANQADCgEIAQAAAA==.Dunshotya:BAAANQAECgEIAQAAAA==.',
Eb='Ebolla:BAAANQADCgcIBwAAAA==.',
Ec='Eclipsy:BAAANQADCgIIAgAAAA==.',
Eg='Eggroll:BAAANQADCgUIBQAAAA==.',
El='Elexander:BAAANQAECgEIAQAAAA==.Elifar:BAAANQADCggIFwAAAA==.Eluneatic:BAAANQADCgQIBAAAAA==.Elyssaris:BAABNQAECn8jAAILAAgKcxaqOAAiAgALAAgKcxaqOAAiAgAAAA==.Elzulkin:BAAANQADCgQIBAAAAA==.',
Em='Emmdeath:BAAANQADCgYIBgAAAA==.Emmils:BAABNQAECn8dAAIFAAgKtwcIVgB7AQAFAAgKtwcIVgB7AQAAAA==.Emìly:BAABNQAECn8gAAMbAAcK3RYRKQDSAQAbAAcK3RYRKQDSAQAcAAcKYxa6GwDDAQAAAA==.',
En='Entaria:BAAANQAECgUIBwAAAA==.',
Ep='Ephria:BAABNQAECn8oAAMCAAgKuSTTDwBEAwACAAgKuSTTDwBEAwAUAAEKAAAKSQEnAAAAAA==.Episkey:BAAANQAECgQIBwAAAA==.',
Er='Eroversion:BAAANQAECgUICgABNQAECggINQAdAO0aAA==.Eroward:BAABNQAECn81AAIdAAgK7RrrDgA6AgAdAAgK7RrrDgA6AgAAAA==.',
Es='Esmay:BAAANQAECgYIEwAAAA==.',
Et='Ethren:BAABNQAECn8hAAIOAAcKNxKePwDJAQAOAAcKNxKePwDJAQAAAA==.',
Eu='Eudoxos:BAAANQAECgEIAQAAAA==.Euroecka:BAAANQADCgYIBQAAAA==.',
Ev='Evelynstar:BAAANQADCgMJAwAAAA==.',
Ez='Ezikarridge:BAAANQADCggIDgAAAA==.',
Fa='Falcone:BAAANQAECgEIAQAAAA==.',
Fe='Felbolter:BAABNQAECn8gAAIeAAcKGB6bCAByAgAeAAcKGB6bCAByAgAAAA==.Feliri:BAAANQADCgMIAwAAAA==.Fetide:BAAANQADCgIIAgAAAA==.',
Fi='Fiddlefaddle:BAAANQABCgMIAwAAAA==.Filgulfin:BAABNQAECn8lAAIDAAgKlBobPwCrAgADAAgKlBobPwCrAgAAAA==.Finkate:BAAANQAECgcICQAAAA==.Firebringer:BAAANQAECgcIDgAAAA==.Fistmegently:BAAANQADCgYICAAAAA==.',
Fl='Flamehunter:BAAANQAECgEIAQAAAA==.Flo:BAABNQAECn8tAAMJAAgKfBbUIgAZAgAJAAgKfBbUIgAZAgAQAAYKrgtQEAAiAQAAAA==.Floki:BAAANQAECgUIEwAAAA==.Flokin:BAAANQADCggICwAAAA==.Flowing:BAABNQAECn8nAAQfAAgKwhQNCAAbAgAfAAgKwhQNCAAbAgAWAAYKIwe7MQAIAQAgAAQKfARWLwCcAAAAAA==.',
Fo='Foods:BAABNQAECn8tAAQKAAgKEgz2sACdAQAKAAgKqAn2sACdAQAdAAUKWg3sLADJAAAhAAEKnA+2LgBDAAAAAA==.',
Fr='Fripouille:BAAANQADCgQIBwAAAA==.',
['Fæ']='Fæ:BAAANQADCgcIBwAAAA==.',
Ga='Gabmoo:BAAANQADCgMIAwAAAA==.Gaboo:BAAANQAECgUIEwAAAA==.',
Gh='Ghostinhale:BAAANQADCgQIBAAAAA==.',
Gi='Gilorion:BAABNQAECn8XAAIDAAcK5RemfQAPAgADAAcK5RemfQAPAgAAAA==.',
Gl='Glasgoww:BAAANQADCgUIBQABNQAECgkJKAACAKAZAA==.Gler:BAAANQADCgQJBQAAAA==.',
Gn='Gnibat:BAAANQAECgIIAwAAAA==.',
Go='Goburina:BAABNQAECn8jAAICAAkKWREfXgDxAQACAAkKWREfXgDxAQAAAA==.Goldhawk:BAAANQABCgIIAgAAAA==.',
Gr='Gryffen:BAAANQABCgcIBwAAAA==.',
Gu='Gulpron:BAAANQABCgMJBAAAAA==.',
['Gí']='Gímlí:BAABNQAECn8fAAIDAAgKCBs0TgCBAgADAAgKCBs0TgCBAgAAAA==.',
Ha='Haidyn:BAAANQADCgMJAwAAAA==.Halcyndraag:BAABNQAECn8hAAQgAAcKNQ+gHwBYAQAgAAYKow2gHwBYAQAWAAUKzgTEOgC/AAAfAAIKKBBaHgBqAAAAAA==.Handofcope:BAAANQAECgYIEAAAAA==.Hartu:BAABNQAECn8pAAIdAAgKoBgPDgBLAgAdAAgKoBgPDgBLAgAAAA==.',
He='Hemogobblin:BAAANQADCgQIBAAAAA==.Herbalmist:BAAANQAECgIIAwAAAA==.',
Hi='Hircine:BAAANQADCggIDAAAAA==.',
Ho='Holysea:BAAANQAECgIIAgABNQAECgcIJQARABkYAA==.Honk:BAAANQADCggIEQAAAA==.',
Im='Imwithfloki:BAAANQAECgUIEwAAAA==.',
Ir='Ironmark:BAAANQAECgIIAgAAAA==.Irys:BAAANQADCgcIDQAAAA==.',
Is='Isam:BAAANQAECgUIBQAAAA==.Isamidor:BAABNQAECn8mAAIDAAkK6SWHCACYAwADAAkK6SWHCACYAwAAAA==.Ismokeu:BAABNQAECn8gAAIIAAkKYRegRwBMAgAIAAkKYRegRwBMAgAAAA==.Ismyn:BAAANQAECgIIAgAAAA==.Istran:BAAANQAECgQIBAAAAA==.',
Iv='Ivrys:BAAANQAECgcIDwAAAA==.',
Iw='Iwillbethere:BAAANQAECgIIAgAAAA==.',
Ja='Jackoneal:BAAANQAECgYIEAAAAA==.Jalidelo:BAABNQAECn8jAAIIAAgKHRX4WAATAgAIAAgKHRX4WAATAgAAAA==.Jalidemon:BAAANQADCggIEAAAAA==.Jalyyn:BAAANQADCgEIAQAAAA==.',
Ji='Jingild:BAAANQADCgYIBgAAAA==.',
Jo='Joeyfoxone:BAAANQADCgQIBAAAAA==.Johan:BAABNQAECn8iAAIiAAgK6hvxRACBAgAiAAgK6hvxRACBAgAAAA==.Jokersfists:BAAANQAECgQIBAABNQAECgUIDQAGAAAAAA==.Jokersmage:BAAANQAECgUIDQAAAA==.Joraflheim:BAAANQABCgIIAgAAAA==.Joranbragi:BAAANQAECgQIDAAAAA==.Jordanjr:BAABNQAECn8rAAMDAAkKYBe4SwCIAgADAAkKCRO4SwCIAgAjAAgKphDpMADCAQAAAA==.Josunlee:BAAANQAECgIIAgAAAA==.Jotoonice:BAABNQAECn8dAAMTAAgKKBJxFgBIAQATAAUKaBRxFgBIAQAkAAYKhAfiRAEWAQAAAA==.',
Jt='Jtoothaordan:BAACNQAFFH8LAAMjAAQKgRDBEgAOAQAjAAQKtw7BEgAOAQADAAEKFw7FNgBLAAA1AAQKfy4AAyMACQoOGiQcAG8CACMACQopFyQcAG8CAAMAAgpsIWoiAaoAAAAA.',
Ju='Juicyfruit:BAAANQABCgYICAAAAA==.Jules:BAAANQADCgcIBwAAAA==.',
Ka='Kaana:BAABNQAECn8hAAIDAAcK4w4ilgDYAQADAAcK4w4ilgDYAQAAAA==.Kaedina:BAAANQAECggIEAABNQAECgkJKwADAGAXAA==.Kallista:BAAANQADCgYIDwAAAA==.Karugan:BAAANQADCgEIAQABNQADCgcICQAGAAAAAA==.Karvel:BAABNQAECn8fAAILAAgKEhwDLwBVAgALAAgKEhwDLwBVAgAAAA==.Kaychow:BAAANQAECgQICAABNQAECggIGAARAAgdAA==.Kaydullz:BAAANQAECgYICAAAAA==.',
Kc='Kchowchow:BAAANQAECgEIAgABNQAECggIGAARAAgdAA==.',
Ke='Kelonaar:BAACNQAFFH8IAAMUAAMKXBB1GQDxAAAUAAMKXBB1GQDxAAACAAIKuAP6JQBuAAA1AAQKfyMAAxQACQqOH/siAPkCABQACQqOH/siAPkCAAIAAgqxHXrgAKQAAAAA.Kenack:BAAANQADCgUIBQAAAA==.',
Kh='Kharys:BAAANQADCggIHAAAAA==.',
Ki='Killermoomoo:BAAANQAECgIIAwAAAA==.',
Kl='Kloverr:BAAANQAECgYIEAAAAA==.',
Ko='Kombatkarl:BAAANQADCgMIAwAAAA==.Koranthia:BAAANQADCgUIBQAAAA==.',
Kr='Kretaios:BAAANQADCgEIAQAAAA==.Kromir:BAAANQADCggICAAAAA==.Kronixrage:BAAANQAECgMIBQAAAA==.Krooler:BAAANQAECgMJBAAAAA==.Krum:BAAANQAECgYIEQAAAA==.',
La='Ladgarkk:BAAANQAECgUIBQAAAA==.Lanval:BAABNQAECn8qAAIPAAgKcBoyYQByAgAPAAgKcBoyYQByAgAAAA==.Latinlover:BAAANQAECgIIAgAAAA==.Laurian:BAAANQABCgMIAwAAAA==.',
Le='Leaky:BAAANQADCgQIBQAAAA==.Leetah:BAABNQAECn8vAAIYAAgKqhsvDQCPAgAYAAgKqhsvDQCPAgAAAA==.Leftblank:BAAANQAECgEIAgAAAA==.',
Li='Lich:BAAANQAECgQIBAAAAA==.Lighthugger:BAABNQAECn8pAAIPAAgKLhgXdgA9AgAPAAgKLhgXdgA9AgAAAA==.Lilyoptra:BAAANQAECgQICAABNQAECgQICAAGAAAAAA==.Liqmycrits:BAAANQADCggIFgAAAA==.Lishalzin:BAAANQAECgEIAQABNQAECgUIEAAGAAAAAA==.Liszt:BAAANQADCgMIAwAAAA==.Livana:BAAANQADCggIEAABNQAECgYIDwAGAAAAAA==.',
Lo='Lockpockets:BAAANQAECgQICgAAAA==.Loriane:BAAANQAECgIIAgABNQAECgcIEQAGAAAAAA==.Lorianth:BAABNQAECn8rAAIjAAgKXxLfJgARAgAjAAgKXxLfJgARAgAAAA==.Lotharbacco:BAAANQADCggICAAAAA==.Lovegood:BAAANQADCgUIBQAAAA==.Loveisbeauty:BAAANQADCgYIAwAAAA==.',
Lu='Lucifér:BAAANQABCggICgAAAA==.',
Ly='Lychi:BAAANQAECgIIAwAAAA==.Lylora:BAABNQAECn82AAIEAAkKyyU/AQDGAwAEAAkKyyU/AQDGAwAAAA==.',
['Lê']='Lêmonaide:BAABNQAECn8hAAMIAAgKfha+UQArAgAIAAgKfha+UQArAgAJAAEKAADNiQAfAAAAAA==.',
Ma='Madclaws:BAABNQAECn8tAAMFAAgKyRxQJgCeAgAFAAgKFRxQJgCeAgAYAAYKrxqfGQDWAQAAAA==.Madman:BAAANQAECgQICgAAAA==.Magekaestey:BAAANQADCggIDwABNQAECggIHwAKAHkNAA==.Malala:BAAANQADCgYIEAABNQAECggIMQAIAKoaAA==.Malyndra:BAAANQAECgUICAAAAA==.Marshy:BAAANQAFFAEIAQAAAA==.Marvolt:BAABNQAECn8gAAIiAAgKdQhsmwCcAQAiAAgKdQhsmwCcAQAAAA==.Masy:BAAANQABCgIIAgAAAA==.',
Me='Mesmash:BAABNQAECn8XAAIdAAcKYiKwCQCrAgAdAAcKYiKwCQCrAgAAAA==.Metadk:BAAANQAECgYIDwAAAA==.Metamasters:BAAANQADCgYIDAABNQAECgYIDwAGAAAAAA==.',
Mi='Mialtaa:BAAANQAECgIIAwAAAA==.Micah:BAAANQAECgIJAgAAAA==.Midgiit:BAAANQAECgUIBQABNQAECgkJJgAIAAEZAA==.Miniborg:BAAANQAECgUIBQABNQAECgkJLgAPADggAA==.Minidude:BAAANQAECgQIBAAAAA==.Misfire:BAAANQAECgEIAQAAAA==.Mistycrusade:BAAANQAECgIIAwAAAA==.Mizzen:BAABNQAECn8bAAMVAAgKcRYuPQAoAgAVAAgKcRYuPQAoAgALAAIKpQxdswBfAAABNQAFFAMIBgAJAOsLAA==.',
Mo='Moejojojo:BAAANQAECgUIEwAAAA==.Moofasaha:BAABNQAECn8YAAMCAAYKbB2AYQDmAQACAAYKbB2AYQDmAQAUAAMKiAhq+ACbAAAAAA==.Morog:BAAANQAECgcIDwAAAA==.Morragan:BAAANQADCggIGQAAAA==.',
Mu='Mulvan:BAAANQAECgUIEQAAAA==.',
['Mâ']='Mârshy:BAAANQAECgQIBAABNQAFFAEIAQAGAAAAAA==.',
['Mã']='Mãrshy:BAAANQAECgcIEAABNQAFFAEIAQAGAAAAAA==.',
['Mä']='Märshy:BAAANQAECgIIAwABNQAFFAEIAQAGAAAAAA==.',
Na='Nabû:BAAANQADCgQIBAAAAA==.Naler:BAAANQAECgUICAAAAA==.Nanarus:BAABNQAECn8xAAIIAAgKqhouPgBuAgAIAAgKqhouPgBuAgAAAA==.Nashalie:BAABNQAECn8oAAMiAAgKWCP1FwAmAwAiAAgKWCP1FwAmAwAeAAIKOgxnVQB9AAAAAA==.',
Ne='Nedyav:BAAANQADCgIIAgAAAA==.Nefele:BAAANQAECgUIEAAAAA==.Nexbasia:BAABNQAECn8iAAIHAAgKNRAqEQDuAQAHAAgKNRAqEQDuAQAAAA==.',
Ni='Nickyboy:BAAANQAECgIIAQAAAA==.Nightevel:BAAANQADCgYICQAAAA==.Nihimetal:BAAANQADCgcIEwAAAA==.',
No='Noctum:BAAANQAECgIIAgAAAA==.Nomad:BAAANQADCggIGgAAAA==.Norinisa:BAAANQABCgcIBwAAAA==.',
Ny='Nymmycup:BAAANQAECgMIBAAAAA==.',
Oc='Octt:BAAANQAECgYICgAAAA==.',
Ol='Oldcannabis:BAAANQAECgcIEAAAAA==.',
Om='Ominis:BAAANQADCgQJBAAAAA==.',
Oo='Oomaw:BAAANQAECgEIAQAAAA==.',
Or='Ormbar:BAAANQADCgIIAgAAAA==.Ornimus:BAAANQAECgMICwAAAA==.Ortian:BAAANQAECgEIAQAAAA==.',
Os='Osrs:BAACNQAFFH8HAAIJAAQKdBohCgBSAQAJAAQKdBohCgBSAQA1AAQKfxwAAgkACQpNIvYQAOgCAAkACQpNIvYQAOgCAAAA.',
Oz='Ozo:BAAANQAECgQICQAAAA==.',
Pa='Paiva:BAAANQAECgIIAgAAAA==.Palandor:BAAANQADCgYIBgAAAA==.Pallydoof:BAAANQADCgcIBwAAAA==.Pallyscorned:BAABNQAECn8iAAIMAAgKuBevHQD5AQAMAAgKuBevHQD5AQAAAA==.Pamgetem:BAAANQAECgQIBQABNQAECgcIDwAGAAAAAA==.Pampas:BAAANQAECgEIAQAAAA==.Panduh:BAABNQAECn8rAAMbAAkKTSHpCgAiAwAbAAkK9SDpCgAiAwAaAAcKjx9zDgALAgAAAA==.',
Ph='Phenixy:BAAANQAECgIIAwAAAA==.Phoebell:BAAANQAECgQIBwAAAA==.Phoinix:BAAANQADCgcIDgAAAA==.',
Pi='Pinkducky:BAAANQADCgcIFAAAAA==.',
Pl='Plen:BAAANQAECgIIAgABNQAECgkJJgAIAAEZAA==.',
Po='Ponyo:BAABNQAECn8nAAIIAAgKXSP8GQAKAwAIAAgKXSP8GQAKAwAAAA==.Poppyseed:BAAANQAECgUIBQAAAA==.Poquads:BAAANQADCggIDAAAAA==.',
Pu='Pulmifinger:BAAANQADCggICAAAAA==.',
Pv='Pve:BAAANQADCgIIAgAAAA==.',
Qu='Quiewt:BAABNQAECn8bAAMjAAcK4hDfNwCMAQAjAAcKARDfNwCMAQADAAMK1hGlGgHBAAAAAA==.',
Ra='Raddra:BAAANQAECgUIBQAAAA==.Raddrah:BAAANQABCgUICAAAAA==.Raddrap:BAAANQADCgUIBgAAAA==.Radra:BAAANQAECgUIEgAAAA==.Raeku:BAABNQAECn8iAAIlAAgKoh5QAwDfAgAlAAgKoh5QAwDfAgAAAA==.Raharuto:BAAANQADCggICAAAAA==.Raja:BAAANQAECgMJBQAAAA==.Rav:BAAANQADCgIIAgAAAA==.Razzlor:BAAANQADCgQIBAAAAA==.',
Re='Recoill:BAABNQAECn8gAAIIAAgK6BfqRQBSAgAIAAgK6BfqRQBSAgAAAA==.Reducto:BAAANQADCgYICwAAAA==.Retribution:BAABNQAECn8hAAIPAAgKow7FqADJAQAPAAgKow7FqADJAQAAAA==.',
Ro='Robomurph:BAAANQADCgQIBAAAAA==.Rolas:BAAANQAECgEIAQAAAA==.Ronfax:BAACNQAFFH8LAAICAAQK4ho6EABGAQACAAQK4ho6EABGAQA1AAQKfyoAAgIACQp9IQYSADYDAAIACQp9IQYSADYDAAAA.Roony:BAAANQADCgIIAQAAAA==.Rooss:BAAANQAECgUIDAAAAA==.Rowdyredneck:BAAANQADCgYIBwABNQAECgYIDwAGAAAAAA==.',
Ru='Rul:BAAANQADCgIIAgABNQAECgkJKwAbAE0hAA==.',
Ry='Ryllae:BAAANQADCgIIAgABNQAECggIIwASADEdAA==.Ryuu:BAAANQAECgIIAwAAAA==.Ryuusythe:BAAANQADCggICQAAAA==.',
['Rì']='Rììdìì:BAABNQAECn8YAAMmAAgK6AfNGQC2AAAiAAgKZAePqQB7AQAmAAQKuwbNGQC2AAABNQAECggIHwADAAgbAA==.',
['Rï']='Rïchardgear:BAAANQADCggIDAABNQAECggIHwADAAgbAA==.',
Sa='Saint:BAABNQAECn8aAAMPAAcKKhTNvACdAQAPAAYK9xbNvACdAQARAAYKcRHojQBwAQAAAA==.Salopard:BAAANQADCgQIBAAAAA==.Sarinae:BAABNQAECn8cAAMfAAcKIgiDEAAsAQAfAAcKCQiDEAAsAQAgAAYKIwQHKgDVAAAAAA==.Sarmuc:BAABNQAECn8vAAIXAAkKxRcIDQCbAgAXAAkKxRcIDQCbAgAAAA==.Saryda:BAAANQAECgQICwAAAA==.Sauda:BAAANQAECgMIAwAAAA==.',
Sc='Schuybusta:BAAANQAECgEIAQAAAA==.Scubagal:BAAANQAECgQIBwAAAA==.',
Se='Secundinius:BAAANQADCgMIAwAAAA==.Selûne:BAAANQABCggICgAAAA==.Sensu:BAAANQAECgMICQAAAA==.Serrest:BAAANQAECgUICgAAAA==.Seä:BAABNQAECn8lAAIRAAcKGRgzVAAaAgARAAcKGRgzVAAaAgAAAA==.',
Sh='Shacktown:BAAANQABCgYICQAAAA==.Shadowdoh:BAAANQAECgQICAABNQAECgUICAAGAAAAAA==.Shapzan:BAAANQAECgMICAAAAA==.Sharks:BAAANQAECgQJBgAAAA==.Shivant:BAABNQAECn8jAAICAAcKVxRgewCVAQACAAcKVxRgewCVAQAAAA==.',
Si='Silendreas:BAAANQADCgUIBQAAAA==.',
Sl='Sloth:BAABNQAECn8hAAILAAcK7iJrHwC0AgALAAcK7iJrHwC0AgAAAA==.',
Sm='Smalltwngirl:BAAANQAECgYIDgABNQAFFAQICwACAOIaAA==.',
So='Solaire:BAAANQAECgMIBAAAAA==.Solaspirus:BAAANQAECgUIDAAAAA==.Solinius:BAAANQADCggIGgAAAA==.Songbreeze:BAABNQAECn8mAAMIAAkKARlYKQDBAgAIAAkKARlYKQDBAgAJAAUKmQU/TwDRAAAAAA==.Sonofagun:BAAANQAECgUIBgAAAA==.',
Sp='Spectors:BAABNQAECn8kAAQmAAgKJQYYDgBvAQAmAAcKiQYYDgBvAQAiAAcKHwMt5QD5AAAeAAEKAACIhAAkAAAAAA==.Spideygirl:BAAANQAECgEIAQAAAA==.',
St='Stabon:BAAANQAECgIJBgAAAA==.Strykah:BAAANQADCgQIBAAAAA==.',
Su='Sugarcube:BAAANQAECgEIAQAAAA==.Sugarmarks:BAAANQAECgIJAgAAAA==.',
Sw='Sweetstorm:BAABNQAECn8YAAISAAYKogLNagDIAAASAAYKogLNagDIAAAAAA==.',
Sy='Sydburns:BAAANQABCgYICAAAAA==.Sydley:BAAANQABCgUIBQAAAA==.',
Ta='Tagg:BAAANQADCggICAAAAA==.Taotao:BAAANQAECgUIBQAAAA==.Tarixx:BAAANQAECggIDQAAAA==.Tazanoth:BAABNQAECn8pAAQDAAcKaiCLYABTAgADAAcKaR6LYABTAgAlAAYKfh8MBgBEAgAjAAYKPQp5RgAiAQAAAA==.',
Te='Tekeela:BAAANQAECgQICAABNQAFFAIIBQADAJsdAA==.Tekeelà:BAACNQAFFH8FAAIDAAIKmx0hIACvAAADAAIKmx0hIACvAAA1AAQKfzEAAgMACQoPIowOAGwDAAMACQoPIowOAGwDAAAA.',
Th='Thalarus:BAAANQADCgIIAgABNQADCgcICQAGAAAAAA==.Thalion:BAAANQAECgIIAgAAAA==.Theenna:BAAANQADCgEIAQAAAA==.Thess:BAAANQADCgYIBgAAAA==.Thianna:BAAANQAECgUIEgAAAA==.Thobu:BAAANQAECgQIBAAAAA==.Thornscale:BAABNQAECn8dAAQfAAgKVQpSDgBfAQAgAAgKmAdyHQB0AQAfAAcKMgpSDgBfAQAWAAEKJQIRUgAmAAAAAA==.',
Ti='Tigolcrittys:BAAANQADCggIEQABNQAECggIHwADAAgbAA==.',
To='Tokkem:BAAANQADCgEIAQAAAA==.Tomzombe:BAAANQADCgYICgAAAA==.Tonguepunch:BAAANQAECgYIDQAAAA==.Totem:BAAANQAECgEIAQAAAA==.Tovê:BAAANQAECgYIBgAAAA==.',
Tr='Traumajazz:BAAANQABCgIIAgAAAA==.Traveler:BAAANQADCgEIAQAAAA==.Trenko:BAAANQADCgMIAwAAAA==.Troloq:BAABNQAECn8dAAMeAAgKzCB5BADiAgAeAAgKzCB5BADiAgAmAAMKQBKrGQC3AAAAAA==.',
Tu='Turger:BAAANQADCggIEAABNQAECgYIGAACAGwdAA==.',
Va='Vaeluptuous:BAAANQAECgQIDQAAAA==.Vahlorraa:BAAANQADCgMJAwAAAA==.Vaimei:BAABNQAECn8hAAMeAAkKmSCvBADaAgAeAAgKzx2vBADaAgAiAAcK1hvmZQAlAgAAAA==.Vallyna:BAAANQADCgYIBgAAAA==.Vapor:BAAANQAECgYIDAAAAA==.Varaine:BAAANQADCgYICwABNQAECgUIEAAGAAAAAA==.',
Ve='Veebs:BAAANQAECgUJBQAAAA==.Vento:BAAANQADCggIDgAAAA==.Verité:BAAANQAECgYIDwAAAA==.',
Vi='Virauca:BAABNQAECn8iAAInAAgKxQumLwDAAQAnAAgKxQumLwDAAQAAAA==.Vizon:BAAANQADCggIGAAAAA==.',
Vo='Voices:BAAANQAECgYIEwAAAA==.Voltrix:BAAANQADCggIGwAAAA==.',
Vy='Vynesta:BAABNQAECn8jAAISAAgKMR34IACPAgASAAgKMR34IACPAgAAAA==.',
Wa='Wanagi:BAAANQAECgMIBQAAAA==.Wankz:BAAANQAECgUIDAAAAA==.Warkaestey:BAABNQAECn8fAAIKAAgKeQ17pQC7AQAKAAgKeQ17pQC7AQAAAA==.Warriorguyes:BAAANQAECgYIEgAAAA==.',
Wh='Whomper:BAAANQAECgMIBAAAAA==.',
Wi='Wickedshadow:BAAANQADCgIIAgAAAA==.Widowx:BAAANQAECgUIDAAAAA==.Windshrieker:BAAANQADCgYIBgAAAA==.Wintervalor:BAABNQAECn8fAAILAAcKlBEsVQCcAQALAAcKlBEsVQCcAQAAAA==.',
Wo='Womphunt:BAABNQAECn8WAAIDAAgKTRMtaQA/AgADAAgKTRMtaQA/AgAAAA==.',
Wu='Wulyn:BAAANQAECgMICAAAAA==.',
Wy='Wylla:BAABNQAECn8WAAIbAAUKSwvJRwDcAAAbAAUKSwvJRwDcAAAAAA==.',
Xa='Xalethra:BAAANQAECgQIBQAAAA==.',
Xe='Xenophobias:BAAANQADCgcIFwAAAA==.',
Xs='Xsuns:BAABNQAECn8ZAAIEAAcKyBn7IQATAgAEAAcKyBn7IQATAgAAAA==.',
Yv='Yve:BAAANQAECgMIBQAAAA==.',
Za='Zabberz:BAAANQADCgQJBAAAAA==.Zaharian:BAAANQADCgYJBgAAAA==.Zalajin:BAAANQAECgMIBQAAAA==.Zarathiel:BAABNQAECn8YAAIKAAkKHAx3nQDOAQAKAAkKHAx3nQDOAQAAAA==.',
Ze='Zeddicus:BAABNQAECn8aAAImAAcKdgYaDwBbAQAmAAcKdgYaDwBbAQAAAA==.',
Zi='Zivadaavid:BAAANQADCgEIAQAAAA==.',
Zo='Zoidz:BAAANQAECgQIBAAAAA==.Zoriadon:BAAANQADCgcIDAAAAA==.',
Zz='Zzilladinzz:BAAANQAECggICgAAAA==.',
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
