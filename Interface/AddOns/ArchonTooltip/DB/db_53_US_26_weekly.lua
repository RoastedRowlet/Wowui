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

local lookup = {'Unknown-Unknown','Paladin-Protection','Mage-Frost','Mage-Arcane','Druid-Balance','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','DeathKnight-Blood','Monk-Mistweaver','DeathKnight-Unholy','Paladin-Holy','Monk-Windwalker','Priest-Shadow','Priest-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','Evoker-Preservation','DemonHunter-Devourer','Evoker-Devastation',}
local provider = {region='US',realm='Azshara',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aaryyee:BAAANQAECgEIAQAAAA==.',
Ac='Acaeus:BAAANQABCgQIBQAAAA==.Aceforlife:BAAANQAECgEJAQAAAA==.',
Ad='Adrox:BAAANQADCgMIBAAAAA==.',
Ae='Aelelelos:BAAANQADCgYIBgAAAA==.Aequus:BAAANQABCgQIAgAAAA==.Aevenyhm:BAAANQAECgYIDgAAAA==.',
Ag='Aghorn:BAAANQAECgEIAgAAAA==.',
Ai='Aidoneus:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
Ak='Akijin:BAAANQABCgQIBAABNQAECgQIBQABAAAAAA==.Akismite:BAAANQAECgQIBQAAAA==.',
Al='Alemental:BAAANQADCgcIEgABNQAECgIJAgABAAAAAA==.Algana:BAAANQADCggIDAABNQAECgYIDgABAAAAAA==.Allhallows:BAAANQAECgUIBgAAAA==.Alorandis:BAAANQAECgIIAgAAAA==.Alqueria:BAAANQAECgUJDAAAAA==.Altarboizyum:BAAANQAECgIJAQABNQAECggJHwACAD8gAA==.',
An='Andanto:BAAANQAECgQJBwAAAA==.Angeliz:BAAANQAECgcICgAAAA==.Anneweaver:BAABNQAECoEkAAMDAAgK5x0YBwD4AQAEAAgKdBmYYgBnAgADAAgKwRkYBwD4AQABNQAECggIEAAEAKIUAA==.Anorantha:BAABNQAECoEXAAIFAAUKEQnWVgDzAAAFAAUKEQnWVgDzAAAAAA==.',
Ap='Apicots:BAAANQADCggIDwAAAA==.Apipa:BAAANQAECgYIBwAAAA==.Apricot:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Apzz:BAAANQADCgIIAgAAAA==.',
Ar='Arizticat:BAAANQABCgIIAwAAAA==.Arrowin:BAAANQADCgQIBAAAAA==.',
As='Ashalan:BAAANQAECgMIBQAAAA==.Asherabinx:BAAANQABCgYJDgAAAA==.Astesia:BAAANQAECgIJAgAAAA==.Astrraa:BAAANQADCgcICAAAAA==.Asulo:BAAANQAECgYIBgABNQAFFAEJAQABAAAAAA==.',
At='Atrejha:BAAANQAFFAEJAQAAAA==.',
Au='Aurä:BAAANQAECgUICQABNQAECgcIEAABAAAAAA==.',
Av='Avera:BAAANQADCgYIBgAAAA==.',
Aw='Awesome:BAAANQAECgEIAgAAAA==.',
Az='Azgkrimpatul:BAAANQADCgYICwAAAA==.Azrina:BAAANQAECgYJDAAAAA==.',
Ba='Bael:BAAANQADCgYIBgAAAA==.Baidden:BAAANQADCgMIBQAAAA==.Baldrogue:BAAANQAFFAEJAQAAAA==.Baldwarrior:BAAANQAECgcIEQAAAA==.Ballflapper:BAAANQADCgUJBQAAAA==.Bandidos:BAAANQADCgcJDwAAAA==.',
Be='Beckz:BAAANQADCggIDQAAAA==.Beefhambacon:BAAANQAECgMIAwAAAA==.Behealzabub:BAAANQAECgQIBgAAAA==.Belmatride:BAAANQAECgIJBgAAAA==.Belpepper:BAAANQAECggJEAAAAA==.Bendelmonte:BAAANQADCggJEgABNQAECgQJBQABAAAAAA==.',
Bi='Biggum:BAAANQADCgIIAgAAAA==.Bigmez:BAAANQADCggJIgAAAA==.Bigmoocowii:BAAANQADCgIIAgAAAA==.Bigswangindi:BAAANQADCggIEAAAAA==.Bilipmonk:BAAANQAECgcIDAAAAA==.Bindinglight:BAABNQAECoEvAAMFAAkK1RQ2KQAeAgAFAAgKLRU2KQAeAgAGAAcK7Q+lHAC1AQAAAA==.Birdofhermes:BAAANQADCgMIAwAAAA==.Biñx:BAAANQABCgQJCQAAAA==.',
Bl='Blarr:BAAANQAECgMIAwAAAA==.Blindehunter:BAAANQADCgIIAgABNQADCgIIAgABAAAAAA==.Blindvoid:BAAANQAECgIIAgABNQADCgIIAgABAAAAAA==.Bloodguard:BAAANQADCgYIBgAAAA==.Bluedabodeba:BAAANQADCgEIAQAAAA==.Bluejeanz:BAAANQADCgYIBQABNQAECgcIEAABAAAAAA==.',
Bo='Boonkay:BAAANQADCgEIAQAAAA==.Boonkie:BAAANQADCgUICAAAAA==.Boonksdeath:BAAANQADCgIIAgAAAA==.Boonksdragon:BAAANQADCggIEQAAAA==.Boonlock:BAAANQADCgIIAgAAAA==.Boreowlis:BAAANQABCgQICAAAAA==.Boxbeater:BAAANQADCgYIBgAAAA==.',
Br='Braedravia:BAAANQADCgIIAgAAAA==.Brisanna:BAAANQAECgIIBAAAAA==.',
Bu='Bubos:BAAANQADCgIJAgAAAA==.Budgeroo:BAAANQAECgUIBAAAAA==.',
['Bà']='Bàwlz:BAAANQAECgMIAwAAAA==.',
['Bè']='Bèérsërk:BAAANQADCgEIAQAAAA==.',
Ca='Caelix:BAAANQADCgQIBQAAAA==.Caledor:BAAANQAECgMJBQAAAA==.Camitriel:BAABNQAECoGhAAMHAAgKniZ/AwCWAwAHAAgKeCZ/AwCWAwAIAAQKAyWiFACxAQAAAA==.Castratôr:BAAANQADCggIAQAAAA==.',
Ce='Ceaserianoma:BAAANQADCgMIAwAAAA==.',
Ch='Chadder:BAAANQAECgYJDwAAAA==.Charliie:BAAANQAECgYIDwAAAA==.Chaunakoala:BAAANQADCgIIAgAAAA==.Cherryfudge:BAAANQADCggIDQAAAA==.Chipinwing:BAAANQAECgEIAQAAAA==.Chunkysoupz:BAAANQADCgYIBgAAAA==.',
Cl='Classyshammy:BAAANQADCggJDAAAAA==.Clockworks:BAAANQADCgcIDwAAAA==.Clouxdyskies:BAAANQADCgEIAQAAAA==.',
Co='Cocinegr:BAAANQAECgYIEQABNQAECgkJIwAEADkbAA==.Coneja:BAAANQAECgUIEAAAAA==.Coomspit:BAAANQAECgIIAgAAAA==.Covidnynteen:BAAANQADCgMIAwAAAA==.Cowtastrophe:BAAANQABCgcIEAAAAA==.',
Cr='Craiso:BAAANQAECgYJEgAAAA==.Crankinhawg:BAAANQAECgcJEgAAAA==.Crazbezzul:BAAANQADCgUIBwAAAA==.Creationz:BAAANQADCgYICQABNQAECgEJAQABAAAAAA==.Crisarrow:BAAANQADCggIGAAAAA==.',
Cu='Current:BAAANQAECgUIDgAAAA==.',
Cy='Cynesh:BAACNQAFFIERAAMJAAYKPyFsAABYAgAJAAYKOyFsAABYAgAKAAQKDhb3BwBIAQA1AAQKgRwAAwkACQrMJSUFAJQDAAkACQrDJSUFAJQDAAoABwqqHVkfAOsBAAAA.Cytl:BAAANQADCgMIAwAAAA==.',
Da='Dailybuilt:BAAANQADCgQICgAAAA==.Dangybangy:BAAANQAECgQJCAAAAA==.Danjaianka:BAAANQADCggJHgAAAA==.Darkken:BAAANQADCgYJBgABNQADCgcIDwABAAAAAA==.Darkkragmur:BAAANQAECgQJBwAAAA==.Darknest:BAAANQADCgQIBgAAAA==.Darthimus:BAAANQAECgIIAwAAAA==.Datbishkarma:BAAANQAECgQICAAAAA==.',
Dd='Dding:BAABNQAECoEdAAMCAAkKtx+LBAA0AwACAAgKiyOLBAA0AwALAAEKEwECSQEFAAAAAA==.',
De='Deadbarcy:BAAANQAECgIJAgAAAA==.Deathklok:BAAANQAECgMIBAAAAA==.Deathran:BAAANQAECgYJEAAAAA==.Deezgrips:BAABNQAECoEdAAIMAAgKKhgDIABWAgAMAAgKKhgDIABWAgAAAA==.Deffgwip:BAAANQAECgMJAwAAAA==.Delfine:BAAANQADCggJFwAAAA==.Demonikiarly:BAAANQADCgUJBQABNQAECgYJCAABAAAAAA==.Desimus:BAAANQADCgcJCgAAAA==.Despott:BAAANQAECgYJDQAAAA==.Dethfox:BAAANQAECgQJBQAAAA==.',
Di='Dioni:BAAANQAECgYIDwABNQAECgcJEwABAAAAAA==.Dirknasty:BAAANQAECgQJBwAAAA==.Diyfootjobs:BAAANQADCgYJGgAAAA==.',
Dk='Dkurther:BAAANQAECgIJAgAAAA==.',
Do='Doggybag:BAAANQADCgQIBAAAAA==.Doublehelix:BAAANQAECgMJBAAAAA==.Dovish:BAAANQAECgcICwAAAA==.',
Dr='Drackygacky:BAAANQAECgEIAQAAAA==.Draglox:BAAANQADCgMIAwAAAA==.Drakaryss:BAAANQADCgEIAQABNQAECggIGAANAFIeAA==.Drashar:BAAANQADCgUIBQAAAA==.Dravenm:BAAANQAECgUICAAAAA==.Draz:BAAANQAECgEIAQAAAA==.Droozh:BAAANQADCgMIAwAAAA==.Drunkendrago:BAAANQADCgcIBwAAAA==.',
Du='Duesenjaeger:BAAANQADCgEIAQAAAA==.Duko:BAAANQADCgEIAQAAAA==.',
['Dè']='Dèmonic:BAAANQAECgQIBQAAAA==.',
['Dø']='Døric:BAAANQADCgcJDAAAAA==.',
['Dü']='Dürinn:BAAANQADCgIIAgAAAA==.',
Ec='Ectoplasm:BAAANQAECggICAAAAA==.',
Eh='Ehud:BAAANQAECgQIDAAAAA==.',
Ei='Eisiss:BAAANQABCgEIAQAAAA==.',
Ek='Ekô:BAAANQADCggIDgAAAA==.',
El='Elabrate:BAAANQADCgMIAwAAAA==.Elade:BAAANQADCgUIBQAAAA==.Elbori:BAAANQAECgcIEQAAAA==.Elbryan:BAAANQADCgMIAwAAAA==.Elementium:BAAANQAECgUIBwAAAA==.Elfmas:BAAANQAECgUJCAAAAA==.Elviswong:BAAANQADCgIIAgAAAA==.',
Em='Emerhy:BAAANQAECgEJAQAAAA==.',
Es='Escänor:BAAANQAECgYJCgAAAA==.Eshaia:BAAANQADCgEIAQAAAA==.',
Ex='Exlisum:BAAANQADCgQIBgAAAA==.',
Ey='Eyewyn:BAAANQABCgYIBQAAAA==.Eylos:BAAANQADCgQIBAAAAA==.',
Fa='Faesmite:BAAANQADCgUIBQAAAA==.Faithflop:BAAANQAECgIJAgAAAA==.Falleh:BAAANQADCgIIAgAAAA==.Fanorage:BAAANQADCgUJBwAAAA==.',
Fe='Felixox:BAAANQAECgEIAQAAAA==.Ferocias:BAAANQAECgQJBQAAAA==.',
Fi='Fiametta:BAAANQADCggICAAAAA==.Fishbreath:BAAANQAECgEIAQAAAA==.',
Fl='Flaffergan:BAAANQAECgUICAAAAA==.Flexhack:BAAANQAECgMIAwAAAA==.Flåsh:BAAANQAECgUICQAAAA==.',
Fo='Focinnet:BAAANQAECgUJEwAAAA==.Forandra:BAAANQAECgIIAgAAAA==.Fortyacres:BAAANQADCgEIAQAAAA==.Four:BAAANQADCgYJDgAAAA==.Fourform:BAAANQADCgIIAgAAAA==.',
Fr='Frieren:BAAANQAECgMJAwAAAA==.',
Fu='Fuzzbutt:BAAANQADCgEIAQAAAA==.',
Ga='Gaalit:BAAANQADCgcIBwAAAA==.Galaxybone:BAAANQADCgQIBAAAAA==.Galithiri:BAAANQAECgEIAQAAAA==.Ganthani:BAAANQAECgUJCwAAAA==.Garzett:BAABNQAECoEXAAIFAAgKWxVLJgA2AgAFAAgKWxVLJgA2AgAAAA==.Gatortooth:BAAANQABCgIIBAAAAA==.Gaybeowners:BAAANQAECgEJAQAAAA==.',
Ge='Geigh:BAAANQADCgUIBQAAAA==.Gethellar:BAAANQAECgMIAwAAAA==.',
Gh='Ghostdaliar:BAAANQADCgIIAgAAAA==.Ghouliana:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Gl='Glizyglober:BAAANQADCgMIAwABNQAECgkJLwAFANUUAA==.Glizzyrizily:BAAANQADCgMIAwABNQAECgkJLwAFANUUAA==.Glizzyys:BAAANQAECgIIAgABNQAECgkJLwAFANUUAA==.Gllizzard:BAAANQADCgMJAwAAAA==.',
Go='Gordo:BAAANQAECgcJBwAAAA==.Gore:BAAANQAECgEJAQAAAA==.Gorrock:BAAANQAECgQIBAAAAA==.',
Gr='Gravtech:BAAANQADCggJDgABNQAECgQIBgABAAAAAA==.Grenzo:BAAANQAECgEIAQAAAA==.Grhm:BAAANQAECgYJBgAAAA==.Grim:BAABNQAECoEZAAIOAAkKaSH5CwAqAwAOAAkKaSH5CwAqAwABNQAFFAMIAwABAAAAAA==.Grymnir:BAAANQAECgIJAwAAAA==.',
Gu='Gumsy:BAAANQAECgQIBwABNQAECgUICwABAAAAAA==.',
['Gø']='Gørë:BAAANQADCgQIBwAAAA==.',
Ha='Haddassah:BAAANQADCgIIAgAAAA==.Haramzadi:BAAANQADCgQICQAAAA==.Haranue:BAAANQAECgQJCQAAAA==.Harryporter:BAAANQAECgEIAQAAAA==.Harukà:BAAANQAECgQJBwAAAA==.',
He='Healscat:BAAANQADCgUJBQAAAA==.Healsdog:BAAANQAECgEIAQAAAA==.Hecâte:BAAANQABCggJCgAAAA==.Helfon:BAAANQAECgYIEgAAAA==.Helgadknight:BAAANQABCgMIAwAAAA==.Helganelf:BAAANQAECgEJAQAAAA==.Helices:BAAANQAECggICwAAAA==.Herm:BAAANQAECgEIAQAAAA==.',
Hi='Highlordt:BAAANQAECgcIEwAAAA==.Highlordtron:BAAANQAECgYIBgAAAA==.Hinoxfine:BAAANQADCgMIBAAAAA==.',
Ho='Holybeast:BAAANQADCgIIAgAAAA==.Holycrab:BAAANQAECgEIAQAAAA==.Holydudy:BAAANQAECgEIAQAAAA==.Holyely:BAAANQADCggIGQAAAA==.Holyfae:BAABNQAECoEdAAIPAAgKpxTELwBAAgAPAAgKpxTELwBAAgAAAA==.Holygrom:BAABNQAECoEYAAILAAkKJB85FgAoAwALAAkKJB85FgAoAwAAAA==.Holysplash:BAAANQAECgUJCAAAAA==.Holyvoids:BAAANQADCgIIAgAAAA==.Hondodk:BAECNQAFFIEJAAIOAAQKJh98AgCTAQAOAAQKJh98AgCTAQA1AAQKgSkAAw4ACQqlJlcAAAYEAA4ACQqcJlcAAAYEAAwAAQrDJhaBAHMAAAE1AAUUBQgJAA4AuhsA.Honeyshamwow:BAAANQADCgQIBAAAAA==.Hoodadin:BAAANQABCgMIAwAAAA==.Hoodlummon:BAAANQADCggJHQAAAA==.Hopesfall:BAAANQAECgIJAwAAAA==.Howzitcuz:BAAANQADCgcIDQABNQAECgQICwABAAAAAA==.Hozari:BAABNQAECoEZAAIFAAgKxROZKgASAgAFAAgKxROZKgASAgAAAA==.',
Ht='Ht:BAAANQADCgcICAAAAA==.',
['Hã']='Hãvøc:BAAANQADCgIIAgAAAA==.',
Ia='Ianil:BAAANQAECgIJAwAAAA==.',
Ic='Iccyhot:BAAANQADCgMIAwABNQAECgkJLwAFANUUAA==.',
Il='Ilirranna:BAAANQAECgIJBAAAAA==.',
In='Infi:BAACNQAFFIEUAAMKAAYKax0IAgAfAgAKAAYKKRwIAgAfAgAJAAEK1wrfFgBkAAA1AAQKgScAAwoACQqpJfwBALEDAAoACQqpJfwBALEDAAkAAQrZJsHYAHUAAAAA.Initabath:BAAANQAECggJCQAAAA==.Initapoop:BAAANQAECgEJAgAAAA==.Inosukè:BAABNQAECoEYAAINAAgKUh6pCACvAgANAAgKUh6pCACvAgAAAA==.Invisibro:BAAANQAECgQIBgAAAA==.',
Io='Ioannis:BAAANQAECgEIAgAAAA==.',
Is='Isos:BAAANQAECgYJEgAAAA==.Isus:BAAANQADCgYJBgABNQAECgYJEgABAAAAAA==.',
Iy='Iykyk:BAAANQADCgQICQABNQAECgQICwABAAAAAA==.',
Ja='Jadeadly:BAAANQAECgcICAAAAA==.Jaded:BAABNQAECoEYAAIQAAkKPBLSFQAdAgAQAAkKPBLSFQAdAgAAAA==.Jakerbonk:BAAANQADCgYIBwAAAA==.Jakersai:BAAANQAECgQIBQAAAA==.Javyr:BAAANQAECgIIAwAAAA==.Jayfmtv:BAAANQAECgIIAgAAAA==.',
Je='Jessicax:BAAANQAECgQIBAAAAA==.Jetpackcat:BAAANQADCgIIAgAAAA==.',
Jl='Jlnxy:BAAANQAECgYJDgAAAA==.',
Jo='Joania:BAAANQADCggICAAAAA==.Jonoa:BAAANQADCgUIBQAAAA==.',
Ju='Judo:BAAANQADCgIJAgAAAA==.',
Ka='Kadre:BAAANQAECgMJBAAAAA==.Kadzilak:BAAANQADCgQIBgAAAA==.Kagemika:BAAANQADCgcIBwABNQAFFAEJAQABAAAAAA==.Kaiola:BAAANQADCgYIEAAAAA==.Kaizumie:BAAANQAECgIIAgAAAA==.Kamistri:BAAANQAECgYICwAAAA==.Kanaa:BAAANQAECgIIAgAAAA==.Kanatre:BAAANQADCgEJAQAAAA==.Karessandra:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Karrison:BAAANQADCgEIAQAAAA==.Kathea:BAAANQADCgIJAgAAAA==.Kayarra:BAAANQADCgEIAQABNQADCgQIBAABAAAAAA==.Kaynarra:BAAANQADCgQIBAAAAA==.Kayonna:BAAANQABCgEIAQABNQADCgQIBAABAAAAAA==.',
Ke='Keastral:BAAANQADCgcICQAAAA==.Keeynai:BAAANQADCgQIBAAAAA==.Keldanis:BAAANQAECgUJEgAAAA==.Kelestrah:BAAANQADCgQJBAAAAA==.Kelterrager:BAAANQADCgMIAwAAAA==.Keony:BAAANQAECgQICwAAAA==.Kerthur:BAAANQADCgYJCAAAAA==.',
Ki='Kickpigeons:BAAANQABCgQIBgAAAA==.Kirgrand:BAAANQADCgMIAwAAAA==.Kittyarly:BAAANQAECgYJCAAAAA==.',
Ko='Kodeck:BAAANQADCggJGQAAAA==.Kodokan:BAAANQADCgYJCQAAAA==.Koshima:BAAANQAECgYJEwAAAA==.Kozan:BAAANQADCgUICAAAAA==.',
Kr='Kreamer:BAAANQABCgIIAQAAAA==.Krimhit:BAAANQADCgUICwAAAA==.Krimrok:BAAANQABCgIIAgAAAA==.',
Ku='Kudranne:BAAANQADCgQICAABNQAECgEIAQABAAAAAA==.Kugia:BAAANQAECgcJEwAAAA==.',
Ky='Kylex:BAAANQAECgEIAQAAAA==.Kynndell:BAAANQADCggIGQAAAA==.Kyo:BAAANQADCgYIDgAAAA==.',
['Kø']='Køkushibø:BAAANQABCgUIBQAAAA==.',
La='Laments:BAAANQADCgUIBQAAAA==.Latak:BAAANQADCgMIAwAAAA==.Latir:BAAANQADCgUIBwAAAA==.Lazyryx:BAAANQADCgUIBQAAAA==.',
Le='Leetheal:BAACNQAFFIEGAAMRAAQKoQtHCADeAAARAAMKvwRHCADeAAASAAMKdwSVDwDXAAA1AAQKgR0AAxEACQobHCAYACQCABEABwr/GiAYACQCABIABgrhCkdlAEIBAAAA.Leethul:BAAANQAECgYJDAAAAA==.Lelethxx:BAAANQAECgIIAgAAAA==.Lesanna:BAABNQAECoEaAAITAAgKWAdyLACjAQATAAgKWAdyLACjAQAAAA==.Leysmith:BAABNQAECoEbAAILAAgKVQ8XZADRAQALAAgKVQ8XZADRAQAAAA==.',
Li='Lifestream:BAAANQAECgEJAQAAAA==.Lilheal:BAAANQAECgIJAgAAAA==.Lilium:BAAANQADCgYICwAAAA==.Lionël:BAAANQADCggIEwAAAA==.Lizzanna:BAAANQAECgYIDAAAAA==.',
Lo='Lomrgreenol:BAAANQADCgQIBAAAAA==.Lopi:BAAANQAECgMIAwAAAA==.Lorast:BAAANQADCgQIBAAAAA==.Lorwater:BAAANQADCgQIBAAAAA==.Loveinfinity:BAAANQABCgIIAgAAAA==.',
Lu='Lumibell:BAAANQABCgYIBwAAAA==.Lunaryon:BAAANQADCgUICgAAAA==.',
Ma='Madamgypsy:BAAANQAECgIJAgAAAA==.Madderco:BAAANQAECggJCAAAAA==.Magaspy:BAAANQAECgEJAQAAAA==.Magerage:BAAANQAECgEIAQAAAA==.Magikiarly:BAAANQADCgYIDwABNQAECgYJCAABAAAAAA==.Mahoogany:BAAANQADCgYIDAAAAA==.Mamimage:BAABNQAECoEjAAIEAAkKORuFNADwAgAEAAkKORuFNADwAgAAAA==.Marukka:BAAANQADCgQIBAABNQADCgcIBwABAAAAAA==.Matty:BAAANQADCgEIAQAAAA==.Mayiana:BAAANQADCggICQAAAA==.',
Me='Meadowlark:BAAANQAECgIIAgAAAA==.Mefistofeles:BAAANQAECgQICgAAAA==.Mellie:BAAANQADCgQIBQAAAA==.Meowstic:BAAANQAECgYJDgABNQAECgIIAgABAAAAAA==.Mercurious:BAAANQADCggJCAAAAA==.Metalrules:BAAANQABCggICAAAAA==.Methypheni:BAAANQAECgIIAgAAAA==.',
Mi='Milfshotz:BAAANQADCgIIAgAAAA==.Mill:BAAANQADCgYICgAAAA==.Minimuff:BAAANQADCgUIBQAAAA==.Mirajanna:BAABNQAECoEZAAIUAAgKHBNOBwD4AQAUAAgKHBNOBwD4AQAAAA==.Missmouthoff:BAAANQAECgUJDQAAAA==.Mitenâ:BAAANQADCgUIBgAAAA==.Mizzxgummy:BAAANQAECgMJAwAAAA==.',
Mo='Monkin:BAAANQAECgEIAQAAAA==.Moogan:BAAANQAECgEIAQAAAA==.Mookins:BAAANQAECgYJDgAAAA==.Moonfishing:BAAANQAECggJEgAAAA==.Moonfly:BAABNQAECoEeAAIFAAkKFCDOCQBXAwAFAAkKFCDOCQBXAwAAAA==.Morax:BAAANQAECgIJAgAAAA==.Mourne:BAAANQAECgYICgAAAA==.',
Ms='Mssmalvile:BAAANQADCgYJCwAAAA==.',
My='Myrrvain:BAAANQAECgEIAQAAAA==.Mythara:BAAANQADCgYIBgAAAA==.',
Na='Naarcissus:BAAANQABCgIIAgAAAA==.Nagrim:BAAANQADCgYICQABNQAECgUICwABAAAAAA==.Nalaana:BAAANQAECgEJAgAAAA==.Nalariel:BAABNQAECoEZAAIOAAgKEh7bFwCrAgAOAAgKEh7bFwCrAgAAAA==.Nalmagedan:BAAANQADCggIFQAAAA==.Nammi:BAAANQADCgMJAwAAAA==.Nandorr:BAAANQADCgEIAQAAAA==.Narec:BAAANQADCgUIBQAAAA==.Narfhound:BAAANQADCgYICAAAAA==.Nazgrok:BAAANQAECgIJAgAAAA==.',
Ne='Nearhammer:BAAANQAECgEIAQAAAA==.Nefariouz:BAAANQAECggJAQAAAA==.Nervouz:BAAANQAECgYJDQAAAA==.Netherpally:BAAANQADCgQJBAAAAA==.',
Ni='Nikis:BAAANQADCgcIDwAAAA==.',
No='Nobbs:BAAANQADCgcJFwAAAA==.Noonecaress:BAAANQAECgIIAgAAAA==.',
Nu='Nualaperafin:BAABNQAECoEfAAIVAAkK6htsBAAbAwAVAAkK6htsBAAbAwAAAA==.',
Ny='Nyvara:BAAANQADCgQIBAABNQADCggJCAABAAAAAA==.Nyxkitsune:BAAANQADCggIDQAAAA==.',
Oi='Oiyo:BAAANQABCggICQAAAA==.',
Ok='Okonomiyaki:BAAANQADCgcIBwAAAA==.',
Ol='Olayro:BAAANQAECgYIDgAAAA==.',
Om='Omie:BAAANQADCgQJBAAAAA==.',
On='Onkiea:BAAANQABCgYJBAAAAA==.Onlyrage:BAAANQAECgUJCQAAAA==.',
Oo='Oomkin:BAAANQADCgQIBAAAAA==.Ooptomss:BAAANQAECgcIEgAAAA==.',
Op='Openingshift:BAAANQAECgEIAQAAAA==.Ophelìa:BAAANQADCgcIBwAAAA==.Ophilitheda:BAAANQADCgYJAwAAAA==.',
Or='Orclee:BAAANQAECgYIEQAAAA==.',
Pa='Pacificadora:BAAANQAECgEIAgAAAA==.Palaguy:BAAANQADCgQIBAAAAA==.Palkavanka:BAAANQAECgMIAwAAAA==.',
Pe='Peeonfists:BAAANQADCgEIAQAAAA==.Persephie:BAAANQAECgEIAQABNQAECgUICwABAAAAAA==.Perzeval:BAAANQADCgMJAwAAAA==.',
Ph='Pharmacology:BAAANQAECgQICAAAAA==.Phyberlamer:BAAANQADCgEIAQAAAA==.Phénicie:BAAANQADCgYJDgAAAA==.',
Pi='Pinkberri:BAAANQAECgEIAQAAAA==.Pipha:BAAANQABCgQIBQAAAA==.Pitchblack:BAAANQADCggJDQAAAA==.',
Po='Popa:BAABNQAECoEiAAMPAAkKGRkNGQDHAgAPAAkKGRkNGQDHAgALAAQKEBmlowAjAQAAAA==.',
Pr='Prathe:BAAANQAECgMJBAAAAA==.Prayinfury:BAAANQAECgUIBgAAAA==.Premorry:BAAANQAECgIIAgAAAA==.Premory:BAAANQADCgUICQAAAA==.Presagee:BAAANQADCgEIAQAAAA==.',
Ps='Psilocy:BAAANQAECgYIDgAAAA==.',
Pu='Pulsate:BAAANQAECgYIDAAAAA==.Purpleduster:BAAANQADCgEIAQAAAA==.',
Py='Pyllo:BAAANQAECggJCgAAAA==.',
Qa='Qaucker:BAAANQAECgYIBgAAAA==.',
Qi='Qiz:BAAANQAECgQICAAAAA==.Qizknows:BAAANQADCgEIAQAAAA==.',
Qu='Quadhelix:BAAANQAECgQIBwAAAA==.',
Qw='Qwish:BAAANQADCgYIBgAAAA==.',
Ra='Radlock:BAAANQAECgIIAQABNQAECgUICQABAAAAAA==.Ragémachine:BAAANQADCgQIBAAAAA==.Raiken:BAAANQADCggIHAAAAA==.Rasto:BAAANQAECgQJBwAAAA==.Raszto:BAAANQADCgIIAgABNQAECgQJBwABAAAAAA==.Rattlebat:BAAANQAECgIIAgAAAA==.',
Re='Redmark:BAAANQADCgUJBgAAAA==.Rendezook:BAAANQAECgQIBAAAAA==.Respec:BAAANQADCggICAAAAA==.',
Ri='Rincewind:BAAANQADCggJFQAAAA==.Riohne:BAAANQADCgMIAwAAAA==.Rivexis:BAAANQADCgIIAgAAAA==.',
Ro='Roci:BAAANQADCggJDAAAAA==.Rocker:BAAANQAECggICAAAAA==.Roxus:BAAANQAECgYIEAAAAA==.',
Ru='Ruthlin:BAAANQADCgYIBgAAAA==.',
Sa='Saegusa:BAAANQAECgMJAwAAAA==.Saepius:BAAANQAECgIJAgAAAA==.Salestia:BAAANQAECgUJCAAAAA==.Samellir:BAAANQAECgEIAQAAAA==.Sanlanesh:BAAANQADCgUJBQAAAA==.Sasive:BAAANQAECgQIBgAAAA==.Satanicpanic:BAAANQAECgEIAgAAAA==.Sazoku:BAAANQAECggIEAAAAA==.',
Sc='Scarletnight:BAAANQADCgcIBwABNQAECgUJDAABAAAAAA==.Schmall:BAAANQAECgIJAgAAAA==.Scrodumpulse:BAAANQADCgcICwAAAA==.',
Se='Sendit:BAAANQAECgcJCQAAAA==.Seniormage:BAAANQAECgIJAwAAAA==.Serveil:BAAANQADCgIIAgABNQAFFAEIAQABAAAAAA==.',
Sh='Shadesprint:BAAANQAECgIIAwAAAA==.Shadowhor:BAAANQAECgUJBQABNQAECggIGwAHAEQcAA==.Shamamoomoo:BAAANQAECgUICQAAAA==.Shaowen:BAAANQADCgYIBgABNQAECgIJAgABAAAAAA==.Shaqeesha:BAAANQADCgUIBQAAAA==.Shenea:BAAANQADCgYICQAAAA==.Shestalker:BAABNQAECoEhAAIJAAkK+RJ4LgB5AgAJAAkK+RJ4LgB5AgAAAA==.Shiau:BAAANQAECgYJDAAAAA==.Shimura:BAAANQADCgEIAQAAAA==.Shinky:BAAANQADCgUIBAABNQAECgYICwABAAAAAA==.Shý:BAAANQAECgMJBQAAAA==.',
Si='Silvaine:BAAANQADCggJGwAAAA==.Silverstorm:BAABNQAECoEYAAIWAAgKxBFiXwD0AQAWAAgKxBFiXwD0AQAAAA==.Sixii:BAAANQAECgMIAwAAAA==.',
Sk='Skitzz:BAAANQAECgQIBAAAAQ==.',
Sl='Slackr:BAAANQADCgUIBQAAAA==.Slackrm:BAAANQADCgMJBwAAAA==.Slackrp:BAAANQADCgIJAgAAAA==.Slashyr:BAAANQAECgQIDAAAAA==.Slimshadydh:BAAANQADCgMJAwAAAA==.',
Sn='Snipez:BAAANQAECgIJAwAAAA==.Snortyhotorc:BAAANQAECgIJAgAAAA==.Snortymcgoop:BAAANQAECgYJDgAAAA==.',
So='Solclipeus:BAABNQAECoEfAAICAAgKPyA6BwDdAgACAAgKPyA6BwDdAgAAAA==.Soldh:BAAANQAECgUJCgABNQAECggJHwACAD8gAA==.Sollock:BAAANQAECggIBgAAAA==.Soulrecall:BAAANQAECgEJAQAAAA==.Soupz:BAAANQAECgQIBwAAAA==.',
Sp='Sparadin:BAAANQAECgEJAQAAAA==.Spartacûs:BAAANQAECgQJBQAAAA==.Spikore:BAAANQABCgcICwAAAA==.Splitpeaz:BAAANQADCgcJBwAAAA==.',
Sq='Squrìtle:BAAANQADCgcJBwAAAA==.',
Sr='Sririacha:BAAANQADCgUIBQABNQAECgIIAwABAAAAAA==.',
St='Stabbyjohn:BAAANQADCggICAAAAA==.Stabbypickle:BAAANQAECgQIBAABNQAECgYIDQABAAAAAA==.Strånge:BAAANQAECgYIBwAAAA==.Stìtch:BAABNQAECoEkAAIHAAkKaCWSAQDHAwAHAAkKaCWSAQDHAwAAAA==.Stítch:BAAANQADCgQIBAABNQAECgkJJAAHAGglAA==.',
Su='Sukiafaunias:BAAANQAECgEIAgAAAA==.Sukiafloras:BAAANQADCgcJDAAAAA==.Suldån:BAAANQADCgcIGQAAAA==.Sunfurious:BAAANQAECgEJAQAAAA==.Suoop:BAAANQADCgYJCgAAAA==.',
Sw='Swiftshaman:BAAANQAECgEIAQAAAA==.',
Sy='Synvaria:BAAANQADCggJGwAAAA==.Syraice:BAAANQADCgUIBQABNQAECggJHAAXAIgaAA==.Syrare:BAAANQADCgcIDwAAAA==.Syvenari:BAAANQAECgIIBAAAAA==.',
['Sï']='Sïxx:BAAANQADCgMJAwABNQAECgMIAwABAAAAAA==.',
Ta='Tachisan:BAAANQAECgIJBAAAAA==.Taeril:BAAANQADCgQIBAAAAA==.Tamfam:BAAANQADCggJEAAAAA==.Tanburn:BAAANQADCgYICwAAAA==.Tanduinex:BAAANQADCgYIDAAAAA==.Tangal:BAAANQADCgQJBAAAAA==.Tankstabber:BAAANQADCgQIBQAAAA==.Tanplate:BAAANQADCgYICAAAAA==.Tarentia:BAAANQABCggIDgAAAA==.Tastytyrande:BAAANQAECgUIBQAAAA==.Tatsumy:BAAANQAECgQJDgAAAA==.',
Tc='Tcmon:BAABNQAECoEZAAIJAAgKmRdxNQBeAgAJAAgKmRdxNQBeAgAAAA==.',
Te='Teachings:BAAANQADCgMIAwAAAA==.Teaglizzy:BAAANQADCgEIAQABNQAECgkJLwAFANUUAA==.Teehole:BAAANQAECgUICwAAAA==.Telihill:BAAANQADCgUIDgAAAA==.Telsarra:BAAANQAECgQIBgAAAA==.',
Th='Thalenia:BAAANQADCgUJBQAAAA==.Thebigtuna:BAABNQAECoEbAAIYAAkKQiCLBQBjAwAYAAkKQiCLBQBjAwAAAA==.Theladydruid:BAAANQAECgcIEQAAAA==.Themeats:BAAANQADCgQIBAAAAA==.Thendezoth:BAAANQAECgEIAgAAAA==.Thighsoffel:BAAANQADCgcIEwAAAA==.Thirdtjme:BAAANQADCgYIBgAAAA==.Thunderhóof:BAAANQABCgYIDQAAAA==.',
Ti='Tigerpa:BAAANQAECgQJBgAAAA==.Tinkernut:BAAANQABCgIIAgAAAA==.Tinypally:BAAANQAECgEIAgAAAA==.Tinyraven:BAAANQAECgYJEAAAAA==.Tinystotems:BAAANQAECgQICgAAAA==.Tinythia:BAAANQADCgUIBQAAAA==.Tioklarus:BAABNQAECoEfAAIZAAcKfgW/GQBOAQAZAAcKfgW/GQBOAQAAAA==.Tisaryn:BAAANQAECgQIBAAAAA==.',
To='Tofulady:BAABNQAECoEhAAINAAkK5R1eBAAnAwANAAkK5R1eBAAnAwAAAA==.Tohu:BAAANQAECgYICAAAAA==.Toshen:BAAANQADCgEIAQAAAA==.Totax:BAAANQAECgEJAQAAAA==.Totemtoker:BAAANQADCggICAAAAA==.',
Tr='Tremors:BAAANQADCggJCAAAAA==.',
Tw='Twobithusler:BAAANQAECgIIAgAAAA==.Twoone:BAAANQADCgQIBAAAAA==.',
Ty='Tyniarstus:BAAANQADCgYICAAAAA==.',
Ud='Udderfiasco:BAAANQABCgIIAgAAAA==.',
Ug='Uggh:BAAANQADCgUIBQAAAA==.',
Un='Unhowly:BAABNQAECoEfAAIOAAkK6iP4AwCnAwAOAAkK6iP4AwCnAwAAAA==.Unpoppable:BAAANQAECgUICQAAAA==.',
Va='Vakir:BAABNQAECoEZAAIMAAgKdw9YOgCqAQAMAAgKdw9YOgCqAQAAAA==.Valmortem:BAEANQADCgcIEgAAAA==.Vapidos:BAAANQAECgIJAwAAAA==.Varynix:BAAANQAECgIIAgABNQAECgYIBwABAAAAAA==.Vatica:BAAANQAECgEIAQAAAA==.',
Ve='Velanoria:BAAANQADCggICwAAAA==.Veldorai:BAAANQADCgYICwAAAA==.Velrenya:BAAANQADCgQIBgAAAA==.Venvalzhar:BAAANQAECgUJDQAAAA==.Veralidaine:BAAANQAECgIIAgAAAA==.Vestammeni:BAAANQAECggIEwAAAA==.',
Vi='Vixsaurion:BAAANQAECgEIAQAAAA==.',
Vl='Vlamort:BAAANQADCgEIAQAAAA==.',
Vo='Voltx:BAAANQAECgEIAQAAAA==.Vow:BAAANQAECgUJEAAAAA==.',
Vy='Vynlenlor:BAAANQABCgIIAgAAAA==.',
Wc='Wckd:BAAANQAECgYIEgAAAA==.',
We='Weaksnow:BAAANQAECgYJDAABNQAECgkJIwAEADkbAA==.Weedvegeta:BAAANQAECgcIDAAAAA==.Wernbirn:BAAANQAECggIAQAAAA==.Wetremin:BAAANQADCgcJEQAAAA==.',
Wh='Whirpy:BAAANQAECgYJCQAAAA==.Whisberis:BAAANQADCgMIAwAAAA==.Whitty:BAAANQADCgQIBAAAAA==.Whizkee:BAAANQAECgUJCgAAAA==.',
Wi='Wildbeefwood:BAAANQADCggIDgAAAA==.Wingedlady:BAAANQAECgIIAgAAAA==.Wingss:BAABNQAECoEYAAILAAcK9SJZJgDJAgALAAcK9SJZJgDJAgAAAA==.',
Wu='Wushu:BAAANQAECgQIBAAAAA==.',
Wy='Wyl:BAAANQAECggJBwAAAA==.',
Xe='Xerath:BAAANQAECgIJAgAAAA==.',
Xi='Xiing:BAAANQAECgcIEQAAAA==.Xinei:BAAANQADCgQIAQAAAA==.',
Xn='Xneutron:BAAANQAECgUJCAAAAA==.',
Xt='Xtravagent:BAAANQADCgIIAgAAAA==.',
Ya='Yaiie:BAAANQAECgQJBQAAAA==.',
Yo='Yonna:BAAANQAECgMIAwAAAA==.',
Yu='Yungholy:BAAANQADCgQIBAAAAA==.Yuuki:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
['Yü']='Yüto:BAABNQAECoEUAAMJAAcKyRa1VgDsAQAJAAcKiRW1VgDsAQAKAAMKGxAWQACwAAAAAA==.',
Za='Zabuto:BAAANQAECgUICwAAAA==.Zahäära:BAAANQADCggIFQAAAA==.Zaldiz:BAAANQADCgIIAgAAAA==.Zarrtan:BAAANQADCgcJEQAAAA==.Zazprie:BAAANQAECgMJBgAAAA==.',
Ze='Zendrozath:BAAANQADCgQIBQAAAA==.',
Zo='Zooz:BAAANQADCgIJAgAAAA==.',
Zu='Zual:BAAANQAECgIIAgAAAA==.Zularraka:BAAANQAECgEJAQAAAA==.',
Zx='Zxeý:BAAANQADCgcIDgAAAA==.',
['Äb']='Äbracadabruh:BAAANQAECgUICQAAAA==.',
['Äl']='Älissia:BAAANQADCgcJEgAAAA==.',
['Ål']='Ålexthegrëat:BAAANQAECgEJAQAAAA==.',
['Ën']='Ëndo:BAAANQAECgUICwAAAA==.',
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
