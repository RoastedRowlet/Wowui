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

local lookup = {'Shaman-Restoration','Unknown-Unknown','Hunter-BeastMastery','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Warrior-Arms','Druid-Balance','Evoker-Devastation','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Vengeance','DemonHunter-Devourer','Mage-Arcane','DeathKnight-Frost','Mage-Frost','Priest-Shadow','DeathKnight-Unholy','Warrior-Protection','Evoker-Preservation','Rogue-Subtlety','Hunter-Marksmanship','Paladin-Retribution','Rogue-Assassination','Paladin-Holy','Priest-Holy','Mage-Fire','Druid-Guardian','Priest-Discipline','Evoker-Augmentation','Paladin-Protection','Hunter-Survival','Shaman-Enhancement','Druid-Restoration','Druid-Feral','Monk-Brewmaster','Monk-Windwalker',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aadrisedh:BAAANQAECgMIAwAAAA==.Aaeryn:BAAANQAECgEIAQAAAA==.Aaliyshaa:BAAANQAECgUICQAAAA==.Aanorim:BAAANQADCgMIBgAAAA==.Aaramis:BAABNQAECn8lAAIBAAkKcRUCQQBaAgABAAkKcRUCQQBaAgAAAA==.',
Ab='Abrakadabruh:BAAANQAECgQICwAAAA==.Abyssal:BAAANQAECgcIEwAAAA==.',
Ac='Achin:BAAANQADCgYICgAAAA==.',
Ad='Adanbad:BAAANQADCggICAAAAA==.',
Ae='Aelanthir:BAAANQAECgYICQAAAA==.Aellwyn:BAAANQAECgEIAQABNQAECggICAACAAAAAA==.',
Ai='Aidoffhealer:BAAANQADCgUIBgAAAA==.',
Al='Alariah:BAAANQADCgMIAwAAAQ==.Aldoraline:BAAANQADCggIEAAAAA==.Alfredstare:BAAANQADCgcIBwAAAA==.Alliancewar:BAAANQADCgEIAQAAAA==.Alordros:BAAANQADCgcIGwAAAA==.Alystair:BAAANQADCgYIBgABNQAECgUIBwACAAAAAA==.',
Am='Amadayus:BAABNQAECn8jAAIDAAkKuSVgAgDgAwADAAkKuSVgAgDgAwAAAA==.Ambellina:BAAANQAECgUICQAAAA==.',
An='Anaria:BAAANQADCgUIBQAAAA==.Anduinz:BAAANQAECgQIBQAAAA==.',
Ar='Aranyssa:BAACNQAFFH8FAAMEAAUKkQk7GwAfAQAEAAQKwAs7GwAfAQAFAAEKNAXWCgBRAAA1AAQKfz8ABAUACQp4GmwMAJgBAAQACAqVGs9VAFECAAUABQp/F2wMAJgBAAYAAQrJGcxsAEQAAAAA.Archiball:BAAANQAECggICAAAAA==.Arclock:BAAANQAECgQICAAAAA==.Arconnai:BAABNQAECn8zAAIHAAkKNSCGOwDWAgAHAAkKNSCGOwDWAgAAAA==.Areilin:BAAANQAECgQIBAAAAA==.Areiotyrict:BAAANQAECgMIBAAAAA==.Arnøld:BAAANQAECgQIBQAAAA==.Arrnac:BAAANQADCgYIBgAAAA==.',
As='Asham:BAAANQADCgYIGQAAAA==.Asiago:BAAANQAECgQIEAABNQAECgkJIwAIAOgcAA==.Asondra:BAAANQADCgMIAwAAAA==.Aspect:BAAANQAECgUIBwAAAA==.',
Av='Avvalethra:BAAANQAECgYIEwAAAA==.',
Az='Azdoroth:BAAANQADCgMIAwAAAA==.Azenet:BAAANQAECgQJCAABNQAFFAYIEQAJAIgWAA==.',
Ba='Babyball:BAAANQAECgIIAgAAAA==.Bainefreeze:BAAANQAECgcIDQAAAA==.Balancedtech:BAAANQAECgEIAQAAAA==.Bananataffy:BAAANQADCgUIBQAAAA==.Barackoshama:BAABNQAECn8oAAIKAAgKlhi3TQA9AgAKAAgKlhi3TQA9AgAAAA==.Barkimadog:BAAANQAECgMIAwAAAA==.Battle:BAAANQADCgIIAgAAAA==.Baw:BAAANQAECgcIDgAAAA==.',
Be='Bearlinwall:BAAANQAECgEIAQAAAA==.Bearmaster:BAAANQAECgUIEgAAAA==.Belacc:BAAANQADCggIEwAAAA==.Belfiyajr:BAAANQAECgcICgAAAA==.Bereaved:BAAANQADCgUIBQAAAA==.',
Bi='Biggiebertha:BAAANQAECgcIEAAAAA==.Bighooves:BAAANQADCgIIAgAAAA==.Bigskymage:BAAANQAFFAEIAQAAAA==.Billybones:BAAANQAECgQIDgAAAA==.Bimbobaby:BAAANQABCgEIAQAAAA==.',
Bl='Blackholes:BAAANQAFFAEIAQAAAA==.Blackwÿn:BAAANQADCggIFgABNQAECgYIEAACAAAAAA==.Bladeblade:BAAANQAECggIEwABNQAECgkJNAAHAAoiAA==.Bladedozzer:BAAANQAECgQICAAAAA==.Blindinglite:BAABNQAECn8pAAILAAkKqB3zEgADAwALAAkKqB3zEgADAwAAAA==.Bloodhaze:BAABNQAECn8aAAILAAkKlyNLGADVAgALAAkKlyNLGADVAgAAAA==.Bloodline:BAAANQAECggIAgAAAA==.Blueorange:BAAANQAECggICAAAAA==.',
Bo='Bodizzle:BAAANQADCggIHgAAAA==.Bombil:BAAANQADCgYIEgAAAA==.Boombastique:BAAANQAECgMIAwAAAA==.Bootychaser:BAAANQADCgUIBQAAAA==.Borestus:BAAANQADCgUJBwAAAA==.',
Br='Brchm:BAAANQAECgQIDQAAAA==.Brickly:BAABNQAECn8ZAAMLAAkKqB0uHgClAgALAAgKqB0uHgClAgAMAAEKAABkLQBJAAAAAA==.Brieter:BAAANQADCgYICgABNQAECgkJIwAIAOgcAA==.Broncolock:BAAANQADCggICAAAAA==.Brotheldog:BAAANQADCgUIBQAAAA==.Brutusx:BAAANQAECgQIBwAAAA==.',
Bu='Bulaktheliar:BAAANQADCgcIGQAAAA==.Bullzi:BAAANQAECgIIAgAAAA==.',
Bx='Bxxberry:BAAANQAECgQIBQAAAA==.',
['Bê']='Bêrserk:BAAANQADCgQIBAABNQAECgkJKQABABIZAA==.',
['Bú']='Búkki:BAAANQADCgYIHAAAAA==.',
['Bü']='Bükkì:BAAANQADCggIEAAAAA==.Bükkï:BAAANQADCgcIEQAAAA==.',
Ca='Caboodles:BAABNQAECn8YAAMGAAcK3QUvNADyAAAGAAYKPwUvNADyAAAEAAYKZQQk7QDqAAAAAA==.Cachamama:BAAANQAECgIIAgAAAA==.Camishami:BAAANQAFFAEIAQAAAA==.Candyhandz:BAAANQADCgUIDAABNQAECgUIDAACAAAAAA==.Carmane:BAAANQADCgEIAQAAAA==.Carsher:BAAANQADCgYIBgAAAA==.Cassander:BAAANQADCgYIBgAAAA==.Casstyelle:BAAANQADCgEIAQABNQAECgkJKQABABIZAA==.Catharsis:BAAANQAECgEIAQAAAA==.',
Ce='Ceraph:BAAANQADCgUIBgAAAA==.Cexiback:BAABNQAECn8xAAINAAkKkx28CgAuAwANAAkKkx28CgAuAwAAAA==.Cexifist:BAAANQAECgQIBQAAAA==.',
Ch='Chancew:BAAANQADCgQIBAAAAA==.Cheebsz:BAAANQADCgYIDgAAAA==.Cheesus:BAABNQAECn8jAAIIAAkK6BylFwAIAwAIAAkK6BylFwAIAwAAAA==.Chicharon:BAABNQAECn8fAAIOAAcKPw+A7QCsAQAOAAcKPw+A7QCsAQAAAA==.Chillfrost:BAAANQADCgEIAQAAAA==.Chingazossal:BAAANQAECgYIDwAAAA==.Chokolock:BAAANQAECggIDwABNQAECgkJJwAPAPwUAA==.Chunggus:BAAANQABCgYICQAAAA==.Churva:BAABNQAECn8fAAMBAAkKBwjLnwAzAQABAAgKIAbLnwAzAQAKAAYKVgbXuQAaAQAAAA==.',
Co='Coko:BAAANQAECgUIBQABNQAECgkJJgADANQbAA==.Condemned:BAAANQADCgYIDAAAAA==.Coochie:BAAANQAECgMIAwAAAA==.Cosecantes:BAABNQAECn8bAAMQAAUKUx+tDQDRAQAQAAUKUx+tDQDRAQAOAAIKDQM6sAFYAAAAAA==.Cowdozer:BAAANQADCggICwABNQAECgkJIwADAD4YAA==.Cowtools:BAAANQADCgQIBAAAAA==.',
Cr='Crackjones:BAAANQAECgYICAAAAA==.Crisgmt:BAAANQAECgQIBQAAAA==.Crism:BAAANQAECgQIBQAAAA==.Crismtg:BAAANQAECgYIEwAAAA==.Critsandgigg:BAAANQADCgYIBwAAAA==.Crusäderaura:BAAANQAECgYIEAAAAA==.Cryptìc:BAACNQAFFH8JAAIRAAQKxhOTCgBHAQARAAQKxhOTCgBHAQA1AAQKfx8AAhEACQoDIXsQAO4CABEACQoDIXsQAO4CAAE1AAQKCQkkAA4AByEA.Cryptîc:BAABNQAECn8kAAMOAAkKByHGMwAjAwAOAAkKgx7GMwAjAwAQAAMKwCFKGQAqAQAAAA==.',
Da='Dabbia:BAABNQAECn8dAAQFAAkKUhxjCgDQAQAFAAYKJR5jCgDQAQAEAAQKfB74ygAvAQAGAAQKMxdgMQAAAQAAAA==.Dabhill:BAAANQADCgIIAgAAAA==.Daedleus:BAAANQAECgcICQAAAA==.Damara:BAAANQADCgYIBgAAAA==.Damented:BAAANQADCggIEQABNQAECgkJKQABABIZAA==.Dandaris:BAAANQAECgEIAQAAAA==.Darkfugg:BAAANQADCgUICgAAAA==.Darood:BAAANQADCggIHgAAAA==.Dasmilnti:BAAANQAECgUIBQAAAA==.Dawnchild:BAAANQAECgIIAgAAAA==.Dazdraperma:BAAANQAECgIIBAAAAA==.',
De='Deadvocate:BAAANQAECgQICgAAAA==.Deathballz:BAABNQAECn8nAAMPAAkK/BSjLQAuAgAPAAkK/BSjLQAuAgASAAIKxwaTygBTAAAAAA==.Declake:BAAANQADCgMIAwAAAA==.Deeznugs:BAAANQAECgMIBQAAAA==.Delthrus:BAAANQAECgQIBwABNQAECggIJAATAL4OAA==.Demonarc:BAABNQAECn8eAAINAAkK2RSxGwB2AgANAAkK2RSxGwB2AgAAAA==.Detreset:BAABNQAECn8ZAAIUAAkKaRgbEQCWAgAUAAkKaRgbEQCWAgAAAA==.Devocate:BAAANQADCgEIAQAAAA==.Devomorph:BAAANQADCgcIBwAAAA==.',
Di='Dinguskhaan:BAABNQAECn8WAAIOAAgKSAcj/gCOAQAOAAgKSAcj/gCOAQAAAA==.Dinkles:BAAANQADCgcIEAAAAA==.Dinkys:BAAANQAECgEIAQABNQAECgYIEgACAAAAAA==.Dinsum:BAAANQADCgUIBQAAAA==.Dirtytaint:BAAANQAECgQJBgABNQAECgkJLQAVAFIkAA==.Disorder:BAAANQAECgEIAQAAAA==.Dixonbuttsz:BAAANQADCgcIBwAAAA==.',
Dk='Dkballz:BAAANQAECgEIAQABNQAECgkJLQAVAFIkAA==.',
Do='Doflamingo:BAAANQABCgEIAQAAAA==.Doldion:BAAANQADCgUICQAAAA==.Donkypunch:BAAANQADCgEIAQAAAA==.Donut:BAAANQAECgIIAgABNQABCgIIAgACAAAAAA==.Dotnrun:BAAANQADCgEJAQAAAA==.',
Dr='Dragonhamer:BAAANQADCgYICAAAAA==.Dragtiago:BAAANQADCgYIDgAAAA==.Drakarys:BAAANQADCgIIAgAAAA==.Dred:BAAANQADCgcIBwAAAA==.Drexybear:BAABNQAECn8VAAIWAAgK2BdoIgA3AgAWAAgK2BdoIgA3AgAAAA==.Drezbi:BAAANQAECgEIAgAAAA==.Droodmon:BAAANQADCgEIAQAAAA==.Drunkenmaste:BAAANQADCgYIBgAAAA==.',
Du='Dunbarth:BAABNQAECn8nAAIXAAkKbA23lgDxAQAXAAkKbA23lgDxAQAAAA==.Durzaka:BAAANQAECgUICQAAAA==.Durzu:BAAANQAECgQIDgAAAA==.Duty:BAAANQAECgIIAgAAAA==.',
['Dà']='Dàrkfate:BAAANQAECgUICQAAAA==.',
Ea='Earthdozzer:BAAANQADCgMIAwAAAA==.',
Ec='Echohavo:BAAANQAECgMIBgAAAA==.',
Ef='Eff:BAABNQAECn8uAAMYAAkKixHjKQA/AgAYAAkKPBHjKQA/AgAVAAYKRAqsMQAqAQAAAA==.',
Eg='Eggy:BAAANQAECggIBgAAAA==.Egholom:BAABNQAECn8qAAILAAkKAhC+OwDTAQALAAkKAhC+OwDTAQAAAA==.',
Ek='Eks:BAAANQADCgUIBQAAAA==.',
El='Electrcfrost:BAABNQAECn8pAAIKAAkK1hmiLQDEAgAKAAkK1hmiLQDEAgABNQAECgkJLwAIAEccAA==.Elkanàh:BAABNQAECn8jAAMXAAkKMRkIaQBdAgAXAAgKMRkIaQBdAgAZAAcK7xqpTAA0AgABNQAFFAYIDwAaAAoVAA==.Elorene:BAABNQAECn8dAAMbAAgK0QfNAwCVAQAbAAgKowfNAwCVAQAOAAYK/wFahAG2AAAAAA==.Elunara:BAAANQAECgcIDwABNQAFFAUIBQAEAJEJAA==.Elyysian:BAACNQAFFH8KAAIRAAUKyRZoCACDAQARAAUKyRZoCACDAQA1AAQKfysAAxEACQo8JIQEAI4DABEACQo8JIQEAI4DABoAAwqWA17iAHcAAAAA.',
Em='Emokitten:BAAANQAECgEIAQAAAA==.Emptor:BAAANQAECgIIAwAAAA==.',
Er='Erebeius:BAAANQADCgMIAwAAAA==.Ereleb:BAAANQADCgUIBQAAAA==.',
Es='Escanör:BAAANQADCgIIAgABNQAECgUIBwACAAAAAA==.Esil:BAAANQADCgUIBQAAAA==.Espresso:BAAANQADCgcIBwAAAA==.Essekk:BAACNQAFFH8LAAIOAAUKGx/sGACtAQAOAAUKGx/sGACtAQA1AAQKfyIAAw4ACQp/Iqc5ABQDAA4ACQp/Iqc5ABQDABAAAQosFxw9AEkAAAAA.',
Ev='Evasivem:BAAANQADCgQIBAAAAA==.Event:BAAANQADCgYIBgAAAA==.',
Ew='Ewoo:BAABNQAECn8XAAIBAAYKlxpQaQDMAQABAAYKlxpQaQDMAQABNQAECggIJAAcAGAlAA==.',
Ex='Executtioner:BAAANQADCggJDQAAAA==.Explicit:BAAANQADCgYIBgAAAA==.Expression:BAAANQAECgUIBQABNQAECggIJAAcAGAlAA==.',
Fa='Fadam:BAAANQAECgYIEwAAAA==.Faei:BAAANQADCgUICAAAAA==.Failtank:BAAANQADCgEIAQAAAA==.Famjam:BAAANQAECggIBgAAAA==.Fatigue:BAAANQAECgEIAQAAAA==.Fatpo:BAABNQAECn8XAAQaAAgK2hzvaADfAQAaAAcK3xvvaADfAQARAAQKkR51OgBQAQAdAAEKBSDSIQBUAAABNQAECgkJGQALAKgdAA==.Fazy:BAAANQADCgYIEAAAAA==.',
Fe='Feldrakka:BAAANQADCgMIBAAAAA==.Felgore:BAAANQADCgQIBAAAAA==.',
Fi='Finality:BAABNQAECn8pAAIOAAkKSxvacwCWAgAOAAkKSxvacwCWAgAAAA==.Fizzey:BAAANQADCgYIBgAAAA==.',
Fl='Flexo:BAAANQADCgUIBQAAAA==.Flirtatious:BAACNQAFFH8MAAIKAAQKbg4xFAAsAQAKAAQKbg4xFAAsAQA1AAQKfxcAAgoACQo+Fd1HAFMCAAoACQo+Fd1HAFMCAAAA.Floriyana:BAAANQAECgIIBgAAAA==.',
Fo='Forsakenvoid:BAAANQADCgQIBAAAAA==.Fortknight:BAAANQADCgUIBQABNQAECgkJNgAOAIchAA==.Fourpriest:BAAANQAECgIIAgAAAA==.Foô:BAABNQAECn8qAAMYAAkKbx12DgALAwAYAAkKbx12DgALAwAVAAUKHBI4MgAmAQAAAA==.',
Fr='Freehands:BAAANQADCgIIAgAAAA==.Frizza:BAAANQAECgEIAgAAAA==.Frostpaw:BAAANQABCgIIAgAAAA==.',
Fu='Fudead:BAAANQAECgMIAwAAAA==.Fugarra:BAAANQAECgUICAABNQAECggICAACAAAAAA==.Furyrosa:BAAANQADCggICgAAAA==.Fuzi:BAAANQADCgMIAwABNQADCggICAACAAAAAA==.',
Fy='Fyah:BAABNQAECn8eAAIXAAkK/xpXVgCPAgAXAAkK/xpXVgCPAgABNQAFFAYIFQADABUZAA==.Fyaza:BAAANQADCggICQABNQAFFAYIFQADABUZAA==.',
Ga='Gaga:BAAANQADCgIIAgAAAA==.Gargamels:BAAANQAECgUIBgABNQAECggICAACAAAAAA==.Garou:BAAANQAECgQIBQAAAA==.',
Ge='Geekyshaman:BAAANQAECgMIAwAAAA==.Genesis:BAAANQAECggIDQAAAA==.Gerttie:BAAANQAECgcIEwAAAA==.',
Gg='Ggoottss:BAAANQADCgYIDQAAAA==.',
Gi='Gingdrac:BAACNQAFFH8WAAIUAAcKtRBxBQAKAgAUAAcKtRBxBQAKAgA1AAQKfyMAAhQACQpMH6INAMsCABQACQpMH6INAMsCAAAA.',
Go='Gobsquadp:BAAANQAECgUIDwABNQAECggIJAAcAGAlAA==.',
Gr='Grassmoker:BAAANQAECgUIBwAAAA==.Grek:BAAANQAECgcIDQABNQAECgkJJwAeAFMeAA==.Grievex:BAABNQAECn8nAAIXAAgKrgkKwwCQAQAXAAgKrgkKwwCQAQAAAA==.Grimbladez:BAAANQADCgYICgAAAA==.Grololo:BAAANQADCgcIIAAAAA==.Grozloo:BAAANQADCgMIAwAAAA==.Grumpel:BAAANQADCgYICgAAAA==.',
Gu='Guzzlr:BAAANQAECgYIBwAAAA==.',
Ha='Habeebe:BAAANQAECgUIDQABNQAFFAIKBQAWAF4MAA==.Hagen:BAAANQADCgYIBgAAAA==.Hammerrhoid:BAAANQADCgEIAQAAAA==.Hanyu:BAAANQADCggICAAAAA==.Harryoneeye:BAAANQAECgEJAQAAAA==.Haydezz:BAAANQAECgIIAgAAAA==.',
Hb='Hbots:BAAANQAECgQIBAAAAA==.',
He='Healthiss:BAABNQAECn8qAAIaAAkK8xx2GAATAwAaAAkK8xx2GAATAwAAAA==.Heelz:BAAANQADCgMIBAAAAA==.Hemolock:BAAANQAECgIIAgABNQAFFAYICwAXACkOAA==.Hemostasis:BAACNQAFFH8LAAIXAAYKKQ5HBwDWAQAXAAYKKQ5HBwDWAQA1AAQKfzAABBcACQomI5IWAGkDABcACQomI5IWAGkDABkAAQqCGB8UAUYAAB8AAQodFs5rADgAAAAA.Herjä:BAAANQAECgQIDAAAAA==.Hexem:BAAANQADCgYIBwABNQADCggIDQACAAAAAA==.Hexoon:BAAANQAECgQIDAAAAA==.',
Ho='Homeslice:BAABNQAECn8XAAQFAAcK5RErFAAEAQAFAAQKtBMrFAAEAQAEAAQKGQmlBQG6AAAGAAIKQRSCVQB9AAAAAA==.',
Hu='Hukeg:BAAANQADCgQIBAAAAA==.Huntweak:BAAANQADCggICQAAAA==.Huun:BAABNQAECn8oAAIgAAkKOB9HAgAkAwAgAAkKOB9HAgAkAwAAAA==.',
Hy='Hyasynthia:BAAANQADCgIIAgAAAA==.Hycindraeda:BAAANQADCgcJBwAAAA==.',
Ia='Iamgabrielsj:BAABNQAECn8tAAMEAAcKvgdXuABYAQAEAAcKvgdXuABYAQAGAAMKtASYUwCCAAAAAA==.',
Id='Idontdps:BAAANQADCgYIBwAAAA==.',
Im='Imphetamine:BAAANQAECggICAAAAA==.',
In='Inayasha:BAAANQADCgUIBQAAAA==.',
Ir='Irrenadro:BAABNQAECn82AAIXAAkKhA/UkQD8AQAXAAkKhA/UkQD8AQAAAA==.',
Is='Islandhunter:BAAANQABCgQJBAAAAA==.',
Iy='Iyahna:BAAANQAECgQIBgAAAA==.',
Ja='Jabaru:BAAANQADCgQIBAAAAA==.Jaypee:BAAANQAECgUICwAAAA==.',
Je='Jeage:BAAANQAECgQIBQABNQAECgkJIAAKAJ4iAA==.Jera:BAAANQADCgIIAgAAAA==.',
Ji='Jimboslice:BAAANQADCgQIBAAAAA==.Jimmoh:BAAANQAECgQIBQABNQAECggIGwAhAGgiAA==.Jimmybones:BAAANQABCgIIAgAAAA==.',
Jk='Jkn:BAAANQADCgcIBwAAAA==.',
Jo='Joes:BAABNQAECn8eAAIDAAcKCxyFaQA+AgADAAcKCxyFaQA+AgAAAA==.Jonesy:BAAANQAECgQIBQAAAA==.Jormingon:BAAANQADCgYIBwAAAA==.',
Ju='Juicygossip:BAAANQADCggIFgAAAA==.',
Ka='Kalabar:BAAANQADCgEIAQAAAA==.Kanada:BAAANQAFFAIIAgABNQAFFAgIHAAXAHEZAA==.Kanikitddon:BAAANQADCgIJAgAAAA==.Katanya:BAAANQAECgIIAgABNQAFFAUIBQAEAJEJAA==.',
Ke='Keetra:BAACNQAFFH8QAAIDAAUKABQADACLAQADAAUKABQADACLAQA1AAQKfx4AAgMACQrkHwstAOUCAAMACQrkHwstAOUCAAAA.Keiriline:BAAANQAECgYIEwAAAA==.',
Ki='Killbreed:BAAANQAECgEIAQAAAA==.Kinkster:BAAANQADCgUIBQAAAA==.Kioshiro:BAAANQADCgQIBAAAAA==.',
Kl='Klix:BAAANQADCgQJBAABNQAECgUIDAACAAAAAA==.',
Kn='Knight:BAABNQAECn8bAAMOAAkKnB3YcACcAgAOAAgKnB3YcACcAgAbAAIKzAi8CQBoAAAAAA==.Knuggz:BAAANQAECgcIDAAAAA==.',
Ko='Korya:BAAANQADCgEIAQAAAA==.',
Kr='Kratoswrath:BAAANQAECgEIAQAAAA==.',
Ku='Kubluk:BAAANQAECgIIAgAAAA==.Kumbustinher:BAAANQADCgcIEQAAAA==.',
Ky='Kyledh:BAAANQADCggICAABNQAFFAMIBwAaAOElAA==.Kylepala:BAAANQAECgYIBgABNQAFFAMIBwAaAOElAA==.Kylepriest:BAACNQAFFH8HAAIaAAMK4SU5FQBQAQAaAAMK4SU5FQBQAQA1AAQKfy0AAxoACQp2JrUBANEDABoACQp2JrUBANEDAB0AAgopIxoXALwAAAAA.Kyntamun:BAAANQADCgYIBgABNQADCgcIDAACAAAAAA==.',
['Kã']='Kãyron:BAAANQADCggICQAAAA==.',
La='Laiselora:BAAANQADCgEIAQAAAA==.Lamashtuu:BAAANQADCgIIAgABNQAECgUIDAACAAAAAA==.Lambeáu:BAAANQAECgYIDAAAAA==.Lambrusca:BAAANQADCgcIBwAAAA==.Lamda:BAAANQAECgUIBwAAAA==.Lamdadk:BAAANQADCggICQAAAA==.Landistis:BAAANQADCgYICwAAAA==.Lanstoll:BAAANQAECggIDgAAAA==.Larcisong:BAAANQAECgYIDgAAAA==.Larzoe:BAAANQADCgUIBQABNQAECgkJKgALAC8hAA==.Larzoh:BAABNQAECn8qAAMLAAkKLyETDABIAwALAAkKLyETDABIAwANAAMKJQZuWACdAAAAAA==.Lateesha:BAAANQAECgUICgAAAA==.Lavac:BAAANQAECgEIAQAAAA==.',
Le='Lethargy:BAAANQADCgUICQAAAA==.Levapally:BAAANQADCgUICAAAAA==.',
Li='Lidorila:BAAANQADCgMICAAAAA==.Lightguard:BAABNQAECn8lAAIXAAgK/RYJiQAPAgAXAAgK/RYJiQAPAgAAAA==.Lightinburn:BAAANQADCgQIBAAAAA==.Lilithiel:BAAANQAFFAUIBAAAAA==.Lilplottwist:BAABNQAECn8eAAIDAAcK0AMT1ABTAQADAAcK0AMT1ABTAQAAAA==.Lilwiz:BAAANQAECgQIBAAAAA==.Linalala:BAABNQAECn9xAAQiAAgKtCZwAwCPAwAiAAgKtCZwAwCPAwAjAAcKqRF9FACvAQAIAAIKLAx1lwB1AAAAAA==.Linnxp:BAAANQAECgIIAgABNQAECgQIAwACAAAAAA==.Linnxs:BAAANQAECgQIAwAAAA==.Linnxvx:BAAANQAECgEIAQABNQAECgQIAwACAAAAAA==.Lishp:BAAANQADCgYIBgAAAA==.Literacola:BAAANQAECgYIDgAAAA==.',
Lo='Lorino:BAAANQAECgEIAQAAAA==.Lothaire:BAAANQABCgIIAgAAAA==.',
Lu='Lubaduba:BAAANQADCggIDQAAAA==.Lugeya:BAAANQAECgUIBQAAAA==.Lugeyamnk:BAAANQAECgQIBgAAAA==.Lumenadiel:BAAANQAECgEJAQAAAA==.Lumyna:BAAANQAECgEIAQAAAA==.Lustnbeiber:BAABNQAECn8oAAQKAAkKwhW8QQBrAgAKAAkKwhW8QQBrAgABAAYK4AuYrAATAQAhAAEKgwItNwAwAAAAAA==.Lustpls:BAAANQABCgUIBQAAAA==.Luuciferr:BAAANQAECgYIDAAAAA==.Luv:BAAANQADCgQIBAAAAA==.',
Ly='Lyncha:BAAANQAECggICAABNQAECggIIAAfAOkjAA==.Lynchà:BAABNQAECn8gAAIfAAgK6SOgBwAmAwAfAAgK6SOgBwAmAwAAAA==.',
Ma='Maakun:BAABNQAECn8qAAIaAAkKYBYnPQByAgAaAAkKYBYnPQByAgAAAA==.Maddevil:BAAANQADCggIEwAAAA==.Magawarrior:BAAANQADCgQICQAAAA==.Mahoragga:BAAANQAECgMIAwAAAA==.Mahzad:BAABNQAECn8sAAMBAAkKBCGWFgAaAwABAAkKBCGWFgAaAwAKAAUKPh4GdQC+AQAAAA==.Malchezaar:BAAANQAECgUICQAAAA==.Malfrun:BAABNQAECn8kAAITAAgKvg6jFwCvAQATAAgKvg6jFwCvAQAAAA==.Marinnite:BAAANQADCgYIBgAAAA==.Marox:BAABNQAECn8nAAIOAAkKyhq2awCnAgAOAAkKyhq2awCnAgAAAA==.Marrøwgar:BAAANQAECgUIDgAAAA==.Mathrim:BAACNQAFFH8IAAMEAAMKBRs+JgDTAAAEAAIKtyM+JgDTAAAGAAEKoQkgHwBKAAA1AAQKfywAAwQACQpZJd8DALkDAAQACQpZJd8DALkDAAYAAgqOFZpTAIIAAAAA.Matooka:BAAANQAECgYIEwAAAA==.Maynji:BAAANQADCggICAAAAA==.',
Mc='Mcthugger:BAAANQADCgYIEAABNQAECgkJIQAXAPEWAA==.',
Mi='Miinthara:BAAANQADCgEIAQAAAA==.Minithril:BAAANQADCgUICAAAAA==.Misspetite:BAAANQADCgYJEgAAAA==.Mitskii:BAAANQADCgMIAwAAAA==.',
Mo='Mojosmiles:BAAANQADCgQIBAAAAA==.Mojosmilês:BAAANQAECgEIAQAAAA==.Mokxî:BAAANQAECgEIAQAAAA==.Molodeath:BAAANQAECgUIDgAAAA==.Mommÿ:BAACNQAFFH8FAAIaAAIKwhbvJgCWAAAaAAIKwhbvJgCWAAA1AAQKfzAAAxoACQrdG5wnAMkCABoACQrdG5wnAMkCAB0ABgpIDJ4QAB0BAAAA.Moneymage:BAAANQAECgQIBAAAAA==.Monkgroom:BAAANQAFFAEIAQAAAA==.Montra:BAABNQAECn8tAAIcAAkKoBPlFgD3AQAcAAkKoBPlFgD3AQAAAA==.Moogaag:BAAANQADCgEIAQABNQAECgkJJgADANQbAA==.Moolificent:BAAANQAECgYIEgAAAA==.Moonrina:BAAANQADCgIIAgAAAA==.Moonshea:BAAANQAECggICAAAAA==.Morgaine:BAAANQADCgUIBgAAAA==.Motorinkashi:BAAANQAECgcIEQAAAA==.',
Mu='Muddbane:BAAANQADCgQIBAABNQAECggILAAYAF4XAA==.Muddgore:BAAANQADCggIDgABNQAECggILAAYAF4XAA==.Muddthir:BAAANQADCgQIBAABNQAECggILAAYAF4XAA==.Murong:BAAANQAECgEIAQAAAA==.Mustardmage:BAAANQAECgcIDwABNQAECgkJNwADALkhAA==.',
My='Myzarei:BAAANQAECgUICwAAAA==.',
['Mø']='Møkxi:BAAANQADCggICAAAAA==.',
['Mû']='Mûdd:BAABNQAECn8sAAMYAAgKXhfBJgBTAgAYAAgKXhfBJgBTAgAVAAQKdhM6NwD5AAAAAA==.',
Ne='Nebur:BAAANQADCgUICQAAAA==.Neebsz:BAAANQADCgQIBAAAAA==.Nestaah:BAAANQADCgYICwAAAA==.Nethender:BAAANQAECgEIAQAAAA==.Newtlid:BAAANQAECgYIBwAAAA==.',
Ni='Nirath:BAABNQAECn8pAAIOAAkK3Q7dqwApAgAOAAkK3Q7dqwApAgAAAA==.Nisia:BAAANQAECggIDwABNQAECgkJNAAHAAoiAA==.Nito:BAABNQAECn8lAAIPAAkKGBEXMwANAgAPAAkKGBEXMwANAgAAAA==.',
No='Nohkano:BAABNQAECn8zAAIkAAkKOSZZAADxAwAkAAkKOSZZAADxAwAAAA==.Nokt:BAAANQAECgYICAAAAA==.Norrbert:BAAANQADCgcIBwAAAA==.Norriz:BAAANQAECgcIDgAAAA==.Noveerra:BAAANQADCgcIDAAAAA==.',
Nu='Numbuh:BAAANQAECgQIBwAAAA==.Nusix:BAAANQADCggIIAAAAA==.',
Oa='Oakremi:BAAANQADCgMIAwAAAA==.Oakrogue:BAAANQADCggIHwAAAA==.',
Od='Odysseusxap:BAAANQADCgIIAgAAAA==.',
Ol='Oldirtytank:BAAANQADCgMIAwAAAA==.',
On='Oneshothel:BAAANQADCgEIAQAAAA==.',
Or='Ortillious:BAAANQAECgQIBAABNQAECgYIDAACAAAAAA==.',
Ov='Overdoze:BAAANQADCgUIEQAAAA==.Overkill:BAAANQAECggICgAAAA==.',
Pa='Painwhisper:BAAANQABCgQJBAAAAA==.Paladeez:BAAANQAECgYICwABNQAFFAYICwAXACkOAA==.Pallymans:BAAANQADCgMIAwAAAA==.Pangpang:BAAANQADCgcJDAAAAA==.Pantheons:BAAANQAECgQIDQAAAA==.Parsi:BAABNQAECn8aAAMMAAcK/hkGDAAFAgAMAAcK/hkGDAAFAgANAAIKmQf5XwBnAAAAAA==.Pattysmyth:BAAANQAECgQIBwABNQADCggIDgACAAAAAA==.Paulinemaroi:BAAANQAECgcIDQAAAA==.Paulinethree:BAAANQAECgQIBAABNQAECgcIDQACAAAAAA==.Pawtism:BAAANQAECggIEgAAAA==.',
Pe='Peleaihonua:BAAANQADCgQJBQABNQAECgUIDAACAAAAAA==.Pennywhys:BAAANQADCgYIBgAAAA==.',
Ph='Philip:BAAANQAECgYICAAAAA==.',
Pl='Playstayshon:BAAANQADCgMIAgAAAA==.',
Po='Pofat:BAAANQADCgYIBgABNQAECgkJGQALAKgdAA==.Polis:BAAANQADCgcIBwABNQAECgQIDAACAAAAAA==.Pottyy:BAAANQABCgIIAgAAAA==.Pougadina:BAAANQAECgIIAgABNQAECgkJGQALAKgdAA==.Powjr:BAAANQADCgYIBgAAAA==.',
Pr='Primal:BAAANQADCgcJBwAAAA==.Pritee:BAAANQADCggIGgAAAA==.',
Pu='Puriel:BAAANQABCgYICQAAAA==.Putu:BAAANQADCgUIBgAAAA==.',
Py='Pyrina:BAAANQAECgUICQABNQAECgYIDgACAAAAAA==.',
['Pä']='Pändora:BAAANQADCggIDgAAAA==.',
Ra='Rabite:BAABNQAECn8kAAIcAAgKYCVhBABjAwAcAAgKYCVhBABjAwAAAA==.Radiance:BAEANQAECgYICAABNQAFFAUICgAWABQfAA==.Raelinastus:BAAANQADCgYICAAAAA==.Ragehound:BAAANQADCgEIAQAAAA==.Rah:BAAANQADCgYJCQAAAA==.Ramshunter:BAAANQAECgMIBQAAAA==.Randyvivaldi:BAAANQAECgEIBAAAAA==.Rashanda:BAAANQAECgUICQAAAA==.Rathasas:BAABNQAECn8nAAMUAAkK9BbJDwCqAgAUAAkK9BbJDwCqAgAJAAIKthVvMACPAAAAAA==.Ratnob:BAABNQAECn8dAAISAAgKgBmeOABAAgASAAgKgBmeOABAAgAAAA==.',
Re='Reddemon:BAABNQAECn8nAAMeAAkKUx6rAwDqAgAeAAkKUx6rAwDqAgAJAAEKfwYIQAAqAAAAAA==.Relda:BAAANQAECgMIBwABNQAECggIGwAhAGgiAA==.Remye:BAABNQAECn8pAAIZAAkKRBabPQBrAgAZAAkKRBabPQBrAgAAAA==.Rennshi:BAABNQAECn8dAAILAAkK8CUmCAB3AwALAAkK8CUmCAB3AwAAAA==.Reportedhunt:BAABNQAECn8jAAIDAAkKPhg3PwCrAgADAAkKPhg3PwCrAgAAAA==.Rezzan:BAAANQAECgMIBwAAAA==.',
Rh='Rhavetta:BAAANQADCgUIBQAAAA==.',
Ri='Riani:BAAANQAECgEIAQAAAA==.Riarina:BAAANQADCgIIAgAAAA==.Richie:BAAANQADCgcIBwAAAA==.Rimmy:BAAANQABCgIIAgABNQADCgEIAQACAAAAAA==.',
Ro='Robbin:BAAANQAECgEIAQAAAA==.Rolanthas:BAABNQAECn8ZAAMNAAUK3gM0UgDKAAANAAUKjAM0UgDKAAALAAIKfgRrhwBSAAAAAA==.Roldaza:BAAANQAECgUICgAAAA==.Rolexiós:BAAANQADCgIJAgAAAA==.Roranhamer:BAAANQADCgcICQAAAA==.Rosario:BAABNQAECn83AAMDAAkKuSHyFgA9AwADAAgK+yTyFgA9AwAWAAYKTgzkSgAGAQAAAA==.',
Ru='Rulep:BAAANQADCgEIAQAAAA==.',
Ry='Rykû:BAAANQAECgEIAgAAAA==.Rythmatic:BAABNQAECn8tAAMVAAkKUiSPBABIAwAVAAgKQCSPBABIAwAYAAcKoyGBHwCBAgAAAA==.',
Sa='Sacrifice:BAAANQADCgEIAQAAAA==.Sagà:BAAANQABCgEIAQAAAA==.Sainttaint:BAAANQADCggIEwABNQADCgEIAQACAAAAAA==.Sakieri:BAABNQAECn8mAAMRAAgK0xvPGQB9AgARAAgK0xvPGQB9AgAaAAEKKQOE/wApAAAAAA==.Salazar:BAAANQAECgEJAQAAAA==.Saluke:BAAANQADCgUIBQAAAA==.Samedi:BAAANQAECgMIAwAAAA==.Samwisegam:BAAANQADCgQIBAAAAA==.Sandordel:BAAANQADCgYIFQAAAA==.Sangan:BAABNQAECn8vAAIOAAkKFBpoRgD2AgAOAAkKFBpoRgD2AgAAAA==.Sangen:BAAANQABCgMIAwAAAA==.Santaclaus:BAAANQADCggIDQAAAA==.Sappie:BAAANQADCgIIAgABNQADCgYIBwACAAAAAA==.Sarafinmae:BAAANQABCgIIAgAAAA==.',
Se='Seanoevil:BAAANQAECgIIAgAAAA==.Selaris:BAAANQADCggICAAAAA==.Selathviala:BAAANQADCgMIAgAAAA==.Serazal:BAACNQAFFH8RAAIJAAYKiBbZAgDaAQAJAAYKiBbZAgDaAQA1AAQKfyYAAgkACQo2JIkFADcDAAkACQo2JIkFADcDAAAA.Sergregorsly:BAAANQADCgIIAgAAAA==.Serintalis:BAAANQADCgEIAQAAAA==.',
Sh='Shadowblitzx:BAAANQADCggICwAAAA==.Shakaphase:BAAANQAECgUIBgAAAA==.Shalidor:BAAANQADCgUIBQAAAA==.Shamshamz:BAAANQAECgIIAgAAAA==.Shangan:BAAANQADCgQIBAAAAA==.Sharpshotz:BAAANQADCggIDQAAAA==.Shenanigan:BAAANQAECgUJBQAAAA==.Shionslime:BAAANQADCgQIBAAAAA==.',
Si='Sidequest:BAAANQADCgQJBAAAAA==.Sinaga:BAABNQAECn8iAAMEAAkKZiAiEwA/AwAEAAkKZiAiEwA/AwAGAAIK8RtwTQCWAAAAAA==.Sinsear:BAAANQADCgcIBwAAAA==.Sintha:BAABNQAECn8dAAIOAAcK1wtO+wCTAQAOAAcK1wtO+wCTAQAAAA==.',
Sl='Slimedink:BAAANQADCgYICAAAAA==.',
Sm='Smarfus:BAAANQADCgQIBAABNQAECgkJJwAeAFMeAA==.Smilingp:BAAANQADCgYIDAAAAA==.Smolworm:BAAANQADCgUIDQAAAA==.',
So='Soulezz:BAAANQAECgUJBwAAAA==.Sourmash:BAAANQAECggICgAAAA==.',
St='Starfrost:BAAANQADCgIJAwAAAA==.Stingerai:BAABNQAECn8mAAIDAAkK1BsGJwD6AgADAAkK1BsGJwD6AgAAAA==.Stingerjb:BAAANQAECgQIBgABNQAECgkJJgADANQbAA==.Stormj:BAAANQAECgEIAQAAAA==.',
Su='Subjugator:BAAANQAECggIDwAAAA==.Sukunaa:BAAANQADCgUJDAAAAA==.Sunbeamer:BAAANQABCgYIBgAAAA==.Superdeej:BAAANQAECgYIBwABNQAECgkJFgAXAAAhAA==.',
Sy='Syl:BAAANQAECgQIDAAAAA==.',
['Sá']='Sága:BAAANQADCgMJAwAAAA==.',
Ta='Tarashock:BAAANQADCgUIBgAAAA==.Taureesha:BAAANQADCgEIAQAAAA==.',
Te='Teecat:BAAANQADCgQIBwAAAA==.Teehuntee:BAAANQADCgEIAQABNQAECggIJAAlAI4fAA==.Teemonk:BAABNQAECn8kAAIlAAgKjh9WEwC7AgAlAAgKjh9WEwC7AgAAAA==.Teepal:BAAANQADCgUIBQABNQAECggIJAAlAI4fAA==.Teila:BAAANQABCggIJAAAAA==.Telamanus:BAAANQABCgIIAgAAAA==.Tempist:BAAANQAECgUIDQAAAA==.Teribullduce:BAABNQAECn8hAAIDAAkKhyNmGAA3AwADAAkKhyNmGAA3AwAAAA==.Terscheckii:BAAANQADCgYIDAAAAA==.',
Th='Thalissille:BAAANQAECgEIAQAAAA==.Thickyricky:BAAANQAECggIEAABNQAECggIGwAhAGgiAA==.Thingol:BAAANQABCgYIEwAAAA==.Thormor:BAAANQAECgQICAABNQAFFAcIFgAUALUQAA==.Throrgar:BAAANQADCgIIAgAAAA==.Thugger:BAAANQAECgQIBgABNQAECgkJIQAXAPEWAA==.Thuggerjr:BAABNQAECn8hAAIXAAkK8RZzZwBhAgAXAAkK8RZzZwBhAgAAAA==.Thundersurge:BAAANQAECgEIAQABNQAECgkJIwADAD4YAA==.Thænes:BAAANQAECgYIEAAAAA==.Thûr:BAAANQAECgIIAgABNQAECgkJKQABABIZAA==.',
Ti='Tigg:BAABNQAECn8eAAIKAAgKNAS84ADQAAAKAAgKNAS84ADQAAAAAA==.Tildin:BAAANQADCggIDQAAAA==.Tinkerdinker:BAAANQAECgEIAQAAAA==.Tipsout:BAABNQAECn80AAMHAAkKCiJgIgAtAwAHAAkKCiJgIgAtAwATAAYK1hOXIQA6AQAAAA==.',
Tn='Tnemith:BAAANQABCgUIBQAAAA==.',
To='Toddlyv:BAAANQADCggICAABNQAECggIJAAlAI4fAA==.Totemm:BAAANQAECgcIEAAAAA==.Totomlystond:BAAANQADCgMIAwAAAA==.Tottemdrop:BAABNQAECn8pAAMBAAkKEhnQPwBeAgABAAkKEhnQPwBeAgAKAAUKQhEtsAAuAQAAAA==.',
Tr='Trailertrash:BAAANQADCgIIAgAAAA==.Traque:BAAANQAECgIIAgAAAA==.Trassenok:BAAANQADCgcIEAAAAA==.Trealin:BAAANQAECgEIAQAAAA==.',
Ty='Tyllinar:BAAANQADCgYIBgAAAA==.Tyrgor:BAAANQADCgYIFgAAAA==.Tyrsside:BAAANQAECgYICgAAAA==.',
Ub='Ubeenbained:BAAANQADCgIIAwAAAA==.',
Ud='Udderlyrich:BAAANQAECgMIAwAAAA==.',
Un='Unfocused:BAABNQAECn8vAAIIAAkKRxy6HQDaAgAIAAkKRxy6HQDaAgAAAA==.Unholybelac:BAAANQADCgQIBAAAAA==.',
Ur='Urgmathron:BAAANQAECgUIEgAAAA==.',
Va='Vakhara:BAAANQAECgUIDAAAAA==.Valdralilia:BAAANQAECgEIAQAAAA==.Valorisa:BAAANQAECgMIAwABNQAFFAUICgARAMkWAA==.Vansthir:BAAANQAECggIBgAAAA==.Vargko:BAAANQADCggICAAAAA==.Vaskie:BAEANQAECggIAQABNQAFFAQIDAAHAMYUAA==.Vaush:BAAANQAECgYIEAAAAA==.',
Ve='Veigär:BAAANQAECgEIAQAAAA==.Verasuchi:BAAANQAECgIIAQAAAA==.',
Vi='Vinsmoke:BAAANQADCggIGQAAAA==.',
Vo='Voidflare:BAABNQAECn8aAAIeAAYKkwxNEQAdAQAeAAYKkwxNEQAdAQAAAA==.Voidnutz:BAAANQADCgUICAAAAA==.Voidyvoid:BAAANQADCgYIBgABNQAECgQIBAACAAAAAA==.Volcanoez:BAAANQADCgYICgAAAA==.Vonrx:BAAANQAECgEIAwAAAA==.',
Vr='Vrezor:BAAANQAECggIBAAAAA==.',
Vu='Vulgate:BAAANQADCgcIBwAAAA==.',
Vy='Vyndrian:BAAANQADCgUIBQABNQAECgkJKwAIAGgjAA==.',
Wa='Wardian:BAAANQAECgQIBAABNQAECgYIHgAfAJoUAA==.Wariastos:BAAANQADCgQIBAAAAA==.Warlockhimup:BAAANQADCgMIBAABNQAECgkJIwADAD4YAA==.',
We='Welfairline:BAAANQADCggIGgAAAA==.',
Wh='Whatasham:BAAANQAECgMIAwABNQAECgkJIQADAIcjAA==.',
Wy='Wynter:BAAANQADCgMIAwAAAA==.',
['Wô']='Wôrm:BAAANQADCgUIDQAAAA==.',
Xa='Xalarys:BAAANQADCgYIDAAAAA==.Xandra:BAAANQADCgMJBQAAAA==.',
Xs='Xsslopgob:BAAANQADCgEIAQAAAA==.',
Xu='Xufoxpikmin:BAAANQADCgEIAQAAAA==.',
Ya='Yappars:BAABNQAECn8aAAIlAAkKVB4oDgD6AgAlAAkKVB4oDgD6AgAAAA==.Yassera:BAAANQAECgQIDAAAAA==.',
Ye='Yekteniya:BAAANQAECgUICgAAAA==.',
Yu='Yurio:BAABNQAECn8bAAIHAAgKkQ33nADPAQAHAAgKkQ33nADPAQAAAA==.Yutch:BAAANQAECgQIBQAAAA==.',
Za='Zacalkan:BAAANQADCgYIHQAAAA==.Zarik:BAAANQAECgUICwAAAA==.',
Ze='Zeddoc:BAEANQAECgEIAQAAAA==.Zedward:BAEANQADCgMIBQABNQAECgEIAQACAAAAAA==.Zenfist:BAAANQADCgQIBAAAAA==.Zenithar:BAAANQADCgIIAgAAAA==.Zenoath:BAAANQAECgYIDgAAAA==.',
Zo='Zolidus:BAAANQADCggIFAAAAA==.Zosiris:BAAANQADCgYICwAAAA==.',
Zu='Zulugangrene:BAABNQAECn8gAAIXAAcKRA2AzQB6AQAXAAcKRA2AzQB6AQAAAA==.Zun:BAABNQAECn8VAAIQAAYKtwixGgAaAQAQAAYKtwixGgAaAQAAAA==.',
['Åt']='Åthenä:BAAANQADCgMIAwAAAA==.',
['Æg']='Ægir:BAAANQADCgUIBQABNQAECgYIEAACAAAAAA==.',
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
