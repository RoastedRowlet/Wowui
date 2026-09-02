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

local lookup = {'Unknown-Unknown','Mage-Arcane','Rogue-Subtlety','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Druid-Balance','Druid-Restoration','Evoker-Preservation','Paladin-Protection','Hunter-Marksmanship','Shaman-Restoration',}
local provider = {region='US',realm='BurningBlade',name='US',type='weekly',zone=53,date='2026-09-01',data={Ac='Acertrick:BAAANQAFFAIIAgAAAA==.',
Ad='Adampriest:BAAANQADCgIIAgAAAA==.Addh:BAAANQAECgUICAAAAA==.',
Ae='Aelwyd:BAAANQAECggIEAAAAA==.Aeoni:BAAANQADCggICAABNQAECgQIBQABAAAAAA==.Aeronis:BAAANQADCggIDAAAAA==.Aessara:BAAANQADCgYICwAAAA==.',
Ag='Aggron:BAAANQAECgcICgAAAA==.',
Ai='Ailurun:BAAANQADCgEIAgAAAA==.',
Al='Alexassassin:BAAANQAECgcIDQAAAA==.Aloriannis:BAAANQAECgMIAwAAAA==.Aluas:BAAANQADCgUICgAAAA==.',
Am='Amaracepally:BAAANQAECgEIAQAAAA==.Amowshamow:BAAANQAECgQIBAAAAA==.',
An='Anan:BAAANQADCggIBgAAAA==.Anatall:BAAANQAECgYICAAAAA==.Andrin:BAAANQADCggIDwAAAA==.Andy:BAAANQADCgYIBgAAAA==.Aneira:BAAANQADCgUIBQAAAA==.Anitá:BAAANQADCgYICQAAAA==.',
Ar='Archaon:BAAANQAECgEIAQAAAA==.Arei:BAAANQAECgUICAAAAA==.Argosa:BAAANQAECgQIBAAAAA==.Ari:BAAANQAECgQIBQAAAA==.Arianagrande:BAAANQADCgYICgAAAA==.Arihog:BAAANQAECgIIAgAAAA==.Arkilytê:BAAANQAECggIDgAAAA==.',
As='Ascend:BAEANQAFFAIIAgAAAA==.Astraeá:BAAANQADCgEIAQAAAA==.',
Au='Auroch:BAAANQAECgYIBwAAAA==.Auxilary:BAAANQAECgUICAAAAA==.',
Av='Avalen:BAAANQADCgQICAAAAA==.Avarcis:BAAANQAECgIIAgAAAA==.Aveleni:BAAANQAECgUICAAAAA==.Aveloree:BAAANQADCgYICQAAAA==.',
Az='Azelie:BAAANQADCgcIDQAAAA==.',
Ba='Baidoom:BAAANQABCgQIBAAAAA==.Balcmeg:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Bandrui:BAAANQADCgUIBQAAAA==.Banick:BAAANQADCgQIBwAAAA==.Bartszwar:BAAANQAECgYIDAAAAA==.',
Be='Bendie:BAAANQADCgIIAgAAAA==.Beret:BAAANQAECgUICAAAAA==.',
Bg='Bgaraecen:BAAANQADCgQIBAAAAA==.',
Bi='Bigchimpn:BAAANQAECgIIAgAAAA==.Bimbo:BAAANQAECgEIAQAAAA==.Bindkickplz:BAAANQABCgMIBQAAAA==.Birdinii:BAAANQAECgUIBQAAAA==.Birstormrage:BAAANQAECgEIAQAAAA==.',
Bl='Blackrose:BAAANQADCgUIBQAAAA==.Blacksmoke:BAAANQADCgUIBAAAAA==.Blacktusk:BAAANQAECgIIAgAAAA==.Bladestorm:BAAANQADCgUIAQAAAA==.Blargdruid:BAAANQAECgYIEgAAAA==.Blessthat:BAEANQADCgcIDQAAAA==.',
Bo='Bonkie:BAAANQADCgYICgABNQADCgcIDQABAAAAAA==.',
Br='Brewdyne:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.Brojojojojo:BAAANQAECgMIAwAAAA==.Broxas:BAAANQADCgcIBwAAAA==.Brøken:BAAANQAECggIBwAAAA==.',
Bu='Bubbleblade:BAAANQADCgEIAQAAAA==.Bubblesbro:BAAANQAECgcICgAAAA==.Bubkiss:BAAANQADCgEIAQAAAQ==.Buffalo:BAAANQAECgUICAAAAA==.Bulbasaurz:BAAANQADCggIDwAAAA==.Buldair:BAAANQADCgQIBAAAAA==.Burntbacon:BAAANQADCggICAABNQAECgQIBQABAAAAAA==.Burstygirl:BAAANQAECgUICgAAAA==.Buzzkill:BAAANQADCgMIAwAAAA==.',
['Bø']='Bøkari:BAAANQAECgEIAQAAAA==.',
Ca='Callie:BAAANQAFFAIIAgAAAA==.Calypsoza:BAAANQADCgMIBAAAAA==.Capitis:BAAANQADCgcICQAAAA==.Catwink:BAAANQADCgIIAgAAAA==.',
Ce='Celine:BAAANQADCggIDAAAAA==.Ceol:BAAANQAECgMIAwAAAA==.',
Ch='Chaosblade:BAAANQAECgEIAQAAAA==.Chilicheese:BAAANQADCgEIAQAAAA==.Chocobomb:BAAANQAECgcIDQAAAA==.Chronarfs:BAAANQADCggIDwAAAA==.',
Ci='Cicatrizesp:BAAANQAECgQIBwAAAA==.Cive:BAAANQADCgcIBwAAAA==.',
Cl='Clayberd:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Clocho:BAAANQADCggIDAAAAA==.',
Co='Coldhearrted:BAAANQAECgUICAAAAA==.Copyleft:BAAANQADCgQIBAAAAA==.Cosmere:BAAANQADCggICAAAAA==.',
Cr='Cryt:BAAANQAECgQIBQAAAA==.',
Da='Dagather:BAAANQADCgMIAwAAAA==.Danendena:BAAANQAECgEIAQAAAA==.Danglars:BAAANQADCgYIBwABNQAECgQIBQABAAAAAA==.Darkcorn:BAAANQAECgYIDAAAAA==.Darkdecayy:BAAANQADCgQIBQAAAA==.Darkshieldz:BAAANQADCggICAAAAA==.David:BAAANQAECgUICAAAAA==.',
De='Deadly:BAAANQADCgUIBQAAAA==.Deathlywind:BAAANQAECgQIBAAAAA==.Delphias:BAAANQADCggIDgAAAA==.Destrorin:BAAANQAECgQIBAAAAA==.Deucedeuce:BAAANQADCgUICwAAAA==.Devowizard:BAABNQAFFIEHAAICAAYJ5xUkAABDAgACAAYJ5xUkAABDAgAAAA==.',
Di='Dibib:BAAANQAFFAIIAgAAAA==.Dinglebery:BAAANQAECgQIBQAAAA==.Dirac:BAAANQADCgYIDAAAAA==.Dirtybirdz:BAAANQADCggIEAAAAA==.Dislexy:BAAANQADCgQIBQAAAA==.',
Dk='Dkitty:BAAANQAECgIIAgAAAA==.Dkizzy:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Do='Donkeydonng:BAAANQADCgUIBQAAAA==.Dota:BAAANQADCggIDwAAAA==.',
Dr='Dracke:BAAANQADCggICAAAAA==.Drekzul:BAAANQADCggIDQAAAA==.',
Du='Ducey:BAAANQADCgcIBwAAAA==.Ducksicker:BAAANQADCggIEAAAAA==.Dumpsterbaby:BAAANQAECgQIBwAAAA==.',
['Dè']='Dèschain:BAAANQADCgQIBQAAAA==.',
['Dó']='Dóth:BAAANQADCgYICwAAAA==.',
Ei='Eightfingers:BAAANQAECgQIBQAAAA==.',
Ek='Ekim:BAAANQADCgUICgAAAA==.',
El='Elentiya:BAAANQADCgMIAwAAAA==.Elyaen:BAAANQAECgMIAwAAAA==.',
Em='Emailed:BAEANQAFFAIIAgAAAA==.Emi:BAAANQAECgIIAgAAAA==.',
En='Envy:BAAANQADCggIDgAAAA==.',
Eo='Eore:BAAANQAECgIIAwAAAA==.',
Er='Erequem:BAAANQADCgEIAQAAAA==.',
Et='Ethøs:BAAANQADCggIDgAAAA==.',
Eu='Eupatorus:BAAANQADCgQIBQAAAA==.',
Ew='Ewokhunter:BAAANQAECgUIBwAAAA==.',
Fe='Felonee:BAAANQADCgYICwAAAA==.Festermight:BAAANQAFFAIIAwAAAA==.',
Fi='Finnhunter:BAAANQABCgIIAgAAAA==.Firenze:BAAANQADCgUIBwAAAA==.Fishpockets:BAAANQADCgEIAQAAAA==.',
Fr='Fredrock:BAAANQAECgQIBQAAAA==.',
Ga='Gaibe:BAAANQAECgYICgAAAA==.Gamba:BAAANQAECgQIBAAAAA==.',
Gb='Gb:BAAANQADCgYIBgAAAA==.',
Ge='Genghiscaulk:BAAANQAECgQIBAAAAA==.Georgeknight:BAAANQAFFAEIAQAAAA==.Gertrùde:BAAANQAECgEIAQAAAA==.Gerunash:BAAANQADCggICAABNQAFFAUIBgADADsDAA==.',
Gi='Gildharts:BAAANQAECgIIAgAAAA==.Girl:BAAANQADCggIDwAAAA==.',
Go='Goblindur:BAAANQADCggIDgAAAA==.',
Gr='Gradris:BAAANQAECgUICAAAAA==.Greener:BAAANQAECgUIBgAAAA==.Griddy:BAAANQADCgcICAAAAA==.Grimghar:BAAANQADCgYICgAAAA==.Grimrael:BAAANQADCgQIBAABNQAECgIIAwABAAAAAA==.Grimreapyr:BAAANQADCgUIBgABNQAECgIIAwABAAAAAA==.Grimtar:BAAANQAECgMIAwABNQAECgIIAwABAAAAAA==.Grimtariel:BAAANQAECgIIAwAAAA==.Grimzilla:BAAANQADCgYICgABNQAECgIIAwABAAAAAA==.Grippin:BAAANQADCggIDAAAAA==.',
Gu='Gunoil:BAAANQADCgcICQAAAA==.',
['Gì']='Gìngerale:BAAANQADCgUICgAAAA==.',
Ha='Hamrshifts:BAAANQADCgUICgAAAA==.Havartihavoc:BAAANQADCgYICgAAAA==.Hawtdots:BAAANQADCgQIBAABNQAECgQIBwABAAAAAA==.',
He='Healmeplx:BAAANQADCgYIBgAAAA==.Hekaraa:BAAANQADCgcICQAAAA==.Hellhammer:BAAANQADCgUIBQABNQADCgUIBQABAAAAAA==.Herenya:BAAANQAECgEIAQAAAA==.',
Hi='Hiccup:BAAANQADCgEIAQAAAA==.Hideyourtoes:BAAANQADCggIDwABNQAECgcIDQABAAAAAQ==.Himnick:BAABNQAFFIEGAAQEAAUJ3RVTAAAdAQAEAAMJUxhTAAAdAQAFAAEJKBhlAABdAAAGAAEJLgzTAwBcAAAAAA==.',
Ho='Holmadic:BAAANQADCggIAQAAAA==.Holyslimes:BAAANQADCgIIAgAAAA==.Honoree:BAAANQADCgYICQAAAA==.Honse:BAAANQADCggIDwAAAA==.Hoodal:BAAANQAECgcICwAAAA==.',
Hu='Huntrez:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Hustlepuff:BAAANQADCgYICAAAAA==.',
Hy='Hyllah:BAAANQADCgYICgAAAA==.',
['Hè']='Hèrrinà:BAAANQAECgEIAQAAAA==.',
Ik='Ikissdudes:BAAANQAECgQIBAAAAA==.',
Il='Illuunni:BAAANQAECgEIAQAAAA==.',
Im='Imbecile:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Imblack:BAAANQAECgUICQAAAA==.',
Jc='Jclaw:BAAANQADCgYIBgAAAA==.',
Je='Jennzen:BAAANQADCgYICQAAAA==.Jesterawr:BAAANQADCgUIBQAAAA==.',
Ji='Jinjin:BAAANQAECgQIBQAAAA==.',
Jl='Jlimremix:BAAANQAECgIIAgAAAA==.',
Jo='Jouley:BAAANQADCgUIBQAAAA==.',
Ju='Justsaiyan:BAAANQADCggIDAAAAA==.',
Jx='Jx:BAAANQAECgYICQAAAQ==.',
Jz='Jzimm:BAAANQADCgQIBAAAAA==.',
Ka='Kaeori:BAABNQAFFIEGAAIHAAUJNw1XAACrAQAHAAUJNw1XAACrAQAAAA==.Kalïsta:BAAANQADCggIDgAAAA==.Karra:BAAANQAECgQIBQAAAA==.Kayliezra:BAAANQADCgUIBQABNQADCgYICQABAAAAAA==.Kayssa:BAAANQAECgcIBwAAAA==.',
Ke='Keegan:BAAANQAECgUICAAAAA==.Keiragosa:BAAANQADCgcIDQAAAA==.Keita:BAAANQADCgYIBgAAAA==.Kelaran:BAAANQADCgEIAQAAAA==.Kelsara:BAAANQAECgYICgABNQAECgcIDAABAAAAAA==.',
Kh='Khaladyn:BAAANQADCgUIBQAAAA==.',
Ki='Kiko:BAAANQADCgYICQAAAA==.Killersmallz:BAAANQAECgMIAwAAAA==.Kindatipsy:BAAANQADCgYIBwAAAA==.Kirasti:BAAANQADCgUICgAAAA==.Kiriko:BAAANQADCgMIAwAAAA==.Kirkap:BAAANQADCgUIBQABNQAFFAUIBwAIAOAlAA==.Kirkas:BAAANQADCgYIBgABNQAFFAUIBwAIAOAlAA==.Kisspr:BAAANQAECgEIAgAAAA==.Kitkatt:BAAANQADCgMIAwAAAA==.Kittyen:BAAANQADCggICAAAAA==.',
Kl='Klet:BAAANQAECgEIAQAAAA==.',
Km='Kmage:BAAANQADCgYICgAAAA==.',
Ko='Kogarasu:BAAANQADCgUICgAAAA==.Kokodrilo:BAAANQADCggICAAAAA==.Koramar:BAAANQAECgIIAgABNQAFFAUIBgADADsDAA==.',
Kr='Kragarsf:BAAANQADCgYICQAAAA==.',
Ku='Kuulistin:BAAANQAECgEIAQAAAA==.',
Ky='Kyoppy:BAAANQAECgQIBQAAAA==.',
La='Labluegirl:BAAANQADCgYIBgABNQABCgIIAgABAAAAAA==.Lacusclyne:BAAANQADCgEIAQAAAA==.Lavaßurst:BAAANQADCgUIBQAAAA==.',
Le='Leejohn:BAAANQADCgYIBgAAAA==.Legndairy:BAAANQADCgYIBgAAAA==.Lenala:BAAANQAECgMIBAAAAA==.',
Li='Lightdeity:BAAANQADCgQIBgAAAA==.Lilbeefroni:BAAANQABCgEIAQAAAA==.Lilith:BAAANQADCgMIAwAAAA==.Lilythh:BAAANQADCgIIAgABNQADCgcICQABAAAAAA==.Linessa:BAAANQAECgQIBAAAAA==.Littlelion:BAAANQAECgYICQAAAA==.Littleteapot:BAAANQADCgcIBwAAAA==.',
Lu='Lucentil:BAAANQADCgUIBQABNQADCgYICQABAAAAAA==.Lucie:BAAANQAECgIIAgAAAA==.Luminth:BAAANQAECgUIBQAAAA==.',
Ly='Lyka:BAAANQAECgQIBwAAAA==.',
Ma='Madoria:BAAANQAECgIIAgAAAA==.Madorie:BAAANQAECgIIAgAAAA==.Magice:BAAANQAECgIIAgAAAA==.Magistus:BAAANQAFFAEIAQAAAA==.Marmalady:BAEBNQAFFIEGAAIJAAUJRB5BAADpAQAJAAUJRB5BAADpAQAAAA==.Masa:BAAANQAFFAIIAgAAAA==.Masq:BAAANQADCgcIDQAAAA==.Matamharicas:BAAANQAECgUIBQAAAA==.Matt:BAAANQAECgEIAQAAAA==.Mauled:BAAANQADCgcIBwABNQAFFAUIBgAKAHsJAA==.Maulnificent:BAAANQAECgIIAgABNQAFFAUIBgAKAHsJAA==.Maulo:BAABNQAFFIEGAAIKAAUJewkhAAB+AQAKAAUJewkhAAB+AQAAAA==.Maynaminty:BAAANQADCgEIAQABNQAECgcICwABAAAAAA==.',
Mc='Mclovin:BAAANQADCgUIBQAAAA==.',
Me='Medspriest:BAAANQADCgYIBgAAAA==.Megasoreass:BAAANQADCgUIAwAAAA==.Meliria:BAAANQAECgMIAwAAAA==.',
Mi='Midgert:BAAANQAECggIDgAAAA==.Mimint:BAAANQAECgIIAgABNQAFFAUIBgALAEQbAA==.Mistfit:BAAANQADCgYIBgAAAA==.',
Mo='Moadebe:BAAANQADCgYICQAAAA==.Moorpheus:BAAANQADCgYIBgAAAA==.Moreshaman:BAAANQADCgEIAQABNQADCgEIAQABAAAAAA==.Morphunter:BAAANQADCggIDwAAAA==.',
Mu='Muwu:BAAANQAECgQIBAAAAA==.',
My='Myfursona:BAAANQADCggICAAAAA==.Mystrali:BAAANQADCggIDwAAAA==.Myztified:BAAANQADCgUIBQAAAA==.',
Na='Naelyni:BAAANQADCgMIAwABNQADCggICAABAAAAAA==.Nathrezara:BAAANQABCgIIAgAAAA==.Nawtikal:BAAANQADCgYIDAAAAA==.',
Ne='Necrootter:BAAANQAECgMIAwAAAA==.Nelune:BAAANQAECgIIAgAAAA==.Neoheals:BAAANQADCgcIBwAAAA==.Neotank:BAAANQADCgUIBQAAAA==.Neurosurgeon:BAAANQADCgEIAQAAAA==.Nezdh:BAAANQAFFAIIAgAAAA==.',
Ni='Nizal:BAAANQADCgYIDAAAAA==.',
No='Nosimpin:BAAANQADCgYIBgAAAA==.',
Nu='Nutzferbuttz:BAAANQADCgMIBAABNQAECgQIBAABAAAAAA==.',
Ny='Nyllamage:BAAANQAECgcICgAAAA==.',
Ob='Obdromeda:BAAANQAECgUIBgAAAA==.Oberron:BAAANQAECgMIAwABNQAECgYICAABAAAAAA==.',
Ok='Okixs:BAAANQAECgYICQAAAA==.',
On='Onebaddruid:BAAANQAECgQIBAAAAA==.Onebadwarr:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Oo='Oogabgooga:BAAANQADCgcICQAAAA==.',
Os='Oscartheorc:BAAANQADCgEIAQAAAA==.Ossoleil:BAAANQADCgYIBgABNQADCgcIBwABAAAAAA==.',
Oz='Ozatar:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Ozen:BAAANQADCgQICAABNQADCgYIBgABAAAAAA==.Ozpal:BAAANQADCgYIBgAAAA==.Oztide:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Oztington:BAAANQADCgEIAQAAAA==.',
Pa='Paiku:BAAANQADCgYICgAAAA==.Palaky:BAAANQADCgcIBwAAAA==.Para:BAAANQAECgEIAQAAAA==.',
Pe='Penelopi:BAAANQAECgEIAQAAAA==.Penguinia:BAAANQAECgEIAQAAAA==.',
Pi='Pitukis:BAAANQABCgQIBAAAAA==.',
Pl='Plandalorian:BAAANQADCgQIBQAAAA==.Platectonics:BAAANQADCgQIBgAAAA==.Plexadin:BAAANQADCggIDgAAAA==.',
Po='Ponch:BAAANQADCgQIBAAAAA==.Popmybubble:BAAANQAECgIIAwAAAA==.',
Pr='Prepotenté:BAAANQAECgQIBwAAAA==.Priesta:BAAANQAECgcICwAAAA==.Pronebone:BAAANQAECgMIAwAAAA==.',
Ra='Rackblaster:BAAANQABCgEIAQAAAA==.Raei:BAAANQAECggIEgAAAA==.Ragestrasz:BAAANQADCgcIBwAAAA==.Raladin:BAAANQADCggICAAAAA==.Ramchi:BAABNQAFFIEGAAILAAUJYRw7AADtAQALAAUJYRw7AADtAQAAAA==.Ramhorn:BAAANQADCgUIBQAAAA==.Ranniel:BAAANQADCgEIAQAAAA==.Razorfists:BAAANQAECgMIAwABNQAFFAIIAgABAAAAAA==.Razorscales:BAAANQAFFAIIAgAAAA==.',
Re='Reckon:BAAANQADCggIDgAAAA==.Reeleaf:BAAANQAECgQIBgAAAA==.Remainn:BAAANQADCgcIBwAAAA==.Remlar:BAAANQADCgYIBgABNQAECgUICgABAAAAAA==.',
Ri='Ride:BAAANQADCgYIDAAAAA==.Rixi:BAAANQADCgIIAgAAAA==.Rizzard:BAAANQADCgUIBQAAAA==.',
Ro='Roriel:BAAANQAECgQIBAAAAA==.Rougarou:BAAANQADCggIDwAAAA==.Roweana:BAAANQADCgUICgAAAA==.',
Ru='Rumblecat:BAAANQADCgMIAwABNQADCgcICQABAAAAAA==.',
Ry='Rylankneth:BAAANQADCgYIBgAAAA==.',
['Rî']='Rîce:BAAANQAECgMIAwAAAA==.',
Sa='Sabelorn:BAAANQAECgIIAgAAAA==.Sacredfear:BAAANQAFFAEIAQAAAA==.Sacredshammy:BAAANQAECgQIBQABNQAFFAEIAQABAAAAAA==.Sandayy:BAAANQAFFAIIAgAAAA==.Sawario:BAAANQADCgMIAwAAAA==.',
Sc='Screwheals:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.',
Se='Sellene:BAABNQAFFIEHAAIIAAUJ4CUFAAATAgAIAAUJ4CUFAAATAgAAAA==.Sellina:BAAANQAECgEIAQABNQAFFAUIBwAIAOAlAA==.Seneriya:BAAANQABCgIIAgAAAA==.Senorbang:BAAANQAECgEIAQAAAA==.Sep:BAAANQAECgUICAAAAA==.',
Sh='Shadowflare:BAAANQADCgcIBwAAAA==.Shaggsalt:BAAANQADCggICAAAAA==.Shaolinhunk:BAAANQAECgIIAwAAAA==.Sharks:BAAANQAECgUICAAAAA==.Shawshanks:BAAANQADCgEIAQABNQADCgEIAQABAAAAAA==.Shelandria:BAABNQAFFIEGAAIDAAUJOwNSAACjAQADAAUJOwNSAACjAQAAAA==.Shiroee:BAAANQABCgQIAQABNQAECgMIAwABAAAAAA==.Shoda:BAAANQAFFAIIAgAAAA==.Shootrmcgávn:BAAANQADCggIEAAAAA==.Shreker:BAAANQAECgUICAAAAA==.',
Si='Sidchatic:BAAANQADCgEIAQAAAA==.Sidebo:BAAANQADCgYIBgAAAA==.Sinhunter:BAAANQAECgEIAQAAAA==.Sitonmytotem:BAAANQADCgEIAQAAAA==.',
Sj='Sjp:BAAANQADCgIIAgABNQAECgEIAgABAAAAAA==.',
Sk='Skeetoo:BAAANQAECgUIBgAAAA==.Skiera:BAAANQADCggICAABNQAECgQIBQABAAAAAA==.Skiplegs:BAAANQAECgEIAQAAAA==.Skorpeo:BAAANQADCggICAAAAA==.',
Sm='Smargendk:BAAANQADCgYIBwAAAA==.Smargenrog:BAAANQAFFAEIAQAAAA==.Smorsh:BAAANQAECgUIBgABNQADCgEIAQABAAAAAA==.',
Sn='Snaven:BAAANQADCgUIBQAAAA==.Sneggs:BAAANQADCgYIEQAAAA==.Snifflez:BAAANQADCggIDwAAAA==.Snipermonkey:BAAANQAECgIIAgAAAA==.',
So='Soiled:BAAANQAECgEIAQAAAA==.Solidshaft:BAAANQADCgYIBgAAAA==.Sopheia:BAAANQAECgIIAgAAAA==.Soul:BAAANQAECgUICAAAAA==.',
Sp='Spek:BAAANQAECggICQAAAA==.Split:BAAANQAECgEIAQAAAA==.Springonion:BAAANQAECgcIDgABNQAFFAUIBgAMAGoNAA==.',
Sq='Squidward:BAAANQAECgYICgAAAA==.',
St='Steadchi:BAAANQADCggICAAAAA==.Steakburrito:BAAANQADCgYICgAAAA==.Stedk:BAAANQAFFAIIAgAAAA==.Steven:BAAANQAECgIIAgAAAA==.Strongshift:BAAANQAECgEIAQAAAA==.Stygwyggyr:BAAANQAECgUICAAAAA==.',
Su='Sugarzcoat:BAAANQAECgEIAQAAAA==.Supdudejr:BAAANQAECgMIAwAAAA==.Supernovi:BAAANQADCggICAAAAA==.',
Sw='Sweetstache:BAAANQABCgQIBAAAAA==.',
Sy='Sykomike:BAAANQAECgIIAwAAAA==.Syler:BAAANQAECggIDgAAAA==.Sylár:BAAANQADCgcIDAAAAA==.Syreal:BAAANQADCgYICAAAAA==.',
['Sä']='Säcred:BAAANQAECgIIAgABNQAFFAEIAQABAAAAAA==.',
Ta='Tahlia:BAAANQAECgQIBgAAAA==.Talìa:BAAANQADCgUICgAAAA==.Tannadà:BAAANQAECgcIBwAAAA==.Tasari:BAAANQAFFAIIAgAAAA==.Taurenadin:BAAANQADCgIIAgAAAA==.Tayson:BAAANQABCgIIAwAAAA==.',
Te='Tekain:BAAANQAECgIIAQAAAA==.Tesia:BAAANQADCgMIBQAAAA==.',
Th='Thedeadlypug:BAAANQADCgIIAgAAAA==.Theeripper:BAAANQAECgMIAwAAAA==.Thrashwar:BAAANQADCgcIDQAAAA==.Thrustie:BAAANQAECgMIBAAAAA==.Thusios:BAAANQADCgcIBwAAAA==.',
Ti='Tichu:BAAANQADCgMIAwAAAA==.Tiekho:BAAANQADCgUIBQAAAA==.Tifelia:BAAANQADCgUIBQAAAA==.Tigorain:BAAANQADCgQIAwAAAA==.Tizirk:BAAANQABCgIIAgAAAA==.',
To='Toastybutter:BAAANQADCgQIBgAAAA==.Tonyz:BAAANQADCggIDwAAAA==.Torrak:BAAANQAECgUIBgAAAA==.Torthie:BAAANQAFFAIIAgAAAA==.Tothdk:BAAANQAFFAQIAwAAAA==.',
Tr='Treeage:BAAANQADCggIDQAAAA==.Treewalker:BAAANQAECgcIDQAAAA==.Tributary:BAAANQADCgcIBwAAAA==.Tripp:BAAANQADCgYIBgAAAA==.Trollerella:BAAANQADCgQIBAABNQAECgUICgABAAAAAA==.Trollzealot:BAAANQAECgMIAwAAAA==.Troxigar:BAAANQADCggIDgAAAA==.',
Tu='Tullyspring:BAAANQADCgQIBAAAAA==.',
Tv='Tverdydk:BAAANQAECgMIAwAAAA==.',
Tw='Twertlekat:BAAANQADCggIDwAAAA==.Twistkun:BAAANQADCgQIBAAAAA==.',
Un='Unclerod:BAAANQADCgcICQAAAA==.Unfixable:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAQ==.Unplayable:BAAANQAFFAEIAQAAAQ==.Unusualhorse:BAAANQAECgQIBgAAAA==.',
Uu='Uunfar:BAAANQAECgUIBgAAAA==.',
Va='Valedia:BAAANQAECgEIAQAAAA==.Valn:BAAANQADCggIDwAAAA==.Valtross:BAAANQADCgYICQAAAA==.Vangough:BAAANQAECgQIBQAAAA==.Vayu:BAAANQADCgQIBAAAAA==.',
Ve='Velvetvixen:BAAANQAECgEIAQAAAA==.',
Vi='Viper:BAAANQAECgUICAAAAA==.',
Vo='Voreâu:BAAANQADCgEIAQAAAA==.Vosslar:BAAANQAECgEIAQAAAA==.',
Vv='Vvarden:BAAANQADCgQIBAAAAA==.',
['Vî']='Vîper:BAAANQADCgMIAwAAAA==.',
Wa='Waarrlockk:BAAANQAFFAIIAgAAAA==.Walrusrider:BAAANQADCgYIBgAAAA==.Wang:BAAANQAECgYICAAAAA==.Warbird:BAAANQAECgIIAgAAAA==.Warhmonger:BAAANQADCggICAAAAA==.Wassy:BAAANQADCggICAAAAA==.',
We='Wemgobyama:BAAANQAECgcIDQAAAA==.',
Wh='Whobe:BAAANQAECgQIBgAAAA==.',
Wi='Witherfang:BAAANQAECgIIAgAAAA==.Wizsera:BAAANQAECgIIAgABNQAECgYIDAABAAAAAA==.Wizshock:BAAANQAECgYIDAAAAA==.',
Wn='Wnred:BAAANQAFFAIIAgAAAA==.',
Wo='Wombly:BAAANQADCgMIAwAAAA==.Womboree:BAAANQAECgIIAgAAAA==.Wonderful:BAAANQADCgIIAgAAAA==.',
Xa='Xanarius:BAAANQADCggIDwAAAA==.',
Yu='Yukarna:BAAANQAECgQIBQAAAA==.',
Za='Zaafkiel:BAAANQAECgYICAAAAA==.Zanaroth:BAAANQADCgUICgAAAA==.Zandrissil:BAEANQADCgYIBgABNQADCggIDwABAAAAAA==.Zarafie:BAEANQADCgIIAgABNQADCggIDwABAAAAAA==.Zaraphym:BAEANQADCggIDwAAAA==.Zarreh:BAAANQADCgYIEAAAAA==.',
Ze='Zephyrine:BAAANQADCgQIBAAAAA==.',
Zh='Zhuzhu:BAAANQAECgUIBQAAAA==.',
Zi='Zigy:BAAANQAECgUIBgAAAA==.',
Zo='Zoeý:BAAANQADCgcIBwAAAA==.Zombie:BAAANQAECgIIAgAAAA==.',
Zu='Zukko:BAAANQADCgcICAAAAA==.Zulkaris:BAAANQADCggICAAAAA==.Zuroxxar:BAEANQADCgcIBwABNQADCggIDwABAAAAAA==.',
Zy='Zynny:BAAANQADCggIDQAAAA==.',
['Zë']='Zëll:BAAANQADCgQIBgAAAA==.',
['Åa']='Åa:BAAANQADCggICAABNQAECgYICQABAAAAAA==.',
['Ðo']='Ðolo:BAAANQADCgQICAABNQADCgUICgABAAAAAA==.',
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
