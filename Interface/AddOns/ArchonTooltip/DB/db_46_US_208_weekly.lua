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

local lookup = {'Druid-Feral','Druid-Guardian','Druid-Restoration','Unknown-Unknown','Warrior-Fury','DemonHunter-Devourer','Evoker-Augmentation','DemonHunter-Havoc','Evoker-Preservation','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Mage-Frost','Monk-Brewmaster','Warlock-Demonology','Warrior-Arms','Warrior-Protection','DemonHunter-Vengeance','Hunter-Marksmanship','Warlock-Destruction','Paladin-Protection','Priest-Discipline','Priest-Holy','Paladin-Holy','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Affliction','Evoker-Devastation','Shaman-Enhancement','Mage-Fire','Monk-Windwalker','Druid-Balance','Monk-Mistweaver','Priest-Shadow','Rogue-Subtlety','DeathKnight-Frost','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aaerion:BAAALgAECgYJEAAAAA==.',
Ab='Abfale:BAAALgADCgYJCQAAAA==.Abhoth:BAAALgAECgEJAQAAAA==.Abor:BAABLgAECn8bAAQBAAYJOxLtEwAcAQABAAYJghHtEwAcAQACAAYJUgtcJwCZAAADAAEJJQf12gAnAAAAAA==.',
Ad='Adammonroe:BAAALgADCgEJAQAAAA==.Adampembe:BAAALgAECgYJBgAAAA==.Aduna:BAAALgAECgMJBQAAAA==.',
Ae='Aegla:BAAALgAFFAMJBAAAAA==.Aelendor:BAAALgADCgIJAgAAAA==.Aero:BAAALgAECgEJAgAAAA==.Aerosualt:BAAALgAECgYJDQAAAA==.Aethelbane:BAAALgADCgUJBQAAAA==.Aeyte:BAAALgADCgEJAQAAAA==.',
Ag='Again:BAAALgAECgEJAQABLgAECgUJBQAEAAAAAA==.Aginah:BAAALgADCgYJBgABLgAECgUJCgAEAAAAAA==.Agüeybaná:BAAALgADCggJEQAAAA==.',
Ai='Airia:BAAALgAECgUJDwAAAA==.',
Ak='Akaushi:BAAALgAECgMJBQAAAA==.Akno:BAABLgAECn8UAAIFAAYJfhptLQBOAQAFAAYJfhptLQBOAQAAAA==.Akshun:BAAALgADCgEJAQABLgAECgYJFAAFAH4aAA==.',
Al='Alariel:BAABLgAECn8nAAIGAAkJmxgdIAAQAgAGAAkJmxgdIAAQAgABLgAFFAQJCAAHAE4VAA==.Albesuri:BAAALgAECgUJBQABLgAFFAcJFwAGAOsYAA==.Alcazar:BAABLgAECn8YAAMGAAYJZhsbQAB9AQAGAAYJZhsbQAB9AQAIAAEJAAAyWwAAAAAAAA==.Alcmeneinen:BAABLgAECn8YAAIJAAgJGwj8HwB+AQAJAAgJGwj8HwB+AQAAAA==.Alcolan:BAAALgADCgMJAwAAAA==.Alera:BAAALgADCgcJBwABLgAFFAgJGQAJAPoYAA==.Alliar:BAABLgAECn8nAAMKAAkJxBzuGAAwAgAKAAkJxBzuGAAwAgALAAIJLgnsZwBTAAAAAA==.Alsonottuckr:BAAALgADCgUJBQAAAA==.Altani:BAAALgADCgMJAwABLgAECgQJCwAEAAAAAA==.Altostratus:BAAALgADCgYJBgAAAA==.Alyra:BAAALgAECgcJCAABLgAFFAgJGQAJAPoYAA==.',
Am='Amalek:BAAALgADCgIJAgAAAA==.Amerha:BAAALgAFFAEJAQAAAA==.Amoguss:BAAALgADCgQJBAAAAA==.',
An='Anasterion:BAACLgAFFH8FAAIMAAIJcSOQRwDUAAAMAAIJcSOQRwDUAAAuAAQKfxwAAgwACAnQIWodAFQCAAwACAnQIWodAFQCAAEuAAUUAwkFAAcAYg8A.Ancalagðn:BAAALgAECgYJCwAAAA==.Angelshare:BAAALgAECgQJEwAAAA==.Ansley:BAAALgAECgIJAgAAAA==.Antius:BAAALgADCgcJBwAAAA==.Anubric:BAAALgAECgcJEAAAAA==.',
Ap='Apandapie:BAAALgADCgEJAQAAAA==.',
Ar='Araylon:BAAALgADCgMJAwAAAA==.Arctus:BAAALgADCgUJBQAAAA==.Arkisha:BAAALgADCgUJBQAAAA==.',
As='Ashl:BAAALgADCgYJBgAAAA==.Ashlairan:BAAALgAECgUJDAAAAA==.Ashr:BAAALgADCgcJBwAAAA==.Ashárya:BAAALgAECgMJBgAAAA==.Astiri:BAACLgAFFH8TAAINAAQJ5B17KwBeAQANAAQJ5B17KwBeAQAuAAQKfyoAAg0ACAkUIvAlANsCAA0ACAkUIvAlANsCAAAA.',
At='Atlasdark:BAABLgAECn8bAAILAAkJbBUBFAD5AQALAAkJbBUBFAD5AQABLgAECgEJAQAEAAAAAA==.Atlasfallen:BAAALgAECgEJAQAAAA==.Atlasstout:BAAALgAECggJEwABLgAECgEJAQAEAAAAAA==.Atrell:BAABLgAECn8eAAIMAAkJrRhXLAAIAgAMAAkJrRhXLAAIAgAAAA==.',
Av='Avyanna:BAAALgADCgYJBgAAAA==.',
Az='Azuremelody:BAAALgADCgcJCAABLgAFFAQJDwAOAMYeAA==.',
Ba='Baddraggon:BAAALgAECgMJAwAAAA==.Badgress:BAAALgADCgkJCQAAAA==.Balrock:BAAALgADCgkJDQAAAA==.Balthromaw:BAABLgAECn8vAAIPAAgJSRtIJQANAgAPAAgJSRtIJQANAgAAAA==.Bangar:BAAALgAECgcJDgAAAA==.Bansol:BAAALgADCgEJAQAAAA==.Barron:BAABLgAECn8aAAIDAAYJGSJ7HAAbAgADAAYJGSJ7HAAbAgAAAA==.Bartahh:BAAALgAECgcJEAAAAA==.Bawonlakwa:BAAALgADCgIJAgAAAA==.',
Be='Beardmage:BAAALgAECgUJCQABLgAECgkJJgAFAPgcAA==.Beardwaffle:BAABLgAECn8mAAIFAAkJ+BwmDABjAgAFAAkJ+BwmDABjAgAAAA==.Bearlysota:BAAALgADCgMJAwABLgAECggJEwACACwjAA==.Beatstick:BAAALgADCgkJFAAAAA==.Belfdelphine:BAAALgAFFAEJAQAAAA==.',
Bi='Bifurthegrey:BAAALgAECgYJDQAAAA==.Bigbubba:BAACLgAFFH8HAAINAAMJ1wSZaAC5AAANAAMJ1wSZaAC5AAAuAAQKfxQAAg0ABwkyE8mJACsBAA0ABwkyE8mJACsBAAAA.Billandted:BAAALgAECgEJAQAAAA==.Biophage:BAACLgAFFH8NAAMFAAQJThwfEABBAQAFAAQJMhofEABBAQAQAAEJ/iMLHwBbAAAuAAQKfygABAUACAkFJC0UAKwCAAUACAlrIy0UAKwCABEAAwmQJEsYACwBABAABQnsGDobABcBAAAA.',
Bl='Bladesplicer:BAAALgAECgIJAwABLgAECggJHAAJAKkPAA==.Blaxdevoured:BAABLgAECn8XAAIGAAgJbBqIKgDYAQAGAAgJbBqIKgDYAQAAAA==.Blinkss:BAAALgAECgYJBgAAAA==.Bloodhoundss:BAABLgAECn8fAAIFAAgJ0xU1IwCNAQAFAAgJ0xU1IwCNAQAAAA==.Blössöm:BAABLgAECn8eAAISAAgJCBScCACUAQASAAgJCBScCACUAQAAAA==.',
Bo='Bob:BAACLgAFFH8RAAIGAAYJBxR4CQCTAQAGAAYJBxR4CQCTAQAuAAQKfyYAAgYACQk+IdoIAEIDAAYACQk+IdoIAEIDAAAA.Bofft:BAABLgAECn8iAAIKAAgJdRhxHQALAgAKAAgJdRhxHQALAgAAAA==.Boggtart:BAAALgAECgYJAQAAAA==.Bowna:BAAALgADCgUJBwAAAA==.Boyblue:BAAALgAECgUJDQAAAA==.',
Br='Braera:BAAALgAECgEJAQAAAA==.Brapbrap:BAAALgADCgYJBgAAAA==.Brawni:BAAALgAECggJEgAAAA==.Brewcow:BAAALgADCgYJBgAAAA==.Brttneyfears:BAAALgAECgIJAgAAAA==.Brunko:BAAALgAECgYJDQAAAA==.Bryan:BAABLgAECn8VAAIFAAgJ4gq2LgBIAQAFAAgJ4gq2LgBIAQAAAA==.Brând:BAAALgAECgUJBQAAAA==.Brâzzy:BAABLgAFFH8GAAITAAIJihyEFACoAAATAAIJihyEFACoAAAAAA==.',
Bu='Buffmeister:BAAALgAECgMJAwAAAA==.Buldur:BAAALgADCgIJAwAAAA==.Buu:BAAALgAFFAEJAQAAAA==.',
Ca='Cadh:BAAALgADCgMJAwAAAA==.Cadn:BAAALgADCgcJBwAAAA==.Caeror:BAAALgAECgQJBAAAAA==.Caliginosity:BAABLgAECn8YAAIUAAcJeRc2DAD/AQAUAAcJeRc2DAD/AQAAAA==.Calypsa:BAAALgADCgUJBQAAAA==.Canaduh:BAAALgAECgEJAQAAAA==.Carebear:BAAALgADCgEJAgAAAA==.',
Ce='Ceeya:BAAALgAECgEJAQAAAA==.Celeira:BAAALgAECgIJAgABLgAECgUJCgAEAAAAAA==.Cesard:BAABLgAECn8YAAICAAcJTxxqCgDZAQACAAcJTxxqCgDZAQAAAA==.',
Ch='Chadia:BAAALgADCgIJAgAAAA==.Chaladar:BAAALgAECgIJBQAAAA==.Chinner:BAAALgAECgMJAwAAAA==.Chrisbrewn:BAABLgAECn8rAAIFAAkJZB0JCwBxAgAFAAkJZB0JCwBxAgAAAA==.Chrondeezee:BAAALgAECgYJDAAAAA==.',
Ci='Ciradyl:BAAALgAECgEJAgAAAA==.Circledebull:BAAALgADCgIJAgAAAA==.',
Cl='Clamchowdér:BAAALgAFFAIJAgAAAA==.Clamsweat:BAAALgAECgMJAwAAAA==.Claypool:BAAALgADCgcJCAAAAA==.Cluedartsn:BAAALgAECgQJBAAAAA==.Clutchscope:BAAALgAECgQJCAAAAA==.',
Co='Cocoabutta:BAAALgAECgIJBQABLgAECgQJBQAEAAAAAA==.Coeurdeleon:BAACLgAFFH8IAAIVAAMJ5hMzBgDQAAAVAAMJ5hMzBgDQAAAuAAQKfxwAAhUACQm7GkwIAFUCABUACQm7GkwIAFUCAAAA.Condemnation:BAABLgAECn8zAAMWAAkJoxqCCgB2AgAWAAkJKhaCCgB2AgAXAAgJ4hb4GQAMAgAAAA==.Congressmen:BAAALgAECgQJBQAAAA==.Conquest:BAAALgAECgMJCQAAAA==.Coonter:BAAALgAECgkJAgAAAA==.Corban:BAAALgAECgMJAwAAAA==.Corebahn:BAAALgADCgUJBQABLgAECgMJAwAEAAAAAA==.Corebin:BAAALgADCggJGQABLgAECgMJAwAEAAAAAA==.Coriantumr:BAAALgAECgEJAgAAAA==.Corriius:BAABLgAECn8YAAIYAAkJ9wpZJgCLAQAYAAkJ9wpZJgCLAQAAAA==.',
Cr='Crayak:BAACLgAFFH8HAAIIAAIJbxycDACuAAAIAAIJbxycDACuAAAuAAQKfywAAwgACQk5IqcCAPUCAAgACQk5IqcCAPUCAAYABglvE2t+AC4BAAAA.Crooks:BAAALgADCgEJAQABLgAECgYJGAAGAGYbAA==.Crossbones:BAABLgAECn8cAAMZAAgJ6xJ/NwCuAQAZAAgJ6RJ/NwCuAQAaAAQJWA+VLADqAAAAAA==.',
Cu='Cudà:BAACLgAFFH8IAAIGAAUJEg4zNgACAQAGAAUJEg4zNgACAQAuAAQKfxMAAgYACAltGqUyAC8CAAYACAltGqUyAC8CAAAA.Curbside:BAABLgAECn8iAAILAAgJQxUpHgCcAQALAAgJQxUpHgCcAQAAAA==.Curbstomped:BAAALgAECgEJAQAAAA==.Curos:BAAALgADCgcJBwAAAA==.',
Cw='Cwellend:BAAALgADCgcJCgAAAA==.',
Cy='Cyllex:BAAALgAECgkJAQAAAA==.Cynwyse:BAAALgAECgIJAgAAAA==.',
Da='Daboozer:BAAALgADCgEJAQAAAA==.Daddymoist:BAAALgAECgYJDgAAAA==.Daemonium:BAAALgADCgcJDwAAAA==.Darkvizzy:BAACLgAFFH8GAAIbAAMJ2hHKaACdAAAbAAMJ2hHKaACdAAAuAAQKfyQAAxsACQkVIm8MANECABsACQkMIm8MANECABwABwkWGnUTANYBAAAA.Davinator:BAACLgAFFH8NAAIRAAQJWCQLBACmAQARAAQJWCQLBACmAQAuAAQKfy0ABBEACAndJG8DAMMCABEACAm1JG8DAMMCAAUABwlIHZUdAGICABAAAgnuFqQrAJcAAAAA.',
De='Deathcreed:BAAALgAECgEJAQAAAA==.Deathjek:BAAALgADCgUJBQAAAA==.Deezyqt:BAAALgAECgYJDQAAAA==.Delindvia:BAAALgADCgUJBAAAAA==.Delix:BAAALgAECgMJBAAAAA==.Demonatrixx:BAAALgAECgYJCgAAAA==.Denarian:BAAALgADCgYJCQABLgAECgcJGwAPAPATAA==.Derekmoniak:BAAALgAECgMJAwAAAA==.Derpah:BAACLgAFFH8MAAINAAQJERKEOwBCAQANAAQJERKEOwBCAQAuAAQKfykAAg0ACAleGjhGAMgBAA0ACAleGjhGAMgBAAAA.Deselle:BAABLgAECn8bAAINAAgJLgUgjwAhAQANAAgJLgUgjwAhAQAAAA==.Dethfox:BAAALgAECgEJAgAAAA==.Devolver:BAAALgAECgUJCQAAAA==.Devoured:BAAALgADCgMJAQAAAA==.Devoy:BAAALgADCgMJAwAAAA==.Dexifer:BAAALgAFFAIJBAAAAA==.Dezratel:BAAALgADCgEJAQAAAA==.',
Di='Diakaze:BAABLgAECn8gAAIDAAgJQBIYLQCsAQADAAgJQBIYLQCsAQAAAA==.Dimensional:BAAALgADCgMJAwAAAA==.Discipline:BAABLgAECn81AAIVAAkJ6BxcAwCWAgAVAAkJ6BxcAwCWAgAAAA==.Divinehugs:BAAALgADCgQJBAAAAA==.',
Do='Dolbyatmos:BAAALgADCgUJBQAAAA==.Donatelloh:BAAALgAECgYJEwAAAA==.Dortbraz:BAAALgAECgYJCAAAAA==.Dotmeharder:BAABLgAECn8bAAMPAAcJ8BOkegBnAQAPAAcJ8BOkegBnAQAdAAEJAABCJgBZAAAAAA==.Dotpocketz:BAAALgAECgQJCgAAAA==.',
Dr='Dragonass:BAAALgADCgQJBAAAAA==.Drakelayer:BAACLgAFFH8IAAIHAAMJNQ5IKgDXAAAHAAMJNQ5IKgDXAAAuAAQKfxcAAwcABgnpH+QbAKgBAAcABgnBH+QbAKgBAB4ABgnlHCgUAKQBAAAA.Drapo:BAAALgAECgMJAwAAAA==.Dratr:BAABLgAECn8YAAIfAAkJ7Q22CQC8AQAfAAkJ7Q22CQC8AQAAAA==.Draxyl:BAABLgAECn8xAAMbAAgJCReLTQCUAQAbAAgJCReLTQCUAQAcAAIJAwWKRwAjAAAAAA==.Dreadkrim:BAAALgADCgQJBAAAAA==.Drengus:BAAALgADCgQJBAAAAA==.Drham:BAABLgAECn8nAAMGAAkJpRCRPQCHAQAGAAkJpRCRPQCHAQASAAUJwwtGFgCoAAAAAA==.Drogbar:BAABLgAECn8WAAITAAgJXwgWEADnAAATAAgJXwgWEADnAAAAAA==.Dropshotta:BAAALgADCgcJBwAAAA==.Drstranger:BAABLgAECn8wAAMPAAkJcBAiMQDWAQAPAAkJcBAiMQDWAQAUAAMJNAYoUQB7AAAAAA==.Dryhtné:BAAALgADCgMJAwAAAA==.',
Du='Dunhambones:BAABLgAECn8kAAIbAAgJ+iCbGgBlAgAbAAgJ+iCbGgBlAgAAAA==.Duo:BAABLgAECn8hAAMgAAgJxhExBABbAQAgAAcJexExBABbAQANAAcJqQcdEAHdAAABLgAECgYJGwABADsSAA==.',
Eb='Ebontoes:BAABLgAECn8tAAMOAAkJ3CDHBQCrAgAOAAkJ3CDHBQCrAgAhAAIJ0gWFbgBXAAAAAA==.',
Eg='Eggchen:BAAALgADCgYJBgAAAA==.Eggtargaryen:BAABLgAECn8eAAIPAAcJCwQ/mQDNAAAPAAcJCwQ/mQDNAAAAAA==.',
Ei='Einjhell:BAAALgAECgYJDQAAAA==.',
El='Eladra:BAAALgAECgUJCgAAAA==.Eleidon:BAAALgAECgYJCQAAAA==.Eletricbollo:BAAALgAECgUJEgAAAA==.Eleveth:BAAALgADCgMJAwAAAA==.Elody:BAAALgAECggJDAAAAA==.Elowynn:BAABLgAECn8wAAMWAAkJ7A+oGgCjAQAWAAgJ8g2oGgCjAQAXAAkJqQtMMgB3AQAAAA==.Elèctra:BAABLgAECn8gAAMKAAgJqxfNHQAIAgAKAAgJqxfNHQAIAgALAAQJCw8cSAC8AAAAAA==.',
En='Enyô:BAABLgAECn8eAAINAAcJwxdQVQCcAQANAAcJwxdQVQCcAQAAAA==.',
Eo='Eorae:BAAALgAECgEJAgAAAA==.',
Ep='Epicsan:BAAALgAECgEJAQAAAA==.',
Er='Erada:BAAALgAECgcJEQAAAA==.',
Es='Esoss:BAAALgAECgMJBQAAAA==.',
Et='Etchelas:BAAALgADCgUJBQAAAA==.',
Ev='Evelise:BAAALgAECgQJBAABLgAFFAcJFwAGAOsYAA==.',
Ex='Exinquisitor:BAAALgAECgUJBQAAAA==.Exorcism:BAAALgAECgIJAgAAAA==.Expectpriest:BAAALgADCgcJCAAAAA==.',
Ez='Ezb:BAAALgAECgYJCQAAAA==.Ezith:BAAALgAECgMJBgABLgAECgYJGwABADsSAA==.',
Fa='Factt:BAAALgADCgkJCQAAAA==.Fardinhard:BAAALgAECgYJEQAAAA==.',
Fe='Felad:BAABLgAECn8hAAIhAAkJFiaaAABxAwAhAAkJFiaaAABxAwABLgAFFAQJCAAeANQeAA==.',
Fh='Fhalanx:BAAALgAECgUJDQAAAA==.',
Fi='Fib:BAAALgAECgEJAQAAAA==.Fijiman:BAAALgAECgMJAwABLgAECgcJFwAiACoSAA==.Firzen:BAAALgAECgYJEAAAAA==.',
Fl='Flaid:BAAALgAFFAEJAQAAAA==.Flamingfists:BAAALgAECgUJBgABLgAECgcJGgAjAAohAA==.Flapfinnigan:BAAALgADCgMJAwABLgAECggJIAAPACsVAA==.Flapp:BAABLgAECn8gAAMPAAgJKxWlOQC1AQAPAAgJKxWlOQC1AQAUAAIJsQiDXABZAAAAAA==.Flarios:BAAALgAECgEJAwAAAA==.Flipynipps:BAAALgAECgYJDwAAAA==.Flowdinstuna:BAAALgAECgYJEQAAAA==.Flybusdriver:BAAALgADCgUJBQAAAA==.',
Fo='Fortitude:BAAALgADCgQJBAAAAA==.',
Fr='Framistina:BAABLgAECn8vAAIZAAkJ1BmRGABIAgAZAAkJ1BmRGABIAgAAAA==.Freehandes:BAAALgAECgEJAgAAAA==.Fridolf:BAAALgAECgUJCwAAAA==.Frierenpally:BAAALgAECgQJCQAAAA==.Frosttitute:BAAALgAECgIJAgAAAA==.Froza:BAAALgAECgQJEgAAAA==.Frozenwings:BAAALgAECgcJCwAAAA==.',
Fu='Furballboi:BAAALgADCgcJBwAAAA==.Furrybait:BAEALgAECgMJBgABLgAFFAQJBwAJANUPAA==.',
Ga='Gaiseric:BAAALgAECgYJCgAAAA==.Garrosh:BAAALgAECggJAwAAAA==.Garyuu:BAAALgAECgYJCwAAAA==.',
Ge='Georgian:BAABLgAECn8UAAMWAAcJTApfKAAxAQAWAAcJSQpfKAAxAQAXAAQJRQNmZACcAAAAAA==.Geraldene:BAABLgAECn8VAAIXAAgJMQrCJgBIAQAXAAgJMQrCJgBIAQAAAA==.Geraniho:BAAALgAECgEJAwAAAA==.',
Gh='Ghydra:BAAALgAECggJDwAAAA==.',
Gi='Girltank:BAAALgADCgQJBAAAAA==.Gishwrath:BAAALgAECgEJAQAAAA==.',
Go='Gotfleas:BAAALgADCgIJAgAAAA==.',
Gr='Grangran:BAAALgADCgcJBwAAAA==.Gremlinn:BAAALgADCgkJCQAAAA==.Grendaldh:BAABLgAECn8zAAIGAAkJ6RaxJAD2AQAGAAkJ6RaxJAD2AQAAAA==.Greyfax:BAAALgAECgYJDwAAAA==.Griftèr:BAAALgADCgIJAgABLgAECggJIQAVALYYAA==.Grimthruul:BAAALgAECggJCQAAAA==.Grommkar:BAABLgAECn8WAAIQAAcJsBRNEwByAQAQAAcJsBRNEwByAQAAAA==.Grumpig:BAAALgAECgUJCQAAAA==.',
Gu='Gunnulf:BAAALgAECgYJDgAAAA==.',
Ha='Halucination:BAABLgAECn8oAAMXAAkJ0xH0KQCjAQAXAAcJDRX0KQCjAQAkAAcJAhKSKgArAQAAAA==.Hamham:BAAALgAECgIJAgABLgAECgQJCwAEAAAAAA==.Hamsandwich:BAAALgADCgEJAQAAAA==.Hangtimesky:BAAALgAECgEJBgABLgAECgQJBQAEAAAAAA==.Hardwood:BAAALgADCgEJAQAAAA==.Harthan:BAAALgADCgIJAgAAAA==.Hayden:BAAALgADCgEJAQAAAA==.Hayleigh:BAAALgAECgIJAgAAAA==.',
He='Hetzák:BAABLgAECn8wAAIiAAkJAhGJGQCnAQAiAAkJAhGJGQCnAQAAAA==.',
Hi='Hightusk:BAAALgAECgYJEwAAAA==.Hinoo:BAAALgADCgkJCQAAAA==.Hintolisu:BAACLgAFFH8HAAIBAAIJphAZCgCoAAABAAIJphAZCgCoAAAuAAQKfzAAAgEACQniHFQDAJcCAAEACQniHFQDAJcCAAAA.Hiphopuler:BAABLgAECn8vAAIXAAcJrBygGwAAAgAXAAcJrBygGwAAAgAAAA==.',
Ho='Holybaloney:BAABLgAECn8aAAMMAAkJUB6eHwCuAgAMAAkJUB6eHwCuAgAVAAQJUxioIgDzAAAAAA==.Holycouw:BAAALgAECgEJAQAAAA==.Holycrit:BAAALgADCgkJCQAAAA==.Holyschmit:BAABLgAECn8jAAIYAAgJTRplEgA2AgAYAAgJTRplEgA2AgAAAA==.Horiblee:BAAALgADCgUJBQAAAA==.',
Hu='Huatarm:BAABLgAECn8wAAIRAAkJVhO4DADUAQARAAkJVhO4DADUAQAAAA==.Hucklebarry:BAABLgAECn8dAAITAAgJ1BnuBgCSAQATAAgJ1BnuBgCSAQAAAA==.Huntris:BAABLgAECn8aAAIaAAkJ6BlgDAAeAgAaAAkJ6BlgDAAeAgAAAA==.Hurdur:BAAALgAECgkJDwAAAA==.',
Hy='Hyala:BAAALgAECgEJAQAAAA==.Hypnotykk:BAAALgAECgYJEgAAAA==.',
Ia='Iadygaga:BAAALgAECggJCQAAAA==.',
Id='Idkwhtnm:BAAALgAECgQJCQAAAA==.',
Im='Immunè:BAAALgAECgEJAgAAAA==.Imrah:BAABLgAECn8kAAQhAAgJERTAGwCCAQAhAAcJWxbAGwCCAQAOAAMJ2QalVgBwAAAjAAEJqANLegAgAAAAAA==.',
In='Innuendowo:BAAALgAECgcJCAAAAA==.',
Ir='Irollu:BAAALgAECgMJBQAAAA==.Ironsheik:BAAALgADCgEJAQAAAA==.',
Is='Isisankh:BAAALgAECgQJBAAAAA==.',
It='Ittáchi:BAAALgAECgYJCwAAAA==.',
Ja='Jardina:BAAALgAECgIJAgAAAA==.',
Je='Jen:BAACLgAFFH8GAAIXAAIJyhTuGwCDAAAXAAIJyhTuGwCDAAAuAAQKfy8AAhcACQldG/IHAKgCABcACQldG/IHAKgCAAAA.',
Jh='Jhakrii:BAAALgAECgUJCgAAAA==.Jhek:BAAALgADCgMJAwAAAA==.',
Jo='Jo:BAABLgAECn8iAAIlAAgJNRg+FwCLAQAlAAgJNRg+FwCLAQAAAA==.Jocon:BAABLgAECn8cAAIPAAgJGAVheQAMAQAPAAgJGAVheQAMAQAAAA==.',
Ju='Jumpyjune:BAAALgAECgcJCAAAAA==.Justjohnn:BAAALgAECgIJAQAAAA==.Juulz:BAAALgAECgYJBgAAAA==.',
Ka='Kamo:BAAALgAECgQJCQABLgAFFAQJDQAaAA0OAA==.Kanami:BAABLgAECn8hAAIFAAgJqhu5FAABAgAFAAgJqhu5FAABAgAAAA==.Kaori:BAABLgAECn8UAAIMAAgJCAg/sgAfAQAMAAgJCAg/sgAfAQAAAA==.Karamazov:BAABLgAECn8cAAICAAkJDRmwBwAYAgACAAkJDRmwBwAYAgAAAA==.Karloch:BAAALgADCgQJBAAAAA==.Kayle:BAAALgAECgMJAwAAAA==.Kaylex:BAAALgADCgUJDQAAAA==.Kaynyx:BAABLgAECn8wAAIlAAkJcB3QBgB6AgAlAAkJcB3QBgB6AgAAAA==.',
Ke='Keathalan:BAAALgADCgcJBwAAAA==.Kedrik:BAACLgAFFH8IAAIMAAMJswgIRQDeAAAMAAMJswgIRQDeAAAuAAQKfy8AAwwACAlpGFM/AMIBAAwACAk7F1M/AMIBABUABgn5GXgPAHUBAAAA.Keedron:BAACLgAFFH8XAAIGAAcJ6xiUBgANAgAGAAcJ6xiUBgANAgAuAAQKfxsAAgYACAlJJIkLACUDAAYACAlJJIkLACUDAAAA.Keiden:BAABLgAECn8fAAIbAAgJpRMpUwCFAQAbAAgJpRMpUwCFAQAAAA==.Kellace:BAAALgAECgQJBgAAAA==.Kelpcake:BAAALgAECgUJCAAAAA==.Kerb:BAABLgAECn8kAAMbAAgJwxviMwDqAQAbAAgJwxviMwDqAQAmAAMJEgnqGwBeAAAAAA==.',
Ki='Kickstuff:BAAALgAECgUJBQAAAA==.Kilfogg:BAABLgAECn8XAAILAAcJoxfmKwC5AQALAAcJoxfmKwC5AQAAAA==.Killinflak:BAAALgAECggJDgAAAA==.Kimosabi:BAAALgAECgcJDAAAAA==.Kirìn:BAAALgAECgQJBAAAAA==.Kissyboots:BAAALgAECgkJEgAAAA==.Kitsurubami:BAAALgAECgQJCwAAAA==.Kiyo:BAACLgAFFH8FAAMHAAMJYg8/OACKAAAHAAIJOgo/OACKAAAJAAIJCw7SGwB6AAAuAAQKfycABAkACQlKGCoJABACAAkACQlKGCoJABACAAcABgk3ECQ1AAcBAB4AAQmRBb9AAC8AAAAA.',
Km='Kmillz:BAAALgAECggJEQAAAA==.',
Ko='Koinpurse:BAAALgAECgYJCgAAAA==.Koinpúrse:BAAALgAECgEJAQAAAA==.Kommuna:BAAALgAECgcJAQAAAA==.Konjur:BAACLgAFFH8VAAINAAYJ2CL5BgDwAQANAAYJ2CL5BgDwAQAuAAQKfxcAAg0ACAm6IwgVACoDAA0ACAm6IwgVACoDAAAA.Koo:BAAALgADCgUJBgAAAA==.Korban:BAAALgADCgYJCwABLgAECgMJAwAEAAAAAA==.Kotonano:BAABLgAECn8UAAIiAAgJKR5oJgDKAQAiAAgJKR5oJgDKAQABLgAECggJHAAMAJAhAA==.',
Kr='Krangler:BAAALgAECgEJAQAAAA==.Krelock:BAACLgAFFH8FAAIPAAMJ2AM7XwC5AAAPAAMJ2AM7XwC5AAAuAAQKfxYAAg8ABwlgFFZSANABAA8ABwlgFFZSANABAAAA.Krymzendeath:BAAALgAECgUJBQABLgAFFAMJCQARAJcZAA==.Krísztina:BAABLgAECn8aAAMUAAgJpwlaDgAOAQAUAAgJpwlaDgAOAQAPAAYJGgLP2gCkAAAAAA==.',
Ku='Kuenybby:BAAALgAECgcJCAABLgAFFAcJFwAGAOsYAA==.Kulikov:BAAALgADCgYJCgABLgAECgQJCwAEAAAAAA==.Kuya:BAAALgAECgYJEwAAAA==.',
Ky='Kyrokenn:BAAALgAECgkJAgAAAA==.Kyuden:BAAALgAECgcJBQAAAA==.',
['Kå']='Kåmo:BAACLgAFFH8NAAIaAAQJDQ5HDABBAQAaAAQJDQ5HDABBAQAuAAQKfyMAAhoACQkmGOQHAHICABoACQkmGOQHAHICAAAA.',
['Kô']='Kôinpurce:BAAALgAECgEJAQAAAA==.',
La='Lakey:BAABLgAECn8VAAQWAAcJvSXXEgD2AQAWAAUJ6SLXEgD2AQAXAAcJvSXiGgCpAQAkAAMJOA73SgCuAAABLgAFFAQJEAADAM0UAA==.Lakeyy:BAACLgAFFH8QAAMDAAQJzRTFHAAaAQADAAQJzRTFHAAaAQAiAAQJMgzvFwAUAQAuAAQKfyEAAwMACAmlIhALAOkCAAMACAmlIhALAOkCACIABQn4GG89AD0BAAAA.Lanayrd:BAAALgAECgEJAQAAAA==.Lawrence:BAACLgAFFH8LAAMLAAQJbxB8FQAgAQALAAQJbxB8FQAgAQAKAAMJkwlyNACzAAAuAAQKfx0AAwsACAkKIcIKAOoCAAsACAkKIcIKAOoCAAoAAgncBOOaADcAAAAA.',
Le='Lebonk:BAAALgAECgEJAQAAAA==.',
Li='Liadran:BAAALgADCgYJCQAAAA==.Lighthon:BAAALgADCgEJAQAAAA==.Lilslaver:BAAALgAECgYJCgAAAA==.Liltyr:BAAALgADCgEJAQAAAA==.Lisex:BAACLgAFFH8bAAQbAAYJGxnUJgANAQAbAAUJiBjUJgANAQAmAAQJmwaXCADlAAAcAAEJAAAfGgA0AAAuAAQKfzEAAxsACQmiI/cWAPICABsACQmYI/cWAPICACYABwkiHW8EABQCAAAA.Lithe:BAAALgAECgQJBQABLgAFFAMJCQALAGMRAA==.',
Lo='Locklear:BAABLgAECn8iAAIMAAkJbBZuKQAUAgAMAAkJbBZuKQAUAgAAAA==.Logic:BAACLgAFFH8aAAINAAgJfRS4BABaAgANAAgJfRS4BABaAgAuAAQKfysAAg0ACQlvIykLAPECAA0ACQlvIykLAPECAAAA.Lolshield:BAAALgAECgYJBgABLgAFFAQJDwAOAMYeAA==.Lonelyphatty:BAAALgAECgcJBwAAAA==.Lorecan:BAABLgAECn8lAAIVAAgJiAobGgD0AAAVAAgJiAobGgD0AAAAAA==.Lotei:BAAALgADCgUJBQAAAA==.',
Lu='Luchenta:BAABLgAECn8YAAInAAcJfRYPBgCrAQAnAAcJfRYPBgCrAQAAAA==.Luminore:BAAALgADCgEJAQAAAA==.Lunaria:BAAALgAECgYJDAABLgAFFAQJEAADAM0UAA==.Luubitotems:BAAALgAECgcJDQAAAA==.',
Ly='Lyricx:BAAALgAECgUJBQAAAA==.Lyterbox:BAABLgAECn8XAAQiAAgJ2QiHOABWAQAiAAgJ2QiHOABWAQABAAYJJAW4HwDjAAACAAMJ6ARIKgBRAAABLgAFFAQJDAAbADoQAA==.',
Ma='Maani:BAAALgAECgYJBgAAAA==.Macediin:BAABLgAECn8jAAIbAAkJlhxaJAAuAgAbAAkJlhxaJAAuAgAAAA==.Macedin:BAAALgAECgIJAgAAAA==.Macthyr:BAAALgADCgEJAQAAAA==.Madderhunter:BAACLgAFFH8TAAIGAAYJBheDBADpAQAGAAYJBheDBADpAQAuAAQKfycAAgYACQkYIkEIAEgDAAYACQkYIkEIAEgDAAAA.Maddice:BAAALgAECgUJCAABLgAFFAYJEwAGAAYXAA==.Magegummy:BAAALgAFFAIJAgAAAA==.Magesterique:BAABLgAECn8uAAINAAkJbhVpQQDXAQANAAkJbhVpQQDXAQAAAA==.Magirzul:BAAALgAECgEJAQAAAA==.Magnok:BAAALgADCgkJCQAAAA==.Mahoutsukai:BAAALgADCgcJDAAAAA==.Makiel:BAABLgAECn8sAAIMAAkJ/R5LEgCbAgAMAAkJ/R5LEgCbAgAAAA==.Malgus:BAAALgAECgcJBwAAAA==.Malricfrost:BAAALgADCgEJAQAAAA==.Malthael:BAABLgAECn8wAAIbAAkJ3hxyFACNAgAbAAkJ3hxyFACNAgAAAA==.Mamageek:BAABLgAECn8XAAIKAAkJ9hHmKADsAQAKAAkJ9hHmKADsAQAAAA==.Mami:BAAALgAECgUJDAAAAA==.Marksterique:BAAALgADCggJEgABLgAECgkJLgANAG4VAA==.Massivemoos:BAAALgADCgMJAwAAAA==.Matsuri:BAABLgAECn8YAAIjAAcJWxdRIACxAQAjAAcJWxdRIACxAQAAAA==.Maxson:BAABLgAECn8fAAIMAAgJuRuvLgD+AQAMAAgJuRuvLgD+AQAAAA==.',
Mc='Mcdeath:BAAALgAECggJDwAAAA==.Mcversatile:BAABLgAECn8VAAICAAYJuxc4DwCIAQACAAYJuxc4DwCIAQABLgAECggJDwAEAAAAAA==.',
Me='Meatloaf:BAABLgAECn8rAAIXAAkJrBksEABkAgAXAAkJrBksEABkAgAAAA==.Meeko:BAACLgAFFH8QAAIJAAcJ7ho3BAC8AQAJAAcJ7ho3BAC8AQAuAAQKfycAAgkACQkZJh4AAO0DAAkACQkZJh4AAO0DAAAA.Mereoleona:BAAALgAECgMJAwAAAA==.Metalmagus:BAABLgAECn8gAAINAAgJZxjROwDrAQANAAgJZxjROwDrAQAAAA==.Metori:BAAALgAECgMJAwAAAA==.',
Mi='Millican:BAABLgAECn8VAAIfAAkJTCJIAgC7AgAfAAkJTCJIAgC7AgAAAA==.Minata:BAAALgAECgEJAQABLgAFFAcJFwAGAOsYAA==.Mindsurge:BAAALgADCgEJAQAAAA==.Misaka:BAAALgAECgYJCgAAAA==.Mishi:BAABLgAECn8kAAIOAAkJ/hJ4FgC6AQAOAAkJ/hJ4FgC6AQAAAA==.Misslobster:BAAALgAECgcJDQAAAA==.Mistweaver:BAAALgAFFAEJAQAAAA==.Mistygoblin:BAAALgAECgYJEQABLgAECggJIAAKAKsXAA==.Mithos:BAAALgAECgEJAQAAAA==.Mithreaum:BAAALgAECgEJAQAAAA==.',
Mo='Modi:BAAALgADCgYJBgAAAA==.Mokoko:BAACLgAFFH8IAAMHAAQJThVqEAD/AAAHAAQJThVqEAD/AAAeAAEJVQsfCgBTAAAuAAQKfy8AAwcACQkjHtEFACcDAAcACQkJHtEFACcDAB4ABwlFHWYLACUCAAAA.Mokomage:BAAALgAECgYJDwABLgAFFAQJCAAHAE4VAA==.Mommythang:BAAALgADCggJDwAAAA==.Monnik:BAAALgADCgUJBQAAAA==.Moomoo:BAABLgAECn8uAAQiAAkJKR31CAB9AgAiAAkJKR31CAB9AgADAAQJDxFhggDUAAACAAEJch1HNgBRAAAAAA==.Moomookiller:BAAALgADCgYJBgAAAA==.Moomoowho:BAAALgADCgIJAgAAAA==.Moonrivia:BAAALgADCgUJBQAAAA==.Moothai:BAABLgAECn8yAAMhAAkJbCO8BADRAgAhAAkJbCO8BADRAgAOAAYJ7hlpHwBvAQAAAA==.Moríko:BAAALgAECgQJAwAAAA==.Moz:BAAALgADCgIJAgAAAA==.',
My='Myka:BAAALgADCgkJCQABLgAECgYJBgAEAAAAAA==.',
['Mò']='Mòrtale:BAAALgADCgMJBAAAAA==.',
Na='Nadiamourn:BAAALgAECgIJAgABLgAFFAQJDwAOAMYeAA==.Nahmo:BAAALgAECgUJEwAAAA==.Nahwa:BAAALgADCgcJDAABLgAECgUJEwAEAAAAAA==.Nametaken:BAAALgAECgEJAQABLgAECgUJBQAEAAAAAA==.',
Ne='Necro:BAABLgAECn8mAAIbAAkJVBu9NADnAQAbAAkJVBu9NADnAQAAAA==.Necrota:BAABLgAECn8aAAMbAAgJlB4pLwD9AQAbAAgJFh4pLwD9AQAcAAEJXBuRQQBFAAABLgAFFAYJFQANANgiAA==.Neuron:BAACLgAFFH8VAAIDAAYJKh2tAQD6AQADAAYJKh2tAQD6AQAuAAQKfx8AAwMACAmAI/oOAMECAAMABwnlJPoOAMECACIAAQkAG4pzAFQAAAAA.',
Ni='Nickadeath:BAAALgAECgQJBQAAAA==.Nigdruu:BAABLgAECn8hAAIDAAkJ6RkmHABbAgADAAkJ6RkmHABbAgAAAA==.Nightsorrow:BAAALgAECgQJBAAAAA==.Nightvine:BAAALgADCgMJAwAAAA==.Ninakal:BAAALgADCgMJAwAAAA==.Ninjavc:BAABLgAECn8kAAIoAAgJ0wxNCACAAQAoAAgJ0wxNCACAAQAAAA==.',
No='Nodamaged:BAAALgAECgEJAgAAAA==.Nokona:BAAALgAECgMJBwAAAA==.Noora:BAAALgAECgIJBAAAAA==.Nosk:BAAALgAECgEJAQAAAA==.Nostradamuxs:BAAALgAECgEJAQAAAA==.Nota:BAAALgAECgUJBQAAAA==.',
Ol='Oldblood:BAAALgAECgcJDAAAAA==.Oldungeonguy:BAAALgADCgMJAwAAAA==.',
Or='Oralys:BAABLgAECn8fAAIYAAgJEiJECgCiAgAYAAgJEiJECgCiAgAAAA==.Oromis:BAAALgAECgcJEAAAAA==.Orthuuwu:BAAALgADCgkJGAAAAA==.Orömis:BAAALgADCgcJCAAAAA==.',
Oz='Ozarkian:BAAALgAECgYJBQAAAA==.',
Pa='Padanfain:BAAALgAECgYJEwAAAA==.Padle:BAAALgAECgYJDQAAAA==.Palacasaurio:BAAALgAECgYJDQAAAA==.Paladindude:BAAALgADCgEJAQAAAA==.Paladine:BAAALgADCgcJCgAAAA==.Paladín:BAABLgAECn8hAAIVAAgJthgLCwDCAQAVAAgJthgLCwDCAQAAAA==.Palugly:BAAALgAECgcJBwABLgAFFAQJBwASAM0UAA==.Panochaluvr:BAAALgADCgUJCQAAAA==.Papasheen:BAAALgADCgYJBgAAAA==.Papertowel:BAAALgADCgQJBAAAAA==.Pargonz:BAAALgAECgcJEgAAAA==.Patoko:BAABLgAECn8pAAIfAAkJXxm9CQC8AQAfAAkJXxm9CQC8AQAAAA==.Paxwet:BAAALgADCgcJFQAAAA==.Payn:BAACLgAFFH8IAAMeAAQJ1B7nAACJAQAeAAQJ1B7nAACJAQAHAAIJlBIUNACZAAAuAAQKfyUAAx4ACQnIJP4AANsCAB4ACAmeJP4AANsCAAcAAgmbHxBKAKwAAAAA.Paypay:BAABLgAECn81AAMDAAkJiiWKAADVAwADAAkJiiWKAADVAwAiAAYJIBBiMQD+AAAAAA==.',
Pe='Pepperknight:BAAALgAECgYJBgAAAA==.',
Ph='Pharoahlyfe:BAAALgAECgMJBAAAAA==.Philipx:BAAALgAECgIJAgAAAA==.',
Pi='Pif:BAAALgADCgEJAQAAAA==.Piglittle:BAABLgAECn8jAAMXAAcJbxkgFwDOAQAXAAcJbxkgFwDOAQAkAAQJYR3bNADyAAAAAA==.Pik:BAAALgADCgQJBQAAAA==.Pikur:BAAALgAECgEJAgABLgAECgUJBwAEAAAAAA==.',
Po='Polyrhythm:BAAALgAECgMJBgAAAA==.Porthub:BAAALgAECgQJBwAAAA==.',
Pr='Prideless:BAAALgAECgMJBQAAAA==.Priestoe:BAACLgAFFH8FAAIWAAMJlQjTIADJAAAWAAMJlQjTIADJAAAuAAQKfxoAAhYABgmVH8MTABACABYABgmVH8MTABACAAAA.Prrowl:BAAALgAECgQJCQAAAA==.',
Ra='Ragnur:BAAALgAECgQJDAAAAA==.Rakashi:BAAALgADCgcJBwAAAA==.Rareley:BAAALgADCgEJAQAAAA==.Rasberri:BAAALgAECgUJBgAAAA==.',
Re='Reenomander:BAAALgAECgEJAQAAAA==.Reginageørge:BAAALgADCgUJBQABLgAECgkJLAAMAP0eAA==.Revival:BAAALgAECgEJAQAAAA==.',
Rh='Rhaen:BAAALgAECgMJAwAAAA==.Rhuarc:BAAALgADCgcJBwAAAA==.',
Ri='Rileyreed:BAAALgAECgkJDQAAAA==.',
Ro='Roksolid:BAABLgAECn8ZAAILAAgJKhTDIACKAQALAAgJKhTDIACKAQAAAA==.Rollos:BAABLgAECn8ZAAIPAAgJPxROPwCiAQAPAAgJPxROPwCiAQAAAA==.Ronara:BAABLgAECn8eAAIjAAgJCBIRHQC2AQAjAAgJCBIRHQC2AQAAAA==.',
Rw='Rwk:BAAALgAFFAEJAQAAAA==.',
Ry='Ryujinsimp:BAACLgAFFH8bAAIHAAgJbSEJAQDSAgAHAAgJbSEJAQDSAgAuAAQKfyAAAgcACQm3JfAAAMwDAAcACQm3JfAAAMwDAAAA.',
['Rä']='Rävylock:BAAALgAECgkJEAAAAA==.',
['Rì']='Rìfter:BAAALgADCgEJAQABLgAECggJIQAVALYYAA==.',
Sa='Saamii:BAAALgADCggJCQABLgAECgYJFAAFAH4aAA==.Saelybricek:BAAALgAECgIJAgAAAA==.Saintnick:BAAALgAECgMJAwAAAA==.Samtarkras:BAABLgAECn8tAAIJAAkJqhoSBQCJAgAJAAkJqhoSBQCJAgAAAA==.Sanctimonius:BAAALgAECgcJDAAAAA==.Sandmann:BAAALgADCgcJBwAAAA==.Saràh:BAAALgADCgIJAgAAAA==.Saråh:BAAALgAECgEJAQAAAA==.Satori:BAAALgAECgEJAQAAAA==.Sawcyy:BAAALgAECgIJAwABLgAECgUJEwAEAAAAAA==.',
Sc='Scathog:BAAALgADCgEJAQAAAA==.Scoresby:BAAALgADCgUJCAAAAA==.',
Se='Seemeenott:BAAALgAECgQJBwAAAA==.Seer:BAACLgAFFH8FAAIdAAMJghGgAwDzAAAdAAMJghGgAwDzAAAuAAQKf0sAAx0ACQnRINwAAMkCAB0ACQnRINwAAMkCAA8ABglQGX1CAJcBAAAA.Selket:BAAALgAECgUJBwAAAA==.',
Sh='Shadowfawn:BAABLgAECn8jAAMkAAgJmxNmGQCpAQAkAAgJmxNmGQCpAQAXAAEJsALpiQAjAAAAAA==.Shadowzugger:BAACLgAFFH8FAAIkAAMJAAnDGQDMAAAkAAMJAAnDGQDMAAAuAAQKf2IAAiQACQnEJH0BAEsDACQACQnEJH0BAEsDAAEuAAUUBgkWAAsA+BoA.Shadowßeast:BAAALgADCgIJAgAAAA==.Shalatar:BAAALgADCgIJAgAAAA==.Shallos:BAAALgADCgMJAwAAAA==.Shamxie:BAAALgAECgEJAQAAAA==.Shamy:BAAALgAFFAEJAQAAAA==.Sharklord:BAABLgAECn8cAAIlAAgJwhfwJgDBAQAlAAgJwhfwJgDBAQAAAA==.Shiivera:BAAALgADCgYJBgAAAA==.Shimada:BAACLgAFFH8GAAIZAAQJSQu6LgACAQAZAAQJSQu6LgACAQAuAAQKfxsAAhkABgnsIXMyAMIBABkABgnsIXMyAMIBAAAA.Shinryujin:BAAALgADCgcJCwABLgAFFAgJGwAHAG0hAA==.Shodin:BAAALgADCgEJAQAAAA==.Shuyan:BAAALgADCgcJBwAAAA==.',
Si='Siilentdeath:BAAALgADCgEJAQAAAA==.Silence:BAAALgAECgEJAgAAAA==.Sindréa:BAAALgADCgIJAgAAAA==.',
Sk='Skarloc:BAAALgAECgYJEwAAAA==.Skyn:BAAALgAECgEJAgAAAA==.',
Sl='Slyde:BAABLgAECn8dAAIbAAgJuh8OKAAcAgAbAAgJuh8OKAAcAgAAAA==.',
Sm='Smalldk:BAACLgAFFH8WAAIbAAYJyBjFFwA3AQAbAAYJyBjFFwA3AQAuAAQKfyUAAhsACAnPIq8VAPoCABsACAnPIq8VAPoCAAAA.Smick:BAABLgAECn8bAAIYAAcJRBSPJQCRAQAYAAcJRBSPJQCRAQAAAA==.Smokermcpot:BAAALgAECgEJAQAAAA==.Smurs:BAAALgAECgQJBgAAAA==.',
Sn='Snackstand:BAAALgAECgYJCAAAAA==.Sneetz:BAAALgADCgcJBwAAAA==.',
So='Solvaring:BAAALgADCgUJBQAAAA==.Sonija:BAAALgAECgQJBQAAAA==.Sota:BAAALgAECgMJAwABLgAECggJEwACACwjAA==.Sotadruid:BAABLgAECn8TAAMCAAgJLCO+BgAxAgACAAcJNSG+BgAxAgAiAAYJvCNLIQDzAQAAAA==.Soularpower:BAAALgAECgQJAQAAAA==.Soulfang:BAABLgAECn81AAIFAAkJCiGxBQDMAgAFAAkJCiGxBQDMAgAAAA==.Soulfox:BAAALgAECgEJAgABLgAECggJIAAKAKsXAA==.',
Sp='Spacing:BAAALgAECgYJDAAAAA==.Speknawz:BAAALgAECgUJCgABLgAFFAQJCAAlAK0YAA==.Splagtooney:BAAALgAECgIJAgAAAA==.Spookmaster:BAAALgAECgcJCgAAAA==.Spoopum:BAAALgADCgEJAQAAAA==.',
Sq='Squidmonk:BAAALgAECgYJBgAAAA==.',
St='Stabwoundz:BAAALgADCgcJDQAAAA==.Stalwart:BAABLgAECn8aAAISAAgJLRAvCgBuAQASAAgJLRAvCgBuAQABLgAFFAMJBQAdAIIRAA==.Starfail:BAAALgADCgIJAgABLgAECgcJGgAjAAohAA==.Starfu:BAAALgADCggJGAAAAA==.Steaknurse:BAAALgADCgEJAQAAAA==.Stealthops:BAAALgAECggJEQAAAA==.Steampuff:BAAALgADCgYJBAAAAA==.Steven:BAACLgAFFH8SAAIhAAYJ6xzvAgCmAQAhAAYJ6xzvAgCmAQAuAAQKfxUAAiEACAlEH5kMALECACEACAlEH5kMALECAAAA.Stoic:BAAALgADCggJDwAAAA==.Stormscales:BAAALgADCgUJBQAAAA==.Stormshot:BAAALgADCgcJBwAAAA==.Stormsigil:BAAALgADCgEJAQAAAA==.Stormstyle:BAAALgAECgQJCQAAAA==.Straydog:BAABLgAECn8eAAIKAAkJ4h9kBAArAwAKAAkJ4h9kBAArAwAAAA==.Strongsad:BAAALgAECgYJDgAAAA==.Stumptavion:BAABLgAECn8vAAIbAAkJlhbRWQBzAQAbAAkJlhbRWQBzAQAAAA==.',
Su='Suddenshield:BAAALgADCgkJCgAAAA==.Suddenshift:BAAALgADCgIJAgABLgADCgkJCgAEAAAAAA==.Suddensmash:BAAALgADCgUJBQABLgADCgkJCgAEAAAAAA==.Sumdingjuan:BAAALgAECgcJCwAAAA==.Superpowers:BAABLgAECn8VAAIOAAgJZB4lCgBZAgAOAAgJZB4lCgBZAgAAAA==.Supersaiyan:BAAALgAECgYJCwAAAA==.Surtur:BAABLgAECn86AAIQAAkJBh/4AgC+AgAQAAkJBh/4AgC+AgAAAA==.Sus:BAAALgAFFAEJAQAAAA==.Suzel:BAAALgAECgUJEwAAAA==.',
Sw='Swoof:BAAALgAECggJEQABLgAFFAQJDAAbADoQAA==.',
Sy='Sy:BAAALgAECgQJBAAAAA==.Sycario:BAAALgAECgEJAQAAAA==.Sygismund:BAABLgAECn8jAAIIAAgJ4w4ZFwBnAQAIAAgJ4w4ZFwBnAQAAAA==.Synndershock:BAAALgAECgUJCgABLgAFFAQJDAAWAD8OAA==.Synwise:BAABLgAECn8sAAIDAAkJBB+VBgAaAwADAAkJBB+VBgAaAwAAAA==.Sysecond:BAAALgAECgEJAQABLgAECgQJBAAEAAAAAA==.',
Ta='Tagbone:BAACLgAFFH8HAAIZAAIJ7RgpRgCoAAAZAAIJ7RgpRgCoAAAuAAQKfzAAAxkACQmyG1kYAEkCABkACQmyG1kYAEkCABMAAQkiAl6aABkAAAAA.Taotien:BAABLgAECn8bAAIhAAgJCRnTGAAcAgAhAAgJCRnTGAAcAgAAAA==.Taowg:BAAALgAECgEJAQAAAA==.Tapmytatas:BAAALgADCgMJAwAAAA==.Tarionfrost:BAAALgADCgIJAgAAAA==.',
Tc='Tchaik:BAABLgAECn8kAAQXAAkJlhp4CgB1AgAXAAkJlhp4CgB1AgAWAAQJkQ3MPACsAAAkAAEJCg6gYAA1AAAAAA==.',
Th='Thanah:BAAALgADCggJCwAAAA==.Thantrax:BAAALgADCgUJAgAAAA==.Thaynes:BAACLgAFFH8IAAIbAAMJyga4dACNAAAbAAMJyga4dACNAAAuAAQKfyoAAxsACQktGPY6ANABABsACQktGPY6ANABACYAAQneCUEiADIAAAAA.Thayos:BAAALgAECgkJAwAAAA==.Thebadman:BAAALgADCgYJCAAAAA==.Thenightkinq:BAAALgAECgUJCwABLgAECggJDwAEAAAAAA==.Thesera:BAAALgADCgMJAwAAAA==.Theshockèr:BAAALgAECgIJAwAAAA==.Thirdlegkick:BAAALgAECgEJAQAAAA==.Thrasher:BAAALgADCgEJAQAAAA==.Threetesties:BAAALgAECgYJDwAAAA==.',
Ti='Tigerugly:BAACLgAFFH8HAAISAAQJzRS7AgAYAQASAAQJzRS7AgAYAQAuAAQKfzgAAhIACQnTHh4CAKYCABIACQnTHh4CAKYCAAAA.Tinytea:BAACLgAFFH8HAAIOAAQJsyLbBwCcAQAOAAQJsyLbBwCcAQAuAAQKfz0AAg4ACQkkJFMBAD4DAA4ACQkkJFMBAD4DAAAA.',
To='Tocarryuaway:BAAALgAECgUJCQAAAA==.Togami:BAAALgADCgYJBgAAAA==.Togepi:BAAALgAECgUJDAAAAA==.Tolgar:BAAALgADCgQJBQAAAA==.Toli:BAACLgAFFH8KAAMYAAQJcx+tDwBmAQAYAAQJcx+tDwBmAQAMAAEJUQ1NdABMAAAuAAQKfygAAxgACQkYHeUVAGECABgACAkqH+UVAGECAAwABQneEFyFABsBAAAA.Totosapling:BAAALgADCgcJBwAAAA==.Totosplash:BAAALgADCgMJAwAAAA==.Totosquishy:BAAALgAECgMJAwAAAA==.Tototree:BAAALgAECgYJCQAAAA==.',
Tr='Tranos:BAAALgADCgcJCAAAAA==.Treshalth:BAAALgAECgEJAQAAAA==.Trock:BAAALgAECgkJAgAAAA==.Trollboi:BAAALgADCgcJCgAAAA==.Trusinner:BAABLgAECn8UAAMFAAYJ0SGHLQD9AQAFAAUJvSOHLQD9AQAQAAEJIxoHPgA8AAABLgAFFAQJCwAbAEQUAA==.Trééhugger:BAAALgAECgQJBAAAAA==.',
Ts='Tsunt:BAAALgAECgcJEAAAAA==.Tsusha:BAAALgADCgkJEAABLgAECgcJEAAEAAAAAA==.',
Tu='Tubbidan:BAAALgAECgUJDQABLgAECgcJBwAEAAAAAA==.Turkeyleg:BAAALgADCgYJBwAAAA==.',
Tw='Twiisty:BAABLgAECn8bAAIRAAgJXg4CFwA7AQARAAgJXg4CFwA7AQAAAA==.Twippy:BAAALgADCgYJBgABLgAECggJGwARAF4OAA==.',
Ty='Tyanis:BAAALgAECgUJDgABLgAECgYJDQAEAAAAAA==.Tyriam:BAABLgAECn8wAAMMAAkJ2hq+GABwAgAMAAgJ2hq+GABwAgAYAAgJ9BavLQDNAQAAAA==.',
Ul='Ultrajames:BAABLgAECn8nAAINAAgJihP6TwCrAQANAAgJihP6TwCrAQAAAA==.',
Un='Underwear:BAAALgAECgMJAwABLgAECgQJBwAEAAAAAA==.Ungrím:BAAALgAECgMJAgAAAA==.',
Va='Valentína:BAAALgADCgEJAQABLgADCgYJBgAEAAAAAA==.Vandy:BAABLgAECn8nAAMGAAkJLAr9ZwAFAQAIAAYJtwvaNwAmAQAGAAkJXAn9ZwAFAQAAAA==.Vathalandor:BAAALgADCgcJBwAAAA==.',
Ve='Velendris:BAAALgAECgEJAQAAAA==.Vellelock:BAAALgAECgEJAQAAAA==.Verlo:BAAALgADCgQJBAAAAA==.Veronique:BAACLgAFFH8NAAIeAAQJDA7/AgAzAQAeAAQJDA7/AgAzAQAuAAQKfx4AAh4ACAlhIEgEAMkCAB4ACAlhIEgEAMkCAAAA.Verso:BAABLgAECn8mAAInAAgJCRr0AwABAgAnAAgJCRr0AwABAgAAAA==.',
Vi='Viberaider:BAAALgAFFAEJAQAAAA==.Vikdruid:BAAALgAECgUJAwABLgAECgkJFQAfAEwiAA==.Vikindia:BAAALgAECgYJCwABLgAECgkJFQAfAEwiAA==.Vinushka:BAAALgAECgYJCwAAAA==.Virdanfrost:BAAALgADCgkJEQAAAA==.Vitalic:BAAALgADCgEJAQABLgAECggJIwAHAEMeAA==.Vitalithry:BAABLgAECn8jAAMHAAgJQx5/EAAbAgAHAAgJOR5/EAAbAgAeAAEJSh+2OABTAAAAAA==.Vivii:BAAALgADCgUJBQAAAA==.',
Vo='Voidcruiser:BAAALgAECgEJAQAAAA==.Voodootime:BAAALgAECgQJBQAAAA==.',
Vy='Vyndication:BAAALgAECgMJAwAAAA==.',
['Vì']='Vìv:BAAALgAECgEJAgABLgAECgkJLAAMAP0eAA==.',
Wa='Waiffelbur:BAAALgADCgcJDgAAAA==.Walterlight:BAAALgADCgMJAwAAAA==.Warchicken:BAAALgAECgMJAwAAAA==.Warham:BAAALgAECgQJCwAAAA==.',
We='Weituvoidy:BAAALgADCgMJAwAAAA==.Wetpax:BAABLgAECn8mAAIbAAgJbhVfRwCmAQAbAAgJbhVfRwCmAQAAAA==.',
Wh='Whatchawant:BAAALgAECgUJBQAAAA==.Whiskeybeer:BAABLgAECn8lAAQLAAgJ4h56DgA5AgALAAgJ4h56DgA5AgAKAAgJdhl+GAAzAgAfAAIJ7xFxJQA4AAAAAA==.Whyld:BAAALgAECgQJCgAAAA==.',
Wi='Wiiska:BAACLgAFFH8PAAIkAAYJBhcFBQCzAQAkAAYJBhcFBQCzAQAuAAQKfywAAyQACAntHC8OAKACACQACAntHC8OAKACABcAAQklJRBKAGcAAAAA.Windoelicker:BAAALgAECgUJDAAAAA==.Winsane:BAAALgAECgUJCwAAAA==.',
Wo='Wooftide:BAAALgAECgEJAQAAAA==.',
Wr='Wrecker:BAAALgAECggJDgAAAA==.',
Wu='Wuggles:BAACLgAFFH8LAAIDAAQJDg3xHwAJAQADAAQJDg3xHwAJAQAuAAQKfycAAwMACQlWG/UTAGcCAAMACQlWG/UTAGcCACIABAkcDdFVAM0AAAAA.Wulong:BAAALgADCgMJBAAAAA==.',
['Wï']='Wïshbe:BAAALgAECgEJAQAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.',
Xb='Xbalanque:BAABLgAECn8oAAMZAAkJ7xqXHwAcAgAZAAgJFxuXHwAcAgATAAgJbxbvJgDyAQAAAA==.',
Xu='Xu:BAACLgAFFH8LAAIbAAQJRBSvNAD3AAAbAAQJRBSvNAD3AAAuAAQKfx4AAxsACAnwHtcmACICABsACAnwHtcmACICACYAAQlgEI0iADEAAAAA.',
Ya='Yad:BAAALgADCgMJBAABLgADCgcJDgAEAAAAAA==.Yakiki:BAABLgAECn8UAAIjAAcJAhrvHgC9AQAjAAcJAhrvHgC9AQABLgAFFAgJJgAjAHobAA==.',
Ye='Yetil:BAABLgAECn8aAAIYAAgJ5Qj4MABFAQAYAAgJ5Qj4MABFAQAAAA==.Yey:BAABLgAECn8hAAQYAAkJjxmBEABMAgAYAAkJjxmBEABMAgAVAAMJJgHpNwA8AAAMAAEJDQSYTQEoAAAAAA==.',
Yo='Yoblown:BAAALgADCgQJBAAAAA==.Yourephired:BAAALgAECggJEQAAAA==.',
Yy='Yytusdelytus:BAAALgADCgEJAQAAAA==.',
Za='Zak:BAAALgAECgMJBQAAAA==.Zarana:BAAALgAECggJEgAAAA==.Zaycursed:BAAALgAFFAMJAwAAAA==.Zaydream:BAABLgAECn8VAAQCAAgJChtMBwAiAgACAAgJChtMBwAiAgAiAAQJmgupQAC1AAABAAIJpAddNwArAAABLgAFFAMJAwAEAAAAAA==.Zaydämon:BAABLgAECn8WAAIGAAgJ4B1IHwCWAgAGAAgJ4B1IHwCWAgABLgAFFAMJAwAEAAAAAA==.Zaymaster:BAAALgAECgEJAQAAAA==.',
Ze='Zenzuken:BAAALgAECgEJAQAAAA==.',
Zi='Zieva:BAAALgAECgEJAgABLgAECggJIgABAKwWAA==.Ziggybeast:BAABLgAECn8tAAQiAAkJViEGDwCvAgAiAAkJViEGDwCvAgADAAEJEyKTiQBiAAACAAMJeA1LNgBRAAAAAA==.Ziggybrute:BAAALgADCgEJAQABLgAECgkJLQAiAFYhAA==.Zignag:BAAALgAECgIJAgAAAA==.',
Zl='Zlackk:BAAALgAECgEJAQAAAA==.',
Zo='Zoinked:BAAALgADCgMJAwAAAA==.Zoldyck:BAABLgAECn86AAIbAAkJ5xx3IQA+AgAbAAkJ5xx3IQA+AgAAAA==.Zomny:BAAALgADCgEJAQAAAA==.Zophmonk:BAAALgAECgEJAgAAAA==.',
Zu='Zugmebalz:BAAALgAECgIJAQAAAA==.',
['Zå']='Zåythyr:BAAALgAECgYJDAABLgAFFAMJAwAEAAAAAA==.',
['Zø']='Zøphar:BAAALgADCgEJAQAAAA==.',
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
