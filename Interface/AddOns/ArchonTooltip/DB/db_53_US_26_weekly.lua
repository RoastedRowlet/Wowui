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

local lookup = {'Druid-Restoration','Warlock-Demonology','Paladin-Retribution','Priest-Holy','Warlock-Affliction','Paladin-Protection','DeathKnight-Unholy','Druid-Balance','Mage-Frost','Mage-Arcane','Rogue-Subtlety','Unknown-Unknown','DeathKnight-Frost','Warrior-Fury','DemonHunter-Havoc','Warrior-Arms','Rogue-Assassination','Rogue-Outlaw','Hunter-BeastMastery','Warrior-Protection','Monk-Windwalker','Paladin-Holy','DeathKnight-Blood','Warlock-Destruction','Druid-Guardian','Druid-Feral','Monk-Brewmaster','Hunter-Marksmanship','Shaman-Restoration','Shaman-Enhancement','Shaman-Elemental','Monk-Mistweaver','Mage-Fire','Priest-Shadow','Priest-Discipline','DemonHunter-Vengeance','DemonHunter-Devourer','Evoker-Devastation','Evoker-Preservation',}
local provider = {region='US',realm='Azshara',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aaryyee:BAAANQAECgEIAQAAAA==.',
Ab='Abandination:BAAANQAECgQIBAAAAA==.',
Ac='Aceforlife:BAABNQAECn9gAAIBAAoKlxRSFwBhAgABAAoKlxRSFwBhAgAAAA==.Activase:BAAANQAECgUIBQAAAA==.',
Ad='Adrox:BAAANQADCgMIBAAAAA==.',
Ae='Aelelelos:BAAANQADCgcICgAAAA==.Aequus:BAAANQABCgUIAwAAAA==.Aestinna:BAAANQAECgMIAwAAAA==.Aevenyhm:BAABNQAECn8tAAIBAAgKfhsNHwA1AgABAAgKfhsNHwA1AgAAAA==.',
Ag='Aghorn:BAAANQAECgEIAgAAAA==.Aguyirl:BAAANQADCgEIAQAAAA==.',
Ai='Aidoneus:BAAANQAECgEIAgABNQAECgoKIwACAOsZAA==.',
Ak='Akijin:BAAANQAECgQIBQABNQAECgoKNQADAOQeAA==.Akismite:BAABNQAECn81AAIDAAoK5B5CKgC4AgADAAoK5B5CKgC4AgAAAA==.',
Al='Alaru:BAABNQAECn9AAAIEAAoK4BE7OQBXAgAEAAoK4BE7OQBXAgAAAA==.Alemental:BAAANQAECgcIEQABNQAECgkJMAACAHIaAA==.Algana:BAAANQADCggIDQABNQAECgoKNQAFAAUQAA==.Allhallows:BAABNQAECn8iAAIDAAcKsQeBFQH7AAADAAcKsQeBFQH7AAAAAA==.Alorandis:BAAANQAECgIIAgAAAA==.Alqueria:BAABNQAECn85AAMGAAoKuRrYGwAOAgAGAAkKEBzYGwAOAgADAAgKXxAZtwCwAQABNQAFFAUIEAACAPQVAA==.Altarboizyum:BAAANQAECgIIAQABNQAECgoKTwAGAKofAA==.',
An='Andanto:BAABNQAECn8aAAIHAAgKIA2jdwA7AQAHAAgKIA2jdwA7AQAAAA==.Angeliz:BAABNQAECn8iAAMBAAoKEBITHwAGAgABAAoKEBITHwAGAgAIAAUKhwltaACHAAAAAA==.Angrylabubu:BAAANQAECggICAAAAA==.Anitaloc:BAAANQAECgUIEQAAAA==.Anitapiss:BAAANQAECgUIBwAAAA==.Anneweaver:BAABNQAECn8pAAMJAAkK6h7FDwCsAQAKAAkKjBwSfACGAgAJAAgKGhvFDwCsAQABNQAFFAgIGgAKALUUAA==.Anorantha:BAABNQAECn9FAAIIAAoKaA4UKgCvAQAIAAoKaA4UKgCvAQAAAA==.Antonio:BAAANQAECgQIBwAAAA==.',
Ap='Apicots:BAAANQADCggIDwAAAA==.Apipa:BAAANQAECgYIBwAAAA==.Apricot:BAEANQADCgUIBQABNQAECgoKLQALADkQAA==.Apzz:BAAANQADCgIIAgAAAA==.',
Ar='Arendir:BAAANQAECggIAwAAAA==.Arilynn:BAAANQAECgMIAgAAAA==.Arizticat:BAAANQADCggIEgAAAA==.Arradrayn:BAAANQAECgUIBQABNQAECgYICwAMAAAAAA==.Arrowin:BAAANQAECgQIBAAAAA==.Artica:BAAANQADCggIFgAAAA==.Artrexity:BAAANQABCggIFgAAAA==.Arzan:BAAANQAECgYIDAAAAA==.',
As='Ashalan:BAABNQAECn8eAAINAAcKwQVGagD2AAANAAcKwQVGagD2AAAAAA==.Ashenflail:BAABNQAECn8YAAIGAAkKzQmDLwD/AAAGAAkKzQmDLwD/AAAAAA==.Astesia:BAAANQAECggICgAAAA==.Astrraa:BAAANQADCggIFgAAAA==.Asulo:BAAANQAECgYIBgABNQAFFAUIDAAOAAQXAA==.Asurathegrey:BAAANQADCgIIAgAAAA==.',
At='Atrejha:BAACNQAFFH8OAAIPAAUK4QhfEQC7AAAPAAUK4QhfEQC7AAA1AAQKfyQAAg8ACgq/ClM/AMEBAA8ACgq/ClM/AMEBAAAA.',
Au='Aurethas:BAAANQAECgQICgAAAA==.Aurä:BAABNQAECn8dAAIKAAkKsw5e1QDcAQAKAAkKsw5e1QDcAQABNQAECgoKJwAQAOAZAA==.Aussilio:BAAANQADCggICAAAAA==.',
Av='Avera:BAAANQAECgUIAgAAAA==.Avye:BAAANQADCgYIBwAAAA==.',
Aw='Awesome:BAAANQAECgQIBQAAAA==.',
Az='Azgkrimpatul:BAAANQADCgYICwAAAA==.Azmodeus:BAAANQADCgUIBwAAAA==.Azrina:BAABNQAECn8nAAILAAoKdBI5OAAbAgALAAoKdBI5OAAbAgAAAA==.',
Ba='Baddazz:BAAANQAECgQIBAAAAA==.Bael:BAABNQAECn8wAAIPAAoKEQ/JKADHAQAPAAoKEQ/JKADHAQAAAA==.Baidden:BAAANQADCgMIBQAAAA==.Balddh:BAAANQAECgIIAgABNQAFFAUIDwARAJgcAA==.Balddk:BAABNQAECn8dAAIHAAkKZA/SKwCIAQAHAAkKZA/SKwCIAQABNQAFFAUIDwARAJgcAA==.Baldpriest:BAAANQAECgQIBAABNQAFFAUIDwARAJgcAA==.Baldrogue:BAACNQAFFH8PAAIRAAUKmBzsBQD4AAARAAUKmBzsBQD4AAA1AAQKfzsABBEACgpTIzAEAO0CABEACgpOIzAEAO0CAAsACApwDlscAPEBABIACArtAmcQABgBAAAA.Baldwarrior:BAABNQAECn81AAIQAAoK7hw5MQB6AgAQAAoK7hw5MQB6AgAAAA==.Ballflapper:BAAANQADCgcICAABNQAECgoKIgATAKEUAA==.Bandidos:BAAANQAECgUIEQAAAA==.',
Be='Beastmans:BAAANQADCgQIBAAAAA==.Becka:BAAANQAECgYIDwAAAA==.Beckz:BAAANQADCggIDQAAAA==.Beefhambacon:BAAANQAECgUIDgAAAA==.Behealzabub:BAAANQAECggIDgAAAA==.Beladora:BAAANQADCgEIAQAAAA==.Belmatride:BAAANQAECgIIBwAAAA==.Belpepper:BAABNQAECn8mAAIDAAoKpgsgpgCCAQADAAoKpgsgpgCCAQAAAA==.Bendelmonte:BAAANQADCggIIgABNQAECgYIGQAHAFIXAA==.',
Bi='Biggum:BAAANQADCgIIAgAAAA==.Bigmez:BAABNQAECn8uAAIUAAkK4RMXEgCXAQAUAAkK4RMXEgCXAQAAAA==.Bigmoocowii:BAAANQADCgIIAgAAAA==.Bigswangindi:BAAANQADCggIEAAAAA==.Bilipmonk:BAACNQAFFH8IAAIVAAUKfAVTDgCUAAAVAAUKfAVTDgCUAAA1AAQKfywAAhUACgrHGLAiABMCABUACgrHGLAiABMCAAAA.Bindinglight:BAACNQAFFH8JAAMIAAMKYgSDIgB/AAAIAAIKYgSDIgB/AAABAAIKdQNsFABZAAA1AAQKf3AAAwEACgqkGDcZAHICAAEACgqkGDcZAHICAAgACQrFErA0AEMCAAAA.Birdofhermes:BAAANQADCgMIAwAAAA==.Bizzthewizz:BAAANQADCgQIBAAAAA==.Biñx:BAAANQABCgQICQAAAA==.',
Bl='Blarr:BAABNQAECn8bAAIDAAgKHxPYuQCqAQADAAgKHxPYuQCqAQAAAA==.Blindehunter:BAAANQADCgIIAgABNQADCgIIAgAMAAAAAA==.Blindvoid:BAAANQAECgIIAgABNQADCgIIAgAMAAAAAA==.Bloodguard:BAAANQADCgYIBgAAAA==.Blubinax:BAAANQADCgQIBAAAAA==.Bluedabodeba:BAAANQADCgEIAQAAAA==.Bluejeanz:BAAANQADCgYIBQABNQAECgoKMwAIAMMhAA==.',
Bo='Boonkay:BAAANQADCgEIAQAAAA==.Boonkie:BAAANQAECggICQAAAA==.Boonksdragon:BAAANQAECggIEAAAAA==.Boonlock:BAAANQAECggIAwAAAA==.Bowmasterbo:BAAANQAECgcICQABNQAECgkJMAACAHIaAA==.Boxbeater:BAAANQADCgYIBgAAAA==.',
Br='Braedravia:BAAANQAECgUIBwAAAA==.Bretikus:BAAANQAECgYIBgAAAA==.Brilok:BAAANQAECgYICgAAAA==.Brisanna:BAABNQAECn8bAAIDAAcKFArM+QArAQADAAcKFArM+QArAQAAAA==.Bruleecreme:BAABNQAECn8hAAIWAAoKjBMkMwBSAgAWAAoKjBMkMwBSAgAAAA==.',
Bu='Bubos:BAAANQADCgIJAgAAAA==.Budgeroo:BAAANQAECgUIBAAAAA==.',
['Bà']='Bàwlz:BAEBNQAECn8kAAQXAAkKqBdWMgCCAQAXAAkKqBdWMgCCAQANAAQKGASphgCbAAAHAAMKvAb/fwBBAAAAAA==.',
['Bè']='Bèérsërk:BAAANQADCgEIAQAAAA==.',
['Bö']='Böðull:BAAANQAECgUICgAAAA==.',
Ca='Cadarion:BAAANQABCgIIAgAAAA==.Caelix:BAAANQADCgQIBQAAAA==.Calamari:BAEANQADCggICAABNQAECgoKLQALADkQAA==.Caledor:BAABNQAECn8vAAIDAAoKZw7KnADpAQADAAoKZw7KnADpAQAAAA==.Calkhan:BAAANQADCgMIAwAAAA==.Camitriel:BAABNQAECn+yAQQCAAkKxyZ8BQClAwACAAkKxyZ8BQClAwAYAAUKBCWlGACnAQAFAAEK+x8zKABIAAAAAA==.Cascadea:BAAANQAECggICAAAAA==.Cataleya:BAAANQAECggIAgAAAA==.Cawa:BAAANQADCggIDwAAAA==.',
Ce='Ceaserianoma:BAAANQADCgMIAwAAAA==.',
Ch='Chadder:BAAANQAECggIEgAAAA==.Chairlegs:BAABNQAECn8jAAIEAAkKNB6gFwAZAwAEAAkKNB6gFwAZAwAAAA==.Charliie:BAABNQAECn9RAAMUAAoKlyNjAgAwAwAUAAoKlyNjAgAwAwAQAAYKog3urAAgAQAAAA==.Chaunakoala:BAAANQADCgIIAgAAAA==.Cherryfudge:BAAANQADCggIDQAAAA==.Chipinwing:BAAANQAECgEIAQAAAA==.Chronicshot:BAAANQAECgQIBQAAAA==.Chunkysoupz:BAAANQADCgYIBgAAAA==.',
Cl='Classyshammy:BAAANQADCggIDAAAAA==.Clockworks:BAAANQAECgMIAgAAAA==.Clouxdyskies:BAAANQADCgEIAQAAAA==.',
Co='Cocinegr:BAABNQAECn8jAAICAAgKVw1mrgB0AQACAAgKVw1mrgB0AQABNQAFFAUIEQAKAJEUAA==.Cocinegrø:BAABNQAECn8YAAMZAAkKjhIcLwAaAQAZAAcKIBAcLwAaAQAaAAYKcg+8JQDUAAABNQAFFAUIEQAKAJEUAA==.Cokuzo:BAAANQAECgQICgAAAA==.Coneja:BAABNQAECn9JAAIKAAoKEQ2fmAB0AQAKAAoKEQ2fmAB0AQAAAA==.Coolbroguy:BAAANQABCgQIBAAAAA==.Coomspit:BAAANQAECgIIAgAAAA==.Corwa:BAAANQAECgEIAQABNQAFFAUIBwADAF4QAA==.Cowtastrophe:BAAANQABCgcIEAAAAA==.',
Cr='Craeftig:BAAANQAECgYIDQABNQAECgoKKAAJACUgAA==.Craiso:BAABNQAECn8cAAIbAAgKeyG9CACdAgAbAAgKeyG9CACdAgAAAA==.Crankinhawg:BAABNQAECn8VAAIKAAgKTiAkgQB8AgAKAAgKTiAkgQB8AgAAAA==.Crazbezzul:BAAANQADCgUIBwAAAA==.Creationz:BAAANQADCgYICQABNQAECgEIAQAMAAAAAA==.Crisarrow:BAAANQADCggIGAAAAA==.',
Cu='Current:BAABNQAECn8fAAIPAAgKKAeNTAD2AAAPAAgKKAeNTAD2AAAAAA==.',
Cy='Cynesh:BAACNQAFFH8bAAMTAAgK8Rv2AwAfAgATAAcKdR32AwAfAgAcAAUKSRXCDAByAQA1AAQKfywAAxMACgrSJiUDAHsDABMACgrSJiUDAHsDABwABwqvIJkpAP4BAAAA.Cytl:BAAANQAECgYICwAAAA==.',
Da='Dailybuilt:BAAANQADCgQICgAAAA==.Damitbobbi:BAAANQADCgUIBQAAAA==.Dangybangy:BAABNQAECn8hAAITAAoK3Q/9mADVAQATAAoK3Q/9mADVAQAAAA==.Danjaianka:BAAANQAECgQIBAAAAA==.Darkken:BAAANQADCgYJBgABNQAECgMIAgAMAAAAAA==.Darkkragmur:BAAANQAECgUICAAAAA==.Darklunche:BAAANQADCgUIBQAAAA==.Darknest:BAAANQADCgQIBgAAAA==.Darthimus:BAAANQAECgIIAwAAAA==.Darthmalgus:BAAANQADCgcICgAAAA==.Datbishkarma:BAABNQAECn8xAAMKAAkKCAm2kwB+AQAKAAkKRwi2kwB+AQAJAAIKlgcJMwBfAAAAAA==.Dawnbreaker:BAAANQADCgYIBgAAAA==.',
Dd='Dding:BAACNQAFFH8KAAIGAAQKgyK2BAASAQAGAAQKgyK2BAASAQA1AAQKfzcAAwYACgqfJXcGAEIDAAYACQqGJXcGAEIDAAMAAwqvE2paAXAAAAAA.',
De='Deadbarcy:BAAANQAECgIJAgAAAA==.Deathklok:BAABNQAECn8zAAMdAAoKSRW1UwAYAgAdAAoKSRW1UwAYAgAeAAgK4QlQHwAvAQAAAA==.Deathran:BAABNQAECn8nAAICAAoKCBepWwBEAgACAAoKCBepWwBEAgAAAA==.Deezgrips:BAABNQAECn8kAAIXAAgKvxq5JgCIAgAXAAgKvxq5JgCIAgAAAA==.Deffgwip:BAABNQAECn8dAAIHAAoKqgt7KgCRAQAHAAoKqgt7KgCRAQAAAA==.Delfine:BAAANQADCggIHQAAAA==.Demonikiarly:BAAANQADCgUIBQABNQAECgoKLQAaAJwhAA==.Despott:BAABNQAECn8mAAIKAAoKQxMrYQD0AQAKAAoKQxMrYQD0AQABNQAFFAUIDwARAJgcAA==.Destina:BAAANQAECggIDwAAAA==.Dethfox:BAABNQAECn8ZAAIHAAYKUheIaABvAQAHAAYKUheIaABvAQAAAA==.Dethlock:BAAANQADCgQIBAAAAA==.',
Di='Dioni:BAABNQAECn84AAMdAAoKdyLlEgAhAwAdAAoKdyLlEgAhAwAfAAYKgArwsAAxAQABNQAFFAQIDAABAJITAA==.Dirknasty:BAAANQAECgUIBwAAAA==.Diyfootjobs:BAAANQADCgYJGgAAAA==.',
Dk='Dkurther:BAABNQAECn8hAAIXAAkKUAVjTgAEAQAXAAkKUAVjTgAEAQAAAA==.Dkxs:BAAANQADCgEIAQAAAA==.',
Do='Doggybag:BAAANQADCgQIBAAAAA==.Doomhauerr:BAAANQAECggICgAAAA==.Dottonohana:BAAANQAECgQIBAAAAA==.Doublehelix:BAAANQAECgcIDQAAAA==.Dovish:BAAANQAECgcIDAAAAA==.',
Dr='Drackygacky:BAAANQAECgYIBwAAAA==.Dracw:BAAANQAECgcIEwAAAA==.Draglox:BAAANQAECgcICAAAAA==.Drakaryss:BAAANQADCgEIAQABNQAECgoKNAAgAAwjAA==.Drama:BAAANQAECgEIAQAAAA==.Drashar:BAAANQADCgUIBQAAAA==.Dravenm:BAABNQAECn86AAIKAAkKWg5ghwCZAQAKAAkKWg5ghwCZAQAAAA==.Drawven:BAAANQAECgYIEAABNQAECgkJOgAKAFoOAA==.Draz:BAAANQAECgMIBQAAAA==.Dreadblossom:BAAANQADCggICAAAAA==.Driney:BAEBNQAECn8fAAQWAAoKiiFfEgApAwAWAAoKiiFfEgApAwAGAAIKCRnGYwBQAAADAAEK8BblggFDAAABNQAECggIGAAdAC4kAA==.Droozh:BAAANQAECgEIAQAAAA==.Drunkendrago:BAAANQADCggIEwAAAA==.',
Du='Duesenjaeger:BAAANQADCgcICwAAAA==.Duko:BAAANQADCgEIAQAAAA==.',
['Dè']='Dèmonic:BAABNQAECn8jAAICAAoK6xnuRwD8AQACAAoK6xnuRwD8AQAAAA==.',
['Dé']='Désy:BAAANQAECgMIAwAAAA==.',
['Dø']='Døric:BAAANQADCgcJDAAAAA==.',
['Dü']='Dürinn:BAAANQADCgIIAgAAAA==.',
Eh='Ehud:BAABNQAECn9cAAIDAAoK5CS/CABWAwADAAoK5CS/CABWAwAAAA==.',
Ei='Eisiss:BAAANQABCgEIAQAAAA==.',
El='Elabrate:BAAANQADCgMIAwAAAA==.Elade:BAAANQADCgUIBQAAAA==.Elbori:BAABNQAECn9DAAIhAAoKqB/OAADaAgAhAAoKqB/OAADaAgAAAA==.Elbryan:BAAANQADCgMIAwAAAA==.Eldaral:BAAANQAECggIBAAAAA==.Elementium:BAAANQAECggIEQAAAA==.Elfmas:BAAANQAECgYICQAAAA==.Ellinarilia:BAAANQADCgEIAQAAAA==.Elorees:BAAANQADCgYIBgAAAA==.Elviswong:BAAANQADCgIIAgAAAA==.Elyyin:BAEANQAECggICgABNQAFFAcIEAANAKkUAA==.',
Em='Emerhy:BAAANQAECgEJAQAAAA==.',
Er='Erinrbb:BAAANQADCgYIBgABNQAECgIIBAAMAAAAAA==.',
Es='Escänor:BAABNQAECn8kAAMDAAkKmh/WJAAyAwADAAkKmh/WJAAyAwAGAAIKfwngZgBHAAAAAA==.Eshaia:BAAANQADCgEIAQAAAA==.Essemdee:BAAANQAECgQICwAAAA==.Essiee:BAAANQAECgQIBAAAAA==.',
Ey='Eyewyn:BAAANQABCgYIBQAAAA==.Eylos:BAAANQAECgEIAQAAAA==.',
Fa='Faesmite:BAAANQADCgUIBQAAAA==.Faithflop:BAAANQAECgYIEAAAAA==.Falleh:BAAANQADCgIIAgAAAA==.Fanorage:BAAANQAECgIIAgAAAA==.',
Fe='Felixox:BAAANQAECgEIAQAAAA==.Ferocias:BAAANQAECgQJBQAAAA==.Ferraxx:BAAANQADCgcIBwAAAA==.Fewture:BAAANQADCgUIBQAAAA==.Feykill:BAAANQAECgQIBAAAAA==.',
Fi='Fiametta:BAAANQADCggICAAAAA==.Fishbreath:BAAANQAECgEIAQAAAA==.',
Fl='Flaffergan:BAAANQAECgYIEwAAAA==.Flastage:BAAANQAECgUIBAAAAA==.Flexhack:BAABNQAECn8/AAILAAkK+gxiVQCwAQALAAkK+gxiVQCwAQAAAA==.Flurrychonk:BAAANQADCgYIBgABNQAECgkJMAACAHIaAA==.Flåsh:BAABNQAECn8fAAMWAAgK8SDtNACQAgAWAAcK+SDtNACQAgADAAcK9BXPlwD0AQAAAA==.',
Fo='Focinnet:BAABNQAECn8oAAITAAgKVwq8igD1AQATAAgKVwq8igD1AQAAAA==.Forandra:BAAANQAECgMIAgAAAA==.Fortyacres:BAAANQADCgEIAQAAAA==.Fortybmh:BAAANQADCgEIAQABNQADCgEIAQAMAAAAAA==.Four:BAAANQAECgQIBAAAAA==.Fourform:BAAANQADCgIIAgAAAA==.',
Fr='Frianna:BAAANQAECgMIAwAAAA==.Frieren:BAABNQAECn8VAAIJAAoKJAznEgBfAQAJAAoKJAznEgBfAQAAAA==.',
Fu='Fuzzbutt:BAAANQADCgEIAQAAAA==.',
Ga='Gaalit:BAAANQADCgcIBwAAAA==.Galaxybone:BAAANQADCgQIBAAAAA==.Galiar:BAAANQAECgcIBwAAAA==.Galithiri:BAAANQAECggIEQAAAA==.Ganthani:BAABNQAECn8gAAIEAAcKNhAZhgCEAQAEAAcKNhAZhgCEAQAAAA==.Garzett:BAABNQAECn9fAAIIAAoKJhsVGABQAgAIAAoKJhsVGABQAgAAAA==.Gatortooth:BAAANQABCgIIBAAAAA==.Gaybeowners:BAAANQAECgEIAQAAAA==.',
Ge='Geigh:BAAANQADCgUIBQAAAA==.Gethellar:BAABNQAECn8iAAMTAAoKoRQMdQDVAQATAAoKoRQMdQDVAQAcAAEKqgP5nAAiAAAAAA==.',
Gh='Ghostdaliar:BAAANQADCgQIBgAAAA==.Ghouliana:BAAANQADCgUIBQABNQAECgIIAgAMAAAAAA==.',
Gl='Glizyglober:BAAANQADCgMIAwABNQAFFAMICQAIAGIEAA==.Glizzrizzler:BAAANQAECgcICgABNQAFFAMICQAIAGIEAA==.Glizzyrizily:BAAANQADCgMIAwABNQAFFAMICQAIAGIEAA==.Glizzyys:BAABNQAECn8yAAIQAAkKGg1IlwBRAQAQAAkKGg1IlwBRAQABNQAFFAMICQAIAGIEAA==.Gllizzard:BAAANQADCgMIAwAAAA==.Gluckglucks:BAAANQABCgQIBAAAAA==.',
Go='Goblikon:BAAANQAECgMIAwABNQAECgcIEgAMAAAAAA==.Gore:BAABNQAECn8mAAQNAAoKuAo3VABFAQANAAoKuAo3VABFAQAHAAMKwQFHzQBSAAAXAAEKAAAPxABAAAAAAA==.Gorrock:BAAANQAECgQIBAAAAA==.',
Gr='Gravtech:BAAANQADCggIDgABNQAECgoKFwARAGkQAA==.Greenlinaii:BAAANQAECgQIBAAAAA==.Greffin:BAAANQAECgEIAQAAAA==.Grenzo:BAAANQAECgEIAgAAAA==.Grhm:BAAANQAECgcIBwAAAA==.Grim:BAABNQAECn8jAAMHAAoKESRDFwACAwAHAAoKCiRDFwACAwANAAMKyiIdZgAJAQABNQAFFAkJEwAaAHYZAA==.Grimheart:BAAANQAECgEIAQAAAA==.Grinshankz:BAAANQADCgYIBgAAAA==.Grundles:BAAANQADCggICAAAAA==.Grymnir:BAABNQAECn81AAMeAAoKCA/HEgDqAQAeAAkK5AzHEgDqAQAfAAgKWwu+jQCCAQAAAA==.',
Gu='Guilliman:BAABNQAECn8hAAIDAAoKwR39KgC1AgADAAoKwR39KgC1AgAAAA==.Gumsy:BAABNQAECn9AAAMQAAoKTBloMwBxAgAQAAoKvRhoMwBxAgAUAAUKWxh1KAC6AAABNQAECgoKQwAHAC4ZAA==.',
Gw='Gwory:BAABNQAECn8ZAAMOAAgKuRPqEQBaAQAOAAgKTBPqEQBaAQAQAAMKvRAw/wB2AAAAAA==.',
['Gø']='Gørë:BAABNQAECn8tAAMCAAoKIhDXWADKAQACAAoKIhDXWADKAQAYAAMKHg+VJABjAAAAAA==.',
Ha='Haddassah:BAAANQAECgQIBAAAAA==.Haramzadi:BAAANQADCgQICQAAAA==.Haranue:BAABNQAECn8nAAITAAcKfQgxywAcAQATAAcKfQgxywAcAQAAAA==.Harryporter:BAAANQAECgEIAQAAAA==.Harukà:BAAANQAECgUIDAAAAA==.Hatxo:BAAANQADCgYICgABNQAECgkJJAAeAKkcAA==.Havvik:BAAANQAECgIIAgAAAA==.',
He='Healscat:BAAANQADCgUJBQAAAA==.Healsdog:BAAANQAECgEIAQAAAA==.Hefferd:BAAANQADCgQIBAAAAA==.Helfon:BAABNQAECn8tAAIPAAoKyB+aFAD4AgAPAAoKyB+aFAD4AgAAAA==.Helgadknight:BAAANQAECgMIAwAAAA==.Helgafrode:BAAANQABCgQIBgAAAA==.Helganelf:BAAANQAECgIIBAAAAA==.Helgaork:BAAANQAECgMIAgAAAA==.Helices:BAABNQAECn84AAQXAAoK7htQGwAkAgAXAAoK7BtQGwAkAgAHAAkK8QyULACDAQANAAUK6wyuXAAkAQAAAA==.Hellenria:BAAANQADCgMIAwAAAA==.Herm:BAAANQAECgEIAQAAAA==.',
Hi='Highlordt:BAABNQAECn80AAQiAAkK4RoHGADnAQAiAAkK4RoHGADnAQAEAAgK8BU/cwDCAQAjAAEKrwd3LgAoAAAAAA==.Highlordtron:BAABNQAECn8kAAQCAAkK8hV8fADvAQACAAkK2BR8fADvAQAYAAEKohKlcQA9AAAFAAEKCwfULQA7AAAAAA==.Hinazuki:BAAANQAECgUIAwAAAA==.Hinoxfine:BAAANQADCgMIBAAAAA==.Hitatchi:BAAANQADCgEIAQAAAA==.',
Ho='Holybeast:BAAANQADCgIIAgAAAA==.Holycharge:BAAANQAECgIIAgAAAA==.Holycrab:BAAANQAECgEIAQAAAA==.Holydudy:BAAANQAECgEIAQAAAA==.Holyely:BAABNQAECn8rAAIDAAkK5ROHewDWAQADAAkK5ROHewDWAQAAAA==.Holyfae:BAABNQAECn8tAAMWAAoKNBXEQABiAgAWAAoKNBXEQABiAgADAAQKbQbPPQG9AAAAAA==.Holygrom:BAABNQAECn8qAAIDAAkKOyWpBwC9AwADAAkKOyWpBwC9AwAAAA==.Holylove:BAAANQADCgUIDAABNQAECgIIBAAMAAAAAA==.Holynutzz:BAAANQAECgMIAwAAAA==.Holyrager:BAABNQAECn8XAAMGAAUKlxp1JwA1AQAGAAQKJiN1JwA1AQADAAUKaAyuPQG9AAAAAA==.Holysplash:BAABNQAECn8hAAIEAAkKLRG4cQDIAQAEAAkKLRG4cQDIAQAAAA==.Holyvoids:BAAANQADCgIIAgAAAA==.Hondodk:BAECNQAFFH8YAAMHAAYKLiXhAAByAgAHAAYKLiXhAAByAgAXAAEKAAD4LAAAAAA1AAQKf1cAAwcACgrIJk0BAHkDAAcACgrIJk0BAHkDABcAAQrDJr+uAG4AAAE1AAUUCAgVAAcAgCQA.Honeyshamwow:BAAANQAECgYIBAAAAA==.Hoodadin:BAAANQABCgMIAwAAAA==.Hoodlummon:BAAANQADCggJHQAAAA==.Hopesfall:BAAANQAECgIJAwAAAA==.Howzitcuz:BAAANQADCgcIJAABNQAECgoKKAAWAA4aAA==.Hozari:BAABNQAECn8zAAIIAAoKihbLIwCyAgAIAAoKihbLIwCyAgAAAA==.',
Ht='Ht:BAAANQADCgcIDAAAAA==.',
Hu='Hunterstickg:BAAANQADCgUIBQAAAA==.',
['Hã']='Hãvøc:BAAANQADCgIIAgAAAA==.',
Ia='Ianil:BAAANQAECgYICwAAAA==.',
Ic='Iccyhot:BAAANQADCgMIAwABNQAFFAMICQAIAGIEAA==.',
Ii='Iimrbrownii:BAAANQADCgIIAgAAAA==.Iiwhiskey:BAAANQADCgcICAAAAA==.',
Il='Ilirranna:BAAANQAECgMIBAAAAA==.',
In='Infi:BAACNQAFFH8dAAMcAAgKwSJeAwBZAgAcAAgKGx1eAwBZAgATAAEKLyXsLQBnAAA1AAQKf0gAAxwACgo0JVkBANwDABwACgo0JVkBANwDABMAAQrZJn86AXAAAAAA.Initabath:BAABNQAECn8iAAMBAAoKDQbuQgD7AAABAAoKDQbuQgD7AAAIAAYKzwWIcQBsAAAAAA==.Initapoop:BAABNQAECn8dAAIDAAUKGAWlUQGeAAADAAUKGAWlUQGeAAAAAA==.Inosukè:BAABNQAECn80AAIgAAoKDCPaAQCsAwAgAAoKDCPaAQCsAwAAAA==.Inse:BAAANQAECgQIAwAAAA==.Invisibro:BAABNQAECn8XAAMRAAoKaRAuOAD2AQARAAoKwQ8uOAD2AQALAAIKMAztzgBMAAAAAA==.',
Io='Ioannis:BAABNQAECn8eAAIDAAgKhxG/vQBXAQADAAgKhxG/vQBXAQAAAA==.',
Ip='Ipse:BAAANQADCgMIAwAAAA==.',
Ir='Irasenme:BAAANQAECgIIAgAAAA==.',
Is='Isos:BAABNQAECn9HAAQEAAoK/yLnDgBOAwAEAAoK/yLnDgBOAwAiAAIKyBMPSQCGAAAjAAEKCBC0KAAzAAAAAA==.Isus:BAAANQADCgYJBgABNQAECgoKRwAEAP8iAA==.',
Iy='Iykyk:BAAANQAECgIIAgABNQAECgoKKAAWAA4aAA==.',
Ja='Jadeadly:BAAANQAECggIDwAAAA==.Jaded:BAACNQAFFH8FAAIVAAIK4gTcEABlAAAVAAIK4gTcEABlAAA1AAQKf0AAAhUACgr/HG4LAKkCABUACgr/HG4LAKkCAAAA.Jakerbonk:BAAANQADCgYIBwAAAA==.Jakersai:BAABNQAECn8bAAISAAkKCA/dCwChAQASAAkKCA/dCwChAQAAAA==.Jakersaint:BAAANQADCggIDAAAAA==.Jamae:BAAANQAECgQIAwAAAA==.Javyr:BAABNQAECn8tAAITAAoKChwsOQBoAgATAAoKChwsOQBoAgAAAA==.Jayfmtv:BAAANQAECgMIBAAAAA==.Jaysdruid:BAAANQAECgQIBAAAAA==.',
Je='Jeetz:BAAANQAECgYIDwAAAA==.Jessicax:BAAANQAECgQIBAAAAA==.Jetpackcat:BAAANQADCgIIAgAAAA==.',
Ji='Jio:BAAANQAECgQIBAAAAA==.',
Jl='Jlnxed:BAAANQAECggIAwAAAA==.Jlnxy:BAABNQAECn8bAAIDAAoKBwoYugCpAQADAAoKBwoYugCpAQAAAA==.',
Jo='Joania:BAAANQADCggICAAAAA==.Jonoa:BAAANQADCgUIBQAAAA==.',
Ju='Judgmentalaf:BAAANQADCggIFwAAAA==.Judo:BAAANQAECgMIBQAAAA==.',
Ka='Kadre:BAABNQAECn8eAAIUAAgKgQOyKgDjAAAUAAgKgQOyKgDjAAAAAA==.Kadzilak:BAAANQADCgQIBgAAAA==.Kagemika:BAAANQAECgQIBAABNQAFFAUIDgAPAOEIAA==.Kaiola:BAAANQAECgMIAgAAAA==.Kaizumie:BAAANQAECgIIAgAAAA==.Kalirti:BAAANQADCgIIAgAAAA==.Kamistri:BAABNQAECn81AAQEAAoKESBkHwDyAgAEAAoKESBkHwDyAgAiAAMKHw/8YQB5AAAjAAIKrAZkIwBOAAAAAA==.Kanaa:BAAANQAECgQIBwAAAA==.Kanatre:BAAANQADCgEIAQAAAA==.Kandicee:BAAANQAECgIIAgAAAA==.Karensmith:BAAANQADCgcIBwAAAA==.Karessandra:BAAANQADCgQIBAABNQAECggIEQAMAAAAAA==.Karrison:BAAANQADCgMIBAAAAA==.Kathea:BAAANQAECgQIBAAAAA==.Kayarra:BAAANQADCgEIAgABNQADCgQIBAAMAAAAAA==.Kaynarra:BAAANQADCgQIBAAAAA==.Kayonna:BAAANQABCgEIAQABNQADCgQIBAAMAAAAAA==.',
Ke='Keastral:BAAANQAECgQICgAAAA==.Keeynai:BAAANQADCgQIBAAAAA==.Keldanis:BAABNQAECn9DAAITAAoKmRyqJACsAgATAAoKmRyqJACsAgAAAA==.Kelestrah:BAAANQADCgQJBAAAAA==.Kelterrager:BAAANQADCgMIAwAAAA==.Keony:BAABNQAECn8oAAIWAAoKDhrdLwBiAgAWAAoKDhrdLwBiAgAAAA==.Kerthur:BAAANQAECggICQAAAA==.',
Ki='Kickpigeons:BAAANQADCgEIAQAAAA==.Kiernaan:BAEBNQAECn8bAAQXAAoK2wz9QgAxAQAXAAUKDRT9QgAxAQANAAoKrwEalQB0AAAHAAEKiAHomQAaAAABNQAFFAcIEAANAKkUAA==.Killertcells:BAABNQAECn8cAAINAAoKdhl7GQB9AgANAAoKdhl7GQB9AgAAAA==.Kilv:BAAANQAECgIIAgABNQAFFAgIIwACAJ4cAA==.Kirgrand:BAAANQADCgMIAwAAAA==.Kittyarly:BAABNQAECn8tAAIaAAoKnCF6AwAJAwAaAAoKnCF6AwAJAwAAAA==.Kiwi:BAEANQADCggICAABNQAECgoKLQALADkQAA==.',
Kl='Klarakai:BAAANQAECgYIBgAAAA==.',
Ko='Kodeck:BAAANQADCggIGQAAAA==.Kodokan:BAAANQAECgEIAQAAAA==.Koshima:BAABNQAECn8zAAIfAAoK6BheNwCZAgAfAAoK6BheNwCZAgAAAA==.Kozan:BAAANQADCgUICAAAAA==.',
Kr='Krimdan:BAAANQADCgQIBAAAAA==.Krimhit:BAAANQADCgUICwAAAA==.Krimrok:BAAANQABCgIIAgAAAA==.Krimwarr:BAAANQADCgQIBAAAAA==.',
Ku='Kudou:BAAANQADCgMIAwAAAA==.Kudranne:BAAANQAECggIDAABNQAECggIEQAMAAAAAA==.Kugia:BAACNQAFFH8MAAIBAAQKkhM+CgAdAQABAAQKkhM+CgAdAQA1AAQKf0EAAgEACgq7IncGAHwDAAEACgq7IncGAHwDAAAA.Kumokiri:BAAANQADCgMIAwAAAA==.',
Ky='Kylex:BAAANQAECgEIAQAAAA==.Kynndell:BAAANQADCggIGQAAAA==.Kyo:BAAANQADCgYIDgAAAA==.',
['Kø']='Køkushibø:BAAANQABCgUIBQAAAA==.',
La='Laments:BAAANQADCgUIBQAAAA==.Lammb:BAAANQADCgUIBQAAAA==.Lanfeariel:BAAANQAECgEIAQAAAA==.Latak:BAAANQADCgMIAwAAAA==.Latir:BAAANQADCgUIBwAAAA==.Lazylox:BAAANQAECgEIAQAAAA==.Lazyryx:BAAANQADCgUIBQAAAA==.',
Le='Leetheal:BAACNQAFFH8UAAMEAAYKkwu9FQBYAQAEAAYKkwu9FQBYAQAiAAMKVhPnDQD1AAA1AAQKfz8AAwQACgpzGz8qAKICAAQACgpzGz8qAKICACIACAqcHn4SADMCAAAA.Leethul:BAABNQAECn9TAAICAAoK4xtYHwCXAgACAAoK4xtYHwCXAgAAAA==.Lelethxx:BAAANQAECgIIBAAAAA==.Lesanna:BAABNQAECn9QAAIPAAoK0gymLgCgAQAPAAoK0gymLgCgAQAAAA==.Lestharia:BAAANQAECgUIBQAAAA==.Leysmith:BAABNQAECn9MAAIDAAoK1BMCnQDoAQADAAoK1BMCnQDoAQAAAA==.',
Li='Lifestream:BAAANQAECgIIAgAAAA==.Lightnings:BAAANQAECgUIBAAAAA==.Lilheal:BAAANQAECgIJAgAAAA==.Lilium:BAAANQADCgYICwAAAA==.Lionël:BAABNQAECn8qAAIWAAkKgyFPDQBbAwAWAAkKgyFPDQBbAwAAAA==.Lisax:BAAANQAECgEIAQAAAA==.Lizbethe:BAABNQAECn8pAAQYAAoK9RxqBwCPAgAYAAcK4CBqBwCPAgACAAcK7xrWiADQAQAFAAcK3BtOEgASAQAAAA==.',
Lo='Loadedtotem:BAAANQAECgMIAwAAAA==.Lockmclovin:BAAANQADCgMIAwAAAA==.Loltank:BAAANQAECgcIEQAAAA==.Lomrgreenol:BAAANQADCgQIBAAAAA==.Lopi:BAAANQAECgQIAwAAAA==.Lorast:BAAANQAECgEIAQAAAA==.Lorwater:BAAANQADCgQIBAAAAA==.Loveinfinity:BAAANQABCgIIAgAAAA==.',
Lp='Lp:BAAANQADCgYICAAAAA==.',
Lt='Lt:BAAANQAECgIIAgAAAA==.',
Lu='Lumibell:BAAANQABCgYIBwAAAA==.Luminate:BAAANQADCgQIBAAAAA==.Lunaru:BAAANQAECgQICQAAAA==.Lunaryon:BAAANQADCgUICgAAAA==.',
Ma='Madamgypsy:BAABNQAECn8VAAIIAAUKXgflYwCWAAAIAAUKXgflYwCWAAAAAA==.Madamlilith:BAAANQAECgcIDQAAAA==.Madderco:BAAANQAECggICAAAAA==.Madivh:BAAANQADCgQIBAAAAA==.Magaspy:BAABNQAECn8iAAIEAAcKQBUweABxAQAEAAcKQBUweABxAQAAAA==.Magerage:BAAANQAECgEIAQAAAA==.Magerassfoo:BAAANQAECgcIDAAAAA==.Magiccairne:BAABNQAECn8jAAIKAAgKVAeWngBnAQAKAAgKVAeWngBnAQAAAA==.Magikiarly:BAAANQAECgUICwABNQAECgoKLQAaAJwhAA==.Magnar:BAAANQAECgUICgABNQAECgkJMAACAHIaAA==.Mahoogany:BAAANQADCgYIDAAAAA==.Malson:BAAANQAECgUIAwAAAA==.Mamimage:BAACNQAFFH8RAAIKAAUKkRRPJgDfAAAKAAUKkRRPJgDfAAA1AAQKf08AAgoACgonJGUVAPQCAAoACgonJGUVAPQCAAAA.Marrik:BAAANQADCgMIAwAAAA==.Marukka:BAAANQADCgQIBAABNQADCgcIBwAMAAAAAA==.Matry:BAAANQAECgQIBQAAAA==.Matty:BAAANQADCgEIAQAAAA==.Mayiana:BAAANQAECgUICgAAAA==.',
Mc='Mcspanky:BAAANQAECggICgAAAA==.',
Me='Meadowlark:BAAANQAECgYICAAAAA==.Mefistofeles:BAAANQAECgQICwAAAA==.Mellie:BAAANQADCgQIBQAAAA==.Meowstic:BAABNQAECn8rAAMZAAoK5xsJBwAaAwAZAAgKoSIJBwAaAwAIAAIKuAfKfABPAAABNQAECgIIAgAMAAAAAA==.Mercurious:BAABNQAECn8kAAMdAAgKNCGSGADyAgAdAAgKNCGSGADyAgAfAAUKSgxBvQCPAAAAAA==.Metalrules:BAAANQABCggICAAAAA==.Methypheni:BAABNQAECn8YAAMIAAcK+hxhXgBXAQAIAAYKZBhhXgBXAQAaAAQK3hZzMQCLAAAAAA==.',
Mi='Mikun:BAAANQAECgQIBgAAAA==.Milkytheman:BAAANQABCgMIAgAAAA==.Mill:BAAANQADCgYICgAAAA==.Minidash:BAAANQAECgUIBgAAAA==.Minimuff:BAAANQAECgIIAgAAAA==.Mintl:BAAANQADCgYIBQAAAA==.Mirajanna:BAABNQAECn9PAAMkAAoKlxkpBwAhAgAkAAoKlxkpBwAhAgAlAAcKqAZONwDiAAAAAA==.Missmouthoff:BAABNQAECn9JAAIEAAoKWxSqSwBCAgAEAAoKWxSqSwBCAgAAAA==.Mitenâ:BAAANQADCgUIBgAAAA==.Mizzxgummy:BAAANQAECgcICAAAAA==.',
Mo='Momster:BAAANQADCggIFgAAAA==.Monkin:BAAANQAECgEIAQAAAA==.Moogan:BAAANQAECgUIDAAAAA==.Mookins:BAAANQAECgYIEgAAAA==.Moonfishing:BAABNQAECn8nAAIKAAoKkhbCeACMAgAKAAoKkhbCeACMAgAAAA==.Moonfly:BAACNQAFFH8RAAIIAAgKPhSRDgCAAQAIAAgKPhSRDgCAAQA1AAQKf0QAAggACgohJeICAGMDAAgACgohJeICAGMDAAAA.Morax:BAABNQAECn8aAAMCAAcKNwx/7wDrAAACAAYKMwx/7wDrAAAFAAEKSQzlLgA4AAAAAA==.Morbidlord:BAAANQABCgYIEQAAAA==.Moscacrazy:BAAANQAECgEIAQAAAA==.Mourne:BAABNQAECn9AAAMRAAoKWhpkHwCFAgARAAoK2BhkHwCFAgALAAoKlhR6MAA7AgAAAA==.',
Ms='Mssmalvile:BAAANQAECgEIAQAAAA==.',
My='Myrrvain:BAAANQAECgEIAQAAAA==.Mythara:BAAANQADCgYIBgAAAA==.',
Na='Naarcissus:BAAANQABCgIIAgAAAA==.Nagrim:BAAANQAECgEIAQABNQAECgoKQwAHAC4ZAA==.Nalaana:BAAANQAECgUIEwAAAA==.Nalariel:BAABNQAECn8hAAMHAAkKgiAiKwCJAgAHAAkKgiAiKwCJAgAXAAEKeRpXvQBNAAAAAA==.Nallaana:BAABNQAECn8aAAIiAAoKqBPkEwAeAgAiAAoKqBPkEwAeAgAAAA==.Nalmagedan:BAABNQAECn8+AAIKAAoKoRKZVQASAgAKAAoKoRKZVQASAgAAAA==.Nammi:BAAANQADCgMIAwAAAA==.Nandorr:BAAANQADCgIIAwAAAA==.Nardalem:BAAANQADCgcIBwAAAA==.Nardorne:BAAANQADCgMIAwAAAA==.Narec:BAAANQADCgUIBQAAAA==.Narfhound:BAAANQADCgYICAAAAA==.Nazgrok:BAABNQAECn8wAAICAAkKchq8LwBQAgACAAkKchq8LwBQAgAAAA==.',
Ne='Nearhammer:BAAANQAECggICQAAAA==.Nearsear:BAAANQADCgcIBwAAAA==.Nefariouz:BAAANQAECggIDwAAAA==.Nervouz:BAABNQAECn8uAAIPAAoKJxPyKwBDAgAPAAoKJxPyKwBDAgAAAA==.Netherpally:BAAANQADCgQJBAAAAA==.',
Ni='Nightbreed:BAAANQAECgEIAQAAAA==.Nikis:BAAANQADCgcIDwAAAA==.',
No='Nobbs:BAAANQAECgYICwAAAA==.Nokurai:BAAANQADCgEIAQAAAA==.Noonecaress:BAAANQAECgIIAgAAAA==.Novanexus:BAAANQAECgYIBwAAAA==.',
Nu='Nualaperafin:BAACNQAFFH8ZAAIeAAYKdxXoAQBJAQAeAAYKdxXoAQBJAQA1AAQKfzgAAh4ACgrJH60GABkDAB4ACgrJH60GABkDAAAA.',
Ny='Nyvara:BAAANQADCgQIBAABNQAECggIJAAdADQhAA==.Nyxkitsune:BAAANQADCggIDQAAAA==.',
Od='Odrada:BAAANQADCgQIBAAAAA==.',
Of='Off:BAAANQAECgEIAQAAAA==.',
Oi='Oiyo:BAAANQABCggICQAAAA==.',
Ok='Okonomiyaki:BAAANQADCgcIBwAAAA==.',
Ol='Olayro:BAABNQAECn81AAMFAAoKBRBLCAAMAgAFAAoKMg9LCAAMAgACAAkKZwlkzQAvAQAAAA==.Olelei:BAAANQADCgEIAQAAAA==.Oleste:BAAANQAECggICAAAAA==.',
Om='Omie:BAAANQADCgcIFwAAAA==.',
On='Onkiea:BAAANQABCgYJBAAAAA==.Onlyrage:BAAANQAECgUJCQAAAA==.',
Oo='Oomkin:BAAANQADCgQIBAAAAA==.Ooptomss:BAABNQAECn8wAAITAAkKKRUufAAWAgATAAkKKRUufAAWAgAAAA==.',
Op='Openingshift:BAAANQAECgUIBQAAAA==.Ophelìa:BAAANQADCgcIBwAAAA==.Ophilitheda:BAAANQADCgYIAwAAAA==.',
Or='Orclee:BAAANQAECgYIEQAAAA==.Oredeal:BAAANQAECgEIAQAAAA==.',
Pa='Pacificadora:BAAANQAECgYICQAAAA==.Palaguy:BAAANQADCgQIBAAAAA==.Palainc:BAAANQADCggICAAAAA==.Palkavanka:BAABNQAECn8ZAAIDAAgKvgYn9wD4AAADAAgKvgYn9wD4AAAAAA==.Pandamonk:BAAANQAECgYIDAAAAA==.Paxryze:BAAANQADCgYIBgAAAA==.',
Pe='Peeonfists:BAAANQADCgEIAQAAAA==.Peeonkeys:BAAANQAECgMIAwAAAA==.Persephie:BAAANQAECgQICwABNQAECgoKQwAHAC4ZAA==.Perzeval:BAAANQADCgMJAwAAAA==.',
Ph='Pharmacology:BAABNQAECn85AAIEAAoKASSuBADpAwAEAAoKASSuBADpAwAAAA==.Phyberlamer:BAAANQADCgEIAQAAAA==.Phénicie:BAAANQAECgUICQAAAA==.',
Pi='Pinkberri:BAAANQAECgEIAQAAAA==.Pinkblossom:BAAANQAECgUIDgAAAA==.Pipha:BAAANQABCgQIBQAAAA==.Pitchblack:BAAANQADCggIDQAAAA==.',
Po='Pocholate:BAAANQAECggICwAAAA==.Popa:BAABNQAECn8zAAQWAAkKsBlQMAClAgAWAAkKsBlQMAClAgADAAUKDhm/7gA/AQAGAAQKvhRsQgDrAAAAAA==.',
Pr='Prathe:BAABNQAECn8dAAIWAAoKSSPyDgBKAwAWAAoKSSPyDgBKAwAAAA==.Prayinfury:BAAANQAECggIDgAAAA==.Premorry:BAAANQAECgIIAgAAAA==.Premory:BAAANQADCgUICQAAAA==.Presagee:BAAANQADCgEIAQAAAA==.',
Ps='Psilocy:BAAANQAECgcIDwAAAA==.',
Pu='Pulsate:BAABNQAECn8sAAImAAoKJRnMCgC/AgAmAAoKJRnMCgC/AgAAAA==.Pulu:BAAANQAECgYIDwAAAA==.Purpleduster:BAAANQADCgEIAQAAAA==.',
Py='Pyllo:BAAANQAECggIDAAAAA==.',
Qa='Qaucker:BAAANQAECggIEQAAAA==.',
Qi='Qiz:BAABNQAECn8xAAQJAAkK1RmTFwAoAQAJAAQK2RmTFwAoAQAKAAcKAxU8wQAkAQAhAAIKfRrLBwCjAAAAAA==.Qizknows:BAAANQADCgEIAQAAAA==.',
Qu='Quadhelix:BAABNQAECn8pAAQUAAoKzRxPDQBdAgAUAAcKfB5PDQBdAgAQAAkKQhQ4YwDWAQAOAAIKqRK7LwBIAAAAAA==.Quartermain:BAAANQAECggIBwAAAA==.Quistas:BAAANQADCgEIAQAAAA==.',
Qw='Qwish:BAAANQADCgYIBgAAAA==.',
Ra='Rad:BAABNQAECn8XAAIfAAoKAQzjngBZAQAfAAoKAQzjngBZAQAAAA==.Radlock:BAAANQAECgMIAQABNQAECgoKFwAfAAEMAA==.Ragémachine:BAAANQAECgMIAwAAAA==.Raijin:BAAANQAECgMIAwABNQAECgkJMAACAHIaAA==.Raiken:BAAANQAECgQICgAAAA==.Rain:BAAANQAECgIIAgAAAA==.Raistlen:BAAANQAECgEIAQAAAA==.Rakin:BAAANQABCgQIBAAAAA==.Rakmin:BAAANQAECgUICwAAAA==.Rarib:BAAANQADCgcIBwAAAA==.Rasalgul:BAAANQADCgYIBgAAAA==.Raspberry:BAEANQAECgcIDAABNQAECgoKLQALADkQAA==.Rasto:BAAANQAECgQJBwAAAA==.Raszto:BAAANQADCgIIAgABNQAECgQJBwAMAAAAAA==.Rattlebat:BAAANQAECgIIAgAAAA==.Razara:BAEANQAECgYIBgABNQAECgkJJAAXAKgXAA==.',
Re='Redmark:BAAANQAECgQIBAAAAA==.Redwrath:BAAANQADCgIIAgAAAA==.Regolas:BAAANQADCgQIBgAAAA==.Relentlezz:BAAANQAECgMIAwAAAA==.Rendezook:BAAANQAECgQICwAAAA==.Respec:BAAANQADCggICAAAAA==.',
Ri='Ridire:BAAANQADCgIIAgAAAA==.Rike:BAAANQAECgQIBAAAAA==.Riohne:BAAANQADCgMIAwAAAA==.Rivexis:BAAANQADCgMIBAAAAA==.',
Ro='Roci:BAAANQAECgQIBAAAAA==.Rocker:BAAANQAECggICAAAAA==.Rolone:BAAANQABCgQIBAAAAA==.Romulias:BAAANQABCgEIAQAAAA==.Rootway:BAAANQAECgQIBAAAAA==.Roxus:BAABNQAECn8uAAIQAAkKtSHOQgDBAgAQAAkKtSHOQgDBAgAAAA==.Roxusdruid:BAABNQAECn8YAAIaAAkK2AvQHgAjAQAaAAkK2AvQHgAjAQABNQAECgkJLgAQALUhAA==.',
Ru='Ruthlin:BAAANQADCgYIBgAAAA==.',
Sa='Sabellal:BAAANQADCgYIBgAAAA==.Saegusa:BAABNQAECn8sAAIJAAoKuxZVCAArAgAJAAoKuxZVCAArAgAAAA==.Saepius:BAAANQAECgMIAgAAAA==.Salestia:BAABNQAECn9LAAIKAAoKkhGIWAAKAgAKAAoKkhGIWAAKAgAAAA==.Salorastor:BAAANQAECgcICwAAAA==.Samellir:BAAANQAECgMIBQAAAA==.Sangres:BAAANQADCgYIBgAAAA==.Sanguin:BAAANQAECgMIAwAAAA==.Sanlanesh:BAAANQADCgUIBQAAAA==.Sardothien:BAAANQADCgEIAQAAAA==.Sariseda:BAAANQAECggICAAAAA==.Sasive:BAAANQAECggIDAAAAA==.Satanicpanic:BAABNQAECn8YAAICAAcK+QSgwADQAAACAAcK+QSgwADQAAAAAA==.Sazoku:BAABNQAECn8mAAIQAAoKuh+HQgDCAgAQAAoKuh+HQgDCAgAAAA==.',
Sc='Scario:BAAANQADCgQIBQAAAA==.Scarletlock:BAAANQAECgcIBQABNQAECgoKPwAEAMcgAA==.Scarletnight:BAAANQAECgUICQABNQAECgoKPwAEAMcgAA==.Scarlët:BAAANQAECggIDgABNQAECgoKPwAEAMcgAA==.Schmall:BAABNQAECn8pAAIfAAoKuBJiYQBiAQAfAAoKuBJiYQBiAQAAAA==.Scrodumpulse:BAAANQADCgcIEAAAAA==.',
Se='Selvalin:BAAANQADCggIDgAAAA==.Sendit:BAAANQAECgcICQAAAA==.Sendron:BAAANQAECgEIAQAAAA==.Seniormage:BAABNQAECn8aAAIKAAkKYBowqwAsAgAKAAkKYBowqwAsAgAAAA==.Serveil:BAAANQADCgIIAgABNQAFFAUIDgAnAG0EAA==.',
Sh='Shaboon:BAAANQAECggICAAAAA==.Shadesprint:BAAANQAECggIBwAAAA==.Shamamoomoo:BAABNQAECn8sAAILAAgK7QPZLABbAQALAAgK7QPZLABbAQAAAA==.Shammywammy:BAAANQADCgMIAwAAAA==.Shaninigans:BAAANQADCgEIAQAAAA==.Shaowen:BAAANQADCgYIBgABNQAECgkJMAACAHIaAA==.Shaqeesha:BAAANQADCgUIBQAAAA==.Shenea:BAAANQADCgYICQAAAA==.Shestalker:BAACNQAFFH8KAAITAAQKzxDmFgDbAAATAAQKzxDmFgDbAAA1AAQKf4YAAhMACgoaIPsoAJwCABMACgoaIPsoAJwCAAAA.Shiau:BAABNQAECn8ZAAIVAAgKJAbHPAAwAQAVAAgKJAbHPAAwAQAAAA==.Shigaraki:BAABNQAECn8XAAIlAAkKCxQkIQCWAQAlAAkKCxQkIQCWAQABNQAECgoKNAAgAAwjAA==.Shimmyshamm:BAAANQAECgEIAQAAAA==.Shimura:BAAANQAECgQIBwAAAA==.Shinky:BAAANQADCgUIBAABNQAECgkJGgACAEoXAA==.Shý:BAABNQAECn8oAAIgAAkKFx6OCwCCAgAgAAkKFx6OCwCCAgAAAA==.',
Si='Silana:BAAANQADCggIDQAAAA==.Silvaine:BAABNQAECn8tAAIKAAkKOAUXrwBGAQAKAAkKOAUXrwBGAQAAAA==.Silverstorm:BAABNQAECn8YAAIQAAgKjBGRnQDSAQAQAAgKjBGRnQDSAQAAAA==.Sisterfran:BAAANQAECgEIAQAAAA==.Sixii:BAAANQAECgMIAwAAAA==.',
Sk='Skitzz:BAAANQAECgQICAAAAQ==.',
Sl='Slackr:BAAANQADCgUIBQAAAA==.Slackrm:BAAANQADCgMJBwAAAA==.Slackrp:BAAANQADCgQIBAAAAA==.Slashyr:BAAANQAECgQIDAAAAA==.Slimshadydh:BAAANQAECgQICwAAAA==.',
Sn='Snipez:BAAANQAECgIJAwAAAA==.Snortyhotorc:BAAANQAECgcICwAAAA==.Snortymcgoop:BAABNQAECn80AAMcAAoKnx2bIwAxAgAcAAgKihibIwAxAgATAAcKtxoadADXAQAAAA==.',
So='Solclipeus:BAABNQAECn9PAAMGAAoKqh/HBQBRAwAGAAkKaSHHBQBRAwADAAQKvhY07AAKAQAAAA==.Soldh:BAAANQAECgUICwABNQAECgoKTwAGAKofAA==.Solku:BAAANQAECgUIDgABNQAECgoKQAAEAOARAA==.Sollock:BAABNQAECn8ZAAICAAgKVxiGeQD3AQACAAgKVxiGeQD3AQABNQAECgoKTwAGAKofAA==.Solna:BAABNQAECn8oAAIKAAkKvgpHkwB/AQAKAAkKvgpHkwB/AQABNQAECgoKQAAEAOARAA==.Soulrecall:BAAANQAECgIIAwAAAA==.Soupz:BAABNQAECn8oAAIDAAkK9R99XQCAAgADAAkK9R99XQCAAgAAAA==.',
Sp='Sparadin:BAABNQAECn8pAAIGAAoKdQksKAAxAQAGAAoKdQksKAAxAQAAAA==.Spartacûs:BAAANQAECgQJBQABNQAFFAcICAALAF4IAA==.Spikore:BAAANQAECgEIAQAAAA==.Splitpeaz:BAAANQADCgcIBwAAAA==.',
Sq='Squrìtle:BAABNQAECn8aAAIDAAkKzwQl6wALAQADAAkKzwQl6wALAQAAAA==.',
Sr='Sririacha:BAAANQADCgUIBQABNQAECggIBwAMAAAAAA==.',
Ss='Ssjweedgoku:BAAANQAECgYIBgAAAA==.',
St='Stabbyjohn:BAAANQADCggICAAAAA==.Stabbypickle:BAAANQAECgcIDgABNQAECgoKOAAWAGEmAA==.Stachelbeere:BAAANQADCgYIBgAAAA==.Steedvegeta:BAAANQAECgQIBAAAAA==.Stewy:BAAANQADCgQIBAAAAA==.Stickybug:BAABNQAECn8YAAIKAAUKFAZvFwGNAAAKAAUKFAZvFwGNAAAAAA==.Strånge:BAAANQAECgYIBwAAAA==.Stìtch:BAACNQAFFH8jAAICAAgKnhxXBAD/AQACAAgKnhxXBAD/AQA1AAQKf0kAAgIACgr3JZUEAK8DAAIACgr3JZUEAK8DAAAA.Stítch:BAAANQADCgQIBAABNQAFFAgIIwACAJ4cAA==.',
Su='Sukiafaunias:BAAANQAECgEIAgAAAA==.Sukiafloras:BAAANQAECgYIDwAAAA==.Suldån:BAAANQAECggIDgAAAA==.Summondaddy:BAAANQADCgQIBQAAAA==.Sunfurious:BAABNQAECn8qAAIhAAkK4BqvAQA5AgAhAAkK4BqvAQA5AgAAAA==.Sunthyl:BAAANQAECgcIDQAAAA==.Suoop:BAAANQAECgYICwAAAA==.Supan:BAAANQADCgQIBAAAAA==.',
Sw='Swiftshaman:BAAANQAECggIDgAAAA==.',
Sy='Synvaria:BAABNQAECn8YAAMdAAYKMw6fggAsAQAdAAYKMw6fggAsAQAfAAMKqgVLxQCAAAAAAA==.Syraice:BAAANQADCgUIBQABNQAECgoKOwAnAM4ZAA==.Syrare:BAAANQAECgIIAgAAAA==.Syvenari:BAAANQAECgYIDgAAAA==.',
['Sï']='Sïxx:BAAANQADCgMJAwABNQAECgMIAwAMAAAAAA==.',
Ta='Tachisan:BAAANQAECgQICAAAAA==.Taeril:BAAANQADCgQIBQAAAA==.Taitan:BAAANQADCgEIAQAAAA==.Talonhand:BAABNQAECn8kAAIeAAkKqRx2CACdAgAeAAkKqRx2CACdAgAAAA==.Tamfam:BAAANQADCggIEAAAAA==.Tanburn:BAAANQADCgYICwAAAA==.Tanduinex:BAAANQADCgYIDAAAAA==.Tangal:BAAANQAECgIIAwAAAA==.Tankstabber:BAAANQADCgQIBQAAAA==.Tanplate:BAAANQADCgYICAAAAA==.Tarentia:BAAANQABCggIDgAAAA==.Tastytyrande:BAAANQAECgUIBQAAAA==.Tatsumy:BAABNQAECn8lAAIDAAgK+wvc1wBsAQADAAgK+wvc1wBsAQAAAA==.',
Tc='Tcmon:BAABNQAECn9QAAMTAAoK/R3MLwDdAgATAAoK/R3MLwDdAgAcAAMK5Av/TQBqAAAAAA==.',
Te='Teachings:BAAANQADCgMIAwAAAA==.Teaglizzy:BAAANQADCgEIAQABNQAFFAMICQAIAGIEAA==.Teehole:BAAANQAECgcIEAAAAA==.Telihill:BAAANQADCgUIDgAAAA==.Telsarra:BAAANQAECgQIBgAAAA==.',
Th='Thalenia:BAAANQADCggIIgAAAA==.Thebeastelf:BAAANQAECgUIDAABNQAFFAUIDwARAJgcAA==.Thebigtuna:BAACNQAFFH8IAAIlAAMKrhNvCADbAAAlAAMKrhNvCADbAAA1AAQKf00AAiUACgpcJCcDAKcDACUACgpcJCcDAKcDAAAA.Thegigatuna:BAAANQAECggICwAAAA==.Thekrisaning:BAAANQADCgYIDAAAAA==.Theladydruid:BAABNQAECn9QAAMBAAoKwhXaHABNAgABAAoKwhXaHABNAgAIAAYK6hCqTgDlAAAAAA==.Thelnaris:BAAANQADCgEIAQAAAA==.Themeats:BAAANQADCgQIBAAAAA==.Thendezoth:BAAANQAECgEIAgAAAA==.Thighsoffel:BAAANQADCgcIEwAAAA==.Thirdtjme:BAAANQADCgYIBgAAAA==.Thordam:BAAANQAECgcIDQAAAA==.Thragmar:BAAANQADCgEIAQAAAA==.Thunderhóof:BAAANQABCgYIDQAAAA==.Thôr:BAAANQAECggICAAAAA==.',
Ti='Tierrasbest:BAAANQAECgEIAQAAAA==.Tigerpa:BAABNQAECn8kAAITAAYKrAw86gDbAAATAAYKrAw86gDbAAAAAA==.Tinkernut:BAAANQABCgIIAgAAAA==.Tinypally:BAAANQAECgEIAgAAAA==.Tinypulls:BAAANQAECgIIAgAAAA==.Tinyraven:BAABNQAECn9VAAIlAAoK0Rn6FgCnAgAlAAoK0Rn6FgCnAgAAAA==.Tinysmites:BAAANQAECgQIAwAAAA==.Tinystotems:BAABNQAECn8cAAMfAAgKXhZVsAAyAQAfAAYKBBRVsAAyAQAdAAYKrQfNrQC/AAAAAA==.Tinythia:BAAANQADCgUIBQAAAA==.Tioklarus:BAABNQAECn9YAAImAAoKowvbCwCfAQAmAAoKowvbCwCfAQAAAA==.Tipzy:BAABNQAECn8kAAIiAAoKvQNfNADuAAAiAAoKvQNfNADuAAAAAA==.Tisaryn:BAAANQAECgQIBAAAAA==.',
To='Tofulady:BAACNQAFFH8IAAIgAAQKywyoCAC1AAAgAAQKywyoCAC1AAA1AAQKfzsAAiAACgpNIRoIAA8DACAACgpNIRoIAA8DAAAA.Tohu:BAAANQAECgYIDgAAAA==.Toraza:BAAANQADCgYIBgAAAA==.Toshen:BAAANQADCgEIAQAAAA==.Totax:BAAANQAECgEIAQAAAA==.Totemtoker:BAAANQADCggIDQAAAA==.',
Tr='Tremors:BAAANQADCggICQAAAA==.Triggër:BAAANQABCgQIBAABNQAECggIDgAMAAAAAA==.Trollverine:BAAANQAECggIAgAAAA==.Tromb:BAAANQAECgMIAwAAAA==.',
Tu='Tucknroll:BAAANQADCgcIDAAAAA==.',
Tw='Twobithusler:BAAANQAECgIIAgAAAA==.Twoon:BAAANQADCgYICAAAAA==.Twoone:BAAANQADCgUIBQAAAA==.',
Ty='Tyniarstus:BAAANQADCgYICAAAAA==.',
Ub='Ubivashka:BAAANQABCgEIAQAAAA==.',
Ud='Udderfiasco:BAAANQABCgQIBQAAAA==.',
Ug='Uggh:BAAANQADCgUIBQAAAA==.',
Un='Unholyslayer:BAAANQABCgIIAgAAAA==.Unhowly:BAACNQAFFH8MAAIHAAUKaBT2BAAlAQAHAAUKaBT2BAAlAQA1AAQKfzUAAgcACgqIJT8LAGADAAcACgqIJT8LAGADAAAA.Unpoppable:BAABNQAECn8cAAIEAAkKDwhTfwBbAQAEAAkKDwhTfwBbAQAAAA==.',
Ur='Ursamine:BAAANQAECggIEwAAAA==.',
Uz='Uzilok:BAAANQAECgcICgAAAA==.',
Va='Vaelyra:BAAANQADCgMIAwABNQAFFAQIDAABAJITAA==.Vakir:BAABNQAECn8qAAIXAAoKLxQLPQAOAgAXAAoKLxQLPQAOAgAAAA==.Valmortem:BAEANQADCgcIEgAAAA==.Vapidos:BAAANQAECgMICQAAAA==.Varynix:BAAANQAECgIIAgABNQAECgYIBwAMAAAAAA==.Vatica:BAAANQAECgcIBwAAAA==.',
Ve='Velanoria:BAAANQADCggICwAAAA==.Veldorai:BAAANQADCgYICwAAAA==.Velrenya:BAAANQADCgQIBgAAAA==.Velýndriel:BAAANQAECgUIDQAAAA==.Venvalzhar:BAABNQAECn81AAMEAAoKuCA3GgALAwAEAAoKuCA3GgALAwAiAAIKoAL+cgBAAAAAAA==.Veralidaine:BAAANQAECgQIBgAAAA==.Vestammeni:BAABNQAECn9AAAMUAAoKdST8AQA/AwAUAAoKdST8AQA/AwAQAAcKJw/kwgB2AQAAAA==.Vexlore:BAAANQADCgcICAAAAA==.',
Vi='Viciousazule:BAAANQADCgEIAQAAAA==.Violet:BAAANQAECggIAQAAAA==.Virus:BAAANQAECggIEgAAAA==.Vixsaurion:BAAANQAECgIIAQAAAA==.',
Vo='Vorn:BAAANQADCgcIBwAAAA==.Vow:BAABNQAECn8bAAIGAAcK6huoIADfAQAGAAcK6huoIADfAQAAAA==.',
Vy='Vynlenlor:BAAANQABCgIIAgAAAA==.',
Wa='Warmidget:BAAANQAECgEIAQAAAA==.',
Wc='Wckd:BAAANQAECgYIEgAAAA==.',
We='Weaksnow:BAABNQAECn8aAAIfAAkK+xaOUgCQAQAfAAkK+xaOUgCQAQABNQAFFAUIEQAKAJEUAA==.Weedgoku:BAAANQAECgYICQAAAA==.Weedvegeta:BAABNQAECn8iAAIKAAoKDh3qQQABAwAKAAoKDh3qQQABAwAAAA==.Wernbirn:BAAANQAECggIAQAAAA==.Wetraman:BAAANQADCgIIAgABNQAECgQIBQAMAAAAAA==.Wetremin:BAAANQAECgQIBQAAAA==.',
Wh='Whirpy:BAABNQAECn8hAAMBAAoKvBgAIAD9AQABAAoKvBgAIAD9AQAIAAEKAAC2vgAiAAAAAA==.Whisberis:BAAANQADCgMIAwAAAA==.Whitty:BAAANQADCgQIBAAAAA==.Whizkee:BAABNQAECn8VAAIiAAkKuw2QLQC5AQAiAAkKuw2QLQC5AQAAAA==.Whookies:BAAANQADCgMIAwABNQAECgYIBgAMAAAAAA==.',
Wi='Wildbeefwood:BAAANQAECgUICgAAAA==.Wingedlady:BAABNQAECn8vAAITAAoKpRKDTQAzAgATAAoKpRKDTQAzAgAAAA==.Wingss:BAACNQAFFH8FAAIDAAMKlh+wFAAQAQADAAMKlh+wFAAQAQA1AAQKfysAAgMACgppIlE4AO4CAAMACgppIlE4AO4CAAAA.',
Wu='Wushu:BAAANQAECgQICgAAAA==.',
Wy='Wyl:BAABNQAECn8zAAIDAAkKOCW6DAA+AwADAAkKOCW6DAA+AwAAAA==.',
Xe='Xerath:BAAANQAECgUICwAAAA==.',
Xi='Xiing:BAABNQAECn86AAMUAAoKxhf3DQDcAQAUAAoKxhf3DQDcAQAQAAEKAAAyXgEpAAAAAA==.Xinei:BAAANQADCgQIAQAAAA==.Xinhe:BAAANQAECgIIAgAAAA==.',
Xn='Xneutron:BAABNQAECn8kAAIKAAoK7hf6RwA1AgAKAAoK7hf6RwA1AgAAAA==.',
Xt='Xtravagent:BAAANQADCgIIAgAAAA==.',
Xw='Xwhitesnow:BAAANQAECgEIAQAAAA==.',
Xy='Xyxia:BAAANQADCgcIBwAAAA==.',
Ya='Yaiie:BAABNQAECn9tAAMYAAkK9BHNCAA/AQAFAAkK/A00CwCTAQAYAAgKshHNCAA/AQAAAA==.',
Yo='Yonna:BAAANQAECgMIAwAAAA==.',
Yu='Yunadrakka:BAAANQADCgEIAQAAAA==.Yunggrazydk:BAAANQADCggIDAABNQAECgYIFgAEAF8SAA==.Yungholy:BAABNQAECn8WAAIEAAYKXxLoigB1AQAEAAYKXxLoigB1AQAAAA==.Yungresto:BAAANQADCgQIBQABNQAECgYIFgAEAF8SAA==.Yuuki:BAAANQADCgcIBwABNQAECgEIAQAMAAAAAA==.Yuunggrazy:BAAANQADCggIEQABNQAECgYIFgAEAF8SAA==.',
['Yü']='Yüto:BAABNQAECn8sAAMTAAoKax/hHgAcAwATAAoKax/hHgAcAwAcAAUKDRcaRACOAAAAAA==.',
Za='Zabuto:BAABNQAECn8dAAIIAAkK8RTAQwDlAQAIAAkK8RTAQwDlAQAAAA==.Zaeraciustv:BAAANQABCggIDwAAAA==.Zahäära:BAABNQAECn8aAAIdAAcKnQopjwAJAQAdAAcKnQopjwAJAQAAAA==.Zaldiz:BAAANQAECgEIAwAAAA==.Zar:BAAANQAECgcICwAAAA==.Zarathor:BAAANQADCgQIBAABNQAECgkJMAACAHIaAA==.Zarrtan:BAAANQAECgYICwAAAA==.Zazevo:BAAANQAECgUIDQAAAA==.Zazlock:BAAANQAECgIIAgAAAA==.Zazmo:BAAANQADCgcIDAAAAA==.Zazprie:BAABNQAECn8iAAMiAAcKBQ76LQAYAQAiAAcKBQ76LQAYAQAEAAQKqAf5yQCUAAAAAA==.',
Ze='Zendrozath:BAAANQADCgQIBQABNQAECgQIBgAMAAAAAA==.',
Zi='Zippyzap:BAAANQAECgEIAQAAAA==.',
Zo='Zooz:BAAANQADCgIIAgAAAA==.',
Zu='Zual:BAAANQAECgQIBgAAAA==.Zularraka:BAAANQAECgUIDwAAAA==.',
Zx='Zxeý:BAAANQADCgcIDgAAAA==.',
['Äb']='Äbracadabruh:BAABNQAECn8eAAMKAAgKiBeWvAALAgAKAAcKthSWvAALAgAJAAIKXSD0NgBgAAABNQAECgoKFwAfAAEMAA==.',
['Äl']='Älissia:BAAANQAECgEIAgAAAA==.',
['Ål']='Ålexthegrëat:BAAANQAECgQIBQABNQAECgoKSwAKAJIRAA==.',
['Èm']='Èmandy:BAAANQADCggIDQAAAA==.',
['Ën']='Ëndo:BAABNQAECn9DAAQHAAoKLhlDIgC9AgAHAAoKzRdDIgC9AgANAAcKAw+XSwBpAQAXAAUKLx6yVADqAAAAAA==.',
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
