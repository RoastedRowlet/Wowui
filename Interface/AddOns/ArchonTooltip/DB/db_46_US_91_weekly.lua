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

local lookup = {'Paladin-Retribution','Druid-Balance','Hunter-BeastMastery','Unknown-Unknown','Shaman-Restoration','Priest-Discipline','Priest-Shadow','Priest-Holy','Paladin-Holy','Warrior-Arms','Warrior-Fury','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Unholy','Warlock-Demonology','Warrior-Protection','Druid-Guardian','DeathKnight-Blood','Monk-Brewmaster','Monk-Windwalker','Mage-Frost','Monk-Mistweaver','Druid-Restoration','Druid-Feral','Warlock-Affliction','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Devourer','Rogue-Assassination','Rogue-Subtlety','Evoker-Preservation','Evoker-Augmentation','Paladin-Protection','Warlock-Destruction','Evoker-Devastation','Rogue-Outlaw','DeathKnight-Frost',}
local provider = {region='US',realm='Executus',name='US',type='weekly',zone=46,date='2026-07-05',data={Ac='Acai:BAAALgAECgYJBgAAAA==.',
Ad='Adolyn:BAAALgADCgkJCQAAAA==.Adventis:BAAALgADCgQJAwAAAA==.',
Al='Allavus:BAAALgADCgQJBQABLgAFFAYJFwABAN0aAA==.Alodiar:BAAALgAECgMJBQAAAA==.',
Am='Amrin:BAAALgAECgkJCQAAAA==.',
An='Andderson:BAAALgAECgEJAgAAAA==.Andersen:BAABLgAECn8kAAIBAAgJEB8dLwBEAgABAAgJEB8dLwBEAgAAAA==.Ando:BAAALgAECgEJAQABLgAECgkJLQACAG8ZAA==.Andryu:BAACLgAFFH8WAAICAAQJegtwDQDgAAACAAQJegtwDQDgAAAuAAQKf0UAAgIACQm7HB8KALMCAAIACQm7HB8KALMCAAAA.Anebel:BAAALgADCgkJCQAAAA==.Angelmuerte:BAAALgADCgkJDgAAAA==.Angyal:BAAALgAECgYJBwAAAA==.Annikya:BAAALgAECgcJBQABLgAECgkJHgADANIGAA==.',
Ap='Apolion:BAAALgADCgYJBgAAAA==.',
Aq='Aquastar:BAAALgAECgEJAQAAAA==.',
Ar='Archerius:BAAALgADCgcJCwAAAA==.Ardre:BAAALgADCgEJAQABLgAECgMJBQAEAAAAAA==.Ariis:BAAALgAECgQJBAAAAA==.Arkanis:BAABLgAECn80AAIFAAkJ3RwHGQCCAgAFAAkJ3RwHGQCCAgAAAA==.Arïel:BAABLgAECn8sAAQGAAkJqxkDDACvAgAGAAkJpxkDDACvAgAHAAMJSQy+cQBeAAAIAAEJfRvzZwBFAAAAAA==.',
Az='Azalya:BAAALgAECgQJBAAAAA==.',
Ba='Backstabath:BAAALgAECgkJDgABLgAFFAkJCQADADYAAA==.Banidor:BAAALgAECgIJAgABLgAFFAQJBAAEAAAAAA==.',
Be='Becka:BAAALgADCgEJAQAAAA==.',
Bh='Bhrown:BAAALgAECggJCwAAAA==.',
Bi='Bibleo:BAAALgADCgEJAQAAAA==.Bishop:BAABLgAECn8nAAMBAAgJjBIrYwCqAQABAAgJjBIrYwCqAQAJAAUJcw4nBgDyAAAAAA==.',
Bl='Bloodlyn:BAAALgADCgUJBQAAAA==.Blueming:BAAALgAECgMJBQAAAA==.',
Bo='Bonsai:BAABLgAECn8WAAMKAAYJFAirRwCsAAALAAYJAwZIZgDDAAAKAAYJnwarRwCsAAAAAA==.',
Br='Broadfang:BAACLgAFFH8rAAMDAAkJIRwFAwBtAQADAAYJOx0FAwBtAQAMAAcJrBNZDwA4AQAuAAQKfyQABAMACQlPJZ0cAFoCAAwABwliIpAYAGcCAAMABgnHJJ0cAFoCAA0ABAlWDjciAMMAAAAA.Broconis:BAAALgAECgUJBwABLgAFFAcJAwAEAAAAAA==.',
Bu='Bubbleoseven:BAABLgAECn8VAAIBAAYJGhkzDgAMAQABAAYJGhkzDgAMAQAAAA==.Bullorly:BAACLgAFFH8jAAIOAAcJWR+3KQDCAQAOAAcJWR+3KQDCAQAuAAQKfyEAAg4ACQnqJF8KABwDAA4ACQnqJF8KABwDAAAA.Bullwînkle:BAAALgADCgcJBwABLgAECgkJGgAPAD8FAA==.Bungulators:BAEALgAFFAEJAQABLgAFFAMJBwAQANAJAA==.Busuu:BAABLgAFFH8FAAIRAAMJ/BvDBgD0AAARAAMJ/BvDBgD0AAABLgAFFAkJNQASAL8hAA==.',
Ca='Capriestsunn:BAAALgAECgUJDQAAAA==.Casey:BAAALgAECgEJAQAAAA==.Catirus:BAAALgAECgEJAQAAAA==.',
Ch='Chunt:BAAALgAECgEJAQAAAA==.',
Cl='Clickshot:BAACLgAFFH8ZAAIDAAQJHiRmGgCdAQADAAQJHiRmGgCdAQAuAAQKf0wAAwMACQk/JlcCAGwDAAMACQk/JlcCAGwDAAwABAkEEv1ZANwAAAAA.Clipe:BAAALgAECgcJCwAAAA==.Clipee:BAAALgAECgkJEgAAAA==.Clipeskeg:BAABLgAECn8jAAMTAAkJQhzPDgBNAgATAAkJQhzPDgBNAgAUAAEJFwuzlQA6AAAAAA==.Clipex:BAAALgAECgkJEAAAAA==.',
Co='Connor:BAAALgAFFAEJAQAAAA==.Contagium:BAAALgAECgQJCgAAAA==.',
Cr='Crunchberry:BAABLgAFFH8NAAIVAAUJxBH+HQAiAQAVAAUJxBH+HQAiAQAAAA==.Cryptus:BAAALgADCgMJAQABLgAECggJHwAWABcgAA==.',
Cy='Cynicboom:BAAALgADCgQJBAAAAA==.Cynîc:BAAALgAECggJCgAAAA==.',
['Cø']='Cønståntine:BAAALgAECgEJAQAAAA==.',
Da='Daddynature:BAAALgAECgUJDQAAAA==.Daddyÿ:BAAALgAECgYJBgAAAA==.Darenas:BAABLgAECn8oAAMHAAkJlxgEFwAuAgAHAAkJlxgEFwAuAgAGAAEJpA1hfgAtAAAAAA==.Darkspyro:BAAALgADCgEJAQAAAA==.Dasu:BAABLgAECn82AAQXAAkJjw+AOwCmAQAXAAkJjw+AOwCmAQACAAYJNAhwTwDPAAAYAAMJUQKiLgBSAAAAAA==.David:BAAALgADCgcJDwABLgAFFAQJCQANAHsZAA==.',
De='Deathbooze:BAACLgAFFH8WAAIOAAUJ/CCoOwCCAQAOAAUJ/CCoOwCCAQAuAAQKfywAAg4ACQl2IcYWAL4CAA4ACQl2IcYWAL4CAAAA.Deathmikee:BAACLgAFFH8MAAMSAAQJpxeoGQAaAQASAAQJkReoGQAaAQAOAAMJnBBKoQDTAAAuAAQKf0IAAg4ACQkEIqcKABoDAA4ACQkEIqcKABoDAAAA.Delita:BAAALgAECgEJAQAAAA==.Demonea:BAAALgAECgEJAQAAAA==.Demonrush:BAAALgAECgEJAQABLgAFFAIJBQAZAFgLAA==.Deyst:BAAALgADCgkJCQABLgAECgEJAQAEAAAAAA==.',
Di='Dimethaline:BAAALgADCgcJBwAAAA==.Dinlek:BAAALgAECgkJDwAAAA==.Dinosoars:BAAALgADCgEJAQAAAA==.',
Dk='Dkmountain:BAABLgAECn8fAAIHAAcJGyFPEwBaAgAHAAcJGyFPEwBaAgAAAA==.',
Dr='Draknol:BAABLgAECn8iAAINAAkJwwjZAQCMAQANAAkJwwjZAQCMAQAAAA==.Drakos:BAABLgAECn8gAAMPAAkJNwnDBgBCAQAPAAkJNwnDBgBCAQAZAAkJ0gPRFgARAQAAAA==.Drunknfist:BAAALgAECgYJBwAAAA==.',
Du='Durton:BAACLgAFFH8RAAILAAQJmRwcFwBYAQALAAQJmRwcFwBYAQAuAAQKfykAAgsACQnQHzkYAIoCAAsACQnQHzkYAIoCAAAA.',
Ec='Echidna:BAABLgAFFH8GAAIDAAMJ+xWkZQDaAAADAAMJ+xWkZQDaAAABLgAFFAcJHQAaAJwdAA==.Echø:BAAALgAFFAEJAQAAAA==.',
Ed='Edison:BAACLgAFFH8TAAILAAQJoiGwEACBAQALAAQJoiGwEACBAQAuAAQKfzsAAwsACQnGIQcCAOEBAAsACQnGIQcCAOEBAAoAAwmAGzxHAK0AAAAA.Edrency:BAAALgADCgYJBgAAAA==.',
Ef='Eferis:BAAALgAECgkJDwAAAA==.',
El='Elder:BAAALgAECgYJBgAAAA==.Elderdorje:BAACLgAFFH8TAAIWAAQJfBH8FgDGAAAWAAQJfBH8FgDGAAAuAAQKfzAAAxYACQlMHbUTAH4CABYACQlMHbUTAH4CABQAAQnuAf6JACQAAAAA.Elesa:BAAALgADCgEJAQAAAA==.Elixe:BAAALgADCgEJAQAAAA==.Elondre:BAABLgAECn9WAAMFAAkJVCaxAADZAwAFAAkJVCaxAADZAwAaAAEJ/wbApQAyAAAAAA==.',
Em='Emomorf:BAABLgAECn8YAAIbAAcJRxAvLwAMAQAbAAcJRxAvLwAMAQAAAA==.Employee:BAACLgAFFH8eAAILAAcJtx0TAwDGAQALAAcJtx0TAwDGAQAuAAQKfyIAAwsACQmvJVYBALsDAAsACQmvJVYBALsDABAAAwmCGvoxALUAAAAA.',
Es='Estias:BAAALgAECgcJEQAAAA==.',
Ev='Evangeliné:BAABLgAECn8XAAIBAAYJygYrAwG0AAABAAYJygYrAwG0AAABLgAECgkJSgAIAOQZAA==.',
Ex='Exavier:BAAALgADCgQJBAAAAA==.Execfive:BAAALgAECgEJAQAAAA==.',
Fe='Femboi:BAABLgAECn8UAAIcAAgJFxFXUgCPAQAcAAgJFxFXUgCPAQABLgAECggJFgAUADYcAA==.',
Fi='Fistsofseno:BAAALgAECgkJCgAAAA==.Fizzenator:BAACLgAFFH8JAAINAAMJBh8pGgAAAQANAAMJBh8pGgAAAQAuAAQKfyoAAg0ACQlfHLYJAIMCAA0ACQlfHLYJAIMCAAAA.',
Fr='Freshlight:BAAALgAECgYJBgABLgAFFAYJFAAWAPYbAA==.',
Fw='Fweeb:BAAALgAECgMJAwAAAA==.',
Ga='Galak:BAAALgAECgEJAQABLgAFFAYJFwABAN0aAA==.Galatea:BAACLgAFFH8XAAIBAAYJ3RoQHgCQAQABAAYJ3RoQHgCQAQAuAAQKfyoAAgEACQmbIr0NAPcCAAEACQmbIr0NAPcCAAAA.Galifen:BAACLgAFFH8WAAICAAQJZSXJBQCMAQACAAQJZSXJBQCMAQAuAAQKf1AAAgIACQl9JmoAAJADAAIACQl9JmoAAJADAAAA.Gank:BAABLgAFFH8NAAMdAAQJxxmNAQD5AAAdAAMJcx+NAQD5AAAeAAEJxAiCHgBMAAAAAA==.Gargyll:BAAALgADCgUJBQAAAA==.Garysparks:BAAALgAECgEJAgAAAA==.',
Ge='Gelidon:BAABLgAECn8yAAMfAAkJshlhCgA7AgAfAAkJshlhCgA7AgAgAAgJZQzfNQBZAQAAAA==.Getoutalive:BAAALgADCgEJAQAAAA==.',
Gh='Ghreen:BAABLgAECn8aAAIUAAkJER01DgBkAgAUAAkJER01DgBkAgAAAA==.',
Gi='Gilgahmesh:BAABLgAECn82AAMhAAkJWgyDAwAOAQAhAAkJWgyDAwAOAQABAAEJaQN3WAEmAAABLgAFFAQJBwAOACwCAA==.',
Gn='Gnomegrown:BAABLgAECn84AAICAAgJZxibGgD2AQACAAgJZxibGgD2AQAAAA==.',
Go='Goy:BAAALgAFFAIJAwAAAA==.',
Gr='Gragehorn:BAAALgAECgEJAQAAAA==.Grapejuice:BAAALgAECgEJAQAAAA==.Gruvi:BAAALgAECgEJAQAAAA==.',
Gu='Gumbusta:BAAALgAECgcJDwAAAA==.Gummiie:BAAALgADCgEJAQAAAA==.Gunrunner:BAAALgADCgcJBwAAAA==.',
Ha='Halestorm:BAAALgADCgYJBgAAAA==.Halyer:BAABLgAECn8fAAMfAAkJuA6+EwCOAQAfAAgJvA6+EwCOAQAgAAYJMAUYagCdAAAAAA==.Hamalainen:BAAALgAECgUJAwABLgAFFAYJFAAWAPYbAA==.Hankthesnake:BAAALgADCgcJGwABLgAECgMJAwAEAAAAAA==.',
He='Helioboops:BAAALgAECgQJBAAAAA==.Hexdaman:BAAALgAECgMJBQAAAA==.',
Hi='Highcurious:BAAALgAECgYJBwABLgAFFAYJFAAWAPYbAA==.',
Ho='Hobbz:BAACLgAFFH8rAAIBAAcJlxnHAwC2AQABAAcJlxnHAwC2AQAuAAQKfy8AAgEACQm2JB0HAF8DAAEACQm2JB0HAF8DAAAA.Hodge:BAAALgADCgMJAwAAAA==.Hoid:BAAALgADCgkJCgAAAA==.Holyfans:BAAALgAFFAQJBAAAAA==.',
['Hó']='Hólythunder:BAAALgAECgIJAgAAAA==.',
Il='Illandros:BAABLgAECn8yAAIHAAkJ+hWiAQAAAgAHAAkJ+hWiAQAAAgAAAA==.Illidankmeme:BAAALgADCgIJAgAAAA==.',
In='Infernogirl:BAAALgAECgcJDgAAAA==.Ingredient:BAABLgAECn8oAAIYAAkJzxMfDAD3AQAYAAkJzxMfDAD3AQAAAA==.Inspire:BAACLgAFFH8WAAMXAAgJNh38AwADAgAXAAgJNh38AwADAgACAAMJHQZ3NwCgAAAuAAQKfxUAAhcACAn3HDAjAC8CABcACAn3HDAjAC8CAAAA.',
Is='Isinia:BAABLgAECn8aAAIPAAkJPwWshgAsAQAPAAkJPwWshgAsAQAAAA==.',
Ja='Janitor:BAAALgADCgMJAgAAAA==.Jayas:BAABLgAECn8fAAIWAAgJFyCACwDgAgAWAAgJFyCACwDgAgAAAA==.Jayim:BAABLgAFFH8GAAIXAAMJvAGfVgBtAAAXAAMJvAGfVgBtAAAAAA==.Jaína:BAABLgAECn8aAAIVAAgJ/gtagwBxAQAVAAgJ/gtagwBxAQABLgAECggJKQABAEMdAA==.',
Jc='Jcvd:BAAALgADCgQJBAABLgAFFAYJFAAWAPYbAA==.',
Je='Jencks:BAAALgAECgUJCQABLgAECgkJLQACAG8ZAA==.',
Ji='Jiren:BAACLgAFFH8UAAIWAAYJ9hvwBAAcAgAWAAYJ9hvwBAAcAgAuAAQKfz4AAxYACQmMIiMHAC4DABYACQmMIiMHAC4DABQAAwkTEERwAHAAAAAA.',
Jo='Johnson:BAABLgAECn8rAAIQAAkJyhvwBwB+AgAQAAkJyhvwBwB+AgAAAA==.Johnsunwell:BAAALgADCgQJAwAAAA==.Joran:BAABLgAECn9DAAIBAAkJHxeaBQC2AQABAAkJHxeaBQC2AQAAAA==.Jormungandr:BAAALgAFFAIJAgABLgAFFAYJFAAWAPYbAA==.',
Ju='Juckbolas:BAAALgAECgQJBAAAAA==.Juicyjj:BAABLgAECn8ZAAIOAAgJCw3QlAA+AQAOAAgJCw3QlAA+AQAAAA==.Jukesnaxx:BAAALgAECgMJBQAAAA==.',
['Jë']='Jësûs:BAAALgAECgEJAQAAAA==.',
Ka='Kaije:BAAALgADCgMJAwAAAA==.',
Ke='Kelekii:BAAALgADCgIJAgAAAA==.',
Ki='Killnoobs:BAAALgADCgEJAQAAAA==.',
Kr='Kravoxx:BAAALgADCgUJCQABLgAFFAQJBAAEAAAAAA==.Kro:BAABLgAECn8wAAIBAAkJWhctBQDGAQABAAkJWhctBQDGAQAAAA==.Krysess:BAAALgADCgEJAQAAAA==.Krèios:BAAALgAECgcJCAABLgAFFAUJEgAcAB8OAA==.',
La='Laenea:BAAALgAECgkJCQAAAA==.',
Le='Leanea:BAAALgAECgQJBAAAAA==.Lenayuh:BAAALgAECgYJCwAAAA==.',
Li='Lich:BAAALgAFFAQJAgAAAA==.Liera:BAABLgAECn8sAAIOAAkJxRjrJwBiAgAOAAkJxRjrJwBiAgAAAA==.',
Ll='Lloydlei:BAABLgAECn8yAAQPAAkJBh0kHgBwAgAPAAkJdxwkHgBwAgAZAAQJ5hUOFgAZAQAiAAMJEhd4JgCBAAAAAA==.',
Lo='Lodin:BAAALgAECgcJBwABLgAFFAUJEAAeANQHAA==.',
Lu='Luminå:BAABLgAECn8gAAIiAAkJZhgpDAB8AQAiAAkJZhgpDAB8AQAAAA==.',
Ly='Lylenn:BAAALgAECgYJBgAAAA==.',
Ma='Madora:BAAALgADCgQJBAAAAA==.Maibisan:BAABLgAECn9ZAAMbAAkJLSYLAQBzAwAbAAkJLSYLAQBzAwAcAAkJTiWyAwBMAwAAAA==.Malificent:BAABLgAECn8dAAIPAAcJ7R36PQDkAQAPAAcJ7R36PQDkAQAAAA==.Malighn:BAACLgAFFH8HAAIOAAQJLAJ2pwDNAAAOAAQJLAJ2pwDNAAAuAAQKfzEAAg4ACQlSCZBrAI4BAA4ACQlSCZBrAI4BAAAA.Masseffex:BAABLgAECn8VAAMCAAgJzRRCIQC+AQACAAgJzRRCIQC+AQAXAAIJAw/LowBpAAAAAA==.',
Mc='Mcshooty:BAAALgAECgYJDAAAAA==.',
Mi='Miziry:BAAALgAECgYJBgAAAA==.',
Mo='Modi:BAAALgAECgEJAQAAAA==.Monawah:BAAALgAECgEJAQAAAA==.Mookong:BAAALgADCgEJAQAAAA==.Moonsliver:BAAALgAECgEJBAAAAA==.Mordecâi:BAAALgAECgEJAQAAAA==.Morf:BAAALgAECgMJAwABLgAECgkJMgAfALIZAA==.Morganä:BAAALgAECgQJDgAAAA==.Morthrin:BAABLgAECn8VAAIXAAkJ5hS1JwATAgAXAAkJ5hS1JwATAgAAAA==.',
Mu='Muhrieyuh:BAAALgADCgQJBAAAAA==.',
My='Mysticdibs:BAAALgAECgEJAQAAAA==.Mystwolf:BAABLgAECn9EAAIFAAkJxh2dBACpAQAFAAkJxh2dBACpAQAAAA==.',
Ne='Ned:BAAALgAECgcJCAABLgAECggJDwAEAAAAAA==.Negora:BAAALgAECgEJAQAAAA==.Nelaris:BAAALgADCgEJAQAAAA==.',
Ni='Niccelndime:BAABLgAECn8VAAINAAYJ5Bt7IgCJAQANAAYJ5Bt7IgCJAQAAAA==.Nightember:BAABLgAECn8iAAQfAAkJHxFgEADGAQAfAAgJoRFgEADGAQAgAAkJjQ+3IgDFAQAjAAEJgAmYJwAuAAABLgAFFAQJEwAWAHwRAA==.Nightski:BAABLgAECn8qAAIXAAkJgBfzIABAAgAXAAkJgBfzIABAAgAAAA==.Nikolatesla:BAAALgAECgcJDgAAAA==.Nizzari:BAACLgAFFH8QAAIeAAUJ1AcIIgAVAQAeAAUJ1AcIIgAVAQAuAAQKf1UABB4ACQkyHZsHAK8CAB4ACQkyHZsHAK8CAB0AAgkdCgEfAGYAACQAAQmUB44nACcAAAAA.',
No='Nomas:BAAALgAECgYJBgAAAA==.Nothalyer:BAABLgAECn80AAIfAAkJ+g4uEgCmAQAfAAkJ+g4uEgCmAQAAAA==.',
Of='Offline:BAABLgAECn8XAAIXAAgJziHCDAD4AgAXAAgJziHCDAD4AgABLgAFFAkJCQADADYAAA==.',
Oh='Ohms:BAACLgAFFH8IAAIVAAMJcgdtjwC5AAAVAAMJcgdtjwC5AAAuAAQKfzcAAhUACQmeGu41AEECABUACQmeGu41AEECAAAA.',
Ol='Olaria:BAAALgADCgYJGQAAAA==.',
Or='Orwasithim:BAABLgAECn8UAAMlAAYJcRAYAwD4AAAlAAUJUA8YAwD4AAAOAAQJRg2xGACZAAABLgAECggJIQALAJsTAA==.Orwasitme:BAAALgAECggJDgABLgAECggJIQALAJsTAA==.Orwasitshrek:BAABLgAECn8hAAMLAAgJmxP5LACeAQALAAgJmxP5LACeAQAKAAEJ0AmSgAApAAAAAA==.Orwasitwrekt:BAAALgADCgkJCgABLgAECggJIQALAJsTAA==.',
Pa='Palabop:BAAALgAECgYJEQAAAA==.Paladinii:BAAALgAFFAEJAQAAAA==.',
Pj='Pjxyo:BAAALgAECgUJBQAAAA==.',
Pl='Planec:BAAALgAECgYJBgAAAA==.',
Po='Polytots:BAACLgAFFH8QAAMFAAcJVAVaNgAJAQAFAAYJzAJaNgAJAQAaAAYJmAraKwDlAAAuAAQKfzIAAwUACQlRERxDAKEBAAUACAlSEhxDAKEBABoACQlUE/gxAHUBAAAA.',
Pr='Proteus:BAAALgADCgMJAwAAAA==.',
Qi='Qiller:BAAALgAECggJDwAAAA==.',
Qu='Quinne:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.',
Ra='Ranin:BAABLgAECn8bAAIbAAkJiRdBDQBRAgAbAAkJiRdBDQBRAgAAAA==.Razius:BAAALgAECgkJEgAAAA==.',
Ri='Ricklepick:BAABLgAECn8aAAMXAAYJDBXzRgB0AQAXAAYJDBXzRgB0AQACAAEJ0wkqlAArAAABLgAFFAYJFAAWAPYbAA==.Riplordfire:BAAALgAECgEJAQAAAA==.',
Ro='Roadsign:BAAALgAECgYJEAAAAA==.Rottey:BAAALgAECgMJAwAAAA==.Roxette:BAAALgADCgcJBwAAAA==.',
Ry='Ryzenther:BAAALgAECgcJEwAAAA==.',
Sa='Salvation:BAAALgAECgkJEgAAAA==.Sanctis:BAAALgAECgYJCQAAAA==.Santan:BAAALgADCgIJAgAAAA==.Sarcoblaze:BAAALgAECgUJBQAAAA==.Satrat:BAAALgAFFAEJAQAAAA==.',
Sc='Scarecrow:BAAALgAECgEJAgAAAA==.Scathclipe:BAAALgAECgEJAQAAAA==.',
Se='Sealgair:BAAALgAECgEJBgAAAA==.Senovourer:BAABLgAECn8fAAIcAAkJjCEJCwAqAwAcAAkJjCEJCwAqAwAAAA==.',
Sh='Shabamoo:BAABLgAECn9AAAMXAAkJsyAVBgBXAwAXAAkJsyAVBgBXAwAYAAEJggcxWQApAAAAAA==.Shakkes:BAAALgAECgEJAQAAAA==.Shasato:BAACLgAFFH8YAAIRAAQJrh81AwBcAQARAAQJrh81AwBcAQAuAAQKf00ABBEACAlCJFsBAO8BABEACAlCJFsBAO8BABgAAQlyGDcLAEgAAAIAAQmSCpgVAC0AAAAA.Shazrast:BAAALgAECgUJBAAAAA==.Shelian:BAAALgAECgEJAQAAAA==.Shiranai:BAAALgAECgEJAQAAAA==.Shoosty:BAAALgADCgcJDAAAAA==.',
Si='Sicarii:BAAALgADCgcJCAAAAA==.Sindora:BAAALgADCgYJBgAAAA==.Sizouze:BAABLgAECn80AAIIAAkJuAsXBgD5AAAIAAkJuAsXBgD5AAAAAA==.',
Sk='Skeeter:BAAALgAFFAQJBAABLgAFFAQJBgAPALoIAA==.Sklonda:BAAALgADCgYJBgAAAA==.Skyepic:BAACLgAFFH8sAAMJAAkJNR+RAAD3AgAJAAkJNR+RAAD3AgABAAMJMwLKoQB8AAAuAAQKfy8AAwkACQnrIt8GAB4DAAkACQnrIt8GAB4DAAEABAllEn7VAOAAAAAA.Skylight:BAAALgAECgEJAQAAAA==.',
Sn='Sneakfu:BAAALgAECgEJAQAAAA==.Snugwalnut:BAACLgAFFH8gAAIFAAgJrh6CCwAZAgAFAAgJrh6CCwAZAgAuAAQKfzcAAgUACAlHI0UOAOICAAUACAlHI0UOAOICAAAA.',
So='Soejoedi:BAABLgAECn8tAAICAAkJbxnREQBKAgACAAkJbxnREQBKAgAAAA==.',
Sp='Spicyburrito:BAABLgAECn8XAAMCAAkJ/gVJCADAAAACAAkJ/gVJCADAAAAXAAEJfQHSAgELAAAAAA==.',
St='Stitchzpls:BAAALgAECgcJDAAAAA==.',
Su='Sunhammer:BAAALgAECgEJAQAAAA==.Sunsworn:BAAALgAECgQJBwAAAA==.',
Sw='Sweetyboi:BAAALgAECgYJDwAAAA==.',
Sy='Sythar:BAAALgAECgEJAQAAAA==.',
Ta='Taintedrush:BAACLgAFFH8FAAIZAAIJWAsFBgCNAAAZAAIJWAsFBgCNAAAuAAQKfxgAAhkACAmVG78AAOABABkACAmVG78AAOABAAAA.Tarhostamir:BAABLgAECn8dAAICAAcJVxD+NABEAQACAAcJVxD+NABEAQAAAA==.Taurup:BAAALgAECgcJEAABLgAFFAUJEAAeANQHAA==.Tazz:BAABLgAECn8eAAIDAAgJ0gaBiAAtAQADAAgJ0gaBiAAtAQAAAA==.',
Te='Tecnine:BAAALgADCgUJBQAAAA==.Teledar:BAAALgAECgQJCAAAAA==.',
Th='Thaluus:BAAALgADCgYJDQAAAA==.Thaysinga:BAABLgAFFH8FAAIOAAMJCQULxACiAAAOAAMJCQULxACiAAAAAA==.Thelandlord:BAACLgAFFH8UAAIfAAYJahVpBQChAQAfAAYJahVpBQChAQAuAAQKfxwAAx8ACAkOG9oMAGgCAB8ACAkOG9oMAGgCACMAAwnJDqIvAJoAAAAA.Theshape:BAAALgADCgMJAwAAAA==.Thunderblast:BAABLgAECn8jAAILAAgJ5SRpCADZAgALAAgJ5SRpCADZAgAAAA==.Thuss:BAABLgAECn8pAAIcAAkJgxo+HABqAgAcAAkJgxo+HABqAgAAAA==.',
Ti='Titgunniz:BAAALgADCgYJCQAAAA==.',
Tr='Treadstone:BAAALgAECgUJCQABLgAFFAYJFAAWAPYbAA==.',
Tu='Tugnutz:BAAALgAECgUJDQAAAA==.Tuk:BAAALgAECgQJBAAAAA==.',
Tw='Twirlywhirly:BAAALgAECgcJEgAAAA==.',
['Tè']='Tèmpos:BAAALgAECgMJAwAAAA==.',
Ul='Ulansiola:BAAALgAECgMJAwAAAA==.',
Un='Unplug:BAAALgAECgUJDQAAAA==.',
Va='Vaelus:BAAALgADCgcJCgAAAA==.Valkyrrie:BAAALgAECgQJBAABLgAECgkJHwAfALgOAA==.Vandder:BAAALgADCgYJBQAAAA==.Vander:BAAALgAECgQJBAABLgAECggJHwAWABcgAA==.Vanderre:BAAALgAECgIJAgABLgAECggJHwAWABcgAA==.Vanidossa:BAACLgAFFH8HAAIHAAMJCwmQDQC+AAAHAAMJCwmQDQC+AAAuAAQKfzoAAgcACQkuFnQUACoCAAcACQkuFnQUACoCAAAA.Vannder:BAAALgAECgMJAwAAAA==.Varygud:BAAALgADCgUJBgAAAA==.Vayper:BAACLgAFFH8SAAIHAAQJMhFeCQAHAQAHAAQJMhFeCQAHAQAuAAQKf1EAAwcACQm5I8kCADkDAAcACQm5I8kCADkDAAYAAQmBBC2GACYAAAAA.',
Ve='Veins:BAAALgAECgEJAQAAAA==.Verdict:BAACLgAFFH8IAAIJAAMJnBMjMwCkAAAJAAMJnBMjMwCkAAAuAAQKfxYAAgkACQkCF98oAMUBAAkACQkCF98oAMUBAAAA.',
Vo='Voklin:BAAALgAECgQJBAAAAA==.',
We='Weemsy:BAABLgAECn87AAILAAkJfiTlAwAoAwALAAkJfiTlAwAoAwAAAA==.',
Wh='Whispyerwild:BAAALgAFFAEJAQAAAA==.',
Wi='Wildfire:BAACLgAFFH8rAAINAAgJNiDdAADqAQANAAgJNiDdAADqAQAuAAQKfzsAAg0ACQntJlsAAIgDAA0ACQntJlsAAIgDAAAA.Wildfirë:BAAALgAECgYJBgABLgAFFAgJKwANADYgAA==.Willthewise:BAAALgADCgIJAgAAAA==.',
Wo='Wolffei:BAAALgAECgEJAQAAAA==.Wolfhammer:BAABLgAECn84AAIQAAkJvyLsAgAPAwAQAAkJvyLsAgAPAwAAAA==.Wolfhammur:BAAALgAECgYJBgAAAA==.Wolflee:BAAALgAECgYJDwAAAA==.Wolfmend:BAABLgAECn8WAAMXAAYJhhvMQgCGAQAXAAYJhhvMQgCGAQACAAEJ1gKTpgAaAAAAAA==.',
Wr='Wreckadin:BAAALgAECgEJAQAAAA==.',
Xa='Xamid:BAAALgAECgYJEAAAAA==.Xanariel:BAAALgAECgYJBgAAAA==.Xaxfen:BAACLgAFFH8bAAIQAAgJHBhVCQCdAQAQAAgJHBhVCQCdAQAuAAQKfyYABBAACAnjItcJAHoCABAACAnjItcJAHoCAAsABQlEFI9UAPoAAAoAAQkAANiPAAAAAAAA.',
['Xê']='Xêndâr:BAAALgADCgQJBAAAAA==.',
Yo='Yogurt:BAAALgAECgIJAgAAAA==.',
Za='Zappieboy:BAAALgAECgcJDQAAAA==.',
Ze='Zeuree:BAABLgAFFH8GAAIWAAIJWxGlTAB0AAAWAAIJWxGlTAB0AAABLgAFFAMJCgAGALcKAA==.Zeurie:BAABLgAFFH8KAAIGAAMJtwpINQC2AAAGAAMJtwpINQC2AAAAAA==.',
Zo='Zod:BAAALgAECgEJAQAAAA==.',
Zu='Zugszy:BAAALgAECgQJBAAAAA==.Zulgrimm:BAAALgADCgMJAwAAAA==.',
Zy='Zyfèr:BAABLgAECn8UAAIXAAcJYhFsRgB2AQAXAAcJYhFsRgB2AQAAAA==.',
['Zî']='Zîmìk:BAAALgAECgQJBgAAAA==.',
['Às']='Àsh:BAACLgAFFH8QAAIIAAQJqBsCEQBIAQAIAAQJqBsCEQBIAQAuAAQKfzoAAggACQnqIlsDAFoDAAgACQnqIlsDAFoDAAAA.',
['Év']='Évangeline:BAAALgAECgcJDAABLgAECgkJSgAIAOQZAA==.',
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
