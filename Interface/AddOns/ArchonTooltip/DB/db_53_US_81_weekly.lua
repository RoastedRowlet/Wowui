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

local lookup = {'Rogue-Outlaw','Shaman-Restoration','Hunter-BeastMastery','Unknown-Unknown','Druid-Feral','DeathKnight-Blood','Druid-Balance','Paladin-Retribution','Paladin-Protection','Paladin-Holy','DeathKnight-Unholy','Priest-Holy','DemonHunter-Havoc','Evoker-Preservation','Priest-Shadow','Shaman-Enhancement','Druid-Guardian','DeathKnight-Frost','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Shaman-Elemental','Warrior-Protection','Rogue-Assassination','Warlock-Destruction','Priest-Discipline','Evoker-Augmentation','Evoker-Devastation','Warrior-Arms','Warrior-Fury','Warlock-Demonology','Hunter-Marksmanship','Mage-Frost','Mage-Arcane','Druid-Restoration','Hunter-Survival','Warlock-Affliction','DemonHunter-Devourer',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aakai:BAABNQAECoEkAAIBAAgKwhjtBQBoAgABAAgKwhjtBQBoAgAAAA==.Aarmorr:BAABNQAECoEZAAICAAcKOQpSjQA6AQACAAcKOQpSjQA6AQAAAA==.',
Ac='Acinianis:BAAANQADCggIDQAAAA==.',
Ad='Adinna:BAAANQADCgYIBgAAAA==.Adiro:BAAANQADCgQIBAAAAA==.Adsdad:BAAANQAECgIIAgAAAA==.',
Ae='Aedelas:BAAANQADCggIDgAAAA==.',
Ai='Aimeeiove:BAAANQAECgMIAwAAAA==.',
Ak='Akarag:BAAANQADCgcIBwAAAA==.',
Al='Alcarza:BAAANQADCgcIBwAAAA==.Alchon:BAABNQAECoEhAAIDAAgK0Rp/PwCIAgADAAgK0Rp/PwCIAgAAAA==.Alicalsastre:BAAANQAECgcJDwAAAA==.Alista:BAAANQABCgIIAgAAAA==.Allykat:BAAANQAECggIDwAAAA==.Alunathsong:BAAANQAECgEIAQAAAA==.Alvagíngras:BAAANQAECgQIBAAAAA==.',
Am='Amaith:BAAANQAECgQJCgAAAA==.Amantillado:BAAANQAECgEIAwABNQAECgYIDwAEAAAAAA==.Amata:BAAANQAECgIIAwAAAA==.Amblance:BAAANQADCggICAAAAA==.Amelianne:BAAANQAECgEIAQAAAA==.Ammastary:BAAANQAECgIIAwAAAA==.',
An='Andrea:BAABNQAECoEYAAIFAAYKwxLIFAB2AQAFAAYKwxLIFAB2AQAAAA==.Angelec:BAAANQADCgYIDAAAAA==.Anthria:BAAANQADCgQIBAAAAA==.Anysra:BAAANQADCgYJBgAAAA==.',
Ap='Apöllo:BAAANQAECgYIEwAAAA==.',
Aq='Aqules:BAAANQADCggICwAAAA==.',
Ar='Arcapeligo:BAAANQADCggIDwAAAA==.Archonsfury:BAAANQADCgcIBwAAAA==.Ardagg:BAAANQABCgYICQAAAA==.Arilyn:BAAANQADCgQIBAAAAA==.Arin:BAAANQAECgcIEgAAAA==.',
As='Ashentris:BAAANQAECgEIAQAAAA==.Asnew:BAABNQAECoEXAAIGAAkK0gfvWABtAQAGAAkK0gfvWABtAQAAAA==.Asura:BAAANQAECgYICAAAAA==.',
At='Athelstan:BAAANQAECgUIDgAAAA==.',
Au='Aumaril:BAAANQADCggICAAAAA==.Aumaryl:BAAANQAECggIEwAAAA==.Auralynn:BAAANQAECgUIDAAAAA==.Auroriana:BAAANQADCgQIBQAAAA==.',
Av='Averus:BAABNQAECoEaAAIHAAcK5QckWwA8AQAHAAcK5QckWwA8AQAAAA==.',
Az='Azariel:BAABNQAECoEgAAMIAAgKeBLEfAAAAgAIAAgKeBLEfAAAAgAJAAEKbBDqZwAoAAAAAA==.Azatre:BAAANQADCgIIAgAAAA==.Azuriah:BAABNQAECoEZAAIJAAcK9RxNFwAXAgAJAAcK9RxNFwAXAgAAAA==.',
Ba='Baane:BAAANQAECgIIAwABNQAECgMIBgAEAAAAAA==.Babnik:BAEANQAECgYICwAAAA==.Balderdashe:BAAANQADCggICAAAAA==.',
Be='Bealzibub:BAAANQABCgIIAgAAAA==.Bedhead:BAAANQAECgUIEAAAAA==.Belaim:BAAANQABCgIIAgAAAA==.Belovis:BAABNQAECoEjAAIIAAkKayPxFABhAwAIAAkKayPxFABhAwAAAA==.Betsea:BAAANQADCgcIBwABNQAECgcIIwAKAF8XAA==.',
Bi='Bidock:BAAANQAECgQJBAAAAA==.Bidoof:BAAANQAECgcIDwAAAA==.Bigocritties:BAAANQABCgMIAgAAAA==.Bitemarks:BAAANQADCggJFQAAAA==.Bix:BAAANQAECgYIEQAAAA==.',
Bl='Blackcoat:BAAANQADCgUIBQAAAA==.Blokmor:BAAANQAECgQIDgAAAA==.',
Bo='Boggrog:BAAANQAECgMIBgAAAA==.Bonepicklucy:BAAANQADCgUICQAAAA==.Boneybob:BAAANQABCgQJCAAAAA==.Boras:BAAANQAECgQIBgAAAA==.Bordeaux:BAAANQAECgIIAgABNQAECgQICwAEAAAAAA==.Bosshog:BAAANQAECgYIEAAAAA==.',
Br='Brabanzio:BAAANQAECgUIDgABNQAECggIIQACAHYbAA==.Breadfriend:BAAANQADCggICAAAAA==.Brightnshiny:BAAANQABCgIIAgAAAA==.Broseidon:BAAANQAECgIIAwAAAA==.Brotato:BAAANQABCgcICwABNQAECgIIAgAEAAAAAA==.Brotatochip:BAAANQAECgIIAgAAAA==.Broxxer:BAAANQADCgYIBgAAAA==.Brycke:BAAANQADCggIFwAAAA==.',
Bu='Buffsalot:BAAANQAECgYICAAAAA==.Burningblunt:BAAANQADCggIEwAAAA==.Buttons:BAAANQADCgcJBwAAAA==.',
Ca='Calav:BAAANQADCgYIBwAAAA==.Castle:BAAANQAECgMIBgAAAA==.Catsinhats:BAAANQADCggICgABNQAECggIKAALAL0YAA==.Catzinhatz:BAAANQADCgUIBQABNQAECggIKAALAL0YAA==.',
Ce='Cecelya:BAABNQAECoEZAAIMAAcKOBdWUwD9AQAMAAcKOBdWUwD9AQAAAA==.',
Ch='Chablis:BAAANQAECgEIAQAAAA==.Cherlia:BAAANQADCgcIDgABNQAECggIHwANAAAcAA==.Chivactdl:BAAANQADCgYJCgABNQAECgcIHAACAOoSAA==.Chosenn:BAAANQAECgUICgAAAA==.Chotek:BAAANQAECgMIAwAAAA==.Chunknoriss:BAAANQAECgQIBgABNQAECgcIHAACAOoSAA==.',
Ci='Cilarnen:BAAANQAECgIIBAAAAA==.',
Cl='Clure:BAABNQAECoEhAAIKAAgKwCI9EgAtAwAKAAgKwCI9EgAtAwABNQAECggIIwAOAO8ZAA==.Clurethyr:BAABNQAECoEjAAIOAAgK7xkWEwBnAgAOAAgK7xkWEwBnAgAAAA==.',
Co='Conchobhar:BAAANQAECgQIBQAAAA==.Coppertan:BAAANQADCgcIFwAAAA==.Cornaddict:BAACNQAFFIEKAAIMAAUKaw15DgCDAQAMAAUKaw15DgCDAQA1AAQKgScAAwwACQo2Flg8AFQCAAwACApHGFg8AFQCAA8ACAoGG3scADwCAAAA.Corrosion:BAABNQAECoEcAAIQAAgKcR/mBwDsAgAQAAgKcR/mBwDsAgAAAA==.',
Cr='Crommash:BAAANQAECggICQAAAA==.Cromshade:BAAANQABCgYIBgAAAA==.Cromsteel:BAAANQADCgQIBAAAAA==.Cromsyth:BAAANQADCgYIBgAAAA==.Crono:BAAANQADCgYICQAAAA==.Crunchynuget:BAAANQAECgQIDwABNQAECgkJKAAIAAkfAA==.Crylessplz:BAAANQAECgIIAgABNQAECggIHAAJAB0cAA==.',
Ct='Cthuwu:BAAANQAECgUIBgABNQAECgkJJwADAA4fAA==.',
Cv='Cvhamster:BAAANQADCgcIBwAAAA==.',
Cy='Cy:BAAANQADCggJCAAAAA==.Cybeast:BAABNQAECoEcAAMFAAgKlBm2CQBzAgAFAAgKlBm2CQBzAgARAAMKghQWNgCrAAAAAA==.Cynortas:BAAANQADCgUIBQAAAA==.',
Da='Daciana:BAAANQAECgUIDgAAAA==.Dados:BAAANQAECgUIBQAAAA==.Dahleigh:BAAANQADCgYIBAAAAA==.Dakanar:BAAANQADCggIDAAAAA==.Darkessence:BAAANQADCgEIAQAAAA==.Darkfox:BAAANQADCgYIBgAAAA==.Darkhazel:BAAANQAECgQIBQAAAA==.Darkkromdor:BAABNQAECoEeAAIIAAgKXx2KTQCEAgAIAAgKXx2KTQCEAgAAAA==.Darloct:BAAANQADCgEIAgAAAA==.',
De='Deadelff:BAABNQAECoEdAAINAAgK4BVbKwAcAgANAAgK4BVbKwAcAgAAAA==.Deathcat:BAABNQAECoEoAAMLAAgKvRizQQDvAQALAAgKvRizQQDvAQASAAYKfQrjTwAoAQAAAA==.Deathkiss:BAAANQAECgMJBAAAAA==.Deathrixx:BAAANQADCggICAAAAA==.Deathshadowx:BAAANQAECgIIAwAAAA==.Decayy:BAAANQAECgcIEgABNQAECgYIDgAEAAAAAA==.Dedbull:BAAANQADCggJIQAAAA==.Demodius:BAAANQADCggICAAAAA==.Demourdenite:BAAANQADCgYJFQAAAA==.Des:BAAANQABCgIIAgAAAA==.',
Di='Discharged:BAAANQADCgYICAABNQAECgYIDwAEAAAAAA==.',
Dk='Dkpheonix:BAAANQAECgYIEwAAAA==.',
Do='Dolemite:BAAANQAECgQIDAAAAA==.Donalbain:BAABNQAECoEhAAICAAgKdhsEMwBuAgACAAgKdhsEMwBuAgAAAA==.Donninban:BAAANQAECgUIBwAAAA==.Doodoobutter:BAAANQAECgIIAgABNQAECggIIgATAJsZAA==.',
Dr='Draganpriest:BAAANQAECgEIAQAAAA==.Dremar:BAAANQAECgEIAQAAAA==.Drizzeh:BAAANQABCggIDgAAAA==.',
Du='Duarcán:BAAANQADCgEIAQAAAA==.Dunshotya:BAAANQADCggICQAAAA==.',
Eb='Ebolla:BAAANQADCgcIBwAAAA==.',
Ec='Eclipsy:BAAANQADCgIIAgAAAA==.',
Eg='Eggroll:BAAANQADCgQIBAAAAA==.',
El='Elexander:BAAANQAECgEIAQAAAA==.Elifar:BAAANQADCggIFwAAAA==.Eluneatic:BAAANQADCgQIBAAAAA==.Elyssaris:BAABNQAECoEfAAIGAAgK7xZ5MQAsAgAGAAgK7xZ5MQAsAgAAAA==.Elzulkin:BAAANQADCgQIBAAAAA==.',
Em='Emmdeath:BAAANQADCgYIBgAAAA==.Emmils:BAAANQAECgYIEwAAAA==.Emìly:BAABNQAECoEaAAMUAAcKYxb1FwDOAQAUAAcKYxb1FwDOAQAVAAYKrBR6LgBwAQAAAA==.',
En='Entaria:BAAANQAECgIIAwAAAA==.',
Ep='Ephria:BAABNQAECoElAAMCAAgKuSQgDABLAwACAAgKuSQgDABLAwAWAAEKUwYwKwEnAAAAAA==.Episkey:BAAANQAECgMIBgAAAA==.',
Er='Eroversion:BAAANQAECgUICgABNQAECggILwAXALcYAA==.Eroward:BAABNQAECoEvAAIXAAgKtxiHDgAYAgAXAAgKtxiHDgAYAgAAAA==.',
Es='Esmay:BAAANQAECgYIDQAAAA==.',
Et='Ethren:BAABNQAECoEaAAIYAAcKkRHqNADKAQAYAAcKkRHqNADKAQAAAA==.',
Eu='Eudoxos:BAAANQAECgEIAQAAAA==.Euroecka:BAAANQADCgYIBQAAAA==.',
Ev='Evelynstar:BAAANQADCgMJAwAAAA==.',
Ez='Ezikarridge:BAAANQADCggIDgAAAA==.',
Fa='Falcone:BAAANQAECgEIAQAAAA==.',
Fe='Felbolter:BAABNQAECoEaAAIZAAcKwhzlCABjAgAZAAcKwhzlCABjAgAAAA==.Fetide:BAAANQADCgIIAgAAAA==.',
Fi='Fiddlefaddle:BAAANQABCgMIAwAAAA==.Filgulfin:BAABNQAECoEdAAIDAAgKXxvaPgCKAgADAAgKXxvaPgCKAgAAAA==.Finkate:BAAANQAECgcIBwAAAA==.Firebringer:BAAANQAECgYIBwAAAA==.Fistmegently:BAAANQADCgYIBgAAAA==.',
Fl='Flamehunter:BAAANQAECgEIAQAAAA==.Flo:BAABNQAECoElAAMPAAgKpBM6IQAHAgAPAAgKpBM6IQAHAgAaAAYKrguNDgAuAQAAAA==.Floki:BAAANQAECgUIDgAAAA==.Flokin:BAAANQADCggICAAAAA==.Flowing:BAABNQAECoEfAAQbAAcKlxbPCADVAQAbAAcKlxbPCADVAQAOAAYKIwf1LQANAQAcAAQK2wQtLACcAAAAAA==.',
Fo='Foods:BAABNQAECoElAAQdAAgKPAt3nACrAQAdAAgKbAl3nACrAQAXAAUK7wmtJwDPAAAeAAEKnA+xKQBEAAAAAA==.',
Fr='Fripouille:BAAANQADCgQIBwAAAA==.',
['Fæ']='Fæ:BAAANQADCgcIBwAAAA==.',
Ga='Gaboo:BAAANQAECgUIDgAAAA==.',
Gh='Ghostinhale:BAAANQADCgQIBAAAAA==.',
Gi='Gilorion:BAAANQAECgYIEAAAAA==.',
Gl='Glasgoww:BAAANQADCgUIBQABNQAECggIIQACAHYbAA==.Gler:BAAANQADCgQJBQAAAA==.',
Gn='Gnibat:BAAANQAECgIIAwAAAA==.',
Go='Goburina:BAABNQAECoEgAAICAAkKWRGwUAD2AQACAAkKWRGwUAD2AQAAAA==.Goldhawk:BAAANQABCgIIAgAAAA==.',
Gu='Gulpron:BAAANQABCgMJBAAAAA==.',
['Gí']='Gímlí:BAABNQAECoEaAAIDAAgKnRrGPgCKAgADAAgKnRrGPgCKAgAAAA==.',
Ha='Haidyn:BAAANQADCgMJAwAAAA==.Halcyndraag:BAABNQAECoEaAAQcAAcKzw44HwBEAQAcAAYKsg04HwBEAQAOAAUKzgRGNgDEAAAbAAIKKBDGGgBsAAAAAA==.Handofcope:BAAANQAECgYIDwAAAA==.Hartu:BAABNQAECoEiAAIXAAgKBxdEDgAcAgAXAAgKBxdEDgAcAgAAAA==.',
He='Hemogobblin:BAAANQADCgQIBAAAAA==.Herbalmist:BAAANQAECgIIAwAAAA==.',
Hi='Hircine:BAAANQADCggIDAAAAA==.',
Ho='Holysea:BAAANQAECgIIAgABNQAECgcIIwAKAF8XAA==.Honk:BAAANQADCggIEQAAAA==.',
Im='Imwithfloki:BAAANQAECgUIDgAAAA==.',
Ir='Ironmark:BAAANQAECgIIAgAAAA==.Irys:BAAANQADCgcIDQAAAA==.',
Is='Isam:BAAANQAECgUIBQAAAA==.Isamidor:BAABNQAECoEmAAIDAAkKwCXQBQCnAwADAAkKwCXQBQCnAwAAAA==.Ismokeu:BAABNQAECoEcAAIMAAgKWBmHTAAXAgAMAAgKWBmHTAAXAgAAAA==.Ismyn:BAAANQAECgIIAgAAAA==.Istran:BAAANQADCgYJCQAAAA==.',
Iv='Ivrys:BAAANQAECgcICwAAAA==.',
Iw='Iwillbethere:BAAANQABCgQIBAAAAA==.',
Ja='Jackoneal:BAAANQAECgYICwAAAA==.Jalidelo:BAABNQAECoEhAAIMAAgKHRXLTQASAgAMAAgKHRXLTQASAgAAAA==.Jalidemon:BAAANQADCggIEAAAAA==.Jalyyn:BAAANQADCgEIAQAAAA==.',
Ji='Jingild:BAAANQADCgYIBgAAAA==.',
Jo='Joeyfoxone:BAAANQADCgQIBAAAAA==.Johan:BAABNQAECoEaAAIfAAgK0hsuRwBfAgAfAAgK0hsuRwBfAgAAAA==.Jokersfists:BAAANQADCggIHwABNQAECgQICgAEAAAAAA==.Jokersmage:BAAANQAECgQICgAAAA==.Joraflheim:BAAANQABCgIIAgAAAA==.Joranbragi:BAAANQAECgQIBgAAAA==.Jordanjr:BAABNQAECoEkAAMgAAkKMBfFKgDSAQADAAcKbhfqbAAMAgAgAAgK5g/FKgDSAQAAAA==.Josunlee:BAAANQADCggIDwAAAA==.Jotoonice:BAABNQAECoEbAAMhAAcK5BAkFwAdAQAiAAYKSQfwKgEfAQAhAAQKqRUkFwAdAQAAAA==.',
Jt='Jtoothaordan:BAACNQAFFIEHAAMgAAMKgRBFEwDVAAAgAAMKtw5FEwDVAAADAAEKFw7dLgBNAAA1AAQKgSgAAyAACQqSFkofADgCACAACQqZE0ofADgCAAMAAgpsIX8HAa8AAAAA.',
Ju='Juicyfruit:BAAANQABCgYICAAAAA==.Jules:BAAANQADCgcIBwAAAA==.',
Ka='Kaana:BAABNQAECoEaAAIDAAcKfRBwgQDaAQADAAcKfRBwgQDaAQAAAA==.Kaedina:BAAANQAECgQIBwABNQAECgkJJAAgADAXAA==.Kallista:BAAANQADCgYIDwAAAA==.Karvel:BAABNQAECoEdAAIGAAgK/BqHJwBoAgAGAAgK/BqHJwBoAgAAAA==.Kaychow:BAAANQAECgQICAABNQAECgcIEwAEAAAAAA==.Kaydullz:BAAANQAECgYICAAAAA==.',
Kc='Kchowchow:BAAANQAECgEIAQABNQAECgcIEwAEAAAAAA==.',
Ke='Kelonaar:BAACNQAFFIEFAAMWAAMKqw10FQDrAAAWAAMKqw10FQDrAAACAAIKuAMZIAB7AAA1AAQKgSEAAxYACQqEHiEfAPQCABYACQqEHiEfAPQCAAIAAgqxHUvNAKQAAAAA.',
Kh='Kharys:BAAANQADCggIGgAAAA==.',
Ki='Killermoomoo:BAAANQAECgIIAwAAAA==.',
Kl='Kloverr:BAAANQAECgYIEAAAAA==.',
Ko='Kombatkarl:BAAANQADCgMIAwAAAA==.Koranthia:BAAANQADCgUIBQAAAA==.',
Kr='Kretaios:BAAANQADCgEIAQAAAA==.Kromir:BAAANQADCggICAAAAA==.Kronixrage:BAAANQAECgMIBQAAAA==.Krooler:BAAANQAECgMJBAAAAA==.Krum:BAAANQAECgYIEQAAAA==.',
La='Lanval:BAABNQAECoEiAAIIAAgKaBvQUQB3AgAIAAgKaBvQUQB3AgAAAA==.Latinlover:BAAANQAECgIIAgAAAA==.Laurian:BAAANQABCgMIAwAAAA==.',
Le='Leaky:BAAANQADCgQIBQAAAA==.Leetah:BAABNQAECoEnAAIRAAgKeBybCgCMAgARAAgKeBybCgCMAgAAAA==.Leftblank:BAAANQAECgEIAgAAAA==.',
Li='Lich:BAAANQAECgQIBAAAAA==.Lighthugger:BAABNQAECoEiAAIIAAgKqRnIYABLAgAIAAgKqRnIYABLAgAAAA==.Lilyoptra:BAAANQAECgIIBAABNQAECgIIBAAEAAAAAA==.Liqmycrits:BAAANQADCggIDgAAAA==.Lishalzin:BAAANQAECgEIAQABNQAECgUICwAEAAAAAA==.Liszt:BAAANQADCgMIAwAAAA==.Livana:BAAANQADCggIEAABNQAECgYIDwAEAAAAAA==.',
Lo='Lockpockets:BAAANQAECgMIAwAAAA==.Loriane:BAAANQAECgIIAgABNQADCgUJCQAEAAAAAA==.Lorianth:BAABNQAECoEjAAIgAAgKyxJoJAAJAgAgAAgKyxJoJAAJAgAAAA==.Lotharbacco:BAAANQADCggICAAAAA==.Lovegood:BAAANQADCgUIBQAAAA==.',
Lu='Lucifér:BAAANQABCggICQAAAA==.',
Ly='Lychi:BAAANQAECgIIAwAAAA==.Lylora:BAABNQAECoEyAAIjAAkKrSUDAQDIAwAjAAkKrSUDAQDIAwAAAA==.',
['Lê']='Lêmonaide:BAABNQAECoEZAAIMAAcKQBVLZADAAQAMAAcKQBVLZADAAQAAAA==.',
Ma='Madclaws:BAABNQAECoElAAMHAAgKYxxQIwCWAgAHAAgKVxtQIwCWAgARAAYKQhvHFwCvAQAAAA==.Madman:BAAANQAECgIIBgAAAA==.Magekaestey:BAAANQADCggIDwABNQAECggIHQAdAMILAA==.Malala:BAAANQADCgQICgABNQAECggIKQAMAKsWAA==.Malyndra:BAAANQAECgUICAAAAA==.Marshy:BAAANQAFFAEIAQAAAA==.Marvolt:BAABNQAECoEeAAIfAAgKJwpjhACuAQAfAAgKJwpjhACuAQAAAA==.',
Me='Mesmash:BAAANQAECgYIDwAAAA==.Metadk:BAAANQAECgYIDwAAAA==.Metamasters:BAAANQADCgYIDAABNQAECgYIDwAEAAAAAA==.',
Mi='Mialtaa:BAAANQAECgIIAwAAAA==.Micah:BAAANQAECgIJAgAAAA==.Midgiit:BAAANQADCgYICwABNQAECggIHgAMAP4ZAA==.Miniborg:BAAANQADCggIFwABNQAECgkJKAAIAAkfAA==.Minidude:BAAANQADCgYIBwAAAA==.Misfire:BAAANQADCgEIAQAAAA==.Mistycrusade:BAAANQAECgIIAgAAAA==.Mizzen:BAAANQAECgcIEwABNQAFFAMIBgAPAOsLAA==.',
Mo='Moejojojo:BAAANQAECgUIDgAAAA==.Moofasaha:BAAANQAECgUIEAAAAA==.Morog:BAAANQAECgcIDwAAAA==.Morragan:BAAANQADCggIGQAAAA==.',
Mu='Mulvan:BAAANQAECgUIDAAAAA==.',
['Mâ']='Mârshy:BAAANQADCgEIAQABNQAFFAEIAQAEAAAAAA==.',
['Mã']='Mãrshy:BAAANQAECgYICwABNQAFFAEIAQAEAAAAAA==.',
['Mä']='Märshy:BAAANQAECgIIAgABNQAFFAEIAQAEAAAAAA==.',
Na='Nabû:BAAANQADCgQIBAAAAA==.Naler:BAAANQAECgUICAAAAA==.Nanarus:BAABNQAECoEpAAIMAAgKqxYaTwANAgAMAAgKqxYaTwANAgAAAA==.Nashalie:BAABNQAECoEgAAMfAAcKDiBkQAB1AgAfAAcKDiBkQAB1AgAZAAIKNRJXUQB/AAAAAA==.',
Ne='Nedyav:BAAANQADCgIIAgAAAA==.Nefele:BAAANQAECgUIDAAAAA==.Nexbasia:BAABNQAECoEaAAIFAAcKShD0EQCsAQAFAAcKShD0EQCsAQAAAA==.',
Ni='Nickyboy:BAAANQAECgIIAQAAAA==.Nightevel:BAAANQADCgYICQAAAA==.Nihimetal:BAAANQADCgcIEwAAAA==.',
No='Noctum:BAAANQAECgIIAgAAAA==.Nomad:BAAANQADCggIGQAAAA==.Norinisa:BAAANQABCgcIBwAAAA==.',
Ny='Nymmycup:BAAANQAECgEIAQAAAA==.',
Oc='Octt:BAAANQAECgYICgAAAA==.',
Ol='Oldcannabis:BAAANQAECgcICQAAAA==.',
Om='Ominis:BAAANQADCgQJBAAAAA==.',
Oo='Oomaw:BAAANQADCggICwAAAA==.',
Or='Ormbar:BAAANQADCgEIAQAAAA==.Ornimus:BAAANQAECgMICAAAAA==.Ortian:BAAANQAECgEIAQAAAA==.',
Os='Osrs:BAABNQAECoEcAAIPAAkK5CKzDQD6AgAPAAkK5CKzDQD6AgAAAA==.',
Oz='Ozo:BAAANQAECgQICQAAAA==.',
Pa='Paiva:BAAANQAECgIIAgAAAA==.Palandor:BAAANQADCgYIBgAAAA==.Pallydoof:BAAANQADCgYIBgAAAA==.Pallyscorned:BAABNQAECoEgAAIJAAgKvhcsGAANAgAJAAgKvhcsGAANAgAAAA==.Pamgetem:BAAANQAECgQIBQABNQAECgcIDQAEAAAAAA==.Pampas:BAAANQAECgEIAQAAAA==.Panduh:BAABNQAECoErAAMVAAkKECEoCAA5AwAVAAkKxSAoCAA5AwATAAcKWh+fDAAXAgAAAA==.',
Ph='Phenixy:BAAANQAECgIIAwAAAA==.Phoebell:BAAANQAECgIIAwAAAA==.Phoinix:BAAANQADCgYIBwAAAA==.',
Pi='Pinkducky:BAAANQADCgYIDgAAAA==.',
Pl='Plen:BAAANQAECgIIAgABNQAECggIHgAMAP4ZAA==.',
Po='Ponyo:BAABNQAECoEfAAIMAAgKXSMuFAAXAwAMAAgKXSMuFAAXAwAAAA==.Poppyseed:BAAANQAECgIIAgAAAA==.Poquads:BAAANQADCggIDAAAAA==.',
Pv='Pve:BAAANQADCgIIAgAAAA==.',
Qu='Quiewt:BAABNQAECoEZAAMgAAcKsg8eMQCaAQAgAAcK8Q4eMQCaAQADAAIKDQ2HFgF+AAAAAA==.',
Ra='Raddra:BAAANQADCgUICgAAAA==.Raddrah:BAAANQABCgUICAAAAA==.Raddrap:BAAANQADCgUIBgAAAA==.Radra:BAAANQAECgMIDQAAAA==.Raeku:BAABNQAECoEhAAIkAAgKth99AgD2AgAkAAgKth99AgD2AgAAAA==.Raharuto:BAAANQADCggICAAAAA==.Raja:BAAANQAECgMJBQAAAA==.Rav:BAAANQADCgIIAgAAAA==.Razzlor:BAAANQADCgQIBAAAAA==.',
Re='Recoill:BAABNQAECoEZAAIMAAgK0BfeOwBWAgAMAAgK0BfeOwBWAgAAAA==.Reducto:BAAANQADCgYICwAAAA==.Retribution:BAABNQAECoEaAAIIAAgKCw4OlADHAQAIAAgKCw4OlADHAQAAAA==.',
Ro='Robomurph:BAAANQADCgQIBAAAAA==.Rolas:BAAANQAECgEIAQAAAA==.Ronfax:BAACNQAFFIELAAICAAQK4hqvDABWAQACAAQK4hqvDABWAQA1AAQKgScAAgIACQp9IZwOADgDAAIACQp9IZwOADgDAAAA.Roony:BAAANQADCgIIAQAAAA==.Rooss:BAAANQAECgUIBwAAAA==.Rowdyredneck:BAAANQADCgYIBwABNQAECgYIDwAEAAAAAA==.',
Ru='Rul:BAAANQADCgIIAgABNQAECgkJKwAVABAhAA==.',
Ry='Ryllae:BAAANQADCgIIAgABNQAECggIHwANAAAcAA==.Ryuu:BAAANQAECgIIAwAAAA==.Ryuusythe:BAAANQADCggICQAAAA==.',
['Rì']='Rììdìì:BAABNQAECoEXAAMlAAgKrAizFgC5AAAfAAgKSQhhkQCMAQAlAAQKGwazFgC5AAABNQAECggIGgADAJ0aAA==.',
['Rï']='Rïchardgear:BAAANQADCggIDAABNQAECggIGgADAJ0aAA==.',
Sa='Saint:BAAANQAECgYIEAAAAA==.Salopard:BAAANQADCgQIBAAAAA==.Sarinae:BAAANQAECgYIEgAAAA==.Sarmuc:BAABNQAECoEmAAIQAAkKThNhDwBZAgAQAAkKThNhDwBZAgAAAA==.Saryda:BAAANQAECgQICwAAAA==.Sauda:BAAANQADCgcIDAAAAA==.',
Sc='Schuybusta:BAAANQAECgEIAQAAAA==.Scubagal:BAAANQAECgIIAwAAAA==.',
Se='Secundinius:BAAANQADCgMIAwAAAA==.Selûne:BAAANQABCgIIAgAAAA==.Sensu:BAAANQAECgMIBgAAAA==.Serrest:BAAANQAECgUICgAAAA==.Seä:BAABNQAECoEjAAIKAAcKXxfLTAAXAgAKAAcKXxfLTAAXAgAAAA==.',
Sh='Shacktown:BAAANQABCgYICQAAAA==.Shadowdoh:BAAANQAECgIIAgABNQAECgUICAAEAAAAAA==.Shapzan:BAAANQAECgMIBQAAAA==.Sharks:BAAANQAECgQJBgAAAA==.Shivant:BAABNQAECoEcAAICAAcK6hKvbQCUAQACAAcK6hKvbQCUAQAAAA==.',
Si='Silendreas:BAAANQADCgUIBQAAAA==.',
Sl='Sloth:BAABNQAECoEbAAIGAAcKPCIeHAC2AgAGAAcKPCIeHAC2AgAAAA==.',
Sm='Smalltwngirl:BAAANQAECgUICgABNQAFFAQICwACAOIaAA==.',
So='Solaspirus:BAAANQAECgUIBwAAAA==.Solinius:BAAANQADCggIGQAAAA==.Songbreeze:BAABNQAECoEeAAMMAAgK/hmLMACFAgAMAAgK/hmLMACFAgAPAAUK1wVPRwDYAAAAAA==.Sonofagun:BAAANQAECgQIBQAAAA==.',
Sp='Spectors:BAABNQAECoEeAAQlAAgKiAVeEgD7AAAfAAcKUgMmzQACAQAlAAUKYgZeEgD7AAAZAAEKwwGZfgAkAAAAAA==.Spideygirl:BAAANQAECgEIAQAAAA==.',
St='Stabon:BAAANQAECgIJBgAAAA==.Strykah:BAAANQADCgQIBAAAAA==.',
Su='Sugarmarks:BAAANQAECgIJAgAAAA==.',
Sw='Sweetstorm:BAAANQAECgUIDwAAAA==.',
Sy='Sydburns:BAAANQABCgYICAAAAA==.Sydley:BAAANQABCgQIBAAAAA==.',
Ta='Tagg:BAAANQADCggICAAAAA==.Taotao:BAAANQADCgYIBgAAAA==.Tarixx:BAAANQAECggIDAAAAA==.Tazanoth:BAABNQAECoEiAAQDAAcKCx+BSgBnAgADAAcKCx+BSgBnAgAgAAYKXwsDPwAqAQAkAAEKrRWLDwBWAAAAAA==.',
Te='Tekeela:BAAANQAECgQIBAABNQAECgkJJwADAA4fAA==.Tekeelà:BAABNQAECoEnAAIDAAkKDh9OGwASAwADAAkKDh9OGwASAwAAAA==.',
Th='Thalarus:BAAANQADCgEIAQABNQADCgcIBwAEAAAAAA==.Thalion:BAAANQAECgEIAQAAAA==.Theenna:BAAANQADCgEIAQAAAA==.Theroux:BAAANQADCggICAAAAA==.Thess:BAAANQADCgYIBgAAAA==.Thianna:BAAANQAECgUIDgAAAA==.Thobu:BAAANQAECgMIAwAAAA==.Thornscale:BAABNQAECoEbAAMbAAgKdwueDgAtAQAcAAgK3gYlGwB7AQAbAAYKmQueDgAtAQAAAA==.',
Ti='Tigolcrittys:BAAANQADCggIEQABNQAECggIGgADAJ0aAA==.',
To='Tokkem:BAAANQADCgEIAQAAAA==.Tomzombe:BAAANQADCgYICgAAAA==.Tonguepunch:BAAANQAECgUICwAAAA==.Totem:BAAANQAECgEIAQAAAA==.Tovê:BAAANQADCgEIAQAAAA==.',
Tr='Traumajazz:BAAANQABCgIIAgAAAA==.Traveler:BAAANQADCgEIAQAAAA==.Trenko:BAAANQADCgMIAwAAAA==.Troloq:BAABNQAECoEdAAMZAAgKux/XAwDrAgAZAAgKux/XAwDrAgAlAAMKlA+yFgC5AAAAAA==.',
Tu='Turger:BAAANQADCggIDQABNQAECgUIEAAEAAAAAA==.',
Va='Vaeluptuous:BAAANQAECgQICQAAAA==.Vahlorraa:BAAANQADCgMJAwAAAA==.Vaimei:BAABNQAECoEeAAMZAAgK6SARBwCMAgAZAAcKSB8RBwCMAgAfAAYKgxtcawD0AQAAAA==.Vallyna:BAAANQADCgYIBgAAAA==.Vapor:BAAANQAECgUIBgAAAA==.Varaine:BAAANQADCgYICwABNQAECgUICwAEAAAAAA==.',
Ve='Veebs:BAAANQAECgUJBQAAAA==.Vento:BAAANQADCggIDgAAAA==.Verité:BAAANQAECgYIDwAAAA==.',
Vi='Virauca:BAABNQAECoEaAAImAAgKzwuvKgDMAQAmAAgKzwuvKgDMAQAAAA==.Vizon:BAAANQADCgcIFwAAAA==.',
Vo='Voices:BAAANQAECgYIEwAAAA==.Voltrix:BAAANQADCggIGwAAAA==.',
Vy='Vynesta:BAABNQAECoEfAAINAAgKABznHACNAgANAAgKABznHACNAgAAAA==.',
Wa='Wanagi:BAAANQAECgMIBAAAAA==.Wankz:BAAANQAECgUIDAAAAA==.Warkaestey:BAABNQAECoEdAAIdAAgKwgtSkgDHAQAdAAgKwgtSkgDHAQAAAA==.Warriorguyes:BAAANQAECgUIDAAAAA==.',
Wh='Whomper:BAAANQAECgEIAQAAAA==.',
Wi='Widowx:BAAANQAECgUIBwAAAA==.Windshrieker:BAAANQADCgYIBgAAAA==.Wintervalor:BAABNQAECoEYAAIGAAcK9xI6TgCcAQAGAAcK9xI6TgCcAQAAAA==.',
Wo='Womphunt:BAAANQAECgYIDQABNQAECgcIFQAMAIwaAA==.',
Wu='Wulyn:BAAANQAECgMIBgAAAA==.',
Wy='Wylla:BAAANQAECgQIDgAAAA==.',
Xa='Xalethra:BAAANQAECgQIBQAAAA==.',
Xe='Xenophobias:BAAANQADCgcIEQAAAA==.',
Xs='Xsuns:BAAANQAECgUIEAAAAA==.',
Yv='Yve:BAAANQAECgMIBQAAAA==.',
Za='Zabberz:BAAANQADCgQJBAAAAA==.Zaharian:BAAANQADCgYJBgAAAA==.Zalajin:BAAANQAECgIIAgAAAA==.Zarathiel:BAABNQAECoEVAAIdAAgK9QnEoACgAQAdAAgK9QnEoACgAQAAAA==.',
Ze='Zeddicus:BAAANQAECgYIEAAAAA==.',
Zi='Zivadaavid:BAAANQADCgEIAQAAAA==.',
Zo='Zoidz:BAAANQAECgQIBAAAAA==.Zoriadon:BAAANQADCgcIDAAAAA==.',
Zz='Zzilladinzz:BAAANQAECggICAAAAA==.',
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
