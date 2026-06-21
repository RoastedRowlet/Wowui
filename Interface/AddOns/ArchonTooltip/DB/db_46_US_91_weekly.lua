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

local lookup = {'Paladin-Retribution','Druid-Balance','Unknown-Unknown','Shaman-Restoration','Priest-Discipline','Priest-Shadow','Priest-Holy','Druid-Restoration','Paladin-Holy','Warrior-Arms','Warrior-Fury','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Unholy','Warlock-Demonology','Warrior-Protection','DeathKnight-Blood','Monk-Brewmaster','Monk-Windwalker','Mage-Frost','Monk-Mistweaver','Druid-Feral','Warlock-Affliction','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Devourer','Rogue-Assassination','Rogue-Subtlety','Evoker-Preservation','Evoker-Augmentation','Paladin-Protection','Warlock-Destruction','Evoker-Devastation','Rogue-Outlaw','Druid-Guardian',}
local provider = {region='US',realm='Executus',name='US',type='weekly',zone=46,date='2026-06-20',data={Ad='Adolyn:BAAALgADCgkJCQAAAA==.Adventis:BAAALgADCgQJAwAAAA==.',
Al='Allavus:BAAALgADCgQJBQABLgAFFAYJFgABAN0aAA==.Alodiar:BAAALgAECgMJAwAAAA==.',
Am='Amrin:BAAALgAECgkJCQAAAA==.',
An='Andderson:BAAALgAECgEJAgAAAA==.Andersen:BAABLgAECn8jAAIBAAgJEB8dLwBEAgABAAgJEB8dLwBEAgAAAA==.Ando:BAAALgAECgEJAQABLgAECgkJLQACAG8ZAA==.Andryu:BAACLgAFFH8PAAICAAQJpQnPLgDKAAACAAQJpQnPLgDKAAAuAAQKf0UAAgIACQm7HB8KALMCAAIACQm7HB8KALMCAAAA.Anebel:BAAALgADCgkJCQAAAA==.Angelmuerte:BAAALgADCgkJDgAAAA==.Angyal:BAAALgAECgYJBwAAAA==.',
Ap='Apolion:BAAALgADCgYJBgAAAA==.',
Aq='Aquastar:BAAALgAECgEJAQAAAA==.',
Ar='Archerius:BAAALgADCgcJCwAAAA==.Ardre:BAAALgADCgEJAQABLgAECgMJAwADAAAAAA==.Ariis:BAAALgAECgQJBAAAAA==.Arkanis:BAABLgAECn80AAIEAAkJ3RwGGQCCAgAEAAkJ3RwGGQCCAgAAAA==.Arïel:BAABLgAECn8sAAQFAAkJqxkDDACvAgAFAAkJpxkDDACvAgAGAAMJSQyycQBeAAAHAAEJfRvwZwBFAAAAAA==.',
Az='Azalya:BAAALgAECgQJBAAAAA==.',
Ba='Backstabath:BAAALgAECgkJDgABLgAECgkJFwAIAM4hAA==.Banidor:BAAALgAECgIJAgABLgAFFAQJBAADAAAAAA==.',
Be='Becka:BAAALgADCgEJAQAAAA==.',
Bh='Bhrown:BAAALgAECgMJAwAAAA==.',
Bi='Bishop:BAABLgAECn8iAAMBAAgJjBIuYwCqAQABAAgJjBIuYwCqAQAJAAMJRgnYbgB7AAAAAA==.',
Bl='Bloodlyn:BAAALgADCgUJBQAAAA==.Blueming:BAAALgAECgMJBQAAAA==.',
Bo='Bonsai:BAABLgAECn8WAAMKAAYJFAipRwCsAAALAAYJAwZDZgDDAAAKAAYJnwapRwCsAAAAAA==.',
Br='Broadfang:BAACLgAFFH8lAAMMAAgJQB8FAwBtAQAMAAUJ9yIFAwBtAQANAAcJrBNZDwA4AQAuAAQKfyQABAwACQlPJZ0cAFoCAA0ABwliIpAYAGcCAAwABgnHJJ0cAFoCAA4ABAlWDjciAMMAAAAA.Broconis:BAAALgAECgUJBwABLgAFFAcJAwADAAAAAA==.',
Bu='Bubbleoseven:BAAALgAECgUJEAAAAA==.Bullorly:BAACLgAFFH8iAAIPAAYJISHLKQDCAQAPAAYJISHLKQDCAQAuAAQKfyEAAg8ACQnqJF8KABwDAA8ACQnqJF8KABwDAAAA.Bullwînkle:BAAALgADCgcJBwABLgAECgkJGgAQAD8FAA==.Bungulators:BAEALgAFFAEJAQABLgAFFAIJBgARAEUJAA==.Busuu:BAAALgAFFAEJAQABLgAFFAkJMQASAIkhAA==.',
Ca='Capriestsunn:BAAALgAECgUJDQAAAA==.Casey:BAAALgAECgEJAQAAAA==.Catirus:BAAALgAECgEJAQAAAA==.',
Ch='Chunt:BAAALgAECgEJAQAAAA==.',
Cl='Clickshot:BAACLgAFFH8RAAIMAAQJHiRoGgCdAQAMAAQJHiRoGgCdAQAuAAQKf0wAAwwACQk/JlgCAGwDAAwACQk/JlgCAGwDAA0ABAkEEv1ZANwAAAAA.Clipe:BAAALgAECgcJCwAAAA==.Clipee:BAAALgAECgkJEgAAAA==.Clipeskeg:BAABLgAECn8jAAMTAAkJQhzODgBNAgATAAkJQhzODgBNAgAUAAEJFwuylQA6AAAAAA==.Clipex:BAAALgAECgkJEAAAAA==.',
Co='Connor:BAAALgAFFAEJAQAAAA==.Contagium:BAAALgAECgQJCgAAAA==.',
Cr='Crunchberry:BAABLgAFFH8JAAIVAAQJyBCgBQA8AQAVAAQJyBCgBQA8AQAAAA==.Cryptus:BAAALgADCgMJAQABLgAECggJHwAWABcgAA==.',
Cy='Cynicboom:BAAALgADCgQJBAAAAA==.Cynîc:BAAALgAECggJCgAAAA==.',
['Cø']='Cønståntine:BAAALgAECgEJAQAAAA==.',
Da='Daddynature:BAAALgAECgUJDQAAAA==.Daddyÿ:BAAALgAECgYJBgAAAA==.Darenas:BAABLgAECn8oAAMGAAkJlxgEFwAuAgAGAAkJlxgEFwAuAgAFAAEJpA1gfgAtAAAAAA==.Darkspyro:BAAALgADCgEJAQAAAA==.Dasu:BAABLgAECn82AAQIAAkJjw+BOwCmAQAIAAkJjw+BOwCmAQACAAYJNAhpTwDPAAAXAAMJUQKiLgBSAAAAAA==.David:BAAALgADCgcJDwAAAA==.',
De='Deathbooze:BAACLgAFFH8WAAIPAAUJ/CC1OwCCAQAPAAUJ/CC1OwCCAQAuAAQKfywAAg8ACQl2IcYWAL4CAA8ACQl2IcYWAL4CAAAA.Deathmikee:BAACLgAFFH8MAAMSAAQJpxexGQAZAQASAAQJkRexGQAZAQAPAAMJnBBOoQDTAAAuAAQKf0IAAg8ACQkEIqcKABoDAA8ACQkEIqcKABoDAAAA.Demonea:BAAALgAECgEJAQAAAA==.Demonrush:BAAALgAECgEJAQABLgAFFAEJBAADAAAAAA==.Deyst:BAAALgADCgkJCQABLgAECgEJAQADAAAAAA==.',
Di='Dimethaline:BAAALgADCgcJBwAAAA==.Dinlek:BAAALgAECgkJDwAAAA==.Dinosoars:BAAALgADCgEJAQAAAA==.',
Dk='Dkmountain:BAABLgAECn8fAAIGAAcJGyFPEwBaAgAGAAcJGyFPEwBaAgAAAA==.',
Dr='Draknol:BAABLgAECn8bAAIOAAkJbwWWKwBGAQAOAAkJbwWWKwBGAQAAAA==.Drakos:BAABLgAECn8XAAMYAAkJhwTSFgARAQAYAAkJ0gPSFgARAQAQAAYJ9wMsBQB9AAAAAA==.Drunknfist:BAAALgAECgYJBwAAAA==.',
Du='Durton:BAACLgAFFH8OAAILAAQJOxoqFwBYAQALAAQJOxoqFwBYAQAuAAQKfykAAgsACQnQHzkYAIoCAAsACQnQHzkYAIoCAAAA.',
Ec='Echidna:BAABLgAFFH8GAAIMAAMJ+xWjZQDaAAAMAAMJ+xWjZQDaAAABLgAFFAYJGgAZAMIhAA==.Echø:BAAALgADCgUJBQAAAA==.',
Ed='Edison:BAACLgAFFH8QAAILAAQJoiHBEACBAQALAAQJoiHBEACBAQAuAAQKfzYAAwsACQlyIdwMAJ4CAAsACQlyIdwMAJ4CAAoAAwmAGzpHAK0AAAAA.Edrency:BAAALgADCgYJBgAAAA==.',
Ef='Eferis:BAAALgAECgkJDwAAAA==.',
El='Elder:BAAALgAECgYJBgAAAA==.Elderdorje:BAACLgAFFH8PAAIWAAQJgRAUMwDiAAAWAAQJgRAUMwDiAAAuAAQKfzAAAxYACQlMHbcTAH4CABYACQlMHbcTAH4CABQAAQnuAf6JACQAAAAA.Elesa:BAAALgADCgEJAQAAAA==.Elixe:BAAALgADCgEJAQAAAA==.Elondre:BAABLgAECn9OAAMEAAkJVCaxAADZAwAEAAkJVCaxAADZAwAZAAEJ/wa9pQAyAAAAAA==.',
Em='Emomorf:BAABLgAECn8YAAIaAAcJRxAtLwAMAQAaAAcJRxAtLwAMAQAAAA==.Employee:BAACLgAFFH8eAAILAAcJtx0TAwDGAQALAAcJtx0TAwDGAQAuAAQKfyIAAwsACQmvJVYBALsDAAsACQmvJVYBALsDABEAAwmCGvoxALUAAAAA.',
Es='Estias:BAAALgAECgcJCAAAAA==.',
Ev='Evangeliné:BAABLgAECn8UAAIBAAYJ0gQoAwG0AAABAAYJ0gQoAwG0AAABLgAECgkJSQAHAHkZAA==.',
Ex='Exavier:BAAALgADCgQJBAAAAA==.Execfive:BAAALgAECgEJAQAAAA==.',
Fe='Femboi:BAABLgAECn8UAAIbAAgJFxFaUgCPAQAbAAgJFxFaUgCPAQABLgAECggJFgAUADYcAA==.',
Fi='Fistsofseno:BAAALgAECgkJCgAAAA==.Fizzenator:BAACLgAFFH8JAAIOAAMJBh8qGgAAAQAOAAMJBh8qGgAAAQAuAAQKfyoAAg4ACQlfHLgJAIMCAA4ACQlfHLgJAIMCAAAA.',
Fr='Freshlight:BAAALgAECgYJBgABLgAFFAQJDAAWAFwaAA==.',
Fw='Fweeb:BAAALgAECgMJAwAAAA==.',
Ga='Galak:BAAALgAECgEJAQABLgAFFAYJFgABAN0aAA==.Galatea:BAACLgAFFH8WAAIBAAYJ3RokHgCQAQABAAYJ3RokHgCQAQAuAAQKfyoAAgEACQmbIrsNAPcCAAEACQmbIrsNAPcCAAAA.Galifen:BAACLgAFFH8PAAICAAQJZSURDwCxAQACAAQJZSURDwCxAQAuAAQKf1AAAgIACQl9JmoAAJADAAIACQl9JmoAAJADAAAA.Gank:BAABLgAFFH8JAAMcAAQJiBh9BgAIAQAcAAMJcx99BgAIAQAdAAEJyAMXPgBDAAAAAA==.Gargyll:BAAALgADCgUJBQAAAA==.Garysparks:BAAALgAECgEJAgAAAA==.',
Ge='Gelidon:BAABLgAECn8yAAMeAAkJshlhCgA7AgAeAAkJshlhCgA7AgAfAAgJZQzdNQBZAQAAAA==.Getoutalive:BAAALgADCgEJAQAAAA==.',
Gh='Ghreen:BAABLgAECn8aAAIUAAkJ/Rw1DgBkAgAUAAkJ/Rw1DgBkAgAAAA==.',
Gi='Gilgahmesh:BAABLgAECn8vAAMgAAkJGQyNGwA7AQAgAAkJGQyNGwA7AQABAAEJaQN3WAEmAAABLgAFFAQJBwAPACwCAA==.',
Gn='Gnomegrown:BAABLgAECn8zAAICAAgJYxiaGgD2AQACAAgJYxiaGgD2AQAAAA==.',
Go='Goy:BAAALgAFFAIJAwAAAA==.',
Gr='Gragehorn:BAAALgAECgEJAQAAAA==.Grapejuice:BAAALgAECgEJAQAAAA==.Gruvi:BAAALgAECgEJAQAAAA==.',
Gu='Gumbusta:BAAALgAECgcJDwAAAA==.Gummiie:BAAALgADCgEJAQAAAA==.Gunrunner:BAAALgADCgcJBwAAAA==.',
Ha='Halestorm:BAAALgADCgYJBgAAAA==.Halyer:BAABLgAECn8eAAMeAAkJuA6+EwCOAQAeAAgJvA6+EwCOAQAfAAYJjAQWagCdAAAAAA==.Hamalainen:BAAALgAECgUJAwABLgAFFAQJDAAWAFwaAA==.Hankthesnake:BAAALgADCgcJGwABLgAECgMJAwADAAAAAA==.',
He='Helioboops:BAAALgAECgQJBAAAAA==.Hexdaman:BAAALgAECgMJBQAAAA==.',
Hi='Highcurious:BAAALgAECgYJBwABLgAFFAQJDAAWAFwaAA==.',
Ho='Hobbz:BAACLgAFFH8qAAIBAAcJlxnHAwC2AQABAAcJlxnHAwC2AQAuAAQKfy8AAgEACQm2JB0HAF8DAAEACQm2JB0HAF8DAAAA.Hodge:BAAALgADCgMJAwAAAA==.Hoid:BAAALgADCgkJCgAAAA==.Holyfans:BAAALgAFFAQJBAAAAA==.',
['Hó']='Hólythunder:BAAALgAECgIJAgAAAA==.',
Il='Illandros:BAABLgAECn8rAAIGAAkJFhKfJQCeAQAGAAkJFhKfJQCeAQAAAA==.Illidankmeme:BAAALgADCgIJAgAAAA==.',
In='Infernogirl:BAAALgAECgcJCAAAAA==.Ingredient:BAABLgAECn8oAAIXAAkJzxMeDAD3AQAXAAkJzxMeDAD3AQAAAA==.Inspire:BAACLgAFFH8LAAMIAAcJshv5EADwAQAIAAcJshv5EADwAQACAAMJHQZ8NwCgAAAuAAQKfxUAAggACAn3HDAjAC8CAAgACAn3HDAjAC8CAAAA.',
Is='Isinia:BAABLgAECn8aAAIQAAkJPwWphgAsAQAQAAkJPwWphgAsAQAAAA==.',
Ja='Janitor:BAAALgADCgMJAgAAAA==.Jayas:BAABLgAECn8fAAIWAAgJFyCCCwDgAgAWAAgJFyCCCwDgAgAAAA==.Jayim:BAABLgAFFH8GAAIIAAMJvAGiVgBtAAAIAAMJvAGiVgBtAAAAAA==.Jaína:BAABLgAECn8aAAIVAAgJ/gtZgwBxAQAVAAgJ/gtZgwBxAQABLgAECggJJwABAAccAA==.',
Jc='Jcvd:BAAALgADCgQJBAABLgAFFAQJDAAWAFwaAA==.',
Je='Jencks:BAAALgAECgUJCQABLgAECgkJLQACAG8ZAA==.',
Ji='Jiren:BAACLgAFFH8MAAIWAAQJXBq1JgA5AQAWAAQJXBq1JgA5AQAuAAQKfzoAAxYACQmSISUHAC4DABYACQmSISUHAC4DABQAAwkTEERwAHAAAAAA.',
Jo='Johnson:BAABLgAECn8rAAIRAAkJyhvxBwB+AgARAAkJyhvxBwB+AgAAAA==.Johnsunwell:BAAALgADCgQJAwAAAA==.Joran:BAABLgAECn86AAIBAAkJYRZWMQA7AgABAAkJYRZWMQA7AgAAAA==.Jormungandr:BAAALgAECgIJAgABLgAFFAQJDAAWAFwaAA==.',
Ju='Juckbolas:BAAALgAECgQJBAAAAA==.Juicyjj:BAABLgAECn8ZAAIPAAgJCw3OlAA+AQAPAAgJCw3OlAA+AQAAAA==.Jukesnaxx:BAAALgAECgMJBQAAAA==.',
['Jë']='Jësûs:BAAALgAECgEJAQAAAA==.',
Ka='Kaije:BAAALgADCgMJAwAAAA==.',
Ke='Kelekii:BAAALgADCgIJAgAAAA==.',
Ki='Killnoobs:BAAALgADCgEJAQAAAA==.',
Kr='Kravoxx:BAAALgADCgUJCQABLgAFFAQJBAADAAAAAA==.Kro:BAABLgAECn8pAAIBAAgJaRWwAwAEAQABAAgJaRWwAwAEAQAAAA==.Krysess:BAAALgADCgEJAQAAAA==.Krèios:BAAALgAECgcJCAABLgAFFAUJEgAbAB8OAA==.',
La='Laenea:BAAALgAECgkJCQAAAA==.',
Le='Leanea:BAAALgAECgMJAwAAAA==.Lenayuh:BAAALgAECgYJCgAAAA==.',
Li='Lich:BAAALgAFFAQJAgAAAA==.Liera:BAABLgAECn8sAAIPAAkJxRjqJwBiAgAPAAkJxRjqJwBiAgAAAA==.',
Ll='Lloydlei:BAABLgAECn8yAAQQAAkJBh0kHgBwAgAQAAkJdxwkHgBwAgAYAAQJ5hUPFgAZAQAhAAMJEhd2JgCBAAAAAA==.',
Lo='Lodin:BAAALgAECgcJBwABLgAFFAUJEAAdANQHAA==.',
Lu='Luminå:BAABLgAECn8gAAIhAAkJZhgpDAB8AQAhAAkJZhgpDAB8AQAAAA==.',
Ly='Lylenn:BAAALgAECgYJBgAAAA==.',
Ma='Madora:BAAALgADCgQJBAAAAA==.Maibisan:BAABLgAECn9QAAMaAAkJLSYLAQBzAwAaAAkJLSYLAQBzAwAbAAkJDiWyAwBMAwAAAA==.Malificent:BAABLgAECn8dAAIQAAcJ7R35PQDkAQAQAAcJ7R35PQDkAQAAAA==.Malighn:BAACLgAFFH8HAAIPAAQJLAJ6pwDNAAAPAAQJLAJ6pwDNAAAuAAQKfzEAAg8ACQlSCZBrAI4BAA8ACQlSCZBrAI4BAAAA.Masseffex:BAABLgAECn8VAAMCAAgJzRQ+IQC+AQACAAgJzRQ+IQC+AQAIAAIJAw/MowBpAAAAAA==.',
Mc='Mcshooty:BAAALgAECgYJDAAAAA==.',
Mo='Modi:BAAALgAECgEJAQAAAA==.Mookong:BAAALgADCgEJAQAAAA==.Moonsliver:BAAALgAECgEJBAAAAA==.Mordecâi:BAAALgAECgEJAQAAAA==.Morf:BAAALgAECgMJAwABLgAECgkJMgAeALIZAA==.Morganä:BAAALgAECgQJDgAAAA==.Morthrin:BAABLgAECn8VAAIIAAkJ5hS3JwATAgAIAAkJ5hS3JwATAgAAAA==.',
Mu='Muhrieyuh:BAAALgADCgQJBAAAAA==.',
My='Mysticdibs:BAAALgAECgEJAQAAAA==.Mystwolf:BAABLgAECn9EAAIEAAkJxh0AAQCxAQAEAAkJxh0AAQCxAQAAAA==.',
Ne='Ned:BAAALgAECgcJCAABLgAECggJDwADAAAAAA==.Negora:BAAALgAECgEJAQAAAA==.Nelaris:BAAALgADCgEJAQAAAA==.',
Ni='Niccelndime:BAABLgAECn8VAAIOAAYJ5Bt7IgCJAQAOAAYJ5Bt7IgCJAQAAAA==.Nightember:BAABLgAECn8iAAQeAAkJHxFhEADGAQAeAAgJoRFhEADGAQAfAAkJjQ+2IgDFAQAiAAEJgAmYJwAuAAABLgAFFAQJDwAWAIEQAA==.Nightski:BAABLgAECn8qAAIIAAkJgBf1IABAAgAIAAkJgBf1IABAAgAAAA==.Nikolatesla:BAAALgAECgcJDgAAAA==.Nizzari:BAACLgAFFH8QAAIdAAUJ1AcMIgAVAQAdAAUJ1AcMIgAVAQAuAAQKf1UABB0ACQkyHZoHAK8CAB0ACQkyHZoHAK8CABwAAgkdCv8eAGYAACMAAQmUB48nACcAAAAA.',
No='Nomas:BAAALgAECgYJBgAAAA==.Nothalyer:BAABLgAECn80AAIeAAkJ+g4vEgCmAQAeAAkJ+g4vEgCmAQAAAA==.',
Of='Offline:BAABLgAECn8XAAIIAAgJziHEDAD4AgAIAAgJziHEDAD4AgAAAA==.',
Oh='Ohms:BAACLgAFFH8IAAIVAAMJcgeHjwC5AAAVAAMJcgeHjwC5AAAuAAQKfzcAAhUACQmeGvE1AEECABUACQmeGvE1AEECAAAA.',
Ol='Olaria:BAAALgADCgYJGQAAAA==.',
Or='Orwasithim:BAAALgAECgYJCgABLgAECggJIQALAJsTAA==.Orwasitme:BAAALgAECggJDgABLgAECggJIQALAJsTAA==.Orwasitshrek:BAABLgAECn8hAAMLAAgJmxP4LACeAQALAAgJmxP4LACeAQAKAAEJ0AmUgAApAAAAAA==.Orwasitwrekt:BAAALgADCgkJCQABLgAECggJIQALAJsTAA==.',
Pa='Palabop:BAAALgAECgYJEQAAAA==.Paladinii:BAAALgAFFAEJAQAAAA==.',
Pj='Pjxyo:BAAALgAECgUJBQAAAA==.',
Pl='Planec:BAAALgAECgYJBgAAAA==.',
Po='Polytots:BAACLgAFFH8PAAMEAAYJzAJxNgAJAQAEAAYJzAJxNgAJAQAZAAUJZQzZKwDlAAAuAAQKfzIAAwQACQlRERdDAKEBAAQACAlSEhdDAKEBABkACQlUE/YxAHUBAAAA.',
Pr='Proteus:BAAALgADCgMJAwAAAA==.',
Qi='Qiller:BAAALgAECggJDwAAAA==.',
Qu='Quinne:BAAALgADCgEJAQABLgAECgEJAQADAAAAAA==.',
Ra='Ranin:BAABLgAECn8bAAIaAAkJiRdCDQBRAgAaAAkJiRdCDQBRAgAAAA==.Razius:BAAALgAECgkJEgAAAA==.',
Ri='Ricklepick:BAABLgAECn8aAAMIAAYJDBX3RgB0AQAIAAYJDBX3RgB0AQACAAEJ0wkllAArAAABLgAFFAQJDAAWAFwaAA==.Riplordfire:BAAALgAECgEJAQAAAA==.',
Ro='Roadsign:BAAALgAECgYJEAAAAA==.Rottey:BAAALgAECgMJAwAAAA==.Roxette:BAAALgADCgcJBwAAAA==.',
Ry='Ryzenther:BAAALgAECgcJEgAAAA==.',
Sa='Salvation:BAAALgAECgkJEgAAAA==.Sanctis:BAAALgAECgYJCQAAAA==.Santan:BAAALgADCgIJAgAAAA==.Satrat:BAAALgAFFAEJAQAAAA==.',
Sc='Scarecrow:BAAALgAECgEJAgAAAA==.',
Se='Sealgair:BAAALgAECgEJBgAAAA==.Senovourer:BAABLgAECn8fAAIbAAkJjCEJCwAqAwAbAAkJjCEJCwAqAwAAAA==.',
Sh='Shabamoo:BAABLgAECn86AAMIAAkJsyAUBgBXAwAIAAkJsyAUBgBXAwAXAAEJggcuWQApAAAAAA==.Shakkes:BAAALgAECgEJAQAAAA==.Shasato:BAACLgAFFH8RAAIkAAQJpx7uCABlAQAkAAQJpx7uCABlAQAuAAQKf0UAAiQACAlCJNENAAUCACQACAlCJNENAAUCAAAA.Shazrast:BAAALgAECgUJBAAAAA==.Shelian:BAAALgAECgEJAQAAAA==.Shiranai:BAAALgAECgEJAQAAAA==.Shoosty:BAAALgADCgcJDAAAAA==.',
Si='Sicarii:BAAALgADCgcJCAAAAA==.Sindora:BAAALgADCgYJBgAAAA==.Sizouze:BAABLgAECn8tAAIHAAgJIAxjLwBUAQAHAAgJIAxjLwBUAQAAAA==.',
Sk='Skeeter:BAAALgAFFAQJBAAAAA==.Sklonda:BAAALgADCgYJBgAAAA==.Skyepic:BAACLgAFFH8mAAMJAAkJEx1KAABNAgAJAAkJEx1KAABNAgABAAMJMwLLoQB8AAAuAAQKfy8AAwkACQnrIuAGAB4DAAkACQnrIuAGAB4DAAEABAllEn7VAOAAAAAA.Skylight:BAAALgAECgEJAQAAAA==.',
Sn='Sneakfu:BAAALgAECgEJAQAAAA==.Snugwalnut:BAACLgAFFH8fAAIEAAcJHyCGCwAZAgAEAAcJHyCGCwAZAgAuAAQKfzcAAgQACAlHI0YOAOICAAQACAlHI0YOAOICAAAA.',
So='Soejoedi:BAABLgAECn8tAAICAAkJbxnREQBKAgACAAkJbxnREQBKAgAAAA==.',
Sp='Spicyburrito:BAAALgAECgkJDwAAAA==.',
St='Stitchzpls:BAAALgAECgcJCwAAAA==.',
Su='Sunhammer:BAAALgAECgEJAQAAAA==.Sunsworn:BAAALgAECgQJBwAAAA==.',
Sw='Sweetyboi:BAAALgAECgYJDwAAAA==.',
Sy='Sythar:BAAALgAECgEJAQAAAA==.',
Ta='Taintedrush:BAAALgAFFAEJBAAAAA==.Tarhostamir:BAABLgAECn8dAAICAAcJVxD7NABEAQACAAcJVxD7NABEAQAAAA==.Taurup:BAAALgAECgcJEAABLgAFFAUJEAAdANQHAA==.Tazz:BAABLgAECn8dAAIMAAgJUgaEiAAtAQAMAAgJUgaEiAAtAQAAAA==.',
Te='Tecnine:BAAALgADCgUJBQAAAA==.Teledar:BAAALgAECgQJCAAAAA==.',
Th='Thaluus:BAAALgADCgYJDQAAAA==.Thaysinga:BAAALgAFFAMJBAAAAA==.Thelandlord:BAACLgAFFH8UAAIeAAYJahVpBQChAQAeAAYJahVpBQChAQAuAAQKfxwAAx4ACAkOG9oMAGgCAB4ACAkOG9oMAGgCACIAAwnJDqIvAJoAAAAA.Theshape:BAAALgADCgMJAwAAAA==.Thunderblast:BAABLgAECn8jAAILAAgJ5SRnCADZAgALAAgJ5SRnCADZAgAAAA==.Thuss:BAABLgAECn8pAAIbAAkJgxpAHABqAgAbAAkJgxpAHABqAgAAAA==.',
Ti='Titgunniz:BAAALgADCgYJCQAAAA==.',
Tu='Tugnutz:BAAALgAECgUJDQAAAA==.Tuk:BAAALgAECgQJBAAAAA==.',
Tw='Twirlywhirly:BAAALgAECgcJEgAAAA==.',
['Tè']='Tèmpos:BAAALgAECgMJAwAAAA==.',
Ul='Ulansiola:BAAALgAECgMJAwAAAA==.',
Un='Unplug:BAAALgAECgUJDQAAAA==.',
Va='Vaelus:BAAALgADCgMJBAAAAA==.Valkyrrie:BAAALgAECgQJBAABLgAECgkJHgAeALgOAA==.Vander:BAAALgAECgQJBAABLgAECggJHwAWABcgAA==.Vanidossa:BAABLgAECn82AAIGAAkJrxV0FAAqAgAGAAkJrxV0FAAqAgAAAA==.Vannder:BAAALgAECgMJAwAAAA==.Varygud:BAAALgADCgUJBgAAAA==.Vayper:BAACLgAFFH8LAAIGAAMJghO+IwDXAAAGAAMJghO+IwDXAAAuAAQKf1EAAwYACQm5I8sCADkDAAYACQm5I8sCADkDAAUAAQmBBC2GACYAAAAA.',
Ve='Veins:BAAALgAECgEJAQAAAA==.Verdict:BAACLgAFFH8IAAIJAAMJnBMiMwCkAAAJAAMJnBMiMwCkAAAuAAQKfxYAAgkACQkCF90oAMUBAAkACQkCF90oAMUBAAAA.',
Vo='Voklin:BAAALgAECgQJBAAAAA==.',
We='Weemsy:BAABLgAECn87AAILAAkJfiTmAwAoAwALAAkJfiTmAwAoAwAAAA==.',
Wh='Whispyerwild:BAAALgAECgUJBgAAAA==.',
Wi='Wildfire:BAACLgAFFH8lAAIOAAgJNiAVAgAsAgAOAAgJNiAVAgAsAgAuAAQKfzsAAg4ACQntJlsAAIgDAA4ACQntJlsAAIgDAAAA.Wildfirë:BAAALgAECgYJBgABLgAFFAgJJQAOADYgAA==.Willthewise:BAAALgADCgIJAgAAAA==.',
Wo='Wolffei:BAAALgAECgEJAQAAAA==.Wolfhammer:BAABLgAECn84AAIRAAkJvyLrAgAPAwARAAkJvyLrAgAPAwAAAA==.Wolflee:BAAALgAECgYJDwAAAA==.Wolfmend:BAABLgAECn8WAAMIAAYJhhvPQgCGAQAIAAYJhhvPQgCGAQACAAEJ1gKNpgAaAAAAAA==.',
Xa='Xamid:BAAALgAECgYJEAAAAA==.Xanariel:BAAALgADCgMJAwAAAA==.Xaxfen:BAACLgAFFH8XAAIRAAgJ8xVaCQCdAQARAAgJ8xVaCQCdAQAuAAQKfyYABBEACAnjItcJAHoCABEACAnjItcJAHoCAAsABQlEFIlUAPoAAAoAAQkAANuPAAAAAAAA.',
['Xê']='Xêndâr:BAAALgADCgQJBAAAAA==.',
Yo='Yogurt:BAAALgAECgIJAgAAAA==.',
Za='Zappieboy:BAAALgAECgcJDQAAAA==.',
Ze='Zeuree:BAABLgAFFH8GAAIWAAIJWxGfTAB0AAAWAAIJWxGfTAB0AAABLgAFFAMJCgAFALcKAA==.Zeurie:BAABLgAFFH8KAAIFAAMJtwpPNQC2AAAFAAMJtwpPNQC2AAAAAA==.',
Zu='Zulgrimm:BAAALgADCgMJAwAAAA==.',
Zy='Zyfèr:BAABLgAECn8UAAIIAAcJYhFvRgB2AQAIAAcJYhFvRgB2AQAAAA==.',
['Zî']='Zîmìk:BAAALgAECgQJBgAAAA==.',
['Às']='Àsh:BAACLgAFFH8MAAIHAAQJqBsEEQBIAQAHAAQJqBsEEQBIAQAuAAQKfzoAAgcACQnqIlwDAFoDAAcACQnqIlwDAFoDAAAA.',
['Év']='Évangeline:BAAALgAECgQJBAABLgAECgkJSQAHAHkZAA==.',
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
