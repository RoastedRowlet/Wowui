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

local lookup = {'Druid-Restoration','Warlock-Demonology','Paladin-Retribution','Priest-Holy','Unknown-Unknown','Warlock-Affliction','Paladin-Protection','DeathKnight-Unholy','Mage-Frost','Mage-Arcane','Druid-Balance','DeathKnight-Frost','Warrior-Fury','DemonHunter-Havoc','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Hunter-BeastMastery','Warrior-Protection','Monk-Windwalker','DeathKnight-Blood','Warlock-Destruction','Monk-Brewmaster','Hunter-Marksmanship','Shaman-Restoration','Shaman-Enhancement','Druid-Feral','Shaman-Elemental','Monk-Mistweaver','Paladin-Holy','Mage-Fire','Priest-Shadow','Priest-Discipline','Druid-Guardian','DemonHunter-Vengeance','Evoker-Devastation','Evoker-Preservation','DemonHunter-Devourer',}
local provider = {region='US',realm='Azshara',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aaryyee:BAAANQAECgEIAQAAAA==.',
Ac='Aceforlife:BAABNQAECn8/AAIBAAkK5Q9DFQDWAQABAAkK5Q9DFQDWAQAAAA==.',
Ad='Adrox:BAAANQADCgMIBAAAAA==.',
Ae='Aelelelos:BAAANQADCgcICgAAAA==.Aequus:BAAANQABCgUIAwAAAA==.Aestinna:BAAANQAECgMIAwAAAA==.Aevenyhm:BAABNQAECn8tAAIBAAgKfhsNHwA1AgABAAgKfhsNHwA1AgAAAA==.',
Ag='Aghorn:BAAANQAECgIIAgAAAA==.',
Ai='Aidoneus:BAAANQADCgYIBgABNQAECgkJFQACAL8WAA==.',
Ak='Akijin:BAAANQAECgEIAQABNQAECgkJHwADAN8UAA==.Akismite:BAABNQAECn8fAAIDAAkK3xRnhwAYAgADAAkK3xRnhwAYAgAAAA==.',
Al='Alaru:BAABNQAECn83AAIEAAoKGw0DMgD2AQAEAAoKGw0DMgD2AQAAAA==.Alemental:BAAANQAECgcIBwABNQAECggIEgAFAAAAAA==.Algana:BAAANQADCggIDQABNQAECgoKNQAGAAUQAA==.Allhallows:BAABNQAECn8YAAIDAAcKBQeBFQH7AAADAAcKBQeBFQH7AAAAAA==.Alorandis:BAAANQAECgIIAgAAAA==.Alqueria:BAABNQAECn8uAAMHAAoKKhfYGwAOAgAHAAkKthfYGwAOAgADAAgKYg8ZtwCwAQABNQAFFAQICQACAGoSAA==.Altarboizyum:BAAANQAECgIIAQABNQAECgoKSQAHAKofAA==.',
An='Andanto:BAABNQAECn8VAAIIAAYK5g6jdwA7AQAIAAYK5g6jdwA7AQAAAA==.Angeliz:BAAANQAECggIDQAAAA==.Anitaloc:BAAANQAECgUIDgAAAA==.Anitapiss:BAAANQAECgMIAwAAAA==.Anneweaver:BAABNQAECn8pAAMJAAkK6h7FDwCsAQAKAAkKjBwSfACGAgAJAAgKGhvFDwCsAQABNQAFFAcIGAAKANsTAA==.Anorantha:BAABNQAECn88AAILAAoK0Q21HwCJAQALAAoK0Q21HwCJAQAAAA==.Antonio:BAAANQAECgEIAQAAAA==.',
Ap='Apicots:BAAANQADCggIDwAAAA==.Apipa:BAAANQAECgYIBwAAAA==.Apricot:BAEANQADCgUIBQABNQAECggIDgAFAAAAAA==.Apzz:BAAANQADCgIIAgAAAA==.',
Ar='Arendir:BAAANQAECggIAgAAAA==.Arizticat:BAAANQADCgUICQAAAA==.Arradrayn:BAAANQAECgUIBQABNQAECgYICwAFAAAAAA==.Arrowin:BAAANQADCgQIBAAAAA==.Artica:BAAANQADCggICAAAAA==.Arzan:BAAANQAECgYIDAAAAA==.',
As='Ashalan:BAABNQAECn8aAAIMAAYKbwZGagD2AAAMAAYKbwZGagD2AAAAAA==.Ashenflail:BAABNQAECn8YAAIHAAkKzQlsHQAQAQAHAAkKzQlsHQAQAQAAAA==.Astesia:BAAANQAECggICQAAAA==.Astrraa:BAAANQADCggIFgAAAA==.Asulo:BAAANQAECgYIBgABNQAFFAQICwANAAQXAA==.',
At='Atrejha:BAACNQAFFH8JAAIOAAQK3gWSCwCqAAAOAAQK3gWSCwCqAAA1AAQKfyMAAg4ACgpYClM/AMEBAA4ACgpYClM/AMEBAAAA.',
Au='Aurethas:BAAANQAECgQIBAAAAA==.Aurä:BAABNQAECn8dAAIKAAkKsw5e1QDcAQAKAAkKsw5e1QDcAQABNQAECgoKHwAPAGEYAA==.Aussilio:BAAANQADCggICAAAAA==.',
Av='Avera:BAAANQAECgUIAgAAAA==.Avye:BAAANQADCgEIAQAAAA==.',
Aw='Awesome:BAAANQAECgQIBQAAAA==.',
Az='Azgkrimpatul:BAAANQADCgYICwAAAA==.Azmodeus:BAAANQADCgUIBwAAAA==.Azrina:BAABNQAECn8cAAIQAAoKDhBAHwDWAQAQAAoKDhBAHwDWAQAAAA==.',
Ba='Bael:BAABNQAECn8dAAIOAAoKsQcaMwASAQAOAAoKsQcaMwASAQAAAA==.Baidden:BAAANQADCgMIBQAAAA==.Balddh:BAAANQAECgIIAgABNQAFFAUIDQARAJgcAA==.Balddk:BAABNQAECn8UAAIIAAYKRA3zdwA6AQAIAAYKRA3zdwA6AQABNQAFFAUIDQARAJgcAA==.Baldrogue:BAACNQAFFH8NAAIRAAUKmByLAgAOAQARAAUKmByLAgAOAQA1AAQKfzAABBEACgpxIoECAPICABEACgpsIoECAPICABAACApwDlscAPEBABIACArtAmcQABgBAAAA.Baldwarrior:BAABNQAECn8uAAIPAAoK+xrIKQA5AgAPAAoK+xrIKQA5AgAAAA==.Ballflapper:BAAANQADCgcICAABNQAECgoKIgATAKEUAA==.Bandidos:BAAANQAECgQICgAAAA==.Banekin:BAAANQADCggICAAAAA==.',
Be='Beastmans:BAAANQADCgQIBAAAAA==.Becka:BAAANQAECgYICwAAAA==.Beckz:BAAANQADCggIDQAAAA==.Beefhambacon:BAAANQAECgUIDgAAAA==.Behealzabub:BAAANQAECgcIDQAAAA==.Beladora:BAAANQADCgEIAQAAAA==.Belmatride:BAAANQAECgIIBwAAAA==.Belpepper:BAABNQAECn8bAAIDAAkK6ws9uACtAQADAAkK6ws9uACtAQAAAA==.Bendelmonte:BAAANQADCggIIgABNQAECgYIFAAIAFIXAA==.',
Bi='Biggum:BAAANQADCgIIAgAAAA==.Bigmez:BAABNQAECn8ZAAIUAAcKdhFqFgDkAAAUAAcKdhFqFgDkAAAAAA==.Bigmoocowii:BAAANQADCgIIAgAAAA==.Bigswangindi:BAAANQADCggIEAAAAA==.Bilipmonk:BAACNQAFFH8HAAIVAAQKfAXuCACfAAAVAAQKfAXuCACfAAA1AAQKfyIAAhUACgpLFrAiABMCABUACgpLFrAiABMCAAAA.Bindinglight:BAACNQAFFH8JAAMLAAMKYgSDIgB/AAALAAIKYgSDIgB/AAABAAIKdQO1DQBdAAA1AAQKf1oAAwEACgqQGDcZAHICAAEACgqQGDcZAHICAAsACQrFErA0AEMCAAAA.Birdofhermes:BAAANQADCgMIAwAAAA==.Bizzthewizz:BAAANQADCgQIBAAAAA==.Biñx:BAAANQABCgQJCQAAAA==.',
Bl='Blarr:BAABNQAECn8VAAIDAAcKyBTYuQCqAQADAAcKyBTYuQCqAQAAAA==.Blindehunter:BAAANQADCgIIAgABNQADCgIIAgAFAAAAAA==.Blindvoid:BAAANQAECgIIAgABNQADCgIIAgAFAAAAAA==.Bloodguard:BAAANQADCgYIBgAAAA==.Blubinax:BAAANQADCgQIBAAAAA==.Bluedabodeba:BAAANQADCgEIAQAAAA==.Bluejeanz:BAAANQADCgYIBQABNQAECgoKJwALAMMhAA==.',
Bo='Boonkay:BAAANQADCgEIAQAAAA==.Boonkie:BAAANQAECggICQAAAA==.Boonksdragon:BAAANQAECggICAAAAA==.Boonlock:BAAANQAECggIAQAAAA==.Boxbeater:BAAANQADCgYIBgAAAA==.',
Br='Braedravia:BAAANQAECgQIAwAAAA==.Bretikus:BAAANQAECgYIBgAAAA==.Brisanna:BAABNQAECn8bAAIDAAcKFApatwDrAAADAAcKFApatwDrAAAAAA==.Bruleecreme:BAAANQAECgcIDQAAAA==.',
Bu='Bubos:BAAANQADCgIJAgAAAA==.Budgeroo:BAAANQAECgUIBAAAAA==.',
['Bà']='Bàwlz:BAABNQAECn8bAAIWAAgKWxj2JwBaAQAWAAgKWxj2JwBaAQAAAA==.',
['Bè']='Bèérsërk:BAAANQADCgEIAQAAAA==.',
['Bö']='Böðull:BAAANQAECgMIBgAAAA==.',
Ca='Cadarion:BAAANQABCgIIAgAAAA==.Caelix:BAAANQADCgQIBQAAAA==.Caledor:BAABNQAECn8qAAIDAAkK4w3KnADpAQADAAkK4w3KnADpAQAAAA==.Calkhan:BAAANQADCgMIAwAAAA==.Camitriel:BAABNQAECn+yAQQCAAkKxyZqAQBqAwACAAkKxyZqAQBqAwAXAAUKBCWlGACnAQAGAAEK+x8mFQBbAAAAAA==.Cascadea:BAAANQAECggICAAAAA==.Cataleya:BAAANQAECggIAgAAAA==.Cawa:BAAANQADCggIDwAAAA==.',
Ce='Ceaserianoma:BAAANQADCgMIAwAAAA==.',
Ch='Chadder:BAAANQAECggIEgAAAA==.Charliie:BAABNQAECn83AAMUAAoKECKpAQAbAwAUAAoKECKpAQAbAwAPAAEKxA2xSgE9AAAAAA==.Chaunakoala:BAAANQADCgIIAgAAAA==.Cherryfudge:BAAANQADCggIDQAAAA==.Chipinwing:BAAANQAECgEIAQAAAA==.Chunkysoupz:BAAANQADCgYIBgAAAA==.',
Cl='Classyshammy:BAAANQADCggIDAAAAA==.Clockworks:BAAANQADCgcIEwAAAA==.Clouxdyskies:BAAANQADCgEIAQAAAA==.',
Co='Cocinegr:BAABNQAECn8gAAICAAgKdAxmrgB0AQACAAgKdAxmrgB0AQABNQAFFAUIEQAKAJEUAA==.Cocinegrø:BAAANQAECggIEgABNQAFFAUIEQAKAJEUAA==.Cokuzo:BAAANQAECgQIBwAAAA==.Coneja:BAABNQAECn81AAIKAAoKFgoP4ADIAQAKAAoKFgoP4ADIAQAAAA==.Coolbroguy:BAAANQABCgQIBAAAAA==.Coomspit:BAAANQAECgIIAgAAAA==.Corwa:BAAANQAECgEIAQABNQAFFAUKBwADAF4QAA==.Covidnynteen:BAAANQADCgUICAAAAA==.Cowtastrophe:BAAANQABCgcIEAAAAA==.',
Cr='Craiso:BAABNQAECn8cAAIYAAgKeyG9CACdAgAYAAgKeyG9CACdAgAAAA==.Crankinhawg:BAABNQAECn8VAAIKAAgKTiAkgQB8AgAKAAgKTiAkgQB8AgAAAA==.Crazbezzul:BAAANQADCgUIBwAAAA==.Creationz:BAAANQADCgYICQABNQAECgEIAQAFAAAAAA==.Crisarrow:BAAANQADCggIGAAAAA==.',
Cu='Current:BAABNQAECn8fAAIOAAgKKAdONAAKAQAOAAgKKAdONAAKAQAAAA==.',
Cy='Cynesh:BAACNQAFFH8aAAMTAAcKUR/2AwAfAgATAAYKDyL2AwAfAgAZAAUKSRXCDAByAQA1AAQKfywAAxMACgrSJn0AAJUDABMACgrSJn0AAJUDABkABwqvIJkpAP4BAAAA.Cytl:BAAANQAECgYICwAAAA==.',
Da='Dailybuilt:BAAANQADCgQICgAAAA==.Damitbobbi:BAAANQADCgUIBQAAAA==.Dangybangy:BAABNQAECn8ZAAITAAgKqBD9mADVAQATAAgKqBD9mADVAQAAAA==.Danjaianka:BAAANQADCggJHgAAAA==.Dankshotzs:BAAANQABCggICwAAAA==.Darkken:BAAANQADCgYJBgABNQADCgcIEwAFAAAAAA==.Darkkragmur:BAAANQAECgUICAAAAA==.Darklunche:BAAANQADCgUIBQAAAA==.Darknest:BAAANQADCgQIBgAAAA==.Darthimus:BAAANQAECgIIAwAAAA==.Darthmalgus:BAAANQADCgcICgAAAA==.Datbishkarma:BAABNQAECn8iAAIKAAgKCgV4ngAJAQAKAAgKCgV4ngAJAQAAAA==.',
Dd='Dding:BAACNQAFFH8KAAIHAAQKgyJhAgAkAQAHAAQKgyJhAgAkAQA1AAQKfzIAAwcACgqfJXcGAEIDAAcACQqGJXcGAEIDAAMAAgqvE2MLAXAAAAAA.',
De='Deadbarcy:BAAANQAECgIJAgAAAA==.Deathklok:BAABNQAECn8lAAMaAAoKcBS1UwAYAgAaAAoKcBS1UwAYAgAbAAgKRwaiIwAhAQAAAA==.Deathran:BAABNQAECn8nAAICAAoKCBepWwBEAgACAAoKCBepWwBEAgAAAA==.Deezgrips:BAABNQAECn8kAAIWAAgKvxq5JgCIAgAWAAgKvxq5JgCIAgAAAA==.Deffgwip:BAABNQAECn8ZAAIIAAcKuAwFLwAQAQAIAAcKuAwFLwAQAQAAAA==.Delfine:BAAANQADCggIHQAAAA==.Demonikiarly:BAAANQADCgUJBQABNQAECgoKHgAcAJ8dAA==.Despott:BAABNQAECn8fAAIKAAoKuRLffABJAQAKAAoKuRLffABJAQABNQAFFAUIDQARAJgcAA==.Destina:BAAANQAECggIDwAAAA==.Dethfox:BAABNQAECn8UAAIIAAYKUheIaABvAQAIAAYKUheIaABvAQAAAA==.Dethlock:BAAANQADCgQIBAAAAA==.',
Di='Dioni:BAABNQAECn8zAAMaAAoK+yGjCAA5AwAaAAoK+yGjCAA5AwAdAAYKgArwsAAxAQABNQAFFAIIBgABAI0RAA==.Dirknasty:BAAANQAECgQIBwAAAA==.Diyfootjobs:BAAANQADCgYJGgAAAA==.',
Dk='Dkurther:BAAANQAECgYIEAAAAA==.Dkxs:BAAANQADCgEIAQAAAA==.',
Do='Doggybag:BAAANQADCgQIBAAAAA==.Doomhauerr:BAAANQAECggICAAAAA==.Dottonohana:BAAANQAECgQIBAAAAA==.Doublehelix:BAAANQAECgcIDQAAAA==.Dovish:BAAANQAECgcIDAAAAA==.',
Dr='Drackygacky:BAAANQAECgIIAwAAAA==.Dracw:BAAANQAECgYICwAAAA==.Draglox:BAAANQAECgcICAAAAA==.Drakaryss:BAAANQADCgEIAQABNQAECgoKNAAeAAwjAA==.Drama:BAAANQAECgEIAQAAAA==.Drashar:BAAANQADCgUIBQAAAA==.Dravenm:BAABNQAECn8sAAIKAAgKbgyYigAuAQAKAAgKbgyYigAuAQAAAA==.Drawven:BAAANQAECgQIAwABNQAECggILAAKAG4MAA==.Draz:BAAANQAECgMIBQAAAA==.Driney:BAEBNQAECn8eAAQfAAoKiiFPCABFAwAfAAoKiiFPCABFAwAHAAIKCRnGYwBQAAADAAEK8BatLAFFAAABNQAECggIFgAaAC4kAA==.Droozh:BAAANQAECgEIAQAAAA==.Drunkendrago:BAAANQADCggIEwAAAA==.',
Du='Duesenjaeger:BAAANQADCgcICwAAAA==.Duko:BAAANQADCgEIAQAAAA==.',
['Dè']='Dèmonic:BAABNQAECn8VAAICAAkKvxZhWABZAQACAAkKvxZhWABZAQAAAA==.',
['Dé']='Désy:BAAANQAECgMIAwAAAA==.',
['Dø']='Døric:BAAANQADCgcJDAAAAA==.',
['Dü']='Dürinn:BAAANQADCgIIAgAAAA==.',
Eh='Ehud:BAABNQAECn8+AAIDAAoKByNdDACfAwADAAoKByNdDACfAwAAAA==.',
Ei='Eisiss:BAAANQABCgEIAQAAAA==.',
El='Elabrate:BAAANQADCgMIAwAAAA==.Elade:BAAANQADCgUIBQAAAA==.Elbori:BAABNQAECn8wAAIgAAoK1xnQAAAyAgAgAAoK1xnQAAAyAgAAAA==.Elbryan:BAAANQADCgMIAwAAAA==.Eldaral:BAAANQAECggIBAAAAA==.Elementium:BAAANQAECggIEQAAAA==.Elfmas:BAAANQAECgYICQAAAA==.Elorees:BAAANQADCgYIBgAAAA==.Elviswong:BAAANQADCgIIAgAAAA==.',
Em='Emerhy:BAAANQAECgEJAQAAAA==.',
Es='Escänor:BAABNQAECn8kAAMDAAkKmh/WJAAyAwADAAkKmh/WJAAyAwAHAAIKfwngZgBHAAAAAA==.Eshaia:BAAANQADCgEIAQAAAA==.Essemdee:BAAANQAECgQICwAAAA==.Essiee:BAAANQAECgQIBAAAAA==.',
Ex='Exlisum:BAAANQADCgQIBgAAAA==.',
Ey='Eyewyn:BAAANQABCgYIBQAAAA==.Eylos:BAAANQAECgEIAQAAAA==.',
Fa='Faesmite:BAAANQADCgUIBQAAAA==.Faithflop:BAAANQAECgYIEAAAAA==.Falleh:BAAANQADCgIIAgAAAA==.Fanorage:BAAANQAECgIIAgAAAA==.',
Fe='Felixox:BAAANQAECgEIAQAAAA==.Ferocias:BAAANQAECgQJBQAAAA==.Ferraxx:BAAANQADCgcIBwAAAA==.Fewture:BAAANQADCgUIBQAAAA==.Feykill:BAAANQAECgQIBAAAAA==.',
Fi='Fiametta:BAAANQADCggICAAAAA==.Fishbreath:BAAANQAECgEIAQAAAA==.',
Fl='Flaffergan:BAAANQAECgYIEwAAAA==.Flastage:BAAANQAECgMIBAAAAA==.Flexhack:BAABNQAECn8iAAIQAAkK3wqxKAB/AQAQAAkK3wqxKAB/AQAAAA==.Flåsh:BAABNQAECn8fAAMfAAgK8SDtNACQAgAfAAcK+SDtNACQAgADAAcK9BXPlwD0AQAAAA==.',
Fo='Focinnet:BAABNQAECn8oAAITAAgKVwq8igD1AQATAAgKVwq8igD1AQAAAA==.Forandra:BAAANQAECgIIAgAAAA==.Fortyacres:BAAANQADCgEIAQAAAA==.Fortybmh:BAAANQADCgEIAQABNQADCgEIAQAFAAAAAA==.Four:BAAANQADCgYJDgAAAA==.Fourform:BAAANQADCgIIAgAAAA==.',
Fr='Frianna:BAAANQAECgMIAwAAAA==.Frieren:BAAANQAECggIEAAAAA==.',
Fu='Fuzzbutt:BAAANQADCgEIAQAAAA==.',
Ga='Gaalit:BAAANQADCgcIBwAAAA==.Galaxybone:BAAANQADCgQIBAAAAA==.Galiar:BAAANQAECgEIAQAAAA==.Galithiri:BAAANQAECggICgAAAA==.Ganthani:BAABNQAECn8gAAIEAAcKNhAZhgCEAQAEAAcKNhAZhgCEAQAAAA==.Garzett:BAABNQAECn9CAAILAAoKRxkfEwAaAgALAAoKRxkfEwAaAgAAAA==.Gatortooth:BAAANQABCgIIBAAAAA==.Gaybeowners:BAAANQAECgEIAQAAAA==.',
Ge='Geigh:BAAANQADCgUIBQAAAA==.Gethellar:BAABNQAECn8iAAMTAAoKoRQwPADwAQATAAoKoRQwPADwAQAZAAEKqgP5nAAiAAAAAA==.',
Gh='Ghostdaliar:BAAANQADCgQIBgAAAA==.Ghouliana:BAAANQADCgUIBQABNQAECgIIAgAFAAAAAA==.',
Gl='Glizyglober:BAAANQADCgMIAwABNQAFFAMICQALAGIEAA==.Glizzyrizily:BAAANQADCgMIAwABNQAFFAMICQALAGIEAA==.Glizzyys:BAABNQAECn8rAAIPAAkKGg1uYwBZAQAPAAkKGg1uYwBZAQABNQAFFAMICQALAGIEAA==.Gllizzard:BAAANQADCgMIAwAAAA==.Gluckglucks:BAAANQABCgQIBAAAAA==.',
Go='Goblikon:BAAANQADCgMIAwABNQAECgYIDwAFAAAAAA==.Gore:BAABNQAECn8bAAQMAAoKegboWwA5AQAMAAoKegboWwA5AQAIAAMKwQFHzQBSAAAWAAEKAAAPxABAAAAAAA==.Gorrock:BAAANQAECgQIBAAAAA==.',
Gr='Gravtech:BAAANQADCggIDgABNQAECgoKFwARAGkQAA==.Greenlinaii:BAAANQADCggICgAAAA==.Greffin:BAAANQAECgEIAQAAAA==.Grenzo:BAAANQAECgEIAgAAAA==.Grhm:BAAANQAECgcIBwAAAA==.Grim:BAABNQAECn8jAAMIAAoKESRDFwACAwAIAAoKCiRDFwACAwAMAAMKyiIdZgAJAQABNQAFFAUICQAcAGsHAA==.Grimheart:BAAANQAECgEIAQAAAA==.Grundles:BAAANQADCggICAAAAA==.Grymnir:BAABNQAECn8kAAMbAAoKZAq8EQBqAQAdAAgKWwu+jQCCAQAbAAgKega8EQBqAQAAAA==.',
Gu='Gumsy:BAABNQAECn8pAAMPAAoK/hKMRAC9AQAPAAoKYxGMRAC9AQAUAAUKJxePGgC9AAAAAA==.',
Gw='Gwory:BAAANQAECgYICgAAAA==.',
['Gø']='Gørë:BAABNQAECn8fAAMCAAoKPwq9YwA7AQACAAoKPwq9YwA7AQAXAAEKAABugQAqAAAAAA==.',
Ha='Haddassah:BAAANQAECgQIBAAAAA==.Haramzadi:BAAANQADCgQICQAAAA==.Haranue:BAABNQAECn8fAAITAAYKgwhFrADVAAATAAYKgwhFrADVAAAAAA==.Harryporter:BAAANQAECgEIAQAAAA==.Harukà:BAAANQAECgUIDAAAAA==.Hatxo:BAAANQADCgQIBAABNQAECggIEQAFAAAAAA==.',
He='Healscat:BAAANQADCgUJBQAAAA==.Healsdog:BAAANQAECgEIAQAAAA==.Hefferd:BAAANQADCgQIBAAAAA==.Helfon:BAABNQAECn8qAAIOAAoKfh6aFAD4AgAOAAoKfh6aFAD4AgAAAA==.Helgadknight:BAAANQABCgUIBgAAAA==.Helganelf:BAAANQAECgEIAQAAAA==.Helices:BAABNQAECn8kAAMIAAoK2xnGGwCWAQAWAAgKyBqnPAAQAgAIAAkK8QzGGwCWAQAAAA==.Herm:BAAANQAECgEIAQAAAA==.',
Hi='Highlordt:BAABNQAECn8sAAQhAAkK4RofIAA5AgAhAAkK4RofIAA5AgAEAAgKkBM/cwDCAQAiAAEKrwd3LgAoAAAAAA==.Highlordtron:BAABNQAECn8fAAQCAAkKDBN8fADvAQACAAkK8RF8fADvAQAXAAEKohKlcQA9AAAGAAEKCwfULQA7AAAAAA==.Hinazuki:BAAANQAECgMIAwAAAA==.Hinoxfine:BAAANQADCgMIBAAAAA==.Hitatchi:BAAANQADCgEIAQAAAA==.',
Ho='Holybeast:BAAANQADCgIIAgAAAA==.Holycharge:BAAANQAECgIIAgAAAA==.Holycrab:BAAANQAECgEIAQAAAA==.Holydudy:BAAANQAECgEIAQAAAA==.Holyely:BAAANQAECgUIDwAAAA==.Holyfae:BAABNQAECn8tAAMfAAoKNBXEQABiAgAfAAoKNBXEQABiAgADAAQKbQbPPQG9AAAAAA==.Holygrom:BAABNQAECn8qAAIDAAkKOyWpBwC9AwADAAkKOyWpBwC9AwAAAA==.Holylove:BAAANQADCgUICgABNQAECgIIBAAFAAAAAA==.Holynutzz:BAAANQAECgMIAwAAAA==.Holyrager:BAAANQAECgYICgAAAA==.Holysplash:BAABNQAECn8hAAIEAAkKLRG4cQDIAQAEAAkKLRG4cQDIAQAAAA==.Holyvoids:BAAANQADCgIIAgAAAA==.Hondodk:BAECNQAFFH8YAAMIAAYKLiXhAAByAgAIAAYKLiXhAAByAgAWAAEKAACzHwAAAAA1AAQKf0YAAwgACgrBJiUBAGgDAAgACgq4JiUBAGgDABYAAQrDJr+uAG4AAAE1AAUUBwgTAAgAYyQA.Honeyshamwow:BAAANQAECgQIBAAAAA==.Hoodadin:BAAANQABCgMIAwAAAA==.Hoodlummon:BAAANQADCggJHQAAAA==.Hopesfall:BAAANQAECgIJAwAAAA==.Howzitcuz:BAAANQADCgcIGQABNQAECgkJJAAfAIMYAA==.Hozari:BAABNQAECn8zAAILAAoKihbLIwCyAgALAAoKihbLIwCyAgAAAA==.',
Ht='Ht:BAAANQADCgcIDAAAAA==.',
Hu='Hunterstickg:BAAANQADCgUIBQAAAA==.',
['Hã']='Hãvøc:BAAANQADCgIIAgAAAA==.',
Ia='Ianil:BAAANQAECgYICwAAAA==.',
Ic='Iccyhot:BAAANQADCgMIAwABNQAFFAMICQALAGIEAA==.',
Ii='Iiwhiskey:BAAANQADCgcICAAAAA==.',
Il='Ilirranna:BAAANQAECgIIBAAAAA==.',
In='Infi:BAACNQAFFH8dAAMZAAgKwSJeAwBZAgAZAAgKGx1eAwBZAgATAAEKLyXsLQBnAAA1AAQKf0gAAxkACgo0JVkBANwDABkACgo0JVkBANwDABMAAQrZJn86AXAAAAAA.Initabath:BAABNQAECn8ZAAMLAAoKYwTgigCpAAALAAYKsgTgigCpAAABAAoK+QM6QACSAAAAAA==.Initapoop:BAAANQAECgQIDQAAAA==.Inosukè:BAABNQAECn80AAIeAAoKDCPaAQCsAwAeAAoKDCPaAQCsAwAAAA==.Inse:BAAANQAECgQIAwAAAA==.Invisibro:BAABNQAECn8XAAMRAAoKaRAuOAD2AQARAAoKwQ8uOAD2AQAQAAIKMAxWjQBPAAAAAA==.',
Io='Ioannis:BAABNQAECn8YAAIDAAYK4RGxvgDfAAADAAYK4RGxvgDfAAAAAA==.',
Ip='Ipse:BAAANQADCgMIAwAAAA==.',
Ir='Irasenme:BAAANQAECgIIAgAAAA==.',
Is='Isos:BAABNQAECn8/AAMEAAoK+SLnDgBOAwAEAAoK+SLnDgBOAwAiAAEKCBC0KAAzAAAAAA==.Isus:BAAANQADCgYJBgABNQAECgoKPwAEAPkiAA==.',
Iy='Iykyk:BAAANQAECgIIAgABNQAECgkJJAAfAIMYAA==.',
Ja='Jadeadly:BAAANQAECgcICAAAAA==.Jaded:BAABNQAECn8wAAIVAAoKaheQFAChAQAVAAoKaheQFAChAQAAAA==.Jakerbonk:BAAANQADCgYIBwAAAA==.Jakersai:BAABNQAECn8YAAISAAkKvA7dCwChAQASAAkKvA7dCwChAQAAAA==.Jakersaint:BAAANQADCggIDAAAAA==.Jamae:BAAANQAECgQIAwAAAA==.Javyr:BAABNQAECn8XAAITAAcKVR3jcABVAQATAAcKVR3jcABVAQAAAA==.Jayfmtv:BAAANQAECgMIBAAAAA==.Jaysdruid:BAAANQAECgQIBAAAAA==.',
Je='Jeetz:BAAANQAECgUIBQAAAA==.Jessicax:BAAANQAECgQIBAAAAA==.Jetpackcat:BAAANQADCgIIAgAAAA==.',
Ji='Jio:BAAANQAECgQIBAAAAA==.',
Jl='Jlnxy:BAABNQAECn8bAAIDAAoKBwoYugCpAQADAAoKBwoYugCpAQAAAA==.',
Jo='Joania:BAAANQADCggICAAAAA==.Jonoa:BAAANQADCgUIBQAAAA==.',
Ju='Judgmentalaf:BAAANQADCggIFwAAAA==.Judo:BAAANQAECgIIAgAAAA==.',
Ka='Kadre:BAABNQAECn8eAAIUAAgKgQM8HgCdAAAUAAgKgQM8HgCdAAAAAA==.Kadzilak:BAAANQADCgQIBgAAAA==.Kagemika:BAAANQAECgQIBAABNQAFFAQICQAOAN4FAA==.Kaiola:BAAANQAECgEIAgAAAA==.Kaizumie:BAAANQAECgIIAgAAAA==.Kalirti:BAAANQADCgIIAgAAAA==.Kamistri:BAABNQAECn8qAAQEAAoKCSBkHwDyAgAEAAoKCSBkHwDyAgAhAAMKHw/8YQB5AAAiAAIKrAZkIwBOAAAAAA==.Kanaa:BAAANQAECgQIBgAAAA==.Kanatre:BAAANQADCgEIAQAAAA==.Kandicee:BAAANQAECgIIAgAAAA==.Karensmith:BAAANQADCgcIBwAAAA==.Karessandra:BAAANQADCgQIBAABNQAECggICgAFAAAAAA==.Karrison:BAAANQADCgEIAQAAAA==.Kathea:BAAANQAECgQIBAAAAA==.Kayarra:BAAANQADCgEIAgABNQADCgQIBAAFAAAAAA==.Kaynarra:BAAANQADCgQIBAAAAA==.Kayonna:BAAANQABCgEIAQABNQADCgQIBAAFAAAAAA==.',
Ke='Keastral:BAAANQAECgQIBwAAAA==.Keeynai:BAAANQADCgQIBAAAAA==.Keldanis:BAABNQAECn8xAAITAAkKfRkVKwA0AgATAAkKfRkVKwA0AgAAAA==.Kelestrah:BAAANQADCgQJBAAAAA==.Kelterrager:BAAANQADCgMIAwAAAA==.Keony:BAABNQAECn8kAAIfAAkKgxg6JQAjAgAfAAkKgxg6JQAjAgAAAA==.Kerthur:BAAANQAECgQIBAAAAA==.',
Ki='Kickpigeons:BAAANQADCgEIAQAAAA==.Killertcells:BAAANQABCgIIAgAAAA==.Kirgrand:BAAANQADCgMIAwAAAA==.Kittyarly:BAABNQAECn8eAAIcAAoKnx2tAwCTAgAcAAoKnx2tAwCTAgAAAA==.',
Ko='Kodeck:BAAANQADCggIGQAAAA==.Kodokan:BAAANQAECgEIAQAAAA==.Koshima:BAABNQAECn8zAAIdAAoK6BheNwCZAgAdAAoK6BheNwCZAgAAAA==.Kozan:BAAANQADCgUICAAAAA==.',
Kr='Krimdan:BAAANQADCgQIBAAAAA==.Krimhit:BAAANQADCgUICwAAAA==.Krimrok:BAAANQABCgIIAgAAAA==.Krimwarr:BAAANQADCgQIBAAAAA==.',
Ku='Kudou:BAAANQADCgMIAwAAAA==.Kudranne:BAAANQAECgQIBAABNQAECggICgAFAAAAAA==.Kugia:BAACNQAFFH8GAAIBAAIKjREJDAB+AAABAAIKjREJDAB+AAA1AAQKfzQAAgEACgrpHY8IAMYCAAEACgrpHY8IAMYCAAAA.',
Ky='Kylex:BAAANQAECgEIAQAAAA==.Kynndell:BAAANQADCggIGQAAAA==.Kyo:BAAANQADCgYIDgAAAA==.',
['Kà']='Kàrgälgan:BAAANQAECgEIAQAAAA==.',
['Kø']='Køkushibø:BAAANQABCgUIBQAAAA==.',
La='Laments:BAAANQADCgUIBQAAAA==.Lammb:BAAANQADCgUIBQAAAA==.Latak:BAAANQADCgMIAwAAAA==.Latir:BAAANQADCgUIBwAAAA==.Lazylox:BAAANQAECgEIAQAAAA==.Lazyryx:BAAANQADCgUIBQAAAA==.',
Le='Leetheal:BAACNQAFFH8TAAMEAAUKIgoiEgAPAQAEAAUKIgoiEgAPAQAhAAMKVhPnDQD1AAA1AAQKfzcAAwQACgrfFes/AGsCAAQACgrfFes/AGsCACEACAqcHpIKAEUCAAAA.Leethul:BAABNQAECn82AAICAAoKkhfiIwApAgACAAoKkhfiIwApAgAAAA==.Lelethxx:BAAANQAECgIIBAAAAA==.Lesanna:BAABNQAECn9DAAIOAAoK8QvoHACzAQAOAAoK8QvoHACzAQAAAA==.Lestharia:BAAANQAECgUIBQAAAA==.Leysmith:BAABNQAECn86AAIDAAoK/RKacwBsAQADAAoK/RKacwBsAQAAAA==.',
Li='Lifestream:BAAANQAECgIIAgAAAA==.Lilheal:BAAANQAECgIJAgAAAA==.Lilium:BAAANQADCgYICwAAAA==.Lionël:BAAANQAECgUIDQAAAA==.Lisax:BAAANQAECgEIAQAAAA==.Lizbethe:BAABNQAECn8pAAQXAAoK9RxqBwCPAgAXAAcK4CBqBwCPAgACAAcK7xrWiADQAQAGAAcK3Bt0BwA9AQAAAA==.',
Lo='Loadedtotem:BAAANQAECgMIAwAAAA==.Lockmclovin:BAAANQADCgMIAwAAAA==.Loltank:BAAANQAECgcICwAAAA==.Lomrgreenol:BAAANQADCgQIBAAAAA==.Lopi:BAAANQAECgQIAwAAAA==.Lorast:BAAANQAECgEIAQAAAA==.Lorwater:BAAANQADCgQIBAAAAA==.Loveinfinity:BAAANQABCgIIAgAAAA==.',
Lp='Lp:BAAANQADCgYICAAAAA==.',
Lu='Lumibell:BAAANQABCgYIBwAAAA==.Luminate:BAAANQADCgQIBAAAAA==.Lunaru:BAAANQAECgQIAwAAAA==.Lunaryon:BAAANQADCgUICgAAAA==.',
Ma='Madamgypsy:BAAANQAECgQIDwAAAA==.Madamlilith:BAAANQAECgUIBQAAAA==.Madderco:BAAANQAECggICAAAAA==.Madivh:BAAANQADCgQIBAAAAA==.Magaspy:BAAANQAECgUIDgAAAA==.Magerage:BAAANQAECgEIAQAAAA==.Magerassfoo:BAAANQAECgcIDAAAAA==.Magiccairne:BAAANQAECgUIEAAAAA==.Magikiarly:BAAANQAECgQIBQABNQAECgoKHgAcAJ8dAA==.Magnar:BAAANQAECgIIAgABNQAECggIEgAFAAAAAA==.Mahoogany:BAAANQADCgYIDAAAAA==.Malson:BAAANQAECgMIAwAAAA==.Mamimage:BAACNQAFFH8RAAIKAAUKkRShEwD8AAAKAAUKkRShEwD8AAA1AAQKf0YAAgoACgpzIFEcAGYDAAoACgpzIFEcAGYDAAAA.Marrik:BAAANQADCgMIAwAAAA==.Marukka:BAAANQADCgQIBAABNQADCgcIBwAFAAAAAA==.Matty:BAAANQADCgEIAQAAAA==.Maxxatk:BAAANQAECgIIAgAAAA==.Mayiana:BAAANQAECgQIBgAAAA==.',
Mc='Mcspanky:BAAANQAECggICAAAAA==.',
Me='Meadowlark:BAAANQAECgQIBAAAAA==.Mefistofeles:BAAANQAECgQICwAAAA==.Mellie:BAAANQADCgQIBQAAAA==.Meowstic:BAABNQAECn8rAAMjAAoK5xsJBwAaAwAjAAgKoSIJBwAaAwALAAIKuAcLYABUAAABNQAECgIIAgAFAAAAAA==.Mercurious:BAAANQAECgYIEgAAAA==.Metalrules:BAAANQABCggICAAAAA==.Methypheni:BAABNQAECn8VAAMLAAYKAR1hXgBXAQALAAUK5R1hXgBXAQAcAAMK4RP7MACLAAAAAA==.',
Mi='Mill:BAAANQADCgYICgAAAA==.Minimuff:BAAANQAECgIIAgAAAA==.Mirajanna:BAABNQAECn9CAAIkAAoK6xdkBAARAgAkAAoK6xdkBAARAgAAAA==.Missmouthoff:BAABNQAECn84AAIEAAgK0ReqSwBCAgAEAAgK0ReqSwBCAgAAAA==.Mitenâ:BAAANQADCgUIBgAAAA==.Mizzxgummy:BAAANQAECgcIBwAAAA==.',
Mo='Momster:BAAANQADCggIDgAAAA==.Monkin:BAAANQAECgEIAQAAAA==.Moogan:BAAANQAECgUICgAAAA==.Mookins:BAAANQAECgYIEgAAAA==.Moonfishing:BAABNQAECn8nAAIKAAoKkhbCeACMAgAKAAoKkhbCeACMAgAAAA==.Moonfly:BAACNQAFFH8PAAILAAcKGReRDgCAAQALAAcKGReRDgCAAQA1AAQKfywAAgsACgqDI6EPAEsDAAsACgqDI6EPAEsDAAAA.Morax:BAABNQAECn8UAAMCAAUKfgx/7wDrAAACAAQKlAx/7wDrAAAGAAEKPAzlLgA4AAAAAA==.Morbidlord:BAAANQABCgYIEQAAAA==.Moscacrazy:BAAANQADCggIEwAAAA==.Mourne:BAABNQAECn8sAAMRAAoK2BhkHwCFAgARAAoK2BhkHwCFAgAQAAIKMRHLRACRAAAAAA==.',
Ms='Mssmalvile:BAAANQAECgEIAQAAAA==.',
Mt='Mtnoflight:BAAANQADCgMIAwAAAA==.',
My='Myrrvain:BAAANQAECgEIAQAAAA==.Mythara:BAAANQADCgYIBgAAAA==.',
Na='Naarcissus:BAAANQABCgIIAgAAAA==.Nagrim:BAAANQAECgEIAQABNQAECgoKKQAPAP4SAA==.Nalaana:BAAANQAECgUIEwAAAA==.Nalariel:BAABNQAECn8hAAMIAAkKgiAiKwCJAgAIAAkKgiAiKwCJAgAWAAEKeRpXvQBNAAAAAA==.Nallaana:BAAANQAECgQIBQAAAA==.Nalmagedan:BAABNQAECn8pAAIKAAoKYw2WQgDtAQAKAAoKYw2WQgDtAQAAAA==.Nammi:BAAANQADCgMIAwAAAA==.Nardalem:BAAANQADCgcIBwAAAA==.Nardorne:BAAANQADCgMIAwAAAA==.Narec:BAAANQADCgUIBQAAAA==.Narfhound:BAAANQADCgYICAAAAA==.Nazgrok:BAAANQAECggIEgAAAA==.',
Ne='Nearhammer:BAAANQAECgEIAQAAAA==.Nearsear:BAAANQADCgcIBwAAAA==.Nefariouz:BAAANQAECggIBwAAAA==.Nervouz:BAABNQAECn8sAAIOAAoKGhOjGwC/AQAOAAoKGhOjGwC/AQAAAA==.Netherpally:BAAANQADCgQJBAAAAA==.',
Ni='Nightbreed:BAAANQAECgEIAQAAAA==.Nikis:BAAANQADCgcIDwAAAA==.',
No='Nobbs:BAAANQAECgYICwAAAA==.Noonecaress:BAAANQAECgIIAgAAAA==.',
Nu='Nualaperafin:BAACNQAFFH8NAAIbAAQKrBQQAgDzAAAbAAQKrBQQAgDzAAA1AAQKfzYAAhsACgpqH60GABkDABsACgpqH60GABkDAAAA.',
Ny='Nyvara:BAAANQADCgQIBAABNQAECgYIEgAFAAAAAA==.Nyxkitsune:BAAANQADCggIDQAAAA==.',
Od='Odrada:BAAANQADCgQIBAAAAA==.',
Of='Off:BAAANQAECgEIAQAAAA==.',
Oi='Oiyo:BAAANQABCggICQAAAA==.',
Ok='Okonomiyaki:BAAANQADCgcIBwAAAA==.',
Ol='Olayro:BAABNQAECn81AAMGAAoKBRA3BAC/AQAGAAoKMg83BAC/AQACAAkKZwnDjADXAAAAAA==.Olelei:BAAANQADCgEIAQAAAA==.',
Om='Omie:BAAANQADCgcIFwAAAA==.',
On='Onkiea:BAAANQABCgYJBAAAAA==.Onlyrage:BAAANQAECgUJCQAAAA==.',
Oo='Oomkin:BAAANQADCgQIBAAAAA==.Ooptomss:BAABNQAECn8uAAITAAkKhhMufAAWAgATAAkKhhMufAAWAgAAAA==.',
Op='Openingshift:BAAANQAECgUIBQAAAA==.Ophelìa:BAAANQADCgcIBwAAAA==.Ophilitheda:BAAANQADCgYIAwAAAA==.',
Or='Orclee:BAAANQAECgYIEQAAAA==.',
Pa='Pacificadora:BAAANQAECgQIBgAAAA==.Palaguy:BAAANQADCgQIBAAAAA==.Palainc:BAAANQADCggICAAAAA==.Palkavanka:BAAANQAECgQIEAAAAA==.Pandamonk:BAAANQAECgYIDAAAAA==.',
Pe='Peeonfists:BAAANQADCgEIAQAAAA==.Peeonkeys:BAAANQAECgMIAwAAAA==.Persephie:BAAANQAECgQICwABNQAECgoKKQAPAP4SAA==.Perzeval:BAAANQADCgMJAwAAAA==.',
Ph='Pharmacology:BAABNQAECn8kAAIEAAgKuiFREwDMAgAEAAgKuiFREwDMAgAAAA==.Phyberlamer:BAAANQADCgEIAQAAAA==.Phénicie:BAAANQAECgIIAQAAAA==.',
Pi='Pinkberri:BAAANQAECgEIAQAAAA==.Pinkblossom:BAAANQAECgUICwAAAA==.Pipha:BAAANQABCgQIBQAAAA==.Pitchblack:BAAANQADCggIDQAAAA==.',
Pl='Plutochibi:BAAANQABCggICwAAAA==.',
Po='Pocholate:BAAANQAECgYICAAAAA==.Popa:BAABNQAECn8zAAQfAAkKsBlQMAClAgAfAAkKsBlQMAClAgADAAUKDhm/7gA/AQAHAAQKvhRsQgDrAAAAAA==.',
Pr='Prathe:BAABNQAECn8ZAAIfAAgKfSOUFAChAgAfAAgKfSOUFAChAgAAAA==.Prayinfury:BAAANQAECgcICAAAAA==.Premorry:BAAANQAECgIIAgAAAA==.Premory:BAAANQADCgUICQAAAA==.Presagee:BAAANQADCgEIAQAAAA==.',
Ps='Psilocy:BAAANQAECgcIDwAAAA==.',
Pu='Pulsate:BAABNQAECn8lAAIlAAoKJRnMCgC/AgAlAAoKJRnMCgC/AgAAAA==.Pulu:BAAANQAECgUIBgAAAA==.Purpleduster:BAAANQADCgEIAQAAAA==.',
Py='Pyllo:BAAANQAECggIDAAAAA==.',
Qa='Qaucker:BAAANQAECggIDwAAAA==.',
Qi='Qiz:BAABNQAECn8iAAMJAAgKtBdwHwDuAAAKAAYKNhJtGQFhAQAJAAQKbhlwHwDuAAAAAA==.Qizknows:BAAANQADCgEIAQAAAA==.',
Qu='Quadhelix:BAABNQAECn8aAAMUAAoKyRtPDQBdAgAUAAcKfB5PDQBdAgAPAAYKRhE/mgDXAAAAAA==.Quartermain:BAAANQAECggIBwAAAA==.Quistas:BAAANQADCgEIAQAAAA==.',
Qw='Qwish:BAAANQADCgYIBgAAAA==.',
Ra='Rad:BAABNQAECn8XAAIdAAoKAQx9XQD1AAAdAAoKAQx9XQD1AAAAAA==.Radlock:BAAANQAECgMIAQABNQAECgoKFwAdAAEMAA==.Ragémachine:BAAANQADCgcICwAAAA==.Raijin:BAAANQADCgcICAABNQAECggIEgAFAAAAAA==.Raiken:BAAANQAECgQICgAAAA==.Rain:BAAANQAECgIIAgAAAA==.Raistlen:BAAANQAECgEIAQAAAA==.Rakin:BAAANQABCgQIBAAAAA==.Rakmin:BAAANQAECgUICwAAAA==.Rarib:BAAANQADCgcIBwAAAA==.Raspberry:BAEANQAECgUIDAABNQAECggIDgAFAAAAAA==.Rasto:BAAANQAECgQJBwAAAA==.Raszto:BAAANQADCgIIAgABNQAECgQJBwAFAAAAAA==.Rattlebat:BAAANQAECgIIAgAAAA==.',
Re='Redmark:BAAANQAECgQIBAAAAA==.Redwrath:BAAANQADCgIIAgAAAA==.Regolas:BAAANQADCgQIBgAAAA==.Rendezook:BAAANQAECgQICQAAAA==.Respec:BAAANQADCggICAAAAA==.',
Ri='Rincewind:BAAANQADCggIFQAAAA==.Riohne:BAAANQADCgMIAwAAAA==.Rivexis:BAAANQADCgMIBAAAAA==.',
Ro='Roci:BAAANQADCggIFgAAAA==.Rocker:BAAANQAECggICAAAAA==.Rolone:BAAANQABCgQIBAAAAA==.Romulias:BAAANQABCgEIAQAAAA==.Rootway:BAAANQAECgQIBAAAAA==.Roxus:BAABNQAECn8uAAIPAAkKtSFPKwAxAgAPAAkKtSFPKwAxAgAAAA==.Roxusdruid:BAABNQAECn8XAAIcAAkK8QrQHgAjAQAcAAkK8QrQHgAjAQABNQAECgkJLgAPALUhAA==.',
Ru='Ruthlin:BAAANQADCgYIBgAAAA==.',
Sa='Sabellal:BAAANQADCgYIBgAAAA==.Saegusa:BAABNQAECn8fAAIJAAoKkhR4BQABAgAJAAoKkhR4BQABAgAAAA==.Saepius:BAAANQAECgMIAgAAAA==.Salestia:BAABNQAECn8vAAIKAAoKOA63WACiAQAKAAoKOA63WACiAQAAAA==.Salorastor:BAAANQAECgUIBQAAAA==.Samellir:BAAANQAECgMIBQAAAA==.Sanlanesh:BAAANQADCgUIBQAAAA==.Sardothien:BAAANQADCgEIAQAAAA==.Sasive:BAAANQAECgcICwAAAA==.Satanicpanic:BAAANQAECgcICwAAAA==.Sazoku:BAABNQAECn8kAAIPAAoKBh+HQgDCAgAPAAoKBh+HQgDCAgAAAA==.',
Sc='Scario:BAAANQADCgQIBQAAAA==.Scarletlock:BAAANQAECgcIBQABNQAECgoKKwAEAEwgAA==.Scarletnight:BAAANQAECgUICQABNQAECgoKKwAEAEwgAA==.Scarlët:BAAANQAECgMIAwABNQAECgoKKwAEAEwgAA==.Schmall:BAABNQAECn8ZAAIdAAgKoxCnfQCrAQAdAAgKoxCnfQCrAQAAAA==.Scrodumpulse:BAAANQADCgcIEAAAAA==.',
Se='Selvalin:BAAANQADCggIDgAAAA==.Sendit:BAAANQAECgcICQAAAA==.Seniormage:BAABNQAECn8XAAIKAAcKvx4wqwAsAgAKAAcKvx4wqwAsAgAAAA==.Serveil:BAAANQADCgIIAgABNQAFFAQICQAmAIsCAA==.',
Sh='Shaboon:BAAANQAECggICAAAAA==.Shadesprint:BAAANQAECggIBwAAAA==.Shamamoomoo:BAABNQAECn8pAAIQAAgK7QPZLABbAQAQAAgK7QPZLABbAQAAAA==.Shaninigans:BAAANQADCgEIAQAAAA==.Shaowen:BAAANQADCgYIBgABNQAECggIEgAFAAAAAA==.Shaqeesha:BAAANQADCgUIBQAAAA==.Shenea:BAAANQADCgYICQAAAA==.Shestalker:BAACNQAFFH8KAAITAAQKzxBzDQDoAAATAAQKzxBzDQDoAAA1AAQKf2QAAhMACgqTHu0YAJECABMACgqTHu0YAJECAAAA.Shiau:BAABNQAECn8ZAAIVAAgKJAbHPAAwAQAVAAgKJAbHPAAwAQAAAA==.Shigaraki:BAABNQAECn8XAAInAAkKCxSvEwCxAQAnAAkKCxSvEwCxAQABNQAECgoKNAAeAAwjAA==.Shimura:BAAANQADCggIEgAAAA==.Shinky:BAAANQADCgUIBAABNQAECgkJGgACAEoXAA==.Shý:BAABNQAECn8aAAIeAAcKyR8BDADXAQAeAAcKyR8BDADXAQAAAA==.',
Si='Silana:BAAANQADCggIDQAAAA==.Silvaine:BAABNQAECn8ZAAIKAAcKmwRnsQDkAAAKAAcKmwRnsQDkAAAAAA==.Silverstorm:BAABNQAECn8YAAIPAAgKjBGRnQDSAQAPAAgKjBGRnQDSAQAAAA==.Sisterfran:BAAANQAECgEIAQAAAA==.Sixii:BAAANQAECgMIAwAAAA==.',
Sk='Skitzz:BAAANQAECgQICAAAAQ==.',
Sl='Slackr:BAAANQADCgUIBQAAAA==.Slackrm:BAAANQADCgMJBwAAAA==.Slackrp:BAAANQADCgQIBAAAAA==.Slashyr:BAAANQAECgQIDAAAAA==.Slimshadydh:BAAANQAECgQICwAAAA==.',
Sn='Snipez:BAAANQAECgIJAwAAAA==.Snortyhotorc:BAAANQAECgcICwAAAA==.Snortymcgoop:BAABNQAECn8sAAMZAAoKUBybIwAxAgAZAAgKihibIwAxAgATAAcK9xjCRQDOAQAAAA==.',
So='Solclipeus:BAABNQAECn9JAAMHAAoKqh/HBQBRAwAHAAkKaSHHBQBRAwADAAQKvhY0nQAaAQAAAA==.Soldh:BAAANQAECgUICwABNQAECgoKSQAHAKofAA==.Solku:BAAANQAECgUICgABNQAECgoKNwAEABsNAA==.Sollock:BAABNQAECn8ZAAICAAgKVxiPVQBiAQACAAgKVxiPVQBiAQABNQAECgoKSQAHAKofAA==.Solna:BAABNQAECn8dAAIKAAkKggnocgBfAQAKAAkKggnocgBfAQABNQAECgoKNwAEABsNAA==.Soulrecall:BAAANQAECgIIAwAAAA==.Soupz:BAABNQAECn8gAAIDAAgK4x99XQCAAgADAAgK4x99XQCAAgAAAA==.',
Sp='Sparadin:BAABNQAECn8eAAIHAAgK7wmGNgA0AQAHAAgK7wmGNgA0AQAAAA==.Spartacûs:BAAANQAECgQJBQABNQAECgoKIgAHAFciAA==.Spikore:BAAANQAECgEIAQAAAA==.Splitpeaz:BAAANQADCgcJBwAAAA==.',
Sq='Squrìtle:BAAANQAECgUICAAAAA==.',
Sr='Sririacha:BAAANQADCgUIBQABNQAECggIBwAFAAAAAA==.',
St='Stabbyjohn:BAAANQADCggICAAAAA==.Stabbypickle:BAAANQAECgcIDgABNQAECgoKLgAfADsmAA==.Stachelbeere:BAAANQADCgYIBgAAAA==.Steedvegeta:BAAANQAECgQIBAAAAA==.Stickybug:BAAANQAECgQIDwAAAA==.Strånge:BAAANQAECgYIBwAAAA==.Stìtch:BAACNQAFFH8iAAICAAcKmxxuAgC+AQACAAcKmxxuAgC+AQA1AAQKf0MAAgIACgruJZUEAK8DAAIACgruJZUEAK8DAAAA.Stítch:BAAANQADCgQIBAABNQAFFAcIIgACAJscAA==.',
Su='Sukiafaunias:BAAANQAECgEIAgAAAA==.Sukiafloras:BAAANQAECgMIAgAAAA==.Suldån:BAAANQAECggIDgAAAA==.Summondaddy:BAAANQADCgQIBQAAAA==.Sunfurious:BAABNQAECn8ZAAIgAAgKoRW1AgAIAgAgAAgKoRW1AgAIAgAAAA==.Suoop:BAAANQAECgYICwAAAA==.Supan:BAAANQADCgQIBAAAAA==.',
Sw='Swiftshaman:BAAANQAECgIIAgAAAA==.',
Sy='Synvaria:BAAANQAECgUIDQAAAA==.Syraice:BAAANQADCgUIBQABNQAECgoKOQAmALsZAA==.Syrare:BAAANQAECgIIAgAAAA==.Syvenari:BAAANQAECgQIDQAAAA==.',
['Sï']='Sïxx:BAAANQADCgMJAwABNQAECgMIAwAFAAAAAA==.',
Ta='Tachisan:BAAANQAECgQICAAAAA==.Taeril:BAAANQADCgQIBQAAAA==.Tamfam:BAAANQADCggJEAAAAA==.Tanburn:BAAANQADCgYICwAAAA==.Tanduinex:BAAANQADCgYIDAAAAA==.Tangal:BAAANQAECgIIAwAAAA==.Tankstabber:BAAANQADCgQIBQAAAA==.Tanplate:BAAANQADCgYICAAAAA==.Tarentia:BAAANQABCggIDgAAAA==.Tastytyrande:BAAANQAECgUIBQAAAA==.Tatsumy:BAABNQAECn8lAAIDAAgK+wvc1wBsAQADAAgK+wvc1wBsAQAAAA==.',
Tc='Tcmon:BAABNQAECn89AAMTAAoKRBtwIQBiAgATAAoKRBtwIQBiAgAZAAMK5Au3OQBuAAAAAA==.',
Te='Teachings:BAAANQADCgMIAwAAAA==.Teaglizzy:BAAANQADCgEIAQABNQAFFAMICQALAGIEAA==.Teehole:BAAANQAECgUICwAAAA==.Telihill:BAAANQADCgUIDgAAAA==.Telsarra:BAAANQAECgQIBgAAAA==.',
Th='Thalenia:BAAANQADCggIIgAAAA==.Thebeastelf:BAAANQAECgUIBwABNQAFFAUIDQARAJgcAA==.Thebigtuna:BAABNQAECn9BAAInAAoKRyQnAwCnAwAnAAoKRyQnAwCnAwAAAA==.Thegigatuna:BAAANQAECgcIBwAAAA==.Thekrisaning:BAAANQADCgYIDAAAAA==.Theladydruid:BAABNQAECn87AAIBAAoKnxPaHABNAgABAAoKnxPaHABNAgAAAA==.Thelnaris:BAAANQADCgEIAQAAAA==.Themeats:BAAANQADCgQIBAAAAA==.Thendezoth:BAAANQAECgEIAgAAAA==.Thighsoffel:BAAANQADCgcIEwAAAA==.Thirdtjme:BAAANQADCgYIBgAAAA==.Thordam:BAAANQAECgIIAgAAAA==.Thragmar:BAAANQADCgEIAQAAAA==.Thunderhóof:BAAANQABCgYIDQAAAA==.Thôr:BAAANQAECggICAAAAA==.',
Ti='Tierrasbest:BAAANQAECgEIAQAAAA==.Tigerpa:BAABNQAECn8cAAITAAUKlwl49QAXAQATAAUKlwl49QAXAQAAAA==.Tinkernut:BAAANQABCgIIAgAAAA==.Tinypally:BAAANQAECgEIAgAAAA==.Tinyraven:BAABNQAECn84AAInAAoK3xf6FgCnAgAnAAoK3xf6FgCnAgAAAA==.Tinysmites:BAAANQAECgMIAwAAAA==.Tinystotems:BAAANQAECgUIEQAAAA==.Tinythia:BAAANQADCgUIBQAAAA==.Tioklarus:BAABNQAECn9BAAIlAAkKpwihCwAqAQAlAAkKpwihCwAqAQAAAA==.Tipzy:BAAANQAECggICAAAAA==.Tisaryn:BAAANQAECgQIBAAAAA==.',
To='Tofulady:BAACNQAFFH8GAAIeAAMKIweoCAC1AAAeAAMKIweoCAC1AAA1AAQKfzcAAh4ACgoyHxoIAA8DAB4ACgoyHxoIAA8DAAAA.Tohu:BAAANQAECgYIDgAAAA==.Toshen:BAAANQADCgEIAQAAAA==.Totax:BAAANQAECgEIAQAAAA==.Totemtoker:BAAANQADCggIDQAAAA==.',
Tr='Tremors:BAAANQADCggICAAAAA==.Triggër:BAAANQABCgQIBAABNQAECgIIAgAFAAAAAA==.Tromb:BAAANQAECgMIAwAAAA==.',
Tu='Tucknroll:BAAANQADCgcIDAAAAA==.',
Tw='Twobithusler:BAAANQAECgIIAgAAAA==.Twoon:BAAANQADCgYICAAAAA==.Twoone:BAAANQADCgQIBAAAAA==.',
Ty='Tyniarstus:BAAANQADCgYICAAAAA==.',
Ud='Udderfiasco:BAAANQABCgIIAgAAAA==.',
Ug='Uggh:BAAANQADCgUIBQAAAA==.',
Un='Unholyslayer:BAAANQABCgIIAgAAAA==.Unhowly:BAACNQAFFH8MAAIIAAUKaBQhAgBJAQAIAAUKaBQhAgBJAQA1AAQKfzQAAggACgqIJQ8EAA4DAAgACgqIJQ8EAA4DAAAA.Unpoppable:BAAANQAECgcIEAAAAA==.',
Uz='Uzilok:BAAANQAECgcICgAAAA==.',
Va='Vaelyra:BAAANQADCgMIAwABNQAFFAIIBgABAI0RAA==.Vakir:BAABNQAECn8qAAIWAAoKLxQLPQAOAgAWAAoKLxQLPQAOAgAAAA==.Valmortem:BAEANQADCgcIEgAAAA==.Vapidos:BAAANQAECgMIBwAAAA==.Varynix:BAAANQAECgIIAgABNQAECgYIBwAFAAAAAA==.Vatica:BAAANQAECgcIBwAAAA==.',
Ve='Velanoria:BAAANQADCggICwAAAA==.Veldorai:BAAANQADCgYICwAAAA==.Velrenya:BAAANQADCgQIBgAAAA==.Velýndriel:BAAANQAECgUIDQAAAA==.Venvalzhar:BAABNQAECn8pAAMEAAkKxiA3GgALAwAEAAkKxiA3GgALAwAhAAIKoAL+cgBAAAAAAA==.Veralidaine:BAAANQAECgQIBgAAAA==.Vestammeni:BAABNQAECn8xAAMUAAoKoyGLBQAzAgAUAAoKoyGLBQAzAgAPAAcKJw/kwgB2AQAAAA==.Vexlore:BAAANQADCgYIBwAAAA==.',
Vi='Virus:BAAANQAECgcIBwAAAA==.Vixsaurion:BAAANQAECgEIAQAAAA==.',
Vo='Voltx:BAAANQAECgEIAQAAAA==.Vorn:BAAANQADCgcIBwAAAA==.Vow:BAABNQAECn8bAAIHAAcK6huoIADfAQAHAAcK6huoIADfAQAAAA==.',
Vy='Vynlenlor:BAAANQABCgIIAgAAAA==.',
Wa='Warmidget:BAAANQAECgEIAQAAAA==.',
Wc='Wckd:BAAANQAECgYIEgAAAA==.',
We='Weaksnow:BAABNQAECn8WAAIdAAkKuhH3RwA3AQAdAAkKuhH3RwA3AQABNQAFFAUIEQAKAJEUAA==.Weedgoku:BAAANQAECgQIBAAAAA==.Weedvegeta:BAABNQAECn8iAAIKAAoKDh3qQQABAwAKAAoKDh3qQQABAwAAAA==.Wernbirn:BAAANQAECggIAQAAAA==.Wetraman:BAAANQADCgIIAgABNQAECgQIBQAFAAAAAA==.Wetremin:BAAANQAECgQIBQAAAA==.',
Wh='Whirpy:BAABNQAECn8gAAMBAAoKvBjvEAAXAgABAAoKvBjvEAAXAgALAAEKAAC2vgAiAAAAAA==.Whisberis:BAAANQADCgMIAwAAAA==.Whitty:BAAANQADCgQIBAAAAA==.Whizkee:BAABNQAECn8UAAIhAAgKNw6QLQC5AQAhAAgKNw6QLQC5AQAAAA==.Whookies:BAAANQADCgMIAwABNQAECgYIBgAFAAAAAA==.',
Wi='Wildbeefwood:BAAANQAECgUICgAAAA==.Wingedlady:BAABNQAECn8bAAITAAkKXwsJTgCyAQATAAkKXwsJTgCyAQAAAA==.Wingss:BAACNQAFFH8FAAIDAAMKlh+wFAAQAQADAAMKlh+wFAAQAQA1AAQKfyoAAgMACgppIkUeAJcCAAMACgppIkUeAJcCAAAA.',
Wu='Wushu:BAAANQAECgQICgAAAA==.',
Wy='Wyl:BAABNQAECn8sAAIDAAkKzSMWDQANAwADAAkKzSMWDQANAwAAAA==.',
Xe='Xerath:BAAANQAECgUICwAAAA==.',
Xi='Xiing:BAABNQAECn86AAMUAAoKxhfvBgD/AQAUAAoKxhfvBgD/AQAPAAEKAAAyXgEpAAAAAA==.Xinei:BAAANQADCgQIAQAAAA==.Xinhe:BAAANQAECgIIAgAAAA==.',
Xn='Xneutron:BAABNQAECn8XAAIKAAgKeRfhdwBUAQAKAAgKeRfhdwBUAQAAAA==.',
Xt='Xtravagent:BAAANQADCgIIAgAAAA==.',
Xw='Xwhitesnow:BAAANQAECgEIAQAAAA==.',
Xy='Xyxia:BAAANQADCgcIBwAAAA==.',
Ya='Yaiie:BAABNQAECn9IAAMXAAgKGw9ABwAGAQAGAAcK+ww0CAAoAQAXAAgKqQ5ABwAGAQAAAA==.',
Yo='Yonna:BAAANQAECgMIAwAAAA==.',
Yu='Yunggrazydk:BAAANQADCggIDAABNQAECgYIFgAEAF8SAA==.Yungholy:BAABNQAECn8WAAIEAAYKXxLoigB1AQAEAAYKXxLoigB1AQAAAA==.Yungresto:BAAANQADCgQIBQABNQAECgYIFgAEAF8SAA==.Yuuki:BAAANQADCgcIBwABNQAECgEIAQAFAAAAAA==.Yuunggrazy:BAAANQADCggIEQABNQAECgYIFgAEAF8SAA==.',
['Yü']='Yüto:BAABNQAECn8qAAMTAAoKax/hHgAcAwATAAoKax/hHgAcAwAZAAQKshejVwDHAAAAAA==.',
Za='Zabuto:BAABNQAECn8dAAILAAkK8RTAQwDlAQALAAkK8RTAQwDlAQAAAA==.Zaeraciustv:BAAANQABCggIDwAAAA==.Zahäära:BAAANQAECgUIEQAAAA==.Zaldiz:BAAANQAECgEIAgAAAA==.Zar:BAAANQAECgcICwAAAA==.Zarathor:BAAANQADCgQIBAABNQAECggIEgAFAAAAAA==.Zarrtan:BAAANQAECgIIAQAAAA==.Zazevo:BAAANQAECgUIDQAAAA==.Zazlock:BAAANQAECgIIAgAAAA==.Zazmo:BAAANQADCgUIBQAAAA==.Zazprie:BAABNQAECn8WAAMhAAcKkwzWUADOAAAhAAcKkwzWUADOAAAEAAQKvARpngCOAAAAAA==.',
Ze='Zendrozath:BAAANQADCgQIBQABNQAECgQIBgAFAAAAAA==.',
Zi='Zippyzap:BAAANQAECgEIAQAAAA==.',
Zo='Zooz:BAAANQADCgIIAgAAAA==.',
Zu='Zual:BAAANQAECgQIBgAAAA==.Zularraka:BAAANQAECgUIDwAAAA==.',
Zx='Zxeý:BAAANQADCgcIDgAAAA==.',
['Äb']='Äbracadabruh:BAABNQAECn8dAAMKAAgKiBeWvAALAgAKAAcKthSWvAALAgAJAAIKXSD0NgBgAAABNQAECgoKFwAdAAEMAA==.',
['Äl']='Älissia:BAAANQAECgEIAgAAAA==.',
['Ål']='Ålexthegrëat:BAAANQAECgQIBQABNQAECgoKLwAKADgOAA==.',
['Èm']='Èmandy:BAAANQADCggIDQAAAA==.',
['Ën']='Ëndo:BAABNQAECn8vAAQIAAkKzxpDIgC9AgAIAAkKrRpDIgC9AgAWAAQK6RIXhADsAAAMAAIKfQqlbwBxAAABNQAECgoKKQAPAP4SAA==.',
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
