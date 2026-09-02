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

local lookup = {'Unknown-Unknown','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Hunter-BeastMastery','Monk-Mistweaver','Paladin-Holy','DemonHunter-Devourer','Paladin-Protection','Shaman-Restoration','Mage-Arcane','Mage-Frost',}
local provider = {region='US',realm="Khaz'goroth",name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abaddom:BAAANQAECgEIAQAAAA==.Abassa:BAAANQADCgIIAgAAAA==.Abyssalblade:BAAANQAECgUIBgAAAA==.Abyssia:BAAANQADCgcIDQAAAA==.',
Ac='Ackwah:BAAANQAECgQICAAAAA==.Actaeön:BAAANQADCgcIDQAAAA==.Acupuncher:BAAANQAECgEIAgAAAA==.Acutar:BAAANQADCgYIEgAAAA==.',
Ad='Adeemo:BAAANQAECgEIAQAAAA==.Adrielar:BAAANQADCgMIAwAAAA==.Adámant:BAAANQAECgYICAAAAA==.',
Ae='Aedd:BAAANQADCgYIBgAAAA==.Aeirra:BAAANQAECgMIBgAAAA==.Aengima:BAAANQADCgEIAQAAAA==.Aestryn:BAAANQAECgEIAQAAAA==.',
Ah='Ahsokatano:BAAANQAECgIIAgAAAA==.',
Ai='Aillie:BAAANQAECgMIAwAAAA==.Aizmirst:BAAANQADCgYICwAAAA==.',
Al='Alarÿ:BAAANQAECgMIAwAAAA==.Aldrettius:BAAANQADCggIDwABNQAECgQIBgABAAAAAA==.Aldrêttius:BAAANQAECgQIBgAAAA==.Alexandrion:BAAANQADCgQIBAAAAA==.Algove:BAAANQADCgUICQAAAA==.Alicity:BAAANQADCgYICwAAAA==.Alkyrie:BAAANQAECgIIBAAAAA==.Alleiria:BAAANQAECgYICQAAAA==.Allhammer:BAAANQADCgYIBwAAAA==.Alliiran:BAAANQAECgQIBQAAAA==.Alphônse:BAAANQADCgcIDQAAAA==.Alucârd:BAAANQADCggIDwAAAA==.Alumar:BAAANQADCgcIBwAAAA==.Aléus:BAAANQAECgQIBAAAAA==.',
Am='Amyn:BAAANQADCgYIBgAAAA==.',
An='Anane:BAAANQADCgYICwAAAA==.Anasteriian:BAAANQADCgMIAwAAAA==.Angelism:BAAANQAECgcIBwAAAA==.Anine:BAAANQAECgEIAQAAAA==.Anketell:BAAANQAECgUIBgAAAA==.Annkulotz:BAAANQADCggICgAAAA==.Anohti:BAAANQADCgYIBgAAAA==.Antoranthree:BAAANQAECgYICgAAAA==.',
Ap='Aphasiawye:BAAANQAECgQIBAAAAA==.Apocryphal:BAAANQAECgEIAQAAAA==.Apopshunter:BAAANQAECgEIAQAAAA==.',
Ar='Araiak:BAAANQAECgQIBAABNQAECgcIDQABAAAAAA==.Araiakk:BAAANQAECgcIDQAAAA==.Arakz:BAAANQAECgIIAgAAAA==.Arallia:BAAANQAFFAEIAQAAAA==.Arallija:BAAANQAECgIIAgAAAA==.Arbrack:BAAANQAECgEIAQAAAA==.Arch:BAAANQAECgMIAwAAAA==.Areaky:BAAANQADCgcIEgAAAA==.Arianamarie:BAAANQAECgQIBAAAAA==.Arkdrood:BAAANQAECgQIBAAAAA==.Arkinup:BAAANQADCgYIDgAAAA==.Arrowrin:BAAANQADCgUIBQAAAA==.',
As='Asasia:BAAANQADCgYIDAAAAA==.Aserlock:BAAANQADCgQIAwAAAA==.Aserpala:BAAANQADCgYIBgAAAA==.Ashalune:BAAANQADCggIDQAAAA==.Ashanormu:BAAANQADCgUIBQAAAA==.Ashendary:BAAANQAECgQIBQAAAA==.Asterisk:BAAANQABCgQIBAAAAA==.',
At='Atchias:BAAANQADCgcIDQAAAA==.Aths:BAAANQAECgEIAQAAAA==.Attachedsham:BAAANQAECgQIBQAAAA==.Attís:BAAANQADCgYIBgAAAA==.',
Au='Auroraknight:BAAANQADCgYIBgAAAA==.Aussyey:BAAANQAECgYIBQAAAA==.Autumnbury:BAAANQADCgUIBQAAAA==.',
Ay='Aytrune:BAAANQADCgcIDQAAAA==.',
Az='Azaraler:BAAANQAECgQIBQAAAA==.Azraelor:BAAANQADCggICAAAAA==.Azraiel:BAAANQAECgMIAwAAAA==.Azureuz:BAAANQAECgIIAgAAAA==.',
Ba='Baalz:BAAANQADCgYICwAAAA==.Backhair:BAAANQAECgcIDgAAAA==.Badimps:BAAANQADCgYIBgABNQAECgcIDQABAAAAAA==.Badsham:BAAANQAECgcIDQAAAA==.Badtóuch:BAAANQAECgQIBQAAAA==.Baelfoar:BAAANQAECgEIAQAAAA==.Baindage:BAAANQAECgQICAAAAA==.Baininator:BAAANQADCggIDgABNQAECgQICAABAAAAAA==.Baj:BAAANQAECgcIDQAAAA==.Balock:BAAANQAECgMIAwAAAA==.Balthamael:BAAANQADCgYICQAAAA==.Banoffi:BAAANQADCgYIDgAAAA==.Baptism:BAAANQAECgIIBAAAAA==.Barabel:BAAANQADCgIIAgAAAA==.Barfonimous:BAAANQADCgQIBQAAAA==.Barrazza:BAAANQABCgEIAQAAAA==.Barricade:BAAANQADCgUIBQAAAA==.Bashath:BAAANQADCgYIBwAAAA==.Batboi:BAAANQADCgcIBwAAAA==.',
Bb='Bbora:BAAANQADCgcICgAAAA==.',
Be='Bearbottom:BAAANQADCgcIDAAAAA==.Bearicade:BAAANQADCggIDwAAAA==.Beewe:BAAANQADCgIIAgAAAA==.Belanguis:BAAANQADCggIDgAAAA==.Beni:BAAANQADCgYICwAAAA==.Bennimaru:BAAANQADCgYIBgAAAA==.',
Bi='Bidzz:BAAANQADCggIDQAAAA==.Binchikin:BAAANQAECgEIAgAAAA==.',
Bl='Blackscale:BAAANQADCgcIDQAAAA==.Bladeygaga:BAAANQADCgcICwAAAA==.Blarrg:BAAANQADCggIDgAAAA==.Blazedk:BAAANQADCgIIAgAAAA==.Blazingdeath:BAAANQAECgIIAgAAAA==.Blazon:BAAANQADCggICAAAAA==.Bloodednuzz:BAAANQAECgEIAQAAAA==.Bluntaxe:BAAANQADCgQIBAAAAA==.',
Bo='Boland:BAAANQADCggIDQAAAA==.Bombeeky:BAAANQADCgYICgAAAA==.Boodsy:BAAANQADCgcIBwAAAA==.Booshti:BAAANQADCgYIDAABNQAECgUIBgABAAAAAA==.Bosora:BAAANQADCgYIBgABNQAECgUIBQABAAAAAA==.Boulvar:BAAANQABCgEIAQAAAA==.',
Br='Brahmin:BAAANQADCgEIAQAAAA==.Braingap:BAAANQAECgEIAQAAAA==.Brandooni:BAAANQADCgEIAQAAAA==.Brewdk:BAAANQADCggICgABNQAECgEIAQABAAAAAA==.Brodeadious:BAAANQADCggIDAAAAA==.Brotherdrood:BAAANQADCgIIAgAAAA==.Brotherdwarf:BAAANQAECgMIAwAAAA==.Brunetta:BAAANQAECgIIAgAAAA==.Brynhîldr:BAAANQADCgYICAAAAA==.',
Bu='Bumblbea:BAAANQADCgcIDAAAAA==.Buncicle:BAAANQADCggICAABNQAECgUICAABAAAAAA==.Bundycat:BAAANQAECgIIAgAAAA==.Bunnifer:BAAANQAECgIIAgABNQAECgUICAABAAAAAA==.Bunsxo:BAAANQAECgUICAAAAA==.Burno:BAAANQADCggIDAABNQAECgcIBwABAAAAAA==.',
['Bé']='Béørn:BAAANQADCgcIDQAAAA==.',
['Bï']='Bïill:BAAANQADCgUIBQAAAA==.',
['Bò']='Bòggie:BAAANQAFFAEIAQAAAA==.',
Ca='Cadburychomp:BAAANQAECgUIBQAAAA==.Caedaari:BAAANQADCggICAAAAA==.Cairos:BAAANQADCgcIDQAAAA==.Caldaemon:BAAANQAECgEIAQAAAA==.Caothanis:BAAANQADCgYICgAAAA==.Caphalor:BAAANQAECgIIAgAAAA==.Captinjack:BAAANQADCgYIBwAAAA==.Carawar:BAAANQAECgYICAAAAA==.Carámel:BAAANQADCggICgAAAA==.Catgirltamer:BAAANQADCgYICwAAAA==.Cayder:BAAANQADCggIDQAAAA==.Cayether:BAAANQAECgEIAQAAAA==.Cayneth:BAAANQADCgYICwAAAA==.',
Ce='Celarelia:BAAANQADCgQIBAAAAA==.Celestiallok:BAAANQAECgQIBAAAAA==.Celestlmage:BAAANQAECgYIDAAAAA==.Celorimran:BAAANQAECgEIAgAAAA==.Cementhead:BAAANQADCgMIAwAAAA==.Cerebral:BAAANQAECgQIBAAAAA==.Cesspool:BAAANQAECgIIBgAAAA==.Cesspools:BAAANQADCgYIEAABNQAECgIIBgABAAAAAA==.Cettie:BAAANQAECgEIAQAAAA==.',
Ch='Cheddar:BAAANQAECgYIBgAAAA==.Chirpeh:BAAANQAECgIIAgAAAA==.Choodmarani:BAAANQAECgIIBAAAAA==.Choofa:BAAANQADCggIDgAAAA==.Choppingdmg:BAAANQAECgEIAQAAAA==.Chordatan:BAAANQADCggIDQAAAA==.Chrónos:BAAANQAECgcIDQABNQAFFAEIAQABAAAAAA==.',
Ci='Cindafella:BAAANQAECgEIAQAAAA==.',
Cl='Clareitheria:BAAANQADCgYICAAAAA==.Clarkson:BAAANQAECgEIAQAAAA==.',
Co='Combustya:BAAANQADCggICAAAAA==.Conjuredmilk:BAAANQADCgcIDAAAAA==.Coode:BAAANQADCgIIAgAAAA==.Cowvid:BAAANQAECgQIBAAAAA==.',
Cr='Crawford:BAAANQAECgIIAgAAAA==.Crimz:BAAANQADCgYICwAAAA==.Crispi:BAAANQAECgMIBQAAAA==.',
Cu='Cucu:BAAANQAECgIIBAAAAA==.Cultured:BAAANQADCgcIBwABNQAECgQICgABAAAAAA==.',
Da='Daddyhands:BAAANQADCgQIBAAAAA==.Daddylua:BAAANQAECgIIBQAAAA==.Daeshim:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Dahlila:BAAANQADCgcIDAAAAA==.Dakila:BAAANQADCgMIAwAAAA==.Damahs:BAAANQADCggIDQAAAA==.Dangao:BAAANQAECgIIAgAAAA==.Dareapa:BAAANQAECgEIAQAAAA==.Darkasha:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.Darkburn:BAAANQADCgQIBgAAAA==.Darksõul:BAAANQADCgYICwAAAA==.Darktiger:BAAANQADCgUIBwAAAA==.Darrant:BAAANQADCgYICwAAAA==.Darthdecimus:BAAANQADCgQIBAAAAA==.Dawarlord:BAAANQADCggIBAAAAA==.',
De='Deadseye:BAAANQADCgMIAwAAAA==.Deadthan:BAAANQADCggIDgAAAA==.Deathshnd:BAAANQADCggICQAAAA==.Deathxpress:BAAANQAECgcIDAAAAA==.Deathyeet:BAAANQADCgYIBgAAAA==.Debrad:BAAANQADCgYIEgAAAA==.Deewizz:BAAANQAECgYICgAAAA==.Defance:BAAANQADCgYICgAAAA==.Deff:BAAANQAECgEIAQAAAA==.Demonexpress:BAAANQADCgYICwAAAQ==.Demonicbacon:BAAANQADCgcIEgAAAA==.Denifer:BAAANQADCgUIBQAAAA==.Denona:BAAANQAECgQICAAAAA==.Dermeister:BAAANQADCgYIBgAAAA==.Desumasuku:BAAANQADCgcIDQAAAA==.Deverel:BAAANQADCgUIBQAAAA==.Dexx:BAAANQADCgYIBgAAAA==.',
Di='Diabellstar:BAAANQAECgcIDQAAAQ==.Dinoraa:BAAANQADCgQIBgAAAA==.Disolve:BAAANQADCgIIAgAAAA==.Disrupt:BAAANQADCgIIAwAAAA==.',
Do='Doll:BAAANQADCgUICAAAAA==.Dolock:BAABNQAECoEdAAQCAAkJ3hyHBQB9AgACAAcJfR+HBQB9AgADAAQJORJuBADYAAAEAAIJBRbqPwCCAAAAAA==.Dotless:BAAANQADCgYICwAAAA==.Doubleclicks:BAAANQAECgQIBAAAAA==.',
Dr='Drabsham:BAAANQADCgYIBgAAAA==.Drawlin:BAAANQADCgYIBgAAAA==.Drexil:BAAANQADCggIDgAAAA==.Drool:BAAANQADCgQIBgAAAA==.Druidnique:BAAANQADCgMIAwAAAA==.Drulari:BAAANQAECgIIBAAAAA==.Drzoiidburg:BAAANQADCgYIBgAAAA==.',
Du='Dulfbron:BAAANQADCgYIBgAAAA==.',
Dw='Dwaynage:BAAANQAECgEIAQAAAA==.Dwayne:BAAANQAFFAEIAQAAAA==.',
Dy='Dynamike:BAAANQADCgYIEQABNQAECgEIAQABAAAAAA==.Dysstatíc:BAAANQAECgEIAQAAAA==.Dysturbia:BAAANQADCgYIBgAAAA==.',
['Dú']='Dúza:BAAANQADCgQIBQAAAA==.',
Eg='Egadazor:BAAANQADCgYICwAAAA==.',
Ei='Einbroch:BAAANQADCgYICwAAAA==.',
Ek='Ekarus:BAAANQABCgIIAgAAAA==.',
El='Elementalex:BAAANQAECgcIDQAAAA==.Eletea:BAAANQAECgUIBgAAAA==.Elijahangel:BAAANQADCgcIDAAAAA==.Elinera:BAAANQADCggIEAAAAA==.Elissanora:BAAANQAECgEIAQAAAA==.Ellouise:BAAANQADCgYIDAAAAA==.Elsiie:BAAANQADCgIIAgAAAA==.Elså:BAAANQAECgUICgAAAA==.Elviscious:BAAANQADCgcIDQAAAA==.Elåin:BAAANQADCgcICwAAAA==.',
En='Enzenia:BAAANQADCgcICwAAAA==.',
Er='Eranei:BAAANQAECggIDgAAAA==.Erimira:BAAANQADCgYIBgAAAA==.Ershim:BAAANQAECgQIBAAAAA==.Erzå:BAAANQAECgQIBQAAAA==.',
Es='Espexie:BAAANQADCgYICwAAAA==.',
Et='Etharien:BAAANQADCgIIAgAAAA==.',
Ev='Evilchicken:BAAANQADCgYIBgAAAA==.Evistrianza:BAEANQADCgYIDAAAAA==.Evokaderp:BAAANQADCgUICgAAAA==.Evonehence:BAAANQAECgIIBAAAAA==.',
Ey='Eyoker:BAAANQADCgcIDQAAAA==.',
Ez='Ezarscarlet:BAAANQAECgIIAgAAAA==.',
Fa='Faragon:BAAANQADCgYICQAAAA==.Fareeha:BAAANQADCgUIBQAAAA==.Fatalkink:BAAANQADCgYICwAAAA==.Faultea:BAAANQAECgQIBAAAAA==.Fayleaves:BAAANQAECgIIAgAAAA==.',
Fe='Felmaho:BAAANQADCgEIAQAAAA==.Felphrena:BAAANQADCgYIBgAAAA==.Fembar:BAAANQADCgEIAQAAAA==.Feralaz:BAAANQADCgQIBAAAAA==.',
Fi='Finchy:BAAANQAECgMIAwABNQADCgUIBQABAAAAAA==.Fistivity:BAAANQADCgIIAgAAAA==.Fistysmash:BAAANQADCgIIAgAAAA==.',
Fl='Flëäbäg:BAAANQADCggIDAAAAA==.',
Fo='Forkenslag:BAAANQADCgIIAgAAAA==.Fortiarrows:BAAANQADCgQIBAABNQAECgUIBQABAAAAAA==.Fortiforms:BAAANQAECgUIBQAAAA==.Foshankai:BAAANQADCgcIBwAAAA==.Foxychax:BAAANQAECgQIBwAAAA==.',
Fr='Frankdpriest:BAAANQABCgIIAgABNQABCgQIBAABAAAAAA==.Frip:BAAANQAECgUIBwAAAA==.Friskmage:BAAANQADCggIDgAAAA==.Frisky:BAAANQAFFAEIAQAAAA==.Frodobaggíns:BAAANQADCgUIBwAAAA==.',
Fu='Furey:BAAANQAECgQIBAAAAA==.Furf:BAAANQAECgEIAQAAAA==.',
['Fá']='Fáitalïty:BAAANQADCgUIBwAAAA==.',
['Fæ']='Fæhecate:BAAANQADCgYIBgAAAA==.',
Ga='Gaberiella:BAAANQAECgEIAQAAAA==.Gadodin:BAAANQADCgcIDQAAAA==.Galidiirn:BAAANQAECgQICgAAAA==.Galila:BAAANQADCggIDQAAAA==.Galinaedra:BAAANQABCgIIAgAAAA==.Gallade:BAAANQADCgIIAgABNQAECgQICgABAAAAAA==.Galnddrael:BAAANQADCgIIAgAAAA==.Gayfrost:BAAANQADCgUIBQAAAA==.',
Ge='Geoði:BAAANQADCgYICgAAAA==.',
Gh='Ghosterhunte:BAAANQADCgQIBAAAAA==.Ghunne:BAAANQADCgcIDQAAAA==.',
Gi='Gisella:BAAANQADCgcIBwAAAA==.',
Gl='Glenn:BAAANQADCgYIBAABNQAECggIDgABAAAAAA==.',
Go='Goatley:BAAANQABCgQIBgAAAA==.Gobbledoc:BAAANQADCgYIDwAAAQ==.Goblane:BAAANQAECgEIAQAAAA==.Gokakyu:BAAANQADCgUIAgAAAA==.Goobydh:BAAANQAECgcIDQAAAA==.',
Gr='Gralin:BAAANQAECgEIAQAAAA==.Grampy:BAAANQADCgYIBgAAAA==.Grandioso:BAAANQAECgIIAgAAAA==.Gregorc:BAAANQADCggIDgAAAA==.Grimzdemon:BAAANQADCgYICgAAAA==.Grumblebeard:BAAANQADCgYICwAAAA==.',
Gu='Guff:BAAANQADCggIIAAAAA==.Guilia:BAAANQABCgQIBAAAAA==.Guldann:BAAANQADCgcICgAAAA==.Gunstein:BAAANQADCggIDQAAAA==.',
['Gå']='Gål:BAAANQAECgEIAQAAAA==.',
['Gõ']='Gõatçheesed:BAAANQADCgMIAwABNQADCgUIBwABAAAAAA==.',
Ha='Hadlé:BAAANQAECgMIAwAAAA==.Hailthelight:BAAANQAECgYICgAAAA==.Hannelore:BAAANQAECgEIAQAAAA==.Happyissues:BAAANQADCgIIAgAAAA==.Happypallie:BAAANQADCgQIBAAAAA==.Haymawty:BAAANQAECgEIAQAAAA==.',
He='Helea:BAAANQADCgQIBAABNQADCgUIBQABAAAAAA==.Heliosax:BAAANQAECgIIBAAAAA==.Helpfllgirl:BAAANQADCgcICwAAAA==.Hemardest:BAAANQADCgMIAgAAAA==.Henlas:BAAANQADCggICAAAAA==.Heraklees:BAAANQADCgIIAgAAAA==.Hezzadem:BAAANQADCgcIDQAAAA==.',
Hi='Hilam:BAAANQABCgIIAgAAAA==.',
Ho='Holycheet:BAAANQADCgcIDQAAAA==.Holyderki:BAAANQAECgYICgAAAA==.Holyleah:BAAANQAECgEIAgAAAA==.Holypoonz:BAAANQAECgEIAQAAAA==.Hontar:BAAANQADCgYIBgAAAA==.Hornlulz:BAAANQADCgYIDAABNQAECgIIBAABAAAAAA==.Howzaboot:BAAANQAECgQIBAAAAA==.',
Hu='Hunteradam:BAAANQADCgUIBwAAAA==.Hunterchickn:BAABNQAECoEcAAIFAAgJGRncBgCxAgAFAAgJGRncBgCxAgAAAA==.Huntericles:BAAANQADCgYIBgAAAA==.',
Hy='Hyperxd:BAAANQADCgcIDQAAAA==.',
Ia='Iamhisalt:BAAANQADCgYIEAAAAA==.Iamnohealer:BAAANQAECgIIAgAAAA==.Iarebingbong:BAAANQAECgIIAgAAAA==.',
Id='Idontparsee:BAAANQADCgQICAABNQAECgQIBgABAAAAAA==.',
Ig='Igzi:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Igzyy:BAAANQAECgIIAgAAAA==.',
Ik='Ikahsia:BAAANQADCgUICgAAAA==.',
Il='Illaiya:BAAANQADCgUICAAAAA==.Illish:BAAANQADCggIDgABNQABCgQIBAABAAAAAA==.',
In='Interlude:BAAANQAECgMIAwAAAA==.',
Is='Isc:BAAANQADCgYIBgAAAA==.Isobel:BAAANQADCgYIBgAAAA==.Issac:BAAANQAECgMIBwAAAA==.Isuckatmage:BAAANQAECgYICgAAAA==.',
Iv='Ivenate:BAAANQAECgEIAQAAAA==.Ivesham:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Ja='Jaarrius:BAAANQAECgMIAwAAAA==.Jacho:BAAANQADCggICAAAAA==.Jacian:BAAANQADCgcIDQAAAA==.Jackiee:BAAANQAECgIIBAAAAA==.Jailbreaktau:BAAANQADCggIDQAAAA==.Jailshifter:BAAANQADCgYICgAAAA==.Jakethesully:BAABNQAECoEcAAIGAAgJih4IAgDsAgAGAAgJih4IAgDsAgAAAA==.Jakharo:BAAANQADCgYICgAAAA==.Jakto:BAAANQADCgUIBQABNQAECgIIBgABAAAAAA==.Jallta:BAAANQADCgIIAgAAAA==.Janjan:BAAANQADCgQIBAAAAA==.Javinda:BAAANQADCgcIDQAAAA==.Jayze:BAAANQADCgYICQAAAA==.Jaênellê:BAABNQAECoEWAAIHAAcJAQlvHgCbAQAHAAcJAQlvHgCbAQAAAA==.',
Je='Jenkies:BAAANQAECgEIAQAAAA==.',
Ji='Jimbajumba:BAAANQAECgMIAwAAAA==.',
Jo='Jodaniki:BAAANQAECgMIAwAAAA==.Johnygoodboi:BAAANQAECgQIBQAAAA==.',
Ju='Justaddwater:BAAANQADCgYICwABNQADCgUICwABAAAAAA==.Justinlaw:BAAANQADCgUICgAAAA==.',
['Já']='Jáyden:BAAANQAECgIIAwAAAA==.',
['Jó']='Jónsí:BAAANQAECgIIAgAAAA==.',
Ka='Kaeel:BAAANQADCgMIAwAAAA==.Kaichrome:BAAANQADCgcIDQAAAA==.Kaidy:BAAANQADCgcIEwAAAA==.Kalathar:BAAANQADCgcIDAAAAA==.Kalixte:BAAANQABCgMIAwABNQADCgcIDAABAAAAAA==.Kamegedon:BAAANQADCgYICQAAAA==.Kameline:BAAANQADCgYICwAAAA==.Kangarang:BAAANQADCgQICAAAAA==.Kanoo:BAAANQAECgEIAQAAAA==.Karou:BAAANQADCgYIBgAAAA==.Karrmaa:BAAANQADCgcICwAAAA==.Katalyna:BAAANQADCgYICAAAAA==.Kathyhilton:BAAANQADCgQIBAAAAA==.Kavedon:BAAANQADCgEIAQAAAA==.Kavis:BAAANQADCgYIBgAAAA==.Kaylehuntz:BAAANQADCgQIAwAAAA==.',
Ke='Keanubreaths:BAAANQADCgQIBAAAAA==.Keary:BAAANQADCgYIEgAAAA==.Kerza:BAAANQADCggIDwAAAA==.Kettlechip:BAAANQADCgcICgAAAA==.Keyalien:BAAANQADCgMIAwAAAA==.',
Kh='Khioracle:BAAANQADCgYICAAAAA==.',
Ki='Kicka:BAAANQAECgEIAgAAAA==.Kiele:BAAANQADCggIDwAAAA==.Killhunter:BAAANQADCgMIAwAAAA==.Kinyo:BAAANQADCgYICAAAAA==.Kirdin:BAAANQAECgMIAwAAAA==.Kitcatt:BAAANQADCgYICAAAAA==.',
Kl='Klawbringer:BAAANQADCgYICQAAAA==.Klystara:BAAANQADCgcIDQAAAA==.',
Ko='Kortlexx:BAAANQAECgQIBAABNQAECgcIDQABAAAAAA==.',
Kr='Kriela:BAAANQAECgUICAAAAA==.Krispen:BAAANQAECgMIAwAAAA==.Kryptiposd:BAAANQAECgcIDQAAAA==.',
Ku='Kumitsu:BAAANQAECgIIBAAAAA==.Kuralei:BAAANQADCgcICwAAAA==.Kushlack:BAAANQADCggIDQAAAA==.',
Ky='Kyrnea:BAAANQADCgYIBgAAAA==.Kytheon:BAAANQAECgQIBQAAAA==.',
['Ká']='Káèl:BAAANQADCggICAABNQAECgQICQABAAAAAA==.',
['Kã']='Kãylee:BAAANQADCgcIDQAAAA==.Kãêl:BAAANQADCggICAABNQAECgQICQABAAAAAA==.',
['Kä']='Käèl:BAAANQAECgQICQAAAA==.',
['Kí']='Kíhí:BAAANQAECgMIAwAAAA==.Kíntor:BAAANQAECgEIAQAAAA==.',
La='Ladeliana:BAAANQAECgQIBgAAAA==.Ladorill:BAABNQAECoEXAAIIAAgJ+hOkDwAGAgAIAAgJ+hOkDwAGAgAAAA==.Laliaquest:BAAANQADCgQIBQAAAA==.Lallorona:BAAANQADCgQIBAAAAA==.Lanyue:BAAANQADCgQIBAAAAA==.Larcenciel:BAAANQAECgQICAAAAA==.Lathus:BAAANQADCggICAAAAA==.Laudde:BAEANQAECgIIBAAAAA==.',
Le='Leicapanda:BAAANQADCgMIAwAAAA==.Leighen:BAAANQADCgYICwAAAA==.Lembah:BAAANQADCgYICgAAAA==.Lemony:BAAANQADCggICwAAAA==.Lempal:BAAANQADCgEIAQAAAA==.Leonìdas:BAAANQADCgUIBQAAAA==.Lexiness:BAAANQADCgcIDAAAAA==.Leylithia:BAAANQADCgYIBgAAAA==.',
Li='Lilavo:BAAANQADCgYICAABNQAECgQIBQABAAAAAA==.Lili:BAAANQADCgYIBgAAAA==.Lilnib:BAAANQAECgIIAgAAAA==.Limm:BAAANQADCgMIAwAAAA==.Limmortalk:BAAANQAECgQIBAAAAA==.Litewave:BAAANQAECgEIAQAAAA==.Littlebomm:BAAANQADCggICAABNQADCggICAABAAAAAA==.Littlemel:BAAANQADCgcIDQAAAA==.Lizardoor:BAAANQABCgIIAgAAAA==.',
Lo='Lockstok:BAAANQABCgIIAgAAAA==.Lokai:BAAANQAECgUIBwAAAA==.Longicorn:BAAANQAECgUICQAAAA==.Lookthatway:BAAANQADCggIDgAAAA==.Loott:BAAANQADCgYIBgAAAA==.',
Lr='Lrelia:BAAANQAECgcIDQAAAA==.',
Lu='Lukaryn:BAAANQAECgEIAQAAAA==.Lukusmaximus:BAAANQAFFAEIAQAAAA==.Lummos:BAAANQADCgcIBwAAAA==.Lunaxwar:BAAANQAECgEIAgAAAA==.Lunch:BAAANQAECgEIAQAAAA==.Lungerie:BAAANQAECgIIAgAAAA==.Lurts:BAAANQADCgQIBAAAAA==.Lusserina:BAAANQADCgYIBgAAAA==.Lustaen:BAAANQADCgUICgAAAA==.Lustiun:BAAANQAECgIIBQAAAA==.Luviana:BAAANQADCgcIDAAAAA==.Luvstaspooje:BAAANQAECgIIBAAAAA==.',
Ly='Lyll:BAAANQAFFAEIAQAAAA==.Lynborough:BAAANQADCgYICwAAAA==.Lyndaks:BAAANQADCgUICQAAAA==.',
Ma='Maalus:BAAANQADCgcIEwAAAA==.Machlin:BAAANQADCgYICgAAAA==.Madalgerca:BAAANQADCgQIBwAAAA==.Maddi:BAAANQAECgEIAgAAAA==.Madlorekeep:BAAANQAFFAEIAQAAAA==.Madmaorid:BAAANQAFFAEIAQAAAA==.Madoren:BAABNQAECoEcAAIJAAgJDg6mBQDYAQAJAAgJDg6mBQDYAQAAAA==.Magibloopa:BAAANQAECgYICQAAAA==.Mahy:BAAANQAECgEIAQAAAA==.Majel:BAAANQADCgYIDAAAAQ==.Makikun:BAAANQAECgQIBQAAAA==.Malerris:BAAANQAECgIIBAAAAA==.Maliae:BAAANQADCgcIDQAAAA==.Malithyus:BAAANQADCgcIDAAAAA==.Mammonite:BAAANQADCggIDwAAAA==.Manastealeaf:BAAANQAECgIIBgAAAA==.Manginahead:BAAANQADCgUIBQAAAA==.Matheral:BAAANQADCgUIBwAAAA==.Matoaka:BAAANQADCgEIAQAAAA==.Matpriest:BAAANQADCgYICwAAAA==.Matspriest:BAAANQADCggICAAAAA==.Mavmeow:BAAANQADCgYICAAAAA==.',
Mc='Mchammasmash:BAAANQADCgMIAwAAAA==.Mclusky:BAAANQAECgIIBAAAAA==.',
Me='Medi:BAAANQADCgYIBgAAAA==.Meeran:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Megaclite:BAAANQADCgMIAwAAAA==.Meirdris:BAAANQAECgMIAwAAAA==.Melinaya:BAAANQADCgIIAgAAAA==.Melissà:BAAANQAECgQIBAAAAA==.Melora:BAAANQADCggICAAAAA==.Meltonjohn:BAAANQADCgMIAwAAAA==.Metalwar:BAAANQAECgYICQAAAA==.',
Mi='Midnightdove:BAAANQADCgYICgAAAA==.Mikeo:BAAANQADCgUIBQAAAA==.Milesysmash:BAAANQADCggIDQAAAA==.Minifrost:BAAANQADCgYIDAAAAA==.Miotas:BAAANQADCgYICgAAAA==.Miracydia:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Mishkaa:BAAANQAECgEIAgAAAA==.Mistfist:BAAANQADCgYIBgAAAA==.Mistq:BAAANQADCgYIEgAAAA==.Mittyree:BAAANQADCgcIEgAAAA==.Mixer:BAAANQAECgQIBgAAAA==.Mizuiro:BAAANQADCgYIBgAAAA==.',
Mo='Moirain:BAABNQAECoEcAAIKAAgJKRkoCgBkAgAKAAgJKRkoCgBkAgAAAA==.Monkeymagìc:BAAANQADCgcIDQAAAA==.Monotron:BAAANQAECgIIBAAAAA==.Moodrown:BAAANQAECgMIAwAAAA==.Moogh:BAAANQADCgUIBQAAAA==.Moonieezz:BAAANQAECgQIBAAAAA==.Moonniiee:BAAANQADCggICgAAAA==.Morgäna:BAAANQAECgQIBgAAAA==.Morte:BAAANQADCgIIAgAAAA==.Mouseybrew:BAAANQAECgEIAQAAAA==.',
Mt='Mtisaelf:BAAANQADCgYICwAAAA==.',
My='Myrlidoran:BAAANQADCgYIBgABNQAECgIIBgABAAAAAA==.Mythdiirus:BAAANQADCgYICgAAAA==.',
['Må']='Måtcoss:BAAANQADCgQIBAABNQADCgYICwABAAAAAA==.',
['Më']='Mërlin:BAAANQADCggIDQAAAA==.',
Na='Nanageddon:BAAANQAECgIIBAAAAA==.Narinutogar:BAAANQADCgIIAgAAAA==.Narsilion:BAAANQADCgYICAAAAA==.Nastazia:BAAANQADCgYICwABNQADCgcIDQABAAAAAA==.Nasthvel:BAAANQADCgYICQAAAA==.Naykaido:BAAANQAECgEIAQAAAA==.Nazarene:BAAANQADCgQIBAAAAA==.Nazzgul:BAAANQADCgUIBgAAAA==.',
Ne='Nedorshock:BAAANQAECgEIAQAAAA==.Neinah:BAAANQADCgcIDQAAAA==.Neirdra:BAAANQADCggIDQAAAA==.Nemises:BAAANQADCgUICQABNQAECgEIAQABAAAAAA==.Neralith:BAAANQADCgcICwAAAA==.Nerv:BAAANQADCgYICwAAAA==.Netimerin:BAAANQAECgIIBgAAAA==.Nezrai:BAAANQAECgIIAwAAAA==.',
Ni='Nicet:BAAANQAECgMIAwAAAA==.Ninannunaki:BAAANQADCgUIBQABNQADCgcICwABAAAAAA==.',
No='Noncultured:BAAANQADCgYIBgABNQAECgQICgABAAAAAA==.Normerules:BAAANQAECgEIAQAAAA==.Norsi:BAAANQAECgMIAwAAAA==.Norstraz:BAAANQAECgEIAQAAAA==.Nostrobow:BAAANQADCgMIAwABNQADCgUICQABAAAAAA==.Nostromo:BAAANQADCgUICQAAAA==.Nouvy:BAAANQAECgEIAgAAAA==.Novicima:BAAANQADCgYICgAAAA==.',
Nu='Nuz:BAAANQAECgIIBAAAAA==.',
Ny='Nymphea:BAAANQADCggIDgAAAA==.Nyssandria:BAAANQAECgQIBAAAAA==.Nyter:BAAANQADCgYICwAAAA==.',
Nz='Nzswarrior:BAAANQADCgMIAwAAAA==.',
['Nê']='Nêmmza:BAAANQADCgYICQAAAA==.',
Oc='Occultus:BAAANQADCgYICwAAAA==.',
Od='Oddpaladin:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Oddshot:BAAANQAECgIIAgAAAA==.',
Oh='Ohnyxia:BAAANQADCgQIBgAAAA==.',
Oj='Ojlahk:BAAANQAECgEIAQAAAA==.',
Ol='Ollydog:BAAANQADCgUIBQABNQADCggICwABAAAAAA==.Ollywarr:BAAANQADCggICwAAAA==.',
Om='Omnibrew:BAAANQAECggIDgAAAA==.Omnipudge:BAAANQADCggIEAABNQAECggIDgABAAAAAA==.',
Or='Orb:BAAANQAECgYIBwAAAA==.Orceissua:BAAANQADCgYICQAAAA==.',
Ou='Outplagued:BAAANQAECgYICAAAAA==.',
Ow='Owlee:BAAANQAECgEIAQAAAA==.',
Ox='Oxoid:BAAANQAECggIDgAAAA==.',
Pa='Padner:BAAANQAECgEIAQAAAA==.Pain:BAAANQADCgYIBgAAAA==.Palabee:BAAANQADCgUICAABNQADCggICAABAAAAAA==.Palastrifus:BAAANQADCgMIAwAAAA==.Pandafelow:BAAANQAECgMIAwAAAA==.Panpann:BAAANQADCgcIEwAAAA==.Parapet:BAAANQAECgEIAgAAAA==.Parmageddon:BAAANQADCgcIDQAAAA==.Pawsey:BAAANQADCgcIDQAAAA==.',
Pe='Peppermint:BAAANQADCgcIBwAAAA==.Permafrost:BAAANQADCgUIBwAAAA==.Pewershaman:BAAANQADCgYICgAAAA==.',
Ph='Phaeora:BAAANQADCgEIAQAAAA==.Phantomfear:BAAANQADCgIIAgAAAA==.Phatzz:BAAANQADCggICAAAAA==.Philmccrackn:BAAANQADCgQIDAAAAA==.Phyllixia:BAAANQADCgYICwAAAA==.',
Pi='Pididdy:BAAANQAECgIIAgAAAA==.Piffles:BAAANQAECgEIAQAAAA==.',
Po='Polymorphinê:BAAANQAECgUICAABNQABCgIIAgABAAAAAA==.Pondmordial:BAAANQAECgEIAQAAAA==.Popeisnomore:BAAANQADCggIEgAAAA==.',
Pr='Precursor:BAAANQADCgYIEQAAAA==.Priestycro:BAAANQADCgUIBQABNQADCgYICQABAAAAAA==.Primemoover:BAAANQADCgcIDAAAAA==.Prodigyloy:BAAANQAECgIIAgAAAA==.Prodigyloysh:BAAANQAECgQIBAABNQAECgIIAgABAAAAAA==.Prodigyloyz:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Prodigylõy:BAAANQAECgQIBwABNQAECgIIAgABAAAAAA==.',
Ps='Psychedeliah:BAAANQADCgUIBQAAAA==.',
Pu='Puddey:BAAANQAECgIIBAAAAA==.Pumpershot:BAAANQAFFAIIAwAAAA==.Punnisher:BAAANQAECgEIAQAAAA==.Purpleshoes:BAAANQAECgEIAQAAAA==.',
Py='Pyjamish:BAAANQADCgcIDAAAAA==.Pyrolusite:BAAANQADCgQIDgAAAA==.',
['Pá']='Pát:BAAANQAFFAEIAQAAAA==.',
['Pú']='Púddums:BAAANQAECgMIAwAAAA==.',
Qa='Qasida:BAAANQADCgYICwAAAA==.',
Qu='Quaril:BAAANQADCgEIAQAAAA==.Quiksilverx:BAAANQAECgYICgAAAA==.Qutie:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Ra='Radathmor:BAAANQADCgcIDAAAAA==.Raefafa:BAAANQAECgMIAwAAAA==.Raelynddra:BAAANQADCgYIBgAAAA==.Raethena:BAAANQADCgYICAAAAA==.Ragermini:BAAANQAECgIIAgAAAA==.Ragonmibrals:BAAANQADCggIGAAAAA==.Raharlem:BAAANQADCgQICgABNQAECgQIBQABAAAAAA==.Ravenkiller:BAAANQAECgMIAwAAAA==.Ravion:BAAANQADCgYIBgAAAA==.Ravosh:BAAANQADCgYICgAAAA==.Raze:BAEANQAECgQIBAABNQAECgcIDQABAAAAAA==.Razex:BAEANQAECgcIDQAAAA==.Razzmage:BAAANQADCgMIAwAAAA==.Razzpally:BAAANQADCgYIBgAAAA==.',
Re='Realhardcore:BAAANQAECgMIAwAAAA==.Redsolodk:BAAANQADCggIDwAAAA==.Reflexes:BAAANQAECgIIAgAAAA==.Reidon:BAAANQAECgEIAQAAAA==.Reing:BAAANQADCgYIBwAAAA==.Renki:BAAANQADCggIEAAAAA==.Reversehyuki:BAAANQADCgcICwABNQAECgEIAQABAAAAAA==.Reyedrà:BAAANQADCgUICAAAAA==.Rez:BAAANQAECgEIAQAAAA==.Reza:BAAANQAECgEIAQAAAA==.Rezashiver:BAAANQADCgcIDgAAAA==.',
Rh='Rhysana:BAAANQADCgUIBQAAAA==.',
Ri='Riddian:BAAANQADCgYIDAAAAA==.Ripcord:BAAANQADCgcIDAAAAA==.Rishima:BAAANQAECgMIAwAAAA==.',
Ro='Rocinante:BAAANQAECgcICwAAAA==.Rogerramjet:BAAANQADCggIDQAAAA==.Roguenjosh:BAAANQADCgcICQAAAA==.Rol:BAAANQAECgcIDAAAAA==.Rongozhunter:BAAANQAECgUIBgABNQADCgYICAABAAAAAA==.Rongozz:BAAANQADCgYIBgABNQADCgYICAABAAAAAA==.',
Ru='Ruaird:BAAANQAECgEIAQAAAA==.Rubladorhar:BAAANQADCgYICAAAAA==.Rudejin:BAAANQADCgQIBAABNQADCgYICwABAAAAAQ==.Ruleturner:BAAANQADCggIDQAAAA==.Rutiger:BAAANQAECgEIAQAAAA==.Ruwyn:BAAANQADCgYIBgAAAA==.',
Ry='Ryugin:BAAANQADCgYICwAAAA==.',
Sa='Saddragon:BAAANQADCggIDwAAAA==.Saltybird:BAAANQAECgUIBAAAAA==.Saltyjesuzz:BAAANQAECgcIDQAAAA==.Sartharion:BAAANQAECgQIBAABNQAECgkJHQACAN4cAA==.Satanservant:BAAANQAECgEIAQAAAA==.Sax:BAAANQADCgcIDQAAAA==.',
Sc='Scaryheäls:BAEANQADCgcIEwAAAA==.Schmacko:BAAANQAECgEIAQAAAA==.Schooners:BAAANQAECgcIEAAAAA==.Scitolock:BAAANQADCgQIBAAAAA==.Scroopy:BAAANQADCgMIAwAAAA==.',
Se='Semavoidp:BAAANQADCgEIAQAAAA==.Senilia:BAAANQADCgQIBAAAAA==.Serenta:BAAANQADCgcIBwAAAA==.Sermixalot:BAAANQAECgEIAQAAAA==.Serrilia:BAAANQAECgYICQAAAA==.Servmonkage:BAAANQAECgEIAgAAAA==.Sezra:BAAANQAECgIIAgAAAA==.',
Sh='Shabentos:BAAANQADCgcIDQAAAA==.Shadowbrew:BAAANQADCgcIBwAAAA==.Shadyman:BAAANQADCgUIBQAAAA==.Shamfurion:BAAANQADCgcIDQAAAA==.Shamizer:BAAANQAECgEIAQAAAA==.Shammeryy:BAAANQADCgYICAAAAA==.Shamouse:BAAANQAECgYICAAAAA==.Sharmac:BAAANQADCggIDgAAAA==.Sharpslice:BAAANQADCgcIDAAAAA==.Shazåm:BAAANQADCgQIBAAAAA==.Sheit:BAAANQADCgcIBwAAAA==.Shenseea:BAAANQAECgIIBAAAAA==.Sherie:BAAANQAECgIIBgAAAA==.Sherå:BAAANQADCgIIAgAAAA==.Shiftingalex:BAAANQAECgQIBAABNQAECgcIDQABAAAAAA==.Shiiro:BAAANQADCgUIBQAAAA==.Shiok:BAAANQADCgUIBwAAAA==.Shix:BAAANQADCgUIBQAAAA==.Shoniroo:BAAANQADCggIEAAAAA==.Shyntaro:BAAANQADCgIIAgAAAA==.Shádowhound:BAAANQABCgQIBAAAAA==.Shádowshaman:BAAANQABCgMIAwAAAA==.',
Si='Sideslash:BAAANQADCggIDwAAAA==.Signaturez:BAAANQADCgQIBAAAAA==.Silkfeather:BAAANQADCgYICwAAAA==.Siltheren:BAAANQADCgcIDQAAAA==.Silverpink:BAAANQAECgEIAQAAAA==.Sinora:BAAANQAECgMIAwAAAA==.Sitra:BAAANQADCgYICgABNQAECgUIBwABAAAAAA==.',
Sk='Skate:BAAANQADCgQIBAAAAA==.Skatty:BAAANQADCgMIAwAAAA==.Skiadrum:BAAANQADCggICAABNQAECgYICgABAAAAAA==.Skippyx:BAAANQAECgcIEQAAAA==.Skook:BAAANQADCgIIAgABNQAECgIIBgABAAAAAA==.Skyebow:BAAANQADCgIIAgAAAA==.Skyenz:BAAANQABCgMIAQAAAA==.Skyevader:BAAANQADCgYICQAAAA==.Skyraa:BAAANQADCgYICQAAAA==.',
Sl='Sliceyboi:BAAANQADCgcICAAAAA==.Slimkidney:BAAANQADCggIDwAAAA==.Slyclaran:BAAANQADCgQIBAAAAA==.',
Sm='Smôôthy:BAAANQADCgYICQAAAA==.',
Sn='Snollas:BAAANQAECgUICAAAAA==.Snootyjam:BAAANQADCgYIBgAAAA==.Snorkes:BAAANQADCgUIAQAAAA==.Snotbubble:BAAANQADCgYIBgAAAA==.Snowmae:BAAANQADCgcIBwAAAA==.',
So='Solestra:BAAANQAECgIIBAAAAA==.Somethingnew:BAAANQADCggIDQAAAA==.Sonead:BAAANQADCggIDQAAAA==.Sorcxisto:BAAANQADCgUIBQAAAQ==.Sostrate:BAAANQADCgcIBwAAAA==.',
Sp='Spankmybeast:BAAANQADCgYICQAAAA==.Sparkerlee:BAAANQAECgEIAQAAAA==.Spellsteel:BAAANQADCgYIDAAAAA==.Splurtle:BAAANQADCgUIAQAAAA==.Sprayandpray:BAAANQAECgYIDAABNQAFFAYIBwALAHoZAA==.Spraynwipe:BAABNQAFFIEHAAMLAAYJehlLAADxAQALAAUJYRhLAADxAQAMAAEJ+B4iAABpAAAAAA==.',
Sq='Squibler:BAAANQADCgYIBgAAAA==.',
St='Stalidin:BAAANQADCgcIDQAAAA==.Steilgar:BAAANQADCgcIDQAAAA==.Stellaar:BAAANQADCgIIAgAAAA==.Steveybaby:BAAANQAECgIIAgAAAA==.Sticksy:BAAANQAECgIIBAAAAA==.Stormchoice:BAAANQAECgMIAwAAAA==.Strangest:BAAANQADCggIDgAAAA==.Stàrlord:BAAANQADCgcIDgAAAA==.',
Su='Sudno:BAAANQAECgcIDQAAAA==.Sugarmelons:BAAANQADCgIIAgAAAA==.Suntanis:BAAANQADCggIDQAAAA==.Superstorm:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.Supertedd:BAAANQADCgYICwAAAA==.Surger:BAAANQADCgMIAwAAAA==.',
Sv='Svenigmatic:BAAANQADCgcIDQAAAA==.Svårl:BAAANQAECgQIBAAAAA==.',
Sw='Swagmasterr:BAAANQADCgcICAAAAA==.Sweetieman:BAAANQADCgcIDQAAAA==.Swen:BAAANQADCgIIBAAAAA==.',
Sy='Sydneysweeny:BAAANQAECgMIAwAAAA==.Sylliné:BAAANQAECgMIAwAAAA==.Sylphâ:BAAANQADCgIIAgAAAA==.Sylreilea:BAAANQADCggIDgAAAA==.Sylvie:BAAANQADCgYIBgAAAA==.Syranz:BAAANQADCgcIDgAAAA==.',
['Sý']='Sýnyster:BAAANQADCgUIBQAAAA==.',
Ta='Tabachoy:BAAANQADCgYIBgAAAA==.Talanos:BAAANQADCggIDwAAAA==.Talbs:BAAANQAECgMIBwAAAA==.Talbz:BAAANQADCgYIBgAAAA==.Talwen:BAAANQADCgYICwAAAA==.Tandarin:BAAANQADCgYICwAAAA==.Tangomago:BAAANQADCgQIBAAAAA==.Tantalus:BAAANQAECgEIAQAAAA==.Tareeya:BAAANQADCgcIEwAAAA==.Tasmanica:BAAANQADCggIDQAAAA==.Tasse:BAAANQADCggIEAAAAA==.Tassiban:BAAANQADCggICAAAAA==.Taurmien:BAAANQAECgQIBwAAAA==.Tazviro:BAAANQAECgcIBwAAAA==.',
Tc='Tcuntius:BAAANQADCgIIAgABNQAECgIIBgABAAAAAA==.',
Te='Tekadin:BAAANQAECgEIAQAAAA==.Tekká:BAAANQADCgcIDQAAAA==.Teledron:BAAANQAECgcIDQAAAA==.Telladk:BAAANQAECgIIAgAAAA==.Telordroth:BAAANQADCgUIBQAAAA==.Tephilaisli:BAAANQADCgYICQAAAA==.Terminated:BAAANQADCggICAAAAA==.Terraform:BAAANQAECgIIAgAAAA==.Terrorscale:BAAANQADCgYIBgAAAA==.',
Th='Thebubble:BAAANQAECgcICwAAAA==.Theelfchick:BAAANQAECgEIAQAAAA==.Therassra:BAAANQADCgcIDQAAAA==.Thethem:BAAANQADCgcICAABNQAECgQICgABAAAAAA==.Thiccshot:BAAANQAECgUIBwAAAA==.Thorgoodsdk:BAAANQADCgcICgAAAA==.Thoughtless:BAAANQADCgYIDgAAAA==.Throlde:BAAANQAECgEIAQAAAA==.Thunderam:BAAANQADCggIDwAAAA==.Thundrstryke:BAAANQADCgcIDQAAAA==.',
Ti='Ticklemaster:BAAANQADCgYIBgAAAA==.Tikitoki:BAAANQAECgEIAQAAAA==.Timmeh:BAAANQAECgEIAQAAAA==.Tingo:BAAANQADCgcIDQAAAA==.Tinkerspell:BAAANQADCggIDwAAAA==.Tinsham:BAAANQAECgEIAgAAAA==.Tipps:BAAANQADCgIIAgAAAA==.Tipsydipsy:BAAANQAECgEIAgAAAA==.Tipsygypsy:BAAANQADCggIDAAAAA==.Tirayvia:BAAANQADCgYIDAABNQAECgQIBQABAAAAAA==.',
Tl='Tlusticus:BAAANQAECgIIBgAAAA==.',
Tn='Tnucyllap:BAAANQADCggIDgAAAA==.',
To='Tobymanajinx:BAAANQADCgQIBwAAAA==.Tomar:BAEANQADCggIEAAAAA==.Torturous:BAAANQABCgQIBAAAAA==.Totemrunna:BAAANQADCgMIAwAAAA==.',
Tr='Tragos:BAAANQADCgYICQAAAA==.Tren:BAAANQADCgYICAAAAA==.Treyel:BAAANQADCgcIEwAAAA==.Tricksybelle:BAAANQADCggICAAAAA==.Trics:BAAANQADCgUIBQAAAA==.Tripitakä:BAAANQADCgYICQAAAA==.Trollmon:BAAANQADCgcIDQAAAA==.',
Ts='Tsubyiaki:BAAANQAECgEIAQAAAA==.',
Tu='Tubig:BAAANQAECgEIAQAAAA==.Tuskarus:BAAANQADCgcICwAAAA==.',
Tv='Tvpper:BAAANQAECgIIAgAAAA==.',
Tw='Twiglet:BAAANQADCgUIBwAAAA==.Twohandedaxe:BAAANQADCgcIDQAAAA==.',
['Tö']='Tölls:BAAANQADCggIDwAAAA==.',
['Tø']='Tølls:BAAANQAECgEIAQAAAA==.',
Ul='Uleo:BAAANQADCgcIDQAAAA==.',
Un='Uncultured:BAAANQAECgQICgAAAA==.Unculturedg:BAAANQADCgYIBgABNQAECgQICgABAAAAAA==.Unculturedzz:BAAANQADCggIDgABNQAECgQICgABAAAAAA==.Unstopbubbl:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.',
Ur='Urukhia:BAAANQAECgEIAQAAAA==.',
Ut='Uturnip:BAAANQADCgEIAQAAAA==.',
Va='Valeryan:BAAANQADCgIIAgAAAA==.Vamoose:BAAANQAECgQIBAAAAA==.Vanatoarea:BAAANQADCgQIBAAAAA==.Vargula:BAAANQADCgYIBgABNQADCgIIAgABAAAAAA==.',
Ve='Veliondel:BAAANQAECgcIDQAAAA==.Velisar:BAAANQADCggIEgAAAA==.Vesperath:BAAANQADCgUIBQAAAA==.',
Vi='Victim:BAAANQADCggICAAAAA==.Vikzulx:BAAANQADCggICAABNQAECgcIDQABAAAAAA==.Vineweaver:BAAANQAECgEIAQAAAA==.',
Vo='Vodkasam:BAAANQADCgYIBwAAAA==.Vodkaspin:BAAANQAECgUICQAAAA==.Voidgirl:BAAANQAECgMIBgABNQABCgIIAgABAAAAAA==.Voidnight:BAAANQADCgYICwAAAA==.Voljuin:BAAANQADCgYIBgAAAA==.Volrod:BAAANQADCgYIFAAAAA==.Voltros:BAAANQADCgYIDgAAAA==.Vorpaxx:BAAANQADCgQIBwAAAA==.',
Vr='Vrenga:BAAANQAECgEIAQAAAA==.',
Vu='Vurne:BAAANQAECgMIBAABNQAECgcIBwABAAAAAA==.Vurve:BAAANQADCgcIDQAAAA==.',
Vy='Vyssali:BAAANQADCgIIAgAAAA==.',
['Vë']='Vël:BAAANQADCgYIBgAAAA==.',
Wa='Walpurgis:BAAANQADCggICgABNQADCggIDQABAAAAAA==.Warhammerer:BAAANQADCgcIDQAAAA==.Warjez:BAAANQADCgEIAQAAAA==.Wasamedis:BAAANQADCgYIEgAAAA==.Wasstwo:BAAANQAECgEIAQAAAA==.Wayfinder:BAAANQAECgQIBQABNQAFFAEIAQABAAAAAA==.',
We='Wellofheaven:BAAANQADCgQIBAAAAA==.Wemenn:BAAANQAECgEIAgAAAA==.',
Wh='Whatmeows:BAAANQAECgIIBAAAAA==.Wheels:BAAANQADCgYIBwAAAA==.Whoox:BAAANQADCgcIBwAAAA==.',
Wi='Widpally:BAAANQADCggIDgAAAA==.Wildhunt:BAAANQADCgIIAgAAAA==.Willdiealot:BAAANQADCgcIDAAAAA==.Wintèr:BAAANQADCgcIBwABNQABCgIIAgABAAAAAA==.',
Wo='Wonkydonky:BAAANQADCggIDgAAAA==.Woolnd:BAAANQADCgYICQAAAA==.',
Wr='Wraitthh:BAAANQADCgYIBwAAAA==.',
Wy='Wyspå:BAAANQADCgYICAAAAA==.',
Xa='Xalafoot:BAAANQADCggICAAAAA==.Xalatath:BAAANQAECgIIAgAAAA==.Xaneie:BAAANQADCgUIAQAAAA==.',
Xo='Xonkz:BAAANQADCgEIAQAAAA==.',
Xt='Xtreme:BAAANQADCgYICgAAAA==.',
Xu='Xuanwu:BAAANQAECgcIEAAAAA==.',
Xy='Xylaera:BAAANQAECgYICAAAAA==.Xylunara:BAAANQADCgcICwABNQAECgYICAABAAAAAA==.',
Ya='Yachtclub:BAAANQAECgQIBAAAAA==.Yadito:BAAANQADCggIDwAAAA==.Yanthra:BAAANQADCgcIFAAAAA==.Yazmi:BAAANQADCggIEAABNQABCgIIAgABAAAAAA==.',
Yb='Ybjealous:BAAANQADCgYICgAAAA==.',
Yi='Yimee:BAAANQADCgcIDQAAAA==.',
Yl='Ylessa:BAAANQADCgcICQAAAA==.',
Yn='Ynotvoidberg:BAAANQABCgIIAQAAAA==.',
Ys='Yseeri:BAAANQAECgcIDAAAAA==.',
Za='Zachbuc:BAAANQADCgQIBAAAAA==.Zackiya:BAAANQAECgMIAwAAAA==.Zadkielle:BAAANQADCgIIAgAAAA==.Zambiéz:BAAANQADCgYIBgAAAA==.Zandar:BAAANQADCgYICwAAAA==.Zaphiel:BAAANQADCgYIBgAAAA==.Zat:BAAANQADCggICAABNQAECgcIDQABAAAAAA==.Zatqt:BAAANQAECgcIDQAAAA==.Zatriel:BAAANQAECgQIBAABNQAECgcIDQABAAAAAA==.',
Ze='Zebo:BAAANQAECgYICQAAAA==.Zekes:BAAANQAECgcIDQABNQADCggIEAABAAAAAA==.Zendma:BAAANQADCggIDgAAAA==.Zeralia:BAAANQAECgIIBgAAAA==.',
Zi='Zialayn:BAAANQAECgQICAAAAA==.Zinrokh:BAAANQADCgYIBgAAAA==.',
Zo='Zorali:BAAANQADCgcIEQABNQAECgYICAABAAAAAA==.Zoranna:BAAANQAECgYICAAAAA==.',
Zu='Zugzy:BAAANQAFFAEIAQAAAA==.Zuxx:BAAANQADCgEIAQAAAA==.',
['Äz']='Äzzä:BAAANQAECgQIBAAAAA==.',
['Ål']='Ålary:BAAANQAECgQIBAAAAA==.',
['Êê']='Êêvêê:BAAANQADCggIDgAAAA==.',
['Ðe']='Ðevine:BAAANQADCgYICwABNQAECgYICgABAAAAAA==.',
['Ón']='Ónzo:BAAANQADCgcIHAAAAA==.',
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
