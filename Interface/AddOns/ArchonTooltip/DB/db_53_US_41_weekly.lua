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

local lookup = {'Warlock-Destruction','Paladin-Holy','Paladin-Retribution','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Unholy','Unknown-Unknown','Druid-Restoration','Evoker-Preservation','DeathKnight-Blood','Shaman-Elemental','Warrior-Protection','Druid-Balance','Monk-Windwalker','Evoker-Devastation','Rogue-Assassination','Warlock-Demonology','Warlock-Affliction','Paladin-Protection','Shaman-Enhancement','Mage-Arcane','Mage-Frost','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Havoc','Evoker-Augmentation','Priest-Holy','Priest-Shadow','Druid-Feral','DeathKnight-Frost','Monk-Mistweaver','Rogue-Subtlety','Hunter-Survival','Warrior-Arms',}
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abbpriest:BAAANQADCgYJBgABNQAECggJGQABAOYYAA==.Abruum:BAAANQADCgcIDAAAAA==.',
Ad='Admetus:BAABNQAECn8jAAICAAkKBR3LCgAXAgACAAkKBR3LCgAXAgAAAA==.Adobe:BAAANQADCggIHAAAAA==.',
Am='Amathal:BAAANQAECggIEgAAAA==.',
An='Anderson:BAAANQADCgQIBAAAAA==.Ankheloios:BAAANQAECgUIDgAAAA==.',
Ar='Arcanehonkey:BAAANQADCggICQAAAA==.Aredhela:BAABNQAECn8WAAIDAAgKxBMdkQACAgADAAgKxBMdkQACAgAAAA==.Arias:BAAANQAECgQIBAAAAA==.Armsdealer:BAAANQADCgUIBQAAAA==.Arro:BAAANQAECgEIAQAAAA==.',
As='Ascending:BAAANQAECgQICAAAAA==.Asha:BAACNQAFFH8QAAIEAAUKGRnUBADrAAAEAAUKGRnUBADrAAA1AAQKfyQAAwQACgpBHOoRANYCAAQACgpBHOoRANYCAAUAAQqxAV1sASYAAAAA.Ashveil:BAAANQADCgQIBAABNQAECgkJHgAGANIZAA==.Astrialynn:BAAANQADCgYIBwAAAA==.Astrulawa:BAAANQAECgQICgAAAA==.',
At='Athrea:BAABNQAECn8mAAIGAAoKXx78IwCyAgAGAAoKXx78IwCyAgAAAA==.',
Av='Avasharm:BAAANQADCgEIAQABNQABCgYIAgAHAAAAAA==.',
Ba='Barakah:BAAANQAECgQIAwAAAA==.Barnre:BAAANQAECgIIBAAAAA==.Battlelord:BAAANQAECgIIBAAAAA==.',
Bd='Bdssm:BAAANQAECgcIBwAAAA==.',
Be='Bearito:BAAANQAECgQIDwAAAA==.Beefstick:BAABNQAECn8YAAIFAAgKeBXYRQApAQAFAAgKeBXYRQApAQAAAA==.Beserkfury:BAABNQAECn8hAAIEAAgKXgp0CwA2AQAEAAgKXgp0CwA2AQAAAA==.',
Bi='Biercan:BAAANQAECgYIDAAAAA==.Bigcarl:BAAANQAECgEIAQAAAA==.Binke:BAAANQADCgQIBgAAAA==.Bittyboop:BAAANQADCgYIDAABNQAECgIIAwAHAAAAAA==.Bittywhite:BAAANQAECgIIAwAAAA==.Bittywyvern:BAAANQADCgEIAQABNQAECgIIAwAHAAAAAA==.',
Bj='Bjarna:BAAANQAECgQIBwAAAA==.',
Bl='Blayze:BAAANQAECgUIBQAAAA==.Blinkytime:BAABNQAECn8dAAIDAAcKzxT0rwC/AQADAAcKzxT0rwC/AQAAAA==.Bloodskull:BAAANQADCgEIAgAAAA==.Blúnt:BAAANQADCgQIBQAAAA==.',
Bo='Bobheals:BAABNQAECn8pAAIIAAoK2BgSBAA6AgAIAAoK2BgSBAA6AgAAAA==.Boibye:BAAANQAECgQICwAAAA==.Bolblock:BAAANQAECggIDwAAAA==.Bolo:BAACNQAFFH8HAAIJAAMKWw7aBwClAAAJAAMKWw7aBwClAAA1AAQKfzIAAgkACgoOH6kHACsDAAkACgoOH6kHACsDAAAA.Boostedww:BAAANQAECgQICwAAAA==.',
Br='Brambleclaw:BAABNQAECn83AAIKAAoKyB5FDABQAwAKAAoKyB5FDABQAwAAAA==.Brayker:BAABNQAECn83AAIDAAoKDCE6IgA7AwADAAoKDCE6IgA7AwAAAA==.Breadoneal:BAABNQAECn8iAAMCAAgKnBTsHQB0AQACAAgKnBTsHQB0AQADAAMKqQasXQGKAAAAAA==.Brewed:BAAANQAECgMIBAAAAA==.Brynjamin:BAAANQAECgQICAAAAA==.Brúh:BAAANQADCgEIAQAAAA==.Brüenor:BAAANQAECgMIBQAAAA==.',
Bu='Bubbi:BAAANQADCgEIAQAAAA==.Bukkorosuzo:BAAANQAECgMIBgAAAA==.Burntroot:BAABNQAECn8dAAILAAcK5APuuAAgAQALAAcK5APuuAAgAQAAAA==.',
['Bá']='Bálor:BAAANQAECgUIDgAAAA==.',
Ca='Cacci:BAAANQADCgcIBwAAAA==.Caedwyn:BAAANQAECgYIDgAAAA==.Camdakablam:BAAANQAECgcJEQAAAA==.Careadin:BAAANQADCgQIBAABNQAECgcIGQAMAAogAA==.Careradin:BAABNQAECn8ZAAIMAAcKCiBaDABwAgAMAAcKCiBaDABwAgAAAA==.Carereaper:BAAANQAECgEIAQABNQAECgcIGQAMAAogAA==.Cartilage:BAAANQAECgcIDgAAAA==.Cassieruth:BAAANQAECgcICwAAAA==.Catalei:BAAANQAECgEIAQAAAA==.',
Ce='Centrest:BAAANQADCgYJCgAAAA==.',
Ch='Chebbles:BAAANQADCgUIBwABNQAECgcIIAANAMwRAA==.Chillidan:BAAANQAECgMIAwABNQAECgkJJgAOAFMhAA==.Chivi:BAAANQADCggIDgABNQAECggIIgAPAKIcAA==.Chonkmonk:BAAANQADCgQIBQAAAA==.Chupacabrass:BAAANQAECgIIAgAAAA==.Chëbbles:BAAANQAECgMIAwABNQAECgcIIAANAMwRAA==.',
Co='Colman:BAAANQAECgMIBgAAAA==.Coorsbanquet:BAAANQAECgYIEAAAAA==.Coorsbite:BAAANQAECgUIEgABNQAECgYIEAAHAAAAAA==.Coorslight:BAAANQADCgYIBgABNQAECgYIEAAHAAAAAA==.Corrahthecow:BAAANQAECgEIAQABNQAECgYIEAAHAAAAAA==.',
Cr='Craccjar:BAAANQADCgYIBwAAAA==.Crackjar:BAAANQADCgUICAAAAA==.Croc:BAAANQAECgYIEAAAAA==.Crudala:BAAANQADCgcICgABNQAECgMIAgAHAAAAAA==.Crystle:BAAANQAECgcIEwAAAA==.Crystlemarie:BAAANQADCgMIAwAAAA==.',
Cs='Csyasha:BAAANQADCgcIBwABNQAECgoKGgAQAA4KAA==.',
Cu='Cubcadet:BAABNQAECn8bAAIDAAoKwReXSQC4AgADAAoKwReXSQC4AgAAAA==.',
Cy='Cybear:BAAANQAECggIEwAAAA==.',
Da='Dalanora:BAABNQAECn83AAQRAAoKMhp3JgDqAgARAAoKMhp3JgDqAgABAAMKXRUdQwC4AAASAAMKpBafGwCkAAAAAA==.Dammned:BAAANQAECgIIAwAAAA==.Dapalyu:BAABNQAECn8mAAMTAAoKkQxCKwCDAQATAAkKNA1CKwCDAQADAAgK2wT1EwH+AAAAAA==.Davidx:BAAANQADCgQIBgAAAA==.',
De='Dekig:BAAANQAECgEIAQAAAA==.Demine:BAAANQAECgMIBAAAAA==.Detrazeral:BAAANQADCggIEQAAAA==.Devoid:BAAANQADCgEIAQAAAA==.',
Di='Dico:BAAANQAECgcICgABNQAFFAcIGwAMAB8XAA==.Dipper:BAABNQAECn8sAAIDAAoKchWcegA2AgADAAoKchWcegA2AgAAAA==.',
Do='Dohan:BAAANQADCggIEAAAAA==.Dorìan:BAAANQADCggIFgAAAA==.',
Dr='Draetona:BAAANQADCggIGQAAAA==.Druidthings:BAAANQADCgUIBQAAAA==.',
Ee='Eeveeko:BAABNQAECn8qAAIUAAkK4RkCDACwAgAUAAkK4RkCDACwAgAAAA==.',
Ej='Ejavuday:BAABNQAECn8nAAMVAAoKABxCQQACAwAVAAoKABxCQQACAwAWAAEKgR2cRwA1AAAAAA==.',
En='Enerchi:BAABNQAECn8mAAIOAAkKUyF8CgArAwAOAAkKUyF8CgArAwAAAA==.',
Er='Erianar:BAAANQADCgEIAQAAAA==.Ervyne:BAABNQAECn8bAAMFAAoKzwyTbAA5AgAFAAoKegyTbAA5AgAEAAUKmAaaUgDeAAAAAA==.',
Ev='Evera:BAABNQAECn8YAAIGAAgKIgp7agBoAQAGAAgKIgp7agBoAQAAAA==.Evos:BAAANQADCgYJBwAAAA==.',
Ex='Exning:BAAANQADCggICAAAAA==.',
Fa='Fathernasty:BAAANQADCgEIAQABNQAECgIIAgAHAAAAAA==.Fauci:BAAANQAECgYIBgABNQAFFAUIEAAQAAclAA==.',
Fe='Feerii:BAAANQADCgEIAQAAAA==.Feihao:BAAANQAECgEIAQAAAA==.Feile:BAABNQAECn8tAAMRAAoKog4lPwAQAQARAAoKog4lPwAQAQABAAEKAAArcQA+AAAAAA==.Feltree:BAAANQADCgQIBQAAAA==.',
Fi='Fifezilla:BAAANQADCgEIAQAAAA==.Fishbox:BAAANQABCgYIDAAAAA==.',
Fl='Flashir:BAAANQADCgIIAgAAAA==.Flinzza:BAABNQAECn8jAAMXAAkK0BanaQDPAQAXAAgK1BSnaQDPAQAUAAgKtRapDAAvAQAAAA==.Flyknit:BAAANQAECgYIDwAAAA==.',
Fr='Fredthedh:BAABNQAECn8gAAMYAAoKixeVIwAsAgAYAAgKXxeVIwAsAgAZAAUKChZRMwCcAAAAAA==.Fromtheback:BAAANQAECgIIAgAAAA==.Frosticals:BAABNQAECn8rAAIVAAkKIyAHEADnAQAVAAkKIyAHEADnAQAAAA==.Frostsugar:BAAANQABCgQIBgAAAA==.',
Ga='Gaashw:BAAANQADCgEIAQAAAA==.Ganandor:BAABNQAECn8gAAIQAAoKRBnaGwCfAgAQAAoKRBnaGwCfAgAAAA==.Gaulish:BAAANQAECgEIAgAAAA==.',
Ge='Geocide:BAABNQAECn8VAAILAAcKVB3oVgAeAgALAAcKVB3oVgAeAgAAAA==.Getagrip:BAAANQAECgIIAgABNQAFFAIIBQAQAOgTAA==.Gethalyn:BAAANQAECgUIBwAAAA==.',
Gh='Ghasch:BAAANQAECggIEgAAAA==.Ghume:BAAANQAECgQIDAAAAA==.',
Gi='Gianthippo:BAAANQADCgYICgAAAA==.Gilf:BAACNQAFFH8GAAIUAAUKYR/UAQDiAQAUAAUKYR/UAQDiAQA1AAQKfx0AAxQACQq6I9ABAJoDABQACQq6I9ABAJoDAAsABAqCCIzsAL4AAAE1AAUUBQgKABEAxxYA.',
Go='Goursh:BAAANQAECgEIAQAAAA==.',
Gr='Grapefruitgt:BAAANQADCgEIAQAAAA==.Grizzoul:BAABNQAECn8VAAMaAAcKTgO9FADiAAAaAAcKTgO9FADiAAAPAAMKxwEdNwBWAAAAAA==.Grreenry:BAAANQAECgEIAQAAAA==.Grumly:BAAANQAECgQIDgAAAA==.',
Ha='Hanswoloqued:BAABNQAECn8mAAIRAAoKixIrWgBIAgARAAoKixIrWgBIAgAAAA==.Haxz:BAAANQADCgUIBQAAAA==.',
He='Healufast:BAABNQAECn8nAAIbAAkK4B6eKgC+AgAbAAkK4B6eKgC+AgAAAA==.Heck:BAAANQADCgYIBgAAAA==.Helstrom:BAAANQADCggIFAAAAA==.Herbalistiks:BAAANQADCgEIAQAAAA==.',
Hj='Hjalmar:BAABNQAECn8dAAMCAAgKNxZhZgDkAQACAAcKfRVhZgDkAQADAAYKOgftPQG9AAAAAA==.',
Ho='Holycõw:BAABNQAECn8VAAIDAAgKBROEuwCmAQADAAgKBROEuwCmAQAAAA==.Holysabeline:BAABNQAECn83AAICAAoKdB0HDAAFAgACAAoKdB0HDAAFAgAAAA==.Hotpots:BAAANQAECggIEgAAAA==.',
Hu='Huchar:BAABNQAECn8yAAIMAAkKFhxAAgDuAQAMAAkKFhxAAgDuAQAAAA==.Humpf:BAAANQADCgEIAQAAAA==.Hunterpanda:BAAANQADCgYIBgAAAA==.',
Hy='Hydraxix:BAAANQADCggICQAAAA==.Hypnose:BAAANQADCggIEAAAAA==.',
Ic='Iceblade:BAABNQAECn8ZAAICAAoKqBevDQDyAQACAAoKqBevDQDyAQAAAA==.',
Id='Idtrapdat:BAAANQAECgIIAgAAAA==.',
If='If:BAAANQADCgQIBAAAAA==.',
In='Incowgnito:BAAANQAECgcICgAAAA==.',
Ir='Ironßest:BAAANQADCgEIAQAAAA==.',
Ja='Jadzi:BAAANQADCgYJCwAAAA==.Jaxxion:BAAANQADCgYIBgAAAA==.',
Je='Jensthyra:BAAANQABCgcICgAAAA==.Jessaiyan:BAAANQAECgcICQAAAA==.',
Jo='Jobo:BAABNQAECn8cAAMIAAkKZw5CBwDRAQAIAAkKZw5CBwDRAQANAAUKZASNhgC4AAAAAA==.Jobodot:BAAANQAECgcIEwAAAA==.',
Ju='Julaudette:BAAANQADCggIFwAAAA==.Juliania:BAAANQADCgYIBgAAAA==.Julzaria:BAAANQAECgYIDAAAAA==.Jurny:BAABNQAECn8gAAMBAAYKnxH+GwCNAQABAAYKnxH+GwCNAQASAAIKVAVDJQBZAAAAAA==.',
Ka='Kahlandra:BAABNQAECn82AAIVAAoKShXTPgA/AQAVAAoKShXTPgA/AQAAAA==.Kaizer:BAABNQAECn81AAILAAkKLRkTNgCfAgALAAkKLRkTNgCfAgAAAA==.Kandera:BAAANQADCgUIBQAAAA==.Karina:BAAANQADCgUJBgABNQAECgoKLwAFAHohAA==.',
Ke='Keizer:BAAANQAECgEIAQAAAA==.Keunen:BAAANQAECgUIEQAAAA==.Kevlock:BAAANQADCgYIBgAAAA==.Keyzer:BAAANQAECgcIEQAAAA==.',
Kh='Khanjuror:BAAANQAECgEIAQAAAA==.Kharún:BAAANQADCgEIAQAAAA==.Khornedog:BAABNQAECn8kAAIRAAkKgRn+VgBRAgARAAkKgRn+VgBRAgAAAA==.Khrama:BAABNQAECn8yAAIKAAkKYiS0AgBpAgAKAAkKYiS0AgBpAgAAAA==.',
Kl='Kleenonean:BAACNQAFFH8XAAIcAAYKxCUmAQC5AQAcAAYKxCUmAQC5AQA1AAQKf4gAAhwACgpeJhEAAI8DABwACgpeJhEAAI8DAAAA.',
Kn='Knut:BAAANQADCggICAAAAA==.',
Kr='Krackjarr:BAABNQAECn8VAAIRAAgKXwaOeQCQAAARAAgKXwaOeQCQAAAAAA==.Kredor:BAAANQAECgIIBAAAAA==.',
Ku='Kungpowbeef:BAAANQAECgIIAgAAAA==.Kurzaan:BAAANQAECgMIAwAAAA==.Kuyaj:BAAANQADCgIIAgAAAA==.',
La='Lacio:BAABNQAECn81AAIcAAoKwAf2MQCTAQAcAAoKwAf2MQCTAQAAAA==.Larune:BAAANQADCgEIAQAAAA==.',
Le='Lemonpepper:BAABNQAECn8jAAIJAAoKxBA/BwBVAQAJAAoKxBA/BwBVAQAAAA==.Lexxix:BAAANQADCgcIDAAAAA==.Leyru:BAAANQAECgUIDAAAAA==.',
Li='Liberos:BAABNQAECn8WAAIXAAcK9hB5kgBaAQAXAAcK9hB5kgBaAQAAAA==.Littlechiken:BAAANQADCgUIBQABNQAFFAUICgAKAIgMAA==.',
Ln='Lninedkhack:BAABNQAECn8eAAIGAAkK0hkJCwCNAQAGAAkK0hkJCwCNAQAAAA==.',
Lo='Logaar:BAABNQAECn8yAAMCAAoKMxFaTgAxAgACAAkK+Q9aTgAxAgADAAoK/QpYvQCiAQAAAA==.',
Lu='Lubuu:BAAANQADCgYIFQAAAA==.Luckymagi:BAAANQAECgEIAQAAAA==.Lucyfurrawr:BAABNQAECn8ZAAIdAAkKOBRCAgDTAQAdAAkKOBRCAgDTAQABNQAECgoKIgAOAM8ZAA==.Lunala:BAAANQADCgcIBwABNQAECgMIAgAHAAAAAA==.Luxurix:BAAANQADCggIEgAAAA==.',
['Lú']='Lúcretia:BAAANQADCgEIAQAAAA==.',
Ma='Maellis:BAAANQAECgEIAQAAAA==.Magtao:BAAANQADCgYIEQAAAA==.Malexannius:BAAANQADCgYIEAAAAA==.Manastorm:BAAANQAECgcIEgAAAA==.Maplebrick:BAAANQADCgEIAQAAAA==.Mariangel:BAAANQADCgEIAQAAAA==.Marric:BAAANQAECggJCgAAAA==.',
Me='Medean:BAAANQADCggICAAAAA==.Megtallica:BAAANQAECgQIDgAAAA==.Mehunglow:BAAANQADCgUIBAAAAA==.Mellissaa:BAAANQADCggIEgAAAA==.Mensrea:BAABNQAECn8YAAMLAAkK6wvtOADgAAALAAgKYwntOADgAAAXAAEKmwLUoQAsAAAAAA==.Merrycold:BAABNQAECn8dAAMGAAgKdxdQSwDoAQAGAAgKdxdQSwDoAQAeAAUKQxBAbADtAAABNQAECgoKHAAOAK4YAA==.',
Mf='Mfgirthquake:BAABNQAECn9GAAMUAAoK6iQ6AABAAwAUAAoK6iQ6AABAAwAXAAQKfhrc3gCrAAAAAA==.',
Mi='Miisty:BAAANQAECgcICQAAAA==.Mikklelee:BAAANQADCggIEAAAAA==.Miller:BAAANQADCgEIAQAAAA==.Mings:BAAANQAECgQICAAAAA==.Miniborohs:BAAANQAECgEIAQAAAA==.Mistweaver:BAABNQAECn83AAIfAAoK/SSqAABpAwAfAAoK/SSqAABpAwAAAA==.',
Mo='Mochi:BAABNQAECn8oAAIVAAkKZhZbPgBAAQAVAAkKZhZbPgBAAQAAAA==.Mochïi:BAAANQADCgIJBAABNQAFFAcIFAAVAIURAA==.Moghorva:BAAANQAECgIIBAAAAA==.Mojoe:BAABNQAECn8eAAIXAAgKSB85MAChAgAXAAgKSB85MAChAgAAAA==.Mommyswaggin:BAAANQAECgQIBwAAAA==.Moopster:BAABNQAECn8pAAIbAAoKUCHMCgBsAwAbAAoKUCHMCgBsAwAAAA==.Moopy:BAAANQAECgQIBAABNQAECgoKKQAbAFAhAA==.Mootangclan:BAABNQAECn8XAAILAAgKtxnkTQA/AgALAAgKtxnkTQA/AgAAAA==.Moxi:BAAANQADCgEIAQAAAA==.',
Na='Namii:BAAANQADCgEIAQAAAA==.Nanashi:BAACNQAFFH8GAAIeAAMKlAj4EQC+AAAeAAMKlAj4EQC+AAA1AAQKfxwAAh4ACQpRHakWANYCAB4ACQpRHakWANYCAAAA.Nazgru:BAAANQADCgYIDAAAAA==.',
Ne='Necros:BAAANQAECgIIAgABNQAFFAcIGgALAAMXAA==.Neiko:BAABNQAECn8hAAIQAAoKChdcIwBtAgAQAAoKChdcIwBtAgAAAA==.Neptuneakis:BAABNQAECn8gAAINAAcKzBF1GAAdAQANAAcKzBF1GAAdAQAAAA==.Neptuno:BAAANQADCgEIAQABNQAECgcIIAANAMwRAA==.Newcarsmell:BAAANQADCggIJwAAAA==.',
Ng='Ngl:BAAANQAECgUIBgAAAA==.',
Ni='Niceknife:BAAANQAECgEIAQAAAA==.Nightwinger:BAAANQAECgQIBgAAAA==.Nimrose:BAAANQAECgIIAgAAAA==.Niquid:BAABNQAECn8dAAIIAAkK6hIaBgDwAQAIAAkK6hIaBgDwAQAAAA==.Nivek:BAAANQAECgUIBgAAAA==.Niylea:BAAANQADCgUIBQABNQAECgoKJgAGAF8eAA==.',
No='Nobu:BAACNQAFFH8QAAMQAAUKByUgBAAKAgAQAAUKViEgBAAKAgAgAAIKXyGpCwBmAAA1AAQKfysAAhAACgqmJb4CALADABAACgqmJb4CALADAAAA.Noobhuntard:BAAANQADCggICQAAAA==.Norinari:BAACNQAFFH8KAAQRAAUKxxYAGAA1AQARAAQKOBQAGAA1AQABAAIKyhKODgCZAAASAAEKAADZDwBFAAA1AAQKfzwABBIACgpSIwIBANsBABEABwodI69BAI0CABIABwoiIwIBANsBAAEAAwoKG+0vAAkBAAAA.Notahealer:BAAANQAECgcIEAAAAA==.Noxloxes:BAAANQADCgIIAgAAAA==.',
Oa='Oakshre:BAABNQAECn82AAIOAAoKKh04CwAhAwAOAAoKKh04CwAhAwAAAA==.',
Ob='Obliteration:BAAANQAECgYIDQABNQAECgkJJgAOAFMhAA==.',
Od='Odsw:BAAANQADCgMJAwAAAA==.',
Oe='Oenaa:BAAANQABCgQIBAAAAA==.',
Ol='Olivertwist:BAAANQAECgQIDAABNQAECgkJJgAOAFMhAA==.',
On='Ontwou:BAABNQAECn8eAAIFAAcKQx5vYwBPAgAFAAcKQx5vYwBPAgAAAA==.',
Or='Orbz:BAABNQAECn82AAIVAAoKLCANBQCKAgAVAAoKLCANBQCKAgAAAA==.Orcazm:BAAANQAECgEIAQAAAA==.',
Pa='Padova:BAAANQAECgMIBAAAAA==.Palathal:BAAANQAECgQIBgABNQAECggIEgAHAAAAAA==.Palyont:BAAANQADCggIIwAAAA==.Pancakezebra:BAABNQAECn80AAIhAAoKvxgqAQDhAQAhAAoKvxgqAQDhAQAAAA==.Parse:BAAANQAECgIIAwAAAA==.Pastellus:BAAANQADCgEIAQAAAA==.',
Pe='Perdido:BAAANQADCgIIAgAAAA==.',
Ph='Phoenix:BAABNQAECn8oAAIDAAoKAxnQggAiAgADAAoKAxnQggAiAgAAAA==.',
Pi='Pikechu:BAAANQAECgYIEAAAAA==.Pinkskies:BAAANQAECgIIAgAAAA==.',
Pl='Playless:BAAANQAECgYIDAAAAA==.Pleasy:BAAANQAECgQIBwAAAA==.Plugtobacca:BAAANQADCgIIAgABNQAFFAUIEAAQAAclAA==.',
Po='Pocketchange:BAABNQAECn8fAAMXAAoKiRdQUgAdAgAXAAoKiRdQUgAdAgALAAUKdROWqABDAQAAAA==.Pocketwatch:BAAANQAECgQIBwABNQAECgoKHwAXAIkXAA==.',
Pr='Prayze:BAAANQADCgYIBgAAAA==.Preservation:BAAANQADCgIIAgABNQAECgoKNwAfAP0kAA==.Promethêus:BAAANQAECgIIAQAAAA==.',
Pu='Purefriction:BAAANQADCgYICQAAAA==.Purehate:BAAANQAECgUIDAAAAA==.',
Qr='Qrz:BAAANQAECgEIAQAAAA==.',
Rb='Rbackwards:BAAANQADCgUIBQABNQAECgoKLgARADEZAA==.',
Re='Relovan:BAABNQAECn8gAAIiAAgKjgs/SgALAQAiAAgKjgs/SgALAQAAAA==.Renothidan:BAABNQAECn8lAAIDAAoKzxglXACEAgADAAoKzxglXACEAgAAAA==.Ret:BAAANQADCgcICQABNQAECgoKRgAUAOokAA==.Reuben:BAAANQAECgEIAQAAAA==.Revin:BAABNQAECn8cAAIDAAgKCRRwoQDeAQADAAgKCRRwoQDeAQAAAA==.Revrynth:BAABNQAECn8iAAQPAAgKohx2DwBjAgAPAAgKohx2DwBjAgAJAAUKNhrgBwBHAQAaAAQKEBXjFADgAAAAAA==.Rexorcist:BAAANQAECgYICQAAAA==.',
Ri='Rillan:BAAANQADCgEIAQAAAA==.Rimed:BAABNQAECn8bAAMVAAcKiw7f8ACpAQAVAAcKMQ3f8ACpAQAWAAEKaBCvRwA1AAAAAA==.Rippèd:BAAANQADCgYIBgAAAA==.Rithcice:BAAANQADCgcICAAAAA==.Rizzard:BAAANQAECggIDQAAAA==.Rizzdolphler:BAACNQAFFH8JAAICAAQKtA5ZEwAsAQACAAQKtA5ZEwAsAQA1AAQKfyYAAwIACgomHFEiAOMCAAIACgomHFEiAOMCAAMABAqUBgZcAYwAAAAA.',
['Rö']='Rönburgundy:BAABNQAECn8uAAIRAAoKMRnwTABtAgARAAoKMRnwTABtAgAAAA==.',
Sa='Sanako:BAAANQAECgcIDgAAAA==.Saneros:BAAANQAECgQIBAAAAA==.',
Sc='Scraggle:BAAANQAECgEIAQAAAA==.Scuffito:BAAANQAECgMIBAAAAA==.',
Sd='Sdh:BAAANQADCgEIAQAAAA==.',
Se='Seasondpally:BAAANQADCgcIBwAAAA==.Sermakan:BAAANQAECgEIAQAAAA==.Setheron:BAAANQAECgMIBgAAAA==.',
Sh='Shiverlok:BAAANQADCgEIAQAAAA==.Shlea:BAABNQAECn8fAAIaAAkKoAp4CwCoAQAaAAkKoAp4CwCoAQAAAA==.Shley:BAAANQADCgYIBwABNQAECgkJHwAaAKAKAA==.',
Si='Silvanna:BAAANQAECgQIBQAAAA==.Sivi:BAAANQAECgIIAgAAAA==.',
Sl='Slinkstir:BAAANQADCgYIBgAAAA==.',
Sm='Smh:BAAANQAECgQIBAAAAA==.',
Sn='Sneak:BAAANQAECgQIBQABNQAECgoKRgAUAOokAA==.',
So='Solendros:BAAANQAECgQIBAAAAA==.Sonoa:BAAANQAECggICgAAAA==.Sonthar:BAAANQADCgQJBAAAAA==.Sorix:BAAANQADCgIIAgAAAA==.Sorlight:BAAANQAECgUIDwAAAA==.Soulelf:BAAANQADCgEIAQAAAA==.Sourpets:BAABNQAECn8VAAIFAAcKURqJWABqAgAFAAcKURqJWABqAgAAAA==.Sourshocks:BAAANQAECgEIAQAAAA==.Sourwords:BAAANQAECgEIAQAAAA==.',
Sp='Speshle:BAAANQADCgEIAQAAAA==.',
St='Standarshh:BAABNQAECn8tAAIFAAoKmB7OBQBxAgAFAAoKmB7OBQBxAgAAAA==.Stevenz:BAABNQAECn8iAAIVAAoKiiD/EwDHAQAVAAoKiiD/EwDHAQAAAA==.Stillflygon:BAAANQADCgYIEwAAAA==.Stormcare:BAAANQADCgUIBQAAAA==.',
Su='Subtle:BAACNQAFFH8FAAMQAAIK6BPlBACgAAAQAAIK6BPlBACgAAAgAAEKYwEEFwA4AAA1AAQKfy0AAxAACQolHlMgAH8CABAACQolHlMgAH8CACAABgrlFKojAKsBAAAA.Sugarbabi:BAAANQAECggIEwAAAA==.Sugarrush:BAAANQAECgEIAQAAAA==.Sugarshot:BAAANQAECgMIAgAAAA==.Sugartotem:BAAANQAECgYICQAAAA==.Sunmere:BAAANQADCgUIBQAAAA==.',
Sw='Swiftwing:BAAANQADCgQIBAAAAA==.',
Sy='Sydarliia:BAAANQAECgYIEAAAAA==.Sylrianah:BAABNQAECn83AAIbAAoKLA7aLQBGAQAbAAoKLA7aLQBGAQAAAA==.Sylveste:BAACNQAFFH8HAAICAAQKNgt9BwAaAQACAAQKNgt9BwAaAQA1AAQKfx0AAgIACgpMGXouAKwCAAIACgpMGXouAKwCAAAA.',
Ta='Tae:BAAANQAECgIIAQAAAA==.Tal:BAAANQAECggICgABNQAECggIFQADAAUTAA==.Talis:BAAANQADCgIIAgAAAA==.Talridor:BAAANQADCgcIBgAAAA==.Tankhiskhan:BAAANQAECggIEQAAAA==.Tarlis:BAAANQAECgUIBQAAAA==.',
Te='Tei:BAAANQADCgEIAQAAAA==.Terily:BAAANQADCgcICgAAAA==.',
Th='Thannill:BAABNQAECn8iAAIGAAgKkw1nIwDaAAAGAAgKkw1nIwDaAAAAAA==.',
Ti='Ticktoklock:BAAANQAECggICQAAAA==.Tie:BAABNQAECn8jAAITAAkKKBdRCwBGAQATAAkKKBdRCwBGAQAAAA==.Tirala:BAAANQAECgcICwAAAA==.',
To='Tomari:BAAANQABCgEIAQAAAA==.Tomias:BAAANQADCgMIAwAAAA==.Torzhu:BAAANQAECgUIEwAAAA==.Toy:BAAANQAECggIDwABNQAFFAcIGAAJAO0VAA==.',
Tr='Trauck:BAAANQAECgUICgAAAA==.Travvy:BAACNQAFFH8rAAMQAAkKhBtsAAAyAwAQAAkKoBhsAAAyAwAgAAcKuxwXAQDNAQA1AAQKfyMAAyAACgpzJrUDAGMDACAACgoaIrUDAGMDABAAAwr2IAxmABoBAAAA.Trevmo:BAABNQAECn8fAAIiAAoK3hGQPgAnAQAiAAoK3hGQPgAnAQAAAA==.Trexin:BAAANQAECgIIAwAAAA==.',
Tu='Turaylon:BAAANQADCgQIBAAAAA==.',
Tz='Tzuyu:BAABNQAECn8vAAMFAAoKeiGlCACXAwAFAAoKeiGlCACXAwAEAAEKIxGwhwA2AAAAAA==.',
Ud='Uddershock:BAAANQADCggIDgAAAA==.',
Un='Unapologetic:BAAANQAECgUIBQABNQAECgoKNwAfAP0kAA==.Unbreakabull:BAABNQAECn8bAAINAAoKOSOEBwCVAwANAAoKOSOEBwCVAwAAAA==.Unver:BAAANQADCgYIBgAAAA==.',
Va='Vache:BAAANQADCgEIAQAAAA==.Vae:BAAANQAECgYJEQABNQAECgoKIgAOAM8ZAA==.Valka:BAAANQAECgEIAQAAAA==.Vanthrall:BAAANQADCgUIBQAAAA==.',
Ve='Veldtt:BAAANQADCgIIAgAAAA==.Velera:BAABNQAECn8XAAIVAAgK8gZVOgBIAQAVAAgK8gZVOgBIAQAAAA==.Veyle:BAABNQAECn83AAMQAAoKgiIhAgC/AwAQAAoKgiIhAgC/AwAgAAYK1B00HQDpAQAAAA==.',
Vi='Viibryd:BAAANQAECgIIAgAAAA==.Vine:BAAANQADCgIIAwAAAA==.',
Vy='Vyel:BAAANQADCgIIAwAAAA==.Vyndria:BAAANQADCgcIDwAAAA==.Vynstus:BAAANQADCggIHAAAAA==.Vyran:BAAANQADCgIIAgAAAA==.',
Wa='Waypal:BAAANQADCggIGAAAAA==.',
We='Weashadow:BAAANQAECgMIAwAAAA==.Weashock:BAAANQADCgYIDQAAAA==.Weasy:BAAANQAECggIDQAAAA==.',
Wi='Windfury:BAABNQAECn8qAAIUAAoKHR9CAgCJAwAUAAoKHR9CAgCJAwAAAA==.Wingzard:BAABNQAECn8fAAIVAAgKZxV4tAAaAgAVAAgKZxV4tAAaAgAAAA==.',
Wo='Wowdudesame:BAABNQAECn8XAAIiAAcKCR2KagBRAgAiAAcKCR2KagBRAgABNQAECgoKRgAUAOokAA==.',
Xl='Xl:BAABNQAECn8nAAIZAAkKSxcJIwCDAgAZAAkKSxcJIwCDAgAAAA==.',
Ya='Yaitoopmfp:BAABNQAECn8cAAMOAAoKrhjRGQBzAgAOAAkKPhjRGQBzAgAfAAUKchJlDQD/AAAAAA==.Yao:BAABNQAECn8wAAMKAAoKqyCWDgA6AwAKAAoKqyCWDgA6AwAGAAEKAAAK2wA6AAAAAA==.Yasrena:BAABNQAECn8fAAMbAAgKXxDAgACWAQAbAAcKQxHAgACWAQAcAAcKYhCDDAA2AQAAAA==.',
Ye='Yelp:BAAANQAECgQIBAAAAA==.',
Za='Zabara:BAAANQADCgYICAABNQAECggIHQACADcWAA==.Zair:BAAANQADCgUIBQAAAA==.Zakaraki:BAABNQAECn83AAMPAAoKqx90BgAiAwAPAAkK3h50BgAiAwAJAAgK8hUvGgAgAgAAAA==.Zaki:BAABNQAECn8dAAIYAAoKyxWWFwChAgAYAAoKyxWWFwChAgAAAA==.Zalujin:BAAANQAECgEIAQAAAA==.Zappin:BAAANQAECgEIAQABNQAFFAUIEAAQAAclAA==.',
Ze='Zealot:BAABNQAECn8VAAMDAAgKXQ9BvACkAQADAAgKLw9BvACkAQATAAYK6wgjSADNAAAAAA==.Zeleria:BAAANQAECgMIAgAAAA==.Zerathis:BAAANQADCgEJAgAAAA==.',
Zi='Zinbek:BAAANQADCgUIBQAAAA==.Zip:BAAANQADCgEIAQAAAA==.Zipstin:BAAANQAECgEIAQAAAA==.',
Zo='Zoo:BAAANQAECgIIAgAAAA==.Zorb:BAABNQAECn81AAINAAoK/xrfFAAgAwANAAoK/xrfFAAgAwABNQAFFAIIBQARALsIAA==.Zoshow:BAAANQAECgUICgAAAA==.Zoshôw:BAAANQAECgcIBwAAAA==.',
['Zõ']='Zõshow:BAAANQAECgQIBwAAAA==.',
['Ða']='Ðaredevil:BAABNQAECn8iAAIOAAoKzxkkEgDMAgAOAAoKzxkkEgDMAgAAAA==.',
['Ðp']='Ðp:BAABNQAECn8WAAIYAAgKmQhAOQB7AQAYAAgKmQhAOQB7AQAAAA==.',
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
