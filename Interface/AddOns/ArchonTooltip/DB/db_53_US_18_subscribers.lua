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

local lookup = {'Unknown-Unknown','Warrior-Arms','Rogue-Outlaw','Priest-Shadow','Paladin-Holy','Warrior-Protection','Mage-Arcane','Druid-Balance','Druid-Feral','Warlock-Demonology','Warlock-Destruction',}
local provider = {region='US',realm='Area52',name='US',type='subscribers',zone=53,date='2026-09-01',data={Aa='Aangst:BAEANQAECggICwAAAA==.',
Ab='Abc:BAEANQAECgcIDQAAAA==.',
Ac='Accentlight:BAEANQAFFAEIAQABNQABCgQIAwABAAAAAA==.Acurze:BAEANQAECgYICwAAAA==.',
Ad='Adamddruid:BAEANQADCggICAABNQAECggIDgABAAAAAA==.Adamdlock:BAEANQAECggIDgAAAA==.Adamdmage:BAEANQADCgEIAQABNQAECggIDgABAAAAAA==.Adazz:BAEANQAECgYICgAAAA==.',
Ag='Aggronawt:BAEANQAFFAEIAQABNQABCgIIAgABAAAAAA==.Agriote:BAEANQADCgYIDAAAAA==.',
Al='Alanaardvark:BAEANQADCgcIBwABNQAECggIDwABAAAAAA==.Allthefist:BAEANQADCgQIBAABNQAECgcICgABAAAAAA==.Alltheprocs:BAEANQAECgcICgAAAA==.',
Am='Amillicyrus:BAEANQADCggIEAAAAA==.',
An='Andraemos:BAEANQAECgYIBgABNQAECggIDAABAAAAAA==.',
Ap='Apook:BAEBNQAFFIEJAAICAAYJ4xQlAABDAgaODQAAAgAgAHUNAAACAEsAfw0AAAEACgCpDQAAAgAXAFwNAAABAGQAMw0AAAEAUAACAAYJ4xQlAABDAgaODQAAAgAgAHUNAAACAEsAfw0AAAEACgCpDQAAAgAXAFwNAAABAGQAMw0AAAEAUAAAAA==.',
Ar='Arcangila:BAEANQAECgIIAgAAAA==.Arganox:BAEANQAECgUICQAAAA==.Arghrond:BAEANQAECgYICgAAAA==.Ariélle:BAEANQAECgcIDAAAAA==.',
At='Atticús:BAEANQAECgcIDQAAAA==.',
Au='Augbahal:BAEANQADCgUIBgABNQAECgQIBgABAAAAAA==.',
Aw='Awangawang:BAEANQADCgcIBwABNQAECggIDAADAFAiAA==.Awangawangaw:BAEBNQAECoEMAAIDAAgJUCJOAABbAwiODQAAAgBjAHUNAAACAGEAfw0AAAIAYwCpDQAAAgBjAFwNAAABAFkAXQ0AAAEAXABlDQAAAQBQAKQNAAABACwAAwAICVAiTgAAWwMIjg0AAAIAYwB1DQAAAgBhAH8NAAACAGMAqQ0AAAIAYwBcDQAAAQBZAF0NAAABAFwAZQ0AAAEAUACkDQAAAQAsAAAA.',
Az='Azorahai:BAEANQAFFAEIAQAAAA==.',
Ba='Babylonius:BAEANQAECgIIAgABNQAFFAEIAgABAAAAAA==.Badsyfy:BAEANQAECggIDgAAAA==.Bahaldk:BAEANQADCgEIAQABNQAECgQIBgABAAAAAA==.Baneoflegion:BAEANQADCggICAABNQAECgcICwABAAAAAA==.Banishes:BAEANQAECggIDwAAAA==.Barruimonk:BAEANQADCgcIDQABNQAFFAMIAwABAAAAAA==.',
Be='Beaneater:BAEANQAECgcICwAAAA==.Beetleslayr:BAEANQAECgYICgABNQAFFAUIBgAEAO0ZAA==.Benchd:BAEANQAECgEIAQABNQAFFAIIAgABAAAAAA==.Berbatof:BAEANQAFFAEIAQAAAA==.Bestpinoza:BAEANQAECgcICwAAAA==.',
Bi='Bigtoasties:BAEANQADCgYIBgABNQADCgIIAgABAAAAAA==.',
Bo='Boostedbilly:BAEANQAECggIAQABNQAECggIBgABAAAAAA==.',
Br='Breezypriest:BAEANQAECgMIBAAAAA==.Brewsleesin:BAEANQAECgEIAQABNQAECggIDgABAAAAAA==.Bringit:BAEANQADCggIEAABNQAECgQIBgABAAAAAA==.Brynnee:BAEANQADCgQIBAAAAA==.',
Ca='Cadhir:BAEANQAECgEIAQABNQAECggIDgABAAAAAA==.Caeriss:BAEANQAECggIDgAAAA==.Calemi:BAEANQAFFAEIAQAAAA==.Carthïl:BAEANQAECgMIAwAAAA==.Casandrá:BAEANQAECggIDgAAAA==.Cassatie:BAEANQAECgMIAwABNQAFFAIIAwABAAAAAA==.Castogar:BAEANQAECgYICQAAAA==.Cavechick:BAEANQAECgcIDQAAAQ==.',
Ce='Cendariel:BAEANQAECgQIBAAAAA==.Ceryal:BAEANQAECgEIAQAAAA==.Cevià:BAEANQAECgYICQAAAA==.',
Ch='Chaningtotam:BAEANQAECgQICAABNQAECggIDgABAAAAAA==.Chitoo:BAEANQADCgUIBQAAAA==.',
Co='Columpia:BAEANQADCggIEAABNQAECgcIDQABAAAAAA==.Columpio:BAEANQAECgcIDQAAAA==.Consecwation:BAEANQAECgYICQAAAA==.Coraloralyn:BAEANQAECgQICgAAAA==.Coraspin:BAEANQADCgUICQABNQAECgQICgABAAAAAA==.',
Cr='Crimsonne:BAEANQADCgYIBgABNQADCggIDgABAAAAAA==.',
Cu='Cugino:BAEANQAFFAEIAQAAAA==.',
Da='Daisukidesu:BAEANQAECgYICgABNQAFFAIIAgABAAAAAA==.Danblessyou:BAEANQAECgUIBwAAAA==.Dangolcouch:BAEANQAECgUICAAAAA==.Darioly:BAEANQADCgYICQAAAA==.',
De='Deadpaull:BAEANQADCgEIAQABNQAECgIIAgABAAAAAA==.Deathsnite:BAEANQAECgEIAgAAAA==.Deletegaming:BAEANQAECgQIBAABNQAECgQIBAABAAAAAA==.Deletemyself:BAEANQAECgQIBAAAAA==.Delicieuse:BAEANQAECgIIAgABNQAECgcIDQABAAAAAA==.Demonmanager:BAEANQAECgcIDQAAAA==.Denadhx:BAEANQAECgcICwAAAA==.',
Di='Diddydk:BAEANQAECggICAAAAA==.Diddydruid:BAEANQADCgcIDQABNQAECggICAABAAAAAA==.Dirtydwarf:BAEANQAECgQIBgAAAA==.Dispi:BAEANQAECgIIAgABNQAECgcICwABAAAAAA==.',
Do='Dobnicki:BAEANQAECggIDgAAAA==.Dogskratches:BAEANQAECgEIAQABNQAFFAQIBQAFAFwSAA==.Dollahbill:BAEANQAECggIBgAAAA==.Dominizo:BAEANQADCgcIBwAAAA==.Donkeydipper:BAEANQAECgQIBAABNQAECgYIDAABAAAAAA==.',
Dr='Drbahal:BAEANQAECgEIAQABNQAECgQIBgABAAAAAA==.Drdemo:BAEANQADCgYIBwABNQAECgQIBgABAAAAAA==.',
Dt='Dthhouse:BAEANQADCggICAABNQAECgQIBgABAAAAAA==.',
['Dë']='Dëlgalo:BAEANQAFFAMIAwAAAA==.',
['Dï']='Dïzz:BAEANQAECgUICAAAAA==.',
['Dû']='Dûckee:BAEANQADCgMIAwAAAA==.',
Ec='Ecodktwo:BAEANQAECgYICAABNQAECgcIDgABAAAAAA==.',
Ed='Eddieiwnl:BAEBNQAFFIEGAAMCAAUJ5A5vAQARAQWODQAAAQA3AHUNAAABADwAfw0AAAEAAACpDQAAAgATAFwNAAABADYAAgADCdoQbwEAEQEDjg0AAAEANwCpDQAAAgATAFwNAAABADYABgACCfMLLgAAvAACdQ0AAAEAPAB/DQAAAQAAAAAA.',
Ee='Eeves:BAEANQAECgcIDAAAAA==.',
Ei='Eisenpelz:BAEANQAFFAIIAwAAAA==.',
El='Elebahal:BAEANQAECgEIAQABNQAECgQIBgABAAAAAA==.',
Em='Emoradon:BAEANQAECgYIAQAAAA==.',
Er='Erisynn:BAEANQAECgYIDAAAAA==.',
Et='Etp:BAEANQADCgcIDQAAAA==.',
Ez='Ezporks:BAEANQADCgQIBAAAAA==.',
Fa='Fastasfckboi:BAEANQAECgYICgAAAA==.',
Fe='Featherbrain:BAEANQAFFAQIBAABNQAFFAQIBQAFAFwSAA==.Feripriest:BAEANQADCggICAABNQAFFAEIAQABAAAAAA==.Feritos:BAEANQAFFAEIAQAAAA==.',
Fi='Filetminhot:BAEANQAECgUIBgAAAA==.Fitzdh:BAEANQAECgEIAQABNQAECggIDgABAAAAAA==.Fitzgreen:BAEANQAECggIDgAAAA==.',
Fl='Flemdingo:BAEANQAFFAIIAwAAAA==.Flðkï:BAEANQAECgQIBQAAAA==.',
Fo='Forkliftcert:BAEANQADCgYIBgAAAA==.Fortyhands:BAEANQAECgcIDAAAAA==.',
Fr='Frogtax:BAEANQAECgEIAQAAAA==.Fránkli:BAEANQAECgEIAQABNQAECgQIBAABAAAAAA==.',
Fx='Fxhp:BAEANQAECgcICwAAAA==.',
Ga='Gargalondus:BAEANQAECgcICwAAAA==.Garnzer:BAEANQADCgEIAQAAAA==.Gayfyst:BAEANQADCggICAABNQAECggIDQABAAAAAA==.',
Ge='Georgehernia:BAEANQAECgIIAgABNQAECgYICgABAAAAAA==.',
Gi='Gingrdk:BAEANQADCggICQAAAA==.',
Go='Goldensneak:BAEANQADCgUIBgABNQADCgcIDQABAAAAAA==.Goldenwrath:BAEANQADCgcIDQAAAA==.Goopedal:BAEANQAECgQIBQAAAA==.',
Gr='Gremgrip:BAEANQADCgIIAgAAAA==.Grerzet:BAEANQAECgMIAwABNQAFFAIIAwABAAAAAA==.',
Gy='Gyattblast:BAEANQADCggIDgAAAA==.',
Ha='Hammymeta:BAEANQAECgcIDAAAAA==.Hardknight:BAEANQADCgUICQAAAA==.Hasapas:BAEANQAECgIIAgAAAA==.Hashadin:BAEANQAECgYICgAAAA==.Havodruid:BAEANQAECgQIBQAAAA==.',
He='Heggsm:BAEANQADCggIDAABNQAECggIDgABAAAAAA==.Heggspriest:BAEANQADCggICAABNQAECggIDgABAAAAAA==.Heggsr:BAEANQADCgEIAQABNQAECggIDgABAAAAAA==.Heggssham:BAEANQADCgIIAgABNQAECggIDgABAAAAAA==.Heibaispirit:BAEANQAECgQIBQABNQAECggIDwABAAAAAA==.',
Hi='Higanbana:BAEANQADCggIDgAAAA==.Hildraxes:BAEANQAECgYICQAAAA==.',
Ho='Hokumana:BAEANQAECgMIBAAAAA==.Hollerkin:BAEANQADCggICAABNQAFFAIIAwABAAAAAA==.Hollermagne:BAEANQAECgEIAQABNQAFFAIIAwABAAAAAA==.Holychitmayn:BAEANQAECgIIAgABNQAECgYICgABAAAAAA==.Holydaz:BAEANQAECgMIAwABNQAECgYICgABAAAAAA==.Holydeaths:BAEANQAECgcICgAAAA==.Holylas:BAEANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Hu='Huhi:BAEANQAECgYICQAAAA==.Huntini:BAEANQAECgYICgAAAA==.Huulluonn:BAEANQAECgQIBgAAAA==.',
Hy='Hyir:BAEANQAECgIIAgAAAA==.',
['Hè']='Hèggs:BAEANQAECggIDgAAAA==.',
Ia='Ias:BAEANQAECgEIAQAAAA==.',
Im='Imparity:BAEANQADCgIIAgABNQAFFAIIAwABAAAAAA==.Impermanence:BAEANQADCgQIBAABNQAFFAIIAwABAAAAAA==.Implicitly:BAEANQAFFAIIAwAAAA==.Imposing:BAEANQAECgIIAgABNQAFFAIIAwABAAAAAA==.Impostor:BAEANQAECgEIAQABNQAFFAIIAwABAAAAAA==.Imprecise:BAEANQADCgYIBgABNQAFFAIIAwABAAAAAA==.',
In='Infërno:BAEANQAECgYIDAABNQAFFAMIAwABAAAAAA==.Inspìred:BAEANQADCgYICwAAAA==.Invectis:BAEANQAECgYICgABNQAFFAEIAQABAAAAAA==.Invectus:BAEANQAFFAEIAQAAAA==.',
Ir='Irashara:BAEANQADCggICAABNQAECgcIDAABAAAAAA==.Irieden:BAEANQAECgEIAQAAAA==.Irønpàw:BAEANQADCggICAAAAA==.',
It='Itslilchonky:BAEANQAECgcIDAAAAA==.',
Ja='Jaksummons:BAEANQADCgYIBgAAAA==.',
Je='Jepi:BAEANQADCgQIBQAAAA==.Jessasavage:BAEANQAECgMIAwAAAA==.',
Ju='Jurisevokes:BAEANQAECgYIBwAAAA==.Jurymaul:BAEANQADCggIBgAAAA==.',
Ka='Kattiibrie:BAEANQADCgYICQAAAA==.Kazidan:BAEANQADCgMIAwAAAA==.',
Ke='Kecia:BAEANQAECgcIEAAAAA==.Keshley:BAEANQAECgIIAwAAAQ==.',
Ki='Kitsulina:BAEANQAECgQIBgAAAA==.Kiwinai:BAEANQAECgIIAgAAAA==.',
Ko='Korpsiçle:BAEANQADCggICAABNQAECgYIBgABAAAAAA==.Korpsiçlë:BAEANQAECgYIBgAAAA==.',
Kr='Krankenkritz:BAEANQAECgIIAgABNQAECgcICwABAAAAAA==.Krankenmight:BAEANQAECgcICwAAAA==.Krelinel:BAEANQADCggICAAAAA==.Kriegerlee:BAEANQAECgIIAgAAAA==.Krypl:BAEANQAECggIDgAAAA==.Kryptdk:BAEANQAECgEIAQABNQAECggIDgABAAAAAA==.Krystraza:BAEANQAECgcICwAAAQ==.',
Ky='Kymmie:BAEANQAECgcICwAAAA==.Kyrasis:BAEANQAECgcICwAAAA==.',
La='Laeythe:BAEANQAECgMIAwABNQAECgQIBAABAAAAAA==.Landorax:BAEANQAECgYICwAAAA==.Landosek:BAEANQAECgEIAQABNQAECgYICwABAAAAAA==.Larrydrywall:BAEANQAECgUICQABNQAECggIDwABAAAAAA==.Lashvir:BAEBNQAECoEZAAIHAAkJfCIoAQDAAwmODQAAAwBgAHUNAAADAGMAfw0AAAMAYwCpDQAAAwBjAFwNAAADAF8AXQ0AAAMAYQBlDQAAAwBXAKQNAAABACMAMw0AAAMAVAAHAAkJfCIoAQDAAwmODQAAAwBgAHUNAAADAGMAfw0AAAMAYwCpDQAAAwBjAFwNAAADAF8AXQ0AAAMAYQBlDQAAAwBXAKQNAAABACMAMw0AAAMAVAAAAA==.Lashvirshamy:BAEANQAECgYICgABNQAECgkJGQAHAHwiAA==.Lazloth:BAEANQAECggICwAAAA==.',
Le='Leatheranvil:BAEANQAECgcIBwABNQAECgcICgABAAAAAA==.Legionlives:BAEANQAECgcICwAAAA==.',
Li='Libxd:BAEANQAECgYIDAAAAA==.Likdh:BAEANQAECgcIDQABNQAFFAUIBwAIAAsQAA==.Likl:BAEBNQAFFIEHAAIIAAUJCxBgAACfAQWODQAAAgBkAHUNAAACACoAfw0AAAEADQCpDQAAAQAlADMNAAABAAsACAAFCQsQYAAAnwEFjg0AAAIAZAB1DQAAAgAqAH8NAAABAA0AqQ0AAAEAJQAzDQAAAQALAAAA.Lilbearky:BAEANQAECgQIBAABNQAECgcIDAABAAAAAA==.Lionnoh:BAEANQAFFAEIAQAAAA==.',
Lu='Lunaticleap:BAEANQAECgUIBwAAAA==.Luxxira:BAEANQADCggICAABNQAECgcIDAABAAAAAA==.',
['Lø']='Løäding:BAEANQAECgMIAwABNQAECgQICAABAAAAAA==.',
Ma='Madprince:BAEANQADCgMIAwAAAA==.Maguslee:BAEANQADCgYIBwABNQAECgIIAgABAAAAAA==.Mahlicee:BAEANQADCgYIBgAAAA==.Makiee:BAEANQAECgQIBAAAAA==.Malicious:BAEANQADCggICAABNQAECgMIAwABAAAAAA==.Marotgus:BAEANQAECgcIDQAAAA==.Martechcurse:BAEANQADCgYIBgABNQAECggIEAABAAAAAA==.Martechscale:BAEANQADCgYIBgABNQAECggIEAABAAAAAA==.Martechsigil:BAEANQAECggIEAAAAA==.Martechtrap:BAEANQAECggIDAABNQAECggIEAABAAAAAA==.Mattdeeman:BAEANQADCgMIBAABNQAECggIDgABAAAAAA==.Mazzyx:BAEANQAECgYICQAAAA==.',
Mc='Mcshamwhich:BAEANQADCggIDgABNQAFFAEIAQABAAAAAA==.',
Me='Menibbles:BAEANQAECgcIDQAAAA==.Meppdruid:BAEANQAECgYIBgABNQAECgcIDAABAAAAAA==.Meppevo:BAEANQAECgQIBAABNQAECgcIDAABAAAAAA==.Metakegs:BAEANQAECgYICAAAAA==.',
Mi='Michellelynn:BAEANQADCgYIDAAAAA==.Mightypuddy:BAEANQADCggIDQAAAA==.Miladyfoo:BAEANQADCggICgAAAA==.Milthara:BAEANQADCgUIBQABNQADCgYIBgABAAAAAA==.Miserïcorde:BAEANQADCggICAABNQADCggIDgABAAAAAA==.Missjeongjin:BAEANQAECgQIBAABNQAECgIIAgABAAAAAA==.',
Mo='Mommymilkas:BAEANQAECgQIBAAAAA==.Mongoosed:BAEANQAECggIDgAAAA==.Mongooze:BAEANQADCgYIBwABNQAECggIDgABAAAAAA==.Mordyc:BAEANQAECgcIDQAAAA==.Movements:BAEANQADCggIEAABNQAFFAEIAQABAAAAAA==.',
Mu='Murrkor:BAEANQADCgYIBgAAAA==.',
My='Myzy:BAEANQAECgQICwAAAA==.',
Na='Narzhul:BAEANQAECgQIBAAAAA==.',
Ne='Nedda:BAEANQAECgIIAgABNQAECgQIBAABAAAAAA==.',
Ni='Nibby:BAEANQAECggIBgAAAA==.Nikeys:BAEBNQAECoEWAAIJAAkJ7CUJAAD9AwmODQAAAgBiAHUNAAACAF8Afw0AAAIAYQCpDQAAAgBeAFwNAAACAF8AXQ0AAAIAYgBlDQAAAgBkAKQNAAAGAF4AMw0AAAIAYwAJAAkJ7CUJAAD9AwmODQAAAgBiAHUNAAACAF8Afw0AAAIAYQCpDQAAAgBeAFwNAAACAF8AXQ0AAAIAYgBlDQAAAgBkAKQNAAAGAF4AMw0AAAIAYwAAAA==.',
No='Noodlecar:BAEANQAECgYIBgABNQAFFAQIBgAKAEIGAA==.Noradh:BAEANQADCggICAAAAA==.Nottoasty:BAEANQAECgQIBAABNQADCgIIAgABAAAAAA==.Noxxira:BAEANQADCggICgABNQAECgcIDAABAAAAAA==.Nozticlegend:BAEANQAFFAIIAgAAAA==.',
Oh='Ohmspacex:BAEANQADCgUIBQABNQADCggICAABAAAAAA==.',
Ol='Oláy:BAEANQAECgIIAgAAAA==.',
Om='Omniazol:BAEANQADCgYICgABNQAECgQIBQABAAAAAA==.Omnific:BAEANQAFFAEIAQABNQAFFAEIAQABAAAAAA==.Omnithic:BAEANQAFFAEIAQAAAA==.Omniumbris:BAEANQAECgQIBQAAAA==.',
Oo='Oomtree:BAEANQAECgcIDAAAAA==.',
Os='Osj:BAEANQADCggICAABNQAECgcIDQABAAAAAA==.',
Oz='Ozikai:BAEANQAFFAEIAQAAAA==.',
Pa='Pailisu:BAEANQAECggIDgAAAA==.Palarak:BAEANQAECgQIBQAAAA==.Pallicake:BAEANQADCgcIDQABNQADCgcIDQABAAAAAA==.Paninidin:BAEANQAFFAIIAgAAAA==.Pattyfuego:BAEANQAFFAEIAQAAAA==.Pawnzz:BAEANQAECgYIBwAAAA==.',
Pi='Pinkroel:BAEANQADCgMIAwABNQAECgUIBgABAAAAAQ==.Pizzabucket:BAEANQAECgUIBwABNQAFFAIIAgABAAAAAA==.Pizzadlvboy:BAEANQAFFAIIAgAAAA==.',
Pl='Plowmydragon:BAEANQAFFAEIAQAAAA==.',
Po='Poadrizza:BAEANQAECgYIDAAAAA==.Politespidee:BAEANQADCgUIBQABNQAECgQICAABAAAAAA==.',
Pr='Priestboï:BAEANQAFFAEIAQAAAA==.Priestcake:BAEANQADCgcIDQAAAA==.Proteck:BAEANQADCgIIAgAAAA==.',
Pu='Pukalani:BAEANQADCggICQABNQAECgMIBAABAAAAAA==.Purkins:BAEANQAECgEIAQAAAA==.',
Ra='Rahfnarr:BAEANQAECgcICgAAAA==.',
Re='Renewmonk:BAEANQADCggIDgABNQAECggIEgABAAAAAA==.Renewpal:BAEANQAECggIEgAAAA==.Renewshaman:BAEANQADCgEIAQABNQAECggIEgABAAAAAA==.Rezponsible:BAEANQAECgUIBQABNQAFFAMIAwABAAAAAA==.',
Ro='Rocklance:BAEANQAECgcIDQAAAA==.Roely:BAEANQADCgYIBQABNQAECgUIBgABAAAAAQ==.Roleplay:BAEANQAFFAEIAQAAAA==.',
Ru='Rubilocks:BAEANQAECgUICAAAAA==.Rubipal:BAEANQADCgMIAwABNQAECgUICAABAAAAAA==.',
Ry='Ryxy:BAEANQADCgYIFQABNQAECgQICwABAAAAAA==.',
Sc='Scottini:BAEANQADCgQIBAABNQAECgYICgABAAAAAA==.Scourgeskull:BAEANQADCgYICQAAAA==.',
Se='Seisos:BAEANQAECgcICwAAAA==.Senpaigame:BAEANQAECgcIDAABNQAFFAIIAgABAAAAAA==.Sequences:BAEANQAECgQIBAAAAA==.',
Sh='Shadowlas:BAEANQADCgEIAgABNQAECgEIAQABAAAAAA==.Shammystabs:BAEANQAECgQIBQAAAA==.Shampook:BAEANQAECgEIAQABNQAFFAYICQACAOMUAA==.Shiroehunter:BAEANQAECggIDwAAAA==.Shïbi:BAEANQAECgQIBAAAAA==.',
Si='Sinfüll:BAEANQADCgYICwABNQAECgUICQABAAAAAA==.Siñfùl:BAEANQAECgUICQAAAA==.',
Sk='Sketcher:BAEANQAECgYICAABNQAECgkJFgAJAOwlAA==.Skwertyz:BAEANQAECggICwAAAA==.',
Sl='Sleepn:BAEANQADCgcIBwAAAA==.',
Sm='Smiterunner:BAEANQADCggICAAAAA==.Smökê:BAEANQADCggIDQABNQAECgcIDQABAAAAAA==.',
Sn='Snazzylemur:BAEANQAECgMIAwABNQAECgcICQABAAAAAA==.Snyddez:BAEANQAECgEIAQABNQAFFAIIAwABAAAAAA==.Snydeez:BAEANQAFFAIIAwAAAA==.Snydez:BAEANQAECgYICgABNQAFFAIIAwABAAAAAA==.',
So='Somaloria:BAEANQAFFAIIAgAAAA==.Somasblind:BAEANQADCggICgABNQAFFAIIAgABAAAAAA==.Sorrafrost:BAEANQADCggIDgAAAA==.',
Sp='Spellghetti:BAEANQAECgIIAgAAAA==.Spidees:BAEANQAECgQICAAAAA==.Spiritmookin:BAEBNQAFFIEGAAIEAAUJ7RkWAAD/AQWODQAAAgBeAHUNAAABACoAfw0AAAEAUACpDQAAAQA3ADMNAAABADsABAAFCe0ZFgAA/wEFjg0AAAIAXgB1DQAAAQAqAH8NAAABAFAAqQ0AAAEANwAzDQAAAQA7AAAA.',
Sq='Squided:BAEANQAECgQIBAAAAA==.Squidragosa:BAEANQAFFAEIAQABNQAECgQIBAABAAAAAA==.Squidrain:BAEANQADCgEIAQABNQAECgQIBAABAAAAAA==.Squidword:BAEANQAFFAEIAQABNQAECgQIBAABAAAAAA==.Squirtsx:BAEANQADCgcIBwABNQAECggICwABAAAAAA==.',
St='Steedcarell:BAEANQAECggIDgAAAA==.Stemí:BAEANQADCgcIBwAAAA==.Sterivari:BAEANQADCgYICAAAAA==.Stormcal:BAEANQADCggICgABNQAFFAEIAQABAAAAAA==.Storrs:BAEANQAECgcIDQAAAA==.Strunish:BAEANQAECgMIBQAAAA==.Stweeg:BAEANQAECgIIAgABNQAFFAIIAwABAAAAAA==.',
Sw='Swiftflame:BAEANQAECgEIAQAAAA==.',
Sy='Sylnestra:BAEANQAFFAIIAwAAAA==.Synvallas:BAEANQADCggIBwAAAA==.',
Ta='Taak:BAEANQADCgYICwAAAA==.Tantify:BAEANQAECgMIAwAAAA==.Tapzdh:BAEANQAECgcICAAAAA==.Tapzm:BAEANQAFFAMIBAABNQAECgcICAABAAAAAA==.',
Te='Teffina:BAEANQADCgcIBwAAAA==.Teribeary:BAEANQAECgYIBwAAAA==.Tetråtide:BAEANQAECgYIAgABNQAFFAIIAgABAAAAAA==.',
Th='Thesnazzyape:BAEANQAECgcICQAAAA==.Thornfallow:BAEANQAFFAIIAwAAAA==.Thunderfyst:BAEANQAECggIDQAAAA==.',
To='Toastyhugs:BAEANQADCgIIAgAAAA==.Toastytricks:BAEANQADCgcIBwABNQADCgIIAgABAAAAAA==.Tommydumps:BAEANQAECgcIBwABNQAECggICAABAAAAAA==.Tonyyma:BAEANQADCgIIAgABNQAECgUICAABAAAAAA==.Totemslangor:BAEANQAECgYICgAAAA==.',
Tr='Trixster:BAEANQAFFAIIAwAAAA==.',
Tw='Twobeararms:BAEANQADCgYIBgABNQAECggIDQABAAAAAA==.',
Ty='Tyyvoker:BAEANQAECgcICgAAAA==.',
['Tí']='Títaníá:BAEANQAFFAIIAwAAAA==.',
Va='Variblu:BAEANQAECgMIBAAAAA==.Vathiondh:BAEANQAECgcIDQAAAA==.Vaughnmourne:BAEANQAECgEIAQAAAA==.',
Vi='Viin:BAEANQADCgUIBQABNQAFFAIIAgABAAAAAA==.Viinsenpai:BAEANQADCggIEAABNQAFFAIIAgABAAAAAA==.Vindiagram:BAEANQAFFAIIAgAAAA==.Vipershado:BAEANQADCgQIBgAAAA==.',
Vo='Voidfunk:BAEANQADCgIIAgAAAA==.Voltania:BAEANQAECggIDgAAAA==.',
['Vî']='Vîtal:BAEANQAECgEIAQAAAA==.',
['Vï']='Vïtal:BAEANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Wa='Warmtoasties:BAEANQADCgMIAwABNQADCgIIAgABAAAAAA==.',
We='Weïwei:BAEANQADCgEIAQAAAA==.',
Wh='Whirledpeaz:BAEANQAECgQIBAAAAA==.',
Wi='Widdeldwagon:BAEANQAECgIIAgABNQAFFAUIBgAEAO0ZAA==.Wilykitt:BAEANQADCggICAABNQAFFAEIAQABAAAAAA==.Windamage:BAEANQADCgQIBAABNQAECgMIAwABAAAAAA==.Windsanity:BAEANQAECgMIAwAAAA==.',
Wk='Wkns:BAEANQAECgEIAQAAAA==.',
Xe='Xephostwo:BAEBNQAFFIEGAAMKAAQJQgapAADpAASODQAAAgASAHUNAAABAAcAqQ0AAAIABAAzDQAAAQAgAAoAAwkPB6kAAOkAA44NAAACABIAqQ0AAAEAAgAzDQAAAQAgAAsAAgl1AqcBAJsAAnUNAAABAAcAqQ0AAAEABAAAAA==.Xernz:BAEANQAECggIEAAAAA==.',
Ya='Yapskratches:BAEBNQAFFIEFAAIFAAQJXBKRAAB7AQSODQAAAgAiAHUNAAABACgAfw0AAAEAYQCpDQAAAQAQAAUABAlcEpEAAHsBBI4NAAACACIAdQ0AAAEAKAB/DQAAAQBhAKkNAAABABAAAAA=.Yarbles:BAEANQAECgQIBgAAAA==.',
Yh='Yhert:BAEANQAECgEIAQABNQAFFAEIAQABAAAAAA==.',
Yi='Yivar:BAEANQAECgYICAAAAA==.',
Ze='Zerofurry:BAEANQABCgQIBQAAAA==.',
Zh='Zhvdow:BAEANQAECgcIEAAAAA==.',
Zi='Zinozastra:BAEANQAECgEIAQABNQAECgUICAABAAAAAA==.',
Zo='Zoshzara:BAEANQADCgUIBQAAAA==.',
['Zì']='Zìôn:BAEANQAECgcIDAAAAA==.',
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
