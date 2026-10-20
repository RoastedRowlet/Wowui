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

local lookup = {'Druid-Restoration','Unknown-Unknown','Paladin-Retribution','Priest-Holy','Warlock-Affliction','Paladin-Protection','Warlock-Demonology','DeathKnight-Unholy','Mage-Frost','Mage-Arcane','Druid-Balance','DeathKnight-Frost','Warrior-Fury','DemonHunter-Havoc','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Hunter-BeastMastery','Monk-Windwalker','Warlock-Destruction','Warrior-Protection','Monk-Brewmaster','Hunter-Marksmanship','Shaman-Restoration','Shaman-Enhancement','DeathKnight-Blood','Shaman-Elemental','Monk-Mistweaver','Mage-Fire','Paladin-Holy','Druid-Feral','Priest-Shadow','Priest-Discipline','Druid-Guardian','DemonHunter-Vengeance','Evoker-Devastation','Evoker-Preservation','DemonHunter-Devourer',}
local provider = {region='US',realm='Azshara',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aaryyee:BAAANQAECgEIAQAAAA==.',
Ac='Aceforlife:BAABNQAECn8qAAIBAAcKmw40DgBcAQABAAcKmw40DgBcAQAAAA==.',
Ad='Adriane:BAAANQADCgEIAQAAAA==.Adrox:BAAANQADCgMIBAAAAA==.',
Ae='Aelelelos:BAAANQADCgcICgAAAA==.Aequus:BAAANQADCgEIBgAAAA==.Aestinna:BAAANQAECgQIAwAAAA==.Aevenyhm:BAABNQAECn8rAAIBAAgKfhuqBwDEAQABAAgKfhuqBwDEAQAAAA==.',
Ag='Aghorn:BAAANQAECgIIAgAAAA==.',
Ai='Aidoneus:BAAANQAECgEIAQABNQAFFAEIAQACAAAAAA==.',
Ak='Akijin:BAAANQADCgEIAQABNQAECgkJGQADAPYTAA==.Akismite:BAABNQAECn8ZAAIDAAkK9hNnhwAYAgADAAkK9hNnhwAYAgAAAA==.',
Al='Alaru:BAABNQAECn8uAAIEAAoKPAyuEwDVAQAEAAoKPAyuEwDVAQAAAA==.Alemental:BAAANQADCgcIEgABNQAECgcIDwACAAAAAA==.Algana:BAAANQADCggIDQABNQAECgoKMQAFADIPAA==.Allhallows:BAAANQAECgYIDwAAAA==.Alorandis:BAAANQAECgIIAgAAAA==.Alqueria:BAABNQAECn8mAAMGAAoKOxbYGwAOAgAGAAkKpRbYGwAOAgADAAgKYg8ZtwCwAQABNQAFFAIIBQAHADYbAA==.Altarboizyum:BAAANQAECgIJAQABNQAECgoKPwAGAJsfAA==.',
An='Andanto:BAABNQAECn8UAAIIAAYK5g6jdwA7AQAIAAYK5g6jdwA7AQAAAA==.Angeliz:BAAANQAECggIDQAAAA==.Anitaloc:BAAANQAECgUICgAAAA==.Anneweaver:BAABNQAECn8pAAMJAAkK6h7FDwCsAQAKAAkKjBwSfACGAgAJAAgKGhvFDwCsAQABNQAFFAYIFwAKAO4VAA==.Anorantha:BAABNQAECn81AAILAAoKdQ2ICgCUAQALAAoKdQ2ICgCUAQAAAA==.',
Ap='Apicots:BAAANQADCggIDwAAAA==.Apipa:BAAANQAECgYIBwAAAA==.Apricot:BAAANQADCgUIBgAAAA==.Apzz:BAAANQADCgIIAgAAAA==.',
Ar='Arendir:BAAANQAECggIAQAAAA==.Arizticat:BAAANQADCgUICgAAAA==.Arradrayn:BAAANQADCgYIBgABNQAECgQIBgACAAAAAA==.Arrowin:BAAANQADCgQIBAAAAA==.Artica:BAAANQADCggICAAAAA==.Arzan:BAAANQAECgUIBwAAAA==.',
As='Ashalan:BAABNQAECn8VAAIMAAYKbwZGagD2AAAMAAYKbwZGagD2AAAAAA==.Ashenflail:BAABNQAECn8VAAIGAAgKZwr7EQD+AAAGAAgKZwr7EQD+AAAAAA==.Astesia:BAAANQAECggICwAAAA==.Astrraa:BAAANQADCggIFwAAAA==.Asulo:BAAANQAECgYIBgABNQAFFAMICgANAFAbAA==.',
At='Atrejha:BAACNQAFFH8IAAIOAAMKWgh5CQCBAAAOAAMKWgh5CQCBAAA1AAQKfyIAAg4ACgpYClM/AMEBAA4ACgpYClM/AMEBAAAA.',
Au='Aurethas:BAAANQAECgEIAgAAAA==.Aurä:BAABNQAECn8bAAIKAAkKFw5e1QDcAQAKAAkKFw5e1QDcAQABNQAECgoKGgAPAPYTAA==.Aussilio:BAAANQADCggICQAAAA==.',
Av='Avera:BAAANQAECgEIAQAAAA==.Avye:BAAANQADCgEIAQAAAA==.',
Aw='Awesome:BAAANQAECgQIBQAAAA==.',
Az='Azgkrimpatul:BAAANQADCgYIDAAAAA==.Azmodeus:BAAANQADCgUIBwAAAA==.Azrina:BAABNQAECn8XAAIQAAkKoQ1AHwDWAQAQAAkKoQ1AHwDWAQAAAA==.',
Ba='Bael:BAABNQAECn8XAAIOAAoKhgU9TwBdAQAOAAoKhgU9TwBdAQAAAA==.Baidden:BAAANQADCgMIBwAAAA==.Balddh:BAAANQAECgIIAgABNQAECgkJHgAKAPISAA==.Balddk:BAAANQAECgYIEQABNQAECgkJHgAKAPISAA==.Baldrogue:BAACNQAFFH8LAAIRAAQKmBy8AwDFAAARAAQKmBy8AwDFAAA1AAQKfyYABBEACgqAIKQJAEIDABEACgp6IKQJAEIDABAACApwDlscAPEBABIACArtAmcQABgBAAAA.Baldwarrior:BAABNQAECn8kAAIPAAoKGBUrVwCGAgAPAAoKGBUrVwCGAgAAAA==.Ballflapper:BAAANQADCgcICgABNQAECgoKHgATANQSAA==.Bandidos:BAAANQAECgQICAAAAA==.Banekin:BAAANQADCggICAAAAA==.',
Be='Beastmans:BAAANQADCgQIBQAAAA==.Becka:BAAANQAECgcICgAAAA==.Beckz:BAAANQADCggIDQAAAA==.Beefhambacon:BAAANQAECgUIDgAAAA==.Behealzabub:BAAANQAECgcIDgAAAA==.Beladora:BAAANQADCgEIAQAAAA==.Belmatride:BAAANQAECgIIBwAAAA==.Belpepper:BAABNQAECn8YAAIDAAkKxwo9uACtAQADAAkKxwo9uACtAQAAAA==.Bendelmonte:BAAANQADCggIJAABNQAECgYIFAAIAFIXAA==.',
Bi='Biggum:BAAANQADCgIIAgAAAA==.Bigmez:BAAANQAECgYIDQAAAA==.Bigmoocowii:BAAANQADCgIIAgAAAA==.Bigswangindi:BAAANQADCggIEAAAAA==.Bilipmonk:BAACNQAFFH8GAAIUAAMKfAWpBQCnAAAUAAMKfAWpBQCnAAA1AAQKfxwAAhQACgrkErAiABMCABQACgrkErAiABMCAAAA.Bindinglight:BAACNQAFFH8IAAMLAAIKYgSDIgB/AAALAAIKYgSDIgB/AAABAAEKdwVVGAA5AAA1AAQKf1AAAwEACgqQGDcZAHICAAEACgqQGDcZAHICAAsACQrFErA0AEMCAAAA.Birdofhermes:BAAANQADCgMIBAAAAA==.Bizzthewizz:BAAANQADCgQIBAAAAA==.Biñx:BAAANQADCgEIBAAAAA==.',
Bl='Blarr:BAAANQAECgcIDgAAAA==.Blindehunter:BAAANQADCgIIAgABNQADCgIIAgACAAAAAA==.Blindvoid:BAAANQAECgIIAgABNQADCgIIAgACAAAAAA==.Bloodguard:BAAANQADCgYIBwAAAA==.Blubinax:BAAANQADCgQIBAAAAA==.Bluedabodeba:BAAANQADCgEIAQAAAA==.Bluejeanz:BAAANQADCgYIBQABNQAECgkJIwALABIiAA==.',
Bo='Boonkay:BAAANQADCgEIAQAAAA==.Boonkie:BAAANQAECggICgAAAA==.Boonksdragon:BAAANQAECggICAAAAA==.Boonlock:BAAANQAECggIAQAAAA==.Boxbeater:BAAANQADCgYIBgAAAA==.',
Br='Braedravia:BAAANQAECgQIBAAAAA==.Bretikus:BAAANQAECgYIBgAAAA==.Brisanna:BAAANQAECgYIEwAAAA==.Bruleecreme:BAAANQAECgUIBgAAAA==.',
Bu='Bubos:BAAANQADCgIJAgAAAA==.Budgeroo:BAAANQAECgUIBAAAAA==.',
['Bà']='Bàwlz:BAAANQAECgYIEwAAAA==.',
['Bè']='Bèérsërk:BAAANQADCgEIAQAAAA==.',
['Bö']='Böðull:BAAANQAECgMIBgAAAA==.',
Ca='Cadarion:BAAANQABCgIIAgAAAA==.Caelix:BAAANQADCgQIBQAAAA==.Calci:BAAANQADCgEIAQAAAA==.Caledor:BAABNQAECn8jAAIDAAkK4w3KnADpAQADAAkK4w3KnADpAQAAAA==.Calkhan:BAAANQADCgMIAwAAAA==.Camitriel:BAABNQAECn+yAQQHAAkKxyYoAACLAwAHAAkKxyYoAACLAwAVAAUKBCWlGACnAQAFAAEK+x/NDABjAAAAAA==.Cataleya:BAAANQAECggIAgAAAA==.Cawa:BAAANQADCgYIBwAAAA==.',
Ce='Ceaserianoma:BAAANQADCgMIAwAAAA==.',
Ch='Chadder:BAAANQAECggIEAAAAA==.Charliie:BAABNQAECn8qAAMWAAoK5R+eBAA6AwAWAAoK5R+eBAA6AwAPAAEKxA2xSgE9AAAAAA==.Chaunakoala:BAAANQADCgIIAgAAAA==.Cherryfudge:BAAANQADCggIDQAAAA==.Chipinwing:BAAANQAECgEIAQAAAA==.Chudmage:BAAANQADCgEIAQAAAA==.Chunkysoupz:BAAANQADCgYIBgAAAA==.',
Cl='Classyshammy:BAAANQADCggIDAAAAA==.Clockworks:BAAANQADCgcIFAAAAA==.Clouxdyskies:BAAANQADCgEIAQAAAA==.',
Co='Cocinegr:BAABNQAECn8cAAIHAAgKIAxmrgB0AQAHAAgKIAxmrgB0AQABNQAFFAQIDQAKAOgWAA==.Cocinegrø:BAAANQAECggIEQABNQAFFAQIDQAKAOgWAA==.Cokuzo:BAAANQAECgQIBgAAAA==.Coneja:BAABNQAECn8vAAIKAAkKEAoP4ADIAQAKAAkKEAoP4ADIAQAAAA==.Coolbroguy:BAAANQADCgEIAQAAAA==.Coomspit:BAAANQAECgIIAgAAAA==.Coraline:BAAANQADCgEIAQAAAA==.Corwa:BAAANQAECgEIAQABNQAFFAMIBQADAF4QAA==.Covidnynteen:BAAANQADCgUICAAAAA==.Cowtastrophe:BAAANQADCgEIAQAAAA==.',
Cr='Craiso:BAABNQAECn8cAAIXAAgKeyG9CACdAgAXAAgKeyG9CACdAgAAAA==.Crankinhawg:BAABNQAECn8VAAIKAAgKTiAkgQB8AgAKAAgKTiAkgQB8AgAAAA==.Crazbezzul:BAAANQADCgUIBwAAAA==.Creationz:BAAANQADCgYICQABNQAECgEIAQACAAAAAA==.Crisarrow:BAAANQADCggIGQAAAA==.',
Cu='Current:BAABNQAECn8YAAIOAAgKoQXWUQBOAQAOAAgKoQXWUQBOAQAAAA==.',
Cy='Cynesh:BAACNQAFFH8ZAAMTAAcKUR/2AwAfAgATAAYKDyL2AwAfAgAYAAUKSRXCDAByAQA1AAQKfyMAAxMACgrFJXMVAEcDABMACgq7JXMVAEcDABgABwqvIJkpAP4BAAAA.Cytl:BAAANQAECgYICwAAAA==.',
Da='Dailybuilt:BAAANQADCgQICgAAAA==.Damitbobbi:BAAANQADCgUIBQAAAA==.Dangybangy:BAABNQAECn8ZAAITAAgKqBD9mADVAQATAAgKqBD9mADVAQAAAA==.Danjaianka:BAAANQADCggJIAAAAA==.Dankshotzs:BAAANQABCggICwAAAA==.Darkken:BAAANQADCgYJBgABNQADCgcIFAACAAAAAA==.Darkkragmur:BAAANQAECgUICAAAAA==.Darknest:BAAANQADCgQICAAAAA==.Darthimus:BAAANQAECgIIAwAAAA==.Datbishkarma:BAABNQAECn8bAAIKAAgK4AR3IwFQAQAKAAgK4AR3IwFQAQAAAA==.',
Dd='Dding:BAACNQAFFH8HAAIGAAMKwyCGAQAjAQAGAAMKwyCGAQAjAQA1AAQKfzAAAwYACgqfJXcGAEIDAAYACQqGJXcGAEIDAAMAAgqvEyO/AHIAAAAA.',
De='Deadbarcy:BAAANQAECgIJAgAAAA==.Deathklok:BAABNQAECn8hAAMZAAoKcBQVGQCRAQAZAAoKcBQVGQCRAQAaAAYKhASiIwAhAQAAAA==.Deathran:BAABNQAECn8nAAIHAAoKCBepWwBEAgAHAAoKCBepWwBEAgAAAA==.Deezgrips:BAABNQAECn8kAAIbAAgKvxq5JgCIAgAbAAgKvxq5JgCIAgAAAA==.Deffgwip:BAABNQAECn8ZAAIIAAcKuAxOFwAoAQAIAAcKuAxOFwAoAQAAAA==.Delfine:BAAANQADCggIHQAAAA==.Demonikiarly:BAAANQADCgUJBQABNQAECggIEAACAAAAAA==.Desimus:BAAANQADCgcICgAAAA==.Despott:BAABNQAECn8eAAIKAAkK8hLpUQAYAQAKAAkK8hLpUQAYAQAAAA==.Destina:BAAANQAECggIEQAAAA==.Dethfox:BAABNQAECn8UAAIIAAYKUheIaABvAQAIAAYKUheIaABvAQAAAA==.Dethlock:BAAANQADCgQIBAAAAA==.',
Di='Dioni:BAABNQAECn8pAAMZAAoKniFEHwDuAgAZAAoKniFEHwDuAgAcAAYKgArwsAAxAQABNQAECgoKKgABAOYdAA==.Dirknasty:BAAANQAECgQIBwAAAA==.Diyfootjobs:BAAANQADCgYJGgAAAA==.',
Dk='Dkurther:BAAANQAECgUIDwAAAA==.',
Do='Doggybag:BAAANQADCgQIBAAAAA==.Doomhauerr:BAAANQAECggICAAAAA==.Dottonohana:BAAANQAECgQIBAAAAA==.Doublehelix:BAAANQAECgcIDwAAAA==.Dovish:BAAANQAECgcIDAAAAA==.',
Dr='Drackygacky:BAAANQAECgIIAwAAAA==.Dracw:BAAANQAECgUIBwAAAA==.Draglox:BAAANQAECgQIBgAAAA==.Drakaryss:BAAANQADCgEIAQABNQAECgoKNAAdAAwjAA==.Drama:BAAANQAECgEIAQAAAA==.Drashar:BAAANQADCgUIBgAAAA==.Dravenm:BAABNQAECn8lAAIKAAgKbgwRUgAYAQAKAAgKbgwRUgAYAQAAAA==.Draz:BAAANQAECgMIBQAAAA==.Droozh:BAAANQADCgMIAwAAAA==.Drunkendrago:BAAANQADCggIDgAAAA==.',
Du='Duesenjaeger:BAAANQADCgcIDQAAAA==.Duko:BAAANQADCgEIAQAAAA==.',
['Dè']='Dèmonic:BAAANQAFFAEIAQAAAA==.',
['Dé']='Désy:BAAANQAECgMIAwAAAA==.',
['Dø']='Døric:BAAANQADCgcJDAAAAA==.',
['Dü']='Dürinn:BAAANQADCgIIAgAAAA==.',
Eh='Ehud:BAABNQAECn81AAIDAAoKByNdDACfAwADAAoKByNdDACfAwAAAA==.',
Ei='Eisiss:BAAANQADCgEIAQAAAA==.',
Ek='Ekô:BAAANQADCggIDgAAAA==.',
El='Elabrate:BAAANQADCgMIAwAAAA==.Elade:BAAANQADCgUIBQAAAA==.Elbori:BAABNQAECn8lAAIeAAoKVxWpAQCIAgAeAAoKVxWpAQCIAgAAAA==.Elbryan:BAAANQADCgMIAwAAAA==.Eldaral:BAAANQAECggIBAAAAA==.Elementium:BAAANQAECggIEQAAAA==.Elerethe:BAAANQADCgEIAQAAAA==.Elfmas:BAAANQAECgYICQAAAA==.Elorees:BAAANQADCgYIBgAAAA==.Elviswong:BAAANQADCgIIAgAAAA==.',
Em='Emerhy:BAAANQAECgEJAQAAAA==.',
Es='Escänor:BAABNQAECn8hAAMDAAkK5R7WJAAyAwADAAkK5R7WJAAyAwAGAAIKfwngZgBHAAAAAA==.Eshaia:BAAANQADCgEIAgAAAA==.Essemdee:BAAANQAECgQIBAAAAA==.Essiee:BAAANQAECgQIBAAAAA==.',
Ex='Exlisum:BAAANQADCgQIBgAAAA==.',
Ey='Eyewyn:BAAANQADCgEIAQAAAA==.Eylos:BAAANQAECgEIAQAAAA==.',
Fa='Faesmite:BAAANQADCgUIBQAAAA==.Faithflop:BAAANQAECgYIEAAAAA==.Falleh:BAAANQADCgIIAgAAAA==.Fanorage:BAAANQAECgIIAgAAAA==.',
Fe='Felixox:BAAANQAECgEIAQAAAA==.Ferocias:BAAANQAECgQJBQAAAA==.Ferraxx:BAAANQADCgcIBwAAAA==.Fewture:BAAANQADCgUIBQAAAA==.',
Fi='Fiametta:BAAANQADCggICAAAAA==.Fishbreath:BAAANQAECgEIAQAAAA==.',
Fl='Flaffergan:BAAANQAECgYIEwAAAA==.Flastage:BAAANQAECgMIAgAAAA==.Flexhack:BAABNQAECn8dAAIQAAgKzgrjGwAEAQAQAAgKzgrjGwAEAQAAAA==.Flåsh:BAABNQAECn8fAAMfAAgK8SDtNACQAgAfAAcK+SDtNACQAgADAAcK9BXPlwD0AQAAAA==.',
Fo='Focinnet:BAABNQAECn8oAAITAAgKVwq8igD1AQATAAgKVwq8igD1AQAAAA==.Forandra:BAAANQAECgIIAgAAAA==.Forsaked:BAAANQADCgEIAQAAAA==.Fortyacres:BAAANQADCgEIAQABNQADCgEIAgACAAAAAA==.Fortybmh:BAAANQADCgEIAgAAAA==.Four:BAAANQADCgYJDgAAAA==.Fourform:BAAANQADCgIIAgAAAA==.',
Fr='Frianna:BAAANQAECgMIAwAAAA==.Frieren:BAAANQAECggIDgAAAA==.',
Fu='Fuzzbutt:BAAANQADCgEIAQAAAA==.',
Ga='Gaalit:BAAANQADCgcICAAAAA==.Galaxybone:BAAANQADCgQIBAAAAA==.Galithiri:BAAANQAECgUIAwAAAA==.Ganthani:BAABNQAECn8gAAIEAAcKNhAZhgCEAQAEAAcKNhAZhgCEAQAAAA==.Garzett:BAABNQAECn84AAILAAoKPxcbBAAiAgALAAoKPxcbBAAiAgAAAA==.Gatortooth:BAAANQADCgEIAQAAAA==.Gaybeowners:BAAANQAECgEJAQAAAA==.',
Ge='Geigh:BAAANQADCgUIBgAAAA==.Gethellar:BAABNQAECn8eAAMTAAoK1BLJEwDUAQATAAkK/hTJEwDUAQAYAAEKqgP5nAAiAAAAAA==.',
Gh='Ghostdaliar:BAAANQADCgQIBgAAAA==.Ghouliana:BAAANQADCgUIBQABNQAECgIIAgACAAAAAA==.',
Gl='Glizyglober:BAAANQADCgMIAwABNQAFFAIICAALAGIEAA==.Glizzyrizily:BAAANQADCgMIAwABNQAFFAIICAALAGIEAA==.Glizzyys:BAABNQAECn8jAAIPAAkKCw21NABBAQAPAAkKCw21NABBAQABNQAFFAIICAALAGIEAA==.Gllizzard:BAAANQADCgMJAwAAAA==.Gluckglucks:BAAANQADCgEIAQAAAA==.',
Go='Goblikon:BAAANQADCgMIAwABNQAECgYIDwACAAAAAA==.Gore:BAABNQAECn8XAAQMAAoKaAXoWwA5AQAMAAoKaAXoWwA5AQAIAAMKwQFHzQBSAAAbAAEKAAAPxABAAAAAAA==.Gorrock:BAAANQAECgQIBAAAAA==.',
Gr='Gravtech:BAAANQAECgEIAQABNQAECgoKFQARAMEPAA==.Greenlinaii:BAAANQADCggICgAAAA==.Greffin:BAAANQAECgEIAQAAAA==.Grenzo:BAAANQAECgEIAgAAAA==.Grhm:BAAANQAECgcIBwAAAA==.Grim:BAABNQAECn8iAAMIAAoK/CJDFwACAwAIAAoK9SJDFwACAwAMAAMKyiIdZgAJAQABNQAFFAUICQAgAGsHAA==.Grimheart:BAAANQAECgEIAQAAAA==.Grundles:BAAANQADCggICAAAAA==.Grymnir:BAABNQAECn8eAAMcAAoKmQm+jQCCAQAcAAgKWwu+jQCCAQAaAAYKSARyDwAKAQAAAA==.',
Gu='Guilliman:BAAANQAECgIIBAAAAA==.Gumsy:BAABNQAECn8jAAMPAAkKiRDSHQCMAQAPAAkKiRDSHQCMAQAWAAQKwQxzMgCjAAABNQAECgkJJwAIAPwYAA==.',
Gw='Gwory:BAAANQAECgUIBgAAAA==.',
['Gø']='Gørë:BAABNQAECn8ZAAMHAAoKZQnGVwDTAAAHAAoKZQnGVwDTAAAVAAEKAABugQAqAAAAAA==.',
Ha='Haddassah:BAAANQADCgIIAgAAAA==.Haramzadi:BAAANQADCgQICQAAAA==.Haranue:BAABNQAECn8cAAITAAYKgwhQYwDkAAATAAYKgwhQYwDkAAAAAA==.Harryporter:BAAANQAECgEIAQAAAA==.Harukà:BAAANQAECgUIDAAAAA==.Hatxo:BAAANQADCgQIBAABNQAECgcICgACAAAAAA==.',
He='Healscat:BAAANQADCgUJBQAAAA==.Healsdog:BAAANQAECgEIAQAAAA==.Hefferd:BAAANQADCgQIBAAAAA==.Helfon:BAABNQAECn8pAAIOAAoK8R2aFAD4AgAOAAoK8R2aFAD4AgAAAA==.Helgadknight:BAAANQABCgMIAwAAAA==.Helganelf:BAAANQAECgEIAQAAAA==.Helices:BAABNQAECn8aAAMbAAkK8hinPAAQAgAbAAcKIBunPAAQAgAIAAIKfxPkNwB7AAAAAA==.Herm:BAAANQAECgEIAQAAAA==.',
Hi='Highlordt:BAABNQAECn8rAAQEAAkKAxU/cwDCAQAEAAgKkBM/cwDCAQAhAAkK0hgOBwCFAQAiAAEKrwd3LgAoAAAAAA==.Highlordtron:BAABNQAECn8ZAAQHAAkKsRL6KwBEAQAHAAkKlxH6KwBEAQAVAAEKohKlcQA9AAAFAAEKCwfULQA7AAAAAA==.Hinazuki:BAAANQAECgMIAwAAAA==.Hinoxfine:BAAANQADCgMIBAAAAA==.Hitmans:BAAANQADCgEIAQAAAA==.',
Ho='Holybeast:BAAANQADCgIIAgAAAA==.Holycharge:BAAANQAECgIIAgAAAA==.Holycrab:BAAANQAECgEIAQAAAA==.Holydudy:BAAANQAECgEIAQAAAA==.Holyely:BAAANQAECgYICwAAAA==.Holyfae:BAABNQAECn8tAAMfAAoKNBXEQABiAgAfAAoKNBXEQABiAgADAAQKbQbPPQG9AAAAAA==.Holygrom:BAABNQAECn8qAAIDAAkKOyWpBwC9AwADAAkKOyWpBwC9AwAAAA==.Holylove:BAAANQADCgUICgABNQAECgIIAwACAAAAAA==.Holynutzz:BAAANQAECgMIAwAAAA==.Holyrager:BAAANQAECgQICAAAAA==.Holysplash:BAABNQAECn8cAAIEAAcKiBS4cQDIAQAEAAcKiBS4cQDIAQAAAA==.Holyvoids:BAAANQADCgIIAgAAAA==.Hondodk:BAECNQAFFH8XAAIIAAYKLiXhAAByAgAIAAYKLiXhAAByAgA1AAQKfzwAAwgACgqeJisAAHYDAAgACgqUJisAAHYDABsAAQrDJr+uAG4AAAE1AAUUBwgTAAgAYyQA.Honeyshamwow:BAAANQAECgMIAwAAAA==.Hoodadin:BAAANQADCgEIAQAAAA==.Hoodlummon:BAAANQADCggJHwAAAA==.Hopesfall:BAAANQAECgIJAwAAAA==.Howzitcuz:BAAANQADCgcIHAABNQAECggIHgAfAN4aAA==.Hozari:BAABNQAECn8tAAILAAkKCxjLIwCyAgALAAkKCxjLIwCyAgAAAA==.',
Ht='Ht:BAAANQADCgcIDAAAAA==.',
Hu='Hunterstickg:BAAANQADCgUIBQAAAA==.',
['Hã']='Hãvøc:BAAANQADCgIIAgAAAA==.',
Ia='Ianil:BAAANQAECgQIBgAAAA==.',
Ic='Iccyhot:BAAANQADCgMIAwABNQAFFAIICAALAGIEAA==.Icecube:BAAANQADCgEIAQAAAA==.',
Ii='Iiwhiskey:BAAANQADCgcICAAAAA==.',
Il='Ilirranna:BAAANQAECgIIBAAAAA==.',
In='Infi:BAACNQAFFH8dAAMYAAgKwSJeAwBZAgAYAAgKGx1eAwBZAgATAAEKLyXsLQBnAAA1AAQKf0gAAxgACgo0JVkBANwDABgACgo0JVkBANwDABMAAQrZJn86AXAAAAAA.Initabath:BAABNQAECn8XAAMLAAkKBgPgigCpAAALAAYKsgTgigCpAAABAAkKmAJ7WQChAAAAAA==.Initapoop:BAAANQAECgQIDAAAAA==.Inosukè:BAABNQAECn80AAIdAAoKDCPaAQCsAwAdAAoKDCPaAQCsAwAAAA==.Inse:BAAANQAECgQIBAAAAA==.Invisibro:BAABNQAECn8VAAIRAAoKwQ8uOAD2AQARAAoKwQ8uOAD2AQAAAA==.',
Io='Ioannis:BAAANQAECgUIEgAAAA==.',
Ip='Ipse:BAAANQADCgMIAwAAAA==.',
Ir='Irasenme:BAAANQAECgIIAgAAAA==.',
Is='Isos:BAABNQAECn85AAMEAAoKkiJNBwB3AgAEAAoKkiJNBwB3AgAiAAEKCBC0KAAzAAAAAA==.Isus:BAAANQADCgYJBgABNQAECgoKOQAEAJIiAA==.',
Iy='Iykyk:BAAANQAECgMIAgABNQAECggIHgAfAN4aAA==.',
Ja='Jadeadly:BAAANQAECgcICAAAAA==.Jaded:BAABNQAECn8oAAIUAAkK3BTxHgA5AgAUAAkK3BTxHgA5AgAAAA==.Jakerbonk:BAAANQADCgYICAAAAA==.Jakersai:BAABNQAECn8VAAISAAkKvA7dCwChAQASAAkKvA7dCwChAQAAAA==.Jakersaint:BAAANQADCggIDAAAAA==.Jamae:BAAANQAECgUIBAAAAA==.Javyr:BAAANQAECgUIDgAAAA==.Jayfmtv:BAAANQAECgMIBAAAAA==.Jaysdruid:BAAANQAECgQIBAAAAA==.',
Je='Jessicax:BAAANQAECgQIBAAAAA==.Jetpackcat:BAAANQADCgIIAgAAAA==.',
Ji='Jio:BAAANQAECgEIAQAAAA==.',
Jl='Jlnxy:BAABNQAECn8ZAAIDAAoKzQkYugCpAQADAAoKzQkYugCpAQAAAA==.',
Jo='Joania:BAAANQADCggICAAAAA==.Jonoa:BAAANQADCgUIBQAAAA==.',
Ju='Judgmentalaf:BAAANQADCggIFwAAAA==.Judo:BAAANQAECgEIAgAAAA==.',
Ka='Kadre:BAABNQAECn8dAAIWAAcKUQP4EwCUAAAWAAcKUQP4EwCUAAAAAA==.Kadzilak:BAAANQADCgQIBgAAAA==.Kagemika:BAAANQAECgQIBAABNQAFFAMICAAOAFoIAA==.Kaiola:BAAANQAECgMIAwAAAA==.Kaizumie:BAAANQAECgIIAgAAAA==.Kalirti:BAAANQADCgIIAgAAAA==.Kamistri:BAABNQAECn8pAAQEAAoKCCBkHwDyAgAEAAoKCCBkHwDyAgAhAAMKHw/8YQB5AAAiAAIKrAZkIwBOAAAAAA==.Kanaa:BAAANQAECgUIBwAAAA==.Kanatre:BAAANQAECgEIAQAAAA==.Kandicee:BAAANQAECgIIAwAAAA==.Karensmith:BAAANQADCgcIBwAAAA==.Karessandra:BAAANQADCgQIBAABNQAECgUIAwACAAAAAA==.Karlhungus:BAAANQADCgEIAQAAAA==.Karrison:BAAANQADCgEIAQAAAA==.Kathea:BAAANQAECgQIBAAAAA==.Kayarra:BAAANQADCgEIAgABNQADCgQIBAACAAAAAA==.Kaynarra:BAAANQADCgQIBAAAAA==.Kayonna:BAAANQADCgEIAQABNQADCgQIBAACAAAAAA==.',
Ke='Keastral:BAAANQAECgUIBgAAAA==.Keeynai:BAAANQADCgQIBQAAAA==.Keldanis:BAABNQAECn8qAAITAAkKghX9DAAKAgATAAkKghX9DAAKAgAAAA==.Kelestrah:BAAANQADCgQJBAAAAA==.Kelterrager:BAAANQADCgMIAwAAAA==.Keony:BAABNQAECn8eAAIfAAgK3hrbJABQAQAfAAgK3hrbJABQAQAAAA==.Kerthur:BAAANQAECgMIAwAAAA==.',
Ki='Kickpigeons:BAAANQADCgEIAgAAAA==.Killertcells:BAAANQABCgIIAgAAAA==.Kirgrand:BAAANQADCgMIAwAAAA==.Kittyarly:BAAANQAECggIEAAAAA==.',
Ko='Kodeck:BAAANQADCggIHQAAAA==.Kodokan:BAAANQAECgEIAQAAAA==.Koshima:BAABNQAECn8tAAIcAAoK6BheNwCZAgAcAAoK6BheNwCZAgAAAA==.Kozan:BAAANQADCgUICAAAAA==.',
Kr='Krimdan:BAAANQADCgQIBAAAAA==.Krimhit:BAAANQADCgUIDAAAAA==.Krimrok:BAAANQADCgEIAQAAAA==.Krimwarr:BAAANQADCgQIBAAAAA==.',
Ku='Kudou:BAAANQADCgMIAwAAAA==.Kudranne:BAAANQADCgQICQABNQAECgUIAwACAAAAAA==.Kugia:BAABNQAECn8qAAIBAAoK5h0wDwDiAgABAAoK5h0wDwDiAgAAAA==.Kuroba:BAAANQADCgEIAQAAAA==.',
Ky='Kylex:BAAANQAECgEIAQAAAA==.Kynndell:BAAANQADCggIGQAAAA==.Kyo:BAAANQADCgYIDgAAAA==.Kyrem:BAAANQADCgEIBAAAAA==.',
['Kø']='Køkushibø:BAAANQADCgEIAQAAAA==.',
La='Laments:BAAANQADCgUIBQAAAA==.Lammb:BAAANQADCgUIBQAAAA==.Lanfeariel:BAAANQAECgEIAQAAAA==.Latak:BAAANQADCgMIAwAAAA==.Latir:BAAANQADCgUIBwAAAA==.Lazylox:BAAANQAECgEIAQAAAA==.Lazyryx:BAAANQADCgUIBQAAAA==.',
Le='Leetheal:BAACNQAFFH8RAAMEAAUKIgokCwATAQAEAAUKIgokCwATAQAhAAMKVhPnDQD1AAA1AAQKfy0AAwQACgrfFes/AGsCAAQACgrfFes/AGsCACEACAq1G9UhACcCAAAA.Leethul:BAABNQAECn8vAAIHAAoK9BUNBgBSAgAHAAoK9BUNBgBSAgAAAA==.Lelethxx:BAAANQAECgIIBAAAAA==.Lesanna:BAABNQAECn86AAIOAAoKHQuhCQCsAQAOAAoKHQuhCQCsAQAAAA==.Lestharia:BAAANQAECgUIBQAAAA==.Leysmith:BAABNQAECn82AAIDAAoKZBITLwBzAQADAAoKZBITLwBzAQAAAA==.',
Li='Lifestream:BAAANQAECgIIAgAAAA==.Lilheal:BAAANQAECgIJAgAAAA==.Lilium:BAAANQADCgYICwAAAA==.Lionël:BAAANQAECgYICQAAAA==.Lisax:BAAANQAECgEIAQAAAA==.Lizbethe:BAABNQAECn8oAAQVAAoKyhxqBwCPAgAVAAcK4CBqBwCPAgAHAAcKqhrWiADQAQAFAAcK3BtBAgBsAQAAAA==.',
Lo='Loadedtotem:BAAANQAECgMIAwAAAA==.Lockmclovin:BAAANQADCgMIAwAAAA==.Loltank:BAAANQAECgcICwAAAA==.Lomrgreenol:BAAANQADCgQIBAAAAA==.Lopi:BAAANQAECgQIAwAAAA==.Lorast:BAAANQAECgEIAQAAAA==.Lorwater:BAAANQADCgQIBAAAAA==.Loveinfinity:BAAANQADCgEIAQAAAA==.',
Lp='Lp:BAAANQADCgYICAAAAA==.',
Lu='Lumibell:BAAANQADCgEIAQAAAA==.Luminate:BAAANQADCgQIBAAAAA==.Lunaru:BAAANQAECgEIAQAAAA==.Lunaryon:BAAANQADCgUICgAAAA==.',
Ma='Madamgypsy:BAAANQAECgQIDAAAAA==.Madderco:BAAANQAECggICAAAAA==.Madivh:BAAANQADCgQIBAAAAA==.Magaspy:BAAANQAECgUIDgAAAA==.Magerage:BAAANQAECgEIAQAAAA==.Magerassfoo:BAAANQAECgUIBgAAAA==.Magiccairne:BAAANQAECgUIDgAAAA==.Magikiarly:BAAANQAECgUIBQABNQAECggIEAACAAAAAA==.Magnar:BAAANQAECgIIAgABNQAECgcIDwACAAAAAA==.Mahoogany:BAAANQADCgYIDAAAAA==.Malson:BAAANQADCgYIBgAAAA==.Mamimage:BAACNQAFFH8NAAIKAAQK6Bb2NQDtAAAKAAQK6Bb2NQDtAAA1AAQKfz0AAgoACgpzIFEcAGYDAAoACgpzIFEcAGYDAAAA.Marukka:BAAANQADCgQIBAABNQADCgcIBwACAAAAAA==.Matty:BAAANQADCgEIAQAAAA==.Mayiana:BAAANQAECgMIBgAAAA==.',
Mc='Mcspanky:BAAANQAECggICAAAAA==.',
Me='Meadowlark:BAAANQAECgQIBAAAAA==.Mefistofeles:BAAANQAECgUIDAAAAA==.Mellie:BAAANQADCgQIBQAAAA==.Meowstic:BAABNQAECn8qAAMjAAkKKB4JBwAaAwAjAAgKoSIJBwAaAwALAAEKVAOHWgAcAAABNQAECgIIAgACAAAAAA==.Mercurious:BAAANQAECgUIDQAAAA==.Metalrules:BAAANQADCgEIAQAAAA==.Methypheni:BAAANQAECgYIEAAAAA==.',
Mi='Mill:BAAANQADCgYICgAAAA==.Minimuff:BAAANQADCgUIBQAAAA==.Mirajanna:BAABNQAECn85AAIkAAoK3xVjAgCsAQAkAAoK3xVjAgCsAQAAAA==.Missmouthoff:BAABNQAECn8uAAIEAAgKSheqSwBCAgAEAAgKSheqSwBCAgAAAA==.Mitenâ:BAAANQADCgUIBgAAAA==.Mizzxgummy:BAAANQAECgcIBwAAAA==.',
Mo='Momster:BAAANQADCggIDgAAAA==.Moncaris:BAAANQADCgEIAQAAAA==.Monkin:BAAANQAECgEIAQAAAA==.Moogan:BAAANQAECgUICgAAAA==.Mookins:BAAANQAECgYIEgAAAA==.Moonfishing:BAABNQAECn8nAAIKAAoKkhbCeACMAgAKAAoKkhbCeACMAgAAAA==.Moonfly:BAACNQAFFH8NAAILAAYKTReRDgCAAQALAAYKTReRDgCAAQA1AAQKfykAAgsACgpQI6EPAEsDAAsACgpQI6EPAEsDAAAA.Morax:BAAANQAECgUIEAAAAA==.Morbidlord:BAAANQADCgEIAQAAAA==.Moscacrazy:BAAANQADCggIDQAAAA==.Mourne:BAABNQAECn8oAAMRAAoKnRhDDgBSAQARAAoKnRhDDgBSAQAQAAIKMRHLRACRAAAAAA==.',
Ms='Mssmalvile:BAAANQADCgYJCwAAAA==.',
Mt='Mtnoflight:BAAANQADCgMIAwAAAA==.',
My='Myrrvain:BAAANQAECgEIAQAAAA==.Mythara:BAAANQADCgYIBgAAAA==.',
Na='Naarcissus:BAAANQADCgEIAwAAAA==.Nagrim:BAAANQAECgEIAgABNQAECgkJJwAIAPwYAA==.Nalaana:BAAANQAECgYIDgAAAA==.Nalariel:BAABNQAECn8hAAMIAAkKgiAiKwCJAgAIAAkKgiAiKwCJAgAbAAEKeRpXvQBNAAAAAA==.Nallaana:BAAANQAECgYIBwAAAA==.Nalmagedan:BAABNQAECn8eAAIKAAgKFgu6SAAqAQAKAAgKFgu6SAAqAQAAAA==.Nammi:BAAANQADCgMIAwAAAA==.Nardalem:BAAANQADCgcIBwAAAA==.Nardorne:BAAANQADCgMIAwAAAA==.Narec:BAAANQADCgUIBQAAAA==.Narfhound:BAAANQADCgYICAAAAA==.Nazgrok:BAAANQAECgcIDwAAAA==.',
Ne='Nearhammer:BAAANQAECgEIAQAAAA==.Nearsear:BAAANQADCgcIBwAAAA==.Nefariouz:BAAANQAECggIBAAAAA==.Nervouz:BAABNQAECn8qAAIOAAoKExIRCQC0AQAOAAoKExIRCQC0AQAAAA==.Netherpally:BAAANQADCgQJBAAAAA==.',
Ni='Nightbreed:BAAANQAECgEIAQAAAA==.Nikis:BAAANQADCgcIDwAAAA==.',
No='Nobbs:BAAANQAECgQIBgAAAA==.Noonecaress:BAAANQAECgIIAgAAAA==.Notacow:BAAANQADCgEIAQAAAA==.',
Nu='Nualaperafin:BAACNQAFFH8JAAIaAAMKpBosAgCwAAAaAAMKpBosAgCwAAA1AAQKfzIAAhoACgqbHq0GABkDABoACgqbHq0GABkDAAAA.',
Ny='Nyvara:BAAANQADCgQIBAABNQAECgUIDQACAAAAAA==.Nyxkitsune:BAAANQADCggIDQAAAA==.',
Od='Odrada:BAAANQADCgQIBAAAAA==.',
Of='Off:BAAANQAECgEIAQAAAA==.',
Oi='Oiyo:BAAANQADCgEIAQAAAA==.',
Ok='Okonomiyaki:BAAANQADCgcIBwAAAA==.',
Ol='Olayro:BAABNQAECn8xAAMFAAoKMg8NAQDXAQAFAAoKMg8NAQDXAQAHAAcKrAdkzQAvAQAAAA==.Olelei:BAAANQADCgEIAQAAAA==.',
Om='Omie:BAAANQADCgcIFwAAAA==.',
On='Onkiea:BAAANQABCgYJBAAAAA==.Onlyrage:BAAANQAECgUJCQAAAA==.',
Oo='Oomkin:BAAANQADCgQIBAAAAA==.Ooptomss:BAABNQAECn8qAAITAAkKHBHjRQApAQATAAkKHBHjRQApAQAAAA==.',
Op='Openingshift:BAAANQAECgQIBQAAAA==.Ophelìa:BAAANQADCgcICAAAAA==.Ophilitheda:BAAANQADCgYIAwAAAA==.',
Or='Orclee:BAAANQAECgYIEQAAAA==.',
Pa='Pacificadora:BAAANQAECgUIBgAAAA==.Palaguy:BAAANQADCgQIBAAAAA==.Palkavanka:BAAANQAECgQIEAAAAA==.Pandamonk:BAAANQAECgYIBwAAAA==.',
Pe='Peeonfists:BAAANQADCgEIAQAAAA==.Peeonkeys:BAAANQAECgMIAwAAAA==.Persephie:BAAANQAECgQICwABNQAECgkJJwAIAPwYAA==.Perzeval:BAAANQADCgMJAwAAAA==.',
Ph='Pharmacology:BAABNQAECn8dAAIEAAgKPR8DEQDvAQAEAAgKPR8DEQDvAQAAAA==.Phyberlamer:BAAANQADCgEIAQAAAA==.Phénicie:BAAANQADCgcIHQAAAA==.',
Pi='Pinkberri:BAAANQAECgEIAQAAAA==.Pinkblossom:BAAANQAECgQICAAAAA==.Pipha:BAAANQADCgEIAQAAAA==.Pitchblack:BAAANQADCggIDwAAAA==.',
Pl='Plutochibi:BAAANQABCggICwAAAA==.',
Po='Pocholate:BAAANQAECgMIAwAAAA==.Popa:BAABNQAECn8zAAQfAAkKsBlQMAClAgAfAAkKsBlQMAClAgADAAUKDhm/7gA/AQAGAAQKvhRsQgDrAAAAAA==.',
Pr='Prathe:BAABNQAECn8YAAIfAAcK2CMcBwBWAgAfAAcK2CMcBwBWAgAAAA==.Prayinfury:BAAANQAECgcICAAAAA==.Premorry:BAAANQAECgIIAgAAAA==.Premory:BAAANQADCgUICwAAAA==.Presagee:BAAANQADCgEIAQAAAA==.',
Ps='Psilocy:BAAANQAECgcIDwAAAA==.',
Pu='Pulsate:BAABNQAECn8jAAIlAAoKJRnMCgC/AgAlAAoKJRnMCgC/AgAAAA==.Pulu:BAAANQAECgQIBQAAAA==.Purpleduster:BAAANQADCgEIAQAAAA==.',
Py='Pyllo:BAAANQAECggICgAAAA==.',
Qa='Qaucker:BAAANQAECggIEQAAAA==.',
Qi='Qiz:BAABNQAECn8bAAMJAAgKzRZwHwDuAAAKAAUKqRBtGQFhAQAJAAQKbhlwHwDuAAAAAA==.Qizknows:BAAANQADCgEIAQAAAA==.',
Qu='Quadhelix:BAABNQAECn8YAAMWAAoKEhpPDQBdAgAWAAcKfB5PDQBdAgAPAAYKiA6CZwDKAAAAAA==.Quartermain:BAAANQAECggICAAAAA==.Quary:BAAANQADCgEIAQAAAA==.Quistas:BAAANQADCgEIAQAAAA==.',
Qw='Qwish:BAAANQADCgYIBwAAAA==.',
Ra='Rad:BAAANQAECggIEwAAAA==.Radlock:BAAANQAECgMIAQABNQAECggIEwACAAAAAA==.Ragémachine:BAAANQADCgcICwAAAA==.Raijin:BAAANQADCgcICAABNQAECgcIDwACAAAAAA==.Raiken:BAAANQAECgQIBwAAAA==.Raistlen:BAAANQAECgEIAQAAAA==.Rakin:BAAANQABCgQIBAAAAA==.Rakmin:BAAANQAECgQICAAAAA==.Rarib:BAAANQADCgcIBwAAAA==.Raspberry:BAAANQAECgcICwAAAA==.Rasto:BAAANQAECgQJBwAAAA==.Raszto:BAAANQADCgIIAwABNQAECgQJBwACAAAAAA==.Rattlebat:BAAANQAECgIIAgAAAA==.',
Re='Redmark:BAAANQAECgQIBAAAAA==.Redwrath:BAAANQADCgIIAgAAAA==.Regolas:BAAANQADCgMIAwAAAA==.Rendezook:BAAANQAECgQICAAAAA==.Respec:BAAANQADCggICAAAAA==.',
Ri='Rincewind:BAAANQADCggIFwAAAA==.Riohne:BAAANQADCgMIAwAAAA==.Ripzly:BAAANQADCgEIAQAAAA==.Rivexis:BAAANQADCgMIBAAAAA==.',
Ro='Roci:BAAANQADCggIFgAAAA==.Rocker:BAAANQAECggICAAAAA==.Rolone:BAAANQADCgEIAQAAAA==.Rootway:BAAANQAECgQIBAAAAA==.Roxus:BAABNQAECn8sAAIPAAcKwSPwFAC2AQAPAAcKwSPwFAC2AQABNQAECggIFgAgAHsKAA==.Roxusdruid:BAABNQAECn8WAAIgAAgKewrQHgAjAQAgAAgKewrQHgAjAQAAAA==.',
Ru='Ruthlin:BAAANQADCgYIBgAAAA==.',
Sa='Sabellal:BAAANQADCgYIBgAAAA==.Saegusa:BAABNQAECn8ZAAIJAAgKHhXGAwCCAQAJAAgKHhXGAwCCAQAAAA==.Saepius:BAAANQAECgIIAgAAAA==.Salestia:BAABNQAECn8nAAIKAAkKsw27ZQDxAAAKAAkKsw27ZQDxAAAAAA==.Saltwater:BAAANQADCgEIAQAAAA==.Samellir:BAAANQAECgMIBgAAAA==.Sanlanesh:BAAANQADCgUIBQAAAA==.Sardothien:BAAANQADCgEIAQAAAA==.Sasive:BAAANQAECgcIDAAAAA==.Satanicpanic:BAAANQAECgcIDAAAAA==.Sazoku:BAABNQAECn8gAAIPAAoKhh1gIgB7AQAPAAoKhh1gIgB7AQAAAA==.',
Sc='Scario:BAAANQADCgEIAQAAAA==.Scarletlock:BAAANQAECgcIBgABNQAECgoKJQAEAHgeAA==.Scarletnight:BAAANQAECgUICQABNQAECgoKJQAEAHgeAA==.Schmall:BAABNQAECn8UAAIcAAcK9BGnfQCrAQAcAAcK9BGnfQCrAQAAAA==.Scrodumpulse:BAAANQADCgcIEAAAAA==.',
Se='Selvalin:BAAANQADCggIDgAAAA==.Sendit:BAAANQAECgcICQAAAA==.Seniormage:BAABNQAECn8WAAIKAAcKqhwwqwAsAgAKAAcKqhwwqwAsAgAAAA==.Serveil:BAAANQADCgIIAgABNQAFFAMICAAmAOsCAA==.',
Sh='Shaboon:BAAANQAECggICAAAAA==.Shadesprint:BAAANQAECggIBwAAAA==.Shamamoomoo:BAABNQAECn8hAAIQAAgKbwPZLABbAQAQAAgKbwPZLABbAQAAAA==.Shaninigans:BAAANQADCgEIAQAAAA==.Shaowen:BAAANQADCgYIBgABNQAECgcIDwACAAAAAA==.Shaqeesha:BAAANQADCgUIBQAAAA==.Shenea:BAAANQADCgYICQAAAA==.Shestalker:BAACNQAFFH8JAAITAAQKzxCJBwDvAAATAAQKzxCJBwDvAAA1AAQKf1UAAhMACgpnGn4MAA4CABMACgpnGn4MAA4CAAAA.Shiau:BAABNQAECn8ZAAIUAAgKJAbHPAAwAQAUAAgKJAbHPAAwAQAAAA==.Shieldheart:BAAANQADCgEIAQAAAA==.Shigaraki:BAAANQAECggIEAABNQAECgoKNAAdAAwjAA==.Shimsaw:BAAANQADCgEIAQAAAA==.Shimura:BAAANQADCgYICgAAAA==.Shinky:BAAANQADCgUIBAABNQAECgkJGgAHAEoXAA==.Shivv:BAAANQADCgEIAQAAAA==.Shý:BAAANQAECgQIDgAAAA==.',
Si='Silana:BAAANQADCggIDgAAAA==.Silvaine:BAAANQAECgYIDQAAAA==.Silverstorm:BAABNQAECn8YAAIPAAgKjBGRnQDSAQAPAAgKjBGRnQDSAQAAAA==.Sisterfran:BAAANQAECgEIAQAAAA==.Sixii:BAAANQAECgMIAwAAAA==.',
Sk='Skitzz:BAAANQAECgQICAAAAQ==.',
Sl='Slackr:BAAANQADCgUIBQAAAA==.Slackrm:BAAANQADCgMJBwAAAA==.Slackrp:BAAANQADCgQIBAAAAA==.Slashyr:BAAANQAECgQIDAAAAA==.Slimshadydh:BAAANQAECgQICwAAAA==.',
Sn='Snipez:BAAANQAECgIJAwAAAA==.Snortyhotorc:BAAANQAECgcICwAAAA==.Snortymcgoop:BAABNQAECn8nAAMTAAoK3RoWFADSAQAYAAgKihibIwAxAgATAAcKkBYWFADSAQAAAA==.',
So='Solclipeus:BAABNQAECn8/AAMGAAoKmx/HBQBRAwAGAAkKaSHHBQBRAwADAAQKLhWFUQAiAQAAAA==.Soldh:BAAANQAECgUIDAABNQAECgoKPwAGAJsfAA==.Solku:BAAANQAECgMIBgABNQAECgoKLgAEADwMAA==.Sollock:BAABNQAECn8YAAIHAAgKlRdGHAB/AQAHAAgKlRdGHAB/AQABNQAECgoKPwAGAJsfAA==.Solna:BAAANQAECgUIEAABNQAECgoKLgAEADwMAA==.Soulrecall:BAAANQAECgIIAwAAAA==.Soupz:BAABNQAECn8ZAAIDAAgK4x99XQCAAgADAAgK4x99XQCAAgAAAA==.',
Sp='Sparadin:BAABNQAECn8YAAIGAAcKcguGNgA0AQAGAAcKcguGNgA0AQAAAA==.Spartacûs:BAAANQAECgQJBQABNQAECggIGgAGACUhAA==.Spikore:BAAANQAECgEIAQAAAA==.Splitpeaz:BAAANQADCgcJBwAAAA==.',
Sq='Squrìtle:BAAANQAECgUICAAAAA==.',
Sr='Sririacha:BAAANQADCgUIBwABNQAECggIBwACAAAAAA==.',
Ss='Ssjweedgoku:BAAANQAECgEIAQAAAA==.',
St='Stabbyjohn:BAAANQADCggICAAAAA==.Stabbypickle:BAAANQAECgYIDQABNQAECgkJJgAfADEmAA==.Stachelbeere:BAAANQADCgYIBgAAAA==.Steedvegeta:BAAANQAECgQIBgAAAA==.Stephelle:BAAANQADCgEIAQAAAA==.Stickybug:BAAANQAECgUIEAAAAA==.Strånge:BAAANQAECgYIBwAAAA==.Stìtch:BAACNQAFFH8cAAIHAAcK7BpvAQCnAQAHAAcK7BpvAQCnAQA1AAQKfzsAAgcACgqgJZUEAK8DAAcACgqgJZUEAK8DAAAA.Stítch:BAAANQADCgQIBAABNQAFFAcIHAAHAOwaAA==.',
Su='Sukiafaunias:BAAANQAECgEIAgAAAA==.Sukiafloras:BAAANQAECgMIAgAAAA==.Suldån:BAAANQAECgIIAgAAAA==.Summondaddy:BAAANQADCgQIBQAAAA==.Sunfurious:BAAANQAECgYIDgAAAA==.Suoop:BAAANQAECgYICwAAAA==.Supan:BAAANQADCgQIBAAAAA==.',
Sw='Swiftshaman:BAAANQAECgEIAQAAAA==.',
Sy='Synvaria:BAAANQAECgUICAAAAA==.Syraice:BAAANQADCgUIBQABNQAECgoKNgAmAFIYAA==.Syrare:BAAANQAECgIIAgAAAA==.Syvenari:BAAANQAECgQICQAAAA==.',
['Sï']='Sïxx:BAAANQADCgMJAwABNQAECgMIAwACAAAAAA==.',
Ta='Tachisan:BAAANQAECgQICAAAAA==.Taeril:BAAANQADCgQIBAAAAA==.Tamfam:BAAANQADCggJEQAAAA==.Tanburn:BAAANQADCgYICwAAAA==.Tanduinex:BAAANQADCgYIDwAAAA==.Tangal:BAAANQAECgEIAQAAAA==.Tankstabber:BAAANQADCgQIBgAAAA==.Tanplate:BAAANQADCgYICQAAAA==.Tarentia:BAAANQABCggIDgAAAA==.Tastytyrande:BAAANQAECgUIBQAAAA==.Tatsumy:BAABNQAECn8lAAIDAAgK+wu1UwAdAQADAAgK+wu1UwAdAQAAAA==.',
Tc='Tcmon:BAABNQAECn8zAAMTAAoKahrMLwDdAgATAAoKahrMLwDdAgAYAAMK5AusJAB9AAAAAA==.',
Te='Teachings:BAAANQADCgMIAwAAAA==.Teaglizzy:BAAANQADCgEIAQABNQAFFAIICAALAGIEAA==.Teehole:BAAANQAECgUICwAAAA==.Telihill:BAAANQADCgUIDgAAAA==.Telsarra:BAAANQAECgQIBgAAAA==.Temptroll:BAAANQADCgEIAQAAAA==.',
Th='Thalenia:BAAANQAECgEIAQAAAA==.Thebeastelf:BAAANQAECgIIAgABNQAECgkJHgAKAPISAA==.Thebigtuna:BAABNQAECn86AAInAAoKGSOqAAD/AgAnAAoKGSOqAAD/AgAAAA==.Thegigatuna:BAAANQADCgMIAwAAAA==.Thekrisaning:BAAANQADCgYIDAAAAA==.Theladydruid:BAABNQAECn83AAIBAAoKGRN0CgCQAQABAAoKGRN0CgCQAQAAAA==.Thelnaris:BAAANQADCgEIAQAAAA==.Themeats:BAAANQADCgQIBQAAAA==.Themufinator:BAAANQADCgEIAgAAAA==.Thendezoth:BAAANQAECgEIAgAAAA==.Thighsoffel:BAAANQADCgcIFQAAAA==.Thirdtjme:BAAANQADCgYIBgAAAA==.Thunderhóof:BAAANQADCgEIAgAAAA==.Thôr:BAAANQAECggICAAAAA==.',
Ti='Tierrasbest:BAAANQAECgEIAQAAAA==.Tigerpa:BAABNQAECn8YAAITAAUKFgl49QAXAQATAAUKFgl49QAXAQAAAA==.Tinkernut:BAAANQABCgIIAgAAAA==.Tinypally:BAAANQAECgEIAgAAAA==.Tinyraven:BAABNQAECn80AAInAAoK6xa+BADOAQAnAAoK6xa+BADOAQAAAA==.Tinysmites:BAAANQAECgEIAQAAAA==.Tinystotems:BAAANQAECgQIDAAAAA==.Tinythia:BAAANQADCgUIBgAAAA==.Tioklarus:BAABNQAECn84AAIlAAgK+gj8HgBkAQAlAAgK+gj8HgBkAQAAAA==.Tipzy:BAAANQADCgQIBAAAAA==.Tisaryn:BAAANQAECgQIBAAAAA==.',
To='Tofulady:BAABNQAECn8tAAIdAAoKMh8aCAAPAwAdAAoKMh8aCAAPAwAAAA==.Tohu:BAAANQAECgYIDgAAAA==.Toshen:BAAANQADCgEIAQAAAA==.Totax:BAAANQAECgEIAQAAAA==.Totemtoker:BAAANQADCggIDQAAAA==.',
Tr='Tremors:BAAANQADCggICAAAAA==.Triggër:BAAANQABCgQIBAABNQAECgEIAQACAAAAAA==.Tromb:BAAANQAECgQIBAAAAA==.',
Tu='Tucknroll:BAAANQADCgcICQAAAA==.',
Tw='Twobithusler:BAAANQAECgIIAgAAAA==.Twoon:BAAANQADCgYIBgAAAA==.Twoone:BAAANQADCgQIBAAAAA==.',
Ty='Tyniarstus:BAAANQADCgYICAAAAA==.',
Ud='Udderfiasco:BAAANQADCgEIAQAAAA==.',
Ug='Uggh:BAAANQADCgUIBQAAAA==.',
Un='Unhowly:BAACNQAFFH8JAAIIAAIKNhs6BQCbAAAIAAIKNhs6BQCbAAA1AAQKfywAAggACgqIJT8LAGADAAgACgqIJT8LAGADAAAA.Unpoppable:BAAANQAECggIEAAAAA==.',
Uz='Uzilok:BAAANQAECgYICQAAAA==.',
Va='Vaelyra:BAAANQADCgMIAwABNQAECgoKKgABAOYdAA==.Vakir:BAABNQAECn8oAAIbAAoKMBQLPQAOAgAbAAoKMBQLPQAOAgAAAA==.Valmortem:BAEANQADCgcIEgAAAA==.Vapidos:BAAANQAECgMIBwAAAA==.Varaniaani:BAAANQADCgEIAgAAAA==.Varynix:BAAANQAECgIIAgABNQAECgYIBwACAAAAAA==.Vatica:BAAANQAECgEIAQAAAA==.',
Ve='Velanoria:BAAANQADCggICwAAAA==.Veldorai:BAAANQADCgYIDAAAAA==.Velrenya:BAAANQADCgQIBgAAAA==.Velýndriel:BAAANQAECgUICgAAAA==.Venvalzhar:BAABNQAECn8mAAMEAAgKCyI3GgALAwAEAAgKCyI3GgALAwAhAAIKoAL+cgBAAAAAAA==.Veralidaine:BAAANQAECgQIBgAAAA==.Vestammeni:BAABNQAECn8tAAMWAAoKIyFaAgDlAQAWAAoKIyFaAgDlAQAPAAYKCg/kwgB2AQAAAA==.Vexlore:BAAANQADCgYIBwAAAA==.',
Vi='Vixsaurion:BAAANQAECgEIAQAAAA==.',
Vo='Voltx:BAAANQAECgEIAQAAAA==.Vorn:BAAANQADCgcICAAAAA==.Vow:BAABNQAECn8bAAIGAAcK6huoIADfAQAGAAcK6huoIADfAQAAAA==.',
Vy='Vynlenlor:BAAANQABCgIIAgAAAA==.',
Wa='Warmidget:BAAANQAECgEIAQAAAA==.',
Wc='Wckd:BAAANQAECgYIEgAAAA==.',
We='Weaksnow:BAABNQAECn8TAAIcAAgKoBH4PADTAAAcAAgKoBH4PADTAAABNQAFFAQIDQAKAOgWAA==.Weedgoku:BAAANQAECgQIBAAAAA==.Weedvegeta:BAABNQAECn8hAAIKAAoKfBtPDQABAgAKAAoKfBtPDQABAgAAAA==.Wernbirn:BAAANQAECggIAQAAAA==.Wetraman:BAAANQAECgEIAQABNQAECgQIBQACAAAAAA==.Wetremin:BAAANQAECgQIBQAAAA==.',
Wh='Whirpy:BAABNQAECn8cAAMBAAkKwRg2BgDtAQABAAkKwRg2BgDtAQALAAEKAAC2vgAiAAAAAA==.Whisberis:BAAANQADCgMIAwAAAA==.Whitty:BAAANQADCgQIBAAAAA==.Whizkee:BAAANQAECgcIEgAAAA==.Whookies:BAAANQADCgMIAwABNQAECgYIBgACAAAAAA==.',
Wi='Wildbeefwood:BAAANQAECgUICgAAAA==.Wingedlady:BAAANQAECgYIDwAAAA==.Wingss:BAACNQAFFH8FAAIDAAMKlh+wFAAQAQADAAMKlh+wFAAQAQA1AAQKfx4AAgMACQq5IVE4AO4CAAMACQq5IVE4AO4CAAAA.',
Wu='Wushu:BAAANQAECgQICgAAAA==.',
Wy='Wyl:BAABNQAECn8jAAIDAAgKziS1DgAHAgADAAgKziS1DgAHAgAAAA==.',
['Wù']='Wùkõng:BAAANQADCgEIAgAAAA==.',
Xe='Xerath:BAAANQAECgUICwAAAA==.',
Xi='Xiing:BAABNQAECn8wAAMWAAoKdhMPBwBIAQAWAAoKdhMPBwBIAQAPAAEKAAAyXgEpAAAAAA==.Xinei:BAAANQADCgQIAQAAAA==.Xinhe:BAAANQAECgIIAgAAAA==.',
Xn='Xneutron:BAAANQAECgcIEAAAAA==.',
Xt='Xtravagent:BAAANQADCgIIAgAAAA==.',
Xy='Xyxia:BAAANQADCgcICAAAAA==.',
Ya='Yaiie:BAABNQAECn83AAMVAAgKjgz8FgC1AQAVAAcKzA38FgC1AQAFAAcK+AxEBQDtAAAAAA==.',
Yo='Yonna:BAAANQAECgMIAwAAAA==.',
Yu='Yunggrazydk:BAAANQADCggIDAABNQAECgYIFgAEAF8SAA==.Yungholy:BAABNQAECn8WAAIEAAYKXxLaNAAsAQAEAAYKXxLaNAAsAQAAAA==.Yungresto:BAAANQADCgQIBQABNQAECgYIFgAEAF8SAA==.Yuuki:BAAANQADCgcIBwABNQAECgEIAQACAAAAAA==.Yuunggrazy:BAAANQADCggIEQABNQAECgYIFgAEAF8SAA==.',
['Yü']='Yüto:BAABNQAECn8pAAMTAAoKax/hHgAcAwATAAoKax/hHgAcAwAYAAQKshejVwDHAAAAAA==.',
Za='Zabuto:BAABNQAECn8bAAILAAgKUBXAQwDlAQALAAgKUBXAQwDlAQAAAA==.Zaeraciustv:BAAANQABCggIDwAAAA==.Zahäära:BAAANQAECgUIDQAAAA==.Zaldiz:BAAANQAECgEIAQAAAA==.Zar:BAAANQAECgQIBAAAAA==.Zarathor:BAAANQADCgQIBAABNQAECgcIDwACAAAAAA==.Zarril:BAAANQADCgEIAQAAAA==.Zarrtan:BAAANQAECgIIAQAAAA==.Zazevo:BAAANQAECgUIDQAAAA==.Zazmo:BAAANQADCgUIBQAAAA==.Zazprie:BAAANQAECgQIEAAAAA==.',
Ze='Zendrozath:BAAANQADCgQIBQABNQAECgQIBgACAAAAAA==.',
Zi='Zippyzap:BAAANQAECgEIAQAAAA==.',
Zo='Zooz:BAAANQADCgIIAgAAAA==.',
Zu='Zual:BAAANQAECgIIAwAAAA==.Zularraka:BAAANQAECgUICgAAAA==.',
Zx='Zxeý:BAAANQADCgcIDgAAAA==.',
['Äb']='Äbracadabruh:BAABNQAECn8cAAMKAAcKLhaWvAALAgAKAAcKthSWvAALAgAJAAEKdCL0NgBgAAABNQAECggIEwACAAAAAA==.',
['Äl']='Älissia:BAAANQAECgIIAgAAAA==.',
['Ål']='Ålexthegrëat:BAAANQAECgQIBQABNQAECgkJJwAKALMNAA==.',
['Èm']='Èmandy:BAAANQADCggIDQAAAA==.',
['Ën']='Ëndo:BAABNQAECn8nAAQIAAkK/BhDIgC9AgAIAAkK2hhDIgC9AgAbAAQK6RIXhADsAAAMAAEKAgkcYwBAAAAAAA==.',
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
