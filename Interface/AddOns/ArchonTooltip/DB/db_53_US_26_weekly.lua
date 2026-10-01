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

local lookup = {'Unknown-Unknown','Warlock-Affliction','Paladin-Protection','Paladin-Retribution','Mage-Frost','Mage-Arcane','Druid-Balance','Warrior-Arms','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Warrior-Protection','DemonHunter-Havoc','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Mage-Fire','DeathKnight-Unholy','DeathKnight-Frost','Priest-Shadow','Priest-Holy','Priest-Discipline','Paladin-Holy','Monk-Windwalker','Druid-Guardian','DemonHunter-Vengeance','Shaman-Enhancement','Evoker-Preservation','DemonHunter-Devourer','Evoker-Devastation',}
local provider = {region='US',realm='Azshara',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaryyee:BAAANQAECgEIAQAAAA==.',
Ac='Acaeus:BAAANQABCgQIBQAAAA==.Aceforlife:BAAANQAECgUICgAAAA==.',
Ad='Adrox:BAAANQADCgMIBAAAAA==.',
Ae='Aelelelos:BAAANQADCgcICgAAAA==.Aequus:BAAANQABCgQIAgAAAA==.Aevenyhm:BAAANQAECgYIEwAAAA==.',
Ag='Aghorn:BAAANQAECgEIAgAAAA==.',
Ai='Aidoneus:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
Ak='Akijin:BAAANQABCgQIBAABNQAECgYICAABAAAAAA==.Akismite:BAAANQAECgYICAAAAA==.',
Al='Alaru:BAAANQADCgEIAQAAAA==.Alemental:BAAANQADCgcIEgABNQAECgIIBAABAAAAAA==.Algana:BAAANQADCggIDAABNQAECggIGQACADIMAA==.Allhallows:BAAANQAECgUICQAAAA==.Alorandis:BAAANQAECgIIAgAAAA==.Alqueria:BAABNQAECoEVAAMDAAkKChfuHQCeAQAEAAgKIw46fADQAQADAAYK1BruHQCeAQAAAA==.Altarboizyum:BAAANQAECgIJAQABNQAECggIJgADAGkhAA==.',
An='Andanto:BAAANQAECgUIDAAAAA==.Angeliz:BAAANQAECgcICwAAAA==.Anitaloc:BAAANQADCggICAAAAA==.Anneweaver:BAABNQAECoEkAAMFAAgK5x0DCgDZAQAGAAgKdBlCfgBIAgAFAAgKwRkDCgDZAQABNQAFFAUICAAGALoPAA==.Anorantha:BAABNQAECoEcAAIHAAUKYQszYAD6AAAHAAUKYQszYAD6AAAAAA==.',
Ap='Apicots:BAAANQADCggIDwAAAA==.Apipa:BAAANQAECgYIBwAAAA==.Apricot:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Apzz:BAAANQADCgIIAgAAAA==.',
Ar='Arizticat:BAAANQADCgQIBAAAAA==.Arrowin:BAAANQADCgQIBAAAAA==.Artica:BAAANQADCggICAAAAA==.Arzan:BAAANQABCgYIFQAAAA==.',
As='Ashalan:BAAANQAECgMIBQAAAA==.Ashenflail:BAAANQADCgMIBgAAAA==.Asherabinx:BAAANQABCgYIDgAAAA==.Astesia:BAAANQAECgIJAgAAAA==.Astrraa:BAAANQADCgcICAAAAA==.Asulo:BAAANQAECgYIBgABNQAECgkJGAAIAAckAA==.',
At='Atrejha:BAAANQAFFAEIAgAAAA==.',
Au='Aurä:BAAANQAECgYIDwABNQAECgcIEwABAAAAAA==.',
Av='Avera:BAAANQADCgYIBgAAAA==.',
Aw='Awesome:BAAANQAECgEIAgAAAA==.',
Az='Azgkrimpatul:BAAANQADCgYICwAAAA==.Azrina:BAAANQAECgYIEgAAAA==.',
Ba='Bael:BAAANQAECgQIBAAAAA==.Baidden:BAAANQADCgMIBQAAAA==.Balddk:BAAANQAECgUIBQABNQAECgYIEgABAAAAAA==.Baldrogue:BAABNQAECoEbAAQJAAkKTBlXGQBgAgAJAAcKZR1XGQBgAgAKAAgKRBA8FgAMAgALAAgK3gIbDgAnAQAAAA==.Baldwarrior:BAABNQAECoEZAAIIAAgKShXAXwAmAgAIAAgKShXAXwAmAgAAAA==.Ballflapper:BAAANQADCgcICAAAAA==.Bandidos:BAAANQADCgcJDwAAAA==.Banekin:BAAANQADCggICAAAAA==.',
Be='Beckz:BAAANQADCggIDQAAAA==.Beefhambacon:BAAANQAECgMIAwAAAA==.Behealzabub:BAAANQAECgUIBwAAAA==.Belmatride:BAAANQAECgIIBwAAAA==.Belpepper:BAAANQAECggIEAAAAA==.Bendelmonte:BAAANQADCggIGgABNQAECgQICQABAAAAAA==.',
Bi='Biggum:BAAANQADCgIIAgAAAA==.Bigmez:BAAANQAECgQIBAAAAA==.Bigmoocowii:BAAANQADCgIIAgAAAA==.Bigswangindi:BAAANQADCggIEAAAAA==.Bilipmonk:BAAANQAECgcIDgAAAA==.Bindinglight:BAACNQAFFIEFAAMHAAIKYgSFGQCEAAAHAAIKYgSFGQCEAAAMAAEKdwXkDwBCAAA1AAQKgTYAAwcACQrVFNYxAA0CAAcACAotFdYxAA0CAAwACArKEQMcAAACAAAA.Birdofhermes:BAAANQADCgMIAwAAAA==.Bizzthewizz:BAAANQADCgQIBAAAAA==.Biñx:BAAANQABCgQJCQAAAA==.',
Bl='Blarr:BAAANQAECgMIAwAAAA==.Blindehunter:BAAANQADCgIIAgABNQADCgIIAgABAAAAAA==.Blindvoid:BAAANQAECgIIAgABNQADCgIIAgABAAAAAA==.Bloodguard:BAAANQADCgYIBgAAAA==.Blubinax:BAAANQADCgQIBAAAAA==.Bluedabodeba:BAAANQADCgEIAQAAAA==.Bluejeanz:BAAANQADCgYIBQABNQAECgcIEwABAAAAAA==.',
Bo='Boonkay:BAAANQADCgEIAQAAAA==.Boonkie:BAAANQAECgEIAQAAAA==.Boonksdeath:BAAANQADCgIIAgAAAA==.Boonksdragon:BAAANQADCggIEQAAAA==.Boonlock:BAAANQADCgIIAgAAAA==.Boreowlis:BAAANQABCgQICAAAAA==.Boxbeater:BAAANQADCgYIBgAAAA==.',
Br='Braedravia:BAAANQADCgIIAgAAAA==.Bretikus:BAAANQAECgYIBgAAAA==.Brisanna:BAAANQAECgQICAAAAA==.',
Bu='Bubos:BAAANQADCgIJAgAAAA==.Budgeroo:BAAANQAECgUIBAAAAA==.',
['Bà']='Bàwlz:BAAANQAECgQIBwAAAA==.',
['Bè']='Bèérsërk:BAAANQADCgEIAQAAAA==.',
Ca='Caelix:BAAANQADCgQIBQAAAA==.Caledor:BAAANQAECgUICgAAAA==.Calkhan:BAAANQADCgMIAwAAAA==.Camitriel:BAABNQAECoHTAAMNAAgKxyYGBACcAwANAAgKxCYGBACcAwAOAAQKAyWDFgCrAQAAAA==.Castratôr:BAAANQADCggIEAAAAA==.',
Ce='Ceaserianoma:BAAANQADCgMIAwAAAA==.',
Ch='Chadder:BAAANQAECggIEAAAAA==.Charliie:BAABNQAECoEZAAIPAAgKkCCoBQDXAgAPAAgKkCCoBQDXAgAAAA==.Chaunakoala:BAAANQADCgIIAgAAAA==.Cherryfudge:BAAANQADCggIDQAAAA==.Chipinwing:BAAANQAECgEIAQAAAA==.Chunkysoupz:BAAANQADCgYIBgAAAA==.',
Cl='Classyshammy:BAAANQADCggJDAAAAA==.Clockworks:BAAANQADCgcIDwAAAA==.Clouxdyskies:BAAANQADCgEIAQAAAA==.',
Co='Cocinegr:BAABNQAECoEVAAINAAYKQA0xmQBCAQANAAYKQA0xmQBCAQABNQAFFAIIBgAGADcSAA==.Coneja:BAABNQAECoEaAAIGAAgKdgoguQDDAQAGAAgKdgoguQDDAQAAAA==.Coomspit:BAAANQAECgIIAgAAAA==.Corwa:BAAANQAECgEIAQABNQAECggICQABAAAAAA==.Covidnynteen:BAAANQADCgMIAwAAAA==.Cowtastrophe:BAAANQABCgcIEAAAAA==.',
Cr='Craiso:BAAANQAECgYIEgAAAA==.Crankinhawg:BAAANQAECgcIEwAAAA==.Crazbezzul:BAAANQADCgUIBwAAAA==.Creationz:BAAANQADCgYICQABNQAECgEJAQABAAAAAA==.Crisarrow:BAAANQADCggIGAAAAA==.',
Cu='Current:BAABNQAECoEWAAIQAAcKEAVgQwA1AQAQAAcKEAVgQwA1AQAAAA==.',
Cy='Cynesh:BAACNQAFFIEWAAMRAAYKPyE1AQA6AgARAAYKOyE1AQA6AgASAAQKDhZ6CwAxAQA1AAQKgR4AAxEACQrMJboJAHADABEACQrDJboJAHADABIABwpRIeMeABwCAAAA.Cytl:BAAANQAECgYIBwAAAA==.',
Da='Dailybuilt:BAAANQADCgQICgAAAA==.Dangybangy:BAAANQAECgQIDAAAAA==.Danjaianka:BAAANQADCggJHgAAAA==.Darkken:BAAANQADCgYJBgABNQADCgcIDwABAAAAAA==.Darkkragmur:BAAANQAECgUICAAAAA==.Darknest:BAAANQADCgQIBgAAAA==.Darthimus:BAAANQAECgIIAwAAAA==.Datbishkarma:BAAANQAECgQIDAAAAA==.',
Dd='Dding:BAABNQAECoElAAMDAAkK8CR+AQC0AwADAAkK8CR+AQC0AwAEAAEKEwFkgAEEAAAAAA==.',
De='Deadbarcy:BAAANQAECgIJAgAAAA==.Deathklok:BAAANQAECgYICgAAAA==.Deathran:BAABNQAECoEbAAINAAcKsxhcWwD3AQANAAcKsxhcWwD3AQAAAA==.Deezgrips:BAABNQAECoEkAAITAAgKNB0XGgCsAgATAAgKNB0XGgCsAgAAAA==.Deffgwip:BAAANQAECgUICAAAAA==.Delfine:BAAANQADCggIHQAAAA==.Demonikiarly:BAAANQADCgUJBQABNQAECgYJCAABAAAAAA==.Desimus:BAAANQADCgcJCgAAAA==.Despott:BAAANQAECgYIEgAAAA==.Destina:BAAANQAECgQIBAAAAA==.Dethfox:BAAANQAECgQICQAAAA==.Dethlock:BAAANQADCgQIBAAAAA==.',
Di='Dioni:BAABNQAECoEbAAMUAAgK5yDvGADeAgAUAAgK5yDvGADeAgAVAAUK5QkYmgANAQABNQAECggIHQAMAEodAA==.Dirknasty:BAAANQAECgQJBwAAAA==.Diyfootjobs:BAAANQADCgYJGgAAAA==.',
Dk='Dkurther:BAAANQAECgQIBAAAAA==.',
Do='Doggybag:BAAANQADCgQIBAAAAA==.Doublehelix:BAAANQAECgYICAAAAA==.Dovish:BAAANQAECgcIDAAAAA==.',
Dr='Drackygacky:BAAANQAECgEIAgAAAA==.Dracw:BAAANQADCgUIBQAAAA==.Draglox:BAAANQADCgMIBAAAAA==.Drakaryss:BAAANQADCgEIAQABNQAECgkJJAAWAMcgAA==.Drama:BAAANQAECgEIAQAAAA==.Drashar:BAAANQADCgUIBQAAAA==.Dravenm:BAAANQAECgUIDQAAAA==.Draz:BAAANQAECgMIAwAAAA==.Droozh:BAAANQADCgMIAwAAAA==.Drunkendrago:BAAANQADCgcIBwAAAA==.',
Du='Duesenjaeger:BAAANQADCgEIAQAAAA==.Duko:BAAANQADCgEIAQAAAA==.',
['Dè']='Dèmonic:BAAANQAECgQIBQAAAA==.',
['Dé']='Désy:BAAANQAECgMIAwAAAA==.',
['Dø']='Døric:BAAANQADCgcJDAAAAA==.',
['Dü']='Dürinn:BAAANQADCgIIAgAAAA==.',
Ec='Ectoplasm:BAAANQAECggICAAAAA==.',
Eh='Ehud:BAABNQAECoEXAAIEAAcK7B8OQQCIAgAEAAcK7B8OQQCIAgAAAA==.',
Ei='Eisiss:BAAANQABCgEIAQAAAA==.',
Ek='Ekô:BAAANQADCggIDgAAAA==.',
El='Elabrate:BAAANQADCgMIAwAAAA==.Elade:BAAANQADCgUIBQAAAA==.Elbori:BAABNQAECoEWAAIXAAgK4xOuAQA4AgAXAAgK4xOuAQA4AgAAAA==.Elbryan:BAAANQADCgMIAwAAAA==.Elementium:BAAANQAECgYICAAAAA==.Elfmas:BAAANQAECgYICQAAAA==.Elviswong:BAAANQADCgIIAgAAAA==.',
Em='Emerhy:BAAANQAECgEJAQAAAA==.',
Es='Escänor:BAAANQAECgcIDAAAAA==.Eshaia:BAAANQADCgEIAQAAAA==.',
Ex='Exlisum:BAAANQADCgQIBgAAAA==.',
Ey='Eyewyn:BAAANQABCgYIBQAAAA==.Eylos:BAAANQADCggIDAAAAA==.',
Fa='Faesmite:BAAANQADCgUIBQAAAA==.Faithflop:BAAANQAECgQIBgAAAA==.Falleh:BAAANQADCgIIAgAAAA==.Fanorage:BAAANQAECgIIAgAAAA==.',
Fe='Felixox:BAAANQAECgEIAQAAAA==.Ferocias:BAAANQAECgQJBQAAAA==.',
Fi='Fiametta:BAAANQADCggICAAAAA==.Fishbreath:BAAANQAECgEIAQAAAA==.',
Fl='Flaffergan:BAAANQAECgUICgAAAA==.Flexhack:BAAANQAECgQIBwAAAA==.Flåsh:BAAANQAECgcIEAAAAA==.',
Fo='Focinnet:BAABNQAECoEaAAIRAAYKiAvupwBLAQARAAYKiAvupwBLAQAAAA==.Forandra:BAAANQAECgIIAgAAAA==.Fortyacres:BAAANQADCgEIAQAAAA==.Fortybmh:BAAANQADCgEIAQABNQADCgEIAQABAAAAAA==.Four:BAAANQADCgYJDgAAAA==.Fourform:BAAANQADCgIIAgAAAA==.',
Fr='Frieren:BAAANQAECgUIBgAAAA==.',
Fu='Fuzzbutt:BAAANQADCgEIAQAAAA==.',
Ga='Gaalit:BAAANQADCgcIBwAAAA==.Galaxybone:BAAANQADCgQIBAAAAA==.Galithiri:BAAANQAECgEIAQAAAA==.Ganthani:BAAANQAECgUIEAAAAA==.Garzett:BAABNQAECoEfAAIHAAgKvRbeKwA6AgAHAAgKvRbeKwA6AgAAAA==.Gatortooth:BAAANQABCgIIBAAAAA==.Gaybeowners:BAAANQAECgEJAQAAAA==.',
Ge='Geigh:BAAANQADCgUIBQAAAA==.Gethellar:BAAANQAECgYIBwAAAA==.',
Gh='Ghostdaliar:BAAANQADCgQIBgAAAA==.Ghouliana:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Gl='Glizyglober:BAAANQADCgMIAwABNQAFFAIIBQAHAGIEAA==.Glizzyrizily:BAAANQADCgMIAwABNQAFFAIIBQAHAGIEAA==.Glizzyys:BAAANQAECggICQABNQAFFAIIBQAHAGIEAA==.Gllizzard:BAAANQADCgMJAwAAAA==.Gluckglucks:BAAANQABCgQIBAAAAA==.',
Go='Gordo:BAAANQAECggICQAAAA==.Gore:BAAANQAECgIIAgAAAA==.Gorrock:BAAANQAECgQIBAAAAA==.',
Gr='Gravtech:BAAANQADCggJDgABNQAECgQIBwABAAAAAA==.Grenzo:BAAANQAECgEIAgAAAA==.Grhm:BAAANQAECgYIBgAAAA==.Grim:BAABNQAECoEfAAMYAAkKgSFYEQD7AgAYAAkKeyFYEQD7AgAZAAMKciG3RgAkAQABNQAFFAQIBAABAAAAAA==.Grymnir:BAAANQAECgQIBwAAAA==.',
Gu='Guilliman:BAAANQAECgEIAQAAAA==.Gumsy:BAAANQAECgUIDAABNQAECgYIEQABAAAAAA==.',
['Gø']='Gørë:BAAANQAECgQIBAAAAA==.',
Ha='Haddassah:BAAANQADCgIIAgAAAA==.Haramzadi:BAAANQADCgQICQAAAA==.Haranue:BAAANQAECgQIDQAAAA==.Harryporter:BAAANQAECgEIAQAAAA==.Harukà:BAAANQAECgUIDAAAAA==.',
He='Healscat:BAAANQADCgUJBQAAAA==.Healsdog:BAAANQAECgEIAQAAAA==.Hecâte:BAAANQABCggICgAAAA==.Helfon:BAABNQAECoEcAAIQAAgKrB9sEQDeAgAQAAgKrB9sEQDeAgAAAA==.Helgadknight:BAAANQABCgMIAwAAAA==.Helganelf:BAAANQAECgEJAQAAAA==.Helices:BAAANQAECggIDwAAAA==.Herm:BAAANQAECgEIAQAAAA==.',
Hi='Highlordt:BAABNQAECoEdAAQaAAgK9hd0GQA7AgAaAAgK9hd0GQA7AgAbAAUKtRLifQAuAQAcAAEKrwd3JAAuAAAAAA==.Highlordtron:BAAANQAECgcIDQAAAA==.Hinoxfine:BAAANQADCgMIBAAAAA==.',
Ho='Holybeast:BAAANQADCgIIAgAAAA==.Holycharge:BAAANQAECgIIAgAAAA==.Holycrab:BAAANQAECgEIAQAAAA==.Holydudy:BAAANQAECgEIAQAAAA==.Holyely:BAAANQAECgIIAgAAAA==.Holyfae:BAABNQAECoEhAAIdAAkK8xMjLAB+AgAdAAkK8xMjLAB+AgAAAA==.Holygrom:BAABNQAECoEiAAIEAAkK0CMDCQCeAwAEAAkK0CMDCQCeAwAAAA==.Holynutzz:BAAANQAECgMIAwAAAA==.Holysplash:BAAANQAECgYIDgAAAA==.Holyvoids:BAAANQADCgIIAgAAAA==.Hondodk:BAECNQAFFIELAAIYAAQKyyAyBQBsAQAYAAQKyyAyBQBsAQA1AAQKgSsAAxgACQq4Js4BANADABgACQqwJs4BANADABMAAQrDJnGTAHEAAAE1AAUUBQgKABgAjCEA.Honeyshamwow:BAAANQADCgQIBAAAAA==.Hoodadin:BAAANQABCgMIAwAAAA==.Hoodlummon:BAAANQADCggJHQAAAA==.Hopesfall:BAAANQAECgIJAwAAAA==.Howzitcuz:BAAANQADCgcIFAABNQAECgUIDAABAAAAAA==.Hozari:BAABNQAECoEhAAIHAAgKZBZCLAA3AgAHAAgKZBZCLAA3AgAAAA==.',
Ht='Ht:BAAANQADCgcICAAAAA==.',
['Hã']='Hãvøc:BAAANQADCgIIAgAAAA==.',
Ia='Ianil:BAAANQAECgIJAwAAAA==.',
Ic='Iccyhot:BAAANQADCgMIAwABNQAFFAIIBQAHAGIEAA==.',
Ii='Iiwhiskey:BAAANQADCgcIBwAAAA==.',
Il='Ilirranna:BAAANQAECgIIBAAAAA==.',
In='Infi:BAACNQAFFIEcAAMSAAcK9yEZAQCbAgASAAcKIB0ZAQCbAgARAAEKLyXEHQBuAAA1AAQKgS8AAxIACQrcJW0BAMwDABIACQrcJW0BAMwDABEAAQrZJtr7AHMAAAAA.Initabath:BAAANQAECggIDAAAAA==.Initapoop:BAAANQAECgIIAwAAAA==.Inosukè:BAABNQAECoEkAAIWAAkKxyAkAwBkAwAWAAkKxyAkAwBkAwAAAA==.Invisibro:BAAANQAECgQIBwAAAA==.',
Io='Ioannis:BAAANQAECgMIBQAAAA==.',
Is='Isos:BAABNQAECoEjAAMbAAgKKx3JJwCPAgAbAAgKKx3JJwCPAgAcAAEKCBBxHwA7AAAAAA==.Isus:BAAANQADCgYJBgABNQAECggIIwAbACsdAA==.',
Iy='Iykyk:BAAANQADCgQIDAABNQAECgUIDAABAAAAAA==.',
Ja='Jadeadly:BAAANQAECgcICAAAAA==.Jaded:BAABNQAECoEfAAIeAAkKNhQvGQAmAgAeAAkKNhQvGQAmAgAAAA==.Jakerbonk:BAAANQADCgYIBwAAAA==.Jakersai:BAAANQAECgUICgAAAA==.Jakersaint:BAAANQADCgUIBQAAAA==.Javyr:BAAANQAECgUICAAAAA==.Jayfmtv:BAAANQAECgIIAgAAAA==.',
Je='Jessicax:BAAANQAECgQIBAAAAA==.Jetpackcat:BAAANQADCgIIAgAAAA==.',
Jl='Jlnxy:BAAANQAECgcIDwAAAA==.',
Jo='Joania:BAAANQADCggICAAAAA==.Jonoa:BAAANQADCgUIBQAAAA==.',
Ju='Judo:BAAANQADCgUICwAAAA==.',
Ka='Kadre:BAAANQAECgUICQAAAA==.Kadzilak:BAAANQADCgQIBgAAAA==.Kagemika:BAAANQAECgQIBAABNQAFFAEIAgABAAAAAA==.Kaiola:BAAANQAECgEIAQAAAA==.Kaizumie:BAAANQAECgIIAgAAAA==.Kamistri:BAAANQAECgYIDwAAAA==.Kanaa:BAAANQAECgIIAgAAAA==.Kanatre:BAAANQADCgEIAQAAAA==.Karessandra:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Karrison:BAAANQADCgEIAQAAAA==.Kathea:BAAANQADCgIIAgAAAA==.Kayarra:BAAANQADCgEIAQABNQADCgQIBAABAAAAAA==.Kaynarra:BAAANQADCgQIBAAAAA==.Kayonna:BAAANQABCgEIAQABNQADCgQIBAABAAAAAA==.',
Ke='Keastral:BAAANQAECgQIBAAAAA==.Keeynai:BAAANQADCgQIBAAAAA==.Keldanis:BAABNQAECoEaAAIRAAYKuhkNbQDeAQARAAYKuhkNbQDeAQAAAA==.Kelestrah:BAAANQADCgQJBAAAAA==.Kelterrager:BAAANQADCgMIAwAAAA==.Keony:BAAANQAECgUIDAAAAA==.Kerthur:BAAANQADCgYJCAAAAA==.',
Ki='Kickpigeons:BAAANQABCgQIBgAAAA==.Killertcells:BAAANQABCgIIAgAAAA==.Kirgrand:BAAANQADCgMIAwAAAA==.Kittyarly:BAAANQAECgYJCAAAAA==.',
Ko='Kodeck:BAAANQADCggIGQAAAA==.Kodokan:BAAANQADCgYIDQAAAA==.Koshima:BAABNQAECoEdAAIVAAgKTRP/RQAQAgAVAAgKTRP/RQAQAgAAAA==.Kozan:BAAANQADCgUICAAAAA==.',
Kr='Kreamer:BAAANQAECgEIAQAAAA==.Krimdan:BAAANQADCgQIBAAAAA==.Krimhit:BAAANQADCgUICwAAAA==.Krimrok:BAAANQABCgIIAgAAAA==.Krimwarr:BAAANQADCgQIBAAAAA==.',
Ku='Kudranne:BAAANQADCgQICAABNQAECgEIAQABAAAAAA==.Kugia:BAABNQAECoEdAAIMAAgKSh0QEACbAgAMAAgKSh0QEACbAgAAAA==.',
Ky='Kylex:BAAANQAECgEIAQAAAA==.Kynndell:BAAANQADCggIGQAAAA==.Kyo:BAAANQADCgYIDgAAAA==.',
['Kø']='Køkushibø:BAAANQABCgUIBQAAAA==.',
La='Laments:BAAANQADCgUIBQAAAA==.Latak:BAAANQADCgMIAwAAAA==.Latir:BAAANQADCgUIBwAAAA==.Lazyryx:BAAANQADCgUIBQAAAA==.',
Le='Leetheal:BAACNQAFFIEIAAMbAAQKxgSKFQDgAAAbAAMKdAWKFQDgAAAaAAMKvwQDCwDPAAA1AAQKgSIAAxsACQpmEWpHAAACABsACApQEWpHAAACABoABwr/GrwfAPABAAAA.Leethul:BAAANQAECgYIEgAAAA==.Lelethxx:BAAANQAECgIIAwAAAA==.Lesanna:BAABNQAECoEgAAIQAAgKtgipNQCdAQAQAAgKtgipNQCdAQAAAA==.Leysmith:BAABNQAECoEhAAIEAAgKTBFGdgDgAQAEAAgKTBFGdgDgAQAAAA==.',
Li='Lifestream:BAAANQAECgIIAgAAAA==.Lilheal:BAAANQAECgIJAgAAAA==.Lilium:BAAANQADCgYICwAAAA==.Lionël:BAAANQAECgQIBAAAAA==.Lizbethe:BAAANQAECgcIEwAAAA==.',
Lo='Lockmclovin:BAAANQADCgMIAwAAAA==.Lomrgreenol:BAAANQADCgQIBAAAAA==.Lopi:BAAANQAECgMIAwAAAA==.Lorast:BAAANQAECgEIAQAAAA==.Lorwater:BAAANQADCgQIBAAAAA==.Loveinfinity:BAAANQABCgIIAgAAAA==.',
Lp='Lp:BAAANQADCgQIBAAAAA==.',
Lu='Lumibell:BAAANQABCgYIBwAAAA==.Lunaryon:BAAANQADCgUICgAAAA==.',
Ma='Madamgypsy:BAAANQAECgIIAgAAAA==.Madderco:BAAANQAECggICAAAAA==.Madivh:BAAANQADCgQIBAAAAA==.Magaspy:BAAANQAECgMIBAAAAA==.Magerage:BAAANQAECgEIAQAAAA==.Magikiarly:BAAANQADCgYIDwABNQAECgYJCAABAAAAAA==.Mahoogany:BAAANQADCgYIDAAAAA==.Mamimage:BAACNQAFFIEGAAIGAAIKNxJNNACcAAAGAAIKNxJNNACcAAA1AAQKgS8AAgYACQrYIPQbAFQDAAYACQrYIPQbAFQDAAAA.Marukka:BAAANQADCgQIBAABNQADCgcIBwABAAAAAA==.Matty:BAAANQADCgEIAQAAAA==.Mayiana:BAAANQADCggICQAAAA==.',
Me='Meadowlark:BAAANQAECgIIAgAAAA==.Mefistofeles:BAAANQAECgQICgAAAA==.Mellie:BAAANQADCgQIBQAAAA==.Meowstic:BAABNQAECoEXAAIfAAgK3h/nBQDbAgAfAAgK3h/nBQDbAgABNQAECgIIAgABAAAAAA==.Mercurious:BAAANQAECgMIAwAAAA==.Metalrules:BAAANQABCggICAAAAA==.Methypheni:BAAANQAECgYICAAAAA==.',
Mi='Milfshotz:BAAANQADCgIIAgAAAA==.Mill:BAAANQADCgYICgAAAA==.Minimuff:BAAANQADCgUIBQAAAA==.Mirajanna:BAABNQAECoEfAAIgAAgKyxQpCQD8AQAgAAgKyxQpCQD8AQAAAA==.Missmouthoff:BAAANQAECgYIEgAAAA==.Mitenâ:BAAANQADCgUIBgAAAA==.Mizzxgummy:BAAANQAECgcIBwAAAA==.',
Mo='Monkin:BAAANQAECgEIAQAAAA==.Moogan:BAAANQAECgEIAQAAAA==.Mookins:BAAANQAECgYIEgAAAA==.Moonfishing:BAABNQAECoEYAAIGAAkKyxG3cQBmAgAGAAkKyxG3cQBmAgAAAA==.Moonfly:BAACNQAFFIEFAAIHAAMKEw9rEADpAAAHAAMKEw9rEADpAAA1AAQKgSAAAgcACQpUICMNAEQDAAcACQpUICMNAEQDAAAA.Morax:BAAANQAECgIIAwAAAA==.Mourne:BAAANQAECgcIEQAAAA==.',
Ms='Mssmalvile:BAAANQADCgYJCwAAAA==.',
My='Myrrvain:BAAANQAECgEIAQAAAA==.Mythara:BAAANQADCgYIBgAAAA==.',
Na='Naarcissus:BAAANQABCgIIAgAAAA==.Nagrim:BAAANQADCgYICQABNQAECgYIEQABAAAAAA==.Nalaana:BAAANQAECgEIAgAAAA==.Nalariel:BAABNQAECoEbAAIYAAgKNh7dIwBlAgAYAAgKNh7dIwBlAgAAAA==.Nalmagedan:BAAANQAECgQIBwAAAA==.Nammi:BAAANQADCgMJAwAAAA==.Nandorr:BAAANQADCgEIAQAAAA==.Narec:BAAANQADCgUIBQAAAA==.Narfhound:BAAANQADCgYICAAAAA==.Nazgrok:BAAANQAECgIIBAAAAA==.',
Ne='Nearhammer:BAAANQAECgEIAQAAAA==.Nefariouz:BAAANQAECggIAQAAAA==.Nervouz:BAAANQAECgYIDgAAAA==.Netherpally:BAAANQADCgQJBAAAAA==.',
Ni='Nikis:BAAANQADCgcIDwAAAA==.',
No='Nobbs:BAAANQAECgQIBAAAAA==.Noonecaress:BAAANQAECgIIAgAAAA==.',
Nu='Nualaperafin:BAABNQAECoElAAIhAAkKnx3OBAAoAwAhAAkKnx3OBAAoAwAAAA==.',
Ny='Nyvara:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Nyxkitsune:BAAANQADCggIDQAAAA==.',
Oi='Oiyo:BAAANQABCggICQAAAA==.',
Ok='Okonomiyaki:BAAANQADCgcIBwAAAA==.',
Ol='Olayro:BAABNQAECoEZAAMCAAgKMgymCACwAQACAAcKGw2mCACwAQANAAcKmQakmgA/AQAAAA==.',
Om='Omie:BAAANQADCgYIEAAAAA==.',
On='Onkiea:BAAANQABCgYJBAAAAA==.Onlyrage:BAAANQAECgUJCQAAAA==.',
Oo='Oomkin:BAAANQADCgQIBAAAAA==.Ooptomss:BAABNQAECoEYAAIRAAcKjxQjYQD/AQARAAcKjxQjYQD/AQAAAA==.',
Op='Openingshift:BAAANQAECgEIAQAAAA==.Ophelìa:BAAANQADCgcIBwAAAA==.Ophilitheda:BAAANQADCgYJAwAAAA==.',
Or='Orclee:BAAANQAECgYIEQAAAA==.',
Pa='Pacificadora:BAAANQAECgIIBAAAAA==.Palaguy:BAAANQADCgQIBAAAAA==.Palkavanka:BAAANQAECgQIBwAAAA==.',
Pe='Peeonfists:BAAANQADCgEIAQAAAA==.Persephie:BAAANQAECgMIBAABNQAECgYIEQABAAAAAA==.Perzeval:BAAANQADCgMJAwAAAA==.',
Ph='Pharmacology:BAAANQAECgQICwAAAA==.Phyberlamer:BAAANQADCgEIAQAAAA==.Phénicie:BAAANQADCgYIEgAAAA==.',
Pi='Pinkberri:BAAANQAECgEIAQAAAA==.Pipha:BAAANQABCgQIBQAAAA==.Pitchblack:BAAANQADCggIDQAAAA==.',
Po='Popa:BAABNQAECoEqAAMdAAkKsBmhHwDBAgAdAAkKsBmhHwDBAgAEAAUKDhmNqQBcAQAAAA==.',
Pr='Prathe:BAAANQAECgUICQAAAA==.Prayinfury:BAAANQAECgYIBwAAAA==.Premorry:BAAANQAECgIIAgAAAA==.Premory:BAAANQADCgUICQAAAA==.Presagee:BAAANQADCgEIAQAAAA==.',
Ps='Psilocy:BAAANQAECgYIDgAAAA==.',
Pu='Pulsate:BAAANQAECgcIEQAAAA==.Purpleduster:BAAANQADCgEIAQAAAA==.',
Py='Pyllo:BAAANQAECggJCgAAAA==.',
Qa='Qaucker:BAAANQAECgYIBgAAAA==.',
Qi='Qiz:BAAANQAECgQIDAAAAA==.Qizknows:BAAANQADCgEIAQAAAA==.',
Qu='Quadhelix:BAAANQAECgQICwAAAA==.Quartermain:BAAANQAECggIBwAAAA==.',
Qw='Qwish:BAAANQADCgYIBgAAAA==.',
Ra='Rad:BAAANQAECgcIBwAAAA==.Radlock:BAAANQAECgMIAQABNQAECgcIBwABAAAAAA==.Ragémachine:BAAANQADCgQIBAAAAA==.Raiken:BAAANQAECgEIAQAAAA==.Rakmin:BAAANQADCggICwAAAA==.Rarib:BAAANQADCgcIBwAAAA==.Rasto:BAAANQAECgQJBwAAAA==.Raszto:BAAANQADCgIIAgABNQAECgQJBwABAAAAAA==.Rattlebat:BAAANQAECgIIAgAAAA==.',
Re='Redmark:BAAANQADCgUIBgAAAA==.Rendezook:BAAANQAECgQIBgAAAA==.Respec:BAAANQADCggICAAAAA==.',
Ri='Rincewind:BAAANQADCggIFQAAAA==.Riohne:BAAANQADCgMIAwAAAA==.Rivexis:BAAANQADCgIIAgAAAA==.',
Ro='Roci:BAAANQADCggIEAAAAA==.Rocker:BAAANQAECggICAAAAA==.Rootway:BAAANQADCgIIAgAAAA==.Roxus:BAABNQAECoEZAAIIAAcKHCPVMgDDAgAIAAcKHCPVMgDDAgAAAA==.Roxusdruid:BAAANQAECgcIBwABNQAECgcIGQAIABwjAA==.',
Ru='Ruthlin:BAAANQADCgYIBgAAAA==.',
Sa='Saegusa:BAAANQAECgQIBwAAAA==.Saepius:BAAANQAECgIIAgAAAA==.Salestia:BAAANQAECgYIDQAAAA==.Samellir:BAAANQAECgIIAwAAAA==.Sanlanesh:BAAANQADCgUIBQAAAA==.Sardothien:BAAANQADCgEIAQAAAA==.Sasive:BAAANQAECgUIBwAAAA==.Satanicpanic:BAAANQAECgQIBQAAAA==.Sazoku:BAABNQAECoEYAAIIAAkK7Rw2JwD0AgAIAAkK7Rw2JwD0AgAAAA==.',
Sc='Scarletnight:BAAANQADCggIDgABNQAECgYIEgABAAAAAA==.Schmall:BAAANQAECgUIBwAAAA==.Scrodumpulse:BAAANQADCgcICwAAAA==.',
Se='Selvalin:BAAANQADCgYIBgAAAA==.Sendit:BAAANQAECgcICQAAAA==.Seniormage:BAAANQAECgUIBgAAAA==.Serveil:BAAANQADCgIIAgABNQAECgkJGQAiABMHAA==.',
Sh='Shadesprint:BAAANQAECggIBwAAAA==.Shadowhor:BAAANQAECgUIBwABNQAECggIIQANAIIdAA==.Shamamoomoo:BAAANQAECgcIEwAAAA==.Shaninigans:BAAANQADCgEIAQAAAA==.Shaowen:BAAANQADCgYIBgABNQAECgIIBAABAAAAAA==.Shaqeesha:BAAANQADCgUIBQAAAA==.Shenea:BAAANQADCgYICQAAAA==.Shestalker:BAABNQAECoEpAAIRAAkKIRVzOwByAgARAAkKIRVzOwByAgAAAA==.Shiau:BAAANQAECgcIDQAAAA==.Shimura:BAAANQADCgEIAQAAAA==.Shinky:BAAANQADCgUIBAABNQAECgYIDQABAAAAAA==.Shý:BAAANQAECgQICAAAAA==.',
Si='Silana:BAAANQADCgUIBQAAAA==.Silvaine:BAAANQAECgQIBAAAAA==.Silverstorm:BAABNQAECoEYAAIIAAgKxBEVdgDkAQAIAAgKxBEVdgDkAQAAAA==.Sixii:BAAANQAECgMIAwAAAA==.',
Sk='Skitzz:BAAANQAECgQICAAAAQ==.',
Sl='Slackr:BAAANQADCgUIBQAAAA==.Slackrm:BAAANQADCgMJBwAAAA==.Slackrp:BAAANQADCgIJAgAAAA==.Slashyr:BAAANQAECgQIDAAAAA==.Slimshadydh:BAAANQAECgQIBAAAAA==.',
Sn='Snipez:BAAANQAECgIJAwAAAA==.Snortyhotorc:BAAANQAECgIIBAAAAA==.Snortymcgoop:BAABNQAECoEXAAISAAgKqRRRIAANAgASAAgKqRRRIAANAgAAAA==.',
So='Solclipeus:BAABNQAECoEmAAIDAAgKaSFxCADhAgADAAgKaSFxCADhAgAAAA==.Soldh:BAAANQAECgUJCgABNQAECggIJgADAGkhAA==.Sollock:BAAANQAECggICwABNQAECggIJgADAGkhAA==.Soulrecall:BAAANQAECgIIAgAAAA==.Soupz:BAAANQAECgUICwAAAA==.',
Sp='Sparadin:BAAANQAECgQIBQAAAA==.Spartacûs:BAAANQAECgQJBQABNQAECgYIBgABAAAAAA==.Spikore:BAAANQADCgYIBgAAAA==.Splitpeaz:BAAANQADCgcJBwAAAA==.',
Sq='Squrìtle:BAAANQADCgcJBwAAAA==.',
Sr='Sririacha:BAAANQADCgUIBQABNQAECggIBwABAAAAAA==.',
St='Stabbyjohn:BAAANQADCggICAAAAA==.Stabbypickle:BAAANQAECgYICQABNQAECgYIDgABAAAAAA==.Stachelbeere:BAAANQADCgYIBgAAAA==.Stickybug:BAAANQADCggICAAAAA==.Strånge:BAAANQAECgYIBwAAAA==.Stìtch:BAACNQAFFIEKAAINAAUK2xsZBgCvAQANAAUK2xsZBgCvAQA1AAQKgScAAg0ACQpoJUQDAKwDAA0ACQpoJUQDAKwDAAAA.Stítch:BAAANQADCgQIBAABNQAFFAUICgANANsbAA==.',
Su='Sukiafaunias:BAAANQAECgEIAgAAAA==.Sukiafloras:BAAANQAECgIIAgAAAA==.Suldån:BAAANQADCggIIQAAAA==.Sunfurious:BAAANQAECgUIBgAAAA==.Suoop:BAAANQADCgYJCgAAAA==.',
Sw='Swiftshaman:BAAANQAECgEIAQAAAA==.',
Sy='Synvaria:BAAANQAECgEIAQAAAA==.Syraice:BAAANQADCgUIBQABNQAECggIIwAiAIgaAA==.Syrare:BAAANQADCgcIDwAAAA==.Syvenari:BAAANQAECgMIBgAAAA==.',
['Sï']='Sïxx:BAAANQADCgMJAwABNQAECgMIAwABAAAAAA==.',
Ta='Tachisan:BAAANQAECgIJBAAAAA==.Taeril:BAAANQADCgQIBAAAAA==.Tamfam:BAAANQADCggJEAAAAA==.Tanburn:BAAANQADCgYICwAAAA==.Tanduinex:BAAANQADCgYIDAAAAA==.Tangal:BAAANQADCgYICgAAAA==.Tankstabber:BAAANQADCgQIBQAAAA==.Tanplate:BAAANQADCgYICAAAAA==.Tarentia:BAAANQABCggIDgAAAA==.Tastytyrande:BAAANQAECgUIBQAAAA==.Tatsumy:BAAANQAECgUIEwAAAA==.',
Tc='Tcmon:BAABNQAECoEeAAIRAAgKExgrQgBbAgARAAgKExgrQgBbAgAAAA==.',
Te='Teachings:BAAANQADCgMIAwAAAA==.Teaglizzy:BAAANQADCgEIAQABNQAFFAIIBQAHAGIEAA==.Teehole:BAAANQAECgUICwAAAA==.Telihill:BAAANQADCgUIDgAAAA==.Telsarra:BAAANQAECgQIBgAAAA==.',
Th='Thalenia:BAAANQADCggIDQAAAA==.Thebigtuna:BAABNQAECoEkAAIjAAkK0CH7AwCJAwAjAAkK0CH7AwCJAwAAAA==.Theladydruid:BAABNQAECoEcAAIMAAkKnhCdGQAcAgAMAAkKnhCdGQAcAgAAAA==.Thelnaris:BAAANQADCgEIAQAAAA==.Themeats:BAAANQADCgQIBAAAAA==.Thendezoth:BAAANQAECgEIAgAAAA==.Thighsoffel:BAAANQADCgcIEwAAAA==.Thirdtjme:BAAANQADCgYIBgAAAA==.Thunderhóof:BAAANQABCgYIDQAAAA==.',
Ti='Tigerpa:BAAANQAECgQICQAAAA==.Tinkernut:BAAANQABCgIIAgAAAA==.Tinypally:BAAANQAECgEIAgAAAA==.Tinyraven:BAABNQAECoEaAAIjAAcKURVGIwDyAQAjAAcKURVGIwDyAQAAAA==.Tinystotems:BAAANQAECgQICwAAAA==.Tinythia:BAAANQADCgUIBQAAAA==.Tioklarus:BAABNQAECoEmAAIkAAcKEAgLGwBcAQAkAAcKEAgLGwBcAQAAAA==.Tisaryn:BAAANQAECgQIBAAAAA==.',
To='Tofulady:BAABNQAECoEhAAIWAAkK5R0UBgAOAwAWAAkK5R0UBgAOAwAAAA==.Tohu:BAAANQAECgYIDgAAAA==.Toshen:BAAANQADCgEIAQAAAA==.Totax:BAAANQAECgEJAQAAAA==.Totemtoker:BAAANQADCggICAAAAA==.',
Tr='Tremors:BAAANQADCggICAAAAA==.Triggër:BAAANQABCgQIBAABNQAECgEIAQABAAAAAA==.Tromb:BAAANQABCgIIBAAAAA==.',
Tw='Twobithusler:BAAANQAECgIIAgAAAA==.Twoone:BAAANQADCgQIBAAAAA==.',
Ty='Tyniarstus:BAAANQADCgYICAAAAA==.',
Ud='Udderfiasco:BAAANQABCgIIAgAAAA==.',
Ug='Uggh:BAAANQADCgUIBQAAAA==.',
Un='Unhowly:BAABNQAECoEiAAIYAAkKByUwBgB7AwAYAAkKByUwBgB7AwAAAA==.Unpoppable:BAAANQAECgUICQAAAA==.',
Uz='Uzilok:BAAANQABCgcICwAAAA==.',
Va='Vakir:BAABNQAECoEdAAITAAgKABFFPgDGAQATAAgKABFFPgDGAQAAAA==.Valmortem:BAEANQADCgcIEgAAAA==.Vapidos:BAAANQAECgIJAwAAAA==.Varynix:BAAANQAECgIIAgABNQAECgYIBwABAAAAAA==.Vatica:BAAANQAECgEIAQAAAA==.',
Ve='Velanoria:BAAANQADCggICwAAAA==.Veldorai:BAAANQADCgYICwAAAA==.Velrenya:BAAANQADCgQIBgAAAA==.Velýndriel:BAAANQADCgEIAQAAAA==.Venvalzhar:BAAANQAECgYIEwAAAA==.Veralidaine:BAAANQAECgIIAgAAAA==.Vestammeni:BAABNQAECoEbAAMPAAkK9h4qBQDoAgAPAAkK9h4qBQDoAgAIAAMK2grb7ACdAAAAAA==.Vexlore:BAAANQADCgUIBQAAAA==.',
Vi='Vixsaurion:BAAANQAECgEIAQAAAA==.',
Vo='Voltx:BAAANQAECgEIAQAAAA==.Vorn:BAAANQADCgcIBwAAAA==.Vow:BAAANQAECgYIEQAAAA==.',
Vy='Vynlenlor:BAAANQABCgIIAgAAAA==.',
Wc='Wckd:BAAANQAECgYIEgAAAA==.',
We='Weaksnow:BAAANQAECgYJDAABNQAFFAIIBgAGADcSAA==.Weedgoku:BAAANQAECgQIBAAAAA==.Weedvegeta:BAAANQAECgcIDwAAAA==.Wernbirn:BAAANQAECggIAQAAAA==.Wetremin:BAAANQADCgcIEQAAAA==.',
Wh='Whirpy:BAAANQAECgYICQAAAA==.Whisberis:BAAANQADCgMIAwAAAA==.Whitty:BAAANQADCgQIBAAAAA==.Whizkee:BAAANQAECgYICwAAAA==.',
Wi='Wildbeefwood:BAAANQADCggIDgAAAA==.Wingedlady:BAAANQAECgIIAwAAAA==.Wingss:BAABNQAECoEbAAIEAAgKvyL/HgAZAwAEAAgKvyL/HgAZAwAAAA==.',
Wu='Wushu:BAAANQAECgQICgAAAA==.',
Wy='Wyl:BAAANQAECggIDQAAAA==.',
Xe='Xerath:BAAANQAECgQIBwAAAA==.',
Xi='Xiing:BAABNQAECoEZAAMPAAgKrRB3EADBAQAPAAgKrRB3EADBAQAIAAEKTgScIQErAAAAAA==.Xinei:BAAANQADCgQIAQAAAA==.',
Xn='Xneutron:BAAANQAECgUJCAAAAA==.',
Xt='Xtravagent:BAAANQADCgIIAgAAAA==.',
Xy='Xyxia:BAAANQADCgcIBwAAAA==.',
Ya='Yaiie:BAAANQAECgYIDwAAAA==.',
Yo='Yonna:BAAANQAECgMIAwAAAA==.',
Yu='Yungholy:BAAANQAECgEIAgAAAA==.Yuuki:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Yuunggrazy:BAAANQADCgIIAgABNQAECgEIAgABAAAAAA==.',
['Yü']='Yüto:BAABNQAECoEYAAMRAAgKWxaFWAAYAgARAAgKQhWFWAAYAgASAAMKGxCsTACkAAAAAA==.',
Za='Zabuto:BAAANQAECgYIEQAAAA==.Zahäära:BAAANQADCggIGgAAAA==.Zaldiz:BAAANQADCgIIAgAAAA==.Zarrtan:BAAANQADCgcIFgAAAA==.Zazevo:BAAANQAECgMIAwAAAA==.Zazprie:BAAANQAECgMICAAAAA==.',
Ze='Zendrozath:BAAANQADCgQIBQABNQAECgIIAgABAAAAAA==.',
Zo='Zooz:BAAANQADCgIIAgAAAA==.',
Zu='Zual:BAAANQAECgIIAgAAAA==.Zularraka:BAAANQAECgEIAgAAAA==.',
Zx='Zxeý:BAAANQADCgcIDgAAAA==.',
['Äb']='Äbracadabruh:BAAANQAECgUIDgABNQAECgcIBwABAAAAAA==.',
['Äl']='Älissia:BAAANQADCgcIGQAAAA==.',
['Ål']='Ålexthegrëat:BAAANQAECgEIAgAAAA==.',
['Èm']='Èmandy:BAAANQADCggICAAAAA==.',
['Ën']='Ëndo:BAAANQAECgYIEQAAAA==.',
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
