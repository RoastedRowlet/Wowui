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

local lookup = {'Paladin-Retribution','Druid-Balance','Hunter-BeastMastery','Unknown-Unknown','Shaman-Restoration','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Holy','Warrior-Arms','Warrior-Fury','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Unholy','Warlock-Demonology','Warrior-Protection','Druid-Guardian','DeathKnight-Blood','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Mage-Frost','Druid-Restoration','Druid-Feral','Warlock-Affliction','Shaman-Elemental','DemonHunter-Havoc','Warlock-Destruction','Evoker-Augmentation','DemonHunter-Devourer','Rogue-Assassination','Rogue-Subtlety','Evoker-Preservation','Paladin-Protection','Evoker-Devastation','Rogue-Outlaw','DeathKnight-Frost',}
local provider = {region='US',realm='Executus',name='US',type='weekly',zone=46,date='2026-08-18',data={Ac='Acai:BAAALgAECgYJBgAAAA==.',
Ad='Adolyn:BAAALgADCgkJCQAAAA==.Adventis:BAAALgADCgQJAwAAAA==.',
Ak='Akirix:BAAALgADCgIJAgAAAA==.',
Al='Alfry:BAAALgAECgIJAgAAAA==.Allavus:BAAALgADCgQJBQABLgAFFAcJHwABAGEbAA==.Alodiar:BAAALgAECgMJDgAAAA==.',
Am='Amrin:BAAALgAECgkJCQAAAA==.',
An='Andersen:BAABLgAECn8lAAIBAAgJrR8dLwBEAgABAAgJrR8dLwBEAgAAAA==.Ando:BAAALgAECgEJAQABLgAECgkJLQACAG8ZAA==.Andryu:BAACLgAFFH8dAAICAAUJeg3XFADgAAACAAUJeg3XFADgAAAuAAQKf0YAAgIACQm7HB8KALMCAAIACQm7HB8KALMCAAAA.Anebel:BAAALgADCgkJCQAAAA==.Angelmuerte:BAAALgADCgkJDgAAAA==.Angyal:BAAALgAECgYJBwAAAA==.Annde:BAAALgAECgEJAgAAAA==.Annikya:BAAALgAECgcJBQABLgAECgkJHgADANIGAA==.',
Ap='Apolion:BAAALgADCgYJBgAAAA==.',
Aq='Aquastar:BAAALgAECgEJAQAAAA==.',
Ar='Archerius:BAAALgADCgcJCwAAAA==.Ardre:BAAALgAECgEJAQABLgAECgMJDgAEAAAAAA==.Ariis:BAAALgAECgQJBAAAAA==.Arkanis:BAABLgAECn80AAIFAAkJ3RwHGQCCAgAFAAkJ3RwHGQCCAgAAAA==.Artemus:BAAALgAECgcJBwABLgAFFAgJGAAGABwNAA==.Arïel:BAACLgAFFH8HAAMHAAQJ1QfkFwCfAAAHAAQJ1QfkFwCfAAAIAAIJlQvFPgB+AAAuAAQKfy0ABAgACQmrGQMMAK8CAAgACQmnGQMMAK8CAAcAAwnCDlIjAEYAAAYAAQl9G/NnAEUAAAAA.',
Az='Azalya:BAAALgAECgQJBAAAAA==.',
Ba='Backstabath:BAAALgAECgkJDgABLgAFFAkJCQADADYAAA==.Banidor:BAAALgAECgIJAgABLgAFFAYJBAAEAAAAAA==.',
Be='Becka:BAAALgADCgEJAQAAAA==.',
Bh='Bhrown:BAAALgAECggJCwAAAA==.',
Bi='Bibleo:BAAALgADCgEJAQAAAA==.Bishop:BAABLgAECn8nAAMBAAgJjBIrYwCqAQABAAgJjBIrYwCqAQAJAAUJcw4pDADwAAAAAA==.',
Bl='Bloodlyn:BAAALgADCgUJBQAAAA==.Blueming:BAAALgAECgMJBQAAAA==.',
Bo='Bonsai:BAABLgAECn8WAAMKAAYJFAirRwCsAAALAAYJAwZIZgDDAAAKAAYJnwarRwCsAAAAAA==.',
Br='Broadfang:BAACLgAFFH9IAAMDAAkJ3x8FAwBtAQAMAAgJQBh3AwDcAQADAAcJVyAFAwBtAQAuAAQKfyQABAMACQlPJZ0cAFoCAAwABwliIpAYAGcCAAMABgnHJJ0cAFoCAA0ABAlWDjciAMMAAAAA.Broconis:BAAALgAECgUJBwABLgAFFAEJAQAEAAAAAA==.',
Bu='Bubbleoseven:BAABLgAECn8VAAIBAAYJGhkZGwAGAQABAAYJGhkZGwAGAQAAAA==.Bullorly:BAACLgAFFH8kAAIOAAgJBx+3KQDCAQAOAAgJBx+3KQDCAQAuAAQKfyEAAg4ACQnqJF8KABwDAA4ACQnqJF8KABwDAAAA.Bullwînkle:BAAALgADCgcJBwABLgAECgkJGgAPAD8FAA==.Bungulators:BAEALgAFFAEJAQABLgAFFAQJEAAQAIIVAA==.Busuu:BAABLgAFFH8FAAIRAAMJ/BsACwDiAAARAAMJ/BsACwDiAAABLgAFFAkJQQASAK0iAA==.',
Ca='Capriestsunn:BAAALgAECgUJDQAAAA==.Casey:BAAALgAECgEJAQAAAA==.Catirus:BAAALgAECgEJAQAAAA==.',
Ch='Chareddh:BAAALgAFFAQJBAABLgAFFAUJGwATAEkTAA==.Chunt:BAAALgAECgMJAQAAAA==.',
Cl='Cleo:BAAALgAECgcJCwAAAA==.Clickshot:BAACLgAFFH8ZAAIDAAQJHiRmGgCdAQADAAQJHiRmGgCdAQAuAAQKf0wAAwMACQk/JlcCAGwDAAMACQk/JlcCAGwDAAwABAkEEv1ZANwAAAAA.Clipe:BAAALgAECgcJCwAAAA==.Clipee:BAAALgAECgkJEgAAAA==.Clipeskeg:BAABLgAECn8jAAMUAAkJQhzPDgBNAgAUAAkJQhzPDgBNAgAVAAEJFwuzlQA6AAAAAA==.Clipex:BAAALgAECgkJEAAAAA==.Clipey:BAAALgADCggJCAAAAA==.',
Co='Connor:BAAALgAFFAEJAQAAAA==.Contagium:BAAALgAECgQJCgAAAA==.',
Cr='Crunchberry:BAABLgAFFH8NAAIWAAUJxBG8LgARAQAWAAUJxBG8LgARAQAAAA==.Cryptus:BAAALgADCgMJAQABLgAECgkJHwATABcgAA==.',
Cy='Cynicboom:BAAALgADCgQJBAAAAA==.Cynîc:BAAALgAECggJCgAAAA==.',
['Cø']='Cønståntine:BAAALgAECgEJAQAAAA==.',
Da='Daddynature:BAAALgAECgUJDQAAAA==.Daddyÿ:BAAALgAECgYJBgAAAA==.Darenas:BAABLgAECn8sAAMHAAkJ7RsiCQA3AQAHAAkJ7RsiCQA3AQAIAAEJpA1hfgAtAAAAAA==.Darkspyro:BAAALgADCgEJAQAAAA==.Dasu:BAABLgAECn82AAQXAAkJjw+AOwCmAQAXAAkJjw+AOwCmAQACAAYJNAhwTwDPAAAYAAMJUQKiLgBSAAAAAA==.David:BAAALgADCgcJDwABLgAFFAQJEAANALgbAA==.',
De='Deathbooze:BAACLgAFFH8XAAIOAAYJniCoOwCCAQAOAAYJniCoOwCCAQAuAAQKfywAAg4ACQl2IcYWAL4CAA4ACQl2IcYWAL4CAAAA.Deathmikee:BAACLgAFFH8UAAMOAAUJmRtXJgA+AQAOAAUJahhXJgA+AQASAAQJkReoGQAaAQAuAAQKf0IAAg4ACQkEIqcKABoDAA4ACQkEIqcKABoDAAAA.Delita:BAAALgAECgcJDAAAAA==.Demonea:BAAALgAECgEJAQAAAA==.Demonrush:BAAALgAECgEJAQABLgAFFAIJBQAZAFgLAA==.Deyst:BAAALgADCgkJCQABLgAECgEJAQAEAAAAAA==.',
Di='Dimethaline:BAAALgADCgcJBwAAAA==.Dinlek:BAAALgAECgkJDwAAAA==.Dinosoars:BAAALgADCgEJAQAAAA==.',
Dk='Dkmountain:BAABLgAECn8fAAIHAAcJGyFPEwBaAgAHAAcJGyFPEwBaAgAAAA==.',
Dr='Draknol:BAABLgAECn8iAAINAAkJwwjSAwBnAQANAAkJwwjSAwBnAQAAAA==.Drakos:BAABLgAECn8gAAMPAAkJNwnBDAA0AQAPAAkJNwnBDAA0AQAZAAkJ0gPRFgARAQAAAA==.Drunknfist:BAAALgAECgYJBwAAAA==.',
Du='Durton:BAACLgAFFH8SAAILAAUJmRwcFwBYAQALAAUJmRwcFwBYAQAuAAQKfykAAgsACQnQHzkYAIoCAAsACQnQHzkYAIoCAAAA.',
Ec='Echidna:BAABLgAFFH8GAAIDAAMJ+xWkZQDaAAADAAMJ+xWkZQDaAAABLgAFFAcJIAAaAJwdAA==.Echø:BAAALgAFFAEJAQAAAA==.',
Ed='Edison:BAACLgAFFH8VAAILAAUJoiGwEACBAQALAAUJoiGwEACBAQAuAAQKfz0AAwsACQnnIaoBAK0CAAsACQnnIaoBAK0CAAoAAwmAGzxHAK0AAAAA.Edrency:BAAALgADCgYJBgAAAA==.',
Ef='Eferis:BAAALgAECgkJDwAAAA==.',
El='Elder:BAAALgAECgYJBgAAAA==.Elderdorje:BAACLgAFFH8bAAITAAUJSRPSGQD8AAATAAUJSRPSGQD8AAAuAAQKfzAAAxMACQlMHbUTAH4CABMACQlMHbUTAH4CABUAAQnuAf6JACQAAAAA.Elesa:BAAALgADCgEJAQAAAA==.Elixe:BAAALgADCgEJAQAAAA==.Elondre:BAABLgAECn9XAAMFAAkJVCaxAADZAwAFAAkJVCaxAADZAwAaAAEJ/wbApQAyAAAAAA==.',
Em='Emomorf:BAABLgAECn8YAAIbAAcJRxAvLwAMAQAbAAcJRxAvLwAMAQAAAA==.Employee:BAACLgAFFH8eAAILAAcJtx0TAwDGAQALAAcJtx0TAwDGAQAuAAQKfyIAAwsACQmvJVYBALsDAAsACQmvJVYBALsDABAAAwmCGvoxALUAAAAA.',
Es='Estias:BAABLgAECn8YAAIcAAcJMw/mBAAdAQAcAAcJMw/mBAAdAQAAAA==.',
Ev='Evangeliné:BAABLgAECn8XAAIBAAYJygYrAwG0AAABAAYJygYrAwG0AAABLgAECgkJSgAGAOQZAA==.Evlove:BAAALgADCgIJAgABLgAECggJFwAdALUWAA==.',
Ex='Exavier:BAAALgADCgQJBAAAAA==.Execfive:BAAALgAECgEJAQAAAA==.',
Fe='Femboi:BAACLgAFFH8JAAIeAAMJIBA/LwC6AAAeAAMJIBA/LwC6AAAuAAQKfxUAAh4ACAmAFVdSAI8BAB4ACAmAFVdSAI8BAAAA.',
Fi='Fistsofseno:BAAALgAECgkJCgAAAA==.Fizzenator:BAACLgAFFH8JAAINAAMJBh8pGgAAAQANAAMJBh8pGgAAAQAuAAQKfyoAAg0ACQlfHLYJAIMCAA0ACQlfHLYJAIMCAAAA.',
Fr='Freshlight:BAAALgAECgYJBgABLgAFFAYJFgATAPYbAA==.',
Fu='Fuurak:BAAALgAFFAEJAgAAAA==.',
Fw='Fweeb:BAAALgAECgMJAwAAAA==.',
Ga='Galak:BAAALgAECgEJAQABLgAFFAcJHwABAGEbAA==.Galatea:BAACLgAFFH8fAAIBAAcJYRviDACrAQABAAcJYRviDACrAQAuAAQKfzIAAgEACQnGIr0NAPcCAAEACQnGIr0NAPcCAAAA.Galifen:BAACLgAFFH8jAAICAAUJZSUEDwCxAQACAAUJZSUEDwCxAQAuAAQKf1AAAgIACQl9JmoAAJADAAIACQl9JmoAAJADAAAA.Gank:BAABLgAFFH8NAAMfAAQJxxl9BgAIAQAfAAMJcx99BgAIAQAgAAEJxAiDKQBDAAAAAA==.Gargyll:BAAALgADCgUJBQAAAA==.Garysparks:BAAALgAECgEJAgAAAA==.',
Ge='Gelidon:BAABLgAECn8yAAMhAAkJshlhCgA7AgAhAAkJshlhCgA7AgAdAAgJZQzfNQBZAQAAAA==.Getoutalive:BAAALgADCgEJAQAAAA==.',
Gh='Ghreen:BAABLgAECn8aAAIVAAkJER01DgBkAgAVAAkJER01DgBkAgAAAA==.',
Gi='Gilgahmesh:BAABLgAECn85AAMiAAkJWgyKBwD6AAAiAAkJWgyKBwD6AAABAAEJaQN3WAEmAAABLgAFFAQJBwAOACwCAA==.',
Gn='Gnomegrown:BAABLgAECn9BAAICAAkJExpeAwAJAgACAAkJExpeAwAJAgAAAA==.',
Go='Gobi:BAAALgAECgMJAwAAAA==.Goy:BAAALgAFFAIJAwAAAA==.',
Gr='Gragehorn:BAAALgAECgEJAQAAAA==.Grapejuice:BAAALgAECgEJAQAAAA==.Gruvi:BAAALgAECgEJAQAAAA==.',
Gu='Gumbusta:BAAALgAECgcJDwAAAA==.Gummiie:BAAALgADCgEJAQAAAA==.Gunrunner:BAAALgADCgcJBwAAAA==.',
Ha='Halestorm:BAAALgADCgYJBgAAAA==.Halyer:BAABLgAECn8fAAMhAAkJuA6+EwCOAQAhAAgJvA6+EwCOAQAdAAYJMAUYagCdAAAAAA==.Hamalainen:BAAALgAECgUJAwABLgAFFAYJFgATAPYbAA==.Hankthesnake:BAAALgADCgcJGwABLgAECgMJAwAEAAAAAA==.',
He='Helioboops:BAAALgAECgQJBAAAAA==.Hexdaman:BAAALgAECgkJBgAAAA==.',
Hi='Highcurious:BAAALgAECgYJBwABLgAFFAYJFgATAPYbAA==.',
Ho='Hobbz:BAACLgAFFH84AAIBAAkJLx7KAwCNAgABAAkJLx7KAwCNAgAuAAQKfy8AAgEACQm2JB0HAF8DAAEACQm2JB0HAF8DAAAA.Hodge:BAAALgADCgMJAwAAAA==.Hoid:BAAALgADCgkJCgAAAA==.Holyfans:BAAALgAFFAYJBAAAAA==.',
['Hó']='Hólythunder:BAAALgAECgIJAgAAAA==.',
Il='Illandros:BAABLgAECn8yAAIHAAkJ+hW8AwDqAQAHAAkJ+hW8AwDqAQAAAA==.Illidankmeme:BAAALgAECgUJBQAAAA==.',
In='Infernogirl:BAAALgAECgcJDgAAAA==.Ingredient:BAABLgAECn8oAAIYAAkJzxMfDAD3AQAYAAkJzxMfDAD3AQAAAA==.Inspire:BAACLgAFFH8iAAMXAAkJfiUsAADaAwAXAAkJfiUsAADaAwACAAMJHQZ3NwCgAAAuAAQKfxUAAhcACAn3HDAjAC8CABcACAn3HDAjAC8CAAAA.',
Is='Isinia:BAABLgAECn8aAAIPAAkJPwWshgAsAQAPAAkJPwWshgAsAQAAAA==.',
Ja='Janitor:BAAALgADCgMJAgAAAA==.Jayas:BAABLgAECn8fAAITAAgJFyCACwDgAgATAAgJFyCACwDgAgAAAA==.Jayim:BAABLgAFFH8GAAIXAAMJvAGfVgBtAAAXAAMJvAGfVgBtAAAAAA==.Jaína:BAABLgAECn8aAAIWAAgJ/gtagwBxAQAWAAgJ/gtagwBxAQABLgAECggJKQABAEMdAA==.',
Jc='Jcvd:BAAALgADCgQJBAABLgAFFAYJFgATAPYbAA==.',
Je='Jencks:BAAALgAECgUJCQABLgAECgkJLQACAG8ZAA==.',
Ji='Jiren:BAACLgAFFH8WAAITAAYJ9huOCQABAgATAAYJ9huOCQABAgAuAAQKfz4AAxMACQmMIiMHAC4DABMACQmMIiMHAC4DABUAAwkTEERwAHAAAAAA.',
Jo='Johnson:BAABLgAECn8xAAIQAAkJ9BvwBwB+AgAQAAkJ9BvwBwB+AgAAAA==.Johnsunwell:BAAALgADCgQJAwAAAA==.Joran:BAABLgAECn9GAAIBAAkJHxc9CgDKAQABAAkJHxc9CgDKAQAAAA==.Jormungandr:BAAALgAFFAIJAgABLgAFFAYJFgATAPYbAA==.',
Ju='Juckbolas:BAAALgAECgQJBAAAAA==.Juicyjj:BAABLgAECn8ZAAIOAAgJCw3QlAA+AQAOAAgJCw3QlAA+AQAAAA==.Jukesnaxx:BAAALgAECgMJBQAAAA==.',
['Jë']='Jësûs:BAAALgAECgEJAQAAAA==.',
Ka='Kaije:BAAALgADCgMJAwAAAA==.',
Ke='Kelekii:BAAALgADCgIJAgAAAA==.',
Ki='Killnoobs:BAAALgADCgEJAQAAAA==.',
Kr='Kraftur:BAAALgAECgEJAQAAAA==.Kravoxx:BAAALgADCgUJCQABLgAFFAYJBAAEAAAAAA==.Kro:BAABLgAECn8wAAIBAAkJWhcCCwC6AQABAAkJWhcCCwC6AQAAAA==.Krysess:BAAALgADCgEJAQAAAA==.Krèios:BAAALgAECgcJCAABLgAFFAUJEgAeAB8OAA==.',
Ky='Kyllaria:BAAALgADCggJBwABLgAECgcJDgAEAAAAAA==.',
La='Laenea:BAAALgAECgkJCQAAAA==.Lastrite:BAAALgADCgMJAwAAAA==.Laststop:BAAALgADCgEJAgAAAA==.',
Le='Leanea:BAAALgAECgQJBAAAAA==.Lenayuh:BAAALgAECgYJCwAAAA==.',
Li='Lich:BAAALgAFFAQJAgAAAA==.Liera:BAABLgAECn8sAAIOAAkJxRjrJwBiAgAOAAkJxRjrJwBiAgAAAA==.',
Ll='Lloydlei:BAACLgAFFH8JAAMZAAQJeQXbCACZAAAZAAMJqgPbCACZAAAPAAMJ2gQ4RQCEAAAuAAQKfzIABA8ACQkGHSQeAHACAA8ACQl3HCQeAHACABkABAnmFQ4WABkBABwAAwkSF3gmAIEAAAAA.',
Lo='Lodin:BAAALgAECgcJBwABLgAFFAYJEQAgAOIGAA==.',
Lu='Luminâ:BAAALgAECgMJAwABLgAECgkJIQAcAJsZAA==.Luminå:BAABLgAECn8hAAIcAAkJmxkpDAB8AQAcAAkJmxkpDAB8AQAAAA==.',
Ly='Lylenn:BAAALgAECgYJBgAAAA==.',
Ma='Madora:BAAALgADCgQJBAAAAA==.Maibisan:BAABLgAECn9aAAMbAAkJLSYLAQBzAwAbAAkJLSYLAQBzAwAeAAkJTiWyAwBMAwAAAA==.Malificent:BAABLgAECn8dAAIPAAcJ7R36PQDkAQAPAAcJ7R36PQDkAQAAAA==.Malighn:BAACLgAFFH8HAAIOAAQJLAJ2pwDNAAAOAAQJLAJ2pwDNAAAuAAQKfzEAAg4ACQlSCZBrAI4BAA4ACQlSCZBrAI4BAAAA.Masseffex:BAABLgAECn8VAAMCAAgJzRRCIQC+AQACAAgJzRRCIQC+AQAXAAIJAw/LowBpAAAAAA==.Mattallica:BAAALgAECgEJAQAAAA==.',
Mc='Mcshooty:BAAALgAECgYJDAAAAA==.',
Me='Metashaman:BAACLgAFFH8OAAIaAAUJpAqtGADUAAAaAAUJpAqtGADUAAAuAAQKfxUAAxoACQlJFUYlAL4BABoACQlJFUYlAL4BAAUAAQlnEgHYADEAAAAA.',
Mi='Mitissix:BAAALgAECgYJBgAAAA==.Miziry:BAAALgAECgYJBgAAAA==.',
Mo='Modi:BAAALgAECgEJAQAAAA==.Monawah:BAAALgAECgUJEAAAAA==.Mookong:BAAALgADCgEJAQAAAA==.Moonsliver:BAAALgAECgEJBAAAAA==.Mordecâi:BAAALgAECgEJAQAAAA==.Morf:BAAALgAECgMJAwABLgAECgkJMgAhALIZAA==.Morganä:BAAALgAECgQJDgAAAA==.Morthrin:BAABLgAECn8VAAIXAAkJ5hS1JwATAgAXAAkJ5hS1JwATAgAAAA==.',
Mu='Muhrieyuh:BAAALgADCgQJBAAAAA==.',
My='Mysticdibs:BAAALgAECgEJAQAAAA==.Mystwolf:BAABLgAECn9EAAIFAAkJxh2TFABwAgAFAAkJxh2TFABwAgAAAA==.',
Ne='Ned:BAAALgAECgcJCAABLgAECggJDwAEAAAAAA==.Nelaris:BAAALgADCgEJAQAAAA==.',
Ni='Niccelndime:BAABLgAECn8VAAINAAYJ5Bt7IgCJAQANAAYJ5Bt7IgCJAQAAAA==.Nightember:BAABLgAECn8iAAQhAAkJHxFgEADGAQAhAAgJoRFgEADGAQAdAAkJjQ+3IgDFAQAjAAEJgAmYJwAuAAABLgAFFAUJGwATAEkTAA==.Nightski:BAABLgAECn8qAAIXAAkJgBfzIABAAgAXAAkJgBfzIABAAgAAAA==.Nikolatesla:BAAALgAECgcJDgAAAA==.Nizzari:BAACLgAFFH8RAAIgAAYJ4gYIIgAVAQAgAAYJ4gYIIgAVAQAuAAQKf1UABCAACQkyHZsHAK8CACAACQkyHZsHAK8CAB8AAgkdCgEfAGYAACQAAQmUB44nACcAAAAA.',
No='Nomas:BAAALgAECgYJBgAAAA==.Nothalyer:BAABLgAECn80AAIhAAkJ+g4uEgCmAQAhAAkJ+g4uEgCmAQAAAA==.',
Of='Offline:BAABLgAECn8XAAIXAAgJziHCDAD4AgAXAAgJziHCDAD4AgABLgAFFAkJCQADADYAAA==.',
Oh='Ohms:BAACLgAFFH8IAAIWAAMJcgdtjwC5AAAWAAMJcgdtjwC5AAAuAAQKfzcAAhYACQmeGu41AEECABYACQmeGu41AEECAAAA.',
Ol='Olaria:BAAALgADCgYJGQAAAA==.',
Or='Orwasithim:BAABLgAECn8UAAMlAAYJcRCbBgD5AAAlAAUJUA+bBgD5AAAOAAQJRg1vKwCNAAABLgAECggJIQALAJsTAA==.Orwasitme:BAAALgAECggJDgABLgAECggJIQALAJsTAA==.Orwasitshrek:BAABLgAECn8hAAMLAAgJmxP5LACeAQALAAgJmxP5LACeAQAKAAEJ0AmSgAApAAAAAA==.Orwasitwrekt:BAAALgADCgkJCgABLgAECggJIQALAJsTAA==.',
Pa='Palabop:BAAALgAECgYJEQAAAA==.Paladinii:BAAALgAFFAEJAQAAAA==.',
Pj='Pjxyo:BAAALgAFFAMJAwAAAA==.',
Pl='Planec:BAAALgAECgYJBgAAAA==.',
Po='Polytots:BAACLgAFFH8QAAMFAAcJVAVaNgAJAQAFAAYJzAJaNgAJAQAaAAYJmAraKwDlAAAuAAQKfzIAAwUACQlRERxDAKEBAAUACAlSEhxDAKEBABoACQlUE/gxAHUBAAAA.',
Pr='Proteus:BAAALgADCgMJAwAAAA==.',
Qi='Qiller:BAAALgAECggJDwAAAA==.',
Qu='Quinne:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.',
Ra='Ragñar:BAAALgAECgEJBgAAAA==.Ranin:BAACLgAFFH8KAAIbAAMJehgNDADrAAAbAAMJehgNDADrAAAuAAQKfxwAAhsACQn8GEENAFECABsACQn8GEENAFECAAAA.Razius:BAAALgAECgkJEgAAAA==.',
Ri='Ricklepick:BAABLgAECn8aAAMXAAYJDBXzRgB0AQAXAAYJDBXzRgB0AQACAAEJ0wkqlAArAAABLgAFFAYJFgATAPYbAA==.Riplordfire:BAAALgAECgEJAQAAAA==.',
Ro='Roadsign:BAAALgAECgYJEAAAAA==.Rottey:BAAALgAECgMJAwAAAA==.Roxette:BAAALgADCgcJBwAAAA==.',
Ry='Ryzenther:BAABLgAECn8VAAILAAgJXhINDQD7AAALAAgJXhINDQD7AAAAAA==.',
['Rà']='Ràgnar:BAAALgAECgEJAgAAAA==.Ràgñàr:BAAALgAECgEJAQAAAA==.',
Sa='Salvation:BAAALgAECgkJEgAAAA==.Sanctis:BAAALgAECgYJCQAAAA==.Santan:BAAALgADCgIJAgAAAA==.Sarcoblaze:BAAALgAECgUJBQAAAA==.Satrat:BAAALgAFFAEJAQAAAA==.',
Sc='Scarecrow:BAAALgAECgEJAgAAAA==.Scathclipe:BAAALgAECgEJAQAAAA==.',
Se='Senovourer:BAABLgAECn8fAAIeAAkJjCEJCwAqAwAeAAkJjCEJCwAqAwAAAA==.',
Sh='Shabamoo:BAABLgAECn9AAAMXAAkJsyAVBgBXAwAXAAkJsyAVBgBXAwAYAAEJggcxWQApAAAAAA==.Shakkes:BAAALgAECgEJAQAAAA==.Shasato:BAACLgAFFH8mAAMRAAQJuiAzBQBkAQARAAQJuiAzBQBkAQACAAMJaQkXGwCnAAAuAAQKf1kABBEACQkUJA4BALICABEACQkUJA4BALICAAIABgmUGEEHAGIBABgAAQlyGCITAEYAAAAA.Shazrast:BAAALgAECgYJBQAAAA==.Shelian:BAAALgAECgEJAQAAAA==.Shiranai:BAAALgAECgIJAgAAAA==.Shockss:BAAALgAECgcJCwAAAA==.Shoosty:BAAALgADCgcJDAAAAA==.',
Si='Sicarii:BAAALgADCgcJCAAAAA==.Sindora:BAAALgAECgYJBgAAAA==.Sizouze:BAACLgAFFH8IAAIGAAMJ5gQrFgBrAAAGAAMJ5gQrFgBrAAAuAAQKfzoAAgYACQkEDxwIAEQBAAYACQkEDxwIAEQBAAAA.',
Sk='Skeeter:BAABLgAECn8aAAMBAAgJMh4dCAD+AQAiAAcJJx5BAgD+AQABAAgJMxsdCAD+AQABLgAFFAgJDgAcAAUMAA==.Sklonda:BAAALgADCgYJBgAAAA==.Skyepic:BAACLgAFFH86AAMJAAkJzSA/AQD5AgAJAAkJzSA/AQD5AgABAAMJMwLKoQB8AAAuAAQKfy8AAwkACQnrIt8GAB4DAAkACQnrIt8GAB4DAAEABAllEn7VAOAAAAAA.Skylight:BAAALgAFFAIJAgAAAA==.',
Sl='Slapshöt:BAAALgAECgEJAgAAAA==.',
Sn='Sneakfu:BAAALgAECgEJAQAAAA==.Snugwalnut:BAACLgAFFH8gAAIFAAgJoh6CCwAZAgAFAAgJoh6CCwAZAgAuAAQKfzgAAgUACQnYIUUOAOICAAUACQnYIUUOAOICAAAA.',
So='Soejoedi:BAABLgAECn8tAAICAAkJbxnREQBKAgACAAkJbxnREQBKAgAAAA==.',
Sp='Spicyburrito:BAABLgAECn8XAAMCAAkJ/gVwEwCeAAACAAkJ/gVwEwCeAAAXAAEJfQHSAgELAAAAAA==.',
St='Stitchzpls:BAAALgAECgcJDAAAAA==.',
Su='Sunhammer:BAAALgAECgEJAQAAAA==.Sunsworn:BAAALgAECgQJBwAAAA==.',
Sw='Sweetyboi:BAAALgAECgYJDwAAAA==.',
Sy='Sythar:BAAALgAECgEJAQAAAA==.',
Ta='Tabytabb:BAAALgADCgUJBQAAAA==.Taintedrush:BAACLgAFFH8FAAIZAAIJWAtkCgB9AAAZAAIJWAtkCgB9AAAuAAQKfxgAAhkACAmVG7cBANwBABkACAmVG7cBANwBAAAA.Tarhostamir:BAABLgAECn8dAAICAAcJVxD+NABEAQACAAcJVxD+NABEAQAAAA==.Taurup:BAAALgAECgcJEAABLgAFFAYJEQAgAOIGAA==.Tazz:BAABLgAECn8eAAIDAAgJ0gaBiAAtAQADAAgJ0gaBiAAtAQAAAA==.',
Te='Tecnine:BAAALgADCgUJBQAAAA==.Teledar:BAAALgAECgQJCAAAAA==.',
Th='Thaluus:BAAALgAECgMJBQAAAA==.Thaysinga:BAABLgAFFH8FAAIOAAMJCQULxACiAAAOAAMJCQULxACiAAAAAA==.Thelandlord:BAACLgAFFH8UAAIhAAYJahVpBQChAQAhAAYJahVpBQChAQAuAAQKfxwAAyEACAkOG9oMAGgCACEACAkOG9oMAGgCACMAAwnJDqIvAJoAAAAA.Theshape:BAAALgADCgMJAwAAAA==.Thunderblast:BAABLgAECn8jAAILAAgJ5SRpCADZAgALAAgJ5SRpCADZAgAAAA==.Thuss:BAABLgAECn8pAAIeAAkJgxo+HABqAgAeAAkJgxo+HABqAgAAAA==.',
Ti='Titgunniz:BAAALgADCgYJCQAAAA==.',
Tr='Treadstone:BAAALgAECgcJEAABLgAFFAYJFgATAPYbAA==.',
Tu='Tugnutz:BAAALgAECgUJDQAAAA==.Tuk:BAAALgAECgQJBAAAAA==.',
Tw='Twirlywhirly:BAAALgAECgcJEgAAAA==.Twodini:BAAALgAECgEJAQAAAA==.',
['Tè']='Tèmpos:BAAALgAECgMJAwAAAA==.',
Ul='Ulansiola:BAAALgAECgMJAwAAAA==.',
Un='Unplug:BAAALgAECgUJDQAAAA==.',
Va='Vaelus:BAAALgAECgUJBgAAAA==.Valkyrrie:BAAALgAECgQJBAABLgAECgkJHwAhALgOAA==.Vandder:BAAALgADCgYJBQAAAA==.Vander:BAAALgAECgQJBAABLgAECgkJHwATABcgAA==.Vanderre:BAAALgAECgIJAgABLgAECgkJHwATABcgAA==.Vanidossa:BAACLgAFFH8NAAIHAAQJWAx+EADvAAAHAAQJWAx+EADvAAAuAAQKf0MAAgcACQm3GBoDABICAAcACQm3GBoDABICAAAA.Vannder:BAAALgAECgMJBgABLgAECgkJHwATABcgAA==.Varygud:BAAALgADCgUJBgAAAA==.Vayper:BAACLgAFFH8dAAIHAAUJIBg+DQAaAQAHAAUJIBg+DQAaAQAuAAQKf1EAAwcACQm5I8kCADkDAAcACQm5I8kCADkDAAgAAQmBBC2GACYAAAAA.',
Ve='Veins:BAAALgAECgMJAwAAAA==.Verdict:BAACLgAFFH8IAAIJAAMJnBMjMwCkAAAJAAMJnBMjMwCkAAAuAAQKfxYAAgkACQkCF98oAMUBAAkACQkCF98oAMUBAAAA.',
Vo='Voklin:BAAALgAECgQJBAAAAA==.',
['Vë']='Vënöm:BAAALgAECgcJBwABLgAECgkJIQAcAJsZAA==.',
We='Weemsy:BAABLgAECn87AAILAAkJfiTlAwAoAwALAAkJfiTlAwAoAwAAAA==.Wellmet:BAAALgAECgYJCAAAAA==.',
Wh='Whispyerwild:BAAALgAFFAEJAQAAAA==.',
Wi='Wildfire:BAACLgAFFH9AAAINAAkJVyGBAADEAgANAAkJVyGBAADEAgAuAAQKfzsAAg0ACQntJlsAAIgDAA0ACQntJlsAAIgDAAAA.Wildfirë:BAAALgAECgYJBgABLgAFFAkJQAANAFchAA==.Wildpriest:BAABLgAFFH8GAAIHAAYJKhCqCgBJAQAHAAYJKhCqCgBJAQABLgAFFAkJQAANAFchAA==.Willthewise:BAAALgADCgIJAgAAAA==.',
Wo='Wolffei:BAAALgAECgEJAQAAAA==.Wolfhammer:BAABLgAECn84AAIQAAkJvyLsAgAPAwAQAAkJvyLsAgAPAwAAAA==.Wolfhammur:BAAALgAECgYJBwAAAA==.Wolflee:BAAALgAECgYJDwAAAA==.Wolfmend:BAABLgAECn8WAAMXAAYJhhvMQgCGAQAXAAYJhhvMQgCGAQACAAEJ1gKTpgAaAAAAAA==.',
Wr='Wreckadin:BAAALgAECgEJAQAAAA==.',
Xa='Xamid:BAAALgAECgYJEAAAAA==.Xanariel:BAAALgAECgYJCgAAAA==.Xaxfen:BAACLgAFFH8dAAIQAAgJLBhVCQCdAQAQAAgJLBhVCQCdAQAuAAQKfycABBAACQmWIdcJAHoCABAACAnjItcJAHoCAAsABgkcFY9UAPoAAAoAAQkAANiPAAAAAAAA.',
Xy='Xylem:BAAALgAECgEJAgAAAA==.',
['Xê']='Xêndâr:BAAALgADCgQJBAAAAA==.',
Yo='Yogurt:BAAALgAECgIJAgAAAA==.',
Za='Zappieboy:BAAALgAECgcJDQAAAA==.',
Ze='Zeuree:BAABLgAFFH8GAAITAAIJWxGlTAB0AAATAAIJWxGlTAB0AAABLgAFFAMJCgAIALcKAA==.Zeurie:BAABLgAFFH8KAAIIAAMJtwpINQC2AAAIAAMJtwpINQC2AAAAAA==.',
Zo='Zod:BAABLgAECn8XAAIdAAgJtRZyAgDaAQAdAAgJtRZyAgDaAQAAAA==.',
Zu='Zugszy:BAAALgAECgQJBAAAAA==.Zulgrimm:BAAALgADCgMJAwAAAA==.',
Zy='Zyfèr:BAABLgAECn8UAAIXAAcJYhFsRgB2AQAXAAcJYhFsRgB2AQAAAA==.',
['Zî']='Zîmìk:BAAALgAECgQJBgAAAA==.',
['Às']='Àsh:BAACLgAFFH8YAAIGAAUJMRxlCAA5AQAGAAUJMRxlCAA5AQAuAAQKfzoAAgYACQnqIlsDAFoDAAYACQnqIlsDAFoDAAAA.',
['Év']='Évangeline:BAAALgAECgcJDAABLgAECgkJSgAGAOQZAA==.',
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
