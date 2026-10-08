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

local lookup = {'Druid-Restoration','Unknown-Unknown','Priest-Holy','Warlock-Affliction','Paladin-Protection','Paladin-Retribution','Warlock-Demonology','Mage-Frost','Mage-Arcane','Druid-Balance','Warrior-Arms','DemonHunter-Havoc','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Monk-Windwalker','Warlock-Destruction','Warrior-Protection','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Mage-Fire','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Druid-Feral','Priest-Shadow','Priest-Discipline','Druid-Guardian','DemonHunter-Vengeance','Shaman-Enhancement','Evoker-Devastation','Evoker-Preservation','DemonHunter-Devourer',}
local provider = {region='US',realm='Azshara',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aaryyee:BAAANQAECgEIAQAAAA==.',
Ac='Acaeus:BAAANQABCgQIBQAAAA==.Aceforlife:BAABNQAECoEaAAIBAAYKPAWAQwDaAAABAAYKPAWAQwDaAAAAAA==.',
Ad='Adrox:BAAANQADCgMIBAAAAA==.',
Ae='Aelelelos:BAAANQADCgcICgAAAA==.Aequus:BAAANQABCgQIAgAAAA==.Aevenyhm:BAABNQAECoEdAAIBAAcKTRrfIAD2AQABAAcKTRrfIAD2AQAAAA==.',
Ag='Aghorn:BAAANQAECgEIAgAAAA==.',
Ai='Aidoneus:BAAANQADCgYIBgABNQAFFAEIAQACAAAAAA==.',
Ak='Akijin:BAAANQABCgQIBAABNQAECgcIDgACAAAAAA==.Akismite:BAAANQAECgcIDgAAAA==.',
Al='Alaru:BAABNQAECoEcAAIDAAcKUwv5ggBUAQADAAcKUwv5ggBUAQAAAA==.Alemental:BAAANQADCgcIEgABNQAECgMIBwACAAAAAA==.Algana:BAAANQADCggIDAABNQAECggIIQAEAPEOAA==.Allhallows:BAAANQAECgUIDQAAAA==.Alorandis:BAAANQAECgIIAgAAAA==.Alqueria:BAABNQAECoEcAAMFAAkKEBk4FgAlAgAFAAgKURk4FgAlAgAGAAgKIw7ElwC+AQABNQAECgkJJgAHAOocAA==.Altarboizyum:BAAANQAECgIJAQABNQAECgkJLgAFAEwgAA==.',
An='Andanto:BAAANQAECgUIEAAAAA==.Angeliz:BAAANQAECgcICwAAAA==.Anitaloc:BAAANQAECgMIBAAAAA==.Anneweaver:BAABNQAECoEnAAMIAAkKzRyRDAC7AQAJAAkKsxnKbgCLAgAIAAgKwRmRDAC7AQABNQAFFAUIDQAJAJwQAA==.Anorantha:BAABNQAECoEgAAIKAAUK5Az9ZwABAQAKAAUK5Az9ZwABAQAAAA==.',
Ap='Apicots:BAAANQADCggIDwAAAA==.Apipa:BAAANQAECgYIBwAAAA==.Apricot:BAAANQADCgUIBQAAAA==.Apzz:BAAANQADCgIIAgAAAA==.',
Ar='Arizticat:BAAANQADCgQIBAAAAA==.Arrowin:BAAANQADCgQIBAAAAA==.Artica:BAAANQADCggICAAAAA==.Arzan:BAAANQAECgEIAQAAAA==.',
As='Ashalan:BAAANQAECgUICgAAAA==.Ashenflail:BAAANQAECgMIAwAAAA==.Asherabinx:BAAANQABCgYIDgAAAA==.Astesia:BAAANQAECgMIAwAAAA==.Astrraa:BAAANQADCggIEAAAAA==.Asulo:BAAANQAECgYIBgABNQAECgkJGwALAAckAA==.',
At='Atrejha:BAABNQAECoEdAAIMAAkKcAkSNwDEAQAMAAkKcAkSNwDEAQAAAA==.',
Au='Aurä:BAABNQAECoEYAAIJAAcKkQ0q2gCtAQAJAAcKkQ0q2gCtAQABNQAECggIFgALALEWAA==.',
Av='Avera:BAAANQAECgEIAQAAAA==.',
Aw='Awesome:BAAANQAECgQIBQAAAA==.',
Az='Azgkrimpatul:BAAANQADCgYICwAAAA==.Azmodeus:BAAANQADCgMIAwAAAA==.Azrina:BAAANQAECgYIEgAAAA==.',
Ba='Bael:BAAANQAECgUICQAAAA==.Baidden:BAAANQADCgMIBQAAAA==.Balddk:BAAANQAECgYICwABNQAECgcIGgAJAD4SAA==.Baldrogue:BAACNQAFFIEGAAINAAMKdBa2CgD/AAANAAMKdBa2CgD/AAA1AAQKgSEABA0ACQoWHNMVAKgCAA0ABwr7INMVAKgCAA4ACApEENwYAAICAA8ACAreAksPAB8BAAAA.Baldwarrior:BAABNQAECoEhAAILAAgKwReXXwBRAgALAAgKwReXXwBRAgAAAA==.Ballflapper:BAAANQADCgcICAAAAA==.Bandidos:BAAANQAECgQIBAAAAA==.Banekin:BAAANQADCggICAAAAA==.',
Be='Beckz:BAAANQADCggIDQAAAA==.Beefhambacon:BAAANQAECgMIAwAAAA==.Behealzabub:BAAANQAECgYICQAAAA==.Belmatride:BAAANQAECgIIBwAAAA==.Belpepper:BAAANQAECggIEAAAAA==.Bendelmonte:BAAANQADCggIIgABNQAECgUIDgACAAAAAA==.',
Bi='Biggum:BAAANQADCgIIAgAAAA==.Bigmez:BAAANQAECgUICQAAAA==.Bigmoocowii:BAAANQADCgIIAgAAAA==.Bigswangindi:BAAANQADCggIEAAAAA==.Bilipmonk:BAABNQAECoEWAAIQAAkKXhNeHQAfAgAQAAkKXhNeHQAfAgAAAA==.Bindinglight:BAACNQAFFIEGAAMKAAIKYgT3HQCBAAAKAAIKYgT3HQCBAAABAAEKdwXDEwA8AAA1AAQKgTwAAwoACQquFCEtAE4CAAoACQquFCEtAE4CAAEACAoBFGIfAAcCAAAA.Birdofhermes:BAAANQADCgMIAwAAAA==.Bizzthewizz:BAAANQADCgQIBAAAAA==.Biñx:BAAANQABCgQJCQAAAA==.',
Bl='Blarr:BAAANQAECgMIAwAAAA==.Blindehunter:BAAANQADCgIIAgABNQADCgIIAgACAAAAAA==.Blindvoid:BAAANQAECgIIAgABNQADCgIIAgACAAAAAA==.Bloodguard:BAAANQADCgYIBgAAAA==.Blubinax:BAAANQADCgQIBAAAAA==.Bluedabodeba:BAAANQADCgEIAQAAAA==.Bluejeanz:BAAANQADCgYIBQABNQAECgkJHAAKAPMiAA==.',
Bo='Boonkay:BAAANQADCgEIAQAAAA==.Boonkie:BAAANQAECggIAQAAAA==.Boonksdeath:BAAANQADCgIIAgAAAA==.Boonksdragon:BAAANQAECggICAAAAA==.Boreowlis:BAAANQABCgQICAAAAA==.Boxbeater:BAAANQADCgYIBgAAAA==.',
Br='Braedravia:BAAANQADCgIIAgAAAA==.Bretikus:BAAANQAECgYIBgAAAA==.Brisanna:BAAANQAECgUIDQAAAA==.',
Bu='Bubos:BAAANQADCgIJAgAAAA==.Budgeroo:BAAANQAECgUIBAAAAA==.',
['Bà']='Bàwlz:BAAANQAECgUIDAAAAA==.',
['Bè']='Bèérsërk:BAAANQADCgEIAQAAAA==.',
['Bö']='Böðull:BAAANQAECgEIAQAAAA==.',
Ca='Caelix:BAAANQADCgQIBQAAAA==.Caledor:BAAANQAECgUIDwAAAA==.Calkhan:BAAANQADCgMIAwAAAA==.Camitriel:BAABNQAECoE8AQMHAAgK8SZQBACpAwAHAAgK8SZQBACpAwARAAQKAyVBFwCqAQAAAA==.Castratôr:BAAANQADCggIEAAAAA==.',
Ce='Ceaserianoma:BAAANQADCgMIAwAAAA==.',
Ch='Chadder:BAAANQAECggIEAAAAA==.Charliie:BAABNQAECoEhAAISAAgKWSHyBQDqAgASAAgKWSHyBQDqAgAAAA==.Chaunakoala:BAAANQADCgIIAgAAAA==.Cherryfudge:BAAANQADCggIDQAAAA==.Chipinwing:BAAANQAECgEIAQAAAA==.Chunkysoupz:BAAANQADCgYIBgAAAA==.',
Cl='Classyshammy:BAAANQADCggIDAAAAA==.Clockworks:BAAANQADCgcIEwAAAA==.Clouxdyskies:BAAANQADCgEIAQAAAA==.',
Co='Cocinegr:BAABNQAECoEZAAIHAAcK6A28kgCIAQAHAAcK6A28kgCIAQABNQAFFAMICQAJABsUAA==.Coneja:BAABNQAECoEoAAIJAAgK4AvNxQDVAQAJAAgK4AvNxQDVAQAAAA==.Coolbroguy:BAAANQABCgQIBAAAAA==.Coomspit:BAAANQAECgIIAgAAAA==.Corwa:BAAANQAECgEIAQABNQAFFAIIAgACAAAAAA==.Covidnynteen:BAAANQADCgUICAAAAA==.Cowtastrophe:BAAANQABCgcIEAAAAA==.',
Cr='Craiso:BAAANQAECgYIEgAAAA==.Crankinhawg:BAAANQAECgcIEwAAAA==.Crazbezzul:BAAANQADCgUIBwAAAA==.Creationz:BAAANQADCgYICQABNQAECgEJAQACAAAAAA==.Crisarrow:BAAANQADCggIGAAAAA==.',
Cu='Current:BAABNQAECoEWAAIMAAcKEAV1TgAnAQAMAAcKEAV1TgAnAQAAAA==.',
Cy='Cynesh:BAACNQAFFIEXAAMTAAYKPyFHAgAwAgATAAYKOyFHAgAwAgAUAAQKdxYEDwAgAQA1AAQKgSAAAxMACQrMJfANAF8DABMACQrDJfANAF8DABQABwpRIQYkAA0CAAAA.Cytl:BAAANQAECgYICwAAAA==.',
Da='Dailybuilt:BAAANQADCgQICgAAAA==.Dangybangy:BAAANQAECgYIEgAAAA==.Danjaianka:BAAANQADCggJHgAAAA==.Darkken:BAAANQADCgYJBgABNQADCgcIEwACAAAAAA==.Darkkragmur:BAAANQAECgUICAAAAA==.Darknest:BAAANQADCgQIBgAAAA==.Darthimus:BAAANQAECgIIAwAAAA==.Datbishkarma:BAAANQAECgUIEQAAAA==.',
Dd='Dding:BAABNQAECoEpAAMFAAkKGSXaAQCwAwAFAAkKGSXaAQCwAwAGAAEKEwHGsQEEAAAAAA==.',
De='Deadbarcy:BAAANQAECgIJAgAAAA==.Deathklok:BAAANQAECggIEQAAAA==.Deathran:BAABNQAECoEfAAIHAAgKAhn4VAA1AgAHAAgKAhn4VAA1AgAAAA==.Deezgrips:BAABNQAECoEkAAIVAAgKNB2mHwCdAgAVAAgKNB2mHwCdAgAAAA==.Deffgwip:BAAANQAECgUICwAAAA==.Delfine:BAAANQADCggIHQAAAA==.Demonikiarly:BAAANQADCgUJBQABNQAECgYIDAACAAAAAA==.Desimus:BAAANQADCgcJCgAAAA==.Despott:BAABNQAECoEaAAIJAAcKPhLYwQDdAQAJAAcKPhLYwQDdAQAAAA==.Destina:BAAANQAECgcICgAAAA==.Dethfox:BAAANQAECgUIDgAAAA==.Dethlock:BAAANQADCgQIBAAAAA==.',
Di='Dioni:BAABNQAECoEjAAMWAAgKSCLJFwD7AgAWAAgKSCLJFwD7AgAXAAYKRgrEmgAyAQABNQAECgkJIQABAP8bAA==.Dirknasty:BAAANQAECgQJBwAAAA==.Diyfootjobs:BAAANQADCgYJGgAAAA==.',
Dk='Dkurther:BAAANQAECgUICQAAAA==.',
Do='Doggybag:BAAANQADCgQIBAAAAA==.Doublehelix:BAAANQAECgcICgAAAA==.Dovish:BAAANQAECgcIDAAAAA==.',
Dr='Drackygacky:BAAANQAECgEIAgAAAA==.Dracw:BAAANQADCgUICQAAAA==.Draglox:BAAANQADCggICgAAAA==.Drakaryss:BAAANQADCgEIAQABNQAECgkJLAAYAJ0hAA==.Drama:BAAANQAECgEIAQAAAA==.Drashar:BAAANQADCgUIBQAAAA==.Dravenm:BAAANQAECgUIEgAAAA==.Draz:BAAANQAECgMIBQAAAA==.Droozh:BAAANQADCgMIAwAAAA==.Drunkendrago:BAAANQADCgcIBwAAAA==.',
Du='Duesenjaeger:BAAANQADCgcICAAAAA==.Duko:BAAANQADCgEIAQAAAA==.',
['Dè']='Dèmonic:BAAANQAFFAEIAQAAAA==.',
['Dé']='Désy:BAAANQAECgMIAwAAAA==.',
['Dø']='Døric:BAAANQADCgcJDAAAAA==.',
['Dü']='Dürinn:BAAANQADCgIIAgAAAA==.',
Eh='Ehud:BAABNQAECoEiAAIGAAkK7h5ZIgAiAwAGAAkK7h5ZIgAiAwAAAA==.',
Ei='Eisiss:BAAANQABCgEIAQAAAA==.',
Ek='Ekô:BAAANQADCggIDgAAAA==.',
El='Elabrate:BAAANQADCgMIAwAAAA==.Elade:BAAANQADCgUIBQAAAA==.Elbori:BAABNQAECoEaAAIZAAkK9xSGAQByAgAZAAkK9xSGAQByAgAAAA==.Elbryan:BAAANQADCgMIAwAAAA==.Elementium:BAAANQAECgcIDgAAAA==.Elfmas:BAAANQAECgYICQAAAA==.Elorees:BAAANQADCgYIBgAAAA==.Elviswong:BAAANQADCgIIAgAAAA==.',
Em='Emerhy:BAAANQAECgEJAQAAAA==.',
Es='Escänor:BAAANQAECgcIEwAAAA==.Eshaia:BAAANQADCgEIAQAAAA==.',
Ex='Exlisum:BAAANQADCgQIBgAAAA==.',
Ey='Eyewyn:BAAANQABCgYIBQAAAA==.Eylos:BAAANQADCggIDAAAAA==.',
Fa='Faesmite:BAAANQADCgUIBQAAAA==.Faithflop:BAAANQAECgUICwAAAA==.Falleh:BAAANQADCgIIAgAAAA==.Fanorage:BAAANQAECgIIAgAAAA==.',
Fe='Felixox:BAAANQAECgEIAQAAAA==.Ferocias:BAAANQAECgQJBQAAAA==.',
Fi='Fiametta:BAAANQADCggICAAAAA==.Fishbreath:BAAANQAECgEIAQAAAA==.',
Fl='Flaffergan:BAAANQAECgUIDgAAAA==.Flastage:BAAANQAECgEIAQAAAA==.Flexhack:BAAANQAECgYIDwAAAA==.Flåsh:BAABNQAECoEZAAMaAAgK8SAULQCXAgAaAAcK+SAULQCXAgAGAAcKUxh5eQAJAgAAAA==.',
Fo='Focinnet:BAABNQAECoEfAAITAAcKcguuowCMAQATAAcKcguuowCMAQAAAA==.Forandra:BAAANQAECgIIAgAAAA==.Fortyacres:BAAANQADCgEIAQAAAA==.Fortybmh:BAAANQADCgEIAQABNQADCgEIAQACAAAAAA==.Four:BAAANQADCgYJDgAAAA==.Fourform:BAAANQADCgIIAgAAAA==.',
Fr='Frieren:BAAANQAECgUIBgAAAA==.',
Fu='Fuzzbutt:BAAANQADCgEIAQAAAA==.',
Ga='Gaalit:BAAANQADCgcIBwAAAA==.Galaxybone:BAAANQADCgQIBAAAAA==.Galithiri:BAAANQAECgQIAQAAAA==.Ganthani:BAABNQAECoEaAAIDAAcK9g7vdACEAQADAAcK9g7vdACEAQAAAA==.Garzett:BAABNQAECoEmAAIKAAgKsBkGKQBsAgAKAAgKsBkGKQBsAgAAAA==.Gatortooth:BAAANQABCgIIBAAAAA==.Gaybeowners:BAAANQAECgEJAQAAAA==.',
Ge='Geigh:BAAANQADCgUIBQAAAA==.Gethellar:BAAANQAECgcIDQAAAA==.',
Gh='Ghostdaliar:BAAANQADCgQIBgAAAA==.Ghouliana:BAAANQADCgUIBQABNQAECgIIAgACAAAAAA==.',
Gl='Glizyglober:BAAANQADCgMIAwABNQAFFAIIBgAKAGIEAA==.Glizzyrizily:BAAANQADCgMIAwABNQAFFAIIBgAKAGIEAA==.Glizzyys:BAAANQAFFAEIAQABNQAFFAIIBgAKAGIEAA==.Gllizzard:BAAANQADCgMJAwAAAA==.Gluckglucks:BAAANQABCgQIBAAAAA==.',
Go='Gore:BAAANQAECgUIBgAAAA==.Gorrock:BAAANQAECgQIBAAAAA==.',
Gr='Gravtech:BAAANQADCggJDgABNQAECgYICQACAAAAAA==.Grenzo:BAAANQAECgEIAgAAAA==.Grhm:BAAANQAECgcIBwAAAA==.Grim:BAABNQAECoEgAAMbAAkKbSJHFgDxAgAbAAkKZyJHFgDxAgAcAAMKciHlUgAXAQABNQAECgkJHAAdACAjAA==.Grimheart:BAAANQAECgEIAQAAAA==.Grundles:BAAANQADCggICAAAAA==.Grymnir:BAAANQAECgUIDAAAAA==.',
Gu='Guilliman:BAAANQAECgEIAQAAAA==.Gumsy:BAAANQAECgcIEgABNQAECggIGwAbAOccAA==.',
Gw='Gwory:BAAANQAECgIIAgAAAA==.',
['Gø']='Gørë:BAAANQAECgcICgAAAA==.',
Ha='Haddassah:BAAANQADCgIIAgAAAA==.Haramzadi:BAAANQADCgQICQAAAA==.Haranue:BAAANQAECgQIEQAAAA==.Harryporter:BAAANQAECgEIAQAAAA==.Harukà:BAAANQAECgUIDAAAAA==.',
He='Healscat:BAAANQADCgUJBQAAAA==.Healsdog:BAAANQAECgEIAQAAAA==.Hecâte:BAAANQABCggICgAAAA==.Hefferd:BAAANQADCgQIBAAAAA==.Helfon:BAABNQAECoEkAAIMAAgKYiFrEAAFAwAMAAgKYiFrEAAFAwAAAA==.Helgadknight:BAAANQABCgMIAwAAAA==.Helganelf:BAAANQAECgEIAQAAAA==.Helices:BAABNQAECoEXAAIVAAcKZBseMwAiAgAVAAcKZBseMwAiAgAAAA==.Herm:BAAANQAECgEIAQAAAA==.',
Hi='Highlordt:BAABNQAECoEgAAQeAAgK9hc0HgAoAgAeAAgK9hc0HgAoAgADAAYK6BWJcgCMAQAfAAEKrwc9KgApAAAAAA==.Highlordtron:BAAANQAECggIEAAAAA==.Hinoxfine:BAAANQADCgMIBAAAAA==.',
Ho='Holybeast:BAAANQADCgIIAgAAAA==.Holycharge:BAAANQAECgIIAgAAAA==.Holycrab:BAAANQAECgEIAQAAAA==.Holydudy:BAAANQAECgEIAQAAAA==.Holyely:BAAANQAECgUIBwAAAA==.Holyfae:BAABNQAECoEkAAIaAAkK8xOWNAB2AgAaAAkK8xOWNAB2AgAAAA==.Holygrom:BAABNQAECoEpAAIGAAkKbCWhBADOAwAGAAkKbCWhBADOAwAAAA==.Holylove:BAAANQADCgUIBgABNQAECgIJAgACAAAAAA==.Holynutzz:BAAANQAECgMIAwAAAA==.Holyrager:BAAANQAECgQIBAAAAA==.Holysplash:BAABNQAECoEWAAIDAAcKiBRWYADOAQADAAcKiBRWYADOAQAAAA==.Holyvoids:BAAANQADCgIIAgAAAA==.Hondodk:BAECNQAFFIERAAIbAAYKiCOYAABvAgAbAAYKiCOYAABvAgA1AAQKgS8AAxsACQrNJpgCAMUDABsACQrEJpgCAMUDABUAAQrDJgihAHAAAAE1AAUUBwgRABsAXSMA.Honeyshamwow:BAAANQADCgQIBAAAAA==.Hoodadin:BAAANQABCgMIAwAAAA==.Hoodlummon:BAAANQADCggJHQAAAA==.Hopesfall:BAAANQAECgIJAwAAAA==.Howzitcuz:BAAANQADCgcIGAABNQAECgYIEwACAAAAAA==.Hozari:BAABNQAECoEqAAIKAAkKSRjvHwCvAgAKAAkKSRjvHwCvAgAAAA==.',
Ht='Ht:BAAANQADCgcICAAAAA==.',
['Hã']='Hãvøc:BAAANQADCgIIAgAAAA==.',
Ia='Ianil:BAAANQAECgIJAwAAAA==.',
Ic='Iccyhot:BAAANQADCgMIAwABNQAFFAIIBgAKAGIEAA==.',
Ii='Iiwhiskey:BAAANQADCgcIBwAAAA==.',
Il='Ilirranna:BAAANQAECgIIBAAAAA==.',
In='Infi:BAACNQAFFIEcAAMUAAcK9yH8AQB1AgAUAAcKIB38AQB1AgATAAEKLyW4JQBpAAA1AAQKgToAAxQACQp3JtYAAOkDABQACQp3JtYAAOkDABMAAQrZJhgbAXIAAAAA.Initabath:BAAANQAECggIEAAAAA==.Initapoop:BAAANQAECgMIBwAAAA==.Inosukè:BAABNQAECoEsAAIYAAkKnSE+AwBtAwAYAAkKnSE+AwBtAwAAAA==.Invisibro:BAAANQAECgYICQAAAA==.',
Io='Ioannis:BAAANQAECgQICQAAAA==.',
Is='Isos:BAABNQAECoEqAAMDAAgKLSEpIgDJAgADAAgKLSEpIgDJAgAfAAEKCBBDIwA6AAAAAA==.Isus:BAAANQADCgYJBgABNQAECggIKgADAC0hAA==.',
Iy='Iykyk:BAAANQADCgQIDAABNQAECgYIEwACAAAAAA==.',
Ja='Jadeadly:BAAANQAECgcICAAAAA==.Jaded:BAABNQAECoEnAAIQAAkK0hSUGwAyAgAQAAkK0hSUGwAyAgAAAA==.Jakerbonk:BAAANQADCgYIBwAAAA==.Jakersai:BAAANQAECgYIEAAAAA==.Jakersaint:BAAANQADCgUIBQAAAA==.Javyr:BAAANQAECgUICAAAAA==.Jayfmtv:BAAANQAECgIIAgAAAA==.',
Je='Jessicax:BAAANQAECgQIBAAAAA==.Jetpackcat:BAAANQADCgIIAgAAAA==.',
Ji='Jio:BAAANQADCgcIBwAAAA==.',
Jl='Jlnxy:BAAANQAECggIEwAAAA==.',
Jo='Joania:BAAANQADCggICAAAAA==.Jonoa:BAAANQADCgUIBQAAAA==.',
Ju='Judo:BAAANQADCgUICwAAAA==.',
Ka='Kadre:BAAANQAECgUIDgAAAA==.Kadzilak:BAAANQADCgQIBgAAAA==.Kagemika:BAAANQAECgQIBAABNQAECgkJHQAMAHAJAA==.Kaiola:BAAANQAECgEIAQAAAA==.Kaizumie:BAAANQAECgIIAgAAAA==.Kalirti:BAAANQADCgIIAgAAAA==.Kamistri:BAABNQAECoEcAAQDAAkKcRkLGwDvAgADAAkKcRkLGwDvAgAeAAMKPAjTVgB+AAAfAAIKrAZSHwBTAAAAAA==.Kanaa:BAAANQAECgIIAgAAAA==.Kanatre:BAAANQADCgEIAQAAAA==.Kandicee:BAAANQADCgMIAwAAAA==.Karessandra:BAAANQADCgQIBAABNQAECgQIAQACAAAAAA==.Karrison:BAAANQADCgEIAQAAAA==.Kathea:BAAANQADCgIIAgAAAA==.Kayarra:BAAANQADCgEIAQABNQADCgQIBAACAAAAAA==.Kaynarra:BAAANQADCgQIBAAAAA==.Kayonna:BAAANQABCgEIAQABNQADCgQIBAACAAAAAA==.',
Ke='Keastral:BAAANQAECgQIBAAAAA==.Keeynai:BAAANQADCgQIBAAAAA==.Keldanis:BAABNQAECoEgAAITAAcK1xk1XwAvAgATAAcK1xk1XwAvAgAAAA==.Kelestrah:BAAANQADCgQJBAAAAA==.Kelterrager:BAAANQADCgMIAwAAAA==.Keony:BAAANQAECgYIEwAAAA==.Kerthur:BAAANQADCgYICAAAAA==.',
Ki='Kickpigeons:BAAANQADCgEIAQAAAA==.Killertcells:BAAANQABCgIIAgAAAA==.Kirgrand:BAAANQADCgMIAwAAAA==.Kittyarly:BAAANQAECgYIDAAAAA==.',
Ko='Kodeck:BAAANQADCggIGQAAAA==.Kodokan:BAAANQAECgEIAQAAAA==.Koshima:BAABNQAECoEkAAIXAAgKWhfSRAA3AgAXAAgKWhfSRAA3AgAAAA==.Kozan:BAAANQADCgUICAAAAA==.',
Kr='Krimdan:BAAANQADCgQIBAAAAA==.Krimhit:BAAANQADCgUICwAAAA==.Krimrok:BAAANQABCgIIAgAAAA==.Krimwarr:BAAANQADCgQIBAAAAA==.',
Ku='Kudranne:BAAANQADCgQICAABNQAECgQIAQACAAAAAA==.Kugia:BAABNQAECoEhAAIBAAkK/xulDQDZAgABAAkK/xulDQDZAgAAAA==.',
Ky='Kylex:BAAANQAECgEIAQAAAA==.Kynndell:BAAANQADCggIGQAAAA==.Kyo:BAAANQADCgYIDgAAAA==.',
['Kø']='Køkushibø:BAAANQABCgUIBQAAAA==.',
La='Laments:BAAANQADCgUIBQAAAA==.Latak:BAAANQADCgMIAwAAAA==.Latir:BAAANQADCgUIBwAAAA==.Lazyryx:BAAANQADCgUIBQAAAA==.',
Le='Leetheal:BAACNQAFFIEKAAMDAAQK6gQ7HADPAAADAAMKowU7HADPAAAeAAMKvwSdDQDDAAA1AAQKgScAAwMACQrtFntQAAgCAAMACQrtFntQAAgCAB4ABwr/GhIlAN8BAAAA.Leethul:BAABNQAECoEdAAIHAAgKzREBXwAYAgAHAAgKzREBXwAYAgAAAA==.Lelethxx:BAAANQAECgIIBAAAAA==.Lesanna:BAABNQAECoEnAAIMAAgKeQnmPACcAQAMAAgKeQnmPACcAQAAAA==.Lestharia:BAAANQAECgQIBAAAAA==.Leysmith:BAABNQAECoEnAAIGAAgKYRJViwDcAQAGAAgKYRJViwDcAQAAAA==.',
Li='Lifestream:BAAANQAECgIIAgAAAA==.Lilheal:BAAANQAECgIJAgAAAA==.Lilium:BAAANQADCgYICwAAAA==.Lionël:BAAANQAECgUIBQAAAA==.Lisax:BAAANQADCgIIAgAAAA==.Lizbethe:BAABNQAECoEZAAMRAAgKWSBcBwCEAgARAAcKKCBcBwCEAgAHAAYKRxcRhQCsAQAAAA==.',
Lo='Lockmclovin:BAAANQADCgMIAwAAAA==.Loltank:BAAANQAECgQIBAAAAA==.Lomrgreenol:BAAANQADCgQIBAAAAA==.Lopi:BAAANQAECgMIAwAAAA==.Lorast:BAAANQAECgEIAQAAAA==.Lorwater:BAAANQADCgQIBAAAAA==.Loveinfinity:BAAANQABCgIIAgAAAA==.',
Lp='Lp:BAAANQADCgYICAAAAA==.',
Lu='Lumibell:BAAANQABCgYIBwAAAA==.Luminate:BAAANQADCgQIBAAAAA==.Lunaryon:BAAANQADCgUICgAAAA==.',
Ma='Madamgypsy:BAAANQAECgIIBAAAAA==.Madderco:BAAANQAECggICAAAAA==.Madivh:BAAANQADCgQIBAAAAA==.Magaspy:BAAANQAECgUICQAAAA==.Magerage:BAAANQAECgEIAQAAAA==.Magiccairne:BAAANQAECgMIBAAAAA==.Magikiarly:BAAANQAECgQIBAABNQAECgYIDAACAAAAAA==.Magnar:BAAANQAECgIIAgABNQAECgMIBwACAAAAAA==.Mahoogany:BAAANQADCgYIDAAAAA==.Malson:BAAANQADCgYIBgAAAA==.Mamimage:BAACNQAFFIEJAAIJAAMKGxQEKwDxAAAJAAMKGxQEKwDxAAA1AAQKgTUAAgkACQosImYTAH8DAAkACQosImYTAH8DAAAA.Marukka:BAAANQADCgQIBAABNQADCgcIBwACAAAAAA==.Matty:BAAANQADCgEIAQAAAA==.Mayiana:BAAANQAECgEIAQAAAA==.',
Me='Meadowlark:BAAANQAECgIIAgAAAA==.Mefistofeles:BAAANQAECgQICwAAAA==.Mellie:BAAANQADCgQIBQAAAA==.Meowstic:BAABNQAECoEeAAIgAAgKlSEwBgADAwAgAAgKlSEwBgADAwABNQAECgIIAgACAAAAAA==.Mercurious:BAAANQAECgMIBgAAAA==.Metalrules:BAAANQABCggICAAAAA==.Methypheni:BAAANQAECgYICgAAAA==.',
Mi='Mill:BAAANQADCgYICgAAAA==.Minimuff:BAAANQADCgUIBQAAAA==.Mirajanna:BAABNQAECoEmAAIhAAgKEBaDCgACAgAhAAgKEBaDCgACAgAAAA==.Missmouthoff:BAABNQAECoEgAAIDAAcKIReXWgDiAQADAAcKIReXWgDiAQAAAA==.Mitenâ:BAAANQADCgUIBgAAAA==.Mizzxgummy:BAAANQAECgcIBwAAAA==.',
Mo='Momster:BAAANQADCgYIBgAAAA==.Monkin:BAAANQAECgEIAQAAAA==.Moogan:BAAANQAECgIIAgAAAA==.Mookins:BAAANQAECgYIEgAAAA==.Moonfishing:BAABNQAECoEgAAIJAAkKSBQodAB/AgAJAAkKSBQodAB/AgAAAA==.Moonfly:BAACNQAFFIEKAAIKAAUKhxINDAB8AQAKAAUKhxINDAB8AQA1AAQKgSMAAgoACQpDIlQMAFoDAAoACQpDIlQMAFoDAAAA.Morax:BAAANQAECgQIBwAAAA==.Morbidlord:BAAANQABCgYIDwAAAA==.Mourne:BAABNQAECoEfAAMNAAkKZxjGFwCXAgANAAkKZxjGFwCXAgAOAAIKOhUJPwCSAAAAAA==.',
Ms='Mssmalvile:BAAANQADCgYJCwAAAA==.',
My='Myrrvain:BAAANQAECgEIAQAAAA==.Mythara:BAAANQADCgYIBgAAAA==.',
Na='Naarcissus:BAAANQABCgIIAgAAAA==.Nagrim:BAAANQADCgYICQABNQAECggIGwAbAOccAA==.Nalaana:BAAANQAECgUICAAAAA==.Nalariel:BAABNQAECoEdAAIbAAkKMB7BIwCUAgAbAAkKMB7BIwCUAgAAAA==.Nallaana:BAAANQADCgUIBQAAAA==.Nalmagedan:BAAANQAECgUIDAAAAA==.Nammi:BAAANQADCgMIAwAAAA==.Nandorr:BAAANQADCgEIAQAAAA==.Nardalem:BAAANQADCgcIBwAAAA==.Narec:BAAANQADCgUIBQAAAA==.Narfhound:BAAANQADCgYICAAAAA==.Nazgrok:BAAANQAECgMIBwAAAA==.',
Ne='Nearhammer:BAAANQAECgEIAQAAAA==.Nefariouz:BAAANQAECggIAQAAAA==.Nervouz:BAABNQAECoEYAAIMAAkKIxF5KQAqAgAMAAkKIxF5KQAqAgAAAA==.Netherpally:BAAANQADCgQJBAAAAA==.',
Ni='Nikis:BAAANQADCgcIDwAAAA==.',
No='Nobbs:BAAANQAECgQIBQAAAA==.Noonecaress:BAAANQAECgIIAgAAAA==.',
Nu='Nualaperafin:BAABNQAECoEqAAIiAAkKJB+6BAA9AwAiAAkKJB+6BAA9AwAAAA==.',
Ny='Nyvara:BAAANQADCgQIBAABNQAECgMIBgACAAAAAA==.Nyxkitsune:BAAANQADCggIDQAAAA==.',
Oi='Oiyo:BAAANQABCggICQAAAA==.',
Ok='Okonomiyaki:BAAANQADCgcIBwAAAA==.',
Ol='Olayro:BAABNQAECoEhAAMEAAgK8Q6qBwD6AQAEAAgK8Q6qBwD6AQAHAAcKmQZWswA5AQAAAA==.',
Om='Omie:BAAANQADCgcIFwAAAA==.',
On='Onkiea:BAAANQABCgYJBAAAAA==.Onlyrage:BAAANQAECgUJCQAAAA==.',
Oo='Oomkin:BAAANQADCgQIBAAAAA==.Ooptomss:BAABNQAECoEcAAITAAcKzBR+dQD3AQATAAcKzBR+dQD3AQAAAA==.',
Op='Openingshift:BAAANQAECgEIAQAAAA==.Ophelìa:BAAANQADCgcIBwAAAA==.Ophilitheda:BAAANQADCgYIAwAAAA==.',
Or='Orclee:BAAANQAECgYIEQAAAA==.',
Pa='Pacificadora:BAAANQAECgQIBgAAAA==.Palaguy:BAAANQADCgQIBAAAAA==.Palkavanka:BAAANQAECgQIDAAAAA==.Pandamonk:BAAANQAECgEIAQAAAA==.',
Pe='Peeonfists:BAAANQADCgEIAQAAAA==.Persephie:BAAANQAECgQIBwABNQAECggIGwAbAOccAA==.Perzeval:BAAANQADCgMJAwAAAA==.',
Ph='Pharmacology:BAAANQAECgQIDwAAAA==.Phyberlamer:BAAANQADCgEIAQAAAA==.Phénicie:BAAANQADCgYIEgAAAA==.',
Pi='Pinkberri:BAAANQAECgEIAQAAAA==.Pinkblossom:BAAANQAECgEIAQAAAA==.Pipha:BAAANQABCgQIBQAAAA==.Pitchblack:BAAANQADCggIDQAAAA==.',
Po='Popa:BAABNQAECoEwAAQaAAkKsBmYJgC3AgAaAAkKsBmYJgC3AgAGAAUKDhkcywBMAQAFAAQKvhNGOQD3AAAAAA==.',
Pr='Prathe:BAAANQAECgUICQAAAA==.Prayinfury:BAAANQAECgYIBwAAAA==.Premorry:BAAANQAECgIIAgAAAA==.Premory:BAAANQADCgUICQAAAA==.Presagee:BAAANQADCgEIAQAAAA==.',
Ps='Psilocy:BAAANQAECgcIDwAAAA==.',
Pu='Pulsate:BAABNQAECoEYAAIjAAgK6BvtCgCjAgAjAAgK6BvtCgCjAgAAAA==.Purpleduster:BAAANQADCgEIAQAAAA==.',
Py='Pyllo:BAAANQAECggICgAAAA==.',
Qa='Qaucker:BAAANQAECgYIBgAAAA==.',
Qi='Qiz:BAAANQAECgUIEQAAAA==.Qizknows:BAAANQADCgEIAQAAAA==.',
Qu='Quadhelix:BAAANQAECgYIEgAAAA==.Quartermain:BAAANQAECggIBwAAAA==.',
Qw='Qwish:BAAANQADCgYIBgAAAA==.',
Ra='Rad:BAAANQAECgcICgAAAA==.Radlock:BAAANQAECgMIAQABNQAECgcICgACAAAAAA==.Ragémachine:BAAANQADCgcICwAAAA==.Raijin:BAAANQADCgcIBwABNQAECgMIBwACAAAAAA==.Raiken:BAAANQAECgIIAwAAAA==.Raistlen:BAAANQAECgEIAQAAAA==.Rakin:BAAANQABCgQIBAAAAA==.Rakmin:BAAANQAECgEIAQAAAA==.Rarib:BAAANQADCgcIBwAAAA==.Raspberry:BAAANQADCggICgABNQAECgEIAQACAAAAAA==.Rasto:BAAANQAECgQJBwAAAA==.Raszto:BAAANQADCgIIAgABNQAECgQJBwACAAAAAA==.Rattlebat:BAAANQAECgIIAgAAAA==.',
Re='Redmark:BAAANQAECgQIBAAAAA==.Rendezook:BAAANQAECgQIBgAAAA==.Respec:BAAANQADCggICAAAAA==.',
Ri='Rincewind:BAAANQADCggIFQAAAA==.Riohne:BAAANQADCgMIAwAAAA==.Rivexis:BAAANQADCgMIBAAAAA==.',
Ro='Roci:BAAANQADCggIFgAAAA==.Rocker:BAAANQAECggICAAAAA==.Rootway:BAAANQAECgQIBAAAAA==.Roxus:BAABNQAECoEfAAILAAcKayPbOgDDAgALAAcKayPbOgDDAgABNQAECggIDgACAAAAAA==.Roxusdruid:BAAANQAECggIDgAAAA==.',
Ru='Ruthlin:BAAANQADCgYIBgAAAA==.',
Sa='Sabellal:BAAANQADCgYIBgAAAA==.Saegusa:BAAANQAECgQICgAAAA==.Saepius:BAAANQAECgIIAgAAAA==.Salestia:BAABNQAECoEZAAIJAAgKFA0rwgDcAQAJAAgKFA0rwgDcAQAAAA==.Samellir:BAAANQAECgIIAwAAAA==.Sanlanesh:BAAANQADCgUIBQAAAA==.Sardothien:BAAANQADCgEIAQAAAA==.Sasive:BAAANQAECgYICQAAAA==.Satanicpanic:BAAANQAECgQIBQAAAA==.Sazoku:BAABNQAECoEaAAILAAkK9Bw8MgDiAgALAAkK9Bw8MgDiAgAAAA==.',
Sc='Scarletnight:BAAANQAECgUIBQABNQAECgYIEgACAAAAAA==.Schmall:BAAANQAECgUIDAAAAA==.Scrodumpulse:BAAANQADCgcIEAAAAA==.',
Se='Selvalin:BAAANQADCggIDgAAAA==.Sendit:BAAANQAECgcICQAAAA==.Seniormage:BAAANQAECgUICAAAAA==.Serveil:BAAANQADCgIIAgABNQAECgkJIgAkAJoPAA==.',
Sh='Shadesprint:BAAANQAECggIBwAAAA==.Shadowhor:BAAANQAECgYIDwABNQAECggIJwAHALodAA==.Shamamoomoo:BAABNQAECoEYAAIOAAgK3gJkKgBWAQAOAAgK3gJkKgBWAQAAAA==.Shaninigans:BAAANQADCgEIAQAAAA==.Shaowen:BAAANQADCgYIBgABNQAECgMIBwACAAAAAA==.Shaqeesha:BAAANQADCgUIBQAAAA==.Shenea:BAAANQADCgYICQAAAA==.Shestalker:BAABNQAECoE2AAITAAkKJxeOPQCNAgATAAkKJxeOPQCNAgAAAA==.Shiau:BAABNQAECoEVAAIQAAgKWQX/NAA2AQAQAAgKWQX/NAA2AQAAAA==.Shimura:BAAANQADCgEIAQAAAA==.Shinky:BAAANQADCgUIBAAAAA==.Shý:BAAANQAECgQICwAAAA==.',
Si='Silana:BAAANQADCggIDQAAAA==.Silvaine:BAAANQAECgUICQAAAA==.Silverstorm:BAABNQAECoEYAAILAAgKxBFihwDkAQALAAgKxBFihwDkAQAAAA==.Sisterfran:BAAANQAECgEIAQAAAA==.Sixii:BAAANQAECgMIAwAAAA==.',
Sk='Skitzz:BAAANQAECgQICAAAAQ==.',
Sl='Slackr:BAAANQADCgUIBQAAAA==.Slackrm:BAAANQADCgMJBwAAAA==.Slackrp:BAAANQADCgIJAgAAAA==.Slashyr:BAAANQAECgQIDAAAAA==.Slimshadydh:BAAANQAECgQICAAAAA==.',
Sn='Snipez:BAAANQAECgIJAwAAAA==.Snortyhotorc:BAAANQAECgcICwAAAA==.Snortymcgoop:BAABNQAECoEXAAIUAAgKqRTYJQD8AQAUAAgKqRTYJQD8AQAAAA==.',
So='Solclipeus:BAABNQAECoEuAAIFAAkKTCAfBwAaAwAFAAkKTCAfBwAaAwAAAA==.Soldh:BAAANQAECgUJCgABNQAECgkJLgAFAEwgAA==.Sollock:BAAANQAECggIEAABNQAECgkJLgAFAEwgAA==.Solna:BAAANQADCgYIBgAAAA==.Soulrecall:BAAANQAECgIIAwAAAA==.Soupz:BAAANQAECgUIEAAAAA==.',
Sp='Sparadin:BAAANQAECgUICgAAAA==.Spartacûs:BAAANQAECgQJBQABNQAECgcICQACAAAAAA==.Spikore:BAAANQADCggICgAAAA==.Splitpeaz:BAAANQADCgcJBwAAAA==.',
Sq='Squrìtle:BAAANQAECgQIBAAAAA==.',
Sr='Sririacha:BAAANQADCgUIBQABNQAECggIBwACAAAAAA==.',
St='Stabbyjohn:BAAANQADCggICAAAAA==.Stabbypickle:BAAANQAECgYIDQABNQAECgcIFwAaAFwmAA==.Stachelbeere:BAAANQADCgYIBgAAAA==.Stickybug:BAAANQAECgMIAwAAAA==.Strånge:BAAANQAECgYIBwAAAA==.Stìtch:BAACNQAFFIEPAAIHAAUK8xttCQCmAQAHAAUK8xttCQCmAQA1AAQKgSwAAgcACQpoJeEEAKEDAAcACQpoJeEEAKEDAAAA.Stítch:BAAANQADCgQIBAABNQAFFAUIDwAHAPMbAA==.',
Su='Sukiafaunias:BAAANQAECgEIAgAAAA==.Sukiafloras:BAAANQAECgIIAgAAAA==.Suldån:BAAANQADCggIJwAAAA==.Summondaddy:BAAANQADCgQIBQAAAA==.Sunfurious:BAAANQAECgUICwAAAA==.Suoop:BAAANQAECgUIBQAAAA==.',
Sw='Swiftshaman:BAAANQAECgEIAQAAAA==.',
Sy='Synvaria:BAAANQAECgEIAQAAAA==.Syraice:BAAANQADCgUIBQABNQAECgkJLAAkAHwYAA==.Syrare:BAAANQADCgcIDwAAAA==.Syvenari:BAAANQAECgMICAAAAA==.',
['Sï']='Sïxx:BAAANQADCgMJAwABNQAECgMIAwACAAAAAA==.',
Ta='Tachisan:BAAANQAECgQICAAAAA==.Taeril:BAAANQADCgQIBAAAAA==.Tamfam:BAAANQADCggJEAAAAA==.Tanburn:BAAANQADCgYICwAAAA==.Tanduinex:BAAANQADCgYIDAAAAA==.Tangal:BAAANQADCggIEQAAAA==.Tankstabber:BAAANQADCgQIBQAAAA==.Tanplate:BAAANQADCgYICAAAAA==.Tarentia:BAAANQABCggIDgAAAA==.Tastytyrande:BAAANQAECgUIBQAAAA==.Tatsumy:BAABNQAECoEZAAIGAAYKyQ4hywBMAQAGAAYKyQ4hywBMAQAAAA==.',
Tc='Tcmon:BAABNQAECoEkAAITAAgKgRmhSwBjAgATAAgKgRmhSwBjAgAAAA==.',
Te='Teachings:BAAANQADCgMIAwAAAA==.Teaglizzy:BAAANQADCgEIAQABNQAFFAIIBgAKAGIEAA==.Teehole:BAAANQAECgUICwAAAA==.Telihill:BAAANQADCgUIDgAAAA==.Telsarra:BAAANQAECgQIBgAAAA==.',
Th='Thalenia:BAAANQADCggIEwAAAA==.Thebigtuna:BAABNQAECoEqAAIlAAkK1yPiAgCqAwAlAAkK1yPiAgCqAwAAAA==.Thegigatuna:BAAANQADCgMIAwAAAA==.Thekrisaning:BAAANQADCgYIBgAAAA==.Theladydruid:BAABNQAECoElAAIBAAkKchOTGABSAgABAAkKchOTGABSAgAAAA==.Thelnaris:BAAANQADCgEIAQAAAA==.Themeats:BAAANQADCgQIBAAAAA==.Thendezoth:BAAANQAECgEIAgAAAA==.Thighsoffel:BAAANQADCgcIEwAAAA==.Thirdtjme:BAAANQADCgYIBgAAAA==.Thunderhóof:BAAANQABCgYIDQAAAA==.Thôr:BAAANQAECggICAAAAA==.',
Ti='Tigerpa:BAAANQAECgQICgAAAA==.Tinkernut:BAAANQABCgIIAgAAAA==.Tinypally:BAAANQAECgEIAgAAAA==.Tinyraven:BAABNQAECoEiAAIlAAgKPBWUHgA/AgAlAAgKPBWUHgA/AgAAAA==.Tinystotems:BAAANQAECgQICwAAAA==.Tinythia:BAAANQADCgUIBQAAAA==.Tioklarus:BAABNQAECoEsAAIjAAcKuwmgHABnAQAjAAcKuwmgHABnAQAAAA==.Tisaryn:BAAANQAECgQIBAAAAA==.',
To='Tofulady:BAABNQAECoEmAAIYAAkKMx/qBgAMAwAYAAkKMx/qBgAMAwAAAA==.Tohu:BAAANQAECgYIDgAAAA==.Toshen:BAAANQADCgEIAQAAAA==.Totax:BAAANQAECgEJAQAAAA==.Totemtoker:BAAANQADCggIDQAAAA==.',
Tr='Tremors:BAAANQADCggICAAAAA==.Triggër:BAAANQABCgQIBAABNQAECgEIAQACAAAAAA==.Tromb:BAAANQABCgIIBAAAAA==.',
Tw='Twobithusler:BAAANQAECgIIAgAAAA==.Twoone:BAAANQADCgQIBAAAAA==.',
Ty='Tyniarstus:BAAANQADCgYICAAAAA==.',
Ud='Udderfiasco:BAAANQABCgIIAgAAAA==.',
Ug='Uggh:BAAANQADCgUIBQAAAA==.',
Un='Unhowly:BAACNQAFFIEFAAIbAAIKNhsZEwCmAAAbAAIKNhsZEwCmAAA1AAQKgSQAAhsACQqGJQsJAGYDABsACQqGJQsJAGYDAAAA.Unpoppable:BAAANQAECgUICQAAAA==.',
Uz='Uzilok:BAAANQAECgYIBgAAAA==.',
Va='Vakir:BAABNQAECoEgAAIVAAgKNRPQPQDqAQAVAAgKNRPQPQDqAQAAAA==.Valmortem:BAEANQADCgcIEgAAAA==.Vapidos:BAAANQAECgMIBAAAAA==.Varynix:BAAANQAECgIIAgABNQAECgYIBwACAAAAAA==.Vatica:BAAANQAECgEIAQAAAA==.',
Ve='Velanoria:BAAANQADCggICwAAAA==.Veldorai:BAAANQADCgYICwAAAA==.Velrenya:BAAANQADCgQIBgAAAA==.Venvalzhar:BAABNQAECoEeAAMDAAcK5CLHJgCyAgADAAcK5CLHJgCyAgAeAAIKkQI0ZgBCAAAAAA==.Veralidaine:BAAANQAECgQIBgAAAA==.Vestammeni:BAABNQAECoEjAAMSAAkKKR+SBgDaAgASAAkKKR+SBgDaAgALAAUKUhDKxgA2AQAAAA==.Vexlore:BAAANQADCgYIBwAAAA==.',
Vi='Vixsaurion:BAAANQAECgEIAQAAAA==.',
Vo='Voltx:BAAANQAECgEIAQAAAA==.Vorn:BAAANQADCgcIBwAAAA==.Vow:BAABNQAECoEVAAIFAAYKOSAKHADiAQAFAAYKOSAKHADiAQAAAA==.',
Vy='Vynlenlor:BAAANQABCgIIAgAAAA==.',
Wc='Wckd:BAAANQAECgYIEgAAAA==.',
We='Weaksnow:BAAANQAECgcIDgABNQAFFAMICQAJABsUAA==.Weedgoku:BAAANQAECgQIBAAAAA==.Weedvegeta:BAAANQAECggIEwAAAA==.Wernbirn:BAAANQAECggIAQAAAA==.Wetremin:BAAANQAECgEIAQAAAA==.',
Wh='Whirpy:BAAANQAECgYIDwAAAA==.Whisberis:BAAANQADCgMIAwAAAA==.Whitty:BAAANQADCgQIBAAAAA==.Whizkee:BAAANQAECgcIEgAAAA==.Whookies:BAAANQADCgMIAwABNQAECgYIBgACAAAAAA==.',
Wi='Wildbeefwood:BAAANQAECgUIBQAAAA==.Wingedlady:BAAANQAECgQIBwAAAA==.Wingss:BAABNQAECoEcAAIGAAgKvyJMKgABAwAGAAgKvyJMKgABAwAAAA==.',
Wu='Wushu:BAAANQAECgQICgAAAA==.',
Wy='Wyl:BAAANQAECggIEwAAAA==.',
Xe='Xerath:BAAANQAECgUICwAAAA==.',
Xi='Xiing:BAABNQAECoEeAAMSAAgKLxGzEwC9AQASAAgKLxGzEwC9AQALAAEKTgQhPQErAAAAAA==.Xinei:BAAANQADCgQIAQAAAA==.Xinhe:BAAANQAECgIIAgAAAA==.',
Xn='Xneutron:BAAANQAECgUICQAAAA==.',
Xt='Xtravagent:BAAANQADCgIIAgAAAA==.',
Xy='Xyxia:BAAANQADCgcIBwAAAA==.',
Ya='Yaiie:BAABNQAECoEbAAMEAAcK0g4/DAB2AQAEAAYKcQ8/DAB2AQARAAYKlQpNJgA4AQAAAA==.',
Yo='Yonna:BAAANQAECgMIAwAAAA==.',
Yu='Yungholy:BAAANQAECgQIBwAAAA==.Yuuki:BAAANQADCgcIBwABNQAECgEIAQACAAAAAA==.Yuunggrazy:BAAANQADCgIIAgABNQAECgQIBwACAAAAAA==.',
['Yü']='Yüto:BAABNQAECoEfAAMTAAkKWR/AGQAZAwATAAkKWR/AGQAZAwAUAAMKrBY2TQDNAAAAAA==.',
Za='Zabuto:BAABNQAECoEYAAIKAAcKbxZKPADoAQAKAAcKbxZKPADoAQAAAA==.Zahäära:BAAANQAECgUIBQAAAA==.Zaldiz:BAAANQADCgIIAgAAAA==.Zar:BAAANQAECgQIBAAAAA==.Zarrtan:BAAANQADCgcIFgAAAA==.Zazevo:BAAANQAECgUICAAAAA==.Zazprie:BAAANQAECgMICgAAAA==.',
Ze='Zendrozath:BAAANQADCgQIBQABNQAECgQIBgACAAAAAA==.',
Zo='Zooz:BAAANQADCgIIAgAAAA==.',
Zu='Zual:BAAANQAECgIIAgAAAA==.Zularraka:BAAANQAECgMIBQAAAA==.',
Zx='Zxeý:BAAANQADCgcIDgAAAA==.',
['Äb']='Äbracadabruh:BAAANQAECgYIEgABNQAECgcICgACAAAAAA==.',
['Äl']='Älissia:BAAANQADCgcIGQAAAA==.',
['Ål']='Ålexthegrëat:BAAANQAECgMIBAAAAA==.',
['Èm']='Èmandy:BAAANQADCggIDQAAAA==.',
['Ën']='Ëndo:BAABNQAECoEbAAMbAAgK5xxgIQCjAgAbAAgK5xxgIQCjAgAVAAQKXxAXhgDAAAAAAA==.',
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
