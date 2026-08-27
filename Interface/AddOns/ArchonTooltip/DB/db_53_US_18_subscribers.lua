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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='Area52',name='US',type='subscribers',zone=53,date='2026-08-26',data={Aa='Aangst:BAEANQAECgMIAwAAAA==.',
Ab='Abc:BAEANQAECgYIBgAAAA==.',
Ac='Accentlight:BAEANQAECgYIBgABNQABCgIIAgABAAAAAA==.Acurze:BAEANQAECgUIBQAAAA==.',
Ad='Adamdlock:BAEANQAECgYIBgAAAA==.Adazz:BAEANQAECgQIBAAAAA==.',
Ag='Aggronawt:BAEANQAECgUIBQAAAA==.Agriote:BAEANQADCgUIBwAAAA==.',
Al='Alanaardvark:BAEANQADCgcIBwABNQAECgcIBwABAAAAAA==.Allthefist:BAEANQADCgQIBAABNQAECgMIAwABAAAAAA==.Alltheprocs:BAEANQAECgMIAwAAAA==.',
Am='Amillicyrus:BAEANQADCggICAAAAA==.',
An='Andraemos:BAEANQADCgIIAgAAAA==.',
Ap='Apook:BAEANQAFFAMIAwAAAA==.',
Ar='Arcangila:BAEANQADCgcIBwAAAA==.Arganox:BAEANQAECgQIBAAAAA==.Arghrond:BAEANQAECgUIBAAAAA==.Ariélle:BAEANQAECgUIBQAAAA==.',
At='Atticús:BAEANQAECgYIBgAAAA==.',
Au='Augbahal:BAEANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Aw='Awangawangaw:BAEANQAECgQIBAAAAA==.',
Az='Azorahai:BAEANQAECgUIBQAAAA==.',
Ba='Babylonius:BAEANQAECgIIAgABNQAFFAEIAQABAAAAAA==.Baneoflegion:BAEANQADCggICAABNQAECgQIBAABAAAAAA==.Banishes:BAEANQAECgcIBwAAAA==.Barruimonk:BAEANQADCgcIBwABNQAECgcIBwABAAAAAA==.',
Be='Beaneater:BAEANQAECgQIBAAAAA==.Beetleslayr:BAEANQAECgQIBAABNQAFFAEIAQABAAAAAA==.Benchd:BAEANQADCgEIAQABNQAECgYIBgABAAAAAA==.Berbatof:BAEANQAECgYIBAAAAA==.Bestpinoza:BAEANQAECgQIBAAAAA==.',
Bi='Bigtoasties:BAEANQADCgYIBgABNQADCgIIAgABAAAAAA==.',
Bo='Boostedbilly:BAEANQADCggICAABNQAECgcIAgABAAAAAA==.Bowdalicious:BAEANQAECgYIBgAAAA==.',
Br='Breezypriest:BAEANQAECgIIAgAAAA==.Brewsleesin:BAEANQAECgEIAQABNQAECgYIBgABAAAAAA==.Bringit:BAEANQADCggICAABNQAECgMIAwABAAAAAA==.',
Ca='Cadhir:BAEANQAECgEIAQABNQAECgYIBgABAAAAAA==.Caeriss:BAEANQAECgYIBgAAAA==.Calemi:BAEANQAECgcIBwAAAA==.Carthïl:BAEANQADCggICAAAAA==.Casandrá:BAEANQAECgYIBgAAAA==.Cassatie:BAEANQAECgMIAwABNQAFFAEIAQABAAAAAA==.Castogar:BAEANQAECgMIAwAAAA==.Cavechick:BAEANQAECgYIBgAAAQ==.',
Ce='Cendariel:BAEANQADCgUIBQAAAA==.Ceryal:BAEANQADCgcIBwAAAA==.Cevià:BAEANQAECgMIAwAAAA==.',
Ch='Chaningtotam:BAEANQAECgQIBAABNQAECgYIBgABAAAAAA==.',
Co='Columpia:BAEANQADCggICAABNQAECgYIBgABAAAAAA==.Columpio:BAEANQAECgYIBgAAAA==.Consecwation:BAEANQAECgMIAwAAAA==.Coraloralyn:BAEANQAECgEIAgAAAA==.Coraspin:BAEANQADCgQIBAABNQAECgEIAgABAAAAAA==.',
Cu='Cugino:BAEANQAECgYIBgAAAA==.',
Da='Daisukidesu:BAEANQAECgQIBAABNQAECgcIBwABAAAAAA==.Danblessyou:BAEANQAECgIIAgAAAA==.Dangolcouch:BAEANQAECgMIAwAAAA==.Darioly:BAEANQADCgUIBQAAAA==.',
De='Deathsnite:BAEANQAECgEIAQAAAA==.Deletegaming:BAEANQADCggICAABNQADCggICAABAAAAAA==.Deletemyself:BAEANQADCggICAAAAA==.Delicieuse:BAEANQADCgEIAQABNQAECgYIBgABAAAAAA==.Demonmanager:BAEANQAECgYIBgAAAA==.',
Di='Diddydk:BAEANQADCgIIAgABNQAECgcIBwABAAAAAA==.Diddydruid:BAEANQADCgYIBgABNQAECgcIBwABAAAAAA==.Dirtydwarf:BAEANQAECgMIAwAAAA==.Dispi:BAEANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Do='Dobnicki:BAEANQAECgYIBgAAAA==.Dogskratches:BAEANQADCgIIAgABNQAFFAEIAQABAAAAAA==.Dollahbill:BAEANQAECgcIAgAAAA==.Donkeydipper:BAEANQADCgYIBgABNQAECgUIBgABAAAAAA==.',
Dr='Drbahal:BAEANQAECgEIAQABNQAECgMIAwABAAAAAA==.Drdemo:BAEANQADCgEIAQABNQAECgMIAwABAAAAAA==.',
['Dè']='Dèstïny:BAEANQAECgYIBgABNQAECgYIBgABAAAAAA==.',
['Dë']='Dëlgalo:BAEANQAECgcIBwAAAA==.',
['Dï']='Dïzz:BAEANQAECgEIAQAAAA==.',
Ec='Ecodktwo:BAEANQAECgIIAgABNQAECgcIBwABAAAAAA==.',
Ed='Eddieiwnl:BAEANQAFFAEIAQAAAA==.',
Ee='Eeves:BAEANQAECgUIBQAAAA==.',
Ei='Eisenpelz:BAEANQAFFAEIAQAAAA==.',
El='Elebahal:BAEANQAECgEIAQABNQAECgMIAwABAAAAAA==.',
Em='Emoradon:BAEANQAECgYIAQAAAA==.',
Er='Erisynn:BAEANQAECgEIAgAAAA==.',
Et='Etp:BAEANQADCgYIBgAAAA==.',
Ez='Ezporks:BAEANQADCgQIBAAAAA==.',
Fa='Fastasfckboi:BAEANQAECgQIBAAAAA==.',
Fe='Featherbrain:BAEANQAECggICAABNQAFFAEIAQABAAAAAA==.Feripriest:BAEANQADCggICAABNQAECgcIBwABAAAAAA==.Feritos:BAEANQAECgcIBwAAAA==.',
Fi='Filetminhot:BAEANQAECgEIAQAAAA==.Fitzdh:BAEANQAECgEIAQABNQAECgYIBgABAAAAAA==.Fitzgreen:BAEANQAECgYIBgAAAA==.',
Fl='Flemdingo:BAEANQAFFAEIAQAAAA==.Flðkï:BAEANQAECgEIAQAAAA==.',
Fo='Forkliftcert:BAEANQADCgYIBgAAAA==.Fortyhands:BAEANQAECgUIBQAAAA==.',
Fr='Frogtax:BAEANQADCgYIBgAAAA==.Fránkli:BAEANQADCgcIBwABNQADCggICAABAAAAAA==.',
Fx='Fxhp:BAEANQAECgQIBAAAAA==.',
Ga='Gargalondus:BAEANQAECgUIBQAAAA==.',
Ge='Georgehernia:BAEANQAECgEIAQABNQAECgQIBAABAAAAAA==.',
Gi='Gingrdk:BAEANQADCggICAAAAA==.',
Go='Goldensneak:BAEANQADCgMIAwABNQADCgYIBgABAAAAAA==.Goldenwrath:BAEANQADCgYIBgAAAA==.Goopedal:BAEANQAECgEIAQAAAA==.',
Gr='Gremgrip:BAEANQADCgIIAgAAAA==.Grerzet:BAEANQADCggICAABNQAFFAEIAQABAAAAAA==.',
Gu='Guanarsh:BAEANQAECgYIBgAAAA==.',
Gy='Gyattblast:BAEANQADCgYIBgAAAA==.',
Ha='Hammymeta:BAEANQAECgUIBQAAAA==.Hardknight:BAEANQADCgQIBAAAAA==.Hasapas:BAEANQADCgYIBgAAAA==.Hashadin:BAEANQAECgQIBAAAAA==.Havodruid:BAEANQAECgEIAQAAAA==.',
He='Heggsm:BAEANQADCgIIAgABNQAECgYIBgABAAAAAA==.Heggspriest:BAEANQADCggICAABNQAECgYIBgABAAAAAA==.Heggssham:BAEANQADCgIIAgABNQAECgYIBgABAAAAAA==.Heibaispirit:BAEANQAECgMIAwABNQAECgcIBwABAAAAAA==.',
Hi='Higanbana:BAEANQADCgYIBgAAAA==.Hildraxes:BAEANQAECgMIAwAAAA==.',
Ho='Hokumana:BAEANQAECgEIAQABNQADCgEIAQABAAAAAA==.Hollerkin:BAEANQADCggICAABNQAFFAEIAQABAAAAAA==.Holychitmayn:BAEANQADCgEIAQABNQAECgQIBAABAAAAAA==.Holydaz:BAEANQADCgcIBwABNQAECgQIBAABAAAAAA==.Holydeaths:BAEANQAECgMIAwAAAA==.',
Hu='Huntini:BAEANQAECgQIBAAAAA==.Huulluonn:BAEANQAECgMIAwAAAA==.',
['Hè']='Hèggs:BAEANQAECgYIBgAAAA==.',
Ia='Ias:BAEANQADCgUICAAAAA==.',
Im='Imparity:BAEANQADCgIIAgABNQAFFAEIAQABAAAAAA==.Implicitly:BAEANQAFFAEIAQAAAA==.Imposing:BAEANQADCgYIBgABNQAFFAEIAQABAAAAAA==.Impostor:BAEANQADCgQIBAABNQAFFAEIAQABAAAAAA==.',
In='Infërno:BAEANQAECgYIBgABNQAECgcIBwABAAAAAA==.Inspìred:BAEANQADCgYIBgAAAA==.Invectis:BAEANQAECgQIBAABNQAECgcIBwABAAAAAA==.Invectus:BAEANQAECgcIBwAAAA==.',
Ir='Irieden:BAEANQADCggICAAAAA==.',
It='Itslilchonky:BAEANQAECgUIBQAAAA==.',
Ja='Jaksummons:BAEANQADCgYIBgAAAA==.',
Je='Jessasavage:BAEANQADCgcIBwAAAA==.',
Ju='Jurisevokes:BAEANQAECgEIAQAAAA==.Jurymaul:BAEANQADCggIBgAAAA==.',
Ka='Kattiibrie:BAEANQADCgMIAwAAAA==.Kazidan:BAEANQADCgMIAwAAAA==.',
Ke='Kecia:BAEANQAECgQIBAAAAA==.Keshley:BAEANQAECgEIAQAAAQ==.',
Ki='Kitsulina:BAEANQAECgIIAgAAAA==.Kiwinai:BAEANQADCgYIBgAAAA==.',
Ko='Korpsiçle:BAEANQADCggICAAAAA==.',
Kr='Krankenmight:BAEANQAECgQIBAAAAA==.Kriegerlee:BAEANQADCgcIBwAAAA==.Krypl:BAEANQAECgYIBgAAAA==.Kryptdk:BAEANQADCggICAABNQAECgYIBgABAAAAAA==.Krypticduh:BAEANQADCggICAABNQAECgYIBgABAAAAAA==.Krystraza:BAEANQAECgQIBAAAAQ==.',
Ku='Kulgrin:BAEANQAECgQIBAABNQAECgYIBgABAAAAAA==.',
Ky='Kymmie:BAEANQAECgQIBAAAAA==.Kyrasis:BAEANQAECgQIBAAAAA==.',
La='Laeythe:BAEANQAECgMIAwAAAA==.Landorax:BAEANQAECgUIBQAAAA==.Landosek:BAEANQADCgYIBgABNQAECgUIBQABAAAAAA==.Larrydrywall:BAEANQAECgUIBQABNQAECgcIBwABAAAAAA==.Lashvir:BAEANQAFFAEIAQAAAA==.Lashvirshamy:BAEANQAECgQIBAABNQAFFAEIAQABAAAAAA==.Lazloth:BAEANQAECgQIBAAAAA==.',
Le='Leatheranvil:BAEANQADCgEIAQABNQAECgMIAwABAAAAAA==.Legionlives:BAEANQAECgQIBAAAAA==.',
Li='Libxd:BAEANQAECgYIBgAAAA==.Likdh:BAEANQAECgYIBgABNQAFFAMIAwABAAAAAA==.Likl:BAEANQAFFAMIAwAAAA==.Lilbearky:BAEANQADCggICAABNQAECgUIBQABAAAAAA==.Lionnoh:BAEANQAECgYIBgAAAA==.',
Lu='Lunaticleap:BAEANQAECgIIAgAAAA==.Luxfortis:BAEANQAECgYIBgAAAA==.Luxsanctia:BAEANQAECgEIAQABNQAECgYIBgABAAAAAA==.Luxxira:BAEANQADCggICAABNQAECgUIBQABAAAAAA==.',
['Lø']='Løäding:BAEANQAECgMIAwAAAA==.',
Ma='Maguslee:BAEANQADCgEIAQABNQADCgcIBwABAAAAAA==.Mahlicee:BAEANQADCgYIBgAAAA==.Makiee:BAEANQADCgcIBwAAAA==.Marotgus:BAEANQAECgYIBgAAAA==.Martechsigil:BAEANQAECgcIBwAAAA==.Martechtrap:BAEANQAECgQIBAABNQAECgcIBwABAAAAAA==.Mattdeeman:BAEANQADCgMIBAABNQAECgYIBgABAAAAAA==.Mazzyx:BAEANQAECgQIAwAAAA==.',
Mc='Mcshamwhich:BAEANQADCgYIBgABNQAECgcIBwABAAAAAA==.',
Me='Megreat:BAEANQAECgYIBgAAAA==.Meppevo:BAEANQAECgQIBAABNQAECgUIBQABAAAAAA==.Metakegs:BAEANQAECgMIAgAAAA==.',
Mi='Mightypuddy:BAEANQADCgQIBQAAAA==.Mightyutters:BAEANQADCgMIAgABNQAECgIIAgABAAAAAA==.Miladyfoo:BAEANQADCgIIAgAAAA==.',
Mo='Mommymilkas:BAEANQADCggICAAAAA==.Mongoosed:BAEANQAECgYIBgAAAA==.Mordyc:BAEANQAECgYIBgAAAA==.Movements:BAEANQADCggICAABNQAECgUIBQABAAAAAA==.',
My='Myzy:BAEANQAECgIIAwAAAA==.',
Ne='Nezwarr:BAEANQADCgYIBwAAAA==.',
Ni='Nikeys:BAEANQAECgcIBwAAAA==.',
No='Noradh:BAEANQADCggICAAAAA==.Nottoasty:BAEANQADCgEIAQABNQADCgIIAgABAAAAAA==.Noxxira:BAEANQADCgEIAQABNQAECgUIBQABAAAAAA==.Nozticlegend:BAEANQAECgcIBwAAAA==.',
Ol='Oláy:BAEANQADCgcIBwAAAA==.',
Om='Omniazol:BAEANQADCgYIBgABNQADCggICAABAAAAAA==.Omnithic:BAEANQAECgcIBwAAAA==.Omniumbris:BAEANQADCggICAAAAA==.',
Oo='Oomtree:BAEANQAECgUIBQAAAA==.',
Os='Osj:BAEANQADCggICAABNQAECgYIBgABAAAAAA==.',
Oz='Ozikai:BAEANQAECgYIBgAAAA==.',
Pa='Pailisu:BAEANQAECgYIBgAAAA==.Palinexx:BAEANQAECgEIAQAAAA==.Pallicake:BAEANQADCgYIBgABNQADCgYIBgABAAAAAA==.Paninidin:BAEANQAECgcIBwAAAA==.Pattyfuego:BAEANQAECgYIBgAAAA==.Pawnzz:BAEANQAECgEIAQAAAA==.',
Pe='Peniaphobia:BAEANQAECgEIAQAAAA==.',
Pi='Pinkroel:BAEANQADCgMIAwABNQADCggICAABAAAAAQ==.Pizzabucket:BAEANQAECgUIBQABNQAECgcIBwABAAAAAA==.Pizzadlvboy:BAEANQAECgcIBwAAAA==.',
Pl='Plowmydragon:BAEANQAECgYIBgAAAA==.',
Po='Poadrizza:BAEANQAECgQIBgAAAA==.',
Pr='Priestboï:BAEANQAECgUIBQAAAA==.Priestcake:BAEANQADCgYIBgAAAA==.Proteck:BAEANQADCgEIAQAAAA==.',
Pu='Pukalani:BAEANQADCgEIAQAAAA==.Purkins:BAEANQAECgEIAQAAAA==.',
Ra='Rahfnarr:BAEANQAECgMIAwAAAA==.',
Re='Renewmonk:BAEANQADCgYIBgABNQAECgYICAABAAAAAA==.Renewpal:BAEANQAECgYICAAAAA==.Rezponsible:BAEANQAECgUIBQAAAA==.',
Ro='Rocklance:BAEANQAECgYIBgAAAA==.Roleplay:BAEANQAECgUIBQAAAA==.',
Ru='Rubilocks:BAEANQAECgMIAwAAAA==.',
Ry='Ryxy:BAEANQADCgUICgABNQAECgIIAwABAAAAAA==.',
Sc='Scourgeskull:BAEANQADCgYIBgAAAA==.',
Se='Seisos:BAEANQAECgQIBAAAAA==.Senpaigame:BAEANQAECgUIBQABNQAECgcIBwABAAAAAA==.Sequences:BAEANQADCggIDwAAAA==.',
Sh='Shadowlas:BAEANQADCgEIAgABNQADCgUICAABAAAAAA==.Shammystabs:BAEANQAECgEIAQAAAA==.Shampook:BAEANQAECgEIAQABNQAFFAMIAwABAAAAAA==.Shiroehunter:BAEANQAECgcIBwAAAA==.Shïbi:BAEANQADCggICAAAAA==.',
Si='Sinfüll:BAEANQADCgYIBgABNQAECgQIBAABAAAAAA==.Siñfùl:BAEANQAECgQIBAAAAA==.',
Sk='Sketcher:BAEANQAECgYIBgABNQAECgcIBwABAAAAAA==.Skwertyz:BAEANQAECgcICAAAAA==.',
Sl='Sleepn:BAEANQADCgcIBwAAAA==.',
Sm='Smiterunner:BAEANQADCggICAAAAA==.Smëg:BAEANQAECgIIAgAAAA==.Smökê:BAEANQADCgYIBgABNQAECgYIBgABAAAAAA==.',
Sn='Snydeez:BAEANQAFFAEIAQAAAA==.Snydez:BAEANQAECgMIAwABNQAFFAEIAQABAAAAAA==.',
So='Soggymoocow:BAEANQADCgUIBQABNQAECgIIAgABAAAAAA==.Somaloria:BAEANQAECgUIBQAAAA==.Somasblind:BAEANQADCgIIAgABNQAECgUIBQABAAAAAA==.Sorrafrost:BAEANQADCgYIBgAAAA==.',
Sp='Spellghetti:BAEANQADCgcIBwAAAA==.Spidees:BAEANQAECgQIBgAAAA==.Spiritmookin:BAEANQAFFAEIAQAAAA==.',
Sq='Squidragosa:BAEANQAECgYIBgABNQAFFAEIAQABAAAAAA==.Squidrain:BAEANQADCgEIAQABNQAFFAEIAQABAAAAAA==.Squidword:BAEANQAFFAEIAQAAAA==.Squirtsx:BAEANQADCgcIBwABNQAECgcICAABAAAAAA==.',
St='Steedcarell:BAEANQAECgYIBgAAAA==.Stemí:BAEANQADCgcIBwAAAA==.Sterivari:BAEANQADCgIIAgAAAA==.Stormcal:BAEANQADCggICAABNQAECgcIBwABAAAAAA==.Storrs:BAEANQAECgYIBgAAAA==.Strunish:BAEANQAECgIIAgAAAA==.Stweeg:BAEANQADCggICAABNQAFFAEIAQABAAAAAA==.',
Sw='Swiftflame:BAEANQADCgcIBwAAAA==.',
Sy='Sylnestra:BAEANQAFFAEIAQAAAA==.',
Ta='Taak:BAEANQADCgUIBQAAAA==.Tantify:BAEANQAECgMIAwAAAA==.Tapzm:BAEANQAFFAEIAQABNQABCgIIAgABAAAAAA==.',
Te='Teffina:BAEANQADCgcIBwAAAA==.Teribeary:BAEANQAECgIIAwAAAA==.Tetråtide:BAEANQADCggICAABNQAECgYIBgABAAAAAA==.',
Th='Thesnazzyape:BAEANQAECgUIBQAAAA==.Thornfallow:BAEANQAFFAEIAQAAAA==.Thunderfyst:BAEANQAECgYIBgAAAA==.',
To='Toastyhugs:BAEANQADCgIIAgAAAA==.Tommydumps:BAEANQAECgcIBwAAAA==.Totemslangor:BAEANQAECgQIBAAAAA==.',
Tr='Trixster:BAEANQAFFAEIAQAAAA==.',
Ty='Tyyvoker:BAEANQAECgMIAwAAAA==.',
['Tí']='Títaníá:BAEANQAFFAEIAQAAAA==.',
Va='Variblu:BAEANQAECgMIBAAAAA==.Vathiondh:BAEANQAECgYIBgAAAA==.',
Vi='Viin:BAEANQADCgUIBQABNQAECgYIBgABAAAAAA==.Viinsenpai:BAEANQADCggICAABNQAECgYIBgABAAAAAA==.Vindiagram:BAEANQAECgYIBgAAAA==.',
Vo='Voltania:BAEANQAECgYIBgAAAA==.',
['Vî']='Vîtal:BAEANQADCgUIBwABNQADCgYIBgABAAAAAA==.',
['Vï']='Vïtal:BAEANQADCgYIBgAAAA==.',
Wa='Warbeanrogue:BAEANQADCggIDwABNQAECgYIBwABAAAAAA==.Warmtoasties:BAEANQADCgMIAwABNQADCgIIAgABAAAAAA==.',
Wh='Whirledpeaz:BAEANQADCgcIBwAAAA==.',
Wi='Widdeldwagon:BAEANQADCgEIAQABNQAFFAEIAQABAAAAAA==.Wilykitt:BAEANQADCggICAABNQAECgYIBgABAAAAAA==.Windsanity:BAEANQAECgMIAwAAAA==.',
Wk='Wkns:BAEANQAECgEIAQAAAA==.',
Xe='Xephostwo:BAEANQAFFAIIAgAAAA==.Xernz:BAEANQAECgYICQAAAA==.',
Ya='Yapskratches:BAEANQAFFAEIAQAAAA==.Yarbles:BAEANQAECgIIAgAAAA==.',
Yh='Yhert:BAEANQAECgEIAQABNQAECgYIBgABAAAAAA==.',
Yi='Yivar:BAEANQAECgIIAgAAAA==.',
Ze='Zerofurry:BAEANQABCgEIAgAAAA==.',
Zh='Zhvdow:BAEANQAECgQIBAAAAA==.',
Zi='Zinozastra:BAEANQADCgEIAQABNQAECgUIBQABAAAAAA==.',
['Zì']='Zìôn:BAEANQAECgUIBQAAAA==.',
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
