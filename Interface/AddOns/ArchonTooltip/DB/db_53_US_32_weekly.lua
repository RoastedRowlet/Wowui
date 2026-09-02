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
local provider = {region='US',realm='Blackhand',name='US',type='weekly',zone=53,date='2026-09-01',data={Ae='Aeris:BAAANQADCgcIDAAAAA==.Aethwyn:BAAANQADCggIDwAAAA==.',
Ah='Ahnkala:BAAANQADCgQIBgAAAA==.',
Ai='Aigirlfriend:BAAANQAECgQIBAAAAA==.',
Al='Allupcreepy:BAAANQADCggICAAAAA==.',
Am='Amalyndi:BAAANQADCgYIBgAAAA==.Ambewlance:BAAANQADCgYIDQAAAA==.',
An='Annimosity:BAAANQADCgEIAQAAAA==.Ansem:BAAANQADCggIDwAAAA==.Anúbis:BAAANQADCgQIBAAAAA==.',
Ap='Apawllo:BAAANQAECgEIAQAAAA==.Apep:BAAANQADCgYICwAAAA==.Apostle:BAAANQAECgEIAQAAAA==.',
Ar='Aramìs:BAAANQADCgIIAgAAAA==.Arcaya:BAAANQADCgYIBgAAAA==.Ariaka:BAAANQADCgEIAQAAAA==.Arleen:BAAANQADCgUIBwAAAA==.Arlida:BAAANQAECgEIAQAAAA==.Aryto:BAAANQADCgUIBQAAAA==.',
As='Asketill:BAAANQADCgYICgAAAA==.Asmodee:BAAANQADCgQIBAAAAA==.',
Au='Aure:BAAANQADCgYIDAAAAA==.',
Ba='Bainne:BAAANQADCgMIAwAAAA==.Baitken:BAAANQADCgYICgABNQADCgYIDAABAAAAAA==.Barktea:BAAANQADCgYIDAAAAA==.Batdawg:BAAANQAECgEIAQAAAA==.Batharel:BAAANQADCgYICwAAAA==.Battcantdps:BAAANQADCgYIBgAAAA==.Battleground:BAAANQADCgIIAgAAAA==.',
Be='Bearen:BAAANQAECgEIAQAAAA==.Beertrain:BAAANQAECgIIAQAAAA==.Beesechurger:BAAANQADCggIDgAAAA==.Belladue:BAAANQADCgYICwAAAA==.Bellezza:BAAANQAECgQIBQAAAA==.',
Bh='Bhilly:BAAANQADCgIIAwAAAA==.',
Bi='Bigdumbkatqt:BAAANQAECgMIAwAAAA==.Bignjuicy:BAAANQABCgIIAgAAAA==.Bimisi:BAAANQAECgEIAQAAAA==.',
Bl='Bloodshhot:BAAANQAECgQICAAAAA==.Blueragebar:BAAANQAECgMIAwAAAA==.',
Bo='Bobadasmash:BAAANQADCgYICQABNQAECgEIAQABAAAAAA==.Bobitt:BAAANQADCgYICwAAAA==.Boddyknocker:BAAANQADCggICwAAAA==.Boombox:BAAANQADCgYIBgAAAA==.Boonerichard:BAAANQADCgYICwAAAA==.',
Br='Braina:BAAANQADCgYICwAAAA==.Branwin:BAAANQADCgEIAQAAAA==.Braver:BAAANQAECggIDQAAAA==.Braverwar:BAAANQAECgIIAwABNQAECggIDQABAAAAAA==.Brayedine:BAAANQADCgYICQAAAA==.Break:BAAANQAECggIDwAAAA==.Bromungandr:BAAANQADCgUIBQAAAA==.',
By='Bynnyy:BAAANQAECgIIAgAAAA==.',
['Bù']='Bùbbles:BAAANQADCgIIAgAAAA==.',
Ca='Cadelsaya:BAAANQAECgQIBQAAAA==.Camandah:BAAANQADCgUIBQAAAA==.Cammandzar:BAAANQADCgQIBAABNQADCgUIBQABAAAAAA==.Canman:BAAANQADCgUIBgAAAA==.Carlo:BAAANQAECgEIAQAAAA==.Carryout:BAAANQADCggICAAAAA==.Cassei:BAAANQADCgYICwAAAA==.Castertroy:BAAANQAECgIIAgAAAA==.',
Ce='Celenia:BAAANQADCgYICwAAAA==.',
Ch='Cheetopaly:BAAANQADCgYIDAAAAA==.Chìgusa:BAAANQAECgEIAQAAAA==.',
Ci='Circa:BAAANQADCgEIAQAAAA==.',
Cl='Clumonk:BAAANQADCggIDgAAAA==.',
Co='Convoke:BAAANQADCggIEAABNQAECgEIAQABAAAAAA==.Coosar:BAAANQADCgYIBgAAAA==.Cooseyloosey:BAAANQAECgEIAQABNQAECgUIBgABAAAAAA==.Coosinator:BAAANQAECgUIBgAAAA==.Cooterray:BAAANQAECgEIAQAAAA==.Corellon:BAAANQADCggIDgAAAA==.Corinth:BAAANQAECgEIAQAAAA==.',
Cr='Cratoz:BAAANQADCgUIBwAAAA==.Croswind:BAAANQAECgQIBgAAAA==.',
Cy='Cyndrine:BAAANQAECgcIBwAAAA==.Cyrani:BAAANQAECgQIBQAAAA==.',
Da='Dadipps:BAAANQAECgUIBQAAAA==.Daggumit:BAAANQADCgYIBgAAAA==.Dagnei:BAAANQADCgQIBQAAAA==.Daltina:BAAANQADCgYIBgAAAA==.Dareael:BAAANQADCggICAAAAA==.Daurgoth:BAAANQADCggIDwAAAA==.',
De='Deadbydrand:BAAANQADCgcIDQAAAA==.Deathndspark:BAAANQAECgMIAwAAAA==.Deathpuma:BAAANQAECgIIAgAAAA==.Deathrowe:BAAANQADCgcIDQAAAA==.Dednevoker:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Deelyte:BAAANQADCgYICwAAAA==.Demítrá:BAAANQADCgIIAgABNQAECgMIBQABAAAAAA==.Denouncer:BAAANQADCgMIBAABNQAECgUIBgABAAAAAA==.Derca:BAAANQADCgUICQAAAA==.',
Di='Dieds:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Dienne:BAEANQAECgEIAQAAAA==.Dietunicorn:BAAANQADCggIDAABNQAECgUIBQABAAAAAA==.Dinarra:BAAANQADCgQIBAAAAA==.Disahzter:BAAANQADCggIEAAAAA==.',
Do='Docdrood:BAAANQABCgEIAQABNQAECgEIAQABAAAAAA==.Docmonk:BAAANQAECgEIAQAAAA==.Donlazul:BAAANQADCgQIBAAAAA==.',
Dr='Draconoth:BAAANQADCgYIDAAAAA==.',
Du='Dunstird:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.',
Dy='Dyami:BAAANQAECgEIAQAAAA==.',
Ea='Eatmorechkn:BAAANQAECgEIAQAAAA==.',
Ee='Eellonwy:BAAANQADCgQIBgAAAA==.Eemerald:BAAANQADCgYICwAAAA==.',
Eg='Egna:BAAANQADCggIDQAAAA==.',
El='Eldiablo:BAAANQAECgQIBAAAAA==.Elizaa:BAAANQAECgEIAQAAAA==.',
Ev='Evilclared:BAAANQADCgIIAgABNQAFFAEIAQABAAAAAA==.Evildean:BAAANQADCgYICgAAAA==.',
Fa='Fanya:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Fe='Fenrigaar:BAAANQAECgQIBAAAAA==.',
Ff='Ffsa:BAAANQAECgQIBgAAAA==.',
Fi='Fillin:BAAANQADCgUIBgAAAA==.Filô:BAAANQAECgcIBwAAAA==.',
Fo='Fourtysixtwo:BAAANQADCggIEAAAAA==.Foxyladie:BAAANQADCgIIAgAAAA==.',
Fr='Frasti:BAAANQADCgQIBAAAAA==.Frostmage:BAAANQAECgQIBAAAAA==.',
Fu='Fuegoblazeit:BAAANQABCgIIAgAAAA==.Furbucket:BAAANQAECgEIAQAAAA==.Futonhunts:BAAANQAECgUIBQAAAA==.',
Fy='Fylerw:BAAANQAECgEIAQAAAA==.',
Gh='Ghostrideher:BAAANQAECgEIAQAAAA==.',
Gi='Gigadad:BAAANQAECgUIBwAAAA==.',
Go='Gornthemonki:BAAANQADCgMIAwAAAA==.',
Gr='Griannee:BAAANQAECgIIAgAAAA==.Grislix:BAAANQADCgYIBgAAAA==.Grismistea:BAAANQADCgMIBQABNQADCgYIBgABAAAAAA==.Gryffin:BAAANQAECgEIAQAAAA==.',
Gu='Guidance:BAAANQADCgcIBwAAAA==.Gummies:BAAANQABCgQICAAAAA==.',
['Gâ']='Gânk:BAAANQAECgEIAQAAAA==.',
Ha='Hanrekt:BAAANQADCgYIBwAAAA==.Happiness:BAAANQADCgcICQABNQAECgQIBAABAAAAAA==.',
He='Heavychevy:BAAANQADCggIDgAAAA==.',
Hi='Hildoehealz:BAAANQADCgQICgAAAA==.',
Hu='Humphrees:BAAANQAECgQIBAAAAA==.',
Hy='Hypocrisy:BAAANQADCgIIAgAAAA==.',
['Hà']='Hàtos:BAAANQAECgYIAQAAAA==.',
Id='Idot:BAAANQADCgUIBQAAAA==.',
Il='Illidave:BAAANQADCgMIAwAAAA==.',
In='Inebriatas:BAAANQAECgEIAQAAAA==.Invissibill:BAAANQADCggIDgAAAA==.',
Is='Ishaa:BAAANQADCggICwAAAA==.',
Iv='Ivanä:BAAANQADCggIDgAAAA==.',
Iz='Izax:BAAANQAECgEIAQAAAA==.',
Ja='Jaddzia:BAAANQABCgQIBAAAAA==.Jadestone:BAAANQADCgYIBgAAAA==.',
Ju='Junglefu:BAAANQADCgIIAgAAAA==.Jupitus:BAAANQADCggIDQAAAA==.Justin:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.',
['Jû']='Jûstin:BAAANQADCgUIDAABNQAECgcIDQABAAAAAA==.',
Ka='Karma:BAAANQADCgYIBgAAAA==.Katalania:BAAANQADCgYIBgAAAA==.',
Ke='Keeshama:BAAANQADCgIIAgAAAA==.Keiwhenua:BAAANQADCggIDgAAAA==.Kelinn:BAAANQADCgUIBQAAAA==.Kenthel:BAAANQAECgQIBAAAAA==.',
Ki='Kiplander:BAAANQAECgQIBQAAAA==.Kitheryn:BAAANQAECgEIAQAAAA==.',
Kl='Klitt:BAAANQADCggIDAAAAA==.',
Ko='Komosky:BAAANQAECgcIDQAAAA==.Korry:BAAANQADCgYIBgAAAA==.Kortanis:BAAANQAECgEIAQAAAA==.',
Kr='Krakìn:BAAANQADCgYIBgAAAA==.',
Ku='Kushage:BAAANQAECgEIAQAAAA==.',
La='Landissa:BAAANQAECgEIAQAAAA==.Larcenciel:BAAANQAECgIIAgAAAA==.Larryholmes:BAAANQABCgQIBAAAAA==.',
Le='Letmehelpyou:BAAANQAECgUIBgAAAA==.',
Li='Licky:BAAANQADCgcIDQAAAA==.Lihan:BAAANQADCggICAAAAA==.Lilieth:BAAANQADCgIIAgAAAA==.Lily:BAAANQAECgEIAQAAAA==.Lively:BAAANQADCgYICQAAAA==.',
Lo='Lockedtoit:BAAANQADCgYIBgAAAA==.Loverocket:BAAANQADCggICAAAAA==.',
Ly='Lyshia:BAAANQAECgQIBQAAAA==.',
['Lí']='Líghthand:BAAANQAECgEIAQAAAA==.',
['Lý']='Lýght:BAAANQADCgcIBwAAAA==.',
Ma='Magedown:BAAANQADCgcIBwAAAA==.Manpumper:BAAANQADCgQIBAAAAA==.Margor:BAAANQADCgYICwAAAA==.Mattdemon:BAAANQAECgQIBQAAAA==.',
Me='Meliany:BAAANQADCgYICgAAAA==.Meliorate:BAAANQAECgUICAAAAA==.Meowch:BAAANQAECgEIAQAAAA==.',
Mi='Mikachu:BAAANQAECgQIBAABNQAFFAEIAQABAAAAAA==.Miksi:BAAANQADCgMIAwABNQADCgUIBgABAAAAAA==.Miradele:BAAANQADCggICAAAAA==.Miraxx:BAAANQADCgUIBgAAAA==.Misscleö:BAAANQAECgEIAQAAAA==.Miyoshi:BAAANQAECgEIAQAAAA==.',
Mo='Moosakka:BAAANQAECgMIAwAAAA==.Moovinthru:BAAANQADCgQIBAAAAA==.Moraxes:BAAANQADCgcIBwAAAA==.Mordenkainen:BAAANQADCgcIBwAAAA==.Morphidmage:BAAANQADCgUIBQAAAA==.Motoko:BAAANQADCgUIAQAAAA==.',
Mu='Muaadib:BAAANQADCggIDgABNQAECgQIBgABAAAAAA==.',
My='Mydin:BAAANQAECgQIBAAAAA==.Myssaphra:BAAANQAECgUIBgAAAA==.',
['Mì']='Mìsawa:BAAANQAECgEIAQAAAA==.',
Na='Nakai:BAAANQADCggIDgAAAA==.Nastijiggle:BAAANQAECgEIAQAAAA==.',
Nc='Nc:BAAANQAECgEIAQAAAA==.',
Ne='Nexxa:BAAANQADCggIDgAAAA==.',
Ni='Nightshadow:BAAANQADCgQIBAAAAA==.Niqkle:BAAANQAECgQIBQAAAA==.Nitetbane:BAAANQAECgIIBQAAAA==.',
No='Nohurtscooby:BAAANQADCgUIBgAAAA==.Notadh:BAAANQADCgQIBAAAAA==.',
Ns='Nstagatr:BAAANQADCggIDgAAAA==.',
Ny='Nyxi:BAAANQABCgQIBAAAAA==.',
Ol='Olari:BAAANQABCgIIAgAAAA==.Olehanna:BAAANQAECgIIAgAAAA==.',
On='Oni:BAAANQADCgYICAAAAA==.',
Op='Opioid:BAAANQADCgcIDAAAAA==.Opsèc:BAAANQAECgEIAQAAAA==.',
Or='Orsa:BAAANQADCggICAAAAA==.',
Pe='Peachshock:BAEANQAECggIDwAAAA==.Perfectlock:BAAANQAECgEIAQAAAA==.',
Pi='Pigog:BAAANQADCgcIDAAAAA==.',
Po='Pordgio:BAAANQADCgcIDAAAAA==.Pozzi:BAAANQAECgQIBAAAAA==.',
Pr='Praypal:BAAANQADCgEIAQAAAA==.',
Ps='Psuedolus:BAAANQAECgEIAQAAAA==.Psålm:BAAANQADCggIDwAAAA==.',
Pu='Pulshadow:BAAANQAECgYICgAAAA==.Pumah:BAAANQADCgUIBgAAAA==.',
Ra='Raamen:BAAANQADCgUIBgAAAA==.Raellia:BAAANQAECgQIBAAAAA==.Raimmey:BAAANQADCgIIBAAAAA==.Rajia:BAAANQADCgYIDAABNQADCggIDgABAAAAAA==.Ralune:BAAANQADCggICgAAAA==.Ranes:BAAANQAECgQIBAAAAA==.Razagual:BAAANQADCggIBAAAAA==.',
Re='Redxelementz:BAAANQAECgQIBgAAAA==.Redxpastakan:BAAANQABCgQIBAABNQAECgQIBgABAAAAAA==.Renasen:BAAANQADCggIDgAAAA==.Reno:BAAANQADCgcICwAAAA==.Resiretha:BAAANQADCggICAAAAA==.Revelynn:BAAANQAECgMIAwAAAA==.Rexkwondo:BAAANQAECgIIAgAAAA==.',
Ri='Rivliam:BAAANQADCggIDgAAAA==.Rizzn:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.',
Ro='Rook:BAAANQAECgIIAgAAAA==.Rooxxy:BAAANQAECgMIAwAAAA==.',
Ry='Rynoh:BAAANQADCgcIBwAAAA==.Rythrik:BAAANQAECgEIAgAAAA==.Ryujinorsted:BAAANQADCgUIBQAAAA==.',
Sa='Sainted:BAAANQAECgcICwAAAA==.Sanoks:BAAANQAECgEIAQAAAA==.Sanokz:BAAANQABCgEIAQAAAA==.Savira:BAAANQADCgcIBwAAAA==.',
Sc='Scaleorva:BAAANQADCgYIDAAAAA==.',
Se='Seraphìm:BAAANQADCgcIDAAAAA==.Seïnaru:BAAANQADCgYIBgAAAA==.',
Sh='Shadyballs:BAAANQADCgYIBgAAAA==.Shamysosa:BAAANQADCgYICgABNQADCgYICwABAAAAAA==.Shinjí:BAAANQAECgUIBwAAAA==.Shmob:BAAANQADCgQIBwAAAA==.Shnappz:BAAANQADCgYIDAAAAA==.Shwillarou:BAAANQAECgEIAQAAAA==.Shádôws:BAAANQADCgYICwAAAA==.',
Si='Sinergee:BAAANQADCggIDgAAAA==.Sinnj:BAAANQADCgcIDQAAAA==.',
Sk='Skinsey:BAAANQADCgYIBwAAAA==.Skycrush:BAAANQADCgUIBQAAAA==.',
Sl='Slanie:BAAANQADCgYICwAAAA==.Slingerz:BAAANQAECgQIBQAAAA==.',
Sm='Smoky:BAAANQAECgIIAgAAAA==.',
Sn='Sneakpastya:BAAANQADCgIIAgAAAA==.Snoochie:BAAANQADCggIDQAAAA==.',
So='Sollis:BAAANQADCgMIBgAAAA==.',
Sp='Spazzchel:BAAANQADCgYICwAAAA==.Spiritbox:BAAANQAECggIDAABNQAECgEIAQABAAAAAA==.Sprucemoose:BAAANQADCgIIAwAAAA==.',
St='Stahlman:BAAANQAECgQIBAAAAA==.Stalpho:BAAANQAECgEIAQAAAA==.Starblessed:BAAANQADCgMIBgABNQADCggIDgABAAAAAA==.Starkind:BAAANQADCggIDgAAAA==.Starliner:BAAANQAECgQIBQAAAA==.Stasis:BAAANQAECgIIAgABNQAECgEIAQABAAAAAA==.Strahd:BAAANQADCgEIAgAAAA==.Styrke:BAAANQADCgYIBgAAAA==.',
Su='Subza:BAAANQAECgQIBQAAAA==.',
Sw='Swagtistic:BAAANQADCgYIDAAAAA==.',
Ta='Taliss:BAAANQAECgEIAQAAAA==.Tankmedaddy:BAAANQAECgEIAQAAAA==.Tappuccino:BAAANQADCgUIBQAAAA==.Taras:BAAANQAECggIDwAAAA==.Taraxist:BAAANQAECgEIAQAAAA==.Tautology:BAAANQAECgEIAQAAAA==.Tazajin:BAAANQADCgYIBgAAAA==.',
Tc='Tchala:BAAANQAECgEIAwAAAA==.Tchallah:BAAANQADCgMIAwAAAA==.Tchaumb:BAAANQADCgEIAQAAAA==.',
Te='Teks:BAAANQAECgEIAQAAAA==.Telian:BAAANQADCgUIBQAAAA==.Teth:BAAANQADCgcIDAAAAA==.',
Th='Thaine:BAAANQAECgQIBQAAAA==.Theoalthor:BAAANQADCgQIBAAAAA==.Theundeadone:BAAANQAECgQIBAAAAA==.Thndrwzrd:BAAANQADCgYIBgAAAA==.Thorphan:BAAANQAECgQIBAAAAA==.',
Ti='Ticho:BAAANQADCggIDQAAAA==.',
Tr='Treygec:BAAANQADCgUIBgAAAA==.Tribolonotus:BAAANQADCgQIBQAAAA==.Trujal:BAAANQAECgEIAQAAAA==.',
Tu='Turdmonk:BAAANQADCgcICwAAAA==.',
Ty='Typhon:BAAANQAECgEIAQAAAA==.',
Un='Unclebób:BAAANQADCgYIDAABNQAECgEIAQABAAAAAA==.',
Va='Vaeshta:BAAANQADCggIDgAAAA==.Valhallarama:BAAANQAECgIIAgAAAA==.Vampy:BAAANQADCgcIBwAAAA==.',
Ve='Vexxya:BAAANQADCgQIAwAAAA==.',
Vl='Vladus:BAAANQADCggIDwAAAA==.',
Vy='Vyllian:BAAANQADCggIDgAAAA==.',
Wa='Wangwang:BAAANQADCgQIBgAAAA==.Wareshesh:BAAANQADCgIIAgAAAA==.Warlakaflaka:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
Wh='Whale:BAAANQADCgcIDQAAAA==.',
Wi='Windfury:BAAANQAECgMIAwAAAA==.Windfuryous:BAAANQADCgUIBQAAAA==.Winston:BAAANQADCgQIBAAAAA==.',
Wo='Wolfsbane:BAAANQADCgYIBgAAAA==.Wonpiece:BAAANQADCgQIBgABNQAECgUICAABAAAAAA==.',
Wy='Wylestrean:BAAANQAECgEIAQAAAA==.',
Xi='Xiaomao:BAEANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Ye='Yeinn:BAAANQAECgQIBAAAAA==.',
Za='Zandalarthas:BAAANQADCgYIDAAAAA==.',
Zc='Zcredo:BAAANQADCggICwAAAA==.',
Ze='Zel:BAAANQADCgYICwAAAA==.Zentradei:BAAANQADCgQIBAAAAA==.',
Zi='Zieganfuss:BAAANQAECgMIBAAAAA==.',
Zo='Zoho:BAAANQAECgUIBwAAAA==.',
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
